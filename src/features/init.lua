-- Feature registry. Every folder under src/features/ with an init.lua is a
-- feature (folders starting with "_" are skipped). A feature is a table of
-- optional hooks; see src/features/_template/init.lua and docs/features.md.
--
-- Core code calls Features.call("hookName", ...) at well-defined points and
-- never needs to know which features exist.

local Features = {
  list = {}, -- sorted by priority, then name
  byName = {},
  clientMessages = {}, -- kind -> handler(client, args)
  serverMessages = {}, -- kind -> handler(server, player, args)
}

local ROOT = "src/features"

local function discover()
  local names = {}
  for _, item in ipairs(love.filesystem.getDirectoryItems(ROOT)) do
    local isFeature = item:sub(1, 1) ~= "_" and love.filesystem.getInfo(ROOT .. "/" .. item .. "/init.lua", "file")
    if isFeature then
      names[#names + 1] = item
    end
  end
  table.sort(names)
  return names
end

local function registerMessages(feature, field, into)
  for kind, handler in pairs(feature[field] or {}) do
    if into[kind] then
      error(("feature '%s' and '%s' both handle %s message %s"):format(feature.name, into[kind].feature, field, kind))
    end
    into[kind] = { feature = feature.name, handler = handler }
  end
end

--- Load features. `names` is optional; by default every folder is discovered.
--- Fails loudly: a broken feature stops the game with a clear message.
function Features.load(names)
  for _, name in ipairs(names or discover()) do
    local ok, feature = pcall(require, "src.features." .. name)
    if not ok then
      error(("feature '%s' failed to load:\n%s"):format(name, tostring(feature)))
    end
    if type(feature) ~= "table" then
      error(("feature '%s': init.lua must return a table"):format(name))
    end
    feature.name = feature.name or name
    feature.priority = feature.priority or 100
    if Features.byName[feature.name] then
      error(("two features are named '%s'"):format(feature.name))
    end
    Features.list[#Features.list + 1] = feature
    Features.byName[feature.name] = feature
    registerMessages(feature, "clientMessages", Features.clientMessages)
    registerMessages(feature, "serverMessages", Features.serverMessages)
  end

  table.sort(Features.list, function(a, b)
    if a.priority ~= b.priority then
      return a.priority < b.priority
    end
    return a.name < b.name
  end)

  Features.call("load")
  return Features.list
end

--- Call hook `name` on every feature that defines it, in priority order.
function Features.call(name, ...)
  for _, f in ipairs(Features.list) do
    local fn = f[name]
    if fn then
      fn(f, ...)
    end
  end
end

--- Returns true if a feature handled the message.
function Features.handleClientMessage(client, kind, args)
  local entry = Features.clientMessages[kind]
  if entry then
    entry.handler(client, args)
    return true
  end
  return false
end

function Features.handleServerMessage(server, player, kind, args)
  local entry = Features.serverMessages[kind]
  if entry then
    entry.handler(server, player, args)
    return true
  end
  return false
end

function Features.names()
  local out = {}
  for _, f in ipairs(Features.list) do
    out[#out + 1] = f.name
  end
  return table.concat(out, ", ")
end

return Features
