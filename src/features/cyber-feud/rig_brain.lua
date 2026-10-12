-- How the Static's war-rigs drive (docs/cyber-feud.md, "The Static"):
-- armoured trucks with a spiked chrome ram and a ganger riding on the
-- back. war_rigs.lua spawns them (NPC drivers from the bots feature,
-- `think` called every host tick) and draws them; this is only their heads.
--
-- A rig waits on its post, parked on the shoulder, until something it
-- wants to hit comes within SPOT and in sight: a player, or, while the two
-- sides are at it (troops.lua's flare-up), one of Halcyon's interceptors.
-- Then it goes straight for them, flat out, nose first: the ram is the
-- weapon. After a hit it drops back for a moment (BACK_OFF) and comes
-- again. The ganger on the back fires a shotgun at whoever it is after,
-- up close (the Static's rounds: `from` "static"). Lost for LOST_AFTER
-- seconds, or further than GIVE_UP, it pulls over where it is and waits.
--
-- A rig with a `script` (Kilowatt's, war_rigs.lua) drives that instead.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Traffic = require("src.features.bots.traffic")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local Brain = {}

Brain.SPOT = 850 -- px; something to hit this near and in sight wakes it
Brain.GIVE_UP = 1700 -- px; further than this and it lets them go
Brain.LOST_AFTER = 5 -- seconds out of sight before it lets them go
Brain.CHASE_SPEED = 500 -- px/s at most (the truck's own top speed if lower)
Brain.LEAD = 0.3 -- seconds ahead of the target it aims for: nose into them
Brain.HIT = 56 -- px between the two middles that counts as a hit
Brain.BACK_OFF = 1.2 -- seconds it drops back after a hit
Brain.SHOOT_RANGE = 260 -- px the ganger on the back shoots out to (a shotgun)
Brain.FIRE_EVERY = 1.3 -- seconds between pulls
Brain.SPREAD = 0.08 -- radians either side
Brain.PELLET = 9 -- per pellet

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function clamp(v)
  return math.max(-1, math.min(1, v))
end

local gun = nil

--- The ganger's shotgun, a little lighter per pellet, in the Static's cyan.
local function shotgun()
  if not gun then
    local base = Tiers.apply(Guns.shotgun, Tiers.DEFAULT)
    gun = setmetatable({ damage = Brain.PELLET, tint = "2ee6ff" }, { __index = base })
  end
  return gun
end

--- Steer for `heading` and off any wall near, at up to `speed`, braking in
--- time for what is ahead; the handbrake for a sharp turn at speed.
function Brain.driveAt(npc, heading, speed)
  local car, input = npc.car, npc.input
  local push, ahead = Traffic.avoid(car)
  local err = angleDiff(heading, car.angle)
  input.steer = clamp(err / 0.35 + push)
  local corner = Traffic.cornerSpeed(car, 240)
  local want = math.min(speed, car.maxSpeed or speed, Traffic.stopping(ahead - 10, car, corner))
  input.handbrake = math.abs(err) > 1.0 and car.speed > 200
  input.throttle = Traffic.throttleFor(car, want)
end

local function brake(npc)
  npc.input.steer, npc.input.handbrake = 0, false
  npc.input.throttle = Traffic.throttleFor(npc.car, 0)
end

--- What it could go for, nearest first: a human (their body or car) or,
--- with `rivals`, one of those cars. Returns who (a player), x, y, their car.
local function nearest(server, npc, range, rivals)
  local car = npc.car
  local best, bx, by, bc, bestD2
  local function consider(p, x, y, c)
    local d2 = (x - car.x) ^ 2 + (y - car.y) ^ 2
    if d2 <= range * range and (not bestD2 or d2 < bestD2) and Sight.clear(car.x, car.y, x, y) then
      best, bx, by, bc, bestD2 = p, x, y, c, d2
    end
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      consider(p, x, y, p.vehicle and not p.vehicle.hidden and p.vehicle or nil)
    end
  end
  for _, r in ipairs(rivals or {}) do
    if r.car and not r.car.hidden and server.players[r.id] then
      consider(r, r.car.x, r.car.y, r.car)
    end
  end
  return best, bx, by, bc
end

--- The ganger on the back pulls the trigger at (x, y), when near enough and in sight.
local function shoot(server, npc, x, y, dt)
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
  -- From the back of the truck, held out to the side it shoots at.
  local ca, sa = math.cos(car.angle), math.sin(car.angle)
  local side = ((x - car.x) * -sa + (y - car.y) * ca) >= 0 and 1 or -1
  local gx, gy = car.x - ca * 18 - sa * side * 18, car.y - sa * 18 + ca * side * 18
  local aim = math.atan2(y - gy, x - gx) + (love.math.random() * 2 - 1) * Brain.SPREAD
  weapons:serverFireFrom(server, 0, gx, gy, aim, shotgun(), "static")
  ai.shot, ai.fireIn = true, Brain.FIRE_EVERY
end

--- Every host tick: wait on its post, or go for something nose first.
--- `rivals` are the interceptors it may go for too (at war only).
function Brain.think(server, npc, dt, rivals)
  local ai, car = npc.ai, npc.car
  local B = Features.byName.bots
  if npc.script then
    npc.script(server, npc, dt)
    return
  end
  local range = ai.chasing and Brain.GIVE_UP or Brain.SPOT
  local p, x, y, tc = nearest(server, npc, range, rivals)
  if p then
    ai.chasing, ai.target, ai.lostFor = true, p.id, 0
  elseif ai.chasing then
    ai.lostFor = (ai.lostFor or 0) + dt
    local q = server.players[ai.target]
    if q and not q.bot and Features.visible(server, q) and ai.lostFor < Brain.LOST_AFTER then
      p = q
      x, y = Features.bodyPose(server, q)
      tc = q.vehicle and not q.vehicle.hidden and q.vehicle or nil
    else
      ai.chasing, ai.target = false, nil
    end
  end
  if not p then
    brake(npc)
    return
  end
  shoot(server, npc, x, y, dt)
  local d = math.sqrt((x - car.x) ^ 2 + (y - car.y) ^ 2)
  ai.backFor = (ai.backFor or 0) - dt
  if d < Brain.HIT and ai.backFor <= 0 then
    ai.backFor = Brain.BACK_OFF
    ai.rams = (ai.rams or 0) + 1
  end
  if ai.backFor > 0 then
    Brain.driveAt(npc, car.angle, math.max(0, math.abs(car.speed) - 150)) -- off the throttle, rolling on
    B.unstick(npc, dt)
    return
  end
  local gx, gy = x, y
  if tc then
    gx, gy = tc.x + math.cos(tc.angle) * tc.speed * Brain.LEAD, tc.y + math.sin(tc.angle) * tc.speed * Brain.LEAD
  end
  Brain.driveAt(npc, math.atan2(gy - car.y, gx - car.x), Brain.CHASE_SPEED)
  B.unstick(npc, dt)
end

--- Wrecked: war_rigs.lua takes it off the road.
function Brain.wrecked(_server, npc)
  npc.ai.chasing, npc.ai.target = false, nil
  npc.wreckedAt = npc.wreckedAt or love.timer.getTime()
end

return Brain
