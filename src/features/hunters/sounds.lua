-- The Hunters' noises, synthesised at load and played where they happen: a
-- base source per sound, cloned per play.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {
  volume = 0.8, -- default of the "hunters" channel
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
  Audio.registerChannel("hunters", "Hunters", Sounds.volume, function()
    Sounds.play("call", 0, 0)
  end)

  -- One calling the others: a rising, warbling whine with a buzzing edge
  -- under it, twice, the second higher, and a click of its pods.
  bank.call = make(1.0, function(buf)
    for i = 0, 1 do
      local t, f = i * 0.34, 520 + i * 180
      buf:sweep(t, 0.3, f, f * 1.9, { wave = "saw", amp = 0.24, decay = 0.25 })
      buf:sweep(t, 0.3, f * 0.5, f * 0.95, { wave = "square", amp = 0.1, decay = 0.2 })
      buf:tone(t + 0.05, 0.25, f * 2.4, { wave = "sine", amp = 0.1, attack = 0.05, decay = 0.15, sustain = 0.3,
        vibRate = 24, vibDepth = 0.8 }) -- the warble over it
    end
    buf:noiseBurst(0.72, 0.03, { amp = 0.4, decay = 0.01 })
    buf:tone(0.72, 0.05, 1800, { wave = "sine", amp = 0.2, attack = 0.001, decay = 0.02, sustain = 0 })
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
  s:setVolume(Audio.volume("hunters"))
  s:play()
  return s
end

return Sounds
