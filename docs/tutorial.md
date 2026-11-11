# Tutorial design: Shoeman's school of survival

The first job on a new world's board: five levels chained by each quest's
`next`, led by a new boss, Shoeman, who teaches the basics (moving and
stamina, dodging, shooting, abilities, building) and hands over the
player's first pistol and first ability. Built in small stages over
several sessions; this file is both the design and the progress tracker.

## How to work from this file

The tutorial is built one tick box at a time, with the conversation
cleared between boxes, so no session ever needs to remember the one
before. This file is the only memory: whatever the next session needs to
know must be written here before stopping.

Every stage under "Stages" is one branch and one pull request into
`staging`, with a tick list. One session does **one tick box**:

1. Read "Status" and "Handoff notes" below, then the first stage with an
   open box. Check out that stage's branch (create it from `main` if it
   does not exist yet; later stages branch from the stage before while
   that one is not merged).
2. Do the first open box of that stage, and only that box. Read only the
   code that box needs; the "Systems" tables say where to look.
3. Verify it: `luacheck .`, and run or test what was built. When the box
   is the stage's last, also `make audit` and the `CHANGELOG.md` line.
4. Tick the box. Rewrite "Status". Put anything the next box needs to
   know in "Handoff notes" (what was built and where, function names,
   surprises, decisions made on the way), and remove notes that no longer
   matter. Add newly discovered work as new boxes in the right stage.
5. Commit the code and this file together on the stage's branch.
6. **Stop.** Say which box is next. Do not start it in the same session,
   even a small one, unless the user asks.

Clear the context only when it is needed, not after every box. Since every
box leaves its notes here, clearing never loses anything, but it costs a
re-read. Keep going in the same session while it is small; clear before a
box that needs a lot of new reading (a big file, another feature), or when
the session has grown long.

When it is time to clear, end with a ready-to-paste message for the user
to send after `/clear`, naming the file, the branch and the box, e.g.:

> Read docs/tutorial.md and continue with stage 1, box 3 (four placeholder
> maps) on `feature/tutorial-skeleton`.

If a box turns out too big for one session, split it into smaller boxes
here first, then do the first of them.

Status: stage 0 done on `feature/tutorial-shoeman-plan` (not merged yet).
Stage 1 done on `feature/tutorial-skeleton`, branched from stage 0 (not
pushed or merged yet): five placeholder levels, each finished by walking
to its way on, first on a new world's board, Karen opening after it, old
worlds counting it as finished. Stage 2 done on
`feature/tutorial-shoeman`, branched from `feature/tutorial-skeleton` (not
pushed or merged yet): the portrait, his body standing on every level,
the comms with the opening speech, the objectives tick list and the
checkpoints. Stage 3 done on `feature/tutorial-start-gear`, branched from
`feature/tutorial-shoeman` (not pushed or merged yet): new players start
with no gun and no ability; existing saved players keep their pistol and
freeze; a newcomer to a world past the tutorial is handed the pistol and
openborders; nothing fires or crashes with empty slots; a body with empty
hands is drawn without a gun on every screen. `make audit` 8.6, pass.
Stage 4 under way on `feature/tutorial-road`, branched from
`feature/tutorial-start-gear` (not pushed or merged yet): box 1 done,
Shoeman's Road built and drawn (four two-way streets, tunnel mouths, safe
strips, the school yard and the lawn), level 1's checkpoint, Shoeman,
HOME star and way on moved onto it. Box 2 done: `traffic.lua` runs every
lane during level 1, each with its own speed and gap. Next: stage 4, box 3
(no health bar on traffic cars).

### Handoff notes

Short notes from the last sessions for the next one. Keep it current, not
a history.

- Traffic (stage 4 box 2): `src/features/tutorial/traffic.lua`, host
  only. `Traffic.serverStep(server, map)` from init.lua's `serverStep`
  with `road()` (the city-map's map while `level.quest == "tutorial-1"`
  and it has `lanes`, else nil: then every traffic car goes).
  `Traffic.serverClear(server)` from `serverStart` and `mapChanged`.
  Cars are plain boxes from `server:spawnVehicle` (no owner, so never
  saved and never parked by `placePlayers`; no model, so the hitbox is
  what is drawn), flagged `car.traffic`. Every step each is put back on
  its lane (`y`, `angle`) at `setSpeed(speed)`, so friction, collisions
  and freeze change nothing; the core's `car:update` moves it. Past
  `toX` it is removed; a new one comes out at `fromX` once the last is a
  gap ahead. On start the lanes are filled end to end. Tuning:
  `Traffic.STREETS[street][lane] = { speed, gap = { min, max } }` (px/s,
  px nose to nose), 170 to 450 px/s, the centre lane faster.
  `Traffic.tune(lane)` reads it. A wrecked traffic car is claimed
  (`Tutorial:serverWreckClaimed` -> `Traffic.claim`, sets `car.gone`) and
  removed next step. For box 4: `Traffic.cars()` is car -> `{ lane,
  tune, cars }`; `CarCollisions:runOver` still deals its usual damage, the
  kill is box 4's. Checked in a scripted run: 35 cars at the start on all
  16 lanes, all on their line at speed on host and client, 99 seen and 66
  removed in 10 s, min gap 323 px, a wreck gone next step, all gone when
  the level ends.
- Shoeman's Road (stage 4 box 1): `city-map/tutorial_maps.lua` builds it
  (`kind = "tutorial-road"`, 24x44 tiles, `TutorialMaps.ROAD` holds the
  rows: lawn 6, streets 4 rows each with 3-row pavement strips between,
  the yard the rest; 2 columns of embankment each side), and
  `city-map/render_tutorial.lua` draws it. `TutorialMaps.builds(kind)` /
  `build` are wired into `layout.lua` and `render.lua` like Borderline's;
  the park, yard and town can be added to its `BUILDERS` table. For
  `traffic.lua`: `map.lanes` = { y, dir (1 east, -1 west), street (1
  bottom, slowest, to 4 top), lane (1 by the centre line, 2 by the kerb),
  angle, fromX, toX }, 16 lanes, drive on the right (south half east);
  `fromX`/`toX` are inside the tunnels (±736), out of sight. `map.streets`
  = { n, y0, y1 } (street 1 is y 320..576, 4 is -1024..-768). Checked in
  a scripted run: no lane end or middle is blocked, cars spawned at both
  ends sit still and unpushed. Read lanes from `Features.byName["city-map"].map`.
- The tunnels: `map.tunnels` roofs (grass and a concrete headwall with
  wing walls) are drawn over the cars by a new `Render.drawAbove`, called
  from `CityMap:drawAboveCars`. What other features draw over cars still
  shows: a car's health bar shows over the roof (box 2 may want traffic
  cars without one). Players can walk into a tunnel (its road tiles are
  open, under the roof); traffic kills them there anyway.
- Level 1's spots now come from the road (the numbers are copied, the
  map also leaves them as `map.cx, cy` (start, checkpoint: 0, 768),
  `map.shoemanX, Y` (160, 888), `map.homeX, Y` (0, 1008: quests'
  `home-tutorial-road`), `map.exitX, Y` (0, -1216: `Tutorial.EXITS`)).
  Change them together if `TutorialMaps.ROAD` changes. Box 5 ("Way on at
  the top") only needs checking: the WAY ON ring already shows on the lawn.
- Pickups (medkits, drinks, ammo crates) scatter on the streets too
  (`randomRoadPoint` takes any road tile). Funny bait; stage 11 may move
  them onto the pavement.

- No gun at the start (`weapons/init.lua`): `Weapons:startSlots()` holds
  only `stock` guns now (none have one), so a new human has four empty
  slots and empty hands: `st.gun` on the host and `Weapons.gun` on the
  client are nil. `fallbackGun(slots)` is the one rule both sides follow
  when the gun in hand is no longer carried: the pistol if in a slot, else
  the lowest slot's gun, else nil. `heldGun` uses it on the host (bots
  always fall back to the pistol, since `serverOwns` lets bots fire
  anything), `heldStats` returns the tuned gun or nil, and `serverFire`,
  `serverReload`, `serverSpin`, `serverCharge` and `serverStat` do
  nothing with empty hands; the client's `tryFire`, `tryReload`,
  `windBarrels`, `chargeShot` and `stat` likewise. Equipping a gun into
  empty hands puts it in hand on both sides with no WPN_SELECT. The host
  record is built by `freshPlayer` (serverStart and serverPlayerJoined).
  The magazine HUD already draws nothing for a nil gun.
- `serverLoadPlayer` no longer forces the pistol into a slot: saved slots
  come back as saved. Existing players keep their gear with no extra code:
  `main` forced the pistol into a slot on every load, so every save it
  wrote has one, and freeze is saved like any ability. Saved worlds
  (`ce9d8aa`) and saved loadouts (`fb99077`) reached `main` in the same
  merge, so no released player file lacks the weapons or abilities slice
  (a missing slice would skip `serverLoadPlayer` and leave them empty).
  Checked in scripted runs: a world created and saved by `main`'s code,
  then loaded twice by this branch's: pistol in slot 1 and in hand, freeze
  in slot 1, on host and client both times; on foot it fires (magazine 15
  to 14). A player who had put freeze down on `main` stays without it.
- No ability at the start (`abilities/init.lua`): `Abilities.startKeys`
  is `{}`, so `startSlots()` gives four empty slots on the host
  (`serverPlayerJoined`) and the client (`exitGame`). Empty slots were
  already a normal state (unequipping leaves one): keys 1 to 3 and the
  fire button do nothing, the HUD draws dim rings. Bots never cast, so
  nothing else changes. `serverLoadPlayer` restores saved slots as saved
  (it never forced freeze). Checked in a scripted run: new world, all
  four slots nil on both sides, keys pressed with no error; freeze given,
  equipped, saved, reloaded: slot 1 holds it.
- Start gear for newcomers: `src/features/tutorial/start_gear.lua`,
  wired from init.lua's `serverStart`, `serverPlayerJoined` (latecomers
  only, `server.started`), `serverPlayerLeft` and `serverStep`. A human
  is noted on arrival as new when `server.world:readPlayer(player.key)` is
  nil (also a guest, or no world: an unsaved session). The gift waits for
  the first step with them `Features.present` (after `serverLoadWorld`, so
  `quests:serverFinished(quests.TUTORIAL)` is right) and is decided once:
  tutorial finished -> `StartGear.give(server, player)`, else nothing.
  `give` puts the item in the bag and calls the normal `serverEquip`
  (pistol into the first empty weapon slot, openborders into ability slot
  1), skipping what they carry or a taken slot; a failed equip takes the
  item back out. Level 4 ("gives a pistol if the player has none") can
  call `StartGear.give` or copy its pistol half. Checked in scripted runs:
  a world marked finished with the player file deleted gives pistol (in
  hand, fires 15 to 14 on foot) and openborders on host and client; the
  next load (file saved, openborders put down) gives nothing again; a new
  world gives nothing. Not run with a real second client (the latecomer
  path is the same note and step).
- The pistol still can't be put down once carried (`serverUnequip`,
  `serverEquip` refusing to swap it out, the inventory's "stays with
  you"). The respawn still refills the pistol's magazine whether carried
  or not (harmless).
- Empty hands checked (box 5), no code needed: the inventory screen
  (`inventory/screen.lua`, empty slots read "empty", no gun on the
  figure), the magazine HUD (draws nothing), grenades' `lastGun` (nil is
  fine), `slotOf(slots, nil)` (pairs never yields an empty slot), the
  audit's arsenal (fires through `serverFireFrom`, never the held gun).
  Scripted run on a new world, in the car and on foot: fire held and
  clicked, R, Z, X, keys 1 to 4, scope, wheel, sprint, dodge, inventory
  open and shut, killed and respawned: `st.gun` and `Weapons.gun` stay
  nil, no projectile, no error. Bots all hold gun 1 (the pistol).
- Empty hands drawn (box 6): a new hook `emptyHanded(client, id)`,
  asked through `Features.any` by `Game:drawBodies`, which passes it to
  `Body.draw`'s new sixth argument (`emptyHanded`: `gun = false`). Two core
  files (`src/body.lua`, `src/states/game.lua`), 18 lines; call it out in
  the pull request. Weapons answers it: my own body from `Weapons.gun`,
  everyone else's from `Weapons.emptyHands[id]`, set by `WPN_HANDS <id>
  <0|1>`. The host's `Weapons:tellHands` (every `serverStep`) compares
  each human's `heldGun` against `sv.emptyHands` and broadcasts changes;
  a latecomer gets every 1 in `serverPlayerJoined`. Bots never show empty.
  The hook is in `_template` and the events table in `docs/features.md`.
  Checked in a scripted run: empty at start (host, client, hook all
  agree), uzi equipped -> armed, put down -> empty again; screenshots
  show the arms. Not run with a real second client. Shoeman's own body
  (`shoeman_render.lua`) is separate and unaffected.

- Shoeman's portrait: `src/features/tutorial/shoeman_face.lua`,
  `ShoemanFace.new()`, `face:update(dt)`, `face:draw(cx, cy, scale)`
  (centred; 64x72 canvas, `ShoemanFace.W/H`), same shape as
  `borderline/faces.lua`, so `comms.lua` can copy `borderline/hud.lua`
  `drawComms` (scale 1 there). Set `face.talking` while text types out and
  `face.shouting` for the "DODGE!!!!" (red face, vein, wide mouth, shake;
  wins over talking). He stands before a chalkboard with a chalk boot.
  Palette for the body to match: skin `0.93, 0.74, 0.62`, brows grey
  `0.70, 0.71, 0.72`, shirt navy `0.13, 0.17, 0.33`.
- Shoeman in the world: `src/features/tutorial/shoeman_render.lua`,
  `ShoemanRender.draw(x, y, angle, { swing, throw, alpha })`, drawn in
  `Body.person`'s style at `SCALE` 1.5 (`RADIUS` is his size in px). Not
  `Body.person` itself: he needs a bald head and a throwing arm. `throw`
  runs 0 to 1: arm back with a shoe in his fist until `WIND` (0.6), the
  shoe leaves his hand at `RELEASE` (0.68), follow-through to 1. nil is
  standing. `ShoemanRender.shoe(x, y, angle, scale, alpha)` draws the
  flying shoe (the same one he holds) for `shoe.lua`.
- Shoeman on the maps: `Tutorial.SHOEMAN[questId] = { x, y }` in init.lua
  (160 px east and 120 px south of each checkpoint, between it and the
  HOME star). Client only: `drawAboveCars` draws him there while the
  quest is active, and `update` turns him (`facing`, at most
  `Tutorial.turnRate` 4 rad/s) towards the nearest body in
  `client.bodies`. The host has no Shoeman yet: he is not solid (players
  walk through him), has no minimap dot, and never throws. `shoe.lua`
  (stage 5) should throw from `Tutorial.SHOEMAN` and send the throw so
  every screen plays the `throw` pose; the facing could then come from
  the host too. Stages 4 to 7 move him with their maps.
- Comms: `src/features/tutorial/story.lua` holds `Story.beats`, keyed
  `"<quest id>.<what>"`; a line is a string or `{ "TEXT", shout = true }`
  (red face, bigger red text, shorter hold), and `{sprint}` / `{dodge}` /
  any control name in a line becomes the player's key (`{move}` the four
  walking keys). Only `tutorial-1.start` (the opening speech plus the
  moving and stamina lesson) exists so far. `src/features/tutorial/comms.lua`:
  host side `Comms.serverStart(questId)` (from `serverQuestStarted`; says
  the "start" beat 1.5 s later), `Comms.serverStop()`,
  `Comms.serverBeat(server, what, again)` (once per level unless `again`),
  `Comms.serverStep(server, dt)`; message `TUT_SAY <key>`. Client side a
  queue (`Comms.queue`, `Comms.update`, `Comms.drawHUD` at (10, 250),
  `Comms.busy()`), cleared on a tutorial quest's start or end and on
  `exitGame`. init.lua wires all of it; later boxes only add beats to
  `story.lua` and call `Comms.serverBeat`. Level 1's lesson lines will
  want splitting into their own beats when stage 4 knows when the player
  first sprints.
- Objectives: `src/features/tutorial/objectives.lua`. Lists are data in
  `Objectives.lists[questId]`: a list of sections `{ title = "Resources"
  (optional), items = { { id, text, need = n, exit = true, timer = true } } }`.
  Only `tutorial-1` has one so far (`cross`, `exit = true`); each later
  stage adds its level's list there. Host: `serverStart(server, quest)` /
  `serverStop(server)` (wired in init.lua with Comms),
  `serverTick(server, id, n)` (counts only items of the section on screen;
  false if not counted), `serverTimer(server, id, seconds)` (level 2's
  "next in n s"; nil clears), `serverSection()` (section, index; level 5's
  wrong-building check), `serverTicked(id)`, `serverOpen()` (way on open:
  last section up and all but `exit` items ticked; true with no list),
  `serverPlayerJoined`. A finished section waits `NEXT_AFTER` (1.5 s)
  then the next replaces it. One message, `TUT_OBJ <quest> <section>
  <counts csv> [<item> <secs>]`, the whole state on every change. Client:
  `Objectives.open(quest)` hides the WAY ON ring while shut; drawn at
  (10, 40), 18 px rows (seven items end just above the quests feature's
  "Quest:" line at y 197). Not built: items every present player must do
  ("pick up", "equip", decision table); stage 6 adds that (e.g. an
  `each = true` item counted per player against `Features.present`
  humans).
- `src/features/tutorial/init.lua` holds `Tutorial.LEVELS` (the five
  quest ids in order), `Tutorial.level(id)` (1 to 5, or nil) and
  `Tutorial.EXITS[questId] = { x, y }`, each level's way on near the top
  of its map. Priority 95, so its `serverRespawnPoint` answers before
  respawn-points (100, which places walked points on any quest map) and
  the garage (994).
- Checkpoints: `src/features/tutorial/checkpoint.lua`,
  `Checkpoint.SPOTS[questId] = { x, y }` (each placeholder map's start,
  `map.cx, map.cy`), `Checkpoint.spot(questId, player)` (a fresh
  `{ x, y, angle }` facing up; players side by side by id, host in the
  middle, `spread` 36 px) and `Checkpoint.draw(questId, time)` (green
  ring and flag labelled CHECKPOINT, drawn in `drawBelowCars` the whole
  level). init.lua's `serverRespawnPoint` answers while `level` is set;
  they come back on foot. A level with no entry falls through to the
  others: stage 7 removes `tutorial-4`'s for the hospital. Stages 4 to 7
  move each spot with its map (with the HOME star and the exit); level 2's
  must be far enough from Shoeman to dodge. Checked in a scripted run:
  killed at (300, -600) on level 1, back at (0, 192) on foot.
- Finishing a level (same file): the host keeps `level = { quest, done }`,
  set in `serverQuestStarted`, cleared in `serverQuestEnded` and
  `mapChanged`. `serverStep` asks `quests:serverArrivedAt(server, x, y,
  reach)` (shared with borderline) for a present human within
  `Tutorial.reach` (120 px) of the exit and calls `quests:serverComplete`;
  the EXIT star comes up there. Until then `drawBelowCars` draws a pulsing
  green ring labelled WAY ON (the client reads `quests.active` and
  `quests.done`). Later stages that lock the way on (level 2's five
  dodges, level 3's waves) need no lock code: `serverStep` asks
  `Objectives.serverOpen()` before the reach test, ticks the exit items on
  arrival, and the ring hides while shut. A level only adds its list and
  `Objectives.serverTick` calls.
- Levels 4 and 5 share `tutorial-city`, so starting level 5 changes no
  map and nobody is moved: `serverQuestStarted` calls the city-map
  feature's `placePlayers` itself when no `mapChanged` came since the last
  quest start (the `arrived` flag). Without it level 5 finished at once.
- Every finished level shows the quests feature's "JOB DONE" banner with
  the quest title, as on every chained line. Stage 2's comms may want to
  say more.
- The five quests are at the top of `Quests.list`
  (`src/features/quests/init.lua`), `boss = "tutorial"`, label SHOEMAN.
  `Quests.TUTORIAL = "tutorial-1"` is the board id finishing is recorded
  under (when `tutorial-5` completes); unlocking is linear, so it opens
  Karen only, then the rest one by one.
- Old worlds: `Quests.SAVE_VERSION` is 2 and `serverSaveWorld` always
  writes its slice. `Quests:serverStart(server)` reads `server.saved`: a
  world written before (`format`) with no quests slice or a version 1 one
  gets `tutorial-1` finished with 1 clear (shows as level 2 on the board;
  clears under 1 are dropped by the board and by `serverLoadWorld`).
- Verifying: scripted LÖVE runs in the scratchpad with a separate
  `t.identity` in `conf.lua` (so real saves are untouched) and a
  coroutine script in `main.lua`. Taking a board job needs the player at
  `quests:jobs()`'s `doorX, doorY`; the last EXIT star home is a victory
  offer that ignores the accept key for its first seconds.
- The other maps are placeholders in `CityMap.maps` (`city-map/init.lua`):
  `tutorial-park` 44x44, `tutorial-yard` and `tutorial-city` 40x40, all
  `empty = true` (open walled ground, like `testrange`), walked, nobody
  about. Everyone arrives on the middle row (`map.cy`: -64, 64, 64). One HOME star per map (`home-tutorial-*`
  in `Quests.list`) 240 px south of that. Backdrops are the outskirts'
  (`surroundings/init.lua` `DRAW`). Ammo crates scatter on their own.
  Stages 4 to 7 replace each with a real map (a `kind` and a builder);
  when they do, move its HOME star and its `Tutorial.EXITS` entry.
- `make audit` passes (8.6, end of stage 3) with four majors: no
  soundtrack on the four maps. Those wait for stage 11 unless a reviewer
  wants them sooner. Minors: core files changed (`src/states/game.lua`
  for stage 0's HUD cleanup and `emptyHanded`, `src/body.lua` for
  `emptyHanded`; call both out in the pull request) and the branch
  touching 10 features (stage 0's HUD cleanup, borderline's switch to
  `serverArrivedAt`, weapons and abilities here).

## Decisions

| Question | Decision |
| --- | --- |
| Where does the code live? | `src/features/tutorial/`, quests `tutorial-1` to `tutorial-5`, feature name `tutorial`. |
| How is it first on the board? | `tutorial-1` is the first `board = true` entry in `Quests.list` (above `karen`). `Quests.unlocked` then opens only it on a new world; the rest open when the chain's last quest completes. |
| Old worlds? | A world created before the tutorial counts it as finished: all jobs stay open and the tutorial can be replayed from the board. Only new worlds must do it first. |
| Starting gear? | New players start with no gun and no ability. Shoeman gives the pistol in level 3 and openborders in level 4. Existing players keep what they have. A player joining a world where the tutorial is already finished is given both at once. |
| One group or each player alone? | The whole server, like every quest. Objectives are shared: any player's progress ticks them, except "pick up" and "equip", which every player present must do (each gets their own pickup). |
| How does Shoeman look? | Drawn in code like every boss and portrait (the game has no image assets): bald, heavy-set, grey eyebrows, navy t-shirt. |
| Levels 4 and 5 map? | One map for both: a small copy of the city centre with only the plots the lesson needs. What is built there is thrown away on leaving, like every quest map. |
| Does building cost money in level 5? | No. Plots are handed over free and build and repair costs are zero on the tutorial map. |
| Hit by a shoe in level 2? | Dead, back to the checkpoint. Shoes already dodged stay counted. |
| Progress tracking? | This file. No other system exists; the other quest lines keep a "Status" paragraph and a "Stages" list in their design doc, and this adds tick boxes. |

## Cast

**Shoeman.** A big bald man in a navy t-shirt who believes the world has
gone soft and that a thrown shoe fixes most things. Loud, insulting, fond
of the player in his own way. Blames everything on public school and on
"Sorros", who hates everyone.

- **The shoe.** One every 5 seconds. He shouts "DODGE!!!!" just before the
  throw (the telegraph), then the shoe flies in a straight line at where
  the target stood. Whatever it touches that can take damage is destroyed
  at once: players, cars, buildings, enemies, rioters.
- **In the tutorial** he is a teacher: he stands still, talks through the
  comms panel, and only throws shoes in level 2 (and when mocking).
- **As a city event** (host, F8) he walks the city and throws shoes at
  players and buildings until beaten. Follows the boss standard
  (`src/features/bosses`).

## Levels

Every level has a checkpoint the players respawn at, a HOME star, and a
way on that only appears when the level's objectives are done.

### Level 1: Cross the road (`tutorial-1`, movement and stamina)

- **Map.** Small and tall. Bottom: the start, the checkpoint, the HOME
  star, Shoeman. Above: four two-way streets running left to right, each
  ending in a tunnel mouth at both edges. Between streets a strip of
  pavement where nothing drives. Top: the way on.
- **Lesson.** The opening speech: he will teach you to survive in this
  "WOKE" world of violence. Then walking, sprinting, and the stamina bar
  (it drains while sprinting, rests before refilling, and an empty bar
  must recover before the next sprint).
- **Traffic.** Fast cars in straight lines, both directions on every
  street, spawned inside one tunnel and removed inside the other. Speeds
  and gaps differ per lane; the top streets are the fastest.
- **Death.** Any touch of a moving car kills, whatever the player wears.
  Respawn at the checkpoint.
- **Objectives.** `[ ] Reach the other side`

### Level 2: Dodge (`tutorial-2`)

- **Map.** A large park. Shoeman stands still in the middle. HOME star on
  one side, the way on on the other, the checkpoint far enough from him
  that a shoe can be dodged.
- **Lesson.** The dodge key, its stamina cost and its cooldown.
- **Play.** A shoe every 5 seconds at the nearest player. A dodge counts
  when a player dodges while a shoe is in flight at them and it misses.
- **Objectives.** `[ ] Dodge Shoeman's shoes (2/5)` with the seconds to
  the next throw beside it. The way on opens at 5.

### Level 3: The scrap yard (`tutorial-3`, shooting)

- **Map.** A scrap yard with room to run and car wrecks as cover. Bottom
  left: Shoeman, the HOME star, the checkpoint and the start. The way on
  is the yard's gate.
- **Lesson.** Picking things up, the inventory and equipping, firing,
  the magazine, reloading.
- **Play.** He drops a pistol. Once it is equipped he says to empty the
  magazine, then to reload. Then three waves of six Bigfoot squirrels;
  a wave starts when the one before is dead.
- **Objectives.** Ticked one by one:
  `[ ] Pick up the pistol` `[ ] Equip it` `[ ] Empty the magazine`
  `[ ] Reload` `[ ] Defeat wave 1` `[ ] Defeat wave 2` `[ ] Defeat wave 3`

### Level 4: Open borders (`tutorial-4`, abilities)

- **Map.** The tutorial city centre (shared with level 5), with a
  hospital.
- **Lesson.** Abilities: picking one up, putting it in a slot, casting it.
- **Play.** He drops openborders. When it is cast he laughs and mocks the
  player: using it as a weapon always backfires, and anyone who uses it is
  a friend of "Sorros", and "Sorros" hates everyone. The rioters must be
  destroyed once; casting again does not reset the objective.
- **Death.** Shoeman mocks the player; respawn at the hospital.
- **Objectives.** `[ ] Pick up Open Borders` `[ ] Equip it` `[ ] Use it`
  `[ ] Destroy the rioters`

### Level 5: Build (`tutorial-5`, buildings and trade)

- **Map.** The same city centre, with exactly the plots the lesson needs
  and a shop.
- **Lesson and objectives.** One section at a time; a section's list is
  shown alone and removed when all of it is ticked.
  1. **Resources.** `[ ] Build a Quarry Mine` `[ ] Set it to iron`
     `[ ] Build a second Quarry Mine` `[ ] Set it to sulfur`
  2. **Factories.** `[ ] Build a Weapons Factory` `[ ] Set it to pistols`
     `[ ] Build an Ammo Factory`
  3. **Transport.** `[ ] Collect iron from the quarry`
     `[ ] Load it into the Weapons Factory`
     `[ ] Load iron and sulfur into the Ammo Factory`
  4. **Repair.** Shoeman puts a shoe through a building.
     `[ ] Repair the damaged building`
  5. **Hires.** `[ ] Hire a driver` `[ ] Hire a Handsy Man`
  6. **Selling.** `[ ] Sell a pistol to the shop`
     `[ ] Sell ammo to the shop`
- **Wrong building.** If a player builds something the current objective
  did not ask for, Shoeman insults them (it must be because they went to
  public school) and the building is destroyed back to an empty lot.
- **Free.** Building and repairing cost nothing here.
- **End.** When every section is done the HOME star takes the players
  home, the tutorial counts as finished and the other jobs open.

Note: the pistol never runs out of ammo; the 9mm the Ammo Factory makes
feeds the Uzi and SMG. Shoeman says so, so nobody thinks the pistol needs
it.

## Systems

What exists and is reused, and what has to be added. Nothing below needs a
change to a core file, except stage 3's `emptyHanded` hook (`src/body.lua`,
`src/states/game.lua`).

### Inside `src/features/tutorial/`

| Module | What it does | Built on |
| --- | --- | --- |
| `init.lua` | Hooks; owns each level's state on the host. | `test-range/init.lua` (smallest quest feature), `borderline/init.lua` (levels ending at an exit) |
| `story.lua` | Every line Shoeman says, keyed by beat. | `borderline/story.lua` |
| `comms.lua` | Portrait and typed text at the usual panel spot `(10, 250)`, played from a queue the host raises. | `borderline/hud.lua` `drawComms`, `borderline/tale.lua` |
| `objectives.lua` | Tick-box list per section, sent by the host, drawn top left; a finished section is removed. New: no quest has a tick list yet. | `borderline/hud.lua` `drawObjective` for the spot and look |
| `checkpoint.lua` | Answers `serverRespawnPoint` with the level's checkpoint (feature priority under 100 so it answers first). | `respawn-points/init.lua` |
| `start_gear.lua` | Hands the pistol and openborders to a newcomer (no saved file) on a world past the tutorial. | `weapons` and `abilities` `serverEquip` |
| `shoeman_face.lua`, `shoeman_render.lua` | His portrait and his body in the world. | `src/art/face.lua`, `borderline/faces.lua`, `Body.person` |
| `shoe.lua` | The shout, the throw and the shoe: kills players, wrecks cars and buildings, kills enemies in its path. | `Weapons:explode` (`weapons/init.lua`), which already walks players, cars, `serverBlast` and `serverShotAt` |
| `traffic.lua` | Level 1's cars: `server:spawnVehicle`, speed set every step, removed in the far tunnel; contact check with `Car.hitTest`. | `car-collisions/init.lua` `runOver` |
| `waves.lua` | Level 3's squirrel waves. | `events/bigfoot.lua` `litter` and `pop` |
| `event.lua` | Shoeman as a host event. | `events/bigfoot.lua`, `a-man/event.lua` |

Maps: four specs in `CityMap.maps` (`city-map/init.lua`) with builders and
renderers beside the other maps' (`city-map/borderline.lua`'s `Blockout`
is the builder to copy).

### Changes to other features

| Feature | Change | Stage |
| --- | --- | --- |
| `quests` | Five entries at the top of `Quests.list`; worlds saved before the tutorial load with it marked finished. | 1 |
| `weapons` | New players start with empty gun slots (`startSlots`, `serverLoadPlayer`, the `heldGun` fallback). Events other features can hear: magazine emptied, reload finished. | 3, 6 |
| `abilities` | New players start with no ability (`startKeys`). | 3 |
| `events` | The squirrel spawn made callable from outside (`serverSummon`, as antlions and rollermines have). Shoeman added to `Events.kinds`. | 6, 10 |
| `open-borders` | A way to tell when one cast's rioters are all dead; rioters die to a shoe in one hit. | 8 |
| `buildings` | Build and repair cost asked through a hook so a map can make them free; a host call to remove a building. | 9 |
| `quests`, `shop`, `garage`, `handsy-man`, `delivery` | A map flag so the shop, the hospital, Handsy Men and shop sales also work on the tutorial city. Today they are default-city only. | 7 |

### Known facts worth remembering

- Dodges have no invulnerability. Level 2 judges a dodge by the shoe
  missing, so none is needed.
- `weapons:serverDamage` is ignored during spawn protection (1.5 s). Fine
  for respawns; do not rely on a kill landing in that window.
- A run-over normally deals about 120 at full speed, which armour or gym
  health can survive. Level 1 does its own contact check and kills
  outright.
- A building is removed when its plot changes owner; that is the existing
  way back to an empty lot.
- `--quest tutorial-3` starts any level directly (`src/launch.lua` skips
  the lock check). Levels must not assume the earlier ones were played:
  level 4 gives a pistol if the player has none.
- Every quest map needs a backdrop, a soundtrack, ammo crates and a HOME
  star, and a quest whose enemies come out late needs a tour script
  (`docs/audit.md`).
- Anything that can be shot answers `serverEnemies` and `wikiEnemies`.

## Stages

One branch and pull request each, in this order. Every stage ends with
`luacheck .`, `make audit` and a `CHANGELOG.md` line where players would
notice.

### 0. HUD cleanup and this plan (`feature/tutorial-shoeman-plan`)

- [x] Remove the top-left help text: speed, the drive hint, kills, the bot keys, roadkill, the sprint and dodge hint
- [x] Keep the FPS counter and the mission comms panels untouched
- [x] Write this file

### 1. Skeleton (`feature/tutorial-skeleton`)

- [x] `src/features/tutorial/init.lua` from `_template`
- [x] Quests `tutorial-1` to `tutorial-5` chained by `next`, `tutorial-1` first on the board
- [x] Four placeholder maps (flat ground, start, HOME star, exit) so the chain can be walked end to end
- [x] Each level completes when a player reaches the exit
- [x] Worlds saved before the tutorial count it as finished
- [x] New world: only the tutorial is open; finishing level 5 opens Karen

### 2. Shoeman and the tutorial HUD (`feature/tutorial-shoeman`)

- [x] `shoeman_face.lua`: portrait, talking mouth
- [x] `shoeman_render.lua`: body in the world, throw pose
- [x] `comms.lua` and `story.lua`, with the opening speech
- [x] `objectives.lua`: tick list, sections, host-synced
- [x] `checkpoint.lua`: respawn at the level's checkpoint
- [x] Shoeman standing on each placeholder map

### 3. Starting with nothing (`feature/tutorial-start-gear`)

- [x] New players start with no gun
- [x] New players start with no ability
- [x] Existing saved players keep their pistol and freeze
- [x] Joining a world with the tutorial finished gives pistol and openborders
- [x] Nothing fires or crashes with empty gun slots (HUD, inventory, bots, audit)
- [x] Bodies drawn with empty hands: a player holding no gun shows none (every client, so the held gun must be synced)

### 4. Level 1: cross the road (`feature/tutorial-road`)

- [x] Map: four two-way streets, tunnel mouths, safe strips, renderer
- [x] `traffic.lua`: spawn, drive, remove; lanes with their own speed and gap
- [ ] No health bar on traffic cars (it shows over the tunnel roofs)
- [ ] A touch kills; respawn at the checkpoint
- [ ] Movement and stamina lines; objective "Reach the other side"
- [ ] Way on at the top

### 5. Level 2: dodge (`feature/tutorial-dodge`)

- [ ] Park map and renderer
- [ ] `shoe.lua`: the "DODGE!!!!" shout, the throw, instant destruction
- [ ] Dodge counting, the `n/5` objective with the countdown
- [ ] Way on appears at 5

### 6. Level 3: the scrap yard (`feature/tutorial-scrapyard`)

- [ ] Scrap yard map and renderer
- [ ] Pistol pickup per player; pick up and equip objectives
- [ ] Magazine-emptied and reload-finished events in weapons; their objectives
- [ ] Squirrel spawn callable from outside `events`; `waves.lua`, three waves of six
- [ ] `serverEnemies` and `wikiEnemies` for the tutorial's squirrels
- [ ] Way on at the gate after wave 3

### 7. The tutorial city (`feature/tutorial-city`)

- [ ] City-centre map with only the lesson's plots
- [ ] Map flag for city services; shop, hospital, Handsy Men and sales honour it
- [ ] Respawn at the hospital on this map

### 8. Level 4: open borders (`feature/tutorial-open-borders`)

- [ ] Openborders pickup per player; pick up and equip objectives
- [ ] "Use it" objective; the Sorros mockery on cast
- [ ] Rioters-cleared detection, counted once
- [ ] Mockery on death
- [ ] Way on to level 5

### 9. Level 5: build (`feature/tutorial-build`)

- [ ] Free plots; build and repair cost hook
- [ ] Wrong building: the public-school insult, building removed
- [ ] Section 1: resources
- [ ] Section 2: factories
- [ ] Section 3: transport
- [ ] Section 4: repair (Shoeman's shoe does the damage)
- [ ] Section 5: hires
- [ ] Section 6: selling
- [ ] HOME star on completion; the tutorial counts as finished

### 10. Shoeman, the city event (`feature/tutorial-shoeman-event`)

- [ ] `event.lua` registered in `Events.kinds`, on the F8 menu
- [ ] Brain: walks, picks players and buildings, a shoe every 5 seconds
- [ ] Boss standard: stamina, the boss bar, health scaling, koins on death
- [ ] `serverEnemies` and `wikiEnemies` for Shoeman

### 11. Polish (`feature/tutorial-polish`)

- [ ] A soundtrack for each map
- [ ] Backdrops past each map's edge; ammo crates
- [ ] Audit tour script in `tools/audit/stages.lua`
- [ ] Wiki pages (`make wiki`, `make wiki-portraits`)
- [ ] Balance pass: traffic speeds, shoe speed, squirrel waves
- [ ] `docs/features.md`: the tutorial in the feature list
