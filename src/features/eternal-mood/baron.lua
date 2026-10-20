-- The Baron of Heck, the Foundry's boss (docs/eternal-mood.md, "The bosses,
-- one a level"): a big horned brute on goat legs, the key to the Snooze
-- Gate on his belt. He stands on the stone ring round the Crucible (the
-- map's `horde.boss`, kind "baron") and wakes when someone crosses a bridge
-- onto it (the spec's `wake`), comes into his sight (RANGE, no wall in
-- between) or shoots him. Awake, he goes after you wherever you are: hang
-- back in the Smelters and he comes down into them.
--
-- He has guns for hands, and fires green fireballs from them in pairs
-- (fireballs.lua's "baron"), one at you and one where you're going; puts
-- his horns down and charges (into a wall, or the moat's edge, he staggers
-- and stands stunned); leaps at whoever is a fair way off or across the
-- lava, landing on them; clubs whoever gets close with a gun arm; and at
-- two thirds and a third of his health he roars, throwing everyone near
-- him back, and imps climb out of the lava (horde.lua's
-- `serverCall`). Under half (phase 2) the green fire catches on his
-- shoulders and he fires three pairs at a go. This module is the man, the
-- wire, the key and the lock; what he does is his brain's
-- (baron_brain.lua), how he looks baron_look.lua's.
--
-- Down, he drops the key where he falls. The portal stays SEALED
-- (`serverLocked`) until somebody walks over the key and picks it up; then
-- someone far away calls your name (the beat).
--
-- He dodges: a round about to hit him and he throws himself aside, off its
-- line, if he has the breath (baron_brain.lua). His breath shows as a bar
-- under him once he has spent some, throbbing red while he is winded, as
-- well as under his boss bar.
--
-- Like every boss (bosses/init.lua) he has breath, scales with the humans
-- (his health, the imps), has the boss bar, goes for medkits when badly
-- hurt, dodges abilities, and going down raises `serverKill` "boss" and
-- spills koins. He is Heck's: only players' rounds reach him. He also
-- drops the super shotgun, one each player can pick up, which unlocks it
-- in the shop (the weapons feature's, with the reward screen).
--
-- Messages
--   server -> all  BR_STATE <tick> <x> <y> <facing> <hp> <max> <move> <aim> <phase2> <awake> <stamina> <winded>
--                  <leap> (unreliable, 15 Hz; move 0 none, 1 fire at the muzzles, 2 firing, 3 horns down for a
--                  charge, 4 charging, 5 stunned, 6 gun arm back to club, 7 roaring, 8 crouched for a leap,
--                  9 in the air, 10 getting up from one, 11 dodging (along `aim`); leap: px along `aim` he
--                  comes down, while 8 or 9; empty once he is gone)
--   server -> all  BR_SAY  <line>            he says Baron.lines[line]
--   server -> all  BR_HIT  <name> <x> <y>    claw, charge (it hit someone), wall (into one), roar
--   server -> all  BR_DOWN <x> <y> <angle>   he went down: the key lies there (to a joiner too)
--   server -> all  BR_KEY  <name>            the key was picked up by <name>: the portal opens (to a joiner too)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Bosses = require("src.features.bosses")
local Tiers = require("src.features.tiers")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Fireballs = require("src.features.eternal-mood.fireballs")
local Look = require("src.features.eternal-mood.baron_look")

local Baron = {}
Baron.__index = Baron

local Brain

-- Tuning --------------------------------------------------------------------

Baron.HEALTH = 4200 -- for one player (more humans, more: bosses/init.lua); the Mancouchbus has 3400
Baron.RADIUS = 15 -- px: his shoulders (baron_look.lua draws him)
Baron.WALK = 95 -- px/s
Baron.STROLL = 45 -- px/s winded
Baron.TURN = 4 -- rad/s
Baron.BREATH = { drain = 9, regen = 13, recovered = 50, breath = 40 }
Baron.RANGE = 900 -- px he sees
Baron.KEEP = 260 -- px he likes to be from whoever he has, to throw
Baron.HAND = 19 -- px either side of his middle: his guns' muzzles (the fire at them)...
Baron.MUZZLE = 28 -- ...and this far ahead of it (baron_look.lua draws the guns there)
Baron.THROW_EVERY = { 2.0, 2.8 } -- seconds between attacks...
Baron.THROW_EVERY_2 = { 1.4, 2.0 } -- ...in phase 2
Baron.WINDUP = 0.6 -- seconds the fire burns at his muzzles first (the tell)
Baron.PAIRS = 1 -- pairs a go (phase 2: PAIRS_2)
Baron.PAIRS_2 = 3
Baron.PAIR_EVERY = 0.35 -- seconds between pairs
Baron.LEAD = 0.55 -- seconds ahead of you the second of a pair is aimed
Baron.THROW_COST = 14 -- breath
Baron.CHARGE_CHANCE = 0.3 -- of an attack being a charge (phase 2: 0.45)
Baron.CHARGE_CHANCE_2 = 0.45
Baron.CHARGE_MIN = 220 -- px: he charges at whoever is at least this far...
Baron.CHARGE_WINDUP = 0.55 -- seconds horns down, a line on the floor showing where
Baron.CHARGE_SPEED = 400 -- px/s
Baron.CHARGE_FOR = 1.1 -- seconds at most
Baron.CHARGE_HIT = 31 -- px: whoever he runs into this near...
Baron.CHARGE_DAMAGE = 40 -- ...takes this (impact)...
Baron.CHARGE_SHOVE = 220 -- ...and goes flying
Baron.CHARGE_COST = 22
Baron.STUN = 1.4 -- seconds he stands stunned after a charge into something
Baron.LEAP_MIN = 300 -- px: he leaps at whoever is at least this far...
Baron.LEAP_MAX = 560 -- ...landing no further than this off
Baron.LEAP_CHANCE = 0.3 -- of an attack being a leap (phase 2: 0.45); always at whoever's across the lava
Baron.LEAP_CHANCE_2 = 0.45
Baron.LEAP_EVERY = 5 -- seconds at least between leaps
Baron.LEAP_WINDUP = 0.6 -- seconds crouched, a ring on the floor where he'll come down
Baron.LEAP_AIR = 0.75 -- seconds in the air
Baron.LEAP_RECOVER = 0.6 -- seconds getting up, wide open
Baron.LEAP_HIT = 80 -- px: whoever he lands this near...
Baron.LEAP_DAMAGE = 45 -- ...takes this (impact)...
Baron.LEAP_SHOVE = 200 -- ...and goes flying
Baron.LEAP_COST = 26
Baron.DODGE_WARN = 0.35 -- seconds' warning he needs of a round to get off its line...
Baron.DODGE_SPEED = 420 -- ...throwing himself aside this fast...
Baron.DODGE_TIME = 0.25 -- ...for this long (about 100 px; further from under an ability)
Baron.DODGE_COOL = 1.8 -- seconds at least between dodges
Baron.DODGE_COST = 20 -- breath; winded, he can't...
Baron.DODGE_FLOOR = 60 -- ...nor with less than this in him: what's under it is for his attacks
Baron.CLAW_REACH = 65 -- px: this near he claws...
Baron.CLAW_ARC = 1.1 -- ...everyone within this many radians of his front...
Baron.CLAW_WINDUP = 0.4
Baron.CLAW_DAMAGE = 30 -- melee
Baron.CLAW_EVERY = 1.3
Baron.ROAR_AT = { 2 / 3, 1 / 3 } -- shares of his health he roars at
Baron.ROAR = 1.0 -- seconds of it
Baron.ROAR_RADIUS = 200 -- px: everyone this near is thrown back
Baron.ROAR_SHOVE = 180
Baron.ROAR_IMPS = 3 -- imps out of the lava each roar (more players, more: Bosses.plus)
Baron.SAY_EVERY = { 9, 14 }
Baron.DROPS = 45
Baron.KEY_REACH = 48 -- px: walk this near the key to pick it up
Baron.GUN = "gun-super-shotgun" -- his drop, one for every player (weapons/guns.lua)
Baron.GUN_AWAY = 100 -- px from the key it lands, so picking one up isn't picking up the other

Baron.lines = {
  "KNEEL.",
  "THE KEY IS MINE.",
  "YOU ARE NOT ON THE LIST.",
  "BURN.",
  "I WAS PROMOTED TOO.",
  "THE GATE SLEEPS. SO WILL YOU.",
  "RISE, LITTLE ONES!",
  "ENOUGH!",
  "...A MOMENT.",
  "The... key... snooze...",
}
Baron.LINE = { intro = 1, taunt = { 2, 3, 4, 5, 6 }, roar = 7, phase2 = 8, heal = 9, down = 10 }

-- What somebody far away says once the key is picked up (the beat): over
-- the HUD, quiet, nobody's.
Baron.CALL = "...hey. Hey. Are you awake?"

local GREEN = { 0.35, 1.00, 0.35 }
local FLESH = { 0.88, 0.62, 0.52 }
local RED = { 1.00, 0.18, 0.10 }
local BRASS = { 0.95, 0.75, 0.25 }

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The man ---------------------------------------------------------------------

function Baron.new(x, y, facing, hp, nav, home)
  return setmetatable({
    x = x, y = y, facing = facing, aim = facing, hp = hp, max = hp, nav = nav, home = home, time = 0, move = nil,
    moveT = 0, attackIn = 1.2, clawIn = 0, sayIn = 6, frozen = 0, stuck = 0, left = 0, pairIn = 0,
    phase2 = false, roars = 0, breath = Stamina.new(Baron.BREATH), running = false, mode = "hunt",
    power = Bosses.power(), -- its hits, times this: harder on a job finished before
  }, Baron)
end

local function fits(x, y)
  local r = Baron.RADIUS
  local k = r * 0.7
  return not (Ground.blocked(x, y) or Ground.blocked(x - r, y) or Ground.blocked(x + r, y)
    or Ground.blocked(x, y - r) or Ground.blocked(x, y + r) or Ground.blocked(x - k, y - k)
    or Ground.blocked(x + k, y - k) or Ground.blocked(x - k, y + k) or Ground.blocked(x + k, y + k))
end
Baron.fits = fits

function Baron:turn(angle, dt, rate)
  local d = Sight.angleDiff(angle, self.facing)
  local step = (rate or Baron.TURN) * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

--- Walk along `angle` at `speed`, sliding along walls. Returns false when
--- he got nowhere.
function Baron:walk(angle, speed, dt)
  local mx, my = math.cos(angle) * speed * dt, math.sin(angle) * speed * dt
  if fits(self.x + mx, self.y + my) then
    self.x, self.y = self.x + mx, self.y + my
  elseif fits(self.x + mx, self.y) then
    self.x = self.x + mx
  elseif fits(self.x, self.y + my) then
    self.y = self.y + my
  else
    self.stuck = self.stuck + dt
    return false
  end
  self.stuck = 0
  return true
end

function Baron:pace()
  return self.breath:pace(Baron.WALK, Baron.STROLL)
end

--- Where the muzzle of gun `side` (-1 left, 1 right) is, for him at (x, y)
--- facing `facing`.
function Baron.muzzle(x, y, facing, side)
  local fx, fy = math.cos(facing), math.sin(facing)
  return x + fx * Baron.MUZZLE - fy * Baron.HAND * side, y + fy * Baron.MUZZLE + fx * Baron.HAND * side
end

--- Where his gun `side` (-1 left, 1 right) fires from.
function Baron:hand(side)
  return Baron.muzzle(self.x, self.y, self.facing, side)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { m, spec, awake, syncIn, down, key = { x, y } | nil, keyTaken }

--- Him on `map`'s Crucible (its `horde.boss` of kind "baron"), finding his
--- way on `nav`. Nothing on a map without him.
function Baron.serverStart(server, map, nav)
  Baron.serverStop(server)
  local spec = map.horde and map.horde.boss
  if not (spec and spec.kind == "baron") then
    return
  end
  local facing = spec.facing or math.pi / 2
  sv = { m = Baron.new(spec.x, spec.y, facing, Bosses.health(Baron.HEALTH, server), nav,
    { x = spec.x, y = spec.y, facing = facing }), spec = spec, awake = false, syncIn = 0 }
end

function Baron.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("BR_STATE", server.tick))
  end
end

--- Is the portal still sealed (he is up, or the key lies where he fell)?
function Baron.serverLocked()
  return sv ~= nil and not sv.keyTaken
end

local function inBox(b, x, y)
  return b ~= nil and x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    server:broadcast(Protocol.encode("BR_SAY", Baron.LINE.intro))
  end
end

--- His roar: imps climb out of the lava round the pit, at whoever he has;
--- away from the Crucible, up through the floor round him.
local function callImps(server)
  local Horde = require("src.features.eternal-mood.horde")
  local m = sv.m
  local pit = sv.spec.pit
  local _, tx, ty = Brain.target(m, server)
  tx, ty = tx or m.x, ty or m.y
  local cx, cy, r = pit.x, pit.y, pit.r
  if dist2(m.x, m.y, pit.x, pit.y) > (pit.r + Baron.ROAR_RADIUS * 2) ^ 2 then
    cx, cy, r = m.x, m.y, Baron.ROAR_RADIUS * 0.6
  end
  local n = Bosses.plus(Baron.ROAR_IMPS, server)
  for k = 1, n do
    local a = k / n * 2 * math.pi + random()
    local x, y = cx + math.cos(a) * r, cy + math.sin(a) * r
    if Ground.blocked(x, y) then
      x, y = cx, cy
    end
    Horde.serverCall(server, "imp", x, y, tx, ty)
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local MOVE = { windup = 1, throw = 2, lower = 3, charge = 4, stunned = 5, claw = 6, roar = 7, crouch = 8, leap = 9,
  land = 10, dodge = 11 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local m = sv.m
  local stamina, winded = m.breath:wire()
  local leap, aim = 0, m.move == "dodge" and m.dodgeA or m.aim
  if m.leapTo and (m.move == "crouch" or m.move == "leap") then
    local f = m.leapFrom or m
    leap, aim = math.sqrt(dist2(f.x, f.y, m.leapTo.x, m.leapTo.y)), math.atan2(m.leapTo.y - f.y, m.leapTo.x - f.x)
  end
  local msg = Protocol.encode("BR_STATE", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
    fmt(math.max(0, m.hp)), fmt(m.max), MOVE[m.move] or 0, ("%.3f"):format(aim), m.phase2 and 1 or 0,
    sv.awake and 1 or 0, stamina, winded, fmt(leap))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- The key lying where he fell: the first player to walk over it has it.
local function stepKey(server)
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if dist2(x, y, sv.key.x, sv.key.y) <= Baron.KEY_REACH ^ 2 then
        sv.keyTaken, sv.key = true, nil
        server:broadcast(Protocol.encode("BR_KEY", p.name or "Somebody"))
        return
      end
    end
  end
end

function Baron.serverStep(server, dt)
  if not sv then
    return
  end
  if sv.down then
    if sv.key then
      stepKey(server)
    end
    return
  end
  if not sv.awake then -- over a bridge, or in his sight
    local m = sv.m
    for _, p in pairs(server.players) do
      if not p.bot and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        if inBox(sv.spec.wake, x, y)
          or (dist2(x, y, m.x, m.y) <= Baron.RANGE ^ 2 and Sight.clear(m.x, m.y, x, y)) then
          wake(server)
        end
      end
    end
  end
  if sv.awake then
    for _, e in ipairs(Brain.think(sv.m, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("BR_SAY", e[2]))
      elseif e[1] == "fireball" then
        Fireballs.serverThrow(server, e[2], e[3], e[4], "baron")
      elseif e[1] == "hit" then
        server:broadcast(Protocol.encode("BR_HIT", e[2], fmt(e[3]), fmt(e[4])))
      elseif e[1] == "imps" then
        callImps(server)
      end
    end
  end
  sync(server)
end

--- Where the shotgun lands: GUN_AWAY from (x, y), the first way round with
--- no wall or lava in between (behind him first: he faces whoever he was
--- fighting), else on him.
local function gunSpot(x, y, facing)
  local d = Baron.GUN_AWAY
  for i = 0, 7 do
    local a = facing + math.pi + i * math.pi / 4
    local gx, gy = x + math.cos(a) * d, y + math.sin(a) * d
    if Ground.clear(x, y, gx, gy) then
      return gx, gy
    end
  end
  return x, y
end

--- Down: his last word, his body, the key on the floor, koins, the
--- shotgun, the kill.
local function down(server, by, angle)
  local m = sv.m
  sv.down = true
  sv.key = { x = m.x, y = m.y }
  server:broadcast(Protocol.encode("BR_SAY", Baron.LINE.down))
  server:broadcast(Protocol.encode("BR_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)))
  server:broadcast(Protocol.encode("BR_STATE", server.tick + 1))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, m.x, m.y, Baron.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, m.x + 60, m.y)
    pickups:serverDropEnemy(server, m.x - 60, m.y)
  end
  if pickups and pickups.serverDrop then
    local gx, gy = gunSpot(m.x, m.y, m.facing)
    local item = Tiers.join(Baron.GUN, Bosses.dropTier()) -- its tier rolled: better on a job finished before
    pickups:serverDrop(server, item, gx, gy, nil, { perPlayer = true })
  end
  Features.call("serverKill", server, { kind = "boss", x = m.x, y = m.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him (and wakes him). Returns true when it hit.
function Baron.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local m = sv.m
  if dist2(x, y, m.x, m.y) > (Baron.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  wake(server)
  m.hp = m.hp - (damage or 20)
  if m.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

--- The wiki's page on him (tools/wiki, docs/wiki.md).
function Baron.wikiEnemies(add)
  local Heal = require("src.features.bosses.heal")
  local B = Baron
  local fire = Fireballs.KINDS.baron
  add({
    kind = "eternal-mood/baron",
    name = "The Baron of Heck",
    quests = { "eternal-mood-foundry" },
    boss = true,
    where = "The Foundry, on the stone ring round the Crucible; he wakes when you cross a bridge onto it, he sees "
      .. "you, or you shoot him",
    about = "A big horned brute on goat legs with guns for hands, the key to the Snooze Gate on his belt. Awake, "
      .. "he comes after you wherever you are, leaping the lava if he has to.",
    stats = {
      { "Health", B.HEALTH },
      { "Speed", ("%g px/s, %g winded"):format(B.WALK, B.STROLL) },
      { "Sight", B.RANGE, "px" },
    },
    weapons = {
      { "Green fire", ("fire burns at both muzzles for %g s, then a pair of fireballs, one at you and one where "
        .. "you're going; %g fire damage each at %g px/s. %g pair a go (%g under half health, %g s apart), every "
        .. "%g to %g s (%g to %g under half)"):format(B.WINDUP, fire.damage, fire.speed, B.PAIRS, B.PAIRS_2,
        B.PAIR_EVERY, B.THROW_EVERY[1], B.THROW_EVERY[2], B.THROW_EVERY_2[1], B.THROW_EVERY_2[2]) },
      { "Charge", ("at anyone %g px or more off: horns down for %g s (a red lane on the floor), then %g px/s for up "
        .. "to %g s; %g impact damage and %g px of flying to whoever he hits. %g%% of his attacks, %g%% under half "
        .. "health"):format(B.CHARGE_MIN, B.CHARGE_WINDUP, B.CHARGE_SPEED, B.CHARGE_FOR, B.CHARGE_DAMAGE,
        B.CHARGE_SHOVE, B.CHARGE_CHANCE * 100, B.CHARGE_CHANCE_2 * 100) },
      { "Leap", ("at anyone %g px or more off (landing no further than %g px), and always at anyone across the lava: "
        .. "crouched for %g s (a ring where he'll land), %g s in the air, then %g impact damage within %g px and "
        .. "%g px of flying; at most every %g s"):format(B.LEAP_MIN, B.LEAP_MAX, B.LEAP_WINDUP, B.LEAP_AIR,
        B.LEAP_DAMAGE, B.LEAP_HIT, B.LEAP_SHOVE, B.LEAP_EVERY) },
      { "Claw", ("within %g px: gun arm back for %g s, then %g melee damage to everyone in front of him; at most "
        .. "every %g s"):format(B.CLAW_REACH, B.CLAW_WINDUP, B.CLAW_DAMAGE, B.CLAW_EVERY) },
    },
    abilities = {
      ("At two thirds and a third of his health he roars: everyone within %g px is thrown back %g px, and %g imps "
        .. "climb out of the lava (more with more players)."):format(B.ROAR_RADIUS, B.ROAR_SHOVE, B.ROAR_IMPS),
      ("Dodges: a round about to hit him and he throws himself aside, at most every %g s, if he has the breath. He "
        .. "gets out from under abilities too."):format(B.DODGE_COOL),
      ("Charging into a wall or the moat's edge, he stands stunned for %g s."):format(B.STUN),
      ("Under %g%% health he goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      "Down, he drops the key: the portal stays sealed until somebody picks it up.",
    },
    tips = {
      "Stand in front of a wall when he lowers his horns, then step aside: he charges into it and stands stunned.",
      ("He comes up slow from a leap, wide open for %g s: be out of the ring, then shoot."):format(B.LEAP_RECOVER),
      "Run him out of breath: winded, he can't dodge your rounds.",
      "A freeze holds him stiff.",
    },
    drops = ("%g koins, maybe a pickup or two, the key, and a super shotgun for every player"):format(B.DROPS),
  })
end

--- Him, until he is down, for the audit (tools/audit).
function Baron.serverEnemies(_server, add)
  if sv and not sv.down then
    local m = sv.m
    add({ id = m, kind = "eternal-mood/baron", x = m.x, y = m.y, hp = m.hp, radius = Baron.RADIUS })
  end
end

function Baron.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.m.x, sv.m.y) <= radius * radius then
    sv.m.frozen = math.max(sv.m.frozen, seconds)
  end
end

function Baron.serverPlayerJoined(server, player)
  if sv and sv.down and not player.bot then
    local m = sv.m
    server:send(player, Protocol.encode("BR_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)), true)
    if sv.keyTaken then
      server:send(player, Protocol.encode("BR_KEY", ""), true)
    end
  end
end

--- For tests.
function Baron.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil
local say = nil
local rings = {} -- { x, y, t, r } dust and shockwaves
local body = nil -- { x, y, angle } where he went down
local key = nil -- { x, y } the key lying there, until picked up
local opened = false -- the key's been picked up: the portal is open
local call = nil -- { t } somebody far away, calling
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local RING_SHOWN = 0.5
local CALL_FOR = 5

function Baron.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2600)
    return src
  end
  bank.roar = make(1.4, 0.9, function(buf) -- a bull's bellow, through a furnace
    buf:sweep(0, 1.3, 95, 60, { wave = "saw", amp = 0.55, attack = 0.08, decay = 1.1, vibRate = 9, vibDepth = 5 })
    buf:sweep(0, 1.2, 190, 120, { wave = "square", amp = 0.2, attack = 0.1, decay = 0.9, vibRate = 7, vibDepth = 8 })
    buf:noiseBurst(0, 1.2, { amp = 0.35, decay = 0.7 })
    buf:drive(3)
    buf:lowpass(900)
  end)
  bank.claw = make(0.35, 0.8, function(buf)
    buf:noiseBurst(0, 0.25, { amp = 0.8, decay = 0.06 })
    buf:sweep(0, 0.2, 700, 200, { wave = "saw", amp = 0.2, decay = 0.1 })
    buf:highpass(600)
  end)
  bank.hooves = make(0.5, 0.8, function(buf) -- his charge setting off
    for k = 0, 3 do
      buf:kick(k * 0.11, 0.7)
      buf:noiseBurst(k * 0.11, 0.05, { amp = 0.3, decay = 0.02 })
    end
    buf:lowpass(1500)
  end)
  bank.wall = make(0.7, 0.9, function(buf) -- horns into a wall
    buf:noiseBurst(0, 0.4, { amp = 0.9, decay = 0.1 })
    buf:sweep(0, 0.6, 120, 35, { wave = "sine", amp = 0.9, decay = 0.2 })
    buf:tone(0, 0.5, 620, { wave = "square", amp = 0.1, decay = 0.2, sustain = 0 })
    buf:lowpass(2500)
  end)
  bank.key = make(1.0, 0.7, function(buf) -- the key picked up: a bright chime
    for k, n in ipairs({ "C6", "E6", "G6", "C7" }) do
      buf:tone((k - 1) * 0.08, 0.6, Synth.freq(n), { wave = "sine", amp = 0.2, attack = 0.002, decay = 0.5,
        sustain = 0 })
    end
  end)
  bank.dash = make(0.3, 0.6, function(buf) -- throwing himself aside: a scuff and a whoosh
    buf:kick(0, 0.5)
    buf:noiseBurst(0, 0.25, { amp = 0.5, decay = 0.12 })
    buf:sweep(0, 0.22, 300, 120, { wave = "sine", amp = 0.25, decay = 0.15 })
    buf:lowpass(1800)
  end)
  bank.fire = make(0.4, 0.6, function(buf) -- fire catching at his muzzles
    buf:noiseBurst(0, 0.38, { amp = 0.5, decay = 0.3 })
    buf:sweep(0, 0.35, 200, 500, { wave = "sine", amp = 0.2, decay = 0.3 })
    buf:lowpass(2200)
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
    else
      s:setRelative(true)
    end
    s:setPitch(0.92 + random() * 0.16)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Baron.clear()
  shown, say, rings, body, key, opened, call, lastTick = nil, nil, {}, nil, nil, false, nil, 0
end

function Baron.update(dt)
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
  end
  for i = #rings, 1, -1 do
    rings[i].t = rings[i].t + dt
    if rings[i].t > RING_SHOWN then
      table.remove(rings, i)
    end
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
  if call then
    call.t = call.t + dt
    if call.t > CALL_FOR then
      call = nil
    end
  end
end

local function spec()
  local c = Features.byName["city-map"]
  local s = c and c.map and c.map.horde and c.map.horde.boss
  return s and s.kind == "baron" and s or nil
end

--- The portal while it is sealed: chains across it and a lock, SEALED.
local function drawSeal()
  local s = spec()
  local p = s and s.portal
  if not p or opened then
    return
  end
  love.graphics.setColor(0.10, 0.02, 0.02, 0.6)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 20)
  love.graphics.setColor(0.45, 0.42, 0.40)
  love.graphics.setLineWidth(5)
  love.graphics.line(p.x + 10, p.y + 10, p.x + p.w - 10, p.y + p.h - 10)
  love.graphics.line(p.x + p.w - 10, p.y + 10, p.x + 10, p.y + p.h - 10)
  love.graphics.setLineWidth(1)
  local cx, cy = p.x + p.w / 2, p.y + p.h / 2
  love.graphics.setColor(BRASS)
  love.graphics.rectangle("fill", cx - 14, cy - 8, 28, 22, 3) -- the lock
  love.graphics.setColor(0.2, 0.15, 0.05)
  love.graphics.circle("fill", cx, cy + 2, 4, 8)
  local pulse = 0.6 + 0.3 * math.abs(math.sin(clock * 3))
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf("SEALED", p.x + 2, p.y + p.h + 6, p.w, "center")
  love.graphics.setColor(1, 0.3, 0.2, pulse)
  love.graphics.printf("SEALED", p.x, p.y + p.h + 4, p.w, "center")
end

function Baron.drawBelowCars()
  drawSeal()
  if body then
    Look.drawBody(body, clock)
  end
  if key then
    Look.drawKey(key.x, key.y, clock)
  end
  local m = shown
  if m and (m.move == 8 or m.move == 9) and m.leapX then -- crouched or up: where he comes down
    local k = m.move == 8 and math.min(1, (clock - (m.moveAt or clock)) / Baron.LEAP_WINDUP)
      or math.min(1, (clock - (m.moveAt or clock)) / Baron.LEAP_AIR)
    love.graphics.setColor(RED[1], RED[2], RED[3], m.move == 8 and 0.12 + 0.12 * k or 0.25)
    love.graphics.circle("fill", m.leapX, m.leapY, Baron.LEAP_HIT, 40)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.7)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", m.leapX, m.leapY, Baron.LEAP_HIT, 40)
    if m.move == 9 then -- closing in as he comes down
      love.graphics.circle("line", m.leapX, m.leapY, Baron.LEAP_HIT * (1 - k), 40)
    end
    love.graphics.setLineWidth(1)
  end
  if m and m.move == 3 then -- horns down: where he'll run
    local k = math.min(1, (clock - (m.moveAt or clock)) / Baron.CHARGE_WINDUP)
    local ex, ey = Sight.reach(m.dx, m.dy, m.aim, Baron.CHARGE_SPEED * Baron.CHARGE_FOR)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.15 + 0.3 * k)
    love.graphics.setLineWidth(Baron.RADIUS * 2)
    love.graphics.line(m.dx, m.dy, ex, ey)
    love.graphics.setLineWidth(1)
  elseif m and m.move == 6 then -- the claw coming: its reach
    local k = math.min(1, (clock - (m.moveAt or clock)) / Baron.CLAW_WINDUP)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.12 + 0.2 * k)
    love.graphics.arc("fill", m.dx, m.dy, Baron.CLAW_REACH, m.facing - Baron.CLAW_ARC, m.facing + Baron.CLAW_ARC, 20)
  elseif m and m.move == 7 then -- the roar: its reach
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.12)
    love.graphics.circle("fill", m.dx, m.dy, Baron.ROAR_RADIUS, 40)
  end
  for _, r in ipairs(rings) do
    local k = r.t / RING_SHOWN
    love.graphics.setColor(0.7, 0.55, 0.4, 0.55 * (1 - k))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", r.x, r.y, r.r * (0.4 + 0.8 * k), 40)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

local BREATH_MAX = Stamina.defaults.max

--- His breath as a thin bar under him once he has spent some, throbbing red
--- while he is winded (the Hunters' bar, bigger: hunters/init.lua).
local function drawBreath(m)
  if not (m.awake and m.stamina) or (not m.winded and m.stamina >= BREATH_MAX) then
    return
  end
  local bw, x, y = 70, m.dx, m.dy + Baron.RADIUS + 26
  local f = math.max(0, math.min(1, m.stamina / BREATH_MAX))
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y, bw + 2, 6)
  if m.winded then
    love.graphics.setColor(0.9, 0.3, 0.3, 0.35 + 0.25 * math.sin(clock * 8))
    love.graphics.rectangle("fill", x - bw / 2, y + 1, bw, 4)
    love.graphics.setColor(1, 0.5, 0.45)
  else
    love.graphics.setColor(0.45, 0.75, 1)
  end
  love.graphics.rectangle("fill", x - bw / 2, y + 1, bw * f, 4)
end

function Baron.drawAboveCars()
  local m = shown
  if m then
    local k = m.move == 9 and math.min(1, (clock - (m.moveAt or clock)) / Baron.LEAP_AIR) or 0
    m.lift = math.sin(k * math.pi) -- how high he is, 0 on the floor
    Look.draw(m, clock)
    drawBreath(m)
    if say then
      require("src.features.eternal-mood.horde").drawBubble(m.dx, m.dy - Baron.RADIUS - 28, say.text)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Baron.drawNightLights(glow)
  local m = shown
  if m then
    local hot = m.move == 1 or m.move == 2
    for _, side in ipairs({ -1, 1 }) do
      local x, y = Baron.muzzle(m.dx, m.dy, m.facing, side)
      glow(x, y, hot and 120 or 40, GREEN, hot and 0.9 or 0.35)
    end
    if m.phase2 then
      glow(m.dx, m.dy, 140, GREEN, 0.4)
    end
  end
  if key then
    glow(key.x, key.y, 90, BRASS, 0.7 + 0.3 * math.sin(clock * 4))
  end
end

--- His bar, once he is fighting; and somebody far away, once the key is up.
function Baron.drawHUD()
  if shown and shown.awake then
    Bar.draw({
      title = "THE BARON OF HECK", titleColor = FLESH, fill = shown.phase2 and GREEN or RED, hp = shown.hp,
      max = shown.max, stamina = shown.stamina, staminaMax = 100, winded = shown.winded,
    })
  end
  if call then
    local w, h = love.graphics.getDimensions()
    local a = math.min(1, call.t / 1.2, (CALL_FOR - call.t) / 1.2)
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0.85, 0.85, 1, 0.75 * a)
    love.graphics.printf(Baron.CALL, 0, h * 0.24, w, "center")
    love.graphics.setColor(1, 1, 1)
  end
end

Baron.clientMessages = {
  BR_STATE = function(_client, args)
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
      shown = { dx = x, dy = y, stride = 0 }
    end
    local m = shown
    m.x, m.y = x, y
    m.facing = tonumber(args[4]) or m.facing or 0
    m.hp, m.max = tonumber(args[5]) or m.hp, tonumber(args[6]) or m.max
    local move = tonumber(args[7]) or 0
    if move ~= m.move then
      m.moveAt = clock
      if move == 1 then
        play("fire")
      elseif move == 4 or move == 9 then -- off on a charge, or up off the floor
        play("hooves")
      elseif move == 11 then
        play("dash")
      elseif move == 7 then
        play("roar")
        rings[#rings + 1] = { x = m.dx, y = m.dy, t = 0, r = Baron.ROAR_RADIUS }
      end
    end
    m.move = move
    m.aim = tonumber(args[8]) or m.facing
    m.phase2 = args[9] == "1"
    m.awake = args[10] == "1"
    m.stamina, m.winded = Stamina.read(args, 11)
    local leap = tonumber(args[13]) or 0
    if move == 8 and leap > 0 then -- where he'll come down, from where he crouches
      m.leapX, m.leapY = x + math.cos(m.aim) * leap, y + math.sin(m.aim) * leap
    elseif move ~= 9 then
      m.leapX, m.leapY = nil, nil
    end
  end,
  BR_SAY = function(_client, args)
    local line = tonumber(args[1]) or 0
    local text = Baron.lines[line]
    if text then
      say = { text = text, t = 1.5 + #text * 0.05 }
      if line == Baron.LINE.intro then
        play("roar")
      end
    end
  end,
  BR_HIT = function(_client, args)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    if args[1] == "claw" then
      play("claw", x, y)
    elseif args[1] == "wall" then
      play("wall", x, y)
      rings[#rings + 1] = { x = x, y = y, t = 0, r = 90 }
    elseif args[1] == "charge" then
      play("wall", x, y)
    elseif args[1] == "leap" then
      play("wall", x, y)
      rings[#rings + 1] = { x = x, y = y, t = 0, r = Baron.LEAP_HIT * 1.6 }
    end
  end,
  BR_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      body = { x = x, y = y, angle = angle }
      if not opened then
        key = { x = x, y = y }
      end
      play("wall", x, y)
    end
    shown = nil
  end,
  BR_KEY = function(_client, args)
    local fresh = not opened
    key, opened = nil, true
    if fresh and args[1] ~= "" then
      play("key")
      call = { t = 0 }
    end
  end,
}

Brain = require("src.features.eternal-mood.baron_brain")

return Baron
