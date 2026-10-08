-- Clothes icons: one small front-on drawing per piece (kinds.lua), in the
-- piece's own colour, for the shop, the bag, the gear slots and a piece
-- lying on the road. About 30 x 30 px at scale 1, centred on (cx, cy).
-- Shaded like the guns (weapons/shade.lua). A piece with no drawing of its
-- own gets its slot's plain one: a cap, a shirt, trousers or shoes.

local Shade = require("src.features.weapons.shade")
local Kinds = require("src.features.gear.kinds")

local box, poly, line, ellipse, dot = Shade.box, Shade.poly, Shade.line, Shade.ellipse, Shade.dot
local set, lit, strokes = Shade.set, Shade.lit, Shade.strokes

local Icons = {}

local SILVER = { 0.85, 0.87, 0.9 } -- reflective tape
local HIVIS = { 0.95, 0.85, 0.2 }
local RUBBER = { 0.2, 0.2, 0.23 }
local STEEL = { 0.78, 0.8, 0.86 }
local GLASS = { 0.45, 0.7, 0.9 }
local WHITE = { 0.92, 0.92, 0.94 }

-- Shapes every piece of a slot starts from -----------------------------------

--- A jacket or shirt: the body, two sleeves out to the cuffs, a collar.
local function torso(c, sleeveLen)
  sleeveLen = sleeveLen or 12
  poly(c, -9, -10, -15, -6, -15, -6 + sleeveLen, -10, -6 + sleeveLen, -9, -2) -- left sleeve
  poly(c, 9, -10, 15, -6, 15, -6 + sleeveLen, 10, -6 + sleeveLen, 9, -2) -- right sleeve
  box(-10, -11, 20, 23, c, 2) -- body
end

--- Trousers: the waist, then a leg down each side.
local function legs(c, len)
  len = len or 13
  poly(c, -10, -1, -1, -1, -2, len, -10.5, len) -- left leg
  poly(c, 1, -1, 10, -1, 10.5, len, 2, len) -- right leg
  box(-10, -12, 20, 12, c, 1.5) -- seat
  box(-10, -13, 20, 3, c, 0.5) -- waistband
end

--- A pair of shoes side by side, soles `sole` coloured, `top` how high they
--- come: the toe, the ankle (or the shaft of a boot) over it, the sole.
local function pair(c, sole, top)
  top = top or -2
  for _, x in ipairs({ -15, 1 }) do
    poly(c, x + 7, 1, x + 12, 3.5, x + 14.5, 6, x + 14.5, 8, x + 7, 8) -- toe
    box(x, top, 9, 8 - top, c, 1.5) -- ankle
    box(x - 0.5, 8, 15.5, 3, sole, 1)
  end
end

--- A dome for a helmet or a cap's crown, `r` wide and `h` high over y = 3.
local function dome(c, r, h)
  ellipse(0, 3, r, h, c, "arc")
end

-- Head -------------------------------------------------------------------------

local DRAW = {}

DRAW["tactical-hat"] = function(c)
  dome(c, 11, 11)
  box(-11, 1, 22, 4, c, 1.5) -- band
  poly(c, 9, 2, 19, 3, 19, 6, 9, 5) -- the peak
  box(-4, -5, 7, 4, lit(c, 0.25), 0.5) -- a patch
  dot(0, -8.5, 1, c, 0.6) -- button on top
end

DRAW["crash-helmet"] = function(c)
  dome(c, 13, 15)
  box(-13, 1, 26, 9, c, 3) -- the chin guard
  box(-9, -5, 18, 7, RUBBER, 2.5) -- the visor
  set(WHITE, 1, 0.7)
  love.graphics.polygon("fill", -6, -4, -3, -4, -6, 0) -- a glint on it
  line(c, 0.5, 1, -10, 6, 10, 6) -- vents
end

DRAW["riot-helmet"] = function(c)
  dome(c, 12, 13)
  box(-12, 0, 24, 3, c, 1) -- rim
  set(GLASS, 1, 0.35)
  love.graphics.rectangle("fill", -11, 1, 22, 12, 3) -- the face shield
  set(GLASS, 0.6)
  love.graphics.setLineWidth(Shade.pixel())
  love.graphics.rectangle("line", -11, 1, 22, 12, 3)
  set(WHITE, 1, 0.6)
  love.graphics.line(-8, 3, -5, 10) -- light on the shield
  line(RUBBER, 1, 1.5, -12, 2, -12, 12) -- chin strap
end

DRAW["welding-mask"] = function(c)
  line(RUBBER, 1, 2, -12, -9, 12, -9) -- headband
  box(-11, -11, 22, 25, c, 4) -- the mask
  box(-8, -4, 16, 6, RUBBER, 1) -- the dark lens
  set(GLASS, 1, 0.6)
  love.graphics.rectangle("fill", -7, -3, 4, 1.2) -- its glint
  box(-4, 6, 8, 5, c, 1) -- the chin piece
  strokes(c, 0.55, 3, -2, 7, 1.4, 4) -- vents in it
  dot(-11, -9, 1.5, STEEL, 1) -- the pivot
  dot(11, -9, 1.5, STEEL, 1)
end

DRAW["ballistic-helmet"] = function(c)
  dome(c, 13, 14)
  box(-14, 1, 28, 3, c, 1) -- rim
  box(-3, -12, 6, 4, RUBBER, 1) -- the night-vision mount
  box(-13, -3, 3, 4, RUBBER, 0.5) -- side rails
  box(10, -3, 3, 4, RUBBER, 0.5)
  line(RUBBER, 1, 1.5, -10, 4, -8, 11, 8, 11, 10, 4) -- chin strap
  for _, d in ipairs({ { -6, -6 }, { 4, -8 }, { 7, -2 }, { -2, -2 } }) do -- camouflage
    set(c, 0.7)
    love.graphics.ellipse("fill", d[1], d[2], 2.2, 1.4)
  end
end

-- Body -------------------------------------------------------------------------

DRAW["plate-carrier"] = function(c)
  box(-11, -11, 5, 6, c, 1) -- shoulder straps
  box(6, -11, 5, 6, c, 1)
  box(-11, -7, 22, 20, c, 2) -- the carrier
  box(-8, -5, 16, 11, c, 1) -- the plate pocket
  strokes(c, 0.55, 3, -8, 7.5, 1.8, 16) -- webbing
  box(-9, 7, 5, 5, c, 0.8) -- pouches
  box(-2.5, 7, 5, 5, c, 0.8)
  box(4, 7, 5, 5, c, 0.8)
end

DRAW["fire-jacket"] = function(c)
  torso(c, 15)
  box(-10, 1, 20, 3, HIVIS, 0) -- reflective bands round the body
  box(-10, 6, 20, 2, SILVER, 0)
  box(-15, 5, 5, 2, SILVER, 0) -- and the cuffs
  box(10, 5, 5, 2, SILVER, 0)
  poly(c, -4, -11, 4, -11, 3, -7, -3, -7) -- the high collar
  line(c, 0.45, 1, 0, -7, 0, 12) -- zip
end

DRAW["leather-jacket"] = function(c)
  torso(c, 15)
  poly(lit(c, 0.15), -9, -11, -2, -11, -4, 0) -- lapels
  poly(lit(c, 0.15), 9, -11, 2, -11, 4, 0)
  line(STEEL, 1, 1.2, -2, -6, 3, 12) -- the zip, across
  dot(-6, 4, 0.9, STEEL, 1) -- studs
  dot(6, 4, 0.9, STEEL, 1)
  box(-10, 9, 20, 3, c, 0.5) -- belt at the hem
  box(-1.5, 9.3, 3, 2.4, STEEL, 0.3) -- its buckle
end

DRAW["lineman-jacket"] = function(c)
  torso(c, 15)
  box(-10, -3, 20, 2.5, SILVER, 0) -- reflective bands
  box(-10, 5, 20, 2.5, SILVER, 0)
  box(-15, 4, 5, 2, SILVER, 0)
  box(10, 4, 5, 2, SILVER, 0)
  -- A lightning bolt on the chest.
  poly(RUBBER, 2, -10, -3, -4, 1, -4)
  poly(RUBBER, -1, -5, 3, -5, -2, 1)
end

DRAW["puffer-jacket"] = function(c)
  torso(c, 14)
  for i = 0, 4 do -- quilted bands, each puffed up
    box(-10, -10 + i * 4.4, 20, 4.2, c, 2)
  end
  box(-7, -14, 14, 5, c, 2.5) -- the hood, rolled into a collar
  line(c, 0.45, 1, 0, -9, 0, 12) -- zip
end

-- Pants ------------------------------------------------------------------------

DRAW["cargo-pants"] = function(c)
  legs(c)
  box(-10.5, 2, 5, 6, c, 0.8) -- the side pockets
  box(5.5, 2, 5, 6, c, 0.8)
  box(-1.5, -12.5, 3, 2, STEEL, 0.3) -- buckle
end

DRAW["kevlar-trousers"] = function(c)
  legs(c)
  box(-9.5, 3, 7, 5, RUBBER, 1.5) -- knee pads
  box(2.5, 3, 7, 5, RUBBER, 1.5)
  strokes(c, 0.6, 2, -8, -9, 3, 16) -- quilting
end

DRAW["fireproof-overalls"] = function(c)
  box(-8, -17, 3, 6, c, 0.5) -- braces
  box(5, -17, 3, 6, c, 0.5)
  legs(c)
  box(-7, -12, 14, 6, c, 1) -- the bib
  box(-10, 8, 8, 2, SILVER, 0) -- reflective bands at the shins
  box(2, 8, 8, 2, SILVER, 0)
  dot(-6.5, -15.5, 1, STEEL, 1)
  dot(6.5, -15.5, 1, STEEL, 1)
end

DRAW["biker-leathers"] = function(c)
  legs(c)
  box(-9.5, 2, 7, 6, lit(c, 0.2), 2.5) -- knee armour
  box(2.5, 2, 7, 6, lit(c, 0.2), 2.5)
  line(STEEL, 0.9, 1, -10, -8, -10.3, 12) -- stitching down the sides
  line(STEEL, 0.9, 1, 10, -8, 10.3, 12)
  box(-1.5, -12.5, 3, 2, STEEL, 0.3)
end

DRAW["rubber-waders"] = function(c)
  box(-7, -17, 2, 4, RUBBER, 0.3) -- braces
  box(5, -17, 2, 4, RUBBER, 0.3)
  legs(c, 11)
  box(-7, -14, 14, 5, c, 1) -- the bib
  box(-11, 9, 10, 5, RUBBER, 1.5) -- boots, all one piece
  box(1, 9, 10, 5, RUBBER, 1.5)
end

-- Shoes ------------------------------------------------------------------------

DRAW["running-shoes"] = function(c)
  pair(c, WHITE)
  for _, x in ipairs({ -15, 1 }) do
    line(WHITE, 1, 1.5, x + 3, 5, x + 10, 2) -- the stripe
    strokes(WHITE, 0.9, 2, x + 3, -0.5, 1.6, 4) -- laces
  end
end

DRAW["rubber-boots"] = function(c)
  pair(c, RUBBER, -12)
  for _, x in ipairs({ -15, 1 }) do
    box(x + 0.5, -13, 8.5, 2.5, lit(c, 0.2), 1) -- the rim at the top
  end
end

DRAW["steel-toe-boots"] = function(c)
  pair(c, RUBBER, -6)
  for _, x in ipairs({ -15, 1 }) do
    ellipse(x + 11, 6, 3.5, 2.5, STEEL) -- the steel toe
    strokes(lit(c, 0.3), 1, 3, x + 3, -4, 2.2, 4) -- laces
  end
end

DRAW["combat-boots"] = function(c)
  pair(c, RUBBER, -12)
  for _, x in ipairs({ -15, 1 }) do
    strokes(RUBBER, 1, 5, x + 3, -10, 2.8, 4) -- laces all the way up
    box(x - 0.5, 10, 15, 1.5, RUBBER, 0) -- a deep tread
  end
end

DRAW["fireproof-boots"] = function(c)
  pair(c, RUBBER, -12)
  for _, x in ipairs({ -15, 1 }) do
    box(x + 0.5, -5, 8.5, 2.5, SILVER, 0) -- a reflective band
    box(x + 0.5, -13, 8.5, 2, c, 0.5) -- the pull-on top
  end
end

-- Plain pieces, by slot, for anything without a drawing of its own.
local PLAIN = {
  head = function(c)
    dome(c, 11, 10)
    box(-11, 1, 22, 4, c, 1.5)
    poly(c, 9, 2, 18, 3, 18, 6, 9, 5)
  end,
  body = function(c)
    torso(c)
  end,
  pants = function(c)
    legs(c)
  end,
  shoes = function(c)
    pair(c, WHITE)
  end,
}

--- Draw the piece `key` ("running-shoes") centred on (cx, cy), `scale`
--- times its natural size, `a` (1) opaque.
function Icons.draw(key, cx, cy, scale, a)
  local g = Kinds.byKey[key]
  local c = g and g.color or { 0.6, 0.6, 0.65 }
  local draw = DRAW[key] or PLAIN[g and g.slot or "body"]
  scale = scale or 1
  Shade.begin(scale, a)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale)
  if g and (g.slot == "pants" or key == "rubber-boots" or key == "combat-boots" or key == "fireproof-boots") then
    love.graphics.translate(0, 1) -- the tall ones sit a little lower, centred
  end
  draw(c)
  love.graphics.pop()
  Shade.finish()
end

--- Does piece `key` have a drawing of its own (not just its slot's)?
function Icons.has(key)
  return DRAW[key] ~= nil
end

return Icons
