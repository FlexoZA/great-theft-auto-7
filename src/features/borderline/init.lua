-- Borderline: the long walk to Handsome Jerry's bunker on Pandoria
-- (docs/borderline.md). Its quests (quests' "borderline" and the seven
-- after it) take everyone over eight maps, city-map's `wreck`, `landing`,
-- `pit`, `prosperity`, `refinery`, `assembly`, `cuts` and `bunker`, all on
-- foot.
--
-- So far each level is only its way through: the first player to walk up
-- to the map's way on (`map.exitX`, `map.exitY`) finishes it, and its EXIT
-- star leads on to the next level (quests' `next`), or home from the
-- Bunker. Jerry, Yappy, the robots and the bosses come in later stages.

local Features = require("src.features")

local Borderline = {
  name = "borderline",
  questId = "borderline", -- quests' `boss` on every level of the line
}

-- Tuning ------------------------------------------------------------------
Borderline.reach = 160 -- px from the way on that finishes a level

local level = nil -- on the host: { quest = id, done = bool } while a level is being played

function Borderline:serverStart()
  level = nil
end

function Borderline:serverQuestStarted(_server, quest)
  if quest.boss == self.questId then
    level = { quest = quest.id, done = false }
  end
end

function Borderline:serverQuestEnded(_server, quest)
  if quest.boss == self.questId then
    level = nil
  end
end

--- Leaving the map ends the level whatever the reason; the next quest
--- (if there is one) starts its own.
function Borderline:mapChanged(_map, server)
  if server then
    level = nil
  end
end

--- The human player standing within reach of (x, y), if any.
local function arrivedAt(server, x, y, reach)
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local px, py = Features.bodyPose(server, p)
      local dx, dy = px - x, py - y
      if dx * dx + dy * dy <= reach * reach then
        return p
      end
    end
  end
  return nil
end

function Borderline:serverStep(server)
  if not level or level.done then
    return
  end
  local city = Features.byName["city-map"]
  local map = city and city.map
  if not (map and map.exitX) or not arrivedAt(server, map.exitX, map.exitY, self.reach) then
    return
  end
  level.done = true
  local quests = Features.byName.quests
  if quests then
    quests:serverComplete(server, level.quest, map.exitX, map.exitY)
  end
end

--- For tests: the level under way on the host.
function Borderline.server()
  return level
end

return Borderline
