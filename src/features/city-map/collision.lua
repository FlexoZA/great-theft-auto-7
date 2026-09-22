-- Circle-vs-solids resolution against the layout's bucketed rectangles.

local Layout = require("src.features.city-map.layout")

local Collision = {}

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

--- Push a circle out of one rectangle. Returns dx, dy, nx, ny or nil.
local function circleVsRect(x, y, r, b)
  local cx = clamp(x, b.x, b.x + b.w)
  local cy = clamp(y, b.y, b.y + b.h)
  local dx, dy = x - cx, y - cy
  local d2 = dx * dx + dy * dy
  if d2 >= r * r then
    return nil
  end
  if d2 > 1e-6 then
    local d = math.sqrt(d2)
    local push = r - d
    return dx / d * push, dy / d * push, dx / d, dy / d
  end
  -- Centre is inside: leave through the nearest face.
  local left, right = x - b.x, b.x + b.w - x
  local top, bottom = y - b.y, b.y + b.h - y
  local m = math.min(left, right, top, bottom)
  if m == left then
    return -(left + r), 0, -1, 0
  elseif m == right then
    return right + r, 0, 1, 0
  elseif m == top then
    return 0, -(top + r), 0, -1
  end
  return 0, bottom + r, 0, 1
end

--- Is the point inside any solid?
function Collision.blocked(map, x, y)
  local CELL = Layout.CELL
  local col = map.cells[math.floor(x / CELL)]
  local list = col and col[math.floor(y / CELL)]
  if not list then
    return false
  end
  for _, b in ipairs(list) do
    if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return true
    end
  end
  return false
end

--- Resolve a circle against every nearby solid. Returns the corrected x, y
--- and the summed collision normal (nx, ny), or x, y, nil when free.
function Collision.resolveCircle(map, x, y, r)
  local CELL = Layout.CELL
  local nx, ny, hit = 0, 0, false
  local c0, c1 = math.floor((x - r) / CELL), math.floor((x + r) / CELL)
  local r0, r1 = math.floor((y - r) / CELL), math.floor((y + r) / CELL)
  for c = c0, c1 do
    local col = map.cells[c]
    if col then
      for row = r0, r1 do
        local list = col[row]
        if list then
          for _, b in ipairs(list) do
            local dx, dy, n1, n2 = circleVsRect(x, y, r, b)
            if dx then
              x, y = x + dx, y + dy
              nx, ny = nx + n1, ny + n2
              hit = true
            end
          end
        end
      end
    end
  end
  if hit then
    return x, y, nx, ny
  end
  return x, y, nil
end

--- Cars are a capsule of three circles along their axis. Pushes the car out
--- of walls and kills or reverses its speed depending on the angle of impact.
--- Returns true when the car touched something.
function Collision.resolveCar(map, car)
  local ca, sa = math.cos(car.angle), math.sin(car.angle)
  local nx, ny, hit = 0, 0, false
  for _, off in ipairs({ -12, 0, 12 }) do
    local px, py = car.x + ca * off, car.y + sa * off
    local rx, ry, n1, n2 = Collision.resolveCircle(map, px, py, 11)
    if n1 then
      car.x, car.y = car.x + (rx - px), car.y + (ry - py)
      nx, ny = nx + n1, ny + n2
      hit = true
    end
  end
  if hit then
    local len = math.sqrt(nx * nx + ny * ny)
    nx, ny = nx / len, ny / len
    local vx, vy = car.vx or ca * car.speed, car.vy or sa * car.speed
    local into = vx * nx + vy * ny
    if into < 0 then
      -- Into the wall: remove the inward part and bounce back a little.
      vx, vy = (vx - into * nx) * 0.6, (vy - into * ny) * 0.6
      vx, vy = vx - nx * into * 0.3, vy - ny * into * 0.3
    else
      vx, vy = vx * 0.92, vy * 0.92 -- scraping along it
    end
    car.vx, car.vy = vx, vy
    car.speed = vx * ca + vy * sa
    car.lastSpeed = car.speed
  end
  return hit
end

return Collision
