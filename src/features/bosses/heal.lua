-- How a boss patches itself up (the standard's point 7, bosses/init.lua):
-- badly hurt, it breaks off to go for a medkit lying near it (pickups'
-- "health"), takes it off the ground the way a player would, and is
-- `Heal.amount` better for it. The boss's brain decides when and walks
-- there itself (kiting, the standard's point 7); this finds one, gives the
-- way there (Heal.way, or Heal.giveUp when there is none it fits), checks
-- and takes. Host only.

local Features = require("src.features")
local Walk = require("src.features.bosses.walk")

local Heal = {}

-- Tuning ------------------------------------------------------------------
Heal.amount = 200 -- what one medkit puts back on a boss (a player gets 50)
Heal.below = 0.4 -- share of its health under which a boss goes for one
Heal.range = 700 -- px; how far it will go for one
Heal.reach = 30 -- px from it that it can pick one up, past its own size
Heal.checkEvery = 1 -- seconds between looks for one
Heal.noWay = 5 -- seconds a boss that finds no way to the nearest one fights on before it looks again

local KINDS = { health = true }

local function pickups()
  local p = Features.byName.pickups
  return p and p.serverNearest and p or nil
end

--- Should a boss with `hp` of `max` be looking for a medkit?
function Heal.wants(hp, max)
  return hp < max * Heal.below
end

--- The nearest medkit within `range` (Heal.range when nil) of (x, y):
--- { id, x, y }, or nil. A boss that gets about faster may look further.
function Heal.find(x, y, range)
  local p = pickups()
  if not p then
    return nil
  end
  local id, it = p:serverNearest(x, y, range or Heal.range, KINDS)
  return id and { id = id, x = it.x, y = it.y } or nil
end

--- Is medkit `m` (from Heal.find) still lying there?
function Heal.there(m)
  local p = pickups()
  return p ~= nil and m ~= nil and p:serverHas(m.id)
end

--- Is a boss at (x, y), `radius` px across, close enough to pick `m` up?
function Heal.within(m, x, y, radius)
  return (m.x - x) ^ 2 + (m.y - y) ^ 2 <= (radius + Heal.reach) ^ 2
end

--- Take medkit `m` off the ground: the hp it gives, 0 if it was gone.
function Heal.take(server, m)
  local p = pickups()
  local it = p and p:serverTake(server, m.id, 0)
  return it and Heal.amount or 0
end

--- The way boss `b` ({ x, y, stuck, route }) walks to medkit `kit` on grid
--- `nav` (Walk.nav's), `time` its clock: an angle (Walk.route's, then
--- straight at the kit once past the grid's last corner, which is a cell's
--- middle and may be short of it), or nil when there is no way it fits
--- (Heal.giveUp then).
function Heal.way(b, nav, kit, time)
  local way, there = Walk.route(b, nav, kit.x, kit.y, time)
  if there then
    return math.atan2(kit.y - b.y, kit.x - b.x)
  end
  return way
end

--- Boss `b` found no way to its medkit (`b.medkit`): it lets it go, fights
--- on, and looks for one again after `noWay` seconds of its clock `time`.
function Heal.giveUp(b, time)
  b.medkit, b.route, b.healLook = nil, nil, time + Heal.noWay
end

--- Boss `b` (`radius` px across) picks up its medkit (`b.medkit`) if it is
--- close enough, and is better for it: the hp it got (0 if somebody else
--- got there first), or nil while it is still on its way.
function Heal.pickUp(server, b, radius)
  local kit = b.medkit
  if not Heal.within(kit, b.x, b.y, radius) then
    return nil
  end
  local got = Heal.take(server, kit)
  b.hp = math.min(b.max, b.hp + got)
  b.medkit, b.goal, b.route = nil, nil, nil
  return got
end

return Heal
