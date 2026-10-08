-- Wire format: tab-separated fields, first field is the message kind.
-- Kept human-readable on purpose for the first milestones (see docs/networking.md).

local Protocol = {
  PORT = 22122, -- ENet game port (UDP)
  DISCOVERY_PORT = 22123, -- LAN discovery port (UDP broadcast)
  DISCOVER_MAGIC = "GTA7_DISCOVER",
  HOST_MAGIC = "GTA7_HOST",
  MAX_NAME = 16,
  MAX_SERVER_NAME = 32, -- a player name and "'s game"
  KEY_LENGTH = 32, -- hex characters in a player key
}

local SEP = "\t"

-- Compression: the server deflates a long message (Protocol.pack) for a
-- client that can read it (one that said its version in HELLO), and marks
-- it with a first byte no message kind starts with. Over Tailscale (1280-
-- byte packets) the big snapshots were split in two otherwise, and a lost
-- half lost the lot. Everything else goes as it is.
local ZIPPED = "\1"
Protocol.ZIP_MIN = 160 -- bytes; shorter messages aren't worth it

--- `msg` deflated and marked, when that is smaller; else `msg` itself.
function Protocol.pack(msg)
  if #msg < Protocol.ZIP_MIN then
    return msg
  end
  local ok, z = pcall(love.data.compress, "string", "deflate", msg)
  if ok and z and #z + 1 < #msg then
    return ZIPPED .. z
  end
  return msg
end

--- A message as it arrived, inflated if it was packed; nil if it can't be.
function Protocol.unpack(data)
  if data:sub(1, 1) ~= ZIPPED then
    return data
  end
  local ok, msg = pcall(love.data.decompress, "string", "deflate", data:sub(2))
  return ok and msg or nil
end

--- Can a game at version `a` play with one at `b` (Version.current)? Only
--- the same release; a build that can't tell its own ("0.0.0", no
--- CHANGELOG.md beside it) doesn't stand in the way.
function Protocol.compatible(a, b)
  return a == b or a == "0.0.0" or b == "0.0.0"
end

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

--- Strip control characters (including our separator) and clamp length to
--- `max` characters (MAX_NAME when not given).
function Protocol.sanitizeName(name, max)
  name = tostring(name or ""):gsub("%c", ""):gsub("^%s+", ""):gsub("%s+$", "")
  if name == "" then
    name = "Player"
  end
  name = name:sub(1, max or Protocol.MAX_NAME)
  -- The cut is in bytes: drop a character it split, or the text is not valid UTF-8 to draw.
  local lead = name:find("[\192-\255][\128-\191]*$")
  if lead then
    local b = name:byte(lead)
    local want = b >= 240 and 4 or b >= 224 and 3 or 2
    if #name - lead + 1 < want then
      name = name:sub(1, lead - 1)
    end
  end
  return name
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
