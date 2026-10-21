-- The Mancouchbus, Heck on Earth's boss (docs/eternal-mood.md, "The bosses,
-- one a level"), the way Heck makes a Mancubus: a huge fat demon who sat
-- down in a recliner when the world ended and never got up again. Heck put
-- the recliner on tank treads and his arms into a pair of rocket launchers.
-- He sits in front of the starport's gate (the map's `horde.boss`, kind
-- "mancubus"), and nobody gets through it while he is up: the gate is
-- CLOSED (`serverLocked`) until he is down.
--
-- He waits until a player comes up the Boulevard (or shoots him), then
-- fights: rockets from both arms in turn at whoever he has, and every so
-- often a sweep of them, a fan from one side to the other with gaps to
-- slip through. Up close he lurches forward and bumps them away with his
-- belly. At two thirds and a third of his health he shouts for the lads and
-- Cacodaemons come in over the roofs (horde.lua's `serverCall`). He is slow
-- to turn on his treads, and his back is the recliner: rounds that land on
-- it do double (BACK). This module is the man, the wire and the lock; what
-- he does is his brain's (mancubus_brain.lua), how he looks is
-- mancubus_look.lua's. His rockets are the weapons feature's (a rocket
-- launcher of his own, ownerless, from the horde: they never hurt Heck).
--
-- Like every boss (bosses/init.lua) he has breath, scales with the humans
-- (his health, the Cacodaemons), has the boss bar, goes for medkits when
-- badly hurt, dodges abilities, and going down raises `serverKill` "boss"
-- and spills koins. He is Heck's: only players' rounds reach him. He also
-- drops the Mood Slayer's helmet, one each player can pick up, which
-- unlocks it in the shop (the gear feature's, with the reward screen).
--
-- Messages
--   server -> all  MC_STATE <tick> <x> <y> <facing> <hp> <max> <move> <aim> <phase2> <awake> <stamina> <winded>
--                  <arm>  (unreliable, 15 Hz; move 0 none, 1 arms up for a volley, 2 the volley, 3 arms up for a
--                  sweep, 4 the sweep, 5 leaning back for a bump; arm the launcher that fired last, -1 or 1;
--                  empty once he is gone)
--   server -> all  MC_SAY  <line>           he says Mancubus.lines[line]
--   server -> all  MC_BUMP <x> <y>          his belly came down there
--   server -> all  MC_SOUND <name>          whine (the launchers coming up)
--   server -> all  MC_DOWN <x> <y> <angle>  he went down: the gate opens (to a joiner too)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local WideNav = require("src.features.eternal-mood.wide_nav")
local Look = require("src.features.eternal-mood.mancubus_look")

local Mancubus = {}
Mancubus.__index = Mancubus

local Brain

-- Tuning --------------------------------------------------------------------

Mancubus.HEALTH = 3400 -- for one player (more humans, more: bosses/init.lua); the Floor Manager has 2250
Mancubus.RADIUS = 46 -- px: him and his recliner (mancubus_look.lua draws him)
Mancubus.DRIVE = 60 -- px/s on his treads, forwards...
Mancubus.REVERSE = 0.6 -- ...and this much of it backwards
Mancubus.STROLL = 30 -- px/s winded
Mancubus.TURN = 0.9 -- rad/s: slow to come round, so get behind him
Mancubus.BREATH = { drain = 8, regen = 12, recovered = 50, breath = 40 }
Mancubus.RANGE = 900 -- px he sees
Mancubus.KEEP = 380 -- px he keeps from whoever he has
Mancubus.DETOUR = 1.5 -- seconds he goes by the walking grid after catching on something on his way to you
Mancubus.BACK = 2 -- a round in his back (the recliner) does this much more
Mancubus.ARM = 44 -- px either side of his middle: the launchers...
Mancubus.MUZZLE = 52 -- ...and how far forward their ends are
Mancubus.VOLLEY_EVERY = { 2.6, 3.4 } -- seconds between attacks...
Mancubus.VOLLEY_EVERY_2 = { 1.8, 2.5 } -- ...in phase 2 (under half)
Mancubus.RAISE = 0.8 -- seconds the arms come up first (the tell, whining)
Mancubus.PAIRS = 3 -- a rocket from each arm, this many times (phase 2: one more)
Mancubus.ROCKET_EVERY = 0.28 -- seconds between rockets in a volley
Mancubus.VOLLEY_COST = 18 -- breath
Mancubus.SWEEP_CHANCE = 0.35 -- of an attack being a sweep (phase 2: SWEEP_CHANCE_2)
Mancubus.SWEEP_CHANCE_2 = 0.5
Mancubus.SWEEP_RAISE = 1.0 -- seconds the arms come up wide first
Mancubus.SWEEP = 7 -- rockets in a sweep...
Mancubus.SWEEP_ARC = 0.75 -- ...from this many radians one side of his aim to the same the other
Mancubus.SWEEP_EVERY = 0.14
Mancubus.BUMP_REACH = 130 -- px: this near, he leans back...
Mancubus.BUMP_RADIUS = 120 -- ...and lurches forward on everyone this near his front
Mancubus.BUMP_WINDUP = 0.55
Mancubus.BUMP_DAMAGE = 35 -- impact
Mancubus.BUMP_SHOVE = 170 -- px
Mancubus.BUMP_EVERY = 2.4
Mancubus.CALL_AT = { 2 / 3, 1 / 3 } -- shares of his health he shouts for the lads at
Mancubus.CALL = 2 -- Cacodaemons each time (more players, more: Bosses.plus)
Mancubus.SAY_EVERY = { 8, 13 }
Mancubus.DROPS = 35
Mancubus.HELMET = "gear-slayer-helmet" -- his drop, one for every player (gear/kinds.lua)
Mancubus.HELMET_AWAY = 90 -- px from his wreck it lands, clear of the koins

-- His rocket launchers: the weapons feature's, slower, a smaller blast.
Mancubus.GUN = {
  speed = 430, -- px/s: you see them coming
  ttl = 2.2, -- about 950 px, then they go off
  blast = { radius = 100, damage = 40, soft = 0 }, -- (times Bosses.power() on a job finished before: armed below)
  bossGun = true, -- a boss's: its rockets hit harder on a job finished before (weapons' serverFireFrom)
}

Mancubus.lines = {
  "Oi. You're blocking the telly.",
  "Don't make me get up.",
  "I've been sat here since the end of the world.",
  "Remote's mine. Everything's mine.",
  "Ever seen a couch with rockets? Now you have.",
  "Get off my lawn. All of it.",
  "Lads! Snacks have arrived!",
  "Right. I'm getting up. ...No, I'm not.",
  "Snack break.",
  "Not the upholstery!",
  "...five... more... minutes...",
  "Starport's closed. Forever.",
}
Mancubus.LINE = {
  intro = 1, taunt = { 2, 3, 4, 5, 6, 12 }, call = 7, phase2 = 8, heal = 9, back = 10, down = 11,
}

local LEATHER = { 0.55, 0.32, 0.20 }
local RED = { 1.00, 0.18, 0.10 }
local ORANGE = { 1.00, 0.55, 0.12 }

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local gun = nil
--- His launchers' gun: the rocket launcher, common, with his numbers on it.
function Mancubus.gun()
  gun = gun or setmetatable(Mancubus.GUN, { __index = Tiers.apply(Guns.rocket, Tiers.DEFAULT) })
  return gun
end

--- His launchers for this fight: their blast hits harder on a job finished
--- before too (the weapons feature grows a boss gun's rounds, not its blast).
local function armed()
  local base, power = Mancubus.gun(), Bosses.power()
  if power == 1 then
    return base
  end
  local blast = {}
  for k, v in pairs(base.blast) do
    blast[k] = v
  end
  blast.damage = blast.damage * power
  return setmetatable({ blast = blast }, { __index = base })
end

-- The man ---------------------------------------------------------------------

function Mancubus.new(x, y, facing, hp, nav, home)
  return setmetatable({
    x = x, y = y, facing = facing, aim = facing, hp = hp, max = hp, nav = nav, home = home, time = 0, move = nil,
    moveT = 0, bumpIn = 1, attackIn = 1.5, sayIn = 6, frozen = 0, stuck = 0, left = 0, rocketIn = 0, arm = 1,
    phase2 = false, calls = 0, backIn = 0, breath = Stamina.new(Mancubus.BREATH), running = false, mode = "hunt",
    power = Bosses.power(), -- its hits, times this: harder on a job finished before
  }, Mancubus)
end

--- Turn the whole thing towards `angle`, at his treads' pace.
function Mancubus:turn(angle, dt)
  local d = Sight.angleDiff(angle, self.facing)
  local step = Mancubus.TURN * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

--- Drive `speed` px/s along where he faces (backwards if `speed` < 0),
--- sliding along walls and feeling his way round corners (Ground.walk).
function Mancubus:drive(speed, dt)
  local angle = speed < 0 and self.facing + math.pi or self.facing
  return Ground.walk(self, angle, math.abs(speed), dt, Mancubus.RADIUS)
end

--- Can he roll straight from where he is to (x, y), recliner and all?
function Mancubus:straight(x, y)
  return Ground.wideClear(self.x, self.y, x, y, Mancubus.RADIUS)
end

--- Shoved straight along `angle` (out of the way of an ability), treads or no treads.
function Mancubus:slide(angle, speed, dt)
  local mx, my = math.cos(angle) * speed * dt, math.sin(angle) * speed * dt
  if Ground.fits(self.x + mx, self.y + my, Mancubus.RADIUS) then
    self.x, self.y = self.x + mx, self.y + my
  end
end

function Mancubus:pace()
  return self.breath:pace(Mancubus.DRIVE, Mancubus.STROLL)
end

--- Where launcher `arm` (-1 left, 1 right) ends.
function Mancubus:muzzle(arm)
  local fx, fy = math.cos(self.facing), math.sin(self.facing)
  local ahead, side = Mancubus.MUZZLE, Mancubus.ARM * arm
  return self.x + fx * ahead - fy * side, self.y + fy * ahead + fx * side
end

-- Server --------------------------------------------------------------------

local sv = nil -- { m, spec, awake, syncIn, down, gun }

--- Him in front of `map`'s gate (its `horde.boss` of kind "mancubus"),
--- finding his way on `nav` (by the cells his recliner fits, wide_nav.lua).
--- Nothing on a map without him.
function Mancubus.serverStart(server, map, nav)
  Mancubus.serverStop(server)
  local spec = map.horde and map.horde.boss
  if not (spec and spec.kind == "mancubus") then
    return
  end
  local wide = nav and WideNav.of(nav, Mancubus.RADIUS)
  sv = { m = Mancubus.new(spec.x, spec.y, spec.facing or math.pi / 2, Bosses.health(Mancubus.HEALTH, server), wide,
    { x = spec.x, y = spec.y, facing = spec.facing or math.pi / 2 }), spec = spec, awake = false, syncIn = 0,
    gun = armed() }
end

function Mancubus.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("MC_STATE", server.tick))
  end
end

--- Is the gate still closed (he is up)?
function Mancubus.serverLocked()
  return sv ~= nil and not sv.down
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    server:broadcast(Protocol.encode("MC_SAY", Mancubus.LINE.intro))
  end
end

--- Is (x, y) on his patch (the spec's `zone`)? He never leaves it.
function Mancubus.inZone(x, y)
  local z = sv and sv.spec.zone
  return z ~= nil and x >= z.x0 and x <= z.x1 and y >= z.y0 and y <= z.y1
end

--- The lads: Cacodaemons in over the roofs either side of whoever he has.
local function callLads(server)
  local Horde = require("src.features.eternal-mood.horde")
  local m = sv.m
  local _, tx, ty = Brain.target(m, server)
  tx, ty = tx or m.x, ty or m.y
  local n = Bosses.plus(Mancubus.CALL, server)
  for k = 1, n do
    local side = k % 2 == 0 and 1 or -1
    Horde.serverCall(server, "caco", tx + side * (700 + k * 40), ty - 120 * k, tx, ty)
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local MOVE = { raise = 1, volley = 2, sweepRaise = 3, sweep = 4, bump = 5 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local m = sv.m
  local stamina, winded = m.breath:wire()
  local msg = Protocol.encode("MC_STATE", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
    fmt(math.max(0, m.hp)), fmt(m.max), MOVE[m.move] or 0, ("%.3f"):format(m.aim), m.phase2 and 1 or 0,
    sv.awake and 1 or 0, stamina, winded, m.arm)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Mancubus.serverStep(server, dt)
  if not sv or sv.down then
    return
  end
  if not sv.awake then
    local w = sv.spec.wake
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if x >= w.x0 and x <= w.x1 and y >= w.y0 and y <= w.y1 then
          wake(server)
        end
      end
    end
  end
  if sv.awake then
    for _, e in ipairs(Brain.think(sv.m, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("MC_SAY", e[2]))
      elseif e[1] == "rocket" then
        local weapons = Features.byName.weapons
        if weapons and weapons.serverFireFrom then
          local Horde = require("src.features.eternal-mood.horde")
          weapons:serverFireFrom(server, 0, e[2], e[3], e[4], sv.gun, Horde.FROM)
        end
      elseif e[1] == "bump" then
        server:broadcast(Protocol.encode("MC_BUMP", fmt(e[2]), fmt(e[3])))
      elseif e[1] == "sound" then
        server:broadcast(Protocol.encode("MC_SOUND", e[2]))
      elseif e[1] == "call" then
        callLads(server)
      end
    end
  end
  sync(server)
end

--- Where the helmet lands: HELMET_AWAY from (x, y), the first way round
--- with no wall or lava in between (in front of him first), else on him.
local function helmetSpot(x, y, facing)
  local d = Mancubus.HELMET_AWAY
  for i = 0, 7 do
    local a = facing + i * math.pi / 4
    local hx, hy = x + math.cos(a) * d, y + math.sin(a) * d
    if Ground.clear(x, y, hx, hy) then
      return hx, hy
    end
  end
  return x, y
end

--- Down: his last word, his wreck, koins, the helmet, the kill, and the gate open.
local function down(server, by, angle)
  local m = sv.m
  sv.down = true
  server:broadcast(Protocol.encode("MC_SAY", Mancubus.LINE.down))
  server:broadcast(Protocol.encode("MC_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)))
  server:broadcast(Protocol.encode("MC_STATE", server.tick + 1))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, m.x, m.y, Mancubus.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, m.x, m.y)
    pickups:serverDropEnemy(server, m.x + 50, m.y)
  end
  if pickups and pickups.serverDrop then
    local hx, hy = helmetSpot(m.x, m.y, m.facing)
    local item = Tiers.join(Mancubus.HELMET, Bosses.dropTier()) -- its tier rolled: better on a job finished before
    pickups:serverDrop(server, item, hx, hy, nil, { perPlayer = true })
  end
  Features.call("serverKill", server, { kind = "boss", x = m.x, y = m.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him (and wakes him). One in his back, the recliner, does BACK
--- times the damage. Returns true when it hit.
function Mancubus.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local m = sv.m
  if dist2(x, y, m.x, m.y) > (Mancubus.RADIUS + 6 + (radius or 0)) ^ 2 then
    return false
  end
  wake(server)
  damage = damage or 20
  local behind = (x - m.x) * math.cos(m.facing) + (y - m.y) * math.sin(m.facing) < -Mancubus.RADIUS * 0.35
  if behind then
    damage = damage * Mancubus.BACK
    if m.backIn <= m.time then
      m.backIn = m.time + 6
      server:broadcast(Protocol.encode("MC_SAY", Mancubus.LINE.back))
    end
  end
  m.hp = m.hp - damage
  if m.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

--- The wiki's page on him (tools/wiki, docs/wiki.md).
function Mancubus.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local M = Mancubus
  local g = M.gun()
  local blastType = g.blast.type or "explosive"
  add({
    kind = "eternal-mood/mancubus",
    name = "The Mancouchbus",
    quests = { "eternal-mood-earth" },
    boss = true,
    where = "Heck on Earth, in his recliner in front of the starport's gate; he wakes when you come up the Boulevard",
    about = "A huge fat demon who sat down in a recliner when the world ended and never got up again. Heck put the "
      .. "recliner on tank treads and his arms into a pair of rocket launchers. The gate stays closed until he is "
      .. "down.",
    stats = {
      { "Health", M.HEALTH },
      { "Armour", ("his back is the recliner: rounds that land on it do %g times the damage"):format(M.BACK) },
      { "Speed", ("%g px/s on his treads, %g winded; turns at only %g rad/s"):format(M.DRIVE, M.STROLL, M.TURN) },
      { "Sight", M.RANGE, "px" },
    },
    weapons = {
      { "Volley", ("arms up, whining, for %g s, then a rocket from each arm in turn, %g pairs (one more under half "
        .. "health), %g s apart; every %g to %g s (%g to %g under half)"):format(M.RAISE, M.PAIRS, M.ROCKET_EVERY,
        M.VOLLEY_EVERY[1], M.VOLLEY_EVERY[2], M.VOLLEY_EVERY_2[1], M.VOLLEY_EVERY_2[2]) },
      { "Sweep", ("arms up wide for %g s, then %g rockets in a fan, gaps between them; %g%% of his attacks, %g%% "
        .. "under half health"):format(M.SWEEP_RAISE, M.SWEEP, M.SWEEP_CHANCE * 100, M.SWEEP_CHANCE_2 * 100) },
      { "Rockets", ("%g %s damage within %g px of where each goes off, flying at %g px/s for about %g px"):format(
        g.blast.damage, blastType, g.blast.radius, g.speed, math.floor(g.speed * g.ttl + 0.5)) },
      { "Bump", ("within %g px: he leans back for %g s (a ring on the road), then lurches forward: %g impact damage "
        .. "to everyone within %g px of his front, knocked %g px; at most every %g s"):format(M.BUMP_REACH,
        M.BUMP_WINDUP, M.BUMP_DAMAGE, M.BUMP_RADIUS, M.BUMP_SHOVE, M.BUMP_EVERY) },
    },
    abilities = {
      ("Sits about %g px from you, rolling in or backing off, and keeps to the Boulevard."):format(M.KEEP),
      ("At two thirds and a third of his health he shouts for the lads: %g Cacodaemons come in over the roofs (more "
        .. "with more players)."):format(M.CALL),
      ("Under %g%% health he rolls off for a snack break: the nearest medkit within %g px, for %g health."):format(
        Heal.below * 100, Heal.range, Heal.amount),
      ("Rolling at full speed costs him breath: about %d s of it and he's winded, crawling."):format(
        math.floor(Stamina.defaults.max / M.BREATH.drain + 0.5)),
      "Gets out from under abilities.",
    },
    tips = {
      "Get behind him: he is slow to turn, and his back takes the most damage.",
      "Keep moving across a volley, and look for the gaps in a sweep.",
      "Off the Boulevard he won't follow: he rolls back to his spot.",
      "A freeze holds him stiff.",
    },
    drops = ("%g koins, maybe a pickup or two, and the Mood Slayer's helmet for every player"):format(M.DROPS),
  })
end

--- Him, until he is down, for the audit (tools/audit).
function Mancubus.serverEnemies(_server, add)
  if sv and not sv.down then
    local m = sv.m
    add({ id = m, kind = "eternal-mood/mancubus", x = m.x, y = m.y, hp = m.hp, radius = Mancubus.RADIUS + 6 })
  end
end

function Mancubus.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.m.x, sv.m.y) <= radius * radius then
    sv.m.frozen = math.max(sv.m.frozen, seconds)
  end
end

function Mancubus.serverPlayerJoined(server, player)
  if sv and sv.down and not player.bot then
    local m = sv.m
    server:send(player, Protocol.encode("MC_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)), true)
  end
end

--- For tests.
function Mancubus.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil
local say = nil
local bumps = {} -- { x, y, t }
local wreck = nil -- { x, y, angle } where he went down
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local BUMP_SHOWN = 0.45

function Mancubus.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2400)
    return src
  end
  bank.whine = make(0.9, 0.6, function(buf) -- the launchers coming up, servos and a rising whine
    buf:sweep(0, 0.85, 180, 720, { wave = "saw", amp = 0.2, decay = 2 })
    buf:sweep(0, 0.85, 900, 2600, { wave = "sine", amp = 0.15, decay = 2 })
    buf:noiseBurst(0, 0.4, { amp = 0.1, decay = 0.3 })
    buf:lowpass(3000)
  end)
  bank.bump = make(0.7, 0.9, function(buf) -- a lot of demon landing on the road
    buf:noiseBurst(0, 0.3, { amp = 0.7, decay = 0.08 })
    buf:sweep(0, 0.6, 90, 30, { wave = "sine", amp = 0.9, decay = 0.2 })
    buf:lowpass(1800)
  end)
  bank.groan = make(1.2, 0.8, function(buf) -- him, waking: a huge belch of a groan
    buf:sweep(0, 1.1, 60, 42, { wave = "saw", amp = 0.5, attack = 0.1, decay = 0.9, vibRate = 5, vibDepth = 3 })
    buf:noiseBurst(0, 1, { amp = 0.2, decay = 0.6 })
    buf:drive(2.5)
    buf:lowpass(600)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    if x then
      s:setPosition(x, 0, y)
    elseif shown then
      s:setPosition(shown.dx, 0, shown.dy)
    end
    s:setPitch(0.92 + random() * 0.16)
    s:setVolume(0.75 * Audio.volume("weapons"))
    s:play()
  end
end

function Mancubus.clear()
  shown, say, bumps, wreck, lastTick = nil, nil, {}, nil, 0
end

function Mancubus.update(dt)
  clock = clock + dt
  if shown and love.timer.getTime() - heardAt > 1.5 then
    shown = nil
  end
  if shown then
    local k = math.min(1, dt * 14)
    local ex, ey = shown.x - shown.dx, shown.y - shown.dy
    if ex * ex + ey * ey > 300 * 300 then
      shown.dx, shown.dy = shown.x, shown.y
    else
      shown.dx, shown.dy = shown.dx + ex * k, shown.dy + ey * k
      shown.stride = shown.stride + math.sqrt(ex * ex + ey * ey) * k
    end
    -- His treads roll with his turning too.
    local turned = Sight.angleDiff(shown.facing, shown.lastFacing or shown.facing)
    shown.lastFacing = shown.facing
    shown.turnStride = (shown.turnStride or 0) + turned * Mancubus.RADIUS
    Look.update(shown, dt)
  end
  for i = #bumps, 1, -1 do
    bumps[i].t = bumps[i].t + dt
    if bumps[i].t > BUMP_SHOWN then
      table.remove(bumps, i)
    end
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

--- The starport's gate while he is up: a boom across it, CLOSED.
local function drawGate(map)
  local spec = map and map.horde and map.horde.boss
  local gate = spec and spec.kind == "mancubus" and spec.gate
  if not gate then
    return
  end
  local y = gate.y + gate.h / 2
  if wreck then -- the boom up: open
    love.graphics.setColor(0.95, 0.75, 0.10)
    love.graphics.rectangle("fill", gate.x - 8, y - 70, 14, 70)
    return
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", gate.x + 4, y - 4, gate.w, 18)
  for x = gate.x, gate.x + gate.w - 1, 32 do -- red and white
    local red = math.floor((x - gate.x) / 32) % 2 == 0
    love.graphics.setColor(red and 0.85 or 0.92, red and 0.12 or 0.88, red and 0.08 or 0.82)
    love.graphics.rectangle("fill", x, y - 7, math.min(32, gate.x + gate.w - x), 14)
  end
  local pulse = 0.6 + 0.3 * math.abs(math.sin(clock * 3))
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf("CLOSED", gate.x + 2, y + 14, gate.w, "center")
  love.graphics.setColor(1, 0.3, 0.2, pulse)
  love.graphics.printf("CLOSED", gate.x, y + 12, gate.w, "center")
end

function Mancubus.drawBelowCars()
  local c = Features.byName["city-map"]
  drawGate(c and c.map)
  if wreck then
    Look.drawWreck(wreck, clock)
  end
  local m = shown
  if m and m.move == 5 then -- leaning back: how far the bump reaches
    local k = math.min(1, (clock - (m.moveAt or clock)) / Mancubus.BUMP_WINDUP)
    local bx, by = m.dx + math.cos(m.facing) * 40, m.dy + math.sin(m.facing) * 40
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.12 + 0.18 * k)
    love.graphics.circle("fill", bx, by, Mancubus.BUMP_RADIUS, 40)
    love.graphics.setColor(1, 0.6, 0.3, 0.5 + 0.4 * k)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", bx, by, Mancubus.BUMP_RADIUS * (1.25 - 0.25 * k), 40)
    love.graphics.setLineWidth(1)
  end
  for _, b in ipairs(bumps) do -- dust off the road
    local k = b.t / BUMP_SHOWN
    love.graphics.setColor(0.6, 0.5, 0.4, 0.5 * (1 - k))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", b.x, b.y, Mancubus.BUMP_RADIUS * (0.5 + 0.7 * k), 40)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

function Mancubus.drawAboveCars()
  local m = shown
  if m then
    Look.draw(m, clock)
    if say then
      require("src.features.eternal-mood.horde").drawBubble(m.dx, m.dy - Mancubus.RADIUS - 24, say.text)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Mancubus.drawNightLights(glow)
  local m = shown
  if m then
    glow(m.dx, m.dy, 150, RED, 0.5)
    local hot = m.move == 1 or m.move == 3
    for _, arm in ipairs({ -1, 1 }) do
      local fx, fy = math.cos(m.facing), math.sin(m.facing)
      local x = m.dx + fx * Mancubus.MUZZLE - fy * Mancubus.ARM * arm
      local y = m.dy + fy * Mancubus.MUZZLE + fx * Mancubus.ARM * arm
      glow(x, y, hot and 110 or 40, ORANGE, hot and 0.9 or 0.4)
    end
  end
  local c = Features.byName["city-map"]
  local spec = c and c.map and c.map.horde and c.map.horde.boss
  local gate = spec and spec.kind == "mancubus" and spec.gate
  if gate and not wreck then
    glow(gate.x + gate.w / 2, gate.y + gate.h / 2, 260, RED, 0.45)
  end
end

--- His bar, once he is fighting.
function Mancubus.drawHUD()
  if not (shown and shown.awake) then
    return
  end
  Bar.draw({
    title = "THE MANCOUCHBUS", titleColor = LEATHER, fill = shown.phase2 and RED or ORANGE, hp = shown.hp,
    max = shown.max, stamina = shown.stamina, staminaMax = 100, winded = shown.winded,
  })
end

Mancubus.clientMessages = {
  MC_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      shown = nil
      return
    end
    if not shown then
      shown = { dx = x, dy = y, stride = 0, firedAt = {} }
    end
    local m = shown
    m.x, m.y = x, y
    m.facing = tonumber(args[4]) or m.facing or 0
    m.hp, m.max = tonumber(args[5]) or m.hp, tonumber(args[6]) or m.max
    local move = tonumber(args[7]) or 0
    if move ~= m.move then
      m.moveAt = clock
    end
    m.move = move
    m.aim = tonumber(args[8]) or m.facing
    m.phase2 = args[9] == "1"
    m.awake = args[10] == "1"
    m.stamina, m.winded = Stamina.read(args, 11)
    local arm = tonumber(args[13]) or m.arm
    if arm ~= m.arm and (move == 2 or move == 4) then
      m.firedAt[-arm] = clock -- the one that just fired kicks back (the next to fire is `arm`)
    end
    m.arm = arm
  end,
  MC_SAY = function(_client, args)
    local line = tonumber(args[1]) or 0
    local text = Mancubus.lines[line]
    if text then
      say = { text = text, t = 1.5 + #text * 0.05 }
      if line == Mancubus.LINE.intro then
        play("groan")
      end
    end
  end,
  MC_BUMP = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      bumps[#bumps + 1] = { x = x, y = y, t = 0 }
      play("bump", x, y)
    end
  end,
  MC_SOUND = function(_client, args)
    play(args[1] == "whine" and "whine" or "bump")
  end,
  MC_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      wreck = { x = x, y = y, angle = angle }
      play("bump", x, y)
    end
    shown = nil
  end,
}

Brain = require("src.features.eternal-mood.mancubus_brain")

return Mancubus
