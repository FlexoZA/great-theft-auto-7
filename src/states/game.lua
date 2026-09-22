-- The driving scene. Networked movement sync comes in milestone 2; for now
-- each player drives their own car locally while the session stays alive.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Car = require("src.car")

local Game = {}

function Game:enter()
  UI.load()
  self.car = Car.new(0, 0)
  self.camera = { x = 0, y = 0 }
end

function Game:update(dt)
  Net.update(dt)
  self.car:update(dt)
  self.camera.x = self.car.x
  self.camera.y = self.car.y
end

function Game:drawWorld()
  local cam = self.camera
  love.graphics.setColor(0.25, 0.25, 0.28)
  local size = 128
  local w, h = love.graphics.getDimensions()
  local x0 = math.floor((cam.x - w) / size) * size
  local y0 = math.floor((cam.y - h) / size) * size
  for x = x0, cam.x + w, size do
    love.graphics.line(x, cam.y - h, x, cam.y + h)
  end
  for y = y0, cam.y + h, size do
    love.graphics.line(cam.x - w, y, cam.x + w, y)
  end
  love.graphics.setColor(1, 1, 1)
  self.car:draw()
end

function Game:draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2 - self.camera.x), math.floor(h / 2 - self.camera.y))
  self:drawWorld()
  love.graphics.pop()

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(("FPS %d  speed %.0f"):format(love.timer.getFPS(), self.car.speed), 10, 10)
  love.graphics.print("Arrows/WASD to drive, Esc to leave", 10, 28)

  local client = Net.client
  if client then
    local text
    if client:isConnected() then
      text = ("%s  players: %d"):format(Net.isHost() and "hosting" or "connected", client:playerCount())
      love.graphics.setColor(0.7, 0.9, 0.7)
    else
      text = "connection lost: " .. tostring(client.error)
      love.graphics.setColor(1, 0.4, 0.4)
    end
    love.graphics.printf(text, 0, 10, w - 10, "right")
  end
end

function Game:keypressed(key)
  if key == "escape" then
    Net.shutdown()
    State.switch("menu")
  end
end

return Game
