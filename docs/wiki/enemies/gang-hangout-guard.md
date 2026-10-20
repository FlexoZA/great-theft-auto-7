<!-- Written by tools/wiki/run.lua from the game's code (`make wiki`): change the game, not this page. -->

# Hangout guard

[Wiki](../README.md) / [Enemies](README.md) / The city

<img src="img/gang-hangout-guard.png" alt="Hangout guard" width="240">

Another player's hired crew. Up to 4 guards stand at their posts outside a Gang Hangout and go after anyone who picks a fight with their boss, the boss's buildings or the crew.

| | |
|---|---|
| **Where** | The city, on the sidewalk in front of a player's Gang Hangout |
| **Health** | 60 (Street thugs) to 90 (Combine) |
| **Speed** | 150 px/s going after you, 70 walking back to their posts |
| **Numbers** | 4 per hangout, each replaced 10 s after going down while the fund pays for it |

## Weapons

- **Street thugs (level 1)**: pistol: 20 damage a round, in bursts of 2, 1 s between bursts, out to 520 px, about 33 damage a second; 60 health each
- **Bent cops (level 2)**: uzi: 12 damage a round, in bursts of 5, 1 s between bursts, out to 520 px, about 47 damage a second; 70 health each
- **Riflemen (level 3)**: AK-47: 18 damage a round, in bursts of 4, 0.8 s between bursts, out to 520 px, about 64 damage a second; 80 health each
- **Combine (level 4)**: shotgun: 6 pellets of 11 damage a shot, a shot every 0.9 s, out to 218 px, about 73 damage a second; 90 health each

## Abilities

- Each level of the hangout is a different crew with a different gun: the owner upgrades them.
- Come after anyone who hurts the boss's buildings anywhere in the city, the boss on or next to the hangout's block, or one of them. Police officers on foot who do it too.
- Stay after you for 30 s, renewed by every new attack, then walk back to their posts.
- Hold fire while their boss or another guard is in the way.
- Their rounds hit police officers, and never make their boss wanted.

## How to beat it

- A car at 60 px/s or more hurts them: 0.3 health for every px/s it is going.
- Leave the boss alone off their block and nobody comes out.
- Freezing and stink work on them: a stink cloud sends them running.
- An empty fund means no replacements: take the guards down and the door stays shut.
