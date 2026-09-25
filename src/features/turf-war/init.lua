-- Turf war: the team quest on The Lanes (docs/turf-war.md). The quests
-- feature brings everyone to the map and raises `serverQuestStarted` /
-- `questStarted` for the quest whose `boss` is "turf-war"; this feature
-- runs what happens there.
--
-- So far: sides, towers and soldiers. Everyone lands in a base and is on
-- that base's side (the Southside, bottom-left, or the Northside,
-- top-right; a latecomer joins the smaller side). Rounds and blasts do
-- nothing to your own side (weapons asks `serverFriendly`). The eighteen
-- towers on the lanes (towers.lua) watch a zone round themselves and fire
-- at any enemy inside it; a player's rounds wear them down, a tower of the
-- same side further out on the lane covers the one behind it, and a tower
-- that comes down leaves rubble and koins. Each side's creeps
-- (creeps.lua) come out of its gates in waves, walk the lanes and fight
-- whatever enemy they see, as far as a tower sees: simps with their
-- fists to begin with, and soldiers with rifles down a lane once the side
-- has broken it (every one of the other side's towers on it down). Both
-- sides send waves the whole war, so a lone player has creeps of their own
-- to march with. A creep down is a koin. Towers pick their target Dota's way: the player who hit them
-- lately, else creeps, else players. The vaults and the score come in
-- their own PRs.
--
-- The host owns all of it. Clients hear each side, each fallen tower and
-- each fallen creep reliably, every tower's aim and health and every
-- creep's position at 15 Hz, build the towers from the map themselves,
-- and draw.
--
-- Messages
--   server -> all     TW_TEAM   <playerId> <team>                 that player is on side 1 or 2
--   server -> all     TW_TOWERS <tick> [<id> <hp> <aim> <flag>]...  (unreliable, 15 Hz; flag 0 scanning,
--                                                                 1 firing at someone, 2 down)
--   server -> all     TW_DOWN   <id> <byId>                       a tower came down (byId 0: nobody's doing)
--   server -> player  TW_COVERED <id>                             the tower you hit is covered by the one further out
--   server -> all     TW_TROOPS <tick> [<id> <x> <y> <facing> <hp> <team> <flag>]...  (unreliable, 15 Hz;
--                                                                 flag: kind s soldier / m simp, then state
--                                                                 a fighting, w walking, p punching)
--   server -> all     TW_TROOP_DOWN <id> <x> <y> <angle>          a creep went down
--   server -> all     TW_OFF                                      the quest is over: nothing left to draw

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Towers = require("src.features.turf-war.towers")
local Creeps = require("src.features.turf-war.creeps")
local Render = require("src.features.turf-war.render")

local TurfWar = {
  name = "turf-war",
  priority = 993, -- HUD over the ability row (990); after quests (22), so QST_START reaches a joiner first
}

TurfWar.questId = "turf-war"

local SYNC_EVERY = 2 -- server ticks between TW_TOWERS packets
local SMOOTHING = 12 -- per second, the easing of the drawn aim
local NOTICE_TIME = 2.5 -- seconds a notice stays up
local COVERED_EVERY = 45 -- host ticks between covered notices to the same shooter from one tower

--- The map in play, if it is The Lanes.
local function arenaMap()
  local city = Features.byName["city-map"]
  local map = city and city.map
  return map and map.kind == "arena" and map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { teams = { id -> 1 | 2 }, towers = Towers or nil (between quests), creeps, waveIn, syncIn, time }
local MAX_STAINS = 60

local function fmt(v)
  return ("%.1f"):format(v)
end

function TurfWar:serverStart()
  sv = { teams = {}, towers = nil, creeps = nil, waveIn = {}, syncIn = 0, time = 0 }
end

--- The side whose fountain (x, y) is nearest.
local function sideOf(map, x, y)
  local best, bestD2
  for _, b in ipairs(map.bases) do
    local d2 = (b.fountain.x - x) ^ 2 + (b.fountain.y - y) ^ 2
    if not bestD2 or d2 < bestD2 then
      best, bestD2 = b.team, d2
    end
  end
  return best
end

local function setTeam(server, player, team)
  sv.teams[player.id] = team
  server:broadcast(Protocol.encode("TW_TEAM", player.id, team))
end

--- The quests feature took everyone to The Lanes: whoever landed in a base
--- is on its side, and the towers stand to.
function TurfWar:serverQuestStarted(server, quest)
  local map = arenaMap()
  if not (sv and quest.boss == self.questId and map) then
    return
  end
  sv.teams = {}
  local ids = {}
  for id, p in pairs(server.players) do
    if p.body then
      ids[#ids + 1] = id
    end
  end
  table.sort(ids)
  for _, id in ipairs(ids) do
    local p = server.players[id]
    local x, y = Features.bodyPose(server, p)
    setTeam(server, p, sideOf(map, x, y))
  end
  sv.towers = Towers.new(map)
  sv.creeps = Creeps.new()
  sv.waveIn = { Creeps.FIRST_WAVE, Creeps.FIRST_WAVE }
  sv.syncIn, sv.time = 0, 0
end

--- Everyone off the map: nothing left to run or draw.
function TurfWar:stop(server)
  if sv and sv.towers then
    sv.towers, sv.creeps, sv.teams = nil, nil, {}
    server:broadcast(Protocol.encode("TW_OFF"))
  end
end

function TurfWar:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    self:stop(server)
  end
end

--- Someone arriving mid-war joins the smaller side and hears who is on
--- which, and which towers are already down (quests has told them the map
--- and the quest by now).
function TurfWar:serverPlayerJoined(server, player)
  if not (sv and sv.towers) then
    return
  end
  local n = { 0, 0 }
  for id, t in pairs(sv.teams) do
    if server.players[id] and id ~= player.id then
      n[t] = n[t] + 1
    end
  end
  setTeam(server, player, n[1] <= n[2] and 1 or 2)
  if player.bot then
    return
  end
  for id, t in pairs(sv.teams) do
    if id ~= player.id then
      server:send(player, Protocol.encode("TW_TEAM", id, t))
    end
  end
  for _, t in ipairs(sv.towers.list) do
    if t.down then
      server:send(player, Protocol.encode("TW_DOWN", t.id, 0))
    end
  end
end

function TurfWar:serverPlayerLeft(_server, player)
  if sv then
    sv.teams[player.id] = nil
  end
end

--- The `serverPlayerTeam` question (docs/features.md): a player's side
--- while the war is on.
function TurfWar:serverPlayerTeam(team, _server, player)
  return team or (sv and sv.towers and sv.teams[player.id]) or nil
end

--- The `serverFriendly` question (docs/features.md): is a blow from `byId`
--- (or from something of side `team`) on `victim` between friends? Only
--- while the war is on, and only when the victim has a side.
function TurfWar:serverFriendly(_server, byId, victim, team)
  if not (sv and sv.towers) then
    return false
  end
  local side = sv.teams[victim.id]
  if not side then
    return false
  end
  if team then
    return team == side
  end
  if byId and byId ~= 0 then
    return sv.teams[byId] == side
  end
  return false
end

--- One creep down: everyone hears where, a koin lands there.
local function creepDown(server, s, by, angle)
  server:broadcast(Protocol.encode("TW_TROOP_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Creeps.DROP)
  end
  Features.call("serverKill", server, { kind = s.kind, x = s.x, y = s.y, by = by, angle = angle })
end

--- Has side `team` broken lane `lane`: every one of the other side's
--- towers on it down? Its waves down that lane are soldiers then.
function TurfWar:serverLaneBroken(team, lane)
  if not (sv and sv.towers) then
    return false
  end
  for _, t in ipairs(sv.towers.list) do
    if t.team ~= team and t.lane == lane and not t.down then
      return false
    end
  end
  return true
end

--- Each side's next wave, once its time is up: simps, and soldiers down
--- every lane the side has broken.
local function stepWaves(map, dt)
  for team = 1, 2 do
    sv.waveIn[team] = sv.waveIn[team] - dt
    if sv.waveIn[team] <= 0 then
      sv.waveIn[team] = Creeps.WAVE_EVERY
      local room = Creeps.MAX_ALIVE - sv.creeps:count(team)
      if room > 0 then
        sv.creeps:wave(map, team, math.min(room, Creeps.PER_WAVE), function(lane)
          return TurfWar:serverLaneBroken(team, lane) and "soldier" or "simp"
        end)
      end
    end
  end
end

function TurfWar:serverStep(server, dt)
  if not (sv and sv.towers) then
    return
  end
  local map = arenaMap()
  if not map then
    return
  end
  local function teamOf(p)
    return sv.teams[p.id]
  end
  sv.time = sv.time + dt
  stepWaves(map, dt)
  for _, kill in ipairs(sv.creeps:update(server, dt, map, teamOf)) do
    creepDown(server, kill.s, kill.by, kill.angle)
  end
  sv.towers:update(server, dt, teamOf, sv.creeps, sv.time)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn <= 0 then
    sv.syncIn = SYNC_EVERY
    local parts = { server.tick }
    for _, t in ipairs(sv.towers.list) do
      parts[#parts + 1] = t.id
      parts[#parts + 1] = t.hp
      parts[#parts + 1] = ("%.2f"):format(t.aim)
      parts[#parts + 1] = t.down and 2 or (t.alert and 1 or 0)
    end
    local troops = { server.tick }
    for _, s in ipairs(sv.creeps.list) do
      troops[#troops + 1] = s.id
      troops[#troops + 1] = ("%.0f"):format(s.x)
      troops[#troops + 1] = ("%.0f"):format(s.y)
      troops[#troops + 1] = ("%.2f"):format(s.facing)
      troops[#troops + 1] = ("%.0f"):format(math.max(0, s.hp))
      troops[#troops + 1] = s.team
      troops[#troops + 1] = (s.kind == "soldier" and "s" or "m") .. (s.swing > 0 and "p" or (s.alert and "a" or "w"))
    end
    local msgs = { Protocol.encode("TW_TOWERS", unpack(parts)), Protocol.encode("TW_TROOPS", unpack(troops)) }
    for _, p in pairs(server.players) do
      if not p.bot then
        for _, msg in ipairs(msgs) do
          server:send(p, msg, true)
        end
      end
    end
  end
end

--- A bullet passing through (x, y): the `serverShotAt` convention. A
--- side's own rounds (a tower's, a soldier's: `team`) fly through its
--- creeps; a player's hit anyone not on their side.
function TurfWar:serverShotAt(server, x, y, radius, by, angle, team)
  if not (sv and sv.creeps) then
    return false
  end
  local side = team or (by and by ~= 0 and sv.teams[by]) or nil
  local s, i = sv.creeps:at(x, y, radius, side)
  if not s then
    return false
  end
  if sv.creeps:hurt(s, i, Creeps.SHOT_DAMAGE, angle) then
    creepDown(server, s, by ~= 0 and by or nil, angle)
  end
  return true
end

--- A freeze landed (abilities' event): creeps inside stand stiff.
function TurfWar:serverFreezeArea(_server, x, y, radius, seconds)
  if sv and sv.creeps then
    sv.creeps:freeze(x, y, radius, seconds)
  end
end

--- Something stinks (abilities' event, every tick while it hangs): creeps
--- inside run from it for a moment.
function TurfWar:serverPanicArea(_server, x, y, radius)
  if sv and sv.creeps then
    sv.creeps:scare(x, y, radius, 1.0)
  end
end

--- Tower `t` takes `amount` from player `by`: nothing while it is covered
--- (the shooter is told, now and then), rubble and koins when it is done.
--- Either way the tower turns on the shooter for a while.
local function hurt(server, t, amount, by)
  sv.towers:hitBy(t, by, sv.time)
  local result = sv.towers:hurt(t, amount)
  if result == "covered" then
    local shooter = server.players[by]
    if shooter and not shooter.bot and server.tick - t.noticeTick >= COVERED_EVERY then
      t.noticeTick = server.tick
      server:send(shooter, Protocol.encode("TW_COVERED", t.id))
    end
  elseif result == "down" then
    server:broadcast(Protocol.encode("TW_DOWN", t.id, by))
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, t.x, t.y, Towers.DROP)
    end
  end
end

--- A round stopped at a wall (weapons' event): ours if it is a tower.
--- Nobody's rounds (another tower's) do nothing to it.
function TurfWar:serverWallHit(server, x, y, damage, by)
  if not (sv and sv.towers) or not by or by == 0 then
    return
  end
  local t = sv.towers:at(x, y, 2)
  if t and not t.down then
    hurt(server, t, damage, by)
  end
end

--- A missile went off (weapons' event): every tower it reaches takes
--- `damage` at the centre down to a third at the edge, like a car.
function TurfWar:serverBlast(server, x, y, radius, damage, by)
  if not (sv and sv.towers) or not by or by == 0 then
    return
  end
  for _, t in ipairs(sv.towers.list) do
    if not t.down then
      local d = math.max(0, math.sqrt((t.x - x) ^ 2 + (t.y - y) ^ 2) - Towers.SIZE / 2)
      if d <= radius then
        hurt(server, t, math.floor(damage * (1 - (2 / 3) * d / radius) + 0.5), by)
      end
    end
  end
end

--- For tests and other features.
function TurfWar.server()
  return sv
end

-- Client --------------------------------------------------------------------

TurfWar.on = false -- the war is on (the towers are built)
TurfWar.teams = {} -- player id -> 1 | 2, from the host
TurfWar.towers = {} -- id -> { id, x, y, team, lane, tier, hp, max, aim, daim, alert, down, flash }
TurfWar.list = {} -- the same in id order
TurfWar.troops = {} -- creep id -> { id, x, y, dx, dy, angle, hp, team, kind, alert, swing, bob }
TurfWar.stains = {} -- { x, y, angle, team, kind } where creeps fell
local notice, noticeTimer = nil, 0
local time, lastTick, lastTroopTick = 0, 0, 0
local SNAP = 150 -- px; a jump this big is a spawn, not a step

local function clear()
  TurfWar.on = false
  TurfWar.teams, TurfWar.towers, TurfWar.list = {}, {}, {}
  TurfWar.troops, TurfWar.stains = {}, {}
  notice, noticeTimer, lastTick, lastTroopTick = nil, 0, 0, 0
end

local function say(text)
  notice, noticeTimer = text, NOTICE_TIME
end

-- TW_TEAM for a war under way arrives in the same burst as START, so the
-- war is only forgotten on the way out.
function TurfWar:exitGame()
  clear()
end

--- Everyone is on The Lanes: build the towers from the map, all standing.
function TurfWar:questStarted(_client, quest)
  local map = arenaMap()
  if quest.boss ~= self.questId or not map then
    return
  end
  clear()
  self.on = true
  for i, t in ipairs(map.towers) do
    local aim = math.atan2(-t.y, -t.x)
    local tower = {
      id = i, x = t.x, y = t.y, team = t.team, lane = t.lane, tier = t.tier, hp = Towers.HEALTH, max = Towers.HEALTH,
      aim = aim, daim = aim, alert = false, down = false, flash = 0,
    }
    self.towers[i] = tower
    self.list[i] = tower
  end
end

function TurfWar:questEnded(_client, quest)
  if quest.boss == self.questId then
    clear()
  end
end

function TurfWar:update(dt)
  time = time + dt
  noticeTimer = math.max(0, noticeTimer - dt)
  if not self.on then
    return
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, t in ipairs(self.list) do
    t.daim = t.daim + Towers.angleDiff(t.aim, t.daim) * k
    t.flash = math.max(0, t.flash - dt)
  end
  for _, s in pairs(self.troops) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
    end
  end
end

function TurfWar:drawBelowCars(_client, camera)
  local map = arenaMap()
  if self.on and map then
    Render.below(self, map, camera, time)
  end
end

function TurfWar:drawAboveCars(_client, camera)
  local map = arenaMap()
  if self.on and map then
    Render.above(self, map, camera, time)
  end
end

function TurfWar:drawHUD(client)
  local map = arenaMap()
  if self.on and map then
    Render.hud(self, map, self.teams[client.myId], notice, noticeTimer)
  end
end

function TurfWar:drawOnMinimap(_client, toMap)
  local map = arenaMap()
  if self.on and map then
    Render.minimap(self, map, toMap)
  end
end

TurfWar.clientMessages = {
  TW_TEAM = function(_client, args)
    local id, team = tonumber(args[1]), tonumber(args[2])
    if id and (team == 1 or team == 2) then
      TurfWar.teams[id] = team
    end
  end,
  TW_TOWERS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick < lastTick then
      return
    end
    lastTick = tick
    for i = 2, #args - 3, 4 do
      local t = TurfWar.towers[tonumber(args[i]) or 0]
      local hp, aim, flag = tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3])
      if t and hp and aim then
        if hp < t.hp then
          t.flash = 0.25
        end
        t.hp, t.aim = hp, aim
        t.alert = flag == 1
        if flag == 2 then
          t.down, t.hp = true, 0
        end
      end
    end
  end,
  TW_DOWN = function(client, args)
    local t = TurfWar.towers[tonumber(args[1]) or 0]
    local by = tonumber(args[2])
    local map = arenaMap()
    if not (t and map) then
      return
    end
    t.down, t.hp, t.alert = true, 0, false
    local name = by and by ~= 0 and client:nameOf(by)
    if name then
      say(("%s brought down a %s tower."):format(name, map.teams[t.team].name))
    end
  end,
  TW_COVERED = function()
    say("That tower is covered. Take the one further out on its lane first.")
  end,
  TW_TROOPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick < lastTroopTick then
      return
    end
    lastTroopTick = tick
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id = tonumber(args[i])
      local x, y, angle, hp, team = tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3]),
        tonumber(args[i + 4]), tonumber(args[i + 5])
      if id and x and y and angle and hp and team then
        local s = TurfWar.troops[id]
        if not s then
          s = { id = id, dx = x, dy = y, team = team, bob = love.math.random() * 6 }
          TurfWar.troops[id] = s
        end
        local flag = args[i + 6] or ""
        s.x, s.y, s.angle, s.hp = x, y, angle, hp
        s.kind = flag:sub(1, 1) == "s" and "soldier" or "simp"
        s.alert, s.swing = flag:sub(2, 2) ~= "w", flag:sub(2, 2) == "p"
        seen[id] = true
      end
    end
    for id in pairs(TurfWar.troops) do
      if not seen[id] then
        TurfWar.troops[id] = nil -- gone: down, or the war is over for him
      end
    end
  end,
  TW_TROOP_DOWN = function(_client, args)
    local id, x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local s = TurfWar.troops[id or 0]
    if x and y then
      TurfWar.stains[#TurfWar.stains + 1] = {
        x = x, y = y, angle = angle or 0, team = s and s.team or 1, kind = s and s.kind or "simp",
      }
      if #TurfWar.stains > MAX_STAINS then
        table.remove(TurfWar.stains, 1)
      end
    end
    TurfWar.troops[id or 0] = nil
  end,
  TW_OFF = function()
    clear()
  end,
}

return TurfWar
