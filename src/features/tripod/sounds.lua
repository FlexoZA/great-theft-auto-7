-- The tripod's noises, synthesised at load and played where they happen,
-- the way the other bosses' are: a base source per sound, cloned per play.
-- The horn carries across the whole city.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "tripod" channel
  refDistance = 500,
  maxDistance = 4000,
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
  Audio.registerChannel("tripod", "The tripod: its horn and heat ray", Sounds.volume, function()
    Sounds.play("horn", 0, 0)
  end)

  -- The horn: a vast, flat, brassy blare that swells, holds and dies away,
  -- two notes a little apart grinding against each other, rumbling under it.
  bank.horn = make(3.6, function(buf)
    local o = { wave = "saw", amp = 0.28, attack = 0.35, decay = 0.4, sustain = 0.85, release = 0.9,
      vibRate = 3, vibDepth = 0.15 }
    buf:tone(0, 3.4, 58, o)
    buf:tone(0, 3.4, 87, o)
    buf:tone(0.05, 3.3, 116, { wave = "saw", amp = 0.2, attack = 0.4, decay = 0.4, sustain = 0.8, release = 0.9,
      detune = 18 })
    buf:tone(0.05, 3.3, 174, { wave = "square", amp = 0.08, attack = 0.5, decay = 0.4, sustain = 0.7, release = 0.9 })
    buf:noiseBurst(0, 3.2, { amp = 0.12, decay = 1.6 })
    buf:drive(2.6)
    buf:lowpass(1400)
  end)

  -- Thunder: a crack right overhead and a long rumble rolling away.
  bank.thunder = make(2.8, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 1.0, decay = 0.02 })
    buf:sweep(0, 0.2, 900, 120, { wave = "saw", amp = 0.5, decay = 0.06 })
    buf:noiseBurst(0.03, 2.7, { amp = 0.8, decay = 0.9 })
    buf:sweep(0.05, 2.5, 90, 35, { wave = "sine", amp = 0.6, decay = 1.0 })
    buf:drive(2.4)
    buf:lowpass(1600)
  end)

  -- The heat ray warming up: a whine climbing for two seconds.
  bank.charge = make(2.0, function(buf)
    buf:sweep(0, 2.0, 180, 1600, { wave = "sine", amp = 0.35, decay = 3 })
    buf:sweep(0, 2.0, 360, 3200, { wave = "square", amp = 0.06, decay = 3 })
    buf:lowpass(5000)
  end)

  -- The heat ray burning: a crackling roar with a buzz in it.
  bank.burn = make(1.6, function(buf)
    buf:noiseBurst(0, 1.6, { amp = 0.6, decay = 1.2 })
    buf:tone(0, 1.5, 220, { wave = "square", amp = 0.18, attack = 0.01, decay = 0.2, sustain = 0.8, release = 0.2,
      vibRate = 30, vibDepth = 0.6 })
    buf:tone(0, 1.5, 1800, { wave = "sine", amp = 0.12, attack = 0.01, decay = 0.2, sustain = 0.8, release = 0.2 })
    buf:drive(2.2)
    buf:lowpass(4200)
  end)

  -- A tentacle lashing down: a whip crack and a wet slap.
  bank.grab = make(0.5, function(buf)
    buf:sweep(0, 0.12, 2400, 300, { wave = "saw", amp = 0.4, decay = 0.05 })
    buf:noiseBurst(0.08, 0.2, { amp = 0.7, decay = 0.05 })
    buf:sweep(0.1, 0.3, 180, 70, { wave = "sine", amp = 0.6, decay = 0.1 })
    buf:drive(2)
    buf:lowpass(3000)
  end)

  -- Going down: a groan of metal and a long crash.
  bank.fall = make(2.4, function(buf)
    buf:sweep(0, 1.2, 140, 40, { wave = "saw", amp = 0.4, decay = 0.8 })
    buf:noiseBurst(1.0, 1.4, { amp = 0.9, decay = 0.5 })
    buf:sweep(1.0, 0.8, 120, 30, { wave = "sine", amp = 1.0, decay = 0.4 })
    buf:drive(2.4)
    buf:lowpass(1800)
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
  s:setVolume(Audio.volume("tripod"))
  s:play()
  return s
end

return Sounds
