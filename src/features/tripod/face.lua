-- The tripod's face, for its portrait. Drawn with primitives onto a 64x72
-- canvas every frame and scaled up with nearest filtering, the way the
-- other bosses' are. It has no face, which is the point: a wide flat head
-- of dark armour under a heavy brow, seen from below against a burning
-- sky, one great lens in the middle of it whose shutter opens and shuts as
-- it looks you over, and two small lights either side. The heat ray rears
-- up off its back on a snaking neck like a cobra, its own lens glowing.
-- Tentacles hang underneath and feel about, the tops of the three legs go
-- down out of the frame, and red weed creeps up round them. Every so often
-- it sounds its horn: the lens flares white and the whole thing shudders.

local Pixel = require("src.art.pixel")

local Face = {}
Face.__index = Face

Face.W, Face.H = 64, 72

local HORN_EVERY = 5 -- seconds between blasts on the horn
local HORN_LENGTH = 1.6 -- seconds a blast lasts

local C = {
  outline = { 0.05, 0.05, 0.06 },
  metal = { 0.40, 0.43, 0.41 },
  metalDark = { 0.22, 0.24, 0.24 },
  metalLight = { 0.62, 0.65, 0.60 },
  under = { 0.14, 0.15, 0.16 },
  glow = { 0.60, 0.88, 1.00 },
  white = { 1.00, 0.98, 0.90 },
  shutter = { 0.10, 0.11, 0.12 },
  tentacle = { 0.30, 0.31, 0.30 },
  tip = { 0.50, 0.38, 0.36 },
  weed = { 0.62, 0.10, 0.08 },
  weedLight = { 0.82, 0.20, 0.14 },
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

--- 0 when quiet, rising to 1 and back over a blast on the horn.
function Face:horn()
  local h = (self.t % HORN_EVERY) - (HORN_EVERY - HORN_LENGTH)
  if h < 0 then
    return 0
  end
  return math.sin(h / HORN_LENGTH * math.pi)
end

--- A tentacle hanging from (x, y), swaying, `len` long.
local function tentacle(x, y, len, t, seed)
  local px, py = x, y
  for i = 1, 8 do
    local k = i / 8
    local nx = x + math.sin(t * 1.7 + seed + k * 3) * 5 * k
    local ny = y + len * k
    color(i >= 7 and C.tip or C.tentacle)
    love.graphics.setLineWidth(i < 4 and 3 or (i < 7 and 2 or 1))
    love.graphics.line(px, py, nx, ny)
    px, py = nx, ny
  end
  love.graphics.setLineWidth(1)
end

--- A leg top: a thick strut from the underside down out of the frame.
local function strut(x1, y1, x2, y2, w)
  color(C.outline)
  love.graphics.setLineWidth(w + 2)
  love.graphics.line(x1, y1, x2, y2)
  color(C.metalDark)
  love.graphics.setLineWidth(w)
  love.graphics.line(x1, y1, x2, y2)
  color(C.metal, 0.8)
  love.graphics.setLineWidth(1)
  love.graphics.line(x1 - 1, y1, x2 - 1, y2)
end

function Face:render()
  local t = self.t
  local cx = Face.W / 2
  local horn = self:horn()

  love.graphics.push("all")
  love.graphics.setCanvas(self.canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.setLineWidth(1)

  -- Legs going down: two splayed out to the sides, one behind and between.
  strut(cx, 36, cx + 2, 72, 3)
  strut(cx - 18, 38, cx - 30, 72, 5)
  strut(cx + 18, 38, cx + 30, 72, 5)
  color(C.metalLight) -- the hip joints
  love.graphics.circle("fill", cx - 18, 38, 3)
  love.graphics.circle("fill", cx + 18, 38, 3)

  -- Red weed creeping up round the feet of the legs: thin crimson
  -- tendrils curling as they grow.
  for i, w in ipairs({ { cx - 34, 1 }, { cx - 27, -1 }, { cx - 20, 1 }, { cx + 26, 1 }, { cx + 33, -1 },
    { cx - 4, 1 }, { cx + 7, -1 } }) do
    local grow = 7 + (i % 3) * 3 + math.sin(t * 0.6 + i) * 1.5
    local curl = math.sin(t * 0.9 + i * 1.7) * 2
    color(i % 2 == 0 and C.weedLight or C.weed)
    love.graphics.line(w[1], 72, w[1] + w[2] * 2, 72 - grow * 0.5, w[1] + curl + w[2] * 3, 72 - grow)
    love.graphics.points(w[1] + curl + w[2] * 3, 71 - grow)
  end

  -- Tentacles out from under the head, feeling about.
  tentacle(cx - 10, 36, 24, t, 0)
  tentacle(cx + 9, 36, 20, t, 2.2)
  tentacle(cx - 3, 37, 14, t, 4.1)

  -- The heat ray on its neck, rearing up off the back, swaying like a
  -- cobra, drawn behind the head so it rises out from over the brow.
  local sway = math.sin(t * 1.1) * 4
  local nx, ny = cx + 6 + sway, 4
  color(C.outline)
  love.graphics.setLineWidth(5)
  love.graphics.line(cx + 4, 20, cx + 8 + sway * 0.4, 12, nx, ny + 5)
  color(C.metalDark)
  love.graphics.setLineWidth(3)
  love.graphics.line(cx + 4, 20, cx + 8 + sway * 0.4, 12, nx, ny + 5)
  love.graphics.setLineWidth(1)
  color(C.outline) -- the hood
  love.graphics.polygon("fill", nx - 6, ny + 4, nx - 3, ny - 2, nx + 3, ny - 2, nx + 6, ny + 4, nx, ny + 8)
  color(C.metal)
  love.graphics.polygon("fill", nx - 5, ny + 4, nx - 2, ny - 1, nx + 2, ny - 1, nx + 5, ny + 4, nx, ny + 7)
  local charge = 0.5 + 0.5 * math.sin(t * 3)
  color(C.glow, 0.35 + 0.4 * charge)
  love.graphics.circle("fill", nx, ny + 3, 3)
  color(C.white, 0.7 + 0.3 * charge)
  love.graphics.circle("fill", nx, ny + 3, 1.2)

  -- The head: a wide flat shield, dark underneath, a heavy brow jutting over
  -- the lens, plates across the top.
  color(C.outline)
  love.graphics.polygon("fill", 1, 30, 8, 20, 22, 15, 42, 15, 56, 20, 63, 30, 52, 39, 12, 39)
  color(C.under)
  love.graphics.polygon("fill", 3, 30, 61, 30, 51, 38, 13, 38)
  color(C.metalDark)
  love.graphics.polygon("fill", 3, 29, 9, 21, 22, 16, 42, 16, 55, 21, 61, 29, 52, 34, 12, 34)
  color(C.metal)
  love.graphics.polygon("fill", 10, 23, 22, 18, 42, 18, 54, 23, 48, 28, 16, 28)
  color(C.metalLight)
  love.graphics.polygon("fill", 22, 19, 42, 19, 38, 22, 26, 22)
  color(C.outline) -- seams between the plates
  love.graphics.line(cx, 16, cx, 22)
  love.graphics.line(18, 19, 15, 27)
  love.graphics.line(46, 19, 49, 27)
  love.graphics.line(8, 26, 3, 29)
  love.graphics.line(56, 26, 61, 29)
  -- The brow, jutting over the lens.
  color(C.outline)
  love.graphics.polygon("fill", 18, 27, 46, 27, 42, 31, 22, 31)
  color(C.metalDark)
  love.graphics.polygon("fill", 19, 27, 45, 27, 41, 30, 23, 30)

  -- The lens, under the brow: a glowing eye behind a shutter of blades
  -- that opens and closes as it looks you over, wide open on the horn.
  local ey = 33
  local open = math.max(horn, 0.35 + 0.3 * math.sin(t * 0.9) + 0.15 * math.sin(t * 2.7))
  color(C.outline)
  love.graphics.circle("fill", cx, ey, 8)
  color(C.glow, 0.5 + 0.5 * horn)
  love.graphics.circle("fill", cx, ey, 7)
  color(C.white, 0.6 + 0.4 * horn)
  love.graphics.circle("fill", cx, ey, 2 + 3 * open)
  color(C.shutter)
  for k = 0, 5 do
    local a = k / 6 * math.pi * 2 + t * 0.3
    local r = 7 - 5 * open
    local bx, by = cx + math.cos(a) * 7, ey + math.sin(a) * 7
    local ex, ey2 = cx + math.cos(a + 1.2) * r, ey + math.sin(a + 1.2) * r
    love.graphics.polygon("fill", bx, by, cx + math.cos(a + 1) * 7, ey + math.sin(a + 1) * 7, ex, ey2)
  end
  color(C.outline)
  love.graphics.circle("line", cx, ey, 7.5)

  -- Two small lights either side, blinking out of step.
  for side = -1, 1, 2 do
    local on = math.sin(t * 2 + side) > -0.6 and 1 or 0.3
    color(C.glow, 0.3 * on)
    love.graphics.circle("fill", cx + side * 16, 32, 2.5)
    color(C.glow, on)
    love.graphics.rectangle("fill", cx + side * 16 - 1, 31, 2, 2)
  end

  -- On the horn: the light spills out of the lens in rings.
  if horn > 0 then
    for i = 0, 2 do
      local r = 9 + i * 5 + horn * 4
      color(C.glow, horn * (0.45 - i * 0.12))
      love.graphics.circle("line", cx, ey, r)
    end
  end

  love.graphics.setCanvas()
  love.graphics.pop()
  return self.canvas
end

--- Draw centred at (x, y), `scale` screen pixels per art pixel, rising and
--- falling slowly on its legs, shuddering while it sounds the horn.
function Face:draw(x, y, scale)
  self:render()
  local horn = self:horn()
  local bob = math.sin(self.t * 0.8) * scale * 0.6
  local shake = horn > 0 and (love.math.random() - 0.5) * scale * horn or 0
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(self.canvas, x + shake, y + bob, 0, scale, scale, Face.W / 2, Face.H / 2)
end

return Face
