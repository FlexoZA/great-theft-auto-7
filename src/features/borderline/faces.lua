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
--   yappy  YAP-TP, a young woman on a comms headset: auburn hair with a
--          side-swept fringe and a ponytail that swings, blue eyes that
--          blink, a blue parka zipped up to its fur collar, the mic's light
--          lit while she talks. Her brows go up and her mouth moves as the
--          words type out.
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
  hairF = { 0.62, 0.27, 0.15 },
  hairFHi = { 0.80, 0.42, 0.24 },
  hairShade = { 0.40, 0.16, 0.09 },
  skinF = { 0.94, 0.78, 0.65 },
  skinFShade = { 0.82, 0.63, 0.51 },
  iris = { 0.25, 0.55, 0.85 },
  lip = { 0.74, 0.34, 0.36 },
  blush = { 0.92, 0.55, 0.52 },
  parka = { 0.22, 0.44, 0.72 },
  parkaDark = { 0.13, 0.28, 0.50 },
  fur = { 0.92, 0.88, 0.80 },
  furShade = { 0.74, 0.70, 0.62 },
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
  local bob = math.floor(math.sin(self.t * (self.talking and 6 or 2)) * 0.8 + 0.5)
  local sway = math.floor(math.sin(self.t * 2.5) * 1.5 + 0.5)
  -- The ponytail behind her head, swinging.
  color(C.hairShade)
  rect(42 + sway, 20 + bob, 7, 22)
  rect(44 + sway, 40 + bob, 5, 6)
  -- The parka: blue, zipped up, a fur-lined collar.
  color(C.parkaDark)
  rect(6, 56 + bob, 52, 16)
  color(C.parka)
  rect(8, 55 + bob, 48, 17)
  color(C.parkaDark)
  rect(31, 58 + bob, 2, 14) -- the zip
  rect(14, 62 + bob, 1, 10)
  rect(49, 62 + bob, 1, 10)
  color(C.furShade)
  rect(17, 51 + bob, 30, 7)
  color(C.fur)
  rect(18, 51 + bob, 28, 5)
  for x = 19, 44, 3 do
    color(C.furShade)
    rect(x, 55 + bob, 1, 2)
  end
  -- The neck.
  color(C.skinFShade)
  rect(27, 45 + bob, 10, 7)
  -- The face, narrowing to the chin.
  color(C.skinF)
  rect(20, 16 + bob, 24, 28)
  rect(22, 44 + bob, 20, 2)
  rect(25, 46 + bob, 14, 2)
  color(C.skinFShade)
  rect(42, 18 + bob, 2, 25)
  rect(31, 32 + bob, 2, 4) -- the nose's shadow
  color(C.blush, 0.6)
  rect(22, 35 + bob, 4, 2)
  rect(38, 35 + bob, 4, 2)
  -- Hair: auburn, a side-swept fringe, falling down both sides.
  color(C.hairShade)
  rect(17, 10 + bob, 30, 8)
  rect(17, 16 + bob, 4, 18)
  rect(43, 16 + bob, 4, 16)
  color(C.hairF)
  rect(19, 8 + bob, 26, 8)
  rect(19, 15 + bob, 16, 4)
  rect(19, 18 + bob, 9, 3)
  rect(19, 20 + bob, 3, 6)
  color(C.hairFHi)
  rect(24, 9 + bob, 12, 2)
  rect(21, 15 + bob, 8, 1)
  -- The headset she talks to you through: band, ear cup, mic boom.
  color(C.ink)
  rect(18, 9 + bob, 28, 1)
  rect(17, 10 + bob, 1, 16)
  color(C.gunmetal)
  rect(14, 24 + bob, 5, 9)
  love.graphics.setLineWidth(1)
  color(C.ink)
  love.graphics.line(17, 32 + bob, 25, 40 + bob)
  color(self.talking and C.eyeHot or C.eye)
  rect(25, 39 + bob, 2, 2)
  -- Eyebrows, up while she talks.
  local up = self.talking and math.floor(math.abs(math.sin(self.t * 7)) * 2 + 0.5) or 0
  color(C.hairShade)
  rect(23, 24 + bob - up, 7, 1)
  rect(34, 24 + bob - up, 7, 1)
  -- Eyes: blue, lashes on top.
  if self.blink > 0 then
    color(C.ink)
    rect(23, 29 + bob, 7, 1)
    rect(34, 29 + bob, 7, 1)
  else
    color(C.white)
    rect(24, 27 + bob, 5, 3)
    rect(35, 27 + bob, 5, 3)
    color(C.iris)
    rect(25, 27 + bob, 3, 3)
    rect(36, 27 + bob, 3, 3)
    color(C.ink)
    rect(26, 28 + bob, 1, 1)
    rect(37, 28 + bob, 1, 1)
    rect(23, 26 + bob, 7, 1)
    rect(34, 26 + bob, 7, 1)
    color(C.white)
    rect(25, 27 + bob, 1, 1)
    rect(36, 27 + bob, 1, 1)
  end
  -- The mouth: a smile at rest, open and shut while she talks.
  local open = self.talking and math.floor((math.sin(self.t * 22) + 1) * 1.5) or 0
  if open > 0 then
    color(C.ink)
    rect(28, 39 + bob, 8, open + 1)
    color(C.lip)
    rect(28, 38 + bob, 8, 1)
    rect(28, 40 + bob + open, 8, 1)
  else
    color(C.lip)
    rect(28, 39 + bob, 8, 2)
    rect(27, 38 + bob, 1, 1)
    rect(36, 38 + bob, 1, 1)
  end
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
