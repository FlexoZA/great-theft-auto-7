-- Bosses: what every boss has in common, for the features that own one
-- (karen, alien-hunt, d-day, events) and for whoever writes the next.
-- This feature has no hooks of its own; it is the standard and the code
-- that keeps the bosses alike. A boss lives in its own feature, which owns
-- the fight (spawns it on the host, steps it, tells clients at 15 Hz, draws
-- it); this folder holds the parts a boss must not do differently.
--
-- The standard for a boss
--   1. Stamina (stamina.lua). A boss has breath like a player on foot:
--      running spends it, anything else lets it come back after a pause.
--      Empty, it is winded and can only walk, slower than a sprinting
--      player, until `recovered` is back, and it has no breath for an
--      ability (a scream, a leap, an MG nest) until it has a lungful of
--      `breath`. Melee (a slap, a swipe) and guns are not abilities: they
--      cost nothing. `Stamina.new(tuning)` on the host, `st:step(running,
--      dt)` every tick, `st:pace(run, walk)` for the speed, `st:has(cost)`
--      before an ability and `st:spend(cost)` when it goes.
--   2. On the wire, the boss's state message ends with `<stamina> <winded>`
--      (`st:wire()` gives them, `Stamina.read(args, i)` reads them back).
--   3. The boss bar (bar.lua). One look for every boss: the name over a
--      health bar, and its breath as a thin bar under it that throbs red
--      with "winded" beside it while it is blown. `Bar.draw(spec)`.
--   4. Tuning lives at the top of the boss's file, including its breath
--      (`drain`, `regen`, `recovered`, what an ability needs and costs):
--      a charge should last a little longer than a player's sprint (4.5 s
--      at 170 px/s) and the winded walk be slower than a player walking
--      away (45 px/s) or about the same.
--   5. When it goes down it raises `serverKill` with kind "boss", spills
--      koins, and if it was a quest's boss calls `quests:serverComplete`
--      with where it fell.
--
-- Modules
--   src/features/bosses/stamina.lua   the breath rule
--   src/features/bosses/bar.lua       the boss bar

local Bosses = {
  name = "bosses",
  priority = 100,
}

return Bosses
