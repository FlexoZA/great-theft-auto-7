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
--            while winded), round the houses on the walking grid (as wide
--            as she is) when her whole width can't get straight there, and
--            slaps whatever she reaches, car or walker
--   scream   every `screamEvery` seconds, breath allowing, she plants her
--            feet and draws breath at whoever is near; `screamDelay` later
--            it lands where she aimed (init.lua hurts whoever is there)
--   heal     badly hurt (bosses/heal.lua): she marches off to the nearest
--            medkit lying within reach, complaining, and takes it; with
--            somebody near she kites there, walking it with her eyes on
--            them, slapping whoever comes in reach and screaming only
--            while the medkit is still more than `KITE_FAR` off
--
-- A freeze roots her to the spot; a stink sends her off away from it as
-- fast as her legs allow, and so does a freeze's warning ring or anything
-- else a player's ability is about to land on her (bosses/dodge.lua), even
-- mid-scream.

local Features = require("src.features")
local Car = require("src.car")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")

local Brain = {}

local random = love.math.random

-- Tuning ------------------------------------------------------------------
Brain.KITE_FAR = 260 -- px; kiting to a medkit further than this, she will still stop to scream

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Solid ground under (x, y), through the `blocksPoint` convention. One
--- function for good: Walk.nav keeps her walking grid by it.
local function blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- One step (bosses/walk.lua): slid along a wall, felt round a corner.
local function walk(k, b, angle, speed, dt)
  Walk.step(b, blocked, angle, speed, dt, k.radius)
end

--- Her pace: full tilt with breath in her, a walk without.
local function pace(k, b)
  return b.breath:pace(k.chargeSpeed, k.walkSpeed)
end

--- Towards (x, y): straight at it when her whole width gets there, round
--- the houses on her walking grid (as wide as she is) when not. Facing
--- `face` when given (kiting: her eyes on somebody), where she goes if
--- not. True once she is there.
local function goTo(k, b, x, y, speed, dt, face)
  local angle
  if not b.nav or Walk.wideClear(blocked, b.x, b.y, x, y, k.radius) then
    b.route = nil
    if dist2(b.x, b.y, x, y) < 16 * 16 then
      return true
    end
    angle = math.atan2(y - b.y, x - b.x)
  else
    local there
    angle, there = Walk.route(b, Walk.nav(b.nav, blocked, k.radius), x, y, b.time)
    if not angle then
      return there -- there, or no way she fits: she holds rather than grind into a wall
    end
  end
  b.facing = face or angle
  walk(k, b, angle, speed, dt)
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
    b.medkit, b.route = nil, nil -- somebody got there first
  end
  if not Heal.wants(b.hp, b.max) or b.time < (b.healLook or 0) then
    return false
  end
  b.healLook = b.time + Heal.checkEvery
  b.medkit, b.route = Heal.find(b.x, b.y), nil
  return b.medkit ~= nil
end

--- A scream at (tx, y) if it is due, in range and she has the breath:
--- feet planted from now until it lands. True when she starts one.
local function tryScream(k, b, d2, tx, ty, events)
  -- A scream takes breath: none while she is winded or nearly so (the
  -- timer stays run down, so it comes as soon as she has it back).
  if b.screamTimer > 0 or d2 > k.screamRange ^ 2 or not b.breath:has(k.screamStamina) then
    return false
  end
  b.screamTimer = k.screamEvery
  b.breath:spend(k.screamStamina)
  b.scream = { x = tx, y = ty, t = k.screamDelay }
  b.facing = math.atan2(ty - b.y, tx - b.x)
  b.charging = false
  events[#events + 1] = { "aim", tx, ty }
  return true
end

--- How close `target` must be for a slap to land on them.
local function reach(k, onFoot)
  return k.radius + k.slapReach + (onFoot and 0 or Car.HEIGHT / 2)
end

--- A slap at `target`, if her hand is ready.
local function slap(k, b, server, target)
  if b.slapTimer > 0 then
    return
  end
  b.slapTimer = k.slapInterval
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, target, nil, k.slapDamage * (b.power or 1), b.facing, "melee")
  end
end

--- Badly hurt, off to her medkit. With somebody near she kites there
--- (the standard's point 7): her eyes on them, walking it, a slap for
--- whoever comes in reach and a scream only while the medkit is still far
--- (it roots her). Nobody near, she runs for it.
local function heal(k, b, server, dt, events)
  b.mode = "heal"
  local m = b.medkit
  local target, d2, tx, ty, onFoot = nearestBody(server, b)
  if target and d2 <= k.aggroRange ^ 2 then
    b.screamTimer = b.screamTimer - dt
    if dist2(b.x, b.y, m.x, m.y) > Brain.KITE_FAR ^ 2 and tryScream(k, b, d2, tx, ty, events) then
      return false
    end
    b.charging = false
    local face = math.atan2(ty - b.y, tx - b.x)
    goTo(k, b, m.x, m.y, k.walkSpeed, dt, face)
    if d2 <= reach(k, onFoot) ^ 2 then
      slap(k, b, server, target)
    end
  else
    b.charging = not b.breath:winded()
    goTo(k, b, m.x, m.y, pace(k, b), dt)
  end
  if Heal.within(m, b.x, b.y, k.radius) then
    local got = Heal.take(server, m)
    b.hp = math.min(b.max, b.hp + got)
    b.medkit, b.route = nil, nil
    if got > 0 then
      b.sayTimer = 3
      events[#events + 1] = { "say", k.TALK + random(#k.lines - k.TALK) }
    end
  end
  return b.charging
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
    return heal(k, b, server, dt, events), events
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
  if tryScream(k, b, d2, tx, ty, events) then
    return false, events
  end
  b.charging = not b.breath:winded() -- winded, she comes on at a waddle
  if d2 > reach(k, onFoot) ^ 2 then
    goTo(k, b, tx, ty, pace(k, b), dt)
    return b.charging, events
  end
  b.facing = math.atan2(ty - b.y, tx - b.x)
  slap(k, b, server, target)
  return false, events
end

return Brain
