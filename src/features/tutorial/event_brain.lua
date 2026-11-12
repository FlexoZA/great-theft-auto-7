-- Shoeman's brain in the city event (event.lua), on the host: what he does
-- each tick. The event owns the shoe itself (shoe.lua's thrower), his
-- health and the wire; it hands him in as `s`, its own table (his numbers)
-- as `S`. He is always in one of these, the later ones cutting in on the
-- earlier:
--
--   hunt    the nearest player he can see within `aggroRange`, humans
--           before bots, or, with nobody that close, the nearest building a
--           player owns. He runs at them while he has the breath and is far
--           off, walks once he is winded or close, and stops `keepAway` px
--           from a player (he is a thrower: no closer than he needs). Every
--           `throwEvery` seconds, with his target within `throwRange` and
--           nothing in the way of the shoe (a building he aims at: within
--           `buildingRange` of its wall), he stops and throws. Straight when
--           his whole width gets there, round by his walking grid (`s.nav`,
--           bosses/walk.lua) when it doesn't.
--   heal    badly hurt (bosses/heal.lua): he goes for the nearest medkit
--           within `healRange` and takes it. Kiting: with somebody in sight
--           he faces them, walks there backwards or sideways and still
--           throws at them on his way; nobody in sight, he runs for it.
--   panic   a stink in his face (`s.panic`): he runs out of it, the way
--           he faced or not, for as long as it lasts.
--   dodge   a player's ability about to land on him (bosses/dodge.lua):
--           he runs out from under it.
--   throw   a throw under way (`s.throwing` seconds left): he stands
--           planted until the shoe has gone and the arm come through.
--
-- Frozen, he stands still and his throw waits.

local Features = require("src.features")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")
local Nav = require("src.features.d-day.nav")

local Brain = {}

Brain.LOOK_EVERY = 0.5 -- seconds between his looks round for a building, when no player is near

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Is (x, y) somewhere he can't stand? (Walk.nav keeps its grid per this.)
local function blocked(x, y)
  return Features.any("blocksPoint", x, y)
end

--- Does a shoe stop at (x, y)?
local function stopsShoe(x, y)
  return Features.any("blocksShot", x, y)
end

--- His walking grid over `bounds` ({ x, y, w, h }) for a walker `r` px
--- across: the event builds it once and hands it in as `s.nav`.
function Brain.nav(bounds, r)
  return Walk.nav(Nav.build(bounds), blocked, r)
end

--- The nearest player he can see within `range`, humans before bots:
--- player, x, y; nil for none.
local function pickPlayer(server, s, range)
  local best, bestD, bestHuman
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d = dist2(x, y, s.x, s.y)
      local human = not p.bot
      if d <= range * range and (not best or (human and not bestHuman) or (human == bestHuman and d < bestD)) then
        best, bestD, bestHuman = p, d, human
      end
    end
  end
  if best then
    local x, y = Features.bodyPose(server, best)
    return best, x, y
  end
  return nil
end

--- The point of rectangle `r` ({ x, y, w, h }) nearest (x, y).
local function nearestOn(r, x, y)
  return math.max(r.x, math.min(r.x + r.w, x)), math.max(r.y, math.min(r.y + r.h, y))
end

--- The nearest building a player owns, still standing: { x, y, w, h, id }
--- or nil. Looked for every LOOK_EVERY seconds, not every tick.
local function pickBuilding(s, time)
  if time < (s.lookAt or 0) and s.building ~= nil then
    return s.building
  end
  s.lookAt = time + Brain.LOOK_EVERY
  local buildings = Features.byName.buildings
  local best, bestD
  for _, b in ipairs(buildings and buildings.serverStanding and buildings:serverStanding() or {}) do
    if b.owner then
      local nx, ny = nearestOn(b, s.x, s.y)
      local d = dist2(nx, ny, s.x, s.y)
      if not bestD or d < bestD then
        best, bestD = b, d
      end
    end
  end
  s.building = best
  return best
end

--- A step towards (tx, ty): straight when his whole width gets there,
--- round by his grid when it doesn't. Turns him to face the way he walks
--- unless `facing` (kiting: he keeps his eyes on someone). True when he got
--- somewhere.
local function walk(S, s, tx, ty, speed, dt, time, facing)
  local angle
  if Walk.wideClear(blocked, s.x, s.y, tx, ty, S.radius) then
    s.route = nil
    angle = math.atan2(ty - s.y, tx - s.x)
  else
    local there
    angle, there = Walk.route(s, s.nav, tx, ty, time)
    if not angle then
      if there then
        return false
      end
      angle = math.atan2(ty - s.y, tx - s.x) -- no way on the grid: feel along the walls
    end
  end
  if not facing then
    s.facing = angle
  end
  return Walk.step(s, blocked, angle, speed, dt, S.radius)
end

--- At full tilt along `angle` while he has the breath, a walk without; he
--- runs (spending breath) only when he got somewhere at full tilt.
local function hurry(S, s, angle, dt)
  local pace = s.breath:pace(S.runSpeed, S.walkSpeed)
  s.moving = Walk.step(s, blocked, angle, pace, dt, S.radius)
  s.running = s.moving and pace == S.runSpeed
end

--- Can a shoe from him get to (x, y), nothing stopping it on the way?
local function shoeGets(s, x, y)
  return Walk.clear(stopsShoe, s.x, s.y, x, y)
end

--- Is it time to throw at a player at (x, y)?
local function canThrowAt(S, s, x, y)
  return s.cool <= 0 and dist2(x, y, s.x, s.y) <= S.throwRange ^ 2 and shoeGets(s, x, y)
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(S, s, time)
  if s.medkit then
    if Heal.there(s.medkit) then
      return true
    end
    s.medkit = nil -- somebody got there first
  end
  if not Heal.wants(s.hp, s.max) or time < (s.healLook or 0) then
    return false
  end
  s.healLook = time + Heal.checkEvery
  s.medkit = Heal.find(s.x, s.y, S.healRange)
  return s.medkit ~= nil
end

--- Off to the medkit, kiting (the bosses' standard, point 7): with somebody
--- in sight he keeps facing them and throws on his way at a walk; nobody in
--- sight, he hurries. Returns a throw ({ x, y, player }) or nil.
local function heal(S, s, server, dt, time)
  local m = s.medkit
  if Heal.pickUp(server, s, S.radius) then
    return nil
  end
  local target, tx, ty = pickPlayer(server, s, S.aggroRange)
  if target then
    s.facing = math.atan2(ty - s.y, tx - s.x)
    if canThrowAt(S, s, tx, ty) then
      return { x = tx, y = ty, player = target }
    end
    s.moving = walk(S, s, m.x, m.y, S.walkSpeed, dt, time, true)
    return nil
  end
  local angle = Heal.way(s, s.nav, m, time)
  if not angle then
    Heal.giveUp(s, time)
    return nil
  end
  s.facing = angle
  hurry(S, s, angle, dt)
  return nil
end

--- What he does this tick. Returns a throw he starts now ({ x, y, player },
--- `player` nil for a building) or nil.
function Brain.think(S, s, server, dt, time)
  s.moving, s.running = false, false
  if s.frozen > 0 then
    s.frozen = s.frozen - dt
    return nil
  end
  s.cool = s.cool - dt
  if s.throwing > 0 then
    s.throwing = s.throwing - dt
    return nil
  end
  local threat = Dodge.threat(s.x, s.y, S.radius)
  if threat then
    local ux, uy = Dodge.away(threat, s.x, s.y)
    s.facing = math.atan2(uy, ux)
    hurry(S, s, s.facing, dt)
    return nil
  end
  if s.panic then
    s.panic.left = s.panic.left - dt
    if s.panic.left <= 0 then
      s.panic = nil
    else
      s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
      hurry(S, s, s.facing, dt)
      return nil
    end
  end
  if wantsHeal(S, s, time) then
    s.mode = "heal"
    return heal(S, s, server, dt, time)
  end
  s.mode = "hunt"
  local target, tx, ty = pickPlayer(server, s, S.aggroRange)
  if target then
    s.facing = math.atan2(ty - s.y, tx - s.x)
    if canThrowAt(S, s, tx, ty) then
      return { x = tx, y = ty, player = target }
    end
    local d2 = dist2(tx, ty, s.x, s.y)
    if d2 > S.keepAway ^ 2 or not shoeGets(s, tx, ty) then
      local run = d2 > S.runFrom ^ 2 and not s.breath:winded()
      s.moving = walk(S, s, tx, ty, run and S.runSpeed or S.walkSpeed, dt, time)
      s.running = s.moving and run
    end
    return nil
  end
  local b = pickBuilding(s, time)
  if not b then
    return nil
  end
  local nx, ny = nearestOn(b, s.x, s.y)
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  s.facing = math.atan2(cy - s.y, cx - s.x)
  local d2 = dist2(nx, ny, s.x, s.y)
  if d2 <= S.buildingRange ^ 2 then
    -- Close enough: the shoe goes at its middle and stops at its wall.
    return s.cool <= 0 and { x = cx, y = cy } or nil
  end
  -- The way round its walls to the point nearest him, a little out from it.
  local away = math.atan2(s.y - ny, s.x - nx)
  local gx, gy = nx + math.cos(away) * S.radius * 2, ny + math.sin(away) * S.radius * 2
  local run = d2 > S.runFrom ^ 2 and not s.breath:winded()
  s.moving = walk(S, s, gx, gy, run and S.runSpeed or S.walkSpeed, dt, time)
  s.running = s.moving and run
  return nil
end

return Brain
