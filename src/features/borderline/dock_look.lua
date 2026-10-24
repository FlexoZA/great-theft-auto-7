-- How a hauler dock (DCK) looks (docs/borderline.md, "The army"), from
-- above at world size: a gunmetal pad with a hazard rim, a charging cradle
-- open to the south where Hyperbole parks a hauler (two clamp arms, a cable
-- glowing purple with Bragium), and on the back of the pad a plasma gun on
-- a turret that turns all the way round, its coils glowing as it charges.
--
--   Look.draw(d, clock)       d: { dx, dy, aim, charge, flash }
--       `aim` where the gun points, `charge` 0..1 its coils glowing, `flash` 0..1 just hit
--   Look.drawWreck(x, y, clock)  shot down or shut off: dark, the gun knocked askew, smoking
--   Look.RADIUS                its size, px (the health bar sits under it)

local Hauler = require("src.features.borderline.hauler_look")

local Look = {}

Look.RADIUS = 26

local C = Hauler.C
local HALF = 28 -- px, half the pad's side
local GUN_Y = -10 -- px, the turret's place on the pad (north of the middle)

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A filled box with the black outline round it.
local function plate(x, y, w, h, fill, r)
  color(C.ink)
  love.graphics.rectangle("fill", x - 1.5, y - 1.5, w + 3, h + 3, (r or 2) + 1)
  color(fill)
  love.graphics.rectangle("fill", x, y, w, h, r or 2)
end

local function disc(x, y, r, fill)
  color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.5, 20)
  color(fill)
  love.graphics.circle("fill", x, y, r, 20)
end

--- The pad and the cradle, lit (`live`) or dark.
local function pad(live, clock)
  love.graphics.setColor(0, 0, 0, 0.35) -- its shadow
  love.graphics.rectangle("fill", -HALF + 5, -HALF + 6, HALF * 2, HALF * 2, 4)
  plate(-HALF, -HALF, HALF * 2, HALF * 2, C.gunmetal, 4)
  -- The hazard rim: black and yellow blocks round the edge.
  local n = 8
  local step = HALF * 2 / n
  for i = 0, n - 1 do
    color(i % 2 == 0 and (live and C.yellow or C.yellowDark) or C.ink)
    love.graphics.rectangle("fill", -HALF + i * step, -HALF, step, 4)
    love.graphics.rectangle("fill", -HALF, -HALF + i * step, 4, step)
    love.graphics.rectangle("fill", HALF - 4, -HALF + i * step, 4, step)
  end
  -- The cradle, open to the south: a floor plate, two clamp arms either side.
  plate(-11, 2, 22, HALF - 2, C.gunmetalLight, 2)
  for _, side in ipairs({ -1, 1 }) do
    plate(side * 15 - 4, 2, 8, HALF - 6, live and C.yellow or C.yellowDark, 2)
    color(C.ink)
    love.graphics.rectangle("fill", side * 15 - 1, 8, 2, HALF - 16)
  end
  -- The charging cable along the cradle floor, glowing while it is live.
  local glow = live and (0.55 + 0.35 * math.sin(clock * 4)) or 0.15
  color(C.plasma, glow)
  love.graphics.rectangle("fill", -2, 6, 4, HALF - 10)
  if live then
    love.graphics.setBlendMode("add")
    color(C.plasma, 0.2 * glow)
    love.graphics.rectangle("fill", -6, 4, 12, HALF - 6, 3)
    love.graphics.setBlendMode("alpha")
  end
  -- The H in its hexagon, stencilled on either side of the gun.
  for _, side in ipairs({ -1, 1 }) do
    local hx, hy = side * 18, -18
    local hex = {}
    for k = 0, 5 do
      local a = k * math.pi / 3
      hex[#hex + 1] = hx + math.cos(a) * 4.5
      hex[#hex + 1] = hy + math.sin(a) * 4.5
    end
    color(live and C.yellow or C.yellowDark)
    love.graphics.polygon("fill", hex)
    color(C.ink)
    love.graphics.rectangle("fill", hx - 2.2, hy - 2.2, 1, 4.4)
    love.graphics.rectangle("fill", hx + 1.2, hy - 2.2, 1, 4.4)
    love.graphics.rectangle("fill", hx - 2.2, hy - 0.5, 4.4, 1)
  end
end

--- The plasma gun on its turret, pointing along +x (rotated by the caller).
local function gun(charge, clock, live)
  disc(0, 0, 11, live and C.yellow or C.yellowDark)
  -- The cannon: a fat barrel with purple coils down it.
  plate(4, -4.5, 20, 9, C.gunmetal, 2)
  for k = 0, 2 do
    local hot = live and math.min(1, 0.3 + charge * 0.7 + 0.15 * math.sin(clock * 9 + k)) or 0.1
    color(C.plasma, hot)
    love.graphics.rectangle("fill", 7 + k * 5, -5.5, 2.5, 11)
  end
  color(C.ink)
  love.graphics.rectangle("fill", 22, -3, 3, 6)
  if live and charge > 0 then -- the muzzle filling with plasma
    love.graphics.setBlendMode("add")
    color(C.plasmaHot, 0.5 * charge)
    love.graphics.circle("fill", 25, 0, 3 + 4 * charge, 14)
    love.graphics.setBlendMode("alpha")
  end
  disc(0, 0, 5, C.gunmetal)
  color(live and C.eye or C.rustDark, live and (0.75 + 0.25 * math.sin(clock * 5)) or 1)
  love.graphics.circle("fill", 0, 0, 2.5, 10)
end

function Look.draw(d, clock)
  local charge = d.charge or 0
  love.graphics.push()
  love.graphics.translate(d.dx, d.dy)
  pad(true, clock)
  love.graphics.push()
  love.graphics.translate(0, GUN_Y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", 3, 4, 12, 16)
  love.graphics.rotate(d.aim or 0)
  gun(charge, clock, true)
  love.graphics.pop()
  if (d.flash or 0) > 0 then
    love.graphics.setColor(1, 1, 1, 0.5 * d.flash)
    love.graphics.rectangle("fill", -HALF, -HALF, HALF * 2, HALF * 2, 4)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

function Look.drawWreck(x, y, clock)
  love.graphics.push()
  love.graphics.translate(x, y)
  pad(false, clock)
  love.graphics.push()
  love.graphics.translate(3, GUN_Y + 2)
  love.graphics.rotate(2.4 + (x % 7) * 0.1) -- knocked askew
  gun(0, clock, false)
  love.graphics.pop()
  -- Smoke curling off it.
  for k = 0, 2 do
    local t = (clock * 0.4 + k / 3) % 1
    love.graphics.setColor(0.25, 0.25, 0.27, 0.45 * (1 - t))
    love.graphics.circle("fill", 4 + k * 3 + t * 10, GUN_Y - t * 30, 5 + t * 9, 14)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
