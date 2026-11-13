-- Shoeman in the world, seen from above (docs/tutorial.md, "Cast"): the
-- figure every player is (`Body.person`), drawn bigger and heavier. Broad
-- navy shoulders, a belly pushing the shirt out in front, thick arms, and a
-- bald head with its shine and a grey fringe round the back.
--
-- The throw is one swing of his right arm, `throw` running 0 to 1: up to
-- WIND he draws the arm back with a shoe in his fist, the shoulders turning
-- with it and the left arm out in front to aim; then he whips it forward,
-- lets go at RELEASE and follows through. The shoe drawn in his hand and
-- the flying one (`ShoemanRender.shoe`, for shoe.lua) are the same shoe.
--
--   ShoemanRender.draw(x, y, angle, pose)  pose fields, all optional:
--     swing   this frame's stride (as Body.person)
--     throw   0 to 1 through a throw; nil standing
--     alpha   how solid
--   ShoemanRender.shoe(x, y, angle, scale, alpha)  a shoe pointing along angle

local Body = require("src.body")

local ShoemanRender = {}

ShoemanRender.SCALE = 1.5 -- drawn this much bigger than a player
ShoemanRender.RADIUS = Body.RADIUS * ShoemanRender.SCALE -- px, his size in the world
ShoemanRender.WIND = 0.6 -- throw fraction where the arm is all the way back
ShoemanRender.RELEASE = 0.68 -- throw fraction where the shoe leaves his hand

-- Matches the portrait (shoeman_face.lua).
local SKIN = { 0.93, 0.74, 0.62 }
local FRINGE = { 0.62, 0.63, 0.64 }
local SHIRT = { 0.13, 0.17, 0.33 }
local PANTS = { 0.20, 0.20, 0.22 }
local BOOTS = { 0.10, 0.09, 0.09 }
local LEATHER = { 0.45, 0.27, 0.14 }
local SOLE = { 0.12, 0.10, 0.09 }
local LACE = { 0.90, 0.88, 0.80 }

local SH = Body.SHOULDERS + 1.5 -- he is broader than anyone
local REST = { -0.5, SH + 1 } -- the right hand hanging at his side
local SHOE = 8 -- px, a shoe's length in his hand (before SCALE)

local alpha = 1
local function set(c, k, a)
  k = k or 1
  love.graphics.setColor(math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), (a or 1) * alpha)
end

local function lerp(a, b, k)
  return a + (b - a) * k
end

--- A shoe, toe along +x, centred, `len` px long, in the current transform:
--- a narrow heel, the wider ball of the foot, a round toe.
local function drawShoe(len)
  local w = len * 0.4
  local function outline(pad)
    love.graphics.ellipse("fill", -len * 0.25, 0, len * 0.25 + pad, w * 0.38 + pad, 10) -- heel
    love.graphics.ellipse("fill", len * 0.12, 0, len * 0.38 + pad, w * 0.5 + pad, 12) -- ball and toe
  end
  set(SOLE)
  outline(0.6)
  set(LEATHER)
  outline(0)
  set(SOLE, 1.6) -- the opening his foot goes in
  love.graphics.ellipse("fill", -len * 0.24, 0, len * 0.15, w * 0.24, 8)
  set(LACE) -- laces across the instep, in front of it
  love.graphics.setLineWidth(math.max(0.5, len * 0.06))
  for i = 0, 2 do
    local lx = len * (-0.04 + i * 0.09)
    love.graphics.line(lx, -w * 0.16, lx, w * 0.16)
  end
  love.graphics.setLineWidth(1)
  set(LEATHER, 1.35) -- the shine on the toe cap
  love.graphics.ellipse("fill", len * 0.34, -w * 0.15, len * 0.07, w * 0.1, 6)
end

--- A shoe at (x, y) in the world pointing along `angle`, `scale` times its
--- size in his hand. The flying shoe of shoe.lua.
function ShoemanRender.shoe(x, y, angle, scale, a)
  alpha = a or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  drawShoe(SHOE * ShoemanRender.SCALE * (scale or 1))
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
  alpha = 1
end

--- Where the hands are and how far the shoulders turn, `throw` through a
--- throw (nil standing). Returns right hand x, y, left hand x, y, twist and
--- whether the shoe is still held.
local function pose(throw, step)
  if not throw then
    return REST[1] + step * 0.9, REST[2], -step * 0.9, -SH - 1, 0, false
  end
  local W = ShoemanRender.WIND
  if throw < W then
    -- Winding up: the right arm goes back and out, the left comes forward.
    local k = throw / W
    k = k * k * (3 - 2 * k)
    return lerp(REST[1], -11, k), lerp(REST[2], SH + 4, k), lerp(0, 9, k), lerp(-SH - 1, -SH + 2, k), -0.45 * k, true
  end
  -- The whip forward and the follow-through, quick then easing off.
  local k = (throw - W) / (1 - W)
  k = 1 - (1 - k) * (1 - k)
  return lerp(-11, SH + 6, k),
    lerp(SH + 4, 1, k),
    lerp(9, -1, k),
    lerp(-SH + 2, -SH - 2, k),
    lerp(-0.45, 0.35, k),
    throw < ShoemanRender.RELEASE
end

--- Shoeman at (x, y) looking along `angle`; `p` is his pose (see the top).
function ShoemanRender.draw(x, y, angle, p)
  p = p or {}
  alpha = p.alpha or 1
  local step = (p.swing or 0) * 2.6
  local rx, ry, lx, ly, twist, holding = pose(p.throw, p.throw and 0 or step)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(ShoemanRender.SCALE)
  -- A shadow, cast down and right whichever way he faces.
  love.graphics.setColor(0, 0, 0, 0.3 * alpha)
  love.graphics.ellipse("fill", 2.5, 2.5, SH + 1, SH, 16)
  love.graphics.rotate(angle)
  -- Boots, planted wide when he throws.
  local plant = p.throw and 1.5 or 0
  set(BOOTS)
  love.graphics.ellipse("fill", step + 1.5 + plant, -4 - plant, 3.6, 2.3, 8)
  love.graphics.ellipse("fill", -step + 1.5 - plant, 4 + plant, 3.6, 2.3, 8)
  set(PANTS)
  love.graphics.ellipse("fill", -1.5, 0, 3.8, 6.4, 10)
  -- Everything above the hips turns with the throw.
  love.graphics.rotate(twist)
  -- Arms: thick, from the shoulders to the hands.
  set(SKIN, 0.9)
  love.graphics.setLineWidth(3.4)
  love.graphics.line(0.5, -SH + 2, lx, ly)
  love.graphics.line(0.5, SH - 2, rx, ry)
  love.graphics.setLineWidth(1)
  -- The belly, pushing the shirt out in front, then the shoulders.
  set(SHIRT)
  love.graphics.ellipse("fill", 2.6, 0, 4, SH - 3, 14)
  love.graphics.ellipse("fill", 0, 0, 4.8, SH, 18)
  set(SHIRT, 0.8)
  love.graphics.ellipse("fill", 0.3, -SH + 1, 3, 2.6, 8)
  love.graphics.ellipse("fill", 0.3, SH - 1, 3, 2.6, 8)
  set(SHIRT, 1.35)
  love.graphics.ellipse("fill", 1.4, -3, 2, 3.4, 10)
  set(SHIRT, 0.45, 0.8)
  love.graphics.ellipse("line", 0, 0, 4.8, SH, 18)
  -- Fists, the shoe in the right one while he still holds it.
  -- held by the heel, the toe sticking out past his knuckles.
  if holding then
    love.graphics.push()
    love.graphics.translate(rx, ry)
    love.graphics.rotate(math.atan2(ry - (SH - 2), rx - 0.5)) -- along the arm
    love.graphics.translate(4, 0)
    drawShoe(SHOE)
    love.graphics.pop()
  end
  set(SKIN)
  love.graphics.circle("fill", lx, ly, 2.4, 10)
  love.graphics.circle("fill", rx, ry, 2.4, 10)
  -- The head: bald, a grey fringe round the back, the shine on top.
  set(SKIN)
  love.graphics.circle("fill", 0.8, 0, 4, 14)
  set(FRINGE)
  love.graphics.arc("fill", "open", 0.6, 0, 4, math.pi * 0.62, math.pi * 1.38, 10)
  set(SKIN)
  love.graphics.circle("fill", 1.3, 0, 3.3, 14)
  set(SKIN, 1.12)
  love.graphics.circle("fill", 1.6, -1.2, 1.3, 8)
  set(SKIN, 0.5, 0.8)
  love.graphics.circle("line", 0.8, 0, 4, 14)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
  alpha = 1
end

return ShoemanRender
