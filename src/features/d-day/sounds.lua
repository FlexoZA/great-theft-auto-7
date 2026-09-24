-- The beach's noises, synthesised at load and played where they happen, the
-- way the other bosses' are: a base source per sound, cloned per play. The
-- rifles and the mortar blasts are weapons' own sounds.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "d-day" channel
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
  Audio.registerChannel("d-day", "The beach: mortars and the Major", Sounds.volume, function()
    Sounds.play("whistle", 0, 0)
  end)

  -- A mortar coming in: a thin whistle falling in pitch.
  bank.whistle = make(1.3, function(buf)
    buf:sweep(0, 1.25, 1700, 520, { wave = "sine", amp = 0.35, decay = 3 })
    buf:sweep(0, 1.25, 1720, 530, { wave = "tri", amp = 0.08, decay = 3 })
  end)

  -- The Major's bugle: a short, proud, slightly flat call to attention.
  bank.bugle = make(1.9, function(buf)
    local notes = { { "G4", 0.18 }, { "C5", 0.18 }, { "E5", 0.18 }, { "G5", 0.5 }, { "E5", 0.2 }, { "G5", 0.6 } }
    local t = 0
    for _, n in ipairs(notes) do
      local f = Synth.freq(n[1])
      buf:tone(t, n[2], f, { wave = "saw", amp = 0.28, attack = 0.02, decay = 0.6, sustain = 0.7, release = 0.06,
        detune = -18, vibRate = 5, vibDepth = 0.15 })
      buf:tone(t, n[2], f * 2, { wave = "square", amp = 0.06, attack = 0.02, decay = 0.4, sustain = 0.5,
        release = 0.06, detune = -18 })
      t = t + n[2] + 0.03
    end
    buf:lowpass(3200)
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
  s:setVolume(Audio.volume("d-day"))
  s:play()
  return s
end

return Sounds
