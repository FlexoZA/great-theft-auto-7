-- How the line's bosses (boss_list.lua) and what they fire (mines.lua) make
-- and play their sounds: each builds its own bank with the synth when the
-- game loads, and plays out of it at a spot in the world, on the guns'
-- volume slider.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Sound = {}

Sound.NEAR, Sound.FAR = 300, 2600 -- px: full volume this near, nothing past this far (a boss is loud)

--- A sound `seconds` long that `synth(buf)` builds, at `volume`; heard
--- from `near` to `far` px (a boss's NEAR and FAR otherwise).
function Sound.make(seconds, volume, synth, near, far)
  local buf = Synth.newBuffer(seconds)
  synth(buf)
  local src = love.audio.newSource(buf:toSoundData(volume), "static")
  src:setAttenuationDistances(near or Sound.NEAR, far or Sound.FAR)
  return src
end

--- Play `base` at (x, y) (everywhere at once without them), its pitch
--- wandering `spread` either way.
function Sound.play(base, x, y, spread)
  if not base then
    return
  end
  local s = base:clone()
  if x then
    s:setPosition(x, 0, y)
  else
    s:setRelative(true)
  end
  if spread and spread > 0 then
    s:setPitch(1 - spread + love.math.random() * 2 * spread)
  end
  s:setVolume(0.8 * Audio.volume("weapons"))
  s:play()
end

return Sound
