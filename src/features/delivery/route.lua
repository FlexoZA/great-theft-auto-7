-- Finding the way to a building on the street grid. Bots' traffic
-- (bots/traffic.lua) drives a car along the streets by the rules and picks
-- a street at random at each crossing, unless the route already names the
-- next one (`ai.route.next`). A driver names it: the first turn of the
-- shortest way to the lane that runs past the building's square.
--
-- The way is found over streets travelled in one direction (a car can't
-- turn round in the middle of one), so a building behind the car means
-- going round the block. Host only.

local Traffic = require("src.features.bots.traffic")
local Layout = require("src.features.city-map.layout")

local Route = {}

local BOX = Layout.TILE -- half a crossing: no stopping inside one
local MARGIN = 30 -- px more a stop keeps clear of a crossing

--- The lane nearest (x, y): the street it is on as { from, to, dx, dy }
--- (driven from `from` to `to`, in its right-hand lane), `stop`, how far
--- along it from `from` the point beside (x, y) is, and that point (sx, sy).
--- Nil on a graph with no streets.
function Route.target(graph, x, y)
  local best
  for _, a in pairs(graph.nodes) do
    for _, e in ipairs(a.exits) do
      local b = e.node
      local len = math.abs(b.x - a.x) + math.abs(b.y - a.y) -- streets run along one axis
      local ox, oy = -e.dy * Traffic.lane, e.dx * Traffic.lane -- the lane, right of the centre line
      local lo, hi = BOX + MARGIN, len - BOX - MARGIN
      local s = (x - a.x - ox) * e.dx + (y - a.y - oy) * e.dy
      s = hi > lo and math.max(lo, math.min(hi, s)) or len / 2
      local sx, sy = a.x + ox + e.dx * s, a.y + oy + e.dy * s
      local d2 = (x - sx) ^ 2 + (y - sy) ^ 2
      if not best or d2 < best.d2 or (d2 == best.d2 and a.key .. b.key < best.from.key .. best.to.key) then
        best = { from = a, to = b, dx = e.dx, dy = e.dy, stop = s, sx = sx, sy = sy, d2 = d2 }
      end
    end
  end
  return best
end

--- How far along `route` (a traffic route: from, to) the car is.
function Route.along(route, car)
  local dx, dy = route.to.x - route.from.x, route.to.y - route.from.y
  local len = math.sqrt(dx * dx + dy * dy)
  return ((car.x - route.from.x) * dx + (car.y - route.from.y) * dy) / len
end

--- Is `route` the street `target` is on, in its direction?
function Route.on(route, target)
  return route.from == target.from and route.to == target.to
end

--- The ways out of the crossing `to` for a car coming from `from`: any but
--- straight back, unless it is a dead end.
local function onwards(from, to)
  local out = {}
  for _, e in ipairs(to.exits) do
    if e.node ~= from then
      out[#out + 1] = e
    end
  end
  return #out > 0 and out or to.exits
end

--- The exit to take at the crossing `route` is heading for, on the
--- shortest way onto `target`'s street: one of `route.to.exits`, or nil
--- when there is no way at all.
function Route.nextExit(route, target)
  local queue, head, seen = {}, 1, {}
  for _, e in ipairs(onwards(route.from, route.to)) do
    local k = route.to.key .. ">" .. e.node.key
    seen[k] = true
    queue[#queue + 1] = { from = route.to, to = e.node, first = e }
  end
  while head <= #queue do
    local s = queue[head]
    head = head + 1
    if s.from == target.from and s.to == target.to then
      return s.first
    end
    for _, e in ipairs(onwards(s.from, s.to)) do
      local k = s.to.key .. ">" .. e.node.key
      if not seen[k] then
        seen[k] = true
        queue[#queue + 1] = { from = s.to, to = e.node, first = s.first }
      end
    end
  end
  return nil
end

return Route
