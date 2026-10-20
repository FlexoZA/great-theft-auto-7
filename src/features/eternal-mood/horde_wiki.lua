-- The wiki's pages on the horde (tools/wiki, docs/wiki.md), for init.lua's
-- `wikiEnemies`: the possessed (one a rank), the Interns, the imps and the
-- Cacodaemons, from horde.lua's numbers and their brains'.

local Features = require("src.features")
local Horde = require("src.features.eternal-mood.horde")
local Possessed = require("src.features.eternal-mood.possessed_brain")
local Imps = require("src.features.eternal-mood.imp_brain")
local Interns = require("src.features.eternal-mood.intern_brain")
local Cacos = require("src.features.eternal-mood.cacodaemon_brain")
local Fireballs = require("src.features.eternal-mood.fireballs")

local Wiki = {}

--- What every page here shares: the guns, the fireballs, the ranks and the
--- sentences said of all the possessed.
local function common()
  local Guns = Features.byName.weapons.guns
  local Grenades = require("src.features.grenades")
  local Fire = Fireballs.KINDS
  local P, R = Possessed, Possessed.RANKS
  local possessedMaps = { "eternal-mood", "eternal-mood-earth", "eternal-mood-foundry" }
  local function koins(kind)
    return ("%g koins, and maybe a pickup"):format(Horde.drops[kind])
  end
  local function speed(r)
    return ("%g px/s after you, %g on patrol"):format(r.speed, r.walk)
  end
  local function sight(r)
    return ("%g px ahead, %g degrees across (%g on edge), %g px all round"):format(r.range,
      math.floor(math.deg(r.fov) + 0.5), math.floor(math.deg(r.alertFov) + 0.5), r.aware)
  end
  local groan = ("Spotting you, it groans: the horde within %g px comes to look. One going down sends those within "
    .. "%g px to where he fell."):format(P.CALL, P.ALARM)
  local lose = ("Loses you and looks about where it last saw you for %g s, then goes back to its post."):format(
    P.SEARCH)
  local heck = "Its rounds pass through the rest of Heck: nothing of Heck's hurts anything else of Heck's."
  return {
    Guns = Guns, Grenades = Grenades, Fire = Fire, P = P, R = R, possessedMaps = possessedMaps, koins = koins,
    speed = speed, sight = sight, groan = groan, lose = lose, heck = heck,
  }
end

--- The possessed: one page a rank.
local function possessedPages(add)
  local c = common()
  local Guns, Grenades, P, R, possessedMaps, koins = c.Guns, c.Grenades, c.P, c.R, c.possessedMaps, c.koins
  local speed, sight, groan, lose, heck = c.speed, c.sight, c.groan, c.lose, c.heck
  local st = R.staffer
  local pistol = Guns[st.base]
  add({
    kind = "eternal-mood/staffer",
    name = "Zombie staffer",
    quests = possessedMaps,
    where = "Fobos Base, Heck on Earth and the Foundry, at desks and posts and on patrol",
    about = "The UAC's office staff, Heck's now, still mostly at work. A staffer shambles at whoever it sees and "
      .. "fires its pistol now and then: no cover, no tactics.",
    stats = {
      { "Health", st.health },
      { "Speed", speed(st) },
      { "Sight", sight(st) },
    },
    weapons = {
      { (pistol.name:gsub("^%l", string.upper)), ("%g damage a round, %g s on you before the first, then one "
        .. "every %g to %g s, out to %g px"):format(st.gun.damage, st.aim, st.pause[1], st.pause[2], st.range) },
    },
    abilities = {
      ("Closes to about %g px and stands there shooting."):format(st.close),
      groan,
      "Shot by somebody it can't see, it turns that way and comes.",
      lose,
      heck,
    },
    tips = {
      "The easiest of the possessed: it never takes cover, so cut it down in the open.",
      "The Floor Manager's quick meetings bring more of them in through the Hangar's doorways.",
    },
    drops = koins("staffer"),
  })

  local gd = R.guard
  local shotgun = Guns[gd.base]
  add({
    kind = "eternal-mood/guard",
    name = "Zombie guard",
    quests = possessedMaps,
    where = "Fobos Base, Heck on Earth and the Foundry, watching doorways and walking patrols",
    about = "The UAC's security, possessed, and the one that fights smart. Posted, it sweeps its gaze across the "
      .. "doorway it watches; in a fight it ducks behind something solid, steps out to shoot and ducks back.",
    stats = {
      { "Health", gd.health },
      { "Speed", speed(gd) },
      { "Sight", sight(gd) },
    },
    weapons = {
      { (shotgun.name:gsub("^%l", string.upper)), ("%g pellets of %g damage a pull, one pull every %g to %g s, out to "
        .. "%g px"):format(gd.gun.pellets, gd.gun.damage, gd.pause[1], gd.pause[2], gd.range) },
      { "Grenade", ("%g%% of guards carry one: %g explosive damage within %g px, thrown at anyone %g to %g px off, "
        .. "never near the rest of the horde"):format(gd.grenadier * 100, Grenades.blast.damage,
        Grenades.blast.radius, P.GRENADE_MIN, Grenades.range) },
    },
    abilities = {
      ("Fights from cover within %g px of where it is, out for %g to %g s at a time to shoot, back in for %g to %g s.")
        :format(P.COVER_RANGE, P.PEEK[1], P.PEEK[2], P.HIDE[1], P.HIDE[2]),
      ("Shot by somebody it can't see, it goes to ground, and the others who know to within %g px with it. "
        .. "After %g s with no more shots, up to %g of them go out to sweep where the shots came from."):format(
        P.PIN_SHARE, P.QUIET, P.SWEEP_SQUAD),
      ("Never goes more than %g px from its post."):format(gd.leash),
      ("Lost you a moment ago? A guard with a grenade may lob it where you were, within %g s."):format(P.LOST_THROW),
      groan,
      heck,
    },
    tips = {
      "Flank it: its cover only faces the way it thinks you are.",
      "Keep moving when you hear the grenade call, and don't stand still behind a crate it knows about.",
    },
    drops = koins("guard"),
  })

  local ot = R.overtime
  local minigun = Guns[ot.base]
  add({
    kind = "eternal-mood/overtime",
    name = "Overtime guy",
    quests = possessedMaps,
    where = "Fobos Base by the hangar lift, Heck on Earth's overpass and starport gate, and the Foundry",
    about = "The big man with the chaingun, who never went home. He holds his ground near his post and fights from "
      .. "cover, spinning up each time he steps out.",
    stats = {
      { "Health", ot.health },
      { "Speed", ("%g px/s, and he never chases"):format(ot.speed) },
      { "Sight", sight(ot) },
    },
    weapons = {
      { (minigun.name:gsub("^%l", string.upper)), ("winds up for %g s (you hear it), then %g damage a round, %g rounds "
        .. "a second, out to %g px"):format(ot.spinUp, ot.gun.damage, 1 / ot.every, ot.range) },
    },
    abilities = {
      ("Never goes more than %g px from his post: he fights from round it, in and out of cover."):format(ot.leash),
      ("Slow to swing round: %g rad/s, so his stream drags after you."):format(ot.turn),
      "Goes to ground with the rest when shot from out of sight, but never out on a sweep.",
      groan,
      heck,
    },
    tips = {
      "Listen for the wind-up and get behind something before the rounds come.",
      "Run across his aim, not away from it: he can't turn fast enough to follow.",
      ("He won't chase you: stay past %g px from his post and pick him off."):format(ot.leash + ot.range),
    },
    drops = koins("overtime"),
  })
end

--- The Interns, the imps and the Cacodaemons.
local function hordePages(add)
  local c = common()
  local Guns, Fire, possessedMaps, koins = c.Guns, c.Fire, c.possessedMaps, c.koins
  local I = Interns
  local pistolHits = math.ceil(I.HEALTH / Guns.at(1).damage)
  add({
    kind = "eternal-mood/intern",
    name = "Intern",
    quests = possessedMaps,
    where = "Fobos Base, Heck on Earth and the Foundry, in mobs crouched round a meal; the Floor Manager's meetings "
      .. "bring more",
    about = "The UAC's unpaid interns, possessed and unarmed, the lowest rank there is. Never one at a time: they come "
      .. "in mobs, crouched round a body they dragged in until something wakes them.",
    stats = {
      { "Health", ("%g: %g pistol %s"):format(I.HEALTH, pistolHits, pistolHits == 1 and "round" or "rounds") },
      { "Speed", ("%g px/s from afar, %g within %g px"):format(I.SHAMBLE, I.LURCH, I.LURCH_FROM) },
      { "Numbers", "A mob of several for one player, one more for each player past the first" },
    },
    weapons = {
      { "Claws", ("%g melee damage, one every %g s, right up against you (arms up for %g s first)"):format(
        I.CLAW_DAMAGE, I.CLAW_EVERY, I.WINDUP) },
    },
    abilities = {
      ("A mob wakes when you come within about %g px, it sees you in plain sight within %g px, or one of it is hurt. "
        .. "Then the whole mob comes."):format(Horde.wake, Horde.mobSees),
      ("Awake, each one goes for the nearest player within %g px."):format(I.HUNTS),
      "A Mecha Zombie walks a loop round each mob, and its scream wakes the mob too.",
    },
    tips = {
      "Shoot one and the lot of them come: thin the mob from a distance, or throw a grenade into the meal.",
      "The blood trail tells you where a mob is eating before you walk into it.",
      "One claw is nothing; a crowd round you is not. Back off as you shoot.",
    },
    drops = ("%g koin, and now and then (%g%%) a pickup"):format(Horde.drops.intern, Horde.internPickups * 100),
  })

  local M = Imps
  local fb = Fire.fireball
  add({
    kind = "eternal-mood/imp",
    name = "Imp",
    quests = { "eternal-mood", "eternal-mood-earth", "eternal-mood-foundry", "eternal-mood-heck" },
    where = "Every Eternal Mood level, bursting out of vents, manholes and cracks as you come near",
    about = "The common demon, brown and spiky. A pack crawls out of a vent one after another, keeps its distance, "
      .. "strafes, and throws fireballs at you.",
    stats = {
      { "Health", M.HEALTH },
      { "Speed", ("%g px/s closing in, %g strafing"):format(M.RUN, M.STRAFE) },
      { "Sight", ("%g px all round; seeing nobody, it hunts the nearest player within %g px"):format(M.SEES,
        M.HUNTS) },
      { "Numbers", ("A pack a vent, one out every %g s, one more for each player past the first"):format(
        Horde.crawlEvery) },
    },
    weapons = {
      { "Fireball", ("%g fire damage, held up for %g s first, one every %g to %g s, thrown out to %g px at %g px/s")
        :format(fb.damage, M.WINDUP, M.THROW_EVERY[1], M.THROW_EVERY[2], M.THROW_RANGE, fb.speed) },
      { "Claws", ("%g melee damage, one every %g s, within %g px"):format(M.CLAW_DAMAGE, M.CLAW_EVERY, M.CLAW_REACH) },
    },
    abilities = {
      ("A vent bursts open the first time a player comes within about %g px of it, and its pack crawls out (%g s "
        .. "each)."):format(Horde.wake, M.EMERGE),
      ("Keeps between %g and %g px from you, strafing from side to side."):format(M.NEAR, M.FAR),
      "The Baron of Heck's roar and the Spider Mattressmind's murmur bring more.",
    },
    tips = {
      "Its fireballs are slow: watch for the raised arm and step to the side.",
      "Wait at the vent and shoot each one as it crawls out, before it can throw.",
    },
    drops = koins("imp"),
  })

  local C = Cacos
  local sp = Fire.spit
  add({
    kind = "eternal-mood/cacodaemon",
    name = "Cacodaemon",
    quests = { "eternal-mood-earth", "eternal-mood-foundry", "eternal-mood-heck" },
    where = "Heck on Earth, the Foundry and Heck, floating over roofs and lava; the Mancouchbus and the Spider "
      .. "Mattressmind call more",
    about = "A floating red tomato with one green eye and a big mouth: the heaviest thing in the horde. It drifts "
      .. "round you at a distance, flies straight over walls and lava, and spits big balls of fire.",
    stats = {
      { "Health", C.HEALTH },
      { "Speed", C.FLY, "px/s" },
      { "Sight", ("%g px, over everything; once awake it hunts the nearest player within %g px"):format(C.SEES,
        C.HUNTS) },
    },
    weapons = {
      { "Spit", ("%g fire damage, mouth open for %g s first, one every %g to %g s, out to %g px at %g px/s"):format(
        sp.damage, C.OPEN, C.SPIT_EVERY[1], C.SPIT_EVERY[2], C.SPIT_RANGE, sp.speed) },
      { "Bite", ("%g melee damage, one every %g s, when you get within %g px of its edge"):format(C.BITE_DAMAGE,
        C.BITE_EVERY, C.BITE_REACH) },
    },
    abilities = {
      "Wakes when you come near, when it sees you across open ground, or when it is hurt: then its whole flock comes.",
      ("Keeps between %g and %g px from you, circling slowly."):format(C.KEEP[1], C.KEEP[2]),
      "Flies: walls, roofs and lava are nothing to it.",
    },
    tips = {
      ("Shoot it in the open mouth: rounds do %g times the damage, and it reels back for %g s without spitting.")
        :format(C.MOUTHFUL, C.REEL),
      "Its spit is big and slow: a step to the side does it.",
      "Don't stand under it: up close it bites.",
    },
    drops = koins("caco"),
  })
end

function Wiki.wikiEnemies(add)
  possessedPages(add)
  hordePages(add)
end

return Wiki
