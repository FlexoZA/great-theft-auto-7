-- How BNK-9 looks (docs/borderline.md, "The bosses"), seen from above at
-- world size, facing +x in its own frame, in the bosses' outlined style
-- (boss_paint.lua): the bunker's flying core, a slab of dark armour plate,
-- seamed and riveted, hazard stripes along its back edge, Hyperbole's H in
-- its hexagon on top, four engines glowing along its flanks and its back,
-- a socket on each corner where a turret rides, and at its front the huge
-- red eye, which is all it looks with. It hovers: its shadow lies on the
-- deck below and behind it. Charging its laser, the eye glares; past half
-- its health (`Look.fury`, kept by bnk9.lua) it flickers and smokes.
--
--   Look.draw(h, clock)        h: { dx, dy, facing, charge, flash }
--   Look.drawWreck(w, clock)   where it crashed: w { x, y, angle }
--   Look.turret                a corner turret's look (BNT): .draw(h, clock) { dx, dy, facing, charge, flash },
--                              .drawWreck(w, clock), fallen to the deck
--   Look.SHADOW                how far below and behind it its shadow lies, px

local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")

local Look = {}

Look.fury = false
Look.SHADOW = { 34, 56 }

local C = Hauler.C
local color, plate, disc, glow = Paint.color, Paint.plate, Paint.disc, Paint.glow
local ARMOUR = { 0.17, 0.18, 0.20 }
local ARMOUR_LIGHT = { 0.27, 0.29, 0.32 }
local THRUST = { 1.00, 0.62, 0.22 }

-- Its engines: (x, y) in its frame, and which way each nacelle runs.
local ENGINES = { { -6, -60, 0 }, { -6, 60, 0 }, { -62, -24, math.pi / 2 }, { -62, 24, math.pi / 2 } }
local SOCKETS = { { 40, -44 }, { 40, 44 }, { -44, -44 }, { -44, 44 } } -- (bnk_brain.lua's CORNERS)

local function engine(x, y, along, clock, k)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(along)
  plate(-14, -9, 28, 18, C.gunmetal, 8)
  color(C.ink)
  love.graphics.ellipse("fill", 0, 0, 8, 6, 16)
  local f = 0.7 + 0.3 * math.sin(clock * 30 + x)
  color(THRUST, (0.5 + 0.5 * f) * k)
  love.graphics.ellipse("fill", 0, 0, 6, 4.5, 16)
  glow(THRUST, 0.25 * f * k, 0, 0, 16)
  love.graphics.pop()
end

--- The slab: seamed armour, rivets, the hazard stripe along its back edge,
--- the H on top, a socket on each corner.
local function hull()
  plate(-56, -52, 112, 104, ARMOUR, 14)
  color(ARMOUR_LIGHT) -- its plates, each a shade lighter at the top
  for _, p in ipairs({ { -50, -46, 46, 44 }, { 0, -46, 46, 44 }, { -50, 2, 46, 44 }, { 0, 2, 46, 44 } }) do
    love.graphics.rectangle("fill", p[1], p[2], p[3], 5, 2)
  end
  color(C.ink)
  love.graphics.setLineWidth(2)
  love.graphics.line(-52, -1, 52, -1)
  love.graphics.line(-2, -48, -2, 48)
  love.graphics.setLineWidth(1)
  for _, rx in ipairs({ -48, -8, 4, 44 }) do -- rivets along the seams
    for _, ry in ipairs({ -44, -6, 6, 44 }) do
      love.graphics.circle("fill", rx, ry, 1.4, 6)
    end
  end
  for i = 0, 8 do -- the hazard stripe across its back
    color(i % 2 == 0 and C.yellow or C.ink)
    love.graphics.rectangle("fill", -55, -45 + i * 10, 6, 10)
  end
  -- Hyperbole's H in its hexagon.
  color(C.ink)
  local hex = {}
  for k = 0, 5 do
    local a = k * math.pi / 3
    hex[#hex + 1], hex[#hex + 2] = -14 + math.cos(a) * 15, math.sin(a) * 15
  end
  love.graphics.polygon("fill", hex)
  color(C.yellow)
  love.graphics.rectangle("fill", -20, -7, 3.5, 14)
  love.graphics.rectangle("fill", -11.5, -7, 3.5, 14)
  love.graphics.rectangle("fill", -18, -1.5, 8, 3)
  for _, s in ipairs(SOCKETS) do
    disc(s[1], s[2], 15, C.gunmetalLight)
    color(C.ink)
    love.graphics.circle("fill", s[1], s[2], 10, 16)
  end
end

--- The eye: a yellow ring round a dark socket, the red eye in it; glaring
--- while it charges, flickering once it's furious.
local function eye(heat, clock)
  local x = 44
  disc(x, 0, 24, C.yellow)
  disc(x, 0, 20, C.black)
  local k = 0.85 + 0.15 * math.sin(clock * 3)
  if Look.fury and math.sin(clock * 23) > 0.6 then
    k = 0.4
  end
  color(C.eye, k)
  love.graphics.circle("fill", x, 0, 16, 28)
  color(C.eyeHot, 0.5 + 0.5 * heat)
  love.graphics.circle("fill", x + 3, -3, 5 + 4 * heat, 16)
  glow(C.eye, 0.2 + 0.5 * heat, x, 0, 26 + 20 * heat)
end

function Look.draw(h, clock)
  local charge, flash = h.charge or 0, h.flash or 0
  love.graphics.setColor(0, 0, 0, 0.3) -- its shadow on the deck, below and behind it
  love.graphics.ellipse("fill", h.dx + Look.SHADOW[1], h.dy + Look.SHADOW[2], 70, 62, 28)
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  love.graphics.rotate(h.facing or 0)
  for _, e in ipairs(ENGINES) do
    engine(e[1], e[2], e[3], clock, 1)
  end
  hull()
  eye(math.max(charge, flash), clock)
  if Look.fury then -- smoke off its back
    for i = 0, 2 do
      local t = (clock * 0.9 + i / 3) % 1
      love.graphics.setColor(0.25, 0.25, 0.27, 0.45 * (1 - t))
      love.graphics.circle("fill", -40 - t * 30, -20 + i * 20 + t * 6, 6 + t * 12, 14)
    end
  end
  if flash > 0 then -- the hit: everything goes white for a moment
    love.graphics.setColor(1, 1, 1, 0.4 * flash)
    love.graphics.rectangle("fill", -56, -52, 112, 104, 14)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where it crashed: down on the deck, tilted, its armour split, its
--- engines dead, its eye dark, burning.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle + 0.25)
  love.graphics.setColor(0, 0, 0, 0.45) -- scorched deck round it
  love.graphics.ellipse("fill", 0, 0, 90, 80, 28)
  for _, e in ipairs(ENGINES) do
    engine(e[1], e[2], e[3], clock, 0)
  end
  hull()
  disc(44, 0, 24, C.yellowDark)
  disc(44, 0, 20, C.black)
  color(C.ink) -- the split across it
  love.graphics.setLineWidth(3)
  love.graphics.line(-30, -52, -10, -14, -22, 10, 4, 52)
  love.graphics.setLineWidth(1)
  for i = 0, 2 do -- fire and smoke out of the split
    local t = (clock * 1.1 + i / 3) % 1
    love.graphics.setColor(1, 0.55, 0.15, 0.6 * (1 - t))
    love.graphics.circle("fill", -14 + i * 6, -10 + i * 8 - t * 20, 5 * (1 - t) + 2, 10)
    love.graphics.setColor(0.25, 0.25, 0.27, 0.4 * (1 - t))
    love.graphics.circle("fill", -14 + i * 6 - t * 16, -18 + i * 8 - t * 40, 6 + t * 14, 14)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

-- Its corner turrets ------------------------------------------------------------

Look.turret = {}

--- A turret: a ring with a yellow rim, twin barrels on it, aiming.
function Look.turret.draw(h, clock)
  local charge, flash = h.charge or 0, h.flash or 0
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  love.graphics.rotate(h.facing or 0)
  disc(0, 0, 13, C.yellow)
  disc(0, 0, 10, C.gunmetal)
  for _, y in ipairs({ -4, 4 }) do
    plate(2, y - 2, 20, 4, C.gunmetalLight, 1)
  end
  disc(-2, 0, 5, C.black)
  color(C.eye, 0.7 + 0.3 * math.sin(clock * 6))
  love.graphics.circle("fill", -2, 0, 2.2, 10)
  if charge > 0 then
    glow(THRUST, 0.4 * charge, 22, 0, 8)
  end
  if flash > 0 then
    love.graphics.setColor(1, 1, 1, 0.5 * flash)
    love.graphics.circle("fill", 0, 0, 13, 16)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- A turret shot off and fallen to the deck: its ring on its side, a
--- barrel bent.
function Look.turret.drawWreck(w)
  love.graphics.push()
  love.graphics.translate(w.x + Look.SHADOW[1] * 0.6, w.y + Look.SHADOW[2] * 0.6) -- it fell from up there
  love.graphics.rotate(w.angle + 1.1)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 2, 3, 16, 12, 16)
  disc(0, 0, 11, C.yellowDark)
  disc(0, 0, 8, C.gunmetal)
  plate(2, -6, 16, 4, C.gunmetalLight, 1)
  love.graphics.push()
  love.graphics.rotate(0.6)
  plate(2, 2, 12, 4, C.gunmetalLight, 1)
  love.graphics.pop()
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
