-- A-Man's brain, on the host: what he does each tick, in the city event
-- (event.lua) and at the top of the Citadel (finale.lua) alike. Whichever
-- runs him owns the blink itself (the tear through everyone on the line),
-- his turrets, his health and the wire; it hands him in as `a`, its own
-- table (his numbers) as `A`, and says whether his case may open now (the
-- event: no turrets standing; the finale: a case owed for the damage done).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   stalk   he walks at the nearest player he can see, humans before bots,
--           never hurrying, to within `keepAway`: straight when his whole
--           width gets there, round by his walking grid (`a.nav`, built by
--           Brain.nav) when it doesn't (bosses/walk.lua)
--   blink   breath allowing and `cool` run down, he stops and winds up: a
--           line shows where he is going (through a target close by, or
--           across the map to one far off), and `windup` later he is there;
--           a landing a wall pulls back onto his own spot won't do, and he
--           aims at the furthest corner of his way there instead, or walks
--   horde   a player within `hordeRange`, his case allowed (whoever runs
--           him says) and the breath for it: he snaps the briefcase open
--   heal    badly hurt (bosses/heal.lua): he goes for the nearest medkit
--           lying within `healRange` and takes it. Kiting: with somebody
--           in sight he faces them and fights on the way (the case, a blink
--           through them that comes out nearer the medkit, a blink onto it
--           while it is far) and otherwise walks there; nobody in sight, by
--           blink if he has the breath, on foot if not
--
-- Frozen, he stands still and his wind-up waits. Under a player's ability
-- about to land (a freeze's warning ring: bosses/dodge.lua) he hurries out
-- of it, the one time he does, unless he is already winding up a blink.

local Features = require("src.features")
local Teleport = require("src.features.abilities.teleport")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")
local Nav = require("src.features.d-day.nav")

local Brain = {}

Brain.DODGE_PACE = 2.6 -- times his walk, getting out from under an ability
Brain.MIN_BLINK = 60 -- px; a blink a wall pulls back to less than this is no blink: he looks for another way
Brain.RETRY = 0.4 -- seconds before he tries a blink again when there was nowhere to land
Brain.HEAL_FAR = 500 -- px; kiting, he only blinks onto a medkit further off than this (nearer, he walks)

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

--- Is (x, y) somewhere he can't stand? (Walk.nav keeps its grid per this.)
local function blocked(x, y)
  return Features.any("blocksPoint", x, y)
end

--- His walking grid over `bounds` ({ x, y, w, h }) for a walker `r` px
--- across: whoever runs him builds it once and hands it in as `a.nav`.
function Brain.nav(bounds, r)
  return Walk.nav(Nav.build(bounds), blocked, r)
end

--- A step towards (tx, ty) at his walking pace: straight when his whole
--- width gets there, round by his grid when it doesn't. Turns him to face
--- the way he walks unless `facing` (kiting: he keeps his eyes on someone).
--- True when he got somewhere.
local function walk(A, a, tx, ty, speed, dt, time, facing)
  local angle
  if Walk.wideClear(blocked, a.x, a.y, tx, ty, A.radius) then
    a.route = nil
    angle = math.atan2(ty - a.y, tx - a.x)
  else
    local there
    angle, there = Walk.route(a, a.nav, tx, ty, time)
    if not angle then
      if there then
        return false
      end
      angle = math.atan2(ty - a.y, tx - a.x) -- no way on the grid: feel along the walls
    end
  end
  if not facing then
    a.facing = angle
  end
  return Walk.step(a, blocked, angle, speed, dt, A.radius)
end

--- Where a blink aimed at (x, y) lands: pulled back out of any wall it ends
--- in; nil when that leaves him (next to) where he stands.
local function landing(A, a, x, y)
  local lx, ly = Teleport.clear(a.x, a.y, x, y, A.radius)
  if dist2(lx, ly, a.x, a.y) < Brain.MIN_BLINK ^ 2 then
    return nil
  end
  return lx, ly
end

--- He stops and the line shows: `windup` later he is at (x, y).
local function aim(A, a, x, y)
  a.aimX, a.aimY = x, y
  a.windup = A.windup
  a.facing = math.atan2(y - a.y, x - a.x)
end

--- The furthest corner of his way to (tx, ty) he can blink to: within
--- `reach` and a landing worth the breath. Nil when there is none.
local function cornerLanding(A, a, tx, ty)
  local corners = a.nav and a.nav:path(a.x, a.y, tx, ty)
  for i = #(corners or {}), 1, -1 do
    local c = corners[i]
    if dist2(c.x, c.y, a.x, a.y) <= A.reach * A.reach then
      local x, y = landing(A, a, c.x, c.y)
      if x then
        return x, y
      end
    end
  end
  return nil
end

--- He picks where he is going: through a target close by, or across the
--- map to one far off, landing to one side of the way he came. A landing a
--- wall pulls back onto his own spot won't do: then the furthest corner of
--- his way there, or nothing (false) and he walks, to try again shortly.
local function windUp(A, a, tx, ty)
  local d = math.sqrt(dist2(tx, ty, a.x, a.y))
  local x, y
  if d <= A.strikeRange then
    local ux, uy = (tx - a.x) / math.max(d, 1), (ty - a.y) / math.max(d, 1)
    x, y = landing(A, a, tx + ux * A.overshoot, ty + uy * A.overshoot)
  else
    local back = math.atan2(a.y - ty, a.x - tx) + (random() - 0.5) * 1.6
    x, y = landing(A, a, tx + math.cos(back) * A.approachGap, ty + math.sin(back) * A.approachGap)
  end
  if not x then
    x, y = cornerLanding(A, a, tx, ty)
  end
  if not x then
    a.cool = Brain.RETRY
    return false
  end
  aim(A, a, x, y)
  return true
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

--- Off to the medkit, kiting (the standard's point 7). With somebody in
--- sight he keeps facing them and fights on the way: the case when it may
--- open, a blink through them when it comes out nearer the medkit, a blink
--- onto the medkit while it is still far; otherwise he walks his way there.
--- Nobody in sight, he blinks onto it if he can, or walks. On it he takes
--- it. Returns "horde" when he opens the case.
local function heal(A, a, server, dt, canHorde, time)
  local m = a.medkit
  if Heal.within(m, a.x, a.y, A.radius) then
    a.hp = math.min(a.max, a.hp + Heal.take(server, m))
    a.medkit = nil
    return nil
  end
  local mx, my = m.x, m.y
  local ready = a.cool <= 0 and a.breath:has(A.blinkCost)
  local target, tx, ty = pickTarget(server, a)
  if target then
    a.facing = math.atan2(ty - a.y, tx - a.x)
    local d2 = dist2(tx, ty, a.x, a.y)
    if canHorde and d2 <= A.hordeRange ^ 2 and a.breath:has(A.hordeCost) then
      return "horde"
    end
    if ready and d2 <= A.strikeRange ^ 2 then
      local d = math.sqrt(d2)
      local ux, uy = (tx - a.x) / math.max(d, 1), (ty - a.y) / math.max(d, 1)
      local x, y = landing(A, a, tx + ux * A.overshoot, ty + uy * A.overshoot)
      if x and dist2(x, y, mx, my) < dist2(a.x, a.y, mx, my) then
        aim(A, a, x, y)
        return nil
      end
    end
  end
  if ready and (not target or dist2(mx, my, a.x, a.y) > Brain.HEAL_FAR ^ 2) then
    -- Onto it, if there is room to land within reach of it; a wall right by
    -- it pulls the landing back, and then he walks.
    local x, y = landing(A, a, mx, my)
    if x and Heal.within(m, x, y, A.radius) then
      aim(A, a, x, y)
      return nil
    end
  end
  a.moving = walk(A, a, mx, my, A.walkSpeed, dt, time, target ~= nil)
  return nil
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
    a.moving = Walk.step(a, blocked, math.atan2(uy, ux), pace, dt, A.radius)
    a.running = a.moving and not a.breath:winded()
    return nil
  end
  a.cool = a.cool - dt
  if wantsHeal(A, a, time) then
    a.mode = "heal"
    return heal(A, a, server, dt, canHorde, time)
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
  elseif a.cool <= 0 and d2 <= A.reach * A.reach and a.breath:has(A.blinkCost) and windUp(A, a, tx, ty) then
    return nil
  elseif d2 > A.keepAway * A.keepAway then
    a.moving = walk(A, a, tx, ty, A.walkSpeed, dt, time)
  end
  return nil
end

return Brain
