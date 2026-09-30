# Changelog

Every change players would notice, newest first. The game reads this file
and shows it from the icon in the bottom-left corner of the main menu, and
the version it shows is the newest release here.

How to write it (details in "Changelog and versioning" in `docs/features.md`):
- Every pull request into `staging` adds a line under `## [Unreleased]`, in
  `### Added`, `### Changed` or `### Fixed`. Write it for players.
- A release is `staging` merged into `main`: `[Unreleased]` becomes
  `## [x.y.z] - YYYY-MM-DD` and a fresh empty `[Unreleased]` goes on top.

## [Unreleased]

### Added
- A changelog on the main menu: the icon in the bottom-left corner opens it,
  and a dot on it means there is something you have not read yet.
- The game has a version number, shown next to the changelog icon.

## [0.1.0] - 2026-09-30

The first numbered release: everything built so far.

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
