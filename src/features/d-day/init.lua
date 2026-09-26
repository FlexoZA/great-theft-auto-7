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
--      as long as he can see you (troops.lua).
--   3. Barracks: guards by the huts, and riflemen coming out of the doors
--      every few seconds, walking down towards the nearest player and
--      firing at whoever they spot.
--   4. The hilltop: more guards, and the flag. Reach it and Major Looz'er's
--      portrait comes up on every screen; then he fights (major.lua). He
--      has the MG nest, the same ability a player can buy.
--
-- When he goes down he spills a pile of koins, the quest is done, the flag
-- turns to yours, and quests puts an EXIT star home where he fell.
--
-- The quests feature brings everyone to the beach and raises
-- `serverQuestStarted` / `questStarted` for the quest whose `boss` is
-- "d-day". The host owns all of it: the stage, every soldier, the mortars,
-- the Major. Clients hear the stage reliably and positions at 15 Hz, and
-- draw. Bullets reach the soldiers and the Major through `serverShotAt`;
-- their own rounds (owner 0) fly through each other.
--
-- Messages
--   server -> all  DD_STAGE  <stage> <line>          none | assault | reveal | boss | done (line: the
--                                                    portrait's speech, Major.lines[line], for reveal)
--   server -> all  DD_TROOPS <tick> [<id> <x> <y> <facing> <hp> <flags>]...   (unreliable, 15 Hz;
--                                                    flags g/r guard/rifleman, upper case when alert)
--   server -> all  DD_DOWN   <id> <x> <y> <angle>    a soldier went down
--   server -> all  DD_AIM    <x> <y> <radius> <delay>  a mortar is coming down here
--   server -> all  DD_BLAST  <x> <y> <radius>        it landed
--   server -> all  DD_MAJOR  <tick> <x> <y> <facing> <hp> <max> <stamina> <winded>   (unreliable, 15 Hz)
--   server -> all  DD_SAY    <line>                  the Major says Major.lines[line]
--   server -> all  DD_NEST   <x> <y> <angle>         the Major put an MG nest down
--   server -> all  DD_MAJOR_DOWN <x> <y> <angle>     the Major went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Troops = require("src.features.d-day.troops")
local Major = require("src.features.d-day.major")
local Face = require("src.features.d-day.major_face")
local Stamina = require("src.features.bosses.stamina")
local Render = require("src.features.d-day.render")
local Sounds = require("src.features.d-day.sounds")

local Dday = {
  name = "d-day",
  priority = 992, -- the portrait goes over every other HUD, the ability row (990) too; under the inventory (995)
}

-- Tuning ------------------------------------------------------------------
Dday.questId = "d-day"
Dday.guards = 16 -- guards on their posts for one player...
Dday.guardsPerPlayer = 2 -- ...and this many more for each other player
Dday.maxGuards = 26
Dday.riflemen = 4 -- most riflemen out at once for one player...
Dday.riflemenPerPlayer = 1 -- ...and this many more for each other player
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
Dday.soldierAmmoChance = 0.2 -- odds a soldier leaves a box of ammo (pickups' serverDropAmmo)...
Dday.soldierAmmo = 0.5 -- ...and how big: magazines of whatever gun it is for

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

-- Server --------------------------------------------------------------------

local sv = nil -- { stage, troops, major, mortars, mortarIn, reinforceIn, maxRiflemen, revealT, syncIn }

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
  local n = 0
  for _, p in pairs(server.players) do
    if not p.bot then
      n = n + 1
    end
  end
  local extra = math.max(0, n - 1)
  sv.troops = Troops.new()
  sv.troops:placeGuards(map, math.min(self.maxGuards, self.guards + self.guardsPerPlayer * extra))
  sv.maxRiflemen = self.riflemen + self.riflemenPerPlayer * extra
  sv.major, sv.mortars = nil, {}
  sv.mortarIn, sv.reinforceIn = self.mortarFirst, self.reinforceEvery
  sv.revealT, sv.syncIn = 0, 0
  setStage(server, "assault")
end

--- Everyone off the beach: nothing left to draw on any screen.
function Dday:stop(server)
  if sv and sv.stage then
    sv.stage, sv.troops, sv.major, sv.mortars = nil, nil, nil, {}
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

--- Where the next mortar comes down: often close to someone on the beach,
--- otherwise anywhere on it.
local function mortarSpot(server, map)
  local beach, surf = map.bands.beach, map.bands.surf
  local onBeach = {}
  for _, p in pairs(server.players) do
    if Features.present(p) then
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
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local d = math.max(0, math.sqrt((x - m.x) ^ 2 + (y - m.y) ^ 2) - 7)
      if d <= R then
        local amount = math.floor(self.mortarDamage * (1 - (2 / 3) * d / R) + 0.5)
        caught[#caught + 1] = { p = p, amount = amount, angle = math.atan2(y - m.y, x - m.x) }
      end
    end
  end
  for _, c in ipairs(caught) do
    weapons:serverDamage(server, c.p, nil, c.amount, c.angle)
  end
end

function Dday:stepMortars(server, map, dt)
  sv.mortarIn = sv.mortarIn - dt
  if sv.mortarIn <= 0 then
    sv.mortarIn = self.mortarEvery[1] + random() * (self.mortarEvery[2] - self.mortarEvery[1])
    local x, y = mortarSpot(server, map)
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
  sv.major = Major.new(map.flagX, map.flagY - 90)
  sv.revealT = self.revealTime
  setStage(server, "reveal", random(#Major.lines))
end

function Dday:serverStep(server, dt)
  if not (sv and sv.stage) then
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

--- One soldier down: gibs on every screen, a koin where he fell, and
--- sometimes a box of ammo.
function Dday:soldierDown(server, s, by, angle)
  server:broadcast(Protocol.encode("DD_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, self.soldierDrops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropAmmo then
    pickups:serverDropAmmo(server, s.x, s.y, self.soldierAmmo, self.soldierAmmoChance)
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
  setStage(server, "done")
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, self.questId, x, y) -- an EXIT star home where he fell
  end
  return true
end

--- A bullet passing through (x, y): the `serverShotAt` convention. The
--- defenders' own rounds (owner 0) pass through their side; the Major can
--- only be hurt once his fight has begun.
function Dday:serverShotAt(server, x, y, radius, by, angle)
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
  if sv.troops:hurt(s, i, Troops.SHOT_DAMAGE, angle) then
    self:soldierDown(server, s, by, angle)
  end
  return true
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
end

function Dday:questStarted(_client, quest)
  if quest.boss == self.questId then
    face = face or Face.new()
    clear()
  end
end

function Dday:questEnded(_client, quest)
  if quest.boss == self.questId then
    clear()
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
  local map = beachMap()
  if self.stage and map then
    Render.above(self, map, camera, time)
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
        s.hp = tonumber(args[i + 4]) or Troops.HEALTH
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
    if id then
      Dday.troops[id] = nil
    end
    if x and y then
      stain({ x = x, y = y, angle = angle })
      if Features.byName.pedestrians then
        require("src.features.pedestrians.gibs").splat(x, y, angle)
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + random() * 0.2)
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

return Dday
