-- What can be built on a plot, and the things buildings make.
--
-- Items are what a player carries and a building stores, by key:
--   iron, sulfur, minerals   raw materials, dug out of a quarry
--   ammo-<gun>               rounds for a gun in weapons/guns.lua ("ammo-uzi")
--   gun-<gun>                a gun ("gun-uzi")
--   medkit                   a health pack; the carrier can use it to heal
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
--   private   true: never open to the public (the parking lot)
--   walkable  true: not solid, cars drive onto it (the parking lot)
-- The parking lot is the odd one out: it earns koins by the minute (`rate`)
-- and pays them to its owner when they drive over it.

local Guns = require("src.features.weapons.guns")

local Kinds = {}

Kinds.materials = { "iron", "sulfur", "minerals" }
Kinds.HOPPER = 20 -- most of each input a factory holds
Kinds.SLOTS = 4 -- inventory slots everyone starts with
Kinds.MAX_SLOTS = 9 -- with every slot upgrade bought

--- How many of `item` fit in one inventory slot.
function Kinds.stack(item)
  if item:match("^ammo%-") then
    return 100
  elseif item:match("^gun%-") or item == "medkit" then
    return 5
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

Kinds.list = {
  {
    key = "parking", name = "Parking Lot", cost = 30,
    rate = 10 / 60, cap = 100, private = true, walkable = true,
  },
  {
    key = "quarry", name = "Quarry Mine", cost = 40,
    inputs = {}, time = 6, batch = 1, cap = 50, unit = 1, price = 1,
    products = Kinds.materials,
  },
  {
    key = "ammo", name = "Ammo Factory", cost = 60,
    inputs = { iron = 1, sulfur = 1 }, time = 6, batch = 10, cap = 200, unit = 10, price = 2,
    products = gunAmmo,
  },
  {
    key = "weapons", name = "Weapons Factory", cost = 80,
    inputs = { iron = 4 }, time = 30, batch = 1, cap = 5, unit = 1, price = 20,
    products = gunItems,
  },
  {
    key = "health", name = "Health Factory", cost = 50,
    inputs = { minerals = 2 }, time = 20, batch = 1, cap = 5, unit = 1, price = 6,
    products = { "medkit" },
  },
}

Kinds.byKey = {}
for i, kind in ipairs(Kinds.list) do
  kind.index = i
  Kinds.byKey[kind.key] = kind
end

--- A readable name for an item and a count: "10 uzi ammo", "1 medkit".
function Kinds.label(item, n)
  local name = item
  local gun = item:match("^ammo%-(.+)$")
  if gun then
    name = gun .. " ammo"
  else
    gun = item:match("^gun%-(.+)$")
    if gun then
      name = gun .. (n ~= 1 and "s" or "")
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

--- The inputs of `kind` as an ordered list of { item, n }, for drawing.
function Kinds.inputList(kind)
  local out = {}
  for _, m in ipairs(Kinds.materials) do
    if kind.inputs and kind.inputs[m] then
      out[#out + 1] = { item = m, n = kind.inputs[m] }
    end
  end
  return out
end

return Kinds
