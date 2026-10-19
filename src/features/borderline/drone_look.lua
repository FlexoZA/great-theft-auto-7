-- How Hyperbole's small machines look (docs/borderline.md, "The army"),
-- from above at world size: the drones that keep the haulers going, and the
-- sentry that pops up out of the floor.
--
--   FIX  a yellow disc on four rotors, a green cross light; its beam heals
--   SHD  the same disc with a blue light; its beam puts a shield on a hauler
--
--   Look.drawDrone(d, clock)   d: { dx, dy, facing, code, beamX, beamY, flash }
--       (`beamX`, `beamY` the hauler it is tending, world px, or nil)
--   Look.drawBubble(x, y, r, clock, strength)   a shield drone's bubble round a hauler
--   Look.drawSentry(s, clock)  s: { dx, dy, aim, rise, charge, flash }: `rise`
--       0 flush in the floor .. 1 up and turning, `charge` 0..1 about to fire
--   Look.drawDebris(x, y, seed)  what's left of either

local Hauler = require("src.features.borderline.hauler_look")

local Look = {}

local C = Hauler.C
local LIGHT = {
  FIX = { 0.35, 1.00, 0.45 },
  SHD = { 0.35, 0.75, 1.00 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function disc(x, y, r, fill)
  color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.2, 18)
  color(fill)
  love.graphics.circle("fill", x, y, r, 18)
end

function Look.drawDrone(d, clock)
  local light = LIGHT[d.code] or LIGHT.FIX
  -- The beam first, under the drone: a wavering line to whoever it tends.
  if d.beamX then
    love.graphics.setBlendMode("add")
    for i = 0, 2 do
      love.graphics.setColor(light[1], light[2], light[3], 0.25 + 0.15 * math.sin(clock * 12 + i))
      love.graphics.setLineWidth(5 - i * 1.5)
      love.graphics.line(d.dx, d.dy, d.beamX, d.beamY)
    end
    love.graphics.setLineWidth(1)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.setColor(0, 0, 0, 0.2) -- it flies: the shadow lies well off it
  love.graphics.circle("fill", d.dx + 8, d.dy + 22, 9, 14)
  love.graphics.push()
  love.graphics.translate(d.dx, d.dy)
  love.graphics.rotate(d.facing or 0)
  -- Four rotors on struts, a blur where the blades turn.
  for i = 0, 3 do
    local a = math.pi / 4 + i * math.pi / 2
    local rx, ry = math.cos(a) * 9, math.sin(a) * 9
    color(C.ink)
    love.graphics.setLineWidth(2.4)
    love.graphics.line(0, 0, rx, ry)
    love.graphics.setLineWidth(1)
    color(C.gunmetalLight, 0.45)
    love.graphics.circle("fill", rx, ry, 4.5, 12)
    color(C.ink, 0.6)
    local spin = clock * 50 + i
    love.graphics.line(rx - math.cos(spin) * 4.5, ry - math.sin(spin) * 4.5, rx + math.cos(spin) * 4.5,
      ry + math.sin(spin) * 4.5)
  end
  disc(0, 0, 6.5, C.yellow)
  disc(0, 0, 3.6, C.gunmetal)
  local pulse = 0.7 + 0.3 * math.sin(clock * 5)
  color(light, pulse)
  if d.code == "SHD" then
    love.graphics.circle("fill", 0, 0, 2.4, 10)
  else -- a cross
    love.graphics.rectangle("fill", -2.6, -0.9, 5.2, 1.8)
    love.graphics.rectangle("fill", -0.9, -2.6, 1.8, 5.2)
  end
  color(C.eye) -- its little eye, looking ahead
  love.graphics.circle("fill", 5.6, 0, 1.3, 8)
  if (d.flash or 0) > 0 then
    love.graphics.setColor(1, 1, 1, 0.6 * d.flash)
    love.graphics.circle("fill", 0, 0, 8, 14)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- A shield drone's bubble round a hauler at (x, y): blue, hexed, flickering
--- as it weakens (`strength` 0..1).
function Look.drawBubble(x, y, r, clock, strength)
  local light = LIGHT.SHD
  local a = 0.18 + 0.2 * strength
  if strength < 0.3 and math.sin(clock * 25) > 0.4 then
    a = a * 0.3
  end
  love.graphics.setColor(light[1], light[2], light[3], a)
  love.graphics.circle("fill", x, y, r, 28)
  love.graphics.setColor(light[1], light[2], light[3], a * 2.5)
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", x, y, r, 6) -- a hexagon inside the round, the bubble's facets
  love.graphics.circle("line", x, y, r, 28)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- The sentry: a hatch in the floor with a hazard rim; risen, a squat
--- turret with twin barrels and a red eye between them.
function Look.drawSentry(s, clock)
  local rise = s.rise or 1
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy)
  -- The hatch, always there.
  for i = 0, 11 do
    color(i % 2 == 0 and C.yellow or C.ink)
    love.graphics.arc("fill", 0, 0, 15, i * math.pi / 6, (i + 1) * math.pi / 6, 3)
  end
  disc(0, 0, 11.5, C.gunmetal)
  if rise > 0 then
    love.graphics.setColor(0, 0, 0, 0.3 * rise)
    love.graphics.circle("fill", 3 * rise, 4 * rise, 11, 16)
    love.graphics.rotate(s.aim or 0)
    love.graphics.scale(0.6 + 0.4 * rise)
    disc(0, 0, 9, C.yellow)
    for _, side in ipairs({ -1, 1 }) do
      color(C.ink)
      love.graphics.rectangle("fill", 2, side * 4 - 2, 15 * rise + 1, 4)
      color(C.gunmetalLight)
      love.graphics.rectangle("fill", 3, side * 4 - 1.2, 15 * rise, 2.4)
    end
    disc(4, 0, 3, C.gunmetal)
    local heat = s.charge or 0
    color(C.eye, 0.7 + 0.3 * math.sin(clock * 6) + heat)
    love.graphics.circle("fill", 4.5, 0, 2.2, 10)
    if (s.flash or 0) > 0 then
      love.graphics.setColor(1, 1, 1, 0.6 * s.flash)
      love.graphics.circle("fill", 0, 0, 10, 14)
    end
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Bits of a drone or sentry on the ground.
function Look.drawDebris(x, y, seed)
  for i = 0, 4 do
    local a = seed + i * 1.3
    local r = 4 + (i * 3.7 + seed) % 7
    color(i % 2 == 0 and C.yellow or C.gunmetal)
    love.graphics.rectangle("fill", x + math.cos(a) * r - 1.5, y + math.sin(a) * r - 1.5, 3, 3)
  end
  love.graphics.setColor(1, 1, 1)
end

return Look
