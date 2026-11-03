-- Heck's horde in the Colosseum (colosseum/waves.lua): a bare horde on its
-- sand (horde.lua's, with no posts, mobs, vents or flocks of its own) and
-- waves called in at the far end, each one awake and on its way to the
-- nearest player (horde.lua's `serverCall`, as a boss's meeting calls them).
-- "possessed": staffers and guards, and the overtime guy with his chaingun
-- on the left. "imps": imps, and a third of them interns. "demons":
-- Cacodaemons (two a side from a share of six), a Dread Knight on the left
-- and a Mecha Zombie on the right (their own modules, each on a spot of the
-- sand), and the rest fodder. init.lua passes the waves' calls on.

local Features = require("src.features")
local Horde = require("src.features.eternal-mood.horde")
local DreadKnight = require("src.features.eternal-mood.dread_knight")
local Mecha = require("src.features.eternal-mood.mecha_zombie")

local Arena = {}

local nav = nil -- the bare horde's walking grid, while it runs

local random = love.math.random

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

--- The bare horde on the sand, if none runs yet. Its walking grid.
local function horde(server, map)
  if not Horde.server() then
    nav = Horde.serverStart(server, setmetatable({ horde = {} }, { __index = map }))
  end
  return nav
end

--- The nearest player to (x, y), as a point: where the wave makes for.
local function nearest(server, x, y)
  local best, bestD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = (px - x) ^ 2 + (py - y) ^ 2
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = { x = px, y = py }, d2
      end
    end
  end
  return best or { x = x, y = y }
end

--- Somewhere open within `r` of (x, y).
local function near(x, y, r)
  for _ = 1, 12 do
    local a, d = random() * 2 * math.pi, r * math.sqrt(random())
    local px, py = x + math.cos(a) * d, y + math.sin(a) * d
    if not Features.any("blocksPoint", px, py) then
      return px, py
    end
  end
  return x, y
end

--- The ranks of this side's share of a wave of `kind`, `n` of them (each
--- spot of the wave gets a share): the ones horde.lua calls in. The overtime
--- guy comes on the left; the demons' elite (one a side) is `elite`'s to bring.
local function ranks(kind, n, left)
  local list = {}
  if kind == "possessed" then
    if left and n >= 4 then
      list[#list + 1] = "overtime"
    end
    for k = #list + 1, n do
      list[k] = k % 2 == 0 and "guard" or "staffer"
    end
  elseif kind == "imps" then
    for k = 1, n do
      list[k] = k % 3 == 0 and "intern" or "imp"
    end
  elseif kind == "demons" then
    for _ = 1, n >= 6 and 2 or 1 do
      list[#list + 1] = "caco"
    end
    for k = #list + 1, n - 1 do -- (and the elite)
      list[k] = k % 2 == 0 and "intern" or "staffer"
    end
  end
  return list
end

--- A demons wave's elite on this side: the Dread Knight on the left, the
--- Mecha Zombie on the right, each on a spot of the sand.
local function elite(server, map, x, y, left)
  if left then
    DreadKnight.serverStart(server, { horde = { knights = {
      { x = x, y = y, facing = math.pi / 2, count = 1, wake = math.huge },
    } } }, nav)
    return DreadKnight.server() and 1 or 0
  end
  local o, route = map.oval, {}
  for i = 0, 7 do -- its loop round the sand
    local a = i / 8 * 2 * math.pi
    route[#route + 1] = { x = o.x + math.cos(a) * o.rx * 0.5, y = o.y + math.sin(a) * o.ry * 0.5 }
  end
  Mecha.serverStart(server, { horde = { mechas = { { route = route } } } }, nav)
  return Mecha.server() and 1 or 0
end

--- The Colosseum's waves: `count` of `kind` ("possessed", "imps" or
--- "demons") come in round (x, y). Returns how many came.
function Arena.serverSend(server, kind, count, x, y)
  local map = cityMap()
  if not (map and map.oval) or not (kind == "possessed" or kind == "imps" or kind == "demons") then
    return 0
  end
  horde(server, map)
  local left = x < map.oval.x
  local target = nearest(server, x, y)
  local came = 0
  for _, rank in ipairs(ranks(kind, count, left)) do
    local sx, sy = near(x, y, 160)
    Horde.serverCall(server, rank, sx, sy, target.x, target.y)
    came = came + 1
  end
  if kind == "demons" then
    came = came + elite(server, map, x, y, left)
  end
  return came
end

--- How many are still up: everything the feature lists for the audit.
function Arena.serverLeft(server, feature)
  local n = 0
  feature:serverEnemies(server, function()
    n = n + 1
  end)
  return n
end

return Arena
