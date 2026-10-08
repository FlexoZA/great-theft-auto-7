-- The Winding Road, the last stop on A-Man's trail before the Citadel
-- (quests' "a-man-road", on city-map's `road`): driven, from the valley
-- floor up to the pass. The Poison Zombie waits on the pass (the
-- poison-zombie feature), and beating him finishes the level. Without that
-- feature, the first player to reach the pass (`map.exitX, map.exitY`)
-- finishes it (quests' `serverComplete`): a star comes up there.
--
-- The a-man feature (init.lua) passes its hooks on to this module.

local Features = require("src.features")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man-road" -- the quest this level is
Level.reach = 200 -- px from the pass's middle that counts as reaching it

local sv = nil -- { reached } while the level is on, on the host

local function roadMap()
  local city = Features.byName["city-map"]
  return city and city.current == "road" and city.map or nil
end

function Level.serverQuestStarted(_server, quest)
  if quest.id == Level.questId and roadMap() then
    sv = { reached = false }
  end
end

function Level.serverStop()
  sv = nil
end

--- Has anyone got to the pass, in a car or on foot? The first one there finishes the level.
function Level.serverStep(server)
  local map = roadMap()
  if not (sv and map) or sv.reached or Features.byName["poison-zombie"] then
    return -- the zombie on the pass finishes it
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
