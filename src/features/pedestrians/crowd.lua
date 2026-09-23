-- Server-side crowd simulation: spawning, wandering, dodging and the moment
-- a bumper connects. Lives only on the host; see init.lua for the wire format.
--
-- Cost per tick is O(pedestrians x cars). Cars are few (players + bots) and
-- everything per car -- travel direction, its sine and cosine -- is computed
-- once per tick in collect(), so a pedestrian's turn is a handful of adds and
-- multiplies. Heading vectors are cached and only recomputed when a
-- pedestrian actually turns.

local Car = require("src.car")

local Crowd = {}
Crowd.__index = Crowd

-- Tuning --------------------------------------------------------------------

Crowd.WALK_SPEED = 45 -- px/s strolling
Crowd.FLEE_SPEED = 170 -- px/s when a car is bearing down
Crowd.RADIUS = 6 -- px; how fat a pedestrian is for hit tests
Crowd.SPLAT_SPEED = 90 -- car speed (px/s) needed to turn one into gibs
Crowd.FLEE_TIME = 1.5 -- seconds of sprinting after the last scare
Crowd.REACT_MIN = 0.12 -- seconds frozen in the headlights before bolting
Crowd.REACT_MAX = 0.34
Crowd.DANGER_RANGE = 320 -- px; no threat test beyond this
Crowd.DANGER_WIDTH = 34 -- px; half-width of the corridor in front of a car
Crowd.PER_CAR = 26 -- crowd size the server aims for per car
Crowd.MAX = 90 -- hard cap, whatever the player count (about 24 kB/s of PED_SYNC)
Crowd.SPAWN_MIN = 700 -- px; spawn ring around a random car...
Crowd.SPAWN_MAX = 1150 -- ...just outside anyone's view
Crowd.DESPAWN = 1500 -- px from the nearest car before one is recycled
Crowd.MAINTAIN_EVERY = 0.25 -- seconds between spawn/despawn sweeps
Crowd.SPAWN_BURST = 8 -- most pedestrians added in one sweep

local DESPAWN2 = Crowd.DESPAWN * Crowd.DESPAWN
local DANGER2 = Crowd.DANGER_RANGE * Crowd.DANGER_RANGE
-- Anything further than this from a car centre cannot be touching it.
local TOUCH2 = (Car.WIDTH / 2 + Crowd.RADIUS + 2) ^ 2

local random = love.math.random

local function setHeading(p, angle)
  p.heading = angle
  p.hx, p.hy = math.cos(angle), math.sin(angle)
end

function Crowd.new()
  return setmetatable({
    peds = {},
    n = 0,
    nextId = 1,
    maintainTimer = 0,
    kills = {}, -- reused every tick: { id, x, y, angle, by }
    cars = {}, -- reused every tick: see collect()
  }, Crowd)
end

--- Snapshot of every car in the world, with the per-car maths the
--- pedestrian loop needs. `id` is the driver, 0 for a car nobody is in (a
--- runaway kill credits nobody). Returns the (reused) table and how many
--- entries are live.
function Crowd:collect(server)
  local cars, n = self.cars, 0
  for _, car in pairs(server.vehicles) do
    if not car.hidden then
      n = n + 1
      local e = cars[n]
      if not e then
        e = {}
        cars[n] = e
      end
      e.id, e.car, e.x, e.y, e.speed = car.driver or 0, car, car.x, car.y, car.speed
      e.fast = math.abs(car.speed)
      -- Pedestrians care about where a car is going, which is backwards when
      -- it reverses; do that flip once here instead of once per pedestrian.
      local travel = car.speed >= 0 and car.angle or car.angle + math.pi
      e.travel = travel
      e.cos, e.sin = math.cos(-travel), math.sin(-travel)
      e.reach = 70 + e.fast * 1.1 -- how far ahead of itself a car is scary
    end
  end
  return cars, n
end

function Crowd:spawn(x, y)
  local id = self.nextId
  self.nextId = id + 1
  local p = { id = id, x = x, y = y, flee = 0, react = 0, timer = random() * 2, speed = Crowd.WALK_SPEED, frozen = 0 }
  setHeading(p, random() * 2 * math.pi)
  self.n = self.n + 1
  self.peds[self.n] = p
  return p
end

--- Everyone off the street at once (a map with no crowd).
function Crowd:clear()
  for i = self.n, 1, -1 do
    self.peds[i] = nil
  end
  self.n = 0
end

function Crowd:remove(i)
  local n = self.n
  self.peds[i] = self.peds[n]
  self.peds[n] = nil
  self.n = n - 1
end

--- Recycle pedestrians nobody can see and top the crowd back up. Runs four
--- times a second, not every tick.
function Crowd:maintain(cars, ncars)
  if ncars == 0 then
    return
  end

  local i = 1
  while i <= self.n do
    if self.peds[i].near2 > DESPAWN2 then
      self:remove(i)
    else
      i = i + 1
    end
  end

  local target = math.min(Crowd.MAX, Crowd.PER_CAR * ncars)
  local budget = Crowd.SPAWN_BURST
  while self.n < target and budget > 0 do
    budget = budget - 1
    local e = cars[random(ncars)]
    local a = random() * 2 * math.pi
    local r = Crowd.SPAWN_MIN + random() * (Crowd.SPAWN_MAX - Crowd.SPAWN_MIN)
    local p = self:spawn(e.x + math.cos(a) * r, e.y + math.sin(a) * r)
    p.near2 = r * r
  end
end

--- One pedestrian's tick. Returns the car that ran it over, if any.
function Crowd:think(p, dt, cars, ncars)
  local near2, hitBy = math.huge, nil
  local dodge, awayX, awayY

  for i = 1, ncars do
    local e = cars[i]
    local dx, dy = p.x - e.x, p.y - e.y
    local d2 = dx * dx + dy * dy
    if d2 < near2 then
      near2 = d2
    end
    if d2 < TOUCH2 then
      if Car.hitTest(e.car, p.x, p.y, Crowd.RADIUS) then
        hitBy, awayX, awayY = e, dx, dy
      end
    elseif d2 < DANGER2 and e.fast > 60 then
      -- Put the pedestrian in the car's frame: lx runs along the bonnet,
      -- ly across it. Inside the corridor ahead means "about to be flattened".
      local lx = dx * e.cos - dy * e.sin
      local ly = dx * e.sin + dy * e.cos
      if lx > 0 and lx < e.reach and (ly < Crowd.DANGER_WIDTH and ly > -Crowd.DANGER_WIDTH) then
        local side = p.dodge
        if p.flee <= 0 or not side then
          side = ly >= 0 and 1 or -1 -- break for the kerb you are nearest to
        end
        dodge = e.travel + side * math.pi / 2
        p.dodge = side
      end
    end
  end
  p.near2 = near2

  if p.frozen > 0 then
    p.frozen = p.frozen - dt -- rooted to the spot: no bolting, no wandering
  elseif dodge then
    if p.flee <= 0 then
      -- Caught in the headlights: a beat of hesitation before bolting, which
      -- is what makes a late swerve lethal and a long straight line survivable.
      p.react = Crowd.REACT_MIN + random() * (Crowd.REACT_MAX - Crowd.REACT_MIN)
    end
    p.flee = Crowd.FLEE_TIME
    setHeading(p, dodge)
  elseif p.flee > 0 then
    p.flee = p.flee - dt
    if p.flee <= 0 then
      p.timer, p.dodge, p.react = 0, nil, 0 -- catch your breath, then wander on
    end
  else
    p.timer = p.timer - dt
    if p.timer <= 0 then
      p.timer = 1 + random() * 2.5
      if random() < 0.25 then
        p.speed = 0 -- stop and stare at something
      else
        p.speed = Crowd.WALK_SPEED * (0.7 + random() * 0.6)
        setHeading(p, p.heading + (random() - 0.5) * 2.5)
      end
    end
  end

  local speed
  if p.frozen > 0 then
    speed = 0
  elseif p.react > 0 then
    p.react = p.react - dt
    speed = 0
  elseif p.flee > 0 then
    speed = Crowd.FLEE_SPEED
  else
    speed = p.speed
  end
  if speed > 0 then
    p.x = p.x + p.hx * speed * dt
    p.y = p.y + p.hy * speed * dt
  end

  if hitBy and p.frozen > 0 and hitBy.fast < Crowd.SPLAT_SPEED then
    return nil -- frozen solid: a slow car neither shifts nor scares them
  end
  if hitBy and hitBy.fast < Crowd.SPLAT_SPEED then
    -- Nudged rather than run over: shove them off the bonnet and let them
    -- scramble away instead of riding along with the car.
    local away = math.atan2(awayY, awayX)
    local push = (Crowd.WALK_SPEED + hitBy.fast) * dt * 2
    p.x = p.x + math.cos(away) * push
    p.y = p.y + math.sin(away) * push
    p.flee = Crowd.FLEE_TIME
    setHeading(p, away)
    return nil
  end
  return hitBy
end

--- Root everyone within `radius` of (x, y) to the spot for `seconds`.
function Crowd:freeze(x, y, radius, seconds)
  local r2 = (radius + Crowd.RADIUS) ^ 2
  for i = 1, self.n do
    local p = self.peds[i]
    local dx, dy = p.x - x, p.y - y
    if dx * dx + dy * dy <= r2 then
      p.frozen = math.max(p.frozen, seconds)
    end
  end
end

--- The first pedestrian standing within `radius` of (x, y), taken out of the
--- crowd. Used for anything that kills one without a bumper (a bullet); the
--- caller announces the death. Returns nil if nobody was there.
function Crowd:take(x, y, radius)
  local r2 = (radius + Crowd.RADIUS) ^ 2
  for i = 1, self.n do
    local p = self.peds[i]
    local dx, dy = p.x - x, p.y - y
    if dx * dx + dy * dy < r2 then
      self:remove(i)
      return p
    end
  end
  return nil
end

--- Advance the whole crowd. Returns the (reused) list of this tick's kills.
function Crowd:update(server, dt)
  local cars, ncars = self:collect(server)
  local kills = self.kills
  for i = #kills, 1, -1 do
    kills[i] = nil
  end

  local i = 1
  while i <= self.n do
    local p = self.peds[i]
    local hitBy = self:think(p, dt, cars, ncars)
    if hitBy then
      kills[#kills + 1] = { id = p.id, x = p.x, y = p.y, angle = hitBy.travel, by = hitBy.id }
      self:remove(i)
    else
      i = i + 1
    end
  end

  self.maintainTimer = self.maintainTimer - dt
  if self.maintainTimer <= 0 then
    self.maintainTimer = Crowd.MAINTAIN_EVERY
    self:maintain(cars, ncars)
  end
  return kills
end

return Crowd
