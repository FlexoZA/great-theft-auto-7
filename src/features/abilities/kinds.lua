-- The abilities, one module each (freeze.lua, ...), in the order they are
-- listed to the world. Each has a `key` ("freeze") the wire and the
-- inventory use ("ability-<key>" is one carried as an item), a `title` (and
-- an optional shorter `hud` name for under its ring), a `color`, `range`, `radius`, `seconds`, `cooldown`, `afterglow`,
-- a `sound`, and `serverCast`, `drawEffect`; a passive one (`passive =
-- true`) has `serverTick` instead and lives in the passive slot. The
-- buildings feature reads this to name and draw an ability in a bag; each
-- ability's picture is in icons.lua, keyed the same.

local Kinds = {
  list = {
    require("src.features.abilities.freeze"),
    require("src.features.abilities.regen"),
    require("src.features.abilities.mgnest"),
    require("src.features.abilities.heal"),
    require("src.features.abilities.fart"),
    require("src.features.abilities.openborders"),
    require("src.features.abilities.leap"),
    require("src.features.abilities.bigleap"),
  },
  byKey = {},
}

for _, ability in ipairs(Kinds.list) do
  Kinds.byKey[ability.key] = ability
end

return Kinds
