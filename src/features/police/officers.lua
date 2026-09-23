-- Police on foot: officers who walk a beat near the players, witness crimes
-- the way a patrol car does and draw a pistol on anyone wanted. The host owns
-- them completely -- where they stand, what they aim at, their health and
-- their death -- and clients only draw what arrives in POL_FOOT (init.lua
-- owns the wire format).
--
-- They are not players and have no car, so they shoot through the weapons
-- feature's ownerless entry point: their bullets belong to the force rather
-- than to anybody's scoreboard.
--
-- Cost per tick is O(officers x cars) with at most MAX officers, so the whole
-- beat is cheaper than a handful of pedestrians.

local Features = require("src.features")
local Car = require("src.car")

local Officers = {}
Officers.__index = Officers

-- Tuning --------------------------------------------------------------------

Officers.OWNER = 0 -- projectile owner id for a shot fired by the force itself
Officers.WALK_SPEED = 52 -- px/s on the beat
Officers.CHASE_SPEED = 155 -- px/s closing on someone wanted
Officers.RADIUS = 7 -- px; how fat an officer is for hit tests
Officers.HEALTH = 50 -- three bullets, the same as a pistol takes off a car
Officers.SHOT_DAMAGE = 20 -- what one bullet does, matching the weapons feature
Officers.SIGHT = 620 -- px; witnesses crimes and spots wanted players inside this
Officers.PURSUE = 1150 -- px; keeps after someone already spotted out to here
Officers.FIRE_RANGE = 520 -- px; won't shoot beyond this
Officers.FIRE_INTERVAL = 0.9 -- seconds between shots
Officers.SPREAD = 0.1 -- radians of aim error
Officers.STANDOFF = 110 -- px; closer than this they stand and shoot
Officers.MUZZLE = 14 -- px from the body a shot leaves, clear of their own feet
Officers.SPLAT_SPEED = 90 -- car speed (px/s) that turns one into a stain
Officers.PER_PLAYER = 1.5 -- officers on the street per living driver
Officers.MAX = 8 -- hard cap whatever the player count
Officers.BACKUP = 2 -- extra officers out while anyone is wanted
Officers.SPAWN_MIN = 700 -- px; they arrive just outside anyone's view...
Officers.SPAWN_MAX = 1250 -- ...and no further than this from the player they cover
Officers.DESPAWN = 1900 -- px from the nearest player before one walks off duty
Officers.MAINTAIN_EVERY = 0.5 -- seconds between spawn/despawn sweeps
Officers.SPAWN_BURST = 2 -- most officers added in one sweep
Officers.WAYPOINT_TIMEOUT = 20 -- seconds before giving up on a patrol waypoint

local DESPAWN2 = Officers.DESPAWN * Officers.DESPAWN
local SPAWN_MIN2 = Officers.SPAWN_MIN * Officers.SPAWN_MIN
-- Anything further than this from a car centre cannot be touching it.
local TOUCH2 = (Car.WIDTH / 2 + Officers.RADIUS + 2) ^ 2

local random = love.math.random

-- Walking -------------------------------------------------------------------

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
--- The body is a circle, so the point is tested with its four extremes.
local function blockedAt(x, y)
  local r = Officers.RADIUS
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
--- into, and a note of whether the step actually got anywhere: an officer
--- wedged in a doorway gives up on where they were going.
local function walk(o, angle, speed, dt)
  local px, py = o.x, o.y
  local nx = o.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, o.y) then
    o.x = nx
  end
  local ny = o.y + math.sin(angle) * speed * dt
  if not blockedAt(o.x, ny) then
    o.y = ny
  end
  local moved = (o.x - px) ^ 2 + (o.y - py) ^ 2
  if moved < (speed * dt * 0.4) ^ 2 then
    o.stuck = o.stuck + dt
  else
    o.stuck = 0
  end
end

-- The beat ------------------------------------------------------------------

function Officers.new()
  return setmetatable({
    list = {},
    n = 0,
    nextId = 1,
    time = 0,
    maintainTimer = 0,
    kills = {}, -- reused every tick: { id, x, y, angle, by }
    bodies = {}, -- reused every tick: see collect()
  }, Officers)
end

function Officers:spawn(x, y)
  local id = self.nextId
  self.nextId = id + 1
  local o = {
    id = id,
    x = x,
    y = y,
    facing = random() * 2 * math.pi,
    hp = Officers.HEALTH,
    target = nil,
    fireTimer = random() * Officers.FIRE_INTERVAL,
    waypoint = nil,
    waypointUntil = 0,
    stuck = 0,
    sidestep = 0,
    side = random() < 0.5 and -1 or 1,
    frozen = 0, -- seconds left rooted to the spot
  }
  self.n = self.n + 1
  self.list[self.n] = o
  return o
end

--- Everyone off duty at once (a map with no crowd).
function Officers:clear()
  for i = self.n, 1, -1 do
    self.list[i] = nil
  end
  self.n = 0
end

function Officers:removeAt(i)
  local n = self.n
  self.list[i] = self.list[n]
  self.list[n] = nil
  self.n = n - 1
end

function Officers:remove(o)
  for i = 1, self.n do
    if self.list[i] == o then
      self:removeAt(i)
      return
    end
  end
end

--- The first officer standing within `radius` of (x, y). Used by anything
--- that shoots at them; the caller does the damage.
function Officers:at(x, y, radius)
  local r2 = (radius + Officers.RADIUS) ^ 2
  for i = 1, self.n do
    local o = self.list[i]
    if (o.x - x) ^ 2 + (o.y - y) ^ 2 < r2 then
      return o
    end
  end
  return nil
end

--- Is anyone standing within `range` of (x, y) to see what just happened?
function Officers:sees(x, y, range)
  local r2 = range * range
  for i = 1, self.n do
    local o = self.list[i]
    if (o.x - x) ^ 2 + (o.y - y) ^ 2 <= r2 then
      return true
    end
  end
  return false
end

--- Snapshot of every live player, with the body they present this tick: their
--- car, or them on foot beside it. Returns the (reused) table and how many
--- entries are live, the way the crowd does it.
function Officers:collect(server)
  local list, n = self.bodies, 0
  for id, player in pairs(server.players) do
    if Features.present(player) then
      n = n + 1
      local e = list[n]
      if not e then
        e = {}
        list[n] = e
      end
      e.id, e.player, e.car, e.police = id, player, player.vehicle, player.police or false
      e.x, e.y, e.onFoot = Features.bodyPose(server, player)
    end
  end
  return list, n
end

local function nearestBody2(o, bodies, nbodies)
  local best = math.huge
  for i = 1, nbodies do
    local e = bodies[i]
    local d2 = (e.x - o.x) ^ 2 + (e.y - o.y) ^ 2
    if d2 < best then
      best = d2
    end
  end
  return best
end

-- Behaviour -----------------------------------------------------------------

function Officers.newWaypoint(o, time)
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
  o.waypointUntil = time + Officers.WAYPOINT_TIMEOUT
end

--- Nobody to hunt: stroll between road points, looking where you are going.
function Officers:patrol(o, dt, time)
  if not o.waypoint or time > o.waypointUntil or o.stuck > 0.5 then
    Officers.newWaypoint(o, time)
    o.stuck = 0
  end
  local dx, dy = o.waypoint.x - o.x, o.waypoint.y - o.y
  if dx * dx + dy * dy < 40 * 40 then
    Officers.newWaypoint(o, time)
    return
  end
  o.facing = math.atan2(dy, dx)
  walk(o, o.facing, Officers.WALK_SPEED, dt)
end

--- Fire at `target`, leading a car by its velocity over the bullet's flight
--- the way the bots do. The shot belongs to the force, not to a player.
function Officers:fire(server, o, target, dist)
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
  local aim = math.atan2(py - o.y, px - o.x) + (random() - 0.5) * 2 * Officers.SPREAD
  o.facing = aim
  local mx, my = math.cos(aim), math.sin(aim)
  Weapons:serverFireFrom(server, Officers.OWNER, o.x + mx * Officers.MUZZLE, o.y + my * Officers.MUZZLE, aim)
end

--- Close on someone wanted and shoot at them. Inside the standoff distance
--- they stand their ground; wedged against a wall they sidestep around it.
function Officers:hunt(server, o, dt, target, dist)
  o.facing = math.atan2(target.y - o.y, target.x - o.x)
  if o.sidestep > 0 then
    o.sidestep = o.sidestep - dt
    walk(o, o.facing + o.side * math.pi / 2, Officers.CHASE_SPEED, dt)
  elseif dist > Officers.STANDOFF then
    walk(o, o.facing, Officers.CHASE_SPEED, dt)
    if o.stuck > 0.4 then
      o.stuck, o.sidestep, o.side = 0, 0.7, -o.side
    end
  end

  o.fireTimer = o.fireTimer - dt
  if o.fireTimer <= 0 and dist <= Officers.FIRE_RANGE then
    o.fireTimer = Officers.FIRE_INTERVAL * (0.8 + random() * 0.4)
    self:fire(server, o, target, dist)
  end
end

--- A car touching this officer: flattened at speed, shoved aside below it.
--- Returns the kill, for the caller to announce.
function Officers:trampled(o, dt, bodies, nbodies)
  for i = 1, nbodies do
    local car = bodies[i].car -- nil for a player on foot: no bumper to worry about
    if car and (car.x - o.x) ^ 2 + (car.y - o.y) ^ 2 < TOUCH2 and Car.hitTest(car, o.x, o.y, Officers.RADIUS) then
      local speed = math.abs(car.speed)
      if speed >= Officers.SPLAT_SPEED then
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        return { id = o.id, x = o.x, y = o.y, angle = travel, by = bodies[i].id }
      end
      local away = math.atan2(o.y - car.y, o.x - car.x)
      local push = (Officers.WALK_SPEED + speed) * dt * 2
      o.x, o.y = o.x + math.cos(away) * push, o.y + math.sin(away) * push
    end
  end
  return nil
end

--- The nearest wanted player this officer can see, out to sight range, or to
--- pursuit range for one they are already after.
function Officers.spot(o, wanted, bodies, nbodies)
  local range = o.target and Officers.PURSUE or Officers.SIGHT
  local best, bestD2
  for i = 1, nbodies do
    local e = bodies[i]
    if wanted[e.id] and not e.police then
      local d2 = (e.x - o.x) ^ 2 + (e.y - o.y) ^ 2
      if d2 <= range * range and (not bestD2 or d2 < bestD2) then
        best, bestD2 = e, d2
      end
    end
  end
  return best, bestD2
end

-- Population ----------------------------------------------------------------

--- A road point near (nearX, nearY) that is out of everyone's view, or nil if
--- the city has nowhere to put one.
function Officers.spawnSpot(nearX, nearY, bodies, nbodies)
  local city = Features.byName["city-map"]
  for _ = 1, 8 do
    local x, y
    if city and city.randomRoadPoint then
      x, y = city:randomRoadPoint(nearX, nearY, Officers.SPAWN_MAX)
    else
      local a = random() * 2 * math.pi
      local r = Officers.SPAWN_MIN + random() * (Officers.SPAWN_MAX - Officers.SPAWN_MIN)
      x, y = nearX + math.cos(a) * r, nearY + math.sin(a) * r
    end
    if x then
      local clear = not blockedAt(x, y)
      for i = 1, nbodies do
        local e = bodies[i]
        if (e.x - x) ^ 2 + (e.y - y) ^ 2 < SPAWN_MIN2 then
          clear = false
        end
      end
      if clear then
        return x, y
      end
    end
  end
  return nil
end

--- Send officers nobody is near off duty and post new ones where the players
--- are. Runs twice a second, not every tick. Nobody mid-chase is recycled.
function Officers:maintain(bodies, nbodies, anyWanted)
  if nbodies == 0 then
    return
  end

  local i = 1
  while i <= self.n do
    local o = self.list[i]
    if not o.target and nearestBody2(o, bodies, nbodies) > DESPAWN2 then
      self:removeAt(i)
    else
      i = i + 1
    end
  end

  local civilians = 0
  for j = 1, nbodies do
    if not bodies[j].police then
      civilians = civilians + 1
    end
  end
  local target = math.min(Officers.MAX, math.ceil(Officers.PER_PLAYER * civilians))
  if anyWanted then
    target = math.min(Officers.MAX, target + Officers.BACKUP)
  end

  local budget = Officers.SPAWN_BURST
  while self.n < target and budget > 0 do
    budget = budget - 1
    local e = bodies[random(nbodies)]
    local x, y = Officers.spawnSpot(e.x, e.y, bodies, nbodies)
    if not x then
      break
    end
    self:spawn(x, y)
  end
end

--- Advance the whole beat. `wanted` is the set of wanted player ids.
--- Returns the (reused) list of officers a car killed this tick.
--- Root every officer within `radius` of (x, y) to the spot for `seconds`.
function Officers:freeze(x, y, radius, seconds)
  local r2 = (radius + Officers.RADIUS) ^ 2
  for i = 1, self.n do
    local o = self.list[i]
    local dx, dy = o.x - x, o.y - y
    if dx * dx + dy * dy <= r2 then
      o.frozen = math.max(o.frozen, seconds)
    end
  end
end

function Officers:update(server, dt, wanted, anyWanted)
  self.time = self.time + dt
  local bodies, nbodies = self:collect(server)
  local kills = self.kills
  for i = #kills, 1, -1 do
    kills[i] = nil
  end

  local i = 1
  while i <= self.n do
    local o = self.list[i]
    local target, d2 = Officers.spot(o, wanted, bodies, nbodies)
    o.target = target and target.id or nil
    if o.frozen > 0 then
      o.frozen = o.frozen - dt -- frozen: neither hunts nor patrols
    elseif target then
      self:hunt(server, o, dt, target, math.sqrt(d2))
    else
      self:patrol(o, dt, self.time)
    end
    local kill = self:trampled(o, dt, bodies, nbodies)
    if kill then
      kills[#kills + 1] = kill
      self:removeAt(i)
    else
      i = i + 1
    end
  end

  self.maintainTimer = self.maintainTimer - dt
  if self.maintainTimer <= 0 then
    self.maintainTimer = Officers.MAINTAIN_EVERY
    self:maintain(bodies, nbodies, anyWanted)
  end
  return kills
end

return Officers
