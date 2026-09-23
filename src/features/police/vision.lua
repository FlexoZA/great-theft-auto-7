-- What the police can see: a cone `FOV` wide in front of a unit or an
-- officer, out to a range, and only where nothing solid stands in the way.
-- Walls come from every feature's `blocksPoint` (docs/features.md), the
-- same rule bullets follow, so a building that stops a shot hides you too.
--
-- Clients draw the cone as a faint white fan, clipped by the same walls, so
-- a player can see exactly where they are being watched.

local Features = require("src.features")

local Vision = {}

Vision.FOV = math.rad(30) -- full width of the cone
Vision.STEP = 14 -- px between line-of-sight samples
Vision.RAYS = 9 -- rays across the cone when drawing it
Vision.FILL = 0.11 -- alpha of the drawn cone
Vision.EDGE = 0.28 -- alpha of its edges

local TWO_PI = 2 * math.pi

--- Shortest signed turn from heading b to heading a.
local function angleDiff(a, b)
  return (a - b + math.pi) % TWO_PI - math.pi
end

--- Is (x, y) inside anything solid?
function Vision.blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- How far a look from (x, y) along `angle` gets before it hits a wall, at
--- most `range`. Returns the end point.
function Vision.reach(x, y, angle, range)
  local cx, cy = math.cos(angle), math.sin(angle)
  local step = Vision.STEP
  local d = step
  while d < range do
    if Vision.blocked(x + cx * d, y + cy * d) then
      return x + cx * (d - step), y + cy * (d - step)
    end
    d = d + step
  end
  return x + cx * range, y + cy * range
end

--- Is the straight line from (x0, y0) to (x1, y1) free of walls?
function Vision.clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local dist = math.sqrt(dx * dx + dy * dy)
  if dist < Vision.STEP then
    return true
  end
  local n = math.floor(dist / Vision.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Vision.blocked(x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Can someone at (x, y) facing `facing` see (tx, ty)? Within `range`,
--- inside the cone (unless `anyAngle`, for someone already turned to look)
--- and with nothing in between. Returns the squared distance when they can.
function Vision.canSee(x, y, facing, tx, ty, range, anyAngle)
  local dx, dy = tx - x, ty - y
  local d2 = dx * dx + dy * dy
  if d2 > range * range then
    return nil
  end
  if not anyAngle and math.abs(angleDiff(math.atan2(dy, dx), facing)) > Vision.FOV / 2 then
    return nil
  end
  if not Vision.clear(x, y, tx, ty) then
    return nil
  end
  return d2
end

-- Drawing -------------------------------------------------------------------

local fan = {} -- reused: the clipped end of each ray

--- The cone from (x, y) facing `facing`, out to `range`, as a faint white
--- fan that stops at walls. `glow` (0..1) brightens it (a unit that has
--- someone in its sights).
function Vision.draw(x, y, facing, range, glow)
  local rays = Vision.RAYS
  local half = Vision.FOV / 2
  for i = 0, rays - 1 do
    local a = facing - half + Vision.FOV * i / (rays - 1)
    local ex, ey = Vision.reach(x, y, a, range)
    fan[i * 2 + 1], fan[i * 2 + 2] = ex, ey
  end
  glow = glow or 0
  love.graphics.setColor(1, 1, 1, Vision.FILL + 0.08 * glow)
  for i = 1, rays - 1 do
    -- One triangle per pair of rays: each is convex, the whole fan may not be.
    love.graphics.polygon("fill", x, y, fan[i * 2 - 1], fan[i * 2], fan[i * 2 + 1], fan[i * 2 + 2])
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, Vision.EDGE + 0.2 * glow)
  love.graphics.line(x, y, fan[1], fan[2])
  love.graphics.line(x, y, fan[rays * 2 - 1], fan[rays * 2])
  love.graphics.setColor(1, 1, 1)
end

return Vision
