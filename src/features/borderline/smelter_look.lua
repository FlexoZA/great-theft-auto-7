-- How the Smelter looks (docs/borderline.md, "The bosses"), seen from above
-- at world size, facing +x in its own frame, in the bosses' outlined style
-- (boss_paint.lua): a squat plasma furnace on four jointed legs. A round
-- riveted shell with Hyperbole's yellow band round it, the charging hatch
-- on top glowing through its grille, two stacks at the back letting off
-- smoke, purple coils down both flanks, and at the front its belly door
-- over a spout: shut, steel; open (a gush lined up or pouring, or
-- venting), the molten Bragium inside glaring out.
--
--   Look.draw(h, clock)
--       h: { dx, dy, facing, stride, charge, flash }
--       `charge` 0..1 its coils lit for a shot, `flash` 0..1 just hit;
--       the belly door is `Look.tell`'s (smelter.lua keeps it): `open`
--       0..1, `vent` true while it vents
--   Look.drawWreck(w, clock)   where it went out: w { x, y, angle }

local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")

local Look = {}

Look.SCALE = 1.6 -- drawn this much over its own frame's px (its RADIUS: sml_brain.lua)
Look.tell = { open = 0, vent = false } -- its belly door, on this screen (smelter.lua)

local C = Hauler.C
local color, plate, disc, glow = Paint.color, Paint.plate, Paint.disc, Paint.glow

--- A leg from its hip at (hx, hy) out along `angle`: thigh, knee, shin, foot.
local function leg(hx, hy, angle, lift)
  local kx, ky = hx + math.cos(angle) * 18, hy + math.sin(angle) * 18
  local out = angle + (hy > 0 and 0.5 or -0.5)
  local fx, fy = kx + math.cos(out) * (14 - lift * 4), ky + math.sin(out) * (14 - lift * 4)
  for _, w in ipairs({ { 7, C.ink }, { 4.5, C.gunmetalLight } }) do
    color(w[2])
    love.graphics.setLineWidth(w[1])
    love.graphics.line(hx, hy, kx, ky, fx, fy)
  end
  love.graphics.setLineWidth(1)
  disc(kx, ky, 3.5, C.yellow)
  disc(fx, fy, 4.5 - lift, C.gunmetal)
end

local function legs(stride)
  local k = math.sin(stride * 0.07)
  leg(12, -18, -1.0 + k * 0.25, math.max(0, k))
  leg(12, 18, 1.0 - k * 0.25, math.max(0, -k))
  leg(-12, -18, -2.1 - k * 0.25, math.max(0, -k))
  leg(-12, 18, 2.1 + k * 0.25, math.max(0, k))
end

--- Its coils down a flank (`side` -1 or 1), lit by `charge`.
local function coils(side, charge, clock)
  for i = 0, 3 do
    local x = -14 + i * 7
    plate(x - 2, side * 26 - 2, 4, 4, C.gunmetal, 1)
    color(C.plasma, 0.5 + 0.5 * charge)
    love.graphics.rectangle("fill", x - 1.2, side * 26 - 1.2, 2.4, 2.4)
    if charge > 0 then
      glow(C.plasma, 0.35 * charge * (0.7 + 0.3 * math.sin(clock * 20 + i)), x, side * 26, 6)
    end
  end
end

--- The two stacks at its back, smoking.
local function stacks(clock)
  for i, y in ipairs({ -9, 9 }) do
    disc(-24, y, 5.5, C.black)
    color(C.ink)
    love.graphics.circle("fill", -24, y, 3.2, 12)
    local t = (clock * 0.8 + i * 0.5) % 1
    love.graphics.setColor(0.30, 0.28, 0.34, 0.45 * (1 - t))
    love.graphics.circle("fill", -26 - t * 16, y + t * 3, 4 + t * 9, 14)
  end
end

--- The shell: riveted steel, the yellow band, the charging hatch on top.
local function shell(heat, clock)
  disc(0, 0, 28, C.gunmetal)
  color(C.yellow)
  love.graphics.setLineWidth(5)
  love.graphics.circle("line", 0, 0, 23, 28)
  love.graphics.setLineWidth(1)
  color(C.ink)
  love.graphics.setLineWidth(1.2)
  love.graphics.circle("line", 0, 0, 25.5, 28)
  love.graphics.circle("line", 0, 0, 20.5, 28)
  love.graphics.setLineWidth(1)
  for i = 0, 11 do -- rivets round the band
    local a = i * math.pi / 6
    color(C.yellowDark)
    love.graphics.circle("fill", math.cos(a) * 23, math.sin(a) * 23, 1, 6)
  end
  disc(-2, 0, 13, C.gunmetalLight) -- the charging hatch
  local k = 0.55 + 0.25 * math.sin(clock * 3) + 0.2 * heat
  color(C.plasma, k)
  love.graphics.circle("fill", -2, 0, 9, 18)
  color(C.ink) -- its grille
  for g = -6, 6, 4 do
    love.graphics.rectangle("fill", -2 + g - 0.7, -9, 1.4, 18)
  end
  glow(C.plasma, 0.2 * k, -2, 0, 18)
end

--- The belly door at its front over the spout: `open` 0..1.
local function belly(open, vent, clock)
  plate(22, -8, 10, 16, C.steel, 2) -- the spout's housing
  local inside = 0.6 + 0.4 * math.sin(clock * (vent and 14 or 6))
  if open > 0 then
    color(C.plasmaHot, open * inside)
    love.graphics.rectangle("fill", 23.5, -6.5, 7, 13, 1.5)
    glow(C.plasma, (vent and 0.5 or 0.35) * open, 30, 0, 12 + 8 * open)
  end
  -- The door's two leaves, sliding apart as it opens.
  local gap = 6.5 * open
  plate(23.5, -6.5 - gap, 7, 6.5, C.gunmetalLight, 1)
  plate(23.5, gap, 7, 6.5, C.gunmetalLight, 1)
  disc(33, 0, 3.5, C.black) -- the spout
end

function Look.draw(h, clock)
  local T = Look.tell
  local charge, flash = h.charge or 0, h.flash or 0
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  love.graphics.scale(Look.SCALE)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 5, 7, 40, 38, 24)
  love.graphics.rotate(h.facing or 0)
  legs(h.stride or 0)
  stacks(clock)
  shell(math.max(charge, T.open), clock)
  coils(-1, charge, clock)
  coils(1, charge, clock)
  belly(T.open, T.vent, clock)
  if T.vent then -- venting: steam off it, the whole of it glowing
    local k = 0.5 + 0.5 * math.sin(clock * 9)
    glow(C.plasma, 0.12 + 0.08 * k, 0, 0, 32)
    for i = 0, 3 do -- steam puffing off its back
      local t = (clock * 1.3 + i * 0.25) % 1
      local a = math.pi + (i - 1.5) * 0.7
      love.graphics.setColor(0.85, 0.8, 0.95, 0.35 * (1 - t))
      love.graphics.circle("fill", math.cos(a) * (24 + t * 22), math.sin(a) * (24 + t * 22), 4 + t * 7, 12)
    end
  end
  if flash > 0 then -- the hit: everything goes white for a moment
    love.graphics.setColor(1, 1, 1, 0.45 * flash)
    love.graphics.circle("fill", 0, 0, 29, 24)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where it went out: slumped on its folded legs, its shell cracked and
--- dark, what was in its belly spilled in front of it, cooling.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.scale(Look.SCALE)
  love.graphics.rotate(w.angle)
  love.graphics.setColor(0.16, 0.08, 0.22, 0.85) -- the spill, crusted over
  love.graphics.ellipse("fill", 38, 2, 22, 16, 20)
  color(C.plasma, 0.25 + 0.1 * math.sin(clock * 2))
  love.graphics.ellipse("fill", 38, 2, 10, 7, 16)
  for _, l in ipairs({ { 8, -20, -1.4 }, { 8, 20, 1.4 }, { -10, -20, -1.9 }, { -10, 20, 1.9 } }) do
    leg(l[1], l[2], l[3], 0.8)
  end
  stacks(0)
  disc(0, 0, 28, C.gunmetal)
  color(C.yellowDark)
  love.graphics.setLineWidth(5)
  love.graphics.circle("line", 0, 0, 23, 28)
  love.graphics.setLineWidth(1)
  disc(-2, 0, 13, C.black) -- the hatch, gone out
  color(C.ink) -- cracks across the shell
  love.graphics.setLineWidth(1.5)
  love.graphics.line(-20, -12, -8, -4, 2, -10, 14, -6)
  love.graphics.line(-6, 16, 4, 6, 18, 10)
  love.graphics.setLineWidth(1)
  plate(22, -8, 10, 16, C.gunmetalLight, 2)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
