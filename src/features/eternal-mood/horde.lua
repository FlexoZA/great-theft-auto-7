-- Heck's horde on a level (docs/eternal-mood.md, "The horde"): one enemy,
-- on the host, and how it looks on every screen. init.lua passes its hooks
-- on to this module.
--
-- The possessed (possessed_brain.lua: staffers, guards, the overtime guy)
-- stand at the map's posts (city-map's `map.horde.posts`) or walk its
-- patrols (`map.horde.patrols`, a squad to each) until they see somebody;
-- the guards and the overtime guy fight like the Combine (possessed_brain.lua).
-- The Interns (intern_brain.lua), the lowest rank, stand about in mobs
-- (`map.horde.mobs`) until a player comes within a mob's `wake` px or sees
-- it from across the room, or one of it is hurt; then the whole mob comes,
-- `count` for one human and one more for each human past the first.
-- The imps (imp_brain.lua) wait in the vents (`map.horde.vents`): the
-- first time a player comes within a vent's `wake` px its grille bursts
-- open and its pack crawls out one after another, `count` for one human and
-- one more for each human past the first (Bosses.plus), and hunts. What
-- the imps throw is fireballs.lua's.
-- The Cacodaemons (cacodaemon_brain.lua), the heavy demons, float about
-- their spots (`map.horde.cacos`, a flock to each, `count` for one human
-- and one more for each human past the first) over roofs and lava until a
-- player comes near, then fly at you over everything and spit balls of
-- fire (fireballs.lua's "spit"), mouth open first.
--
-- The horde is all one side: its rounds carry its name (weapons' `from`),
-- and an ownerless round passes through every one of them, so nothing of
-- Heck's ever hurts anything else of Heck's. Only players' rounds and
-- blasts reach them. One that spots somebody groans, and the rest of the
-- horde near it comes to look.
--
-- They talk (Story.horde): idle chatter at their posts, a shout on spotting
-- somebody, a last word going down; the imps mostly growl.
--
-- Messages
--   server -> all  HRD_STATE <tick> [<id> <kind> <x> <y> <facing> <hp> <state> <alert>]...  (unreliable,
--                  15 Hz; kind s staffer, g guard, o overtime, z intern, i imp, c Cacodaemon; state for the
--                  possessed 0 at post, 1 hunting, 2 looking; for an intern 0 standing about, 1 after somebody,
--                  2 arms up to claw; for an imp 0 hunting, 1 crawling out, 2 winding up a throw; for a
--                  Cacodaemon 0 waiting, 1 hunting, 2 mouth open to spit, 3 mouth open to bite, 4 reeling)
--   server -> all  HRD_DOWN  <id> <x> <y> <angle> <kind>   one went down
--   server -> all  HRD_SAY   <id> <category> <index>       one says Story.horde[side][category][index]
--   server -> all  HRD_VENT  <index>                       vent `index` of the map's burst open
--   server -> all  HRD_SPIN  <id>                          the overtime guy's chaingun winding up
--   server -> all  HRD_CLAW  <id>                          an imp or an intern clawed, a Cacodaemon bit
--   server -> all  HRD_REEL  <id>                          a Cacodaemon shot in the mouth

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")
local Corpses = require("src.features.corpses")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Possessed = require("src.features.eternal-mood.possessed_brain")
local Imps = require("src.features.eternal-mood.imp_brain")
local Interns = require("src.features.eternal-mood.intern_brain")
local Cacos = require("src.features.eternal-mood.cacodaemon_brain")
local Fireballs = require("src.features.eternal-mood.fireballs")
local Story = require("src.features.eternal-mood.story")

local Horde = {}

-- Tuning ------------------------------------------------------------------
Horde.FROM = "horde" -- the name on its rounds
Horde.firstPossessed = 1
Horde.firstImp = 20001
Horde.firstIntern = 30001
Horde.firstCaco = 40001
Horde.mobSees = 520 -- px: a player in plain sight this near wakes a mob too
Horde.mobSpread = 110 -- px round its spot a mob stands about in
Horde.internPickups = 0.15 -- the chance one going down drops something (a mob would bury you in them)
Horde.wake = 420 -- px a player comes within to burst a vent open (a vent may say its own)
Horde.crawlEvery = 0.7 -- seconds between imps out of one vent
Horde.drops = { staffer = 2, guard = 3, overtime = 6, imp = 3, intern = 1, caco = 8 } -- koins each spills
Horde.chatEvery = { 14, 32 } -- seconds between one of the possessed's idle remarks
Horde.chatNear = 900 -- px; nobody talks to an empty room
Horde.sayFor = 2.6 -- seconds a remark shows

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local HURT = 0.18

local KIND = { staffer = "s", guard = "g", overtime = "o", imp = "i", intern = "z", caco = "c" }
local RANK = { s = "staffer", g = "guard", o = "overtime" }
local POSSESSED_STATE = { post = 0, beat = 0, hunt = 1, search = 2, back = 2 }
local IMP_STATE = { hunt = 0, emerge = 1, windup = 2 }
local INTERN_STATE = { idle = 0, hunt = 1, windup = 2 }
local CACO_STATE = { idle = 0, hunt = 1, open = 2, bite = 3, reel = 4 }

local RED = { 1.00, 0.18, 0.10 }
local ORANGE = { 1.00, 0.55, 0.12 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

-- Server --------------------------------------------------------------------

local sv = nil -- { possessed, imps, vents, syncIn, emptySends, chatIn }

local function say(server, s, side, category)
  local lines = Story.horde[side] and Story.horde[side][category]
  if lines and #lines > 0 then
    server:broadcast(Protocol.encode("HRD_SAY", s.id, category, random(#lines)))
  end
end

--- An imp or an intern claws player `who`.
local function claw(server, _imp, who, damage, angle)
  local weapons = Features.byName.weapons
  local p = server.players[who]
  if p and weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, damage, angle, "melee")
  end
end

--- Put the horde on `map` (its `horde`), or nothing on a map without one.
--- Returns the walking grid it built, for the level's boss.
function Horde.serverStart(server, map)
  Horde.serverStop(server)
  local spec = map.horde
  if not spec then
    return
  end
  local T = require("src.features.city-map.layout").TILE
  local nav = Nav.build({ x = map.x0, y = map.y0, w = map.cols * T, h = map.rows * T })
  local possessed
  possessed = Possessed.new({
    nav = nav, firstId = Horde.firstPossessed, from = Horde.FROM,
    -- One groans: the possessed near it come and look where it saw somebody.
    call = function(x, y, tx, ty)
      for _, o in ipairs(possessed.list) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 <= Possessed.CALL * Possessed.CALL then
          possessed:alert(o, tx, ty)
        end
      end
    end,
  })
  for _, p in ipairs(spec.posts or {}) do
    possessed:add(p.rank, p.x, p.y, p.watch)
  end
  -- Patrols: a squad walking its loop, its leader in front.
  for _, p in ipairs(spec.patrols or {}) do
    possessed:addSquad(p.route, p.ranks, p.start)
  end
  local imps = Imps.new({ nav = nav, firstId = Horde.firstImp, throw = function(srv, _imp, x, y, angle)
    Fireballs.serverThrow(srv, x, y, angle)
  end, claw = claw })
  local interns = Interns.new({ nav = nav, firstId = Horde.firstIntern, claw = claw })
  local mobs = {}
  for i, mob in ipairs(spec.mobs or {}) do
    mobs[i] = { x = mob.x, y = mob.y, wake = mob.wake or Horde.wake, awake = false }
    local n = Bosses.plus(mob.count or 5, server)
    for _ = 1, n do
      -- Somewhere clear round the spot, standing about.
      local x, y = mob.x, mob.y
      for _ = 1, 12 do
        local a, d = random() * 2 * math.pi, Horde.mobSpread * math.sqrt(random())
        local cx, cy = mob.x + math.cos(a) * d, mob.y + math.sin(a) * d
        if not (Sight.blocked(cx, cy) or Sight.blocked(cx - 10, cy) or Sight.blocked(cx + 10, cy)
          or Sight.blocked(cx, cy - 10) or Sight.blocked(cx, cy + 10)) then
          x, y = cx, cy
          break
        end
      end
      interns:add(x, y, nil, i, false) -- (on the spot itself if nowhere round it was clear)
    end
  end
  local cacos = Cacos.new({
    firstId = Horde.firstCaco,
    bounds = { x0 = map.x0, y0 = map.y0, x1 = map.x0 + map.cols * T, y1 = map.y0 + map.rows * T },
    spit = function(srv, _caco, x, y, angle)
      Fireballs.serverThrow(srv, x, y, angle, "spit")
    end,
    bite = claw,
  })
  for i, flock in ipairs(spec.cacos or {}) do
    local n = Bosses.plus(flock.count or 1, server)
    for k = 1, n do -- spread round the spot
      local a = k / n * 2 * math.pi
      local d = n > 1 and Cacos.SPACE or 0
      cacos:add(flock.x + math.cos(a) * d, flock.y + math.sin(a) * d, flock.wake, i)
    end
  end
  local vents = {}
  for i, v in ipairs(spec.vents or {}) do
    vents[i] = { x = v.x, y = v.y, out = v.out or 0, count = v.count or 3, wake = v.wake or Horde.wake,
      open = false, left = 0, crawlIn = 0 }
  end
  Fireballs.serverStart()
  sv = { possessed = possessed, imps = imps, interns = interns, cacos = cacos, mobs = mobs, vents = vents, syncIn = 0,
    emptySends = 0, chatIn = between(Horde.chatEvery) }
  return nav
end

function Horde.serverStop(server)
  Fireballs.serverStop()
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("HRD_STATE", server.tick))
  end
end

--- One of rank `rank` called in (a boss's meeting): at (x, y), on its way
--- to look at (tx, ty), and back to (x, y) after if it finds nobody. A
--- "caco" comes in awake, hunting.
function Horde.serverCall(server, rank, x, y, tx, ty)
  if sv and rank == "caco" then
    local s = sv.cacos:add(x, y, 0, nil)
    sv.cacos:wakeUp(s)
    s.woke = nil
    say(server, s, "caco", "alert")
  elseif sv and rank == "intern" then
    sv.interns:add(x, y, math.atan2(ty - y, tx - x), nil, true) -- awake already
  elseif sv then
    local s = sv.possessed:add(rank, x, y, math.atan2(ty - y, tx - x))
    sv.possessed:alert(s, tx, ty)
  end
end

--- Wake mob `i`: the lot of them, and one shouts about it.
local function wakeMob(server, i)
  local mob = sv.mobs[i]
  if not mob or mob.awake then
    return
  end
  mob.awake = true
  sv.interns:wake(i)
  for _, s in ipairs(sv.interns.list) do
    if s.mob == i then
      say(server, s, "intern", "alert")
      break
    end
  end
end

--- Wake the mobs a player has come near, or can see from across the room.
local function stepMobs(server)
  for i, mob in ipairs(sv.mobs) do
    if not mob.awake then
      for _, p in pairs(server.players) do
        if not p.bot and Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          local d2 = (x - mob.x) ^ 2 + (y - mob.y) ^ 2
          if d2 <= mob.wake * mob.wake or (d2 <= Horde.mobSees * Horde.mobSees and Sight.clear(x, y, mob.x, mob.y)) then
            wakeMob(server, i)
            break
          end
        end
      end
    end
  end
end

--- A newcomer sees the vents already burst.
function Horde.serverPlayerJoined(server, player)
  for i, v in ipairs(sv and sv.vents or {}) do
    if v.open then
      server:send(player, Protocol.encode("HRD_VENT", i), true)
    end
  end
end

--- Burst the vents players have come near, and let their imps out.
local function stepVents(server, dt)
  for i, v in ipairs(sv.vents) do
    if not v.open then
      for _, p in pairs(server.players) do
        if not p.bot and Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          if (x - v.x) ^ 2 + (y - v.y) ^ 2 <= v.wake * v.wake then
            v.open, v.left, v.crawlIn = true, Bosses.plus(v.count, server), 0.3
            server:broadcast(Protocol.encode("HRD_VENT", i))
            break
          end
        end
      end
    elseif v.left > 0 then
      v.crawlIn = v.crawlIn - dt
      if v.crawlIn <= 0 then
        v.left, v.crawlIn = v.left - 1, Horde.crawlEvery
        local imp = sv.imps:add(v.x, v.y, v.out + (random() - 0.5) * 0.8)
        if v.left == 0 or random() < 0.4 then
          say(server, imp, "imp", "alert")
        end
      end
    end
  end
end

--- Now and then one of the possessed at its post says something, if a
--- player is near enough to hear.
local function chatter(server, dt)
  sv.chatIn = sv.chatIn - dt
  if sv.chatIn > 0 then
    return
  end
  sv.chatIn = between(Horde.chatEvery)
  local idle = {}
  for _, s in ipairs(sv.possessed.list) do
    if s.state == "post" or s.state == "beat" then
      for _, p in pairs(server.players) do
        if not p.bot and Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          if (x - s.x) ^ 2 + (y - s.y) ^ 2 <= Horde.chatNear * Horde.chatNear then
            idle[#idle + 1] = s
            break
          end
        end
      end
    end
  end
  if #idle > 0 then
    say(server, idle[random(#idle)], "possessed", "idle")
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local count = #sv.possessed.list + #sv.imps.list + #sv.interns.list + #sv.cacos.list
  if count == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { server.tick }
  local function put(s, kind, state)
    parts[#parts + 1] = s.id
    parts[#parts + 1] = kind
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = state
    parts[#parts + 1] = s.target and 1 or 0
  end
  for _, s in ipairs(sv.possessed.list) do
    put(s, KIND[s.rank], POSSESSED_STATE[s.state] or 0)
  end
  for _, s in ipairs(sv.imps.list) do
    put(s, "i", IMP_STATE[s.state] or 0)
  end
  for _, s in ipairs(sv.interns.list) do
    put(s, "z", INTERN_STATE[s.state] or 0)
  end
  for _, s in ipairs(sv.cacos.list) do
    put(s, "c", CACO_STATE[s.state] or 0)
  end
  local msg = Protocol.encode("HRD_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Horde.serverStep(server, dt)
  if not sv then
    return
  end
  stepVents(server, dt)
  stepMobs(server)
  sv.possessed:update(server, dt)
  sv.imps:update(server, dt)
  sv.interns:update(server, dt)
  sv.cacos:update(server, dt)
  Fireballs.serverStep(server, dt)
  for _, s in ipairs(sv.possessed.list) do
    if s.spotted then
      s.spotted = nil
      if random() < 0.6 then
        say(server, s, "possessed", "alert")
      end
    end
    -- What the smart ones say: into cover, a grenade, out on a sweep.
    if s.tookCover then
      s.tookCover = nil
      if random() < 0.25 then
        say(server, s, "possessed", "cover")
      end
    end
    if s.threw then
      s.threw = nil
      say(server, s, "possessed", "grenade")
    end
    if s.sentOut then
      s.sentOut = nil
      say(server, s, "possessed", "sweep")
    end
    if s.spinning then
      server:broadcast(Protocol.encode("HRD_SPIN", s.id))
    end
  end
  for _, s in ipairs(sv.cacos.list) do
    if s.woke then
      s.woke = nil
      if random() < 0.7 then
        say(server, s, "caco", "alert")
      end
    end
    if s.reeled then
      s.reeled = nil
      server:broadcast(Protocol.encode("HRD_REEL", s.id))
    end
  end
  for _, list in ipairs({ sv.imps.list, sv.interns.list, sv.cacos.list }) do
    for _, s in ipairs(list) do
      if s.clawed then
        server:broadcast(Protocol.encode("HRD_CLAW", s.id))
      end
    end
  end
  chatter(server, dt)
  sync(server)
end

local function down(server, s, kind, by, angle, cause)
  server:broadcast(Protocol.encode("HRD_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0), KIND[kind]))
  if random() < (kind == "intern" and 0.12 or 0.35) then
    say(server, s, (kind == "imp" or kind == "intern" or kind == "caco") and kind or "possessed", "down")
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Horde.drops[kind] or 2)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy and (kind ~= "intern" or random() < Horde.internPickups) then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, {
    kind = (kind == "imp" or kind == "caco") and "demon" or "soldier", x = s.x, y = s.y, by = by, angle = angle,
    cause = cause,
  })
end

--- A round through (x, y): the `serverShotAt` convention. Players' rounds
--- and blasts hit; an ownerless one (Heck's own) passes through. Returns
--- true when it hit one.
function Horde.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.possessed:at(x, y, radius)
  if s then
    if sv.possessed:hurt(s, i, damage or 20, angle) then
      down(server, s, s.rank, by, angle, dtype)
    end
    return true
  end
  s, i = sv.imps:at(x, y, radius)
  if s then
    if sv.imps:hurt(s, i, damage or 20) then
      down(server, s, "imp", by, angle, dtype)
    end
    return true
  end
  s, i = sv.interns:at(x, y, radius)
  if s then
    if s.mob then
      wakeMob(server, s.mob) -- hurt one, and the mob comes
    end
    if sv.interns:hurt(s, i, damage or 20) then
      down(server, s, "intern", by, angle, dtype)
    end
    return true
  end
  s, i = sv.cacos:at(x, y, radius)
  if s then
    if sv.cacos:hurt(s, i, damage or 20, angle) then
      down(server, s, "caco", by, angle, dtype)
    end
    return true
  end
  return false
end

function Horde.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.possessed:freeze(x, y, radius, seconds)
    sv.imps:freeze(x, y, radius, seconds)
    sv.interns:freeze(x, y, radius, seconds)
    sv.cacos:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Horde.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { kind, x, y, dx, dy, facing, hp, state, alert, stride, hurt, spinT }
local said = {} -- id -> { text, t }
local opened = {} -- vent index -> true
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

-- The possessed: torn UAC grey and hazard yellow, grey-green skin; Heck's
-- red eyes and the cracks in their skin are drawn over them.
local SKIN = { 0.52, 0.56, 0.46 }
local LOOK = {
  staffer = { shirt = { 0.46, 0.46, 0.44 }, pants = { 0.36, 0.36, 0.34 }, skin = SKIN, hair = { 0.18, 0.16, 0.14 },
    gun = true, gunLength = 4 },
  guard = { shirt = { 0.30, 0.32, 0.34 }, pants = { 0.24, 0.25, 0.27 }, skin = SKIN, vest = { 0.20, 0.21, 0.23 },
    hat = { 0.34, 0.36, 0.38 }, gun = true, gunLength = 9 },
  overtime = { shirt = { 0.46, 0.40, 0.30 }, pants = { 0.28, 0.26, 0.22 }, skin = SKIN, vest = { 0.95, 0.75, 0.10 },
    hat = { 0.95, 0.75, 0.10 }, brim = true, gun = true, gunLength = 15 },
}
-- The Interns: a white shirt, a lanyard, no gun, the same grey-green skin
-- and red eyes; their arms reach out in front of them (drawn over).
local INTERN = { shirt = { 0.80, 0.80, 0.76 }, pants = { 0.30, 0.30, 0.34 }, skin = SKIN, hair = { 0.35, 0.25, 0.15 },
  gun = true, gunLength = -2 }
-- What an imp leaves behind (corpses.lua draws people).
local IMP_CORPSE = { shirt = { 0.40, 0.24, 0.14 }, pants = { 0.32, 0.18, 0.10 }, skin = { 0.45, 0.28, 0.16 },
  hair = { 0.20, 0.12, 0.08 }, shoes = { 0.20, 0.12, 0.08 } }
local IMP = { body = { 0.58, 0.36, 0.20 }, dark = { 0.36, 0.20, 0.11 }, spike = { 0.90, 0.84, 0.70 } }
local IMP_SCALE = 1.35 -- drawn bigger than a person: a demon, hunched over
-- A Cacodaemon: a floating red ball, a darker hide and lumps, bone horns,
-- one green eye, and a mouth full of teeth.
local CACO = { hide = { 0.78, 0.12, 0.10 }, dark = { 0.42, 0.05, 0.04 }, light = { 1.00, 0.42, 0.34 },
  horn = { 0.92, 0.86, 0.72 }, eye = { 0.35, 0.95, 0.25 }, white = { 0.95, 0.92, 0.85 }, maw = { 0.18, 0.02, 0.02 },
  tongue = { 0.85, 0.35, 0.45 } }
local CACO_LIFT = 12 -- px it is drawn above where it is (its shadow is there): it floats
local carcasses = {} -- { x, y, angle, seed }: dead Cacodaemons, flat on the ground
local MAX_CARCASSES = 40

function Horde.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- A low, wet groan: the possessed spotting somebody.
  bank.groan = make(0.9, 0.7, function(buf)
    buf:tone(0, 0.8, 92, { wave = "saw", amp = 0.4, attack = 0.08, decay = 0.6, sustain = 0.5, vibRate = 5,
      vibDepth = 0.6 })
    buf:tone(0, 0.8, 139, { wave = "saw", amp = 0.2, attack = 0.1, decay = 0.5, vibRate = 4, vibDepth = 0.8 })
    buf:noiseBurst(0, 0.7, { amp = 0.12, decay = 0.4 })
    buf:lowpass(900)
  end)
  -- A screech: an imp out of a vent.
  bank.screech = make(0.5, 0.7, function(buf)
    buf:sweep(0, 0.45, 900, 1500, { wave = "saw", amp = 0.35, decay = 0.25 })
    buf:sweep(0.02, 0.4, 1350, 2100, { wave = "square", amp = 0.15, decay = 0.2 })
    buf:noiseBurst(0, 0.3, { amp = 0.2, decay = 0.1 })
    buf:highpass(500)
  end)
  -- A fireball thrown: a whoosh.
  bank.throw = make(0.45, 0.6, function(buf)
    buf:noiseBurst(0, 0.4, { amp = 0.6, decay = 0.18 })
    buf:sweep(0, 0.35, 220, 120, { wave = "sine", amp = 0.3, decay = 0.15 })
    buf:lowpass(2400)
  end)
  -- And bursting.
  bank.pop = make(0.4, 0.6, function(buf)
    buf:noiseBurst(0, 0.35, { amp = 0.7, decay = 0.09 })
    buf:sweep(0, 0.3, 160, 50, { wave = "sine", amp = 0.5, decay = 0.1 })
    buf:lowpass(1800)
  end)
  -- The chaingun winding up.
  bank.spin = make(0.7, 0.6, function(buf)
    buf:sweep(0, 0.65, 180, 900, { wave = "square", amp = 0.18, decay = 2 })
    buf:sweep(0, 0.65, 90, 450, { wave = "saw", amp = 0.15, decay = 2 })
    buf:lowpass(3000)
  end)
  -- A Cacodaemon waking: a deep, wet, wobbling roar.
  bank.roar = make(1.1, 0.8, function(buf)
    buf:sweep(0, 1.0, 70, 52, { wave = "saw", amp = 0.45, attack = 0.05, decay = 0.8, vibRate = 7, vibDepth = 4 })
    buf:sweep(0, 0.9, 140, 98, { wave = "square", amp = 0.18, attack = 0.08, decay = 0.6, vibRate = 9, vibDepth = 6 })
    buf:noiseBurst(0, 0.9, { amp = 0.25, decay = 0.5 })
    buf:drive(2)
    buf:lowpass(700)
  end)
  -- Its spit: a wet hack and a roar of flame.
  bank.spit = make(0.6, 0.7, function(buf)
    buf:noiseBurst(0, 0.55, { amp = 0.7, decay = 0.25 })
    buf:sweep(0, 0.4, 180, 70, { wave = "saw", amp = 0.35, decay = 0.2 })
    buf:lowpass(1500)
  end)
  -- Its bite: two rows of teeth meeting.
  bank.chomp = make(0.25, 0.7, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 0.8, decay = 0.03 })
    buf:noiseBurst(0.1, 0.1, { amp = 0.9, decay = 0.03 })
    buf:sweep(0.1, 0.12, 200, 80, { wave = "sine", amp = 0.5, decay = 0.05 })
    buf:lowpass(2500)
  end)
  -- Shot in the mouth: a squeal.
  bank.squeal = make(0.4, 0.6, function(buf)
    buf:sweep(0, 0.35, 400, 900, { wave = "saw", amp = 0.3, decay = 0.2, vibRate = 20, vibDepth = 30 })
    buf:lowpass(2200)
  end)
  bank.claw = make(0.2, 0.6, function(buf)
    buf:noiseBurst(0, 0.15, { amp = 0.7, decay = 0.04 })
    buf:highpass(1800)
  end)
  -- A plasma bolt: a short falling zap, and a fizz where it lands.
  bank.plasma = make(0.18, 0.5, function(buf)
    buf:sweep(0, 0.16, 1400, 500, { wave = "square", amp = 0.25, decay = 0.06 })
    buf:noiseBurst(0, 0.05, { amp = 0.2, decay = 0.02 })
    buf:highpass(300)
  end)
  bank.fizz = make(0.2, 0.4, function(buf)
    buf:noiseBurst(0, 0.18, { amp = 0.5, decay = 0.05 })
    buf:highpass(1500)
  end)
  Fireballs.onThrow = function(x, y, kind)
    Horde.play(kind == "plasma" and "plasma" or kind == "spit" and "spit" or "throw", x, y)
  end
  Fireballs.onPop = function(x, y, kind)
    Horde.play(kind == "plasma" and "fizz" or "pop", x, y)
  end
end

function Horde.play(name, x, y, pitch)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch((pitch or 1) * (0.9 + random() * 0.2))
    s:setVolume(0.6 * Audio.volume("weapons"))
    s:play()
  end
end

function Horde.clear()
  shown, said, opened, lastTick, carcasses = {}, {}, {}, 0, {}
  Fireballs.clear()
end

--- Is vent `i` of the map burst open, on this screen?
function Horde.opened(i)
  return opened[i] == true
end

function Horde.update(dt)
  clock = clock + dt
  Fireballs.update(dt)
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
      s.stride = s.stride + math.sqrt(ex * ex + ey * ey) * k
    end
    s.hurt = math.max(0, s.hurt - dt)
  end
  for id, b in pairs(said) do
    b.t = b.t + dt
    if b.t > Horde.sayFor then
      said[id] = nil
    end
  end
end

--- A dead Cacodaemon on the ground: burst flat, its eye shut, its tongue out.
local function drawCarcass(c)
  love.graphics.push()
  love.graphics.translate(c.x, c.y)
  love.graphics.rotate(c.angle)
  love.graphics.setColor(0.30, 0.03, 0.03, 0.7) -- what came out of it
  love.graphics.ellipse("fill", 6, 4, 40, 28, 18)
  love.graphics.setColor(CACO.dark)
  love.graphics.ellipse("fill", 0, 0, 30, 22, 18)
  love.graphics.setColor(CACO.hide[1] * 0.7, CACO.hide[2] * 0.7, CACO.hide[3] * 0.7)
  love.graphics.ellipse("fill", -2, -2, 26, 18, 18)
  love.graphics.setColor(CACO.maw)
  love.graphics.setLineWidth(2)
  love.graphics.line(4, -6, 12, -2) -- its eye, shut
  love.graphics.setLineWidth(1)
  love.graphics.setColor(CACO.tongue)
  love.graphics.ellipse("fill", 30, 6, 10, 5, 10)
  love.graphics.pop()
end

--- The possessed's cones, in Heck's red; the dead Cacodaemons, and the
--- live ones' shadows on the ground under them.
function Horde.drawBelowCars()
  for _, c in ipairs(carcasses) do
    drawCarcass(c)
  end
  for _, s in pairs(shown) do
    if s.kind == "c" then
      love.graphics.setColor(0, 0, 0, 0.3)
      love.graphics.ellipse("fill", s.dx + 6, s.dy + 8, Cacos.RADIUS * 0.9, Cacos.RADIUS * 0.7, 20)
    end
  end
  if Features.any("hideSightCones") then
    return
  end
  for id, s in pairs(shown) do
    local rank = RANK[s.kind]
    if rank then
      local conf = Possessed.RANKS[rank]
      local fov = s.alert and conf.alertFov or conf.fov
      Sight.draw(s.dx, s.dy, s.facing, conf.range, s.alert, clock, fov, { seed = id, color = RED })
    end
  end
end

--- Two red eyes in a possessed face, and the cracks glowing in its skin.
local function drawEyes(s)
  local fx, fy = math.cos(s.facing), math.sin(s.facing)
  local px, py = -fy, fx
  love.graphics.setColor(RED)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.circle("fill", s.dx + fx * 3.5 + px * side * 2, s.dy + fy * 3.5 + py * side * 2, 1.1, 6)
  end
end

--- An imp, seen from above: a hunched brown back with a row of bone spikes
--- down it, long arms with claws out in front, orange eyes; holding a
--- fireball up while it winds up a throw.
local function drawImp(s)
  local a = s.facing
  local fx, fy = math.cos(a), math.sin(a)
  local px, py = -fy, fx
  local x, y = s.dx, s.dy
  local swing = math.sin(s.stride * 0.25) * 3
  local emerge = s.state == 1 and 0.75 or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(IMP_SCALE)
  love.graphics.translate(-x, -y)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x + 3, y + 3, 11 * emerge, 10 * emerge, 14)
  -- Arms, reaching forward, swinging.
  love.graphics.setColor(IMP.dark)
  love.graphics.setLineWidth(3.5)
  for _, side in ipairs({ -1, 1 }) do
    local sx, sy = x + px * side * 7, y + py * side * 7
    local reach = 9 + side * swing * 0.6
    local hx, hy = sx + fx * reach + px * side * 2, sy + fy * reach + py * side * 2
    love.graphics.line(sx, sy, hx, hy)
    love.graphics.setColor(IMP.spike)
    love.graphics.circle("fill", hx + fx * 2, hy + fy * 2, 1.4, 6) -- claws
    love.graphics.setColor(IMP.dark)
  end
  love.graphics.setLineWidth(1)
  -- The body, hunched.
  love.graphics.setColor(IMP.body)
  love.graphics.ellipse("fill", x - fx * 1, y - fy * 1, 9 * emerge, 10 * emerge, 16)
  love.graphics.setColor(IMP.dark)
  love.graphics.circle("fill", x + fx * 5, y + fy * 5, 5 * emerge, 12) -- the head, low
  -- Spikes along the shoulders and down the back.
  love.graphics.setColor(IMP.spike)
  for k = -2, 2 do
    local back, off = k * 2.5 + 1, k % 2 == 0 and 2 or -2
    local bx, by = x - fx * back + px * off, y - fy * back + py * off
    love.graphics.polygon("fill", bx - px * 1.2, by - py * 1.2, bx + px * 1.2, by + py * 1.2, bx - fx * 3.5,
      by - fy * 3.5)
  end
  for _, side in ipairs({ -1, 1 }) do -- the shoulder horns
    local bx, by = x + px * side * 6 + fx * 2, y + py * side * 6 + fy * 2
    local tx, ty = bx + px * side * 4 - fx * 2, by + py * side * 4 - fy * 2
    love.graphics.polygon("fill", bx, by, tx, ty, bx - fx * 2, by - fy * 2)
  end
  -- Eyes.
  love.graphics.setColor(ORANGE)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.circle("fill", x + fx * 8 + px * side * 2, y + fy * 8 + py * side * 2, 1.3, 6)
  end
  if s.state == 2 then -- the fireball, held up: the tell
    local pulse = 0.8 + 0.2 * math.sin(clock * 30)
    local hx, hy = x + fx * 12 + px * 6, y + fy * 12 + py * 6
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
    love.graphics.circle("fill", hx, hy, 11 * pulse, 14)
    love.graphics.setColor(1, 0.85, 0.4)
    love.graphics.circle("fill", hx, hy, 5 * pulse, 12)
  end
  love.graphics.pop()
end

--- How far a Cacodaemon's mouth is open (0..1): opening over its tell, wide
--- as it spits or bites, half shut while it reels.
local function mouthOpen(s)
  if s.state == 2 then
    return math.min(1, (clock - (s.since or clock)) / Cacos.OPEN)
  elseif s.state == 3 then
    return math.min(1, (clock - (s.since or clock)) / Cacos.BITE_OPEN)
  elseif s.state == 4 then
    return 0.5
  end
  return 0.08 + 0.04 * math.sin(clock * 2 + s.dx * 0.01) -- breathing
end

--- A Cacodaemon, seen from above, floating a little over its shadow: a red
--- ball, lit from the top left, lumps on its hide, horns round the back, one
--- green eye and the mouth across its front, fire in it when it's about to
--- spit; spinning when shot in the mouth.
local function drawCaco(s, id)
  local R = Cacos.RADIUS
  local bob = math.sin(clock * 1.7 + id) * 3
  local x, y = s.dx, s.dy - CACO_LIFT + bob
  local reel = s.state == 4
  local a = s.facing + (reel and math.sin(clock * 25) * 0.35 or 0)
  local open = mouthOpen(s)
  -- The ball: its outline, hide and shading (the light stays top left as it turns).
  love.graphics.setColor(CACO.dark)
  love.graphics.circle("fill", x, y, R + 2, 32)
  love.graphics.setColor(CACO.hide)
  love.graphics.circle("fill", x, y, R, 32)
  love.graphics.setColor(CACO.dark[1], CACO.dark[2], CACO.dark[3], 0.45)
  love.graphics.circle("fill", x + R * 0.18, y + R * 0.2, R * 0.82, 28)
  love.graphics.setColor(CACO.hide)
  love.graphics.circle("fill", x - R * 0.08, y - R * 0.1, R * 0.78, 28)
  love.graphics.setColor(CACO.light[1], CACO.light[2], CACO.light[3], 0.55)
  love.graphics.circle("fill", x - R * 0.38, y - R * 0.4, R * 0.28, 16)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(a)
  -- Lumps on its hide.
  love.graphics.setColor(CACO.dark[1], CACO.dark[2], CACO.dark[3], 0.6)
  for k = 0, 6 do
    local la = 1.8 + k * 0.42
    love.graphics.circle("fill", math.cos(la) * R * 0.62, math.sin(la) * R * 0.62, 2.5 + (k % 3), 8)
  end
  -- Horns round the back half, bone, pointing out.
  love.graphics.setColor(CACO.horn)
  for _, ha in ipairs({ 2.2, 2.75, 3.53, 4.08 }) do
    local bx, by = math.cos(ha) * (R - 3), math.sin(ha) * (R - 3)
    local tx, ty = math.cos(ha) * (R + 11), math.sin(ha) * (R + 11)
    local px, py = -math.sin(ha) * 4, math.cos(ha) * 4
    love.graphics.polygon("fill", bx + px, by + py, bx - px, by - py, tx, ty)
  end
  -- The mouth across its front: a seam with teeth, or a maw.
  local mw, md = R * 0.62, 3 + open * R * 0.42
  local mx = R * 0.62
  love.graphics.setColor(CACO.maw)
  love.graphics.ellipse("fill", mx, 0, md, mw, 20)
  if open > 0.3 then
    if s.state == 2 then -- the fire coming up
      local glow = 0.6 + 0.4 * math.sin(clock * 35)
      love.graphics.setColor(1, 0.45, 0.12, 0.9 * open)
      love.graphics.ellipse("fill", mx, 0, md * 0.7 * glow, mw * 0.6 * glow, 16)
      love.graphics.setColor(1, 0.85, 0.5, open)
      love.graphics.ellipse("fill", mx, 0, md * 0.35, mw * 0.3, 12)
    else
      love.graphics.setColor(CACO.tongue)
      love.graphics.ellipse("fill", mx + md * 0.2, 0, md * 0.5, mw * 0.4, 12)
    end
  end
  love.graphics.setColor(CACO.white) -- the teeth, two rows
  for k = -3, 3 do
    local ty = k * mw / 4
    local edge = math.sqrt(math.max(0, 1 - (ty / mw) ^ 2)) * md
    love.graphics.polygon("fill", mx - edge, ty - 2.5, mx - edge, ty + 2.5, mx - edge + 4 + open * 3, ty)
    love.graphics.polygon("fill", mx + edge, ty - 2.5, mx + edge, ty + 2.5, mx + edge - 4 - open * 3, ty)
  end
  -- The eye, on top, looking ahead: wide when it's about to spit, squeezed shut reeling.
  local ex = R * 0.05
  local lid = reel and 0.2 or (s.state == 2 and 1.15 or 0.85)
  love.graphics.setColor(CACO.dark)
  love.graphics.ellipse("fill", ex, 0, 10, 11 * lid + 1, 16)
  love.graphics.setColor(CACO.white)
  love.graphics.ellipse("fill", ex, 0, 8, 9 * lid, 16)
  if lid > 0.4 then
    love.graphics.setColor(CACO.eye)
    love.graphics.circle("fill", ex + 2, 0, 5.5 * math.min(1, lid), 14)
    love.graphics.setColor(0, 0, 0)
    love.graphics.rectangle("fill", ex + 1.2, -4 * lid, 1.8, 8 * lid)
  end
  love.graphics.pop()
end

--- An intern: a person reaching out with both arms, the way they always
--- did for the coffee; up over its head when it is about to claw.
local function drawIntern(s)
  local swing = s.state == 0 and 0 or math.sin(s.stride * 0.2) * 1.6
  local lean = s.state == 0 and math.sin(clock * 1.3 + s.dx * 0.01) * 0.15 or 0
  Body.person(s.dx, s.dy, s.facing + lean, swing, INTERN)
  local a = s.facing + lean
  local fx, fy = math.cos(a), math.sin(a)
  local px, py = -fy, fx
  local up = s.state == 2
  local reach = up and 9 or 13
  love.graphics.setColor(SKIN)
  love.graphics.setLineWidth(2.6)
  for _, side in ipairs({ -1, 1 }) do
    local hx, hy = s.dx + fx * 8 + px * side * 2.2, s.dy + fy * 8 + py * side * 2.2
    local ex = hx + fx * (reach - 8) + px * side * (up and 5 or 2)
    local ey = hy + fy * (reach - 8) + py * side * (up and 5 or 2)
    love.graphics.line(hx, hy, ex, ey)
    love.graphics.circle("fill", ex, ey, up and 2.6 or 2, 8)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.2, 0.35, 0.8) -- the lanyard
  love.graphics.line(s.dx + px * 2, s.dy + py * 2, s.dx + fx * 4, s.dy + fy * 4, s.dx - px * 2, s.dy - py * 2)
  drawEyes(s)
end

local function healthBar(s, max, r, width)
  if s.hp < max then
    local bw, f = width or 20, math.max(0, s.hp / max)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 4, bw * f, 2)
  end
end

--- A speech bubble in Heck's red, its bottom edge at (cx, bottom).
function Horde.drawBubble(cx, bottom, text)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local w = math.min(220, font:getWidth(text) + 14)
  local _, lines = font:getWrap(text, w - 10)
  local h = #lines * font:getHeight() + 8
  local x, y = cx - w / 2, bottom - h
  love.graphics.setColor(0.08, 0.02, 0.02, 0.8)
  love.graphics.rectangle("fill", x, y, w, h, 4)
  love.graphics.setColor(RED[1], RED[2], RED[3], 0.8)
  love.graphics.rectangle("line", x, y, w, h, 4)
  love.graphics.setColor(1, 0.85, 0.8)
  love.graphics.printf(text, x + 5, y + 4, w - 10, "center")
end

function Horde.drawAboveCars()
  for _, s in pairs(shown) do
    local rank = RANK[s.kind]
    if rank then
      local swing = s.state == 0 and 0 or math.sin(s.stride * 0.18) * 1.4 -- a shamble
      Body.person(s.dx, s.dy, s.facing, swing, LOOK[rank])
      drawEyes(s)
      if rank == "overtime" and s.spinT and clock - s.spinT < 1.2 then
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.7) -- the barrels, hot
        love.graphics.circle("fill", s.dx + math.cos(s.facing) * 22, s.dy + math.sin(s.facing) * 22, 3, 8)
      end
      healthBar(s, Possessed.RANKS[rank].health, Body.SHOULDERS)
    elseif s.kind == "z" then
      drawIntern(s)
      healthBar(s, Interns.HEALTH, Body.SHOULDERS)
    elseif s.kind == "i" then
      drawImp(s)
      healthBar(s, Imps.HEALTH, Imps.RADIUS)
    end
    if s.hurt > 0 and s.kind ~= "c" then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.6)
      love.graphics.circle("fill", s.dx, s.dy, Body.SHOULDERS + 1, 12)
    end
  end
  for id, s in pairs(shown) do -- the Cacodaemons float over everyone
    if s.kind == "c" then
      drawCaco(s, id)
      if s.hurt > 0 then
        love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.5)
        love.graphics.circle("fill", s.dx, s.dy - CACO_LIFT, Cacos.RADIUS + 2, 24)
      end
      healthBar(s, Cacos.HEALTH, Cacos.RADIUS, 44)
    end
  end
  Fireballs.draw()
  for id, b in pairs(said) do
    local s = shown[id]
    if s then
      local over = s.kind == "c" and Cacos.RADIUS + CACO_LIFT + 4 or Body.SHOULDERS
      Horde.drawBubble(s.dx, s.dy - over - 14, b.text)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Horde.drawNightLights(glow)
  for _, s in pairs(shown) do
    -- Lit from inside, as everything of Heck's is: you see them in the dark
    -- before they see you.
    if s.kind == "i" then
      glow(s.dx, s.dy, s.state == 2 and 110 or 60, ORANGE, s.state == 2 and 1 or 0.7)
    elseif s.kind == "c" then
      glow(s.dx, s.dy - CACO_LIFT, 120, RED, 0.7)
      glow(s.dx, s.dy - CACO_LIFT, 30, CACO.eye, 0.6)
      if s.state == 2 then -- the fire in its mouth
        glow(s.dx + math.cos(s.facing) * 18, s.dy - CACO_LIFT + math.sin(s.facing) * 18, 150, ORANGE, 1)
      end
    else
      glow(s.dx, s.dy, 52, RED, 0.75)
    end
  end
  Fireballs.drawNightLights(glow)
end

--- The open vents on `map`: a black hole where the grille was, the grille
--- bent back off it (a manhole's cover thrown aside, a crack torn open).
--- Under everyone.
function Horde.drawVents(map)
  for i, v in ipairs(map and map.horde and map.horde.vents or {}) do
    if opened[i] and v.look == "crack" then -- a crack in the road, torn wide open, Heck glowing in it
      love.graphics.setColor(0.08, 0.02, 0.01)
      love.graphics.ellipse("fill", v.x, v.y, 28, 18, 16)
      love.graphics.setColor(1, 0.35, 0.05, 0.85)
      love.graphics.ellipse("fill", v.x, v.y, 16, 7, 12)
      love.graphics.setColor(1, 0.8, 0.3, 0.9)
      love.graphics.ellipse("fill", v.x, v.y, 7, 3, 10)
    elseif opened[i] and v.look == "manhole" then -- the hole, the cover thrown aside
      love.graphics.setColor(0.05, 0.02, 0.02)
      love.graphics.circle("fill", v.x, v.y, 20, 20)
      local lx, ly = v.x + math.cos(v.out + 0.7) * 38, v.y + math.sin(v.out + 0.7) * 38
      love.graphics.setColor(0.25, 0.16, 0.15)
      love.graphics.circle("fill", lx, ly, 19, 20)
      love.graphics.setColor(0.40, 0.28, 0.26)
      love.graphics.circle("line", lx, ly, 15, 20)
    elseif opened[i] then
      love.graphics.setColor(0.05, 0.02, 0.02)
      love.graphics.rectangle("fill", v.x - 22, v.y - 16, 44, 32, 4)
      love.graphics.setColor(0.35, 0.10, 0.06, 0.8)
      love.graphics.rectangle("line", v.x - 22, v.y - 16, 44, 32, 4)
      love.graphics.setColor(0.45, 0.32, 0.30)
      love.graphics.push()
      love.graphics.translate(v.x + math.cos(v.out) * 30, v.y + math.sin(v.out) * 30)
      love.graphics.rotate(v.out + 0.6)
      love.graphics.rectangle("fill", -20, -6, 40, 12)
      love.graphics.setColor(0.25, 0.16, 0.15)
      for k = -16, 16, 8 do
        love.graphics.rectangle("fill", k, -5, 3, 10)
      end
      love.graphics.pop()
    end
  end
end

function Horde.walkers()
  local list = {}
  for id, s in pairs(shown) do
    if s.kind ~= "c" then -- the Cacodaemons float
      list[#list + 1] = { key = "hrd" .. id, x = s.dx, y = s.dy, size = "person" }
    end
  end
  return list
end

Horde.clientMessages = {
  HRD_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, kind, x, y = tonumber(args[i]), args[i + 1], tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y then
        local s = shown[id]
        if not s then
          local max = RANK[kind] and Possessed.RANKS[RANK[kind]].health
            or (kind == "z" and Interns.HEALTH or kind == "c" and Cacos.HEALTH or Imps.HEALTH)
          s = { kind = kind, dx = x, dy = y, stride = 0, hurt = 0, hp = max }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 4]) or s.facing or 0
        local hp = tonumber(args[i + 5]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        local state = tonumber(args[i + 6]) or 0
        if state ~= s.state then
          s.since = clock
        end
        s.state = state
        s.alert = args[i + 7] == "1"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  HRD_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y and args[5] == "c" then -- a Cacodaemon comes down and bursts
      carcasses[#carcasses + 1] = { x = s and s.dx or x, y = s and s.dy or y, angle = angle }
      if #carcasses > MAX_CARCASSES then
        table.remove(carcasses, 1)
      end
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.6)
      end
    elseif x and y then
      local rank = RANK[args[5]]
      local look = rank and LOOK[rank] or (args[5] == "z" and INTERN or IMP_CORPSE)
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, look)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, rank and 0.9 or 1.2)
      end
    end
  end,
  HRD_SAY = function(_client, args)
    local id = tonumber(args[1])
    local s = id and shown[id]
    if not s then
      return
    end
    local side = s.kind == "i" and "imp" or s.kind == "z" and "intern" or s.kind == "c" and "caco" or "possessed"
    local lines = Story.horde[side][args[2]]
    local text = lines and lines[tonumber(args[3]) or 0]
    if text then
      said[id] = { text = text, t = 0 }
    end
    if args[2] == "alert" then
      local sound = side == "imp" and "screech" or side == "caco" and "roar" or "groan"
      Horde.play(sound, s.dx, s.dy, side == "intern" and 1.25 or 1)
    end
  end,
  HRD_VENT = function(_client, args)
    local i = tonumber(args[1])
    if i then
      opened[i] = true
    end
  end,
  HRD_SPIN = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.spinT = clock
      Horde.play("spin", s.dx, s.dy)
    end
  end,
  HRD_CLAW = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      Horde.play(s.kind == "c" and "chomp" or "claw", s.dx, s.dy)
    end
  end,
  HRD_REEL = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      Horde.play("squeal", s.dx, s.dy)
    end
  end,
}
for kind, handler in pairs(Fireballs.clientMessages) do
  Horde.clientMessages[kind] = handler
end

return Horde
