-- Koin sounds: a short two-note "ching" for a pickup, synthesised once at
-- load and played as a positioned clone. Grabbing a pile plays it a few
-- times, so the caller raises the pitch per coin to make it a run.

local Synth = require("src.audio.synth")

local Sounds = { volume = 0.5 }
local base

function Sounds.load()
  local buf = Synth.newBuffer(0.35)
  buf:tone(0, 0.05, 1318, { wave = "square", amp = 0.26, attack = 0.002, decay = 0.07, sustain = 0.2, release = 0.02 })
  buf:tone(0.045, 0.18, 1975, {
    wave = "square", amp = 0.24, attack = 0.002, decay = 0.16, sustain = 0.2, release = 0.05,
  })
  buf:tone(0.045, 0.18, 2637, { wave = "sine", amp = 0.1, attack = 0.002, decay = 0.16, sustain = 0.2, release = 0.05 })
  buf:lowpass(7000)
  base = love.audio.newSource(buf:toSoundData(0.8), "static")
  base:setAttenuationDistances(300, 2200)
end

function Sounds.play(x, y, pitch)
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Sounds.volume)
  s:play()
end

return Sounds
