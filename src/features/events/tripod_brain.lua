-- The Tripod's brain, on the host: where it walks, who it burns and who it
-- snatches, each tick. Its event (tripod.lua) owns the storm it comes in
-- on, its health and the wire; it hands it in as `t` and its own table
-- (its numbers) as `T`.
--
--   roam     nobody about: down the middle of the streets (bots/traffic.lua's
--            graph), taking a street at every crossing
--   hunt     a player within `huntRange`: it steps straight over whatever is
--            in the way, to `standOff` from them
--   ray      the heat ray, on its own round whatever the legs are doing:
--            rest, then either a charge on the nearest player in reach (the
--            aim following them, locking `lock` before it fires) and a burn
--            on that spot, or, with somebody out in front and the breath for
--            it, a sweep across the ground in front of it
--   grab     a player on foot under it: a tentacle lashes, and if they are
--            still there it snatches them into the cage, where they are held
--            and hurt until it has been hurt enough or `cageTime` is up
--   heal     badly hurt (bosses/heal.lua): it strides over everything to the
--            nearest medkit lying within `healRange`, the heat ray still at
--            work, and a tentacle snatches it up once it is within reach
--
-- Frozen, it stands; winded, it ambles and keeps no ray going it hasn't
-- already fired. Under a player's ability about to land (a freeze's
-- warning ring: bosses/dodge.lua) it strides straight out of it, the ray
-- still at work, unless its legs are planted for a sweep.

local Features = require("src.features")
local Car = require("src.car")
local Traffic = require("src.features.bots.traffic")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local BURN_TICK = 0.1 -- seconds between bites of the heat ray and the cage
local PED_EVERY = 0.2 -- seconds between pedestrians burned
local CAGE_BACK = 50 -- px behind its centre the cage hangs

local REST, CHARGE, LOCKED, FIRE, SWEEP_WARN, SWEEP = 0, 1, 2, 3, 4, 5
Brain.REST = REST

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

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
function Brain.pickStreet(t, node)
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

--- Let whoever is in the cage go, where the cage is.
function Brain.release(T, t)
  t.caged = nil
  t.grabIn = T.grabEvery
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
    Brain.pickStreet(t, g and g.nodes[t.to.key] or t.to)
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
local function move(T, server, t, dt)
  if t.phase >= SWEEP_WARN then
    t.speed = 0 -- legs planted for the sweep
    return false
  end
  local prey = nearest(server, t, T.huntRange)
  if not prey then
    t.speed = T.roamSpeed
    roam(t, t.speed * dt)
    return false
  end
  t.to, t.street = nil, nil -- off the streets now; back to the nearest crossing after
  local dx, dy = prey.x - t.x, prey.y - t.y
  local d = math.sqrt(dx * dx + dy * dy)
  t.facing = math.atan2(dy, dx)
  if d <= T.standOff then
    t.speed = 0
    return false
  end
  t.speed = t.breath:pace(T.huntSpeed, T.windedSpeed)
  local step = math.min(t.speed * dt, d - T.standOff)
  t.x, t.y = t.x + dx / d * step, t.y + dy / d * step
  return not t.breath:winded()
end

-- The heat ray ------------------------------------------------------------

--- Anyone on foot (players and bots) and any car at (x, y) takes a bite of
--- `footDps` / `carDps`; somebody on foot it kills is left as ash.
local function burn(T, server, t, x, y, footDps, carDps)
  local weapons = Features.byName.weapons
  if not weapons then
    return
  end
  local r = T.burnRadius
  for _, p in pairs(server.players) do
    if Features.present(p) and not (t.caged and t.caged.id == p.id) then
      local px, py, onFoot = Features.bodyPose(server, p)
      if onFoot and dist2(px, py, x, y) <= r * r then
        weapons:serverDamage(server, p, nil, footDps * BURN_TICK, t.facing, "fire")
        if not (p.body and p.body.dead) and Features.byName.damage then
          Features.byName.damage:ignite(server, p, T.afterburnTime, T.afterburnDps)
        end
      end
    end
  end
  if weapons.damageCar then
    local reach = r + Car.WIDTH / 2
    for _, car in pairs(server.vehicles) do
      if not (car.hidden or car.stowed) and dist2(car.x, car.y, x, y) <= reach * reach then
        weapons:damageCar(server, car, nil, carDps * BURN_TICK, 0, t.facing, "fire")
      end
    end
  end
end

--- Pedestrians at (x, y) burn up, a few at a time.
local function burnPeds(T, server, t, x, y, dt)
  t.pedIn = t.pedIn - dt
  local peds = Features.byName.pedestrians
  if t.pedIn > 0 or not (peds and peds.serverShotAt) then
    return
  end
  t.pedIn = PED_EVERY
  for _ = 1, 3 do
    if not peds:serverShotAt(server, x, y, T.burnRadius, 0, t.facing, nil, "fire") then
      break
    end
  end
end

--- Where the sweeping beam is `k` (0..1) of the way along.
local function sweepPoint(T, t, k)
  local a = t.sweepA0 + (t.sweepA1 - t.sweepA0) * k
  return t.x + math.cos(a) * T.sweepRadius, t.y + math.sin(a) * T.sweepRadius
end

--- Is anybody (a player or a bot, not the one in the cage) out in front in
--- reach of a sweep?
local function sweepWorth(T, server, t)
  local near, far = T.sweepRadius - T.burnRadius * 2, T.sweepRadius + T.burnRadius * 2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and not (t.caged and t.caged.id == p.id) then
      local px, py = Features.bodyPose(server, p)
      local d = math.sqrt(dist2(px, py, t.x, t.y))
      local off = (math.atan2(py - t.y, px - t.x) - t.facing + math.pi) % (2 * math.pi) - math.pi
      if d >= near and d <= far and math.abs(off) <= T.sweepArc / 2 then
        return true
      end
    end
  end
  return false
end

--- Start a sweep across the ground in front, from one side or the other.
local function startSweep(T, t)
  local side = random() < 0.5 and 1 or -1
  t.sweepA0 = t.facing - side * T.sweepArc / 2
  t.sweepA1 = t.facing + side * T.sweepArc / 2
  t.breath:spend(T.sweepCost)
  t.sweepIn = T.sweepEvery
  t.target, t.phase, t.phaseT, t.burnIn, t.pedIn = 0, SWEEP_WARN, 0, 0, 0
end

--- The heat ray's round: rest, pick somebody and charge on them, lock where
--- they are, then burn there.
local function ray(T, server, t, dt)
  t.phaseT = t.phaseT + dt
  t.sweepIn = t.sweepIn - dt
  if t.phase == REST then
    if t.phaseT < T.rest then
      return
    end
    local canSweep = t.sweepIn <= 0 and t.breath:has(T.sweepCost) and sweepWorth(T, server, t)
    if canSweep and (random() < T.sweepChance or not nearest(server, t, T.rayRange)) then
      startSweep(T, t)
      return
    end
    if t.breath:has(T.rayCost) then
      local prey = nearest(server, t, T.rayRange)
      if prey then
        t.breath:spend(T.rayCost)
        t.target, t.phase, t.phaseT = prey.player.id, CHARGE, 0
      end
    end
    return
  elseif t.phase == FIRE then
    t.burnIn = t.burnIn - dt
    if t.burnIn <= 0 then
      t.burnIn = t.burnIn + BURN_TICK
      burn(T, server, t, t.lockX, t.lockY, T.burnDps, T.carDps)
    end
    burnPeds(T, server, t, t.lockX, t.lockY, dt)
    if t.phaseT >= T.fire then
      t.target, t.phase, t.phaseT = 0, REST, 0
    end
    return
  elseif t.phase == SWEEP_WARN then
    if t.phaseT >= T.sweepWarn then
      t.phase, t.phaseT = SWEEP, 0
    end
    return
  elseif t.phase == SWEEP then
    local x, y = sweepPoint(T, t, math.min(1, t.phaseT / T.sweepTime))
    t.burnIn = t.burnIn - dt
    if t.burnIn <= 0 then
      t.burnIn = t.burnIn + BURN_TICK
      burn(T, server, t, x, y, T.sweepDps, T.sweepCarDps)
    end
    burnPeds(T, server, t, x, y, dt)
    if t.phaseT >= T.sweepTime then
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
    if t.phaseT >= T.charge - T.lock then
      t.phase = LOCKED
    end
  elseif t.phase == LOCKED and t.phaseT >= T.charge then
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
local function tentacles(T, server, t, dt)
  local c = t.caged
  if c then
    local p = server.players[c.id]
    c.t = c.t + dt
    if not (p and p.body and Features.present(p)) or p.vehicle or p.body.dead
      or c.t >= T.cageTime or c.taken >= t.max * T.dropAfter then
      Brain.release(T, t)
      return
    end
    p.body.x, p.body.y = cagePoint(t)
    c.bite = c.bite - dt
    local weapons = Features.byName.weapons
    if c.bite <= 0 and weapons then
      c.bite = c.bite + BURN_TICK
      weapons:serverDamage(server, p, nil, T.cageDps * BURN_TICK, t.facing, "melee")
    end
    return
  end
  local g = t.grab
  if g then
    g.t = g.t + dt
    if g.t < T.grabWindup then
      return
    end
    t.grab = nil
    local p = server.players[g.id]
    local reach = T.grabReach + T.grabSlack
    if p and p.body and not p.vehicle and not p.body.dead and Features.present(p)
      and dist2(p.body.x, p.body.y, t.x, t.y) <= reach * reach then
      t.caged = { id = g.id, t = 0, taken = 0, bite = 0 }
      if t.target == g.id then
        t.target, t.phase, t.phaseT = 0, REST, 0 -- it has them: no need to burn them
      end
    else
      t.grabIn = T.grabEvery / 2 -- missed: another go sooner
    end
    return
  end
  t.grabIn = t.grabIn - dt
  if t.grabIn > 0 or not t.breath:has(T.grabCost) then
    return
  end
  local prey = nearest(server, t, T.grabReach)
  if prey and prey.onFoot then
    t.breath:spend(T.grabCost)
    t.grab = { id = prey.player.id, t = 0 }
  end
end


-- Healing --------------------------------------------------------------------

--- Should it go for a medkit now? Looks once a second while it is hurt.
local function wantsHeal(T, t, time)
  if t.medkit then
    if Heal.there(t.medkit) then
      return true
    end
    t.medkit = nil -- somebody got there first
  end
  if not Heal.wants(t.hp, t.max) or time < (t.healLook or 0) then
    return false
  end
  t.healLook = time + Heal.checkEvery
  t.medkit = Heal.find(t.x, t.y, T.healRange)
  return t.medkit ~= nil
end

--- Over everything to the medkit; a tentacle snatches it up once it is
--- within reach. Returns whether it strode (what costs breath).
local function heal(T, server, t, dt)
  local m = t.medkit
  if Heal.within(m, t.x, t.y, T.grabReach) then
    t.hp = math.min(t.max, t.hp + Heal.take(server, m))
    t.medkit, t.speed = nil, 0
    return false
  end
  t.to, t.street = nil, nil -- off the streets now; back to the nearest crossing after
  local dx, dy = m.x - t.x, m.y - t.y
  local d = math.sqrt(dx * dx + dy * dy)
  t.facing = math.atan2(dy, dx)
  t.speed = t.breath:pace(T.huntSpeed, T.windedSpeed)
  local step = math.min(t.speed * dt, d)
  t.x, t.y = t.x + dx / d * step, t.y + dy / d * step
  return not t.breath:winded()
end

-- Every tick ----------------------------------------------------------------

--- Its tick (once the storm is over). Returns whether it spent the tick
--- striding (what costs breath).
function Brain.think(T, t, server, dt, time)
  if t.frozen > 0 then
    t.frozen = t.frozen - dt
    t.speed = 0
    return false
  end
  local striding
  local threat = t.phase < SWEEP_WARN and Dodge.threat(t.x, t.y, T.radius)
  if threat then
    local ux, uy = Dodge.away(threat, t.x, t.y)
    t.speed = t.breath:pace(T.huntSpeed, T.windedSpeed)
    t.facing = math.atan2(uy, ux)
    t.to, t.street = nil, nil -- off the streets; back to the nearest crossing after
    t.x, t.y = t.x + ux * t.speed * dt, t.y + uy * t.speed * dt
    striding = not t.breath:winded()
  elseif t.phase < SWEEP_WARN and wantsHeal(T, t, time) then
    t.mode = "heal"
    striding = heal(T, server, t, dt)
  else
    t.mode = "fight"
    striding = move(T, server, t, dt)
  end
  if t.breath:winded() and (t.phase == CHARGE or t.phase == LOCKED) then
    t.target, t.phase = 0, REST -- no breath to keep the ray up (it finishes a burst it began)
  end
  ray(T, server, t, dt)
  tentacles(T, server, t, dt)
  return striding
end

return Brain
