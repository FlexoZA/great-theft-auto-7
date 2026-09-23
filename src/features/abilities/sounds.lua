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
