-- Shotgun's face, for his portrait. Drawn with primitives onto a 64x72
-- canvas every frame and scaled up with nearest filtering, the way the
-- other bosses' are. A long pale face going bald on top with a few hairs
-- combed over, stubble, glasses with frames as thick as a thumb, one eye
-- magnified and darting, the other blind and milky, and the mouth always
-- wide open, a tall oval, with a single buck tooth standing up from the
-- bottom. A camo jacket, and a badge on it: a speech bubble crossed out.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.08, 0.07, 0.06 },
  skin = { 0.93, 0.80, 0.68 },
  shade = { 0.80, 0.64, 0.52 },
  stubble = { 0.55, 0.48, 0.42 },
  hair = { 0.35, 0.28, 0.20 },
  camo = { 0.38, 0.42, 0.26 },
  camoDark = { 0.26, 0.29, 0.17 },
  camoLight = { 0.52, 0.48, 0.32 },
  frame = { 0.10, 0.09, 0.08 },
  glass = { 0.75, 0.88, 0.95 },
  white = { 0.98, 0.97, 0.94 },
  blind = { 0.86, 0.87, 0.85 },
  iris = { 0.35, 0.50, 0.30 },
  pupil = { 0.02, 0.02, 0.03 },
  mouth = { 0.32, 0.05, 0.07 },
  tongue = { 0.80, 0.35, 0.38 },
  tooth = { 0.96, 0.93, 0.80 },
  badge = { 0.95, 0.95, 0.92 },
  red = { 0.85, 0.15, 0.12 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.look = 0 -- where the good eye is darting, -1..1
  self.lookIn = 0.5
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.lookIn = self.lookIn - dt
  if self.lookIn <= 0 then
    self.lookIn = 0.3 + love.math.random() * 0.9
    self.look = love.math.random(-1, 1)
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

  -- Jacket: camo, hunched shoulders, and the badge.
  color(C.outline)
  love.graphics.rectangle("fill", 2, 59, 60, 15)
  color(C.camo)
  love.graphics.rectangle("fill", 3, 60, 58, 14)
  color(C.camoDark)
  for _, b in ipairs({ { 6, 62, 7, 4 }, { 18, 66, 8, 3 }, { 44, 61, 6, 5 }, { 52, 67, 7, 3 }, { 30, 69, 5, 3 } }) do
    love.graphics.rectangle("fill", b[1], b[2], b[3], b[4])
  end
  color(C.camoLight)
  for _, b in ipairs({ { 12, 60, 5, 3 }, { 38, 66, 6, 3 }, { 56, 62, 4, 3 } }) do
    love.graphics.rectangle("fill", b[1], b[2], b[3], b[4])
  end
  color(C.shade)
  love.graphics.polygon("fill", cx - 6, 59, cx, 66, cx + 6, 59)
  color(C.badge) -- a speech bubble...
  love.graphics.rectangle("fill", 44, 63, 9, 6)
  love.graphics.polygon("fill", 46, 69, 48, 69, 45, 71)
  color(C.red) -- ...crossed out
  love.graphics.line(43, 71, 54, 62)

  -- Neck and head: long, pale, stubbly jaw.
  color(C.shade)
  love.graphics.rectangle("fill", cx - 6, 50, 12, 10)
  color(C.outline)
  love.graphics.ellipse("fill", cx, 36, 17, 22)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 36, 16, 21)
  color(C.stubble, 0.55)
  love.graphics.ellipse("fill", cx, 48, 13, 8)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 44, 12, 5)
  color(C.outline) -- ears
  love.graphics.ellipse("fill", cx - 17, 36, 3, 5)
  love.graphics.ellipse("fill", cx + 17, 36, 3, 5)
  color(C.skin)
  love.graphics.ellipse("fill", cx - 17, 36, 2, 4)
  love.graphics.ellipse("fill", cx + 17, 36, 2, 4)
  -- Bald on top, a few long hairs combed over it, lifting as he shouts.
  color(C.hair)
  love.graphics.rectangle("fill", cx - 16, 26, 3, 8)
  love.graphics.rectangle("fill", cx + 13, 26, 3, 8)
  local lift = math.floor(math.abs(math.sin(t * 7)) * 2)
  love.graphics.line(cx - 14, 25, cx - 4, 17 - lift, cx + 8, 16 - lift, cx + 13, 20)
  love.graphics.line(cx - 14, 27, cx - 2, 19 - lift, cx + 10, 18 - lift)

  -- Brows: jammed down in the middle.
  color(C.hair)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - 14, 27, cx - 3, 30)
  love.graphics.line(cx + 3, 30, cx + 14, 27)
  love.graphics.setLineWidth(1)

  -- Eyes, behind the glasses: the left one (his right) good and huge
  -- through the lens, darting; the other milky and blind, looking at nothing.
  local lx, rx, ey = cx - 8, cx + 8, 35
  color(C.white)
  love.graphics.circle("fill", lx, ey, 5)
  color(C.iris)
  love.graphics.circle("fill", lx + self.look * 2, ey, 3)
  color(C.pupil)
  love.graphics.circle("fill", lx + self.look * 2, ey, 1.5)
  color(C.blind)
  love.graphics.circle("fill", rx, ey + 1, 4)
  color(C.white, 0.8)
  love.graphics.circle("fill", rx + 1, ey + 2, 2.4)
  color(C.shade)
  love.graphics.rectangle("fill", rx - 4, ey - 4, 9, 2) -- the lid, drooping
  -- The glasses: thick black frames, glass with a glint sliding over it.
  color(C.glass, 0.35)
  love.graphics.circle("fill", lx, ey, 7)
  love.graphics.circle("fill", rx, ey, 7)
  color(C.frame)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", lx, ey, 7.5)
  love.graphics.circle("line", rx, ey, 7.5)
  love.graphics.line(lx + 7, ey - 1, rx - 7, ey - 1) -- the bridge
  love.graphics.line(lx - 8, ey - 1, cx - 16, ey - 3) -- the arms
  love.graphics.line(rx + 8, ey - 1, cx + 16, ey - 3)
  love.graphics.setLineWidth(1)
  local g = (t * 0.7) % 2
  if g < 1 then
    color(C.white, 0.8)
    local gx = math.floor(-4 + g * 8)
    love.graphics.line(lx + gx, ey - 4, lx + gx + 2, ey - 6)
    love.graphics.line(rx + gx, ey - 4, rx + gx + 2, ey - 6)
  end

  -- Nose: long and pointed.
  color(C.shade)
  love.graphics.polygon("fill", cx - 1, 37, cx + 3, 44, cx - 2, 45)

  -- The mouth: always wide open, a tall oval, one buck tooth standing up
  -- from the bottom lip.
  local open = 7 + math.abs(math.sin(t * 6)) * 1.5
  color(C.outline)
  love.graphics.ellipse("fill", cx, 51, 5, open + 1)
  color(C.mouth)
  love.graphics.ellipse("fill", cx, 51, 4, open)
  color(C.tongue)
  love.graphics.ellipse("fill", cx, 51 + open - 3, 3, 2)
  color(C.tooth)
  love.graphics.rectangle("fill", cx - 1, 51 + open - 6, 3, 5)
  color(C.outline, 0.5)
  love.graphics.line(cx, 51 + open - 6, cx, 51 + open - 2)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, leaning in
--- and jabbing at you as he talks.
function Face:draw(x, y, scale)
  self:render()
  local lean = math.sin(self.t * 5) * scale * 0.4
  local bob = math.abs(math.sin(self.t * 6)) * scale * 0.5
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x + lean, y - bob, 0, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
