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
  and the Mess. Dark (the night feature), lit by blue strip lights, green
  screens, the reactor, the sludge and red alarm lamps over every door
  (they don't sweep yet).

## Decisions

| Question | Decision |
| --- | --- |
| Parody or its own thing? | **A parody**, like A-Man. Punned names (the Mood Slayer, the UAC as the Union of Awful Choices, Heck), never the real ones. |
| Who talks you through it? | **Nobody else. Your own inner voice.** Where Cyber Feud has VEX in your earpiece, here it is the hero's thoughts: a gravelly action-movie narrator that keeps slipping into a half-asleep person on a sofa. |
| How does it end? | **It was all a dream.** You beat the last boss, the screen goes white, an alarm clock is ringing, and you wake up on the sofa. |
| How long? | **Five maps**, like Cyber Feud and A-Man. |
| Is the dream hinted? | **Yes, more and more.** Each level leaks a bit more of the real world into the dream (a phone buzzing, a microwave, someone calling your name) until the last boss is the alarm clock. A player who notices gets the joke before the end; one who doesn't still gets it at the end. |
| Does it tie to Cyber Feud? | **Lightly.** The dream is built out of whatever you did that day: a demon with Kilowatt's reactor, a voice in a vending machine that sounds a lot like VEX. Nothing in the plot needs Cyber Feud played first. |
| Who's the enemy? | **Heck, and only Heck.** No factions and no infighting, unlike Cyber Feud: the UAC's possessed staff are Heck's lowest rank, and the whole horde works together against you. |
| Bosses? | **One on every level**, each at the level's end and in the way of its exit: the Floor Manager, the Cyberdaemon, the Baron of Heck, the Spider Mattressmind, the Snoozedemon. They follow the bosses' standard (`src/features/bosses`: breath, the boss bar, a medkit when badly hurt) and each gets its own brain module. |
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

- **The Floor Manager** (Fobos Base). The UAC's shift supervisor, a zombie
  in a yellow cargo-loader exosuit, still holding a clipboard. Guards the
  hangar lift. Slams forklift arms, throws crates, and calls zombie staff in
  "for a quick meeting". The most normal of the five: a dream that hasn't
  started being silly yet.
- **The Cyberdaemon** (Heck on Earth). A huge horned demon with a rocket
  launcher for an arm and, where its heart should be, a reactor that looks
  exactly like Kilowatt's. It stomps down the road to the starport after
  your truck: a driven boss fight, rockets landing on the road ahead and its
  feet shaking the screen.
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
| **Zombie staffer** | A UAC jumpsuit, a lanyard, a coffee mug in the other hand | 40 | Pistol (`bullet`, 8), slow to aim | Sits at a desk or stands at a post until someone comes in sight, then shambles at them (60 px/s) firing now and then. Fodder. |
| **Zombie guard** | UAC security armour, a cracked helmet | 60 | Shotgun (`bullet`, 6 pellets of 7) | Holds doorways and corridors, steps in to close range. |
| **Overtime guy** | Big, in a hard hat and hi-vis, a chaingun from the loading bay | 100 | Chaingun (`bullet`, 6 a round, 8 a second) | Spins up for 0.6 s (you hear it), then keeps firing at whoever he can see, sweeping slowly. Bad in the open, easy round a corner. |

#### The demons

| Unit | Look | Health | Attack | Behaviour |
| --- | --- | --- | --- | --- |
| **Imp** | Brown, spiky, hunched, orange eyes | 60 | Fireball (`fire`, 14, slow enough to sidestep); a claw up close (`melee`, 10) | The common demon. Comes out of vents and walls, strafes sideways between throws, climbs over low cover. Packs of 3-5. |
| **Pinky** | A pink muscle with legs and a huge jaw | 160 | Charge and bite (`impact` 30, a shove; `melee` 18) | Braces 0.5 s, then charges in a straight line; into a wall it reels for 1 s. Its front is armoured (rounds from in front do half); its back is soft. In the Foundry's dark some are **Spectres**, a shimmer you only see close. |
| **Lost Sole** | A flaming boot with teeth, flying | 20 | Dive (`fire`, 12) | Floats in flocks of 3-6, over lava and walls; one at a time picks a target, hangs back for 0.4 s and dives straight at it. One round brings one down. |
| **Cacodaemon** | A floating red tomato with one green eye and a big mouth | 220 | Spits a ball of fire (`fire`, 24); a bite up close (`melee`, 30) | Slow, flies over walls and lava. Opens its mouth for 0.5 s before it spits (a tell). Shot while its mouth is open it reels. On Earth they float over the road and spit at the truck. |
| **The Shoe Rack** | A floating brown ball with a mouth full of shoes | 180 | Spits a Lost Sole every 4 s, at most 3 out | Hangs back, flies. When it dies it spits three at once. Kill it first. |
| **Heck Knight** | The Baron's brown cousin, horned, 1.4x | 300 | Green fireball (`fire`, 20); a leap (`impact`, 30, lands 0.6 s after a shadow shows where) | Walks at you and leaps when you get far. The Foundry's north half and Heck. |
| **Revenaunt** | A tall skeleton in a cardigan, a rocket pod on each shoulder | 200 | Two homing rockets (`explosive`, 22 each, turning slowly; dodge round a corner); a punch (`melee`, 20) | Keeps at mid range, firing its rockets in turn every 3 s. The rockets can be shot down. Says something about your posture. |
| **Mancouchbus** | A huge fat demon in a recliner on tank treads, a flame cannon for each arm | 450 | Two fireballs at once, in a V (`fire`, 26 each); a flame burst up close (`fire` DoT) | Never gets up. Rolls slowly, turning to keep you in front; its back is the recliner (rounds do double). Heck and the Snooze Gate. |
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
| 2 | **Heck on Earth**: a city overrun, the road to the starport | Driven: an armoured truck through demon-filled streets | The Cyberdaemon | The radio plays the TV's adverts. A phone buzzes. |
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

The portal's leaked: Earth is overrun. You drive a UAC armoured truck
through a burning city to the starport, Pinkies ramming you and Cacodaemons
floating over the road. The truck's radio is meant to be mission control;
it keeps playing adverts for sofas. On the last stretch before the starport
the Cyberdaemon steps out of a burning tower and comes after the truck.

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
| `earth` | Heck on Earth | 36x180 | Driven | `eternal-mood-earth` |
| `foundry` | The Foundry | 56x64 | On foot | `eternal-mood-foundry` |
| `heck` | Heck | 60x96 | On foot | `eternal-mood-heck` |
| `snooze` | The Snooze Gate | 40x40 | On foot, the arena | `eternal-mood-snooze` |

Each quest's `next` is the following one, as Cyber Feud's are; the Snooze
Gate's star goes home. Everyone travels north (up the screen), the way both
quest lines before it do. Every level's exit is shut until its boss is down:
reaching it before then doesn't finish the level, and the objective line
points at the boss.

### Shared look

- Two palettes, and the dream moves from one to the other. The UAC's: grey
  steel panels, hazard stripes in yellow and black, green computer screens,
  blue strip lights. Heck's: dark red rock, black bone, orange lava, and
  everything lit from below.
- Light comes in pools: the `night` feature's dark with lamps, screens,
  fires and lava as the lights. Fobos Base's alarms sweep red over
  everything every couple of seconds.
- Pun signs and posters, the way Grey City has NOODLZ: UAC: WE OPENED IT SO
  YOU DON'T HAVE TO, PORTAL SAFETY WEEK (0 DAYS SINCE LAST INCIDENT), DEMON
  PARKING ONLY, HECK: NOW HIRING, MIND THE LAVA.
- The dream leaking in is drawn as well as said: a sofa cushion where a
  crate should be, a TV remote the size of a car, the corner of a lampshade
  in the sky, more of it each level.
- Each map gets its own theme music: heavy, fast, chugging metal, as Cyber
  Feud's maps have theirs.
- Lava is a hazard tile: walk in it and you burn (`fire` damage over time,
  the damage feature's DoT, like the Winding Road's poison); drive over it
  and the car burns. Cars and players can't stop on it.

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
  the lift in his loader and wakes when someone walks in.
- **The end:** the hangar lift. The EXIT star, once he's down: "HECK ON
  EARTH".

### 2. Heck on Earth (`earth`, 36x180, driven)

One long road north through a burning city to the starport, like the
Overpass but on the ground: a six-lane boulevard with the city's blocks
solid either side, crossroads every 20 tiles or so where side streets run
off (blocked a block in with wrecks and fire). Past the edges the city is
burning (a surroundings file, `heck_on_earth.lua`: towers on fire, smoke,
a red sky, a portal's glow over the skyline, Cacodaemons drifting over it).

- **Arrival:** the bottom, at a UAC motor pool, everyone behind the wheel of
  a **UAC Hauler**, lent by the map the way the Overpass lends the Courier
  (city-map's `loaner` with `issued`): a squat armoured truck in hazard
  yellow with a cannon on the roof the driver fires. The radio beat (the
  sofa advert) on pulling out.
- **The Suburbs:** the first stretch. Houses either side, burning, Pinkies
  charging out of the side streets to ram you, imps on the rooftops.
- **Downtown:** the middle stretch. Taller blocks, abandoned cars and buses
  as obstacles, a collapsed overpass squeezing the road to two lanes,
  Cacodaemons floating over the road spitting fireballs. A phone buzzes
  here (the beat).
- **The Crater:** two thirds of the way up, a portal has opened in the road.
  The road splits round it, lava in the middle, demons pouring out of it.
- **The Boulevard:** the last stretch, long, straight and wide, with the
  starport's gate at the top. The Cyberdaemon steps out of a burning tower
  at the bottom of it and walks up the road after you: you fight him from
  the truck, out-driving his rockets and turning to fire.
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
2. "Earth. Home. On fire. The truck's got a full tank. So have I."
3. "A factory that melts demons. Somebody's going to melt. Not me."
4. "Heck. Hot, loud, full of demons. ...Is it hot in here, or is it the blanket?"
5. "One big demon left. Then I'm going back to... where was I going?"

### Story beats

- **Fobos Base**
  - The lab door opens: "Rip. Tear. In that order."
  - The reactor room: "Reactor's humming. Weird hum. Sounds like a fridge."
  - The Floor Manager wakes: "A manager. In a forklift. Finally, a fair fight. For him."
  - The Floor Manager down: "Meeting's over."
  - The end, the lift: "Going up. The demons are going down."
- **Heck on Earth**
  - Into the truck: "Mission control on the radio. ...That's an advert for sofas."
  - A phone buzzes on the road: "That's not my phone. I don't have a phone. I'm a space marine."
  - The Cyberdaemon steps out: "That's a big one. With a reactor. I've seen that reactor before. Where have I seen it?"
  - The Cyberdaemon down: "Bigger they are. Louder they land."
  - The end, the starport: "Starport. Last shuttle to the Foundry. I'm driving."
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
  - The Cyberdaemon: roars only, and its reactor whines before every rocket.
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
