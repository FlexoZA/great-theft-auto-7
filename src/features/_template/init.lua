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

--- Every frame while in the game. client.cars, client.players, client.myId
--- and client:myCar() are available. Send to the server with
--- client:send(Protocol.encode("KIND", ...)).
function MyFeature:update(dt, client) end

--- World-space drawing; the camera transform is already applied.
function MyFeature:drawBelowCars(client, camera) end
function MyFeature:drawAboveCars(client, camera) end

--- Screen-space drawing, after the world.
function MyFeature:drawHUD(client) end

function MyFeature:keypressed(key, client) end
function MyFeature:mousepressed(x, y, button, client) end

--- Messages from the server that the core doesn't know. `args` is the list of
--- fields after the kind. Keys must not collide with core kinds or other
--- features (the registry errors if they do).
MyFeature.clientMessages = {
  -- MYKIND = function(client, args) end,
}

-- Server side (runs only on the host) ---------------------------------------

--- Game started; every player has a car at its spawn slot. Reposition them
--- here if your feature owns spawn points (server.players[id].car).
function MyFeature:serverStart(server) end

--- Fixed 30 Hz step, after car physics and before the STATE broadcast.
--- Send to everyone with server:broadcast(msg) or one player with
--- server:send(player, msg).
function MyFeature:serverStep(server, dt) end

function MyFeature:serverPlayerJoined(server, player) end
function MyFeature:serverPlayerLeft(server, player) end

--- Messages from clients that the core doesn't know.
MyFeature.serverMessages = {
  -- MYKIND = function(server, player, args) end,
}

return MyFeature
