-- How the Floor Manager looks (floor_manager.lua's walker), on every screen:
-- Fobos Base's Arachnotron, drawn at world size, seen from above.
--
-- Four mechanical legs that really walk: each foot stays planted on the
-- floor while the body moves over it and steps when it has been left too
-- far behind its rest spot, the diagonal pairs taking turns, so he picks his
-- way across the Hangar like a spider. Each leg is a thigh and a shin with
-- a hydraulic ram along the thigh, bolted at the knee, three claws on the
-- foot. For a stomp the legs rear (feet pulled in and lifted, knees high).
--
-- On them an armoured octagon, hazard stripes round its rim, rivets, status
-- lights blinking, two exhaust stacks puffing; on that the glass dome and
-- the manager's brain in it, folded and pulsing, an eye on a stalk; the
-- plasma cannon under the front, twin barrels in coils that glow green
-- (brighter as it charges, a ball of plasma swelling at the muzzle, a flash
-- as it streams); his clipboard taped to the side. Hurt, it shows: the dome
-- cracks under half his health, and under a quarter he sparks and smokes.
-- Shot off, the cannon leaves a stump and dangling cables.
--
--   local look = Look.new()
--   Look.update(look, m, dt)      -- m: floor_manager.lua's shown walker
--   Look.draw(look, m, clock)
--   Look.drawWreck(wreck, clock)  -- { x, y, angle } where he went down

local Look = {}

Look.SCALE = 1.3 -- the hull, dome and cannon are drawn this much bigger than their plan below
Look.MUZZLE = 52 -- the cannon's end, in the plan: 52 * SCALE px out in the world (floor_manager.lua's MUZZLE)

local THIGH, SHIN = 54, 60 -- px, each leg's two parts
local HIP = 23 -- px out from his middle to each hip, along the diagonals
local REACH = 86 -- px from his middle out to where a foot rests
local STEP_AT = 44 -- px a foot is left behind its rest spot before it steps...
local STEP_ANYWAY = 80 -- ...and this far behind it steps whatever the other legs are doing
local STEP_TIME = 0.18 -- seconds a step takes
local CORNERS = { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } } -- front left, front right, back right, back left

local C = {
  steel = { 0.40, 0.38, 0.37 },
  steelHi = { 0.62, 0.60, 0.58 },
  steelDark = { 0.18, 0.17, 0.17 },
  black = { 0.06, 0.06, 0.06 },
  hazard = { 0.95, 0.72, 0.10 },
  glass = { 0.30, 0.55, 0.52 },
  brain = { 0.92, 0.58, 0.60 },
  brainDark = { 0.68, 0.34, 0.40 },
  vein = { 0.80, 0.22, 0.28 },
  eye = { 1.00, 0.18, 0.10 },
  plasma = { 0.35, 1.00, 0.45 },
  plasmaHot = { 0.85, 1.00, 0.85 },
  paper = { 0.92, 0.90, 0.82 },
  board = { 0.55, 0.40, 0.22 },
}

local random = love.math.random

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function dist(ax, ay, bx, by)
  return math.sqrt((ax - bx) ^ 2 + (ay - by) ^ 2)
end

--- Where hip `i` and its foot's rest spot are, for a body at (x, y) facing `a`.
local function corner(x, y, a, i, reach)
  local c = CORNERS[i]
  local la = a + math.atan2(c[2], c[1]) -- out along the diagonal
  return x + math.cos(la) * HIP, y + math.sin(la) * HIP, x + math.cos(la) * reach, y + math.sin(la) * reach
end

function Look.new()
  return { legs = nil, puffs = {}, sparks = {}, lastX = nil, lastY = nil }
end

--- Step the legs and the smoke for walker `m` (dx, dy, facing, move).
function Look.update(look, m, dt)
  local x, y, a = m.dx, m.dy, m.facing
  local vx, vy = 0, 0
  if look.lastX then
    vx, vy = (x - look.lastX) / math.max(dt, 1e-3), (y - look.lastY) / math.max(dt, 1e-3)
  end
  look.lastX, look.lastY = x, y
  if not look.legs or dist(x, y, look.legs[1].x, look.legs[1].y) > 300 then
    look.legs = {}
    for i = 1, 4 do
      local _, _, rx, ry = corner(x, y, a, i, REACH)
      look.legs[i] = { x = rx, y = ry, fromX = rx, fromY = ry, toX = rx, toY = ry, t = 1 }
    end
  end
  local rearing = m.move == 1
  for i, l in ipairs(look.legs) do
    local _, _, rx, ry = corner(x, y, a, i, rearing and REACH * 0.62 or REACH)
    if l.t < 1 then
      l.t = math.min(1, l.t + dt / STEP_TIME)
      local k = l.t * l.t * (3 - 2 * l.t)
      l.x, l.y = l.fromX + (l.toX - l.fromX) * k, l.fromY + (l.toY - l.fromY) * k
    else
      -- Left too far behind, and neither leg of the other diagonal pair
      -- stepping (its own diagonal partner may step with it): step, landing a
      -- little ahead of where the body is going.
      local busy = look.legs[i % 4 + 1].t < 1 or look.legs[(i + 2) % 4 + 1].t < 1
      local behind = dist(l.x, l.y, rx, ry)
      if (behind > STEP_AT and not busy) or behind > STEP_ANYWAY or (rearing and behind > 6) then
        l.fromX, l.fromY, l.t = l.x, l.y, 0
        l.toX, l.toY = rx + vx * STEP_TIME * 1.5, ry + vy * STEP_TIME * 1.5
      end
    end
  end
  -- Smoke from the stacks, more when he strains (a charge, a stomp) or is hurt.
  local hurt = m.max and m.max > 0 and m.hp / m.max or 1
  local rate = (m.move ~= 0 and 9 or 3) + (hurt < 0.25 and 6 or 0)
  if random() < dt * rate then
    for _, side in ipairs({ -1, 1 }) do
      local sx = x - math.cos(a) * 31 + math.cos(a + math.pi / 2) * side * 13
      local sy = y - math.sin(a) * 31 + math.sin(a + math.pi / 2) * side * 13
      look.puffs[#look.puffs + 1] = { x = sx, y = sy, t = 0, life = 0.9 + random() * 0.6,
        vx = -math.cos(a) * 20 + (random() - 0.5) * 16, vy = -math.sin(a) * 20 + (random() - 0.5) * 16 }
    end
  end
  for i = #look.puffs, 1, -1 do
    local p = look.puffs[i]
    p.t, p.x, p.y = p.t + dt, p.x + p.vx * dt, p.y + p.vy * dt
    if p.t >= p.life then
      table.remove(look.puffs, i)
    end
  end
  if hurt < 0.25 and random() < dt * 8 then -- sparks off him, badly hurt
    local sa = random() * 2 * math.pi
    look.sparks[#look.sparks + 1] = { x = x + math.cos(sa) * 18, y = y + math.sin(sa) * 18, t = 0,
      vx = math.cos(sa) * (60 + random() * 80), vy = math.sin(sa) * (60 + random() * 80) }
  end
  for i = #look.sparks, 1, -1 do
    local s = look.sparks[i]
    s.t, s.x, s.y = s.t + dt, s.x + s.vx * dt, s.y + s.vy * dt
    if s.t > 0.35 then
      table.remove(look.sparks, i)
    end
  end
end

--- One leg from its hip (hx, hy) to its foot (fx, fy), the knee bent out
--- away from his middle (cx, cy); `lift` 0..1 how high the foot is off
--- the floor (a step, or rearing).
local function drawLeg(hx, hy, fx, fy, cx, cy, lift)
  local d = math.min(dist(hx, hy, fx, fy), THIGH + SHIN - 1)
  local base = math.atan2(fy - hy, fx - hx)
  local bend = math.acos(math.max(-1, math.min(1, (THIGH * THIGH + d * d - SHIN * SHIN) / (2 * THIGH * d))))
  -- Bend the knee to whichever side is further from his middle.
  local k1x, k1y = hx + math.cos(base + bend) * THIGH, hy + math.sin(base + bend) * THIGH
  local k2x, k2y = hx + math.cos(base - bend) * THIGH, hy + math.sin(base - bend) * THIGH
  local kx, ky = k1x, k1y
  if dist(k2x, k2y, cx, cy) > dist(k1x, k1y, cx, cy) then
    kx, ky = k2x, k2y
  end
  -- A lifted foot (and the knee over it) sits a little further out: higher, seen from above.
  local ox, oy = (fx - cx) / math.max(1, dist(fx, fy, cx, cy)), (fy - cy) / math.max(1, dist(fx, fy, cx, cy))
  kx, ky = kx + ox * lift * 6, ky + oy * lift * 6
  local footX, footY = fx + ox * lift * 4, fy + oy * lift * 4
  -- The foot's shadow, left behind on the floor when it lifts.
  love.graphics.setColor(0, 0, 0, 0.3 * (1 - lift * 0.5))
  love.graphics.circle("fill", fx + 3, fy + 3, 6, 10)
  -- Thigh, its ram, the knee, the shin.
  color(C.steelDark)
  love.graphics.setLineWidth(9)
  love.graphics.line(hx, hy, kx, ky)
  color(C.steel)
  love.graphics.setLineWidth(6)
  love.graphics.line(hx, hy, kx, ky)
  color(C.steelHi)
  love.graphics.setLineWidth(2) -- the hydraulic ram along it
  local px, py = -(ky - hy) / THIGH * 4, (kx - hx) / THIGH * 4
  love.graphics.line(hx + px + (kx - hx) * 0.15, hy + py + (ky - hy) * 0.15, hx + px + (kx - hx) * 0.8,
    hy + py + (ky - hy) * 0.8)
  color(C.steelDark)
  love.graphics.setLineWidth(7)
  love.graphics.line(kx, ky, footX, footY)
  color(C.steel)
  love.graphics.setLineWidth(4)
  love.graphics.line(kx, ky, footX, footY)
  love.graphics.setLineWidth(1)
  color(C.steelDark)
  love.graphics.circle("fill", kx, ky, 6, 12)
  color(C.steelHi)
  love.graphics.circle("fill", kx, ky, 2.5, 8) -- the bolt
  -- Three claws on the foot, splayed out the way the leg runs.
  local fa = math.atan2(footY - ky, footX - kx)
  color(C.black)
  love.graphics.setLineWidth(3)
  for _, off in ipairs({ -0.6, 0, 0.6 }) do
    love.graphics.line(footX, footY, footX + math.cos(fa + off) * 9, footY + math.sin(fa + off) * 9)
  end
  love.graphics.setLineWidth(1)
  color(C.steelDark)
  love.graphics.circle("fill", footX, footY, 4.5, 10)
end

--- The brain in its dome at the origin (facing +x): folds, veins, the eye
--- on its stalk; `pulse` how swollen it is.
local function drawBrain(pulse, cracked)
  -- The dome's rim and the fluid in it.
  color(C.steelDark)
  love.graphics.circle("fill", -2, 0, 17, 28)
  color(C.glass, 0.95)
  love.graphics.circle("fill", -2, 0, 15, 28)
  -- The brain: two halves, their folds, a vein or two.
  local s = 1 + 0.05 * pulse
  color(C.brainDark)
  love.graphics.ellipse("fill", -2, 0, 12.5 * s, 11 * s, 24)
  color(C.brain)
  love.graphics.ellipse("fill", -2.5, -0.5, 11.5 * s, 10 * s, 24)
  color(C.brainDark)
  love.graphics.setLineWidth(1.4)
  love.graphics.line(-13, 0, 9, 0) -- between the halves
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.line(-10, side * 3, -7, side * 6, -3, side * 4, 1, side * 7, 5, side * 4)
    love.graphics.line(-8, side * 8, -4, side * 7.5, 0, side * 9)
    love.graphics.line(-12, side * 5.5, -11, side * 8)
  end
  color(C.vein)
  love.graphics.setLineWidth(1)
  love.graphics.line(4, -3, 7, -5, 9, -3)
  love.graphics.line(-6, 4, -9, 6)
  -- The eye on its stalk, out over the front, still red.
  color(C.brainDark)
  love.graphics.setLineWidth(2)
  love.graphics.line(6, 0, 12, -1)
  love.graphics.setLineWidth(1)
  color(C.paper)
  love.graphics.circle("fill", 13, -1, 3, 10)
  color(C.eye)
  love.graphics.circle("fill", 14, -1, 1.8, 8)
  -- The glass catching the light, and cracks in it once he's hurt.
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.arc("fill", -2, 0, 14, 3.5, 4.6, 10)
  love.graphics.setColor(1, 1, 1, 0.15)
  love.graphics.circle("line", -2, 0, 15, 28)
  if cracked > 0 then
    love.graphics.setColor(0.9, 1, 0.95, 0.55)
    love.graphics.line(-12, -8, -5, -2, -7, 5)
    love.graphics.line(-5, -2, 2, -6)
    if cracked > 1 then
      love.graphics.line(4, 8, 0, 3, 8, 1)
      love.graphics.line(-14, 4, -9, 2)
    end
  end
end

--- The cannon under the front (facing +x), from the hull out to MUZZLE:
--- its housing, twin barrels, coils glowing `heat` 0..1; `charge` 0..1 a
--- ball swelling at the muzzle; `firing` a flash there.
local function drawCannon(heat, charge, firing, clock)
  color(C.steelDark)
  love.graphics.rectangle("fill", 14, -9, 18, 18, 3) -- the housing
  color(C.steel)
  love.graphics.rectangle("fill", 16, -7, 14, 14, 2)
  for _, side in ipairs({ -1, 1 }) do -- twin barrels
    color(C.steelDark)
    love.graphics.rectangle("fill", 28, side * 4 - 3, Look.MUZZLE - 30, 6, 2)
    color(C.steel)
    love.graphics.rectangle("fill", 28, side * 4 - 2, Look.MUZZLE - 30, 2)
    for x = 32, Look.MUZZLE - 6, 5 do -- the coils
      love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.25 + 0.75 * heat)
      love.graphics.rectangle("fill", x, side * 4 - 3.5, 2, 7)
    end
  end
  if charge > 0 then
    local r = 3 + charge * 7 + math.sin(clock * 40) * 0.8
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.5)
    love.graphics.circle("fill", Look.MUZZLE, 0, r * 1.6, 16)
    color(C.plasmaHot)
    love.graphics.circle("fill", Look.MUZZLE, 0, r, 14)
  end
  if firing and math.floor(clock * 22) % 2 == 0 then
    color(C.plasmaHot)
    love.graphics.polygon("fill", Look.MUZZLE, -6, Look.MUZZLE + 14, 0, Look.MUZZLE, 6)
  end
end

--- His stump, once the cannon is shot off: torn housing, cables hanging, sparks.
local function drawStump(clock)
  color(C.black)
  love.graphics.rectangle("fill", 14, -8, 12, 16, 2)
  love.graphics.setLineWidth(2)
  for k, c in ipairs({ { 0.9, 0.2, 0.2 }, { 0.2, 0.4, 0.9 }, { 0.9, 0.8, 0.2 } }) do
    color(c)
    local sway = math.sin(clock * 3 + k) * 3
    love.graphics.line(24, (k - 2) * 4, 30, (k - 2) * 5 + sway, 34, (k - 2) * 4 + sway * 1.5)
  end
  love.graphics.setLineWidth(1)
  if random() < 0.35 then
    love.graphics.setColor(1, 0.85, 0.4)
    love.graphics.circle("fill", 34 + random() * 4, (random() - 0.5) * 10, 1.5, 6)
  end
end

--- The hull at the origin (facing +x): an octagon, hazard stripes round the
--- rim, rivets, the stacks at the back, lights blinking (out when `dead`).
local function drawHull(clock, dead)
  local pts = {}
  for k = 0, 7 do
    local a = k * math.pi / 4 + math.pi / 8
    pts[#pts + 1], pts[#pts + 2] = math.cos(a) * 28, math.sin(a) * 28
  end
  color(C.steelDark)
  love.graphics.polygon("fill", pts)
  -- The rim, in hazard stripes.
  for k = 0, 15 do
    local a0, a1 = k * math.pi / 8, (k + 1) * math.pi / 8
    color(k % 2 == 0 and C.hazard or C.black)
    love.graphics.polygon("fill", math.cos(a0) * 26, math.sin(a0) * 26, math.cos(a1) * 26, math.sin(a1) * 26,
      math.cos(a1) * 21, math.sin(a1) * 21, math.cos(a0) * 21, math.sin(a0) * 21)
  end
  color(C.steel)
  love.graphics.circle("fill", 0, 0, 21, 24)
  color(C.steelHi, 0.5)
  love.graphics.arc("fill", 0, 0, 21, 3.4, 4.4, 8) -- light on the plate
  for k = 0, 11 do -- rivets
    local a = k * math.pi / 6
    color(C.steelDark)
    love.graphics.circle("fill", math.cos(a) * 18.5, math.sin(a) * 18.5, 1.3, 6)
  end
  -- The exhaust stacks at the back.
  for _, side in ipairs({ -1, 1 }) do
    color(C.black)
    love.graphics.circle("fill", -24, side * 10, 4.5, 10)
    color(C.steelDark)
    love.graphics.circle("line", -24, side * 10, 4.5, 10)
  end
  -- Status lights round the dome, blinking out of step.
  for k = 0, 3 do
    local a = math.pi / 4 + k * math.pi / 2
    local on = not dead and math.floor(clock * 2.5 + k * 0.7) % 3 ~= 0
    if k % 2 == 0 then
      love.graphics.setColor(1, 0.2, 0.1, on and 1 or 0.25)
    else
      love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], on and 1 or 0.25)
    end
    love.graphics.circle("fill", math.cos(a) * 19, math.sin(a) * 19, 1.8, 8)
  end
end

--- His clipboard, taped to his left flank.
local function drawClipboard()
  love.graphics.push()
  love.graphics.translate(-4, -29)
  love.graphics.rotate(-0.15)
  color(C.board)
  love.graphics.rectangle("fill", -7, -5, 14, 10, 1)
  color(C.paper)
  love.graphics.rectangle("fill", -6, -4, 12, 8)
  love.graphics.setColor(0.2, 0.2, 0.2, 0.6)
  for k = -2, 2, 2 do
    love.graphics.rectangle("fill", -4, k, 8, 0.8)
  end
  love.graphics.setColor(0.85, 0.85, 0.78, 0.85)
  love.graphics.rectangle("fill", -9, -1.5, 18, 3) -- the tape
  love.graphics.pop()
end

--- Draw walker `m` (dx, dy, facing, move, cannon, hp, max) with `look`'s legs.
function Look.draw(look, m, clock)
  local x, y, a = m.dx, m.dy, m.facing
  -- The smoke under him first, then a shadow.
  for _, p in ipairs(look.puffs) do
    local k = p.t / p.life
    love.graphics.setColor(0.22, 0.2, 0.2, 0.45 * (1 - k))
    love.graphics.circle("fill", p.x, p.y, 5 + k * 14, 10)
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x + 8, y + 8, 44, 40, 24)
  -- Legs (under the hull).
  local rearing = m.move == 1
  local rear = rearing and math.min(1, m.rearT or 0) or 0
  if look.legs then
    for i, l in ipairs(look.legs) do
      local hx, hy = corner(x, y, a, i, REACH)
      local step = l.t < 1 and math.sin(l.t * math.pi) or 0
      drawLeg(hx, hy, l.x, l.y, x, y, math.max(step, rear))
    end
  end
  local hurt = m.max and m.max > 0 and m.hp / m.max or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  love.graphics.scale(Look.SCALE * (1 + 0.08 * rear)) -- reared up: a touch bigger, nearer the eye
  if m.cannon > 0 then
    local charging = m.move == 2 and math.min(1, m.chargeT or 0) or 0
    local heat = m.move == 2 and (0.4 + 0.6 * charging) or m.move == 3 and 1 or 0.1
    drawCannon(heat, charging, m.move == 3, clock)
  else
    drawStump(clock)
  end
  drawHull(clock)
  drawClipboard()
  drawBrain(0.5 + 0.5 * math.sin(clock * 3.2), hurt < 0.25 and 2 or hurt < 0.5 and 1 or 0)
  love.graphics.pop()
  for _, s in ipairs(look.sparks) do
    love.graphics.setColor(1, 0.85, 0.4, 1 - s.t / 0.35)
    love.graphics.line(s.x, s.y, s.x - s.vx * 0.03, s.y - s.vy * 0.03)
  end
  love.graphics.setColor(1, 1, 1)
end

--- His wreck where he went down: legs splayed out flat, the hull dark, the
--- dome smashed and empty, smoke going up.
function Look.drawWreck(wreck, clock)
  local x, y, a = wreck.x, wreck.y, wreck.angle
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x + 8, y + 8, 44, 40, 24)
  for i = 1, 4 do
    local hx, hy, rx, ry = corner(x, y, a, i, REACH * 1.15)
    drawLeg(hx, hy, rx, ry, x, y, 0)
  end
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  love.graphics.scale(Look.SCALE)
  drawStump(clock)
  drawHull(clock, true)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.circle("fill", 0, 0, 22, 24) -- scorched dark
  color(C.steelDark)
  love.graphics.circle("fill", -2, 0, 17, 28)
  love.graphics.setColor(0.3, 0.5, 0.48, 0.6) -- the dome, smashed: shards round the rim
  for k = 0, 7 do
    local sa = k * math.pi / 4
    love.graphics.polygon("fill", -2 + math.cos(sa) * 15, math.sin(sa) * 15, -2 + math.cos(sa + 0.3) * 15,
      math.sin(sa + 0.3) * 15, -2 + math.cos(sa + 0.15) * 9, math.sin(sa + 0.15) * 9)
  end
  love.graphics.pop()
  for k = 0, 2 do -- smoke rising, puff after puff
    local f = (clock * 0.5 + k / 3) % 1
    love.graphics.setColor(0.25, 0.22, 0.2, 0.5 * (1 - f))
    love.graphics.circle("fill", x - 6 + k * 6, y - 10 - f * 50, 6 + f * 12, 10)
  end
  love.graphics.setColor(1, 1, 1)
end

return Look
