-- General Volt's brain, on the host: what he does each tick in Noodle
-- Square. The man himself (his numbers, lines and body) is volt.lua; he is
-- handed in as `v`, and his numbers are read off him (v.BOLT_RANGE...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   nobody in his sights: he goes for the nearest player anywhere,
--          round the stalls on the walking grid
--   fight  somebody he can see: he keeps his distance (KEEP), closing in or
--          backing off, and works through his moves (below)
--   heal   badly hurt (bosses/heal.lua): he breaks off for the nearest
--          medkit lying within reach
--
-- His moves, each with a tell before it lands:
--
--   bolt     he raises his hand and a crackling line marks where the bolt
--            will go (AIM seconds, following them for the first part, then
--            set); then it strikes down the line, through whoever is on it
--            (`shock`, enough to stun). Phase 2: two at once, forked.
--   grenade  he lobs a lightning grenade at where they stand: a ring on the
--            ground shows where it will come down; it lands as a crackling
--            field that zaps whoever stands in it (`shock`) for a few
--            seconds. Phase 2: two at once.
--   backup   at three quarters, half and a quarter of his health he shouts
--            for the Static, and a pack runs in from the lanes (volt.lua
--            sends them).
--
-- A freeze holds him stiff; an ability about to land on him gets him out
-- from under it (bosses/dodge.lua). His breath (bosses/stamina.lua): moving
-- briskly spends it, a grenade needs some in him and costs it; winded he
-- walks.

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
function Brain.target(v, server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, v.x, v.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= v.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(v.x, v.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

local function hurt(server, p, amount, angle)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, amount, angle, "shock")
  end
end

local function goTo(v, x, y, speed, dt)
  local g = v.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or v.time > g.replanAt or v.stuck > 0.3 then
    local corners = v.nav and v.nav:path(v.x, v.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = v.time + 1.2 }
    v.goal = g
  end
  local c = g.corners[g.at]
  if dist2(v.x, v.y, c.x, c.y) < 18 * 18 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  v.facing = math.atan2(c.y - v.y, c.x - v.x)
  v:walk(v.facing, speed, dt)
  return false
end

local function wantsHeal(v)
  if v.medkit then
    if Heal.there(v.medkit) then
      return true
    end
    v.medkit, v.goal = nil, nil
  end
  if not Heal.wants(v.hp, v.max) or v.time < (v.healLook or 0) then
    return false
  end
  v.healLook = v.time + Heal.checkEvery
  v.medkit = Heal.find(v.x, v.y)
  v.goal = nil
  return v.medkit ~= nil
end

--- The bolt goes: down each line (one, or two forked), every player within
--- BOLT_WIDTH of it to its end (or the first wall) takes it. The lines it
--- went down, for every screen.
local function strike(v, server, events)
  local aims = v.phase2 and { v.aim - v.FORK, v.aim + v.FORK } or { v.aim }
  for _, a in ipairs(aims) do
    local ex, ey = Sight.reach(v.x, v.y, a, v.BOLT_RANGE)
    local dx, dy = ex - v.x, ey - v.y
    local len2 = math.max(1, dx * dx + dy * dy)
    for _, p in pairs(server.players) do
      if Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        local k = math.max(0, math.min(1, ((x - v.x) * dx + (y - v.y) * dy) / len2))
        if dist2(x, y, v.x + dx * k, v.y + dy * k) <= v.BOLT_WIDTH ^ 2 then
          hurt(server, p, v.BOLT_DAMAGE * v.power, a)
        end
      end
    end
    events[#events + 1] = { "bolt", v.x, v.y, ex, ey }
  end
end

--- His grenades in the air and on the ground.
local function stepGrenades(v, server, dt, events)
  for i = #v.grenades, 1, -1 do
    local g = v.grenades[i]
    if g.flying > 0 then
      g.flying = g.flying - dt
      if g.flying <= 0 then
        g.left, g.zapIn = v.FIELD_TIME, 0
        events[#events + 1] = { "field", g.x, g.y }
      end
    else
      g.left, g.zapIn = g.left - dt, g.zapIn - dt
      if g.zapIn <= 0 then
        g.zapIn = v.FIELD_EVERY
        for _, p in pairs(server.players) do
          if Features.visible(server, p) then
            local x, y = Features.bodyPose(server, p)
            if dist2(x, y, g.x, g.y) <= v.FIELD_RADIUS ^ 2 then
              local first = not g.hit[p]
              g.hit[p] = true
              hurt(server, p, (first and v.FIELD_FIRST or v.FIELD_DAMAGE) * v.power, math.atan2(y - g.y, x - g.x))
            end
          end
        end
      end
      if g.left <= 0 then
        table.remove(v.grenades, i)
      end
    end
  end
end

--- A grenade at (x, y) (off a little each when he throws two).
local function throw(v, x, y, events)
  local n = v.phase2 and 2 or 1
  for k = 1, n do
    local off = n == 1 and 0 or (k == 1 and -1 or 1) * v.FIELD_RADIUS * 0.9
    local a = math.atan2(y - v.y, x - v.x) + math.pi / 2
    local gx, gy = x + math.cos(a) * off, y + math.sin(a) * off
    v.grenades[#v.grenades + 1] = { x = gx, y = gy, flying = v.FLIGHT, hit = {} }
    events[#events + 1] = { "lob", v.x, v.y, gx, gy }
  end
end

--- What he does this tick. Returns the events the others should hear
--- about: { "say", line }, { "bolt", x0, y0, x1, y1 }, { "lob", x0, y0, x1,
--- y1 }, { "field", x, y }, { "backup" }.
function Brain.think(v, server, dt)
  local events = {}
  v.time = v.time + dt
  v.running = false
  v.boltIn = v.boltIn - dt
  v.lobIn = v.lobIn - dt
  v.sayIn = v.sayIn - dt
  stepGrenades(v, server, dt, events)
  if not v.phase2 and v.hp <= v.max / 2 then
    v.phase2 = true
    events[#events + 1] = { "say", v.LINE.phase2 }
  end
  -- Backup at each mark he drops past.
  local mark = v.BACKUP_AT[v.backups + 1]
  if mark and v.hp <= v.max * mark then
    v.backups = v.backups + 1
    events[#events + 1] = { "backup" }
    events[#events + 1] = { "say", v.LINE.backup[random(#v.LINE.backup)] }
  end
  if v.sayIn <= 0 then
    v.sayIn = v.SAY_EVERY[1] + random() * (v.SAY_EVERY[2] - v.SAY_EVERY[1])
    events[#events + 1] = { "say", v.LINE.taunt[random(#v.LINE.taunt)] }
  end
  if v.frozen > 0 then
    v.frozen = v.frozen - dt
    v.breath:step(false, dt)
    return events
  end
  if v.aiming then -- the line up, he holds still
    v.aimT = v.aimT + dt
    local hold = v.phase2 and v.AIM_2 or v.AIM
    if v.aimT < hold - v.SET then -- following them for the first part
      local p = v.aimAt
      if p and Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        v.aim = math.atan2(y - v.y, x - v.x)
      end
    end
    if v.aimT >= hold then
      strike(v, server, events)
      v.aiming, v.aimAt = false, nil
      v.boltIn = v.phase2 and v.BOLT_EVERY_2 or v.BOLT_EVERY
    end
    v.breath:step(false, dt)
    return events
  end
  local threat = Dodge.threat(v.x, v.y, v.RADIUS)
  if threat then
    local ux, uy = Dodge.away(threat, v.x, v.y)
    v.facing = math.atan2(uy, ux)
    v:walk(v.facing, v:pace(), dt)
    v.running = not v.breath:winded()
    v.breath:step(v.running, dt)
    return events
  end
  if wantsHeal(v) then
    v.mode = "heal"
    local m = v.medkit
    goTo(v, m.x, m.y, v:pace(), dt)
    v.running = not v.breath:winded()
    if Heal.within(m, v.x, v.y, v.RADIUS) then
      local got = Heal.take(server, m)
      v.hp = math.min(v.max, v.hp + got)
      v.medkit, v.goal = nil, nil
      if got > 0 then
        events[#events + 1] = { "say", v.LINE.heal }
      end
    end
    v.breath:step(v.running, dt)
    return events
  end
  local target, tx, ty, visible = Brain.target(v, server)
  if not target then
    v.breath:step(false, dt)
    return events
  end
  local toward = math.atan2(ty - v.y, tx - v.x)
  local d = math.sqrt(dist2(tx, ty, v.x, v.y))
  if not visible then
    v.mode = "hunt"
    goTo(v, tx, ty, v:pace(), dt)
    v.running = not v.breath:winded()
    v.breath:step(v.running, dt)
    return events
  end
  v.mode, v.goal = "fight", nil
  v.facing = toward
  if v.boltIn <= 0 and d <= v.BOLT_RANGE then
    v.aiming, v.aimT, v.aim, v.aimAt = true, 0, toward, target
    v.breath:step(false, dt)
    return events
  end
  if v.lobIn <= 0 and d <= v.LOB_RANGE and v.breath:has(v.LOB_COST) then
    v.breath:spend(v.LOB_COST)
    v.lobIn = v.LOB_EVERY
    throw(v, tx, ty, events)
  end
  if d > v.KEEP + 60 then
    v:walk(toward, v:pace(), dt)
    v.running = not v.breath:winded()
  elseif d < v.KEEP - 80 then
    v:walk(toward + math.pi + v.side, v:pace(), dt)
    v.running = not v.breath:winded()
    if v.stuck > 0.5 then
      v.side = -v.side
    end
  end
  v.facing = toward
  v.breath:step(v.running, dt)
  return events
end

return Brain
