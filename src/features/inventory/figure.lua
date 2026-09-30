-- The character on the inventory screen, front on, wearing what you wear:
-- the clothes in their slots (gear), the armor over them, the gun in hand
-- in the right hand. Each piece is drawn in its own colour with the bits
-- that make it itself (a crash helmet's visor, a firefighter jacket's
-- bands, knee pads, tall boots); a piece with nothing special gets its
-- slot's plain shape in its colour. With nothing on they stand in a plain
-- shirt, trousers and shoes. Shaded like the icons (weapons/shade.lua).
--
-- Units: 200 tall, the top of the head at 0 and the feet at 200, centred
-- on x = 0. `Figure.draw(cx, top, scale, dress, face)` puts it on the screen.
--
-- Given `face` (a src/art/face.lua face, the menu's crazy one), the head is
-- that instead: its pixel art, big, on the neck, blinking and twitching as
-- it does on the menu (the caller updates it). It is drawn a whole number
-- of screen pixels to its pixel so it stays crisp, the hair needs
-- `BIG_HEADROOM` more room over the top (`Figure.height(face)`), and
-- whatever is on the head is stretched to fit it.

local Shade = require("src.features.weapons.shade")
local GearKinds = require("src.features.gear.kinds")
local ArmorKinds = require("src.features.armor.kinds")
local GunIcons = require("src.features.weapons.icons")
local Face = require("src.art.face")

local box, poly, line, ellipse, dot = Shade.box, Shade.poly, Shade.line, Shade.ellipse, Shade.dot
local set, lit, strokes = Shade.set, Shade.lit, Shade.strokes

local Figure = {}

-- The two skin tones, as src/art/face.lua has them (inclusive mode picks the
-- dark one).
local SKINS = {
  { skin = { 0.90, 0.78, 0.62 }, hair = { 0.16, 0.09, 0.06 } },
  { skin = { 0.33, 0.20, 0.13 }, hair = { 0.07, 0.05, 0.04 } },
}

local SHIRT = { 0.36, 0.38, 0.50 }
local TROUSERS = { 0.28, 0.30, 0.40 }
local SHOES = { 0.22, 0.22, 0.26 }
local SILVER = { 0.85, 0.87, 0.9 }
local HIVIS = { 0.95, 0.85, 0.2 }
local RUBBER = { 0.2, 0.2, 0.23 }
local STEEL = { 0.78, 0.8, 0.86 }
local GLASS = { 0.45, 0.7, 0.9 }
local WHITE = { 0.92, 0.92, 0.94 }
local INK = { 0.08, 0.06, 0.07 }

local HEAD_Y, HEAD_R = 24, 19

-- The big head: the menu face's picture (64 x 72 pixels, about a unit
-- each, rounded so each is a whole number of screen pixels), its chin on
-- the neck, and how headwear drawn for the small head is stretched over it.
local BIG_HEADROOM = 24 -- units the spiky hair takes above y = 0
local BIG_CHIN = 42 -- units down where the picture's chin (its row 70) goes
local BIG_FACE_ROW = 38 -- the picture's row at the middle of the face
local BIG_SX, BIG_SY = 1.35, 1.65 -- headwear stretched this much across and down, at a unit a pixel

--- Units per pixel of the face's picture at `scale`: whole screen pixels.
local function bigPixel(scale)
  return math.max(1, math.floor(scale + 0.5)) / scale
end

--- How tall the whole drawing is in units: 200, and room for the big hair.
function Figure.height(face)
  return face and 200 + BIG_HEADROOM or 200
end

-- The body --------------------------------------------------------------------

local function head(sk)
  box(-6, 38, 12, 10, sk.skin, 2) -- neck
  ellipse(0, HEAD_Y, HEAD_R, HEAD_R + 1, sk.skin)
  ellipse(-HEAD_R, HEAD_Y + 2, 3, 5, sk.skin) -- ears
  ellipse(HEAD_R, HEAD_Y + 2, 3, 5, sk.skin)
end

local function drawFace()
  dot(-7, HEAD_Y + 1, 2.2, INK, 1) -- eyes
  dot(7, HEAD_Y + 1, 2.2, INK, 1)
  dot(-6.3, HEAD_Y + 0.3, 0.8, WHITE, 1)
  dot(7.7, HEAD_Y + 0.3, 0.8, WHITE, 1)
  line(INK, 1, 2, -11, HEAD_Y - 5, -4, HEAD_Y - 6) -- brows, one raised
  line(INK, 1, 2, 4, HEAD_Y - 7, 11, HEAD_Y - 4)
  line(INK, 1, 2, -5, HEAD_Y + 10, 1, HEAD_Y + 11, 6, HEAD_Y + 9) -- a lopsided grin
end

local function hair(sk)
  ellipse(0, HEAD_Y - 6, HEAD_R + 1, HEAD_R - 4, sk.hair, "arc")
end

--- Arms: sleeves in `sleeve` down to `cuff`, bare skin below, hands.
local function arms(sk, sleeve, cuff)
  for _, x in ipairs({ -40, 26 }) do
    box(x + 1, 52, 12, 64, sk.skin, 5) -- the arm
    box(x, 48, 14, cuff - 48, sleeve, 5) -- the sleeve over it
    ellipse(x + 7, 118, 7, 7, sk.skin) -- the hand
  end
end

local function torso(c)
  box(-26, 44, 52, 74, c, 9)
end

local function legs(c, bottom)
  bottom = bottom or 192
  box(-21, 108, 18, bottom - 108, c, 4)
  box(3, 108, 18, bottom - 108, c, 4)
  box(-24, 106, 48, 14, c, 4) -- the seat, joining them
end

--- Shoes at the feet, `top` how far up the leg they come (190 for a shoe,
--- 150 or so for a tall boot).
local function shoes(c, top, sole)
  top = top or 186
  for _, x in ipairs({ -24, 2 }) do
    box(x + 2, top, 18, 196 - top, c, 3) -- the upper
    box(x, 193, 22, 7, sole or RUBBER, 2) -- the sole
  end
end

-- What the pieces add ---------------------------------------------------------

local HEAD = {
  ["tactical-hat"] = function(c)
    ellipse(0, HEAD_Y - 8, HEAD_R + 2, 12, c, "arc")
    box(-HEAD_R - 2, HEAD_Y - 10, (HEAD_R + 2) * 2, 5, c, 2) -- band
    ellipse(0, HEAD_Y - 5, 16, 4, lit(c, 0.1)) -- the peak, towards us
    box(-4, HEAD_Y - 18, 8, 5, lit(c, 0.3), 1) -- a patch
  end,
  ["crash-helmet"] = function(c)
    ellipse(0, HEAD_Y, HEAD_R + 5, HEAD_R + 6, c) -- all of the head
    box(-15, HEAD_Y - 6, 30, 12, RUBBER, 5) -- the visor
    set(WHITE, 1, 0.7)
    love.graphics.polygon("fill", -11, HEAD_Y - 4, -6, HEAD_Y - 4, -11, HEAD_Y + 3)
    strokes(c, 0.55, 3, -5, HEAD_Y + 14, 5, 3, true) -- the chin vents
  end,
  ["riot-helmet"] = function(c)
    ellipse(0, HEAD_Y - 2, HEAD_R + 4, HEAD_R + 2, c, "arc")
    box(-HEAD_R - 4, HEAD_Y - 4, (HEAD_R + 4) * 2, 4, c, 1) -- rim
    set(GLASS, 1, 0.35)
    love.graphics.rectangle("fill", -HEAD_R - 2, HEAD_Y - 1, (HEAD_R + 2) * 2, 22, 5) -- the face shield
    set(WHITE, 1, 0.5)
    love.graphics.setLineWidth(Shade.pixel() * 1.5)
    love.graphics.line(-14, HEAD_Y + 2, -9, HEAD_Y + 17)
  end,
  ["welding-mask"] = function(c)
    line(RUBBER, 1, 3, -HEAD_R - 1, HEAD_Y - 10, HEAD_R + 1, HEAD_Y - 10) -- headband
    box(-17, HEAD_Y - 14, 34, 40, c, 7) -- the mask, all of the face
    box(-12, HEAD_Y - 4, 24, 8, RUBBER, 1.5) -- the lens
    set(GLASS, 1, 0.6)
    love.graphics.rectangle("fill", -10, HEAD_Y - 3, 6, 1.5)
    strokes(c, 0.55, 3, -4, HEAD_Y + 12, 4, 6, true) -- vents
  end,
  ["ballistic-helmet"] = function(c)
    ellipse(0, HEAD_Y - 4, HEAD_R + 4, HEAD_R + 1, c, "arc")
    box(-HEAD_R - 5, HEAD_Y - 6, (HEAD_R + 5) * 2, 4, c, 1) -- rim
    box(-5, HEAD_Y - 24, 10, 6, RUBBER, 1) -- night-vision mount
    for _, d in ipairs({ { -9, -14 }, { 6, -18 }, { 11, -10 }, { -2, -10 } }) do -- camouflage
      set(c, 0.7)
      love.graphics.ellipse("fill", d[1], HEAD_Y + d[2], 3.5, 2.2)
    end
    line(RUBBER, 1, 2, -HEAD_R + 1, HEAD_Y - 2, -12, HEAD_Y + 18, 12, HEAD_Y + 18, HEAD_R - 1, HEAD_Y - 2)
  end,
}
local PLAIN_HEAD = HEAD["tactical-hat"]

-- A jacket: the body and full sleeves in its colour, then what makes it itself.
local function jacket(sk, c)
  arms(sk, c, 112)
  box(-27, 43, 54, 76, c, 9)
end

local BODY = {
  ["plate-carrier"] = function(_, c) -- over a shirt (Figure.draw puts one on)
    box(-19, 40, 8, 16, c, 2) -- shoulder straps
    box(11, 40, 8, 16, c, 2)
    box(-24, 52, 48, 52, c, 5) -- the carrier
    box(-17, 57, 34, 22, c, 3) -- the plate pocket
    for i = 0, 2 do -- pouches along the bottom
      box(-21 + i * 15, 84, 12, 16, c, 2)
    end
  end,
  ["fire-jacket"] = function(sk, c)
    jacket(sk, c)
    box(-27, 80, 54, 6, HIVIS, 0) -- reflective bands
    box(-27, 90, 54, 4, SILVER, 0)
    for _, x in ipairs({ -40, 26 }) do
      box(x, 98, 14, 4, SILVER, 0)
    end
    box(-9, 40, 18, 10, c, 3) -- the high collar
    line(c, 0.45, 1.5, 0, 50, 0, 118) -- zip
  end,
  ["leather-jacket"] = function(sk, c)
    jacket(sk, c)
    poly(lit(c, 0.15), -24, 45, -6, 45, -11, 72) -- lapels
    poly(lit(c, 0.15), 24, 45, 6, 45, 11, 72)
    line(STEEL, 1, 1.5, -6, 55, 8, 116) -- the zip, across
    box(-27, 108, 54, 7, c, 1) -- belt at the hem
    box(-4, 108.5, 8, 6, STEEL, 1) -- its buckle
  end,
  ["lineman-jacket"] = function(sk, c)
    jacket(sk, c)
    box(-27, 70, 54, 5, SILVER, 0)
    box(-27, 94, 54, 5, SILVER, 0)
    for _, x in ipairs({ -40, 26 }) do
      box(x, 92, 14, 4, SILVER, 0)
    end
    poly(RUBBER, 4, 50, -6, 62, 1, 62) -- a lightning bolt
    poly(RUBBER, -1, 60, 7, 60, -5, 76)
  end,
  ["puffer-jacket"] = function(sk, c)
    arms(sk, c, 112)
    for i = 0, 6 do -- quilted all over, each band puffed up
      box(-28, 44 + i * 10.6, 56, 10.8, c, 5)
    end
    for i = 0, 5 do
      box(-41, 48 + i * 10.6, 15, 10.8, c, 5)
      box(26, 48 + i * 10.6, 15, 10.8, c, 5)
    end
    box(-14, 38, 28, 10, c, 5) -- the hood, rolled into a collar
    line(c, 0.45, 1.5, 0, 48, 0, 118)
  end,
}
local function plainBody(sk, c)
  jacket(sk, c)
end

--- Trousers, as far as the waist (PANTS_TOP adds a bib and braces over
--- the shirt, under any jacket).
local PANTS = {
  ["cargo-pants"] = function(c)
    legs(c)
    box(-23, 136, 9, 16, c, 2) -- side pockets
    box(14, 136, 9, 16, c, 2)
  end,
  ["kevlar-trousers"] = function(c)
    legs(c)
    box(-20, 140, 16, 14, RUBBER, 4) -- knee pads
    box(4, 140, 16, 14, RUBBER, 4)
  end,
  ["fireproof-overalls"] = function(c)
    legs(c)
    box(-21, 170, 18, 5, SILVER, 0) -- reflective bands at the shins
    box(3, 170, 18, 5, SILVER, 0)
  end,
  ["biker-leathers"] = function(c)
    legs(c)
    box(-20, 138, 16, 16, lit(c, 0.2), 6) -- knee armour
    box(4, 138, 16, 16, lit(c, 0.2), 6)
    line(STEEL, 0.9, 1, -21, 112, -21, 190) -- stitching down the sides
    line(STEEL, 0.9, 1, 21, 112, 21, 190)
  end,
  ["rubber-waders"] = function(c)
    legs(c, 170)
    shoes(RUBBER, 166) -- the boots, all one piece
  end,
}

local PANTS_TOP = {
  ["fireproof-overalls"] = function(c)
    box(-16, 44, 6, 40, c, 1) -- braces
    box(10, 44, 6, 40, c, 1)
    box(-18, 78, 36, 32, c, 3) -- the bib
    dot(-13, 80, 2, STEEL, 1)
    dot(13, 80, 2, STEEL, 1)
  end,
  ["rubber-waders"] = function(c)
    box(-14, 44, 4, 44, RUBBER, 1) -- braces
    box(10, 44, 4, 44, RUBBER, 1)
    box(-18, 80, 36, 30, c, 3) -- the bib
  end,
}
local function plainPants(c)
  legs(c)
end

--- Footwear: `top` is how far up the leg it comes.
local SHOES_BY = {
  ["running-shoes"] = function(c)
    shoes(c, 184, WHITE)
    for _, x in ipairs({ -24, 2 }) do
      line(WHITE, 1, 2, x + 5, 191, x + 17, 186)
    end
  end,
  ["rubber-boots"] = function(c)
    shoes(c, 150)
    for _, x in ipairs({ -24, 2 }) do
      box(x + 1, 148, 20, 5, lit(c, 0.2), 2)
    end
  end,
  ["steel-toe-boots"] = function(c)
    shoes(c, 172)
    for _, x in ipairs({ -24, 2 }) do
      ellipse(x + 11, 190, 8, 4, STEEL)
      strokes(lit(c, 0.3), 1, 3, x + 7, 175, 4, 8)
    end
  end,
  ["combat-boots"] = function(c)
    shoes(c, 152)
    for _, x in ipairs({ -24, 2 }) do
      strokes(RUBBER, 1, 8, x + 6, 155, 4.5, 10)
    end
  end,
  ["fireproof-boots"] = function(c)
    shoes(c, 150)
    for _, x in ipairs({ -24, 2 }) do
      box(x + 2, 166, 18, 5, SILVER, 0)
    end
  end,
}

--- Armor over everything, and what it adds round the head (a hood, a neck guard).
local ARMOR = {
  vest = function(c)
    box(-19, 42, 8, 14, c, 2)
    box(11, 42, 8, 14, c, 2)
    box(-25, 50, 50, 56, c, 6)
    box(-17, 60, 34, 16, lit(c, 0.2), 2) -- velcro panel
    box(-25, 94, 50, 7, RUBBER, 1) -- waist straps
    box(-4, 94, 8, 7, STEEL, 1)
  end,
  ["bomb-suit"] = function(c)
    ellipse(-28, 52, 12, 10, c) -- bulky shoulders
    ellipse(28, 52, 12, 10, c)
    box(-31, 46, 62, 66, c, 10)
    strokes(c, 0.6, 4, -30, 60, 12, 60) -- padded segments
    box(-14, 108, 28, 22, c, 5) -- the groin flap
    box(-17, 34, 34, 18, c, 7) -- the neck guard, up to the chin
  end,
  ["riot-armor"] = function(c)
    box(-25, 46, 50, 64, c, 6)
    box(-19, 52, 38, 30, lit(c, 0.25), 8) -- the chest plate
    line(c, 0.5, 1.5, 0, 54, 0, 80)
    for i = 0, 2 do -- pauldrons, in plates
      box(-42, 44 + i * 8, 18, 9, lit(c, 0.15), 3)
      box(24, 44 + i * 8, 18, 9, lit(c, 0.15), 3)
    end
    strokes(c, 0.55, 3, -24, 88, 7, 48)
  end,
  ["insulated-suit"] = function(c)
    box(-28, 44, 56, 72, c, 9)
    for _, x in ipairs({ -41, 26 }) do
      box(x, 48, 15, 64, c, 5) -- sleeves
      ellipse(x + 7.5, 118, 8, 8, RUBBER) -- rubber gloves
    end
    line(RUBBER, 1, 3, 0, 48, 0, 116) -- the taped zip
  end,
  ["ceramic-plates"] = function(c)
    box(-19, 40, 8, 16, c, 2)
    box(11, 40, 8, 16, c, 2)
    box(-25, 50, 50, 58, c, 6)
    box(-18, 54, 36, 34, { 0.88, 0.86, 0.8 }, 4) -- the big front plate
    line({ 0.88, 0.86, 0.8 }, 0.75, 1.5, -18, 71, 18, 71)
    box(-26, 92, 52, 14, c, 2) -- cummerbund
    strokes(RUBBER, 1, 4, -22, 95, 3, 44)
  end,
}

--- The hood of an insulated suit, behind the head.
local function hood(c)
  ellipse(0, HEAD_Y + 2, HEAD_R + 7, HEAD_R + 8, c)
end

--- The hood of an insulated suit, behind the big head.
local function bigHood(c, scale)
  local k = bigPixel(scale)
  ellipse(0, BIG_CHIN - (70 - BIG_FACE_ROW) * k + 2, (HEAD_R + 7) * BIG_SX * k, (HEAD_R + 8) * BIG_SY * k, c)
end

--- `key` of a piece in `kinds`, its colour (grey for nothing known).
local function colorOf(kinds, key)
  local k = key and kinds.byKey[key]
  return k and k.color or { 0.6, 0.6, 0.65 }
end

--- The menu face's picture on the neck, its chin at the neck's top, a whole
--- number of screen pixels to its pixel.
local function bigHead(face, scale)
  -- The face paints its picture under whatever transform is on: none, then.
  love.graphics.push()
  love.graphics.origin()
  local canvas = face:render()
  love.graphics.pop()
  local k = bigPixel(scale)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, -Face.W / 2 * k, BIG_CHIN - 70 * k, 0, k, k)
end

--- Draw the character with the top of its head at (cx, top), `scale` times
--- `Figure.height(face)` tall. `dress` says what they wear, every field
--- optional: head, body, pants, shoes (clothes keys), armor (an armor key),
--- gun (a gun key for the right hand). `face`: the menu face to give them.
function Figure.draw(cx, top, scale, dress, face)
  dress = dress or {}
  local sk = SKINS[Face.inclusive() and 2 or 1]
  Shade.begin(scale)
  love.graphics.push()
  love.graphics.translate(cx, top)
  love.graphics.scale(scale)
  if face then
    love.graphics.translate(0, BIG_HEADROOM) -- the hair's room over the top
  end
  -- Shadow underfoot.
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 0, 200, 40, 9)
  -- Back to front: legs and feet, a shirt (unless a jacket covers it), the
  -- bib of overalls, the jacket, the armor.
  local pantsKey, bodyKey = dress.pants, dress.body
  local pantsColor = colorOf(GearKinds, pantsKey)
  if pantsKey then
    (PANTS[pantsKey] or plainPants)(pantsColor)
  else
    legs(TROUSERS)
  end
  if pantsKey ~= "rubber-waders" then -- waders bring their own boots
    if dress.shoes then
      (SHOES_BY[dress.shoes] or shoes)(colorOf(GearKinds, dress.shoes))
    else
      shoes(SHOES)
    end
  end
  if not bodyKey or bodyKey == "plate-carrier" then
    arms(sk, SHIRT, 76)
    torso(SHIRT)
  end
  if PANTS_TOP[pantsKey] then
    PANTS_TOP[pantsKey](pantsColor)
  end
  if bodyKey then
    (BODY[bodyKey] or plainBody)(sk, colorOf(GearKinds, bodyKey))
  end
  if dress.armor == "insulated-suit" then
    (face and bigHood or hood)(colorOf(ArmorKinds, dress.armor), scale)
  end
  if dress.armor then
    (ARMOR[dress.armor] or ARMOR.vest)(colorOf(ArmorKinds, dress.armor))
  end
  -- The head, and what is on it.
  local wear = dress.head and (HEAD[dress.head] or PLAIN_HEAD)
  if face then
    box(-6, 38, 12, 10, sk.skin, 2) -- neck
    bigHead(face, scale)
    if wear then
      -- Headwear made for the small head, stretched over the big one.
      local k = bigPixel(scale)
      love.graphics.push()
      love.graphics.translate(0, BIG_CHIN - (70 - BIG_FACE_ROW) * k)
      love.graphics.scale(BIG_SX * k, BIG_SY * k)
      love.graphics.translate(0, -HEAD_Y)
      Shade.begin(scale * BIG_SX * k)
      wear(colorOf(GearKinds, dress.head))
      Shade.begin(scale)
      love.graphics.pop()
    end
  else
    head(sk)
    local covered = dress.head == "crash-helmet" or dress.head == "welding-mask"
    if not covered then
      drawFace()
    end
    if wear then
      wear(colorOf(GearKinds, dress.head))
    elseif dress.armor ~= "insulated-suit" then
      hair(sk)
    end
  end
  love.graphics.pop()
  -- The gun in hand, held out in the right hand.
  if dress.gun then
    local down = face and BIG_HEADROOM or 0
    GunIcons.draw(dress.gun, cx + 40 * scale, top + (112 + down) * scale, 0.65 * scale)
  end
  Shade.finish()
end

return Figure
