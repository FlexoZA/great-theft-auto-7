-- Waiting room. Same screen for host and joiners; only the host gets Start.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Protocol = require("src.net.protocol")

local Lobby = {}

local W = 420

function Lobby:enter()
  UI.load()
  self.buttons = {}
  if Net.isHost() then
    self.startButton = UI.button({ label = "Start game", w = 200, onClick = function()
      Net.server:start()
    end })
    self.buttons[#self.buttons + 1] = self.startButton
  else
    self.startButton = nil
  end
  self.leaveButton = UI.button({ label = "Leave", w = 200, onClick = function()
    Net.shutdown()
    State.switch("menu")
  end })
  self.buttons[#self.buttons + 1] = self.leaveButton
end

function Lobby:update(dt)
  Net.update(dt)
  local client = Net.client
  if not client then
    State.switch("menu")
    return
  end
  if client.started then
    State.switch("game")
    return
  end
  if self.startButton then
    self.startButton.enabled = client.state == "lobby"
  end

  local x = UI.centerX(W)
  local h = love.graphics.getHeight()
  if self.startButton then
    self.startButton.x, self.startButton.y = x, h - 140
  end
  self.leaveButton.x, self.leaveButton.y = x + (self.startButton and 220 or 0), h - 140
end

function Lobby:draw()
  local client = Net.client
  if not client then
    return
  end
  local w = love.graphics.getWidth()
  local x = UI.centerX(W)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(client.serverName or "Connecting", 0, 50, w, "center")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local status
  if client.state == "connecting" then
    status = "Connecting to " .. tostring(client.address)
  elseif client.state == "connected" then
    status = "Joining"
  elseif client.state == "lobby" then
    status = Net.isHost() and ("Hosting on UDP port " .. Protocol.PORT) or "Waiting for the host to start"
  elseif client.state == "failed" or client.state == "disconnected" then
    love.graphics.setColor(1, 0.4, 0.4)
    status = "Connection lost: " .. tostring(client.error)
  else
    status = client.state
  end
  love.graphics.printf(status, 0, 88, w, "center")
  if Net.isHost() and Net.server.discoveryError then
    love.graphics.setColor(1, 0.7, 0.3)
    local warn = "LAN discovery off (" .. Net.server.discoveryError .. "). Players must type your IP."
    love.graphics.printf(warn, 0, 106, w, "center")
  end

  love.graphics.setFont(UI.fonts.body)
  local players = client:playerList()
  love.graphics.setColor(0.8, 0.8, 0.85)
  love.graphics.print(("Players (%d/%d)"):format(#players, 8), x, 140)
  for i, p in ipairs(players) do
    local line = p.name
    if p.id == client.myId then
      line = line .. "  (you)"
    end
    if p.id == 1 then
      line = line .. "  [host]"
    end
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(line, x + 16, 140 + i * 28)
  end

  for _, b in ipairs(self.buttons) do
    b:draw()
  end
end

function Lobby:keypressed(key)
  if key == "escape" then
    Net.shutdown()
    State.switch("menu")
  elseif key == "return" and self.startButton and self.startButton.enabled then
    Net.server:start()
  end
end

function Lobby:mousepressed(x, y, button)
  for _, b in ipairs(self.buttons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
end

return Lobby
