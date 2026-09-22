-- "Join LAN game": lists hosts found by broadcast, or connect to a typed IP.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Discovery = require("src.net.discovery")
local Protocol = require("src.net.protocol")

local Browser = {}

local W = 520

function Browser:enter(playerName)
  UI.load()
  self.playerName = playerName
  self.scanner = Discovery.newScanner()
  self.hostButtons = {}
  self.error = nil
  self.ipField = UI.textField({
    label = "Or type a host address (ip or ip:port)",
    value = "",
    maxLength = 21,
    w = W - 130,
  })
  self.connectButton = UI.button({ label = "Connect", w = 120, h = 38, onClick = function()
    self:connectManual()
  end })
  self.backButton = UI.button({ label = "Back", w = 120, onClick = function()
    State.switch("menu")
  end })
end

function Browser:exit()
  if self.scanner then
    self.scanner:close()
    self.scanner = nil
  end
end

function Browser:join(ip, port)
  if Net.join(self.playerName, ip, port) then
    State.switch("lobby")
  else
    self.error = "could not connect to " .. tostring(ip)
  end
end

function Browser:connectManual()
  local text = self.ipField.value:gsub("%s", "")
  local ip, port = text:match("^([%d%.]+):(%d+)$")
  if not ip then
    ip = text:match("^[%d%.]+$")
  end
  if not ip then
    self.error = "enter an IPv4 address like 192.168.1.20"
    return
  end
  self:join(ip, tonumber(port) or Protocol.PORT)
end

function Browser:update(dt)
  self.scanner:update(dt)

  local x = UI.centerX(W)
  local y = 120
  self.hostButtons = {}
  for i, h in ipairs(self.scanner:list()) do
    local label = ("%s   %d/%d players   %s"):format(h.name, h.players, h.maxPlayers, h.ip)
    self.hostButtons[i] = UI.button({ label = label, x = x, y = y + (i - 1) * 52, w = W, onClick = function()
      self:join(h.ip, h.port)
    end })
  end

  local h = love.graphics.getHeight()
  self.ipField.x, self.ipField.y = x, h - 150
  self.connectButton.x, self.connectButton.y = x + W - 120, h - 150
  self.backButton.x, self.backButton.y = x, h - 80
end

function Browser:draw()
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Join a LAN game", 0, 50, w, "center")

  if #self.hostButtons == 0 then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0.6, 0.6, 0.65)
    local dots = string.rep(".", math.floor(love.timer.getTime() * 2) % 4)
    love.graphics.printf("Searching for hosts on your network" .. dots, 0, 130, w, "center")
  end
  for _, b in ipairs(self.hostButtons) do
    b:draw()
  end

  self.ipField:draw()
  self.connectButton:draw()
  self.backButton:draw()

  if self.error then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.printf(self.error, 0, love.graphics.getHeight() - 30, w, "center")
  end
end

function Browser:keypressed(key)
  self.ipField:keypressed(key)
  if key == "escape" then
    State.switch("menu")
  elseif key == "return" and self.ipField.focused then
    self:connectManual()
  end
end

function Browser:textinput(t)
  self.ipField:textinput(t)
end

function Browser:mousepressed(x, y, button)
  self.ipField:mousepressed(x, y, button)
  for _, b in ipairs(self.hostButtons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
  if self.connectButton:mousepressed(x, y, button) then
    return
  end
  self.backButton:mousepressed(x, y, button)
end

return Browser
