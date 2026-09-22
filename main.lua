-- Great Theft Auto 7 — entry point
-- Top-down starter: a car you can drive around with the arrow keys / WASD.

local Car = require("src.car")

local car
local camera = { x = 0, y = 0 }

function love.load()
  love.graphics.setBackgroundColor(0.16, 0.16, 0.18)
  love.graphics.setDefaultFilter("nearest", "nearest")
  car = Car.new(0, 0)
end

function love.update(dt)
  car:update(dt)
  -- Camera follows the car.
  camera.x = car.x
  camera.y = car.y
end

local function drawWorld()
  -- Simple grid so movement is visible.
  love.graphics.setColor(0.25, 0.25, 0.28)
  local size = 128
  local w, h = love.graphics.getDimensions()
  local x0 = math.floor((camera.x - w) / size) * size
  local y0 = math.floor((camera.y - h) / size) * size
  for x = x0, camera.x + w, size do
    love.graphics.line(x, camera.y - h, x, camera.y + h)
  end
  for y = y0, camera.y + h, size do
    love.graphics.line(camera.x - w, y, camera.x + w, y)
  end
  love.graphics.setColor(1, 1, 1)
  car:draw()
end

function love.draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2 - camera.x), math.floor(h / 2 - camera.y))
  drawWorld()
  love.graphics.pop()

  love.graphics.setColor(1, 1, 1)
  love.graphics.print(("FPS %d  speed %.0f"):format(love.timer.getFPS(), car.speed), 10, 10)
  love.graphics.print("Arrows/WASD to drive, Esc to quit", 10, 30)
end

function love.keypressed(key)
  if key == "escape" then
    love.event.quit()
  end
end
