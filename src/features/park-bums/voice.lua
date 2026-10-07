-- A bum's voice and his speech bubble. The voice is made up at load
-- (src/audio/synth.lua): a run of slurred syllables, each sliding down in
-- pitch with a drunken wobble on it, pushed through a narrow, overdriven
-- band so no word comes out whole. Shouting is higher, louder and rougher;
-- a mutter is low and soft. The "bums" channel in Settings sets how loud.

local Audio = require("src.audio")
local Synth = require("src.audio.synth")
local UI = require("src.ui")

local Voice = {
  volume = 0.7, -- the channel's default
  nearDistance = 250, -- px; nearer than this he is heard at full volume
  farDistance = 900, -- px; further than this he is not heard at all
}

local takes = { shout = {}, mutter = {} } -- base Sources, shortest first
local LENGTHS = { shout = { 0.6, 1.0, 1.5 }, mutter = { 0.5, 0.9 } } -- seconds of talk in each

--- `talk` seconds of slurring, shouted or muttered.
local function render(talk, shouting)
  local length = talk + 0.3
  local buf = Synth.newBuffer(length)
  local rnd = Synth.noise
  local base = shouting and 165 or 100
  local t = 0.02
  while t < talk do
    local d = 0.09 + (rnd() + 1) * 0.07
    local f = base * (0.9 + (rnd() + 1) * 0.15)
    local o = { wave = "saw", amp = shouting and 0.55 or 0.4, decay = d * 1.6 }
    buf:sweep(t, d, f * 1.12, f * 0.82, o)
    buf:tone(t, d, f * 2.02, {
      wave = "square", amp = shouting and 0.1 or 0.05, attack = 0.01, decay = d, sustain = 0.3,
      vibRate = 7, vibDepth = 0.6,
    })
    if rnd() > 0.6 then
      buf:noiseBurst(t, 0.05, { amp = shouting and 0.18 or 0.08, decay = 0.02 }) -- a spat consonant
    end
    t = t + d + (rnd() > 0.5 and 0.07 or 0.015)
  end
  buf:highpass(shouting and 180 or 120)
  buf:lowpass(shouting and 2200 or 1100)
  buf:drive(shouting and 5 or 2)
  local source = love.audio.newSource(buf:toSoundData(0.8), "static")
  source:setRelative(true) -- faded by hand (Voice.play)
  return source
end

function Voice.load()
  for kind, lengths in pairs(LENGTHS) do
    for i, talk in ipairs(lengths) do
      takes[kind][i] = render(talk, kind == "shout")
    end
  end
  Audio.registerChannel("bums", "Park bums", Voice.volume, function()
    local lx, _, ly = love.audio.getPosition()
    Voice.play("Gimme back my shopping cart!", lx, ly, true)
  end)
end

--- How long a line hangs over his head.
function Voice.sayTime(text)
  return 2 + #text / 20
end

--- `text` said at (x, y): a take about as long as the line, fading with
--- distance from the listener and panned a little towards his side.
function Voice.play(text, x, y, shouting)
  local lx, _, ly = love.audio.getPosition()
  local d = math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
  local fade = math.min(1, 1 - (d - Voice.nearDistance) / (Voice.farDistance - Voice.nearDistance))
  if fade <= 0 then
    return
  end
  local kind = shouting and "shout" or "mutter"
  local lengths, list = LENGTHS[kind], takes[kind]
  local i = 1
  while i < #list and lengths[i] < #text / 22 do
    i = i + 1
  end
  local base = list[i]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(math.max(-1, math.min(1, (x - lx) / Voice.farDistance)), 0, 0)
  s:setPitch(0.92 + love.math.random() * 0.16)
  s:setVolume(Audio.volume("bums") * fade)
  s:play()
end

--- `text` in a bubble over (x, y), the tail pointing down at him: grubby
--- white for a mutter, red-edged and bold for a shout.
function Voice.drawBubble(x, y, text, alpha, shouting)
  local font = UI.fonts.small
  local maxW = 210
  local w, wrapped = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 14
  local h = #wrapped * font:getHeight() + 10
  local bx, by = x - w / 2, y - h - 12
  love.graphics.setColor(0, 0, 0, 0.4 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 5)
  if shouting then
    love.graphics.setColor(0.22, 0.06, 0.05, 0.92 * alpha)
  else
    love.graphics.setColor(0.93, 0.91, 0.84, 0.92 * alpha)
  end
  love.graphics.rectangle("fill", bx, by, w, h, 5)
  love.graphics.polygon("fill", x - 5, by + h - 1, x + 5, by + h - 1, x - 2, by + h + 8)
  love.graphics.setLineWidth(1)
  if shouting then
    love.graphics.setColor(1, 0.35, 0.25, 0.9 * alpha)
  else
    love.graphics.setColor(0.45, 0.4, 0.32, 0.8 * alpha)
  end
  love.graphics.rectangle("line", bx, by, w, h, 5)
  love.graphics.setFont(font)
  if shouting then
    love.graphics.setColor(1, 0.85, 0.75, alpha)
  else
    love.graphics.setColor(0.25, 0.22, 0.18, alpha)
  end
  love.graphics.printf(text, bx + 7, by + 5, w - 14, "center")
end

return Voice
