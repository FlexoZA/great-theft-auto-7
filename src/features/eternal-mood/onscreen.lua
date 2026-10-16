-- What a monster of the horde's elite needs on every screen, shared by the
-- Dread Knights (dread_knight.lua) and the Mecha Zombies (mecha_zombie.lua):
-- its sounds made once and played where they happen, and where it is shown
-- eased after where the host says it is.

local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Onscreen = {}

local random = love.math.random

--- A sound `seconds` long, `build(buf)` writing it, at `volume`, heard from
--- `near` to `far` px off.
function Onscreen.sound(seconds, volume, build, near, far)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local src = love.audio.newSource(buf:toSoundData(volume), "static")
  src:setAttenuationDistances(near or 250, far or 2200)
  return src
end

--- Play `bank[name]` at (x, y): a copy of it, pitched a little either way so
--- a crowd doesn't sound like one, at the weapons' volume.
function Onscreen.play(bank, name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.92 + random() * 0.16)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

--- Ease every one in `shown` ({ x, y, dx, dy, stride }) towards where the
--- host last put it, snapping when it is far off; `stride` counts the
--- distance its legs have covered.
function Onscreen.ease(shown, dt)
  local k = math.min(1, dt * 14)
  for _, m in pairs(shown) do
    local ex, ey = m.x - m.dx, m.y - m.dy
    if ex * ex + ey * ey > 300 * 300 then
      m.dx, m.dy = m.x, m.y
    else
      m.dx, m.dy = m.dx + ex * k, m.dy + ey * k
      m.stride = m.stride + math.sqrt(ex * ex + ey * ey) * k
    end
  end
end

return Onscreen
