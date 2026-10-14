-- VEX's intro screen: laid out like the other bosses' (a column on the left
-- with a small heading, a big title, a line under it and what she says; her
-- portrait big on the right), in her own look: a dark green terminal, a
-- grid scrolling behind her, her words typed out in a terminal box rather
-- than a speech bubble, and the whole screen tearing now and then.
--
--   Screen.draw(face, line, t, time, opts)
--
-- `line` is one of Story.lines; `t` is how long the screen has been up (it
-- types her words out), `time` the clock for the grid. `opts` (optional)
-- puts its own `kicker`, `title` and `tagline` over her words in place of
-- YOUR FIXER, VEX and her line (the Shard's reveal: Story.revealScreen).

local UI = require("src.ui")
local Video = require("src.video")
local Face = require("src.features.cyber-feud.face")

local Screen = {}

Screen.TYPE_RATE = 40 -- characters a second her words type out at

local GREEN = Face.GREEN
local BG = { 0.02, 0.05, 0.04 }
local GRID = { 0.43, 1.00, 0.60, 0.07 }

local tear = 0 -- seconds left of a tear across the screen
local tearY = 0

--- How much of `text` is typed `t` seconds in.
function Screen.typed(text, t)
  return text:sub(1, math.max(0, math.floor(t * Screen.TYPE_RATE)))
end

function Screen.draw(face, line, t, time, opts)
  opts = opts or {}
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(BG)
  love.graphics.rectangle("fill", 0, 0, w, h)
  -- A grid scrolling down behind her, a horizon of it.
  love.graphics.setColor(GRID)
  local step = 48
  local off = (time * 30) % step
  for y = -step + off, h, step do
    love.graphics.rectangle("fill", 0, y, w, 1)
  end
  for x = 0, w, step do
    love.graphics.rectangle("fill", x, 0, 1, h)
  end

  local homeX, homeY = math.floor(w * 0.70), math.floor(h * 0.52)
  local scale = math.floor(math.min(h / 80, (w * 0.5) / 64))
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.08)
  love.graphics.circle("fill", homeX, homeY, scale * 42)
  face.talking = #Screen.typed(line, t) < #line
  face:draw(homeX, homeY, scale)

  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.12)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(GREEN)
  love.graphics.print(opts.kicker or "YOUR FIXER", colX, y)
  y = y + 26
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(1, 0.24, 0.78, 0.5) -- the title splits, a little, in both sides' colours
  local title = opts.title or "VEX"
  love.graphics.print(title, colX - 3, y)
  love.graphics.setColor(0.18, 0.9, 1, 0.5)
  love.graphics.print(title, colX + 3, y + 1)
  love.graphics.setColor(GREEN)
  love.graphics.print(title, colX, y)
  y = y + UI.fonts.title:getHeight() + 6
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(opts.tagline or "Totally on your side.", colX, y)
  y = y + UI.fonts.heading:getHeight() + 36

  -- Her words, typed out in a terminal box, a cursor blinking at the end.
  local font = UI.fonts.body
  local _, full = font:getWrap(line .. "_", colW - 32)
  local bh = #full * font:getHeight() + 28
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.rectangle("fill", colX, y, colW, bh, 4)
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", colX, y, colW, bh, 4)
  love.graphics.setLineWidth(1)
  local shown = Screen.typed(line, t)
  if math.floor(time * 3) % 2 == 0 or #shown < #line then
    shown = shown .. "_"
  end
  love.graphics.setFont(font)
  love.graphics.setColor(GREEN)
  love.graphics.printf(shown, colX + 16, y + 14, colW - 32, "left")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.75, 0.65)
  love.graphics.printf("press any key", 0, h - 40, w, "center")

  -- Now and then a tear across the whole screen.
  if tear <= 0 and love.math.random() < 0.01 then
    tear, tearY = 0.12, love.math.random(0, h)
  end
  if tear > 0 then
    tear = tear - love.timer.getDelta()
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.25)
    love.graphics.rectangle("fill", 0, tearY, w, 3)
    love.graphics.setColor(1, 0.24, 0.78, 0.15)
    love.graphics.rectangle("fill", 0, tearY + 5, w, 2)
  end
  if Video.get("scanlines") then
    love.graphics.setColor(0, 0, 0, 0.2)
    for sy = 0, h, 4 do
      love.graphics.rectangle("fill", 0, sy, w, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Screen
