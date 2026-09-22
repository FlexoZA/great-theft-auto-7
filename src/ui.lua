-- Tiny immediate-ish UI: buttons and a single-line text field.

local utf8 = require("utf8")

local UI = {}
UI.fonts = nil

function UI.load()
  if UI.fonts then
    return
  end
  UI.fonts = {
    title = love.graphics.newFont(44),
    heading = love.graphics.newFont(26),
    body = love.graphics.newFont(18),
    small = love.graphics.newFont(14),
  }
end

function UI.centerX(w)
  return math.floor((love.graphics.getWidth() - w) / 2)
end

-- Button ------------------------------------------------------------------

local Button = {}
Button.__index = Button

--- UI.button({ label=, onClick=, x=, y=, w=, h=, enabled= })
function UI.button(opts)
  opts.x = opts.x or 0
  opts.y = opts.y or 0
  opts.w = opts.w or 260
  opts.h = opts.h or 44
  if opts.enabled == nil then
    opts.enabled = true
  end
  return setmetatable(opts, Button)
end

function Button:contains(mx, my)
  return mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h
end

function Button:draw()
  local hover = self.enabled and self:contains(love.mouse.getPosition())
  if not self.enabled then
    love.graphics.setColor(0.28, 0.28, 0.32)
  elseif hover then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 6)
  love.graphics.setColor(1, 1, 1, self.enabled and 1 or 0.5)
  love.graphics.setFont(UI.fonts.body)
  local th = UI.fonts.body:getHeight()
  love.graphics.printf(self.label, self.x + 8, self.y + math.floor((self.h - th) / 2), self.w - 16, "center")
end

function Button:mousepressed(mx, my, button)
  if button == 1 and self.enabled and self:contains(mx, my) then
    self.onClick(self)
    return true
  end
  return false
end

-- TextField ---------------------------------------------------------------

local TextField = {}
TextField.__index = TextField

--- UI.textField({ label=, value=, maxLength=, focused=, x=, y=, w=, h= })
function UI.textField(opts)
  opts.x = opts.x or 0
  opts.y = opts.y or 0
  opts.w = opts.w or 260
  opts.h = opts.h or 38
  opts.value = opts.value or ""
  opts.maxLength = opts.maxLength or 16
  opts.focused = opts.focused or false
  return setmetatable(opts, TextField)
end

function TextField:contains(mx, my)
  return mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h
end

function TextField:draw()
  if self.label then
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.print(self.label, self.x, self.y - 18)
  end
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 4)
  if self.focused then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.4, 0.4, 0.45)
  end
  love.graphics.rectangle("line", self.x, self.y, self.w, self.h, 4)

  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1)
  local text = self.value
  if self.focused and math.floor(love.timer.getTime() * 2) % 2 == 0 then
    text = text .. "|"
  end
  local th = UI.fonts.body:getHeight()
  love.graphics.print(text, self.x + 8, self.y + math.floor((self.h - th) / 2))
end

function TextField:textinput(t)
  if not self.focused or t:find("%c") then
    return
  end
  if utf8.len(self.value .. t) <= self.maxLength then
    self.value = self.value .. t
  end
end

function TextField:keypressed(key)
  if self.focused and key == "backspace" then
    local off = utf8.offset(self.value, -1)
    if off then
      self.value = self.value:sub(1, off - 1)
    end
  end
end

function TextField:mousepressed(mx, my, button)
  if button == 1 then
    self.focused = self:contains(mx, my)
  end
end

return UI
