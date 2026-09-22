-- Pickups: items lying on the road that a car collects by driving over them.
-- The server owns them: it scatters them on road tiles (from the city map
-- when present), decides who takes one and respawns it elsewhere later.
-- Clients draw them and show a little "+50" when someone grabs one.
--
-- Kinds live in KINDS; "health" heals through the weapons feature.
--
-- Messages
--   server -> all  PK_SPAWN <id> <kind> <x> <y>
--   server -> all  PK_TAKE  <id> <playerId>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sounds = require("src.features.pickups.sounds")

local Pickups = {
  name = "pickups",
  priority = 70, -- draws under cars but over the map (20) and pedestrians (60)
}

-- Tuning ------------------------------------------------------------------
Pickups.count = 6 -- kits on the map at once
Pickups.respawnTime = 20 -- seconds after one is taken before a new one appears
Pickups.radius = 34 -- px from car centre that counts as driving over it
Pickups.healAmount = 50

local KINDS = {
  health = {
    --- Returns true if the player actually used it.
    apply = function(server, player)
      local weapons = Features.byName.weapons
      if weapons and weapons.serverHeal then
        return weapons:serverHeal(server, player, Pickups.healAmount)
      end
      return true -- no weapons feature: take it anyway
    end,
    label = "+" .. 50,
  },
}

-- Client state --------------------------------------------------------------
Pickups.items = {} -- id -> { kind, x, y }
Pickups.floats = {} -- { x, y, text, t }
local time = 0

function Pickups:load()
  Sounds.load()
end

-- PK_SPAWN for the whole set arrives in the same burst as START, just before
-- the game state is entered, so nothing is cleared on the way in.
function Pickups:enterGame()
  self.floats = {}
end

function Pickups:exitGame()
  self.items = {}
  self.floats = {}
end

function Pickups:update(dt)
  time = time + dt
  local i = 1
  while i <= #self.floats do
    local f = self.floats[i]
    f.t = f.t - dt
    f.y = f.y - 30 * dt
    if f.t <= 0 then
      table.remove(self.floats, i)
    else
      i = i + 1
    end
  end
end

--- A medkit: white box, red cross, dark outline, bobbing over a soft glow.
local function drawHealth(x, y, t)
  local bob = math.sin(t * 3) * 2
  local pulse = 0.5 + 0.5 * math.sin(t * 4)
  love.graphics.setColor(1, 0.3, 0.3, 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 26 + pulse * 4)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - 12, y - 6 + 6, 24, 20)
  y = y + bob
  love.graphics.setColor(0.10, 0.08, 0.08)
  love.graphics.rectangle("fill", x - 14, y - 12, 28, 24)
  love.graphics.setColor(0.95, 0.95, 0.92)
  love.graphics.rectangle("fill", x - 12, y - 10, 24, 20)
  love.graphics.setColor(0.85, 0.15, 0.15)
  love.graphics.rectangle("fill", x - 3, y - 8, 6, 16)
  love.graphics.rectangle("fill", x - 8, y - 3, 16, 6)
  love.graphics.setColor(0.10, 0.08, 0.08)
  love.graphics.rectangle("fill", x - 4, y - 14, 8, 3) -- handle
end

function Pickups:drawBelowCars()
  for _, it in pairs(self.items) do
    if it.kind == "health" then
      drawHealth(it.x, it.y, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Pickups:drawAboveCars()
  love.graphics.setFont(UI.fonts.body)
  for _, f in ipairs(self.floats) do
    love.graphics.setColor(0.4, 1, 0.4, math.min(1, f.t))
    love.graphics.printf(f.text, f.x - 60, f.y, 120, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Pickups.clientMessages = {
  PK_SPAWN = function(_client, args)
    local id, kind = tonumber(args[1]), args[2]
    local x, y = tonumber(args[3]), tonumber(args[4])
    if id and kind and x and y then
      Pickups.items[id] = { kind = kind, x = x, y = y }
    end
  end,
  PK_TAKE = function(client, args)
    local id, by = tonumber(args[1]), tonumber(args[2])
    local it = id and Pickups.items[id]
    if it then
      Pickups.items[id] = nil
      Sounds.play(it.x, it.y)
      local kind = KINDS[it.kind]
      local car = by and client.cars[by]
      Pickups.floats[#Pickups.floats + 1] = {
        x = car and car.dx or it.x,
        y = (car and car.dy or it.y) - 30,
        text = kind and kind.label or "",
        t = 1.2,
      }
    end
  end,
}

-- Server ----------------------------------------------------------------

local sv = nil -- { items = { id -> { kind, x, y } }, nextId, pending = { { at, kind } } , time }

--- A random spot on a road tile (city map) or in a ring around the origin.
local function roadSpot()
  local city = Features.byName["city-map"]
  if city and city.randomRoadPoint then
    local x, y = city:randomRoadPoint()
    if x then
      return x, y
    end
  end
  local a = love.math.random() * 2 * math.pi
  local d = 300 + love.math.random() * 700
  return math.cos(a) * d, math.sin(a) * d
end

local function farFromCars(server, x, y)
  for _, p in pairs(server.players) do
    if p.car and (p.car.x - x) ^ 2 + (p.car.y - y) ^ 2 < 200 ^ 2 then
      return false
    end
  end
  return true
end

local function spawnOne(server, kind)
  local x, y
  for _ = 1, 20 do
    x, y = roadSpot()
    if farFromCars(server, x, y) then
      break
    end
  end
  local id = sv.nextId
  sv.nextId = id + 1
  sv.items[id] = { kind = kind, x = x, y = y }
  server:broadcast(Protocol.encode("PK_SPAWN", id, kind, ("%.0f"):format(x), ("%.0f"):format(y)))
end

function Pickups:serverStart(server)
  sv = { items = {}, nextId = 1, pending = {}, time = 0 }
  for _ = 1, self.count do
    spawnOne(server, "health")
  end
end

function Pickups:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt

  local r2 = self.radius * self.radius
  for id, it in pairs(sv.items) do
    for _, player in pairs(server.players) do
      local car = player.car
      if car and not car.hidden and (car.x - it.x) ^ 2 + (car.y - it.y) ^ 2 < r2 then
        local kind = KINDS[it.kind]
        if kind.apply(server, player) then
          sv.items[id] = nil
          server:broadcast(Protocol.encode("PK_TAKE", id, player.id))
          sv.pending[#sv.pending + 1] = { at = sv.time + self.respawnTime, kind = it.kind }
          break
        end
      end
    end
  end

  local i = 1
  while i <= #sv.pending do
    if sv.time >= sv.pending[i].at then
      spawnOne(server, table.remove(sv.pending, i).kind)
    else
      i = i + 1
    end
  end
end

--- For tests.
function Pickups.server()
  return sv
end

return Pickups
