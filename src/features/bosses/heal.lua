-- How a boss patches itself up (the standard's point 7, bosses/init.lua):
-- badly hurt, it breaks off to go for a medkit lying near it (pickups'
-- "health"), takes it off the ground the way a player would, and is
-- `Heal.amount` better for it. The boss's brain decides when and walks
-- there itself; this only finds, checks and takes. Host only.

local Features = require("src.features")

local Heal = {}

-- Tuning ------------------------------------------------------------------
Heal.amount = 200 -- what one medkit puts back on a boss (a player gets 50)
Heal.below = 0.4 -- share of its health under which a boss goes for one
Heal.range = 700 -- px; how far it will go for one
Heal.reach = 30 -- px from it that it can pick one up, past its own size
Heal.checkEvery = 1 -- seconds between looks for one

local KINDS = { health = true }

local function pickups()
  local p = Features.byName.pickups
  return p and p.serverNearest and p or nil
end

--- Should a boss with `hp` of `max` be looking for a medkit?
function Heal.wants(hp, max)
  return hp < max * Heal.below
end

--- The nearest medkit within Heal.range of (x, y): { id, x, y }, or nil.
function Heal.find(x, y)
  local p = pickups()
  if not p then
    return nil
  end
  local id, it = p:serverNearest(x, y, Heal.range, KINDS)
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

return Heal
