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

--- The cone from (x, y) facing `facing`, out to `range`, clipped by walls:
--- a faint pale fan while scanning, a hot red one with somebody in it.
function Sight.draw(x, y, facing, range, alert, time)
  local rays = Sight.RAYS
  local half = Sight.FOV / 2
  for i = 0, rays - 1 do
    local a = facing - half + Sight.FOV * i / (rays - 1)
    fan[i * 2 + 1], fan[i * 2 + 2] = Sight.reach(x, y, a, range)
  end
  local r, g, b, fill, edge = 1, 0.95, 0.7, 0.10, 0.28
  if alert then
    local pulse = 0.5 + 0.5 * math.sin((time or 0) * 12)
    r, g, b, fill, edge = 1, 0.2, 0.15, 0.16 + 0.08 * pulse, 0.5
  end
  love.graphics.setColor(r, g, b, fill)
  for i = 1, rays - 1 do
    -- One triangle per pair of rays: each is convex, the whole fan may not be.
    love.graphics.polygon("fill", x, y, fan[i * 2 - 1], fan[i * 2], fan[i * 2 + 1], fan[i * 2 + 2])
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(r, g, b, edge)
  love.graphics.line(x, y, fan[1], fan[2])
  love.graphics.line(x, y, fan[rays * 2 - 1], fan[rays * 2])
  love.graphics.setColor(1, 1, 1)
end

return Sight
