-- Cyber Feud: the courier job into Grey City (docs/cyber-feud.md). Its
-- quests (quests' "cyber-feud" and the four after it) take everyone over
-- five maps, city-map's `drop`, `market`, `overpass`, `tower` and `roof`,
-- all at night.
--
-- The story so far (the words are in story.lua):
--   - Arriving on a map, everyone gets its banner (hud.lua): GREY CITY, where
--     in the line it is, its name and tagline; on every map but the Drop,
--     VEX's intro screen comes first (screen.lua, her face in face.lua),
--     with the quest's `introLine`.
--   - On the Drop the package is in the vending machine by the garage: the
--     first player to press the action key there (F) takes the Shard and carries it for the rest of the line (a green
--     diamond over them). Once someone has it and is halfway up the map
--     (`map.vexY`), VEX boots up: her intro screen, in your earpiece.
--   - The host raises story beats once each per level (`Story.beats`):
--     walking into a part of the map (`map.zones`), the Overpass's dead end
--     (`map.knot`), the far end. Each is something VEX says on the comms.
--   - Walking or driving into a new part of the map puts its name up.
--   - The objective line says what to do next and how far it is.
--   - The Overpass's theme (theme_overpass.lua, darksynth) starts on every
--     screen as Kilowatt's rig roars past (KW_RIDE, or CF_MUSIC for a
--     player joining after), and plays until the map changes.
--   - Halcyon Tower's theme (theme_tower.lua, industrial groove metal)
--     starts on every screen the moment the tower wakes (CF_WAKE: a player
--     walking past the reception), and plays until the map changes.
--   - The Market's theme (theme_market.lua, heavy metal) starts on every
--     screen the moment the Market wakes (CF_WAKE: a player walking up out
--     of the tunnel), and plays until the map changes. Rendered on arrival.
--   - On the Drop, the chase theme (theme_chase.lua, rock) starts on every
--     screen the moment someone takes the Shard, and plays until the map
--     changes. It is rendered on arriving there, so the pickup doesn't stall.
-- The factions hold the streets (troops.lua): on the Drop, Halcyon's
-- officers on the roadblocks and the Static's gangers on the corners and
-- walking their blocks, at war with each other. They stay calm until
-- someone takes the Shard (or a player hurts one of them), then come for
-- whoever is nearest, a player or the other side. On the Market, Halcyon
-- holds the south gate and the east side and the Static their chop shop in
-- the west; both wake when a player walks up out of the tunnel's mouth.
-- Over the Drop, every now and then, a flying machine crosses the sky
-- (flyers.lua): scenery, on each screen by itself.
-- The tunnel end is Halcyon's alone, guarded by its assassin droids
-- (droids.lua): the Hunters' brain, quicker, dodging every round.
-- Each level is still only the way through: the first player to reach the
-- map's far end (`map.exitX`, `map.exitY`), with the Shard taken on the
-- Drop, finishes it, and an EXIT star comes up there leading on to the next
-- (quests' `next`), or home from the Roof. The other maps' troops, the
-- breach and the bosses come later.
--
-- Messages
--   client -> server  CF_TAKE               (take the Shard out of the vending machine)
--   server -> all     CF_SHARD <id> [quiet] (who carries the Shard; 0 nobody; quiet: no notice, for a joiner)
--   server -> all     CF_BEAT  <key>        (a story beat: one of Story.beats)
--   and gates.lua's: GATE_WORK, GATE_PROG, GATE_OPEN, GATE_VEX, GATE_ROOM (the Overpass's roadblocks, the
--   tower's stair doors), and troops.lua's turrets' TUR_WORK, brutes' BRT_WORK and VEX's VX_WORK
--   server -> all     CF_WAKE               (troops.lua's: the street woke; on the Market, its theme starts)
--   server -> one     CF_MUSIC              (to a player joining a level whose theme is on: start it)
--   and troops.lua's: CF_TROOPS, CF_DOWN, CF_SAY (and its enforcers' ENF_STATE, ENF_BLOCK, ENF_DOWN,
--   its interceptors' INT_UNITS, its war-rigs' RIG_UNITS, KW_RIDE, KW_LEAP, KW_EXIT,
--   its rippers' RIP_STATE, RIP_CUT, RIP_DOWN,
--   its sparkers' SPK_STATE, SPK_LOB, SPK_EMP, SPK_DOWN,
--   its watcher drones' WCH_STATE, WCH_CALL, WCH_DOWN, its sting drones' STG_STATE, STG_DOWN,
--   and its marksmen's MRK_STATE, MRK_SHOT, MRK_DOWN)

local Features = require("src.features")
local Protocol = require("src.net.protocol")
local Controls = require("src.controls")
local Story = require("src.features.cyber-feud.story")
local Face = require("src.features.cyber-feud.face")
local Screen = require("src.features.cyber-feud.screen")
local Hud = require("src.features.cyber-feud.hud")
local Troops = require("src.features.cyber-feud.troops")
local Interceptors = require("src.features.cyber-feud.interceptors")
local WarRigs = require("src.features.cyber-feud.war_rigs")
local Gates = require("src.features.cyber-feud.gates")
local Turrets = require("src.features.cyber-feud.turrets")
local Brutes = require("src.features.cyber-feud.brutes")
local Kilowatt = require("src.features.cyber-feud.kilowatt")
local Saye = require("src.features.cyber-feud.saye")
local Vex = require("src.features.cyber-feud.vex")
local Droids = require("src.features.cyber-feud.droids")
local Flyers = require("src.features.cyber-feud.flyers")
local ChaseTheme = require("src.features.cyber-feud.theme_chase")
local MarketTheme = require("src.features.cyber-feud.theme_market")
local OverpassTheme = require("src.features.cyber-feud.theme_overpass")
local TowerTheme = require("src.features.cyber-feud.theme_tower")
local Audio = require("src.audio")

local CyberFeud = {
  name = "cyber-feud",
  priority = 991, -- VEX's intro screen over the HUD and the ability bar (990), like A-Man's; under the inventory (995)
  questId = "cyber-feud", -- the quests that are this feature's (quests' `boss`)
}

-- Tuning ------------------------------------------------------------------
CyberFeud.reach = 160 -- px from the far end that finishes a level
CyberFeud.takeRadius = 110 -- px from the vending machine that takes the Shard
CyberFeud.introTime = 9 -- seconds VEX's intro screen stays up on arrival, unless a key takes it down
CyberFeud.bootTime = 6 -- seconds it stays up when she boots up mid-run on the Drop

local SLACK = 60 -- px the host allows for a taker drawn a little behind where it is

local function city()
  return Features.byName["city-map"]
end

local function cityMap()
  local c = city()
  return c and c.map
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server ------------------------------------------------------------------

local run = nil -- { shard = player id or nil } on the host for the whole line
local sv = nil -- { quest, map, reached, beats = { [key] = true } } on the host while a level is under way

function CyberFeud:load()
  Flyers.load() -- the flying machines' engines, synthesised
  require("src.features.cyber-feud.enforcers").load() -- the ping of a round off a riot shield
  require("src.features.cyber-feud.rippers").load() -- the rippers' blades
  require("src.features.cyber-feud.sparkers").load() -- the sparkers' EMPs
  require("src.features.cyber-feud.watchers").load() -- the watcher drones' call
  Gates.load() -- the key that asks VEX to open a tower door
  Brutes.load() -- the thump of a brute's arm
  require("src.features.cyber-feud.kilowatt").load() -- and of Kilowatt's
end

function CyberFeud:serverStart()
  run, sv = nil, nil
end

function CyberFeud:serverQuestStarted(server, quest)
  if quest.boss ~= self.questId then
    return
  end
  if quest.id == self.questId or not run then
    run = { shard = nil } -- the line starts again: the Shard is back in its machine
    server:broadcast(Protocol.encode("CF_SHARD", 0, "quiet"))
  end
  local c = city()
  sv = { quest = quest.id, map = c and c.current, reached = false, beats = {} }
  Gates.serverStart()
  if c and c.map then
    -- Calm until the Shard is taken, on the map it is taken on.
    Troops.serverStart(server, c.map, c.current, run.shard == nil and c.map.pickupX ~= nil)
  end
end

function CyberFeud:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    run, sv = nil, nil
    server:broadcast(Protocol.encode("CF_SHARD", 0, "quiet"))
    Troops.serverStop(server)
    Gates.serverStop()
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function CyberFeud:mapChanged(_map, server)
  if server then
    sv = nil
    Troops.serverStop(server)
    Gates.serverStop()
  end
  self:clearLevel()
end

--- Raise story beat `key` (one of Story.beats) if this level has not had it.
local function beat(server, key)
  if not Story.beats[key] or sv.beats[key] then
    return
  end
  if sv.map == "drop" and key ~= "drop.boot" and not sv.beats["drop.boot"] then
    return -- she is not in your earpiece yet: it waits
  end
  sv.beats[key] = true
  server:broadcast(Protocol.encode("CF_BEAT", key))
end

local function zoneAt(map, y)
  for _, z in ipairs(map.zones or {}) do
    if y >= z.y0 and y < z.y1 then
      return z
    end
  end
  return nil
end

function CyberFeud:serverStep(server, dt)
  Troops.serverStep(server, dt)
  Gates.serverStep(server, dt)
  local map = cityMap()
  if not (sv and map and map.exitX) then
    return
  end
  if Vex.serverGone() and not sv.reached then -- she got away: the job's done, HOME on the helipad
    sv.reached = true
    local quests = Features.byName.quests
    if quests then
      quests:serverComplete(server, sv.quest, map.exitX, map.exitY)
    end
    beat(server, sv.map .. ".end")
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local z = zoneAt(map, y)
      if z then
        beat(server, sv.map .. "." .. z.name)
      end
      if map.vexY and run.shard and y < map.vexY then
        beat(server, "drop.boot")
      end
      local k = map.knot
      if k and x >= k.x and x < k.x + k.w and y >= k.y and y < k.y + k.h then
        beat(server, sv.map .. ".knot")
      end
      local ready = not map.pickupX or run.shard ~= nil -- the Drop wants the Shard taken first
      ready = ready and not (Kilowatt.serverUp() or Saye.serverUp() or Vex.serverUp()) -- the Roof: all of them gone
      if ready and not sv.reached and dist2(x, y, map.exitX, map.exitY) <= self.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests then
          quests:serverComplete(server, sv.quest, map.exitX, map.exitY)
        end
        beat(server, sv.map .. ".end")
      end
    end
  end
end

function CyberFeud:serverPlayerJoined(server, player)
  if run and run.shard and server.started and not player.bot then
    server:send(player, Protocol.encode("CF_SHARD", run.shard, "quiet"))
  end
  if Troops.serverAwake() and not player.bot then
    server:send(player, Protocol.encode("CF_WAKE")) -- the level's music, if it is on
  end
  Interceptors.serverPlayerJoined(server, player)
  WarRigs.serverPlayerJoined(server, player)
  Gates.serverPlayerJoined(server, player)
  Vex.serverPlayerJoined(server, player)
  local rigs = WarRigs.server()
  if rigs and rigs.cameo and rigs.cameo.stage ~= "waiting" and not player.bot then
    server:send(player, Protocol.encode("CF_MUSIC")) -- the Overpass's theme is on
  end
end

--- Halcyon's interceptors and the Static's war-rigs are drivers like
--- players, but no enemy goes after them.
function CyberFeud:serverHidden(_server, player)
  return Interceptors.isOne(player) or WarRigs.isOne(player)
end

--- The carrier left: the Shard passes to another human still here, if any.
function CyberFeud:serverPlayerLeft(server, player)
  if not (run and run.shard == player.id) then
    return
  end
  run.shard = nil
  for id, p in pairs(server.players) do
    if id ~= player.id and not p.bot then
      run.shard = id
      break
    end
  end
  server:broadcast(Protocol.encode("CF_SHARD", run.shard or 0))
end

CyberFeud.serverMessages = {
  CF_TAKE = function(server, player)
    local map = cityMap()
    if not (sv and run and not run.shard and map and map.pickupX and Features.present(player)) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, map.pickupX, map.pickupY) > (CyberFeud.takeRadius + SLACK) ^ 2 then
      return
    end
    run.shard = player.id
    server:broadcast(Protocol.encode("CF_SHARD", player.id))
    Troops.serverWake() -- both sides come for it
  end,
}
for kind, handler in pairs(Gates.serverMessages) do
  CyberFeud.serverMessages[kind] = handler
end
for kind, handler in pairs(Turrets.serverMessages) do
  CyberFeud.serverMessages[kind] = handler
end
for kind, handler in pairs(Brutes.serverMessages) do
  CyberFeud.serverMessages[kind] = handler
end
for kind, handler in pairs(Vex.serverMessages) do
  CyberFeud.serverMessages[kind] = handler
end

function CyberFeud:serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  return Troops.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
end

--- A player's or a bot's gun went off: the assassin droids hear it.
function CyberFeud:serverShotFired(_server, player, x, y)
  Droids.serverShotFired(player, x, y)
end

function CyberFeud:serverFreezeArea(_server, x, y, radius, seconds)
  Troops.serverFreezeArea(x, y, radius, seconds)
end

function CyberFeud:serverPanicArea(_server, x, y, radius)
  Troops.serverPanicArea(x, y, radius)
end

-- Client ------------------------------------------------------------------

-- Each level's theme, and what starts it: on the Drop the Shard being
-- taken, on the Market and in the tower the place waking, on the Overpass
-- Kilowatt's rig roaring past (war_rigs.lua's KW_RIDE).
local THEMES = { drop = ChaseTheme, market = MarketTheme, overpass = OverpassTheme, tower = TowerTheme }
local music = {} -- map name -> its theme's Source, rendered on first arriving there

local function musicVolume()
  return Audio.muted and 0 or Audio.volume("music")
end

local function stopMusic()
  for _, source in pairs(music) do
    source:stop()
  end
end

--- Render `level`'s theme, once, if it has one.
local function loadMusic(level)
  if THEMES[level] and not music[level] then
    local source = love.audio.newSource(THEMES[level].render(), "static")
    source:setLooping(true)
    source:setRelative(true) -- never positional: the game moves the listener around
    music[level] = source
  end
end

--- `level`'s theme from the top, unless it is playing already.
local function startMusic(level)
  loadMusic(level)
  local source = music[level]
  if source and not source:isPlaying() then
    source:setVolume(musicVolume())
    source:seek(0)
    source:play()
  end
end

local face = nil
local time = 0
local cl = {
  level = nil, -- the map name of the level on, while one is
  page = nil, -- { line, t, max } while VEX's intro screen is up
  banner = nil, -- { spec, t } the map banner, waiting for the page to go or up
  zone = nil, -- { name, kicker, t } the part of the map just entered
  myZone = false, -- the name of the part I am in; false until the first look
  says = {}, -- what VEX has still to say, in order
  say = nil, -- { text, t } what she is saying
  shardBy = nil, -- the player carrying the Shard
  near = false, -- at the vending machine, with the Shard still in it
}

function CyberFeud:clearLevel()
  cl.page, cl.banner, cl.zone, cl.myZone, cl.says, cl.say, cl.near = nil, nil, nil, false, {}, nil, false
  Troops.clear()
  Interceptors.clear()
  WarRigs.clear()
  Gates.clear()
  Flyers.clear()
  stopMusic()
end

function CyberFeud:exitGame()
  self:clearLevel()
  cl.level, cl.shardBy = nil, nil
end

--- Everyone arrived on one of the maps: VEX's intro screen (not on the
--- Drop: she isn't in your earpiece yet), then the map's banner.
function CyberFeud:questStarted(_client, quest)
  if quest.boss ~= self.questId then
    return
  end
  face = face or Face.new()
  self:clearLevel()
  cl.level = quest.map
  loadMusic(quest.map) -- now, under the banner, not when it starts
  if quest.introLine then
    cl.page = { line = Story.lines[quest.introLine] or Story.lines[1], t = 0, max = self.introTime }
  end
  local b = Story.banners[quest.map]
  if b then
    cl.banner = { spec = { n = b.n, of = Story.LEVELS, title = b.title, tagline = b.tagline }, t = 0 }
  end
end

function CyberFeud:questEnded(_client, quest)
  if quest.boss == self.questId then
    self:clearLevel()
    cl.level, cl.shardBy = nil, nil
  end
end

local function nameOf(client, id)
  local p = client.players[id]
  return p and p.name or "Someone"
end

CyberFeud.clientMessages = {
  CF_SHARD = function(client, args)
    local id = tonumber(args[1]) or 0
    cl.shardBy = id > 0 and id or nil
    if cl.shardBy and cl.level == "drop" then
      startMusic("drop") -- the chase is on
    end
    if cl.shardBy and args[2] ~= "quiet" then
      cl.zone = { name = nameOf(client, id) .. " has the Shard", kicker = "THE PACKAGE", t = 0 }
    end
  end,
  CF_WAKE = function()
    if cl.level == "market" or cl.level == "tower" then
      startMusic(cl.level) -- they know you're here
    end
  end,
  CF_MUSIC = function()
    if cl.level and THEMES[cl.level] then
      startMusic(cl.level) -- joining a level whose theme is on already
    end
  end,
  CF_BEAT = function(_client, args)
    local b = Story.beats[args[1] or ""]
    if not b then
      return
    end
    face = face or Face.new()
    if b.screen then
      cl.page = { line = Story.lines[b.screen], t = 0, max = CyberFeud.bootTime }
    end
    if b.say then
      cl.says[#cl.says + 1] = b.say
    end
  end,
}
for kind, handler in pairs(Interceptors.clientMessages) do
  CyberFeud.clientMessages[kind] = handler
end
for kind, handler in pairs(WarRigs.clientMessages) do
  CyberFeud.clientMessages[kind] = handler
end
for kind, handler in pairs(Gates.clientMessages) do
  CyberFeud.clientMessages[kind] = handler
end
do -- Kilowatt's rig roaring past is the Overpass's cue
  local ride = CyberFeud.clientMessages.KW_RIDE
  CyberFeud.clientMessages.KW_RIDE = function(client, args)
    ride(client, args)
    if cl.level == "overpass" then
      startMusic("overpass")
    end
  end
end
for kind, handler in pairs(Troops.clientMessages) do
  CyberFeud.clientMessages[kind] = handler
end

--- Is the level on this screen one of ours, on the map it belongs to?
local function onLevel()
  local c = city()
  return cl.level ~= nil and c ~= nil and c.current == cl.level
end

function CyberFeud:update(dt, client)
  time = time + dt
  Troops.update(dt)
  Interceptors.update(dt)
  WarRigs.update(dt, client)
  if onLevel() then
    Gates.update(dt, client)
    Turrets.update(dt, client)
    Brutes.update(dt, client)
    Vex.update(dt, client)
  end
  if cl.level == "drop" and onLevel() then -- machines flying over, now and then
    Flyers.update(dt, client:myPose())
  end
  for _, source in pairs(music) do
    if source:isPlaying() then
      source:setVolume(musicVolume()) -- the slider may move
    end
  end
  if not (face and onLevel()) then
    return
  end
  face:update(dt)
  if cl.page then
    cl.page.t = cl.page.t + dt
    if cl.page.t >= cl.page.max then
      cl.page = nil
    end
    return -- the rest waits for her screen to go
  end
  if cl.banner then
    cl.banner.t = cl.banner.t + dt
    if cl.banner.t >= Hud.BANNER_TIME then
      cl.banner = nil
    end
  end
  if cl.zone then
    cl.zone.t = cl.zone.t + dt
    if cl.zone.t >= Hud.ZONE_TIME then
      cl.zone = nil
    end
  end
  if cl.say then
    cl.say.t = cl.say.t + dt
    if cl.say.t >= #cl.say.text / Screen.TYPE_RATE + Hud.SAY_HOLD then
      cl.say = nil
    end
  elseif #cl.says > 0 then
    cl.say = { text = table.remove(cl.says, 1), t = 0 }
  end
  -- Where I am: a new part of the map puts its name up (not the first, on
  -- arrival: the banner says where I am), and the machine's prompt.
  local map = cityMap()
  local x, y = client:myPose()
  cl.near = false
  if not (map and x) then
    return
  end
  local z = zoneAt(map, y)
  local name = z and z.name or nil
  if cl.myZone ~= false and name and name ~= cl.myZone and not cl.banner then
    local kicker
    for i, f in ipairs(map.floors or {}) do
      if f == z then
        kicker = ("FLOOR %d OF %d"):format(i, #map.floors)
      end
    end
    cl.zone = { name = name, kicker = kicker, t = 0 }
  end
  if name or cl.myZone == false then
    cl.myZone = name
  end
  cl.near = map.pickupX ~= nil and not cl.shardBy
    and dist2(x, y, map.pickupX, map.pickupY) <= self.takeRadius ^ 2
end

--- The action key is ours at the vending machine, and at a roadblock's
--- panel, a tower door's terminal, a turret or a brute (on-foot leaves the car alone).
function CyberFeud:actionTaken()
  return cl.near or Gates.actionTaken() or Turrets.actionTaken() or Brutes.actionTaken() or Vex.actionTaken()
end

function CyberFeud:keypressed(key, client)
  if cl.page then
    cl.page = nil -- any key takes her screen down
    return
  end
  if cl.near and Controls.is("enter-exit", key) and client then
    client:send(Protocol.encode("CF_TAKE"))
  end
  if client and onLevel() then
    Gates.keypressed(key, client)
  end
end

--- Her intro screen softens the world behind it.
function CyberFeud:worldBlur()
  return cl.page and onLevel() and 1 or 0
end

function CyberFeud:drawBelowCars()
  if onLevel() then
    Gates.drawBelowCars()
    Troops.drawBelowCars()
  end
end

function CyberFeud:drawAboveCars(client)
  if not onLevel() then
    return
  end
  Troops.drawAboveCars()
  Interceptors.drawAboveCars(client)
  WarRigs.drawAboveCars(client)
  Flyers.draw() -- high over everything
  local map = cityMap()
  if map and map.pickupX and not cl.shardBy then
    Hud.drawMachine(map.pickupX, map.pickupY - 34, time)
  end
  if cl.shardBy then
    local x, y = client:pose(cl.shardBy)
    if x then
      Hud.drawCarrier(x, y, time)
    end
  end
end

--- At night (the night feature), the Shard glows over whoever carries it.
function CyberFeud:drawNightLights(client, _camera, glow)
  if onLevel() then
    Troops.drawNightLights(glow)
    Gates.drawNightLights(glow)
    Interceptors.drawNightLights(client, glow)
    WarRigs.drawNightLights(client, glow)
    Flyers.lights(glow)
  end
  if cl.shardBy and onLevel() then
    local x, y = client:pose(cl.shardBy)
    if x then
      glow(x, y - 40, 70, Face.GREEN, 0.9)
    end
  end
end

function CyberFeud:drawHUD(client)
  if not (face and onLevel()) then
    return
  end
  if cl.page then
    Screen.draw(face, cl.page.line, cl.page.t, time)
    return
  end
  local map = cityMap()
  local quests = Features.byName.quests
  local done = quests and quests.done ~= nil and quests.done == quests.active
  local bosses = Kilowatt.up() and (Saye.up() and "Kilowatt and Saye" or "Kilowatt") or (Saye.up() and "Saye")
  local text, tx, ty = Story.objective(cl.level, map, cl.shardBy ~= nil, done, bosses)
  local vexOn, relaysLeft = Vex.active()
  if vexOn and not done then
    local x, y = client:myPose()
    text = ("Objective: breach VEX's relays (%d left)"):format(relaysLeft)
    tx, ty = Vex.nearestRelay(x, y)
  end
  if text then
    local x, y = client:myPose()
    Hud.drawObjective(text, tx and x and math.sqrt(dist2(x, y, tx, ty)) or nil)
  end
  if cl.say then
    local hold = #cl.say.text / Screen.TYPE_RATE + Hud.SAY_HOLD
    Hud.drawComms(face, cl.say.text, cl.say.t, math.min(1, (hold - cl.say.t) / 0.5))
  end
  if cl.near then
    Hud.drawPrompt(Controls.name(Controls.bindings("enter-exit")[1]))
  end
  Gates.drawHUD()
  Turrets.drawHUD()
  Brutes.drawHUD()
  Vex.drawHUD()
  Kilowatt.drawHUD()
  Saye.drawHUD(Kilowatt.up() and 1 or 0) -- over his
  if cl.banner then
    Hud.drawBanner(cl.banner.spec, cl.banner.t)
  elseif cl.zone then
    Hud.drawZone(cl.zone.name, cl.zone.kicker, cl.zone.t)
  end
end

--- The footsteps feature's hook: the factions' soldiers walking about.
function CyberFeud:footstepWalkers()
  return onLevel() and Troops.walkers() or {}
end

--- For tests.
function CyberFeud.server()
  return sv, run
end

return CyberFeud
