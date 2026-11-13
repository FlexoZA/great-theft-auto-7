-- What Shoeman hands out (docs/tutorial.md, "Level 3" and "Level 4"): the
-- pistol in the scrap yard, openborders in town. He puts it on the ground,
-- one each (a pickups `perPlayer` drop), and watches every human pick
-- theirs up and equip it.
--
-- Host only. `Gift.serverStart(gift, x, y)` when the level begins, with
-- one of the gifts below; it lands `DROP_AFTER` seconds in, while he says
-- so. From then on every step asks, for each human, whether they carry it
-- equipped (and so picked up) or have it in their bag (picked up), and
-- tells init.lua through `on`:
--   on.picked(server, player)   they have it, in the bag or equipped
--   on.equipped(server, player) they carry it in a slot
-- Each is said every step it is true; the objectives count a player once.
-- Somebody who already carries one (an old player replaying the level)
-- counts as done at once and never sees the one on the ground, so nobody
-- walks off with a spare to sell.

local Features = require("src.features")
local Tiers = require("src.features.tiers")

local Gift = {}

Gift.DROP_AFTER = 10 -- seconds into the level he puts it down (his start beat says so)

-- The gifts. `item` is the bag's item (and the pickup's kind); `equipped`
-- says whether a player carries one in a slot, in any tier.
Gift.PISTOL = {
  item = "gun-pistol",
  equipped = function(player)
    local weapons = Features.byName.weapons
    return weapons ~= nil and weapons:serverOwns(player, weapons.guns.DEFAULT)
  end,
}
Gift.OPENBORDERS = {
  item = "ability-openborders",
  equipped = function(player)
    local abilities = Features.byName.abilities
    return abilities ~= nil and abilities:serverOwns(player, "openborders")
  end,
}

local sv = nil -- { gift, x, y, dropIn, id (the pickup), hidden = { [player id] = true } }

function Gift.serverStart(gift, x, y)
  sv = { gift = gift, x = x, y = y, dropIn = Gift.DROP_AFTER, hidden = {} }
end

function Gift.serverStop()
  sv = nil
end

--- Does player `id` have the gift's item in their bag, in any tier?
local function inBag(buildings, id, item)
  for _, tier in ipairs(Tiers.list) do
    if buildings:serverCount(id, Tiers.join(item, tier.key)) > 0 then
      return true
    end
  end
  return false
end

function Gift.serverStep(server, dt, on)
  if not sv then
    return
  end
  local pickups, buildings = Features.byName.pickups, Features.byName.buildings
  if not (pickups and buildings) then
    return
  end
  if sv.dropIn then
    sv.dropIn = sv.dropIn - dt
    if sv.dropIn > 0 then
      return
    end
    sv.dropIn = nil
    sv.id = pickups:serverDrop(server, sv.gift.item, sv.x, sv.y, nil, { perPlayer = true })
  end
  for id, player in pairs(server.players) do
    if not player.bot then
      local armed = sv.gift.equipped(player)
      if armed and sv.id and not sv.hidden[id] then
        sv.hidden[id] = true
        pickups:serverTakenBy(server, sv.id, player)
      end
      if armed or inBag(buildings, id, sv.gift.item) then
        on.picked(server, player)
      end
      if armed then
        on.equipped(server, player)
      end
    end
  end
end

return Gift
