-- Dodging: a boss sees a player's ability coming down on it (a freeze's
-- warning ring, a leaper about to land, a heat ray burning) and gets out
-- from under it. Every area comes from abilities' `serverIncoming`. A boss
-- needs `react` seconds to notice one, so a cast right on top of it with
-- little warning still catches it; after that it heads straight out from
-- the middle until it is clear of the edge.
--
-- A boss with the stink rule (a `panic` it runs from: Karen, Shotgun, the
-- Major, Bigfoot) calls `Dodge.step(b, radius)` once a tick before its
-- panic is read, and runs from the area as it would from a stink. One that
-- moves its own way asks `Dodge.threat(x, y, radius)` and goes `Dodge.away`.

local Features = require("src.features")

local Dodge = {}

-- Tuning ------------------------------------------------------------------
Dodge.react = 0.2 -- seconds after an area shows before a boss moves for it
Dodge.margin = 20 -- px past the edge it wants to be
Dodge.hold = 0.15 -- seconds a dodge runs on for once the area has gone (it is checked again every tick)

--- The area about to hit a body of `radius` at (x, y) that it has had
--- time to see, the one it is deepest in; nil for none.
function Dodge.threat(x, y, radius)
  local abilities = Features.byName.abilities
  if not (abilities and abilities.serverIncoming) then
    return nil
  end
  local best, deepest = nil, 0
  for _, a in ipairs(abilities:serverIncoming()) do
    if a.age >= Dodge.react then
      local dx, dy = x - a.x, y - a.y
      local depth = a.radius + radius + Dodge.margin - math.sqrt(dx * dx + dy * dy)
      if depth > deepest then
        best, deepest = a, depth
      end
    end
  end
  return best
end

--- Which way is out of area `a` from (x, y): a unit vector from its middle
--- (any way at all from right on it).
function Dodge.away(a, x, y)
  local dx, dy = x - a.x, y - a.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then
    local t = love.math.random() * 2 * math.pi
    return math.cos(t), math.sin(t)
  end
  return dx / d, dy / d
end

--- A boss with the stink rule: under something about to land, it runs
--- from it as from a stink (sets `b.panic`).
function Dodge.step(b, radius)
  local a = Dodge.threat(b.x, b.y, radius)
  if a then
    local ux, uy = Dodge.away(a, b.x, b.y)
    b.panic = { x = b.x - ux, y = b.y - uy, left = Dodge.hold } -- just behind it, so it runs straight out
  end
end

return Dodge
