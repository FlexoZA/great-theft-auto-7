-- Bigfoot's brain, on the host: what he does each tick. One Bigfoot, two
-- fights: the alien hunt's (init.lua, in the forest) and his city event's
-- (events/bigfoot.lua). Each owns him (his body `f`, his health, the wire,
-- what his landing and his claws do to the world) and hands its own
-- numbers in as `T`:
--
--   radius, speed, walkSpeed, swipeReach, swipeDamage, swipeEvery,
--   leapEvery, leapRange, leapStamina, crouchTime, airTime, recoverTime,
--   aggroRange
--   stuckLeap  seconds getting no closer before he leaps over whatever is in
--              the way (nil: never)
--   leapFar    true to leap towards targets further than leapRange too (as
--              far as it takes him), not only at ones within it
--   leapClose  true to leap at a player even when they are within a swipe
--
-- and, each tick, `buildings`: the players' buildings he may go after when
-- nobody is near (the city's; nil in the forest).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   idle     nobody to go after
--   walk     after the nearest player within `aggroRange` (or, failing
--            that, the nearest player or player's building anywhere, in the
--            city), swiping whatever he reaches
--   crouch, air, recover   a leap: `crouchTime` crouched (a ring shows where
--            he comes down), `airTime` in the air, `recoverTime` getting up;
--            every `leapEvery` seconds, breath allowing, onto a player or
--            over something he is stuck behind
--   heal     badly hurt (bosses/heal.lua): he goes for the nearest medkit
--            lying within reach, leaping onto it if it is a fair way off and
--            he has the breath (the landing slams whoever is there, as ever),
--            lumbering over if not, and takes it
--
-- A freeze holds him still; a stink sends him lumbering away from it, and
-- so does an ability about to land on him (bosses/dodge.lua), unless he is
-- crouched for a leap.
--
-- Brain.think returns the events the feature should act on:
--   { "leap", fx, fy, tx, ty }   he took off from (fx, fy); lands on (tx, ty)
--   { "slam" }                   he landed where he stands
--   { "claw", x, y }             a swipe at the building at (x, y)

local Features = require("src.features")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

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

--- One step along `angle`, each axis on its own so a corner or a trunk is
--- slid along; landed in something, he walks out of it. At full tilt while
--- he has the breath, which it costs him; a lumber once he is winded.
--- Wedged, he sidesteps for a moment.
local function walk(T, f, angle, dt)
  if f.sidestep > 0 then
    f.sidestep = f.sidestep - dt
    angle = angle + f.side * math.pi / 2
  end
  local px, py, r = f.x, f.y, T.radius
  local speed = f.breath:pace(T.speed, T.walkSpeed)
  f.running = not f.breath:winded()
  local free = blocked(f.x, f.y, r)
  local nx = f.x + math.cos(angle) * speed * dt
  if free or not blocked(nx, f.y, r) then
    f.x = nx
  end
  local ny = f.y + math.sin(angle) * speed * dt
  if free or not blocked(f.x, ny, r) then
    f.y = ny
  end
  if dist2(f.x, f.y, px, py) < (speed * dt * 0.4) ^ 2 then
    f.stuck = f.stuck + dt
    if f.stuck > 0.4 then
      f.stuck, f.sidestep, f.side = 0, 0.6, -f.side
    end
  else
    f.stuck = 0
  end
end

--- Crouch for a leap towards (tx, ty), no further than `leapRange`, and
--- onto clear ground: the landing is pulled back towards him until it is.
--- `playerId`: whoever he means to land on, for a last look before he goes.
local function crouch(T, f, tx, ty, playerId)
  local angle = math.atan2(ty - f.y, tx - f.x)
  local d = math.min(T.leapRange, math.sqrt(dist2(tx, ty, f.x, f.y)))
  local x, y = f.x + math.cos(angle) * d, f.y + math.sin(angle) * d
  while d > 0 and blocked(x, y, T.radius) do
    d = math.max(0, d - 12)
    x, y = f.x + math.cos(angle) * d, f.y + math.sin(angle) * d
  end
  f.mode, f.timer, f.facing = "crouch", T.crouchTime, angle
  f.tx, f.ty, f.target = x, y, playerId
  f.leapTimer, f.stuck, f.noCloser, f.chasing = T.leapEvery, 0, 0, nil
end

--- What he goes after: the nearest player within aggro range; failing that
--- (in the city), whichever is nearer of any player and any building of a
--- player's. Returns { x, y, player, onFoot } or { x, y, building } or nil.
local function pickTarget(T, f, server, buildings)
  local best, bestD2
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local d2 = dist2(x, y, f.x, f.y)
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = { x = x, y = y, player = p, onFoot = onFoot }, d2
      end
    end
  end
  if best and bestD2 <= T.aggroRange ^ 2 then
    return best
  end
  if not buildings then
    return nil -- the forest: only who is near
  end
  for _, b in ipairs(buildings) do
    local x, y = nearestOn(b, f.x, f.y)
    local d2 = dist2(x, y, f.x, f.y)
    if not bestD2 or d2 < bestD2 then
      best, bestD2 = { x = x, y = y, building = b }, d2
    end
  end
  return best
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(f, time)
  if f.medkit then
    if Heal.there(f.medkit) then
      return true
    end
    f.medkit = nil -- somebody got there first
  end
  if not Heal.wants(f.hp, f.max) or time < (f.healLook or 0) then
    return false
  end
  f.healLook = time + Heal.checkEvery
  f.medkit = Heal.find(f.x, f.y)
  return f.medkit ~= nil
end

--- Off to the medkit: a leap onto it if it is a fair way off and he has
--- the breath, a lumber over if not; on it, he takes it.
local function heal(T, f, server, dt)
  local m = f.medkit
  if Heal.within(m, f.x, f.y, T.radius) then
    f.hp = math.min(f.max, f.hp + Heal.take(server, m))
    f.medkit = nil
    return
  end
  local d = math.sqrt(dist2(m.x, m.y, f.x, f.y))
  f.facing = math.atan2(m.y - f.y, m.x - f.x)
  if d > 250 and f.leapTimer <= 0 and f.breath:has(T.leapStamina) then
    f.breath:spend(T.leapStamina)
    crouch(T, f, m.x, m.y, nil)
    return
  end
  f.mode = "walk"
  walk(T, f, f.facing, dt)
end

--- His tick. `time` is the fight's clock; `buildings` (or nil) what he may
--- go after besides players. Returns the events for the feature (above).
function Brain.think(T, f, server, dt, time, buildings)
  local events = {}
  f.running = false
  f.swipe = math.max(0, f.swipe - dt)
  f.swipeTimer = f.swipeTimer - dt
  if f.mode == "air" then
    f.running = true -- flying is the hardest work he does
    f.timer = f.timer - dt
    local k = math.min(1, 1 - f.timer / T.airTime)
    f.x, f.y = f.fx + (f.tx - f.fx) * k, f.fy + (f.ty - f.fy) * k
    if f.timer <= 0 then
      f.x, f.y = f.tx, f.ty
      f.mode, f.timer = "recover", T.recoverTime
      events[#events + 1] = { "slam" }
    end
    return events
  end
  if f.frozen > 0 then
    f.frozen = f.frozen - dt
    f.mode = "idle"
    return events
  end
  if f.mode ~= "crouch" then
    Dodge.step(f, T.radius)
  end
  if f.panic and f.mode ~= "crouch" then
    -- A stink: he lumbers away from it, whoever is about.
    f.panic.left = f.panic.left - dt
    f.mode = "walk"
    f.facing = math.atan2(f.y - f.panic.y, f.x - f.panic.x)
    walk(T, f, f.facing, dt)
    if f.panic.left <= 0 then
      f.panic = nil
    end
    return events
  end
  if f.mode == "crouch" then
    f.timer = f.timer - dt
    if f.timer <= 0 then
      local target = f.target and server.players[f.target]
      if target and Features.visible(server, target) then
        -- A last look: he goes where they are now, within reach and onto clear ground.
        local tx, ty = Features.bodyPose(server, target)
        crouch(T, f, tx, ty, nil)
      end
      f.fx, f.fy = f.x, f.y
      f.mode, f.timer = "air", T.airTime
      events[#events + 1] = { "leap", f.fx, f.fy, f.tx, f.ty }
    end
    return events
  end
  if f.mode == "recover" then
    f.timer = f.timer - dt
    if f.timer <= 0 then
      f.mode = "walk"
    end
    return events
  end

  f.leapTimer = f.leapTimer - dt
  if wantsHeal(f, time) then
    heal(T, f, server, dt)
    return events
  end

  local target = pickTarget(T, f, server, buildings)
  if not target then
    f.mode = "idle"
    return events
  end
  f.mode = "walk"
  f.facing = math.atan2(target.y - f.y, target.x - f.x)
  local dist = math.sqrt(dist2(target.x, target.y, f.x, f.y))
  local reach = T.radius + T.swipeReach + ((target.player and not target.onFoot) and 10 or 0)
  -- Getting any closer? A new target starts the count again.
  local key = target.player or target.building.id
  if key ~= f.chasing or dist < (f.closest or math.huge) - 30 then
    f.chasing, f.closest, f.noCloser = key, dist, 0
  else
    f.noCloser = (f.noCloser or 0) + dt
  end
  -- A leap takes breath: none while he is winded or nearly so (the timer
  -- stays run down, so it comes as soon as he has it back).
  local stuck = T.stuckLeap and f.noCloser > T.stuckLeap
  local onto = f.leapTimer <= 0 and target.player and (T.leapFar or dist <= T.leapRange)
  local towards = f.leapTimer <= 0 and target.building and dist > 300
  if (dist > reach or (T.leapClose and onto)) and (stuck or onto or towards) and f.breath:has(T.leapStamina) then
    -- Onto a player in reach, towards anything further, over whatever he is stuck on.
    f.breath:spend(T.leapStamina)
    crouch(T, f, target.x, target.y, target.player and dist <= T.leapRange and target.player.id or nil)
    return events
  end
  if dist > reach then
    walk(T, f, f.facing, dt)
  elseif f.swipeTimer <= 0 then
    f.swipeTimer, f.swipe = T.swipeEvery, 0.25
    if target.player then
      local weapons = Features.byName.weapons
      if weapons and weapons.serverDamage then
        weapons:serverDamage(server, target.player, nil, T.swipeDamage, f.facing, "melee")
      end
    else
      events[#events + 1] = { "claw", target.x, target.y }
    end
  end
  return events
end

return Brain
