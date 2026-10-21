-- The Runner's brain, on the host: where he runs each tick. His event
-- (runner.lua) owns what he smashes on the way, his health and the wire;
-- it hands him in as `r` and its own table (his numbers) as `R`.
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   run      flat out along the street grid (bots/traffic.lua's graph), in
--            one lane or the other, picking a street at every crossing and
--            never straight back unless it is a dead end
--   heal     badly hurt (bosses/heal.lua): he leaves the street for the
--            nearest medkit lying within `healRange`, round the blocks on
--            the walking grid (bosses/walk.lua), takes it, then makes for
--            the nearest crossing the same way and runs on from there
--
-- Frozen, he stands still; a stink ahead turns him round on his street.
-- Winded (bosses/stamina.lua), he walks whatever he is doing.

local Features = require("src.features")
local Traffic = require("src.features.bots.traffic")
local Heal = require("src.features.bosses.heal")
local Walk = require("src.features.bosses.walk")
local Nav = require("src.features.d-day.nav")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The street grid of the city in play, or nil.
function Brain.graph()
  local city = Features.byName["city-map"]
  return city and city.map and Traffic.graph(city.map) or nil
end

--- Where the street he is on ends for him: the far crossing, over in his lane.
local function waypoint(R, r)
  local e = r.street
  -- Right of the way he runs is (-dy, dx) with y pointing down.
  return r.to.x - e.dy * r.side * R.lane, r.to.y + e.dx * r.side * R.lane
end

--- A street out of crossing `node`: any but straight back where he came
--- from, unless it is a dead end. He takes it in a lane picked at random.
function Brain.pickStreet(r, node)
  local options = {}
  for _, e in ipairs(node.exits) do
    if not (r.street and e.dx == -r.street.dx and e.dy == -r.street.dy) then
      options[#options + 1] = e
    end
  end
  if #options == 0 then
    options = node.exits
  end
  local e = options[random(#options)]
  r.street, r.from, r.to = e, node, e.node
  r.side = random() < 0.5 and 1 or -1
end

--- Turn round on the street he is on: a stink ahead.
local function turnBack(r)
  for _, e in ipairs(r.to.exits) do
    if e.node == r.from then
      r.street, r.from, r.to = e, r.to, r.from
      return
    end
  end
end

--- Run `dist` px along his route, taking the next street at each crossing.
local function run(R, r, dist)
  for _ = 1, 8 do -- a few crossings at most in one tick
    local wx, wy = waypoint(R, r)
    local d = math.sqrt(dist2(wx, wy, r.x, r.y))
    if d > dist then
      r.x, r.y = r.x + (wx - r.x) / d * dist, r.y + (wy - r.y) / d * dist
      r.facing = math.atan2(wy - r.y, wx - r.x)
      return
    end
    r.x, r.y, dist = wx, wy, dist - d
    -- The graph is rebuilt when the city grows: carry on from the new one's crossing.
    local g = Brain.graph()
    local node = g and g.nodes[r.to.key] or r.to
    Brain.pickStreet(r, node)
  end
end

--- Where nothing of his can stand (the `blocksPoint` convention).
local function solid(x, y)
  return Features.any("blocksPoint", x, y)
end

local grid, gridVersion -- the city's walking grid, and the map.version it was built for

--- The walking grid (d-day/nav.lua) of the city in play as he fits through
--- it (bosses/walk.lua), built the first time he leaves the street (it takes
--- a moment) and again when the city has changed shape; nil without one.
function Brain.nav(R)
  local city = Features.byName["city-map"]
  local map = city and city.map
  if not map then
    return nil
  end
  if not grid or gridVersion ~= map.version then
    grid = Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
    gridVersion = map.version
  end
  return Walk.nav(grid, solid, R.radius)
end

--- Off the street: `dist` px towards (x, y), round the blocks on the walking
--- grid and feeling his way round corners (bosses/walk.lua); straight at it
--- when there is no way on the grid. True once he is there; `r.stuck`
--- counts the seconds he gets nowhere.
local function cut(R, r, x, y, dist, dt, time)
  local d = math.sqrt(dist2(x, y, r.x, r.y))
  if d <= dist then
    r.x, r.y, r.stuck, r.route = x, y, 0, nil
    return true
  end
  local way, there = Walk.route(r, Brain.nav(R), x, y, time)
  if there then
    return true
  end
  way = way or math.atan2(y - r.y, x - r.x)
  r.facing = way
  Walk.step(r, solid, way, dist / dt, dt, R.radius)
  return false
end

--- The crossing nearest to (x, y), to get back on his route from, other
--- than `skip` (one he couldn't get to).
local function nearestNode(x, y, skip)
  local g = Brain.graph()
  local best, bestD2
  for _, node in pairs(g and g.nodes or {}) do
    local d2 = dist2(node.x, node.y, x, y)
    if node ~= skip and #node.exits > 0 and (not bestD2 or d2 < bestD2) then
      best, bestD2 = node, d2
    end
  end
  return best
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(R, r, time)
  if r.medkit then
    if Heal.there(r.medkit) then
      return true
    end
    r.medkit = nil -- somebody got there first
  end
  if not Heal.wants(r.hp, r.max) or time < (r.healLook or 0) then
    return false
  end
  r.healLook = time + Heal.checkEvery
  r.medkit = Heal.find(r.x, r.y, R.healRange)
  return r.medkit ~= nil
end

--- His tick: how far he gets and which way. Returns whether he ran flat
--- out (it costs him breath).
function Brain.think(R, r, server, dt, time)
  if r.frozen > 0 then
    r.frozen = r.frozen - dt
    r.speed = 0
    return false
  end
  if r.panic then
    r.panic = nil
    if not r.backTo then
      turnBack(r)
    end
  end
  r.speed = r.breath:pace(R.speed, R.walkSpeed)
  local dist = r.speed * dt

  if wantsHeal(R, r, time) then
    r.mode, r.backTo = "heal", nil
    local m = r.medkit
    if cut(R, r, m.x, m.y, dist, dt, time) or Heal.within(m, r.x, r.y, R.radius) then
      r.hp = math.min(r.max, r.hp + Heal.take(server, m))
      r.medkit = nil
      r.backTo = nearestNode(r.x, r.y) -- back to his route from the nearest crossing
    elseif (r.stuck or 0) > 2 then
      -- Something he can't get round: not that one, and not for a while.
      r.medkit, r.healLook, r.stuck, r.route = nil, time + 8, 0, nil
      r.backTo = nearestNode(r.x, r.y)
    end
    return not r.breath:winded()
  end

  if r.backTo then
    -- Back to the street grid after a detour.
    r.mode = "back"
    if cut(R, r, r.backTo.x, r.backTo.y, dist, dt, time) then
      Brain.pickStreet(r, r.backTo)
      r.backTo = nil
    elseif (r.stuck or 0) > 2 then
      r.backTo, r.stuck, r.route = nearestNode(r.x, r.y, r.backTo), 0, nil -- that one is walled off: the next
    end
    return not r.breath:winded()
  end

  r.mode = "run"
  run(R, r, dist)
  return not r.breath:winded()
end

return Brain
