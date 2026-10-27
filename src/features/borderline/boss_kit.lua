-- What the line's bosses that are one of the army (wlb_brain.lua,
-- knk_brain.lua) do the same way: who they are after, and how they walk
-- (the boss walking rule, bosses/walk.lua, on the level's grid).

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Walk = require("src.features.bosses.walk")

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

return Kit
