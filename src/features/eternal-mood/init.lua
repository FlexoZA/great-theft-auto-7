-- Eternal Mood: the pest-control job to the moon (docs/eternal-mood.md), a
-- dream of a 90s demon shooter that you wake up from. Its quests (quests'
-- "eternal-mood" and the ones after it) take everyone over its maps, all
-- in the dark; so far only Fobos Base (city-map's `fobos`).
--
-- The first player to reach the map's way on (`map.exitX`, `map.exitY`,
-- Fobos Base's hangar lift) finishes the level, and an EXIT star comes up
-- there, once the level's boss is down (Fobos Base's: the Floor Manager,
-- floor_manager.lua, standing on the lift). Heck's horde holds the way
-- (horde.lua: the possessed at their posts, the imps in the vents). The
-- Voice comes later.

local Features = require("src.features")
local RenderEternalMood = require("src.features.city-map.render_eternal_mood")
local Horde = require("src.features.eternal-mood.horde")
local FloorManager = require("src.features.eternal-mood.floor_manager")

local EternalMood = {
  name = "eternal-mood",
  priority = 27, -- its maps' props right over the map canvas (20), under skidmarks, corpses and pickups
  questId = "eternal-mood", -- the quests that are this feature's (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
EternalMood.reach = 160 -- px from the way on that finishes a level

local sv = nil -- { quest, reached } on the host while one of the levels is under way

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

function EternalMood:load()
  Horde.load()
  FloorManager.load()
end

function EternalMood:serverStart()
  sv = nil
end

function EternalMood:serverQuestStarted(server, quest)
  if quest.boss == self.questId then
    sv = { quest = quest.id, reached = false }
    local map = cityMap()
    if map then
      local nav = Horde.serverStart(server, map)
      FloorManager.serverStart(server, map, nav)
    end
  end
end

function EternalMood:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function EternalMood:mapChanged(_map, server)
  if server then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
  end
  Horde.clear()
  FloorManager.clear()
end

function EternalMood:serverPlayerJoined(server, player)
  Horde.serverPlayerJoined(server, player)
  FloorManager.serverPlayerJoined(server, player)
end

function EternalMood:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  return FloorManager.serverShotAt(server, x, y, radius, by, angle, damage)
    or Horde.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

function EternalMood:serverFreezeArea(_server, x, y, radius, seconds)
  Horde.serverFreezeArea(x, y, radius, seconds)
  FloorManager.serverFreezeArea(x, y, radius, seconds)
end

--- Has anyone got to the way on? The first one there finishes the level,
--- once its boss is down.
function EternalMood:serverStep(server, dt)
  Horde.serverStep(server, dt)
  FloorManager.serverStep(server, dt)
  local map = cityMap()
  if not (sv and not sv.reached and map and map.exitX) or FloorManager.serverLocked() then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.exitX) ^ 2 + (y - map.exitY) ^ 2 <= self.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests then
          quests:serverComplete(server, sv.quest, map.exitX, map.exitY)
        end
        return
      end
    end
  end
end

--- For tests.
function EternalMood.server()
  return sv
end

-- Client --------------------------------------------------------------------

function EternalMood:questStarted(_client, quest)
  if quest.boss == self.questId then
    Horde.clear() -- the vents shut again on a new run
    FloorManager.clear()
  end
end

function EternalMood:questEnded(_client, quest)
  if quest.boss == self.questId then
    Horde.clear()
    FloorManager.clear()
  end
end

function EternalMood:exitGame()
  Horde.clear()
  FloorManager.clear()
end

local clock = 0

function EternalMood:update(dt)
  clock = clock + dt
  Horde.update(dt)
  FloorManager.update(dt)
end

--- What `camera` sees, world px, with a margin.
local function view(camera)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local hw, hh = w / 2 / s + 120, h / 2 / s + 120
  return camera.x - hw, camera.y - hh, camera.x + hw, camera.y + hh
end

--- Is the map in play one of ours (it has a horde)?
local function ours(map)
  return map ~= nil and map.horde ~= nil and map.cover ~= nil
end

function EternalMood:drawBelowCars(_client, camera)
  local map = cityMap()
  if ours(map) and camera then
    local left, top, right, bottom = view(camera)
    RenderEternalMood.drawProps(map, left, top, right, bottom, clock)
  end
  Horde.drawVents(cityMap())
  FloorManager.drawBelowCars()
  Horde.drawBelowCars()
end

function EternalMood:drawAboveCars()
  FloorManager.drawAboveCars()
  Horde.drawAboveCars()
end

--- A strip light on the blink at `t`: on, with every so often a fault, a
--- few seconds of stutter; a `dying` one is mostly out, with flashes.
local function flicker(f, t)
  local fault = love.math.noise(t * 0.35, f.seed * 0.13) > (f.dying and 0.25 or 0.62)
  if not fault then
    return 1
  end
  local buzz = love.math.noise(t * 14, f.seed * 0.7)
  if f.dying then
    return buzz > 0.78 and 0.9 or 0.05
  end
  return buzz > 0.42 and 1 or 0.1
end

function EternalMood:drawNightLights(_client, _camera, glow)
  local map = cityMap()
  if ours(map) then
    for _, f in ipairs(map.flickers or {}) do
      local k = flicker(f, clock)
      if k > 0.02 then
        glow(f.x, f.y, f.r, f.color, f.a * k)
      end
    end
    for _, a in ipairs(map.alarms or {}) do -- the beacons, a dim red always and a flash as each comes round
      glow(a.x, a.y, 130, { 1, 0.12, 0.06 }, 0.25 + 0.75 * RenderEternalMood.alarmFlash(a, clock))
    end
    for _, s in ipairs(map.cover) do -- the reactor's core breathing
      if s.kind == "reactor" then
        local pulse = RenderEternalMood.corePulse(clock)
        glow(s.x + s.w / 2, s.y + s.h / 2, s.w * (1.8 + 0.5 * pulse), { 1, 0.45, 0.12 }, 0.5 * pulse)
      end
    end
  end
  Horde.drawNightLights(glow)
  FloorManager.drawNightLights(glow)
end

function EternalMood:drawHUD()
  FloorManager.drawHUD()
end

function EternalMood:footstepWalkers()
  return Horde.walkers()
end

EternalMood.clientMessages = {}
for _, part in ipairs({ Horde, FloorManager }) do
  for kind, handler in pairs(part.clientMessages) do
    EternalMood.clientMessages[kind] = handler
  end
end

return EternalMood
