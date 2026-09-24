# Persistence design

Saved worlds: the host can stop, come back later and **Continue**, and
everyone who played in that world gets their stuff back.

## Decisions

| Question | Decision |
| --- | --- |
| Who keeps the save? | **The host.** A world is a folder on the host's machine. Clients save nothing that matters. If the host is away, nobody plays that world (a headless dedicated server may come later). |
| Where does a character live? | **In the world.** Your money, loadout and upgrades belong to that host's world, not to you. Carrying a character between servers would mean trusting client files, which breaks "never trust a client". |
| Can people join a running game? | **Yes, required.** A returning player is useless if they can only join from the lobby. This is milestone 3 in `networking.md`. |
| What happens to an offline player's stuff? | **It stays.** Their cars stay parked where they left them, their houses and buildings stay theirs. Same rules apply as when they are online. |
| How does the host pick a world? | **New world / Continue** when hosting. |

## Identity: player keys, stable ids

Today `player.id` is a counter that restarts every session, and the name is
free text anyone can type. Neither survives a restart.

- **Player key.** On first run a client makes a random 32-hex-char key and
  stores it in settings (`player.key`). It is sent in `HELLO`:
  `HELLO <name> <key>`. The server accepts only `[0-9a-f]` of that length;
  anything else gets a throwaway key for the session.
- **Stable ids per world.** The world save keeps `ids = { [key] = id }` and
  `nextId`. A known key gets its old `player.id` back; a new key gets the next
  one. So `player.id` means the same person for the whole life of a world.
- Because ids are stable, every feature that keys state by `player.id`
  (`sv.levels[player.id]`, `sv.owners[plot] = player.id`, ...) keeps working
  unchanged, including for players who are offline. No feature has to move to
  keys. Bots keep taking ids from `server.nextId`; they are never saved, so
  their ids are simply burnt.
- **Same key twice.** Two game copies on one machine share a save directory
  and so a key (normal while testing). If a key is already connected, the
  newcomer plays under a throwaway key and is not saved.
- **Names.** The latest name a key used is stored with it. Clients only know
  online players, so showing "owned by Christiaan" for an offline owner needs
  a way to send names of known-but-offline players (a `KNOWN <id> <name>`
  message on join). Small, but needed.
- Not secure: copying someone's settings file lets you play as them. Fine for
  LAN.

Cars get the same treatment: a saved car is restored with **its old vehicle
id**, and the server's vehicle counter starts past the highest saved one, so
per-car feature state (`vehicles`' model per car id) also survives as is.

## Save layout

```
saves/<world-slug>/
  meta.lua              name, created, lastPlayed, format version, player names (for the Continue list)
  world.lua             ids, nextId, cars, and one slice per feature
  world.lua.bak         the previous world.lua
  players/<key>.lua     name, position, and one slice per feature
  players/<key>.lua.bak
```

- Files are Lua tables written by the serializer from `src/settings.lua`
  (moved to a shared `src/serialize.lua`).
- **Loading is sandboxed:** `love.filesystem.load` then `setfenv(chunk, {})`,
  called with `pcall`. People will pass world folders around; a save file must
  not be able to run code.
- **Crash safety:** before writing a file, its current version is copied to
  `.bak`. If the main file fails to load, the `.bak` is used and the host is
  told.
- Each feature's slice is stored under its folder name
  (`world.lua` → `features["real-estate"]`). A missing slice means "fresh",
  so a new feature works with old saves. Each slice carries its own
  `version = n` so the feature can upgrade its own old data. The save format
  itself has a `format` number in `meta.lua`.

## Feature hooks

Four new optional hooks, all server side:

| Hook | Called |
| --- | --- |
| `serverSaveWorld(server)` → table or nil | Every save. Return the world part this feature owns. |
| `serverLoadWorld(server, data)` | Continuing a world, right after `serverStart`, with this feature's slice. |
| `serverSavePlayer(server, player)` → table or nil | Every save, and when that player leaves. Their personal part. |
| `serverLoadPlayer(server, player, data)` | A known player is back, after their body exists. |

Order when a game starts (from the lobby):
`spawnPlayers` → `serverStart` → `serverLoadWorld` → `serverLoadPlayer` (each
known player) → `START`.

Order when someone joins a running game:
body and car → `serverLoadPlayer` (if known) → `serverPlayerJoined`, so a
feature sending its state to the newcomer in `serverPlayerJoined` sends the
loaded state.

Rules for features:
- Save **facts**, not things you can work out. Save the upgrade level, not the
  max health it gives; `serverLoadPlayer` reapplies it.
- Save nothing about ongoing action: bullets, cooldowns, timers, stamina.
- Only the server saves. Clients never read or write a save.

`src/features/init.lua` needs a call variant that passes each feature's name
along and collects return values. `_template` and `features.md` get the new
hooks.

## What gets saved

| Owner | Kept |
| --- | --- |
| Core (world) | `ids`, `nextId`, vehicle counter, every owned car: id, x, y, angle, owner |
| Core (player) | name, last position |
| `money` | wallet (player) |
| `upgrades` | levels (player) |
| `weapons` | guns in slots, ammo (player). Health comes back full. |
| `armor`, `gear` | what is worn (player) |
| `abilities` | slotted abilities (player) |
| `buildings` | buildings on plots (world); carried stock and quick slots (player) |
| `real-estate` | plot owners (world) |
| `vehicles` | model per car id (world) |

**Not saved:** pedestrians, police and wanted level, bots, projectiles, coins
lying on the ground, pickups, skidmarks, quest progress (`quests`, `d-day`,
`alien-hunt`). Unowned parked cars respawn as the map does today.

## Save and load moments

- **Player leaves:** their player file is written.
- **Autosave** every 5 minutes (host setting in `server_settings`).
- **Host quits** the game or the app (`love.quit`): everything is written.
- **Quests:** on a quest map the world is not the city, so world autosaves
  pause until everyone is back; player files are still written. A world is
  always continued in the city.
- **Loading a player:** returning players appear on foot where they last
  were. A player new to this world gets a starter car as today; a known player
  does not (their cars are where they parked them).

## Changes to existing behaviour

- `Server:onHello` stops turning people away with "game already started".
- `Server:onDisconnect` no longer removes the player's own car; it stays
  parked, still theirs.
- **Open issue:** a quest swaps the map and real-estate's `mapChanged` clears
  every owner, and buildings clear every building. With saves this would
  throw away property for good. Before real-estate and buildings save their
  state, the city's owners and buildings need to be put back when everyone
  returns from a quest (keep them aside instead of clearing).

## Host flow

Host → **New world** (type a name) or **Continue** (list from `saves/`,
showing name, last played and who has played) → lobby as today → Start.
Players joining later go straight into the running game.

## Plan (one PR each, into `staging`)

1. `feature/player-key`: client makes and stores a key, sends it in `HELLO`,
   server keeps it on `player.key`. No behaviour change.
2. `feature/join-running-game`: accept `HELLO` after start: spawn, send the
   roster, every car (`VEHICLE`), `START`; audit each feature's
   `serverPlayerJoined` so a latecomer gets its state (real-estate and bots
   already handle this). Own cars stay when their owner leaves. Also
   `KNOWN` for offline owners' names.
3. `feature/world-saves`: `src/serialize.lua`, save module, the four hooks,
   stable player and vehicle ids, core slices, autosave, `.bak`, sandboxed
   load, New world / Continue screens.
4. `bug/quest-keeps-property`: owners and buildings survive a quest trip.
5. One small PR per feature slice (`feature/save-money-upgrades`,
   `feature/save-loadout`, `feature/save-property`, `feature/save-vehicles`).
   These touch only their own feature folder, so they can be done in parallel.

1 and 2 can be done at the same time; 3 needs 1; 5 needs 3 (and 4 for
property).
