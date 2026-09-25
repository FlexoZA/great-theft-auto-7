-- Traffic: how a peaceful NPC car drives through the city. The street grid
-- (city-map's layout: two-tile roads every PERIOD tiles) becomes a graph of
-- intersections joined by streets, and a car follows it in the right-hand
-- lane, picking a street at each crossing, at a sensible speed:
--
--   * keep right: the lane is `lane` px right of the street's centre line
--     (the map's spawn points sit in the same lanes);
--   * a speed limit, `speed` (what the brain asks for), and slower through
--     a turn (`turnSpeed`);
--   * keep your distance: brake for any car ahead in your path;
--   * wait at a crossing while another car is going across it;
--   * stop for anyone on foot in your path: pedestrians, officers, players,
--     and for one about to step into it; and go past anyone standing in
--     the road near your path at `cautionSpeed` (people bolt when a car
--     comes at them, and a slow car only bumps them);
--   * nobody waits for ever: stuck behind other cars for `creepAfter`
--     seconds (four cars nose to nose in a crossing), a car creeps on.
--
-- A reckless driver (bots picks one now and then) keeps to the streets but
-- breaks every rule on them: it speeds, takes turns fast, weaves, and
-- stops for nobody, car or person, and waits at no crossing. That is where
-- the accidents come from, and the police chases after them.
--
-- Only the host runs this. Fights, chases and panics don't: those brains
-- drive with Bots.driveTowards and are allowed to go wild. A car that comes
-- back from one (or is far from its lane for any reason) picks up the
-- nearest street again. A map without a street grid (open ground, the
-- cul-de-sac) has no graph, and bots falls back to its old waypoints.

local Layout = require("src.features.city-map.layout")
local Car = require("src.car")

local Traffic = {}

-- Tuning ------------------------------------------------------------------
Traffic.lane = 32 -- px right of the centre line: the middle of the right-hand lane
Traffic.turnSpeed = 90 -- px/s through a turn
Traffic.turnSlowdown = 190 -- px before a crossing a turning car starts slowing for it
Traffic.lookMin, Traffic.lookMax = 50, 130 -- px ahead along the lane the car steers at
Traffic.carGap = 26 -- px of bumper to bumper a car stops short of another
Traffic.walkerGap = 34 -- px short of someone on foot a car stops
Traffic.pathHalf = 20 -- px either side of the car's line that counts as in its path
Traffic.brakeRate = 1.6 -- px/s of speed allowed per px of room left before the stop point
Traffic.cautionSpeed = 80 -- px/s past anyone standing in the road near the car's path (under the 90 that runs one over)
Traffic.cautionHalf = 80 -- px either side of the car's line that counts as near it
Traffic.foresight = { 0, 0.4, 0.8, 1.2 } -- seconds ahead a walker's path is checked against the car's
Traffic.yieldWait = 3 -- seconds waiting at a crossing before going anyway (nobody sits forever)
Traffic.creepAfter = 4 -- seconds stopped behind other cars before creeping on (a gridlocked crossing unpicks itself)
Traffic.creepSpeed = 35 -- px/s a car creeps at then; people on foot still stop it dead
Traffic.recklessTurnSpeed = 170 -- px/s a reckless driver takes a turn at
Traffic.weave = 0.35 -- how hard a reckless driver weaves (steering, either way)
Traffic.offLane = 110 -- px from its lane: the car has lost the road and finds it again

local T, P = Layout.TILE, Layout.PERIOD
local BOX = T -- half the size of a crossing: the road is two tiles wide

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

-- The graph -----------------------------------------------------------------

local cache = { map = nil, version = nil, graph = nil }

local function isRoad(map, c, r)
  local col = map.tiles[c]
  return col ~= nil and col[r] == "road"
end

--- Intersections and the streets between them, for `map`: nodes keyed
--- "i,j" with x, y (the crossing's centre) and exits { dx, dy, node }.
--- Nil for a map that isn't a street grid.
local function build(map)
  if map.kind ~= "grid" or map.empty then
    return nil
  end
  local nodes, count = {}, 0
  local i0, i1 = math.floor(map.c0 / P), math.floor(map.c1 / P)
  local j0, j1 = math.floor(map.r0 / P), math.floor(map.r1 / P)
  for i = i0, i1 do
    for j = j0, j1 do
      local c, r = i * P, j * P
      if isRoad(map, c, r) and isRoad(map, c + 1, r + 1) then
        local key = i .. "," .. j
        nodes[key] = { key = key, i = i, j = j, x = map.x0 + (c + 1) * T, y = map.y0 + (r + 1) * T, exits = {} }
        count = count + 1
      end
    end
  end
  if count == 0 then
    return nil
  end
  -- A street joins two crossings when every tile between them is road.
  local function street(a, horizontal)
    for k = 2, P - 1 do
      local c = horizontal and a.i * P + k or a.i * P
      local r = horizontal and a.j * P or a.j * P + k
      if not (isRoad(map, c, r) and isRoad(map, c + (horizontal and 0 or 1), r + (horizontal and 1 or 0))) then
        return false
      end
    end
    return true
  end
  for _, a in pairs(nodes) do
    local east, south = nodes[(a.i + 1) .. "," .. a.j], nodes[a.i .. "," .. (a.j + 1)]
    if east and street(a, true) then
      a.exits[#a.exits + 1] = { dx = 1, dy = 0, node = east }
      east.exits[#east.exits + 1] = { dx = -1, dy = 0, node = a }
    end
    if south and street(a, false) then
      a.exits[#a.exits + 1] = { dx = 0, dy = 1, node = south }
      south.exits[#south.exits + 1] = { dx = 0, dy = -1, node = a }
    end
  end
  return { nodes = nodes, map = map }
end

--- The street graph of `map`, built once per map and again when it grows.
function Traffic.graph(map)
  if not map then
    return nil
  end
  if cache.map ~= map or cache.version ~= map.version then
    cache.map, cache.version, cache.graph = map, map.version, build(map)
  end
  return cache.graph
end

-- Following a street ----------------------------------------------------------

--- The street `ai.route` is on: from, to, the unit direction and its length.
local function geometry(route)
  local a, b = route.from, route.to
  local dx, dy = b.x - a.x, b.y - a.y
  local len = math.sqrt(dx * dx + dy * dy)
  return a, b, dx / len, dy / len, len
end

--- Where the car is against its route: along the street from `from`, and
--- how far off the lane (right of the centre line by Traffic.lane).
local function place(car, route)
  local a, _, ux, uy, len = geometry(route)
  local rx, ry = car.x - a.x, car.y - a.y
  local along = rx * ux + ry * uy
  local side = -rx * uy + ry * ux -- right of the line is positive (y points down)
  return along, side - Traffic.lane, len
end

--- The nearest street to the car, taken in the direction it is facing.
local function snap(graph, car)
  local best, bestD
  local hx, hy = math.cos(car.angle), math.sin(car.angle)
  for _, a in pairs(graph.nodes) do
    for _, e in ipairs(a.exits) do
      local b = e.node
      -- Distance from the car to the segment between the two crossings.
      local sx, sy = b.x - a.x, b.y - a.y
      local len2 = sx * sx + sy * sy
      local t = math.max(0, math.min(1, ((car.x - a.x) * sx + (car.y - a.y) * sy) / len2))
      local px, py = a.x + sx * t, a.y + sy * t
      local d = (car.x - px) ^ 2 + (car.y - py) ^ 2
      if not bestD or d < bestD - 1 or (math.abs(d - bestD) <= 1 and e.dx * hx + e.dy * hy > 0) then
        best, bestD = { from = a, to = b, dx = e.dx, dy = e.dy }, d
      end
    end
  end
  if not best then
    return nil
  end
  -- Drive it the way the car already points.
  if best.dx * hx + best.dy * hy < 0 then
    best.from, best.to, best.dx, best.dy = best.to, best.from, -best.dx, -best.dy
  end
  return best
end

--- A street out of the crossing the route is heading for: any but straight
--- back, unless it is a dead end.
local function pickNext(route)
  local options = {}
  for _, e in ipairs(route.to.exits) do
    if not (e.dx == -route.dx and e.dy == -route.dy) then
      options[#options + 1] = e
    end
  end
  if #options == 0 then
    options = route.to.exits
  end
  return options[love.math.random(#options)]
end

--- How fast the car may go with something `room` px ahead of the point it
--- has to stop at: slowing in a straight line down to nothing there.
local function stopping(room)
  return math.max(0, room) * Traffic.brakeRate
end

--- The nearest thing in the car's path, as the speed the car may do for
--- it: other cars (bumper to bumper), then anyone on foot (`walkers`, a
--- flat list of x, y, vx, vy each): where they are, and where they will be
--- over the next second if they keep walking, so one stepping off the kerb
--- is braked for before they are in front of the bumper.
local function clearance(map, car, vehicles, walkers, look, creeping)
  local hx, hy = math.cos(car.angle), math.sin(car.angle)
  local limit = math.huge
  for _, v in pairs(vehicles) do
    if v ~= car and not v.hidden and not v.stowed then
      local rx, ry = v.x - car.x, v.y - car.y
      local along = rx * hx + ry * hy
      if along > 0 and along < look then
        local across = math.abs(-rx * hy + ry * hx)
        if across < Traffic.pathHalf + Car.HEIGHT / 2 then
          limit = math.min(limit, stopping(along - Car.WIDTH - Traffic.carGap))
        end
      end
    end
  end
  if creeping then
    limit = math.max(limit, Traffic.creepSpeed)
  end
  for k = 1, #walkers - 3, 4 do
    local wx, wy, vx, vy = walkers[k], walkers[k + 1], walkers[k + 2], walkers[k + 3]
    local nx, ny = wx - car.x, wy - car.y
    local near = nx * hx + ny * hy
    if near > -Car.WIDTH / 2 and near < look and math.abs(-nx * hy + ny * hx) < Traffic.cautionHalf then
      if Layout.tileAt(map, wx, wy) == "road" then
        limit = math.min(limit, Traffic.cautionSpeed)
      end
    end
    for _, t in ipairs(Traffic.foresight) do
      local rx, ry = wx + vx * t - car.x, wy + vy * t - car.y
      local along = rx * hx + ry * hy
      if along > 0 and along < look and math.abs(-rx * hy + ry * hx) < Traffic.pathHalf then
        limit = math.min(limit, stopping(along - Car.WIDTH / 2 - Traffic.walkerGap))
        break
      end
    end
  end
  return limit
end

--- Is another car going across the crossing `node` (in its box, moving, not
--- travelling the same way as us)?
local function crossingBusy(node, car, vehicles)
  for _, v in pairs(vehicles) do
    if v ~= car and not v.hidden and not v.stowed and math.abs(v.x - node.x) < BOX and math.abs(v.y - node.y) < BOX then
      local same = math.abs(angleDiff(v.angle, car.angle)) < 0.6
      if not same and math.abs(v.speed or 0) > 15 then
        return true
      end
    end
  end
  return false
end

--- Drive `npc` one tick along the streets of `graph` at up to `speed`.
--- Sets its steering and returns the speed it should do right now; the
--- caller turns that into throttle. `vehicles` is every car in the world,
--- `walkers` everyone on foot (flat x, y, vx, vy list). `reckless`: the
--- street and nothing else (see the top of this file).
function Traffic.drive(npc, graph, speed, vehicles, walkers, dt, reckless)
  local map = graph.map
  local car, ai, input = npc.car, npc.ai, npc.input
  local route = ai.route
  if route then
    local _, off = place(car, route)
    if math.abs(off) > Traffic.offLane then
      route = nil -- knocked off the road, or back from a chase
    end
  end
  if not route then
    route = snap(graph, car)
    ai.route = route
    if not route then
      return 0
    end
    route.next = nil
    ai.waited = 0
  end

  local along, _, len = place(car, route)
  local rem = len - along -- to the centre of the crossing ahead
  route.next = route.next or pickNext(route)
  local turning = route.next and not (route.next.dx == route.dx and route.next.dy == route.dy)

  -- Into the crossing: the next street becomes the route. Turning, the car
  -- starts steering for the new lane a little before the middle.
  if route.next and rem < (turning and BOX * 0.9 or BOX * 0.5) then
    local n = route.next
    route = { from = route.to, to = n.node, dx = n.dx, dy = n.dy }
    ai.route, ai.waited = route, 0
    along, _, len = place(car, route)
    rem = len - along
    route.next = pickNext(route)
    turning = false
  end

  -- Steer at a point further along the lane, more of it the faster we go.
  local look = math.max(Traffic.lookMin, math.min(Traffic.lookMax, 40 + math.abs(car.speed) * 0.3))
  local a, _, ux, uy = geometry(route)
  local s = math.min(along + look, len + BOX) -- past the far crossing's middle there is no lane
  local tx = a.x + ux * s - uy * Traffic.lane
  local ty = a.y + uy * s + ux * Traffic.lane
  local err = angleDiff(math.atan2(ty - car.y, tx - car.x), car.angle)
  local weave = reckless and Traffic.weave * math.sin(love.timer.getTime() * 2.3 + npc.id) or 0
  input.steer = math.max(-1, math.min(1, err / 0.4 + weave))

  -- How fast: the limit, slower into a turn, then whatever is in the way.
  local want = speed
  if turning and rem < Traffic.turnSlowdown then
    want = math.min(want, (reckless and Traffic.recklessTurnSpeed or Traffic.turnSpeed) + stopping(rem - BOX))
  end
  if reckless then
    return want -- no looking out for anyone
  end
  if math.abs(err) > 0.7 then
    want = math.min(want, Traffic.turnSpeed) -- well off line (rejoining the road): take it easy
  end
  -- Wait short of a crossing someone else is going across.
  if rem > BOX and rem < BOX + 90 and crossingBusy(route.to, car, vehicles) and ai.waited < Traffic.yieldWait then
    ai.waited = ai.waited + dt
    want = math.min(want, stopping(rem - BOX - 8))
  end
  -- Held up by other cars for long enough: creep on through them.
  if math.abs(car.speed) > Traffic.creepSpeed + 10 then
    ai.heldFor = 0
  elseif want > Traffic.creepSpeed then
    ai.heldFor = (ai.heldFor or 0) + dt
  end
  local creeping = (ai.heldFor or 0) > Traffic.creepAfter
  return math.min(want, clearance(map, car, vehicles, walkers, 60 + math.abs(car.speed) * 0.9 + Car.WIDTH, creeping))
end

--- Throttle for holding `speed`: on under it, off near it, brakes above it,
--- and never into reverse (a stopped car waiting stays put).
function Traffic.throttleFor(car, speed)
  local v = car.speed
  if speed < 5 then
    return v > 5 and -1 or 0
  elseif v < speed - 8 then
    return 1
  elseif v > speed + 20 then
    return -1
  end
  return 0
end

return Traffic
