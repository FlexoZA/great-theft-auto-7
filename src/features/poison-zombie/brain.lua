-- The Poison Zombie's brain, on the host (init.lua runs it and owns the
-- wire). Modes that cut in on each other:
--
--   wait     standing on the pass where he was put, breathing hard. A
--            player he can see within `wake` of him (or a round in him)
--            wakes him:
--   howl     `howlTime` seconds of it, then he goes after them for good
--   hunt     after the nearest player he can see within `sight`, never
--            further than `leash` from the pass (with nobody to go after he
--            trudges back there). He shuffles (`shuffleSpeed`), and lurches
--            (`lurchSpeed`, spending breath: bosses/stamina.lua) after
--            somebody further off than `lurchFrom`; winded, he drags
--            himself along at `walkSpeed`. From there he picks:
--   swipe    within `swipeReach`: the claws across, `swipeDamage` melee
--            (they bleed). No breath.
--   throw    `throwNear` .. `throwFar` off, a crab on his back, a clear line
--            and the breath for it (`throwCost`): he reaches back over his
--            shoulder for one and flings it at them (`throwRelease` seconds
--            in). init.lua sends it flying (crabs.lua) when think() says so.
--   heal     badly hurt (bosses/heal.lua): off to a medkit and takes it.
--            With somebody in sight he kites there: faces them and backs or
--            sidesteps to it at a shuffle, clawing whoever comes close and
--            throwing a crab while the kit is still `HEAL_FAR` off.
--   dodge    out from under a player's ability about to land (bosses/dodge.lua).
--
-- He walks the standard's way (bosses/walk.lua): straight at somebody only
-- when his whole width gets there, else round on his walking grid (init.lua
-- cuts it as wide as he is, the water counting), so the water he can see
-- across doesn't catch him. No way round to them, he stands and throws.
--
-- A new crab grows on his back every `regrow` seconds while he has fewer
-- than `crabs`. Frozen, he stands stiff; a stink throws him off for a moment.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")

local Brain = {}

local random = love.math.random

local HEAL_FAR = 260 -- px off the medkit past which he still stops to throw a crab, kiting
local HEAL_GIVE_UP = 5 -- seconds before he looks again for a medkit he found no way to

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

--- Nothing he can stand on at (x, y): walls, rock and the water alike
--- (init.lua cuts his walking grid by it too).
local function blocked(x, y)
  return Features.any("blocksPoint", x, y)
end
Brain.blocked = blocked

--- A step along `angle`, feeling round what is in the way (bosses/walk.lua);
--- true if it got anywhere.
local function step(G, z, angle, speed, dt)
  return Walk.step(z, blocked, angle, speed, dt, G.radius)
end

--- Which way to walk to (x, y): straight when his whole width gets there,
--- else along his walking grid (init.lua puts it on him). An angle; or nil
--- and true once he is there, nil and false when there is no way.
local function way(G, z, x, y, time)
  if Walk.wideClear(blocked, z.x, z.y, x, y, G.radius) then
    if (z.x - x) ^ 2 + (z.y - y) ^ 2 < 4 then
      return nil, true
    end
    return math.atan2(y - z.y, x - z.x)
  end
  return Walk.route(z, z.nav, x, y, time)
end

--- Walk towards (x, y), turning to where he goes. True once he is there.
local function goTo(G, z, x, y, speed, dt, time)
  local a, there = way(G, z, x, y, time)
  if a then
    z.facing = turn(z.facing, a, G.turn, dt)
    step(G, z, a, speed, dt)
  end
  return there
end

--- The nearest player he could see, as { id, x, y, p, car }, within `reach` of
--- him and `leash` of home.
local function nearest(server, z, reach, home, leash)
  local best, bestD2 = nil, reach * reach
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local d2 = dist2(x, y, z.x, z.y)
      if d2 < bestD2 and dist2(x, y, home.x, home.y) <= leash * leash then
        best, bestD2 = { id = id, x = x, y = y, p = p, car = not onFoot and p.vehicle or nil }, d2
      end
    end
  end
  return best
end

local function setMode(z, mode)
  z.mode, z.t = mode, 0
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(z, time)
  if z.medkit then
    if Heal.there(z.medkit) then
      return true
    end
    z.medkit = nil
  end
  if not Heal.wants(z.hp, z.max) or time < (z.healLook or 0) then
    return false
  end
  z.healLook = time + Heal.checkEvery
  z.medkit = Heal.find(z.x, z.y)
  return z.medkit ~= nil
end

--- His claws land: everyone in front of him within reach, hidden or not.
local function swipe(G, z, server)
  local weapons = Features.byName.weapons
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local a = math.atan2(y - z.y, x - z.x)
      local reach = G.swipeReach + (p.vehicle and G.carReach or 0) + 10 -- as far as he stopped to swipe from, and a bit
      if dist2(x, y, z.x, z.y) <= reach * reach and math.abs(wrap(a - z.facing)) < 1.3
        and weapons and weapons.serverDamage then
        weapons:serverDamage(server, p, nil, G.swipeDamage * z.power, a, "melee")
      end
    end
  end
end

--- Close enough to claw `q` (`d` px off, that way), or a crab to throw at
--- them (`throwOk`: room for one, and he may stand for it)? Starts it and
--- says true.
local function fight(G, z, q, d, toward, throwOk, dt)
  local reach = G.swipeReach + (q.car and G.carReach or 0) -- a car's side is further out than a man
  if d <= reach then
    if z.swipeIn <= 0 then
      setMode(z, "swipe")
      return true
    end
    return false
  end
  if z.crabs > 0 and throwOk and z.throwIn <= 0 and d >= G.throwNear and d <= G.throwFar
    and math.abs(wrap(toward - z.facing)) < 0.6 and z.breath:has(G.throwCost) and random() < G.throwChance * dt
    and Sight.clear(z.x, z.y, q.x, q.y) then
    z.aimX, z.aimY = q.x, q.y
    setMode(z, "throw")
    return true
  end
  return false
end

--- Wake him (a round in him, or somebody seen): he howls first.
function Brain.wake(z)
  if z.mode == "wait" and not z.awake then
    z.awake = true
    setMode(z, "howl")
  end
end

--- One tick of the zombie `z` with tuning `G`; `room` says whether another
--- crab may go out (crabs.lua keeps how many are about). Returns what
--- happened worth telling init.lua: "throw" and where the crab goes
--- ({ x, y, tx, ty }), or nil.
function Brain.think(G, z, server, dt, time, room)
  z.t = z.t + dt
  z.running = false
  z.swipeIn = math.max(0, z.swipeIn - dt)
  z.throwIn = math.max(0, z.throwIn - dt)
  local st = z.breath
  local function done()
    st:step(z.running, dt)
  end
  if z.crabs < G.crabs then
    z.regrowIn = z.regrowIn - dt
    if z.regrowIn <= 0 then
      z.crabs, z.regrowIn = z.crabs + 1, G.regrow
    end
  else
    z.regrowIn = G.regrow
  end
  if z.frozen > 0 then
    z.frozen = z.frozen - dt
    return done()
  end
  local home = { x = z.homeX, y = z.homeY }

  if z.mode == "wait" then
    local q = nearest(server, z, G.wake, home, G.leash)
    if q and (z.awake or Sight.clear(z.x, z.y, q.x, q.y)) then
      if z.awake then
        setMode(z, "hunt")
      else
        Brain.wake(z)
      end
    end
    return done()
  elseif z.mode == "howl" then
    if z.t >= G.howlTime then
      setMode(z, "hunt")
    end
    return done()
  elseif z.mode == "swipe" then
    if not z.swiped and z.t >= G.swipeHit then
      z.swiped = true
      swipe(G, z, server)
    end
    if z.t >= G.swipeTime then
      z.swiped, z.swipeIn = nil, G.swipeEvery
      setMode(z, "hunt")
    end
    return done()
  elseif z.mode == "throw" then
    local q = z.target and server.players[z.target]
    if q and Features.visible(server, q) and not z.thrown then -- he keeps his eye on them until he lets go
      local x, y = Features.bodyPose(server, q)
      z.aimX, z.aimY = x, y
      z.facing = turn(z.facing, math.atan2(y - z.y, x - z.x), G.turn * 1.5, dt)
    end
    local event
    if not z.thrown and z.t >= G.throwRelease then
      z.thrown = true
      z.crabs = z.crabs - 1
      st:spend(G.throwCost)
      -- Not quite where they stand: a crab is not a rifle round.
      local spread = G.throwSpread * math.sqrt(random())
      local a = random() * 2 * math.pi
      local hx, hy = z.x + math.cos(z.facing) * 14, z.y + math.sin(z.facing) * 14
      event = { x = hx, y = hy, tx = z.aimX + math.cos(a) * spread, ty = z.aimY + math.sin(a) * spread }
    end
    if z.t >= G.throwTime then
      z.thrown, z.throwIn = nil, G.throwEvery
      setMode(z, "hunt")
    end
    done()
    return event and "throw" or nil, event
  end

  -- Out from under anything about to land on him.
  local threat = Dodge.threat(z.x, z.y, G.radius)
  if threat then
    local ux, uy = Dodge.away(threat, z.x, z.y)
    z.facing = turn(z.facing, math.atan2(uy, ux), G.turn * 2, dt)
    z.running = step(G, z, math.atan2(uy, ux), st:pace(G.lurchSpeed, G.walkSpeed), dt) and not st:winded()
    z.mode = "dodge"
    return done()
  end
  if z.panic then
    z.panic.left = z.panic.left - dt
    local away = math.atan2(z.y - z.panic.y, z.x - z.panic.x)
    z.facing = turn(z.facing, away, G.turn, dt)
    step(G, z, away, G.walkSpeed, dt)
    if z.panic.left <= 0 then
      z.panic = nil
    end
    return done()
  end
  if wantsHeal(z, time) then
    z.mode = "heal"
    local m = z.medkit
    if Heal.within(m, z.x, z.y, G.radius) then
      z.hp = math.min(z.max, z.hp + Heal.take(server, m))
      z.medkit = nil
      return done()
    end
    local a, there = way(G, z, m.x, m.y, time)
    if not a and not there then -- no way round to it: look again in a while
      z.medkit, z.healLook = nil, time + HEAL_GIVE_UP
      return done()
    end
    -- Kiting: somebody in sight, he keeps his face (and claws, and crabs)
    -- on them and backs or sidesteps to the kit at his shuffle.
    local q = nearest(server, z, G.sight, z, G.sight)
    z.target = q and q.id
    if q then
      local d = math.sqrt(dist2(q.x, q.y, z.x, z.y))
      local toward = math.atan2(q.y - z.y, q.x - z.x)
      z.facing = turn(z.facing, toward, G.turn * 1.5, dt)
      local far = dist2(m.x, m.y, z.x, z.y) > HEAL_FAR * HEAL_FAR -- a rooted throw only while the kit is a way off
      if fight(G, z, q, d, toward, room and far, dt) then
        return done()
      end
      if a then
        step(G, z, a, st:winded() and G.walkSpeed or G.shuffleSpeed, dt)
      end
      return done()
    end
    if a then
      z.facing = turn(z.facing, a, G.turn, dt)
      z.running = not st:winded()
      step(G, z, a, st:pace(G.lurchSpeed, G.walkSpeed), dt)
    end
    return done()
  end

  z.mode = "hunt"
  local q = nearest(server, z, G.sight, home, G.leash)
  z.target = q and q.id
  if not q then
    -- Nobody: back to the pass, and wait there.
    if dist2(z.x, z.y, z.homeX, z.homeY) <= 30 * 30 or goTo(G, z, z.homeX, z.homeY, G.shuffleSpeed, dt, time) then
      setMode(z, "wait")
    end
    return done()
  end
  local d = math.sqrt(dist2(q.x, q.y, z.x, z.y))
  local toward = math.atan2(q.y - z.y, q.x - z.x)
  if fight(G, z, q, d, toward, room, dt) then
    return done()
  end
  if d <= G.swipeReach + (q.car and G.carReach or 0) then
    z.facing = turn(z.facing, toward, G.turn * 1.5, dt)
    return done()
  end
  z.running = d > G.lurchFrom and not st:winded()
  local speed = z.running and G.lurchSpeed or (st:winded() and G.walkSpeed or G.shuffleSpeed)
  local a = way(G, z, q.x, q.y, time)
  if a then -- no way round to them (over the water): he stands and throws
    z.facing = turn(z.facing, a, G.turn, dt)
    step(G, z, a, speed, dt)
  else
    z.running = false
    z.facing = turn(z.facing, toward, G.turn, dt)
  end
  return done()
end

return Brain
