-- Ability sounds, synthesised at load and played at a point in the world,
-- the way the weapons do it.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "abilities" channel
  refDistance = 300,
  maxDistance = 2400,
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
  Audio.registerChannel("abilities", "Abilities", Sounds.volume, function()
    Sounds.play("freeze", 0, 0)
  end)

  -- Freeze: a crystalline chime climbing over a cold downward rush.
  bank.freeze = make(0.9, function(buf)
    buf:sweep(0, 0.5, 900, 140, { wave = "sine", amp = 0.45, decay = 0.18 })
    buf:noiseBurst(0, 0.6, { amp = 0.35, decay = 0.16 })
    buf:tone(0.02, 0.5, 1568, { wave = "sine", amp = 0.3, attack = 0.005, decay = 0.25, sustain = 0, release = 0.05 })
    buf:tone(0.08, 0.5, 2093, { wave = "sine", amp = 0.28, attack = 0.005, decay = 0.25, sustain = 0, release = 0.05 })
    buf:tone(0.16, 0.6, 2637, { wave = "sine", amp = 0.26, attack = 0.005, decay = 0.3, sustain = 0, release = 0.05 })
    buf:tone(0.24, 0.6, 3136, { wave = "tri", amp = 0.18, attack = 0.005, decay = 0.35, sustain = 0, release = 0.05 })
    buf:highpass(220)
  end)

  -- Heal: a warm rising chord with a soft shimmer over it.
  bank.heal = make(1.0, function(buf)
    buf:tone(0, 0.7, 523, { wave = "sine", amp = 0.3, attack = 0.02, decay = 0.4, sustain = 0.2, release = 0.2 })
    buf:tone(0.08, 0.7, 659, { wave = "sine", amp = 0.28, attack = 0.02, decay = 0.4, sustain = 0.2, release = 0.2 })
    buf:tone(0.16, 0.7, 784, { wave = "sine", amp = 0.26, attack = 0.02, decay = 0.4, sustain = 0.2, release = 0.2 })
    buf:tone(0.24, 0.7, 1047, { wave = "tri", amp = 0.2, attack = 0.02, decay = 0.45, sustain = 0.2, release = 0.2 })
    buf:noiseBurst(0.1, 0.6, { amp = 0.08, decay = 0.25 })
    buf:highpass(200)
    buf:lowpass(6000)
  end)

  -- Panic fart: a low, wet sputter that sags in pitch as it runs out.
  bank.fart = make(0.9, function(buf)
    buf:sweep(0, 0.7, 120, 42, { wave = "saw", amp = 0.5, decay = 0.5 })
    buf:sweep(0, 0.7, 61, 30, { wave = "square", amp = 0.25, decay = 0.5 })
    for i = 0, 11 do
      buf:noiseBurst(i * 0.055, 0.03, { amp = 0.35 - i * 0.02, decay = 0.012 })
    end
    buf:drive(2.4)
    buf:lowpass(700)
  end)

  -- MG nest: sandbags thumping down and the gun's tripod clanking open.
  bank.mgnest = make(0.7, function(buf)
    buf:sweep(0, 0.2, 180, 50, { wave = "sine", amp = 0.9, decay = 0.09 })
    buf:noiseBurst(0, 0.3, { amp = 0.6, decay = 0.08 })
    buf:sweep(0.22, 0.16, 150, 45, { wave = "sine", amp = 0.7, decay = 0.07 })
    buf:noiseBurst(0.22, 0.2, { amp = 0.45, decay = 0.06 })
    buf:tone(0.42, 0.2, 1500, { wave = "square", amp = 0.25, attack = 0.001, decay = 0.05, sustain = 0 })
    buf:tone(0.5, 0.2, 2100, { wave = "square", amp = 0.2, attack = 0.001, decay = 0.05, sustain = 0 })
    buf:drive(1.8)
    buf:lowpass(3200)
  end)

  -- Open borders: a gate clanging open and a rush of feet and torches.
  bank.openborders = make(1.2, function(buf)
    buf:tone(0, 0.5, 220, { wave = "square", amp = 0.3, attack = 0.001, decay = 0.2, sustain = 0 })
    buf:tone(0.01, 0.5, 331, { wave = "square", amp = 0.2, attack = 0.001, decay = 0.25, sustain = 0 })
    buf:sweep(0.05, 0.9, 120, 60, { wave = "saw", amp = 0.25, decay = 0.4 })
    buf:noiseBurst(0.1, 1.0, { amp = 0.5, decay = 0.45 })
    buf:noiseBurst(0.35, 0.8, { amp = 0.35, decay = 0.3 })
    buf:drive(1.5)
    buf:lowpass(2600)
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
  s:setVolume(Audio.volume("abilities"))
  s:play()
  return s
end

return Sounds
