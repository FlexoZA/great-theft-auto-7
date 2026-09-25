-- Bigfoot comes to town: the first city event (see init.lua). He comes out
-- of the woods onto a road somewhere away from everyone and goes for the
-- nearest player, or the nearest building a player owns when nobody is
-- close, walking, and leaping when they are far off or he is stuck behind a
-- block. Near a player he swipes and, every few seconds, crouches and leaps
-- onto them: a ring on the ground shows where he comes down, and the
-- landing hurts everyone in it and cracks the buildings around it. Next to
-- a building he claws at it. Bullets pass under him while he is in the air.
--
-- He brings his squirrels: a litter of `litter` round his feet that wait a
-- moment and then shoot off at the nearest player (or building) in range,
-- far faster than anyone runs. One that reaches its target bursts into
-- gibs, doing a little damage; one shot does the same, and one that finds
-- nothing bursts after a while anyway. Once the whole litter is gone he
-- roars up another.
--
-- When he goes down he spills koins and drops his leap ("ability-bigleap",
-- abilities/bigleap.lua) on the spot as a pickup, for whoever gets there
-- first; the event is then over.
--
-- The host owns him and his squirrels; clients hear positions at 15 Hz and
-- draw with the alien hunt's pictures (alien-hunt/render.lua) and sounds.
--
-- Messages (the events feature registers them)
--   server -> all  EBF_STATE <tick> <x> <y> <facing> <hp> <mode> <swipe> [<id> <x> <y> <facing>]...
--                                          (unreliable, 15 Hz; the squirrels after him)
--   server -> all  EBF_LEAP  <fx> <fy> <tx> <ty> <seconds> <radius>   he took off; lands on (tx, ty)
--   server -> all  EBF_SLAM  <x> <y> <radius>        he landed
--   server -> all  EBF_LITTER <x> <y>                a new litter came out round him
--   server -> all  EBF_POP   <x> <y> <angle>         a squirrel burst
--   server -> all  EBF_DOWN  <x> <y> <angle>         he went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Body = require("src.body")
local Render = require("src.features.alien-hunt.render")
local Sounds = require("src.features.alien-hunt.sounds")

local Bigfoot = {
  key = "bigfoot",
  title = "BIGFOOT IS IN THE CITY",
  subtitle = "The police have fled. Stop him before he flattens your buildings.",
  wonTitle = "BIGFOOT IS DOWN",
  wonSubtitle = "He dropped his leap. First one there takes it.",
  color = { 1, 0.35, 0.2 },
}

-- Tuning ------------------------------------------------------------------
Bigfoot.health = 2500 -- 125 rounds
Bigfoot.radius = 22
Bigfoot.speed = 120 -- px/s; a sprint outruns him, a walk doesn't
Bigfoot.aggroRange = 900 -- px; a player this close comes before any building
Bigfoot.spawnNear = 1000 -- px; he comes in about this far from the nearest player
Bigfoot.spawnFar = 1800
Bigfoot.swipeReach = 22 -- px past his body a swipe lands
Bigfoot.swipeDamage = 16
Bigfoot.swipeEvery = 1.4
Bigfoot.clawDamage = 25 -- what a swipe does to a building
Bigfoot.leapEvery = 5 -- seconds between leaps
Bigfoot.leapRange = 620 -- px; the furthest one leap takes him
Bigfoot.stuckLeap = 2 -- seconds getting no closer before he leaps over whatever is in the way
Bigfoot.crouchTime = 0.6
Bigfoot.airTime = 1.0
Bigfoot.recoverTime = 0.8
Bigfoot.slamRadius = 125
Bigfoot.slamDamage = 30
Bigfoot.slamWalls = 60 -- to a building right under the landing, less towards the edge
Bigfoot.bulletDamage = 20 -- what one round takes off him (matches the pistol)
Bigfoot.drops = 60 -- koins he spills
Bigfoot.drop = "ability-bigleap" -- the pickup he leaves

Bigfoot.litter = 15 -- squirrels at a time
Bigfoot.litterDelay = 4 -- seconds after the last one burst before the next litter
Bigfoot.squirrelHealth = 10 -- one round
Bigfoot.squirrelRadius = 7
Bigfoot.squirrelSpeed = 340 -- px/s; faster than any car off the line
Bigfoot.squirrelTurn = 5 -- rad/s; they swerve, but overshoot a sharp dodge...
Bigfoot.squirrelHoming = 140 -- px; ...until this close, where they turn up to four times as hard
Bigfoot.squirrelWait = { 0.4, 1.4 } -- seconds a new one sits before it goes
Bigfoot.squirrelRange = 1000 -- px; what one goes after
Bigfoot.squirrelLife = 7 -- seconds before one bursts on its own
Bigfoot.squirrelDamage = 3
Bigfoot.squirrelWalls = 6 -- what one does to a building it hits

local SYNC_EVERY = 2 -- server ticks between EBF_STATE packets
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 150 -- px; a jump this big is a spawn or a landing, not a step
local MODES = { idle = "i", walk = "w", crouch = "c", air = "a", recover = "r" }
local MODE_NAMES = { i = "idle", w = "walk", c = "crouch", a = "air", r = "recover" }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The point of rectangle `r` ({ x, y, w, h }) nearest to (x, y).
local function nearestOn(r, x, y)
  return math.max(r.x, math.min(x, r.x + r.w)), math.max(r.y, math.min(y, r.y + r.h))
end

--- Solid ground (the `blocksPoint` convention) under a circle of radius
--- `r` at (x, y): the centre and its four extremes.
local function blocked(x, y, r)
  return Features.any("blocksPoint", x, y)
    or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y)
    or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { foot, squirrels = { id -> s }, count, nextId, litterIn, syncIn, buildings, events }

function Bigfoot.serverStop()
  sv = nil
end

--- Every human who can be gone after, with where they are.
local function humans(server)
  local out = {}
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      out[#out + 1] = { player = p, x = x, y = y, onFoot = onFoot }
    end
  end
  return out
end

--- The players' buildings still standing, this tick.
local function buildings()
  local b = Features.byName.buildings
  local out = {}
  for _, s in ipairs(b and b.serverStanding and b:serverStanding() or {}) do
    if s.owner then
      out[#out + 1] = s
    end
  end
  return out
end

--- A road somewhere away from everyone: about `spawnNear`..`spawnFar` px
--- from the nearest player, and not in a wall.
local function spawnPoint(server)
  local city = Features.byName["city-map"]
  local people = humans(server)
  local best, bestScore
  for _ = 1, 60 do
    local x, y
    if city and city.randomRoadPoint then
      x, y = city:randomRoadPoint()
    elseif people[1] then
      local a = random() * 2 * math.pi
      x, y = people[1].x + math.cos(a) * Bigfoot.spawnNear, people[1].y + math.sin(a) * Bigfoot.spawnNear
    end
    if x and not blocked(x, y, Bigfoot.radius) then
      local near
      for _, h in ipairs(people) do
        local d = math.sqrt(dist2(x, y, h.x, h.y))
        near = math.min(near or d, d)
      end
      near = near or Bigfoot.spawnNear
      local score = -math.max(0, Bigfoot.spawnNear - near) * 2 - math.max(0, near - Bigfoot.spawnFar)
      if not bestScore or score > bestScore then
        best, bestScore = { x = x, y = y }, score
      end
      if score == 0 then
        break
      end
    end
  end
  return best
end

function Bigfoot.serverBegin(server, events)
  local at = spawnPoint(server)
  if not at then
    return nil
  end
  sv = {
    events = events,
    foot = {
      x = at.x, y = at.y, facing = math.pi / 2, hp = Bigfoot.health, mode = "idle", timer = 0, frozen = 0,
      swipeTimer = 1, swipe = 0, leapTimer = Bigfoot.leapEvery * 0.5, stuck = 0, sidestep = 0, side = 1,
      closest = math.huge, noCloser = 0,
    },
    squirrels = {},
    count = 0,
    nextId = 1,
    litterIn = 2.5, -- the first litter soon after he arrives
    syncIn = 0,
    buildings = {},
  }
  return at.x, at.y
end

local function hurtPlayer(server, player, amount, angle)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, player, nil, amount, angle)
  end
end

--- Take `amount` off whatever building is at (x, y) (on its edge), the way
--- a gun or a blast would.
local function hurtWall(server, x, y, amount, radius)
  Features.call("serverBlast", server, x, y, radius or 1, amount, 0)
end

--- What he goes after: the nearest player within aggro range; failing
--- that, whichever is nearer of any player and any building of a player's.
--- Returns { x, y, player, onFoot } or { x, y, building } or nil.
local function pickTarget(server, f)
  local best, bestD2
  for _, h in ipairs(humans(server)) do
    local d2 = dist2(h.x, h.y, f.x, f.y)
    if not bestD2 or d2 < bestD2 then
      best, bestD2 = { x = h.x, y = h.y, player = h.player, onFoot = h.onFoot }, d2
    end
  end
  if best and bestD2 <= Bigfoot.aggroRange ^ 2 then
    return best
  end
  for _, b in ipairs(sv.buildings) do
    local x, y = nearestOn(b, f.x, f.y)
    local d2 = dist2(x, y, f.x, f.y)
    if not bestD2 or d2 < bestD2 then
      best, bestD2 = { x = x, y = y, building = b }, d2
    end
  end
  return best
end

--- One step, each axis on its own so a corner is slid along. Landed in
--- something, he walks out of it.
local function walk(f, angle, dt)
  local px, py, r = f.x, f.y, Bigfoot.radius
  local free = blocked(f.x, f.y, r)
  local nx = f.x + math.cos(angle) * Bigfoot.speed * dt
  if free or not blocked(nx, f.y, r) then
    f.x = nx
  end
  local ny = f.y + math.sin(angle) * Bigfoot.speed * dt
  if free or not blocked(f.x, ny, r) then
    f.y = ny
  end
  if dist2(f.x, f.y, px, py) < (Bigfoot.speed * dt * 0.4) ^ 2 then
    f.stuck = f.stuck + dt
  else
    f.stuck = 0
  end
end

--- Crouch for a leap towards (tx, ty), no further than `leapRange`, and
--- onto clear ground: the landing is pulled back towards him until it is.
local function crouch(f, tx, ty, playerId)
  local angle = math.atan2(ty - f.y, tx - f.x)
  local d = math.min(Bigfoot.leapRange, math.sqrt(dist2(tx, ty, f.x, f.y)))
  local x, y = f.x + math.cos(angle) * d, f.y + math.sin(angle) * d
  while d > 0 and blocked(x, y, Bigfoot.radius) do
    d = math.max(0, d - 12)
    x, y = f.x + math.cos(angle) * d, f.y + math.sin(angle) * d
  end
  f.mode, f.timer, f.facing = "crouch", Bigfoot.crouchTime, angle
  f.tx, f.ty, f.target = x, y, playerId
  f.leapTimer, f.stuck, f.noCloser, f.chasing = Bigfoot.leapEvery, 0, 0, nil
end

--- He comes down: everyone inside the ring is hurt and the buildings round
--- it crack.
local function slam(server, f)
  for _, h in ipairs(humans(server)) do
    local pad = h.onFoot and Body.RADIUS or Car.WIDTH / 2
    if dist2(h.x, h.y, f.x, f.y) <= (Bigfoot.slamRadius + pad) ^ 2 then
      hurtPlayer(server, h.player, Bigfoot.slamDamage, math.atan2(h.y - f.y, h.x - f.x))
    end
  end
  hurtWall(server, f.x, f.y, Bigfoot.slamWalls, Bigfoot.slamRadius)
  server:broadcast(Protocol.encode("EBF_SLAM", fmt(f.x), fmt(f.y), Bigfoot.slamRadius))
end

--- Bigfoot's tick: in the air, frozen, crouching, getting up, running from
--- a stink, or after his target.
local function stepFoot(server, dt)
  local f = sv.foot
  f.swipe = math.max(0, f.swipe - dt)
  f.swipeTimer = f.swipeTimer - dt
  if f.mode == "air" then
    f.timer = f.timer - dt
    local k = math.min(1, 1 - f.timer / Bigfoot.airTime)
    f.x, f.y = f.fx + (f.tx - f.fx) * k, f.fy + (f.ty - f.fy) * k
    if f.timer <= 0 then
      f.x, f.y = f.tx, f.ty
      f.mode, f.timer = "recover", Bigfoot.recoverTime
      slam(server, f)
    end
    return
  end
  if f.frozen > 0 then
    f.frozen = f.frozen - dt
    f.mode = "idle"
    return
  end
  if f.panic and f.mode ~= "crouch" then
    f.panic.left = f.panic.left - dt
    f.mode = "walk"
    f.facing = math.atan2(f.y - f.panic.y, f.x - f.panic.x)
    walk(f, f.facing, dt)
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
        -- A last look: he goes where they are now, within reach and onto clear ground.
        local tx, ty = Features.bodyPose(server, target)
        crouch(f, tx, ty, nil)
      end
      f.fx, f.fy = f.x, f.y
      f.mode, f.timer = "air", Bigfoot.airTime
      server:broadcast(Protocol.encode("EBF_LEAP", fmt(f.fx), fmt(f.fy), fmt(f.tx), fmt(f.ty), Bigfoot.airTime,
        Bigfoot.slamRadius))
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

  local target = pickTarget(server, f)
  if not target then
    f.mode = "idle"
    return
  end
  f.mode = "walk"
  f.facing = math.atan2(target.y - f.y, target.x - f.x)
  f.leapTimer = f.leapTimer - dt
  local dist = math.sqrt(dist2(target.x, target.y, f.x, f.y))
  local reach = Bigfoot.radius + Bigfoot.swipeReach + ((target.player and not target.onFoot) and 10 or 0)
  -- Getting any closer? A new target starts the count again.
  local key = target.player or target.building.id
  if key ~= f.chasing or dist < f.closest - 30 then
    f.chasing, f.closest, f.noCloser = key, dist, 0
  else
    f.noCloser = f.noCloser + dt
  end
  if dist > reach and (f.noCloser > Bigfoot.stuckLeap or (f.leapTimer <= 0 and (target.player or dist > 300))) then
    -- Onto a player in reach, towards anything further, over whatever he is stuck on.
    crouch(f, target.x, target.y, target.player and dist <= Bigfoot.leapRange and target.player.id or nil)
    return
  end
  if dist > reach then
    if f.sidestep > 0 then
      f.sidestep = f.sidestep - dt
      walk(f, f.facing + f.side * math.pi / 2, dt)
    else
      walk(f, f.facing, dt)
      if f.stuck > 0.4 then
        f.stuck, f.sidestep, f.side = 0, 0.6, -f.side
      end
    end
  elseif f.swipeTimer <= 0 then
    f.swipeTimer, f.swipe = Bigfoot.swipeEvery, 0.25
    if target.player then
      hurtPlayer(server, target.player, Bigfoot.swipeDamage, f.facing)
    else
      hurtWall(server, target.x, target.y, Bigfoot.clawDamage)
    end
  end
end

--- A new litter round his feet.
local function litter(server)
  local f = sv.foot
  for i = 1, Bigfoot.litter do
    local a = (i / Bigfoot.litter) * math.pi * 2 + random() * 0.3
    local d = Bigfoot.radius + 14 + random() * 40
    local id = sv.nextId
    sv.nextId = id + 1
    sv.squirrels[id] = {
      id = id, x = f.x + math.cos(a) * d, y = f.y + math.sin(a) * d, facing = a, hp = Bigfoot.squirrelHealth,
      wait = Bigfoot.squirrelWait[1] + random() * (Bigfoot.squirrelWait[2] - Bigfoot.squirrelWait[1]),
      life = Bigfoot.squirrelLife, frozen = 0,
    }
  end
  sv.count = Bigfoot.litter
  server:broadcast(Protocol.encode("EBF_LITTER", fmt(f.x), fmt(f.y)))
end

--- Squirrel `s` bursts where it is.
local function pop(server, s)
  if not sv.squirrels[s.id] then
    return
  end
  sv.squirrels[s.id] = nil
  sv.count = sv.count - 1
  if sv.count <= 0 then
    sv.litterIn = Bigfoot.litterDelay
  end
  server:broadcast(Protocol.encode("EBF_POP", fmt(s.x), fmt(s.y), ("%.2f"):format(s.facing)))
end

--- What squirrel `s` makes for: the nearest player in range, or the nearest
--- building of a player's in range; nil for neither.
local function squirrelTarget(s, people)
  local best, bestD2 = nil, Bigfoot.squirrelRange ^ 2
  for _, h in ipairs(people) do
    local d2 = dist2(h.x, h.y, s.x, s.y)
    if d2 < bestD2 then
      best, bestD2 = h, d2
    end
  end
  if best then
    return best
  end
  bestD2 = Bigfoot.squirrelRange ^ 2
  for _, b in ipairs(sv.buildings) do
    local x, y = nearestOn(b, s.x, s.y)
    local d2 = dist2(x, y, s.x, s.y)
    if d2 < bestD2 then
      best, bestD2 = { x = x, y = y, building = b }, d2
    end
  end
  return best
end

--- Turn `from` towards `to` by at most `step` radians.
local function turn(from, to, step)
  local d = (to - from + math.pi) % (2 * math.pi) - math.pi
  return from + math.max(-step, math.min(step, d))
end

--- Every squirrel's tick: sit, then shoot off at a target and burst on it.
local function stepSquirrels(server, dt)
  local people = humans(server)
  local f = sv.foot
  for _, s in pairs(sv.squirrels) do
    s.life = s.life - dt
    if s.life <= 0 then
      pop(server, s)
    elseif s.frozen > 0 then
      s.frozen = s.frozen - dt
    elseif s.wait > 0 then
      s.wait = s.wait - dt
    else
      local speed = Bigfoot.squirrelSpeed
      local t = not s.panic and squirrelTarget(s, people)
      local want
      local turnRate = Bigfoot.squirrelTurn
      if s.panic then
        want = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
        s.panic.left = s.panic.left - dt
        s.panic = s.panic.left > 0 and s.panic or nil
      elseif t then
        want = math.atan2(t.y - s.y, t.x - s.x)
        -- Close in, they turn harder, or they'd circle a player standing still.
        local d = math.sqrt(dist2(t.x, t.y, s.x, s.y))
        turnRate = Bigfoot.squirrelTurn * (1 + 3 * math.max(0, 1 - d / Bigfoot.squirrelHoming))
      else
        -- Nothing about: circle him, slower.
        want = math.atan2(f.y - s.y, f.x - s.x) + math.pi / 2
        speed = speed * 0.4
      end
      s.facing = turn(s.facing, want, turnRate * dt)
      s.x, s.y = s.x + math.cos(s.facing) * speed * dt, s.y + math.sin(s.facing) * speed * dt
      if t and t.player then
        local reach = Bigfoot.squirrelRadius + (t.onFoot and Body.RADIUS or Car.WIDTH / 2 + 4)
        if dist2(t.x, t.y, s.x, s.y) <= reach * reach then
          hurtPlayer(server, t.player, Bigfoot.squirrelDamage, s.facing)
          pop(server, s)
        end
      elseif t and t.building then
        local b = t.building
        local r = Bigfoot.squirrelRadius
        if s.x >= b.x - r and s.x <= b.x + b.w + r and s.y >= b.y - r and s.y <= b.y + b.h + r then
          hurtWall(server, t.x, t.y, Bigfoot.squirrelWalls)
          pop(server, s)
        end
      end
    end
  end
end

--- Where everything is, to everyone.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local f = sv.foot
  local parts = { server.tick, fmt(f.x), fmt(f.y), ("%.2f"):format(f.facing), math.max(0, math.floor(f.hp)),
    MODES[f.mode], f.swipe > 0 and 1 or 0 }
  for id, s in pairs(sv.squirrels) do
    parts[#parts + 1] = id
    parts[#parts + 1] = fmt(s.x)
    parts[#parts + 1] = fmt(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
  end
  local msg = Protocol.encode("EBF_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Bigfoot.serverStep(server, dt)
  if not sv then
    return
  end
  sv.buildings = buildings()
  stepFoot(server, dt)
  if not sv then
    return
  end
  if sv.count <= 0 then
    sv.litterIn = sv.litterIn - dt
    if sv.litterIn <= 0 and sv.foot.mode ~= "air" then
      litter(server)
    end
  end
  stepSquirrels(server, dt)
  sync(server)
end

--- He takes `amount`. At zero he goes down: koins, his leap on the ground,
--- and the event is over.
local function hurtFoot(server, amount, by, angle)
  local f = sv.foot
  f.hp = f.hp - amount
  if f.hp > 0 then
    return
  end
  local x, y = f.x, f.y
  server:broadcast(Protocol.encode("EBF_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Bigfoot.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    -- Beside the koins, not under them, on clear ground.
    local dx, dy = x, y
    for i = 0, 7 do
      local a = math.pi / 2 + i * math.pi / 4
      local ox, oy = x + math.cos(a) * 70, y + math.sin(a) * 70
      if not blocked(ox, oy, 14) then
        dx, dy = ox, oy
        break
      end
    end
    pickups:serverDrop(server, Bigfoot.drop, dx, dy)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  sv.events:serverFinish(server, x, y)
end

--- A bullet passing through (x, y): the `serverShotAt` convention. It
--- bursts a squirrel, or hits him while he is on the ground.
function Bigfoot.serverShotAt(server, x, y, radius, by, angle)
  if not sv then
    return false
  end
  for _, s in pairs(sv.squirrels) do
    if dist2(s.x, s.y, x, y) < (radius + Bigfoot.squirrelRadius + 3) ^ 2 then
      s.hp = s.hp - Bigfoot.bulletDamage
      if s.hp <= 0 then
        pop(server, s)
        Features.call("serverKill", server, { kind = "animal", x = s.x, y = s.y, by = by ~= 0 and by or nil,
          angle = angle })
      end
      return true
    end
  end
  local f = sv.foot
  if f.mode ~= "air" and dist2(f.x, f.y, x, y) < (radius + Bigfoot.radius) ^ 2 then
    hurtFoot(server, Bigfoot.bulletDamage, by ~= 0 and by or nil, angle)
    return true
  end
  return false
end

--- Something stinks at (x, y): he (on the ground) and his squirrels run
--- from it for a moment.
function Bigfoot.serverPanicArea(_server, x, y, radius)
  if not sv then
    return
  end
  local f = sv.foot
  if f.mode ~= "air" and f.mode ~= "crouch" and dist2(f.x, f.y, x, y) <= (radius + Bigfoot.radius) ^ 2 then
    f.panic = { x = x, y = y, left = 0.5 }
  end
  for _, s in pairs(sv.squirrels) do
    if dist2(s.x, s.y, x, y) <= (radius + Bigfoot.squirrelRadius) ^ 2 then
      s.panic = { x = x, y = y, left = 0.5 }
    end
  end
end

--- A freeze landed on (x, y): he (not in the air) and his squirrels stand still.
function Bigfoot.serverFreezeArea(_server, x, y, radius, seconds)
  if not sv then
    return
  end
  local f = sv.foot
  if f.mode ~= "air" and dist2(f.x, f.y, x, y) <= (radius + Bigfoot.radius) ^ 2 then
    f.frozen = math.max(f.frozen, seconds)
  end
  for _, s in pairs(sv.squirrels) do
    if dist2(s.x, s.y, x, y) <= (radius + Bigfoot.squirrelRadius) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- For tests.
function Bigfoot.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { foot, squirrels = { id -> s }, leap, rings, pops, shake, lastTick }
local time = 0

function Bigfoot.start()
  cl = { foot = nil, squirrels = {}, leap = nil, rings = {}, pops = {}, shake = 0, lastTick = 0 }
end

function Bigfoot.stop()
  cl = nil
end

--- Where he is drawn now, for the minimap.
function Bigfoot.where()
  local f = cl and cl.foot
  if f then
    return f.dx, f.dy
  end
  return nil
end

local function ease(e, k)
  local ex, ey = e.x - e.dx, e.y - e.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    e.dx, e.dy = e.x, e.y
  else
    e.dx, e.dy = e.dx + ex * k, e.dy + ey * k
  end
end

function Bigfoot.update(dt, _client, camera)
  time = time + dt
  if not cl then
    return
  end
  local k = math.min(1, dt * SMOOTHING)
  if cl.foot then
    ease(cl.foot, k)
  end
  for _, s in pairs(cl.squirrels) do
    ease(s, math.min(1, k * 1.5)) -- they are quick: less lag
  end
  local leap = cl.leap
  if leap then
    leap.t = leap.t + dt
    if leap.t > leap.total + 0.5 then
      cl.leap = nil -- the landing never came
    end
  end
  for _, list in ipairs({ cl.rings, cl.pops }) do
    for i = #list, 1, -1 do
      list[i].t = list[i].t + dt
      if list[i].t > 0.8 then
        table.remove(list, i)
      end
    end
  end
  if cl.shake > 0 then
    cl.shake = math.max(0, cl.shake - dt)
    local a = cl.shake * 30
    camera.x = camera.x + (random() - 0.5) * a
    camera.y = camera.y + (random() - 0.5) * a
  end
end

function Bigfoot.drawBelowCars()
  if cl and cl.leap then
    Render.landing(cl.leap, time)
  end
end

--- A squirrel bursting: a red puff swelling out and fading.
local function drawPop(p)
  local k = p.t / 0.8
  love.graphics.setColor(0.8, 0.1, 0.08, (1 - k) * 0.7)
  love.graphics.circle("fill", p.x, p.y, 6 + 18 * math.min(1, k * 3))
  love.graphics.setColor(1, 0.75, 0.4, (1 - k * 3) * 0.9)
  love.graphics.circle("fill", p.x, p.y, 5 + 8 * k)
end

function Bigfoot.drawAboveCars()
  if not cl then
    return
  end
  for _, s in pairs(cl.squirrels) do
    Render.squirrel(s, time)
  end
  for _, p in ipairs(cl.pops) do
    drawPop(p)
  end
  for _, ring in ipairs(cl.rings) do
    Render.slamRing(ring)
  end
  if cl.foot then
    Render.foot(cl.foot, cl.leap, time, Bigfoot.health, Bigfoot.radius)
  end
  love.graphics.setColor(1, 1, 1)
end

--- An arrow at the edge of the screen pointing at him while he is off it.
local function drawPointer(camera, f)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local sx, sy = w / 2 + (f.dx - camera.x) * s, h / 2 + (f.dy - camera.y) * s
  local m = 40
  if sx >= 0 and sx <= w and sy >= 0 and sy <= h then
    return
  end
  local a = math.atan2(sy - h / 2, sx - w / 2)
  local ex = math.max(m, math.min(w - m, sx))
  local ey = math.max(m, math.min(h - m, sy))
  local pulse = 0.6 + 0.4 * math.sin(time * 8)
  love.graphics.push()
  love.graphics.translate(ex, ey)
  love.graphics.rotate(a)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.polygon("fill", 16, 0, -8, -11, -8, 11)
  love.graphics.setColor(1, 0.2, 0.1, pulse)
  love.graphics.polygon("fill", 13, 0, -6, -8, -6, 8)
  love.graphics.pop()
end

--- His health along the bottom, how many squirrels are loose, and a
--- pointer to him when he is off screen.
function Bigfoot.drawHUD(_client, camera)
  local f = cl and cl.foot
  if not f then
    return
  end
  if camera then
    drawPointer(camera, f)
  end
  local w, h = love.graphics.getDimensions()
  local bw, bh = 380, 14
  local bx, by = math.floor((w - bw) / 2), h - 110 -- above the ability circles
  local n = 0
  for _ in pairs(cl.squirrels) do
    n = n + 1
  end
  local title = n > 0 and ("BIGFOOT  -  %d squirrels loose"):format(n) or "BIGFOOT"
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(title, 1, by - 19, w, "center")
  love.graphics.setColor(1, 0.6, 0.3)
  love.graphics.printf(title, 0, by - 20, w, "center")
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4, 3)
  love.graphics.setColor(0.6, 0.35, 0.15)
  love.graphics.rectangle("fill", bx, by, bw * math.max(0, f.hp / Bigfoot.health), bh, 2)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.rectangle("line", bx, by, bw, bh, 2)
end

local function splat(x, y, angle, pitch)
  if Features.byName.pedestrians then
    require("src.features.pedestrians.gibs").splat(x, y, angle)
    require("src.features.pedestrians.sounds").play("splat", x, y, pitch)
  end
end

Bigfoot.clientMessages = {
  EBF_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.lastTick then
      return
    end
    cl.lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    local f = cl.foot or { dx = x, dy = y, bob = random() * 6 }
    f.x, f.y = x, y
    f.angle = tonumber(args[4]) or f.angle or 0
    f.hp = tonumber(args[5]) or f.hp or Bigfoot.health
    f.mode = MODE_NAMES[args[6]] or "idle"
    f.swipe = args[7] == "1"
    cl.foot = f
    local seen = {}
    for i = 8, #args - 3, 4 do
      local id, sx, sy = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and sx and sy then
        local s = cl.squirrels[id] or { dx = sx, dy = sy, bob = random() * 6 }
        s.x, s.y, s.angle = sx, sy, tonumber(args[i + 3]) or s.angle or 0
        cl.squirrels[id] = s
        seen[id] = true
      end
    end
    for id in pairs(cl.squirrels) do
      if not seen[id] then
        cl.squirrels[id] = nil
      end
    end
  end,
  EBF_LEAP = function(_client, args)
    local v = {}
    for i = 1, 6 do
      v[i] = tonumber(args[i])
      if not v[i] then
        return
      end
    end
    if cl then
      cl.leap = { fx = v[1], fy = v[2], tx = v[3], ty = v[4], total = v[5], r = v[6], t = 0 }
    end
  end,
  EBF_SLAM = function(client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (cl and x and y and r) then
      return
    end
    cl.leap = nil
    local f = cl.foot
    if f then
      f.x, f.y, f.dx, f.dy = x, y, x, y
    end
    cl.rings[#cl.rings + 1] = { x = x, y = y, r = r, t = 0 }
    Sounds.play("slam", x, y)
    local mx, my = client:myPose()
    if mx and dist2(mx, my, x, y) < (r * 3) ^ 2 then
      cl.shake = 0.4
    end
  end,
  EBF_LITTER = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("roar", x, y, 1.15)
      Sounds.play("chitter", x, y, 0.8)
    end
  end,
  EBF_POP = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if not (cl and x and y) then
      return
    end
    cl.pops[#cl.pops + 1] = { x = x, y = y, t = 0 }
    for id, s in pairs(cl.squirrels) do
      if dist2(s.x, s.y, x, y) < 4 then
        cl.squirrels[id] = nil -- gone now, not at the next sync
      end
    end
    splat(x, y, angle, 1.4 + random() * 0.3)
  end,
  EBF_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if not (x and y) then
      return
    end
    for _ = 1, 4 do
      splat(x + (random() - 0.5) * 30, y + (random() - 0.5) * 30, angle + (random() - 0.5) * 2, 0.7)
    end
    Sounds.play("roar", x, y, 0.7)
  end,
}

return Bigfoot
