-- Pickup sound: a two-note rising chime, synthesised at load and played on
-- one of a few positioned voices. A boss's loot is taken in one sweep, so the
-- chimes are capped: at most VOICES ring at once (a new one cuts the oldest)
-- and a chime within GAP seconds of the last is skipped, so a pile of drops
-- jingles instead of stacking into one loud blast.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = { volume = 0.6 }
local VOICES = 3
local GAP = 0.06
local voices = {}
local nextVoice = 1
local lastAt = -math.huge

function Sounds.load()
  Audio.registerChannel("pickups", "Pickups", Sounds.volume, function()
    Sounds.play(0, 0)
  end)
  local buf = Synth.newBuffer(0.4)
  buf:tone(0, 0.12, 660, { wave = "square", amp = 0.35, attack = 0.005, decay = 0.2, sustain = 0.3, release = 0.03 })
  buf:tone(0.11, 0.22, 990, {
    wave = "square", amp = 0.35, attack = 0.005, decay = 0.25, sustain = 0.3, release = 0.05,
  })
  buf:tone(0.11, 0.22, 1320, { wave = "sine", amp = 0.2, attack = 0.005, decay = 0.25, sustain = 0.2, release = 0.05 })
  buf:lowpass(5000)
  local base = love.audio.newSource(buf:toSoundData(0.8), "static")
  base:setAttenuationDistances(300, 2200)
  voices = { base }
  for i = 2, VOICES do
    voices[i] = base:clone()
  end
end

--- `pitch` tells the kinds apart: an energy drink rings a little higher.
function Sounds.play(x, y, pitch)
  if not voices[1] then
    return
  end
  local now = love.timer.getTime()
  if now - lastAt < GAP then
    return
  end
  lastAt = now
  local s = voices[nextVoice]
  nextVoice = nextVoice % VOICES + 1
  s:stop()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Audio.volume("pickups"))
  s:play()
end

return Sounds
