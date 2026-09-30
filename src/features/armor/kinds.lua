-- Every piece of armor, by key. An armor item in a bag is "armor-<key>";
-- worn, it stands between a player's body and whatever hits it until its
-- points are gone.
--
--   key     on the wire and in a bag
--   title   what the shop and the inventory call it
--   points  how much damage it soaks up before it is destroyed
--   color   the bar and the item
--   blurb   what it does, for the shop's side panel
--   resist  optional: type -> the share of that damage type it stops
--           while worn (src/features/damage), before its points soak up
--           the rest: { bullet = 0.3 } stops 30% of every bullet
--   tierStats  what a better tier improves, in order (tiers/init.lua):
--              "points", or a resistance as "resist.<type>"

local Kinds = {
  list = {
    {
      key = "vest", title = "kevlar vest", points = 100, color = { 0.35, 0.65, 1 },
      resist = { bullet = 0.3 }, tierStats = { "points", "resist.bullet" },
      blurb = "Takes the hits before your body does, until it is shot through. Bullets hurt less through it.",
    },
    {
      key = "bomb-suit", title = "bomb suit", points = 60, color = { 0.45, 0.52, 0.32 },
      resist = { explosive = 0.5, impact = 0.3, fire = 0.15 },
      tierStats = { "resist.explosive", "points", "resist.impact", "resist.fire" },
      blurb = "Thick padding for standing next to things that go bang: blasts and knocks do much less, "
        .. "and throw you less far.",
    },
  },
  byKey = {},
}

for _, a in ipairs(Kinds.list) do
  Kinds.byKey[a.key] = a
end

return Kinds
