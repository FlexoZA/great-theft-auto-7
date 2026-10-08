-- Crazy Karen's brain, on the host: what she does each tick. Her feature
-- (init.lua) owns her body, the cars that ram her, the scream landing,
-- her health and the wire; it hands her in as `b` and its own table, with
-- her numbers, as `k`.
--
-- She is always in one of these, the later ones cutting in on the earlier:
--
--   idle     nobody within `aggroRange`: she rants where she stands, and
--            stomps back to her turning circle if a chase took her off it
--   charge   somebody near: she comes at the nearest at full tilt (a waddle
--            while winded), round the houses on the walking grid when they
--            are in the way, and slaps whatever she reaches, car or walker
--   scream   every `screamEvery` seconds, breath allowing, she plants her
--            feet and draws breath at whoever is near; `screamDelay` later
--            it lands where she aimed (init.lua hurts whoever is there)
--   heal     badly hurt (bosses/heal.lua): she marches off to the nearest
--            medkit lying within reach, complaining, and takes it
--
-- A freeze roots her to the spot; a stink sends her off away from it as
-- fast as her legs allow, and so does a freeze's warning ring or anything
-- else a player's ability is about to land on her (bosses/dodge.lua), even
-- mid-scream.

local Features = require("src.features")
local Car = require("src.car")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Solid ground, through the `blocksPoint` convention, tested at the four
--- extremes of her body (`r` across).
local function blockedAt(x, y, r)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along; wedged, she
--- sidesteps for a moment.
local function walk(k, b, angle, speed, dt)
  if b.sidestep > 0 then
    b.sidestep = b.sidestep - dt
    angle = angle + b.side * math.pi / 2
  end
  local px, py = b.x, b.y
  local nx = b.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, b.y, k.radius) then
    b.x = nx
  end
  local ny = b.y + math.sin(angle) * speed * dt
  if not blockedAt(b.x, ny, k.radius) then
    b.y = ny
  end
  if dist2(b.x, b.y, px, py) < (speed * dt * 0.4) ^ 2 then
    b.stuck = b.stuck + dt
    if b.stuck > 0.4 then
      b.stuck, b.sidestep, b.side = 0, 0.6, -b.side
    end
  else
    b.stuck = 0
  end
end

--- Her pace: full tilt with breath in her, a walk without.
local function pace(k, b)
  return b.breath:pace(k.chargeSpeed, k.walkSpeed)
end

--- Towards (x, y): straight at it when nothing is in the way, round the
--- houses on her walking grid when something is. True once she is there.
local function goTo(k, b, x, y, speed, dt)
  if not b.nav or Sight.clear(b.x, b.y, x, y) then
    b.goal = nil
    b.facing = math.atan2(y - b.y, x - b.x)
    walk(k, b, b.facing, speed, dt)
    return dist2(b.x, b.y, x, y) < 16 * 16
  end
  local g = b.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or b.time > g.replanAt then
    local corners = b.nav:path(b.x, b.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = b.time + 1.2 }
    b.goal = g
  end
  local c = g.corners[g.at]
  if dist2(b.x, b.y, c.x, c.y) < 20 * 20 and g.at < #g.corners then
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  b.facing = math.atan2(c.y - b.y, c.x - b.x)
  walk(k, b, b.facing, speed, dt)
  return false
end

--- Everyone's body this tick, and the nearest one to her.
local function nearestBody(server, b)
  local best, bestD2, bx, by, onFoot
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y, foot = Features.bodyPose(server, p)
      local d2 = dist2(x, y, b.x, b.y)
      if not bestD2 or d2 < bestD2 then
        best, bestD2, bx, by, onFoot = p, d2, x, y, foot
      end
    end
  end
  return best, bestD2, bx, by, onFoot
end

--- Should she go for a medkit now? Looks once a second while she is hurt.
local function wantsHeal(b)
  if b.medkit then
    if Heal.there(b.medkit) then
      return true
    end
    b.medkit, b.goal = nil, nil -- somebody got there first
  end
  if not Heal.wants(b.hp, b.max) or b.time < (b.healLook or 0) then
    return false
  end
  b.healLook = b.time + Heal.checkEvery
  b.medkit, b.goal = Heal.find(b.x, b.y), nil
  return b.medkit ~= nil
end

--- What she does this tick. Returns whether she ran flat out (it costs her
--- breath) and what the others should hear about: { "say", index },
--- { "aim", x, y } (a scream coming down there) or { "scream" } (it lands).
function Brain.think(k, b, server, dt)
  local events = {}
  b.time = (b.time or 0) + dt
  b.slapTimer = b.slapTimer - dt
  b.sayTimer = b.sayTimer - dt
  if b.sayTimer <= 0 then
    b.sayTimer = 4 + random() * 4
    events[#events + 1] = { "say", random(k.TALK) }
  end

  if (b.frozen or 0) > 0 then
    b.frozen = b.frozen - dt -- frozen: no charging, no slapping
    b.charging = false
    return false, events
  end
  Dodge.step(b, k.radius)
  if b.panic then
    -- A stink: away from it, nose held, whatever else she was doing, as
    -- fast as her legs allow.
    b.charging, b.scream = false, nil
    b.panic.left = b.panic.left - dt
    b.facing = math.atan2(b.y - b.panic.y, b.x - b.panic.x)
    walk(k, b, b.facing, pace(k, b), dt)
    if b.panic.left <= 0 then
      b.panic = nil
    end
    return not b.breath:winded(), events
  end
  if b.scream then
    -- Feet planted, drawing breath; when the time is up it lands.
    b.charging = false
    b.scream.t = b.scream.t - dt
    if b.scream.t <= 0 then
      events[#events + 1] = { "scream" }
    end
    return false, events
  end

  if wantsHeal(b) then
    b.mode, b.charging = "heal", not b.breath:winded()
    local m = b.medkit
    goTo(k, b, m.x, m.y, pace(k, b), dt)
    if Heal.within(m, b.x, b.y, k.radius) then
      local got = Heal.take(server, m)
      b.hp = math.min(b.max, b.hp + got)
      b.medkit, b.goal = nil, nil
      if got > 0 then
        b.sayTimer = 3
        events[#events + 1] = { "say", k.TALK + random(#k.lines - k.TALK) }
      end
    end
    return b.charging, events
  end

  local target, d2, tx, ty, onFoot = nearestBody(server, b)
  if not (target and d2 <= k.aggroRange ^ 2) then
    -- Idle: back to her turning circle if a chase took her off it.
    b.mode, b.charging = "idle", false
    if b.homeX and dist2(b.x, b.y, b.homeX, b.homeY) > 60 * 60 then
      goTo(k, b, b.homeX, b.homeY, k.walkSpeed, dt)
    end
    return false, events
  end

  b.mode = "charge"
  b.screamTimer = b.screamTimer - dt
  -- A scream takes breath: none while she is winded or nearly so (the
  -- timer stays run down, so it comes as soon as she has it back).
  if b.screamTimer <= 0 and d2 <= k.screamRange ^ 2 and b.breath:has(k.screamStamina) then
    b.screamTimer = k.screamEvery
    b.breath:spend(k.screamStamina)
    b.scream = { x = tx, y = ty, t = k.screamDelay }
    b.facing = math.atan2(ty - b.y, tx - b.x)
    b.charging = false
    events[#events + 1] = { "aim", tx, ty }
    return false, events
  end
  b.charging = not b.breath:winded() -- winded, she comes on at a waddle
  local reach = k.radius + k.slapReach + (onFoot and 0 or Car.HEIGHT / 2)
  if d2 > reach * reach then
    goTo(k, b, tx, ty, pace(k, b), dt)
    return b.charging, events
  end
  b.facing = math.atan2(ty - b.y, tx - b.x)
  if b.slapTimer <= 0 then
    b.slapTimer = k.slapInterval
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, target, nil, k.slapDamage, b.facing, "melee")
    end
  end
  return false, events
end

return Brain
