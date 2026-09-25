-- Inventory: the character screen (I). What you carry (the buildings
-- feature keeps the items), the guns you hold (weapons) and your abilities
-- around a picture of you; screen.lua draws it.
--
-- While it is up the mouse is yours, not the gun's: weapons doesn't fire,
-- abilities don't aim, vision stops panning and lends us its arrow cursor,
-- drawn last so it sits over the panel (the `pointerTaken` convention,
-- docs/features.md), and the number keys are ours (`menuOpen`). It never
-- opens over the upgrade shop, the shop or a building menu, and closes if
-- one of those comes up.
--
-- The weapon slots are the number keys: drag a gun item from the bag onto
-- a slot and that key fires it (weapons:equip; a gun already there swaps
-- into the bag), drag a gun from its slot into the bag to put it down
-- (weapons:unequip: it becomes a "gun-<key>" item, if there is room, and
-- the slot is empty), or onto another slot to change its key
-- (weapons:move). A click on a slot selects its gun. The ability slots
-- work the same way with "ability-<key>" items (abilities:equip, unequip,
-- move). Medkits and energy drinks go the same way into the quick slots
-- beside the abilities (buildings.usables; buildings:quickPut takes the
-- stack out of the bag, quickTake puts it back); their keys (H, J) use one
-- from there. A vest ("armor-<key>") dragged onto the armor gear slot is
-- put on (armor:equip) and dragged back into the bag taken off
-- (armor:unequip; a damaged one is thrown away). Clothes ("gear-<key>")
-- go onto the head, body, pants and shoes slots the same way (gear:equip,
-- unequip). Any stack in the bag dragged onto the bin under the items is
-- destroyed (buildings:trash); something in a slot goes into the bag first.
-- The host does the moving and tells each feature what is in its slots;
-- this only asks.
--
-- Equipment comes in tiers (tiers/init.lua), and every box that holds some
-- shows its tier's colour. A gun or ability dragged from the bag in another
-- tier than the one you carry swaps with it (a better pistol for yours); a
-- vest or piece of clothing swaps the way it always did. What is dragged
-- keeps its tier: `key` is "leap@rare", "vest@rare", and a gun has `tier`.

local Features = require("src.features")
local Controls = require("src.controls")
local Kinds = require("src.features.buildings.kinds")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Screen = require("src.features.inventory.screen")

local Inventory = {
  name = "inventory",
  priority = 995, -- draws over every other HUD; only vision's cursor is later
}

Inventory.open = false
-- What is being dragged: { kind = "gun", index, tier }, { kind = "ability", key }, { kind = "quick", item },
-- { kind = "armor", key }, { kind = "gear", key, slot } or { kind = "item" } (anything else in the bag,
-- which only the bin takes), with from = "slot" | "bag" | "quick", box (the slot or item box it left),
-- x0, y0, moved, and from the bag the stack it is: item, n.
Inventory.drag = nil
Inventory.dragStart = 5 -- px the mouse must move with the button down before a press is a drag
Inventory.notice = nil -- { text, t }: why a drop did nothing
Inventory.noticeTime = 2.5

local function buildings()
  return Features.byName.buildings
end

local function weapons()
  return Features.byName.weapons
end

local function abilities()
  return Features.byName.abilities
end

local function armor()
  return Features.byName.armor
end

local function gear()
  return Features.byName.gear
end

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- Another panel up that wants the middle of the screen or the number keys?
local function otherOpen()
  local upgrades, shop, b = Features.byName.upgrades, Features.byName.shop, buildings()
  return (upgrades and upgrades.open) or (shop and shop.open) or (b and b.menu) or false
end

function Inventory:load()
  Controls.register("inventory", "Open / close the inventory", "i")
end

function Inventory:enterGame()
  self.open, self.drag, self.notice = false, nil, nil
end

function Inventory:exitGame()
  self:enterGame()
end

--- The `menuOpen` convention: the number keys are ours while we are up.
function Inventory:menuOpen()
  return self.open
end

--- The `pointerTaken` convention: so is the mouse.
function Inventory:pointerTaken()
  return self.open
end

function Inventory:say(text)
  self.notice = { text = text, t = self.noticeTime }
end

--- The `closeMenu` convention: Esc takes the screen down.
function Inventory:closeMenu()
  if not self.open then
    return false
  end
  self.open, self.drag = false, nil
  return true
end

--- Opening takes down whatever other panel is up (the shop, the upgrade
--- shop, the building menu), so I goes straight from the shop to the bag.
function Inventory:toggle(client)
  if self.open then
    self:closeMenu()
    return
  end
  Features.call("closeMenu", client)
  if not otherOpen() then
    self.open, self.notice = true, nil
  end
end

function Inventory:keypressed(key, client)
  if Controls.is("inventory", key) then
    self:toggle(client)
  end
end

--- What a press on (x, y) would pick up: a gun in its weapon slot, an
--- ability in its slot, the stack in a quick slot, or any stack in the bag.
function Inventory:pick(x, y, client)
  local L = Screen.layout()
  local w, a, b = weapons(), abilities(), buildings()
  local ar, g = armor(), gear()
  local armorSlot = L.gear[Screen.ARMOR]
  if inside(armorSlot, x, y) then
    local worn = ar and client and ar:mine(client)
    if worn then
      return { kind = "armor", key = worn.kind, from = "slot" }
    end
    return nil
  end
  for i, r in ipairs(L.gear) do
    if i ~= Screen.ARMOR and inside(r, x, y) then
      local key = g and client and g:mine(client)[r.name]
      if key then
        return { kind = "gear", key = key, slot = r.name, from = "slot" }
      end
      return nil
    end
  end
  for _, r in ipairs(L.quick) do
    if inside(r, x, y) then
      if b and b:quickCount(r.item) > 0 then
        return { kind = "quick", item = r.item, from = "quick" }
      end
      return nil
    end
  end
  for slot, r in ipairs(L.weapons) do
    if inside(r, x, y) then
      local index = w and w.slots[slot]
      if index and Guns.list[index] then
        return { kind = "gun", index = index, tier = w:tierOf(index), from = "slot", box = slot }
      end
      return nil
    end
  end
  for slot, r in ipairs(L.abilities) do
    if inside(r, x, y) then
      local key = a and a.slots[slot]
      if key then
        return { kind = "ability", key = key, from = "slot", box = slot }
      end
      return nil
    end
  end
  if b then
    local list = Screen.stacks(b.inventory)
    for i, r in ipairs(L.items) do
      if inside(r, x, y) then
        local s = i <= b.slots and list[i]
        if not s then
          return nil
        end
        local d
        local base, tier = Tiers.split(s.item)
        local gunKey = tier and base:match("^gun%-(.+)$")
        local gun = gunKey and Guns[gunKey]
        local abilityKey = s.item:match("^ability%-(.+)$") -- with its tier: "leap@rare"
        local piece = s.item:match("^gear%-") and g and g.pieceOf(s.item:sub(6))
        if gun then
          d = { kind = "gun", index = gun.index, tier = tier }
        elseif abilityKey and a and a.kindOf(abilityKey) then
          d = { kind = "ability", key = abilityKey }
        elseif b.usableByItem and b.usableByItem[s.item] then
          d = { kind = "quick", item = s.item }
        elseif s.item:match("^armor%-") and ar and ar.kindOf(s.item:sub(7)) then
          d = { kind = "armor", key = s.item:sub(7) }
        elseif piece then
          d = { kind = "gear", key = s.item:sub(6), slot = piece.slot }
        else
          d = { kind = "item", item = s.item } -- materials, ammo: only the bin takes them
        end
        d.from, d.box, d.item, d.n = "bag", i, s.item, s.n
        return d
      end
    end
  end
  return nil
end

function Inventory:mousepressed(x, y, button, client)
  if not self.open or button ~= 1 then
    return
  end
  local d = self:pick(x, y, client)
  if d then
    d.x0, d.y0, d.moved = x, y, false
    self.drag = d
  end
end

--- A press that never moved: on a weapon slot it selects that gun.
function Inventory:click(client, d)
  local w = weapons()
  if d.kind == "gun" and d.from == "slot" and w then
    w:selectGun(client, d.index)
  end
end

--- The slot under (x, y) among `boxes` (a row of slot rectangles standing
--- in `area`, with `slots` the slot -> content map and `count` how many):
--- the one whose box it is in, or, anywhere else in the area, the first
--- empty one.
local function slotAt(boxes, area, slots, count, x, y)
  for slot, r in ipairs(boxes) do
    if inside(r, x, y) then
      return slot
    end
  end
  if inside(area, x, y) then
    for slot = 1, count do
      if not slots[slot] then
        return slot
      end
    end
  end
  return nil
end

--- An ability came down at (x, y): into a slot, or into the bag.
function Inventory:dropAbility(client, d, x, y, L)
  local a, b = abilities(), buildings()
  if not (a and b) then
    return
  end
  local ability = a.kindOf(d.key)
  local slot = slotAt(L.abilities, L.abilitiesArea, a.slots, a.slotCount, x, y)
  local have = a:slotOf(d.key) -- the slot it is in, in whatever tier
  if d.from == "slot" and inside(L.itemsArea, x, y) then
    if Kinds.room(b.inventory, b.slots, "ability-" .. d.key) < 1 then
      self:say("No room in your bag for " .. ability.title .. ".")
    else
      a:unequip(client, d.box)
    end
  elseif d.from == "slot" and slot then
    if a:canMove(d.box, slot) then
      a:move(client, d.box, slot)
    else
      self:sayFit(ability, slot)
    end
  elseif d.from == "bag" and (slot or (have and inside(L.abilitiesArea, x, y))) then
    if have and a.slots[have] == d.key then
      self:say("You already carry " .. ability.title .. ".")
    elseif not a:fits(d.key, have or slot) then
      self:sayFit(ability, have or slot)
    else
      a:equip(client, d.key, slot or have) -- another tier of one I carry swaps with it where it is
    end
  elseif d.from == "bag" and inside(L.abilitiesArea, x, y) then
    self:say("No empty ability slot: drop it on the one to swap with.")
  end
end

--- Why `ability` can't go in ability slot `slot`.
function Inventory:sayFit(ability, slot)
  if slot == abilities().passiveSlot then
    self:say("Only a passive ability goes in the passive slot.")
  elseif ability.passive then
    self:say(ability.title .. " is passive: it goes in the passive slot.")
  else
    self:say("A keyed ability can't swap with a passive one.")
  end
end

--- A quick-slot stack came down at (x, y): from the bag into its slot, or
--- out of the slot back into the bag.
function Inventory:dropQuick(client, d, x, y, L)
  local b = buildings()
  if not b then
    return
  end
  local u = b.usableByItem[d.item]
  local slot
  for _, r in ipairs(L.quick) do
    if inside(r, x, y) then
      slot = r
    end
  end
  if d.from == "bag" and slot then
    if slot.item ~= d.item then
      self:say("That slot is for " .. slot.usable.title .. ".")
    elseif b:quickCount(d.item) >= u.max then
      self:say("That slot is full.")
    else
      b:quickPut(client, d.item)
    end
  elseif d.from == "quick" and inside(L.itemsArea, x, y) then
    if Kinds.room(b.inventory, b.slots, d.item) < 1 then
      self:say("No room in your bag for the " .. u.title .. ".")
    else
      b:quickTake(client, d.item)
    end
  end
end

--- A vest came down at (x, y): from the bag onto the armor slot to put it
--- on, or from the slot into the bag to take it off.
function Inventory:dropArmor(client, d, x, y, L)
  local ar, b = armor(), buildings()
  if not (ar and b) then
    return
  end
  local kind = ar.kindOf(d.key)
  if d.from == "bag" and inside(L.gear[Screen.ARMOR], x, y) then
    local worn = ar:mine(client)
    if worn and worn.points < worn.max then
      self:say("Your " .. (ar.kindOf(worn.kind) or {}).title .. " is damaged: it will be thrown away.")
    end
    ar:equip(client, d.key)
  elseif d.from == "slot" and inside(L.itemsArea, x, y) then
    local worn = ar:mine(client)
    if worn and worn.points < worn.max then
      self:say("The " .. kind.title .. " is damaged: thrown away.")
      ar:unequip(client)
    elseif Kinds.room(b.inventory, b.slots, "armor-" .. d.key) < 1 then
      self:say("No room in your bag for the " .. kind.title .. ".")
    else
      ar:unequip(client)
    end
  end
end

--- A piece of clothing came down at (x, y): from the bag onto its slot to
--- put it on (whatever was there swaps into the bag), or from its slot
--- into the bag to take it off.
function Inventory:dropGear(client, d, x, y, L)
  local g, b = gear(), buildings()
  if not (g and b) then
    return
  end
  local piece = g.pieceOf(d.key)
  local slot
  for i, r in ipairs(L.gear) do
    if i ~= Screen.ARMOR and inside(r, x, y) then
      slot = r
    end
  end
  if d.from == "bag" and (slot or inside(L.gear[Screen.ARMOR], x, y)) then
    if not slot or slot.name ~= piece.slot then
      self:say("The " .. piece.title .. " goes on your " .. piece.slot .. ".")
    else
      g:equip(client, d.key)
    end
  elseif d.from == "slot" and inside(L.itemsArea, x, y) then
    if Kinds.room(b.inventory, b.slots, "gear-" .. d.key) < 1 then
      self:say("No room in your bag for the " .. piece.title .. ".")
    else
      g:unequip(client, d.slot)
    end
  end
end

--- Something came down on the bin: a stack from the bag is destroyed;
--- anything in a slot has to go into the bag first.
function Inventory:dropTrash(client, d)
  local b = buildings()
  if not b then
    return
  end
  if d.from ~= "bag" then
    self:say("Put it in your bag first, then drag it into the bin.")
    return
  end
  b:trash(client, d.item, d.n)
  self:say("Destroyed " .. Kinds.label(d.item, d.n) .. ".")
end

--- The button came up at (x, y) after a drag: put the gun, ability, stack,
--- vest or piece of clothing where it landed, or destroy it in the bin.
function Inventory:drop(client, d, x, y)
  local L = Screen.layout()
  if inside(L.trash, x, y) then
    return self:dropTrash(client, d)
  elseif d.kind == "item" then
    return -- nowhere to put it but the bin
  elseif d.kind == "ability" then
    return self:dropAbility(client, d, x, y, L)
  elseif d.kind == "quick" then
    return self:dropQuick(client, d, x, y, L)
  elseif d.kind == "armor" then
    return self:dropArmor(client, d, x, y, L)
  elseif d.kind == "gear" then
    return self:dropGear(client, d, x, y, L)
  end
  local w, b = weapons(), buildings()
  if not (w and b) then
    return
  end
  local gun = Guns.list[d.index]
  local slot = slotAt(L.weapons, L.weaponsArea, w.slots, w.slotCount, x, y)
  local have = w:owns(d.index)
  if d.from == "slot" and inside(L.itemsArea, x, y) then
    if d.index == Guns.DEFAULT then
      self:say("The " .. gun.name .. " stays with you.")
    elseif Kinds.room(b.inventory, b.slots, Tiers.join("gun-" .. gun.key, d.tier)) < 1 then
      self:say("No room in your bag for the " .. gun.name .. ".")
    else
      w:unequip(client, d.box)
    end
  elseif d.from == "slot" and slot then
    w:move(client, d.box, slot)
  elseif d.from == "bag" and (slot or (have and inside(L.weaponsArea, x, y))) then
    if have and w:tierOf(d.index) == d.tier then
      self:say("You already carry a " .. Tiers.named(gun.name, d.tier) .. ".")
    elseif not have and w.slots[slot] == Guns.DEFAULT then
      self:say("The " .. Guns.at(Guns.DEFAULT).name .. " stays with you.")
    else
      w:equip(client, d.index, slot or w:slotOf(d.index), d.tier) -- another tier swaps with the one I carry
    end
  elseif d.from == "bag" and inside(L.weaponsArea, x, y) then
    self:say("No empty weapon slot: drop it on the one to swap with.")
  end
end

function Inventory:update(dt, client)
  if self.notice then
    self.notice.t = self.notice.t - dt
    if self.notice.t <= 0 then
      self.notice = nil
    end
  end
  if self.open and otherOpen() then
    self.open, self.drag = false, nil
  end
  local d = self.drag
  if not (self.open and d) then
    self.drag = nil
    return
  end
  local mx, my = love.mouse.getPosition()
  if not d.moved and (math.abs(mx - d.x0) > self.dragStart or math.abs(my - d.y0) > self.dragStart) then
    d.moved = true
  end
  if not love.mouse.isDown(1) then
    self.drag = nil
    if d.moved then
      self:drop(client, d, mx, my)
    else
      self:click(client, d)
    end
  end
end

function Inventory:drawHUD(client)
  local b = buildings()
  if not b then
    return
  end
  if not self.open then
    return
  end
  local d = self.drag and self.drag.moved and self.drag or nil
  Screen.draw(b, Screen.stacks(b.inventory), d, self.notice and self.notice.text, client)
  if d then
    Screen.drawDrag(d, love.mouse.getPosition())
  end
  -- The cursor last of all, over the panel and whatever is being dragged.
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client)
  end
  love.graphics.setColor(1, 1, 1)
end

return Inventory
