-- Plasma rounds (a gun's `ball`: the plasma rifle): drawn as the plasma
-- haulers' bolts are (borderline/bolts.lua), purple with Bragium, only a
-- small ball instead of a big slow one. A glowing ball with a fading trail
-- behind it, and a little splash ring where it ends (a wall, somebody, or
-- the end of its flight). Only the look: the round itself is the weapons
-- feature's, flown and struck like any other.

local Damage = require("src.features.damage")

local Plasma = {}

Plasma.HOT = { 0.92, 0.75, 1.00 } -- the white-hot middle
Plasma.SPLASH_FOR = 0.3 -- seconds a splash shows

local splashes = {} -- { x, y, r, t }

--- The purple of a plasma hit (the damage feature's).
local function purple()
  return Damage.of("plasma").color
end

function Plasma.clear()
  splashes = {}
end

--- A round of `radius` px ended at (x, y): a splash a few times its size.
function Plasma.splash(x, y, radius)
  splashes[#splashes + 1] = { x = x, y = y, r = radius * 4, t = 0 }
end

function Plasma.update(dt)
  for i = #splashes, 1, -1 do
    splashes[i].t = splashes[i].t + dt
    if splashes[i].t > Plasma.SPLASH_FOR then
      table.remove(splashes, i)
    end
  end
end

--- Round `p` (x, y, vx, vy, age) as a ball of `radius` px. Its trail is
--- never longer than it has flown, so it doesn't start behind the gun.
function Plasma.drawBall(p, radius, clock)
  local C = purple()
  local speed = math.max(1, math.sqrt(p.vx * p.vx + p.vy * p.vy))
  local ux, uy = p.vx / speed, p.vy / speed
  local flown = p.age * speed
  love.graphics.setBlendMode("add")
  for k = 4, 1, -1 do -- the trail, fading behind it
    local back = k * radius * 1.8
    if back < flown then
      love.graphics.setColor(C[1], C[2], C[3], 0.12 * (5 - k))
      love.graphics.circle("fill", p.x - ux * back, p.y - uy * back, radius * (1 - k * 0.15), 10)
    end
  end
  love.graphics.setColor(C[1], C[2], C[3], 0.35)
  love.graphics.circle("fill", p.x, p.y, radius * 1.8 + math.sin(clock * 30 + p.x * 0.05) * 0.6, 12)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(C)
  love.graphics.circle("fill", p.x, p.y, radius, 10)
  love.graphics.setColor(Plasma.HOT)
  love.graphics.circle("fill", p.x, p.y, radius * 0.5, 8)
end

--- A gun charging at (x, y): a ball of plasma swelling there as `k` (0..1)
--- fills, crackling.
function Plasma.drawCharge(x, y, k, clock)
  local C = purple()
  local r = 3 + 7 * k
  love.graphics.setBlendMode("add")
  love.graphics.setColor(C[1], C[2], C[3], 0.25 + 0.25 * k)
  love.graphics.circle("fill", x, y, r * 2.2 + math.sin(clock * 25) * (1 + k), 14)
  love.graphics.setBlendMode("alpha")
  love.graphics.setColor(C)
  love.graphics.circle("fill", x, y, r, 12)
  love.graphics.setColor(Plasma.HOT)
  love.graphics.circle("fill", x, y, r * 0.5, 10)
  if k >= 1 then -- full: a ring pulsing round it
    love.graphics.setColor(Plasma.HOT[1], Plasma.HOT[2], Plasma.HOT[3], 0.5 + 0.5 * math.sin(clock * 12))
    love.graphics.circle("line", x, y, r * 2.6, 16)
  end
end

--- The splashes, over everyone.
function Plasma.drawSplashes()
  local C, H = purple(), Plasma.HOT
  for _, s in ipairs(splashes) do
    local k = s.t / Plasma.SPLASH_FOR
    love.graphics.setBlendMode("add")
    love.graphics.setColor(C[1], C[2], C[3], 0.5 * (1 - k))
    love.graphics.circle("fill", s.x, s.y, s.r * (0.4 + 0.6 * k), 16)
    love.graphics.setBlendMode("alpha")
    love.graphics.setColor(H[1], H[2], H[3], 1 - k)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", s.x, s.y, s.r * k, 16)
  end
  love.graphics.setLineWidth(1)
end

return Plasma
