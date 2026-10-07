-- A-Man's brain, on the host: what he does each tick. His event
-- (event.lua) owns the blink itself (the tear through everyone on the
-- line), his turrets, his health and the wire; it hands him in as `a`, its
-- own table (his numbers) as `A`, and says whether a horde may come now.
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   stalk   he walks at the nearest player he can see, humans before bots,
--           never hurrying, to within `keepAway`
--   blink   breath allowing and `cool` run down, he stops and winds up: a
--           line shows where he is going (through a target close by, or
--           across the map to one far off), and `windup` later he is there
--   horde   a player within `hordeRange`, no turrets standing and the
--           breath for it: he snaps the briefcase open
--   heal    badly hurt (bosses/heal.lua): he goes for the nearest medkit
--           lying within `healRange`, by blink if he has the breath (the
--           line shows; anyone on it is torn through as ever), on foot if
--           not, and takes it
--
-- Frozen, he stands still and his wind-up waits. Under a player's ability
-- about to land (a freeze's warning ring: bosses/dodge.lua) he hurries out
-- of it, the one time he does, unless he is already winding up a blink.

local Features = require("src.features")
local Teleport = require("src.features.abilities.teleport")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

Brain.DODGE_PACE = 2.6 -- times his walk, getting out from under an ability

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Who he goes after: the nearest player he can see, humans before bots.
local function pickTarget(server, a)
  local best, bestD, bestHuman
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d = dist2(x, y, a.x, a.y)
      local human = not p.bot
      if not best or (human and not bestHuman) or (human == bestHuman and d < bestD) then
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

--- A step of `dist` px towards (tx, ty), sliding along a wall if one is in
--- the way, standing still if both ways are.
local function walk(a, tx, ty, dist)
  local d = math.sqrt(dist2(tx, ty, a.x, a.y))
  if d < 1 then
    return false
  end
  local mx, my = (tx - a.x) / d * dist, (ty - a.y) / d * dist
  for _, m in ipairs({ { mx, my }, { mx, 0 }, { 0, my } }) do
    local nx, ny = a.x + m[1], a.y + m[2]
    if (m[1] ~= 0 or m[2] ~= 0) and not Features.any("blocksPoint", nx, ny) then
      a.x, a.y = nx, ny
      return true
    end
  end
  return false
end

--- He stops and picks where he is going: through a target close by, or
--- across the map to one far off, landing to one side of the way he came.
local function windUp(A, a, tx, ty)
  local d = math.sqrt(dist2(tx, ty, a.x, a.y))
  local ax, ay
  if d <= A.strikeRange then
    local ux, uy = (tx - a.x) / math.max(d, 1), (ty - a.y) / math.max(d, 1)
    ax, ay = tx + ux * A.overshoot, ty + uy * A.overshoot
  else
    local back = math.atan2(a.y - ty, a.x - tx) + (random() - 0.5) * 1.6
    ax, ay = tx + math.cos(back) * A.approachGap, ty + math.sin(back) * A.approachGap
  end
  a.aimX, a.aimY = Teleport.clear(a.x, a.y, ax, ay, A.radius)
  a.windup = A.windup
  a.facing = math.atan2(a.aimY - a.y, a.aimX - a.x)
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(A, a, time)
  if a.medkit then
    if Heal.there(a.medkit) then
      return true
    end
    a.medkit = nil -- somebody got there first
  end
  if not Heal.wants(a.hp, a.max) or time < (a.healLook or 0) then
    return false
  end
  a.healLook = time + Heal.checkEvery
  a.medkit = Heal.find(a.x, a.y, A.healRange)
  return a.medkit ~= nil
end

--- Off to the medkit: a blink straight onto it if he has the breath, a walk
--- if not; when he is on it he takes it.
local function heal(A, a, server, dt)
  local m = a.medkit
  if Heal.within(m, a.x, a.y, A.radius) then
    a.hp = math.min(a.max, a.hp + Heal.take(server, m))
    a.medkit = nil
    return
  end
  a.facing = math.atan2(m.y - a.y, m.x - a.x)
  if a.cool <= 0 and a.breath:has(A.blinkCost) then
    -- Onto it, if there is room to land within reach of it; a wall right by
    -- it pulls the landing back, and then he walks.
    local x, y = Teleport.clear(a.x, a.y, m.x, m.y, A.radius)
    if Heal.within(m, x, y, A.radius) and dist2(x, y, a.x, a.y) > 40 * 40 then
      a.aimX, a.aimY, a.windup = x, y, A.windup
      return
    end
  end
  a.moving = walk(a, m.x, m.y, A.walkSpeed * dt)
end

--- What he does this tick. `canHorde` says whether the briefcase may open
--- now (no turrets standing, the wait over). Returns "blink" when his
--- wind-up is done and he goes, "horde" when he opens the case, or nil.
function Brain.think(A, a, server, dt, canHorde, time)
  a.moving, a.running = false, false
  if a.frozen > 0 then
    a.frozen = a.frozen - dt
    return nil
  end
  if a.aimX then
    a.windup = a.windup - dt
    return a.windup <= 0 and "blink" or nil
  end
  local threat = Dodge.threat(a.x, a.y, A.radius)
  if threat then
    -- The one time he hurries, and it costs him: winded, he only walks it.
    local ux, uy = Dodge.away(threat, a.x, a.y)
    a.facing = math.atan2(uy, ux)
    local pace = a.breath:pace(A.walkSpeed * Brain.DODGE_PACE, A.walkSpeed)
    a.moving = walk(a, a.x + ux * 100, a.y + uy * 100, pace * dt)
    a.running = a.moving and not a.breath:winded()
    return nil
  end
  a.cool = a.cool - dt
  if wantsHeal(A, a, time) then
    a.mode = "heal"
    heal(A, a, server, dt)
    return nil
  end
  a.mode = "stalk"
  local target, tx, ty = pickTarget(server, a)
  if not target then
    return nil
  end
  local d2 = dist2(tx, ty, a.x, a.y)
  a.facing = math.atan2(ty - a.y, tx - a.x)
  if canHorde and d2 <= A.hordeRange ^ 2 and a.breath:has(A.hordeCost) then
    return "horde"
  elseif a.cool <= 0 and d2 <= A.reach * A.reach and a.breath:has(A.blinkCost) then
    windUp(A, a, tx, ty)
  elseif d2 > A.keepAway * A.keepAway then
    a.moving = walk(a, tx, ty, A.walkSpeed * dt)
  end
  return nil
end

return Brain
