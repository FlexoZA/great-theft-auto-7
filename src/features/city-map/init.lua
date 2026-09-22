-- City map: an urban grid of roads, buildings, parks and parking lots,
-- generated from a fixed seed so every machine has the same city. The
-- server keeps cars and pedestrians out of buildings and trees; clients
-- draw the city from a canvas built once.
--
-- Conventions other features use:
--   server.spawnPoints  list of { x, y, angle } on the road (set in serverStart)
--   feature:blocksPoint(x, y)  true inside a solid; weapons stops bullets with it
--
-- No network messages: the map is code, so nothing needs sending.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local Collision = require("src.features.city-map.collision")
local Render = require("src.features.city-map.render")

local CityMap = {
  name = "city-map",
  priority = 20, -- draws over the grid (10), under pedestrians (60); collides before bots/weapons
}

CityMap.map = nil
CityMap.canvas = nil

function CityMap:load()
  self.map = Layout.generate(Layout.SEED)
end

function CityMap:blocksPoint(x, y)
  return Collision.blocked(self.map, x, y)
end

-- Client ----------------------------------------------------------------

function CityMap:enterGame()
  if not self.canvas and love.graphics then
    local started = love.timer.getTime()
    self.canvas = Render.build(self.map)
    print(("city-map: %d buildings, %d trees; canvas built in %.2fs"):format(
      #self.map.buildings, #self.map.trees, love.timer.getTime() - started))
  end
end

function CityMap:drawBelowCars()
  if self.canvas then
    Render.draw(self.map, self.canvas)
  end
end

-- Server ----------------------------------------------------------------

--- Put every car on the central road and publish the spawn list.
function CityMap:serverStart(server)
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
    car.x, car.y, car.angle, car.speed = s.x, s.y, s.angle, 0
  end
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

--- For tests and other features.
function CityMap.layout()
  return CityMap.map
end

return CityMap
