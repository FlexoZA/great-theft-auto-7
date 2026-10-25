-- The two faces of the Borderline quest line (docs/borderline.md, "The
-- cast"), for Max's intro screen and the comms panel. Each is drawn with
-- primitives onto a 64x72 canvas and scaled up with nearest filtering, the
-- way VEX's (cyber-feud/face.lua) and the Mood Slayer's are.
--
--   max    Maximum Maximilian Max on a Hyperbole broadcast card: a yellow
--          border, a LIVE dot, a tall blond flat-top, a red sweatband,
--          wraparound shades a glint sweeps across, a lantern jaw with a
--          cleft, a wide white grin, a yellow muscle shirt, a gold chain
--          with an M on it, and one arm flexed up beside his head. Talking,
--          his grin opens to a shout, his brows bounce and he pumps the
--          arm; now and then he leans into the camera.
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
  blond = { 0.98, 0.86, 0.45 },
  blondHi = { 1.00, 0.95, 0.70 },
  blondShade = { 0.78, 0.62, 0.25 },
  tan = { 0.86, 0.60, 0.40 },
  tanHi = { 0.96, 0.74, 0.54 },
  tanShade = { 0.66, 0.42, 0.26 },
  red = { 0.90, 0.18, 0.16 },
  lens = { 0.16, 0.30, 0.42 },
  mouth = { 0.45, 0.10, 0.12 },
  gold = { 1.00, 0.80, 0.20 },
  goldDark = { 0.70, 0.50, 0.08 },
  ink = { 0.08, 0.08, 0.09 },
  white = { 1, 1, 1 },
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
  self.lean, self.leanIn = 0, 6 -- Max leaning into the camera
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

-- Max -----------------------------------------------------------------------

local function drawMax(self)
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
  color(C.yellow) -- the logo: an H by the LIVE dot
  rect(10, 4, 1, 5)
  rect(13, 4, 1, 5)
  rect(11, 6, 2, 1)
  -- He pumps the flexed arm while he talks.
  local pump = self.talking and math.floor(math.abs(math.sin(self.t * 7)) * 2 + 0.5) or 0
  -- Shoulders and traps, bare: a yellow muscle shirt cut deep.
  color(C.tanShade)
  rect(6, 54, 52, 18)
  color(C.tan)
  rect(8, 53, 48, 19)
  rect(14, 50, 36, 4)
  color(C.yellowDark)
  rect(17, 56, 30, 16)
  color(C.yellow)
  rect(18, 57, 28, 15)
  color(C.tan) -- the neckline, cut low
  rect(26, 57, 12, 3)
  rect(28, 60, 8, 2)
  -- The flexed arm, his left, up in the frame's right: upper arm out from
  -- the shoulder, forearm up, the fist by his ear, the bicep bulging.
  color(C.tanShade)
  rect(48, 47 - pump, 12, 9)
  rect(54, 30 - pump, 7, 19)
  color(C.tan)
  rect(48, 48 - pump, 11, 7)
  rect(55, 31 - pump, 5, 18)
  rect(49, 44 - pump, 7, 5) -- the bicep
  color(C.tanHi)
  rect(50, 45 - pump, 4, 1)
  color(C.tanShade) -- the fist, knuckles to him
  rect(53, 24 - pump, 9, 8)
  color(C.tan)
  rect(54, 25 - pump, 7, 6)
  color(C.tanShade)
  for y = 26, 30, 2 do
    rect(54, y - pump, 4, 1)
  end
  color(C.red) -- a sweatband on the wrist
  rect(54, 32 - pump, 7, 2)
  -- The thick neck.
  color(C.tanShade)
  rect(24, 44, 16, 9)
  color(C.tan)
  rect(25, 44, 14, 9)
  -- The head: a lantern jaw, wider at the bottom.
  color(C.tanShade)
  rect(19, 14, 26, 31)
  rect(20, 44, 24, 4)
  color(C.tan)
  rect(20, 14, 24, 30)
  rect(21, 44, 22, 3)
  color(C.tanShade) -- the jawline, and the cleft in the chin
  rect(21, 47, 22, 1)
  rect(31, 45, 2, 2)
  rect(18, 26, 2, 5) -- ears
  rect(44, 26, 2, 5)
  -- The flat-top: blond, tall, square, the tallest hair on Pandoria.
  color(C.blondShade)
  rect(18, 2, 28, 15)
  color(C.blond)
  rect(19, 2, 26, 14)
  color(C.blondHi)
  for x = 21, 43, 4 do
    rect(x, 3, 1, 11)
  end
  rect(19, 2, 26, 1)
  -- The sweatband across the brow.
  color(C.red)
  rect(19, 15, 26, 3)
  color(C.white)
  rect(30, 16, 4, 1)
  -- Brows over the shades: he talks with them too.
  local up = self.talking and math.floor(math.abs(math.sin(self.t * 9)) * 2.5) or 0
  color(C.blondShade)
  rect(21, 21 - up, 9, 2)
  rect(34, 21 - up, 9, 2)
  -- Wraparound shades, a glint sweeping across them now and then.
  color(C.ink)
  rect(19, 24, 26, 6)
  rect(31, 24, 2, 3)
  color(C.lens)
  rect(21, 25, 9, 4)
  rect(34, 25, 9, 4)
  local glint = math.floor((self.t * 30) % 90)
  if glint < 26 then
    color(C.white)
    rect(19 + glint, 25, 2, 1)
    rect(18 + glint, 26, 2, 1)
  end
  -- The nose.
  color(C.tanShade)
  rect(31, 30, 3, 5)
  rect(30, 34, 5, 1)
  -- The grin, wide; it opens to a shout while he talks.
  local open = self.talking and math.floor(self.t * 8) % 2 == 0
  color(C.ink)
  rect(22, 37, 20, open and 8 or 5)
  color(C.white)
  rect(23, 38, 18, 3)
  if open then
    color(C.mouth)
    rect(25, 41, 14, 3)
    color(C.white)
    rect(24, 44, 16, 1)
  end
  color(C.tanShade)
  rect(21, 36, 1, 2) -- dimples
  rect(42, 36, 1, 2)
  -- The gold chain and its medallion: an M.
  color(C.goldDark)
  for i = 0, 5 do
    rect(25 + i, 53 + i, 1, 1)
    rect(37 - i, 53 + i, 1, 1)
  end
  color(C.gold)
  rect(28, 59, 7, 6)
  color(C.goldDark)
  rect(29, 60, 1, 4)
  rect(33, 60, 1, 4)
  rect(30, 61, 1, 1)
  rect(31, 62, 1, 1)
  rect(32, 61, 1, 1)
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
  if self.who == "max" then
    drawMax(self)
  else
    drawYappy(self)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel. Max
--- leaning into the camera comes a little bigger for a moment.
function Faces:draw(x, y, scale)
  local canvas = self:render()
  local lean = self.who == "max" and math.sin(math.min(1, self.lean / 1.4) * math.pi) * 0.12 or 0
  local s = scale * (1 + lean)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, x - Faces.W / 2 * s, y - Faces.H / 2 * s, 0, s, s)
end

return Faces
