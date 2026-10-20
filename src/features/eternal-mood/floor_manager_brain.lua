-- The Floor Manager's brain, on the host: what he does each tick in the
-- Hangar. The man himself (his numbers, lines and walker) is
-- floor_manager.lua; he is handed in as `m`, and his numbers are read off
-- him (m.PLASMA_RANGE...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   nobody in his sights: he walks for the nearest player anywhere,
--          round the crates on the walking grid
--   fight  somebody he can see: with his cannon he keeps his distance
--          (KEEP), side-stepping in his chair; with it shot off he
--          closes in to stomp
--   heal   badly hurt (bosses/heal.lua): he breaks off for the nearest
--          medkit lying within reach ("statutory break")
--
-- His moves, each with a tell before it lands:
--
--   plasma  the cannon charges (CHARGE seconds, glowing green), then a stream
--           of plasma bolts goes out (STREAM bolts, STREAM_EVERY apart),
--           its aim following them slowly (STREAM_TURN): keep moving across
--           it. Phase 2 (under half his health): three streams in a fan.
--           Not once the cannon is shot off (floor_manager.lua's `cannon`).
--   stomp   up close the legs rear up (STOMP_WINDUP, a ring on the floor
--           showing the reach) and come down: whoever is in the ring takes
--           it (`impact`) and is shoved away
--   meeting at two thirds and a third of his health he calls a quick meeting:
--           staffers come in through the Hangar's doorways (floor_manager.lua
--           sends them)
--
-- A freeze holds him stiff; an ability about to land on him gets him out
-- from under it (bosses/dodge.lua). His breath (bosses/stamina.lua): walking
-- briskly spends it, a stream needs some in him and costs it; winded he
-- picks his way along.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The nearest player he can see, and where they are; failing that, the
--- nearest player anywhere, and whether he sees them.
function Brain.target(m, server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, m.x, m.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= m.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(m.x, m.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
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
  if dist2(m.x, m.y, c.x, c.y) < 20 * 20 then
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

--- The legs come down: everyone in the ring round him takes it.
local function stomp(m, server, events)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if dist2(x, y, m.x, m.y) <= m.STOMP_RADIUS ^ 2 then
        local a = math.atan2(y - m.y, x - m.x)
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, m.STOMP_DAMAGE * m.power, a, "impact")
        end
        if onFoot and onFoot.serverShove then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), m.STOMP_SHOVE, 0.35)
        end
      end
    end
  end
  events[#events + 1] = { "stomp", m.x, m.y }
end

--- One round of the stream: a bolt down each line (one, or three in a fan).
local function bolt(m, events)
  local x, y = m:muzzle()
  local aims = m.phase2 and { m.aim - m.FAN, m.aim, m.aim + m.FAN } or { m.aim }
  for _, a in ipairs(aims) do
    events[#events + 1] = { "bolt", x, y, a }
  end
  m.left = m.left - 1
end

--- What he does this tick. Returns the events the others should hear
--- about: { "say", line }, { "stomp", x, y }, { "bolt", x, y, angle },
--- { "sound", name }, { "meeting" }.
function Brain.think(m, server, dt)
  local events = {}
  m.time = m.time + dt
  m.running = false
  m.stompIn = m.stompIn - dt
  m.plasmaIn = m.plasmaIn - dt
  m.sayIn = m.sayIn - dt
  if not m.phase2 and m.hp <= m.max / 2 then
    m.phase2 = true
    events[#events + 1] = { "say", m.LINE.phase2 }
  end
  local mark = m.MEETING_AT[m.meetings + 1]
  if mark and m.hp <= m.max * mark then
    m.meetings = m.meetings + 1
    events[#events + 1] = { "meeting" }
    events[#events + 1] = { "say", m.LINE.meeting[random(#m.LINE.meeting)] }
  end
  if m.sayIn <= 0 then
    m.sayIn = m.SAY_EVERY[1] + random() * (m.SAY_EVERY[2] - m.SAY_EVERY[1])
    events[#events + 1] = { "say", m.LINE.taunt[random(#m.LINE.taunt)] }
  end
  if m.frozen > 0 then
    m.frozen = m.frozen - dt
    m.breath:step(false, dt)
    return events
  end
  if m.move then -- a move under way: he stands and does it
    m.moveT = m.moveT + dt
    if m.move == "stomp" and m.moveT >= m.STOMP_WINDUP then
      stomp(m, server, events)
      m.move, m.stompIn = nil, m.STOMP_EVERY
    elseif m.move == "charge" and (not m.cannon or m.moveT >= m.CHARGE) then
      m.move, m.moveT, m.left, m.boltIn = m.cannon and "stream" or nil, 0, m.STREAM, 0
    elseif m.move == "stream" then
      if not m.cannon or m.left <= 0 then
        m.move, m.plasmaIn = nil, m.phase2 and m.PLASMA_EVERY_2 or m.PLASMA_EVERY
      else
        local p = m.aimAt
        if p and Features.visible(server, p) then -- the aim drags after them
          local x, y = Features.bodyPose(server, p)
          local want = math.atan2(y - m.y, x - m.x)
          local d = Sight.angleDiff(want, m.aim)
          local step = m.STREAM_TURN * dt
          m.aim = m.aim + math.max(-step, math.min(step, d))
        end
        m.facing = m.aim
        m.boltIn = m.boltIn - dt
        if m.boltIn <= 0 then
          m.boltIn = m.STREAM_EVERY
          bolt(m, events)
        end
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
  if wantsHeal(m) then
    m.mode = "heal"
    local kit = m.medkit
    goTo(m, kit.x, kit.y, m:pace(), dt)
    m.running = not m.breath:winded()
    if Heal.within(kit, m.x, m.y, m.RADIUS) then
      local got = Heal.take(server, kit)
      m.hp = math.min(m.max, m.hp + got)
      m.medkit, m.goal = nil, nil
      if got > 0 then
        events[#events + 1] = { "say", m.LINE.heal }
      end
    end
    m.breath:step(m.running, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(m, server)
  if not target then
    m.breath:step(false, dt)
    return events
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
  if d <= m.STOMP_REACH and m.stompIn <= 0 then
    m.move, m.moveT = "stomp", 0
    events[#events + 1] = { "sound", "rear" }
    m.breath:step(false, dt)
    return events
  end
  if m.cannon and m.plasmaIn <= 0 and d <= m.PLASMA_RANGE and m.breath:has(m.PLASMA_COST)
    and math.abs(Sight.angleDiff(toward, m.facing)) < 0.25 then
    m.breath:spend(m.PLASMA_COST)
    m.move, m.moveT, m.aim, m.aimAt = "charge", 0, toward, target
    events[#events + 1] = { "sound", "charge" }
    m.breath:step(false, dt)
    return events
  end
  -- Placing himself: off at range with the cannon, side-stepping; right in
  -- without it.
  local keep = m.cannon and m.KEEP or 0
  local speed = m.cannon and m:pace() or m:pace() * m.RAGE
  if d > keep + 80 then
    m:walk(toward, speed, dt)
    m.running = not m.breath:winded()
  elseif d < keep - 80 then
    m:walk(toward + math.pi + m.side * 0.6, speed, dt)
    m.running = not m.breath:winded()
  else
    m:walk(toward + m.side * math.pi / 2, speed * 0.6, dt) -- crabwise, the way spiders do
  end
  m.sideIn = m.sideIn - dt
  if m.stuck > 0.4 or m.sideIn <= 0 then
    m.side, m.stuck = -m.side, 0
    m.sideIn = m.SIDE_EVERY[1] + random() * (m.SIDE_EVERY[2] - m.SIDE_EVERY[1])
  end
  m.breath:step(m.running, dt)
  return events
end

return Brain
