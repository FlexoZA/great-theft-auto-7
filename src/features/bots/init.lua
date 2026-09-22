-- Bots: AI drivers. They live only on the server as fake players with a stub
-- connection, so movement sync, hitboxes, health and respawns treat them
-- exactly like humans.
--
-- Bots are peaceful by default: they cruise the city between random road
-- waypoints and ignore players. Shoot one or ram one and it turns hostile
-- towards you for a while, chasing, orbiting at a standoff distance and
-- shooting through the weapons feature with lead and a little spread. It
-- calms down again once it has been left alone for `hostileTime` seconds.
-- Other features can provoke a bot too (a trigger area later):
--   Features.byName.bots:provoke(server, botPlayer, playerId)
--
-- Host keys: B adds a bot, N removes the last one.
--
-- Messages
--   client -> server  BOT_ADD / BOT_REMOVE   (host only)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Net = require("src.net")
local UI = require("src.ui")
local Car = require("src.car")
local Controls = require("src.controls")

local Bots = {
  name = "bots",
  priority = 800, -- before weapons (950): bots must exist when weapons registers players
}

-- Tuning ------------------------------------------------------------------
Bots.startCount = 1 -- bots spawned when the game starts
Bots.maxBots = 6
Bots.fireInterval = 0.5 -- seconds between shots (weapons enforces its own cooldown too)
Bots.range = 650 -- px; won't shoot beyond this
Bots.spread = 0.08 -- radians of random aim error
Bots.standoff = 220 -- px; closer than this it orbits instead of ramming
Bots.retargetEvery = 1.5 -- seconds
Bots.hostileTime = 40 -- seconds a bot stays angry after the last provocation
Bots.ramSpeed = 120 -- closing speed (px/s) that counts as being rammed
Bots.cruiseThrottle = 0.65 -- how hard a peaceful bot drives
Bots.waypointRange = 1600 -- px; how far away a new waypoint may be
Bots.waypointTimeout = 25 -- seconds before giving up on a waypoint

local HOST_ID = 1
local bots = {} -- ordered list of bot players on the server
local nextNumber = 1
local now = 0 -- server time, seconds since start

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local function angleDiff(target, current)
  return (target - current + math.pi) % (2 * math.pi) - math.pi
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

function Bots:add(server, x, y, angle)
  if #bots >= self.maxBots then
    return nil
  end
  local id = server.nextId
  server.nextId = id + 1
  local bot = {
    id = id,
    name = "Bot " .. nextNumber,
    peer = stubPeer(id),
    input = { throttle = 0, steer = 0 },
    lastSeq = 0,
    car = Car.new(x, y, angle),
    bot = true,
    ai = {
      hostileTo = nil, -- player id this bot is angry at
      hostileUntil = 0,
      waypoint = nil,
      waypointUntil = 0,
      retarget = 0,
      fireTimer = love.math.random() * self.fireInterval,
      orbitDir = love.math.random() < 0.5 and -1 or 1,
      stuck = 0,
      reverseFor = 0,
    },
  }
  nextNumber = nextNumber + 1
  server.players[id] = bot
  bots[#bots + 1] = bot
  server:broadcast(Protocol.encode("JOIN", id, bot.name))
  Features.call("serverPlayerJoined", server, bot)
  return bot
end

function Bots:removeLast(server)
  local bot = table.remove(bots)
  if not bot then
    return
  end
  server.players[bot.id] = nil
  server:broadcast(Protocol.encode("LEAVE", bot.id))
  Features.call("serverPlayerLeft", server, bot)
end

function Bots:serverStart(server)
  bots = {}
  nextNumber = 1
  now = 0
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
  if host and host.car then
    hx, hy = host.car.x, host.car.y
  end
  local a = love.math.random() * 2 * math.pi
  return hx + math.cos(a) * 500, hy + math.sin(a) * 500, a + math.pi
end

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
  bot.ai.hostileUntil = now + self.hostileTime
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
  for _, bot in ipairs(bots) do
    if bot.ai.hostileTo == player.id then
      bot.ai.hostileTo = nil
    end
  end
end

-- Driving -----------------------------------------------------------------

--- Steer towards a world point; returns the distance to it.
local function driveTowards(bot, tx, ty, throttle, orbit)
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
local function unstick(bot, dt)
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

local function newWaypoint(bot)
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

function Bots:cruise(bot)
  local ai = bot.ai
  if not ai.waypoint or now > ai.waypointUntil then
    newWaypoint(bot)
  end
  local dist = driveTowards(bot, ai.waypoint.x, ai.waypoint.y, self.cruiseThrottle, false)
  if dist < 110 then
    newWaypoint(bot)
  end
end

function Bots:fight(server, bot, target)
  local ai, car = bot.ai, bot.car
  local tc = target.car
  local dx, dy = tc.x - car.x, tc.y - car.y
  local dist = math.sqrt(dx * dx + dy * dy)
  driveTowards(bot, tc.x, tc.y, 1, dist <= self.standoff)

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
    ai.fireTimer = self.fireInterval
    local Weapons = Features.byName.weapons
    if Weapons and Weapons.serverFire then
      local flight = dist / Weapons.PROJECTILE_SPEED
      local px = tc.x + math.cos(tc.angle) * tc.speed * flight
      local py = tc.y + math.sin(tc.angle) * tc.speed * flight
      local aim = math.atan2(py - car.y, px - car.x) + (love.math.random() - 0.5) * 2 * self.spread
      Weapons:serverFire(server, bot, aim)
    end
  end
end

function Bots:think(server, bot, dt)
  local ai = bot.ai
  if ai.hostileTo and now > ai.hostileUntil then
    ai.hostileTo = nil -- forgiven
  end
  local target = ai.hostileTo and server.players[ai.hostileTo]
  if target and target.car and not target.car.hidden then
    self:fight(server, bot, target)
  else
    self:cruise(bot)
  end
  unstick(bot, dt)
end

function Bots:serverStep(server, dt)
  now = now + dt
  server.dtLast = dt
  for _, bot in ipairs(bots) do
    if bot.car and not bot.car.hidden then
      self:think(server, bot, dt)
    elseif bot.car then
      bot.input.throttle, bot.input.steer = 0, 0 -- wrecked: sit still until respawn
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

--- For tests and other features.
function Bots.list()
  return bots
end

return Bots
