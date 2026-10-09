-- What a defender can see: a narrow fan (`FOV`, thirty degrees) in front of
-- them, out to a range, and only where nothing solid stands in the way.
-- Walls are every feature's `blocksPoint` (docs/features.md), the same rule
-- bullets follow, so a hedgehog or a sandbag wall that stops a round hides
-- you too. The host decides who is seen; clients draw the same fan, clipped
-- by the same walls, so a player can see exactly where the eyes are.

local Features = require("src.features")

local Sight = {}

Sight.FOV = math.rad(30) -- full width of the cone
Sight.STEP = 12 -- px between line-of-sight samples
Sight.RAYS = 7 -- rays across the cone when drawing it

local TWO_PI = 2 * math.pi

--- Shortest signed turn from heading b to heading a.
function Sight.angleDiff(a, b)
  return (a - b + math.pi) % TWO_PI - math.pi
end

--- Is (x, y) inside anything solid?
function Sight.blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- Is the straight line from (x0, y0) to (x1, y1) free of walls?
function Sight.clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Sight.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Sight.blocked(x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Can someone at (x, y) facing `facing` see (tx, ty)? Within `range`,
--- inside the cone `fov` wide (Sight.FOV unless given) and with nothing in
--- between. Returns the squared distance when they can.
function Sight.canSee(x, y, facing, tx, ty, range, fov)
  local dx, dy = tx - x, ty - y
  local d2 = dx * dx + dy * dy
  if d2 > range * range then
    return nil
  end
  if math.abs(Sight.angleDiff(math.atan2(dy, dx), facing)) > (fov or Sight.FOV) / 2 then
    return nil
  end
  if not Sight.clear(x, y, tx, ty) then
    return nil
  end
  return d2
end

--- How far a look from (x, y) along `angle` gets before it hits a wall, at
--- most `range`. Returns the end point.
function Sight.reach(x, y, angle, range)
  local cx, cy = math.cos(angle), math.sin(angle)
  local step = Sight.STEP * 1.5 -- drawing can afford to be a little coarser
  local d = step
  while d < range do
    if Sight.blocked(x + cx * d, y + cy * d) then
      return x + cx * (d - step), y + cy * (d - step)
    end
    d = d + step
  end
  return x + cx * range, y + cy * range
end

local fan = {} -- reused: the clipped end of each ray
local reached = {} -- reused: how far each ray got

Sight.SWEEP = 1.4 -- seconds for the radar's beam to cross the cone one way
Sight.TRAIL = 0.35 -- share of the cone the beam's fading trail covers
Sight.RINGS = 3 -- range rings across the cone

--- The cone from (x, y) facing `facing`, out to `range`, clipped by walls,
--- drawn as a radar: a faint fan with range rings across it and a beam
--- sweeping from side to side, a fading trail behind it. Cold green while
--- scanning, a hot pulsing red with somebody in it. `fov` is how wide
--- (Sight.FOV unless given); a wider one gets more rays. `opts.seed`
--- (optional) sets where its beam is, so a crowd's don't sweep in step.
function Sight.draw(x, y, facing, range, alert, time, fov, opts)
  fov = fov or Sight.FOV
  time = time or 0
  local seed = opts and opts.seed or 0
  local rays = math.max(Sight.RAYS, math.ceil(fov / Sight.FOV * Sight.RAYS)) * 2
  local half = fov / 2
  for i = 0, rays - 1 do
    local a = facing - half + fov * i / (rays - 1)
    local ex, ey = Sight.reach(x, y, a, range)
    fan[i * 2 + 1], fan[i * 2 + 2] = ex, ey
    reached[i + 1] = math.sqrt((ex - x) ^ 2 + (ey - y) ^ 2)
  end
  local r, g, b, fill, edge = 0.45, 1, 0.65, 0.05, 0.22
  if alert then
    local pulse = 0.5 + 0.5 * math.sin(time * 12)
    r, g, b, fill, edge = 1, 0.25, 0.18, 0.10 + 0.06 * pulse, 0.45
  end
  love.graphics.setColor(r, g, b, fill)
  for i = 1, rays - 1 do
    -- One triangle per pair of rays: each is convex, the whole fan may not be.
    love.graphics.polygon("fill", x, y, fan[i * 2 - 1], fan[i * 2], fan[i * 2 + 1], fan[i * 2 + 2])
  end
  -- Range rings, only as far as each ray got before a wall.
  love.graphics.setLineWidth(1)
  love.graphics.setColor(r, g, b, edge * 0.9)
  for k = 1, Sight.RINGS do
    local rr = range * k / Sight.RINGS
    for i = 1, rays - 1 do
      if reached[i] >= rr - 1 and reached[i + 1] >= rr - 1 then
        local a0 = facing - half + fov * (i - 1) / (rays - 1)
        local a1 = facing - half + fov * i / (rays - 1)
        love.graphics.line(x + math.cos(a0) * rr, y + math.sin(a0) * rr, x + math.cos(a1) * rr, y + math.sin(a1) * rr)
      end
    end
  end
  -- The beam, sweeping across and back, its trail fading out behind it.
  local phase = (time / Sight.SWEEP + seed * 0.618) % 2
  local k = phase < 1 and phase or 2 - phase -- 0..1 across, then back
  local dir = phase < 1 and 1 or -1
  local beam = k * (rays - 1) -- in rays, fractional
  local trail = math.max(1, Sight.TRAIL * (rays - 1))
  for i = 1, rays - 1 do
    -- The triangle between rays i and i + 1, by how far behind the beam it is.
    local mid = i - 0.5
    local behind = (beam - mid) * dir
    if behind >= 0 and behind < trail then
      local a = (1 - behind / trail) ^ 2
      love.graphics.setColor(r, g, b, (alert and 0.30 or 0.22) * a)
      love.graphics.polygon("fill", x, y, fan[i * 2 - 1], fan[i * 2], fan[i * 2 + 1], fan[i * 2 + 2])
    end
  end
  local bi = math.max(1, math.min(rays, math.floor(beam + 0.5) + 1))
  love.graphics.setColor(r, g, b, alert and 0.85 or 0.6)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y, fan[bi * 2 - 1], fan[bi * 2])
  love.graphics.setLineWidth(1)
  -- The cone's edges.
  love.graphics.setColor(r, g, b, edge)
  love.graphics.line(x, y, fan[1], fan[2])
  love.graphics.line(x, y, fan[rays * 2 - 1], fan[rays * 2])
  love.graphics.setColor(1, 1, 1)
end

return Sight
