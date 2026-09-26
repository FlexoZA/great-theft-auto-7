-- The full-screen portrait Shotgun gets when everyone arrives under his
-- cliff: his face over turning rays on the right, and a column on the left
-- with a small heading, a big title, a line under it and what he says, in
-- a speech bubble pointing at him. Laid out like the other bosses' screens.

local UI = require("src.ui")
local Video = require("src.video")

local Screen = {}

--- `face` has draw(x, y, scale); `s` is { bg, ray, kicker, title, titleColor,
--- subtitle, speech, speechColor, hint }. `time` turns the rays.
function Screen.draw(face, s, time)
  local w, h = love.graphics.getDimensions()
  local faceX, faceY = math.floor(w * 0.70), math.floor(h * 0.52)
  local faceScale = math.floor(math.min(h / 76, (w * 0.5) / 64))
  local radius = math.sqrt(w * w + h * h)

  love.graphics.setColor(s.bg)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local a0 = time * 0.15
  love.graphics.setColor(s.ray)
  for i = 0, 17, 2 do
    local a1 = a0 + i / 18 * 2 * math.pi
    local a2 = a0 + (i + 1) / 18 * 2 * math.pi
    love.graphics.polygon("fill", faceX, faceY, faceX + math.cos(a1) * radius, faceY + math.sin(a1) * radius,
      faceX + math.cos(a2) * radius, faceY + math.sin(a2) * radius)
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", faceX, faceY, faceScale * 40)
  face:draw(faceX, faceY, faceScale)

  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.12)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.print(s.kicker, colX, y)
  y = y + 26
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(s.title, colX + 3, y + 3, colW, "left")
  love.graphics.setColor(s.titleColor)
  love.graphics.printf(s.title, colX, y, colW, "left")
  local _, lines = UI.fonts.title:getWrap(s.title, colW)
  y = y + #lines * UI.fonts.title:getHeight() + 6
  if s.subtitle then
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(s.subtitle, colX, y)
    y = y + UI.fonts.heading:getHeight()
  end
  y = y + 36

  local font = UI.fonts.body
  local text = '"' .. s.speech .. '"'
  local _, tl = font:getWrap(text, colW - 32)
  local bh = #tl * font:getHeight() + 28
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", colX + 3, y + 4, colW, bh, 8)
  love.graphics.setColor(0.97, 0.95, 0.92)
  love.graphics.rectangle("fill", colX, y, colW, bh, 8)
  love.graphics.polygon("fill", colX + colW - 1, y + bh / 2 - 10, colX + colW - 1, y + bh / 2 + 10,
    colX + colW + 18, y + bh / 2)
  love.graphics.setFont(font)
  love.graphics.setColor(s.speechColor)
  love.graphics.printf(text, colX + 16, y + 14, colW - 32, "left")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.75)
  love.graphics.printf(s.hint or "press any key", 0, h - 40, w, "center")

  if Video.get("scanlines") then
    love.graphics.setColor(0, 0, 0, 0.18)
    for sy = 0, h, 4 do
      love.graphics.rectangle("fill", 0, sy, w, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Screen
