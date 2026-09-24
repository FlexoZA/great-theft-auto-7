-- Tiny immediate-ish UI: buttons, a single-line text field, a slider and a
-- cycler (pick one of several options with arrows).

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

--- `text` as it fits in `width` px of `font`: whole, or cut short (whole
--- characters, so a name with accents stays valid) and ended with "...".
function UI.fit(text, font, width)
  if font:getWidth(text) <= width then
    return text
  end
  while #text > 0 and font:getWidth(text .. "...") > width do
    text = text:sub(1, (utf8.offset(text, -1) or 1) - 1)
  end
  return text .. "..."
end

--- The dark rounded panel menu screens put their controls on, over the
--- menu backdrop (settings, host, join, lobby).
function UI.panel(x, y, w, h)
  love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
  love.graphics.rectangle("fill", x, y, w, h, 8)
  love.graphics.setColor(0.3, 0.3, 0.35)
  love.graphics.rectangle("line", x, y, w, h, 8)
  love.graphics.setColor(1, 1, 1)
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
  elseif hover or self.selected then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 6)
  if self.selected then
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.rectangle("fill", self.x, self.y + 4, 4, self.h - 8, 2)
  end
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

-- Slider -----------------------------------------------------------------

local Slider = {}
Slider.__index = Slider

--- UI.slider({ label=, value= (0..1), onChange=, x=, y=, w=, h= })
--- Call update() every frame so dragging follows the mouse.
function UI.slider(opts)
  opts.x = opts.x or 0
  opts.y = opts.y or 0
  opts.w = opts.w or 300
  opts.h = opts.h or 10
  opts.value = opts.value or 0
  opts.dragging = false
  return setmetatable(opts, Slider)
end

function Slider:contains(mx, my)
  return mx >= self.x - 8 and mx <= self.x + self.w + 8 and my >= self.y - 12 and my <= self.y + self.h + 12
end

function Slider:setFromMouse(mx)
  local v = (mx - self.x) / self.w
  v = math.max(0, math.min(1, v))
  if v ~= self.value then
    self.value = v
    if self.onChange then
      self.onChange(v)
    end
  end
end

function Slider:update()
  if self.dragging then
    if love.mouse.isDown(1) then
      self:setFromMouse(love.mouse.getX())
    else
      self.dragging = false
    end
  end
end

function Slider:draw()
  local hover = self.dragging or self:contains(love.mouse.getPosition())
  if self.label then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(self.label, self.x, self.y - 30)
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.printf(("%d%%"):format(math.floor(self.value * 100 + 0.5)), self.x, self.y - 30, self.w, "right")
  end
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.rectangle("fill", self.x, self.y, self.w, self.h, 3)
  if hover then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", self.x, self.y, self.w * self.value, self.h, 3)
  local kx = self.x + self.w * self.value
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.rectangle("fill", kx - 7, self.y - 7, 14, self.h + 14, 3)
  love.graphics.setColor(hover and 1 or 0.85, hover and 1 or 0.85, hover and 1 or 0.88)
  love.graphics.rectangle("fill", kx - 5, self.y - 5, 10, self.h + 10, 3)
  love.graphics.setColor(1, 1, 1)
end

function Slider:mousepressed(mx, my, button)
  if button == 1 and self:contains(mx, my) then
    self.dragging = true
    self:setFromMouse(mx)
    return true
  end
  return false
end

-- Cycler ------------------------------------------------------------------

local Cycler = {}
Cycler.__index = Cycler

--- UI.cycler({ label=, options = { { label=, value= }, ... }, index=, onChange=(value), x=, y=, w=, h=, enabled= })
function UI.cycler(opts)
  opts.x = opts.x or 0
  opts.y = opts.y or 0
  opts.w = opts.w or 300
  opts.h = opts.h or 32
  opts.index = opts.index or 1
  if opts.enabled == nil then
    opts.enabled = true
  end
  return setmetatable(opts, Cycler)
end

function Cycler:step(delta)
  local n = #self.options
  self.index = (self.index - 1 + delta) % n + 1
  if self.onChange then
    self.onChange(self.options[self.index].value, self.index)
  end
end

function Cycler:contains(mx, my)
  return mx >= self.x and mx <= self.x + self.w and my >= self.y and my <= self.y + self.h
end

function Cycler:draw()
  local arrowW = self.h
  local hover = self.enabled and self:contains(love.mouse.getPosition())
  if not self.enabled then
    love.graphics.setColor(0.20, 0.20, 0.24)
  elseif hover then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", self.x, self.y, arrowW, self.h, 6)
  love.graphics.rectangle("fill", self.x + self.w - arrowW, self.y, arrowW, self.h, 6)
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.rectangle("fill", self.x + arrowW + 2, self.y, self.w - arrowW * 2 - 4, self.h, 4)
  love.graphics.setFont(UI.fonts.body)
  local th = UI.fonts.body:getHeight()
  local ty = self.y + math.floor((self.h - th) / 2)
  love.graphics.setColor(1, 1, 1, self.enabled and 1 or 0.5)
  love.graphics.printf("<", self.x, ty, arrowW, "center")
  love.graphics.printf(">", self.x + self.w - arrowW, ty, arrowW, "center")
  love.graphics.printf(self.options[self.index].label, self.x + arrowW, ty, self.w - arrowW * 2, "center")
  love.graphics.setColor(1, 1, 1)
end

function Cycler:mousepressed(mx, my, button)
  if not self.enabled or not self:contains(mx, my) then
    return false
  end
  if button == 1 then
    local arrowW = self.h
    if mx < self.x + arrowW then
      self:step(-1)
    else
      self:step(1)
    end
    return true
  elseif button == 2 then
    self:step(-1)
    return true
  end
  return false
end

-- HUD meters --------------------------------------------------------------
-- Small readouts features draw in drawHUD, so they all look like one HUD.

local function clamp01(v)
  return v < 0 and 0 or (v > 1 and 1 or v)
end

--- Text with a dark shadow under it, so it reads on any road or roof.
--- `color` is { r, g, b[, a] }; white if nil.
function UI.label(text, x, y, color)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.print(text, x + 1, y + 1)
  if color then
    love.graphics.setColor(color)
  else
    love.graphics.setColor(1, 1, 1)
  end
  love.graphics.print(text, x, y)
end

--- A horizontal meter: a dark trough with a lit fill `frac` (0..1) of the
--- way across, in `color` = { r, g, b[, a] }. `marks` is an optional list
--- of fractions to notch on the trough (a threshold worth seeing).
function UI.meter(x, y, w, h, frac, color, marks)
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3)
  local fill = math.floor(w * clamp01(frac) + 0.5)
  if fill > 0 then
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y, fill, h, 1)
    -- A lighter band along the top gives the fill some body.
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("fill", x, y, fill, math.max(1, math.floor(h / 3)), 1)
  end
  if marks then
    love.graphics.setColor(0, 0, 0, 0.6)
    for _, m in ipairs(marks) do
      local mx = x + math.floor(w * clamp01(m) + 0.5)
      love.graphics.rectangle("fill", mx - 1, y, 2, h)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 1.5, y - 1.5, w + 3, h + 3, 3)
end

--- A vertical meter: a dark trough with a lit fill `frac` (0..1) of the
--- way up from the bottom, in `color`. `marks` notches fractions on it.
function UI.vmeter(x, y, w, h, frac, color, marks)
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", x - 2, y - 2, w + 4, h + 4, 3)
  local fill = math.floor(h * clamp01(frac) + 0.5)
  if fill > 0 then
    love.graphics.setColor(color)
    love.graphics.rectangle("fill", x, y + h - fill, w, fill, 1)
    -- A lighter band up the left edge gives the fill some body.
    love.graphics.setColor(1, 1, 1, 0.22)
    love.graphics.rectangle("fill", x, y + h - fill, math.max(1, math.floor(w / 4)), fill, 1)
  end
  if marks then
    love.graphics.setColor(0, 0, 0, 0.6)
    for _, m in ipairs(marks) do
      local my = y + h - math.floor(h * clamp01(m) + 0.5)
      love.graphics.rectangle("fill", x, my - 1, w, 2)
    end
  end
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", x - 1.5, y - 1.5, w + 3, h + 3, 3)
end

--- A ring around (cx, cy): a dark disc, a faint track and a lit arc `frac`
--- (0..1) of the way round clockwise from the top, in `color`. Full at 1.
function UI.ring(cx, cy, radius, frac, color, width)
  width = width or 4
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.circle("fill", cx, cy, radius + width / 2 + 1, 48)
  love.graphics.setLineWidth(width)
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.circle("line", cx, cy, radius, 48)
  frac = clamp01(frac)
  if frac > 0 then
    love.graphics.setColor(color)
    local from = -math.pi / 2
    if frac >= 1 then
      love.graphics.circle("line", cx, cy, radius, 48)
    else
      love.graphics.arc("line", "open", cx, cy, radius, from, from + frac * 2 * math.pi, 48)
    end
  end
  love.graphics.setLineWidth(1)
end

-- The bottom-left row of stat bars ----------------------------------------
-- Health, stamina, dodge, abilities: each feature draws its own bar into a
-- numbered slot of the same row, so they line up as one readout.

UI.statBar = {
  x = 24, -- left edge of slot 0
  step = 70, -- px between slots; room for a name under each bar
  w = 28,
  h = 100,
  bottom = 58, -- px up from the bottom edge the bars stand on; the inventory line sits under
}

--- Green with plenty, amber when getting low, red when nearly gone.
function UI.rampColor(frac)
  frac = clamp01(frac)
  if frac > 0.5 then
    local k = (frac - 0.5) * 2
    return { 0.4 + 0.6 * (1 - k), 0.85, 0.35 }
  end
  local k = frac * 2
  return { 1, 0.35 + 0.5 * k, 0.3 }
end

--- One bar of the row at `slot` (0 is leftmost): `value` above it if
--- given, the bar, `name` under it. `alpha` dims the whole thing (a stat
--- that does not apply right now). Returns the bar's x, y, w, h.
function UI.drawStatBar(slot, name, frac, color, value, valueColor, marks, alpha)
  local font = UI.fonts.small
  local sb = UI.statBar
  local x, w, h = sb.x + slot * sb.step, sb.w, sb.h
  local y = love.graphics.getHeight() - sb.bottom - h
  local cx = x + w / 2
  alpha = alpha or 1
  love.graphics.setFont(font)
  UI.vmeter(x, y, w, h, frac, { color[1], color[2], color[3], (color[4] or 1) * alpha }, marks)
  UI.label(name, math.floor(cx - font:getWidth(name) / 2), y + h + 6, { 0.85, 0.85, 0.9, alpha })
  if value then
    local vc = valueColor or { 1, 1, 1 }
    UI.label(value, math.floor(cx - font:getWidth(value) / 2), y - font:getHeight() - 2,
      { vc[1], vc[2], vc[3], (vc[4] or 1) * alpha })
  end
  return x, y, w, h
end

return UI
