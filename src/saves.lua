-- Saved worlds on the host's disk (docs/persistence.md). Only files live
-- here; what goes in them is src/net/persistence.lua's business.
--
--   saves/<slug>/meta.lua           name, created, lastPlayed, players (names, for the Continue list)
--   saves/<slug>/world.lua          the world: ids, cars, one slice per feature
--   saves/<slug>/players/<key>.lua  one player: name, one slice per feature
--
-- Every write first copies the file it replaces to <file>.bak, and a read
-- that fails on the file falls back to the .bak, so a crash halfway through
-- a write costs at most the last save.

local Serialize = require("src.serialize")

local Saves = { DIR = "saves" }

local World = {}
World.__index = World

--- The table in `path`, or nil when there is none. Falls back to the .bak
--- when the file is missing or broken; the second value is true then.
local function readTable(path)
  for _, file in ipairs({ path, path .. ".bak" }) do
    if love.filesystem.getInfo(file, "file") then
      local data, err = Serialize.decode(love.filesystem.read(file), file)
      if type(data) == "table" then
        return data, file ~= path
      end
      print("saves: could not read " .. file .. ": " .. tostring(err or "not a table"))
    end
  end
  return nil
end

local function writeTable(path, data)
  local text = Serialize.encode(data) -- before touching anything: a bad value must not cost the .bak
  if love.filesystem.getInfo(path, "file") then
    love.filesystem.write(path .. ".bak", love.filesystem.read(path))
  end
  local ok, err = love.filesystem.write(path, text)
  if not ok then
    print("saves: could not write " .. path .. ": " .. tostring(err))
  end
  return ok
end

--- "My Big City!" -> "my-big-city", made unique among the saves there are.
local function slugFor(name)
  local base = name:lower():gsub("[^%w]+", "-"):gsub("^%-+", ""):gsub("%-+$", ""):sub(1, 32)
  if base == "" then
    base = "world"
  end
  local slug, n = base, 1
  while love.filesystem.getInfo(Saves.DIR .. "/" .. slug) do
    n = n + 1
    slug = base .. "-" .. n
  end
  return slug
end

--- Every saved world, the last played first: { slug, name, lastPlayed, players }.
function Saves.list()
  local out = {}
  for _, slug in ipairs(love.filesystem.getDirectoryItems(Saves.DIR)) do
    local meta = readTable(Saves.DIR .. "/" .. slug .. "/meta.lua")
    if meta then
      out[#out + 1] = {
        slug = slug,
        name = tostring(meta.name or slug),
        lastPlayed = tonumber(meta.lastPlayed) or 0,
        players = type(meta.players) == "table" and meta.players or {},
      }
    end
  end
  table.sort(out, function(a, b)
    return a.lastPlayed > b.lastPlayed
  end)
  return out
end

--- A new, empty world called `name`.
function Saves.create(name)
  local slug = slugFor(name)
  local dir = Saves.DIR .. "/" .. slug
  love.filesystem.createDirectory(dir .. "/players")
  local world = setmetatable({ slug = slug, dir = dir, meta = { name = name, created = os.time() } }, World)
  world.meta.lastPlayed = world.meta.created
  world:writeMeta()
  return world
end

--- The world saved as `slug`, or nil and a reason.
function Saves.open(slug)
  local dir = Saves.DIR .. "/" .. slug
  local meta, fromBackup = readTable(dir .. "/meta.lua")
  if not meta then
    return nil, "no saved world " .. slug
  end
  love.filesystem.createDirectory(dir .. "/players")
  local world = setmetatable({ slug = slug, dir = dir, meta = meta }, World)
  world.restored = fromBackup or nil -- true once any file came from its .bak
  return world
end

function World:name()
  return tostring(self.meta.name or self.slug)
end

function World:writeMeta()
  return writeTable(self.dir .. "/meta.lua", self.meta)
end

--- The world table, or nil for a world never saved yet.
function World:readWorld()
  local data, fromBackup = readTable(self.dir .. "/world.lua")
  self.restored = self.restored or fromBackup or nil
  return data
end

function World:writeWorld(data)
  return writeTable(self.dir .. "/world.lua", data)
end

--- `key` is a player key (Protocol.sanitizeKey), so it is safe as a file name.
function World:readPlayer(key)
  local data, fromBackup = readTable(self.dir .. "/players/" .. key .. ".lua")
  self.restored = self.restored or fromBackup or nil
  return data
end

function World:writePlayer(key, data)
  return writeTable(self.dir .. "/players/" .. key .. ".lua", data)
end

return Saves
