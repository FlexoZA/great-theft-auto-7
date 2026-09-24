-- Every vehicle model in the game, read from the models folder at startup.
--
-- Drop `<type>-<colour>.svg` into src/features/vehicles/models/ and it is a
-- model: the vehicle factory can make it and it drives with its type's
-- stats. Every colour of a type shares `<type>.lua` next to it, so a new
-- colour is only a new SVG ("hatchback-blue.svg" drives like
-- "hatchback.lua" says, and is sold as the "Blue Hatchback"). A
-- `<type>-<colour>.lua` changes just that one colour; anything left out is
-- the starter car's. The SVG is a top-down view with the nose pointing
-- right (set `facing` otherwise); it is drawn `length` px long.
--
--   return {
--     name = "Hatchback",   -- shown in the shop, after the colour (default: from the file name)
--     price = 120,          -- Fcks at a vehicle factory; its owner can change it
--     hitpoints = 100,      -- how much damage it takes before it blows up
--     topSpeed = 520,       -- px/s
--     acceleration = 430,   -- px/s^2
--     weight = 900,         -- kg; heavier stops later and slides further
--     turning = 2.8,        -- rad/s at full speed
--     facing = "right",     -- where the nose points in the SVG: right, left, up, down
--     length = 44,          -- px the drawing is from nose to tail, mirrors and all
--     time = 45,            -- seconds the vehicle factory takes to make one
--     inputs = { iron = 4, oil = 2 }, -- what one uses up (default: the factory's own, buildings/kinds.lua)
--   }
--
-- Parsing is plain Lua, so the host knows every model without drawing one;
-- the pictures are painted the first time they are needed.

local Svg = require("src.features.vehicles.svg")

local Catalog = {
  list = {}, -- models, cheapest first
  byKey = {},
}

Catalog.DIR = "src/features/vehicles/models"
Catalog.ITEM_PREFIX = "car-" -- a model as a building product: "car-hatchback-orange"
Catalog.RESOLUTION = 512 -- px along the longer side of each painted picture

-- The starter car (src/car.lua), which every stat is measured against.
Catalog.BASE = {
  hitpoints = 100,
  topSpeed = 500,
  acceleration = 400,
  weight = 1000,
  turning = 2.6,
  brake = 700,
  friction = 250,
  handbrakeDecel = 320,
  driftGrip = 1.1,
}

local DEFAULTS = {
  price = 100,
  hitpoints = Catalog.BASE.hitpoints,
  topSpeed = Catalog.BASE.topSpeed,
  acceleration = Catalog.BASE.acceleration,
  weight = Catalog.BASE.weight,
  turning = Catalog.BASE.turning,
  facing = "right",
  length = 44,
}

local FACING = { right = 0, down = -math.pi / 2, left = math.pi, up = math.pi / 2 }

-- Colours whose file name doesn't read well as it is.
local COLOURS = { bluegrey = "Blue-grey" }

--- "hatchback-orange" -> "Hatchback Orange"
local function titleOf(key)
  return (key:gsub("[-_]+", " "):gsub("(%a)(%w*)", function(a, b)
    return a:upper() .. b
  end))
end

--- The table `<name>.lua` in the models folder returns, or nil without one.
local function loadStats(name)
  local path = Catalog.DIR .. "/" .. name .. ".lua"
  if not love.filesystem.getInfo(path, "file") then
    return nil
  end
  local chunk, err = love.filesystem.load(path)
  if not chunk then
    error(("vehicle model '%s': %s"):format(name, err))
  end
  local stats = chunk()
  if type(stats) ~= "table" then
    error(("vehicle model '%s': %s must return a table"):format(name, path))
  end
  return stats
end

--- Build the model for `key` out of the defaults, its type's stats and its
--- own, each over the one before.
local function makeModel(key, doc)
  local model = { key = key, doc = doc }
  for k, v in pairs(DEFAULTS) do
    model[k] = v
  end
  local typeKey, colour = key:match("^(.+)%-([^-]+)$")
  local typeStats = typeKey and loadStats(typeKey)
  local own = loadStats(key) or {}
  if typeStats then
    model.type, model.colour = typeKey, COLOURS[colour] or titleOf(colour)
    for k, v in pairs(typeStats) do
      model[k] = v
    end
    model.name = model.colour .. " " .. (typeStats.name or titleOf(typeKey))
  end
  for k, v in pairs(own) do
    model[k] = v
  end
  model.name = own.name or model.name or titleOf(key)
  model.item = Catalog.ITEM_PREFIX .. key
  return model
end

--- Read the models folder. Runs once, when this file is first required.
function Catalog.scan()
  Catalog.list, Catalog.byKey = {}, {}
  local items = love.filesystem.getDirectoryItems(Catalog.DIR)
  table.sort(items)
  for _, file in ipairs(items) do
    local key = file:match("^(.+)%.[sS][vV][gG]$")
    if key then
      local doc, err = Svg.parse(love.filesystem.read(Catalog.DIR .. "/" .. file))
      if doc then
        local model = makeModel(key, doc)
        Catalog.list[#Catalog.list + 1] = model
        Catalog.byKey[key] = model
      else
        print(("vehicles: skipping %s (%s)"):format(file, err))
      end
    end
  end
  table.sort(Catalog.list, function(a, b)
    if a.price ~= b.price then
      return a.price < b.price
    end
    return a.name < b.name
  end)
end

--- The model a building product stands for ("car-hatchback-orange"), or nil.
function Catalog.fromItem(item)
  local key = type(item) == "string" and item:match("^" .. Catalog.ITEM_PREFIX:gsub("%-", "%%-") .. "(.+)$")
  return key and Catalog.byKey[key]
end

--- Tune a server car (src/car.lua) to drive like `model`. Weight scales
--- the brakes, rolling friction and handbrake the other way round, and how
--- long a slide keeps its sideways speed.
function Catalog.apply(car, model)
  local B = Catalog.BASE
  local heavy = math.max(0.25, model.weight / B.weight)
  car.maxSpeed = model.topSpeed
  car.accel = model.acceleration
  car.turnRate = model.turning
  car.brake = B.brake / heavy
  car.friction = B.friction / heavy
  car.handbrakeDecel = B.handbrakeDecel / heavy
  car.driftGrip = B.driftGrip / heavy
end

--- The painted picture of `model`, made the first time it is asked for.
function Catalog.image(model)
  if not model.image then
    model.image = Svg.render(model.doc, Catalog.RESOLUTION)
  end
  return model.image
end

--- Draw `model` centred on (x, y), nose along `angle`, `length` px from
--- nose to tail (the model's own length by default). `alpha` fades it.
function Catalog.draw(model, x, y, angle, length, alpha)
  local img = Catalog.image(model)
  local turn = FACING[model.facing] or 0
  local long = (turn == 0 or turn == math.pi) and img:getWidth() or img:getHeight()
  local s = (length or model.length) / long
  alpha = alpha or 1
  love.graphics.push("all")
  love.graphics.setBlendMode("alpha", "premultiplied")
  love.graphics.setColor(alpha, alpha, alpha, alpha)
  love.graphics.draw(img, x, y, angle + turn, s, s, img:getWidth() / 2, img:getHeight() / 2)
  love.graphics.pop()
end

-- For the shop: each stat as a bar, how full against a generous ceiling.
Catalog.STAT_ROWS = {
  { key = "hitpoints", label = "Hitpoints", max = 250, show = "%d" },
  { key = "topSpeed", label = "Top speed", max = 900, show = "%d" },
  { key = "acceleration", label = "Acceleration", max = 900, show = "%d" },
  { key = "turning", label = "Turning", max = 4.5, show = "%.1f" },
  { key = "weight", label = "Weight", max = 3000, show = "%d kg" },
}

Catalog.scan()

return Catalog
