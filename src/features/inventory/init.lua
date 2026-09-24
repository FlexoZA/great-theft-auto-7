-- Inventory: the character screen (I). What you carry (the buildings
-- feature keeps the items), the guns you hold (weapons) and your abilities
-- around a picture of you; screen.lua draws it.
--
-- While it is up the mouse is yours, not the gun's: weapons doesn't fire,
-- abilities don't aim, vision stops panning and lends us its arrow cursor,
-- drawn last so it sits over the panel (the `pointerTaken` convention,
-- docs/features.md), and the number keys are ours (`menuOpen`). It never
-- opens over the upgrade shop or a building menu, and closes if one of
-- those comes up.
--
-- The weapon slots are the number keys: drag a gun item from the bag onto
-- a slot and that key fires it (weapons:equip; a gun already there swaps
-- into the bag), drag a gun from its slot into the bag to put it down
-- (weapons:unequip: it becomes a "gun-<key>" item, if there is room, and
-- the slot is empty), or onto another slot to change its key
-- (weapons:move). A click on a slot selects its gun. The host does the
-- moving and tells weapons what is in each slot; this only asks.

local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Kinds = require("src.features.buildings.kinds")
local Guns = require("src.features.weapons.guns")
local Screen = require("src.features.inventory.screen")

local Inventory = {
  name = "inventory",
  priority = 995, -- draws over every other HUD; only vision's cursor is later
}

Inventory.open = false
Inventory.drag = nil -- { index, from = "slot" | "bag", box, x0, y0, moved }: a gun on the move, out of `box`
Inventory.dragStart = 5 -- px the mouse must move with the button down before a press is a drag
Inventory.notice = nil -- { text, t }: why a drop did nothing
Inventory.noticeTime = 2.5

local function buildings()
  return Features.byName.buildings
end

local function weapons()
  return Features.byName.weapons
end

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- Another panel up that wants the middle of the screen or the number keys?
local function otherOpen()
  local shop, b = Features.byName.upgrades, buildings()
  return (shop and shop.open) or (b and b.menu) or false
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

function Inventory:toggle()
  if self.open then
    self.open, self.drag = false, nil
  elseif not otherOpen() then
    self.open, self.notice = true, nil
  end
end

function Inventory:keypressed(key)
  if Controls.is("inventory", key) then
    self:toggle()
  end
end

--- What a press on (x, y) would pick up: a gun in its weapon slot, or a
--- gun item in the bag.
function Inventory:pick(x, y)
  local L = Screen.layout()
  local w, b = weapons(), buildings()
  for slot, r in ipairs(L.weapons) do
    if inside(r, x, y) then
      local index = w and w.slots[slot]
      if index and Guns.list[index] then
        return { index = index, from = "slot", box = slot }
      end
      return nil
    end
  end
  if b then
    local list = Screen.stacks(b.inventory)
    for i, r in ipairs(L.items) do
      if inside(r, x, y) then
        local s = i <= b.slots and list[i]
        local key = s and s.item:match("^gun%-(.+)$")
        local gun = key and Guns[key]
        if gun then
          return { index = gun.index, from = "bag", box = i }
        end
        return nil
      end
    end
  end
  return nil
end

function Inventory:mousepressed(x, y, button)
  if not self.open or button ~= 1 then
    return
  end
  local d = self:pick(x, y)
  if d then
    d.x0, d.y0, d.moved = x, y, false
    self.drag = d
  end
end

--- A press that never moved: on a weapon slot it selects that gun.
function Inventory:click(client, d)
  local w = weapons()
  if d.from == "slot" and w then
    w:selectGun(client, d.index)
  end
end

--- The weapon slot under (x, y): the one whose box it is in, or, anywhere
--- else on the weapons block, the first empty one.
local function slotAt(L, w, x, y)
  for slot, r in ipairs(L.weapons) do
    if inside(r, x, y) then
      return slot
    end
  end
  if inside(L.weaponsArea, x, y) then
    for slot = 1, w.slotCount do
      if not w.slots[slot] then
        return slot
      end
    end
  end
  return nil
end

--- The button came up at (x, y) after a drag: put the gun where it landed.
function Inventory:drop(client, d, x, y)
  local L = Screen.layout()
  local w, b = weapons(), buildings()
  if not (w and b) then
    return
  end
  local gun = Guns.list[d.index]
  local slot = slotAt(L, w, x, y)
  if d.from == "slot" and inside(L.itemsArea, x, y) then
    if d.index == Guns.DEFAULT then
      self:say("The " .. gun.name .. " stays with you.")
    elseif Kinds.room(b.inventory, b.slots, "gun-" .. gun.key) < 1 then
      self:say("No room in your bag for the " .. gun.name .. ".")
    else
      w:unequip(client, d.box)
    end
  elseif d.from == "slot" and slot then
    w:move(client, d.box, slot)
  elseif d.from == "bag" and slot then
    if w:owns(d.index) then
      self:say("You already carry a " .. gun.name .. ".")
    elseif w.slots[slot] == Guns.DEFAULT then
      self:say("The " .. Guns.at(Guns.DEFAULT).name .. " stays with you.")
    else
      w:equip(client, d.index, slot)
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

--- A reminder of the key, bottom left, while the screen is shut.
local function drawHint(b)
  local used = Kinds.slotsUsed(b.inventory)
  local line = ("%s: inventory (%d/%d)"):format(Controls.name(Controls.bindings("inventory")[1]), used, b.slots)
  if (b.inventory.medkit or 0) > 0 then
    line = line .. "   " .. Controls.name(Controls.bindings("use-medkit")[1]) .. ": use medkit"
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.85, 0.8, 0.6)
  love.graphics.print(line, 10, love.graphics.getHeight() - 28)
end

function Inventory:drawHUD(client)
  local b = buildings()
  if not b then
    return
  end
  if not self.open then
    drawHint(b)
    return
  end
  local d = self.drag and self.drag.moved and self.drag or nil
  Screen.draw(b, Screen.stacks(b.inventory), d, self.notice and self.notice.text)
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
