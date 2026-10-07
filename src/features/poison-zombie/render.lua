-- The Poison Zombie, drawn from above: the Winding Road's boss, after
-- Half-Life 2's. A man swollen and hunched under the poison headcrab on his
-- head, about twice a player's size here. From above you mostly see his
-- back: bloated, lumpy, dark grey skin, the spine standing out down the
-- middle and one side torn open to the ribs. Up to three more poison
-- headcrabs ride on his back, and he throws them. Long arms hang in front of
-- him to his clawed hands; he shuffles, dragging his feet, and his whole
-- back heaves with every strangled breath.
--
-- What he can be doing, besides shuffling along:
--   throw    `throw` 0..1: the right hand reaches back over the shoulder for
--            a crab (holding it up to 0.55), then flings it forward
--   swipe    `swipe` 0..1: the right claws rake across in front of him
--   howl     arms flung out, head thrown back, the back heaving hard
--   dead     face down, arms out, the crabs left on his back gone still
--
-- The poison headcrab is drawn on its own too (Render.crab), for the ones
-- he throws: scuttling, leaping, held, dead on its back.
--
-- Stateless, like the other models: everything takes what to draw and the clock.

local Render = {}

-- Look ---------------------------------------------------------------------

Render.SKIN = { 0.34, 0.32, 0.33 } -- dark grey, a bruised tinge to it, bloated
Render.SKIN_DARK = { 0.21, 0.19, 0.20 }
Render.SKIN_LIGHT = { 0.45, 0.43, 0.43 }
Render.BOIL = { 0.52, 0.44, 0.42 }
Render.FLESH = { 0.42, 0.08, 0.08 } -- inside the torn side
Render.BONE = { 0.86, 0.80, 0.66 }
Render.RAGS = { 0.22, 0.21, 0.20 } -- what's left of his trousers
Render.CLAW = { 0.20, 0.16, 0.12 }

Render.CRAB = { 0.11, 0.10, 0.10 } -- the poison headcrab: near black
Render.CRAB_LIGHT = { 0.27, 0.25, 0.24 }
Render.BAND = { 0.78, 0.74, 0.66 } -- the pale bands on its legs
Render.CRAB_BELLY = { 0.62, 0.50, 0.42 }

-- Size ---------------------------------------------------------------------

Render.RADIUS = 22 -- px; the body, for hitting it (a player is 9)
Render.CRAB_RADIUS = 5 -- px; a poison headcrab
local SCALE = 1.75 -- the model below is drawn this size
local HEIGHT = 5 -- px his shadow falls away, down and right
local CRAB_SCALE = 1.1 -- a thrown crab, against its model below

-- Where the crabs on his back cling, in his frame (before SCALE), and which
-- way each one faces: the first one thrown is the last in this list.
local BACK = {
  { -10.5, 0, math.pi },
  { -6.5, 8.5, math.pi * 0.7 },
  { -3.5, -10, -math.pi * 0.55 },
}

local fade = 1 -- how solid what is being drawn is (a body fading away)

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], (a or 1) * fade)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local function lerp(a, b, k)
  return a + (b - a) * k
end

-- The poison headcrab ------------------------------------------------------

--- A poison headcrab in its own frame (front along +x, about 5 across):
--- four long legs, spiked and banded pale, round a black hairy dome.
--- `cycle` scuttles the legs, `curl` (0..1) draws them in (clinging,
--- flying, dead), `hurt` whitens it.
local function crab(cycle, curl, hurt)
  local dark, light = mix(Render.CRAB, { 1, 1, 1 }, hurt), mix(Render.CRAB_LIGHT, { 1, 1, 1 }, hurt)
  love.graphics.setLineJoin("bevel") -- a mitre on a folded leg shoots out a spike
  for i = 1, 4 do
    local front = i <= 2
    local side = (i % 2 == 1) and -1 or 1
    local beat = (i == 1 or i == 4) and 0 or math.pi
    local swing = math.sin(cycle * math.pi * 2 + beat) * 1.4 * (1 - curl)
    local hx, hy = front and 1.5 or -1.5, side * 2.5
    local kx = (front and 4.5 or -4.2) + swing
    local ky = side * lerp(6.5, 4, curl)
    local fx = (front and 7.5 or -6.5) + swing * 1.5
    local fy = side * lerp(5, 2.5, curl)
    fx, fy = lerp(fx, kx * 0.6, curl), lerp(fy, ky * 0.7, curl)
    color(dark)
    love.graphics.setLineWidth(1.3)
    love.graphics.line(hx, hy, kx, ky, fx, fy)
    -- A pale band at the knee, and a spike off it.
    color(Render.BAND, 0.85)
    love.graphics.circle("fill", kx, ky, 0.6, 6)
    color(dark)
    love.graphics.setLineWidth(0.6)
    love.graphics.line(kx, ky, kx + side * 0.2, ky + side * 1.3)
    love.graphics.line(fx, fy, fx + (front and 1.2 or -1.2), fy)
  end
  -- The dome, bristling at its edge.
  color(dark)
  for k = 0, 11 do
    local a = k / 12 * math.pi * 2
    love.graphics.line(math.cos(a) * 3.6, math.sin(a) * 3.2, math.cos(a) * 4.6, math.sin(a) * 4.1)
  end
  love.graphics.ellipse("fill", 0, 0, 4, 3.6, 14)
  color(light)
  love.graphics.ellipse("fill", 0.6, -0.9, 1.8, 1.3, 10) -- the shine on it
  -- The mouth's lip, just showing at the front.
  color(mix(Render.CRAB_BELLY, dark, 0.35))
  love.graphics.ellipse("fill", 3.6, 0, 1, 2, 8)
  love.graphics.setLineJoin("miter")
end

--- A dead crab, on its back: the pale belly up, legs curled over it.
local function deadCrab()
  color(Render.CRAB)
  love.graphics.setLineWidth(1.2)
  love.graphics.setLineJoin("bevel")
  for i = 1, 4 do
    local side = (i % 2 == 1) and -1 or 1
    local fx = i <= 2 and 2.5 or -2.5
    love.graphics.line(fx * 0.4, side * 2.4, fx * 1.4, side * 4.4, fx * 0.8, side * 2.2)
  end
  love.graphics.setLineJoin("miter")
  color(Render.CRAB_BELLY)
  love.graphics.ellipse("fill", 0, 0, 3.6, 3.2, 12)
  color(Render.FLESH)
  love.graphics.ellipse("fill", 1.4, 0, 1.3, 1.6, 8) -- the mouth
end

--- A poison headcrab at (x, y) facing `angle`. `c` (all optional): cycle
--- (scuttle), leap (0..1 through a jump: drawn higher and bigger, legs
--- tucked, shadow falling away), dead, hurt (0..1), alpha.
function Render.crab(x, y, angle, c)
  c = c or {}
  local leap = c.leap
  local up = leap and math.sin(leap * math.pi) or 0
  local size = CRAB_SCALE * (1 + up * 0.45)
  local drop = 1.5 + up * 14
  love.graphics.setColor(0, 0, 0, 0.3 * (1 - up * 0.5) * (c.alpha or 1))
  love.graphics.ellipse("fill", x + drop, y + drop, 5 * CRAB_SCALE, 4.5 * CRAB_SCALE, 12)
  fade = c.alpha or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.scale(size)
  if c.dead then
    deadCrab()
  else
    crab(c.cycle or 0, leap and 0.7 or 0, c.hurt or 0)
  end
  love.graphics.pop()
  fade = 1
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

-- The zombie ---------------------------------------------------------------

--- Where his right hand is, in his frame: reaching back over the shoulder
--- for a crab, then flinging it forward; or raking across.
local function rightHand(g, step)
  if g.throw then
    local t = g.throw
    if t < 0.55 then
      local k = math.sin(t / 0.55 * math.pi * 0.5)
      return lerp(7, -6, k), lerp(11, 6, k)
    end
    local k = (t - 0.55) / 0.45
    return lerp(-6, 19, k), lerp(6, 3, k)
  elseif g.swipe then
    local k = g.swipe
    return lerp(6, 14, math.sin(k * math.pi)), lerp(15, -9, k)
  elseif g.howl then
    return 2, 19
  elseif g.dead then
    return 9, 15
  end
  return 9 + step, 14.5
end

local function leftHand(g, step)
  if g.howl then
    return 2, -19
  elseif g.dead then
    return 6, -16
  elseif g.swipe then
    return 7, -12
  end
  return 9 - step, -14.5
end

--- An arm from the shoulder (sx, sy) to the hand (hx, hy): thick and
--- swollen up top, the elbow bent out away from the body, three claws.
local function arm(sx, sy, hx, hy, side, hurt)
  local dx, dy = hx - sx, hy - sy
  local d = math.max(1, math.sqrt(dx * dx + dy * dy))
  local ex, ey = sx + dx * 0.5 - dy / d * side * -3, sy + dy * 0.5 + dx / d * side * -3
  if (ey - sy) * side < 0 then
    ex, ey = sx + dx * 0.5 + dy / d * side * -3, sy + dy * 0.5 - dx / d * side * -3
  end
  color(mix(Render.SKIN_DARK, { 1, 1, 1 }, hurt))
  love.graphics.setLineWidth(4.6)
  love.graphics.line(sx, sy, ex, ey)
  love.graphics.setLineWidth(3.4)
  love.graphics.line(ex, ey, hx, hy)
  color(mix(Render.SKIN, { 1, 1, 1 }, hurt))
  love.graphics.setLineWidth(3)
  love.graphics.line(sx, sy, ex, ey)
  love.graphics.setLineWidth(2)
  love.graphics.line(ex, ey, hx, hy)
  love.graphics.circle("fill", ex, ey, 1.8, 8)
  -- The hand, big and knotted, and its claws on along the forearm.
  love.graphics.circle("fill", hx, hy, 2.6, 10)
  local ux, uy = (hx - ex), (hy - ey)
  local u = math.max(1, math.sqrt(ux * ux + uy * uy))
  ux, uy = ux / u, uy / u
  color(Render.CLAW)
  love.graphics.setLineWidth(0.9)
  for k = -1, 1 do
    local px, py = -uy * k * 1.5, ux * k * 1.5
    love.graphics.line(hx + ux * 2 + px, hy + uy * 2 + py, hx + ux * 4.2 + px * 1.3, hy + uy * 4.2 + py * 1.3)
  end
end

--- The swollen back: lumps on lumps, the spine standing out, the left side
--- torn open to the ribs, boils. `heave` swells it with each breath.
local function back(heave, hurt)
  local skin, dark, light = Render.SKIN, Render.SKIN_DARK, Render.SKIN_LIGHT
  if hurt > 0 then
    skin, dark, light = mix(skin, { 1, 1, 1 }, hurt), mix(dark, { 1, 1, 1 }, hurt), mix(light, { 1, 1, 1 }, hurt)
  end
  local s = 1 + heave
  color(dark)
  love.graphics.ellipse("fill", -2, 0, 10.5 * s, 14 * s, 22)
  love.graphics.circle("fill", -4, 9, 6.2 * s, 14)
  love.graphics.circle("fill", -3, -9.5, 5.6 * s, 14)
  color(skin)
  love.graphics.ellipse("fill", -2, 0, 9.6 * s, 13.2 * s, 22)
  love.graphics.circle("fill", -4, 9, 5.5 * s, 14) -- the bigger swelling on the right
  love.graphics.circle("fill", -3, -9.5, 4.9 * s, 14)
  love.graphics.circle("fill", 2, 7.5, 4.5, 12) -- the shoulders, hunched up
  love.graphics.circle("fill", 2, -7.5, 4.2, 12)
  color(light)
  love.graphics.ellipse("fill", 0, 3.5, 3.5, 5, 12) -- lit from the front
  love.graphics.ellipse("fill", 1.5, 7, 2.2, 2.2, 8)
  -- The torn side: raw flesh and the ribs across it.
  color(Render.FLESH)
  love.graphics.ellipse("fill", -4, -6, 5, 3.4, 14)
  color(Render.BONE)
  love.graphics.setLineWidth(0.9)
  for k = 0, 3 do
    local x = -7.5 + k * 2.2
    love.graphics.line(x, -2.8, x - 0.6, -6, x + 0.2, -9.2)
  end
  color(dark)
  love.graphics.setLineWidth(1)
  love.graphics.ellipse("line", -4, -6, 5, 3.4, 14)
  -- The spine, knob by knob down the middle of the hunch.
  for k = 0, 6 do
    local x = 4 - k * 2.3
    color(Render.BONE, 0.85)
    love.graphics.ellipse("fill", x, 0, 0.9, 1.5, 8)
    color(dark, 0.6)
    love.graphics.line(x - 1.1, -0.6, x - 1.1, 0.6)
  end
  -- Boils.
  color(Render.BOIL)
  love.graphics.circle("fill", -6.5, 5, 1.3, 8)
  love.graphics.circle("fill", -1.5, 10.5, 1.1, 8)
  love.graphics.circle("fill", -9.5, -2, 0.9, 6)
  love.graphics.circle("fill", 0.5, -10, 1, 6)
  color(light, 0.9)
  love.graphics.circle("fill", -6.9, 4.6, 0.45, 5)
  love.graphics.circle("fill", -1.8, 10.1, 0.4, 5)
end

--- His own head, sunk between the shoulders, under the crab that rides it.
local function head(lift, hurt, cycle, clock)
  local x = 10 - lift * 2.5
  color(mix(Render.SKIN_DARK, { 1, 1, 1 }, hurt))
  love.graphics.ellipse("fill", 6, 0, 4, 3.6, 12) -- the neck, thick and bowed
  love.graphics.circle("fill", x, 0, 4.4, 14) -- the skull
  love.graphics.ellipse("fill", x + 3.6, 0, 2.4, 2.8, 10) -- the jaw, hanging out under the crab
  color(Render.FLESH)
  love.graphics.ellipse("fill", x + 4.6, 0, 1, 1.7 + lift, 8)
  love.graphics.push()
  love.graphics.translate(x - 0.5, 0)
  love.graphics.scale(0.95)
  -- The crab's legs wrap round his skull and twitch; it never lets go.
  crab((cycle or 0) * 0.3 + clock * 0.4, 0.8, hurt)
  love.graphics.pop()
end

--- The Poison Zombie at (x, y) facing `angle`. `g` (all optional): cycle
--- (0..1 through two steps), stride (0..1), crabs (0..3 on his back, 3 if
--- unset), throw (0..1), swipe (0..1), howl (true), hurt (0..1), dead,
--- alpha.
function Render.draw(x, y, angle, g, clock)
  g = g or {}
  clock = clock or 0
  local hurt = g.hurt or 0
  local crabs = g.crabs or #BACK
  local stride = g.stride or 0
  local cycle = g.cycle or 0
  local step = math.sin(cycle * math.pi * 2) * 3 * stride
  -- Strangled breathing: a slow heave, hard and fast when he howls.
  local heave = g.dead and 0 or (g.howl and 0.07 * math.abs(math.sin(clock * 9)) or 0.03 * math.sin(clock * 2.4))
  -- The shuffle rolls him side to side.
  local roll = g.dead and 0 or math.sin(cycle * math.pi * 2) * 0.06 * stride
  local alpha = g.alpha or 1

  love.graphics.push()
  love.graphics.translate(x + HEIGHT, y + HEIGHT)
  love.graphics.rotate(angle + roll)
  love.graphics.scale(SCALE)
  love.graphics.setColor(0, 0, 0, 0.28 * alpha)
  love.graphics.ellipse("fill", g.dead and -4 or -1, 0, g.dead and 13 or 11, 15, 20)
  love.graphics.pop()

  fade = alpha
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle + roll)
  love.graphics.scale(SCALE)
  if g.dead then
    love.graphics.translate(-6, 0) -- fallen forward: what showed of his legs is behind him now
  end

  -- Feet, bare and dragging, one ahead as the other trails; the rags of his
  -- trousers between them.
  if not g.dead then
    color(mix(Render.SKIN_DARK, { 1, 1, 1 }, hurt))
    love.graphics.ellipse("fill", 1 + step, -5.5, 4, 2.4, 10)
    love.graphics.ellipse("fill", 1 - step, 5.5, 4, 2.4, 10)
    color(Render.CLAW)
    love.graphics.setLineWidth(0.8)
    love.graphics.line(4.5 + step, -6.5, 4.5 + step, -4.5)
    love.graphics.line(4.5 - step, 4.5, 4.5 - step, 6.5)
  end
  color(Render.RAGS)
  love.graphics.ellipse("fill", -5, 0, 6, 9, 14)
  color(Render.RAGS, 0.8)
  love.graphics.polygon("fill", -9, -4, -12, -2, -10, 0)
  love.graphics.polygon("fill", -9, 3, -12.5, 5, -10, 6)

  local lx, ly = leftHand(g, step)
  local rx, ry = rightHand(g, step)
  local reaching = g.throw and g.throw < 0.55
  -- Arms hanging in front go under the hunch; the reach over his shoulder
  -- goes over it.
  arm(2, -10, lx, ly, -1, hurt)
  if not reaching then
    arm(2, 10, rx, ry, 1, hurt)
  end

  back(heave, hurt)

  -- The crabs riding on his back.
  for i = 1, math.min(crabs, #BACK) do
    local b = BACK[i]
    love.graphics.push()
    love.graphics.translate(b[1], b[2])
    love.graphics.rotate(b[3])
    love.graphics.scale(0.7)
    if g.dead then
      crab(0, 0.8, 0)
    else
      crab(clock * 0.25 + i * 0.3, 0.75, hurt) -- clinging, twitching now and then
    end
    love.graphics.pop()
  end

  if reaching then
    arm(2, 10, rx, ry, 1, hurt)
  end
  -- A crab in his fist from the moment he grabs it until he lets go.
  if g.throw and g.throw > 0.3 and g.throw < 0.85 then
    love.graphics.push()
    love.graphics.translate(rx, ry)
    love.graphics.rotate(g.throw < 0.55 and math.pi or 0)
    love.graphics.scale(0.85)
    crab(clock * 3, 0.6, 0)
    love.graphics.pop()
  end

  if not g.dead then
    head(g.howl and 1 or 0, hurt, cycle, clock)
  else
    -- Face down: the crab on his head lies flat in front of him.
    love.graphics.push()
    love.graphics.translate(9, 0)
    crab(0, 1, 0)
    love.graphics.pop()
  end

  if g.howl then
    -- The howl itself: a ragged ring of breath out in front.
    local k = (clock * 2) % 1
    color({ 0.70, 0.78, 0.55 }, 0.45 * (1 - k))
    love.graphics.setLineWidth(1.2)
    love.graphics.arc("line", "open", 8, 0, 6 + k * 12, -0.8, 0.8, 10)
  end
  love.graphics.pop()
  fade = 1
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Render
