-- The Spider Mattressmind, Heck's boss (docs/eternal-mood.md, "The bosses,
-- one a level"), the way Heck makes a Spider Mastermind: a giant brain on
-- four mechanical spider legs, a chaingun under its chin, standing on a
-- mattress it drags with it everywhere. It sits on the Mattress's plateau
-- before the Snooze Gate (the map's `horde.boss`, kind "mattressmind") and
-- wakes when somebody walks onto the plateau (the spec's `wake`) or shoots
-- it; it keeps to the plateau (`zone`). Nobody goes through the gate while
-- it is up: the gate is LOCKED (`serverLocked`) until it is down.
--
-- The chaingun spins up (a whine, the barrels glowing: the tell), then
-- fires a long burst that drags after you; up close its legs come down on
-- you; at two thirds and a third of its health it murmurs "...five more
-- minutes..." and imps and Cacodaemons come up onto the plateau (horde.lua's
-- `serverCall`). Under half (phase 2) it starts yawning: a yawn pulls
-- everyone near it in, slowly, and snaps shut on whoever it got. The
-- mattress soaks up rounds from the front (FRONT): get round it. This
-- module is the beast, the wire and the lock; what it does is its brain's
-- (mattressmind_brain.lua), how it looks mattressmind_look.lua's. Its
-- rounds are the weapons feature's (a minigun of its own, ownerless, from
-- the horde: they never hurt Heck).
--
-- Like every boss (bosses/init.lua) it has breath, scales with the humans
-- (its health, its company), has the boss bar, goes for medkits when badly
-- hurt, dodges abilities, and going down raises `serverKill` "boss" and
-- spills koins. It is Heck's: only players' rounds reach it.
--
-- Messages
--   server -> all  SM_STATE <tick> <x> <y> <facing> <hp> <max> <move> <aim> <phase2> <awake> <stamina> <winded>
--                  (unreliable, 15 Hz; move 0 none, 1 the chaingun spinning up, 2 firing, 3 legs up, 4 yawning;
--                  empty once it is gone)
--   server -> all  SM_SAY  <line>             it says Mattressmind.lines[line]
--   server -> all  SM_HIT  <name> <x> <y>     slam (its legs came down), snap (the yawn shut), soak (the
--                                             mattress took one)
--   server -> all  SM_DOWN <x> <y> <angle>    it went down: the gate unlocks (to a joiner too)

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
local Look = require("src.features.eternal-mood.mattressmind_look")

local Mattressmind = {}
Mattressmind.__index = Mattressmind

local Brain

-- Tuning --------------------------------------------------------------------

Mattressmind.HEALTH = 5200 -- for one player (more humans, more: bosses/init.lua); the Baron has 4200
Mattressmind.RADIUS = 56 -- px: it, on its mattress (mattressmind_look.lua draws it)
Mattressmind.WALK = 70 -- px/s, any way on its legs, the mattress dragging under it
Mattressmind.STROLL = 35 -- px/s winded
Mattressmind.TURN = 1.6 -- rad/s
Mattressmind.BREATH = { drain = 8, regen = 12, recovered = 50, breath = 40 }
Mattressmind.RANGE = 950 -- px it sees
Mattressmind.KEEP = 420 -- px it keeps from whoever it has
Mattressmind.FRONT = 0.3 -- what a round coming at it from in front does, through the mattress
Mattressmind.MUZZLE = 64 -- px ahead of its middle: the chaingun's end
Mattressmind.ATTACK_EVERY = { 2.4, 3.2 } -- seconds between bursts...
Mattressmind.ATTACK_EVERY_2 = { 1.8, 2.4 } -- ...in phase 2
Mattressmind.SPIN = 0.8 -- seconds the chaingun spins up first (the tell)
Mattressmind.FIRE_FOR = 2.4 -- seconds a burst lasts
Mattressmind.FIRE_EVERY = 0.09 -- seconds between rounds
Mattressmind.AIM_TURN = 1.25 -- rad/s the aim drags after you while it fires: outrun it
Mattressmind.FIRE_COST = 18 -- breath
Mattressmind.SLAM_REACH = 140 -- px: this near, its legs go up...
Mattressmind.SLAM_RADIUS = 135 -- ...and come down on everyone this near
Mattressmind.SLAM_WINDUP = 0.6
Mattressmind.SLAM_DAMAGE = 32 -- impact
Mattressmind.SLAM_SHOVE = 160
Mattressmind.SLAM_EVERY = 2.4
Mattressmind.YAWN_EVERY = { 8, 11 } -- seconds between yawns, in phase 2
Mattressmind.YAWN = 2.2 -- seconds a yawn pulls...
Mattressmind.YAWN_REACH = 650 -- ...everyone this near...
Mattressmind.YAWN_PULL = 95 -- ...in at this many px/s (a walk won't hold it, a sprint will)
Mattressmind.SNAP_REACH = 140 -- px: whoever it got this near when it shuts...
Mattressmind.SNAP_DAMAGE = 45 -- ...takes this (melee)...
Mattressmind.SNAP_SHOVE = 200 -- ...and is spat out
Mattressmind.CALL_AT = { 2 / 3, 1 / 3 } -- shares of its health it murmurs at
Mattressmind.CALL_IMPS = 3 -- each time (more players, more: Bosses.plus)
Mattressmind.CALL_CACOS = 1
Mattressmind.SAY_EVERY = { 9, 14 }
Mattressmind.DROPS = 60

-- Its chaingun: the weapons feature's minigun, its numbers.
Mattressmind.GUN = { damage = 6, spread = 0.07 }

Mattressmind.lines = {
  "I AM THE MIND.",
  "...five more minutes...",
  "THE MATTRESS IS MINE. THE MATTRESS IS ME.",
  "YOU WILL LIE DOWN.",
  "SLEEP IS COMPULSORY.",
  "DO NOT DISTURB.",
  "...just resting my eyes...",
  "SNOOZE. SNOOZE. SNOOZE.",
  "...comfy...",
  "Who... set... the alarm...",
}
Mattressmind.LINE = { intro = 1, call = 2, taunt = { 3, 4, 5, 6, 8 }, phase2 = 7, heal = 9, down = 10 }

local BRAIN = { 0.92, 0.58, 0.60 }
local RED = { 1.00, 0.18, 0.10 }
local SLEEP = { 0.55, 0.62, 0.95 }
local ORANGE = { 1.00, 0.55, 0.12 }

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local gun = nil
--- Its chaingun: the minigun, common, with its numbers on it.
function Mattressmind.gun()
  gun = gun or setmetatable(Mattressmind.GUN, { __index = Tiers.apply(Guns.minigun, Tiers.DEFAULT) })
  return gun
end

-- The beast -------------------------------------------------------------------

function Mattressmind.new(x, y, facing, hp, nav, home)
  return setmetatable({
    x = x, y = y, facing = facing, aim = facing, hp = hp, max = hp, nav = nav, home = home, time = 0, move = nil,
    moveT = 0, attackIn = 1.5, slamIn = 1, yawnIn = 4, sayIn = 6, frozen = 0, stuck = 0, roundIn = 0,
    phase2 = false, calls = 0, breath = Stamina.new(Mattressmind.BREATH), running = false, mode = "hunt", side = 1,
  }, Mattressmind)
end

local function fits(x, y)
  local r = Mattressmind.RADIUS
  local k = r * 0.7
  return not (Ground.blocked(x, y) or Ground.blocked(x - r, y) or Ground.blocked(x + r, y)
    or Ground.blocked(x, y - r) or Ground.blocked(x, y + r) or Ground.blocked(x - k, y - k)
    or Ground.blocked(x + k, y - k) or Ground.blocked(x - k, y + k) or Ground.blocked(x + k, y + k))
end

function Mattressmind:turn(angle, dt, rate)
  local d = Sight.angleDiff(angle, self.facing)
  local step = (rate or Mattressmind.TURN) * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

--- Walk along `angle` at `speed`, whichever way it faces, sliding along walls.
function Mattressmind:walk(angle, speed, dt)
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

function Mattressmind:pace()
  return self.breath:pace(Mattressmind.WALK, Mattressmind.STROLL)
end

--- Where its chaingun's end is.
function Mattressmind:muzzle()
  return self.x + math.cos(self.aim) * Mattressmind.MUZZLE, self.y + math.sin(self.aim) * Mattressmind.MUZZLE
end

-- Server --------------------------------------------------------------------

local sv = nil -- { m, spec, awake, syncIn, down }

--- It on `map`'s plateau (its `horde.boss` of kind "mattressmind"), finding
--- its way on `nav`. Nothing on a map without it.
function Mattressmind.serverStart(server, map, nav)
  Mattressmind.serverStop(server)
  local spec = map.horde and map.horde.boss
  if not (spec and spec.kind == "mattressmind") then
    return
  end
  local facing = spec.facing or math.pi / 2
  sv = { m = Mattressmind.new(spec.x, spec.y, facing, Bosses.health(Mattressmind.HEALTH, server), nav,
    { x = spec.x, y = spec.y, facing = facing }), spec = spec, awake = false, syncIn = 0 }
end

function Mattressmind.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("SM_STATE", server.tick))
  end
end

--- Is the gate still locked (it is up)?
function Mattressmind.serverLocked()
  return sv ~= nil and not sv.down
end

local function inBox(b, x, y)
  return b ~= nil and x >= b.x0 and x <= b.x1 and y >= b.y0 and y <= b.y1
end

--- Is (x, y) on its patch (the spec's `zone`)? It never leaves it.
function Mattressmind.inZone(x, y)
  return sv ~= nil and inBox(sv.spec.zone, x, y)
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    server:broadcast(Protocol.encode("SM_SAY", Mattressmind.LINE.intro))
  end
end

--- Its company: imps and Cacodaemons up onto the plateau's edges, at whoever it has.
local function callCompany(server)
  local Horde = require("src.features.eternal-mood.horde")
  local m = sv.m
  local z = sv.spec.zone
  local _, tx, ty = Brain.target(m, server)
  tx, ty = tx or m.x, ty or m.y
  local imps = Bosses.plus(Mattressmind.CALL_IMPS, server)
  for k = 1, imps do
    local side = k % 2 == 0 and 1 or -1
    local x = side > 0 and z.x1 - 80 or z.x0 + 80
    Horde.serverCall(server, "imp", x, z.y0 + (z.y1 - z.y0) * (0.25 + 0.2 * k), tx, ty)
  end
  for k = 1, Bosses.plus(Mattressmind.CALL_CACOS, server) do
    local side = k % 2 == 0 and -1 or 1
    Horde.serverCall(server, "caco", tx + side * 700, ty - 200, tx, ty)
  end
end

--- Players within reach of a yawn are drawn in towards it, stopping at walls.
local function pull(server, dt)
  local m = sv.m
  for _, p in pairs(server.players) do
    local body = p.body
    if body and not p.vehicle and not body.dead and Features.present(p) then
      local dx, dy = m.x - body.x, m.y - body.y
      local d = math.sqrt(dx * dx + dy * dy)
      if d <= Mattressmind.YAWN_REACH and d > Mattressmind.RADIUS + 20 then
        local step = Mattressmind.YAWN_PULL * dt
        local nx, ny = body.x + dx / d * step, body.y + dy / d * step
        if not Sight.blocked(nx, ny) then
          body.x, body.y = nx, ny
        end
      end
    end
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local MOVE = { spin = 1, fire = 2, slam = 3, yawn = 4 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local m = sv.m
  local stamina, winded = m.breath:wire()
  local msg = Protocol.encode("SM_STATE", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
    fmt(math.max(0, m.hp)), fmt(m.max), MOVE[m.move] or 0, ("%.3f"):format(m.aim), m.phase2 and 1 or 0,
    sv.awake and 1 or 0, stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Mattressmind.serverStep(server, dt)
  if not sv or sv.down then
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
        server:broadcast(Protocol.encode("SM_SAY", e[2]))
      elseif e[1] == "round" then
        local weapons = Features.byName.weapons
        if weapons and weapons.serverFireFrom then
          local Horde = require("src.features.eternal-mood.horde")
          weapons:serverFireFrom(server, 0, e[2], e[3], e[4], Mattressmind.gun(), Horde.FROM)
        end
      elseif e[1] == "hit" then
        server:broadcast(Protocol.encode("SM_HIT", e[2], fmt(e[3]), fmt(e[4])))
      elseif e[1] == "call" then
        callCompany(server)
      end
    end
    if sv.m.move == "yawn" then
      pull(server, dt)
    end
  end
  sync(server)
end

--- Down: its last word, its wreck, koins, the kill, and the gate unlocked.
local function down(server, by, angle)
  local m = sv.m
  sv.down = true
  server:broadcast(Protocol.encode("SM_SAY", Mattressmind.LINE.down))
  server:broadcast(Protocol.encode("SM_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)))
  server:broadcast(Protocol.encode("SM_STATE", server.tick + 1))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, m.x, m.y, Mattressmind.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, m.x + 80, m.y)
    pickups:serverDropEnemy(server, m.x - 80, m.y)
  end
  Features.call("serverKill", server, { kind = "boss", x = m.x, y = m.y, by = by, angle = angle })
end

--- A round through (x, y), going along `angle`: the `serverShotAt`
--- convention. Only a player's reaches it (and wakes it). One coming at it
--- from in front hits the mattress and does FRONT of its damage. Returns
--- true when it hit.
function Mattressmind.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local m = sv.m
  if dist2(x, y, m.x, m.y) > (Mattressmind.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  wake(server)
  damage = damage or 20
  if angle and math.cos(angle - m.facing) < -0.5 then -- coming at its face: into the mattress
    damage = damage * Mattressmind.FRONT
    if (m.soakIn or 0) <= m.time then
      m.soakIn = m.time + 0.25
      server:broadcast(Protocol.encode("SM_HIT", "soak", fmt(x), fmt(y)))
    end
  end
  m.hp = m.hp - damage
  if m.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

function Mattressmind.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.m.x, sv.m.y) <= radius * radius then
    sv.m.frozen = math.max(sv.m.frozen, seconds)
  end
end

function Mattressmind.serverPlayerJoined(server, player)
  if sv and sv.down and not player.bot then
    local m = sv.m
    server:send(player, Protocol.encode("SM_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)), true)
  end
end

--- For tests.
function Mattressmind.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil
local say = nil
local rings = {} -- { x, y, t, r }
local puffs = {} -- { x, y, t }: stuffing knocked out of the mattress
local wreck = nil -- { x, y, angle } where it went down
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local RING_SHOWN = 0.5
local PUFF_SHOWN = 0.6

function Mattressmind.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2600)
    return src
  end
  bank.spin = make(0.9, 0.6, function(buf) -- the chaingun winding up
    buf:sweep(0, 0.85, 120, 900, { wave = "square", amp = 0.2, decay = 2 })
    buf:sweep(0, 0.85, 60, 450, { wave = "saw", amp = 0.18, decay = 2 })
    buf:lowpass(3200)
  end)
  bank.slam = make(0.7, 0.9, function(buf)
    buf:noiseBurst(0, 0.3, { amp = 0.8, decay = 0.08 })
    buf:sweep(0, 0.6, 100, 35, { wave = "sine", amp = 0.9, decay = 0.2 })
    buf:lowpass(2200)
  end)
  bank.yawn = make(2.2, 0.8, function(buf) -- a huge, slow yawn, falling
    buf:sweep(0, 2.1, 160, 70, { wave = "saw", amp = 0.4, attack = 0.4, decay = 99, vibRate = 3, vibDepth = 1 })
    buf:sweep(0, 2.1, 320, 140, { wave = "sine", amp = 0.2, attack = 0.5, decay = 99 })
    buf:noiseBurst(0, 2.0, { amp = 0.12, decay = 1.2 })
    buf:lowpass(900)
  end)
  bank.snap = make(0.4, 0.9, function(buf) -- the yawn shut
    buf:noiseBurst(0, 0.1, { amp = 0.9, decay = 0.03 })
    buf:sweep(0, 0.3, 300, 80, { wave = "sine", amp = 0.6, decay = 0.1 })
    buf:lowpass(2500)
  end)
  bank.soak = make(0.15, 0.5, function(buf) -- a round into the mattress: a dull thup
    buf:noiseBurst(0, 0.1, { amp = 0.5, decay = 0.03 })
    buf:lowpass(700)
  end)
  bank.voice = make(1.4, 0.8, function(buf) -- I AM THE MIND: a vast, low murmur
    buf:sweep(0, 1.3, 80, 70, { wave = "saw", amp = 0.4, attack = 0.1, decay = 1.2, vibRate = 4, vibDepth = 1 })
    buf:sweep(0, 1.3, 160, 140, { wave = "square", amp = 0.12, attack = 0.1, decay = 1.2 })
    buf:drive(2)
    buf:lowpass(800)
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
    s:setPitch(0.94 + random() * 0.12)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Mattressmind.clear()
  shown, say, rings, puffs, wreck, lastTick = nil, nil, {}, {}, nil, 0
end

function Mattressmind.update(dt)
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
  for _, list in ipairs({ rings, puffs }) do
    for i = #list, 1, -1 do
      list[i].t = list[i].t + dt
      if list[i].t > (list == rings and RING_SHOWN or PUFF_SHOWN) then
        table.remove(list, i)
      end
    end
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

local function spec()
  local c = Features.byName["city-map"]
  local s = c and c.map and c.map.horde and c.map.horde.boss
  return s and s.kind == "mattressmind" and s or nil
end

--- The Snooze Gate while it is up: bars of light across the doors, LOCKED.
local function drawLock()
  local s = spec()
  local g = s and s.gate
  if not g or wreck then
    return
  end
  local pulse = 0.5 + 0.4 * math.abs(math.sin(clock * 2.5))
  love.graphics.setColor(SLEEP[1], SLEEP[2], SLEEP[3], 0.35 * pulse)
  love.graphics.rectangle("fill", g.x + g.w * 0.3, g.y + g.h * 0.35, g.w * 0.4, g.h * 0.65)
  love.graphics.setColor(SLEEP[1], SLEEP[2], SLEEP[3], 0.8 * pulse)
  love.graphics.setLineWidth(4)
  for k = 1, 4 do
    local y = g.y + g.h * 0.35 + k * g.h * 0.13
    love.graphics.line(g.x + g.w * 0.3, y, g.x + g.w * 0.7, y)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf("LOCKED", g.x + 2, g.y + g.h + 8, g.w, "center")
  love.graphics.setColor(SLEEP[1], SLEEP[2], SLEEP[3], 0.6 + 0.4 * pulse)
  love.graphics.printf("LOCKED", g.x, g.y + g.h + 6, g.w, "center")
end

function Mattressmind.drawBelowCars()
  drawLock()
  if wreck then
    Look.drawWreck(wreck, clock)
  end
  local m = shown
  if m and m.move == 3 then -- legs up: how far the slam reaches
    local k = math.min(1, (clock - (m.moveAt or clock)) / Mattressmind.SLAM_WINDUP)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.12 + 0.18 * k)
    love.graphics.circle("fill", m.dx, m.dy, Mattressmind.SLAM_RADIUS, 40)
  elseif m and m.move == 4 then -- yawning: the pull, rings drawing in
    for k = 0, 3 do
      local f = 1 - ((clock * 0.8 + k / 4) % 1)
      love.graphics.setColor(SLEEP[1], SLEEP[2], SLEEP[3], 0.35 * (1 - f))
      love.graphics.setLineWidth(3)
      love.graphics.circle("line", m.dx, m.dy, Mattressmind.YAWN_REACH * f, 48)
    end
    love.graphics.setLineWidth(1)
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

function Mattressmind.drawAboveCars()
  local m = shown
  if m then
    Look.draw(m, clock)
    if say then
      require("src.features.eternal-mood.horde").drawBubble(m.dx, m.dy - Mattressmind.RADIUS - 30, say.text)
    end
  end
  for _, p in ipairs(puffs) do -- stuffing in the air
    local k = p.t / PUFF_SHOWN
    for j = 0, 3 do
      local a = j * 1.6 + p.x * 0.01
      love.graphics.setColor(0.95, 0.93, 0.88, 0.8 * (1 - k))
      love.graphics.circle("fill", p.x + math.cos(a) * 18 * k, p.y + math.sin(a) * 18 * k - 10 * k, 4, 8)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Mattressmind.drawNightLights(glow)
  local m = shown
  if m then
    glow(m.dx, m.dy, 170, BRAIN, 0.45)
    if m.move == 1 or m.move == 2 then
      glow(m.dx + math.cos(m.aim) * Mattressmind.MUZZLE, m.dy + math.sin(m.aim) * Mattressmind.MUZZLE,
        m.move == 2 and 150 or 70, ORANGE, m.move == 2 and 1 or 0.6)
    end
    if m.move == 4 then
      glow(m.dx, m.dy, 300, SLEEP, 0.5)
    end
  end
  local s = spec()
  local g = s and s.gate
  if g and not wreck then
    glow(g.x + g.w / 2, g.y + g.h * 0.6, 260, SLEEP, 0.5)
  end
end

--- Its bar, once it is fighting.
function Mattressmind.drawHUD()
  if not (shown and shown.awake) then
    return
  end
  Bar.draw({
    title = "THE SPIDER MATTRESSMIND", titleColor = BRAIN, fill = shown.phase2 and SLEEP or RED, hp = shown.hp,
    max = shown.max, stamina = shown.stamina, staminaMax = 100, winded = shown.winded,
  })
end

Mattressmind.clientMessages = {
  SM_STATE = function(_client, args)
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
        play("spin")
      elseif move == 4 then
        play("yawn")
      end
    end
    m.move = move
    m.aim = tonumber(args[8]) or m.facing
    m.phase2 = args[9] == "1"
    m.awake = args[10] == "1"
    m.stamina, m.winded = Stamina.read(args, 11)
  end,
  SM_SAY = function(_client, args)
    local line = tonumber(args[1]) or 0
    local text = Mattressmind.lines[line]
    if text then
      say = { text = text, t = 1.5 + #text * 0.05 }
      if line == Mattressmind.LINE.intro or line == Mattressmind.LINE.call then
        play("voice")
      end
    end
  end,
  SM_HIT = function(_client, args)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    if args[1] == "slam" then
      play("slam", x, y)
      rings[#rings + 1] = { x = x, y = y, t = 0, r = Mattressmind.SLAM_RADIUS }
    elseif args[1] == "snap" then
      play("snap", x, y)
    elseif args[1] == "soak" then
      play("soak", x, y)
      puffs[#puffs + 1] = { x = x, y = y, t = 0 }
    end
  end,
  SM_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      wreck = { x = x, y = y, angle = angle }
      play("slam", x, y)
    end
    shown = nil
  end,
}

Brain = require("src.features.eternal-mood.mattressmind_brain")

return Mattressmind
