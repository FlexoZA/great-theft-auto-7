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
--   resist  optional: type -> the share of that damage type it stops
--           (src/features/damage): { fire = 0.4 } stops 40% of every
--           fire hit. Pieces stack the same way: two that each stop 30%
--           stop 51%.
--   tierStats  which of its stats a better tier improves, in order
--              (tiers/init.lua), a resistance as "resist.<type>"; left
--              out, every stat and resistance it has, sorted by name.
--              Leave out a stat that is a drawback (x0.95 speed): a
--              tier grows it like a bonus

local Kinds = {
  slots = { "head", "body", "pants", "shoes" },
  list = {
    {
      key = "tactical-hat", slot = "head", title = "tactical hat", color = { 0.35, 0.42, 0.3 },
      blurb = "ammo bundles half as big again", stats = { ammo = 1.5 },
    },
    {
      key = "plate-carrier", slot = "body", title = "plate carrier", color = { 0.42, 0.46, 0.52 },
      blurb = "armor holds a quarter more; bullets and blasts hurt a little less", stats = { armor = 1.25 },
      resist = { bullet = 0.1, explosive = 0.1 }, tierStats = { "armor", "resist.bullet", "resist.explosive" },
    },
    {
      key = "cargo-pants", slot = "pants", title = "cargo pants", color = { 0.52, 0.46, 0.3 },
      blurb = "abilities back a quarter sooner", stats = { cooldown = 0.75 },
    },
    {
      key = "running-shoes", slot = "shoes", title = "running shoes", color = { 0.9, 0.35, 0.3 },
      blurb = "15% faster on foot, sprinting costs 30% less", stats = { speed = 1.15, stamina = 0.7 },
      tierStats = { "speed", "stamina" },
    },
    {
      key = "crash-helmet", slot = "head", title = "crash helmet", color = { 0.85, 0.75, 0.2 },
      blurb = "knocks, trampling and slams hurt a third less; blasts a little less", stats = {},
      resist = { impact = 0.35, explosive = 0.1 }, tierStats = { "resist.impact", "resist.explosive" },
    },
    {
      key = "fire-jacket", slot = "body", title = "firefighter jacket", color = { 0.85, 0.55, 0.15 },
      blurb = "fire and burning hurt 40% less", stats = {}, resist = { fire = 0.4 },
    },
    {
      key = "leather-jacket", slot = "body", title = "leather jacket", color = { 0.3, 0.22, 0.18 },
      blurb = "punches, claws and bites hurt 30% less", stats = {}, resist = { melee = 0.3 },
    },
    {
      key = "rubber-boots", slot = "shoes", title = "rubber boots", color = { 0.2, 0.45, 0.25 },
      blurb = "shocks hurt half as much and stun you half as long; a little slower on foot",
      stats = { speed = 0.95 }, resist = { shock = 0.5 }, tierStats = { "resist.shock" },
    },
  },
  byKey = {},
  bySlot = {},
}

for _, g in ipairs(Kinds.list) do
  Kinds.byKey[g.key] = g
  if not g.tierStats then
    g.tierStats = {}
    for name in pairs(g.stats) do
      g.tierStats[#g.tierStats + 1] = name
    end
    for dtype in pairs(g.resist or {}) do
      g.tierStats[#g.tierStats + 1] = "resist." .. dtype
    end
    table.sort(g.tierStats)
  end
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
