-- The antlions' noises, synthesised at load and played where they happen:
-- a base source per sound, cloned per play.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "antlions" channel
  refDistance = 300,
  maxDistance = 2000,
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
  Audio.registerChannel("antlions", "Antlions", Sounds.volume, function()
    Sounds.play("emerge", 0, 0)
  end)

  -- Coming up out of the sand: a low heave and a long hiss of sand
  -- pouring off it, a scrabble of claws through it.
  bank.emerge = make(0.9, function(buf)
    buf:sweep(0, 0.5, 70, 45, { wave = "sine", amp = 0.5, decay = 0.4 })
    buf:noiseBurst(0.02, 0.8, { amp = 0.35, decay = 0.5 })
    for i = 0, 5 do
      buf:noiseBurst(0.15 + i * 0.09, 0.02, { amp = 0.3, decay = 0.012 })
    end
    buf:lowpass(2400)
  end)

  -- The chitter it makes rushing in: a run of dry clicks, rising.
  bank.chitter = make(0.45, function(buf)
    for i = 0, 7 do
      local t = i * 0.05
      buf:tone(t, 0.02, 1500 + i * 120, { wave = "square", amp = 0.18, attack = 0.001, decay = 0.012, sustain = 0 })
      buf:noiseBurst(t, 0.012, { amp = 0.22, decay = 0.006 })
    end
    buf:highpass(700)
  end)

  -- A bite: the mandibles snapping shut, hard and dry.
  bank.bite = make(0.18, function(buf)
    buf:noiseBurst(0, 0.03, { amp = 0.6, decay = 0.012 })
    buf:tone(0, 0.05, 900, { wave = "square", amp = 0.25, attack = 0.001, decay = 0.03, sustain = 0 })
    buf:noiseBurst(0.06, 0.02, { amp = 0.35, decay = 0.01 })
    buf:highpass(400)
  end)

  -- A leap: the wings opening into a fast, buzzing drone.
  bank.buzz = make(0.6, function(buf)
    buf:tone(0, 0.55, 140, { wave = "saw", amp = 0.28, attack = 0.04, decay = 0.2, sustain = 0.6, vibRate = 38,
      vibDepth = 3 })
    buf:tone(0, 0.55, 285, { wave = "square", amp = 0.1, attack = 0.04, decay = 0.2, sustain = 0.5 })
    buf:lowpass(3000)
  end)

  -- The Guard coming up: a long, deep heave of the ground under you.
  bank.rumble = make(2.2, function(buf)
    buf:sweep(0, 2.0, 55, 32, { wave = "sine", amp = 0.7, decay = 1.6 })
    buf:sweep(0, 1.8, 90, 50, { wave = "saw", amp = 0.18, decay = 1.4 })
    buf:noiseBurst(0, 2.1, { amp = 0.35, decay = 1.6 })
    buf:lowpass(900)
  end)

  -- The Guard's growl, pawing the sand or rearing: a grinding, chittering low snarl.
  bank.growl = make(1.0, function(buf)
    buf:tone(0, 0.9, 85, { wave = "saw", amp = 0.45, attack = 0.08, decay = 0.4, sustain = 0.7, vibRate = 18,
      vibDepth = 6 })
    for i = 0, 9 do
      buf:noiseBurst(0.05 + i * 0.08, 0.03, { amp = 0.2, decay = 0.015 })
    end
    buf:lowpass(1600)
  end)

  -- The scream: a huge rising shriek over a roar, with a shudder of noise under it.
  bank.scream = make(1.4, function(buf)
    buf:sweep(0, 0.9, 380, 1400, { wave = "saw", amp = 0.32, decay = 0.6 })
    buf:sweep(0.05, 1.0, 520, 1900, { wave = "square", amp = 0.14, decay = 0.7 })
    buf:tone(0, 1.2, 70, { wave = "saw", amp = 0.5, attack = 0.02, decay = 0.6, sustain = 0.5, vibRate = 26,
      vibDepth = 8 })
    buf:noiseBurst(0, 1.2, { amp = 0.4, decay = 0.9 })
    buf:lowpass(5200)
  end)

  -- The Guard running into something: a heavy, dull thud.
  bank.thud = make(0.6, function(buf)
    buf:sweep(0, 0.4, 120, 40, { wave = "sine", amp = 0.8, decay = 0.25 })
    buf:noiseBurst(0, 0.15, { amp = 0.5, decay = 0.06 })
    buf:lowpass(1200)
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
  s:setVolume(Audio.volume("antlions"))
  s:play()
  return s
end

return Sounds
