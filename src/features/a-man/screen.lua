-- The full-screen portrait A-Man gets at the start of his quest: his face
-- over slow turning rays on the right, and a column on the left with a
-- small heading, a big title, a line under it and what he says, in a
-- speech bubble pointing at him. Laid out like the other bosses' screens,
-- with his own touch: every few seconds the portrait jumps, the way he
-- does, leaving a tear behind and coming back a moment later.
--
--   Screen.draw(face, Screen.spec(line), time)
--
-- `Screen.lines` is what he might say; the quest picks one (by index, so
-- every machine shows the same).

local UI = require("src.ui")
local Video = require("src.video")
local Teleport = require("src.features.abilities.teleport")

local Screen = {}

-- He talks the way he does: slow, with the pauses... in the wrong places.
Screen.lines = {
  "Ah. Hello. No... we have never met. I am merely a man. With a... moustache. Do step aside.",
  "The right man in the wrong... city. Can make all the difference. I am not that man. Obviously.",
  "I have an... appointment. In this city. You are, regrettably... in my way.",
  "These glasses? Prescription. The tag is... a reminder. Of the price. Of everything.",
  "Time, I'm afraid... is up. Nothing personal. My case is... full of surprises.",
  "The Citadel? Not... yet. There is another way round. A scenic one. I insist.",
}

Screen.color = { 0.55, 0.95, 0.65 }
local JUMP_EVERY = 4.5 -- seconds between the portrait's jumps
local JUMP_GONE = 0.18 -- seconds it is away
local JUMP_TEAR = 0.6 -- seconds the tear hangs

--- What the screen says, with line `line` of `lines` in the bubble.
function Screen.spec(line)
  return {
    bg = { 0.05, 0.08, 0.07 },
    ray = { 0.1, 0.2, 0.15 },
    kicker = "A PERFECTLY ORDINARY MAN",
    title = "A-MAN",
    titleColor = Screen.color,
    subtitle = "No relation.",
    speech = Screen.lines[line] or Screen.lines[1],
    speechColor = { 0.12, 0.16, 0.22 },
  }
end

--- `face` has draw(x, y, scale); `s` is { bg, ray, kicker, title, titleColor,
--- subtitle, speech, speechColor, hint } (`Screen.spec` makes his). `time`
--- turns the rays and times the jumps.
function Screen.draw(face, s, time)
  local w, h = love.graphics.getDimensions()
  local homeX, homeY = math.floor(w * 0.70), math.floor(h * 0.52)
  local faceScale = math.floor(math.min(h / 76, (w * 0.5) / 64))
  local radius = math.sqrt(w * w + h * h)

  love.graphics.setColor(s.bg)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local a0 = time * 0.1
  love.graphics.setColor(s.ray)
  for i = 0, 17, 2 do
    local a1 = a0 + i / 18 * 2 * math.pi
    local a2 = a0 + (i + 1) / 18 * 2 * math.pi
    love.graphics.polygon("fill", homeX, homeY, homeX + math.cos(a1) * radius, homeY + math.sin(a1) * radius,
      homeX + math.cos(a2) * radius, homeY + math.sin(a2) * radius)
  end

  -- The jump: gone for a moment, back a little to one side, a tear between.
  local cycle = math.floor(time / JUMP_EVERY)
  local into = time - cycle * JUMP_EVERY
  local side = (cycle % 2 == 0 and 1 or -1) * faceScale * 6
  local faceX = homeX + (cycle % 2 == 0 and 0 or side)
  local fromX = homeX + (cycle % 2 == 0 and side or 0)
  if cycle > 0 and into < JUMP_TEAR then
    Teleport.drawTear(fromX, homeY, faceX, homeY, into / JUMP_TEAR, Screen.color)
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", faceX, homeY, faceScale * 40)
  if not (cycle > 0 and into < JUMP_GONE) then
    face:draw(faceX, homeY, faceScale)
  end

  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.12)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(Screen.color)
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
