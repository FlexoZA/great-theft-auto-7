-- The bluff's noises, synthesised at load and played where they happen,
-- the way the other bosses' are: a base source per sound, cloned per play.
-- His rifle and pistol are weapons' own sounds.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "shotgun" channel
  refDistance = 400,
  maxDistance = 3200,
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
  Audio.registerChannel("shotgun", "The bluff: Shotgun's warnings", Sounds.volume, function()
    Sounds.play("lock", 0, 0)
  end)

  -- A bead drawn on you: a second of beeps getting quicker and higher,
  -- ending in one long tone as the aim locks.
  bank.lock = make(1.0, function(buf)
    local t, gap, f = 0, 0.22, 1300
    while t < 0.72 do
      buf:tone(t, 0.05, f, { wave = "square", amp = 0.22, attack = 0.002, decay = 0.03, sustain = 0.4, release = 0.01 })
      t, gap, f = t + gap, gap * 0.72, f + 90
    end
    buf:tone(0.75, 0.25, 1900, {
      wave = "square", amp = 0.2, attack = 0.002, decay = 0.1, sustain = 0.7, release = 0.03,
    })
    buf:lowpass(6000)
  end)

  -- His entrance: a gavel banged three times and a sour horn.
  bank.gavel = make(1.6, function(buf)
    for i = 0, 2 do
      local t = i * 0.22
      buf:noiseBurst(t, 0.06, { amp = 0.9, decay = 0.015 })
      buf:sweep(t, 0.12, 260, 90, { wave = "sine", amp = 0.9, decay = 0.05 })
    end
    buf:tone(0.75, 0.8, 233, { wave = "saw", amp = 0.25, attack = 0.03, decay = 0.5, sustain = 0.6, release = 0.1,
      detune = -30, vibRate = 6, vibDepth = 0.3 })
    buf:tone(0.75, 0.8, 247, { wave = "saw", amp = 0.2, attack = 0.03, decay = 0.5, sustain = 0.6, release = 0.1 })
    buf:drive(1.8)
    buf:lowpass(3000)
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
  s:setVolume(Audio.volume("shotgun"))
  s:play()
  return s
end

return Sounds
