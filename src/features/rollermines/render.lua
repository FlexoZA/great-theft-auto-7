-- A rollermine drawn from above, stateless: a steel ball with dark seams
-- between its panels and a glowing eye, after Half-Life 2's. Its blades
-- fold out from the seams as it wakes and spin with it as it rolls.
--
--   Render.draw(x, y, pose, time)
--
-- `pose`: spin (radians it has rolled), heading (the way it rolls), blades
-- (0 shut .. 1 out), sink (0 up .. 1 half sunk in the ground), lift (0..1,
-- a hop: bigger and its shadow further off), armed (beeping: the eye goes
-- red and flashes), hurt (0..1, a white flash), alpha.

local Render = {}

Render.RADIUS = 12

local C = {
  steel = { 0.62, 0.66, 0.70 },
  steelDark = { 0.36, 0.39, 0.43 },
  steelLight = { 0.86, 0.89, 0.92 },
  seam = { 0.14, 0.15, 0.17 },
  blade = { 0.78, 0.80, 0.82 },
  bladeDark = { 0.30, 0.31, 0.33 },
  eye = { 0.35, 0.75, 1.00 },
  eyeArmed = { 1.00, 0.25, 0.20 },
  dirt = { 0.33, 0.27, 0.19 },
  dirtDark = { 0.22, 0.18, 0.13 },
  shadow = { 0, 0, 0, 0.3 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * (c[4] or 1))
end

function Render.draw(x, y, pose, time)
  local R = Render.RADIUS
  local alpha = pose.alpha or 1
  local lift = pose.lift or 0
  local sink = pose.sink or 0
  local scale = 1 + lift * 0.25
  local r = R * scale

  -- The ground it sits in, or its shadow.
  if sink > 0 then
    color(C.dirtDark, alpha * sink)
    love.graphics.ellipse("fill", x, y + 2, r + 7, r * 0.8 + 6)
    color(C.dirt, alpha * sink)
    love.graphics.ellipse("fill", x, y + 1, r + 4, r * 0.8 + 3)
  else
    color(C.shadow, alpha)
    love.graphics.circle("fill", x + 3 + lift * 8, y + 5 + lift * 12, r)
  end

  love.graphics.push()
  love.graphics.translate(x, y)

  -- The blades: three, folded out from the seams, turning as it rolls.
  local blades = pose.blades or 0
  if blades > 0 then
    for k = 0, 2 do
      local a = (pose.spin or 0) + k * 2 * math.pi / 3
      local ca, sa = math.cos(a), math.sin(a)
      local out = r + 7 * blades
      local w = 3.2
      local px, py = -sa * w, ca * w
      color(C.bladeDark, alpha)
      love.graphics.polygon("fill", ca * (r - 3) + px, sa * (r - 3) + py, ca * out, sa * out,
        ca * (r - 3) - px, sa * (r - 3) - py)
      color(C.blade, alpha)
      love.graphics.polygon("fill", ca * (r - 3) + px * 0.5, sa * (r - 3) + py * 0.5, ca * (out - 1.5),
        sa * (out - 1.5), ca * (r - 3), sa * (r - 3))
    end
  end

  -- The shell, lit from the top left.
  color(C.steelDark, alpha)
  love.graphics.circle("fill", 0, 0, r)
  color(C.steel, alpha)
  love.graphics.circle("fill", -r * 0.12, -r * 0.12, r * 0.86)
  -- The seams between the panels, rolling over it: three arcs that drift
  -- across the ball the way it rolls and come round again.
  local heading = pose.heading or 0
  local ch, sh = math.cos(heading), math.sin(heading)
  love.graphics.setLineWidth(1.6)
  color(C.seam, alpha * 0.9)
  for k = 0, 2 do
    local phase = ((pose.spin or 0) / (2 * math.pi) + k / 3) % 1 -- 0..1 across the ball
    local along = (phase * 2 - 1) * r * 0.85
    local half = math.sqrt(math.max(0, r * r * 0.72 - along * along))
    local cx, cy = ch * along, sh * along
    love.graphics.line(cx - sh * half, cy + ch * half, cx + sh * half, cy - ch * half)
  end
  love.graphics.setLineWidth(1)
  color(C.steelLight, alpha * 0.85)
  love.graphics.circle("fill", -r * 0.38, -r * 0.4, r * 0.24)

  -- The eye: blue, red and flashing when it is about to go.
  local armed = pose.armed
  local on = not armed or math.floor(time * 12) % 2 == 0
  local eye = armed and C.eyeArmed or C.eye
  local glow = (pose.blades or 0) > 0 and 1 or 0.35
  if on then
    color(eye, alpha * 0.35 * glow)
    love.graphics.circle("fill", 0, 0, r * 0.62)
    color(eye, alpha * glow)
    love.graphics.circle("fill", 0, 0, r * 0.3)
    love.graphics.setColor(1, 1, 1, alpha * glow * 0.9)
    love.graphics.circle("fill", -1, -1, r * 0.12)
  else
    color(C.seam, alpha)
    love.graphics.circle("fill", 0, 0, r * 0.3)
  end

  if (pose.hurt or 0) > 0 then
    love.graphics.setColor(1, 1, 1, alpha * pose.hurt)
    love.graphics.circle("fill", 0, 0, r)
  end
  love.graphics.pop()

  -- Half sunk: the near half of the dirt over its lower edge.
  if sink > 0 then
    color(C.dirt, alpha * sink)
    love.graphics.arc("fill", x, y + 1, r + 4, 0.15, math.pi - 0.15)
  end
end

return Render
