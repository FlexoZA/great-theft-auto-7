-- What the shop sells: every gun and a box of its rounds (weapons/guns.lua),
-- every ability (abilities/kinds.lua) but a boss's drop, a medkit, and every car model
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
--   price   Fcks; 0 is free. Everything is free for now: put prices here
--           when the economy is ready and the host charges them (init.lua
--           pays through money:spend). A better tier costs more
--           (`Catalog.price`).
--   tiered  true for equipment (guns, abilities, armor, clothes): it is sold
--           in every tier (tiers/init.lua), "gun-uzi@rare" on the wire
--
-- The host and every client share this list, so an item on the wire is
-- checked against `Catalog.byItem` before anything is handed over.

local Guns = require("src.features.weapons.guns")
local AbilityKinds = require("src.features.abilities.kinds")
local Vehicles = require("src.features.vehicles.catalog")
local Kinds = require("src.features.buildings.kinds")
local ArmorKinds = require("src.features.armor.kinds")
local GearKinds = require("src.features.gear.kinds")
local Tiers = require("src.features.tiers")

local Catalog = {
  list = {},
  byItem = {},
  -- The shop's tabs, each a filter on `kind`: All is everything that goes
  -- into a bag, the rest one kind each. Cars have their own tab, with
  -- bigger cards.
  tabs = {
    { key = "all", title = "All" },
    { key = "guns", title = "Guns", kind = "gun" },
    { key = "ammo", title = "Ammo", kind = "ammo" },
    { key = "abilities", title = "Abilities", kind = "ability" },
    { key = "cars", title = "Cars", kind = "car" },
  },
  tabByKey = {},
}

--- Rounds in a box of ammo for `gun`: two magazines, and at least five.
local function boxOf(gun)
  return math.max(5, gun.magazine * 2)
end

local function add(entry)
  entry.price = entry.price or 0
  entry.tiered = Tiers.tiered(entry.item)
  Catalog.list[#Catalog.list + 1] = entry
  Catalog.byItem[entry.item] = entry
end

for _, gun in ipairs(Guns.list) do
  add({ item = "gun-" .. gun.key, n = 1, name = gun.name, kind = "gun" })
end
for _, gun in ipairs(Guns.list) do
  if not gun.bottomless then -- the pistol never runs out: nothing to sell for it
    local n = boxOf(gun)
    add({ item = "ammo-" .. gun.key, n = n, name = Kinds.label("ammo-" .. gun.key, n), kind = "ammo" })
  end
end
for _, ability in ipairs(AbilityKinds.list) do
  if not ability.unsold then -- a boss's drop (bigleap) is only won
    add({
      item = "ability-" .. ability.key, n = 1, name = ability.title, kind = "ability",
      badge = ability.passive and "passive" or nil, -- a passive works by being carried, no key
    })
  end
end
add({ item = "medkit", n = 1, name = "medkit", kind = "supply" })
add({ item = "drink", n = 1, name = "energy drink", kind = "supply" })
for _, a in ipairs(ArmorKinds.list) do
  add({ item = "armor-" .. a.key, n = 1, name = a.title, kind = "armor" })
end
for _, g in ipairs(GearKinds.list) do
  add({ item = "gear-" .. g.key, n = 1, name = g.title, kind = "gear", badge = g.slot })
end
for _, model in ipairs(Vehicles.list) do
  add({ item = model.item, n = 1, name = model.name, kind = "car" })
end

for _, t in ipairs(Catalog.tabs) do
  Catalog.tabByKey[t.key] = t
end

--- What `entry` costs in tier `tier`: its price times the tier's.
function Catalog.price(entry, tier)
  if not entry.tiered then
    return entry.price
  end
  return entry.price * Tiers.get(tier).price
end

--- The entry `item` ("gun-uzi", "gun-uzi@rare") is bought from, and its
--- tier; nil for anything not for sale, or a tier on something that has none.
function Catalog.lookup(item)
  local base, tier = Tiers.split(item or "")
  local entry = Catalog.byItem[base]
  if not (entry and tier) or (tier ~= Tiers.DEFAULT and not entry.tiered) then
    return nil
  end
  return entry, tier
end

--- The entries on tab `key`, in shelf order.
function Catalog.onTab(key)
  local t = Catalog.tabByKey[key] or Catalog.tabs[1]
  local out = {}
  for _, e in ipairs(Catalog.list) do
    if (t.kind and e.kind == t.kind) or (not t.kind and e.kind ~= "car") then
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
