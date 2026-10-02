-- A-Man: G-Man from Half-Life in a joke-shop disguise. The fight is a city
-- event (event.lua, listed in src/features/events); his teleport is an
-- ability (src/features/abilities/teleport.lua) he drops when he goes down.
-- His quest (quests' "a-man") starts in City 17 (city-map's `city17`).
-- This feature loads his sounds, keeps the disguise he leaves behind on
-- the ground after the event is over, puts up his intro screen when his
-- quest starts and runs its levels (city17.lua for now).
--
-- Modules
--   event.lua    the boss: the host's side and every client's
--   face.lua     his portrait, beside his boss bar and on his intro screen
--   screen.lua   his intro screen, for his quest: the portrait and what he says
--   city17.lua   the quest's first level: Combine soldiers on the checkpoints and on patrol
--   radio.lua    the soldiers' radio chatter: their lines, its sound, the bubble
--   cameo.lua    his visits to City 17's plaza: in, a horde of turrets, out
--   theme.lua    his music, while he is loose
--   turrets.lua  the sentry turrets out of his briefcase
--   sounds.lua   his noises: appear, vanish, clasp, rip, tiptoe, turret, pop

local Sounds = require("src.features.a-man.sounds")
local Event = require("src.features.a-man.event")
local Face = require("src.features.a-man.face")
local Screen = require("src.features.a-man.screen")
local City17 = require("src.features.a-man.city17")
local Radio = require("src.features.a-man.radio")

local AMan = {
  name = "a-man",
  priority = 991, -- his intro screen goes over every other HUD, like the other bosses'; under the inventory (995)
  questId = "a-man", -- the quest that is his (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
AMan.introTime = 9 -- seconds his intro screen stays up, unless a key takes it down first

local page = nil -- { line, t } while his intro screen is up
local face = nil
local time = 0

function AMan:load()
  Sounds.load()
  Radio.load()
end

function AMan:exitGame()
  Event.stopTheme()
  Event.clearRemains()
  City17.clear()
  page = nil
end

-- The levels, on the host -------------------------------------------------

function AMan:serverQuestStarted(server, quest)
  City17.serverQuestStarted(server, quest)
end

function AMan:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    City17.serverStop(server)
  end
end

--- A map change of any kind ends a level; the quest starts it again.
function AMan:mapChanged(_map, server)
  if server then
    City17.serverStop(server)
  end
end

function AMan:serverStep(server, dt)
  City17.serverStep(server, dt)
end

function AMan:serverShotAt(server, x, y, radius, by, angle, damage)
  return City17.serverShotAt(server, x, y, radius, by, angle, damage)
end

function AMan:serverFreezeArea(_server, x, y, radius, seconds)
  City17.serverFreezeArea(x, y, radius, seconds)
end

function AMan:serverPanicArea(_server, x, y, radius)
  City17.serverPanicArea(x, y, radius)
end

-- Every machine -------------------------------------------------------------

AMan.clientMessages = City17.clientMessages

--- Everyone arrived in City 17: his intro screen comes up, and his theme
--- with it, playing on till the quest is over. The first of his lines, so
--- every machine shows the same.
function AMan:questStarted(_client, quest)
  if quest.boss == self.questId then
    face = face or Face.new()
    page = { line = 1, t = self.introTime }
    City17.clear()
    Event.playTheme()
  end
end

function AMan:questEnded(_client, quest)
  if quest.boss == self.questId then
    page = nil
    City17.clear()
    Event.stopTheme()
  end
end

--- A key takes the intro screen down.
function AMan:keypressed()
  if page then
    page = nil
  end
end

--- His intro screen softens the world behind it.
function AMan:worldBlur()
  return page and 1 or 0
end

function AMan:update(dt)
  time = time + dt
  Event.updateRemains(dt)
  Event.themeVolume()
  City17.update(dt)
  if page then
    face:update(dt)
    page.t = page.t - dt
    if page.t <= 0 then
      page = nil
    end
  end
end

function AMan:drawHUD()
  if page then
    Screen.draw(face, Screen.spec(page.line), time)
  end
end

function AMan:drawBelowCars()
  Event.drawRemains()
  City17.drawBelowCars()
end

function AMan:drawAboveCars()
  City17.drawAboveCars()
end

return AMan
