-- Network session: at most one server (when hosting) and one client.
-- The host is also a client of its own server, so game code only ever
-- talks to Net.client.

local Protocol = require("src.net.protocol")
local Server = require("src.net.server")
local Client = require("src.net.client")

local Net = {
  server = nil,
  client = nil,
}

function Net.host(playerName)
  Net.shutdown()
  local server, err = Server.new(playerName .. "'s game")
  if not server then
    return false, err
  end
  Net.server = server
  Net.client = Client.new(playerName)
  Net.client:connect("127.0.0.1", Protocol.PORT)
  return true
end

function Net.join(playerName, ip, port)
  Net.shutdown()
  Net.client = Client.new(playerName)
  return Net.client:connect(ip, port)
end

function Net.isHost()
  return Net.server ~= nil
end

function Net.isActive()
  return Net.client ~= nil
end

function Net.update(dt)
  if Net.server then
    Net.server:update()
  end
  if Net.client then
    Net.client:update(dt)
  end
end

function Net.shutdown()
  if Net.client then
    Net.client:disconnect()
    Net.client = nil
  end
  if Net.server then
    Net.server:close()
    Net.server = nil
  end
end

return Net
