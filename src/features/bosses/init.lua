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
--   6. It scales with the humans in the game (`Bosses.health`,
--      `Bosses.count` below): its health, and how many helpers it brings
--      (simps, squirrels, soldiers, a litter), are the base for one human
--      and grow by `perHuman` of the base for each human past the first,
--      counted when it spawns (or the helpers do). Two humans, double.
--      Hunters grow slower (`Bosses.plus`): one more for each human past
--      the first.
--   7. Its own brain: a module of its own that decides what it does, in
--      modes that cut in on each other (fighting, hunting, healing...), not
--      shared with any other character. Badly hurt (under `Heal.below` of
--      its health) it breaks off to go for a medkit lying within
--      `Heal.range`, takes it off the ground and is `Heal.amount` better
--      (heal.lua). The Hunters' brain (hunters/brain.lua) is the model.
--      It kites there: while it can see somebody it keeps facing them and
--      fighting on its way (backing or side-stepping to the medkit at its
--      walking pace, not turning its back and sprinting): shots, throws,
--      and a swipe at whoever comes close, yes; a charge, leap or lunge
--      only when it carries it towards the medkit, and a long rooted
--      wind-up only while the medkit is still far. Nobody in sight, it
--      just runs for it. `Heal.way` gives the way without turning it
--      (`Heal.giveUp` when there is none it fits), `Heal.pickUp` takes it.
--   8. It dodges: a player's ability about to land on it (a freeze's
--      warning ring, a leaper coming down, a heat ray) gets it moving out
--      from under it once it has had `react` seconds to see it
--      (dodge.lua): `Dodge.step(b, radius)` before its panic is read, or
--      `Dodge.threat` / `Dodge.away` for one that moves its own way.
--   9. It comes back harder (`Bosses.rage` below). Every time a job is
--      finished in this world (quests' clears) its bosses and enemies come
--      back tougher for it: `Bosses.health`, `Bosses.count` and
--      `Bosses.plus` already grow with the clears of the job under way,
--      so a boss built on them needs nothing more for its health and its
--      helpers. Its own hits are multiplied by `Bosses.power()` where they
--      land. A regular enemy (a soldier, an imp) takes `Bosses.enemyHealth`
--      for its health and `Bosses.enemyPower()` on its hits, and a boss's
--      per-player drop rolls its tier with `Bosses.dropTier()`. Off a quest
--      (a city event) the clears are 0, so nothing changes there. The boss
--      bar says how many times over it is.
--  10. It doesn't get stuck (walk.lua). It walks with `Walk.step` (corner
--      feeling, no slide of next to nothing), finds its way on
--      `Walk.nav(nav, blocked, radius)` (the walking grid as its own width
--      fits through it) and goes straight at somebody only when
--      `Walk.wideClear` says its whole width gets there: seeing them is
--      not enough. A charge walks `headlong` (into the wall, and stunned).
--
-- Modules
--   src/features/bosses/stamina.lua   the breath rule
--   src/features/bosses/bar.lua       the boss bar
--   src/features/bosses/heal.lua      going for a medkit
--   src/features/bosses/dodge.lua     getting out from under an ability
--   src/features/bosses/walk.lua      getting about without getting stuck

local Features = require("src.features")

local Bosses = {
  name = "bosses",
  priority = 100,
}

-- Tuning ------------------------------------------------------------------
Bosses.perHuman = 1 -- each human past the first adds this much of the base again: two humans, double; three, triple
Bosses.extra = 1 -- what each human past the first adds to a count that grows by Bosses.plus (Hunters)

-- Coming back harder: per time the job under way has been finished in this
-- world, up to `max` times.
Bosses.rage = {
  health = 0.25, -- a boss's health, +25% each time (1500 -> 1875 -> 2250 ...)
  damage = 0.15, -- a boss's hits, +15% each time
  count = 0.2, -- helpers and enemies brought in by count, +20% each time (5 -> 6 -> 7 ...)
  enemyHealth = 0.1, -- a regular enemy's health, +10% each time
  enemyDamage = 0.1, -- a regular enemy's hits, +10% each time
  max = 10, -- past this many it gets no harder
}

-- A boss's per-player drop: its tier rolled from the row for how many times
-- the job has been finished before (the last row from then on). Chances in
-- a hundred.
Bosses.dropTiers = {
  { common = 100 }, -- the first time: always common
  { common = 80, uncommon = 20 },
  { common = 65, uncommon = 30, rare = 5 },
  { common = 50, uncommon = 35, rare = 13, legendary = 2 },
  { common = 40, uncommon = 35, rare = 18, legendary = 7 },
  { common = 30, uncommon = 35, rare = 23, legendary = 12 }, -- the sixth time and every time after
}
local TIER_ORDER = { "common", "uncommon", "rare", "legendary" }

--- How many times the job under way has been finished in this world
--- before, up to rage.max; 0 off a quest (in the city, a city event). On
--- the host.
function Bosses.clears()
  local quests = Features.byName.quests
  local quest = quests and quests.serverActive and quests:serverActive()
  local root = quest and quests.root[quest.id]
  return root and math.min(quests:serverClears(root), Bosses.rage.max) or 0
end

--- The same on a client, from what the host has told it.
function Bosses.clientClears()
  local quests = Features.byName.quests
  local root = quests and quests.active and quests.root[quests.active]
  return root and math.min(quests.clears[root] or 0, Bosses.rage.max) or 0
end

--- What a boss's hits are multiplied by on this job.
function Bosses.power()
  return 1 + Bosses.rage.damage * Bosses.clears()
end

--- A regular enemy's health on this job, from its `base`.
function Bosses.enemyHealth(base)
  return math.floor(base * (1 + Bosses.rage.enemyHealth * Bosses.clears()) + 0.5)
end

--- What a regular enemy's hits are multiplied by on this job.
function Bosses.enemyPower()
  return 1 + Bosses.rage.enemyDamage * Bosses.clears()
end

--- The tier a boss's per-player drop comes in on this job ("common" the
--- first time). `rows` is a table like `Bosses.dropTiers` (the default);
--- `roll` in [0, 1) is for tests.
function Bosses.dropTier(rows, roll)
  rows = rows or Bosses.dropTiers
  local row = rows[math.min(Bosses.clears() + 1, #rows)]
  local total = 0
  for _, tier in ipairs(TIER_ORDER) do
    total = total + (row[tier] or 0)
  end
  roll = (roll or love.math.random()) * total
  for _, tier in ipairs(TIER_ORDER) do
    roll = roll - (row[tier] or 0)
    if roll < 0 then
      return tier
    end
  end
  return TIER_ORDER[1]
end

--- The humans in the game (bots don't count), at least one.
function Bosses.humans(server)
  local n = 0
  for _, p in pairs(server.players) do
    if not p.bot and p.body then
      n = n + 1
    end
  end
  return math.max(1, n)
end

--- What a boss's numbers are multiplied by right now.
function Bosses.scale(server)
  return 1 + Bosses.perHuman * (Bosses.humans(server) - 1)
end

--- What a count is multiplied by for the clears of the job under way.
local function more()
  return 1 + Bosses.rage.count * Bosses.clears()
end

--- A boss's health for the humans in the game and the clears of the job,
--- from its `base` for one human the first time.
function Bosses.health(base, server)
  return math.floor(base * Bosses.scale(server) * (1 + Bosses.rage.health * Bosses.clears()) + 0.5)
end

--- How many of a boss's helpers (or of a map's enemies) for the humans in
--- the game and the clears of the job, from `base` for one human the first
--- time; never fewer than one.
function Bosses.count(base, server)
  return math.max(1, math.floor(base * Bosses.scale(server) * more() + 0.5))
end

--- `base` (grown by the clears of the job) for one human and
--- `Bosses.extra` more for each human past the first (Hunters: two humans,
--- one more; three, two more); never fewer than one.
function Bosses.plus(base, server)
  return math.max(1, math.floor(base * more() + 0.5) + Bosses.extra * (Bosses.humans(server) - 1))
end

return Bosses
