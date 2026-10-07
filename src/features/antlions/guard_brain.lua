-- The Antlion Guard's brain, on the host (guard.lua runs it and owns the
-- wire). Modes that cut in on each other:
--
--   emerge   digging up out of the sand (`G.rise` seconds) once the
--            Coast's final section is clear
--   hunt     after the nearest player it can see: running while they are
--            further off than `chargeFar` and it has the breath, prowling
--            (`prowlSpeed`, no breath spent: it saves that for what it
--            does next) once they are closer, walking it off once winded
--            (bosses/stamina.lua). From there it picks what to do:
--   swipe    within `swipeReach`: a backhand of the head, `swipeDamage`
--            and knocked back `swipeShove`. Melee: no breath.
--   paw      `chargeFar` .. `chargeNear` off with the breath for it: it
--            paws the sand for `pawTime` (the warning), locks its line...
--   charge   ...and barrels down it at `chargeSpeed` for up to
--            `chargeTime`. Whoever it hits takes `chargeDamage` and flies
--            `chargeShove`; it runs on through them. Into anything solid,
--            it reels:
--   stunned  `stunTime` seconds, standing there for you.
--   rear     a player within `screamRange` and the breath for it: it rears
--            up for `rearTime`, the cone it will scream down showing on
--            the ground, its line fixed on whoever it rose at...
--   scream   ...and lets go: everyone in the cone (`screamRange` long,
--            `screamHalf` either side) and not behind anything solid takes
--            up to `screamDamage` and is blown back up to `screamShove`,
--            both less at the far end. Then `screamRecover` to get its
--            breath back.
--   heal     badly hurt (bosses/heal.lua): off to a medkit and takes it.
--   dodge    out from under a player's ability about to land (bosses/dodge.lua).
--
-- Frozen, it stands stiff; a stink throws it off for a moment.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function turn(from, to, rate, dt)
  local d = wrap(to - from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- Solid ground under any edge of a body `r` across at (x, y).
local function blockedAt(x, y, r)
  return Features.any("blocksPoint", x, y) or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y) or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

--- A step that way, each axis on its own; true if it got anywhere.
local function move(g, r, angle, speed, dt)
  local px, py = g.x, g.y
  local nx = g.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, g.y, r) then
    g.x = nx
  end
  local ny = g.y + math.sin(angle) * speed * dt
  if not blockedAt(g.x, ny, r) then
    g.y = ny
  end
  return (g.x - px) ^ 2 + (g.y - py) ^ 2 > (speed * dt * 0.3) ^ 2
end

--- The nearest player anyone could see from it, as { id, x, y, p }, within `reach`.
local function nearest(server, g, reach)
  local best, bestD2 = nil, reach * reach
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, g.x, g.y)
      if d2 < bestD2 then
        best, bestD2 = { id = id, x = x, y = y, p = p }, d2
      end
    end
  end
  return best
end

--- Hurt `p` by `amount`, an impact, and knock them `distance` px along `angle`.
local function hit(server, p, amount, angle, distance)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, amount, angle, "impact")
  end
  local onFoot = Features.byName["on-foot"]
  if onFoot and onFoot.serverShove and distance > 0 then
    onFoot:serverShove(server, p, math.cos(angle), math.sin(angle), distance, 0.35 + distance / 1200)
  end
end

local function setMode(g, mode)
  g.mode, g.t = mode, 0
end

--- Its scream lands: everyone in the cone it can reach, hidden or not (it
--- only picks whom to go after by what it sees; what it hits, it hits).
local function scream(G, g, server)
  local caught = {}
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local d = math.sqrt(dist2(x, y, g.x, g.y))
      local off = math.abs(wrap(math.atan2(y - g.y, x - g.x) - g.aim))
      if d <= G.screamRange and (off <= G.screamHalf or d < G.radius + 20) and Sight.clear(g.x, g.y, x, y) then
        local k = 1 - 0.55 * d / G.screamRange -- weaker towards the far end
        hit(server, p, G.screamDamage * k, math.atan2(y - g.y, x - g.x), G.screamShove * k)
        caught[#caught + 1] = p.id
      end
    end
  end
  return caught
end

--- Should it go for a medkit now? Looks once a second while it is hurt.
local function wantsHeal(g, time)
  if g.medkit then
    if Heal.there(g.medkit) then
      return true
    end
    g.medkit = nil
  end
  if not Heal.wants(g.hp, g.max) or time < (g.healLook or 0) then
    return false
  end
  g.healLook = time + Heal.checkEvery
  g.medkit = Heal.find(g.x, g.y)
  return g.medkit ~= nil
end

--- One tick of the Guard `g` with tuning `G`. Returns what happened worth
--- telling everyone: "scream" (with who it caught), or nil.
function Brain.think(G, g, server, dt, time)
  g.t = g.t + dt
  g.running = false
  g.swipeIn = math.max(0, g.swipeIn - dt)
  g.chargeIn = math.max(0, g.chargeIn - dt)
  g.screamIn = math.max(0, g.screamIn - dt)
  local st = g.breath
  local function done()
    st:step(g.running, dt)
  end
  if g.mode == "emerge" then
    if g.t >= G.rise then
      setMode(g, "hunt")
    end
    return done()
  end
  if g.frozen > 0 then
    g.frozen = g.frozen - dt
    return done()
  end

  -- What it is already in the middle of.
  if g.mode == "stunned" then
    if g.t >= G.stunTime then
      setMode(g, "hunt")
    end
    return done()
  elseif g.mode == "paw" then
    local q = g.target and nearest(server, g, G.chargeFar * 1.5)
    if q then -- it keeps its eye on them until it goes
      g.facing = turn(g.facing, math.atan2(q.y - g.y, q.x - g.x), G.turn, dt)
    end
    if g.t >= G.pawTime then
      st:spend(G.chargeCost)
      g.aim, g.hitIds = g.facing, {}
      setMode(g, "charge")
    end
    return done()
  elseif g.mode == "charge" then
    g.running = true
    local moved = move(g, G.radius * 0.8, g.aim, G.chargeSpeed, dt)
    for id, p in pairs(server.players) do
      if not g.hitIds[id] and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, g.x, g.y) <= (G.radius + 14) ^ 2 then
          g.hitIds[id] = true
          -- Thrown off the line, to whichever side of it they were.
          local side = wrap(math.atan2(y - g.y, x - g.x) - g.aim) >= 0 and 1 or -1
          hit(server, p, G.chargeDamage, g.aim + side * 0.6, G.chargeShove)
        end
      end
    end
    if not moved then
      g.chargeIn = G.chargeEvery
      setMode(g, "stunned") -- ran into something
    elseif g.t >= G.chargeTime then
      g.chargeIn = G.chargeEvery
      setMode(g, "hunt")
    end
    return done()
  elseif g.mode == "swipe" then
    if not g.swiped and g.t >= G.swipeHit then
      g.swiped = true
      for _, p in pairs(server.players) do
        if Features.present(p) then
          local x, y = Features.bodyPose(server, p)
          local a = math.atan2(y - g.y, x - g.x)
          if dist2(x, y, g.x, g.y) <= (G.swipeReach + 10) ^ 2 and math.abs(wrap(a - g.facing)) < 1.4 then
            hit(server, p, G.swipeDamage, a, G.swipeShove)
          end
        end
      end
    end
    if g.t >= G.swipeTime then
      g.swiped, g.swipeIn = nil, G.swipeEvery
      setMode(g, "hunt")
    end
    return done()
  elseif g.mode == "rear" then
    if g.t >= G.rearTime then
      st:spend(G.screamCost)
      setMode(g, "scream")
      done()
      return "scream", scream(G, g, server)
    end
    return done()
  elseif g.mode == "scream" then
    if g.t >= G.screamRecover then
      g.screamIn = G.screamEvery
      setMode(g, "hunt")
    end
    return done()
  end

  -- Out from under anything about to land on it.
  local threat = Dodge.threat(g.x, g.y, G.radius)
  if threat then
    local ux, uy = Dodge.away(threat, g.x, g.y)
    g.facing = turn(g.facing, math.atan2(uy, ux), G.turn * 2, dt)
    g.running = move(g, G.radius, math.atan2(uy, ux), st:pace(G.runSpeed, G.walkSpeed), dt)
      and not st:winded()
    g.mode = "dodge"
    return done()
  end
  if g.panic then
    g.panic.left = g.panic.left - dt
    local away = math.atan2(g.y - g.panic.y, g.x - g.panic.x)
    g.facing = turn(g.facing, away, G.turn, dt)
    move(g, G.radius, away, G.walkSpeed, dt)
    if g.panic.left <= 0 then
      g.panic = nil
    end
    return done()
  end
  if wantsHeal(g, time) then
    g.mode = "heal"
    local m = g.medkit
    if Heal.within(m, g.x, g.y, G.radius) then
      g.hp = math.min(g.max, g.hp + Heal.take(server, m))
      g.medkit = nil
    else
      local a = math.atan2(m.y - g.y, m.x - g.x)
      g.facing = turn(g.facing, a, G.turn, dt)
      g.running = not st:winded()
      move(g, G.radius, a, st:pace(G.runSpeed, G.walkSpeed), dt)
    end
    return done()
  end

  g.mode = "hunt"
  local q = nearest(server, g, G.sight)
  g.target = q and q.id
  if not q then
    return done()
  end
  local d = math.sqrt(dist2(q.x, q.y, g.x, g.y))
  local toward = math.atan2(q.y - g.y, q.x - g.x)
  local facingThem = math.abs(wrap(toward - g.facing)) < 0.35
  local clear = Sight.clear(g.x, g.y, q.x, q.y)
  if d <= G.swipeReach then
    g.facing = turn(g.facing, toward, G.turn * 1.5, dt)
    if g.swipeIn <= 0 then
      setMode(g, "swipe")
    end
    return done()
  end
  if clear and facingThem and g.screamIn <= 0 and d <= G.screamRange * 0.85 and st:has(G.screamCost)
    and random() < G.screamChance * dt then
    g.aim = toward
    setMode(g, "rear")
    return done()
  end
  if clear and facingThem and g.chargeIn <= 0 and d >= G.chargeNear and d <= G.chargeFar
    and st:has(G.chargeCost) and random() < G.chargeChance * dt then
    setMode(g, "paw")
    return done()
  end
  g.facing = turn(g.facing, toward, G.turn, dt)
  g.running = d > G.chargeFar and not st:winded()
  local speed = g.running and G.runSpeed or (st:winded() and G.walkSpeed or G.prowlSpeed)
  if not move(g, G.radius, toward, speed, dt) then
    -- Caught on something: round it the way it favours, or the other way.
    if not move(g, G.radius, toward + g.side * math.pi / 2, G.prowlSpeed, dt) then
      g.side = -g.side
    end
  end
  return done()
end

return Brain
