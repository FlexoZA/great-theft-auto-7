-- Abilities: powers a character casts on the world. Hold the ability's key
-- and a target area follows the cursor, kept within the ability's range of
-- you; let go to cast it there, or right-click to think better of it. Each
-- ability then waits out its cooldown.
--
-- You carry abilities in `slotCount` ability slots: three on keys (Q, E,
-- R; slot 1 casts whatever is in slot 1) and a fourth, `passiveSlot`, with
-- no key, for a passive ability (`passive = true` in its module) that
-- works by being there. Only a passive ability fits that slot and a
-- passive one fits nowhere else. Everyone starts with freeze (freeze.lua)
-- in slot 1; kinds.lua lists every ability. An ability is
-- also an item ("ability-<key>" in the inventory): on the inventory screen
-- you drag one from your bag onto a slot to carry it (ABL_EQUIP takes the
-- item; one already there swaps into the bag), drag it from its slot into
-- the bag to put it down (ABL_UNEQUIP; the slot is empty then), or onto
-- another slot to change its key (ABL_MOVE). The host keeps the slots and
-- tells you them (ABL_SLOTS), and casts only what is in one. Cooldowns
-- follow the ability, not the slot, so moving one doesn't reset it.
-- The shop sells ability items; what you start with is freeze.
--
-- A passive ability (regen.lua) has no cast: every host tick this feature
-- calls its `serverTick(server, player, dt, abilities)` for the player
-- carrying it in the passive slot. `serverSinceHurt(player)` tells such an
-- ability how long its carrier has gone unhurt (weapons raises
-- `serverPlayerDamaged`, which is noted here).
--
-- Holding: the host keeps a frozen player or car where it is by putting it
-- back every tick after everything else has moved it (this feature runs
-- last), and answers `serverHeld(server, player)` so on-foot stops walking
-- them and weapons stops their gun. Clients hear who is held and answer
-- `held(client, id)` the same way, so prediction and the HUD agree. Another
-- feature can hold a player through Features.byName.abilities:serverHold.
--
-- Messages
--   client -> server  ABL_CAST  <ability> <x> <y>
--   client -> server  ABL_EQUIP <ability> <slot>       (the ability item I carry, into that slot)
--   client -> server  ABL_UNEQUIP <slot>               (the ability in that slot, into my bag)
--   client -> server  ABL_MOVE <slot> <slot>           (swap two slots)
--   server -> player  ABL_SLOTS <ability per slot>...  (what is in each slot; "-" = empty)
--   server -> all     ABL_FIRED <by> <ability> <x> <y> <seconds> [<heldId>]...

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")
local Kinds = require("src.features.abilities.kinds")
local Freeze = require("src.features.abilities.freeze")

local Abilities = {
  name = "abilities",
  priority = 990, -- last: holds override every other mover; the aim ring draws over everything
}

Abilities.kinds = Kinds
Abilities.slotCount = 4 -- ability slots: the keyed ones and the passive one
Abilities.passiveSlot = 4 -- the slot with no key, for an ability that works by being carried
Abilities.defaultKeys = { "q", "e", "r" } -- slot i is cast with action "ability-<i>"
Abilities.startKeys = { "freeze" } -- what everyone starts with, slot by slot
-- The ability circles along the bottom centre of the screen, one per slot,
-- `hudStep` apart, empty ones dim.
Abilities.hudStep = 64
Abilities.hudRadius = 24
Abilities.hudBottom = 48 -- px up from the bottom edge to the circles' centres

local EMPTY = "-" -- an empty slot on the wire

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- The slots everyone starts with: slot -> ability key.
local function startSlots()
  local slots = {}
  for i, key in ipairs(Abilities.startKeys) do
    if Kinds.byKey[key] and i <= Abilities.slotCount then
      slots[i] = key
    end
  end
  return slots
end

--- Does ability `key` belong in `slot`: passive ones in the passive slot,
--- the rest anywhere else?
local function fits(key, slot)
  local ability = Kinds.byKey[key]
  if not ability then
    return false
  end
  return (slot == Abilities.passiveSlot) == (ability.passive == true)
end

--- The slot ability `key` sits in, in a slot -> key map, or nil.
local function slotOf(slots, key)
  for slot, k in pairs(slots) do
    if k == key then
      return slot
    end
  end
  return nil
end

-- Client --------------------------------------------------------------------

Abilities.camera = nil -- last camera seen in update, to put the cursor in the world
Abilities.time = 0
Abilities.slots = {} -- slot -> ability key, mine (the host says: ABL_SLOTS)
Abilities.aiming = nil -- slot index while its key is held
Abilities.spent = nil -- slot whose key must be released before it aims again (cancelled)
Abilities.cooldowns = {} -- ability key -> seconds left
Abilities.readyFlash = {} -- ability key -> seconds of "it's back" flash left on the HUD
Abilities.effects = {} -- { ability, x, y, t, seconds }
Abilities.heldUntil = {} -- player id -> client time their hold ends

function Abilities:load()
  for i = 1, self.slotCount do
    if i ~= self.passiveSlot then
      Controls.register("ability-" .. i, ("Ability slot %d"):format(i), self.defaultKeys[i])
    end
  end
  Controls.register("ability-cancel", "Cancel ability", "mouse2")
  Sounds.load()
end

function Abilities:enterGame()
  self.camera = nil
  self.time = 0
  self.slots = startSlots()
  self.aiming = nil
  self.spent = nil
  self.cooldowns = {}
  self.readyFlash = {}
  self.effects = {}
  self.heldUntil = {}
end

function Abilities:exitGame()
  self:enterGame()
end

--- The ability in slot `slot`, or nil.
function Abilities:inSlot(slot)
  return Kinds.byKey[self.slots[slot] or EMPTY]
end

--- Do I carry ability `key`, as far as the host has told me?
function Abilities:owns(key)
  return slotOf(self.slots, key) ~= nil
end

--- The slot ability `key` is in, or nil.
function Abilities:slotOf(key)
  return slotOf(self.slots, key)
end

--- Does ability `key` belong in `slot` (see `fits`)? The inventory screen
--- asks before a drop, to say why not.
function Abilities:fits(key, slot)
  return fits(key, slot)
end

--- Would swapping slots `from` and `to` leave every ability in a slot it
--- fits? A passive one can't go on a key, nor a keyed one in the passive slot.
function Abilities:canMove(from, to)
  local a, b = self.slots[from], self.slots[to]
  return from ~= to and a ~= nil and to >= 1 and to <= self.slotCount and fits(a, to) and (not b or fits(b, from))
end

--- Ask to put the ability item I carry for `key` into slot `slot` (the
--- inventory screen does, on a drag). The host answers with ABL_SLOTS.
function Abilities:equip(client, key, slot)
  if Kinds.byKey[key] and not self:owns(key) and fits(key, slot) then
    client:send(Protocol.encode("ABL_EQUIP", key, slot))
  end
end

--- Ask to put the ability in slot `slot` down into my bag.
function Abilities:unequip(client, slot)
  if self.slots[slot] then
    client:send(Protocol.encode("ABL_UNEQUIP", slot))
  end
end

--- Ask to swap slots `from` and `to` (either may be empty).
function Abilities:move(client, from, to)
  if self:canMove(from, to) then
    client:send(Protocol.encode("ABL_MOVE", from, to))
  end
end

--- Is this player held still, as far as this machine knows? The `held`
--- convention: on-foot and weapons ask every feature.
function Abilities:held(_client, id)
  return (self.heldUntil[id] or 0) > self.time
end

--- The cursor in world space, inverting the game state's draw transform.
local function mouseToWorld(camera, ox, oy)
  local mx, my = love.mouse.getPosition()
  local w, h = love.graphics.getDimensions()
  local cx, cy, s = ox, oy, 1
  if camera then
    cx, cy, s = camera.x, camera.y, camera.scale or 1
  end
  return cx + (mx - w / 2) / s, cy + (my - h / 2) / s
end

--- Where the ability would land: the cursor, pulled back to within its
--- range of me. Nil while I am out of the world.
function Abilities:target(client, ability)
  local ox, oy = client:myPose()
  if not ox then
    return nil
  end
  local x, y = mouseToWorld(self.camera, ox, oy)
  local d = math.sqrt(dist2(x, y, ox, oy))
  if d > ability.range then
    x, y = ox + (x - ox) / d * ability.range, oy + (y - oy) / d * ability.range
  end
  return x, y
end

function Abilities:cast(client, slot)
  local ability = self:inSlot(slot)
  if not ability then
    return
  end
  local x, y = self:target(client, ability)
  if x then
    client:send(Protocol.encode("ABL_CAST", ability.key, ("%.1f"):format(x), ("%.1f"):format(y)))
  end
end

function Abilities:update(dt, client, camera)
  self.camera = camera
  self.time = self.time + dt
  for key, left in pairs(self.cooldowns) do
    if left - dt > 0 then
      self.cooldowns[key] = left - dt
    else
      self.cooldowns[key] = nil
      self.readyFlash[key] = 0.6
    end
  end
  for key, left in pairs(self.readyFlash) do
    self.readyFlash[key] = left - dt > 0 and left - dt or nil
  end
  for i = #self.effects, 1, -1 do
    local e = self.effects[i]
    e.t = e.t + dt
    if e.t > e.seconds + e.ability.afterglow then
      table.remove(self.effects, i)
    end
  end

  local taken = Features.any("pointerTaken", client) -- a screen (the inventory) has the mouse
  local canAim = client:myPose() ~= nil and not self:held(client, client.myId) and not taken
  for i = 1, self.slotCount do
    local ability = i ~= self.passiveSlot and self:inSlot(i) or nil
    local down = ability ~= nil and Controls.isDown("ability-" .. i)
    if self.aiming == i then
      if not ability or Controls.suspended or taken or Controls.isDown("ability-cancel") then
        self.aiming, self.spent = nil, i -- a menu or screen came up, or they changed their mind
      elseif not down then
        self.aiming = nil
        self:cast(client, i)
      end
    elseif down and not self.aiming and self.spent ~= i and canAim and not self.cooldowns[ability.key] then
      self.aiming = i
    end
    if not down and self.spent == i then
      self.spent = nil
    end
  end
end

--- The aim ring while a key is held, then every effect in the world and a
--- glaze over whoever is held.
function Abilities:drawAboveCars(client)
  local ability = self.aiming and self:inSlot(self.aiming)
  if ability then
    local ox, oy = client:myPose()
    local x, y = self:target(client, ability)
    if x then
      local c = ability.color
      love.graphics.setLineWidth(1)
      love.graphics.setColor(c[1], c[2], c[3], 0.18)
      love.graphics.circle("line", ox, oy, ability.range, 64)
      love.graphics.setColor(c[1], c[2], c[3], 0.16)
      love.graphics.circle("fill", x, y, ability.radius, 48)
      love.graphics.setLineWidth(2)
      love.graphics.setColor(c[1], c[2], c[3], 0.85)
      love.graphics.circle("line", x, y, ability.radius, 48)
      love.graphics.setLineWidth(1)
    end
  end
  for _, e in ipairs(self.effects) do
    e.ability.drawEffect(e)
  end
  for id in pairs(self.heldUntil) do
    if self:held(client, id) then
      local px, py, onFoot = client:pose(id)
      if px then
        Freeze.drawHeld(px, py, onFoot and Body.RADIUS + 4 or Car.WIDTH * 0.62, self.time)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The y of the top of the circle row (their glow included), so a feature
--- can sit something just above the abilities.
function Abilities:hudTop()
  return love.graphics.getHeight() - self.hudBottom - self.hudRadius - 8
end

function Abilities:drawHUD(client)
  -- A row of circles along the bottom centre, one per slot. The key sits
  -- in the circle and the title under it; on cast the ring empties and
  -- fills back up through the cooldown with the seconds left inside. Full
  -- and lit means ready. Empty slots are just dim rings; the passive slot
  -- says so under its ring and shows its ability, if any, always lit.
  local small, body = UI.fonts.small, UI.fonts.body
  local w, h = love.graphics.getDimensions()
  local r, n = self.hudRadius, self.slotCount
  local cy = h - self.hudBottom
  local x0 = math.floor(w / 2 - (n - 1) * self.hudStep / 2)
  for i = 1, n do
    local cx = x0 + (i - 1) * self.hudStep
    local ability = self:inSlot(i)
    if i == self.passiveSlot then
      if ability then
        local c = ability.color
        love.graphics.setColor(c[1], c[2], c[3], 0.2)
        love.graphics.circle("fill", cx, cy, r + 6, 48)
        UI.ring(cx, cy, r, 1, c, 5)
      else
        UI.ring(cx, cy, r, 0, { 1, 1, 1 }, 4)
      end
      love.graphics.setFont(small)
      local title = ability and ability.title or "passive"
      UI.label(title, cx - math.floor(small:getWidth(title) / 2), cy + r + 4, { 0.6, 0.6, 0.65 })
    elseif not ability then
      UI.ring(cx, cy, r, 0, { 1, 1, 1 }, 4)
    else
      local key = Controls.name(Controls.bindings("ability-" .. i)[1])
      local left = self.cooldowns[ability.key]
      local c = ability.color
      local middle, middleColor, title, titleColor
      if left then
        UI.ring(cx, cy, r, 1 - left / ability.cooldown, { c[1], c[2], c[3], 0.85 }, 5)
        middle = left >= 10 and ("%d"):format(left) or ("%.1f"):format(left)
        middleColor = { 1, 1, 1 }
        title, titleColor = ability.title, { 0.7, 0.7, 0.75 }
      else
        local flash = self.readyFlash[ability.key]
        if flash then
          -- Just back: a burst swelling out of the ring and fading.
          local k = flash / 0.6
          love.graphics.setLineWidth(2)
          love.graphics.setColor(c[1], c[2], c[3], 0.8 * k)
          love.graphics.circle("line", cx, cy, r + 5 + (1 - k) * 18, 48)
          love.graphics.setLineWidth(1)
        end
        local aiming = self.aiming == i
        local pulse = aiming and (0.5 + 0.5 * math.sin(self.time * 10)) or 0
        love.graphics.setColor(c[1], c[2], c[3], 0.2 + 0.3 * pulse)
        love.graphics.circle("fill", cx, cy, r + 6, 48)
        UI.ring(cx, cy, r, 1, c, 5)
        middle, middleColor = key, { 1, 1, 1 }
        title = aiming and "release" or ability.title
        titleColor = aiming and c or { 0.9, 0.9, 0.95 }
      end
      love.graphics.setFont(body)
      UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), middleColor)
      love.graphics.setFont(small)
      UI.label(title, cx - math.floor(small:getWidth(title) / 2), cy + r + 4, titleColor)
    end
  end
  if self:held(client, client.myId) then
    love.graphics.setFont(body)
    local c = Freeze.color
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("FROZEN", 1, 89, w, "center")
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.printf("FROZEN", 0, 88, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Abilities.clientMessages = {
  ABL_FIRED = function(client, args)
    local by, ability = tonumber(args[1]), Kinds.byKey[args[2] or EMPTY]
    local x, y, seconds = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if not (ability and x and y and seconds) then
      return
    end
    Abilities.effects[#Abilities.effects + 1] = { ability = ability, x = x, y = y, t = 0, seconds = seconds }
    for i = 6, #args do
      local id = tonumber(args[i])
      if id then
        Abilities.heldUntil[id] = Abilities.time + seconds
      end
    end
    if by == client.myId then
      Abilities.cooldowns[ability.key] = ability.cooldown
    end
    Sounds.play(ability.sound, x, y)
  end,
  ABL_SLOTS = function(_client, args)
    local slots = {}
    for slot, key in ipairs(args) do
      if Kinds.byKey[key] and slot <= Abilities.slotCount then
        slots[slot] = key
      end
    end
    Abilities.slots = slots
    if Abilities.aiming and not slots[Abilities.aiming] then
      Abilities.aiming = nil -- it left the slot mid-aim
    end
  end,
}

-- Server --------------------------------------------------------------------

Abilities.sv = nil

function Abilities:serverStart(server)
  self.sv = {
    time = 0,
    slots = {}, -- player id -> slot -> ability key
    readyAt = {}, -- player id -> ability key -> time it may be cast again
    players = {}, -- player id -> time their hold ends
    bodies = {}, -- player id -> { until, x, y }: a walker kept on the spot
    cars = {}, -- vehicle id -> { until, x, y, angle }: a car kept on the spot
    hurtAt = {}, -- player id -> time they were last hurt, for passive abilities
  }
  for _, p in pairs(server.players) do
    self:serverPlayerJoined(server, p)
  end
end

--- Tell `player` what is in each of their ability slots (ABL_SLOTS). Bots
--- aren't listening.
function Abilities:sendSlots(server, player)
  local slots = self.sv and self.sv.slots[player.id]
  if not slots or player.bot then
    return
  end
  local list = {}
  for slot = 1, self.slotCount do
    list[slot] = slots[slot] or EMPTY
  end
  server:send(player, Protocol.encode("ABL_SLOTS", unpack(list)))
end

function Abilities:serverPlayerJoined(server, player)
  local sv = self.sv
  if sv and not sv.slots[player.id] then
    sv.slots[player.id] = startSlots()
    self:sendSlots(server, player)
  end
end

function Abilities:serverPlayerLeft(_server, player)
  local sv = self.sv
  if sv then
    sv.slots[player.id], sv.readyAt[player.id] = nil, nil
    sv.players[player.id], sv.bodies[player.id], sv.hurtAt[player.id] = nil, nil, nil
  end
end

--- Does `player` carry ability `key` in a slot on the host?
function Abilities:serverOwns(player, key)
  local slots = self.sv and self.sv.slots[player.id]
  return slots ~= nil and slotOf(slots, key) ~= nil
end

--- `player` takes the ability item they carry for `key` and puts it in
--- slot `slot`; one already there goes back into the bag as an item (the
--- slot the taken item freed has room). Returns true if it happened.
function Abilities:serverEquip(server, player, key, slot)
  local slots = self.sv and self.sv.slots[player.id]
  local buildings = Features.byName.buildings
  if not (slots and Kinds.byKey[key] and slot and buildings and buildings.serverTake and Features.present(player)) then
    return false
  elseif not fits(key, slot) or slotOf(slots, key) then
    return false -- no such slot, the wrong kind of slot, or they carry it already
  end
  if buildings:serverTake(server, player, "ability-" .. key, 1) < 1 then
    return false -- they don't carry one
  end
  local old = slots[slot]
  if old then
    buildings:serverGive(server, player, "ability-" .. old, 1)
  end
  slots[slot] = key
  self:sendSlots(server, player)
  return true
end

--- `player` puts the ability in slot `slot` down into their bag as an
--- item, if there is room, leaving the slot empty. Returns true if they do.
function Abilities:serverUnequip(server, player, slot)
  local slots = self.sv and self.sv.slots[player.id]
  local key = slots and slot and slots[slot]
  local buildings = Features.byName.buildings
  if not (key and buildings and buildings.serverGive and Features.present(player)) then
    return false
  end
  if buildings:serverGive(server, player, "ability-" .. key, 1) < 1 then
    return false -- no room in their bag
  end
  slots[slot] = nil
  self:sendSlots(server, player)
  return true
end

--- `player` swaps slots `from` and `to` (either may be empty), as long as
--- each ability still fits where it lands. Returns true if they did.
function Abilities:serverMove(server, player, from, to)
  local slots = self.sv and self.sv.slots[player.id]
  if not (slots and from and to and Features.present(player)) or from == to then
    return false
  elseif not slots[from] or not fits(slots[from], to) or (slots[to] and not fits(slots[to], from)) then
    return false
  end
  slots[from], slots[to] = slots[to], slots[from]
  self:sendSlots(server, player)
  return true
end

--- Everything moved to a new map: nothing is held there.
function Abilities:mapChanged(_map, server)
  if server and self.sv then
    self.sv.players, self.sv.bodies, self.sv.cars = {}, {}, {}
  end
end

--- The `serverHeld` convention: is this player held still on the host?
function Abilities:serverHeld(_server, player)
  local sv = self.sv
  return sv ~= nil and (sv.players[player.id] or 0) > sv.time
end

--- Keep a car where it stands for `seconds`, whoever is in it.
function Abilities:serverHoldCar(_server, car, seconds)
  local sv = self.sv
  if not (sv and car) then
    return
  end
  local h = sv.cars[car.id]
  local untilT = sv.time + seconds
  if h and h.untilT >= untilT then
    return -- already held for longer
  end
  sv.cars[car.id] = { untilT = untilT, x = car.x, y = car.y, angle = car.angle }
  car:stop()
end

--- Hold a player still for `seconds`: their car if they are driving, their
--- feet if not, and their trigger finger either way. Other features reach
--- this via Features.byName.abilities.
function Abilities:serverHold(server, player, seconds)
  local sv = self.sv
  if not (sv and Features.present(player)) then
    return false
  end
  sv.players[player.id] = math.max(sv.players[player.id] or 0, sv.time + seconds)
  if player.vehicle then
    self:serverHoldCar(server, player.vehicle, seconds)
  else
    local b = player.body
    local h = sv.bodies[player.id]
    if not (h and h.untilT >= sv.time + seconds) then
      sv.bodies[player.id] = { untilT = sv.time + seconds, x = b.x, y = b.y }
    end
  end
  return true
end

--- Put everything held back where it was when the hold began. Runs after
--- every other feature's step, so this is the last word before STATE.
function Abilities:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for vid, h in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if not car or h.untilT <= sv.time or car.hidden or car.stowed then
      sv.cars[vid] = nil
    else
      car.x, car.y, car.angle = h.x, h.y, h.angle
      car:stop()
    end
  end
  for id, h in pairs(sv.bodies) do
    local player = server.players[id]
    if not player or h.untilT <= sv.time or player.vehicle or not Features.present(player) then
      sv.bodies[id] = nil
    else
      player.body.x, player.body.y = h.x, h.y
    end
  end
  for id, untilT in pairs(sv.players) do
    if untilT <= sv.time then
      sv.players[id] = nil
    end
  end
  -- Passive abilities work by being carried: tick the one in each
  -- player's passive slot.
  for id, slots in pairs(sv.slots) do
    local player = server.players[id]
    local ability = player and Kinds.byKey[slots[self.passiveSlot] or EMPTY]
    if ability and ability.serverTick then
      ability.serverTick(server, player, dt, self)
    end
  end
end

--- Weapons says `victim` was hurt: noted for the passive abilities.
function Abilities:serverPlayerDamaged(_server, victim)
  local sv = self.sv
  if sv and victim then
    sv.hurtAt[victim.id] = sv.time
  end
end

--- Seconds since `player` was last hurt on the host (a long time if never).
function Abilities:serverSinceHurt(player)
  local sv = self.sv
  if not sv then
    return 0
  end
  local at = sv.hurtAt[player.id]
  return at and (sv.time - at) or math.huge
end

Abilities.serverMessages = {
  ABL_CAST = function(server, player, args)
    local sv = Abilities.sv
    local key = args[1]
    local ability = Kinds.byKey[key or EMPTY]
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (sv and ability and x and y) or not Features.present(player) then
      return
    end
    if not Abilities:serverOwns(player, key) or ability.passive then
      return -- not in any of their slots, or not the casting kind: a stale or forged cast
    end
    if Abilities:serverHeld(server, player) then
      return -- frozen people cast nothing
    end
    local ready = sv.readyAt[player.id]
    if not ready then
      ready = {}
      sv.readyAt[player.id] = ready
    end
    if (ready[key] or 0) > sv.time then
      return -- still cooling down; the client knows, so this was a stale or forged cast
    end
    -- Never further than the ability reaches, whatever the client said.
    local ox, oy = Features.bodyPose(server, player)
    local d = math.sqrt(dist2(x, y, ox, oy))
    if d > ability.range then
      x, y = ox + (x - ox) / d * ability.range, oy + (y - oy) / d * ability.range
    end
    ready[key] = sv.time + ability.cooldown
    local held = ability.serverCast(server, player, x, y, Abilities)
    server:broadcast(Protocol.encode("ABL_FIRED", player.id, key, ("%.1f"):format(x), ("%.1f"):format(y),
      ("%.2f"):format(ability.seconds), unpack(held)))
  end,
  ABL_EQUIP = function(server, player, args)
    Abilities:serverEquip(server, player, args[1], tonumber(args[2]))
  end,
  ABL_UNEQUIP = function(server, player, args)
    Abilities:serverUnequip(server, player, tonumber(args[1]))
  end,
  ABL_MOVE = function(server, player, args)
    Abilities:serverMove(server, player, tonumber(args[1]), tonumber(args[2]))
  end,
}

return Abilities
