-- Siren: a two-tone wail, synthesised as a seamless loop and played per
-- police unit as a positional looping source while it is chasing.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = { volume = 0.6 }
local loopData

function Sounds.load()
  local seconds = 0.8
  local buf = Synth.newBuffer(seconds)
  local RATE = Synth.RATE
  local phase = 0
  for i = 0, buf.n - 1 do
    local t = i / RATE
    -- glide 620 -> 880 -> 620 Hz over the loop so it wraps cleanly
    local k = 0.5 - 0.5 * math.cos(2 * math.pi * t / seconds)
    local f = 620 + 260 * k
    phase = (phase + f / RATE) % 1
    local v = (phase < 0.5 and 1 or -1) * 0.5 + math.sin(2 * math.pi * phase) * 0.5
    buf.data[i] = v
  end
  buf:lowpass(3200)
  buf:drive(1.6)
  loopData = buf:toSoundData(0.7)
  Audio.registerChannel("police", "Police sirens", Sounds.volume, function()
    local s = love.audio.newSource(loopData, "static")
    s:setRelative(true)
    s:setVolume(Audio.volume("police"))
    s:play()
  end)
end

--- A looping positional siren source, not yet playing.
function Sounds.newSiren()
  local s = love.audio.newSource(loopData, "static")
  s:setLooping(true)
  s:setAttenuationDistances(300, 2400)
  return s
end

function Sounds.volumeNow()
  return Audio.volume("police")
end

return Sounds
