-- The driving scene. All cars are simulated by the server; this state sends
-- local input, smooths the snapshots it receives, and draws everyone.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Car = require("src.car")

local Game = {}

local SMOOTHING = 12 -- per second; higher = snappier, lower = smoother
local GRID = 128

local function angleDiff(target, current)
  return (target - current + math.pi) % (2 * math.pi) - math.pi
end

function Game:enter()
  UI.load()
  self.camera = { x = 0, y = 0 }
end

function Game:update(dt)
  Net.update(dt)
  local client = Net.client
  if not client then
    State.switch("menu")
    return
  end

  local throttle, steer = Car.readInput()
  client:sendInput(throttle, steer, dt)

  local k = math.min(1, dt * SMOOTHING)
  for _, c in pairs(client.cars) do
    c.dx = c.dx + (c.x - c.dx) * k
    c.dy = c.dy + (c.y - c.dy) * k
    c.dangle = c.dangle + angleDiff(c.angle, c.dangle) * k
  end

  local me = client:myCar()
  if me then
    self.camera.x, self.camera.y = me.dx, me.dy
  end
end

function Game:drawGrid()
  local cam = self.camera
  love.graphics.setColor(0.25, 0.25, 0.28)
  local w, h = love.graphics.getDimensions()
  local x0 = math.floor((cam.x - w) / GRID) * GRID
  local y0 = math.floor((cam.y - h) / GRID) * GRID
  for x = x0, cam.x + w, GRID do
    love.graphics.line(x, cam.y - h, x, cam.y + h)
  end
  for y = y0, cam.y + h, GRID do
    love.graphics.line(cam.x - w, y, cam.x + w, y)
  end
end

function Game:drawCars(client)
  love.graphics.setFont(UI.fonts.small)
  for id, c in pairs(client.cars) do
    Car.draw(c.dx, c.dy, c.dangle, Car.colorFor(id))
    local p = client.players[id]
    if p then
      love.graphics.setColor(1, 1, 1, id == client.myId and 1 or 0.8)
      love.graphics.printf(p.name, c.dx - 60, c.dy - Car.HEIGHT - 18, 120, "center")
    end
  end
end

function Game:draw()
  local client = Net.client
  if not client then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2 - self.camera.x), math.floor(h / 2 - self.camera.y))
  self:drawGrid()
  self:drawCars(client)
  love.graphics.pop()

  local me = client:myCar()
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(("FPS %d  speed %.0f"):format(love.timer.getFPS(), me and me.speed or 0), 10, 10)
  love.graphics.print("Arrows/WASD to drive, Esc to leave", 10, 28)

  local text
  if client:isConnected() then
    local role = Net.isHost() and "hosting" or "connected"
    text = ("%s  players: %d  tick %d"):format(role, client:playerCount(), client.lastTick)
    love.graphics.setColor(0.7, 0.9, 0.7)
  else
    text = "connection lost: " .. tostring(client.error)
    love.graphics.setColor(1, 0.4, 0.4)
  end
  love.graphics.printf(text, 0, 10, w - 10, "right")
end

function Game:keypressed(key)
  if key == "escape" then
    Net.shutdown()
    State.switch("menu")
  end
end

return Game
