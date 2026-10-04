-- Grenades: hand grenades, thrown on foot and going off where they land.
--
-- Grenades are an item ("grenade", five to a stack) carried in a quick slot
-- of their own beside the medkits and drinks (buildings.usables; drag a
-- stack there on the inventory screen). Their key (T) readies one: the
-- landing spot follows the cursor, kept within `range` of you and short of
-- the first wall in the way, with the blast's reach drawn round it, and the
-- fire button throws it there (weapons leaves the gun alone meanwhile: the
-- `fireTaken` convention). It stays readied for the next one until the key
-- again, right-click, a weapon key or the last grenade puts it away. Not
-- from a car.
--
-- The throw is BLD_USE grenade <x> <y>: buildings checks the slot and the
-- cooldown, takes one out and asks `serverThrow`, which works the landing
-- spot out again on the host and lobs it. It flies in an arc over people
-- and cars for a time that grows with the distance and goes off on landing
-- with weapons' blast (Weapons:explode, explosive damage; it hurts the
-- thrower too). Grenades have no tiers: they are used up, like ammo.
--
-- Messages
--   server -> all  GRN_THROW <id> <owner> <ox> <oy> <x> <y> <flight>  (one is in the air from o to (x, y))

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local Render = require("src.features.buildings.render")
local Sounds = require("src.features.grenades.sounds")

local Grenades = {
  name = "grenades",
  priority = 951, -- just after weapons
}

-- Tuning ------------------------------------------------------------------
Grenades.range = 400 -- px; furthest a grenade is thrown
Grenades.speed = 520 -- px/s over the ground in the air
Grenades.minFlight = 0.3 -- seconds in the air at the least (one dropped at your feet)
Grenades.blast = { radius = 100, damage = 80, soft = 4, type = "explosive" } -- as a gun's `blast` (guns.lua)
Grenades.arc = 0.3 -- how high it flies, as a share of the distance (drawn only)

local STEP = 6 -- px between the wall checks along the throw
local NOT_IN_CAR = "Get out of the car to throw a grenade."

-- Client state --------------------------------------------------------------
Grenades.readied = false -- is a grenade in hand, waiting for the fire button?
Grenades.flying = {} -- id -> { ox, oy, x, y, t, flight }
local fireSpent = false -- the fire button threw one and is still down
local camera = nil
local lastGun = nil -- the gun in hand last frame: switching guns puts the grenade away

local sv = nil -- host: { flying = { { id, owner, ox, oy, x, y, t, flight } }, nextId }

--- Is (x, y) solid for a grenade? The same walls that stop bullets
--- (`blocksPoint`), on the host and on every client.
local function blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- Where a grenade thrown from (ox, oy) towards (tx, ty) comes down: the
--- target pulled back to within `range`, or the last clear point short of
--- the first wall in the way (it bounces off and drops there).
function Grenades.landing(ox, oy, tx, ty)
  local dx, dy = tx - ox, ty - oy
  local d = math.sqrt(dx * dx + dy * dy)
  if d > Grenades.range then
    dx, dy, d = dx / d * Grenades.range, dy / d * Grenades.range, Grenades.range
  end
  local steps = math.ceil(d / STEP)
  local lx, ly = ox, oy
  for i = 1, steps do
    local x, y = ox + dx * i / steps, oy + dy * i / steps
    if blocked(x, y) then
      return lx, ly
    end
    lx, ly = x, y
  end
  return lx, ly
end

--- Seconds a grenade is in the air from (ox, oy) to (x, y).
function Grenades.flightTime(ox, oy, x, y)
  return math.max(Grenades.minFlight, math.sqrt((x - ox) ^ 2 + (y - oy) ^ 2) / Grenades.speed)
end

local function buildings()
  return Features.byName.buildings
end

local function mouseToWorld(ox, oy)
  local mx, my = love.mouse.getPosition()
  local w, h = love.graphics.getDimensions()
  local cx, cy, s = ox, oy, 1
  if camera then
    cx, cy, s = camera.x, camera.y, camera.scale or 1
  end
  return cx + (mx - w / 2) / s, cy + (my - h / 2) / s
end

--- Where my grenade would land now, from where I stand towards the cursor,
--- and where I stand; nil while I am out of the world.
function Grenades:target(client)
  local ox, oy = client:myPose()
  if not ox then
    return nil
  end
  local tx, ty = mouseToWorld(ox, oy)
  local x, y = Grenades.landing(ox, oy, tx, ty)
  return x, y, ox, oy
end

--- May I have a grenade in hand: on foot, in the world, with no screen or
--- menu up?
local function canReady(client)
  return client:myPose() ~= nil and not client:myVehicle() and not Controls.suspended
    and not Features.any("pointerTaken", client) and not Features.any("menuOpen", client)
end

function Grenades:enterGame()
  self.readied, self.flying, fireSpent, lastGun = false, {}, false, nil
end

function Grenades:exitGame()
  self.readied, self.flying, fireSpent = false, {}, false
end

function Grenades:mapChanged()
  self.flying = {}
  if sv then
    sv.flying = {}
  end
end

--- The `fireTaken` convention: the fire button throws while a grenade is
--- readied, and does nothing more until it is let go after a throw.
function Grenades:fireTaken()
  return self.readied or (fireSpent and Controls.isDown("fire"))
end

--- The grenade key readies one (or puts it away); a weapon key puts it away
--- and lets weapons take that gun out.
function Grenades:keypressed(key, client)
  if not Controls.is("grenade", key) then
    if self.readied and not Features.any("menuOpen", client) then
      local weapons = Features.byName.weapons
      for i = 1, weapons and weapons.slotCount or 0 do
        if Controls.is("weapon-" .. i, key) then
          self.readied = false
        end
      end
    end
    return
  end
  local b = buildings()
  if self.readied then
    self.readied = false
  elseif not b or not canReady(client) then
    if b and client:myVehicle() then
      b:notice(NOT_IN_CAR)
    end
  elseif b:quickCount("grenade") < 1 then
    b:notice(b:unusable("grenade"))
  else
    self.readied = true
    local abilities = Features.byName.abilities
    if abilities and abilities.selecting and abilities:selecting() then
      abilities.aiming = nil -- one thing on the fire button at a time
    end
  end
end

--- The fire button throws the grenade in hand at the landing spot.
function Grenades:mousepressed(_x, _y, button, client)
  if not (self.readied and Controls.isMouse("fire", button)) then
    return
  end
  fireSpent = true
  local b = buildings()
  local why = b and b:unusable("grenade")
  if why then
    b:notice(why)
    return
  elseif not b or Features.any("held", client, client.myId) then
    return -- frozen: no throwing either
  end
  local x, y = self:target(client)
  if x then
    client:send(Protocol.encode("BLD_USE", "grenade", ("%.1f"):format(x), ("%.1f"):format(y)))
  end
end

function Grenades:update(dt, client, cam)
  camera = cam
  for id, g in pairs(self.flying) do
    g.t = g.t + dt
    if g.t >= g.flight then
      self.flying[id] = nil -- weapons' WPN_BOOM shows the blast
    end
  end
  if fireSpent and not Controls.isDown("fire") then
    fireSpent = false
  end
  local weapons, abilities, b = Features.byName.weapons, Features.byName.abilities, buildings()
  local gun = weapons and weapons.gun
  if self.readied and (not canReady(client) or not b or b:quickCount("grenade") < 1
      or Controls.isDown("ability-cancel") or gun ~= lastGun
      or (abilities and abilities.selecting and abilities:selecting())) then
    self.readied = false -- in a car, a screen came up, none left, changed their mind or picked something else
  end
  lastGun = gun
end

--- A grenade `g` in the air: its shadow on the ground under it and the
--- grenade itself up the arc, tumbling, bigger the higher it is.
local function drawFlying(g)
  local k = math.min(1, g.t / g.flight)
  local gx, gy = g.ox + (g.x - g.ox) * k, g.oy + (g.y - g.oy) * k
  local d = math.sqrt((g.x - g.ox) ^ 2 + (g.y - g.oy) ^ 2)
  local height = 4 * k * (1 - k) * (10 + d * Grenades.arc)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", gx, gy, 5, 3)
  love.graphics.push()
  love.graphics.translate(gx, gy - height)
  love.graphics.rotate(g.t * 14)
  Render.grenade(0, 0, 0.45 + height / 160)
  love.graphics.pop()
end

--- My aim while a grenade is readied: how far I can throw, the arc it
--- would fly as a dotted line, and the ground the blast would cover.
local function drawAim(self, client)
  local x, y, ox, oy = self:target(client)
  if not x then
    return
  end
  local c = buildings().usableByItem.grenade.color
  local pulse = 0.5 + 0.5 * math.sin(love.timer.getTime() * 8)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(c[1], c[2], c[3], 0.15)
  love.graphics.circle("line", ox, oy, self.range, 64)
  -- The arc, as dots, seen from above: lifted off the line by its height.
  local d = math.sqrt((x - ox) ^ 2 + (y - oy) ^ 2)
  local n = math.max(2, math.floor(d / 14))
  love.graphics.setColor(1, 1, 1, 0.55)
  for i = 1, n - 1 do
    local k = i / n
    local h = 4 * k * (1 - k) * (10 + d * self.arc)
    love.graphics.circle("fill", ox + (x - ox) * k, oy + (y - oy) * k - h, 2, 8)
  end
  -- Where it comes down and what goes with it.
  local R = self.blast.radius
  love.graphics.setColor(1, 0.35, 0.15, 0.1 + 0.06 * pulse)
  love.graphics.circle("fill", x, y, R, 48)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.4, 0.2, 0.6 + 0.3 * pulse)
  love.graphics.circle("line", x, y, R, 48)
  love.graphics.setColor(1, 0.9, 0.6, 0.9)
  love.graphics.line(x - 8, y, x + 8, y)
  love.graphics.line(x, y - 8, x, y + 8)
  love.graphics.setLineWidth(1)
end

function Grenades:drawAboveCars(client)
  for _, g in pairs(self.flying) do
    drawFlying(g)
  end
  if self.readied and buildings() then
    drawAim(self, client)
  end
  love.graphics.setColor(1, 1, 1)
end

function Grenades:load()
  Sounds.load()
end

Grenades.clientMessages = {
  GRN_THROW = function(_client, args)
    local id = tonumber(args[1])
    local ox, oy, x, y = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    local flight = tonumber(args[7])
    if id and ox and oy and x and y and flight then
      Grenades.flying[id] = { ox = ox, oy = oy, x = x, y = y, t = 0, flight = flight }
      Sounds.play("throw", ox, oy)
    end
  end,
}

-- Server ------------------------------------------------------------------

function Grenades:serverStart()
  sv = { flying = {}, nextId = 1 }
end

--- `player` throws a grenade at (x, y) (buildings has checked their slot
--- and will take one out when this answers true). Only on foot, in the
--- world and not held; the landing spot is worked out here again, never
--- taken from the client.
function Grenades:serverThrow(server, player, x, y)
  if not (sv and x and y and math.abs(x) < 1e7 and math.abs(y) < 1e7) then
    return false -- missing, NaN or silly
  elseif player.vehicle or not Features.present(player) or Features.any("serverHeld", server, player) then
    return false
  end
  local ox, oy = Features.bodyPose(server, player)
  local lx, ly = Grenades.landing(ox, oy, x, y)
  local g = {
    id = sv.nextId, owner = player.id, ox = ox, oy = oy, x = lx, y = ly, t = 0,
    flight = Grenades.flightTime(ox, oy, lx, ly),
  }
  sv.nextId = sv.nextId + 1
  sv.flying[#sv.flying + 1] = g
  server:broadcast(Protocol.encode("GRN_THROW", g.id, g.owner, ("%.1f"):format(ox), ("%.1f"):format(oy),
    ("%.1f"):format(lx), ("%.1f"):format(ly), ("%.3f"):format(g.flight)))
  return true
end

--- Where grenades are coming down, for enemies that get out of the way
--- (hunters): { x, y, radius } each.
function Grenades:serverIncoming()
  local out = {}
  for _, g in ipairs(sv and sv.flying or {}) do
    out[#out + 1] = { x = g.x, y = g.y, radius = self.blast.radius }
  end
  return out
end

function Grenades:serverStep(server, dt)
  if not sv then
    return
  end
  local weapons = Features.byName.weapons
  local i = 1
  while i <= #sv.flying do
    local g = sv.flying[i]
    g.t = g.t + dt
    if g.t >= g.flight then
      table.remove(sv.flying, i)
      if weapons then
        -- Weapons' blast, as a missile's: the id only tells clients which streak to drop (none).
        weapons:explode(server, { id = 0, owner = g.owner, blast = self.blast, vx = g.x - g.ox, vy = g.y - g.oy },
          g.x, g.y)
      end
    else
      i = i + 1
    end
  end
end

return Grenades
