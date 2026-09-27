-- The build screen: what the square in front of your own empty plot opens.
-- It looks like the shop (shop/screen.lua): a panel over the game with a
-- card per kind of building (kinds.lua), each showing a little working
-- model of the building, its name and what it costs, and its number key in
-- the corner. Click a card to see it in the side panel on the right: a
-- bigger model, what it does, its numbers, what it makes (as icons) and the
-- Build button. The number keys still build straight away.
--
-- `Screen.layout(picked)` works out every rectangle for the window as it is
-- now and `Screen.draw` paints them; init.lua hit-tests the same rectangles.
-- The pieces (the panel, a card's frame, the side panel's rows and button)
-- are shared with the product screen (product-screen.lua).

local Features = require("src.features")
local UI = require("src.ui")
local Controls = require("src.controls")
local Kinds = require("src.features.buildings.kinds")
local Render = require("src.features.buildings.render")
local Catalog = require("src.features.vehicles.catalog")

local Screen = {}

-- Tuning ------------------------------------------------------------------
Screen.width = 720 -- px for the cards (less on a narrow window); the side panel is added on the right
Screen.detailWidth = 300 -- px, the side panel
Screen.pad = 24 -- px inside the panel's edge

local CARD_W, CARD_H = 156, 150 -- a card: key, model, name, price
local MODEL_H = 86 -- the model's box on a card
local MODEL_W, MODEL_TALL = 250, 170 -- the ground a model is drawn on before it is shrunk to fit
local GAP = 10 -- px between cards
local TITLE_H = 56 -- the title strip
local FOOT_H = 60 -- the notice line and the key hint
local MARGIN = 8 -- px the panel keeps from the window's edges
local BUY_H = 38 -- the Build button
local ROW_H = 20 -- a row of numbers in the side panel
local ICON = 34 -- px between product icons in the side panel
local DETAIL_MODEL_H = 130 -- the model's box in the side panel
local MIN_H = 580 -- px; the side panel needs the room even when the cards don't
local GOLD = { 1, 0.85, 0.3 }

--- "30 Fcks", as the money feature writes it (or near enough without it).
local function amount(n)
  local money = Features.byName.money
  if money and money.amount then
    return money.amount(n)
  end
  return ("%d Fcks"):format(n)
end

--- How wide the cards' part of the panel is in a window `windowW` wide.
local function cardsWidth(windowW)
  return math.max(2 * Screen.pad + CARD_W, math.min(Screen.width, windowW - 2 * MARGIN - Screen.detailWidth))
end

--- Every rectangle on the screen:
---   panel     { x, y, w, h }
---   cards[i]  { x, y, w, h, kind }, one per kind in Kinds.list order
---   detail    { x, y, w, h }, the side panel
---   build     { x, y, w, h }, its Build button, when a kind is picked
---   notice / foot   y of the text lines under the cards
function Screen.layout(picked)
  local w, h = love.graphics.getDimensions()
  local areaW = cardsWidth(w)
  local n = #Kinds.list
  local cols = math.max(1, math.floor((areaW - 2 * Screen.pad + GAP) / (CARD_W + GAP)))
  local rows = math.ceil(n / cols)
  local gridH = rows * (CARD_H + GAP) - GAP
  local ph = math.max(TITLE_H + gridH + FOOT_H + Screen.pad, math.min(MIN_H, h - 2 * MARGIN))
  local pw = areaW + Screen.detailWidth
  local px = math.floor((w - pw) / 2)
  local py = math.max(MARGIN, math.floor((h - ph) / 2))
  local L = { panel = { x = px, y = py, w = pw, h = ph }, cards = {}, areaW = areaW }

  local gridCols = math.min(cols, n)
  local gx = px + math.floor((areaW - (gridCols * (CARD_W + GAP) - GAP)) / 2)
  local gy = py + TITLE_H
  for i, kind in ipairs(Kinds.list) do
    local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
    L.cards[i] = { x = gx + col * (CARD_W + GAP), y = gy + row * (CARD_H + GAP), w = CARD_W, h = CARD_H, kind = kind }
  end

  L.detail = { x = px + areaW, y = gy, w = Screen.detailWidth - Screen.pad, h = py + ph - 44 - gy }
  if picked then
    local d = L.detail
    L.build = { x = d.x + 12, y = d.y + d.h - BUY_H - 12, w = d.w - 24, h = BUY_H }
  end
  L.notice = gy + gridH + 14
  L.foot = py + ph - 26
  return L
end

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end
Screen.inside = inside

--- A made-up building of `kind`, hard at work with a full hopper and a few
--- things waiting in the yard, for the model on a card.
local demos = {}
local function demo(kind)
  if demos[kind.key] then
    return demos[kind.key]
  end
  local b = { kind = kind.key, public = true, running = true, progress = 0.5, product = 1, hopper = {}, pays = {},
    hp = kind.hp, output = 0 }
  if kind.rate then
    b.output = kind.cap * 0.6
  elseif kind.products then
    local r = Kinds.recipe(kind, 1)
    b.output = math.min(r.cap, r.unit * 3)
    for _, m in ipairs(Kinds.hopperList(kind)) do
      b.hopper[m] = Kinds.HOPPER
    end
  end
  demos[kind.key] = b
  return b
end

--- A little model of `kind` shrunk into the box (x, y, w, h), working away.
function Screen.drawModel(kind, x, y, w, h, time)
  local s = math.min(w / MODEL_W, h / MODEL_TALL)
  local mw, mh = MODEL_W * s, MODEL_TALL * s
  local sx, sy, sw, sh = love.graphics.getScissor()
  love.graphics.intersectScissor(x, y, w, h)
  love.graphics.push()
  love.graphics.translate(x + (w - mw) / 2, y + (h - mh) / 2)
  love.graphics.scale(s)
  local r = { x = 0, y = 0, w = MODEL_W, h = MODEL_TALL }
  local runner = kind.service and Features.byName[kind.service]
  if runner and runner.drawBuilding then
    runner:drawBuilding(demo(kind), kind, r, time)
  elseif not kind.service then
    Render.building(demo(kind), kind, r, time)
  end
  love.graphics.pop()
  love.graphics.setScissor(sx, sy, sw, sh)
  love.graphics.setLineWidth(1)
end

--- A card's frame, `lit` while the mouse is over it or it is the one in the side panel.
local function frame(r, lit)
  love.graphics.setColor(1, 1, 1, lit and 0.14 or 0.07)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  if lit then
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.9)
    love.graphics.setLineWidth(2)
  else
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.setLineWidth(1)
  end
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
  love.graphics.setLineWidth(1)
end
Screen.frame = frame

--- A price: gold when the wallet covers it, red when it doesn't.
local function priceColor(cost, purse)
  if purse >= cost then
    love.graphics.setColor(GOLD)
  else
    love.graphics.setColor(1, 0.45, 0.4)
  end
end

--- The number key that builds card `i`, in a little box in its corner.
local function keyTag(r, i)
  local bound = Controls.bindings("building-" .. i)[1]
  if not bound then
    return
  end
  local text = Controls.name(bound)
  love.graphics.setFont(UI.fonts.small)
  local w = math.max(20, UI.fonts.small:getWidth(text) + 10)
  love.graphics.setColor(0.36, 0.56, 0.92, 0.9)
  love.graphics.rectangle("fill", r.x + 6, r.y + 6, w, 18, 4)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(text, r.x + 6, r.y + 7, w, "center")
end

local function drawCard(r, i, purse, lit, time)
  frame(r, lit)
  Screen.drawModel(r.kind, r.x + 8, r.y + 8, r.w - 16, MODEL_H, time)
  keyTag(r, i)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.9, 0.9, 0.95)
  love.graphics.printf(r.kind.name, r.x + 4, r.y + MODEL_H + 16, r.w - 8, "center")
  priceColor(r.kind.cost, purse)
  love.graphics.printf(amount(r.kind.cost), r.x, r.y + r.h - 22, r.w, "center")
end

--- `text` wrapped to `w` at (x, y) in the current font; returns the y under it.
local function para(text, x, y, w)
  local font = love.graphics.getFont()
  local _, lines = font:getWrap(text, w)
  love.graphics.printf(text, x, y, w, "left")
  return y + #lines * font:getHeight()
end
Screen.para = para
Screen.amount = amount
Screen.GOLD = GOLD

--- One product's picture, centred on (cx, cy), about `scale` * 40 px
--- across (0.8 by default); a car lies nose up.
function Screen.productIcon(item, cx, cy, scale)
  scale = scale or 0.8
  local model = Catalog.fromItem(item)
  if model then
    Catalog.draw(model, cx, cy, -math.pi / 2, scale * 40 - 2)
    return
  end
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale)
  Render.itemIcon(item, 0, 0)
  love.graphics.pop()
end

--- A row of numbers in a side panel, `label` on the left and `value` on
--- the right (wrapped when long), from y; returns the y under it.
function Screen.statRow(x, y, w, label, value)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local vw = w - font:getWidth(label) - 12
  local _, parts = font:getWrap(value, vw)
  local rh = math.max(1, #parts) * font:getHeight() + ROW_H - font:getHeight()
  love.graphics.setColor(1, 1, 1, 0.04)
  love.graphics.rectangle("fill", x - 4, y - 1, w + 8, rh - 2, 3)
  love.graphics.setColor(0.7, 0.7, 0.76)
  love.graphics.print(label, x, y + 1)
  love.graphics.setColor(0.95, 0.95, 1)
  love.graphics.printf(value, x + w - vw, y + 1, vw, "right")
  return y + rh
end

--- The side panel's big button: gold while it can be pressed (`can`),
--- lit under the mouse (`over`); red when it can't, grey when that is no
--- fault of yours (`idle`: it is already done).
function Screen.button(b, text, can, over, idle)
  if idle then
    love.graphics.setColor(1, 1, 1, 0.06)
  elseif can then
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], over and 0.4 or 0.25)
  else
    love.graphics.setColor(1, 0.45, 0.4, 0.15)
  end
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
  love.graphics.setColor(idle and { 1, 1, 1, 0.3 } or can and GOLD or { 1, 0.45, 0.4, 0.7 })
  love.graphics.setLineWidth(over and can and 2 or 1)
  love.graphics.rectangle("line", b.x, b.y, b.w, b.h, 6)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1, can and 1 or 0.6)
  love.graphics.printf(text, b.x, b.y + b.h / 2 - UI.fonts.body:getHeight() / 2, b.w, "center")
end

--- The side panel's box, and a line in the middle of it while nothing is picked.
function Screen.detailBox(d, empty)
  love.graphics.setColor(1, 1, 1, 0.05)
  love.graphics.rectangle("fill", d.x, d.y, d.w, d.h, 8)
  love.graphics.setColor(1, 1, 1, 0.14)
  love.graphics.rectangle("line", d.x, d.y, d.w, d.h, 8)
  love.graphics.setFont(UI.fonts.small)
  if empty then
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.printf(empty, d.x + 20, d.y + d.h / 2 - 20, d.w - 40, "center")
  end
end

--- The game dimmed, the panel `p` over it, `title` across the top, `note`
--- on the left of the title strip and my wallet on the right.
function Screen.chrome(p, title, note, purse)
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 10)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 10)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(title, p.x, p.y + 12, p.w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(GOLD)
  love.graphics.printf("You have " .. amount(purse), p.x, p.y + 20, p.w - Screen.pad, "right")
  if note then
    love.graphics.setColor(0.7, 0.7, 0.75, 0.9)
    love.graphics.print(note, p.x + Screen.pad, p.y + 20)
  end
end

--- The numbers for `kind` in the side panel: { label, value } rows.
local function statRows(kind)
  local rows = { { "Hit points", tostring(kind.hp) } }
  if kind.rate then
    rows[#rows + 1] = { "Earns", ("%s a minute"):format(amount(math.floor(kind.rate * 60 + 0.5))) }
    rows[#rows + 1] = { "Holds", amount(kind.cap) }
  elseif kind.products then
    local r = Kinds.recipe(kind, 1)
    rows[#rows + 1] = { "A batch takes", ("%d s"):format(r.time) }
    rows[#rows + 1] = { "Holds", ("%d made"):format(r.cap) }
    local runs = Kinds.hopperList(kind)
    rows[#rows + 1] = { "Runs on", #runs > 0 and table.concat(runs, ", ") or "nothing: digs it up" }
  end
  return rows
end

--- The side panel: `picked` (a bigger model, its name, what it does, its
--- numbers, what it makes and the Build button), or how to fill it.
local function drawDetail(L, picked, purse, mx, my, time)
  local d = L.detail
  Screen.detailBox(d, not picked and "Click a building to see what it does, then build it here.")
  if not picked then
    return
  end
  local x, w = d.x + 14, d.w - 28
  local y = d.y + 12
  Screen.drawModel(picked, x, y, w, DETAIL_MODEL_H, time)
  y = y + DETAIL_MODEL_H + 8
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(picked.name, d.x, y, d.w, "center")
  y = y + UI.fonts.body:getHeight() + 4
  love.graphics.setFont(UI.fonts.small)
  if picked.blurb then
    love.graphics.setColor(0.88, 0.88, 0.92)
    y = para(picked.blurb, x, y, w) + 8
  end
  for _, row in ipairs(statRows(picked)) do
    y = Screen.statRow(x, y, w, row[1], row[2])
  end

  -- What it makes, as a row of pictures that wraps; as many as fit above the button.
  local products = picked.products or {}
  if #products > 0 then
    y = y + 6
    love.graphics.setColor(0.7, 0.7, 0.76)
    love.graphics.print("Makes", x, y)
    y = y + ROW_H
    local per = math.max(1, math.floor(w / ICON))
    local room = math.max(0, math.floor((L.build.y - 8 - y) / ICON)) * per
    for i, item in ipairs(products) do
      if i > room then
        break
      end
      local col, row = (i - 1) % per, math.floor((i - 1) / per)
      local cx, cy = x + col * ICON + ICON / 2, y + row * ICON + ICON / 2
      love.graphics.setColor(1, 1, 1, 0.05)
      love.graphics.rectangle("fill", cx - ICON / 2 + 1, cy - ICON / 2 + 1, ICON - 2, ICON - 2, 4)
      Screen.productIcon(item, cx, cy)
    end
  end

  -- The Build button: its price on it, gold when the wallet covers it.
  Screen.button(L.build, "BUILD   " .. amount(picked.cost), picked.cost <= purse, inside(L.build, mx, my))
end

--- The whole screen. `picked` is the kind in the side panel, `purse` my
--- wallet, (mx, my) the mouse, `time` for the models' moving parts.
function Screen.draw(picked, purse, mx, my, time)
  local L = Screen.layout(picked)
  local p = L.panel
  Screen.chrome(p, "BUILD", "Pick a building for your plot", purse)

  for i, r in ipairs(L.cards) do
    drawCard(r, i, purse, inside(r, mx, my) or r.kind == picked, time)
  end
  drawDetail(L, picked, purse, mx, my, time)

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local close = Controls.name(Controls.bindings("buy")[1])
  love.graphics.printf("click a building to see it   number key: build it   " .. close .. ": close", p.x, L.foot,
    p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

return Screen
