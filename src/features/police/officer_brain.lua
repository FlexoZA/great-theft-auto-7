-- The police officers' brain, on the host: what each officer on foot does
-- each tick. The beat itself (who is on duty, where they come on and go
-- off, the cars that flatten them) is officers.lua; an officer is handed
-- in as `o`, the beat's numbers as `O`.
--
-- Each is always in one of these, the later ones cutting in on the earlier:
--
--   patrol   strolling between road points, looking where they are going
--   search   lost sight of someone wanted, or shot at by someone they can't
--            see, or answering a call: they go to the spot, look round for
--            SEARCH_TIME and go back to the beat
--   hunt     somebody wanted in sight (in the cone in front out to SIGHT, or
--            all round out to PURSUE once they are after them): they close
--            to STANDOFF and fire, and call it in over the radio once, so
--            every officer within RADIO who isn't busy comes to the spot
--
-- Frozen, they stand to attention. They never go after police.

local Features = require("src.features")
local Vision = require("src.features.police.vision")

local Brain = {}

-- Tuning --------------------------------------------------------------------

Brain.SEARCH_TIME = 4 -- seconds looking round where they lost somebody
Brain.SEARCH_SPEED = 110 -- px/s on their way to look
Brain.RADIO = 900 -- px; officers this near the one who calls it in come
Brain.RADIO_EVERY = 10 -- seconds before the same officer calls in again
Brain.HEARD_SHOT = 260 -- px back along a round that hit them that they go looking

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
--- The body is a circle, so the point is tested with its four extremes.
function Brain.blockedAt(x, y, r)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along rather than run
--- into; wedged against one, they sidestep round it.
local function walk(O, o, angle, speed, dt)
  if o.sidestep > 0 then
    o.sidestep = o.sidestep - dt
    angle = angle + o.side * math.pi / 2
  end
  local px, py = o.x, o.y
  local nx = o.x + math.cos(angle) * speed * dt
  if not Brain.blockedAt(nx, o.y, O.RADIUS) then
    o.x = nx
  end
  local ny = o.y + math.sin(angle) * speed * dt
  if not Brain.blockedAt(o.x, ny, O.RADIUS) then
    o.y = ny
  end
  if dist2(o.x, o.y, px, py) < (speed * dt * 0.4) ^ 2 then
    o.stuck = o.stuck + dt
  else
    o.stuck = 0
  end
end

--- A new road point to stroll to.
local function newWaypoint(O, o, time)
  local city = Features.byName["city-map"]
  local x, y
  if city and city.randomRoadPoint then
    x, y = city:randomRoadPoint(o.x, o.y, 900)
  end
  if not x then
    local a = random() * 2 * math.pi
    x, y = o.x + math.cos(a) * 350, o.y + math.sin(a) * 350
  end
  o.waypoint = { x = x, y = y }
  o.waypointUntil = time + O.WAYPOINT_TIMEOUT
end

--- Nobody to hunt: stroll between road points, looking where they are going.
local function patrol(O, o, dt, time)
  if not o.waypoint or time > o.waypointUntil or o.stuck > 0.5 then
    newWaypoint(O, o, time)
    o.stuck = 0
  end
  local dx, dy = o.waypoint.x - o.x, o.waypoint.y - o.y
  if dx * dx + dy * dy < 40 * 40 then
    newWaypoint(O, o, time)
    return
  end
  o.facing = math.atan2(dy, dx)
  walk(O, o, o.facing, O.WALK_SPEED, dt)
end

--- Fire at `target`, leading a car by its velocity over the bullet's flight
--- the way the bots do. The shot belongs to the force, not to a player.
local function fire(O, o, server, target, dist)
  local Weapons = Features.byName.weapons
  if not (Weapons and Weapons.serverFireFrom) then
    return
  end
  local px, py = target.x, target.y
  if not target.onFoot then
    local car = target.car
    local flight = dist / Weapons.PROJECTILE_SPEED
    px = px + math.cos(car.angle) * car.speed * flight
    py = py + math.sin(car.angle) * car.speed * flight
  end
  local aim = math.atan2(py - o.y, px - o.x) + (random() - 0.5) * 2 * O.SPREAD
  o.facing = aim
  local mx, my = math.cos(aim), math.sin(aim)
  Weapons:serverFireFrom(server, O.OWNER, o.x + mx * O.MUZZLE, o.y + my * O.MUZZLE, aim)
end

--- Close on someone wanted and shoot at them; inside the standoff distance
--- they stand their ground.
local function hunt(O, o, server, dt, target, dist)
  o.facing = math.atan2(target.y - o.y, target.x - o.x)
  if dist > O.STANDOFF or o.sidestep > 0 then
    walk(O, o, o.facing, O.CHASE_SPEED, dt)
    if o.stuck > 0.4 then
      o.stuck, o.sidestep, o.side = 0, 0.7, -o.side
    end
  end
  o.fireTimer = o.fireTimer - dt
  if o.fireTimer <= 0 and dist <= O.FIRE_RANGE then
    o.fireTimer = O.FIRE_INTERVAL * (0.8 + random() * 0.4)
    fire(O, o, server, target, dist)
  end
end

--- Off to look at (x, y): unless they are after somebody already.
function Brain.investigate(o, x, y)
  if o.target then
    return
  end
  o.search = { x = x, y = y, look = nil }
end

--- On their way to the spot, then looking round it. False once done.
local function search(O, o, dt)
  local s = o.search
  if s.look then
    s.look = s.look - dt
    o.facing = s.from + 1.4 * math.sin(s.look * 2.2)
    return s.look > 0
  end
  local dx, dy = s.x - o.x, s.y - o.y
  if dx * dx + dy * dy < 30 * 30 or o.stuck > 1.5 then
    s.look, s.from = Brain.SEARCH_TIME, o.facing
    return true
  end
  o.facing = math.atan2(dy, dx)
  walk(O, o, o.facing, Brain.SEARCH_SPEED, dt)
  if o.stuck > 0.4 then
    o.sidestep, o.side = 0.7, -o.side
  end
  return true
end

--- Officer `o` calls it in: everyone on the beat within RADIO who isn't
--- busy comes to (x, y).
local function radio(beat, o, x, y, time)
  if (o.radioUntil or 0) > time then
    return
  end
  o.radioUntil = time + Brain.RADIO_EVERY
  for i = 1, beat.n do
    local other = beat.list[i]
    if other ~= o and dist2(other.x, other.y, o.x, o.y) <= Brain.RADIO * Brain.RADIO then
      Brain.investigate(other, x, y)
    end
  end
end

--- The nearest wanted player this officer can see: in the cone in front of
--- them out to SIGHT, or all round out to PURSUE for one they are already
--- after. Returns the body and its squared distance.
local function spot(O, o, wanted, bodies, nbodies)
  local hunting = o.target ~= nil
  local range = hunting and O.PURSUE or O.SIGHT
  local best, bestD2
  for i = 1, nbodies do
    local e = bodies[i]
    if wanted[e.id] and not e.police then
      local d2 = Vision.canSee(o.x, o.y, o.facing, e.x, e.y, range, hunting)
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = e, d2
      end
    end
  end
  return best, bestD2
end

--- Officer `o` was shot by player `by`, the round going along `angle`:
--- they turn on the shooter if they can see them (the police feature makes
--- them wanted), and otherwise go and look the way it came, calling it in.
function Brain.shotAt(beat, o, by, angle, server, time)
  local p = by and server.players[by]
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    o.facing = math.atan2(y - o.y, x - o.x) -- the cone round onto them: next look, they have them
  elseif angle and not o.target then
    local x, y = o.x - math.cos(angle) * Brain.HEARD_SHOT, o.y - math.sin(angle) * Brain.HEARD_SHOT
    o.facing = angle + math.pi
    Brain.investigate(o, x, y)
    radio(beat, o, x, y, time)
  end
end

--- One officer's tick. `beat` is the whole force (for the radio), `wanted`
--- the set of wanted player ids, `bodies` everyone this tick.
function Brain.think(O, beat, o, server, dt, wanted, bodies, nbodies, time)
  if o.frozen > 0 then
    o.frozen = o.frozen - dt -- frozen: neither hunts nor patrols
    return
  end
  local target, d2 = spot(O, o, wanted, bodies, nbodies)
  if target then
    if o.target ~= target.id then
      radio(beat, o, target.x, target.y, time) -- a new one: called in
    end
    o.target, o.search, o.mode = target.id, nil, "hunt"
    o.lastX, o.lastY = target.x, target.y
    hunt(O, o, server, dt, target, math.sqrt(d2))
    return
  end
  if o.target then
    -- Lost them: to where they were last seen.
    o.target = nil
    Brain.investigate(o, o.lastX, o.lastY)
  end
  if o.search then
    o.mode = "search"
    if not search(O, o, dt) then
      o.search = nil
    end
    return
  end
  o.mode = "patrol"
  patrol(O, o, dt, time)
end

return Brain
