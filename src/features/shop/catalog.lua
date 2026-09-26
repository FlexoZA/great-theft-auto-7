-- What the shop sells: every gun and a box of its rounds (weapons/guns.lua),
-- every ability (abilities/kinds.lua) but a boss's drop, a medkit and an energy drink, every
-- piece of armor (armor/kinds.lua) and clothing (gear/kinds.lua), every car model
-- (vehicles/catalog.lua) and the people for hire (delivery/hire.lua). Built
-- once from those lists, so a new gun, ability or model is on the shelf
-- without touching this file.
--
-- Each entry:
--   item    the inventory item it hands over ("gun-uzi", "ammo-uzi",
--           "ability-freeze", "medkit", "car-hatchback-orange")
--   n       how many of it one purchase gives (cars: one on the road)
--   name    what the card says
--   kind    "gun" | "ammo" | "ability" | "supply" | "armor" | "gear" | "car" | "hire", the badge on the card
--   badge   what the badge says instead of the kind ("passive" for a passive ability)
--   price   Fcks; 0 is free. Everything is free for now: put prices here
--           when the economy is ready and the host charges them (init.lua
--           pays through money:spend). A better tier costs more
--           (`Catalog.price`).
--   tiered  true for equipment (guns, abilities, armor, clothes): it is sold
--           in every tier (tiers/init.lua), "gun-uzi@rare" on the wire
--   onRoad  true for something put into the world outside the door rather
--           than into a bag (cars always are): the host hands it to the
--           `serverDeliver` event and the feature that answers places it
--   icon    function(cx, cy, scale): the card's picture, when the
--           inventory has none for the item (a hire)
--   details function(entry) -> { blurb, use, rows }: the side panel's text,
--           for a kind details.lua doesn't know
--   bought  what the shop says once it is bought, for an `onRoad` thing
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
local Hire = require("src.features.delivery.hire")

local Catalog = {
  list = {},
  byItem = {},
  -- The shop's tabs, each a filter on `kind` (or on `kinds`, a set of
  -- them): All is everything that goes into a bag, the rest one shelf
  -- each. Supplies are medkits and energy drinks; Gear is what you wear:
  -- armor and clothes. Cars have their own tab, with bigger cards.
  tabs = {
    { key = "all", title = "All" },
    { key = "guns", title = "Guns", kind = "gun" },
    { key = "ammo", title = "Ammo", kind = "ammo" },
    { key = "supplies", title = "Supplies", kind = "supply" },
    { key = "abilities", title = "Abilities", kind = "ability" },
    { key = "gear", title = "Gear", kinds = { armor = true, gear = true } },
    { key = "cars", title = "Cars", kind = "car" },
    { key = "hire", title = "Hire", kind = "hire" },
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
for _, entry in ipairs(Hire.list) do
  add(entry)
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
    local on
    if t.kinds then
      on = t.kinds[e.kind]
    elseif t.kind then
      on = e.kind == t.kind
    else
      on = not Catalog.onRoad(e)
    end
    if on then
      out[#out + 1] = e
    end
  end
  return out
end

--- Is this a car (drawn with the vehicle factory's card)?
function Catalog.isCar(entry)
  return entry.kind == "car"
end

--- Is this something put into the world rather than into a bag: a car, or
--- anything marked `onRoad` (a driver for hire)?
function Catalog.onRoad(entry)
  return entry.kind == "car" or entry.onRoad == true
end

return Catalog
