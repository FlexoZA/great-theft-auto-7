-- A crate breaking open: the lid's boards cracking, a thud, and rounds
-- rattling out. Synthesised at load and played as a positioned clone, on
-- the pickups' volume.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {}
local base

function Sounds.load()
  local buf = Synth.newBuffer(0.6)
  buf:noiseBurst(0, 0.05, { amp = 0.7, decay = 0.012 }) -- the first crack
  buf:noiseBurst(0.045, 0.06, { amp = 0.55, decay = 0.015 })
  buf:noiseBurst(0.1, 0.04, { amp = 0.4, decay = 0.01 })
  buf:kick(0.02, 0.6) -- the lid landing
  buf:lowpass(2600) -- wood, not glass
  local rattle = Synth.newBuffer(0.6)
  for i = 0, 5 do
    rattle:hat(0.14 + i * 0.055 + (i % 2) * 0.012, 0.25 - i * 0.03)
  end
  rattle:mixInto(buf, 0.8)
  base = love.audio.newSource(buf:toSoundData(0.85), "static")
  base:setAttenuationDistances(300, 2200)
end

function Sounds.play(x, y)
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(0.9 + love.math.random() * 0.2)
  s:setVolume(Audio.volume("pickups"))
  s:play()
end

return Sounds
