-- Shoeman's school of survival: the first job on a new world's board, five
-- levels chained by each quest's `next` (`tutorial-1` to `tutorial-5`).
-- Shoeman teaches moving and stamina, dodging, shooting, abilities and
-- building, and hands over the first pistol and the first ability.
-- The design, and the tick list it is built from, is docs/tutorial.md.
--
-- Every level's state lives on the host, in this feature; clients only draw
-- what the host tells them.

local Tutorial = {
  name = "tutorial",
}

-- The levels, in order. Each is a quest of the same id in `Quests.list`.
Tutorial.LEVELS = { "tutorial-1", "tutorial-2", "tutorial-3", "tutorial-4", "tutorial-5" }

local levelOf = {}
for i, id in ipairs(Tutorial.LEVELS) do
  levelOf[id] = i
end

-- Each level's way on, world px, near the top of its map (city-map's
-- `tutorial-*` maps, placeholder fields for now): reaching it finishes the
-- level and the EXIT star comes up there. Levels 4 and 5 share the town.
Tutorial.EXITS = {
  ["tutorial-1"] = { x = 0, y = -1536 },
  ["tutorial-2"] = { x = 0, y = -1152 },
  ["tutorial-3"] = { x = 0, y = -1024 },
  ["tutorial-4"] = { x = 0, y = -1024 },
  ["tutorial-5"] = { x = 0, y = -1024 },
}

--- The level number (1 to 5) of quest `id`, or nil when it is not a tutorial level.
function Tutorial.level(id)
  return levelOf[id]
end

return Tutorial
