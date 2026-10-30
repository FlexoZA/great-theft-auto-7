-- The wiki's pages on Hyperbole's army (tools/wiki, docs/wiki.md): one a
-- model, its numbers read off its brain. Wilbur's page is wilbur.lua's.

local Army = require("src.features.borderline.army")
local Chassis = require("src.features.borderline.chassis")
local Brains = Army.BRAINS
local Junk, Gun, Rpg, Plz, Jet = Brains.JNK, Brains.GUN, Brains.RPG, Brains.PLZ, Brains.JET
local Exp, Dzr, Arc, Drone, Sentry = Brains.EXP, Brains.DZR, Brains.ARC, Brains.FIX, Brains.SEN
local Dock, Bad, Stk, Can = Brains.DCK, Brains.BAD, Brains.STK, Brains.CAN
local Heal = require("src.features.bosses.heal")

local Wiki = {}

local function range(r)
  return ("%g to %g"):format(r[1], r[2])
end

local function sight(conf)
  return ("%g px, a %g degree cone, and it hears anyone within %g px"):format(conf.range, math.deg(conf.fov),
    conf.aware)
end

local function drops(code)
  local chance = Army.pickupChance[code]
  return ("%g koins, %s"):format(Army.drops[code], chance and "maybe a pickup" or "and a pickup")
end

local function bursts(conf, what)
  return ("bursts of %d, %g s apart, %s s between bursts; %s"):format(conf.burst, conf.every, range(conf.pause), what)
end

local CRAWL = ("A killing hit takes its legs instead, one time in %g: it drags itself on at half speed, still "
  .. "shooting, for %g s, and a hit finishes it."):format(1 / Chassis.CRAWL_CHANCE, Chassis.CRAWL_FOR)
local CALLS = ("Seeing somebody, it calls the army within %g px to come and look."):format(Army.CALL)

local function junk(add)
  local C = Junk.CONF
  add({
    kind = "borderline/jnk",
    name = "Junk hauler",
    quests = { "borderline", "borderline-landing", "borderline-pit" },
    where = "In packs on the Frozen Wreck, Liar's Landing and the Bragium Pit, picking over whatever is lying about; "
      .. "a hauler dock builds more",
    about = "The cheapest thing Hyperbole ever built, and it knows it: a rusty frame with a pistol. It walks straight "
      .. "at you with no cover and no plan.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s picking about, %g after you"):format(C.mill, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Pistol", bursts(C, ("%g bullet damage a shot"):format(Junk.gun().damage)) },
    },
    abilities = {
      "The first of a pack to see you wakes the rest of it.",
      ("Walks in to %g px and stands there shooting."):format(C.close),
      ("Loses you and goes to where you were, looks about for %g s, and settles there."):format(C.search),
      CRAWL,
    },
    tips = {
      "Packs bunch up: one grenade or rocket does a lot of them.",
      "They don't take cover: stand back and pick them off.",
    },
    drops = drops("JNK"),
  })
end

local function gun(add)
  local C = Gun.CONF
  add({
    kind = "borderline/gun",
    name = "Gun hauler",
    quests = { "borderline", "borderline-landing", "borderline-pit", "borderline-prosperity",
      "borderline-refinery", "borderline-assembly", "borderline-cuts" },
    where = "Everywhere on the line: standing watch, or walking a beat in squads",
    about = "Hyperbole's standard model: a rifle on one arm and a grenade launcher on the other, and drilled.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Rifle", bursts(C, ("%g bullet damage a shot"):format(Gun.gun().damage)) },
      { "Grenade launcher", ("a grenade every %s s, at anyone %s px off, and one where it lost you: a red ring "
        .. "marks where it will land, and the hauler stands still %g s before it lobs")
        :format(range(C.grenadeEvery), range(C.grenadeRange), Gun.LOB_WARN) },
    },
    abilities = {
      ("Keeps its distance: closes in past %g px, backs off inside %g, side-stepping as it shoots.")
        :format(C.far, C.near),
      CALLS,
      "Shot by somebody it can't see, it turns and goes to look.",
      CRAWL,
    },
    tips = {
      "When a red ring shows up under you and it stops shooting, get out of the ring: a grenade is coming.",
      "Squads flank in pairs: keep a wall at your back.",
    },
    drops = drops("GUN"),
  })
end

local function stalker(add)
  local C = Stk.CONF
  local SC, SB = Stk.CHARGE, Stk.BREATH
  add({
    kind = "borderline/stk",
    name = "Stalker hauler",
    quests = { "borderline-landing" },
    where = "Liar's Landing: a pair hunting the container stacks, and one in the last wave at the ferry lift",
    about = "Hyperbole's hunter: tall and quick, two long legs in front and a wheel behind, a flechette pod on each "
      .. "shoulder. It dodges what you shoot at it.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Flechettes", bursts(C, ("each sticks in you for %g bullet damage, then blows a second later: %g within "
        .. "%g px"):format(Stk.DART.sting, Stk.DART.damage, Stk.DART.radius)) },
      { "Charge", ("now and then at somebody %s px off: it crouches for %g s, its pods and eye glowing, then runs "
        .. "straight at where they stood for %g impact damage"):format(range(SC.range), SC.windUp, SC.damage) },
    },
    abilities = {
      "Once it knows you are about, it throws itself aside from a round about to hit it. A shot from hiding lands.",
      ("Each dodge and charge costs breath, shown under it; a few in a row and it is winded: walking, no dodge or "
        .. "charge until it has %g breath back."):format(SB.recovered),
      ("Under %g%% health it backs off to a medkit within %g px, for %g health."):format(Heal.below * 100,
        Heal.range, Heal.amount),
      CRAWL,
    },
    tips = {
      "Open up on it before it sees you: those shots can't be dodged.",
      "Make it dodge until it is winded (its breath goes red), then unload.",
      "Step aside when it crouches: it can't turn once it runs.",
      "Pick up the medkits near it first.",
    },
    drops = drops("STK"),
  })
end

local function rocket(add)
  local C = Rpg.CONF
  local launcher = Rpg.gun()
  add({
    kind = "borderline/rpg",
    name = "Rocket hauler",
    quests = { "borderline-landing", "borderline-prosperity", "borderline-assembly", "borderline-cuts" },
    where = "Standing watch from far back: under Liar's Landing's gantries, then Prosperity, the Assembly Line and "
      .. "Thousand Papercuts",
    about = "A heavier hauler with a launcher on one arm and two pods of rockets on its back. It hangs back and "
      .. "makes you move.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Launcher", ("one slow rocket every %s s, %g px/s, %g explosive damage within %g px"):format(range(C.pause),
        launcher.speed, launcher.blast.damage, launcher.blast.radius) },
      { "Pods", ("every %s s its pods glow for %g s, then %d rockets come down on red rings round you, %g explosive "
        .. "damage each within %g px"):format(range(C.volleyEvery), C.windUp, C.volley, C.volleyDamage,
        C.volleyRadius) },
    },
    abilities = {
      ("Keeps well back: closes in past %g px, backs off inside %g."):format(C.far, C.near),
      CALLS,
      CRAWL,
    },
    tips = {
      "When its pods glow, keep moving: one rocket always lands right where you stand.",
      "Its own rockets are slow enough to sidestep.",
    },
    drops = drops("RPG"),
  })
end

local function drones(add)
  for _, d in ipairs({
    { code = "FIX", name = "Medic drone", quests = { "borderline-landing", "borderline-prosperity",
      "borderline-refinery", "borderline-assembly" },
      where = "Hanging behind the haulers: Liar's Landing (and its lift's waves), Prosperity, the Refinery and the "
        .. "Assembly Line",
      about = "A small yellow disc on four rotors with a red cross. It never fights: it heals the most hurt hauler "
        .. "near it.",
      does = ("Heals the hauler it tends by %g a second along its beam, %g px long."):format(Drone.HEAL, Drone.BEAM) },
    { code = "SHD", name = "Shield drone", quests = { "borderline-pit", "borderline-prosperity",
      "borderline-refinery", "borderline-assembly", "borderline-cuts" },
      where = "Hanging behind the haulers: the Bragium Pit, Prosperity, the Refinery, the Assembly Line and Thousand "
        .. "Papercuts",
      about = "A small yellow disc on four rotors. It never fights: it puts a bubble on a hauler, one in a fight "
        .. "first.",
      does = ("Gives the hauler it tends a %g point bubble that soaks hits first, topped up %g a second along its "
        .. "beam (%g px long); untended, a bubble fades %g a second."):format(Drone.SHIELD, Drone.TOP_UP,
        Drone.BEAM, Drone.FADE) },
  }) do
    add({
      kind = "borderline/" .. d.code:lower(),
      name = d.name,
      quests = d.quests,
      where = d.where,
      about = d.about,
      stats = {
        { "Health", Drone.CONF.health },
        { "Speed", Drone.CONF.speed, "px/s" },
      },
      abilities = {
        d.does,
        ("Looks for somebody to tend within %g px, and hangs %g px behind them, out of your line of fire.")
          :format(Drone.SEEK, Drone.BEHIND),
        "Flies over walls, and anything can shoot it.",
      },
      tips = {
        "Shoot it first: it goes down fast, and what it tends goes down slow until it does.",
        "Get round the side of whoever it tends to get a clear shot.",
      },
      drops = drops(d.code),
    })
  end
end

local function plasma(add)
  local C = Plz.CONF
  add({
    kind = "borderline/plz",
    name = "Plasma hauler",
    quests = { "borderline-pit", "borderline-prosperity", "borderline-refinery", "borderline-assembly" },
    where = "Standing watch on the Bragium Pit's rings, then Prosperity, the Refinery and the Assembly Line",
    about = "A cannon on its arm with purple coils down it, and a tank of Bragium on its back to feed it.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Plasma cannon", ("its coils glow for %g s, then one slow bolt, %g px/s, every %s s: %g plasma damage, "
        .. "splashing %g px; plasma melts armor"):format(C.aim, Plz.BOLT.speed, range(C.pause), Plz.BOLT.damage,
        Plz.BOLT.splash) },
    },
    abilities = {
      ("Its tank is its weak spot: killed by a hit from behind, it bursts, %g plasma damage within %g px, its own "
        .. "side included."):format(Plz.BURST.damage, Plz.BURST.radius),
      CALLS,
      CRAWL,
    },
    tips = {
      "A sprint sidesteps the bolt: move when the coils glow.",
      "Finish it from behind when it stands among its friends.",
    },
    drops = drops("PLZ"),
  })
end

local function kamikaze(add)
  local C = Exp.CONF
  add({
    kind = "borderline/exp",
    name = "Kamikaze hauler",
    quests = { "borderline-prosperity", "borderline-refinery", "borderline-assembly", "borderline-cuts" },
    where = "In packs of three from Prosperity on",
    about = "Stripped to the frame, no arms, a red core in its chest. It runs at you and goes off.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s at you"):format(C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Core", ("goes off within %g px of you: %g explosive damage within %g px"):format(Exp.REACH, Exp.BLAST.damage,
        Exp.BLAST.radius) },
    },
    abilities = {
      ("Its core blinks faster from %g px off."):format(Exp.WARN),
      "Killed, it goes off all the same where it fell, and that blast hurts its own side too.",
      "It has no legs to lose: no crawl, it just blows.",
    },
    tips = {
      "Shoot it while it is still among its friends.",
      "A sprint only just keeps ahead of it: shoot, don't run.",
    },
    drops = drops("EXP"),
  })
end

local function jet(add)
  local C = Jet.CONF
  add({
    kind = "borderline/jet",
    name = "Jet hauler",
    quests = { "borderline-prosperity", "borderline-cuts" },
    where = "Standing watch in Prosperity and Thousand Papercuts",
    about = "A rifle hauler with wings folded on its back and thrusters under them. Every so often it takes off "
      .. "and bombs a line straight over you.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight, %g in the air"):format(C.walk, C.speed, C.flySpeed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Rifle", bursts(C, ("%g bullet damage a shot"):format(Jet.gun().damage)) },
      { "Bombing run", ("every %s s it crouches for %g s as its thrusters light, then flies over you and %g px "
        .. "past; %d rockets come down along its line on red rings, %g explosive damage each within %g px")
        :format(range(C.runEvery), C.takeOff, C.runPast, C.marks, C.markDamage, C.markRadius) },
    },
    abilities = {
      "In the air nothing reaches it, and it flies over walls.",
      ("Lands where there is room and stands %g s before it fights on."):format(C.landFor),
      CRAWL,
    },
    tips = {
      "When its thrusters light, step off the line between you and it: the rockets fall along it.",
      "Shoot it as it lands.",
    },
    drops = drops("JET"),
  })
end

local function dozer(add)
  local C = Dzr.CONF
  local DC, DS = Dzr.CHARGE, Dzr.SHOVE
  add({
    kind = "borderline/dzr",
    name = "Dozer hauler",
    quests = { "borderline-prosperity", "borderline-refinery", "borderline-assembly" },
    where = "Standing watch in Prosperity, the Refinery and the Assembly Line",
    about = "Wide, slow and tough, a bulldozer blade across its front.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g at you, %g charging"):format(C.walk, C.speed, DC.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Shove", ("up close, %g impact damage every %g s, knocked down"):format(DS.damage, DS.every) },
      { "Charge", ("every %s s it folds into a dozer for %g s, then charges straight where you stood: %g impact "
        .. "damage, flattened"):format(range(DC.every), DC.windUp, DC.damage) },
    },
    abilities = {
      ("Its blade stops every round from the front, %g degrees either side; blasts and fire go round it.")
        :format(math.deg(Dzr.SHIELD)),
      "It can't turn once it charges.",
      CRAWL,
    },
    tips = {
      "Flank it, or blow it up.",
      "Step aside when it folds down, and shoot its back as it goes by.",
    },
    drops = drops("DZR"),
  })
end

local function badass(add)
  local C = Bad.CONF
  local shell = Bad.gun()
  add({
    kind = "borderline/bad",
    name = "Badass hauler",
    quests = { "borderline-prosperity", "borderline-refinery", "borderline-assembly", "borderline-cuts" },
    where = "One a level from Prosperity on, with drones tending it",
    about = "The elite: big, black and yellow, horns either side of its eye, a war cannon on each arm and rocket "
      .. "pods on its back. It doesn't mind you close.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "War cannons", bursts(C, ("shells, %g explosive damage within %g px"):format(shell.blast.damage,
        shell.blast.radius)) },
      { "Pods", ("every %s s its pods glow for %g s, then %d rockets come down on red rings round you, %g explosive "
        .. "damage each within %g px"):format(range(C.volleyEvery), C.windUp, C.volley, C.volleyDamage,
        C.volleyRadius) },
      { "Stomp", ("within %g px it rears up for %g s and stamps: %g impact damage to everyone round it, knocked "
        .. "down; at most every %g s"):format(Bad.STOMP.reach * 0.8, Bad.STOMP.windUp, Bad.STOMP.damage,
        Bad.STOMP.every) },
    },
    abilities = {
      ("Keeps its distance, but short: closes in past %g px, backs off inside %g."):format(C.far, C.near),
      CALLS,
      CRAWL,
    },
    tips = {
      "Down its drones first.",
      ("Back off past %g px when it rears up."):format(Bad.STOMP.reach),
      "Keep moving when its pods glow.",
    },
    drops = drops("BAD"),
  })
end

local function arc(add)
  local C = Arc.CONF
  local bolt, D = Arc.gun(), Arc.DOME
  add({
    kind = "borderline/arc",
    name = "Arc hauler",
    quests = { "borderline-refinery", "borderline-cuts" },
    where = "Standing watch in the Refinery's tunnels and in Thousand Papercuts",
    about = "Blue coils on both arms and a dish on its back that throws a dome over it and its friends.",
    stats = {
      { "Health", C.health },
      { "Speed", ("%g px/s on its beat, %g in a fight"):format(C.walk, C.speed) },
      { "Sight", sight(C) },
    },
    weapons = {
      { "Shock bolts", bursts(C, ("one from each arm, %g shock damage, and %g a second for %g s after"):format(
        bolt.damage, bolt.electrify.dps, bolt.electrify.seconds)) },
    },
    abilities = {
      ("Every %s s in a fight its dish throws a dome %g px round it for %g s: rounds from outside stop at it, and "
        .. "anyone inside takes %g shock damage a second."):format(range(D.every), D.radius, D.time, D.zap),
      ("Keeps its distance, closer than most: closes in past %g px, backs off inside %g."):format(C.far, C.near),
      CALLS,
      CRAWL,
    },
    tips = {
      "Wait the dome out, or walk in and shoot from inside it.",
      "From inside the dome your shots hit everything under it, blasts too; from outside nothing does.",
    },
    drops = drops("ARC"),
  })
end

local function sentry(add)
  local C = Sentry.CONF
  add({
    kind = "borderline/sen",
    name = "Sentry",
    quests = { "borderline-assembly", "borderline-cuts" },
    where = "Flush in the floor of the Assembly Line and in Thousand Papercuts' rock",
    about = "A yellow turret in a hatch, out of reach until it comes up.",
    stats = {
      { "Health", C.health },
      { "Sight", ("%g px, all the way round"):format(C.range) },
    },
    weapons = {
      { "Turret gun", bursts(C, ("%g bullet damage a shot"):format(Sentry.gun().damage)) },
    },
    abilities = {
      ("Comes up in %g s when anyone is within %g px, and sinks back %g s after it last saw anyone."):format(
        Sentry.RISE, Sentry.WAKE, Sentry.SINK_AFTER),
      "Sunk, nothing reaches it. It never moves.",
    },
    tips = {
      "Get behind cover as it rises, then shoot between its bursts.",
    },
    drops = drops("SEN"),
  })
end

local function dock(add)
  local C = Dock.CONF
  add({
    kind = "borderline/dck",
    name = "Hauler dock",
    quests = { "borderline" },
    where = "The Frozen Wreck: a charging bay at each post, guarding a terminal that opens the tunnel's blast door",
    about = "The bay Hyperbole parks its haulers in, with a plasma gun on a turret over it.",
    stats = {
      { "Health", C.health },
      { "Sight", ("%g px, all the way round"):format(C.range) },
    },
    weapons = {
      { "Plasma turret", bursts(C, ("bolts at %g px/s, %g plasma damage, splashing %g px"):format(Dock.BOLT.speed,
        Dock.BOLT.damage, Dock.BOLT.splash)) },
    },
    abilities = {
      ("With anyone within %g px it builds a junk hauler every %g s and sends it out, %d of its own out at most.")
        :format(Dock.WAKE, Dock.BUILD_EVERY, Dock.CAP),
      "Hacking its terminal shuts it down. It never moves.",
    },
    tips = {
      "Hack the terminal beside it rather than shooting it down.",
      "Sidestep its bolts: they are slow.",
    },
    drops = drops("DCK"),
  })
end

local function cannon(add)
  local C, S = Can.CONF, Can.SHELL
  add({
    kind = "borderline/can",
    name = "Rim cannon",
    quests = { "borderline-bunker" },
    where = "The Bunker: eleven round the rim of its roof; the way on stays shut until every one is down",
    about = "A heavy twin-barrelled gun on a turret, bolted to the Bunker's rim.",
    stats = {
      { "Health", C.health },
      { "Reach", ("%g px, all the way round, over anything in the way"):format(C.range) },
    },
    weapons = {
      { "Shell", ("lobbed at the nearest player every %s s, landing %g s later on a red ring within %g px of "
        .. "where they stood: %g explosive damage, %g px blast"):format(range(C.pause), S.delay, S.scatter,
        S.damage, S.radius) },
    },
    abilities = {
      ("Its muzzle glows for %g s before a shell goes. It turns slowly and never moves."):format(C.aim),
    },
    tips = {
      "Watch for the red rings and keep moving: standing still is how a shell finds you.",
      "Work round the rim: the further one is, the longer you have to step out of its ring.",
    },
    drops = drops("CAN"),
  })
end

local PAGES = { junk, gun, stalker, rocket, drones, plasma, kamikaze, jet, dozer, badass, arc, sentry, dock, cannon }

--- Every model's page, in the order you meet them.
function Wiki.wikiEnemies(add)
  for _, page in ipairs(PAGES) do
    page(add)
  end
end

return Wiki
