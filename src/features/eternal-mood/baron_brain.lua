-- The Baron of Heck's brain, on the host: what he does each tick in the
-- Crucible. The man himself (his numbers, lines and the key) is baron.lua;
-- he is handed in as `m`, and his numbers are read off him (m.KEEP...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   home   nobody in the Crucible (the spec's `zone`): back to his spot on
--          the ring, facing the south bridge
--   hunt   somebody in the Crucible he can't see: after them, on the
--          walking grid
--   fight  somebody he can see: he keeps about KEEP off and circles, and
--          lets fly
--   heal   badly hurt (bosses/heal.lua): off for the nearest medkit
--          lying within reach ("...A MOMENT.")
--
-- His moves, each with a tell before it lands:
--
--   pairs   green fire burns up in both hands (WINDUP), then a fireball
--           from each, one at where you stand and one where you're going
--           (LEAD seconds on); phase 2: three pairs, PAIR_EVERY apart
--   charge  horns down (CHARGE_WINDUP, a red lane on the floor showing
--           where), then he runs straight down it (CHARGE_SPEED, up to
--           CHARGE_FOR): whoever he hits takes it (`impact`) and goes
--           flying, and he stops; into a wall or the moat's edge he
--           staggers and stands stunned (STUN), wide open
--   claw    up close (CLAW_REACH) his arm goes back (CLAW_WINDUP, his reach
--           shown) and swipes everyone in front of him (`melee`)
--   roar    at two thirds and a third of his health: everyone near him is
--           thrown back, and imps climb out of the lava (baron.lua calls
--           them)
--
-- A freeze holds him stiff; an ability about to land on him gets him out
-- from under it (bosses/dodge.lua). His breath (bosses/stamina.lua): a
-- throw or a charge needs some in him and costs it; winded he walks.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- The nearest player in the Crucible he can see, and where they are;
--- failing that, the nearest in it at all, and whether he sees them.
function Brain.target(m, server)
  local Baron = require("src.features.eternal-mood.baron")
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if Baron.inZone(x, y) then
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

--- Everyone within `radius` of (x, y) and, if `arc`, within `arc` radians
--- of `facing` from (x, y): each takes `damage` of `dtype` and is shoved
--- `shove` px away. Returns how many it caught.
local function strike(server, x, y, radius, facing, arc, damage, dtype, shove)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  local caught = 0
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local a = math.atan2(py - y, px - x)
      if dist2(px, py, x, y) <= radius * radius and (not arc or math.abs(Sight.angleDiff(a, facing)) <= arc) then
        caught = caught + 1
        if weapons and weapons.serverDamage and damage > 0 then
          weapons:serverDamage(server, p, nil, damage, a, dtype)
        end
        if onFoot and onFoot.serverShove and shove > 0 then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), shove, 0.35)
        end
      end
    end
  end
  return caught
end

--- A pair: a fireball from each hand, the left at where `p` stands, the
--- right where they're going (by how they've moved since the last look).
local function pair(m, server, events)
  local p = m.aimAt
  local tx, ty = m.lastX, m.lastY
  local vx, vy = 0, 0
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    if m.seenX then
      local dt = math.max(0.05, m.time - m.seenT)
      vx, vy = (x - m.seenX) / dt, (y - m.seenY) / dt
    end
    tx, ty = x, y
  end
  if not tx then
    return
  end
  local lx, ly = m:hand(-1)
  events[#events + 1] = { "fireball", lx, ly, math.atan2(ty - ly, tx - lx) }
  local rx, ry = m:hand(1)
  local px, py = tx + vx * m.LEAD, ty + vy * m.LEAD
  events[#events + 1] = { "fireball", rx, ry, math.atan2(py - ry, px - rx) }
  m.aim = math.atan2(ty - m.y, tx - m.x)
end

local function nextAttack(m)
  m.attackIn = between(m.phase2 and m.THROW_EVERY_2 or m.THROW_EVERY)
end

--- What he does this tick. Returns the events the others should hear
--- about: { "say", line }, { "fireball", x, y, angle }, { "hit", name, x, y }, { "imps" }.
function Brain.think(m, server, dt)
  local events = {}
  m.time = m.time + dt
  m.running = false
  m.attackIn = m.attackIn - dt
  m.clawIn = m.clawIn - dt
  m.sayIn = m.sayIn - dt
  if not m.phase2 and m.hp <= m.max / 2 then
    m.phase2 = true
    events[#events + 1] = { "say", m.LINE.phase2 }
  end
  if m.frozen > 0 then
    m.frozen = m.frozen - dt
    m.breath:step(false, dt)
    return events
  end
  local mark = m.ROAR_AT[m.roars + 1]
  if mark and m.hp <= m.max * mark and m.move ~= "roar" and m.move ~= "charge" then
    m.roars = m.roars + 1
    m.move, m.moveT = "roar", 0
    events[#events + 1] = { "say", m.LINE.roar }
  end
  if m.move then -- a move under way
    m.moveT = m.moveT + dt
    if m.move == "roar" then
      if m.moveT >= 0.25 and not m.roared then
        m.roared = true
        strike(server, m.x, m.y, m.ROAR_RADIUS, nil, nil, 0, "impact", m.ROAR_SHOVE)
        events[#events + 1] = { "imps" }
        events[#events + 1] = { "hit", "roar", m.x, m.y }
      end
      if m.moveT >= m.ROAR then
        m.move, m.roared = nil, nil
        nextAttack(m)
      end
    elseif m.move == "windup" then
      local p = m.aimAt
      if p and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        m:turn(math.atan2(y - m.y, x - m.x), dt)
        m.seenX, m.seenY, m.seenT, m.lastX, m.lastY = x, y, m.time, x, y
      end
      if m.moveT >= m.WINDUP then
        m.move, m.moveT, m.pairIn = "throw", 0, 0
        m.left = m.phase2 and m.PAIRS_2 or m.PAIRS
      end
    elseif m.move == "throw" then
      m.pairIn = m.pairIn - dt
      if m.pairIn <= 0 then
        m.pairIn = m.PAIR_EVERY
        pair(m, server, events)
        m.left = m.left - 1
        local p = m.aimAt -- for the next pair's lead
        if p and Features.visible(server, p) then
          m.seenX, m.seenY = Features.bodyPose(server, p)
          m.seenT = m.time
        end
      end
      if m.left <= 0 and m.pairIn > m.PAIR_EVERY * 0.5 then
        m.move = nil
        nextAttack(m)
      end
    elseif m.move == "lower" then
      if m.moveT >= m.CHARGE_WINDUP then
        m.move, m.moveT = "charge", 0
      end
    elseif m.move == "charge" then
      local before = { x = m.x, y = m.y }
      local moved = m:walk(m.aim, m.CHARGE_SPEED, dt)
      local slid = dist2(before.x, before.y, m.x, m.y) < (m.CHARGE_SPEED * dt * 0.6) ^ 2
      m.facing = m.aim
      if strike(server, m.x, m.y, m.CHARGE_HIT, nil, nil, m.CHARGE_DAMAGE, "impact", m.CHARGE_SHOVE) > 0 then
        events[#events + 1] = { "hit", "charge", m.x, m.y }
        m.move = nil
        nextAttack(m)
      elseif not moved or slid then -- into something: horns first
        events[#events + 1] = { "hit", "wall", m.x + math.cos(m.aim) * m.RADIUS, m.y + math.sin(m.aim) * m.RADIUS }
        m.move, m.moveT = "stunned", 0
      elseif m.moveT >= m.CHARGE_FOR then
        m.move = nil
        nextAttack(m)
      end
    elseif m.move == "stunned" then
      if m.moveT >= m.STUN then
        m.move = nil
        nextAttack(m)
      end
    elseif m.move == "claw" then
      if m.moveT >= m.CLAW_WINDUP then
        if strike(server, m.x, m.y, m.CLAW_REACH, m.facing, m.CLAW_ARC, m.CLAW_DAMAGE, "melee", 60) > 0 then
          events[#events + 1] = { "hit", "claw", m.x + math.cos(m.facing) * 40, m.y + math.sin(m.facing) * 40 }
        end
        m.move, m.clawIn = nil, m.CLAW_EVERY
      end
    end
    m.breath:step(m.move == "charge", dt)
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
    m.mode = "home"
    local h = m.home
    if dist2(m.x, m.y, h.x, h.y) > 30 * 30 then
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
  local facing = math.abs(Sight.angleDiff(toward, m.facing))
  if d <= m.CLAW_REACH and m.clawIn <= 0 then
    m.move, m.moveT = "claw", 0
    m.breath:step(false, dt)
    return events
  end
  if m.attackIn <= 0 and facing < 0.4 then
    local chance = m.phase2 and m.CHARGE_CHANCE_2 or m.CHARGE_CHANCE
    if d >= m.CHARGE_MIN and random() < chance and m.breath:has(m.CHARGE_COST) then
      m.breath:spend(m.CHARGE_COST)
      m.move, m.moveT, m.aim = "lower", 0, toward
      m.breath:step(false, dt)
      return events
    elseif m.breath:has(m.THROW_COST) then
      m.breath:spend(m.THROW_COST)
      m.move, m.moveT, m.aimAt = "windup", 0, target
      m.seenX, m.seenY, m.seenT, m.lastX, m.lastY = tx, ty, m.time, tx, ty
      m.breath:step(false, dt)
      return events
    end
  end
  -- Placing himself: at his distance, circling; round by the bridges when
  -- the lava is between them.
  if d > m.KEEP + 80 and not Ground.clear(m.x, m.y, tx, ty) then
    goTo(m, tx, ty, m:pace(), dt)
    m.running = not m.breath:winded()
  elseif d > m.KEEP + 80 then
    m:walk(toward, m:pace(), dt)
    m.running = not m.breath:winded()
  elseif d < m.KEEP - 80 then
    m:walk(toward + math.pi, m:pace() * 0.7, dt)
  else
    m.side = m.side or 1
    if not m:walk(toward + m.side * math.pi / 2, m:pace() * 0.5, dt) or random() < dt * 0.3 then
      m.side = -m.side
    end
  end
  m.breath:step(m.running, dt)
  return events
end

return Brain
