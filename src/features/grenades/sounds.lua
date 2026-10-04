-- Grenade sounds, synthesised at load and played as positioned clones on
-- the "weapons" channel (the blast itself is weapons' explosion):
--   throw   the pin's ping and the spoon flicking off, then a quick whoosh

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sounds = {}
local bank = {}

function Sounds.load()
  local buf = Synth.newBuffer(0.4)
  buf:tone(0, 0.05, 2900, { wave = "sine", amp = 0.35, attack = 0.001, decay = 0.04, sustain = 0, release = 0.02 })
  buf:tone(0.004, 0.05, 4350, { wave = "sine", amp = 0.15, attack = 0.001, decay = 0.03, sustain = 0, release = 0.02 })
  buf:noiseBurst(0.06, 0.02, { amp = 0.35, decay = 0.006 }) -- the spoon
  buf:noiseBurst(0.1, 0.28, { amp = 0.4, decay = 0.09 }) -- the arm going through
  buf:lowpass(5200)
  bank.throw = love.audio.newSource(buf:toSoundData(0.7), "static")
  bank.throw:setAttenuationDistances(200, 1600)
end

--- Play `name` at world position (x, y).
function Sounds.play(name, x, y)
  local base = bank[name]
  if not base then
    return
  end
  local s = base:clone()
  s:setPosition(x, 0, y)
  s:setPitch(0.95 + love.math.random() * 0.1)
  s:setVolume(Audio.volume("weapons"))
  s:play()
end

return Sounds
