-- The tripod, drawn from above: a war machine out of the sky, taller than
-- the buildings. A flat armoured head (a shield-shaped carapace, broad at
-- the back and narrowing to a blunt nose) rides on three long jointed legs
-- that walk it in a slow, rolling gait. The heat ray sits on a snaking arm
-- out of the nose, two tentacles trail underneath, feeling about, and the
-- cage for whoever it picks up hangs at the back. Its shadow falls well off
-- to the side, so you can tell how high it stands.
--
-- The camera looks straight down, so height shows only in the shadow and in
-- how big things are drawn: a foot in the air grows and its shadow slides
-- away from it.
--
-- Nothing here keeps state: everything takes what to draw and the clock,
-- so the fight and anything else that shows a tripod draw the same thing.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.METAL = { 0.40, 0.43, 0.41 }
Render.METAL_DARK = { 0.22, 0.24, 0.24 }
Render.METAL_LIGHT = { 0.60, 0.63, 0.58 }
Render.GLOW = { 0.60, 0.88, 1.00 }
Render.RAY = { 1.00, 0.97, 0.85 }
Render.WEED = { 0.62, 0.10, 0.08 }
local SEAM = { 0.14, 0.15, 0.15 }
local CAGE = { 0.16, 0.17, 0.17 }
local TENTACLE = { 0.18, 0.19, 0.20 }
local TENTACLE_TIP = { 0.55, 0.30, 0.28 }

-- Size ---------------------------------------------------------------------

Render.RADIUS = 38 -- px; the head, for hitting it
local SCALE = 1.4 -- the carapace outline below is in units of this many px
local HEIGHT = 54 -- px the shadow falls away from the head, down and right
local HIP = 26 -- px from the centre to where a leg meets the head
local SPAN = 130 -- px from the centre out to a planted foot
local STRIDE = 70 -- px a foot moves in one step
local STANCE = 0.7 -- share of a step a foot spends on the ground
local LIFT = 16 -- px a foot rises at the top of its swing (drawn as size)

-- Where the legs meet the head, as angles off the heading: one behind, two
-- out front at the sides, like the camera stand it is named for.
local LEGS = { math.pi, math.pi / 3, -math.pi / 3 }

-- The carapace from above, in (forward, side) units: a blunt nose at the
-- front, flared cheeks, a broad back. Convex, so it fills in one go.
local SHELL = {
  { 32, 0 },
  { 27, 9 },
  { 15, 20 },
  { 0, 26 },
  { -17, 25 },
  { -28, 16 },
  { -32, 0 },
  { -28, -16 },
  { -17, -25 },
  { 0, -26 },
  { 15, -20 },
  { 27, -9 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

--- A list of shell points turned to `angle`, scaled by `k`, placed at (x, y).
local function shell(x, y, angle, k)
  local fx, fy = math.cos(angle), math.sin(angle)
  local pts = {}
  for _, p in ipairs(SHELL) do
    local u, v = p[1] * k, p[2] * k
    pts[#pts + 1] = x + fx * u - fy * v
    pts[#pts + 1] = y + fy * u + fx * v
  end
  return pts
end

-- Legs ---------------------------------------------------------------------

--- Where leg `i` is at step phase `cycle`: its foot on the ground (fx, fy),
--- how high that foot is off it (0 on the ground, 1 at the top of a swing)
--- and its hip on the head. `stride` scales the step (0 stands still).
local function leg(x, y, angle, i, cycle, stride)
  local a = angle + LEGS[i]
  local p = (cycle + (i - 1) / 3) % 1
  local along, up
  if p < STANCE then
    along = 0.5 - p / STANCE -- planted: slides from front to back as the head goes over
    up = 0
  else
    local k = (p - STANCE) / (1 - STANCE)
    along = -0.5 + k -- swinging forward through the air
    up = math.sin(k * math.pi)
  end
  local hx, hy = math.cos(angle), math.sin(angle)
  local off = along * STRIDE * stride
  local footX = x + math.cos(a) * SPAN + hx * off
  local footY = y + math.sin(a) * SPAN + hy * off
  return footX, footY, up * stride, x + math.cos(a) * HIP, y + math.sin(a) * HIP
end

--- The knee between a hip and a foot: under halfway out and kicked a little
--- to one side, the way the thigh goes out and down and the shin plants.
local function knee(hx, hy, footX, footY, side)
  local dx, dy = footX - hx, footY - hy
  local d = math.sqrt(dx * dx + dy * dy)
  local nx, ny = -dy / d, dx / d
  return hx + dx * 0.42 + nx * 12 * side, hy + dy * 0.42 + ny * 12 * side
end

local function drawLegShadow(footX, footY, up, hx, hy, kx, ky, sx, sy)
  local fsx, fsy = footX + up * sx * 0.35, footY + up * sy * 0.35
  love.graphics.setLineWidth(7)
  love.graphics.line(hx + sx, hy + sy, kx + sx * 1.25, ky + sy * 1.25)
  love.graphics.setLineWidth(5)
  love.graphics.line(kx + sx * 1.25, ky + sy * 1.25, fsx, fsy)
  love.graphics.circle("fill", fsx, fsy, 7, 10)
end

--- One leg: shin from the foot up to the knee, thigh from the knee down to
--- the hip, joints as rings, the foot a three-toed pad.
local function drawLeg(footX, footY, up, hx, hy, kx, ky, angle)
  local grow = 1 + up * LIFT / 40
  -- Shin (thinner, drawn first: it is lower than the thigh at the knee).
  color(SEAM)
  love.graphics.setLineWidth(6)
  love.graphics.line(kx, ky, footX, footY)
  color(Render.METAL)
  love.graphics.setLineWidth(4)
  love.graphics.line(kx, ky, footX, footY)
  color(Render.METAL_LIGHT, 0.7)
  love.graphics.setLineWidth(1)
  love.graphics.line(kx - 1, ky - 1, footX - 1, footY - 1)
  -- A collar partway down the shin.
  local cx, cy = kx + (footX - kx) * 0.55, ky + (footY - ky) * 0.55
  color(Render.METAL_DARK)
  love.graphics.circle("fill", cx, cy, 3.5, 8)
  -- Foot: three toes splayed round it.
  local r = 6 * grow
  color(SEAM)
  for t = 0, 2 do
    local a = angle + t * math.pi * 2 / 3
    love.graphics.setLineWidth(3 * grow)
    love.graphics.line(footX, footY, footX + math.cos(a) * r * 1.6, footY + math.sin(a) * r * 1.6)
  end
  color(Render.METAL_DARK)
  love.graphics.circle("fill", footX, footY, r, 12)
  color(Render.METAL)
  love.graphics.circle("fill", footX - 1, footY - 1, r - 2, 12)
  -- Thigh: thick, segmented, up to the knee.
  color(SEAM)
  love.graphics.setLineWidth(9)
  love.graphics.line(hx, hy, kx, ky)
  color(Render.METAL)
  love.graphics.setLineWidth(7)
  love.graphics.line(hx, hy, kx, ky)
  color(Render.METAL_LIGHT, 0.6)
  love.graphics.setLineWidth(2)
  love.graphics.line(hx - 1, hy - 1, kx - 1, ky - 1)
  color(SEAM)
  love.graphics.setLineWidth(1)
  for s = 1, 3 do
    local k = s / 4
    love.graphics.circle("fill", hx + (kx - hx) * k, hy + (ky - hy) * k, 2, 6)
  end
  -- The knee: a big joint with a light on it.
  color(SEAM)
  love.graphics.circle("fill", kx, ky, 7, 14)
  color(Render.METAL_DARK)
  love.graphics.circle("fill", kx, ky, 5.5, 14)
  color(Render.METAL_LIGHT)
  love.graphics.circle("fill", kx - 1.5, ky - 1.5, 2.5, 10)
  love.graphics.setLineWidth(1)
end

-- Underneath -------------------------------------------------------------

--- A tentacle: a snaking line of shrinking beads from under the head, the
--- tip reaching for (reachX, reachY) if it is given.
local function drawTentacle(x, y, angle, side, time, seed, reachX, reachY)
  local fx, fy = math.cos(angle), math.sin(angle)
  local sx, sy = -fy * side, fx * side
  local bx, by = x + fx * 20 + sx * 22, y + fy * 20 + sy * 22
  local tx, ty = bx + fx * 46 + sx * 34, by + fy * 46 + sy * 34
  if reachX then
    tx, ty = reachX, reachY
  end
  local dx, dy = tx - bx, ty - by
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local nx, ny = -dy / d, dx / d
  local n = 14
  local prevX, prevY
  for i = 0, n do
    local k = i / n
    local wave = math.sin(time * 3 + seed + k * 5) * 9 * k * (reachX and 0.4 or 1)
    local px, py = bx + dx * k + nx * wave, by + dy * k + ny * wave
    local w = 5 - 3.5 * k
    if prevX then
      color(i >= n - 2 and TENTACLE_TIP or TENTACLE)
      love.graphics.setLineWidth(w * 2)
      love.graphics.line(prevX, prevY, px, py)
    end
    love.graphics.circle("fill", px, py, w, 8)
    prevX, prevY = px, py
  end
  love.graphics.setLineWidth(1)
end

--- The cage at the back: a basket of bars, with a shape in it if it holds
--- somebody.
local function drawCage(x, y, angle, full, time)
  local fx, fy = math.cos(angle), math.sin(angle)
  local cx, cy = x - fx * 50, y - fy * 50
  color(CAGE)
  love.graphics.ellipse("fill", cx, cy, 15, 15)
  if full then
    local wob = math.sin(time * 9) * 1.5
    love.graphics.setColor(0.85, 0.72, 0.60)
    love.graphics.circle("fill", cx + wob, cy, 4, 10)
    love.graphics.setColor(0.25, 0.35, 0.60)
    love.graphics.circle("fill", cx + wob - fx * 2, cy - fy * 2, 5.5, 10)
    love.graphics.setColor(0.85, 0.72, 0.60)
    love.graphics.circle("fill", cx + wob + fx, cy + fy, 3.5, 10)
  end
  color(Render.METAL_DARK)
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", cx, cy, 15, 16)
  for k = 0, 5 do
    local a = angle + k * math.pi / 6
    local c, s = math.cos(a) * 15, math.sin(a) * 15
    love.graphics.line(cx - c, cy - s, cx + c, cy + s)
  end
  love.graphics.setLineWidth(1)
end

-- The head ----------------------------------------------------------------

--- The heat ray's arm: out of the nose on a snaking neck, a hooded pod on
--- the end with the lens that glows as it charges. Returns where the lens is.
local function drawGun(x, y, angle, aim, charge, time)
  local fx, fy = math.cos(angle), math.sin(angle)
  local bx, by = x + fx * 40, y + fy * 40
  local ax, ay = math.cos(aim), math.sin(aim)
  local sway = math.sin(time * 1.3) * 3 * (1 - charge)
  local mx, my = bx + fx * 14 - fy * sway, by + fy * 14 + fx * sway
  local px, py = mx + ax * 16, my + ay * 16
  color(SEAM)
  love.graphics.setLineWidth(8)
  love.graphics.line(bx, by, mx, my, px, py)
  color(Render.METAL_DARK)
  love.graphics.setLineWidth(5)
  love.graphics.line(bx, by, mx, my, px, py)
  love.graphics.setLineWidth(1)
  -- The pod: a hood flared round the lens, like a cobra's.
  local hood = {}
  for k = 0, 6 do
    local a = aim + math.pi / 2 + k / 6 * math.pi
    local r = (k == 0 or k == 6) and 5 or 9
    hood[#hood + 1] = px + math.cos(a) * r - ax * 3
    hood[#hood + 1] = py + math.sin(a) * r - ay * 3
  end
  hood[#hood + 1] = px + ax * 6
  hood[#hood + 1] = py + ay * 6
  color(SEAM)
  love.graphics.polygon("fill", hood)
  color(Render.METAL)
  love.graphics.circle("fill", px - ax * 2, py - ay * 2, 6, 12)
  local lx, ly = px + ax * 5, py + ay * 5
  local pulse = 0.5 + 0.5 * math.sin(time * (4 + charge * 30))
  color(Render.GLOW, 0.25 + 0.5 * charge * pulse)
  love.graphics.circle("fill", lx, ly, 5 + 9 * charge, 16)
  color(charge > 0 and Render.RAY or Render.GLOW, 0.6 + 0.4 * math.max(charge, pulse * 0.4))
  love.graphics.circle("fill", lx, ly, 2.5 + 1.5 * charge, 10)
  return lx, ly
end

--- The carapace: the shell with a rim, plates, a ridge down the spine,
--- vents at the back and the lights under the brow.
local function drawShell(x, y, angle, time, hurt)
  local fx, fy = math.cos(angle), math.sin(angle)
  color(SEAM)
  love.graphics.polygon("fill", shell(x, y, angle, SCALE + 0.08))
  color(Render.METAL_DARK)
  love.graphics.polygon("fill", shell(x, y, angle, SCALE))
  color(Render.METAL)
  love.graphics.polygon("fill", shell(x - fx - fy, y - fy + fx, angle, SCALE * 0.84))
  color(Render.METAL_LIGHT, 0.55)
  love.graphics.polygon("fill", shell(x + fx * 4 - 2, y + fy * 4 - 2, angle, SCALE * 0.5))
  -- Plates: seams running out from the spine to the rim.
  local function at(u, v)
    return x + (fx * u - fy * v) * SCALE, y + (fy * u + fx * v) * SCALE
  end
  color(SEAM, 0.8)
  love.graphics.setLineWidth(1)
  for _, s in ipairs({ { 12, 5, 14, 17 }, { -4, 6, -2, 21 }, { -18, 5, -22, 17 } }) do
    local x1, y1 = at(s[1], s[2])
    local x2, y2 = at(s[3], s[4])
    love.graphics.line(x1, y1, x2, y2)
    x1, y1 = at(s[1], -s[2])
    x2, y2 = at(s[3], -s[4])
    love.graphics.line(x1, y1, x2, y2)
  end
  -- The ridge down the middle, nose to tail.
  local ax, ay = at(26, 0)
  local bx, by = at(-28, 0)
  love.graphics.setLineWidth(3)
  color(SEAM)
  love.graphics.line(ax, ay, bx, by)
  love.graphics.setLineWidth(1)
  color(Render.METAL_LIGHT)
  love.graphics.line(ax - 1, ay - 1, bx - 1, by - 1)
  -- Vents at the back, breathing.
  local breathe = 0.4 + 0.3 * math.sin(time * 2)
  for v = -1, 1, 2 do
    for k = 0, 2 do
      local x1, y1 = at(-20 - k * 3, v * 8)
      local x2, y2 = at(-20 - k * 3, v * 15)
      color(SEAM)
      love.graphics.setLineWidth(2)
      love.graphics.line(x1, y1, x2, y2)
      color(Render.GLOW, breathe * 0.35)
      love.graphics.setLineWidth(1)
      love.graphics.line(x1, y1, x2, y2)
    end
  end
  -- The lights under the brow at the front, like eyes, one each side.
  for v = -1, 1, 2 do
    local ex, ey = at(22, v * 11)
    color(Render.GLOW, 0.3)
    love.graphics.circle("fill", ex, ey, 4.5, 10)
    color(Render.GLOW)
    love.graphics.circle("fill", ex, ey, 2, 8)
  end
  -- Hurt: sparks and black scorch where it has been hit.
  if hurt > 0 then
    for k = 1, math.floor(hurt * 5) do
      local u, v = ((k * 37) % 40) - 20, ((k * 23) % 30) - 15
      local hx, hy = at(u, v)
      love.graphics.setColor(0.05, 0.05, 0.05, 0.6)
      love.graphics.circle("fill", hx, hy, 3 + k % 3, 8)
      if math.sin(time * 13 + k * 2.1) > 0.7 then
        love.graphics.setColor(1, 0.8, 0.3)
        love.graphics.circle("fill", hx + 1, hy - 1, 1.5, 5)
      end
    end
  end
end

--- The shield: a thin shimmer round the head that ripples. `k` 0..1 is how
--- much is left of it.
local function drawShield(x, y, k, time)
  local r = Render.RADIUS + 16
  for i = 0, 2 do
    local wob = math.sin(time * 5 + i * 2) * 2
    color(Render.GLOW, (0.10 + 0.08 * i) * k)
    love.graphics.setLineWidth(3 - i)
    love.graphics.circle("line", x, y, r + wob - i * 3, 40)
  end
  color(Render.GLOW, 0.06 * k)
  love.graphics.circle("fill", x, y, r, 40)
  love.graphics.setLineWidth(1)
end

-- Drawing it -----------------------------------------------------------------

--- The tripod from above. `t` is:
---   dx, dy, angle   where it stands and which way it faces
---   hp, max         health, for the bar over it (no bar without them)
---   walk            0..1, how far into a stride it is going (0 stands still)
---   cycle           where it is in its step, counting up by one a step; the
---                   fight advances it by distance walked / STEP so the feet
---                   do not slide (defaults to the clock)
---   aim             where the heat ray points (defaults to `angle`)
---   charge          0..1 the heat ray warming up, 1 firing
---   ray             { x, y } where the heat ray is burning, while it fires
---   grab            { x, y } one tentacle reaching for something
---   caged           true when somebody is in the cage
---   shield          0..1 how much shield is left (nil or 0: none)
function Render.tripod(t, time)
  local x, y, angle = t.dx, t.dy, t.angle
  local walk = t.walk or 0
  local cycle = t.cycle or time * 0.45
  local sx, sy = HEIGHT, HEIGHT * 0.8 -- where the shadow falls
  -- A rolling sway as the weight goes from leg to leg.
  local sway = math.sin(cycle * math.pi * 2) * 2.5 * walk
  local hx, hy = x - math.sin(angle) * sway, y + math.cos(angle) * sway

  local legs = {}
  for i = 1, 3 do
    local fx, fy, up, px, py = leg(hx, hy, angle, i, cycle, walk)
    local kx, ky = knee(px, py, fx, fy, i == 1 and 1 or (i == 2 and -1 or 1))
    legs[i] = { fx, fy, up, px, py, kx, ky }
  end

  -- Shadows: head, legs and all, cast off down and to the right.
  love.graphics.setColor(0, 0, 0, 0.28)
  for _, l in ipairs(legs) do
    drawLegShadow(l[1], l[2], l[3], l[4], l[5], l[6], l[7], sx, sy)
  end
  love.graphics.polygon("fill", shell(hx + sx, hy + sy, angle, SCALE * 1.05))
  love.graphics.setLineWidth(1)

  -- Underneath: the legs going down, the cage, and the tentacles hanging
  -- lower than the hips.
  for _, l in ipairs(legs) do
    drawLeg(l[1], l[2], l[3], l[4], l[5], l[6], l[7], angle)
  end
  drawCage(hx, hy, angle, t.caged, time)
  drawTentacle(hx, hy, angle, 1, time, 0, t.grab and t.grab.x, t.grab and t.grab.y)
  drawTentacle(hx, hy, angle, -1, time, 2.4)

  -- The head on top of it all.
  local lx, ly = drawGun(hx, hy, angle, t.aim or angle, t.charge or 0, time)
  local hurt = (t.hp and t.max) and (1 - math.max(0, t.hp / t.max)) or 0
  drawShell(hx, hy, angle, time, hurt)

  if t.ray then
    Render.heatRay(lx, ly, t.ray.x, t.ray.y, time)
  end
  if t.shield and t.shield > 0 then
    drawShield(hx, hy, t.shield, time)
  end

  if t.hp and t.max then
    local bw = 110
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", hx - bw / 2 - 1, hy - Render.RADIUS - 22, bw + 2, 6)
    local f = math.max(0, t.hp / t.max)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", hx - bw / 2, hy - Render.RADIUS - 21, bw * f, 4)
  end
  love.graphics.setColor(1, 1, 1)
end

--- How far the tripod walks in one full step, for advancing `cycle`.
Render.STEP = STRIDE / STANCE

--- The heat ray from the lens at (x1, y1) to (x2, y2): a white-hot core in
--- a pale blue glow, flickering, and the ground boiling where it lands.
function Render.heatRay(x1, y1, x2, y2, time)
  local flicker = 0.8 + 0.2 * math.sin(time * 60)
  color(Render.GLOW, 0.25 * flicker)
  love.graphics.setLineWidth(14)
  love.graphics.line(x1, y1, x2, y2)
  color(Render.GLOW, 0.5 * flicker)
  love.graphics.setLineWidth(7)
  love.graphics.line(x1, y1, x2, y2)
  color(Render.RAY)
  love.graphics.setLineWidth(3)
  love.graphics.line(x1, y1, x2, y2)
  love.graphics.setLineWidth(1)
  for k = 0, 5 do
    local a = time * 7 + k * 1.05
    local r = 8 + 6 * math.abs(math.sin(time * 11 + k))
    love.graphics.setColor(1, 0.55 + 0.1 * (k % 3), 0.15, 0.7)
    love.graphics.circle("fill", x2 + math.cos(a) * r, y2 + math.sin(a) * r, 3 + k % 2, 6)
  end
  color(Render.RAY, 0.9)
  love.graphics.circle("fill", x2, y2, 7 * flicker, 12)
  love.graphics.setColor(1, 1, 1)
end

--- The red weed it sows as it walks: a creeping clump of crimson tendrils.
--- `w` is { x, y, size, seed }.
function Render.weed(w, time)
  local n = 7
  for k = 0, n - 1 do
    local a = w.seed + k / n * math.pi * 2
    local len = w.size * (0.6 + 0.4 * math.abs(math.sin(w.seed * 3 + k)))
    local curl = math.sin(time * 0.8 + k + w.seed) * 0.25
    local mx, my = w.x + math.cos(a + curl) * len * 0.5, w.y + math.sin(a + curl) * len * 0.5
    local ex, ey = w.x + math.cos(a + curl * 2) * len, w.y + math.sin(a + curl * 2) * len
    color(Render.WEED, 0.85)
    love.graphics.setLineWidth(3)
    love.graphics.line(w.x, w.y, mx, my, ex, ey)
    love.graphics.setColor(0.80, 0.18, 0.12)
    love.graphics.circle("fill", ex, ey, 2.5, 6)
  end
  color(Render.WEED)
  love.graphics.circle("fill", w.x, w.y, w.size * 0.25, 10)
  love.graphics.setLineWidth(1)
end

--- A bolt of lightning coming down on (x, y): a jagged line out of the sky
--- (from high up the screen) with a branch or two, a white core in a blue
--- glow, and a flash where it lands. `k` is 0 when it strikes and 1 once it
--- has faded; `seed` keeps its shape the same from frame to frame.
function Render.bolt(x, y, seed, k)
  local rng = love.math.newRandomGenerator(math.floor(seed * 100000) + 1)
  local alpha = 1 - k
  local top = y - 700
  local pts = { x + (rng:random() - 0.5) * 160, top }
  local n = 12
  for i = 1, n - 1 do
    local f = i / n
    pts[#pts + 1] = x + (pts[1] - x) * (1 - f) + (rng:random() - 0.5) * 60
    pts[#pts + 1] = top + (y - top) * f
  end
  pts[#pts + 1], pts[#pts + 2] = x, y
  local branches = {}
  for _ = 1, 2 do
    local i = rng:random(3, n - 3)
    local bx, by = pts[i * 2 - 1], pts[i * 2]
    local dir = rng:random() < 0.5 and -1 or 1
    branches[#branches + 1] = { bx, by, bx + dir * (30 + rng:random() * 50), by + 40 + rng:random() * 60,
      bx + dir * (50 + rng:random() * 70), by + 90 + rng:random() * 80 }
  end
  -- The flash on the ground.
  color(Render.GLOW, 0.35 * alpha)
  love.graphics.circle("fill", x, y, 60 * (0.6 + 0.4 * k), 24)
  color(Render.RAY, 0.8 * alpha)
  love.graphics.circle("fill", x, y, 18 * (1 - k * 0.5), 16)
  for pass = 1, 2 do
    local w, c, a = pass == 1 and 10 or 3, pass == 1 and Render.GLOW or Render.RAY, pass == 1 and 0.35 or 1
    color(c, a * alpha)
    love.graphics.setLineWidth(w)
    love.graphics.line(pts)
    love.graphics.setLineWidth(w * 0.5)
    for _, br in ipairs(branches) do
      love.graphics.line(br)
    end
  end
  love.graphics.setLineWidth(1)
end

--- Where a bolt is about to come down: a ring on the ground flickering
--- brighter and closing in as the strike nears. `k` is 0 when it is first
--- marked and 1 as it strikes.
function Render.boltWarning(x, y, r, k, time)
  local flicker = (math.sin(time * (20 + 40 * k)) > 0) and 1 or 0.4
  color(Render.GLOW, (0.08 + 0.2 * k) * flicker)
  love.graphics.circle("fill", x, y, r, 24)
  love.graphics.setLineWidth(2)
  color(Render.RAY, (0.3 + 0.6 * k) * flicker)
  love.graphics.circle("line", x, y, r * (1.4 - 0.4 * k), 24)
  love.graphics.setLineWidth(1)
end

--- A felled tripod: the head down on its side, cracked open and leaking,
--- the legs sprawled out stiff, a hatch open on the ground. `s` is
--- { x, y, angle }.
function Render.wreck(s, time)
  local x, y, angle = s.x, s.y, s.angle
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", x + 6, y + 6, 46, 34)
  color(Render.WEED, 0.8)
  love.graphics.ellipse("fill", x - 14, y + 18, 24, 12)
  love.graphics.setLineWidth(5)
  for i, off in ipairs({ 2.6, 0.9, -1.2 }) do
    local a = angle + off
    local kx, ky = x + math.cos(a) * 50, y + math.sin(a) * 50
    local fx, fy = x + math.cos(a + 0.35 * (i - 2)) * 100, y + math.sin(a + 0.35 * (i - 2)) * 100
    color(SEAM)
    love.graphics.line(x, y, kx, ky, fx, fy)
    color(Render.METAL_DARK)
    love.graphics.setLineWidth(3)
    love.graphics.line(x, y, kx, ky, fx, fy)
    love.graphics.setLineWidth(5)
    love.graphics.circle("fill", kx, ky, 5, 10)
  end
  love.graphics.setLineWidth(1)
  drawShell(x, y, angle + 0.3, time, 1)
  -- The hatch blown open, and something pale slumped out of it.
  local fx, fy = math.cos(angle + 0.3), math.sin(angle + 0.3)
  local hx, hy = x - fx * 6 + fy * 10, y - fy * 6 - fx * 10
  love.graphics.setColor(0.05, 0.05, 0.05)
  love.graphics.ellipse("fill", hx, hy, 10, 7)
  love.graphics.setColor(0.72, 0.66, 0.58)
  love.graphics.ellipse("fill", hx + fy * 10, hy - fx * 10, 7, 5)
  love.graphics.setLineWidth(2)
  for k = -1, 1 do
    local a = angle + 0.3 - math.pi / 2 + k * 0.5
    love.graphics.line(hx + fy * 10, hy - fx * 10, hx + fy * 10 + math.cos(a) * 14,
      hy - fx * 10 + math.sin(a) * 14)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
