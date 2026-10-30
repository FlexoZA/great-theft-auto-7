-- Thousand Papercuts' road up the cliff (borderline.lua's `cuts`,
-- borderline_cuts.lua), drawn into the map's canvas by
-- render_borderline.lua: the bunker's door at the top and the sentry
-- nests cut into the rock beside the road (the road, its lines and the
-- cliff are the ground's and render_borderline.lua's). Each is a
-- `DRAW[kind](s)` for a thing of `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Cliff = {}

local INK, C = Kit.INK, Kit.C
local color, box, hazard = Kit.color, Kit.box, Kit.hazard

local DRAW = {}
Cliff.DRAW = DRAW

--- The bunker's door: a concrete frame set into the rock, two armoured
--- leaves meeting in the middle, riveted, hazard chevrons down their
--- meeting edges, Hyperbole's H across them, a red lamp either side.
function DRAW.bunkerdoor(s)
  box(s.x - 24, s.y - 10, s.w + 48, s.h + 10, C.concreteDark) -- the frame
  color(INK, 0.3)
  for a = s.x - 20, s.x + s.w + 20, 26 do
    love.graphics.rectangle("fill", a, s.y - 10, 2, 10)
  end
  local half = s.w / 2
  for k, lx in ipairs({ s.x, s.x + half }) do
    box(lx + 4, s.y + 4, half - 8, s.h - 8, C.gunmetal)
    color(C.gunmetalLight) -- the leaf's armour plates
    for py = s.y + 14, s.y + s.h - 24, 26 do
      love.graphics.rectangle("fill", lx + 12, py, half - 24, 18)
    end
    color(INK, 0.6) -- rivets round it
    for a = lx + 12, lx + half - 12, 16 do
      love.graphics.circle("fill", a, s.y + 9, 2, 6)
      love.graphics.circle("fill", a, s.y + s.h - 9, 2, 6)
    end
    local ex = k == 1 and lx + half - 22 or lx + 4 -- the chevrons down the meeting edge
    for py = s.y + 4, s.y + s.h - 22, 18 do
      color(C.yellow)
      love.graphics.polygon("fill", ex, py, ex + 18, py + 9, ex, py + 18)
    end
  end
  color(INK) -- Hyperbole's H over the seam
  love.graphics.rectangle("fill", s.x + half - 30, s.y + s.h / 2 - 26, 60, 52)
  color(C.yellow)
  love.graphics.rectangle("fill", s.x + half - 22, s.y + s.h / 2 - 20, 12, 40)
  love.graphics.rectangle("fill", s.x + half + 10, s.y + s.h / 2 - 20, 12, 40)
  love.graphics.rectangle("fill", s.x + half - 10, s.y + s.h / 2 - 6, 20, 12)
  for _, lx in ipairs({ s.x - 16, s.x + s.w + 4 }) do -- the lamps
    color(INK)
    love.graphics.circle("fill", lx + 6, s.y + s.h / 2, 10, 12)
    color({ 0.95, 0.15, 0.1 })
    love.graphics.circle("fill", lx + 6, s.y + s.h / 2, 7, 12)
  end
  hazard(s.x - 24, s.y + s.h, s.w + 48, 10)
end

--- A sentry's nest cut into the rock: a dark hole with a concrete collar
--- round it, hazard paint on the lip, scorch where it fires from.
function DRAW.nest(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK, 0.25) -- scorched rock round it
  love.graphics.ellipse("fill", cx - r * 0.3, cy, r * 1.5, r * 1.1, 18)
  color(INK)
  love.graphics.circle("fill", cx, cy, r + 5, 20)
  color(C.concrete)
  love.graphics.circle("fill", cx, cy, r, 20)
  color(C.yellow)
  love.graphics.setLineWidth(5)
  love.graphics.arc("line", "open", cx, cy, r * 0.82, math.pi * 0.6, math.pi * 1.4, 12)
  love.graphics.setLineWidth(1)
  color(INK)
  love.graphics.circle("fill", cx, cy, r * 0.62, 18)
end

return Cliff
