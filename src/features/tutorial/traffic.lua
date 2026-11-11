-- Level 1's traffic (docs/tutorial.md, "Level 1: Cross the road"): cars
-- in straight lines along every lane of Shoeman's Road, both ways on every
-- street, each coming out of the tunnel at one edge and gone into the
-- tunnel at the other. Host only: the cars are ordinary vehicles in
-- `server.vehicles` (plain boxes, nobody's, nobody driving), so every
-- client draws them like any other car.
--
-- The lanes are the map's (`map.lanes`, city-map/tutorial_maps.lua). Each
-- has its own speed and its own gap between cars (`Traffic.STREETS`): the
-- bottom street is the slowest, the top the fastest, and the lane by the
-- centre line runs faster than the one by the kerb.
--
-- Every step a car is put back on its lane at its lane's speed: nothing
-- slows it, turns it or pushes it aside (the core's friction, a collision,
-- a freeze). Shot to a wreck it is simply gone (`claim`, from the
-- tutorial's `serverWreckClaimed`): the next car comes along anyway.
--
--   Traffic.serverStep(server, map)  run the lanes while `map` has some, clear them when nil
--   Traffic.serverClear(server)      every traffic car out of the world
--   Traffic.claim(car)               true for a traffic car (it goes next step)
--   Traffic.cars()                   car -> its lane, for the contact check (box 3)

local Traffic = {}

-- Per street (1 the bottom, 4 the top) and lane (1 by the centre line, 2
-- by the kerb): `speed` px/s, and the gap from one car's nose to the next
-- one's, px, picked at random between `gap[1]` and `gap[2]` for each car.
-- Walking is 45 px/s and a sprint 170 (on-foot), a street 256 px across:
-- walked, a street is death; sprinted, about 1.5 s, so the gaps leave
-- about that much on the slow streets and less on the fast ones.
Traffic.STREETS = {
  { { speed = 210, gap = { 340, 700 } }, { speed = 170, gap = { 300, 620 } } },
  { { speed = 290, gap = { 460, 900 } }, { speed = 240, gap = { 400, 800 } } },
  { { speed = 370, gap = { 600, 1150 } }, { speed = 310, gap = { 520, 1000 } } },
  { { speed = 450, gap = { 760, 1400 } }, { speed = 390, gap = { 660, 1250 } } },
}

local lanes = nil -- on the host: { { lane, tune, cars = { car, ... } oldest first, wait = px to the next } ... }
local owned = {} -- car -> its lane entry, every traffic car in the world

--- The speed and gap of `lane` (a `map.lanes` entry).
function Traffic.tune(lane)
  local street = Traffic.STREETS[lane.street] or Traffic.STREETS[#Traffic.STREETS]
  return street[lane.lane] or street[#street]
end

local function gap(tune)
  return tune.gap[1] + love.math.random() * (tune.gap[2] - tune.gap[1])
end

--- A new car on `entry`'s lane at x, already at speed.
local function spawn(server, entry, x)
  local lane = entry.lane
  local car = server:spawnVehicle(x, lane.y, lane.angle)
  car.traffic = true
  car:setSpeed(entry.tune.speed)
  entry.cars[#entry.cars + 1] = car
  owned[car] = entry
  return car
end

local function remove(server, car)
  owned[car] = nil
  server:removeVehicle(car)
end

--- Every traffic car out of the world; the lanes are forgotten.
function Traffic.serverClear(server)
  for car in pairs(owned) do
    remove(server, car)
  end
  owned, lanes = {}, nil
end

--- The lanes of `map`, already full of cars from end to end at their
--- gaps, so nobody arrives to an empty road.
local function start(server, map)
  lanes = {}
  for _, lane in ipairs(map.lanes) do
    local entry = { lane = lane, tune = Traffic.tune(lane), cars = {} }
    -- From the far tunnel back towards the near one: the oldest car first.
    local x = lane.toX - lane.dir * love.math.random() * entry.tune.gap[1]
    local g = gap(entry.tune)
    while (x - lane.fromX) * lane.dir >= 0 do
      spawn(server, entry, x)
      g = gap(entry.tune)
      x = x - lane.dir * g
    end
    -- The next car (the one that would stand at x) comes out of the tunnel
    -- once the last is its gap ahead of the tunnel.
    entry.wait = g
    lanes[#lanes + 1] = entry
  end
end

--- One lane's step: every car back on its line at its speed, the ones
--- through the far tunnel (or wrecked, or gone) taken out, a new one out
--- of the near tunnel when the last is a gap ahead.
local function drive(server, entry)
  local lane, speed = entry.lane, entry.tune.speed
  local kept = {}
  for _, car in ipairs(entry.cars) do
    if server.vehicles[car.id] ~= car or car.gone or (car.x - lane.toX) * lane.dir >= 0 then
      remove(server, car)
    else
      car.y, car.angle = lane.y, lane.angle
      car:setSpeed(speed)
      kept[#kept + 1] = car
    end
  end
  entry.cars = kept
  local last = kept[#kept]
  local travelled = last and (last.x - lane.fromX) * lane.dir or math.huge
  if travelled >= entry.wait then
    spawn(server, entry, lane.fromX)
    entry.wait = gap(entry.tune)
  end
end

--- Run the traffic while `map` (the road, during level 1) is given; with
--- nil every car goes.
function Traffic.serverStep(server, map)
  if not (map and map.lanes) then
    if lanes then
      Traffic.serverClear(server)
    end
    return
  end
  if not lanes then
    start(server, map)
  end
  for _, entry in ipairs(lanes) do
    drive(server, entry)
  end
end

--- A traffic car wrecked: it is gone at the next step instead of coming
--- back where it died. True for one of ours.
function Traffic.claim(car)
  if owned[car] then
    car.gone = true
    return true
  end
  return false
end

--- Every traffic car in the world: car -> its lane entry ({ lane, tune }).
function Traffic.cars()
  return owned
end

return Traffic
