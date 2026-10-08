-- The Suppressors' noises, synthesised at load and played where they
-- happen: a base source per sound, cloned per play. The minigun's rounds
-- are quiet in weapons (its gun is `quiet`), so every screen plays them
-- here, one per round while the host says it is firing.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "suppressors" channel
  refDistance = 360,
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
  Audio.registerChannel("suppressors", "Suppressors", Sounds.volume, function()
    Sounds.play("spinup", 0, 0)
  end)

  -- The barrels winding up: a motor's whine climbing, a rattle under it.
  bank.spinup = make(0.95, function(buf)
    buf:sweep(0, 0.9, 90, 420, { wave = "saw", amp = 0.2, decay = 4 })
    buf:sweep(0, 0.9, 180, 840, { wave = "square", amp = 0.05, decay = 4 })
    for i = 0, 11 do
      buf:noiseBurst(i * 0.075 * (1 - i / 30), 0.012, { amp = 0.12, decay = 0.008 })
    end
    buf:lowpass(3200)
  end)
  -- And winding down again.
  bank.spindown = make(1.5, function(buf)
    buf:sweep(0, 1.45, 420, 70, { wave = "saw", amp = 0.18, decay = 0.6 })
    buf:sweep(0, 1.2, 840, 140, { wave = "square", amp = 0.05, decay = 0.5 })
    buf:lowpass(2600)
  end)
  -- One round: a hard crack with a thump behind it, short enough to run
  -- together at twelve a second into the minigun's roar.
  bank.shot = make(0.11, function(buf)
    buf:noiseBurst(0, 0.05, { amp = 0.7, decay = 0.025 })
    buf:tone(0, 0.08, 95, { wave = "sine", amp = 0.5, attack = 0.001, decay = 0.05, sustain = 0 })
    buf:tone(0, 0.04, 260, { wave = "square", amp = 0.15, attack = 0.001, decay = 0.02, sustain = 0 })
    buf:drive(1.6)
    buf:lowpass(5200)
  end)
  -- Venting: a hiss of hot air off the barrels.
  bank.vent = make(1.3, function(buf)
    buf:noiseBurst(0, 1.25, { amp = 0.3, decay = 0.9 })
    buf:highpass(1800)
  end)
  -- His shield going down: a falling electric zap and a crackle.
  bank.shieldbreak = make(0.7, function(buf)
    buf:sweep(0, 0.5, 1600, 180, { wave = "saw", amp = 0.25, decay = 0.35 })
    buf:sweep(0.02, 0.45, 2400, 300, { wave = "square", amp = 0.08, decay = 0.3 })
    for i = 0, 7 do
      buf:noiseBurst(0.05 + i * 0.07, 0.02, { amp = 0.25, decay = 0.012 })
    end
    buf:lowpass(5000)
  end)
end

--- Play `name` at world position (x, y).
function Sounds.play(name, x, y, pitch, gain)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(pitch or 1)
  s:setVolume(Audio.volume("suppressors") * (gain or 1))
  s:play()
  return s
end

return Sounds
