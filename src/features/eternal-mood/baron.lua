-- The Baron of Heck, the Foundry's boss (docs/eternal-mood.md, "The bosses,
-- one a level"): a big horned brute on goat legs, the key to the Snooze
-- Gate on his belt. He stands on the stone ring round the Crucible (the
-- map's `horde.boss`, kind "baron") and wakes when someone crosses a bridge
-- onto it (the spec's `wake`) or shoots him; he never leaves the Crucible
-- (its `zone`).
--
-- He throws green fireballs in pairs (fireballs.lua's "baron"), one at you
-- and one where you're going; puts his horns down and charges (into a wall,
-- or the moat's edge, he staggers and stands stunned); claws whoever gets
-- close; and at two thirds and a third of his health he roars, throwing
-- everyone near him back, and imps climb out of the lava (horde.lua's
-- `serverCall`). Under half (phase 2) the green fire catches on his
-- shoulders and he throws three pairs at a go. This module is the man, the
-- wire, the key and the lock; what he does is his brain's
-- (baron_brain.lua), how he looks baron_look.lua's.
--
-- Down, he drops the key where he falls. The portal stays SEALED
-- (`serverLocked`) until somebody walks over the key and picks it up; then
-- someone far away calls your name (the beat).
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
--                  (unreliable, 15 Hz; move 0 none, 1 hands up with fire, 2 throwing, 3 horns down for a charge,
--                  4 charging, 5 stunned, 6 claw raised, 7 roaring; empty once he is gone)
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
Baron.RADIUS = 30 -- px: his shoulders (baron_look.lua draws him)
Baron.WALK = 95 -- px/s
Baron.STROLL = 45 -- px/s winded
Baron.TURN = 4 -- rad/s
Baron.BREATH = { drain = 9, regen = 13, recovered = 50, breath = 40 }
Baron.RANGE = 900 -- px he sees
Baron.KEEP = 260 -- px he likes to be from whoever he has, to throw
Baron.HAND = 26 -- px either side of his middle: his hands (the fire in them)
Baron.THROW_EVERY = { 2.0, 2.8 } -- seconds between attacks...
Baron.THROW_EVERY_2 = { 1.4, 2.0 } -- ...in phase 2
Baron.WINDUP = 0.6 -- seconds the fire burns in his hands first (the tell)
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
Baron.CHARGE_HIT = 46 -- px: whoever he runs into this near...
Baron.CHARGE_DAMAGE = 40 -- ...takes this (impact)...
Baron.CHARGE_SHOVE = 220 -- ...and goes flying
Baron.CHARGE_COST = 22
Baron.STUN = 1.4 -- seconds he stands stunned after a charge into something
Baron.CLAW_REACH = 95 -- px: this near he claws...
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

--- Where hand `side` (-1 left, 1 right) is.
function Baron:hand(side)
  local fx, fy = math.cos(self.facing), math.sin(self.facing)
  return self.x + fx * 18 - fy * Baron.HAND * side, self.y + fy * 18 + fx * Baron.HAND * side
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

--- Is (x, y) on his patch (the spec's `zone`)? He never leaves it.
function Baron.inZone(x, y)
  return sv ~= nil and inBox(sv.spec.zone, x, y)
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    server:broadcast(Protocol.encode("BR_SAY", Baron.LINE.intro))
  end
end

--- His roar: imps climb out of the lava round the pit, at whoever he has.
local function callImps(server)
  local Horde = require("src.features.eternal-mood.horde")
  local m = sv.m
  local pit = sv.spec.pit
  local _, tx, ty = Brain.target(m, server)
  tx, ty = tx or m.x, ty or m.y
  local n = Bosses.plus(Baron.ROAR_IMPS, server)
  for k = 1, n do
    local a = k / n * 2 * math.pi + random()
    local x, y = pit.x + math.cos(a) * pit.r, pit.y + math.sin(a) * pit.r
    Horde.serverCall(server, "imp", x, y, tx, ty)
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local MOVE = { windup = 1, throw = 2, lower = 3, charge = 4, stunned = 5, claw = 6, roar = 7 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local m = sv.m
  local stamina, winded = m.breath:wire()
  local msg = Protocol.encode("BR_STATE", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
    fmt(math.max(0, m.hp)), fmt(m.max), MOVE[m.move] or 0, ("%.3f"):format(m.aim), m.phase2 and 1 or 0,
    sv.awake and 1 or 0, stamina, winded)
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
  if not sv.awake then
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if inBox(sv.spec.wake, x, y) then
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
    pickups:serverDrop(server, Baron.GUN, gx, gy, nil, { perPlayer = true })
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
  bank.fire = make(0.4, 0.6, function(buf) -- fire catching in his hands
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

function Baron.drawAboveCars()
  local m = shown
  if m then
    Look.draw(m, clock)
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
      local fx, fy = math.cos(m.facing), math.sin(m.facing)
      local x, y = m.dx + fx * 18 - fy * Baron.HAND * side, m.dy + fy * 18 + fx * Baron.HAND * side
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
      elseif move == 4 then
        play("hooves")
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
