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
| `drawScreen(client)` | Screen space, after every feature's `drawHUD` and the core's own lines. For a full panel that must cover the whole HUD when your priority can't put it last: the job board (quests draws at 22), the building menu with its build and product screens (buildings, 26) and the big map (minimap, 890). The shop (993) and the garage (994) get the same by priority instead, under the inventory (995). |
| `drawLens(client, drawWorld)` | Screen space, after the world and before any HUD. `drawWorld(camera, w, h)` draws the whole world again through a camera of your own (`{ x, y, scale }`), centred in a `w` x `h` view (the window when left out): set a canvas first and show it however you like. Weapons draws the sniper's scope this way, and its low-health halo (red creeping in from the screen's edges under 20% health, stronger the lower it goes) so it sits under the HUD. |
| `keypressed(key, client)` | Key press in the game (Esc is taken: it opens the pause menu, and while that is up no key or click reaches a feature and every Controls query reads as released). |

| `mousepressed(x, y, button, client)` | Mouse press in the game. |
| `wheelmoved(dx, dy, client)` | Mouse wheel in the game, not while paused (`dy > 0` is up). Weapons steps through your guns with it. |
| `drawVehicle(client, c)` | Asked before the core draws each car (world space). Draw `c` at `c.dx, c.dy, c.dangle` yourself and return true, and the core's box is left out. Vehicles draws its SVG models this way. |
| `worldBlur(client)` | Asked every frame: return 0..1 for how soft the world should be drawn (the HUD stays sharp). The core takes the highest answer and eases towards it; weapons answers 1 while you are wrecked. |
| `clientMessages = { KIND = function(client, args) end }` | A message from the server the core doesn't know. |

The same `camera` table reaches the draw hooks, so a feature that needs the
visible world bounds divides the window size by `camera.scale`.

Useful client fields: `client.vehicles[vid]` (every car in the world:
`x y angle speed driver` from the server, `owner color` from when it was
spawned, `dx dy dangle` smoothed for drawing), `client.bodies[id]` (every
player on foot: `x y angle`, `dx dy dangle`), `client.players[id].name`,
`client.myId`, `client:pose(id)` (where a player is drawn: `x, y, onFoot,
angle`, or nil while they are wrecked), `client:myPose()`,
`client:myVehicle()`, `client:myBody()`, `client:vehicleOf(id)`,
`client:send(msg, unreliable)`.

### Server side

Runs only on the host. **Everything that changes the world happens here.**
Clients send intent; the server decides. Never trust a client message.

| Hook | When |
| --- | --- |
| `serverStart(server)` | Game started, every player has a body and their own car at the default spawn slot and sits in it. A map feature moves them to its own spawn points here (city-map's `placePlayers`). |
| `serverStep(server, dt)` | Fixed 30 Hz, after car physics, before the `STATE` broadcast. Collisions, projectiles, scoring. |
| `serverPlayerJoined(server, player)` / `serverPlayerLeft(server, player)` | Roster changes. Joined also fires for someone arriving mid-game (`server.started`, `player.body` set) before their `START`: send them any state you only send on change, or they never see it. It fires for bots too (`player.bot`). A player who leaves keeps their car in the world, so `car.owner` may not be in `server.players`. |
| `serverSaveWorld(server)` → table or nil | A saved world is being written (autosave, host quits). Return this feature's part of the world: facts, not what can be worked out, with a `version`. See `persistence.md`. |
| `serverLoadWorld(server, data)` | A saved world is continued: after `serverStart`, with what `serverSaveWorld` returned last time. Not called when there is nothing saved. Tell clients what changed. |
| `serverSavePlayer(server, player)` → table or nil | Every save, and when that player leaves (before `serverPlayerLeft`). Their personal part: wallet, loadout, levels. |
| `serverLoadPlayer(server, player, data)` | A remembered player is back, fully set up (after `serverStart`, or after `serverPlayerJoined` for a latecomer). Put their things back and broadcast, as for any change. |
| `serverMessages = { KIND = function(server, player, args) end }` | A message from a client the core doesn't know. `player` is the verified sender. |

Useful server fields: `server.players[id]` (`id name key guest peer input body
vehicle car`; `key` is the player's lasting identity, and in a saved world
`id` stays the same for that person game after game, see `persistence.md`), `server.vehicles[vid]`, `server.tick`, `server:broadcast(msg,
exceptPlayer)`, `server:send(player, msg, unreliable)`. See "Bodies and
vehicles" below.

## Bodies and vehicles

A player is a person. From the moment the game starts every player has a
`body` (`src/body.lua`: `x y facing dead`), the game gives them a car of
their own (`player.car`) and sits them in it. `player.vehicle` is whatever
they are driving right now, nil on foot; it is usually their own car, but
any car in the world can be driven by whoever climbs in. Every car in the
world is in `server.vehicles`, keyed by its id, with `owner` (a player id or
nil) and `driver` (a player id or nil).

- A person on foot is drawn by `Body.person(x, y, angle, swing, look)` (a
  top-down figure: shoulders, stepping feet, arms, a head with hair or a
  cap), `look` saying what they wear (`shirt`, `pants`, `skin`, `hair`,
  `shoes`, `hat`, `brim`, `hood`, `vest`, `pack`, `gun`, `gunLength`,
  `punch`, `panic`, `alpha`, `shadow`); it returns where the hands are, for something
  held (the horde's torches). Players, the crowd, police officers, Karen's
  simps, the D-Day troops and the open-borders horde all use it, so they
  match; Karen, the Major, Bigfoot and the Runner use it too, drawn their
  size (scaled to their radius) with their own details over it. Anything new on foot should too. They are 17 px across; `Body.RADIUS` (9) is a player's size against
  walls and bullets, and the crowd's and the officers' hit sizes match it.
- `Features.bodyPose(server, player)` → `x, y, onFoot, angle`: where they
  are, driving or walking. `Features.clientBodyPose(client, id)` is the same
  on a client (nil while they are wrecked).
- `Features.present(player)`: spawned, alive, and not sitting in a vehicle
  that is out of the world (a wreck, a parked NPC). Anything that shoots at,
  runs over, sells to or pays a player checks this first, on the host.
- `server:seat(player, car)` / `server:unseat(player, x, y)`: in and out. A
  car someone gets out of stops where it is for the next driver. On-foot
  asks for these on E; weapons uses them around death.
- `server:spawnVehicle(x, y, angle, owner)` / `server:removeVehicle(car)`:
  a new car in the world (everyone hears `VEHICLE <vid> <owner> <color>`)
  or one gone for good (`VEHICLE_GONE <vid>`). A feature that sells cars
  spawns them this way. `server:spawnPlayer(player, x, y, angle)` gives a
  player added mid-game (a bot) a body and a car of their own.
- `car.hidden`: out of the world. The core leaves it out of STATE and
  every feature skips it; weapons parks a dead player's own car this way
  until they respawn, bots park NPCs with it on a map with no traffic. A
  player sitting in a hidden car is not present. `car.stowed` is the same
  for a map with no vehicles: on-foot stows every player's own car there
  and brings them back on the next map with roads.
- Health: a person and a car are hurt separately. Weapons keeps hit points
  per player (their body) and per car; damage to a driver lands on the
  car. A wrecked car explodes and its human driver bails out beside it,
  alive and briefly protected; the car is hidden for the death time and
  comes back whole at its owner's slot (where it died, for a car nobody
  owns). An NPC driver goes down with its car. Cars nobody is driving stop
  bullets and take the damage too, so a parked car is cover and can be
  blown up.
- Death: when a player on foot runs out of health, weapons sets `body.dead`,
  hides their own car at its spawn slot (whole again) and leaves a borrowed
  car where it stands; after the death time they are back at the slot in
  their own car.
- `STATE <tick> <n> [<vid> <x> <y> <angle> <speed> <driver>]... [<id> <x> <y> <facing>]...`:
  every vehicle in the world, then everyone on foot. A player in neither
  list is out of the world.

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
    -- play a sound at client:pose(id)
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

## HUD readouts

The important numbers stand as a row of vertical bars in the bottom-left
corner, one slot each: health (weapons, 0), stamina and the dodge (on-foot,
1 and 2). Abilities are a row of circles along the bottom centre
(`Abilities.hudSlots` of them; keep the strip from about h-80 down clear
of centred text; `Abilities:hudTop()` is where the row starts and
`Abilities:hudLeft()` where it begins on the left; weapons stands the gun
in hand there, a big icon over its ammo count). The minimap sits top right and the koin bottom right,
with `Money:hudCoin()` giving its centre, radius and the y of the line
under it (upgrades writes there). Draw yours into
the next free slot with `UI.drawStatBar(slot, name, frac, color, value,
valueColor, marks, alpha)`: the bar, `name` under it, `value` above, dimmed
by `alpha` when the stat does not apply right now. It returns x, y, w, h.
`UI.rampColor(frac)` is the green-amber-red of health and stamina. Behind
it, colours as `{ r, g, b[, a] }`:

```lua
UI.label("stamina", x, y, { 0.85, 0.85, 0.9 })      -- text with a dark shadow under it
UI.meter(x, y, w, h, frac, color, { 0.2 })          -- a bar `frac` full; optional notches
UI.vmeter(x, y, w, h, frac, color, { 0.2 })         -- the same standing up, filling from the bottom
UI.ring(cx, cy, radius, frac, color, width)         -- an arc `frac` of the way round from the top
```

## Events between features

A feature can raise an event for every other feature with
`Features.call("hookName", ...)`; any feature defining that hook receives
it. `Features.any("hookName", ...)` is the yes/no version: it stops at the
first feature whose hook returns true. `Features.reduce("hookName", value,
...)` passes a value through every hook in turn and returns what comes out
(damage through armor). Events in use:

| Event | Raised by | Meaning |
| --- | --- | --- |
| `serverPlayerDamaged(server, victim, attacker, amount, type, angle)` | weapons | A player (or the car they drive) was hurt, by anything: a round, a blast, a boss. `attacker` may be nil (nobody did it, or they left); `amount` is before armor; `type` is the damage type ("Damage types" under conventions); `angle` the way the blow travelled, when known. The damage feature puts the type's status on a player on foot (bleeding, a stun, a knock). |
| `serverCarsCollided(server, rammer, rammed, closingSpeed)` | car-collisions | Two cars touched while closing. `rammer` was moving into the other faster. |
| `serverShotFired(server, player, x, y)` | weapons | A projectile left a gun at (x, y). `player` is nil for a shot nobody owns (a police officer on foot). |
| `serverWallHit(server, x, y, damage, by, type)` | weapons | A round stopped at a wall (a `blocksPoint`) at (x, y), carrying `damage` of damage type `type`. `by` is the shooter's id, 0 for nobody. Buildings takes the damage when the wall is one of its own. |
| `serverBlast(server, x, y, radius, damage, by, type)` | weapons, leap, Bigfoot | Something hit the ground hard at (x, y): a missile going off (type "explosive"), a heavy leap landing ("impact"), Bigfoot's claws ("melee"). `damage` at the centre, falling to a third at `radius`. Players, cars and soft targets are already handled; buildings hurts every building it reaches. |
| `serverKill(server, { kind, x, y, by, victim, cause })` | weapons, pedestrians, police, bosses | Something died: kind is "car", "pedestrian", "police", "soldier", "boss" or "animal", `by` the killer's id, `cause` the damage type when weapons knows it. |
| `mapChanged(map, server)` | city-map | The game moved to another map mid-game (`city:switchTo`). Raised once per machine; `server` is set on the host and nil on a client. Every car already stands on the new map's spawn points. Drop or move anything you keep in world coordinates: weapons moves its respawn slots, on-foot puts walkers back in their cars, real-estate forgets the old plots. |
| `serverQuestStarted(server, quest, player)` / `serverQuestEnded(server, quest)` | quests | A quest began (everyone is already on its map) or the group took the star home. `quest.boss` names the feature that owns the fight; karen spawns herself on the first and leaves on the second, alien-hunt starts the wild man's walk, d-day puts the defenders on their posts. |
| `questStarted(client, quest, byId)` / `questEnded(client, quest)` | quests | The same on every machine, after the map switched. Karen puts up her title screen and starts her theme here. |
| `serverPanicArea(server, x, y, radius, by)` | abilities | Something stinks at (x, y) (a panic fart): whatever a feature owns inside `radius` should run from it. Raised every host tick while the cloud hangs, so answer with a moment of flight and let it be renewed. Bots drive every NPC car (police units too) away, pedestrians bolt, Karen and her simps and the wild man's squirrel and Bigfoot run. `by` is the caster's id. |
| `serverFreezeArea(server, x, y, radius, seconds, by)` | abilities | A freeze landed on (x, y): whatever a feature owns inside `radius` should stand still for `seconds`. Abilities holds players and cars itself; pedestrians, police officers and Karen root their own. `by` is the caster's id. |
| `serverDodged(server, player)` | on-foot | `player` started a dodge on the host. The damage feature puts out a player who is burning. |
| `clientHit(client, { x, y, amount, dtype, key })` | weapons, on every machine | A player or a car on this screen was hit (`WPN_HIT` / `WPN_CARHIT`): at (x, y), for `amount` after resistances, of damage type `dtype`; `key` is the player id or `"car" .. vehicle id`. The damage feature floats a number up off it. |
| `serverOpenBorders(server, caster, x, y, seconds)` | abilities | Open borders was cast at (x, y): the open-borders feature lets its horde of simps in there for `seconds`. |
| `serverRespawnPoint(spot, server, player)` → `{ x, y, angle }` or nil | weapons asks, through `Features.reduce` | Where a dead human player comes back. Start from nil; a feature that answers wins. With an answer they come back there on foot and their own car stays where it is; without one weapons puts them back at their slot in their own car. The garage answers in the city: their garage's square, or the hospital. |
| `serverWreckClaimed(server, car)` | weapons asks, through `Features.any` | A car was just wrecked (its driver is already out). Answer true to keep it: weapons makes it whole and leaves it to you (hide it yourself), instead of bringing it back at its owner's slot. The garage claims a person's car in the city. |
| `serverDeliver(server, player, item, x, y, angle)` | buildings asks | A building handed over a product nobody carries (a `"car-<model>"`). Put it into the world at (x, y) for `player` and answer true; vehicles spawns the car. |
| `serverStat(value, server, player, name)` / `stat(value, client, id, name)` | on-foot, abilities, armor, buildings ask, through `Features.reduce` | What a player's clothes do to `name`: "speed" and "stamina" (on-foot's pace and sprint cost), "cooldown" (abilities), "armor" (a vest's points), "ammo" (a bundle of rounds going into a bag). Start from 1; gear multiplies by each piece worn, and abilities by the `stats` of the passive ability carried (overclock: "cooldown" x0.8). `serverStatsChanged(server, player)` follows a change of clothes, for anything that keeps a number derived from them (armor rescales the vest). |
| `serverResist(share, server, player, type)` / `resist(share, client, id, type)` | the damage feature asks, through `Features.reduce` | How much of a hit of damage type `type` gets through what a player wears. Start from 1; each feature that dresses them multiplies by (1 - what it stops): armor for the vest, gear for every piece worn (`resist` in their kinds). The damage feature caps the total at `Damage.maxResist` (80%), takes it off every hit to a body before the vest soaks up the rest, and shortens a stun, knockdown, daze or knock by the same share. The inventory's resist strip and the shop's cards show it. |
| `serverAbsorbDamage(amount, server, victim, type)` | weapons asks, through `Features.reduce` | A body is about to take `amount` of damage type `type`; answer what is left of it. Armor takes its share off the top and returns the rest; the hit still counts for everyone listening even when nothing gets through. |
| `serverWalkers(server, add)` | bots asks, every host tick | Call `add(x, y)` for each person of yours on foot, and cars on patrol stop for them. Pedestrians and police (officers) answer it; players out of their cars are added by bots itself. |
| `menuOpen(client)` | weapons asks | Answer true while a menu of yours has the number keys, and weapons leaves the gun alone. The gym's upgrade panel, the building menu, the inventory screen, the cheat list (F2) and the controls overview (F1) answer it. |
| `closeMenu(client)` | the game screen and the inventory ask | Esc was pressed in the game, or the inventory is opening: if a panel of yours is up, take it down and answer true (Esc then doesn't pause). Answer false when nothing of yours was open. The inventory, the shop, the gym's upgrade panel, the building menu, the vehicles screen and the controls overview (F1) answer it; the inventory raises it on every feature before it opens, so I goes straight from the shop to the bag. |
| `actionTaken(client)` | on-foot asks | Answer true while the action key (F) is yours: a prompt of yours is up for it. On-foot then leaves getting in or out of a car alone. Real-estate answers it on a plot for sale, buildings on an owned plot's square, the shop on its bag, the gym (upgrades) at its door, quests at the Jobs door. |
| `fireTaken(client)` | weapons asks | Answer true while the fire button is yours: weapons then neither fires nor clicks on it. Abilities answers it while a direction ability (the MG nest) is selected, and until the button is let go after placing one. |
| `serverEventActive(server)` | police and bots ask, through `Features.any` | Answer true while a city event is on (a boss loose in the streets). Police forgets who was wanted and sees no crimes (the units keep cruising with their lights flashing, the beat keeps walking, nobody is chased or shot); bots forgive every fight, can't be provoked and don't drive recklessly. Both are back to normal when nobody answers any more. The events feature answers it. |
| `drawOnMinimap(client, toMap, w, h)` | minimap | Draw on the minimap: screen space, already moved to its top-left corner and clipped to it; `toMap(x, y)` turns a world point into a minimap pixel and `w, h` is its size. Only while the minimap is showing. The big map (M) calls it too, with its own `toMap` and size, so a mark shows on both. The events feature flashes it red where a boss came in and marks him while he is loose. |
| `hidden(client, id)` / `serverHidden(server, player)` | the core, weapons, minimap, player-arrows ask / `Features.visible` asks | Is this player out of sight (the chicken ability)? Answer true and on a client they are not drawn for anyone else (body, car they drive, name, health bar, minimap dot, edge arrow); on the host `Features.visible(server, player)` (present, and nobody answers `serverHidden`) is false for them. Anything that picks a player to go after or aim at (bots, police, every boss and its helpers) asks `visible` instead of `present`; damage over an area (a blast, a slam, a scream) still asks `present`, so a hidden player caught in it is still hurt. Abilities answers both. |
| `cursorStyle(name, client)` | vision asks, through `Features.reduce` | Which of `vision/cursors.lua` to draw at the mouse, starting from the crosshair: weapons answers "scope" while a gun with a `scope` is in hand and "none" while its lens is up. |
| `pointerTaken(client)` | weapons, abilities, vision ask | Answer true while a screen of yours owns the mouse: weapons doesn't fire, abilities don't aim (an aim in progress is dropped), vision stops edge-panning and leaves the cursor to you: call `Features.byName.vision:drawCursor(client)` at the end of your `drawHUD` and it draws an arrow there, on top of your panel. The inventory screen, the shop, the job board, the building menu (with its build and product screens) and the controls overview (F1) answer it. |

Bots listen to damage and collisions to decide who to fight; police listen
to all of them to decide who is wanted. A trigger-area feature would raise
its own event the same way.

NPC drivers: `Features.byName.bots:spawnNpc(server, { name, x, y, angle, brain })`
creates a server-side driver; `brain.think(server, npc, dt)` runs every tick
and can use `Bots.driveTowards`, `Bots:cruise(server, npc, speed)` (peaceful
driving by the traffic rules in `bots/traffic.lua`: right-hand lane, a speed
limit, slowing for turns, keeping distance, waiting at a busy crossing,
stopping for anyone on foot), `Bots:fight` and `Bots.unstick`. Police is the
worked example. Pass `civilian = true` and every client is told it is
traffic (`BOT_UNIT`): the minimap and the edge arrows leave it out, as they
do the civilian bots. A brain that wants to get somewhere on the street
grid sets `npc.ai.route.next` (an exit of `route.to`) before calling
`Bots:cruise`, and traffic takes that street at the next crossing instead of
a random one; delivery's `route.lua` finds the way.

## Conventions between features

Features stay decoupled by talking through the server's player tables and a
couple of small conventions rather than requiring each other:

- `src/server_settings.lua`: choices the host makes for the game they run
  (bot difficulty today), set on the Settings screen's Server tab and saved
  with the other settings. Read them on the host, live, and never send them
  to clients: bots read the difficulty every time they shoot.
- `server.spawnPoints`: a map feature sets this in `serverStart` to a list of
  `{ x, y, angle }` on drivable ground. Anything that spawns a car (bots)
  uses it when present and falls back to its own placement otherwise.
- `feature:serverWorldSaveHeld(server)`: return true while the world must not
  be saved (city-map: while everyone is away on a quest map). Players are
  still saved.
- `feature:hideSightCones()`: return true while cones of sight should not be
  drawn (sight-cones: the player pressed `` ` ``). Anything that draws a cone
  (police, d-day) skips it when `Features.any("hideSightCones")` is true. It
  only changes the picture; who sees whom is up to the host as before.
- `feature:blocksPoint(x, y)`: return true when a point is inside something
  solid. Weapons checks every feature that defines it, so bullets stop at
  walls without knowing which feature owns them.
- `feature:serverKill(server, kill)`: the host tells every feature that
  something died. The feature that owns the kill calls
  `Features.call("serverKill", server, kill)` right after it broadcasts its
  own message (pedestrians and weapons do); `kill` is
  `{ kind = "pedestrian" | "police" | "car", x, y, by = <killer player id>, victim = <player id> }`
  with `x, y` where it died, not where a wreck respawns. Weapons adds
  `cause`, the damage type that did it. Kind "car" is
  weapons' kind for a player: a wrecked car (`victim` is its driver, nil
  for a parked one) or a player killed on foot (`onFoot = true`). Money
  drops koins there: a pedestrian is worth a fresh koin and an officer on
  foot three, while a wrecked car spills up to five out of `victim`'s own
  wallet and nothing at all if it was empty, so fill in `victim` for
  anything a player was driving. Ignore kinds you don't care about; new
  kinds may appear.
- `feature:serverShotAt(server, x, y, radius, by, angle, damage, type)`: a bullet is
  passing through this point on the host. Kill whatever of your own is
  standing within `radius` of it and return true, and the shot stops there;
  return false and it flies on. Weapons walks its projectiles through every
  feature that defines it, so a gun kills pedestrians without knowing they
  exist (police answers it too: officers on foot take a few rounds before
  they go down). `by` is the shooter's player id and `angle` the direction of
  travel, for gibs and scoring; `by` is 0 for a shot no player fired;
  `damage` is what the round carries (nil from a blast), for a target that
  takes hits rather than dying to one (Shotgun takes a sniper round's 200),
  and `type` its damage type (a blast's "explosive", a heat ray's "fire";
  the same call is made by anything that hurts an area). Cars
  are tested first, so answering here never steals a hit from a player.
  A missile's blast (the rocket launcher) asks each feature up to its
  `blast.soft` times at the blast centre with a wide radius, stopping at the
  first false, so answer one target per call.
- `Features.bodyPose(server, player)` and `Features.clientBodyPose(client,
  id)`: where a player is, driving or walking (see "Bodies and vehicles").
  Weapons fires from there, lands hits there and draws the health bar
  there; money, pickups, bots, police and Karen use them, so anything that
  happens "to a player" happens to the body. A parked car is a target of
  its own, never a stand-in for the player who left it.
- `Features.byName.weapons:serverDamage(server, victim, attacker, amount, angle, type)`:
  hurt a player from any cause (cars run walkers over with it). Kills raise
  `serverKill` with `angle`, `onFoot` and `cause`. Nobody is hurt during
  their spawn protection. `weapons:damageCar(server, car, byId, amount,
  pid, angle, type)` is the same for a car (`pid` 0 when it wasn't a round).
- Damage types: every hit says what kind of hit it is (`src/features/damage`,
  design and plan in `docs/damage-types.md`): "bullet", "explosive",
  "fire", "impact", "shock" or "melee", in `Damage.types` with each one's
  name, colour and kill feed words. **Anything new that hurts passes its
  type** as the last argument of `serverDamage` / `damageCar` and of the
  `serverShotAt` / `serverBlast` it raises; left out, it counts as
  `Damage.DEFAULT` ("bullet"). A gun declares `damageType` (default
  "bullet") and a missile's blast `blast.type` (default "explosive").
  Every hook that hears about damage gets the type on the end
  (`serverAbsorbDamage`, `serverPlayerDamaged`, `serverShotAt`,
  `serverBlast`, `serverWallHit`) and `serverKill` gets `cause`;
  `WPN_KILL` and `WPN_WRECK` carry it, and the kill feed says "Bob burned
  Alice" in the type's colour. A new type is a new entry in `Damage.types`.
  What it looks like (the damage feature's `effects.lua`): the ring a hit
  flashes round a body or a car is the type's colour, a number in that
  colour floats up off every hit (quick hits on one target add up into one;
  `Damage.numbers = false` turns them off), and a hit under 3 makes no
  sound. Death on foot leaves what the type would (`OF_GIB` carries the
  cause, `damage:deathAt(x, y, angle, cause)` draws it): ash for fire and
  shock, a scorch mark and the pieces thrown every way for a blast, a
  bigger splat for impact, the gibs for bullets and melee.
  What a type does besides the damage, to a player on foot (the damage
  feature, from `serverPlayerDamaged`): melee leaves them bleeding, shock
  stuns them, impact knocks them back a little and down, explosive blows
  them back (further the harder it hit) and dazes them (`worldBlur`).
  Stunned or down is held (`serverHeld` / `held`). Fire does nothing by
  itself: `Features.byName.damage:ignite(server, victim, seconds, dps, by)`
  sets someone alight, and the heat ray ability, the Tripod's beam and the
  open-borders fires call it with their own `afterburn` numbers; anything
  new that burns should too. Burning and bleeding bite every quarter second
  (the kill is `by`'s); another dose tops the time up at the stronger rate,
  never stacks. A dodge puts a fire out, a medkit stops a bleed
  (`damage:serverStopBleeding(server, id)`), and a car, dying or leaving
  ends everything. `damage:serverAfflict(server, victim, status, seconds,
  dps, by)`, `serverCure(server, id, status)` and `serverHas(id, status)`
  are the general form (status "burn", "bleed", "stun", "down" or "daze");
  every client hears `DMG_FX <id> <status> <seconds>` and draws it. A knock
  is `Features.byName["on-foot"]:serverShove(server, player, dx, dy,
  distance, seconds)`: the body is carried that far, sliding along walls,
  whatever holds it.
- `Features.byName.weapons:serverSetMaxHealth(server, player, max)` and
  `Features.byName["on-foot"]:serverSetMaxStamina(server, player, max)`: raise
  a player's ceiling for the rest of the game (respawns keep it). Raising it
  tops them up by the difference. Each owner broadcasts its own `WPN_MAX` /
  `OF_MAX` so every HUD scales. `on-foot:serverSetStaminaRegen(server,
  player, scale)` sets how fast stamina comes back, as a multiple of the
  base rate (host only; nothing to draw). `on-foot:serverSetDodgeScale(server,
  player, scale)` sets how far their dodge carries them, as a multiple of
  `dodgeDistance` (broadcast as `OF_DASH`, since each client predicts its own
  dash). Upgrades (the gym) buys all four with koins.
- `Features.byName.weapons:serverSetCarMaxHealth(server, car, max)`: give one
  car a health ceiling of its own (every car has 100 otherwise) and fill it
  up; wrecks come back with it. Weapons broadcasts `WPN_CARMAX` so every
  health bar scales. Vehicles sets each model's hitpoints this way.
- Vehicle models: every `src/features/vehicles/models/<type>-<colour>.svg`
  is a car model, found at startup. A `<type>.lua` beside it sets the
  stats every colour of that type shares: name, price, hitpoints, top
  speed, acceleration, weight, turning, drawn length, and the factory's
  build time and materials (the header of `vehicles/catalog.lua` lists
  them). A new colour is just a new SVG; a `<type>-<colour>.lua` changes
  one colour on its own. `Features.byName.vehicles:serverSpawn(server,
  model, x, y, angle, owner)` puts one on the road (`model` from
  `vehicles.catalog.byKey`), tuned and drawn as that model. The SVG reader
  (`vehicles/svg.lua`) handles paths, basic shapes, fills, strokes, groups
  and transforms; not CSS classes, `<use>`, text, clips or masks.
- `Features.byName.weapons:serverHeal(server, player, amount)` and
  `Features.byName["on-foot"]:serverRestoreStamina(server, player, amount)`:
  top a player up towards their ceiling. Both return true only if anything
  was gained, so a pickup that did nothing (full health, a drink taken from
  behind the wheel) can stay on the road. Pickups uses both. A heal fills
  the body first and then the car they are driving;
  `weapons:serverRepair(server, car, amount)` mends a car on its own.
  `on-foot:serverStamina(player)` reads a walker's stamina and ceiling (nil
  for a driver); second wind uses it.
- `Features.byName.money:wallet(id)` / `money:spend(server, id, amount, label)`:
  read a wallet on the host, or take koins out of it all-or-nothing (false
  and a reason, and nothing happens, when they can't cover it). Every sale
  goes through `spend`; see "Selling things for Fcks" below.
- `Features.byName.money:serverSetReach(server, player, scale)`: how far a
  player's koins jump to them, as a multiple of the base radius; money
  broadcasts `FCK_REACH` and draws the ring. Pickups scales its radius by
  the same reach (`money:reachOf(id)`), so drops (medkits, drinks, ammo,
  abilities) come from as far as koins do. Upgrades sells it ("Pickup reach").
- Ammo: guns fire from a magazine (`magazine`, `reload` in `weapons/guns.lua`)
  and reload from the player's inventory, `"ammo-<gun key>"`, through
  `buildings:serverCount(id, item)` and `buildings:serverTake(server, player,
  item, n)`. A gun marked `bottomless` (the pistol) reloads from nowhere:
  there is no ammo item for it, and the shop, the ammo factory and the
  police drops leave it out. `weapons:serverFire` counts rounds for human
  players only; a player with `bot = true` (bots, police) and
  `serverFireFrom` never run dry.
- Tiers: everything a player equips (guns, abilities, armor, clothes) comes
  in a tier, `src/features/tiers`: common (grey, base stats), uncommon
  (green, its first stat better), rare (blue, its first two, by more) and
  legendary (gold, all of them, by more again). Each kind lists the stats a
  tier improves, in order, as `tierStats` (`guns.lua`, each ability module,
  `armor/kinds.lua`, `gear/kinds.lua`). An item of a tier is its key with
  `@<tier>` on the end (`"gun-uzi@rare"`); nothing on the end is common, so
  old items and saves stay valid. `Tiers.split(s)` → base, tier (nil for a
  made-up one), `Tiers.join(base, tier)`, `Tiers.apply(kind, tier)` → a
  table that reads like `kind` with the tier's numbers (cached, with `tier`
  and `base`), `Tiers.color(tier)` and `Tiers.drawFrame(tier, x, y, w, h)`
  for every box that shows one. A slot keeps its tier (`"leap@rare"` in an
  ability slot, `"vest@rare"` worn) and hands the item back in it; another
  tier of something already carried swaps with it where it is. Medkits,
  drinks, ammo and materials have none. **New equipment gets tiers too**:
  add its item prefix to `Tiers.prefixes`, give its kinds `tierStats`, read
  its numbers through `Tiers.apply`, and draw its boxes with `drawFrame`.
- Weapon slots: each player carries guns in `weapons.slotCount` slots, one
  per number key; the host keeps them (the pistol in slot 1 and any gun with
  a `stock` in `guns.lua` after it, to start with) and tells the player
  (`WPN_GUNS`, a gun index per slot, 0 for empty). A gun is also an item
  (`"gun-<gun key>"`, from a weapons factory): `WPN_EQUIP <gun> <slot>` takes
  one out of the bag and puts the gun in that slot (a gun already there goes
  back into the bag), `WPN_UNEQUIP <slot>` puts the slot's gun back as an
  item (if there is room; never the pistol), `WPN_MOVE <slot> <slot>` swaps
  two slots. The inventory screen sends those on drags.
  `weapons:serverOwns(player, index)` is the host's answer to "do they carry
  it" and `weapons:owns(index)` the client's; selecting or firing anything
  else is refused, and putting down the gun in hand leaves the pistol.
- Ability slots: the same for abilities. `abilities/kinds.lua` lists every
  ability by `key` (and `abilities/icons.lua` draws each one's icon: give a
  new ability a drawing there, or it shows as a plain dot); each player carries them in `abilities.slotCount` slots
  (Q, E, R, and a keyless passive slot for an ability with `passive = true`,
  which only fits there), freeze in slot 1 to start with, kept on the host and told to
  the player (`ABL_SLOTS`, a key per slot, `-` for empty). An ability in a
  bag is the item `"ability-<key>"`; `ABL_EQUIP <key> <slot>`,
  `ABL_UNEQUIP <slot>` and `ABL_MOVE <slot> <slot>` move them, and a cast
  (`ABL_CAST <key> ...`) is refused unless the ability is in one of the
  caster's slots. Cooldowns follow the ability, not the slot. The shop
  sells ability items. A passive ability (`regen.lua`: once the body has
  gone a few seconds unhurt it heals fast for three seconds, then rests
  through a cooldown; `secondwind.lua` does the same for stamina, once the
  bar has gone a moment without being spent; or `overclock.lua`, whose
  `stats` cut its carrier's cooldowns through the `serverStat` / `stat`
  conventions) has no cast; abilities calls its `serverTick(server,
  player, dt, abilities)` every host tick while it sits in a player's
  passive slot, `abilities:serverSinceHurt(player)` says how long its
  carrier has gone unhurt, and `abilities:serverPassive(server, player,
  key, phase, seconds)` tells the carrier its phase (`ABL_PASSIVE`; idle,
  active or cooldown) so the HUD's passive ring shows it working and then
  filling back. `weapons:serverHealth(player)` reads a body's hit points
  and ceiling on the host. An ability with `aim = "direction"` (`mgnest.lua`)
  is selected with a press of its key and placed with the fire button,
  `range` px away towards the cursor, facing away from the caster:
  `serverCast` returns its facing as a second value (and, third and
  fourth, where it settled, if it moved: the nest steps back out of
  walls) and `ABL_FIRED` carries them, `drawAim(ox, oy, x, y, time, mode)` draws the arrow while it is
  selected (a point ability may have one too), and an ability's `serverStep(server, dt, abilities)` runs
  whatever it left standing in the world (the nest sprays AK-47 rounds,
  owned by its placer, across its forty-five-degree arc for five
  seconds, sweeping side to side and picking no targets: the rounds hurt
  whatever they meet; `serverReset()` clears them between games). An
  ability with `modes` (a list of `{ key, title }`) does more than one
  thing: a tap of its key works as usual in the mode it is on, and holding
  the key for `modeHold` (0.3 s) brings its modes up as buttons over its
  ring; pointing at one and letting go (or clicking it) switches to it.
  The mode goes up with `ABL_CAST <key> <x> <y> <mode>` and out with
  `ABL_FIRED` (after the angle, `-` for none); `serverCast` gets it as
  its last argument and effects see it as `e.mode`. The first is the heat
  ray (`heatray.lua`, the tripod's drop, never sold): beam burns the spot
  you pick, within 450 px, for 1.2 s (100 to someone standing in it);
  sweep drags the ray across an arc 200 px out in front of you (about 75
  to whatever it crosses). Either hurts everything but you: players and
  bots on foot, cars but your own, and whatever answers `serverShotAt`
  (pedestrians, officers, bosses). Its icons are `heatray`,
  `heatray-beam` and `heatray-sweep` in `icons.lua`. One
  with `aim = "self"` (`heal.lua`) is cast where the caster stands by a
  press of its key: a circle that follows them for a few seconds and
  heals every player inside it through `weapons:serverHeal`; the panic
  fart (`fart.lua`) is the other, a cloud that hangs where it was let go
  and raises `serverPanicArea` every tick. Effects carry
  `by`, the caster, and `drawEffect(e, client)` gets the client to follow
  them.
  The chicken (`abilities/chicken.lua`, `aim = "self"`) makes its caster
  invisible for its `seconds` (20, 50 s cooldown for a common one; tiers
  stretch the first and shorten the second), or until they fire a gun:
  abilities hears `serverShotFired`, ends it on the host and tells
  everyone (`ABL_REVEAL`). See `hidden` / `serverHidden` under events. `Chicken.variant(tuning)` is the same trick on other
  numbers (Shotgun's).
  A gun with a `scope` (the sniper rifle: 200 a round, five in the
  magazine, a five-second reload, a round that carries a little past
  anywhere the cursor reaches) has a scope's crosshair for a cursor, and
  holding the scope button (`scope`, right mouse) opens a lens round the
  cursor showing the world `scope` times closer (`drawLens`).
  A gun with a `blast` (the rocket launcher) fires a missile that explodes
  on whatever stops it, or in mid-air when its `ttl` runs out, hurting every
  player and car in the radius, the shooter included (`WPN_BOOM` draws it).
  A gun's `stock` is how many rounds each human player starts the game with.
  The flamethrower sprays short-lived tongues of fire (`flame` draws them,
  `damageType = "fire"`), and a round that catches somebody on foot sets
  them alight (`ignite = { seconds, dps }`, the damage feature's burning).
  Its magazine is a `tank`: a reload takes one fuel can ("ammo-flamethrower",
  made from oil and iron at the ammo factory) and fills it whole, and
  boxes, drops and stocks count cans, not rounds.
- `Features.byName.weapons:serverFireFrom(server, ownerId, x, y, aim, gun)`: put a
  bullet into the world from something that is not a player behind the wheel.
  `gun` is a table from `src/features/weapons/guns.lua` (the pistol when
  left out); its damage, speed and scatter apply.
  Pass `0` as the owner for a shot that belongs to nobody -- it can hit
  anyone, and its kills credit no scoreboard; the police officers on foot
  shoot this way. No cooldown is applied, so the caller paces its own fire.
- `Features.byName.weapons:explosionAt(client, x, y, color)`: an explosion
  seen and heard at (x, y) on this machine (client side, no damage). Buildings
  blows up with it when one comes down.
- `Features.byName.money:give(server, id, amount)`: put koins into a
  player's wallet, the other way round from `spend` (the cheats use it).
- `Features.byName.buildings:serverGive(server, player, item, n)`: put up
  to `n` of an item into a player's inventory, as many as fit; returns how
  many went in. The other way round from `serverTake`.
- Freight, for moving materials between buildings with no player carrying
  them (host only): `buildings:serverBuilding(plotId)` reads the host's
  record of a building (kind, owner, product, output, hopper, hp);
  `serverTakeOutput(server, plotId, n)` → item, taken takes up to `n` of what
  a quarry or oil well made; `serverHopperRoom(plotId, item)` and
  `serverFillHopper(server, plotId, item, n)` → moved fill a factory's hopper.
- `Features.byName.vehicles:serverSetModel(server, car, model)`: make a car
  already in the world (an NPC's own) a model from `vehicles.catalog.byKey`.
- `Features.byName.pickups:serverDrop(server, kind, x, y, amount)`: leave a
  pickup on the ground right there, gone for good once taken. `kind` is a
  pickups kind ("health", "stamina"), `"ammo-<gun key>"` for a box of
  `amount` rounds that goes into the taker's inventory, or a material
  (`"iron"`) for a crate of `amount` of it (a human takes what fits in
  their bag; the rest stays as a smaller crate).
  `pickups:serverDropAmmo(server, x, y, magazines)` drops a box for one of
  the guns that take ammo, picked at random and sized in that gun's
  magazines.
  `pickups:serverDropEnemy(server, x, y)` is what every enemy calls when it
  goes down (Karen's simps, the hunt's squirrels, D-Day's soldiers, the
  police's officers and units), and the one place the odds live: one thing
  at most, `pickups.dropChance` (40%) of anything, then one of
  `pickups.drops` (an ammo box, a medkit, an energy drink, a kevlar vest),
  each as likely; something with tiers then rolls its tier by
  `pickups.dropTiers` (80, 14, 5 and 1 in every 100 from common up). Add a
  kind to `drops` and every enemy can drop it. A human with no armor on
  who runs over a vest wears it at once, whole
  (`armor:serverWearFound(server, player, kind)`); one wearing a damaged
  vest has it topped back up to full (or wears the found one instead if it
  holds more); anyone whose vest is whole leaves it lying.
- `feature:serverHeld(server, player)` / `feature:held(client, id)`: is this
  player held still by some feature (frozen)? On-foot asks every feature
  through `Features.any` before walking, seating or unseating them, and
  weapons before firing their gun; on a client the same question stops
  prediction and the HUD says so. Abilities answers it for the players it
  holds, and `Features.byName.abilities:serverHold(server, player, seconds)`
  holds one from any feature: the car they are driving or their feet stay
  where they are until it wears off.

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
example with a menu at a place to stand (the gym's door); real-estate is
the one with a plot.
- Plots: city-map leaves the corner blocks empty as `kind = "plot"` in
  `map.blocks`; real-estate sells them and answers `real-estate:owner(plotId)`
  on the host. `real-estate:serverTransfer(server, plotId, playerId)` hands a
  plot to someone else (buildings' hostile takeover, after they have paid).
- Buildings: `src/features/buildings` puts a building on a plot its owner
  picks (parking lot, quarry, oil well, ammo, weapons, health and vehicle factories;
  the catalog is `kinds.lua`), used from a square on the sidewalk in front of
  the plot. Owners set what a building sells for and what it pays for each
  material it runs on; other players sell into its hopper from there. A
  product can have its own recipe (`recipes` in `kinds.lua`: rockets and the
  rocket launcher need copper, oil and plastic on top of iron and sulfur);
  add a material to `Kinds.materials` and `BLD_STATE` carries it. Buildings are solid (all but the parking lot): buildings pushes
  cars and pedestrians out itself and answers `blocksPoint` for everything
  else. The inventory lives there too, on the host, keyed by item
  (`"iron"`, `"ammo-uzi"`, `"gun-uzi"`, `"ability-freeze"`, `"medkit"`, `"drink"`, `"armor-vest"`, `"gear-running-shoes"`), in slots of one stack
  each; `buildings:serverSetSlots(server, player, n)` changes how many a
  player has (upgrades sells them). Weapons reloads from the ammo in it and
  moves guns in and out of it as items. Buildings have hit points (`hp` in
  `kinds.lua`) and take damage through `serverWallHit` and `serverBlast`; a
  destroyed one is a ruin (not solid, makes nothing) until its owner pays to
  rebuild it, or anyone else pays `buildings.takeoverPrice` to take the lot
  over empty. A building still standing can't be taken over. Switching what
  a building makes scraps whatever it had made of the one before. A factory
  whose goods can be carried (all but the vehicle factory,
  `Kinds.sellsToShop`) can be set to sell to the shop (`BLD_TOSHOP`, the
  last field of `BLD_STATE`): delivery's drivers then take its goods to the
  shop. What a thing fetches there is `Kinds.worth(item)`, worked out from
  its recipe (materials at their quarry or oil well price, plus
  `Kinds.WORTH_TIME` a second, over the batch, times `Kinds.WORTH_MARGIN`),
  so the harder to make, the more it pays. Materials and cars have none.
- Surroundings: `src/features/surroundings` draws the world past a map's
  edge (over the grid, under the map), made up as the camera looks so it
  never runs out. The city is an island: deep sea, lighter shallows round
  the shore, rolling waves, foam against a concrete harbour wall with
  bollards, and boats sailing loops round it. The shore follows the city's
  land tile by tile, so a block the city grows gets its own quay.
  Whispering Pines (the forest) goes on as forest: pines and broadleaf
  trees stamped from a few pictures drawn once (so a thousand on screen
  cost little), a ragged treeline at the edge, darker further out. Karen's
  cul-de-sac is hedged in: the neighbours' lawns and woods past the hedge,
  and its street runs on south out of the entrance, hedged both sides and
  lit by street lamps (`woods` is shared: trees from a distance out, off
  somewhere like a road). Looz'er Beach runs on along the coast both ways
  band by band (hedgehogs on the sand, barbed wire fencing the battle off
  at the sides), hedgerowed farmland north of the hill and the sea south,
  warships steaming along offshore. Shotgun's Bluff runs on both ways
  (plateau, cliff face, flowered meadow, boulders) between dry-stone walls,
  a canyon with a river at its bottom drops away north of the plateau, and
  the meadow gives way to woods south. The outskirts are fenced round with
  post and rail, farmland past it: a patchwork of fields with tracks
  between, a lone tree here and there, a farm and a tractor working a
  field. Every map now has surroundings; a new one gets them with an entry
  in the `DRAW` table (by map name), and shows the grid until it does. The crowd spawns only on the map's land.
- Car tags: `src/features/car-tags` writes the owner's name over a parked
  car, the way the core writes the driver's over a moving one, so you know
  whose car you are borrowing and can spot your own. Player-arrows marks the
  window's edge towards other players (a walker), police (an arrow) and your
  own cars (a car) while they are off screen; civilian bots are left out
  (bots tells clients who they are with `BOT_UNIT`).
- Armor: `src/features/armor` is what you wear against damage. A vest
  (`armor/kinds.lua`; `"armor-<key>"` in a bag, sold by the shop) dragged
  onto the armor gear slot on the inventory screen goes on whole
  (`ARM_EQUIP`) and soaks up damage to your body until its points are
  gone, when it is destroyed; only then does health go. Dragged back into
  the bag it comes off (`ARM_UNEQUIP`), as an item while whole, thrown
  away once damaged. Death takes it. `ARM_STATE` tells everyone what a
  player wears; the armor bar stands fourth in the bottom-left row, always
  there, grey and empty with nothing on. `armor:serverWorn(player)` reads
  it on the host. A vest can resist damage types (`resist`, a share per
  type, improvable by tier as `"resist.<type>"`): the kevlar vest stops
  30% of bullets, the bomb suit half of every blast and some knocks and
  fire, riot armor fists and claws, the insulated suit shocks and fire,
  ceramic plates bullets with the most points (`serverResist` / `resist`;
  the full list is in `docs/damage-types.md`).
- Gear: `src/features/gear` is the clothes: a piece (`gear/kinds.lua`;
  `"gear-<key>"` in a bag, sold by the shop) has a slot (head, body, pants
  or shoes) and `stats`, multipliers other features read through the
  `serverStat` / `stat` conventions (running shoes: speed x1.15, sprint
  cost x0.7; a tactical hat: ammo bundles x1.5; cargo pants: ability
  cooldowns x0.75; a plate carrier: armor x1.25). Dragged onto its slot on
  the inventory screen it goes on (`GEAR_EQUIP`; what was there swaps into
  the bag), dragged back it comes off (`GEAR_UNEQUIP`); clothes are never
  damaged and death leaves them on. `GEAR_STATE` tells everyone what a
  player wears. Add a piece to the list and the shop and the slots know it;
  give it a drawing of its own in `gear/icons.lua` (without one it is its
  slot's plain cap, shirt, trousers or shoes). Armor draws the same way, in
  `armor/icons.lua`. Both, and the guns' `weapons/icons.lua`, shade their
  parts with `weapons/shade.lua` (`Shade.box`, `Shade.poly`, ...: a lit top,
  a shadowed bottom, a one-pixel outline at any scale).
  A piece can also resist damage types (`resist = { fire = 0.4 }`; a tier
  grows it by its `bonus`, `gear.resistance(g, tier, type)` reads it).
  Each slot has five pieces; most resist one or two types, and the list is
  in `docs/damage-types.md`. A drawback (x0.95 speed) stays out of
  `tierStats`, or a tier would grow it.
- Open borders: `src/features/open-borders` is the horde behind the "open
  borders" ability (`abilities/openborders.lua`, sold by the shop). Cast, it
  lets 25 simps out round the caster (the `serverOpenBorders` event); for
  30 seconds they run about near them lighting fires and punch whoever comes
  close, the caster included, running off for a few seconds after each
  punch. A fire burns for 30 seconds and every half second hurts whatever
  touches it but the simps: players and cars through weapons, soft targets
  through `serverShotAt`. The simps answer `serverShotAt` and
  `serverFreezeArea` and `serverPanicArea` themselves and a car at speed flattens one.
  `OB_SIMPS`, `OB_SIMP_DOWN`, `OB_FIRE` and `OB_CLEAR` carry it to clients;
  tuning is at the top of `horde.lua`.
- Inventory: `src/features/inventory` is the screen (I) that shows what you
  carry around a picture of you: gear slots (head, body, pants and shoes
  for clothes, and armor), a stats strip (what the clothes do to speed,
  sprint cost, ammo bundles, cooldowns and armor, read through `stat`), a weapon slot
  per number key, an ability slot per ability key, and the item boxes. It
  owns the mouse while it is up (`pointerTaken`) and the number keys
  (`menuOpen`); drag a gun or ability from the bag onto a slot to put it on
  that key, out of its slot into the bag to put it down, or between slots to
  swap (weapons and abilities do the moving). Beside the abilities are the
  quick slots, one per entry of `buildings.usables` (medkits on H, energy
  drinks on J): a stack dragged onto its slot is what the key uses
  (`BLD_QUICK_PUT <item>` / `BLD_QUICK_TAKE <item>`; buildings keeps the
  slots and says `BLD_QUICK <item> <n>`); stacks left in the bag are just
  carried. Each usable has a circle at the end of the abilities row on the
  HUD with its key and count, and each use starts its cooldown (told by
  `BLD_USED <item> <seconds>`) that the ring fills back through. Add an
  entry to `usables` (item, key, colour, cooldown, `apply`) and the slot,
  the circle and the key come with it.
  `screen.lua` lays out every box (`Screen.layout()`), so dragging anything
  else later hit-tests the same rectangles.
  The picture of you (`inventory/figure.lua`), with the menu's crazy face
  (`src/art/face.lua`, blinking and twitching) for a big head, wears what you wear: each
  clothes piece and armor front on in its colour with the bits that make it
  itself, and the gun in hand in the right hand; a new piece without a
  drawing of its own there wears its slot's plain shape in its colour.
- Several maps: `city.maps` names every map the game can play on (each a
  seed and size for the same generator, plus a title; `kind = "culdesac"`
  builds a suburban dead end instead of a grid, with `map.circleX, circleY`
  at its turning circle; `kind = "forest"` is trees and shrubs round a dirt
  trail, with `map.trail`, `map.waypoints` (its clearings) and `map.lair`;
  `kind = "beach"` is a landing beach under a defended hill, with
  `map.bands` (hill, barracks, bunkers, beach, surf: each a `y0`..`y1`),
  `map.flagX, flagY`, `map.posts` (where defenders stand), `map.doors`
  (barracks doors) and `map.cover` (tank stoppers, sandbags, bunkers and
  huts, all solid); `kind = "cliff"` is a meadow under a long cliff with a
  plateau on top and one ramp up at the far left, with `map.cliffY`,
  `map.plateau`, `map.meadow`, `map.ramp`, `map.perches` (spots on the
  plateau for a sniper; `edge` ones overlook the meadow), `map.clumps` and
  `map.cover` (dry-stone walls, boulders, and the cliff itself, marked
  `ledge = true`: solid to walkers and to rounds); `kind = "city17"` is
  City 17, walked from the train at the bottom to the Citadel at the top,
  with `map.zones` (platform, station, plaza, old town, wall, canal,
  citadel: each a `y0`..`y1`), `map.citadel` ({ x, y, r }),
  `map.citadelX, citadelY` (in front of its doors), `map.bridges`,
  `map.screen`, `map.lanes`, `map.patrols` (beats for squads, each a loop
  of { x, y } corners kept clear of loose cover), `map.crowdClothes` (the
  citizens' jumpsuits, which pedestrians dresses its crowd in), `map.offLimits` (the
  track: `randomRoadPoint` never picks a spot there, nor anywhere solid) and `map.cover` (Combine walls, barriers,
  planters, the station wings, the train, the canal's water, the Citadel,
  the screen and rubble; rubble and the screen are drawn but not solid).
  Anything in `map.cover` with a `mapColor` is drawn on the minimap in it,
  round with `round = true`, and the minimap draws "walk", "road" and
  "water" tiles as well as "ground")
  and `city.current` is
  the one in play; every game starts on `city.DEFAULT`. `city:switchTo(name,
  server)` moves the game to another one: on the host pass the server and
  every car lands on the new map's spawn points, then `mapChanged` reaches
  every feature. The feature that switches tells every client to call
  `switchTo` too (quests sends `QST_MAP`), the same way real-estate tells
  them to grow. Add a map to `city.maps` and it can be reached by name. A
  spec with `crowd = false` has no pedestrians or officers on foot
  (pedestrians and police read `map.crowd`), one with `police = false`
  keeps its pedestrians but no officers on foot (police reads
  `map.police`), one with `traffic = false` has
  every NPC car parked out of sight while it is in play (bots reads
  `map.traffic`), and one with `vehicles = false` is walked: on-foot turns
  everyone out beside their car and refuses to let them back in (Karen's
  street). Pickups are scattered afresh and koins on the ground swept on
  every switch.
- Gym: the upgrades feature's building (`src/features/upgrades`), picked
  by `quests/jobs.lua` after the Jobs building and the shop so it never
  moves them: a third building in their block, or the nearest one to the
  Jobs door outside it (`upgrades:here()`; the default city only). A
  storefront with a dumbbell, marked on the minimap. Its door square opens
  the upgrade panel on the action key (`actionTaken`), and the host only
  sells a level to a buyer at that door (`UPG_DENY ... away`).
- Quests: every job starts at the Jobs building in the city
  (`quests/jobs.lua` picks one of the city's own buildings the same way on
  every machine, like the hospital, clear of the spawn road and the
  garage's places, in a block with room for the shop beside it). Both are
  drawn as storefronts facing the street (`quests/storefront.lua`: roof
  units, a lit window, a striped awning), each with its own things outside. Stand on the square by its door, press the action
  key (F, through `actionTaken`) and the job board lists every quest marked
  `board = true` in `quests.list`; pick one and take it (`QST_ACCEPT`, the
  host checks you are at the door). The board owns the mouse
  (`pointerTaken`) and Esc closes it (`closeMenu`); the building is marked on
  the minimap. The way back is still a star on the quest map (a quest with
  `onMap`, `x, y` and `returns`); a map may carry several stars and the
  nearest one is on offer. A trip still takes the whole server.
  `Features.byName.quests:serverComplete(server, questId, x, y)` marks the
  job under way as done (everyone hears `QST_DONE`); `quests:serverActive()`
  is the quest in play on the host. Every boss calls the first when it goes
  down, passing where it fell: an EXIT star home (`QST_EXIT <x> <y>`) comes
  up right there, so nobody has to walk back to the entrance. Leave out
  `x, y` and there is only the star by the entrance.
- D-Day landing: `src/features/d-day` is the third boss quest, on the
  beach map. Guards stand on the map's posts sweeping thirty-degree cones
  of sight (`sight.lua`; solid cover hides you), turn to follow and fire at
  anyone they see for as long as they see them; riflemen come out of the
  barracks and walk down at the players; mortars fall on the beach behind a
  warning ring. Reaching the flag puts up Major Looz'er's portrait, then he
  fights, throwing down the MG nest ability (`abilities/mgnest.lua`) every
  few seconds. Soldiers raise `serverKill` with kind "soldier", the Major
  with "boss". Tuning is at the top of `init.lua`, `brain.lua` and
  `major.lua`.
- Shotgun: `src/features/shotgun` is the fourth boss quest, on the cliff
  map (Shotgun's Bluff). Everyone arrives at the bottom right; Shotgun is
  on the plateau with a sniper rifle, and the cliff stops every round fired
  up at him, so the way to him is from cover to cover up the map and left
  to the ramp. He goes invisible whenever he can (the chicken on his own
  numbers) and moves to a new spot, and when he shows again he draws a bead
  on the nearest player he can see: for a second every screen shows it (a
  laser and a closing ring) and the target's screen throbs red, then he
  fires where they were going (he leads a walker), so stopping, turning,
  dodging or ducking behind something makes him miss. Close in and he
  vanishes again or, when he can't, backs off with his pistol. His rounds
  leave from past the lip, so the cliff never stops them. Down, he drops
  the chicken as a pickup; he raises `serverKill` with kind "boss". Tuning
  is at the top of `boss.lua` and `init.lua`.
- A-Man's quest: `src/features/a-man` (the boss feature) and quests'
  "a-man" job ("The man with the moustache", on the board) take everyone
  to City 17 (city-map's `city17`), arriving on the platform, with a HOME
  star at its left end ("home-city17"). His intro screen
  (`a-man/screen.lua`) comes up on arrival for 9 s or until a key. The
  quest is planned as several levels ending with A-Man himself; City 17 is
  the first (`a-man/city17.lua`, the a-man feature passes its hooks on).
  Combine soldiers stand on every checkpoint (the map's `posts`: the
  station's concourse, the avenue's mouth on the plaza, the gate, each
  bridge and the Citadel's doors, 12 in all), thinking with their own
  brain (`a-man/combine.lua`; D-Day's soldiers have a replica of it,
  `d-day/brain.lua`) and seeing with `d-day/sight.lua`: the same
  sweeping cone and 60 health, taking each round's own `damage` (20 from a
  blast, which carries none; D-Day's take 20 a round out of 40), 3 koins and
  maybe a pickup when they drop. The first player within 140 px of the
  Citadel's doors finishes the level (`quests:serverComplete`): a star
  comes up there, saying the quest's `exitText` (a quest may give its EXIT
  star its own words). For now it leads home; it will lead to the next
  level. Squads of 3 walk the map's `patrols` (troops' `patrol` kind,
  `Troops:addSquad`: the first leads, the rest keep formation, and the
  squad stops and turns when one of them has somebody). City 17 makes its
  troop with `Troops.new({ hunt, fov, aware, health })` (`hunt`, a 60-degree
  cone where D-Day's is 30 (100 while on edge, `alertFov`), an undrawn 170 px all-round awareness, walls
  still hiding you, and 60 health where D-Day's have 40): a soldier closes in on whoever
  he can see, searches where he lost them, goes looking when shot from
  out of sight, and `Troops:alarm` sends everyone within 700 px of a
  soldier going down to look; each walks back on a trail of breadcrumbs
  after (D-Day's hold their places). `Troops:navigate(bounds)` gives them
  a walking grid (`d-day/nav.lua`: 32 px cells, A*, the path cut down to
  corners in plain sight of each other) to find their way round walls to
  where they are going. `Troops:arm(s, { gun, burst, pause, reach })`
  hands one a gun (an AK otherwise): City 17 picks one per soldier by
  `Level.loadout`'s weights from every gun in `weapons/guns.lua`, common
  tier, and the gun's index goes out in `C17_TROOPS` so clients draw it in
  his hands. A-Man's theme plays through his quest, from the
  intro screen to the end, the way Karen's does. They talk over the
  radio (`a-man/radio.lua`: the lines, a synthesised burst of radio on the
  "combine" sound channel and a bubble): a checkpoint's guards or a squad
  now and then with a mate answering, a shout on spotting somebody, and a
  call when a soldier nearby goes down. Messages: `C17_TROOPS`, `C17_DOWN`
  and `C17_SAY` down.
- Events: `src/features/events` is something big happening in the city.
  One event at a time, only on the default city map and off a quest; a map
  change calls it off. When one starts every minimap flashes red where the
  boss came in (`drawOnMinimap`), a banner says what is going on, a red
  mark and an arrow at the screen's edge follow him, and the police and
  bots go passive (`serverEventActive`: lights on, nobody wanted, no
  fights) until he is beaten. For now the host starts one
  from the F8 menu (`event-menu` in Controls: a number key or a click picks
  an event, and the menu can call off the one that is on) or any feature with
  `events:serverTrigger(server, key)`, which returns false and a reason
  ("busy", "away", "nowhere") when it can't. Each kind of event is a module
  in that folder listed in `Events.kinds` (the header of `events/init.lua`
  says what one has); the first is Bigfoot (`events/bigfoot.lua`): he comes
  in on a road away from everyone and goes for the nearest player, or the
  nearest building a player owns (`buildings:serverStanding()`) when nobody
  is near, swiping, leaping onto players and over blocks he is stuck
  behind. He brings litters of fifteen squirrels that wait a moment and then
  shoot at the nearest player or building, bursting into gibs on it for a
  little damage (shot, they burst too); once a whole litter is gone he roars
  up another. Down, he spills koins and drops his leap, "ability-bigleap",
  as a pickup. He is drawn with the alien hunt's pictures
  (`alien-hunt/render.lua`). Messages: `EVT_TRIGGER` up; `EVT_START`,
  `EVT_END`, `EVT_NO` and Bigfoot's `EBF_*` down. Tuning is at the top of
  `bigfoot.lua`. The second is the Runner (`events/runner.lua`): he comes
  in at a crossing away from everyone and sprints the street grid (bots'
  traffic graph) at three times a player's sprint, a lane at random on
  each street, targeting nobody. Any car he runs into is wrecked, any
  pedestrian gibbed, and a player on foot in his way trampled (30, once a
  second at most). He has breath for about half a minute and then walks
  it off for a few seconds. Down, he spills koins and drops
  "ability-secondwind" in a tier rolled from `dropTiers` (50% common, 30%
  uncommon, 17% rare, 3% legendary). Messages: `EVT_STOP` up (the menu
  calling one off); the Runner's `ERN_*` down. The third is the Tripod
  (`events/tripod.lua`, drawn and voiced by `src/features/tripod`). It
  starts as a storm: for 8 s the sky goes dark and lightning comes down
  round every player (each bolt marked on the ground for 0.7 s first, a
  third of them right on a player), 35 to anyone on foot and 45 to a car
  within 50 px, pedestrians too. In the last second the bolts hammer a
  crossing away from everyone and a war machine on three legs rises there,
  sounds its horn and strides the street grid leaving red weed. With a
  player within 900 px it steps straight over the city to stand off 240 px
  from them. Its heat ray warms up on the nearest player in range for 2 s,
  a ring closing on them, then locks where they were for the last 0.35 s
  ("DODGE!") and burns that spot for 1.4 s: 120 a second on foot, 160 to a
  car, pedestrians burned up, and anyone it kills left as ash (bots on
  foot too). Every 8 s or so, with somebody (a player or a bot) out in
  front, it may sweep instead: it plants its legs, lights a red arc on the
  ground 260 px out and about 115 degrees wide for 1 s ("GET OFF THE RED
  LINE!"), then drags the beam across it in 1.8 s, burning everything in
  the band as it passes (about 120 on foot, 160 to a car, bots' cars too,
  and the pedestrians). A player on
  foot who gets under it is lashed at and, still there 0.7 s later,
  snatched into its cage: held still (`serverHeld` / `held`, passed on by
  the events feature), 20 a second, until it has taken 8% of its health
  since the grab or 7 s pass. Only its head can be shot; it has breath
  like any boss (striding after somebody spends it, the ray and a grab
  cost some). Down, it crashes (the tripod feature keeps the wreck and the
  ash for 90 s), spills koins and drops its heat ray, the ability
  "ability-heatray", in a tier rolled from `dropTiers` (45% common, 30% uncommon, 20% rare, 5%
  legendary). Messages: the Tripod's `ETR_STATE`, `ETR_ASH` and
  `ETR_DOWN` down, and the storm's `ETR_BOLT` and `ETR_RISE`. Tuning is at the top of `events/tripod.lua`. The
  fourth is A-Man, the one event that lives outside this folder: its
  module is `src/features/a-man/event.lua`, listed in `Events.kinds` like
  the rest, and the a-man feature loads his sounds and keeps the disguise
  he leaves on the ground (30 s) after the event is over. He is a
  player's size and walks (55 px/s) towards the nearest player he can
  see, humans before bots. Every 3 to 5 s, with the breath for it (a blink
  costs 45 of 100: two in a row, then a rest), he stops and a line shows
  for 0.8 s where he is going: within 600 px of his target straight
  through them and 220 px out past them, further off (up to 2600 px)
  across the map to land 240 px from them. Everyone on the line takes 60
  (abilities/teleport.lua's `Teleport.serverThrough`, players and bots on
  foot or at the wheel), and pedestrians and officers on it go down. A
  freeze holds his wind-up, a fart in his face throws it off. With a
  player within 900 px and 40 breath he opens his briefcase and a horde of
  sentry turrets (`a-man/turrets.lua`; 8 for one human, more with more)
  spills out round him: they scuttle about at random (110 px/s) and spray
  bursts of four rounds (6 each, weapons' `serverFireFrom` owned by
  nobody) in random directions, until one round knocks them over or 20 s
  pass. One horde at a time, the next 10 s after the last turret falls;
  the first 8 s after he arrives. Rounds owned by nobody don't hit him or
  his turrets, and neither does his own blink. His theme
  (`a-man/theme.lua`) plays while he is loose and his portrait
  (`a-man/face.lua`) sits beside his boss bar. Down, he spills koins and
  drops "ability-teleport" in a tier rolled from `dropTiers` (50% common,
  30% uncommon, 17% rare, 3% legendary), and every turret falls over.
  Messages: `EAM_STATE`, `EAM_BLINK`, `EAM_DOWN`, `EAM_HORDE`,
  `EAM_TURRETS` and `EAM_POP` down. Tuning is at the top of `event.lua`.
- Bosses: `src/features/bosses` is the standard every boss follows and the
  code that keeps them alike; its header spells the standard out. A boss
  has breath like a player on foot (`bosses/stamina.lua`): running spends
  it, anything else lets it come back after a pause, and empty it is
  winded: walking only, slower than a player walking away, with no
  ability (Karen's scream, a Bigfoot's leap, the Major's MG nest) until it
  holds a lungful again. Melee and guns cost nothing. On the host
  `Stamina.new(tuning)`, `st:step(running, dt)` every tick, `st:pace(run,
  walk)` for the speed, `st:has(cost)` before an ability and
  `st:spend(cost)` when it goes; the boss's state message ends with
  `<stamina> <winded>` (`st:wire()`, `Stamina.read(args, i)`). Every boss
  bar is `bosses/bar.lua`'s `Bar.draw(spec)`: the name over the health,
  and the breath as a thin bar under it that throbs red with "winded"
  while it is blown. Breath tuning sits with the rest at the top of the
  boss's file (`drain`, `regen`, `recovered`, `breath`, what an ability
  costs). A boss scales with the humans in the game: its health is
  `Bosses.health(base, server)` and its helpers (simps, squirrels,
  soldiers, a litter) `Bosses.count(base, server)`, the numbers for one
  human grown by `Bosses.perHuman` of the base for each human past the
  first (two humans, double), counted when it spawns.
- Leap variants: `abilities/leap.lua`'s `Leap.variant(tuning)` is another
  leap on the same flying and landing with its own key and numbers
  (`walls` cracks buildings under the landing, `shake` rocks the view near
  it). Bigfoot's leap (`abilities/bigleap.lua`) is one: further, wider,
  harder. An ability with `unsold = true` is left off the shop's shelf.
- Teleport: `abilities/teleport.lua` (A-Man's drop, never sold, on foot,
  `aim = "point"`) puts its caster up to 700 px away in one go, through
  walls but never into one (`Teleport.clear` pulls the spot back). Every
  other player within 14 px of the line takes 50, and the soft targets
  along it are hit through `serverShotAt`, a boss once. A-Man's own blinks
  use the same line (`Teleport.serverThrough`) and tear
  (`Teleport.drawTear`). Tiers: cooldown (14 s), then range, then damage.
- Abilities on the ground: `pickups:serverDrop(server, "ability-<key>", x,
  y)` leaves an ability lying loose, an orb in its colour; the first human
  over it with room in their bag carries it off as the item.
- Shop: `src/features/shop` is a building in the same block as the Jobs
  building (`quests/jobs.lua` picks both from the map; `shop:here()` gives
  it while the default city is in play) and sells everything in one place.
  It is marked on the minimap with a green bag. Stand or stop on the square
  by its door and a prompt offers the shop on the action key (F; the shop
  answers `actionTaken` there and while it is open); it opens and closes
  the shop screen, and walking away from the door closes it too. The screen
  draws over every other HUD piece (priority 993), under only the inventory.
  On sale: every gun and a box of its rounds, every ability, a medkit and an
  energy drink (the Supplies tab), armor and clothes (the Gear tab) and every car model, built into `shop/catalog.lua` from the other features'
  lists, so a new gun or model is on the shelf by itself. A click on a card
  shows it in a side panel on the right (`shop/details.lua`): a bigger
  picture, its `blurb`, how it is used and its numbers in the tier on show,
  those the tier improves in the tier's colour. Give a new gun, ability,
  armor or piece of clothing a one-sentence `blurb` for it. The panel's Buy
  button buys it: an item goes into the buyer's bag through
  `buildings:serverGive`, a car onto the road outside the door through
  `serverDeliver` (vehicles answers), in the first delivery bay with no
  car in it. Prices live in the catalog (`PRICES`, a default per kind; a
  car is its factory price times `CAR_MARKUP`) and the host charges them
  through `money:spend`. Equipment is sold in every tier, picked on a row
  of tier buttons under the tabs; a better tier costs more (its `price`
  multiplier in `tiers/init.lua`: x2.5, x6, x15, `Catalog.price`). The dev
  shop is the same screen with everything free, for trying things out: the
  `itisminenow` cheat turns it on and off for whoever typed it
  (`shop:serverSetDev(server, player, on)`, `SHOP_DEV <0|1>` to them).
  The Hire tab sells people (delivery's `hire.lua` lists them): an entry
  with `onRoad = true` is handed to `serverDeliver` like a car rather than
  put into a bag, and may bring its own card picture (`icon`), side-panel
  text (`details`) and line once bought (`bought`).
  Messages: `SHOP_BUY <item>[@<tier>]`, `SHOP_OK <item>[@<tier>] <n>`, `SHOP_NO <reason>`, `SHOP_DEV <0|1>`.
- Delivery: `src/features/delivery` is the drivers a player hires at the
  shop (the Hire tab, 50 Fcks, up to three each). A driver is an NPC
  (`civilian`) in the refrigerated box truck with their employer's name over
  it, driving by the traffic rules and finding its way with `route.lua`. It
  collects what its employer's quarries and oil wells made, as much as their
  factories need for the product each is making (its recipe, not every
  material its hopper holds) less what the employer's other drivers already
  carry, up to two stacks, fetching what the factories are shortest of
  first. It pulls up at each building's square to load and unload, and
  fills the nearest factory that needs the load: the hopper first, then the
  factory's yard (50 materials past the hopper, an even share per material
  the product needs, fed into the hopper as the factory works, lost with
  the factory), then on to the next factory with whatever is left. A load
  no factory needs any more (a product was switched) is left at any factory
  whose hopper holds it. A factory draws the hoppers its product doesn't
  use faded. With nothing to fetch, a driver collects the goods of the
  employer's factories set to sell to the shop (`toShop`, once they are
  worth `Delivery.minSale` or the factory is full), drives them to the
  shop's door and sells them there: the employer is paid `Kinds.worth` for
  each and hears what went (`DLV_SOLD`). Wrecked, the truck spills its
  load as crates (goods too; `pickups` takes any item with a worth) and the driver is gone. Drivers leave with their employer
  and come back with them (player file); yards are kept in the saved world.
  The load shows under each truck, and the employer sees what each driver
  is doing and their trucks on the minimap. Messages: `DLV_UNIT`,
  `DLV_GONE`, `DLV_YARD`, `DLV_LOST`, `DLV_SOLD`, `DLV_NO` down. Tuning is at the top of
  `hire.lua` and `init.lua`.
- A growing city: `city:grow(bi, bj)` adds a block past the city limits and
  `city:growthSites()` lists where one may go. The map can stop being a
  rectangle, so read its bounds from `map.c0 c1 r0 r1` (tiles) or
  `map.left top w h` (world px), treat a missing `map.tiles[c][r]` as outside,
  and redraw anything built from the map when `map.version` changes. `city.map`
  is replaced between games, so read it when you need it rather than keeping
  it. Real-estate sells the blocks and tells every client to grow the same way.
- `car.hidden`: set on a server car to keep it out of `STATE` (weapons does
  this for wrecks). The core respects it; other features should skip hidden
  cars too. `car.kept` on top of it means a feature is keeping that car off
  the road for its owner (the garage: parked, wrecked or impounded): weapons
  never moves or unhides it and city-map doesn't seat its owner in it.
- Garage: `src/features/garage` keeps players' cars. A garage is a building
  (kind `"garage"` in `buildings/kinds.lua`, with `service = "garage"`: a kind
  another feature runs makes nothing, and buildings asks that feature for its
  menu rows, info lines and drawing: `buildingRows(client, plot, b, row)`,
  `buildingInfo(client, plot, b)`, `drawBuilding(b, kind, r, time)`;
  `buildings:ofKind(kind, owner)` lists a player's buildings of a kind, on
  either side). Each holds six cars, parked from its square and taken out
  from the vehicles screen (G), which lists every car you own with its
  health: tow it home, repair it, take it out, collect it. In the city a
  person's wrecked car no longer comes back by itself: with a garage it waits
  destroyed for a tow, without one it goes to the impound lot, whole, to be
  collected for koins. A dead player comes back at their garage or, with
  none, the hospital. The hospital and impound lot are buildings the city
  already had, picked from the map the same way everywhere (`garage/places.lua`).
  Prices are at the top of `garage/init.lua`. Messages: `GAR_PARK`,
  `GAR_TAKE`, `GAR_TOW`, `GAR_REPAIR`, `GAR_COLLECT` up; `GAR_KEPT`,
  `GAR_FREE`, `GAR_OK`, `GAR_NO` down. `weapons:serverCarHealth(car)` /
  `serverSetCarHealth(server, car, hp)` read and set a car's hit points even
  while it is hidden.
- `Features.byName.<name>` is the escape hatch when a feature genuinely
  needs another (the city map pushes pedestrians out of buildings through
  `Features.byName.pedestrians.crowd`). Check for nil: the other feature
  may have been deleted.

## When the hooks aren't enough

Add a hook to the core rather than reaching into it from a feature. Keep the
core change to a few lines, document the new hook here and in `_template`,
and mention it in the pull request so others can use it.

## Changelog and versioning

`CHANGELOG.md` at the repository root is what players read: the icon in the
bottom-left corner of the main menu opens it, and a dot on that icon means
the version changed since they last looked. It is also the only place the
version lives; `src/version.lua` reads it, so there is nothing else to bump.

Every pull request into `staging` that a player would notice adds lines
under `## [Unreleased]`, in `### Added`, `### Changed` or `### Fixed`
(create the heading if it is missing):
- One line per change a player would notice, not one per pull request: a
  pull request that adds a gun and fixes a reload bug adds two lines.
- Write it for players, not for the code: "Cars can be repainted at the
  garage", not "garage: PAINT message".
- Balance changes give the numbers, old to new: "Shotgun damage 40 -> 32",
  "Gym dodge distance costs 3/5/8/11/14 Fcks (was 4/6/9/12/15)".
- Wrap long lines with a two-space indent. Pure refactors and docs need no
  line. In the game the unreleased lines show as "Coming next" and the
version reads `0.1.0-dev`, so a staging build is easy to tell apart.

A release is `staging` merged into `main`. In the same merge, rename
`[Unreleased]` to `## [x.y.z] - YYYY-MM-DD`, write a sentence or two under
that heading saying what the release is about (the game shows it above the
list), put a fresh empty `## [Unreleased]` above it, and tag the merge
commit `vx.y.z`. The number
follows semantic versioning, read for a game that is not finished yet
(`0.y.z`):
- `y` (minor) for a release with anything new in it: features, content,
  balance changes. Most releases.
- `z` (patch) for a release that only fixes things.
- `1.0.0` when we call the game released; after that `x` goes up when
  saved worlds or LAN play stop working with the previous version.
