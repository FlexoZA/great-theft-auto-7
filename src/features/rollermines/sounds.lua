-- The rollermines' noises, synthesised at load and played where they
-- happen: a base source per sound, cloned per play. Their blast is the
-- weapons feature's, like any explosion's.
--   pop    hopping up out of the ground: a thump, and the blades snapping out
--   whirr  rolling: a gritty electric buzz, played over and over while it rolls
--   beep   about to go: a sharp double beep

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "rollermines" channel
  refDistance = 260,
  maxDistance = 1800,
}

local bank = {} -- name -> base Source

local function make(seconds, build)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local source = love.audio.newSource(buf:toSoundData(0.9), "static")
  source:setAttenuationDistances(Sounds.refDistance, Sounds.maxDistance)
  return source
end

function Sounds.load()
  Audio.registerChannel("rollermines", "Rollermines", Sounds.volume, function()
    Sounds.play("pop", 0, 0)
  end)

  bank.pop = make(0.5, function(buf)
    buf:sweep(0, 0.25, 140, 60, { wave = "sine", amp = 0.7, decay = 0.1 })
    buf:noiseBurst(0, 0.1, { amp = 0.35, decay = 0.03 })
    for i = 0, 2 do -- the three blades: clack, clack, clack
      local t = 0.16 + i * 0.045
      buf:noiseBurst(t, 0.02, { amp = 0.45, decay = 0.006 })
      buf:tone(t, 0.03, 2400 + i * 300, { wave = "square", amp = 0.12, attack = 0.001, decay = 0.015, sustain = 0 })
    end
    buf:lowpass(5000)
  end)

  bank.whirr = make(0.42, function(buf)
    buf:tone(0, 0.38, 110, { wave = "saw", amp = 0.25, attack = 0.04, decay = 1, sustain = 0.8, release = 0.04,
      vibRate = 18, vibDepth = 0.6 })
    buf:tone(0, 0.38, 330, { wave = "square", amp = 0.06, attack = 0.04, decay = 1, sustain = 0.8, release = 0.04 })
    buf:noiseBurst(0, 0.42, { amp = 0.12, decay = 1 })
    buf:lowpass(1600)
  end)

  bank.beep = make(0.2, function(buf)
    buf:tone(0, 0.05, 1760, { wave = "square", amp = 0.22, attack = 0.002, decay = 1, sustain = 1, release = 0.01 })
    buf:tone(0.09, 0.05, 1760, { wave = "square", amp = 0.22, attack = 0.002, decay = 1, sustain = 1, release = 0.01 })
    buf:lowpass(5000)
  end)
end

--- Play `name` at world position (x, y).
function Sounds.play(name, x, y, pitch)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Audio.volume("rollermines"))
  s:play()
  return s
end

return Sounds
