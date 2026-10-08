# Changelog

Every change players would notice, newest first. The game reads this file
and shows it from the icon in the bottom-left corner of the main menu, and
the version it shows is the newest release here.

How to write it (details in "Changelog and versioning" in `docs/features.md`):
- Every pull request into `staging` adds lines under `## [Unreleased]`, in
  `### Added`, `### Changed` or `### Fixed`: one per change a player would
  notice, written for players, with old -> new numbers for balance changes.
- A release is `staging` merged into `main`: `[Unreleased]` becomes
  `## [x.y.z] - YYYY-MM-DD` with a sentence or two summing the release up,
  and a fresh empty `[Unreleased]` goes on top.

## [Unreleased]

## [0.20.0] - 2026-10-08

The Suppressor's minigun is yours to buy: hold the trigger, let it wind
up, and hose.

### Added
- The minigun, in the shop for 420 Fcks (a box of 300 rounds is 70). Hold the trigger and the barrels
  wind up for 0.8 seconds, then it fires 17 rounds a second, 10 damage each, from a belt of 150. Let go
  and it has to wind up again. Better tiers wind up faster. The ammo factory makes its rounds too.

## [0.19.0] - 2026-10-08

A heavy joins the Combine in the Citadel: the Suppressor, with a minigun
that winds up before it fires and a shield you have to break first.

### Added
- A new enemy, the Combine Suppressor: a heavy soldier with a minigun and an energy shield, two of them
  holding the Citadel's gallery and reactor deck. Listen for the barrels winding up, then get into cover:
  he hoses you down for about 3 seconds and has to vent his gun after. He is slow to turn, so circling
  him works. His blue shield soaks every hit first (shock breaks it twice as fast) and comes back if you
  leave him alone for 5 seconds. He leaves a body in his heavy armour with the minigun beside him.

## [0.18.0] - 2026-10-08

Dying deep into a long quest no longer means walking it all again: find
respawn points along the way and pick where to come back.

### Added
- Respawn points on the long quest maps (City 17, the Coast, the Winding Road, the Citadel and Shotgun's
  Bluff). Walk or drive past one to find it: its flag turns green and it shows on the minimap. Die after
  finding one and you pick where to come back from a list: where you came in, or any point you found. On
  the Winding Road they are the car station pads, so you can call a car straight away.

## [0.17.0] - 2026-10-08

The dead stay down: shot Combine, D-Day soldiers, pedestrians and simps
leave bodies in three different poses, in their own clothes. Cars and
blasts still splat them, and fire leaves ash.

### Changed
- D-Day's soldiers, pedestrians and simps (Karen's and open borders') now drop dead where they are
  shot, in the same three poses as the Combine, in their own clothes. Run over or blown up, they
  still burst into a splat; burned or electrocuted, they leave ash.
- Dead Combine soldiers fall three ways now: on their back as before, face down with their arms up
  by their head, or curled up on their side.

## [0.16.0] - 2026-10-08

Sniping from the dark no longer works on the Combine or D-Day's soldiers:
they take cover, wait you out and send squads to find you, and some of
them throw grenades now. The Winding Road's bunkers send out squads of 3.

### Added
- Combine soldiers fight back against snipers. Shoot one from where none of them can see you and he
  and his mates nearby (MG gunners too) take cover; once the shooting has stopped for 8 seconds they
  send a squad out to find you. The moment any of them sees you, defenders run back to their posts
  and guns and everyone else comes for you.
- A quarter of the Combine carry two grenades, and throw them at you, or at where you just ducked
  out of sight.
- D-Day's soldiers fight back against snipers the way the Combine do: shot from where none of them
  can see you, they take cover, send squads of 3 out to find you after 8 seconds of quiet, and all
  come for you once one of them sees you.
- A quarter of D-Day's soldiers carry two grenades and throw them at you, or at where you just
  ducked out of sight.

### Changed
- The Winding Road's bunkers send their soldiers out in squads of 3 instead of one at a time: 9 per
  bunker in 3 squads (was 8, one every 6 seconds).

## [0.15.0] - 2026-10-08

The gym trains your legs: buy up to five levels of walking speed and walk
twice as fast.

### Added
- Walking speed at the gym (key 7): five levels, each +20% walking pace, so a full set walks twice
  as fast. Costs 3/5/8/11/14 Fcks. Sprinting is unchanged.

## [0.14.0] - 2026-10-08

Enemies leave a lot more ammo behind, and now and then a grenade. Medkits,
drinks and grenades you can't use on the spot go into their quick slot for
later.

### Added
- Enemies can drop a grenade when they go down (5 in every 100 kills).
- Medkits and energy drinks you can't use right now (full health, full stamina, or a drink from
  behind the wheel) go into their quick slot for later, up to 5; with the slot full they stay on
  the ground. Grenades you pick up go straight into their quick slot too, then your bag, so
  you no longer have to drag them over.

### Changed
- Enemies drop a lot more ammo: something drops from 40% -> 65% of kills, an ammo box from 10 ->
  30 of every 100 kills, and each box holds 0.6 -> 1 full magazine. Medkits, energy drinks and
  vests still drop from 10 of every 100 kills each.

## [0.13.0] - 2026-10-08

A-Man's trail runs all the way to the top of the Citadel: through the
Outer City, up the Coast and along the Winding Road in the new Scout Car,
past the Hunter-Chopper, antlions, Hunters and the Poison Zombie. Back in
the city, parks get bums and you can hire a crew for a Gang Hangout.

### Added
- A-Man's trail goes on: take the star at the Citadel's doors in City 17
  and he steps out in front of you, and sends everyone the long way round,
  to the Outer City: packed concrete blocks, canals and bridges, parks,
  and a big open square on an island in the middle, all of it left to
  rot: collapsed buildings, holed roofs, rusted wrecks, weeds through the
  paving and rubbish in the canals.
- The Combine hold the Outer City: guards at the choke points on the way
  in and squads on patrol. Get near a guard station and its door slides
  open and more of them come pouring out.
- The Hunter-Chopper: a Combine gunship circling the Outer City's square.
  You hear its rotor from across the city; when its gun locks on to you a
  red beam and a rising whine give you a second to get moving before the
  burst. Run across its line, or get behind something. Every so often it
  peels off with a klaxon on a bombing run, dives over you and drops a
  stick of bombs down both sides of it: watch the red rings and get out
  from under. Its rounds are blue. It calls for help as you shoot it:
  at 80% health it sets Combine soldiers down under it, three lots of
  three 8 seconds apart, and at 30% A-Man blinks in beside you, opens his
  briefcase on three Hunters (more with more players) and blinks out
  again. Shoot it down (3600 health for one player, more with more) and
  it spins out, crashes in a fireball, spills koins and leaves a burning
  wreck by the way out.
- Combine soldiers no longer burst into a red splat when they go down:
  they fall where they stood, knocked over by the shot, gun dropped by
  their hand, and lie there a while.
- A-Man's trail has music of its own for each stop: City 17 keeps his
  industrial rock, the Outer City gets a fast electronic chase, the Coast
  a wide-open, uneasy piece with the sea in it and something under the
  sand, the Winding Road heavy metal (galloping riffs, double kick and a
  screaming lead guitar) and the Citadel slow, heavy industrial metal with
  a cold machine arpeggio, clanking far below and the Combine's alarm.
- A-Man's trail goes on up the coast: the star by the Hunter-Chopper's
  wreck takes everyone to the Coast, one long beach winding north between
  the sea and green mountains, narrow most of the way and opening into
  wide coves strewn with rocks, driftwood and a beached boat. The sea runs
  on out west past the edge, the mountains roll on east, and on this long
  map the minimap shows the part round you and scrolls as you go.
- The Combine hold three bunkers on the Coast, each with a machine gun
  nest in front of it raking the beach and four soldiers keeping it:
  one on the gun, three with rifles round the bunker. They hold their
  ground rather than chase you, and when the gunner drops, another runs
  to the gun. The gun only swings so far: get round its side. The
  riflemen fight from cover: they duck behind the bunker or a rock, lean
  out to shoot and duck back, and dive for cover the moment you hit them
  in the open.
- Antlions: swarms of them, over a hundred in all, lie buried along the
  Coast and burst up out of the sand when you come near, run you down and
  bite, leaping the last of the way now and then. You can only just
  outrun them at a sprint. Walk away and they burrow back down to wait
  for you.
- The Coast has a boss: clear the point of every antlion and soldier and
  the Antlion Guard digs its way up out of the sand. It swipes, paws the
  sand and charges (it reels if it runs into a rock), and rears up to
  scream: a cone shows on the ground, then a sound wave rolls down it,
  hurting and blowing back everyone caught in the open. Get out of the
  cone or behind something. Bring it down and the way on opens by its
  body.
- The Winding Road, after the Coast: get back in your car and drive one
  long mountain road from the valley floor up to the pass, beside the
  river and over it on six bridges, up a stack of hairpins and along the
  gorge, with snow on the peaks near the top. It is wide, room for eight
  cars abreast, and the bridges' railings stop cars but not sight or
  bullets. Left your car in the garage? You are lent a Scout Car to drive
  there instead; it stays behind when you leave.
- The Scout Car, after Half-Life 2's buggy: a bare tube frame on big
  off-road tyres with the engine out back and a tau cannon bolted to the
  side. Quick off the line and nimble, but light and easy to shoot up
  (295 top speed, 560 acceleration, 165 hitpoints). 240 koins at a
  vehicle factory.
- Boost: hold Shift while driving a Scout Car to double its speed for up
  to 3 seconds, off a meter beside your health that refills in 5 once you
  let go (run it dry and let go of Shift before it boosts again).
- The Scout Car carries an auto turret for its driver: the fire button
  shoots it, 30 rounds a magazine, never out of ammo but still reloaded (X).
- The Scout Car's tau cannon fires: right mouse while you drive one. Tap
  for quick bolts, or hold to charge one heavy shot (up to 150 damage)
  that kicks the car back when it goes. Hold it too long and it overloads,
  going off by itself and burning your car. It never runs out.
- The Combine hold every bridge on the Winding Road but the top one: two
  machine-gun nests at the far end fire back across it, riflemen fight
  from behind concrete blocks laid as a chicane, and a bunker beside the
  road keeps sending soldiers out after you while you are near. Drive
  through fast, shoot the gunners, or run the soldiers down: on the road,
  a car at speed kills a Combine soldier outright. Three burnt-out cars lie
  staggered across the road short of every bridge, to take cover behind.
- Hunters stalk the open road between the Winding Road's bridges: two on
  each long stretch, walking it up and down and opening up on anyone who
  comes along.
- Rollermines, after Half-Life 2's: steel balls sunk in the ground along
  the Winding Road, with more scattered at random over the whole map,
  somewhere different every time. Come near and they hop out, blades
  snapping open, and roll after you, a little slower than a cruising Scout
  Car, beeping as they close in. Their blades shock and stun you the
  moment they touch you, and then they blow up, on you or your car. Shoot
  them first: two pistol rounds set one off, and its blast sets off any
  others near it.
- Car stations on the Winding Road: a pad short of every bridge. Lost your
  buggy? Get out of the line of fire, stand on a pad and press F, and your
  Scout Car comes up on it, whole and loaded (one every 10 seconds). A
  wrecked car leaves you alive on foot where it went up.
- The Poison Zombie waits at the top of the Winding Road: a bloated,
  wheezing hulk with a poison headcrab on his head and more on his back.
  He throws them at you, and claws anyone who gets close. Shoot the crabs,
  or run them over; drive into him and your car bounces off, hurting you
  both. Beat him to finish the level.
- Poison, a new kind of damage: a poison headcrab's bite leaves you
  poisoned, losing 4 health a second for 6 seconds, with green bubbles
  rising off you. A dodge or a medkit cures it. It shows in the
  resistances on the inventory screen; nothing protects against it yet.
- Into the Citadel: beat the Poison Zombie and his EXIT star takes you
  inside at last. One catwalk climbs a vast dark shaft, platform to
  platform, and the Combine hold all of it: guards on every platform,
  rollermines on the catwalks, Hunters near the top, and a machine gun
  firing straight down the long span over the core, with nowhere on it
  to hide.
- A-Man waits at the top of the Citadel: step onto the top platform and
  he blinks in. He is far tougher than when he walks the city (5000
  health), teleports straight through you, and every time you knock
  another tenth off his health his briefcase opens on something you
  fought on the way: Combine soldiers, Hunters, rollermines, antlions or
  his sentry turrets, and when he is nearly beaten, two lots at once. Beat
  him to finish his trail; he drops his teleport, uncommon or better.
- Every park has a bum living on one of its benches, his shopping cart parked beside him. Stand next
  to him and press F to hire him for 1000 Fcks: pick another player or a bot and he goes after them,
  shouting abuse, and every punch leaves them bleeding (5 a second for 6 s). He gives up after 75 s,
  or once they go down, and walks back to his bench. The target's screen warns them, but not who paid.
  A bum has 200 health (ten pistol rounds) and can also be frozen or run over; a new one takes the
  bench a minute later.
- Whoever a bum goes for cries "I have been stabbed" at his first punch, and police who see it just
  answer "I don't think you have mate". Shoot back at the bum in front of them, though, and they come
  after you. Bots he goes for fight back, and get the same treatment.
- Gang Hangout: a new building (200 Fcks) for a plot you own. Deposit koins into its fund and up to
  4 armed guards come out, 100 Fcks each from the fund; with the fund empty nobody comes out, and
  a guard who goes down is replaced 10 seconds later. They go after anyone who shoots any of your
  buildings, shoots you on the hangout's block or the blocks around it, or shoots them.
- Gang Hangout upgrades: street thugs with pistols (100 Fcks a guard), bent cops with uzis (upgrade
  500, 150 a guard), riflemen with AK-47s (1000, 200 a guard) and the Combine with shotguns (2000,
  300 a guard).
- Gang Hangout guards also fight the police: an officer on foot who shoots you near the hangout,
  or shoots one of them, has the crew after them, and their rounds bring officers down.

### Changed
- A dodge now stops bleeding (and poison, and a shock running through you)
  the way it already puts out a fire; a medkit still stops a bleed too.
- Driving puts your weapons away: no guns, abilities or grenades from
  behind the wheel, and their buttons leave the screen until you get out.
  Most cars are unarmed now; get out to fight.
- Parks are no longer plain grass: gravel paths lead in from each side to a paved plaza with a
  fountain, with striped lawns, low hedges, flower beds, lamps and benches.
- On the minimap and the big map, every building is now drawn in its owner's colour (the colour of
  their dot), so you can see at a glance whose it is. Ruins are a darker shade of it.

## [0.12.0] - 2026-10-05

Grenades: keep a few in a quick slot, see where one will land and how far
it reaches, and throw it.

### Added
- Grenades: a new quick slot beside medkits and energy drinks holds up to 5. Press T to ready one,
  see where it will land and how far the blast reaches, and click to throw it. On foot only, and
  the blast hurts you too.
- The ammo factory makes grenades out of iron and sulfur, and the shop sells them under Supplies.

## [0.11.0] - 2026-10-04

Abilities are quicker to juggle: with one selected, another ability's key
switches straight to it.

### Changed
- With an ability selected, pressing another ability's key switches straight to it instead of
  having to put the first one away.

## [0.10.0] - 2026-10-02

The city finally sounds alive. Every vehicle has its own engine and horn,
crashes crunch, scrapes grind and tyres screech; guns, explosions, hits
and reloads hit harder; and everyone on foot, enemies included, is heard
walking on whatever ground is under them.

### Added
- Car horns: hold V while driving and everyone nearby hears you. Every
  kind of vehicle has its own: hatchbacks beep, sedans have the two-tone
  car horn, SUVs and pickups go deeper, motorbikes meep, vans blare and
  trucks and buses blast an air horn. Ram a bot and it honks back. Rebind
  it in Settings; the horns have their own volume slider.

### Changed
- Every kind of vehicle has its own engine sound: hatchbacks buzz, sedans
  purr, SUVs and pickups burble like a V8, motorbikes scream through six
  gears, vans and trucks clatter like diesels and the dump truck thumps.
  The settings screen's engine preview plays a different one each press.
- Guns hit harder on the ear: every shot now has the click of the action,
  a sharp crack, a deep thump and an echo off the buildings. The shotgun
  booms and rolls away, the sniper's crack echoes across the city, and the
  rocket launcher kicks.
- The flamethrower roars instead of rattling like a gun: it lights with a
  whoomp, keeps up one steady roar while you hold the trigger, and dies
  away when you let go.
- Explosions sound bigger and never quite the same twice: a sharp crack, a
  deep boom, debris crackling down and a roar rolling off the buildings.
  Cars clang with flying panels as their fuel goes up, and buildings
  come down with a long rumble of falling rubble.
- Hits sound like what they hit: bullets clank off cars and thud into
  people, punches land with a thump, fire sizzles, shocks zap, and bullets
  chip the walls with the odd ricochet whining away. The flamethrower no
  longer clanks fourteen times a second on whatever it burns.
- Reloads sound like the real thing: the empty magazine clatters on the
  ground, a fresh one slaps in and the slide racks home; shotgun shells
  click in one by one, the rocket launcher beeps when armed. They keep
  pace with the reload, so a legendary gun's quicker reload sounds quicker.
- An empty gun gives a loud click when you pull the trigger (the
  flamethrower splutters), and your last round ends with a ping.
- Footsteps: everyone on foot is heard walking and running, in step with
  their legs. Shoes click on the road, swish through park grass and
  forest, crunch on the beach's sand and splash through water, and the
  crowd around you murmurs along. They have their own volume slider.
- Enemies have footsteps too, so you can hear them coming: police, simps,
  soldiers and the Combine walk and run, bosses like Karen, the Major,
  Shotgun, Bigfoot and the runner thud heavily, hunters click along on
  their claws, and the tripod's stomps carry across the city.
- Car crashes make a noise, as big as the hit: a tap thunks, a crash
  crunches metal, and a big smash shatters glass and scatters bits. Walls
  thud, cars clang, and trucks crash deeper than motorbikes. They have
  their own volume slider.
- Sliding along a wall or another car grinds: screeching metal and
  sparks that get louder the faster you scrape, and die away as you pull
  clear.
- Tyres screech: handbrake turns, corners taken too fast and hard stops
  squeal, louder the harder you push, and scrabble in the dirt on grass
  and sand. Motorbikes squeal higher, trucks lower. They have their own
  volume slider.

## [0.9.0] - 2026-10-02

Freeze gives fair warning now: a ring shows where it is coming down and
everyone, bosses and traffic included, gets a moment to dodge it. Vests
on the road top up damaged armor, and the city stays calm for a few
seconds after a boss falls.

### Changed
- Freeze warns before it lands: a ring shows on everyone's screen where
  it is coming down, frost filling it in from the middle, and it lands
  0.75 seconds later (it used to land the moment you let go). Walk or
  drive out of the ring in time and it misses you.
- Freeze looks the part: a flash and a shockwave as it lands, frost with
  ice crystals and drifting snowflakes on the ground, a ring round the
  edge counting the hold down, and whoever is caught sits in a block of
  ice that cracks just before it lets them go.
- Bosses (Karen, Shotgun, the Major, Bigfoot, A-Man, the Tripod) and
  drivers in traffic get out from under a freeze's warning ring, a leap
  about to land or a heat ray once they've had a moment to see it. The
  Hunters dodge freezes now too.
- Police and traffic stay passive for 5 seconds after a city event's
  boss goes down, instead of turning on you the moment he dies.

### Fixed
- Running over a vest on the road with damaged armor on now tops your
  armor back up to full (a vest that holds more than yours replaces it).
  It used to stay on the road until your armor was gone completely; it
  still does if your armor is full.

## [0.8.0] - 2026-10-02

Every enemy thinks for itself: the bosses go for medkits when they're
hurt, D-Day's soldiers hunt like the Combine, Karen's simps gang up and
the police radio for backup.

### Changed
- Police officers on foot think for themselves now: one who spots you
  while you're wanted calls it in, and every officer within 900 px who
  isn't busy comes; lose them and they search where they last saw you
  instead of knowing where you went; shoot one from out of sight and they
  turn round and go looking the way the shot came, calling it in.
- Karen's simps think for themselves now: shoot Karen and all of them
  come for you (for 6 seconds), whoever is nearer; they come at you from
  all sides instead of queueing up behind each other; and with nobody to
  fight they stay by her instead of wandering off.
- The Tripod has a brain of its own now, and below 40% of its health it
  strides over the buildings to a medkit lying within 900 px (+200 each)
  and snatches it up with a tentacle, its heat ray still at work.
- The Runner has a brain of his own now, and below 40% of his health he
  leaves his street for a medkit lying within 1200 px (+200 each),
  smashing whatever is on the way, then gets back on the street grid and
  runs on.
- Bigfoot has a brain of his own now, the same one in the city and in
  the forest, and below 40% of his health he goes for a medkit lying
  within 700 px (+200 each): he leaps onto it if it's a fair way off and
  he has the breath (the landing slams anyone there, as usual), and
  lumbers over if not.
- A-Man has a brain of his own now, and below 40% of his health he goes
  for a medkit lying within 1600 px (+200 each): he blinks straight onto
  it if he has the breath (the warning line shows, and anyone on it is
  torn through as usual), and walks over if he hasn't.
- Shotgun has a brain of his own now, and below 40% of his health he
  goes after a medkit lying within 700 px (+200 each): out of sight first
  if his vanish is ready and he has the breath, round the bluff by the
  ramp if it is down below, and he only says something about it if
  anyone can see him.
- Crazy Karen thinks for herself now: she charges round the houses
  instead of into them, stomps back to her turning circle when nobody is
  about, and below 40% of her health she marches off to a medkit lying
  within 700 px (+200 each), complaining about it.
- Major Looz'er has a mind of his own now: out of sight, he marches after
  you round the bunkers and huts instead of into them, and below 40% of
  his health he breaks off for a medkit lying within 700 px (+200 each),
  still firing at you on the way, with a word or two about it.
- D-Day's soldiers now think like City 17's Combine: a guard or rifleman
  who spots you comes after you instead of staying at his post, searches
  where he last saw you, then walks back. One who spots you calls in the
  nearest three within 800 px (every 15 seconds at most), and when one
  goes down everyone within 700 px comes to see. They find their way
  round the bunkers and huts.

## [0.7.0] - 2026-10-02

Hunters stalk City 17's Citadel: quick three-legged synths that keep you
at range, dodge, heal, call each other in and zap you with every hit.

### Changed
- A light shock hit no longer stuns you on its own: it takes 20 or more
  in one hit (the Tripod's lightning, 35, still does).

### Added
- Hunters, a new Combine enemy: quick three-legged synths with glowing
  blue eyes and a pair of flechette guns under their faces. Three of them
  patrol a ring round City 17's Citadel. They see as the Combine soldiers
  do (the same cones, wider when on edge, and anyone within 170 px), but
  fight their own way: they keep you at range (about 260 to 440 px),
  strafing and backing off if you rush them, and fire uzi bursts that do
  8 a round (shock damage). A hit zaps you: the shock runs on through
  you for 3 seconds at 8 a second, the way a flame burns on, unless you
  dodge it off. About every 8 seconds one stands still, charges its pods
  (a crackling white-blue glow, 0.6 s) and fires a slower stun shot that
  holds you still for 1.2 seconds. They dash aside from
  rounds and rockets coming at them, from where a leap is about to land
  and from a heat ray, though not every time (once a second at most).
  Below 45% health they break off to grab a medkit (+70) or an energy
  drink (+30 and quicker for 6 seconds) lying within 700 px, and the
  pickup is gone for you. They take 180 (nine pistol rounds) and drop 8
  koins. Shoot one from behind and it whips round on you, straight into
  a fight if it can see you, otherwise off to search the way your shot
  came; a shot within 550 px sends it to look. They call each other:
  one that spots you or is shot at sends out a call (a blue pulse and a
  whine, at most every 6 seconds) and every Hunter within 1000 px that
  isn't busy comes to where you are. Their sounds have their own volume
  slider ("Hunters").

## [0.6.0] - 2026-10-02

City 17 no longer stops at its edges: the war-torn city runs on past a
Combine wall all round it.

### Added
- City 17 no longer ends in the bare grid: the city carries on past its
  edges, out of reach behind a Combine wall that runs all round it.
  Streets and blocks of flats, some bombed down to rubble and some
  burning, the railway, the canal and the Combine's wall running on out
  of both sides, all under a haze that thickens further out.

## [0.5.0] - 2026-10-02

City 17 goes to war: fires and rubbish in the streets, twice the Combine
on its checkpoints and beats, and A-Man dropping by the plaza with his
turrets.

### Added
- City 17 looks like it has been through a war: fires that never go out
  (oil drums burning on the pavements, fires in the rubble and out on the
  roads, flats burning in the old town, smoke drifting off them all),
  scorch marks round them, heaps of bin bags and junk, and litter
  everywhere. Walk into a fire on the ground and you catch alight
  (2 seconds, 6 damage a second); the drums are solid.
- A-Man drops by in City 17: the first time you walk into the plaza he
  blinks in near you, snaps his briefcase open, leaves five sentry
  turrets (more with more players) and blinks out again, three times,
  8 seconds apart. He is gone in under a second and a half and can't be
  hurt yet; his turrets go over as usual.

### Changed
- Twice as many Combine soldiers in City 17 (24 -> 48): two guards at
  every checkpoint post (was one), standing side by side, and two squads
  of three on every patrol beat (was one), spread out round it.
- Fewer citizens on City 17's streets to make room for them: half as
  many as before (26 -> 13 for each player).

## [0.4.0] - 2026-10-02

City 17's Combine soldiers call for backup: spot you and the nearest of
them come running.

### Added
- City 17's Combine soldiers call each other: one who spots you radios
  it in, and the nearest three soldiers within 800 px who aren't busy
  (guards off their posts too) come to where he saw you. The same soldier
  calls again at most every 15 seconds.

## [0.3.0] - 2026-10-02

City 17 comes alive: Combine squads patrol, hunt and talk over their
radios with any gun in hand, and citizens walk the streets.

### Added
- City 17's Combine soldiers watch a wider cone while they are on edge:
  100 degrees (was 60) while they have you in their sights, are searching
  for you or are looking into something, back to 60 once they settle.
- City 17's Combine soldiers carry any of the guns now, not just the AK:
  uzis, shotguns, pistols, flamethrowers (with a fuel tank on their back),
  rocket launchers and sniper rifles, fired in bursts. Shotgun and
  flamethrower soldiers come in close before they open up. A soldier's
  sniper round does 60 damage, not a player's 200.
- City 17's Combine soldiers are tougher: health 40 -> 60. Your guns do
  their own damage to them (every hit was 20): three pistol rounds, four
  from an AK, five from an uzi, one sniper round, a close shotgun blast;
  better tiers hit harder.
- City 17's Combine soldiers notice you within 170 px whichever way they
  are facing, unless there's a wall between you. Their cone of sight on
  the ground is unchanged; sneaking up right behind one no longer works.
  He has to turn round before he can fire.
- City 17: squads of three Combine soldiers now patrol the old town's
  roads, the plaza and the Citadel's square, keeping formation; when one
  of them spots you the whole squad stops and turns your way.
- City 17's Combine soldiers talk over their radios, standing at their
  checkpoints or out on patrol: a crackle of radio and what they said over
  their heads, a mate answering. They shout when they spot you and call it
  in when one of them goes down. Their volume has its own slider in the
  sound settings ("Combine soldiers' radio").
- City 17's Combine soldiers see twice as wide as before: their cones of
  sight are 60 degrees across (was 30).
- City 17's Combine soldiers hunt you: spot one and he comes after you
  (90 px/s, so a walk won't lose him but a sprint will), shooting as he
  comes, and his squad comes with him. Lose him and he searches where he
  last saw you. Shoot one from where he can't see you and he goes that
  way looking. When a soldier goes down, the others within earshot come
  to see what happened. They all go back to their posts and beats after.
- City 17's soldiers find their way round walls when they come to look
  into something, instead of walking into them and getting stuck.
- A-Man's theme plays from his intro screen in City 17 to the end of his
  quest.
- City 17 has citizens now, in their blue-grey jumpsuits, wandering the
  streets (no police there).
- Pedestrians scatter when a gun goes off near them, anyone's gun, in
  every city: a moment of shock, then they run for it.

### Fixed
- City 17: medkits and energy drinks no longer turn up bunched together
  on the railway behind the train, where nobody can reach them.

## [0.2.0] - 2026-10-01

A-Man arrives: a new city event with his own boss fight and theme, and
City 17, the first new map, at the end of his trail.

### Added
- A-Man, a new city event (host: F8). A very familiar man in a suit, fake
  glasses and a stuck-on moustache walks the city and teleports straight
  through anyone in his way for 60 damage. A line shows where he is going
  just before he goes: get off it. He also opens his briefcase and lets
  out a horde of sentry turrets that scuttle about spraying bullets in
  random directions; one shot knocks a turret over. He has his own theme
  music.
- City 17, a new map and the first stop on A-Man's trail: take "The man
  with the moustache" from the Jobs board and step off the train, then
  make your way through the station, the plaza, the old town, the wall and
  over the canal to the Citadel. He says hello when you arrive. Combine
  soldiers guard every checkpoint on the way: get past them (or through
  them) and reach the Citadel's doors to finish the job.
- Teleport, a new ability A-Man drops when he goes down: vanish and
  reappear up to 700 px away, tearing through anyone in between for 50
  damage. Never sold.

## [0.1.0] - 2026-09-30

The first numbered release: everything built so far, and this changelog to
keep track of what comes next.

### Added
- LAN multiplayer: host a game or join one from the server browser, with
  recent servers remembered. The host runs the world; everyone else sends
  what they want to do.
- Saved worlds: money, upgrades, loadouts, vehicles and property are kept
  between sessions, and owners who were offline still get paid.
- The city: a generated grid of roads, buildings, parks and parking lots,
  the sea round it, and surroundings past every map's edge (forest,
  beach, bluff, cul-de-sac and outskirts).
- Driving: cars built from their own models with their own handling, engine
  sound through four gears, skid marks, car-to-car collisions and name tags
  on parked cars.
- On foot: get out of your car and walk, sprint on stamina, dodge on Space,
  and take any empty car in reach.
- Guns and a gun wheel, a flamethrower, reloading, and damage types
  (bullet, explosive, fire, impact, shock, melee) with burning,
  resistances and hit and death effects to match.
- Abilities: heal aura, leap, panic fart, open borders, MG nest, second
  wind, overclock and more, each with its own icon and cooldown.
- Tiers for everything you equip: common, uncommon, rare and legendary.
- The inventory screen (I): drag guns, abilities, armor and clothes onto
  your character, trash what you do not want.
- Armor and gear: a kevlar vest, and clothes for the head, body, pants and
  shoes slots that each improve something.
- Money: Federal Commie Koins (Fcks), dropped by the dead and picked up
  off the road.
- The shop, with tabs for guns, ammo, abilities, supplies, cars and
  delivery drivers for hire.
- The gym: spend Fcks on health, stamina, reach, regen, slots and dodge
  distance.
- Real estate and buildings: buy plots, build factories, hospitals, shops
  and garages on them, and hire drivers to keep the factories fed.
- Quests from the Jobs building: Crazy Karen, the alien hunt, the D-Day
  landing and Shotgun's Bluff, each with its own boss, and bosses that tire.
- City events: a boss (the tripod, the runner and others) comes into the
  streets and goes after players and their buildings.
- Police that patrol, see crimes in their sight cones and chase you, and
  stand down while a city event is on.
- Pedestrians that wander the streets and flee from cars, and AI drivers.
- A minimap and a big map, arrows at the screen edge towards things off
  screen, a low-health halo and a tidy HUD.
- Settings for sound, controls, video and the server you host, a controls
  overview on F1, and cheats typed while playing.
- An inclusive mode on the main menu.
- A changelog on the main menu: the icon in the bottom-left corner opens it,
  and a dot on it means there is something you have not read yet.
- A version number, shown next to the changelog icon.

### Fixed
- The event menu (F8) is tall enough for every event's description.
