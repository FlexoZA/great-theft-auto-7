-- Where the Hunter-Chopper flies, on the host: round and round the square
-- on the Outer City's island, never quite the same circle twice. Its path
-- is a ring round the middle of the square that swells out to its edge
-- and pulls in over the paving in a few slow lobes, so it sweeps close over
-- one stretch of the square and wide past the next; the lobes drift round
-- as it goes. It faces where it is going, leans into the curve and bobs a
-- little in the air. Nothing here shoots or gets shot yet.

local Flight = {}

-- Tuning ------------------------------------------------------------------
Flight.speed = 210 -- px a second along its path
Flight.radius = 520 -- px from the middle of the square, on average
Flight.swing = 150 -- px the lobes take it in and out of that
Flight.lobes = 3 -- in and out this many times a lap
Flight.drift = 0.07 -- radians a second the lobes creep round
Flight.bankFor = 0.9 -- radians a second of turning that leans it right over
Flight.altitude = 80 -- px up, on average (its shadow falls this far)
Flight.bob = 8 -- px up and down
Flight.bobEvery = 3.2 -- seconds for one bob

--- A chopper flying round (cx, cy), starting `at` radians round.
function Flight.new(cx, cy, at)
  local f = { cx = cx, cy = cy, theta = at or 0, time = 0, x = cx, y = cy, angle = 0, bank = 0, altitude = 0 }
  Flight.step(f, 0)
  return f
end

local function ring(f, theta)
  local r = Flight.radius + Flight.swing * math.sin(theta * Flight.lobes + f.time * Flight.drift)
  return f.cx + math.cos(theta) * r, f.cy + math.sin(theta) * r
end

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

--- Fly on `dt` seconds: round the ring at its speed, nose along the way.
function Flight.step(f, dt)
  f.time = f.time + dt
  -- How far round the ring a stride of `speed * dt` takes it here.
  local x0, y0 = ring(f, f.theta)
  local x1, y1 = ring(f, f.theta + 0.01)
  local per = math.max(1, math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / 0.01) -- px per radian round
  f.theta = (f.theta + Flight.speed * dt / per) % (2 * math.pi)
  local x, y = ring(f, f.theta)
  local ax, ay = ring(f, f.theta + 0.02)
  local angle = math.atan2(ay - y, ax - x)
  local turn = dt > 0 and wrap(angle - f.angle) / dt or 0
  f.bank = f.bank + (math.max(-1, math.min(1, turn / Flight.bankFor)) - f.bank) * math.min(1, dt * 3)
  f.x, f.y, f.angle = x, y, angle
  f.altitude = Flight.altitude + Flight.bob * math.sin(f.time * 2 * math.pi / Flight.bobEvery)
end

return Flight
