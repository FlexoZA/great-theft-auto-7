-- The Tripod: a city event (see init.lua), and a boss (bosses/init.lua has
-- the standard). First a storm: for `stormTime` seconds the sky goes dark
-- and lightning comes down at random round every player, some of it right
-- on them. Each bolt is marked on the ground for `boltWarn` seconds (a
-- flickering ring) and then strikes, hurting everything in `boltRadius`:
-- players and bots on foot, cars, pedestrians. In the storm's last second
-- the bolts hammer one crossing away from everyone, and the tripod rises
-- there.
--
-- A war machine out of War of the Worlds, it sounds its horn and strides the streets on
-- its three long legs, sowing red weed where it walks. It is taller than
-- the buildings: once it has somebody in sight it steps straight over
-- whatever is in the way to stand off from them, and when nobody is near
-- it goes back to the streets.
--
-- The heat ray: it picks the nearest player in range and warms the ray up
-- on them (`charge`), the aim following them, and a ring closing on them
-- says so. `lock` seconds before it fires, the aim stops following and
-- stays where they were: it burns that spot for `fire` seconds, hurting
-- anyone on foot (`burnDps`) and any car (`carDps`) standing in it and
-- burning pedestrians up. Dash or sprint out of it in that last moment and
-- it misses. Whoever it kills on foot is left a heap of ash.
--
-- The sweep: when somebody (a player or a bot) is in front of it and it
-- has the breath, it may plant its legs and sweep the heat ray across the
-- ground in front of it instead: an arc `sweepRadius` out, `sweepArc` wide,
-- lit up red for `sweepWarn` seconds first so there is time to get off it,
-- then burned from one end to the other over `sweepTime`. Everything in
-- the band as the beam passes burns (`sweepDps`, `sweepCarDps`: hot, as it
-- is only on a spot for a moment): players and bots on foot, every car,
-- and the pedestrians.
--
-- The tentacles: a player on foot who comes under it (`grabReach`) may be
-- lashed at (`grabWindup` to get clear) and snatched up into the cage at
-- its back, held still there (the `serverHeld` / `held` conventions: no
-- walking, no shooting, no dodging), taking `cageDps`. The others get them
-- out by hurting it: once it has taken `dropAfter` of its health since the
-- grab, it lets go. It drops them anyway after `cageTime`.
--
-- It is beaten by shooting its head (`radius` round where it stands); the
-- legs are out of reach. It has breath like every boss (bosses/stamina.lua):
-- striding after somebody spends it, the heat ray and a grab cost some,
-- and winded it only ambles and does neither. Its health scales with the
-- humans in the game. Down, it crashes to the ground (the tripod feature
-- keeps the wreck), spills koins and drops its heat ray, an ability with a
-- beam and a sweep ("ability-heatray", abilities/heatray.lua), in a tier
-- rolled from `dropTiers`.
--
-- The host owns it; clients hear it at 15 Hz and draw it ahead along the
-- way it is walking.
--
-- Messages (the events feature registers them)
--   server -> all  ETR_STATE <tick> <x> <y> <facing> <speed> <hp> <max> <target> <phase> <phaseT>
--                            <lockX> <lockY> <grabId> <cagedId> <sweepA0> <sweepA1> <stamina> <winded>
--                            (unreliable, 15 Hz)
--     target: the player the heat ray is on, 0 for nobody
--     phase:  0 resting, 1 charging, 2 locked (about to fire), 3 firing, 4 sweep lit up, 5 sweeping;
--             phaseT seconds into it
--     lockX, lockY: where it will burn / is burning (phases 2 and 3)
--     grabId: the player a tentacle is lashing at, 0 for nobody; cagedId: who is in the cage
--     sweepA0, sweepA1: the angles the sweep runs from and to (phases 4 and 5), round (x, y)
--   server -> all  ETR_BOLT <x> <y> <warn>      lightning will strike there in `warn` seconds
--   server -> all  ETR_RISE <x> <y>             the storm is over and the tripod rises there
--   server -> all  ETR_ASH  <x> <y> <angle>     the heat ray (or lightning) burned somebody to ash there
--   server -> all  ETR_DOWN <x> <y> <angle>     it went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Car = require("src.car")
local Traffic = require("src.features.bots.traffic")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")
local Render = require("src.features.tripod.render")
local Sounds = require("src.features.tripod.sounds")
local Remains = require("src.features.tripod")

local Tripod = {
  key = "tripod",
  title = "A STORM IS COMING",
  subtitle = "Lightning is striking the city. Keep moving: something is coming down with it.",
  wonTitle = "THE TRIPOD IS DOWN",
  wonSubtitle = "It dropped its heat ray ability. First one there takes it.",
  color = { 0.60, 0.88, 1.00 },
  menu = "A war machine on three legs burns you with its heat ray and snatches you into its cage. Drops the heat ray.",
}

-- Tuning ------------------------------------------------------------------
Tripod.stormTime = 8 -- seconds of lightning before it rises
Tripod.boltEvery = 0.6 -- seconds between bolts round each player, give or take
Tripod.boltWarn = 0.7 -- seconds a bolt is marked on the ground before it strikes
Tripod.boltRadius = 50 -- px round a strike that it hurts
Tripod.boltDamage = 35 -- to somebody on foot
Tripod.boltCarDamage = 45 -- to a car
Tripod.boltAimed = 0.3 -- chance a bolt comes down right on a player (within 50 px)
Tripod.boltNear = 80 -- px; the others land this far from them...
Tripod.boltFar = 450 -- ...to this far
Tripod.health = 4000 -- 200 pistol rounds, for one player (more humans, more: bosses/init.lua)
Tripod.radius = Render.RADIUS -- px round its centre that a round hits the head
Tripod.roamSpeed = 60 -- px/s down the streets with nobody about
Tripod.huntSpeed = 95 -- px/s striding after somebody: a walk (45) loses, a sprint (170) gets away
Tripod.windedSpeed = 35 -- px/s winded
Tripod.breath = { -- its stamina (bosses/stamina.lua has the rule and the defaults)
  drain = 8, -- per second striding after somebody (~12 s)
  regen = 12,
  recovered = 50,
  breath = 30, -- in it before it uses the heat ray or a tentacle
}
Tripod.rayCost = 20 -- breath the heat ray costs
Tripod.grabCost = 25 -- breath a grab costs
Tripod.huntRange = 900 -- px; it goes after a player this close
Tripod.standOff = 240 -- px; it stops this far from them to shoot
Tripod.rayRange = 650 -- px; it turns the heat ray on a player this close
Tripod.rest = 2.5 -- seconds between bursts
Tripod.charge = 2 -- seconds the heat ray warms up on somebody, the aim following them...
Tripod.lock = 0.35 -- ...the last of which it stops following: the moment to get out of it
Tripod.fire = 1.4 -- seconds it burns the spot
Tripod.burnRadius = 34 -- px round the spot that burns
Tripod.burnDps = 120 -- to somebody on foot (168 over a whole burst)
Tripod.carDps = 160 -- to a car
Tripod.sweepCost = 30 -- breath a sweep costs
Tripod.sweepEvery = 8 -- seconds between sweeps
Tripod.sweepChance = 0.5 -- when both could go, the chance it sweeps rather than aims
Tripod.sweepRadius = 260 -- px out in front the beam sweeps the ground
Tripod.sweepArc = 2.0 -- radians the sweep covers, side to side
Tripod.sweepWarn = 1.0 -- seconds the arc is lit before the beam comes
Tripod.sweepTime = 1.8 -- seconds the beam takes from one end to the other
Tripod.sweepDps = 480 -- to somebody on foot as it passes: it is on one spot about a quarter of a second (~120)
Tripod.sweepCarDps = 640 -- to a car (~160)
Tripod.grabReach = 130 -- px from its centre: a player on foot this close is under it
Tripod.grabWindup = 0.7 -- seconds from the lash to the snatch: get clear
Tripod.grabSlack = 50 -- px past `grabReach` still caught when it lands
Tripod.grabEvery = 6 -- seconds between grabs
Tripod.cageDps = 20
Tripod.cageTime = 7 -- seconds before it drops somebody anyway
Tripod.dropAfter = 0.08 -- share of its health that, taken since the grab, makes it let go
Tripod.bulletDamage = 20 -- what a round takes off it when it doesn't say (a blast)
Tripod.spawnNear = 900 -- px; it comes down about this far from the nearest player
Tripod.spawnFar = 1600
Tripod.drops = 60 -- koins it spills
Tripod.drop = "ability-heatray" -- the pickup it leaves, in a tier from `dropTiers`
Tripod.dropTiers = { -- chance in a hundred of each tier
  { "common", 45 },
  { "uncommon", 30 },
  { "rare", 20 },
  { "legendary", 5 },
}
Tripod.weedEvery = 70 -- px walked between clumps of red weed
Tripod.weedMax = 120 -- clumps kept; the oldest goes first
Tripod.hornEvery = 30 -- seconds between blasts on the horn

local SYNC_EVERY = 2 -- server ticks between ETR_STATE packets
local BURN_TICK = 0.1 -- seconds between bites of the heat ray and the cage
local PED_EVERY = 0.2 -- seconds between pedestrians burned
local CAGE_BACK = 50 -- px behind its centre the cage hangs
local SMOOTHING = 6 -- per second, the easing of what is drawn
local SNAP = 300 -- px; a jump this big is a spawn, not a step
local TURN = 1.2 -- rad/s the drawn heading turns at

local REST, CHARGE, LOCKED, FIRE, SWEEP_WARN, SWEEP = 0, 1, 2, 3, 4, 5

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Turn angle `a` toward `b` by at most `step`.
local function turnToward(a, b, step)
  local d = (b - a + math.pi) % (2 * math.pi) - math.pi
  if math.abs(d) <= step then
    return b
  end
  return a + (d > 0 and step or -step)
end

--- A tier from `Tripod.dropTiers`, as likely as its weight.
function Tripod.rollTier()
  local total = 0
  for _, t in ipairs(Tripod.dropTiers) do
    total = total + t[2]
  end
  local roll = random() * total
  for _, t in ipairs(Tripod.dropTiers) do
    roll = roll - t[2]
    if roll < 0 then
      return t[1]
    end
  end
  return Tripod.dropTiers[1][1]
end

-- Server --------------------------------------------------------------------

local sv = nil -- { t = the tripod, events, syncIn, time }

--- The street grid of the city in play, or nil.
local function graph()
  local city = Features.byName["city-map"]
  return city and city.map and Traffic.graph(city.map) or nil
end

--- The humans in the world, as { player, x, y, onFoot }.
local function people(server)
  local list = {}
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      list[#list + 1] = { player = p, x = x, y = y, onFoot = onFoot }
    end
  end
  return list
end

--- A crossing about `spawnNear`..`spawnFar` px from the nearest player.
local function spawnNode(g, server)
  local humans = people(server)
  local best, bestScore
  for _, node in pairs(g.nodes) do
    if #node.exits > 0 then
      local near = Tripod.spawnNear
      for i, h in ipairs(humans) do
        local d = math.sqrt(dist2(node.x, node.y, h.x, h.y))
        near = i == 1 and d or math.min(near, d)
      end
      local score = -math.max(0, Tripod.spawnNear - near) * 2 - math.max(0, near - Tripod.spawnFar) + random() * 200
      if not bestScore or score > bestScore then
        best, bestScore = node, score
      end
    end
  end
  return best
end

--- The crossing nearest (x, y), to get back onto the streets from.
local function nearestNode(g, x, y)
  local best, bestD
  for _, node in pairs(g.nodes) do
    local d = dist2(node.x, node.y, x, y)
    if #node.exits > 0 and (not bestD or d < bestD) then
      best, bestD = node, d
    end
  end
  return best
end

--- A street out of crossing `node`: any but straight back, unless it is a
--- dead end.
local function pickStreet(t, node)
  local options = {}
  for _, e in ipairs(node.exits) do
    if not (t.street and e.dx == -t.street.dx and e.dy == -t.street.dy) then
      options[#options + 1] = e
    end
  end
  if #options == 0 then
    options = node.exits
  end
  local e = options[random(#options)]
  t.street, t.to = e, e.node
end

function Tripod.serverBegin(server, events)
  local g = graph()
  local node = g and spawnNode(g, server)
  if not node then
    return nil
  end
  local hp = Bosses.health(Tripod.health, server)
  local t = {
    x = node.x, y = node.y, facing = 0, speed = 0, hp = hp, max = hp, frozen = 0,
    breath = Stamina.new(Tripod.breath),
    target = 0, phase = REST, phaseT = 0, lockX = 0, lockY = 0,
    grab = nil, -- { id, t } a tentacle lashing at somebody
    caged = nil, -- { id, t, taken, bite } somebody in the cage
    grabIn = Tripod.grabEvery, burnIn = 0, pedIn = 0, sweepIn = Tripod.sweepEvery / 2, sweepA0 = 0, sweepA1 = 0,
  }
  pickStreet(t, node)
  sv = { t = t, events = events, syncIn = 0, time = 0, storm = { t = 0, nextIn = {}, bolts = {} } }
  return node.x, node.y
end

--- Let whoever is in the cage go, where the cage is.
local function release(t)
  t.caged = nil
  t.grabIn = Tripod.grabEvery
end

function Tripod.serverStop()
  sv = nil
end

-- Walking --------------------------------------------------------------------

--- Walk `dist` px down the middle of its street, taking the next one at
--- each crossing. Off the streets (after a hunt) it heads for the nearest
--- crossing first.
local function roam(t, dist)
  if not t.to then
    local g = graph()
    local node = g and nearestNode(g, t.x, t.y)
    if not node then
      return
    end
    t.street, t.to = nil, node
  end
  for _ = 1, 8 do
    local wx, wy = t.to.x, t.to.y
    local d = math.sqrt(dist2(wx, wy, t.x, t.y))
    if d > dist then
      t.x, t.y = t.x + (wx - t.x) / d * dist, t.y + (wy - t.y) / d * dist
      t.facing = math.atan2(wy - t.y, wx - t.x)
      return
    end
    t.x, t.y, dist = wx, wy, dist - d
    -- The graph is rebuilt when the city grows: carry on from the new one's crossing.
    local g = graph()
    pickStreet(t, g and g.nodes[t.to.key] or t.to)
  end
end

--- The nearest human it can see within `range` of it, as a people() entry;
--- not whoever is in its cage.
local function nearest(server, t, range)
  local best, bestD
  for _, h in ipairs(people(server)) do
    local d = dist2(h.x, h.y, t.x, t.y)
    if d <= range * range and Features.visible(server, h.player) and not (t.caged and t.caged.id == h.player.id)
      and (not bestD or d < bestD) then
      best, bestD = h, d
    end
  end
  return best
end

--- Stride toward somebody over whatever is in the way, stopping `standOff`
--- short, or roam the streets with nobody about. Returns whether it spent
--- the tick striding after somebody (what costs breath).
local function move(server, t, dt)
  if t.phase >= SWEEP_WARN then
    t.speed = 0 -- legs planted for the sweep
    return false
  end
  local prey = nearest(server, t, Tripod.huntRange)
  if not prey then
    t.speed = Tripod.roamSpeed
    roam(t, t.speed * dt)
    return false
  end
  t.to, t.street = nil, nil -- off the streets now; back to the nearest crossing after
  local dx, dy = prey.x - t.x, prey.y - t.y
  local d = math.sqrt(dx * dx + dy * dy)
  t.facing = math.atan2(dy, dx)
  if d <= Tripod.standOff then
    t.speed = 0
    return false
  end
  t.speed = t.breath:pace(Tripod.huntSpeed, Tripod.windedSpeed)
  local step = math.min(t.speed * dt, d - Tripod.standOff)
  t.x, t.y = t.x + dx / d * step, t.y + dy / d * step
  return not t.breath:winded()
end

-- The heat ray ------------------------------------------------------------

--- Anyone on foot (players and bots) and any car at (x, y) takes a bite of
--- `footDps` / `carDps`; somebody on foot it kills is left as ash.
local function burn(server, t, x, y, footDps, carDps)
  local weapons = Features.byName.weapons
  if not weapons then
    return
  end
  local r = Tripod.burnRadius
  for _, p in pairs(server.players) do
    if Features.present(p) and not (t.caged and t.caged.id == p.id) then
      local px, py, onFoot = Features.bodyPose(server, p)
      if onFoot and dist2(px, py, x, y) <= r * r then
        weapons:serverDamage(server, p, nil, footDps * BURN_TICK, t.facing)
        if p.body and p.body.dead then
          server:broadcast(Protocol.encode("ETR_ASH", fmt(px), fmt(py), ("%.2f"):format(t.facing)))
        end
      end
    end
  end
  if weapons.damageCar then
    local reach = r + Car.WIDTH / 2
    for _, car in pairs(server.vehicles) do
      if not (car.hidden or car.stowed) and dist2(car.x, car.y, x, y) <= reach * reach then
        weapons:damageCar(server, car, nil, carDps * BURN_TICK, 0, t.facing)
      end
    end
  end
end

--- Pedestrians at (x, y) burn up, a few at a time.
local function burnPeds(server, t, x, y, dt)
  t.pedIn = t.pedIn - dt
  local peds = Features.byName.pedestrians
  if t.pedIn > 0 or not (peds and peds.serverShotAt) then
    return
  end
  t.pedIn = PED_EVERY
  for _ = 1, 3 do
    if not peds:serverShotAt(server, x, y, Tripod.burnRadius, 0, t.facing) then
      break
    end
  end
end

--- Where the sweeping beam is `k` (0..1) of the way along.
local function sweepPoint(t, k)
  local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * k
  return t.x + math.cos(a) * Tripod.sweepRadius, t.y + math.sin(a) * Tripod.sweepRadius
end

--- Is anybody (a player or a bot, not the one in the cage) out in front in
--- reach of a sweep?
local function sweepWorth(server, t)
  local near, far = Tripod.sweepRadius - Tripod.burnRadius * 2, Tripod.sweepRadius + Tripod.burnRadius * 2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and not (t.caged and t.caged.id == p.id) then
      local px, py = Features.bodyPose(server, p)
      local d = math.sqrt(dist2(px, py, t.x, t.y))
      local off = (math.atan2(py - t.y, px - t.x) - t.facing + math.pi) % (2 * math.pi) - math.pi
      if d >= near and d <= far and math.abs(off) <= Tripod.sweepArc / 2 then
        return true
      end
    end
  end
  return false
end

--- Start a sweep across the ground in front, from one side or the other.
local function startSweep(t)
  local side = random() < 0.5 and 1 or -1
  t.sweepA0 = t.facing - side * Tripod.sweepArc / 2
  t.sweepA1 = t.facing + side * Tripod.sweepArc / 2
  t.breath:spend(Tripod.sweepCost)
  t.sweepIn = Tripod.sweepEvery
  t.target, t.phase, t.phaseT, t.burnIn, t.pedIn = 0, SWEEP_WARN, 0, 0, 0
end

--- The heat ray's round: rest, pick somebody and charge on them, lock where
--- they are, then burn there.
local function ray(server, t, dt)
  t.phaseT = t.phaseT + dt
  t.sweepIn = t.sweepIn - dt
  if t.phase == REST then
    if t.phaseT < Tripod.rest then
      return
    end
    local canSweep = t.sweepIn <= 0 and t.breath:has(Tripod.sweepCost) and sweepWorth(server, t)
    if canSweep and (random() < Tripod.sweepChance or not nearest(server, t, Tripod.rayRange)) then
      startSweep(t)
      return
    end
    if t.breath:has(Tripod.rayCost) then
      local prey = nearest(server, t, Tripod.rayRange)
      if prey then
        t.breath:spend(Tripod.rayCost)
        t.target, t.phase, t.phaseT = prey.player.id, CHARGE, 0
      end
    end
    return
  elseif t.phase == FIRE then
    t.burnIn = t.burnIn - dt
    if t.burnIn <= 0 then
      t.burnIn = t.burnIn + BURN_TICK
      burn(server, t, t.lockX, t.lockY, Tripod.burnDps, Tripod.carDps)
    end
    burnPeds(server, t, t.lockX, t.lockY, dt)
    if t.phaseT >= Tripod.fire then
      t.target, t.phase, t.phaseT = 0, REST, 0
    end
    return
  elseif t.phase == SWEEP_WARN then
    if t.phaseT >= Tripod.sweepWarn then
      t.phase, t.phaseT = SWEEP, 0
    end
    return
  elseif t.phase == SWEEP then
    local x, y = sweepPoint(t, math.min(1, t.phaseT / Tripod.sweepTime))
    t.burnIn = t.burnIn - dt
    if t.burnIn <= 0 then
      t.burnIn = t.burnIn + BURN_TICK
      burn(server, t, x, y, Tripod.sweepDps, Tripod.sweepCarDps)
    end
    burnPeds(server, t, x, y, dt)
    if t.phaseT >= Tripod.sweepTime then
      t.phase, t.phaseT = REST, 0
    end
    return
  end
  -- Charging: the aim follows them until the lock, then stays put.
  local p = server.players[t.target]
  if t.phase == CHARGE then
    if not (p and Features.present(p)) then
      t.target, t.phase, t.phaseT = 0, REST, 0
      return
    end
    t.lockX, t.lockY = Features.bodyPose(server, p)
    if t.phaseT >= Tripod.charge - Tripod.lock then
      t.phase = LOCKED
    end
  elseif t.phase == LOCKED and t.phaseT >= Tripod.charge then
    t.phase, t.phaseT, t.burnIn, t.pedIn = FIRE, 0, 0, 0
  end
end

-- The tentacles and the cage ----------------------------------------------

--- Where the cage hangs.
local function cagePoint(t)
  return t.x - math.cos(t.facing) * CAGE_BACK, t.y - math.sin(t.facing) * CAGE_BACK
end

--- Lash at somebody on foot under it, snatch them if they are still there
--- when it lands, and keep whoever is in the cage: pinned in it, hurting,
--- until it has been hurt enough, `cageTime` is up, or they are gone.
local function tentacles(server, t, dt)
  local c = t.caged
  if c then
    local p = server.players[c.id]
    c.t = c.t + dt
    if not (p and p.body and Features.present(p)) or p.vehicle or p.body.dead
      or c.t >= Tripod.cageTime or c.taken >= t.max * Tripod.dropAfter then
      release(t)
      return
    end
    p.body.x, p.body.y = cagePoint(t)
    c.bite = c.bite - dt
    local weapons = Features.byName.weapons
    if c.bite <= 0 and weapons then
      c.bite = c.bite + BURN_TICK
      weapons:serverDamage(server, p, nil, Tripod.cageDps * BURN_TICK, t.facing)
    end
    return
  end
  local g = t.grab
  if g then
    g.t = g.t + dt
    if g.t < Tripod.grabWindup then
      return
    end
    t.grab = nil
    local p = server.players[g.id]
    local reach = Tripod.grabReach + Tripod.grabSlack
    if p and p.body and not p.vehicle and not p.body.dead and Features.present(p)
      and dist2(p.body.x, p.body.y, t.x, t.y) <= reach * reach then
      t.caged = { id = g.id, t = 0, taken = 0, bite = 0 }
      if t.target == g.id then
        t.target, t.phase, t.phaseT = 0, REST, 0 -- it has them: no need to burn them
      end
    else
      t.grabIn = Tripod.grabEvery / 2 -- missed: another go sooner
    end
    return
  end
  t.grabIn = t.grabIn - dt
  if t.grabIn > 0 or not t.breath:has(Tripod.grabCost) then
    return
  end
  local prey = nearest(server, t, Tripod.grabReach)
  if prey and prey.onFoot then
    t.breath:spend(Tripod.grabCost)
    t.grab = { id = prey.player.id, t = 0 }
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local t = sv.t
  local stamina, winded = t.breath:wire()
  local msg = Protocol.encode("ETR_STATE", server.tick, fmt(t.x), fmt(t.y), ("%.2f"):format(t.facing),
    math.floor(t.speed), math.max(0, math.floor(t.hp)), t.max, t.target, t.phase, ("%.2f"):format(t.phaseT),
    fmt(t.lockX), fmt(t.lockY), t.grab and t.grab.id or 0, t.caged and t.caged.id or 0,
    ("%.3f"):format(t.sweepA0), ("%.3f"):format(t.sweepA1), stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

-- The storm ----------------------------------------------------------------

--- Lightning hits (x, y): everyone on foot (players and bots), every car
--- and a few pedestrians in `boltRadius` are hurt.
local function strike(server, x, y)
  local weapons = Features.byName.weapons
  local r = Tripod.boltRadius
  if weapons then
    for _, p in pairs(server.players) do
      if Features.present(p) then
        local px, py, onFoot = Features.bodyPose(server, p)
        if onFoot and dist2(px, py, x, y) <= r * r then
          local angle = math.atan2(py - y, px - x)
          weapons:serverDamage(server, p, nil, Tripod.boltDamage, angle)
          if p.body and p.body.dead then
            server:broadcast(Protocol.encode("ETR_ASH", fmt(px), fmt(py), ("%.2f"):format(angle)))
          end
        end
      end
    end
    if weapons.damageCar then
      local reach = r + Car.WIDTH / 2
      for _, car in pairs(server.vehicles) do
        if not (car.hidden or car.stowed) and dist2(car.x, car.y, x, y) <= reach * reach then
          weapons:damageCar(server, car, nil, Tripod.boltCarDamage, 0, 0)
        end
      end
    end
  end
  local peds = Features.byName.pedestrians
  if peds and peds.serverShotAt then
    for _ = 1, 4 do
      if not peds:serverShotAt(server, x, y, r, 0, 0) then
        break
      end
    end
  end
end

--- Mark a bolt at (x, y), to strike in `warn` seconds.
local function bolt(server, x, y, warn)
  local st = sv.storm
  st.bolts[#st.bolts + 1] = { x = x, y = y, t = warn }
  server:broadcast(Protocol.encode("ETR_BOLT", fmt(x), fmt(y), ("%.2f"):format(warn)))
end

--- The storm before it comes: bolts round every player, then a last few
--- where it will rise, and then it rises.
local function storm(server, dt)
  local st = sv.storm
  st.t = st.t + dt
  for i = #st.bolts, 1, -1 do
    local b = st.bolts[i]
    b.t = b.t - dt
    if b.t <= 0 then
      table.remove(st.bolts, i)
      strike(server, b.x, b.y)
    end
  end
  if st.t < Tripod.stormTime - 1 then
    for _, h in ipairs(people(server)) do
      local id = h.player.id
      st.nextIn[id] = (st.nextIn[id] or random() * Tripod.boltEvery) - dt
      if st.nextIn[id] <= 0 then
        st.nextIn[id] = Tripod.boltEvery * (0.6 + 0.8 * random())
        local a = random() * math.pi * 2
        local d = random() < Tripod.boltAimed and random() * 50
          or Tripod.boltNear + random() * (Tripod.boltFar - Tripod.boltNear)
        bolt(server, h.x + math.cos(a) * d, h.y + math.sin(a) * d, Tripod.boltWarn)
      end
    end
  elseif not st.finale then
    st.finale = true -- the last second: where it will stand
    for i = 0, 2 do
      bolt(server, sv.t.x + (random() - 0.5) * 80, sv.t.y + (random() - 0.5) * 80, 0.4 + i * 0.25)
    end
  end
  if st.t >= Tripod.stormTime and #st.bolts == 0 then
    sv.storm = nil
    server:broadcast(Protocol.encode("ETR_RISE", fmt(sv.t.x), fmt(sv.t.y)))
  end
end

function Tripod.serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  if sv.storm then
    storm(server, dt)
    return
  end
  local t = sv.t
  local striding = false
  if t.frozen > 0 then
    t.frozen = t.frozen - dt
    t.speed = 0
  else
    striding = move(server, t, dt)
    if t.breath:winded() and (t.phase == CHARGE or t.phase == LOCKED) then
      t.target, t.phase = 0, REST -- no breath to keep the ray up (it finishes a burst it began)
    end
    ray(server, t, dt)
    tentacles(server, t, dt)
  end
  t.breath:step(striding, dt)
  sync(server)
end

--- It takes `amount`. At zero it goes down: the cage opens, koins, its heat
--- ray on the ground, and the event is over.
local function hurt(server, amount, by, angle)
  local t = sv.t
  t.hp = t.hp - amount
  if t.caged then
    t.caged.taken = t.caged.taken + amount
  end
  if t.hp > 0 then
    return
  end
  local x, y = t.x, t.y
  release(t)
  server:broadcast(Protocol.encode("ETR_DOWN", fmt(x), fmt(y), ("%.3f"):format(t.facing)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Tripod.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    -- Beside the wreck, on clear ground.
    local dx, dy = x, y
    for i = 0, 7 do
      local a = math.pi / 2 + i * math.pi / 4
      local ox, oy = x + math.cos(a) * 80, y + math.sin(a) * 80
      if not Features.any("blocksPoint", ox, oy) then
        dx, dy = ox, oy
        break
      end
    end
    pickups:serverDrop(server, Tiers.join(Tripod.drop, Tripod.rollTier()), dx, dy)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  sv.events:serverFinish(server, x, y)
end

--- A round passing through (x, y): the `serverShotAt` convention. Only the
--- head can be hit.
function Tripod.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.storm then
    return false
  end
  local t = sv.t
  if dist2(t.x, t.y, x, y) >= (radius + Tripod.radius) ^ 2 then
    return false
  end
  hurt(server, damage or Tripod.bulletDamage, by ~= 0 and by or nil, angle)
  return true
end

--- A freeze landed on it: it stands still, the ray and tentacles with it.
function Tripod.serverFreezeArea(_server, x, y, radius, seconds)
  local t = sv and not sv.storm and sv.t
  if t and dist2(t.x, t.y, x, y) <= (radius + Tripod.radius) ^ 2 then
    t.frozen = math.max(t.frozen, seconds)
  end
end

--- The `serverHeld` convention: whoever is in the cage can't move.
function Tripod.serverHeld(_server, player)
  local c = sv and sv.t.caged
  return c ~= nil and c.id == player.id
end

--- For tests.
function Tripod.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { t, lastTick, weed, weedIn, scorch, hornIn, storm, bolts, flash, dark, rise, cam }
local BOLT_LIFE = 0.35 -- seconds a strike is drawn
local FLASH_RANGE = 800 -- px; a strike closer than this lights up the screen
local time = 0
local drawSweepArc -- below: the arc a sweep is about to burn

--- Thunder, heard wherever you are.
function Tripod.announce(x, y)
  Sounds.play("thunder", x, y)
end

function Tripod.start()
  cl = {
    t = nil, lastTick = 0, weed = {}, weedIn = 0, scorch = {}, hornIn = Tripod.hornEvery,
    storm = true, bolts = {}, flash = 0, dark = 0, rise = nil, cam = nil,
  }
end

--- The storm on this machine: bolts counting down to their strike, the
--- flash of any close by, and the sky darkening and clearing.
local function updateStorm(dt, client)
  cl.dark = cl.dark + ((cl.storm and 1 or 0) - cl.dark) * math.min(1, dt * (cl.storm and 2 or 0.7))
  cl.flash = math.max(0, cl.flash - dt * 3)
  if cl.rise then
    cl.rise.t = cl.rise.t - dt
    if cl.rise.t <= 0 then
      cl.rise = nil
    end
  end
  for i = #cl.bolts, 1, -1 do
    local b = cl.bolts[i]
    b.t = b.t - dt
    if b.t <= 0 and not b.hit then
      b.hit = true
      Sounds.play("thunder", b.x, b.y, 0.8 + random() * 0.4)
      cl.scorch[#cl.scorch + 1] = { x = b.x, y = b.y }
      if #cl.scorch > 60 then
        table.remove(cl.scorch, 1)
      end
      local mx, my = client:myPose()
      if mx then
        local d = math.sqrt(dist2(mx, my, b.x, b.y))
        cl.flash = math.max(cl.flash, 1 - d / FLASH_RANGE)
      end
    end
    if b.hit and b.t <= -BOLT_LIFE then
      table.remove(cl.bolts, i)
    end
  end
end

function Tripod.stop()
  cl = nil
end

--- Where it is drawn now, for the minimap.
function Tripod.where()
  local t = cl and cl.t
  if t then
    return t.dx, t.dy
  end
  return nil
end

--- The `held` convention: is player `id` in the cage, as far as we know?
function Tripod.held(_client, id)
  local t = cl and cl.t
  return t ~= nil and t.caged ~= 0 and t.caged == id
end

function Tripod.update(dt, client, camera)
  time = time + dt
  if not cl then
    return
  end
  cl.cam = camera
  updateStorm(dt, client)
  local t = cl.t
  if not t then
    return
  end
  -- It keeps walking between packets: the server's point moves on with it.
  t.x, t.y = t.x + math.cos(t.facing) * t.speed * dt, t.y + math.sin(t.facing) * t.speed * dt
  t.phaseT = t.phaseT + dt
  local ex, ey = t.x - t.dx, t.y - t.dy
  local moved = 0
  if ex * ex + ey * ey > SNAP * SNAP then
    t.dx, t.dy = t.x, t.y
  else
    local k = math.min(1, dt * SMOOTHING)
    moved = math.sqrt(ex * ex + ey * ey) * k
    t.dx, t.dy = t.dx + ex * k, t.dy + ey * k
  end
  t.angle = turnToward(t.angle, t.facing, TURN * dt)
  t.cycle = t.cycle + moved / Render.STEP
  t.walk = math.min(1, (t.walk or 0) + ((moved > 0.01 and 1 or 0) - (t.walk or 0)) * math.min(1, dt * 3))
  -- The heat ray's aim: on its target while it charges, on the spot once locked.
  local ax, ay
  if t.phase == 1 and t.target ~= 0 then
    ax, ay = client:pose(t.target)
  elseif t.phase == 2 or t.phase == 3 then
    ax, ay = t.lockX, t.lockY
  elseif t.phase == 4 then
    ax, ay = t.dx + math.cos(t.sweepA0), t.dy + math.sin(t.sweepA0)
  elseif t.phase == 5 then
    local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * math.min(1, t.phaseT / Tripod.sweepTime)
    ax, ay = t.dx + math.cos(a), t.dy + math.sin(a)
  end
  local want = ax and math.atan2(ay - t.dy, ax - t.dx) or t.angle
  t.aim = turnToward(t.aim, want, TURN * (ax and (t.phase == 5 and 20 or 4) or 1) * dt)
  -- The horn, now and then, from where it stands.
  cl.hornIn = cl.hornIn - dt
  if cl.hornIn <= 0 then
    cl.hornIn = Tripod.hornEvery
    Sounds.play("horn", t.dx, t.dy)
  end
  -- Red weed where it has walked.
  cl.weedIn = cl.weedIn - moved
  if cl.weedIn <= 0 then
    cl.weedIn = Tripod.weedEvery
    local a = random() * math.pi * 2
    local r = 40 + random() * 60
    cl.weed[#cl.weed + 1] = { x = t.dx + math.cos(a) * r, y = t.dy + math.sin(a) * r, size = 14 + random() * 16,
      seed = random() * 10 }
    if #cl.weed > Tripod.weedMax then
      table.remove(cl.weed, 1)
    end
  end
end

function Tripod.drawBelowCars()
  if not cl then
    return
  end
  for _, w in ipairs(cl.weed) do
    Render.weed(w, time)
  end
  for _, s in ipairs(cl.scorch) do
    love.graphics.setColor(0.06, 0.05, 0.05, 0.55)
    love.graphics.circle("fill", s.x, s.y, Tripod.burnRadius, 24)
    love.graphics.setColor(0.2, 0.1, 0.06, 0.5)
    love.graphics.circle("fill", s.x, s.y, Tripod.burnRadius * 0.6, 20)
  end
end

--- The ring on whoever the heat ray is warming up on, closing in, and on
--- the spot once it has locked: solid and red, the last moment to move.
local function drawTargetRing(x, y, k, locked)
  local c = locked and { 1, 0.25, 0.15 } or Tripod.color
  local ring = Tripod.burnRadius + 40 * (1 - k)
  local pulse = 0.5 + 0.5 * math.sin(time * (locked and 30 or 10 + 20 * k))
  love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.15 * pulse)
  love.graphics.circle("fill", x, y, ring, 32)
  love.graphics.setLineWidth(locked and 3 or 2)
  love.graphics.setColor(c[1], c[2], c[3], 0.6 + 0.4 * pulse)
  love.graphics.circle("line", x, y, ring, 32)
  love.graphics.setLineWidth(1)
end

--- The band of ground the sweep is about to burn (lit red, throbbing faster
--- as the beam comes), and while it sweeps, the part already burned.
drawSweepArc = function(t)
  local lo, hi = math.min(t.sweepA0, t.sweepA1), math.max(t.sweepA0, t.sweepA1)
  local r, w = Tripod.sweepRadius, Tripod.burnRadius * 2
  local k = t.phase == 4 and math.min(1, t.phaseT / Tripod.sweepWarn) or 1
  local pulse = 0.5 + 0.5 * math.sin(time * (10 + 25 * k))
  love.graphics.setLineWidth(w)
  love.graphics.setColor(1, 0.2, 0.1, 0.12 + 0.18 * pulse)
  love.graphics.arc("line", "open", t.dx, t.dy, r, lo, hi, 32)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.3, 0.15, 0.5 + 0.5 * pulse)
  love.graphics.arc("line", "open", t.dx, t.dy, r - w / 2, lo, hi, 32)
  love.graphics.arc("line", "open", t.dx, t.dy, r + w / 2, lo, hi, 32)
  if t.phase == 5 then
    local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * math.min(1, t.phaseT / Tripod.sweepTime)
    love.graphics.setLineWidth(w * 0.7)
    love.graphics.setColor(1, 0.55, 0.15, 0.55)
    love.graphics.arc("line", "open", t.dx, t.dy, r, math.min(t.sweepA0, a), math.max(t.sweepA0, a), 32)
  end
  love.graphics.setLineWidth(1)
end

--- The storm over the world: the sky dark over everything in view, the
--- bolts marked and striking, a flash when one comes down close, and dust
--- thrown up where the tripod rises.
local function drawStorm()
  local cam = cl.cam
  if cam and cl.dark > 0.01 then
    local w, h = love.graphics.getDimensions()
    local s = cam.scale or 1
    love.graphics.setColor(0.02, 0.03, 0.08, 0.62 * cl.dark)
    love.graphics.rectangle("fill", cam.x - w / s, cam.y - h / s, w * 2 / s, h * 2 / s)
  end
  for _, b in ipairs(cl.bolts) do
    if b.hit then
      Render.bolt(b.x, b.y, b.seed, math.min(1, -b.t / BOLT_LIFE))
    else
      Render.boltWarning(b.x, b.y, Tripod.boltRadius, 1 - b.t / b.warn, time)
    end
  end
  if cam and cl.flash > 0 then
    local w, h = love.graphics.getDimensions()
    local s = cam.scale or 1
    love.graphics.setColor(0.85, 0.92, 1, 0.45 * cl.flash)
    love.graphics.rectangle("fill", cam.x - w / s, cam.y - h / s, w * 2 / s, h * 2 / s)
  end
  local r = cl.rise
  if r then
    local k = 1 - r.t / 4
    love.graphics.setLineWidth(6)
    for i = 0, 2 do
      local kk = k * 1.5 - i * 0.15
      if kk > 0 and kk < 1 then
        love.graphics.setColor(0.55, 0.50, 0.45, (1 - kk) * 0.8)
        love.graphics.circle("line", r.x, r.y, 40 + 220 * kk, 48)
      end
    end
    love.graphics.setLineWidth(1)
  end
end

function Tripod.drawAboveCars(client)
  if not cl then
    return
  end
  drawStorm()
  local t = cl.t
  if not t then
    love.graphics.setColor(1, 1, 1)
    return
  end
  local draw = {
    dx = t.dx, dy = t.dy, angle = t.angle, walk = t.walk, cycle = t.cycle, aim = t.aim, hp = t.hp, max = t.max,
    caged = t.caged ~= 0,
  }
  if t.phase == 1 or t.phase == 2 then
    draw.charge = math.min(1, t.phaseT / Tripod.charge)
  elseif t.phase == 3 then
    draw.charge, draw.ray = 1, { x = t.lockX, y = t.lockY }
  elseif t.phase == 4 then
    draw.charge = math.min(1, t.phaseT / Tripod.sweepWarn)
  elseif t.phase == 5 then
    local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * math.min(1, t.phaseT / Tripod.sweepTime)
    draw.charge = 1
    draw.ray = { x = t.dx + math.cos(a) * Tripod.sweepRadius, y = t.dy + math.sin(a) * Tripod.sweepRadius }
  end
  if t.phase == 4 or t.phase == 5 then
    drawSweepArc(t)
  end
  if t.grab ~= 0 then
    local gx, gy = client:pose(t.grab)
    if gx then
      draw.grab = { x = gx, y = gy }
    end
  end
  Render.tripod(draw, time)
  if t.phase == 1 and t.target ~= 0 then
    local x, y = client:pose(t.target)
    if x then
      drawTargetRing(x, y, t.phaseT / Tripod.charge, false)
    end
  elseif t.phase == 2 then
    drawTargetRing(t.lockX, t.lockY, 1, true)
  end
  love.graphics.setColor(1, 1, 1)
end

--- An arrow at the edge of the screen pointing at it while it is off it.
local function drawPointer(camera, t)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local sx, sy = w / 2 + (t.dx - camera.x) * s, h / 2 + (t.dy - camera.y) * s
  local m = 40
  if sx >= 0 and sx <= w and sy >= 0 and sy <= h then
    return
  end
  local a = math.atan2(sy - h / 2, sx - w / 2)
  local pulse = 0.6 + 0.4 * math.sin(time * 8)
  love.graphics.push()
  love.graphics.translate(math.max(m, math.min(w - m, sx)), math.max(m, math.min(h - m, sy)))
  love.graphics.rotate(a)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.polygon("fill", 16, 0, -8, -11, -8, 11)
  love.graphics.setColor(Tripod.color[1], Tripod.color[2], Tripod.color[3], pulse)
  love.graphics.polygon("fill", 13, 0, -6, -8, -6, 8)
  love.graphics.pop()
end

--- A line of warning across the middle of the screen, over a throbbing edge.
local function warn(text, c, strength, speed)
  local w, h = love.graphics.getDimensions()
  local pulse = 0.5 + 0.5 * math.sin(time * speed)
  love.graphics.setLineWidth(18)
  love.graphics.setColor(c[1], c[2], c[3], strength * (0.6 + 0.4 * pulse))
  love.graphics.rectangle("line", 9, 9, w - 18, h - 18)
  love.graphics.setLineWidth(1)
  local UI = require("src.ui")
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf(text, 2, h * 0.32 + 2, w, "center") -- under the event banner
  love.graphics.setColor(c[1], 0.3 + 0.4 * pulse * c[2], c[3])
  love.graphics.printf(text, 0, h * 0.32, w, "center")
end

--- Its boss bar, a pointer to it when it is off screen, and a warning when
--- its heat ray is on me or I am in its cage.
--- A big line across the screen under the event banner, fading with `alpha`.
local function headline(text, c, alpha)
  local UI = require("src.ui")
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7 * alpha)
  love.graphics.printf(text, 2, h * 0.32 + 2, w, "center")
  love.graphics.setColor(c[1], c[2], c[3], alpha)
  love.graphics.printf(text, 0, h * 0.32, w, "center")
end

function Tripod.drawHUD(client, camera)
  if not cl then
    return
  end
  if cl.rise then
    headline("A TRIPOD HAS LANDED", Tripod.color, math.min(1, cl.rise.t))
  end
  local t = cl.t
  if not t then
    if cl.storm then
      headline("Something is coming...", { 0.8, 0.85, 1 }, 0.5 + 0.3 * math.sin(time * 3))
    end
    love.graphics.setColor(1, 1, 1)
    return
  end
  if camera then
    drawPointer(camera, t)
  end
  BossBar.draw({
    title = t.winded and "THE TRIPOD  -  winded, shoot the head!" or "THE TRIPOD",
    titleColor = Tripod.color, fill = { 0.45, 0.75, 0.95 },
    hp = t.hp, max = t.max, stamina = t.stamina, staminaMax = Stamina.defaults.max, winded = t.winded,
  })
  local me = client.myId
  local mx, my = client:myPose()
  local inSweep = false
  if mx and (t.phase == 4 or t.phase == 5) then
    local d = math.sqrt(dist2(mx, my, t.dx, t.dy))
    local lo, hi = math.min(t.sweepA0, t.sweepA1), math.max(t.sweepA0, t.sweepA1)
    local mid = (lo + hi) / 2
    local off = (math.atan2(my - t.dy, mx - t.dx) - mid + math.pi) % (2 * math.pi) - math.pi
    inSweep = math.abs(d - Tripod.sweepRadius) <= Tripod.burnRadius * 1.5 and math.abs(off) <= (hi - lo) / 2 + 0.1
  end
  if t.caged == me then
    warn("CAUGHT!  Hurt it to make it drop you", { 1, 0.4, 0.3 }, 0.35, 6)
  elseif t.grab == me then
    warn("GET OUT FROM UNDER IT!", { 1, 0.5, 0.2 }, 0.4, 20)
  elseif inSweep then
    warn("GET OFF THE RED LINE!", { 1, 0.25, 0.15 }, 0.45, 25)
  elseif t.target == me and t.phase == 2 then
    warn("DODGE!", { 1, 0.25, 0.15 }, 0.5, 30)
  elseif t.target == me and t.phase == 1 then
    warn("THE TRIPOD HAS SEEN YOU", Tripod.color, 0.2 + 0.2 * t.phaseT / Tripod.charge, 10)
  end
  love.graphics.setColor(1, 1, 1)
end

Tripod.clientMessages = {
  ETR_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.lastTick then
      return
    end
    cl.lastTick = tick
    cl.storm = false -- it is up (a latecomer hears no ETR_RISE)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    local facing = tonumber(args[4]) or 0
    local t = cl.t or { dx = x, dy = y, angle = facing, aim = facing, cycle = 0, phase = 0, grab = 0 }
    local was, wasGrab = t.phase, t.grab
    t.x, t.y, t.facing = x, y, facing
    t.speed = tonumber(args[5]) or 0
    t.hp = tonumber(args[6]) or t.hp or Tripod.health
    t.max = tonumber(args[7]) or t.max or Tripod.health
    t.target = tonumber(args[8]) or 0
    t.phase = tonumber(args[9]) or 0
    t.phaseT = tonumber(args[10]) or 0
    t.lockX, t.lockY = tonumber(args[11]) or 0, tonumber(args[12]) or 0
    t.grab = tonumber(args[13]) or 0
    t.caged = tonumber(args[14]) or 0
    t.sweepA0, t.sweepA1 = tonumber(args[15]) or 0, tonumber(args[16]) or 0
    local stamina, winded = Stamina.read(args, 17)
    t.stamina, t.winded = stamina or t.stamina, winded
    cl.t = t
    -- The sounds of what it just started doing.
    if t.phase == 1 and was ~= 1 then
      Sounds.play("charge", t.dx, t.dy)
    elseif t.phase == 3 and was ~= 3 then
      Sounds.play("burn", t.lockX, t.lockY)
      cl.scorch[#cl.scorch + 1] = { x = t.lockX, y = t.lockY }
      if #cl.scorch > 30 then
        table.remove(cl.scorch, 1)
      end
    end
    if t.phase == 4 and was ~= 4 then
      Sounds.play("charge", t.dx, t.dy, 1.6)
    elseif t.phase == 5 and was ~= 5 then
      Sounds.play("burn", t.dx, t.dy, 0.9)
    end
    if was == 5 and t.phase ~= 5 then -- the sweep is done: the ground it crossed is burned
      for i = 0, 8 do
        local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * i / 8
        cl.scorch[#cl.scorch + 1] = { x = t.x + math.cos(a) * Tripod.sweepRadius,
          y = t.y + math.sin(a) * Tripod.sweepRadius, trail = true }
      end
      while #cl.scorch > 60 do
        table.remove(cl.scorch, 1)
      end
    end
    if t.grab ~= 0 and wasGrab ~= t.grab then
      Sounds.play("grab", t.dx, t.dy)
    end
  end,
  ETR_BOLT = function(_client, args)
    local x, y, due = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if cl and x and y and due then
      cl.bolts[#cl.bolts + 1] = { x = x, y = y, t = due, warn = math.max(0.01, due), seed = random() }
    end
  end,
  ETR_RISE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if cl and x and y then
      cl.storm = false
      cl.rise = { x = x, y = y, t = 4 }
      Sounds.play("horn", x, y)
    end
  end,
  ETR_ASH = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Remains.ashAt(x, y, tonumber(args[3]) or 0)
    end
  end,
  ETR_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Remains.wreckAt(x, y, tonumber(args[3]) or 0)
      Sounds.play("fall", x, y)
    end
  end,
}

return Tripod
