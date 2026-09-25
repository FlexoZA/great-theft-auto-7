-- The vehicles screen: a panel over the game with a row per car you own,
-- its colour, name, where it is, a health bar and a button or two for what
-- can be done with it right now (tow, repair, take out, park, collect).
-- A button that can't be used says why when you point at it.
--
-- `Screen.layout(entries, page)` works out every rectangle for the window
-- as it is now and `Screen.draw` paints them; init.lua hit-tests the same
-- rectangles. Features don't get the mouse wheel, so a long list is paged.

local UI = require("src.ui")
local Controls = require("src.controls")
local Catalog = require("src.features.vehicles.catalog")

local Screen = {}

Screen.width = 780 -- px; the panel is centred on the screen

local PAD = 24 -- px inside the panel's edge
local TITLE_H = 56
local INFO_H = 30 -- the line about your garages
local ROW_H, GAP = 58, 6
local FOOT_H = 70 -- the notice line and the key hint
local BTN_W, BTN_H = 130, 30
local MARGIN = 8 -- px the panel keeps from the window's top and bottom
local ICON_LEN = 42 -- px nose to tail of a model's picture in its row

local STATE_COLORS = {
  road = { 0.8, 0.8, 0.85 },
  stored = { 0.5, 1, 0.6 },
  wrecked = { 1, 0.6, 0.35 },
  destroyed = { 1, 0.45, 0.4 },
  impound = { 0.95, 0.75, 0.15 },
}

local function inside(r, x, y)
  return r and x >= r.x and x < r.x + r.w and y >= r.y and y < r.y + r.h
end
Screen.inside = inside

--- Every rectangle for `entries` on page `page`:
---   panel            { x, y, w, h }
---   rows[i]          { x, y, w, h, entry, buttons = { { x, y, w, h, action } } }
---   prev / next      when there is more than one page
---   page, pages, notice, foot (y of the lines under the rows)
function Screen.layout(entries, page)
  local w, h = love.graphics.getDimensions()
  local fit = math.max(1, math.floor((h - 2 * MARGIN - TITLE_H - INFO_H - FOOT_H - PAD + GAP) / (ROW_H + GAP)))
  local pages = math.max(1, math.ceil(#entries / fit))
  page = math.max(1, math.min(pages, page or 1))
  local shown = math.max(1, math.min(fit, #entries))
  local ph = TITLE_H + INFO_H + shown * (ROW_H + GAP) - GAP + FOOT_H + PAD
  local px = math.floor((w - Screen.width) / 2)
  local py = math.max(MARGIN, math.floor((h - ph) / 2))
  local L = { panel = { x = px, y = py, w = Screen.width, h = ph }, rows = {}, page = page, pages = pages }
  local top = py + TITLE_H + INFO_H
  local first = (page - 1) * fit
  for i = 1, math.min(fit, #entries - first) do
    local e = entries[first + i]
    local r = { x = px + PAD, y = top + (i - 1) * (ROW_H + GAP), w = Screen.width - 2 * PAD, h = ROW_H, entry = e }
    r.buttons = {}
    local bx = r.x + r.w - 10
    for j = #e.actions, 1, -1 do
      bx = bx - BTN_W
      r.buttons[j] = { x = bx, y = r.y + (ROW_H - BTN_H) / 2, w = BTN_W, h = BTN_H, action = e.actions[j] }
      bx = bx - 8
    end
    L.rows[i] = r
  end
  local under = top + shown * (ROW_H + GAP) - GAP + 10
  if pages > 1 then
    L.prev = { x = px + Screen.width / 2 - 90, y = under, w = 36, h = 24 }
    L.next = { x = px + Screen.width / 2 + 54, y = under, w = 36, h = 24 }
  end
  L.notice = under + 30
  L.foot = py + ph - 26
  return L
end

local function button(b, mx, my)
  local a = b.action
  local hover = inside(b, mx, my)
  if not a.enabled then
    love.graphics.setColor(0.28, 0.28, 0.32)
  elseif hover then
    love.graphics.setColor(0.36, 0.56, 0.92)
  else
    love.graphics.setColor(0.24, 0.40, 0.72)
  end
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h, 6)
  love.graphics.setColor(1, 1, 1, a.enabled and 1 or 0.5)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf(a.label, b.x + 4, b.y + (b.h - UI.fonts.small:getHeight()) / 2, b.w - 8, "center")
end

local function arrow(r, text, mx, my)
  love.graphics.setColor(1, 1, 1, inside(r, mx, my) and 0.25 or 0.12)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 4)
  love.graphics.setColor(1, 1, 1)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.printf(text, r.x, r.y + 1, r.w, "center")
end

--- Paint the screen. `info` is the line under the title, `notice` the last
--- answer ({ text, color }) or nil.
function Screen.draw(entries, page, info, notice, mx, my)
  local L = Screen.layout(entries, page)
  local p = L.panel
  love.graphics.setColor(0.10, 0.10, 0.13, 0.95)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 10)
  love.graphics.setColor(1, 0.85, 0.3, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 10)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Your vehicles", p.x, p.y + 12, p.w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.8, 0.8, 0.85)
  love.graphics.printf(info, p.x + PAD, p.y + TITLE_H, p.w - 2 * PAD, "center")

  if #entries == 0 then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0.7, 0.7, 0.75)
    love.graphics.printf("You don't own a car.", p.x, p.y + TITLE_H + INFO_H + 18, p.w, "center")
  end
  local why
  for _, r in ipairs(L.rows) do
    local e = r.entry
    love.graphics.setColor(1, 1, 1, 0.06)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
    -- The car's picture: its model, or the starter car's paint as a little
    -- car-shaped block.
    local alpha = e.state == "destroyed" and 0.4 or 1
    if e.model then
      Catalog.draw(e.model, r.x + 30, r.y + ROW_H / 2, 0, ICON_LEN, alpha)
    else
      local c = e.color
      love.graphics.setColor(c[1], c[2], c[3], alpha)
      love.graphics.rectangle("fill", r.x + 12, r.y + 18, 36, 20, 4)
      love.graphics.setColor(0.6, 0.8, 1, alpha)
      love.graphics.rectangle("fill", r.x + 36, r.y + 21, 8, 14)
    end
    -- Name and where it is.
    local textW = r.w - 64 - #r.buttons * (BTN_W + 8) - 150
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(UI.fit(e.name, UI.fonts.body, textW), r.x + 60, r.y + 8)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(STATE_COLORS[e.state] or STATE_COLORS.road)
    love.graphics.print(UI.fit(e.status, UI.fonts.small, textW), r.x + 60, r.y + 33)
    -- Health.
    local frac = e.max > 0 and math.max(0, math.min(1, e.hp / e.max)) or 0
    local mx0 = r.x + 60 + textW + 10
    UI.meter(mx0, r.y + 20, 130, 10, frac, UI.rampColor(frac))
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.printf(("%d/%d"):format(math.floor(e.hp + 0.5), e.max), mx0, r.y + 34, 130, "center")
    for _, b in ipairs(r.buttons) do
      button(b, mx, my)
      if not b.action.enabled and inside(b, mx, my) then
        why = b.action.why
      end
    end
  end
  if L.prev then
    arrow(L.prev, "<", mx, my)
    arrow(L.next, ">", mx, my)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.printf(("%d / %d"):format(L.page, L.pages), p.x, L.prev.y + 4, p.w, "center")
  end
  love.graphics.setFont(UI.fonts.small)
  if why then
    love.graphics.setColor(0.8, 0.8, 0.85)
    love.graphics.printf(why, p.x + PAD, L.notice, p.w - 2 * PAD, "center")
  elseif notice then
    love.graphics.setColor(notice.color)
    love.graphics.printf(notice.text, p.x + PAD, L.notice, p.w - 2 * PAD, "center")
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  local key = Controls.name(Controls.bindings("vehicles")[1])
  love.graphics.printf(key .. ": close", p.x, L.foot, p.w, "center")
  love.graphics.setColor(1, 1, 1)
end

return Screen
