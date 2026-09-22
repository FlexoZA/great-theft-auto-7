-- Pickup sound: a two-note rising chime, synthesised at load and played as a
-- positioned clone.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = { volume = 0.7 }
local base

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
  base = love.audio.newSource(buf:toSoundData(0.8), "static")
  base:setAttenuationDistances(300, 2200)
end

function Sounds.play(x, y)
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setVolume(Audio.volume("pickups"))
  s:play()
end

return Sounds
