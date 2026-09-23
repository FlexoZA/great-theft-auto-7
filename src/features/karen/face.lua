-- Crazy Karen's face, for the quest's title screen. Drawn with primitives
-- onto a 64x72 canvas every frame and scaled up with nearest filtering,
-- the way the menu face is (src/art/face.lua), so the two screens match.
-- A wide face with a double chin, the haircut (long swept fringe on one
-- side, cropped short on the other), sunglasses pushed up on top, hoops,
-- a phone clamped to one ear and a mouth that never stops going.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.10, 0.05, 0.06 },
  skin = { 0.95, 0.80, 0.68 },
  shade = { 0.82, 0.62, 0.52 },
  blush = { 0.95, 0.50, 0.50 },
  hair = { 0.93, 0.80, 0.42 },
  hairDark = { 0.72, 0.56, 0.22 },
  hairLight = { 1.00, 0.94, 0.66 },
  white = { 0.96, 0.96, 0.92 },
  iris = { 0.35, 0.55, 0.80 },
  pupil = { 0.04, 0.04, 0.05 },
  lips = { 0.78, 0.12, 0.28 },
  mouth = { 0.30, 0.05, 0.08 },
  tongue = { 0.85, 0.35, 0.40 },
  teeth = { 0.95, 0.92, 0.82 },
  glasses = { 0.10, 0.08, 0.12 },
  glare = { 0.55, 0.60, 0.70 },
  gold = { 0.92, 0.76, 0.30 },
  phone = { 0.16, 0.16, 0.19 },
  screen = { 0.55, 0.85, 0.95 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.blink = 0
  self.nextBlink = 2 + love.math.random() * 3
  self.jitter = 0
  self.jitterTarget = 0
  self.jitterTimer = 0
  self.browTwitch = 0
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  if self.blink > 0 then
    self.blink = self.blink - dt
  else
    self.nextBlink = self.nextBlink - dt
    if self.nextBlink <= 0 then
      self.blink = 0.08
      self.nextBlink = 1.5 + love.math.random() * 3
    end
  end
  -- The eyes dart about looking for whoever is in charge.
  self.jitterTimer = self.jitterTimer - dt
  if self.jitterTimer <= 0 then
    self.jitterTarget = (love.math.random() - 0.5) * 4
    self.jitterTimer = 0.25 + love.math.random() * 1.2
  end
  self.jitter = self.jitter + (self.jitterTarget - self.jitter) * math.min(1, dt * 16)
  self.browTwitch = math.max(0, self.browTwitch - dt)
  if love.math.random() < dt * 0.6 then
    self.browTwitch = 0.2
  end
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- Hair, back volume: big, blown out.
  color(C.hairDark)
  love.graphics.ellipse("fill", cx, 34, 31, 27)
  color(C.hair)
  love.graphics.ellipse("fill", cx, 32, 29, 24)

  -- Neck and the double chin under the jaw.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 66, 23, 9)
  color(C.shade)
  love.graphics.ellipse("fill", cx, 66, 22, 8)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 68, 20, 6)

  -- Head: wide and round.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 43, 27, 25)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 43, 26, 24)
  color(C.shade)
  love.graphics.ellipse("fill", cx, 58, 20, 7) -- jowls
  color(C.skin)
  love.graphics.ellipse("fill", cx, 44, 24, 19)
  color(C.blush, 0.55)
  love.graphics.ellipse("fill", 15, 50, 6, 4)
  love.graphics.ellipse("fill", 49, 50, 6, 4)

  -- Hoop earrings.
  color(C.gold)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", 7, 54, 4)
  love.graphics.circle("line", 57, 54, 4)
  love.graphics.setLineWidth(1)

  -- Eyes: narrowed, darting.
  local blink = self.blink > 0
  for i, e in ipairs({ { x = 23, y = 41 }, { x = 41, y = 41 } }) do
    color(C.outline)
    love.graphics.ellipse("fill", e.x, e.y, 6, 4)
    color(C.white)
    love.graphics.ellipse("fill", e.x, e.y, 5, 3)
    local px = e.x + self.jitter + math.sin(t * 1.1 + i) * 0.6
    color(C.iris)
    love.graphics.circle("fill", px, e.y, 2.2)
    color(C.pupil)
    love.graphics.circle("fill", px, e.y, 1.2)
    if blink then
      color(C.skin)
      love.graphics.ellipse("fill", e.x, e.y, 6, 4)
      color(C.outline)
      love.graphics.line(e.x - 5, e.y, e.x + 5, e.y)
    end
  end
  -- Brows: a hard V, the inner ends jammed down.
  local lift = self.browTwitch > 0 and 1 or 0
  color(C.outline)
  love.graphics.setLineWidth(2)
  love.graphics.line(15, 32 - lift, 28, 37)
  love.graphics.line(36, 37, 49, 32 - lift)
  love.graphics.setLineWidth(1)

  -- Nose, small and turned up.
  love.graphics.line(33, 45, 31, 50, 35, 50)
  -- A mole.
  love.graphics.rectangle("fill", 44, 53, 1, 1)

  -- Mouth: open, going at it. It flaps in a talking rhythm.
  local open = 3 + 3.5 * math.abs(math.sin(t * 9)) * (0.6 + 0.4 * math.abs(math.sin(t * 2.3)))
  color(C.lips)
  love.graphics.ellipse("fill", cx + 1, 58, 11, open + 2)
  color(C.outline)
  love.graphics.ellipse("fill", cx + 1, 58, 10, open + 1)
  color(C.mouth)
  love.graphics.ellipse("fill", cx + 1, 58, 9, open)
  color(C.tongue)
  love.graphics.ellipse("fill", cx + 1, 58 + open * 0.5, 5, open * 0.4)
  color(C.teeth)
  for k = 0, 4 do
    love.graphics.rectangle("fill", 25 + k * 3.4, 58 - open, 3, 2)
  end

  -- The haircut goes on over the face: a fringe swept across from the
  -- right, one side hanging long to the jaw, the other cropped.
  color(C.hair)
  love.graphics.ellipse("fill", cx, 22, 28, 9)
  love.graphics.polygon("fill", 8, 26, 58, 16, 60, 24, 34, 30, 14, 34)
  color(C.hairLight)
  love.graphics.polygon("fill", 20, 22, 54, 15, 55, 18, 22, 26)
  color(C.hair)
  love.graphics.polygon("fill", 3, 28, 12, 27, 17, 62, 4, 58) -- long side
  color(C.hairDark)
  love.graphics.polygon("fill", 5, 40, 11, 39, 15, 60, 6, 57)
  color(C.hair)
  love.graphics.polygon("fill", 52, 27, 61, 28, 60, 42, 51, 44) -- cropped side
  color(C.hairDark)
  love.graphics.polygon("fill", 55, 30, 60, 30, 59, 41, 54, 42)

  -- Sunglasses pushed up on top of the head.
  color(C.outline)
  love.graphics.rectangle("fill", 16, 12, 14, 7, 3)
  love.graphics.rectangle("fill", 34, 12, 14, 7, 3)
  love.graphics.rectangle("fill", 29, 14, 6, 2)
  color(C.glasses)
  love.graphics.rectangle("fill", 17, 13, 12, 5, 2)
  love.graphics.rectangle("fill", 35, 13, 12, 5, 2)
  color(C.glare)
  love.graphics.line(19, 14, 24, 14)
  love.graphics.line(37, 14, 42, 14)
  color(C.gold)
  love.graphics.line(16, 15, 12, 20)
  love.graphics.line(48, 15, 52, 20)

  -- Phone clamped to the right ear, shaking with her.
  local shake = math.sin(t * 13) * 0.6
  love.graphics.push()
  love.graphics.translate(57 + shake, 44)
  love.graphics.rotate(0.15)
  color(C.outline)
  love.graphics.rectangle("fill", -4, -13, 9, 24, 2)
  color(C.phone)
  love.graphics.rectangle("fill", -3, -12, 7, 22, 2)
  color(C.screen)
  love.graphics.rectangle("fill", -2, -10, 5, 16)
  love.graphics.pop()

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, bobbing
--- and jabbing forward as she makes her point.
function Face:draw(x, y, scale)
  self:render()
  local bob = math.sin(self.t * 1.8) * scale * 0.5
  local jab = math.max(0, math.sin(self.t * 4.6)) * scale * 0.8
  local tilt = math.sin(self.t * 0.9) * 0.04
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x - jab, y + bob, tilt, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
