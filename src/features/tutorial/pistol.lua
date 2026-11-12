-- Level 3's pistol (docs/tutorial.md, "Level 3"): Shoeman puts a pistol on
-- the ground, one each (a pickups `perPlayer` drop), and watches every
-- human pick theirs up and put it in a weapon slot.
--
-- Host only. `Pistol.serverStart(x, y)` when the level begins (the scrap
-- yard's `map.dropX, dropY`); the pistol lands `DROP_AFTER` seconds in,
-- while he says so. From then on every step asks, for each human, whether
-- they carry a pistol in a slot (equipped, and so picked up) or have one
-- in their bag (picked up), and tells init.lua through `on`:
--   on.picked(server, player)   they have one, in the bag or a slot
--   on.equipped(server, player) they carry one in a weapon slot
-- Each is said every step it is true; the objectives count a player once.
-- Somebody who already carries a pistol (an old player replaying the
-- level) counts as done at once and never sees the one on the ground, so
-- nobody walks off with a spare to sell.

local Features = require("src.features")

local Pistol = {}

Pistol.ITEM = "gun-pistol" -- the bag's item for it (buildings/kinds.lua)
Pistol.DROP_AFTER = 10 -- seconds into the level he puts it down (his start beat says so)

local sv = nil -- { x, y, dropIn, id (the pickup), hidden = { [player id] = true } }

function Pistol.serverStart(x, y)
  sv = { x = x, y = y, dropIn = Pistol.DROP_AFTER, hidden = {} }
end

function Pistol.serverStop()
  sv = nil
end

--- Does `player` carry a pistol in a weapon slot?
local function carries(weapons, player)
  local Guns = weapons.guns
  return weapons:serverOwns(player, Guns.DEFAULT)
end

function Pistol.serverStep(server, dt, on)
  if not sv then
    return
  end
  local pickups, weapons, buildings = Features.byName.pickups, Features.byName.weapons, Features.byName.buildings
  if not (pickups and weapons and buildings) then
    return
  end
  if sv.dropIn then
    sv.dropIn = sv.dropIn - dt
    if sv.dropIn > 0 then
      return
    end
    sv.dropIn = nil
    sv.id = pickups:serverDrop(server, Pistol.ITEM, sv.x, sv.y, nil, { perPlayer = true })
  end
  for id, player in pairs(server.players) do
    if not player.bot then
      local armed = carries(weapons, player)
      if armed and sv.id and not sv.hidden[id] then
        sv.hidden[id] = true
        pickups:serverTakenBy(server, sv.id, player)
      end
      if armed or buildings:serverCount(id, Pistol.ITEM) > 0 then
        on.picked(server, player)
      end
      if armed then
        on.equipped(server, player)
      end
    end
  end
end

return Pistol
