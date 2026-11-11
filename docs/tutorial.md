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
worlds counting it as finished. Stage 2 under way on
`feature/tutorial-shoeman`, branched from `feature/tutorial-skeleton`:
the portrait and his body in the world are done. Next: stage 2, third
box (`comms.lua` and `story.lua`).

### Handoff notes

Short notes from the last sessions for the next one. Keep it current, not
a history.

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
  flying shoe (the same one he holds) for `shoe.lua`. Nothing draws him
  yet; the last box of stage 2 stands him on the maps.
- `src/features/tutorial/init.lua` holds `Tutorial.LEVELS` (the five
  quest ids in order), `Tutorial.level(id)` (1 to 5, or nil) and
  `Tutorial.EXITS[questId] = { x, y }`, each level's way on near the top
  of its map. Default priority (100); `checkpoint.lua` will need under
  100 when it comes.
- Finishing a level (same file): the host keeps `level = { quest, done }`,
  set in `serverQuestStarted`, cleared in `serverQuestEnded` and
  `mapChanged`. `serverStep` asks `quests:serverArrivedAt(server, x, y,
  reach)` (shared with borderline) for a present human within
  `Tutorial.reach` (120 px) of the exit and calls `quests:serverComplete`;
  the EXIT star comes up there. Until then `drawBelowCars` draws a pulsing
  green ring labelled WAY ON (the client reads `quests.active` and
  `quests.done`). Later stages that lock the way on (level 2's five
  dodges, level 3's waves) add their check before the reach test in
  `serverStep`, and should hide the ring while it is locked.
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
- The maps are placeholders in `CityMap.maps` (`city-map/init.lua`):
  `tutorial-road` 24x56 tiles, `tutorial-park` 44x44, `tutorial-yard`
  and `tutorial-city` 40x40, all `empty = true` (open walled ground, like
  `testrange`), walked, nobody about. Everyone arrives on the middle row
  (`map.cy`: 192, -64, 64, 64). One HOME star per map (`home-tutorial-*`
  in `Quests.list`) 240 px south of that. Backdrops are the outskirts'
  (`surroundings/init.lua` `DRAW`). Ammo crates scatter on their own.
  Stages 4 to 7 replace each with a real map (a `kind` and a builder);
  when they do, move its HOME star and its `Tutorial.EXITS` entry.
- `make audit` passes (8.6) with four majors: no soundtrack on the four
  maps. Those wait for stage 11 unless a reviewer wants them sooner. Two
  minors: `src/states/game.lua` changed (stage 0's HUD cleanup; call it
  out in the pull request) and the branch touching 9 features (stage 0's
  HUD cleanup plus borderline's switch to `serverArrivedAt`).

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
change to a core file.

### Inside `src/features/tutorial/`

| Module | What it does | Built on |
| --- | --- | --- |
| `init.lua` | Hooks; owns each level's state on the host. | `test-range/init.lua` (smallest quest feature), `borderline/init.lua` (levels ending at an exit) |
| `story.lua` | Every line Shoeman says, keyed by beat. | `borderline/story.lua` |
| `comms.lua` | Portrait and typed text at the usual panel spot `(10, 250)`, played from a queue the host raises. | `borderline/hud.lua` `drawComms`, `borderline/tale.lua` |
| `objectives.lua` | Tick-box list per section, sent by the host, drawn top left; a finished section is removed. New: no quest has a tick list yet. | `borderline/hud.lua` `drawObjective` for the spot and look |
| `checkpoint.lua` | Answers `serverRespawnPoint` with the level's checkpoint (feature priority under 100 so it answers first). | `respawn-points/init.lua` |
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
- [ ] `comms.lua` and `story.lua`, with the opening speech
- [ ] `objectives.lua`: tick list, sections, host-synced
- [ ] `checkpoint.lua`: respawn at the level's checkpoint
- [ ] Shoeman standing on each placeholder map

### 3. Starting with nothing (`feature/tutorial-start-gear`)

- [ ] New players start with no gun
- [ ] New players start with no ability
- [ ] Existing saved players keep their pistol and freeze
- [ ] Joining a world with the tutorial finished gives pistol and openborders
- [ ] Nothing fires or crashes with empty gun slots (HUD, inventory, bots, audit)

### 4. Level 1: cross the road (`feature/tutorial-road`)

- [ ] Map: four two-way streets, tunnel mouths, safe strips, renderer
- [ ] `traffic.lua`: spawn, drive, remove; lanes with their own speed and gap
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
