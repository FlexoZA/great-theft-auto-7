-- The Citadel, the end of A-Man's trail (quests' "a-man-citadel", on
-- city-map's `citadel`): one catwalk up through the shaft, widening into
-- platforms on the way. For now it is the walk alone: the map's `posts`
-- mark where the Combine will stand. The first player to reach the lift up
-- at the top (`map.exitX, map.exitY`) finishes the level (quests'
-- `serverComplete`): a star comes up there.
--
-- The a-man feature (init.lua) passes its hooks on to this module.

local Features = require("src.features")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man-citadel" -- the quest this level is
Level.reach = 140 -- px from the lift up that counts as reaching it

local sv = nil -- { reached } while the level is on, on the host

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == "citadel" and city.map or nil
end

function Level.serverQuestStarted(_server, quest)
  if quest.id == Level.questId and cityMap() then
    sv = { reached = false }
  end
end

function Level.serverStop()
  sv = nil
end

--- Has anyone got to the lift up? The first one there finishes the level.
function Level.serverStep(server)
  local map = cityMap()
  if not (sv and map) or sv.reached then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.exitX) ^ 2 + (y - map.exitY) ^ 2 <= Level.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests and quests.serverComplete then
          quests:serverComplete(server, Level.questId, map.exitX, map.exitY)
        end
        return
      end
    end
  end
end

return Level
