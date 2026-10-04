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

### Added
- A-Man's trail goes on: take the star at the Citadel's doors in City 17
  and he steps out in front of you, and sends everyone the long way round,
  to the Outer City: packed concrete blocks, canals and bridges, parks,
  and a big open square on an island in the middle. Nobody there yet.

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
