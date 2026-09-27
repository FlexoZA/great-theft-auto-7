-- The product screen: what "Choose what to make..." opens on a building
-- with more than two products. It looks like the build screen
-- (build-screen.lua, whose pieces it borrows) and the shop: a card per
-- product with its picture, its name and what it starts selling for, the one
-- in hand marked MAKING. Click a card to see it in the side panel: a bigger
-- picture (a car shows its stats), what one batch takes as icons, its
-- numbers and the Make button. Back returns to the building's menu.
--
-- `Screen.layout(kind, picked)` works out every rectangle for the window as
-- it is now and `Screen.draw` paints them; init.lua hit-tests the same
-- rectangles.

local Features = require("src.features")
local UI = require("src.ui")
local Controls = require("src.controls")
local Kinds = require("src.features.buildings.kinds")
local Catalog = require("src.features.vehicles.catalog")
local Build = require("src.features.buildings.build-screen")

local Screen = {}

-- Tuning ------------------------------------------------------------------
local CARD_W, CARD_H = 124, 136 -- a card: picture, name (up to two lines), price
local GAP = 8 -- px between cards
local TITLE_H = 56 -- the title strip
local FOOT_H = 60 -- the key hint
local MARGIN = 8 -- px the panel keeps from the window's edges
local MIN_H = 580 -- px; the side panel needs the room even when the cards don't
local BUY_H = 38 -- the Make button
local ICON = 40 -- px between input icons in the side panel
local GREEN = { 0.45, 0.95, 0.6 }

local inside = Build.inside

--- "Uzi ammo" for "ammo-uzi".
local function title(item)
  return (Kinds.name(item, 1):gsub("^%l", string.upper))
end

--- What one of `item` (or a customer's lot of them) starts selling for.
local function priceText(r)
  if not r.price then
    return ""
  elseif r.unit and r.unit > 1 then
    return ("%s per %d"):format(Build.amount(r.price), r.unit)
  end
  return Build.amount(r.price) .. " each"
end

--- Every rectangle on the screen for building `kind`:
---   panel     { x, y, w, h }
---   back      { x, y, w, h }, the Back button in the title strip
---   cards[i]  { x, y, w, h, item, index }, one per product
---   detail    { x, y, w, h }, the side panel
---   make      { x, y, w, h }, its Make button, when a product is picked
---   foot      y of the key hint
function Screen.layout(kind, picked)
  local w, h = love.graphics.getDimensions()
  local areaW = math.max(2 * Build.pad + CARD_W, math.min(Build.width, w - 2 * MARGIN - Build.detailWidth))
  local products = kind.products
  local cols = math.max(1, math.floor((areaW - 2 * Build.pad + GAP) / (CARD_W + GAP)))
  local rows = math.ceil(#products / cols)
  local gridH = rows * (CARD_H + GAP) - GAP
  local ph = math.max(TITLE_H + gridH + FOOT_H + Build.pad, math.min(MIN_H, h - 2 * MARGIN))
  local pw = areaW + Build.detailWidth
  local px = math.floor((w - pw) / 2)
  local py = math.max(MARGIN, math.floor((h - ph) / 2))
  local L = { panel = { x = px, y = py, w = pw, h = ph }, cards = {} }
  L.back = { x = px + Build.pad, y = py + 16, w = 84, h = 26 }

  local gridCols = math.min(cols, #products)
  local gx = px + math.floor((areaW - (gridCols * (CARD_W + GAP) - GAP)) / 2)
  local gy = py + TITLE_H
  for i, item in ipairs(products) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    L.cards[i] = {
      x = gx + col * (CARD_W + GAP), y = gy + row * (CARD_H + GAP), w = CARD_W, h = CARD_H, item = item, index = i,
    }
  end

  L.detail = { x = px + areaW, y = gy, w = Build.detailWidth - Build.pad, h = py + ph - 44 - gy }
  if picked then
    local d = L.detail
    L.make = { x = d.x + 12, y = d.y + d.h - BUY_H - 12, w = d.w - 24, h = BUY_H }
  end
  L.foot = py + ph - 26
  return L
end

--- A product's picture on a card, centred on (cx, cy): a car lies across it.
local function cardIcon(item, cx, cy, w)
  local model = Catalog.fromItem(item)
  if model then
    Catalog.draw(model, cx, cy, 0, w - 28)
  else
    Build.productIcon(item, cx, cy, 1.3)
  end
end

--- The MAKING tag in the corner of the card for what the building makes now.
local function makingTag(r)
  love.graphics.setFont(UI.fonts.small)
  local text = "MAKING"
  local w = UI.fonts.small:getWidth(text) + 12
  love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.85)
  love.graphics.rectangle("fill", r.x + 6, r.y + 6, w, 16, 4)
  love.graphics.setColor(0.05, 0.12, 0.08)
  love.graphics.printf(text, r.x + 6, r.y + 6, w, "center")
end

--- `text` wrapped to `w` in the current font, cut to `most` lines ("...").
local function clip(text, w, most)
  local font = love.graphics.getFont()
  local _, lines = font:getWrap(text, w)
  if #lines <= most then
    return text
  end
  local kept = {}
  for i = 1, most do
    kept[i] = lines[i]
  end
  local last = kept[most]
  while #last > 1 and font:getWidth(last .. "...") > w do
    last = last:sub(1, -2)
  end
  kept[most] = last .. "..."
  return table.concat(kept, "\n")
end

local function drawCard(r, kind, current, lit)
  Build.frame(r, lit)
  if current then
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.8)
    love.graphics.setLineWidth(2)
    love.graphics.rectangle("line", r.x + 2, r.y + 2, r.w - 4, r.h - 4, 5)
    love.graphics.setLineWidth(1)
    makingTag(r)
  end
  cardIcon(r.item, r.x + r.w / 2, r.y + 46, r.w)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.9, 0.9, 0.95)
  love.graphics.printf(clip(title(r.item), r.w - 8, 2), r.x + 4, r.y + 78, r.w - 8, "center")
  love.graphics.setColor(Build.GOLD)
  love.graphics.printf(priceText(Kinds.recipe(kind, r.index)), r.x, r.y + r.h - 20, r.w, "center")
end

--- What one batch of `r` takes, as a row of icons with a count under each.
local function drawInputs(r, x, y, w)
  local inputs = Kinds.inputList(r)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.7, 0.7, 0.76)
  love.graphics.print("One batch takes", x, y)
  y = y + 20
  if #inputs == 0 then
    love.graphics.setColor(0.95, 0.95, 1)
    love.graphics.print("Nothing: it comes out of the ground", x, y)
    return y + 22
  end
  local per = math.max(1, math.floor(w / ICON))
  for i, input in ipairs(inputs) do
    local col, row = (i - 1) % per, math.floor((i - 1) / per)
    local cx, cy = x + col * ICON + ICON / 2, y + row * (ICON + 18) + ICON / 2
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle("fill", cx - ICON / 2 + 2, cy - ICON / 2 + 2, ICON - 4, ICON - 4, 4)
    Build.productIcon(input.item, cx, cy, 0.8)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.95, 0.95, 1)
    love.graphics.printf("x" .. input.n, cx - ICON / 2, cy + ICON / 2, ICON, "center")
  end
  love.graphics.setColor(0.6, 0.62, 0.7)
  local names = {}
  for _, input in ipairs(inputs) do
    names[#names + 1] = input.item
  end
  y = y + math.ceil(#inputs / per) * (ICON + 18)
  return Build.para(table.concat(names, ", "), x, y, w) + 6
end

--- The side panel: product `picked` of building `b` (a bigger picture, its
--- name, what a batch takes, its numbers and the Make button), or how to fill it.
local function drawDetail(L, kind, b, picked, mx, my)
  local d = L.detail
  Build.detailBox(d, not picked and "Click a product to see what it takes, then make it here.")
  if not picked then
    return
  end
  local item = kind.products[picked]
  local r = Kinds.recipe(kind, picked)
  local x, w = d.x + 14, d.w - 28
  local y = d.y + 12
  local vehicles = Features.byName.vehicles
  local cardW = d.w - 40 -- a little narrower, so the car leaves room for the rest
  local cardH = vehicles and vehicles.cardHeight and vehicles:cardHeight(item, cardW) or 0
  if cardH > 0 then
    vehicles:drawCard(item, d.x + 20, y, cardW) -- the car and a bar per stat
    y = y + cardH + 4
  else
    love.graphics.setColor(1, 1, 1, 0.05)
    love.graphics.rectangle("fill", d.x + d.w / 2 - 40, y, 80, 70, 6)
    Build.productIcon(item, d.x + d.w / 2, y + 35, 1.8)
    y = y + 78
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(title(item), d.x, y, d.w, "center")
    y = y + UI.fonts.body:getHeight() + 6
  end
  y = drawInputs(r, x, y, w)
  local rows = { { "A batch takes", ("%d s"):format(r.time) } }
  if r.batch > 1 then
    rows[#rows + 1] = { "Makes per batch", tostring(r.batch) }
  end
  rows[#rows + 1] = { "Holds", ("%d made"):format(r.cap) }
  rows[#rows + 1] = { "Starts selling at", priceText(r) }
  for _, row in ipairs(rows) do
    if y + 20 > L.make.y - 4 then
      break -- no room left above the button
    end
    y = Build.statRow(x, y, w, row[1], row[2])
  end

  local current = picked == b.product
  love.graphics.setFont(UI.fonts.small)
  local label = "MAKE THIS"
  if not current and b.output > 0 then
    -- What switching throws away: a line above the button, or on it when a
    -- car's stats leave no room.
    local made = math.floor(b.output)
    local warning = ("Switching throws away the %s already made."):format(Kinds.label(kind.products[b.product], made))
    local _, lines = UI.fonts.small:getWrap(warning, w)
    if y + 6 + #lines * UI.fonts.small:getHeight() <= L.make.y - 4 then
      love.graphics.setColor(1, 0.45, 0.4)
      Build.para(warning, x, y + 6, w)
    else
      label = ("MAKE THIS  (scraps %d)"):format(made)
    end
  end
  if current then
    Build.button(L.make, "MAKING THIS NOW", false, false, true)
  else
    Build.button(L.make, label, true, inside(L.make, mx, my))
  end
end

--- The whole screen for building `b` of `kind`. `picked` is the product
--- index in the side panel, `purse` my wallet, (mx, my) the mouse.
function Screen.draw(kind, b, picked, purse, mx, my)
  local L = Screen.layout(kind, picked)
  local p = L.panel
  Build.chrome(p, "WHAT TO MAKE", nil, purse)

  -- Back to the building's own menu.
  local bk = L.back
  local over = inside(bk, mx, my)
  love.graphics.setColor(1, 1, 1, over and 0.16 or 0.07)
  love.graphics.rectangle("fill", bk.x, bk.y, bk.w, bk.h, 5)
  love.graphics.setColor(1, 1, 1, over and 0.6 or 0.3)
  love.graphics.rectangle("line", bk.x, bk.y, bk.w, bk.h, 5)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1, over and 1 or 0.8)
  love.graphics.printf("< BACK", bk.x, bk.y + 5, bk.w, "center")

  for _, r in ipairs(L.cards) do
    drawCard(r, kind, r.index == b.product, inside(r, mx, my) or r.index == picked)
  end
  drawDetail(L, kind, b, picked, mx, my)

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local close = Controls.name(Controls.bindings("buy")[1])
  love.graphics.printf(("click a product to see it   %s: close"):format(close), p.x, L.foot, p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

return Screen
