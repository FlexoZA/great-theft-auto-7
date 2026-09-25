-- Game client. The hosting player also runs one of these against 127.0.0.1.
--
-- What it knows of the world mirrors the server: `vehicles` (every car in
-- the world, with who is driving it) and `bodies` (every player on foot),
-- both refreshed by STATE, plus `garage`, what VEHICLE said about each
-- car's owner and colour. `pose(id)` answers where a player is drawn, in
-- either. Each snapshot carries x, y, angle from the server and dx, dy,
-- dangle eased towards them for drawing (the game state does the easing;
-- a body with `predicted` set is moved by a feature instead).

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

function Client.new(playerName, key)
  return setmetatable({
    host = enet.host_create(nil, 1, CHANNELS),
    name = Protocol.sanitizeName(playerName),
    key = key, -- this install's player key, sent in HELLO
    peer = nil,
    state = "idle",
    error = nil,
    myId = nil,
    serverName = nil,
    players = {}, -- id -> { id, name }
    known = {}, -- id -> name of everyone who has left (KNOWN, LEAVE); their cars may still be about
    started = false,
    connectTimer = 0,
    vehicles = {}, -- vehicle id -> { id, owner, color, driver, x, y, angle, speed, dx, dy, dangle }
    bodies = {}, -- player id -> { id, x, y, angle, dx, dy, dangle, predicted, running, bob }
    garage = {}, -- vehicle id -> { owner, color }, from VEHICLE, kept while a wreck is out of STATE
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
      self.peer:send(Protocol.encode("HELLO", self.name, self.key or ""), RELIABLE, "reliable")
    elseif event.type == "receive" then
      self:onMessage(event.data)
    elseif event.type == "disconnect" then
      if self.state ~= "failed" then
        self.state = "disconnected"
        self.error = self.error or "connection closed"
      end
      self.players = {}
      self.known = {}
      self.vehicles = {}
      self.bodies = {}
      self.garage = {}
      self.myId = nil
    end
  end
end

--- Send the local input at a fixed rate. Call every frame with the frame dt.
function Client:sendInput(throttle, steer, dt, handbrake)
  if self.state ~= "joined" or not self.peer then
    return
  end
  self.inputTimer = self.inputTimer - dt
  if self.inputTimer > 0 then
    return
  end
  self.inputTimer = self.inputTimer + INPUT_INTERVAL
  self.inputSeq = self.inputSeq + 1
  local msg = Protocol.encode("INPUT", self.inputSeq, throttle, steer, handbrake and 1 or 0)
  self.peer:send(msg, STATE_CHANNEL, "unreliable")
end

--- STATE <tick> <vehicles> [<vid> <x> <y> <angle> <speed> <driver>]... [<id> <x> <y> <facing>]...
function Client:onState(args)
  local tick, nv = tonumber(args[1]), tonumber(args[2])
  if not tick or not nv or tick <= self.lastTick then
    return -- out of order, keep the newer snapshot
  end
  self.lastTick = tick
  local seen = {}
  local i = 3
  for _ = 1, nv do
    local id = tonumber(args[i])
    local x, y = tonumber(args[i + 1]), tonumber(args[i + 2])
    local angle, speed, driver = tonumber(args[i + 3]), tonumber(args[i + 4]), tonumber(args[i + 5])
    i = i + 6
    if id and x and y and angle and speed then
      local v = self.vehicles[id]
      if not v then
        local info = self.garage[id]
        v = { id = id, owner = info and info.owner, color = info and info.color or 1, dx = x, dy = y, dangle = angle }
        self.vehicles[id] = v
      end
      v.x, v.y, v.angle, v.speed = x, y, angle, speed
      v.driver = driver ~= 0 and driver or nil
      seen[id] = true
    end
  end
  for id in pairs(self.vehicles) do
    if not seen[id] then
      self.vehicles[id] = nil -- a wreck waiting to come back, or gone for good
    end
  end
  local walking = {}
  while i <= #args - 3 do
    local id = tonumber(args[i])
    local x, y, facing = tonumber(args[i + 1]), tonumber(args[i + 2]), tonumber(args[i + 3])
    i = i + 4
    if id and x and y and facing then
      local b = self.bodies[id]
      if not b then
        b = { id = id, dx = x, dy = y, dangle = facing, bob = love.math.random() * 6 }
        self.bodies[id] = b
      end
      b.x, b.y, b.angle = x, y, facing
      walking[id] = true
    end
  end
  for id in pairs(self.bodies) do
    if not walking[id] then
      self.bodies[id] = nil -- got into something, or gone for the moment
    end
  end
end

--- The vehicle player `id` is driving, or nil.
function Client:vehicleOf(id)
  for _, v in pairs(self.vehicles) do
    if v.driver == id then
      return v
    end
  end
  return nil
end

--- Where player `id` is drawn: on foot or in a vehicle. Returns x, y,
--- onFoot, angle, or nil when they are not in the world just now (wrecked).
function Client:pose(id)
  local b = self.bodies[id]
  if b then
    return b.dx, b.dy, true, b.dangle
  end
  local v = self:vehicleOf(id)
  if v then
    return v.dx, v.dy, false, v.dangle
  end
  return nil
end

--- Is player `id` in the world (walking or driving) right now?
function Client:present(id)
  return self.bodies[id] ~= nil or self:vehicleOf(id) ~= nil
end

function Client:myVehicle()
  return self.myId and self:vehicleOf(self.myId) or nil
end

function Client:myBody()
  return self.myId and self.bodies[self.myId] or nil
end

function Client:myPose()
  if not self.myId then
    return nil
  end
  return self:pose(self.myId)
end

function Client:onMessage(data)
  local kind, args = Protocol.decode(data)
  if kind == "WELCOME" then
    self.myId = tonumber(args[1])
    self.serverName = args[2]
    self.serverId = args[3] -- lasting id of the world (src/net/recent.lua); nil from an older host
    self.worldName = args[4] ~= "" and args[4] or nil
    self.state = "joined"
  elseif kind == "JOIN" then
    local id = tonumber(args[1])
    if id then
      self.players[id] = { id = id, name = args[2] or "?" }
    end
  elseif kind == "LEAVE" then
    local id = tonumber(args[1])
    if id then
      self.known[id] = self.players[id] and self.players[id].name
      self.players[id] = nil
      self.bodies[id] = nil
    end
  elseif kind == "KNOWN" then
    local id = tonumber(args[1])
    if id then
      self.known[id] = args[2] or "?"
    end
  elseif kind == "STATE" then
    self:onState(args)
  elseif kind == "VEHICLE" then
    local id, owner, color = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id then
      self.garage[id] = { owner = owner ~= 0 and owner or nil, color = color or 1 }
      local v = self.vehicles[id]
      if v then
        v.owner, v.color = self.garage[id].owner, self.garage[id].color
      end
    end
  elseif kind == "VEHICLE_GONE" then
    local id = tonumber(args[1])
    if id then
      self.garage[id] = nil
      self.vehicles[id] = nil
    end
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

--- The name of player `id`, whether they are here or have left; nil if unknown.
function Client:nameOf(id)
  local p = self.players[id]
  if p then
    return p.name
  end
  return self.known[id]
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
  self.known = {}
  self.vehicles = {}
  self.bodies = {}
  self.garage = {}
  self.myId = nil
end

return Client
