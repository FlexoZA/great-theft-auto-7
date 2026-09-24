-- What the shop sells: every gun and a box of its rounds (weapons/guns.lua),
-- every ability (abilities/kinds.lua), a medkit, and every car model
-- (vehicles/catalog.lua). Built once from those lists, so a new gun, ability
-- or model is on the shelf without touching this file.
--
-- Each entry:
--   item    the inventory item it hands over ("gun-uzi", "ammo-uzi",
--           "ability-freeze", "medkit", "car-hatchback-orange")
--   n       how many of it one purchase gives (cars: one on the road)
--   name    what the card says
--   kind    "gun" | "ammo" | "ability" | "supply" | "armor" | "gear" | "car", the badge on the card
--   badge   what the badge says instead of the kind ("passive" for a passive ability)
--   tab     which tab of the shop it is on ("items" or "cars")
--   price   Fcks; 0 is free. Everything is free for now: put prices here
--           when the economy is ready and the host charges them (init.lua
--           pays through money:spend).
--
-- The host and every client share this list, so an item on the wire is
-- checked against `Catalog.byItem` before anything is handed over.

local Guns = require("src.features.weapons.guns")
local AbilityKinds = require("src.features.abilities.kinds")
local Vehicles = require("src.features.vehicles.catalog")
local Kinds = require("src.features.buildings.kinds")
local ArmorKinds = require("src.features.armor.kinds")
local GearKinds = require("src.features.gear.kinds")

local Catalog = {
  list = {},
  byItem = {},
  tabs = {
    { key = "items", title = "Items" },
    { key = "cars", title = "Cars" },
  },
}

--- Rounds in a box of ammo for `gun`: two magazines, and at least five.
local function boxOf(gun)
  return math.max(5, gun.magazine * 2)
end

local function add(entry)
  entry.price = entry.price or 0
  Catalog.list[#Catalog.list + 1] = entry
  Catalog.byItem[entry.item] = entry
end

for _, gun in ipairs(Guns.list) do
  add({ item = "gun-" .. gun.key, n = 1, name = gun.name, kind = "gun", tab = "items" })
end
for _, gun in ipairs(Guns.list) do
  local n = boxOf(gun)
  add({ item = "ammo-" .. gun.key, n = n, name = Kinds.label("ammo-" .. gun.key, n), kind = "ammo", tab = "items" })
end
for _, ability in ipairs(AbilityKinds.list) do
  add({
    item = "ability-" .. ability.key, n = 1, name = ability.title, kind = "ability", tab = "items",
    badge = ability.passive and "passive" or nil, -- a passive works by being carried, no key
  })
end
add({ item = "medkit", n = 1, name = "medkit", kind = "supply", tab = "items" })
add({ item = "drink", n = 1, name = "energy drink", kind = "supply", tab = "items" })
for _, a in ipairs(ArmorKinds.list) do
  add({ item = "armor-" .. a.key, n = 1, name = a.title, kind = "armor", tab = "items" })
end
for _, g in ipairs(GearKinds.list) do
  add({ item = "gear-" .. g.key, n = 1, name = g.title, kind = "gear", tab = "items", badge = g.slot })
end
for _, model in ipairs(Vehicles.list) do
  add({ item = model.item, n = 1, name = model.name, kind = "car", tab = "cars" })
end

--- The entries on `tab`, in shelf order.
function Catalog.onTab(tab)
  local out = {}
  for _, e in ipairs(Catalog.list) do
    if e.tab == tab then
      out[#out + 1] = e
    end
  end
  return out
end

--- Is this something that goes on the road rather than into a bag?
function Catalog.isCar(entry)
  return entry.kind == "car"
end

return Catalog
