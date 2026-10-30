-- How the Knuckle Scrapper looks (docs/borderline.md, "The bosses"), seen
-- from above at world size, facing +x in its own frame, in the haulers'
-- outlined style (hauler_look.lua's colours): a junk hauler that built
-- itself huge out of Max's wrecked train. A heap of rusted scrap with a
-- torn-off carriage panel in Hyperbole yellow on its back (two windows and
-- a hazard stripe), the engine's smokestack puffing out of it, the engine's
-- headlight for an eye, and two long arms of girder ending in fists that
-- were bogies (a pair of wheels each, an axle through them). Scrap plates
-- stud the heap: hurt, it sheds them (`plates`), down to the bare frame.
--
--   Look.draw(h, clock)
--       h: { dx, dy, facing, stride, plates, draw, lift, swing, flash }
--       `plates` 0..1 of them left (its health), `flash` 0..1 just hit;
--       `draw` 0..1 a fist drawn back for a swing, `lift` 0..1 a lump of
--       scrap coming up over its head, `swing` 0..1 a swing going round (1
--       just thrown): `Look.tell`'s when not given (scrapper.lua keeps it)
--   Look.plateCount(f)                how many plates it shows at `f` 0..1 of its health
--   Look.drawLump(x, y, spin, size)   a lump of scrap in the air
--   Look.drawWreck(w, clock)          where it fell apart: w { x, y, angle }
--   Look.drawLoad(x, y, clock)        the scrap a junk hauler carries to it

local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")

local Look = {}

Look.tell = { draw = 0, lift = 0, swing = 0 } -- the move it is making, on this screen (scrapper.lua)

local C = Hauler.C
local HEADLIGHT = { 1.00, 0.94, 0.70 }
local GLASS = { 0.55, 0.70, 0.80 }

Look.SCALE = 1.45 -- drawn this much over its own frame's px: it is huge (its RADIUS: knk_brain.lua)

-- The plates studding the heap's rim: x, y, w, h, angle, in its frame.
-- The first ones go first.
local PLATES = {
  { 26, 10, 12, 8, 1.92 }, { -26, -10, 11, 9, 5.06 }, { -10, 26, 12, 8, 3.49 }, { 10, -26, 11, 9, 6.63 },
  { 12, 25, 12, 8, 2.71 }, { -12, -25, 11, 9, 5.85 }, { -25, 12, 12, 8, 4.28 }, { 25, -12, 11, 9, 7.42 },
}

local color, plate, disc, glow = Paint.color, Paint.plate, Paint.disc, Paint.glow

--- A plate turned by `a` round its middle.
local function tilted(x, y, w, h, a, fill)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  plate(-w / 2, -h / 2, w, h, fill, 1.5)
  color(C.rustDark) -- a rivet in each corner
  for _, k in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    love.graphics.circle("fill", k[1] * (w / 2 - 2), k[2] * (h / 2 - 2), 0.9, 6)
  end
  love.graphics.pop()
end

--- Its feet: a bogie under each side, rolling as it goes.
local function bogies(stride)
  local step = math.sin(stride * 0.06) * 6
  for _, side in ipairs({ -1, 1 }) do
    local y = side * 22
    plate(-18 + step * side, y - 5, 30, 10, C.gunmetal, 2)
    for _, wx in ipairs({ -12, 6 }) do
      disc(wx + step * side, y, 4.5, C.black)
    end
  end
end

--- A fist: a bogie torn off the train, its two wheels for knuckles.
local function fist(x, y)
  plate(x - 9, y - 9, 18, 18, C.gunmetal, 3)
  disc(x + 4, y - 5, 5, C.steel)
  disc(x + 4, y + 5, 5, C.steel)
  color(C.ink)
  love.graphics.rectangle("fill", x + 3, y - 7, 2, 14) -- the axle
end

--- An arm of girder from its shoulder at (sx, sy) out to its fist,
--- `reach` px along `angle` (its frame).
local function arm(sx, sy, angle, reach)
  local fx, fy = sx + math.cos(angle) * reach, sy + math.sin(angle) * reach
  color(C.ink)
  love.graphics.setLineWidth(11)
  love.graphics.line(sx, sy, fx, fy)
  color(C.rust)
  love.graphics.setLineWidth(8)
  love.graphics.line(sx, sy, fx, fy)
  color(C.rustDark) -- the girder's holes
  love.graphics.setLineWidth(1)
  for k = 0.25, 0.8, 0.18 do
    love.graphics.circle("fill", sx + (fx - sx) * k, sy + (fy - sy) * k, 1.6, 6)
  end
  disc(sx, sy, 7, C.gunmetalLight) -- the shoulder
  fist(fx, fy)
end

function Look.plateCount(f)
  return math.max(0, math.ceil(#PLATES * math.min(1, f) - 0.001))
end

--- The heap itself: rust and scrap, the carriage panel on its back, what
--- plates it still has, its smokestack and its eye (`out` once it has
--- fallen apart).
local function heap(plates, heat, clock, out)
  color(C.ink)
  love.graphics.polygon("fill", -34, -16, -22, -32, 2, -34, 22, -24, 32, -4, 28, 18, 10, 32, -14, 32, -32, 18)
  color(C.rustDark)
  love.graphics.polygon("fill", -31, -15, -20, -29, 2, -31, 20, -22, 29, -4, 25, 16, 9, 29, -13, 29, -29, 16)
  color(C.rust)
  love.graphics.polygon("fill", -24, -12, -14, -24, 4, -25, 18, -16, 22, 2, 16, 18, 0, 24, -18, 20, -25, 6)
  -- The carriage panel on its back: Hyperbole yellow, two windows, a hazard stripe.
  love.graphics.push()
  love.graphics.rotate(-0.15)
  plate(-24, -12, 20, 26, C.yellow, 2)
  plate(-21, -9, 6, 7, GLASS, 1)
  plate(-21, 1, 6, 7, GLASS, 1)
  for i = 0, 5 do
    color(i % 2 == 0 and C.ink or C.yellow)
    love.graphics.rectangle("fill", -12, -12 + i * 4.3, 4, 4.3)
  end
  love.graphics.pop()
  local n = Look.plateCount(plates)
  for i = #PLATES - n + 1, #PLATES do -- the first in the list go first
    local p = PLATES[i]
    tilted(p[1], p[2], p[3], p[4], p[5], i % 3 == 0 and C.steel or C.gunmetalLight)
  end
  -- The smokestack, puffing.
  disc(-6, 12, 6, C.black)
  color(C.ink)
  love.graphics.circle("fill", -6, 12, 3.5, 12)
  local t = (clock * 0.9) % 1
  love.graphics.setColor(0.32, 0.32, 0.34, 0.5 * (1 - t))
  love.graphics.circle("fill", -6 - t * 14, 12 + t * 4, 4 + t * 9, 14)
  -- The eye: the engine's headlight, white-hot, going red as it winds up.
  disc(14, 0, 8, C.steel)
  if out then
    love.graphics.setColor(0.08, 0.08, 0.09)
    love.graphics.circle("fill", 14, 0, 5.5, 18)
    return
  end
  local eye = heat > 0 and C.eye or HEADLIGHT
  color(eye, 0.85 + 0.15 * math.sin(clock * 3))
  love.graphics.circle("fill", 14, 0, 5.5, 18)
  color(heat > 0 and C.eyeHot or C.white)
  love.graphics.circle("fill", 15.5, -1, 2 + heat, 10)
  glow(eye, 0.25 + 0.35 * heat, 14, 0, 14 + 6 * heat)
end

function Look.draw(h, clock)
  local T = Look.tell
  local draw, lift, swing, flash = h.draw or T.draw, h.lift or T.lift, h.swing or T.swing, h.flash or 0
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  love.graphics.scale(Look.SCALE)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 6, 8, 44, 40, 24)
  love.graphics.rotate(h.facing or 0)
  bogies(h.stride or 0)
  -- The arms reach forward; the right one draws back for a swing, then
  -- sweeps round across the front.
  local right = swing > 0 and (-0.9 + 1.45 * (1 - swing)) or (0.55 + draw * 1.5) -- swung: across, coming back
  local left = -0.55 - lift * 1.6
  arm(4, -24, left, 44 - lift * 16)
  arm(4, 24, right, 46)
  heap(h.plates or 1, math.max(draw, lift, flash), clock)
  if lift > 0 then -- the lump of scrap coming up over its head
    Look.drawLump(-4 + lift * 4, -18 + lift * 18, clock * 2, 0.7 + 0.5 * lift)
  end
  if flash > 0 then -- the hit: everything goes white for a moment
    love.graphics.setColor(1, 1, 1, 0.45 * flash)
    love.graphics.polygon("fill", -34, -16, -22, -32, 2, -34, 22, -24, 32, -4, 28, 18, 10, 32, -14, 32, -32, 18)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- A lump of scrap: a crumpled plate, a girder end and a wheel, tumbling
--- (`spin` rad), `size` times its own size.
function Look.drawLump(x, y, spin, size)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(spin)
  love.graphics.scale(size or 1)
  color(C.ink)
  love.graphics.polygon("fill", -14, -9, 2, -15, 15, -6, 13, 10, -2, 14, -15, 6)
  color(C.rust)
  love.graphics.polygon("fill", -12, -7, 2, -12.5, 12.5, -5, 11, 8, -2, 11.5, -12.5, 5)
  color(C.rustDark) -- a dent across it
  love.graphics.polygon("fill", -8, 2, 6, -4, 8, 0, -6, 6)
  tilted(-4, -3, 12, 7, 0.5, C.steel)
  tilted(6, 4, 8, 6, -0.7, C.yellow) -- a scrap of the carriage's paint
  disc(-5, 6, 3.2, C.black)
  love.graphics.pop()
end

--- What a junk hauler feeding it carries over its head: a few plates and
--- a wheel, glinting.
function Look.drawLoad(x, y, clock)
  local bob = math.sin(clock * 9 + x * 0.05) * 1.5
  love.graphics.push()
  love.graphics.translate(x, y - 14 + bob)
  tilted(-3, 0, 12, 6, 0.3, C.gunmetalLight)
  tilted(4, -2, 9, 6, -0.6, C.rust)
  disc(0, 3, 3, C.black)
  love.graphics.pop()
end

--- Where it fell apart: the heap spilled out flat, its arms off, its
--- headlight out, smoke still coming out of the stack.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.scale(Look.SCALE)
  love.graphics.rotate(w.angle + 0.3)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 0, 0, 50, 42, 24)
  love.graphics.scale(1.15, 0.9)
  heap(0, 0, clock, true)
  love.graphics.pop()
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.scale(Look.SCALE)
  love.graphics.rotate(w.angle)
  for i, p in ipairs(PLATES) do -- the plates it shed, scattered round it
    local a = i * 2.4
    tilted(math.cos(a) * (44 + i * 3), math.sin(a) * (40 + i * 2), p[3], p[4], a, C.gunmetalLight)
  end
  fist(48, -28)
  fist(-40, 34)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
