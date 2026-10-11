-- Cyber Feud: the courier job into Grey City (docs/cyber-feud.md). Its
-- quests (quests' "cyber-feud" and the four after it) take everyone over
-- five maps, city-map's `drop`, `market`, `overpass`, `tower` and `roof`,
-- all at night.
--
-- For now each level is only the way through: the first player to reach the
-- map's far end (`map.exitX`, `map.exitY`) finishes it, and an EXIT star
-- comes up there leading on to the next one (quests' `next`), or home from
-- the Roof. VEX, the factions, the breach and the bosses come later.

local Features = require("src.features")

local CyberFeud = {
  name = "cyber-feud",
  questId = "cyber-feud", -- the quests that are this feature's (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
CyberFeud.reach = 160 -- px from the far end that finishes a level

local sv = nil -- { quest, reached } on the host while one of the levels is under way

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

function CyberFeud:serverStart()
  sv = nil
end

function CyberFeud:serverQuestStarted(_server, quest)
  if quest.boss == self.questId then
    sv = { quest = quest.id, reached = false }
  end
end

function CyberFeud:serverQuestEnded(_server, quest)
  if quest.boss == self.questId then
    sv = nil
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function CyberFeud:mapChanged(_map, server)
  if server then
    sv = nil
  end
end

--- Has anyone got to the far end? The first one there finishes the level.
function CyberFeud:serverStep(server)
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
function CyberFeud.server()
  return sv
end

return CyberFeud
