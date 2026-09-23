-- The forest's noises, synthesised at load and played where they happen,
-- the way Karen's are: a base source per sound, cloned per play.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "alien-hunt" channel
  refDistance = 320,
  maxDistance = 2600,
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
  Audio.registerChannel("alien-hunt", "Bigfoot and the squirrels", Sounds.volume, function()
    Sounds.play("roar", 0, 0)
  end)

  -- Roar: a low saw swelling up and wobbling, a throatful of noise, driven
  -- until it tears, and dropping away at the end.
  bank.roar = make(1.8, function(buf)
    buf:sweep(0, 0.25, 70, 140, { wave = "saw", amp = 0.5, decay = 0.4 })
    buf:tone(0.1, 1.3, 120, { wave = "saw", amp = 0.6, attack = 0.12, decay = 2, sustain = 0.8, release = 0.3,
      vibRate = 11, vibDepth = 1.2 })
    buf:tone(0.12, 1.25, 181, { wave = "square", amp = 0.22, attack = 0.1, decay = 2, sustain = 0.7, release = 0.3,
      vibRate = 11, vibDepth = 1.2, detune = 18 })
    buf:noiseBurst(0.05, 1.5, { amp = 0.35, decay = 0.9 })
    buf:sweep(1.3, 0.45, 150, 60, { wave = "saw", amp = 0.45, decay = 0.25 })
    buf:drive(3)
    buf:lowpass(1800)
  end)

  -- Slam: a thump you feel, and dirt coming down after it.
  bank.slam = make(0.9, function(buf)
    buf:sweep(0, 0.5, 110, 32, { wave = "sine", amp = 0.9, decay = 0.2 })
    buf:noiseBurst(0, 0.7, { amp = 0.4, decay = 0.18 })
    buf:drive(1.8)
    buf:lowpass(900)
  end)

  -- Squirrel: a rapid, angry chitter.
  bank.chitter = make(0.45, function(buf)
    for i = 0, 6 do
      buf:sweep(i * 0.055, 0.04, 2600 + (i % 3) * 300, 1700, { wave = "square", amp = 0.25, decay = 0.02 })
    end
    buf:highpass(900)
  end)

  -- Wild man vanishing: a comedy swoosh upwards.
  bank.poof = make(0.5, function(buf)
    buf:sweep(0, 0.4, 300, 1800, { wave = "tri", amp = 0.4, decay = 0.3 })
    buf:noiseBurst(0, 0.3, { amp = 0.2, decay = 0.1 })
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
  s:setVolume(Audio.volume("alien-hunt"))
  s:play()
  return s
end

return Sounds
