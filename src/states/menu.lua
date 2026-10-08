local State = require("src.state")
local UI = require("src.ui")
local Protocol = require("src.net.protocol")
local Audio = require("src.audio")
local Controls = require("src.controls")
local Logo = require("src.art.logo")
local Face = require("src.art.face")
local Background = require("src.art.menu_background")
local Version = require("src.version")
local Changelog = require("src.states.changelog")

local Menu = {}

local W = 260
local LOGO_SCALE = 6
local TOGGLE_W, TOGGLE_H = 210, 36
local TOGGLE_MARGIN = 20
local NOTES_SIZE = 36 -- the changelog icon in the bottom-left corner
local NOTES_MARGIN = 12

local iconSet = false

function Menu:enter()
  UI.load()
  self:applyInclusive()
  Audio.playMenuTheme()
  if not iconSet then
    love.window.setIcon(Logo.icon())
    iconSet = true
  end
  self.background = Background.shared()
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
    UI.button({ label = "Settings", onClick = function()
      State.switch("settings")
    end }),
    UI.button({ label = "Quit", onClick = function()
      love.event.quit()
    end }),
  }
  self.inclusiveButton = UI.button({
    w = TOGGLE_W,
    h = TOGGLE_H,
    label = self:inclusiveLabel(),
    selected = Face.inclusive(),
    onClick = function(b)
      Face.setInclusive(not Face.inclusive())
      b.selected = Face.inclusive()
      b.label = self:inclusiveLabel()
      self:applyInclusive()
    end,
  })
end

function Menu:inclusiveLabel()
  return "Inclusive mode: " .. (Face.inclusive() and "on" or "off")
end

--- Inclusive mode swaps the menu theme along with the face.
function Menu:applyInclusive()
  Audio.setMenuTrack(Face.inclusive() and "rap" or "metal")
end

function Menu:playerName()
  return Protocol.sanitizeName(self.nameField.value)
end

--- Pick a world to host (new or saved) first.
function Menu:host()
  State.switch("worlds", self:playerName())
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
  self.inclusiveButton.x = w - TOGGLE_W - TOGGLE_MARGIN
  self.inclusiveButton.y = TOGGLE_MARGIN
  self.notes = { x = NOTES_MARGIN, y = h - NOTES_SIZE - NOTES_MARGIN, w = NOTES_SIZE, h = NOTES_SIZE }
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
  self.inclusiveButton:draw()

  if self.error then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.printf(self.error, self.colX, h - 90, W + 200, "left")
  end
  self:drawNotes()
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local muteKey = Controls.name(Controls.bindings("mute")[1])
  love.graphics.printf(muteKey .. (Audio.muted and ": music off" or ": music on"), 0, h - 22, w - 10, "right")
end

function Menu:overNotes(x, y)
  local n = self.notes
  return n and x >= n.x and x <= n.x + n.w and y >= n.y and y <= n.y + n.h
end

--- The changelog icon: a page of notes on a round tile, the version beside
--- it, and a dot while there is a version the player has not read about.
function Menu:drawNotes()
  local n = self.notes
  local hover = self:overNotes(love.mouse.getPosition())
  if hover then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", n.x, n.y, n.w, n.h, 6)

  local px, py, pw, ph, fold = n.x + 10, n.y + 7, n.w - 20, n.h - 14, 5
  love.graphics.setColor(0.95, 0.95, 0.9)
  love.graphics.polygon("fill", px, py, px + pw - fold, py, px + pw, py + fold, px + pw, py + ph, px, py + ph)
  love.graphics.setColor(0.7, 0.7, 0.65)
  love.graphics.polygon("fill", px + pw - fold, py, px + pw, py + fold, px + pw - fold, py + fold)
  love.graphics.setColor(0.24, 0.40, 0.72)
  for i = 0, 2 do
    local lw = i == 2 and pw - 8 or pw - 5
    love.graphics.rectangle("fill", px + 3, py + 8 + i * 5, lw, 2)
  end

  if Changelog.unread() then
    love.graphics.setColor(1, 0.35, 0.3)
    love.graphics.circle("fill", n.x + n.w - 2, n.y + 2, 6)
    love.graphics.setColor(1, 1, 1)
    love.graphics.circle("line", n.x + n.w - 2, n.y + 2, 6)
  end

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local label = "v" .. Version.label
  if hover then
    love.graphics.setColor(1, 1, 1)
    label = label .. "  -  what's new"
  end
  love.graphics.print(label, n.x + n.w + 10, n.y + math.floor((n.h - UI.fonts.small:getHeight()) / 2))
end

function Menu:keypressed(key)
  self.nameField:keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "return" then
    self:host()
  elseif Controls.is("mute", key) and not self.nameField.focused then
    Audio.toggleMute()
  end
end

function Menu:textinput(t)
  self.nameField:textinput(t)
end

function Menu:mousepressed(x, y, button)
  self.nameField:mousepressed(x, y, button)
  if self.inclusiveButton:mousepressed(x, y, button) then
    return
  end
  if button == 1 and self:overNotes(x, y) then
    State.switch("changelog")
    return
  end
  for _, b in ipairs(self.buttons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
end

return Menu
