-- What the line's bosses that are one of the army (wlb_brain.lua,
-- knk_brain.lua, sml_brain.lua) do the same way: who they are after, how
-- they walk (the boss walking rule, bosses/walk.lua, on the level's grid),
-- and what comes before their own fight (`before`: an ability to get out
-- from under, a medkit to go for, somebody out of sight to go after).

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Walk = require("src.features.bosses.walk")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Kit = {}

local function blocked(x, y)
  return Chassis.blocked(x, y)
end
Kit.blocked = blocked

--- The nearest player `s` can see, and where; failing that, the nearest
--- anywhere, and whether it sees them.
function Kit.target(server, s)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Chassis.dist2(x, y, s.x, s.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = id, x, y, d2
      end
      if d2 <= s.conf.range ^ 2 and (not seenD2 or d2 < seenD2) and Chassis.lineClear(s.x, s.y, x, y) then
        seen, sx, sy, seenD2 = id, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

--- One step along `angle`, by the boss walking rule.
function Kit.step(s, angle, speed, dt)
  return Walk.step(s, blocked, angle, speed, dt, s.radius)
end

--- Is the way from `s` to (x, y) wide enough for it to walk straight there?
function Kit.straight(s, x, y)
  return Walk.wideClear(blocked, s.x, s.y, x, y, s.radius)
end

--- The level's walking grid as `s` walks it (its size), made the first time.
function Kit.nav(roster, s)
  s.walkNav = s.walkNav or Walk.nav(roster.nav, blocked, s.radius)
  return s.walkNav
end

--- One step on the walking grid towards (x, y).
function Kit.walkTo(roster, s, x, y, speed, dt)
  local way = Walk.route(s, Kit.nav(roster, s), x, y, roster.time)
  if way then
    s.facing = Chassis.turn(s.facing, way, Chassis.TURN, dt)
    Kit.step(s, way, speed, dt)
  end
end

--- Badly hurt and a medkit in reach: `s` off for it at a run. Returns
--- true while that is what it is doing.
function Kit.heal(roster, server, s, dt)
  if not Heal.wants(s.hp, s.max) then
    s.medkit = nil
    return false
  end
  if s.medkit and not Heal.there(s.medkit) then
    s.medkit = nil
  end
  if not s.medkit and roster.time >= (s.healLook or 0) then
    s.medkit, s.healLook = Heal.find(s.x, s.y), roster.time + Heal.checkEvery
  end
  if not s.medkit then
    return false
  end
  local way = Heal.way(s, Kit.nav(roster, s), s.medkit, roster.time)
  if not way then
    Heal.giveUp(s, roster.time)
    s.medkit = nil
    return false
  end
  s.facing = Chassis.turn(s.facing, way, Chassis.TURN, dt)
  Kit.step(s, way, s.conf.speed, dt)
  Heal.pickUp(server, s, s.radius)
  return true
end

--- What `s` does before its own fight, a tick of it, breath and all: out
--- from under an ability about to land on it, off for a medkit when badly
--- hurt, after whoever it can't see on the walking grid. Returns who it
--- sees to fight and where (id, x, y), or nil when it did one of those
--- (or there is nobody).
function Kit.before(roster, server, s, dt)
  local threat = Dodge.threat(s.x, s.y, s.radius)
  if threat then -- out from under it, as fast as it goes
    local ux, uy = Dodge.away(threat, s.x, s.y)
    Kit.step(s, math.atan2(uy, ux), s.conf.speed, dt)
    s.breath:step(not s.breath:winded(), dt)
    return nil
  end
  local who, tx, ty, visible = Kit.target(server, s)
  if not who then
    s.breath:step(false, dt)
    return nil
  end
  if Kit.heal(roster, server, s, dt) then
    s.breath:step(true, dt)
    return nil
  end
  if not visible then
    Kit.walkTo(roster, s, tx, ty, s.conf.speed, dt)
    s.breath:step(not s.breath:winded(), dt)
    return nil
  end
  return who, tx, ty
end

return Kit
