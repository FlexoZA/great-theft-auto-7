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

| `mousepressed(x, y, button, client)` | Mouse press in the game. |
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
| `serverPlayerJoined(server, player)` / `serverPlayerLeft(server, player)` | Roster changes. |
| `serverMessages = { KIND = function(server, player, args) end }` | A message from a client the core doesn't know. `player` is the verified sender. |

Useful server fields: `server.players[id]` (`id name peer input body vehicle
car`), `server.vehicles[vid]`, `server.tick`, `server:broadcast(msg,
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
of centred text; `Abilities:hudTop()` is where the row starts, weapons
puts the magazine count just above it). The minimap sits top right and the koin bottom right,
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
first feature whose hook returns true. Events in use:

| Event | Raised by | Meaning |
| --- | --- | --- |
| `serverPlayerDamaged(server, victim, attacker, amount)` | weapons | A projectile hit. `attacker` may be nil if they left. |
| `serverCarsCollided(server, rammer, rammed, closingSpeed)` | car-collisions | Two cars touched while closing. `rammer` was moving into the other faster. |
| `serverShotFired(server, player, x, y)` | weapons | A projectile left a gun at (x, y). `player` is nil for a shot nobody owns (a police officer on foot). |
| `serverWallHit(server, x, y, damage, by)` | weapons | A round stopped at a wall (a `blocksPoint`) at (x, y), carrying `damage`. `by` is the shooter's id, 0 for nobody. Buildings takes the damage when the wall is one of its own. |
| `serverBlast(server, x, y, radius, damage, by)` | weapons | A missile went off at (x, y): `damage` at the centre, falling to a third at `radius`. Players, cars and soft targets are already handled; buildings hurts every building it reaches. |
| `serverKill(server, { kind, x, y, by, victim })` | weapons, pedestrians, police | Something died: kind is "car", "pedestrian" or "police", `by` the killer's id. |
| `mapChanged(map, server)` | city-map | The game moved to another map mid-game (`city:switchTo`). Raised once per machine; `server` is set on the host and nil on a client. Every car already stands on the new map's spawn points. Drop or move anything you keep in world coordinates: weapons moves its respawn slots, on-foot puts walkers back in their cars, real-estate forgets the old plots. |
| `serverQuestStarted(server, quest, player)` / `serverQuestEnded(server, quest)` | quests | A quest began (everyone is already on its map) or the group took the star home. `quest.boss` names the feature that owns the fight; karen spawns herself on the first and leaves on the second, alien-hunt starts the wild man's walk. |
| `questStarted(client, quest, byId)` / `questEnded(client, quest)` | quests | The same on every machine, after the map switched. Karen puts up her title screen and starts her theme here. |
| `serverFreezeArea(server, x, y, radius, seconds, by)` | abilities | A freeze landed on (x, y): whatever a feature owns inside `radius` should stand still for `seconds`. Abilities holds players and cars itself; pedestrians, police officers and Karen root their own. `by` is the caster's id. |
| `serverDeliver(server, player, item, x, y, angle)` | buildings asks | A building handed over a product nobody carries (a `"car-<model>"`). Put it into the world at (x, y) for `player` and answer true; vehicles spawns the car. |
| `menuOpen(client)` | weapons asks | Answer true while a menu of yours has the number keys, and weapons leaves the gun alone. The upgrade shop, the building menu and the inventory screen answer it. |
| `actionTaken(client)` | on-foot asks | Answer true while the action key (F) is yours: a prompt of yours is up for it. On-foot then leaves getting in or out of a car alone. Real-estate answers it on a plot for sale, buildings on an owned plot's square, the shop on its bag. |
| `fireTaken(client)` | weapons asks | Answer true while the fire button is yours: weapons then neither fires nor clicks on it. Abilities answers it while a direction ability (the MG nest) is selected, and until the button is let go after placing one. |
| `pointerTaken(client)` | weapons, abilities, vision ask | Answer true while a screen of yours owns the mouse: weapons doesn't fire, abilities don't aim (an aim in progress is dropped), vision stops edge-panning and leaves the cursor to you: call `Features.byName.vision:drawCursor(client)` at the end of your `drawHUD` and it draws an arrow there, on top of your panel. The inventory screen and the shop answer it. |

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

- `src/server_settings.lua`: choices the host makes for the game they run
  (bot difficulty today), set on the Settings screen's Server tab and saved
  with the other settings. Read them on the host, live, and never send them
  to clients: bots read the difficulty every time they shoot.
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
  with `x, y` where it died, not where a wreck respawns. Kind "car" is
  weapons' kind for a player: a wrecked car (`victim` is its driver, nil
  for a parked one) or a player killed on foot (`onFoot = true`). Money
  drops koins there: a pedestrian is worth a fresh koin and an officer on
  foot three, while a wrecked car spills up to five out of `victim`'s own
  wallet and nothing at all if it was empty, so fill in `victim` for
  anything a player was driving. Ignore kinds you don't care about; new
  kinds may appear.
- `feature:serverShotAt(server, x, y, radius, by, angle)`: a bullet is
  passing through this point on the host. Kill whatever of your own is
  standing within `radius` of it and return true, and the shot stops there;
  return false and it flies on. Weapons walks its projectiles through every
  feature that defines it, so a gun kills pedestrians without knowing they
  exist (police answers it too: officers on foot take a few rounds before
  they go down). `by` is the shooter's player id and `angle` the direction of
  travel, for gibs and scoring; `by` is 0 for a shot no player fired. Cars
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
- `Features.byName.money:wallet(id)` / `money:spend(server, id, amount, label)`:
  read a wallet on the host, or take koins out of it all-or-nothing (false
  and a reason, and nothing happens, when they can't cover it). Every sale
  goes through `spend`; see "Selling things for Fcks" below.
- `Features.byName.money:serverSetReach(server, player, scale)`: how far a
  player's koins jump to them, as a multiple of the base radius; money
  broadcasts `FCK_REACH` and draws the ring. Upgrades sells it.
- Ammo: guns fire from a magazine (`magazine`, `reload` in `weapons/guns.lua`)
  and reload from the player's inventory, `"ammo-<gun key>"`, through
  `buildings:serverCount(id, item)` and `buildings:serverTake(server, player,
  item, n)`. `weapons:serverFire` counts rounds for human players only; a
  player with `bot = true` (bots, police) and `serverFireFrom` never run dry.
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
  ability by `key`; each player carries them in `abilities.slotCount` slots
  (Q, E, R, and a keyless passive slot for an ability with `passive = true`,
  which only fits there), freeze in slot 1 to start with, kept on the host and told to
  the player (`ABL_SLOTS`, a key per slot, `-` for empty). An ability in a
  bag is the item `"ability-<key>"`; `ABL_EQUIP <key> <slot>`,
  `ABL_UNEQUIP <slot>` and `ABL_MOVE <slot> <slot>` move them, and a cast
  (`ABL_CAST <key> ...`) is refused unless the ability is in one of the
  caster's slots. Cooldowns follow the ability, not the slot. The shop
  sells ability items. A passive ability (`regen.lua`: once the body has
  gone a few seconds unhurt it heals fast for three seconds, then rests
  through a cooldown) has no cast; abilities calls its `serverTick(server,
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
  walls) and `ABL_FIRED` carries them, `drawAim(ox, oy, x, y, time)` draws the arrow while it is
  selected, and an ability's `serverStep(server, dt, abilities)` runs
  whatever it left standing in the world (the nest sprays AK-47 rounds,
  owned by its placer, across its forty-five-degree arc for five
  seconds, sweeping side to side and picking no targets: the rounds hurt
  whatever they meet; `serverReset()` clears them between games). One
  with `aim = "self"` (`heal.lua`) is cast where the caster stands by a
  press of its key: a circle that follows them for a few seconds and
  heals every player inside it through `weapons:serverHeal`. Effects carry
  `by`, the caster, and `drawEffect(e, client)` gets the client to follow
  them.
  A gun with a `blast` (the rocket launcher) fires a missile that explodes
  on whatever stops it, or in mid-air when its `ttl` runs out, hurting every
  player and car in the radius, the shooter included (`WPN_BOOM` draws it).
  A gun's `stock` is how many rounds each human player starts the game with.
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
- `Features.byName.pickups:serverDrop(server, kind, x, y, amount)`: leave a
  pickup on the ground right there, gone for good once taken. `kind` is a
  pickups kind ("health", "stamina") or `"ammo-<gun key>"` for a box of
  `amount` rounds that goes into the taker's inventory. Police drops pistol
  rounds where an officer falls or a unit is wrecked.
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
example with a menu; real-estate is the one with a place to stand.
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
  (`"iron"`, `"ammo-uzi"`, `"gun-uzi"`, `"ability-freeze"`, `"medkit"`, `"drink"`), in slots of one stack
  each; `buildings:serverSetSlots(server, player, n)` changes how many a
  player has (upgrades sells them). Weapons reloads from the ammo in it and
  moves guns in and out of it as items. Buildings have hit points (`hp` in
  `kinds.lua`) and take damage through `serverWallHit` and `serverBlast`; a
  destroyed one is a ruin (not solid, makes nothing) until its owner pays to
  rebuild it, or anyone else pays `buildings.takeoverPrice` to take the lot
  over empty. A building still standing can't be taken over.
- Car tags: `src/features/car-tags` writes the owner's name over a parked
  car, the way the core writes the driver's over a moving one, so you know
  whose car you are borrowing and can spot your own. Player-arrows marks the
  window's edge towards other players (a walker), police (an arrow) and your
  own cars (a car) while they are off screen; civilian bots are left out
  (bots tells clients who they are with `BOT_UNIT`).
- Inventory: `src/features/inventory` is the screen (I) that shows what you
  carry around a picture of you: gear slots (empty for now), a weapon slot
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
- Several maps: `city.maps` names every map the game can play on (each a
  seed and size for the same generator, plus a title; `kind = "culdesac"`
  builds a suburban dead end instead of a grid, with `map.circleX, circleY`
  at its turning circle; `kind = "forest"` is trees and shrubs round a dirt
  trail, with `map.trail`, `map.waypoints` (its clearings) and `map.lair`)
  and `city.current` is
  the one in play; every game starts on `city.DEFAULT`. `city:switchTo(name,
  server)` moves the game to another one: on the host pass the server and
  every car lands on the new map's spawn points, then `mapChanged` reaches
  every feature. The feature that switches tells every client to call
  `switchTo` too (quests sends `QST_MAP`), the same way real-estate tells
  them to grow. Add a map to `city.maps` and it can be reached by name. A
  spec with `crowd = false` has no pedestrians or officers on foot
  (pedestrians and police read `map.crowd`), one with `traffic = false` has
  every NPC car parked out of sight while it is in play (bots reads
  `map.traffic`), and one with `vehicles = false` is walked: on-foot turns
  everyone out beside their car and refuses to let them back in (Karen's
  street). Pickups are scattered afresh and koins on the ground swept on
  every switch.
- Quests: a map may carry several stars (`quests.list`, each with its own
  `onMap`); the nearest one is on offer.
  `Features.byName.quests:serverComplete(server, questId)` marks the
  job under way as done (everyone hears `QST_DONE`); `quests:serverActive()`
  is the quest in play on the host. Karen calls the first when she goes down.
- Shop: `src/features/shop` puts a shopping bag on the road (`shop.list`,
  one per map; the city's is on the first north-south road east of the
  middle) and sells everything in one place. Stand or stop on the bag and
  a prompt offers the shop on the action key (F; the shop answers
  `actionTaken` there and while it is open); it opens and closes the shop
  screen, and walking off the bag closes it too. On sale: every gun and a box of its rounds, every ability, a medkit and
  every car model, built into `shop/catalog.lua` from the other features'
  lists, so a new gun or model is on the shelf by itself. A click on a card
  buys it: an item goes into the buyer's bag through
  `buildings:serverGive`, a car onto the road beside the bag through
  `serverDeliver` (vehicles answers), in the first delivery bay with no
  car in it. Everything is free for now: prices live in the catalog and
  the host pays them through `money:spend` when they are above zero.
  Messages: `SHOP_BUY <item>`, `SHOP_OK <item> <n>`, `SHOP_NO <reason>`.
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
