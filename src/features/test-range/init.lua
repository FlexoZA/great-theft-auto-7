-- The test range: a walled field for trying things out against the real
-- thing, nothing round it but what it is here to test. Nothing leads here
-- in play; `love . --world <slug> --quest test-range` does (src/launch.lua),
-- and the blue star takes you home. See "The test range" in docs/features.md.
--
-- `ARMY` is the map's `army` (borderline/army.lua says what goes in it), so
-- anything of Hyperbole's stands here as it does on its own map, its brain
-- untouched and without Borderline's story: put another post in to try it.
-- The rest of the game's enemies need the same from their own features.

local Features = require("src.features")

local TestRange = {
  name = "test-range",
  questId = "test-range", -- quests' `boss` on the range
}

-- Far enough up the field that it is out of range of everyone arriving.
TestRange.ARMY = {
  posts = {
    { code = "DCK", x = 0, y = -900, watch = math.pi / 2 }, -- a hauler dock: the plasma turret, and what it builds
  },
}

--- Everyone is on the range by now; leaving it clears the army (borderline's mapChanged).
function TestRange:serverQuestStarted(server, quest)
  if quest.boss == self.questId then
    local map = Features.byName["city-map"].map
    map.army = self.ARMY
    Features.byName.borderline:serverStartArmy(server, map)
  end
end

return TestRange
