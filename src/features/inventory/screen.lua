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
--                 quick slots (buildings.usables): a stack each of medkits,
--                 energy drinks and grenades dragged out of the bag, the
--                 ones their keys (H, J, T) use
--                 under those, the stats strip: what your clothes do to
--                 your speed, sprint cost, ammo bundles, ability cooldowns
--                 and armor, each tile lit when it is better than base
--   bottom        the item slots buildings fills: a stack per box, locked
--                 ones greyed out until the upgrade shop opens them; under
--                 them on the right the bin: a stack dropped there is
--                 destroyed
--
-- Every box holding equipment (a gun, an ability, a vest, clothes) is
-- framed in its tier's colour (tiers/init.lua), and hovering one says
-- which tier it is and what that improves, on the hint line.
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
local AbilityIcons = require("src.features.abilities.icons")
local Tiers = require("src.features.tiers")
local Damage = require("src.features.damage")
local Figure = require("src.features.inventory.figure")
local Face = require("src.art.face")

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
local QUICK_W = 96 -- widest a quick slot (medkits, drinks) gets, as tall as an ability box; narrower to fit
local STAT_H = 40 -- a stats tile: the value over its name
local TRASH_W, TRASH_H = 150, 30 -- the bin under the item boxes

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
---   resists[i]             { x, y, w, h, dtype }, the resistances strip under it, Damage.order
---   items[i]               { x, y, w, h }, Kinds.MAX_SLOTS of them
---   trash                  { x, y, w, h }, the bin under the items, right
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
    + SECTION_GAP + LABEL_H + STAT_H
  local topH = math.max(gearH, rightH)
  local itemsH = rows * (CELL + GAP) - GAP
  local ph = 56 + topH + SECTION_GAP + LABEL_H + itemsH + 12 + TRASH_H + 34
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
  local qx = x + abilitySlots * (ABL_W + GAP) + 2 * GAP
  L.quickLabel = { x = qx, y = ay }
  L.quick = {}
  local usables = buildings and buildings.usables or {}
  local room = px + Screen.width - Screen.pad - qx + GAP
  local quickW = math.min(QUICK_W, math.floor(room / math.max(1, #usables)) - GAP)
  for i, u in ipairs(usables) do
    L.quick[i] = {
      x = qx + (i - 1) * (quickW + GAP), y = ay + LABEL_H, w = quickW, h = ABL_H, item = u.item, usable = u,
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

  -- What everything worn resists, a tile per damage type, under the stats.
  local ry = sy + LABEL_H + STAT_H + SECTION_GAP
  L.resistsLabel = { x = x, y = ry }
  L.resists = {}
  local resistW = math.floor((statsW - (#Damage.order - 1) * GAP) / #Damage.order)
  for i, dtype in ipairs(Damage.order) do
    L.resists[i] = { x = x + (i - 1) * (resistW + GAP), y = ry + LABEL_H, w = resistW, h = STAT_H, dtype = dtype }
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
  L.trash = { x = px + Screen.width - Screen.pad - TRASH_W, y = L.hint - 4, w = TRASH_W, h = TRASH_H }
  L.foot = py + ph - 26
  return L
end

-- The menu's crazy face, as the character's head: blinking and twitching,
-- ticked by the screen's own clock while it is up.
local face, faceAt = nil, nil

--- The character standing in the box, with the menu's face for a head,
--- wearing what I wear (figure.lua): my clothes and armor, and the gun in my
--- hand. A piece being dragged out of its slot (`liftedArmor`,
--- `liftedSlot`) is off them while it is.
local function drawFigure(r, client, liftedArmor, liftedSlot)
  face = face or Face.new()
  local now = love.timer.getTime()
  face:update(math.min(0.1, now - (faceAt or now)))
  faceAt = now
  love.graphics.setColor(1, 1, 1, 0.04)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  local dress = {}
  local gear, armor, weapons = Features.byName.gear, Features.byName.armor, Features.byName.weapons
  for slot, key in pairs(gear and gear:mine(client) or {}) do
    if slot ~= liftedSlot then
      dress[slot] = Tiers.base(key)
    end
  end
  local worn = armor and not liftedArmor and armor:mine(client)
  if worn then
    dress.armor = Tiers.base(worn.kind)
  end
  local gun = weapons and Guns.list[weapons.gun]
  if gun then
    dress.gun = gun.key
  end
  -- As big as the box allows: the figure's height and its shadow, about 110
  -- wide with the gun held out; centred up and down.
  local height = Figure.height(face) + 5
  local scale = math.min((r.h - 24) / height, (r.w - 8) / 110)
  Figure.draw(r.x + r.w / 2 - 8 * scale, r.y + (r.h - height * scale) / 2, scale, dress, face)
end

--- The gear slots, each named for what goes in it: the clothes worn in
--- the first four (gear) and, in the armor slot, the vest and the points
--- it has left. `liftedArmor` while the vest is being dragged out,
--- `liftedSlot` the clothes slot whose piece is.
local function drawGear(L, client, liftedArmor, liftedSlot)
  local armor, gear = Features.byName.armor, Features.byName.gear
  local worn = armor and not liftedArmor and armor:mine(client) or nil
  local kind = worn and armor.kindOf(worn.kind)
  local clothes = gear and gear:mine(client) or {}
  love.graphics.setFont(UI.fonts.small)
  for i, r in ipairs(L.gear) do
    local isArmor = i == Screen.ARMOR
    local piece = not isArmor and liftedSlot ~= r.name and gear and gear.pieceOf(clothes[r.name]) or nil
    box(r.x, r.y, r.w, r.h, (isArmor and kind ~= nil) or piece ~= nil, false)
    if isArmor and kind then
      Tiers.drawFrame(Tiers.of(worn.kind), r.x, r.y, r.w, r.h)
      Render.itemIcon("armor-" .. worn.kind, r.x + r.w / 2, r.y + 20)
      local c = kind.color
      UI.meter(r.x + 6, r.y + r.h - 12, r.w - 12, 6, worn.points / worn.max, c)
      love.graphics.setColor(1, 0.85, 0.3)
      love.graphics.printf(tostring(worn.points), r.x, r.y + 2, r.w - 4, "right")
    elseif piece then
      Tiers.drawFrame(Tiers.of(clothes[r.name]), r.x, r.y, r.w, r.h)
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
    local gun = i and Guns.list[i] and weapons:gunAt(i) -- in the tier I carry it
    local held = gun and weapons.gun == i
    box(r.x, r.y, r.w, r.h, gun ~= nil, held)
    if gun then
      Tiers.drawFrame(weapons:tierOf(i), r.x, r.y, r.w, r.h, held and 1 or 0.7)
    end
    love.graphics.setFont(small)
    -- The key in a badge in the corner either way, if the slot has one (none by default: Z and X cycle).
    local bound = Controls.bindings("weapon-" .. slot)[1]
    if bound then
      love.graphics.setColor(0.36, 0.56, 0.92, (held and 1) or (gun and 0.6) or 0.3)
      love.graphics.rectangle("fill", r.x + 4, r.y + 4, 20, 18, 4)
      love.graphics.setColor(1, 1, 1, gun and 1 or 0.5)
      love.graphics.printf(Controls.name(bound), r.x + 4, r.y + 5, 20, "center")
    end
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
    if ability then
      Tiers.drawFrame(ability.tier, r.x, r.y, r.w, r.h)
    end
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
        AbilityIcons.draw(ability.key, cx, cy, radius - 6)
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
      local middle
      if left then
        UI.ring(cx, cy, radius, 1 - left / ability.cooldown, { c[1], c[2], c[3], 0.85 }, 4)
        middle = left >= 10 and ("%d"):format(left) or ("%.1f"):format(left)
      else
        love.graphics.setColor(c[1], c[2], c[3], 0.2)
        love.graphics.circle("fill", cx, cy, radius + 4, 32)
        UI.ring(cx, cy, radius, 1, c, 4)
      end
      AbilityIcons.draw(ability.key, cx, cy, radius - 6, middle and 0.3 or 1)
      if middle then
        love.graphics.setFont(body)
        UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), { 1, 1, 1 })
      end
      AbilityIcons.keyBadge(key, cx, cy, radius, middle and 0.5 or 1, small)
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

--- The resistances strip: for each damage type, how much of it what I
--- wear stops altogether (armor and clothes), lit in the type's colour
--- when it is anything.
local function drawResists(L, client)
  heading("resist", L.resistsLabel.x, L.resistsLabel.y)
  local damage = Features.byName.damage
  love.graphics.setFont(UI.fonts.small)
  for _, r in ipairs(L.resists) do
    local pct = damage and math.floor((1 - damage:share(client, client.myId, r.dtype)) * 100 + 0.5) or 0
    box(r.x, r.y, r.w, r.h, pct > 0, false)
    local c = Damage.of(r.dtype).color
    if pct > 0 then
      love.graphics.setColor(c[1], c[2], c[3])
    else
      love.graphics.setColor(1, 1, 1, 0.45)
    end
    love.graphics.printf(pct > 0 and ("%d%%"):format(pct) or "-", r.x, r.y + 4, r.w, "center")
    love.graphics.setColor(0.85, 0.85, 0.9, pct > 0 and 1 or 0.5)
    love.graphics.printf(r.dtype, r.x, r.y + r.h - 18, r.w, "center")
  end
end

--- The item boxes: a stack per open slot, locked ones greyed out. `lifted`
--- is the box whose item is being dragged, drawn empty meanwhile.
--- One item box `r`: the stack `s` in it ({ item, n }), nothing, or
--- locked when the slot isn't `open` yet. A box smaller than the
--- inventory's (the bag beside the shop) leaves out a name that won't fit
--- on one line, and centres the picture.
local function drawItemBox(r, s, open)
  box(r.x, r.y, r.w, r.h, open, false)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  if s then
    local tiered = Tiers.tiered(s.item)
    if tiered then
      Tiers.drawFrame(Tiers.of(s.item), r.x, r.y, r.w, r.h)
    end
    local name = Kinds.shortName(Tiers.base(s.item), s.n)
    local named = r.h >= CELL or font:getWidth(name) <= r.w - 4
    Render.itemIcon(s.item, r.x + r.w / 2, named and r.y + 20 or r.y + r.h / 2 + 2)
    -- Equipment is named in its tier's colour; the frame and the hint say which.
    love.graphics.setColor(tiered and Tiers.color(Tiers.of(s.item)) or { 0.85, 0.85, 0.9 })
    if named then
      love.graphics.printf(name, r.x + 2, r.y + math.min(38, r.h - font:getHeight() - 2), r.w - 4, "center")
    end
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.printf(tostring(s.n), r.x, r.y + 2, r.w - 5, "right")
  elseif not open then
    love.graphics.setColor(1, 1, 1, 0.2)
    love.graphics.printf("locked", r.x, r.y + r.h / 2 - 8, r.w, "center")
  end
end

local function drawItems(L, buildings, list, lifted)
  heading("items", L.itemsLabel.x, L.itemsLabel.y)
  for i, r in ipairs(L.items) do
    local open = i <= buildings.slots
    drawItemBox(r, open and lifted ~= i and list[i], open)
  end
end

--- The bin: dim until something from the bag is dragged, red while it is
--- over it.
local function drawTrash(r, drag)
  local armed = drag ~= nil and drag.from == "bag"
  local mx, my = love.mouse.getPosition()
  local over = armed and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
  if over then
    love.graphics.setColor(0.9, 0.25, 0.2, 0.45)
  else
    love.graphics.setColor(0.9, 0.25, 0.2, armed and 0.18 or 0.06)
  end
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  love.graphics.setColor(1, 0.45, 0.4, over and 1 or armed and 0.7 or 0.3)
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
  -- A bin: lid, handle, can with its ribs.
  local bx, by = r.x + 12, r.y + 6
  love.graphics.rectangle("fill", bx - 1, by + 2, 16, 3, 1)
  love.graphics.rectangle("fill", bx + 5, by, 4, 2)
  love.graphics.rectangle("line", bx + 1, by + 6, 12, 12, 1)
  love.graphics.line(bx + 5, by + 8, bx + 5, by + 16)
  love.graphics.line(bx + 9, by + 8, bx + 9, by + 16)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf(over and "drop to destroy" or "destroy", r.x + 24, r.y + math.floor((r.h - 14) / 2) - 1,
    r.w - 30, "center")
end

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end

--- The piece of equipment under (mx, my) as an item ("gun-uzi@rare"): in a
--- weapon, ability or gear slot or a bag box. Nil over anything else.
local function hovered(L, list, buildings, client, mx, my)
  local weapons, abilities = Features.byName.weapons, Features.byName.abilities
  local armor, gear = Features.byName.armor, Features.byName.gear
  for slot, r in ipairs(L.weapons) do
    local i = weapons and weapons.slots[slot]
    if inside(r, mx, my) and i and Guns.list[i] then
      return Tiers.join("gun-" .. Guns.list[i].key, weapons:tierOf(i))
    end
  end
  for slot, r in ipairs(L.abilities) do
    local key = abilities and abilities.slots[slot]
    if inside(r, mx, my) and key then
      return "ability-" .. key
    end
  end
  for i, r in ipairs(L.gear) do
    if inside(r, mx, my) then
      local worn = i == Screen.ARMOR and armor and armor:mine(client)
      local piece = i ~= Screen.ARMOR and gear and gear:mine(client)[r.name]
      return (worn and "armor-" .. worn.kind) or (piece and "gear-" .. piece) or nil
    end
  end
  for i, r in ipairs(L.items) do
    local s = i <= buildings.slots and list[i]
    if inside(r, mx, my) and s and Tiers.tiered(s.item) then
      return s.item
    end
  end
  return nil
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
  drawFigure(L.figure, client, drag ~= nil and drag.kind == "armor" and drag.from == "slot",
    drag and drag.kind == "gear" and drag.from == "slot" and drag.slot or nil)
  drawGear(L, client, drag ~= nil and drag.kind == "armor" and drag.from == "slot",
    drag and drag.kind == "gear" and drag.from == "slot" and drag.slot or nil)
  drawWeapons(L, drag and drag.kind == "gun" and drag.from == "slot" and drag.box or nil)
  drawAbilities(L, drag and drag.kind == "ability" and drag.from == "slot" and drag.box or nil)
  drawQuick(L, buildings, drag and drag.kind == "quick" and drag.from == "quick" and drag.item or nil)
  drawStats(L, client)
  drawResists(L, client)
  drawItems(L, buildings, list, drag and drag.from == "bag" and drag.box or nil)

  love.graphics.setFont(UI.fonts.small)
  local hint
  local over = not drag and hovered(L, list, buildings, client, love.mouse.getPosition())
  if notice then
    hint = notice
    love.graphics.setColor(1, 0.6, 0.5)
  elseif over then
    -- What is under the mouse: its tier, in its colour, and what that does.
    local tier = Tiers.of(over)
    hint = ("%s (%s): %s"):format(Kinds.name(Tiers.base(over), 1), tier, Kinds.tierLine(over) or "")
    love.graphics.setColor(Tiers.color(tier))
  elseif buildings.slots < Kinds.MAX_SLOTS then
    hint = ("%d/%d item slots used. More slots at the gym."):format(math.min(#list, buildings.slots), buildings.slots)
    love.graphics.setColor(0.8, 0.8, 0.85)
  else
    hint = ("%d/%d item slots used."):format(math.min(#list, buildings.slots), buildings.slots)
    love.graphics.setColor(0.8, 0.8, 0.85)
  end
  love.graphics.printf(hint, p.x + Screen.pad, L.hint, L.trash.x - p.x - 2 * Screen.pad, "left")
  drawTrash(L.trash, drag)
  local foot = "drag things between their slots, your gear and your bag, or into the bin   "
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
  if drag.kind == "item" then
    Render.itemIcon(drag.item, mx, my)
    return
  elseif drag.kind == "ability" then
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

-- The bag beside the shop -----------------------------------------------------

Screen.BAG_W = 196 -- px the bag panel takes beside the shop: two item boxes across
local MINI = 38 -- px a weapon or ability box in the bag panel's "carrying" rows
local CARRY_H = 2 * (16 + MINI) + 18 -- px those two rows take, with their headings and a gap under them

--- The guns and abilities I carry, small, in two rows from (x, y) across a
--- panel `w` wide: each in its tier's frame, the gun in hand lit. Only to
--- look at, beside the shop.
local function drawCarried(x, y, w)
  local weapons, abilities = Features.byName.weapons, Features.byName.abilities
  local function row(label, ry, n, drawOne)
    heading(label, x + 12, ry)
    local gap = math.max(2, math.floor((w - 24 - n * MINI) / math.max(1, n - 1)))
    for i = 1, n do
      drawOne(i, x + 12 + (i - 1) * (MINI + gap), ry + 16)
    end
  end
  if weapons then
    row("weapons", y, weapons.slotCount, function(slot, bx, by)
      local i = weapons.slots[slot]
      local gun = i and Guns.list[i] and weapons:gunAt(i)
      local held = gun and weapons.gun == i
      box(bx, by, MINI, MINI, gun ~= nil, held)
      if gun then
        Tiers.drawFrame(weapons:tierOf(i), bx, by, MINI, MINI, held and 1 or 0.7)
        Icons.draw(gun.key, bx + MINI / 2 + 3, by + MINI / 2, 0.55, held and 1 or 0.75)
      end
    end)
  end
  if abilities then
    row("abilities", y + 16 + MINI + 10, abilities.slotCount, function(slot, bx, by)
      local ability = abilities:inSlot(slot)
      box(bx, by, MINI, MINI, ability ~= nil, false)
      if ability then
        Tiers.drawFrame(ability.tier, bx, by, MINI, MINI)
        UI.ring(bx + MINI / 2, by + MINI / 2, MINI / 2 - 4, 1, ability.color, 2)
        AbilityIcons.draw(ability.key, bx + MINI / 2, by + MINI / 2, MINI / 2 - 8)
      end
    end)
  end
end

--- The bag's boxes in a panel at (x, y), `h` tall: every item slot, two
--- across, as big as the inventory's or smaller if the shop is short. Each
--- is { x, y, w, h, open, stack } (`stack` { item, n }, nil when empty);
--- also the y under them, where the guns and abilities go.
function Screen.bagBoxes(buildings, x, y, h)
  local w = Screen.BAG_W
  local list = Screen.stacks(buildings.inventory)
  local cols, total = 2, Kinds.MAX_SLOTS
  local rows = math.ceil(total / cols)
  local quickH = 20 * #(buildings.usables or {}) + 8
  local top, bottom = y + 64, y + h - 12 - quickH - CARRY_H
  local cell = math.min(CELL, math.floor((bottom - top + GAP) / rows) - GAP, math.floor((w - 24 - GAP) / cols))
  local gx = x + math.floor((w - (cols * (cell + GAP) - GAP)) / 2)
  local boxes = {}
  for i = 1, total do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    local open = i <= buildings.slots
    boxes[i] = { x = gx + col * (cell + GAP), y = top + row * (cell + GAP), w = cell, h = cell, open = open,
      stack = open and list[i] or nil }
  end
  return boxes, top + rows * (cell + GAP) + 2, #list
end

--- What I carry, in a narrow panel at (x, y), `h` tall, beside the shop
--- (shop/screen.lua asks for it): every item slot as the inventory draws
--- it, locked ones too, and under them how many medkits, drinks and
--- grenades are in the quick slots, and between the two the guns and
--- abilities I carry (drawCarried). The shop takes a click on a box as
--- picking that item to sell; `selected` is the item picked, its boxes lit.
--- Moving things about is still the inventory's (I).
function Screen.drawBag(buildings, x, y, h, selected)
  local w = Screen.BAG_W
  panel(x, y, w, h, "YOUR BAG")
  local boxes, qy, used = Screen.bagBoxes(buildings, x, y, h)
  local mx, my = love.mouse.getPosition()
  -- Under the title: what the box under the mouse holds (a small box has no
  -- room for its name), else how full the bag is.
  local line = ("%d of %d slots used"):format(math.min(used, buildings.slots), buildings.slots)
  for _, r in ipairs(boxes) do
    if r.stack and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h then
      line = Kinds.label(Tiers.base(r.stack.item), r.stack.n)
    end
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.75, 0.9)
  love.graphics.printf(line, x, y + 40, w, "center")
  drawCarried(x, qy, w) -- under the items
  for _, r in ipairs(boxes) do
    drawItemBox(r, r.stack, r.open)
    local over = r.stack and mx >= r.x and mx < r.x + r.w and my >= r.y and my < r.y + r.h
    if r.stack and (r.stack.item == selected or over) then
      love.graphics.setColor(0.45, 0.95, 0.6, r.stack.item == selected and 0.9 or 0.45)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
      love.graphics.setLineWidth(1)
    end
  end
  -- The quick slots, a line each, at the bottom.
  qy = qy + CARRY_H
  for _, u in ipairs(buildings.usables or {}) do
    local n = buildings:quickCount(u.item)
    local c = u.color
    love.graphics.setColor(c[1], c[2], c[3], n > 0 and 1 or 0.4)
    love.graphics.rectangle("fill", x + 16, qy + 4, 10, 10, 2)
    love.graphics.setColor(0.85, 0.85, 0.9, n > 0 and 1 or 0.5)
    love.graphics.print(u.title, x + 32, qy)
    love.graphics.setColor(1, 0.85, 0.3, n > 0 and 1 or 0.4)
    love.graphics.printf(("%d/%d"):format(n, u.max), x, qy, w - 16, "right")
    qy = qy + 20
  end
  love.graphics.setColor(1, 1, 1)
end

return Screen
