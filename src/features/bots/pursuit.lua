-- Pursuit: how an NPC car goes after someone it is fighting: a patrol car
-- after someone wanted (the police brain hands it who), a civilian bot that
-- fights back (bots' init.lua). It is doing one of three things:
--
--   * standing: they are in sight within `standRange`. It stops, sliding
--     round side-on with the handbrake if it comes in fast, and shoots
--     from there. It stays put until they are past `holdRange` (as far as
--     the gun reaches) or out of sight for `lostFor` seconds.
--   * chasing: they are further off, or behind a building. It drives at
--     them, by the streets when a wall is in the way (Traffic.towards),
--     steering off walls with the reckless drivers' feelers and braking in
--     time for them, and pulls the handbrake to swing round a sharp turn
--     at speed. It shoots whenever it has them in sight and in range.
--   * backing off: shot by the one it is after (Pursuit.shotBy: the caller
--     says it was them), it gets
--     away for `retreatTime` seconds, in reverse if they are in front of
--     it and there is room behind, then stops and stands where it got to.
--     Not again for `retreatEvery` seconds, so a stream of fire doesn't
--     keep it running.

local Features = require("src.features")
local Traffic = require("src.features.bots.traffic")

local Pursuit = {}

-- Tuning ------------------------------------------------------------------
Pursuit.standRange = 450 -- px; in sight this near, a unit stops to shoot
Pursuit.holdRange = 650 -- px; a standing unit stays put out to this (Bots.range, its gun's reach)
Pursuit.lostFor = 0.6 -- seconds out of sight before a standing unit gives chase
Pursuit.chaseSpeed = 400 -- px/s at most on a chase (the car's own top speed if lower)
Pursuit.slideSpeed = 130 -- px/s; stopping from faster than this is a handbrake slide
Pursuit.driftAngle = 0.9 -- radians off its heading a turn must be before the handbrake goes on...
Pursuit.driftSpeed = 170 -- px/s ...and this fast
Pursuit.turnSpeed = 200 -- px/s it takes a corner at
Pursuit.retreatTime = 2.5 -- seconds a unit backs off once shot by who it is after
Pursuit.retreatEvery = 8 -- seconds before being shot makes it back off again
Pursuit.backRoom = 70 -- px clear behind the car it needs to reverse away
Pursuit.routeEvery = 0.3 -- seconds between looking up the way by the streets

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

local function clamp(v)
  return math.max(-1, math.min(1, v))
end

--- Steer for `heading` and off any wall near, at up to `speed`, braking in
--- time for what is ahead; the handbrake for a sharp turn at speed.
local function driveAt(unit, heading, speed)
  local car, input = unit.car, unit.input
  local push, ahead = Traffic.avoid(car)
  local err = angleDiff(heading, car.angle)
  input.steer = clamp(err / 0.4 + push)
  local corner = Traffic.cornerSpeed(car, Pursuit.turnSpeed)
  local want = math.min(speed, car.maxSpeed or speed, Traffic.stopping(ahead - 10, car, corner))
  input.handbrake = math.abs(err) > Pursuit.driftAngle and car.speed > Pursuit.driftSpeed
  input.throttle = Traffic.throttleFor(car, want)
end

--- Stop: a handbrake slide that swings it side-on to (tx, ty) when it is
--- going fast, then the brakes.
local function stand(unit, tx, ty)
  local car, input = unit.car, unit.input
  if math.abs(car.speed) > Pursuit.slideSpeed then
    local bearing = math.atan2(ty - car.y, tx - car.x)
    local left, right = angleDiff(bearing - math.pi / 2, car.angle), angleDiff(bearing + math.pi / 2, car.angle)
    input.steer = clamp((math.abs(left) < math.abs(right) and left or right) / 0.4)
    input.handbrake, input.throttle = true, 0
  else
    input.steer, input.handbrake = 0, false
    input.throttle = Traffic.throttleFor(car, 0)
  end
end

--- Get away from (tx, ty): backwards if they are in front and there is room
--- behind, else turned round and driven off.
local function backOff(unit, tx, ty)
  local car, input = unit.car, unit.input
  local away = math.atan2(car.y - ty, car.x - tx)
  local facingThem = math.cos(angleDiff(away, car.angle)) < 0
  if facingThem and Traffic.feel(car, car.angle + math.pi, Pursuit.backRoom) >= Pursuit.backRoom then
    -- Reversing turns the other way: steer so the tail swings round to `away`.
    input.steer = clamp(-angleDiff(away, car.angle + math.pi) / 0.4)
    input.handbrake, input.throttle = false, -1
  else
    driveAt(unit, away, Pursuit.chaseSpeed)
  end
end

--- One tick of `unit` going after `target` (a player). `B` is the bots
--- feature (shooting, getting unstuck), `now` the caller's clock.
function Pursuit.drive(server, B, unit, target, now, dt)
  local tx, ty, onFoot = Features.bodyPose(server, target)
  Pursuit.driveAt(server, B, unit, tx, ty, not onFoot and target.vehicle or nil, now, dt)
end

--- The same, after whatever is at (tx, ty): `tc` the car there, if it is
--- one, for leading the shots.
function Pursuit.driveAt(server, B, unit, tx, ty, tc, now, dt)
  local ai, car = unit.ai, unit.car
  local d2 = (tx - car.x) ^ 2 + (ty - car.y) ^ 2
  local seen = Traffic.inSight(car.x, car.y, tx, ty)

  if ai.backOffUntil then
    if now < ai.backOffUntil then
      backOff(unit, tx, ty)
      B.unstick(unit, dt)
      return
    end
    ai.backOffUntil, ai.standing = nil, true -- far enough: stop where it got to
  end

  ai.unseen = seen and 0 or (ai.unseen or 0) + dt
  if ai.standing then
    if d2 > Pursuit.holdRange ^ 2 or ai.unseen > Pursuit.lostFor then
      ai.standing = false
    end
  elseif seen and d2 <= Pursuit.standRange ^ 2 then
    ai.standing = true
  end
  if ai.standing then
    stand(unit, tx, ty)
  else
    -- In sight: straight at them. Behind a building: by the streets.
    local hx, hy = tx, ty
    if seen then
      ai.routeIn = 0
    else
      ai.routeIn = (ai.routeIn or 0) - dt
      if ai.routeIn <= 0 then
        ai.routeIn = Pursuit.routeEvery
        local city = Features.byName["city-map"]
        local graph = city and Traffic.graph(city.map)
        ai.wayX, ai.wayY = nil, nil
        if graph then
          ai.wayX, ai.wayY = Traffic.towards(graph, car, tx, ty)
        end
      end
      hx, hy = ai.wayX or tx, ai.wayY or ty
    end
    driveAt(unit, math.atan2(hy - car.y, hx - car.x), Pursuit.chaseSpeed)
    B.unstick(unit, dt)
  end
  if seen then
    B:shootAt(server, unit, tx, ty, tc)
  end
end

--- `unit` was shot by who it is after (the caller knows who that is): it
--- backs off for a moment (not again until `retreatEvery` has passed).
function Pursuit.shotBy(unit, now)
  local ai = unit.ai
  if now >= (ai.backOffReady or 0) then
    ai.backOffUntil = now + Pursuit.retreatTime
    ai.backOffReady = now + Pursuit.retreatEvery
    ai.standing = false
  end
end

--- Off the chase (lost them, wrecked): start the next one fresh.
function Pursuit.reset(unit)
  local ai = unit.ai
  ai.standing, ai.backOffUntil, ai.unseen, ai.wayX, ai.wayY, ai.routeIn = false, nil, 0, nil, nil, 0
end

return Pursuit
