-- The wiki's pages on the Cyber Feud's enemies (tools/wiki, docs/wiki.md),
-- for init.lua's `wikiEnemies`: the factions' soldiers here, from troops.lua's
-- numbers and their brain's (Troops.brain, A-Man's Combine), then each
-- special's and boss's own page from its own module, next to its numbers.

local Features = require("src.features")
local Troops = require("src.features.cyber-feud.troops")
-- In the order their pages come.
local Droids = require("src.features.cyber-feud.droids")
local Enforcers = require("src.features.cyber-feud.enforcers")
local Rippers = require("src.features.cyber-feud.rippers")
local Sparkers = require("src.features.cyber-feud.sparkers")
local Watchers = require("src.features.cyber-feud.watchers")
local Volt = require("src.features.cyber-feud.volt")
local Interceptors = require("src.features.cyber-feud.interceptors")
local WarRigs = require("src.features.cyber-feud.war_rigs")
local Stings = require("src.features.cyber-feud.stings")
local Marksmen = require("src.features.cyber-feud.marksmen")
local Turrets = require("src.features.cyber-feud.turrets")
local Brutes = require("src.features.cyber-feud.brutes")
local Kilowatt = require("src.features.cyber-feud.kilowatt")
local Saye = require("src.features.cyber-feud.saye")
local Vex = require("src.features.cyber-feud.vex")
local Dropship = require("src.features.cyber-feud.dropship")

local Combine = Troops.brain
local Wiki = {}

--- A gun of a side's `loadout` (one of its rows), in words: what a round
--- (or a pull) does, how he fires it, and how many of them carry it.
local function armsText(l, total)
  local gun = Features.byName.weapons.guns[l.gun]
  local hit = gun.pellets and ("%g pellets of %g damage a pull"):format(gun.pellets, gun.damage)
    or ("%g damage a round"):format(gun.damage)
  local how = l.burst > 1 and ("in bursts of %g, then %g s"):format(l.burst, l.pause)
    or ("one at a time, %g s apart"):format(l.pause)
  return { gun.name:sub(1, 1):upper() .. gun.name:sub(2), ("%s, %s; %g in %g of them carry one"):format(hit, how,
    l.weight, total) }
end

--- The soldiers' wiki pages (docs/wiki.md): one side's (`key`) rank and file.
local function soldierPage(key, page)
  local conf = Troops.side[key]
  local total = 0
  for _, l in ipairs(conf.loadout) do
    total = total + l.weight
  end
  local weapons = {}
  for _, l in ipairs(conf.loadout) do
    weapons[#weapons + 1] = armsText(l, total)
  end
  for _, w in ipairs(page.weapons or {}) do
    weapons[#weapons + 1] = w
  end
  local G = Features.byName["city-map"].cyberFeud
  local abilities = {
    "Calm until somebody takes the Shard or a player hurts one of them (on the Drop), or a player walks in past "
      .. "the way in (the Market, the tower, the Roof): then the whole street wakes at once.",
    ("Sees %g px ahead in a cone %g degrees wide (%g once on edge) and hears anyone within %g px all round."):format(
      Combine.RANGE, math.deg(conf.fov), math.deg(conf.alertFov), conf.aware),
    ("Spotting somebody, shouts it and calls in up to %g of his own side within %g px."):format(Troops.callAnswer,
      Troops.callHeard),
    ("One of them going down sends up to %g more within %g px to look."):format(Troops.downAnswer, Troops.downHeard),
    ("Guard stations: an MG nest with a gunner on it and riflemen round it who fight from cover; drop the gunner "
      .. "and the nearest of the crew runs to the gun. The station house's garrison (%g of them for one "
      .. "player) comes out of the door one after another once you are within %g px of it."):format(G.GARRISON,
      G.GARRISON_REACH),
    ("The feud: on the Drop and the Market the two sides shoot each other on sight. On the Overpass they hold fire "
      .. "until a round of one side hits the other, then fight for %g s after the last such hit. In the tower and "
      .. "on the Roof they never do: their rounds pass through each other."):format(Troops.flare),
  }
  for _, a in ipairs(page.abilities or {}) do
    abilities[#abilities + 1] = a
  end
  local tips = {
    ("He turns at only %g rad/s: sprint across his cone and he loses you."):format(Combine.TURN),
    "Pull them into the other side's line of fire and let them fight it out.",
    "A car at speed runs them down.",
  }
  for _, t in ipairs(page.tips or {}) do
    tips[#tips + 1] = t
  end
  return {
    kind = "cyber-feud/" .. key .. "-soldier",
    pick = page.pick,
    name = page.name,
    quests = page.quests,
    where = page.where,
    about = page.about,
    stats = {
      { "Health", conf.health },
      { "Speed", ("%g px/s walking, %g on a beat, %g closing in"):format(Combine.WALK, Combine.PATROL_WALK,
        Combine.CHASE_WALK) },
      { "Sight", Combine.RANGE, "px" },
      { "Numbers", page.numbers },
    },
    weapons = weapons,
    abilities = abilities,
    tips = tips,
    drops = ("%g koins, maybe a pickup"):format(conf.drops),
  }
end

--- The wiki's pages on the level's enemies (tools/wiki, docs/wiki.md): the
--- two sides' soldiers here, then each of the others' own, as `serverEnemies`.
function Wiki.wikiEnemies(add)
  local g, b = Troops.nestGun, Troops.breakIn
  local nest = { "MG (a station's nest)", ("%g damage a round, %g s apart, in bursts of %g then %g s, out to %g px, "
    .. "only into the nest's arc"):format(g.damage, g.cooldown, g.burst, g.pause, g.range) }
  local Gates = require("src.features.cyber-feud.gates")
  add(soldierPage("halcyon", {
    pick = function(e)
      return not e.id.elite
    end,
    name = "Halcyon officer",
    quests = { "cyber-feud", "cyber-feud-market", "cyber-feud-overpass", "cyber-feud-tower", "cyber-feud-roof" },
    where = "Every map: roadblocks and squads on the Drop, the Market's east side, the Overpass's checkpoints, "
      .. "every floor of the tower, the Roof's dropship",
    about = "Halcyon's rank and file: grey armour, a white helmet and a magenta visor strip. Disciplined: they hold "
      .. "posts, walk beats in squads and call in what they see.",
    numbers = ("Squads of %g; more on a job finished before"):format(Troops.side.halcyon.squad),
    weapons = { nest },
    abilities = {
      ("In Halcyon Tower, asking VEX to open a locked door opens its guard room too: %g officers (for one player) "
        .. "come out after you."):format(Gates.roomGuards),
    },
  }))
  local e = Troops.elite
  local ar = Features.byName.weapons.guns.ar
  add({
    kind = "cyber-feud/halcyon-soldier",
    id = "cyber-feud-elite-officer",
    pick = function(en)
      return en.id.elite == true
    end,
    name = "Elite officer",
    quests = { "cyber-feud-roof" },
    where = "The Roof: one with each of the dropship's drops from the second on",
    about = "A Halcyon officer in black and gold, the best the company has: tougher, with a harder-hitting rifle "
      .. "fired in longer bursts.",
    stats = {
      { "Health", Troops.side.halcyon.health * e.health },
      { "Speed", ("%g px/s walking, %g on a beat, %g closing in"):format(Combine.WALK, Combine.PATROL_WALK,
        Combine.CHASE_WALK) },
      { "Sight", Combine.RANGE, "px" },
    },
    weapons = {
      { ar.name, ("%g damage a round, in bursts of %g, then %g s"):format(ar.damage * e.damage, e.burst, e.pause) },
    },
    abilities = {
      ("%g times an officer's health, and his rounds hit %g times as hard."):format(e.health, e.damage),
      "Comes down the dropship's ropes with the rest of the drop and walks a beat round the relay it is guarding.",
      ("Calls in up to %g of his own side within %g px when he spots you, as any officer."):format(Troops.callAnswer,
        Troops.callHeard),
    },
    tips = {
      "Drop him first: his bursts are the ones that hurt.",
      ("He turns at only %g rad/s: sprint across his cone and he loses you."):format(Combine.TURN),
    },
    drops = ("%g koins, maybe a pickup"):format(Troops.side.halcyon.drops),
  })
  add(soldierPage("static", {
    name = "Static ganger",
    quests = { "cyber-feud", "cyber-feud-market", "cyber-feud-overpass", "cyber-feud-tower" },
    where = "The Drop's corners and blocks, the Market's west and its chop shop, the Overpass's shoulders and the "
      .. "Knot, Halcyon Tower breaking in from below",
    about = "The Static's street gang: dark mismatched clothes, cyan-tipped cable hair, a chrome forearm. All noise: "
      .. "a wide cone, a keen ear and packs that rush.",
    numbers = ("Packs of %g; more on a job finished before"):format(Troops.side.static.squad),
    weapons = { nest },
    abilities = {
      ("In Halcyon Tower they break in from below: a pack up onto the lowest floor anyone is on, the first %g s "
        .. "after it wakes and then every %g s, while fewer than %g of them (%g more for each human past the first) "
        .. "are on that floor. From floor %g up a sparker comes with them, from floor %g up a brute."):format(b.first,
        b.every, b.most, b.perHuman, b.sparkerFrom, b.bruteFrom),
      "In the Market, General Volt's backup: a pack runs in from the lanes each time he shouts for it.",
    },
  }))
  Droids.wikiEnemies(add)
  Enforcers.wikiEnemies(add)
  Rippers.wikiEnemies(add)
  Sparkers.wikiEnemies(add)
  Watchers.wikiEnemies(add)
  Volt.wikiEnemies(add)
  Interceptors.wikiEnemies(add)
  WarRigs.wikiEnemies(add)
  Stings.wikiEnemies(add)
  Marksmen.wikiEnemies(add)
  Turrets.wikiEnemies(add)
  Brutes.wikiEnemies(add)
  Kilowatt.wikiEnemies(add)
  Saye.wikiEnemies(add)
  Vex.wikiEnemies(add)
  Dropship.wikiEnemies(add)
end

return Wiki
