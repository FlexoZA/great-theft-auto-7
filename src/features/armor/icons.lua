-- Armor icons: one small front-on drawing per kind (kinds.lua), in its own
-- colour, for the shop, the bag, the armor slot and a vest lying on the
-- road. About 30 x 30 px at scale 1, centred on (cx, cy). Shaded like the
-- guns (weapons/shade.lua); an armor with no drawing of its own is a vest.

local Shade = require("src.features.weapons.shade")
local Kinds = require("src.features.armor.kinds")

local box, poly, line, ellipse, dot, strokes = Shade.box, Shade.poly, Shade.line, Shade.ellipse, Shade.dot,
  Shade.strokes
local lit = Shade.lit

local Icons = {}

local STRAP = { 0.2, 0.2, 0.24 }
local STEEL = { 0.78, 0.8, 0.86 }
local CERAMIC = { 0.88, 0.86, 0.8 }
local RUBBER = { 0.2, 0.2, 0.23 }

--- A vest's shoulders over its body: `c` the cloth, `neck` how deep the
--- collar dips.
local function vest(c, neck)
  neck = neck or 4
  poly(c, -12, -9, -6, -13, -4, -13 + neck, -4, -4, -12, -4) -- left shoulder
  poly(c, 12, -9, 6, -13, 4, -13 + neck, 4, -4, 12, -4) -- right shoulder
  box(-12, -6, 24, 19, c, 2.5) -- body
end

local DRAW = {}

DRAW.vest = function(c)
  vest(c)
  box(-8, -3, 16, 8, lit(c, 0.2), 1) -- the velcro panel across the chest
  line(c, 0.45, 1, 0, -6, 0, 13) -- the opening down the front
  box(-12, 7, 24, 3, STRAP, 0.5) -- side straps round the waist
  box(-2, 7, 4, 3, STEEL, 0.5) -- their buckle
end

DRAW["bomb-suit"] = function(c)
  box(-7, -15, 14, 7, c, 3) -- the high neck guard
  vest(c, 6)
  strokes(c, 0.6, 3, -11, -1, 4, 22) -- padded segments across the chest
  box(-5, 10, 10, 5, c, 2) -- the groin flap
  ellipse(-12, -6, 4, 4, c) -- bulky shoulders
  ellipse(12, -6, 4, 4, c)
end

DRAW["riot-armor"] = function(c)
  vest(c)
  box(-9, -5, 18, 10, lit(c, 0.25), 3) -- the hard chest plate
  line(c, 0.5, 1, 0, -4, 0, 4) -- its ridge
  for i = 0, 1 do -- segmented pauldrons, both sides
    box(-15, -11 + i * 4, 6, 4.5, lit(c, 0.15), 1.5)
    box(9, -11 + i * 4, 6, 4.5, lit(c, 0.15), 1.5)
  end
  strokes(c, 0.55, 2, -10, 8, 2.5, 20) -- the belly bands
end

DRAW["insulated-suit"] = function(c)
  box(-8, -15, 16, 7, c, 3.5) -- the hood
  box(-5, -13, 10, 4, RUBBER, 1.5) -- the face in it
  vest(c, 6)
  line(RUBBER, 1, 1.5, 0, -8, 0, 13) -- the zip, taped
  box(-14, -4, 4, 12, c, 1.5) -- the sleeves
  box(10, -4, 4, 12, c, 1.5)
  box(-14.5, 7, 5, 4, RUBBER, 1.5) -- rubber gloves
  box(9.5, 7, 5, 4, RUBBER, 1.5)
end

DRAW["ceramic-plates"] = function(c)
  vest(c)
  box(-9, -5, 18, 12, CERAMIC, 2) -- the big front plate
  line(CERAMIC, 0.75, 1, -9, 1, 9, 1) -- where it was cast in two
  box(-12, 7, 24, 5, c, 1) -- the cummerbund
  strokes(STRAP, 1, 3, -10, 8, 1.5, 20) -- webbing on it
  dot(-7, -3, 0.9, STEEL, 1) -- the plate's fixings
  dot(7, -3, 0.9, STEEL, 1)
end

--- Draw the armor `key` ("vest") centred on (cx, cy), `scale` times its
--- natural size, `a` (1) opaque.
function Icons.draw(key, cx, cy, scale, a)
  local k = Kinds.byKey[key]
  local c = k and k.color or { 0.5, 0.5, 0.6 }
  scale = scale or 1
  Shade.begin(scale, a)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale)
  local draw = DRAW[key] or DRAW.vest
  draw(c)
  love.graphics.pop()
  Shade.finish()
end

--- Does armor `key` have a drawing of its own (not just a vest)?
function Icons.has(key)
  return DRAW[key] ~= nil
end

return Icons
