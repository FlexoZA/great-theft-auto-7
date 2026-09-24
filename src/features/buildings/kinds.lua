-- What can be built on a plot, and the things buildings make.
--
-- Items are what a player carries and a building stores, by key:
--   iron, sulfur, minerals,  raw materials, dug out of a quarry
--   copper
--   oil, plastic             pumped (and refined) by an oil well
--   ammo-<gun>               rounds for a gun in weapons/guns.lua ("ammo-uzi")
--   gun-<gun>                a gun ("gun-uzi")
--   medkit                   a health pack; the carrier can use it to heal
--   car-<model>              a car from vehicles/models ("car-hatchback-orange"). Nobody
--                            carries one: collecting or buying it puts it on the road
--                            (the `serverDeliver` event, answered by vehicles)
--
-- A player carries items in slots, SLOTS to start with (the upgrade shop
-- sells more, up to MAX_SLOTS). A slot holds one stack of one item, up to
-- that item's stack size; more of it spills into another slot.
--
-- Each kind of building:
--   cost      Fcks to build it on a plot you own
--   inputs    item -> how many one batch uses up (loaded into its hopper)
--   time      seconds per batch while it has its inputs and room
--   batch     how many it makes per batch
--   cap       most it holds before somebody collects or buys
--   unit      how many a customer buys at once
--   price     Fcks per unit a new building starts at; the owner changes it
--   products  the items it can make; the owner picks one
--   recipes   product -> overrides for making that one: any of inputs, time,
--             batch, cap, unit, price (the rocket launcher needs more than
--             iron). Kinds.recipe merges them over the kind's own.
--   private   true: never open to the public (the parking lot)
--   walkable  true: not solid, cars drive onto it (the parking lot)
--   hp        hit points; every gun hurts a building (a rocket's blast hurts
--             the parking lot too, bullets fly over it). At 0 it is a ruin
--             until its owner repairs it or someone takes the lot over.
-- The parking lot is the odd one out: it earns koins by the minute (`rate`)
-- and pays them to its owner when they drive over it.
--
-- A factory's hopper takes every material any of its products runs on
-- (`kind.hopper`, worked out below), so switching products never strands
-- what was loaded; a batch uses up only what the product in hand needs.

local Guns = require("src.features.weapons.guns")
local Catalog = require("src.features.vehicles.catalog")

local Kinds = {}

Kinds.materials = { "iron", "sulfur", "minerals", "copper", "oil", "plastic" }
Kinds.HOPPER = 20 -- most of each input a factory holds
Kinds.SLOTS = 4 -- inventory slots everyone starts with
Kinds.MAX_SLOTS = 9 -- with every slot upgrade bought
Kinds.REPAIR = 0.5 -- repairing a ruin costs this share of what the building cost; less damage, less

--- How many of `item` fit in one inventory slot.
function Kinds.stack(item)
  local gun = item:match("^ammo%-(.+)$")
  if gun then
    return Guns[gun] and Guns[gun].stack or 100
  elseif item:match("^gun%-") or item == "medkit" then
    return 5
  elseif Catalog.fromItem(item) then
    return 1
  end
  return 50 -- materials
end

--- Slots `inventory` (item -> count) fills.
function Kinds.slotsUsed(inventory)
  local n = 0
  for item, count in pairs(inventory) do
    if count > 0 then
      n = n + math.ceil(count / Kinds.stack(item))
    end
  end
  return n
end

--- How many more of `item` fit in `inventory` with `slots` slots: the rest
--- of its last stack plus every free slot.
function Kinds.room(inventory, slots, item)
  local stack = Kinds.stack(item)
  local have = inventory[item] or 0
  local partial = have % stack
  local free = math.max(0, slots - Kinds.slotsUsed(inventory))
  return free * stack + (partial > 0 and stack - partial or 0)
end

local gunAmmo, gunItems = {}, {}
for _, gun in ipairs(Guns.list) do
  gunAmmo[#gunAmmo + 1] = "ammo-" .. gun.key
  gunItems[#gunItems + 1] = "gun-" .. gun.key
end

-- One product per vehicle model, each at the model's own price.
local carItems, carRecipes = {}, {}
for _, model in ipairs(Catalog.list) do
  carItems[#carItems + 1] = model.item
  carRecipes[model.item] = { price = model.price }
end

Kinds.list = {
  {
    key = "parking", name = "Parking Lot", cost = 30, hp = 200,
    rate = 10 / 60, cap = 100, private = true, walkable = true,
  },
  {
    key = "quarry", name = "Quarry Mine", cost = 40, hp = 600,
    inputs = {}, time = 6, batch = 1, cap = 50, unit = 1, price = 1,
    products = { "iron", "sulfur", "minerals", "copper" },
  },
  {
    key = "oil", name = "Oil Well", cost = 70, hp = 500,
    inputs = {}, time = 8, batch = 1, cap = 50, unit = 1, price = 2,
    products = { "oil", "plastic" },
    recipes = { plastic = { time = 12, price = 3 } }, -- refined on the spot, so slower
  },
  {
    key = "ammo", name = "Ammo Factory", cost = 60, hp = 800,
    inputs = { iron = 1, sulfur = 1 }, time = 6, batch = 10, cap = 200, unit = 10, price = 2,
    products = gunAmmo,
    recipes = {
      ["ammo-rocket"] = {
        inputs = { iron = 1, copper = 1, sulfur = 1 }, time = 10, batch = 2, cap = 20, unit = 1, price = 8,
      },
    },
  },
  {
    key = "weapons", name = "Weapons Factory", cost = 80, hp = 1000,
    inputs = { iron = 4 }, time = 30, batch = 1, cap = 5, unit = 1, price = 20,
    products = gunItems,
    recipes = {
      ["gun-rocket"] = { inputs = { iron = 4, copper = 2, oil = 2, plastic = 2 }, time = 45, price = 60 },
    },
  },
  {
    key = "health", name = "Health Factory", cost = 50, hp = 600,
    inputs = { minerals = 2 }, time = 20, batch = 1, cap = 5, unit = 1, price = 6,
    products = { "medkit" },
  },
}

-- The vehicle factory runs on every material but sulfur and keeps at most
-- five finished cars. Only there when there is a model to build.
if #carItems > 0 then
  Kinds.list[#Kinds.list + 1] = {
    key = "vehicles", name = "Vehicle Factory", cost = 120, hp = 1000,
    inputs = { iron = 4, minerals = 2, copper = 2, oil = 2, plastic = 2 },
    time = 45, batch = 1, cap = 5, unit = 1, price = Catalog.list[1].price,
    products = carItems,
    recipes = carRecipes,
  }
end

local FIELDS = { "inputs", "time", "batch", "cap", "unit", "price" }

--- How `kind` makes product number `index`: { item, inputs, time, batch,
--- cap, unit, price }, the kind's own figures under any override in
--- `kind.recipes`. Kinds without products (the parking lot) get the kind's.
function Kinds.recipe(kind, index)
  local item = kind.products and kind.products[index]
  local cache = kind.recipeCache
  if item and cache[item] then
    return cache[item]
  end
  local over = item and kind.recipes and kind.recipes[item] or {}
  local r = { item = item }
  for _, f in ipairs(FIELDS) do
    if over[f] ~= nil then
      r[f] = over[f]
    else
      r[f] = kind[f]
    end
  end
  r.inputs = r.inputs or {}
  if item then
    cache[item] = r
  end
  return r
end

Kinds.byKey = {}
for i, kind in ipairs(Kinds.list) do
  kind.index = i
  kind.recipeCache = {}
  Kinds.byKey[kind.key] = kind
  -- Everything the hopper takes: the inputs of every product it can make.
  kind.hopper = {}
  for p = 1, #(kind.products or {}) do
    for item in pairs(Kinds.recipe(kind, p).inputs) do
      kind.hopper[item] = true
    end
  end
end

--- Fcks to bring a building of `kind` at `hp` back to full.
function Kinds.repairCost(kind, hp)
  local missing = math.max(0, kind.hp - hp)
  if missing == 0 then
    return 0
  end
  return math.max(1, math.ceil(kind.cost * Kinds.REPAIR * missing / kind.hp))
end

--- A readable name for an item and a count: "10 uzi ammo", "1 medkit".
function Kinds.label(item, n)
  local name = item
  local gun = item:match("^ammo%-(.+)$")
  if gun then
    local g = Guns[gun]
    if g and g.ammoName then
      name = g.ammoName .. (n ~= 1 and "s" or "")
    else
      name = gun .. " ammo"
    end
  else
    gun = item:match("^gun%-(.+)$")
    local model = Catalog.fromItem(item)
    if model then
      name = model.name .. (n ~= 1 and "s" or "")
    elseif gun then
      name = (Guns[gun] and Guns[gun].name or gun) .. (n ~= 1 and "s" or "")
    elseif item == "medkit" and n ~= 1 then
      name = "medkits"
    end
  end
  return n and ("%d %s"):format(n, name) or name
end

--- Is `item` something a building makes or a player carries?
function Kinds.isItem(item)
  for _, kind in ipairs(Kinds.list) do
    for _, p in ipairs(kind.products or {}) do
      if p == item then
        return true
      end
    end
  end
  return false
end

--- The inputs of a recipe as an ordered list of { item, n }, for drawing.
function Kinds.inputList(recipe)
  local out = {}
  for _, m in ipairs(Kinds.materials) do
    if recipe.inputs and recipe.inputs[m] then
      out[#out + 1] = { item = m, n = recipe.inputs[m] }
    end
  end
  return out
end

--- The materials `kind`'s hopper takes, in order: what can be loaded, sold
--- into it and drawn along its side.
function Kinds.hopperList(kind)
  local out = {}
  for _, m in ipairs(Kinds.materials) do
    if kind.hopper and kind.hopper[m] then
      out[#out + 1] = m
    end
  end
  return out
end

--- Is `item` a car (made by the vehicle factory, never carried)?
function Kinds.isVehicle(item)
  return Catalog.fromItem(item) ~= nil
end

--- Is `item` a raw material?
function Kinds.isMaterial(item)
  for _, m in ipairs(Kinds.materials) do
    if m == item then
      return true
    end
  end
  return false
end

return Kinds
