-- Prosperity's streets and plaza (borderline.lua's `prosperity`), drawn
-- into the map's canvas by render_borderline.lua: the pavements round the
-- blocks, the gold inlay round the statue, Max's statue, planters, the legs
-- his screens stand on (the screens themselves are live: the borderline
-- feature's screens.lua). Each is a `DRAW[kind](s)` for a thing of
-- `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local City = {}

local INK, C = Kit.INK, Kit.C
local color, hash = Kit.color, Kit.hash
local blob = Kit.blob

local DRAW = {}
City.DRAW = DRAW

local W = 38 -- px of pavement round a block

--- The pavement round a block (or the plaza): a ring of pale paving slabs
--- `W` wide just inside `s`, a kerb along its street side.
function DRAW.sidewalk(s)
  local strips = {
    { s.x, s.y, s.w, W }, { s.x, s.y + s.h - W, s.w, W }, { s.x, s.y + W, W, s.h - 2 * W },
    { s.x + s.w - W, s.y + W, W, s.h - 2 * W },
  }
  for _, st in ipairs(strips) do
    color(C.pavement)
    love.graphics.rectangle("fill", st[1], st[2], st[3], st[4])
  end
  color(INK, 0.15) -- the slabs' joints
  for x = s.x + 32, s.x + s.w - 8, 32 do
    love.graphics.rectangle("fill", x, s.y, 2, W)
    love.graphics.rectangle("fill", x, s.y + s.h - W, 2, W)
  end
  for y = s.y + 32, s.y + s.h - 8, 32 do
    love.graphics.rectangle("fill", s.x, y, W, 2)
    love.graphics.rectangle("fill", s.x + s.w - W, y, W, 2)
  end
  color(C.kerb) -- the kerb, on the street side
  love.graphics.setLineWidth(5)
  love.graphics.rectangle("line", s.x + 2, s.y + 2, s.w - 4, s.h - 4)
  love.graphics.setLineWidth(1)
  color(INK, 0.6)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", s.x, s.y, s.w, s.h)
  love.graphics.setLineWidth(1)
end

--- Gold set in the plaza's paving round the statue: a ring, rays out from
--- it, a second ring inside.
function DRAW.inlay(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.gold, 0.85)
  love.graphics.setLineWidth(10)
  love.graphics.circle("line", cx, cy, r - 6, 64)
  love.graphics.setLineWidth(4)
  love.graphics.circle("line", cx, cy, r * 0.62, 48)
  for i = 0, 23 do
    local a = i * math.pi / 12
    local r0, r1 = r * 0.66, i % 2 == 0 and r - 14 or r * 0.85
    love.graphics.line(cx + math.cos(a) * r0, cy + math.sin(a) * r0, cx + math.cos(a) * r1, cy + math.sin(a) * r1)
  end
  love.graphics.setLineWidth(1)
end

--- Max's statue, larger than life, in gold on a stepped plinth, seen from
--- above: the flat-top, the sweatband, his shoulders and the chain, one arm
--- flexed up beside his head, the other fist on his hip; MAX on the plinth.
function DRAW.statue(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local r = s.w / 2
  blob(s.x, s.y, s.w, s.h, C.gunmetalLight) -- the plinth, stepped
  color(C.gunmetal)
  love.graphics.circle("fill", cx, cy, r * 0.82, 40)
  color(C.gunmetalLight)
  love.graphics.circle("fill", cx, cy, r * 0.72, 40)
  color(C.shadow) -- his shadow on it
  love.graphics.ellipse("fill", cx + 12, cy + 14, r * 0.48, r * 0.36, 24)
  local gold, goldHi, goldDark = C.gold, { 1, 0.92, 0.55 }, { 0.70, 0.52, 0.12 }
  local function part(fill, mode, ...)
    color(INK)
    love.graphics.setLineWidth(5)
    love.graphics[mode]("line", ...)
    love.graphics.setLineWidth(1)
    color(fill)
    love.graphics[mode]("fill", ...)
  end
  -- The shoulders and chest, broad.
  part(goldDark, "ellipse", cx, cy + r * 0.12, r * 0.5, r * 0.28, 24)
  part(gold, "ellipse", cx - 2, cy + r * 0.1, r * 0.46, r * 0.24, 24)
  -- The fist on his hip (his right, our left), the flexed arm (his left).
  part(gold, "circle", cx - r * 0.5, cy + r * 0.3, r * 0.1, 12)
  part(gold, "polygon", cx + r * 0.36, cy, cx + r * 0.62, cy + r * 0.04, cx + r * 0.6, cy - r * 0.34,
    cx + r * 0.48, cy - r * 0.36, cx + r * 0.46, cy - r * 0.08, cx + r * 0.34, cy - r * 0.08)
  part(goldHi, "circle", cx + r * 0.55, cy - r * 0.4, r * 0.1, 12) -- the fist up
  color(goldHi) -- the bicep's shine
  love.graphics.ellipse("fill", cx + r * 0.53, cy - r * 0.08, r * 0.05, r * 0.1, 8)
  -- The head, all flat-top from up here, the sweatband round it.
  part(goldHi, "rectangle", cx - r * 0.2, cy - r * 0.26, r * 0.4, r * 0.34)
  color(goldDark)
  for k = 1, 4 do
    love.graphics.rectangle("fill", cx - r * 0.2 + k * r * 0.08, cy - r * 0.26, 2, r * 0.34)
  end
  color(gold)
  love.graphics.rectangle("fill", cx - r * 0.22, cy + r * 0.04, r * 0.44, r * 0.06)
  color(goldDark) -- the chain over his chest
  love.graphics.setLineWidth(3)
  love.graphics.arc("line", "open", cx, cy + r * 0.1, r * 0.18, 0.4, math.pi - 0.4, 10)
  love.graphics.setLineWidth(1)
  -- The plaque on the plinth's south face.
  color(INK)
  love.graphics.rectangle("fill", cx - 34, s.y + s.h - 26, 68, 22, 3)
  love.graphics.setFont(Kit.signFont())
  color(C.gold)
  love.graphics.printf("MAX", cx - 34, s.y + s.h - 27, 68, "center")
end

--- A planter: a round concrete tub, a clipped shrub in it, flowers in
--- Hyperbole yellow.
function DRAW.planter(s)
  local h = hash(s.seed or s.x)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  blob(s.x, s.y, s.w, s.h, C.pavement)
  color(C.concreteDark)
  love.graphics.circle("fill", cx, cy, r * 0.82, 20)
  color(C.green)
  love.graphics.circle("fill", cx, cy, r * 0.75, 18)
  love.graphics.setColor(0.30, 0.55, 0.22)
  for i = 0, 4 do
    local a = h * 6 + i * 1.3
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.35, cy + math.sin(a) * r * 0.35, r * 0.3, 10)
  end
  color(C.yellow)
  for i = 0, 5 do
    local a = h * 9 + i * 1.05
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.5, 3, 6)
  end
end

--- A leg one of Max's screens stands on: a steel column on a footing,
--- bolted down, hazard yellow round its foot.
function DRAW.pylon(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  blob(s.x - 6, s.y - 6, s.w + 12, s.h + 12, C.concrete)
  color(C.gunmetalLight)
  for i = 0, 3 do
    local a = math.pi / 4 + i * math.pi / 2
    love.graphics.circle("fill", cx + math.cos(a) * (r + 1), cy + math.sin(a) * (r + 1), 3, 6)
  end
  blob(s.x, s.y, s.w, s.h, C.yellow)
  blob(s.x + s.w * 0.2, s.y + s.h * 0.2, s.w * 0.6, s.h * 0.6, C.gunmetal)
end

return City
