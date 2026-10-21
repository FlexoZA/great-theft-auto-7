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

### Fixed
- The Baron of Heck no longer gets stuck on corners and low walls in the Foundry: he feels his way round them,
  and takes the long way round what he can see you past but can't get his shoulders through.
- The Floor Manager no longer gets stuck going after you round Fobos Base: he only takes ways his chair fits
  through, feels his way round corners, and no longer rocks on the spot at a corridor's mouth.

## [0.39.2] - 2026-10-20

The Floor Manager traded his spider legs for an executive chair on a rocket.

### Changed
- The Floor Manager has lost his spider legs: he floats about the Hangar in an oxblood executive chair on a
  rocket, its flames roaring behind him. For his stomp he rises on full burn and drops the chair on you.

## [0.39.1] - 2026-10-20

Kilowatt is more machine than man now, with two spikes on his back and lightning crackling between them.

### Changed
- Kilowatt looks more machine than man: gunmetal plating, steel arms, an armoured back plate, and two insulator
  spikes standing up off his back with a blue arc crackling between them. It runs white while he vents and forks
  once he's lit (phase 2).

## [0.39.0] - 2026-10-20

The game has a wiki: a page for every enemy, with its picture, its numbers and how to beat it.

### Added
- A wiki for the game, in `docs/wiki` on GitHub: a page for every enemy with its picture, its health, what it
  carries, what it can do and how to beat it, written from the game's own numbers.

## [0.38.0] - 2026-10-20

Halcyon's dropship now flies troops in to guard VEX's relays on the Roof, and the helipad is the only way home.

### Changed
- The Roof: there is no HOME star at the top of the stairs any more. The only way home is the one on the helipad
  once VEX gets away.

### Added
- The Roof: while VEX holds the roof she calls in Halcyon's dropship, a rocket tiltrotor. It hangs over the relay
  you're going for, its landing spot ringed in magenta, and puts a squad of officers down to guard it, then flies
  off. It comes back every 35 s while fewer than 5 of its officers are up, and right away whenever you breach a
  relay. Each drop also brings one of Grey City's harder enemies, in turn: an assassin droid, a riot-shield enforcer
  or a brute. From its second drop on, one of the officers is an elite: black armour and a gold helmet, a gold
  diamond over him, three times the health and a harder-hitting rifle.

## [0.37.0] - 2026-10-19

VEX's relays on the Roof are closer together, warn you before they shock you, and the last one can be finished.

### Changed
- The Roof: VEX's four relays stand round the helipad instead of in the corners, so the run from one to the next
  is about half as long (about 1450 -> 770 px).
- The Roof: the relay VEX is at has a red ring breathing round it instead of a green one, and her face on its
  screen.

### Fixed
- The Roof: VEX's relay now warns you before it shocks you. For 2 s before each pulse its reach lights up blue on
  the ground and fills in from the middle, with static crackling in it that builds as it charges, it whines, and
  "VEX's relay is charging - get clear!" shows while you're inside. Before, the pulse hit at once with no warning
  and, on a job finished before, stunned you. Her pulses also come less often: every 4 -> 6 s.
- The Roof: VEX's last relay can be breached. Her relay no longer drains from the warning until 1 s after the pulse,
  so stepping out of it (or being stunned by it) doesn't lose what you had done. Before, the drain took back more
  than you could put in, and the last relay, always hers, couldn't be finished alone.
- The Roof: let go of a relay and it waits 0.45 -> 1.5 s before it starts losing what you had done.

## [0.36.0] - 2026-10-19

Bullets now spark and leave marks on walls, and every job level has a name, shown on the victory screen and the board.

### Added
- Bullets that hit a wall, building or rock now spark and kick up a puff of dust and grit where they strike, and
  leave a pock mark for a few seconds. Everyone in the world sees them.
- Every job level has a name, from Easy (level 1) through Hard, Brutal, Carnage, Rip and Tear and Nightmare up to Hell
  on Earth (level 11, the last). The victory screen shows the level you just finished and its name, and the job board
  shows the name next to each job's level.

## [0.35.1] - 2026-10-19

A fix for your own shots bending along with your MG nest's sweep.

### Fixed
- Your own shots go where you aim again while your MG nest is firing: its sweep no longer bends them (a breached
  Cyber Feud turret did the same).

## [0.35.0] - 2026-10-19

Finishing a job now ends on a victory screen with your stats, and the EXIT star keeps clear of a fallen boss's loot.

### Added
- Finishing a job now shows a victory screen with how it went for you: the time it took, enemies killed, bosses
  beaten, deaths, Fcks picked up and anything you unlocked. The star home puts it up (Enter goes home, Backspace
  stays to pick things up), and anyone taken home by someone else sees it on arriving.

### Fixed
- The EXIT star no longer comes up on top of a fallen boss and the loot it drops: it stands at least 240 px away,
  on open ground.

## [0.34.0] - 2026-10-19

Kilowatt and the Hunters now warn you before they stun you, and VEX's relays on the Roof are easier to follow.

### Changed
- Kilowatt's arc whip (Cyber Feud, the Roof) now shows a flickering line from his fist for 0.5 s (was a 0.45 s
  crackle you could barely see) and only hits whoever is still on that line: step off it and it misses.
- Kilowatt's slam now marks how far its shock ring will roll (230 px, 330 px in phase 2) while he is in the air.
- The Hunters' stun shot now shows a line where it will go while they charge, and goes down that line: step off it.
- VEX on the Roof stays at a relay for 20 s before moving to another (was 11 s).
- On the Roof the objective line now names the relay to breach ("breach the top-left relay"), steering you away from
  the one VEX is guarding, and a white arrow hovers over it.

## [0.33.0] - 2026-10-18

Jobs unlock one at a time and come back harder every time you finish them, and Crazy Karen drops an uzi.

### Added
- Crazy Karen drops an uzi for every player when she goes down. The uzi is now a won gun: pick one up to unlock it
  in the shop (factories no longer make them). The first time it is always common; beat her again for a chance at
  uncommon, then rare, and from the fourth time legendary (up to 12%).
- "Inventory full" now shows over a dropped item you can't pick up because your bag has no room.

### Changed
- Every job comes back harder each time you finish it, up to 10 times (Karen's rage now works on all of them).
  Bosses: +25% health (Karen 1500 -> 1875 -> 2250 ...) and +15% damage (her slap 15 -> 17 -> 20 ...). Enemies:
  +10% health and +10% damage. Helpers and enemy groups: +20% more of them (Karen's simps 5 -> 6 -> 7 ...). The
  boss bar shows how many times over it is ("HARDER x2"; Karen's says ANGRIER).
- Bosses' per-player drops come in better tiers each time you beat them again, the way Karen's uzi does.
- The job board shows the level each open job is at (LEVEL 1 the first time, one more per finish, up to LEVEL 11)
  and how many times you finished it ("DONE x3").
- Jobs unlock one at a time: a new game opens only Crazy Karen, and finishing a job opens the next on the board
  (Karen, the alien hunt, D-Day, Shotgun, A-Man, Cyber Feud, Eternal Mood). Finished jobs can be played again,
  and a saved world remembers how far you got.
- City events wait for their quest: Bigfoot comes to town only after the alien hunt is finished, and A-Man only
  after his quest. The Runner and the Tripod can come any time.

### Fixed
- Finished jobs are saved as soon as you are back in the city. Before, quitting while on a job could lose every
  job finished since the last autosave.

## [0.32.0] - 2026-10-17

The Antlion Guard is redrawn, quicker and calls a Hunter-Chopper for help; medkits and drinks move next to WASD.

### Added
- The Antlion Guard calls for help: at 60% and again at 20% health a Hunter-Chopper sweeps in low from behind you,
  drops 3 rollermines on you and flies off. It doesn't shoot. Watch your back when the rotor starts up.

### Changed
- The Antlion Guard on the Coast looks like the new antlions: olive plates rimmed in orange over its back, a pointed
  tail and long orange spiked legs, under its shovel of a head plate. It is smaller and quicker on its feet: body
  34 -> 24 px, running 150 -> 190 px/s, prowling 90 -> 120, walking winded 42 -> 55, turning 2.4 -> 4.2 rad/s,
  charging 440 -> 480 px/s every 4 s (was 5), reeling 2.2 -> 1.6 s after a crash. Its swipe is quicker: reach
  62 -> 50 px, landing 0.32 -> 0.24 s in, 0.9 -> 0.7 s between swipes.
- New default keys: use a medkit on Q (was H), drink an energy drink on E (was J), and ask VEX to open a locked
  door in Halcyon Tower on T (was E). If yours stay on the old keys (you rebound them, or reset your controls
  before), reset the controls in the settings to get the new ones.

## [0.31.0] - 2026-10-17

Walls you can't shoot past cast shadows on every map, rounds fly over water, and the antlions look like Half-Life's.

### Changed
- Every wall casts a shadow now, on every map: the map's edges, mountains, the Tower's floors and the Roof's parapet,
  Earth's hedges and waste ground, the Citadel's catwalk rails, fallen-building rubble, and Cyber Feud's barriers,
  drums, shelves, lockers and the rest. If it has a shadow, rounds stop there.
- Rivers, canals and the sea no longer stop rounds, sight or grenades: you can shoot across them and off the side of a
  bridge. You still can't walk or drive into the water.
- Antlions look like Half-Life's now: an olive shield of orange-rimmed plates on their back, a pointed tail, a wedge
  head and long spiked stilt legs. Their wing covers swing open outward when they fly.

## [0.30.1] - 2026-10-16

Your shots leave your gun again when you sprint and strafe.

### Fixed
- Your shots come out of your gun when you sprint and strafe. They used to start from where the host had you, behind
  where you see yourself, and showed up a moment late where you'd been, so they seemed to come out of your side. Your
  own shots are drawn from your gun the moment you fire now, and the host starts them where you are (within reach).

## [0.30.0] - 2026-10-16

Eternal Mood is no straight run any more: every level hides terminals (Heck's are seals) that open the lift, the road's blast gates, the Crucible's doors and the bone wall to the Mattress.

### Changed
- Heck's ramp up to the Mattress is barred by a wall of bone until you light four seals: one on each island out in the
  lava, one at the Altar Fields' west end and one on the pizza lake's shore.
- The Foundry's way up into the Crucible is shut by blast doors until you've hacked four terminals: in the Front
  Office, the Loading Bay, out on the Conveyors' far walkway and at the Smelters' west end.
- Heck on Earth's road is shut by three blast gates. Each opens from a terminal off the road: one down a side street in
  the Suburbs, two down Downtown's side streets, one on the Crater's far rim past the lava.
- Fobos Base's lift won't run until you've hacked four terminals, one each in Crew Quarters, the Mess, the Offices and
  Toxic Storage (and the Floor Manager is down). Hold F at one for 3 s; the alarm brings the horde nearby, so cover
  each other. The HUD counts them and the minimap marks them.

## [0.29.9] - 2026-10-16

Mecha Zombies guard the Intern mobs, who are busy eating, and scream the horde down on you; and enemies' uzi rounds show all the way again.

### Added
- Mecha Zombies on Fobos Base, Earth and the Foundry: zombies the UAC rebuilt with a plasma cannon, a flamethrower and
  talons. One walks round every Intern mob. They fire plasma from afar, flame you at mid range and slash up close, and
  when they wake they scream: a sound wave goes out and every zombie and mob in it comes for you.
- The Interns' mobs are eating: each crouches round a body it dragged in, a trail of blood leading to it, until
  something wakes them.

### Fixed
- Enemies' uzi rounds (Cyber Feud's troops, stings, turrets, interceptors and drones, the Hunters, A-Man's turrets,
  the Bent Cops) disappeared on screen after about 360 px while they flew on and hit you from further away. They are
  drawn all the way now. A better tier's flamethrower flame is drawn as long as it really reaches too.

## [0.29.8] - 2026-10-16

Eternal Mood gets its polish: walls that look solid and cast shadows, lava that flows with ragged shores, and every level filled out; and the uzi becomes a close-range 9mm sprayer.

### Changed
- Heck is fuller. Braziers burn at the Altar Fields' edges among rib cages, skull piles, bone spikes and glowing rune
  circles; gouges and skulls mark the Mattress's plateau; and the ramp up to it is steps cut into the rock instead of
  grey slabs.
- The Foundry is fuller. Slag spilled round the Smelters' vats, ingot moulds still glowing, stacks of ingots and pipes
  along the wall; bones, skulls, bone spikes and burning braziers across the Crucible's floor; a copier in the Front
  Office; pallets, tyres, a fuel hose and oil in the Loading Bay and on the Landing Pad.
- Heck on Earth is fuller. Front yards have what people left in them (trampolines, swings, burnt garden beds, lawn
  chairs, bikes, mailboxes, a kennel now and then), Downtown's sidewalks have hydrants, and debris, oil and skid marks
  are strewn down the roads and the Boulevard. Roofs have dormers, solar panels and dishes, and the towers have stair
  hatches, vents, skylights, aerials and the odd helipad.
- Fobos Base is fuller. Server racks and cable runs in the Lab, footlockers, a rug and laundry in Crew Quarters,
  chairs round the Mess's tables and vending machines on its wall, cables and coffee in the Offices, hazard paint and
  leaks round the Reactor, hazmat lockers and painted hazard boxes in Toxic Storage, and a workshop round the
  Hangar's walls (workbenches, tool chests, tyres, fuel drums) with oil, skid marks and pallets on its floor.
- Eternal Mood's lava flows: the Foundry's moat and Heck's lava sea have ragged shores of cooled crust, glowing where
  they meet the molten lava, lumpy crust drifting on a slow current and bright seams opening and closing. Lava next to
  lava is one body now, not a row of squares.
- Eternal Mood's walls stand up: on every level a wall shows its face over the floor and casts a shadow across it, so
  you can see what you can't shoot over. Heck's rock walls are darker than its floor, Earth's buildings cast shadows
  as long as they are tall, and the ground outside each map (moon dust, waste ground, tarmac, the abyss) is smooth
  instead of blocky.
- The uzi fires 9mm rounds, the same as the SMG (the pistol never needs any). Uzi ammo is gone: any you had becomes
  9mm, and 9mm boxes now drop as often as uzi ammo did.
- The uzi is a close-range gun: its rounds are spent after about 360 px (1080 -> 360). It still fires fourteen a
  second.

## [0.29.7] - 2026-10-16

Dread Knights stalk Earth, the Foundry and Heck, blades out; and the Mood Slayer's helmet gets its detail, the same on you as in the bag.

### Added
- Dread Knights, Heck's elite: black plate, a horned helm and a blade out of each arm. Two on Earth, two in the
  Foundry's Smelters, three on Heck's Fields. They weave in, slash up close and lunge from a few steps off, each with
  a tell (his reach or his lane shows on the floor). A hit does 26, knocks you back and stuns you for 1.2 s, and 70%
  of the time it's a deep wound (6 s at 6 a second; a medkit stops it). They let you get up, then lunge straight
  away: dodge it. They dodge your rounds on their breath, back off when winded, and go for medkits when hurt.

### Changed
- The Mood Slayer's helmet is drawn in more detail (a crested shell, a riveted brow, the amber visor with depth and
  glints, ear guards with lamps, a vented breather, claw marks), and your character in the inventory now wears that
  same helmet instead of a different one.

## [0.29.6] - 2026-10-16

Eternal Mood's demons sharpen up: the Baron of Heck is half the size and harder to hit, the Cacodaemons look ahead with a meaner face, and the shuttle's engines point the right way.

### Changed
- The Baron of Heck is half the size (hitbox 30 -> 15 px), so he's harder to hit and gets clear of your rounds more
  easily. His claw reach (95 -> 65 px) and charge hit (46 -> 31 px) shrink with him.
- The Cacodaemons look meaner: their eye looks ahead out of their face under a heavy brow instead of straight up, and
  they have darker veined hide, two horns curving back and yellowed teeth.

### Fixed
- The Eternal Mood shuttle's engines point backwards now: flared bells with oval mouths instead of round nozzles
  facing up.

## [0.29.5] - 2026-10-15

The shuttle you land in on Eternal Mood is drawn in full: lit portholes, blinking nav lights, glowing engines and its ramp down.

### Changed
- Eternal Mood's shuttle (on Earth and in the Foundry) is drawn in full: a rounded hull with panels, rivets and lit
  portholes, a framed canopy, delta wings with flaps and blinking red and green nav lights, a tail fin, three engines
  still glowing and steaming over a scorched pad, a strobing beacon, and its ramp down and lit from inside.

## [0.29.4] - 2026-10-15

The Baron of Heck comes after you wherever you hide, leaps over the lava, dodges your rounds, and has guns for hands.

### Added
- The Baron of Heck leaps. At anyone a fair way off (300 px or more), and always at anyone across the lava from him,
  he crouches with a red ring on the floor where he'll land, sails over the lava and comes down on you: 45 damage and
  a big shove. He's slow to get up after.
- The Baron of Heck dodges. A round about to hit him and he throws himself aside, if he has the breath for it (a
  fifth of his bar each time, and only while he has more than half). His breath shows as a bar under him once he's
  spent some, throbbing red while he's winded: wind him and he can't dodge.

### Changed
- The Baron of Heck comes after you. Hanging back in the Smelters no longer keeps him on his spot by the pit: he
  follows you anywhere on the map, and he notices you as soon as he can see you instead of only when you step onto a
  bridge.
- The Baron of Heck gets his breath back while circling you; before, he could stay stuck short of breath for the
  whole fight.
- The Baron of Heck has a new look: broad horned shoulders, guns for hands (his green fireballs come out of the
  barrels), a goat's skull with glowing eyes, a tail.

## [0.29.3] - 2026-10-15

The Hunters tire: run them ragged and they can only walk, with a breath bar under each to show it.

### Changed
- The Hunters tire now. Closing in, strafing and backing off wear them out (about ten seconds of it), and each dodge
  costs a quarter of their breath. A blown Hunter can only walk and can't dodge until it gets its breath back (a few
  seconds), and an energy drink it finds puts it all back. A thin bar under each one shows its breath once it has
  spent some, throbbing red while it is winded. Cyber Feud's assassin droids think the same way and tire too.

## [0.29.2] - 2026-10-15

Halcyon's soldiers carry the new AR, and ammo crates hold half as much.

### Changed
- Ammo crates on quest maps hold less: a crate spills 4 -> 2 ammo boxes. There are still 5 crates on every map.
- Halcyon's soldiers in Grey City carry the AR now: most of them have one (in bursts of four), the rest an uzi or a
  pistol as before. Their rifles reach further than the uzis did (about 1170 px against 920).

## [0.29.1] - 2026-10-15

The AR, a faster and straighter rifle than the AK, firing the same rounds, which are 7.62 rounds now.

### Added
- A new gun, the AR: an assault rifle firing about twelve rounds a second against the AK's nine, 15 damage a round
  against its 18, with half its scatter and faster rounds. It fires the AK's 7.62 rounds. 140 Fcks in the shop.

### Changed
- The AK-47's rounds are 7.62 rounds now (they were "AK-47 rounds"); the ones you have keep working, in the AK and
  the new AR.

## [0.29.0] - 2026-10-15

New music on three quests, the A-Man trail's last maps no longer end in a bare grid, a leap that hits enemies as
hard as it hits players, and a freeze and some stuck soldiers fixed.

### Added
- Three quests get their own music: an eerie whistle in the woods of Whispering Pines (the alien hunt), a snare-drum
  march with brass for the beach landing (D-Day), and a twangy spaghetti-western standoff on Shotgun's Bluff.
- The Outer City, the Winding Road and the Citadel no longer end in a bare grid: City 17's outskirts run on past
  the Outer City's wall, mountains, forest, the river and snow round the Winding Road, and the Citadel's abyss
  (girders, pods on their rails, far-off platforms) all round its catwalk.

### Changed
- A leap's landing hits enemies as hard as it hits players: 20 -> 45 for the leap, 20 -> 70 for Bigfoot's leap, and a
  better tier hits harder still. Enemies that always take a set amount per hit (Karen, the D-Day troops, police
  officers) are unchanged.

### Fixed
- The leap now hurts the Hunter-Chopper.
- Soldiers on the Market and in Halcyon Tower, and a staffer on Heck on Earth, no longer start stuck inside a wall
  where nothing could reach them.
- The game no longer freezes when you leap or teleport right on top of a Hunter or an assassin droid.

## [0.28.4] - 2026-10-15

The SMG, won off the Hunter-Chopper: faster than the AK, shorter reach, firing 9mm, which is back.

### Added
- A new gun, the SMG: fifteen rounds a second against the AK's nine, tighter than the uzi, but spent by about 500 px
  (the AK reaches 1200). The Hunter-Chopper drops one for every player in the Outer City; pick it up and the shop
  sells it to you from then on (110 Fcks). It fires 9mm rounds, the pistol's: 9mm is back in the shop (60 for 35
  Fcks), the ammo factory, enemies' drops and the ammo crates. The pistol still never runs out.
- The Combine soldiers in City 17 carry SMGs now and then.

### Fixed
- A super shotgun in your bag (not in a weapon slot) is no longer lost when a saved world is loaded.

## [0.28.3] - 2026-10-15

Ammo crates on every quest map: press F or shoot one for a dump of ammo, AK rounds most of all.

### Added
- Ammo crates on every quest map, five of them: walk up and press F, or shoot one, and it breaks open into four
  boxes of ammo, a magazine and a half each. AK rounds come out of them more often than off enemies.

## [0.28.2] - 2026-10-15

The Baron of Heck drops the super shotgun, the Mood Slayer's own: twice the pellets and the reach of a shotgun.

### Added
- The Baron of Heck drops the super shotgun, the Mood Slayer's own, one for every player: 12 pellets a pull instead
  of 6, twice a shotgun's reach and 10 shells a magazine instead of 6. It fires ordinary shotgun shells. Pick it up
  and it's yours with a magazine's worth of shells, and the shop sells it to you from then on (260 Fcks).

## [0.28.1] - 2026-10-15

The Mancouchbus drops the Mood Slayer's helmet, and a boss's reward you haven't unlocked yet now stands out on the road.

### Added
- The Mancouchbus drops the Mood Slayer's helmet, one for every player: rockets and blasts hurt 30% less and fire a
  fifth less. Pick it up and it's yours, and the shop sells it to you from then on (120 Fcks).

### Changed
- A boss's reward on the ground you haven't unlocked yet (the Mood Slayer's helmet, Volt's electric grenades) stands
  out: gold rings ripple out from it, NEW bobs over it, and it lights up in the dark.

## [0.28.0] - 2026-10-15

Eternal Mood: a new quest line, on foot all the way. Take the pest-control job up to Fobos Base, then down through
Heck on Earth and the Foundry into Heck itself, past the Floor Manager, the Mancouchbus, the Baron of Heck and the
Spider Mattressmind to the Snooze Gate. Each map has its own boss and its own metal theme, and lava burns.

### Added
- A new job on the board, "Pest control": the start of the Eternal Mood quest line. Fobos Base, the UAC's moon base,
  in the dark, everything in it red: wake up in the Lab and find your way up to the Hangar's lift.
- Heck holds Fobos Base: the possessed UAC staff at their desks and posts (staffers with pistols, guards with
  shotguns in the doorways, the overtime guy spinning up his chaingun by the lift), and imps bursting out of the floor
  vents as you come near, throwing fireballs you can sidestep.
- The Floor Manager holds Fobos Base's lift: the UAC's shift supervisor, promoted out of his body, his brain in a
  glass dome on a four-legged spider walker with a plasma cannon. He charges the cannon and sprays streams of plasma
  that drag after you (three at once below half health), stomps whoever gets close (the ring shows first), and calls
  staff in for a quick meeting at two thirds and a third of his health. Shoot his cannon off and he has to come and
  stomp you instead. The lift is out of service until he's down.
- Patrols of the possessed walk Fobos Base as squads: up and down the Ring, round the Offices' desks, the
  Reactor's catwalk, Toxic Storage and the Hangar's floor. When one of a squad sees you, the whole squad comes.
- The possessed fight smarter: guards sweep the doorways they hold, fight from cover, go to ground when shot from
  out of sight and then come looking, and some throw grenades; the overtime guy fights from cover round his post;
  and one of them going down brings the others near to see why.
- The Interns: the UAC's unpaid interns, possessed and unarmed, in mobs all over Fobos Base. They stand about until
  you come near, then the whole mob shambles after you, arms out, and claws. One shot drops one; the trouble is
  the other seven. The Floor Manager's meetings bring a few in too.
- Eternal Mood has its intro screen: the Mood Slayer's own voice in his head, typed out in a thought bubble beside
  his helmet, over Heck's glow and rising embers, with a power chord. Watch his eye behind the visor: he keeps
  nodding off.
- Fobos Base has its own theme: rip-and-tear metal, tuned way down, chugs, diving synth bass and a screaming lead.
  It starts in the dream, a lullaby on a music box over a snore, until the floor drops out.
- Heck on Earth, Eternal Mood's second map: off the shuttle from Fobos Base and up one long road through a burning
  city to the starport, on foot all the way (no driving on this quest line). Houses on fire in the Suburbs, wrecked
  buses and cars to hide behind Downtown, a fallen overpass squeezing the road to one gap, a lava-filled crater where
  the portal opened, and the Boulevard's sandbags up to the starport's gate. Possessed guards behind the wrecks,
  mobs of interns in the side streets, imps out of the manholes and the cracks round the crater.
- Cacodaemons float over Heck on Earth: big red one-eyed demons that fly over roofs and lava, spit balls of fire
  (watch for the mouth opening first) and bite whoever gets close. 220 health; shoot one in its open mouth and it
  takes extra damage and reels.
- Heck on Earth has its boss: the Mancouchbus, a huge fat demon in a recliner on tank treads, a rocket launcher for
  each arm, parked in front of the starport's gate. He fires rockets from both arms in turn and sweeps fans of them
  across the road (look for the gap), bumps you away with his belly if you get close, and shouts for Cacodaemons.
  He's slow to turn, and his back is the recliner: shots there do double. The gate stays closed until he's down.
- Heck on Earth has its own theme: faster thrash metal, galloping riffs and tremolo picking, air-raid sirens wailing
  through it and car horns in the breakdown. It starts in the dream, a sofa-sale jingle on the telly and a phone
  buzzing, until the siren drowns it out.
- The Foundry, Eternal Mood's third map: the UAC's factory, where they melt Heck down, half of it already Heck's.
  Off the shuttle onto the landing pad, through the loading bay and Dr. Seek's office, across the conveyor belts
  (they carry you, and anyone else standing on them: walk against one and you go nowhere), through the smelters'
  vats of lava to the Crucible, a pit of lava ringed by a lava moat, and the portal behind it.
- The Foundry has its boss: the Baron of Heck, a big horned brute on goat legs, waiting on the stone ring round the
  Crucible. He throws green fireballs in pairs (one where you are, one where you're going), puts his horns down and
  charges (dodge it and he runs into the wall and stands there dazed), claws you up close, and roars, throwing you
  back while imps climb out of the lava. He drops the key to the Snooze Gate; the portal stays sealed until you pick
  it up. And then somebody far away asks if you're awake.
- Lava burns: you can walk into the Crucible's lava, the Smelters' vats or Heck on Earth's crater now, but you'll catch
  fire. You can also shoot across lava; demons won't set foot in it.
- The Foundry has its own theme: heavy industrial metal, guitars locked to a machine, anvils ringing, steam hissing
  out of the press and a choir rising where the factory turns to Heck. It starts in the dream, on a cooking show,
  until somebody far away calls and the press slams down.
- Heck, Eternal Mood's fourth map: out of the portal onto a shelf of rock, across a sea of lava by bridges of bone
  (three ways over, one of them very narrow), over the Altar Fields with their altars, spikes and fire pits, past a
  pizza box the size of a house sinking in a lava lake, and up to the Snooze Gate. Imps climb out of the cracks
  and Cacodaemons float over the lava. Past the edges: lava falls, castles hanging upside down, and a crack in the
  sky with a lampshade hanging through it.
- Heck has its boss: the Spider Mattressmind, a giant brain on mechanical spider legs, standing on the mattress it
  drags everywhere, in front of the Snooze Gate. Its chaingun spins up and sprays after you (keep running across
  it), its legs slam down if you get close, and once it's half down it starts yawning: each yawn pulls you in, then
  snaps shut. The mattress soaks up shots from the front, so get round it. The Snooze Gate stays locked until it's
  down.
- Heck has its own theme: black metal blast beats and slow doom, a choir, a church organ and bells tolling. The dream
  is wearing thin: it starts with a microwave warming a pizza, and halfway round everything stops for Fobos Base's
  music box lullaby, slowed and out of tune, before a yawn and the blast tearing back in.
- Fobos Base looks the part: sharper desks, crates and posters, the reactor's core pulsing inside a halo of light
  and sparks, alarm lamps turning like beacons over the doors, strip lights on the blink, and the mess of the night
  everywhere: knocked-over bins spilling rubbish, scattered memos, blood, scorch marks, broken glass, chairs on
  their sides.

## [0.27.1] - 2026-10-14

A quieter mix out of the box: footsteps, the Combine soldiers' radio and pickups start lower.

### Changed
- Quieter default sound levels: footsteps 60% -> 25%, the Combine soldiers' radio 70% -> 40%, pickups 70% -> 60%.
  Levels you already set in Settings stay as they are.

## [0.27.0] - 2026-10-14

Cyber Feud: a new quest line through Grey City at night. Carry the Shard across five maps from the Drop to the roof
of Halcyon Tower, caught between Halcyon and the Static, past General Volt, Saye and Kilowatt, and then VEX. It
also brings the Courier, rain and storms, and the electric grenade, the first thing you unlock.

### Added
- A new job on the board, "Courier wanted": the start of the Cyber Feud quest line in Grey City. Five maps so far,
  driven and on foot, from downtown to the roof of Halcyon Tower; for now each is the way through, with its fights
  still to come.
- Night: Grey City is played in the dark, lit by neon, street lamps, your headlights and a torch on foot.
- The Shard stays with you through all five levels of Cyber Feud. Whoever carries it has to reach each level's end
  for the job to go on; if they go down, it drops where they fell (marked on the minimap and the big map) and anyone
  can pick it up. On the Roof, once Saye and Kilowatt are down, take it to VEX's uplink by the billboard: she shows
  you what is on it, and then she turns on you.
- Cyber Feud's story: take the Shard from the vending machine on the Drop (F), meet VEX, your fixer, who talks you
  through every map, and see each map's title card, where you are and what to do next.
- Cyber Feud's factions on the Drop: Halcyon officers hold the roadblocks and the Static's gangers roam the west.
  They ignore you until the Shard is taken, then come for you and for each other.
- Guard stations on the Drop: each faction holds a few yards on the avenues with an MG nest out front and a
  garrison inside that comes out when you get close.
- Halcyon's assassin droids guard the tunnel at the end of the Drop: cloaked robots with rail pistols that dodge
  your shots (then need 3 s before they can dodge again) and line up a rail shot you can see coming. Two of them,
  one more for each extra player.
- The tunnel end of the Drop is held by Halcyon alone, so its roadblock is still standing when you get there.
- Grey City carries on past the edge of the Drop: towers and neon, street lamps and traffic going by, a sea of
  lights in the dark.
- Flying machines cross the sky over the Drop now and then: Halcyon's aerodyne sweeping its searchlight, a cargo
  hauler with a container slung under it, and an ad drone towing a holo billboard. You hear each one coming.
- People on the Drop's streets: a thin crowd out late in the rain, who scatter when the shooting starts.
- The Drop has its own rock theme: it kicks in the moment someone takes the Shard and carries the chase to the
  tunnel.
- The Market is held now: Halcyon officers in the gaps of the south gate and behind the east line, squads walking
  the east side and Noodle Square, and the Static's gangers on the western corners, roaming the west lanes and
  pouring out of their chop shop. They leave you alone at the tunnel's mouth and wake the moment you walk in, and
  they fight each other as hard as they fight you.
- Halcyon's enforcers hold three of the Market's gates: riot shields that stop every shot from in front, a
  shotgun, and slow to turn. Get round their side, or blow them up.
- The Static's rippers stalk the Market's west lanes: blades out, they go for whoever is on their own, crouch
  with a cyan line on the ground showing where they will go, and lunge down it. Step off the line.
- The Static's sparkers hang back in the Market and lob EMP grenades: a cyan ring on the ground shows where each
  will land. Get out of it, or the jolt stuns you.
- The Overpass has its own darksynth theme, a night drive: it kicks in as Kilowatt's rig roars past.
- The Overpass is a bridge now: steel girders and railings along its edges, piers under it, and cable-stay towers
  with red lights either side. Grey City lies a long way below it, sliding slowly by as you drive: streets full of
  traffic, lit towers and a river the bridge crosses halfway up.
- Halcyon has blast gates across the Overpass. Nothing drives through a shut one: get out, hold the action key at
  the control panel beside it while the others cover you, and the guards behind it come running.
- Each blast gate on the Overpass is guarded on your side: an MG nest in the middle of the road, riflemen behind
  barriers either side of it who take over the gun, and two riot shields out in front holding the road.
- The car station prompt now names the car it calls (a Courier on the Overpass, a Scout Car on the Winding Road).
- The Overpass has car stations along the shoulder: lose your Courier and walk onto the nearest green pad to call
  it back, and if you die you can come back at any pad you have passed instead of at the on-ramp.
- A new car, the Courier: an armoured gunmetal wedge with green neon and a minigun turret on the roof that the driver
  fires. Everyone drives one on the Overpass (your own car waits for you), and the vehicle factory can build one
  (600).
- The Overpass is held: the Static's gangers on the shoulders of the long stretch, Halcyon at the fork, the
  roadworks and the tower ramp, and both of them waiting for you together in VEX's "shortcut". Up here they hold
  fire on each other, until a stray round from one side hits the other: then they go at it until things calm
  down. Drive between them.
- The Static's war-rigs wait on the Overpass too: rusty trucks with a spiked ram and a ganger with a shotgun on
  the back, built to ram you off the road (and Halcyon's interceptors, once the two sides are at it).
- Kilowatt, the Static's leader, makes an entrance on the Overpass: his war-rig roars past you with him on the back,
  and he jumps off before it hits the barrier. You'll meet him properly later.
- Halcyon's marksmen stand on the Overpass's gantries with long rifles. A thin magenta line shows where each is aiming;
  when it stops moving and flares, swerve, or the round finds you.
- Halcyon's sting drones hang over the Overpass's gantries in swarms of three, then come after you in strafing runs,
  faster than your car, guns going. One or two rounds bring one down.
- Halcyon's interceptors wait on the Overpass's shoulder: armoured grey SUVs with flashing light bars that come
  after you flat out, ram you and have an officer lean out of the window to shoot.
- Past the Market's walls Grey City is at war: a front through the city, rubble and craters in no-man's-land,
  barricades facing each other across the streets, tracer fire, shells landing, burning towers and searchlights.
  You hear it too: muffled bursts and shells beyond the walls, on their own volume slider ("the battle beyond
  the walls").
- The Market has its own heavy metal theme: it kicks in the moment you walk up out of the tunnel and the
  factions come for you.
- Halcyon's watcher drones fly over the Market's lanes. One that sees you hangs over you and calls officers in
  every few seconds until you shoot it down. The sparkers' EMPs knock them out for a while.
- Halcyon Tower is held now: Halcyon officers on every floor, a pair on each stair door up, the lobby's lifts
  guarded and a squad walking each floor (two on the security floor), so the climb is a sneak past their sight
  cones. Nobody looks your way until you are past the reception.
- Halcyon's assassin droids stalk Halcyon Tower too, cloaked: one among the server racks, two in the labs (one more
  for each extra player) and two round the boardroom on the executive floor.
- More of Halcyon's officers hold Halcyon Tower's lower floors: two behind the lobby's reception desk, and three
  more each among the office desks, the server racks and the labs' tanks.
- The Static break into Halcyon Tower behind you: a pack of gangers through the front doors, then up the
  stairwell onto the lowest floor anyone is on, about every 35 s. The two factions ignore each other in the
  tower; they only want you.
- Halcyon Tower's stair doors are locked. Hold F at the terminal beside one for 4 s to breach it quietly, or press
  E to have VEX open it at once, which also opens that floor's guard room: four officers come out after you (more
  with more players).
- Halcyon's enforcers hold Halcyon Tower's top floors: four riot shields on the security floor, two in front of the
  stair door up and two across the way to it, and two either side of Saye's desk on the executive floor.
- Halcyon's marksmen in Halcyon Tower: three in the far corners of the security floor (more with more players,
  then the executive floor), lining up their shots along the floor. Walls hide you from them, and their sightline
  stops at the first wall.
- Halcyon's watcher drones in Halcyon Tower: two down the offices' aisles and one over the lobby. They see over the
  desks but not through floors, hang over you in the aisles and call officers in until you shoot them down.
- Halcyon's sting drones swarm Halcyon Tower's server room: two swarms of three (one more swarm for each extra
  player) making strafing runs down the aisles between the racks, slower and tighter than on the Overpass.
- Sentry turrets in Halcyon Tower: three in the labs and four round the security floor. Each sweeps its arc, puts a
  laser on you for a moment, then fires bursts. Get behind one and hold F for 2.5 s to breach it: it fights for
  you for 15 s, shooting Halcyon and the Static. The sparkers' EMPs knock them out for 5 s.
- The Static's brutes: huge, slow, 150 health and a giant chrome arm. One braces with a cyan line on the floor, then
  charges down it, and punches up close. Get next to one and hold F for 1.5 s to breach his arm: for 4 s he spins,
  swinging at everyone near him, his own side included.
- The Static's break-ins into Halcyon Tower bring sparkers from the offices up and brutes from the server room up.
- Kilowatt waits for you on the Roof: the Static's boss, huge, with a reactor for a heart. He charges down a line
  he marks on the floor, hops and slams a ring of shock out round him, whips lightning through you and whoever is
  next to you, and punches up close. Every few moves he vents, cage open and steaming: hits count double then. At
  half health he gets faster and meaner. The Roof isn't done until he is down.
- Director Saye joins Kilowatt on the Roof: Halcyon's boss fights at range. A thin magenta line marks her pistol
  shot for a second before one heavy round goes down it (step off the line), three executive drones orbit her and
  shoot (shot down, she calls more), and she drops sentry turrets and walks away from them. At half health her skin
  cracks: the line comes faster and she fires two at once in a V. The Roof isn't done until both bosses are down,
  and their two bars sit one over the other.
- Saye and Kilowatt fight as partners. Shoot Saye and Kilowatt comes for you; stand next to him and her line comes
  for you, quicker. When he vents she parks her drones round him: shoot them down before his hits count double.
  When one falls the other rages: Saye alone calls six drones and fires three shots down each line ("Hostile
  takeover."); Kilowatt alone stays in phase 2 and his slams leave crackling shock patches ("MELTDOWN!"). And
  they bicker about forty years of business while they're at it.
- While Kilowatt fights, the Static's brutes come up the stairs at the Roof's south edge to help him: one every
  25 s, two at a time at most (one more for each extra player), and no more once he's down.
- VEX takes the Roof once Saye and Kilowatt are down: she locks the stairs, her face comes up huge over the whole
  roof, and four turrets wake up (one more for each extra player). Breach her four relays (hold F for 5 s at each):
  she sits at one at a time, where breaching is half as fast and a ring of shock pulses out every few seconds, and
  she moves to whichever you're furthest into. Her face breaks up more with every relay lost. On the last one she
  gets away into the net, "Nothing personal, courier.", and the job is done.
- The Roof has its own music: a metal finale with a choir and a tolling bell while Saye and Kilowatt fight, each
  getting their own half (his chugging, hers cold strings and a ticking clock) before it brings them together; and
  VEX's own glitchy chiptune theme the moment she takes the roof, which cuts out when she gets away.
- General Volt holds Noodle Square in the Market: the Static's general, all coils and cable. He shows you a
  crackling line before each lightning bolt strikes down it, lobs lightning grenades that leave shock fields on
  the ground, and calls in a pack of the Static each time you knock another quarter off him. He has the loading
  dock's pass code: the dock stays locked until he's down and somebody picks the code up.
- It starts to rain the moment you step into Noodle Square, and a storm breaks over Volt's fight: flashes in the
  sky, thunder, and lightning striking round you (watch for the flickering ring on the ground). The lightning stops
  when he goes down; the rain keeps on until you leave the Market. Rain and thunder have their own volume slider.
- The electric grenade: General Volt's own, and the first thing you unlock. When he goes down he drops a stack of
  three that every player can pick up their own of, with a "NEW GRENADE UNLOCKED" screen to go with it. Drag them
  onto your grenade slot and G throws them like any grenade (the grenades in there go back into your bag): a shock
  blast that stuns whoever it catches and holds enemies still for a moment, then a field that keeps zapping anyone
  who stays in it for 4 s. From then on the shop sells them to you (60 Fcks, on the Ammo shelf) and enemies drop
  them now and then, and the unlock is saved with you.
- The Roof stands over Grey City: the city far below on every side, other skyscrapers' tops round it, their red
  lights blinking.
- The Static's brutes look like themselves now, not like small Kilowatts: rust-orange work jackets, welding masks
  with a cyan visor slit and that giant arm, and a head shorter than Kilowatt, so the help that comes up the Roof's
  stairs isn't mistaken for more of him.
- Halcyon Tower is furnished: marble and Halcyon's logo in the lobby with sofas and holo screens, office chairs and
  a glass meeting room, cooling units and cables among the server racks, lab benches, lockers on the guard floor,
  and a lounge, a bar and Saye's glass office at the top. Each floor has its own floor, and Grey City lies far
  below through the glass walls.
- Halcyon Tower has its own metal theme, heavier and slower than the Market's: it kicks in the moment you walk past
  the reception, cutting off the lobby's lift music.

### Fixed
- The blue low-stamina glow no longer flashes: it fades in gently from 30% stamina instead of popping on, and
  breathes more slowly and softly.

## [0.26.15] - 2026-10-09

The FPS counter is back top left and coloured by how smooth it runs; the ping sits in the top middle.

### Changed
- The FPS counter is back in the top-left corner, a size bigger and green, amber or red by how smooth it is; the
  ping moves to the top middle.

## [0.26.14] - 2026-10-09

On fire, bleeding, poisoned and the rest now show in big letters in the middle of the screen.

### Changed
- On fire, bleeding, poisoned, electrified, stunned or knocked down now shows in big letters in the middle of the
  screen, in the status's colour, with what gets rid of it underneath (it was a small line top left).

## [0.26.13] - 2026-10-09

Antlions find their way round bunkers, rocks and walls to get at you.

### Fixed
- Antlions no longer get stuck behind bunkers, rocks and walls: they find their way round to you, and only leap
  when nothing is in the way.

## [0.26.12] - 2026-10-09

Bots that fight back stop and shoot like the police, and bots and the police back off from each other when hit.

### Changed
- Bots that fight back go after you the way the police do: they chase you by the streets, stop side-on to shoot
  once they have you in sight and near, and back off a moment when you hit them (they used to circle you).
- Bots and the police fight each other the same way, backing off when hit; a police car that is shot while it
  is after nobody turns on whoever shot it.

## [0.26.11] - 2026-10-09

Bots running from you take to the streets and slide round the corners on the handbrake.

### Changed
- Bots running from you keep to the streets: they turn away from you at every crossing, turn round when you are
  ahead of them, and slide round the corners on the handbrake. Reckless drivers use the handbrake on sharp corners
  too.

## [0.26.10] - 2026-10-09

A big R: RELOAD in the middle of the screen when your magazine runs low.

### Added
- R: RELOAD flashes in big letters in the middle of the screen when the magazine is nearly out and there is ammo
  to load, as it does over the gun.

## [0.26.9] - 2026-10-09

The Citadel fights back harder: bunkers sending out squads, more soldiers and rollermines. Enemies' cones of sight
are hidden now, all but the Hunters', who sweep a radar and see wider.

### Added
- The Citadel has a Combine bunker on the pens, the processing floor, the gallery and the reactor deck: get near
  and squads of 3 come out of its door, 6 soldiers from each.

### Changed
- More Combine in the Citadel: soldiers on guard 36 -> 48, rollermines waiting on the catwalks 6 -> 17 (for one
  player; more with more).
- Enemies' cones of sight start hidden (` shows them); only the Hunters' always show, now as a radar: range rings,
  a beam sweeping across.
- Hunters see wider: 60 -> 90 degrees, 100 -> 130 while on edge.
- D-Day's soldiers and the police now notice you close by whichever way they face (150 px all round), as the
  Combine, the Hunters and the Suppressors already did.

## [0.26.8] - 2026-10-09

The Citadel comes alive: computers along its platforms and repair drones flying round fixing things.

### Changed
- The Citadel is busier: banks of computers line the platforms' rails, cabled to terminals with live screens, and
  repair drones fly round welding the machines, the struts and the pillars down in the drop.

## [0.26.7] - 2026-10-09

A big RELOADING across the middle of the screen while a gun reloads.

### Added
- RELOADING shows in big letters in the middle of the screen while a gun reloads, with a bar filling as it goes.

## [0.26.6] - 2026-10-09

The bag beside the shop lists your guns and abilities too, grenades are on the Ammo shelf, and clicking one
no longer crashes the game.

### Added
- The bag beside the shop also lists the guns and abilities you carry, a row each at the bottom (the gun in
  hand lit, an ability ready or cooling down), taller on a bigger window. It shows only the slots you have, as
  big as fit, and hovering a small one names it.

### Changed
- Grenades are on the shop's Ammo shelf now, not Supplies.

### Fixed
- Clicking the grenade in the shop crashed the game since it moved to the Ammo shelf; it shows what it does again.

## [0.26.5] - 2026-10-09

Sell things back to the shop from your bag, for half what it asks.

### Added
- Sell things back to the shop: click something in your bag beside the shop and sell a bundle or all of it
  for half of what the shop asks (60 uzi rounds: 20 Fcks). It only buys what it sells itself, not materials.

## [0.26.4] - 2026-10-09

Armor and clothes can be bought and put straight on in the shop.

### Added
- Armor and clothes in the shop have a Buy & wear button beside Buy: it puts the piece straight on, and
  whatever you had on in that slot goes into your bag. If your bag has no room for it, nothing is bought.

## [0.26.3] - 2026-10-09

The shop shows your bag beside it, and medkits, drinks and grenades you buy go straight into their quick slot.

### Added
- The shop shows your bag beside it: every slot with what is in it and how many, and your medkits, drinks
  and grenades, so you can see what fits before you buy. On a narrow window it is left out.

### Changed
- Medkits, energy drinks and grenades you buy go straight into their quick slot, ready on their key, until
  it is full (5); only the rest go into your bag. A full bag no longer stops you buying one while the slot has room.

## [0.26.2] - 2026-10-08

Ammo stacks to about ten magazines a slot, and freeze is aimed with the key and cast with a click.

### Changed
- Ammo stacks much higher in your inventory, about ten magazines a slot: uzi and AK-47 100 -> 300 rounds,
  minigun 300 -> 1500, shotgun 50 -> 60, sniper 50 -> 60, rockets 20 -> 30, fuel cans 10 -> 20.
- Freeze is cast like the leap now: press its key to show the area, click to cast it there (the key again or
  right-click to put it away). It used to be hold the key and let go.

## [0.26.1] - 2026-10-08

Walking, sprinting and dodging answer the keys at once on a laggy connection too, like the car.

### Changed
- On foot, walking, sprinting and dodging now answer the keys at once on a laggy connection too: you no
  longer stick for a moment when you set off or slide on after you stop (at 150 ms each way you used to
  drift on about 8 px after letting go; now none).

## [0.26.0] - 2026-10-08

Your car answers the keys at once however far away the server is, the connection is lighter and steadier,
and everyone has to be on the same version to play together.

### Added
- Firing an empty gun, or reloading with no ammo left for it, now flashes NO AMMO in big red letters in the
  middle of the screen.
- Running low on stamina on foot (under 30%) now shows too: a blue glow breathes in from the edges of the
  screen, stronger the less is left and strongest while you are winded, and the stamina bar flashes.

### Changed
- Your car answers the keys at once, however far away the server is: your game drives it ahead and the
  server corrects it, instead of waiting for the server to say where it went. At 150 ms each way it answers
  the throttle in about 40 ms instead of 460, and the rubber-band pull is gone. Bumping another car still
  settles a moment later.
- The ping on screen is right within a few seconds of joining: it used to start near 500 ms and take
  20 seconds or more to come down, so it read 100+ ms even on a fast connection.
- Your inputs and the server's updates go out the moment they are ready instead of waiting for the next
  frame: up to a frame (about 16 ms) less delay each way.
- The server now sends about half as much (30 -> 16 kB/s per player): its big updates are compressed, so over
  Tailscale they fit in one packet instead of being split in two, where losing either half lost the update.
- Everyone in a game must have the same version now. Joining a server on another version tells you both
  versions instead of going wrong mid-game.
- The FPS counter moved from the top left to the top middle of the screen.

## [0.25.0] - 2026-10-08

Police cars stop to shoot and chase you round buildings instead of into them, most traffic runs instead
of fighting back, soldiers go easy on the grenades, and the keys move about: abilities on 1-3, R to reload.

### Added
- Your ping to the server now shows in big numbers at the top left while driving: green, yellow over 80 ms, red over 150 ms.
- Hire a Handsy Man at the shop (Hire shelf, 30 Fcks): he drives his pickup to each of your damaged buildings,
  ruins too, and repairs them with your Fcks, then goes back to the shop and leaves once everything is fixed
  or you run out of money. He charges 3x what the repair menu does, and 6x to rebuild a ruin. He is only for hire while something of yours needs fixing,
  and his pickup can be shot up and wrecked.

### Changed
- New default keys: G readies a grenade (was T), P opens your vehicles (was G), R reloads (was X), your
  abilities are on 1, 2 and 3 (were Q, E and R), and Z and X step back and forward through your guns (the
  number keys used to pick one; the mouse wheel still works). Keys you have rebound in Settings stay as set.
- Combine soldiers in City 17 throw far fewer grenades: 1 in 4 -> 1 in 10 carry them, 2 -> 1 each, at most
  one every 8 -> 20 seconds, and they wait longer before deciding to throw.
- D-Day soldiers throw far fewer grenades: 1 in 4 -> 1 in 10 carry them, 2 -> 1 each, at most one every
  8 -> 20 seconds, and they wait longer before deciding to throw.
- Police cars drive smarter: once they are close and can see you they stop and shoot (sliding round on the
  handbrake if they come in fast), they chase you around buildings by the streets instead of into walls, and
  they handbrake round sharp corners. Shoot back and they back off for a moment, then stop and shoot again.
  They crash far less: about 125 -> 8 hits on walls and cars per patrol car in five minutes of chasing.
- Most traffic no longer fights back: shoot or ram a civilian car and only 1 in 10 drivers comes after you
  (was every one); the rest floor it and get away from you. Police are unchanged.
- Fewer pedestrians on the streets, about 20% less: 26 -> 21 per car, at most 90 -> 72.
- Hunters no longer double with every extra player: each player past the first adds one more instead.
  The Hunter-Chopper's Hunters with two players 6 -> 4, A-Man's briefcase Hunters 4 -> 3, the Winding Road
  and Citadel beats the same (one player is unchanged).

### Fixed
- Police no longer shoot each other: officers on foot kept wrecking their own patrol cars, and patrol cars
  could hit each other and the officers. Their rounds now fly through the force.

## [0.24.0] - 2026-10-08

The Poison Zombie and his headcrabs now hurt as badly as the Antlion Guard.

### Changed
- The Poison Zombie on the Winding Road hits far harder: his claws 20 -> 60, a headcrab's bite 15 -> 35
  (and you are still poisoned after), a headcrab landing on a car 6 -> 15. He is as slow and as easy to
  hurt as before.

## [0.23.0] - 2026-10-08

The Antlion Guard is still slow, but now every blow it lands is a big one.

### Changed
- The Antlion Guard on the Coast hits far harder: swipe 22 -> 60, charge 35 -> 90, scream 30 -> 70 (right
  in front of it). Still as slow and as easy to hurt: dodge it or pay.

## [0.22.0] - 2026-10-08

Ammo drops for the guns you actually carry, AK rounds far more often, and
no more free rocket launcher at the start.

### Changed
- Enemy ammo drops favour the guns you carry: half of all ammo boxes are now for a gun in one of your
  weapon slots. The rest lean towards common guns: AK and uzi rounds turn up 6 times as often as rockets
  or minigun belts (was all the same). Carrying an AK, you find its rounds about 1 kill in 5 (was 1 in 23).
- New players no longer start with a rocket launcher and 5 rockets: buy one at the shop. Players who have
  one in a saved world keep it.

## [0.21.0] - 2026-10-08

The minigun gets its weight: you lug it at half pace while it turns.

### Changed
- The minigun is heavy: you move at half your pace, walking or sprinting, while its barrels turn (winding
  up and firing).

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
