-- Major Looz'er's brain, on the host: what he does each tick. The man
-- himself (his numbers, lines, body and nests) is major.lua; he is handed
-- in as `m`, and his numbers are read off him (m.RANGE, m.KEEP...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   nobody in his sights: he marches on the nearest player anywhere
--          (he knows his hill), round the bunkers and huts on the walking
--          grid rather than into them
--   fight  somebody he can see within RANGE (he sees all round him): he
--          keeps about KEEP between you, closing in or backing off, fires
--          three-round bursts and throws an MG nest down in front of him
--          every NEST_EVERY seconds, breath allowing
--   heal   badly hurt (bosses/heal.lua): he breaks off for the nearest
--          medkit lying within reach, still firing at whoever he can see on
--          the way, takes it and says something about it
--
-- A freeze holds him stiff; a stink sends him marching away from it. He
-- talks about his country every few seconds whatever he is doing.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- The nearest player he can see, and where they are; failing that, the
--- nearest player anywhere (he goes looking), and whether he sees them.
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

--- One round at `aim`, out of his rifle.
local function fire(m, server, aim)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    aim = aim + (random() * 2 - 1) * m.SPREAD
    weapons:serverFireFrom(server, 0, m.x + math.cos(aim) * m.MUZZLE, m.y + math.sin(aim) * m.MUZZLE, aim,
      require("src.features.weapons.guns").ak47)
  end
end

--- Towards (x, y) at `speed`: round walls on his walking grid when he has
--- one, the path worked out again when the goal moves or he gets caught.
--- True once he is there.
local function goTo(m, x, y, speed, dt)
  local g = m.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or m.time > g.replanAt or m.stuck > 0.3 then
    local corners = m.nav and m.nav:path(m.x, m.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = m.time + 1.5 }
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
  m:walk(math.atan2(c.y - m.y, c.x - m.x), speed, dt)
  return false
end

--- His trigger: bursts at whoever he can see, at (tx, ty).
local function shoot(m, server, tx, ty, dt)
  m.burstIn = m.burstIn - dt
  if m.burstIn <= 0 then
    if m.burstLeft <= 0 then
      m.burstLeft = m.BURST
    end
    fire(m, server, math.atan2(ty - m.y, tx - m.x))
    m.burstLeft = m.burstLeft - 1
    m.burstIn = m.burstLeft > 0 and m.BURST_GAP or m.BURST_EVERY
  end
end

--- An MG nest down in front of him, facing `toward`, if it is time and he
--- has the breath: the nest goes on his list and an event goes out.
local function nest(m, toward, events, dt)
  m.nestIn = m.nestIn - dt
  local Nest = m.nestKind()
  -- A nest takes breath: none while he is winded or nearly so (the timer
  -- stays run down, so it comes as soon as he has it back).
  if not (Nest and m.nestIn <= 0 and m.breath:has(m.NEST_STAMINA)) then
    return
  end
  m.nestIn = m.NEST_EVERY
  m.breath:spend(m.NEST_STAMINA)
  local out = m.NEST_OUT
  local nx, ny = m.x + math.cos(toward) * out, m.y + math.sin(toward) * out
  while out > 0 and Features.any("blocksPoint", nx, ny) do
    out = math.max(0, out - 8) -- not inside a wall: pulled back towards him
    nx, ny = m.x + math.cos(toward) * out, m.y + math.sin(toward) * out
  end
  m.nests[#m.nests + 1] = {
    x = nx, y = ny, angle = toward, placedAt = m.time, untilT = m.time + Nest.seconds, nextShot = m.time,
  }
  events[#events + 1] = { "nest", nx, ny, toward }
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(m)
  if m.medkit then
    if Heal.there(m.medkit) then
      return true
    end
    m.medkit, m.goal = nil, nil -- somebody got there first
  end
  if not Heal.wants(m.hp, m.max) or m.time < (m.healLook or 0) then
    return false
  end
  m.healLook = m.time + Heal.checkEvery
  m.medkit = Heal.find(m.x, m.y)
  m.goal = nil
  return m.medkit ~= nil
end

--- Off to the medkit, still firing at whoever he can see on the way.
local function heal(m, server, dt, events)
  local k = m.medkit
  local _, tx, ty, visible = Brain.target(m, server)
  if visible then
    m.facing = math.atan2(ty - m.y, tx - m.x)
    shoot(m, server, tx, ty, dt)
  else
    m.burstLeft = 0
    m.facing = math.atan2(k.y - m.y, k.x - m.x)
  end
  goTo(m, k.x, k.y, m:pace(), dt)
  m.running = not m.breath:winded()
  if Heal.within(k, m.x, m.y, m.RADIUS) then
    local got = Heal.take(server, k)
    m.hp = math.min(m.max, m.hp + got)
    m.medkit, m.goal = nil, nil
    if got > 0 then
      m.sayIn = m.SAY_EVERY[1] -- and a word about it, now
      events[#events + 1] = { "say", m.TALK + random(#m.lines - m.TALK) }
    end
  end
end

--- What he does this tick. Returns the events the others should hear
--- about ({ "say", index } or { "nest", x, y, angle }).
function Brain.think(m, server, dt)
  local events = {}
  m.time = m.time + dt
  m:stepNests(server)
  m.sayIn = m.sayIn - dt
  if m.sayIn <= 0 then
    m.sayIn = m.SAY_EVERY[1] + random() * (m.SAY_EVERY[2] - m.SAY_EVERY[1])
    events[#events + 1] = { "say", random(m.TALK) }
  end
  if m.frozen > 0 then
    m.frozen = m.frozen - dt
    return events
  end
  if m.panic then
    m.panic.left = m.panic.left - dt
    m.facing = math.atan2(m.y - m.panic.y, m.x - m.panic.x)
    m:walk(m.facing, m:pace(1.8), dt)
    m.running = not m.breath:winded()
    if m.panic.left <= 0 then
      m.panic = nil
    end
    return events
  end

  if wantsHeal(m) then
    m.mode = "heal"
    heal(m, server, dt, events)
    return events
  end

  local target, tx, ty, visible = Brain.target(m, server)
  if not target then
    return events
  end
  local toward = math.atan2(ty - m.y, tx - m.x)
  local d = math.sqrt(dist2(tx, ty, m.x, m.y))
  if not visible then
    -- Hunting: round the walls to wherever they are.
    m.mode, m.burstLeft = "hunt", 0
    goTo(m, tx, ty, m:pace(), dt)
    m.running = not m.breath:winded()
    local g = m.goal and m.goal.corners[m.goal.at]
    m.facing = g and math.atan2(g.y - m.y, g.x - m.x) or toward
    return events
  end
  m.mode, m.goal = "fight", nil
  m.facing = toward
  if d > m.KEEP + 40 then
    m:walk(toward, m:pace(), dt)
    m.running = not m.breath:winded()
  elseif d < m.KEEP - 80 then
    m:walk(toward + math.pi, m:pace(0.7), dt) -- backs off, still facing them
    m.running = not m.breath:winded()
  end
  shoot(m, server, tx, ty, dt)
  nest(m, toward, events, dt)
  return events
end

return Brain
