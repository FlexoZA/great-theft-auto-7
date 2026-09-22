-- Persistent settings: a nested table saved as Lua source in the save
-- directory. Read with dotted paths, e.g. Settings.get("sound.music", 0.5).
-- Loaded once on first require; every set() writes the file.

local FILE = "settings.lua"

local Settings = { data = {}, loaded = false }

local function serialize(v, indent)
  indent = indent or ""
  local t = type(v)
  if t == "table" then
    local keys = {}
    for k in pairs(v) do
      keys[#keys + 1] = k
    end
    table.sort(keys, function(a, b)
      return tostring(a) < tostring(b)
    end)
    local parts = {}
    for _, k in ipairs(keys) do
      parts[#parts + 1] = indent .. "  [" .. serialize(k) .. "] = " .. serialize(v[k], indent .. "  ")
    end
    return "{\n" .. table.concat(parts, ",\n") .. "\n" .. indent .. "}"
  elseif t == "string" then
    return ("%q"):format(v)
  end
  return tostring(v)
end

function Settings.load()
  Settings.loaded = true
  Settings.data = {}
  if love.filesystem.getInfo(FILE, "file") then
    local chunk = love.filesystem.load(FILE)
    local ok, data = pcall(chunk)
    if ok and type(data) == "table" then
      Settings.data = data
    else
      print("settings: could not read " .. FILE .. ", using defaults")
    end
  end
end

function Settings.save()
  love.filesystem.write(FILE, "return " .. serialize(Settings.data) .. "\n")
end

local function walk(path, create)
  local node = Settings.data
  local parts = {}
  for part in path:gmatch("[^%.]+") do
    parts[#parts + 1] = part
  end
  for i = 1, #parts - 1 do
    local next = node[parts[i]]
    if type(next) ~= "table" then
      if not create then
        return nil
      end
      next = {}
      node[parts[i]] = next
    end
    node = next
  end
  return node, parts[#parts]
end

function Settings.get(path, default)
  if not Settings.loaded then
    Settings.load()
  end
  local node, key = walk(path, false)
  local v = node and node[key]
  if v == nil then
    return default
  end
  return v
end

function Settings.set(path, value)
  if not Settings.loaded then
    Settings.load()
  end
  local node, key = walk(path, true)
  node[key] = value
  Settings.save()
end

--- Path to the file, for the settings screen to show.
function Settings.file()
  return love.filesystem.getSaveDirectory() .. "/" .. FILE
end

return Settings
