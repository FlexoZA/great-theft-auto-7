-- Eternal Mood: the pest-control job to the moon (docs/eternal-mood.md), a
-- dream of a 90s demon shooter that you wake up from. Its quests (quests'
-- "eternal-mood" and the ones after it) take everyone over its maps, all
-- in the dark; so far only Fobos Base (city-map's `fobos`).
--
-- For now each level is only the way through: the first player to reach the
-- map's way on (`map.exitX`, `map.exitY`, Fobos Base's hangar lift)
-- finishes it, and an EXIT star comes up there. The Voice, the horde and the
-- bosses come later.

local Features = require("src.features")

local EternalMood = {
  name = "eternal-mood",
  questId = "eternal-mood", -- the quests that are this feature's (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
EternalMood.reach = 160 -- px from the way on that finishes a level

local sv = nil -- { quest, reached } on the host while one of the levels is under way

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

function EternalMood:serverStart()
  sv = nil
end

function EternalMood:serverQuestStarted(_server, quest)
  if quest.boss == self.questId then
    sv = { quest = quest.id, reached = false }
  end
end

function EternalMood:serverQuestEnded(_server, quest)
  if quest.boss == self.questId then
    sv = nil
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function EternalMood:mapChanged(_map, server)
  if server then
    sv = nil
  end
end

--- Has anyone got to the way on? The first one there finishes the level.
function EternalMood:serverStep(server)
  local map = cityMap()
  if not (sv and not sv.reached and map and map.exitX) then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.exitX) ^ 2 + (y - map.exitY) ^ 2 <= self.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests then
          quests:serverComplete(server, sv.quest, map.exitX, map.exitY)
        end
        return
      end
    end
  end
end

--- For tests.
function EternalMood.server()
  return sv
end

return EternalMood
