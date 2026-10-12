# Cyber Feud design

A quest line in the shape of A-Man's (`src/features/a-man`): a job on the
board, five maps chained by each quest's `next`, an intro screen, chatter, and
a boss at the end. The look is cyberpunk, neon on grey, in that style rather
than a parody of any one game.

Status: story, characters, troops and maps designed. Built so far (each a
branch off `feature/cyber-feud`):

- `feature/cyber-feud-skeleton`: the five maps (city-map's `drop`, `market`,
  `overpass`, `tower`, `roof`, in `city-map/cyber_feud.lua`), their quests and
  HOME stars, the `cyber-feud` feature finishing each level when someone
  reaches its far end, and night (the `night` feature) on all five.
- `feature/cyber-feud-story`: the story told so far. Map and zone banners,
  VEX's intro screen and her face, her comms lines at story beats, the
  objective line, and the Shard: taken from the vending machine on the Drop
  and carried for the rest of the line. Every word is in
  `src/features/cyber-feud/story.lua`.
- The Drop's chase theme (`src/features/cyber-feud/theme_chase.lua`): rock
  with a synth arpeggio, 150 BPM in A minor, ~48 s, looping from the moment
  someone takes the Shard until the map changes.
- The factions in Halcyon Tower (`feature/cyber-feud-tower-troops`, `tower`
  in `Troops.levels`, feud `false`; placements in `buildTower`): they ignore
  each other (never rivals, and their rounds pass through both sides).
  Halcyon holds every floor: a pair on each stair door up, two on each of
  the lobby's lifts, a few more posts floor by floor, and a squad of three
  walking each floor's beat (a loop round its desks, racks, tanks,
  barricades or table; two squads on the security floor; none in the
  lobby). Calm until a player walks past the reception (`map.wakeY`). The
  Static break in from below (`Troops.breakIn`, `map.breakIns`): 12 s after
  the tower wakes, then every 35 s, a pack of four comes in onto the lowest
  floor any human is on (the lobby's front doors, above it the top of the
  stairwell from the floor below) and walks that floor's beat, while fewer
  than 8 (4 more a human past the first) of them are on that floor; packs
  left two floors behind are taken off. The first of each pack shouts as
  they come in (`Story.troops.static.breakIn`).
- Kilowatt, the Roof's first boss (`feature/cyber-feud-kilowatt`,
  `src/features/cyber-feud/kilowatt.lua` and `kilowatt_brain.lua`,
  `map.bosses.kilowatt` in `buildRoof`; KWB_ messages, since the Overpass's
  cameo has KW_): waits on the helipad until the roof wakes (`map.wakeY`, a
  few rows up from the stairs, or a round into him), then comes for the
  nearest player. 2400 health for one human (`Bosses.health`), drawn at
  2.2x. Charge: from 130-460 px he braces 0.6 s (a cyan line on the floor)
  and runs 540 px/s for 0.9 s down it (40 `impact` and a 140 px shove);
  into a wall he reels for 1 s. Slam: within 170 px he hops (0.5 s) and a
  ring of shock rolls out to 230 px at 520 px/s (26 `shock`, a stun). Whip:
  within 380 px, after a 0.45 s crackle, lightning to whoever he sees and
  on to the next player within 170 px, up to three (22 `shock` each).
  Punch up close (30 `impact`). After every 4 moves he vents for 3 s (hits
  count double). Phase 2 at half health: charges back to back (0.8 s apart,
  a 0.45 s brace), the slam rolls to 330 px, venting every 6 moves for
  4.5 s. The bosses' standard: breath (running at you drains it; a charge
  costs 20, a slam 15), the boss bar, a medkit when badly hurt (heal.lua),
  out from under abilities (dodge.lua), and going down `serverKill` "boss",
  40 koins and two pickups. Only players' rounds reach him. While he is up
  the Roof isn't done (the helipad doesn't finish it) and the objective
  line says to take him down.
- Director Saye, the Roof's second boss (`feature/cyber-feud-saye`,
  `src/features/cyber-feud/saye.lua` and `saye_brain.lua`,
  `map.bosses.saye` in `buildRoof`, by the billboard; SYE_ messages): wakes
  with the roof. 2000 health for one human. She never runs: walks at 70
  px/s (95 in phase 2; 38 winded), keeping 420 px from whoever she sees.
  Sightline: every 3.2 s she holds still with a thin magenta line on where
  they stood for 1 s (brighter for its last moment), then one 45-damage
  round at 1800 px/s down it. Executive drones: three orbiting her at 50
  px, each firing bursts of two (5 a round) every 1.7 s at the nearest
  player in sight within 520 px; 30 health each, only players' rounds;
  lost ones come back 12 s later ("Drones. Re-onboard."). Restructuring:
  every 14 s (25 breath, at most three up) she drops a sentry turret
  where she stands, sweeping all the way round (`Turrets.serverJoin`), and
  walks off from it. Phase 2 at half health: the line holds 0.5 s, comes
  every 2.4 s and fires two in a V (0.16 rad either side). The bosses'
  standard as Kilowatt's. The boss bar takes a `row` (bosses/bar.lua):
  hers sits over his while he is up. The Roof needs both down, and the
  objective line names whoever is still up.
- Brutes up the Roof's stairs (`feature/cyber-feud-roof-brutes`,
  kilowatt.lua's `callHelp`, `map.bosses.stairs` and `map.bosses.beat` in
  `buildRoof`): while Kilowatt fights, a brute comes up the stairs at the
  south edge 15 s into the fight and every 25 s after, while fewer than 2
  of his are up (`Bosses.plus`: one more for each human past the first),
  and walks a beat round the helipad until it spots somebody. He shouts
  for them ("Boys! Up here! Bring the big ones!"). None come once he is
  down. A breached one's swings reach the bosses too.
- Saye and Kilowatt together (`feature/cyber-feud-roof-duo`,
  `src/features/cyber-feud/duo.lua`, the only place either looks at the
  other; troops.lua steps it after both). They cover each other: a
  player's round into Saye gives Kilowatt a 6 s grudge on that player (he
  goes for them and his next charge is ready; "Hey! Hands off the suit,
  spark!" half the time), and a player within 200 px of Kilowatt that Saye
  can see is her target first, her line hurried to 0.8 s at most. Shield:
  while he vents her drones circle him at 52 px, and while any are there
  his vent doesn't double hits (his bar says SHIELDED). When one falls the
  other rages: Saye alone ("Hostile takeover.") six drones and her line
  fires three rounds 0.15 s apart; Kilowatt alone ("MELTDOWN!") phase 2
  for good, each slam leaving a 120 px shock patch for 4 s (8 `shock`
  every 0.5 s; KWB_PATCH). They bicker every 18-30 s while both are up: one
  line and the other's answer 2.4 s later, four exchanges in turn. (The
  boss card with their portraits waits on the portraits.)
- Halcyon Tower's theme (`src/features/cyber-feud/theme_tower.lua`,
  `feature/cyber-feud-tower-theme`): industrial groove metal, 132 BPM in
  C# minor, ~60 s, looping from the moment the tower wakes (CF_WAKE, a
  player walking past the reception) until the map changes. A bar of the
  lobby's muzak (electric piano, vibraphone, brushes) cut off by a tape-stop
  glitch; a syncopated groove of low C# chugs with the kick locked to them,
  the snare on three and synth stabs in the gaps; an industrial march (four
  on the floor, an anvil off the beat) leaning on D and G; a chorus of open
  chords (C# minor, A, E, B) over double kick under a lead and a cold
  square arpeggio; a half-time breakdown ending on the lift's chime; and
  the groove again into the top.
- The Static's brutes (`feature/cyber-feud-tower-brutes`,
  `src/features/cyber-feud/brutes.lua` and `brute_brain.lua`): drawn at
  2x, 150 health, slow (45 px/s on a beat, 85 going in), finding their way
  on the troops' walking grid. From 70-280 px with a clear line one braces
  for 0.7 s (a cyan line on the floor where he will go), then charges
  400 px/s for 0.75 s (34 `impact` to whoever he runs through); into a
  wall he is dazed for 1.2 s. Up close he winds up (0.35 s) and punches
  (24). His arm is a breach target: on foot within 70 px hold F for 1.5 s
  (BRT_WORK, BRT_PROG; draining at half that when let go) and for 4 s he
  spins, swinging every 0.45 s at whatever is just past his reach, his own
  side, Halcyon and players alike (30 a swing, the breacher's). Placed by
  the map's `brutes` beats (for the Roof, later) or joining a break-in.
- The tower's break-ins (`Troops.breakIn`) bring the Static's specialists:
  a pack is still four, but from the offices up one of them is a sparker
  (`Sparkers.serverJoin`; the brain starts empty on the tower) and from the
  server room up one a brute (`Brutes.serverJoin`), walking the floor's
  beat at the back of the file. In the tower the sparkers have no rivals:
  they don't go for Halcyon's drones, though an EMP still knocks out any
  machine it catches.
- Halcyon's sentry turrets (`feature/cyber-feud-tower-turrets`,
  `src/features/cyber-feud/turrets.lua` and `turret_brain.lua`,
  `map.turrets` in `buildTower`): three in the labs (by the way in, in the
  middle between the tanks, by the door up) and four round the security
  floor, one on each wall facing in. Bolted down; each sweeps its arc
  (`arc` round `watch`) with a 50° cone out to 620 px along a clear line,
  puts a laser on whoever it sees for 0.6 s, then fires bursts of four (8 a
  round, Halcyon's) while it keeps them in sight, tracking at 2.2 rad/s
  (never past its arc's ends). 80 health; only players' rounds reach it.
  Breach: on foot next to one (60 px), hold F for 2.5 s (draining at half
  that when let go; TUR_WORK, TUR_PROG); it fights for the breacher for
  15 s, its lens green, going for every Halcyon and Static unit in its
  sight, its rounds theirs. The sparkers' EMPs knock it out for 5 s. (The
  hex-grid breach mini-game, when it comes, replaces the hold.)
- The tower's sting drones (`feature/cyber-feud-tower-stings`,
  `map.stings` in `buildTower`): swarms in the server room's aisles (the
  middle aisle, the east end by the way up, then the west aisle: two for
  one human). Indoors (the brain's `indoors` and `sameRoom`, the floors,
  from `src/features/cyber-feud/rooms.lua`, which the watchers use too) a
  swarm only goes for somebody on its own floor, never leaves it, and its
  runs are slower and shorter (`Brain.INDOORS`: 340 px/s, 150 px past,
  spotting within 560, giving up past 1100), go round the racks (sliding
  along them, breaking off when stuck) and fire only with a clear line.
- The tower's watcher drones (`feature/cyber-feud-tower-watchers`,
  `map.watchers` in `buildTower`): two in the offices (one round the desks,
  one up and down between them) and one in the lobby between the lifts and
  the reception, on beats down the aisles. Indoors (the brain's `indoors`
  and `sameRoom`, the tower's floors) one sees over the furniture but only
  who is on its own floor, and goes round what stands on the floor, never
  over it, so it is always where a round can reach it.
- The tower's marksmen (`feature/cyber-feud-tower-marksmen`,
  `map.marksmen` in `buildTower`): the Overpass's marksmen on the floor, in
  the far corners, in the order they are used (three for one human, one
  more each past the first): the security floor's stair-door corner
  watching back across it, its east end watching along the bottom, then
  the executive floor's west end over the boardroom, the security floor's
  west corner along the top, and the executive floor's east corner.
  Indoors (the brain's `indoors`, set on the tower) a wall hides you from
  them: they spot only who they have a clear line to and lose whoever goes
  behind one. Their sightline is drawn to the first wall, everywhere.
- The tower's enforcers (`feature/cyber-feud-tower-enforcers`,
  `map.enforcers` in `buildTower`): six riot shields, all Halcyon's: on the
  security floor a pair in front of the stair door up and a pair across its
  east side (the way to that door, clear of where the barricades fall), and
  on the executive floor a pair either side of Saye's desk. In the tower a
  faction's round passes through every troop of both sides (enforcers and
  the rest included: `Troops.serverShotAt` lets them all by).
- The tower's locked stair doors (`feature/cyber-feud-tower-doors`, gates
  of `kind` "door" in `map.gates`, `src/features/cyber-feud/gates.lua`): a
  shutter across the foot of each of the five stairwells up, solid to
  people and rounds until opened (and shut in the troops' walking grid
  too: `Nav:refresh` opens it there). Breach it by holding the action key
  (F) at the terminal on the wall beside it for 4 s, quietly (no alarm),
  draining at half that pace when let go; or press E there ("vex-door")
  and VEX opens it at once, along with the floor's guard room, a door in
  the middle of its north wall: four of Halcyon's officers (`Bosses.count`)
  come out of it one after another at whoever asked
  (`Troops.serverAmbush`, a garrison let out), and VEX says sorry
  (`tower.vex1`..`3`). The lobby's lifts moved in to make room for its
  door's terminal.
- The factions on the Overpass (`feature/cyber-feud-overpass`, `overpass`
  in `Troops.levels`; placements in `city-map/cyber_feud.lua`'s
  `buildOverpass`): Static gangers in pairs on the shoulders of the long
  stretch; Halcyon at the fork for the off-ramp, along the roadworks and
  across the tower ramp, with a squad on the stretch below it; and both
  waiting together in the Knot, Halcyon on its north and east edges, the
  Static along its south edge and a pack on the pad. Here the sides hold
  fire on each other (`feud = "provoked"`) until a round of one hits the
  other, usually crossfire aimed at a player between them; then they fight
  until 25 s after the last such hit (`Troops.flare`) and call a truce
  (Story.troops' `truce` lines). The troops are calm only on the Drop now,
  until the Shard is taken there.
- Halcyon's interceptors (`feature/cyber-feud-interceptors`,
  `src/features/cyber-feud/interceptors.lua`, their own brain in
  `interceptor_brain.lua`): NPC drivers from the bots feature, parked on
  the Overpass's shoulder at `map.interceptors` (three for one human, one
  more for each extra, up to five). A grey SUV tuned to 540 px/s and
  armoured to 220, a light bar flashing magenta and blue, an officer
  leaning out of the window. A player within 900 px and in sight sets one
  off: flat out at where they will be, into them once alongside, dropping
  back after each hit to come again, the officer firing SMG bursts
  (Halcyon's rounds) out to 520 px. It lets them go 5 s out of sight or
  past 1800 px. Wrecked, it spills 8 koins and is gone. Enemies don't
  target them (`serverHidden`), but crossfire hits them.
- The Static's war-rigs and Kilowatt's cameo (`feature/cyber-feud-war-rigs`,
  `src/features/cyber-feud/war_rigs.lua`, their own brain in
  `rig_brain.lua`): NPC trucks parked on the shoulder at `map.rigs` (two
  for one human, one more for each extra, up to four). A rusty truck
  tractor with a spiked chrome ram and junk plates, 380 health, 500 px/s,
  a ganger on the back with a shotgun (the Static's rounds, out to 260
  px). Something to hit within 850 px and in sight sets one off, straight
  at it nose first, dropping back after each hit; while the two sides are
  at it (the flare-up) Halcyon's interceptors are fair game too. Wrecked,
  10 koins. Kilowatt's ride (`map.kilowatt`): 11 s after arriving, or as
  soon as someone drives off, his rig roars up the right-hand edge from
  behind everyone with him on the back ("THERE you are, spark!"), swerves
  into the barrier 20 rows up; he leaps onto the road just before it goes
  up, laughs, and 2.4 s later runs off the east edge. Drawn twice anyone's
  size, chrome shoulders and jaw, a cyan reactor and cable mohawk, lit by
  his own glow.
- Halcyon's sting drones (`feature/cyber-feud-sting-drones`,
  `src/features/cyber-feud/stings.lua`, their own brain in
  `sting_brain.lua`): swarms of three over the Overpass's gantries
  (`map.stings`; two swarms for one human, one more for each extra, up to
  five). 20 health, 560 px/s, faster than a car. A player within 700 px
  (no line of sight needed, they are up high) sets a swarm off: run after
  run through a point a little ahead of where the target is going, each
  drone off to its own side, on 260 px past and looping back (3.4 rad/s,
  so wide at speed), firing three-round bursts (6 a round, Halcyon's)
  whenever the target is in front and within 420 px. They give up past
  1500 px. Only players' rounds reach them; an EMP knocks one out for 5 s.
- Halcyon's marksmen (`feature/cyber-feud-marksmen`,
  `src/features/cyber-feud/marksmen.lua`, their own brain in
  `marksman_brain.lua`): on the gantries' catwalks at `map.marksmen`, drawn
  over the cars (three for one human, one more for each extra, up to
  five). 40 health. A 130-degree cone down the road out to 950 px, over
  everything. A thin magenta line follows whoever he has for 1 s, leading
  a car to where it will be when the round arrives, then holds still and
  bright for 0.4 s and he fires down it: one round of 40 at 1700 px/s.
  Drive straight on and it hits; swerve while it holds and it misses. Then
  2.4 s on the bolt. A player's rounds or the Static's reach him; in a
  flare-up the Static are his rivals and he theirs. That is everything the
  design puts on the Overpass.
- The Overpass's theme (`src/features/cyber-feud/theme_overpass.lua`,
  `feature/cyber-feud-overpass-theme`): darksynth, a night drive, 124 BPM
  in D minor, ~58 s, looping from the moment Kilowatt's rig roars past
  (KW_RIDE; CF_MUSIC for a player joining after) until the map changes. A
  pad and an arpeggio over a riser, a rolling octave bass under a
  four-on-the-floor kick and a gated snare, the arpeggio over D minor, B
  flat, F, C, a detuned saw lead in the choruses, a break with the lead
  echoing, and the chorus again an octave up.
- The Courier (`feature/cyber-feud-armed-car`): the armed car everyone
  drives on the Overpass (see the Overpass's arrival): 180 health, 560
  px/s, a minigun in a roof turret. It is in the vehicle factory's catalog
  too (600).
- Car stations on the Overpass (`feature/cyber-feud-overpass-checkpoints`,
  `map.carStations` in `buildOverpass`): five pads on the shoulder about
  every thirty rows (the long stretch, the overhead signs, the off-ramp,
  the roadworks, the tower ramp), clear of the enemies' posts, drawn in
  VEX's green and lit at night. On foot on one, the action key calls your
  Courier back whole (the car-stations feature), and they are the map's
  respawn points (respawn-points takes a driven map's pads), so a wreck or
  a death doesn't send you back to the on-ramp.
- Halcyon's roadblocks (`feature/cyber-feud-roadblocks`,
  `src/features/cyber-feud/gates.lua`, `map.gates` in `buildOverpass`):
  blast gates right across the Overpass at the long stretch, the roadworks
  and below the tower ramp, solid to cars, people and rounds (a solid in
  the map's `solids` and `cells`, taken out of both on the host and every
  screen when it opens). To open one, somebody gets out and holds the
  action key at the control panel on the shoulder short of it for 3 s (it
  drains at half that pace when they let go); working it calls up to four
  of Halcyon's officers within 900 px, every 6 s, on top of the three
  posted behind each gate. Open, it stays open. The Knot gets round the
  roadworks gate; nothing gets round the other two.
- The Market's theme (`src/features/cyber-feud/theme_market.lua`,
  `feature/cyber-feud-market-theme`): heavy metal, thrash-fast, 170 BPM in
  E minor, ~48 s, looping from the moment the Market wakes (troops.lua's
  CF_WAKE, a player walking up out of the tunnel) until the map changes. A
  low E rung out under a pinch squeal, a palm-muted gallop with chromatic
  stabs and the tritone, a tremolo-picked riff over a thrash beat, a
  chorus of open chords (E minor, C, D, B) over double kick under a twin
  lead in thirds, and a half-time breakdown.
- The factions on the Drop (`src/features/cyber-feud/troops.lua`): Halcyon
  officers on the roadblocks and squads in the east, Static gangers on the
  western corners and packs walking their blocks, both on the Combine's brain
  (`a-man/combine.lua`, which now takes `rivals`, a `from` on its rounds and
  a `calm` switch). The two sides shoot each other on sight and stay calm
  until someone takes the Shard. The last stretch before the tunnel is
  Halcyon's alone (when both held it, they had wiped each other out long
  before anyone got there): the big roadblock, a station, a squad and the
  assassin droids (`src/features/cyber-feud/droids.lua`, drawn by
  `droid_render.lua`), on the Hunters' brain (`hunters/brain.lua`, which
  now takes a pace, a dodge cooldown and a locked-aim heavy shot). Guard stations (three Halcyon, two
  Static, `CyberFeud.DROP_STATIONS`): a yard on the avenue with a station
  house, an MG nest crewed as A-Man's Coast's are, cover either side, and a
  garrison that comes out of the house when a player gets near.
- The factions in the Market (`feature/cyber-feud-market`, the same
  `troops.lua` with `market` in `Troops.levels`; placements in
  `city-map/cyber_feud.lua`'s `buildMarket`): Halcyon officers in the gaps
  of the south cordon and behind the east line, a squad on the east strip
  and one round Noodle Square; Static gangers on the western corners and at
  the chop shop's door, packs on the west lanes (one through the square),
  and a garrison that comes out of the shop (a station with no MG nest).
  They wake when a player walks up out of the tunnel's mouth
  (`map.wakeY`), so nobody is shot on arrival.
- Halcyon's enforcers (`feature/cyber-feud-enforcers`,
  `src/features/cyber-feud/enforcers.lua`, their own brain in
  `enforcer_brain.lua`): riot shields in three of the Market's gates
  (`map.enforcers`), in front of the officers. 120 health, a shotgun, slow
  to turn (1.3 rad/s) and to step up (34 px/s, never more than 300 px from
  the gate). The shield stops every round coming within 70 degrees of
  straight on (a spark and a ping); blasts and fire go through. In the
  feud like the rest of Halcyon: the Static are their rivals and they are
  the Static's.
- The Static's rippers (`feature/cyber-feud-rippers`,
  `src/features/cyber-feud/rippers.lua`, their own brain in
  `ripper_brain.lua`): five on the Market's Static beats (`map.rippers`).
  40 health, a run of 150 px/s (a sprint is 170), finding their way round
  the stalls on the walking grid. Each goes for whoever is most alone
  (anyone else within 260 px makes a target count 300 px further off),
  crouches 0.5 s from within 200 px with a cyan line on the ground where it
  will go, then lunges about 220 px down it (28, `melee`): the line is set
  at the crouch, so stepping sideways dodges it. Up close it slashes twice
  (10 each) and backs off to lunge again. In the feud they go for Halcyon
  too; an enforcer's shield stops a cut from in front.
- The Static's sparkers (`feature/cyber-feud-sparkers`,
  `src/features/cyber-feud/sparkers.lua`, their own brain in
  `sparker_brain.lua`): two on the Market's Static beats (`map.sparkers`).
  40 health. They keep 230-400 px off whoever they have, backing off and
  closing in round the stalls, and every 3.6 s raise an EMP for 0.6 s and
  lob it at where that player stands then. A cyan ring on the ground shows
  where it comes down for as long as it is in the air; the burst is
  `shock`, 26 at the middle and a third of that at the edge (110 px), so
  near the middle it stuns. It does nothing to people of either side: it is
  for Halcyon's machines: a watcher drone caught in one is knocked out for
  5 s (stalling cars waits for a driven level with sparkers).
- Halcyon's watcher drones (`feature/cyber-feud-watchers`,
  `src/features/cyber-feud/watchers.lua`, their own brain in
  `watcher_brain.lua`): three flying the Market's lanes (`map.watchers`;
  over a stall a player's rounds would stop at its wall, so their beats
  keep to the lanes and they never hang over anything solid). 20 health,
  no gun. A 70-degree cone out to 440 px that sees over the stalls; a
  player in it is followed (hung over from 140 px) and called in: the
  nearest three of Halcyon's officers not holding a post (within 1100 px)
  go to look, again every 6 s while it still has them (a magenta ping and
  two beeps). Only players can shoot them down: the factions' rounds pass
  under them (the gangers shooting at them, or strays from the fights
  below, had them all down before any player got near). The sparkers go
  for them: an EMP knocks one out for 5 s. Still to come: interceptors and
  war-rigs; per-faction voices; and breach (blinding a drone).

## Decisions

| Question | Decision |
| --- | --- |
| Whose side are you on? | **Nobody's, and nobody is on yours.** No faction choice, no branching. Both factions want you dead, and so does your fixer. |
| Parody or its own thing? | **Its own thing in the style.** Original names, no direct jokes on one game the way A-Man is on Half-Life. |
| How long? | **Five maps**, like A-Man's trail. |
| Does VEX die? | **No. She escapes into the net** at the end, to set up a sequel quest line. |
| What happens to the Shard? | **Undecided.** Keep it, broadcast it, or something else. It decides the last screen's line and maybe the reward (see "Open questions"). |

## Logline

Grey City has two powers, and they've been at war for 40 years. You're a
nobody courier, and you just picked up the one thing that proves the war is
staged. Now both sides want you dead, and so does the voice in your dashboard.

## The cast

None of them are on your side.

- **VEX**, your fixer. A voice and a glitching face that lives in your
  earpiece, and later your car's dashboard. She gave you the job, she talks you through every level, and she
  sounds like she's helping. She isn't: she sells your location to whoever
  pays most, and every "helpful tip" comes just before a wave arrives. She
  fills A-Man's role in the quest: the intro screen portrait (glitching where
  his jumps), the chatter, and the last word. Colour: sickly green.
- **Halcyon Dynamics**, the corporation. Grey suits, drones, turrets, polite
  and clinical. Colour: magenta on grey.
  - **Director Saye**, its head. No visible implants, and somehow the
    scariest one in the city.
- **The Static**, the street. A gang more machine than people: shotguns,
  cyber-limbs, war-rigs. Colour: cyan on chrome.
  - **Kilowatt**, its leader. Loud, huge, with a reactor where a heart used
    to be.
- **The Shard**, the package. A data chip holding a recording of Saye and
  Kilowatt splitting the profits from 40 years of selling weapons to each
  other. The feud is a business, and you're holding the receipts.

## Character design

### VEX

**Who she is.** A fixer nobody has met in person, and nobody alive ever
will. Years ago she uploaded herself and kept the business. She lives in
whatever is connected: your earpiece, your car's dashboard, the market's screens, the
tower's systems, and at the end the net itself. She doesn't hate you. You
are a job, and jobs have margins. She calls you "courier" and never by name.

**Portrait** (64x72, primitives on a canvas scaled up with nearest
filtering, like `a-man/face.lua`): a hologram on a dashboard screen, head and
shoulders.

- Hair: a hard-cut black bob with a green sheen, long on her left and down
  past the jaw, shaved to stubble on her right. Blunt fringe down to the
  brows.
- Face: pale, grey-green under the hologram's tint, narrow and calm.
- Eyes: her left one is natural and dark. Her right one is a ring optic that
  glows green with a bright pinpoint.
- Mouth: a thin smile, a little too wide, that never moves much.
- A data-port tattoo: a green circuit line running from the corner of her
  mouth down to her chin.
- Collar: a high-necked dark jacket with glowing green seams.
- Over it all: a faint green wash, rolling scanlines, and now and then a
  slice of her slipping sideways.

| Colour | Use |
| --- | --- |
| `#08110d` | screen behind her |
| `#b8c6bc` / `#8d9c92` | skin, shade |
| `#0e1d17` / `#25463a` | hair, its sheen |
| `#4a5c53` | the shaved side |
| `#262c30` / `#171b1e` | jacket |
| `#6dff9a` | optic, seams, tattoo, scanline wash (her green) |
| `#ff3ec8` | the tell when she sells you to Halcyon |
| `#2ee6ff` | the tell when she sells you to the Static |

**Animation.** Blinks; her natural eye glances, the optic never moves. Small
slices slip sideways now and then. While she talks, a slice slips on each
emphasised word. She freezes for a few frames now and then, as if buffering.

**The tell (gameplay).** When she sells your location, a ghost of her splits
off in the buyer's colour (magenta for Halcyon, cyan for the Static) and her
slices jitter harder, for a second or two, while she keeps talking as if
nothing happened. A few seconds later that faction's wave arrives. New players
read it as a glitch; those who have learnt it get a warning and the colour of
who is coming. The tell is the story told through the HUD: she is lying to
you, and the screen shows it.

**Voice.** Warm, quick, reassuring, a customer-service tone. Short sentences.
She praises you a lot. She is always eating something or doing something else
while you are being shot at. Her lies are specific and confident; her truths
come out as asides. Her sound is a soft modem chirp with a falling pitch at
the end of each line, on its own sound channel.

**Chatter** (picked by category and index on the host, like
`a-man/radio.lua`; it shows on the HUD next to her small portrait, not over
anyone's head):

| Category | When | Examples |
| --- | --- | --- |
| `tip` | Before a wave, often with the tell | "Take the left exit, courier. It's quiet." / "Nobody uses the service stairs. Trust me." / "Park it there. Safest block in the city." |
| `praise` | A wave cleared | "Look at you. Five stars." / "See? I told you that'd work out." / "That's why I hire the best. Well, the available." |
| `aside` | Now and then, the truth slipping out | "...yes, eastbound, grey car. Oh. You're still on?" / "Sorry, other call. Unrelated." / "Hold on, someone's bidding. Not on you." |
| `down` | A player goes down | "Oof. I'll put that on your tab." / "Get up. The job's not done and neither are you." |
| `breach` | A player starts a breach | "Easy, that's my network you're poking." / "Need a hand? No? Fine." |
| `callback` | When a lie is found out | "In fairness, it was quiet. Before." / "Okay, *mostly* safe." |

**Intro screen lines** (one per level; the quest picks by index, like
`a-man/screen.lua`):

1. The Drop: "Hey, courier. Nice earpiece. I'm in it now. Run."
2. The Market: "Crowded in there. Good. Crowds are safe. Usually."
3. The Overpass: "I found you a shortcut. You're going to love it."
4. Halcyon Tower: "Their security is a mess. I'll get you in. Getting out is on you."
5. The Roof: "Funny thing about the receipts, courier. My name's on them too."

**Her arc, level by level.**

| Level | Where she lives | What she does |
| --- | --- | --- |
| 1 | Your earpiece | Boots up mid-chase, friendly. First tell at the end; few will notice. |
| 2 | The market's screens too | Tips, praise, tells before each wave. Her face appears on the stall screens around you. |
| 3 | The overpass's signs | The shortcut. Her biggest lie, and the first ambush with both sides waiting together. |
| 4 | The tower's systems | Guides you floor by floor; the doors she opens lead to rooms full of guards. She stops pretending much. |
| 5 | The roof's screens, then the net | Drops the act. The last fight. |

**On the Roof.** When Saye and Kilowatt are down, VEX locks the roof and comes
up huge: her face projected over the whole roof, in green with both tells
flickering at once. She can't be shot. She drives the tower's turrets, and
relay terminals around the edge of the roof keep her there. Players breach
the relays one by one while the turrets fire; she moves between the ones
left, and her portrait breaks up more with each one lost (more slips, colour
dropping out, frames missing). On the last relay she gets away: her face
shrinks to a single green pixel that streaks off the edge of the screen,
leaving her last line in the bubble: "Nothing personal, courier." She is
never beaten for good; the sequel picks her up.

### Director Saye

**Who she is.** Head of Halcyon Dynamics for 40 years and somehow not a day
older. Calm, precise, never raises her voice. People say she's the only
person in Grey City without implants. The truth is that there is nothing left
of her to see: under the skin she is all Halcyon hardware, the best money
can buy, and she has kept a human face because it's good for business.

**Portrait** (64x72): head and shoulders, front on, perfectly still.

- Hair: short, swept back, silver-white, not a strand out of place.
- Face: pale, smooth, nearly expressionless. Thin rimless glasses that catch
  the light (a pinpoint glint on each lens).
- Mouth: a straight line. The only expression she has is a very slight
  narrowing of the eyes.
- Clothes: a grey suit, a white shirt buttoned to the top, a magenta pocket
  square: the only colour on her, Halcyon's colour.
- Phase 2: her cheek and lapel crack open to brushed chrome, lit magenta
  from inside, and a magenta light comes on behind one lens. Nothing else on
  her face changes.

Her portrait barely moves: an occasional blink, slow and exactly on a
rhythm. The stillness is the point; next to VEX's glitching and Kilowatt's
shaking, she is the frightening one.

| Colour | Use |
| --- | --- |
| `#14121a` | behind her |
| `#ddd6cf` / `#c9c2bc` | skin, shade |
| `#e9e9ee` / `#b9bcc4` | hair, its shade |
| `#6c727a` / `#5a5f66` | suit |
| `#e6e6ea` | shirt |
| `#ff3ec8` | pocket square; the glow under her skin |
| `#9aa0aa` / `#c8cdd5` | chrome under the cracks |

**Voice.** Corporate euphemism for everything, especially violence. She
never threatens; she schedules. She calls players "the contractor".

- "You've been let go."
- "Let's take this offline."
- "I'm afraid your position has been made redundant."
- "Security, please escort the contractor. Permanently."
- "We'll circle back to you." (as she backs off)
- Phase 2: "This is coming out of your severance."
- Down: "Noted."

**In the fight: at range.** She walks, never runs, and keeps her distance.

- **Executive drones**: three small drones orbit her and shoot at whoever is
  nearest (`bullet`). Shoot them down and she calls more after a while.
- **Sightline**: she raises her pistol and a thin magenta line marks where
  her shot is going, for a second. Then a single heavy round down that line
  (`bullet`, hits hard). Step off the line to dodge it.
- **Restructuring**: she drops a sentry turret where she stands and walks
  away from it.
- Phase 2 (half health): her skin cracks. The sightline takes half as long,
  she fires two at once in a V, and she walks faster.

**Before the Roof.** She is on the tower's screens through level 4, talking
to the guards, and to you, about "an unscheduled visitor".

### Kilowatt

**Who he is.** Leader of the Static: huge, loud, and more machine than man.
His heart was replaced with a small reactor years ago and he hasn't slowed
down since. He loves a fight the way other people love a meal. He knows the
feud is a business, and doesn't care: he gets to fight every day and gets
paid for it.

**Portrait** (64x72): fills the frame, leaning in.

- Hair: a mohawk of thick black cables, each with a glowing cyan tip.
- Face: broad, warm brown, heavy brow.
- Eyes: his left one is natural, wide and wild. His right one is a cyan visor
  bar that pulses with his reactor.
- Jaw: the whole lower jaw is chrome, with a grille of steel teeth fixed in
  a grin.
- Body: a neck as wide as his head, and a chrome cage over his chest with
  the reactor glowing cyan inside, pulsing like a heartbeat.
- Phase 2: the reactor runs hot, pulsing fast, cyan arcs spark off his
  cables and shoulders, and the whole portrait shakes.

| Colour | Use |
| --- | --- |
| `#0c1418` | behind him |
| `#7a5a44` / `#6a4c38` | skin, shade |
| `#20262a` | cables |
| `#8a939c` / `#b5bdc4` | chrome jaw, cage |
| `#d8dde2` | teeth |
| `#2ee6ff` / `#c8fbff` | cable tips, visor, reactor, arcs |

**Voice.** Loud. Laughs at everything, including getting shot. Calls players
"spark" and means it fondly, sort of.

- "THERE you are, spark!"
- "Hold still, I just wanna hug you. Hard."
- "Ha! That tickled. Do it again."
- "You run like a corp. Fight like one too?"
- Venting: "Ooh, hot hot hot, gimme a second."
- Phase 2: "Now we're LIT!"
- Down: "...good fight, spark."

**In the fight: up close.**

- **Charge**: he lowers his head and runs at whoever is nearest, a long straight
  line (`impact`). He can't turn once started; side-step it.
- **Ground slam**: a hop and a slam, with a cyan ring of shock rolling out
  (`shock`; jumping it isn't a thing, so be out of reach).
- **Arc whip**: a crackling line from his fist to a target and on to anyone
  near them (`shock`, chains up to 3).
- **Venting**: after every few attacks his chest cage opens and he stands
  steaming for 3 s. Hits on his reactor then do double damage. This is the
  window.
- Phase 2 (half health): no cooldown between charges, the slam's ring
  travels further, and he vents less often but for longer.

**Before the Roof.** He makes a cameo on the Overpass (level 3), riding the
lead war-rig past you, laughing, and leaping off it onto the road as it
crashes.

### Saye and Kilowatt together: the Roof

Two bosses with two health bars, fighting as partners. Their portraits sit
side by side on the boss card when the fight starts.

- **They cover each other.** Shooting Saye sends Kilowatt charging at you;
  standing next to Kilowatt draws Saye's sightline. The way to win is to
  split the group: some keep Kilowatt busy while others take Saye.
- **Shield**: when Kilowatt vents, Saye parks her drones round him as a
  shield. Shoot the drones and the vent window opens properly.
- **When one falls**, the other rages:
  - Saye left alone: "Hostile takeover." Her drones double, and her sightline
    fires in bursts of three.
  - Kilowatt left alone: "MELTDOWN!" Permanent phase 2, and his slams leave
    shock patches on the ground for a few seconds.
- **They bicker.** Forty years of a business partnership come out mid-fight:
  - Kilowatt: "You said this kid was a nobody!" / Saye: "They are. It's a
    very expensive nobody."
  - Saye: "Your people destroyed my lobby." / Kilowatt: "It was ugly."
  - Kilowatt: "Sixty-forty, Saye. It was always supposed to be sixty-forty."
  - Saye: "Try to hit them, not the building."

When both are down, VEX takes the roof (see VEX, above).

Both drop a pickup when they go down and each raises `serverKill` with kind
"boss". What they drop, and the quest's reward, waits on the Shard's ending.

### The factions' troops

On the street everyone is drawn top down as a person (`src/body.lua`, 9 px
radius) in their faction's colours, with one thing each that makes their
role readable at a glance. All numbers here are starting points for tuning;
for scale, a Combine soldier has 60 health and drops 3 koins.

The two factions play differently on purpose:

| | Halcyon | The Static |
| --- | --- | --- |
| Style | Disciplined: formations, cover, procedure | Reckless: packs that rush, no cover, all noise |
| Colour | Grey, white helmets, a magenta visor strip | Dark mismatched clothes, chrome limbs, cyan cable tips |
| Brain | The Combine's (`a-man/combine.lua`) as it is: posts, squads, sweeps | A rusher: no posts, packs of 3-5 that close in and keep moving |
| Breach | Almost everything they field is tech: turrets, drones, cameras, cars | Mostly flesh and chrome: one breach target, the Brute's arm |
| Weak to | Flanking, breach, Static EMPs | Choke points, cover, Halcyon's shields |

So Halcyon fights are puzzles you can hack, and Static fights are brawls you
have to shoot your way through.

#### Halcyon

| Unit | Look | Health | Gun / attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Officer** | Grey armour, white helmet, magenta visor strip | 60 | SMG or pistol (`bullet`) | Rank and file: posts and squads of 3, like the Combine. Calls in what they see. |
| **Enforcer** | Darker grey, a riot shield in front with a magenta edge | 120 | Shotgun (`bullet`) | Slow. The shield stops everything from in front (within 70 degrees of straight on); flank him or blow him up (blasts and fire go through). Holds doorways and choke points: steps up on you, never more than 300 px from his post. |
| **Marksman** | Dark helmet, long rifle | 40 | Rifle (`bullet`, 40) | Rooftops and catwalks (the Overpass's gantries). A thin magenta line follows you for a second, leading a car, then holds still and bright for 0.4 s before he fires down it, like Saye's sightline but slower. Swerve while it holds. |
| **Watcher drone** | A small flying disc with a magenta eye and a sight cone | 20 | None | Flies a patrol, seeing over walls. Seeing you, it hangs over you and calls the nearest three officers on their feet, every 6 s. Shoot it down (only players' rounds reach it) or an EMP knocks it out for 5 s. Breach it to blind it. |
| **Sting drone** | Smaller, faster | 20 | Light gun (`bullet`), three-round bursts | Flies in swarms of 3: over the Overpass's gantries, making strafing runs through where you are going, faster than a car; later in the tower and with Saye. |
| **Sentry turret** | A grey tripod with a magenta lens | 80 | Burst fire (`bullet`) | Fixed. Breach it and it fights for you for 15 s. |
| **Assassin droid** | A lean white-plated robot, magenta visor band, rail pistol and a mono-blade; cloaked until it has you | 240 | Rail pistol bursts (`bullet`); a charged rail shot down a magenta sightline | The Drop's tunnel end. The Hunters' brain, quicker: keeps you at range, strafes, and dodges every round it sees coming (again 1.3 s later). Step off the sightline to dodge the rail shot. Two for one player, one more per extra human. |
| **Interceptor** | A grey SUV with a magenta and blue light bar | car, 220 | Rams; an officer leans out and shoots SMG bursts | The Overpass. Waits on the shoulder, then chases flat out, rams you once alongside and drops back to come again. Breach it parked and it stays dead. |

#### The Static

| Unit | Look | Health | Gun / attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Ganger** | Dark clothes, cyan-tipped cable hair, a chrome forearm | 50 | Shotgun or pistol (`bullet`) | Packs of 3-5 that run straight at the nearest target, shooting as they go. |
| **Ripper** | Lean, with two chrome blades out from the forearms | 40 | Blades (`melee`): a lunge 28, a slash 10 | Fast. Crouches for half a second with a cyan line showing where it will go, then lunges about 220 px (dodge it sideways). Slashes twice up close, then backs off to lunge again. Goes for whoever is alone. |
| **Brute** | A small Kilowatt: huge, a giant chrome arm, a cyan reactor glow | 150 | Punch (`impact`), a short charge | Slow, tough, soaks fire for the pack. Breach his arm and it locks up and he swings at whoever is next to him (often his own side) for 4 s. |
| **Sparker** | Hooded, a belt of cyan-glowing EMP grenades | 40 | EMP grenade (`shock`, 26 at the middle, 110 px) | Hangs back (230-400 px) and lobs EMPs, a cyan ring on the ground where each will land. Stuns a player near the middle. An EMP knocks out drones, turrets and cars in its blast for 5 s, Halcyon's and yours alike (once there are any). |
| **War-rig** | An armoured truck with a spiked chrome ram and a ganger on the back | car, 380 | Rams (`impact`); the ganger shoots a shotgun | The Overpass. Waits on the shoulder, then comes at you nose first, dropping back after each hit to come again; rams Halcyon's interceptors too while the two sides are at it. |

#### How they fight each other

While the factions are hostile (levels 1-2, see "Feud AI"), each picks its
target from the other faction as well as from players, the nearest it can
see. Their kits answer each other, so it pays to set them on each other:

- Sparkers' EMPs drop Halcyon's drones and turrets.
- Enforcers' shields stop a Static rush in a doorway.
- Rippers go round the shields and through the marksmen.
- War-rigs ram interceptors off the road.

On the Overpass (level 3) they only shoot each other when the other side
shoots first. From level 4 on they never do.

#### What they say

Same system as the Combine's radio (`a-man/radio.lua`): categories picked by
the host, a bubble over their heads, a sound per faction (a clipped radio
click for Halcyon, a distorted shout for the Static).

| Category | Halcyon | The Static |
| --- | --- | --- |
| `post` / `idle` | "Floor secure. Logging it." / "Code green, no visitors." | "Bored. Somebody start something." / "Who took my battery?" |
| `alert` (you) | "Unscheduled contractor, sector four." / "Visitor without a badge." | "COURIER! Get 'em!" / "There's the delivery!" |
| `alert` (the other side) | "Static in the lobby!" / "Gang activity, engage." | "Grey suits! Light 'em up!" / "Corp-meat at twelve!" |
| `down` | "Officer down. Filing it." / "We have a casualty." | "They got Ratchet!" / "Oh, that's gonna leave a mark." |
| `truce` (levels 3-4) | "Hold fire on the Static. Courier first." | "Easy, suit. Courier first, then you." |
| `breached` | "My drone's not responding." / "Turret's compromised!" | "Why's my ARM doing that?!" |

#### Who turns up where

| Level | Halcyon | The Static |
| --- | --- | --- |
| 1. The Drop | Officers at roadblocks, squads, guard stations with MG nests, assassin droids at the tunnel | Gangers on corners, packs, guard stations with MG nests |
| 2. The Market | Officers in squads, enforcers in the market's gates, watcher drones | Packs of gangers, rippers, a sparker or two |
| 3. The Overpass | Interceptors, sting drones strafing, marksmen on the gantries | War-rigs (Kilowatt rides the first), gangers at the ambush |
| 4. Halcyon Tower | Everything: officers, enforcers, marksmen, watchers, stings, turrets | Gangers, brutes and sparkers breaking in from below |
| 5. The Roof | Saye's sting drones and turrets | Brutes coming up the stairs while Kilowatt fights |

Each drops koins when it goes down (officers and gangers 3, the heavier
ones more) and maybe a pickup, and every kill raises `serverKill`.

## The arc: the feud breaks down as you go

The two factions start out at war with each other and end up fighting side by
side against you. The game gets lonelier as the story does.

| # | Map | Play | Who's after you |
| --- | --- | --- | --- |
| 1 | **The Drop**: downtown, night, rain | On foot, a chase across town with the Shard | Both sides, separately, also fighting each other |
| 2 | **The Market**: neon stalls, crowded, on foot | Get through a three-way firefight | Both sides; you survive by pulling them into each other |
| 3 | **The Overpass**: elevated highway over the grey | Driving: war-rigs ram you, drones strafe | Both sides, starting to hold fire on each other. VEX "finds you a shortcut" straight into an ambush |
| 4 | **Halcyon Tower**: on foot, stealth and hacking | Breach cameras, turrets and doors, and climb | Halcyon inside, the Static breaking in; they ignore each other now |
| 5 | **The Roof**: the finale | Saye and Kilowatt fight together, as a tag-team boss | Then VEX locks the roof and turns the tower's turrets on you |

### 1. The Drop

The job on the board: "Courier wanted. No questions." Everyone arrives
downtown at night in the rain. The Shard is waiting in a vending machine. Once
someone has it, both factions come for it and the level becomes a chase
across town to the exit, on foot: no cars on the Drop. VEX boots up in your
earpiece halfway through: her intro screen.

### 2. The Market

A dense on-foot market of neon stalls in a grey concrete block. Both factions
catch up at once. They shoot at each other as much as at you, and the way
through is to pull one side into the other: lead Static gangers into a Halcyon
checkpoint and watch from cover.

### 3. The Overpass

An elevated highway out over the city. Static war-rigs ram you, and Halcyon
drones strafe from above. The factions start holding fire on each other here.
VEX finds you "a shortcut" that runs straight into an ambush where both sides
are waiting together: the first sign they are working it out.

### 4. Halcyon Tower

On foot, mostly stealth and hacking, climbing floor by floor. Cameras,
turrets and locked doors are all breach targets. Halcyon guards the inside,
and the Static is breaking in from below. They no longer shoot each other;
they only want you.

### 5. The Roof

Saye and Kilowatt fight together as a tag-team boss: Saye at range with
drones and turrets, Kilowatt up close with his bulk. When they are down, VEX
locks the roof and turns the tower's turrets on everyone. The last phase is
breaching VEX out of the tower's systems while the turrets fire. You beat
her, but she escapes into the net with a parting line ("Nothing personal,
courier."), which sets up the sequel.

## Maps

Five new maps in city-map, one builder each beside A-Man's
(`city-map/outer_city.lua` and the rest), drawn by their own render file. Tiles
are 64 px (`Layout.TILE`). For scale: City 17 is 48x76 tiles, the Outer City
72x56, the Winding Road 76x224, the Citadel 84x112.

| Map key | Title | Size (tiles) | Played | Quest |
| --- | --- | --- | --- | --- |
| `drop` | The Drop | 64x96 | On foot | `cyber-feud` (on the board) |
| `market` | The Market | 56x56 | On foot | `cyber-feud-market` |
| `overpass` | The Overpass | 32x200 | Driven | `cyber-feud-overpass` |
| `tower` | Halcyon Tower | 48x112 | On foot | `cyber-feud-tower` |
| `roof` | The Roof | 36x36 | On foot, the arena | `cyber-feud-roof` |

Each quest's `next` is the following one, as A-Man's are; the Roof's star
goes home. Every map is night and rain. Everyone travels north (up the
screen), the way A-Man's trail does.

### Shared look

- Grey everywhere: concrete roofs in cold greys, dark wet streets.
- Rain on every map: streaks over everything, ripples in puddles, the
  neon reflected in the wet ground as smeared colour under the signs.
- Neon signs on building edges in the faction colour of whoever holds that
  block (magenta or cyan), plus a few in VEX's green where she has a screen.
  Pun signs: NOODLZ, CHROME 4 LESS, RIPPERDOC, NO REFUNDS, SOYLENT FRIED,
  KARMA KREDIT, MEAT (REAL*).
- Steam from vents, holo-ads flickering, cables strung across streets.
- A green screen anywhere means VEX can see you.
- Past the edge the city carries on (the surroundings feature's
  `grey_city.lua`, the Drop so far): blocks of towers with neon in the
  colour of whoever holds that side of town, street lamps, traffic going
  by both ways, a haze further out; at night only its lights show. Round
  the Market the same city is at war (`surroundings/turf_war.lua`): a front
  north to south in line with Noodle Square, the Static's west and
  Halcyon's east; no-man's-land either side of it in rubble, craters and
  burning towers; barricades across every street (the Static's junk walls,
  a drum alight, facing Halcyon's concrete), war-rigs and interceptors
  behind them, tracer bursts both ways, shells coming down, Halcyon's
  searchlights sweeping, and further back cyan tags over the Static's roofs
  and Halcyon's hexagon over its own. No traffic. It is heard too
  (`surroundings/war_sounds.lua`, its own "battle" volume): each burst and
  shell plays where it is seen, on the same clock, muffled the further off
  it is, and now and then the war further out than anything in sight.
- Overhead, every now and then, one of three flying machines crosses the
  sky (`cyber-feud/flyers.lua`, the Drop so far): Halcyon's aerodyne on
  four ducted fans with its searchlight sweeping the streets, a cargo
  hauler with a container slung under it, an ad drone towing a holo
  billboard, each with its engine (`flyer_sounds.lua`). Scenery on each
  screen by itself.

### 1. The Drop (`drop`, 64x96, on foot)

Downtown. A grid of tall blocks with wide avenues, like the city's own, but
taller, darker and wetter. The west third is the Static's (cyan signs,
junk, burning drums, wrecks), the east third Halcyon's (clean, magenta signs,
bollards), and the middle avenue is the no-man's-land where they meet.

- **Arrival:** the bottom left, coming up out of a parking garage on foot
  (the cars stay below).
- **Downtown's crowd:** a thin crowd out late in the rain (the pedestrians
  feature, dressed by `map.crowdClothes`; no police), who scatter when the
  shooting starts and get caught in the crossfire.
- **The pickup:** a vending machine in a small plaza next to the garage. The
  first player to press F at it takes the Shard, and the chase begins: both
  factions are quiet until then.
- **The chase:** Halcyon roadblocks (barriers and officers) close some
  intersections and its guard stations hold the east; the Static's gangers
  hold the corners and their stations in the west. The way north changes
  depending on which roadblocks you dodge.
- **VEX boots up** halfway up the map (a zone line, like City 17's
  `map.zones`): her intro screen, in your earpiece.
- **The end:** a tunnel mouth at the top middle, with the biggest roadblock
  of all in front of it, held by Halcyon alone with its assassin droids. Break through and the EXIT star is in the tunnel: "THE MARKET".

### 2. The Market (`market`, 56x56, on foot)

A huge covered market in a concrete block: narrow lanes between stalls
(solid cover), crates and noodle carts (cover), canopies drawn over the lanes
with gaps where the rain comes through.

- **Arrival:** the south end, out of the tunnel; cars are left behind at the
  entrance.
- **Halcyon** has cordoned the south gate and the east side: posts at the
  gates, squads in the lanes, watcher drones over the canopies.
- **The Static** holds the west: their chop shop, packs roaming out of it.
- **Noodle Square** in the middle: an open plaza under a giant screen where
  VEX's face appears. Both sides' lanes meet here; this is where the big
  three-way fights happen.
- **The end:** the north gate, a loading dock with parked cars waiting. The
  EXIT star: "THE OVERPASS".

### 3. The Overpass (`overpass`, 32x200, driven)

An elevated highway, long and narrow, with the city a drop away on both
sides (the edges are solid, drawn as a long fall with lights far below).
Four lanes, with wrecks and stalled traffic as obstacles.

- **Arrival:** the bottom, onto the on-ramp, everyone behind the wheel of a
  Courier (`vehicles/models/courier.lua`): VEX's armoured runner, a gunmetal
  wedge with green neon and a minigun turret the driver fires (the model's
  `gun`). The map lends one to everyone (city-map's `loaner` with
  `issued`): their own car waits out of the world until they leave. Kilowatt's war-rig is the first
  thing you see: it roars past, he laughs, and he leaps off onto the road
  before it crashes ahead.
- **Gantries** cross the road every 30 tiles or so; Halcyon marksmen stand
  on them (drawn over the cars), and sting drones strafe between them.
- **Construction** squeezes the road to one lane in places.
- **The shortcut:** two thirds of the way up, VEX says to take the off-ramp.
  It loops round into the Knot, a dead-end interchange where both factions
  wait together: the ambush. Fight out and the loop rejoins the highway.
  Taking the main road instead also works, but it is longer and has more
  roadblocks; VEX sells you either way.
- **The end:** the highway runs into Halcyon Tower's garage ramp. The EXIT
  star: "HALCYON TOWER".

### 4. Halcyon Tower (`tower`, 48x112, on foot)

The tower, cut through and stacked: six floors laid out as six bands up the
map, each joined to the next by a stairwell at alternating ends, so the climb
zigzags.

| Floor | What's there |
| --- | --- |
| Lobby | Marble, a reception desk, the Static smashing in through the front with a war-rig. Halcyon holding the lifts. |
| Offices | Cubicles as cover, glass walls, watcher drones. |
| Servers | Rows of racks, breach terminals, sting drones. Dark, lit by blinking lights. |
| Labs | Glass tanks, spare chrome bodies on racks (Saye's), turrets. |
| Security | The guard floor: enforcers, marksmen, a lot of turrets. |
| Executive | Carpet, a long boardroom table, Saye's office with a window wall. Saye on the screens. |

- Each floor's stair door is locked. Breach the terminal beside it to open it,
  or let VEX open it for you, which opens a room full of guards instead.
- The Static come up from below the whole way, so the floors behind you
  aren't safe.
- **The end:** the executive lift up to the roof. The EXIT star: "THE ROOF".

### 5. The Roof (`roof`, 36x36, the arena)

The top of the tower, square, open to the rain.

- A helipad in the middle (open ground).
- AC units, vents and antenna masts as cover, spread round.
- Four relay terminals near the corners (VEX's phase).
- A giant holo-billboard along the north edge, where VEX's face shows.
- The stairs at the south edge, where Static brutes come up during the fight.
- The edges are solid: a parapet, and the city far below.

**The end:** when VEX gets away, a HOME star comes up on the helipad.

## Mechanics

### Feud AI

Two enemy factions with a hostility between them that changes per level:

| Level | Halcyon vs. the Static |
| --- | --- |
| 1, 2 | Fully hostile: they shoot each other on sight |
| 3 | Sometimes hold fire |
| 4 | Share targets: ignore each other, hunt you |
| 5 | One team, the bosses fighting together |

A-Man's Combine is the only enemy side on its maps, so this is new. The
soldiers' brain (`a-man/combine.lua`, with D-Day's sight cones) is the place
to start; what it needs is a faction on each soldier and a way to choose
targets from the other faction as well as from players.

### Breach (the hacking mini-game)

On foot, press F (`actionTaken`) at a terminal, turret, camera or parked car to
get a small hex-code grid: pick a given sequence against a timer. On success:

- a turret switches to your side for a while
- a camera goes blind
- a door opens
- a car is bricked (stops dead)

The world does not pause while you breach, so in co-op someone covers the
hacker. As always, the server decides whether a breach succeeds; the client
sends only its picks.

### VEX's chatter

Like the Combine's radio (`a-man/radio.lua`): lines in a bubble with a
sound, plus a burst of HUD glitch on her big lines. Her lines sound helpful
and turn out to be lies, and some get called back later ("Take the left exit,
it's quiet" -> the ambush). Her intro screen works like A-Man's
(`a-man/screen.lua`): her portrait and a line picked by index, glitching
where his jumps.

## Look

- Grey concrete, constant rain, wet streets that catch the neon.
- Neon only in faction colours (magenta for Halcyon, cyan for the Static),
  plus VEX's green on the HUD. Anywhere you see colour, there's someone who
  wants you dead.
- Pun shop signs: NOODLZ, CHROME 4 LESS, RIPPERDOC, NO REFUNDS.
- Each map gets its own theme music, as A-Man's do.

## Open questions

- **The Shard's ending.** Keep it, broadcast it to the city, or something else.
  It decides the last screen's line, and maybe the reward.
- **The reward.** One idea is the Shard as a legendary ability: one use per
  fight turns two enemies on each other, a small feud of your own. Whatever it
  is, it is equipment, so it has tiers (`tierStats`, read through
  `Tiers.apply`).
- **The sequel.** VEX gets away; where she goes is for that quest line.

## Next steps

1. Character design: VEX, Saye, Kilowatt and the factions' troops (done).
2. Map design for the five levels (done; city-map builds and draws them).
3. Feud AI and breach as their own pieces, since later quests can use them
   too.
