-- City 17, the first level of A-Man's quest (the map is city-map's
-- `city17`). Combine soldiers guard every checkpoint on the way up, two to
-- a post (`Level.guardsPerPost`): the station's concourse, the mouth of the
-- avenue on the plaza, the gate in the wall, the far end of each bridge and
-- the Citadel's doors (the map's `posts`). They are the D-Day landing's guards on other uniforms
-- (their brain, combine.lua, and d-day/sight.lua): each stands at his post sweeping
-- a narrow cone of sight, turns to follow whoever walks into it and opens
-- fire. Cover breaks his sight. He takes what each round carries, out of
-- 60 (`Level.health`): three pistol rounds, a sniper round. Each carries
-- one of the guns, picked by `Level.loadout`'s weights (every gun in
-- weapons/guns.lua can turn up; one missing from the list is as likely as
-- the pistol), fired in bursts once you are in its reach.
-- They hunt (combine.lua's `hunt`): one who spots somebody closes in on them,
-- and goes to where he saw them last when he loses them, his squad with
-- him; shot from somewhere none of them can see, they go to ground and
-- send out a sweep once it goes quiet (combine.lua's sieges). One who
-- spots somebody calls it in, and the nearest few others within reach of
-- the radio (not his squad, who are with him) come to where he saw them.
-- When a soldier goes down, everyone near enough to hear it goes to see. Each
-- walks back to his post or his beat after.
-- Squads of three walk beats between them, two squads to a beat spread
-- round it (`Level.squadsPerBeat`; the map's `patrols`): through the old
-- town, round the plaza and the Citadel's square. They talk over
-- the radio (radio.lua): guards at a checkpoint and squads on their beat
-- now and then, a mate answering; whoever spots somebody shouts it, and
-- one near a soldier who goes down calls it in, those going to look say
-- so, and one who found nothing says that on his way back.
-- The first time a player walks into the plaza, A-Man drops by: he blinks
-- in, leaves a horde of his turrets and blinks out, three times over
-- (cameo.lua). He can't be hurt here: the fight with him is at the top of
-- the Citadel (finale.lua).
-- Three Hunters (the hunters feature) patrol a ring round the Citadel.
-- The first player to reach the Citadel's doors finishes the level
-- (quests' `serverComplete`): a star comes up there.
--
-- The same soldiers hold the Outer City (city-map's `outercity`, quests'
-- "a-man-2"): guards on its posts at the choke points on the way in and a
-- squad on each of its beats (`Level.maps` says what each map has: the
-- plaza visits, the Hunters and the Citadel's doors are City 17's alone).
-- Some guard stations have a garrison (the map's `garrisons`): nobody is
-- inside until it is needed, and the first time a player comes within the
-- garrison's `reach` its door opens on every screen (C17_DOOR) and
-- `garrison` soldiers (more with more humans: Bosses.count) come out of it
-- one after another and go for where that player is; when they have
-- looked round they walk back and stand guard at the door.
--
-- The Coast (city-map's `coast`, quests' "a-man-coast") has three bunkers
-- (the map's `bunkers`), each with an MG nest in front of it and a crew of
-- `Level.nestCrew`: one on the gun and the rest on the bunker's posts with
-- their rifles. They defend (combine.lua's `hold`): they never leave their
-- places to chase or answer a call. The riflemen fight from cover
-- (`takesCover`): into cover near their post, out to shoot, back again.
-- The gunner fires long bursts
-- (`Level.nestGun`), and only into the nest's arc. Drop him and the
-- nearest of his crew still up runs to the gun (`post`) and takes over.
-- nests.lua draws the guns.
--
-- The Winding Road (city-map's `road`, quests' "a-man-road") holds a
-- checkpoint past every bridge but the top one (the Poison Zombie's): two MG nests either side of the road
-- facing back over it (the map's `nests`, crewed as the Coast's are) and a
-- bunker whose garrison comes in waves (a garrison's `waves`: a squad of
-- `squad` out of its door one after another, the next squad `every`
-- seconds on while a player is near and no more than `alive` of its own
-- would be up with it, `total` in all, more with more humans; the door
-- opens again for each squad). On a map driven like that a car can run
-- them down: one hit at speed (car-collisions' numbers) is enough. Hunters
-- (the hunters feature) walk the open stretches of road between the
-- checkpoints (the map's `hunterBeats`, one more for each human past the first).
--
-- The Citadel (city-map's `citadel`, quests' "a-man-citadel") has guards
-- on the posts on every platform, an MG emplacement over the long span
-- (the map's `nests`, crewed as the Winding Road's), Hunters on the
-- beats round the gallery and the top (its `hunterBeats`) and two
-- Suppressors (the suppressors feature), heavies with a minigun and a
-- shield, holding the gallery and the reactor deck (its `suppressors`),
-- and a bunker on each wide platform but the top whose garrison comes in
-- waves, as the Winding Road's do (its `garrisons`).
--
-- The a-man feature (init.lua) passes its hooks on to this module.
--
-- Messages
--   server -> all  C17_TROOPS <tick> [<id> <x> <y> <facing> <hp> <alert> <gun>]...   (unreliable, 15 Hz;
--                  alert 1 has somebody, 2 searching or looking into something, 0 neither)
--   server -> all  C17_DOWN   <id> <x> <y> <angle>     a soldier went down
--   server -> all  C17_SAY    <id> <category> <index>  a soldier says radio.lines[category][index]
--   server -> all  C17_DOOR   <x> <y> <nx> <ny>        a garrison's door opens (nx, ny: the way out)
--   and cameo.lua's: C17_AMAN_IN, C17_AMAN_CASE, C17_AMAN_OUT, C17_TURRETS, C17_POP

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Combine = require("src.features.a-man.combine")
local Sight = require("src.features.d-day.sight")
local Radio = require("src.features.a-man.radio")
local Cameo = require("src.features.a-man.cameo")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Sounds = require("src.features.a-man.sounds")
local Nests = require("src.features.a-man.nests")
local Corpses = require("src.features.corpses")
local Car = require("src.car")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man" -- the quest this level belongs to (quests' `boss`)
Level.reach = 140 -- px from the Citadel's doors that counts as reaching them
Level.soldierDrops = 3 -- koins a soldier spills
Level.squadSize = 3 -- soldiers in a patrol
Level.guardsPerPost = 2 -- soldiers at each of the map's posts, side by side
Level.squadsPerBeat = 2 -- squads walking each beat, spread round it
Level.pairGap = 40 -- px between the guards sharing a post
Level.hunters = 3 -- Hunters (the hunters feature) patrolling round the Citadel
Level.hunterRing = 230 -- px out from the Citadel's wall that they walk
Level.fov = math.rad(60) -- how wide their cone of sight is (D-Day's guards see 30 degrees)
Level.alertFov = math.rad(100) -- how wide it is while one is on edge: has somebody, searching, investigating
Level.aware = 170 -- px all round them they notice somebody in, any way they face (not drawn)
Level.health = 60 -- three rounds (D-Day's soldiers take 40, two)
-- What they carry, by gun key: `weight` how likely, `burst` rounds at the
-- gun's own rate then `pause` seconds; `damage` per round instead of the
-- gun's (a soldier's sniper rifle doesn't kill in one). A gun not listed
-- has weight 1, a burst of 4 if it fires fast and 1 if not, a 1.2 s pause.
Level.loadout = {
  ak47 = { weight = 4, burst = 3, pause = 1.1 },
  uzi = { weight = 2, burst = 5, pause = 1.2 },
  shotgun = { weight = 2, burst = 1, pause = 1.3 },
  pistol = { weight = 1, burst = 2, pause = 0.9 },
  flamethrower = { weight = 1, burst = 10, pause = 1.0 },
  rocket = { weight = 0.5, burst = 1, pause = 3.0 },
  sniper = { weight = 0.5, burst = 1, pause = 2.5, damage = 60 },
  minigun = { weight = 0, burst = 1, pause = 1 }, -- the Suppressors' (the suppressors feature), not theirs
}
local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)
Level.chatEvery = { 12, 26 } -- seconds between a checkpoint's or a squad's idle chatter (min, max)
Level.replyAfter = { 1.3, 2.1 } -- seconds before a mate answers
Level.chatGap = 4 -- seconds, map-wide, between one conversation starting and the next
Level.shoutEvery = 6 -- seconds a soldier keeps quiet after shouting that he has someone
Level.downHeard = 700 -- px; a soldier this near one who goes down calls it in, and goes to look
Level.downAnswer = 5 -- of them at most go to look, nearest first (each works out his way there)
Level.callHeard = 800 -- px; soldiers this near where one spotted somebody come when he calls it in
Level.callAnswer = 3 -- how many of them come at most, nearest first
Level.callEvery = 15 -- seconds before the same soldier calls in again
Level.garrison = 4 -- soldiers out of a garrison's door, for one human (more humans, more)
Level.garrisonFirst = 0.8 -- seconds from the door opening to the first coming out
Level.garrisonEvery = 0.7 -- seconds between one coming out and the next
Level.doorOpen = 5 -- seconds a garrison's door stands open on every screen
-- What each map the soldiers hold has besides its posts and beats.
Level.maps = {
  city17 = { squadsPerBeat = 2, cameo = true, hunters = true },
  outercity = { squadsPerBeat = 1 }, -- fewer about: its garrisons bring more when they are wanted
  coast = { squadsPerBeat = 0, nests = true }, -- the bunkers' crews, for now
  road = { squadsPerBeat = 0, nests = true }, -- the bridges' checkpoints: nests and bunkers' waves
  citadel = { squadsPerBeat = 0, nests = true }, -- guards on every platform, the emplacement over the span
}
Level.nestCrew = 4 -- soldiers to an MG nest: one on the gun, the rest on the bunker's posts
Level.manGunWithin = 15 -- seconds the crewman going to a dead gunner's gun has before he is simply on it
-- The nest's gun: an AK's rounds, twelve a second, in long bursts.
Level.nestGun = { burst = 14, pause = 1.4, cooldown = 0.08, damage = 12, range = 700 }

local SYNC_EVERY = 2 -- server ticks between C17_TROOPS
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local GUNNER_ON = 16 -- px from a nest's gun that counts as on it (nests.lua's)
-- Combine soldiers: dark grey-blue fatigues and armour, gloved hands, a
-- masked head with two lenses that glow.
local LOOK = {
  shirt = { 0.34, 0.40, 0.48 }, pants = { 0.18, 0.21, 0.25 }, skin = { 0.13, 0.14, 0.16 },
  hood = { 0.17, 0.19, 0.22 }, shoes = { 0.06, 0.06, 0.07 }, vest = { 0.45, 0.51, 0.59 }, gun = true,
  mask = true, -- a masked head: dead lenses on his body (the corpses feature)
}
local LENS = { 0.45, 0.85, 1.00 }
local LENS_ALERT = { 1.00, 0.45, 0.20 }

local function fmt(v)
  return ("%.1f"):format(v)
end

--- The map in play, if the soldiers hold it, and what it has (Level.maps).
local function cityMap()
  local city = Features.byName["city-map"]
  local conf = city and Level.maps[city.current]
  return conf and city.map or nil, conf
end

-- Server --------------------------------------------------------------------

local sv = nil -- { troops, syncIn, reached, time, groups, pending }

local random = love.math.random

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- A gun for a soldier, picked by the loadout's weights, and how he uses it.
local function pickArms()
  local total = 0
  for _, gun in ipairs(Guns.list) do
    local l = Level.loadout[gun.key]
    total = total + (l and l.weight or 1)
  end
  local roll = random() * total
  local gun = Guns.list[1]
  for _, g in ipairs(Guns.list) do
    local w = Level.loadout[g.key]
    roll = roll - (w and w.weight or 1)
    if roll < 0 then
      gun = g
      break
    end
  end
  local l = Level.loadout[gun.key] or {}
  local tuned = Tiers.apply(gun, Tiers.DEFAULT) -- they carry common ones
  if l.damage then
    tuned = setmetatable({ damage = l.damage }, { __index = tuned })
  end
  return {
    gun = tuned,
    key = gun.key,
    index = gun.index,
    burst = l.burst or (gun.cooldown < 0.15 and 4 or 1),
    pause = l.pause or 1.2,
    reach = gun.speed * (gun.ttl or ROUND_TTL) * 0.85, -- a little short of where its rounds give out
  }
end

--- Where the `i`th guard at post `p` stands: the first on the post, the
--- others a step to either side of him (across the way he watches), or
--- behind him where the side is a wall.
local function besidePost(p, i)
  if i == 1 then
    return p.x, p.y
  end
  local city = Features.byName["city-map"]
  local d = Level.pairGap * math.ceil((i - 1) / 2)
  local side = i % 2 == 0 and 1 or -1
  local ax, ay = -math.sin(p.watch), math.cos(p.watch) -- across his watch
  local tries = {
    { p.x + ax * d * side, p.y + ay * d * side },
    { p.x - ax * d * side, p.y - ay * d * side },
    { p.x - math.cos(p.watch) * d, p.y - math.sin(p.watch) * d },
  }
  for _, t in ipairs(tries) do
    local clear = true
    for _, k in ipairs({ { 0, 0 }, { 10, 0 }, { -10, 0 }, { 0, 10 }, { 0, -10 } }) do
      clear = clear and not (city and city:blocksPoint(t[1] + k[1], t[2] + k[2]))
    end
    if clear then
      return t[1], t[2]
    end
  end
  return p.x, p.y
end

--- The Hunters' beat: a ring round the Citadel, kept inside its square.
local function citadelBeat(map)
  local c = map.citadel
  local y0, y1 = map.top + 90, c.y + c.r + 400
  for _, z in ipairs(map.zones or {}) do
    if z.name == "citadel" then
      y1 = z.y1 - 150
    end
  end
  local route, ring = {}, c.r + Level.hunterRing
  for i = 0, 7 do
    local a = i / 8 * 2 * math.pi
    local y = math.max(y0, math.min(y1, c.y + math.sin(a) * ring))
    route[#route + 1] = { x = c.x + math.cos(a) * ring, y = y }
  end
  return route
end

--- Everyone arrived: guards on every post, squads on every beat, Hunters
--- round the Citadel.
function Level.serverQuestStarted(server, quest)
  local map, conf = cityMap()
  if not (quest.boss == Level.questId and map and map.posts) then
    return
  end
  local troops = Combine.new({
    hunt = true, fov = Level.fov, alertFov = Level.alertFov, aware = Level.aware, health = Level.health,
  })
  sv = { troops = troops, syncIn = 0, reached = false, time = 0, garrisons = {} }
  Cameo.serverStart(conf.cameo == true) -- his plaza visits where the map has them; called-in ones anywhere
  local hunters = Features.byName.hunters
  if hunters and conf.hunters then
    hunters:serverPatrol(server, citadelBeat(map), Level.hunters)
  end
  for _, beat in ipairs(hunters and map.hunterBeats or {}) do -- the Winding Road's open stretches
    hunters:serverPatrol(server, beat.route, Bosses.plus(beat.count, server))
  end
  local suppressors = Features.byName.suppressors
  for _, p in ipairs(suppressors and map.suppressors or {}) do -- the Citadel's heavies
    suppressors:serverPost(server, p.x, p.y, p.watch)
  end
  for _, g in ipairs(map.garrisons or {}) do
    sv.garrisons[#sv.garrisons + 1] = { g = g, out = false, left = 0, nextIn = 0, doorFor = 0, own = {} }
  end
  sv.groups, sv.pending, sv.quietUntil = {}, {}, 0
  local T = require("src.features.city-map.layout").TILE
  sv.troops:navigate({ x = map.x0, y = map.y0, w = map.cols * T, h = map.rows * T })
  -- Who chats together: the guards at one checkpoint, or one squad.
  local posts = {}
  for _, p in ipairs(map.posts) do
    local g = posts[p.at]
    if not g then
      g = { kind = "post", members = {}, chatIn = between(Level.chatEvery) * random() }
      posts[p.at] = g
      sv.groups[#sv.groups + 1] = g
    end
    for i = 1, Level.guardsPerPost do
      local x, y = besidePost(p, i)
      g.members[#g.members + 1] = sv.troops:add("guard", x, y, p.watch + (i - 1) * 0.15)
    end
  end
  local perBeat = conf.squadsPerBeat or Level.squadsPerBeat
  for _, route in ipairs(map.patrols or {}) do
    -- A lone squad starts at the corner furthest from where everyone arrives.
    local first, far = random(#route), -1
    if perBeat == 1 then
      for i, pt in ipairs(route) do
        local d = (pt.x - map.cx) ^ 2 + (pt.y - map.cy) ^ 2
        if d > far then
          first, far = i, d
        end
      end
    end
    local taken = {}
    for i = 1, perBeat do
      -- Spread round the beat: each starts a share of its corners on from the
      -- first, or the next corner along where one is there already (a beat
      -- walked out and back passes some corners twice).
      local start = (first - 1 + math.floor((i - 1) * #route / perBeat)) % #route + 1
      for _ = 1, #route do
        local at = route[start].x .. "," .. route[start].y
        if not taken[at] then
          taken[at] = true
          break
        end
        start = start % #route + 1
      end
      local squad = sv.troops:addSquad(route, Level.squadSize, start)
      local chatIn = between(Level.chatEvery) * random()
      sv.groups[#sv.groups + 1] = { kind = "patrol", members = squad.members, chatIn = chatIn }
    end
  end
  for _, s in ipairs(sv.troops.list) do
    sv.troops:arm(s, pickArms())
  end
  sv.nests = {}
  if conf.nests then
    for _, b in ipairs(map.nests or map.bunkers or {}) do -- a bunker with its nest, or a nest on its own
      local nest = { b = b, crew = {} }
      local gunner = sv.troops:add("guard", b.nest.x, b.nest.y, b.nest.angle)
      gunner.hold = true
      nest.crew[1] = gunner
      for i = 1, Level.nestCrew - 1 do
        local p = b.posts[(i - 1) % #b.posts + 1]
        local s = sv.troops:add("guard", p.x, p.y, p.watch)
        s.hold, s.takesCover = true, true
        sv.troops:arm(s, pickArms())
        nest.crew[#nest.crew + 1] = s
      end
      Level.manGun(nest, gunner)
      sv.nests[#sv.nests + 1] = nest
      sv.groups[#sv.groups + 1] = { kind = "post", members = nest.crew, chatIn = between(Level.chatEvery) * random() }
    end
  end
end

--- `s` takes the gun of `nest`: its arc, its sight and its rounds.
function Level.manGun(nest, s)
  local n, g = nest.b.nest, Level.nestGun
  local ak = Guns.ak47
  s.watch, s.arc, s.fov, s.post = n.angle, n.arc, 2 * n.arc, nil
  s.takesCover, s.cv, s.threat = nil, nil, nil -- the gun has no cover to go to: he stays on it
  s.facing = n.angle
  nest.gunner, nest.coming = s, nil
  local gun = setmetatable({ damage = g.damage, cooldown = g.cooldown }, { __index = Tiers.apply(ak, Tiers.DEFAULT) })
  sv.troops:arm(s, { gun = gun, key = ak.key, index = ak.index, burst = g.burst, pause = g.pause, reach = g.range })
end

--- Every nest keeps its gun manned while any of its crew is up: the
--- nearest goes to it, and is on it after `manGunWithin` however he got stuck.
local function stepNests(dt)
  for _, nest in ipairs(sv.nests) do
    local n = nest.b.nest
    if nest.gunner and nest.gunner.hp <= 0 then
      nest.gunner = nil
    end
    local c = nest.coming
    if c and c.hp <= 0 then
      nest.coming, c = nil, nil
    end
    if c and c.post then
      nest.comingFor = (nest.comingFor or 0) + dt
      if nest.comingFor > Level.manGunWithin then
        c.x, c.y, c.post = n.x, n.y, nil -- caught on something all this time: he gets there anyway
      end
    end
    if c and not c.post then
      nest.comingFor = nil
      Level.manGun(nest, c) -- he got there
    elseif not nest.gunner and not c then
      local best, bestD2 = nil, math.huge
      for _, s in ipairs(nest.crew) do
        local d2 = (s.x - n.x) ^ 2 + (s.y - n.y) ^ 2
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

--- Over: nothing left to step or draw.
function Level.serverStop(server)
  Cameo.serverStop(server)
  local hunters = Features.byName.hunters
  if hunters then
    hunters:serverClear()
  end
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("C17_TROOPS", server.tick)) -- an empty list clears every screen
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
  for _, s in ipairs(sv.troops.list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.alert and 1 or (Combine.wary(s) and 2 or 0)
    parts[#parts + 1] = s.arms and s.arms.index or 0
  end
  local msg = Protocol.encode("C17_TROOPS", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Has anyone got to the Citadel's doors? The first one there finishes the
--- level: a star comes up at the doors.
local function checkReached(server)
  local map = cityMap()
  if sv.reached or not (map and map.citadelX) then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.citadelX) ^ 2 + (y - map.citadelY) ^ 2 <= Level.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests and quests.serverComplete then
          quests:serverComplete(server, Level.questId, map.citadelX, map.citadelY)
        end
        return
      end
    end
  end
end

-- Talk ----------------------------------------------------------------------

--- `s` says a line out of `category`, on every screen.
local function say(server, s, category)
  local lines = Radio.lines[category]
  server:broadcast(Protocol.encode("C17_SAY", s.id, category, random(#lines)))
end

--- `s` says something out of `category` in `after` seconds, if he is still up.
local function later(s, category, after)
  sv.pending[#sv.pending + 1] = { s = s, category = category, t = after }
end

local function alive(s)
  return s.hp > 0
end

--- Somebody in `g` still up other than `s`, at random.
local function mate(g, s)
  local others = {}
  for _, m in ipairs(g.members) do
    if m ~= s and alive(m) then
      others[#others + 1] = m
    end
  end
  return others[1] and others[random(#others)] or nil
end

--- `s` has just spotted somebody: he calls it in, and the nearest few
--- within earshot of the radio who aren't busy (and aren't his own squad,
--- who are with him already) come to where he saw them. The nearest of
--- them says he is on his way.
local function callIn(s)
  s.callUntil = sv.time + Level.callEvery
  local went = sv.troops:alarm(s.aimX, s.aimY, Level.callHeard, { from = s, most = Level.callAnswer })
  if went[1] then
    later(went[1], "investigate", 1.6)
  end
end

--- The idle chatter, the shouts and the replies.
local function talk(server, dt)
  sv.time = sv.time + dt
  for _, s in ipairs(sv.troops.list) do
    if s.alert and not s.wasAlert and (s.quietUntil or 0) <= sv.time then
      s.quietUntil = sv.time + Level.shoutEvery
      say(server, s, "alert")
    end
    if s.alert and not s.wasAlert and (s.callUntil or 0) <= sv.time then
      callIn(s)
    end
    s.wasAlert = s.alert
    if s.tookCover then -- diving for cover: now and then he says so
      s.tookCover = false
      if random() < 0.45 and (s.quietUntil or 0) <= sv.time then
        s.quietUntil = sv.time + Level.shoutEvery
        say(server, s, "cover")
      end
    end
    if s.threw then -- a grenade out: he says so, mostly
      s.threw = false
      if random() < 0.8 then
        s.quietUntil = sv.time + Level.shoutEvery
        say(server, s, "grenade")
      end
    end
    if s.sentOut then -- the first of a sweep going out after a shooter nobody saw
      s.sentOut = false
      s.quietUntil = sv.time + Level.shoutEvery
      say(server, s, "sweep")
      local other = mate({ members = sv.troops.list }, s)
      if other and (other.x - s.x) ^ 2 + (other.y - s.y) ^ 2 < 400 * 400 then
        later(other, "reply", between(Level.replyAfter))
      end
    end
    if s.gaveUp then -- looked, found nothing, on his way back
      s.gaveUp = false
      if random() < 0.6 and (s.quietUntil or 0) <= sv.time then
        s.quietUntil = sv.time + Level.shoutEvery
        say(server, s, "lost")
      end
    end
  end
  for _, g in ipairs(sv.groups) do
    g.chatIn = g.chatIn - dt
    if g.chatIn <= 0 and sv.time < sv.quietUntil then
      g.chatIn = 0.5 + random() * 3 -- somebody else is talking: wait a moment, not all at once after
    elseif g.chatIn <= 0 then
      g.chatIn = between(Level.chatEvery)
      local busy = false
      for _, m in ipairs(g.members) do
        busy = busy or (alive(m) and m.alert)
      end
      -- A squad's leader is the first of them; at a checkpoint, anyone.
      local speaker = g.kind == "patrol" and g.members[1] or mate(g, nil)
      if speaker and not busy then
        sv.quietUntil = sv.time + Level.chatGap
        say(server, speaker, g.kind)
        local other = mate(g, speaker)
        if other then
          later(other, "reply", between(Level.replyAfter))
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

--- Everyone near enough to hear `down` go down goes to look; the nearest
--- of them calls it in, the next says he is on his way. If nobody is free
--- to go, the nearest still calls it in.
local function callDown(down)
  local went = sv.troops:alarm(down.x, down.y, Level.downHeard, { most = Level.downAnswer })
  if went[1] then
    later(went[1], "down", 0.5)
    if went[2] then
      later(went[2], "investigate", 1.8)
    end
    return
  end
  local best, bestD2 = nil, Level.downHeard ^ 2
  for _, s in ipairs(sv.troops.list) do
    local d2 = (s.x - down.x) ^ 2 + (s.y - down.y) ^ 2
    if s ~= down and d2 < bestD2 then
      best, bestD2 = s, d2
    end
  end
  if best then
    later(best, "down", 0.5)
  end
end

--- The nearest player anyone could see within `reach` of (x, y), as a point.
local function nearestPlayer(server, x, y, reach)
  local best, bestD2 = nil, reach * reach
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = (px - x) ^ 2 + (py - y) ^ 2
      if d2 <= bestD2 then
        best, bestD2 = { x = px, y = py }, d2
      end
    end
  end
  return best
end

--- The garrisons: a door opens the first time a player comes near, and its
--- soldiers come out one by one and go for where the player is.
local function stepGarrisons(server, dt)
  for _, gs in ipairs(sv.garrisons) do
    local g, door = gs.g, gs.g.door
    gs.doorFor = gs.doorFor - dt
    local waves = g.waves
    if not gs.out then
      local who = nearestPlayer(server, g.x, g.y, g.reach)
      if who then
        gs.out, gs.target = true, who
        gs.left = Bosses.count(waves and waves.total or Level.garrison, server)
        gs.nextIn = Level.garrisonFirst
        gs.doorFor = Level.doorOpen
        server:broadcast(Protocol.encode("C17_DOOR", door.x, door.y, door.nx, door.ny))
      end
    elseif gs.left > 0 then
      gs.nextIn = gs.nextIn - dt
      local ready = gs.nextIn <= 0
      local squad = waves and waves.squad or 1
      if ready and waves and (gs.burst or 0) == 0 then
        -- A squad at a time: only while somebody is near, and not too many of its own up at once.
        local up = 0
        for i = #gs.own, 1, -1 do
          if gs.own[i].hp > 0 then
            up = up + 1
          else
            table.remove(gs.own, i)
          end
        end
        local who = nearestPlayer(server, g.x, g.y, g.reach * 1.5)
        ready = who ~= nil and up + squad <= waves.alive
        if ready then
          gs.burst = math.min(squad, gs.left)
          if gs.doorFor <= 0 then -- the door shut since the last: open it again
            gs.doorFor = Level.doorOpen
            server:broadcast(Protocol.encode("C17_DOOR", door.x, door.y, door.nx, door.ny))
          end
        end
      end
      if ready then
        gs.left = gs.left - 1
        local slot = 0 -- which of his squad he is: the first goes straight for them, the others to either side
        if waves then
          gs.burst = gs.burst - 1
          slot = squad - 1 - gs.burst
          gs.nextIn = gs.burst > 0 and Level.garrisonEvery or waves.every
        else
          gs.nextIn = Level.garrisonEvery
        end
        gs.target = nearestPlayer(server, g.x, g.y, g.reach * 1.5) or gs.target
        local s = sv.troops:add("guard", door.x + door.nx * 22, door.y + door.ny * 22, math.atan2(door.ny, door.nx))
        gs.own[#gs.own + 1] = s
        sv.troops:arm(s, pickArms())
        local side = slot == 0 and 0 or (slot % 2 == 1 and 1 or -1) * 50 * math.ceil(slot / 2)
        sv.troops:sendTo(s, gs.target.x - door.ny * side, gs.target.y + door.nx * side)
        if not gs.said then -- the first out says where they are going
          gs.said = true
          later(s, "investigate", 0.4)
        end
      end
    end
  end
end

--- Reinforcements, for another feature (the Hunter-Chopper's): `count`
--- soldiers (more with more humans: Bosses.count) set down on clear ground
--- round (x, y), who go for the nearest player and stand guard where they
--- end up. Returns how many came, 0 while no level runs.
function Level.serverDrop(server, x, y, count)
  if not sv then
    return 0
  end
  local city = Features.byName["city-map"]
  local n = Bosses.count(count, server)
  local target = nearestPlayer(server, x, y, 1e5) or { x = x, y = y }
  local came = 0
  for i = 1, n do
    local a = (i - 1) / n * 2 * math.pi
    for r = 40, 200, 40 do
      local sx, sy = x + math.cos(a) * r, y + math.sin(a) * r
      if not (city and city:blocksPoint(sx, sy)) then
        local s = sv.troops:add("guard", sx, sy, math.atan2(target.y - sy, target.x - sx))
        sv.troops:arm(s, pickArms())
        sv.troops:sendTo(s, target.x, target.y)
        if came == 0 then -- the first down says where they are going
          later(s, "investigate", 0.4)
        end
        came = came + 1
        break
      end
    end
  end
  return came
end

--- How many soldiers are still up inside { x, y, w, h }, for another
--- feature (the antlions' boss waits for the Coast's final section to be clear).
function Level.serverTroopsIn(r)
  local n = 0
  for _, s in ipairs(sv and sv.troops.list or {}) do
    if s.hp > 0 and s.x >= r.x and s.x <= r.x + r.w and s.y >= r.y and s.y <= r.y + r.h then
      n = n + 1
    end
  end
  return n
end

--- A-Man drops in once near the player nearest (x, y), for another feature
--- (cameo.lua's serverVisit). False while no level runs.
function Level.serverVisit(server, x, y, opened)
  return sv ~= nil and Cameo.serverVisit(server, x, y, opened)
end

--- One soldier down: gibs on every screen, a few koins, maybe a pickup.
local function soldierDown(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("C17_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  callDown(s)
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Level.soldierDrops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
end

--- Cars running soldiers down, on a map that is driven: car-collisions'
--- numbers, the driver's kill.
local function runOver(server)
  local cc = Features.byName["car-collisions"]
  if not (cc and cityMap().vehicles) then
    return
  end
  for _, car in pairs(server.vehicles) do
    if car.driver and not car.hidden and math.abs(car.speed) >= cc.runOverSpeed then
      for i = #sv.troops.list, 1, -1 do
        local s = sv.troops.list[i]
        if Car.hitTest(car, s.x, s.y, Combine.RADIUS) then
          local amount = cc.runOverDamage * (1 + math.min(1, math.abs(car.speed) / car.maxSpeed))
          local travel = car.speed >= 0 and car.angle or car.angle + math.pi
          if sv.troops:hurt(s, i, amount, travel) then
            soldierDown(server, s, car.driver, travel, "impact")
          end
        end
      end
    end
  end
end

function Level.serverStep(server, dt)
  if not sv then
    return
  end
  sv.troops:update(server, dt)
  runOver(server)
  stepNests(dt)
  stepGarrisons(server, dt)
  Cameo.serverStep(server, dt, cityMap())
  talk(server, dt)
  checkReached(server)
  sync(server)
end

--- A bullet through (x, y): the `serverShotAt` convention. Their own rounds
--- (owned by nobody) pass through their side. A round takes off what it
--- carries (the gun's damage, tier and all); a blast, which carries
--- nothing and asks a few times over, 20 a time. `dtype` is the kill's cause.
function Level.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  if Cameo.serverShotAt(server, x, y, radius, by) then
    return true
  end
  local s, i = sv.troops:at(x, y, radius)
  if not s then
    return false
  end
  if sv.troops:hurt(s, i, damage or Combine.SHOT_DAMAGE, angle) then
    soldierDown(server, s, by, angle, dtype)
  end
  return true
end

function Level.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.troops:freeze(x, y, radius, seconds)
  end
  Cameo.serverFreezeArea(x, y, radius, seconds)
end

function Level.serverPanicArea(x, y, radius)
  if sv then
    sv.troops:scare(x, y, radius, 0.5)
  end
end

--- For tests.
function Level.server()
  return sv
end

-- Client --------------------------------------------------------------------

local troops = {} -- id -> { x, y, dx, dy, angle, hp, alert, bob, stride, say, sayT, shout }
local doors = {} -- { x, y, nx, ny, t }: garrisons' doors standing open
local lastTick = 0
local heardAt = 0 -- when the last C17_TROOPS came
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer
local time = 0

function Level.clear()
  troops, doors, lastTick = {}, {}, 0
  Cameo.clear()
  Corpses.clear()
end

--- The arc of the MG nest's gun soldier `s` (as drawn) stands at, or nil.
local function gunnersArc(s)
  local city = Features.byName["city-map"]
  local map = city and city.map
  for _, b in ipairs(map and (map.nests or map.bunkers) or {}) do
    local n = b.nest
    if (s.dx - n.x) ^ 2 + (s.dy - n.y) ^ 2 < GUNNER_ON * GUNNER_ON then
      return n.arc
    end
  end
end

function Level.update(dt)
  time = time + dt
  if next(troops) and love.timer.getTime() - heardAt > STALE then
    troops = {}
  end
  Cameo.update(dt)
  for i = #doors, 1, -1 do
    doors[i].t = doors[i].t - dt
    if doors[i].t <= 0 then
      table.remove(doors, i)
    end
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
    -- His cone opens out while he is on edge and closes again after; on an
    -- MG nest's gun it is as wide as the gun turns, the way the host sees it.
    local arc = gunnersArc(s)
    local fov = arc and 2 * arc or (s.wary and Level.alertFov or Level.fov)
    s.fov = s.fov + (fov - s.fov) * math.min(1, dt * 4)
    if s.say then
      s.sayT = s.sayT - dt
      if s.sayT <= 0 then
        s.say = nil
      end
    end
  end
end

--- A garrison's door standing open: the doorway lit from inside and the
--- light falling out across the ground, fading as it shuts.
local function drawDoor(d)
  local k = math.min(1, d.t / 0.6, (Level.doorOpen - d.t) / 0.25) -- opening, open, shutting
  local ax, ay = d.ny ~= 0 and 1 or 0, d.nx ~= 0 and 1 or 0 -- along the face
  local w = 40
  local x0, y0 = d.x - ax * w / 2, d.y - ay * w / 2
  local spill = 90 * k
  love.graphics.setColor(0.55, 0.85, 1, 0.22 * k)
  love.graphics.polygon("fill", x0, y0, x0 + ax * w, y0 + ay * w,
    x0 + ax * (w + 30) + d.nx * spill, y0 + ay * (w + 30) + d.ny * spill,
    x0 - ax * 30 + d.nx * spill, y0 - ay * 30 + d.ny * spill)
  love.graphics.setColor(0.80, 0.95, 1, 0.9 * k)
  love.graphics.rectangle("fill", math.min(x0, x0 - d.nx * 8), math.min(y0, y0 - d.ny * 8),
    ax * w + math.abs(d.nx) * 8, ay * w + math.abs(d.ny) * 8)
end

--- Their cones of sight, on the ground under everything (unless the
--- sight-cones toggle hides them).
function Level.drawBelowCars()
  for _, d in ipairs(doors) do
    drawDoor(d)
  end
  if not Features.any("hideSightCones") then -- the ` key (sight-cones)
    for _, s in pairs(troops) do
      Sight.draw(s.dx, s.dy, s.angle, Combine.RANGE, s.alert, time, s.fov)
    end
  end
  Cameo.drawBelowCars()
end

--- How each gun shows in his hands: how far the barrel reaches, and a pack
--- on his back for the flamethrower's tank and the launcher's missiles.
local HELD = {
  pistol = { gunLength = 4 },
  uzi = { gunLength = 8 },
  ak47 = { gunLength = 15 },
  shotgun = { gunLength = 14 },
  sniper = { gunLength = 21 },
  rocket = { gunLength = 18, pack = { 0.28, 0.32, 0.24 } },
  flamethrower = { gunLength = 12, pack = { 0.78, 0.36, 0.12 } },
  minigun = { gunLength = 14, pack = { 0.22, 0.24, 0.20 } },
}
local looks = {} -- gun index -> LOOK with that gun in his hands

local function lookFor(index)
  local look = looks[index or 0]
  if not look then
    look = {}
    for k, v in pairs(LOOK) do
      look[k] = v
    end
    local gun = index and Guns.list[index]
    local held = gun and HELD[gun.key] or {}
    look.gunLength, look.pack = held.gunLength or 15, held.pack
    looks[index or 0] = look
  end
  return look
end

--- One soldier: the core's person in Combine gear with whatever gun he
--- carries, the mask's two lenses glowing (hot when he has somebody), a "!"
--- over him then, and a bar under him once he is hurt.
local function drawSoldier(s)
  local x, y, r = s.dx, s.dy, Body.SHOULDERS
  Body.person(x, y, s.angle, math.sin(s.stride * 0.18) * 1.2, lookFor(s.gun))
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(s.angle)
  local lens = s.alert and LENS_ALERT or LENS
  love.graphics.setColor(lens)
  love.graphics.circle("fill", 3.4, -1.5, 1.1, 6)
  love.graphics.circle("fill", 3.4, 1.5, 1.1, 6)
  love.graphics.pop()
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(1, 0.45, 0.2)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < Level.health then
    local bw, f = 20, math.max(0, s.hp / Level.health)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

function Level.drawAboveCars()
  for _, s in pairs(troops) do
    drawSoldier(s)
  end
  local city = Features.byName["city-map"]
  Nests.draw(city and Level.maps[city.current] and city.map, troops)
  Cameo.drawAboveCars()
  -- What they say, over all of them.
  for _, s in pairs(troops) do
    if s.say then
      local lift = s.alert and 34 or 8
      Radio.drawBubble(s.dx, s.dy - Body.SHOULDERS - lift, s.say, math.min(1, s.sayT * 2), s.shout)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Level.clientMessages = {
  C17_DOOR = function(_client, args)
    local x, y, nx, ny = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and nx and ny then
      doors[#doors + 1] = { x = x, y = y, nx = nx, ny = ny, t = Level.doorOpen }
      Sounds.play("door", x, y)
    end
  end,
  C17_TROOPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = troops[id]
        if not s then
          s = { dx = x, dy = y, bob = love.math.random() * 6, stride = 0, fov = Level.fov }
          troops[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.hp = tonumber(args[i + 4]) or Level.health
        s.alert = args[i + 5] == "1"
        s.wary = args[i + 5] ~= "0"
        s.gun = tonumber(args[i + 6])
        seen[id] = true
      end
    end
    for id in pairs(troops) do
      if not seen[id] then
        troops[id] = nil
      end
    end
  end,
  C17_SAY = function(_client, args)
    local s = troops[tonumber(args[1])]
    local lines = Radio.lines[args[2]]
    local text = lines and lines[tonumber(args[3])]
    if s and text then
      s.say, s.sayT = text, Radio.sayTime(text)
      s.shout = args[2] == "alert" or args[2] == "down"
      Radio.play(text, s.x, s.y, s.shout)
    end
  end,
  C17_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and troops[id]
    if id then
      troops[id] = nil
    end
    if x and y then
      -- His body, where he was drawn, knocked over the way the round went.
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, lookFor(s and s.gun))
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
      end
    end
  end,
}
for kind, handler in pairs(Cameo.clientMessages) do
  Level.clientMessages[kind] = handler
end

--- The Combine soldiers this client shows, id -> { dx, dy, ... } (footsteps).
function Level.troops()
  return troops
end

return Level
