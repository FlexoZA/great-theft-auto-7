-- The Antlion Guard, drawn from above: the Coast's boss, an antlion grown
-- huge and armoured, after Half-Life's. About four times an antlion. No
-- wings and no sickle mandibles: a great shovel of a head plate out in
-- front, ridged and scarred, two short tusks under it, a humped back of
-- overlapping plates and a heavy ribbed abdomen, on six thick legs (the
-- front pair the biggest, it leans on them).
--
-- What it can be doing, besides walking:
--   swipe    the head swings across in a backhand, `swipe` 0..1 through it
--   paw      pawing the sand before a charge: head down, front legs digging
--   charge   head down and lunging, legs at full stretch, sand kicked up
--   rear     rearing up to scream: drawn bigger at the front, head lifted
--   scream   the head thrown back and the mouth wide, the plates flared
--   stunned  reeling from running into something: wobbling, stars over it
--   burrow   coming up out of the sand (1 under, 0 out)
--   dead     on its back, legs curled
--
-- Stateless like the antlion's: everything takes what to draw and the clock.

local Ant = require("src.features.antlions.render")

local Render = {}

Render.SHELL = { 0.62, 0.48, 0.26 }
Render.SHELL_LIGHT = { 0.78, 0.64, 0.38 }
Render.SHELL_DARK = { 0.40, 0.29, 0.14 }
Render.PLATE = { 0.54, 0.44, 0.30 } -- the head plate: duller, older
Render.PLATE_LIGHT = { 0.70, 0.60, 0.44 }
Render.SEAM = { 0.24, 0.17, 0.08 }
Render.LEG = { 0.36, 0.26, 0.13 }
Render.CLAW = { 0.18, 0.13, 0.06 }
Render.MOUTH = { 0.45, 0.12, 0.10 }
Render.BELLY = { 0.74, 0.64, 0.46 }

Render.RADIUS = 34 -- px; the body, for hitting it
local SCALE = 2.1 -- the model below is drawn this size
local HEIGHT = 9 -- px its shadow falls away, down and right
local STRIDE = 9
local STANCE = 0.6

-- Legs in the body's frame, as the antlion's: hip, planted foot, knee, gait half, thickness.
local LEGS = {
  { hip = { 6, -7 }, foot = { 20, -20 }, knee = 6, beat = 0, w = 4.2 }, -- front left: the big ones
  { hip = { 6, 7 }, foot = { 20, 20 }, knee = 6, beat = 0.5, w = 4.2 },
  { hip = { -2, -8 }, foot = { -1, -24 }, knee = 5, beat = 0.5, w = 3.2 },
  { hip = { -2, 8 }, foot = { -1, 24 }, knee = 5, beat = 0, w = 3.2 },
  { hip = { -8, -7 }, foot = { -20, -21 }, knee = 5, beat = 0, w = 3 },
  { hip = { -8, 7 }, foot = { -20, 21 }, knee = 5, beat = 0.5, w = 3 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local function tint(c, hurt, sand)
  return mix(mix(c, { 1, 1, 1 }, hurt), Ant.SAND, sand)
end

local function leg(l, cycle, stride, reach, tuck)
  local p = (cycle + l.beat) % 1
  local along, up
  if p < STANCE then
    along, up = 0.5 - p / STANCE, 0
  else
    local k = (p - STANCE) / (1 - STANCE)
    along, up = -0.5 + k, math.sin(k * math.pi)
  end
  local fx, fy = l.foot[1] + along * STRIDE * stride + reach, l.foot[2]
  local hx, hy = l.hip[1], l.hip[2]
  fx, fy = fx + (hx - fx) * tuck * 0.55, fy + (hy - fy) * tuck * 0.55
  local dx, dy = fx - hx, fy - hy
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local nx, ny = -dy / d, dx / d
  if ny * hy < 0 then
    nx, ny = -nx, -ny
  end
  local out = l.knee + up * stride * 3 + tuck * 3
  return fx, fy, hx + dx * 0.45 + nx * out, hy + dy * 0.45 + ny * out
end

local function drawLeg(l, fx, fy, kx, ky, hurt, sand)
  color(tint(Render.LEG, hurt, sand))
  love.graphics.setLineWidth(l.w)
  love.graphics.line(l.hip[1], l.hip[2], kx, ky)
  love.graphics.setLineWidth(l.w * 0.7)
  love.graphics.line(kx, ky, fx, fy)
  color(tint(Render.SHELL_DARK, hurt, sand))
  love.graphics.circle("fill", kx, ky, l.w * 0.75, 8)
  color(tint(Render.CLAW, hurt, sand))
  local dx, dy = fx - kx, fy - ky
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  love.graphics.setLineWidth(l.w * 0.5)
  love.graphics.line(fx, fy, fx + dx / d * 4, fy + dy / d * 4)
end

local function body(hurt, sand, flare)
  -- The heavy abdomen, ribbed across.
  color(tint(Render.SHELL_DARK, hurt, sand))
  love.graphics.ellipse("fill", -17, 0, 15, 13, 20)
  color(tint(Render.SHELL, hurt, sand))
  love.graphics.ellipse("fill", -17, 0, 14, 12, 20)
  color(tint(Render.SEAM, hurt, sand), 0.7)
  love.graphics.setLineWidth(1.2)
  for k = 0, 4 do
    local x = -8 - k * 4.4
    love.graphics.arc("line", "open", x + 4, 0, 11 - math.abs(k - 1.5) * 1.3, math.pi * 0.62, math.pi * 1.38, 10)
  end
  -- The humped back: overlapping plates from the thorax over the abdomen,
  -- standing up (wider) when it flares.
  for k = 0, 3 do
    local x = 2 - k * 6
    local half = (10 - k * 0.6) * (1 + flare * 0.25)
    color(tint(k % 2 == 0 and Render.SHELL or Render.SHELL_DARK, hurt, sand))
    love.graphics.polygon("fill", x + 3, -half * 0.75, x + 4, 0, x + 3, half * 0.75, x - 3, half, x - 4.5, 0,
      x - 3, -half)
    color(tint(Render.SHELL_LIGHT, hurt, sand), 0.7)
    love.graphics.setLineWidth(1)
    love.graphics.line(x + 2.5, -half * 0.6, x + 2.5, half * 0.6)
  end
end

--- The head: a broad shovel of a plate, tusks under it, the mouth showing when it opens.
local function head(lift, mouth, hurt, sand)
  local x = 10 + lift * 3
  -- Tusks first, under the plate.
  color(tint(Render.CLAW, hurt, sand))
  love.graphics.setLineWidth(2.6)
  love.graphics.line(x + 8, -6, x + 15, -8 - mouth * 3, x + 18, -5 - mouth * 4)
  love.graphics.line(x + 8, 6, x + 15, 8 + mouth * 3, x + 18, 5 + mouth * 4)
  if mouth > 0 then
    color(tint(Render.MOUTH, hurt, sand))
    love.graphics.ellipse("fill", x + 10, 0, 4 + mouth * 3, 3 + mouth * 3, 12)
    color(Render.CLAW)
    for k = -1, 1 do
      love.graphics.circle("fill", x + 12 + mouth * 2, k * (2 + mouth * 2), 0.9, 4)
    end
  end
  -- The plate: wide at the front, scalloped edge, a ridge down the middle.
  color(tint(Render.SHELL_DARK, hurt, sand))
  love.graphics.polygon("fill", x - 4, -9, x + 6, -15, x + 13, -13, x + 16, -6, x + 16, 6, x + 13, 13,
    x + 6, 15, x - 4, 9)
  color(tint(Render.PLATE, hurt, sand))
  love.graphics.polygon("fill", x - 3, -8, x + 6, -13.5, x + 12, -11.8, x + 14.6, -5.5, x + 14.6, 5.5,
    x + 12, 11.8, x + 6, 13.5, x - 3, 8)
  color(tint(Render.PLATE_LIGHT, hurt, sand))
  love.graphics.setLineWidth(1.6)
  love.graphics.line(x - 1, 0, x + 13, 0)
  love.graphics.line(x + 3, -10, x + 11, -5)
  love.graphics.line(x + 3, 10, x + 11, 5)
  color(tint(Render.SEAM, hurt, sand), 0.8) -- old scars
  love.graphics.setLineWidth(1)
  love.graphics.line(x + 7, 4, x + 10, 9)
  love.graphics.line(x + 5, -6, x + 8, -3)
  -- Eyes set low and to the sides, under the plate's edge.
  color({ 0.08, 0.06, 0.04 })
  love.graphics.circle("fill", x + 1, -9, 1.6, 6)
  love.graphics.circle("fill", x + 1, 9, 1.6, 6)
end

--- The Guard at (x, y) facing `angle`. `g` (all optional): cycle, stride,
--- swipe (0..1), paw, charge, rear, scream (true), stunned, burrow (0..1),
--- hurt (0..1), dead, alpha.
function Render.draw(x, y, angle, g, clock)
  g = g or {}
  clock = clock or 0
  local hurt, burrow = g.hurt or 0, g.burrow or 0
  if burrow > 0 then
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(2.4)
    Ant.mound(0, 0, math.min(1, burrow * 2), clock)
    love.graphics.pop()
  end
  if burrow >= 1 then
    return
  end
  local stride = g.stride or 0
  local cycle = g.cycle or 0
  local reach, tuck, lift, mouth, flare, sway = 0, g.dead and 1 or 0, 0, 0, 0, 0
  if g.paw then
    reach, lift = 3 * math.sin(clock * 14), -2
    stride = math.max(stride, 0.5)
  elseif g.charge then
    reach, lift, stride = 4, -2, 1
  elseif g.rear then
    lift, flare, reach = 3, 0.6, -3
  elseif g.scream then
    lift, mouth, flare = 4, 1, 1
  end
  if g.stunned then
    sway = math.sin(clock * 9) * 0.25
  end
  local headTurn = 0
  if g.swipe then
    headTurn = math.sin(g.swipe * math.pi * 2) * 0.6 -- across one way and back
    mouth = math.max(mouth, 0.4)
  end
  local size = SCALE * (1 - burrow * 0.3) * (1 + (g.rear and 0.06 or 0) + (g.scream and 0.08 or 0))
  -- Shadow.
  love.graphics.push()
  love.graphics.translate(x + HEIGHT, y + HEIGHT)
  love.graphics.rotate(angle + sway)
  love.graphics.scale(size)
  love.graphics.setColor(0, 0, 0, 0.25 * (1 - burrow) * (g.alpha or 1))
  love.graphics.ellipse("fill", -15, 0, 15, 13, 18)
  love.graphics.ellipse("fill", 8, 0, 11, 14, 16)
  love.graphics.pop()

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle + sway)
  love.graphics.scale(size)
  if g.dead then
    color(Render.BELLY, g.alpha or 1)
    love.graphics.ellipse("fill", -17, 0, 14, 12, 20)
    love.graphics.ellipse("fill", 1, 0, 9, 9, 16)
    color(Render.PLATE, g.alpha or 1)
    love.graphics.ellipse("fill", 14, 0, 6, 12, 14)
    color(Render.SEAM, 0.6 * (g.alpha or 1))
    love.graphics.setLineWidth(1.2)
    for k = 0, 4 do
      love.graphics.line(-8 - k * 4.4, -9, -8 - k * 4.4, 9)
    end
    for _, l in ipairs(LEGS) do
      local fx, fy, kx, ky = leg(l, 0, 0, 0, 1)
      drawLeg(l, fx, fy, kx, ky, 0, 0)
    end
    love.graphics.pop()
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    return
  end
  local legs = {}
  for i, l in ipairs(LEGS) do
    legs[i] = { leg(l, cycle, stride, i <= 2 and reach or 0, tuck) }
  end
  for i = 3, 6 do
    drawLeg(LEGS[i], legs[i][1], legs[i][2], legs[i][3], legs[i][4], hurt, burrow)
  end
  body(hurt, burrow, flare)
  for i = 1, 2 do
    drawLeg(LEGS[i], legs[i][1], legs[i][2], legs[i][3], legs[i][4], hurt, burrow)
  end
  love.graphics.push()
  love.graphics.translate(6, 0)
  love.graphics.rotate(headTurn)
  love.graphics.translate(-6, 0)
  head(lift, mouth, hurt, burrow)
  love.graphics.pop()
  love.graphics.pop()
  if g.charge then -- sand thrown up behind it
    for k = 0, 5 do
      local a = angle + math.pi + (k - 2.5) * 0.25
      local d = 40 + ((clock * 160 + k * 17) % 50)
      color(Ant.SAND, 0.6 * (1 - ((clock * 160 + k * 17) % 50) / 50))
      love.graphics.circle("fill", x + math.cos(a) * d, y + math.sin(a) * d, 4 + k % 3, 6)
    end
  end
  if g.stunned then -- stars wheeling over it
    for k = 0, 2 do
      local a = clock * 4 + k * 2.1
      local sx, sy = x + math.cos(a) * 26, y - 30 + math.sin(a) * 8
      love.graphics.setColor(1, 0.92, 0.4)
      love.graphics.circle("fill", sx, sy, 3, 5)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- The scream on the ground: while it rears (`k` 0..1 filling), a cone
--- where it will go; once it goes (`wave` 0..1), rings rolling out along it.
function Render.cone(x, y, angle, range, half, k, wave)
  local segs = 20
  local pts = { x, y }
  for i = 0, segs do
    local a = angle - half + i / segs * 2 * half
    pts[#pts + 1], pts[#pts + 2] = x + math.cos(a) * range, y + math.sin(a) * range
  end
  if wave then
    -- The air itself shoved along the cone: a bright front and rings behind it.
    love.graphics.setColor(1, 0.92, 0.75, 0.3 * (1 - wave))
    love.graphics.polygon("fill", pts)
    for ring = 0, 4 do
      local r = (wave * 1.15 - ring * 0.1) * range
      if r > 0 and r <= range then
        local front = ring == 0
        love.graphics.setColor(1, front and 1 or 0.9, front and 0.95 or 0.7, (front and 0.95 or 0.6) * (1 - wave * 0.8))
        love.graphics.setLineWidth(front and 12 or 7 - ring)
        love.graphics.arc("line", "open", x, y, r, angle - half, angle + half, segs)
      end
    end
  else
    love.graphics.setColor(1, 0.35, 0.2, 0.1 + 0.15 * k)
    love.graphics.polygon("fill", pts)
    love.graphics.setColor(1, 0.4, 0.25, 0.6)
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", pts)
    love.graphics.setColor(1, 0.5, 0.3, 0.35)
    love.graphics.arc("line", "open", x, y, range * k, angle - half, angle + half, segs)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
