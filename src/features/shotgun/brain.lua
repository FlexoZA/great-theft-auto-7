-- Shotgun's brain, on the host: what he does each tick. The man himself
-- (his numbers, lines, eyes and legs) is boss.lua; he is handed in as `b`
-- and his numbers are read off him (b.RANGE, b.WARN...).
--
-- How he fights (and the order things cut in, last first):
--   * Hidden (his chicken), he walks to the spot he picked and does
--     nothing else: a new perch, or a medkit.
--   * Somebody within EVADE of him: he vanishes if he can and goes
--     somewhere else; if he can't, he backs away from them firing his pistol.
--   * Back where everyone can see him, he is gone again as soon as he can
--     be, unless he is in the middle of a shot.
--   * Otherwise he draws a bead on the nearest player he can see: WARN
--     seconds marked, his aim leading them until LOCK before the shot,
--     then the round goes where the aim was. FIVE rounds, then RELOAD.
--     Nobody in sight, he goes along the lip towards the nearest player.
--   * Badly hurt (bosses/heal.lua), he goes for the nearest medkit lying
--     within reach: out of sight first if his chicken is back, round the
--     bluff on his walking grid, and takes it (a word about it, if anyone
--     can see him).
-- A freeze holds him still; a stink sends him off away from it.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")
local Heal = require("src.features.bosses.heal")

local Brain = {}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Towards (x, y) at `speed`, round the bluff on his walking grid. True
--- once he is there.
local function goTo(b, x, y, speed, dt)
  local g = b.path
  if not g or dist2(g.x, g.y, x, y) > 60 * 60 or b.time > g.replanAt then
    local corners = b.nav and b.nav:path(b.x, b.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = b.time + 1.5 }
    b.path = g
  end
  local c = g.corners[g.at]
  if dist2(b.x, b.y, c.x, c.y) < 16 * 16 then
    if g.at >= #g.corners then
      return true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
  end
  b.facing = math.atan2(c.y - b.y, c.x - b.x)
  b:walk(b.facing, speed, dt)
  return false
end

--- Should he go for a medkit now? Looks once a second while he is hurt.
local function wantsHeal(b)
  if b.medkit then
    if Heal.there(b.medkit) then
      return true
    end
    b.medkit, b.path = nil, nil -- somebody got there first
  end
  if not Heal.wants(b.hp, b.max) or b.time < (b.healLook or 0) then
    return false
  end
  b.healLook = b.time + Heal.checkEvery
  b.medkit, b.path = Heal.find(b.x, b.y), nil
  return b.medkit ~= nil
end

--- Everyone he could go after: { p, x, y, d2 }, nearest first. `seeing`
--- keeps only those in range and in sight.
local function players(b, server, map, seeing)
  local list = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = (x - b.x) ^ 2 + (y - b.y) ^ 2
      if not seeing or (d2 <= b.RANGE ^ 2 and b.clear(map, b.x, b.y, x, y)) then
        list[#list + 1] = { p = p, x = x, y = y, d2 = d2 }
      end
    end
  end
  table.sort(list, function(e, f)
    return e.d2 < f.d2
  end)
  return list
end

--- A new spot to shoot from. With somebody up on the plateau, the one
--- furthest from whoever is nearest to it; otherwise one on the lip in
--- range of somebody below, at random, or the lip spot nearest them.
local function pickPerch(b, server, map)
  local climbers, below = {}, {}
  for _, e in ipairs(players(b, server, map, false)) do
    if e.y < map.cliffY then
      climbers[#climbers + 1] = e
    else
      below[#below + 1] = e
    end
  end
  local best, bestScore
  for _, perch in ipairs(map.perches) do
    local here = (perch.x - b.x) ^ 2 + (perch.y - b.y) ^ 2 < 60 * 60
    if not here then
      local score
      if #climbers > 0 then
        local near = math.huge
        for _, e in ipairs(climbers) do
          near = math.min(near, (perch.x - e.x) ^ 2 + (perch.y - e.y) ^ 2)
        end
        score = math.sqrt(near) + random() * 250
      elseif perch.edge then
        local near = math.huge
        for _, e in ipairs(below) do
          near = math.min(near, math.sqrt((perch.x - e.x) ^ 2 + (perch.y - e.y) ^ 2))
        end
        -- In range of somebody is what matters; after that, anywhere will do.
        score = (near <= b.RANGE * 0.9 and 2000 or -near) + random() * 600
      end
      if score and (not bestScore or score > bestScore) then
        best, bestScore = perch, score
      end
    end
  end
  return best
end

--- Out of sight, off to a new spot. Returns the event for the wire.
local function vanish(b, server, map, goal)
  b.hiddenUntil = b.time + b.STEALTH.seconds
  b.stealthReady = b.time + b.STEALTH.cooldown
  b.breath:spend(b.STEALTH_BREATH)
  b.aim = nil
  b.goal = goal or pickPerch(b, server, map)
  return { "hide", b.x, b.y }
end

--- One sniper round from where he stands at `aim`, over the lip if need be.
local function fireRifle(server, map, b, aim, reach)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    local mx, my = b.muzzle(map, b.x, b.y, aim, reach)
    weapons:serverFireFrom(server, 0, mx, my, aim, Guns.sniper)
  end
end

local function firePistol(server, b, aim)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    aim = aim + (random() * 2 - 1) * b.PISTOL_SPREAD
    weapons:serverFireFrom(server, 0, b.x + math.cos(aim) * b.MUZZLE, b.y + math.sin(aim) * b.MUZZLE,
      aim, Guns.pistol)
  end
end

--- The bead he has on somebody: follow them, leading their walk, until
--- the lock; then the shot. Returns true while it goes on.
local function stepAim(b, server, map, dt, events)
  local a = b.aim
  local p = server.players[a.target]
  local x, y
  if p and Features.visible(server, p) then
    x, y = Features.bodyPose(server, p)
  end
  if not a.locked then
    if not x or not b.clear(map, b.x, b.y, x, y) then
      b.aim = nil -- lost them: behind something, out of sight or gone
      events[#events + 1] = { "aimoff" }
      return false
    end
    -- How they are moving, eased, so the lead doesn't jitter.
    if a.x then
      local k = math.min(1, dt * 6)
      a.vx = a.vx + ((x - a.x) / dt - a.vx) * k
      a.vy = a.vy + ((y - a.y) / dt - a.vy) * k
    end
    a.x, a.y = x, y
  end
  a.t = a.t - dt
  if not a.locked and a.t <= b.LOCK then
    -- Lead them to where they will be when the round arrives, if they
    -- keep going the way they are.
    local d = math.sqrt((a.x - b.x) ^ 2 + (a.y - b.y) ^ 2)
    local ahead = a.t + d / Guns.sniper.speed
    a.aimX, a.aimY = a.x + a.vx * ahead, a.y + a.vy * ahead
    a.locked = true
  end
  local ax, ay = a.aimX or a.x, a.aimY or a.y
  b.facing = math.atan2(ay - b.y, ax - b.x)
  if a.t <= 0 then
    local reach = math.sqrt((ax - b.x) ^ 2 + (ay - b.y) ^ 2)
    fireRifle(server, map, b, b.facing, reach)
    b.aim = nil
    b.rounds = b.rounds - 1
    b.boltIn = b.BOLT
    if b.rounds <= 0 then
      b.reloadIn = b.RELOAD
      events[#events + 1] = { "reload" }
    end
    return false
  end
  return true
end


--- Off to the medkit: out of sight first if he can manage it. Returns true
--- while that is what he is doing.
local function heal(b, server, map, dt, events)
  local m = b.medkit
  if not b:hidden() and b:canVanish() then
    if b.aim then
      events[#events + 1] = { "aimoff" }
    end
    events[#events + 1] = vanish(b, server, map, m)
  end
  if b.aim then -- no shots on the way
    b.aim = nil
    events[#events + 1] = { "aimoff" }
  end
  b.mode = "heal"
  goTo(b, m.x, m.y, b:pace(), dt)
  b.running = not b.breath:winded()
  if Heal.within(m, b.x, b.y, b.RADIUS) then
    local got = Heal.take(server, m)
    b.hp = math.min(b.max, b.hp + got)
    b.medkit, b.path = nil, nil
    if b.goal == m then
      b.goal = nil
    end
    if got > 0 and not b:hidden() then
      b.sayIn = b.SAY_EVERY[1]
      events[#events + 1] = { "say", b.TALK + random(#b.lines - b.TALK) }
    end
  end
  return true
end

--- What he does this tick. Returns the events the others should hear about
--- (boss.lua's `update` lists them).
function Brain.think(b, server, dt)
  local events = {}
  local map = b.cliffMap()
  b.time = b.time + dt
  if not map then
    return events
  end
  if b.time - dt < b.hiddenUntil and not b:hidden() then
    events[#events + 1] = { "show", b.x, b.y }
  end
  if not b:hidden() then
    b.sayIn = b.sayIn - dt
    if b.sayIn <= 0 then
      b.sayIn = b.SAY_EVERY[1] + random() * (b.SAY_EVERY[2] - b.SAY_EVERY[1])
      events[#events + 1] = { "say", random(b.TALK) }
    end
  end
  b.boltIn = math.max(0, b.boltIn - dt)
  b.pistolIn = math.max(0, b.pistolIn - dt)
  if b.reloadIn > 0 then
    b.reloadIn = b.reloadIn - dt
    if b.reloadIn <= 0 then
      b.rounds = b.MAGAZINE
    end
  end
  if b.frozen > 0 then
    b.frozen = b.frozen - dt
    return events
  end
  if b.panic then
    b.panic.left = b.panic.left - dt
    b.facing = math.atan2(b.y - b.panic.y, b.x - b.panic.x)
    b:walk(b.facing, b:pace(1.3), dt)
    b.running = not b.breath:winded()
    if b.panic.left <= 0 then
      b.panic = nil
    end
    return events
  end

  if wantsHeal(b) and heal(b, server, map, dt, events) then
    return events
  end

  -- Hidden: on his way to the new spot, and nothing else.
  b.mode = b:hidden() and "hide" or "fight"
  if b:hidden() then
    local g = b.goal
    if g and (g.x - b.x) ^ 2 + (g.y - b.y) ^ 2 > 16 * 16 then
      b.facing = math.atan2(g.y - b.y, g.x - b.x)
      b:walk(b.facing, b:pace(), dt)
      b.running = not b.breath:winded()
    end
    return events
  end

  -- Too close for comfort: gone if he can be, the pistol if not.
  local all = players(b, server, map, false)
  local near = all[1]
  if near and near.d2 < b.EVADE ^ 2 then
    if b:canVanish() then
      if b.aim then
        events[#events + 1] = { "aimoff" }
      end
      events[#events + 1] = vanish(b, server, map)
      return events
    end
    local toward = math.atan2(near.y - b.y, near.x - b.x)
    b:walk(toward + math.pi, b:pace(0.8), dt)
    b.running = not b.breath:winded()
    if b.aim then
      b.aim = nil
      events[#events + 1] = { "aimoff" }
    end
    b.facing = toward
    if b.pistolIn <= 0 and b.clear(map, b.x, b.y, near.x, near.y) then
      b.pistolIn = b.PISTOL_EVERY
      firePistol(server, b, toward)
    end
    return events
  end

  -- Back where everyone can see him: gone again as soon as he can be,
  -- unless he is about to take a shot.
  if not b.aim and b:canVanish() then
    events[#events + 1] = vanish(b, server, map)
    return events
  end

  if b.aim then
    stepAim(b, server, map, dt, events)
    return events
  end
  if b.boltIn > 0 or b.reloadIn > 0 then
    return events
  end
  local seen = players(b, server, map, true)[1]
  if seen then
    b.aim = { target = seen.p.id, t = b.WARN, vx = 0, vy = 0 }
    b.facing = math.atan2(seen.y - b.y, seen.x - b.x)
    events[#events + 1] = { "aim", seen.p.id, b.WARN }
  elseif near then
    -- Nobody in sight: along the lip towards the nearest of them.
    local tx = math.max(map.ramp.x1 + 80, math.min(map.left + map.w - 80, near.x))
    local ty = near.y < map.cliffY and near.y or map.cliffY - 60
    if (tx - b.x) ^ 2 + (ty - b.y) ^ 2 > 40 * 40 then
      b.facing = math.atan2(ty - b.y, tx - b.x)
      b:walk(b.facing, b:pace(0.5), dt)
    end
  end
  return events
end


return Brain
