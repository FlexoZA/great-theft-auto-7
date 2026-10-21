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
--   heal     badly hurt (bosses/heal.lua): off to a medkit and takes it,
--            kiting (the standard's point 7): with somebody in sight it
--            faces them and prowls there, swiping whoever comes close,
--            screaming while the medkit is still far, charging only when
--            the line carries it towards the medkit; nobody in sight, it
--            runs for it. One it can't get to, it gives up on for a while.
--   dodge    out from under a player's ability about to land (bosses/dodge.lua).
--
-- Frozen, it stands stiff; a stink throws it off for a moment.
--
-- It gets about with the bosses' walking (bosses/walk.lua): straight at
-- somebody only when its whole width gets there, else round on `g.nav`
-- (the walking grid as it fits through it, guard.lua's).

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")

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

--- Solid ground at (x, y): what stops it.
function Brain.blocked(x, y)
  return Features.any("blocksPoint", x, y)
end

--- A step that way (bosses/walk.lua), `headlong` for a charge; true if it
--- got anywhere. Already caught in something (a charge or a shove that
--- ended in rock), it walks free until it is clear again.
local function move(G, g, angle, speed, dt, headlong)
  if not Walk.fits(Brain.blocked, g.x, g.y, G.radius) then
    g.x, g.y, g.stuck = g.x + math.cos(angle) * speed * dt, g.y + math.sin(angle) * speed * dt, 0
    return true
  end
  return Walk.step(g, Brain.blocked, angle, speed, dt, G.radius, headlong)
end

--- Which way to walk to (x, y): straight when its whole width gets there,
--- else round on its walking grid. Nil when there is no way (or it is there).
local function way(G, g, x, y, time)
  if Walk.wideClear(Brain.blocked, g.x, g.y, x, y, G.radius) then
    g.route = nil
    return math.atan2(y - g.y, x - g.x)
  end
  return Walk.route(g, g.nav, x, y, time)
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
        hit(server, p, G.screamDamage * k * g.power, math.atan2(y - g.y, x - g.x), G.screamShove * k)
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

--- Off to its medkit, kiting whoever it can see (the standard's point 7).
--- Ends with it in "heal", or in whatever it cut in with.
local function heal(G, g, server, dt, time)
  g.mode = "heal"
  local st, m = g.breath, g.medkit
  if Heal.within(m, g.x, g.y, G.radius) then
    g.hp = math.min(g.max, g.hp + Heal.take(server, m))
    g.medkit = nil
    return
  end
  local a = way(G, g, m.x, m.y, time)
  if not a or (g.stuck or 0) > 2 then -- no way it fits there, or caught: not this one, not for a while
    g.medkit, g.healLook, g.stuck, g.route = nil, time + 8, 0, nil
    return
  end
  local q = nearest(server, g, G.sight)
  g.target = q and q.id
  if not q then -- nobody to watch: it runs for it
    g.facing = turn(g.facing, a, G.turn, dt)
    g.running = not st:winded()
    move(G, g, a, st:pace(G.runSpeed, G.walkSpeed), dt)
    return
  end
  -- Facing them, fighting on its way there at a prowl.
  local d = math.sqrt(dist2(q.x, q.y, g.x, g.y))
  local toward = math.atan2(q.y - g.y, q.x - g.x)
  g.facing = turn(g.facing, toward, G.turn * (d <= G.swipeReach and 1.5 or 1), dt)
  local facingThem = math.abs(wrap(toward - g.facing)) < 0.35
  local clear = Sight.clear(g.x, g.y, q.x, q.y)
  local medkitFar = math.sqrt(dist2(m.x, m.y, g.x, g.y)) > G.kiteFar
  if d <= G.swipeReach and g.swipeIn <= 0 then
    return setMode(g, "swipe")
  end
  if clear and facingThem and medkitFar and g.screamIn <= 0 and d <= G.screamRange * 0.85 and st:has(G.screamCost)
    and random() < G.screamChance * dt then
    g.aim = toward
    return setMode(g, "rear")
  end
  -- A charge only down a line that carries it towards the medkit.
  if clear and facingThem and g.chargeIn <= 0 and d >= G.chargeNear and d <= G.chargeFar
    and math.abs(wrap(toward - math.atan2(m.y - g.y, m.x - g.x))) < G.kiteCharge and st:has(G.chargeCost)
    and random() < G.chargeChance * dt then
    return setMode(g, "paw")
  end
  move(G, g, a, st:winded() and G.walkSpeed or G.prowlSpeed, dt)
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
    local moved = move(G, g, g.aim, G.chargeSpeed, dt, true)
    for id, p in pairs(server.players) do
      if not g.hitIds[id] and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, g.x, g.y) <= (G.radius + 14) ^ 2 then
          g.hitIds[id] = true
          -- Thrown off the line, to whichever side of it they were.
          local side = wrap(math.atan2(y - g.y, x - g.x) - g.aim) >= 0 and 1 or -1
          hit(server, p, G.chargeDamage * g.power, g.aim + side * 0.6, G.chargeShove)
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
            hit(server, p, G.swipeDamage * g.power, a, G.swipeShove)
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
    g.running = move(G, g, math.atan2(uy, ux), st:pace(G.runSpeed, G.walkSpeed), dt)
      and not st:winded()
    g.mode = "dodge"
    return done()
  end
  if g.panic then
    g.panic.left = g.panic.left - dt
    local away = math.atan2(g.y - g.panic.y, g.x - g.panic.x)
    g.facing = turn(g.facing, away, G.turn, dt)
    move(G, g, away, G.walkSpeed, dt)
    if g.panic.left <= 0 then
      g.panic = nil
    end
    return done()
  end
  if wantsHeal(g, time) then
    heal(G, g, server, dt, time)
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
  local a = way(G, g, q.x, q.y, time)
  g.facing = turn(g.facing, a or toward, G.turn, dt)
  g.running = d > G.chargeFar and not st:winded()
  local speed = g.running and G.runSpeed or (st:winded() and G.walkSpeed or G.prowlSpeed)
  if a then
    g.running = move(G, g, a, speed, dt) and g.running
  else
    g.running = false
  end
  return done()
end

return Brain
