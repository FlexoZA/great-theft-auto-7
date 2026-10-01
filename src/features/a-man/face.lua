-- A-Man's face, for his portrait. Drawn with primitives onto a 64x72
-- canvas every frame and scaled up with nearest filtering, the way Karen's
-- and the Major's are. A certain man in a blue suit who would rather not be
-- recognised: the long gaunt face, the slicked-back hair going thin at the
-- temples, the tired green eyes and the knowing half-smile are all his. The
-- disguise is a pair of joke-shop glasses with no lenses and the price tag
-- still on, and a black moustache too big for his lip and a different colour
-- from his hair, stuck on crooked with a strip of tape that is coming loose.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.07, 0.06, 0.06 },
  skin = { 0.84, 0.77, 0.66 },
  shade = { 0.67, 0.60, 0.50 },
  hollow = { 0.58, 0.52, 0.44 },
  hair = { 0.25, 0.19, 0.14 },
  hairLight = { 0.38, 0.30, 0.22 },
  white = { 0.92, 0.92, 0.86 },
  iris = { 0.36, 0.62, 0.30 },
  pupil = { 0.02, 0.02, 0.03 },
  lip = { 0.62, 0.46, 0.42 },
  suit = { 0.16, 0.22, 0.38 },
  suitDark = { 0.10, 0.14, 0.26 },
  shirt = { 0.90, 0.90, 0.86 },
  tie = { 0.20, 0.30, 0.42 },
  tieDark = { 0.13, 0.20, 0.30 },
  frame = { 0.04, 0.04, 0.05 },
  shine = { 0.55, 0.55, 0.60 },
  tache = { 0.03, 0.03, 0.03 },
  tacheHi = { 0.18, 0.18, 0.20 },
  tape = { 0.93, 0.90, 0.78 },
  tag = { 0.96, 0.92, 0.70 },
  string = { 0.90, 0.88, 0.80 },
  price = { 0.80, 0.15, 0.15 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.blink = 0
  self.look = 0 -- where the eyes are glancing, -1 (left) to 1 (right)
  self.lookTarget = 0
  self.lookTimer = 1
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.blink = math.max(0, self.blink - dt)
  if love.math.random() < dt * 0.3 then
    self.blink = 0.14
  end
  -- Shifty: glance one way, hold it, glance the other, now and then ahead.
  self.lookTimer = self.lookTimer - dt
  if self.lookTimer <= 0 then
    local r = love.math.random()
    self.lookTarget = r < 0.4 and -1 or r < 0.8 and 1 or 0
    self.lookTimer = 0.6 + love.math.random() * 1.4
  end
  self.look = self.look + (self.lookTarget - self.look) * math.min(1, dt * 14)
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- Suit: narrow shoulders, lapels, a white shirt and a neat tie.
  color(C.outline)
  love.graphics.polygon("fill", 3, 72, 6, 61, 20, 56, 44, 56, 58, 61, 61, 72)
  color(C.suit)
  love.graphics.polygon("fill", 4, 72, 7, 62, 21, 57, 43, 57, 57, 62, 60, 72)
  color(C.shirt)
  love.graphics.polygon("fill", cx - 8, 56, cx + 8, 56, cx, 72)
  color(C.suitDark)
  love.graphics.polygon("fill", cx - 9, 57, cx - 4, 64, cx - 2, 72, cx - 12, 72, cx - 14, 60)
  love.graphics.polygon("fill", cx + 9, 57, cx + 4, 64, cx + 2, 72, cx + 12, 72, cx + 14, 60)
  color(C.tieDark)
  love.graphics.polygon("fill", cx - 2, 57, cx + 2, 57, cx + 1, 60, cx - 1, 60)
  color(C.tie)
  love.graphics.polygon("fill", cx - 1, 60, cx + 1, 60, cx + 3, 70, cx, 72, cx - 3, 70)

  -- Neck: thin.
  color(C.shade)
  love.graphics.rectangle("fill", cx - 5, 50, 10, 8)

  -- Hair behind the head: the back of it, slicked flat, showing at the crown.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 17, 14, 8)
  color(C.hair)
  love.graphics.ellipse("fill", cx, 17, 13, 7)

  -- Ears: set low, close to the head.
  color(C.outline)
  love.graphics.ellipse("fill", cx - 13, 35, 3, 5)
  love.graphics.ellipse("fill", cx + 13, 35, 3, 5)
  color(C.skin)
  love.graphics.ellipse("fill", cx - 13, 35, 2, 4)
  love.graphics.ellipse("fill", cx + 13, 35, 2, 4)

  -- Head: long and narrow, a high forehead, a long chin.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 34, 13, 22)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 34, 12, 21)
  -- Gaunt: hollow cheeks under sharp cheekbones, a narrow shadowed jaw.
  color(C.hollow)
  love.graphics.polygon("fill", cx - 12, 37, cx - 8, 40, cx - 7, 48, cx - 10, 47)
  love.graphics.polygon("fill", cx + 12, 37, cx + 8, 40, cx + 7, 48, cx + 10, 47)
  color(C.shade)
  love.graphics.ellipse("fill", cx, 52, 7, 3)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 51, 5, 3)
  -- Lines from the nose down past the mouth.
  color(C.hollow)
  love.graphics.line(cx - 4, 41, cx - 6, 45, cx - 6, 49)
  love.graphics.line(cx + 4, 41, cx + 6, 45, cx + 6, 49)

  -- Hair over the forehead: gone far back at both temples, leaving a
  -- widow's peak, the rest combed straight back and flat at the sides.
  color(C.hair)
  love.graphics.polygon("fill", cx - 10, 11, cx + 10, 11, cx + 11, 14, cx + 8, 15, cx - 8, 15, cx - 11, 14)
  love.graphics.polygon("fill", cx - 5, 14, cx + 5, 14, cx, 19)
  love.graphics.polygon("fill", cx - 13, 18, cx - 11, 14, cx - 9, 15, cx - 12, 26)
  love.graphics.polygon("fill", cx + 13, 18, cx + 11, 14, cx + 9, 15, cx + 12, 26)
  color(C.hairLight)
  for k = -2, 2 do
    love.graphics.line(cx + k * 3, 14, cx + k * 4, 11) -- comb lines, raked back
  end
  -- A little temple shine where the hair used to be.
  color(C.white, 0.35)
  love.graphics.rectangle("fill", cx - 7, 17, 2, 1)

  -- Brows: thin, a little raised, unimpressed.
  color(C.hair)
  love.graphics.line(cx - 10, 26, cx - 7, 25, cx - 3, 26)
  love.graphics.line(cx + 3, 26, cx + 7, 25, cx + 10, 25)

  -- Eyes: heavy lids, bags under them, green irises glancing about.
  local look = math.floor(self.look * 1.5 + 0.5)
  for side = -1, 1, 2 do
    local ex = cx + side * 6
    color(C.shade)
    love.graphics.line(ex - 3, 34, ex + 3, 34) -- the bags
    love.graphics.line(ex - 2, 35, ex + 2, 35)
    if self.blink > 0 then
      color(C.outline)
      love.graphics.line(ex - 3, 31, ex + 3, 31)
    else
      color(C.white)
      love.graphics.rectangle("fill", ex - 3, 30, 6, 3)
      color(C.iris)
      love.graphics.rectangle("fill", ex - 1 + look, 30, 3, 3)
      color(C.pupil)
      love.graphics.rectangle("fill", ex + look, 31, 1, 1)
      color(C.shade)
      love.graphics.rectangle("fill", ex - 3, 30, 6, 1) -- the lid, half down
      color(C.outline)
      love.graphics.line(ex - 3, 29, ex + 3, 29)
    end
  end

  -- Nose: long and straight.
  color(C.shade)
  love.graphics.line(cx, 33, cx, 40)
  love.graphics.line(cx - 2, 41, cx + 2, 41)
  color(C.hollow)
  love.graphics.rectangle("fill", cx - 2, 40, 1, 1)
  love.graphics.rectangle("fill", cx + 2, 40, 1, 1)

  -- Mouth: thin lips, one corner up. He knows something you don't.
  color(C.lip)
  love.graphics.line(cx - 4, 47, cx + 2, 47, cx + 4, 46)
  color(C.hollow)
  love.graphics.rectangle("fill", cx + 4, 45, 1, 1)

  -- The glasses: big round joke-shop frames with nothing in them.
  color(C.frame)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", cx - 6, 31, 4.5)
  love.graphics.circle("line", cx + 6, 31, 4.5)
  love.graphics.setLineWidth(1)
  love.graphics.line(cx - 1, 30, cx + 1, 30) -- the bridge
  love.graphics.line(cx - 11, 30, cx - 13, 33) -- the arms, to the ears
  love.graphics.line(cx + 11, 30, cx + 13, 33)
  color(C.shine)
  love.graphics.rectangle("fill", cx - 9, 27, 2, 1)
  love.graphics.rectangle("fill", cx + 3, 27, 2, 1)
  -- The price tag, still on its string, swinging off the right arm.
  local swing = math.sin(t * 2.4) * 1.5
  local tx, ty = cx + 17 + swing, 41
  color(C.string)
  love.graphics.line(cx + 13, 33, tx, ty)
  color(C.outline)
  love.graphics.rectangle("fill", tx - 3, ty, 7, 5)
  color(C.tag)
  love.graphics.rectangle("fill", tx - 2, ty + 1, 5, 3)
  color(C.price)
  love.graphics.rectangle("fill", tx - 1, ty + 2, 3, 1)

  -- The moustache: a black bristle-brush stuck on crooked, too big for the
  -- lip and nothing like his hair. The left end has come unstuck and flaps.
  local flap = math.floor(math.sin(t * 5) * 1.5 + 0.5)
  color(C.tache)
  love.graphics.polygon("fill", cx - 6, 41, cx + 9, 42, cx + 10, 45, cx - 5, 45)
  love.graphics.polygon("fill", cx - 6, 41, cx - 5, 45, cx - 11, 45 + flap, cx - 11, 42 + flap)
  color(C.tacheHi)
  for k = 0, 6 do
    love.graphics.rectangle("fill", cx - 5 + k * 2, 44, 1, 1) -- bristles
  end
  -- A strip of tape holding the right end on, for now.
  color(C.tape)
  love.graphics.polygon("fill", cx + 6, 40, cx + 8, 40, cx + 10, 46, cx + 8, 46)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, standing
--- very still the way he does, with only the slightest drift.
function Face:draw(x, y, scale)
  self:render()
  local drift = math.sin(self.t * 0.9) * scale * 0.3
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x, y + drift, 0, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
