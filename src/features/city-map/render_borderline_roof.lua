-- The Bunker's roof (borderline.lua's `bunker`, borderline_bunker.lua),
-- drawn into the map's canvas by render_borderline.lua: the rim cannons'
-- mounts (the guns on them are the army's: cannon_look.lua), the eye's
-- hatch in the middle, the engine intakes (their fans turn live:
-- works.lua), the vents, the hatch up from inside. Each is a
-- `DRAW[kind](s)` for a thing of `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Roof = {}

local INK, LINE, C = Kit.INK, Kit.LINE, Kit.C
local color, hash, box, hazard = Kit.color, Kit.hash, Kit.box, Kit.hazard

local DRAW = {}
Roof.DRAW = DRAW

local EYE = { 0.95, 0.12, 0.1 }

--- A rim cannon's mount: an armoured socket let into the deck, bolted
--- round, a hazard ring round its lip.
function DRAW.cannon(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + LINE, 28)
  for i = 0, 11 do
    color(i % 2 == 0 and C.yellow or INK)
    love.graphics.arc("fill", cx, cy, r, i * math.pi / 6, (i + 1) * math.pi / 6, 4)
  end
  color(C.gunmetal)
  love.graphics.circle("fill", cx, cy, r * 0.8, 28)
  color(C.gunmetalLight)
  for k = 0, 9 do
    local a = k / 10 * math.pi * 2
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.68, cy + math.sin(a) * r * 0.68, 2.5, 6)
  end
end

--- The eye's hatch, the way down: a round iris of armoured blades shut
--- over a red glass eye, a ring of yellow round it, MAX on the plate.
function DRAW.eyehatch(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + LINE, 48)
  color(C.yellow)
  love.graphics.circle("fill", cx, cy, r, 48)
  color(C.gunmetal)
  love.graphics.circle("fill", cx, cy, r * 0.88, 48)
  for k = 0, 7 do -- the iris's blades, each lit along one edge
    local a0 = k * math.pi / 4
    local a1 = a0 + math.pi / 4
    color(k % 2 == 0 and C.gunmetalLight or C.gunmetal)
    love.graphics.polygon("fill", cx, cy, cx + math.cos(a0) * r * 0.86, cy + math.sin(a0) * r * 0.86,
      cx + math.cos(a1) * r * 0.86, cy + math.sin(a1) * r * 0.86)
    color(INK, 0.6)
    love.graphics.setLineWidth(3)
    love.graphics.line(cx, cy, cx + math.cos(a0) * r * 0.86, cy + math.sin(a0) * r * 0.86)
    love.graphics.setLineWidth(1)
  end
  color(INK) -- the eye in the middle
  love.graphics.circle("fill", cx, cy, r * 0.3, 32)
  color(EYE)
  love.graphics.circle("fill", cx, cy, r * 0.25, 32)
  color({ 1, 0.6, 0.55 })
  love.graphics.circle("fill", cx - r * 0.08, cy - r * 0.08, r * 0.07, 16)
  color(INK, 0.7)
  for k = 0, 15 do -- bolts round the rim
    local a = k / 16 * math.pi * 2
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.94, cy + math.sin(a) * r * 0.94, 3, 6)
  end
end

--- An engine intake: a round hole going deep into the bunker, a hazard
--- ring round its lip, the duct stepping down darker to where its fan
--- turns (works.lua), the struts across it.
function DRAW.intake(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + LINE, 40)
  for i = 0, 15 do
    color(i % 2 == 0 and C.yellow or INK)
    love.graphics.arc("fill", cx, cy, r, i * math.pi / 8, (i + 1) * math.pi / 8, 4)
  end
  for i = 1, 4 do
    local k = i / 5
    love.graphics.setColor(C.gunmetal[1] * (1 - k), C.gunmetal[2] * (1 - k), C.gunmetal[3] * (1 - k))
    love.graphics.circle("fill", cx, cy, r * (0.92 - i * 0.05), 40)
  end
  color(C.gunmetalLight) -- the guard's struts across the mouth
  for k = 0, 2 do
    local a = k * math.pi / 3
    love.graphics.setLineWidth(5)
    love.graphics.line(cx - math.cos(a) * r * 0.86, cy - math.sin(a) * r * 0.86, cx + math.cos(a) * r * 0.86,
      cy + math.sin(a) * r * 0.86)
  end
  love.graphics.setLineWidth(1)
end

--- A vent on the deck: a raised housing, louvres across it lit along their
--- tops, soot round it from the exhaust.
function DRAW.vent(s)
  local h = hash(s.seed or s.x)
  color(INK, 0.25)
  love.graphics.ellipse("fill", s.x + s.w / 2 + 8, s.y + s.h / 2 + 4, s.w * 0.8, s.h * 0.6, 16)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  for y = s.y + 8, s.y + s.h - 10, 10 do
    color(INK, 0.55)
    love.graphics.rectangle("fill", s.x + 6, y, s.w - 12, 5)
    color(C.white, 0.2)
    love.graphics.rectangle("fill", s.x + 6, y, s.w - 12, 1)
  end
  if h < 0.3 then -- a warning stencil on its side
    color(C.yellow)
    love.graphics.rectangle("fill", s.x, s.y + s.h - 6, s.w, 6)
  end
end

--- The hatch up from inside: a steel plate in the deck, hazard at both
--- ends, the rungs of the ladder showing through the open half.
function DRAW.hatch(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  hazard(s.x, s.y, s.w, 14)
  hazard(s.x, s.y + s.h - 14, s.w, 14)
  color(INK)
  love.graphics.rectangle("fill", s.x + 16, s.y + 22, s.w - 32, s.h - 44)
  color(C.gunmetalLight)
  for y = s.y + 30, s.y + s.h - 30, 16 do
    love.graphics.rectangle("fill", s.x + 24, y, s.w - 48, 4)
  end
end

return Roof
