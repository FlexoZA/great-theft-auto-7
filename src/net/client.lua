-- Game client. The hosting player also runs one of these against 127.0.0.1.

local enet = require("enet")
local Protocol = require("src.net.protocol")
local Features = require("src.features")

local Client = {}
Client.__index = Client

local CHANNELS = 2
local RELIABLE = 0
local STATE_CHANNEL = 1
local CONNECT_TIMEOUT = 5 -- seconds
local INPUT_INTERVAL = 1 / 30 -- seconds between INPUT packets

-- state: idle -> connecting -> connected -> joined -> (disconnected | failed)

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
    cars = {}, -- id -> { id, x, y, angle, speed, dx, dy, dangle } (d* = smoothed for drawing)
    lastTick = 0,
    inputSeq = 0,
    inputTimer = 0,
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
      self.cars = {}
      self.myId = nil
    end
  end
end

--- Send the local input at a fixed rate. Call every frame with the frame dt.
function Client:sendInput(throttle, steer, dt)
  if self.state ~= "joined" or not self.peer then
    return
  end
  self.inputTimer = self.inputTimer - dt
  if self.inputTimer > 0 then
    return
  end
  self.inputTimer = self.inputTimer + INPUT_INTERVAL
  self.inputSeq = self.inputSeq + 1
  self.peer:send(Protocol.encode("INPUT", self.inputSeq, throttle, steer), STATE_CHANNEL, "unreliable")
end

function Client:onState(args)
  local tick = tonumber(args[1])
  if not tick or tick <= self.lastTick then
    return -- out of order, keep the newer snapshot
  end
  self.lastTick = tick
  local seen = {}
  for i = 2, #args - 4, 5 do
    local id = tonumber(args[i])
    local x, y = tonumber(args[i + 1]), tonumber(args[i + 2])
    local angle, speed = tonumber(args[i + 3]), tonumber(args[i + 4])
    if id and x and y and angle and speed then
      local c = self.cars[id]
      if c then
        c.x, c.y, c.angle, c.speed = x, y, angle, speed
      else
        self.cars[id] = { id = id, x = x, y = y, angle = angle, speed = speed, dx = x, dy = y, dangle = angle }
      end
      seen[id] = true
    end
  end
  for id in pairs(self.cars) do
    if not seen[id] then
      self.cars[id] = nil
    end
  end
end

function Client:myCar()
  return self.myId and self.cars[self.myId] or nil
end

function Client:onMessage(data)
  local kind, args = Protocol.decode(data)
  if kind == "WELCOME" then
    self.myId = tonumber(args[1])
    self.serverName = args[2]
    self.state = "joined"
  elseif kind == "JOIN" then
    local id = tonumber(args[1])
    if id then
      self.players[id] = { id = id, name = args[2] or "?" }
    end
  elseif kind == "LEAVE" then
    local id = tonumber(args[1])
    if id then
      self.players[id] = nil
      self.cars[id] = nil
    end
  elseif kind == "STATE" then
    self:onState(args)
  elseif kind == "START" then
    self.started = true
  elseif kind == "REJECT" then
    self.state = "failed"
    self.error = args[1] or "rejected"
  else
    Features.handleClientMessage(self, kind, args)
  end
end

--- Send a message to the server. Reliable by default; pass true for
--- high-frequency state that may be dropped.
function Client:send(msg, unreliable)
  if not self.peer or not self:isConnected() then
    return false
  end
  self.peer:send(msg, unreliable and STATE_CHANNEL or RELIABLE, unreliable and "unreliable" or "reliable")
  return true
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
  return self.state == "connected" or self.state == "joined"
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
  self.cars = {}
  self.myId = nil
end

return Client
