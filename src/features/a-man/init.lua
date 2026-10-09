-- A-Man: G-Man from Half-Life in a joke-shop disguise. The fight is a city
-- event (event.lua, listed in src/features/events); his teleport is an
-- ability (src/features/abilities/teleport.lua) he drops when he goes down.
-- His quest (quests' "a-man") starts in City 17 (city-map's `city17`).
-- This feature loads his sounds, keeps the disguise he leaves behind on
-- the ground after the event is over, puts up his intro screen when his
-- quest starts and runs its levels: city17.lua runs the Combine soldiers
-- on all five maps of his trail (City 17, the Outer City, the Coast, the
-- Winding Road, the Citadel), road.lua the Winding Road and citadel.lua the
-- Citadel, where he is the last fight himself (finale.lua).
--
-- Modules
--   event.lua    the boss: the host's side and every client's
--   brain.lua    his brain, the event's and the finale's: stalk, blink, open the case, medkits, dodging
--   face.lua     his portrait, beside his boss bar and on his intro screen
--   screen.lua   his intro screen, for his quest: the portrait and what he says
--   city17.lua   the quest's first level, and the Combine soldiers on every map of it
--   combine.lua  the Combine soldiers' brain
--   detour.lua   him stepping in at the Citadel's doors and sending everyone to the Outer City
--   road.lua     the Winding Road: the drive up to the pass
--   citadel.lua  the end of the trail: the catwalk up through the Citadel
--   finale.lua   A-Man himself at the top of it, the last fight: his case holds the trail's enemies
--   upkeep.lua   the Citadel's computers ticking over and its repair drones flying round
--   radio.lua    the soldiers' radio chatter: their lines, its sound, the bubble
--   cameo.lua    his visits to City 17's plaza (in, a horde of turrets, out), and called-in
--                ones on any level (the Hunter-Chopper's Hunters)
--   theme.lua    his music, while he is loose, and City 17's
--   theme_outercity.lua, theme_coast.lua, theme_road.lua, theme_citadel.lua
--                the Outer City's music, the Coast's, the Winding Road's and the Citadel's
--   turrets.lua  the sentry turrets out of his briefcase
--   nests.lua    the MG nests' guns (the Coast's, the Winding Road's, the Citadel's), drawn
--                (city17.lua mans them)
--   corpses.lua  the Combine's dead, lying where they fell
--   sounds.lua   his noises: appear, vanish, clasp, rip, tiptoe, turret, pop; a Combine door

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
  Citadel.clear()
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
    Citadel.serverStop(server)
    Detour.serverStop()
  end
end

--- Stop every level on the host (`server` may be nil: nobody to tell).
local function stopLevels(server)
  if server then
    City17.serverStop(server)
  end
  Road.serverStop()
  Citadel.serverStop(server)
  Detour.serverStop()
end

--- A new game: nothing of the last one's levels carries over.
function AMan:serverStart(server)
  stopLevels(server)
end

--- A map change of any kind ends a level; the quest starts it again. What
--- every screen shows of the old map goes with it, the host's too (its own
--- client never hears the clearing messages in time to trust them).
function AMan:mapChanged(_map, server)
  if server then
    stopLevels(server)
  end
  City17.clear()
  Citadel.clear()
  Event.clearRemains()
end

function AMan:serverStep(server, dt)
  City17.serverStep(server, dt)
  Road.serverStep(server)
  Citadel.serverStep(server, dt)
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

function AMan:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  return City17.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
    or Citadel.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

function AMan:serverFreezeArea(_server, x, y, radius, seconds)
  City17.serverFreezeArea(x, y, radius, seconds)
  Citadel.serverFreezeArea(x, y, radius, seconds)
end

function AMan:serverPanicArea(_server, x, y, radius)
  City17.serverPanicArea(x, y, radius)
  Citadel.serverPanicArea(x, y, radius)
end

-- Every machine -------------------------------------------------------------

AMan.clientMessages = {}
for _, handlers in ipairs({ City17.clientMessages, Citadel.clientMessages }) do
  for kind, handler in pairs(handlers) do
    AMan.clientMessages[kind] = handler
  end
end

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
    Citadel.clear()
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
  Citadel.update(dt)
  if page then
    face:update(dt)
    page.t = page.t - dt
    if page.t <= 0 then
      page = nil
    end
  end
end

function AMan:drawHUD()
  Citadel.drawHUD()
  if page then
    Screen.draw(face, Screen.spec(page.line), time)
  end
end

function AMan:drawBelowCars()
  Event.drawRemains()
  City17.drawBelowCars()
  Citadel.drawBelowCars()
end

function AMan:drawAboveCars()
  City17.drawAboveCars()
  Citadel.drawAboveCars()
end

--- The footsteps feature's hook: who of mine is walking about, and where.
function AMan:footstepWalkers()
  local list = {}
  for id, s in pairs(City17.troops()) do
    list[#list + 1] = { key = id, x = s.dx, y = s.dy, size = "person" }
  end
  local hx, hy = Citadel.where()
  if hx then
    list[#list + 1] = { key = "a-man", x = hx, y = hy, size = "person" }
  end
  return list
end

return AMan
