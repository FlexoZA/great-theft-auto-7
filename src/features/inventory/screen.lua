-- The inventory screen's picture: the character in the middle of the
-- screen with everything they carry around them.
--
--   top left      the character and the gear slots down their side: head,
--                 body, pants and shoes with the clothes they wear (gear),
--                 and the armor slot with the vest and its points left
--   top right     the weapon slots, one per number key (weapons.slotCount),
--                 each with the gun in it, what is in the magazine and what
--                 is left to load, the one in hand lit up, empty ones bare;
--                 under them the ability slots, one per ability key, as the
--                 HUD shows them, empty ones bare, and beside those the
--                 quick slots (buildings.usables): a stack of medkits and
--                 one of energy drinks dragged out of the bag, the ones
--                 their keys (H, J) use
--                 under those, the stats strip: what your clothes do to
--                 your speed, sprint cost, ammo bundles, ability cooldowns
--                 and armor, each tile lit when it is better than base
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
Screen.gear = { "head", "body", "pants", "shoes", "armor" } -- the slots down the character's side
Screen.ARMOR = 5 -- the gear slot armor goes in

local CELL, GAP = 76, 8 -- item boxes
local GEAR = 54 -- gear boxes
local GUN_W, GUN_H = 120, 96 -- weapon boxes: the icon over the name over the ammo
local ABL_W, ABL_H = 64, 72 -- ability boxes
local QUICK_W = 96 -- a quick slot (medkits, drinks), as tall as an ability box
local STAT_H = 40 -- a stats tile: the value over its name

-- The stats the clothes (gear) can change, as the strip shows them: the
-- name the `stat` convention answers to, the label, and whether more of
-- it is better (a lower sprint cost or cooldown is an improvement).
Screen.stats = {
  { key = "speed", label = "speed", moreIsBetter = true },
  { key = "stamina", label = "sprint", moreIsBetter = false },
  { key = "ammo", label = "ammo", moreIsBetter = true },
  { key = "cooldown", label = "cooldowns", moreIsBetter = false },
  { key = "armor", label = "armor", moreIsBetter = true },
}
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
---   weapons[i]             { x, y, w, h }, weapons.slotCount of them
---   abilities[i]           { x, y, w, h }, as many as the HUD shows
---   quick[i]               { x, y, w, h, item, usable }, the quick slots beside them, buildings.usables order
---   stats[i]               { x, y, w, h, stat }, the stats strip under the abilities, Screen.stats order
---   items[i]               { x, y, w, h }, Kinds.MAX_SLOTS of them
---   weaponsArea / abilitiesArea / itemsArea  the block each row of boxes stands in, for drops
---   hint / foot            y of the text lines under the items
function Screen.layout()
  local abilities, weapons = Features.byName.abilities, Features.byName.weapons
  local abilitySlots = abilities and abilities.slotCount or 0
  local weaponSlots = weapons and weapons.slotCount or 4
  local cols = math.floor((Screen.width - 2 * Screen.pad + GAP) / (CELL + GAP))
  local rows = math.ceil(Kinds.MAX_SLOTS / cols)
  local gearH = #Screen.gear * (GEAR + GAP) - GAP
  local rightH = LABEL_H + GUN_H + SECTION_GAP + LABEL_H + ABL_H + SECTION_GAP + LABEL_H + STAT_H
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
  for i = 1, weaponSlots do
    L.weapons[i] = { x = x + (i - 1) * (GUN_W + GAP), y = top + LABEL_H, w = GUN_W, h = GUN_H }
  end
  L.weaponsArea = {
    x = x - GAP, y = top, w = weaponSlots * (GUN_W + GAP) + GAP, h = LABEL_H + GUN_H + GAP,
  }
  local ay = top + LABEL_H + GUN_H + SECTION_GAP
  L.abilitiesLabel = { x = x, y = ay }
  for i = 1, abilitySlots do
    L.abilities[i] = { x = x + (i - 1) * (ABL_W + GAP), y = ay + LABEL_H, w = ABL_W, h = ABL_H }
  end
  L.abilitiesArea = { x = x - GAP, y = ay, w = abilitySlots * (ABL_W + GAP) + GAP, h = LABEL_H + ABL_H + GAP }
  -- The quick slots to the right of the abilities: what the use keys use.
  local buildings = Features.byName.buildings
  local qx = x + abilitySlots * (ABL_W + GAP) + Screen.pad
  L.quickLabel = { x = qx, y = ay }
  L.quick = {}
  for i, u in ipairs(buildings and buildings.usables or {}) do
    L.quick[i] = {
      x = qx + (i - 1) * (QUICK_W + GAP), y = ay + LABEL_H, w = QUICK_W, h = ABL_H, item = u.item, usable = u,
    }
  end

  -- The stats strip under the abilities and quick slots, a tile per stat.
  local sy = ay + LABEL_H + ABL_H + SECTION_GAP
  L.statsLabel = { x = x, y = sy }
  L.stats = {}
  local statsW = px + Screen.width - Screen.pad - x
  local tileW = math.floor((statsW - (#Screen.stats - 1) * GAP) / #Screen.stats)
  for i, stat in ipairs(Screen.stats) do
    L.stats[i] = { x = x + (i - 1) * (tileW + GAP), y = sy + LABEL_H, w = tileW, h = STAT_H, stat = stat }
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

--- The gear slots, each named for what goes in it: the clothes worn in
--- the first four (gear) and, in the armor slot, the vest and the points
--- it has left. `liftedArmor` while the vest is being dragged out,
--- `liftedSlot` the clothes slot whose piece is.
local function drawGear(L, client, liftedArmor, liftedSlot)
  local armor, gear = Features.byName.armor, Features.byName.gear
  local worn = armor and not liftedArmor and armor:mine(client) or nil
  local kind = worn and armor.kinds.byKey[worn.kind]
  local clothes = gear and gear:mine(client) or {}
  love.graphics.setFont(UI.fonts.small)
  for i, r in ipairs(L.gear) do
    local isArmor = i == Screen.ARMOR
    local piece = not isArmor and liftedSlot ~= r.name and gear and gear.kinds.byKey[clothes[r.name] or ""] or nil
    box(r.x, r.y, r.w, r.h, (isArmor and kind ~= nil) or piece ~= nil, false)
    if isArmor and kind then
      Render.itemIcon("armor-" .. worn.kind, r.x + r.w / 2, r.y + 20)
      local c = kind.color
      UI.meter(r.x + 6, r.y + r.h - 12, r.w - 12, 6, worn.points / worn.max, c)
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.printf(tostring(worn.points), r.x, r.y + 2, r.w - 4, "right")
    elseif piece then
      Render.itemIcon("gear-" .. piece.key, r.x + r.w / 2, r.y + 20)
      love.graphics.setColor(0.85, 0.85, 0.9)
      love.graphics.printf(r.name, r.x, r.y + r.h - 16, r.w, "center")
    else
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.printf(r.name, r.x, r.y + r.h / 2 - 8, r.w, "center")
    end
  end
end

--- The weapon slots, one per number key, with the gun in each; the one in
--- hand lit. `lifted` is the slot whose gun is being dragged, drawn empty
--- meanwhile.
local function drawWeapons(L, lifted)
  local weapons = Features.byName.weapons
  local small = UI.fonts.small
  heading("weapons", L.weaponsLabel.x, L.weaponsLabel.y)
  for slot, r in ipairs(L.weapons) do
    local i = weapons and lifted ~= slot and weapons.slots[slot]
    local gun = i and Guns.list[i]
    local held = gun and weapons.gun == i
    box(r.x, r.y, r.w, r.h, gun ~= nil, held)
    love.graphics.setFont(small)
    -- The key in a badge in the corner either way.
    local key = Controls.name(Controls.bindings("weapon-" .. slot)[1])
    love.graphics.setColor(0.36, 0.56, 0.92, (held and 1) or (gun and 0.6) or 0.3)
    love.graphics.rectangle("fill", r.x + 4, r.y + 4, 20, 18, 4)
    love.graphics.setColor(1, 1, 1, gun and 1 or 0.5)
    love.graphics.printf(key, r.x + 4, r.y + 5, 20, "center")
    if not gun then
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf("empty", r.x, r.y + r.h / 2 - 8, r.w, "center")
    else
      -- The gun drawn across the top, its name under it and the ammo along
      -- the bottom, red when the magazine is empty. Guns not in hand are
      -- drawn a little faded.
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

--- The ability slots, one per key, drawn the way the HUD draws them: a
--- ring that empties on a cast and fills back through the cooldown.
--- `lifted` is the slot whose ability is being dragged, drawn empty.
local function drawAbilities(L, lifted)
  local abilities = Features.byName.abilities
  if not abilities then
    return
  end
  local small, body = UI.fonts.small, UI.fonts.body
  heading("abilities", L.abilitiesLabel.x, L.abilitiesLabel.y)
  for i, r in ipairs(L.abilities) do
    local ability = lifted ~= i and abilities:inSlot(i) or nil
    box(r.x, r.y, r.w, r.h, ability ~= nil, false)
    local cx, cy, radius = r.x + r.w / 2, r.y + 26, 20
    local passive = i == abilities.passiveSlot
    local key = not passive and Controls.name(Controls.bindings("ability-" .. i)[1]) or nil
    if passive then
      -- No key: it works by being there. Its name under the ring, or what
      -- the slot is for while it is empty.
      if ability then
        local c = ability.color
        love.graphics.setColor(c[1], c[2], c[3], 0.2)
        love.graphics.circle("fill", cx, cy, radius + 4, 32)
        UI.ring(cx, cy, radius, 1, c, 4)
      else
        UI.ring(cx, cy, radius, 0, { 1, 1, 1 }, 3)
      end
      love.graphics.setFont(small)
      love.graphics.setColor(1, 1, 1, ability and 0.85 or 0.25)
      love.graphics.printf(ability and (ability.hud or ability.title) or "passive", r.x, r.y + r.h - 20, r.w, "center")
    elseif not ability then
      UI.ring(cx, cy, radius, 0, { 1, 1, 1 }, 3)
      love.graphics.setFont(body)
      love.graphics.setColor(1, 1, 1, 0.3)
      love.graphics.printf(key, r.x, cy - math.floor(body:getHeight() / 2), r.w, "center")
      love.graphics.setFont(small)
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf("empty", r.x, r.y + r.h - 20, r.w, "center")
    else
      local left = abilities.cooldowns[ability.key]
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
      love.graphics.printf(ability.hud or ability.title, r.x, r.y + r.h - 20, r.w, "center")
    end
  end
end

--- The quick slots: each with its key in a badge, what is in it and how
--- many of the most it holds. `lifted` is the item whose stack is being
--- dragged out, drawn empty meanwhile.
local function drawQuick(L, buildings, lifted)
  heading("quick use", L.quickLabel.x, L.quickLabel.y)
  for _, r in ipairs(L.quick) do
    local u = r.usable
    local n = lifted ~= r.item and buildings:quickCount(r.item) or 0
    box(r.x, r.y, r.w, r.h, n > 0, false)
    love.graphics.setFont(UI.fonts.small)
    local key = Controls.name(Controls.bindings(u.action)[1])
    local c = u.color
    love.graphics.setColor(c[1], c[2], c[3], n > 0 and 1 or 0.35)
    love.graphics.rectangle("fill", r.x + 4, r.y + 4, 20, 18, 4)
    love.graphics.setColor(1, 1, 1, n > 0 and 1 or 0.5)
    love.graphics.printf(key, r.x + 4, r.y + 5, 20, "center")
    if n > 0 then
      Render.itemIcon(r.item, r.x + r.w / 2 + 8, r.y + 30)
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.printf(("%d/%d"):format(n, u.max), r.x, r.y + 4, r.w - 6, "right")
      love.graphics.setColor(0.85, 0.85, 0.9)
      love.graphics.printf(u.title, r.x, r.y + r.h - 20, r.w, "center")
    else
      love.graphics.setColor(1, 1, 1, 0.2)
      love.graphics.printf(u.title, r.x, r.y + r.h / 2 - 8, r.w, "center")
    end
  end
end

--- The stats strip: for each stat, what my clothes make of it against
--- base, as a percentage; green and lit when it is an improvement, red
--- when it is worse, plain "base" otherwise.
local function drawStats(L, client)
  heading("stats", L.statsLabel.x, L.statsLabel.y)
  local small = UI.fonts.small
  for _, r in ipairs(L.stats) do
    local stat = r.stat
    local scale = Features.reduce("stat", 1, client, client.myId, stat.key)
    local pct = math.floor((scale - 1) * 100 + 0.5)
    local better = (pct > 0) == stat.moreIsBetter and pct ~= 0
    local worse = pct ~= 0 and not better
    box(r.x, r.y, r.w, r.h, pct ~= 0, better)
    love.graphics.setFont(small)
    local value = pct == 0 and "base" or ("%+d%%"):format(pct)
    if better then
      love.graphics.setColor(0.5, 1, 0.55)
    elseif worse then
      love.graphics.setColor(1, 0.45, 0.4)
    else
      love.graphics.setColor(1, 1, 1, 0.45)
    end
    love.graphics.printf(value, r.x, r.y + 4, r.w, "center")
    love.graphics.setColor(0.85, 0.85, 0.9, pct ~= 0 and 1 or 0.5)
    love.graphics.printf(stat.label, r.x, r.y + r.h - 18, r.w, "center")
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
      love.graphics.printf(Kinds.name(s.item, s.n), r.x + 2, r.y + 38, r.w - 4, "center")
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
--- dragged ({ index, from = "slot" | "bag", box }: `box` the slot or item
--- box it left) once it has moved, `notice` a line to show under the boxes
--- instead of the usual hint, and `client` for what I wear.
function Screen.draw(buildings, list, drag, notice, client)
  local L = Screen.layout()
  local p = L.panel
  panel(p.x, p.y, p.w, p.h, "INVENTORY")
  drawFigure(L.figure)
  drawGear(L, client, drag ~= nil and drag.kind == "armor" and drag.from == "slot",
    drag and drag.kind == "gear" and drag.from == "slot" and drag.slot or nil)
  drawWeapons(L, drag and drag.kind == "gun" and drag.from == "slot" and drag.box or nil)
  drawAbilities(L, drag and drag.kind == "ability" and drag.from == "slot" and drag.box or nil)
  drawQuick(L, buildings, drag and drag.kind == "quick" and drag.from == "quick" and drag.item or nil)
  drawStats(L, client)
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
  local foot = "drag things between their slots, your gear and your bag   "
    .. Controls.name(Controls.bindings("inventory")[1]) .. ": close"
  for _, u in ipairs(buildings.usables) do
    if buildings:quickCount(u.item) > 0 then
      foot = Controls.name(Controls.bindings(u.action)[1]) .. ": " .. Kinds.name(u.item, 1) .. "   " .. foot
    end
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(foot, p.x, L.foot, p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The gun, ability or quick-slot stack being dragged, under the cursor.
function Screen.drawDrag(drag, mx, my)
  if drag.kind == "ability" then
    Render.abilityIcon(drag.key, mx, my, 18)
    return
  elseif drag.kind == "quick" then
    Render.itemIcon(drag.item, mx, my)
    return
  elseif drag.kind == "armor" then
    Render.itemIcon("armor-" .. drag.key, mx, my)
    return
  elseif drag.kind == "gear" then
    Render.itemIcon("gear-" .. drag.key, mx, my)
    return
  end
  local gun = Guns.list[drag.index]
  if gun then
    Icons.draw(gun.key, mx, my, 1.2, 0.9)
  end
end

return Screen
