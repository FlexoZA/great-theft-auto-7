-- Gear: the clothes a player wears in the head, body, pants and shoes
-- slots of the inventory screen, each scaling something about them
-- (kinds.lua): running shoes make you faster and sprinting cheaper, a
-- tactical hat makes ammo bundles bigger, cargo pants bring abilities back
-- sooner, a plate carrier makes a vest hold more; others resist a kind of
-- damage (a firefighter jacket, a crash helmet, rubber boots).
--
-- A piece ("gear-<key>", sold by the shop) is dragged from the bag onto
-- its slot to put it on (GEAR_EQUIP: the host takes the item; whatever was
-- in the slot goes back into the bag) and from the slot into the bag to
-- take it off (GEAR_UNEQUIP). Clothes are never damaged and death leaves
-- them on, and a saved world keeps them on for next time (serverSavePlayer).
--
-- Clothes come in tiers (tiers/init.lua): "gear-running-shoes@rare" makes
-- more of both its bonuses. What is worn is kept with its tier
-- ("running-shoes@rare") and goes back into the bag in it.
--
-- Nobody asks this feature what a piece does. On the host a feature asks
-- `Features.reduce("serverStat", 1, server, player, name)` and on a client
-- `Features.reduce("stat", 1, client, id, name)`, and every piece worn
-- multiplies the answer by its `stats[name]`; `serverStatsChanged(server,
-- player)` goes out when what they wear changes, for anything that keeps a
-- number derived from it (armor rescales the vest).
--
-- A piece can resist damage types too (`resist` in kinds.lua): the damage
-- feature asks `serverResist` / `resist`, and every piece worn lets through
-- (1 - its resistance) of a hit of that type. A tier that improves a
-- resistance grows it by the tier's `bonus`, as it would a clothes bonus.
--
-- Messages
--   client -> server  GEAR_EQUIP   <key[@tier]>
--   client -> server  GEAR_UNEQUIP <slot>
--   server -> all     GEAR_STATE   <id> <head> <body> <pants> <shoes>   (each key[@tier]; "-" = nothing there)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Kinds = require("src.features.gear.kinds")
local Tiers = require("src.features.tiers")
local Damage = require("src.features.damage")

local Gear = {
  name = "gear",
}

Gear.kinds = Kinds
local NONE = "-"

--- The piece `key` ("running-shoes", "running-shoes@rare") names, and its
--- tier key; nil for nonsense.
local function pieceOf(key)
  if type(key) ~= "string" then
    return nil
  end
  local base, tier = Tiers.split(key)
  local g = Kinds.byKey[base]
  if g and tier then
    return g, tier
  end
  return nil
end
Gear.pieceOf = pieceOf

--- What piece `g` in tier `tier` does to `name`: its multiplier, the bonus
--- grown if the tier improves that stat.
local function multiplier(g, tier, name)
  local m = g.stats[name]
  if not m then
    return 1
  end
  for i, stat in ipairs(g.tierStats) do
    if stat == name then
      return Tiers.multiplier(m, tier, i)
    end
  end
  return m
end
Gear.multiplier = multiplier

--- How much of a `dtype` hit piece `g` in tier `tier` stops, 0 to 1: its
--- resistance, grown by the tier's bonus if the tier improves it.
local function resistance(g, tier, dtype)
  local r = g.resist and g.resist[dtype]
  if not r then
    return 0
  end
  for i, stat in ipairs(g.tierStats) do
    if stat == "resist." .. dtype and Tiers.improves(tier, i) then
      r = r * Tiers.get(tier).bonus
    end
  end
  return Damage.clampResist(r)
end
Gear.resistance = resistance

--- What gets through of a `dtype` hit, times `share`, past what `worn`
--- (slot -> key) holds.
local function through(share, worn, dtype)
  if worn then
    for _, key in pairs(worn) do
      local g, tier = pieceOf(key)
      if g then
        share = share * (1 - resistance(g, tier, dtype))
      end
    end
  end
  return share
end

--- The product of `name` over what `worn` (slot -> key) holds.
local function scale(worn, name)
  local s = 1
  if worn then
    for _, key in pairs(worn) do
      local g, tier = pieceOf(key)
      if g then
        s = s * multiplier(g, tier, name)
      end
    end
  end
  return s
end

-- Client --------------------------------------------------------------------

Gear.worn = {} -- player id -> slot -> key with its tier ("running-shoes@rare"), as the host told us

function Gear:exitGame()
  self.worn = {}
end

--- What I wear: slot -> key (an empty table with nothing on).
function Gear:mine(client)
  return self.worn[client.myId] or {}
end

--- Ask to put on the piece I carry for `key` (the inventory screen does,
--- on a drag).
function Gear:equip(client, key)
  if pieceOf(key) then
    client:send(Protocol.encode("GEAR_EQUIP", key))
  end
end

--- Ask to take off what is in `slot`.
function Gear:unequip(client, slot)
  if self:mine(client)[slot] then
    client:send(Protocol.encode("GEAR_UNEQUIP", slot))
  end
end

--- The `stat` convention on a client: what a player's clothes do to `name`.
function Gear:stat(value, _client, id, name)
  return value * scale(self.worn[id], name)
end

--- The `resist` convention on a client: what player `id`'s clothes stop.
function Gear:resist(share, _client, id, dtype)
  return through(share, self.worn[id], dtype)
end

Gear.clientMessages = {
  GEAR_STATE = function(_client, args)
    local id = tonumber(args[1])
    if not id then
      return
    end
    local worn = {}
    for i, slot in ipairs(Kinds.slots) do
      local key = args[i + 1]
      local g = key ~= NONE and pieceOf(key)
      if g and g.slot == slot then
        worn[slot] = key
      end
    end
    Gear.worn[id] = worn
  end,
}

-- Server --------------------------------------------------------------------

Gear.sv = nil -- { worn = { player id -> slot -> key } }

local function stateOf(id, worn)
  local list = {}
  for i, slot in ipairs(Kinds.slots) do
    list[i] = worn and worn[slot] or NONE
  end
  return Protocol.encode("GEAR_STATE", id, unpack(list))
end

local function changed(server, player, worn)
  server:broadcast(stateOf(player.id, worn))
  Features.call("serverStatsChanged", server, player)
end

function Gear:serverStart()
  self.sv = { worn = {} }
end

function Gear:serverPlayerJoined(server, player)
  if not self.sv then
    return
  end
  for id, worn in pairs(self.sv.worn) do
    if server.players[id] then
      server:send(player, stateOf(id, worn))
    end
  end
end

function Gear:serverPlayerLeft(_server, player)
  if self.sv then
    self.sv.worn[player.id] = nil
  end
end

--- What `player` wears on the host: slot -> key.
function Gear:serverWorn(player)
  local worn = self.sv and self.sv.worn[player.id]
  if not worn and self.sv then
    worn = {}
    self.sv.worn[player.id] = worn
  end
  return worn or {}
end

--- The `serverStat` convention: what a player's clothes do to `name`.
function Gear:serverStat(value, _server, player, name)
  return value * scale(self.sv and self.sv.worn[player.id], name)
end

--- The `serverResist` convention: what `player`'s clothes stop of a `dtype` hit.
function Gear:serverResist(share, _server, player, dtype)
  return through(share, self.sv and self.sv.worn[player.id], dtype)
end

--- Put `key` on `player` out of their bag; what was in its slot goes back
--- into the bag (the slot the new piece left has room for it). Returns
--- true if it happened.
function Gear:serverEquip(server, player, key)
  local g = pieceOf(key)
  local buildings = Features.byName.buildings
  if not (self.sv and g and buildings and buildings.serverTake and Features.present(player)) then
    return false
  end
  if buildings:serverTake(server, player, "gear-" .. key, 1) < 1 then
    return false
  end
  local worn = self:serverWorn(player)
  local old = worn[g.slot]
  if old then
    buildings:serverGive(server, player, "gear-" .. old, 1)
  end
  worn[g.slot] = key
  changed(server, player, worn)
  return true
end

--- Take off what is in `slot`, back into the bag as an item; refused when
--- the bag is full.
function Gear:serverUnequip(server, player, slot)
  local worn = self:serverWorn(player)
  local key = worn[slot or ""]
  local buildings = Features.byName.buildings
  if not (key and buildings and buildings.serverGive and Features.present(player)) then
    return false
  end
  if buildings:serverGive(server, player, "gear-" .. key, 1) < 1 then
    return false
  end
  worn[slot] = nil
  changed(server, player, worn)
  return true
end

-- Saved worlds (docs/persistence.md) ----------------------------------------

local SAVE_VERSION = 1

--- `player`'s part of a saved world: what they wear, slot -> key, or nil
--- with nothing on.
function Gear:serverSavePlayer(_server, player)
  local worn = self.sv and self.sv.worn[player.id]
  if not (worn and next(worn)) then
    return nil
  end
  local out = {}
  for slot, key in pairs(worn) do
    out[slot] = key
  end
  return { version = SAVE_VERSION, worn = out }
end

--- Put the saved clothes back on; a piece no longer sold (kinds.lua) or in
--- the wrong slot is dropped.
function Gear:serverLoadPlayer(server, player, data)
  if not self.sv or type(data) ~= "table" or (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  if type(data.worn) ~= "table" then
    return
  end
  local worn = {}
  for _, slot in ipairs(Kinds.slots) do
    local key = data.worn[slot]
    local g = pieceOf(key)
    if g and g.slot == slot then
      worn[slot] = key
    end
  end
  self.sv.worn[player.id] = worn
  changed(server, player, worn)
end

Gear.serverMessages = {
  GEAR_EQUIP = function(server, player, args)
    Gear:serverEquip(server, player, args[1])
  end,
  GEAR_UNEQUIP = function(server, player, args)
    Gear:serverUnequip(server, player, args[1])
  end,
}

return Gear
