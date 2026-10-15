-- How the Baron of Heck looks (baron.lua), seen from above at world size:
-- a big horned brute, outlined dark so he reads as one, pink-hided above
-- the waist and shaggy brown goat legs below, cloven hooves stepping out
-- under him as he walks, a tail flicking behind. A wedge of a back, broad
-- shoulders knotted with muscle tapering to the waist, bone spikes down
-- the spine; long jointed arms ending in guns, no hands, the flesh grown
-- over the steel at the wrist; a long goat's skull with
-- glowing eyes and two great ridged horns sweeping out and forward. The
-- Snooze Gate's key hangs off his belt, brass, a tag with Zz on it. Green
-- fire burns up at his muzzles before he fires; he drops his head, horns
-- first, to charge; reels, eyes rolling, when he's run into a wall;
-- throws his head back to roar; crouches, guns on the floor, to leap,
-- and spreads his arms in the air; throws himself aside, guns back,
-- leaving a smear of himself, to dodge. Under half his health
-- the green fire catches on his shoulders.
--
--   Look.draw(m, clock)       m: baron.lua's `shown` (dx, dy, facing, move, moveAt, stride, phase2, hp, max,
--                             lift: 0 on the floor, 1 at the top of a leap)
--   Look.drawBody(b, clock)   where he fell: b { x, y, angle }
--   Look.drawKey(x, y, clock) the key, lying there

local Look = {}

local C = {
  hide = { 0.86, 0.58, 0.48 },
  hideDark = { 0.62, 0.38, 0.32 },
  hideHi = { 0.98, 0.74, 0.64 },
  fur = { 0.40, 0.25, 0.14 },
  furDark = { 0.26, 0.15, 0.08 },
  hoof = { 0.12, 0.10, 0.09 },
  horn = { 0.90, 0.84, 0.70 },
  hornDark = { 0.62, 0.55, 0.42 },
  claw = { 0.92, 0.88, 0.78 },
  gun = { 0.32, 0.32, 0.35 },
  gunDark = { 0.17, 0.17, 0.19 },
  gunHi = { 0.55, 0.55, 0.60 },
  eye = { 0.55, 1.00, 0.35 },
  belt = { 0.25, 0.16, 0.10 },
  brass = { 0.95, 0.75, 0.25 },
  brassDark = { 0.62, 0.45, 0.12 },
  fire = { 0.35, 1.00, 0.35 },
  fireCore = { 0.85, 1.00, 0.75 },
  blood = { 0.30, 0.03, 0.03 },
  shadow = { 0, 0, 0, 0.35 },
  ink = { 0.14, 0.05, 0.04 }, -- his outline
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- Green fire at (x, y), `size` across, flickering.
local function fire(x, y, size, clock, seed)
  love.graphics.setBlendMode("add")
  for k = 0, 4 do
    local f = 0.7 + 0.3 * math.sin(clock * (18 + k * 3) + seed + k)
    local up = (clock * 2 + k * 0.23 + seed) % 1
    love.graphics.setColor(C.fire[1], C.fire[2], C.fire[3], 0.35 * (1 - up))
    local fx = x + math.sin(k * 2.1 + clock * 5) * size * 0.2
    love.graphics.circle("fill", fx, y - up * size * 0.5, size * 0.5 * f, 10)
  end
  love.graphics.setColor(C.fireCore[1], C.fireCore[2], C.fireCore[3], 0.8)
  love.graphics.circle("fill", x, y, size * 0.25, 10)
  love.graphics.setBlendMode("alpha")
end

--- The key: a big brass key, a tag with Zz on it.
local function key(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle or 0)
  color(C.brassDark)
  love.graphics.circle("fill", -8, 0, 7, 12)
  color(C.brass)
  love.graphics.circle("fill", -8, 0, 5, 12)
  color(C.brassDark)
  love.graphics.circle("fill", -8, 0, 2, 8)
  color(C.brass)
  love.graphics.rectangle("fill", -2, -2, 18, 4)
  love.graphics.rectangle("fill", 10, 2, 3, 5)
  love.graphics.rectangle("fill", 14, 2, 2, 4)
  color(C.horn) -- the tag
  love.graphics.rectangle("fill", -22, 4, 10, 8, 2)
  love.graphics.setColor(0.2, 0.2, 0.3)
  love.graphics.print("z", -21, 1, 0, 0.6, 0.6)
  love.graphics.pop()
end

--- A limb from (ax, ay) to (bx, by), `w` thick, outlined, round at both ends.
local function limb(ax, ay, bx, by, w, c)
  color(C.ink)
  love.graphics.setLineWidth(w + 3)
  love.graphics.line(ax, ay, bx, by)
  love.graphics.circle("fill", ax, ay, (w + 3) / 2, 10)
  love.graphics.circle("fill", bx, by, (w + 3) / 2, 10)
  color(c)
  love.graphics.setLineWidth(w)
  love.graphics.line(ax, ay, bx, by)
  love.graphics.circle("fill", ax, ay, w / 2, 10)
  love.graphics.circle("fill", bx, by, w / 2, 10)
  love.graphics.setLineWidth(1)
end

--- A strip along `pts` ({ x, y, ... }) tapering from `w0` thick to `w1`:
--- a horn, a tail.
local function strip(pts, w0, w1, c)
  color(c)
  local n = #pts / 2
  local left, right = {}, {}
  for i = 1, n do
    local x, y = pts[i * 2 - 1], pts[i * 2]
    local j0, j1 = math.max(1, i - 1), math.min(n, i + 1)
    local dx, dy = pts[j1 * 2 - 1] - pts[j0 * 2 - 1], pts[j1 * 2] - pts[j0 * 2]
    local len = math.sqrt(dx * dx + dy * dy)
    local w = (w0 + (w1 - w0) * (i - 1) / (n - 1)) / 2
    left[i] = { x - dy / len * w, y + dx / len * w }
    right[i] = { x + dy / len * w, y - dx / len * w }
  end
  for i = 1, n - 1 do
    love.graphics.polygon("fill", left[i][1], left[i][2], left[i + 1][1], left[i + 1][2], right[i + 1][1],
      right[i + 1][2], right[i][1], right[i][2])
  end
end

--- A horn on `side`, from the top of the head at (hx, 0): out sideways,
--- round and forward to a point. Outlined, ridged.
local function horn(hx, side)
  local pts = { hx - 3, side * 6, hx - 7, side * 15, hx - 3, side * 24, hx + 6, side * 28, hx + 15, side * 26,
    hx + 22, side * 20 }
  strip(pts, 10, 3, C.ink)
  strip(pts, 7, 1.2, C.horn)
  color(C.hornDark) -- the ridges
  love.graphics.setLineWidth(1.2)
  for i = 2, 4 do
    local x, y = pts[i * 2 - 1], pts[i * 2]
    love.graphics.line(x - 2, y - side * 1.5, x + 2, y + side * 1.5)
  end
  love.graphics.setLineWidth(1)
end

Look.GUN = 24 -- px from his wrist to the muzzle, in his own frame (before he's scaled up)

--- A gun where a hand should be, at the wrist (x, y), pointing along `a`:
--- a cuff where the flesh grows into it, a boxy body with a green cell
--- glowing in it, twin barrels, a muzzle brake. `hot`: about to fire.
local function gun(x, y, a, clock, hot)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  color(C.ink)
  love.graphics.rectangle("fill", -4.5, -7, 18, 14, 2) -- the body
  love.graphics.rectangle("fill", 12, -5, Look.GUN - 10, 10) -- the barrels
  color(C.gun)
  love.graphics.rectangle("fill", -3, -5.5, 15, 11, 1.5)
  color(C.gunHi)
  love.graphics.rectangle("fill", -1, -5.5, 11, 2.5)
  color(C.gunDark)
  for k = -1, 1, 2 do
    love.graphics.rectangle("fill", 13, k * 2.2 - 1.4, Look.GUN - 12, 2.8)
  end
  love.graphics.rectangle("fill", Look.GUN - 3, -4.5, 3, 9) -- the brake
  color(C.hideDark) -- the cuff, flesh grown over the steel
  love.graphics.rectangle("fill", -5, -6, 4, 12, 1.5)
  color(C.ink)
  love.graphics.setLineWidth(1)
  for k = -1, 1, 2 do
    love.graphics.circle("fill", -3, k * 3.5, 0.9, 6) -- the bolts
  end
  local glow = hot and 1 or 0.55 + 0.25 * math.sin(clock * 4)
  love.graphics.setColor(C.fire[1], C.fire[2], C.fire[3], glow) -- the cell
  love.graphics.circle("fill", 5, 0, 2.6, 10)
  love.graphics.pop()
end

-- Where his elbows and wrists go, by pose: { ex, ey, hx, hy } for the right
-- arm (+y), the left mirrored. `swing` swings them as he walks.
local ARMS = {
  walk = function(swing)
    return -2 - swing * 3, 38, 12 - swing * 6, 36
  end,
  fire = function()
    return 6, 40, 18, 30
  end,
  roar = function()
    return 2, 46, 6, 58
  end,
  charge = function()
    return -6, 36, -16, 28
  end,
  crouch = function()
    return 12, 36, 24, 30
  end,
  air = function()
    return 6, 44, 16, 52
  end,
  dead = function()
    return 8, 42, 20, 50
  end,
}
ARMS.throw, ARMS.land, ARMS.stunned, ARMS.claw, ARMS.dodge = ARMS.fire, ARMS.crouch, ARMS.walk, ARMS.walk,
  ARMS.charge

--- Him in his own frame: +x ahead, +y his right. `pose` says what he's doing.
local function body(pose, stride, clock, phase2)
  local step = math.sin(stride * 0.09)
  local crouched = pose == "crouch" or pose == "land"
  -- His tail, flicking behind him, a tuft at the end.
  local wag = math.sin(clock * 3 + stride * 0.05) * 6
  local tail = { -16, 0, -26, wag * 0.5, -34, wag, -40, wag * 0.4 }
  strip(tail, 6, 3, C.ink)
  strip(tail, 4, 1.5, C.furDark)
  color(C.furDark)
  love.graphics.circle("fill", -41, wag * 0.4, 3.5, 8)
  -- Goat legs below: shaggy haunches, cloven hooves stepping out from
  -- under him (both out front, crouched).
  for _, side in ipairs({ -1, 1 }) do
    local reach = (pose == "charge" and 1.6 or 1) * step * side * 9
    if crouched then
      reach = 8
    elseif pose == "air" then
      reach = -8
    end
    color(C.ink)
    love.graphics.ellipse("fill", -8 + reach * 0.4, side * 12, 14, 11, 14)
    color(C.fur)
    love.graphics.ellipse("fill", -8 + reach * 0.4, side * 12, 12.5, 9.5, 14)
    color(C.furDark) -- the shag
    for k = 0, 4 do
      local a = side * (0.6 + k * 0.5)
      love.graphics.circle("fill", -8 + reach * 0.4 + math.cos(a) * 11, side * 12 + math.sin(a) * 8, 2.5, 6)
    end
    color(C.ink)
    love.graphics.ellipse("fill", 4 + reach, side * 15, 6.5, 5.5, 8)
    color(C.hoof)
    love.graphics.ellipse("fill", 4 + reach, side * 15 - 2.2, 5, 2.2, 8) -- cloven
    love.graphics.ellipse("fill", 4 + reach, side * 15 + 2.2, 5, 2.2, 8)
  end
  -- The torso, wedge-shaped: broad shoulders tapering to the waist,
  -- outlined, the muscle drawn on.
  local lean = pose == "charge" and 6 or pose == "roar" and -5 or crouched and 4 or 0
  local back = {
    lean - 16, -12, lean - 6, -26, lean + 6, -31, lean + 13, -20, lean + 15, 0, lean + 13, 20, lean + 6, 31,
    lean - 6, 26, lean - 16, 12,
  }
  color(C.hide)
  love.graphics.polygon("fill", back)
  color(C.hideHi) -- the light on his traps and shoulder tops
  love.graphics.ellipse("fill", lean + 4, -10, 8, 7, 12)
  love.graphics.ellipse("fill", lean + 4, 10, 8, 7, 12)
  color(C.hideDark) -- the spine's groove, the shoulder blades, the lats
  love.graphics.setLineWidth(2)
  love.graphics.line(lean - 15, 0, lean + 8, 0)
  love.graphics.arc("line", "open", lean - 4, -12, 9, 0.6, 2.7, 8)
  love.graphics.arc("line", "open", lean - 4, 12, 9, -2.7, -0.6, 8)
  love.graphics.line(lean - 13, -14, lean - 6, -22)
  love.graphics.line(lean - 13, 14, lean - 6, 22)
  color(C.ink)
  love.graphics.polygon("line", back)
  love.graphics.setLineWidth(1)
  color(C.horn) -- bone spikes down his back
  for k = 0, 3 do
    local x = lean - 12 + k * 5
    love.graphics.polygon("fill", x - 2.5, -2.5, x - 2.5, 2.5, x + 2.5, 0)
  end
  -- The belt, the key on it.
  color(C.ink)
  love.graphics.rectangle("fill", lean - 16, -14, 6, 28)
  color(C.belt)
  love.graphics.rectangle("fill", lean - 15, -13, 4, 26)
  love.graphics.push()
  love.graphics.translate(lean - 13, 17)
  love.graphics.scale(0.6, 0.6)
  key(0, 0, 1.4)
  love.graphics.pop()
  -- The arms: upper arm, forearm, a gun for a hand; the shoulder on top.
  -- The guns point ahead, unless the arm is flung out, back or wide.
  local swing = step
  local ahead = pose == "walk" or pose == "fire" or pose == "throw" or pose == "stunned" or crouched
    or pose == "claw"
  for _, side in ipairs({ -1, 1 }) do
    local ex, ey, hx, hy = ARMS[pose](swing * side)
    local bash = pose == "claw" and side == 1
    if bash then -- the arm back, to club with the gun
      ex, ey, hx, hy = -6, 40, -16, 30
    end
    ex, ey, hx, hy = lean + ex, ey * side, lean + hx, hy * side
    limb(lean + 4, side * 27, ex, ey, 10, C.hideDark)
    limb(ex, ey, hx, hy, 8, C.hide)
    local a = math.atan2(hy - ey, hx - ex)
    if ahead and not bash then
      a = -side * ((pose == "fire" or pose == "throw") and 0.06 or 0.15) -- a touch in, at whoever's ahead
    end
    gun(hx, hy, a, clock, pose == "fire" or pose == "throw")
    color(C.ink) -- the shoulder, a knot of muscle
    love.graphics.circle("fill", lean + 4, side * 27, 11.5, 14)
    color(C.hide)
    love.graphics.circle("fill", lean + 4, side * 27, 10, 14)
    color(C.hideHi)
    love.graphics.circle("fill", lean + 6, side * 25, 4.5, 10)
    if pose == "fire" or pose == "throw" then -- green fire at the muzzle
      fire(hx + math.cos(a) * Look.GUN, hy + math.sin(a) * Look.GUN, pose == "fire" and 22 or 16, clock, side)
    end
  end
  -- The head, low and heavy between the shoulders: a long goat's skull, a
  -- brow over glowing eyes, ears out, the horns sweeping round it.
  local hx = lean + (pose == "charge" and 24 or pose == "roar" and 14 or crouched and 22 or 19)
  for _, side in ipairs({ -1, 1 }) do -- the ears
    color(C.ink)
    love.graphics.polygon("fill", hx - 4, side * 5, hx - 6, side * 15, hx + 1, side * 8)
    color(C.hideDark)
    love.graphics.polygon("fill", hx - 4, side * 6, hx - 5.5, side * 13, hx, side * 8)
  end
  color(C.ink)
  love.graphics.ellipse("fill", hx, 0, 11, 9.5, 16)
  love.graphics.ellipse("fill", hx + 9, 0, 7, 6, 12)
  color(C.hide)
  love.graphics.ellipse("fill", hx, 0, 9.5, 8, 16)
  color(C.hideDark) -- the muzzle, the nostrils
  love.graphics.ellipse("fill", hx + 9, 0, 5.5, 4.5, 12)
  love.graphics.setColor(0.15, 0.05, 0.05)
  love.graphics.circle("fill", hx + 13, -1.6, 1, 6)
  love.graphics.circle("fill", hx + 13, 1.6, 1, 6)
  for _, side in ipairs({ -1, 1 }) do
    horn(hx, side)
  end
  color(C.ink) -- the brow
  love.graphics.setLineWidth(2)
  love.graphics.line(hx + 2, -7, hx + 5, -2, hx + 5, 2, hx + 2, 7)
  love.graphics.setLineWidth(1)
  if pose == "stunned" then -- eyes rolling
    color(C.eye)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.circle("line", hx + 3, side * 4.5, 2.2, 8)
    end
    love.graphics.setColor(1, 1, 0.6, 0.8)
    for k = 0, 2 do
      local a = clock * 5 + k * 2.1
      love.graphics.circle("fill", hx + math.cos(a) * 18, math.sin(a) * 18, 2.5, 6)
    end
  elseif pose ~= "dead" then
    love.graphics.setBlendMode("add")
    love.graphics.setColor(C.eye[1], C.eye[2], C.eye[3], 0.35)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.circle("fill", hx + 3, side * 4.5, 4, 8)
    end
    love.graphics.setBlendMode("alpha")
    color(C.eye)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.ellipse("fill", hx + 3, side * 4.5, 1.6, 2.2, 8)
    end
  end
  if pose == "roar" then -- the jaw dropped, wide
    love.graphics.setColor(0.25, 0.04, 0.04)
    love.graphics.ellipse("fill", hx + 13, 0, 4, 5.5, 10)
    color(C.claw)
    love.graphics.polygon("fill", hx + 11, -4, hx + 15, -3, hx + 13, -1)
    love.graphics.polygon("fill", hx + 11, 4, hx + 15, 3, hx + 13, 1)
  end
  if phase2 then -- the green fire caught on his shoulders
    fire(lean + 2, -26, 18, clock, 3)
    fire(lean + 2, 26, 18, clock, 7)
  end
end

local POSE = {
  [1] = "fire", [2] = "throw", [3] = "charge", [4] = "charge", [5] = "stunned", [6] = "claw", [7] = "roar",
  [8] = "crouch", [9] = "air", [10] = "land", [11] = "dodge",
}

--- The smear he leaves throwing himself aside: faint copies of his
--- shoulders and horns back along the way he came (`aim`).
local function smear(m, s)
  local bx, by = -math.cos(m.aim or 0), -math.sin(m.aim or 0)
  for k = 3, 1, -1 do
    love.graphics.push()
    love.graphics.translate(m.dx + bx * k * 16, m.dy + by * k * 16)
    love.graphics.rotate(m.facing)
    love.graphics.scale(s, s)
    local a = 0.4 - k * 0.1
    love.graphics.setColor(C.hide[1], C.hide[2], C.hide[3], a)
    love.graphics.ellipse("fill", 0, 0, 16, 31, 18)
    love.graphics.setColor(C.horn[1], C.horn[2], C.horn[3], a)
    love.graphics.ellipse("fill", 16, 0, 6, 26, 12)
    love.graphics.pop()
  end
end

function Look.draw(m, clock)
  local pose = POSE[m.move] or "walk"
  local lift = m.lift or 0
  local s = 1.35 -- a head and more over a person
  if pose == "dodge" then
    smear(m, s)
  end
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  color(C.shadow, 0.35 * (1 - lift * 0.5)) -- on the floor, under him even in the air
  love.graphics.ellipse("fill", 4, 6, 34 * s * (1 - lift * 0.3), 30 * s * (1 - lift * 0.3), 24)
  love.graphics.translate(0, -lift * 26) -- up off the floor...
  local wobble = pose == "stunned" and math.sin(clock * 9) * 0.25 or 0
  love.graphics.rotate(m.facing + wobble)
  s = s * (1 + lift * 0.3) -- ...and nearer the camera
  love.graphics.scale(s, s)
  body(pose, m.stride or 0, clock, m.phase2)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where he fell: face down, sprawled, horns in the floor, blood round him.
function Look.drawBody(b, clock)
  love.graphics.push()
  love.graphics.translate(b.x, b.y)
  love.graphics.rotate(b.angle + 0.4)
  love.graphics.scale(1.35, 1.35)
  color(C.blood, 0.75)
  love.graphics.ellipse("fill", 8, 4, 42, 34, 24)
  body("dead", 0, clock, false)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- The key lying where he fell, glinting, bobbing a little to catch the eye.
function Look.drawKey(x, y, clock)
  local bob = math.sin(clock * 3) * 2
  love.graphics.setBlendMode("add")
  love.graphics.setColor(C.brass[1], C.brass[2], C.brass[3], 0.25 + 0.15 * math.sin(clock * 4))
  love.graphics.circle("fill", x, y + bob, 26, 20)
  love.graphics.setBlendMode("alpha")
  love.graphics.push()
  love.graphics.translate(x, y + bob)
  love.graphics.scale(1.6, 1.6)
  key(0, 0, -0.4)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
