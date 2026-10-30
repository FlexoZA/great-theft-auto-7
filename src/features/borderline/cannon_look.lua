-- How a rim cannon (CAN) looks (docs/borderline.md, "8. The Bunker"), from
-- above at world size: an armoured base ringed with hazard paint, bolted to
-- the deck, and on it a turret with a long twin barrel, its muzzle
-- glowing as it charges a shell.
--
--   Look.draw(d, clock)       d: { dx, dy, aim, charge, flash }
--       `aim` where the barrels point, `charge` 0..1 the muzzle glowing, `flash` 0..1 just hit
--   Look.drawWreck(x, y, clock)  shot down: dark, the barrels knocked askew, smoking
--   Look.RADIUS                its size, px (the health bar sits under it)

local Hauler = require("src.features.borderline.hauler_look")

local Look = {}

Look.RADIUS = 30

local C = Hauler.C

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function disc(x, y, r, fill)
  color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.5, 24)
  color(fill)
  love.graphics.circle("fill", x, y, r, 24)
end

--- The base: armour, a hazard ring, bolts round it.
local function base(live)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", 5, 6, Look.RADIUS, 24)
  disc(0, 0, Look.RADIUS, C.gunmetal)
  for k = 0, 11 do -- the hazard ring
    color(k % 2 == 0 and (live and C.yellow or C.yellowDark) or C.ink)
    love.graphics.arc("fill", 0, 0, Look.RADIUS - 1, k * math.pi / 6, (k + 1) * math.pi / 6, 4)
  end
  disc(0, 0, Look.RADIUS - 6, C.gunmetal)
  color(C.ink)
  for k = 0, 7 do
    local a = k * math.pi / 4 + 0.2
    love.graphics.circle("fill", math.cos(a) * (Look.RADIUS - 10), math.sin(a) * (Look.RADIUS - 10), 1.8, 6)
  end
end

--- The turret and its barrels, pointing along +x (rotated by the caller).
local function turret(charge, clock, live)
  for _, side in ipairs({ -1, 1 }) do -- the twin barrels
    color(C.ink)
    love.graphics.rectangle("fill", 6, side * 5.5 - 4, 34, 8, 2)
    color(live and C.gunmetalLight or C.gunmetal)
    love.graphics.rectangle("fill", 7, side * 5.5 - 3, 32, 6, 2)
    color(C.ink)
    love.graphics.rectangle("fill", 36, side * 5.5 - 4, 4, 8)
  end
  if live and charge > 0 then -- the muzzles glowing
    love.graphics.setBlendMode("add")
    color(C.flame, 0.6 * charge)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.circle("fill", 41, side * 5.5, 3 + 5 * charge + math.sin(clock * 30) * charge, 12)
    end
    love.graphics.setBlendMode("alpha")
  end
  disc(0, 0, 15, live and C.yellow or C.yellowDark) -- the turret
  color(C.ink)
  love.graphics.rectangle("fill", -10, -2, 20, 4)
  disc(-4, 0, 5, C.gunmetal)
  color(live and C.eye or C.rustDark, live and (0.75 + 0.25 * math.sin(clock * 5)) or 1)
  love.graphics.circle("fill", -4, 0, 2.5, 10)
end

function Look.draw(d, clock)
  love.graphics.push()
  love.graphics.translate(d.dx, d.dy)
  base(true)
  love.graphics.push()
  love.graphics.rotate(d.aim or 0)
  turret(d.charge or 0, clock, true)
  love.graphics.pop()
  if (d.flash or 0) > 0 then
    love.graphics.setColor(1, 1, 1, 0.5 * d.flash)
    love.graphics.circle("fill", 0, 0, Look.RADIUS, 24)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

function Look.drawWreck(x, y, clock)
  love.graphics.push()
  love.graphics.translate(x, y)
  base(false)
  love.graphics.push()
  love.graphics.translate(2, 3)
  love.graphics.rotate(1.9 + (x % 7) * 0.2) -- knocked askew
  turret(0, clock, false)
  love.graphics.pop()
  for k = 0, 2 do -- smoke curling off it
    local t = (clock * 0.4 + k / 3) % 1
    love.graphics.setColor(0.25, 0.25, 0.27, 0.45 * (1 - t))
    love.graphics.circle("fill", 4 + k * 3 + t * 12, -t * 36, 6 + t * 10, 14)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
