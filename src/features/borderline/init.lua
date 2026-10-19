-- Borderline: the long walk to Handsome Jerry's bunker on Pandoria
-- (docs/borderline.md). Its quests (quests' "borderline" and the seven
-- after it) take everyone over eight maps, city-map's `wreck`, `landing`,
-- `pit`, `prosperity`, `refinery`, `assembly`, `cuts` and `bunker`, all on
-- foot.
--
-- The first player to walk up to the map's way on (`map.exitX`,
-- `map.exitY`) finishes a level, and its EXIT star leads on to the next
-- level (quests' `next`), or home from the Bunker. Hyperbole's robots hold
-- the way (army.lua, from the map's `army`); so far the junk and gun
-- haulers, on the Frozen Wreck and Liar's Landing. Jerry, Yappy, the rest
-- of the army and the bosses come in later stages.

local Features = require("src.features")
local Army = require("src.features.borderline.army")

local Borderline = {
  name = "borderline",
  questId = "borderline", -- quests' `boss` on every level of the line
}

-- Tuning ------------------------------------------------------------------
Borderline.reach = 160 -- px from the way on that finishes a level

local level = nil -- on the host: { quest = id, done = bool } while a level is being played

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

function Borderline:load()
  Army.load()
end

function Borderline:serverStart()
  level = nil
end

function Borderline:serverQuestStarted(server, quest)
  if quest.boss == self.questId then
    level = { quest = quest.id, done = false }
    Army.serverStart(server, cityMap())
  end
end

function Borderline:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    level = nil
    Army.serverStop(server)
  end
end

--- Leaving the map ends the level whatever the reason; the next quest
--- (if there is one) starts its own.
function Borderline:mapChanged(_map, server)
  if server then
    level = nil
    Army.serverStop(server)
  end
  Army.clear()
end

function Borderline:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  return Army.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

--- Every enemy of the level in the world right now, for the audit (tools/audit).
function Borderline:serverEnemies(server, add)
  Army.serverEnemies(server, add)
end

function Borderline:serverFreezeArea(_server, x, y, radius, seconds)
  Army.serverFreezeArea(x, y, radius, seconds)
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

function Borderline:serverStep(server, dt)
  Army.serverStep(server, dt)
  if not level or level.done then
    return
  end
  local map = cityMap()
  if not (map and map.exitX) or not arrivedAt(server, map.exitX, map.exitY, self.reach) then
    return
  end
  level.done = true
  local quests = Features.byName.quests
  if quests then
    quests:serverComplete(server, level.quest, map.exitX, map.exitY)
  end
end

function Borderline:update(dt)
  Army.update(dt)
end

function Borderline:drawBelowCars()
  Army.drawBelowCars()
end

function Borderline:drawAboveCars()
  Army.drawAboveCars()
end

function Borderline:footstepWalkers()
  return Army.walkers()
end

Borderline.clientMessages = Army.clientMessages

--- For tests: the level under way on the host.
function Borderline.server()
  return level
end

return Borderline
