-- Bigfoot's face, for the moment he shows himself. Drawn with primitives
-- onto a 64x72 canvas every frame and scaled up with nearest filtering,
-- like the other portraits. He is not a looker: matted fur, a brow like a
-- shelf, two mean little eyes of different sizes, a squashed nose with
-- nostrils you could lose a hand in, warts, and a mouth wide open in a
-- roar full of crooked yellow teeth, drooling.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.06, 0.04, 0.03 },
  fur = { 0.42, 0.28, 0.16 },
  furDark = { 0.28, 0.18, 0.10 },
  furLight = { 0.56, 0.40, 0.24 },
  skin = { 0.36, 0.26, 0.22 }, -- the leathery bit of the face
  skinDark = { 0.24, 0.17, 0.14 },
  wart = { 0.46, 0.38, 0.26 },
  eye = { 0.95, 0.80, 0.25 },
  red = { 0.85, 0.12, 0.08 },
  pupil = { 0.02, 0.02, 0.02 },
  mouth = { 0.22, 0.04, 0.05 },
  gum = { 0.60, 0.25, 0.28 },
  tongue = { 0.62, 0.22, 0.25 },
  tooth = { 0.86, 0.78, 0.42 },
  toothDark = { 0.62, 0.52, 0.22 },
  drool = { 0.80, 0.90, 0.95 },
  fly = { 0.05, 0.05, 0.05 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  return self
end

function Face:update(dt)
  self.t = self.t + dt
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2
  local roar = 0.75 + 0.25 * math.abs(math.sin(t * 7)) -- how far the jaw is dropped

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- The head: a heap of matted fur, wider than it is tall, shoulders under.
  color(C.furDark)
  love.graphics.ellipse("fill", cx, 70, 34, 16)
  love.graphics.ellipse("fill", cx, 36, 31, 34)
  color(C.fur)
  love.graphics.ellipse("fill", cx, 70, 32, 14)
  love.graphics.ellipse("fill", cx, 36, 29, 32)
  -- Clumps sticking out of the outline.
  for k = 0, 17 do
    local a = k / 18 * math.pi * 2
    local r = 28 + (k * 5) % 5
    color(k % 2 == 0 and C.furDark or C.fur)
    love.graphics.circle("fill", cx + math.cos(a) * r, 36 + math.sin(a) * r * 1.05, 3 + k % 3)
  end
  color(C.furLight)
  for k = 0, 9 do
    local x, y = 10 + (k * 13) % 44, 8 + (k * 7) % 18
    love.graphics.line(x, y, x + 2, y + 5)
  end

  -- The face: a leathery patch, low and wide.
  color(C.skinDark)
  love.graphics.ellipse("fill", cx, 44, 21, 21)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 44, 20, 20)

  -- The brow: one great shelf of bone and fur over everything.
  color(C.outline)
  love.graphics.polygon("fill", cx - 23, 30, cx - 10, 24, cx, 28, cx + 10, 24, cx + 23, 30, cx + 20, 35, cx - 20, 35)
  color(C.furDark)
  love.graphics.polygon("fill", cx - 21, 30, cx - 10, 25, cx, 29, cx + 10, 25, cx + 21, 30, cx + 18, 33, cx - 18, 33)

  -- Eyes: sunk in under the brow, small, mean, bloodshot, not a pair.
  color(C.red)
  love.graphics.ellipse("fill", cx - 10, 37, 5, 3)
  love.graphics.ellipse("fill", cx + 11, 38, 3.5, 2.5)
  color(C.eye)
  love.graphics.circle("fill", cx - 10, 37, 2.2)
  love.graphics.circle("fill", cx + 11, 38, 1.6)
  color(C.pupil)
  love.graphics.rectangle("fill", cx - 10, 36, 1, 2)
  love.graphics.rectangle("fill", cx + 11, 37, 1, 2)

  -- Nose: squashed flat, nostrils flaring with every breath.
  local flare = 1 + 0.4 * math.abs(math.sin(t * 7))
  color(C.skinDark)
  love.graphics.ellipse("fill", cx, 44, 9, 5)
  color(C.outline)
  love.graphics.ellipse("fill", cx - 4, 45, 2.5 * flare, 2)
  love.graphics.ellipse("fill", cx + 4, 45, 2.5 * flare, 2)

  -- Warts, one with a hair growing out of it.
  color(C.wart)
  love.graphics.circle("fill", cx - 16, 44, 2)
  love.graphics.circle("fill", cx + 15, 49, 1.5)
  love.graphics.circle("fill", cx + 7, 32, 1.2)
  color(C.outline)
  love.graphics.line(cx - 16, 43, cx - 18, 40)

  -- Mouth: roaring, as wide as the face. Gums, a tongue, teeth pointing
  -- every which way, a gap or two.
  local mh = 11 * roar
  color(C.outline)
  love.graphics.ellipse("fill", cx, 58, 17, mh + 1)
  color(C.mouth)
  love.graphics.ellipse("fill", cx, 58, 16, mh)
  color(C.tongue)
  love.graphics.ellipse("fill", cx + 2, 58 + mh * 0.55, 9, mh * 0.35)
  color(C.gum)
  love.graphics.rectangle("fill", cx - 14, 58 - mh, 28, 2)
  love.graphics.rectangle("fill", cx - 13, 56 + mh, 26, 2)
  local upper = { -12, -8, -5, -1, 4, 7, 11 }
  for i, dx in ipairs(upper) do
    local len = (i == 2 or i == 6) and 6 or 3 + i % 2
    color(i % 3 == 0 and C.toothDark or C.tooth)
    local top = 59 - mh
    love.graphics.polygon("fill", cx + dx - 1.5, top, cx + dx + 1.5, top, cx + dx + (i % 2 - 0.5), top + len)
  end
  for i, dx in ipairs({ -10, -6, 0, 5, 9 }) do
    local len = (i == 1 or i == 5) and 5 or 3
    color(i % 2 == 0 and C.toothDark or C.tooth)
    love.graphics.polygon("fill", cx + dx - 1.5, 57 + mh, cx + dx + 1.5, 57 + mh, cx + dx, 57 + mh - len)
  end
  -- Drool, stretching off the lip.
  local drip = 3 + (t * 6) % 9
  color(C.drool, 0.85)
  love.graphics.rectangle("fill", cx - 9, 57 + mh, 1, drip)
  love.graphics.circle("fill", cx - 8.5, 57 + mh + drip, 1.2)
  love.graphics.rectangle("fill", cx + 12, 55 + mh, 1, drip * 0.6)

  -- A fly that will not leave him alone.
  color(C.fly)
  love.graphics.rectangle("fill", cx + 22 + math.sin(t * 9) * 4, 20 + math.cos(t * 13) * 3, 1, 1)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, shaking
--- with the roar.
function Face:draw(x, y, scale)
  self:render()
  local shake = scale * 0.5
  local jx = math.sin(self.t * 41) * shake
  local jy = math.cos(self.t * 37) * shake
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x + jx, y + jy, 0, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
