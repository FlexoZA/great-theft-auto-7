-- Arcade car physics plus drawing. The same update runs on the server for
-- every player; clients only draw what the server tells them.

local Controls = require("src.controls")

local Car = {}
Car.__index = Car

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
    speed = 0, -- px/s, negative = reversing
    maxSpeed = 500,
    accel = 400,
    brake = 700,
    friction = 250,
    turnRate = 2.6, -- rad/s at full speed
  }, Car)
end

--- Reads the local driving controls. Returns throttle, steer in [-1, 1].
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
  return throttle, steer
end

function Car:update(dt, throttle, steer)
  if throttle > 0 then
    self.speed = math.min(self.speed + self.accel * dt, self.maxSpeed)
  elseif throttle < 0 then
    if self.speed > 0 then
      self.speed = math.max(self.speed - self.brake * dt, 0)
    else
      self.speed = math.max(self.speed - self.accel * 0.5 * dt, -self.maxSpeed * 0.4)
    end
  else
    -- Roll to a stop.
    if self.speed > 0 then
      self.speed = math.max(self.speed - self.friction * dt, 0)
    elseif self.speed < 0 then
      self.speed = math.min(self.speed + self.friction * dt, 0)
    end
  end

  -- Steering scales with speed so you can't spin on the spot.
  local factor = math.min(math.abs(self.speed) / 150, 1)
  local dir = self.speed < 0 and -1 or 1
  self.angle = self.angle + steer * self.turnRate * factor * dir * dt

  self.x = self.x + math.cos(self.angle) * self.speed * dt
  self.y = self.y + math.sin(self.angle) * self.speed * dt
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
