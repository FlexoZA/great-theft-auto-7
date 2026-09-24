-- The abilities, one module each (freeze.lua, ...), in the order they are
-- listed to the world. Each has a `key` ("freeze") the wire and the
-- inventory use ("ability-<key>" is one carried as an item), a `title` for
-- the HUD, a `color`, `range`, `radius`, `seconds`, `cooldown`, `afterglow`,
-- a `sound`, and `serverCast`, `drawEffect`. The buildings feature reads
-- this to name and draw an ability in a bag.

local Kinds = {
  list = {
    require("src.features.abilities.freeze"),
  },
  byKey = {},
}

for _, ability in ipairs(Kinds.list) do
  Kinds.byKey[ability.key] = ability
end

return Kinds
