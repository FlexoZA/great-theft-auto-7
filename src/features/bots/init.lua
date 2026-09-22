-- Bots: AI drivers for testing. They live only on the server as fake players
-- with a stub connection, so movement sync, hitboxes, health and respawns
-- treat them exactly like humans. Each bot chases the nearest car, orbits it
-- at a standoff distance and shoots through the weapons feature with lead
-- and a little spread.
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

local HOST_ID = 1
local bots = {} -- ordered list of bot players on the server
local nextNumber = 1

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
      target = nil,
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

local function pickTarget(server, bot)
  local best, bestCost
  for id, p in pairs(server.players) do
    if id ~= bot.id and p.car and not p.car.hidden then
      local dx, dy = p.car.x - bot.car.x, p.car.y - bot.car.y
      local cost = math.sqrt(dx * dx + dy * dy) * (p.bot and 1.5 or 1) -- prefer humans
      if not bestCost or cost < bestCost then
        best, bestCost = id, cost
      end
    end
  end
  return best
end

function Bots:think(server, bot, dt)
  local ai, car, input = bot.ai, bot.car, bot.input

  ai.retarget = ai.retarget - dt
  if ai.retarget <= 0 or not (ai.target and server.players[ai.target]) then
    ai.target = pickTarget(server, bot)
    ai.retarget = self.retargetEvery
    if love.math.random() < 0.3 then
      ai.orbitDir = -ai.orbitDir
    end
  end

  local target = ai.target and server.players[ai.target]
  if not (target and target.car) then
    input.throttle, input.steer = 0.6, 0.4 -- nobody around: cruise in a circle
    return
  end

  local tc = target.car
  local dx, dy = tc.x - car.x, tc.y - car.y
  local dist = math.sqrt(dx * dx + dy * dy)
  local toTarget = math.atan2(dy, dx)

  -- Drive: head for the target, or circle it once close.
  local desired = dist > self.standoff and toTarget or (toTarget + ai.orbitDir * math.pi / 2)
  local err = angleDiff(desired, car.angle)
  input.steer = clamp(err / 0.4, -1, 1)
  if math.abs(err) > 2.4 and dist < 120 then
    input.throttle = -0.6 -- nose-to-nose and stuck: back out
  else
    input.throttle = 1
  end

  -- Wedged against a wall (throttle on, not moving): back out the other way for a moment.
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
    end
  else
    ai.stuck = 0
  end

  -- Shoot: lead the target by its velocity over the projectile's flight time.
  ai.fireTimer = ai.fireTimer - dt
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

function Bots:serverStep(server, dt)
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
