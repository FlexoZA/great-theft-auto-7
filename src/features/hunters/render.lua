-- A Hunter, drawn from above: the Combine's tripod hunter, about twice a
-- man's height. A swollen, sack-like body under ribbed grey-brown armour
-- plates rides on three long legs, two out front and one behind, their
-- knees jutting up and out past the body the way a spider's do. The head is
-- the blunt front end of the body: a dark face plate with a cluster of
-- glowing blue lights, and two flechette pods slung under it, pointing the
-- way it faces. It walks in a quick, skittering gait and leans into a
-- dodge, leaving a smear of itself behind.
--
-- The camera looks straight down, so height shows in the shadow, which
-- falls off down and right, and in how big a raised foot is drawn.
--
-- Nothing here keeps state: everything takes what to draw and the clock,
-- so the fight and anything else that shows a Hunter draw the same thing.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.HIDE = { 0.36, 0.33, 0.31 } -- the body under the plates
Render.PLATE = { 0.52, 0.50, 0.47 }
Render.PLATE_DARK = { 0.40, 0.38, 0.36 }
Render.FACE = { 0.18, 0.19, 0.21 }
Render.LEG = { 0.20, 0.20, 0.22 }
Render.GLOW = { 0.45, 0.85, 1.00 }
Render.SPARK = { 0.75, 0.92, 1.00 }

-- Size ---------------------------------------------------------------------

Render.RADIUS = 15 -- px; the body, for hitting it (a player is 9)
local HEIGHT = 7 -- px the shadow falls away from the body, down and right
local STRIDE = 12 -- px a foot moves in one step
local STANCE = 0.62 -- share of a step a foot spends on the ground
local LIFT = 0.35 -- how much bigger a foot is drawn at the top of its swing
local KNEE = 7 -- px a front knee juts out past the line from hip to foot

-- Each leg in the body's frame (forward, side): where it meets the body,
-- where its foot plants when standing, and which way its knee juts.
local LEGS = {
  { hip = { 4, -8 }, foot = { 20, -21 }, side = -1 }, -- front left
  { hip = { 4, 8 }, foot = { 20, 21 }, side = 1 }, -- front right
  { hip = { -12, 0 }, foot = { -30, 0 }, side = 0 }, -- the one behind: its knee straight up
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- Legs ---------------------------------------------------------------------

--- Leg `l` (i of 3) at step phase `cycle`, in the body's frame: its foot
--- (fx, fy), how high that foot is (0 planted, 1 top of the swing), and
--- its knee (kx, ky). `stride` scales the step (0 stands still).
local function leg(l, i, cycle, stride)
  local p = (cycle + (i - 1) / 3) % 1
  local along, up
  if p < STANCE then
    along = 0.5 - p / STANCE -- planted: slides back as the body goes over it
    up = 0
  else
    local k = (p - STANCE) / (1 - STANCE)
    along = -0.5 + k -- swinging forward through the air
    up = math.sin(k * math.pi)
  end
  local fx, fy = l.foot[1] + along * STRIDE * stride, l.foot[2]
  local hx, hy = l.hip[1], l.hip[2]
  -- The knee: halfway out and bent away from the body, the way an insect's
  -- leg looks from above, further while the foot is in the air. The one
  -- behind bends straight up, so from above it sits on the line.
  local dx, dy = fx - hx, fy - hy
  local d = math.sqrt(dx * dx + dy * dy)
  local nx, ny = -dy / d, dx / d
  if ny * l.side < 0 then
    nx, ny = -nx, -ny -- the side away from the body
  end
  local out = (KNEE + up * stride * 3) * math.abs(l.side)
  return fx, fy, up * stride, hx + dx * 0.5 + nx * out, hy + dy * 0.5 + ny * out
end

local function drawLeg(l, fx, fy, up, kx, ky)
  color(Render.LEG)
  love.graphics.setLineWidth(4)
  love.graphics.line(l.hip[1], l.hip[2], kx, ky)
  love.graphics.setLineWidth(2.6)
  love.graphics.line(kx, ky, fx, fy)
  -- The knee joint, catching the light, and the hoof at the end.
  color(Render.PLATE_DARK)
  love.graphics.circle("fill", kx, ky, l.side == 0 and 3.2 or 2.6, 8)
  color(Render.LEG)
  love.graphics.circle("fill", fx, fy, 2.2 * (1 + up * LIFT), 8)
end

-- Body ---------------------------------------------------------------------

local function body(hurt)
  -- The sack of it, wider at the back.
  color(mix(Render.HIDE, { 1, 1, 1 }, hurt))
  love.graphics.ellipse("fill", -2, 0, 15, 11, 18)
  love.graphics.ellipse("fill", -10, 0, 8, 9, 14)
  -- Ribbed plates across the back, each overlapping the one behind it.
  for k = 0, 3 do
    local x = 5 - k * 5.5
    local half = 9.5 - math.abs(k - 1.2) * 1.4
    color(mix(k % 2 == 0 and Render.PLATE or Render.PLATE_DARK, { 1, 1, 1 }, hurt))
    love.graphics.polygon("fill", x + 2, -half * 0.8, x + 3, 0, x + 2, half * 0.8, x - 2.5, half, x - 3.5, 0,
      x - 2.5, -half)
  end
  -- A seam down the spine.
  color(Render.LEG, 0.6)
  love.graphics.setLineWidth(1)
  love.graphics.line(-17, 0, 7, 0)
end

local function head(firing, clock, hurt, charging)
  -- The flechette pods under the face, poking out ahead of it.
  color(Render.LEG)
  love.graphics.rectangle("fill", 12, -6.5, 10, 3, 1)
  love.graphics.rectangle("fill", 12, 3.5, 10, 3, 1)
  color(Render.GLOW, 0.8)
  love.graphics.rectangle("fill", 20, -6, 2, 2)
  love.graphics.rectangle("fill", 20, 4, 2, 2)
  -- The face plate, the blunt front end.
  color(mix(Render.FACE, { 1, 1, 1 }, hurt))
  love.graphics.polygon("fill", 6, -8, 13, -6, 16, -2, 16, 2, 13, 6, 6, 8)
  -- Its lights: a big pair and smaller ones round them, pulsing slowly.
  local pulse = 0.75 + 0.25 * math.sin(clock * 3)
  color(Render.GLOW, 0.25 * pulse)
  love.graphics.circle("fill", 12.5, 0, 6, 12)
  color(Render.GLOW, pulse)
  love.graphics.circle("fill", 13, -2.4, 1.5, 8)
  love.graphics.circle("fill", 13, 2.4, 1.5, 8)
  love.graphics.circle("fill", 10.5, -4.6, 0.9, 6)
  love.graphics.circle("fill", 10.5, 4.6, 0.9, 6)
  love.graphics.circle("fill", 15, 0, 0.8, 6)
  if charging then
    -- Both pods charging for a stun shot: a hot white-blue glow swelling
    -- and crackling at their tips.
    local k = 0.6 + 0.4 * math.abs(math.sin(clock * 30))
    for _, side in ipairs({ -5, 5 }) do
      color(Render.GLOW, 0.35 * k)
      love.graphics.circle("fill", 23, side, 7 * k, 10)
      color(Render.SPARK, 0.9)
      love.graphics.circle("fill", 23, side, 3.2 * k, 8)
    end
    color({ 1, 1, 1 }, 0.8)
    love.graphics.setLineWidth(1)
    local j = math.floor(clock * 40) % 4
    love.graphics.line(23, -5, 25 + j, -1, 22, 1, 24 + j, 5) -- an arc between them
  end
  if firing then
    -- A flash of blue off whichever pod just fired, crackling.
    local side = math.floor(clock * 24) % 2 == 0 and -5 or 5
    color(Render.SPARK, 0.9)
    love.graphics.circle("fill", 24, side, 3 + math.sin(clock * 90) * 1, 8)
    color({ 1, 1, 1 })
    love.graphics.circle("fill", 24, side, 1.4, 6)
  end
end

--- A Hunter at (x, y) facing `angle`. `h` (all optional):
---   cycle    its step phase (0..1, keeps counting while it walks)
---   stride   how big its steps are, 0 standing to 1 at a run
---   firing   true while it shoots: a flash off the pods
---   charging true while it charges a stun shot: its pods glow and crackle
---   hurt     0..1, how white it flashes just after a hit
---   dodge    0..1 while it throws itself aside: it leans and leaves a smear
---   dodgeX, dodgeY  which way it is dodging (a unit vector), for the smear
---   alpha    how solid it is
function Render.draw(x, y, angle, h, clock)
  h = h or {}
  clock = clock or 0
  local cycle, stride = h.cycle or 0, h.stride or 0
  local hurt, alpha = h.hurt or 0, h.alpha or 1
  local dodge = h.dodge or 0
  -- The smear it leaves behind in a dodge: faint copies along the way it came.
  if dodge > 0 and h.dodgeX then
    for k = 3, 1, -1 do
      local back = k * 9 * dodge
      love.graphics.push()
      love.graphics.translate(x - h.dodgeX * back, y - h.dodgeY * back)
      love.graphics.rotate(angle)
      color(Render.GLOW, 0.12 * dodge * alpha)
      love.graphics.ellipse("fill", -2, 0, 15, 11, 14)
      love.graphics.pop()
    end
  end
  -- Its shadow: the body and its legs, cast down and right.
  love.graphics.push()
  love.graphics.translate(x + HEIGHT, y + HEIGHT)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 0.2 * alpha)
  love.graphics.ellipse("fill", -3, 0, 14, 10, 16)
  love.graphics.setLineWidth(2)
  for i, l in ipairs(LEGS) do
    local fx, fy, _, kx, ky = leg(l, i, cycle, stride)
    love.graphics.line(l.hip[1], l.hip[2], kx, ky, fx - HEIGHT * 0.6, fy - HEIGHT * 0.6)
  end
  love.graphics.pop()

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  -- In a dodge it leans over the way it is going: squashed across.
  if dodge > 0 then
    love.graphics.scale(1, 1 - 0.18 * dodge)
  end
  local legs = {}
  for i, l in ipairs(LEGS) do
    legs[i] = { leg(l, i, cycle, stride) }
  end
  -- The leg behind goes under the body, the front ones over its sides.
  drawLeg(LEGS[3], unpack(legs[3]))
  body(hurt)
  drawLeg(LEGS[1], unpack(legs[1]))
  drawLeg(LEGS[2], unpack(legs[2]))
  head(h.firing, clock, hurt, h.charging)
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  if alpha < 1 then
    love.graphics.setColor(1, 1, 1)
  end
end

return Render
