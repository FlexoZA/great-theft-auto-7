-- Arcade car physics plus drawing. The same update runs on the server for
-- every player; clients only draw what the server tells them.
--
-- The car carries a world-space velocity (vx, vy). Each tick it is split
-- into a forward part (throttle, brake, friction act on it) and a sideways
-- part that grip pulls towards zero. Normal grip snaps the car straight
-- almost at once; the handbrake cuts grip, sheds forward speed and
-- sharpens the turn, so the tail steps out and the car slides. `speed` is
-- kept as the forward component for everything that reads it (sync, engine
-- sound, bots); assigning to `speed` from outside still works and re-aims
-- the velocity along the heading.

local Controls = require("src.controls")

local Car = {}
Car.__index = Car

Controls.register("handbrake", "Handbrake", "space")

Car.WIDTH = 40
Car.HEIGHT = 20

local PALETTE = {
  { 0.90, 0.20, 0.20 },
  { 0.20, 0.60, 0.90 },
  { 0.30, 0.80, 0.30 },
  { 0.95, 0.80, 0.20 },
  { 0.80, 0.40, 0.90 },
  { 0.95, 0.55, 0.20 },
  { 0.30, 0.85, 0.85 },
  { 0.90, 0.90, 0.90 },
}

function Car.new(x, y, angle)
  return setmetatable({
    x = x or 0,
    y = y or 0,
    angle = angle or 0, -- radians, 0 = facing right
    speed = 0, -- forward px/s, negative = reversing (derived from vx, vy)
    vx = 0,
    vy = 0,
    lastSpeed = 0, -- to notice outside code assigning `speed`
    maxSpeed = 500,
    accel = 400,
    brake = 700,
    friction = 250,
    turnRate = 2.6, -- rad/s at full speed
    grip = 14, -- per second; how fast sideways velocity dies normally
    driftGrip = 1.1, -- grip with the handbrake on
    handbrakeDecel = 320, -- px/s^2 shed while the handbrake is on
    driftTurnBoost = 1.35, -- steering multiplier with the handbrake on
  }, Car)
end

--- Aim the velocity along the heading at `s` px/s.
function Car:setSpeed(s)
  self.vx, self.vy = math.cos(self.angle) * s, math.sin(self.angle) * s
  self.speed, self.lastSpeed = s, s
end

function Car:stop()
  self:setSpeed(0)
end

--- Sideways speed, px/s (positive = sliding to the car's right).
function Car:lateralSpeed()
  return -self.vx * math.sin(self.angle) + self.vy * math.cos(self.angle)
end

--- Reads the local driving controls. Returns throttle, steer in [-1, 1] and
--- whether the handbrake is held.
function Car.readInput()
  local throttle, steer = 0, 0
  if Controls.isDown("accelerate") then
    throttle = throttle + 1
  end
  if Controls.isDown("brake") then
    throttle = throttle - 1
  end
  if Controls.isDown("left") then
    steer = steer - 1
  end
  if Controls.isDown("right") then
    steer = steer + 1
  end
  return throttle, steer, Controls.isDown("handbrake")
end

function Car:update(dt, throttle, steer, handbrake)
  if self.vx == nil or self.speed ~= self.lastSpeed then
    self:setSpeed(self.speed) -- created or assigned from outside: trust `speed`
  end

  local ca, sa = math.cos(self.angle), math.sin(self.angle)
  local forward = self.vx * ca + self.vy * sa
  local lateral = -self.vx * sa + self.vy * ca

  if handbrake then
    -- Rear wheels locked: no drive, forward speed bleeds off.
    if forward > 0 then
      forward = math.max(forward - self.handbrakeDecel * dt, 0)
    else
      forward = math.min(forward + self.handbrakeDecel * dt, 0)
    end
  elseif throttle > 0 then
    forward = math.min(forward + self.accel * dt, self.maxSpeed)
  elseif throttle < 0 then
    if forward > 0 then
      forward = math.max(forward - self.brake * dt, 0)
    else
      forward = math.max(forward - self.accel * 0.5 * dt, -self.maxSpeed * 0.4)
    end
  else
    -- Roll to a stop.
    if forward > 0 then
      forward = math.max(forward - self.friction * dt, 0)
    elseif forward < 0 then
      forward = math.min(forward + self.friction * dt, 0)
    end
  end

  -- Grip pulls the sideways velocity towards zero; the handbrake lets it live.
  lateral = lateral * math.exp(-(handbrake and self.driftGrip or self.grip) * dt)

  -- Rebuild the world velocity in the current frame, then turn the car. The
  -- velocity keeps its direction while the heading rotates: that is the slide.
  self.vx, self.vy = forward * ca - lateral * sa, forward * sa + lateral * ca

  -- Steering scales with speed so you can't spin on the spot. Total speed,
  -- not forward speed, so a sliding car keeps rotating through the slide.
  local factor = math.min(math.sqrt(self.vx * self.vx + self.vy * self.vy) / 150, 1)
  -- Steering flips only when genuinely reversing, not when a slide has
  -- swung the nose past ninety degrees.
  local reversing = forward < 0 and math.abs(forward) > math.abs(lateral)
  local dir = reversing and -1 or 1
  local rate = self.turnRate * (handbrake and self.driftTurnBoost or 1)
  self.angle = self.angle + steer * rate * factor * dir * dt

  self.x = self.x + self.vx * dt
  self.y = self.y + self.vy * dt
  self.speed, self.lastSpeed = forward, forward
end

--- Hitbox: is the point (px, py), padded by `radius`, inside this car's
--- rotated rectangle? Works on any table with x, y, angle (server cars and
--- client snapshots alike).
function Car.hitTest(car, px, py, radius)
  radius = radius or 0
  local dx, dy = px - car.x, py - car.y
  local c, s = math.cos(-car.angle), math.sin(-car.angle)
  local lx = dx * c - dy * s
  local ly = dx * s + dy * c
  return math.abs(lx) <= Car.WIDTH / 2 + radius and math.abs(ly) <= Car.HEIGHT / 2 + radius
end

function Car.colorFor(id)
  return PALETTE[(id - 1) % #PALETTE + 1]
end

function Car.draw(x, y, angle, color)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.setColor(color)
  love.graphics.rectangle("fill", -Car.WIDTH / 2, -Car.HEIGHT / 2, Car.WIDTH, Car.HEIGHT, 4)
  -- Windscreen
  love.graphics.setColor(0.6, 0.8, 1)
  love.graphics.rectangle("fill", 4, -Car.HEIGHT / 2 + 3, 10, Car.HEIGHT - 6)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Car
