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
--   and troops.lua's: CF_TROOPS, CF_DOWN, CF_SAY

local Features = require("src.features")
local Protocol = require("src.net.protocol")
local Controls = require("src.controls")
local Story = require("src.features.cyber-feud.story")
local Face = require("src.features.cyber-feud.face")
local Screen = require("src.features.cyber-feud.screen")
local Hud = require("src.features.cyber-feud.hud")
local Troops = require("src.features.cyber-feud.troops")
local Droids = require("src.features.cyber-feud.droids")
local Flyers = require("src.features.cyber-feud.flyers")
local ChaseTheme = require("src.features.cyber-feud.theme_chase")
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
  if c and c.map then
    Troops.serverStart(server, c.map, c.current, run.shard == nil)
  end
end

function CyberFeud:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    run, sv = nil, nil
    server:broadcast(Protocol.encode("CF_SHARD", 0, "quiet"))
    Troops.serverStop(server)
  end
end

--- A map change of any kind ends a level; the quest starts the next one.
function CyberFeud:mapChanged(_map, server)
  if server then
    sv = nil
    Troops.serverStop(server)
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
  local map = cityMap()
  if not (sv and map and map.exitX) then
    return
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

local chase = nil -- the chase theme's Source, rendered on first arriving on the Drop

local function musicVolume()
  return Audio.muted and 0 or Audio.volume("music")
end

local function stopChase()
  if chase then
    chase:stop()
  end
end

--- Render the chase theme, once.
local function loadChase()
  if not chase then
    chase = love.audio.newSource(ChaseTheme.render(), "static")
    chase:setLooping(true)
    chase:setRelative(true) -- never positional: the game moves the listener around
  end
end

--- The chase theme from the top, unless it is playing already.
local function startChase()
  loadChase()
  if not chase:isPlaying() then
    chase:setVolume(musicVolume())
    chase:seek(0)
    chase:play()
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
  Flyers.clear()
  stopChase()
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
  if quest.map == "drop" then
    loadChase() -- now, under the banner, not at the pickup
  end
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
      startChase() -- the chase is on
    end
    if cl.shardBy and args[2] ~= "quiet" then
      cl.zone = { name = nameOf(client, id) .. " has the Shard", kicker = "THE PACKAGE", t = 0 }
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
  if cl.level == "drop" and onLevel() then -- machines flying over, now and then
    Flyers.update(dt, client:myPose())
  end
  if chase and chase:isPlaying() then
    chase:setVolume(musicVolume()) -- the slider may move
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

--- The action key is ours at the vending machine (on-foot leaves the car alone).
function CyberFeud:actionTaken()
  return cl.near
end

function CyberFeud:keypressed(key, client)
  if cl.page then
    cl.page = nil -- any key takes her screen down
    return
  end
  if cl.near and Controls.is("enter-exit", key) and client then
    client:send(Protocol.encode("CF_TAKE"))
  end
end

--- Her intro screen softens the world behind it.
function CyberFeud:worldBlur()
  return cl.page and onLevel() and 1 or 0
end

function CyberFeud:drawBelowCars()
  if onLevel() then
    Troops.drawBelowCars()
  end
end

function CyberFeud:drawAboveCars(client)
  if not onLevel() then
    return
  end
  Troops.drawAboveCars()
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
  local text, tx, ty = Story.objective(cl.level, map, cl.shardBy ~= nil, done)
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
