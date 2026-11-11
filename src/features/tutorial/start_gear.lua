-- What a newcomer to a world past the tutorial is handed: the pistol and
-- openborders, the two things Shoeman gives out in levels 3 and 4. Every
-- new player starts with empty slots (weapons, abilities); one who never
-- played here while the tutorial was finished would otherwise have nothing
-- and no way to get it.
--
-- Host only. A human is noted when they arrive (serverStart, or
-- serverPlayerJoined for a latecomer) as new when the world has no file
-- for them: a guest, an unsaved session, or a first visit. A returning
-- player keeps exactly what they saved. The gift waits for the first step
-- with them on their feet, after the saved world has told the quests
-- feature what is finished; it is given once, and not at all if the
-- tutorial is not finished then (they will play it).

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")

local StartGear = {}

StartGear.ABILITY = "openborders"
StartGear.ABILITY_SLOT = 1

local waiting = {} -- player id -> true: a new human not yet given their gear

--- Does the saved world remember `player` (a file of their own)?
local function remembered(server, player)
  return server.world ~= nil and not player.guest and server.world:readPlayer(player.key) ~= nil
end

local function note(server, player)
  if not player.bot then
    waiting[player.id] = not remembered(server, player) or nil
  end
end

--- Put item `item` in `player`'s bag and equip it with `equip`; a failed
--- equip takes it back out, so nothing is left lying in the bag.
local function hand(server, player, item, equip)
  local buildings = Features.byName.buildings
  if not (buildings and buildings.serverGive) or buildings:serverGive(server, player, item, 1) < 1 then
    return
  end
  if not equip() then
    buildings:serverTake(server, player, item, 1)
  end
end

--- The pistol into the first empty weapon slot, and openborders into its
--- slot, unless they carry them already.
function StartGear.give(server, player)
  local weapons, abilities = Features.byName.weapons, Features.byName.abilities
  local pistol = Guns.list[Guns.DEFAULT]
  if weapons and weapons.sv and not weapons:serverOwns(player, pistol.index) then
    local st = weapons.sv.players[player.id]
    for slot = 1, weapons.slotCount do
      if st and not st.slots[slot] then
        hand(server, player, "gun-" .. pistol.key, function()
          return weapons:serverEquip(server, player, pistol.index, slot)
        end)
        break
      end
    end
  end
  if abilities and abilities.sv and not abilities:serverOwns(player, StartGear.ABILITY) then
    local slots = abilities.sv.slots[player.id]
    if slots and not slots[StartGear.ABILITY_SLOT] then
      hand(server, player, "ability-" .. StartGear.ABILITY, function()
        return abilities:serverEquip(server, player, StartGear.ABILITY, StartGear.ABILITY_SLOT)
      end)
    end
  end
end

function StartGear.serverStart(server)
  waiting = {}
  for _, player in pairs(server.players) do
    note(server, player)
  end
end

--- Only latecomers count: before Start, serverStart notes everyone.
function StartGear.serverPlayerJoined(server, player)
  if server.started then
    note(server, player)
  end
end

function StartGear.serverPlayerLeft(player)
  waiting[player.id] = nil
end

--- Hand out what is owed, once each newcomer is on their feet.
function StartGear.serverStep(server)
  if not next(waiting) then
    return
  end
  local quests = Features.byName.quests
  local finished = quests and quests:serverFinished(quests.TUTORIAL)
  for id in pairs(waiting) do
    local player = server.players[id]
    if not player then
      waiting[id] = nil
    elseif Features.present(player) then
      waiting[id] = nil
      if finished then
        StartGear.give(server, player)
      end
    end
  end
end

return StartGear
