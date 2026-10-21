-- The Mancouchbus's brain, on the host: what he does each tick on the
-- Boulevard. The man himself (his numbers, lines and recliner) is
-- mancubus.lua; he is handed in as `m`, and his numbers are read off him
-- (m.KEEP...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   home   nobody on his patch (the spec's `zone`, the Boulevard): he rolls
--          back to his spot in front of the gate and sits there, facing
--          down the road
--   hunt   somebody on his patch he can't see: he rolls after them, round
--          things on the walking grid
--   fight  somebody he can see: he turns to face them (slowly: TURN) and
--          sits at his distance (KEEP), rolling in or backing off on his
--          treads, and lets fly
--   heal   badly hurt (bosses/heal.lua): he rolls off for the nearest
--          medkit lying within reach ("Snack break."); with somebody in
--          sight he kites there, facing them and rolling backwards or
--          forwards to it (turning off them only when it's off to his
--          side), bumping whoever comes close, and raising his arms only
--          while it is still far off (KITE_FAR)
--
-- His moves, each with a tell before it lands:
--
--   volley  the arms come up, whining (RAISE seconds), then a rocket from
--           each arm in turn at where they stand (PAIRS each, ROCKET_EVERY
--           apart), his body still coming round after them: keep moving
--   sweep   the arms come up wide (SWEEP_RAISE), then SWEEP rockets in a
--           fan from one side of his aim to the other: find the gap
--   bump    up close he leans back (BUMP_WINDUP, a ring on the road in
--           front of him) and lurches forward: whoever is in it takes it
--           (`impact`) and is knocked away
--   lads    at two thirds and a third of his health he shouts and
--           Cacodaemons come in (mancubus.lua calls them)
--
-- Under half his health (phase 2) his volleys are a pair longer and come
-- quicker, and he sweeps more. A freeze holds him stiff; an ability about
-- to land on him gets him out from under it (bosses/dodge.lua). His breath
-- (bosses/stamina.lua): rolling at full speed spends it, a volley needs
-- some in him and costs it; winded he crawls.

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

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- The nearest player on his patch he can see, and where they are; failing
--- that, the nearest on his patch at all, and whether he sees them.
function Brain.target(m, server)
  local Mancubus = require("src.features.eternal-mood.mancubus")
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if Mancubus.inZone(x, y) then
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

--- Roll for (x, y): turn for the next corner, and drive once he faces it
--- near enough. Returns true there.
local function goTo(m, x, y, speed, dt)
  local g = m.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or m.time > g.replanAt or m.stuck > 0.4 then
    local corners = m.nav and m.nav:path(m.x, m.y, x, y)
    -- No way there he fits: he holds where he is rather than grind into a wall.
    g = { x = x, y = y, corners = corners or (not m.nav and { { x = x, y = y } }), at = 1, replanAt = m.time + 1.5 }
    m.goal = g
  end
  if not g.corners then
    m:turn(math.atan2(y - m.y, x - m.x), dt)
    return false, false
  end
  local c = g.corners[g.at]
  if dist2(m.x, m.y, c.x, c.y) < 30 * 30 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  local a = math.atan2(c.y - m.y, c.x - m.x)
  m:turn(a, dt)
  if math.abs(Sight.angleDiff(a, m.facing)) < 0.6 then
    m:drive(speed, dt)
    return false, true
  end
  return false, false
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

--- He lurches forward: everyone in the ring in front of him takes it.
local function bump(m, server, events)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  local bx, by = m.x + math.cos(m.facing) * 40, m.y + math.sin(m.facing) * 40
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if dist2(x, y, bx, by) <= m.BUMP_RADIUS ^ 2 then
        local a = math.atan2(y - m.y, x - m.x)
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, m.BUMP_DAMAGE * m.power, a, "impact")
        end
        if onFoot and onFoot.serverShove then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), m.BUMP_SHOVE, 0.35)
        end
      end
    end
  end
  events[#events + 1] = { "bump", bx, by }
end

--- A rocket off launcher `arm` at angle `a`; the other arm next.
local function rocket(m, events, a)
  local x, y = m:muzzle(m.arm)
  events[#events + 1] = { "rocket", x, y, a }
  m.arm = -m.arm
  m.left = m.left - 1
end

--- At where `p` stands now, from launcher `arm`, or along his aim.
local function aimFrom(m, server, arm)
  local p = m.aimAt
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    local mx, my = m:muzzle(arm)
    return math.atan2(y - my, x - mx), math.atan2(y - m.y, x - m.x)
  end
  return m.aim, m.aim
end

--- A bump or a volley at `target` (`d` off, along `toward`), if one is due
--- and he faces them near enough; true when one starts. Kiting to a medkit
--- (`kiting`), the arms come up only while that is still far off.
local function attack(m, events, target, d, toward, kiting)
  local facing = math.abs(Sight.angleDiff(toward, m.facing))
  if d <= m.BUMP_REACH and m.bumpIn <= 0 and facing < 0.8 then
    m.move, m.moveT = "bump", 0
    return true
  end
  if m.attackIn <= 0 and d <= m.RANGE and facing < 0.35 and m.breath:has(m.VOLLEY_COST)
    and not (kiting and dist2(m.x, m.y, m.medkit.x, m.medkit.y) < m.KITE_FAR ^ 2) then
    m.breath:spend(m.VOLLEY_COST)
    m.aim, m.aimAt, m.moveT = toward, target, 0
    if random() < (m.phase2 and m.SWEEP_CHANCE_2 or m.SWEEP_CHANCE) then
      m.move = "sweepRaise"
    else
      m.move = "raise"
    end
    events[#events + 1] = { "sound", "whine" }
    return true
  end
  return false
end

--- Off to the medkit he's after, picking it up there: kiting with somebody
--- in sight (bosses/init.lua's point 7), straight for it with nobody. He
--- only rolls along where he faces, so kiting he faces them and rolls
--- forwards or backwards while the way there is near that line, and turns
--- his line onto the way (the end nearer them) when it isn't.
local function heal(m, server, events, dt, target, tx, ty, visible)
  m.mode = "heal"
  local kit = m.medkit
  local way, there = Walk.route(m, m.nav, kit.x, kit.y, m.time)
  if there then -- at the grid's last corner, not yet on the kit: the last step straight at it
    way = math.atan2(kit.y - m.y, kit.x - m.x)
  end
  if way == nil and not there then -- no way there he fits: he fights on, and looks again in a while
    m.medkit, m.route, m.healLook = nil, nil, m.time + Heal.noWay
    return false
  end
  if visible then
    local toward = math.atan2(ty - m.y, tx - m.x)
    local face = toward
    if math.abs(math.sin(Sight.angleDiff(way, toward))) > math.sin(m.KITE_ALONG) then
      face = math.abs(Sight.angleDiff(way, toward)) < math.pi / 2 and way or way + math.pi
    end
    m:turn(face, dt)
    if attack(m, events, target, math.sqrt(dist2(tx, ty, m.x, m.y)), toward, true) then
      return
    end
    -- On his line near enough (a little slack, for how slowly he comes round): forwards or backwards along it.
    local off = Sight.angleDiff(way, m.facing)
    local onLine = math.abs(math.sin(off)) <= math.sin(m.KITE_ALONG + 0.1)
    if onLine and math.cos(off) > 0 then
      m:drive(m:pace(), dt)
    elseif onLine then
      m:drive(-m:pace() * m.REVERSE, dt)
    end
    m.running = onLine and math.cos(off) > 0 and not m.breath:winded()
  else
    local _, driving = goTo(m, kit.x, kit.y, m:pace(), dt)
    m.running = driving and not m.breath:winded()
  end
  if Heal.within(kit, m.x, m.y, m.RADIUS) then
    local got = Heal.take(server, kit)
    m.hp = math.min(m.max, m.hp + got)
    m.medkit, m.goal, m.route = nil, nil, nil
    if got > 0 then
      events[#events + 1] = { "say", m.LINE.heal }
    end
  end
end

local function nextAttack(m)
  m.attackIn = between(m.phase2 and m.VOLLEY_EVERY_2 or m.VOLLEY_EVERY)
end

--- What he does this tick. Returns the events the others should hear
--- about: { "say", line }, { "rocket", x, y, angle }, { "bump", x, y },
--- { "sound", name }, { "call" }.
function Brain.think(m, server, dt)
  local events = {}
  m.time = m.time + dt
  m.running = false
  m.bumpIn = m.bumpIn - dt
  m.attackIn = m.attackIn - dt
  m.sayIn = m.sayIn - dt
  if not m.phase2 and m.hp <= m.max / 2 then
    m.phase2 = true
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
  if m.move then -- a move under way: he sits and does it
    m.moveT = m.moveT + dt
    if m.move == "bump" and m.moveT >= m.BUMP_WINDUP then
      bump(m, server, events)
      m.move, m.bumpIn = nil, m.BUMP_EVERY
    elseif m.move == "raise" and m.moveT >= m.RAISE then
      m.move, m.moveT, m.rocketIn = "volley", 0, 0
      m.left = (m.PAIRS + (m.phase2 and 1 or 0)) * 2
    elseif m.move == "sweepRaise" and m.moveT >= m.SWEEP_RAISE then
      m.move, m.moveT, m.rocketIn, m.left = "sweep", 0, 0, m.SWEEP
      m.sweepDir = random() < 0.5 and 1 or -1
    elseif m.move == "volley" then
      local a, body = aimFrom(m, server, m.arm)
      m:turn(body, dt) -- his body comes round after them, slowly
      m.aim = body
      m.rocketIn = m.rocketIn - dt
      if m.rocketIn <= 0 then
        m.rocketIn = m.ROCKET_EVERY
        rocket(m, events, a + (random() - 0.5) * 0.08)
      end
      if m.left <= 0 then
        m.move = nil
        nextAttack(m)
      end
    elseif m.move == "sweep" then
      m.rocketIn = m.rocketIn - dt
      if m.rocketIn <= 0 then
        m.rocketIn = m.SWEEP_EVERY
        local k = (m.SWEEP - m.left) / (m.SWEEP - 1) -- 0 to 1 across the fan
        rocket(m, events, m.aim + m.sweepDir * m.SWEEP_ARC * (k * 2 - 1))
      end
      if m.left <= 0 then
        m.move = nil
        nextAttack(m)
      end
    end
    m.breath:step(false, dt)
    return events
  end
  local threat = Dodge.threat(m.x, m.y, m.RADIUS)
  if threat then
    local ux, uy = Dodge.away(threat, m.x, m.y)
    m:slide(math.atan2(uy, ux), m:pace(), dt)
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
    -- Nobody on his patch: back to his spot in front of the gate, facing down the road.
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
    local _, driving = goTo(m, tx, ty, m:pace(), dt)
    m.running = driving and not m.breath:winded()
    m.breath:step(m.running, dt)
    return events
  end
  m.mode = "fight"
  if m.stuck > 0.3 then
    m.detour = m.time + m.DETOUR
  end
  -- Round whatever his recliner won't get past (or has caught on) by the walking grid, turning for its corners
  -- instead of for them.
  local around = d > m.KEEP + 120 and (m.time < (m.detour or 0) or not m:straight(tx, ty))
  if around then
    local _, driving = goTo(m, tx, ty, m:pace(), dt)
    m.running = driving and not m.breath:winded()
  else
    m.goal = nil -- a way he was on is stale once he's off it
    m:turn(toward, dt)
  end
  if attack(m, events, target, d, toward) then
    m.breath:step(false, dt)
    return events
  end
  local facing = math.abs(Sight.angleDiff(toward, m.facing))
  -- Sitting at his distance: rolling in if they are far, backing off if
  -- they are near, as long as he faces them near enough to.
  if facing < 0.6 and not around then
    if d > m.KEEP + 120 then
      m:drive(m:pace(), dt)
      m.running = not m.breath:winded()
    elseif d < m.KEEP - 120 then
      m:drive(-m:pace() * m.REVERSE, dt)
    end
  end
  m.breath:step(m.running, dt)
  return events
end

return Brain
