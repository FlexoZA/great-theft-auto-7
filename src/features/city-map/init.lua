-- City map: an urban grid of roads, buildings, parks and parking lots,
-- generated from a fixed seed so every machine has the same city. The
-- server keeps cars and pedestrians out of buildings and trees; clients
-- draw the city from a canvas built once.
--
-- The game knows several maps (`CityMap.maps`, all built by the same
-- generator from their own seed and size) and plays on one at a time,
-- `CityMap.current`. Every game starts on the default one; a feature may
-- move everyone to another mid-game with `city:switchTo(name, server)`
-- (quests does). The map table is replaced, so read `city.map` when you
-- need it rather than keeping it.
--
-- Conventions other features use:
--   server.spawnPoints  list of { x, y, angle } on the road (set in serverStart)
--   feature:blocksPoint(x, y)  true inside a solid; weapons stops bullets with it
--   feature:grow(bi, bj) / feature:growthSites()  add a block past the city
--     limits; real-estate sells them. `map.version` changes whenever the city
--     does, so anything drawn from it knows to redraw.
--   feature:switchTo(name, server)  play on another map. On the host pass the
--     server: every car is put on the new map's spawn points. Raises the
--     `mapChanged(map, server)` event for every feature (docs/features.md).
--
-- No network messages: the map is code, so nothing needs sending. A feature
-- that grows the city, or switches it, tells every machine to do the same in
-- the same order; the city goes back to its default map and size between
-- games.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local Collision = require("src.features.city-map.collision")
local Render = require("src.features.city-map.render")

local CityMap = {
  name = "city-map",
  priority = 20, -- draws over the grid (10), under pedestrians (60); collides before bots/weapons
}

-- Maps ------------------------------------------------------------------
-- Every map the game can play on, by name. Each is a spec for
-- Layout.generate plus a title for the HUD. Add one here and a quest (or
-- anything else) can send everyone there by name.
CityMap.maps = {
  city = { title = "The City", seed = Layout.SEED, cols = Layout.COLS, rows = Layout.ROWS, plots = Layout.PLOTS },
  -- Open ground out past the city: nothing built, nothing for sale, nobody
  -- about and no traffic, walls around it. Quests go here and come back.
  outskirts = {
    title = "The Outskirts", seed = 23, cols = 32, rows = 22, empty = true, crowd = false, traffic = false,
  },
  -- A suburban dead end where Crazy Karen lives: one street, a turning
  -- circle, houses on lawns. Nobody about but her, and you face her on
  -- foot: the cars stay parked on the verge by the entrance.
  culdesac = {
    title = "Karen's Cul-de-sac", kind = "culdesac", seed = 41, cols = 26, rows = 30,
    crowd = false, traffic = false, vehicles = false,
  },
}
CityMap.DEFAULT = "city" -- every game starts here

CityMap.map = nil
CityMap.current = nil -- name of the map in `map`
CityMap.canvas = nil
local drawnMap, drawnVersion = nil, nil -- the map and map.version the canvas shows

local function generate(name)
  local spec = CityMap.maps[name]
  local map = Layout.generate(spec)
  map.name, map.title = name, spec.title
  return map
end

function CityMap:load()
  self.map = generate(self.DEFAULT)
  self.current = self.DEFAULT
end

--- Back to the default city as generated, once it has grown or been
--- switched. The map table is replaced, so other features read `city.map`
--- when they need it rather than keeping it. No event: this runs between
--- games, when every feature resets itself anyway.
function CityMap:reset()
  if self.current ~= self.DEFAULT or #self.map.grown > 0 then
    self.map = generate(self.DEFAULT)
    self.current = self.DEFAULT
  end
end

--- Put every car on the map's spawn points, in player order, and publish
--- the list for anything else that spawns cars.
function CityMap:placeCars(server)
  server.spawnPoints = self.map.spawns
  local ids = {}
  for id, p in pairs(server.players) do
    if p.car then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for i, id in ipairs(ids) do
    local s = self.map.spawns[(i - 1) % #self.map.spawns + 1]
    local car = server.players[id].car
    car.x, car.y, car.angle = s.x, s.y, s.angle
    car:stop()
  end
end

--- Play on map `name` from now on. Returns true if the map changed, false
--- for an unknown name or the map already in play (so a host's own client,
--- which shares this table with its server, can hear the message and do
--- nothing). With `server` (the host), every car is moved to the new map's
--- spawn points before the `mapChanged` event goes out, so features that
--- remember where a car is (weapons' respawn slots) see the new spots.
function CityMap:switchTo(name, server)
  if not self.maps[name] or name == self.current then
    return false
  end
  self.map = generate(name)
  self.current = name
  if server then
    self:placeCars(server)
  end
  Features.call("mapChanged", self.map, server)
  return true
end

--- Add block (bi, bj) to the city as an empty plot ringed by streets.
--- Returns the new block, or nil if it can't go there. Calling it again for
--- a block that is already there is harmless, which matters on the host,
--- where the server and its own client share this map.
function CityMap:grow(bi, bj)
  return Layout.grow(self.map, bi, bj)
end

--- Blocks the city could grow into right now: { bi, bj, from } where
--- `from` is the neighbouring block it would grow from.
function CityMap:growthSites()
  return Layout.growthSites(self.map)
end

function CityMap:blocksPoint(x, y)
  return Collision.blocked(self.map, x, y)
end

-- Client ----------------------------------------------------------------

--- Draw the city into its canvas, again whenever it has changed.
function CityMap:redraw()
  if not love.graphics or (drawnMap == self.map and drawnVersion == self.map.version) then
    return
  end
  local started = love.timer.getTime()
  if self.canvas then
    self.canvas:release()
  end
  self.canvas = Render.build(self.map)
  drawnMap, drawnVersion = self.map, self.map.version
  print(("city-map: %d buildings, %d trees, %d blocks; canvas built in %.2fs"):format(
    #self.map.buildings, #self.map.trees, #self.map.blocks, love.timer.getTime() - started))
end

function CityMap:enterGame()
  self:redraw()
end

function CityMap:exitGame()
  self:reset()
end

-- Not in drawBelowCars: the camera transform is applied there.
function CityMap:update()
  self:redraw()
end

function CityMap:drawBelowCars()
  if self.canvas then
    Render.draw(self.map, self.canvas)
  end
end

-- Server ----------------------------------------------------------------

--- Every game starts on the default map with every car on its central road.
function CityMap:serverStart(server)
  self:reset()
  self:placeCars(server)
end

--- Keep pedestrians out of solids; bounce their heading off the wall.
local function collidePedestrians(map)
  local peds = Features.byName.pedestrians
  local crowd = peds and peds.crowd
  if not crowd then
    return
  end
  local r = 6
  for i = 1, crowd.n do
    local p = crowd.peds[i]
    local x, y, nx, ny = Collision.resolveCircle(map, p.x, p.y, r)
    if nx then
      p.x, p.y = x, y
      local len = math.sqrt(nx * nx + ny * ny)
      if len > 0 then
        nx, ny = nx / len, ny / len
        local dot = p.hx * nx + p.hy * ny
        if dot < 0 then
          p.hx, p.hy = p.hx - 2 * dot * nx, p.hy - 2 * dot * ny
          p.heading = math.atan2(p.hy, p.hx)
        end
      end
    end
  end
end

function CityMap:serverStep(server)
  for _, player in pairs(server.players) do
    local car = player.car
    if car and not car.hidden then
      Collision.resolveCar(self.map, car)
    end
  end
  collidePedestrians(self.map)
end

--- Centre of a random road tile (or any tile of an open field), optionally
--- within `maxDist` of (nearX, nearY). Other features reach this via
--- Features.byName["city-map"].
function CityMap:randomRoadPoint(nearX, nearY, maxDist)
  local map = self.map
  for _ = 1, 60 do
    local c = love.math.random(map.c0, map.c1)
    local r = love.math.random(map.r0, map.r1)
    local kind = map.tiles[c] and map.tiles[c][r]
    if kind == "road" or kind == "ground" then
      local x, y = map.x0 + (c + 0.5) * Layout.TILE, map.y0 + (r + 0.5) * Layout.TILE
      if not nearX or (x - nearX) ^ 2 + (y - nearY) ^ 2 <= maxDist * maxDist then
        return x, y
      end
    end
  end
  return nil
end

--- For tests and other features.
function CityMap.layout()
  return CityMap.map
end

return CityMap
