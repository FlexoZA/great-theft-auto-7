-- Shoeman's portrait for the tutorial's comms panel (docs/tutorial.md,
-- "Cast"). Drawn with primitives onto a 64x72 canvas and scaled up with
-- nearest filtering, the way the Borderline faces are (borderline/faces.lua).
--
-- A big bald man in front of a school chalkboard with a shoe chalked on it:
-- a wide shiny head, bushy grey eyebrows pulled down in a scowl, small hard
-- eyes, a red nose, stubble, a double chin, a thick neck and a navy t-shirt
-- stretched over heavy shoulders. Talking, his mouth opens and shuts and his
-- brows bounce; shouting (the "DODGE!!!!" before a throw) his face goes red,
-- a vein stands out on his temple, his brows go up and his mouth opens wide
-- on his teeth, and the whole portrait shakes.
--
--   ShoemanFace.new()  -> face; face:update(dt); face:draw(x, y, scale)
--   face.talking       set while the words are still typing out
--   face.shouting      set while he shouts; wins over talking

local Pixel = require("src.art.pixel")

local ShoemanFace = {}
ShoemanFace.__index = ShoemanFace

ShoemanFace.W, ShoemanFace.H = 64, 72

local C = {
  board = { 0.13, 0.25, 0.19 },
  boardDark = { 0.10, 0.20, 0.15 },
  frame = { 0.42, 0.27, 0.14 },
  frameDark = { 0.30, 0.18, 0.09 },
  chalk = { 0.88, 0.90, 0.86 },
  skin = { 0.93, 0.74, 0.62 },
  skinHi = { 1.00, 0.88, 0.80 },
  skinShade = { 0.78, 0.56, 0.45 },
  red = { 0.90, 0.40, 0.36 }, -- the face while he shouts
  redShade = { 0.74, 0.28, 0.25 },
  nose = { 0.88, 0.50, 0.46 },
  vein = { 0.60, 0.18, 0.20 },
  brow = { 0.70, 0.71, 0.72 },
  browShade = { 0.48, 0.49, 0.51 },
  stubble = { 0.45, 0.40, 0.38 },
  white = { 0.96, 0.96, 0.92 },
  eye = { 0.22, 0.30, 0.36 },
  ink = { 0.08, 0.07, 0.07 },
  mouth = { 0.36, 0.08, 0.10 },
  tongue = { 0.80, 0.36, 0.38 },
  teeth = { 0.95, 0.92, 0.80 },
  shirt = { 0.13, 0.17, 0.33 },
  shirtDark = { 0.08, 0.11, 0.22 },
  shirtHi = { 0.20, 0.25, 0.44 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function rect(x, y, w, h)
  love.graphics.rectangle("fill", x, y, w, h)
end

function ShoemanFace.new()
  local self = setmetatable({}, ShoemanFace)
  self.canvas = Pixel.canvas(ShoemanFace.W, ShoemanFace.H)
  self.t = 0
  self.blink, self.blinkIn = 0, 2
  self.heat = 0 -- 0 calm to 1 red in the face; follows `shouting`
  self.talking = false
  self.shouting = false
  return self
end

function ShoemanFace:update(dt)
  self.t = self.t + dt
  self.blinkIn = self.blinkIn - dt
  if self.blinkIn <= 0 then
    self.blink, self.blinkIn = 0.15, 2.5 + love.math.random() * 3
  end
  self.blink = math.max(0, self.blink - dt)
  -- Goes red quickly, cools off slowly.
  local rate = self.shouting and 6 or 1.2
  self.heat = self.heat + ((self.shouting and 1 or 0) - self.heat) * math.min(1, dt * rate)
end

--- Skin colour `c` mixed toward its red twin by how heated he is.
local function heated(self, c, hot)
  local k = self.heat
  return { c[1] + (hot[1] - c[1]) * k, c[2] + (hot[2] - c[2]) * k, c[3] + (hot[3] - c[3]) * k }
end

local function drawBoard(self)
  color(C.board)
  rect(0, 0, 64, 72)
  color(C.boardDark)
  for y = 6, 70, 9 do
    rect(2, y, 60, 1)
  end
  color(C.frameDark)
  rect(0, 0, 64, 3)
  rect(0, 0, 2, 72)
  rect(62, 0, 2, 72)
  color(C.frame)
  rect(0, 0, 64, 2)
  -- A shoe chalked top left, with lines flying off it.
  color(C.chalk, 0.55)
  rect(5, 5, 4, 4) -- the shaft
  rect(5, 8, 8, 3) -- the foot
  rect(12, 9, 2, 2) -- the toe
  color(C.chalk, 0.85)
  rect(4, 11, 11, 1) -- the sole
  color(C.chalk, 0.45)
  rect(16, 6, 3, 1)
  rect(16, 9, 2, 1)
  -- Scribbled lesson lines top right; he has been at the board a while.
  local wobble = math.floor(self.t * 0.5) % 2
  rect(49, 6, 10, 1)
  rect(51, 9, 8 - wobble, 1)
  rect(50, 12, 6 + wobble, 1)
end

local function drawBody(self, bob)
  -- Heavy shoulders filling the bottom of the frame, a navy t-shirt.
  color(C.shirtDark)
  rect(0, 53 + bob, 64, 19)
  color(C.shirt)
  rect(2, 52 + bob, 60, 20)
  rect(8, 50 + bob, 48, 3)
  color(C.shirtHi)
  rect(6, 54 + bob, 10, 1)
  rect(48, 54 + bob, 10, 1)
  -- The collar, round, stretched.
  color(C.shirtDark)
  rect(20, 51 + bob, 24, 4)
  -- The thick neck.
  local skin, shade = heated(self, C.skin, C.red), heated(self, C.skinShade, C.redShade)
  color(shade)
  rect(19, 44 + bob, 26, 9)
  color(skin)
  rect(21, 44 + bob, 22, 7)
end

local function drawHead(self, bob, shake)
  local skin, shade = heated(self, C.skin, C.red), heated(self, C.skinShade, C.redShade)
  local x0, y0 = shake, bob
  -- Ears.
  color(shade)
  rect(12 + x0, 27 + y0, 4, 8)
  rect(48 + x0, 27 + y0, 4, 8)
  -- The head: wide and round on top, heavy at the jaw.
  color(shade)
  rect(17 + x0, 9 + y0, 30, 3)
  rect(15 + x0, 12 + y0, 34, 32)
  rect(17 + x0, 44 + y0, 30, 3)
  color(skin)
  rect(19 + x0, 9 + y0, 26, 3)
  rect(16 + x0, 12 + y0, 32, 31)
  rect(18 + x0, 43 + y0, 28, 3)
  -- The shine on the bald scalp.
  color(C.skinHi, 0.85 - self.heat * 0.4)
  rect(22 + x0, 12 + y0, 7, 2)
  rect(24 + x0, 14 + y0, 3, 1)
  -- The double chin.
  color(shade)
  rect(22 + x0, 46 + y0, 20, 1)
  -- A vein standing out on the temple when he shouts.
  if self.heat > 0.5 then
    color(C.vein)
    rect(43 + x0, 15 + y0, 1, 3)
    rect(42 + x0, 18 + y0, 1, 2)
    rect(44 + x0, 17 + y0, 1, 1)
  end
end

local function drawFace(self, bob, shake)
  local x0, y0 = shake, bob
  local shade = heated(self, C.skinShade, C.redShade)
  local loud = self.shouting
  -- Brows: bushy and grey, pulled down at the middle in a scowl. They bounce
  -- while he talks and shoot up when he shouts.
  local up = 0
  if loud then
    up = 2
  elseif self.talking then
    up = math.floor(math.abs(math.sin(self.t * 8)) * 2 + 0.5)
  end
  local by = 22 + y0 - up
  color(C.browShade)
  rect(19 + x0, by, 11, 3)
  rect(34 + x0, by, 11, 3)
  color(C.brow)
  if loud then
    rect(19 + x0, by, 10, 2)
    rect(35 + x0, by, 10, 2)
  else
    rect(19 + x0, by - 1, 4, 2) -- outer ends high,
    rect(23 + x0, by, 4, 2)
    rect(27 + x0, by + 1, 4, 2) -- inner ends low
    rect(41 + x0, by - 1, 4, 2)
    rect(37 + x0, by, 4, 2)
    rect(33 + x0, by + 1, 4, 2)
  end
  -- Eyes: small and hard, wide open when he shouts.
  local ey = 27 + y0
  if self.blink > 0 then
    color(C.ink)
    rect(21 + x0, ey + 1, 7, 1)
    rect(36 + x0, ey + 1, 7, 1)
  else
    local h = loud and 3 or 2
    color(C.white)
    rect(21 + x0, ey, 7, h)
    rect(36 + x0, ey, 7, h)
    color(C.eye)
    rect(24 + x0, ey, 2, h)
    rect(38 + x0, ey, 2, h)
    color(C.ink)
    rect(24 + x0, ey, 1, 1)
    rect(38 + x0, ey, 1, 1)
    color(shade) -- heavy lids
    rect(21 + x0, ey - 1, 7, 1)
    rect(36 + x0, ey - 1, 7, 1)
  end
  -- The nose: big and red.
  color(shade)
  rect(30 + x0, 29 + y0, 4, 7)
  color(C.nose)
  rect(29 + x0, 34 + y0, 6, 3)
  color(shade)
  rect(29 + x0, 37 + y0, 2, 1)
  rect(33 + x0, 37 + y0, 2, 1)
  -- Stubble round the mouth and jaw.
  color(C.stubble, 0.55)
  for k = 0, 22 do
    local sx = 19 + (k * 7) % 27
    local sy = 39 + (k * 5) % 7
    rect(sx + x0, sy + y0, 1, 1)
  end
  -- The mouth: a flat frown at rest, chewing out words while he talks,
  -- wide open on his teeth when he shouts.
  local my = 40 + y0
  if loud then
    color(C.ink)
    rect(23 + x0, my - 1, 18, 8)
    color(C.mouth)
    rect(24 + x0, my, 16, 6)
    color(C.teeth)
    rect(24 + x0, my, 16, 2)
    rect(26 + x0, my + 5, 12, 1)
    color(C.tongue)
    rect(28 + x0, my + 3, 8, 2)
  else
    local open = 0
    if self.talking then
      open = math.floor((math.sin(self.t * 20) + 1) * 1.5)
    end
    if open > 0 then
      color(C.ink)
      rect(25 + x0, my, 14, open + 2)
      color(C.mouth)
      rect(26 + x0, my + 1, 12, open)
      color(C.teeth)
      rect(27 + x0, my + 1, 10, 1)
    else
      color(C.ink)
      rect(25 + x0, my + 1, 14, 1)
      rect(24 + x0, my + 2, 1, 1) -- the corners turned down
      rect(39 + x0, my + 2, 1, 1)
    end
  end
end

function ShoemanFace:render()
  -- He bobs gently, harder while talking; shouting he shakes.
  local bob = math.floor(math.sin(self.t * (self.talking and 6 or 1.6)) * 0.8 + 0.5)
  local shake = 0
  if self.shouting then
    shake = math.floor(self.t * 30) % 2 == 0 and 1 or -1
  end
  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.origin()
  love.graphics.clear(0, 0, 0, 0)
  drawBoard(self)
  drawBody(self, bob)
  drawHead(self, bob, shake)
  drawFace(self, bob, shake)
  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel. Shouting,
--- he comes a little closer to the camera.
function ShoemanFace:draw(x, y, scale)
  local canvas = self:render()
  local s = scale * (1 + self.heat * 0.06)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, x - ShoemanFace.W / 2 * s, y - ShoemanFace.H / 2 * s, 0, s, s)
end

return ShoemanFace
