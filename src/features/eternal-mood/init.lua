-- Eternal Mood: the pest-control job to the moon (docs/eternal-mood.md), a
-- dream of a 90s demon shooter that you wake up from. Its quests (quests'
-- "eternal-mood" and the ones after it) take everyone over its maps, all
-- in the dark; so far only Fobos Base (city-map's `fobos`).
--
-- The first player to reach the map's way on (`map.exitX`, `map.exitY`,
-- Fobos Base's hangar lift) finishes the level, and an EXIT star comes up
-- there, once the level's boss is down (Fobos Base's: the Floor Manager,
-- floor_manager.lua, standing on the lift). Heck's horde holds the way
-- (horde.lua: the possessed at their posts, the imps in the vents). The
-- Voice comes later.

local Features = require("src.features")
local Horde = require("src.features.eternal-mood.horde")
local FloorManager = require("src.features.eternal-mood.floor_manager")

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

function EternalMood:load()
  Horde.load()
  FloorManager.load()
end

function EternalMood:serverStart()
  sv = nil
end

function EternalMood:serverQuestStarted(server, quest)
  if quest.boss == self.questId then
    sv = { quest = quest.id, reached = false }
    local map = cityMap()
    if map then
      local nav = Horde.serverStart(server, map)
      FloorManager.serverStart(server, map, nav)
    end
  end
end

function EternalMood:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function EternalMood:mapChanged(_map, server)
  if server then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
  end
  Horde.clear()
  FloorManager.clear()
end

function EternalMood:serverPlayerJoined(server, player)
  Horde.serverPlayerJoined(server, player)
  FloorManager.serverPlayerJoined(server, player)
end

function EternalMood:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  return FloorManager.serverShotAt(server, x, y, radius, by, angle, damage)
    or Horde.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

function EternalMood:serverFreezeArea(_server, x, y, radius, seconds)
  Horde.serverFreezeArea(x, y, radius, seconds)
  FloorManager.serverFreezeArea(x, y, radius, seconds)
end

--- Has anyone got to the way on? The first one there finishes the level,
--- once its boss is down.
function EternalMood:serverStep(server, dt)
  Horde.serverStep(server, dt)
  FloorManager.serverStep(server, dt)
  local map = cityMap()
  if not (sv and not sv.reached and map and map.exitX) or FloorManager.serverLocked() then
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

-- Client --------------------------------------------------------------------

function EternalMood:questStarted(_client, quest)
  if quest.boss == self.questId then
    Horde.clear() -- the vents shut again on a new run
    FloorManager.clear()
  end
end

function EternalMood:questEnded(_client, quest)
  if quest.boss == self.questId then
    Horde.clear()
    FloorManager.clear()
  end
end

function EternalMood:exitGame()
  Horde.clear()
  FloorManager.clear()
end

function EternalMood:update(dt)
  Horde.update(dt)
  FloorManager.update(dt)
end

function EternalMood:drawBelowCars()
  Horde.drawVents(cityMap())
  FloorManager.drawBelowCars()
  Horde.drawBelowCars()
end

function EternalMood:drawAboveCars()
  FloorManager.drawAboveCars()
  Horde.drawAboveCars()
end

function EternalMood:drawNightLights(_client, _camera, glow)
  Horde.drawNightLights(glow)
  FloorManager.drawNightLights(glow)
end

function EternalMood:drawHUD()
  FloorManager.drawHUD()
end

function EternalMood:footstepWalkers()
  return Horde.walkers()
end

EternalMood.clientMessages = {}
for _, part in ipairs({ Horde, FloorManager }) do
  for kind, handler in pairs(part.clientMessages) do
    EternalMood.clientMessages[kind] = handler
  end
end

return EternalMood
