-- A-Man: G-Man from Half-Life in a joke-shop disguise. The fight is a city
-- event (event.lua, listed in src/features/events); his teleport is an
-- ability (src/features/abilities/teleport.lua) he drops when he goes down.
-- This feature loads his sounds and keeps the disguise he leaves behind
-- on the ground after the event is over.
--
-- Modules
--   event.lua    the boss: the host's side and every client's
--   face.lua     his portrait, beside his boss bar and on his intro screen
--   screen.lua   his intro screen, for his quest: the portrait and what he says
--   theme.lua    his music, while he is loose
--   turrets.lua  the sentry turrets out of his briefcase
--   sounds.lua   his noises: appear, vanish, clasp, rip, tiptoe, turret, pop

local Sounds = require("src.features.a-man.sounds")
local Event = require("src.features.a-man.event")

local AMan = {
  name = "a-man",
}

function AMan:load()
  Sounds.load()
end

function AMan:exitGame()
  Event.clearRemains()
end

function AMan:update(dt)
  Event.updateRemains(dt)
end

function AMan:drawBelowCars()
  Event.drawRemains()
end

return AMan
