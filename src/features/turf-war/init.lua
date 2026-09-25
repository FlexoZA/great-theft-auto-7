-- Turf war: the team quest on The Lanes (docs/turf-war.md). The quests
-- feature brings everyone to the map and raises `serverQuestStarted` /
-- `questStarted` for the quest whose `boss` is "turf-war"; this feature
-- runs what happens there.
--
-- So far: sides and towers. Everyone lands in a base and is on that
-- base's side (the Southside, bottom-left, or the Northside, top-right;
-- a latecomer joins the smaller side). Rounds and blasts do nothing to
-- your own side (weapons asks `serverFriendly`). The eighteen towers on
-- the lanes (towers.lua) watch a zone round themselves and fire at any
-- enemy who steps into it; a player's rounds wear them down, a tower of
-- the same side further out on the lane covers the one behind it, and a
-- tower that comes down leaves rubble and koins. Waves of simps, the
-- vaults and the score come in their own PRs.
--
-- The host owns all of it. Clients hear each side and each fallen tower
-- reliably and every tower's aim and health at 15 Hz, build the towers
-- from the map themselves, and draw.
--
-- Messages
--   server -> all     TW_TEAM   <playerId> <team>                 that player is on side 1 or 2
--   server -> all     TW_TOWERS <tick> [<id> <hp> <aim> <flag>]...  (unreliable, 15 Hz; flag 0 scanning,
--                                                                 1 firing at someone, 2 down)
--   server -> all     TW_DOWN   <id> <byId>                       a tower came down (byId 0: nobody's doing)
--   server -> player  TW_COVERED <id>                             the tower you hit is covered by the one further out
--   server -> all     TW_OFF                                      the quest is over: nothing left to draw

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Towers = require("src.features.turf-war.towers")
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

local sv = nil -- { teams = { id -> 1 | 2 }, towers = Towers or nil (between quests), syncIn }

function TurfWar:serverStart()
  sv = { teams = {}, towers = nil, syncIn = 0 }
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
  sv.syncIn = 0
end

--- Everyone off the map: nothing left to run or draw.
function TurfWar:stop(server)
  if sv and sv.towers then
    sv.towers, sv.teams = nil, {}
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

function TurfWar:serverStep(server, dt)
  if not (sv and sv.towers) then
    return
  end
  sv.towers:update(server, dt, function(p)
    return sv.teams[p.id]
  end)
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
    local msg = Protocol.encode("TW_TOWERS", unpack(parts))
    for _, p in pairs(server.players) do
      if not p.bot then
        server:send(p, msg, true)
      end
    end
  end
end

--- Tower `t` takes `amount` from player `by`: nothing while it is covered
--- (the shooter is told, now and then), rubble and koins when it is done.
local function hurt(server, t, amount, by)
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
local notice, noticeTimer = nil, 0
local time, lastTick = 0, 0

local function clear()
  TurfWar.on = false
  TurfWar.teams, TurfWar.towers, TurfWar.list = {}, {}, {}
  notice, noticeTimer, lastTick = nil, 0, 0
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
  TW_OFF = function()
    clear()
  end,
}

return TurfWar
