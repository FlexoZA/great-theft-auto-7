-- Loose squirrels: Bigfoot's squirrels (bigfoot.lua) without Bigfoot, set
-- down anywhere by another feature (`Events:serverSummonSquirrels`: the
-- tutorial's scrap yard, tutorial/waves.lua). They come out of the ground
-- chittering, sit a moment, then run at the nearest player in sight and
-- bite: a nip of `bite` damage, then they back off for `backOff` seconds
-- and come again. Unlike Bigfoot's they never burst on a player or on
-- their own: they are there until they are shot (one round does it) or
-- the map changes.
--
-- They are drawn and heard like his (alien-hunt/render.lua, sounds.lua),
-- steer the same way (`Squirrels.chase`, which bigfoot.lua uses too), and
-- run from a fart and stand still in a freeze like his. Unlike an event
-- they live on any map; the events feature runs them alongside whichever
-- event is on, and clears them on a map change.
--
-- Messages (the events feature registers them)
--   server -> all  ESQ_STATE <tick> [<id> <x> <y> <facing>]...   (unreliable, 15 Hz; every loose squirrel)
--   server -> all  ESQ_OUT   <x> <y>                            some came out of the ground there
--   server -> all  ESQ_POP   <x> <y> <angle>                    one was shot

local Protocol = require("src.net.protocol")
local Drawn = require("src.features.drawn")
local Features = require("src.features")
local Body = require("src.body")
local Car = require("src.car")
local Render = require("src.features.alien-hunt.render")
local Sounds = require("src.features.alien-hunt.sounds")

local Squirrels = {}

-- Tuning ------------------------------------------------------------------
Squirrels.health = 10 -- one round of anything
Squirrels.bulletDamage = 20 -- what a round takes off one (Bigfoot's)
Squirrels.radius = 7
Squirrels.speed = 230 -- px/s; slower than Bigfoot's (340), so a new shot can hit one; a sprint does not outrun it
Squirrels.turn = 5 -- rad/s, harder close in (`homing`), as his
Squirrels.homing = 140
Squirrels.wait = { 0.6, 1.6 } -- seconds a new one sits before it goes
Squirrels.range = 3000 -- px; what one goes after: across any yard
Squirrels.bite = 4 -- damage a nip does
Squirrels.backOff = 0.7 -- seconds one runs off after a bite before it comes again

local SYNC_EVERY = 2 -- server ticks between ESQ_STATE packets
local SMOOTHING = 15 -- per second, the easing of what is drawn
local SNAP = 150 -- px; a jump this big is a spawn, not a step

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Turn `from` towards `to` by at most `step` radians.
local function turn(from, to, step)
  local d = (to - from + math.pi) % (2 * math.pi) - math.pi
  return from + math.max(-step, math.min(step, d))
end

--- Squirrel `s` ({ x, y, facing }) running at (tx, ty) for `dt` at `speed`:
--- it swerves at `turnRate` rad/s, up to four times as hard within
--- `homing` px, or it would circle a player standing still.
function Squirrels.chase(s, tx, ty, dt, speed, turnRate, homing)
  local d = math.sqrt(dist2(tx, ty, s.x, s.y))
  local rate = turnRate * (1 + 3 * math.max(0, 1 - d / homing))
  Squirrels.run(s, math.atan2(ty - s.y, tx - s.x), dt, speed, rate)
end

--- Squirrel `s` turning towards `want` at `rate` rad/s and running on.
function Squirrels.run(s, want, dt, speed, rate)
  s.facing = turn(s.facing, want, rate * dt)
  s.x, s.y = s.x + math.cos(s.facing) * speed * dt, s.y + math.sin(s.facing) * speed * dt
end

-- Server --------------------------------------------------------------------

local sv = nil -- { squirrels = { id -> s }, count, nextId, syncIn }

local function fresh()
  return { squirrels = {}, count = 0, nextId = 1, syncIn = 0 }
end

--- Gone, all of them (a new game, a map change).
function Squirrels.serverClear(server)
  local had = sv and sv.count > 0
  sv = fresh()
  if had and server then
    server:broadcast(Protocol.encode("ESQ_STATE", server.tick))
  end
end

--- `count` squirrels out of the ground round (x, y), within `r` px.
function Squirrels.serverSummon(server, x, y, count, r)
  sv = sv or fresh()
  for i = 1, count do
    local a = (i / count) * math.pi * 2 + random() * 0.5
    local d = random() * (r or 0)
    local id = sv.nextId
    sv.nextId = id + 1
    sv.squirrels[id] = {
      id = id, x = x + math.cos(a) * d, y = y + math.sin(a) * d, facing = a, hp = Squirrels.health,
      wait = Squirrels.wait[1] + random() * (Squirrels.wait[2] - Squirrels.wait[1]), frozen = 0, away = 0,
    }
  end
  sv.count = sv.count + count
  sv.syncIn = 0
  server:broadcast(Protocol.encode("ESQ_OUT", fmt(x), fmt(y)))
end

--- How many are loose.
function Squirrels.serverCount()
  return sv and sv.count or 0
end

--- The nearest player in sight within range: { player, x, y, onFoot } or nil.
local function target(server, s)
  local best, bestD2 = nil, Squirrels.range ^ 2
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local d2 = dist2(x, y, s.x, s.y)
      if d2 < bestD2 then
        best, bestD2 = { player = p, x = x, y = y, onFoot = onFoot }, d2
      end
    end
  end
  return best
end

local function bite(server, player, angle)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, player, nil, Squirrels.bite, angle, "melee")
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for id, s in pairs(sv.squirrels) do
    parts[#parts + 1] = id
    parts[#parts + 1] = fmt(s.x)
    parts[#parts + 1] = fmt(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
  end
  local msg = Protocol.encode("ESQ_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Squirrels.serverStep(server, dt)
  if not (sv and sv.count > 0) then
    return
  end
  for _, s in pairs(sv.squirrels) do
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    elseif s.wait > 0 then
      s.wait = s.wait - dt
    elseif s.panic then
      Squirrels.run(s, math.atan2(s.y - s.panic.y, s.x - s.panic.x), dt, Squirrels.speed, Squirrels.turn * 2)
      s.panic.left = s.panic.left - dt
      s.panic = s.panic.left > 0 and s.panic or nil
    elseif s.away > 0 then
      -- Backing off after a bite, the way it was going.
      s.away = s.away - dt
      Squirrels.run(s, s.facing, dt, Squirrels.speed * 0.8, 0)
    else
      local t = target(server, s)
      if t then
        Squirrels.chase(s, t.x, t.y, dt, Squirrels.speed, Squirrels.turn, Squirrels.homing)
        local reach = Squirrels.radius + (t.onFoot and Body.RADIUS or Car.WIDTH / 2 + 4)
        if dist2(t.x, t.y, s.x, s.y) <= reach * reach then
          bite(server, t.player, s.facing)
          s.away, s.facing = Squirrels.backOff, s.facing + math.pi + (random() - 0.5) * 1.2
        end
      end
    end
  end
  sync(server)
end

--- A round through (x, y): the `serverShotAt` convention. One round
--- bursts one squirrel.
function Squirrels.serverShotAt(server, x, y, radius, by, angle)
  if not (sv and sv.count > 0) then
    return false
  end
  for id, s in pairs(sv.squirrels) do
    if dist2(s.x, s.y, x, y) < (radius + Squirrels.radius + 3) ^ 2 then
      s.hp = s.hp - Squirrels.bulletDamage
      if s.hp <= 0 then
        sv.squirrels[id] = nil
        sv.count = sv.count - 1
        server:broadcast(Protocol.encode("ESQ_POP", fmt(s.x), fmt(s.y), ("%.2f"):format(s.facing)))
        Features.call("serverKill", server, { kind = "animal", x = s.x, y = s.y, by = by ~= 0 and by or nil,
          angle = angle })
      end
      return true
    end
  end
  return false
end

--- Every one loose, for the audit (tools/audit).
function Squirrels.serverEnemies(add)
  for _, s in pairs(sv and sv.squirrels or {}) do
    add({ id = s, kind = "events/loose-squirrel", x = s.x, y = s.y, hp = s.hp, radius = Squirrels.radius })
  end
end

--- A fart at (x, y): they run from it a moment.
function Squirrels.serverPanicArea(x, y, radius)
  for _, s in pairs(sv and sv.squirrels or {}) do
    if dist2(s.x, s.y, x, y) <= (radius + Squirrels.radius) ^ 2 then
      s.panic = { x = x, y = y, left = 0.5 }
    end
  end
end

--- A freeze at (x, y): they stand still.
function Squirrels.serverFreezeArea(x, y, radius, seconds)
  for _, s in pairs(sv and sv.squirrels or {}) do
    if dist2(s.x, s.y, x, y) <= (radius + Squirrels.radius) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

-- Client --------------------------------------------------------------------

local cl = { squirrels = {}, pops = {}, lastTick = 0 }
local time = 0

function Squirrels.clear()
  cl = { squirrels = {}, pops = {}, lastTick = 0 }
end

function Squirrels.update(dt)
  time = time + dt
  for _, s in pairs(cl.squirrels) do
    Drawn.step(s, dt, SMOOTHING, SNAP)
  end
  for i = #cl.pops, 1, -1 do
    local p = cl.pops[i]
    p.t = p.t + dt
    if p.t > 0.8 then
      table.remove(cl.pops, i)
    end
  end
end

--- A squirrel bursting: a red puff swelling out and fading (as Bigfoot's).
local function drawPop(p)
  local k = p.t / 0.8
  love.graphics.setColor(0.8, 0.1, 0.08, (1 - k) * 0.7)
  love.graphics.circle("fill", p.x, p.y, 6 + 18 * math.min(1, k * 3))
  love.graphics.setColor(1, 0.75, 0.4, (1 - k * 3) * 0.9)
  love.graphics.circle("fill", p.x, p.y, 5 + 8 * k)
end

function Squirrels.drawAboveCars()
  for _, s in pairs(cl.squirrels) do
    Render.squirrel(s, time)
  end
  for _, p in ipairs(cl.pops) do
    drawPop(p)
  end
  love.graphics.setColor(1, 1, 1)
end

Squirrels.clientMessages = {
  ESQ_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick < cl.lastTick then
      return
    end
    cl.lastTick = tick
    local seen = {}
    for i = 2, #args - 3, 4 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = cl.squirrels[id] or { dx = x, dy = y, bob = random() * 6 }
        Drawn.heard(s, x, y, tick)
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        cl.squirrels[id] = s
        seen[id] = true
      end
    end
    for id in pairs(cl.squirrels) do
      if not seen[id] then
        cl.squirrels[id] = nil
      end
    end
  end,
  ESQ_OUT = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("chitter", x, y, 0.9)
    end
  end,
  ESQ_POP = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if not (x and y) then
      return
    end
    cl.pops[#cl.pops + 1] = { x = x, y = y, t = 0 }
    for id, s in pairs(cl.squirrels) do
      if dist2(s.x, s.y, x, y) < 4 then
        cl.squirrels[id] = nil -- gone now, not at the next sync
      end
    end
    if Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 1.4 + random() * 0.3)
    end
  end,
}

return Squirrels
