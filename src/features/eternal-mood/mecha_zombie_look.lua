-- How a Mecha Zombie looks (mecha_zombie.lua), seen from above at world
-- size, facing +x in its own frame: a zombie the UAC rebuilt. Its jumpsuit
-- torn over rotting skin, a steel spine down its back with a power cell
-- glowing in it and tubes into its neck; its right arm a plasma cannon, coils
-- along the barrel that glow as it charges; on its left a flamer, a pilot
-- light at its nozzle, and three talons past it; half its skull steel, a
-- red optic where the eye was.
--
-- Its poses: walking, the cannon forward; the cannon glowing (1, 2); the
-- pilot light flaring and the flame going (3, 4); talons up and out (5);
-- head thrown back, jaw wide, screaming (6).
--
--   Look.draw(m, clock)       m: mecha_zombie.lua's shown zombie (dx, dy, facing, move, moveAt, stride)
--   Look.drawBody(b, clock)   where one fell: b { x, y, angle }

local Look = {}

local C = {
  skin = { 0.40, 0.46, 0.34 },
  skinDark = { 0.26, 0.30, 0.22 },
  suit = { 0.46, 0.46, 0.48 },
  suitDark = { 0.30, 0.30, 0.33 },
  hivis = { 0.90, 0.72, 0.10 },
  steel = { 0.55, 0.57, 0.62 },
  steelDark = { 0.24, 0.25, 0.28 },
  ink = { 0.06, 0.05, 0.05 },
  plasma = { 0.50, 0.92, 1.00 },
  pilot = { 1.00, 0.55, 0.15 },
  optic = { 1.00, 0.15, 0.08 },
  blood = { 0.32, 0.03, 0.03 },
  talon = { 0.85, 0.86, 0.90 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- Its legs, stepping out under it by `stride`, steel braces down them.
local function legs(stride, still)
  for _, side in ipairs({ -1, 1 }) do
    local fx = still and 0 or math.sin(stride * 0.2) * 5 * side
    color(C.ink)
    love.graphics.ellipse("fill", fx + 1, side * 5, 5, 3.5, 10)
    color(C.suitDark)
    love.graphics.ellipse("fill", fx + 1, side * 5, 4, 2.6, 10)
    color(C.steel)
    love.graphics.line(fx - 2, side * 7, fx + 4, side * 7)
  end
end

--- The cannon on its right arm (+y): a barrel, coils along it glowing with
--- `charge` (0..1).
local function cannon(charge, clock)
  local y = 9
  color(C.ink)
  love.graphics.rectangle("fill", -2, y - 4.5, 24, 9, 3)
  color(C.steelDark)
  love.graphics.rectangle("fill", -1, y - 3.5, 22, 7, 2)
  color(C.steel)
  love.graphics.rectangle("fill", 17, y - 2.5, 6, 5, 1) -- the muzzle
  for k = 0, 2 do -- the coils
    local glow = charge > 0 and (0.5 + 0.5 * math.sin(clock * 30 + k)) * charge or 0.15
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.3 + 0.7 * glow)
    love.graphics.rectangle("fill", 3 + k * 5, y - 3.5, 2.5, 7)
  end
  if charge > 0 then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.5 * charge)
    love.graphics.circle("fill", 23, y, 4 + 4 * charge, 12)
    love.graphics.setBlendMode("alpha")
  end
end

--- The left arm (-y): the flamer and its pilot light (`flare` 0..1), the
--- talons past it, swung up and out when `up`.
local function flamerArm(flare, up, clock)
  local y = -9
  local reach = up and 14 or 18
  local out = up and -6 or 0
  color(C.ink)
  love.graphics.setLineWidth(6)
  love.graphics.line(0, y, reach, y + out)
  color(C.skin)
  love.graphics.setLineWidth(4)
  love.graphics.line(0, y, reach, y + out)
  love.graphics.setLineWidth(1)
  color(C.steelDark) -- the flamer strapped under the forearm
  love.graphics.rectangle("fill", 6, y + out * 0.5 + 1, 12, 5, 2)
  color(C.steel)
  love.graphics.rectangle("fill", 17, y + out * 0.5 + 2, 4, 3)
  local lit = 0.4 + 0.6 * flare
  love.graphics.setColor(C.pilot[1], C.pilot[2], C.pilot[3], lit)
  love.graphics.circle("fill", 22, y + out * 0.5 + 3.5, 1.5 + 2 * flare + math.sin(clock * 20) * 0.4, 8)
  color(C.talon) -- three talons
  love.graphics.setLineWidth(2)
  for k = -1, 1 do
    local tx, ty = reach + 9, y + out + k * 3.5 + (up and -3 or 0)
    love.graphics.line(reach, y + out + k * 1.5, tx, ty)
  end
  love.graphics.setLineWidth(1)
end

--- Its back: the torn jumpsuit over rotting skin, the hi-vis band, the steel
--- spine with its power cell, tubes into the neck.
local function torso(clock)
  color(C.ink)
  love.graphics.ellipse("fill", -1, 0, 9, 12, 18)
  color(C.suit)
  love.graphics.ellipse("fill", -1, 0, 8, 11, 18)
  color(C.skinDark) -- where it's torn through
  love.graphics.ellipse("fill", 2, 5, 3.5, 3, 8)
  color(C.blood, 0.8)
  love.graphics.ellipse("fill", -3, -6, 3, 2, 8)
  color(C.hivis)
  love.graphics.rectangle("fill", -4, -10.5, 3, 21)
  color(C.steelDark) -- the spine
  love.graphics.rectangle("fill", -9, -2, 10, 4, 1)
  color(C.steel)
  for k = 0, 2 do
    love.graphics.rectangle("fill", -8 + k * 3.5, -2.5, 2, 5)
  end
  love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.6 + 0.3 * math.sin(clock * 3)) -- the cell
  love.graphics.circle("fill", -7, 0, 2, 8)
  color(C.ink) -- tubes into the neck
  love.graphics.line(-2, -1.5, 3, -2.5)
  love.graphics.line(-2, 1.5, 3, 2.5)
end

--- Its head: rotting skin, half its skull steel, the red optic; thrown
--- back with its jaw open when `screaming`.
local function head(screaming, clock)
  local hx = screaming and 2 or 5
  color(C.ink)
  love.graphics.circle("fill", hx, 0, 5.5, 14)
  color(C.skin)
  love.graphics.circle("fill", hx, 0, 4.5, 14)
  color(C.steel) -- the steel half
  love.graphics.arc("fill", hx, 0, 4.5, -math.pi / 2, math.pi / 2, 10)
  local glow = 0.7 + 0.3 * math.sin(clock * 6)
  love.graphics.setColor(C.optic[1], C.optic[2], C.optic[3], glow)
  love.graphics.circle("fill", hx + 2.5, 1.5, 1.4, 8)
  if screaming then
    color(C.ink) -- the jaw wide
    love.graphics.ellipse("fill", hx + 3.5, 0, 2, 3, 8)
  end
end

function Look.draw(m, clock)
  local move = m.move or 0
  local since = clock - (m.moveAt or clock)
  local charge = move == 1 and math.min(1, since / 0.4) or move == 2 and 1 or 0
  local flare = move == 3 and math.min(1, since / 0.35) or move == 4 and 1 or 0
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 3, 4, 13, 12, 18)
  love.graphics.rotate(m.facing or 0)
  legs(m.stride or 0, move ~= 0)
  flamerArm(flare, move == 5, clock)
  torso(clock)
  cannon(charge, clock)
  head(move == 6, clock)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where one fell: sprawled, sparking out, blood and coolant under it.
function Look.drawBody(b, clock)
  love.graphics.push()
  love.graphics.translate(b.x, b.y)
  love.graphics.rotate(b.angle + 0.6)
  color(C.blood, 0.75)
  love.graphics.ellipse("fill", 2, 3, 18, 14, 18)
  love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.25) -- coolant
  love.graphics.ellipse("fill", -8, -6, 7, 4, 10)
  legs(0, true)
  flamerArm(0, false, clock)
  torso(clock)
  cannon(0, clock)
  head(false, clock)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", 0, 0, 10, 12, 14)
  if (clock * 2 + b.x) % 3 < 0.15 then -- a spark now and then
    love.graphics.setColor(C.plasma)
    love.graphics.circle("fill", -6, 1, 2, 6)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
