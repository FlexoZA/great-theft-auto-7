-- D-Day landing: the third boss quest. Everyone wades ashore at the bottom
-- of Looz'er Beach (city-map's "beach") and has to fight up the map to the
-- flag on the hilltop, through four bands:
--
--   1. The beach: open sand strewn with tank stoppers and sandbag walls to
--      hide behind from the eyes above. Mortars fall on it all the while,
--      a ring on the sand showing where each one will land.
--   2. Bunkers and trenches: guards in the bunker embrasures and the gaps
--      in the trench sandbags sweep thirty-degree cones of sight over the
--      beach. Walk into one and he turns to follow you and opens fire, for
--      as long as he can see you, and comes after you when you duck out of
--      sight (brain.lua: the Combine soldiers' brain, in other uniforms).
--      One who spots you calls in the nearest few others; one going down
--      brings everyone near enough to hear it to look.
--   3. Barracks: guards by the huts, and riflemen coming out of the doors
--      every few seconds, walking down towards the nearest player and
--      firing at whoever they spot.
--   4. The hilltop: more guards, and the flag. Reach it and Major Looz'er's
--      portrait comes up on every screen; then he fights (major.lua, his
--      brain major_brain.lua). He has the MG nest, the same ability a
--      player can buy, and badly hurt he goes for a medkit.
--
-- When he goes down he spills a pile of koins, the quest is done, the flag
-- turns to yours, and quests puts an EXIT star home where he fell.
--
-- The Colosseum's waves bring them onto its sand too (`serverArenaSend`,
-- colosseum/waves.lua): riflemen coming in at the far end and hunting
-- everyone, with mortars falling near the players, and the Major with
-- riflemen coming in after him while he stands. Stage "arena" there, and
-- "boss" while he fights; no flag, no portrait.
--
-- The quests feature brings everyone to the beach and raises
-- `serverQuestStarted` / `questStarted` for the quest whose `boss` is
-- "d-day"; every client starts the beach's march (theme.lua) until the
-- quest ends. The host owns all of it: the stage, every soldier, the mortars,
-- the Major. Clients hear the stage reliably and positions at 15 Hz, and
-- draw. Bullets reach the soldiers and the Major through `serverShotAt`;
-- their own rounds (owner 0) fly through each other.
--
-- Messages
--   server -> all  DD_STAGE  <stage> <line>          none | assault | reveal | boss | done (line: the
--                                                    portrait's speech, Major.lines[line], for reveal)
--   server -> all  DD_TROOPS <tick> [<id> <x> <y> <facing> <hp> <flags>]...   (unreliable, 15 Hz;
--                                                    flags g/r guard/rifleman, upper case when alert)
--   server -> all  DD_DOWN   <id> <x> <y> <angle> <cause>   a soldier went down (cause: the damage type)
--   server -> all  DD_AIM    <x> <y> <radius> <delay>  a mortar is coming down here
--   server -> all  DD_BLAST  <x> <y> <radius>        it landed
--   server -> all  DD_MAJOR  <tick> <x> <y> <facing> <hp> <max> <stamina> <winded>   (unreliable, 15 Hz)
--   server -> all  DD_SAY    <line>                  the Major says Major.lines[line]
--   server -> all  DD_NEST   <x> <y> <angle>         the Major put an MG nest down
--   server -> all  DD_MAJOR_DOWN <x> <y> <angle>     the Major went down

local Protocol = require("src.net.protocol")
local Audio = require("src.audio")
local Features = require("src.features")
local Soldiers = require("src.features.d-day.brain")
local Major = require("src.features.d-day.major")
local Face = require("src.features.d-day.major_face")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Render = require("src.features.d-day.render")
local Corpses = require("src.features.corpses")
local Sounds = require("src.features.d-day.sounds")
local Theme = require("src.features.d-day.theme")

local Dday = {
  name = "d-day",
  priority = 992, -- the portrait goes over every other HUD, the ability row (990) too; under the inventory (995)
}

-- Tuning ------------------------------------------------------------------
Dday.questId = "d-day"
Dday.guards = 16 -- guards on their posts for one player (more humans, more: bosses/init.lua)...
Dday.maxGuards = 26 -- ...as far as the posts go
Dday.aware = 150 -- px all round them they notice somebody in, any way they face
Dday.callHeard = 800 -- px; soldiers this near where one spotted somebody come when he calls it in
Dday.callAnswer = 3 -- how many of them come at most, nearest first
Dday.callEvery = 15 -- seconds before the same soldier calls again
Dday.downHeard = 700 -- px; soldiers this near one who goes down go to look
Dday.riflemen = 4 -- most riflemen out at once for one player (more humans, more)
Dday.reinforceEvery = 7 -- seconds between riflemen coming out of the barracks
Dday.mortarEvery = { 1.4, 3.0 } -- seconds between mortars, at random in this range
Dday.mortarFirst = 4 -- seconds after landing before the first
Dday.mortarDelay = 1.3 -- seconds the ring shows before it lands
Dday.mortarRadius = 95 -- px
Dday.mortarDamage = 45 -- at the centre, falling to a third at the edge
Dday.mortarAimed = 0.5 -- the chance a mortar is dropped near someone on the beach rather than anywhere on it
Dday.mortarNear = 170 -- px from them it can land
Dday.flagRadius = 110 -- px from the flag that counts as reaching it
Dday.revealTime = 7 -- seconds of portrait before the Major moves
Dday.bulletDamage = 20 -- what one round takes off the Major (matches the pistol)
Dday.soldierDrops = 1 -- koins a soldier drops, like a pedestrian

local SYNC_EVERY = 2 -- server ticks between DD_TROOPS / DD_MAJOR packets
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 150 -- px; a jump this big is a spawn, not a step
local MAX_STAINS = 80

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

--- The map in play, if it is the beach.
local function beachMap()
  local city = Features.byName["city-map"]
  local map = city and city.map
  return map and map.kind == "beach" and map or nil
end

--- The map in play, if it is the Colosseum's arena (its sand: `map.oval`).
local function arenaMap()
  local city = Features.byName["city-map"]
  local map = city and city.map
  return map and map.oval and map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { stage, troops, major, mortars, mortarIn, reinforceIn, maxRiflemen, revealT, syncIn,
--                  arena = { x, y } where reinforcements come in on the Colosseum's sand, or nil }

function Dday:serverStart()
  sv = { stage = nil, mortars = {} }
end

local function setStage(server, stage, line)
  sv.stage = stage
  server:broadcast(Protocol.encode("DD_STAGE", stage, line or 0))
end

--- The quests feature took everyone to the beach: the defenders take their
--- posts and the mortars start.
function Dday:serverQuestStarted(server, quest)
  local map = beachMap()
  if not (sv and quest.boss == self.questId and map) then
    return
  end
  -- tougher each time the beach has been taken before (their rifles already hit harder: Weapons:serverFireFrom)
  sv.troops = Soldiers.new({ aware = Dday.aware, health = Bosses.enemyHealth(Soldiers.HEALTH) })
  sv.troops:navigate({ x = map.left, y = map.top, w = map.w, h = map.h })
  sv.troops:placeGuards(map, math.min(self.maxGuards, Bosses.count(self.guards, server)))
  sv.maxRiflemen = Bosses.count(self.riflemen, server)
  sv.major, sv.mortars = nil, {}
  sv.mortarIn, sv.reinforceIn = self.mortarFirst, self.reinforceEvery
  sv.revealT, sv.syncIn = 0, 0
  setStage(server, "assault")
end

--- Everyone off the beach: nothing left to draw on any screen.
function Dday:stop(server)
  if sv and sv.stage then
    sv.stage, sv.troops, sv.major, sv.mortars, sv.arena = nil, nil, nil, {}, nil
    server:broadcast(Protocol.encode("DD_STAGE", "none", 0))
  end
end

function Dday:serverQuestEnded(server, quest)
  if quest.boss == self.questId then
    self:stop(server)
  end
end

--- A map change of any kind ends it; the quest starts it again.
function Dday:mapChanged(_map, server)
  if server then
    self:stop(server)
  end
end

--- Someone joining mid-landing hears the stage (after quests' QST_START,
--- which clears the beach on their screen); the soldiers come with the sync.
function Dday:serverPlayerJoined(server, player)
  if sv and sv.stage and server.started and not player.bot then
    server:send(player, Protocol.encode("DD_STAGE", sv.stage, 0))
  end
end

--- Something froze the world around (x, y): soldiers and the Major inside
--- it stand still for `seconds`.
function Dday:serverFreezeArea(_server, x, y, radius, seconds)
  if not (sv and sv.troops) then
    return
  end
  sv.troops:freeze(x, y, radius, seconds)
  local m = sv.major
  if m and m:hitBy(x, y, radius) then
    m.frozen = math.max(m.frozen, seconds)
  end
end

--- Something stinks at (x, y): whoever is inside it runs for a moment.
function Dday:serverPanicArea(_server, x, y, radius)
  if not (sv and sv.troops) then
    return
  end
  sv.troops:scare(x, y, radius, 0.5)
  local m = sv.major
  if m and m:hitBy(x, y, radius) then
    m.panic = { x = x, y = y, left = 0.5 }
  end
end

--- Where the next mortar comes down in the arena: often close to someone,
--- otherwise anywhere on the sand.
local function arenaMortarSpot(server, oval)
  local people = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      people[#people + 1] = { x = x, y = y }
    end
  end
  if #people > 0 and random() < Dday.mortarAimed then
    local t = people[random(#people)]
    local a, d = random() * 2 * math.pi, random() * Dday.mortarNear
    return t.x + math.cos(a) * d, t.y + math.sin(a) * d
  end
  local a, d = random() * 2 * math.pi, math.sqrt(random()) * 0.9
  return oval.x + math.cos(a) * oval.rx * d, oval.y + math.sin(a) * oval.ry * d
end

--- Where the next mortar comes down: often close to someone on the beach,
--- otherwise anywhere on it.
local function mortarSpot(server, map)
  local beach, surf = map.bands.beach, map.bands.surf
  local onBeach = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if y >= beach.y0 and y <= surf.y0 + 60 then
        onBeach[#onBeach + 1] = { x = x, y = y }
      end
    end
  end
  local x, y
  if #onBeach > 0 and random() < Dday.mortarAimed then
    local t = onBeach[random(#onBeach)]
    local a, d = random() * 2 * math.pi, random() * Dday.mortarNear
    x, y = t.x + math.cos(a) * d, t.y + math.sin(a) * d
  else
    x = map.left + 60 + random() * (map.w - 120)
    y = beach.y0 + 40 + random() * (surf.y0 - beach.y0 - 40)
  end
  x = math.max(map.left + 40, math.min(map.left + map.w - 40, x))
  y = math.max(beach.y0 + 40, math.min(surf.y0 + 40, y))
  return x, y
end

--- A mortar lands: everyone near it is hurt, most at the middle.
function Dday:mortarLands(server, m)
  local R = self.mortarRadius
  local weapons = Features.byName.weapons
  server:broadcast(Protocol.encode("DD_BLAST", fmt(m.x), fmt(m.y), R))
  if not (weapons and weapons.serverDamage) then
    return
  end
  local caught = {}
  local full = self.mortarDamage * Bosses.enemyPower() -- the defenders' guns, harder each time the beach is taken
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local d = math.max(0, math.sqrt((x - m.x) ^ 2 + (y - m.y) ^ 2) - 7)
      if d <= R then
        local amount = math.floor(full * (1 - (2 / 3) * d / R) + 0.5)
        caught[#caught + 1] = { p = p, amount = amount, angle = math.atan2(y - m.y, x - m.x) }
      end
    end
  end
  for _, c in ipairs(caught) do
    weapons:serverDamage(server, c.p, nil, c.amount, c.angle, "explosive")
  end
end

function Dday:stepMortars(server, map, dt)
  sv.mortarIn = sv.mortarIn - dt
  if sv.mortarIn <= 0 then
    sv.mortarIn = self.mortarEvery[1] + random() * (self.mortarEvery[2] - self.mortarEvery[1])
    local x, y
    if sv.arena then
      x, y = arenaMortarSpot(server, map.oval)
    else
      x, y = mortarSpot(server, map)
    end
    sv.mortars[#sv.mortars + 1] = { x = x, y = y, t = self.mortarDelay }
    server:broadcast(Protocol.encode("DD_AIM", fmt(x), fmt(y), self.mortarRadius, ("%.2f"):format(self.mortarDelay)))
  end
  for i = #sv.mortars, 1, -1 do
    local m = sv.mortars[i]
    m.t = m.t - dt
    if m.t <= 0 then
      table.remove(sv.mortars, i)
      self:mortarLands(server, m)
    end
  end
end

function Dday:stepReinforcements(map, dt)
  sv.reinforceIn = sv.reinforceIn - dt
  if sv.reinforceIn > 0 then
    return
  end
  sv.reinforceIn = self.reinforceEvery
  if #map.doors > 0 and sv.troops:count("rifleman") < sv.maxRiflemen then
    sv.troops:reinforce(map)
  end
end

--- Is a player (not a bot) at the flag?
local function flagReached(server, map)
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.flagX) ^ 2 + (y - map.flagY) ^ 2 <= Dday.flagRadius ^ 2 then
        return true
      end
    end
  end
  return false
end

--- Someone reached the flag: the Major steps out behind it, and every
--- screen gets his portrait while the world holds still.
function Dday:reveal(server, map)
  sv.major = Major.new(map.flagX, map.flagY - 90, Bosses.health(Major.HEALTH, server), sv.troops and sv.troops.nav)
  sv.revealT = self.revealTime
  setStage(server, "reveal", random(Major.TALK))
end

--- In the Colosseum, a rifleman somewhere open round (x, y); nil if walled in.
local function arenaRifleman(x, y)
  for _ = 1, 10 do
    local a, d = random() * 2 * math.pi, 40 + random() * 200
    local sx, sy = x + math.cos(a) * d, y + math.sin(a) * d
    if not Features.any("blocksPoint", sx, sy) then
      return sv.troops:add("rifleman", sx, sy, math.pi / 2)
    end
  end
  return nil
end

--- The fight on the Colosseum's sand starts, if it hasn't: the soldiers'
--- side, with nobody yet, and the mortars.
local function arenaStart(server, map)
  if sv.arena then
    return
  end
  sv.troops = Soldiers.new({ aware = Dday.aware, health = Bosses.enemyHealth(Soldiers.HEALTH) })
  sv.troops:navigate({ x = map.left, y = map.top, w = map.w, h = map.h })
  sv.major, sv.mortars, sv.maxRiflemen = nil, {}, 0
  sv.mortarIn, sv.reinforceIn, sv.revealT, sv.syncIn = Dday.mortarFirst, Dday.reinforceEvery, 0, 0
  sv.arena = { x = 0, y = 0 }
  setStage(server, "arena")
end

--- The Colosseum's waves (colosseum/waves.lua): `count` riflemen come in
--- round (x, y) (`kind` "soldier"), or the Major stands there (`kind`
--- "major"), riflemen coming in there after him while he stands. Returns
--- how many came.
function Dday:serverArenaSend(server, kind, count, x, y)
  local map = arenaMap()
  if not (sv and map and (kind == "soldier" or kind == "major")) then
    return 0
  end
  arenaStart(server, map)
  sv.arena.x, sv.arena.y = x, y
  if kind == "major" then
    if sv.major then
      return 0
    end
    sv.major = Major.new(x, y, Bosses.health(Major.HEALTH, server), sv.troops.nav)
    sv.maxRiflemen, sv.reinforceIn = Bosses.count(self.riflemen, server), self.reinforceEvery
    setStage(server, "boss")
    server:broadcast(Protocol.encode("DD_SAY", random(Major.TALK)))
    return 1
  end
  local came = 0
  for _ = 1, count do
    if arenaRifleman(x, y) then
      came = came + 1
    end
  end
  return came
end

--- How many are still up on the sand: the soldiers, and the Major with them.
function Dday:serverArenaLeft(_server, kind)
  if not (sv and sv.arena) then
    return 0
  end
  return #sv.troops.list + (kind == "major" and sv.major and 1 or 0)
end

--- The Colosseum's tick: the soldiers, the mortars, the Major and the
--- riflemen coming in after him.
function Dday:stepArena(server, map, dt)
  sv.troops:update(server, dt)
  self:callIns()
  self:stepMortars(server, map, dt)
  if sv.major then
    for _, e in ipairs(sv.major:update(server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("DD_SAY", e[2]))
      elseif e[1] == "nest" then
        server:broadcast(Protocol.encode("DD_NEST", fmt(e[2]), fmt(e[3]), ("%.3f"):format(e[4])))
      end
    end
    sv.reinforceIn = sv.reinforceIn - dt
    if sv.reinforceIn <= 0 then
      sv.reinforceIn = self.reinforceEvery
      if sv.troops:count("rifleman") < sv.maxRiflemen then
        arenaRifleman(sv.arena.x, sv.arena.y)
      end
    end
  end
end

function Dday:serverStep(server, dt)
  if not (sv and sv.stage) then
    return
  end
  if sv.arena then
    local arena = arenaMap()
    if arena then
      sv.syncIn = sv.syncIn - 1
      if sv.syncIn < 0 then
        sv.syncIn = SYNC_EVERY - 1
      end
      self:stepArena(server, arena, dt)
      if sv.syncIn == 0 then
        self:sync(server)
      end
    end
    return
  end
  local map = beachMap()
  if not map then
    return
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn < 0 then
    sv.syncIn = SYNC_EVERY - 1
  end
  if sv.stage == "reveal" then
    sv.revealT = sv.revealT - dt
    if sv.revealT <= 0 then
      setStage(server, "boss")
    end
  else
    sv.troops:update(server, dt)
    self:callIns()
    if sv.stage ~= "done" then
      self:stepMortars(server, map, dt)
      self:stepReinforcements(map, dt)
    end
    if sv.stage == "assault" and flagReached(server, map) then
      self:reveal(server, map)
    elseif sv.stage == "boss" and sv.major then
      for _, e in ipairs(sv.major:update(server, dt)) do
        if e[1] == "say" then
          server:broadcast(Protocol.encode("DD_SAY", e[2]))
        elseif e[1] == "nest" then
          server:broadcast(Protocol.encode("DD_NEST", fmt(e[2]), fmt(e[3]), ("%.3f"):format(e[4])))
        end
      end
    end
  end
  if sv.syncIn == 0 then
    self:sync(server)
  end
end

--- Every soldier and the Major, to everyone, unreliably.
function Dday:sync(server)
  local parts = { server.tick }
  for _, s in ipairs(sv.troops.list) do
    local flag = s.kind == "guard" and "g" or "r"
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.alert and flag:upper() or flag
  end
  local msgs = { Protocol.encode("DD_TROOPS", unpack(parts)) }
  local m = sv.major
  if m then
    msgs[2] = Protocol.encode("DD_MAJOR", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
      math.max(0, math.floor(m.hp)), m.max, m.breath:wire())
  end
  for _, player in pairs(server.players) do
    for _, msg in ipairs(msgs) do
      server:send(player, msg, true)
    end
  end
end

--- A soldier who has just spotted somebody calls it in: the nearest few
--- within earshot who aren't busy come to where he saw them.
function Dday:callIns()
  local time = sv.troops.time
  for _, s in ipairs(sv.troops.list) do
    if s.alert and not s.wasAlert and (s.callUntil or 0) <= time then
      s.callUntil = time + self.callEvery
      sv.troops:alarm(s.aimX, s.aimY, self.callHeard, { from = s, most = self.callAnswer })
    end
    s.wasAlert = s.alert
  end
end

--- One soldier down: his body on every screen (a splat for a blast; the
--- corpses feature), a koin where he fell, and sometimes something to pick
--- up. Everyone near enough to hear it goes to look. `cause` is the damage type.
function Dday:soldierDown(server, s, by, angle, cause)
  sv.troops:alarm(s.x, s.y, self.downHeard)
  server:broadcast(Protocol.encode("DD_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0),
    cause or "bullet"))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, self.soldierDrops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y) -- maybe something to pick up (the odds are pickups')
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle })
end

--- Take `amount` off the Major. Returns true if that finished him.
function Dday:hurtMajor(server, amount, by, angle)
  local m = sv.major
  m.hp = m.hp - amount
  if m.hp > 0 then
    return false
  end
  local x, y = m.x, m.y
  sv.major = nil
  server:broadcast(Protocol.encode("DD_MAJOR_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Major.DROPS)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  setStage(server, sv.arena and "arena" or "done") -- no flag in the Colosseum
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, self.questId, x, y) -- an EXIT star home where he fell
  end
  return true
end

--- A bullet passing through (x, y): the `serverShotAt` convention. The
--- defenders' own rounds (owner 0) pass through their side; the Major can
--- only be hurt once his fight has begun.
function Dday:serverShotAt(server, x, y, radius, by, angle, _damage, dtype)
  if not (sv and sv.troops) or by == 0 then
    return false
  end
  local m = sv.major
  if m and sv.stage == "boss" and m:hitBy(x, y, radius) then
    self:hurtMajor(server, self.bulletDamage, by, angle)
    return true
  end
  local s, i = sv.troops:at(x, y, radius)
  if not s then
    return false
  end
  if sv.troops:hurt(s, i, Soldiers.SHOT_DAMAGE, angle) then
    self:soldierDown(server, s, by, angle, dtype)
  end
  return true
end

--- Every enemy on the beach right now, for the audit (tools/audit): each
--- soldier, and the Major, who can only be hurt once his fight has begun
--- (as `serverShotAt` has it).
function Dday:serverEnemies(_server, add)
  if not (sv and sv.troops) then
    return
  end
  for _, s in ipairs(sv.troops.list) do
    add({ id = s, kind = "d-day/soldier", x = s.x, y = s.y, hp = s.hp, radius = Soldiers.RADIUS })
  end
  local m = sv.major
  if m then
    add({
      id = m,
      kind = "d-day/major",
      x = m.x,
      y = m.y,
      hp = m.hp,
      radius = Major.RADIUS,
      immune = sv.stage ~= "boss",
    })
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Dday:wikiEnemies(add)
  local Guns = Features.byName.weapons.guns
  local Grenades = require("src.features.grenades")
  local Heal = require("src.features.bosses.heal")
  local Nest = Features.byName.abilities.kinds.byKey.mgnest
  local ak = Guns.ak47
  add({
    kind = "d-day/soldier",
    name = "D-Day soldier",
    quests = { self.questId, "colosseum" },
    where = "Looz'er Beach: guards in the bunkers, trenches and huts, riflemen out of the barracks; and the "
      .. "Colosseum's ninth to eleventh waves",
    about = "The Major's men. Guards sweep a cone of sight over the beach from their posts; riflemen come out "
      .. "of the barracks doors and walk down the hill at you. Both open fire on anyone they spot.",
    stats = {
      { "Health", Soldiers.HEALTH },
      { "Hits", ("%g a hit, whatever the gun: %g hits"):format(Soldiers.SHOT_DAMAGE,
        math.ceil(Soldiers.HEALTH / Soldiers.SHOT_DAMAGE)) },
      { "Speed", ("%g px/s walking down the hill, %g closing in"):format(Soldiers.WALK, Soldiers.CHASE_WALK) },
      { "Sight", ("%g px in a %g degree cone, and %g px all round"):format(Soldiers.RANGE,
        math.floor(math.deg(require("src.features.d-day.sight").FOV) + 0.5), self.aware) },
      { "Numbers", ("%g guards and up to %g riflemen at once for one player, a rifleman every %g s"):format(
        self.guards, self.riflemen, self.reinforceEvery) },
    },
    weapons = {
      { "AK-47", ("%g damage a round, a round every %g s while he can see you, out to %g px"):format(ak.damage,
        Soldiers.FIRE_EVERY, Soldiers.RANGE) },
      { "Hand grenade", ("%g%% of them carry %g each: %g explosive damage across %g px, thrown %g to %g px"):format(
        Soldiers.GRENADIER * 100, Soldiers.GRENADES, Grenades.blast.damage, Grenades.blast.radius,
        Soldiers.GRENADE_MIN, Grenades.range) },
    },
    abilities = {
      ("Spots you, turns to follow you at %d degrees a second and fires after %g s to take aim."):format(
        math.floor(math.deg(Soldiers.TURN) + 0.5), Soldiers.REACT),
      ("Calls in the nearest %g within %g px when he spots you; one going down brings everyone within %g px "
        .. "to look."):format(self.callAnswer, self.callHeard, self.downHeard),
      ("Comes after you when you duck out of sight (up to %g px from where he started) and searches where he lost you "
        .. "for %g s."):format(Soldiers.LEASH, Soldiers.SEARCH_TIME),
      "Shot at from out of sight, he and his mates take cover and wait, then send a squad to look.",
      ("Behind them, mortars fall on the beach every %g to %g s: a ring shows where for %g s, then up to %g "
        .. "explosive damage across %g px."):format(self.mortarEvery[1], self.mortarEvery[2], self.mortarDelay,
        self.mortarDamage, self.mortarRadius),
    },
    tips = {
      "Keep a tank stopper or a sandbag wall between you and the cones of sight.",
      "Sprint across a cone: he can't turn fast enough to follow you.",
      "A freeze stops them looking and shooting, and a stink sends them running.",
    },
    drops = ("%g koin, and sometimes something to pick up"):format(self.soldierDrops),
  })
  add({
    kind = "d-day/major",
    name = "Major Looz'er",
    quests = { self.questId },
    boss = true,
    where = "Looz'er Beach, on the hilltop behind the flag once someone reaches it",
    about = "Big, slow and never done talking about his country. He sees all round him, marches to rifle "
      .. "range of the nearest player and fires bursts, and throws MG nests down in front of him.",
    stats = {
      { "Health", Major.HEALTH },
      { "Hits", ("%g a hit, whatever the gun: %g hits"):format(self.bulletDamage,
        math.ceil(Major.HEALTH / self.bulletDamage)) },
      { "Speed", ("%g px/s marching, %g winded"):format(Major.SPEED, Major.WALK_SPEED) },
      { "Sight", ("%g px, all the way round"):format(Major.RANGE) },
    },
    weapons = {
      { "AK-47", ("bursts of %g rounds, %g damage each, a burst every %g s"):format(Major.BURST, ak.damage,
        Major.BURST_EVERY) },
      { "MG nest", ("every %g s (the first %g s in): a machine gun that sprays a %g degree arc in front of him "
        .. "for %g s, %g damage a round"):format(Major.NEST_EVERY, Major.NEST_FIRST, math.deg(Nest.arc),
        Nest.seconds, Nest.gun.damage) },
    },
    abilities = {
      ("Keeps about %g px from whoever he is after."):format(Major.KEEP),
      "Marching costs him breath: winded, he strolls, and has no MG nest in him until it's back.",
      ("Under %g%% health he goes for the nearest medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      "Can't be hurt until his portrait is gone and the fight is on.",
    },
    tips = {
      "Stay out of the nest's arc: it only fires the way it faces.",
      "Run him dry and he can't keep up, or put a nest down.",
      "A freeze holds him still, and a stink sends him running.",
    },
    drops = ("%g koins"):format(Major.DROPS),
  })
end

--- For tests.
function Dday.server()
  return sv
end

-- Client --------------------------------------------------------------------

Dday.stage = nil -- the stage, from the host
Dday.troops = {} -- id -> { x, y, dx, dy, angle, hp, kind, alert, bob }
Dday.major = nil -- { x, y, dx, dy, angle, hp, max, stamina, winded, say, sayTimer, bob }
Dday.aims = {} -- { x, y, r, t, total }: mortars on their way
Dday.nests = {} -- { x, y, angle, t, seconds }: the Major's MG nests
Dday.stains = {} -- { x, y, angle, big } or { x, y, r, crater = true }
Dday.page = nil -- { line, t } while his portrait is up
local face = nil
local time, lastTick, lastMajorTick = 0, 0, 0
local march = nil -- the beach's theme, made the first time anyone lands

--- The march at the music slider's level (silent while muted).
local function marchVolume()
  if march then
    march:setVolume(Audio.muted and 0 or Audio.volume("music"))
  end
end

local function startMarch()
  if march == nil then
    local t0 = love.timer.getTime()
    march = love.audio.newSource(Theme.render(), "static")
    march:setLooping(true)
    march:setRelative(true) -- heard the same wherever you are on the beach
    -- The render time on the console, the way every theme reports it.
    local took = love.timer.getTime() - t0
    print(("d-day theme: %.1fs of audio rendered in %.2fs"):format(Theme.duration(), took)) -- audit: allow
  end
  marchVolume()
  march:seek(0)
  march:play()
end

local function stopMarch()
  if march ~= nil then
    march:stop()
  end
end

local function clear()
  Dday.stage, Dday.major, Dday.page = nil, nil, nil
  Dday.troops, Dday.aims, Dday.nests, Dday.stains = {}, {}, {}, {}
end

local function stain(s)
  Dday.stains[#Dday.stains + 1] = s
  if #Dday.stains > MAX_STAINS then
    table.remove(Dday.stains, 1)
  end
end

function Dday:load()
  Sounds.load()
end

function Dday:exitGame()
  clear()
  lastTick, lastMajorTick = 0, 0
  stopMarch()
end

function Dday:questStarted(_client, quest)
  if quest.boss == self.questId then
    face = face or Face.new()
    clear()
    startMarch()
  end
end

function Dday:questEnded(_client, quest)
  if quest.boss == self.questId then
    clear()
    stopMarch()
  end
end

local function ease(e, k)
  local ex, ey = e.x - e.dx, e.y - e.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    e.dx, e.dy = e.x, e.y
  else
    e.dx, e.dy = e.dx + ex * k, e.dy + ey * k
  end
end

function Dday:update(dt)
  time = time + dt
  marchVolume()
  if self.page then
    face:update(dt)
    self.page.t = self.page.t - dt
    if self.page.t <= 0 then
      self.page = nil
    end
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(self.troops) do
    ease(s, k)
  end
  local m = self.major
  if m then
    ease(m, k)
    m.sayTimer = math.max(0, m.sayTimer - dt)
  end
  for i = #self.aims, 1, -1 do
    local a = self.aims[i]
    a.t = a.t - dt
    if a.t < -0.5 then
      table.remove(self.aims, i) -- the landing never came
    end
  end
  for i = #self.nests, 1, -1 do
    local n = self.nests[i]
    n.t = n.t + dt
    if n.t > n.seconds + 1 then
      table.remove(self.nests, i)
    end
  end
end

--- His portrait softens the world behind it.
function Dday:worldBlur()
  return self.page and 1 or 0
end

function Dday:drawBelowCars(_client, camera)
  if self.stage then
    Render.below(self, camera, time)
  end
end

function Dday:drawAboveCars(_client, camera)
  if self.stage then
    Render.above(self, beachMap(), camera, time) -- the flag on the beach; none in the Colosseum
  end
end

function Dday:drawHUD(client)
  if not self.stage then
    return
  end
  local map, distance = beachMap(), nil
  local x, y = client:myPose()
  if map and x then
    distance = math.sqrt((x - map.flagX) ^ 2 + (y - map.flagY) ^ 2)
  end
  Render.hud(self, face, distance, time)
end

Dday.clientMessages = {
  DD_STAGE = function(_client, args)
    local stage, line = args[1], tonumber(args[2]) or 0
    if stage == "none" then
      clear()
      return
    end
    if stage == "reveal" and Dday.stage ~= "reveal" and Major.lines[line] then
      face = face or Face.new()
      Dday.page = { line = Major.lines[line], t = Dday.revealTime }
      local map = beachMap()
      Sounds.play("bugle", map and map.flagX or 0, map and map.flagY or 0)
    end
    Dday.stage = stage
  end,
  DD_TROOPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = Dday.troops[id]
        if not s then
          s = { dx = x, dy = y, bob = random() * 6 }
          Dday.troops[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.hp = tonumber(args[i + 4]) or Soldiers.HEALTH
        s.top = math.max(s.top or Soldiers.HEALTH, s.hp) -- his bar's full: more than HEALTH once the beach is taken
        local flag = args[i + 5] or "g"
        s.kind = flag:lower() == "r" and "rifleman" or "guard"
        s.alert = flag ~= flag:lower()
        seen[id] = true
      end
    end
    for id in pairs(Dday.troops) do
      if not seen[id] then
        Dday.troops[id] = nil
      end
    end
  end,
  DD_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and Dday.troops[id]
    if id then
      Dday.troops[id] = nil
    end
    if x and y then
      -- His body where he was drawn, or a splat (and a stain) for a blast.
      local bx, by = s and s.dx or x, s and s.dy or y
      if not Corpses.down(bx, by, angle, Render.lookFor(s and s.kind), args[5]) then
        stain({ x = x, y = y, angle = angle })
      end
    end
  end,
  DD_AIM = function(_client, args)
    local x, y, r, delay = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and delay then
      Dday.aims[#Dday.aims + 1] = { x = x, y = y, r = r, t = delay, total = delay }
      Sounds.play("whistle", x, y, 0.9 + random() * 0.2)
    end
  end,
  DD_BLAST = function(client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (x and y and r) then
      return
    end
    for i = #Dday.aims, 1, -1 do
      local a = Dday.aims[i]
      if (a.x - x) ^ 2 + (a.y - y) ^ 2 < 4 then
        table.remove(Dday.aims, i)
      end
    end
    stain({ x = x, y = y, r = r * 0.45, crater = true })
    local weapons = Features.byName.weapons
    if weapons and weapons.explosionAt then
      weapons:explosionAt(client, x, y, { 0.85, 0.75, 0.5 })
    end
  end,
  DD_MAJOR = function(_client, args)
    local tick = tonumber(args[1])
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (tick and x and y) or tick <= lastMajorTick then
      return
    end
    lastMajorTick = tick
    local m = Dday.major
    if not m then
      m = { dx = x, dy = y, bob = random() * 6, sayTimer = 0 }
      Dday.major = m
    end
    m.x, m.y = x, y
    m.angle = tonumber(args[4]) or m.angle or math.pi / 2
    m.hp = tonumber(args[5]) or m.hp or Major.HEALTH
    m.max = tonumber(args[6]) or m.max or Major.HEALTH
    local stamina, winded = Stamina.read(args, 7)
    m.stamina, m.winded = stamina or m.stamina, winded
  end,
  DD_SAY = function(_client, args)
    local m, line = Dday.major, Major.lines[tonumber(args[1]) or 0]
    if m and line then
      m.say, m.sayTimer = line, 3.6
    end
  end,
  DD_NEST = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local Nest = Features.byName.abilities and require("src.features.abilities.mgnest")
    if x and y and angle and Nest then
      Dday.nests[#Dday.nests + 1] = { x = x, y = y, angle = angle, t = 0, seconds = Nest.seconds }
    end
  end,
  DD_MAJOR_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    Dday.major, Dday.nests = nil, {}
    if x and y then
      stain({ x = x, y = y, angle = angle, big = true })
      if Features.byName.pedestrians then
        require("src.features.pedestrians.gibs").splat(x, y, angle)
      end
    end
  end,
}

--- The footsteps feature's hook: who of mine is walking about, and where.
function Dday:footstepWalkers()
  local list = {}
  for id, s in pairs(self.troops or {}) do
    list[#list + 1] = { key = id, x = s.dx, y = s.dy, size = "person" }
  end
  if self.major then
    list[#list + 1] = { key = "major", x = self.major.dx, y = self.major.dy, size = "heavy" }
  end
  return list
end

return Dday
