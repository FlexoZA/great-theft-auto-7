-- Car-to-car collisions on the server. Cars are capsules of three circles
-- (like the map collision); overlapping cars are pushed apart, both lose
-- speed, and every feature hears about it:
--
--   feature:serverCarsCollided(server, rammer, rammed, closingSpeed)
--
-- `rammer` is the player whose car was moving into the other one faster.
-- Bots use this to take offence at being rammed.

local Features = require("src.features")

local CarCollisions = {
  name = "car-collisions",
  priority = 25, -- after the map has settled cars against walls (20)
}

CarCollisions.radius = 11
CarCollisions.offsets = { -12, 0, 12 }
CarCollisions.damping = 0.55 -- speed kept by both cars on a closing hit

local function circles(car, out)
  local ca, sa = math.cos(car.angle), math.sin(car.angle)
  for i, off in ipairs(CarCollisions.offsets) do
    out[i] = out[i] or {}
    out[i][1], out[i][2] = car.x + ca * off, car.y + sa * off
  end
  return out
end

local ca, cb = {}, {}

--- Resolve one pair. Returns closing speed and the normal from a to b if they touched.
local function resolvePair(a, b)
  local r2 = CarCollisions.radius * 2
  circles(a, ca)
  circles(b, cb)
  local nx, ny, hit = 0, 0, false
  for i = 1, #ca do
    for j = 1, #cb do
      local dx, dy = cb[j][1] - ca[i][1], cb[j][2] - ca[i][2]
      local d2 = dx * dx + dy * dy
      if d2 < r2 * r2 and d2 > 1e-6 then
        local d = math.sqrt(d2)
        local push = (r2 - d) / 2
        local ux, uy = dx / d, dy / d
        a.x, a.y = a.x - ux * push, a.y - uy * push
        b.x, b.y = b.x + ux * push, b.y + uy * push
        nx, ny = nx + ux, ny + uy
        hit = true
        circles(a, ca)
        circles(b, cb)
      end
    end
  end
  if not hit then
    return nil
  end
  local len = math.sqrt(nx * nx + ny * ny)
  if len < 1e-6 then
    return 0, 1, 0
  end
  nx, ny = nx / len, ny / len
  local avx, avy = a.vx or math.cos(a.angle) * a.speed, a.vy or math.sin(a.angle) * a.speed
  local bvx, bvy = b.vx or math.cos(b.angle) * b.speed, b.vy or math.sin(b.angle) * b.speed
  local van = avx * nx + avy * ny
  local vbn = bvx * nx + bvy * ny
  local closing = van - vbn -- > 0 when a moves into b (or b into a)
  if closing > 0 then
    local d = CarCollisions.damping
    a.vx, a.vy = avx * d, avy * d
    b.vx, b.vy = bvx * d, bvy * d
    a.speed = a.vx * math.cos(a.angle) + a.vy * math.sin(a.angle)
    b.speed = b.vx * math.cos(b.angle) + b.vy * math.sin(b.angle)
    a.lastSpeed, b.lastSpeed = a.speed, b.speed
  end
  return closing, van, -vbn
end

function CarCollisions:serverStep(server)
  local list = {}
  for _, p in pairs(server.players) do
    if p.car and not p.car.hidden then
      list[#list + 1] = p
    end
  end
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      local closing, aInto, bInto = resolvePair(a.car, b.car)
      if closing and closing > 0 then
        -- Whoever was moving into the other faster did the ramming.
        local rammer, rammed = a, b
        if bInto > aInto then
          rammer, rammed = b, a
        end
        Features.call("serverCarsCollided", server, rammer, rammed, closing)
      end
    end
  end
end

return CarCollisions
