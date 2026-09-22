-- The menu's crazy face. Drawn with primitives onto a 64x72 canvas every
-- frame and scaled up with nearest filtering, so it reads as pixel art and
-- animates cheaply: skewed eyes that drift and twitch independently (left
-- looks left, right looks right), blinks, a raised brow, and a knife
-- clenched in the teeth.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local C = {
  outline = { 0.08, 0.035, 0.05 },
  skin = { 0.90, 0.78, 0.62 },
  shade = { 0.76, 0.60, 0.44 },
  hair = { 0.16, 0.09, 0.06 },
  white = { 0.96, 0.96, 0.92 },
  blood = { 0.80, 0.18, 0.18 },
  iris = { 0.55, 0.82, 0.25 },
  pupil = { 0.04, 0.04, 0.05 },
  mouth = { 0.30, 0.05, 0.08 },
  gum = { 0.62, 0.16, 0.20 },
  teeth = { 0.95, 0.92, 0.82 },
  blade = { 0.78, 0.80, 0.84 },
  edge = { 1.00, 1.00, 1.00 },
  handle = { 0.42, 0.24, 0.12 },
  ring = { 0.65, 0.55, 0.30 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

function Face.new()
  local self = setmetatable({}, Face)
  self.canvas = Pixel.canvas(Face.W, Face.H)
  self.t = 0
  self.blink = 0 -- seconds of lid closed remaining
  self.nextBlink = 2 + love.math.random() * 3
  self.eyes = {
    { base = -4, jitter = 0, target = 0, timer = 0 }, -- left eye: looks left
    { base = 4, jitter = 0, target = 0, timer = 0 }, -- right eye: looks right
  }
  self.browTwitch = 0
  return self
end

function Face:update(dt)
  self.t = self.t + dt

  -- Blink.
  if self.blink > 0 then
    self.blink = self.blink - dt
  else
    self.nextBlink = self.nextBlink - dt
    if self.nextBlink <= 0 then
      self.blink = 0.09
      self.nextBlink = 1.5 + love.math.random() * 4
    end
  end

  -- Each pupil picks a new twitch target now and then and eases to it.
  for _, e in ipairs(self.eyes) do
    e.timer = e.timer - dt
    if e.timer <= 0 then
      e.target = (love.math.random() - 0.5) * 3
      e.timer = 0.3 + love.math.random() * 1.6
    end
    e.jitter = e.jitter + (e.target - e.jitter) * math.min(1, dt * 18)
  end

  self.browTwitch = math.max(0, self.browTwitch - dt)
  if love.math.random() < dt * 0.4 then
    self.browTwitch = 0.25
  end
end

local function spike(x0, y0, x1, y1, x2, y2)
  love.graphics.polygon("fill", x0, y0, x1, y1, x2, y2)
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- Hair: back mass and spikes.
  color(C.hair)
  love.graphics.ellipse("fill", cx, 26, 25, 16)
  local spikes = {
    { 10, 4 }, { 17, -2 }, { 24, 1 }, { 31, -4 }, { 38, 0 }, { 45, -3 }, { 52, 3 }, { 57, 9 }, { 7, 12 },
  }
  for i, s in ipairs(spikes) do
    local sway = math.sin(t * 2 + i) * 0.8
    spike(s[1] - 4, 22, s[1] + 4, 22, s[1] + sway, s[2])
  end

  -- Ears.
  color(C.outline)
  love.graphics.circle("fill", 10, 43, 5)
  love.graphics.circle("fill", 54, 43, 5)
  color(C.skin)
  love.graphics.circle("fill", 10, 43, 4)
  love.graphics.circle("fill", 54, 43, 4)
  color(C.shade)
  love.graphics.circle("fill", 10, 44, 2)
  love.graphics.circle("fill", 54, 44, 2)

  -- Head.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 42, 23, 27)
  color(C.skin)
  love.graphics.ellipse("fill", cx, 42, 22, 26)
  color(C.shade)
  love.graphics.ellipse("fill", cx - 2, 54, 18, 12) -- jaw shadow
  color(C.skin)
  love.graphics.ellipse("fill", cx, 40, 20, 18)

  -- Fringe hanging over the forehead.
  color(C.hair)
  love.graphics.ellipse("fill", cx, 22, 22, 7)
  spike(12, 24, 20, 24, 14, 32)
  spike(24, 24, 32, 24, 30, 30)
  spike(38, 24, 46, 24, 44, 31)

  -- Eyes: left is wide open and big, right is smaller and higher (mad).
  local blink = self.blink > 0
  local eyes = { { x = 22, y = 37, r = 8 }, { x = 43, y = 34, r = 6 } }
  for i, e in ipairs(eyes) do
    color(C.outline)
    love.graphics.circle("fill", e.x, e.y, e.r + 1)
    color(C.white)
    love.graphics.circle("fill", e.x, e.y, e.r)
    -- bloodshot veins from the rim inwards
    color(C.blood)
    for k = 0, 5 do
      local a = k * 1.05 + i
      local ca, sa = math.cos(a), math.sin(a)
      love.graphics.line(e.x + ca * e.r, e.y + sa * e.r, e.x + ca * (e.r - 3), e.y + sa * (e.r - 3))
    end
    -- pupil: skewed outwards, drifting and twitching
    local st = self.eyes[i]
    local drift = math.sin(t * 1.3 + i * 2) * 1.2
    local px = e.x + st.base + drift + st.jitter
    local py = e.y + math.sin(t * 0.8 + i) * 0.8
    color(C.iris)
    love.graphics.circle("fill", px, py, e.r * 0.5)
    color(C.pupil)
    love.graphics.circle("fill", px, py, e.r * 0.3)
    color(C.edge)
    love.graphics.rectangle("fill", px - 1, py - 2, 1, 1)
    if blink then
      color(C.skin)
      love.graphics.circle("fill", e.x, e.y, e.r + 1)
      color(C.outline)
      love.graphics.line(e.x - e.r, e.y, e.x + e.r, e.y)
    end
  end

  -- Brows: left slammed down (angry), right arched high (twitching).
  color(C.outline)
  love.graphics.setLineWidth(2)
  love.graphics.line(13, 27, 30, 31)
  local lift = self.browTwitch > 0 and 2 or 0
  love.graphics.line(36, 26 - lift, 43, 22 - lift, 50, 25 - lift)
  love.graphics.setLineWidth(1)

  -- Scar on the right cheek.
  love.graphics.line(48, 40, 52, 50)
  love.graphics.line(48, 43, 51, 42)
  love.graphics.line(50, 47, 53, 46)

  -- Nose.
  love.graphics.line(31, 42, 30, 47, 33, 47)

  -- Mouth: a wide manic grin.
  color(C.outline)
  love.graphics.ellipse("fill", cx, 56, 15, 6)
  color(C.mouth)
  love.graphics.ellipse("fill", cx, 56, 14, 5)
  color(C.gum)
  love.graphics.ellipse("fill", cx, 53, 12, 2)

  -- Knife clenched across the mouth: blade points left, handle right.
  local ka = math.sin(t * 2.2) * 0.04
  love.graphics.push()
  love.graphics.translate(cx, 56)
  love.graphics.rotate(ka)
  color(C.outline)
  love.graphics.polygon("fill", -32, 0, -22, -4, 12, -4, 12, 3, -22, 3)
  color(C.blade)
  love.graphics.polygon("fill", -30, 0, -22, -3, 11, -3, 11, 2, -22, 2)
  color(C.edge)
  love.graphics.line(-29, 0, -22, -3, 10, -3)
  color(C.outline)
  love.graphics.rectangle("fill", 11, -5, 4, 9) -- guard
  love.graphics.rectangle("fill", 15, -3, 17, 6)
  color(C.handle)
  love.graphics.rectangle("fill", 15, -2, 16, 4)
  color(C.ring)
  love.graphics.rectangle("fill", 19, -2, 1, 4)
  love.graphics.rectangle("fill", 25, -2, 1, 4)
  love.graphics.pop()

  -- Teeth biting the blade: upper row over it, lower row under it.
  color(C.teeth)
  for k = 0, 5 do
    love.graphics.rectangle("fill", 21 + k * 4, 51, 3, 3)
    love.graphics.rectangle("fill", 22 + k * 4, 59, 3, 2)
  end

  -- Stubble.
  color(C.outline, 0.5)
  for k = 0, 14 do
    local sx = 20 + (k * 7) % 24
    local sy = 60 + (k * 5) % 7
    love.graphics.rectangle("fill", sx, sy, 1, 1)
  end

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, with a bob
--- and a slow tilt.
function Face:draw(x, y, scale)
  self:render()
  local bob = math.sin(self.t * 1.6) * scale * 0.6
  local tilt = math.sin(self.t * 0.7) * 0.03
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x, y + bob, tilt, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
