-- The two faces of the Borderline quest line (docs/borderline.md, "The
-- cast"), for Jerry's intro screen and the comms panel. Each is drawn with
-- primitives onto a 64x72 canvas and scaled up with nearest filtering, the
-- way VEX's (cyber-feud/face.lua) and the Mood Slayer's are.
--
--   jerry  Handsome Jerry on a Hyperbole broadcast card: a yellow border, a
--          LIVE dot, a swept brown quiff, a mask a shade too pale and too
--          smooth clipped on at the temples with its seam showing at the
--          jaw, one blue eye and one green behind it, a big white grin that
--          never moves, a yellow suit, green shirt, thin dark tie. He talks
--          with his eyebrows, and now and then leans into the camera.
--   yappy  YAP-TP, whose face is his whole body: a yellow box, a big blue
--          eye with a shutter that blinks, a vent of a mouth that flickers
--          when he talks, an antenna, two stick arms that wave about. His
--          eye goes big when he is excited.
--
--   Faces.new(who)  -> face; face:update(dt); face:draw(x, y, scale)
--   face.talking    set while the words are still typing out

local Pixel = require("src.art.pixel")

local Faces = {}
Faces.__index = Faces

Faces.W, Faces.H = 64, 72

local C = {
  card = { 0.12, 0.13, 0.15 },
  cardLine = { 0.18, 0.19, 0.22 },
  yellow = { 0.95, 0.76, 0.19 },
  yellowDark = { 0.74, 0.55, 0.10 },
  live = { 1.00, 0.20, 0.20 },
  hair = { 0.42, 0.27, 0.15 },
  hairHi = { 0.62, 0.42, 0.24 },
  mask = { 0.93, 0.86, 0.80 },
  maskShade = { 0.82, 0.74, 0.68 },
  skin = { 0.78, 0.60, 0.48 },
  clip = { 0.55, 0.58, 0.62 },
  ink = { 0.08, 0.08, 0.09 },
  white = { 1, 1, 1 },
  blue = { 0.25, 0.55, 1.00 },
  green = { 0.30, 0.80, 0.35 },
  brow = { 0.30, 0.19, 0.10 },
  shirt = { 0.25, 0.55, 0.30 },
  tie = { 0.12, 0.14, 0.16 },
  gunmetal = { 0.23, 0.25, 0.28 },
  eye = { 0.35, 0.75, 1.00 },
  eyeHot = { 0.85, 0.95, 1.00 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

function Faces.new(who)
  local self = setmetatable({}, Faces)
  self.who = who
  self.canvas = Pixel.canvas(Faces.W, Faces.H)
  self.t = 0
  self.blink, self.blinkIn = 0, 2
  self.lean, self.leanIn = 0, 6 -- Jerry leaning into the camera
  self.talking = false
  return self
end

function Faces:update(dt)
  self.t = self.t + dt
  self.blinkIn = self.blinkIn - dt
  if self.blinkIn <= 0 then
    self.blink, self.blinkIn = 0.15, 2 + love.math.random() * 3
  end
  self.blink = math.max(0, self.blink - dt)
  self.leanIn = self.leanIn - dt
  if self.leanIn <= 0 then
    self.lean, self.leanIn = 1.4, 6 + love.math.random() * 6
  end
  self.lean = math.max(0, self.lean - dt)
end

-- Jerry ---------------------------------------------------------------------

local function drawJerry(self)
  -- The broadcast card behind him.
  color(C.card)
  rect(0, 0, 64, 72)
  color(C.cardLine)
  for y = 2, 70, 4 do
    rect(2, y, 60, 1)
  end
  color(C.yellow)
  rect(0, 0, 64, 2)
  rect(0, 70, 64, 2)
  rect(0, 0, 2, 72)
  rect(62, 0, 2, 72)
  if math.floor(self.t * 2) % 2 == 0 then
    color(C.live)
    rect(5, 5, 3, 3)
  end
  color(C.yellow) -- the logo: an H in the corner
  rect(54, 4, 1, 5)
  rect(57, 4, 1, 5)
  rect(55, 6, 2, 1)
  -- The suit: yellow jacket, green shirt, the tie.
  color(C.yellowDark)
  rect(6, 56, 52, 16)
  color(C.yellow)
  rect(8, 55, 48, 17)
  color(C.shirt)
  rect(26, 55, 12, 17)
  color(C.tie)
  rect(30, 57, 4, 15)
  color(C.yellowDark) -- lapels
  rect(22, 56, 4, 14)
  rect(38, 56, 4, 14)
  -- The neck under the mask: his own skin.
  color(C.skin)
  rect(26, 48, 12, 8)
  -- The mask.
  color(C.maskShade)
  rect(17, 15, 30, 35)
  color(C.mask)
  rect(18, 14, 28, 34)
  rect(20, 47, 24, 3) -- the square chin
  color(C.maskShade) -- the seam at the jaw
  rect(19, 45, 26, 1)
  color(C.clip) -- the clips at the temples
  rect(16, 24, 2, 4)
  rect(46, 24, 2, 4)
  -- The quiff, swept up and over.
  color(C.hair)
  rect(16, 6, 32, 10)
  rect(20, 3, 26, 5)
  rect(40, 1, 8, 4)
  color(C.hairHi)
  rect(24, 4, 14, 2)
  rect(42, 2, 4, 1)
  -- Eyebrows: he talks with them.
  local up = self.talking and math.floor(math.abs(math.sin(self.t * 9)) * 2.5) or 0
  color(C.brow)
  rect(22, 21 - up, 8, 2)
  rect(34, 21 - up, 8, 2)
  -- The eye holes, and behind them one blue eye and one green.
  color(C.ink)
  rect(22, 25, 8, 5)
  rect(34, 25, 8, 5)
  if self.blink <= 0 then
    color(C.white)
    rect(23, 26, 6, 3)
    rect(35, 26, 6, 3)
    color(C.blue)
    rect(25, 26, 3, 3)
    color(C.green)
    rect(37, 26, 3, 3)
  end
  -- The grin: big, white, never moving.
  color(C.ink)
  rect(22, 36, 20, 7)
  color(C.white)
  rect(23, 37, 18, 4)
  color(C.maskShade)
  for x = 26, 38, 3 do
    rect(x, 37, 1, 4)
  end
end

-- Yappy ---------------------------------------------------------------------

local function drawYappy(self)
  local bob = math.floor(math.sin(self.t * (self.talking and 10 or 3)) * 1.5 + 0.5)
  -- The antenna, a light on top.
  color(C.ink)
  rect(31, 4 + bob, 2, 10)
  color(self.talking and C.eyeHot or C.eye)
  rect(29, 2 + bob, 6, 4)
  -- Stick arms, waving while he talks.
  local wave = self.talking and math.floor(math.sin(self.t * 12) * 4) or 0
  color(C.ink)
  love.graphics.setLineWidth(2)
  love.graphics.line(10, 40 + bob, 3, 30 + bob - wave)
  love.graphics.line(54, 40 + bob, 61, 30 + bob + wave)
  love.graphics.setLineWidth(1)
  -- The box.
  color(C.ink)
  rect(9, 13 + bob, 46, 46)
  color(C.yellow)
  rect(10, 14 + bob, 44, 44)
  color(C.yellowDark)
  rect(10, 54 + bob, 44, 4)
  -- The eye: nearly all of him.
  local big = self.talking and 2 or 0
  color(C.gunmetal)
  rect(16 - big, 18 + bob - big, 32 + 2 * big, 24 + 2 * big)
  color(C.eye)
  rect(19 - big, 21 + bob - big, 26 + 2 * big, 18 + 2 * big)
  color(C.eyeHot)
  rect(28, 26 + bob, 8, 7)
  color(C.white)
  rect(30, 27 + bob, 3, 2)
  if self.blink > 0 then -- the shutter
    color(C.gunmetal)
    rect(16 - big, 18 + bob - big, 32 + 2 * big, 24 + 2 * big)
  end
  -- The vent of a mouth: lit while he talks.
  for k = 0, 3 do
    local lit = self.talking and math.sin(self.t * 25 + k) > 0
    color(lit and C.eye or C.ink)
    rect(22 + k * 5, 46 + bob, 3, 5)
  end
  -- The wheel under him.
  color(C.ink)
  rect(26, 59 + bob, 12, 10)
  color(C.gunmetal)
  rect(27, 60 + bob, 10, 8)
end

function Faces:render()
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  if self.who == "jerry" then
    drawJerry(self)
  else
    drawYappy(self)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel. Jerry
--- leaning into the camera comes a little bigger for a moment.
function Faces:draw(x, y, scale)
  local canvas = self:render()
  local lean = self.who == "jerry" and math.sin(math.min(1, self.lean / 1.4) * math.pi) * 0.12 or 0
  local s = scale * (1 + lean)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, x - Faces.W / 2 * s, y - Faces.H / 2 * s, 0, s, s)
end

return Faces
