-- Saved worlds on the server side (docs/persistence.md): who is who across
-- sessions, which cars stay, when to write, and handing each feature its
-- slice. Files are src/saves.lua's; this decides what goes in them.
--
-- Identity: a player's key (Protocol) maps to the same `player.id` for the
-- life of a world, so feature state kept by id means the same person next
-- time. The host's own key is always id 1. Saved cars come back with their
-- old vehicle ids, so per-car feature state holds as well.
--
-- A server works without a world too (tests, harnesses): ids are then kept
-- for the session only and nothing is written.

local Features = require("src.features")
local ServerSettings = require("src.server_settings")

local Persistence = {}

Persistence.FORMAT = 1 -- bump when the layout of world.lua or a player file changes
Persistence.HOST_ID = 1

--- Set up identity and read the world (nil: a session that is not saved).
--- `hostKey` is the hosting player's key; they get id 1.
function Persistence.attach(server, world, hostKey)
  local data = world and world:readWorld() or {}
  server.world = world
  server.saved = data -- what the world held when it was opened
  server.ids = type(data.ids) == "table" and data.ids or {} -- key -> id
  server.names = type(data.names) == "table" and data.names or {} -- id -> last name, everyone in `ids`
  server.nextId = math.max(tonumber(data.nextId) or 1, hostKey and Persistence.HOST_ID + 1 or 1)
  server.nextVehicleId = tonumber(data.nextVehicleId) or 1
  server.saveTimer = 0
  if hostKey then
    -- A world moved to another machine: its new host takes over id 1.
    for key, id in pairs(server.ids) do
      if id == Persistence.HOST_ID and key ~= hostKey then
        server.ids[key] = nil
      end
    end
    server.ids[hostKey] = Persistence.HOST_ID
  end
  for id, name in pairs(server.names) do
    server.departed[id] = name -- nobody is here yet; their cars may be
  end
end

--- The id for a player who has just said HELLO: theirs from before when the
--- key is known, else the next free one (remembered unless they are a guest).
function Persistence.assignId(server, player)
  local id = not player.guest and server.ids[player.key]
  if not id or server.players[id] then
    id = server.nextId
    server.nextId = id + 1
    if not player.guest then
      server.ids[player.key] = id
    end
  end
  if not player.guest then
    server.names[id] = player.name
  end
  server.departed[id] = nil
  return id
end

--- Is `id` someone the world remembers (a keyed player, not a bot or guest)?
local function remembered(server, id)
  return id ~= nil and server.names[id] ~= nil
end

-- Loading -------------------------------------------------------------------

--- Before anyone is spawned: every saved car back in the world, under its
--- old id. A player's own car is picked up again by server:spawnPlayers.
function Persistence.restoreCars(server)
  local cars = type(server.saved.cars) == "table" and server.saved.cars or {}
  for _, rec in ipairs(cars) do
    local id = tonumber(rec.id)
    if id and not server.vehicles[id] and remembered(server, rec.owner) then
      local car = server:restoreVehicle(id, rec.x or 0, rec.y or 0, rec.angle or 0, rec.owner, rec.color)
      car.personal = rec.personal or nil
      server.nextVehicleId = math.max(server.nextVehicleId, id + 1)
    end
  end
end

--- After serverStart (a map feature has lined everyone up on its spawn
--- points by then): saved cars go back where they were parked, taking their
--- drivers with them, then each feature gets its slice of the world and
--- everyone here gets theirs.
function Persistence.afterStart(server)
  local cars = type(server.saved.cars) == "table" and server.saved.cars or {}
  for _, rec in ipairs(cars) do
    local car = server.vehicles[tonumber(rec.id)]
    if car and car.owner == rec.owner then
      car.x, car.y, car.angle = rec.x or car.x, rec.y or car.y, rec.angle or car.angle
      car:stop()
    end
  end
  server:seatBodies()
  Features.deliver("serverLoadWorld", server.saved.features, server)
  for _, player in pairs(server.players) do
    Persistence.loadPlayer(server, player)
  end
end

--- A remembered player is in the game, set up like anyone new (after
--- serverStart, or after serverPlayerJoined for a latecomer): features put
--- back what they saved for them and tell everyone, as for any change.
function Persistence.loadPlayer(server, player)
  if not server.world or player.guest or player.bot then
    return
  end
  local data = server.world:readPlayer(player.key)
  if data then
    Features.deliver("serverLoadPlayer", data.features, server, player)
  end
end

-- Saving --------------------------------------------------------------------

--- Write one player's file. Called when they leave (before features forget
--- them), and for everyone on every save.
function Persistence.savePlayer(server, player)
  if not (server.world and server.started) or player.guest or player.bot then
    return
  end
  server.world:writePlayer(player.key, {
    format = Persistence.FORMAT,
    name = player.name,
    saved = os.time(),
    features = Features.gather("serverSavePlayer", server, player),
  })
end

--- The world as it stands: identity, every car a remembered player owns,
--- and each feature's slice.
function Persistence.snapshot(server)
  local cars = {}
  for id, car in pairs(server.vehicles) do
    if remembered(server, car.owner) then
      cars[#cars + 1] = {
        id = id,
        x = car.x,
        y = car.y,
        angle = car.angle,
        owner = car.owner,
        color = car.color,
        personal = car.personal or nil,
      }
    end
  end
  table.sort(cars, function(a, b)
    return a.id < b.id
  end)
  return {
    format = Persistence.FORMAT,
    ids = server.ids,
    names = server.names,
    nextId = server.nextId,
    nextVehicleId = server.nextVehicleId,
    cars = cars,
    features = Features.gather("serverSaveWorld", server),
  }
end

--- Save everything: every player here, and the world unless a feature holds
--- it (away on a quest map, where the world is not the city: the last save
--- from home stands).
function Persistence.saveAll(server)
  if not (server.world and server.started) then
    return
  end
  for _, player in pairs(server.players) do
    Persistence.savePlayer(server, player)
  end
  if not Features.any("serverWorldSaveHeld", server) then
    server.world:writeWorld(Persistence.snapshot(server))
  end
  local names = {}
  for _, name in pairs(server.names) do
    names[#names + 1] = name
  end
  table.sort(names)
  server.world.meta.lastPlayed = os.time()
  server.world.meta.players = names
  server.world.meta.format = Persistence.FORMAT
  server.world:writeMeta()
  server.saveTimer = 0
end

--- Autosave every few minutes (the host's server setting) while playing.
function Persistence.update(server, dt)
  if not (server.world and server.started) then
    return
  end
  server.saveTimer = server.saveTimer + dt
  if server.saveTimer >= ServerSettings.get("autosaveMinutes") * 60 then
    Persistence.saveAll(server)
  end
end

return Persistence
