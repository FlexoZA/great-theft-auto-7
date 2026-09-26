-- Abilities: powers a character casts on the world. Hold the ability's key
-- and a target area follows the cursor, kept within the ability's range of
-- you; let go to cast it there, or right-click to think better of it. Each
-- ability then waits out its cooldown. An ability with `aim = "direction"`
-- (the MG nest) is selected with a press of its key instead: an arrow from
-- you shows where it would go, `range` away towards the cursor, and the
-- fire button puts it there (weapons leaves the gun alone meanwhile: the
-- `fireTaken` convention); the key again or right-click puts it away. One
-- with `aim = "point"` (leap) is selected and placed the same way, but
-- shows its area under the cursor, kept within range, like a held one. One
-- with `aim = "self"` (heal) has nothing to aim: a press of its key casts
-- it where you stand. One with `onFoot = true` (leap) only works out of a
-- car: behind the wheel its key does nothing and the host refuses it.
--
-- An ability may fly something about (leap.lua flies its caster to the
-- landing spot): its `onFired(e, client)` hears the cast, its
-- `updateEffect(e, client, camera)` runs every frame of the effect, and
-- `drawBelow(e)` draws under the cars. While its `airborne(e)` is true the
-- caster is `held` here (no walking, shooting or casting), but not frozen.
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
-- The shop sells ability items; what you start with is freeze. A saved
-- world keeps what is in each slot (serverSavePlayer), not the cooldowns.
--
-- A passive ability (regen.lua) has no cast: every host tick this feature
-- calls its `serverTick(server, player, dt, abilities)` for the player
-- carrying it in the passive slot. `serverSinceHurt(player)` tells such an
-- ability how long its carrier has gone unhurt (weapons raises
-- `serverPlayerDamaged`, which is noted here), and `serverPassive(server,
-- player, key, phase, seconds)` tells the carrier its phase (ABL_PASSIVE)
-- so the HUD ring shows it working ("active") or resting ("cooldown").
--
-- Abilities come in tiers (tiers/init.lua): "ability-leap@rare" is a leap
-- that comes back sooner and flies further (each ability's `tierStats`).
-- A slot holds the ability with its tier ("leap@rare"), still one of each
-- ability per player; another tier of one you carry dragged onto the slots
-- swaps with it. The host casts the tier in the slot: its cooldown and
-- range here, the rest in the ability's own module, which gets the tuned
-- table as the last argument of `serverCast` and `serverTick` (and finds it
-- as `e.ability` in an effect), so everything reads the numbers from there.
-- ABL_FIRED names the tier too, so every client draws the same.
--
-- A cheat (reachforthestars) can lift an ability's limits for a player,
-- Abilities:serverSetReach: the host lets their casts land wherever the
-- cursor is, out to `liftedRange`, with no cooldown in between, and tells
-- them (ABL_REACH) so their aim ring follows the cursor and their HUD
-- shows it ready again straight away.
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
--   client -> server  ABL_EQUIP <ability>[@<tier>] <slot>  (the ability item I carry, into that slot)
--   client -> server  ABL_UNEQUIP <slot>               (the ability in that slot, into my bag)
--   client -> server  ABL_MOVE <slot> <slot>           (swap two slots)
--   server -> player  ABL_SLOTS <ability[@tier] per slot>...  (what is in each slot; "-" = empty)
--   server -> player  ABL_PASSIVE <ability> <phase> <seconds>  (the passive in your slot went idle,
--                                                             active or into cooldown, for that long)
--   server -> player  ABL_REACH <ability> <0|1>       (its range and cooldown are lifted for you, or back to normal)
--   server -> all     ABL_FIRED <by> <ability[@tier]> <x> <y> <seconds> <angle> [<heldId>]...
--                                              (angle: which way it faces)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")
local Kinds = require("src.features.abilities.kinds")
local Icons = require("src.features.abilities.icons")
local Tiers = require("src.features.tiers")
local Freeze = require("src.features.abilities.freeze")
local Leap = require("src.features.abilities.leap")
local Chicken = require("src.features.abilities.chicken")

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
Abilities.hudIcon = 17 -- radius the ability's icon (icons.lua) fills inside its ring
-- A lifted range (a cheat) still stops somewhere: past any screen's edge,
-- short of a forged cast across the whole world.
Abilities.liftedRange = 4000

local EMPTY = "-" -- an empty slot on the wire

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- The ability a slot holds, "leap" or "leap@rare", in its tier: the
--- tuned table (tiers/init.lua), or nil for nothing or nonsense.
local function kindOf(held)
  if not held then
    return nil
  end
  local key, tier = Tiers.split(held)
  local ability = Kinds.byKey[key]
  return ability and tier and Tiers.apply(ability, tier) or nil
end
Abilities.kindOf = kindOf

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

--- Does ability `key` (with or without a tier) belong in `slot`: passive
--- ones in the passive slot, the rest anywhere else?
local function fits(key, slot)
  local ability = kindOf(key)
  if not ability then
    return false
  end
  return (slot == Abilities.passiveSlot) == (ability.passive == true)
end

--- The slot ability `key` sits in, in a slot -> key map, or nil, in
--- whatever tier (a player carries one of each ability).
local function slotOf(slots, key)
  key = Tiers.base(key)
  for slot, k in pairs(slots) do
    if Tiers.base(k) == key then
      return slot
    end
  end
  return nil
end

-- Client --------------------------------------------------------------------

Abilities.camera = nil -- last camera seen in update, to put the cursor in the world
Abilities.time = 0
Abilities.slots = {} -- slot -> ability key with its tier ("leap@rare"), mine (the host says: ABL_SLOTS)
Abilities.aiming = nil -- slot index while its key is held
Abilities.spent = nil -- slot whose key must be released before it aims again (cancelled)
Abilities.fireSpent = nil -- true after the fire button placed something, until it is let go
Abilities.cooldowns = {} -- ability key -> seconds left
Abilities.readyFlash = {} -- ability key -> seconds of "it's back" flash left on the HUD
Abilities.passive = nil -- { key, phase, left, total }: what my passive ability is up to (ABL_PASSIVE)
Abilities.effects = {} -- { ability, by, x, y, angle, t, seconds }
Abilities.heldUntil = {} -- player id -> client time their hold ends
Abilities.lifted = {} -- ability key -> true while its range and cooldown are lifted for me (ABL_REACH)

function Abilities:load()
  for i = 1, self.slotCount do
    if i ~= self.passiveSlot then
      Controls.register("ability-" .. i, ("Ability slot %d"):format(i), self.defaultKeys[i])
    end
  end
  Controls.register("ability-cancel", "Cancel ability", "mouse2")
  Sounds.load()
end

-- ABL_SLOTS arrives in the same burst as START, before the game screen
-- opens (a saved world's slots too), so the slots are only forgotten on
-- the way out.
function Abilities:enterGame()
  self.camera = nil
  self.time = 0
  self.aiming = nil
  self.spent = nil
  self.fireSpent = nil
  self.cooldowns = {}
  self.readyFlash = {}
  self.passive = nil
  self.effects = {}
  self.heldUntil = {}
  self.lifted = {}
end

function Abilities:exitGame()
  self:enterGame()
  self.slots = startSlots()
end

--- The ability in slot `slot`, in its tier, or nil.
function Abilities:inSlot(slot)
  return kindOf(self.slots[slot])
end

--- The tier key of what is in slot `slot`.
function Abilities:tierIn(slot)
  return Tiers.of(self.slots[slot] or "")
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

--- Ask to put the ability item I carry for `key` ("leap", "leap@rare")
--- into slot `slot` (the inventory screen does, on a drag); another tier
--- of one I carry swaps with it where it is. The host answers with ABL_SLOTS.
function Abilities:equip(client, key, slot)
  local have = slotOf(self.slots, key)
  if kindOf(key) and (not have or self.slots[have] ~= key) and fits(key, have or slot) then
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

--- Is this player frozen, as far as this machine knows?
function Abilities:frozen(id)
  return (self.heldUntil[id] or 0) > self.time
end

--- Is this player held still, as far as this machine knows: frozen, or in
--- the air (a leap)? The `held` convention: on-foot and weapons ask every feature.
function Abilities:held(_client, id)
  if self:frozen(id) then
    return true
  end
  for _, e in ipairs(self.effects) do
    if e.by == id and e.ability.airborne and e.ability.airborne(e) then
      return true
    end
  end
  return false
end

--- The `hidden` convention: is this player out of sight on this screen
--- (a chicken still hiding them)? The core, weapons, the minimap and the
--- arrows leave them out.
function Abilities:hidden(_client, id)
  for _, e in ipairs(self.effects) do
    if e.by == id and Chicken.hiding(e) then
      return true
    end
  end
  return false
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

--- How far ability `ability` reaches for me: its range, or further while
--- a cheat has lifted it.
function Abilities:range(ability)
  return self.lifted[ability.key] and self.liftedRange or ability.range
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
  local range = self:range(ability)
  if ability.aim == "self" then
    return ox, oy
  elseif d > range or (ability.aim == "direction" and d > 1) then
    x, y = ox + (x - ox) / d * range, oy + (y - oy) / d * range -- exactly `range` away for a direction
  end
  return x, y
end

--- Can I use `ability` where I am? One marked `onFoot` not from a car.
local function usable(client, ability)
  return not (ability.onFoot and client:myVehicle())
end

--- Is `ability` selected by a press of its key and placed by the fire
--- button (a direction or a point), rather than held and let go?
local function placed(ability)
  return ability.aim == "direction" or ability.aim == "point"
end

--- Is a direction or point ability selected, waiting for the fire button?
function Abilities:selecting()
  local ability = self.aiming and self:inSlot(self.aiming)
  return ability ~= nil and placed(ability)
end

--- The `fireTaken` convention: the fire button is ours while a direction
--- or point ability is selected, and until it is let go after placing one.
function Abilities:fireTaken()
  return self:selecting() or (self.fireSpent == true and Controls.isDown("fire"))
end

--- A press of a direction or point ability's key selects it (or puts it
--- away); a press of a self ability's key casts it on the spot.
function Abilities:keypressed(key, client)
  for i = 1, self.slotCount do
    local ability = i ~= self.passiveSlot and self:inSlot(i) or nil
    if ability and (placed(ability) or ability.aim == "self") and Controls.is("ability-" .. i, key) then
      local free = not self.aiming and not self.cooldowns[ability.key] and client:myPose() ~= nil
        and usable(client, ability)
        and not self:held(client, client.myId) and not Features.any("pointerTaken", client)
      if ability.aim == "self" then
        if free then
          self:cast(client, i)
        end
      elseif self.aiming == i then
        self.aiming = nil
      elseif free then
        self.aiming = i
      end
      return
    end
  end
end

--- The fire button places a selected direction ability.
function Abilities:mousepressed(_x, _y, button, client)
  if self:selecting() and Controls.isMouse("fire", button) then
    local slot = self.aiming
    self.aiming, self.fireSpent = nil, true
    self:cast(client, slot)
  end
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
  if self.passive then
    self.passive.left = math.max(0, self.passive.left - dt)
  end
  for i = #self.effects, 1, -1 do
    local e = self.effects[i]
    e.t = e.t + dt
    if e.ability.updateEffect then
      e.ability.updateEffect(e, client, camera)
    end
    if e.t > e.seconds + e.ability.afterglow then
      table.remove(self.effects, i)
    end
  end

  local taken = Features.any("pointerTaken", client) -- a screen (the inventory) has the mouse
  local canAim = client:myPose() ~= nil and not self:held(client, client.myId) and not taken
  if self.fireSpent and not Controls.isDown("fire") then
    self.fireSpent = nil
  end
  for i = 1, self.slotCount do
    local ability = i ~= self.passiveSlot and self:inSlot(i) or nil
    -- Selected by a press and placed by the fire button, or cast by a press: not held.
    local direction = ability ~= nil and (placed(ability) or ability.aim == "self")
    local down = ability ~= nil and Controls.isDown("ability-" .. i)
    if self.aiming == i then
      if not ability or Controls.suspended or taken or Controls.isDown("ability-cancel")
        or not usable(client, ability) then
        self.aiming, self.spent = nil, i -- a menu or screen came up, they got in a car, or changed their mind
      elseif not down and not direction then
        self.aiming = nil
        self:cast(client, i)
      end
    elseif down and not direction and not self.aiming and self.spent ~= i and canAim
      and not self.cooldowns[ability.key] and usable(client, ability) then
      self.aiming = i
    end
    if not down and self.spent == i then
      self.spent = nil
    end
  end
end

--- Whatever an effect puts on the ground under the cars (a leaper's shadow).
function Abilities:drawBelowCars(client)
  for _, e in ipairs(self.effects) do
    if e.ability.drawBelow then
      e.ability.drawBelow(e, client)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The aim ring while a key is held, then every effect in the world and a
--- glaze over whoever is held.
function Abilities:drawAboveCars(client)
  local ability = self.aiming and self:inSlot(self.aiming)
  if ability then
    local ox, oy = client:myPose()
    local x, y = self:target(client, ability)
    if x and ability.aim == "direction" and ability.drawAim then
      ability.drawAim(ox, oy, x, y, self.time)
    elseif x then
      local c = ability.color
      love.graphics.setLineWidth(1)
      if not self.lifted[ability.key] then
        love.graphics.setColor(c[1], c[2], c[3], 0.18)
        love.graphics.circle("line", ox, oy, ability.range, 64)
      end
      love.graphics.setColor(c[1], c[2], c[3], 0.16)
      love.graphics.circle("fill", x, y, ability.radius, 48)
      love.graphics.setLineWidth(2)
      love.graphics.setColor(c[1], c[2], c[3], 0.85)
      love.graphics.circle("line", x, y, ability.radius, 48)
      love.graphics.setLineWidth(1)
    end
  end
  for _, e in ipairs(self.effects) do
    e.ability.drawEffect(e, client)
  end
  for id in pairs(self.heldUntil) do
    if self:frozen(id) then
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

--- The x where the circle row begins on the left (glow included), so a
--- feature can stand something beside it: weapons puts the gun in hand there.
function Abilities:hudLeft()
  local w = love.graphics.getWidth()
  return math.floor(w / 2 - (self.slotCount - 1) * self.hudStep / 2) - self.hudRadius - 8
end

function Abilities:drawHUD(client)
  -- A row of circles along the bottom centre, one per slot. The ability's
  -- icon sits in the circle, its key in a badge on the ring and the title
  -- under it; on cast the ring empties and fills back up through the
  -- cooldown with the seconds left over the faded icon. Full and lit means
  -- ready. Empty slots are just dim rings; the passive slot
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
      -- The passive ability: lit while carried; working, its ring pulses
      -- with the seconds it has left inside; resting, the ring fills back
      -- through its cooldown like a keyed ability's.
      local p = ability and self.passive and self.passive.key == ability.key and self.passive or nil
      local title = ability and (ability.hud or ability.title) or "passive"
      local titleColor = ability and Tiers.color(ability.tier) or { 0.6, 0.6, 0.65 } -- named in its tier's colour
      local middle, middleColor
      if not ability then
        UI.ring(cx, cy, r, 0, { 1, 1, 1 }, 4)
      elseif p and p.phase == "active" then
        local c = ability.color
        local pulse = 0.5 + 0.5 * math.sin(self.time * 8)
        love.graphics.setColor(c[1], c[2], c[3], 0.25 + 0.35 * pulse)
        love.graphics.circle("fill", cx, cy, r + 6 + pulse * 3, 48)
        UI.ring(cx, cy, r, 1, c, 5)
        middle, middleColor = ("%.1f"):format(p.left), { 1, 1, 1 }
        titleColor = c
      elseif p and p.phase == "cooldown" then
        local c = ability.color
        UI.ring(cx, cy, r, 1 - p.left / math.max(0.01, p.total), { c[1], c[2], c[3], 0.85 }, 5)
        middle = p.left >= 10 and ("%d"):format(p.left) or ("%.1f"):format(p.left)
        middleColor = { 1, 1, 1 }
      else
        local c = ability.color
        local flash = self.readyFlash[ability.key]
        if flash then
          local k = flash / 0.6
          love.graphics.setLineWidth(2)
          love.graphics.setColor(c[1], c[2], c[3], 0.8 * k)
          love.graphics.circle("line", cx, cy, r + 5 + (1 - k) * 18, 48)
          love.graphics.setLineWidth(1)
        end
        love.graphics.setColor(c[1], c[2], c[3], 0.2)
        love.graphics.circle("fill", cx, cy, r + 6, 48)
        UI.ring(cx, cy, r, 1, c, 5)
      end
      if ability then
        Icons.draw(ability.key, cx, cy, self.hudIcon, middle and 0.3 or 1)
      end
      if middle then
        love.graphics.setFont(body)
        UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), middleColor)
      end
      love.graphics.setFont(small)
      UI.label(title, cx - math.floor(small:getWidth(title) / 2), cy + r + 4, titleColor)
    elseif not ability then
      UI.ring(cx, cy, r, 0, { 1, 1, 1 }, 4)
    else
      local key = Controls.name(Controls.bindings("ability-" .. i)[1])
      local left = self.cooldowns[ability.key]
      local c = ability.color
      local middle, middleColor, title, titleColor
      if left then
        local total = ability.cooldown * Features.reduce("stat", 1, client, client.myId, "cooldown")
        UI.ring(cx, cy, r, 1 - left / math.max(0.01, total), { c[1], c[2], c[3], 0.85 }, 5)
        middle = left >= 10 and ("%d"):format(left) or ("%.1f"):format(left)
        middleColor = { 1, 1, 1 }
        title, titleColor = ability.hud or ability.title, { 0.7, 0.7, 0.75 }
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
        title = aiming and (placed(ability) and "fire: place" or "release") or (ability.hud or ability.title)
        titleColor = aiming and c or Tiers.color(ability.tier) -- named in its tier's colour
      end
      Icons.draw(ability.key, cx, cy, self.hudIcon, middle and 0.3 or 1)
      if middle then
        love.graphics.setFont(body)
        UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), middleColor)
      end
      Icons.keyBadge(key, cx, cy, r, middle and 0.5 or 1, small)
      love.graphics.setFont(small)
      UI.label(title, cx - math.floor(small:getWidth(title) / 2), cy + r + 4, titleColor)
    end
  end
  if self:frozen(client.myId) then
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
    local by, ability = tonumber(args[1]), kindOf(args[2])
    local x, y, seconds = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    local angle = tonumber(args[6]) or 0
    if not (ability and x and y and seconds) then
      return
    end
    local e = { ability = ability, by = by, x = x, y = y, angle = angle, t = 0, seconds = seconds }
    Abilities.effects[#Abilities.effects + 1] = e
    if ability.onFired then
      ability.onFired(e, client)
    end
    for i = 7, #args do
      local id = tonumber(args[i])
      if id then
        Abilities.heldUntil[id] = Abilities.time + seconds
      end
    end
    if by == client.myId and not Abilities.lifted[ability.key] then
      -- Clothes (gear) may bring it back sooner.
      Abilities.cooldowns[ability.key] = ability.cooldown * Features.reduce("stat", 1, client, by, "cooldown")
    end
    Sounds.play(ability.sound, x, y)
  end,
  ABL_SLOTS = function(_client, args)
    local slots = {}
    for slot, key in ipairs(args) do
      if kindOf(key) and slot <= Abilities.slotCount then
        slots[slot] = key
      end
    end
    Abilities.slots = slots
    if Abilities.aiming and not slots[Abilities.aiming] then
      Abilities.aiming = nil -- it left the slot mid-aim
    end
    if Abilities.passive and Tiers.base(slots[Abilities.passiveSlot] or EMPTY) ~= Abilities.passive.key then
      Abilities.passive = nil -- put down: whatever it was doing is over
    end
  end,
  ABL_REACH = function(_client, args)
    if Kinds.byKey[args[1] or EMPTY] then
      Abilities.lifted[args[1]] = args[2] == "1" or nil
      if Abilities.lifted[args[1]] then
        Abilities.cooldowns[args[1]] = nil -- ready now
      end
    end
  end,
  ABL_PASSIVE = function(_client, args)
    local key, phase, seconds = args[1], args[2], tonumber(args[3])
    if not (Kinds.byKey[key] and seconds) then
      return
    end
    if phase == "idle" then
      if Abilities.passive and Abilities.passive.key == key then
        Abilities.readyFlash[key] = 0.6 -- back: the same burst a keyed ability gets
      end
      Abilities.passive = nil
    else
      Abilities.passive = { key = key, phase = phase, left = seconds, total = seconds }
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
    lifted = {}, -- player id -> ability key -> true while its range and cooldown are lifted (a cheat)
  }
  for _, p in pairs(server.players) do
    self:serverPlayerJoined(server, p)
  end
  for _, ability in ipairs(Kinds.list) do
    if ability.serverReset then
      ability.serverReset() -- anything left in the world from the last game
    end
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
    sv.lifted[player.id] = nil
    for _, ability in ipairs(Kinds.list) do
      if ability.serverForget then
        ability.serverForget(player)
      end
    end
  end
end

--- Does `player` carry ability `key` (in any tier) in a slot on the host?
function Abilities:serverOwns(player, key)
  local slots = self.sv and self.sv.slots[player.id]
  return slots ~= nil and slotOf(slots, key) ~= nil
end

--- Ability `key` as `player` carries it on the host, in its tier, or nil.
function Abilities:serverKind(player, key)
  local slots = self.sv and self.sv.slots[player.id]
  local slot = slots and slotOf(slots, key)
  return slot and kindOf(slots[slot]) or nil
end

--- `player` takes the ability item they carry for `key` ("leap",
--- "leap@rare") and puts it in slot `slot`; one already there goes back
--- into the bag as an item, in its tier. Another tier of an ability they
--- carry swaps with that one in its own slot, whatever `slot` says.
--- Returns true if it happened.
function Abilities:serverEquip(server, player, key, slot)
  local slots = self.sv and self.sv.slots[player.id]
  local buildings = Features.byName.buildings
  if not (slots and kindOf(key) and slot and buildings and buildings.serverTake and Features.present(player)) then
    return false
  end
  local have = slotOf(slots, key)
  if have then
    if slots[have] == key then
      return false -- they carry that one already
    end
    slot = have -- trading it for another tier, where it is
  end
  if not fits(key, slot) then
    return false -- no such slot, or the wrong kind of slot
  end
  if buildings:serverTake(server, player, "ability-" .. key, 1) < 1 then
    return false -- they don't carry one
  end
  local old = slots[slot]
  if old and buildings:serverGive(server, player, "ability-" .. old, 1) < 1 then
    buildings:serverGive(server, player, "ability-" .. key, 1) -- no room for the old one: nothing changes
    return false
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

-- Saved worlds (docs/persistence.md) ----------------------------------------

local SAVE_VERSION = 1

--- `player`'s part of a saved world: the ability key in each slot, with
--- its tier ("leap@rare"). Always
--- kept, since an empty set is not the same as what everyone starts with.
function Abilities:serverSavePlayer(_server, player)
  local slots = self.sv and self.sv.slots[player.id]
  if not slots or player.bot then
    return nil
  end
  local out = {}
  for slot = 1, self.slotCount do
    out[slot] = slots[slot]
  end
  return { version = SAVE_VERSION, slots = out }
end

--- Put the saved slots back over the start set; an ability no longer in
--- kinds.lua, one in a slot it doesn't fit or one carried twice is dropped.
--- Cooldowns start fresh.
function Abilities:serverLoadPlayer(server, player, data)
  local sv = self.sv
  if not (sv and sv.slots[player.id]) or type(data) ~= "table" or (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  elseif type(data.slots) ~= "table" then
    return
  end
  local slots = {}
  for slot = 1, self.slotCount do
    local key = data.slots[slot]
    if type(key) == "string" and fits(key, slot) and not slotOf(slots, key) then
      slots[slot] = key
    end
  end
  sv.slots[player.id] = slots
  self:sendSlots(server, player)
end

--- Lift the range and cooldown of ability `key` for `player` (on = true),
--- or put them back; they hear ABL_REACH so their aim agrees. Returns whether it is
--- lifted now. The cheats feature does this.
function Abilities:serverSetReach(server, player, key, on)
  local sv = self.sv
  key = Tiers.base(key or EMPTY)
  if not (sv and Kinds.byKey[key]) then
    return false
  end
  local lifted = sv.lifted[player.id] or {}
  sv.lifted[player.id] = lifted
  lifted[key] = on and true or nil
  local ready = sv.readyAt[player.id]
  if on and ready then
    ready[key] = nil -- ready now, whatever was left of its cooldown
  end
  server:send(player, Protocol.encode("ABL_REACH", key, on and 1 or 0))
  return lifted[key] == true
end

--- Are the range and cooldown of ability `key` lifted for `player`?
function Abilities:serverReachLifted(player, key)
  local lifted = self.sv and self.sv.lifted[player.id]
  return lifted ~= nil and lifted[key] == true
end

--- Everything moved to a new map: nothing is held there.
function Abilities:mapChanged(_map, server)
  if server and self.sv then
    self.sv.players, self.sv.bodies, self.sv.cars = {}, {}, {}
  end
end

--- The `serverHeld` convention: is this player held still on the host
--- (frozen, or in the air)?
function Abilities:serverHeld(_server, player)
  local sv = self.sv
  return sv ~= nil and ((sv.players[player.id] or 0) > sv.time or Leap.serverLeaping(player.id))
end

--- The `serverHidden` convention (`Features.visible` asks): is this player
--- out of sight on the host, a chicken hiding them?
function Abilities:serverHidden(_server, player)
  return self.sv ~= nil and Chicken.serverHiding(player.id, self.sv.time)
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
  if not (sv and Features.present(player)) or Leap.serverLeaping(player.id) then
    return false -- nobody to hold, or in the air: nothing holds a leaper
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
  -- Abilities with something standing in the world (the MG nest) run it.
  for _, ability in ipairs(Kinds.list) do
    if ability.serverStep then
      ability.serverStep(server, dt, self)
    end
  end
  -- Passive abilities work by being carried: tick the one in each
  -- player's passive slot.
  for id, slots in pairs(sv.slots) do
    local player = server.players[id]
    local ability = player and kindOf(slots[self.passiveSlot])
    if ability and ability.serverTick then
      ability.serverTick(server, player, dt, self, ability)
    end
  end
end

--- A passive ability tells its carrier what it is up to: `phase` is
--- "idle", "active" or "cooldown" and `seconds` how long that lasts.
function Abilities:serverPassive(server, player, key, phase, seconds)
  server:send(player, Protocol.encode("ABL_PASSIVE", key, phase, ("%.1f"):format(seconds or 0)))
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
    local key = Tiers.base(args[1] or EMPTY)
    local ability = Abilities:serverKind(player, key) -- in the tier they carry it
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (sv and Kinds.byKey[key] and x and y) or not Features.present(player) then
      return
    end
    if not ability or ability.passive then
      return -- not in any of their slots, or not the casting kind: a stale or forged cast
    end
    if Abilities:serverHeld(server, player) then
      return -- frozen people cast nothing
    end
    if ability.onFoot and player.vehicle then
      return -- not from behind the wheel; the client knows, so this was stale or forged
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
    local lifted = Abilities:serverReachLifted(player, key)
    local range = lifted and Abilities.liftedRange or ability.range
    if d > range then
      x, y = ox + (x - ox) / d * range, oy + (y - oy) / d * range
    end
    if not lifted then
      ready[key] = sv.time + ability.cooldown * Features.reduce("serverStat", 1, server, player, "cooldown")
    end
    local held, angle, nx, ny, seconds = ability.serverCast(server, player, x, y, Abilities, ability)
    x, y = nx or x, ny or y -- an ability may settle somewhere else (the nest steps out of walls)
    -- ... and last longer than usual this time (a long leap flies longer).
    local named = Tiers.join(key, ability.tier)
    server:broadcast(Protocol.encode("ABL_FIRED", player.id, named, ("%.1f"):format(x), ("%.1f"):format(y),
      ("%.2f"):format(seconds or ability.seconds), ("%.3f"):format(angle or 0), unpack(held or {})))
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
