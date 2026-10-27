# Borderline design

A quest line in the shape of Cyber Feud's and Eternal Mood's
(`docs/cyber-feud.md`, `docs/eternal-mood.md`): a job on the board, eight
maps chained by each quest's `next`, a banner and tagline on each map, an
intro screen, story beats said over the HUD, robots' barks, bosses, and a
last word. The look is a cel-shaded loot-shooter on a frozen junk planet,
played the way A-Man plays Half-Life: a parody with its own names, not the
real ones. Every map is on foot; nobody drives.

The source is the robot half of a famous looter-shooter's second game: a
smug corporation, its CEO's face on every screen, and an army of yellow
loader robots, each model stencilled with a three-letter code that says
what it does (GUN, RPG, EXP, ...), built by giant factory robots and guarded
by a flying bunker. We keep the shape and the jokes, and our own names.

Status: designed; stage 1 (the skeleton) built on `feature/borderline`:
the eight maps blocked out in `city-map/borderline.lua` (floors, walls,
cover, the way in and the way on, drawn by `render_borderline.lua` in the
outlined look), their eight quests chained by `next` with "Left for dead"
on the board, a HOME star by each way in, and the `borderline` feature
finishing each level when someone reaches its way on. Stage 3 started:
the robots' looks (`hauler_look.lua`, `drone_look.lua`, every model), and
the junk and gun haulers' brains (`junk_brain.lua`, `gun_brain.lua` on the
shared body `chassis.lua`, put on the map by `army.lua`) with the torso
crawl, on the Frozen Wreck (a junk pack by each carriage, a bigger one at
the engine) and Liar's Landing (gun haulers posted where the container
lanes cross and on the quay, two squads walking the lanes, two junk
packs). Stage 4 and 5 done: rocket haulers (`rpg_brain.lua`, pod volleys
through `barrage.lua`) on Liar's Landing and in Prosperity, jet haulers
(`jet_brain.lua`, strafing runs through `barrage.lua`) in Prosperity,
the `plasma` damage type (the damage feature's "melt" status, the armor
feature spending two points a point while melted) and plasma haulers
(`plz_brain.lua`, `bolts.lua`) in the Bragium Pit and Prosperity. What
every drilled model shares (posts, squads, keeping its distance) is
`drill.lua`. Stage 6 done: kamikaze (`exp_brain.lua`), dozer
(`dzr_brain.lua`), arc (`arc_brain.lua`, domes in `domes.lua`) and badass
(`bad_brain.lua`) haulers, the medic and shield drones (`drone_brain.lua`,
shields soaked up in `chassis.lua`) and the sentries (`sentry_brain.lua`),
on every map from Liar's Landing on: the Refinery's bridges held by arc
haulers, the Assembly Line's aisles by gun haulers with a badass and two
sentries on the Foreman's floor, Thousand Papercuts' road by rocket and
jet haulers with a sentry in every nest, and the Bunker's rim by eleven
sentries on the cannon mounts. Stage 2 (the story) done too: the words
in `story.lua`, Max's and Yappy's portraits in `faces.lua`, the HUD in
`hud.lua` (Max's intro screen, drawn in `drawScreen`; the map and zone
banners; the comms; the objective line), played by `tale.lua` (the host
raises each level's beats once: start, a zone walked into, the first
fight, the end; and the chatter: Max's taunts, a bigger one promised
for every big kill, both of them on a player going down, Yappy cheering now and then).
A gold chevron bounces over what the objective line is after (`marker.lua`):
every terminal still to hack, then the way on until the level is done,
with a ring pinging round it on the minimap and the big map. The minimap
shows each map's layout: its floor in the map's colour
(`Borderline.MAP_FLOOR`) and the big things on it in theirs
(`Borderline.MAP_COLORS`: sheds, the train, pits, containers, factories,
the river), and its areas (`map.zones`): a dashed line between each, its
name, the one you're in tinted gold. Yappy is a voice so far, not on the map. Liar's Landing's ferry lift is held while Yappy hacks it
(`hold.lua`, below). Two bosses are in: the Knuckle Scrapper on the Frozen
Wreck (`scrapper.lua`, `knk_brain.lua`) and Wilbur on the Bragium Pit
(`wilbur.lua`, `wlb_brain.lua`, "The bosses"). Every map has its theme
music. See "Stages" at the end for the order.

## Decisions

| Question | Decision |
| --- | --- |
| How long? | **Eight maps**, all on foot. |
| Enemies? | **Robots only.** One corporation's army, so no feud: every robot is on the same side. |
| Rockets and plasma? | **Both.** Rocket robots use the rockets we have (`weapons/rockets.lua`, `explosive`). Plasma is new: a new damage type, `plasma` (see "Plasma"). |
| Parody or its own thing? | **Parody with our own names**, like Eternal Mood. |
| Story? | **Simple.** A villain on the screens, a sidekick in your ear, one goal: shut the robot army down. |

## Logline

Maximum Maximilian Max, CEO of Hyperbole, is mining the planet Pandoria hollow for
Bragium, the purple rock that powers his robot army. You came for the loot;
he left you for dead in the snow. A small, loud, one-wheeled robot digs you
out, and the two of you walk all the way to his bunker to pull the plug.

## The cast

- **Maximum Maximilian Max**, CEO of Hyperbole. The villain, and he never
  shows up in person: he is on every screen, billboard and PA, talking to
  you the whole way. He does everything to the max, and his catchphrase is
  "TO THE MAX!". His friends call him MMM. A tall blond
  flat-top, a sweatband, shades, a lantern jaw, a yellow muscle shirt
  and a gold chain, one arm always flexed. Colour: Hyperbole yellow `#f2c230`.
  He fills VEX's role: the intro screen portrait, the chatter, the last
  word. Calls you "bandit".
- **YAP-TP ("Yappy")**, the sidekick. Max's secretary, an ordinary
  woman; YAP-TP is her Hyperbole staff code, because Max never learned
  anyone's name. He put her on the train too, so she is as left for dead as
  you. She dug you out, she has decided you are her minion, and she will
  not stop talking. She knows his codes and his passwords, opens doors
  (slowly), hides when shooting starts, and takes credit afterwards. She is
  a character on the map, not only a voice: she walks ahead of you, stops at
  doors, and can't be killed (shots knock her over; she gets up complaining).
- **The Bragium**: purple crystal, glowing. The ore on the early maps, the
  molten river in the refinery, the fuel in every plasma gun.
- **The robots** (see "The army").

### Maximum Maximilian Max

**Portrait** (64x72, primitives on a canvas scaled up with nearest
filtering, like `cyber-feud/face.lua`): head and shoulders on a Hyperbole
broadcast card (yellow border, a logo in the corner, a LIVE dot).

- Hair: a blond flat-top, square and so tall it runs off the top of the
  card, a red sweatband across the brow.
- Face: tanned, a lantern jaw with a cleft chin, wraparound shades with a
  glint sweeping across them now and then.
- Mouth: a wide white grin.
- Clothes: a yellow muscle shirt cut low, a gold chain with an M medallion.
- Pose: his left arm up beside his head, flexed, a sweatband on the wrist.
- Animation: talking, the grin opens to a shout, his brows bounce and he
  pumps the arm. Now and then he leans into the camera so his face fills
  the frame.

**Voice.** Loud, generous, unstoppable. He never complains: whatever you
break, he builds a bigger one, and every setback is a reason to go further.
Everything he owns is the biggest, the deepest, the hottest, and he wanted
it bigger still. Short lines, a joke in most of them, "TO THE MAX!" in a
few. His friends call him MMM; nobody is sure he has friends.

| Category | When | Examples |
| --- | --- | --- |
| `hello` | A map starts | "You're still alive! Fantastic! Guards? Maximum guards!" / "Welcome to Prosperity! Maximum prosperity. Mostly for me." |
| `taunt` | Now and then | "I don't do anything halfway. I don't even know where halfway is." / "My friends call me MMM. You can call me Maximum." |
| `down` | A player goes down | "Down! Did you see that? Maximum replay." / "Get up, bandit! You're not done. I'm not done. Nobody's done!" |
| `kill` | A big robot falls | "A prototype! Love it. The next one's bigger." / "I'll build ten more. No: a hundred. TO THE MAX!" |
| `yappy` | Yappy says something | "YAP-TP! Still alive? Great hustle! You're fired. Maximum fired." |

### YAP-TP

**Portrait** (64x72): a young woman on a comms headset, auburn hair with a
side-swept fringe and a swinging ponytail, blue eyes, a blue parka zipped
up to its fur collar. She blinks; while she talks her brows go up, her
mouth moves and the mic's light comes on.

**Voice.** Loud, eager, cowardly, sure she is in charge. Calls you "minion".

| Category | When | Examples |
| --- | --- | --- |
| `go` | A map starts | "Onward, minion! I'll be right behind you. Way behind." |
| `door` | Opening a door | "Opening! Opening... Hold on, I have a lot of tabs open." |
| `hide` | Shooting starts | "I am bravely hiding!" / "Tactical retreat! Tactical retreat!" |
| `win` | A wave cleared | "We did it! By we I mean me." |
| `hit` | Knocked over | "Ow! My everything!" / "I'm fine! I'm fine. Is my hair okay?" |

**Intro screen lines** (one per map, Max's portrait, picked by index like
`cyber-feud/screen.lua`):

1. The Frozen Wreck: "That train hit the snow at maximum speed. Biggest crash on record. TO THE MAX!"
2. Liar's Landing: "The biggest docks on Pandoria. Maximum cranes. Maximum guns. Enjoy!"
3. The Bragium Pit: "The deepest hole on the planet. I dug it to the max. Mind the glowing rock."
4. Prosperity: "My city! The biggest statue, the biggest screens, the biggest me. TO THE MAX!"
5. The Refinery: "The hottest river in the galaxy. I turned it up. Then I turned it up again."
6. The Assembly Line: "A robot every four seconds. I asked for two. Every one has your name on it."
7. Thousand Papercuts: "One road, a thousand guns. I wanted a million. We're getting there."
8. The Bunker: "You found my bunker! It flies. Of course it flies. TO THE MAX!"

## The army

Every robot is Hyperbole yellow (`#f2c230`) over gunmetal (`#3a3f47`),
with a red eye (`#ff3030`), a black-and-yellow hazard stripe and its code
stencilled on its chest. Drawn top down with their own look module each
(like `eternal-mood/mancubus_look.lua`), one brain module each (the
brains standard), and every one answers `serverEnemies` so the audit can aim
at it. Numbers are starting points; for scale, a Combine soldier has 60
health and drops 3 koins, Eternal Mood's possessed staffer 40.

**Haulers** are the loader robots: tall, thin, two legs, two arms, a round
red eye on the top. They all share one trick, the **torso crawl**: when a
hauler with legs takes a killing hit, one time in three its legs give out
and its top half drags itself on for 4 s, still shooting, before it dies
(half its health back, at half the speed). Shoot it again to finish it.

| Unit | Code | Look | Health | Attack | Behaviour |
| --- | --- | --- | --- | --- | --- |
| **Junk hauler** | `JNK` | Patched, missing panels, mismatched rust-red arm | 30 | Pistol (`bullet`, 6) | Weak and many. Packs of 4-6 that walk at you shooting. Fodder; first map. |
| **Gun hauler** | `GUN` | The standard: rifle arm, grenade arm | 70 | Rifle bursts (`bullet`, 8) and now and then a grenade (`grenades:serverLob`): it marks the landing spot with a red ring (`barrage.lua`'s `serverMark`) and stands turned to it 0.6 s before it lobs, the ring staying until the grenade lands | Posts and squads, like the Combine: takes cover, keeps 250-450 px off, flanks in pairs. |
| **Rocket hauler** | `RPG` | Heavier, two rocket pods on its back, a launcher arm | 120 | A rocket from the arm (`explosive`, 30, 90 px), or a volley of four from the pods | Hangs back (400-650 px). Before a volley, four red rings mark the ground where the rockets will land (1 s), then they rain in. Kill it first. Pods count as part of it. |
| **Plasma hauler** | `PLZ` | Purple glowing coils on a cannon arm, a Bragium tank on its back | 90 | Plasma bolt (`plasma`, 22): slow (260 px/s), glowing, big, splashes 40 px | Mid range. Charges for 0.5 s (coil glows brighter), fires one bolt. Bolts are slow enough to sidestep. Shoot the tank on its back (from behind) and it bursts: a plasma splash that hurts robots too. |
| **Kamikaze hauler** | `EXP` | Stripped, a red blinking core in its chest | 40 | Self-destruct (`explosive`, 45, 120 px) | Sprints at the nearest player beeping faster and faster; at 60 px it goes off. Kill it early and it still blows: keep it away from you, near its friends. |
| **Dozer hauler** | `DZR` | Wide, a bulldozer blade on one arm | 160 | Blade shove (`impact`), a dozer charge | The blade stops everything from the front (70 degrees, like the Enforcer's shield); flank it or blow it up. Every 6-8 s it folds into a dozer and charges in a straight line (`impact`, 30, knocked down). |
| **Arc hauler** | `ARC` | Blue coils on both arms, a dish on its back | 80 | Shock bolts (`shock`, 10, `electrify`) | Throws up a dome shield (180 px) over itself and anything near it for 5 s, every 12 s. Rounds from outside stop at the dome; walk inside and you are zapped every second (`shock`, 8) but your rounds hit. |
| **Jet hauler** | `JET` | Wings folded on its back, thrusters | 70 | In the air: a strafing run of rockets in a line (`explosive`, 20 each); on the ground: a rifle | Flies over walls (drawn over everything, a shadow on the ground), makes a run along a line through you (red marks along the line 0.8 s before), lands somewhere, fights on foot, takes off again. Only shootable on the ground or while landing. |
| **Stalker hauler** | `STK` | Tall on two long legs forward and a wheel on a strut behind, a dark visor with one red eye slit, a flechette pod on each shoulder | 140 | Bursts of six flechettes (`darts.lua`): each stings as it sticks in you (3), in a wall or in the ground where it stops, blinks inside a red ring and blows a second later (`explosive`, 10, 40 px) | Hyperbole's hunter. Hunts the stacks in a pair and keeps its distance (260-480 px) quicker than the drilled models. Once it knows somebody is about (hunting or searching), it throws itself aside from rounds and abilities coming at it and turns on whoever fired; before that a shot from hiding lands. Dodging spends breath (`bosses/stamina.lua`, about a quarter a dodge): four or five in a row and it is winded for ~5 s, walking, no dodge or charge (its breath shows under its health, throbbing red while winded). Every 6-9 s it crouches (0.5 s, its pods and eye glow) and charges where you stood (`impact`, 20, knocked down), then backs off. Badly hurt, it backs to a medkit lying near, still shooting (`bosses/heal.lua`). `stk_brain.lua`; from Liar's Landing on. |
| **Medic drone** | `FIX` | A yellow flying disc with a green cross light, about a hauler's size (14 px round, so it can be hit) | 25 | None | Flies in pairs, hangs behind the haulers and heals the most hurt one (12 a second, a green beam). Fragile; shoot it first. |
| **Shield drone** | `SHD` | The same disc, blue light | 25 | None | Gives one hauler a shield bubble (80 points) and keeps it topped up while the beam holds. |
| **Sentry** | | A yellow pop-up turret | 90 | Bursts (`bullet`) | Sits flush in the floor until you are near, then rises. Creatures rule: no brain module. |
| **Hauler dock** | `DCK` | A gunmetal pad with a hazard rim, a charging cradle open to the south (clamp arms, a cable glowing purple), a plasma gun on a turret at the back | 300 | Plasma bursts of three (`plasma`, 14 each, 32 px splash, 300 px/s) | Guards a terminal; never moves, turns all the way round. With anyone within 900 px it builds a junk hauler every 20 s and sends it out of the cradle (up to 3 of its own out). Shoot it down, or hack the terminal it runs and it shuts off (`dock_brain.lua`, `dock_look.lua`). |
| **Badass hauler** | `BAD` | 1.6x size, black and yellow, twin war cannons, rocket pods, a horned head | 450 | Cannon bursts (`explosive`, small blasts), pod volleys, a stomp (`impact`) | Elite. One or two per map from map 4 on. |

### How they look

Drawn (`borderline/hauler_look.lua`, `borderline/drone_look.lua`; the
sheet is `docs/borderline-robots.png`) top down at world size in the
outlined style of the maps: black outlines, flat colours.

- **Haulers** are one body with a kit per model (`Look.KITS`, by code): two
  thin legs with backward knees and pad feet stepping out wide of the
  hull, a squat yellow hull with a hazard stripe across its back and a
  strip of the model's trim colour up front, and the head: a gunmetal ring
  round a big red eye that brightens as it winds up or is hit. Size
  1x a hauler is 13 px across the middle (a player is 9); RPG 1.1, PLZ
  1.05, DZR 1.15, EXP 0.95, BAD 1.6.
- **Kits:** JNK a rust patch, a missing panel with wires showing, a stub
  arm and a pistol on a rust-red arm; GUN a long rifle and a fat grenade
  launcher; RPG a wide launcher with a red warhead and two pods of four
  rockets on its back (they glow orange as it winds up); PLZ a cannon with
  three purple coils that glow and a purple bloom at the muzzle, and a
  Bragium tank on its back; EXP no panels and no arms, a red core that
  blinks faster the closer it is to going off; DZR wider, a curved blade
  across its front; ARC blue coils on both arms and a dish on its back;
  JET wings folded along its back and twin thrusters, wings swept out and
  a flame when it flies (drawn bigger, its shadow further off); BAD dark
  grey and yellow, horns either side of its eye, twin war cannons, pods.
- **Torso crawl:** no legs, scrape marks behind it, sparks off its hips.
- **Wrecks:** fallen on their side, eye dark, oil under them, a spark now
  and then.
- **Drones:** a yellow disc on four blurred rotors, a green cross (FIX) or
  blue dot (SHD) in the middle, a red eye at the front, a wavering beam to
  the hauler it tends. The shield is a blue bubble with a hexagon in it,
  flickering as it weakens.
- **Sentry:** a hatch with a hazard rim flush in the floor; risen, a
  yellow turret with twin barrels and a red eye between them.

### The bosses

Every boss uses the bosses standard (`src/features/bosses`: stamina, the
shared bar, goes for medkits when hurt), has its own brain and look, drops
koins and a pickup, and raises `serverKill` with kind "boss".

| Map | Boss | What it is | The fight |
| --- | --- | --- | --- |
| 1 | **Knuckle Scrapper** (`KNK`, built) | A junk hauler that built itself huge out of the train wreck: a heap of rusted scrap with a carriage panel on its back, the engine's headlight for an eye, the smokestack puffing, two girder arms with bogies for fists | The tutorial boss. 1500 health for one player (`Bosses.health`). Builds itself out of the engine (2.6 s of scrap dragging together) onto the rails in front of the tunnel the moment the yard's three terminals are hacked (the `power` lock); the tunnel's blast door (the `tunnel` lock, no terminals) opens only when it falls apart. Lumbers at you at 60 px/s. Close up its fist goes back (0.75 s, its eye goes red) and swings round in front of it (150 px, 25 `impact`, thrown 260 px). Further off, every 4-6 s it lifts a lump of itself (0.9 s) and lobs it onto a red ring (30 `impact` within 75 px, thrown). Every 9 s two junk haulers climb out of the carriages nearest the engine and make straight for it carrying scrap (a dashed line from each to it), five out at most: one that reaches it is pulled in and heals it 90, so shoot them first. Its plates come off as its health goes. Boss standard: breath (walking after you, the throw; winded it shuffles, no throws), medkits, walks out from under abilities, the boss bar. `knk_brain.lua` (it is one of the army's), `scrapper.lua` (the build, the feeders, the tunnel, the bar), `scrapper_look.lua`. |
| 3 | **Wilbur** (`WLB`, built) | Max's cyborg enforcer, more machine than man: a broad slab in Hyperbole plate, a rotary gun for a right arm, a steel fist for a left, a rocket pod on his shoulder, half his head steel with a red eye | 3000 health for one player (`Bosses.health`). Drops onto the pad (a red ring for 1.6 s; landing throws everyone within 130 px flat, 30 `impact`) when somebody first sets foot on the pit's floor (gated until the four power terminals are hacked); the mine lift stays shut until the keycard he drops where he falls is picked up. He also leaves a plasma rifle for every player (`weapons/guns.lua`, `unlock`: picking it up puts it on the shop's shelf). Keeps ~300 px off, circling, firing his rotary gun in bursts of ten (`bullet`, 9 each). Every 8-11 s his pod glows (0.8 s) and five rockets come down on red rings round you (`explosive`, 30). At anyone 260 px or more off he leaps: a red ring where he'll land, 0.8 s in the air out of reach, a slam (40 `impact`, 110 px, thrown flat), slow to get up. Every 15 s a drone out of his back, shield and medic by turns, 2 of his own at most: they heal and shield him, so shoot them first. At half health Max pushes an upgrade: his plates glow, he moves quicker, fires sooner, rockets every 5-7 s, drones twice as often (3 at most). Boss standard: breath (running, rockets and leaps; winded he walks, no leap or rockets), medkits, walks out from under abilities, the boss bar. `wlb_brain.lua` (he is one of the army's, so the drones tend him), `wilbur.lua` (the drop, the lock, the bar, the keycard), `wilbur_look.lua`. |
| 5 | **Smelter** | A squat plasma furnace on four legs, molten Bragium in its belly | All plasma: bolt fans, a plasma mortar that leaves puddles burning for 5 s, and a gush that floods a lane. Vents every few attacks: its belly glows, hits there do double. Fights by the river: the puddles and the river are the danger. |
| 6 | **Foreman BIG-B055** | The badass hauler that runs the line: 2.2x, gold trim, a hard hat welded on | Every badass move, plus it calls the line: the conveyors start up and carry haulers in. Phase 2 (half health): it rips one cannon off and charges. |
| 8 | **BNK-9, the Bunker** | The bunker, which flies. A slab of armour with four engines, a huge red eye, turrets round its rim | See "The Bunker". |

Maps 2, 4 and 7 end on a set piece, not a boss (see each map).

## Plasma

Plasma is a new damage type (`plasma`, in `Damage.types` in
`src/features/damage/init.lua`), purple (`#b44cff`), the colour of the
Bragium that powers it. Kill feed verb: "melted".

- **Shots** are big, glowing, slow bolts with a trail, so you see them coming
  and can sidestep. They splash a small area where they land.
- **Effect** on a player on foot: **melted**: for 3 s your armor's
  resistances count for half and its points drain twice as fast. The
  answer to a heavily armored player, and the reason to dodge.
- **Built:** bolts are `borderline/bolts.lua`; "melted" is the damage
  feature's `melt` status (its `serverShare` halves what gear stops) and
  the armor feature's `serverAbsorbDamage` (two points a point).
- **Puddles** (not built yet): some plasma (the Smelter's mortar, a burst Bragium tank, the
  refinery's spills) leaves a puddle that hurts while you stand in it
  (`plasma` damage over time, like the Winding Road's poison and Eternal
  Mood's lava).
- **Resists**: the insulated suit gets plasma 25% (beside shock and fire).
- **The players' plasma gun**: the reward (see "The reward").

## The arc: the long walk to the bunker

| # | Map | Play | Boss / set piece |
| --- | --- | --- | --- |
| 1 | **The Frozen Wreck** | Wake in the snow by Max's wrecked train. Yappy digs you out. Junk haulers scavenge the wreck. | Knuckle Scrapper |
| 2 | **Liar's Landing** | A frozen harbour of containers and cranes. Gun haulers, drones, the first rocket hauler. | Hack the four control terminals round the yard, then hold the ferry lift while Yappy hacks it |
| 3 | **The Bragium Pit** | An open-pit mine, purple crystals, conveyors. Plasma haulers first show up. | Hack the four power terminals to open the pit's floor, take Wilbur down, pick up his keycard for the mine lift |
| 4 | **Prosperity** | Max's shiny city: a giant statue of him, his face on every screen. Dozers, kamikazes, jets, the first badass. | Shoot down Max's four big screens; on the last he throws the gate open for a bigger show |
| 5 | **The Refinery** | Rivers of molten Bragium, catwalks, arc haulers' domes. | Lower the bridges one run at a time from each bank's control, then the Smelter |
| 6 | **The Assembly Line** | The robot factory: conveyors carry unfinished haulers that wake as you pass. | Shoot down the two Fabricators to open the Foreman's floor, then Foreman BIG-B055 |
| 7 | **Thousand Papercuts** | A narrow cliff road up to the bunker: turret nests, rocket haulers on the ledges, the army and a barrage coming up behind you. | Hold out while Yappy opens the bunker door (very slowly) |
| 8 | **The Bunker** | The bunker's roof. Eleven cannons, then it takes off. | BNK-9 |

### The story, beat by beat

1. **The Frozen Wreck.** Snow, the train wreck smoking. Max on a cracked
   screen in the wreck: "Sorry about the train." Yappy digs you out,
   declares you her minion, and says she knows the way to Max's bunker. Junk
   haulers are stripping the wreck; the Knuckle Scrapper rises out of it.
2. **Liar's Landing.** Yappy needs the ferry lift to cross the bay. She
   hacks the controls (a timed hold, waves of gun haulers and drones, the
   first rocket hauler) and the lift carries you over.
3. **The Bragium Pit.** Max's mine. You see what the Bragium is for:
   the plasma haulers glow with it. Wilbur, Max's cyborg enforcer, drops
   onto the pit's floor with his drones, and Max upgrades him halfway.
4. **Prosperity.** Max's city, where his face is everywhere. Yappy's
   idea: ruin the broadcast. Shoot the four giant screens; each one he
   turns the next one up brighter; on the last he throws the north gate
   open himself: a show this big needs a bigger stage.
5. **The Refinery.** Where the Bragium is melted down. Catwalks over the
   molten river, every bridge drawn up: Yappy hacks them down one run at
   a time from each bank's control, Max promising every one hotter than
   the last. The Smelter guards the outflow.
6. **The Assembly Line.** Where the army is built. Yappy typed up the order
   for every robot it ever built, and never got a thank you. Two Fabricators
   keep building haulers and the stairs stay shuttered while they run:
   break them both. The Foreman runs the floor.
7. **Thousand Papercuts.** The road up to the bunker. Yappy opens the door
   ("I have a lot of tabs open") while everything Max has left comes at
   you.
8. **The Bunker.** On its roof, the cannons, then the bunker lifts off.
   Bring it down and Yappy logs in on Max's computer (the password is
   "TOTHEMAX") and shuts the army down: every robot on Pandoria stops. "Did
   we win? I feel like I won." Max's last word, on the one
   screen still lit: "What a finish! The biggest loss in Hyperbole
   history. Next time, bandit: bigger. TO THE MAX!"
   HOME star on the roof.

## Maps

Eight new maps in city-map, one builder file for all of them
(`city-map/borderline.lua`, like `cyber_feud.lua` and `eternal_mood.lua`)
and their own render file (`render_borderline.lua`). Tiles are 64 px. For
scale: the Drop is 64x96, Fobos Base 56x80, the Roof 36x36.

| Map key | Title | Size (tiles) | Quest |
| --- | --- | --- | --- |
| `wreck` | The Frozen Wreck | 48x72 | `borderline` (on the board, "Left for dead") |
| `landing` | Liar's Landing | 56x64 | `borderline-landing` |
| `pit` | The Bragium Pit | 60x60 | `borderline-pit` |
| `prosperity` | Prosperity | 56x88 | `borderline-prosperity` |
| `refinery` | The Refinery | 48x80 | `borderline-refinery` |
| `assembly` | The Assembly Line | 56x72 | `borderline-assembly` |
| `cuts` | Thousand Papercuts | 28x140 | `borderline-cuts` |
| `bunker` | The Bunker | 40x40, the arena | `borderline-bunker` |

Each quest's `next` is the following one; the Bunker's star goes home.
Everyone travels north. A level's exit is shut until its boss is down or
its set piece is done; the objective line says what's left.

### Shared look

- The style: flat bright colours, hard black outlines on everything
  (robots, crates, walls), comic-book shading in flat bands. Our first
  outlined look: an outline pass in the render file.
- Two palettes. Pandoria's: snow white and blue-grey, rust, scrap, sky
  pale. Hyperbole's: clean yellow and gunmetal, hazard stripes, its logo
  (a yellow H in a hexagon) on everything it owns, Max's face on screens.
  The maps go from the first to the second as you get closer.
- Bragium purple is the only other colour: crystals, plasma, the river.
- Pun signs and posters: HYPERBOLE: WE'RE THE BEST (SOURCE: US),
  PROSPERITY: NO BANDITS, NO LOITERING, NO BANDITS, MAX LOVES YOU,
  NOW HIRING (ROBOTS ONLY), 0 DAYS WITHOUT A BANDIT INCIDENT.
- Snow falls on maps 1, 2 and 7 (the weather feature); the rest are
  indoors or under Prosperity's dome.
- Industrial grounds: the outdoor maps are Hyperbole's works, played at
  dusk under floodlights, with deep excavations, cranes working over them
  (moving: `borderline/works.lua`), emergency beacons turning, and painted
  safety lines, walkways, zebra crossings, cones and drums. Done so far on
  the Frozen Wreck, Liar's Landing, the Bragium Pit, Prosperity and the
  Refinery and the Assembly Line (indoors, dark rather than dusk),
  Thousand Papercuts and the Bunker: every map.
- Each map gets its own theme music, metal with a frontier twang, faster
  the closer you get to the bunker (`borderline/music.lua` plays a map's
  theme from when Max's screen goes: its intro once, then its loop). So
  far the Frozen Wreck's (`theme_wreck.lua`): freight-yard thrash at 168
  BPM in E minor. A train horn over wheels clacking faster and faster
  opens it once; then a galloping low-E chug over a thrash beat, a
  tremolo riff in E Phrygian dominant with anvils on the backbeat, a
  chorus of open chords under a twangy slide lead, and a half-time
  breakdown where rails clang and the wheels clack (~46 s loop). Liar's
  Landing's (`theme_landing.lua`): shanty metal in 6/8, 100 dotted
  crotchets in D minor. The ice creaking, a bell buoy and the foghorn open
  it once, then a gantry's winch and a container slammed down; then a
  rolling low-D stomp, a sailors' tune on a squeezebox over Dm, C, Bb, A,
  a chorus with the tune up an octave on a lead guitar in thirds over
  driving drums, and a half-time stretch of winches, chains and slamming
  containers with the foghorn over it (~38 s loop). The voices they share
  are `theme_kit.lua`'s.

### 1. The Frozen Wreck (`wreck`, 48x72, at dusk)

Hyperbole's freight yard in the snow, factory grounds where Max's train
came off the rails: concrete slabs under patches of snow (heaped against
the walls and everything standing, forklift tracks through it), a rail
line out of the tunnel and a siding up the middle, sheds round the sides
(pitched corrugated roofs, skylights, turbine vents, rust and snow, the
bay number painted on each, a loading door onto the yard), the factory's
roofs running on past the edge (parapets, skylights some of them lit,
pipes, vents and stacks). Played at dusk (`night` { 0.58, 0.62, 0.78 })
under floodlight towers.

- **Arrival:** the yard gate at the bottom. Yappy catches up.
- **The excavations:** three deep holes in the yard, fenced and hazard
  striped, DANGER DEEP EXCAVATION painted by each; nobody walks in, rounds
  fly over. A tower crane works over each from a corner, its jib swinging
  back and forth, a trolley running out and in with a load of girders
  swaying under it, a red light blinking at its tip (`borderline/works.lua`).
- **Emergency lights:** amber and red beacons turning on the cranes, the
  holes' corners, the gate and the tunnel, their beams sweeping the ground.
- **Safety lines:** a painted walkway up the west of the rails with arrows
  pointing out, zebra crossings over the tracks, traffic cones, oil drums.
- **The wreck:** carriages in a zig-zag up the yard, each lying its own
  way (tipped with its windows showing, a bogie torn out beside it, an end
  crumpled), the ground torn up between each and the rail bed; two still
  burning (`Borderline.BURNING`: embers in a hole in the roof, smoke, a
  glow), the locomotive smoking from its stack with its headlights on.
  Cargo spilled (crates, loot chests), junk haulers in twos and threes
  stripping it. A hollow in the snow at the arrival where Yappy dug you
  out.
- **The terminals:** three Hyperbole terminals put the tunnel's power back
  on (the `power` lock: the `terminals` feature, shared with Eternal Mood:
  hold F for 3 s, every 6 s an alarm brings the robots within 700 px).
  One in each part of the yard: by the east shed in the Freight Yard, by
  the west shed in the Wreck, between the sheds at the Engine. Each is
  guarded by a hauler dock (`DCK`) that it runs, gun haulers posted at it
  (one in the yard, two further up) and a few junk haulers; hacking it
  shuts the dock down (`Borderline.WRECK_POSTS`). The objective line points
  at the nearest one left until the power is on.
- **Knuckle Scrapper:** the power on, it builds itself out of the
  locomotive onto the rails in front of the tunnel, and junk haulers climb
  out of the three carriages nearest it to feed it
  (`Borderline.WRECK_CLIMB`). A blast door shuts the tunnel (the `tunnel`
  lock) until it is down.
- **The end:** the tunnel out at the top. EXIT: "LIAR'S LANDING".

### 2. Liar's Landing (`landing`, 56x64, at dusk)

A frozen container port: stacks of shipping containers as a maze, an icy
quay along the north edge with a freighter moored along it. Played at
dusk under floodlight towers, like the Wreck. Drawn in
`render_borderline_port.lua` (city-map):

- **The yard:** quay concrete in big slabs, each poured its own shade,
  joints and saw cuts, a crack here and there; snow in patches, the
  straddle carriers' tracks down the lanes, frozen puddles, oil stains.
- **The containers:** each stack two boxes side by side the long way,
  each its own colour (red, blue, green, orange, Hyperbole yellow, old
  grey), some two high (a deeper shadow, a lighter roof): corrugated roofs,
  corner castings, doors with their locking bars at one end, rust run from
  the seams, snow on some, Hyperbole's logo or a box number stencilled on
  others. The footprints are the blockout's, so they play the same.
- **The quay:** a yellow-painted coping along the edge with black fenders
  hung off it, bollards with mooring lines out to the freighter, the two
  crane rails down its length with the gantries' feet standing on them
  (bogies, buffers, hazard-striped legs), a spare spreader and bundles of
  lashing rods lying about.
- **The freighter:** red hull, the bridge and its funnel (Hyperbole's
  logo) at the stern with a lifeboat each side, bay after bay of containers
  on the hatch covers with a hold open here and there, the windlass and
  its chains at the bow.
- **The harbour:** the port stands in a frozen sea all round, quay walls
  on every side: plates of sea ice running on past the map's edges,
  broken into shards and slush along the walls; the tunnel in from the
  south runs under it, its portal at the water's edge. The canvas leaves
  the sea out and `render_borderline_beyond.lua` draws it every frame,
  in the map and past it alike, so the ice has no seams.

- **Arrival:** the south, out of the tunnel.
- **The gantries:** two gantry cranes stand on the quay (four feet each,
  the rest overhead), their booms out over the freighter, a trolley
  running out and back with a container on its spreader (works.lua's
  `gantries`), beacons on their legs.
- **The dry dock:** a deep basin down the west side, its stepped walls
  going down with ladders, ice at the bottom, and a rusting hull up on its
  keel blocks, shored to the walls: its holds open, deck plates up, patches
  of red primer, scaffolding down one side, the propeller off its stern,
  welders at work on it in bursts of sparks (`map.welders`, works.lua).
  Nobody walks in and rounds fly over; a tower crane works over each end.
  KEEP OUT painted at its foot.
- **The ferry lift:** a tread-plate deck with railings down its sides,
  hinges where it meets the ferry, chevrons and FERRY painted on it, a
  control pedestal in one corner.
- **Safety lines:** the lanes the stacks leave clear are painted (yellow
  dashes) with each bay's number (A1 to F5), a zebra crossing to the lift,
  beacons round the lift.
- **The ferry's control terminals:** the lift is shuttered on its three
  landward sides (a lock, the terminals feature, as on the Wreck) until
  four Hyperbole terminals are hacked, one out in each corner of the yard
  (`borderline_landing.lua`'s `POSTS`): the far south-west past the dry dock, the
  east side, the north-west and the north-east ends of the quay. Each is
  guarded by a hauler dock (`DCK`) building junk haulers until it is shot
  down or its terminal hacked, a gun hauler or two and a pack of junk
  haulers. The objective line points at the nearest one left; the last
  one brings the shutters down ("open": Yappy calls you onto the lift, Max
  promises a bigger welcome).
- **The army:** gun haulers posted where the lanes cross
  (`GUNS`, ten) and round the terminals, three squads
  of gun haulers walking loops of the lanes, a pair of stalker haulers
  hunting the east stacks, two gun haulers at the lift, four rocket
  haulers (two under the gantries, two out in the yard), medic drones and
  a shield drone with the squads, junk haulers about the edges.
- **The ferry lift:** a platform at the quay, the way on, shut until
  Yappy has hacked it (`hold.lua`, the map's `hold`): she does it from
  wherever she is, but only while somebody stands on the lift; the first
  one on starts it, and it takes 60 s of standing there
  (`LIFT_HOLD`). With nobody on it the hack stops (it doesn't
  go back) and Yappy frets. Waves come at the lift as it goes, each when
  the hack gets so far, so stepping off never piles them up: two gun
  haulers and a medic drone off the west end of the quay at the start,
  four junk haulers up the lanes at 20%, three gun haulers off the east
  end at 40%, a rocket hauler and two gun haulers up the lanes at 60%,
  a stalker hauler, two gun haulers and a medic drone at 80%, a rocket
  hauler, two gun haulers and a shield drone off the west end at 90% (and
  a gun hauler with the junk at 20%; one more gun hauler in each for every
  player past the first); what's left of each stays on the
  lift. A bar on the lift's deck and one at the top of the screen show
  the hack; the objective line says whether it's running. When it's done
  the lift is the EXIT: "THE BRAGIUM PIT".

### 3. The Bragium Pit (`pit`, 60x60, at dusk)

How it's drawn (`render_borderline_mine.lua`, and the ground's in
`render_borderline_ground.lua`): four levels going down, each a shade
darker, the gravel rims, the terraces, the bench and the pit's floor
(Bragium veins and ore lying on it), each worked earth with grit and
stones, no joints. Every terrace wall has a berm of rocks along its top
and a rock face dropping inward to the level below (strata, cracks,
scree at its foot); the pit's outer wall drops the same from the rock
round it. Haul ramps between the levels go dark as they go down, ruts and
berms along them; the haul trucks' tracks run round the terraces. The
crystals are clusters of faceted purple shards glowing on the ground,
the trucks have treaded tyres, a ribbed bed heaped with ore and a ladder
up to the cab, the conveyors a steel frame on legs and a belt dusty with
Bragium, the boulders faceted with snow on them. The pad has Hyperbole's
logo on it. The ferry's top station is a lift on the south rim, where
you arrive; the mine lift up to Prosperity one on the north rim. The
rock round the pit (`Ground.LIVE`, like Liar's Landing's sea) is drawn
every frame in and past the map alike: paler slabs, strata, cracks,
stones, boulders, snow lying in the hollows, with no seams.

The two ramps down onto the pit's floor are gated (a lock, `THE PIT'S
FLOOR`) until four power terminals are hacked (`borderline_pit.lua`'s
`POSTS`): two on the outer terrace's west and east sides, two on the
bench's north-west and south-east corners, each guarded by a hauler dock
(`DCK`), a gun hauler and junk haulers. The last terminal opens the
gates ("open": Yappy, then Max), and the first one down onto the floor
brings Wilbur. He carries the mine lift's code: down, he drops his
keycard where he falls (glowing, bobbing), and the mine lift stays shut
until somebody picks it up ("keycard"). The objective line and the
markers go terminals, then the pad, then him, then his keycard, then the
mine lift. The army: plasma
haulers on the terraces' corners, gun haulers at the ramps and round the
terminals, a pair walking the outer terrace and three the bench, a pair
of stalker haulers going the other way, rocket haulers over the way out,
shield and medic drones, junk haulers on the floor.

The theme (`theme_pit.lua`): slow, drop-tuned groove metal at 120 BPM in
C minor. A blast opens it once (the siren, three beeps, the charge going
off, rubble raining down); then a lurching low-C grind with pick slides,
a chime of glass bells (the Bragium) over Cm, Ab, Bb, G with pickaxes on
the offbeats, a wailing lead over a double kick and a rock drill, and a
half-time stretch of blasts under the siren (~64 s loop).

The mine at work: two tower cranes swing over the floor from its
corners, two shafts on the inner terrace have headframes over them
(wheels turning, a cage running up and down: works.lua's `headframes`),
the conveyors carry glowing ore up (works.lua's `conveyors`), haul trucks
stand parked, floodlights on the rims and corners, beacons at the ramps
and the shafts, the haul road's edge painted round the outer terrace,
BLAST ZONE painted on the floor, and the Bragium glowing purple in the
dusk.


An open-pit mine in terraces going down to a floor in the middle: ramps
between the terraces, conveyors (cover), purple crystal clusters (they
glow, some burst in plasma when shot).

- **Arrival:** the south rim.
- Plasma haulers on the terraces, gun haulers on the ramps.
- **Wilbur** drops onto the pad in the pit's floor when the first player
  sets foot on it (the map's `boss`), once the power terminals have
  opened the way down; the mine lift stays shut until the keycard he
  drops is picked up. The objective line points at the pad until he
  comes, says to take him down, then points at his keycard.
- **The end:** the north rim's mine lift. EXIT: "PROSPERITY".

### 4. Prosperity (`prosperity`, 56x88, at dusk)

Built in `borderline_prosperity.lua`, drawn in `render_borderline_city.lua`
and the ground's module: dark asphalt streets (grit, cracks, patches,
manholes) with the yellow centre lines, pale paving round every block
with its kerb, the plaza paved cream and gold with a gold ring and rays
set round the statue, planters round its edges. Max's statue is gold on a
stepped plinth, seen from above: the flat-top, his shoulders and chain,
one arm flexed up, MAX on its plaque. Past the streets, the dome's glass
wall (ribs, panes, the shine on it) and the snowfield beyond it (wind
ripples, drifts, a rock here and there), drawn every frame like the
Landing's sea (`Ground.LIVE`).

**Max's screens** (`screens.lua`): in each corner district a block is a
paved square with a giant screen up on two legs in the middle, his face
live on it (faces.lua's portrait, talking), his name beside it, TO THE
MAX running along the bottom, a LIVE dot; a hauler dock and two gun
haulers guard each. Anything a player fires that touches a panel hurts it
(450 health each for one player, `Bosses.health`; a blast takes 40);
every one down, the rest turn up brighter, and Max has something to say
("screen1" .. "screen3"); the last one down, he throws the north gate
open (the lock `THE NORTH GATE`, a lock of the terminals feature with no
terminals, opened by `Terminals.serverUnlock`: "screens"). The objective
line and the markers point at the nearest screen still up. A screen down
is shattered glass in its frame, sparking, smoking a while.

The theme (`theme_prosperity.lua`): Max's own anthem, bright cheesy arena
rock at 132 BPM in E major. The PA opens it once (the chime, Hyperbole's
jingle on synth brass, the crowd); then two stomps and a clap under
chugged E, a brass fanfare over E, B, C#m, A, a chorus of lead guitar and
brass with the crowd shouting HEY, and a half-time stretch of presses
stamping with the jingle on a music box (~51 s loop).

Max's factory town under the dome: its blocks are factories
(corrugated roofs, sawtooth skylights, a chimney each with its smoke
rising and drifting: works.lua's `stacks`), loading lots with haul trucks
and pallets, and two "Phase 2" building sites, each a deep foundation
hole with a tower crane over it. Pipe bridges cross the avenue overhead
(works.lua's `overpipes`); dashed centre lines down the streets, zebra
crossings at the plaza, street lamps, floodlights on the plaza's corners
and beacons at the gates light it at dusk. Max's statue and screens
stand over it all.


Max's city under a glass dome: clean yellow streets, a plaza with a
giant statue of him, his face on four huge screens.

- **Arrival:** the south gate (open: they let you in).
- Every hauler type so far plus dozers, kamikazes and jet haulers; the
  first badass at the statue.
- **The screens:** four, one in each corner district. Each one shot down,
  Max turns the rest up brighter; on the last, he throws the north gate
  open.
- **The end:** the north gate. EXIT: "THE REFINERY".

### 5. The Refinery (`refinery`, 48x80, dark)

Built in `borderline_refinery.lua`, drawn in `render_borderline_hall.lua`
and the ground's module: the floor is bar grating in panels laid crosswise
(`grate`), scorched steel plates by the outflow (`outflow`); the river runs
across the hall in four runs joined by bends along the walls, each drawn
whole (deep purple, a hot core wandering down it, crust floes riding near
the banks, bubbles) between steel kerbs with hazard paint and railing
posts. The smelting tanks have riveted jackets, a yellow band, a domed top
with its charging hatch, ports glowing round them, a ladder and pipes; the
pipe racks run on supports with flanges and a valve wheel; the casting pit
has a runner across it feeding rows of moulds, some still glowing; ladles
stand parked for the cranes (crust on top, glowing cracks), ingots stacked
on pallets, slag gone hard where the river spilled. The hall's walls
(`hall`) are firebrick with a steel column every four tiles, the plant's
roofs past them.

**The bridges** (`bridges.lua`): every one stands drawn up, a bascule leaf
hinged on the south bank with its rams and a red lamp blinking, until the
bridge control on the bank below is hacked; then it swings down (1.6 s)
and lies across, a deck of grating between yellow girders. Each run's
bridges are a lock (`bridge1` .. `bridge4`, "THE FIRST BRIDGES" .. "THE
LAST BRIDGE") whose wall over each gap is `water` (rounds and sight cross,
feet don't), and each comes `after` the one below it, so its terminal
can't be worked, and the marker doesn't point at it, until that one is
down (`borderline_refinery.lua`'s `POSTS`): the intake's on its west
side, the next bank's at its east end, then west, then east, each away
from the bridges and guarded by a hauler dock (`DCK`) and two gun
haulers. Yappy and Max have a line for each bridge ("bridge1" ..
"bridge3", then "open"). On the minimap a bridge down shows across the
river, one up as a red bar on its bank.

The theme (`theme_refinery.lua`): mechanical industrial metal at 128 BPM
in D minor. The shift starts once (a steam whistle, the furnace catching,
a hammer blow); then the press, a clipped sixteenth riff on low D with the
kick on every chug and a forge hammer each bar; the pour, a lead singing
over Dm, Bb, F, C and Dm, Bb, Gm, A with anvils on the backbeat; the
vent, half-time chugs with steam hissing out of the floor; and the press
again (~53 s loop).

A smelting hall, dark (`night` { 0.42, 0.38, 0.52 }) and lit by its
molten river, which flows (works.lua's `flows`), and by work lamps on the
walls. Two bridge cranes run the length of the hall, a ladle of glowing
Bragium under each (`bridgecranes`); pipes run across it overhead; a
casting pit with glowing moulds sits by the outflow; vents in the floor
let off steam now and then (`steam`); the banks are railed and hazard
striped, and beacons stand at both ends of every bridge.


Indoors, hot and dark, lit purple: a river of molten Bragium winding up
the map, catwalks over it, smelting tanks, pipes.

- The river can't be waded (a `water` solid: rounds and sight cross it,
  feet don't), so the bridges are the way over and the places to hold.
  Spills from it are the hazard (`plasma` puddles).
- Every bridge is drawn up; the bridge control on each bank lowers the
  next run's, one run at a time up the hall.
- Arc haulers hold the far end of every bridge under their domes; plasma
  haulers by the tanks; gun haulers walking the banks and a gun and
  stalker pair across the middle one; junk haulers at the intake,
  kamikazes in the middle, medic and shield drones; a dozer and the
  badass at the outflow, rocket haulers watching the last bridge.
- **Smelter** at the outflow, the top of the map.
- **The end:** a freight door past the Smelter. EXIT: "THE ASSEMBLY LINE".

### 6. The Assembly Line (`assembly`, 56x72, under strip lights)

Built in `borderline_assembly.lua`, drawn in `render_borderline_line.lua`
and the ground's module: the floor is sealed concrete in big slabs with
saw-cut joints and oil stains (`steel`), the Foreman's floor checker plate
(`upper`) behind a steel step with its handrail, steel stairs up at either
end; the walls (`plant`) corrugated steel cladding with a column every
four tiles, the plant's roofs past them. The belts have steel frames with
hazard paint, dark rubber with cleats pointing the way each runs, end
rollers and a drive motor; the welding arms stand on bolted yellow
pedestals; the presses have four columns, a die on the bed and red light
curtains; the paint booths white panels, a hauler shell half painted,
overspray, an extractor fan; racks of hauler parts line the walls, parts
carts stand about.

**The belts carry you** (`belts.lua`): each one moves whoever stands on it
the way it runs, at 40 px/s (you walk at 45, so you can just about walk
against one), through on-foot's `floorDrift` (the host's step and your own
prediction alike), and the host carries the army's robots on the ground
the same way. The parts riding them go at the same speed (the map's
`speed`).

**The Fabricators** (`fabricators.lua`): one on a pad each side of the
floor (`FAB 1`, `FAB 2`), a gantry on four yellow legs with welding arms
sweeping in over a cradle with a hauler half built in it, a door on the
side facing the middle. While anyone is within 1100 px, every 14 s a
finished hauler walks out of the door (gun, junk, gun, kamikaze in turn),
up to three of its own out at once. Each has a boss's health (900 for one
player, `Bosses.health`; a blast takes 50); a `water` solid, so nobody
walks through it and rounds fly to it. The first one down, Max has a line
("fabricator"); the last one down opens the shutters over both stairs
(the lock `THE FOREMAN'S FLOOR`, opened by `Terminals.serverUnlock`:
"fabricators"). The objective line and the markers point at the nearest
one still up. Down, its beam falls across the cradle, sparking and
smoking.

The theme (`theme_assembly.lua`): thrash at 180 BPM in E minor, faster
than any other map's. The shift starts once (the line's klaxon, the PA's
robot voice counting it in, a rivet gun); then the gallop over a d-beat,
the riff (chromatic runs round low E, the kick doubling it), the solo (a
lead shredding sixteenth arpeggios over Em, C, D, B on a double kick), the
breakdown (half-time chugs, rivet guns, the robot voice chanting), and the
gallop again (~43 s loop).

The factory floor at work: hauler parts (torsos with their eyes not lit
yet, legs, arms) ride the belts, each belt the other way from the last
(works.lua's `conveyors` with `cargo` "parts"); the arms either side
swing in to weld, sparks flying (`arms`); the presses stamp (`presses`);
a bridge crane carries a finished hauler up and down the line
(`bridgecranes` with `load` "hauler"). Scrap pits full of rejected parts
on either side, a walkway line painted down each aisle, beacons at the
belt ends, the stairs and the shipping bay.


The factory floor: conveyor belts (a moving floor, the same piece Eternal
Mood's Foundry wants) carrying robots in pieces, assembly arms, paint
booths.

- Unfinished haulers lie on the belts and wake when a player passes.
- A Fabricator on each side, building; both down open the stairs up to
  the Foreman's floor. The belts carry whoever stands on them.
- **Foreman BIG-B055** on the top floor, by the line's end.
- **The end:** the shipping bay. EXIT: "THOUSAND PAPERCUTS".

### 7. Thousand Papercuts (`cuts`, 28x140, at dusk)

Built in `borderline_cuts.lua`, drawn in `render_borderline_cliff.lua` and
the ground's module: the road is dark asphalt with snow packed into it in
patches and faint tyre ruts; the cliff past it is drawn every frame
(`Ground.LIVE`, in and past the map alike): the rock east of the road
(slabs, strata, cracks, snow in the hollows, boulders), the drop west of
it going dark forever with cloud drifting far below, a rock face falling
away from the road's edge into it. The bunker's door is two armoured
leaves in a concrete frame, chevrons down their seam, Hyperbole's H over
it, red lamps; the sentries' nests are holes in the rock with a concrete
collar.

**The pursuit** (`pursuit.lua`): everything Max has left comes up the road
behind you, so you keep climbing. 8 s after you arrive, waves of the army
(junk, gun, kamikaze, stalker and rocket haulers in turn) come up the road
from 760 px below whoever is furthest back and go straight for them:
every 13 s while they keep climbing, down to every 5 s once they have
stopped 10 s, 12 of them out at most. And Max's barrage creeps up the road
behind them: rockets on red rings (`barrage.lua`, 22 at the middle of an
80 px blast, owned by nobody, so it never hurts the army) every 0.45 s
along a line that climbs 34 px a second on its own (you walk at 45), jumps
up to 420 px behind the rearmost when they get ahead, stops on them when
they stand and follows them back down if they retreat; it never climbs
past row 22, below the door. Yappy and Max have something to say when it
starts ("pursuit") and the first time the rearmost stands still long
enough ("stall"). Up the road ahead there's little: the sentries in the
rock and three rocket haulers on the bends.

**The door:** a hold (`hold.lua`, the same as Liar's Landing's lift):
60 s of standing at it while Yappy opens it, five waves up the road at you
as the hack goes (the last a badass); the barrage keeps shelling the road
below.

The theme (`theme_cuts.lua`): chase metal at 172 BPM. The alarm once (an
air-raid siren winding up, a clock ticking, a heartbeat); then the chase,
low D chugged in driving sixteenths with the hi-hat ticking every
sixteenth like a clock, again a whole step up in E; the climb up in F#,
rung chords and a soaring lead over a double kick; a short bridge, the
band dropping out to a heartbeat and the siren over a drone; and back
down to D (~39 s loop).

Hyperbole's service road up the cliff: yellow lines along both edges and
dashes down the middle, a crash barrier along the drop (render_borderline's
`drawRoadLines`, following `cutsRoad` and stepping across the bends), an
ore ropeway down the abyss beside it with buckets running up full and
down empty (works.lua's `ropeway`), a tower crane at the top still
building the bunker, lamps up the road's east edge and amber beacons on
the bends, red ones at the door.


A narrow road cut into a cliff, winding up the map, snow, a drop on one
side (solid edge), the cliff on the other.

- Sentry nests in the cliff, rocket haulers on the ledges above.
- Everything else comes up the road behind you, with Max's barrage
  creeping after you: you keep climbing.
- **The bunker door** at the top. Yappy opens it: a hold (60 s) while
  waves come up the road behind you.
- **The end:** the door. EXIT: "THE BUNKER".

### 8. The Bunker (`bunker`, 40x40, at dusk)

Built in `borderline_bunker.lua`, drawn in `render_borderline_roof.lua`
and the ground's module: the deck is armour plate in panels two tiles
square, each its own shade, a weld bead beside every seam, rivets at the
corners, scorch here and there; the sky round it is drawn every frame
(`Ground.LIVE`, in and past the map alike), banks of cloud drifting far
below, and the bunker's armoured side falling away from the roof's south
and east edges into it. The intakes have a hazard lip, the duct stepping
down dark to the fan, a guard's struts across it; the vents are louvred
housings, sooty round the foot; the eye's hatch in the middle, the way on,
is an iris of armoured blades shut over a red glass eye.

**The rim cannons** (`CAN`, `can_brain.lua`, `cannon_look.lua`): eleven,
round the rim on hazard-ringed mounts, each an army model (so the army
draws them, syncs them, takes the shots at them and leaves their wrecks):
a twin-barrelled gun on a turret that needs no line of sight. It turns
slowly to the nearest player within 1600 px, its muzzles glow for 0.9 s,
and it lobs a shell at where they stand: it comes down 1.5 s later on a
red ring within 45 px of them (`barrage.lua`: 26 at the middle of a 75 px
blast, owned by nobody). Each fires every 4.5-7.5 s, the first shots
staggered, so a few are always in the air. 120 health each. The way on
waits for all eleven (the lock `THE EYE'S HATCH`, no terminals, no walls,
opened by the borderline feature once none is left); Max and Yappy have
a line for the first one down ("cannon"), half of them ("cannons") and
the last ("open"). The objective line and the markers point at the
nearest cannon still up.

The theme (`theme_bunker.lua`): a final-boss epic at 104 BPM in A minor.
A bell tolls once while the organ swells; then the march (war drums, a
choir singing Am, F, G, Em over a chord rung out and chugged under it),
the anthem (a hero's tune in A minor over the organ and Am, F, C, G, the
double kick under it), the last stand (a solo racing over Am, Dm, E, Am),
and the march again (~74 s loop).

BNK-9 lifting off (below) is its own step, still to come.

An armour-plated deck, riveted, with clouds far below past its edge. Four
engine intakes, deep and hazard ringed, a turbine fan spinning down in
each with the engine's glow under it (works.lua's `fans`; nobody walks
in, rounds fly over, NO STEP painted by each); a radar turning on its
mast (`radars`); a gantry running over the deck with a missile on it
(`bridgecranes` with `load` "missile"); a walkway painted round the deck
and across it, a zebra at the hatch, floodlights in the corners and red
beacons on the rim.


The bunker's roof, square: vents and hatches as cover, a rim of
eleven cannons.

- **Part one:** the eleven cannons (120 health each) lob shells from the
  rim onto red rings. Destroy all eleven.
- **Part two:** the roof shakes, the players are thrown to a landing pad
  next to it, and BNK-9 lifts off. It flies round the arena (drawn over
  everything, its shadow on the ground), then parks and fights: a turret
  on each corner (shoot them off; they come back after a while), a rocket
  volley (red rings on the ground), mines shot onto the ground, and a big
  charged laser from its eye (a red line, 1 s, then the beam). Its red eye
  is the weak spot: hits there do double. Below half it flies faster and
  parks less.
- **The end:** BNK-9 crashes. Yappy logs in, the army stops, the last
  lines. HOME star on the pad.

## The reward: the Bragium Bolter

A plasma rifle, Hyperbole's own: fires slow purple bolts that splash and
melt (`plasma`), with a charged shot (hold to charge, a bigger bolt). A new
gun in `weapons/guns.lua`. Unlocked per player when BNK-9 falls, the way
the electric grenade is unlocked (the grenades feature's unlock, the
rewards feature's screen), saved with them. It is equipment, so it has
tiers (`tierStats`, read through `Tiers.apply`).

## Open questions

- **Names.** Borderline, Hyperbole, Maximum Maximilian Max, YAP-TP, Pandoria,
  Bragium: all proposals.
- **Plasma's effect.** "Melted" (armor halved for 3 s) is a proposal.
- **The torso crawl.** In for every hauler, or only the bigger ones.
- **Yappy on the map.** A character that walks ahead is new (closest is
  nothing yet); she could stay a voice only if that's too much.
- **New pieces the maps need:** an outline pass for the look, conveyor
  belts (shared with Eternal Mood's Foundry), the hold-the-spot objective
  (maps 2 and 7), a flying boss drawn over everything.

## Stages

One branch each, off `feature/borderline` (or straight into staging,
each a PR), in this order:

1. **Skeleton.** The `borderline` feature, all eight maps blocked out in
   `city-map/borderline.lua` (walls, floors, arrival, exits), their eight
   quests chained by `next` with the first on the board, and the level
   finishing at each exit.
2. **Story.** Banners and taglines, Max's face and intro screen, the
   chatter for Max and Yappy, the objective line.
3. **The robots' bodies.** The hauler look (one shared body, the code and
   kit per model) and the first two brains: junk and gun haulers, with
   the torso crawl. Map 1 and 2 populated.
4. **Rockets.** The rocket hauler and the jet hauler; red ground markers.
5. **Plasma.** The `plasma` damage type, its effect and puddles, the plasma
   hauler.
6. **The rest of the army.** Kamikaze, dozer, arc haulers; medic and shield
   drones; sentries; the badass.
7. **The maps dressed.** Each map's look, one map per PR.
8. **The bosses.** One per PR: Knuckle Scrapper (done), Wilbur (done), Smelter,
   Foreman, BNK-9.
9. **Set pieces.** The ferry hold, the screens, the bunker door; Yappy on
   the map.
10. **Themes and the reward.** The music, the Bragium Bolter.
