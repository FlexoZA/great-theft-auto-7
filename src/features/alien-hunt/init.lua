-- The alien hunt: the second boss quest. Wild Man Wendell (wild hair,
-- wilder eyes, lunch down his shirt) is sure aliens are harvesting human
-- hair to eat, and takes everyone into the forest (city-map's "forest") to
-- find where they land.
--
-- Part one: follow him. He walks the trail through five clearings
-- (`map.waypoints`), waiting whenever nobody keeps up. At each of the first
-- four a squirrel comes for him out of the trees (an alien spy, obviously)
-- and bites until it is shot; he only moves on once it is down. If the
-- squirrels bite him flat he faints, comes round a few seconds later, and
-- another one comes for him at the same stop.
--
-- Part two: the fifth clearing is Bigfoot's. Wendell's portrait comes up
-- once more (he wanted aliens, not Bigfoot) and he vanishes; then Bigfoot's
-- does, roaring, and the fight is on. Bigfoot chases whoever is nearest and
-- swipes at them, and every few seconds crouches and leaps at them: a ring
-- on the ground shows where he will come down, and everyone inside it when
-- he lands is hurt. Bullets pass under him while he is in the air. When he
-- goes down he spills a pile of koins and the quest is done.
--
-- The quests feature brings everyone to the forest and raises
-- `serverQuestStarted` / `questStarted` for the quest whose `boss` is
-- "alien-hunt": the host starts the walk, and every client puts up the
-- wild man's title screen. Everything goes away when the group leaves.
--
-- The host owns all of it: the stage, the wild man, the squirrel, Bigfoot.
-- Clients hear the stage reliably and positions at 15 Hz, and draw.
--
-- Messages
--   server -> all  HNT_STAGE <stage> <waypoint>          none | follow | defend | faint | reveal | fight | done
--   server -> all  HNT_STATE <tick> [m <x> <y> <facing> <hp>] [s <x> <y> <facing> <hp>]
--                            [b <x> <y> <facing> <hp> <mode> <swipe>]   (unreliable, 15 Hz; a group left out is gone)
--   server -> all  HNT_SAY   <pool> <index>                the wild man says something (Hunt.lines[pool][index])
--   server -> all  HNT_SQ    <x> <y>                       a squirrel came out of the trees
--   server -> all  HNT_SQ_DOWN <x> <y> <angle>             it was shot
--   server -> all  HNT_MAN_GONE <x> <y>                    the wild man vanished
--   server -> all  HNT_LEAP  <fx> <fy> <tx> <ty> <seconds> <radius>  Bigfoot took off; he lands on (tx, ty)
--   server -> all  HNT_SLAM  <x> <y> <radius> [<playerId>]...  he landed; these were caught in it
--   server -> all  HNT_DOWN  <x> <y> <angle> <playerId>    Bigfoot went down (0 = nobody's kill)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local WildFace = require("src.features.alien-hunt.wildman_face")
local FootFace = require("src.features.alien-hunt.bigfoot_face")
local Screen = require("src.features.alien-hunt.screen")
local Sounds = require("src.features.alien-hunt.sounds")

local Hunt = {
  name = "alien-hunt",
  priority = 975, -- the portraits go over every other HUD (karen is 970)
}

-- Tuning ------------------------------------------------------------------
Hunt.questId = "alien-hunt"
Hunt.manSpeed = 62 -- px/s; a brisk walk, slower than a sprint
Hunt.manHealth = 100
Hunt.manRadius = 7
Hunt.followRange = 360 -- px; further than this from everyone and he waits
Hunt.startDelay = 4 -- seconds he waits before setting off
Hunt.faintTime = 4 -- seconds flat on his back before he gets up again
Hunt.squirrelHealth = 30 -- two pistol rounds
Hunt.squirrelSpeed = 150 -- px/s
Hunt.squirrelRadius = 7 -- px; generous for something that small, so it can be hit
Hunt.squirrelBite = 7
Hunt.squirrelBiteEvery = 0.8 -- seconds
Hunt.squirrelSpawn = 300 -- px from the clearing it comes from
Hunt.revealTime = 7 -- seconds of portraits before Bigfoot moves
Hunt.manLeavesAt = 3.5 -- seconds into those when Wendell vanishes

Hunt.footHealth = 1800 -- ninety pistol rounds
Hunt.footRadius = 22
Hunt.footSpeed = 105 -- px/s; you can outrun him sprinting, not walking
Hunt.aggroRange = 1100
Hunt.swipeReach = 22 -- px past his body a swipe lands
Hunt.swipeDamage = 16
Hunt.swipeEvery = 1.4
Hunt.leapEvery = 5 -- seconds between leaps
Hunt.leapRange = 620 -- px; he leaps at anyone this close, even right next to him
Hunt.crouchTime = 0.6 -- seconds he crouches before he goes
Hunt.airTime = 1.0 -- seconds in the air
Hunt.recoverTime = 0.8 -- seconds getting up after landing
Hunt.slamRadius = 125
Hunt.slamDamage = 30
Hunt.bulletDamage = 20 -- what one round takes off him (matches the pistol)
Hunt.drops = 40 -- koins he spills

Hunt.introTime = 12 -- seconds the title screen stays up unless a key is pressed
Hunt.sayTime = 3.2 -- seconds a line hangs over his head

-- What Wendell says, by occasion.
Hunt.lines = {
  go = {
    "They land out here every full moon. Or every Tuesday. One of those.",
    "They took my cousin's mullet. Slurped it right off his head like spaghetti.",
    "Smell that? Ozone. ALIEN ozone.",
    "Don't look up. They like it when you look up.",
    "Human hair is a delicacy where they come from. Like caviar. Hairy caviar.",
    "This stain? Evidence. Don't touch it.",
    "I shaved my eyebrows once so they'd leave me alone. Didn't work.",
    "Keep your hat on. Keep your hat ON.",
  },
  wait = {
    "Keep up! They can smell hesitation!",
    "Hurry! Your hair is showing!",
    "Hello? HELLO? Don't leave me alone with the trees!",
  },
  squirrel = {
    "SQUIRREL! It's working for THEM!",
    "That's no squirrel, that's a probe with a tail!",
    "Alien spy! Shoot it! SHOOT IT!",
    "It's after my hair! GET IT OFF ME!",
    "Look at its little eyes. Pure evil.",
  },
  win = {
    "Ha! Tell your masters Wendell sent you!",
    "One less spy. Onwards!",
    "Good. Now we move, before its friends come.",
  },
  faint = { "Tell... my hair... I loved it..." },
  up = { "I'm up! I'm up! Where'd it go?!" },
}

-- The title screen, and the two portraits before the fight.
local INTRO = {
  kicker = "QUEST",
  title = "THE TRUTH IS OUT THERE",
  subtitle = "...in the woods, apparently.",
  speech = "Psst! You! Yeah, you, with the HAIR. The aliens are back and they're HARVESTING it. Human hair! "
    .. "For FOOD! I know where they land. Follow me into the forest, and watch out for the squirrels. "
    .. "They're in on it.",
}
local WENDELL_QUITS = {
  kicker = "WILD MAN WENDELL",
  title = "BIGFOOT?!",
  subtitle = "is not what he signed up for.",
  speech = "Bigfoot?! BIGFOOT?! I came out here for ALIENS, not some overgrown doormat with feet! "
    .. "Forget this. I'm going home!",
}
local BIGFOOT_ROARS = {
  kicker = "BOSS",
  title = "BIGFOOT",
  subtitle = "is very, very ugly.",
  speech = "ROAAAR!",
}
local WILD_LOOK = {
  bg = { 0.04, 0.08, 0.05 },
  ray = { 0.10, 0.22, 0.12 },
  titleColor = { 0.55, 1, 0.45 },
  speechColor = { 0.10, 0.20, 0.08 },
}
local FOOT_LOOK = {
  bg = { 0.10, 0.04, 0.02 },
  ray = { 0.28, 0.12, 0.05 },
  titleColor = { 1, 0.55, 0.25 },
  speechColor = { 0.45, 0.10, 0.02 },
}

local SYNC_EVERY = 2 -- server ticks between HNT_STATE packets
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 150 -- px; a jump this big is a spawn, not a step
local MODES = { idle = "i", walk = "w", crouch = "c", air = "a", recover = "r" }
local MODE_NAMES = { i = "idle", w = "walk", c = "crouch", a = "air", r = "recover" }
local SHIRT = { 0.86, 0.84, 0.74 }
local HAIR = { 0.62, 0.58, 0.52 }
local SKIN = { 0.88, 0.70, 0.55 }
local FUR = { 0.42, 0.28, 0.16 }
local FUR_DARK = { 0.28, 0.18, 0.10 }
local SQUIRREL = { 0.55, 0.36, 0.22 }
local SQUIRREL_LIGHT = { 0.72, 0.52, 0.34 }

local function fmt(v)
  return ("%.1f"):format(v)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server --------------------------------------------------------------------

local sv = nil -- { stage, wp, node, timer, man, squirrel, foot, syncIn, left }

local function fresh()
  return { stage = nil, wp = 0, node = 0, timer = 0, man = nil, squirrel = nil, foot = nil, syncIn = 0 }
end

function Hunt:serverStart()
  sv = fresh()
end

local function setStage(server, stage)
  sv.stage = stage
  server:broadcast(Protocol.encode("HNT_STAGE", stage or "none", sv.wp))
end

local function say(server, pool)
  local lines = Hunt.lines[pool]
  server:broadcast(Protocol.encode("HNT_SAY", pool, love.math.random(#lines)))
  if sv.man then
    sv.man.sayTimer = 5 + love.math.random() * 4
  end
end

--- The quest brought everyone to the forest: Wendell at the start of the
--- trail, heading for the first clearing.
function Hunt:serverQuestStarted(server, quest)
  local map = cityMap()
  if not (sv and quest.boss == self.questId and map and map.trail) then
    return
  end
  local start = map.trail[1]
  sv = fresh()
  sv.wp, sv.node, sv.timer = 1, 2, self.startDelay
  sv.man = { x = start.x, y = start.y, facing = -math.pi / 2, hp = self.manHealth, sayTimer = 2 }
  setStage(server, "follow")
end

--- Everything leaves with the group, or with a map change of any kind.
function Hunt:stop(server)
  if sv and sv.stage then
    sv = fresh()
    setStage(server, nil)
  end
end

function Hunt:serverQuestEnded(server)
  self:stop(server)
end

function Hunt:mapChanged(_map, server)
  if server then
    self:stop(server)
  end
end

function Hunt:serverPlayerJoined(server, player)
  if sv and sv.stage then
    server:send(player, Protocol.encode("HNT_STAGE", sv.stage, sv.wp))
  end
end

--- Something froze the world around (x, y): the squirrel and Bigfoot stand
--- still if caught in it (Bigfoot not while in the air).
--- Something stinks at (x, y) (the `serverPanicArea` event, raised every
--- tick a cloud hangs): the squirrel and Bigfoot (on the ground) run from
--- it for a moment.
function Hunt:serverPanicArea(_server, x, y, radius)
  if not sv then
    return
  end
  local s = sv.squirrel
  if s and dist2(s.x, s.y, x, y) <= (radius + self.squirrelRadius) ^ 2 then
    s.panic = { x = x, y = y, left = 0.5 }
  end
  local f = sv.foot
  if f and f.mode ~= "air" and f.mode ~= "crouch" and dist2(f.x, f.y, x, y) <= (radius + self.footRadius) ^ 2 then
    f.panic = { x = x, y = y, left = 0.5 }
  end
end

function Hunt:serverFreezeArea(_server, x, y, radius, seconds)
  if not sv then
    return
  end
  local s = sv.squirrel
  if s and dist2(s.x, s.y, x, y) <= (radius + self.squirrelRadius) ^ 2 then
    s.frozen = math.max(s.frozen, seconds)
  end
  local f = sv.foot
  if f and f.mode ~= "air" and dist2(f.x, f.y, x, y) <= (radius + self.footRadius) ^ 2 then
    f.frozen = math.max(f.frozen, seconds)
  end
end

--- Every player's body this tick, and the nearest one to (x, y).
local function nearestBody(server, x, y)
  local best, bestD2, bx, by, onFoot
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local px, py, foot = Features.bodyPose(server, p)
      local d2 = dist2(px, py, x, y)
      if not bestD2 or d2 < bestD2 then
        best, bestD2, bx, by, onFoot = p, d2, px, py, foot
      end
    end
  end
  return best, bestD2, bx, by, onFoot
end

local function hurtPlayer(server, player, amount, angle)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, player, nil, amount, angle)
  end
end

--- A squirrel comes out of the trees at the clearing, from any side but
--- straight down the trail.
local function spawnSquirrel(server, at)
  local a = love.math.random() * math.pi * 2
  local x, y = at.x + math.cos(a) * Hunt.squirrelSpawn, at.y + math.sin(a) * Hunt.squirrelSpawn
  sv.squirrel = { x = x, y = y, facing = a + math.pi, hp = Hunt.squirrelHealth, bite = 0.5, zig = 0, hop = 0,
    frozen = 0 }
  server:broadcast(Protocol.encode("HNT_SQ", fmt(x), fmt(y)))
  say(server, "squirrel")
end

--- Wendell's walk: to the next trail node, unless nobody is keeping up.
function Hunt:stepFollow(server, dt)
  local map = cityMap()
  local m = sv.man
  sv.timer = sv.timer - dt
  local _, d2 = nearestBody(server, m.x, m.y)
  if sv.timer > 0 or not d2 or d2 > self.followRange ^ 2 then
    m.walking = false
    if d2 and d2 > self.followRange ^ 2 and m.sayTimer <= 0 then
      say(server, "wait")
    end
    return
  end
  m.walking = true
  local node = map.trail[sv.node]
  local d = math.sqrt(dist2(node.x, node.y, m.x, m.y))
  local step = self.manSpeed * dt
  m.facing = math.atan2(node.y - m.y, node.x - m.x)
  if d > step then
    m.x, m.y = m.x + math.cos(m.facing) * step, m.y + math.sin(m.facing) * step
    if m.sayTimer <= 0 then
      say(server, "go")
    end
    return
  end
  m.x, m.y = node.x, node.y
  sv.node = sv.node + 1
  if not node.wp then
    return
  end
  m.walking = false
  if sv.wp >= #map.waypoints then
    self:startReveal(server, map)
  else
    spawnSquirrel(server, node)
    setStage(server, "defend")
  end
end

--- The squirrel's tick: zigzag in, bite, hop back, come again.
function Hunt:stepSquirrel(server, dt)
  local s, m = sv.squirrel, sv.man
  if not s then
    return
  end
  if s.frozen > 0 then
    s.frozen = s.frozen - dt
    return
  end
  if s.panic then
    -- A stink: straight away from it.
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    s.x, s.y = s.x + math.cos(s.facing) * self.squirrelSpeed * dt, s.y + math.sin(s.facing) * self.squirrelSpeed * dt
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end
  s.bite = s.bite - dt
  local ang = math.atan2(m.y - s.y, m.x - s.x)
  if s.hop > 0 then
    s.hop = s.hop - dt
    s.facing = ang + math.pi
    s.x, s.y = s.x - math.cos(ang) * self.squirrelSpeed * dt, s.y - math.sin(ang) * self.squirrelSpeed * dt
    return
  end
  local reach = self.manRadius + self.squirrelRadius + 3
  if dist2(s.x, s.y, m.x, m.y) > reach * reach then
    s.zig = s.zig + dt
    s.facing = ang + math.sin(s.zig * 7) * 0.7
    s.x = s.x + math.cos(s.facing) * self.squirrelSpeed * dt
    s.y = s.y + math.sin(s.facing) * self.squirrelSpeed * dt
  elseif s.bite <= 0 and sv.stage == "defend" then
    s.bite, s.hop = self.squirrelBiteEvery, 0.3
    s.facing = ang
    m.hp = m.hp - self.squirrelBite
    if m.hp <= 0 then
      m.hp = 0
      sv.timer = self.faintTime
      say(server, "faint")
      setStage(server, "faint")
    end
  end
end

--- The fifth clearing: Wendell sees who lives here. Bigfoot stands at the
--- far side while the portraits are up.
function Hunt:startReveal(server, map)
  local lair = map.lair
  sv.timer = self.revealTime
  sv.foot = {
    x = lair.x,
    y = lair.y - map.lairRadius * 0.55,
    facing = math.pi / 2,
    hp = self.footHealth,
    mode = "idle",
    timer = 0,
    frozen = 0,
    swipeTimer = 1,
    swipe = 0,
    leapTimer = self.leapEvery * 0.5,
    stuck = 0,
    sidestep = 0,
    side = 1,
  }
  setStage(server, "reveal")
end

--- Solid ground, through the `blocksPoint` convention, at the four
--- extremes of Bigfoot's body.
local function blockedAt(x, y)
  local r = Hunt.footRadius
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a trunk is slid along. Landed in
--- something, he walks out of it.
local function walk(f, angle, speed, dt)
  local px, py = f.x, f.y
  local free = blockedAt(f.x, f.y)
  local nx = f.x + math.cos(angle) * speed * dt
  if free or not blockedAt(nx, f.y) then
    f.x = nx
  end
  local ny = f.y + math.sin(angle) * speed * dt
  if free or not blockedAt(f.x, ny) then
    f.y = ny
  end
  if dist2(f.x, f.y, px, py) < (speed * dt * 0.4) ^ 2 then
    f.stuck = f.stuck + dt
  else
    f.stuck = 0
  end
end

--- He comes down: everyone inside the ring is hurt and told so.
function Hunt:slam(server, f)
  local caught = {}
  for id, p in pairs(server.players) do
    if Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local pad = onFoot and 7 or 12
      if dist2(x, y, f.x, f.y) <= (self.slamRadius + pad) ^ 2 then
        caught[#caught + 1] = id
        hurtPlayer(server, p, self.slamDamage, math.atan2(y - f.y, x - f.x))
      end
    end
  end
  server:broadcast(Protocol.encode("HNT_SLAM", fmt(f.x), fmt(f.y), self.slamRadius, unpack(caught)))
end

--- Bigfoot's tick: in the air, frozen, crouching, getting up, or after
--- whoever is nearest.
function Hunt:stepFoot(server, dt)
  local f = sv.foot
  f.swipe = math.max(0, f.swipe - dt)
  f.swipeTimer = f.swipeTimer - dt
  if f.mode == "air" then
    f.timer = f.timer - dt
    local k = math.min(1, 1 - f.timer / self.airTime)
    f.x, f.y = f.fx + (f.tx - f.fx) * k, f.fy + (f.ty - f.fy) * k
    if f.timer <= 0 then
      f.x, f.y = f.tx, f.ty
      f.mode, f.timer = "recover", self.recoverTime
      self:slam(server, f)
    end
    return
  end
  if f.frozen > 0 then
    f.frozen = f.frozen - dt
    f.mode = "idle"
    return
  end
  if f.panic and f.mode ~= "crouch" then
    -- A stink: he lumbers away from it, whoever is about.
    f.panic.left = f.panic.left - dt
    f.mode = "walk"
    f.facing = math.atan2(f.y - f.panic.y, f.x - f.panic.x)
    walk(f, f.facing, self.footSpeed, dt)
    if f.panic.left <= 0 then
      f.panic = nil
    end
    return
  end
  if f.mode == "crouch" then
    f.timer = f.timer - dt
    if f.timer <= 0 then
      local target = f.target and server.players[f.target]
      if target and Features.present(target) then
        f.tx, f.ty = Features.bodyPose(server, target)
      end
      f.fx, f.fy = f.x, f.y
      f.mode, f.timer = "air", self.airTime
      f.facing = math.atan2(f.ty - f.y, f.tx - f.x)
      f.leapTimer = self.leapEvery
      server:broadcast(Protocol.encode("HNT_LEAP", fmt(f.fx), fmt(f.fy), fmt(f.tx), fmt(f.ty), self.airTime,
        self.slamRadius))
    end
    return
  end
  if f.mode == "recover" then
    f.timer = f.timer - dt
    if f.timer <= 0 then
      f.mode = "walk"
    end
    return
  end

  local target, d2, tx, ty, onFoot = nearestBody(server, f.x, f.y)
  if not (target and d2 <= self.aggroRange ^ 2) then
    f.mode = "idle"
    return
  end
  f.mode = "walk"
  f.facing = math.atan2(ty - f.y, tx - f.x)
  f.leapTimer = f.leapTimer - dt
  local dist = math.sqrt(d2)
  if f.leapTimer <= 0 and dist <= self.leapRange then
    f.mode, f.timer, f.target = "crouch", self.crouchTime, target.id
    f.tx, f.ty = tx, ty
    return
  end
  local reach = self.footRadius + self.swipeReach + (onFoot and 0 or 10)
  if dist > reach then
    if f.sidestep > 0 then
      f.sidestep = f.sidestep - dt
      walk(f, f.facing + f.side * math.pi / 2, self.footSpeed, dt)
    else
      walk(f, f.facing, self.footSpeed, dt)
      if f.stuck > 0.4 then
        f.stuck, f.sidestep, f.side = 0, 0.6, -f.side
      end
    end
  elseif f.swipeTimer <= 0 then
    f.swipeTimer, f.swipe = self.swipeEvery, 0.25
    hurtPlayer(server, target, self.swipeDamage, f.facing)
  end
end

function Hunt:serverStep(server, dt)
  if not (sv and sv.stage) then
    return
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn < 0 then
    sv.syncIn = SYNC_EVERY - 1
  end
  local m = sv.man
  if m then
    m.sayTimer = m.sayTimer - dt
  end
  local stage = sv.stage
  if stage == "follow" then
    self:stepFollow(server, dt)
  elseif stage == "defend" then
    self:stepSquirrel(server, dt)
  elseif stage == "faint" then
    self:stepSquirrel(server, dt) -- it keeps prowling, but leaves him be
    sv.timer = sv.timer - dt
    if sv.timer <= 0 then
      m.hp = self.manHealth
      say(server, "up")
      if not sv.squirrel then
        spawnSquirrel(server, cityMap().waypoints[sv.wp])
      end
      setStage(server, "defend")
    end
  elseif stage == "reveal" then
    local before = sv.timer
    sv.timer = sv.timer - dt
    local leaveAt = self.revealTime - self.manLeavesAt
    if m and before > leaveAt and sv.timer <= leaveAt then
      server:broadcast(Protocol.encode("HNT_MAN_GONE", fmt(m.x), fmt(m.y)))
      sv.man = nil
    end
    if sv.timer <= 0 then
      sv.man = nil
      setStage(server, "fight")
    end
  elseif stage == "fight" then
    self:stepFoot(server, dt)
  end
  self:sync(server)
end

--- Where everything is, to everyone.
function Hunt:sync(server)
  if sv.syncIn > 0 then
    return
  end
  local parts = { server.tick }
  local function add(...)
    for _, v in ipairs({ ... }) do
      parts[#parts + 1] = v
    end
  end
  local m, s, f = sv.man, sv.squirrel, sv.foot
  if m then
    add("m", fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing), math.max(0, math.floor(m.hp)))
  end
  if s then
    add("s", fmt(s.x), fmt(s.y), ("%.2f"):format(s.facing), math.max(0, math.floor(s.hp)))
  end
  if f then
    add("b", fmt(f.x), fmt(f.y), ("%.2f"):format(f.facing), math.max(0, math.floor(f.hp)), MODES[f.mode],
      f.swipe > 0 and 1 or 0)
  end
  local msg = Protocol.encode("HNT_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    server:send(player, msg, true)
  end
end

--- Bigfoot takes `amount`. Returns true if that finished him.
function Hunt:hurtFoot(server, amount, by, angle)
  local f = sv.foot
  f.hp = f.hp - amount
  if f.hp > 0 then
    return false
  end
  local x, y = f.x, f.y
  sv.foot = nil
  server:broadcast(Protocol.encode("HNT_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0), by or 0))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, self.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, self.questId)
  end
  setStage(server, "done")
  return true
end

--- A bullet passing through (x, y): the `serverShotAt` convention. It hits
--- the squirrel, or Bigfoot when he is on the ground; Wendell it misses.
function Hunt:serverShotAt(server, x, y, radius, by, angle)
  if not sv then
    return false
  end
  by = by ~= 0 and by or nil
  local s = sv.squirrel
  if s and dist2(s.x, s.y, x, y) < (radius + self.squirrelRadius + 3) ^ 2 then
    s.hp = s.hp - self.bulletDamage
    if s.hp <= 0 then
      sv.squirrel = nil
      server:broadcast(Protocol.encode("HNT_SQ_DOWN", fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
      Features.call("serverKill", server, { kind = "animal", x = s.x, y = s.y, by = by, angle = angle })
      if sv.stage == "defend" then
        sv.wp = sv.wp + 1
        say(server, "win")
        setStage(server, "follow")
      end
    end
    return true
  end
  local f = sv.foot
  if f and sv.stage == "fight" and f.mode ~= "air" and dist2(f.x, f.y, x, y) < (radius + self.footRadius) ^ 2 then
    self:hurtFoot(server, self.bulletDamage, by, angle)
    return true
  end
  return false
end

--- For tests.
function Hunt.server()
  return sv
end

-- Client --------------------------------------------------------------------

Hunt.stage = nil -- the stage, from the host
Hunt.wp = 0 -- the clearing Wendell is heading for or standing in
Hunt.man = nil -- { x, y, dx, dy, angle, hp, say, sayTimer, bob }
Hunt.squirrel = nil -- { x, y, dx, dy, angle, hp }
Hunt.foot = nil -- { x, y, dx, dy, angle, hp, mode, swipe, bob }
Hunt.leap = nil -- { fx, fy, tx, ty, t, total, r } while he is in the air
Hunt.pages = {} -- portraits waiting to be shown, the first one up: { face, spec, look, t, roar, keep }
Hunt.rings = {} -- { x, y, r, t }: slams that just landed
Hunt.poofs = {} -- { x, y, t }: where Wendell vanished
Hunt.stain = nil -- { x, y, angle } where Bigfoot went down
Hunt.shake = 0 -- seconds of camera shake left
local wildFace, footFace = nil, nil
local time, lastTick = 0, 0

local function clear()
  Hunt.stage, Hunt.wp = nil, 0
  Hunt.man, Hunt.squirrel, Hunt.foot, Hunt.leap, Hunt.stain = nil, nil, nil, nil, nil
  Hunt.pages, Hunt.rings, Hunt.poofs = {}, {}, {}
  Hunt.shake = 0
end

function Hunt:load()
  Sounds.load()
end

function Hunt:exitGame()
  clear()
  lastTick = 0
end

local function page(face, spec, look, seconds, roar, keep)
  Hunt.pages[#Hunt.pages + 1] = { face = face, spec = spec, look = look, t = seconds, roar = roar, keep = keep }
end

--- The quest brought everyone to the forest: Wendell's title screen.
function Hunt:questStarted(_client, quest)
  if quest.boss ~= self.questId then
    return
  end
  wildFace = wildFace or WildFace.new()
  footFace = footFace or FootFace.new()
  clear()
  page(wildFace, INTRO, WILD_LOOK, self.introTime)
end

function Hunt:questEnded(_client, quest)
  if quest.boss == self.questId then
    clear()
  end
end

local function ease(e, k)
  local ex, ey = e.x - e.dx, e.y - e.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    e.dx, e.dy = e.x, e.y
  else
    e.dx, e.dy = e.dx + ex * k, e.dy + ey * k
  end
end

function Hunt:update(dt, _client, camera)
  time = time + dt
  local p = self.pages[1]
  if p then
    if p.roar then
      p.roar = false
      local f = self.foot
      Sounds.play("roar", f and f.dx or camera.x, f and f.dy or camera.y)
    end
    p.face:update(dt)
    p.t = p.t - dt
    if p.t <= 0 then
      table.remove(self.pages, 1)
    end
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, e in pairs({ man = self.man, squirrel = self.squirrel, foot = self.foot }) do
    ease(e, k)
  end
  if self.man then
    self.man.sayTimer = math.max(0, self.man.sayTimer - dt)
  end
  local leap = self.leap
  if leap then
    leap.t = leap.t + dt
    if leap.t > leap.total + 0.5 then
      self.leap = nil -- the landing never came (he went down first)
    end
  end
  for _, list in ipairs({ self.rings, self.poofs }) do
    for i = #list, 1, -1 do
      list[i].t = list[i].t + dt
      if list[i].t > 0.8 then
        table.remove(list, i)
      end
    end
  end
  if self.shake > 0 then
    self.shake = math.max(0, self.shake - dt)
    local a = self.shake * 30
    camera.x = camera.x + (love.math.random() - 0.5) * a
    camera.y = camera.y + (love.math.random() - 0.5) * a
  end
end

--- Any key takes the title screen down. The reveal portraits stay: they
--- come up mid-drive, and a held or repeating steering key would skip both
--- in a blink. They run on the host's clock anyway.
function Hunt:keypressed()
  if self.pages[1] and not self.pages[1].keep then
    table.remove(self.pages, 1)
  end
end

function Hunt:worldBlur()
  return self.pages[1] and 1 or 0
end

--- Update `e` (or make it) from a state group starting at args[i].
local function track(e, args, i)
  local x, y = tonumber(args[i]), tonumber(args[i + 1])
  if not (x and y) then
    return e
  end
  e = e or { dx = x, dy = y, bob = love.math.random() * 6, sayTimer = 0 }
  e.x, e.y = x, y
  e.angle = tonumber(args[i + 2]) or e.angle or 0
  e.hp = tonumber(args[i + 3]) or e.hp or 0
  return e
end

Hunt.clientMessages = {
  HNT_STAGE = function(_client, args)
    local stage, wp = args[1], tonumber(args[2]) or 0
    if stage == "none" then
      clear()
      return
    end
    if stage == "reveal" and Hunt.stage ~= "reveal" then
      wildFace = wildFace or WildFace.new()
      footFace = footFace or FootFace.new()
      Hunt.pages = {}
      page(wildFace, WENDELL_QUITS, WILD_LOOK, Hunt.manLeavesAt, false, true)
      page(footFace, BIGFOOT_ROARS, FOOT_LOOK, Hunt.revealTime - Hunt.manLeavesAt, true, true)
    end
    Hunt.stage, Hunt.wp = stage, wp
  end,
  HNT_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    local i = 2
    while i <= #args do
      local tag = args[i]
      if tag == "m" then
        Hunt.man = track(Hunt.man, args, i + 1)
        seen.m, i = true, i + 5
      elseif tag == "s" then
        Hunt.squirrel = track(Hunt.squirrel, args, i + 1)
        seen.s, i = true, i + 5
      elseif tag == "b" then
        local f = track(Hunt.foot, args, i + 1)
        f.mode = MODE_NAMES[args[i + 5]] or "idle"
        f.swipe = args[i + 6] == "1"
        Hunt.foot = f
        seen.b, i = true, i + 7
      else
        break
      end
    end
    if not seen.m then
      Hunt.man = nil
    end
    if not seen.s then
      Hunt.squirrel = nil
    end
    if not seen.b then
      Hunt.foot = nil
    end
  end,
  HNT_SAY = function(_client, args)
    local pool = Hunt.lines[args[1] or ""]
    local line = pool and pool[tonumber(args[2]) or 0]
    local m = Hunt.man
    if m and line then
      m.say, m.sayTimer = line, Hunt.sayTime
    end
  end,
  HNT_SQ = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("chitter", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
  HNT_SQ_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    Hunt.squirrel = nil
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 1.3 + love.math.random() * 0.2)
    end
  end,
  HNT_MAN_GONE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    Hunt.man = nil
    if x and y then
      Hunt.poofs[#Hunt.poofs + 1] = { x = x, y = y, t = 0 }
      Sounds.play("poof", x, y)
    end
  end,
  HNT_LEAP = function(_client, args)
    local v = {}
    for i = 1, 6 do
      v[i] = tonumber(args[i])
      if not v[i] then
        return
      end
    end
    Hunt.leap = { fx = v[1], fy = v[2], tx = v[3], ty = v[4], total = v[5], r = v[6], t = 0 }
  end,
  HNT_SLAM = function(client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (x and y and r) then
      return
    end
    Hunt.leap = nil
    local f = Hunt.foot
    if f then
      f.x, f.y, f.dx, f.dy = x, y, x, y
    end
    Hunt.rings[#Hunt.rings + 1] = { x = x, y = y, r = r, t = 0 }
    Sounds.play("slam", x, y)
    local mx, my = client:myPose()
    if mx and dist2(mx, my, x, y) < (r * 3) ^ 2 then
      Hunt.shake = 0.4
    end
  end,
  HNT_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    Hunt.foot, Hunt.leap = nil, nil
    if x and y then
      Hunt.stain = { x = x, y = y, angle = angle }
    end
  end,
}

-- Drawing ---------------------------------------------------------------------

--- A ring on the ground: the clearing Wendell is making for, or where
--- Bigfoot is about to come down (filling as he falls).
local function drawTargets(self)
  local map = cityMap()
  local wp = map and map.waypoints and map.waypoints[self.wp]
  if wp and (self.stage == "follow" or self.stage == "defend" or self.stage == "faint") then
    local pulse = 0.5 + 0.5 * math.sin(time * 3)
    love.graphics.setColor(0.55, 1, 0.45, 0.25 + 0.2 * pulse)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", wp.x, wp.y, 70 + 6 * pulse, 40)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.55, 1, 0.45, 0.8)
    love.graphics.printf(self.wp .. " / " .. #map.waypoints, wp.x - 40, wp.y - 8, 80, "center")
  end
  local leap = self.leap
  if leap then
    local k = math.min(1, leap.t / leap.total)
    local pulse = 0.5 + 0.5 * math.sin(time * 14)
    love.graphics.setColor(0.95, 0.35, 0.15, 0.12 + 0.08 * pulse)
    love.graphics.circle("fill", leap.tx, leap.ty, leap.r, 48)
    love.graphics.setColor(0.95, 0.35, 0.15, 0.35)
    love.graphics.circle("fill", leap.tx, leap.ty, leap.r * k, 48)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 0.5, 0.25, 0.6 + 0.4 * pulse)
    love.graphics.circle("line", leap.tx, leap.ty, leap.r, 48)
  end
  love.graphics.setLineWidth(1)
end

--- Where Bigfoot went down: a heap of fur on a dark patch.
local function drawStain(s)
  love.graphics.setColor(0.35, 0.06, 0.06, 0.8)
  love.graphics.ellipse("fill", s.x, s.y, 40, 30)
  love.graphics.setColor(FUR_DARK)
  love.graphics.ellipse("fill", s.x, s.y, 26, 18)
  love.graphics.setColor(FUR)
  for k = 0, 5 do
    local a = s.angle + k
    love.graphics.circle("fill", s.x + math.cos(a) * 14, s.y + math.sin(a) * 10, 7)
  end
end

function Hunt:drawBelowCars()
  drawTargets(self)
  if self.stain then
    drawStain(self.stain)
  end
  love.graphics.setColor(1, 1, 1)
end

--- A speech bubble over a head, the tail pointing down.
local function drawBubble(x, y, text, alpha)
  local font = UI.fonts.small
  local maxW = 220
  local w, lines = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 16
  local h = #lines * font:getHeight() + 12
  local bx, by = x - w / 2, y - h - 14
  love.graphics.setColor(0, 0, 0, 0.5 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 6)
  love.graphics.setColor(1, 1, 1, 0.95 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 6)
  love.graphics.polygon("fill", x - 6, by + h - 1, x + 6, by + h - 1, x, by + h + 8)
  love.graphics.setFont(font)
  love.graphics.setColor(0.10, 0.20, 0.08, alpha)
  love.graphics.printf(text, bx + 8, by + 6, w - 16, "center")
end

local function drawBar(x, y, w, frac)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - w / 2 - 1, y, w + 2, 6)
  love.graphics.setColor(1 - frac, frac, 0.2)
  love.graphics.rectangle("fill", x - w / 2, y + 1, w * frac, 4)
end

--- Wendell from above: stained shirt, arms flapping, a shock of grey hair
--- sticking out all round. Fainted, he lies flat with stars going round.
local function drawMan(m, fainted)
  local x, y, r = m.dx, m.dy, Hunt.manRadius
  local fx, fy = math.cos(m.angle), math.sin(m.angle)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r + 1, 12)
  if fainted then
    love.graphics.setColor(SHIRT)
    love.graphics.ellipse("fill", x, y, r + 5, r - 1)
    love.graphics.setColor(HAIR)
    love.graphics.circle("fill", x - r - 4, y, 5, 8)
    love.graphics.setColor(1, 0.9, 0.3)
    for k = 0, 2 do
      local a = time * 4 + k * 2.1
      love.graphics.circle("fill", x - r - 4 + math.cos(a) * 9, y - 10 + math.sin(a) * 4, 1.6, 5)
    end
    return
  end
  local swing = math.sin(time * 14 + m.bob) * 2
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x - fy * (r + 2) + fx * swing, y + fx * (r + 2) + fy * swing, 2.2, 6)
  love.graphics.circle("fill", x + fy * (r + 2) - fx * swing, y - fx * (r + 2) - fy * swing, 2.2, 6)
  love.graphics.setColor(SHIRT)
  love.graphics.circle("fill", x, y, r, 12)
  love.graphics.setColor(0.90, 0.72, 0.12)
  love.graphics.circle("fill", x + fx * 3 - fy * 2, y + fy * 3 + fx * 2, 1.5, 5) -- mustard
  love.graphics.setColor(0.75, 0.10, 0.08)
  love.graphics.circle("fill", x + fx * 2 + fy * 3, y + fy * 2 - fx * 3, 1.2, 5) -- ketchup
  love.graphics.setColor(HAIR)
  for k = 0, 9 do
    local a = k / 10 * math.pi * 2 + math.sin(time * 6 + k) * 0.1
    local d = 5.5 + (k % 3) * 1.2
    love.graphics.line(x - fx, y - fy, x - fx + math.cos(a) * d, y - fy + math.sin(a) * d)
  end
  love.graphics.circle("fill", x - fx, y - fy, 4, 8)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 1.5, y + fy * 1.5, 2.5, 6)
end

--- A squirrel from above: a small body, a head out front and a huge bushy
--- tail curling behind, twitching.
local function drawSquirrel(s)
  local x, y = s.dx, s.dy
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local flick = math.sin(time * 12 + (s.bob or 0)) * 0.5
  local ta = s.angle + math.pi + flick
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, 5, 8)
  love.graphics.setColor(SQUIRREL_LIGHT)
  love.graphics.ellipse("fill", x + math.cos(ta) * 8, y + math.sin(ta) * 8, 6, 6)
  love.graphics.setColor(SQUIRREL)
  love.graphics.circle("fill", x + math.cos(ta) * 11 + math.cos(ta + 1.4) * 3,
    y + math.sin(ta) * 11 + math.sin(ta + 1.4) * 3, 4, 8)
  love.graphics.ellipse("fill", x, y, 5, 5)
  love.graphics.circle("fill", x + fx * 5, y + fy * 5, 3, 8)
  love.graphics.setColor(0, 0, 0)
  love.graphics.circle("fill", x + fx * 6.5 - fy * 1.5, y + fy * 6.5 + fx * 1.5, 0.8, 4)
  love.graphics.circle("fill", x + fx * 6.5 + fy * 1.5, y + fy * 6.5 - fx * 1.5, 0.8, 4)
  if s.hp < Hunt.squirrelHealth then
    drawBar(x, y + 9, 16, math.max(0, s.hp / Hunt.squirrelHealth))
  end
end

--- Bigfoot from above: a big shaggy body, long arms, a head sunk into the
--- shoulders. He squashes down to crouch, swells up in the air (his shadow
--- stays on the ground), and an arm swings out on a swipe.
local function drawFoot(self, f)
  local x, y, r = f.dx, f.dy, Hunt.footRadius
  local lift, scale = 0, 1
  local leap = self.leap
  if leap and f.mode == "air" then
    local k = math.min(1, leap.t / leap.total)
    x, y = leap.fx + (leap.tx - leap.fx) * k, leap.fy + (leap.ty - leap.fy) * k
    lift = math.sin(k * math.pi) * 90
    scale = 1 + math.sin(k * math.pi) * 0.45
  elseif f.mode == "crouch" then
    scale = 0.88
  end
  local fx, fy = math.cos(f.angle), math.sin(f.angle)
  love.graphics.setColor(0, 0, 0, 0.35 - lift / 400)
  love.graphics.circle("fill", x + 5, y + 5, r * (1 - lift / 300), 20)
  y = y - lift
  r = r * scale
  local swing = math.sin(time * (f.mode == "walk" and 9 or 3) + f.bob) * 2.5
  local sx, sy = -fy * swing, fx * swing
  local reach = f.swipe and 12 or 0
  love.graphics.setColor(FUR_DARK)
  love.graphics.circle("fill", x - fy * (r + 4) + sx + fx * reach, y + fx * (r + 4) + sy + fy * reach, 7 * scale, 10)
  love.graphics.circle("fill", x + fy * (r + 4) - sx, y - fx * (r + 4) - sy, 7 * scale, 10)
  love.graphics.setColor(FUR)
  love.graphics.circle("fill", x, y, r, 20)
  love.graphics.setColor(FUR_DARK)
  for k = 0, 11 do
    local a = f.angle + k / 12 * math.pi * 2
    love.graphics.circle("fill", x + math.cos(a) * r * 0.95, y + math.sin(a) * r * 0.95, 3.5 * scale, 6)
  end
  love.graphics.setColor(0.36, 0.26, 0.22)
  love.graphics.circle("fill", x + fx * r * 0.45, y + fy * r * 0.45, 8 * scale, 12)
  love.graphics.setColor(0.85, 0.12, 0.08)
  love.graphics.circle("fill", x + fx * r * 0.6 - fy * 3, y + fy * r * 0.6 + fx * 3, 1.5, 5)
  love.graphics.circle("fill", x + fx * r * 0.6 + fy * 3, y + fy * r * 0.6 - fx * 3, 1.2, 5)
  local bw = 60
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y - r - 16, bw + 2, 6)
  local frac = math.max(0, f.hp / Hunt.footHealth)
  love.graphics.setColor(1 - frac, frac, 0.2)
  love.graphics.rectangle("fill", x - bw / 2, y - r - 15, bw * frac, 4)
end

--- A slam that just landed: dust rings spreading out.
local function drawRing(ring)
  local k = ring.t / 0.8
  love.graphics.setLineWidth(4)
  for i = 0, 2 do
    local kk = k - i * 0.15
    if kk > 0 and kk < 1 then
      love.graphics.setColor(0.65, 0.50, 0.32, (1 - kk) * 0.9)
      love.graphics.circle("line", ring.x, ring.y, ring.r * (0.2 + 0.9 * kk), 48)
    end
  end
  love.graphics.setLineWidth(1)
end

--- Where Wendell vanished: a green puff going up.
local function drawPoof(p)
  local k = p.t / 0.8
  love.graphics.setColor(0.7, 1, 0.6, (1 - k) * 0.8)
  for i = 0, 5 do
    local a = i / 6 * math.pi * 2
    love.graphics.circle("fill", p.x + math.cos(a) * 14 * k, p.y + math.sin(a) * 14 * k - 30 * k, 6 * (1 - k) + 2)
  end
end

function Hunt:drawAboveCars()
  local s = self.squirrel
  if s then
    drawSquirrel(s)
  end
  local m = self.man
  if m then
    drawMan(m, self.stage == "faint")
    local x, y = m.dx, m.dy
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("Wendell", x - 59, y - 29, 120, "center")
    love.graphics.setColor(0.7, 1, 0.6)
    love.graphics.printf("Wendell", x - 60, y - 30, 120, "center")
    drawBar(x, y - 13, 28, math.max(0, m.hp / self.manHealth))
    if m.say and m.sayTimer > 0 then
      drawBubble(x, y - 30, m.say, math.min(1, m.sayTimer * 2))
    end
  end
  for _, ring in ipairs(self.rings) do
    drawRing(ring)
  end
  for _, p in ipairs(self.poofs) do
    drawPoof(p)
  end
  local f = self.foot
  if f then
    drawFoot(self, f)
  end
  love.graphics.setColor(1, 1, 1)
end

local OBJECTIVES = {
  follow = "Follow Wendell to the clearing",
  defend = "Protect Wendell from the squirrel!",
  faint = "Wendell fainted. He's coming round...",
}

--- The boss bar along the bottom of the screen.
local function drawBossBar(f)
  local w, h = love.graphics.getDimensions()
  local bw, bh = 380, 14
  local bx, by = math.floor((w - bw) / 2), h - 110 -- above the ability circles
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("BIGFOOT", 1, by - 19, w, "center")
  love.graphics.setColor(1, 0.6, 0.3)
  love.graphics.printf("BIGFOOT", 0, by - 20, w, "center")
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4, 3)
  love.graphics.setColor(0.6, 0.35, 0.15)
  love.graphics.rectangle("fill", bx, by, bw * math.max(0, f.hp / Hunt.footHealth), bh, 2)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.rectangle("line", bx, by, bw, bh, 2)
end

function Hunt:drawHUD()
  local text = OBJECTIVES[self.stage]
  if text then
    local map = cityMap()
    local n = map and map.waypoints and #map.waypoints or 5
    if self.stage == "follow" then
      text = text .. " (" .. self.wp .. " / " .. n .. ")"
    end
    local w = love.graphics.getWidth()
    love.graphics.setFont(UI.fonts.body)
    UI.label(text, math.floor((w - UI.fonts.body:getWidth(text)) / 2), 70, { 0.7, 1, 0.6 })
  end
  if self.foot and self.stage == "fight" then
    drawBossBar(self.foot)
  end
  local p = self.pages[1]
  if p then
    local spec = {}
    for k, v in pairs(p.look) do
      spec[k] = v
    end
    for k, v in pairs(p.spec) do
      spec[k] = v
    end
    Screen.draw(p.face, spec, time)
  end
  love.graphics.setColor(1, 1, 1)
end

return Hunt
