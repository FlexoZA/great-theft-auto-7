-- The driving scene. All cars are simulated by the server; this state sends
-- local input, smooths the snapshots it receives, draws everyone, and gives
-- features their hooks. Keep gameplay out of here: put it in src/features/.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Car = require("src.car")
local Features = require("src.features")

local Game = {}

local SMOOTHING = 12 -- per second; higher = snappier, lower = smoother

local function angleDiff(target, current)
  return (target - current + math.pi) % (2 * math.pi) - math.pi
end

function Game:enter()
  UI.load()
  -- Features may move the camera and change its scale in their update hook.
  self.camera = { x = 0, y = 0, scale = 1 }
  Features.call("enterGame", Net.client)
end

function Game:exit()
  Features.call("exitGame", Net.client)
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

  Features.call("update", dt, client, self.camera)
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
  love.graphics.setColor(1, 1, 1)
end

function Game:draw()
  local client = Net.client
  if not client then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.push()
  love.graphics.translate(math.floor(w / 2), math.floor(h / 2))
  love.graphics.scale(self.camera.scale or 1)
  love.graphics.translate(-math.floor(self.camera.x), -math.floor(self.camera.y))
  Features.call("drawBelowCars", client, self.camera)
  self:drawCars(client)
  Features.call("drawAboveCars", client, self.camera)
  love.graphics.pop()

  Features.call("drawHUD", client)

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
    return
  end
  Features.call("keypressed", key, Net.client)
end

function Game:mousepressed(x, y, button)
  Features.call("mousepressed", x, y, button, Net.client)
end

return Game
