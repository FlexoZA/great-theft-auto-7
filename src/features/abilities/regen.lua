-- Regen: a passive ability. Carry it in the passive slot and your body
-- heals itself, a little every second, once you have gone a few seconds
-- without being hurt. It never mends the car you are driving (weapons'
-- serverHeal would, once the body is full, so this stops at the body) and
-- does nothing while you are dead or out of the world.
--
-- Passive abilities have no cast: the abilities feature calls
-- `serverTick(server, player, dt, abilities)` every host tick for whatever
-- sits in a player's passive slot, and this one asks weapons to heal.

local Features = require("src.features")

local Regen = {
  key = "regen", -- on the wire and in a bag ("ability-regen")
  title = "regen",
  passive = true, -- fits only the passive slot
  color = { 0.45, 0.95, 0.55 }, -- fresh green
}

-- Tuning ------------------------------------------------------------------
Regen.rate = 2 -- hit points a second, once it is going
Regen.delay = 4 -- seconds without being hurt before it starts

local owed = {} -- player id -> fractions of a hit point saved up

--- Heal `player` a little, in whole hit points, once the delay after their
--- last wound has passed.
function Regen.serverTick(server, player, dt, abilities)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverHealth and weapons.serverHeal and Features.present(player)) then
    owed[player.id] = nil
    return
  end
  if abilities:serverSinceHurt(player) < Regen.delay then
    owed[player.id] = nil -- a fresh wound: start the wait again
    return
  end
  local hp, max = weapons:serverHealth(player)
  if not hp or hp >= max then
    owed[player.id] = nil
    return
  end
  local sum = (owed[player.id] or 0) + Regen.rate * dt
  local whole = math.floor(sum)
  owed[player.id] = sum - whole
  if whole > 0 then
    weapons:serverHeal(server, player, math.min(whole, max - hp))
  end
end

return Regen
