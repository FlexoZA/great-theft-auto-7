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

## What each type does

Besides the damage, each type does something to a player on foot:

| Type        | Effect                                                                                      |
| ----------- | ------------------------------------------------------------------------------------------- |
| `bullet`    | nothing more                                                                                |
| `fire`      | a fire that means it sets you alight: you burn on (3-4 s) after you are out of it           |
| `melee`     | bleeding: 3 a second for 4 s; a medkit stops it                                             |
| `shock`     | stunned: held still for 1 s (no walking, shooting or dodging)                               |
| `impact`    | knocked back 36 px and down for 0.6 s                                                       |
| `explosive` | blown back from the blast, 1.5 px per point of damage up to 110 px, and dazed (screen swims) |

Burning and bleeding top up rather than stack; a dodge puts a fire out.

## What resists what

| Piece                         | Slot   | Resists                                      |
| ----------------------------- | ------ | -------------------------------------------- |
| kevlar vest                   | armor  | bullet 30%                                   |
| bomb suit                     | armor  | explosive 50%, impact 30%, fire 15%          |
| plate carrier                 | body   | bullet 10%, explosive 10% (and armor x1.25)  |
| firefighter jacket            | body   | fire 40%                                     |
| leather jacket                | body   | melee 30%                                    |
| crash helmet                  | head   | impact 35%, explosive 10%                    |
| rubber boots                  | shoes  | shock 50% (and 5% slower on foot)            |

A better tier improves a resistance like any other stat: armor by the
tier's `boost`, clothes by its `bonus`. No piece, and nothing worn
together, stops more than 80% of a type.
Getting into a car, dying or leaving ends every status. The numbers are
at the top of `src/features/damage/init.lua`.

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
2. **Resistances.** Armor and clothes carry `resist = { fire = 0.4, ... }`
   (the share of that type they stop), improvable by tier like any stat.
   The damage feature asks `serverResist` (armor and gear answer), takes
   that share off every hit before the vest soaks up the rest, and shortens
   stuns, knockdowns, dazes and knocks by it. Pieces multiply (two 30%
   pieces stop 51%); no more than 80% of a type is ever stopped. See the
   resistance table below.
3. **Burning.** The damage feature owns a burning status: `Damage:ignite(server,
   victim, seconds, dps, by)` sets a player on foot alight, they take `fire`
   damage every quarter second until it runs out, and every client draws
   the flames. A new fire on someone already burning tops the time back
   up at the hotter rate; it never stacks. A dodge puts it out (stop, drop
   and roll), and so does getting into a car. The heat ray, the Tripod's
   beam and the open-borders fires keep hurting whoever stands in them as
   before, and set them alight on top (each with its own `afterburn`
   numbers), so getting out of the fire is no longer the end of it.
   Then the other types got theirs (the table above): bleeding, stuns,
   knockdowns and blasts that throw you, in the same status system
   (`DMG_FX`), with on-foot's `serverShove` for the knocks.
4. **Feedback.** Hit flashes tinted by type, a death effect per type (the
   Tripod's ash becomes the fire death, a blast leaves gibs), and maybe
   damage numbers.

Later, once cars are back on the table: crash damage (`impact` on a car
hitting a car or a wall) and resistances for vehicle models.
