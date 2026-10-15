-- How the Baron of Heck looks (baron.lua), seen from above at world size:
-- a big horned brute, pink-hided above the waist and shaggy brown goat legs
-- below, hooves stepping out under him as he walks. Broad shoulders knotted
-- with muscle, long arms with claws, a heavy head with two great horns
-- curving forward. The Snooze Gate's key hangs off his belt, brass, a tag
-- with Zz on it. Green fire burns up in his hands before he throws; he
-- drops his head, horns first, to charge; reels, eyes rolling, when he's
-- run into a wall; throws his head back to roar. Under half his health
-- the green fire catches on his shoulders.
--
--   Look.draw(m, clock)       m: baron.lua's `shown` (dx, dy, facing, move, moveAt, stride, phase2, hp, max)
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
  eye = { 0.55, 1.00, 0.35 },
  belt = { 0.25, 0.16, 0.10 },
  brass = { 0.95, 0.75, 0.25 },
  brassDark = { 0.62, 0.45, 0.12 },
  fire = { 0.35, 1.00, 0.35 },
  fireCore = { 0.85, 1.00, 0.75 },
  blood = { 0.30, 0.03, 0.03 },
  shadow = { 0, 0, 0, 0.35 },
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

--- Him in his own frame: +x ahead, +y his right. `pose` says what he's doing.
local function body(pose, stride, clock, phase2)
  local step = math.sin(stride * 0.09)
  -- Goat legs below: shaggy haunches and hooves stepping out from under him.
  for _, side in ipairs({ -1, 1 }) do
    local reach = (pose == "charge" and 1.6 or 1) * step * side * 9
    color(C.furDark)
    love.graphics.ellipse("fill", -6 + reach * 0.4, side * 13, 15, 10, 14)
    color(C.fur)
    love.graphics.ellipse("fill", -6 + reach * 0.4, side * 12, 13, 8, 14)
    color(C.hoof)
    love.graphics.ellipse("fill", 4 + reach, side * 14, 6, 5, 8)
  end
  -- The torso: broad, pink, knotted with muscle.
  local lean = pose == "charge" and 6 or pose == "roar" and -5 or 0
  color(C.hideDark)
  love.graphics.ellipse("fill", lean + 1, 1, 22, 30, 24)
  color(C.hide)
  love.graphics.ellipse("fill", lean, 0, 20, 28, 24)
  color(C.hideHi)
  love.graphics.ellipse("fill", lean - 4, -9, 10, 9, 14)
  color(C.hideDark) -- the spine, the shoulder blades
  love.graphics.setLineWidth(2)
  love.graphics.line(lean - 18, 0, lean + 6, 0)
  love.graphics.arc("line", "open", lean - 6, -12, 9, 0.5, 2.6, 8)
  love.graphics.arc("line", "open", lean - 6, 12, 9, -2.6, -0.5, 8)
  love.graphics.setLineWidth(1)
  color(C.belt) -- the belt, the key on it
  love.graphics.rectangle("fill", lean - 4, -26, 5, 52)
  key(lean - 1, 24, 1.2)
  -- The arms: up with fire, back for a claw, wide for a roar, out ahead
  -- otherwise; the claws at the ends.
  for _, side in ipairs({ -1, 1 }) do
    local hx, hy
    if pose == "fire" or pose == "throw" then
      hx, hy = lean + 18, side * 26
    elseif pose == "claw" and side == 1 then
      hx, hy = lean - 8, 36
    elseif pose == "roar" then
      hx, hy = lean + 4, side * 42
    elseif pose == "charge" then
      hx, hy = lean - 6, side * 30
    else
      hx, hy = lean + 14 + side * step * 4, side * 32
    end
    color(C.hideDark)
    love.graphics.setLineWidth(10)
    love.graphics.line(lean, side * 24, hx, hy)
    love.graphics.setLineWidth(1)
    color(C.hide)
    love.graphics.circle("fill", lean, side * 25, 9, 12) -- the shoulder
    love.graphics.circle("fill", hx, hy, 6, 10) -- the hand
    color(C.claw)
    for k = -1, 1 do
      love.graphics.circle("fill", hx + 5, hy + k * 3.5, 1.6, 6)
    end
    if pose == "fire" or pose == "throw" then
      fire(hx + 4, hy, pose == "fire" and 26 or 16, clock, side)
    end
  end
  -- The head, low and heavy, the horns curving forward round it.
  local hx = lean + (pose == "charge" and 26 or pose == "roar" and 14 or 20)
  color(C.hideDark)
  love.graphics.ellipse("fill", hx, 0, 12, 11, 16)
  color(C.hide)
  love.graphics.ellipse("fill", hx + 1, -1, 10, 9, 16)
  for _, side in ipairs({ -1, 1 }) do
    color(C.hornDark)
    love.graphics.setLineWidth(7)
    love.graphics.line(hx - 4, side * 7, hx - 6, side * 18, hx + 6, side * 24, hx + 18, side * 18)
    love.graphics.setLineWidth(4)
    color(C.horn)
    love.graphics.line(hx - 4, side * 7, hx - 6, side * 18, hx + 6, side * 24, hx + 18, side * 18)
    love.graphics.setLineWidth(1)
    love.graphics.circle("fill", hx + 19, side * 17, 2.5, 6)
  end
  if pose == "stunned" then -- eyes rolling
    color(C.eye)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.circle("line", hx + 7, side * 4, 2.2, 8)
    end
    love.graphics.setColor(1, 1, 0.6, 0.8)
    for k = 0, 2 do
      local a = clock * 5 + k * 2.1
      love.graphics.circle("fill", hx + math.cos(a) * 18, math.sin(a) * 18, 2.5, 6)
    end
  else
    color(C.eye)
    for _, side in ipairs({ -1, 1 }) do
      love.graphics.ellipse("fill", hx + 7, side * 4, 2.2, 1.5, 8)
    end
  end
  if pose == "roar" then -- the mouth wide
    love.graphics.setColor(0.25, 0.04, 0.04)
    love.graphics.ellipse("fill", hx + 10, 0, 4, 6, 10)
  end
  if phase2 then -- the green fire caught on his shoulders
    fire(lean - 4, -22, 18, clock, 3)
    fire(lean - 4, 22, 18, clock, 7)
  end
end

local POSE = {
  [1] = "fire", [2] = "throw", [3] = "charge", [4] = "charge", [5] = "stunned", [6] = "claw", [7] = "roar",
}

function Look.draw(m, clock)
  local pose = POSE[m.move] or "walk"
  love.graphics.push()
  love.graphics.translate(m.dx, m.dy)
  local wobble = pose == "stunned" and math.sin(clock * 9) * 0.25 or 0
  love.graphics.rotate(m.facing + wobble)
  local s = 1.35 -- a head and more over a person
  love.graphics.scale(s, s)
  color(C.shadow)
  love.graphics.ellipse("fill", 4, 6, 30, 36, 24)
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
