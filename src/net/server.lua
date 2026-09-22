-- Authoritative game server. Runs inside the hosting player's game.

local enet = require("enet")
local Protocol = require("src.net.protocol")
local Discovery = require("src.net.discovery")

local Server = {}
Server.__index = Server

Server.MAX_PLAYERS = 8
local CHANNELS = 2
local RELIABLE = 0

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

function Server:update()
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
end

function Server:onMessage(peer, data)
  local kind, args = Protocol.decode(data)
  if kind == "HELLO" then
    self:onHello(peer, args[1])
  end
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
  local player = { id = id, name = Protocol.sanitizeName(name), peer = peer }
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
  self:broadcast(Protocol.encode("START"))
  self.host:flush()
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
