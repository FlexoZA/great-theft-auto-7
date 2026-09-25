-- Pickups: items lying on the road that a car collects by driving over them.
-- The server owns them: it scatters them on road tiles (from the city map
-- when present), decides who takes one and respawns it elsewhere later.
-- Clients draw them and show a little "+50" when someone grabs one.
--
-- Kinds live in KINDS: "health" (a medkit) heals through the weapons
-- feature, "stamina" (an energy drink) refills the bar through on-foot,
-- and "ammo-<gun>" (an ammo box) puts rounds into the inventory through
-- buildings. A kit that would do nothing -- a medkit at full health, a
-- drink from behind the wheel, a box for a full bag -- stays where it is
-- for whoever can use it.
--
-- Ammo boxes are never scattered; they are dropped, where something died,
-- through Pickups:serverDrop (police drops one for every officer or unit
-- lost), and a drop is gone for good once taken. So is "ability-<key>", an
-- ability lying loose (a boss drops his own when he goes down): the first
-- human over it with room in their bag carries it off as the item.
--
-- Messages
--   server -> all  PK_SPAWN <id> <kind> <x> <y> [<amount>]   (amount: rounds in an ammo box)
--   server -> all  PK_TAKE  <id> <playerId>
--   server -> all  PK_CLEAR                       (the map changed: forget every item)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sounds = require("src.features.pickups.sounds")
local AbilityKinds = require("src.features.abilities.kinds")

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
  local ability = AbilityKinds.byKey[key:match("^ability%-(.+)$")]
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
    label = "+" .. ability.title,
    color = ability.color,
    pitch = 0.6,
  }
end

--- The kind record for a kind key: the fixed ones, or an ammo box or an
--- ability made (and kept) on first sight.
local function kindOf(key)
  local kind = KINDS[key]
  if not kind and key:match("^ammo%-") then
    kind = ammoKind(key)
    KINDS[key] = kind
  elseif not kind and key:match("^ability%-") then
    kind = abilityKind(key)
    KINDS[key] = kind
  end
  return kind
end

KINDS.health = {
    --- Returns true if the player actually used it.
    apply = function(server, player)
      local weapons = Features.byName.weapons
      if weapons and weapons.serverHeal then
        return weapons:serverHeal(server, player, Pickups.healAmount)
      end
      return true -- no weapons feature: take it anyway
    end,
    label = "+" .. 50,
    color = { 0.4, 1, 0.4 },
    pitch = 1,
}
KINDS.stamina = {
    --- Only a body on foot has a bar to fill; a driver leaves it lying.
    apply = function(server, player)
      local onFoot = Features.byName["on-foot"]
      if onFoot and onFoot.serverRestoreStamina then
        return onFoot:serverRestoreStamina(server, player, Pickups.staminaAmount)
      end
      return false -- no on-foot feature: nothing to fill, ever
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
  local ability = AbilityKinds.byKey[key:match("^ability%-(.+)$") or ""]
  local c = ability and ability.color or { 1, 1, 1 }
  local pulse = 0.5 + 0.5 * math.sin(t * 5)
  love.graphics.setColor(c[1], c[2], c[3], 0.15 + pulse * 0.15)
  love.graphics.circle("fill", x, y, 34 + pulse * 6)
  love.graphics.setLineWidth(3)
  for i = 0, 5 do
    local a = t * 1.5 + i * math.pi / 3
    love.graphics.setColor(c[1], c[2], c[3], 0.45)
    love.graphics.line(x + math.cos(a) * 16, y + math.sin(a) * 16, x + math.cos(a) * 30, y + math.sin(a) * 30)
  end
  love.graphics.setLineWidth(1)
  y = y + math.sin(t * 3 + 2.3) * 2
  love.graphics.setColor(0.08, 0.06, 0.05)
  love.graphics.circle("fill", x, y, 13)
  love.graphics.setColor(c)
  love.graphics.circle("fill", x, y, 11)
  love.graphics.setColor(1, 1, 1, 0.8)
  love.graphics.circle("fill", x - 3, y - 4, 3.5)
end

local DRAW = { health = drawHealth, stamina = drawStamina }

--- How a kind is drawn: its own picture, the ammo box for any ammo, or
--- the orb for any ability.
local function drawerOf(key)
  return DRAW[key] or (key:match("^ammo%-") and drawAmmo) or (key:match("^ability%-") and drawAbility) or nil
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
        text = kind and labelOf(kind, it) or "",
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

  local r2 = self.radius * self.radius
  for id, it in pairs(sv.items) do
    for _, player in pairs(server.players) do
      local bx, by, onFoot
      if Features.present(player) then
        bx, by, onFoot = Features.bodyPose(server, player)
      end
      local reach2 = onFoot and self.footRadius * self.footRadius or r2
      if bx and (bx - it.x) ^ 2 + (by - it.y) ^ 2 < reach2 then
        local kind = kindOf(it.kind)
        if kind and kind.apply(server, player, it) then
          sv.items[id] = nil
          server:broadcast(Protocol.encode("PK_TAKE", id, player.id))
          if not it.dropped then
            sv.pending[#sv.pending + 1] = { at = sv.time + self.respawnTime, kind = it.kind }
          end
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

--- For tests.
function Pickups.server()
  return sv
end

return Pickups
