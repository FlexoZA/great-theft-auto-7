-- Drawing a bum and his shopping cart. He is the core's person
-- (src/body.lua) in a long brown coat and a red beanie, with a scruffy
-- beard and a bottle in a paper bag; his cart, piled with junk, stays
-- parked beside his bench whether he is on it or not.

local Body = require("src.body")

local Render = {}

local LOOK = {
  shirt = { 0.42, 0.34, 0.22 }, -- the coat
  pants = { 0.30, 0.28, 0.24 },
  skin = { 0.84, 0.68, 0.55 },
  hat = { 0.62, 0.18, 0.16 }, -- a beanie
  shoes = { 0.20, 0.16, 0.12 },
}
local BEARD = { 0.48, 0.44, 0.38 }
local BAG = { 0.66, 0.52, 0.34 }

local function set(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

--- A bum at (x, y) looking along `angle`. `swing` is his stride, `punch`
--- true while a fist lands, `sitting` true on his bench (feet out in front,
--- the bottle at his lips now and then: `sip` 0..1).
function Render.bum(x, y, angle, swing, punch, sitting, sip)
  LOOK.punch = punch or nil
  local hx, hy, rx, ry = Body.person(x, y, angle, swing, LOOK)
  local c, s = math.cos(angle), math.sin(angle)
  -- The beard, under his chin.
  set(BEARD)
  love.graphics.circle("fill", x + c * 4.2, y + s * 4.2, 2.6, 8)
  love.graphics.circle("fill", x + c * 3.4 - s * 2, y + s * 3.4 + c * 2, 1.6, 6)
  love.graphics.circle("fill", x + c * 3.4 + s * 2, y + s * 3.4 - c * 2, 1.6, 6)
  -- The bottle in its bag, in his left hand (lifted to his mouth for a sip).
  if not punch then
    local k = sitting and (sip or 0) or 0
    local bx, by = hx + (x + c * 5 - hx) * k, hy + (y + s * 5 - hy) * k
    love.graphics.push()
    love.graphics.translate(bx, by)
    love.graphics.rotate(angle)
    set(BAG)
    love.graphics.rectangle("fill", -2.5, -2, 6, 4, 1)
    set({ 0.25, 0.45, 0.25 })
    love.graphics.rectangle("fill", 3.5, -1, 2.5, 2) -- the neck
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1)
  return hx, hy, rx, ry
end

--- His shopping cart at (x, y), its handle towards `angle`: a wire basket
--- piled with bags and junk, four little wheels.
function Render.cart(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", -9, -13, 24, 30, 2)
  love.graphics.rotate(angle)
  love.graphics.setColor(0.12, 0.12, 0.13)
  for _, w in ipairs({ { -10, -9 }, { -10, 9 }, { 10, -8 }, { 10, 8 } }) do
    love.graphics.circle("fill", w[1], w[2], 2)
  end
  -- The junk, over the basket's floor.
  love.graphics.setColor(0.35, 0.35, 0.38)
  love.graphics.rectangle("fill", -10, -9, 20, 18, 2)
  love.graphics.setColor(0.15, 0.15, 0.17)
  love.graphics.circle("fill", -3, -3, 5, 10) -- a bin bag
  love.graphics.setColor(0.55, 0.42, 0.28)
  love.graphics.rectangle("fill", 1, -1, 8, 8, 1) -- a box
  love.graphics.setColor(0.25, 0.4, 0.65)
  love.graphics.circle("fill", -5, 5, 3, 8) -- a blanket
  love.graphics.setColor(0.8, 0.75, 0.3)
  love.graphics.circle("fill", 5, -6, 2, 6) -- a can
  -- The wire basket over it.
  love.graphics.setColor(0.78, 0.8, 0.82)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", -10, -9, 20, 18, 2)
  for i = -6, 6, 4 do
    love.graphics.line(i, -9, i, 9)
  end
  -- The handle, at the back.
  love.graphics.setLineWidth(2)
  love.graphics.line(-13, -9, -13, 9)
  love.graphics.setColor(0.8, 0.2, 0.15)
  love.graphics.line(-13, -4, -13, 4)
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Render
