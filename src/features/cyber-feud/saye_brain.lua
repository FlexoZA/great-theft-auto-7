-- Director Saye's brain, on the host: what she does each tick on the Roof.
-- The woman herself (her numbers, lines and body) is saye.lua; she is
-- handed in as `s`, and her numbers are read off her (s.KEEP...).
--
-- She never runs. She is always in one of these, the later ones cutting in
-- on the earlier:
--
--   hunt   nobody in her sights: she walks to the nearest player anywhere,
--          round the roof's clutter on the walking grid
--   fight  somebody she can see: she keeps her distance (KEEP), walking in
--          or backing off, and works through her moves (below)
--   heal   badly hurt (bosses/heal.lua): she walks to the nearest medkit
--          lying within reach
--
-- Her moves:
--
--   sightline  she raises her pistol at where they stand and a thin magenta
--              line marks the shot for AIM seconds; then one heavy round
--              down it. Step off the line. Phase 2: two at once, in a V.
--   drones     three executive drones orbit her and shoot at whoever is
--              nearest (saye.lua flies them); shot down, she calls more
--              after DRONES_BACK seconds.
--   restructuring  every so often she drops a sentry turret where she
--              stands (turrets.lua) and walks away from it.
--
-- At half health her skin cracks (phase 2): the sightline takes half as
-- long, fires in a V, and she walks faster. A freeze holds her stiff; an
-- ability about to land on her gets her out from under it
-- (bosses/dodge.lua). Her breath (bosses/stamina.lua): walking briskly
-- spends it, a turret needs some in her and costs it; winded she strolls.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The nearest player she can see, and where they are; failing that, the
--- nearest player anywhere, and whether she sees them.
function Brain.target(s, server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, s.x, s.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= s.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(s.x, s.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

local function goTo(s, x, y, speed, dt)
  local g = s.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or s.time > g.replanAt or s.stuck > 0.3 then
    local corners = s.nav and s.nav:path(s.x, s.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = s.time + 1.2 }
    s.goal = g
  end
  local c = g.corners[g.at]
  if dist2(s.x, s.y, c.x, c.y) < 18 * 18 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  s.facing = math.atan2(c.y - s.y, c.x - s.x)
  s:walk(s.facing, speed, dt)
  return false
end

local function wantsHeal(s)
  if s.medkit then
    if Heal.there(s.medkit) then
      return true
    end
    s.medkit, s.goal = nil, nil
  end
  if not Heal.wants(s.hp, s.max) or s.time < (s.healLook or 0) then
    return false
  end
  s.healLook = s.time + Heal.checkEvery
  s.medkit = Heal.find(s.x, s.y)
  s.goal = nil
  return s.medkit ~= nil
end

--- The sightline under way: the line holds, then the round (or two) goes.
local function stepAim(s, server, dt, events)
  s.aimT = s.aimT + dt
  if s.aimT < (s.phase2 and s.AIM_2 or s.AIM) then
    return
  end
  if s.phase2 then
    s:fire(server, s.aim - s.V)
    s:fire(server, s.aim + s.V)
  else
    s:fire(server, s.aim)
  end
  events[#events + 1] = { "shot" }
  s.aiming = false
  s.sightIn = s.phase2 and s.SIGHT_EVERY_2 or s.SIGHT_EVERY
end

--- What she does this tick. Returns the events the others should hear
--- about: { "say", line }, { "shot" }, { "turret", x, y }.
function Brain.think(s, server, dt)
  local events = {}
  s.time = s.time + dt
  s.running = false
  s.sightIn = s.sightIn - dt
  s.turretIn = s.turretIn - dt
  s.sayIn = s.sayIn - dt
  if not s.phase2 and s.hp <= s.max / 2 then
    s.phase2 = true
    events[#events + 1] = { "say", s.LINE.phase2 }
  end
  if s.sayIn <= 0 then
    s.sayIn = s.SAY_EVERY[1] + random() * (s.SAY_EVERY[2] - s.SAY_EVERY[1])
    events[#events + 1] = { "say", s.LINE.taunt[random(#s.LINE.taunt)] }
  end
  s:stepDrones(server, dt, events)
  if s.frozen > 0 then
    s.frozen = s.frozen - dt
    s.breath:step(false, dt)
    return events
  end
  if s.aiming then -- she holds still while the line is up
    stepAim(s, server, dt, events)
    s.breath:step(false, dt)
    return events
  end
  local threat = Dodge.threat(s.x, s.y, s.RADIUS)
  if threat then
    local ux, uy = Dodge.away(threat, s.x, s.y)
    s.facing = math.atan2(uy, ux)
    s:walk(s.facing, s:pace(), dt)
    s.running = not s.breath:winded()
    s.breath:step(s.running, dt)
    return events
  end
  if wantsHeal(s) then
    s.mode = "heal"
    local m = s.medkit
    goTo(s, m.x, m.y, s:pace(), dt)
    s.running = not s.breath:winded()
    if Heal.within(m, s.x, s.y, s.RADIUS) then
      local got = Heal.take(server, m)
      s.hp = math.min(s.max, s.hp + got)
      s.medkit, s.goal = nil, nil
      if got > 0 then
        events[#events + 1] = { "say", s.LINE.heal }
      end
    end
    s.breath:step(s.running, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(s, server)
  if not target then
    s.breath:step(false, dt)
    return events
  end
  local toward = math.atan2(ty - s.y, tx - s.x)
  local d = math.sqrt(dist2(tx, ty, s.x, s.y))
  if not visible then
    s.mode = "hunt"
    goTo(s, tx, ty, s:pace(), dt)
    s.running = not s.breath:winded()
    s.breath:step(s.running, dt)
    return events
  end
  s.mode, s.goal = "fight", nil
  s.facing = toward
  if s.sightIn <= 0 then
    s.aiming, s.aimT, s.aim = true, 0, toward -- set now: step off this line
    s.breath:step(false, dt)
    return events
  end
  if s.turretIn <= 0 and s.breath:has(s.TURRET_COST) and s:turretsUp() < s.TURRETS_MAX then
    s.breath:spend(s.TURRET_COST)
    s.turretIn = s.TURRET_EVERY
    events[#events + 1] = { "turret", s.x, s.y, toward }
    s.leaveFrom = { x = s.x, y = s.y, left = s.LEAVE } -- and she walks off from it
    if random() < 0.5 then
      events[#events + 1] = { "say", s.LINE.turret }
    end
  end
  if s.leaveFrom then
    s.leaveFrom.left = s.leaveFrom.left - dt
    local away = math.atan2(s.y - s.leaveFrom.y, s.x - s.leaveFrom.x) + 0.6
    s:walk(away, s:pace(), dt)
    s.running = not s.breath:winded()
    if s.leaveFrom.left <= 0 then
      s.leaveFrom = nil
    end
  elseif d > s.KEEP + 60 then
    s:walk(toward, s:pace(), dt)
    s.running = not s.breath:winded()
  elseif d < s.KEEP - 80 then
    s:walk(toward + math.pi + (s.side or 0.4), s:pace(), dt) -- backs off, still facing them
    s.running = not s.breath:winded()
    if s.stuck > 0.5 then
      s.side = -(s.side or 0.4) -- into a corner: the other way round
    end
  end
  s.facing = toward
  s.breath:step(s.running, dt)
  return events
end

return Brain
