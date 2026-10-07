-- The Citadel, the end of A-Man's trail (quests' "a-man-citadel", on
-- city-map's `citadel`): one catwalk up through the shaft, widening into
-- platforms on the way. The Combine hold it (city17.lua: guards on the
-- map's `posts`, its MG emplacement over the long span), with rollermines
-- on the catwalks and Hunters on the gallery and the top (the map's
-- `rollermines` and `hunterBeats`). A-Man himself waits at the top
-- (finale.lua): the first player onto the top platform brings him, and
-- beating him finishes the level (quests' `serverComplete`): the EXIT
-- star comes up where he fell.
--
-- The a-man feature (init.lua) passes its hooks on to this module.

local Features = require("src.features")
local Finale = require("src.features.a-man.finale")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man-citadel" -- the quest this level is

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == "citadel" and city.map or nil
end

function Level.serverQuestStarted(_server, quest)
  if quest.id == Level.questId and cityMap() then
    Finale.serverStart()
  end
end

function Level.serverStop(server)
  Finale.serverStop(server)
end

function Level.serverStep(server, dt)
  local map = cityMap()
  if map then
    Finale.serverStep(server, dt, map)
  end
end

function Level.serverShotAt(server, x, y, radius, by, angle, damage)
  return Finale.serverShotAt(server, x, y, radius, by, angle, damage)
end

function Level.serverFreezeArea(x, y, radius, seconds)
  Finale.serverFreezeArea(x, y, radius, seconds)
end

function Level.serverPanicArea(x, y, radius)
  Finale.serverPanicArea(x, y, radius)
end

-- Every machine: A-Man, his turrets, his boss bar.
Level.clientMessages = Finale.clientMessages
Level.clear = Finale.clear
Level.update = Finale.update
Level.drawBelowCars = Finale.drawBelowCars
Level.drawAboveCars = Finale.drawAboveCars
Level.drawHUD = Finale.drawHUD
Level.where = Finale.where

return Level
