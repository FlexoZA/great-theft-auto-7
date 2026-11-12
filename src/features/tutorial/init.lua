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
local ShoemanRender = require("src.features.tutorial.shoeman_render")
local StartGear = require("src.features.tutorial.start_gear")
local Traffic = require("src.features.tutorial.traffic")
local Road = require("src.features.tutorial.road")
local Shoe = require("src.features.tutorial.shoe")
local Pistol = require("src.features.tutorial.pistol")

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
-- `tutorial-*` maps' `map.exitX, exitY`: on the road's lawn past the
-- streets, at the park's gate, at the scrap yard's gate; the town is still
-- a placeholder field): reaching it finishes the level and the EXIT star
-- comes up there. Levels 4 and 5 share the town.
Tutorial.EXITS = {
  ["tutorial-1"] = { x = 0, y = -1216 },
  ["tutorial-2"] = { x = 0, y = -1184 },
  ["tutorial-3"] = { x = 832, y = -1056 },
  ["tutorial-4"] = { x = 0, y = -1024 },
  ["tutorial-5"] = { x = 0, y = -1024 },
}

-- Where Shoeman stands on each level, world px: just south-east of the
-- checkpoint, between it and the HOME star (each built map's
-- `map.shoemanX, shoemanY`); in the park, the middle of the lawn, the
-- checkpoint 768 px south; in the scrap yard, on the pad in its bottom-left
-- corner. Stage 7 moves him with the town. On
-- level 2 his shoes (shoe.lua) fly from here.
Tutorial.SHOEMAN = {
  ["tutorial-1"] = { x = 160, y = 888 },
  ["tutorial-2"] = { x = 0, y = 0 },
  ["tutorial-3"] = { x = -736, y = 1016 },
  ["tutorial-4"] = { x = 160, y = 184 },
  ["tutorial-5"] = { x = 160, y = 184 },
}

--- The level number (1 to 5) of quest `id`, or nil when it is not a tutorial level.
function Tutorial.level(id)
  return levelOf[id]
end

-- Tuning ------------------------------------------------------------------
Tutorial.reach = 120 -- px from the way on that finishes a level
Tutorial.turnRate = 4 -- radians a second Shoeman turns to keep his eye on the nearest player

local level = nil -- on the host: { quest = id, done = bool } while a level is being played
local arrived = false -- on the host: the map changed since the last quest started (everyone is on its start)
local time = 0 -- on the client, for the way on's pulse
local facing = -math.pi / 2 -- on the client, where Shoeman looks

function Tutorial:serverStart(server)
  level, arrived = nil, false
  Traffic.serverClear(server)
  Shoe.serverStop()
  Pistol.serverStop()
  StartGear.serverStart(server)
end

--- A level begins. Levels 4 and 5 share the town, so level 5 starts with no
--- map change and everyone still on level 4's way on: put them back on
--- the start, as a new map would have.
function Tutorial:serverQuestStarted(server, quest)
  level = levelOf[quest.id] and { quest = quest.id, done = false } or nil
  Shoe.serverStop()
  Pistol.serverStop()
  local city = Features.byName["city-map"]
  if level then
    Comms.serverStart(level.quest)
    Objectives.serverStart(server, level.quest)
    local at = level.quest == "tutorial-2" and Tutorial.SHOEMAN[level.quest]
    if at then
      Shoe.serverStart(at.x, at.y)
      Objectives.serverTimer(server, "dodge", Shoe.serverNextIn())
    end
    -- The scrap yard: he puts a pistol down for everyone, in front of him.
    local map = city and city.map
    if level.quest == "tutorial-3" and map and map.dropX then
      Pistol.serverStart(map.dropX, map.dropY)
    end
  else
    Comms.serverStop()
    Objectives.serverStop(server)
  end
  if level and not arrived and city then
    city:placePlayers(server)
  end
  arrived = false
end

function Tutorial:serverQuestEnded(server)
  level = nil
  Shoe.serverStop()
  Pistol.serverStop()
  Comms.serverStop()
  Objectives.serverStop(server)
end

--- Leaving the map ends the level whatever the reason; the next quest
--- starts its own (serverQuestStarted comes after the map change).
function Tutorial:mapChanged(_map, server)
  if server then
    level, arrived = nil, true
    Traffic.serverClear(server)
    Shoe.serverStop()
    Pistol.serverStop()
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

--- Weapons asks who takes a wreck: a traffic car is simply gone.
function Tutorial:serverWreckClaimed(_server, car)
  return Traffic.claim(car)
end

--- The map in play when it is level 1's road with its lanes, else nil.
local function road()
  local city = Features.byName["city-map"]
  local map = level and level.quest == "tutorial-1" and city and city.map
  return map and map.lanes and map or nil
end

--- A player died: on level 1 that was a car, on level 2 a shoe (nothing
--- else kills there), and Shoeman has something to say about it the
--- first time.
function Tutorial:serverKill(server, kill)
  if not (level and kill.victim) then
    return
  end
  if level.quest == "tutorial-1" then
    Comms.serverBeat(server, "flat")
  elseif level.quest == "tutorial-2" then
    Comms.serverBeat(server, "hit")
  end
end

--- On-foot says somebody dodged: a shoe in the air at them notes it.
function Tutorial:serverDodged(_server, player)
  Shoe.serverDodged(player)
end

-- What the shoes tell this feature (Shoe.serverStep's `on`): the shout as
-- he winds up, with the countdown to the next; a dodge ticks the objective,
-- and the fifth opens the way on and ends the throwing.
local shoeEvents = {
  threw = function(server)
    Comms.serverBeat(server, "dodge", true)
    Objectives.serverTimer(server, "dodge", Shoe.serverNextIn())
  end,
  dodged = function(server)
    if not Objectives.serverTick(server, "dodge") then
      return
    end
    if Objectives.serverOpen() then
      -- Five: the way on is open, and he puts the shoes down.
      Shoe.serverHalt()
      Objectives.serverTimer(server, "dodge", nil)
      Comms.serverBeat(server, "open")
    else
      Comms.serverBeat(server, "dodged")
    end
  end,
}

-- What the pistol lesson tells this feature (Pistol.serverStep's `on`):
-- every human picks theirs up and equips it, each ticked for them; the
-- first to do either hears the next step.
local pistolEvents = {
  picked = function(server, player)
    if Objectives.serverTickPlayer(server, "pickup", player) then
      Comms.serverBeat(server, "picked")
    end
  end,
  equipped = function(server, player)
    if Objectives.serverDidPlayer("pickup", player) and Objectives.serverTickPlayer(server, "equip", player) then
      Comms.serverBeat(server, "equipped")
    end
  end,
}

function Tutorial:serverPlayerJoined(server, player)
  Objectives.serverPlayerJoined(server, player)
  StartGear.serverPlayerJoined(server, player)
end

function Tutorial:serverPlayerLeft(_server, player)
  StartGear.serverPlayerLeft(player)
end

--- The first player to reach the level's way on finishes it, once the
--- level's objectives have opened it: the exit items tick and the quests
--- feature puts the EXIT star there (on to the next level, or home).
function Tutorial:serverStep(server, dt)
  Comms.serverStep(server, dt)
  Objectives.serverStep(server, dt)
  StartGear.serverStep(server)
  local map = road()
  Traffic.serverStep(server, map)
  if map then
    Road.serverStep(server, map)
  end
  Shoe.serverStep(server, dt, shoeEvents)
  Pistol.serverStep(server, dt, pistolEvents)
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
    Shoe.clear()
  end
end

function Tutorial:questEnded(_client, quest)
  if levelOf[quest.id] then
    Comms.clear()
    Shoe.clear()
  end
end

function Tutorial:exitGame()
  Comms.clear()
  Shoe.clear()
  Objectives.clear()
end

--- The nearest player to (x, y) on this screen: their x, y, or nil.
local function nearest(client, x, y)
  local bx, by, best = nil, nil, math.huge
  for id in pairs(client.bodies or {}) do
    local px, py = Features.clientBodyPose(client, id)
    local d = px and (px - x) ^ 2 + (py - y) ^ 2
    if d and d < best then
      bx, by, best = px, py, d
    end
  end
  return bx, by
end

--- Shoeman turns towards the nearest player, never faster than `turnRate`.
local function turn(client, dt)
  local quests = Features.byName.quests
  local at = quests and quests.active and Tutorial.SHOEMAN[quests.active]
  if not at then
    return
  end
  local px, py = nearest(client, at.x, at.y)
  if not px then
    return
  end
  local want = math.atan2(py - at.y, px - at.x)
  local d = (want - facing + math.pi) % (2 * math.pi) - math.pi
  local step = Tutorial.turnRate * dt
  facing = facing + math.max(-step, math.min(step, d))
end

function Tutorial:update(dt, client)
  time = time + dt
  turn(client, dt)
  Shoe.update(dt)
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

--- Weapons asks which cars go without a health bar: on level 1's road
--- every car is traffic (players' own are stowed on a walked map), and
--- the bars would show over the tunnel roofs.
function Tutorial:carBarHidden()
  local quests = Features.byName.quests
  local city = Features.byName["city-map"]
  return quests ~= nil and quests.active == "tutorial-1" and city ~= nil and city.map ~= nil
    and city.map.lanes ~= nil
end

--- Shoeman, standing on the level's map with the other walkers, or
--- throwing (he faces the way the shoe goes), and his shoes.
function Tutorial:drawAboveCars()
  local quests = Features.byName.quests
  local at = quests and quests.active and self.SHOEMAN[quests.active]
  if at then
    local throw, angle = Shoe.pose()
    if angle then
      facing = angle -- and he carries on looking that way afterwards
    end
    ShoemanRender.draw(at.x, at.y, facing, { throw = throw })
  end
  Shoe.draw(at and at.x, at and at.y)
end

Tutorial.clientMessages = {}
for _, part in ipairs({ Comms, Objectives, Shoe }) do
  for kind, handler in pairs(part.clientMessages) do
    Tutorial.clientMessages[kind] = handler
  end
end

return Tutorial
