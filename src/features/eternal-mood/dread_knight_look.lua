-- How a Dread Knight looks (dread_knight.lua), seen from above at world
-- size, facing +x in his own frame: a head over a person in black plate,
-- cracked through with Heck's red glowing underneath; great pauldrons; a
-- horned helm with two red eyes in the slit; legs in braces, pistons down
-- them, boots stepping out under him as he walks. Out of each forearm,
-- where a hand should be, a long blade, its edge catching the light.
--
-- His poses: walking, blades low and forward; a blade drawn back over his
-- shoulder for a slash (the tell), then swept across; crouched with both
-- blades back for a lunge (the tell), then both driven forward; tucked,
-- leaving a smear of himself, as he throws himself aside.
--
--   Look.draw(m, clock)       m: dread_knight.lua's shown knight (dx, dy, facing, move, moveAt, stride, aim)
--   Look.drawBody(b, clock)   where one fell: b { x, y, angle }

local Look = {}

local C = {
  plate = { 0.17, 0.16, 0.17 },
  plateHi = { 0.42, 0.40, 0.42 },
  plateDark = { 0.07, 0.06, 0.07 },
  ink = { 0.03, 0.02, 0.02 }, -- his outline
  crack = { 1.00, 0.30, 0.10 },
  flesh = { 0.45, 0.12, 0.10 },
  piston = { 0.55, 0.52, 0.48 },
  blade = { 0.58, 0.60, 0.64 },
  bladeHi = { 0.93, 0.94, 0.97 },
  horn = { 0.66, 0.58, 0.46 },
  hornDark = { 0.38, 0.32, 0.24 },
  eye = { 1.00, 0.18, 0.08 },
  blood = { 0.30, 0.03, 0.03 },
  shadow = { 0, 0, 0, 0.35 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local POSE = { [1] = "windup", [2] = "slash", [3] = "crouch", [4] = "lunge", [5] = "dodge" }

-- Where each wrist is and which way its blade points, by pose, for the
-- right arm (side 1); the left is mirrored unless the pose gives it its
-- own (`left`). { wrist x, wrist y, blade angle }.
local ARMS = {
  walk = { 12, 15, 0.25 },
  windup = { -6, 17, 2.5, left = { 12, -12, -0.15 } }, -- the right blade back over his shoulder
  slash = { 13, -7, -1.3, left = { 4, -16, -0.9 } }, -- swept across to his left
  crouch = { -7, 15, 2.7 }, -- both back, low
  lunge = { 16, 7, -0.1 }, -- both driven forward
  dodge = { 2, 15, 2.3 },
  dead = { 5, 19, 1.2, left = { -9, -17, -2.4 } },
}

--- A blade out of the wrist at (x, y) along `a`, `len` long: the flat, its
--- edge catching the light, Heck's red where it grows out of him.
local function blade(x, y, a, len)
  local fx, fy = math.cos(a), math.sin(a)
  local px, py = -fy, fx
  local mx, my = x + fx * len * 0.6 + px * 1.2, y + fy * len * 0.6 + py * 1.2 -- a little curve
  local tx, ty = x + fx * len, y + fy * len
  color(C.ink)
  love.graphics.polygon("fill", x + px * 3.2, y + py * 3.2, x - px * 3.2, y - py * 3.2, mx - px * 2.8, my - py * 2.8,
    mx + px * 2.8, my + py * 2.8)
  love.graphics.polygon("fill", mx + px * 2.8, my + py * 2.8, mx - px * 2.8, my - py * 2.8, tx + fx * 1.5,
    ty + fy * 1.5)
  color(C.blade)
  love.graphics.polygon("fill", x + px * 2.2, y + py * 2.2, x - px * 2.2, y - py * 2.2, mx - px * 1.9, my - py * 1.9,
    mx + px * 1.9, my + py * 1.9)
  love.graphics.polygon("fill", mx + px * 1.9, my + py * 1.9, mx - px * 1.9, my - py * 1.9, tx, ty)
  color(C.bladeHi) -- the edge
  love.graphics.setLineWidth(1)
  love.graphics.line(x + px * 2, y + py * 2, mx + px * 1.8, my + py * 1.8, tx, ty)
  color(C.crack, 0.9) -- where it grows out of him
  love.graphics.circle("fill", x, y, 2, 8)
end

--- One arm, `side` 1 right or -1 left, in `pose`, `swing` from his stride.
local function arm(pose, side, swing)
  local a = ARMS[pose] or ARMS.walk
  local wx, wy, ba
  if side == -1 and a.left then
    wx, wy, ba = a.left[1], a.left[2], a.left[3]
  elseif side == -1 then
    wx, wy, ba = a[1], -a[2], -a[3]
  else
    wx, wy, ba = a[1], a[2], a[3]
  end
  if pose == "walk" then
    wx = wx + swing * side
  end
  local sx, sy = -1, side * 10
  local ex, ey = (sx + wx) / 2, (sy + wy) / 2 + side * 3 -- the elbow, out a little
  color(C.ink)
  love.graphics.setLineWidth(6.5)
  love.graphics.line(sx, sy, ex, ey, wx, wy)
  color(C.flesh) -- red muscle between the plates
  love.graphics.setLineWidth(4.5)
  love.graphics.line(sx, sy, ex, ey, wx, wy)
  color(C.plate) -- the vambrace down the forearm
  love.graphics.setLineWidth(4)
  love.graphics.line(ex + (wx - ex) * 0.3, ey + (wy - ey) * 0.3, wx, wy)
  color(C.plateHi, 0.8)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(ex + (wx - ex) * 0.35, ey + (wy - ey) * 0.35 - 1, wx, wy - 1)
  love.graphics.setLineWidth(1)
  blade(wx, wy, ba, pose == "lunge" and 28 or 25)
end

--- His legs and boots: stepping out under him by `stride` while he walks,
--- set wide crouched or lunging, pistons down the braces.
local function legs(pose, stride)
  for _, side in ipairs({ -1, 1 }) do
    local fx = math.sin(stride * 0.16) * 6 * side
    if pose == "crouch" then
      fx = side == 1 and -5 or 5
    elseif pose == "lunge" then
      fx = side == 1 and 8 or -8
    elseif pose ~= "walk" then
      fx = 0
    end
    local fy = side * 6
    color(C.ink)
    love.graphics.ellipse("fill", fx + 2, fy, 6, 4, 12)
    color(C.plate)
    love.graphics.ellipse("fill", fx + 2, fy, 5, 3, 12)
    color(C.piston) -- the brace
    love.graphics.setLineWidth(1.5)
    love.graphics.line(fx - 2, fy + side * 2.5, fx + 5, fy + side * 2.5)
    love.graphics.setLineWidth(1)
  end
end

--- Black plate, cracked red: his back, the spine ridge, the pauldrons.
local function torso(pose)
  local hunch = (pose == "crouch" or pose == "lunge") and 1 or 0
  color(C.ink)
  love.graphics.ellipse("fill", -1 + hunch, 0, 10.5, 12, 20)
  color(C.plate)
  love.graphics.ellipse("fill", -1 + hunch, 0, 9, 10.5, 20)
  color(C.plateHi, 0.5) -- lit from the top left
  love.graphics.ellipse("fill", -3 + hunch, -3, 4, 5, 12)
  color(C.crack, 0.85) -- the cracks, Heck showing through
  love.graphics.setLineWidth(1)
  love.graphics.line(-7, -3, -4, -1, -5, 3, -2, 5)
  love.graphics.line(-1, -8, 1, -5, 0, -2)
  love.graphics.line(2, 4, 4, 7, 3, 9)
  color(C.plateDark) -- the spine ridge
  love.graphics.setLineWidth(2)
  love.graphics.line(-9, 0, 4, 0)
  love.graphics.setLineWidth(1)
end

--- The pauldrons, ridged, a spike off each, over his shoulders.
local function pauldrons()
  for _, side in ipairs({ -1, 1 }) do
    local py = side * 10
    color(C.ink)
    love.graphics.polygon("fill", -5, py - side * 1, -1, py + side * 7.5, 4, py + side * 1)
    love.graphics.ellipse("fill", -1, py, 6.5, 6, 14)
    color(C.plate)
    love.graphics.ellipse("fill", -1, py, 5.5, 5, 14)
    color(C.plateHi, 0.6)
    love.graphics.ellipse("fill", -2.5, py - 1.5, 2.5, 2, 8)
    color(C.plateDark)
    love.graphics.setLineWidth(1)
    love.graphics.line(-4, py + side * 1.5, 2, py + side * 2.5)
  end
end

--- The helm: a horned skull of plate, two red eyes in the slit.
local function head(pose, clock)
  local hx = (pose == "crouch" or pose == "lunge") and 7.5 or 6
  for _, side in ipairs({ -1, 1 }) do -- the horns, out of the sides of the helm, sweeping out and forward
    color(C.ink)
    love.graphics.polygon("fill", hx - 3, side * 2.5, hx + 1, side * 3, hx + 1, side * 8.5, hx - 3, side * 7.5)
    love.graphics.polygon("fill", hx - 3, side * 7.5, hx + 1, side * 8.5, hx + 7, side * 11)
    color(C.hornDark)
    love.graphics.polygon("fill", hx - 2, side * 3, hx + 0.5, side * 3.5, hx + 0.5, side * 8, hx - 2, side * 7.2)
    love.graphics.polygon("fill", hx - 2, side * 7.2, hx + 0.5, side * 8, hx + 6, side * 10.4)
    color(C.horn)
    love.graphics.polygon("fill", hx - 1.2, side * 3.3, hx + 0.2, side * 3.5, hx + 0.2, side * 7.5, hx - 1.2, side * 7)
    love.graphics.line(hx, side * 7.6, hx + 5.5, side * 10.2)
  end
  color(C.ink)
  love.graphics.ellipse("fill", hx, 0, 5.5, 5, 14)
  color(C.plate)
  love.graphics.ellipse("fill", hx, 0, 4.5, 4, 14)
  color(C.plateHi, 0.6)
  love.graphics.ellipse("fill", hx - 1, -1.5, 2, 1.4, 8)
  local glow = 0.75 + 0.25 * math.sin(clock * 5)
  color(C.eye, glow)
  love.graphics.circle("fill", hx + 3.2, -1.6, 1, 6)
  love.graphics.circle("fill", hx + 3.2, 1.6, 1, 6)
end

local function body(pose, stride, clock)
  local swing = math.sin(stride * 0.16) * 3
  legs(pose, stride)
  torso(pose)
  arm(pose, -1, swing)
  arm(pose, 1, swing)
  pauldrons()
  head(pose, clock)
end

--- The smear he leaves throwing himself aside: faint copies of his
--- shoulders back along the way he came (`aim`).
local function smear(m)
  local bx, by = -math.cos(m.aim or 0), -math.sin(m.aim or 0)
  for k = 3, 1, -1 do
    local a = 0.35 - k * 0.09
    love.graphics.push()
    love.graphics.translate(m.dx + bx * k * 7, m.dy + by * k * 7)
    love.graphics.rotate(m.facing)
    love.graphics.setColor(C.plate[1], C.plate[2], C.plate[3], a)
    love.graphics.ellipse("fill", -1, 0, 9, 15, 14)
    love.graphics.setColor(C.crack[1], C.crack[2], C.crack[3], a * 0.6)
    love.graphics.ellipse("fill", -1, 0, 3, 6, 8)
    love.graphics.pop()
  end
end

function Look.draw(m, clock)
  local pose = POSE[m.move] or "walk"
  if pose == "dodge" then
    smear(m)
  end
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  color(C.shadow)
  love.graphics.ellipse("fill", 3, 4, 17, 15, 20)
  love.graphics.rotate(m.facing)
  body(pose, m.stride or 0, clock)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where one fell: face down, blades splayed, blood under him, the cracks
--- gone dark.
function Look.drawBody(b, clock)
  love.graphics.push()
  love.graphics.translate(b.x, b.y)
  love.graphics.rotate(b.angle + 0.5)
  color(C.blood, 0.75)
  love.graphics.ellipse("fill", 2, 3, 22, 18, 20)
  legs("dead", 0)
  torso("dead")
  arm("dead", -1, 0)
  arm("dead", 1, 0)
  pauldrons()
  head("dead", clock)
  color(C.plateDark, 0.55) -- the light gone out of him
  love.graphics.ellipse("fill", 0, 0, 12, 14, 16)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
