-- Pickups: items lying on the road that a car collects by driving over them.
-- The server owns them: it scatters them on road tiles (from the city map
-- when present), decides who takes one and respawns it elsewhere later.
-- Clients draw them and show a little "+50" when someone grabs one.
--
-- Kinds live in KINDS: "health" (a medkit) heals through the weapons
-- feature, "stamina" (an energy drink) refills the bar through on-foot,
-- and "ammo-<gun>" (an ammo box) puts rounds into the inventory through
-- buildings. A medkit or drink that would do nothing now -- at full health
-- or stamina, a drink from behind the wheel -- goes into the player's quick
-- slot for it instead ("+1 medkit"), until that slot is full; then it stays
-- where it is for whoever can use it, as does a box for a full bag.
--
-- What an enemy leaves behind has one source of truth, here: when one
-- goes down (a simp, a squirrel, a soldier, a police officer or unit) its
-- feature calls Pickups:serverDropEnemy, which drops one thing at most:
-- `dropChance` (65%) of anything, and then one of `drops` by weight: an
-- ammo box three times as likely as a medkit, an energy drink or a kevlar
-- vest, a grenade half as likely. Something that comes in tiers then rolls
-- its tier by `dropTiers`: nearly always common. Ammo boxes are never scattered, only dropped: a box for
-- one of the guns that take ammo (never the bottomless pistol), sized in
-- that gun's magazines (serverDropAmmo). `carriedShare` (half) of them are
-- for a gun the player it is for carries in a weapon slot (whoever the
-- dropper names, else the nearest human), the rest for any gun; either way
-- by each gun's `dropWeight` (guns.lua: rifles and uzis far more often than
-- rockets or minigun belts). A drop is
-- gone for good once taken. So is "ability-<key>", an
-- ability lying loose (a boss drops his own when he goes down): the first
-- human over it with room in their bag carries it off as the item, in the
-- tier it was dropped in ("ability-bigleap@legendary"; tiers/init.lua),
-- which rings the orb in its colour. A material's own key ("iron", "oil";
-- buildings/kinds.lua) is a crate of `amount` of it, spilled by a wrecked
-- delivery truck: the first human over it with room takes what fits (a
-- grenade, medkit or drink into its quick slot first, then the bag), and
-- the rest stays on the ground. So is a factory's goods on
-- their way to the shop ("gun-uzi", "medkit": anything with a
-- `Kinds.worth`); rounds spill as an ammo box.
--
-- "armor-<key>" is a vest lying on the road (armor/kinds.lua; "armor-vest"
-- is a common kevlar vest, "armor-vest@rare" a rare one). A human with no
-- armor on who walks or drives over it wears it at once, whole
-- (armor:serverWearFound); one with a damaged vest on has theirs topped
-- back up to full by it; anyone whose vest is whole leaves it lying.
--
-- How close you have to get is `radius` from a car or `footRadius` on foot,
-- times the player's pickup reach: the one money keeps for koins, which
-- upgrades sells (Money:reachOf). Without money it is 1.
--
-- Messages
--   server -> all  PK_SPAWN <id> <kind> <x> <y> [<amount>]   (amount: rounds in an ammo box, a crate's material)
--   server -> all  PK_TAKE  <id> <playerId> [<item>]   (item: it went into their quick slot as one of these)
--   server -> all  PK_CLEAR                       (the map changed: forget every item)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sounds = require("src.features.pickups.sounds")
local AbilityKinds = require("src.features.abilities.kinds")
local Tiers = require("src.features.tiers")
local Guns = require("src.features.weapons.guns")
local BuildingKinds = require("src.features.buildings.kinds")
local ArmorKinds = require("src.features.armor.kinds")
local Render = require("src.features.buildings.render")

local Pickups = {
  name = "pickups",
  priority = 70, -- draws under cars but over the map (20) and pedestrians (60)
}

-- Tuning ------------------------------------------------------------------
Pickups.count = 6 -- medkits on the map at once
Pickups.staminaCount = 4 -- energy drinks on the map at once
Pickups.respawnTime = 20 -- seconds after one is taken before a new one appears
Pickups.radius = 34 -- px from car centre that counts as driving over it
Pickups.footRadius = 20 -- px from a body on foot that counts as picking it up
Pickups.healAmount = 50
Pickups.staminaAmount = 60
Pickups.ammoAmount = 10 -- rounds in a dropped ammo box unless the dropper says otherwise
-- What an enemy drops (serverDropEnemy): one thing at most, `dropChance` of
-- the time, picked from `drops` by weight ("ammo" is a box for a random gun,
-- `dropMagazines` of its magazines big; "grenade" is one hand grenade). Out
-- of every 100 kills: 30 ammo boxes, 10 each of medkits, drinks and vests,
-- 5 grenades. Add a kind to the list and give it a weight.
Pickups.dropChance = 0.65
Pickups.drops = {
  { kind = "ammo", weight = 3 },
  { kind = "health", weight = 1 },
  { kind = "stamina", weight = 1 },
  { kind = "armor-vest", weight = 1 },
  { kind = "grenade", weight = 0.5 },
}
Pickups.dropMagazines = 1
Pickups.carriedShare = 0.5 -- of ammo boxes, the share for a gun the player it is for carries
-- The tier of a dropped thing that comes in tiers, by weight: nearly always
-- common, a better one much less often (of every 100 about 80, 14, 5 and 1).
Pickups.dropTiers = {
  { tier = "common", weight = 80 },
  { tier = "uncommon", weight = 14 },
  { tier = "rare", weight = 5 },
  { tier = "legendary", weight = 1 },
}

local KINDS = {} -- kind key -> { apply, label, color, pitch }; see kindOf

--- An ammo box for one gun: kind "ammo-<gun key>", the same key the
--- inventory uses for the rounds. It goes into the inventory of whoever
--- walks or drives over it (buildings keeps that); a full bag leaves it.
local function ammoKind(key)
  local gun = key:match("^ammo%-(.+)$")
  return {
    apply = function(server, player, item)
      local buildings = Features.byName.buildings
      if not (buildings and buildings.serverGive) then
        return false -- nowhere to put it
      end
      return buildings:serverGive(server, player, key, item.amount or Pickups.ammoAmount) > 0
    end,
    label = function(item)
      return "+" .. (item.amount or Pickups.ammoAmount) .. " " .. gun .. " ammo"
    end,
    color = { 1, 0.85, 0.35 },
    pitch = 0.8,
  }
end

--- An ability lying loose: kind "ability-<key>", the item a bag carries
--- it as. Only a human picks it up (never a bot driving past), into their
--- inventory through buildings; a full bag leaves it.
local function abilityKind(key)
  local base, tier = Tiers.split(key)
  local ability = tier and AbilityKinds.byKey[base:match("^ability%-(.+)$")]
  if not ability then
    return nil
  end
  return {
    apply = function(server, player)
      local buildings = Features.byName.buildings
      if player.bot or not (buildings and buildings.serverGive) then
        return false
      end
      return buildings:serverGive(server, player, key, 1) > 0
    end,
    label = "+" .. Tiers.named(ability.title, tier),
    color = ability.color,
    pitch = 0.6,
  }
end

--- A crate of a material or of a factory's goods: kind "<item>" ("iron",
--- "gun-uzi"), the item a bag carries it as. Only a human picks it up, into their inventory through
--- buildings; what doesn't fit is left on the spot as a smaller crate.
local function materialKind(key)
  return {
    apply = function(server, player, item)
      local buildings = Features.byName.buildings
      if player.bot or not (buildings and buildings.serverGive) then
        return false
      end
      local amount = item.amount or 1
      local given = buildings:serverQuickGive(server, player, key, amount)
      given = given + buildings:serverGive(server, player, key, amount - given)
      if given > 0 and given < amount then
        Pickups:serverDrop(server, key, item.x, item.y, amount - given)
      end
      return given > 0
    end,
    label = function(item)
      return "+" .. BuildingKinds.label(key, item.amount or 1)
    end,
    color = { 0.85, 0.75, 0.55 },
    pitch = 0.7,
  }
end

--- A vest lying on the road: kind "armor-<key>[@tier]". Whoever runs over
--- it with no armor on wears it there and then (armor:serverWearFound),
--- with a damaged one on is patched up to full; with a whole vest on, or
--- as a bot, they leave it lying.
local function armorKind(key)
  local base, tier = Tiers.split(key)
  local vest = tier and ArmorKinds.byKey[base:match("^armor%-(.+)$")]
  if not vest then
    return nil
  end
  return {
    apply = function(server, player)
      local armor = Features.byName.armor
      return armor ~= nil and armor.serverWearFound ~= nil
        and armor:serverWearFound(server, player, key:sub(7))
    end,
    label = "+" .. Tiers.named(vest.title, tier),
    color = vest.color,
    pitch = 0.7,
  }
end

--- The kind record for a kind key: the fixed ones, or an ammo box, an
--- ability, a material crate or a vest made (and kept) on first sight.
local function kindOf(key)
  local kind = KINDS[key]
  if not kind and key:match("^ammo%-") then
    kind = ammoKind(key)
    KINDS[key] = kind
  elseif not kind and key:match("^ability%-") then
    kind = abilityKind(key)
    KINDS[key] = kind
  elseif not kind and (BuildingKinds.isMaterial(key) or BuildingKinds.worth(key)) then
    kind = materialKind(key)
    KINDS[key] = kind
  elseif not kind and key:match("^armor%-") then
    kind = armorKind(key)
    KINDS[key] = kind
  end
  return kind
end

--- Put one `item` (a medkit, a drink) into `player`'s quick slot for later,
--- if it has room: true, item when it did.
local function stash(server, player, item)
  local buildings = Features.byName.buildings
  if not player.bot and buildings and buildings.serverQuickGive
    and buildings:serverQuickGive(server, player, item, 1) > 0 then
    return true, item
  end
  return false
end

KINDS.health = {
    --- Returns true if the player used it or stashed it (then also "medkit").
    apply = function(server, player)
      local weapons = Features.byName.weapons
      if not (weapons and weapons.serverHeal) then
        return true -- no weapons feature: take it anyway
      end
      if weapons:serverHeal(server, player, Pickups.healAmount) then
        return true
      end
      return stash(server, player, "medkit")
    end,
    label = "+" .. 50,
    color = { 0.4, 1, 0.4 },
    pitch = 1,
}
KINDS.stamina = {
    --- Only a body on foot has a bar to fill; a driver, or someone with a
    --- full bar, stashes it (then also "drink").
    apply = function(server, player)
      local onFoot = Features.byName["on-foot"]
      if onFoot and onFoot.serverRestoreStamina
        and onFoot:serverRestoreStamina(server, player, Pickups.staminaAmount) then
        return true
      end
      return stash(server, player, "drink")
    end,
    label = "+" .. 60 .. " stamina",
    color = { 0.45, 0.85, 1 },
    pitch = 1.25,
}

-- Client state --------------------------------------------------------------
Pickups.items = {} -- id -> { kind, x, y }
Pickups.floats = {} -- { x, y, text, t }
local time = 0

function Pickups:load()
  Sounds.load()
end

-- PK_SPAWN for the whole set arrives in the same burst as START, just before
-- the game state is entered, so nothing is cleared on the way in.
function Pickups:enterGame()
  self.floats = {}
end

function Pickups:exitGame()
  self.items = {}
  self.floats = {}
end

function Pickups:update(dt)
  time = time + dt
  local i = 1
  while i <= #self.floats do
    local f = self.floats[i]
    f.t = f.t - dt
    f.y = f.y - 30 * dt
    if f.t <= 0 then
      table.remove(self.floats, i)
    else
      i = i + 1
    end
  end
end

--- A medkit: white box, red cross, dark outline, bobbing over a soft glow.
local function drawHealth(x, y, t)
  local bob = math.sin(t * 3) * 2
  local pulse = 0.5 + 0.5 * math.sin(t * 4)
  love.graphics.setColor(1, 0.3, 0.3, 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 26 + pulse * 4)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - 12, y - 6 + 6, 24, 20)
  y = y + bob
  love.graphics.setColor(0.10, 0.08, 0.08)
  love.graphics.rectangle("fill", x - 14, y - 12, 28, 24)
  love.graphics.setColor(0.95, 0.95, 0.92)
  love.graphics.rectangle("fill", x - 12, y - 10, 24, 20)
  love.graphics.setColor(0.85, 0.15, 0.15)
  love.graphics.rectangle("fill", x - 3, y - 8, 6, 16)
  love.graphics.rectangle("fill", x - 8, y - 3, 16, 6)
  love.graphics.setColor(0.10, 0.08, 0.08)
  love.graphics.rectangle("fill", x - 4, y - 14, 8, 3) -- handle
end

--- An energy drink: a tall teal can with a yellow bolt on the label,
--- bobbing over a cool glow.
local function drawStamina(x, y, t)
  local bob = math.sin(t * 3 + 1.7) * 2
  local pulse = 0.5 + 0.5 * math.sin(t * 4 + 1.7)
  love.graphics.setColor(0.4, 0.8, 1, 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 24 + pulse * 4)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - 7, y - 8 + 6, 14, 26, 3)
  y = y + bob
  love.graphics.setColor(0.08, 0.10, 0.12)
  love.graphics.rectangle("fill", x - 9, y - 15, 18, 30, 4)
  love.graphics.setColor(0.10, 0.45, 0.50)
  love.graphics.rectangle("fill", x - 7, y - 13, 14, 26, 3)
  love.graphics.setColor(0.75, 0.78, 0.82) -- the lid
  love.graphics.rectangle("fill", x - 6, y - 13, 12, 3)
  love.graphics.setColor(0.06, 0.28, 0.32) -- label band
  love.graphics.rectangle("fill", x - 7, y - 6, 14, 14)
  love.graphics.setColor(1, 0.9, 0.2) -- the bolt
  love.graphics.polygon("fill", x + 2, y - 5, x - 3, y + 1, x, y + 1, x - 2, y + 6, x + 3, y - 1, x, y - 1)
end

--- An ammo box: an olive tin with a brass round on the lid, bobbing over
--- a warm glow.
local function drawAmmo(x, y, t)
  local bob = math.sin(t * 3 + 0.9) * 2
  local pulse = 0.5 + 0.5 * math.sin(t * 4 + 0.9)
  love.graphics.setColor(1, 0.8, 0.3, 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 22 + pulse * 4)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - 11, y - 5 + 6, 22, 16, 2)
  y = y + bob
  love.graphics.setColor(0.12, 0.13, 0.08)
  love.graphics.rectangle("fill", x - 13, y - 10, 26, 20, 3)
  love.graphics.setColor(0.36, 0.42, 0.22)
  love.graphics.rectangle("fill", x - 11, y - 8, 22, 16, 2)
  love.graphics.setColor(0.25, 0.30, 0.15) -- the lid seam
  love.graphics.rectangle("fill", x - 11, y - 2, 22, 2)
  love.graphics.setColor(0.85, 0.65, 0.25) -- a round on the lid
  love.graphics.rectangle("fill", x - 5, y - 6, 10, 3, 1)
  love.graphics.setColor(0.65, 0.35, 0.2)
  love.graphics.rectangle("fill", x + 3, y - 6, 3, 3, 1)
  love.graphics.setColor(0.12, 0.13, 0.08)
  love.graphics.rectangle("fill", x - 4, y - 13, 8, 3) -- handle
end

--- An ability lying loose: an orb in the ability's colour, turning rays
--- round it and a beacon of light going up, so it is seen from afar.
local function drawAbility(x, y, t, key)
  local base, tier = Tiers.split(key)
  local ability = AbilityKinds.byKey[base:match("^ability%-(.+)$") or ""]
  local c = ability and ability.color or { 1, 1, 1 }
  local tc = Tiers.color(tier)
  local pulse = 0.5 + 0.5 * math.sin(t * 5)
  love.graphics.setColor(c[1], c[2], c[3], 0.15 + pulse * 0.15)
  love.graphics.circle("fill", x, y, 34 + pulse * 6)
  love.graphics.setLineWidth(3)
  for i = 0, 5 do
    local a = t * 1.5 + i * math.pi / 3
    love.graphics.setColor(c[1], c[2], c[3], 0.45)
    love.graphics.line(x + math.cos(a) * 16, y + math.sin(a) * 16, x + math.cos(a) * 30, y + math.sin(a) * 30)
  end
  -- A ring in its tier's colour round the whole thing.
  love.graphics.setLineWidth(2)
  love.graphics.setColor(tc[1], tc[2], tc[3], 0.6 + pulse * 0.4)
  love.graphics.circle("line", x, y, 36 + pulse * 4)
  love.graphics.setLineWidth(1)
  y = y + math.sin(t * 3 + 2.3) * 2
  love.graphics.setColor(0.08, 0.06, 0.05)
  love.graphics.circle("fill", x, y, 13)
  love.graphics.setColor(c)
  love.graphics.circle("fill", x, y, 11)
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.circle("fill", x - 3, y - 4, 3.5)
end

--- A crate of a material: a wooden pallet with the material heaped on
--- it, the picture the inventory draws for it.
local function drawMaterial(x, y, t, key)
  local bob = math.sin(t * 3 + 0.4) * 2
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x - 14, y - 8 + 6, 28, 22, 2)
  y = y + bob
  love.graphics.setColor(0.36, 0.25, 0.14)
  love.graphics.rectangle("fill", x - 16, y - 12, 32, 26, 3)
  love.graphics.setColor(0.6, 0.44, 0.25)
  love.graphics.rectangle("fill", x - 14, y - 10, 28, 22, 2)
  Render.itemIcon(key, x, y)
end

--- A vest on the road: the bag's picture of it, bobbing a little over a
--- soft glow in the vest's colour, ringed in its tier's.
local function drawVest(x, y, t, key)
  local base, tier = Tiers.split(key)
  local vest = ArmorKinds.byKey[base:match("^armor%-(.+)$") or ""]
  local c = vest and vest.color or { 0.5, 0.6, 0.9 }
  local tc = Tiers.color(tier)
  local pulse = 0.5 + 0.5 * math.sin(t * 4)
  love.graphics.setColor(c[1], c[2], c[3], 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 24 + pulse * 4)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(tc[1], tc[2], tc[3], 0.5 + pulse * 0.4)
  love.graphics.circle("line", x, y, 24 + pulse * 3)
  love.graphics.setLineWidth(1)
  love.graphics.push()
  love.graphics.translate(x, y + math.sin(t * 3 + 1.1) * 2)
  love.graphics.scale(1.2)
  Render.itemIcon(base, 0, 0)
  love.graphics.pop()
end

--- A grenade dropped by an enemy: an olive pineapple with its lever and
--- pin, bobbing over a warm glow like an ammo box.
local function drawGrenade(x, y, t)
  local bob = math.sin(t * 3 + 1.7) * 2
  local pulse = 0.5 + 0.5 * math.sin(t * 4 + 1.7)
  love.graphics.setColor(1, 0.8, 0.3, 0.12 + pulse * 0.12)
  love.graphics.circle("fill", x, y, 20 + pulse * 4)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x, y + 10, 9, 4)
  y = y + bob
  love.graphics.setColor(0.12, 0.13, 0.08)
  love.graphics.ellipse("fill", x, y + 1, 10, 11)
  love.graphics.setColor(0.36, 0.42, 0.22)
  love.graphics.ellipse("fill", x, y + 1, 8, 9)
  love.graphics.setColor(0.25, 0.30, 0.15) -- the segments
  love.graphics.rectangle("fill", x - 8, y - 2, 16, 1.5)
  love.graphics.rectangle("fill", x - 8, y + 3, 16, 1.5)
  love.graphics.rectangle("fill", x - 0.75, y - 8, 1.5, 18)
  love.graphics.setColor(0.55, 0.55, 0.5) -- the fuse head and lever
  love.graphics.rectangle("fill", x - 3, y - 12, 6, 4, 1)
  love.graphics.rectangle("fill", x + 2, y - 11, 3, 10, 1)
  love.graphics.setColor(0.85, 0.65, 0.25) -- the pin's ring
  love.graphics.setLineWidth(1.5)
  love.graphics.circle("line", x - 6, y - 11, 3)
  love.graphics.setLineWidth(1)
end

local DRAW = { health = drawHealth, stamina = drawStamina, grenade = drawGrenade }

--- How a kind is drawn: its own picture, the ammo box for any ammo, the
--- orb for any ability, a crate for a material, the vest for any armor.
local function drawerOf(key)
  return DRAW[key] or (key:match("^ammo%-") and drawAmmo) or (key:match("^ability%-") and drawAbility)
    or ((BuildingKinds.isMaterial(key) or BuildingKinds.worth(key)) and drawMaterial)
    or (key:match("^armor%-") and drawVest) or nil
end

--- What floats up when a kind is taken.
local function labelOf(kind, item)
  if type(kind.label) == "function" then
    return kind.label(item)
  end
  return kind.label
end

function Pickups:drawBelowCars()
  for _, it in pairs(self.items) do
    local draw = drawerOf(it.kind)
    if draw then
      draw(it.x, it.y, time, it.kind)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Pickups:drawAboveCars()
  love.graphics.setFont(UI.fonts.body)
  for _, f in ipairs(self.floats) do
    local c = f.color
    love.graphics.setColor(c[1], c[2], c[3], math.min(1, f.t))
    love.graphics.printf(f.text, f.x - 60, f.y, 120, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Pickups.clientMessages = {
  PK_SPAWN = function(_client, args)
    local id, kind = tonumber(args[1]), args[2]
    local x, y = tonumber(args[3]), tonumber(args[4])
    if id and kind and x and y then
      Pickups.items[id] = { kind = kind, x = x, y = y, amount = tonumber(args[5]) }
    end
  end,
  PK_CLEAR = function()
    Pickups.items = {}
  end,
  PK_TAKE = function(client, args)
    local id, by = tonumber(args[1]), tonumber(args[2])
    local stashed = args[3] ~= "" and args[3] or nil
    local it = id and Pickups.items[id]
    if it then
      Pickups.items[id] = nil
      local kind = kindOf(it.kind)
      Sounds.play(it.x, it.y, kind and kind.pitch)
      -- Over the body that took it, which is not always a car.
      local fx, fy = it.x, it.y
      if by then
        local px, py = client:pose(by)
        if px then
          fx, fy = px, py
        end
      end
      Pickups.floats[#Pickups.floats + 1] = {
        x = fx,
        y = fy - 30,
        text = stashed and "+" .. BuildingKinds.label(stashed, 1) or kind and labelOf(kind, it) or "",
        color = kind and kind.color or { 1, 1, 1 },
        t = 1.2,
      }
    end
  end,
}

-- Server ----------------------------------------------------------------

local sv = nil -- { items = { id -> { kind, x, y, amount, dropped } }, nextId, pending = { { at, kind } } , time }

--- A random spot on a road tile (city map) or in a ring around the origin.
local function roadSpot()
  local city = Features.byName["city-map"]
  if city and city.randomRoadPoint then
    local x, y = city:randomRoadPoint()
    if x then
      return x, y
    end
  end
  local a = love.math.random() * 2 * math.pi
  local d = 300 + love.math.random() * 700
  return math.cos(a) * d, math.sin(a) * d
end

local function farFromCars(server, x, y)
  for _, p in pairs(server.players) do
    if p.body then
      local bx, by = Features.bodyPose(server, p)
      if (bx - x) ^ 2 + (by - y) ^ 2 < 200 ^ 2 then
        return false
      end
    end
  end
  return true
end

local function spawnOne(server, kind)
  local x, y
  for _ = 1, 20 do
    x, y = roadSpot()
    if farFromCars(server, x, y) then
      break
    end
  end
  local id = sv.nextId
  sv.nextId = id + 1
  sv.items[id] = { kind = kind, x = x, y = y }
  server:broadcast(Protocol.encode("PK_SPAWN", id, kind, ("%.0f"):format(x), ("%.0f"):format(y)))
end

--- Drop a pickup of `kind` at (x, y) right now: an ammo box where an
--- officer fell, say. `amount` is what an ammo box holds (ammoAmount when
--- not given). A drop never respawns once taken. Other features reach
--- this via Features.byName.pickups (police does). Returns the item's id,
--- or nil before a game.
function Pickups:serverDrop(server, kind, x, y, amount)
  if not (sv and kindOf(kind)) then
    return nil
  end
  local id = sv.nextId
  sv.nextId = id + 1
  sv.items[id] = { kind = kind, x = x, y = y, amount = amount, dropped = true }
  server:broadcast(Protocol.encode("PK_SPAWN", id, kind, ("%.0f"):format(x), ("%.0f"):format(y), amount or ""))
  return id
end

--- The human a drop at (x, y) is for: player `by` if that is one, else
--- the nearest one in the world.
local function recipient(server, x, y, by)
  local p = by and server.players[by]
  if p and not p.bot then
    return p
  end
  local best, bestD2
  for _, q in pairs(server.players) do
    if not q.bot and Features.present(q) then
      local qx, qy = Features.bodyPose(server, q)
      local d2 = (qx - x) ^ 2 + (qy - y) ^ 2
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = q, d2
      end
    end
  end
  return best
end

--- One of the guns that take ammo, by `dropWeight`; only those `player`
--- carries in a weapon slot when `player` is given. Nil if there is none.
local function ammoGun(player)
  local weapons = player and Features.byName.weapons
  local list = {}
  for _, gun in ipairs(Guns.list) do
    if not gun.bottomless and (not player or (weapons and weapons:serverOwns(player, gun.index))) then
      list[#list + 1] = { gun = gun, weight = gun.dropWeight or 1 }
    end
  end
  if #list == 0 then
    return nil
  end
  local total = 0
  for _, e in ipairs(list) do
    total = total + e.weight
  end
  local roll = love.math.random() * total
  for _, e in ipairs(list) do
    roll = roll - e.weight
    if roll < 0 then
      return e.gun
    end
  end
  return list[#list].gun
end

--- Drop a box of ammo at (x, y) for one of the guns that take ammo:
--- `carriedShare` of the time one that the player it is for (`by`, or the
--- nearest human) carries, otherwise any, by `dropWeight` either way.
--- `magazines` of whatever it turns out to be (0.6 of an uzi's is 18
--- rounds, of a shotgun's 4 shells, of the launcher's one rocket), so a box
--- means the same whichever gun it is for. Returns the item's id, or nil
--- when there is no gun to drop for.
function Pickups:serverDropAmmo(server, x, y, magazines, by)
  local gun
  if love.math.random() < self.carriedShare then
    gun = ammoGun(recipient(server, x, y, by)) -- nil for somebody with only the pistol
  end
  gun = gun or ammoGun(nil)
  if not gun then
    return nil
  end
  local n = gun.tank and 1 or math.floor(magazines * gun.magazine + 0.5) -- one fuel can fills a tank
  return self:serverDrop(server, "ammo-" .. gun.key, x, y, math.max(1, n))
end

--- One entry of `list` ({ weight = n, ... }), picked by weight; nil for
--- an empty list.
local function byWeight(list)
  local total = 0
  for _, e in ipairs(list) do
    total = total + e.weight
  end
  local roll = love.math.random() * total
  for _, e in ipairs(list) do
    roll = roll - e.weight
    if roll < 0 then
      return e
    end
  end
  return list[#list]
end

--- A tier for a dropped thing, by `dropTiers`' weights.
local function dropTier()
  local t = byWeight(Pickups.dropTiers)
  return t and t.tier or Tiers.DEFAULT
end

--- An enemy went down at (x, y): maybe it leaves something. One thing at
--- most: `dropChance` of anything, then one of `drops` by weight,
--- in a tier by `dropTiers` if it comes in tiers. Every enemy calls this
--- (Karen's simps, the hunt's squirrels, D-Day's soldiers, the police's
--- officers and units), so the odds live here and nowhere else. `by`
--- (optional) is who it is for (the killer); the nearest human otherwise.
--- Returns the item's id, or nil when nothing dropped.
function Pickups:serverDropEnemy(server, x, y, by)
  if #self.drops == 0 or love.math.random() >= self.dropChance then
    return nil
  end
  local kind = byWeight(self.drops).kind
  if kind == "ammo" then
    return self:serverDropAmmo(server, x, y, self.dropMagazines, by)
  end
  if Tiers.tiered(kind) then
    kind = Tiers.join(kind, dropTier())
  end
  return self:serverDrop(server, kind, x, y)
end

function Pickups:serverStart(server)
  sv = { items = {}, nextId = 1, pending = {}, time = 0 }
  for _ = 1, self.count do
    spawnOne(server, "health")
  end
  for _ = 1, self.staminaCount do
    spawnOne(server, "stamina")
  end
end

--- Someone joining mid-game sees what is already lying about.
function Pickups:serverPlayerJoined(server, player)
  if not sv or player.bot then
    return
  end
  for id, it in pairs(sv.items) do
    server:send(player, Protocol.encode("PK_SPAWN", id, it.kind, ("%.0f"):format(it.x), ("%.0f"):format(it.y),
      it.amount or ""))
  end
end

--- Everyone was moved to another map (city-map's `mapChanged`; the host
--- passes `server`, clients get nil): what lay on the old roads is swept
--- and a fresh set is scattered over the new map.
function Pickups:mapChanged(_map, server)
  if not (server and sv) then
    return
  end
  sv.items, sv.pending = {}, {}
  server:broadcast(Protocol.encode("PK_CLEAR"))
  for _ = 1, self.count do
    spawnOne(server, "health")
  end
  for _ = 1, self.staminaCount do
    spawnOne(server, "stamina")
  end
end

function Pickups:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt

  local money = Features.byName.money
  for id, it in pairs(sv.items) do
    for _, player in pairs(server.players) do
      local bx, by, onFoot
      if Features.present(player) then
        bx, by, onFoot = Features.bodyPose(server, player)
      end
      local scale = money and money.reachOf and money:reachOf(player.id) or 1
      local reach = (onFoot and self.footRadius or self.radius) * scale
      if bx and (bx - it.x) ^ 2 + (by - it.y) ^ 2 < reach * reach then
        local kind = kindOf(it.kind)
        local took, stashed = false, nil
        if kind then
          took, stashed = kind.apply(server, player, it)
        end
        if took then
          self:serverTake(server, id, player.id, stashed)
          break
        end
      end
    end
  end

  local i = 1
  while i <= #sv.pending do
    if sv.time >= sv.pending[i].at then
      spawnOne(server, table.remove(sv.pending, i).kind)
    else
      i = i + 1
    end
  end
end

--- Pickup `id` is taken by player `byId` (0 for somebody who isn't one:
--- an enemy helping itself): gone from the ground on every screen, and one
--- of the map's own comes back in time. `stashed` is the item it went into
--- their quick slot as, for the "+1 medkit". Doesn't apply it; returns the item
--- ({ kind, x, y, amount }) or nil if it was already gone.
function Pickups:serverTake(server, id, byId, stashed)
  local it = sv and sv.items[id]
  if not it then
    return nil
  end
  sv.items[id] = nil
  server:broadcast(Protocol.encode("PK_TAKE", id, byId or 0, stashed or ""))
  if not it.dropped then
    sv.pending[#sv.pending + 1] = { at = sv.time + self.respawnTime, kind = it.kind }
  end
  return it
end

--- The nearest pickup lying within `range` of (x, y) whose kind is one of
--- `kinds` (a set: { health = true }): its id and the item, or nil.
function Pickups:serverNearest(x, y, range, kinds)
  local best, bestId, bestD2 = nil, nil, range * range
  for id, it in pairs(sv and sv.items or {}) do
    local d2 = (it.x - x) ^ 2 + (it.y - y) ^ 2
    if kinds[it.kind] and d2 <= bestD2 then
      best, bestId, bestD2 = it, id, d2
    end
  end
  return bestId, best
end

--- Is pickup `id` still lying there?
function Pickups:serverHas(id)
  return sv ~= nil and sv.items[id] ~= nil
end

--- For tests.
function Pickups.server()
  return sv
end

return Pickups
