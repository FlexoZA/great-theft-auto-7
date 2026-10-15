-- The Voice's intro screen (docs/eternal-mood.md, "The Voice"): laid out
-- like the other quest lines' (a column on the left with a small heading, a
-- big title, a line under it and what the Voice says; the Mood Slayer's
-- helmet big on the right, face.lua), in the look of a 90s demon shooter: a
-- title cut from hot metal, Heck's glow coming up from the bottom of the
-- screen, embers rising through it. What the Voice says isn't on a radio:
-- it's in his head, so it comes in a thought bubble, typed out.
--
--   Screen.draw(face, line, t, time, level)
--
-- `line` is one of Story.lines; `t` is how long the screen has been up (it
-- types the words out), `time` a clock for the embers, `level` which of the
-- line's levels this is (for the heading). `Screen.load()` makes its sound:
-- a power chord, played by `Screen.sting()` when the screen comes up.

local UI = require("src.ui")
local Video = require("src.video")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Screen = {}

Screen.TYPE_RATE = 32 -- characters a second the words type out at
Screen.LEVELS = 5

local BG = { 0.05, 0.01, 0.01 }
local GLOW = { 0.70, 0.12, 0.02 }
local HOT = { 1.00, 0.55, 0.12 }
local CREAM = { 1.00, 0.90, 0.75 }

local sting = nil

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- How much of `text` is typed `t` seconds in.
function Screen.typed(text, t)
  return text:sub(1, math.max(0, math.floor(t * Screen.TYPE_RATE)))
end

--- The sting, synthesised once: two muted chugs and a power chord ringing
--- out, overdriven.
function Screen.load()
  local buf = Synth.newBuffer(1.6)
  local e2, b2, e3 = Synth.freq("E2"), Synth.freq("B2"), Synth.freq("E3")
  for _, at in ipairs({ 0, 0.16 }) do
    for _, f in ipairs({ e2, b2 }) do
      buf:tone(at, 0.09, f, { wave = "saw", amp = 0.3, attack = 0.002, decay = 0.05, sustain = 0.2 })
    end
  end
  for _, f in ipairs({ e2, b2, e3 }) do
    buf:tone(0.34, 1.1, f, { wave = "saw", amp = 0.28, attack = 0.004, decay = 0.6, sustain = 0.35, release = 0.15,
      vibRate = 5, vibDepth = 0.08 })
  end
  buf:kick(0, 0.8)
  buf:kick(0.16, 0.8)
  buf:kick(0.34, 1)
  buf:drive(3)
  buf:lowpass(3200)
  sting = love.audio.newSource(buf:toSoundData(0.8), "static")
end

function Screen.sting()
  if sting then
    local s = sting:clone()
    s:setVolume(0.8 * Audio.volume("music"))
    s:play()
  end
end

--- `text` in a title cut from hot metal: dark layers stepped down under it,
--- then the face, red going to yellow at the top.
local function metal(text, x, y, font)
  love.graphics.setFont(font)
  for k = 4, 1, -1 do
    love.graphics.setColor(0.25 - k * 0.04, 0.03, 0.02)
    love.graphics.print(text, x + k, y + k)
  end
  love.graphics.setColor(0.85, 0.18, 0.05)
  love.graphics.print(text, x, y)
  -- The top of the letters catching the heat: the same text again, clipped
  -- to its upper half, in yellow.
  local h = font:getHeight()
  love.graphics.setScissor(x - 4, y, font:getWidth(text) + 8, math.floor(h * 0.45))
  love.graphics.setColor(1, 0.72, 0.2)
  love.graphics.print(text, x, y)
  love.graphics.setScissor()
end

--- A thought bubble round (x, y, w, h), its trail of little bubbles off
--- towards (tx, ty).
local function thought(x, y, w, h, tx, ty)
  love.graphics.setColor(0.10, 0.03, 0.02, 0.88)
  love.graphics.rectangle("fill", x, y, w, h, 18)
  love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.85)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 18)
  local sx, sy = x + w, y + h * 0.5
  for k = 1, 3 do
    local f = k / 4
    local cx, cy = sx + (tx - sx) * f, sy + (ty - sy) * f
    local r = 11 - k * 2.5
    love.graphics.setColor(0.10, 0.03, 0.02, 0.88)
    love.graphics.circle("fill", cx, cy, r, 16)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.85)
    love.graphics.circle("line", cx, cy, r, 16)
  end
  love.graphics.setLineWidth(1)
end

function Screen.draw(face, line, t, time, level)
  local w, h = love.graphics.getDimensions()
  -- Black going to Heck's red at the bottom.
  love.graphics.setColor(BG)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local bands = 24
  for k = 0, bands - 1 do
    local f = k / bands
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.55 * f * f * (0.9 + 0.1 * math.sin(time * 1.7 + k)))
    love.graphics.rectangle("fill", 0, h * (0.45 + 0.55 * f), w, h * 0.55 / bands + 1)
  end
  -- Embers rising through it, drifting.
  for i = 1, 60 do
    local speed = 0.05 + hash(i) * 0.12
    local life = (time * speed + hash(i * 3.1)) % 1
    local x = hash(i * 7.7) * w + math.sin(time * (0.6 + hash(i)) + i) * 30
    local y = h * (1.05 - life * 0.9)
    love.graphics.setColor(HOT[1], HOT[2] * (1 - life * 0.5), HOT[3], (1 - life) * 0.8)
    love.graphics.circle("fill", x, y, 1.2 + hash(i * 5) * 2.2, 6)
  end

  -- Him on the right, the dream swaying him a little.
  local homeX = math.floor(w * 0.70 + math.sin(time * 0.5) * 4)
  local homeY = math.floor(h * 0.52 + math.sin(time * 0.37) * 3)
  local scale = math.floor(math.min(h / 80, (w * 0.5) / 64))
  love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.06)
  love.graphics.circle("fill", homeX, homeY, scale * 44)
  face:draw(homeX, homeY, scale)

  -- The column on the left: where, who, and what he's thinking.
  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.12)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(HOT)
  love.graphics.print(("ETERNAL MOOD  -  %d OF %d"):format(level or 1, Screen.LEVELS), colX, y)
  y = y + 26
  metal("THE MOOD SLAYER", colX, y, UI.fonts.title)
  y = y + UI.fonts.title:getHeight() + 6
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(CREAM)
  love.graphics.print("Rip. Tear. Five more minutes.", colX, y)
  y = y + UI.fonts.heading:getHeight() + 40

  -- What he's thinking, typed out in a thought bubble trailing off to him.
  local font = UI.fonts.body
  local _, full = font:getWrap(line, colW - 40)
  local bh = #full * font:getHeight() + 34
  thought(colX, y, colW, bh, homeX - scale * 22, homeY - scale * 14)
  love.graphics.setFont(font)
  love.graphics.setColor(CREAM)
  love.graphics.printf(Screen.typed(line, t), colX + 20, y + 17, colW - 40, "left")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.85, 0.6, 0.45)
  love.graphics.printf("press any key", 0, h - 40, w, "center")
  if Video.get("scanlines") then
    love.graphics.setColor(0, 0, 0, 0.2)
    for sy = 0, h, 4 do
      love.graphics.rectangle("fill", 0, sy, w, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Screen
