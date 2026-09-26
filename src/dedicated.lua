-- Dedicated server: the world with nobody at the keyboard (docs/dedicated-server.md).
-- main.lua comes here when LÖVE was started without a window (GTA7_SERVER=1,
-- see conf.lua). The server is the same Server every host runs; there is
-- just no client of its own, and the game starts as soon as it is up, so
-- everyone joins a running game.
--
-- Environment:
--   GTA7_NAME   the server's name in the Join screen (default "Dedicated server")
--   GTA7_WORLD  the saved world to run, by name; made on first run. Unset:
--               nothing is saved, like hosting a new world without a save.
--
-- Features build their sounds and the vehicles feature its car art when
-- they load, so the modules that need a screen or a sound card are stood in
-- for by no-op stubs: any function returns a stub object whose every method
-- is a no-op. Nothing on the server path draws or plays anything.

-- luacheck: globals love (the stubs below are written into love itself)

io.stdout:setvbuf("no") -- logs show up at once in `docker logs`

local stubObject = setmetatable({}, {
  __index = function(_, k)
    if k == "getFFIPointer" then
      return nil -- the synth writes samples one by one when there is no pointer
    end
    return function()
      return 0, {}
    end
  end,
})

local function stubModule(real)
  return setmetatable(real or {}, {
    __index = function()
      return function()
        return stubObject
      end
    end,
  })
end

love.graphics = stubModule({
  getWidth = function()
    return 1280
  end,
  getHeight = function()
    return 720
  end,
  getDimensions = function()
    return 1280, 720
  end,
})
love.audio = stubModule()
love.sound = stubModule()
love.image = stubModule()
love.font = stubModule()
love.window = stubModule()
love.keyboard = stubModule({
  isDown = function()
    return false
  end,
})
love.mouse = stubModule({
  getPosition = function()
    return 0, 0
  end,
  isDown = function()
    return false
  end,
})

local Features = require("src.features")
local Server = require("src.net.server")
local Protocol = require("src.net.protocol")
local Saves = require("src.saves")

local server

--- The saved world called `name`, made if there is none.
local function openWorld(name)
  for _, entry in ipairs(Saves.list()) do
    if entry.name == name then
      local world, err = Saves.open(entry.slug)
      if not world then
        error(err)
      end
      return world, "continuing"
    end
  end
  return Saves.create(name), "new"
end

function love.load()
  Features.load()
  print("features: " .. Features.names())

  local name = os.getenv("GTA7_NAME") or "Dedicated server"
  local worldName = os.getenv("GTA7_WORLD")
  local world
  if worldName and worldName ~= "" then
    local how
    world, how = openWorld(worldName)
    print(("world: %s (%s) in %s/%s"):format(world:name(), how, love.filesystem.getSaveDirectory(), world.dir))
  else
    print("world: none (GTA7_WORLD is not set, nothing is saved)")
  end

  local err
  server, err = Server.new(name, world, nil)
  if not server then
    error(err)
  end
  if server.discoveryError then
    print("LAN discovery off (" .. server.discoveryError .. "); players join by address")
  end
  server:start()
  print(("%s: hosting on UDP port %d, up to %d players, world started"):format(name, Protocol.PORT, Server.MAX_PLAYERS))
end

local online = 0

function love.update(dt)
  server:update(dt)
  local n = server:playerCount()
  if n ~= online then
    online = n
    print(("players online: %d"):format(n))
  end
end

--- SIGTERM (docker stop, Ctrl-C) lands here through SDL: save and disconnect everyone.
function love.quit()
  print("shutting down: saving the world and disconnecting everyone")
  server:close()
end
