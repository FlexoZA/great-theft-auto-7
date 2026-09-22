-- Authoritative game server. Runs inside the hosting player's game.

local enet = require("enet")
local Protocol = require("src.net.protocol")
local Discovery = require("src.net.discovery")
local Car = require("src.car")

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
    players = {}, -- id -> { id, name, peer }
    byPeer = {}, -- peer:index() -> player
    nextId = 1,
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

function Server:step(dt)
  self.tick = self.tick + 1
  for _, p in pairs(self.players) do
    if p.car then
      p.car:update(dt, p.input.throttle, p.input.steer)
    end
  end
  self:broadcastState()
end

function Server:broadcastState()
  local parts = { self.tick }
  for _, p in pairs(self.players) do
    if p.car then
      local c = p.car
      parts[#parts + 1] = p.id
      parts[#parts + 1] = ("%.1f"):format(c.x)
      parts[#parts + 1] = ("%.1f"):format(c.y)
      parts[#parts + 1] = ("%.3f"):format(c.angle)
      parts[#parts + 1] = ("%.0f"):format(c.speed)
    end
  end
  local msg = Protocol.encode("STATE", unpack(parts))
  for _, p in pairs(self.players) do
    p.peer:send(msg, STATE_CHANNEL, "unreliable")
  end
end

function Server:onMessage(peer, data)
  local kind, args = Protocol.decode(data)
  if kind == "HELLO" then
    self:onHello(peer, args[1])
  elseif kind == "INPUT" then
    self:onInput(peer, args)
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
end

function Server:onHello(peer, name)
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

  local id = self.nextId
  self.nextId = id + 1
  local player = {
    id = id,
    name = Protocol.sanitizeName(name),
    peer = peer,
    input = { throttle = 0, steer = 0 },
    lastSeq = 0,
    car = nil,
  }
  self.players[id] = player
  self.byPeer[idx] = player

  peer:send(Protocol.encode("WELCOME", id, self.name), RELIABLE, "reliable")
  -- Full roster to the newcomer (includes themselves), then announce to the rest.
  for _, other in pairs(self.players) do
    peer:send(Protocol.encode("JOIN", other.id, other.name), RELIABLE, "reliable")
  end
  self:broadcast(Protocol.encode("JOIN", id, player.name), player)
end

function Server:onDisconnect(peer)
  local idx = peer:index()
  local player = self.byPeer[idx]
  if not player then
    return
  end
  self.byPeer[idx] = nil
  self.players[player.id] = nil
  self:broadcast(Protocol.encode("LEAVE", player.id))
end

function Server:start()
  if self.started then
    return
  end
  self.started = true
  self:spawnCars()
  self:broadcast(Protocol.encode("START"))
  self.host:flush()
end

--- Line everyone up side by side at the origin, facing up.
function Server:spawnCars()
  local ids = {}
  for id in pairs(self.players) do
    ids[#ids + 1] = id
  end
  table.sort(ids)
  local n = #ids
  for i, id in ipairs(ids) do
    local x = (i - 1 - (n - 1) / 2) * SPAWN_SPACING
    self.players[id].car = Car.new(x, 0, -math.pi / 2)
  end
end

function Server:close()
  for _, p in pairs(self.players) do
    p.peer:disconnect()
  end
  self.host:flush()
  self.players = {}
  self.byPeer = {}
  if self.responder then
    self.responder:close()
    self.responder = nil
  end
  pcall(function()
    self.host:destroy()
  end)
end

return Server
