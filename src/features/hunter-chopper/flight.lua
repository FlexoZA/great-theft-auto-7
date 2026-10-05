-- Where the Hunter-Chopper flies, on the host: round and round the square
-- on the Outer City's island, never quite the same circle twice. Its path
-- is a ring round the middle of the square that swells out to its edge
-- and pulls in over the paving in a few slow lobes, so it sweeps close over
-- one stretch of the square and wide past the next; the lobes drift round
-- as it goes. It faces where it is going, leans into the curve and bobs a
-- little in the air.
--
-- It can leave the ring to fly somewhere (`Flight.flyTo`, a bombing run:
-- brain.lua): it turns towards the point no faster than `turnRate` and
-- flies on at the speed it was given until told otherwise, and
-- `Flight.rejoin` brings it round back onto the ring, where it goes on
-- circling from wherever it joined. `f.travel` counts the px it has flown.

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
Flight.turnRate = 1.8 -- radians a second it can turn off the ring
Flight.joinAt = 30 -- px from the ring that counts as back on it

--- A chopper flying round (cx, cy), starting `at` radians round.
function Flight.new(cx, cy, at)
  local f = { cx = cx, cy = cy, theta = at or 0, time = 0, x = cx, y = cy, angle = 0, bank = 0, altitude = 0,
    travel = 0, course = nil, joining = false }
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

--- Leave the ring (or change course) for (x, y), at `speed` px a second.
function Flight.flyTo(f, x, y, speed)
  f.course, f.joining = { x = x, y = y, speed = speed or Flight.speed }, false
end

--- Head back round onto the ring, and circle again from there.
function Flight.rejoin(f)
  f.course, f.joining = nil, true
end

--- Is it off the ring, flying somewhere or on its way back?
function Flight.away(f)
  return f.course ~= nil or f.joining
end

local function lean(f, angle, dt)
  local turn = dt > 0 and wrap(angle - f.angle) / dt or 0
  f.bank = f.bank + (math.max(-1, math.min(1, turn / Flight.bankFor)) - f.bank) * math.min(1, dt * 3)
end

--- Turn towards (x, y) no faster than `turnRate` and fly on at `speed`.
local function steer(f, x, y, speed, dt)
  local want = math.atan2(y - f.y, x - f.x)
  local d = wrap(want - f.angle)
  local step = Flight.turnRate * dt
  local angle = f.angle + math.max(-step, math.min(step, d))
  lean(f, angle, dt)
  f.angle = angle
  f.x, f.y = f.x + math.cos(angle) * speed * dt, f.y + math.sin(angle) * speed * dt
  f.travel = f.travel + speed * dt
end

--- Fly on `dt` seconds: round the ring at its speed, nose along the way,
--- or wherever it has been sent.
function Flight.step(f, dt)
  f.time = f.time + dt
  f.altitude = Flight.altitude + Flight.bob * math.sin(f.time * 2 * math.pi / Flight.bobEvery)
  if f.course then
    steer(f, f.course.x, f.course.y, f.course.speed, dt)
    return
  end
  if f.joining then
    -- For a point on the ring a little further round than where it is.
    local theta = math.atan2(f.y - f.cy, f.x - f.cx)
    local rx, ry = ring(f, theta)
    if (rx - f.x) ^ 2 + (ry - f.y) ^ 2 <= Flight.joinAt ^ 2 then
      f.theta, f.joining = theta % (2 * math.pi), false
    else
      local ax, ay = ring(f, theta + 0.35)
      steer(f, ax, ay, Flight.speed, dt)
      return
    end
  end
  -- How far round the ring a stride of `speed * dt` takes it here.
  local x0, y0 = ring(f, f.theta)
  local x1, y1 = ring(f, f.theta + 0.01)
  local per = math.max(1, math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2) / 0.01) -- px per radian round
  f.theta = (f.theta + Flight.speed * dt / per) % (2 * math.pi)
  local x, y = ring(f, f.theta)
  local ax, ay = ring(f, f.theta + 0.02)
  local angle = math.atan2(ay - y, ax - x)
  lean(f, angle, dt)
  f.x, f.y, f.angle = x, y, angle
  f.travel = f.travel + Flight.speed * dt
end

return Flight
