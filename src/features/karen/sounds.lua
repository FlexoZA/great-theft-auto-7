-- Karen's voice, synthesised at load and played where she stands, the way
-- the weapons do it: a base source per sound, cloned per play.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "karen" channel
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
  Audio.registerChannel("karen", "Karen's screams", Sounds.volume, function()
    Sounds.play("scream", 0, 0)
  end)

  -- Scream: a ragged saw with a wide wobble, a rasp of noise, driven hard,
  -- rising into it and cracking off at the end.
  bank.scream = make(1.1, function(buf)
    buf:sweep(0, 0.12, 320, 780, { wave = "saw", amp = 0.5, decay = 0.2 })
    buf:tone(0.08, 0.75, 760, { wave = "saw", amp = 0.55, attack = 0.02, decay = 1.5, sustain = 0.8, release = 0.12,
      vibRate = 8, vibDepth = 1.6 })
    buf:tone(0.1, 0.72, 1140, { wave = "square", amp = 0.18, attack = 0.02, decay = 1.5, sustain = 0.7, release = 0.1,
      vibRate = 8, vibDepth = 1.6, detune = 12 })
    buf:noiseBurst(0.08, 0.8, { amp = 0.22, decay = 0.5 })
    buf:sweep(0.82, 0.2, 700, 380, { wave = "saw", amp = 0.4, decay = 0.08 })
    buf:drive(2.4)
    buf:highpass(260)
    buf:lowpass(4200)
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
  s:setVolume(Audio.volume("karen"))
  s:play()
  return s
end

return Sounds
