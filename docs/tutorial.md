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
Stage 4 done on `feature/tutorial-road`, branched from
`feature/tutorial-start-gear` (not pushed or merged yet): Shoeman's Road
(four two-way streets, tunnel mouths, safe strips, the school yard and
the lawn), its traffic with a speed and gap per lane and no health bars,
any touch of a car kills and brings you back at the checkpoint, the
movement and stamina lesson said as it happens, "Reach the other side"
ticking at the way on, the EXIT star on to the park. `make audit` 8.6,
pass; `CHANGELOG.md` line added. Stage 5 done on
`feature/tutorial-dodge`, branched from `feature/tutorial-road` (not
pushed or merged yet): Shoeman's Park, a shoe every 5 s at the nearest
player with the "DODGE!!!!" shout, everything it touches destroyed,
dodges in the air counted to 5 with the countdown, then he stops
throwing and the way on opens. `make audit` 8.6, pass; `CHANGELOG.md`
line added. Stage 6 done on `feature/tutorial-scrapyard`, branched from
`feature/tutorial-dodge` (not pushed or merged yet): Shoeman's Scrap
Yard; a pistol put down one each, pick up and equip ticked per player;
weapons' magazine-emptied and reloaded events tick "Empty the magazine"
and "Reload"; loose squirrels in the events feature, three waves of six
out of the burrows; their wiki page and portrait; the gate opens after
wave 3. `make audit` 8.2, pass; `CHANGELOG.md` line added. Stage 7 done
on `feature/tutorial-city`, branched from `feature/tutorial-scrapyard`
(not pushed or merged yet): Shoeman's Town, a 3x3-block city grid with
the four corner plots and the hospital in the middle block; `services =
true` on it, so the shop, sales, hires, the hospital and Handsy Men work
there; dying on levels 4 and 5 brings you back at the hospital's door.
`make audit` 8.2, pass (the four soundtrack majors are stage 11's);
`CHANGELOG.md` line added. Stage 8 done on
`feature/tutorial-open-borders`, branched from `feature/tutorial-city`
(not pushed or merged yet): openborders put down one each by Shoeman in
town (the pistol's module made shared: `gift.lua`), "Pick up Open
Borders" and "Equip it" ticked per player; "Use it" on the first cast,
he laughs at every cast and mocks the first (Sorros); "Destroy the
rioters (n/25)" counts simps killed across casts and stays ticked; the
dead are mocked (in full once, then a quip at most every 15 s); anyone
there without a pistol is handed one; once all is ticked he says where
the way on is, and taking its EXIT star starts level 5 on the start with
level 4's horde and fires cleared. `make audit` 8.1, pass (the four
soundtrack majors are stage 11's); `CHANGELOG.md` line added. Stage 9
under way on `feature/tutorial-build`, branched from
`feature/tutorial-open-borders`: box 1 done (plots, building and repairs
free in Shoeman's Town through the new `buildCost` hook), box 2 (a
building the list did not ask for comes down with the public-school
line), box 3 (section 1: resources), box 4 (section 2: factories). Next:
stage 9, box 5 (section 3: transport).

### Handoff notes

Short notes from the last sessions for the next one. Keep it current, not
a history.

- Section 2 (stage 9 box 4): data and beats only: `pistols` is `kind =
  "weapons", makes = "gun-pistol"` (the factory starts on it, product 1),
  section `beat = "factories"` (the 9mm note: the pistol never runs dry,
  9mm is the Uzi's and SMG's). Checked in a scripted run (sections 1 and 2
  from the harness's `SECTION1`): ammo factory first says `ammo`, a third
  quarry is wrong and comes down, the weapons factory ticks `weapons` and
  `pistols` and says `factories`; section 3 up after.
- Section 1 (stage 9 box 3): an item with `kind` and `makes` asks for a
  building of that kind making that item (`iron`, `sulfur` on quarries);
  it ticks on "built" (a quarry starts on iron, product 1) or "product".
  After each event `sayNext` says one beat: the section's `beat` field
  ("resources") when the section is all ticked, else the last ticked
  item's (`iron` covers a first quarry: built and digging iron). Checked
  in a scripted run: two plots taken, quarry on 1 ticks 1 and 2 (`iron`
  said), quarry on 2 ticks 3 (`quarry2`), BLD_PRODUCT 2 2 (sulfur) ticks 4
  and `resources`; section 2 up 1.5 s later. Harness helpers: plot i's
  middle and pad are (-640|640, -640|640) and (x, y + 224).
- Level 5's lesson (stage 9 box 2): buildings raises a new event
  `serverBuildingDone(server, player, plotId, what, kind, item, n)` (in the
  events table of `docs/features.md`), `what` "built", "product",
  "collected", "loaded" (one call per material), "repaired" (from the
  menu only: a Handsy Man's `serverRepair` raises nothing), through its
  local `did`; and a public `Buildings:serverRemove(server, id)` (empty
  lot, owner kept). The tutorial's `serverBuildingDone` passes it on to
  `src/features/tutorial/build.lua` (`Build.serverDone`) while a level is
  on in town (`inTown()`: levels 4 and 5) for a human. `Objectives.lists
  ["tutorial-5"]` holds all six sections already (ids `quarry1`, `iron`,
  `quarry2`, `sulfur`; `weapons`, `pistols`, `ammo`; `collect`,
  `loadWeapons`, `loadAmmo`; `repair`; `driver`, `handsy`; `sellPistol`,
  `sellAmmo`); an item with `build = kind` asks for a building of that
  kind. "built": the first unticked `build` item of that kind on screen
  ticks and says the beat named after the item id; nothing asks for it
  (level 4 asks for nothing) -> `serverRemove` and `<level>.wrong`, at
  most every `Build.insultEvery` (6 s). A build in the 1.5 s between two
  sections is judged against the finished one, so it comes down: rare,
  left. Story: `tutorial-4.wrong`, `tutorial-5.start`, `.wrong`,
  `.quarry1`, `.quarry2`. Checked in a scripted run: a weapons factory on
  plot 1 in section 1 gone on host and client (BLD_GONE), the plot still
  ours, `wrong` said; a second one within 6 s gone with no line; a quarry
  stays and ticks "Build a Quarry Mine".
- Free in town (stage 9 box 1): a new hook `buildCost(cost, what, kind)`,
  asked through `Features.reduce` on both sides (in `_template` and the
  events table of `docs/features.md`). Real-estate asks it as
  `RealEstate.plotPrice()` ("plot"; the sign then reads FREE PLOT and the
  prompt "Free plot. F: take it"); buildings as `Kinds.buildPrice(kind)`
  ("build": menu rows, the build screen's cards and button, BLD_BUILD)
  and `Kinds.repairPrice(kind, hp)` ("repair": menu rows, BLD_REPAIR).
  `Kinds.repairCost` stays the raw price: it still says whether there is
  damage ("intact", the menu's repair row) and handsy-man's fee reads it.
  Not asked: the ruin takeover price, Handsy Men's fees. The tutorial
  answers 0 while `city.current == Tutorial.TOWN` ("tutorial-city"), on
  levels 4 and 5 alike. Checked in a scripted run (`--quest tutorial-5`,
  wallet 0): RE_BUY took plot 1, BLD_BUILD put up a quarry, BLD_REPAIR from
  hp 100 to 600, the wallet 0 throughout; screenshots of the FREE PLOT
  sign and the quarry's menu. Harness: a copy of the game in the
  scratchpad with `t.identity = "gta7-build-test"` and a copy of a saved
  world there (`--world newjob`), so real saves are untouched.
- City services (stage 7 box 2): a spec flag `services = true` (on
  `tutorial-city` only) and `CityMap:servicesHere()` (default city, or a
  spec with the flag). Honoured by: `Quests:jobsBuilding()` (new: the Jobs
  building with shop and gym, on any services map), which `Shop:here()`
  now uses, so buying, selling and hiring drivers and Handsy Men work at
  the town's shop; `Garage:hospital()` (new: the hospital on any services
  map), which draws it and its minimap cross; handsy-man's `inCity()`.
  Left default-city only on purpose: `Quests:jobs()` (the board: no jobs
  taken mid-tutorial; it now calls `jobsBuilding` behind a DEFAULT check),
  `Garage:places()` (garages, impound, wrecks, `serverHome`), the gym
  (`Upgrades:here()` still asks `quests:jobs()`), delivery's `inCity()`
  (its yards are keyed by the city's plot ids, and the town's plots 1 to 4
  would collide and delete them), buildings' and real-estate's DEFAULT
  checks (stage 9's). Buildings already swap the city's away off it
  (`sv.home`), so Handsy Men only see the town's own. `quests/jobs.lua`'s
  `taken` asks `garage:hospital()` now; the town's doors did not move.
  Checked in a scripted run (`--quest tutorial-4`): shop door (0, -416)
  bought a medkit and pistol ammo, bought back an uzi, delivered a hired
  driver; a Handsy Man was refused "nowork" (no buildings, as it should);
  hospital and shop drawn; `jobs()` nil there; back in the city every
  service as before.
- Respawn at the hospital (stage 7 box 3): `checkpoint.lua`'s
  `tutorial-4` and `tutorial-5` entries carry `hospital = true`: the spot
  is `garage:hospital()`'s door (0, 224), facing down out of it (their
  own x, y only without a garage). The CHECKPOINT ring is drawn there too,
  under the EMERGENCY sign. The garage's own `serverHome` still answers
  nothing off the default city. Checked in a scripted run: killed at
  (640, -640) on levels 4 and 5, back at (0, 224) on foot; level 3 still
  at its yard pad (-896, 896).
- Shoeman's Town (stage 7 box 1): not a builder of its own but a plain
  city grid (`map.kind == "grid"`), so `garage/places.lua`'s `Places.of`
  and `quests/jobs.lua`'s `Jobs.of` (both grid-only) already find its
  hospital, Jobs building, shop and gym. Its spec in `CityMap.maps`:
  `seed = 8, cols = 32, rows = 32, blocks = { "pbp", "bbb", "pgp" }`. New
  in `layout.lua`: a spec's `blocks` fixes each block's kind, one string
  per row of blocks, top first ("b" buildings, "g" park, "l" lot, "p"
  plot; the "p"s make `map.plots`), the seed still filling them. Seed 8
  was picked by trying 3000 seeds for a big hospital and a Jobs building
  with a shop. What comes out (checked in a scripted run, `--quest
  tutorial-4`): 9 buildings; four plots, real-estate ids 1 (-832, -832)
  NW, 2 (-832, 448) SW, 3 (448, -832) NE, 4 (448, 448) SE, each 384 px
  square, FOR SALE 20 Fcks; the hospital the whole middle block (-192,
  -192, 384x384), door (0, 224); the Jobs building in the top middle
  block, door (0, -864) on the top street side; the shop below it in the
  same block, door (0, -416), facing the hospital across the street; the
  gym door (544, -224); no impound (no lot). None of these show yet:
  see box 2's note for which services show now. Start and checkpoint (0, 320) on the road under the
  hospital (`map.cx, cy`); Shoeman (160, 416) on the pavement over the
  park; HOME star (0, 544) on the park's north path; the way on (-640,
  -960) on the top street above the NW plot (clear of the Jobs door).
  Spots and spawns all clear of solids. Ammo crates and medkits scatter
  on their own. Bots still roam it (13 players in the run): as on every
  tutorial map.

- Their wiki page (stage 6 box 5): `Squirrels.wikiEnemies(add)` in
  `events/squirrels.lua` (kind `events/loose-squirrel`, `quests = {
  "tutorial-3" }`, `scaling = "none"`), asked by `Events:wikiEnemies`;
  `serverEnemies` already listed them (box 4). `tools/wiki/pages.lua`'s
  `ARCS` names the tutorial's index section "Shoeman's School of
  Survival". Portrait: a city scene in `tools/wiki/scenes.lua` summons
  one beside the host; drawn with `WIKI_ONLY=city make wiki-portraits`
  (`docs/wiki/enemies/img/events-loose-squirrel.png`). `make wiki` fails
  on `main` already (gun-plasma-rifle and gun-bolter: "no wikiEnemies
  entry drops it") and then writes nothing, so the pages were written
  with a scratch copy of `tools/wiki/run.lua` that skips that exit, and
  only the squirrel's page and the enemies index were kept. Fixing those
  two guns' droppers is someone else's (not the tutorial's) to do.
- The squirrels (stage 6 box 4): `src/features/events/squirrels.lua`,
  loose squirrels, Bigfoot's with no Bigfoot, on any map. Host:
  `Events:serverSummonSquirrels(server, x, y, count, r)`,
  `Events:serverSquirrelsLoose()` (count). Their own tuning
  (`Squirrels.speed` 230, slower than Bigfoot's 340; `bite` 4 "melee",
  then `backOff` 0.7 s running off; `range` 3000; one round kills; no
  lifetime, never burst on a player). Messages `ESQ_STATE` (15 Hz,
  unreliable), `ESQ_OUT`, `ESQ_POP`. The events feature runs them beside
  whatever event is on (step, shots first, panic, freeze, draw, messages)
  and clears them on `mapChanged` and `serverStart`. Bigfoot's squirrels
  now steer through the shared `Squirrels.chase` / `Squirrels.run` (same
  numbers as before; checked in a scripted Bigfoot event: litters come
  out, run, burst). They ignore walls like his (they run through wrecks
  and the office). `serverEnemies` already lists them as kind
  `events/loose-squirrel`.
  `src/features/tutorial/waves.lua`: `Waves.serverStart(dens)` from
  `serverReloaded` once "reload" ticks (with `map.dens`), stopped where
  the pistol is. `FIRST_AFTER` 5 s, then each wave `SIZE` 6 out of `DENS`
  2 burrows in turn (3 each), the next `GAP` 4 s after the last of one is
  shot; `on.out` (shouted beat `tutorial-3.out`, "HERE THEY COME!"),
  `on.killed(wave, n)` ticks `wave1..3` (`need = Waves.SIZE`, shown
  "(2/6)"), `on.cleared(wave)` says `tutorial-3.wave1`/`.wave2`; `.wave3`
  is box 6's. A death on level 3 says `.bitten` once. Checked in scripted
  runs: all three waves come out in turn, 18 killed by real pistol rounds
  (20 shots aimed at the nearest), 16 bites taken while they came in,
  each kill ticks its wave on host and client, and after wave 3
  `Objectives.serverOpen()` is true. Screenshot shows the seven items
  fitting above the "Quest:" line. The beats still queue far behind the
  start speech (the equip line was on while wave 1 bit): stage 11.
- Empty and reload (stage 6 box 3): weapons raises two new host events
  (in the events table of `docs/features.md`):
  `serverMagazineEmptied(server, player, index)` from `serverFire` when a
  counted round (not a bot's, not infinite ammo) leaves the magazine at 0,
  and `serverReloaded(server, player, index)` from `finishReloads` when an
  on-foot reload put rounds in. The tutorial answers both on level 3:
  "empty" ticks when the player has ticked "equip"
  (`serverDidPlayer`), "reload" once "empty" is ticked; beats
  `tutorial-3.emptied` and `.reloaded`, and `.equipped` now says to fire.
  Both items are shared (anyone's counts). Checked in a scripted run: 15
  `serverFire` calls tick "Empty the magazine", `serverReload` ticks
  "Reload" when it finishes (mag back to 15), host and client. With all
  four ticked the way on opens: box 4's wave items close it again. The
  beats queue behind the long start speech, so they come late.
- The way on to level 5 (stage 8 box 6): stage 1's machinery already
  did it (reaching `Tutorial.EXITS["tutorial-4"]`, (-640, -960) on the top
  street above the NW plot, once `Objectives.serverOpen()`, completes the
  quest and the EXIT star comes up there; taking it is the player's
  choice, the client's `QST_ACCEPT exit` on the star, which starts
  `tutorial-5` and `serverQuestStarted` puts everyone on the start). New:
  `serverStep` says the level's `open` beat once the way on is open, if
  it has one (`tutorial-4.open` gives directions; level 2's was already
  said by `shoeEvents`, and a beat plays once a level). And
  `OpenBorders:serverClear(server)` (new, public, host: horde and fires
  gone, `OB_CLEAR`; `mapChanged` now calls it) is called when a level
  starts with no map change, so level 4's fires do not burn round level
  5's start (they did, 30 s, in the first run). The rioters' koins stay on
  the ground. Checked in a scripted run: the whole of level 4 (armed at 2
  s, pickup at 10 s, equip, cast, 25 shot, `cleared` then `open`), the
  WAY ON ring drawn clear on the top street's crossing, standing on it
  completes `tutorial-4`, `QST_ACCEPT exit` starts `tutorial-5` with the
  player at (-120, 318), no simps or fires on host or client. In that run
  the player burned to death in the horde's fires before reaching the way
  on until moved off them: stage 11's balance pass. Harness notes: a
  player standing on the EXIT star is not enough, send `QST_ACCEPT exit`
  from the client; `serverArrivedAt` counts only the living.
- A pistol on level 4 (stage 8 box 5): `start_gear.lua`'s `give` is split;
  `StartGear.givePistol(server, player)` (true when handed over) puts the
  pistol in the first empty weapon slot unless they carry one, and `give`
  calls it and then does openborders as before. Its `hand` now equips one
  already in the bag instead of giving a second, and returns whether it
  equipped. init.lua's local `armEveryone`, from `serverStep` on
  `tutorial-4` once `level.t >= Tutorial.armAfter` (2 s, so his line comes
  after the start beat), looks at each human once a level (`level.armed`)
  the first step they are present; a pistol handed over says
  `tutorial-4.armed` ("Did you skip the scrap yard?"). Someone whose slots
  are all full of other guns gets nothing (they are armed). Checked in
  scripted runs: no pistol at all, pistol in slot 1 at 2 s and `armed`
  said after `start`; one in the bag, that one equipped (bag 1 -> 0);
  carrying one already, nothing and no line.
- Mockery on death (stage 8 box 4): the tutorial's `serverKill` on
  `tutorial-4` with a `victim` who is a human (`server.players[id]`, not
  `.bot`; bots roam the town and die in the fires too) calls the local
  `mockDeath`: the first time `tutorial-4.died` (the full mockery, Sorros,
  the hospital), after that `Tutorial.QUIPS` (`died2`, `died3`, `died4`,
  one line each) in turn with `again`, and nothing when the last was under
  `Tutorial.mockEvery` (15 s) ago. The level table now keeps `t` (seconds
  into it, counted in `serverStep`), `mockedAt`, `mockedOnce`, `quips`.
  Respawn at the hospital is stage 7's (`checkpoint.lua`). Checked in a
  scripted run: a bot's death said nothing; a real `weapons:serverKill`
  at 3 s said `died` and the player came back at (0, 224); a death at
  10 s said nothing; at 19, 35, 51 and 67 s `died2`, `died3`, `died4`,
  `died2`. A harness note: a faked `serverKill` needs `x, y` (money drops
  a koin there).
- "Destroy the rioters" (stage 8 box 3): the open-borders feature's
  `serverKill` for a simp now carries `simp = true` (still kind
  "pedestrian"; documented in `docs/features.md`'s events table). The
  tutorial's `serverKill` sends those on `tutorial-4` to a local
  `rioterDown`, which ticks the shared `rioters` item (`need =
  Objectives.RIOTERS`, 25, a copy of open-borders' `Horde.SIMPS`: the
  audit flags requiring another feature's files)
  and says `tutorial-4.cleared` when that tick fills it. Decided (see
  "Decisions"): kills add up across casts and never reset; a horde that
  times out (30 s) keeps what was killed. Simps that time out or burn are
  not kills (they are immune to fire anyway). `.cast` now ends with "clean
  up your mess". Checked in a scripted run: 10 killed from a cast at 3 s
  (counted before "use" ticked: the count does not wait for it), the rest
  timed out, still 10 at 36 s and the way on shut; a second horde, 14 and
  then 11 more killed: 24, then 25 ticks it once (the extra kills did
  nothing), `cleared` said, `serverOpen()` true. The caster burned to death
  every time, and openborders' 90 s cooldown makes a timed-out horde a
  long wait: stage 11's balance pass should look at both on this level.
- "Use it" (stage 8 box 2): the tutorial answers abilities'
  `serverOpenBorders(server, caster, x, y, seconds)` event (every feature
  hears it; the open-borders feature lets the horde in beside it). On
  `tutorial-4`, a human caster who has ticked "equip" (`serverDidPlayer`)
  ticks the shared `use` item (init.lua's local `used`); every such cast
  says `tutorial-4.laugh` (shout only, so it cuts in, `again`), the first
  also `.cast` (the mockery: rioters are yours, it backfires, friend of
  Sorros, Sorros hates everyone). A cast before "equip" ticked for them
  (someone who carried one already casts before the drop lands at 10 s;
  the cooldown is 90 s) is remembered in `level.castEarly[id]` and counts
  when `giftEvents.equipped` ticks them. `.equipped` now names
  `{ability-1}` and tells them to cast. The open-borders feature calls
  its horde "simps"; the tutorial says "rioters". Checked in a scripted
  run (`--quest tutorial-4`, openborders given and equipped at 1 s, a real
  `abilities:cast` at 3 s): nothing ticked before the drop; at 10 s
  `picked`, `equipped`, `laugh`, `cast` arrive on the client and all three
  items tick; a second cast at 18 s says only `laugh`. The caster burned to
  death in the horde's fires within seconds (box 4's mockery will be
  heard a lot). The `.cast` lines queue behind the start speech (still on
  at 16 s): stage 11's comms timing.
- The gifts (stage 6 box 2, made shared in stage 8 box 1):
  `src/features/tutorial/gift.lua` (was `pistol.lua`), host only.
  `Gift.serverStart(gift, x, y)` from `serverQuestStarted`, driven by
  `Tutorial.GIFTS` in init.lua: `tutorial-3` drops `Gift.PISTOL` at the
  yard's `map.dropX, dropY` (-600, 940); `tutorial-4` drops
  `Gift.OPENBORDERS` at (64, 416), the pavement between the town's start
  and Shoeman (the town is a plain grid, no `dropX`). A gift is `{ item,
  equipped(player) }`. `DROP_AFTER` 10 s in it is dropped with
  `pickups:serverDrop(..., item, ..., { perPlayer = true })`: one each,
  NEW and the gold reward rings, walking over it puts the item in the bag
  (pickups' material kind for the pistol, ability kind for openborders).
  Every step after, per human: equipped calls `on.equipped` and
  `on.picked`; the item in the bag in any tier (`buildings:serverCount`
  over `Tiers.list`) `on.picked`. Someone who carries one already is
  hidden from the drop by `Pickups:serverTakenBy(server, id, player)`
  (`PK_GONE <id>` to them only) and ticks at once. init.lua's
  `giftEvents` tick `pickup` / `equip` and say the level's own
  `<level>.picked` / `.equipped`. `Objectives.lists["tutorial-4"]` so
  far: `pickup` "Pick up Open Borders", `equip` (both `each`), `use`,
  `rioters`; the way on opens once all are ticked (`serverOpen`); no WAY
  ON item yet (box 5). Story: `tutorial-4.start` (three lines,
  "lesson five"), `.picked`, `.equipped`. Checked in scripted runs (`--world town --quest
  tutorial-4`): stripped of openborders, the orb lands at 10 s by
  Shoeman, walking onto it ticks "Pick up Open Borders", `serverEquip`
  into slot 1 ticks "Equip it" (client's `abilities.slots[1]` shows it);
  carrying one already, both tick when it lands and the drop is hidden
  from them. Level 3 rechecked through the new module: pistol drops, walk
  ticks pickup, equip ticks equip. Not run with a second human.
- Objectives can now count per player: an item with `each = true` is
  ticked with `Objectives.serverTickPlayer(server, id, player)` (true when
  new for them), asked with `serverDidPlayer(id, player)`; its need is the
  number of humans in `server.players` (bots never count), recounted every
  `serverStep` (`serverRecount`) so a leaver stops counting and a joiner
  must do it too. On the wire its count is `done/need`; the label shows
  "(1/2)" only with more than one human. `serverTick` refuses `each`
  items. `Objectives.lists["tutorial-3"]` so far: `pickup`, `equip` (both
  `each`), `empty`, `reload`, `wave1` to `wave3`. Checked in scripted runs: a fresh player sees the pistol at
  10 s, walking onto it ticks "Pick up" (1/1) and says `picked`,
  `serverEquip` ticks "Equip it" and it is in hand (15/15); a player
  already carrying a pistol never sees the drop and both tick when it
  lands. Not run with a second human.
- Shoeman's Scrap Yard (stage 6 box 1): `buildYard` in
  `city-map/tutorial_maps.lua` (`kind = "tutorial-yard"`, 40x40 tiles,
  tuning in `TutorialMaps.YARD`), `drawYard` in `render_tutorial.lua`.
  The fence row round the edge is nil tiles (walls), inside is "walk".
  The concrete pad (`map.pad`, -1216..-448 x 704..1216) in the bottom-left
  corner: start and checkpoint (-896, 896), Shoeman (-736, 1016), HOME
  star (-896, 1136); the site office (`map.office`) above it against the
  west fence. The way on (832, -1056) by the shut gate (`map.gate`) in the
  top fence. Solids: the office, the crusher (`map.crusher`, top-left),
  four piles of wrecks along the top, east and west fences (`map.piles`;
  not `stacks`, which Borderline's works reads as chimney smoke on any
  map), 30 lone wrecks (`map.wrecks`, 80x40 or 40x80 boxes, their
  `solid`), 10 tyre heaps (`map.tyres`, 44 px boxes). All stop rounds:
  cover. `map.dens` = five squirrel burrows in the far half, kept clear
  (-300,-900), (320,-700), (900,-220), (520,320), (-560,-320): for
  `waves.lua`. Checked: headless build (spawns, spots and dens open, a
  16 px flood fill from the start reaches every den and the way on) and a
  scripted run with `--quest tutorial-3`, screenshots of the pad, the
  middle, the gate, the crusher, the east pile and the office.
- The fifth dodge (stage 5 box 4): `shoeEvents.dodged` in init.lua,
  when the tick makes `Objectives.serverOpen()` true, calls
  `Shoe.serverHalt()` (no new throws; one under way and shoes in the air
  finish; `serverNextIn()` is nil after), clears the timer and says
  `tutorial-2.open` (go to the gate) instead of `dodged`. Checked in a
  scripted run: five dodges, no throw in the 8 s after, standing at the
  gate finished `tutorial-2`. The gate is drawn shut on the map canvas and
  stays so; the WAY ON ring is the sign. Stage 11 may open it.
- Dodge counting (stage 5 box 3): a dodge counts when the player a shoe
  was thrown at (`shoe.target`) dodges while it is in the air (init.lua's
  new `serverDodged` hook -> `Shoe.serverDodged(player)` sets
  `shoe.dodged`) and it then goes past them (`passed`: their pose is more
  than 18 px behind the shoe along its line) or stops short, without
  touching them and with them alive (`settle`, once per shoe). A dodge
  in the wind-up does not count: he aims where they stand at release, so
  standing after it gets them killed (the start beat says so).
  `Shoe.serverStep(server, dt, on)` now takes callbacks instead of
  returning true: init.lua's `shoeEvents.threw(server)` raises the shout
  and sets the countdown (`Objectives.serverTimer(server, "dodge",
  Shoe.serverNextIn())`, also at the level's start), `dodged(server, id)`
  ticks `dodge` (`Objectives.lists["tutorial-2"]`: one item, `need = 5`,
  `timer = true`, no exit item) and says `tutorial-2.dodged` the first
  time. A death on level 2 says `tutorial-2.hit` once. Counts survive a
  death. At 5 the label drops the timer and `serverOpen()` is true, so the
  WAY ON ring shows. Checked in a scripted run:
  dodged in flight five times, ticked 1 to 5 and opened at the fifth (host
  and client); walking away without dodging and dodging in the wind-up
  did not count, the second one killed; screenshots show "(1/5)  next in
  2 s" and "(5/5)" ticked.
- The shoe (stage 5 box 2): `src/features/tutorial/shoe.lua`. Host:
  `Shoe.serverStart(x, y)` (init.lua's `serverQuestStarted` for
  `tutorial-2`, from `Tutorial.SHOEMAN`), `Shoe.serverStop()` (quest end,
  `mapChanged`, `serverStart`), `Shoe.serverStep(server, dt, on)` takes the
  callbacks (see dodge counting above). `Shoe.serverShoes()` lists the
  shoes in flight. Timing: first
  throw `FIRST_AFTER` 10 s into the level, then every `PERIOD` 5 s; the
  throw lasts `THROW_TIME` 1.2 s, the target is picked (nearest living
  human within `RANGE` 1600) at its start and the shoe aimed at where they
  stand at `ShoemanRender.RELEASE` (0.82 s in). `SPEED` 900 px/s,
  `RADIUS` 8. Destruction, sampled every 6 px: players on foot
  `Weapons:serverKill` ("impact", no attacker, spawn protection still
  spares); any car not hidden or stowed `weapons:damageCar(..., 1e6)` (a
  human driver bails out, as war_rigs does it); every `serverShotAt` asked
  up to 8 times at the spot with damage 1e6. It flies on through all of
  those and stops at the first `blocksShot` (hedge, tree, pond), which
  takes `serverBlast` radius 8, damage 1e6 (buildings fall: level 5's
  repair section wants a dent instead, so give it a damage argument then).
  Messages `TUT_THROW <angle>`, `TUT_SHOE <id> <x> <y> <angle>`,
  `TUT_SHOE_END <id> <x> <y>`; clients fly the shoe themselves, tumbling,
  stop it at a wall or the range, and leave it lying 4 s. Client:
  `Shoe.pose()` (throw fraction, angle) drives `ShoemanRender.draw`'s
  `throw` in init.lua's `drawAboveCars` (he faces the throw and keeps
  looking that way), `Shoe.draw(x, y)` the shoes and the red "DODGE!!!!"
  over him. Comms: a beat that is all shouting now cuts in at once
  (`Comms.queue`) and the interrupted line resumes where it was. Level 2's
  `start` beat (the dodge lesson: key, stamina, cooldown) is in
  `story.lua`. Checked in a scripted run (`FIRST_AFTER` 4): standing still
  at the start, killed by the first shoe and back at the checkpoint;
  walking east through the next throw, missed; an empty car between him
  and the player wrecked, the shoe flying on; screenshots show the shout
  on the panel and over him, the throw pose and the shoe in flight. Not
  tried: an enemy or a building in its path (none in the park), a real
  second client.
- Shoeman's Park (stage 5 box 1): `buildPark` in
  `city-map/tutorial_maps.lua` (`kind = "tutorial-park"`, 44x44 tiles,
  tuning in `TutorialMaps.PARK = { ring 640, plaza 96, path 64, start 768,
  hedge 1 }`), `drawPark` in `render_tutorial.lua` (its `draw` now
  dispatches by kind through `DRAW`). Shoeman stands at (0, 0) on a paved
  circle (`map.shoemanX, Y`); `map.ring = { x, y, r }` is the dodging
  ground round him, open lawn with nothing solid on it (checked), a chalk
  ring drawn at its edge. Start and checkpoint (0, 768), 768 px south of
  him (`map.cx, cy`), on a gravel square with the twelve spawns; HOME star
  (0, 1008); the way on (0, -1184) by a shut gate in the top hedge (the
  hedge row round the edge is nil tiles, so walls). Trees (`map.trees`, a
  16 px solid box each), the pond (`map.pond`, three solid boxes) and beds
  only outside the ring. Old shoes lie in the grass as decor. `shoe.lua`
  throws from `Tutorial.SHOEMAN["tutorial-2"]` (0, 0); a shoe that flies
  past the ring may hit a tree or the pond's boxes (`map.solids`, the
  trees flagged `tree = true`); they all stop it.
  Checked in a scripted run (`--quest tutorial-2` on a fresh world): spots
  all open, nothing solid in the ring, walking works, standing at the way
  on finishes the level; screenshots of the start, Shoeman, the gate, the
  pond and a corner look right. The minimap shows the park as plain grey,
  like the road.
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
  removed next step. `Traffic.cars()` is car -> `{ lane, tune, cars }`.
  The kill (box 4): after the lanes drive, `hits` tests every present
  player on foot against every traffic car (`Car.hitTest`,
  `Traffic.BODY_RADIUS` 8) and calls a new public
  `Weapons:serverKill(server, victim, attacker, angle, dtype)` ("impact",
  no attacker): `die` straight away whatever the health or armour, the
  same players spared as by `damage` (absent, in a car, dead, spawn
  protected); raises `serverPlayerDamaged` first, so box 5 or stage 2's
  comms can hear a death (also `serverKill` from `die`, `victim` set,
  `by` nil). Listed in `docs/features.md` beside `serverDamage`. The
  run-over damage from car-collisions still lands first; harmless.
  Checked in a scripted run: health 5000, 3 s on a safe strip alive, in
  street 1's kerb lane dead in 0.45 s, inside a tunnel dead in 0.6 s,
  both times back on foot at the checkpoint (0, 768). Checked in a scripted run: 35 cars at the start on all
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
  from `CityMap:drawAboveCars`. Car health bars are gone there (box 3: a
  new client hook `carBarHidden(client, vid)`, asked through
  `Features.any` by weapons' bar loop in `drawAboveCars`; the tutorial
  answers true for every car while `quests.active == "tutorial-1"` and the
  map has `lanes`, since players' own cars are stowed on a walked map. No
  message: the client cannot tell traffic apart, `car.traffic` is host
  only. In `_template` and the events table of `docs/features.md`).
  Anything else other features draw over cars would still show. Players can walk into a tunnel (its road tiles are
  open, under the roof); traffic kills them there anyway.
- Level 1's spots now come from the road (the numbers are copied, the
  map also leaves them as `map.cx, cy` (start, checkpoint: 0, 768),
  `map.shoemanX, Y` (160, 888), `map.homeX, Y` (0, 1008: quests'
  `home-tutorial-road`), `map.exitX, Y` (0, -1216: `Tutorial.EXITS`)).
  Change them together if `TutorialMaps.ROAD` changes. The way on (box 6)
  needed no code: checked in a scripted run, the WAY ON ring shows on the
  lawn, reaching it ticks "cross", completes the level and offers "Lesson
  two"; accepting the EXIT star (`Features.serverMessages.QST_ACCEPT
  .handler(server, p, { "exit" })` in a harness) puts everyone on
  `tutorial-park` on foot with `tutorial-2` active and no traffic left.
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
  walking keys). Level 1's beats are all there (box 5): `start` (the
  speech, walking, the sprint key, the road), then `sprint`, `spent`,
  `strip`, `across` raised by `src/features/tutorial/road.lua`
  (`Road.serverStep(server, map)` from init.lua's `serverStep` with the
  road: first stamina below max, first `spent` (on-foot's
  `walker(player)` record; stamina itself refills in the same tick when
  no rest delay runs), first player on a pavement strip, first past the
  top street) and `flat` from `Tutorial:serverKill` (any `kill.victim`
  during level 1). Every beat queues behind the 40 s opening speech, so
  a fast player hears "EMPTY!" late; stage 11 may cut the speech or let
  a lesson beat jump the queue. `src/features/tutorial/comms.lua`:
  host side `Comms.serverStart(questId)` (from `serverQuestStarted`; says
  the "start" beat 1.5 s later), `Comms.serverStop()`,
  `Comms.serverBeat(server, what, again)` (once per level unless `again`),
  `Comms.serverStep(server, dt)`; message `TUT_SAY <key>`. Client side a
  queue (`Comms.queue`, `Comms.update`, `Comms.drawHUD` at (10, 250),
  `Comms.busy()`), cleared on a tutorial quest's start or end and on
  `exitGame`. init.lua wires all of it; later boxes only add beats to
  `story.lua` and call `Comms.serverBeat`.
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
  `serverPlayerJoined`, plus the `each` calls above. A finished section
  waits `NEXT_AFTER` (1.5 s) then the next replaces it. One message, `TUT_OBJ <quest> <section>
  <counts csv> [<item> <secs>]`, the whole state on every change. Client:
  `Objectives.open(quest)` hides the WAY ON ring while shut; drawn at
  (10, 40), 18 px rows (seven items end just above the quests feature's
  "Quest:" line at y 197).
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
- Backdrops are the outskirts' (`surroundings/init.lua` `DRAW`) on every
  tutorial map, the town's too (the city's own is the sea: stage 11).
- `make audit` passes (8.2, end of stage 6; 8.6 at stage 5) with four
  majors: no soundtrack on the four maps. Those wait for stage 11 unless a reviewer
  wants them sooner. Minors: core files changed (`src/states/game.lua`
  for stage 0's HUD cleanup and `emptyHanded`, `src/body.lua` for
  `emptyHanded`; call both out in the pull request) and the branch
  touching 10 features (stage 0's HUD cleanup, borderline's switch to
  `serverArrivedAt`, weapons and abilities here). Stage 4 also changed
  weapons (the `carBarHidden` hook, `serverKill`): no core file. Stage 5
  changed only the tutorial and city-map. Stage 6 changed weapons (two
  events), pickups (`serverTakenBy`), events (loose squirrels) and the
  wiki tool (`ARCS`, a scene); its new minors are `events/squirrels.lua`
  requiring alien-hunt's render and sounds and pedestrians' gibs, as
  `bigfoot.lua` already does (the gibs moved from there; Bigfoot now
  uses `Squirrels.drawPop` and `Squirrels.splat`). One full audit run
  showed seven "does not hurt borderline/jet" arsenal majors on
  borderline-prosperity; not this branch's: the quest alone passed three
  times and the next full run had none (timing under the parallel run).

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
| "Destroy the rioters" in level 4? | 25 simps killed (one cast's worth), added up over any casts by anyone. A horde that times out keeps what was killed; nothing resets it. Killing one whole horde inside its 30 s while burning was too hard for a lesson. |
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
| `events` | Loose squirrels anyone can summon (`serverSummonSquirrels`, `serverSquirrelsLoose`; `events/squirrels.lua`). Shoeman added to `Events.kinds`. | 6, 10 |
| `pickups` | `serverTakenBy`: a one-each drop hidden from one player (the pistol from those who carry one). | 6 |
| `open-borders` | A simp's `serverKill` says `simp = true`, so the tutorial can count the rioters; rioters die to a shoe in one hit. | 8, 10 |
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
- [x] No health bar on traffic cars (it shows over the tunnel roofs)
- [x] A touch kills; respawn at the checkpoint
- [x] Movement and stamina lines; objective "Reach the other side"
- [x] Way on at the top

### 5. Level 2: dodge (`feature/tutorial-dodge`)

- [x] Park map and renderer
- [x] `shoe.lua`: the "DODGE!!!!" shout, the throw, instant destruction
- [x] Dodge counting, the `n/5` objective with the countdown
- [x] Way on appears at 5

### 6. Level 3: the scrap yard (`feature/tutorial-scrapyard`)

- [x] Scrap yard map and renderer
- [x] Pistol pickup per player; pick up and equip objectives
- [x] Magazine-emptied and reload-finished events in weapons; their objectives
- [x] Squirrel spawn callable from outside `events`; `waves.lua`, three waves of six
- [x] `serverEnemies` and `wikiEnemies` for the tutorial's squirrels
- [x] Way on at the gate after wave 3

### 7. The tutorial city (`feature/tutorial-city`)

- [x] City-centre map with only the lesson's plots
- [x] Map flag for city services; shop, hospital, Handsy Men and sales honour it
- [x] Respawn at the hospital on this map

### 8. Level 4: open borders (`feature/tutorial-open-borders`)

- [x] Openborders pickup per player; pick up and equip objectives
- [x] "Use it" objective; the Sorros mockery on cast
- [x] Rioters-cleared detection, counted once
- [x] A pistol for anyone who reaches level 4 without one (`--quest tutorial-4`, a newcomer mid-tutorial): the rioters need shooting
- [x] Mockery on death
- [x] Way on to level 5

### 9. Level 5: build (`feature/tutorial-build`)

- [x] Free plots; build and repair cost hook
- [x] Wrong building: the public-school insult, building removed
- [x] Section 1: resources
- [x] Section 2: factories
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
