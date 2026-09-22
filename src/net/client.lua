-- Game client. The hosting player also runs one of these against 127.0.0.1.

local enet = require("enet")
local Protocol = require("src.net.protocol")

local Client = {}
Client.__index = Client

local CHANNELS = 2
local RELIABLE = 0
local CONNECT_TIMEOUT = 5 -- seconds

-- state: idle -> connecting -> connected -> lobby -> (disconnected | failed)

function Client.new(playerName)
  return setmetatable({
    host = enet.host_create(nil, 1, CHANNELS),
    name = Protocol.sanitizeName(playerName),
    peer = nil,
    state = "idle",
    error = nil,
    myId = nil,
    serverName = nil,
    players = {}, -- id -> { id, name }
    started = false,
    connectTimer = 0,
  }, Client)
end

function Client:connect(ip, port)
  local address = ("%s:%d"):format(ip, port or Protocol.PORT)
  local ok, peer = pcall(self.host.connect, self.host, address, CHANNELS)
  if not ok or not peer then
    self.state = "failed"
    self.error = "bad address " .. address
    return false
  end
  self.peer = peer
  self.address = address
  self.state = "connecting"
  self.connectTimer = CONNECT_TIMEOUT
  return true
end

function Client:update(dt)
  if self.state == "connecting" then
    self.connectTimer = self.connectTimer - dt
    if self.connectTimer <= 0 then
      self.state = "failed"
      self.error = "no answer from " .. tostring(self.address)
      self.peer:reset()
      return
    end
  end

  while true do
    local ok, event = pcall(self.host.service, self.host, 0)
    if not ok or not event then
      break
    end
    if event.type == "connect" then
      self.state = "connected"
      self.peer:send(Protocol.encode("HELLO", self.name), RELIABLE, "reliable")
    elseif event.type == "receive" then
      self:onMessage(event.data)
    elseif event.type == "disconnect" then
      if self.state ~= "failed" then
        self.state = "disconnected"
        self.error = self.error or "connection closed"
      end
      self.players = {}
      self.myId = nil
    end
  end
end

function Client:onMessage(data)
  local kind, args = Protocol.decode(data)
  if kind == "WELCOME" then
    self.myId = tonumber(args[1])
    self.serverName = args[2]
    self.state = "lobby"
  elseif kind == "JOIN" then
    local id = tonumber(args[1])
    if id then
      self.players[id] = { id = id, name = args[2] or "?" }
    end
  elseif kind == "LEAVE" then
    local id = tonumber(args[1])
    if id then
      self.players[id] = nil
    end
  elseif kind == "START" then
    self.started = true
  elseif kind == "REJECT" then
    self.state = "failed"
    self.error = args[1] or "rejected"
  end
end

--- Players sorted by id (id 1 is the host).
function Client:playerList()
  local out = {}
  for _, p in pairs(self.players) do
    out[#out + 1] = p
  end
  table.sort(out, function(a, b)
    return a.id < b.id
  end)
  return out
end

function Client:playerCount()
  return #self:playerList()
end

function Client:isConnected()
  return self.state == "connected" or self.state == "lobby"
end

function Client:disconnect()
  if self.peer then
    pcall(function()
      self.peer:disconnect()
      self.host:flush()
    end)
    self.peer = nil
  end
  self.state = "idle"
  self.players = {}
  self.myId = nil
end

return Client
