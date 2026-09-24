-- "Host LAN game": start a new world or continue a saved one
-- (docs/persistence.md), then on to the lobby.

local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Saves = require("src.saves")

local Worlds = {}

local W = 560
local MAX_LISTED = 6 -- the last played ones; older worlds stay on disk

function Worlds:enter(playerName)
  UI.load()
  self.playerName = playerName
  self.error = nil
  self.nameField = UI.textField({
    label = "New world",
    value = (playerName .. "'s city"):sub(1, 24),
    maxLength = 24,
    focused = true,
    w = W - 130,
  })
  self.createButton = UI.button({ label = "Create", w = 120, h = 38, onClick = function()
    self:create()
  end })
  self.backButton = UI.button({ label = "Back", w = 120, onClick = function()
    State.switch("menu")
  end })
  self.worldButtons = {}
  for i, saved in ipairs(Saves.list()) do
    if i > MAX_LISTED then
      break
    end
    local when = os.date("%d %b %H:%M", saved.lastPlayed)
    local who = #saved.players > 0 and ("   " .. table.concat(saved.players, ", ")) or ""
    self.worldButtons[i] = UI.button({ label = saved.name .. "   " .. when .. who, w = W, onClick = function()
      self:continue(saved.slug)
    end })
  end
end

function Worlds:create()
  local name = self.nameField.value:gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    self.error = "give the world a name"
    return
  end
  self:host(Saves.create(name))
end

function Worlds:continue(slug)
  local world, err = Saves.open(slug)
  if not world then
    self.error = err
    return
  end
  self:host(world)
end

function Worlds:host(world)
  local ok, err = Net.host(self.playerName, world)
  if ok then
    State.switch("lobby")
  else
    self.error = err
  end
end

function Worlds:update()
  local x = UI.centerX(W)
  self.nameField.x, self.nameField.y = x, 130
  self.createButton.x, self.createButton.y = x + W - 120, 130
  for i, b in ipairs(self.worldButtons) do
    b.x, b.y = x, 230 + (i - 1) * 54
  end
  self.backButton.x, self.backButton.y = x, love.graphics.getHeight() - 80
end

function Worlds:draw()
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Host a game", 0, 50, w, "center")

  self.nameField:draw()
  self.createButton:draw()

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.75)
  local x = UI.centerX(W)
  if #self.worldButtons > 0 then
    love.graphics.print("Continue", x, 208)
  else
    love.graphics.print("No saved worlds yet", x, 208)
  end
  for _, b in ipairs(self.worldButtons) do
    b:draw()
  end
  self.backButton:draw()

  if self.error then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.printf(self.error, 0, love.graphics.getHeight() - 30, w, "center")
  end
end

function Worlds:keypressed(key)
  self.nameField:keypressed(key)
  if key == "escape" then
    State.switch("menu")
  elseif key == "return" and self.nameField.focused then
    self:create()
  end
end

function Worlds:textinput(t)
  self.nameField:textinput(t)
end

function Worlds:mousepressed(x, y, button)
  self.nameField:mousepressed(x, y, button)
  if self.createButton:mousepressed(x, y, button) then
    return
  end
  for _, b in ipairs(self.worldButtons) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
  self.backButton:mousepressed(x, y, button)
end

return Worlds
