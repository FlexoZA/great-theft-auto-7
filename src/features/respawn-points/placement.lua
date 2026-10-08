-- Where a map's respawn points stand: { name, x, y, angle } in route order,
-- from the way in towards the boss.
--
-- A map that names its own (`map.respawnPoints`) gets those. A driven map
-- with car stations (the Winding Road) gets one on each pad, so whoever
-- comes back there can call a car straight away. Anything else is worked
-- out from the ground: a walk (breadth first, over GRID px squares that
-- nothing solid stands in) from the first spawn point to the boss
-- (`map.bossX, bossY`) or, without one, to the furthest place you can walk
-- to, with a point every `spacing` px along it, none too close to the
-- start or the end. A walk shorter than `shortest` gets none: Karen's
-- street, the forest and the beach are over before dying there costs much.
-- Every machine works it out from the same map, in the same order, so the
-- list is the same everywhere and needs no messages.

local Collision = require("src.features.city-map.collision")

local Placement = {}

Placement.GRID = 32 -- px per square of the walk
Placement.spacing = 1800 -- px of walk between two points, at least
Placement.shortest = 5000 -- px of walk a map needs before it gets any points
Placement.most = 6 -- points on even the longest walk (the gap grows instead)
Placement.startGap = 1200 -- no point nearer the way in than this, along the walk
Placement.endGap = 1200 -- nor nearer the boss (or the far end)
Placement.roomy = 3 -- squares either side a point looks for open ground in

local function offLimits(map, x, y)
  for _, o in ipairs(map.offLimits or {}) do
    if x >= o.x and x < o.x + o.w and y >= o.y and y < o.y + o.h then
      return true
    end
  end
  return false
end

--- Points from the ground (see the top of the file). Nil for a map too
--- short to want any.
local function walked(map)
  local G = Placement.GRID
  local cols, rows = math.floor(map.w / G), math.floor(map.h / G)
  local function centre(k)
    return map.left + (k % cols + 0.5) * G, map.top + (math.floor(k / cols) + 0.5) * G
  end
  local free = {}
  for k = 0, cols * rows - 1 do
    local x, y = centre(k)
    free[k] = not Collision.blocked(map, x, y) and not offLimits(map, x, y)
  end
  local function square(x, y)
    local i, j = math.floor((x - map.left) / G), math.floor((y - map.top) / G)
    if i < 0 or j < 0 or i >= cols or j >= rows then
      return nil
    end
    return j * cols + i
  end
  local s = map.spawns and map.spawns[1]
  local start = s and square(s.x, s.y)
  if not (start and free[start]) then
    return nil
  end
  local dist, prev, queue = { [start] = 0 }, {}, { start }
  local head = 1
  while head <= #queue do
    local k = queue[head]
    head = head + 1
    local i = k % cols
    local ns = { i > 0 and k - 1, i < cols - 1 and k + 1, k - cols, k + cols }
    for n = 1, 4 do
      local nk = ns[n]
      if nk and free[nk] and not dist[nk] then
        dist[nk], prev[nk] = dist[k] + 1, k
        queue[#queue + 1] = nk
      end
    end
  end
  -- The goal: the reachable square nearest the boss, or the last one the
  -- walk got to (the furthest).
  local goal = queue[#queue]
  if map.bossX then
    local best = math.huge
    for _, k in ipairs(queue) do
      local x, y = centre(k)
      local d = (x - map.bossX) ^ 2 + (y - map.bossY) ^ 2
      if d < best then
        goal, best = k, d
      end
    end
  end
  local path = {}
  local k = goal
  while k do
    table.insert(path, 1, k)
    k = prev[k]
  end
  local length = (#path - 1) * G
  if length < Placement.shortest then
    return nil
  end
  local gap = math.max(Placement.spacing, length / (Placement.most + 1))
  local points = {}
  local at = math.max(gap, Placement.startGap)
  while at <= length - Placement.endGap and #points < Placement.most do
    local n = math.floor(at / G) + 1
    -- The roomiest square near that spot on the walk, so nobody comes back
    -- with their nose against a wall.
    local pk, pi, pj = path[n], path[n] % cols, math.floor(path[n] / cols)
    local best, bestRoom = pk, -1
    local R = Placement.roomy
    for dj = -R, R do
      for di = -R, R do
        local ci, cj = pi + di, pj + dj
        local ck = cj * cols + ci
        if ci >= 0 and ci < cols and cj >= 0 and cj < rows and dist[ck] then
          local room = 0
          for ej = -2, 2 do
            for ei = -2, 2 do
              local ek = (cj + ej) * cols + ci + ei
              if ci + ei >= 0 and ci + ei < cols and free[ek] then
                room = room + 1
              end
            end
          end
          if room > bestRoom then
            best, bestRoom = ck, room
          end
        end
      end
    end
    local x, y = centre(best)
    local ax, ay = centre(path[math.max(1, n - 3)])
    local bx, by = centre(path[math.min(#path, n + 3)])
    points[#points + 1] = {
      name = "Checkpoint " .. (#points + 1), x = math.floor(x), y = math.floor(y), angle = math.atan2(by - ay, bx - ax),
    }
    at = at + gap
  end
  return points
end

--- The respawn points of `map`, in route order (possibly none). Never for
--- the default city (`isHome`): the garage looks after respawns there.
function Placement.of(map, isHome)
  if not map or isHome then
    return {}
  end
  if map.respawnPoints then
    return map.respawnPoints
  end
  if map.carStations and #map.carStations > 0 then
    local points = {}
    for _, st in ipairs(map.carStations) do
      points[#points + 1] = { name = "Car station by " .. st.name, x = st.x, y = st.y, angle = st.angle }
    end
    return points
  end
  return walked(map) or {}
end

return Placement
