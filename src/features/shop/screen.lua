-- The shop screen: a panel over the game with a tab per shelf (all, guns,
-- ammo, abilities, gear, cars: catalog.lua) and a card per thing for sale. Item cards show the picture the
-- inventory draws for the item, its name and its price; car cards borrow
-- the vehicle factory's card (the car over a bar per stat). Click a card to
-- see it in the side panel on the right: a bigger picture, what it does and
-- its numbers in the tier on show (details.lua), and the Buy button that
-- buys it. Under the tabs a row of tier buttons (common,
-- uncommon, rare, legendary) picks the tier the equipment cards show and
-- sell: each is framed and named in the tier's colour and costs the tier's
-- price; hovering one says what the tier improves, under the cards.
--
-- `Screen.layout(tab, page)` works out every rectangle for the window as it
-- is now and `Screen.draw` paints them; init.lua hit-tests the same
-- rectangles. There is no scrolling: a shelf that doesn't fit is paged,
-- with arrows under the cards.

local Features = require("src.features")
local UI = require("src.ui")
local Controls = require("src.controls")
local Render = require("src.features.buildings.render")
local Catalog = require("src.features.shop.catalog")
local Kinds = require("src.features.buildings.kinds")
local Tiers = require("src.features.tiers")
local Details = require("src.features.shop.details")

local Screen = {}

-- Tuning ------------------------------------------------------------------
Screen.width = 800 -- px for the cards (less on a narrow window); the side panel is added on the right
Screen.detailWidth = 280 -- px, the side panel
Screen.pad = 24 -- px inside the panel's edge

local CARD_W, CARD_H = 140, 118 -- an item card: badge, picture, name, price
local CAR_W = 240 -- a car card; as tall as vehicles' card plus the badge and price rows
local GAP = 8 -- px between cards
local TITLE_H = 56 -- the title strip
local TABS_H = 44 -- the tab row
local TIERS_H = 34 -- the tier row under it
local FOOT_H = 66 -- the notice line and the key hint
local BADGE_H = 22 -- the row a card's kind badge sits in
local PRICE_H = 26 -- the row a card's price sits in
local MARGIN = 8 -- px the panel keeps from the window's edges
local BUY_H = 38 -- the Buy button
local ROW_H = 20 -- a row of numbers in the side panel

local BADGES = {
  gun = { 0.36, 0.56, 0.92 },
  ammo = { 0.8, 0.6, 0.2 },
  ability = { 0.6, 0.45, 0.95 },
  passive = { 0.3, 0.7, 0.5 },
  supply = { 0.85, 0.25, 0.25 },
  armor = { 0.35, 0.55, 0.85 },
  head = { 0.55, 0.45, 0.7 },
  body = { 0.55, 0.45, 0.7 },
  pants = { 0.55, 0.45, 0.7 },
  shoes = { 0.55, 0.45, 0.7 },
  car = { 0.3, 0.75, 0.55 },
}

--- "30 Fcks", as the money feature writes it (or near enough without it).
local function amount(n)
  local money = Features.byName.money
  if money and money.amount then
    return money.amount(n)
  end
  return ("%d Fcks"):format(n)
end

--- "FREE", or "30 Fcks": what `entry` costs in tier `tier`.
function Screen.priceText(entry, tier)
  local p = Catalog.price(entry, tier)
  if p <= 0 then
    return "FREE"
  end
  return amount(p)
end

--- The size of a card on `tab`: item cards are fixed, car cards as tall as
--- the vehicle card they wrap.
local function cardSize(tab)
  if tab ~= "cars" then
    return CARD_W, CARD_H
  end
  local vehicles = Features.byName.vehicles
  local tall = 0
  for _, e in ipairs(Catalog.onTab("cars")) do
    local h = vehicles and vehicles.cardHeight and vehicles:cardHeight(e.item, CAR_W) or 0
    tall = math.max(tall, h)
  end
  if tall == 0 then
    return CARD_W, CARD_H
  end
  return CAR_W, BADGE_H + tall + PRICE_H
end

--- How wide the cards' part of the panel is in a window `windowW` wide:
--- Screen.width, less if the side panel wouldn't fit beside it.
local function cardsWidth(windowW)
  return math.max(2 * Screen.pad + CARD_W, math.min(Screen.width, windowW - 2 * MARGIN - Screen.detailWidth))
end

--- How a shelf fits: columns, rows per page and cards per page.
local function grid(tab, windowH, areaW)
  local cw, ch = cardSize(tab)
  local cols = math.max(1, math.floor((areaW - 2 * Screen.pad + GAP) / (cw + GAP)))
  local avail = windowH - 2 * MARGIN - TITLE_H - TABS_H - TIERS_H - FOOT_H - Screen.pad
  local rowsFit = math.max(1, math.floor((avail + GAP) / (ch + GAP)))
  return cw, ch, cols, rowsFit
end

--- Every rectangle on the screen for `tab`, page `page`:
---   panel            { x, y, w, h }
---   tabs[i]          { x, y, w, h, key, title }
---   tiers[i]         { x, y, w, h, key, title }, the tier buttons (none on the cars tab)
---   cards[i]         { x, y, w, h, entry }, the cards on this page
---   prev / next      { x, y, w, h } when there is more than one page
---   page, pages      where we are and how many there are
---   notice / foot    y of the text lines under the cards
---   detail           { x, y, w, h }, the side panel
---   buy              { x, y, w, h }, its Buy button, when something is picked
--- `picked` is the entry in the side panel, or nil.
function Screen.layout(tab, page, picked)
  local w, h = love.graphics.getDimensions()
  local areaW = cardsWidth(w)
  local entries = Catalog.onTab(tab)
  local cw, ch, cols, rowsFit = grid(tab, h, areaW)
  local perPage = cols * rowsFit
  local pages = math.max(1, math.ceil(#entries / perPage))
  page = math.max(1, math.min(pages, page or 1))

  -- The panel stays the same height whichever tab is up, so the tabs
  -- don't jump under the mouse: as tall as the taller shelf needs.
  local gridH = 0
  for _, t in ipairs(Catalog.tabs) do
    local _, tch, tcols, trows = grid(t.key, h, areaW)
    local n = #Catalog.onTab(t.key)
    local rows = math.min(trows, math.max(1, math.ceil(n / tcols)))
    gridH = math.max(gridH, rows * (tch + GAP) - GAP)
  end
  local ph = TITLE_H + TABS_H + TIERS_H + gridH + FOOT_H + Screen.pad
  local pw = areaW + Screen.detailWidth
  local px = math.floor((w - pw) / 2)
  local py = math.max(MARGIN, math.floor((h - ph) / 2))
  local L = {
    panel = { x = px, y = py, w = pw, h = ph }, tabs = {}, tiers = {}, cards = {}, page = page, pages = pages,
  }
  local dy = py + TITLE_H
  L.detail = { x = px + areaW, y = dy, w = Screen.detailWidth - Screen.pad, h = py + ph - 44 - dy }
  if picked then
    local d = L.detail
    L.buy = { x = d.x + 12, y = d.y + d.h - BUY_H - 12, w = d.w - 24, h = BUY_H }
  end

  -- Tabs across the top, under the title.
  local n = #Catalog.tabs
  local tabW = math.min(140, math.floor((areaW - 2 * Screen.pad - (n - 1) * GAP) / n))
  local tx = px + math.floor((areaW - #Catalog.tabs * (tabW + GAP) + GAP) / 2)
  for i, t in ipairs(Catalog.tabs) do
    L.tabs[i] = {
      x = tx + (i - 1) * (tabW + GAP), y = py + TITLE_H, w = tabW, h = TABS_H - 12, key = t.key, title = t.title,
    }
  end

  -- The tier buttons under them, smaller; cars come in no tiers.
  if tab ~= "cars" then
    local nt = #Tiers.list
    local tierW = math.min(110, math.floor((areaW - 2 * Screen.pad - (nt - 1) * GAP) / nt))
    local tierX = px + math.floor((areaW - nt * (tierW + GAP) + GAP) / 2)
    for i, t in ipairs(Tiers.list) do
      L.tiers[i] = { x = tierX + (i - 1) * (tierW + GAP), y = py + TITLE_H + TABS_H - 6, w = tierW, h = 24,
        key = t.key, title = t.title }
    end
  end

  -- The cards on this page, the grid centred in the panel.
  local first = (page - 1) * perPage
  local count = math.min(perPage, #entries - first)
  local gridCols = math.min(cols, math.max(1, count))
  local gridW = gridCols * (cw + GAP) - GAP
  local gx, gy = px + math.floor((areaW - gridW) / 2), py + TITLE_H + TABS_H + TIERS_H
  for i = 1, count do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    L.cards[i] = { x = gx + col * (cw + GAP), y = gy + row * (ch + GAP), w = cw, h = ch, entry = entries[first + i] }
  end

  local under = py + TITLE_H + TABS_H + TIERS_H + gridH + 10
  if pages > 1 then
    L.prev = { x = px + areaW / 2 - 90, y = under, w = 36, h = 24 }
    L.next = { x = px + areaW / 2 + 54, y = under, w = 36, h = 24 }
  end
  L.notice = under + 30
  L.foot = py + ph - 26
  L.areaW = areaW
  return L
end

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end
Screen.inside = inside

--- A card's frame: `lit` while the mouse is over it or it is the one in
--- the side panel, `glow` (0..1) just after a purchase.
local function frame(r, lit, glow)
  if glow > 0 then
    love.graphics.setColor(1, 0.85, 0.3, glow * 0.45)
    love.graphics.rectangle("fill", r.x - 4, r.y - 4, r.w + 8, r.h + 8, 8)
  end
  love.graphics.setColor(1, 1, 1, lit and 0.14 or 0.07)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  if lit then
    love.graphics.setColor(1, 0.85, 0.3, 0.9)
    love.graphics.setLineWidth(2)
  else
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.setLineWidth(1)
  end
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
  love.graphics.setLineWidth(1)
end

--- The kind badge in a card's top-left corner.
local function badge(r, kind)
  local c = BADGES[kind] or { 0.5, 0.5, 0.55 }
  love.graphics.setFont(UI.fonts.small)
  local text = kind:upper()
  local w = UI.fonts.small:getWidth(text) + 12
  love.graphics.setColor(c[1], c[2], c[3], 0.85)
  love.graphics.rectangle("fill", r.x + 6, r.y + 5, w, 16, 4)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(text, r.x + 6, r.y + 5, w, "center")
end

--- The price along the bottom of a card: green when free, gold when the
--- wallet covers it, red when it doesn't.
local function price(r, entry, purse, tier)
  love.graphics.setFont(UI.fonts.small)
  local text = Screen.priceText(entry, tier)
  local cost = Catalog.price(entry, tier)
  if cost <= 0 then
    love.graphics.setColor(0.5, 1, 0.55)
  elseif purse >= cost then
    love.graphics.setColor(1, 0.85, 0.3)
  else
    love.graphics.setColor(1, 0.45, 0.4)
  end
  love.graphics.printf(text, r.x, r.y + r.h - 20, r.w, "center")
end

--- An item card; equipment in tier `tier`: framed and named in its colour.
local function drawItemCard(r, entry, purse, lit, glow, tier)
  frame(r, lit, glow)
  if entry.tiered then
    Tiers.drawFrame(tier, r.x, r.y, r.w, r.h, lit and 1 or 0.75)
  end
  badge(r, entry.badge or entry.kind)
  Render.itemIcon(entry.item, r.x + r.w / 2, r.y + BADGE_H + 26)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(entry.tiered and Tiers.color(tier) or { 0.9, 0.9, 0.95 })
  love.graphics.printf(entry.name, r.x + 4, r.y + BADGE_H + 50, r.w - 8, "center")
  price(r, entry, purse, entry.tiered and tier or nil)
end

local function drawCarCard(r, entry, purse, lit, glow)
  frame(r, lit, glow)
  badge(r, entry.badge or entry.kind)
  local vehicles = Features.byName.vehicles
  if vehicles and vehicles.drawCard then
    vehicles:drawCard(entry.item, r.x, r.y + BADGE_H, r.w)
  else
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf(entry.name, r.x + 4, r.y + r.h / 2 - 8, r.w - 8, "center")
  end
  price(r, entry, purse)
end

--- A paging arrow: "<" or ">", lit under the mouse.
local function arrow(r, text, lit)
  love.graphics.setColor(1, 1, 1, lit and 0.2 or 0.08)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1, lit and 1 or 0.7)
  love.graphics.printf(text, r.x, r.y + 2, r.w, "center")
end

--- `text` wrapped to `w` at (x, y) in the current font; returns the y under it.
local function para(text, x, y, w)
  local font = love.graphics.getFont()
  local _, lines = font:getWrap(text, w)
  love.graphics.printf(text, x, y, w, "left")
  return y + #lines * font:getHeight()
end

--- The side panel: `picked` in tier `tier` (a bigger picture, its name,
--- what it does, its numbers and the Buy button), or how to fill it.
local function drawDetail(L, picked, purse, mx, my, tier)
  local d = L.detail
  love.graphics.setColor(1, 1, 1, 0.05)
  love.graphics.rectangle("fill", d.x, d.y, d.w, d.h, 8)
  love.graphics.setColor(1, 1, 1, 0.14)
  love.graphics.rectangle("line", d.x, d.y, d.w, d.h, 8)
  love.graphics.setFont(UI.fonts.small)
  if not picked then
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.printf("Click a card to see what it does, then buy it here.", d.x + 20, d.y + d.h / 2 - 20,
      d.w - 40, "center")
    return
  end
  local tiered = picked.tiered
  local x, w = d.x + 14, d.w - 28
  local y = d.y + 12
  if Catalog.isCar(picked) then
    local vehicles = Features.byName.vehicles
    if vehicles and vehicles.drawCard then
      vehicles:drawCard(picked.item, d.x, y, d.w)
      y = y + vehicles:cardHeight(picked.item, d.w) + 6
    end
    love.graphics.setColor(0.85, 0.85, 0.9)
    para("Parked on the road outside the door, yours to drive off.", x, y, w)
  else
    if tiered then
      Tiers.drawFrame(tier, d.x + d.w / 2 - 36, y, 72, 64, 0.9)
    end
    love.graphics.push()
    love.graphics.translate(d.x + d.w / 2, y + 32)
    love.graphics.scale(1.8)
    Render.itemIcon(picked.item, 0, 0)
    love.graphics.pop()
    y = y + 72
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(tiered and Tiers.color(tier) or { 1, 1, 1 })
    local name = picked.n > 1 and Kinds.label(picked.item, picked.n) or picked.name
    love.graphics.printf(tiered and Tiers.named(name, tier) or name, d.x, y, d.w, "center")
    y = y + UI.fonts.body:getHeight() + 6
    local info = Details.of(picked, tier)
    love.graphics.setFont(UI.fonts.small)
    if info then
      if info.blurb then
        love.graphics.setColor(0.88, 0.88, 0.92)
        y = para(info.blurb, x, y, w) + 6
      end
      if info.use then
        love.graphics.setColor(0.6, 0.62, 0.7)
        y = para(info.use, x, y, w) + 8
      end
      for _, row in ipairs(info.rows) do
        love.graphics.setColor(1, 1, 1, 0.04)
        love.graphics.rectangle("fill", x - 4, y - 1, w + 8, ROW_H - 2, 3)
        love.graphics.setColor(0.7, 0.7, 0.76)
        love.graphics.print(row.label, x, y + 1)
        love.graphics.setColor(row.lit and Tiers.color(tier) or { 0.95, 0.95, 1 })
        love.graphics.printf(row.value, x, y + 1, w, "right")
        y = y + ROW_H
      end
    end
    if tiered then
      love.graphics.setColor(Tiers.color(tier))
      para(("%s: %s"):format(Tiers.get(tier).title, Kinds.tierLine(Tiers.join(picked.item, tier))), x, y + 4, w)
    end
  end

  -- The Buy button: its price on it, gold when the wallet covers it.
  local b = L.buy
  local cost = Catalog.price(picked, tiered and tier or nil)
  local can = cost <= purse
  local over = inside(b, mx, my)
  if can then
    love.graphics.setColor(0.45, 0.95, 0.6, over and 0.4 or 0.25)
  else
    love.graphics.setColor(1, 0.45, 0.4, 0.15)
  end
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
  love.graphics.setColor(can and { 0.45, 0.95, 0.6 } or { 1, 0.45, 0.4, 0.7 })
  love.graphics.setLineWidth(over and can and 2 or 1)
  love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1, can and 1 or 0.6)
  local label = "BUY   " .. Screen.priceText(picked, tiered and tier or nil)
  love.graphics.printf(label, b.x, b.y + b.h / 2 - UI.fonts.body:getHeight() / 2, b.w, "center")
end

--- The whole screen. `tab` and `page` are what is up, `purse` my wallet,
--- (mx, my) the mouse, `flash` { item, t } a card lit after a purchase and
--- `notice` a line to show instead of the usual hint, `tier` the tier
--- equipment is shown and sold in, `picked` the entry in the side panel.
function Screen.draw(tab, page, purse, mx, my, flash, notice, tier, picked)
  local L = Screen.layout(tab, page, picked)
  local p = L.panel
  local w, h = love.graphics.getDimensions()

  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 10)
  love.graphics.setColor(0.45, 0.95, 0.6, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 10)
  love.graphics.setLineWidth(1)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("SHOP", p.x, p.y + 12, p.w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf("You have " .. amount(purse), p.x, p.y + 20, p.w - Screen.pad, "right")
  love.graphics.setColor(0.5, 1, 0.55, 0.9)
  love.graphics.print("Everything is free, for now", p.x + Screen.pad, p.y + 20)

  for _, t in ipairs(L.tabs) do
    local active = t.key == tab
    local lit = inside(t, mx, my)
    if active then
      love.graphics.setColor(0.45, 0.95, 0.6, 0.22)
    else
      love.graphics.setColor(1, 1, 1, lit and 0.12 or 0.05)
    end
    love.graphics.rectangle("fill", t.x, t.y, t.w, t.h, 6)
    love.graphics.setColor(0.45, 0.95, 0.6, active and 0.9 or 0.25)
    love.graphics.rectangle("line", t.x, t.y, t.w, t.h, 6)
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1, active and 1 or 0.6)
    love.graphics.printf(t.title:upper(), t.x, t.y + 5, t.w, "center")
  end

  for _, r in ipairs(L.cards) do
    local e = r.entry
    local glow = flash and flash.item == e.item and flash.t or 0
    local lit = inside(r, mx, my) or e == picked
    if Catalog.isCar(e) then
      drawCarCard(r, e, purse, lit, glow)
    else
      drawItemCard(r, e, purse, lit, glow, tier)
    end
  end
  drawDetail(L, picked, purse, mx, my, tier)

  for _, t in ipairs(L.tiers) do
    -- A tier button: its colour, lit when it is the one up.
    local c = Tiers.color(t.key)
    local active = t.key == tier
    love.graphics.setColor(c[1], c[2], c[3], active and 0.35 or (inside(t, mx, my) and 0.18 or 0.08))
    love.graphics.rectangle("fill", t.x, t.y, t.w, t.h, 5)
    love.graphics.setColor(c[1], c[2], c[3], active and 1 or 0.45)
    love.graphics.setLineWidth(active and 2 or 1)
    love.graphics.rectangle("line", t.x, t.y, t.w, t.h, 5)
    love.graphics.setLineWidth(1)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(c[1], c[2], c[3], active and 1 or 0.7)
    love.graphics.printf(t.title:upper(), t.x, t.y + 4, t.w, "center")
  end

  if L.prev then
    arrow(L.prev, "<", inside(L.prev, mx, my))
    arrow(L.next, ">", inside(L.next, mx, my))
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.printf(("page %d/%d"):format(L.page, L.pages), L.prev.x + L.prev.w, L.prev.y + 4,
      L.next.x - L.prev.x - L.prev.w, "center")
  end

  love.graphics.setFont(UI.fonts.small)
  local over
  for _, r in ipairs(L.cards) do
    if r.entry.tiered and inside(r, mx, my) then
      over = Tiers.join(r.entry.item, tier)
    end
  end
  if notice then
    love.graphics.setColor(notice.color[1], notice.color[2], notice.color[3], math.min(1, notice.t * 2))
    love.graphics.printf(notice.text, p.x, L.notice, L.areaW, "center")
  elseif over then
    -- The card under the mouse: its tier, in its colour, and what that does.
    love.graphics.setColor(Tiers.color(tier))
    love.graphics.printf(("%s (%s): %s"):format(Kinds.name(Tiers.base(over), 1), Tiers.get(tier).title,
      Kinds.tierLine(over)), p.x, L.notice, L.areaW, "center")
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  local close = Controls.name(Controls.bindings("shop")[1])
  local foot = "click a card to see it   " .. close .. ": close shop"
  love.graphics.printf(foot, p.x, L.foot, p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

return Screen
