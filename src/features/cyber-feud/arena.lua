-- Grey City's factions in the Colosseum (colosseum/waves.lua): a bare level
-- of troops.lua's on its sand (`Troops.levels.colosseum`: no posts, no
-- beats, the two sides at war and awake), and packs that come in at the far
-- end, go for the nearest player and then walk a beat round the sand. The
-- Static's are gangers with a ripper in three and a sparker (two from nine);
-- Halcyon's are officers with an enforcer in four and a watcher drone from
-- six. An enforcer holds a post, so his is out towards the middle of the
-- sand, between the gate and where they came in: get round his shield there.
-- A "feud" wave is both, the Static left of the middle and Halcyon right of
-- it, at each other as much as at you. init.lua passes the waves' calls on.

local Features = require("src.features")
local Troops = require("src.features.cyber-feud.troops")
local Enforcers = require("src.features.cyber-feud.enforcers")
local Rippers = require("src.features.cyber-feud.rippers")
local Sparkers = require("src.features.cyber-feud.sparkers")
local Watchers = require("src.features.cyber-feud.watchers")

local Arena = {}

--- The sand on the map in play, if it is the Colosseum's.
local function sand()
  local city = Features.byName["city-map"]
  return city and city.map and city.map.oval
end

--- The bare level, if none runs yet. True once one does.
local function level(server)
  if Troops.server() then
    return true
  end
  local city = Features.byName["city-map"]
  local bare = setmetatable({
    troops = { halcyon = {}, static = {} }, enforcers = {}, rippers = {}, sparkers = {}, watchers = {}, brutes = {},
  }, { __index = city.map })
  Troops.serverStart(server, bare, "colosseum", false)
  local sv = Troops.server()
  if sv then
    sv.awake = true
  end
  return sv ~= nil
end

--- A loop round the sand `oval` at `k` of its radii.
local function ring(oval, k)
  local route = {}
  for i = 0, 7 do
    local a = i / 8 * 2 * math.pi
    route[#route + 1] = { x = oval.x + math.cos(a) * oval.rx * k, y = oval.y + math.sin(a) * oval.ry * k }
  end
  return route
end

--- What comes in with faction `faction`'s rank and file, `n` in all: makers of one special each.
local function specials(faction, n, beat, oval, target)
  local list = {}
  if faction == "static" then
    for _ = 1, math.floor(n / 3) do
      list[#list + 1] = function(x, y)
        return Rippers.serverJoin(x, y, beat, 1)
      end
    end
    for _ = 1, n >= 9 and 2 or 1 do
      list[#list + 1] = function(x, y)
        return Sparkers.serverJoin(x, y, beat, 1)
      end
    end
  else
    for _ = 1, math.max(1, math.floor(n / 4)) do
      list[#list + 1] = function(x, y)
        local px, py = Troops.clearSpot(oval.x + (x - oval.x) * 0.4, oval.y + (y - oval.y) * 0.4)
        return Enforcers.serverJoin(px, py, math.atan2(target.y - py, target.x - px))
      end
    end
    if n >= 6 then
      list[#list + 1] = function(x, y)
        return Watchers.serverJoin(x, y, beat, 1)
      end
    end
  end
  while #list >= n do
    list[#list] = nil -- a small share is mostly the rank and file
  end
  return list
end

--- The Colosseum's waves: `count` of `kind` ("static", "halcyon", or
--- "feud": the Static left of the middle, Halcyon right of it) come in round
--- (x, y). Returns how many came.
function Arena.serverSend(server, kind, count, x, y)
  local oval = sand()
  if not (oval and level(server)) then
    return 0
  end
  local faction = kind
  if kind == "feud" then
    faction = x < oval.x and "static" or "halcyon"
  end
  if faction ~= "static" and faction ~= "halcyon" then
    return 0
  end
  local beat = ring(oval, 0.55)
  local target = Troops.nearestPlayer(server, x, y, 1e6) or { x = oval.x, y = oval.y }
  local extras = specials(faction, count, beat, oval, target)
  local came = 0
  for i, make in ipairs(extras) do
    local a = i / #extras * 2 * math.pi
    local sx, sy = Troops.clearSpot(x + math.cos(a) * 70, y + math.sin(a) * 70)
    if make(sx, sy) then
      came = came + 1
    end
  end
  local pack = Troops.serverPack(server, faction, { x = x, y = y }, beat, count - #extras, false, target.x, target.y)
  return came + #pack
end

--- How many of the level's are still up: everything troops.lua lists for the audit.
function Arena.serverLeft(server)
  local n = 0
  Troops.serverEnemies(server, function()
    n = n + 1
  end)
  return n
end

return Arena
