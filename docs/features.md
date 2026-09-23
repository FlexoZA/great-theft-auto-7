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

Timing note: messages the server sends right after `START` (rosters,
one-off announcements like `POL_UNIT` or `PK_SPAWN`) reach the client in the
same burst as `START`, *before* `enterGame` runs. Don't clear such state in
`enterGame`; clear it in `exitGame` instead.


Runs on every machine, including the host (the host runs its own client).

| Hook | When |
| --- | --- |
| `update(dt, client, camera)` | Every frame in the game, after car snapshots are smoothed. `camera` is `{ x, y, scale }`, already following the local player; move it or change its scale to steer the view (`vision` does). |
| `drawBelowCars(client, camera)` | World space, camera applied, before cars. Maps go here. |
| `drawAboveCars(client, camera)` | World space, after cars. Bullets, effects. |
| `drawHUD(client)` | Screen space, after the world. |
| `keypressed(key, client)` | Key press in the game (Esc is taken: it opens the pause menu, and while that is up no key or click reaches a feature and every Controls query reads as released). |
| `hidesCarLabel(client, id)` | Asked while drawing player `id`'s car: return true to keep the core from printing their name over it, because your feature draws them elsewhere (on-foot does, while they are out walking). |
| `mousepressed(x, y, button, client)` | Mouse press in the game. |
| `worldBlur(client)` | Asked every frame: return 0..1 for how soft the world should be drawn (the HUD stays sharp). The core takes the highest answer and eases towards it; weapons answers 1 while you are wrecked. |
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

## Events between features

A feature can raise an event for every other feature with
`Features.call("hookName", ...)`; any feature defining that hook receives
it. `Features.any("hookName", ...)` is the yes/no version: it stops at the
first feature whose hook returns true (the core asks `hidesCarLabel` that
way). Events in use:

| Event | Raised by | Meaning |
| --- | --- | --- |
| `serverPlayerDamaged(server, victim, attacker, amount)` | weapons | A projectile hit. `attacker` may be nil if they left. |
| `serverCarsCollided(server, rammer, rammed, closingSpeed)` | car-collisions | Two cars touched while closing. `rammer` was moving into the other faster. |
| `serverShotFired(server, player, x, y)` | weapons | A projectile left a gun at (x, y). `player` is nil for a shot nobody owns (a police officer on foot). |
| `serverKill(server, { kind, x, y, by, victim })` | weapons, pedestrians, police | Something died: kind is "car", "pedestrian" or "police", `by` the killer's id. |
| `mapChanged(map, server)` | city-map | The game moved to another map mid-game (`city:switchTo`). Raised once per machine; `server` is set on the host and nil on a client. Every car already stands on the new map's spawn points. Drop or move anything you keep in world coordinates: weapons moves its respawn slots, on-foot puts walkers back in their cars, real-estate forgets the old plots. |

Bots listen to damage and collisions to decide who to fight; police listen
to all of them to decide who is wanted. A trigger-area feature would raise
its own event the same way.

NPC drivers: `Features.byName.bots:spawnNpc(server, { name, x, y, angle, brain })`
creates a server-side driver; `brain.think(server, npc, dt)` runs every tick
and can use `Bots.driveTowards`, `Bots:cruise`, `Bots:fight` and
`Bots.unstick`. Police is the worked example.

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
  `{ kind = "pedestrian" | "police" | "car", x, y, by = <killer player id>, victim = <player id> }`
  with `x, y` where it died, not where a wreck respawns. Money drops koins
  there: a pedestrian is worth a fresh koin and an officer on foot three,
  while a wrecked car spills up to five out of `victim`'s own wallet and
  nothing at all if it was empty, so fill in `victim` for anything a player
  was driving. Ignore kinds you don't care about; new kinds may appear.
- `feature:serverShotAt(server, x, y, radius, by, angle)`: a bullet is
  passing through this point on the host. Kill whatever of your own is
  standing within `radius` of it and return true, and the shot stops there;
  return false and it flies on. Weapons walks its projectiles through every
  feature that defines it, so a gun kills pedestrians without knowing they
  exist (police answers it too: officers on foot take a few rounds before
  they go down). `by` is the shooter's player id and `angle` the direction of
  travel, for gibs and scoring; `by` is 0 for a shot no player fired. Cars
  are tested first, so answering here never steals a hit from a player.
- `feature:playerPose(server, player)` / `feature:clientPlayerPose(client, id)`:
  return `x, y, angle` when a player is not behind the wheel, and nil when
  they are. On-foot answers both while its owner is out of the car. Weapons
  asks before it fires (the shot leaves the body), before it tests a hit (the
  body is the target, and the car they parked is not) and before it draws a
  health bar. A feature that moves a player out of their car answers these;
  one that shoots or draws players asks. `Features.bodyPose(server, player)`
  and `Features.clientBodyPose(client, id, carSnapshot)` do the asking for
  you and fall back to the car: money, pickups, bots, police and weapons use
  them, so anything that happens "to a player" happens to the body.
- `Features.byName.weapons:serverDamage(server, victim, attacker, amount, angle)`:
  hurt a player from any cause (cars run walkers over with it). Kills raise
  `serverKill` with `angle` and `onFoot`.
- `Features.byName.weapons:serverSetMaxHealth(server, player, max)` and
  `Features.byName["on-foot"]:serverSetMaxStamina(server, player, max)`: raise
  a player's ceiling for the rest of the game (respawns keep it). Raising it
  tops them up by the difference. Each owner broadcasts its own `WPN_MAX` /
  `OF_MAX` so every HUD scales. `on-foot:serverSetStaminaRegen(server,
  player, scale)` sets how fast stamina comes back, as a multiple of the
  base rate (host only; nothing to draw). Upgrades buys all three with koins.
- `Features.byName.weapons:serverHeal(server, player, amount)` and
  `Features.byName["on-foot"]:serverRestoreStamina(server, player, amount)`:
  top a player up towards their ceiling. Both return true only if anything
  was gained, so a pickup that did nothing (full health, a drink taken from
  behind the wheel) can stay on the road. Pickups uses both.
- `Features.byName.money:wallet(id)` / `money:spend(server, id, amount, label)`:
  read a wallet on the host, or take koins out of it all-or-nothing (false
  and a reason, and nothing happens, when they can't cover it). Every sale
  goes through `spend`; see "Selling things for Fcks" below.
- `Features.byName.money:serverSetReach(server, player, scale)`: how far a
  player's koins jump to them, as a multiple of the base radius; money
  broadcasts `FCK_REACH` and draws the ring. Upgrades sells it.
- `Features.byName.weapons:serverFireFrom(server, ownerId, x, y, aim)`: put a
  bullet into the world from something that is not a player behind the wheel.
  Pass `0` as the owner for a shot that belongs to nobody -- it can hit
  anyone, and its kills credit no scoreboard; the police officers on foot
  shoot this way. No cooldown is applied, so the caller paces its own fire.
- `Features.byName.money:give(server, id, amount)`: put koins into a
  player's wallet, the other way round from `spend` (the cheats use it).

## Selling things for Fcks

Koins (Fcks) are the one currency: plots, city blocks and upgrades are
bought with them today, buildings, guns and abilities next. A feature that
sells something never touches a wallet itself; it does this:

1. **Price it in your own tuning** (`Guns.price = 30`), and show it with
   `Money.amount(n)` ("30 Fcks") wherever you draw a price tag.
2. **On the client, refuse the obvious at once.** Before sending your buy
   message, `if not money:canAfford(client, price)` show your own "can't
   afford it" notice and stop; no round trip for an empty wallet. `money`
   is `Features.byName.money`, and may be nil: then everything is free.
3. **On the host, check your own conditions first, then pay, then grant.**
   Standing in the right place, still for sale, not maxed out -- refuse
   those with your own message. Only when the sale can go ahead call
   `money:spend(server, player.id, price, "plot")`. It takes the koins all
   or nothing and returns `true`, or `false, "broke"` (`"nogame"` before a
   game starts): refuse with that reason and grant nothing. On `true`, grant
   the thing and broadcast your own message about it (`RE_OWNER`, `UPG_LEVEL`).
4. **That's it for feedback.** `spend` broadcasts `FCK_SPENT` with the
   label, so every client's wallet total updates and "-30 Fcks  pistol"
   floats over the buyer, whoever is watching. Your feature draws the thing
   bought, not the payment.

Never send a price from the client, never deduct on the client, and never
call `spend` before your own checks pass -- it has already taken the koins
by the time it returns. Upgrades (`src/features/upgrades`) is the worked
example with a menu; real-estate is the one with a place to stand.
- Plots: city-map leaves the corner blocks empty as `kind = "plot"` in
  `map.blocks`; real-estate sells them and answers `real-estate:owner(plotId)`
  on the host.
- Several maps: `city.maps` names every map the game can play on (each a
  seed and size for the same generator, plus a title) and `city.current` is
  the one in play; every game starts on `city.DEFAULT`. `city:switchTo(name,
  server)` moves the game to another one: on the host pass the server and
  every car lands on the new map's spawn points, then `mapChanged` reaches
  every feature. The feature that switches tells every client to call
  `switchTo` too (quests sends `QST_MAP`), the same way real-estate tells
  them to grow. Add a map to `city.maps` and it can be reached by name. A
  spec with `crowd = false` has no pedestrians or officers on foot
  (pedestrians and police read `map.crowd`), one with `traffic = false` has
  every NPC car parked out of sight while it is in play (bots reads
  `map.traffic`). Pickups are scattered afresh and koins on the ground swept
  on every switch.
- A growing city: `city:grow(bi, bj)` adds a block past the city limits and
  `city:growthSites()` lists where one may go. The map can stop being a
  rectangle, so read its bounds from `map.c0 c1 r0 r1` (tiles) or
  `map.left top w h` (world px), treat a missing `map.tiles[c][r]` as outside,
  and redraw anything built from the map when `map.version` changes. `city.map`
  is replaced between games, so read it when you need it rather than keeping
  it. Real-estate sells the blocks and tells every client to grow the same way.
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
