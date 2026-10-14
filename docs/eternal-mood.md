# Eternal Mood design

A quest line in the shape of Cyber Feud's (`docs/cyber-feud.md`): a job on
the board, five maps chained by each quest's `next`, a banner and tagline on
each map, an intro screen, story beats said over the HUD, troops' barks, a
boss on every level, and a last word. The look is a 90s demon-blasting shooter on a
moon base and in hell, played the way A-Man plays Half-Life: a parody with
its own names, not the real ones.

Status: story, bosses, maps and the horde designed. Built so far (each a
branch off `feature/eternal-mood`):

- `feature/eternal-mood-fobos`: Fobos Base (`fobos`,
  `city-map/eternal_mood.lua`, drawn by `render_eternal_mood.lua`), its
  quest on the board ("Pest control") and HOME star, the moon past its edge
  (surroundings' `fobos_moon.lua`), and the `eternal-mood` feature
  finishing the level when someone reaches the Hangar's lift. Every room in
  the doc's Fobos Base is there, plus two the Ring leads to: Crew Quarters
  and the Mess. In a red dark (the night feature, with the map's own
  ambient), lit by red-orange strip lights, red screens, the reactor's
  orange core, the sludge's green and red alarm lamps over every door
  (they don't sweep yet); every surface has a red cast.
- `feature/eternal-mood-horde`: the possessed and the imps on Fobos Base
  (`eternal-mood/horde.lua`, `possessed_brain.lua`, `imp_brain.lua`,
  `fireballs.lua`, placed by the map's `horde`). The possessed are one
  brain with three ranks (`Brain.RANKS`): staffers (40 health, a pistol,
  8 a round), guards (60, a shotgun, six pellets of 7, kept within 560 px
  of their doorway) and the overtime guy (100, a chaingun spinning up for
  0.6 s, then 6 a round eight times a second, sweeping after you at 1.6
  rad/s, within 260 px of his post). Each stands at its post facing its
  `watch`, sees in a cone and a little all round, and on spotting somebody
  groans: the possessed within 380 px come and look. Lost, they search
  where they last saw you for 6 s and go back. Imps (60 health) wait in
  five floor vents (two in the Reactor, one in Toxic Storage, two in the
  Hangar): the first player within 420 px bursts the grille and its pack
  crawls out, one every 0.7 s (3 or 2, one more for each human past the
  first). They hunt the nearest player, keep 150-380 px off, strafe, and
  every 1.8-2.8 s hold a fireball up for 0.45 s (drawn) and throw it at
  where you stand (330 px/s, 14 `fire`); up close they claw (10 `melee`).
  Nothing of Heck's hurts anything else of Heck's. Twenty-five of the
  possessed on Fobos Base: none in the Lab; staffers about the Crew
  Quarters, the Mess, the Ring, the Offices' desks, the Reactor's catwalk
  and Toxic Storage; a guard inside each doorway up from the Ring; the
  overtime guy by the Hangar's lift with two guards and three staffers.
  No Pinky yet.
- `feature/eternal-mood-floor-manager`: Fobos Base's boss
  (`eternal-mood/floor_manager.lua`, his brain `floor_manager_brain.lua`,
  placed by the map's `horde.boss`; FM_ messages), the line's Arachnotron.
  The UAC's shift supervisor, promoted out of his body: his brain in a
  glass dome on a four-legged spider walker, a plasma cannon under the
  front, the clipboard taped on (drawn at 1.5x, 34 px across). 2250 health
  for one human (Volt has 1800). He waits on the Hangar's lift, facing the
  room, until a player walks into the Hangar or shoots him ("You're not on
  the rota."). He walks any way on his legs (90 px/s), keeps 340 px off
  whoever he has and side-steps. Plasma: within 700 px, facing them, the
  cannon charges for 0.55 s (glowing, a faint green line where it points),
  then a stream of ten bolts 0.09 s apart (fireballs.lua's "plasma", 520
  px/s, 9 `shock` each), the aim dragging after them at 1.1 rad/s: keep
  moving across it. Every 3.2 s, 2.4 in phase 2 (under half), when three
  streams go out in a fan (0.28 rad either side); 15 breath. Stomp: within
  120 px the legs rear up for 0.6 s (a ring on the floor) and come down on
  everyone within 115 px (30 `impact`, a 140 px shove); every 2.2 s. The
  cannon has 600 health of its own (scaled like his): a round within 18 px
  of its end hits it, and him for a quarter; shot off ("My presentation!")
  it lies smoking where it fell, he has no plasma and closes in to stomp at
  1.35 times his pace, and his bar says CANNON DOWN. Quick meetings at two
  thirds and a third of his health: two staffers (Bosses.plus) through each
  of the Hangar's three doorways, at whoever he has (horde.lua's
  `serverCall`). The bosses' standard (breath: winded he walks at 40; the
  boss bar; a medkit when badly hurt, "statutory break"; dodging
  abilities; `serverKill` "boss", 25 koins and two pickups). The lift is
  OUT OF SERVICE while he is up (the way on doesn't finish the level);
  down, his walker lies smoking, legs splayed and the dome cracked and
  empty, and the lift works.

- `feature/eternal-mood-patrols`: the Floor Manager made tougher (1500 ->
  2250 health, his cannon 300 -> 600), and patrols of the possessed on
  Fobos Base (the map's `horde.patrols`): a squad walking a loop (squads
  since `feature/eternal-mood-smarter-possessed`), doing everything else as
  the posts do. A guard on patrol has no leash. Five, twelve more of the possessed: a guard and two staffers up
  and down the Ring, two staffers round the Offices' desks, a guard and a
  staffer round the Reactor's catwalk, two staffers through Toxic Storage,
  and a guard and two staffers round the Hangar's floor.

- `feature/eternal-mood-interns`: the Interns, the melee mob
  (`eternal-mood/intern_brain.lua`, in horde.lua, kind `z` on the wire;
  the map's `horde.mobs`). 20 health, no gun: they shamble at 85 px/s and
  lurch at 140 within 200 px, raise their arms for 0.35 s within 24 px and
  claw (7 `melee`, once a second each; 55 and 100 px/s before
  `feature/eternal-mood-faster-interns`), keeping 22 px apart so a mob comes
  as a crowd. A mob stands about its spot, swaying, until a player comes
  within its `wake` px or within 520 px with a clear line to it, or one of
  it is hurt: then all of it comes at once and one shouts ("BRAAAINS...
  storming session!"). 1 koin each, and a pickup only now and then (15%).
  Five mobs on Fobos Base, 29 for one human (one more each for each human
  past the first): 6 asleep in the Crew Quarters, 8 at lunch in the Mess, 5
  at the Ring's west end, 5 in Toxic Storage, 5 in the Offices' far corner.
  The Floor Manager's meetings bring a file of three interns (Bosses.plus)
  in behind the staffer at each doorway (his staffers down from two to one
  a doorway).

- `feature/eternal-mood-visuals`: Fobos Base looked at again. Its props
  are drawn every frame at full size by the eternal-mood feature
  (render_eternal_mood.lua's `drawProps`, culled to the view; the feature's
  priority is 27, over the map canvas and under corpses and pickups), not
  into the half-size map canvas, which keeps only the floors and walls: no
  more soft props, and the posters are sharp. Some of it moves: the
  reactor's core breathes (`corePulse`) under a halo (soft rings, three arcs
  of energy running round, sparks flung off) and its glow in the dark
  breathes with it; its vanes turn; the sludge bubbles; the consoles'
  screens scroll and blink. The alarm lamps over the doors turn like
  beacons (`alarmFlash`: a dim red always, a flash and a sweeping beam as
  each comes round). One strip light in four is on the blink
  (`map.flickers`): on, with a stutter every so often; one in twelve has
  all but died, with the odd flash. And the mess the night left, scattered
  per room (eternal_mood.lua's `CLUTTER`, kept to open floor, off the
  doorways and away from everyone's spots and routes): bins (solid),
  tipped bins spilling rubbish, trash, memos, blood, scorch marks, glass
  that glints, office chairs knocked over.

- `feature/eternal-mood-smarter-possessed`: the possessed fight like City
  17's Combine (a-man/combine.lua, ported into possessed_brain.lua, their
  own), each rank as much as suits it (`Brain.RANKS`' `sweeps`, `cover`,
  `pins`, `sweepsOut`, `holds`, `grenadier`). Guards sweep their cones
  across the doorways they hold (55 degrees either way, 6 s there and
  back), fight from cover near where they are (hide 1.2-2.6 s, step out up
  to 90 px to shoot for 1.4-2.2 s, duck back at once if hit), go to ground
  when hit by somebody none of them can see (everyone who knows to within
  400 px, a "siege"; after 8 s quiet up to three of the guards go out to
  sweep where it came from; 30 s of quiet, or anyone spotting the shooter,
  ends it), and one in three carries a grenade (thrown now and then at
  whoever it has between 140 px and the grenade's range, or at where it just
  lost somebody; never onto the horde). The overtime guy holds his ground
  round his post from cover, spinning up each time he steps out, and goes
  to ground but never out on a sweep. Staffers stay office zombies, but
  everyone answers the alarm when one of them goes down (those within 520
  px go to look where he fell), cones widen once on edge, and the patrols
  are squads: a leader walking the beat with the rest a step behind him
  either side, all of them going to where any one of them is shooting. New
  lines for it ("Taking my break!", "Here's your severance!", "Let's circle
  back to that.").

- `feature/eternal-mood-intro`: the Voice's intro screen
  (`eternal-mood/screen.lua`, the Mood Slayer's face in `face.lua`), up on
  arrival for 10 s or until a key takes it down, over the whole HUD
  (`drawScreen`) with the world softened behind it, picked by the quest's
  `introLine` (`Story.lines`). Laid out like VEX's: ETERNAL MOOD and the
  level's number, THE MOOD SLAYER cut from hot metal, "Rip. Tear. Five more
  minutes.", and the line typed out in a thought bubble trailing off to
  him (the Voice is in his head). Black going to Heck's red at the bottom,
  embers rising, a power chord as it comes up. His face: a green helmet,
  an amber visor and one eye behind it, heavy-lidded, blinking slowly,
  every so often nodding off (the lid shutting, the helmet sinking) and
  jerking awake wide-eyed; `drowsy` grows with the level (0.2 on Fobos
  Base, 0.95 at the Snooze Gate), so he nods more the further down the
  dream it is.

- Fobos Base's theme (`eternal-mood/theme_fobos.lua`, on the same branch
  as the intro screen): rip-and-tear metal rendered by src/audio/synth.lua,
  128 BPM in A minor (Phrygian where it hurts), tuned down to a low A. It
  comes in the moment the Voice's intro screen goes. First the dream, once
  (`renderIntro`, ~2 s): a lullaby on a music box over a snore, the floor
  dropping out in a diving synth bass. Then the loop (`render`, ~60 s):
  riff A, low A chugs grouped three, three and two against the beat with
  the kick locked to them and the snare on three, the synth bass diving
  every other bar end; riff B over double kick leaning on the flat second
  (B flat), high stabs and gated noise creeping in; the chorus, open
  power chords A, F, G, E (B flat to turn it round) under a screaming lead;
  a half-time breakdown on the lowest A, gated noise stuttering; riff A
  into the top. Its own riffs, none of anybody else's. Rendered on
  arriving, under the intro screen (about 1.4 s).

- `feature/eternal-mood-boss-look`: the Floor Manager redrawn
  (`eternal-mood/floor_manager_look.lua`), at world size and 30% bigger
  (his hull 40 px across for hits, the cannon's end 68 px out). Four legs
  that walk: each foot stays planted while the body moves over it and
  steps (0.18 s) once it is left 44 px behind its rest spot, the diagonal
  pairs taking turns (80 px behind, it steps anyway); thigh and shin with a
  hydraulic ram, bolted knees, three claws, the foot's shadow left on the
  floor while it lifts; rearing for a stomp, the feet pulled in and up.
  An armoured octagon with hazard stripes round the rim, rivets, status
  lights blinking, two exhaust stacks puffing (more when he strains or is
  hurt); the glass dome with the brain in it, folded, veined and pulsing,
  an eye on a stalk; the plasma cannon under the front, twin barrels in
  coils glowing as it charges, a ball of plasma swelling at the muzzle, a
  flash as it streams; the clipboard taped on. The dome cracks under half
  his health, again under a quarter, when he sparks too. Shot off, the
  cannon leaves a stump with its cables swinging and sparking. His wreck:
  legs sprawled flat, the hull dark, the dome smashed to shards round its
  rim, smoke going up.

- `feature/eternal-mood-earth`: Heck on Earth (`earth`, 40x160, on foot,
  `city-map/eternal_mood.lua`'s `buildEarth`), quest `eternal-mood-earth`
  (introLine 2) behind Fobos Base's lift (EXIT star "HECK ON EARTH"), its
  HOME star by the shuttle, and the burning city past its edge
  (surroundings' `heck_on_earth.lua`). The Depot, the Suburbs, Downtown, the
  Crater and the Boulevard as above, the starport's gate finishing the level
  (and, for now, going home). Floors per patch (`map.grounds`: asphalt with
  lane markings and zebra crossings, sidewalk slabs, dead lawns, cracked
  road) and roofs per building (`map.roofs`: pitched houses, flat tower
  roofs with air-con and water tanks, the fallen overpass, ruins, dead
  hedges), in the same red dark (its own ambient). Lit by street lamps
  (some dead, some on the blink), fires on burning roofs, wrecks and the
  side streets' barricades (flames that dance and never go out), and the
  Crater's lava. The horde from Fobos Base fills it: 38 of the possessed
  (25 posts, 5 patrols), 12 interns' mobs (69 for one human), imps under
  six manholes and four cracks round the Crater (an open manhole has its
  cover thrown aside; a crack is torn open, glowing). Billboards over the
  side streets: SOFA SALE!, HECK: NOW HIRING, MIND THE LAVA. It played
  Fobos Base's theme until `feature/eternal-mood-earth-theme`. No boss yet:
  the gate is open.

- `feature/eternal-mood-cacodaemon`: the Cacodaemon, the first of the
  heavy demons, not a boss (`eternal-mood/cacodaemon_brain.lua`, in
  horde.lua, kind `c` on the wire; the map's `horde.cacos`, flocks of
  `count` for one human, Bosses.plus). A floating red ball with lumps on
  its hide, bone horns round the back, one green eye and a mouth of teeth
  across its front, drawn over everyone a little above its shadow. 220
  health, 26 px across for hits. It floats, so it flies straight over
  walls, roofs and lava (70 px/s, kept in the map); it hangs about its spot
  until a player comes within its `wake` px, is seen across open ground
  within 700 px, or it is hurt, and its flock comes with it ("GRAAAWRBLE!",
  a deep wet roar). It circles its target 200-400 px off, making for open
  ground, and every 2.6-3.8 s, with a clear line within 640 px, opens its
  mouth for 0.5 s (the tell: the mouth gapes, fire welling up in it, the
  eye wide) and spits a ball of fire at where you stand (fireballs.lua's
  "spit": 260 px/s, 14 px, 24 `fire`). Shot with its mouth open it takes
  1.5 times the damage, squeals and reels back spinning for 0.9 s without
  spitting. Within 24 px of its edge it bites: the mouth opens for 0.3 s,
  then 30 `melee` (every 1.2 s). Down, it bursts flat on the ground, its
  eye shut, its tongue out; 8 koins, `serverKill` "demon". Nine on Heck on
  Earth: one over the Suburbs' houses, three Downtown, two over the
  Crater's lava, two over the Boulevard's towers. Over a roof it can't be
  shot (rounds stop at walls) but can't spit either.

- `feature/eternal-mood-mancubus`: Heck on Earth's boss, the Mancouchbus
  (`eternal-mood/mancubus.lua`, his brain `mancubus_brain.lua`, his look
  `mancubus_look.lua`; MC_ messages; the map's `horde.boss`, now with a
  `kind`: "floor-manager" on Fobos Base, "mancubus" here), the line's
  Mancubus with two rocket launchers. A huge fat demon in a brown leather
  recliner leant right back on tank treads, feet up, belly first, his
  little horned head on the headrest, a TV remote on the armrest and a can
  in the cup holder; his arms end in rocket launchers as long as he is.
  3400 health for one human (the Floor Manager has 2250), 46 px across. He
  sits in front of the starport's gate, which is CLOSED (a red and white
  boom across it) until he is down; he wakes when a player comes up the
  Boulevard past row 30 ("Oi. You're blocking the telly.") or shoots him,
  and never leaves the Boulevard (nobody on it, he rolls back to his spot).
  On treads he drives only forwards and back (60 px/s, backwards at 0.6)
  and turns slowly (0.9 rad/s), keeping 380 px off whoever he has. Volley:
  the launchers come up whining and glowing for 0.8 s, then a rocket from
  each arm in turn, three pairs (four in phase 2, under half), 0.28 s
  apart, at where you stand, his body coming round after you. Sweep (35%
  of attacks, 50% in phase 2): the launchers come up wide for 1 s, then
  seven rockets in a fan 0.75 rad either side of his aim, 0.14 s apart,
  one side to the other: find the gap. His rockets are the weapons
  feature's rocket launcher with his numbers (430 px/s, a 100 px blast of
  40 `explosive`, ownerless and the horde's, so they never hurt Heck), and
  they stop on walls and cover. Every 2.6-3.4 s (1.8-2.5 in phase 2), 18
  breath a go. Bump: within 130 px he leans back for 0.55 s (a ring on the
  road in front of him) and lurches: 35 `impact` and a 170 px shove, every
  2.4 s. At two thirds and a third of his health, "Lads! Snacks have
  arrived!": two Cacodaemons (Bosses.plus) come in awake over the roofs
  either side of you (horde.lua's `serverCall` "caco"). His back is the
  recliner: a round landing behind his middle does double ("Not the
  upholstery!"). The bosses' standard (breath: winded he crawls at 30; the
  boss bar; a medkit when badly hurt, "Snack break."; dodging abilities;
  `serverKill` "boss", 35 koins and two pickups). Down ("...five... more...
  minutes..."), his recliner lies on its back smoking, the boom goes up,
  and the gate finishes the level. The Boulevard's planters and sandbags
  moved back off the gate to give him room.

- `feature/eternal-mood-earth-theme`: Heck on Earth's own theme
  (`eternal-mood/theme_earth.lua`, played like Fobos Base's: the dream
  once, then the loop; rendered on arriving in about 1.3 s). Rush hour:
  faster than Fobos Base's, thrash where that one is heavy, 150 BPM in E
  minor. The dream (~3 s, `renderIntro`): a cheery major-key TV jingle,
  the sofa sale off the billboards, on bells, over a phone buzzing on a
  table; then the jingle dragged down like a tape stopping as an air-raid
  siren comes up and the bass drops out. The loop (~51 s, `render`): a
  gallop on the low E (an eighth and two sixteenths, the kick locked to
  it, the root moving E, G, E, C), a synth bass dive every four bars; a
  tremolo-picked riff in E Phrygian (the flat second, F) over a thrash beat,
  the low string on each beat, an air-raid siren rising behind its second
  half; the chorus, open chords E minor, C, D, B under a lead that slides
  up into every note like a siren; a stop-start breakdown on the lowest E,
  car horns blaring in its gaps, a siren into the last bar; and the gallop
  again into the top. Its own riffs, none of anybody else's.

- `feature/eternal-mood-foundry`: the Foundry (`foundry`, 56x64, on foot,
  `city-map/eternal_mood.lua`'s `buildFoundry`), quest
  `eternal-mood-foundry` (introLine 3) behind Earth's starport gate (EXIT
  star "THE FOUNDRY"), its HOME star by the shuttle's tail, the starport
  past its walls (surroundings' `starport_pads.lua`: tarmac, landing pads,
  runway lights blinking round them, the odd parked shuttle). Six rooms,
  bottom to top: the Landing Pad (the shuttle down from Earth, where
  everyone arrives), the Loading Bay (crates, barrels, a loader), the
  Front Office (Dr. Seek's glass booth with his brain in its jar on the
  desk, bubbling, a light blinking as he talks; desks, filing), the
  Conveyors, the Smelters (six vats of lava in two rows, chains hanging,
  Heck's rock and bone growing up through the grating, thicker north,
  rock spires) and the Crucible (a round pit of lava inside a stone ring,
  a lava moat round the ring with a stone bridge in from each side, the
  portal down into Heck behind it all: a ring of bones round a swirl of
  red; reaching it finishes the level, for now going home). North of the
  Conveyors the shed's steel walls are Heck's rock with bones in them
  (`map.heckFrom`). The Conveyors' three belts cross the whole hall,
  running east, west, east at 70 px/s (`map.belts`; the eternal-mood
  feature's `belts.lua`): whoever stands on one is carried, players and
  the possessed, interns and imps alike (the Cacodaemons float), into the
  wall if nothing stops them; walking against one (45) gets you nowhere,
  sprinting (170) does. Drawn running: ribs and chevrons going by, lumps of
  glowing ore riding along. Crates riding the belts as moving cover are
  left for later (cover is fixed in place). The horde: 17 posts and three
  patrols of the possessed (24 for one human), six interns' mobs, imps in
  five vents (three in the Smelters, two in the Crucible), two Cacodaemons
  over the Crucible's pit. Fobos Base's theme for now; no Baron yet, so
  the portal was open.

- `feature/eternal-mood-baron`: the Foundry's boss, the Baron of Heck
  (`eternal-mood/baron.lua`, his brain `baron_brain.lua`, his look
  `baron_look.lua`; BR_ messages; the map's `horde.boss` kind "baron"). A
  big horned brute (drawn 1.35 times a person's size): pink hide above the
  waist, shaggy brown goat legs and hooves below, two great horns curving
  forward, the Snooze Gate's key, brass with a Zz tag, on his belt. 4200
  health for one human (the Mancouchbus has 3400), 30 px across. He stands
  on the stone ring south of the Crucible's pit and wakes ("KNEEL.") when
  somebody comes over a bridge or shoots him; he keeps to the Crucible.
  Pairs: green fire burns up in both hands for 0.6 s, then a fireball from
  each (fireballs.lua's "baron": green, 360 px/s, 22 `fire`), the left at
  where you stand, the right where you're going (0.55 s ahead); under half
  his health three pairs 0.35 s apart, and the green fire catches on his
  shoulders. Every 2-2.8 s (1.4-2 in phase 2), 14 breath. Charge (30% of
  attacks at 220 px or more, 45% in phase 2): horns down for 0.55 s, a red
  lane on the floor showing where, then he runs it at 400 px/s for up to
  1.1 s: whoever he hits takes 40 `impact` and goes flying 220 px; into a
  wall or the moat's edge he stands stunned for 1.4 s, eyes rolling, wide
  open. Claw: within 95 px his arm goes back for 0.4 s (his reach shown),
  then 30 `melee` to everyone in front of him. Roar, at two thirds and a
  third of his health ("RISE, LITTLE ONES!"): everyone within 200 px is
  thrown back 180 px and three imps (Bosses.plus) climb out of the pit's
  lava (horde.lua's `serverCall` "imp"). The bosses' standard (breath, the
  boss bar, a medkit when badly hurt, "...A MOMENT.", dodging abilities,
  `serverKill` "boss", 45 koins and two pickups). Down ("The... key...
  snooze..."), he lies face down where he fell and the key lies by him,
  glinting; the portal behind the Crucible is SEALED (chains across it, a
  lock) until somebody walks over the key and picks it up: a chime, the
  portal opens, and somebody far away says, over the HUD, "...hey. Hey. Are
  you awake?" (the beat).

  Lava is a hazard now, as this doc had it: the Crucible's pit and moat,
  the Smelters' vats and Earth's Crater are `low` on the map (city-map's
  low solids: no wall to sight or rounds), so you can shoot across them,
  and you can walk into them, but they set you alight (1.5 s at 30 `fire` a
  second, kept up while you're in; `eternal-mood/ground.lua`). Nothing of
  Heck's walks into lava: every walker's brain asks `Ground.blocked` (the
  walls and the lava) and `Ground.clear`, and the walking grid's cells over
  it are shut.

## Decisions

| Question | Decision |
| --- | --- |
| Parody or its own thing? | **A parody**, like A-Man. Punned names (the Mood Slayer, the UAC as the Union of Awful Choices, Heck), never the real ones. |
| Who talks you through it? | **Nobody else. Your own inner voice.** Where Cyber Feud has VEX in your earpiece, here it is the hero's thoughts: a gravelly action-movie narrator that keeps slipping into a half-asleep person on a sofa. |
| How does it end? | **It was all a dream.** You beat the last boss, the screen goes white, an alarm clock is ringing, and you wake up on the sofa. |
| How long? | **Five maps**, like Cyber Feud and A-Man. |
| Any driving? | **No.** Every map is walked. Heck on Earth, first planned as a drive, is a long road fought up on foot. |
| Is the dream hinted? | **Yes, more and more.** Each level leaks a bit more of the real world into the dream (a phone buzzing, a microwave, someone calling your name) until the last boss is the alarm clock. A player who notices gets the joke before the end; one who doesn't still gets it at the end. |
| Does it tie to Cyber Feud? | **Lightly.** The dream is built out of whatever you did that day: a demon with Kilowatt's reactor, a voice in a vending machine that sounds a lot like VEX. Nothing in the plot needs Cyber Feud played first. |
| Who's the enemy? | **Heck, and only Heck.** No factions and no infighting, unlike Cyber Feud: the UAC's possessed staff are Heck's lowest rank, and the whole horde works together against you. |
| Bosses? | **One on every level**, each at the level's end and in the way of its exit: the Floor Manager, the Mancouchbus, the Baron of Heck, the Spider Mattressmind, the Snoozedemon. They follow the bosses' standard (`src/features/bosses`: breath, the boss bar, a medkit when badly hurt) and each gets its own brain module. |
| The reward? | **A unique shotgun, the Mood Swing** (see "The reward"). Unlocked per player, the way Volt unlocks the electric grenade. |

## Logline

You've been running jobs for three days straight. You sit down on the sofa
"for a minute". You open your eyes on a moon base, in green armour, with a
shotgun, and a corporation has just opened a door to Heck. You are the Mood
Slayer. You are very angry. You are also, it turns out, asleep.

## The cast

- **You, the Mood Slayer.** A huge silent space marine in green armour with
  a visor. Silent out loud, anyway: everything he says is in his head. The
  players are all Mood Slayers (everyone is dreaming the same dream; it's a
  dream, it doesn't have to make sense).
- **The Voice**, your inner voice. It fills VEX's role: the intro screen
  (the Mood Slayer's visor, with a sleepy eye blinking behind it, where VEX's
  face glitches), the story beats, and the last word. It talks like a movie
  trailer ("In a world... of demons..."), it is very sure of itself, and it
  keeps getting distracted by the real world it can half hear: the TV, the
  fridge, a pizza going cold. Colour: visor green, going warm lamp-yellow as
  you wake up.
- **The UAC, the Union of Awful Choices.** The corporation that built a
  portal to Heck on a moon because the paperwork was cheaper there. It is
  not a side: Heck took its staff, who are zombies now and still on the
  clock. Colour: grey and hazard
  yellow.
  - **Dr. Hayden Seek**, its director, a brain in a jar on a robot body,
    who opened the portal and keeps apologising for it on the base's
    speakers ("This was in the risk assessment. Page four hundred.").
- **Heck**, the one enemy, and its demons. Red, loud and on fire. Imps that throw fireballs,
  Pinkies that charge, Lost Soles (flaming shoes, one each; nobody knows
  where the other one went) and a Cacodaemon or two floating about like
  angry tomatoes. Colour: lava red and orange.
### The bosses, one a level

Each is a bit more dream than the last, the way the levels are.

- **The Floor Manager** (Fobos Base), the line's Arachnotron. The UAC's
  shift supervisor, promoted out of his body: his brain in a glass dome on
  a four-legged spider walker with a plasma cannon, his clipboard taped to
  the side. Guards the hangar lift. Streams plasma, stomps whoever gets
  close, and calls zombie staff in "for a quick meeting". Shoot his cannon
  off and he has to come and stomp you. Not to be confused with Heck's
  Spider Mattressmind, the bigger spider with the chaingun.
- **The Mancouchbus** (Heck on Earth), the line's Mancubus. A huge fat
  demon who sat down in a recliner when the world ended and never got up;
  Heck put the recliner on tank treads and his arms into two rocket
  launchers. He sits in front of the starport's gate and keeps it closed:
  volleys of rockets from both arms in turn, sweeps of them in a fan, a
  belly bump up close, Cacodaemons called in. Slow to turn, and his back
  is the recliner. (Replaces the Cyberdaemon first planned here.)
- **The Baron of Heck** (The Foundry). A big horned brute with green
  fireballs at the foundry's heart, holding the Snooze Gate's key. Charges,
  throws fireballs in pairs, and roars.
- **The Spider Mattressmind** (Heck). A giant brain on mechanical spider
  legs, standing on a mattress it drags with it everywhere. A chaingun
  under its chin, and the mattress soaks up rounds from the front. Halfway
  down it starts yawning, and its yawns pull you in.
- **The Snoozedemon** (The Snooze Gate), the last one: a giant goat-headed
  wall of a demon with a clock in its forehead, whose roar is an alarm clock
  beeping. Beat it and you hit snooze on the whole of Heck.

### The horde

One enemy: Heck. There are no factions and no feud this time, and nobody
fights anybody but you. The UAC's staff aren't a side of their own: the
portal took them, and they're Heck's now, its lowest rank, the possessed.
Drawn top down like everyone else (`src/body.lua`, 9 px radius), the horde
bigger and stranger the further down the dream goes. All numbers are
starting points for tuning; for scale, a Combine soldier has 60 health and
drops 3 koins, a Halcyon officer 60, a Static brute 150.

- **One side.** Every member of the horde is on the same team: their
  rounds, fireballs, rockets and charges pass through each other and only
  hurt players (the way Halcyon Tower's two factions ignore each other), so
  they never fight among themselves.
- **They work together.** The possessed hold the ground with guns while the
  demons close in; packs mix the two. Bosses call in help.
- **One look.** Heck's red, orange and black throughout, lit from inside.
  The possessed keep their torn UAC grey and hazard yellow, with Heck's red
  eyes and glowing cracks in their skin.
- **Damage.** The possessed shoot (`bullet`); the demons burn (`fire`),
  charge (`impact`) and claw (`melee`).

Every enemy character gets its own brain module (the enemy brains
standard), as Cyber Feud's do.

#### The possessed (Heck's lowest rank)

| Unit | Look | Health | Attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Intern** | A white shirt, a lanyard, no gun, arms reaching out in front | 20 | Claws (`melee`, 7) | The lowest rank there is, and never alone: mobs of 5-8 stand about their spot (asleep in the bunks, at lunch) until a player comes near or sees them, or one is hurt; then the whole mob shambles after the nearest player (85 px/s, a lurch at 140 once close), raises its arms for 0.35 s and claws. One is nothing; a mob is not. The old zombies. |
| **Zombie staffer** | A UAC jumpsuit, a lanyard, a coffee mug in the other hand | 40 | Pistol (`bullet`, 8), slow to aim | Sits at a desk or stands at a post until someone comes in sight, then shambles at them (60 px/s) firing now and then. Fodder. |
| **Zombie guard** | UAC security armour, a cracked helmet | 60 | Shotgun (`bullet`, 6 pellets of 7); a grenade, one in three | The one that fights smart, like the Combine: sweeps its cone across the doorway it holds, fights from cover (ducks, steps out to shoot, ducks back), goes to ground when sniped and then sweeps where it came from. |
| **Overtime guy** | Big, in a hard hat and hi-vis, a chaingun from the loading bay | 100 | Chaingun (`bullet`, 6 a round, 8 a second) | Holds his ground near his post from cover, spinning up for 0.6 s (you hear it) each time he steps out, then firing at whoever he can see, sweeping slowly. |

#### The demons

| Unit | Look | Health | Attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Imp** | Brown, spiky, hunched, orange eyes | 60 | Fireball (`fire`, 14, slow enough to sidestep); a claw up close (`melee`, 10) | The common demon. Comes out of vents and walls, strafes sideways between throws, climbs over low cover. Packs of 3-5. |
| **Pinky** | A pink muscle with legs and a huge jaw | 160 | Charge and bite (`impact` 30, a shove; `melee` 18) | Braces 0.5 s, then charges in a straight line; into a wall it reels for 1 s. Its front is armoured (rounds from in front do half); its back is soft. In the Foundry's dark some are **Spectres**, a shimmer you only see close. |
| **Lost Sole** | A flaming boot with teeth, flying | 20 | Dive (`fire`, 12) | Floats in flocks of 3-6, over lava and walls; one at a time picks a target, hangs back for 0.4 s and dives straight at it. One round brings one down. |
| **Cacodaemon** | A floating red tomato with one green eye and a big mouth | 220 | Spits a ball of fire (`fire`, 24); a bite up close (`melee`, 30) | Slow, flies over walls and lava. Opens its mouth for 0.5 s before it spits (a tell). Shot while its mouth is open it reels. On Earth they float over the road and the roofs, spitting down at you. |
| **The Shoe Rack** | A floating brown ball with a mouth full of shoes | 180 | Spits a Lost Sole every 4 s, at most 3 out | Hangs back, flies. When it dies it spits three at once. Kill it first. |
| **Heck Knight** | The Baron's brown cousin, horned, 1.4x | 300 | Green fireball (`fire`, 20); a leap (`impact`, 30, lands 0.6 s after a shadow shows where) | Walks at you and leaps when you get far. The Foundry's north half and Heck. |
| **Revenaunt** | A tall skeleton in a cardigan, a rocket pod on each shoulder | 200 | Two homing rockets (`explosive`, 22 each, turning slowly; dodge round a corner); a punch (`melee`, 20) | Keeps at mid range, firing its rockets in turn every 3 s. The rockets can be shot down. Says something about your posture. |
| **Mancouchbus** | A huge fat demon in a recliner on tank treads, a flame cannon for each arm | 450 | Two fireballs at once, in a V (`fire`, 26 each); a flame burst up close (`fire` DoT) | Never gets up. Rolls slowly, turning to keep you in front; its back is the recliner (rounds do double). Heck and the Snooze Gate; Heck on Earth's boss is the big one, with rocket launchers. |
| **Arch-Revival** | Tall, thin, grey-white, glowing hands | 250 | Fire pillar: a ring of fire on the ground under you for 1 s, then it erupts (`fire`, 50); you have to get out of sight or out of the ring | Runs away from you, fast. Every 6 s it brings back the nearest dead demon (not bosses), which gets up with half health. Kill it first. Heck only. |

#### Mood kills

The quest's own trick, as breach is Cyber Feud's. A demon brought below 20%
of its health is staggered for 2.5 s: it stops, flashes orange and sways.
Walk up and press F and the Mood Slayer finishes it with a single over the
top move (a stomp, a punch, ripping a horn off), and it spills two small
health pickups. Bosses can't be mood killed, but their help can. It is a
reason to close in, and it pairs with the Mood Swing's hook.

#### What they say

The same system as Cyber Feud's (`Story.troops`, a bubble and a sound),
but one side: the possessed say the words and the demons mostly growl.

| Category | Lines |
| --- | --- |
| `idle` | "Is this overtime?" / "My badge doesn't work." / "Has anyone seen my legs?" / a demon's "Hungry..." |
| `reply` | "Please hold." / "Per my last email." / "Noted." / a growl back |
| `alert` (you) | "Visitor in the lab!" / "You're not on the rota." / "MEAT!" / "Who ordered the space marine?" / "Heck yeah!" |
| `down` | "Tell HR..." / "Finally, a break." / a scream, or a puff of smoke and a boot falling |
| `revive` (the Arch-Revival) | "Up. Up. Back to work." |

#### Who turns up where

The horde changes as you go down: mostly the possessed at the top, all
demons at the bottom.

| Level | Who |
| --- | --- |
| 1. Fobos Base | Staffers at their desks and posts, guards on the doors, an overtime guy in the Hangar; imps out of the vents from the Reactor on, a Pinky in Toxic Storage |
| 2. Heck on Earth | Pinkies charging out of the side streets, imps on the roofs, Cacodaemons over the road, Lost Soles round the Crater, a few guards behind wrecks at the crossroads |
| 3. The Foundry | Staffers, guards and overtime guys in the south half alongside imps and Pinkies; Spectres in the dark, Heck Knights in the north half, a Shoe Rack over the Crucible |
| 4. Heck | Demons only: imps, Pinkies, Lost Soles on the bridges, Cacodaemons, Shoe Racks, Knights, Revenaunts, a Mancouchbus and an Arch-Revival on the Altar Fields |
| 5. The Snooze Gate | Imps and Lost Soles it calls in, and a Mancouchbus in its last phase |

Each drops koins when it goes down (staffers 2, imps 3, the heavier ones
more, the Mancouchbus 15) and maybe a pickup, and every kill raises
`serverKill`.

## The arc: the dream falls apart as you go

The dream starts out perfectly serious and ends with the alarm clock as a
boss. Every level, the real world gets louder.

| # | Map | Play | Boss | What leaks in |
| --- | --- | --- | --- | --- |
| 1 | **Fobos Base**: the moon base, red alarms | On foot: get out of the lab and through the base | The Floor Manager | Nothing yet. One line about the "humming" (it's the fridge). |
| 2 | **Heck on Earth**: a city overrun, the road to the starport | On foot: one long road north, fought up street by street | The Mancouchbus | The billboards advertise sofas. A phone buzzes. |
| 3 | **The Foundry**: the UAC's factory, half turned to Heck | On foot | The Baron of Heck | Dr. Seek's speeches turn into a cooking show. Someone calls your name. |
| 4 | **Heck**: lava, bones, upside-down castles | On foot: down to the Snooze Gate | The Spider Mattressmind | The sky is the sofa's ceiling. A giant pizza box lies in the lava. |
| 5 | **The Snooze Gate**: the arena | On foot, the arena | The Snoozedemon | It beeps. It beeps louder. You wake up. |

### 1. Fobos Base

The job on the board: "Pest control. Moon. Bring a shotgun." The Mood Slayer
wakes on a slab in a lab with red lights going round and Dr. Seek on the
speakers apologising. Zombie staff on the clock and imps through the vents.
The way out is the base's hangar lift, and the Floor Manager is standing on
it in his loader. The Voice is pure action hero here.

### 2. Heck on Earth

The portal's leaked: Earth is overrun. The shuttle down from Fobos Base
lands at a UAC depot at the bottom of the city, and the only way on is the
road north to the starport, on foot, Pinkies charging out of the side
streets and Cacodaemons floating over the roofs. The billboards are meant
to show the evacuation route; half of them advertise sofas. On the last
stretch, in front of the starport's gate, the Mancouchbus sits in his
recliner, the remote on the armrest, and he isn't getting up.

### 3. The Foundry

The UAC's factory, where they melt Heck down for fuel, half of it turned to
bone and lava. Dr. Seek tries to talk you out of "breaking company
property" and, mid speech, starts explaining how to make a lasagne. The
Baron of Heck waits at the foundry's heart, holding the Snooze Gate's key.
Somebody far away calls your name. The Voice pretends it didn't hear.

### 4. Heck

Down through the portal. Lava rivers, bone bridges, castles hanging upside
down. The sky up there has a crack in it, and a lampshade. A giant pizza
box is sinking in the lava. The Voice is starting to struggle to stay in
character. The Spider Mattressmind sits in front of the Snooze Gate on its
mattress, and nobody goes through until it's down.

### 5. The Snooze Gate

The Snoozedemon fills the far wall: a goat-skull face with a clock in its
forehead. Its roar is BEEP BEEP BEEP, louder every phase, and the screen
shakes with it. When it falls the screen goes white, the beeping turns into
an ordinary alarm clock, and a last card says you wake up on the sofa. The
Voice gets the last word, back to normal: "...Huh. Pizza's cold." The
quest's star goes home as usual.

## Maps

Five new maps in city-map, one builder file for all five
(`city-map/eternal_mood.lua`, like `cyber_feud.lua`) and their own render
file (`render_eternal_mood.lua`). Tiles are 64 px (`Layout.TILE`). For
scale: the Drop is 64x96, the Market 56x56, the Overpass 32x200, the Roof
36x36.

| Map key | Title | Size (tiles) | Played | Quest |
| --- | --- | --- | --- | --- |
| `fobos` | Fobos Base | 56x80 | On foot | `eternal-mood` (on the board) |
| `earth` | Heck on Earth | 40x160 | On foot | `eternal-mood-earth` |
| `foundry` | The Foundry | 56x64 | On foot | `eternal-mood-foundry` |
| `heck` | Heck | 60x96 | On foot | `eternal-mood-heck` |
| `snooze` | The Snooze Gate | 40x40 | On foot, the arena | `eternal-mood-snooze` |

Each quest's `next` is the following one, as Cyber Feud's are; the Snooze
Gate's star goes home. Everyone travels north (up the screen), the way both
quest lines before it do. Every level's exit is shut until its boss is down:
reaching it before then doesn't finish the level, and the objective line
points at the boss.

### Shared look

- Everything is red, because everything in this universe is evil: a red
  dark (the night feature's ambient, per map), red-orange light, red-cast
  steel and floors. The one other colour is the toxic sludge's sick green.
- Two palettes inside that red, and the dream moves from one to the other.
  The UAC's: rust-red steel panels, hazard stripes in yellow and black, red
  computer screens, strip lights burning red-orange. Heck's: dark red rock,
  black bone, orange lava, and everything lit from below.
- Light comes in pools: the `night` feature's dark with lamps, screens,
  fires and lava as the lights. Fobos Base's alarm lamps turn like beacons,
  and its strip lights are on the blink.
- Pun signs and posters, the way Grey City has NOODLZ: UAC: WE OPENED IT SO
  YOU DON'T HAVE TO, PORTAL SAFETY WEEK (0 DAYS SINCE LAST INCIDENT), DEMON
  PARKING ONLY, HECK: NOW HIRING, MIND THE LAVA.
- The dream leaking in is drawn as well as said: a sofa cushion where a
  crate should be, a TV remote the size of a car, the corner of a lampshade
  in the sky, more of it each level.
- Each map gets its own theme music: heavy, fast, chugging metal, as Cyber
  Feud's maps have theirs. Each opens in the dream (Fobos Base's on a music
  box) before the riff tears in.
- Lava is a hazard tile: walk in it and you burn (`fire` damage over time,
  the damage feature's DoT, like the Winding Road's poison). Nobody can
  stand in it for long.

### 1. Fobos Base (`fobos`, 56x80, on foot)

The UAC's base on a moon, cut through: corridors two to three tiles wide
between rooms, steel walls, blast doors. Outside the walls the moon is grey
dust and craters under a black sky with stars and a big red planet hanging
in it (a surroundings file, `fobos_moon.lua`).

- **Arrival:** the bottom middle, in **the Lab**: a row of slabs with
  everyone waking up on one, glass tanks, a smashed portal ring. Dr. Seek on
  the speakers. The first beat ("Rip. Tear.") when the lab door opens.
- **The Offices:** the west wing. Desks and filing cabinets as cover, zombie
  staff at their desks until someone walks in, water coolers.
- **The Reactor:** the middle. A round room with the reactor in it (solid,
  glowing green, humming like a fridge), catwalks round it and pipes as
  cover. Imps come out of the vents here.
- **Toxic Storage:** the east wing. Barrels (some explode), pools of green
  sludge (a hazard like lava, `poison` instead of `fire`), a crane.
- **The Hangar:** the top. A big open hall with a lift pad at the top and
  crates and parked loaders round the walls. The Floor Manager stands on
  the lift on his spider walker and wakes when someone walks in.
- **The end:** the hangar lift. The EXIT star, once he's down: "HECK ON
  EARTH".

### 2. Heck on Earth (`earth`, 40x160, on foot)

No driving on this line: every map is walked. Earth is one long road north
through a burning city to the starport, fought up on foot (about a minute's
sprint end to end with nobody in the way): a six-lane road with sidewalks,
the city's buildings solid either side, crossroads where side streets run
off a block and end at burning barricades. The wrecks in the road (cars,
vans, buses, a police car) are cover, not vehicles. Past the edges the
city is burning (a surroundings file, `heck_on_earth.lua`: blocks of roofs,
a good few on fire, smoke drifting over).

- **Arrival:** the bottom, in **the Depot**, the UAC's yard, off the
  shuttle down from Fobos Base on its landing pad; crates, floodlights, red
  alarm lamps over the gate out onto the road. HOME star by the shuttle.
- **The Suburbs:** the first stretch. Houses either side behind front
  yards, some burning, dead hedges between, a car on the drive or a burnt
  tree; two crossroads. Possessed neighbours in the yards, a patrol up the
  road, interns' mobs in the side streets, imps under the manholes; Pinkies
  charging out of the side streets later.
- **Downtown:** the middle stretch. Tower blocks flush to the sidewalks,
  wrecks all over the road, guards behind the bus and the cars across
  both crossroads, and the overpass that crossed it fallen in: slabs of it
  over the road, a three-tile gap left in the middle that an overtime guy
  holds, with a mob in front of it. A phone buzzes here (the beat).
  Cacodaemons later.
- **The Crater:** two thirds of the way up, a portal has opened in the road:
  a pit of lava (solid, glowing, crust drifting on it, embers rising) with
  the cracked road split either side of it, the blocks round it fallen in.
  Imps climb out of the cracks round its rim; guards and mobs either side.
- **The Boulevard:** the last stretch, long, straight and wide, planters of
  burnt trees down the middle, the UAC's sandbags across it with guards
  behind them, a tower on fire at the bottom of it. The Mancouchbus sits
  in front of the starport's gate, an overtime guy beside it.
- **The end:** the starport gate. The EXIT star, once he's down: "THE
  FOUNDRY".

### 3. The Foundry (`foundry`, 56x64, on foot)

The UAC's factory, where they melt Heck down for fuel: a big steel shed,
half of it already turned to Heck. The south half is still the UAC's
(steel, yellow stripes, conveyor belts); going north, rock and bone grow
up through the floor until the north half is Heck's. Past the walls: the
starport's landing pads at night, then red sky (a surroundings file).

- **Arrival:** the bottom left, off a shuttle on a landing pad, the
  shuttle's ramp down.
- **The Conveyors:** belts running across the floor that carry anyone on
  them sideways (a moving floor, new), with crates riding on them as cover
  that moves.
- **The Front Office:** the south-east corner. A glass booth with Dr. Seek's
  jar on a desk in it, talking. Walk past and his speech turns into the
  lasagne recipe (the beat).
- **The Smelters:** the middle. Big vats of lava with walkways between
  them, sparks, chains hanging from the roof. Zombie staff and imps, and
  the first Heck Knights (the Baron's smaller, brown cousins).
- **The Crucible:** the top. A round pit of lava with a stone ring round it
  and four bridges in. The Baron of Heck stands on the ring and wakes when
  someone walks onto a bridge; he holds the key to the Snooze Gate, and
  drops it where he falls. Someone calls your name as he goes down (the
  beat).
- **The end:** the portal behind the Crucible, the way down into Heck. The
  EXIT star, once the key is picked up: "HECK".

### 4. Heck (`heck`, 60x96, on foot)

Heck itself: dark red rock cut by rivers of lava, crossed by bone bridges,
with black castles hanging upside down from the sky at the edges (scenery
past the walls, in a surroundings file, `heck.lua`: lava falls, the
castles, and high up a crack in the sky with the sofa's ceiling and a
lampshade through it).

- **Arrival:** the bottom, out of the portal, on a rock shelf.
- **The Bone Bridges:** the south third. Lava everywhere and narrow bridges
  over it, with Lost Soles (flaming shoes) diving at you as you cross.
- **The Altar Fields:** the middle. Wide open rock with altars and spikes
  as cover, fire pits, the biggest crowd of demons on the line.
- **The Pizza Box:** a giant pizza box half sunk in a lava lake on the east
  side. The beat walking past it. Drawn so it's obvious from the far side
  of the map.
- **The Mattress:** the top. A wide flat plateau in front of the Snooze
  Gate, where the Spider Mattressmind sits on its mattress. It wakes when
  someone walks onto the plateau.
- **The end:** the Snooze Gate, a huge stone door with a clock face over it.
  The EXIT star, once the Mattressmind is down: "THE SNOOZE GATE".

### 5. The Snooze Gate (`snooze`, 40x40, the arena)

A square arena of black rock floating in the dark, lava falls round it, a
lot like the Roof.

- The Snoozedemon fills the north edge: a wall of a demon from one side to
  the other, the clock in its forehead, its arms reaching down on to the
  arena. It is the wall: it doesn't walk.
- Pillars and broken stone across the floor as cover, some knocked down as
  the fight goes on.
- Four lava channels run across the floor from its mouth, and when it beeps
  they flare.
- Past the edge: nothing but dark and the lava falls, and more of the real
  room as it goes on: the sofa's arm, the coffee table, the TV's glow.
- **The end:** when it falls the screen goes white, the beeping becomes an
  alarm clock, and a last card shows the sofa: you wake up. A HOME star
  comes up in the middle of the arena.

## The Voice: what it says

The internal dialog works like VEX's chatter (`cyber-feud/story.lua`): one
intro line per level, then a line at each story beat (walking into a zone,
a boss waking or falling, the level's end), in a bubble on the HUD. These are
the first drafts.

### Banners

| Map | Title | Tagline |
| --- | --- | --- |
| 1 | FOBOS BASE | "Somebody opened a door." |
| 2 | HECK ON EARTH | "Rush hour." |
| 3 | THE FOUNDRY | "Now hiring. Souls preferred." |
| 4 | HECK | "Mind the step." |
| 5 | THE SNOOZE GATE | "Five more minutes." |

### Intro lines (one per level)

1. "They opened a door to Heck. They're about to find out I'm worse."
2. "Earth. Home. On fire. One road to the starport, and Heck's standing on all of it. Good."
3. "A factory that melts demons. Somebody's going to melt. Not me."
4. "Heck. Hot, loud, full of demons. ...Is it hot in here, or is it the blanket?"
5. "One big demon left. Then I'm going back to... where was I going?"

### Story beats

- **Fobos Base**
  - The lab door opens: "Rip. Tear. In that order."
  - The reactor room: "Reactor's humming. Weird hum. Sounds like a fridge."
  - The Floor Manager wakes: "A manager. A brain. On legs. With a gun. ...That's most managers."
  - The Floor Manager down: "Meeting's over."
  - The end, the lift: "Going up. The demons are going down."
- **Heck on Earth**
  - The first billboard: "Evacuation route, it says. ...No. That's an advert for sofas."
  - A phone buzzes on the road: "That's not my phone. I don't have a phone. I'm a space marine."
  - The Mancouchbus wakes: "A demon. In a recliner. With rockets. ...That recliner looks comfy."
  - The Mancouchbus down: "Bigger they are. Louder they land."
  - The end, the starport: "Starport. Last shuttle to the Foundry. Window seat."
- **The Foundry**
  - Dr. Seek's speech goes wrong: "Did he just say 'a pinch of oregano'?"
  - The Baron of Heck wakes: "Big. Horns. Angry. We have so much in common."
  - The Baron down, the key picked up: "The key to the Snooze Gate. ...Snooze Gate. Sure."
  - Someone calls your name: "Nobody called my name. Keep moving."
- **Heck**
  - Under the crack in the sky: "The sky's got a lampshade. That's... fine. Heck's like that."
  - The pizza box in the lava: "Don't think about the pizza. There's no pizza. Focus."
  - The Spider Mattressmind wakes: "A brain. On legs. On a mattress. ...I want that mattress."
  - It yawns: "Don't yawn. Don't yawn. Don't... *yawn*."
  - It falls: "Took its mattress, too. No. Focus."
  - The end, the Snooze Gate: "Big door. Something behind it is ticking."
- **The Snooze Gate**
  - It wakes: "BEEP. BEEP. Oh, I hate that sound. I REALLY hate that sound."
  - Half health: "It's getting louder. Why is it getting louder?"
  - It falls, the end: "...Huh. Sofa. Pizza's cold. Weird dream."

### What the others say

Barks like Cyber Feud's troops (`Story.troops`), by side:

- **UAC zombies**, still at work: "Is this overtime?", "My badge doesn't
  work.", "Has anyone seen my legs?", "Please hold. Your call is important."
- **Demons**: mostly roars, with the odd line: "MEAT!", "Heck yeah!",
  "Who ordered the space marine?"
- **The bosses**, one or two lines each as they fight:
  - The Floor Manager: "You're not on the rota.", "Let's circle back to you."
  - The Mancouchbus: "Oi. You're blocking the telly.", "Don't make me get up.", "Not the upholstery!"
  - The Baron of Heck: "KNEEL.", "THE KEY IS MINE."
  - The Spider Mattressmind: "I AM THE MIND.", "...five more minutes..."
  - The Snoozedemon: "BEEP. BEEP. BEEP." (that's all it ever says)
- **Dr. Seek**, on the speakers: "Please don't shoot the portal. It's
  leased.", "This was in the risk assessment.", "First you soften the
  onions..."

## The reward: the Mood Swing

A unique double-barrelled shotgun, the Mood Slayer's own. Where the
ordinary shotgun (`weapons/guns.lua`) pumps six pellets a pull, the Mood
Swing fires both barrels at once: more pellets, a wider spread and a harder
kick, then a break-open reload after every pull. Its trick is a hook under
the barrels: a second button fires it at an enemy and swings you in to
point-blank range, where the shotgun does the rest. A new gun in
`weapons/guns.lua` beside the shotgun, not a change to it.

It is unlocked per player, the way the electric grenade is (the grenades
feature's unlock, the rewards feature's screen), and saved with them. Unique
or not, it is equipment, so it has tiers (`tierStats`, read through
`Tiers.apply`). Its numbers are for when it is built.

## Open questions

- **Where the Mood Swing comes from.** Dropped by one of the bosses, or
  waiting on the coffee table when you wake up.
- **The bosses' fights.** The moves above are first ideas; each gets its
  numbers when it is built, as Cyber Feud's did.
- **Mood kills** are a proposal: whether they're in, and whether every
  demon can be mood killed or only the bigger ones.
- **The bosses' help.** Which demons each boss calls in, and when.
- **New pieces the maps need:** lava and sludge as hazard tiles, and the
  Foundry's conveyor belts (a moving floor). Lava and sludge might belong
  in their own feature, since later maps could use them too.
