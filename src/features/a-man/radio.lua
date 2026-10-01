-- The Combine soldiers' radio chatter in City 17 (city17.lua): what they
-- say, the garbled burst of radio you hear when they say it and the bubble
-- over their heads. The host picks who says what (a category and an index
-- into it); every machine has the same lines.
--
-- Categories
--   post     a guard at his checkpoint, now and then
--   patrol   a squad's leader, walking the beat
--   reply    a mate answering either of those
--   alert    whoever has just spotted somebody
--   down     a soldier near one who just went down

local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local UI = require("src.ui")

local Radio = {
  volume = 0.7, -- default of the "combine" channel
  refDistance = 260,
  maxDistance = 1500,
}

Radio.lines = {
  post = {
    "Checkpoint holding. No movement.",
    "Sector clear. Maintaining position.",
    "Overwatch, this post is quiet.",
    "Citizens dispersed. Area secure.",
    "Holding the line. Nothing to report.",
    "All citizens accounted for.",
    "Requesting relief at this checkpoint.",
    "Ration queue is orderly.",
  },
  patrol = {
    "Patrol moving. Sweeping the sector.",
    "Keep formation. Eyes on the windows.",
    "Next block. Stay sharp.",
    "Overwatch, patrol on route.",
    "Checking the alleys. Nothing yet.",
    "Sector sweep, phase two.",
    "Stay off the main road. Watch the rooftops.",
  },
  reply = { "Copy.", "Affirmative.", "Understood.", "Ten-four.", "Copy that, holding.", "Roger." },
  alert = {
    "Contact! Engaging!",
    "Anticitizen sighted!",
    "Target in view. Opening fire.",
    "Hostile! Converge!",
    "Suspect is armed! Fire!",
    "Lock on target!",
  },
  down = { "Unit down!", "Lost a man! Reinforce!", "Overwatch, we have casualties!", "Man down! Find the shooter!" },
}

--- How long a line hangs over a soldier's head.
function Radio.sayTime(text)
  return 2.2 + #text / 22
end

-- Sound ---------------------------------------------------------------------

local bursts = {} -- base Sources, shortest first
local LENGTHS = { 0.5, 0.9, 1.3, 1.8 } -- seconds of talk in each

--- A burst of radio: the squelch opening, a voice chewed up past knowing
--- (buzzy syllables pushed through a narrow, overdriven band, a hiss under
--- it) and the two-note chirp of the key coming up.
local function burst(talk)
  local buf = Synth.newBuffer(talk + 0.45)
  local rnd = Synth.noise
  buf:noiseBurst(0, 0.05, { amp = 0.5, decay = 0.02 })
  buf:tone(0, 0.05, 1500, { wave = "sine", amp = 0.25, attack = 0.002, decay = 0.03, sustain = 0 })
  buf:noiseBurst(0.05, talk + 0.1, { amp = 0.05, decay = 99 })
  local t = 0.1
  while t < talk do
    local d = 0.06 + (rnd() + 1) * 0.05
    local f = 115 + (rnd() + 1) * 40
    buf:sweep(t, d, f, f * (0.8 + (rnd() + 1) * 0.2), { wave = "saw", amp = 0.6, decay = d * 1.5 })
    buf:sweep(t, d, f * 2.02, f * 1.8, { wave = "square", amp = 0.15, decay = d })
    t = t + d + (rnd() > 0.55 and 0.08 or 0.015)
  end
  buf:highpass(450)
  buf:lowpass(2600)
  buf:drive(5)
  local off = talk + 0.15
  buf:tone(off, 0.05, 1250, { wave = "sine", amp = 0.3, attack = 0.002, decay = 0.05, sustain = 0.8 })
  buf:tone(off + 0.06, 0.07, 1650, { wave = "sine", amp = 0.3, attack = 0.002, decay = 0.05, sustain = 0.8 })
  buf:noiseBurst(off + 0.13, 0.06, { amp = 0.35, decay = 0.02 })
  local source = love.audio.newSource(buf:toSoundData(0.8), "static")
  source:setAttenuationDistances(Radio.refDistance, Radio.maxDistance)
  return source
end

function Radio.load()
  for i, talk in ipairs(LENGTHS) do
    bursts[i] = burst(talk)
  end
  Audio.registerChannel("combine", "Combine soldiers' radio", Radio.volume, function()
    Radio.play("Overwatch, patrol on route.", 0, 0, false)
  end)
end

--- `text` over the radio at (x, y): a burst about as long as the line,
--- higher and quicker when he is shouting.
function Radio.play(text, x, y, shouting)
  local i = 1
  while i < #bursts and LENGTHS[i] < #text / 22 do
    i = i + 1
  end
  local base = bursts[i]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch((shouting and 1.18 or 1) * (0.94 + love.math.random() * 0.12))
  s:setVolume(Audio.volume("combine"))
  s:play()
end

-- Bubble --------------------------------------------------------------------

--- `text` in a radio-blue bubble over (x, y), the tail pointing down at him.
function Radio.drawBubble(x, y, text, alpha, shouting)
  local font = UI.fonts.small
  local maxW = 200
  local w, wrapped = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 14
  local h = #wrapped * font:getHeight() + 10
  local bx, by = x - w / 2, y - h - 10
  love.graphics.setColor(0, 0, 0, 0.45 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 4)
  love.graphics.setColor(0.08, 0.12, 0.16, 0.92 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 4)
  love.graphics.polygon("fill", x - 5, by + h - 1, x + 5, by + h - 1, x, by + h + 7)
  local edge = shouting and { 1.00, 0.45, 0.20 } or { 0.45, 0.85, 1.00 }
  love.graphics.setColor(edge[1], edge[2], edge[3], 0.8 * alpha)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", bx, by, w, h, 4)
  love.graphics.setFont(font)
  love.graphics.setColor(edge[1], edge[2], edge[3], alpha)
  love.graphics.printf(text, bx + 7, by + 5, w - 14, "center")
end

return Radio
