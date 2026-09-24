-- Every piece of clothing, by key, and the slot it goes in. A piece in a
-- bag is "gear-<key>"; worn, its `stats` scale what the wearer does.
--
--   key     on the wire and in a bag
--   slot    "head" | "body" | "pants" | "shoes"
--   title   what the shop and the inventory call it
--   color   the item
--   blurb   what it does, for the shop card
--   stats   multipliers, all optional and 1 when left out:
--             speed     walking and running speed (on-foot)
--             stamina   what sprinting costs (on-foot)
--             ammo      how big a bundle of rounds is when it goes into the bag (buildings)
--             cooldown  how long abilities take to come back (abilities)
--             armor     how many points a vest has (armor)
--           Pieces stack: two that each give x1.2 give x1.44.

local Kinds = {
  slots = { "head", "body", "pants", "shoes" },
  list = {
    {
      key = "tactical-hat", slot = "head", title = "tactical hat", color = { 0.35, 0.42, 0.3 },
      blurb = "ammo bundles half as big again", stats = { ammo = 1.5 },
    },
    {
      key = "plate-carrier", slot = "body", title = "plate carrier", color = { 0.42, 0.46, 0.52 },
      blurb = "armor holds a quarter more", stats = { armor = 1.25 },
    },
    {
      key = "cargo-pants", slot = "pants", title = "cargo pants", color = { 0.52, 0.46, 0.3 },
      blurb = "abilities back a quarter sooner", stats = { cooldown = 0.75 },
    },
    {
      key = "running-shoes", slot = "shoes", title = "running shoes", color = { 0.9, 0.35, 0.3 },
      blurb = "15% faster on foot, sprinting costs 30% less", stats = { speed = 1.15, stamina = 0.7 },
    },
  },
  byKey = {},
  bySlot = {},
}

for _, g in ipairs(Kinds.list) do
  Kinds.byKey[g.key] = g
  Kinds.bySlot[g.slot] = Kinds.bySlot[g.slot] or {}
  table.insert(Kinds.bySlot[g.slot], g)
end

--- Is `slot` one clothes go in?
function Kinds.isSlot(slot)
  for _, s in ipairs(Kinds.slots) do
    if s == slot then
      return true
    end
  end
  return false
end

return Kinds
