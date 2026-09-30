-- Controls overview: F1 puts every key binding on one screen. A keyboard
-- (and a mouse beside it) with each key that does something lit, and under
-- it a list of every action with its keys, read live from src/controls.lua
-- so a rebind or a feature's new action shows up without touching this.
-- Point at a key and the actions on it light up in the list; point at an
-- action and its keys light up on the keyboard.
--
-- Numbered runs of actions ("Weapon slot 1".."Weapon slot 4") fold into one
-- row. While it is up the mouse (`pointerTaken`) and the number keys
-- (`menuOpen`) are ours; F1 again or Esc (`closeMenu`) closes it, and
-- opening it takes down any other panel first. The wheel scrolls the list
-- when the window is too short for all of it.

local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")

local Overview = {
  name = "controls-overview",
  priority = 997, -- over the inventory (995) and every other panel
}

Overview.open = false
Overview.scroll = 0 -- px the list is scrolled up by
Overview.maxScroll = 0

-- Colours
local BACKDROP = { 0.03, 0.035, 0.05, 0.96 }
local KEY_IDLE = { 0.16, 0.17, 0.2 }
local KEY_IDLE_TEXT = { 0.45, 0.46, 0.5 }
local KEY_BOUND = { 0.2, 0.34, 0.52 }
local KEY_BOUND_TEXT = { 0.9, 0.94, 1 }
local KEY_HOT = { 0.95, 0.72, 0.25 }
local KEY_HOT_TEXT = { 0.08, 0.06, 0.02 }
local ROW_HOT = { 0.95, 0.72, 0.25, 0.18 }
local LABEL = { 0.85, 0.86, 0.9 }
local DIM = { 0.6, 0.62, 0.68 }

-- The keyboard, in key units: { binding, legend, width } per key (width 1
-- unless given), rows top to bottom, { false, width } for a gap. The F-row
-- stands a half row above the rest, as on a real board.
local KEYBOARD = {
  {
    { "escape", "Esc" },
    { false, 1 },
    { "f1", "F1" },
    { "f2", "F2" },
    { "f3", "F3" },
    { "f4", "F4" },
    { false, 0.5 },
    { "f5", "F5" },
    { "f6", "F6" },
    { "f7", "F7" },
    { "f8", "F8" },
    { false, 0.5 },
    { "f9", "F9" },
    { "f10", "F10" },
    { "f11", "F11" },
    { "f12", "F12" },
  },
  {
    { "`", "`" },
    { "1", "1" },
    { "2", "2" },
    { "3", "3" },
    { "4", "4" },
    { "5", "5" },
    { "6", "6" },
    { "7", "7" },
    { "8", "8" },
    { "9", "9" },
    { "0", "0" },
    { "-", "-" },
    { "=", "=" },
    { "backspace", "Backspace", 2 },
  },
  {
    { "tab", "Tab", 1.5 },
    { "q", "Q" },
    { "w", "W" },
    { "e", "E" },
    { "r", "R" },
    { "t", "T" },
    { "y", "Y" },
    { "u", "U" },
    { "i", "I" },
    { "o", "O" },
    { "p", "P" },
    { "[", "[" },
    { "]", "]" },
    { "\\", "\\", 1.5 },
  },
  {
    { "capslock", "Caps", 1.75 },
    { "a", "A" },
    { "s", "S" },
    { "d", "D" },
    { "f", "F" },
    { "g", "G" },
    { "h", "H" },
    { "j", "J" },
    { "k", "K" },
    { "l", "L" },
    { ";", ";" },
    { "'", "'" },
    { "return", "Enter", 2.25 },
  },
  {
    { "lshift", "Shift", 2.25 },
    { "z", "Z" },
    { "x", "X" },
    { "c", "C" },
    { "v", "V" },
    { "b", "B" },
    { "n", "N" },
    { "m", "M" },
    { ",", "," },
    { ".", "." },
    { "/", "/" },
    { "rshift", "Shift", 2.75 },
  },
  {
    { "lctrl", "Ctrl", 1.25 },
    { "lgui", "Super", 1.25 },
    { "lalt", "Alt", 1.25 },
    { "space", "Space", 6.25 },
    { "ralt", "Alt", 1.25 },
    { "rgui", "Super", 1.25 },
    { "application", "Menu", 1.25 },
    { "rctrl", "Ctrl", 1.25 },
  },
}

-- Right of the main block: the navigation keys and the arrows, as
-- { binding, legend, column, row } in key units from the block's corner.
local NAV = {
  { "insert", "Ins", 0, 1 },
  { "home", "Home", 1, 1 },
  { "pageup", "PgUp", 2, 1 },
  { "delete", "Del", 0, 2 },
  { "end", "End", 1, 2 },
  { "pagedown", "PgDn", 2, 2 },
  { "up", "Up", 1, 4 },
  { "left", "Left", 0, 5 },
  { "down", "Down", 1, 5 },
  { "right", "Right", 2, 5 },
}

local NAV_X = 15.5 -- units: where the navigation keys start, half a key right of the 15-wide main block
local MOUSE_X = 19.25 -- units: where the mouse starts
local MOUSE_W = 2.5
local TOTAL_W = MOUSE_X + MOUSE_W
local TOTAL_H = 6.5 -- units: the F-row, a half-row gap, five rows

--- Every action as a list row, numbered runs folded into one:
--- { label, keys = { binding = true }, text = "W / Up" }.
local function buildRows()
  local rows = {}
  local run -- the row a numbered run is folding into
  for _, action in ipairs(Controls.actions) do
    local b = Controls.bindings(action.key)
    local prefix, n = action.label:match("^(.-)%s*(%d+)$")
    n = tonumber(n)
    if run and prefix == run.prefix and n == run.last + 1 then
      run.last = n
      run.lastKey = b[1]
      for i = 1, 2 do
        if b[i] then
          run.keys[b[i]] = true
        end
      end
    else
      local row = { label = action.label, keys = {}, bindings = b }
      for i = 1, 2 do
        if b[i] then
          row.keys[b[i]] = true
        end
      end
      if prefix and n then
        row.prefix, row.first, row.last, row.firstKey, row.lastKey = prefix, n, n, b[1], b[1]
        run = row
      else
        run = nil
      end
      rows[#rows + 1] = row
    end
  end
  for _, row in ipairs(rows) do
    if row.prefix and row.last > row.first then
      row.label = ("%s %d-%d"):format(row.prefix, row.first, row.last)
      row.text = Controls.name(row.firstKey) .. " - " .. Controls.name(row.lastKey)
    else
      local b = row.bindings
      if b[1] and b[2] then
        row.text = Controls.name(b[1]) .. " / " .. Controls.name(b[2])
      elseif b[1] or b[2] then
        row.text = Controls.name(b[1] or b[2])
      else
        row.text = "-"
      end
    end
  end
  return rows
end

function Overview:load()
  Controls.register("controls-overview", "Show all controls", "f1")
end

function Overview:enterGame()
  self.open, self.scroll = false, 0
end

function Overview:exitGame()
  self.open = false
end

function Overview:toggle(client)
  if self.open then
    self.open = false
    return
  end
  Features.call("closeMenu", client)
  self.open, self.scroll = true, 0
end

--- The `closeMenu` convention: Esc takes the overview down.
function Overview:closeMenu()
  if not self.open then
    return false
  end
  self.open = false
  return true
end

--- The `pointerTaken` and `menuOpen` conventions: the mouse and the number
--- keys are ours while it is up.
function Overview:pointerTaken()
  return self.open
end

function Overview:menuOpen()
  return self.open
end

function Overview:keypressed(key, client)
  if Controls.is("controls-overview", key) then
    self:toggle(client)
  end
end

function Overview:wheelmoved(_dx, dy)
  if self.open then
    self.scroll = math.max(0, math.min(self.maxScroll, self.scroll - dy * 40))
  end
end

local function inside(mx, my, x, y, w, h)
  return mx >= x and mx < x + w and my >= y and my < y + h
end

--- One key cap at (x, y), `w` x `h` px: lit when something is bound to it,
--- hot when it is the key under the mouse or belongs to the hovered row.
local function drawKey(x, y, w, h, legend, bound, hot)
  local fill, text = KEY_IDLE, KEY_IDLE_TEXT
  if hot then
    fill, text = KEY_HOT, KEY_HOT_TEXT
  elseif bound then
    fill, text = KEY_BOUND, KEY_BOUND_TEXT
  end
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", x + 1, y + 2, w, h, 4, 4)
  love.graphics.setColor(fill)
  love.graphics.rectangle("fill", x, y, w, h, 4, 4)
  love.graphics.setColor(text)
  local font = UI.fonts.small
  legend = UI.fit(legend, font, w + 4) -- "Home" runs a hair past a key's padding
  love.graphics.print(legend, math.floor(x + (w - font:getWidth(legend)) / 2),
    math.floor(y + (h - font:getHeight()) / 2))
end

function Overview:drawScreen(client)
  if not self.open then
    return
  end
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local fonts = UI.fonts
  local rows = buildRows()

  -- Who is bound to what, for lighting the keys.
  local bound = {}
  for _, row in ipairs(rows) do
    for binding in pairs(row.keys) do
      bound[binding] = bound[binding] or {}
      table.insert(bound[binding], row)
    end
  end

  love.graphics.setColor(BACKDROP)
  love.graphics.rectangle("fill", 0, 0, w, h)

  -- Title and how to get out.
  love.graphics.setFont(fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("CONTROLS", 0, 18, w, "center")
  love.graphics.setFont(fonts.small)
  love.graphics.setColor(DIM)
  local closeKey = Controls.name(Controls.bindings("controls-overview")[1])
  love.graphics.printf(closeKey .. " or Esc: close   -   change keys in Settings, Controls", 0, 52, w, "center")

  -- The board: as big as fits in the width and in two fifths of the height.
  local unit = math.floor(math.min(46, (w - 60) / TOTAL_W, (h * 0.4) / TOTAL_H))
  local gap = math.max(2, math.floor(unit * 0.08))
  local bx = math.floor((w - TOTAL_W * unit) / 2)
  local by = 80

  -- The list is drawn after the board, but which row the mouse is on must
  -- be known first to light its keys; lay the list out now.
  local listTop = by + TOTAL_H * unit + 40
  local cols = math.max(1, math.min(3, math.floor((w - 60) / 330)))
  local colW = math.floor((math.min(w - 60, cols * 400)) / cols)
  local lx = math.floor((w - cols * colW) / 2)
  local rowH = fonts.small:getHeight() + 4
  local perCol = math.ceil(#rows / cols)
  local listH = perCol * rowH
  local listBottom = h - 22
  self.maxScroll = math.max(0, listH - (listBottom - listTop))
  self.scroll = math.min(self.scroll, self.maxScroll)

  local hoverRow
  local inList = my >= listTop and my < listBottom
  for i, row in ipairs(rows) do
    local c = math.floor((i - 1) / perCol)
    row.x, row.y = lx + c * colW, listTop + ((i - 1) % perCol) * rowH - self.scroll
    if inList and inside(mx, my, row.x, row.y, colW - 16, rowH) then
      hoverRow = row
    end
  end

  -- Keys: find the one under the mouse, then draw them all.
  local hoverKey
  local caps = {}
  local function cap(binding, legend, x, y, kw)
    caps[#caps + 1] = { binding = binding, legend = legend, x = x, y = y, w = kw }
    if binding and inside(mx, my, x, y, kw, unit - gap) then
      hoverKey = binding
    end
  end
  for r, keys in ipairs(KEYBOARD) do
    local ky = by + (r == 1 and 0 or (r - 0.5) * unit)
    local kx = 0
    for _, k in ipairs(keys) do
      local kw
      if k[1] == false then
        kw = k[2]
      else
        kw = k[3] or 1
        cap(k[1], k[2], bx + kx * unit, ky, kw * unit - gap)
      end
      kx = kx + kw
    end
  end
  for _, k in ipairs(NAV) do
    cap(k[1], k[2], bx + (NAV_X + k[3]) * unit, by + (k[4] + 0.5) * unit, unit - gap)
  end

  -- The mouse: two buttons over a body, the wheel between them.
  local mox, moy = bx + MOUSE_X * unit, by + 1.5 * unit
  local mw, mh = MOUSE_W * unit, 4.5 * unit
  local half = math.floor((mw - gap) / 2)
  local buttons = {
    { "mouse1", "Left", mox, moy, half, 1.6 * unit },
    { "mouse2", "Right", mox + half + gap, moy, mw - half - gap, 1.6 * unit },
  }
  local wheel = { "mouse3", "", mox + mw / 2 - unit * 0.22, moy + unit * 0.35, unit * 0.44, unit * 0.9 }
  for _, btn in ipairs({ buttons[1], buttons[2], wheel }) do
    if inside(mx, my, btn[3], btn[4], btn[5], btn[6]) then
      hoverKey = btn[1]
    end
  end

  local hotKeys = hoverRow and hoverRow.keys or {}
  local function isHot(binding)
    return binding ~= nil and (binding == hoverKey or hotKeys[binding] == true)
  end

  love.graphics.setFont(fonts.small)
  for _, c in ipairs(caps) do
    drawKey(c.x, c.y, c.w, unit - gap, c.legend, bound[c.binding] ~= nil, isHot(c.binding))
  end
  love.graphics.setColor(KEY_IDLE)
  love.graphics.rectangle("fill", mox, moy, mw, mh, mw / 2, mw / 2)
  for _, btn in ipairs(buttons) do
    drawKey(btn[3], btn[4], btn[5], btn[6], btn[2], bound[btn[1]] ~= nil, isHot(btn[1]))
  end
  drawKey(wheel[3], wheel[4], wheel[5], wheel[6], "", bound.mouse3 ~= nil, isHot("mouse3"))
  love.graphics.setColor(DIM)
  love.graphics.printf("Mouse", mox, moy + mh + 4, mw, "center")

  -- What the key under the mouse does, in one line under the board.
  local infoY = by + TOTAL_H * unit + 12
  if hoverKey then
    local names = {}
    for _, row in ipairs(bound[hoverKey] or {}) do
      names[#names + 1] = row.label
    end
    local text = Controls.name(hoverKey) .. ":  " .. (#names > 0 and table.concat(names, ",  ") or "nothing")
    love.graphics.setColor(KEY_HOT)
    love.graphics.printf(UI.fit(text, fonts.small, w - 40), 20, infoY, w - 40, "center")
  else
    love.graphics.setColor(DIM)
    love.graphics.printf("Point at a key to see what it does", 0, infoY, w, "center")
  end

  -- The list, clipped to the space left under the board.
  love.graphics.setScissor(0, listTop, w, listBottom - listTop)
  for _, row in ipairs(rows) do
    local hot = row == hoverRow
    if not hot and hoverKey then
      hot = row.keys[hoverKey] == true
    end
    if hot then
      love.graphics.setColor(ROW_HOT)
      love.graphics.rectangle("fill", row.x - 6, row.y, colW - 10, rowH, 3, 3)
    end
    local keysW = math.min(fonts.small:getWidth(row.text), math.floor(colW * 0.45))
    local text = UI.fit(row.text, fonts.small, keysW)
    love.graphics.setColor(hot and KEY_HOT or KEY_BOUND_TEXT)
    love.graphics.print(text, row.x + colW - 20 - fonts.small:getWidth(text), row.y + 2)
    love.graphics.setColor(hot and { 1, 1, 1 } or LABEL)
    love.graphics.print(UI.fit(row.label, fonts.small, colW - 34 - keysW), row.x, row.y + 2)
  end
  love.graphics.setScissor()
  if self.maxScroll > 0 then
    love.graphics.setColor(DIM)
    local more = self.scroll < self.maxScroll and "wheel: more below" or "wheel: back up"
    love.graphics.printf(more, 0, listBottom + 3, w - 20, "right")
  end

  love.graphics.setColor(1, 1, 1)
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client)
  end
end

return Overview
