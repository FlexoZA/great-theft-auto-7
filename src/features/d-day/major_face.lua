-- Major Looz'er's face, for his portrait. Drawn with primitives onto a
-- 64x72 canvas every frame and scaled up with nearest filtering, the way
-- Karen's and Wendell's are. A peaked cap with far too much braid, a
-- monocle, a face gone red from shouting, a moustache wider than the face
-- under it, and a chest so full of medals they are running out of room.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.08, 0.06, 0.05 },
  skin = { 0.92, 0.66, 0.54 },
  flush = { 0.86, 0.42, 0.36 },
  shade = { 0.76, 0.50, 0.40 },
  cap = { 0.30, 0.34, 0.24 },
  capDark = { 0.20, 0.23, 0.16 },
  peak = { 0.10, 0.10, 0.10 },
  gold = { 0.95, 0.78, 0.25 },
  goldDark = { 0.70, 0.52, 0.12 },
  tunic = { 0.36, 0.40, 0.28 },
  tunicDark = { 0.26, 0.30, 0.20 },
  tache = { 0.55, 0.52, 0.50 },
  tacheDark = { 0.38, 0.36, 0.35 },
  white = { 0.98, 0.97, 0.92 },
  iris = { 0.25, 0.40, 0.70 },
  pupil = { 0.02, 0.02, 0.03 },
  glass = { 0.80, 0.92, 1.00 },
  mouth = { 0.35, 0.06, 0.06 },
  teeth = { 0.96, 0.94, 0.86 },
  ribbons = {
    { 0.80, 0.15, 0.15 },
    { 0.20, 0.35, 0.80 },
    { 0.95, 0.95, 0.95 },
    { 0.20, 0.60, 0.30 },
    { 0.85, 0.55, 0.15 },
  },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.blink = 0
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.blink = math.max(0, self.blink - dt)
  if love.math.random() < dt * 0.4 then
    self.blink = 0.12
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

  -- Tunic: square shoulders, epaulettes with fringes, a chest of medals.
  color(C.outline)
  love.graphics.rectangle("fill", 1, 58, 62, 16)
  color(C.tunic)
  love.graphics.rectangle("fill", 2, 59, 60, 15)
  color(C.tunicDark)
  love.graphics.polygon("fill", cx - 7, 58, cx, 68, cx + 7, 58)
  color(C.gold)
  love.graphics.rectangle("fill", 2, 58, 12, 4)
  love.graphics.rectangle("fill", 50, 58, 12, 4)
  color(C.goldDark)
  for k = 0, 5 do
    love.graphics.rectangle("fill", 2 + k * 2, 62, 1, 2)
    love.graphics.rectangle("fill", 51 + k * 2, 62, 1, 2)
  end
  -- Medals: two rows of ribbons each side, and medals hanging off them,
  -- swinging a little as he shouts.
  for side = -1, 1, 2 do
    for row = 0, 1 do
      for k = 0, 2 do
        local x = cx + side * (10 + k * 5) - (side < 0 and 4 or 0)
        local y = 63 + row * 5
        color(C.ribbons[(k + row * 2 + (side > 0 and 1 or 0)) % #C.ribbons + 1])
        love.graphics.rectangle("fill", x, y, 4, 2)
        color((k + row) % 2 == 0 and C.gold or C.white)
        local swing = math.floor(math.sin(t * 9 + k + row) + 0.5)
        love.graphics.rectangle("fill", x + 1 + swing, y + 2, 2, 2)
      end
    end
  end

  -- Neck and head: broad, jowly, red with the effort.
  color(C.shade)
  love.graphics.rectangle("fill", cx - 8, 50, 16, 9)
  color(C.outline)
  love.graphics.ellipse("fill", cx, 39, 19, 19)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 39, 18, 18)
  color(C.flush, 0.55 + 0.25 * math.abs(math.sin(t * 3)))
  love.graphics.ellipse("fill", cx - 10, 44, 5, 3)
  love.graphics.ellipse("fill", cx + 10, 44, 5, 3)
  color(C.shade)
  love.graphics.ellipse("fill", cx, 54, 12, 4) -- the chins
  color(C.outline)
  love.graphics.ellipse("fill", cx - 19, 40, 3, 5)
  love.graphics.ellipse("fill", cx + 19, 40, 3, 5)
  color(C.skin)
  love.graphics.ellipse("fill", cx - 19, 40, 2, 4)
  love.graphics.ellipse("fill", cx + 19, 40, 2, 4)

  -- Eyes: one narrowed in fury, the other huge behind a monocle.
  local shut = self.blink > 0
  color(C.outline)
  love.graphics.line(cx - 12, 34, cx - 4, 36)
  if not shut then
    color(C.white)
    love.graphics.rectangle("fill", cx - 11, 36, 6, 2)
    color(C.pupil)
    love.graphics.rectangle("fill", cx - 9, 36, 2, 2)
  else
    color(C.outline)
    love.graphics.line(cx - 11, 37, cx - 5, 37)
  end
  color(C.white)
  love.graphics.circle("fill", cx + 8, 36, 4)
  if not shut then
    color(C.iris)
    love.graphics.circle("fill", cx + 8, 36, 2)
    color(C.pupil)
    love.graphics.rectangle("fill", cx + 8, 36, 1, 1)
  end
  color(C.gold)
  love.graphics.circle("line", cx + 8, 36, 5)
  color(C.glass, 0.35)
  love.graphics.circle("fill", cx + 8, 36, 4)
  color(C.gold)
  love.graphics.line(cx + 13, 37, cx + 16, 44, cx + 15, 52) -- the monocle's chain
  -- Brows: thick and grey, jammed down.
  color(C.tacheDark)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - 13, 32, cx - 3, 34)
  love.graphics.line(cx + 3, 31, cx + 13, 30)
  love.graphics.setLineWidth(1)

  -- Nose: a big red bulb.
  color(C.flush)
  love.graphics.circle("fill", cx, 42, 3)

  -- Mouth: open, bellowing, under the moustache.
  local open = 2 + 3 * math.abs(math.sin(t * 8)) * (0.6 + 0.4 * math.abs(math.sin(t * 1.3)))
  color(C.outline)
  love.graphics.ellipse("fill", cx, 50, 7, open + 1)
  color(C.mouth)
  love.graphics.ellipse("fill", cx, 50, 6, open)
  color(C.teeth)
  love.graphics.rectangle("fill", cx - 5, 50 - open, 10, 1)

  -- The moustache: a handlebar out past both cheeks, twitching as he shouts.
  local lift = math.sin(t * 8) * 0.8
  color(C.tacheDark)
  love.graphics.polygon("fill", cx, 45, cx - 22, 42 - lift, cx - 25, 38 - lift, cx - 18, 45, cx - 4, 48)
  love.graphics.polygon("fill", cx, 45, cx + 22, 42 - lift, cx + 25, 38 - lift, cx + 18, 45, cx + 4, 48)
  color(C.tache)
  love.graphics.polygon("fill", cx, 45, cx - 20, 42 - lift, cx - 16, 44, cx - 4, 47)
  love.graphics.polygon("fill", cx, 45, cx + 20, 42 - lift, cx + 16, 44, cx + 4, 47)

  -- The cap: a tall crown, a black peak, braid and a badge.
  color(C.outline)
  love.graphics.polygon("fill", cx - 24, 24, cx - 20, 8, cx + 20, 8, cx + 24, 24)
  color(C.cap)
  love.graphics.polygon("fill", cx - 23, 23, cx - 19, 9, cx + 19, 9, cx + 23, 23)
  color(C.capDark)
  love.graphics.rectangle("fill", cx - 22, 20, 44, 5)
  color(C.gold)
  love.graphics.rectangle("fill", cx - 22, 20, 44, 1)
  love.graphics.rectangle("fill", cx - 22, 24, 44, 1)
  love.graphics.circle("fill", cx, 15, 4)
  color(C.goldDark)
  love.graphics.circle("fill", cx, 15, 2)
  color(C.peak)
  love.graphics.polygon("fill", cx - 22, 25, cx + 22, 25, cx + 17, 30, cx - 17, 30)
  color(C.gold)
  love.graphics.line(cx - 16, 27, cx + 16, 27) -- scrambled egg on the peak

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, standing
--- stiffly to attention and shaking with conviction.
function Face:draw(x, y, scale)
  self:render()
  local shake = math.sin(self.t * 31) * scale * 0.2
  local bob = math.sin(self.t * 2) * scale * 0.3
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x + shake, y + bob, 0, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
