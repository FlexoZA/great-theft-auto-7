-- How the Floor Manager looks (floor_manager.lua's walker), on every screen:
-- Fobos Base's Arachnotron, drawn at world size, seen from above.
--
-- No legs: he floats about the Hangar in his executive chair, a rocket
-- strapped under it. Oxblood leather, the seat piped round its edge, a tall
-- tufted backrest curved round behind him, padded armrests on chrome posts,
-- his clipboard taped to the left one. Two rocket engines poke out under
-- the backrest, their flames licking out behind him, longer when he goes
-- somewhere; he bobs on them, his shadow off to one side on the floor
-- below. For a stomp the rockets roar and he rises (bigger, the shadow
-- further off), then drops on you.
--
-- In the chair an armoured octagon, hazard stripes round its rim, rivets,
-- status lights blinking, two exhaust stacks puffing; on that the glass
-- dome and the manager's brain in it, folded and pulsing, an eye on a
-- stalk; the plasma cannon under the front, twin barrels in coils that glow
-- green (brighter as it charges, a ball of plasma swelling at the muzzle, a
-- flash as it streams). Hurt, it shows: the dome cracks under half his
-- health, and under a quarter he sparks and smokes. Shot off, the cannon
-- leaves a stump and dangling cables.
--
--   local look = Look.new()
--   Look.update(look, m, dt)      -- m: floor_manager.lua's shown walker
--   Look.draw(look, m, clock)
--   Look.drawWreck(wreck, clock)  -- { x, y, angle } where he went down

local Look = {}

Look.SCALE = 1.3 -- the hull, dome and cannon are drawn this much bigger than their plan below
Look.MUZZLE = 52 -- the cannon's end, in the plan: 52 * SCALE px out in the world (floor_manager.lua's MUZZLE)

local NOZZLE_X, NOZZLE_Y = -58, 15 -- the rockets' nozzles, in the plan: out behind the backrest, either side
local HOVER = 7 -- px he floats over the floor...
local BOB, BOB_RATE = 2, 2.4 -- ...rising and falling this much, this often (radians a second)
local RISE = 16 -- px more at the top of a stomp's rearing

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
  leather = { 0.38, 0.11, 0.10 }, -- oxblood: an executive's chair
  leatherHi = { 0.58, 0.22, 0.19 },
  chrome = { 0.78, 0.80, 0.84 },
  flame = { 1.00, 0.55, 0.12 },
  flameHot = { 1.00, 0.92, 0.55 },
}

local random = love.math.random

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- Where a nozzle is in the world, for a chair at (x, y) facing `a` (`side` -1 or 1).
local function nozzle(x, y, a, side)
  local px, py = NOZZLE_X * Look.SCALE, NOZZLE_Y * Look.SCALE * side
  return x + math.cos(a) * px - math.sin(a) * py, y + math.sin(a) * px + math.cos(a) * py
end

function Look.new()
  return { puffs = {}, sparks = {}, lastX = nil, lastY = nil, speed = 0 }
end

--- The rockets' throttle and the smoke for walker `m` (dx, dy, facing, move).
function Look.update(look, m, dt)
  local x, y, a = m.dx, m.dy, m.facing
  if look.lastX then
    local v = math.sqrt((x - look.lastX) ^ 2 + (y - look.lastY) ^ 2) / math.max(dt, 1e-3)
    look.speed = look.speed + (math.min(v, 300) - look.speed) * math.min(1, dt * 6) -- eased, so the flames don't jump
  end
  look.lastX, look.lastY = x, y
  -- Smoke from the stacks, more when he strains (a charge, a stomp) or is hurt.
  local hurt = m.max and m.max > 0 and m.hp / m.max or 1
  local rate = (m.move ~= 0 and 9 or 3) + (hurt < 0.25 and 6 or 0)
  if random() < dt * (rate + look.speed / 30) then -- the rockets' smoke, thicker the harder they burn
    for _, side in ipairs({ -1, 1 }) do
      local sx, sy = nozzle(x, y, a, side)
      sx, sy = sx - math.cos(a) * 14, sy - math.sin(a) * 14
      look.puffs[#look.puffs + 1] = { x = sx, y = sy, t = 0, life = 0.9 + random() * 0.6,
        vx = -math.cos(a) * 40 + (random() - 0.5) * 16, vy = -math.sin(a) * 40 + (random() - 0.5) * 16 }
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

--- A rocket's flame at its nozzle (the origin, pointing -x), `burn` 0..1
--- how hard it is going: a long orange tongue round a white-hot core,
--- licking about.
local function drawFlame(burn, clock, side)
  local len = 10 + 26 * burn + random() * 6
  local w = 4.5 + 1.5 * burn
  local lick = math.sin(clock * 31 + side) * 1.5
  color(C.flame, 0.85)
  love.graphics.polygon("fill", 0, -w, -len * 0.55, -w * 0.9 + lick, -len, lick * 2, -len * 0.55, w * 0.9 + lick, 0,
    w)
  color(C.flameHot)
  love.graphics.polygon("fill", 0, -w * 0.5, -len * 0.45, lick, 0, w * 0.5)
end

--- The rockets under the backrest: the engines' bells, each with its flame.
local function drawRockets(burn, clock, cold)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.push()
    love.graphics.translate(NOZZLE_X, NOZZLE_Y * side)
    if not cold then
      drawFlame(burn, clock, side)
    end
    color(C.steelDark)
    love.graphics.polygon("fill", 8, -4, 8, 4, 0, 6.5, 0, -6.5) -- the bell, opening backwards
    color(C.steel)
    love.graphics.rectangle("fill", 8, -4.5, 16, 9, 1.5) -- the engine, running in under the seat
    color(C.steelHi, 0.6)
    love.graphics.rectangle("fill", 9, -3.5, 14, 2, 1)
    color(C.hazard)
    love.graphics.rectangle("fill", 12, -4.5, 2, 9) -- a band of hazard paint round it
    color(cold and C.black or C.flameHot, cold and 1 or 0.9)
    love.graphics.ellipse("fill", 0.5, 0, 1.2, 5, 10) -- the throat, glowing
    love.graphics.pop()
  end
end

--- An armrest along his `side` (-1 left, 1 right): a padded bar on a
--- chrome post.
local function drawArmrest(side)
  local y = 35 * side
  color(C.chrome)
  love.graphics.rectangle("fill", -6, y - 2.5, 6, 5, 1) -- the post, peeking out under the pad
  color(C.leather)
  love.graphics.rectangle("fill", -24, y - 5, 40, 10, 5)
  color(C.leatherHi)
  love.graphics.rectangle("fill", -21, y - 3.5, 34, 3, 1.5)
  color(C.black, 0.8)
  love.graphics.rectangle("line", -24, y - 5, 40, 10, 5)
end

--- His chair round the origin (facing +x), under the hull: the seat, the
--- backrest curved round behind him, the armrests.
local function drawChair()
  -- The seat, a rounded square a little bigger than the hull, piped round.
  color(C.leather)
  love.graphics.rectangle("fill", -33, -32, 62, 64, 12)
  color(C.leatherHi, 0.7)
  love.graphics.rectangle("line", -30, -29, 56, 58, 10)
  -- The backrest: a thick band round behind him, tufted with buttons.
  local pts = {}
  for k = 0, 12 do
    local t = math.pi * 0.62 + k * math.pi * 0.76 / 12
    pts[#pts + 1], pts[#pts + 2] = math.cos(t) * 50, math.sin(t) * 50
  end
  for k = 12, 0, -1 do
    local t = math.pi * 0.62 + k * math.pi * 0.76 / 12
    pts[#pts + 1], pts[#pts + 2] = math.cos(t) * 36, math.sin(t) * 36
  end
  color(C.leather)
  love.graphics.polygon("fill", pts)
  color(C.black, 0.8)
  love.graphics.polygon("line", pts)
  color(C.leatherHi)
  for k = 1, 5 do -- the buttons
    local t = math.pi * 0.62 + k * math.pi * 0.76 / 6
    love.graphics.circle("fill", math.cos(t) * 43, math.sin(t) * 43, 1.4, 6)
  end
  drawArmrest(-1)
  drawArmrest(1)
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

--- His clipboard, taped to his left armrest.
local function drawClipboard()
  love.graphics.push()
  love.graphics.translate(-4, -36)
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

--- Draw walker `m` (dx, dy, facing, move, cannon, hp, max) in his chair.
function Look.draw(look, m, clock)
  local x, y, a = m.dx, m.dy, m.facing
  local rear = m.move == 1 and math.min(1, m.rearT or 0) or 0
  local lift = HOVER + BOB * math.sin(clock * BOB_RATE) + RISE * rear
  -- The smoke under him first, then his shadow on the floor, further off the higher he floats.
  for _, p in ipairs(look.puffs) do
    local k = p.t / p.life
    love.graphics.setColor(0.22, 0.2, 0.2, 0.45 * (1 - k))
    love.graphics.circle("fill", p.x, p.y, 5 + k * 14, 10)
  end
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", x + 4 + lift, y + 4 + lift, 46 - lift * 0.3, 42 - lift * 0.3, 24)
  local burn = math.min(1, 0.25 + look.speed / 160 + rear)
  local hurt = m.max and m.max > 0 and m.hp / m.max or 1
  love.graphics.push()
  love.graphics.translate(x, y - lift * 0.4) -- up off the floor, a little toward the top of the screen
  love.graphics.rotate(a)
  love.graphics.scale(Look.SCALE * (1 + 0.08 * rear)) -- risen: a touch bigger, nearer the eye
  drawRockets(burn, clock)
  drawChair()
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

--- His wreck where he went down: the chair on the floor, its rockets
--- cold, the hull dark, the dome smashed and empty, smoke going up.
function Look.drawWreck(wreck, clock)
  local x, y, a = wreck.x, wreck.y, wreck.angle
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x + 4, y + 4, 46, 42, 24)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  love.graphics.scale(Look.SCALE)
  drawRockets(0, clock, true)
  drawChair()
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
