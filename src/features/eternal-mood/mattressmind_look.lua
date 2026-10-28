-- How the Spider Mattressmind looks (mattressmind.lua), seen from above at
-- world size: a striped mattress, pillow at the back, dragged along under
-- a steel chassis on four long mechanical spider legs that step out over
-- its edges; on the chassis a giant brain, folded and veined and pulsing,
-- two small red eyes at its front; slung under its chin a chaingun, a
-- drum of six barrels that spins up before it fires, and flashes as it
-- does. Yawning, the front of the brain splits into a vast mouth and Zs
-- float up out of it. Under half its health its eyes droop.
--
--   Look.draw(m, clock)        m: mattressmind.lua's `shown` (dx, dy, facing, aim, move, moveAt, stride, ...)
--   Look.drawWreck(w, clock)   where it went down: w { x, y, angle }

local Look = {}

local C = {
  mattress = { 0.82, 0.80, 0.86 },
  stripe = { 0.55, 0.62, 0.80 },
  pillow = { 0.95, 0.94, 0.96 },
  steel = { 0.40, 0.38, 0.37 },
  steelHi = { 0.62, 0.60, 0.58 },
  steelDark = { 0.18, 0.17, 0.17 },
  brain = { 0.92, 0.58, 0.60 },
  brainDark = { 0.68, 0.34, 0.40 },
  brainHi = { 1.00, 0.76, 0.76 },
  vein = { 0.80, 0.22, 0.28 },
  eye = { 1.00, 0.18, 0.10 },
  mouth = { 0.25, 0.04, 0.06 },
  flash = { 1.00, 0.85, 0.45 },
  zed = { 0.70, 0.75, 1.00 },
  shadow = { 0, 0, 0, 0.35 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local MAT_L, MAT_W = 150, 112 -- the mattress, along and across it
local LEGS = { { 1, -1 }, { 1, 1 }, { -1, 1 }, { -1, -1 } } -- front left, front right, back right, back left

--- The mattress, in its own frame (+x ahead).
local function mattress(dented)
  color(C.shadow)
  love.graphics.rectangle("fill", -MAT_L / 2 + 8, -MAT_W / 2 + 10, MAT_L, MAT_W, 14)
  color(C.mattress)
  love.graphics.rectangle("fill", -MAT_L / 2, -MAT_W / 2, MAT_L, MAT_W, 14)
  color(C.stripe)
  for x = -MAT_L / 2 + 14, MAT_L / 2 - 14, 22 do
    love.graphics.rectangle("fill", x, -MAT_W / 2 + 5, 8, MAT_W - 10)
  end
  color(C.pillow)
  love.graphics.rectangle("fill", -MAT_L / 2 + 8, -MAT_W / 2 + 14, 30, MAT_W - 28, 10)
  love.graphics.setColor(0, 0, 0, dented and 0.25 or 0.12)
  love.graphics.ellipse("fill", 10, 0, 50, 40, 20)
  love.graphics.setColor(0.45, 0.42, 0.50)
  love.graphics.rectangle("line", -MAT_L / 2 + 3, -MAT_W / 2 + 3, MAT_L - 6, MAT_W - 6, 12)
end

--- A leg from the chassis out past the mattress's corner: thigh up, shin
--- down to a claw, stepping with `phase`; `rear` 0..1 for the slam.
local function leg(cx, cy, phase, rear, flat)
  local hx, hy = cx * 26, cy * 22 -- hip
  local swing = flat and 0 or math.sin(phase) * 12
  local fx = cx * (MAT_L / 2 + 22) + swing * cx
  local fy = cy * (MAT_W / 2 + 26)
  if rear > 0 then -- pulled in and up
    fx, fy = fx * (1 - 0.3 * rear), fy * (1 - 0.3 * rear)
  end
  local kx, ky = (hx + fx) / 2 + cx * 10, (hy + fy) / 2 + cy * (flat and 4 or 26 + rear * 14) -- the knee, high
  color(C.steelDark)
  love.graphics.setLineWidth(10)
  love.graphics.line(hx, hy, kx, ky, fx, fy)
  color(C.steel)
  love.graphics.setLineWidth(5)
  love.graphics.line(hx, hy, kx, ky, fx, fy)
  love.graphics.setLineWidth(1)
  color(C.steelHi)
  love.graphics.circle("fill", kx, ky, 6, 10)
  color(C.steelDark)
  love.graphics.polygon("fill", fx - 6, fy - 4, fx + 6, fy - 4, fx, fy + 8) -- the claw
end

--- The chaingun under its chin, pointing along `aim` (in its own frame):
--- a drum of barrels turning by `spin`, `flash` when it fires.
local function chaingun(aim, spin, flash, hot)
  love.graphics.push()
  love.graphics.rotate(aim)
  color(C.steelDark)
  love.graphics.rectangle("fill", 30, -12, 36, 24, 5)
  color(C.steel)
  love.graphics.rectangle("fill", 36, -10, 30, 20, 4)
  for k = 0, 5 do -- the barrels, round the drum
    local a = spin + k * math.pi / 3
    local by = math.sin(a) * 7
    local shade = 0.5 + 0.5 * math.cos(a)
    love.graphics.setColor(0.2 + 0.4 * shade, 0.2 + 0.4 * shade, 0.2 + 0.4 * shade)
    love.graphics.rectangle("fill", 60, by - 2, 18, 4)
  end
  if hot > 0 then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(1, 0.55, 0.15, 0.6 * hot)
    love.graphics.circle("fill", 78, 0, 9, 12)
    love.graphics.setBlendMode("alpha")
  end
  if flash then
    love.graphics.setBlendMode("add")
    color(C.flash, 0.9)
    love.graphics.polygon("fill", 78, -8, 100, 0, 78, 8)
    love.graphics.circle("fill", 82, 0, 10, 12)
    love.graphics.setBlendMode("alpha")
  end
  love.graphics.pop()
end

--- The brain on the chassis: folds, veins, a pulse; the eyes; the yawn.
local function brain(clock, yawn, sleepy, dead)
  local pulse = dead and 0 or 0.04 * math.sin(clock * 3)
  local r = 40 * (1 + pulse)
  color(C.steelDark)
  love.graphics.ellipse("fill", 0, 0, 46, 42, 24) -- the chassis
  color(C.steel)
  love.graphics.ellipse("line", 0, 0, 44, 40, 24)
  color(dead and C.brainDark or C.brain)
  love.graphics.ellipse("fill", -4, 0, r, r * 0.9, 24)
  color(C.brainHi)
  love.graphics.ellipse("fill", -14, -12, r * 0.35, r * 0.25, 14)
  color(C.brainDark) -- the folds
  love.graphics.setLineWidth(2.5)
  love.graphics.line(-38, 0, 30, 0) -- the cleft
  for _, side in ipairs({ -1, 1 }) do
    for k = 0, 3 do
      local x = -30 + k * 16
      love.graphics.arc("line", "open", x, side * 14, 9, side > 0 and 0.2 or math.pi + 0.2,
        side > 0 and math.pi - 0.2 or 2 * math.pi - 0.2, 8)
    end
  end
  love.graphics.setLineWidth(1)
  color(C.vein, dead and 0.3 or 0.8)
  love.graphics.line(-20, -24, -6, -16, 6, -26)
  love.graphics.line(-24, 22, -8, 14, 10, 24)
  if yawn > 0 then -- the front splitting into a mouth
    color(C.mouth)
    love.graphics.ellipse("fill", 26, 0, 6 + 14 * yawn, 10 + 22 * yawn, 20)
    love.graphics.setColor(0.95, 0.93, 0.88)
    for k = -2, 2 do
      love.graphics.polygon("fill", 26 - 4 - 10 * yawn, k * 7 * yawn - 2, 26 - 4 - 10 * yawn, k * 7 * yawn + 2,
        26 - 10 * yawn + 2, k * 7 * yawn)
    end
  end
  local lid = dead and 0 or (sleepy and 0.4 or 1) * (yawn > 0.5 and 0.3 or 1)
  for _, side in ipairs({ -1, 1 }) do
    color(C.steelDark)
    love.graphics.circle("fill", 34, side * 16, 6, 10)
    if lid > 0 then
      color(C.eye)
      love.graphics.ellipse("fill", 35, side * 16, 3.5, 3.5 * lid, 10)
    end
  end
end

function Look.draw(m, clock)
  local into = clock - (m.moveAt or clock)
  local rear = m.move == 3 and math.min(1, into / 0.6) or 0
  local yawn = 0
  if m.move == 4 then
    yawn = into < 0.4 and into / 0.4 or (into > 2.0 and math.max(0, 1 - (into - 2.0) / 0.2) or 1)
  end
  local spin = m.move == 1 and into * into * 15 or (m.move == 2 and into * 40 or 0) -- the drum spinning up
  local flash = m.move == 2 and math.floor(clock * 22) % 2 == 0
  local hot = m.move == 1 and math.min(1, into / 0.8) or (m.move == 2 and 1 or 0)
  local stride = m.stride or 0
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  love.graphics.rotate(m.facing)
  mattress(false)
  for i, l in ipairs(LEGS) do
    leg(l[1], l[2], stride * 0.06 + (i % 2) * math.pi, rear, false)
  end
  love.graphics.push()
  love.graphics.translate(0, -rear * 6) -- reared, the body lifts
  chaingun((m.aim or m.facing) - m.facing, spin, flash, hot)
  brain(clock, yawn, m.phase2, false)
  love.graphics.pop()
  love.graphics.pop()
  if yawn > 0 then -- Zs floating up out of it
    love.graphics.setColor(C.zed)
    for k = 0, 2 do
      local f = (clock * 0.7 + k / 3) % 1
      love.graphics.print("Z", m.dx + 30 + k * 12 + f * 20, m.dy - 40 - f * 60, 0, 1 + f, 1 + f)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- Where it fell: the legs splayed flat, the brain slumped grey on its
--- mattress, a last Z or two.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle)
  mattress(true)
  for _, l in ipairs(LEGS) do
    leg(l[1], l[2], 0, 0, true)
  end
  brain(clock, 0, true, true)
  love.graphics.pop()
  local f = (clock * 0.3) % 1
  love.graphics.setColor(C.zed[1], C.zed[2], C.zed[3], 1 - f)
  love.graphics.print("z", w.x + 20 + f * 10, w.y - 30 - f * 40)
  love.graphics.setColor(1, 1, 1)
end

return Look
