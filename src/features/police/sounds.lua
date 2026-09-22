-- Siren: a classic hi-lo two-tone, synthesised as a seamless loop and played
-- per police unit as a positional looping source while it is chasing.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = { volume = 0.8 }
local loopData

function Sounds.load()
  local seconds = 1.0
  local half = seconds / 2
  local buf = Synth.newBuffer(seconds)
  local RATE = Synth.RATE
  local phase = 0
  for i = 0, buf.n - 1 do
    local t = i / RATE
    -- hi for half the loop, lo for the other half; 8 ms ramps hide the switch
    local inHalf = t % half
    local f = t < half and 960 or 720
    local ramp = math.min(1, inHalf / 0.008, (half - inHalf) / 0.008)
    phase = (phase + f / RATE) % 1
    local v = (phase < 0.5 and 1 or -1) * 0.45 + math.sin(2 * math.pi * phase) * 0.55
    buf.data[i] = v * ramp
  end
  buf:lowpass(3600)
  buf:drive(1.8)
  loopData = buf:toSoundData(0.85)
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
