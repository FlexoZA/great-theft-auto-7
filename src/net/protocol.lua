-- Wire format: tab-separated fields, first field is the message kind.
-- Kept human-readable on purpose for the first milestones (see docs/networking.md).

local Protocol = {
  PORT = 22122, -- ENet game port (UDP)
  DISCOVERY_PORT = 22123, -- LAN discovery port (UDP broadcast)
  DISCOVER_MAGIC = "GTA7_DISCOVER",
  HOST_MAGIC = "GTA7_HOST",
  MAX_NAME = 16,
  KEY_LENGTH = 32, -- hex characters in a player key
}

local SEP = "\t"

function Protocol.encode(kind, ...)
  local parts = { kind }
  for i = 1, select("#", ...) do
    parts[#parts + 1] = tostring(select(i, ...))
  end
  return table.concat(parts, SEP)
end

--- Returns kind, args where args[1] is the first field after the kind.
function Protocol.decode(msg)
  local parts = {}
  for field in (msg .. SEP):gmatch("(.-)" .. SEP) do
    parts[#parts + 1] = field
  end
  local kind = table.remove(parts, 1)
  return kind, parts
end

--- Strip control characters (including our separator) and clamp length.
function Protocol.sanitizeName(name)
  name = tostring(name or ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    name = "Player"
  end
  return name:sub(1, Protocol.MAX_NAME)
end

--- A fresh random player key: KEY_LENGTH lowercase hex characters.
function Protocol.newKey()
  local digits = {}
  for i = 1, Protocol.KEY_LENGTH do
    digits[i] = ("%x"):format(love.math.random(0, 15))
  end
  return table.concat(digits)
end

--- The key if it is exactly KEY_LENGTH lowercase hex characters, else nil.
function Protocol.sanitizeKey(key)
  key = tostring(key or "")
  if #key == Protocol.KEY_LENGTH and not key:find("[^0-9a-f]") then
    return key
  end
  return nil
end

return Protocol
