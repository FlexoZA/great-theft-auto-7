local State = require("src.state")
local UI = require("src.ui")
local Net = require("src.net")
local Protocol = require("src.net.protocol")

local Menu = {}

local W = 260

function Menu:enter()
  UI.load()
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

function Menu:layout()
  local w, h = love.graphics.getDimensions()
  local x = UI.centerX(W)
  local y = math.floor(h * 0.36)
  self.nameField.x, self.nameField.y = x, y
  for i, b in ipairs(self.buttons) do
    b.x, b.y = x, y + 60 + (i - 1) * 56
  end
  self.width = w
end

function Menu:update()
  self:layout()
end

function Menu:draw()
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("GREAT THEFT AUTO 7", 0, math.floor(h * 0.16), w, "center")

  self.nameField:draw()
  for _, b in ipairs(self.buttons) do
    b:draw()
  end

  if self.error then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 0.4, 0.4)
    love.graphics.printf(self.error, 0, h - 60, w, "center")
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.5, 0.5, 0.55)
  love.graphics.print("LÖVE " .. love.getVersion(), 10, h - 22)
end

function Menu:keypressed(key)
  self.nameField:keypressed(key)
  if key == "escape" then
    love.event.quit()
  elseif key == "return" then
    self:host()
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
