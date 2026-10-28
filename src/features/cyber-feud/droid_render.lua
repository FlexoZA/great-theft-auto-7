-- An assassin droid, drawn from above: Halcyon's hunter-killer, a lean
-- machine a head taller than a man. White-grey armour plates over a
-- graphite frame: a narrow chest plate, angular shoulder plates, a slim
-- head with a magenta visor band whose scanner dot sweeps side to side, a
-- spine pack with two vents on its back. A rail pistol in its right hand,
-- a mono-blade along its left forearm glowing magenta at the edge. It
-- walks on two long legs in a quick, even stride.
--
-- While it has nobody it goes half cloaked: faint and shimmering, only its
-- visor sharp. Once it has somebody it drops the cloak. It throws itself
-- aside in a dodge leaving glitching magenta afterimages, and before its
-- rail shot its pistol charges, crackling (the sightline is drawn by
-- droids.lua, out to the first wall).
--
-- The camera looks straight down, so height shows in the shadow, which
-- falls off down and right. Nothing here keeps state.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.PLATE = { 0.84, 0.85, 0.88 } -- the armour
Render.PLATE_SHADE = { 0.62, 0.64, 0.69 }
Render.FRAME = { 0.15, 0.16, 0.19 } -- the graphite under it
Render.FRAME_LIGHT = { 0.30, 0.32, 0.37 }
Render.GLOW = { 1.00, 0.24, 0.78 } -- Halcyon's magenta
Render.HOT = { 1.00, 0.80, 0.95 }

-- Size ---------------------------------------------------------------------

Render.RADIUS = 12 -- px; the body, for hitting it (a player is 9)
local HEIGHT = 6 -- px the shadow falls away from the body, down and right
local STRIDE = 9 -- px a foot moves in one step
local CLOAKED = 0.38 -- how solid it is drawn while cloaked

local alpha = 1 -- of everything drawn, for the cloak

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * alpha)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

-- Parts (in the body's frame: x forward, y to its right) -----------------------

--- Its legs: long and jointed backwards, the feet swinging past each other.
local function legs(cycle, stride)
  for _, side in ipairs({ -1, 1 }) do
    local swing = math.sin((cycle + (side > 0 and 0.5 or 0)) * 2 * math.pi) * STRIDE * stride
    local fx, fy = swing, side * 6.5
    color(Render.FRAME)
    love.graphics.setLineWidth(3)
    love.graphics.line(-3, side * 4.5, -7 + swing * 0.3, side * 7.5, fx, fy) -- thigh, the knee behind, shin
    color(Render.FRAME_LIGHT)
    love.graphics.polygon("fill", fx + 4.5, fy, fx - 1.5, fy - 2, fx - 1.5, fy + 2) -- the foot, pointed
    color(Render.GLOW, 0.8)
    love.graphics.circle("fill", -7 + swing * 0.3, side * 7.5, 1, 6) -- the knee joint's light
  end
end

--- The left arm and its blade along the forearm, the edge lit.
local function blade(clock)
  color(Render.FRAME)
  love.graphics.setLineWidth(2.6)
  love.graphics.line(0, -9, 6, -10.5, 11, -7.5)
  color(Render.PLATE_SHADE)
  love.graphics.polygon("fill", 4, -9, 23, -12.5, 9, -10.8) -- the blade
  local flick = 0.75 + 0.25 * math.sin(clock * 7)
  color(Render.GLOW, flick)
  love.graphics.setLineWidth(1.2)
  love.graphics.line(5, -10.2, 23, -12.5) -- its edge
  color(Render.FRAME_LIGHT)
  love.graphics.circle("fill", 11, -7.5, 2, 8) -- the hand
end

--- The right arm and the rail pistol, charging or firing.
local function pistol(clock, firing, charging)
  color(Render.FRAME)
  love.graphics.setLineWidth(2.6)
  love.graphics.line(0, 9, 7, 9, 12, 4.5)
  color(Render.FRAME_LIGHT)
  love.graphics.circle("fill", 12, 4.5, 2, 8)
  color(Render.FRAME)
  love.graphics.rectangle("fill", 11, 2.6, 13, 3.6, 1) -- the gun
  color(Render.PLATE)
  love.graphics.rectangle("fill", 13, 2.6, 7, 1.2) -- its top rail
  color(Render.GLOW, 0.9)
  love.graphics.rectangle("fill", 15, 4.6, 6, 1) -- the coil along it
  if charging then
    local k = 0.6 + 0.4 * math.abs(math.sin(clock * 34))
    color(Render.GLOW, 0.35 * k)
    love.graphics.circle("fill", 25, 4.4, 8 * k, 12)
    color(Render.HOT, 0.95)
    love.graphics.circle("fill", 25, 4.4, 3 * k, 8)
    color({ 1, 1, 1 }, 0.8)
    love.graphics.setLineWidth(1)
    local j = math.floor(clock * 40) % 3
    love.graphics.line(14, 4.4, 17, 2 + j, 20, 6 - j, 24, 4.4) -- arcing down the coil
  end
  if firing then
    color(Render.HOT, 0.9)
    love.graphics.circle("fill", 26, 4.4, 3.4 + math.sin(clock * 90), 8)
    color({ 1, 1, 1 })
    love.graphics.circle("fill", 26, 4.4, 1.4, 6)
  end
end

--- The torso: spine pack behind, chest plate, shoulder plates.
local function torso(hurt, clock)
  -- The spine pack and its vents, glowing as it works.
  color(Render.FRAME)
  love.graphics.rectangle("fill", -11, -3.5, 7, 7, 1.5)
  local vent = 0.5 + 0.5 * math.sin(clock * 5)
  color(Render.GLOW, 0.4 + 0.5 * vent)
  love.graphics.rectangle("fill", -10.5, -2.6, 1.6, 2)
  love.graphics.rectangle("fill", -10.5, 0.6, 1.6, 2)
  -- The frame under the plates.
  color(Render.FRAME)
  love.graphics.ellipse("fill", -1, 0, 5.5, 9.5, 16)
  -- The chest plate: a narrow hexagon, lit from the front.
  color(mix(Render.PLATE_SHADE, { 1, 1, 1 }, hurt))
  love.graphics.polygon("fill", 4.5, -3.5, 4.5, 3.5, 0, 6.5, -5, 4, -5, -4, 0, -6.5)
  color(mix(Render.PLATE, { 1, 1, 1 }, hurt))
  love.graphics.polygon("fill", 4.5, -3.5, 4.5, 3.5, 1, 5, 1, -5)
  -- Shoulder plates, angled back.
  for _, side in ipairs({ -1, 1 }) do
    color(mix(Render.PLATE, { 1, 1, 1 }, hurt))
    love.graphics.polygon("fill", 3, side * 6.5, 1, side * 11.5, -4.5, side * 11, -3.5, side * 6)
    color(Render.FRAME_LIGHT)
    love.graphics.setLineWidth(1)
    love.graphics.line(1, side * 11.5, -4.5, side * 11)
  end
  -- The seam down its middle.
  color(Render.FRAME, 0.6)
  love.graphics.line(4.5, 0, -5, 0)
end

--- The head: a slim helmet, the visor band across its front and the
--- scanner dot sweeping along it (still and wide open once it has somebody).
local function head(clock, alert, hurt)
  color(mix(Render.FRAME_LIGHT, { 1, 1, 1 }, hurt))
  love.graphics.ellipse("fill", 1.5, 0, 4.6, 3.8, 14)
  color(mix(Render.PLATE, { 1, 1, 1 }, hurt))
  love.graphics.ellipse("fill", 0.5, 0, 3.2, 3, 12) -- the crown
  color(Render.GLOW, alert and 0.95 or 0.55)
  love.graphics.setLineWidth(1.4)
  love.graphics.arc("line", "open", 1.5, 0, 4.4, -0.95, 0.95, 10)
  local dot = alert and 0 or math.sin(clock * 3.2) * 0.8
  color(Render.HOT, 1)
  love.graphics.circle("fill", 1.5 + math.cos(dot) * 4.4, math.sin(dot) * 4.4, alert and 1.6 or 1.2, 8)
end

--- The whole droid in its own frame.
local function droid(h, clock)
  local hurt = h.hurt or 0
  legs(h.cycle or 0, h.stride or 0)
  torso(hurt, clock)
  blade(clock)
  pistol(clock, h.firing, h.charging)
  head(clock, h.alert, hurt)
end

--- A droid at (x, y) facing `angle`. `h` (all optional):
---   cycle    its step phase (0..1, keeps counting while it walks)
---   stride   how big its steps are, 0 standing to 1 at a run
---   alert    true once it has somebody: the cloak drops, the visor opens
---   cloak    0..1, how far cloaked it is (1 while it has nobody)
---   firing   true while it shoots: a flash off the pistol
---   charging true while it charges its rail shot
---   hurt     0..1, how white it flashes just after a hit
---   dodge    0..1 while it throws itself aside: afterimages behind it
---   dodgeX, dodgeY  which way it is dodging (a unit vector)
function Render.draw(x, y, angle, h, clock)
  h = h or {}
  clock = clock or 0
  local cloak = h.cloak or 0
  local dodge = h.dodge or 0
  -- The afterimages: magenta copies back along the way it came, sliced.
  if dodge > 0 and h.dodgeX then
    for k = 3, 1, -1 do
      local back = k * 11 * dodge
      love.graphics.push()
      love.graphics.translate(x - h.dodgeX * back, y - h.dodgeY * back)
      love.graphics.rotate(angle)
      local slip = (math.floor(clock * 30 + k) % 3 - 1) * 2.5
      alpha = 0.22 * dodge
      love.graphics.setColor(Render.GLOW[1], Render.GLOW[2], Render.GLOW[3], alpha)
      love.graphics.polygon("fill", 4.5, -3.5, 4.5, 3.5, 1, 11.5, -5, 11, -5, -11, 1, -11.5)
      love.graphics.rectangle("fill", -6 + slip, -12, 12, 3) -- a slice slipped sideways
      love.graphics.pop()
    end
  end
  -- How solid: faint and shimmering under the cloak.
  local solid = 1 - cloak * (1 - CLOAKED)
  if cloak > 0 then
    solid = solid * (0.85 + 0.15 * math.sin(clock * 11 + x * 0.05))
  end
  -- Its shadow, a little apart, lighter under the cloak.
  love.graphics.push()
  love.graphics.translate(x + HEIGHT, y + HEIGHT)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 0.25 * solid)
  love.graphics.ellipse("fill", -1, 0, 7, 11, 14)
  love.graphics.pop()

  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  if dodge > 0 then
    love.graphics.scale(1, 1 - 0.15 * dodge) -- leaning into it
  end
  alpha = solid
  droid(h, clock)
  if cloak > 0 then
    -- The cloak's edge: a faint bright outline that crawls round it.
    alpha = cloak * 0.35
    color(Render.HOT)
    love.graphics.setLineWidth(1)
    local a0 = clock * 2 % (2 * math.pi)
    love.graphics.arc("line", "open", 0, 0, Render.RADIUS, a0, a0 + 2, 12)
    love.graphics.arc("line", "open", 0, 0, Render.RADIUS, a0 + math.pi, a0 + math.pi + 1.4, 10)
  end
  love.graphics.pop()
  alpha = 1
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
