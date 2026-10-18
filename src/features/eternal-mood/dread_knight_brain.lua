-- The Dread Knights' brain, on the host: what one does each tick, once
-- awake. The knight himself (his numbers, lines, the wire) is
-- dread_knight.lua; he is handed in as `k`, and his numbers are read off
-- him (k.SLASH_REACH...).
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   home    nobody about: back to his spot
--   hunt    somebody he can't see: after them on the walking grid
--   fight   somebody he can see: in at them, weaving so he's hard to hit,
--           and cut them down
--   regroup winded: he backs off and circles, out of reach, till he has
--           his breath back
--   heal    badly hurt (bosses/heal.lua): off for the nearest medkit
--
-- His moves, each with a tell before it lands:
--
--   slash   up close (SLASH_REACH): a blade goes back (SLASH_WINDUP, his
--           reach shown on the floor), then sweeps across in front of him
--   lunge   a few steps off (LUNGE_MIN to LUNGE_MAX): he crouches, blades
--           back (LUNGE_WINDUP, a lane on the floor where he'll go), then
--           dashes down it (LUNGE_SPEED for up to LUNGE_TIME) and slashes
--           whoever he reaches. Aimed where you're going, not where you
--           are. Whoever he's stunned he lets get up, closing in, and
--           crouches for a lunge the moment they do (UP_WINDOW, if he has the
--           breath): the tell is your chance to dodge, or take another
--
-- Either one that lands is a `melee` hit (SLASH_DAMAGE): you bleed, as from
-- any blade, and DEEP_CHANCE of the time it's a deep wound on top (DEEP_TIME
-- seconds at DEEP_DPS; a medkit stops it); you're thrown back KNOCK px and
-- stunned STUN seconds (less what you wear against melee). After either he
-- stands a moment (RECOVER), open.
--
-- A dodge: a player's round about to hit him (DODGE_WARN seconds off) and
-- he throws himself aside off its line, to whichever side keeps him nearer
-- whoever he's after; an ability about to land on him and he dashes out
-- from under it (bosses/dodge.lua). Each costs DODGE_COST breath,
-- DODGE_COOL apart at most, and only with DODGE_FLOOR in him (the rest is
-- for his lunges); winded, he only walks out from under an ability.
--
-- A freeze holds him stiff. His breath (bosses/stamina.lua): running, a
-- lunge or a dodge spends it; winded he strolls and regroups.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
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

--- The nearest player he can see, and where they are; failing that, the
--- nearest within HUNTS, and whether he sees them.
function Brain.target(k, server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, k.x, k.y)
      if d2 <= k.HUNTS ^ 2 and (not anyD2 or d2 < anyD2) then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= k.SEES ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(k.x, k.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

local function goTo(k, x, y, speed, dt)
  local g = k.goal
  if not g or dist2(g.x, g.y, x, y) > 80 * 80 or k.time > g.replanAt or k.stuck > 0.3 then
    local corners = k.nav and k.nav:path(k.x, k.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = k.time + 1 }
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
  local a = math.atan2(c.y - k.y, c.x - k.x)
  k:turn(a, dt)
  k:walk(a, speed, dt)
  return false
end

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

--- Is player `p` held by a stun or a knock right now?
local function stunned(server, p)
  local damage = Features.byName.damage
  return damage ~= nil and damage.serverHeld ~= nil and damage:serverHeld(server, p) == true
end

--- His blade through everyone within `reach` and ARC of his front: each
--- takes the hit (see the top of this file). Returns the players it caught.
local function cut(k, server, reach)
  local weapons, damage = Features.byName.weapons, Features.byName.damage
  local onFoot = Features.byName["on-foot"]
  local caught = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local a = math.atan2(py - k.y, px - k.x)
      if dist2(px, py, k.x, k.y) <= reach * reach and math.abs(Sight.angleDiff(a, k.facing)) <= k.ARC then
        caught[#caught + 1] = p
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, k.SLASH_DAMAGE * k.power, a, "melee")
        end
        if Features.present(p) then -- that didn't kill them
          if damage and damage.serverAfflict then
            if random() < k.DEEP_CHANCE then
              damage:serverAfflict(server, p, "bleed", k.DEEP_TIME, k.DEEP_DPS * k.power)
            end
            damage:serverAfflict(server, p, "stun", k.STUN * damage:serverShare(server, p, "melee"))
          end
          if onFoot and onFoot.serverShove then
            onFoot:serverShove(server, p, math.cos(a), math.sin(a), k.KNOCK, k.KNOCK_TIME)
          end
        end
      end
    end
  end
  return caught
end

--- The way off the line of the player's round about to hit him (a unit
--- vector, onto clear ground, the side nearer (tx, ty) first), or nil.
local function incoming(k, server, tx, ty)
  local weapons = Features.byName.weapons
  local rounds = weapons and weapons.sv and weapons.sv.projectiles
  for _, r in ipairs(rounds or {}) do
    local speed = math.sqrt(r.vx * r.vx + r.vy * r.vy)
    if r.owner ~= 0 and speed > 0 and server.players[r.owner] then
      local ux, uy = r.vx / speed, r.vy / speed
      local rx, ry = k.x - r.x, k.y - r.y
      local along, across = rx * ux + ry * uy, rx * -uy + ry * ux
      local width = r.blast and r.blast.radius * 0.6 or 0
      if along > 0 and along / speed < k.DODGE_WARN and math.abs(across) < k.RADIUS + width + 10 then
        local side = across >= 0 and 1 or -1
        if tx then -- whichever side keeps him nearer them
          local reach = k.DODGE_SPEED * k.DODGE_TIME
          local d1 = dist2(k.x - uy * side * reach, k.y + ux * side * reach, tx, ty)
          local d2 = dist2(k.x + uy * side * reach, k.y - ux * side * reach, tx, ty)
          if d2 < d1 then
            side = -side
          end
        end
        local reach = k.DODGE_SPEED * k.DODGE_TIME
        for _, s in ipairs({ side, -side }) do
          local dx, dy = -uy * s, ux * s
          if k.fits(k.x + dx * reach, k.y + dy * reach) then
            return dx, dy
          end
        end
        return nil
      end
    end
  end
  return nil
end

local function canDodge(k)
  return k.time >= (k.dodgeAt or 0) and k.breath:has(k.DODGE_COST) and k.breath.stamina >= k.DODGE_FLOOR
end

local function dodge(k, ux, uy, far)
  k.breath:spend(k.DODGE_COST)
  k.move, k.moveT, k.goal = "dodge", 0, nil
  k.dodgeA = math.atan2(uy, ux)
  k.dodgeFor = math.max(k.DODGE_TIME, (far or 0) / k.DODGE_SPEED)
  k.dodgeAt = k.time + k.DODGE_COOL
end

--- Crouch for a lunge at `p` (at tx, ty), aimed where they're going.
local function lunge(k, p, tx, ty)
  local vx, vy = 0, 0
  if k.seenP == p and k.seenT and k.time > k.seenT then
    local dt = math.max(0.05, k.time - k.seenT)
    vx, vy = (tx - k.seenX) / dt, (ty - k.seenY) / dt
  end
  local ax, ay = tx + vx * k.LEAD, ty + vy * k.LEAD
  k.breath:spend(k.LUNGE_COST)
  k.move, k.moveT, k.goal = "crouch", 0, nil
  k.aim = math.atan2(ay - k.y, ax - k.x)
  k.lungeIn = between(k.LUNGE_EVERY)
end

--- His blade comes through: whoever it catches takes the hit (see the top
--- of this file); then the follow-through, and `every` before the next.
local function swing(k, server, events, every)
  if #cut(k, server, k.SLASH_REACH) > 0 then
    events[#events + 1] = { "hit", "slash", k.x + math.cos(k.facing) * 20, k.y + math.sin(k.facing) * 20 }
    k.landed = true
  else
    events[#events + 1] = { "hit", "miss", k.x, k.y }
  end
  k.move, k.moveT, k.slashIn = "slash", 0, every
end

--- Is anyone within his reach in front of him, along `aim`?
local function within(k, server, aim)
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local a = math.atan2(y - k.y, x - k.x)
      if dist2(x, y, k.x, k.y) <= (k.SLASH_REACH * 0.8) ^ 2 and math.abs(Sight.angleDiff(a, aim)) <= k.ARC then
        return true
      end
    end
  end
  return false
end

--- A move under way, on to its end. Returns whether he ran this tick.
local function carryOn(k, server, dt, events)
  k.moveT = k.moveT + dt
  if k.move == "windup" then
    local p = k.aimAt
    if p and Features.visible(server, p) then -- coming round slowly: a step aside beats it
      local x, y = Features.bodyPose(server, p)
      k:turn(math.atan2(y - k.y, x - k.x), dt, k.TURN * 0.4)
    end
    if k.moveT >= k.SLASH_WINDUP then
      swing(k, server, events, k.SLASH_EVERY)
    end
  elseif k.move == "crouch" then
    if k.moveT >= k.LUNGE_WINDUP then
      k.move, k.moveT, k.facing = "lunge", 0, k.aim
    end
  elseif k.move == "lunge" then
    k.facing = k.aim
    local moved = k:walk(k.aim, k.LUNGE_SPEED, dt)
    if within(k, server, k.aim) or not moved or k.moveT >= k.LUNGE_TIME then
      swing(k, server, events, k.SLASH_EVERY * 0.5)
    end
    return true
  elseif k.move == "slash" then -- the follow-through, then he stands a moment, open
    if k.moveT >= k.RECOVER then
      k.move = nil
    end
  elseif k.move == "dodge" then
    k:walk(k.dodgeA, k.DODGE_SPEED, dt)
    if k.moveT >= k.dodgeFor then
      k.move = nil
    end
  end
  return false
end

--- Off the line of a round, or out from under an ability. Returns whether
--- he did either, and whether he ran.
local function avoid(k, server, dt, tx, ty)
  if canDodge(k) then
    local ux, uy = incoming(k, server, tx, ty)
    if ux then
      dodge(k, ux, uy)
      return true, false
    end
  end
  local threat = Dodge.threat(k.x, k.y, k.RADIUS)
  if not threat then
    return false
  end
  local ux, uy = Dodge.away(threat, k.x, k.y)
  if canDodge(k) then -- out from under it in one dash
    local d = math.sqrt(dist2(k.x, k.y, threat.x, threat.y))
    dodge(k, ux, uy, threat.radius + k.RADIUS + Dodge.margin - d)
    return true, false
  end
  k:walk(math.atan2(uy, ux), k:pace(), dt)
  return true, not k.breath:winded()
end

--- Off to the medkit he's after, picking it up there. Returns whether he ran.
local function heal(k, server, dt)
  k.mode = "heal"
  local kit = k.medkit
  goTo(k, kit.x, kit.y, k:pace(), dt)
  if Heal.within(kit, k.x, k.y, k.RADIUS) then
    k.hp = math.min(k.max, k.hp + Heal.take(server, kit))
    k.medkit, k.goal = nil, nil
  end
  return not k.breath:winded()
end

--- Back to his spot, nobody about.
local function home(k, dt)
  k.mode = "home"
  local h = k.home
  if dist2(k.x, k.y, h.x, h.y) > 30 * 30 then
    goTo(k, h.x, h.y, k.WALK * 0.7, dt)
  else
    k:turn(h.facing, dt)
  end
end

--- Whoever he has in sight, at (tx, ty): wait for them to get up, slash,
--- lunge, regroup winded, or weave in. Returns whether he ran.
local function fight(k, server, dt, target, tx, ty)
  k.mode, k.goal = "fight", nil
  local toward = math.atan2(ty - k.y, tx - k.x)
  local d = math.sqrt(dist2(tx, ty, k.x, k.y))
  if k.seenP ~= target or not k.seenT or k.time - k.seenT > 0.2 then -- where they were, to lead a lunge
    k.seenP, k.seenX, k.seenY, k.seenT = target, tx, ty, k.time
  end
  k:turn(toward, dt)
  local facing = math.abs(Sight.angleDiff(toward, k.facing))
  if stunned(server, target) then -- he lets them get up, closing in, and goes the moment they do
    k.waited = target
    if d > k.LUNGE_MIN then
      k:walk(toward, k.WALK, dt)
    end
    return false
  end
  if k.waited == target then -- they just got up: no waiting for his next lunge
    k.upAt = k.time
  end
  k.waited = nil
  local up = k.upAt ~= nil and k.time - k.upAt < k.UP_WINDOW
  if d <= k.SLASH_REACH and k.slashIn <= 0 and facing < 0.6 then
    k.move, k.moveT, k.aimAt = "windup", 0, target
    return false
  end
  if d >= k.LUNGE_MIN and d <= k.LUNGE_MAX and facing < 0.35 and k.breath:has(k.LUNGE_COST)
    and (k.lungeIn <= 0 or up) and Sight.clear(k.x, k.y, tx, ty) then
    lunge(k, target, tx, ty)
    return false
  end
  if k.breath:winded() then -- out of reach till he has his breath back
    k.mode = "regroup"
    local away = d < k.REGROUP and toward + math.pi or toward + k.side * math.pi / 2
    if not k:walk(away, k.STROLL, dt) then
      k.side = -k.side
    end
    return false
  end
  -- In at them, weaving: never a straight line to shoot down.
  local weave = math.sin(k.time * k.WEAVE + k.id) * k.WEAVE_ARC
  local far = d > k.LUNGE_MAX
  if not k:walk(toward + weave, far and k:pace() or k.WALK, dt) then
    k:walk(toward - weave, k.WALK, dt)
  end
  return far and not k.breath:winded()
end

--- What he does this tick. Returns the events the others should hear
--- about: { "say", category }, { "hit", name, x, y }.
function Brain.think(k, server, dt)
  local events = {}
  k.time = k.time + dt
  k.slashIn = k.slashIn - dt
  k.lungeIn = k.lungeIn - dt
  k.sayIn = k.sayIn - dt
  local running = false
  if k.frozen > 0 then
    k.frozen = k.frozen - dt
  elseif k.move then
    running = carryOn(k, server, dt, events)
  else
    local target, tx, ty, visible = Brain.target(k, server)
    local acted, ran = avoid(k, server, dt, tx, ty)
    if acted then
      running = ran
    elseif wantsHeal(k) then
      running = heal(k, server, dt)
    elseif not target then
      home(k, dt)
    elseif not visible then
      k.mode = "hunt"
      goTo(k, tx, ty, k:pace(), dt)
      running = not k.breath:winded()
    else
      if k.sayIn <= 0 then
        k.sayIn = between(k.SAY_EVERY)
        events[#events + 1] = { "say", k.landed and "gloat" or "taunt" }
        k.landed = nil
      end
      running = fight(k, server, dt, target, tx, ty)
    end
  end
  k.running = running
  k.breath:step(running, dt)
  return events
end

return Brain
