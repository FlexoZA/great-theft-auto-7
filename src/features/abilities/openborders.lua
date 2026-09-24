-- Open borders: twenty-five simps pour out round you, each with a torch.
-- For thirty seconds they run about near you setting fires, and they
-- punch whoever they get close to, you included. A fire burns for thirty
-- seconds and hurts everything that touches it except the simps: players,
-- cars, the crowd, officers and Karen alike. Nothing to aim: press the key
-- and they are out (`aim = "self"`).
--
-- The horde and its fires belong to the open-borders feature
-- (src/features/open-borders), which hears the cast through the
-- `serverOpenBorders` event. This module only makes it an ability, so it
-- sits in a slot, sells in the shop and cools down like the others.

local Features = require("src.features")

local OpenBorders = {
  key = "openborders", -- on the wire and in a bag ("ability-openborders")
  title = "open borders",
  hud = "borders", -- short enough to fit under its ring
  sound = "openborders",
  color = { 1, 0.45, 0.12 }, -- torchlight
  aim = "self",
}

-- Tuning ------------------------------------------------------------------
OpenBorders.range = 0 -- cast where you stand
OpenBorders.radius = 120 -- px, the ring the simps pour out of
OpenBorders.seconds = 30 -- how long the simps keep lighting fires
OpenBorders.cooldown = 90 -- seconds before the next horde
OpenBorders.afterglow = 0.5

-- Server --------------------------------------------------------------------

--- Let them in. Nobody is held.
function OpenBorders.serverCast(server, caster, x, y)
  Features.call("serverOpenBorders", server, caster, x, y, OpenBorders.seconds)
  return {}
end

-- Client --------------------------------------------------------------------

--- The cast: a ring of torchlight flashing out from the caster. The horde
--- itself is drawn by the open-borders feature.
function OpenBorders.drawEffect(e)
  if e.t >= 0.6 then
    return
  end
  local c = OpenBorders.color
  local k = e.t / 0.6
  love.graphics.setLineWidth(4)
  love.graphics.setColor(c[1], c[2], c[3], 0.8 * (1 - k))
  love.graphics.circle("line", e.x, e.y, 20 + k * OpenBorders.radius, 48)
  love.graphics.setColor(1, 0.85, 0.4, 0.25 * (1 - k))
  love.graphics.circle("fill", e.x, e.y, 20 + k * OpenBorders.radius, 48)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return OpenBorders
