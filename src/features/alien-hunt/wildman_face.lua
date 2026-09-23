-- Wild Man Wendell's face, for the quest's screens. Drawn with primitives
-- onto a 64x72 canvas every frame and scaled up with nearest filtering,
-- the way Karen's is. Hair out in every direction, eyes far too wide and
-- never pointing the same way, a stubbly grin with a tooth missing, and a
-- shirt that has had most of lunch down it.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.08, 0.06, 0.05 },
  skin = { 0.88, 0.70, 0.55 },
  shade = { 0.74, 0.55, 0.42 },
  hair = { 0.62, 0.58, 0.52 },
  hairDark = { 0.42, 0.38, 0.34 },
  hairLight = { 0.82, 0.80, 0.74 },
  stubble = { 0.45, 0.38, 0.32 },
  white = { 0.98, 0.97, 0.92 },
  vein = { 0.85, 0.30, 0.30 },
  iris = { 0.30, 0.70, 0.35 },
  pupil = { 0.02, 0.02, 0.03 },
  mouth = { 0.30, 0.08, 0.08 },
  teeth = { 0.92, 0.86, 0.60 },
  shirt = { 0.86, 0.84, 0.74 }, -- once white
  shirtShade = { 0.70, 0.68, 0.58 },
  mustard = { 0.90, 0.72, 0.12 },
  ketchup = { 0.75, 0.10, 0.08 },
  gravy = { 0.45, 0.30, 0.15 },
  noodle = { 0.96, 0.90, 0.55 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.look = { 0, 0 } -- each eye goes its own way
  self.lookTarget = { 0, 0 }
  self.lookTimer = 0
  self.twitch = 0
  return self
end

function Face:update(dt)
  self.t = self.t + dt
  self.lookTimer = self.lookTimer - dt
  if self.lookTimer <= 0 then
    self.lookTarget = { (love.math.random() - 0.5) * 5, (love.math.random() - 0.5) * 5 }
    self.lookTimer = 0.15 + love.math.random() * 0.7
  end
  for i = 1, 2 do
    self.look[i] = self.look[i] + (self.lookTarget[i] - self.look[i]) * math.min(1, dt * 20)
  end
  self.twitch = math.max(0, self.twitch - dt)
  if love.math.random() < dt * 1.2 then
    self.twitch = 0.15
  end
end

--- A tuft of hair: a spike from the head outwards at angle `a`.
local function spike(cx, cy, a, r0, r1, w)
  local ca, sa = math.cos(a), math.sin(a)
  love.graphics.polygon("fill", cx + ca * r0 - sa * w, cy + sa * r0 + ca * w, cx + ca * r1, cy + sa * r1,
    cx + ca * r0 + sa * w, cy + sa * r0 - ca * w)
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- Hair: spikes out in every direction, stirring as if in a gale.
  for k = 0, 22 do
    local a = math.pi + k / 22 * math.pi * 1.3 - 0.15 + math.sin(t * 3 + k) * 0.05
    local r1 = 27 + (k * 7) % 9 + math.sin(t * 5 + k * 2) * 1.2
    color(k % 3 == 0 and C.hairDark or C.hair)
    spike(cx, 30, a, 12, r1, 4)
  end
  color(C.hair)
  love.graphics.ellipse("fill", cx, 24, 24, 16)
  color(C.hairLight)
  for k = 0, 6 do
    spike(cx, 28, math.pi * 1.1 + k * 0.28, 10, 24 + (k * 5) % 6, 1.5)
  end

  -- Shirt: shoulders across the bottom, stained.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 74, 33, 16)
  color(C.shirt)
  love.graphics.ellipse("fill", cx, 74, 32, 15)
  color(C.shirtShade)
  love.graphics.polygon("fill", cx - 8, 60, cx, 70, cx + 8, 60) -- the collar gap
  color(C.skin)
  love.graphics.polygon("fill", cx - 6, 60, cx, 67, cx + 6, 60)
  color(C.mustard)
  love.graphics.ellipse("fill", 16, 66, 4, 3)
  love.graphics.rectangle("fill", 17, 68, 2, 3)
  color(C.ketchup)
  love.graphics.ellipse("fill", 45, 64, 3, 2)
  love.graphics.ellipse("fill", 49, 68, 2, 2)
  love.graphics.rectangle("fill", 44, 65, 1, 4)
  color(C.gravy)
  love.graphics.ellipse("fill", 28, 69, 5, 2)
  color(C.noodle)
  love.graphics.setLineWidth(1)
  love.graphics.line(38, 66, 40, 68, 38, 70, 41, 71) -- a noodle, still hanging on

  -- Neck and head: long and gaunt.
  color(C.shade)
  love.graphics.rectangle("fill", cx - 6, 52, 12, 9)
  color(C.outline)
  love.graphics.ellipse("fill", cx, 38, 19, 22)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 38, 18, 21)
  color(C.shade)
  love.graphics.ellipse("fill", cx - 11, 46, 4, 6) -- sunken cheeks
  love.graphics.ellipse("fill", cx + 11, 46, 4, 6)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 49, 11, 9)
  -- Ears, sticking out.
  color(C.outline)
  love.graphics.ellipse("fill", cx - 19, 40, 4, 6)
  love.graphics.ellipse("fill", cx + 19, 40, 4, 6)
  color(C.skin)
  love.graphics.ellipse("fill", cx - 19, 40, 3, 5)
  love.graphics.ellipse("fill", cx + 19, 40, 3, 5)

  -- Stubble on the jaw.
  color(C.stubble)
  for k = 0, 26 do
    local a = math.pi * 0.15 + k / 26 * math.pi * 0.7
    local d = 13 + (k * 3) % 5
    love.graphics.rectangle("fill", cx + math.cos(a) * d, 42 + math.sin(a) * d, 1, 1)
  end

  -- Eyes: huge, round, bloodshot, each pupil tiny and on its own errand.
  local lift = self.twitch > 0 and 1 or 0
  for i, e in ipairs({ { x = cx - 8, y = 34 - lift, r = 7 }, { x = cx + 8, y = 34, r = 6 } }) do
    color(C.outline)
    love.graphics.circle("fill", e.x, e.y, e.r + 1)
    color(C.white)
    love.graphics.circle("fill", e.x, e.y, e.r)
    color(C.vein)
    love.graphics.line(e.x - e.r + 1, e.y + 1, e.x - e.r + 3, e.y + 2, e.x - e.r + 4, e.y + 1)
    love.graphics.line(e.x + e.r - 1, e.y - 1, e.x + e.r - 3, e.y - 2)
    local px = e.x + self.look[i] * (i == 1 and 1 or -0.8)
    local py = e.y + math.sin(t * 2.1 + i) * 1.2
    color(C.iris)
    love.graphics.circle("fill", px, py, 2.5)
    color(C.pupil)
    love.graphics.circle("fill", px, py, 1.2)
  end
  -- Brows: shoved right up in alarm, one higher than the other.
  color(C.hairDark)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - 15, 24 - lift, cx - 9, 22 - lift, cx - 3, 25)
  love.graphics.line(cx + 3, 26, cx + 9, 24, cx + 15, 27)
  love.graphics.setLineWidth(1)

  -- Nose: long and bent.
  color(C.outline)
  love.graphics.line(cx, 38, cx + 2, 45, cx - 2, 47)

  -- Mouth: a manic grin that keeps talking, one front tooth gone.
  local open = 2 + 2.5 * math.abs(math.sin(t * 10)) * (0.5 + 0.5 * math.abs(math.sin(t * 1.7)))
  color(C.outline)
  love.graphics.ellipse("fill", cx, 52, 10, open + 1.5)
  color(C.mouth)
  love.graphics.ellipse("fill", cx, 52, 9, open + 0.5)
  color(C.teeth)
  for k = 0, 5 do
    if k ~= 2 then
      love.graphics.rectangle("fill", cx - 8 + k * 3, 52 - open, 2, 2)
    end
  end
  -- A crumb stuck in the stubble.
  color(C.mustard)
  love.graphics.rectangle("fill", cx + 7, 56, 2, 1)

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, jittering
--- with nervous energy.
function Face:draw(x, y, scale)
  self:render()
  local jx = math.sin(self.t * 23) * scale * 0.25
  local bob = math.sin(self.t * 2.6) * scale * 0.6
  local tilt = math.sin(self.t * 1.3) * 0.06
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x + jx, y + bob, tilt, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
