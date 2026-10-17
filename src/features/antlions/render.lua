-- An antlion, drawn from above: the insects out of the sand, after Half-
-- Life's. A little bigger than a man. Its back is one big shield: two wing
-- covers of layered olive plates, rimmed in orange, folded over a small
-- pointed abdomen that sticks out behind them. A humped thorax in front, a
-- low wedge of a head with a pair of short hooked mandibles, and six long
-- thin stilt legs, spiked at the knee and pointed at the foot, splayed out
-- wide round it. They walk in an insect's tripod gait: the front and back
-- legs of one side with the middle leg of the other.
--
-- What it can be doing, besides walking:
--   bite    the mandibles spread wide and snap shut, the front legs lunging
--           forward to stab
--   air     off the ground in a leap or a short flight: the wing covers swing
--           open, the wings buzz out behind them in a blur, the body is drawn
--           bigger the higher it is and its shadow falls further away
--   burrow  half in the sand: coming up out of it or going down, a mound of
--           sand heaped round it and spraying off it; all the way under, only
--           the mound
--   dead    on its back, legs curled up
--
-- The camera looks straight down, so height shows in the shadow, which
-- falls off down and right, and in how big the body is drawn.
--
-- Nothing here keeps state: everything takes what to draw and the clock,
-- so the fight and anything else that shows an antlion draw the same thing.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.SHELL = { 0.46, 0.48, 0.24 } -- the plates on its back: olive
Render.SHELL_LIGHT = { 0.64, 0.65, 0.36 }
Render.SHELL_DARK = { 0.29, 0.30, 0.14 }
Render.RIM = { 0.72, 0.47, 0.22 } -- the orange edge round each plate
Render.SEAM = { 0.18, 0.16, 0.08 }
Render.BELLY = { 0.80, 0.68, 0.46 }
Render.LEG = { 0.64, 0.38, 0.17 } -- the legs: orange-brown
Render.LEG_DARK = { 0.40, 0.22, 0.10 }
Render.CLAW = { 0.20, 0.12, 0.06 }
Render.EYE = { 0.10, 0.08, 0.05 }
Render.WING = { 0.80, 0.88, 0.84 }
Render.SAND = { 0.86, 0.78, 0.58 }
Render.SAND_DARK = { 0.70, 0.62, 0.44 }

-- Size ---------------------------------------------------------------------

Render.RADIUS = 11 -- px; the body, for hitting it (a player is 9)
local SCALE = 0.78 -- the model below is drawn this size: nose to tail about twice a player
local HEIGHT = 5 -- px the shadow falls away from the body standing, down and right
local FLIGHT = 28 -- px more it falls at the top of a leap
local STRIDE = 13 -- px a foot moves in one step
local STANCE = 0.55 -- share of a step a foot spends on the ground
local LIFT = 0.4 -- how much bigger a foot is drawn at the top of its swing

-- Each leg in the body's frame (forward, side): where it meets the thorax,
-- where its foot plants when standing, how far its knee juts out (the legs
-- stand tall, so from above the knee sits well out past the body), and
-- which half of the gait it steps with.
local LEGS = {
  { hip = { 5, -3 }, foot = { 25, -17 }, knee = 7, beat = 0 }, -- front left
  { hip = { 5, 3 }, foot = { 25, 17 }, knee = 7, beat = 0.5 }, -- front right
  { hip = { 1, -4 }, foot = { 3, -28 }, knee = 7, beat = 0.5 }, -- middle left
  { hip = { 1, 4 }, foot = { 3, 28 }, knee = 7, beat = 0 }, -- middle right
  { hip = { -3, -4 }, foot = { -20, -25 }, knee = 8, beat = 0 }, -- back left
  { hip = { -3, 4 }, foot = { -20, 25 }, knee = 8, beat = 0.5 }, -- back right
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

--- Colour `c` flashed towards white by `hurt` and buried towards the sand by `sand`.
local function tint(c, hurt, sand)
  return mix(mix(c, { 1, 1, 1 }, hurt), Render.SAND, sand)
end

-- Legs ---------------------------------------------------------------------

--- Leg `l` at step phase `cycle`, in the body's frame: its foot (fx, fy),
--- how high that foot is (0 planted, 1 top of the swing) and its knee
--- (kx, ky). `stride` scales the step (0 stands still), `bite` lunges the
--- front pair forward, `tuck` (0..1) folds every leg in under the body.
local function leg(l, i, cycle, stride, bite, tuck)
  local p = (cycle + l.beat) % 1
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
  if i <= 2 and bite > 0 then -- the front pair stab forward and in
    fx, fy = fx + bite * 10, fy * (1 - bite * 0.45)
    up = math.max(up, bite)
  end
  local hx, hy = l.hip[1], l.hip[2]
  fx, fy = fx + (hx - fx) * tuck * 0.6, fy + (hy - fy) * tuck * 0.6
  -- The knee: out past the line from hip to foot, away from the body, and
  -- higher (further out) while the foot is in the air.
  local dx, dy = fx - hx, fy - hy
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local nx, ny = -dy / d, dx / d
  if ny * hy < 0 then
    nx, ny = -nx, -ny
  end
  local out = l.knee + up * stride * 3 + tuck * 3
  return fx, fy, up * math.max(stride, bite), hx + dx * 0.4 + nx * out, hy + dy * 0.4 + ny * out
end

local function drawLeg(l, fx, fy, up, kx, ky, hurt, sand)
  local hx, hy = l.hip[1], l.hip[2]
  -- The thigh: a thick segment up to the knee, darker along its edge.
  color(tint(Render.LEG_DARK, hurt, sand))
  love.graphics.setLineWidth(3.4)
  love.graphics.line(hx, hy, kx, ky)
  color(tint(Render.LEG, hurt, sand))
  love.graphics.setLineWidth(2)
  love.graphics.line(hx, hy, kx, ky)
  -- The shin: a long spike tapering from the knee down to the point it
  -- walks on, which reaches further while the foot is lifted.
  local dx, dy = fx - kx, fy - ky
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local ux, uy = dx / d, dy / d
  local reach = 3 + up * LIFT * 3
  local tx, ty = fx + ux * reach, fy + uy * reach
  color(tint(Render.LEG, hurt, sand))
  love.graphics.polygon("fill", kx - uy * 1.3, ky + ux * 1.3, kx + uy * 1.3, ky - ux * 1.3, tx, ty)
  color(tint(Render.CLAW, hurt, sand))
  love.graphics.setLineWidth(1)
  love.graphics.line(fx, fy, tx, ty)
  -- A thorn off the back of the knee.
  local bx, by = kx - hx, ky - hy
  local bd = math.max(1, math.sqrt(bx * bx + by * by))
  color(tint(Render.LEG_DARK, hurt, sand))
  love.graphics.circle("fill", kx, ky, 1.6, 6)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(kx, ky, kx + bx / bd * 3 - 1.5, ky + by / bd * 3)
end

-- Body ---------------------------------------------------------------------

--- The wings, while it is in the air: two pairs blurred out behind the
--- open wing covers, beating.
local function wings(air, clock, hurt, sand)
  local beat = math.sin(clock * 70)
  for _, side in ipairs({ -1, 1 }) do
    for k = 0, 2 do -- a blur: a few faint copies through the beat
      local a = -side * (0.75 + 0.35 * beat + k * 0.18) * air
      love.graphics.push()
      love.graphics.translate(-2, side * 3)
      love.graphics.rotate(math.pi + a)
      color(tint(Render.WING, hurt, sand), 0.16 * air)
      love.graphics.ellipse("fill", 15, 0, 17, 5, 12)
      love.graphics.pop()
    end
  end
end

--- The wing covers: the shield on its back, two broad plates hinged at the
--- thorax and folded over the abdomen, swung open by `open`. Each is laid
--- in overlapping bands like shingles, every band rimmed in orange.
local function covers(open, hurt, sand)
  for _, side in ipairs({ -1, 1 }) do
    local s = side
    love.graphics.push()
    love.graphics.translate(1, s * 1)
    love.graphics.rotate(-s * open * 0.9)
    color(tint(Render.RIM, hurt, sand))
    love.graphics.polygon("fill", 1, 0, -1, s * 8.5, -9, s * 11, -19, s * 9, -25, s * 3.5, -23, 0)
    color(tint(Render.SHELL_DARK, hurt, sand))
    love.graphics.polygon("fill", 0, s * 0.5, -1.5, s * 7.8, -9, s * 10, -18.5, s * 8.2, -23.5, s * 3.2, -21.5, s * 0.5)
    -- The bands, back to front so each overlaps the one behind it.
    for k = 2, 0, -1 do
      local x0 = -7 * k
      local w = 9.6 - k * 0.9
      color(tint(Render.RIM, hurt, sand))
      love.graphics.polygon("fill", x0, s * 0.6, x0 - 1.5, s * w, x0 - 7, s * (w + 0.4 - k * 0.6), x0 - 8, s * 0.6)
      color(tint(k == 0 and Render.SHELL_LIGHT or Render.SHELL, hurt, sand))
      love.graphics.polygon("fill", x0 - 0.6, s * 0.9, x0 - 2, s * (w - 1), x0 - 6.6, s * (w - 0.6 - k * 0.6),
        x0 - 7.4, s * 0.9)
    end
    -- A ridge down each cover, catching the light.
    color(tint(Render.SHELL_LIGHT, hurt, sand), 0.9)
    love.graphics.setLineWidth(1)
    love.graphics.line(-1, s * 3.5, -10, s * 5.2, -21, s * 3)
    love.graphics.pop()
  end
end

--- The abdomen: small and pointed, the end of it poking out from under the
--- covers behind.
local function abdomen(hurt, sand)
  color(tint(Render.SHELL_DARK, hurt, sand))
  love.graphics.ellipse("fill", -16, 0, 10, 6.5, 16)
  love.graphics.polygon("fill", -22, -4, -31, 0, -22, 4)
  color(tint(Render.SHELL, hurt, sand)) -- banded across, seen when the covers open
  love.graphics.setLineWidth(1.4)
  for k = 0, 3 do
    local x = -10 - k * 3.6
    local half = 5.8 - math.abs(k - 1.2) * 0.9
    love.graphics.line(x, -half, x - 1.2, 0, x, half)
  end
  color(tint(Render.RIM, hurt, sand))
  love.graphics.polygon("fill", -23, -2.6, -29.5, 0, -23, 2.6)
  color(tint(Render.SEAM, hurt, sand), 0.8)
  love.graphics.setLineWidth(1)
  love.graphics.line(-25, -1.8, -25, 1.8)
  love.graphics.line(-27.3, -1, -27.3, 1)
end

--- The thorax: a humped, angular plate the legs and covers hang off.
local function thorax(hurt, sand)
  color(tint(Render.RIM, hurt, sand))
  love.graphics.polygon("fill", 8, 0, 5, -5.5, -2, -6.2, -4.5, 0, -2, 6.2, 5, 5.5)
  color(tint(Render.SHELL, hurt, sand))
  love.graphics.polygon("fill", 7, 0, 4.5, -4.6, -1.5, -5.2, -3.5, 0, -1.5, 5.2, 4.5, 4.6)
  color(tint(Render.SHELL_LIGHT, hurt, sand)) -- the crest of the hump
  love.graphics.polygon("fill", 6.5, 0, 3, -1.6, -2.5, 0, 3, 1.6)
end

--- The head and its mandibles, `open` 0 shut to 1 spread wide.
local function head(open, hurt, sand)
  for _, side in ipairs({ -1, 1 }) do
    -- A short hooked mandible either side of the mouth, curving in to a
    -- point; shut, the two points meet.
    local pts = {}
    for k = 0, 4 do
      local t = k / 4
      local x = 15 + t * (7 + open * 1.5)
      local bow = math.sin(t * math.pi * 0.85) * (1.5 + open * 4)
      local y = side * (2.6 + bow - t * (2.4 - open * 3.5))
      pts[#pts + 1], pts[#pts + 2] = x, y
    end
    color(tint(Render.CLAW, hurt, sand))
    love.graphics.setLineWidth(2.2)
    love.graphics.line(pts)
    color(tint(Render.LEG_DARK, hurt, sand))
    love.graphics.setLineWidth(1)
    love.graphics.line(pts[1], pts[2], pts[3], pts[4], pts[5], pts[6])
  end
  -- A low wedge, wide at the neck and narrowing to the mouth.
  color(tint(Render.RIM, hurt, sand))
  love.graphics.polygon("fill", 5, -4.6, 12, -4.2, 17.5, -1.8, 17.5, 1.8, 12, 4.2, 5, 4.6)
  color(tint(Render.SHELL, hurt, sand))
  love.graphics.polygon("fill", 6, -3.8, 12, -3.4, 16.5, -1.4, 16.5, 1.4, 12, 3.4, 6, 3.8)
  color(tint(Render.SHELL_LIGHT, hurt, sand)) -- a plate down the middle of it
  love.graphics.polygon("fill", 6.5, -1.4, 14.5, -0.6, 14.5, 0.6, 6.5, 1.4)
  -- Small dark eyes, back on each side.
  color(Render.EYE)
  love.graphics.circle("fill", 10, -3.2, 1, 6)
  love.graphics.circle("fill", 10, 3.2, 1, 6)
end

--- The mound of sand it is under, `k` 0 flat to 1 heaped up, spraying.
function Render.mound(x, y, k, clock)
  clock = clock or 0
  if k <= 0 then
    return
  end
  local r = (12 + k * 10) * SCALE
  love.graphics.setColor(0, 0, 0, 0.18 * k)
  love.graphics.ellipse("fill", x + 3, y + 4, r + 2, r * 0.85 + 2, 18)
  color(Render.SAND_DARK, k)
  love.graphics.ellipse("fill", x, y, r, r * 0.85, 18)
  color(Render.SAND, k)
  love.graphics.ellipse("fill", x - 1.5, y - 1.5, r * 0.82, r * 0.68, 18)
  -- Cracks across the top, and clods thrown off the edge.
  color(Render.SAND_DARK, k)
  love.graphics.setLineWidth(1)
  for a = 0, 4 do
    local t = a * 1.26 + 0.4
    love.graphics.line(x + math.cos(t) * 2, y + math.sin(t) * 2, x + math.cos(t + 0.2) * r * 0.6,
      y + math.sin(t + 0.2) * r * 0.5)
  end
  for i = 0, 7 do
    local t = i * 0.785 + clock * 0.7
    local d = r + 3 + ((clock * 30 + i * 7) % 9)
    color(i % 2 == 0 and Render.SAND or Render.SAND_DARK, 0.8 * k)
    love.graphics.circle("fill", x + math.cos(t) * d, y + math.sin(t) * d * 0.85, 1.6, 5)
  end
end

--- An antlion at (x, y) facing `angle`. `a` (all optional):
---   cycle    its step phase (0..1, keeps counting while it walks)
---   stride   how big its steps are, 0 standing to 1 at a run
---   bite     0..1 through a bite: mandibles spread, then snap shut on 1
---   air      0..1, how high it is in a leap or a flight
---   burrow   0 out on the sand to 1 all the way under it
---   hurt     0..1, how white it flashes just after a hit
---   dead     true on its back, legs curled
---   alpha    how solid it is
function Render.draw(x, y, angle, a, clock)
  a = a or {}
  clock = clock or 0
  local cycle, stride = a.cycle or 0, a.stride or 0
  local hurt, alpha = a.hurt or 0, a.alpha or 1
  local air, burrow = a.air or 0, a.burrow or 0
  local bite = a.bite or 0
  -- The mandibles open through the first two thirds of a bite and snap shut.
  local jaw = bite < 0.65 and bite / 0.65 or (1 - bite) / 0.35
  local lunge = math.sin(bite * math.pi)
  if burrow > 0 then
    Render.mound(x, y, math.min(1, burrow * 2), clock)
  end
  if burrow >= 1 then
    return
  end
  local sand = burrow
  local size = (1 + air * 0.3) * (1 - burrow * 0.35)
  local tuck = a.dead and 1 or air * 0.7
  -- Its shadow: the body and its legs, cast down and right, further and
  -- fainter the higher it is.
  local fall = HEIGHT + air * FLIGHT
  if burrow < 0.6 then
    love.graphics.push()
    love.graphics.translate(x + fall, y + fall)
    love.graphics.rotate(angle)
    love.graphics.scale(SCALE * (1 - air * 0.15))
    love.graphics.setColor(0, 0, 0, (0.22 - air * 0.1) * alpha * (1 - burrow))
    love.graphics.ellipse("fill", -11, 0, 14, 10, 16)
    love.graphics.ellipse("fill", 9, 0, 9, 5, 12)
    love.graphics.setLineWidth(2)
    for i, l in ipairs(LEGS) do
      local fx, fy, _, kx, ky = leg(l, i, cycle, stride, lunge, tuck)
      love.graphics.line(l.hip[1], l.hip[2], kx, ky, fx, fy)
    end
    love.graphics.pop()
  end

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.scale(SCALE * size)
  if a.dead then
    -- On its back: the pale belly up, legs curled in over it.
    color(tint(Render.BELLY, hurt, 0), alpha)
    love.graphics.ellipse("fill", -15, 0, 10, 7, 16)
    love.graphics.polygon("fill", -22, -4, -30, 0, -22, 4)
    love.graphics.ellipse("fill", 2, 0, 6.5, 5.5, 14)
    color(tint(Render.SHELL_DARK, hurt, 0), alpha)
    love.graphics.polygon("fill", 6, -3.8, 12, -3.4, 16.5, -1.4, 16.5, 1.4, 12, 3.4, 6, 3.8)
    color(Render.SEAM, 0.6 * alpha)
    love.graphics.setLineWidth(1)
    for k = 0, 3 do
      love.graphics.line(-9 - k * 4, -5.5, -9 - k * 4, 5.5)
    end
    for i, l in ipairs(LEGS) do
      local fx, fy, up, kx, ky = leg(l, i, 0, 0, 0, 1)
      drawLeg(l, fx, fy, up, kx, ky, hurt, 0)
    end
    love.graphics.pop()
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    return
  end
  local legs = {}
  for i, l in ipairs(LEGS) do
    legs[i] = { leg(l, i, cycle, stride, lunge, tuck) }
  end
  -- The back and middle legs go under the body, the front ones over it.
  for i = 3, 6 do
    drawLeg(LEGS[i], legs[i][1], legs[i][2], legs[i][3], legs[i][4], legs[i][5], hurt, sand)
  end
  abdomen(hurt, sand)
  if air > 0 then
    wings(air, clock, hurt, sand)
  end
  covers(air, hurt, sand)
  thorax(hurt, sand)
  for i = 1, 2 do
    drawLeg(LEGS[i], legs[i][1], legs[i][2], legs[i][3], legs[i][4], legs[i][5], hurt, sand)
  end
  head(math.max(jaw * (bite > 0 and 1 or 0), air * 0.3), hurt, sand)
  love.graphics.pop()
  if burrow > 0 then -- sand heaped over its edges as it goes under
    color(Render.SAND, burrow)
    love.graphics.setLineWidth(5)
    love.graphics.ellipse("line", x, y, 18 * SCALE * size, 15 * SCALE * size, 18)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
