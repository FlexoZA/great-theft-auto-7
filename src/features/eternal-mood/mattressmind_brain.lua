-- The Spider Mattressmind's brain, on the host: what it does each tick on
-- the Mattress's plateau. The beast itself (its numbers, lines and the
-- lock) is mattressmind.lua; it is handed in as `m`, and its numbers are
-- read off it (m.KEEP...).
--
-- It is always in one of these, the later ones cutting in on the earlier:
--
--   home   nobody on the plateau (the spec's `zone`): back onto its spot
--          before the gate, facing down the ramp
--   hunt   somebody on the plateau it can't see: after them, on the
--          walking grid
--   fight  somebody it can see: it keeps its distance (KEEP), walking any
--          way on its legs, turning to face them, and lets fly
--   heal   badly hurt (bosses/heal.lua): off for the nearest medkit
--          lying within reach ("...comfy..."); with somebody in sight it
--          kites there, facing them and slamming whoever comes close, and
--          spins up the chaingun or yawns only while it is still far off
--          (KITE_FAR)
--
-- Its moves, each with a tell before it lands:
--
--   chaingun  the barrels spin up (SPIN, whining, glowing), then a burst
--             (FIRE_FOR, a round every FIRE_EVERY), the aim dragging after
--             you at AIM_TURN: run across it
--   slam      up close (SLAM_REACH) its legs go up (SLAM_WINDUP, the reach
--             shown on the floor) and come down: whoever is in it takes it
--             (`impact`) and is knocked away
--   yawn      phase 2 only (under half its health), every YAWN_EVERY: a
--             huge yawn for YAWN seconds that pulls everyone within
--             YAWN_REACH in (mattressmind.lua does the pulling), then
--             shuts on whoever it got (`melee`, spat out)
--   company   at two thirds and a third of its health: imps and
--             Cacodaemons up onto the plateau (mattressmind.lua calls them)
--
-- A freeze holds it stiff; an ability about to land on it gets it out from
-- under it (bosses/dodge.lua). Its breath (bosses/stamina.lua): a burst
-- needs some in it and costs it; winded it creeps.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- The nearest player on the plateau it can see, and where they are;
--- failing that, the nearest on it at all, and whether it sees them.
function Brain.target(m, server)
  local Mattressmind = require("src.features.eternal-mood.mattressmind")
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if Mattressmind.inZone(x, y) then
        local d2 = dist2(x, y, m.x, m.y)
        if not anyD2 or d2 < anyD2 then
          any, ax, ay, anyD2 = p, x, y, d2
        end
        if d2 <= m.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(m.x, m.y, x, y) then
          seen, sx, sy, seenD2 = p, x, y, d2
        end
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

local function goTo(m, x, y, speed, dt)
  local g = m.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or m.time > g.replanAt or m.stuck > 0.3 then
    local corners = m.nav and m.nav:path(m.x, m.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = m.time + 1.2 }
    m.goal = g
  end
  local c = g.corners[g.at]
  if dist2(m.x, m.y, c.x, c.y) < 24 * 24 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  local a = math.atan2(c.y - m.y, c.x - m.x)
  m:turn(a, dt)
  m:walk(a, speed, dt)
  return false
end

local function wantsHeal(m)
  if m.medkit then
    if Heal.there(m.medkit) then
      return true
    end
    m.medkit, m.goal = nil, nil
  end
  if not Heal.wants(m.hp, m.max) or m.time < (m.healLook or 0) then
    return false
  end
  m.healLook = m.time + Heal.checkEvery
  m.medkit = Heal.find(m.x, m.y)
  m.goal = nil
  return m.medkit ~= nil
end

--- Everyone within `radius` of (x, y): each takes `damage` of `dtype` and
--- is shoved `shove` px away from (x, y). Returns how many it caught.
local function strike(server, x, y, radius, damage, dtype, shove)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  local caught = 0
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if dist2(px, py, x, y) <= radius * radius then
        caught = caught + 1
        local a = math.atan2(py - y, px - x)
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, damage, a, dtype)
        end
        if onFoot and onFoot.serverShove then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), shove, 0.35)
        end
      end
    end
  end
  return caught
end

local function nextAttack(m)
  m.attackIn = between(m.phase2 and m.ATTACK_EVERY_2 or m.ATTACK_EVERY)
end

--- A yawn, a slam or a burst at `target` (`d` off, along `toward`), if one
--- is due; true when one starts. Kiting to a medkit (`kiting`), the
--- stand-still ones (a yawn, the chaingun) only while that is still far off.
local function attack(m, target, d, toward, kiting)
  local facing = math.abs(Sight.angleDiff(toward, m.facing))
  local far = not (kiting and dist2(m.x, m.y, m.medkit.x, m.medkit.y) < m.KITE_FAR ^ 2)
  if m.phase2 and m.yawnIn <= 0 and far then
    m.move, m.moveT = "yawn", 0
    return true
  end
  if d <= m.SLAM_REACH and m.slamIn <= 0 then
    m.move, m.moveT = "slam", 0
    return true
  end
  if m.attackIn <= 0 and facing < 0.4 and m.breath:has(m.FIRE_COST) and far then
    m.breath:spend(m.FIRE_COST)
    m.move, m.moveT, m.aim, m.aimAt = "spin", 0, toward, target
    return true
  end
  return false
end

--- Off to the medkit it's after, picking it up there: kiting with somebody
--- in sight (bosses/init.lua's point 7), straight for it with nobody.
local function heal(m, server, events, dt, target, tx, ty, visible)
  m.mode = "heal"
  local kit = m.medkit
  local way, there = Walk.route(m, m.nav, kit.x, kit.y, m.time)
  if there then -- at the grid's last corner, not yet on the kit: the last step straight at it
    way = math.atan2(kit.y - m.y, kit.x - m.x)
  end
  if way == nil and not there then -- no way there it fits: it fights on, and looks again in a while
    m.medkit, m.route, m.healLook = nil, nil, m.time + Heal.noWay
    return false
  end
  if visible then
    local toward = math.atan2(ty - m.y, tx - m.x)
    m:turn(toward, dt)
    if attack(m, target, math.sqrt(dist2(tx, ty, m.x, m.y)), toward, true) then
      return
    end
    if way then
      m:walk(way, m:pace(), dt)
    end
  else
    goTo(m, kit.x, kit.y, m:pace(), dt)
  end
  m.running = not m.breath:winded()
  if Heal.within(kit, m.x, m.y, m.RADIUS) then
    local got = Heal.take(server, kit)
    m.hp = math.min(m.max, m.hp + got)
    m.medkit, m.goal, m.route = nil, nil, nil
    if got > 0 then
      events[#events + 1] = { "say", m.LINE.heal }
    end
  end
end

--- What it does this tick. Returns the events the others should hear
--- about: { "say", line }, { "round", x, y, angle }, { "hit", name, x, y }, { "call" }.
function Brain.think(m, server, dt)
  local events = {}
  m.time = m.time + dt
  m.running = false
  m.attackIn = m.attackIn - dt
  m.slamIn = m.slamIn - dt
  m.sayIn = m.sayIn - dt
  if m.phase2 then
    m.yawnIn = m.yawnIn - dt
  end
  if not m.phase2 and m.hp <= m.max / 2 then
    m.phase2, m.yawnIn = true, 3
    events[#events + 1] = { "say", m.LINE.phase2 }
  end
  local mark = m.CALL_AT[m.calls + 1]
  if mark and m.hp <= m.max * mark then
    m.calls = m.calls + 1
    events[#events + 1] = { "call" }
    events[#events + 1] = { "say", m.LINE.call }
  end
  if m.frozen > 0 then
    m.frozen = m.frozen - dt
    m.breath:step(false, dt)
    return events
  end
  if m.move then -- a move under way: it stands and does it
    m.moveT = m.moveT + dt
    if m.move == "spin" then
      local p = m.aimAt
      if p and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        m.aim = math.atan2(y - m.y, x - m.x)
        m:turn(m.aim, dt)
      end
      if m.moveT >= m.SPIN then
        m.move, m.moveT, m.roundIn = "fire", 0, 0
      end
    elseif m.move == "fire" then
      local p = m.aimAt
      if p and Features.visible(server, p) then -- the aim drags after them
        local x, y = Features.bodyPose(server, p)
        local d = Sight.angleDiff(math.atan2(y - m.y, x - m.x), m.aim)
        local step = m.AIM_TURN * dt
        m.aim = m.aim + math.max(-step, math.min(step, d))
      end
      m:turn(m.aim, dt)
      m.roundIn = m.roundIn - dt
      while m.roundIn <= 0 do
        m.roundIn = m.roundIn + m.FIRE_EVERY
        local x, y = m:muzzle()
        events[#events + 1] = { "round", x, y, m.aim }
      end
      if m.moveT >= m.FIRE_FOR then
        m.move = nil
        nextAttack(m)
      end
    elseif m.move == "slam" then
      if m.moveT >= m.SLAM_WINDUP then
        strike(server, m.x, m.y, m.SLAM_RADIUS, m.SLAM_DAMAGE * m.power, "impact", m.SLAM_SHOVE)
        events[#events + 1] = { "hit", "slam", m.x, m.y }
        m.move, m.slamIn = nil, m.SLAM_EVERY
      end
    elseif m.move == "yawn" then
      if m.moveT >= m.YAWN then -- shut, on whoever it got
        local fx, fy = m.x + math.cos(m.facing) * 30, m.y + math.sin(m.facing) * 30
        strike(server, fx, fy, m.SNAP_REACH, m.SNAP_DAMAGE * m.power, "melee", m.SNAP_SHOVE)
        events[#events + 1] = { "hit", "snap", fx, fy }
        m.move, m.yawnIn = nil, between(m.YAWN_EVERY)
        nextAttack(m)
      end
    end
    m.breath:step(false, dt)
    return events
  end
  local threat = Dodge.threat(m.x, m.y, m.RADIUS)
  if threat then
    local ux, uy = Dodge.away(threat, m.x, m.y)
    m:walk(math.atan2(uy, ux), m:pace(), dt)
    m.running = not m.breath:winded()
    m.breath:step(m.running, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(m, server)
  if wantsHeal(m) then
    heal(m, server, events, dt, target, tx, ty, visible)
    m.breath:step(m.running, dt)
    return events
  end
  if not target then
    m.mode = "home"
    local h = m.home
    if dist2(m.x, m.y, h.x, h.y) > 40 * 40 then
      goTo(m, h.x, h.y, m:pace() * 0.7, dt)
    else
      m:turn(h.facing, dt)
    end
    m.breath:step(false, dt)
    return events
  end
  if m.sayIn <= 0 then
    m.sayIn = between(m.SAY_EVERY)
    events[#events + 1] = { "say", m.LINE.taunt[random(#m.LINE.taunt)] }
  end
  local toward = math.atan2(ty - m.y, tx - m.x)
  local d = math.sqrt(dist2(tx, ty, m.x, m.y))
  if not visible then
    m.mode = "hunt"
    goTo(m, tx, ty, m:pace(), dt)
    m.running = not m.breath:winded()
    m.breath:step(m.running, dt)
    return events
  end
  m.mode, m.goal = "fight", nil
  m:turn(toward, dt)
  if attack(m, target, d, toward) then
    m.breath:step(false, dt)
    return events
  end
  -- Keeping its distance, side-stepping; round by the grid when something's between.
  if d > m.KEEP + 100 and not Ground.clear(m.x, m.y, tx, ty) then
    goTo(m, tx, ty, m:pace(), dt)
    m.running = not m.breath:winded()
  elseif d > m.KEEP + 100 then
    m:walk(toward, m:pace(), dt)
    m.running = not m.breath:winded()
  elseif d < m.KEEP - 100 then
    m:walk(toward + math.pi + m.side * 0.5, m:pace(), dt)
  else
    if not m:walk(toward + m.side * math.pi / 2, m:pace() * 0.6, dt) or random() < dt * 0.25 then
      m.side = -m.side
    end
  end
  m.breath:step(m.running, dt)
  return events
end

return Brain
