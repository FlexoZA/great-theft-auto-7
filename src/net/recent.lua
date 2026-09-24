-- Servers this machine has joined before, newest first, kept in settings
-- (`recent.servers`) so the Join screen can offer them again. A server is
-- known by its lasting id (the saved world's, see src/saves.lua), so it is
-- found again on the network even when the host's address has changed; the
-- last address is kept for hosts a broadcast does not reach.

local Settings = require("src.settings")

local Recent = {}

Recent.MAX = 6

local function valid(e)
  return type(e) == "table" and type(e.id) == "string" and type(e.ip) == "string" and tonumber(e.port) ~= nil
end

--- Every remembered server: { id, name, world, ip, port, at }, newest first.
function Recent.list()
  local out = {}
  local saved = Settings.get("recent.servers", {})
  for _, e in ipairs(type(saved) == "table" and saved or {}) do
    if valid(e) then
      out[#out + 1] = e
    end
  end
  return out
end

--- Remember joining server `id` (its name, world name, address) just now.
--- It goes to the top; the oldest drops off past MAX.
function Recent.remember(id, name, world, ip, port)
  local list = { { id = id, name = name, world = world, ip = ip, port = port, at = os.time() } }
  for _, e in ipairs(Recent.list()) do
    if e.id ~= id and #list < Recent.MAX then
      list[#list + 1] = e
    end
  end
  Settings.set("recent.servers", list)
end

function Recent.forget(id)
  local list = {}
  for _, e in ipairs(Recent.list()) do
    if e.id ~= id then
      list[#list + 1] = e
    end
  end
  Settings.set("recent.servers", list)
end

return Recent
