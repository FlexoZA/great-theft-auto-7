-- The Mecha Zombies' brain, on the host: what one does each tick. The
-- zombie itself (its numbers, its guns, the wire) is mecha_zombie.lua; it
-- is handed in as `z`, its numbers read off it (z.PLASMA_FROM...), and its
-- hands as `hands` { fire(server, z, x, y, angle, gun), cut(server, z, p,
-- damage, angle), scream(server, z, tx, ty) }.
--
-- It is always in one of these:
--
--   patrol  nobody seen: round its mob's loop, stopping at each corner to
--           look about (LOOK_FOR)
--   hunt    somebody it can't see any more: after them on the walking grid,
--           back to its loop when they're gone (HUNTS)
--   fight   somebody it can see: by how far off they are, one of
--
-- its moves, each with a tell:
--
--   plasma  past PLASMA_FROM: its cannon glows (PLASMA_WINDUP), then a
--           burst of BURST bolts (PLASMA_GAP apart), each `fire`: slow
--           enough to step out of the way
--   flame   between TALON_REACH and PLASMA_FROM: its pilot light flares
--           (FLAME_WINDUP), then it sprays fire (FLAME_FOR), coming round
--           after you slowly
--   talons  up close (TALON_REACH): its claws go up (TALON_WINDUP), then a
--           swipe (`melee`)
--   scream  when it wakes (seen, shot, or its mob woken), and again every
--           SCREAM_EVERY while it can see somebody: it throws its head back
--           (SCREAM_WINDUP, the sound wave showing) and screams: every mob
--           and every one of the possessed within SCREAM_RADIUS comes
--
-- Ranged fodder: it closes to KEEP and holds there, side-stepping, rather
-- than charging in. A freeze holds it stiff.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- The nearest player it can see, and where; failing that the nearest within
--- HUNTS, and whether it sees them.
function Brain.target(z, server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, z.x, z.y)
      if d2 <= z.HUNTS ^ 2 and (not anyD2 or d2 < anyD2) then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= z.SEES ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(z.x, z.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

local function goTo(z, x, y, speed, dt)
  local g = z.goal
  if not g or dist2(g.x, g.y, x, y) > 60 * 60 or z.time > g.replanAt or z.stuck > 0.3 then
    local corners
    if not Ground.clear(z.x, z.y, x, y) then
      corners = z.nav and z.nav:path(z.x, z.y, x, y)
    end
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = z.time + 1 }
    z.goal = g
  end
  local c = g.corners[g.at]
  if dist2(z.x, z.y, c.x, c.y) < 16 * 16 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  local a = math.atan2(c.y - z.y, c.x - z.x)
  z:turn(a, dt)
  z:walk(a, speed, dt)
  return false
end

--- Start move `move` (with its tell).
local function start(z, move)
  z.move, z.moveT, z.goal = move, 0, nil
end

--- Round its mob's loop, a moment at each corner looking about.
local function patrol(z, dt)
  z.mode = "patrol"
  local route = z.route
  if not route or #route == 0 then
    return
  end
  if z.lookFor > 0 then
    z.lookFor = z.lookFor - dt
    z:turn(z.facing + math.sin(z.time * 1.3) * 0.8, dt, z.TURN * 0.3)
    return
  end
  local p = route[z.leg]
  if goTo(z, p.x, p.y, z.PATROL, dt) then
    z.leg = z.leg % #route + 1
    z.lookFor, z.goal = z.LOOK_FOR, nil
  end
end

--- A move under way, on to its end.
local function carryOn(z, server, dt, hands, events)
  z.moveT = z.moveT + dt
  local p = z.aimAt
  local tx, ty
  if p and Features.visible(server, p) then
    tx, ty = Features.bodyPose(server, p)
  end
  if z.move == "scream" then
    if z.moveT >= z.SCREAM_WINDUP and not z.screamed then
      z.screamed = true
      hands.scream(server, z, tx or z.x, ty or z.y)
      events[#events + 1] = { "scream" }
    end
    if z.moveT >= z.SCREAM_WINDUP + 0.4 then
      z.move, z.screamed = nil, nil
      z.screamIn = z.SCREAM_EVERY
    end
    return
  end
  if tx then
    z:turn(math.atan2(ty - z.y, tx - z.x), dt, z.move == "flame" and z.TURN * 0.45 or z.TURN)
  end
  if z.move == "plasma" then
    if z.moveT >= z.PLASMA_WINDUP then
      z.move, z.moveT, z.left, z.gapIn = "burst", 0, z.BURST, 0
    end
  elseif z.move == "burst" then
    z.gapIn = z.gapIn - dt
    if z.gapIn <= 0 and z.left > 0 then
      local mx, my = z:muzzle(1)
      hands.fire(server, z, mx, my, tx and math.atan2(ty - my, tx - mx) or z.facing, z.plasmaGun)
      z.left, z.gapIn = z.left - 1, z.PLASMA_GAP
    end
    if z.left <= 0 and z.gapIn <= 0 then
      z.move, z.plasmaIn = nil, between(z.PLASMA_EVERY)
    end
  elseif z.move == "light" then
    if z.moveT >= z.FLAME_WINDUP then
      z.move, z.moveT, z.flameIn = "flame", 0, 0
    end
  elseif z.move == "flame" then
    z.flameIn = z.flameIn - dt
    if z.flameIn <= 0 then
      local mx, my = z:muzzle(-1)
      hands.fire(server, z, mx, my, z.facing, z.flameGun)
      z.flameIn = z.flameGun.cooldown
    end
    if z.moveT >= z.FLAME_FOR then
      z.move, z.flameCool = nil, z.FLAME_EVERY
    end
  elseif z.move == "talons" then
    if z.moveT >= z.TALON_WINDUP then
      if tx and dist2(tx, ty, z.x, z.y) <= (z.TALON_REACH + 10) ^ 2 then
        hands.cut(server, z, p, z.TALON_DAMAGE, math.atan2(ty - z.y, tx - z.x))
        events[#events + 1] = { "hit", "talons", z.x + math.cos(z.facing) * 16, z.y + math.sin(z.facing) * 16 }
      end
      z.move, z.talonIn = nil, z.TALON_EVERY
    end
  end
end

--- Somebody in sight at (tx, ty): pick a move by how far off they are, or
--- hold at KEEP, side-stepping.
local function fight(z, target, tx, ty, dt)
  z.mode = "fight"
  local d = math.sqrt(dist2(tx, ty, z.x, z.y))
  local toward = math.atan2(ty - z.y, tx - z.x)
  z.aimAt = target
  z:turn(toward, dt)
  local facing = math.abs(Sight.angleDiff(toward, z.facing))
  if z.screamIn <= 0 then
    start(z, "scream")
    return
  end
  if d <= z.TALON_REACH and z.talonIn <= 0 then
    start(z, "talons")
    return
  end
  if facing < 0.5 then
    if d > z.PLASMA_FROM and z.plasmaIn <= 0 then
      start(z, "plasma")
      return
    elseif d <= z.PLASMA_FROM and d > z.TALON_REACH and z.flameCool <= 0 then
      start(z, "light")
      return
    end
  end
  if d > z.KEEP[2] then
    z:walk(toward, z.WALK, dt)
  elseif d < z.KEEP[1] and d > z.TALON_REACH * 1.5 then
    z:walk(toward + math.pi, z.WALK * 0.6, dt)
  else
    if not z:walk(toward + z.side * math.pi / 2, z.WALK * 0.5, dt) or random() < dt * 0.4 then
      z.side = -z.side
    end
  end
end

--- What it does this tick. `hands` as above. Returns the events the others
--- should hear about: { "scream" }, { "hit", name, x, y }.
function Brain.think(z, server, dt, hands)
  local events = {}
  z.time = z.time + dt
  z.plasmaIn = z.plasmaIn - dt
  z.flameCool = z.flameCool - dt
  z.talonIn = z.talonIn - dt
  z.screamIn = z.screamIn - dt
  if z.frozen > 0 then
    z.frozen = z.frozen - dt
    return events
  end
  if z.move then
    carryOn(z, server, dt, hands, events)
    return events
  end
  if not z.awake then
    patrol(z, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(z, server)
  if not target then -- nobody about: back to its loop
    z.awake = false
    patrol(z, dt)
    return events
  end
  if visible then
    fight(z, target, tx, ty, dt)
  else
    z.mode = "hunt"
    goTo(z, tx, ty, z.WALK, dt)
  end
  return events
end

return Brain
