# Turf War design

A team quest in the shape of Dota: two gangs of four, three lanes between
two bases, waves of simps marching down the lanes, towers guarding them,
and a vault at the back of each base. Break the other side's vault and the
job is done. It is the biggest quest in the game, so it lands in pieces
(see "PR order" at the bottom); this file is the agreed design they all
build to.

## Decisions

| Question | Decision |
| --- | --- |
| Where is it played? | **A new map, "The Lanes"** (`arena` in city-map's `maps`): a walled square with a base in two opposite corners and three lanes between them. Nobody about but the two teams and the simps. |
| Cars or feet? | **Both.** The lanes and the base courtyards are tarmac; you can drive them. The jungle between the lanes is trees with footpaths a car can just about squeeze down. Simps get flattened by a car at speed the same as anywhere. |
| How do teams form? | **Two teams of four, filled in the base** (later PR). Taking the job from the board takes everyone to the map, as every quest does. There, whoever stands in a base is on that base's team; the host keeps the sides even (a fifth player on one side is sent to the other). Bots fill the empty seats so it can be played by two people. |
| Can I hurt a teammate? | **No.** Bullets, blasts, rams and simps' fists do nothing to your own side. The host decides (weapons asks a `serverFriendly` question, see "Hooks it needs"). |
| Creeps | **Simps first, soldiers once a lane is broken.** Waves of five out of a base's gates, marching down the lanes, fighting the other side's creeps and players. To begin with they are simps, Karen's kind, with their fists. Once a side has destroyed all three of the other side's towers on a lane, that side's waves down that lane are soldiers, D-Day's riflemen in the side's colours (Dota's mega creeps). They see as far as a tower does, all round. One dropped creep is worth **1 koin**. |
| Killing a player | Drops **5 koins** where they fell, out of thin air (not from their wallet, unlike a wreck in the city). |
| Who can pick koins up? | **Anybody.** A koin on the ground belongs to whoever gets to it, teammate or not. |
| What are koins for here? | **Upgrades**, through the shop that already exists: health, stamina, reach, guns, abilities. A shop stand in each base is a shop bag, and **O** puts the shop screen up from anywhere on the map while the war is on (done, PR 4; everything is still free until the catalog gets prices). What you buy stays yours after the quest, like anything else you buy. |
| How do I get what I bought? | **A police car brings it.** Bought on a stand, it goes straight into your bag. Bought anywhere else, a police car comes out of your base's gate onto the lane nearest you, drives it reckless with the siren on, throws the parcel out on the road at the point nearest where you stood, and drives home. The parcel is a pickup: **anyone can take it**, your side or theirs, so meet the car. Your own towers and creeps let the car by; the other side's shoot it, and a wrecked car drops the parcel where it died (done, PR 5). |
| Dying | You come back at your own base's fountain after the usual death time, in your own car if it is there. |
| Winning | Break the other vault. Towers must go first: a vault is unhurt while any of the enemy's towers stand on the lane you came down (the gate tower counts). The quest completes for the winning side; everyone goes home by the EXIT star that comes up at the broken vault. |

## The map

Square, 64 x 64 tiles (4096 px a side, the biggest map in the game; its
canvas is the same size as the city's). World origin is the centre. The
whole thing is rotationally symmetric: everything built for the Southside
(bottom-left) is turned 180 degrees for the Northside (top-right), so both
teams walk the same distances and turn the same corners.

```
  +----------------------------------------------------------------+
  |  NW corner      TOP LANE (edge road)                  N gate    |
  |   bridge  ====================================> [ NORTHSIDE  ]  |
  |   ||      \  river runs                    /   [   base      ]  |
  |   ||       \  NW -> SE       jungle       /    [ towers/fount]  |
  |   ||        \                           /      [  VAULT      ]  |
  |   ||  jungle \      MID LANE  ---------/-------- [W gate      ]  |
  |   ||          \    (diagonal,      /           ||               |
  |   ||           \    SW <-> NE)   /             ||               |
  |   ||   camp     \              /    camp       ||  RIGHT       |
  |   ||             \   bridge  /                 ||  LANE        |
  |   ||              \   (0,0) /                  ||               |
  |   ||          /-----\      /  jungle           ||               |
  |   ||        /        \   /                     ||               |
  |   ||      /  jungle   \/                       ||               |
  |   ||    /   camp      /\       camp            ||               |
  |   ||  /             /   \                      ||               |
  | [S gate     ]     /       \                    ||               |
  | [ SOUTHSIDE ]---/           \                  || SE corner     |
  | [   base    ]=================================== bridge         |
  | [  VAULT    ]   BOTTOM LANE (edge road)                         |
  +----------------------------------------------------------------+
```

Numbers below are world px for the Southside; negate both for the Northside.

- **Lanes** are three tiles of tarmac (192 px) with a dashed centre line,
  wide enough for four cars abreast or a wave of simps around a tower. The
  edge lanes' centrelines run 288 px in from the wall (`map.lanes`, each a
  polyline from the Southside gate to the Northside gate):
  - *top*: out of the Southside's north gate at (-1760, 1280), up the west
    wall, round the north-west corner, along the north wall to the
    Northside's west gate at (1280, -1760).
  - *bottom*: out of the east gate at (-1280, 1760), along the south wall,
    round the south-east corner, up the east wall to the Northside's south
    gate at (1760, -1280).
  - *mid*: straight from the Southside's corner gate at (-1280, 1280)
    through the centre to the Northside's at (1280, -1280).
- **The river** is a concrete storm channel 200 px wide on the other
  diagonal, north-west corner to south-east corner, with a foot of water in
  it. It is walkable and drivable (it is only paint), and marks the halfway
  line. Where a lane crosses it there is a bridge deck with railings:
  the mid bridge at the origin and one in each corner (`map.bridges`).
- **Bases** are the two corner compounds, 768 px square, walled on the two
  inner sides (the map wall closes the other two). The courtyard is paved.
  Three gates, one per lane: the north gate for the top lane, the east
  gate for the bottom lane, and the corner cut off for the mid lane.
  Inside (`map.bases[team]`):
  - the **vault** in the middle of the courtyard at (-1664, 1664): a squat
    strongroom with the team's colour on its roof. Solid. The thing to
    break.
  - the **fountain** behind it towards the corner, at (-1840, 1840): the
    spawn and respawn point, a ring on the paving. Eight car slots along
    the two outer walls (`map.spawns` takes a Southside slot and a
    Northside slot in turn, so city-map's `placePlayers` lands a group half
    in each base: the first player in the Southside, the second in the
    Northside, and so on).
  - the **shop stand** by the fountain (a later PR draws and runs it).
- **Towers** (`map.towers`, `{ x, y, team, lane, tier }`): three per lane
  per side, standing on the verge just off the tarmac, on the inside of the
  lane. Tier 1 is the outer one, a little short of the river; tier 2 halfway
  back; tier 3 is the gate tower, right outside the base. Each is a square
  stone tower with a lit top (solid, 56 px). That makes 18 towers.
- **The jungle** is everything else: grass thick with trees (solid
  trunks, like the forest), shrubs you push through, and a **camp**
  (`map.camps`) in each clearing: four on each side, two in each wedge
  between an edge lane and the mid lane. A camp is where neutral simps
  stand about (a later PR); a footpath one tile wide (`map.paths`) joins
  each camp to the nearest lane and to its neighbour, so the jungle is a
  shortcut, not a wall. Nothing grows on the lanes, the river, the paths,
  the camps or in the bases. The river bed is open too: it is the
  jungle's fourth road, corner to corner.
- **Map fields** other features read: `map.kind == "arena"`, `map.lanes`,
  `map.river` (`{ x0, y0, x1, y1, w }`), `map.bridges`, `map.bases`
  (`{ [1] = { vault, fountain, gates, shop, team = 1 }, [2] = ... }`),
  `map.towers`, `map.camps`, `map.paths`, `map.shrubs`, `map.trees`,
  `map.spawns`, `map.teams` (`{ name, color }` for 1 and 2) and `map.arena`
  (the sizes it was built from). Vehicles on, crowd and traffic off.

The map has two HOME stars, one in each base's corner behind the fountain
(at (-1950, 1950) and its mirror), so anyone can take everyone home from
either base; the quest feature's EXIT star at the broken vault is the
proper way out.

## Rules (the turf-war feature, later PRs)

- **Teams.** `server.players[id].team` is 1 (Southside) or 2 (Northside),
  set by the host when the quest starts: taker's side first, then round
  robin by player id, humans before bots; bots are added to fill to four a
  side (`Bots:add` with a lane brain) and removed when the quest ends. The
  host broadcasts `TW_TEAM <id> <team>` and every machine colours names,
  arrows, minimap dots and car tags by team while the quest is on.
- **Friendly fire.** Weapons asks `Features.any("serverFriendly", server,
  attacker, victim)` before it hurts anyone; turf-war answers true for two
  players on the same team while the quest is on, and for a player and
  their own side's simps and towers. A blast still knocks koins out of a
  teammate's hands: no, it does nothing at all to them. Ramming a teammate
  is a shove, not damage. Simps only punch the other side.
- **Waves** (done, PR 3). Every 45 seconds a base sends a wave of five
  creeps out of its gates, two up the top lane, two along the bottom, one
  down the middle, each a little off the centreline so they walk as a file.
  A creep walks his lane's polyline to the far gate and on to the enemy
  vault, where he stands (the vault PR gives him something to do there). He
  sees 400 px all round, as far as a tower's zone, with line of sight past
  walls and trees, and the nearest enemy in sight, a player or the other
  side's creep, is his. A **simp** runs at them and punches (8 a second,
  like Karen's); a **soldier** stops, and after a moment to aim fires rifle
  bursts (the AK-47's rounds, carrying his side) for as long as he can see
  them. A side sends simps until it has **broken a lane**, every one of the
  other side's towers on it down; from then on its waves down that lane
  are soldiers. Two pistol rounds put either down, a car at speed flattens
  one, and a freeze or a stink works on him as on anyone. Both sides send
  waves the whole war, whoever is on the map, so a lone player has five
  creeps of their own marching with them and five coming at them; a side
  has at most fifteen out at once.
- **Towers** (done, PR 2). An MG on every tower, the same gun as the MG
  nest ability but turning the full circle: a tower watches a **detection
  zone** 400 px round itself (drawn on the ground in its side's colour, red
  while it has someone) and fires at the nearest enemy inside it that it
  can see (line of sight past every wall and tree, the rule bullets
  follow), at the pistol's rate and with the pistol's rounds, after half a
  second to swing round. It picks its target **Dota's way**: a player who
  hit it in the last four seconds and is still in sight, else the nearest
  enemy creep it can see, else the nearest enemy player. Its rounds belong
  to nobody but carry its side, so they pass through its own team. 800 hit
  points, worn down only by players' rounds and blasts (a soldier's or
  another tower's rounds do nothing). A tower that goes down stays down as rubble
  and spills ten koins. Tier 3 towers only fall once tier 2 on that lane
  has, tier 2 once tier 1 has: hitting a covered tower does nothing, a
  shield marks it and the HUD says so.
- **The vault.** 1500 hit points, hurt only when all three towers on at
  least one lane are down. A broken vault ends the quest: `QST_DONE` for
  everyone, the winning team's name in the banner, an EXIT star on the
  vault. Anyone who takes it goes home as usual.
- **Koins.** A simp that goes down drops one (the `serverKill` convention
  with kind "pedestrian", as Karen's do). A player killed on the map drops
  five out of thin air: turf-war listens for kind "car" kills while the
  quest is on and drops them itself, and money is told not to spill the
  wallet (a `serverKillPays` question, or turf-war raises the kill with a
  kind of its own that money prices at five: the second is simpler).
  Towers drop ten. Anyone can pick any of them up.
- **Respawn.** Turf-war answers `serverRespawnPoint` with the player's
  fountain while the quest is on.
- **Score.** The HUD shows towers standing per side and the koins picked
  up per team; the minimap shows towers, the vaults and every simp wave.

## Hooks it needs

New questions other features ask, all optional, all answered by turf-war:

| Question | Asked by | Meaning |
| --- | --- | --- |
| `serverFriendly(server, byId, victim, team)` → true/false | weapons (bullets, blasts, rams), simps | Answer true and the blow is dropped before any damage is done. `team` is set for a round fired by a side rather than a player (a tower's). Done in PR 2. |
| `serverPlayerTeam(team, server, player)` → team or nil | anything that colours or targets by side, through `Features.reduce` | A team number while the quest is on. Done in PR 2. |

Both are small changes to shared code (weapons) and are called out in their PRs.

## PR order

1. **The map** (done): `arena` in city-map's maps, `buildArena` in
   layout.lua and `drawArena` in render.lua, minimap tiles for every map
   kind, the job on the board, two HOME stars.
2. **Towers** (done): `src/features/turf-war/` with towers.lua (the
   thinking) and render.lua (the drawing), `TW_TOWERS` / `TW_DOWN` /
   `TW_COVERED`, the cover rule, koins for a fallen tower, the HUD line and
   minimap marks. With the least of teams the towers need: everyone is on
   the side of the base they landed in (`TW_TEAM`), a latecomer joins the
   smaller side, and the `serverFriendly` / `serverPlayerTeam` questions in
   weapons, so rounds, blasts and blows do nothing between friends.
3. **Waves** (done): `creeps.lua`, waves out of the gates down the lanes,
   simps first and soldiers down a broken lane, creeps seeing all round as
   far as a tower, towers targeting Dota's way, `TW_TROOPS` /
   `TW_TROOP_DOWN`, a koin each. Weapons' `serverShotAt` now carries the
   round's side, so a side's rounds fly through its own creeps.
4. **Teams proper**: sorting by where you stand, even sides, bots filling
   the seats, respawn at the fountain, names, arrows, minimap dots and car
   tags in your side's colour. The jungle camps.
5. **The vault**: hit points, the lane rule, soldiers attacking it,
   completion and the EXIT star.
6. **The shop** (done): the shop feature's `addShop` / `toggle` and its
   `shopAnywhere` questions; a stand in each base, O anywhere.
7. **Delivery** (done): `courier.lua`, a police car (a bots NPC in the
   police livery) down the lane with the parcel; the shop's
   `serverShopDeliver` question and `SHOP_SENT`; pickups take any item as
   a parcel.
8. **Koins for players and the score HUD.**
