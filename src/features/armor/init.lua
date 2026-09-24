-- Armor: a vest worn in the armor slot of the inventory screen soaks up
-- damage to your body until its points run out; only then does health
-- start to go. A permanent bar in the bottom-left row shows what is left
-- of it (empty and grey with nothing on).
--
-- An armor item ("armor-<key>", kinds.lua; the shop sells them) is dragged
-- from the bag onto the armor slot to put it on (ARM_EQUIP: the host takes
-- the item and the vest starts whole; a vest already worn goes back into
-- the bag if it is still whole, and is thrown away if not) and from the
-- slot into the bag to take it off (ARM_UNEQUIP: back as an item while it
-- is whole; a damaged one can't be put back and is thrown away). Death
-- takes it with you.
--
-- Weapons asks every feature `serverAbsorbDamage(amount, server, victim)`
-- through Features.reduce before a body takes damage; this answers what is
-- left after the vest has taken its share.
--
-- Messages
--   client -> server  ARM_EQUIP   <kind>
--   client -> server  ARM_UNEQUIP
--   server -> all     ARM_STATE   <id> <kind|-> <points> <max>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Kinds = require("src.features.armor.kinds")

local Armor = {
  name = "armor",
}

Armor.kinds = Kinds
Armor.hudSlot = 3 -- the bottom-left row of stat bars: health 0, stamina 1, dodge 2, armor 3

local NONE = "-"
local FLASH = 0.25 -- seconds the bar flares after a hit

-- Client --------------------------------------------------------------------

Armor.worn = {} -- player id -> { kind, points, max }, as the host told us
Armor.flash = 0

function Armor:exitGame()
  self.worn, self.flash = {}, 0
end

--- What I am wearing: { kind, points, max } or nil.
function Armor:mine(client)
  return self.worn[client.myId]
end

--- The kind table of what I am wearing, or nil.
function Armor:wornKind(client)
  local w = self:mine(client)
  return w and Kinds.byKey[w.kind] or nil
end

--- Ask to put on the armor item I carry for `kind` (the inventory screen
--- does, on a drag).
function Armor:equip(client, kind)
  if Kinds.byKey[kind] then
    client:send(Protocol.encode("ARM_EQUIP", kind))
  end
end

--- Ask to take off what I am wearing.
function Armor:unequip(client)
  if self:mine(client) then
    client:send(Protocol.encode("ARM_UNEQUIP"))
  end
end

function Armor:update(dt)
  self.flash = math.max(0, self.flash - dt)
end

--- The armor bar, always there: blue and full of points with a vest on,
--- empty and grey without.
function Armor:drawHUD(client)
  local w = self:mine(client)
  local kind = w and Kinds.byKey[w.kind]
  if kind then
    local c = kind.color
    local k = self.flash / FLASH
    local color = { c[1] + (1 - c[1]) * k, c[2] + (1 - c[2]) * k, c[3] }
    UI.drawStatBar(self.hudSlot, "armor", w.points / w.max, color, ("%d"):format(w.points), { 1, 1, 1 })
  else
    UI.drawStatBar(self.hudSlot, "armor", 0, { 0.5, 0.5, 0.55 }, "0", { 0.6, 0.6, 0.65 }, nil, 0.6)
  end
  love.graphics.setColor(1, 1, 1)
end

Armor.clientMessages = {
  ARM_STATE = function(client, args)
    local id, kind = tonumber(args[1]), args[2]
    local points, max = tonumber(args[3]), tonumber(args[4])
    if not (id and points and max) then
      return
    end
    local before = Armor.worn[id]
    if kind == NONE or not Kinds.byKey[kind] then
      Armor.worn[id] = nil
    else
      Armor.worn[id] = { kind = kind, points = points, max = max }
    end
    if id == client.myId and before and before.kind == kind and points < before.points then
      Armor.flash = FLASH
    end
  end,
}

-- Server --------------------------------------------------------------------

Armor.sv = nil -- { worn = { player id -> { kind, points, max } } }

local function tell(server, player, w)
  server:broadcast(Protocol.encode("ARM_STATE", player.id, w and w.kind or NONE, w and w.points or 0,
    w and w.max or 0))
end

function Armor:serverStart()
  self.sv = { worn = {} }
end

function Armor:serverPlayerJoined(server, player)
  if not self.sv then
    return
  end
  for id, w in pairs(self.sv.worn) do
    local p = server.players[id]
    if p then
      server:send(player, Protocol.encode("ARM_STATE", id, w.kind, w.points, w.max))
    end
  end
end

function Armor:serverPlayerLeft(_server, player)
  if self.sv then
    self.sv.worn[player.id] = nil
  end
end

--- What `player` wears on the host: { kind, points, max } or nil.
function Armor:serverWorn(player)
  return self.sv and self.sv.worn[player.id] or nil
end

--- The `serverAbsorbDamage` convention: the vest takes what it can of
--- `amount` and what is left goes on to the body. A vest that runs out is
--- destroyed.
function Armor:serverAbsorbDamage(amount, server, victim)
  local w = self:serverWorn(victim)
  if not w or amount <= 0 then
    return amount
  end
  local taken = math.min(w.points, amount)
  w.points = w.points - taken
  if w.points <= 0 then
    self.sv.worn[victim.id] = nil
    tell(server, victim, nil)
  else
    tell(server, victim, w)
  end
  return amount - taken
end

--- Death takes the vest with it.
function Armor:serverKill(server, kill)
  if not (self.sv and kill.victim and kill.onFoot) then
    return
  end
  local player = server.players[kill.victim]
  if player and self.sv.worn[kill.victim] then
    self.sv.worn[kill.victim] = nil
    tell(server, player, nil)
  end
end

--- Put `kind` on `player` out of their bag. A vest already on goes back
--- into the bag if whole (the slot the new one left has room for it) and
--- is thrown away if not. Returns true if it happened.
function Armor:serverEquip(server, player, kind)
  local a = Kinds.byKey[kind or ""]
  local buildings = Features.byName.buildings
  if not (self.sv and a and buildings and buildings.serverTake and Features.present(player)) then
    return false
  end
  if buildings:serverTake(server, player, "armor-" .. kind, 1) < 1 then
    return false
  end
  local old = self.sv.worn[player.id]
  if old and old.points >= old.max then
    buildings:serverGive(server, player, "armor-" .. old.kind, 1)
  end
  local max = math.max(1, math.floor(a.points * Features.reduce("serverStat", 1, server, player, "armor") + 0.5))
  self.sv.worn[player.id] = { kind = kind, points = max, max = max }
  tell(server, player, self.sv.worn[player.id])
  return true
end

--- Clothes changed (gear): a vest holds as many points as they now allow,
--- what is left of it scaled along.
function Armor:serverStatsChanged(server, player)
  local w = self:serverWorn(player)
  local a = w and Kinds.byKey[w.kind]
  if not a then
    return
  end
  local max = math.max(1, math.floor(a.points * Features.reduce("serverStat", 1, server, player, "armor") + 0.5))
  if max ~= w.max then
    w.points = math.max(1, math.floor(w.points * max / w.max + 0.5))
    w.max = max
    tell(server, player, w)
  end
end

--- Take off what `player` wears: back into the bag as an item while it is
--- whole (refused when the bag is full), thrown away once damaged.
function Armor:serverUnequip(server, player)
  local w = self:serverWorn(player)
  local buildings = Features.byName.buildings
  if not (w and buildings and buildings.serverGive and Features.present(player)) then
    return false
  end
  if w.points >= w.max and buildings:serverGive(server, player, "armor-" .. w.kind, 1) < 1 then
    return false -- no room: it stays on
  end
  self.sv.worn[player.id] = nil
  tell(server, player, nil)
  return true
end

Armor.serverMessages = {
  ARM_EQUIP = function(server, player, args)
    Armor:serverEquip(server, player, args[1])
  end,
  ARM_UNEQUIP = function(server, player)
    Armor:serverUnequip(server, player)
  end,
}

return Armor
