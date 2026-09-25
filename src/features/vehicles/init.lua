-- Vehicles: cars built from a model of their own, drawn from an SVG and
-- driving with that model's stats (catalog.lua; drop an SVG into models/
-- and it is in the game).
--
-- The vehicle factory (buildings) makes them. When one is collected or
-- bought, buildings hands the product to `serverDeliver` and a new car
-- belonging to the buyer appears on the road in front of the factory. The
-- starter cars stay the plain boxes in each player's colour.
--
-- A model car is an ordinary car in `server.vehicles`: the host tunes its
-- physics to the model, weapons gives it the model's hitpoints, and every
-- client is told which model it is so it can draw the picture instead of
-- the box (the `drawVehicle` hook).
--
-- Messages
--   server -> all  VH_MODEL <vid> <model key>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Catalog = require("src.features.vehicles.catalog")

local Vehicles = {
  name = "vehicles",
}

Vehicles.catalog = Catalog

-- Client --------------------------------------------------------------------

Vehicles.models = {} -- vehicle id -> model key, as the host told us

--- Paint every model now so the first one on screen doesn't stall a frame.
function Vehicles:load()
  for _, model in ipairs(Catalog.list) do
    Catalog.image(model)
  end
  if #Catalog.list > 0 then
    local names = {}
    for _, model in ipairs(Catalog.list) do
      names[#names + 1] = model.key
    end
    print("vehicles: " .. table.concat(names, ", "))
  end
end

-- VH_MODEL for cars bought before we joined arrives with the rest of the
-- burst, so the book is only cleared on the way out.
function Vehicles:exitGame()
  self.models = {}
end

--- The core asks before drawing each car: draw it as its model and answer
--- true, or leave it to the core's box.
function Vehicles:drawVehicle(_client, c)
  local model = Catalog.byKey[self.models[c.id] or ""]
  if not model then
    return false
  end
  Catalog.draw(model, c.dx, c.dy, c.dangle)
  return true
end

local CARD_TITLE, CARD_ROW = 22, 18

--- How tall the picture on a card `w` px wide is, and how long the car in it.
local function cardPicture(model, w)
  local img = Catalog.image(model)
  local length = math.min(w - 40, 220)
  return length * img:getHeight() / img:getWidth(), length
end

--- The height of the shop card for `item` at width `w`: 0 unless it is a car.
function Vehicles:cardHeight(item, w)
  local model = Catalog.fromItem(item)
  if not model then
    return 0
  end
  return cardPicture(model, w) + 24 + CARD_TITLE + #Catalog.STAT_ROWS * CARD_ROW + 6
end

--- A shop card for a building product that is a car: the picture over a bar
--- per stat, `w` px wide at (x, y), `cardHeight` tall. Buildings shows it in
--- the vehicle factory's menu, so a buyer sees the car before paying.
function Vehicles:drawCard(item, x, y, w)
  local model = Catalog.fromItem(item)
  if not model then
    return
  end
  local tall, length = cardPicture(model, w)
  love.graphics.setColor(1, 1, 1, 0.05)
  love.graphics.rectangle("fill", x + 10, y, w - 20, tall + 16, 6)
  Catalog.draw(model, x + w / 2, y + 8 + tall / 2, 0, length)

  local top = y + tall + 24
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf(model.name, x, top, w, "center")
  top = top + CARD_TITLE
  local labelW, valueW = 100, 60
  local barX = x + 20 + labelW
  local barW = w - 40 - labelW - valueW
  for _, row in ipairs(Catalog.STAT_ROWS) do
    local v = model[row.key]
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.print(row.label, x + 20, top)
    UI.meter(barX, top + 4, barW, 8, math.min(1, v / row.max), { 0.36, 0.62, 0.95 })
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf(row.show:format(v), barX + barW, top, valueW, "right")
    top = top + CARD_ROW
  end
  love.graphics.setColor(1, 1, 1)
end

Vehicles.clientMessages = {
  VH_MODEL = function(_client, args)
    local vid, key = tonumber(args[1]), args[2]
    if vid and key and Catalog.byKey[key] then
      Vehicles.models[vid] = key
    end
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { models = vehicle id -> model key }

function Vehicles:serverStart()
  sv = { models = {} }
end

--- Make `car` (already in `server.vehicles`) a `model`: its handling, its
--- hitpoints, and every client told which picture to draw.
local function makeModel(server, car, model)
  car.model = model.key
  Catalog.apply(car, model)
  sv = sv or { models = {} }
  sv.models[car.id] = model.key
  server:broadcast(Protocol.encode("VH_MODEL", car.id, model.key))
  local weapons = Features.byName.weapons
  if weapons and weapons.serverSetCarMaxHealth then
    weapons:serverSetCarMaxHealth(server, car, model.hitpoints)
  end
end

--- Put a new car of `model` (a catalog entry) into the world at (x, y),
--- belonging to player id `owner` (nil for nobody). Returns the car.
function Vehicles:serverSpawn(server, model, x, y, angle, owner)
  local car = server:spawnVehicle(x, y, angle, owner)
  makeModel(server, car, model)
  return car
end

--- Make `car` a model picked at random from the catalog (every car the
--- shop sells): bots give each civilian driver one. Returns the model.
function Vehicles:serverRandomModel(server, car)
  if #Catalog.list == 0 then
    return nil
  end
  local model = Catalog.list[love.math.random(#Catalog.list)]
  makeModel(server, car, model)
  return model
end

--- Buildings hands over a product nobody can carry: a car goes onto the
--- road at (x, y) as `player`'s. Answers true when `item` was a car.
function Vehicles:serverDeliver(server, player, item, x, y, angle)
  local model = Catalog.fromItem(item)
  if not model then
    return false
  end
  self:serverSpawn(server, model, x, y, angle or 0, player.id)
  return true
end

--- A player joining a running game hears the model of every car already out.
function Vehicles:serverPlayerJoined(server, player)
  if not (sv and server.started) or player.bot then
    return
  end
  for vid, key in pairs(sv.models) do
    if server.vehicles[vid] then
      server:send(player, Protocol.encode("VH_MODEL", vid, key))
    end
  end
end

--- Cars someone bought stay in the world when they leave, the way their own
--- car does; only the book of cars that are gone is tidied.
function Vehicles:serverPlayerLeft(server)
  if not sv then
    return
  end
  for vid in pairs(sv.models) do
    if not server.vehicles[vid] then
      sv.models[vid] = nil
    end
  end
end

-- Saved worlds --------------------------------------------------------------

local SAVE_VERSION = 1

--- The model of every car the core keeps (a remembered player's), by
--- vehicle id: { version = 1, models = { [vid] = model key } }.
function Vehicles:serverSaveWorld(server)
  local models = {}
  for vid, key in pairs(sv and sv.models or {}) do
    local car = server.vehicles[vid]
    if car and car.owner ~= nil and server.names[car.owner] ~= nil then
      models[vid] = key
    end
  end
  return { version = SAVE_VERSION, models = models }
end

--- The core has put the saved cars back under their old ids: each becomes
--- its model again, as when it was delivered. Models no longer in the
--- catalog and cars that did not come back are skipped.
function Vehicles:serverLoadWorld(server, data)
  if type(data) ~= "table" or type(data.models) ~= "table" or (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  for vid, key in pairs(data.models) do
    local car = server.vehicles[tonumber(vid)]
    local model = type(key) == "string" and Catalog.byKey[key]
    if car and model then
      makeModel(server, car, model)
    end
  end
end

return Vehicles
