-- luacheck: no unused args
-- Copy this folder to src/features/<your-feature>/ and delete the hooks you
-- don't need. Folders starting with "_" are ignored, so this one never loads.
-- Full reference: docs/features.md
-- Messages are built with Protocol.encode from require("src.net.protocol").

local MyFeature = {
  name = "my-feature", -- defaults to the folder name
  priority = 100, -- lower runs/draws first
}

-- Lifecycle ----------------------------------------------------------------

--- Once at startup, after all features are loaded. Load assets here.
function MyFeature:load() end

--- Entering/leaving the driving scene on this machine.
function MyFeature:enterGame(client) end
function MyFeature:exitGame(client) end

-- Client side (runs on every machine, including the host) -------------------

--- Every frame while in the game. client.vehicles, client.bodies,
--- client.players, client.myId, client:pose(id), client:myPose() and
--- client:myVehicle() are available. Send to the server with
--- client:send(Protocol.encode("KIND", ...)). `camera` is { x, y, scale },
--- already on the local player; move or scale it to steer the view.
function MyFeature:update(dt, client, camera) end

--- World-space drawing; the camera transform is already applied.
function MyFeature:drawBelowCars(client, camera) end
function MyFeature:drawAboveCars(client, camera) end

--- Screen-space drawing, after the world.
function MyFeature:drawHUD(client) end

function MyFeature:keypressed(key, client) end
function MyFeature:mousepressed(x, y, button, client) end

--- Asked before the core draws each vehicle `c` (world space, camera
--- applied; `c.dx c.dy c.dangle` is where it is drawn). Draw it your own way
--- and return true to leave out the core's box; vehicles draws its models so.
function MyFeature:drawVehicle(client, c) end


--- Asked every frame: 0..1 for how soft the world should be drawn (the HUD
--- stays sharp). The core takes the highest answer from any feature and
--- eases towards it; weapons answers 1 while you are wrecked.
function MyFeature:worldBlur(client) end

--- Messages from the server that the core doesn't know. `args` is the list of
--- fields after the kind. Keys must not collide with core kinds or other
--- features (the registry errors if they do).
MyFeature.clientMessages = {
  -- MYKIND = function(client, args) end,
}

-- Server side (runs only on the host) ---------------------------------------

--- Game started; every player has a body and their own car at its spawn
--- slot, and sits in it. Reposition them here if your feature owns spawn
--- points (server.players[id].body, .car; server:seat / server:unseat).
function MyFeature:serverStart(server) end

--- Fixed 30 Hz step, after car physics and before the STATE broadcast.
--- Send to everyone with server:broadcast(msg) or one player with
--- server:send(player, msg).
function MyFeature:serverStep(server, dt) end

function MyFeature:serverPlayerJoined(server, player) end
function MyFeature:serverPlayerLeft(server, player) end

--- Saved worlds (docs/persistence.md). Return a plain table (strings,
--- numbers, booleans, tables) of facts worth keeping, or nil for nothing;
--- put a `version` in it. Load gets it back after serverStart (world) or
--- once the player is set up (player) and must tell clients what changed.
function MyFeature:serverSaveWorld(server) end
function MyFeature:serverLoadWorld(server, data) end
function MyFeature:serverSavePlayer(server, player) end
function MyFeature:serverLoadPlayer(server, player, data) end

--- Messages from clients that the core doesn't know.
MyFeature.serverMessages = {
  -- MYKIND = function(server, player, args) end,
}

return MyFeature
