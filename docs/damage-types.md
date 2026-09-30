# Damage types

Every hit in the game says what kind of hit it is: a bullet, a blast, a
flame, a crash, a bolt of lightning or a fist. Equipment can then resist
some kinds and not others, fire can keep burning after the hit, and the
kill feed and death effects can say what happened.

## The types

| Type        | What deals it                                                                          | Kill feed verb |
| ----------- | -------------------------------------------------------------------------------------- | -------------- |
| `bullet`    | every gun's round (the default for anything a gun fires)                               | wasted         |
| `explosive` | a rocket's blast, the D-Day mortar                                                     | blew up        |
| `fire`      | the heat ray ability, the Tripod's heat ray, the open-borders fires                    | burned         |
| `impact`    | being run over, the Runner's trample, a leap or slam landing, Karen's ram and scream   | flattened      |
| `shock`     | the Tripod's lightning                                                                 | fried          |
| `melee`     | punches, slaps, swipes and bites (simps, Karen, Bigfoot, squirrels), the Tripod's cage | beat down      |

The list lives in `src/features/damage/init.lua` (`Damage.types`), one
entry per type with its name, colour and kill feed words. A new type is a
new entry there. Anything that hurts without saying what it is counts as
`Damage.DEFAULT` (`bullet`).

Cars are left alone for now: crashes still do no damage, and a car takes
every type the same.

## How a type travels

The type is the last argument everywhere damage goes, so nothing that
doesn't care has to change:

- `Weapons:serverDamage(server, victim, attacker, amount, angle, type)`
- `Weapons:damageCar(server, car, byId, amount, pid, angle, type)`
- guns declare `damageType` (default `bullet`); a missile's blast declares
  `blast.type` (default `explosive`). Each projectile carries both.

And every hook that hears about damage gets it too:

| Hook                                                           | New argument                           |
| -------------------------------------------------------------- | -------------------------------------- |
| `serverAbsorbDamage(amount, server, victim, type)`             | `type`                                 |
| `serverPlayerDamaged(server, victim, attacker, amount, type)`  | `type`                                 |
| `serverShotAt(server, x, y, radius, by, angle, damage, type)`  | `type`                                 |
| `serverBlast(server, x, y, radius, damage, by, type)`          | `type`                                 |
| `serverWallHit(server, x, y, damage, by, type)`                | `type`                                 |
| `serverKill(server, { ..., cause })`                           | `cause`: the type that did it, or nil  |

`WPN_KILL` and `WPN_WRECK` carry the type on the end, so every client can
word the kill feed ("Bob burned Alice") and pick a death effect.

## The PRs

1. **Plumbing** (no change to how the game plays). The `damage` feature
   with the list of types; the type through weapons and every hook above;
   every damage call tagged with its type; the kill feed words it by type.
   Also: `serverDamage` now respects spawn protection, as bullets and
   rockets always did (a boss could hurt someone the moment they came back).
2. **Resistances.** Wearables get `resist = { fire = 0.3, ... }` (the share
   of that type they stop), improvable by tier like any stat. Armor and
   gear take their share in `serverAbsorbDamage` before the vest soaks up
   what is left, so a fire suit and a bulletproof vest are different things.
3. **Burning.** The damage feature owns a burning status: `Damage:ignite(server,
   victim, seconds, dps, by)` sets someone alight, they take `fire` damage
   every tick until it runs out, and every client draws the flames. The heat
   ray, the Tripod's beam and the open-borders fires set people alight
   instead of each running their own tick loop.
4. **Feedback.** Hit flashes tinted by type, a death effect per type (the
   Tripod's ash becomes the fire death, a blast leaves gibs), and maybe
   damage numbers.

Later, once cars are back on the table: crash damage (`impact` on a car
hitting a car or a wall) and resistances for vehicle models.
