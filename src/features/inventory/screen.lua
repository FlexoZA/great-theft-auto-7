-- The inventory screen's picture: the character in the middle of the
-- screen with everything they carry around them.
--
--   top left      the character and the gear slots they will wear one day
--                 (head, body, legs, other); nothing fits in them yet
--   top right     the weapon slots, one per gun, the ones I hold drawn in
--                 full with what is in the magazine and what is left to
--                 load, the one in hand lit up, the rest a faint outline
--                 of the gun that would go there; under them the ability
--                 slots as the HUD shows them
--   bottom        the item slots buildings fills: a stack per box, locked
--                 ones greyed out until the upgrade shop opens them
--
-- `Screen.layout()` works out every box on the screen and `Screen.draw`
-- paints them; init.lua hit-tests the same rectangles for dragging. The
-- buildings feature owns the items, weapons the guns, abilities the
-- abilities; this file only reads them.

local Controls = require("src.controls")
local Features = require("src.features")
local UI = require("src.ui")
local Kinds = require("src.features.buildings.kinds")
local Render = require("src.features.buildings.render")
local Guns = require("src.features.weapons.guns")
local Icons = require("src.features.weapons.icons")

local Screen = {}

-- Tuning ------------------------------------------------------------------
Screen.width = 800 -- px; the panel is centred on the screen (nine item boxes across)
Screen.pad = 24 -- px inside the panel's edge
Screen.weaponSlots = 4 -- boxes on the weapon row, the spare ones empty
Screen.gear = { "head", "body", "legs", "other" } -- the slots down the character's side

local CELL, GAP = 76, 8 -- item boxes
local GEAR = 60 -- gear boxes
local GUN_W, GUN_H = 120, 96 -- weapon boxes: the icon over the name over the ammo
local ABL_W, ABL_H = 64, 72 -- ability boxes
local FIGURE_W = 120 -- px the character stands in
local SECTION_GAP = 16 -- px between the top half and the item rows
local LABEL_H = 22 -- px a section's title takes above its boxes

--- A slot's frame: `open` slots hold something, `lit` ones are selected.
local function box(x, y, w, h, open, lit)
  if lit then
    love.graphics.setColor(1, 0.85, 0.3, 0.18)
  else
    love.graphics.setColor(1, 1, 1, open and 0.10 or 0.03)
  end
  love.graphics.rectangle("fill", x, y, w, h, 6)
  if lit then
    love.graphics.setColor(1, 0.85, 0.3, 0.9)
    love.graphics.setLineWidth(2)
  else
    love.graphics.setColor(1, 1, 1, open and 0.35 or 0.12)
  end
  love.graphics.rectangle("line", x, y, w, h, 6)
  love.graphics.setLineWidth(1)
end

--- A section's title, small and gold, above its boxes.
local function heading(text, x, y)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3, 0.7)
  love.graphics.print(text:upper(), x, y)
end

--- The panel's frame and title.
local function panel(x, y, w, h, title)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.94)
  love.graphics.rectangle("fill", x, y, w, h, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, w, h, 10)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(title, x, y + 12, w, "center")
end

--- My inventory as the stacks that fill its slots, materials first.
function Screen.stacks(inventory)
  local items = {}
  for _, m in ipairs(Kinds.materials) do
    items[#items + 1] = m
  end
  local others = {}
  for item in pairs(inventory) do
    if not Kinds.isMaterial(item) then
      others[#others + 1] = item
    end
  end
  table.sort(others)
  for _, item in ipairs(others) do
    items[#items + 1] = item
  end
  local out = {}
  for _, item in ipairs(items) do
    local left, stack = inventory[item] or 0, Kinds.stack(item)
    while left > 0 do
      out[#out + 1] = { item = item, n = math.min(stack, left) }
      left = left - stack
    end
  end
  return out
end

--- Every rectangle on the screen for the window as it is now:
---   panel                  { x, y, w, h }
---   figure                 where the character stands
---   gear[i]                { x, y, w, h, name }, Screen.gear order
---   weapons[i]             { x, y, w, h }, Screen.weaponSlots of them
---   abilities[i]           { x, y, w, h }, as many as the HUD shows
---   items[i]               { x, y, w, h }, Kinds.MAX_SLOTS of them
---   weaponsArea / itemsArea  the block each row of boxes stands in, for drops
---   hint / foot            y of the text lines under the items
function Screen.layout()
  local abilities = Features.byName.abilities
  local abilitySlots = abilities and math.max(abilities.hudSlots, #abilities.slots) or 0
  local cols = math.floor((Screen.width - 2 * Screen.pad + GAP) / (CELL + GAP))
  local rows = math.ceil(Kinds.MAX_SLOTS / cols)
  local gearH = #Screen.gear * (GEAR + GAP) - GAP
  local rightH = LABEL_H + GUN_H + SECTION_GAP + LABEL_H + ABL_H
  local topH = math.max(gearH, rightH)
  local itemsH = rows * (CELL + GAP) - GAP
  local ph = 56 + topH + SECTION_GAP + LABEL_H + itemsH + 12 + 22 + 34
  local w, h = love.graphics.getDimensions()
  local px = math.floor((w - Screen.width) / 2)
  local py = math.max(8, math.floor((h - ph) / 2))
  local L = { panel = { x = px, y = py, w = Screen.width, h = ph } }
  L.gear, L.weapons, L.abilities, L.items = {}, {}, {}, {}

  -- The character and their gear down the left.
  local top = py + 56
  local x = px + Screen.pad
  L.figure = { x = x, y = top, w = FIGURE_W, h = topH }
  x = x + FIGURE_W + GAP
  for i, name in ipairs(Screen.gear) do
    L.gear[i] = { x = x, y = top + (i - 1) * (GEAR + GAP), w = GEAR, h = GEAR, name = name }
  end
  local leftW = FIGURE_W + GAP + GEAR

  -- Weapons over abilities down the right.
  x = px + Screen.pad + leftW + 2 * Screen.pad
  L.weaponsLabel = { x = x, y = top }
  for i = 1, Screen.weaponSlots do
    L.weapons[i] = { x = x + (i - 1) * (GUN_W + GAP), y = top + LABEL_H, w = GUN_W, h = GUN_H }
  end
  L.weaponsArea = {
    x = x - GAP, y = top, w = Screen.weaponSlots * (GUN_W + GAP) + GAP, h = LABEL_H + GUN_H + GAP,
  }
  local ay = top + LABEL_H + GUN_H + SECTION_GAP
  L.abilitiesLabel = { x = x, y = ay }
  for i = 1, abilitySlots do
    L.abilities[i] = { x = x + (i - 1) * (ABL_W + GAP), y = ay + LABEL_H, w = ABL_W, h = ABL_H }
  end

  -- The item boxes along the bottom.
  local iy = top + topH + SECTION_GAP
  L.itemsLabel = { x = px + Screen.pad, y = iy }
  for i = 1, Kinds.MAX_SLOTS do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    L.items[i] = { x = px + Screen.pad + col * (CELL + GAP), y = iy + LABEL_H + row * (CELL + GAP), w = CELL, h = CELL }
  end
  L.itemsArea = { x = px + Screen.pad - GAP, y = iy, w = cols * (CELL + GAP) + GAP, h = LABEL_H + itemsH + GAP }
  L.hint = iy + LABEL_H + itemsH + 12
  L.foot = py + ph - 26
  return L
end

--- The character: a plain figure standing in the box, front on, until
--- there are clothes to draw on them.
local function drawFigure(r)
  local cx, top = r.x + r.w / 2, r.y + 18
  local scale = math.min(1, (r.h - 36) / 200)
  local function s(v)
    return v * scale
  end
  love.graphics.setColor(1, 1, 1, 0.04)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  -- Shadow underfoot, then legs, torso, arms, head.
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", cx, top + s(200), s(38), s(9))
  love.graphics.setColor(0.28, 0.30, 0.40)
  love.graphics.rectangle("fill", cx - s(20), top + s(112), s(17), s(84), s(6))
  love.graphics.rectangle("fill", cx + s(3), top + s(112), s(17), s(84), s(6))
  love.graphics.setColor(0.36, 0.38, 0.50)
  love.graphics.rectangle("fill", cx - s(26), top + s(44), s(52), s(74), s(10))
  love.graphics.rectangle("fill", cx - s(40), top + s(48), s(13), s(66), s(6))
  love.graphics.rectangle("fill", cx + s(27), top + s(48), s(13), s(66), s(6))
  love.graphics.setColor(0.80, 0.65, 0.52)
  love.graphics.circle("fill", cx, top + s(22), s(20), 32)
  love.graphics.circle("fill", cx - s(34), top + s(120), s(6), 16)
  love.graphics.circle("fill", cx + s(34), top + s(120), s(6), 16)
end

--- The gear slots: empty for now, each named for what will go in it.
local function drawGear(L)
  love.graphics.setFont(UI.fonts.small)
  for _, r in ipairs(L.gear) do
    box(r.x, r.y, r.w, r.h, true, false)
    love.graphics.setColor(1, 1, 1, 0.3)
    love.graphics.printf(r.name, r.x, r.y + r.h / 2 - 8, r.w, "center")
  end
end

--- The weapon slots: a gun each in number-key order, the held one lit.
--- `lifted` is the index of the gun being dragged out of its slot, if any.
local function drawWeapons(L, lifted)
  local weapons = Features.byName.weapons
  local small = UI.fonts.small
  heading("weapons", L.weaponsLabel.x, L.weaponsLabel.y)
  for i, r in ipairs(L.weapons) do
    local gun = Guns.list[i]
    local held = weapons and weapons.gun == i and lifted ~= i
    local owned = gun and (not weapons or weapons:owns(i)) and lifted ~= i
    box(r.x, r.y, r.w, r.h, owned, held)
    love.graphics.setFont(small)
    if not gun then
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf("empty", r.x, r.y + r.h / 2 - 8, r.w, "center")
    elseif not owned then
      -- A gun I don't hold: its shape, faint, to show what goes here.
      Icons.draw(gun.key, r.x + r.w / 2, r.y + 27, 1.2, 0.2)
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.printf(gun.name, r.x, r.y + 48, r.w, "center")
      love.graphics.printf("empty", r.x, r.y + r.h - 20, r.w, "center")
    else
      -- The key in a badge in the corner, the gun drawn across the top,
      -- its name under it and the ammo along the bottom, red when the
      -- magazine is empty. Guns not in hand are drawn a little faded.
      local key = Controls.name(Controls.bindings("weapon-" .. i)[1])
      love.graphics.setColor(0.36, 0.56, 0.92, held and 1 or 0.6)
      love.graphics.rectangle("fill", r.x + 4, r.y + 4, 20, 18, 4)
      love.graphics.setColor(1, 1, 1)
      love.graphics.printf(key, r.x + 4, r.y + 5, 20, "center")
      Icons.draw(gun.key, r.x + r.w / 2 + 6, r.y + 27, 1.2, held and 1 or 0.7)
      love.graphics.setColor(held and { 1, 0.9, 0.3 } or { 0.85, 0.85, 0.9 })
      love.graphics.printf(gun.name, r.x, r.y + 48, r.w, "center")
      local ammo
      if weapons and weapons.infiniteAmmo then
        ammo = "inf"
      else
        local mag = weapons and weapons.mags[i] or gun.magazine
        local spare = weapons and weapons:reserve(i) or 0
        ammo = ("%d/%d"):format(mag, gun.magazine)
        if spare ~= math.huge then
          ammo = ammo .. (" +%d"):format(spare)
        end
        if mag < 1 then
          love.graphics.setColor(1, 0.45, 0.4)
        else
          love.graphics.setColor(0.6, 0.6, 0.65)
        end
      end
      if ammo == "inf" then
        love.graphics.setColor(0.6, 0.6, 0.65)
      end
      love.graphics.printf(ammo, r.x, r.y + r.h - 20, r.w, "center")
    end
  end
end

--- The ability slots, drawn the way the HUD draws them: a ring that
--- empties on a cast and fills back through the cooldown.
local function drawAbilities(L)
  local abilities = Features.byName.abilities
  if not abilities then
    return
  end
  local small, body = UI.fonts.small, UI.fonts.body
  heading("abilities", L.abilitiesLabel.x, L.abilitiesLabel.y)
  for i, r in ipairs(L.abilities) do
    local ability = abilities.slots[i]
    box(r.x, r.y, r.w, r.h, ability ~= nil, false)
    local cx, cy, radius = r.x + r.w / 2, r.y + 26, 20
    if not ability then
      UI.ring(cx, cy, radius, 0, { 1, 1, 1 }, 3)
      love.graphics.setFont(small)
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf("empty", r.x, r.y + r.h - 20, r.w, "center")
    else
      local key = Controls.name(Controls.bindings("ability-" .. i)[1])
      local left = abilities.cooldowns[i]
      local c = ability.color
      local middle, middleColor
      if left then
        UI.ring(cx, cy, radius, 1 - left / ability.cooldown, { c[1], c[2], c[3], 0.85 }, 4)
        middle, middleColor = left >= 10 and ("%d"):format(left) or ("%.1f"):format(left), { 1, 1, 1 }
      else
        love.graphics.setColor(c[1], c[2], c[3], 0.2)
        love.graphics.circle("fill", cx, cy, radius + 4, 32)
        UI.ring(cx, cy, radius, 1, c, 4)
        middle, middleColor = key, { 1, 1, 1 }
      end
      love.graphics.setFont(body)
      UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), middleColor)
      love.graphics.setFont(small)
      love.graphics.setColor(0.85, 0.85, 0.9)
      love.graphics.printf(ability.title, r.x, r.y + r.h - 20, r.w, "center")
    end
  end
end

--- The item boxes: a stack per open slot, locked ones greyed out. `lifted`
--- is the box whose item is being dragged, drawn empty meanwhile.
local function drawItems(L, buildings, list, lifted)
  heading("items", L.itemsLabel.x, L.itemsLabel.y)
  for i, r in ipairs(L.items) do
    local open = i <= buildings.slots
    box(r.x, r.y, r.w, r.h, open, false)
    local s = open and lifted ~= i and list[i]
    love.graphics.setFont(UI.fonts.small)
    if s then
      Render.itemIcon(s.item, r.x + r.w / 2, r.y + 20)
      love.graphics.setColor(0.85, 0.85, 0.9)
      love.graphics.printf(Kinds.label(s.item), r.x + 2, r.y + 38, r.w - 4, "center")
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.printf(tostring(s.n), r.x, r.y + 2, r.w - 5, "right")
    elseif not open then
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf("locked", r.x, r.y + r.h / 2 - 8, r.w, "center")
    end
  end
end

--- The whole screen. `buildings` is the buildings feature (its items and
--- slots), `list` its stacks (Screen.stacks), `drag` what is being
--- dragged ({ index, from = "slot" | "bag", box }) once it has moved, and
--- `notice` a line to show under the boxes instead of the usual hint.
function Screen.draw(buildings, list, drag, notice)
  local L = Screen.layout()
  local p = L.panel
  panel(p.x, p.y, p.w, p.h, "INVENTORY")
  drawFigure(L.figure)
  drawGear(L)
  drawWeapons(L, drag and drag.from == "slot" and drag.index or nil)
  drawAbilities(L)
  drawItems(L, buildings, list, drag and drag.from == "bag" and drag.box or nil)

  love.graphics.setFont(UI.fonts.small)
  local hint
  if notice then
    hint = notice
    love.graphics.setColor(1, 0.6, 0.5)
  elseif buildings.slots < Kinds.MAX_SLOTS then
    local shop = Controls.name(Controls.bindings("upgrades")[1])
    hint = ("%d/%d item slots used. More slots in the upgrade shop (%s)."):format(
      math.min(#list, buildings.slots), buildings.slots, shop)
    love.graphics.setColor(0.8, 0.8, 0.85)
  else
    hint = ("%d/%d item slots used."):format(math.min(#list, buildings.slots), buildings.slots)
    love.graphics.setColor(0.8, 0.8, 0.85)
  end
  love.graphics.printf(hint, p.x + Screen.pad, L.hint, p.w - 2 * Screen.pad, "left")
  local foot = "drag a gun between its slot and your bag   "
    .. Controls.name(Controls.bindings("inventory")[1]) .. ": close"
  if (buildings.inventory.medkit or 0) > 0 then
    foot = Controls.name(Controls.bindings("use-medkit")[1]) .. ": use a medkit   " .. foot
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(foot, p.x, L.foot, p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The gun being dragged, under the cursor.
function Screen.drawDrag(drag, mx, my)
  local gun = Guns.list[drag.index]
  if gun then
    Icons.draw(gun.key, mx, my, 1.2, 0.9)
  end
end

return Screen
