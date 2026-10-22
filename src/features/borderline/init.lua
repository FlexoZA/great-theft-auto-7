-- Borderline: the long walk to Handsome Jerry's bunker on Pandoria
-- (docs/borderline.md). Its quests (quests' "borderline" and the seven
-- after it) take everyone over eight maps, city-map's `wreck`, `landing`,
-- `pit`, `prosperity`, `refinery`, `assembly`, `cuts` and `bunker`, all on
-- foot.
--
-- The first player to walk up to the map's way on (`map.exitX`,
-- `map.exitY`) finishes a level, and its EXIT star leads on to the next
-- level (quests' `next`), or home from the Bunker. Hyperbole's robots hold
-- the way (army.lua, from the map's `army`). Handsome Jerry and YAP-TP tell
-- the story as it goes (tale.lua: Jerry's intro screen, the banners, their
-- lines over the comms, the objective line). The maps' moving parts (the
-- cranes, the beacons) are works.lua's, their themes music.lua's; a halo
-- hangs over what the objective line is after (halo.lua). The bosses come
-- later.
--
-- A level with terminals (the Frozen Wreck's) keeps its way on shut until
-- they are hacked (the terminals feature); hacking one sets off an alarm
-- the army near it hears, and shuts down the hauler dock it runs.

local Features = require("src.features")
local UI = require("src.ui")
local Army = require("src.features.borderline.army")
local Tale = require("src.features.borderline.tale")
local Works = require("src.features.borderline.works")
local Music = require("src.features.borderline.music")
local Halo = require("src.features.borderline.halo")
local Terminals = require("src.features.terminals")

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

--- What the objective line is after on this screen, while it is up: none
--- under Jerry's screen or off the line's levels (halo.lua).
local function objectives()
  local map = cityMap()
  if not Tale.onLevel(map) or Tale.blurring(map) then
    return {}
  end
  local quests = Features.byName.quests
  return Halo.objectives(map, quests ~= nil and quests.done ~= nil and quests.done == quests.active)
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
    Terminals.serverOpen(cityMap(), Army.nav(), Army.serverAlarm)
    Tale.serverStart(cityMap())
  end
end

function Borderline:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    level = nil
    Army.serverStop(server)
    Terminals.serverClose()
    Tale.serverStop()
  end
end

--- Leaving the map ends the level whatever the reason; the next quest
--- (if there is one) starts its own.
function Borderline:mapChanged(_map, server)
  if server then
    level = nil
    Army.serverStop(server)
    Tale.serverStop()
  end
  Army.clear()
end

--- A terminal hacked (the terminals feature): the dock it runs shuts down.
function Borderline:serverTerminalDone(server, terminal, player)
  if level and terminal.dock then
    Army.serverShutDock(server, terminal.dock, player and player.id)
  end
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
  Tale.serverStep(server, map, Army.alerted(), dt)
  if not (map and map.exitX) or Terminals.serverLocked()
    or not arrivedAt(server, map.exitX, map.exitY, self.reach) then
    return
  end
  level.done = true
  Tale.serverBeat(server, "end")
  local quests = Features.byName.quests
  if quests then
    quests:serverComplete(server, level.quest, map.exitX, map.exitY)
  end
end

function Borderline:serverKill(server, kill)
  Tale.serverKill(server, kill)
end

function Borderline:questStarted(_client, quest)
  if quest.boss == self.questId then
    Tale.questStarted(quest)
  end
end

function Borderline:questEnded(_client, quest)
  if quest.boss == self.questId then
    Tale.clear()
    Music.stop()
  end
end

function Borderline:exitGame()
  Tale.clear()
  Army.clear()
  Music.stop()
end

function Borderline:update(dt, client)
  Army.update(dt)
  Works.update(dt)
  local y = nil
  if client then
    y = select(2, client:myPose())
  end
  local map = cityMap()
  Tale.update(dt, map, y)
  Music.update(map, Tale.onLevel(map), Tale.blurring(map))
  Halo.update(dt)
end

--- Any key takes Jerry's intro screen down.
function Borderline:keypressed()
  Tale.keypressed()
end

--- Jerry's intro screen softens the world behind it.
function Borderline:worldBlur()
  return Tale.blurring(cityMap()) and 1 or 0
end

--- Jerry's intro screen goes over every HUD piece.
function Borderline:drawScreen()
  Tale.drawScreen(cityMap())
end

function Borderline:drawHUD(client)
  local quests = Features.byName.quests
  local done = quests ~= nil and quests.done ~= nil and quests.done == quests.active
  local x, y = client:myPose()
  Tale.drawHUD(cityMap(), done, x, y)
end

function Borderline:drawBelowCars()
  local map = cityMap()
  if map then
    Works.drawBelowCars(map)
  end
  Army.drawBelowCars()
end

function Borderline:drawAboveCars()
  Army.drawAboveCars()
  local map = cityMap()
  if map then
    Works.drawAboveCars(map)
  end
  Halo.draw(objectives())
end

function Borderline:drawNightLights(_client, _camera, glow)
  local map = cityMap()
  if map then
    Works.drawNightLights(map, glow)
  end
  Halo.drawNightLights(objectives(), glow)
end

--- The map's areas on the minimap and the big map (`w` px wide): a dashed
--- line where one meets the next, each one's name in it, the one I am in
--- tinted gold.
local function drawAreas(client, map, toMap, w)
  local _, myY = client:myPose()
  local font = w > 300 and UI.fonts.body or UI.fonts.small
  love.graphics.setFont(font)
  for _, z in ipairs(map.zones or {}) do
    local x0, y0 = toMap(z.x0, z.y0)
    local x1, y1 = toMap(z.x1, z.y1)
    local mine = myY and myY >= z.y0 and myY < z.y1
    if mine then
      love.graphics.setColor(1, 0.84, 0.32, 0.12)
      love.graphics.rectangle("fill", x0, y0, x1 - x0, y1 - y0)
    end
    if z.y0 > map.top then
      love.graphics.setColor(1, 1, 1, 0.6)
      for x = x0, x1, 10 do
        love.graphics.rectangle("fill", x, y0 - 0.5, 6, 1.5)
      end
    end
    local name = z.name:upper()
    love.graphics.setColor(0, 0, 0, 0.75)
    love.graphics.print(name, x0 + 5, y0 + 4)
    if mine then
      love.graphics.setColor(1, 0.84, 0.32)
    else
      love.graphics.setColor(1, 1, 1, 0.85)
    end
    love.graphics.print(name, x0 + 4, y0 + 3)
  end
  love.graphics.setColor(1, 1, 1)
end

--- On the minimap and the big map: the map's areas, and the halo's ring
--- round each objective.
function Borderline:drawOnMinimap(client, toMap, w)
  local map = cityMap()
  if Tale.onLevel(map) then
    drawAreas(client, map, toMap, w)
  end
  Halo.drawOnMinimap(objectives(), toMap)
end

function Borderline:footstepWalkers()
  return Army.walkers()
end

Borderline.clientMessages = {}
for _, part in ipairs({ Army, Tale }) do
  for kind, handler in pairs(part.clientMessages) do
    Borderline.clientMessages[kind] = handler
  end
end

--- For tests: the level under way on the host.
function Borderline.server()
  return level
end

return Borderline
