-- The Combine's dead, as every screen draws them (city17.lua adds one on
-- each C17_DOWN): a soldier sprawled on the ground where he fell, knocked
-- over the way the round that dropped him was going, arms and legs flung
-- out a little differently each time, his mask's lenses gone dark, his gun
-- dropped by his hand and a pool spreading under him. They lie there for
-- `LIE` seconds and fade, `MAX` at most at once. Client only.

local Body = require("src.body")

local Corpses = {}

local LIE = 40 -- seconds one lies there
local FADE = 4 -- the last of them fading out
local MAX = 60 -- at most, the oldest go first
local POOL_TIME = 6 -- seconds the pool takes to spread
local POOL = { 0.32, 0.03, 0.05 }
local LENS_DEAD = { 0.16, 0.22, 0.27 }
local SIZE = 1.2 -- a little bigger than a standing soldier's figure: lying flat, he is all there is of him

local list = {} -- { x, y, angle, look, seed, t }

local function set(c, a, k)
  k = k or 1
  love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, a or 1)
end

local function hash(n)
  local v = math.sin(n * 12.9898) * 43758.5453
  return v - math.floor(v)
end

function Corpses.clear()
  list = {}
end

--- A soldier went down at (x, y), the round that did it going `angle`, in `look` (Body.person's).
function Corpses.add(x, y, angle, look)
  list[#list + 1] = { x = x, y = y, angle = angle + (love.math.random() - 0.5) * 0.6, look = look,
    seed = love.math.random(1000), t = 0 }
  while #list > MAX do
    table.remove(list, 1)
  end
end

function Corpses.update(dt)
  for i = #list, 1, -1 do
    list[i].t = list[i].t + dt
    if list[i].t > LIE then
      table.remove(list, i)
    end
  end
end

--- One, lying along +x (the head that way), from above.
local function sprawl(c, alpha)
  local look, s = c.look, c.seed
  local shirt, pants = look.shirt, look.pants
  local function limb(x0, y0, x1, y1, w, col, k)
    set(col, alpha, k)
    love.graphics.setLineWidth(w)
    love.graphics.line(x0, y0, x1, y1)
  end
  -- How this one fell: which arm went up, how far the legs splayed.
  local flip = hash(s) < 0.5 and 1 or -1
  local splay = 2 + hash(s + 1) * 5
  local reach = hash(s + 2)
  -- Shadow.
  love.graphics.setColor(0, 0, 0, 0.25 * alpha)
  love.graphics.ellipse("fill", -2, 1.5, 15, 7, 16)
  -- Legs, bent a little at the knee, boots at the ends.
  for _, side in ipairs({ -1, 1 }) do
    local kx, ky = -9, side * (3 + splay * 0.4)
    local fx, fy = -16 + (side == flip and 2 or 0), side * (3.5 + splay)
    limb(-4, side * 2.4, kx, ky, 3.8, pants, 1.6)
    limb(kx, ky, fx, fy, 3.4, pants, 1.4)
    set(look.shoes or Body.SHOES, alpha)
    love.graphics.ellipse("fill", fx - 1.5, fy, 2.6, 1.9, 8)
  end
  -- Arms: one flung up past the head, the other out to the side.
  local up = { 9 + reach * 3, flip * -(8 + reach * 3) }
  local out = { 1 - reach * 4, -flip * (11 + reach * 2) }
  limb(3, flip * -4.6, up[1], up[2], 3, shirt, 1.1)
  limb(3, -flip * -4.6, out[1], out[2], 3, shirt, 1.1)
  set(look.skin, alpha) -- gloved hands
  love.graphics.circle("fill", up[1], up[2], 1.9, 8)
  love.graphics.circle("fill", out[1], out[2], 1.9, 8)
  -- The torso, flat on the ground: fatigues and the armoured vest over them.
  set(shirt, alpha)
  love.graphics.ellipse("fill", 0, 0, 6.5, 5.6, 16)
  set(shirt, alpha * 0.8, 0.45)
  love.graphics.setLineWidth(1)
  love.graphics.ellipse("line", 0, 0, 6.5, 5.6, 16)
  if look.vest then
    set(look.vest, alpha)
    love.graphics.ellipse("fill", 0.5, 0, 4.8, 4.2, 14)
    set(look.vest, alpha, 0.75)
    love.graphics.setLineWidth(1)
    love.graphics.line(-3, 0, 4, 0) -- the vest's seam
  end
  set(pants, alpha, 1.5)
  love.graphics.ellipse("fill", -4.5, 0, 3, 4.4, 10) -- the belt and hips
  -- The head, turned a little aside: the hood, the mask, two dead lenses.
  local tilt = flip * 0.4
  love.graphics.push()
  love.graphics.translate(9.5, 0)
  love.graphics.rotate(tilt)
  set(look.hood or look.skin, alpha)
  love.graphics.circle("fill", -0.6, 0, 4.2, 12)
  set(look.skin, alpha)
  love.graphics.circle("fill", 0.8, 0, 3.3, 12)
  set(LENS_DEAD, alpha)
  love.graphics.circle("fill", 2.6, -1.5, 1, 6)
  love.graphics.circle("fill", 2.6, 1.5, 1, 6)
  love.graphics.pop()
  -- His gun, dropped by the hand that was out.
  local gx, gy = out[1] + 3, out[2] + flip * 3
  local ga = flip * (0.8 + reach)
  set({ 0.1, 0.1, 0.12 }, alpha)
  love.graphics.setLineWidth(2.6)
  love.graphics.line(gx, gy, gx + math.cos(ga) * 14, gy + math.sin(ga) * 14)
  set({ 0.35, 0.36, 0.42 }, alpha)
  love.graphics.setLineWidth(1)
  love.graphics.line(gx + math.cos(ga) * 4, gy + math.sin(ga) * 4 - 0.8, gx + math.cos(ga) * 14,
    gy + math.sin(ga) * 14 - 0.8)
end

function Corpses.draw()
  for _, c in ipairs(list) do
    local alpha = math.min(1, (LIE - c.t) / FADE)
    -- The pool under him, spreading out to one side.
    local k = math.min(1, c.t / POOL_TIME)
    local side = c.seed % 2 == 0 and 1 or -1
    local px, py = c.x - math.sin(c.angle) * side * 6 * k, c.y + math.cos(c.angle) * side * 6 * k
    love.graphics.setColor(POOL[1], POOL[2], POOL[3], 0.7 * alpha)
    for b = 0, 2 do
      local a = c.seed + b * 2.1
      love.graphics.circle("fill", px + math.cos(a) * 4 * k, py + math.sin(a) * 4 * k, (3 + b * 1.5) * k + 1.5, 14)
    end
    love.graphics.push()
    love.graphics.translate(c.x, c.y)
    love.graphics.rotate(c.angle)
    love.graphics.scale(SIZE)
    sprawl(c, alpha)
    love.graphics.pop()
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Corpses
