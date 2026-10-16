-- How Halcyon's interceptors drive (docs/cyber-feud.md, "Halcyon"): grey
-- patrol cars on the Overpass with a magenta and blue light bar and an
-- officer leaning out of the window. interceptors.lua spawns them (NPC
-- drivers from the bots feature, `think` called every host tick) and draws
-- them; this is only their heads.
--
-- An interceptor waits on its post, parked on the shoulder, until a player
-- comes within SPOT and in sight. Then it gives chase: flat out at where
-- they will be in a moment, steering off walls and wrecks with the bots'
-- feelers (bots/traffic.lua), and once it is alongside, into them, to spin
-- them out and box them in. After a hit it drops back for a moment
-- (BACK_OFF) and comes again. All the while its officer shoots out of the
-- window at them (Halcyon's rounds: `from` "halcyon", so they pass Halcyon
-- and hit the Static). Lost for LOST_AFTER seconds, or further than GIVE_UP,
-- it pulls over where it is and waits there for the next one.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Traffic = require("src.features.bots.traffic")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local UZI_TTL = 1.2 -- its uzi's rounds fly the full way (weapons' default): the player's uzi is close-range only

local Brain = {}

Brain.SPOT = 900 -- px; a player this near and in sight wakes it
Brain.GIVE_UP = 1800 -- px; further than this and it lets them go
Brain.LOST_AFTER = 5 -- seconds out of sight before it lets them go
Brain.CHASE_SPEED = 520 -- px/s at most (the car's own top speed if lower)
Brain.LEAD = 0.55 -- seconds ahead of the target it aims for on the way up
Brain.RAM_FROM = 200 -- px; this near, it goes into them...
Brain.RAM_LEAD = 0.2 -- ...aiming a little ahead of where they are, for the side of the car
Brain.HIT = 52 -- px between the two cars' middles that counts as a hit
Brain.BACK_OFF = 0.9 -- seconds it drops back after a hit
Brain.SHOOT_RANGE = 520 -- px the officer shoots out to
Brain.FIRE_EVERY = 0.4 -- seconds between rounds
Brain.BURST = 5 -- rounds, then...
Brain.BURST_PAUSE = 1.1 -- ...a breather
Brain.SPREAD = 0.1 -- radians either side
Brain.DAMAGE = 9 -- a round (an officer's SMG)

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function clamp(v)
  return math.max(-1, math.min(1, v))
end

local gun = nil

--- The officer's SMG: an uzi, a little lighter, in Halcyon's magenta.
local function smg()
  if not gun then
    gun = setmetatable({ damage = Brain.DAMAGE, tint = "ff3ec8", ttl = UZI_TTL },
      { __index = Tiers.apply(Guns.uzi, Tiers.DEFAULT) })
  end
  return gun
end

--- Steer for `heading` and off any wall near, at up to `speed`, braking in
--- time for what is ahead; the handbrake for a sharp turn at speed.
local function driveAt(npc, heading, speed)
  local car, input = npc.car, npc.input
  local push, ahead = Traffic.avoid(car)
  local err = angleDiff(heading, car.angle)
  input.steer = clamp(err / 0.35 + push)
  local corner = Traffic.cornerSpeed(car, 260)
  local want = math.min(speed, car.maxSpeed or speed, Traffic.stopping(ahead - 10, car, corner))
  input.handbrake = math.abs(err) > 0.9 and car.speed > 180
  input.throttle = Traffic.throttleFor(car, want)
end

local function brake(npc)
  npc.input.steer, npc.input.handbrake = 0, false
  npc.input.throttle = Traffic.throttleFor(npc.car, 0)
end

--- The nearest human it can see within `range` of its car, and where they are.
local function nearestPlayer(server, npc, range)
  local car = npc.car
  local best, bx, by, bestD2
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = (x - car.x) ^ 2 + (y - car.y) ^ 2
      if d2 <= range * range and (not bestD2 or d2 < bestD2) and Sight.clear(car.x, car.y, x, y) then
        best, bx, by, bestD2 = p, x, y, d2
      end
    end
  end
  return best, bx, by
end

--- The officer's trigger, at `p` (at x, y; their car `tc` if they drive), when in range and in sight.
local function shoot(server, npc, x, y, tc, dt)
  local ai, car = npc.ai, npc.car
  ai.fireIn = (ai.fireIn or 0) - dt
  local d2 = (x - car.x) ^ 2 + (y - car.y) ^ 2
  if ai.fireIn > 0 or d2 > Brain.SHOOT_RANGE ^ 2 or not Sight.clear(car.x, car.y, x, y) then
    return
  end
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local flight = math.sqrt(d2) / (smg().speed or 900)
  local px, py = x, y
  if tc then
    px, py = tc.x + math.cos(tc.angle) * tc.speed * flight, tc.y + math.sin(tc.angle) * tc.speed * flight
  end
  -- Out of the driver's window, on the left, the gun held out past the
  -- front corner so its rounds never clip the car's own nose.
  local ca, sa = math.cos(car.angle), math.sin(car.angle)
  local wx, wy = car.x + ca * 24 + sa * 18, car.y + sa * 24 - ca * 18
  local aim = math.atan2(py - wy, px - wx) + (love.math.random() * 2 - 1) * Brain.SPREAD
  weapons:serverFireFrom(server, 0, wx, wy, aim, smg(), "halcyon")
  ai.shot = true
  ai.burstLeft = (ai.burstLeft or Brain.BURST) - 1
  if ai.burstLeft > 0 then
    ai.fireIn = Brain.FIRE_EVERY
  else
    ai.burstLeft, ai.fireIn = Brain.BURST, Brain.BURST_PAUSE
  end
end

--- Every host tick: wait on its post, or chase, ram and shoot.
function Brain.think(server, npc, dt)
  local ai, car = npc.ai, npc.car
  local B = Features.byName.bots
  local range = ai.chasing and Brain.GIVE_UP or Brain.SPOT
  local p, x, y = nearestPlayer(server, npc, range)
  if p then
    ai.chasing, ai.target, ai.lostFor = true, p.id, 0
  elseif ai.chasing then
    ai.lostFor = (ai.lostFor or 0) + dt
    local q = server.players[ai.target]
    if q and Features.visible(server, q) and ai.lostFor < Brain.LOST_AFTER then
      p = q
      x, y = Features.bodyPose(server, q)
    else
      ai.chasing, ai.target = false, nil -- let them go: pull over here
    end
  end
  if not p then
    brake(npc)
    return
  end
  local tc = p.vehicle and not p.vehicle.hidden and p.vehicle or nil
  shoot(server, npc, x, y, tc, dt)
  local d = math.sqrt((x - car.x) ^ 2 + (y - car.y) ^ 2)
  ai.backFor = (ai.backFor or 0) - dt
  if d < Brain.HIT and ai.backFor <= 0 then
    ai.backFor = Brain.BACK_OFF -- a hit: drop back and come again
    ai.rams = (ai.rams or 0) + 1
  end
  if ai.backFor > 0 then
    -- Off the throttle and away to one side of them.
    local away = math.atan2(car.y - y, car.x - x)
    driveAt(npc, car.angle + clamp(angleDiff(away, car.angle)) * 0.4, math.max(0, math.abs(car.speed) - 120))
    B.unstick(npc, dt)
    return
  end
  local lead = d < Brain.RAM_FROM and Brain.RAM_LEAD or Brain.LEAD
  local gx, gy = x, y
  if tc then
    gx, gy = tc.x + math.cos(tc.angle) * tc.speed * lead, tc.y + math.sin(tc.angle) * tc.speed * lead
  end
  driveAt(npc, math.atan2(gy - car.y, gx - car.x), Brain.CHASE_SPEED)
  B.unstick(npc, dt)
end

--- Wrecked: interceptors.lua takes it off the road.
function Brain.wrecked(_server, npc)
  npc.ai.chasing, npc.ai.target = false, nil
  npc.wreckedAt = npc.wreckedAt or love.timer.getTime()
end

return Brain
