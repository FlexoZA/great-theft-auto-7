-- Eternal Mood: the pest-control job to the moon (docs/eternal-mood.md), a
-- dream of a 90s demon shooter that you wake up from. Its quests (quests'
-- "eternal-mood" and the ones after it) take everyone over its maps, all
-- in the dark, all of them on foot; so far Fobos Base, Heck on Earth and
-- the Foundry (city-map's `fobos`, `earth` and `foundry`; the Foundry's
-- conveyor belts carry whoever stands on them, belts.lua).
--
-- The first player to reach the map's way on (`map.exitX`, `map.exitY`,
-- Fobos Base's hangar lift, Earth's starport gate) finishes the level, and
-- an EXIT star comes up there, once the level's boss is down (Fobos Base's:
-- the Floor Manager, floor_manager.lua, standing on the lift; Earth's
-- comes later). Heck's horde holds the way (horde.lua: the possessed at
-- their posts, the imps in the vents and manholes, the interns' mobs). The
-- Voice's intro screen opens every level.

local Features = require("src.features")
local RenderEternalMood = require("src.features.city-map.render_eternal_mood")
local Horde = require("src.features.eternal-mood.horde")
local Face = require("src.features.eternal-mood.face")
local Screen = require("src.features.eternal-mood.screen")
local Story = require("src.features.eternal-mood.story")
local FobosTheme = require("src.features.eternal-mood.theme_fobos")
local EarthTheme = require("src.features.eternal-mood.theme_earth")
local Audio = require("src.audio")
local FloorManager = require("src.features.eternal-mood.floor_manager")
local Mancubus = require("src.features.eternal-mood.mancubus")
local Baron = require("src.features.eternal-mood.baron")
local Belts = require("src.features.eternal-mood.belts")
local Ground = require("src.features.eternal-mood.ground")

local EternalMood = {
  name = "eternal-mood",
  priority = 27, -- its maps' props right over the map canvas (20), under skidmarks, corpses and pickups
  questId = "eternal-mood", -- the quests that are this feature's (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
EternalMood.reach = 160 -- px from the way on that finishes a level
EternalMood.introTime = 10 -- seconds the Voice's intro screen stays up on arrival, unless a key takes it down

local sv = nil -- { quest, reached } on the host while one of the levels is under way
local clock = 0 -- seconds, on this screen: what moves on the map and the intro screen

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

local page = nil -- { line, t, level, face } while the Voice's intro screen is up

-- Each level's theme (by map), played from the moment the Voice's intro
-- screen goes: its intro once, then its loop. Rendered on arriving, under
-- the intro screen. The Foundry borrows Fobos Base's until it has its own.
local THEMES = { fobos = FobosTheme, earth = EarthTheme, foundry = FobosTheme }
local music = {} -- map name -> { intro, loop } Sources
local playing = nil -- the map whose theme is on

local function musicVolume()
  return Audio.muted and 0 or Audio.volume("music")
end

local function loadMusic(level)
  local theme = THEMES[level]
  for other, m in pairs(music) do -- rendered already for another level
    if not music[level] and THEMES[other] == theme then
      music[level] = m
    end
  end
  if theme and not music[level] then
    local loop = love.audio.newSource(theme.render(), "static")
    loop:setLooping(true)
    loop:setRelative(true) -- never positional: the game moves the listener around
    local intro = theme.renderIntro and love.audio.newSource(theme.renderIntro(), "static")
    if intro then
      intro:setRelative(true)
    end
    music[level] = { intro = intro, loop = loop }
  end
end

local function stopMusic()
  for _, m in pairs(music) do
    m.loop:stop()
    if m.intro then
      m.intro:stop()
    end
  end
  playing = nil
end

--- `level`'s theme from the top: its intro, then the loop (update starts it).
local function startMusic(level)
  loadMusic(level)
  local m = music[level]
  if not m or playing == level then
    return
  end
  stopMusic()
  playing, m.introDone = level, nil
  local first = m.intro or m.loop
  first:setVolume(musicVolume())
  first:seek(0)
  first:play()
end

--- The intro screen is going: the level's theme comes in.
local function closePage()
  page = nil
  local map = cityMap()
  if map and map.horde and map.name then
    startMusic(map.name)
  end
end

function EternalMood:load()
  Horde.load()
  FloorManager.load()
  Mancubus.load()
  Baron.load()
  Screen.load()
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
      Mancubus.serverStart(server, map, nav)
      Baron.serverStart(server, map, nav)
    end
  end
end

function EternalMood:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
    Mancubus.serverStop(server)
    Baron.serverStop(server)
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function EternalMood:mapChanged(_map, server)
  if server then
    sv = nil
    Horde.serverStop(server)
    FloorManager.serverStop(server)
    Mancubus.serverStop(server)
    Baron.serverStop(server)
  end
  Horde.clear()
  FloorManager.clear()
  Mancubus.clear()
  Baron.clear()
  stopMusic()
end

function EternalMood:serverPlayerJoined(server, player)
  Horde.serverPlayerJoined(server, player)
  FloorManager.serverPlayerJoined(server, player)
  Mancubus.serverPlayerJoined(server, player)
  Baron.serverPlayerJoined(server, player)
end

function EternalMood:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  return FloorManager.serverShotAt(server, x, y, radius, by, angle, damage)
    or Mancubus.serverShotAt(server, x, y, radius, by, angle, damage)
    or Baron.serverShotAt(server, x, y, radius, by, angle, damage)
    or Horde.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

function EternalMood:serverFreezeArea(_server, x, y, radius, seconds)
  Horde.serverFreezeArea(x, y, radius, seconds)
  FloorManager.serverFreezeArea(x, y, radius, seconds)
  Mancubus.serverFreezeArea(x, y, radius, seconds)
  Baron.serverFreezeArea(x, y, radius, seconds)
end

--- Has anyone got to the way on? The first one there finishes the level,
--- once its boss is down.
function EternalMood:serverStep(server, dt)
  Horde.serverStep(server, dt)
  FloorManager.serverStep(server, dt)
  Mancubus.serverStep(server, dt)
  Baron.serverStep(server, dt)
  local map = cityMap()
  if sv then
    Belts.serverStep(server, map, dt, Horde.server())
    Ground.serverStep(server, dt)
  end
  local locked = FloorManager.serverLocked() or Mancubus.serverLocked() or Baron.serverLocked()
  if not (sv and not sv.reached and map and map.exitX) or locked then
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


--- Everyone arrived on one of the levels: the Voice's intro screen, the
--- Mood Slayer drowsier the further down the dream it is.
function EternalMood:questStarted(_client, quest)
  if quest.boss == self.questId then
    Horde.clear() -- the vents shut again on a new run
    FloorManager.clear()
    Mancubus.clear()
    Baron.clear()
    if quest.introLine then
      local level = quest.introLine
      page = { line = Story.lines[level] or Story.lines[1], t = 0, level = level,
        face = Face.new(0.2 + (level - 1) / (Story.LEVELS - 1) * 0.75) }
      Screen.sting()
    end
    stopMusic()
    loadMusic(quest.map) -- now, under the intro screen, not when it starts
    if not page then
      closePage()
    end
  end
end

--- Any key takes the intro screen down.
function EternalMood:keypressed()
  if page then
    closePage()
  end
end

--- The intro screen softens the world behind it.
function EternalMood:worldBlur()
  return page and 1 or 0
end

--- The intro screen, over the whole HUD.
function EternalMood:drawScreen()
  if page then
    Screen.draw(page.face, page.line, page.t, clock, page.level)
  end
end

function EternalMood:questEnded(_client, quest)
  if quest.boss == self.questId then
    Horde.clear()
    FloorManager.clear()
    Mancubus.clear()
    Baron.clear()
    page = nil
    stopMusic()
  end
end

function EternalMood:exitGame()
  Horde.clear()
  FloorManager.clear()
  Mancubus.clear()
  Baron.clear()
  page = nil
  stopMusic()
end

function EternalMood:update(dt)
  clock = clock + dt
  if page then
    page.t = page.t + dt
    page.face:update(dt)
    if page.t >= self.introTime then
      closePage()
    end
  end
  local m = playing and music[playing]
  if m then
    if m.intro and not m.intro:isPlaying() and not m.loop:isPlaying() and m.introDone ~= playing then
      m.introDone = playing -- the dream is over: rip and tear
      m.loop:seek(0)
      m.loop:play()
    end
    m.loop:setVolume(musicVolume()) -- the slider may move
    if m.intro then
      m.intro:setVolume(musicVolume())
    end
  end
  Horde.update(dt)
  FloorManager.update(dt)
  Mancubus.update(dt)
  Baron.update(dt)
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
  Mancubus.drawBelowCars()
  Baron.drawBelowCars()
  Horde.drawBelowCars()
end

function EternalMood:drawAboveCars()
  FloorManager.drawAboveCars()
  Mancubus.drawAboveCars()
  Baron.drawAboveCars()
  Horde.drawAboveCars()
end

--- A strip light on the blink at `t`: on, with every so often a fault, a
--- few seconds of stutter; a `dying` one is mostly out, with flashes. A
--- `fire` never goes out, only dances.
local function flicker(f, t)
  if f.fire then
    return 0.65 + 0.25 * love.math.noise(t * 3.1, f.seed * 0.21) + 0.1 * love.math.noise(t * 11, f.seed)
  end
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
    for _, s in ipairs(map.cover) do -- the reactor's core breathing, the Crater's lava too
      if s.kind == "reactor" or s.kind == "crater" or s.kind == "crucible" then
        local pulse = RenderEternalMood.corePulse(clock)
        glow(s.x + s.w / 2, s.y + s.h / 2, s.w * (1.8 + 0.5 * pulse), { 1, 0.45, 0.12 }, 0.5 * pulse)
      end
    end
  end
  Horde.drawNightLights(glow)
  FloorManager.drawNightLights(glow)
  Mancubus.drawNightLights(glow)
  Baron.drawNightLights(glow)
end

function EternalMood:drawHUD()
  FloorManager.drawHUD()
  Mancubus.drawHUD()
  Baron.drawHUD()
end

function EternalMood:footstepWalkers()
  return Horde.walkers()
end

EternalMood.clientMessages = {}
for _, part in ipairs({ Horde, FloorManager, Mancubus, Baron }) do
  for kind, handler in pairs(part.clientMessages) do
    EternalMood.clientMessages[kind] = handler
  end
end

return EternalMood
