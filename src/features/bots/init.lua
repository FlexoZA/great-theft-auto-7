-- Bots: AI drivers. They live only on the server as fake players with a stub
-- connection, so movement sync, hitboxes, health and respawns treat them
-- exactly like humans.
--
-- This feature is also the NPC toolkit for others: Bots:spawnNpc() creates
-- a driver with a custom `brain` (police uses one), and Bots.driveTowards,
-- Bots.unstick, Bots:cruise and Bots:fight are the shared driving skills.
-- The civilian bots below are just the default brain.
--
-- Each civilian bot drives a car picked at random from the shop's (the
-- vehicles feature's catalog), with that model's handling and hitpoints.
--
-- Bots are peaceful by default: they cruise the city's streets and ignore
-- players, keeping to the traffic rules in traffic.lua (right-hand lane, a
-- speed limit, slowing for turns, keeping their distance, waiting at a
-- busy crossing and stopping for anyone on foot); every so often one of
-- them drives recklessly for a while instead, which is where accidents and
-- police chases come from (a patrol that sees it run someone over or ram a
-- car wants it, and it fights back once shot at). Anyone on foot is who
-- the `serverWalkers` hook reports (pedestrians, officers) plus players out
-- of their cars. On a map without a street grid they drive between random
-- road waypoints instead, at the same speed. Shoot one or ram one and it turns hostile
-- towards you for a while, chasing, orbiting at a standoff distance and
-- shooting through the weapons feature with lead and a little spread. It
-- calms down again once it has been left alone for `hostileTime` seconds,
-- when its target stays further than `giveUpDistance` for `giveUpTime`
-- seconds, or when it gets wrecked (it respawns peaceful).
-- Other features can provoke a bot too (a trigger area later):
--   Features.byName.bots:provoke(server, botPlayer, playerId)
--
-- Host keys: B adds a bot, N removes the last one.
--
-- Messages
--   client -> server  BOT_ADD / BOT_REMOVE   (host only)
--   server -> all     BOT_UNIT <id>          (that player is a civilian bot; player-arrows leaves them out)

local Protocol = require("src.net.protocol")
local ServerSettings = require("src.server_settings")
local Features = require("src.features")
local Net = require("src.net")
local UI = require("src.ui")
local Controls = require("src.controls")
local Traffic = require("src.features.bots.traffic")

local Bots = {
  name = "bots",
  priority = 800, -- before weapons (950): bots must exist when weapons registers players
}

-- Tuning ------------------------------------------------------------------
Bots.startCount = 1 -- bots spawned when the game starts
Bots.maxBots = 6
Bots.range = 650 -- px; won't shoot beyond this
Bots.standoff = 220 -- px; closer than this it orbits instead of ramming
Bots.retargetEvery = 1.5 -- seconds
-- How well a bot fights, by the host's bot difficulty (src/server_settings,
-- set on the Settings screen's Server tab). Police units fight through the
-- same code, so it is their aim too.
--   spread        radians of random aim error either side of the target
--   fireInterval  seconds between shots (weapons enforces its own cooldown too)
--   hostileTime   seconds a bot stays angry after the last provocation
Bots.difficulties = {
  easy = { spread = 0.24, fireInterval = 0.8, hostileTime = 25 },
  normal = { spread = 0.14, fireInterval = 0.55, hostileTime = 40 },
  hard = { spread = 0.05, fireInterval = 0.35, hostileTime = 60 },
}
Bots.giveUpDistance = 1300 -- px; a target further than this is "away"
Bots.giveUpTime = 8 -- seconds the target must stay away before the bot gives up
Bots.ramSpeed = 120 -- closing speed (px/s) that counts as being rammed
Bots.cruiseSpeed = 170 -- px/s a peaceful bot keeps to (cars top out at 500 or so)
-- Now and then one civilian bot drives recklessly for a while (traffic.lua):
-- the accidents, and the police chases when a patrol sees one.
Bots.recklessSpeed = 330 -- px/s
Bots.recklessEvery = { 30, 60 } -- seconds between one reckless spell and the next
Bots.recklessFor = { 20, 35 } -- seconds a spell lasts
Bots.waypointRange = 1600 -- px; how far away a new waypoint may be
Bots.waypointTimeout = 25 -- seconds before giving up on a waypoint

local HOST_ID = 1

--- The numbers behind the host's chosen bot difficulty, read live so a
--- change on the Settings screen takes effect mid-game.
Bots.panicHold = 0.5 -- seconds an NPC keeps fleeing a stink after it was last told of it

function Bots:difficulty()
  return self.difficulties[ServerSettings.get("botDifficulty")] or self.difficulties.normal
end
local bots = {} -- civilian bots (the default brain), in spawn order
local npcs = {} -- every NPC, civilians included
local nextNumber = 1
local now = 0 -- server time, seconds since start
local nextReckless = 0 -- server time the next reckless spell starts
local walkers = {} -- everyone on foot this tick, flat: x, y, vx, vy per walker (traffic stops for them)

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function angleDiff(target, current)
  return (target - current + math.pi) % (2 * math.pi) - math.pi
end

--- Does the map in play want NPC cars on it? (city-map's `map.traffic`)
local function trafficWanted()
  local city = Features.byName["city-map"]
  return not (city and city.map and city.map.traffic == false)
end

--- Stands in for an ENet peer so core code can call peer:send etc.
local function stubPeer(id)
  local peer = {}
  function peer.send() end
  function peer.disconnect() end
  function peer.disconnect_later() end
  function peer.reset() end
  function peer.index()
    return -id
  end
  return peer
end

function Bots:load()
  Controls.register("bot-add", "Add a bot (host)", "b")
  Controls.register("bot-remove", "Remove a bot (host)", "n")
end

-- Server ----------------------------------------------------------------

--- Create any NPC driver: a player with a body and a car of its own, seated
--- (server:spawnPlayer). opts: name, x, y, angle, brain (table with
--- think(server, npc, dt), optional), plus any extra fields to copy onto the
--- player (e.g. police = true). Returns the player table. `npc.car` is the
--- car it drives, so a brain reads and steers that.
function Bots:spawnNpc(server, opts)
  local id = server.nextId
  server.nextId = id + 1
  local npc = {
    id = id,
    name = opts.name,
    peer = stubPeer(id),
    input = { throttle = 0, steer = 0 },
    lastSeq = 0,
    bot = true,
    brain = opts.brain,
    ai = {
      hostileTo = nil, -- player id this bot is angry at
      hostileUntil = 0,
      farFor = 0, -- seconds the target has been out of range
      waypoint = nil,
      waypointUntil = 0,
      retarget = 0,
      fireTimer = love.math.random() * self:difficulty().fireInterval,
      orbitDir = love.math.random() < 0.5 and -1 or 1,
      stuck = 0,
      reverseFor = 0,
    },
  }
  for k, v in pairs(opts) do
    if npc[k] == nil and k ~= "x" and k ~= "y" and k ~= "angle" then
      npc[k] = v
    end
  end
  server.players[id] = npc
  server:spawnPlayer(npc, opts.x, opts.y, opts.angle)
  npcs[#npcs + 1] = npc
  if not trafficWanted() then
    self:park(npc, true) -- born on a map with no traffic: wait out of sight
  end
  server:broadcast(Protocol.encode("JOIN", id, npc.name))
  Features.call("serverPlayerJoined", server, npc)
  return npc
end

--- Take an NPC off the road (hidden, still, peaceful; the core stops
--- broadcasting it) or put it back. Parked ones stay hidden even when
--- weapons brings a wreck back, until they are unparked.
function Bots:park(npc, parked)
  npc.parked = parked
  npc.car.hidden = parked
  if parked then
    npc.car:stop()
    npc.input.throttle, npc.input.steer = 0, 0
    self:calm(npc)
  end
end

--- Everyone was moved to another map (city-map's `mapChanged`; the host
--- passes `server`, clients get nil). NPC drivers are parked out of sight
--- on a map without traffic and back on the road, at the spawn points the
--- map put them on, when there is traffic again.
function Bots:mapChanged(map, server)
  if not server then
    return
  end
  for _, npc in ipairs(npcs) do
    self:park(npc, not map.traffic)
  end
end

function Bots:removeNpc(server, npc)
  for i = #npcs, 1, -1 do
    if npcs[i] == npc then
      table.remove(npcs, i)
    end
  end
  for i = #bots, 1, -1 do
    if bots[i] == npc then
      table.remove(bots, i)
    end
  end
  server:unseat(npc)
  server:removeVehicle(npc.car)
  server.players[npc.id] = nil
  server:broadcast(Protocol.encode("LEAVE", npc.id))
  Features.call("serverPlayerLeft", server, npc)
end

--- A civilian bot (default brain).
function Bots:add(server, x, y, angle)
  if #bots >= self.maxBots then
    return nil
  end
  local bot = self:spawnNpc(server, { name = "Bot " .. nextNumber, x = x, y = y, angle = angle })
  bot.wantsModel = true -- a random car from the shop, on the next tick (weapons must be up to give it its hitpoints)
  nextNumber = nextNumber + 1
  bots[#bots + 1] = bot
  server:broadcast(Protocol.encode("BOT_UNIT", bot.id))
  return bot
end

--- A player who arrives mid-game hears which players are bots. In the lobby
--- `bots` may still hold the last game's, so nothing is sent before the start.
function Bots:serverPlayerJoined(server, player)
  if player.bot or not server.started then
    return
  end
  for _, bot in ipairs(bots) do
    server:send(player, Protocol.encode("BOT_UNIT", bot.id))
  end
end

function Bots:removeLast(server)
  local bot = bots[#bots]
  if bot then
    self:removeNpc(server, bot)
  end
end

function Bots:serverStart(server)
  bots = {}
  npcs = {}
  nextNumber = 1
  now = 0
  nextReckless = self.recklessEvery[1] -- nobody at it in the first moments of a game
  local humans = 0
  for _ in pairs(server.players) do
    humans = humans + 1
  end
  for i = 1, self.startCount do
    local spawns = server.spawnPoints
    if spawns and #spawns > 0 then
      -- A map is loaded: take the next free spawn point after the humans.
      local s = spawns[(humans + i - 1) % #spawns + 1]
      self:add(server, s.x, s.y, s.angle)
    else
      -- No map: humans are lined up along x at y = 0 facing up; put bots ahead, facing back.
      local x = (i - 1 - (self.startCount - 1) / 2) * 120
      self:add(server, x, -450, math.pi / 2)
    end
  end
end

--- A random map spawn point if there is a map, else off to the side of the host.
local function spawnNearHost(server)
  local spawns = server.spawnPoints
  if spawns and #spawns > 0 then
    local s = spawns[love.math.random(#spawns)]
    return s.x, s.y, s.angle
  end
  local host = server.players[HOST_ID]
  local hx, hy = 0, 0
  if host and host.body then
    hx, hy = Features.bodyPose(server, host)
  end
  local a = love.math.random() * 2 * math.pi
  return hx + math.cos(a) * 500, hy + math.sin(a) * 500, a + math.pi
end

-- Client --------------------------------------------------------------------

Bots.ids = {} -- player id -> true for the civilian bots (the host says: BOT_UNIT)

function Bots:exitGame()
  self.ids = {}
end

Bots.clientMessages = {
  BOT_UNIT = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Bots.ids[id] = true
    end
  end,
}

Bots.serverMessages = {
  BOT_ADD = function(server, player)
    if player.id == HOST_ID and server.started then
      local x, y, angle = spawnNearHost(server)
      Bots:add(server, x, y, angle)
    end
  end,
  BOT_REMOVE = function(server, player)
    if player.id == HOST_ID then
      Bots:removeLast(server)
    end
  end,
}

-- Provocation -------------------------------------------------------------

--- Make `bot` hostile towards player `byId` (a human or another bot).
function Bots:provoke(_server, bot, byId)
  if not (bot and bot.bot and byId) or byId == bot.id then
    return
  end
  bot.ai.hostileTo = byId
  bot.ai.hostileUntil = now + self:difficulty().hostileTime
  bot.ai.farFor = 0
end

function Bots:calm(bot)
  bot.ai.hostileTo = nil
  bot.ai.farFor = 0
  bot.ai.recklessUntil = nil -- a fight or a wreck ends a reckless spell too
end

function Bots:serverPlayerDamaged(server, victim, attacker)
  if victim.bot and attacker then
    self:provoke(server, victim, attacker.id)
  end
end

function Bots:serverCarsCollided(server, rammer, rammed, closing)
  if rammed.bot and closing >= self.ramSpeed then
    self:provoke(server, rammed, rammer.id)
  end
end

function Bots:serverPlayerLeft(_server, player)
  for _, bot in ipairs(npcs) do
    if bot.ai.hostileTo == player.id then
      bot.ai.hostileTo = nil
    end
  end
end

-- Driving -----------------------------------------------------------------

--- Steer towards a world point; returns the distance to it.
function Bots.driveTowards(bot, tx, ty, throttle, orbit)
  local car, input, ai = bot.car, bot.input, bot.ai
  local dx, dy = tx - car.x, ty - car.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local heading = math.atan2(dy, dx)
  if orbit then
    heading = heading + ai.orbitDir * math.pi / 2
  end
  local err = angleDiff(heading, car.angle)
  input.steer = clamp(err / 0.4, -1, 1)
  input.throttle = throttle
  if math.abs(err) > 2.4 and dist < 120 and not orbit then
    input.throttle = -0.6 -- nose-to-nose with the target: back out
  end
  return dist
end

--- Wedged against a wall (throttle on, not moving): back out the other way for a moment.
function Bots.unstick(bot, dt)
  local car, input, ai = bot.car, bot.input, bot.ai
  if ai.reverseFor > 0 then
    ai.reverseFor = ai.reverseFor - dt
    input.throttle = -1
    input.steer = -input.steer
  elseif input.throttle > 0 and math.abs(car.speed) < 25 then
    ai.stuck = ai.stuck + dt
    if ai.stuck > 0.7 then
      ai.stuck = 0
      ai.reverseFor = 0.8 + love.math.random() * 0.6
      ai.orbitDir = -ai.orbitDir
      ai.waypoint = nil -- pick somewhere else afterwards
    end
  else
    ai.stuck = 0
  end
end

function Bots.newWaypoint(bot)
  local city = Features.byName["city-map"]
  local x, y
  if city and city.randomRoadPoint then
    x, y = city:randomRoadPoint(bot.car.x, bot.car.y, Bots.waypointRange)
  end
  if not x then
    local a = love.math.random() * 2 * math.pi
    x, y = bot.car.x + math.cos(a) * 600, bot.car.y + math.sin(a) * 600
  end
  bot.ai.waypoint = { x = x, y = y }
  bot.ai.waypointUntil = now + Bots.waypointTimeout
end

--- Drive peacefully at up to `speed` px/s (default cruiseSpeed): along the
--- streets by the traffic rules (traffic.lua) on a street grid, else
--- between random road waypoints. `reckless`: along the streets, by none
--- of the rules.
function Bots:cruise(server, bot, speed, reckless)
  speed = speed or self.cruiseSpeed
  local ai = bot.ai
  local city = Features.byName["city-map"]
  local graph = city and Traffic.graph(city.map)
  if graph then
    local v = Traffic.drive(bot, graph, speed, server.vehicles, walkers, server.dtLast or 0, reckless)
    bot.input.throttle = Traffic.throttleFor(bot.car, v)
    return
  end
  ai.route = nil
  if not ai.waypoint or now > ai.waypointUntil then
    Bots.newWaypoint(bot)
  end
  local dist = Bots.driveTowards(bot, ai.waypoint.x, ai.waypoint.y, 1, false)
  bot.input.throttle = Traffic.throttleFor(bot.car, speed)
  if dist < 110 then
    Bots.newWaypoint(bot)
  end
end

function Bots:fight(server, bot, target)
  local ai, car = bot.ai, bot.car
  local tc = target.vehicle
  -- The target is where their body is: the car they drive, or their feet.
  local tx, ty, onFoot = Features.bodyPose(server, target)
  local dx, dy = tx - car.x, ty - car.y
  local dist = math.sqrt(dx * dx + dy * dy)
  Bots.driveTowards(bot, tx, ty, 1, dist <= self.standoff)

  ai.retarget = ai.retarget - server.dtLast
  if ai.retarget <= 0 then
    ai.retarget = self.retargetEvery
    if love.math.random() < 0.3 then
      ai.orbitDir = -ai.orbitDir
    end
  end

  -- Shoot: lead the target by its velocity over the projectile's flight time.
  ai.fireTimer = ai.fireTimer - server.dtLast
  if ai.fireTimer <= 0 and dist < self.range then
    local skill = self:difficulty()
    ai.fireTimer = skill.fireInterval
    local Weapons = Features.byName.weapons
    if Weapons and Weapons.serverFire then
      local flight = dist / Weapons.PROJECTILE_SPEED
      local px, py = tx, ty
      if not onFoot then
        px = tc.x + math.cos(tc.angle) * tc.speed * flight
        py = tc.y + math.sin(tc.angle) * tc.speed * flight
      end
      local aim = math.atan2(py - car.y, px - car.x) + (love.math.random() - 0.5) * 2 * skill.spread
      Weapons:serverFire(server, bot, aim)
    end
  end
end

function Bots:think(server, bot, dt)
  local ai = bot.ai
  if ai.hostileTo and now > ai.hostileUntil then
    self:calm(bot) -- forgiven
  end
  local target = ai.hostileTo and server.players[ai.hostileTo]
  if target and Features.present(target) then
    local tx, ty = Features.bodyPose(server, target)
    local dist = math.sqrt((tx - bot.car.x) ^ 2 + (ty - bot.car.y) ^ 2)
    if dist > self.giveUpDistance then
      ai.farFor = ai.farFor + dt
      if ai.farFor >= self.giveUpTime then
        self:calm(bot) -- they got away
        target = nil
      end
    else
      ai.farFor = 0
    end
  end
  if target and Features.present(target) then
    self:fight(server, bot, target)
  elseif ai.recklessUntil and now < ai.recklessUntil then
    self:cruise(server, bot, self.recklessSpeed, true)
  else
    self:cruise(server, bot)
  end
  Bots.unstick(bot, dt)
end

--- Something stinks at (x, y) (the `serverPanicArea` event, raised every
--- tick a cloud hangs): every NPC car inside `radius`, whatever its brain,
--- drives away from it for the next moment.
function Bots:serverPanicArea(_server, x, y, radius)
  for _, npc in ipairs(npcs) do
    local car = npc.car
    if car and not car.hidden and (car.x - x) ^ 2 + (car.y - y) ^ 2 <= radius ^ 2 then
      npc.panic = { x = x, y = y, untilT = now + self.panicHold }
    end
  end
end

--- Drive `npc` straight away from what it is panicking about.
local function flee(npc)
  local car, p = npc.car, npc.panic
  local dx, dy = car.x - p.x, car.y - p.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then
    dx, dy, d = math.cos(car.angle), math.sin(car.angle), 1
  end
  Bots.driveTowards(npc, car.x + dx / d * 400, car.y + dy / d * 400, 1)
end

--- Everyone on foot, for the traffic to stop for: players out of their
--- cars, and whoever features report through `serverWalkers`.
local function collectWalkers(server)
  local n = 0
  local function add(x, y, vx, vy)
    walkers[n + 1], walkers[n + 2], walkers[n + 3], walkers[n + 4] = x, y, vx or 0, vy or 0
    n = n + 4
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      if onFoot then
        add(x, y)
      end
    end
  end
  Features.call("serverWalkers", server, add)
  for k = #walkers, n + 1, -1 do
    walkers[k] = nil
  end
end

local function between(range)
  return range[1] + love.math.random() * (range[2] - range[1])
end

--- Time for someone to drive badly? One civilian bot on the road, peaceful
--- and not already at it, goes reckless for a spell.
local function maybeReckless()
  if now < nextReckless then
    return
  end
  nextReckless = now + between(Bots.recklessEvery)
  local calm = {}
  for _, bot in ipairs(bots) do
    if not bot.car.hidden and not bot.ai.hostileTo and not (bot.ai.recklessUntil and now < bot.ai.recklessUntil) then
      calm[#calm + 1] = bot
    end
  end
  if #calm > 0 then
    calm[love.math.random(#calm)].ai.recklessUntil = now + between(Bots.recklessFor)
  end
end

function Bots:serverStep(server, dt)
  now = now + dt
  server.dtLast = dt
  collectWalkers(server)
  maybeReckless()
  local vehicles = Features.byName.vehicles
  for _, bot in ipairs(bots) do
    if bot.wantsModel and bot.car then
      bot.wantsModel = nil
      if vehicles and vehicles.serverRandomModel then
        vehicles:serverRandomModel(server, bot.car)
      end
    end
  end
  for _, npc in ipairs(npcs) do
    if npc.parked then
      npc.car.hidden = true -- a wreck's timer running out must not put a parked car back
    end
    if npc.panic and now >= npc.panic.untilT then
      npc.panic = nil
    end
    if npc.car and not npc.car.hidden then
      if npc.panic then
        flee(npc) -- a stink cloud: nose away from it, whatever the brain would do
        Bots.unstick(npc, dt)
      elseif npc.brain then
        npc.brain.think(server, npc, dt)
      else
        self:think(server, npc, dt)
      end
    elseif npc.car then
      npc.input.throttle, npc.input.steer = 0, 0 -- wrecked: sit still until respawn
      self:calm(npc) -- and come back peaceful
      if npc.brain and npc.brain.wrecked then
        npc.brain.wrecked(server, npc)
      end
    end
  end
end

-- Client ----------------------------------------------------------------

function Bots:keypressed(key, client)
  if not Net.isHost() then
    return
  end
  if Controls.is("bot-add", key) then
    client:send(Protocol.encode("BOT_ADD"))
  elseif Controls.is("bot-remove", key) then
    client:send(Protocol.encode("BOT_REMOVE"))
  end
end

function Bots:drawHUD()
  if Net.isHost() then
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.6, 0.6, 0.65)
    local add = Controls.name(Controls.bindings("bot-add")[1])
    local remove = Controls.name(Controls.bindings("bot-remove")[1])
    love.graphics.print(add .. ": add bot   " .. remove .. ": remove bot", 10, 82)
    love.graphics.setColor(1, 1, 1)
  end
end

--- Civilian bots, for tests and other features.
function Bots.list()
  return bots
end

--- Every NPC driver.
function Bots.npcs()
  return npcs
end

return Bots
