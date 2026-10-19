-- Kilowatt's brain, on the host: what he does each tick on the Roof. The
-- man himself (his numbers, lines and body) is kilowatt.lua; he is handed
-- in as `k`, and his numbers are read off him (k.CHARGE_FROM...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   nobody in his sights: he goes for the nearest player anywhere,
--          round the roof's clutter on the walking grid
--   fight  somebody he can see: he closes in and picks a move (below),
--          one at a time, each with a tell before it lands
--   heal   badly hurt (bosses/heal.lua): he breaks off for the nearest
--          medkit lying within reach and eats it
--
-- His moves, each an `action` that runs its course before he thinks again:
--
--   charge  he lowers his head (`brace`, the line on the floor set) and
--           runs a long way straight down it (`impact`, a shove); he can't
--           turn once started, and into something solid he staggers
--   slam    a hop and a slam: a cyan ring of shock rolls out from him
--           (`shock`), hurting whoever it passes
--   whip    his fist crackles and a line flickers out from it, set on
--           whoever he can see (WHIP_WIND, the tell); then lightning goes
--           down that line, into the first player still on it, and on to
--           the next player near them, up to three (`shock`). Off the
--           line, it misses
--   punch   right up against you
--   vent    after every few moves his chest cage opens and he stands
--           steaming: hits on him then count double. The window.
--
-- At half health he goes to phase 2 ("Now we're LIT!"): charges come
-- back to back, the slam rolls further, and he vents less often but for
-- longer. A freeze holds him stiff, and an ability about to land on him
-- gets him out from under it (bosses/dodge.lua). His breath
-- (bosses/stamina.lua): running at you drains it; a charge or a slam needs
-- some in him and costs it; winded he walks.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Whoever shot Saye lately (duo.lua's grudge), if they are still there:
--- him first. Else the nearest player he can see, and where they are;
--- failing that, the nearest player anywhere (he goes looking), and
--- whether he sees them.
function Brain.target(k, server)
  local g = k.grudge
  if g and k.time < g.untilT then
    local p = server.players[g.id]
    if p and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      return p, x, y, dist2(x, y, k.x, k.y) <= k.RANGE ^ 2 and Sight.clear(k.x, k.y, x, y)
    end
  end
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, k.x, k.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= k.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(k.x, k.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

--- `amount` of `dtype` on player `p`, from along `angle`.
local function hurt(server, p, amount, angle, dtype)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, amount, angle, dtype)
  end
end

--- Towards (x, y) at `speed`: round the clutter on his walking grid when
--- he has one. True once he is there.
local function goTo(k, x, y, speed, dt)
  local g = k.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or k.time > g.replanAt or k.stuck > 0.3 then
    local corners = k.nav and k.nav:path(k.x, k.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = k.time + 1.2 }
    k.goal = g
  end
  local c = g.corners[g.at]
  if dist2(k.x, k.y, c.x, c.y) < 20 * 20 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  k.facing = math.atan2(c.y - k.y, c.x - k.x)
  k:walk(k.facing, speed, dt)
  return false
end

local function act(k, name, seconds)
  k.action, k.t, k.actionTime = name, 0, seconds
end

--- One move done: count it, and every so many, vent.
local function moved(k, events, recover)
  k.moves = k.moves + 1
  if k.moves >= (k.phase2 and k.VENT_AFTER_2 or k.VENT_AFTER) then
    k.moves = 0
    act(k, "vent", k.phase2 and k.VENT_TIME_2 or k.VENT_TIME)
    events[#events + 1] = { "say", k.LINE.vent }
  else
    act(k, "recover", recover)
  end
end

--- The whip: down his line (`k.aim`) to the first player within WHIP_WIDTH
--- of it before WHIP_RANGE (or the first wall), and on from them to the
--- nearest other player within WHIP_CHAIN of the last, up to WHIP_HITS.
--- Nobody on the line, it crackles out to the end of it. The points it went through.
local function whip(k, server, events)
  local hand = k.facing + 0.5
  local hx, hy = k.x + math.cos(hand) * 30, k.y + math.sin(hand) * 30
  local pts = { hx, hy }
  local ex, ey = Sight.reach(k.x, k.y, k.aim, k.WHIP_RANGE)
  local dx, dy = ex - k.x, ey - k.y
  local len2 = math.max(1, dx * dx + dy * dy)
  local cur, nearest = nil, nil
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local along = math.max(0, math.min(1, ((x - k.x) * dx + (y - k.y) * dy) / len2))
      if dist2(x, y, k.x + dx * along, k.y + dy * along) <= k.WHIP_WIDTH ^ 2 and (not nearest or along < nearest) then
        cur, nearest = p, along
      end
    end
  end
  if not cur then
    pts[#pts + 1], pts[#pts + 2] = ex, ey
  end
  local hit = {}
  local n = 0
  while cur and n < k.WHIP_HITS do
    n = n + 1
    hit[cur] = true
    local x, y = Features.bodyPose(server, cur)
    pts[#pts + 1], pts[#pts + 2] = x, y
    hurt(server, cur, k.WHIP_DAMAGE * k.power, math.atan2(y - k.y, x - k.x), "shock")
    local nextP, bestD2 = nil, k.WHIP_CHAIN ^ 2
    for _, p in pairs(server.players) do
      if not hit[p] and Features.visible(server, p) then
        local px, py = Features.bodyPose(server, p)
        local d2 = dist2(px, py, x, y)
        if d2 <= bestD2 then
          nextP, bestD2 = p, d2
        end
      end
    end
    cur = nextP
  end
  events[#events + 1] = { "arc", pts }
end

--- The action under way, a tick of it.
local function stepAction(k, server, dt, events)
  k.t = k.t + dt
  local a = k.action
  if a == "brace" then
    if k.t >= k.actionTime then
      act(k, "charge", k.CHARGE_TIME)
      k.struck = {}
    end
  elseif a == "charge" then
    local step = k.CHARGE_SPEED * dt
    local ok = k:move(math.cos(k.aim) * step, math.sin(k.aim) * step)
    for _, p in pairs(server.players) do
      if not k.struck[p] and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, k.x, k.y) <= (k.RADIUS + 14) ^ 2 then
          k.struck[p] = true
          hurt(server, p, k.CHARGE_DAMAGE * k.power, k.aim, "impact")
          local onFoot = Features.byName["on-foot"]
          if onFoot and onFoot.serverShove then
            onFoot:serverShove(server, p, math.cos(k.aim), math.sin(k.aim), k.CHARGE_SHOVE, 0.4)
          end
          events[#events + 1] = { "thump" }
        end
      end
    end
    if not ok then
      events[#events + 1] = { "thump" } -- into the wall
      moved(k, events, k.STAGGER)
    elseif k.t >= k.actionTime then
      moved(k, events, 0.35)
    end
  elseif a == "hop" then
    k.lift = math.sin(math.min(1, k.t / k.actionTime) * math.pi) * 26
    if k.t >= k.actionTime then
      k.lift = 0
      local r = k.phase2 and k.SLAM_RADIUS_2 or k.SLAM_RADIUS
      k.rings[#k.rings + 1] = { x = k.x, y = k.y, r = 0, max = r, hit = {} }
      events[#events + 1] = { "slam", k.x, k.y, r }
      if k.meltdown then -- and the ground where he came down crackles a while
        k.patches[#k.patches + 1] = { x = k.x, y = k.y, left = k.PATCH_TIME, zapIn = 0 }
        events[#events + 1] = { "patch", k.x, k.y, k.PATCH_RADIUS, k.PATCH_TIME }
      end
      moved(k, events, 0.45)
    end
  elseif a == "whip" then
    if k.t >= k.actionTime then
      whip(k, server, events)
      moved(k, events, 0.25)
    end
  elseif a == "punch" then
    if k.t >= k.actionTime then
      local p = k.punchAt
      if p and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, k.x, k.y) <= (k.RADIUS + k.PUNCH_REACH) ^ 2 then
          hurt(server, p, k.PUNCH_DAMAGE * k.power, k.facing, "impact")
        end
      end
      events[#events + 1] = { "thump" }
      k.punchAt = nil
      act(k, "recover", 0.5)
    end
  elseif k.t >= k.actionTime then -- recover, vent
    k.action = nil
  end
end

--- His slam rings rolling out: whoever the front passes takes the shock, once.
local function stepRings(k, server, dt)
  for i = #k.rings, 1, -1 do
    local g = k.rings[i]
    g.r = g.r + k.RING_SPEED * dt
    for _, p in pairs(server.players) do
      if not g.hit[p] and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        local d = math.sqrt(dist2(x, y, g.x, g.y))
        if math.abs(d - g.r) <= 24 then
          g.hit[p] = true
          hurt(server, p, k.SLAM_DAMAGE * k.power, math.atan2(y - g.y, x - g.x), "shock")
        end
      end
    end
    if g.r >= g.max then
      table.remove(k.rings, i)
    end
  end
end

--- His meltdown patches: whoever stands in one gets a jolt every so often.
local function stepPatches(k, server, dt)
  for i = #k.patches, 1, -1 do
    local p = k.patches[i]
    p.left, p.zapIn = p.left - dt, p.zapIn - dt
    if p.zapIn <= 0 then
      p.zapIn = k.PATCH_EVERY
      for _, pl in pairs(server.players) do
        if Features.visible(server, pl) then
          local x, y = Features.bodyPose(server, pl)
          if dist2(x, y, p.x, p.y) <= k.PATCH_RADIUS ^ 2 then
            hurt(server, pl, k.PATCH_DAMAGE * k.power, math.atan2(y - p.y, x - p.x), "shock")
          end
        end
      end
    end
    if p.left <= 0 then
      table.remove(k.patches, i)
    end
  end
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(k)
  if k.medkit then
    if Heal.there(k.medkit) then
      return true
    end
    k.medkit, k.goal = nil, nil
  end
  if not Heal.wants(k.hp, k.max) or k.time < (k.healLook or 0) then
    return false
  end
  k.healLook = k.time + Heal.checkEvery
  k.medkit = Heal.find(k.x, k.y)
  k.goal = nil
  return k.medkit ~= nil
end

--- What he does this tick. Returns the events the others should hear about:
--- { "say", line }, { "slam", x, y, radius }, { "arc", points }, { "thump" }.
function Brain.think(k, server, dt)
  local events = {}
  k.time = k.time + dt
  k.running = false
  k.chargeIn = k.chargeIn - dt
  k.slamIn = k.slamIn - dt
  k.whipIn = k.whipIn - dt
  k.sayIn = k.sayIn - dt
  stepRings(k, server, dt)
  stepPatches(k, server, dt)
  if not k.phase2 and k.hp <= k.max / 2 then
    k.phase2 = true
    events[#events + 1] = { "say", k.LINE.phase2 }
  end
  if k.sayIn <= 0 then
    k.sayIn = k.SAY_EVERY[1] + random() * (k.SAY_EVERY[2] - k.SAY_EVERY[1])
    events[#events + 1] = { "say", k.LINE.taunt[random(#k.LINE.taunt)] }
  end
  if k.frozen > 0 then
    k.frozen = k.frozen - dt
    k.breath:step(false, dt)
    return events
  end
  if k.action then
    stepAction(k, server, dt, events)
    k.breath:step(false, dt)
    return events
  end
  local threat = Dodge.threat(k.x, k.y, k.RADIUS)
  if threat then
    local ux, uy = Dodge.away(threat, k.x, k.y)
    local away = math.atan2(uy, ux)
    k.facing = away
    k:walk(away, k:pace(), dt)
    k.running = not k.breath:winded()
    k.breath:step(k.running, dt)
    return events
  end
  if wantsHeal(k) then
    k.mode = "heal"
    local m = k.medkit
    goTo(k, m.x, m.y, k:pace(), dt)
    k.running = not k.breath:winded()
    if Heal.within(m, k.x, k.y, k.RADIUS) then
      local got = Heal.take(server, m)
      k.hp = math.min(k.max, k.hp + got)
      k.medkit, k.goal = nil, nil
      if got > 0 then
        events[#events + 1] = { "say", k.LINE.heal[random(#k.LINE.heal)] }
      end
    end
    k.breath:step(k.running, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(k, server)
  if not target then
    k.breath:step(false, dt)
    return events
  end
  local toward = math.atan2(ty - k.y, tx - k.x)
  local d = math.sqrt(dist2(tx, ty, k.x, k.y))
  if not visible then
    k.mode = "hunt"
    goTo(k, tx, ty, k:pace(), dt)
    k.running = not k.breath:winded()
    k.breath:step(k.running, dt)
    return events
  end
  k.mode, k.goal = "fight", nil
  k.facing = toward
  if d <= k.SLAM_REACH and k.slamIn <= 0 and k.breath:has(k.SLAM_COST) then
    k.breath:spend(k.SLAM_COST)
    k.slamIn = k.SLAM_EVERY
    act(k, "hop", k.HOP)
  elseif d >= k.CHARGE_MIN and d <= k.CHARGE_FROM and k.chargeIn <= 0 and k.breath:has(k.CHARGE_COST) then
    k.breath:spend(k.CHARGE_COST)
    k.chargeIn = k.phase2 and k.CHARGE_EVERY_2 or k.CHARGE_EVERY
    k.aim = toward -- set now: get off this line
    act(k, "brace", k.phase2 and k.BRACE_2 or k.BRACE)
  elseif d <= k.WHIP_RANGE and k.whipIn <= 0 then
    k.whipIn = k.WHIP_EVERY
    k.aim = toward -- set now: get off this line
    act(k, "whip", k.WHIP_WIND)
  elseif d <= k.RADIUS + k.PUNCH_REACH then
    k.punchAt = target
    act(k, "punch", k.PUNCH_WIND)
  else
    k:walk(toward, k:pace(), dt)
    k.running = not k.breath:winded()
  end
  k.breath:step(k.running, dt)
  return events
end

return Brain
