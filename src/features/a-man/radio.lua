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
--   investigate  another one, on his way to look
--   lost     one who went looking and found nothing, on his way back
--   cover    a rifleman ducking into cover (the nests' crews)

local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local UI = require("src.ui")

local Radio = {
  volume = 0.7, -- default of the "combine" channel
  nearDistance = 300, -- px; nearer than this he is heard at full volume
  farDistance = 1000, -- px; further than this he is not heard at all
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
  investigate = {
    "Moving to investigate.",
    "On my way. Cover me.",
    "Checking it out.",
    "Converging on last position.",
  },
  cover = { "Taking cover!", "Moving to cover!", "Cover me!", "Suppressing fire!", "Get down!" },
  lost = { "Lost visual.", "Area clear. Returning to post.", "Nothing here.", "Target lost. Resuming patrol." },
}

--- How long a line hangs over a soldier's head.
function Radio.sayTime(text)
  return 2.2 + #text / 22
end

-- Sound ---------------------------------------------------------------------

local bursts = {} -- base Sources, shortest first
local LENGTHS = { 0.5, 0.9, 1.3, 1.8 } -- seconds of talk in each
local PEEP = 0.22 -- seconds of quiet peep before the squelch opens

--- A burst of radio: a soft peep, the squelch opening, a deep voice
--- chewed up past knowing (low buzzy syllables pushed through a narrow,
--- overdriven band, a hiss under it) and the two-note chirp of the key
--- coming up. The voice is roughed up in a buffer of its own so the
--- overdrive leaves the peep as quiet as it is.
local function burst(talk)
  local length = PEEP + talk + 0.45
  local voice = Synth.newBuffer(length)
  local rnd = Synth.noise
  local t = PEEP + 0.1
  while t < PEEP + talk do
    local d = 0.07 + (rnd() + 1) * 0.055
    local f = 68 + (rnd() + 1) * 18
    voice:sweep(t, d, f, f * (0.82 + (rnd() + 1) * 0.12), { wave = "saw", amp = 0.6, decay = d * 1.5 })
    voice:sweep(t, d, f * 2.01, f * 1.85, { wave = "square", amp = 0.12, decay = d })
    t = t + d + (rnd() > 0.55 and 0.09 or 0.02)
  end
  voice:noiseBurst(PEEP + 0.05, talk + 0.1, { amp = 0.04, decay = 99 })
  voice:highpass(220)
  voice:lowpass(1700)
  voice:drive(4)

  local buf = Synth.newBuffer(length)
  buf:tone(0, 0.07, 1900, { wave = "sine", amp = 0.14, attack = 0.005, decay = 0.05, sustain = 0.6 })
  buf:noiseBurst(PEEP, 0.05, { amp = 0.3, decay = 0.02 })
  voice:mixInto(buf, 0.7)
  local off = PEEP + talk + 0.15
  buf:tone(off, 0.05, 1100, { wave = "sine", amp = 0.18, attack = 0.002, decay = 0.05, sustain = 0.8 })
  buf:tone(off + 0.06, 0.07, 1450, { wave = "sine", amp = 0.18, attack = 0.002, decay = 0.05, sustain = 0.8 })
  buf:noiseBurst(off + 0.13, 0.06, { amp = 0.25, decay = 0.02 })
  local source = love.audio.newSource(buf:toSoundData(0.8), "static")
  source:setRelative(true) -- faded by hand (Radio.play): the game's distance model never quite lets go
  return source
end

function Radio.load()
  for i, talk in ipairs(LENGTHS) do
    bursts[i] = burst(talk)
  end
  Audio.registerChannel("combine", "Combine soldiers' radio", Radio.volume, function()
    local lx, _, ly = love.audio.getPosition()
    Radio.play("Overwatch, patrol on route.", lx, ly, false)
  end)
end

--- `text` over the radio at (x, y): a burst about as long as the line,
--- higher and quicker when he is shouting, fading out with distance from
--- the listener and panned a little towards his side.
function Radio.play(text, x, y, shouting)
  local lx, _, ly = love.audio.getPosition()
  local d = math.sqrt((x - lx) ^ 2 + (y - ly) ^ 2)
  local fade = 1 - (d - Radio.nearDistance) / (Radio.farDistance - Radio.nearDistance)
  fade = math.min(1, fade)
  if fade <= 0 then
    return
  end
  local i = 1
  while i < #bursts and LENGTHS[i] < #text / 22 do
    i = i + 1
  end
  local base = bursts[i]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(math.max(-1, math.min(1, (x - lx) / Radio.farDistance)), 0, 0)
  s:setPitch((shouting and 1.12 or 1) * (0.95 + love.math.random() * 0.1))
  s:setVolume(Audio.volume("combine") * fade)
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
