-- Authoritative game server. Runs inside the hosting player's game.
--
-- The world is people and vehicles. Every player has a `body` (src/body.lua)
-- from the moment the game starts; `server.vehicles` holds every car in
-- the world (src/car.lua), each with an owner and, while someone is behind
-- the wheel, a driver. `player.vehicle` is the one they are driving (nil on
-- foot) and `player.car` the one they own, spawned with them and respawned
-- with them. Seat and unseat move a player between the two; features
-- decide when (on-foot asks for the driver, weapons for the wrecked).
--
-- STATE carries every vehicle in the world with its driver, then every
-- player who is on foot, so a client can tell who is driving what, who is
-- walking where, and who is gone for the moment.

local enet = require("enet")
local Protocol = require("src.net.protocol")
local Discovery = require("src.net.discovery")
local Car = require("src.car")
local Body = require("src.body")
local Features = require("src.features")

local Server = {}
Server.__index = Server

Server.MAX_PLAYERS = 8
Server.TICK = 1 / 30 -- simulation step, seconds
local CHANNELS = 2
local RELIABLE = 0
local STATE_CHANNEL = 1
local MAX_FRAME = 0.25 -- never simulate more than this per update (spiral of death guard)
local SPAWN_SPACING = 80

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

function Server.new(hostName)
  local ok, host = pcall(enet.host_create, "*:" .. Protocol.PORT, Server.MAX_PLAYERS, CHANNELS)
  if not ok or not host then
    return nil, ("could not open UDP port %d (already hosting?)"):format(Protocol.PORT)
  end

  local self = setmetatable({
    host = host,
    name = Protocol.sanitizeName(hostName),
    hostId = ("%04x%04x"):format(love.math.random(0, 0xffff), love.math.random(0, 0xffff)),
    players = {}, -- id -> { id, name, key, guest, peer, input, body, vehicle, car }
    byPeer = {}, -- peer:index() -> player
    nextId = 1,
    vehicles = {}, -- vehicle id -> Car
    nextVehicleId = 1,
    started = false,
    discoveryError = nil,
    tick = 0,
    accumulator = 0,
  }, Server)

  local responder, err = Discovery.newResponder(function()
    return self.name, self:playerCount(), Server.MAX_PLAYERS, self.hostId
  end)
  self.responder = responder
  self.discoveryError = err
  return self
end

function Server:playerCount()
  local n = 0
  for _ in pairs(self.players) do
    n = n + 1
  end
  return n
end

function Server:send(player, msg, unreliable)
  player.peer:send(msg, unreliable and 1 or RELIABLE, unreliable and "unreliable" or "reliable")
end

function Server:broadcast(msg, except)
  for _, p in pairs(self.players) do
    if p ~= except then
      p.peer:send(msg, RELIABLE, "reliable")
    end
  end
end

function Server:update(dt)
  if self.responder then
    self.responder:update()
  end
  while true do
    local ok, event = pcall(self.host.service, self.host, 0)
    if not ok or not event then
      break
    end
    if event.type == "receive" then
      self:onMessage(event.peer, event.data)
    elseif event.type == "disconnect" then
      self:onDisconnect(event.peer)
    end
    -- "connect" is ignored: a peer becomes a player once it sends HELLO.
  end

  if self.started then
    self.accumulator = math.min(self.accumulator + dt, MAX_FRAME)
    while self.accumulator >= Server.TICK do
      self.accumulator = self.accumulator - Server.TICK
      self:step(Server.TICK)
    end
  end
end

--- Everyone behind a wheel rides where their vehicle is.
function Server:seatBodies()
  for _, p in pairs(self.players) do
    local car = p.vehicle
    if car and p.body then
      p.body.x, p.body.y, p.body.facing = car.x, car.y, car.angle
    end
  end
end

function Server:step(dt)
  self.tick = self.tick + 1
  for _, car in pairs(self.vehicles) do
    if not (car.hidden or car.stowed) then
      local driver = car.driver and self.players[car.driver]
      local input = driver and driver.input
      if input then
        car:update(dt, input.throttle, input.steer, input.handbrake)
      else
        car:update(dt, 0, 0, false) -- parked: rolls to a stop
      end
    end
  end
  self:seatBodies()
  Features.call("serverStep", self, dt)
  self:seatBodies() -- features shove cars about (collisions); the drivers go with them
  self:broadcastState()
end

--- STATE <tick> <vehicles> [<vid> <x> <y> <angle> <speed> <driver>]... [<id> <x> <y> <facing>]...
--- Every vehicle in the world (a hidden or stowed one is out of it), then
--- everyone on foot. A player in neither list is driving something listed,
--- or gone.
function Server:broadcastState()
  local parts = { self.tick, 0 }
  local nv = 0
  for id, c in pairs(self.vehicles) do
    if not (c.hidden or c.stowed) then
      nv = nv + 1
      parts[#parts + 1] = id
      parts[#parts + 1] = ("%.1f"):format(c.x)
      parts[#parts + 1] = ("%.1f"):format(c.y)
      parts[#parts + 1] = ("%.3f"):format(c.angle)
      parts[#parts + 1] = ("%.0f"):format(c.speed)
      parts[#parts + 1] = c.driver or 0
    end
  end
  parts[2] = nv
  for id, p in pairs(self.players) do
    local b = p.body
    if b and not b.dead and not p.vehicle then
      parts[#parts + 1] = id
      parts[#parts + 1] = ("%.1f"):format(b.x)
      parts[#parts + 1] = ("%.1f"):format(b.y)
      parts[#parts + 1] = ("%.3f"):format(b.facing)
    end
  end
  local msg = Protocol.encode("STATE", unpack(parts))
  for _, p in pairs(self.players) do
    p.peer:send(msg, STATE_CHANNEL, "unreliable")
  end
end

-- Vehicles and bodies -------------------------------------------------------

--- Put a car into the world at (x, y). `owner` is the player it belongs to
--- (nil for one nobody owns); it is painted in their colour. Everyone hears
--- VEHICLE so they can paint it too.
function Server:spawnVehicle(x, y, angle, owner)
  local id = self.nextVehicleId
  self.nextVehicleId = id + 1
  local car = Car.new(x, y, angle)
  car.id, car.owner = id, owner
  car.color = owner and Car.colorIndexFor(owner) or love.math.random(#Car.PALETTE)
  self.vehicles[id] = car
  self:broadcast(Protocol.encode("VEHICLE", id, owner or 0, car.color))
  return car
end

--- Take a car out of the world for good. Whoever was driving it is left
--- standing where it was.
function Server:removeVehicle(car)
  if not car or self.vehicles[car.id] ~= car then
    return
  end
  local driver = car.driver and self.players[car.driver]
  if driver then
    self:unseat(driver)
  end
  self.vehicles[car.id] = nil
  self:broadcast(Protocol.encode("VEHICLE_GONE", car.id))
end

--- Put `player` behind the wheel of `car`. Refused if either is taken.
function Server:seat(player, car)
  if not (player.body and car) or car.driver or player.vehicle then
    return false
  end
  car.driver, player.vehicle = player.id, car
  player.body.x, player.body.y, player.body.facing = car.x, car.y, car.angle
  return true
end

--- Get `player` out of whatever they are driving, standing at (x, y) (the
--- car's spot when not given). The car stops where it is.
function Server:unseat(player, x, y)
  local car = player.vehicle
  if not car then
    return false
  end
  car.driver, player.vehicle = nil, nil
  car:stop()
  player.body.x, player.body.y, player.body.facing = x or car.x, y or car.y, car.angle
  return true
end

--- Where a player is: their vehicle, or their feet. Returns x, y, onFoot, facing.
function Server:pose(player)
  local car = player.vehicle
  if car then
    return car.x, car.y, false, car.angle
  end
  local b = player.body
  return b.x, b.y, true, b.facing
end

function Server:onMessage(peer, data)
  local kind, args = Protocol.decode(data)
  if kind == "HELLO" then
    self:onHello(peer, args[1], args[2])
  elseif kind == "INPUT" then
    self:onInput(peer, args)
  else
    local player = self.byPeer[peer:index()]
    if player then
      Features.handleServerMessage(self, player, kind, args)
    end
  end
end

function Server:onInput(peer, args)
  local player = self.byPeer[peer:index()]
  if not player then
    return
  end
  local seq = tonumber(args[1])
  if not seq or seq <= player.lastSeq then
    return -- stale or garbage
  end
  player.lastSeq = seq
  player.input.throttle = clamp(tonumber(args[2]) or 0, -1, 1)
  player.input.steer = clamp(tonumber(args[3]) or 0, -1, 1)
  player.input.handbrake = args[4] == "1"
end

--- The connected player holding `key`, if any.
function Server:playerByKey(key)
  for _, player in pairs(self.players) do
    if player.key == key then
      return player
    end
  end
  return nil
end

function Server:onHello(peer, name, key)
  local idx = peer:index()
  if self.byPeer[idx] then
    return
  end
  local reason
  if self.started then
    reason = "game already started"
  elseif self:playerCount() >= Server.MAX_PLAYERS then
    reason = "server full"
  end
  if reason then
    peer:send(Protocol.encode("REJECT", reason), RELIABLE, "reliable")
    peer:disconnect_later()
    return
  end

  -- A missing, malformed or already connected key (two copies of the game on
  -- one machine share one) plays under a throwaway key and is never saved.
  key = Protocol.sanitizeKey(key)
  local guest = not key or self:playerByKey(key) ~= nil
  if guest then
    key = Protocol.newKey()
  end

  local id = self.nextId
  self.nextId = id + 1
  local player = {
    id = id,
    name = Protocol.sanitizeName(name),
    key = key, -- lasting identity across sessions (docs/persistence.md); `id` is this session's
    guest = guest, -- true: throwaway key, not to be saved
    peer = peer,
    input = { throttle = 0, steer = 0 },
    lastSeq = 0,
    body = nil, -- Body once the game starts
    vehicle = nil, -- the car they are driving, nil on foot
    car = nil, -- the car they own
  }
  self.players[id] = player
  self.byPeer[idx] = player

  peer:send(Protocol.encode("WELCOME", id, self.name), RELIABLE, "reliable")
  -- Full roster to the newcomer (includes themselves), then announce to the rest.
  for _, other in pairs(self.players) do
    peer:send(Protocol.encode("JOIN", other.id, other.name), RELIABLE, "reliable")
  end
  self:broadcast(Protocol.encode("JOIN", id, player.name), player)
  Features.call("serverPlayerJoined", self, player)
end

function Server:onDisconnect(peer)
  local idx = peer:index()
  local player = self.byPeer[idx]
  if not player then
    return
  end
  self.byPeer[idx] = nil
  self.players[player.id] = nil
  self:unseat(player)
  if player.car then
    self:removeVehicle(player.car) -- their own car leaves with them
  end
  self:broadcast(Protocol.encode("LEAVE", player.id))
  Features.call("serverPlayerLeft", self, player)
end

function Server:start()
  if self.started then
    return
  end
  self.started = true
  self:spawnPlayers()
  Features.call("serverStart", self)
  self:broadcast(Protocol.encode("START"))
  self.host:flush()
end

--- Everyone gets a body and a car of their own, lined up side by side at
--- the origin facing up, and starts behind the wheel. A map feature moves
--- them to its own spawn points in serverStart.
function Server:spawnPlayers()
  local ids = {}
  for id in pairs(self.players) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local n = #ids
  for i, id in ipairs(ids) do
    local x = (i - 1 - (n - 1) / 2) * SPAWN_SPACING
    local p = self.players[id]
    p.body = Body.new(x, 0, -math.pi / 2)
    p.car = self:spawnVehicle(x, 0, -math.pi / 2, id)
    self:seat(p, p.car)
  end
end

--- A player added while the game is running (a bot): body, own car, seated.
function Server:spawnPlayer(player, x, y, angle)
  player.body = Body.new(x, y, angle)
  player.car = self:spawnVehicle(x, y, angle, player.id)
  self:seat(player, player.car)
  return player
end

function Server:close()
  for _, p in pairs(self.players) do
    p.peer:disconnect()
  end
  self.host:flush()
  self.players = {}
  self.byPeer = {}
  self.vehicles = {}
  if self.responder then
    self.responder:close()
    self.responder = nil
  end
  pcall(function()
    self.host:destroy()
  end)
end

return Server
