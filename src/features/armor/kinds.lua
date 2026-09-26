-- Every piece of armor, by key. An armor item in a bag is "armor-<key>";
-- worn, it stands between a player's body and whatever hits it until its
-- points are gone.
--
--   key     on the wire and in a bag
--   title   what the shop and the inventory call it
--   points  how much damage it soaks up before it is destroyed
--   color   the bar and the item
--   blurb   what it does, for the shop's side panel
--   tierStats  what a better tier improves (tiers/init.lua): the points

local Kinds = {
  list = {
    {
      key = "vest", title = "kevlar vest", points = 100, color = { 0.35, 0.65, 1 }, tierStats = { "points" },
      blurb = "Takes the hits before your body does, until it is shot through.",
    },
  },
  byKey = {},
}

for _, a in ipairs(Kinds.list) do
  Kinds.byKey[a.key] = a
end

return Kinds
