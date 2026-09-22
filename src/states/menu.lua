local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Protocol = require("src.net.protocol")
local Audio = require("src.audio")
local Logo = require("src.art.logo")
local Background = require("src.art.menu_background")

local Menu = {}

local W = 260
local LOGO_SCALE = 6

local iconSet = false

function Menu:enter()
  UI.load()
  Audio.playMenuTheme()
  if not iconSet then
    love.window.setIcon(Logo.icon())
    iconSet = true
  end
  self.background = self.background or Background.new()
  if not self.nameField then
    local default = os.getenv("USER") or os.getenv("USERNAME") or "Player"
    self.nameField = UI.textField({ label = "Your name", value = default:sub(1, Protocol.MAX_NAME), focused = true })
  end
  self.error = nil
  self.buttons = {
    UI.button({ label = "Host LAN game", onClick = function()
      self:host()
    end }),
    UI.button({ label = "Join LAN game", onClick = function()
      State.switch("browser", self:playerName())
    end }),
    UI.button({ label = "Quit", onClick = function()
      love.event.quit()
    end }),
  }
end

function Menu:playerName()
  return Protocol.sanitizeName(self.nameField.value)
end

function Menu:host()
  local ok, err = Net.host(self:playerName())
  if ok then
    State.switch("lobby")
  else
    self.error = err
  end
end

--- Left column holds the logo, title and controls; the face fills the right.
function Menu:layout()
  local w, h = love.graphics.getDimensions()
  local colX = math.floor(math.max(40, w * 0.08))
  self.colX = colX
  self.logoY = math.floor(h * 0.08)
  self.titleY = self.logoY + 20 * LOGO_SCALE + 16
  local y = self.titleY + UI.fonts.title:getHeight() + 40
  self.nameField.x, self.nameField.y = colX, y
  for i, b in ipairs(self.buttons) do
    b.x, b.y = colX, y + 60 + (i - 1) * 56
  end
  self.faceX = math.floor(w * 0.68)
  self.faceY = math.floor(h * 0.52)
  self.faceScale = math.floor(math.min(h / 76, (w * 0.55) / 64))
end

function Menu:update(dt)
  self:layout()
  self.background:update(dt)
end

function Menu:draw()
  local w, h = love.graphics.getDimensions()
  self.background:draw(self.faceX, self.faceY, self.faceScale)

  -- Darken the left column so the controls read over the rays.
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, self.colX + W + 40, h)

  Logo.draw(self.colX, self.logoY, LOGO_SCALE)
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("GREAT THEFT AUTO", self.colX, self.titleY)

  self.nameField:draw()
  for _, b in ipairs(self.buttons) do
    b:draw()
  end

  if self.error then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.printf(self.error, self.colX, h - 60, W + 200, "left")
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.print("LÖVE " .. love.getVersion(), 10, h - 22)
  love.graphics.printf(Audio.muted and "M: music off" or "M: music on", 0, h - 22, w - 10, "right")
end

function Menu:keypressed(key)
  self.nameField:keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "return" then
    self:host()
  elseif key == "m" and not self.nameField.focused then
    Audio.toggleMute()
  end
end

function Menu:textinput(t)
  self.nameField:textinput(t)
end

function Menu:mousepressed(x, y, button)
  self.nameField:mousepressed(x, y, button)
  for _, b in ipairs(self.buttons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
end

return Menu
