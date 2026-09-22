-- A very simple arcade car: accelerate, brake, steer.

local Car = {}
Car.__index = Car

function Car.new(x, y)
  return setmetatable({
    x = x,
    y = y,
    angle = 0,       -- radians, 0 = facing right
    speed = 0,       -- px/s, negative = reversing
    maxSpeed = 500,
    accel = 400,
    brake = 700,
    friction = 250,
    turnRate = 2.6,  -- rad/s at full speed
    width = 40,
    height = 20,
  }, Car)
end

local function down(...)
  return love.keyboard.isDown(...)
end

function Car:update(dt)
  local throttle = 0
  if down("up", "w") then throttle = throttle + 1 end
  if down("down", "s") then throttle = throttle - 1 end

  local steer = 0
  if down("left", "a") then steer = steer - 1 end
  if down("right", "d") then steer = steer + 1 end

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

function Car:draw()
  love.graphics.push()
  love.graphics.translate(self.x, self.y)
  love.graphics.rotate(self.angle)
  love.graphics.setColor(0.9, 0.2, 0.2)
  love.graphics.rectangle("fill", -self.width / 2, -self.height / 2, self.width, self.height, 4)
  -- Windscreen
  love.graphics.setColor(0.6, 0.8, 1)
  love.graphics.rectangle("fill", 4, -self.height / 2 + 3, 10, self.height - 6)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Car
