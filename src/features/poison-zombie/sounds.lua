-- The Poison Zombie's noises, synthesised at load and played where they
-- happen: a base source per sound, cloned per play.
--   breath   his strangled breathing: a wet, rasping in-and-out, over and over
--   howl     waking up: a long, choked howl that cracks at the top
--   grunt    heaving a crab off his back to throw it
--   claw     his swipe: a heavy whoosh
--   chitter  a crab on the move: a dry rattle
--   screech  a crab leaping: a thin hissing shriek
--   bite     a crab biting home
--   squish   a crab dying

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.85, -- default of the "poison-zombie" channel
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
  Audio.registerChannel("poison-zombie", "Poison Zombie", Sounds.volume, function()
    Sounds.play("howl", 0, 0)
  end)

  bank.breath = make(1.6, function(buf)
    -- In: a rasp through a closed throat; out: a lower, bubbling groan.
    buf:noiseBurst(0, 0.6, { amp = 0.3, decay = 0.5 })
    buf:sweep(0.05, 0.55, 220, 260, { wave = "saw", amp = 0.08, attack = 0.2, decay = 0.35 })
    buf:tone(0.75, 0.75, 82, { wave = "saw", amp = 0.3, attack = 0.08, decay = 0.6, sustain = 0.5, release = 0.15,
      vibRate = 11, vibDepth = 1.2 })
    buf:noiseBurst(0.75, 0.7, { amp = 0.18, decay = 0.6 })
    buf:lowpass(900)
  end)

  bank.howl = make(1.8, function(buf)
    buf:sweep(0, 0.9, 120, 300, { wave = "saw", amp = 0.45, attack = 0.15, decay = 0.9 })
    buf:sweep(0.8, 0.9, 300, 140, { wave = "saw", amp = 0.4, decay = 0.8 })
    buf:sweep(0, 1.7, 61, 70, { wave = "square", amp = 0.15, attack = 0.2, decay = 1.5 })
    buf:noiseBurst(0, 1.7, { amp = 0.22, decay = 1.4 })
    buf:drive(2.2)
    buf:lowpass(1500)
  end)

  bank.grunt = make(0.45, function(buf)
    buf:sweep(0, 0.35, 140, 90, { wave = "saw", amp = 0.45, attack = 0.02, decay = 0.3 })
    buf:noiseBurst(0, 0.3, { amp = 0.2, decay = 0.2 })
    buf:drive(1.8)
    buf:lowpass(1000)
  end)

  bank.claw = make(0.35, function(buf)
    buf:noiseBurst(0, 0.3, { amp = 0.4, decay = 0.18 })
    buf:sweep(0, 0.25, 300, 90, { wave = "sine", amp = 0.25, decay = 0.2 })
    buf:lowpass(2200)
  end)

  bank.chitter = make(0.3, function(buf)
    for i = 0, 5 do
      local t = i * 0.04
      buf:noiseBurst(t, 0.015, { amp = 0.3, decay = 0.006 })
      buf:tone(t, 0.02, 1900 + (i % 3) * 260,
        { wave = "square", amp = 0.06, attack = 0.001, decay = 0.01, sustain = 0 })
    end
    buf:highpass(900)
  end)

  bank.screech = make(0.45, function(buf)
    buf:sweep(0, 0.4, 1500, 2600,
      { wave = "saw", amp = 0.2, attack = 0.02, decay = 0.35, vibRate = 30, vibDepth = 0.8 })
    buf:noiseBurst(0, 0.4, { amp = 0.2, decay = 0.3 })
    buf:highpass(700)
  end)

  bank.bite = make(0.3, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 0.55, decay = 0.03 })
    buf:sweep(0, 0.2, 600, 180, { wave = "square", amp = 0.2, decay = 0.15 })
    buf:noiseBurst(0.08, 0.2, { amp = 0.2, decay = 0.12 }) -- the hiss of the poison going in
    buf:lowpass(3500)
  end)

  bank.squish = make(0.35, function(buf)
    buf:sweep(0, 0.25, 260, 70, { wave = "sine", amp = 0.5, decay = 0.15 })
    buf:noiseBurst(0, 0.15, { amp = 0.35, decay = 0.06 })
    buf:lowpass(1400)
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
  s:setVolume(Audio.volume("poison-zombie"))
  s:play()
  return s
end

return Sounds
