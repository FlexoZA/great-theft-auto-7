-- LAN discovery over UDP broadcast (ENet cannot broadcast).
-- Host runs a Responder; joiners run a Scanner.

local socket = require("socket")
local Protocol = require("src.net.protocol")

local Discovery = {}

local MAX_PACKETS_PER_UPDATE = 32

-- Responder (host side) -----------------------------------------------------

local Responder = {}
Responder.__index = Responder

--- getInfo() must return: hostName, playerCount, maxPlayers, hostId, worldName ("" if none)
function Discovery.newResponder(getInfo)
  local udp = socket.udp()
  udp:settimeout(0)
  local ok, err = udp:setsockname("*", Protocol.DISCOVERY_PORT)
  if not ok then
    udp:close()
    return nil, ("discovery port %d busy: %s"):format(Protocol.DISCOVERY_PORT, tostring(err))
  end
  return setmetatable({ udp = udp, getInfo = getInfo }, Responder)
end

function Responder:update()
  for _ = 1, MAX_PACKETS_PER_UPDATE do
    local data, ip, port = self.udp:receivefrom()
    if not data then
      break
    end
    if data == Protocol.DISCOVER_MAGIC then
      local name, count, max, hostId, worldName = self.getInfo()
      local reply = Protocol.encode(Protocol.HOST_MAGIC, hostId, name, Protocol.PORT, count, max, worldName or "")
      self.udp:sendto(reply, ip, port)
    end
  end
end

function Responder:close()
  self.udp:close()
end

-- Scanner (joiner side) -----------------------------------------------------

local Scanner = {}
Scanner.__index = Scanner

function Discovery.newScanner()
  local udp = socket.udp()
  udp:settimeout(0)
  udp:setoption("broadcast", true)
  udp:setsockname("*", 0)
  return setmetatable({
    udp = udp,
    hosts = {}, -- hostId -> { ip, port, name, world, players, maxPlayers, lastSeen }
    probes = {}, -- addresses asked directly as well (servers joined before, maybe out of broadcast reach)
    timer = 0,
    interval = 1.0, -- seconds between broadcasts
    ttl = 4.0, -- forget a host after this many seconds of silence
  }, Scanner)
end

function Scanner:update(dt)
  self.timer = self.timer - dt
  if self.timer <= 0 then
    self.timer = self.interval
    self.udp:sendto(Protocol.DISCOVER_MAGIC, "255.255.255.255", Protocol.DISCOVERY_PORT)
    -- Also poke localhost so hosting and joining on one machine works.
    self.udp:sendto(Protocol.DISCOVER_MAGIC, "127.0.0.1", Protocol.DISCOVERY_PORT)
    for _, ip in ipairs(self.probes) do
      self.udp:sendto(Protocol.DISCOVER_MAGIC, ip, Protocol.DISCOVERY_PORT)
    end
  end

  local now = socket.gettime()
  for _ = 1, MAX_PACKETS_PER_UPDATE do
    local data, ip = self.udp:receivefrom()
    if not data then
      break
    end
    local kind, args = Protocol.decode(data)
    if kind == Protocol.HOST_MAGIC and args[1] then
      local existing = self.hosts[args[1]]
      -- Prefer a LAN address over loopback if we hear both.
      if not existing or existing.ip == "127.0.0.1" or ip ~= "127.0.0.1" then
        self.hosts[args[1]] = {
          id = args[1],
          ip = ip,
          name = args[2] or "?",
          port = tonumber(args[3]) or Protocol.PORT,
          players = tonumber(args[4]) or 0,
          maxPlayers = tonumber(args[5]) or 0,
          world = args[6] ~= "" and args[6] or nil, -- the saved world's name (older hosts send none)
          lastSeen = now,
        }
      else
        existing.players = tonumber(args[4]) or existing.players
        existing.lastSeen = now
      end
    end
  end

  for id, h in pairs(self.hosts) do
    if now - h.lastSeen > self.ttl then
      self.hosts[id] = nil
    end
  end
end

--- Also ask `ip` directly every round: a host a broadcast does not reach
--- (another subnet) still answers that.
function Scanner:probe(ip)
  for _, known in ipairs(self.probes) do
    if known == ip then
      return
    end
  end
  self.probes[#self.probes + 1] = ip
end

--- Hosts as an array, sorted by name.
function Scanner:list()
  local out = {}
  for _, h in pairs(self.hosts) do
    out[#out + 1] = h
  end
  table.sort(out, function(a, b)
    return a.name < b.name
  end)
  return out
end

function Scanner:close()
  self.udp:close()
end

return Discovery
