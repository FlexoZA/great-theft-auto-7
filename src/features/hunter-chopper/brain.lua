-- The Hunter-Chopper's gun, on the host: who it goes after and when it
-- fires. It works in turns:
--   scan  nobody to shoot: the gun follows the nearest player it can see
--         and is waiting for one to come round in front of it;
--   lock  it has somebody: for `lockTime` the gun tracks them quickly and a
--         beam down its aim warns them (every screen draws it), then
--   fire  a burst of `burst` rounds at the gun's rate, the gun turning
--         after them only slowly (`trackFire`), so whoever runs across its
--         line gets out of it and whoever stands still or runs straight
--         away does not;
--   rest  `rest` seconds of quiet before it looks for the next one.
-- It only goes after somebody it can see (Features.visible): within
-- `reach`, with nothing solid on the line from the muzzle, and where the
-- gun can swing to (render.lua's 70 degrees either way of the nose); lose
-- them while locking and it scans again, and lose the line while firing
-- and it stops early. Its rounds belong to nobody (weapons'
-- serverFireFrom with owner 0) and go where any round goes: cover stops
-- them.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Sight = require("src.features.d-day.sight")
local Render = require("src.features.hunter-chopper.render")

local Brain = {}

-- Tuning ------------------------------------------------------------------
Brain.reach = 700 -- px it goes after somebody from: about as far as the screen shows
Brain.lockTime = 1.0 -- seconds of warning before the first round
Brain.burst = 20 -- rounds a burst
Brain.rest = 2.2 -- seconds between a burst and the next lock
Brain.trackLock = 4 -- per second, how quickly the gun closes on its target while locking
Brain.trackFire = 1.4 -- radians a second the gun turns while firing: run across it and it can't keep up
Brain.spread = 0.035 -- radians either way a round strays (about 17 px at 500 px out)
-- The pulse gun: the rifle's rounds and sound, its own rate and bite.
Brain.gun = setmetatable({ damage = 6, cooldown = 0.075, spread = 0, speed = 1100 },
  { __index = Tiers.apply(Guns.ak47 or Guns.list[2], Tiers.DEFAULT) })

local random = love.math.random

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

function Brain.new(angle)
  return { mode = "scan", t = 0, aim = angle, target = nil, left = 0, fireIn = 0 }
end

--- Can the chopper `f` with its gun on `b.aim` get a shot at player `p`?
--- Returns where they are when it can.
local function inSight(server, f, aim, p)
  if not (p and Features.visible(server, p)) then
    return nil
  end
  local px, py = Features.bodyPose(server, p)
  if (px - f.x) ^ 2 + (py - f.y) ^ 2 > Brain.reach ^ 2 then
    return nil
  end
  if not Render.canAim(f.angle, math.atan2(py - f.y, px - f.x)) then
    return nil
  end
  local mx, my = Render.muzzle(f.x, f.y, f.angle, aim, f.altitude)
  if not Sight.clear(mx, my, px, py) then
    return nil
  end
  return px, py
end

--- The nearest player it could shoot at, or failing that the nearest it
--- can see at all (for the gun to follow while it waits).
local function pick(server, f, aim)
  local best, bestD2, near, nearD2 = nil, math.huge, nil, Brain.reach ^ 2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = (px - f.x) ^ 2 + (py - f.y) ^ 2
      if d2 < nearD2 then
        near, nearD2 = { x = px, y = py }, d2
      end
      if d2 < bestD2 and inSight(server, f, aim, p) then
        best, bestD2 = p, d2
      end
    end
  end
  return best, near
end

--- The way from the muzzle to (px, py): the gun aims down its own barrel,
--- not from the middle of the chopper, which is well behind it.
local function bearing(f, aim, px, py)
  local mx, my = Render.muzzle(f.x, f.y, f.angle, aim, f.altitude)
  return math.atan2(py - my, px - mx)
end

local function turnTo(b, want, rate, dt)
  local d = wrap(want - b.aim)
  b.aim = b.aim + math.max(-rate * dt, math.min(rate * dt, d))
end

--- One tick of the gun on chopper `f` (flight.lua's). Returns the mode it
--- is in afterwards.
function Brain.step(b, f, server, dt)
  b.t = b.t + dt
  if b.mode == "scan" or b.mode == "rest" then
    local target, near = pick(server, f, b.aim)
    local want = near and math.atan2(near.y - f.y, near.x - f.x) or f.angle
    b.aim = b.aim + wrap(want - b.aim) * math.min(1, dt * 3)
    if b.mode == "rest" and b.t < Brain.rest then
      return b.mode
    end
    if target then
      b.mode, b.t, b.target = "lock", 0, target.id
    else
      b.mode = "scan"
    end
  elseif b.mode == "lock" then
    local px, py = inSight(server, f, b.aim, server.players[b.target])
    if not px then
      b.mode, b.t, b.target = "scan", 0, nil
      return b.mode
    end
    b.aim = b.aim + wrap(bearing(f, b.aim, px, py) - b.aim) * math.min(1, dt * Brain.trackLock)
    if b.t >= Brain.lockTime then
      b.mode, b.t, b.left, b.fireIn = "fire", 0, Brain.burst, 0
    end
  elseif b.mode == "fire" then
    local px, py = inSight(server, f, b.aim, server.players[b.target])
    if px then
      turnTo(b, bearing(f, b.aim, px, py), Brain.trackFire, dt)
    end
    b.fireIn = b.fireIn - dt
    local weapons = Features.byName.weapons
    while b.fireIn <= 0 and b.left > 0 do
      b.fireIn = b.fireIn + Brain.gun.cooldown
      b.left = b.left - 1
      local mx, my, a = Render.muzzle(f.x, f.y, f.angle, b.aim, f.altitude)
      if weapons and weapons.serverFireFrom then
        weapons:serverFireFrom(server, 0, mx, my, a + (random() * 2 - 1) * Brain.spread, Brain.gun)
      end
    end
    if b.left <= 0 or not px then
      b.mode, b.t, b.target = "rest", 0, nil
    end
  end
  return b.mode
end

--- How far into locking on it is (0..1), for the beam; 0 when it isn't.
function Brain.lock(b)
  return b.mode == "lock" and math.min(1, b.t / Brain.lockTime) or 0
end

return Brain
