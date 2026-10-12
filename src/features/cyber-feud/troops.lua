-- The factions' troops on the street (docs/cyber-feud.md, "The factions'
-- troops" and "Feud AI"): Halcyon's officers and the Static's gangers, on
-- the host, and how they look on every screen. init.lua passes its hooks on
-- to this module.
--
-- Each side is a troop of A-Man's Combine soldiers (a-man/combine.lua, with
-- D-Day's sight cones): guards on the map's posts sweeping a cone of sight,
-- squads walking its beats (city-map's `map.troops`), each hunting whoever
-- it spots, calling it in to the nearest few of its own side, and walking
-- back to its place after. Where the level has a feud (`Troops.levels`),
-- the two sides are each other's `rivals`: a soldier goes for whoever is
-- nearest in his cone, a player or one of the other side. Their rounds
-- carry their side's name (weapons' `from`), so a round passes through its
-- own side and hits the other.
--
-- Guard stations (the map's `stations`; the Market's chop shop has no gun): an MG nest crewed as A-Man's
-- Coast's are (a-man/city17.lua): one on the gun, firing long bursts into
-- its arc only, and riflemen on the station's posts who hold them and fight
-- from cover. Drop the gunner and the nearest of his crew still up runs to
-- the gun and takes over. The station house holds a garrison: once the
-- street is awake, the first time a player comes within its `reach` they
-- come out of the door one after another and go for where that player is.
--
-- They are calm (they see nobody) until someone takes the Shard, or a
-- player hurts one of them, or (where the map has a `wakeY`, the Market)
-- a player walks past that line: then the whole street wakes at once.
--
-- In Halcyon Tower they ignore each other (Troops.levels' false): never
-- each other's rivals, and their rounds pass through both sides; they only
-- want you. Halcyon holds every floor, and the Static break in from below
-- (Troops.breakIn, the map's `breakIns`): a pack at a time, every so often,
-- up the stairwell onto the lowest floor anyone is on (the lobby's doors
-- for the lobby), walking that floor's beat after them, so the floors
-- behind you aren't safe; a sparker with them from the offices up, and a
-- brute (brutes.lua, their own brain) from the servers up.
--
-- On the Overpass the two sides hold fire on each other (Troops.levels'
-- "provoked"), until a round of one hits the other: then they are at it
-- until things calm down (Troops.flare), and call a truce again. Getting
-- them into each other's line of fire is the way to start it.
--
-- On the Overpass Halcyon's interceptors (interceptors.lua) wait on the
-- shoulder to chase, ram and shoot at whoever drives by, and the Static's
-- war-rigs (war_rigs.lua) to ram them, Kilowatt riding the first one past;
-- over the gantries Halcyon's sting drones (stings.lua) wait to strafe them,
-- and on them its marksmen (marksmen.lua) draw a line on them and fire.
--
-- Halcyon's enforcers (enforcers.lua, their own brain) hold the Market's
-- gates behind riot shields (and the tower's guard and executive floors), in the feud with the rest of Halcyon; the
-- Static's rippers (rippers.lua, their own brain) lunge out of the west
-- lanes at whoever is most alone, and its sparkers (sparkers.lua) hang
-- back and lob EMPs; Halcyon's watcher drones (watchers.lua) fly over
-- the stalls and call officers to whoever they see.
--
-- In the Market the Static's general, Volt (volt.lua, his own brain),
-- holds Noodle Square and the dock's pass code; his backup comes in as
-- packs (`serverPack`).
--
-- On the Roof the factions' bosses (kilowatt.lua and saye.lua, each their
-- own brain) wait, on the helipad and by the billboard, for the roof to wake.
--
-- In Halcyon Tower its sentry turrets (turrets.lua) sweep the labs and
-- the security floor; breached, one fights for whoever breached it.
--
-- Halcyon is disciplined: SMGs and pistols, a narrow cone, squads of
-- three. The Static are noise: shotguns and pistols, a wide cone and a
-- keen ear, packs of four. Both talk (Story.troops): idle chatter and a
-- mate's answer, a shout on spotting a player or the other side, a call
-- when one of their own goes down. A car at speed runs them down.
--
-- Messages
--   server -> all  CF_TROOPS <tick> [<id> <side> <x> <y> <facing> <hp> <alert> <gun>]...  (unreliable, 15 Hz;
--                  side h or s; alert 1 has somebody, 2 searching or looking into something, 0 neither)
--   server -> all  CF_DOWN   <id> <x> <y> <angle>      a soldier went down
--   server -> all  CF_SAY    <id> <category> <index>   a soldier says Story.troops[side][category][index]
--   server -> all  CF_WAKE                              the street woke (init.lua's music listens)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Car = require("src.car")
local Combine = require("src.features.a-man.combine")
local Radio = require("src.features.a-man.radio")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Corpses = require("src.features.corpses")
local Story = require("src.features.cyber-feud.story")
local Bosses = require("src.features.bosses")
local Nests = require("src.features.a-man.nests")
local Droids = require("src.features.cyber-feud.droids")
local Enforcers = require("src.features.cyber-feud.enforcers")
local Rippers = require("src.features.cyber-feud.rippers")
local Sparkers = require("src.features.cyber-feud.sparkers")
local Watchers = require("src.features.cyber-feud.watchers")
local Interceptors = require("src.features.cyber-feud.interceptors")
local WarRigs = require("src.features.cyber-feud.war_rigs")
local Stings = require("src.features.cyber-feud.stings")
local Marksmen = require("src.features.cyber-feud.marksmen")
local Turrets = require("src.features.cyber-feud.turrets")
local Brutes = require("src.features.cyber-feud.brutes")
local Kilowatt = require("src.features.cyber-feud.kilowatt")
local Saye = require("src.features.cyber-feud.saye")
local Duo = require("src.features.cyber-feud.duo")
local Vex = require("src.features.cyber-feud.vex")
local Volt = require("src.features.cyber-feud.volt")
local Hud = require("src.features.cyber-feud.hud")

local Troops = {}

local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }

-- Tuning ------------------------------------------------------------------

Troops.SIDES = { "halcyon", "static" }
-- Each side: `code` on the wire, `firstId` its soldiers' ids start at,
-- `health` what each takes (for scale, a Combine soldier 60), `squad` to a
-- beat, `fov` and `alertFov` its cone calm and on edge, `aware` px all round
-- it notices somebody in, `drops` koins each spills, `loadout` what they
-- carry (`weight` how likely, `burst` rounds at the gun's rate then `pause`
-- seconds).
Troops.side = {
  halcyon = {
    code = "h", firstId = 1, health = 60, squad = 3, drops = 3, color = MAGENTA,
    fov = math.rad(60), alertFov = math.rad(100), aware = 170,
    loadout = {
      { gun = "uzi", weight = 3, burst = 5, pause = 1.2 },
      { gun = "pistol", weight = 2, burst = 2, pause = 0.9 },
    },
  },
  static = {
    code = "s", firstId = 5001, health = 50, squad = 4, drops = 3, color = CYAN,
    fov = math.rad(80), alertFov = math.rad(120), aware = 230,
    loadout = {
      { gun = "shotgun", weight = 3, burst = 1, pause = 1.1 },
      { gun = "pistol", weight = 2, burst = 3, pause = 0.8 },
    },
  },
}
-- The maps they hold, and whether the two sides fight each other there.
-- `feud` true: they fight on sight; "provoked": they hold fire on each
-- other until a round of one side hits the other (crossfire, more often than
-- not), then fight for `Troops.flare` seconds after the last such hit and
-- call a truce again. false: never, and their rounds pass through each other.
Troops.levels = {
  drop = { feud = true },
  market = { feud = true },
  overpass = { feud = "provoked" },
  tower = { feud = false },
  roof = { feud = false },
}
-- The Static breaking in to the tower: the first pack `first` seconds after
-- it wakes, then one every `every`, while fewer than `most` of them (and
-- `perHuman` more for each human past the first) are on that floor already.
-- A pack is the Static's squad (four): gangers, but from floor `sparkerFrom`
-- up one of them is a sparker (sparkers.lua), and from `bruteFrom` up one
-- a brute (brutes.lua).
Troops.breakIn = { first = 12, every = 35, most = 8, perHuman = 4, sparkerFrom = 2, bruteFrom = 3 }
Troops.flare = 25
Troops.chatEvery = { 14, 28 } -- seconds between a post's or a squad's idle chatter (min, max)
Troops.replyAfter = { 1.3, 2.1 } -- seconds before a mate answers
Troops.chatGap = 4 -- seconds, map-wide, between one conversation starting and the next
Troops.shoutEvery = 6 -- seconds a soldier keeps quiet after shouting
Troops.callHeard = 800 -- px; his own side this near where one spotted somebody come when he calls it in
Troops.callAnswer = 3 -- how many of them come at most, nearest first
Troops.callEvery = 15 -- seconds before the same soldier calls in again
Troops.downHeard = 700 -- px; his own side this near one who goes down goes to look
Troops.downAnswer = 4 -- of them at most, nearest first
-- A station's MG: rounds at `damage`, `cooldown` apart, in bursts of `burst` then `pause` seconds.
Troops.nestGun = { burst = 14, pause = 1.4, cooldown = 0.08, damage = 12, range = 700 }
Troops.manGunWithin = 15 -- seconds the crewman going to a dead gunner's gun has before he is simply on it
Troops.garrisonFirst = 0.8 -- seconds from a player coming near a station to the first out of its door
Troops.garrisonEvery = 0.7 -- seconds between one coming out and the next

local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)
local SYNC_EVERY = 2 -- server ticks between CF_TROOPS
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STALE = 1 -- seconds without word from the host before what it last sent is dropped

local random = love.math.random

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function city()
  return Features.byName["city-map"]
end

-- Server --------------------------------------------------------------------

local sv = nil -- { sides = { [key] = { troops, groups } }, pending, time, quietUntil, syncIn, feud }

--- A gun out of `loadout`, by weight, and how he uses it.
local function pickArms(loadout)
  local total = 0
  for _, l in ipairs(loadout) do
    total = total + l.weight
  end
  local roll, pick = random() * total, loadout[1]
  for _, l in ipairs(loadout) do
    roll = roll - l.weight
    if roll < 0 then
      pick = l
      break
    end
  end
  local gun = Guns[pick.gun]
  return {
    gun = Tiers.apply(gun, Tiers.DEFAULT), -- they carry common ones
    key = gun.key,
    index = gun.index,
    burst = pick.burst,
    pause = pick.pause,
    reach = gun.speed * (gun.ttl or ROUND_TTL) * 0.85, -- a little short of where its rounds give out
  }
end

--- (x, y), or the nearest spot round it a soldier fits (not in a wreck).
local function clearSpot(x, y)
  local c = city()
  if not c then
    return x, y
  end
  local r = Combine.RADIUS + 2
  local function fits(px, py)
    return not (c:blocksPoint(px, py) or c:blocksPoint(px - r, py) or c:blocksPoint(px + r, py)
      or c:blocksPoint(px, py - r) or c:blocksPoint(px, py + r))
  end
  if fits(x, y) then
    return x, y
  end
  for d = 16, 160, 16 do
    for k = 0, 7 do
      local a = k / 8 * 2 * math.pi
      local px, py = x + math.cos(a) * d, y + math.sin(a) * d
      if fits(px, py) then
        return px, py
      end
    end
  end
  return x, y
end

--- Everyone arrived on map `name` (`map`): each side on its posts and
--- beats, calm while `calm` (nobody has the Shard yet).
function Troops.serverStart(server, map, name, calm)
  Troops.serverStop(server)
  local level = Troops.levels[name]
  if not (level and map.troops) then
    return
  end
  calm = calm or map.wakeY ~= nil
  sv = { sides = {}, pending = {}, time = 0, quietUntil = 0, syncIn = 0, feud = level.feud, wakeY = map.wakeY,
    allied = level.feud == false }
  if map.breakIns and map.floors then
    sv.breakIn = { spots = map.breakIns, floors = map.floors, nextIn = Troops.breakIn.first }
  end
  local T = require("src.features.city-map.layout").TILE
  local bounds = { x = map.x0, y = map.y0, w = map.cols * T, h = map.rows * T }
  local nav = nil
  for _, key in ipairs(Troops.SIDES) do
    local conf, spec = Troops.side[key], map.troops[key]
    local troops = Combine.new({
      hunt = true, fov = conf.fov, alertFov = conf.alertFov, aware = conf.aware, health = conf.health,
      from = key, firstId = conf.firstId, calm = calm,
    })
    if nav then
      troops.nav = nav -- one walking grid for both
    else
      troops:navigate(bounds)
      nav = troops.nav
    end
    local side = { conf = conf, troops = troops, groups = {}, nests = {}, garrisons = {} }
    sv.sides[key] = side
    -- Who chats together: the soldiers at one place, or one squad.
    local at = {}
    for _, p in ipairs(spec and spec.posts or {}) do
      local g = at[p.at]
      if not g then
        g = { kind = "post", members = {}, chatIn = between(Troops.chatEvery) * random() }
        at[p.at] = g
        side.groups[#side.groups + 1] = g
      end
      local x, y = clearSpot(p.x, p.y)
      local s = troops:add("guard", x, y, p.watch)
      s.hold = p.hold
      g.members[#g.members + 1] = s
    end
    for _, route in ipairs(spec and spec.patrols or {}) do
      local squad = troops:addSquad(route, conf.squad)
      side.groups[#side.groups + 1] = { kind = "patrol", members = squad.members, chatIn = between(Troops.chatEvery) }
    end
    for _, s in ipairs(troops.list) do
      s.faction = key -- (`side` is the brain's own: which way he sidesteps)
      troops:arm(s, pickArms(conf.loadout))
    end
    for _, st in ipairs(spec and spec.stations or {}) do
      Troops.addStation(server, side, key, st)
    end
  end
  local shields = Enforcers.serverStart(server, map, calm) -- Halcyon's riot shields in the gates
  local blades = Rippers.serverStart(server, map, nav, calm) -- the Static's rippers in the lanes
  local emps = Sparkers.serverStart(server, map, nav, calm) -- and its sparkers, hanging back
  local eyes = Watchers.serverStart(server, map, calm) -- Halcyon's watcher drones overhead
  local rifles = Marksmen.serverStart(server, map, calm) -- Halcyon's marksmen up on the gantries
  local fists = Brutes.serverStart(server, map, nav, calm) -- and its brutes (the tower's come with the break-ins)
  if emps and not sv.allied then
    emps.rivals = { eyes } -- what an EMP is for (the gangers leave the drones to them)
  end
  --- The two sides at each other's throats (`on`), or holding fire.
  function sv.setWar(on)
    local h, s = sv.sides.halcyon.troops, sv.sides.static.troops
    h.rivals, s.rivals = on and { s, blades, emps } or {}, on and { h, shields, rifles } or {}
    if rifles then
      rifles.rivals = on and { s, blades, emps } or {}
    end
    if shields then
      shields.rivals = on and { s, blades, emps } or {}
    end
    if blades then
      blades.rivals = on and { h, shields } or {}
    end
  end
  if level.feud == true then
    sv.setWar(true)
  elseif level.feud == "provoked" then
    sv.provoked = true -- a truce, until one side's round finds the other
  end
  Droids.serverStart(server, map, nav, calm) -- Halcyon's assassin droids, on the same walking grid
  Interceptors.serverStart(server, map) -- and its patrol cars, on a driven map
  WarRigs.serverStart(server, map) -- the Static's war-rigs, and Kilowatt riding one
  Stings.serverStart(server, map) -- Halcyon's sting drones over the gantries
  Kilowatt.serverStart(server, map, nav, calm) -- the Roof's bosses: Kilowatt on the helipad...
  Saye.serverStart(server, map, nav, calm) -- ...and Saye by the billboard
  Vex.serverStart(server, map) -- and VEX, once they are down
  Volt.serverStart(server, map, nav) -- the Market's general, in Noodle Square
  Turrets.serverStart(server, map, calm, function() -- its sentry turrets; breached, they go for all of these
    return { sv.sides.halcyon.troops, sv.sides.static.troops, shields or { list = {} }, rifles or { list = {} },
      blades or { list = {} }, emps or { list = {} }, fists or { list = {} } }
  end)
end

--- `s` takes the gun of `nest`: its arc, its sight and its rounds.
local function manGun(side, nest, s)
  local n, g = nest.nest, Troops.nestGun
  local ak = Guns.ak47
  s.watch, s.arc, s.fov, s.post = n.angle, n.arc, 2 * n.arc, nil
  s.takesCover, s.cv, s.threat = nil, nil, nil -- the gun has no cover to go to: he stays on it
  s.facing = n.angle
  nest.gunner, nest.coming = s, nil
  local gun = setmetatable({ damage = g.damage, cooldown = g.cooldown }, { __index = Tiers.apply(ak, Tiers.DEFAULT) })
  side.troops:arm(s, { gun = gun, key = ak.key, index = ak.index, burst = g.burst, pause = g.pause, reach = g.range })
end

--- Station `st` for `side` (`key`): the gunner on its nest (if it has
--- one), the crew on its posts, and its garrison waiting in the house.
function Troops.addStation(server, side, key, st)
  local troops, conf = side.troops, side.conf
  local n = st.nest
  local crew = {}
  if n then
    local gunner = troops:add("guard", n.x, n.y, n.angle)
    gunner.hold, gunner.faction = true, key
    crew[1] = gunner
  end
  for _, p in ipairs(st.posts) do
    local x, y = clearSpot(p.x, p.y)
    local s = troops:add("guard", x, y, p.watch)
    s.hold, s.takesCover, s.faction = true, true, key
    troops:arm(s, pickArms(conf.loadout))
    crew[#crew + 1] = s
  end
  if n then
    local nest = { nest = n, crew = crew }
    manGun(side, nest, crew[1])
    side.nests[#side.nests + 1] = nest
  end
  side.groups[#side.groups + 1] = { kind = "post", members = crew, chatIn = between(Troops.chatEvery) * random() }
  local g = st.garrison
  side.garrisons[#side.garrisons + 1] = { g = g, out = false, left = Bosses.count(g.count, server), nextIn = 0 }
end

--- Every nest keeps its gun manned while any of its crew is up: the
--- nearest goes to it, and is on it after `manGunWithin` however he got stuck.
local function stepNests(side, dt)
  for _, nest in ipairs(side.nests) do
    local n = nest.nest
    if nest.gunner and nest.gunner.hp <= 0 then
      nest.gunner = nil
    end
    local c = nest.coming
    if c and c.hp <= 0 then
      nest.coming, c = nil, nil
    end
    if c and c.post then
      nest.comingFor = (nest.comingFor or 0) + dt
      if nest.comingFor > Troops.manGunWithin then
        c.x, c.y, c.post = n.x, n.y, nil -- caught on something all this time: he gets there anyway
      end
    end
    if c and not c.post then
      nest.comingFor = nil
      manGun(side, nest, c) -- he got there
    elseif not nest.gunner and not c then
      local best, bestD2 = nil, math.huge
      for _, s in ipairs(nest.crew) do
        local d2 = dist2(s.x, s.y, n.x, n.y)
        if s.hp > 0 and d2 < bestD2 then
          best, bestD2 = s, d2
        end
      end
      if best then
        nest.coming, best.post = best, { x = n.x, y = n.y }
      end
    end
  end
end

--- The nearest player anyone could see within `reach` of (x, y), as a point.
local function nearestPlayer(server, x, y, reach)
  local best, bestD2 = nil, reach * reach
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = dist2(px, py, x, y)
      if d2 <= bestD2 then
        best, bestD2 = { x = px, y = py }, d2
      end
    end
  end
  return best
end

--- The station houses: once the street is awake, a player near one brings
--- its garrison out of the door, one by one, after where they are.
local function stepGarrisons(server, side, dt)
  if side.troops.calm then
    return
  end
  for _, gs in ipairs(side.garrisons) do
    local g, door = gs.g, gs.g.door
    if not gs.out then
      local who = nearestPlayer(server, g.x, g.y, g.reach)
      if who then
        gs.out, gs.target, gs.nextIn = true, who, Troops.garrisonFirst
      end
    elseif gs.left > 0 then
      gs.nextIn = gs.nextIn - dt
      if gs.nextIn <= 0 then
        gs.left, gs.nextIn = gs.left - 1, Troops.garrisonEvery
        gs.target = nearestPlayer(server, g.x, g.y, g.reach * 1.5) or gs.target
        local s = side.troops:add("guard", door.x + door.nx * 22, door.y + door.ny * 22, math.atan2(door.ny, door.nx))
        s.faction = side.troops.from
        side.troops:arm(s, pickArms(side.conf.loadout))
        local spread = (gs.left % 3 - 1) * 50 -- the first straight at them, the next to either side
        side.troops:sendTo(s, gs.target.x - door.ny * spread, gs.target.y + door.nx * spread)
      end
    end
  end
end

--- Over: nothing left to step or draw.
function Troops.serverStop(server)
  Droids.serverStop(server)
  Interceptors.serverStop(server)
  WarRigs.serverStop(server)
  Enforcers.serverStop(server)
  Rippers.serverStop(server)
  Sparkers.serverStop(server)
  Watchers.serverStop(server)
  Stings.serverStop(server)
  Marksmen.serverStop(server)
  Turrets.serverStop(server)
  Brutes.serverStop(server)
  Kilowatt.serverStop(server)
  Saye.serverStop(server)
  Duo.serverStop()
  Vex.serverStop(server)
  Volt.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("CF_TROOPS", server.tick)) -- an empty list clears every screen
  end
end

--- The street wakes: from now on they see whoever is there (and every
--- screen hears about it, once: CF_WAKE, sent on the next step).
function Troops.serverWake()
  for _, side in pairs(sv and sv.sides or {}) do
    side.troops.calm = false
  end
  if sv then
    sv.awake = true
  end
  Droids.serverWake()
  Enforcers.serverWake()
  Rippers.serverWake()
  Sparkers.serverWake()
  Watchers.serverWake()
  Marksmen.serverWake()
  Turrets.serverWake()
  Brutes.serverWake()
  Kilowatt.serverWake()
  Saye.serverWake()
end

--- Where the sides hold fire on each other (sv.provoked), a round of one
--- side has hit `s` of the other: they are at it, for Troops.flare seconds
--- after the last such hit. `s` shouts about it.
function Troops.flareUp(server, s)
  sv.warUntil = sv.time + Troops.flare
  if not sv.atWar then
    sv.atWar = true
    sv.setWar(true)
    if s.hp > 0 then
      s.quietUntil = sv.time + Troops.shoutEvery
      server:broadcast(Protocol.encode("CF_SAY", s.id, "rival", random(#Story.troops[s.faction].rival)))
    end
  end
end

--- A flare-up that has run its course: they hold fire again, drop each
--- other as targets, and one of each side says so.
local function stepTruce(server)
  if not (sv.atWar and sv.time > sv.warUntil) then
    return
  end
  sv.atWar = false
  sv.setWar(false)
  for _, key in ipairs(Troops.SIDES) do
    local speaker
    for _, s in ipairs(sv.sides[key].troops.list) do
      if type(s.target) == "table" then
        s.target, s.alert = nil, false
      end
      if s.hp > 0 and not s.alert and (not speaker or random() < 0.3) then
        speaker = s
      end
    end
    if speaker then
      local lines = Story.troops[key].truce
      server:broadcast(Protocol.encode("CF_SAY", speaker.id, "truce", random(#lines)))
    end
  end
end

--- Every soldier, to everyone, unreliably.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, key in ipairs(Troops.SIDES) do
    local side = sv.sides[key]
    for _, s in ipairs(side.troops.list) do
      parts[#parts + 1] = s.id
      parts[#parts + 1] = side.conf.code
      parts[#parts + 1] = ("%.0f"):format(s.x)
      parts[#parts + 1] = ("%.0f"):format(s.y)
      parts[#parts + 1] = ("%.2f"):format(s.facing)
      parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
      parts[#parts + 1] = s.alert and 1 or (Combine.wary(s) and 2 or 0)
      parts[#parts + 1] = s.arms and s.arms.index or 0
    end
  end
  local msg = Protocol.encode("CF_TROOPS", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

-- Talk ----------------------------------------------------------------------

local function alive(s)
  return s.hp > 0
end

--- `s` says a line out of `category`, on every screen.
local function say(server, s, category)
  local lines = Story.troops[s.faction][category]
  server:broadcast(Protocol.encode("CF_SAY", s.id, category, random(#lines)))
end

--- `s` says something out of `category` in `after` seconds, if he is still up.
local function later(s, category, after)
  sv.pending[#sv.pending + 1] = { s = s, category = category, t = after }
end

--- Somebody in `members` still up other than `s`, at random.
local function mate(members, s)
  local others = {}
  for _, m in ipairs(members) do
    if m ~= s and alive(m) then
      others[#others + 1] = m
    end
  end
  return others[1] and others[random(#others)] or nil
end

--- The shouts on spotting somebody (calling the nearest few of his side
--- over), and the idle chatter and the replies.
local function talk(server, dt)
  sv.time = sv.time + dt
  for _, side in pairs(sv.sides) do
    for _, s in ipairs(side.troops.list) do
      local fresh = s.alert and not s.wasAlert
      if fresh and (s.quietUntil or 0) <= sv.time then
        s.quietUntil = sv.time + Troops.shoutEvery
        say(server, s, type(s.target) == "table" and "rival" or "alert")
      end
      if fresh and (s.callUntil or 0) <= sv.time and s.aimX then
        s.callUntil = sv.time + Troops.callEvery
        side.troops:alarm(s.aimX, s.aimY, Troops.callHeard, { from = s, most = Troops.callAnswer })
      end
      s.wasAlert = s.alert
    end
    for _, g in ipairs(side.groups) do
      g.chatIn = g.chatIn - dt
      if g.chatIn <= 0 and sv.time < sv.quietUntil then
        g.chatIn = 0.5 + random() * 3 -- somebody else is talking: wait a moment
      elseif g.chatIn <= 0 then
        g.chatIn = between(Troops.chatEvery)
        local busy = false
        for _, m in ipairs(g.members) do
          busy = busy or (alive(m) and m.alert)
        end
        local speaker = mate(g.members, nil)
        if speaker and not busy then
          sv.quietUntil = sv.time + Troops.chatGap
          say(server, speaker, "idle")
          local other = mate(g.members, speaker)
          if other then
            later(other, "reply", between(Troops.replyAfter))
          end
        end
      end
    end
  end
  for i = #sv.pending, 1, -1 do
    local p = sv.pending[i]
    p.t = p.t - dt
    if p.t <= 0 then
      table.remove(sv.pending, i)
      if alive(p.s) then
        say(server, p.s, p.category)
      end
    end
  end
end

--- One of `side` down: those of his side near enough go to look, the
--- nearest calls it in; gibs on every screen, a few koins, maybe a pickup.
local function soldierDown(server, side, s, by, angle, cause)
  server:broadcast(Protocol.encode("CF_DOWN", s.id, ("%.1f"):format(s.x), ("%.1f"):format(s.y),
    ("%.3f"):format(angle or 0)))
  local went = side.troops:alarm(s.x, s.y, Troops.downHeard, { most = Troops.downAnswer })
  local caller = went[1]
  if not caller then
    local bestD2 = Troops.downHeard ^ 2
    for _, m in ipairs(side.troops.list) do
      local d2 = dist2(m.x, m.y, s.x, s.y)
      if d2 < bestD2 then
        caller, bestD2 = m, d2
      end
    end
  end
  if caller and (caller.quietUntil or 0) <= sv.time then
    caller.quietUntil = sv.time + Troops.shoutEvery
    later(caller, "down", 0.5)
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, side.conf.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
end

--- Cars running soldiers down: car-collisions' numbers, the driver's kill,
--- and the street wakes.
local function runOver(server)
  local cc = Features.byName["car-collisions"]
  if not cc then
    return
  end
  for _, car in pairs(server.vehicles) do
    if car.driver and not car.hidden and math.abs(car.speed) >= cc.runOverSpeed then
      for _, side in pairs(sv.sides) do
        local list = side.troops.list
        for i = #list, 1, -1 do
          local s = list[i]
          if Car.hitTest(car, s.x, s.y, Combine.RADIUS) then
            local amount = cc.runOverDamage * (1 + math.min(1, math.abs(car.speed) / car.maxSpeed))
            local travel = car.speed >= 0 and car.angle or car.angle + math.pi
            Troops.serverWake()
            if side.troops:hurt(s, i, amount, travel) then
              soldierDown(server, side, s, car.driver, travel, "impact")
            end
          end
        end
      end
    end
  end
end

--- The lowest of the tower's floors (1 the lobby) a human on foot is on,
--- counting the stairwell up from a floor as part of it; nil for nobody.
local function lowestFloor(server, floors)
  local T = require("src.features.city-map.layout").TILE
  local low = nil
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local _, y = Features.bodyPose(server, p)
      for i, f in ipairs(floors) do
        if y and y >= f.y0 - 2 * T and y < f.y1 and (not low or i < low) then
          low = i
        end
      end
    end
  end
  return low
end

--- The Static breaking in to the tower: a pack up onto the lowest floor
--- anyone is on, every so often once it is awake, walking that floor's
--- beat from the way in. Any of theirs left two floors behind by then are
--- taken off (out of sight, out of the way).
local function stepBreakIn(server, dt)
  local b = sv.breakIn
  if not (b and sv.awake) then
    return
  end
  b.nextIn = b.nextIn - dt
  if b.nextIn > 0 then
    return
  end
  b.nextIn = Troops.breakIn.every
  local floor = lowestFloor(server, b.floors)
  local spot = floor and b.spots[floor]
  if not spot then
    return
  end
  local side = sv.sides.static
  local sparks, fists = Sparkers.server(), Brutes.server()
  local here = 0
  for _, list in ipairs({ side.troops.list, sparks and sparks.brain.list or {}, fists and fists.brain.list or {} }) do
    for i = #list, 1, -1 do
      local s = list[i]
      if s.breakIn and s.breakIn <= floor - 2 then
        s.hp = 0 -- (so nobody counts him to talk)
        table.remove(list, i)
      elseif s.breakIn == floor then
        here = here + 1
      end
    end
  end
  local conf = Troops.breakIn
  local most = conf.most + conf.perHuman * (Bosses.humans(server) - 1)
  local size = math.min(side.conf.squad, most - here)
  if size <= 0 then
    return
  end
  -- Onto the beat at its corner nearest the way in, in file behind the first.
  local beat, first, bestD2 = spot.beat, 1, math.huge
  for k, c in ipairs(beat) do
    local d2 = dist2(c.x, c.y, spot.x, spot.y)
    if d2 < bestD2 then
      first, bestD2 = k, d2
    end
  end
  local start = (first - 2) % #beat + 1
  local heading = math.atan2(beat[first].y - spot.y, beat[first].x - spot.x)
  --- The `n`th of the pack's place in the file behind the first.
  local function inFile(n)
    return clearSpot(spot.x - math.cos(heading) * 30 * (n - 1), spot.y - math.sin(heading) * 30 * (n - 1))
  end
  -- The specialists go at the back of the file, up front the gangers.
  local extras = {}
  if floor >= conf.bruteFrom and fists then
    extras[#extras + 1] = Brutes.serverJoin
  end
  if floor >= conf.sparkerFrom and sparks then
    extras[#extras + 1] = Sparkers.serverJoin
  end
  local gangers = math.max(1, size - #extras)
  local squad = side.troops:addSquad(beat, gangers, start)
  for i, s in ipairs(squad.members) do
    s.x, s.y = inFile(i)
    s.facing, s.breakIn, s.faction = heading, floor, "static"
    side.troops:arm(s, pickArms(side.conf.loadout))
  end
  for k = 1, math.min(#extras, size - gangers) do
    local x, y = inFile(gangers + k)
    local s = extras[k](x, y, beat, start)
    if s then
      s.breakIn, s.facing = floor, heading
    end
  end
  side.groups[#side.groups + 1] = { kind = "patrol", members = squad.members, chatIn = between(Troops.chatEvery) }
  say(server, squad.members[1], "breakIn")
end

--- A pack of side `key`'s coming in at `spot` ({ x, y }) onto `beat` (a
--- loop of { x, y }), `size` of them in file, and a sparker at the back
--- when `sparker` (the Static's), all sent at (tx, ty) first. A boss's
--- backup (volt.lua). Returns the pack's soldiers.
function Troops.serverPack(server, key, spot, beat, size, sparker, tx, ty)
  if not sv then
    return {}
  end
  local side = sv.sides[key]
  local first, bestD2 = 1, math.huge
  for k, c in ipairs(beat) do
    local d2 = dist2(c.x, c.y, spot.x, spot.y)
    if d2 < bestD2 then
      first, bestD2 = k, d2
    end
  end
  local start = (first - 2) % #beat + 1
  local heading = math.atan2(ty - spot.y, tx - spot.x)
  local squad = side.troops:addSquad(beat, size, start)
  for i, s in ipairs(squad.members) do
    s.x, s.y = clearSpot(spot.x - math.cos(heading) * 30 * (i - 1), spot.y - math.sin(heading) * 30 * (i - 1))
    s.facing, s.faction = heading, key
    side.troops:arm(s, pickArms(side.conf.loadout))
    side.troops:sendTo(s, tx, ty)
  end
  if sparker then
    local x, y = clearSpot(spot.x - math.cos(heading) * 30 * size, spot.y - math.sin(heading) * 30 * size)
    Sparkers.serverJoin(x, y, beat, start)
  end
  side.groups[#side.groups + 1] = { kind = "patrol", members = squad.members, chatIn = between(Troops.chatEvery) }
  say(server, squad.members[1], "alert")
  return squad.members
end

--- Anyone past the map's `wakeY` wakes the street.
local function checkWake(server)
  local calm = false
  for _, side in pairs(sv.sides) do
    calm = calm or side.troops.calm
  end
  if not (calm and sv.wakeY) then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local _, y = Features.bodyPose(server, p)
      if y and y < sv.wakeY then
        Troops.serverWake()
        return
      end
    end
  end
end

function Troops.serverStep(server, dt)
  if not sv then
    return
  end
  checkWake(server)
  if sv.awake and not sv.toldAwake then
    sv.toldAwake = true
    server:broadcast(Protocol.encode("CF_WAKE"))
  end
  for _, key in ipairs(Troops.SIDES) do
    local side = sv.sides[key]
    side.troops:update(server, dt)
    stepNests(side, dt)
    stepGarrisons(server, side, dt)
  end
  Droids.serverStep(server, dt)
  Enforcers.serverStep(server, dt)
  Interceptors.serverStep(server)
  WarRigs.serverStep(server, dt)
  Rippers.serverStep(server, dt)
  Sparkers.serverStep(server, dt)
  Watchers.serverStep(server, dt)
  Stings.serverStep(server, dt)
  Marksmen.serverStep(server, dt)
  Turrets.serverStep(server, dt)
  Brutes.serverStep(server, dt)
  Kilowatt.serverStep(server, dt)
  Saye.serverStep(server, dt)
  Duo.serverStep(server, dt) -- the two of them as partners
  Vex.serverStep(server, dt)
  Volt.serverStep(server, dt)
  runOver(server)
  talk(server, dt)
  stepTruce(server)
  stepBreakIn(server, dt)
  sync(server)
end

--- A round through (x, y): the `serverShotAt` convention. A player's hurts
--- either side (and wakes the street); one fired by nobody only when it
--- carries the other side's name (`from`), so a round passes through its
--- own side. It takes off what it carries; a blast, which carries nothing
--- and asks a few times over, 20 a time.
function Troops.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  if not sv or (by == 0 and sv.allied and Troops.side[from] ~= nil) then
    return false -- (in the tower a faction's round passes through everyone of both)
  end
  for _, key in ipairs(Troops.SIDES) do
    local side = sv.sides[key]
    local s, i = side.troops:at(x, y, radius)
    local hits = s and (by ~= 0 or (from ~= nil and from ~= key and Troops.side[from] ~= nil))
    if hits then
      if by ~= 0 then
        Troops.serverWake()
      elseif sv.provoked then
        Troops.flareUp(server, s) -- the other side's round: that's it, then
      end
      if side.troops:hurt(s, i, damage or Combine.SHOT_DAMAGE, angle) then
        soldierDown(server, side, s, by ~= 0 and by or nil, angle, dtype)
      end
      return true
    end
  end
  local hit, byPlayer = Enforcers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  if not hit then
    hit, byPlayer = Rippers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  end
  if not hit then
    hit, byPlayer = Sparkers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  end
  if not hit then
    hit, byPlayer = Watchers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  end
  if not hit then
    hit, byPlayer = Marksmen.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  end
  if not hit then
    hit, byPlayer = Stings.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  end
  if not hit then
    hit, byPlayer = Turrets.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  end
  if not hit then
    hit, byPlayer = Brutes.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  end
  if not hit then
    hit = Kilowatt.serverShotAt(server, x, y, radius, by, angle, damage)
    byPlayer = hit
  end
  if not hit then
    hit = Saye.serverShotAt(server, x, y, radius, by, angle, damage)
    byPlayer = hit
  end
  if not hit then
    hit = Volt.serverShotAt(server, x, y, radius, by, angle, damage)
    byPlayer = hit
  end
  if hit then
    if byPlayer then
      Troops.serverWake()
    end
    return true
  end
  return Droids.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
end

function Troops.serverFreezeArea(x, y, radius, seconds)
  for _, side in pairs(sv and sv.sides or {}) do
    side.troops:freeze(x, y, radius, seconds)
  end
  Droids.serverFreezeArea(x, y, radius, seconds)
  Enforcers.serverFreezeArea(x, y, radius, seconds)
  Rippers.serverFreezeArea(x, y, radius, seconds)
  Sparkers.serverFreezeArea(x, y, radius, seconds)
  Watchers.serverFreezeArea(x, y, radius, seconds)
  Stings.serverFreezeArea(x, y, radius, seconds)
  Marksmen.serverFreezeArea(x, y, radius, seconds)
  Turrets.serverFreezeArea(x, y, radius, seconds)
  Brutes.serverFreezeArea(x, y, radius, seconds)
  Kilowatt.serverFreezeArea(x, y, radius, seconds)
  Saye.serverFreezeArea(x, y, radius, seconds)
  Volt.serverFreezeArea(x, y, radius, seconds)
end

function Troops.serverPanicArea(x, y, radius)
  for _, side in pairs(sv and sv.sides or {}) do
    side.troops:scare(x, y, radius, 0.5)
  end
  Droids.serverPanicArea(x, y, radius)
  Enforcers.serverPanicArea(x, y, radius)
  Rippers.serverPanicArea(x, y, radius)
  Sparkers.serverPanicArea(x, y, radius)
end

--- A guard room opened on Halcyon (`door` { x, y, nx, ny }, a tower door
--- VEX opened): `count` officers out of it one after another, at (x, y),
--- and then at whoever is nearest, as a station's garrison comes out. The
--- street wakes, if it hasn't.
function Troops.serverAmbush(_server, door, x, y, count)
  if not sv then
    return
  end
  Troops.serverWake()
  local side = sv.sides.halcyon
  side.garrisons[#side.garrisons + 1] = {
    g = { x = door.x, y = door.y, reach = 700, door = door }, out = true, target = { x = x, y = y }, left = count,
    nextIn = Troops.garrisonFirst,
  }
end

--- Is the street awake (for a player joining after it woke)?
function Troops.serverAwake()
  return sv ~= nil and sv.awake == true
end

--- For tests.
function Troops.server()
  return sv
end

-- Client --------------------------------------------------------------------

local troops = {} -- id -> { side, x, y, dx, dy, angle, hp, alert, wary, gun, fov, bob, stride, say, sayT, shout }
local lastTick = 0
local heardAt = 0 -- when the last CF_TROOPS came
local time = 0
local SIDE_OF = { h = "halcyon", s = "static" }

-- How they look (src/body.lua's person). Halcyon: grey armour, a white
-- helmet, a magenta visor strip. The Static: dark mismatched clothes, a
-- chrome forearm, cable hair with cyan tips.
local HALCYON = {
  shirt = { 0.50, 0.52, 0.56 }, pants = { 0.26, 0.27, 0.30 }, vest = { 0.66, 0.68, 0.72 },
  shoes = { 0.08, 0.08, 0.09 }, skin = { 0.80, 0.70, 0.62 }, hat = { 0.90, 0.91, 0.94 }, gun = true,
}
local STATIC_SHIRTS = {
  { 0.16, 0.14, 0.18 }, { 0.26, 0.16, 0.14 }, { 0.14, 0.20, 0.18 }, { 0.22, 0.22, 0.24 }, { 0.30, 0.24, 0.12 },
}
local STATIC_SKINS = { { 0.78, 0.62, 0.50 }, { 0.55, 0.40, 0.30 }, { 0.42, 0.30, 0.22 }, { 0.86, 0.72, 0.62 } }
local HELD = { pistol = 4, uzi = 8, shotgun = 14, ak47 = 15 } -- how far each gun's barrel reaches in his hands
local looks = {} -- side .. gun index .. id variant -> look

local function lookFor(s)
  local variant = s.side == "static" and s.id % (#STATIC_SHIRTS * #STATIC_SKINS) or 0
  local k = s.side .. ":" .. (s.gun or 0) .. ":" .. variant
  local look = looks[k]
  if not look then
    look = {}
    if s.side == "halcyon" then
      for f, v in pairs(HALCYON) do
        look[f] = v
      end
    else
      look.shirt = STATIC_SHIRTS[variant % #STATIC_SHIRTS + 1]
      look.skin = STATIC_SKINS[math.floor(variant / #STATIC_SHIRTS) % #STATIC_SKINS + 1]
      look.pants, look.hair, look.shoes = { 0.12, 0.12, 0.14 }, { 0.07, 0.07, 0.09 }, { 0.05, 0.05, 0.06 }
      look.gun = true
    end
    local gun = s.gun and Guns.list[s.gun]
    look.gunLength = gun and HELD[gun.key] or 10
    looks[k] = look
  end
  return look
end

function Troops.clear()
  troops, lastTick = {}, 0
  Corpses.clear()
  Droids.clear()
  Enforcers.clear()
  Rippers.clear()
  Sparkers.clear()
  Watchers.clear()
  Stings.clear()
  Marksmen.clear()
  Turrets.clear()
  Brutes.clear()
  Kilowatt.clear()
  Saye.clear()
  Vex.clear()
  Volt.clear()
end

--- The map's nests (cyber_feud.lua), as drawn.
local function mapNests()
  local c = city()
  return c and c.map and c.map.nests
end

--- The arc of the nest's gun soldier `s` (as drawn) stands at, or nil.
local function gunnersArc(s)
  for _, b in ipairs(mapNests() or {}) do
    local n = b.nest
    if dist2(s.dx, s.dy, n.x, n.y) < 16 * 16 then
      return n.arc
    end
  end
  return nil
end

function Troops.update(dt)
  time = time + dt
  Droids.update(dt)
  Enforcers.update(dt)
  Rippers.update(dt)
  Sparkers.update(dt)
  Watchers.update(dt)
  Stings.update(dt)
  Marksmen.update(dt)
  Kilowatt.update(dt)
  Saye.update(dt)
  Volt.update(dt)
  if next(troops) and love.timer.getTime() - heardAt > STALE then
    troops = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(troops) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
      s.stride = s.stride + math.sqrt(ex * ex + ey * ey) * k -- how far he has walked, for his legs
    end
    -- His cone opens out while he is on edge; on a nest's gun it is as wide as the gun turns.
    local conf = Troops.side[s.side]
    local arc = gunnersArc(s)
    local fov = arc and 2 * arc or (s.wary and conf.alertFov or conf.fov)
    s.fov = s.fov + (fov - s.fov) * math.min(1, dt * 4)
    if s.say then
      s.sayT = s.sayT - dt
      if s.sayT <= 0 then
        s.say = nil
      end
    end
  end
end

--- Their cones of sight, on the ground under everything, in their side's
--- colour (unless the sight-cones toggle hides them).
function Troops.drawBelowCars()
  Droids.drawBelowCars()
  Enforcers.drawBelowCars()
  Rippers.drawBelowCars()
  Sparkers.drawBelowCars()
  Watchers.drawBelowCars()
  Stings.drawBelowCars()
  Turrets.drawBelowCars()
  Brutes.drawBelowCars()
  Vex.drawBelowCars() -- (her face first, under everything)
  Kilowatt.drawBelowCars()
  Volt.drawBelowCars()
  if Features.any("hideSightCones") then
    return
  end
  for id, s in pairs(troops) do
    local opts = { seed = id, color = Troops.side[s.side].color }
    Sight.draw(s.dx, s.dy, s.angle, Combine.RANGE, s.alert, time, s.fov, opts)
  end
end

--- One soldier: the core's person in his side's gear, its mark on him (the
--- visor strip, the cable tips and chrome arm), a "!" over him when he has
--- somebody, and a bar under him once he is hurt.
local function drawSoldier(s)
  local x, y, r = s.dx, s.dy, Body.SHOULDERS
  local conf = Troops.side[s.side]
  local color = conf.color
  Body.person(x, y, s.angle, math.sin(s.stride * 0.18) * 1.2, lookFor(s))
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(s.angle)
  if s.side == "halcyon" then
    love.graphics.setColor(color[1], color[2], color[3], s.alert and 1 or 0.85)
    love.graphics.setLineWidth(1.6)
    love.graphics.line(3.6, -2.4, 3.6, 2.4)
  else
    love.graphics.setColor(0.72, 0.76, 0.80)
    love.graphics.ellipse("fill", 4.5, 2.2, 3, 1.4, 8) -- the chrome forearm
    love.graphics.setColor(color)
    for _, c in ipairs({ { -3.4, -2.2 }, { -4.3, 0 }, { -3.4, 2.2 } }) do
      love.graphics.circle("fill", c[1], c[2], 0.9, 6)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(color)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < conf.health then
    local bw, f = 20, math.max(0, s.hp / conf.health)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

function Troops.drawAboveCars()
  for _, s in pairs(troops) do
    drawSoldier(s)
  end
  if mapNests() then
    Nests.draw(city().map, troops)
  end
  Droids.drawAboveCars()
  Enforcers.drawAboveCars()
  Rippers.drawAboveCars()
  Sparkers.drawAboveCars()
  Watchers.drawAboveCars()
  Stings.drawAboveCars()
  Marksmen.drawAboveCars()
  Turrets.drawAboveCars()
  Brutes.drawAboveCars()
  Kilowatt.drawAboveCars()
  Saye.drawAboveCars()
  Vex.drawAboveCars()
  Volt.drawAboveCars()
  for _, s in pairs(troops) do -- what they say, over all of them
    if s.say then
      local lift = s.alert and 34 or 8
      Hud.drawBubble(s.dx, s.dy - Body.SHOULDERS - lift, s.say, math.min(1, s.sayT * 2), Troops.side[s.side].color)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- At night (the night feature), each one's mark glows a little in his side's colour.
function Troops.drawNightLights(glow)
  for _, s in pairs(troops) do
    glow(s.dx, s.dy, 46, Troops.side[s.side].color, s.alert and 0.7 or 0.45)
  end
  Droids.drawNightLights(glow)
  Enforcers.drawNightLights(glow)
  Rippers.drawNightLights(glow)
  Sparkers.drawNightLights(glow)
  Watchers.drawNightLights(glow)
  Stings.drawNightLights(glow)
  Marksmen.drawNightLights(glow)
  Turrets.drawNightLights(glow)
  Brutes.drawNightLights(glow)
  Kilowatt.drawNightLights(glow)
  Saye.drawNightLights(glow)
  Vex.drawNightLights(glow)
  Volt.drawNightLights(glow)
end

--- The footsteps feature's walkers.
function Troops.walkers()
  local list = {}
  for id, s in pairs(troops) do
    list[#list + 1] = { key = "cf" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  for _, w in ipairs(Droids.walkers()) do
    list[#list + 1] = w
  end
  for _, w in ipairs(Enforcers.walkers()) do
    list[#list + 1] = w
  end
  for _, w in ipairs(Rippers.walkers()) do
    list[#list + 1] = w
  end
  for _, w in ipairs(Sparkers.walkers()) do
    list[#list + 1] = w
  end
  for _, w in ipairs(Brutes.walkers()) do
    list[#list + 1] = w
  end
  return list
end

Troops.clientMessages = {
  CF_TROOPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, side = tonumber(args[i]), SIDE_OF[args[i + 1]]
      local x, y = tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and side and x and y then
        local s = troops[id]
        if not s then
          s = { id = id, side = side, dx = x, dy = y, bob = love.math.random() * 6, stride = 0 }
          s.fov = Troops.side[side].fov
          troops[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 4]) or s.angle or 0
        s.hp = tonumber(args[i + 5]) or Troops.side[side].health
        s.alert = args[i + 6] == "1"
        s.wary = args[i + 6] ~= "0"
        s.gun = tonumber(args[i + 7])
        seen[id] = true
      end
    end
    for id in pairs(troops) do
      if not seen[id] then
        troops[id] = nil
      end
    end
  end,
  CF_SAY = function(_client, args)
    local s = troops[tonumber(args[1])]
    local lines = s and Story.troops[s.side][args[2]]
    local text = lines and lines[tonumber(args[3])]
    if text then
      s.say, s.sayT = text, Radio.sayTime(text)
      s.shout = args[2] == "alert" or args[2] == "rival" or args[2] == "down"
      Radio.play(text, s.x, s.y, s.shout)
    end
  end,
  CF_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and troops[id]
    if id then
      troops[id] = nil
    end
    if s and x and y then
      -- His body, where he was drawn, knocked over the way the round went.
      Corpses.add(s.dx, s.dy, angle, lookFor(s))
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
      end
    end
  end,
}
for kind, handler in pairs(Droids.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Enforcers.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Rippers.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Sparkers.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Watchers.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Stings.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Marksmen.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Turrets.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Brutes.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Kilowatt.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Saye.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Vex.clientMessages) do
  Troops.clientMessages[kind] = handler
end
for kind, handler in pairs(Volt.clientMessages) do
  Troops.clientMessages[kind] = handler
end

return Troops
