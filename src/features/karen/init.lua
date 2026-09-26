-- Crazy Karen: the first boss. She stands in the turning circle of her
-- cul-de-sac screaming about nothing, and when anyone comes near she charges
-- them and slaps whatever she reaches, car or walker. She is big, she is
-- slow, and she takes a great many bullets; ram her with a car and she gets
-- hurt, but so does the car, and it bounces off (her street is a walking
-- map, so that takes a car that got there some other way). When she finally
-- goes down she spills a pile of koins, far more than anything else drops,
-- and the quest is done.
--
-- She has stamina like every boss (bosses/stamina.lua): charging spends it
-- and standing, walking or slapping lets it come back. Run her dry and she
-- is winded: she can only walk, slower than anyone sprinting, and has no
-- breath for a scream until a good part of it is back. Sprint away while
-- she puffs.
--
-- She also screams. Every so often she plants her feet and draws breath at
-- whoever is nearest: a ring on the ground shows where the scream will
-- land, and a moment later it does. Anyone caught inside is hurt and their
-- screen swims for a few seconds (the `worldBlur` hook), so a scream is
-- something to step out of, not stand in.
--
-- She is not alone: while she stands, her simps turn up (simps.lua), up to
-- five at a time, each with a name that starts "Simpin". They run at the
-- nearest player and punch; two pistol rounds drop one. Once she is down
-- no more arrive, and the ones left keep swinging until they are dealt with.
--
-- The quests feature brings everyone to her street and raises
-- `serverQuestStarted` / `questStarted` for the quest whose `boss` is
-- "karen": the host spawns her then, and every client puts up the title
-- screen (her face, the quest's name, whatever she is complaining about)
-- and starts her theme. Both go away when the group leaves.
--
-- The host owns her: where she is, what she is doing, how much is left of
-- her. Clients hear about it at 15 Hz and draw her, her rants and the boss
-- bar. Bullets reach her through the `serverShotAt` convention.
--
-- Messages
--   server -> all  KRN_SPAWN <x> <y> <hp> <max>                    she is here (also to anyone joining)
--   server -> all  KRN_STATE <tick> <x> <y> <facing> <hp> <charging> <stamina> <winded>  (unreliable, 15 Hz)
--   server -> all  KRN_SAY   <lineIndex>                          a rant, for the speech bubble
--   server -> all  KRN_DOWN  <x> <y> <angle> <playerId>            she went down (0 = nobody's kill)
--   server -> all  KRN_GONE                                       she left with the map
--   server -> all  KRN_SCREAM_AIM <x> <y> <radius> <delay>          she is drawing breath: it lands here
--   server -> all  KRN_SCREAM <x> <y> <radius> [<playerId>]...      it landed; these were caught in it
--   server -> all  KRN_SIMP  <id> <name>                           a simp arrived (also to anyone joining)
--   server -> all  KRN_SIMPS <tick> [<id> <x> <y> <facing> <hp> <swing>]...  (unreliable, 15 Hz; empty = all gone)
--   server -> all  KRN_SIMP_DOWN <id> <x> <y> <angle> <playerId>   one went down (0 = nobody's kill)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Audio = require("src.audio")
local Video = require("src.video")
local UI = require("src.ui")
local Car = require("src.car")
local KarenFace = require("src.features.karen.face")
local Theme = require("src.features.karen.theme")
local Simps = require("src.features.karen.simps")
local Sounds = require("src.features.karen.sounds")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")

local Karen = {
  name = "karen",
  priority = 970, -- the title screen goes over every other HUD (upgrades is 960)
}

-- Tuning ------------------------------------------------------------------
Karen.maxHealth = 1500 -- seventy-five pistol rounds
Karen.radius = 19 -- px; three pedestrians wide
Karen.chargeSpeed = 165 -- px/s once she has seen you, while she has the breath
Karen.walkSpeed = 55 -- px/s winded: a stroll, and anyone sprinting (170) leaves her behind
Karen.breath = { -- her stamina (bosses/stamina.lua has the rule and the defaults)
  drain = 16, -- per second charging (~6 s flat out; more puff than a player's 4.5 s)
  regen = 14, -- per second otherwise (a player's is 9)
  recovered = 50, -- back before a winded Karen charges again (~4.5 s of walking it off)
  breath = 50, -- in her before she draws a scream: none while winded or nearly so
}
Karen.screamStamina = 20 -- what a scream costs her
Karen.aggroRange = 650 -- px; she notices anyone inside this
Karen.slapReach = 24 -- px past her body a slap lands
Karen.slapDamage = 15
Karen.slapInterval = 1.3 -- seconds between slaps
Karen.bulletDamage = 20 -- what one round takes off her (matches the pistol)
Karen.ramScale = 0.14 -- hp she loses per px/s of a car that hits her
Karen.ramMinSpeed = 60 -- px/s; slower than this a car just nudges her
Karen.ramDamageToCar = 12 -- hp the car loses hitting her
Karen.drops = 30 -- koins she spills when she goes down (a pedestrian drops one, an officer three)
Karen.introTime = 9 -- seconds the title screen stays up unless a key is pressed
Karen.sayTime = 3.2 -- seconds a rant hangs over her head
Karen.screamEvery = 8 -- seconds between screams
Karen.screamRange = 520 -- px; she screams at anyone this close
Karen.screamDelay = 1.2 -- seconds the ring shows before the scream lands
Karen.screamRadius = 120 -- px; the area it lands on
Karen.screamDamage = 20
Karen.screamBlur = 3 -- seconds the screen swims for anyone caught

-- What she is on about. None of it makes any sense; that is the point.
Karen.lines = {
  "The moon was FAR too bright last night and NOBODY warned me!",
  "I ordered a Tuesday and this is CLEARLY a Wednesday. I want a refund.",
  "Your clouds keep looking at me. Make them stop.",
  "I have been waiting for the number 7 bus since 1998. Unacceptable.",
  "Why does the grass have a smell? Who approved that?",
  "My sandwich had TWO corners. TWO. Get me your manager.",
  "This road has entirely too much road in it.",
  "The number 4 is far too close to 5 and I will not be quiet about it.",
  "Somebody put Wednesday in my Tuesday AGAIN.",
  "I demand to speak to whoever is in charge of the wind.",
}

local SYNC_EVERY = 2 -- server ticks between KRN_STATE and KRN_SIMPS packets
local SIMP_COLOR = { 0.45, 0.50, 0.62 } -- the hoodie
local SIMP_SKIN = { 0.90, 0.76, 0.62 }
local SMOOTHING = 10 -- per second, the crowd's easing
local SNAP = 150 -- px; a jump this big is a spawn, not a step
local BODY_COLOR = { 0.93, 0.35, 0.60 } -- the top
local SPOT_COLOR = { 0.35, 0.18, 0.10 } -- leopard print
local HAIR_COLOR = { 0.95, 0.82, 0.45 }
local SKIN_COLOR = { 0.95, 0.80, 0.68 }
local BAG_COLOR = { 0.55, 0.12, 0.30 }

local function fmt(v)
  return ("%.1f"):format(v)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city, city and city.map
end

-- Server --------------------------------------------------------------------

local sv = nil -- { boss = { x, y, facing, hp, max, ... } or nil, syncIn }

--- Solid ground, through the `blocksPoint` convention, tested at the four
--- extremes of her body.
local function blockedAt(x, y)
  local r = Karen.radius
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along, and a note of
--- whether it got anywhere (wedged, she sidesteps).
local function walk(b, angle, speed, dt)
  local px, py = b.x, b.y
  local nx = b.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, b.y) then
    b.x = nx
  end
  local ny = b.y + math.sin(angle) * speed * dt
  if not blockedAt(b.x, ny) then
    b.y = ny
  end
  if (b.x - px) ^ 2 + (b.y - py) ^ 2 < (speed * dt * 0.4) ^ 2 then
    b.stuck = b.stuck + dt
  else
    b.stuck = 0
  end
end

function Karen:serverStart()
  sv = { boss = nil, syncIn = 0, simps = Simps.new(), simpsOut = 0 }
end

--- Send the gang home: nothing left to draw on any screen.
function Karen:clearSimps(server)
  sv.simps:clear()
  sv.simps.spawnIn = Simps.FIRST_AFTER
  server:broadcast(Protocol.encode("KRN_SIMPS", server.tick))
  sv.simpsOut = 0
end

--- One simp down: gibs on every screen, and the other features price it
--- (money drops a koin, the same as a pedestrian).
function Karen:simpDown(server, kill)
  server:broadcast(Protocol.encode("KRN_SIMP_DOWN", kill.id, fmt(kill.x), fmt(kill.y), ("%.3f"):format(kill.angle),
    kill.by or 0))
  Features.call("serverKill", server, { kind = "pedestrian", x = kill.x, y = kill.y, by = kill.by })
end

function Karen:spawnBoss(server, x, y)
  sv.boss = {
    x = x,
    y = y,
    facing = math.pi / 2,
    hp = self.maxHealth,
    max = self.maxHealth,
    charging = false,
    breath = Stamina.new(self.breath), -- winded, she walks and cannot scream
    slapTimer = 1,
    sayTimer = 1.5,
    stuck = 0,
    sidestep = 0,
    side = 1,
    frozen = 0, -- seconds left rooted to the spot
    screamTimer = self.screamEvery * 0.6, -- the first comes a little sooner
    scream = nil, -- { x, y, t } while she is drawing breath
    rammed = {}, -- player id -> seconds before that car can hurt her again
  }
  self:clearSimps(server) -- a fresh gang for a fresh fight
  server:broadcast(Protocol.encode("KRN_SPAWN", fmt(x), fmt(y), self.maxHealth, self.maxHealth))
end

function Karen:removeBoss(server)
  if sv and sv.boss then
    sv.boss = nil
    server:broadcast(Protocol.encode("KRN_GONE"))
  end
  if sv and sv.simps.n > 0 then
    self:clearSimps(server) -- they leave with her
  end
end

--- The quests feature took everyone to her street: she is in the turning
--- circle (the map says where), or the middle of whatever map it is.
function Karen:serverQuestStarted(server, quest)
  if not (sv and quest.boss == "karen") then
    return
  end
  local _, map = cityMap()
  local x = map and (map.circleX or map.cx) or 0
  local y = map and (map.circleY or map.cy) or 0
  self:spawnBoss(server, x, y)
end

function Karen:serverQuestEnded(server)
  self:removeBoss(server)
end

--- A map change of any kind takes her with it; the quest respawns her.
function Karen:mapChanged(_map, server)
  if server then
    self:removeBoss(server)
  end
end

--- Something froze the world around (x, y) (the `serverFreezeArea` event):
--- caught inside it, she stands there for `seconds`.
function Karen:serverFreezeArea(_server, x, y, radius, seconds)
  local b = sv and sv.boss
  if b and (b.x - x) ^ 2 + (b.y - y) ^ 2 <= (radius + self.radius) ^ 2 then
    b.frozen = math.max(b.frozen or 0, seconds)
  end
end

--- Something stinks at (x, y) (the `serverPanicArea` event, raised every
--- tick a cloud hangs): Karen and any simp inside it run from it for a
--- moment.
function Karen:serverPanicArea(_server, x, y, radius)
  local b = sv and sv.boss
  if b and (b.x - x) ^ 2 + (b.y - y) ^ 2 <= (radius + self.radius) ^ 2 then
    b.panic = { x = x, y = y, left = 0.5 }
  end
  if sv and sv.simps then
    sv.simps:scare(x, y, radius, 0.5)
  end
end

function Karen:serverPlayerJoined(server, player)
  if not (sv and server.started) or player.bot then
    return -- a lobby join: `sv` may be the last game's
  end
  local b = sv.boss
  if b then
    server:send(player, Protocol.encode("KRN_SPAWN", fmt(b.x), fmt(b.y), math.max(0, b.hp), b.max))
  end
  for i = 1, sv.simps.n do
    local s = sv.simps.list[i]
    server:send(player, Protocol.encode("KRN_SIMP", s.id, s.name))
  end
end

--- Take `amount` off her. `by` is the player who did it (nil for nobody).
--- Returns true if that finished her.
function Karen:hurt(server, amount, by, angle)
  local b = sv and sv.boss
  if not b then
    return false
  end
  b.hp = b.hp - amount
  if b.hp > 0 then
    return false
  end
  local x, y = b.x, b.y
  sv.boss = nil
  server:broadcast(Protocol.encode("KRN_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0), by or 0))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, self.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, "karen", x, y) -- an EXIT star home where she fell
  end
  return true
end

--- A bullet passing through (x, y): the `serverShotAt` convention. She is
--- fat enough that it is hard to miss; failing her, a simp standing there
--- takes it.
function Karen:serverShotAt(server, x, y, radius, by, angle)
  if not sv then
    return false
  end
  local b = sv.boss
  if b and (b.x - x) ^ 2 + (b.y - y) ^ 2 < (radius + self.radius) ^ 2 then
    self:hurt(server, self.bulletDamage, by ~= 0 and by or nil, angle)
    return true
  end
  local s, i = sv.simps:at(x, y, radius)
  if not s then
    return false
  end
  local kill = sv.simps:hurt(s, Simps.SHOT_DAMAGE, by ~= 0 and by or nil, angle)
  if kill then
    sv.simps:removeAt(i)
    self:simpDown(server, kill)
  end
  return true
end

--- Where everyone's body is this tick, and the nearest one to her.
local function nearestBody(server, b)
  local best, bestD2, bx, by, onFoot
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y, foot = Features.bodyPose(server, p)
      local d2 = (x - b.x) ^ 2 + (y - b.y) ^ 2
      if not bestD2 or d2 < bestD2 then
        best, bestD2, bx, by, onFoot = p, d2, x, y, foot
      end
    end
  end
  return best, bestD2, bx, by, onFoot
end

--- Her pace: full tilt with breath in her, a walk without.
local function pace(b)
  return b.breath:pace(Karen.chargeSpeed, Karen.walkSpeed)
end

--- Cars driving into her: at speed they hurt her, get hurt and bounce off;
--- slower they only shove her a little.
function Karen:rams(server, b, dt)
  for id, t in pairs(b.rammed) do
    b.rammed[id] = t - dt
  end
  for id, p in pairs(server.players) do
    local car = p.vehicle
    if car and Features.present(p) then
      if Car.hitTest(car, b.x, b.y, self.radius) then
        local speed = math.abs(car.speed)
        local away = math.atan2(b.y - car.y, b.x - car.x)
        b.x, b.y = b.x + math.cos(away) * 40 * dt, b.y + math.sin(away) * 40 * dt
        if speed >= self.ramMinSpeed and (b.rammed[id] or 0) <= 0 then
          b.rammed[id] = 0.6
          local weapons = Features.byName.weapons
          if weapons and weapons.serverDamage then
            weapons:serverDamage(server, p, nil, self.ramDamageToCar, away + math.pi)
          end
          car.speed = -car.speed * 0.35 -- the car re-derives its velocity from this
          if self:hurt(server, speed * self.ramScale, id, car.angle) then
            return
          end
        end
      end
    end
  end
end

--- The gang's tick: arrivals while she stands, the hunt, and their sync.
function Karen:stepSimps(server, dt)
  local simps = sv.simps
  if simps.n == 0 and not sv.boss and sv.simpsOut == 0 then
    return
  end
  local kills, arrived = simps:update(server, dt, sv.boss)
  if arrived then
    server:broadcast(Protocol.encode("KRN_SIMP", arrived.id, arrived.name))
  end
  for _, kill in ipairs(kills) do
    self:simpDown(server, kill)
  end
  if sv.syncIn <= 0 and (simps.n > 0 or sv.simpsOut > 0) then
    local parts = { server.tick }
    for i = 1, simps.n do
      local s = simps.list[i]
      parts[#parts + 1] = s.id
      parts[#parts + 1] = ("%.0f"):format(s.x)
      parts[#parts + 1] = ("%.0f"):format(s.y)
      parts[#parts + 1] = ("%.2f"):format(s.facing)
      parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
      parts[#parts + 1] = s.swing > 0 and 1 or 0
    end
    local msg = Protocol.encode("KRN_SIMPS", unpack(parts))
    for _, player in pairs(server.players) do
      server:send(player, msg, true)
    end
    sv.simpsOut = simps.n
  end
end

function Karen:serverStep(server, dt)
  if not sv then
    return
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn < 0 then
    sv.syncIn = SYNC_EVERY - 1
  end
  self:stepSimps(server, dt)
  local b = sv.boss
  if not b then
    return
  end
  b.slapTimer = b.slapTimer - dt
  b.sayTimer = b.sayTimer - dt

  local target, d2, tx, ty, onFoot = nearestBody(server, b)
  local running = false -- at full tilt this tick: that is what costs her breath
  if (b.frozen or 0) > 0 then
    b.frozen = b.frozen - dt -- frozen: no charging, no slapping
    b.charging = false
  elseif b.panic then
    -- A stink: away from it, nose held, whatever else she was doing, as
    -- fast as her legs allow.
    b.charging, b.scream = false, nil
    b.panic.left = b.panic.left - dt
    b.facing = math.atan2(b.y - b.panic.y, b.x - b.panic.x)
    walk(b, b.facing, pace(b), dt)
    running = not b.breath:winded()
    if b.panic.left <= 0 then
      b.panic = nil
    end
  elseif b.scream then
    -- Feet planted, drawing breath; when the time is up it lands.
    b.charging = false
    b.scream.t = b.scream.t - dt
    if b.scream.t <= 0 then
      self:scream(server, b)
    end
  elseif target and d2 <= self.aggroRange ^ 2 then
    b.screamTimer = b.screamTimer - dt
    -- A scream takes breath: none while she is winded or nearly so (the
    -- timer stays run down, so it comes as soon as she has it back).
    if b.screamTimer <= 0 and d2 <= self.screamRange ^ 2 and b.breath:has(self.screamStamina) then
      b.screamTimer = self.screamEvery
      b.breath:spend(self.screamStamina)
      b.scream = { x = tx, y = ty, t = self.screamDelay }
      b.facing = math.atan2(ty - b.y, tx - b.x)
      server:broadcast(Protocol.encode("KRN_SCREAM_AIM", fmt(tx), fmt(ty), self.screamRadius,
        ("%.2f"):format(self.screamDelay)))
      return self:finishStep(server, b, dt, false)
    end
    b.charging = not b.breath:winded() -- winded, she comes on at a waddle
    b.facing = math.atan2(ty - b.y, tx - b.x)
    local dist = math.sqrt(d2)
    local reach = self.radius + self.slapReach + (onFoot and 0 or Car.HEIGHT / 2)
    if dist > reach then
      running = not b.breath:winded()
      if b.sidestep > 0 then
        b.sidestep = b.sidestep - dt
        walk(b, b.facing + b.side * math.pi / 2, pace(b), dt)
      else
        walk(b, b.facing, pace(b), dt)
        if b.stuck > 0.4 then
          b.stuck, b.sidestep, b.side = 0, 0.6, -b.side
        end
      end
    elseif b.slapTimer <= 0 then
      b.slapTimer = self.slapInterval
      local weapons = Features.byName.weapons
      if weapons and weapons.serverDamage then
        weapons:serverDamage(server, target, nil, self.slapDamage, b.facing)
      end
    end
  else
    b.charging = false
  end

  if b.sayTimer <= 0 then
    b.sayTimer = 4 + love.math.random() * 4
    server:broadcast(Protocol.encode("KRN_SAY", love.math.random(#self.lines)))
  end

  self:finishStep(server, b, dt, running)
end

--- The scream lands: everyone inside the area is hurt and told so.
function Karen:scream(server, b)
  local sc = b.scream
  b.scream = nil
  local caught = {}
  local weapons = Features.byName.weapons
  for id, p in pairs(server.players) do
    if Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local pad = onFoot and 7 or Car.WIDTH / 2
      if (x - sc.x) ^ 2 + (y - sc.y) ^ 2 <= (self.screamRadius + pad) ^ 2 then
        caught[#caught + 1] = id
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, self.screamDamage, math.atan2(y - sc.y, x - sc.x))
        end
      end
    end
  end
  server:broadcast(Protocol.encode("KRN_SCREAM", fmt(sc.x), fmt(sc.y), self.screamRadius, unpack(caught)))
end

--- The rest of her tick: her breath, cars hitting her, and her state to
--- everyone. `running` says whether she spent this tick at full tilt.
function Karen:finishStep(server, b, dt, running)
  b.breath:step(running, dt or 0)
  self:rams(server, b, dt or 0)
  b = sv.boss
  if not b then
    return -- a ram finished her
  end

  if sv.syncIn <= 0 then
    local msg = Protocol.encode("KRN_STATE", server.tick, fmt(b.x), fmt(b.y), ("%.2f"):format(b.facing),
      math.max(0, math.floor(b.hp)), b.charging and 1 or 0, b.breath:wire())
    for _, player in pairs(server.players) do
      server:send(player, msg, true)
    end
  end
end

--- For tests.
function Karen.server()
  return sv
end

-- Client --------------------------------------------------------------------

Karen.boss = nil -- { x, y, dx, dy, angle, hp, max, charging, stamina, winded, say, sayTimer, bob }
Karen.intro = nil -- { t, line } while the title screen is up
Karen.stain = nil -- { x, y, angle } where she went down
Karen.simps = {} -- id -> { name, x, y, dx, dy, angle, hp, swing, bob }
Karen.simpNames = {} -- id -> name, from KRN_SIMP (it lands before the first KRN_SIMPS)
Karen.screamAim = nil -- { x, y, r, t, total } while a scream is coming
Karen.screams = {} -- { x, y, r, t }: screams that just landed, for the rings
Karen.screamed = 0 -- seconds my screen still swims
local face, music = nil, nil
local time, lastTick, lastSimpTick = 0, 0, 0

local function startMusic()
  if not music then
    local started = love.timer.getTime()
    local sd = Theme.render()
    music = love.audio.newSource(sd, "static")
    music:setLooping(true)
    music:setRelative(true)
    print(("karen theme: %.1fs of audio rendered in %.2fs"):format(Theme.duration(), love.timer.getTime() - started))
  end
  music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  music:play()
end

local function stopMusic()
  if music then
    music:stop()
  end
end

function Karen:load()
  Sounds.load()
end

function Karen:exitGame()
  self.boss, self.intro, self.stain = nil, nil, nil
  self.simps, self.simpNames = {}, {}
  self.screamAim, self.screams, self.screamed = nil, {}, 0
  lastTick, lastSimpTick = 0, 0
  stopMusic()
end

--- The quest brought everyone to her street: the title screen and the theme.
function Karen:questStarted(_client, quest)
  if quest.boss ~= "karen" then
    return
  end
  face = face or KarenFace.new()
  self.intro = { t = self.introTime, line = self.lines[love.math.random(#self.lines)] }
  self.stain = nil
  startMusic()
end

function Karen:questEnded(_client, quest)
  if quest.boss == "karen" then
    self.intro, self.boss, self.stain = nil, nil, nil
    self.simps, self.simpNames = {}, {}
    self.screamAim, self.screams, self.screamed = nil, {}, 0
    stopMusic()
  end
end

function Karen:update(dt)
  time = time + dt
  if self.intro then
    self.intro.t = self.intro.t - dt
    face:update(dt)
    if self.intro.t <= 0 then
      self.intro = nil
    end
  end
  if music and music:isPlaying() then
    music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  end
  local b = self.boss
  if b then
    local ex, ey = b.x - b.dx, b.y - b.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      b.dx, b.dy = b.x, b.y
    else
      local k = math.min(1, dt * SMOOTHING)
      b.dx, b.dy = b.dx + ex * k, b.dy + ey * k
    end
    b.sayTimer = math.max(0, b.sayTimer - dt)
  end
  if self.screamAim then
    self.screamAim.t = self.screamAim.t - dt
    if self.screamAim.t <= -0.5 then
      self.screamAim = nil -- the landing never came (she went down first)
    end
  end
  for i = #self.screams, 1, -1 do
    local sc = self.screams[i]
    sc.t = sc.t + dt
    if sc.t > 0.7 then
      table.remove(self.screams, i)
    end
  end
  self.screamed = math.max(0, self.screamed - dt)
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(self.simps) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
    end
  end
end

--- Any key takes the title screen down.
function Karen:keypressed()
  if self.intro then
    self.intro = nil
  end
end

--- The title screen is soft; so is the world while a scream rings in my
--- ears, easing back as it fades.
function Karen:worldBlur()
  if self.intro then
    return 1
  end
  return math.min(1, self.screamed / self.screamBlur * 1.5)
end

Karen.clientMessages = {
  KRN_SPAWN = function(_client, args)
    local x, y, hp, max = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and hp and max then
      Karen.boss = {
        x = x, y = y, dx = x, dy = y, angle = math.pi / 2, hp = hp, max = max, charging = false,
        stamina = Stamina.defaults.max, winded = false, say = nil, sayTimer = 0, bob = love.math.random() * 6,
      }
      Karen.stain = nil
    end
  end,
  KRN_STATE = function(_client, args)
    local tick = tonumber(args[1])
    local b = Karen.boss
    if not (b and tick) or tick <= lastTick then
      return
    end
    lastTick = tick
    b.x, b.y = tonumber(args[2]) or b.x, tonumber(args[3]) or b.y
    b.angle = tonumber(args[4]) or b.angle
    b.hp = tonumber(args[5]) or b.hp
    b.charging = args[6] == "1"
    local stamina, winded = Stamina.read(args, 7)
    b.stamina, b.winded = stamina or b.stamina, winded
  end,
  KRN_SAY = function(_client, args)
    local b = Karen.boss
    local line = Karen.lines[tonumber(args[1]) or 0]
    if b and line then
      b.say, b.sayTimer = line, Karen.sayTime
    end
  end,
  KRN_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    Karen.boss = nil
    if x and y then
      Karen.stain = { x = x, y = y, angle = angle }
    end
  end,
  KRN_GONE = function()
    Karen.boss = nil
    Karen.screamAim = nil
  end,
  KRN_SCREAM_AIM = function(_client, args)
    local x, y, r, delay = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and delay then
      Karen.screamAim = { x = x, y = y, r = r, t = delay, total = delay }
    end
  end,
  KRN_SCREAM = function(client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (x and y and r) then
      return
    end
    Karen.screamAim = nil
    Karen.screams[#Karen.screams + 1] = { x = x, y = y, r = r, t = 0 }
    local b = Karen.boss
    Sounds.play("scream", b and b.dx or x, b and b.dy or y, 0.95 + love.math.random() * 0.1)
    for i = 4, #args do
      if tonumber(args[i]) == client.myId then
        Karen.screamed = Karen.screamBlur
      end
    end
  end,
  KRN_SIMP = function(_client, args)
    local id, name = tonumber(args[1]), args[2]
    if id and name then
      Karen.simpNames[id] = name
      local s = Karen.simps[id]
      if s then
        s.name = name
      end
    end
  end,
  KRN_SIMPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastSimpTick then
      return
    end
    lastSimpTick = tick
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = Karen.simps[id]
        if not s then
          s = { name = Karen.simpNames[id] or Simps.PREFIX, dx = x, dy = y, bob = love.math.random() * 6 }
          Karen.simps[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.hp = tonumber(args[i + 4]) or Simps.HEALTH
        s.swing = args[i + 5] == "1"
        seen[id] = true
      end
    end
    for id in pairs(Karen.simps) do
      if not seen[id] then
        Karen.simps[id] = nil
        Karen.simpNames[id] = nil
      end
    end
  end,
  KRN_SIMP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      Karen.simps[id] = nil
      Karen.simpNames[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
}

-- Drawing ---------------------------------------------------------------------

--- The ring on the ground where a scream is about to land: it fills as
--- she draws breath, so there is time to step out.
local function drawScreamAim(aim)
  local k = 1 - math.max(0, aim.t) / aim.total
  local pulse = 0.5 + 0.5 * math.sin(time * 14)
  love.graphics.setColor(0.95, 0.35, 0.6, 0.12 + 0.08 * pulse)
  love.graphics.circle("fill", aim.x, aim.y, aim.r, 48)
  love.graphics.setColor(0.95, 0.35, 0.6, 0.35)
  love.graphics.circle("fill", aim.x, aim.y, aim.r * k, 48)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.55, 0.75, 0.6 + 0.4 * pulse)
  love.graphics.circle("line", aim.x, aim.y, aim.r, 48)
  love.graphics.setLineWidth(1)
end

--- Where she went down: a wide stain and what is left of the outfit.
function Karen:drawBelowCars()
  if self.screamAim then
    drawScreamAim(self.screamAim)
  end
  local s = self.stain
  if not s then
    love.graphics.setColor(1, 1, 1)
    return
  end
  love.graphics.setColor(0.55, 0.08, 0.10, 0.85)
  love.graphics.ellipse("fill", s.x, s.y, 34, 26)
  for k = 0, 6 do
    local a = s.angle + (k - 3) * 0.5
    local d = 30 + (k * 17) % 22
    love.graphics.circle("fill", s.x + math.cos(a) * d, s.y + math.sin(a) * d, 5 + (k % 3) * 2)
  end
  love.graphics.setColor(BODY_COLOR)
  love.graphics.ellipse("fill", s.x + 8, s.y - 6, 12, 8)
  love.graphics.setColor(HAIR_COLOR)
  love.graphics.circle("fill", s.x - 14, s.y + 4, 7)
  love.graphics.setColor(1, 1, 1)
end

--- A speech bubble over her head, the tail pointing down at her.
local function drawBubble(x, y, text, alpha)
  local font = UI.fonts.small
  local maxW = 220
  local w, lines = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 16
  local h = #lines * font:getHeight() + 12
  local bx, by = x - w / 2, y - h - 14
  love.graphics.setColor(0, 0, 0, 0.5 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 6)
  love.graphics.setColor(1, 1, 1, 0.95 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 6)
  love.graphics.polygon("fill", x - 6, by + h - 1, x + 6, by + h - 1, x, by + h + 8)
  love.graphics.setFont(font)
  love.graphics.setColor(0.15, 0.05, 0.1, alpha)
  love.graphics.printf(text, bx + 8, by + 6, w - 16, "center")
end

--- A simp from above: a hoodie, a head, and a fist out front while the
--- punch lands. His name hangs over him, and a bar once he is hurt.
local function drawSimp(s)
  local x, y, r = s.dx, s.dy, Simps.RADIUS
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local swing = math.sin(time * 12 + s.bob) * 1.2
  local sx, sy = -fy * swing, fx * swing
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(SIMP_SKIN)
  if s.swing then
    love.graphics.circle("fill", x + fx * (r + 6), y + fy * (r + 6), 2.4, 6) -- the fist
  end
  love.graphics.circle("fill", x - fy * (r + 1) - sx, y + fx * (r + 1) - sy, 2, 6)
  love.graphics.circle("fill", x + fy * (r + 1) + sx, y - fx * (r + 1) + sy, 2, 6)
  love.graphics.setColor(SIMP_COLOR)
  love.graphics.circle("fill", x + sx * 0.5, y + sy * 0.5, r, 10)
  love.graphics.setColor(SIMP_SKIN)
  love.graphics.circle("fill", x + fx * 2, y + fy * 2, 3.2, 8)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(s.name, x - 59, y - r - 19, 120, "center")
  love.graphics.setColor(0.85, 0.85, 0.95)
  love.graphics.printf(s.name, x - 60, y - r - 20, 120, "center")
  if s.hp < Simps.HEALTH then
    local bw, f = 20, math.max(0, s.hp / Simps.HEALTH)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

--- Karen from above: a big body in a leopard-print top, arms out, a
--- handbag, a blonde bob, sunglasses on the head. She waddles; charging,
--- she waddles fast. Her simps are drawn first, so she is never under one.
--- A scream that just landed: rings spreading out over the area.
local function drawScream(sc)
  local k = sc.t / 0.7
  love.graphics.setLineWidth(3)
  for i = 0, 2 do
    local kk = k - i * 0.15
    if kk > 0 and kk < 1 then
      love.graphics.setColor(1, 0.55, 0.75, (1 - kk) * 0.9)
      love.graphics.circle("line", sc.x, sc.y, sc.r * (0.2 + 0.9 * kk), 48)
    end
  end
  love.graphics.setLineWidth(1)
end

function Karen:drawAboveCars()
  for _, s in pairs(self.simps) do
    drawSimp(s)
  end
  for _, sc in ipairs(self.screams) do
    drawScream(sc)
  end
  local b = self.boss
  if not b then
    love.graphics.setColor(1, 1, 1)
    return
  end
  local x, y, r = b.dx, b.dy, self.radius
  local fx, fy = math.cos(b.angle), math.sin(b.angle)
  local swing = math.sin(time * (b.charging and 13 or 5) + b.bob) * (b.charging and 2.2 or 1.2)
  local sx, sy = -fy * swing, fx * swing

  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + 4, y + 4, r + 1, 16)
  -- Arms, swinging opposite to the body.
  love.graphics.setColor(SKIN_COLOR)
  love.graphics.circle("fill", x - fy * (r + 3) - sx * 1.5, y + fx * (r + 3) - sy * 1.5, 5, 8)
  love.graphics.circle("fill", x + fy * (r + 3) - sx * 1.5, y - fx * (r + 3) - sy * 1.5, 5, 8)
  -- The handbag hangs off the left arm.
  love.graphics.setColor(BAG_COLOR)
  love.graphics.rectangle("fill", x - fy * (r + 7) - sx * 1.5 - 4, y + fx * (r + 7) - sy * 1.5 - 3, 9, 7, 2)
  -- Body and the print.
  love.graphics.setColor(BODY_COLOR)
  love.graphics.circle("fill", x + sx, y + sy, r, 16)
  love.graphics.setColor(SPOT_COLOR)
  for k = 0, 6 do
    local a = b.angle + k * 0.9
    local d = 4 + (k * 5) % 8
    love.graphics.circle("fill", x + sx + math.cos(a) * d, y + sy + math.sin(a) * d, 2.2, 6)
  end
  -- Head: hair behind, face forward, sunglasses on top.
  love.graphics.setColor(HAIR_COLOR)
  love.graphics.circle("fill", x + fx * 1 + sx * 0.5, y + fy * 1 + sy * 0.5, 10, 12)
  love.graphics.setColor(SKIN_COLOR)
  love.graphics.circle("fill", x + fx * 5 + sx * 0.5, y + fy * 5 + sy * 0.5, 6.5, 12)
  love.graphics.setColor(0.1, 0.08, 0.12)
  love.graphics.setLineWidth(2)
  love.graphics.line(x - fy * 5 + sx * 0.5, y + fx * 5 + sy * 0.5, x + fy * 5 + sx * 0.5, y - fx * 5 + sy * 0.5)
  love.graphics.setLineWidth(1)

  -- Health, always shown: she is the boss.
  local bw = 56
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y - r - 16, bw + 2, 6)
  local f = math.max(0, b.hp / b.max)
  love.graphics.setColor(1 - f, f, 0.2)
  love.graphics.rectangle("fill", x - bw / 2, y - r - 15, bw * f, 4)

  if b.say and b.sayTimer > 0 then
    drawBubble(x, y - r - 18, b.say, math.min(1, b.sayTimer * 2))
  end
  love.graphics.setColor(1, 1, 1)
end

--- The boss bar along the bottom of the screen.
local function drawBossBar(b)
  BossBar.draw({
    title = "CRAZY KAREN", titleColor = { 1, 0.55, 0.75 }, fill = { 0.9, 0.2, 0.45 },
    hp = b.hp, max = b.max, stamina = b.stamina, staminaMax = Stamina.defaults.max, winded = b.winded,
  })
end

--- The title screen: her face over rays, the quest's name, and what she is
--- complaining about this time. Laid out like the main menu.
local function drawIntro(intro)
  local w, h = love.graphics.getDimensions()
  local faceX, faceY = math.floor(w * 0.70), math.floor(h * 0.52)
  local faceScale = math.floor(math.min(h / 76, (w * 0.5) / 64))
  local radius = math.sqrt(w * w + h * h)

  love.graphics.setColor(0.12, 0.03, 0.07)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local a0 = time * 0.15
  for i = 0, 17 do
    if i % 2 == 0 then
      local a1 = a0 + i / 18 * 2 * math.pi
      local a2 = a0 + (i + 1) / 18 * 2 * math.pi
      love.graphics.setColor(0.30, 0.08, 0.18)
      love.graphics.polygon("fill", faceX, faceY,
        faceX + math.cos(a1) * radius, faceY + math.sin(a1) * radius,
        faceX + math.cos(a2) * radius, faceY + math.sin(a2) * radius)
    end
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", faceX, faceY, faceScale * 40)
  face:draw(faceX, faceY, faceScale)

  -- The left column: darkened, the quest's name and her complaint.
  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.12)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.print("QUEST", colX, y)
  y = y + 26
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("CRAZY KAREN IS AT IT AGAIN", colX + 3, y + 3, colW, "left")
  love.graphics.setColor(1, 0.55, 0.75)
  love.graphics.printf("CRAZY KAREN IS AT IT AGAIN", colX, y, colW, "left")
  local _, lines = UI.fonts.title:getWrap("CRAZY KAREN IS AT IT AGAIN", colW)
  y = y + #lines * UI.fonts.title:getHeight() + 6
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("let's end this.", colX, y)
  y = y + UI.fonts.heading:getHeight() + 36

  -- Her complaint, in a bubble that points at her.
  local font = UI.fonts.body
  local text = '"' .. intro.line .. '"'
  local _, tl = font:getWrap(text, colW - 32)
  local bh = #tl * font:getHeight() + 28
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", colX + 3, y + 4, colW, bh, 8)
  love.graphics.setColor(0.97, 0.95, 0.92)
  love.graphics.rectangle("fill", colX, y, colW, bh, 8)
  love.graphics.polygon("fill", colX + colW - 1, y + bh / 2 - 10, colX + colW - 1, y + bh / 2 + 10,
    colX + colW + 18, y + bh / 2)
  love.graphics.setFont(font)
  love.graphics.setColor(0.35, 0.05, 0.15)
  love.graphics.printf(text, colX + 16, y + 14, colW - 32, "left")

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.75)
  love.graphics.printf("press any key", 0, h - 40, w, "center")

  if Video.get("scanlines") then
    love.graphics.setColor(0, 0, 0, 0.18)
    for sy = 0, h, 4 do
      love.graphics.rectangle("fill", 0, sy, w, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Karen:drawHUD()
  if self.boss then
    drawBossBar(self.boss)
  end
  if self.intro then
    drawIntro(self.intro)
  end
  love.graphics.setColor(1, 1, 1)
end

return Karen
