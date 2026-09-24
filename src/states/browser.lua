-- "Join LAN game": servers joined before (src/net/recent.lua) with whether
-- they are up, hosts found by broadcast, or connect to a typed IP.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Discovery = require("src.net.discovery")
local Protocol = require("src.net.protocol")
local Recent = require("src.net.recent")
local utf8 = require("utf8")

local Browser = {}

local W = 600
local ROW = 52 -- a list row: 44 px button and the gap under it
local FORGET_W = 44

function Browser:enter(playerName)
  UI.load()
  self.playerName = playerName
  self.scanner = Discovery.newScanner()
  self:loadRecent()
  self.hostButtons, self.forgetButtons, self.headings = {}, {}, {}
  self.lanTop, self.lanCount = 110, 0
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

--- Read the servers joined before and ask each one's last address directly
--- too, in case a broadcast does not reach it.
function Browser:loadRecent()
  self.recent = Recent.list()
  for _, e in ipairs(self.recent) do
    self.scanner:probe(e.ip)
  end
end

--- "World (Host's game)", or just the server name for a game not saved.
local function title(name, world)
  return world and ("%s  (%s)"):format(world, name) or name
end

--- A row's label: `title`, cut short (whole characters) so it and `status`
--- fit on one line of a button `w` wide.
local function rowLabel(text, status, w)
  local font = UI.fonts.body
  local room = w - 24 - font:getWidth("   " .. status)
  if font:getWidth(text) > room then
    while #text > 0 and font:getWidth(text .. "...") > room do
      text = text:sub(1, (utf8.offset(text, -1) or 1) - 1)
    end
    text = text .. "..."
  end
  return text .. "   " .. status
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
  local h = love.graphics.getHeight()
  local bottom = h - 190 -- rows stop above the address field
  local y = 110
  self.headings = {}
  self.hostButtons = {}
  self.forgetButtons = {}

  -- Recent: found again by id wherever the host is now, else at its last address.
  local listed = {}
  if #self.recent > 0 then
    self.headings[#self.headings + 1] = { text = "Recent", y = y }
    y = y + 22
    for _, e in ipairs(self.recent) do
      if y + 44 > bottom then
        break
      end
      local live = self.scanner.hosts[e.id]
      listed[e.id] = true
      local w = W - FORGET_W - 8
      local label
      if live then
        label = rowLabel(title(live.name, live.world), ("%d/%d players"):format(live.players, live.maxPlayers), w)
      else
        label = rowLabel(title(e.name, e.world), "offline, " .. os.date("%d %b", e.at or 0), w)
      end
      self.hostButtons[#self.hostButtons + 1] = UI.button({ label = label, x = x, y = y, w = w,
        selected = live ~= nil, onClick = function()
          self:join(live and live.ip or e.ip, live and live.port or e.port)
        end })
      self.forgetButtons[#self.forgetButtons + 1] = UI.button({ label = "x", x = x + W - FORGET_W, y = y, w = FORGET_W,
        onClick = function()
          Recent.forget(e.id)
          self.recent = Recent.list()
        end })
      y = y + ROW
    end
    y = y + 10
  end

  self.headings[#self.headings + 1] = { text = "On your network", y = y }
  y = y + 22
  self.lanTop = y
  self.lanCount = 0
  for _, host in ipairs(self.scanner:list()) do
    if not listed[host.id] and y + 44 <= bottom then
      local label = rowLabel(title(host.name, host.world), ("%d/%d players   %s"):format(host.players,
        host.maxPlayers, host.ip), W)
      self.hostButtons[#self.hostButtons + 1] = UI.button({ label = label, x = x, y = y, w = W, onClick = function()
        self:join(host.ip, host.port)
      end })
      self.lanCount = self.lanCount + 1
      y = y + ROW
    end
  end

  self.ipField.x, self.ipField.y = x, h - 150
  self.connectButton.x, self.connectButton.y = x + W - 120, h - 150
  self.backButton.x, self.backButton.y = x, h - 80
end

function Browser:draw()
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Join a LAN game", 0, 50, w, "center")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.75)
  for _, heading in ipairs(self.headings) do
    love.graphics.print(heading.text, UI.centerX(W), heading.y)
  end
  if self.lanCount == 0 then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0.6, 0.6, 0.65)
    local dots = string.rep(".", math.floor(love.timer.getTime() * 2) % 4)
    love.graphics.printf("Searching for hosts on your network" .. dots, 0, self.lanTop + 10, w, "center")
  end
  for _, b in ipairs(self.hostButtons) do
    b:draw()
  end
  for _, b in ipairs(self.forgetButtons) do
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
  for _, b in ipairs(self.forgetButtons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
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
