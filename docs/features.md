# Features

Gameplay is built as **features**: self-contained folders that plug into the
core through hooks. The core (`main.lua`, `src/net/`, `src/states/`) stays
stable; features are where maps, vehicles, weapons, missions and so on live.
Two developers working on two features never touch the same files.

## Creating one

```bash
cp -r src/features/_template src/features/city-map
```

Edit `src/features/city-map/init.lua`, delete the hooks you don't need, run
`love .`. The console prints `features: city-map, grid` on startup. That's it:
no registration, no changes to `main.lua`.

Rules:

- Folder name = feature name, lowercase with hyphens. Folders starting with `_`
  are ignored.
- `init.lua` must return a table. Other Lua files in the folder are required
  as `require("src.features.city-map.tiles")`.
- Assets belong in the folder too (`src/features/city-map/assets/…`) unless
  they are shared by several features, then `assets/`.
- A feature that errors while loading stops the game with its name in the
  message. That's deliberate.

## Hooks

All optional. `self` is the feature table. Priority (default 100) orders
calls; lower runs and draws first.

### Lifecycle

| Hook | When |
| --- | --- |
| `load()` | Once at startup, after every feature is loaded. Load images, fonts, sounds here. |
| `enterGame(client)` / `exitGame(client)` | Entering / leaving the driving scene on this machine. |

### Client side

Runs on every machine, including the host (the host runs its own client).

| Hook | When |
| --- | --- |
| `update(dt, client, camera)` | Every frame in the game, after car snapshots are smoothed. `camera` is `{ x, y, scale }`, already following the local player; move it or change its scale to steer the view (`vision` does). |
| `drawBelowCars(client, camera)` | World space, camera applied, before cars. Maps go here. |
| `drawAboveCars(client, camera)` | World space, after cars. Bullets, effects. |
| `drawHUD(client)` | Screen space, after the world. |
| `keypressed(key, client)` | Key press in the game (Esc is taken). |
| `mousepressed(x, y, button, client)` | Mouse press in the game. |
| `clientMessages = { KIND = function(client, args) end }` | A message from the server the core doesn't know. |

The same `camera` table reaches the draw hooks, so a feature that needs the
visible world bounds divides the window size by `camera.scale`.

Useful client fields: `client.cars[id]` (`x y angle speed` from the server,
`dx dy dangle` smoothed for drawing), `client.players[id].name`,
`client.myId`, `client:myCar()`, `client:send(msg, unreliable)`.

### Server side

Runs only on the host. **Everything that changes the world happens here.**
Clients send intent; the server decides. Never trust a client message.

| Hook | When |
| --- | --- |
| `serverStart(server)` | Game started, every player has a car at the default spawn slot. A map feature can move `server.players[id].car` to its own spawn points here. |
| `serverStep(server, dt)` | Fixed 30 Hz, after car physics, before the `STATE` broadcast. Collisions, projectiles, scoring. |
| `serverPlayerJoined(server, player)` / `serverPlayerLeft(server, player)` | Roster changes. |
| `serverMessages = { KIND = function(server, player, args) end }` | A message from a client the core doesn't know. `player` is the verified sender. |

Useful server fields: `server.players[id]` (`id name peer input car`),
`server.tick`, `server:broadcast(msg, exceptPlayer)`, `server:send(player, msg, unreliable)`.

## Messages

Build them with `Protocol.encode("KIND", a, b, c)` from
`require("src.net.protocol")`. Fields are tab-separated strings; convert with
`tonumber` on receipt. Pick a kind name unique to your feature (`GUN_FIRE`,
not `FIRE`). The registry refuses to load two features that claim the same
kind, and the core owns `HELLO WELCOME JOIN LEAVE START REJECT INPUT STATE`.

Reliable (default) for events that must arrive: pickups, hits, chat.
Unreliable (`true`) for things sent every tick where only the latest matters.

## Example

`src/features/grid/init.lua` draws the background grid in twelve lines using
`drawBelowCars`; `src/features/vision/init.lua` is client-only too, panning and
zooming the camera in `update` and drawing its own cursor in `drawHUD`. For a
feature that talks to the server, the shape is:

```lua
local Protocol = require("src.net.protocol")
local Horn = { name = "horn" }

function Horn:keypressed(key, client)
  if key == "h" then
    client:send(Protocol.encode("HORN"))
  end
end

Horn.serverMessages = {
  HORN = function(server, player)
    server:broadcast(Protocol.encode("HORN_HONKED", player.id))
  end,
}

Horn.clientMessages = {
  HORN_HONKED = function(client, args)
    local id = tonumber(args[1])
    -- play a sound at client.cars[id]
  end,
}

return Horn
```

## Sound volumes

Register one channel per kind of sound in your `load` hook and scale every
play by it; the settings screen then shows a slider for it automatically:

```lua
local Audio = require("src.audio")
Audio.registerChannel("sirens", "Police sirens", 0.8, function()
  Sounds.play("siren", 0, 0) -- preview when the slider moves
end)
...
source:setVolume(Audio.volume("sirens")) -- includes the master level
```

## Key bindings

Never test raw keys in a feature. Register an action in `load` and ask the
controls module; the Controls section of Settings then lists it and players
can rebind it:

```lua
local Controls = require("src.controls")
Controls.register("horn", "Sound the horn", "h") -- key, label, default (+ optional secondary)
...
function Horn:keypressed(key, client)
  if Controls.is("horn", key) then ... end          -- key presses
end
Controls.isDown("horn")                            -- held, in update
Controls.isMouse("horn", button)                   -- in mousepressed
Controls.name(Controls.bindings("horn")[1])        -- "H", for HUD hints
```

## Conventions between features

Features stay decoupled by talking through the server's player tables and a
couple of small conventions rather than requiring each other:

- `server.spawnPoints`: a map feature sets this in `serverStart` to a list of
  `{ x, y, angle }` on drivable ground. Anything that spawns a car (bots)
  uses it when present and falls back to its own placement otherwise.
- `feature:blocksPoint(x, y)`: return true when a point is inside something
  solid. Weapons checks every feature that defines it, so bullets stop at
  walls without knowing which feature owns them.
- `feature:serverKill(server, kill)`: the host tells every feature that
  something died. The feature that owns the kill calls
  `Features.call("serverKill", server, kill)` right after it broadcasts its
  own message (pedestrians and weapons do); `kill` is
  `{ kind = "pedestrian" | "car", x, y, by = <killer player id>, victim = <player id> }`
  with `x, y` where it died, not where a wreck respawns. Money drops koins
  there: a pedestrian is worth a fresh koin, while a wrecked car spills up to
  five out of `victim`'s own wallet and nothing at all if it was empty, so
  fill in `victim` for anything a player was driving. Ignore kinds you don't
  care about; new kinds may appear.
- `car.hidden`: set on a server car to keep it out of `STATE` (weapons does
  this for wrecks). The core respects it; other features should skip hidden
  cars too.
- `Features.byName.<name>` is the escape hatch when a feature genuinely
  needs another (the city map pushes pedestrians out of buildings through
  `Features.byName.pedestrians.crowd`). Check for nil: the other feature
  may have been deleted.

## When the hooks aren't enough

Add a hook to the core rather than reaching into it from a feature. Keep the
core change to a few lines, document the new hook here and in `_template`,
and mention it in the pull request so others can use it.
