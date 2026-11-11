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
local Comms = require("src.features.tutorial.comms")
local Objectives = require("src.features.tutorial.objectives")
local Checkpoint = require("src.features.tutorial.checkpoint")

local Tutorial = {
  name = "tutorial",
  priority = 95, -- answers serverRespawnPoint before respawn-points (100) and the garage (994)
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
  if level then
    Comms.serverStart(level.quest)
    Objectives.serverStart(server, level.quest)
  else
    Comms.serverStop()
    Objectives.serverStop(server)
  end
  local city = Features.byName["city-map"]
  if level and not arrived and city then
    city:placePlayers(server)
  end
  arrived = false
end

function Tutorial:serverQuestEnded(server)
  level = nil
  Comms.serverStop()
  Objectives.serverStop(server)
end

--- Leaving the map ends the level whatever the reason; the next quest
--- starts its own (serverQuestStarted comes after the map change).
function Tutorial:mapChanged(_map, server)
  if server then
    level, arrived = nil, true
    Comms.serverStop()
    Objectives.serverStop(server)
  end
end

--- Weapons asks where a dead player comes back: during a level, at its
--- checkpoint (checkpoint.lua), on foot.
function Tutorial:serverRespawnPoint(spot, _server, player)
  if spot or player.bot or not level then
    return spot
  end
  return Checkpoint.spot(level.quest, player)
end

function Tutorial:serverPlayerJoined(server, player)
  Objectives.serverPlayerJoined(server, player)
end

--- The first player to reach the level's way on finishes it, once the
--- level's objectives have opened it: the exit items tick and the quests
--- feature puts the EXIT star there (on to the next level, or home).
function Tutorial:serverStep(server, dt)
  Comms.serverStep(server, dt)
  Objectives.serverStep(server, dt)
  if not level or level.done or not Objectives.serverOpen() then
    return
  end
  local exit = self.EXITS[level.quest]
  local quests = Features.byName.quests
  if not (exit and quests and quests:serverArrivedAt(server, exit.x, exit.y, self.reach)) then
    return
  end
  level.done = true
  local section = Objectives.serverSection()
  for _, item in ipairs(section and section.items or {}) do
    if item.exit then
      Objectives.serverTick(server, item.id)
    end
  end
  quests:serverComplete(server, level.quest, exit.x, exit.y)
end

-- Client --------------------------------------------------------------------

--- A tutorial level began, or one ended: whatever he was saying stops.
function Tutorial:questStarted(_client, quest)
  if levelOf[quest.id] then
    Comms.clear()
  end
end

function Tutorial:questEnded(_client, quest)
  if levelOf[quest.id] then
    Comms.clear()
  end
end

function Tutorial:exitGame()
  Comms.clear()
  Objectives.clear()
end

function Tutorial:update(dt)
  time = time + dt
  Comms.update(dt)
  Objectives.update(dt)
end

function Tutorial:drawHUD()
  local quests = Features.byName.quests
  Objectives.drawHUD(quests and quests.active)
  Comms.drawHUD()
end

--- The checkpoint, on the ground the whole level; the way on, once the
--- objectives open it and until it is reached (then the EXIT star stands
--- there instead).
function Tutorial:drawBelowCars()
  local quests = Features.byName.quests
  local active = quests and quests.active
  if active and levelOf[active] then
    Checkpoint.draw(active, time)
  end
  local exit = active and self.EXITS[active]
  if not exit or quests.done == active or not Objectives.open(active) then
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

Tutorial.clientMessages = {}
for _, part in ipairs({ Comms, Objectives }) do
  for kind, handler in pairs(part.clientMessages) do
    Tutorial.clientMessages[kind] = handler
  end
end

return Tutorial
