-- Shoeman's school of survival: the first job on a new world's board, five
-- levels chained by each quest's `next` (`tutorial-1` to `tutorial-5`).
-- Shoeman teaches moving and stamina, dodging, shooting, abilities and
-- building, and hands over the first pistol and the first ability.
-- The design, and the tick list it is built from, is docs/tutorial.md.
--
-- Every level's state lives on the host, in this feature; clients only draw
-- what the host tells them.

local Features = require("src.features")
local UI = require("src.ui")

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

-- Tuning ------------------------------------------------------------------
Tutorial.reach = 120 -- px from the way on that finishes a level

local level = nil -- on the host: { quest = id, done = bool } while a level is being played
local arrived = false -- on the host: the map changed since the last quest started (everyone is on its start)
local time = 0 -- on the client, for the way on's pulse

function Tutorial:serverStart()
  level, arrived = nil, false
end

--- A level begins. Levels 4 and 5 share the town, so level 5 starts with no
--- map change and everyone still on level 4's way on: put them back on
--- the start, as a new map would have.
function Tutorial:serverQuestStarted(server, quest)
  level = levelOf[quest.id] and { quest = quest.id, done = false } or nil
  local city = Features.byName["city-map"]
  if level and not arrived and city then
    city:placePlayers(server)
  end
  arrived = false
end

function Tutorial:serverQuestEnded()
  level = nil
end

--- Leaving the map ends the level whatever the reason; the next quest
--- starts its own (serverQuestStarted comes after the map change).
function Tutorial:mapChanged(_map, server)
  if server then
    level, arrived = nil, true
  end
end

--- The first player to reach the level's way on finishes it: the quests
--- feature puts the EXIT star there (on to the next level, or home).
function Tutorial:serverStep(server)
  if not level or level.done then
    return
  end
  local exit = self.EXITS[level.quest]
  local quests = Features.byName.quests
  if not (exit and quests and quests:serverArrivedAt(server, exit.x, exit.y, self.reach)) then
    return
  end
  level.done = true
  quests:serverComplete(server, level.quest, exit.x, exit.y)
end

function Tutorial:update(dt)
  time = time + dt
end

--- The way on, marked on the ground until it is reached (then the EXIT
--- star stands there instead).
function Tutorial:drawBelowCars()
  local quests = Features.byName.quests
  local active = quests and quests.active
  local exit = active and self.EXITS[active]
  if not exit or quests.done == active then
    return
  end
  local pulse = 0.5 + 0.5 * math.sin(time * 3)
  love.graphics.setColor(0.35, 0.95, 0.5, 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", exit.x, exit.y, self.reach)
  love.graphics.setColor(0.35, 0.95, 0.5, 0.45 + 0.35 * pulse)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", exit.x, exit.y, self.reach)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("WAY ON", exit.x - 59, exit.y - 7, 120, "center")
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.printf("WAY ON", exit.x - 60, exit.y - 8, 120, "center")
  love.graphics.setColor(1, 1, 1)
end

return Tutorial
