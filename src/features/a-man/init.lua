-- A-Man: G-Man from Half-Life in a joke-shop disguise. The fight is a city
-- event (event.lua, listed in src/features/events); his teleport is an
-- ability (src/features/abilities/teleport.lua) he drops when he goes down.
-- His quest (quests' "a-man") starts in City 17 (city-map's `city17`).
-- This feature loads his sounds, keeps the disguise he leaves behind on
-- the ground after the event is over, puts up his intro screen when his
-- quest starts and runs its levels (city17.lua; the Outer City has no
-- level of its own yet; road.lua; citadel.lua, for later).
--
-- Modules
--   event.lua    the boss: the host's side and every client's
--   face.lua     his portrait, beside his boss bar and on his intro screen
--   screen.lua   his intro screen, for his quest: the portrait and what he says
--   city17.lua   the quest's first level: Combine soldiers on the checkpoints and on patrol
--   detour.lua   him stepping in at the Citadel's doors and sending everyone to the Outer City
--   road.lua     the Winding Road: the drive up to the pass
--   citadel.lua  the end of the trail, for later: the catwalk up through the Citadel
--   radio.lua    the soldiers' radio chatter: their lines, its sound, the bubble
--   cameo.lua    his visits to City 17's plaza: in, a horde of turrets, out
--   theme.lua    his music, while he is loose, and City 17's
--   theme_outercity.lua, theme_coast.lua   the Outer City's music and the Coast's
--   turrets.lua  the sentry turrets out of his briefcase
--   nests.lua    the Coast's MG nests' guns, drawn (city17.lua mans them)
--   corpses.lua  the Combine's dead, lying where they fell
--   sounds.lua   his noises: appear, vanish, clasp, rip, tiptoe, turret, pop

local Sounds = require("src.features.a-man.sounds")
local Event = require("src.features.a-man.event")
local Face = require("src.features.a-man.face")
local Screen = require("src.features.a-man.screen")
local City17 = require("src.features.a-man.city17")
local Citadel = require("src.features.a-man.citadel")
local Road = require("src.features.a-man.road")
local Detour = require("src.features.a-man.detour")
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
  Road.serverQuestStarted(server, quest)
  Citadel.serverQuestStarted(server, quest)
end

function AMan:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    City17.serverStop(server)
    Road.serverStop()
    Citadel.serverStop()
    Detour.serverStop()
  end
end

--- A map change of any kind ends a level; the quest starts it again.
function AMan:mapChanged(_map, server)
  if server then
    City17.serverStop(server)
    Road.serverStop()
    Citadel.serverStop()
    Detour.serverStop()
  end
end

function AMan:serverStep(server, dt)
  City17.serverStep(server, dt)
  Road.serverStep(server)
  Citadel.serverStep(server)
  Detour.serverStep(server, dt)
end

--- Quests' hook: the trip on from City 17 waits for him (detour.lua).
function AMan:serverHoldTrip(server, quest, player)
  return Detour.serverHoldTrip(server, quest, player)
end

--- Combine soldiers set down round (x, y) on the level that is on (city17.lua's serverDrop).
function AMan:serverDropTroops(server, x, y, count)
  return City17.serverDrop(server, x, y, count)
end

--- Combine soldiers still up inside rectangle `r` ({ x, y, w, h }) on the level that is on.
function AMan:serverTroopsIn(_server, r)
  return City17.serverTroopsIn(r)
end

--- A-Man drops in near the player nearest (x, y), opens his case (out
--- comes whatever `opened(server, x, y)` brings) and blinks out (cameo.lua).
function AMan:serverVisit(server, x, y, opened)
  return City17.serverVisit(server, x, y, opened)
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
    page = { line = quest.introLine or 1, t = self.introTime }
    City17.clear()
    Event.playTheme(quest.map)
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

--- The footsteps feature's hook: who of mine is walking about, and where.
function AMan:footstepWalkers()
  local list = {}
  for id, s in pairs(City17.troops()) do
    list[#list + 1] = { key = id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

return AMan
