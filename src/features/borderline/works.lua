-- The working parts of Hyperbole's grounds (docs/borderline.md, "Maps"),
-- drawn every frame on every screen, moving: the tower cranes swinging
-- their jibs back and forth over the excavations, a trolley running in and
-- out along each jib with a load swaying under it, a red light blinking
-- at its tip; and the emergency beacons turning, amber and red, their
-- beams sweeping the ground. From the map (city-map's borderline.lua:
-- `map.cranes`, `map.beacons`). Scenery only: nothing here is on the host
-- or touches anyone, and each screen keeps its own clock.

local Hauler = require("src.features.borderline.hauler_look")

local Works = {}

local C = Hauler.C
local BEACON = { amber = { 1.00, 0.62, 0.10 }, red = { 1.00, 0.15, 0.10 } }
local LIFT = 26 -- px the cranes' parts are drawn up off the ground (their shadows lie there)

local clock = 0

function Works.update(dt)
  clock = clock + dt
end

local function ease(t)
  return 0.5 - 0.5 * math.cos(t)
end

--- Where crane `c`'s jib points, and how far out its trolley is, now.
local function pose(c)
  local a = c.from + c.sweep * ease(2 * math.pi * clock / c.period + c.phase)
  local out = c.jib * (0.35 + 0.5 * ease(2 * math.pi * clock / (c.period * 0.63) + c.phase * 1.7))
  return a, out
end

--- The beam a beacon `b` throws, turning (0..1 how bright it faces you).
local function flash(b)
  local turn = (clock * 1.4 + (b.x * 0.37 + b.y * 0.11) % 1) % 1
  return math.max(0, math.cos(turn * 2 * math.pi)) ^ 6, turn * 2 * math.pi
end

--- On the ground: each crane's shadow, the jib's and its load's.
function Works.drawBelowCars(map)
  love.graphics.setColor(0, 0, 0, 0.22)
  for _, c in ipairs(map.cranes or {}) do
    local a, out = pose(c)
    local ca, sa = math.cos(a), math.sin(a)
    local sx, sy = c.x + LIFT, c.y + LIFT -- the light comes from up and to the left
    love.graphics.setLineWidth(14)
    love.graphics.line(sx - ca * c.jib * 0.3, sy - sa * c.jib * 0.3, sx + ca * c.jib, sy + sa * c.jib)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("fill", sx + ca * out - 22, sy + sa * out - 14, 44, 28)
  end
  love.graphics.setColor(1, 1, 1)
end

--- A lattice of the jib from (x0, y0) to (x1, y1), `w` px wide.
local function truss(x0, y0, x1, y1, w)
  local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  love.graphics.push()
  love.graphics.translate(x0, y0)
  love.graphics.rotate(math.atan2(y1 - y0, x1 - x0))
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", -2, -w / 2 - 2, len + 4, w + 4)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", 0, -w / 2, len, w)
  love.graphics.setColor(C.ink)
  love.graphics.setLineWidth(1.5)
  for k = 0, len - w, w do -- the zig-zag bracing
    love.graphics.line(k, -w / 2, k + w, w / 2)
  end
  love.graphics.setLineWidth(1)
  love.graphics.pop()
end

local function drawCrane(c)
  local a, out = pose(c)
  local ca, sa = math.cos(a), math.sin(a)
  local x, y = c.x, c.y - LIFT
  -- The load first, under the jib: a bundle of girders on its cable, swaying.
  local sway = math.sin(clock * 1.7 + c.phase) * 6
  local lx, ly = x + ca * out - sa * sway, y + sa * out + ca * sway + LIFT * 0.6
  love.graphics.setColor(C.ink)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(x + ca * out, y + sa * out, lx, ly)
  love.graphics.setLineWidth(1)
  love.graphics.push()
  love.graphics.translate(lx, ly)
  love.graphics.rotate(a + math.pi / 2)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", -22, -12, 44, 24)
  love.graphics.setColor(C.rust)
  for k = -1, 1 do
    love.graphics.rectangle("fill", -20, k * 7 - 3, 40, 6)
  end
  love.graphics.pop()
  -- The counter-jib behind, its weight, the jib out front, the trolley on it.
  truss(x, y, x - ca * c.jib * 0.3, y - sa * c.jib * 0.3, 14)
  love.graphics.setColor(C.ink)
  love.graphics.push()
  love.graphics.translate(x - ca * c.jib * 0.28, y - sa * c.jib * 0.28)
  love.graphics.rotate(a)
  love.graphics.rectangle("fill", -14, -14, 24, 28)
  love.graphics.setColor(C.gunmetalLight)
  love.graphics.rectangle("fill", -12, -12, 20, 24)
  love.graphics.pop()
  truss(x, y, x + ca * c.jib, y + sa * c.jib, 14)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x + ca * out - 9, y + sa * out - 9, 18, 18)
  love.graphics.setColor(C.gunmetal)
  love.graphics.rectangle("fill", x + ca * out - 7, y + sa * out - 7, 14, 14)
  -- The cab at the top of the mast, and the light at the jib's tip.
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 14, y - 14, 28, 28)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", x - 12, y - 12, 24, 24)
  love.graphics.setColor(0.26, 0.36, 0.48)
  love.graphics.rectangle("fill", x - 6, y - 10, 14, 10)
  local on = math.floor(clock * 1.5 + c.phase) % 2 == 0
  love.graphics.setColor(on and 1 or 0.35, 0.1, 0.08)
  love.graphics.circle("fill", x + ca * c.jib, y + sa * c.jib, 5, 10)
end

local function drawBeacon(b)
  local col = BEACON[b.color] or BEACON.amber
  local f, turn = flash(b)
  love.graphics.setColor(C.ink)
  love.graphics.circle("fill", b.x, b.y, 10, 12)
  love.graphics.setColor(col[1] * (0.45 + 0.55 * f), col[2] * (0.45 + 0.55 * f), col[3] * (0.45 + 0.55 * f))
  love.graphics.circle("fill", b.x, b.y, 7, 12)
  love.graphics.setBlendMode("add") -- the beam sweeping round
  love.graphics.setColor(col[1], col[2], col[3], 0.18 + 0.25 * f)
  love.graphics.arc("fill", b.x, b.y, 110, turn - 0.3, turn + 0.3, 10)
  love.graphics.setBlendMode("alpha")
end

--- Overhead: the beacons, then the cranes over everything.
function Works.drawAboveCars(map)
  for _, b in ipairs(map.beacons or {}) do
    drawBeacon(b)
  end
  for _, c in ipairs(map.cranes or {}) do
    drawCrane(c)
  end
  love.graphics.setColor(1, 1, 1)
end

--- At dusk (the night feature): the beacons and the cranes' tip lights glow.
function Works.drawNightLights(map, glow)
  for _, b in ipairs(map.beacons or {}) do
    local f = flash(b)
    glow(b.x, b.y, 90 + 90 * f, BEACON[b.color] or BEACON.amber, 0.35 + 0.6 * f)
  end
  for _, c in ipairs(map.cranes or {}) do
    local a = pose(c)
    if math.floor(clock * 1.5 + c.phase) % 2 == 0 then
      glow(c.x + math.cos(a) * c.jib, c.y - LIFT + math.sin(a) * c.jib, 60, BEACON.red, 0.8)
    end
    glow(c.x, c.y - LIFT, 80, { 1, 0.9, 0.7 }, 0.4) -- the cab's lamp
  end
end

return Works
