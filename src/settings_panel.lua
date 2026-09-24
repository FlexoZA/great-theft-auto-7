-- The settings panel: sections down the left -- Sound (a slider per volume
-- channel registered with src/audio), Controls (primary and secondary
-- binding per action registered with src/controls; click a slot, press a
-- key or mouse button), Video (display mode, size, vsync and display
-- toggles from src/video) and Server (what the host sets for the game
-- they run, from src/server_settings). Changes apply and save immediately.
--
-- It is hosted twice: by the settings screen (src/states/settings.lua) over
-- the menu background, and by the pause menu in the game, over the blurred
-- world. The host draws whatever goes behind it, forwards update, draw,
-- keypressed, mousepressed and wheelmoved, and gets `onClose` when the
-- player is done (Back, or Esc when nothing is being captured).
--
-- The section's content scrolls when it is taller than the space: the
-- Controls tab outgrows a small window as features register actions.

local UI = require("src.ui")
local Audio = require("src.audio")
local Controls = require("src.controls")
local Video = require("src.video")
local ServerSettings = require("src.server_settings")
local Settings = require("src.settings")

local Panel = {}
Panel.__index = Panel

local PANEL_W = 760
local TABS_W = 160
local PREVIEW_GAP = 0.35 -- seconds between preview sounds while dragging
local ROW_H = 40 -- a controls row
local SLIDER_H = 64 -- a sound slider with its label
local CYCLER_H = 48 -- a video option
local CONTENT_TOP = 100 -- px below the panel top where a section's content starts
local CONTENT_BOTTOM = 70 -- px above the panel bottom it stops: the buttons live there
local SCROLL_STEP = 48 -- px per wheel notch

Panel.sections = {
  { key = "sound", label = "Sound" },
  { key = "controls", label = "Controls" },
  { key = "video", label = "Video" },
  { key = "server", label = "Server" },
}

local ON_OFF = { { label = "On", value = true }, { label = "Off", value = false } }

--- Panel.new({ onClose = function(panel) end, closeLabel = "Back" })
function Panel.new(opts)
  opts = opts or {}
  UI.load()
  local self = setmetatable({
    onClose = opts.onClose,
    section = "sound",
    previewAt = {},
    scroll = 0,
    maxScroll = 0,
    capturing = nil, -- { action, slot } while waiting for a key
  }, Panel)

  self.tabs = {}
  for _, sec in ipairs(Panel.sections) do
    self.tabs[#self.tabs + 1] = UI.button({ label = sec.label, w = TABS_W - 20, onClick = function()
      self.section = sec.key
      self:build()
    end })
  end
  self.backButton = UI.button({ label = opts.closeLabel or "Back", w = 140, onClick = function()
    self:close()
  end })
  self.resetButton = UI.button({ label = "Reset to defaults", w = 200, onClick = function()
    if self.section == "sound" then
      Audio.resetVolumes()
    elseif self.section == "controls" then
      Controls.reset()
    else
      Video.reset()
    end
    self:build()
  end })
  self:build()
  return self
end

function Panel:close()
  self.capturing = nil
  if self.onClose then
    self.onClose(self)
  end
end

--- Rebuild the widgets for the current section from live values.
function Panel:build()
  self.sliders = {}
  self.rows = {}
  self.cyclers = {}
  self.capturing = nil
  self.scroll = 0
  if self.section == "video" then
    local function toggle(label, key)
      self.cyclers[#self.cyclers + 1] = UI.cycler({
        label = label,
        options = ON_OFF,
        index = Video.get(key) and 1 or 2,
        onChange = function(v)
          Video.set(key, v)
        end,
      })
    end
    self.cyclers[#self.cyclers + 1] = UI.cycler({
      label = "Display",
      options = { { label = "Windowed", value = false }, { label = "Fullscreen", value = true } },
      index = Video.get("fullscreen") and 2 or 1,
      onChange = function(v)
        Video.set("fullscreen", v)
        self:build()
      end,
    })
    local sizes = {}
    for _, s in ipairs(Video.SIZES) do
      sizes[#sizes + 1] = { label = s[1] .. " x " .. s[2], value = s }
    end
    self.cyclers[#self.cyclers + 1] = UI.cycler({
      label = "Window size",
      options = sizes,
      index = Video.sizeIndex(),
      enabled = not Video.get("fullscreen"),
      onChange = function(s)
        Settings.set("video.width", s[1])
        Video.set("height", s[2])
      end,
    })
    toggle("VSync", "vsync")
    toggle("Show FPS", "showFps")
    toggle("Screen shake", "screenShake")
    toggle("Menu scanlines", "scanlines")
  end
  if self.section == "server" then
    local levels = {}
    for _, d in ipairs(ServerSettings.DIFFICULTIES) do
      levels[#levels + 1] = { label = d.label, value = d.key }
    end
    self.cyclers[#self.cyclers + 1] = UI.cycler({
      label = "Bot difficulty",
      options = levels,
      index = ServerSettings.difficultyIndex(),
      onChange = function(v)
        ServerSettings.set("botDifficulty", v)
      end,
    })
  end
  if self.section == "controls" then
    for _, action in ipairs(Controls.actions) do
      local row = { action = action, buttons = {} }
      for slot = 1, 2 do
        row.buttons[slot] = UI.button({ w = 150, h = 32, label = "", onClick = function()
          self.capturing = { action = action, slot = slot }
        end })
      end
      self.rows[#self.rows + 1] = row
    end
  end
  if self.section == "sound" then
    -- Master and music first, then the feature channels by name.
    local channels = {}
    for _, ch in ipairs(Audio.channels) do
      channels[#channels + 1] = ch
    end
    local rank = { master = 1, music = 2 }
    table.sort(channels, function(a, b)
      local ra, rb = rank[a.key] or 3, rank[b.key] or 3
      if ra ~= rb then
        return ra < rb
      end
      return a.label < b.label
    end)
    for _, ch in ipairs(channels) do
      self.sliders[#self.sliders + 1] = UI.slider({
        label = ch.label,
        value = Audio.get(ch.key),
        onChange = function(v)
          Audio.setVolume(ch.key, v)
          self:preview(ch)
        end,
      })
    end
  end
end

function Panel:preview(ch)
  local fn = ch.preview or (ch.key == "master" and Audio.byKey.weapons and Audio.byKey.weapons.preview)
  if not fn then
    return
  end
  local now = love.timer.getTime()
  if (self.previewAt[ch.key] or -1) + PREVIEW_GAP <= now then
    self.previewAt[ch.key] = now
    fn()
  end
end

--- How tall the current section's content is, before scrolling.
function Panel:contentHeight()
  if self.section == "sound" then
    return #self.sliders * SLIDER_H
  elseif self.section == "video" or self.section == "server" then
    return #self.cyclers * CYCLER_H
  end
  return #self.rows * ROW_H
end

--- Place everything for this frame's window size. Content is laid out from
--- the top of its area minus the scroll, and drawn through a scissor so it
--- never leaks over the hint above or the buttons below.
function Panel:layout()
  local w, h = love.graphics.getDimensions()
  local px = math.floor((w - PANEL_W) / 2)
  local py = math.floor(h * 0.06)
  local ph = math.floor(h * 0.88)
  self.panel = { x = px, y = py, w = PANEL_W, h = ph }
  for i, b in ipairs(self.tabs) do
    b.x, b.y = px + 10, py + 70 + (i - 1) * 52
  end
  local sx = px + TABS_W + 30
  local sw = PANEL_W - TABS_W - 60
  local top = py + CONTENT_TOP
  local viewH = ph - CONTENT_TOP - CONTENT_BOTTOM
  self.clip = { x = px + TABS_W + 1, y = top - 6, w = PANEL_W - TABS_W - 2, h = viewH + 6 }
  self.maxScroll = math.max(0, self:contentHeight() - viewH)
  self.scroll = math.max(0, math.min(self.scroll, self.maxScroll))
  local y0 = top - self.scroll

  for i, s in ipairs(self.sliders) do
    s.x, s.y, s.w = sx, y0 + 35 + (i - 1) * SLIDER_H, sw
  end
  for i, c in ipairs(self.cyclers) do
    c.x, c.y, c.w = sx + sw - 320, y0 + (i - 1) * CYCLER_H, 320
    c.labelX = sx
  end
  for i, row in ipairs(self.rows) do
    local y = y0 + (i - 1) * ROW_H
    row.y = y
    row.x = sx
    row.buttons[1].x, row.buttons[1].y = sx + sw - 320, y
    row.buttons[2].x, row.buttons[2].y = sx + sw - 155, y
  end
  self.backButton.x, self.backButton.y = px + 10, py + ph - 56
  self.resetButton.x, self.resetButton.y = px + PANEL_W - 210, py + ph - 56
end

function Panel:update(_dt)
  self:layout()
  for _, s in ipairs(self.sliders) do
    s:update()
  end
end

--- Is a screen point inside the scrolling content area?
function Panel:inContent(x, y)
  local c = self.clip
  return c and x >= c.x and x <= c.x + c.w and y >= c.y and y <= c.y + c.h
end

function Panel:inPanel(x, y)
  local p = self.panel
  return p and x >= p.x and x <= p.x + p.w and y >= p.y and y <= p.y + p.h
end

--- The panel itself: the host has already drawn whatever goes behind it.
function Panel:draw()
  if not self.panel then
    self:layout()
  end
  local p = self.panel
  UI.panel(p.x, p.y, p.w, p.h)
  love.graphics.setColor(0.3, 0.3, 0.35)
  love.graphics.line(p.x + TABS_W, p.y + 60, p.x + TABS_W, p.y + p.h - 70)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Settings", p.x + 20, p.y + 16)

  for i, b in ipairs(self.tabs) do
    b.selected = Panel.sections[i].key == self.section
    b:draw()
  end

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.5, 0.5, 0.55)
  if self.section == "sound" then
    love.graphics.print("Drag a slider to hear it. Saved automatically.", p.x + TABS_W + 30, p.y + 70)
  elseif self.section == "video" then
    love.graphics.print("Changes apply straight away. Saved automatically.", p.x + TABS_W + 30, p.y + 70)
  elseif self.section == "server" then
    love.graphics.print("For games you host. Applies at once, even mid-game. Saved automatically.",
      p.x + TABS_W + 30, p.y + 70)
  else
    love.graphics.print("Click a slot, then press a key or mouse button. Backspace clears it, Esc cancels.",
      p.x + TABS_W + 30, p.y + 70)
  end

  -- The section's content, clipped to its area.
  local c = self.clip
  love.graphics.setScissor(c.x, c.y, c.w, c.h)
  for _, s in ipairs(self.sliders) do
    s:draw()
  end
  for _, cy in ipairs(self.cyclers) do
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1, cy.enabled and 1 or 0.5)
    love.graphics.print(cy.label, cy.labelX, cy.y + 5)
    cy:draw()
  end
  for _, row in ipairs(self.rows) do
    local b = Controls.bindings(row.action.key)
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(row.action.label, row.x, row.y + 5)
    for slot = 1, 2 do
      local btn = row.buttons[slot]
      local capturing = self.capturing and self.capturing.action == row.action and self.capturing.slot == slot
      btn.label = capturing and "press a key..." or Controls.name(b[slot])
      btn.enabled = not self.capturing or capturing
      btn:draw()
    end
  end
  love.graphics.setScissor()

  -- A scrollbar down the right edge when there is more than fits.
  if self.maxScroll > 0 then
    local trackX, trackY, trackH = p.x + p.w - 12, c.y, c.h
    local viewH = c.h
    local thumbH = math.max(24, trackH * viewH / (viewH + self.maxScroll))
    local thumbY = trackY + (trackH - thumbH) * (self.scroll / self.maxScroll)
    love.graphics.setColor(1, 1, 1, 0.08)
    love.graphics.rectangle("fill", trackX, trackY, 6, trackH, 3)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("fill", trackX, thumbY, 6, thumbH, 3)
  end

  self.backButton:draw()
  self.resetButton:draw()
  love.graphics.setColor(1, 1, 1)
end

--- Returns true when the panel used the key (it always does while shown).
function Panel:keypressed(key)
  if self.capturing then
    local c = self.capturing
    self.capturing = nil
    if key == "backspace" or key == "delete" then
      Controls.clear(c.action.key, c.slot)
    elseif key ~= "escape" then
      Controls.set(c.action.key, c.slot, key)
    end
    return true
  end
  if key == "escape" then
    self:close()
  elseif Controls.is("mute", key) then
    Audio.toggleMute()
  end
  return true
end

function Panel:mousepressed(x, y, button)
  if self.capturing then
    local c = self.capturing
    self.capturing = nil
    Controls.set(c.action.key, c.slot, "mouse" .. button)
    return true
  end
  if self:inContent(x, y) then
    for _, row in ipairs(self.rows) do
      for slot = 1, 2 do
        if row.buttons[slot]:mousepressed(x, y, button) then
          return true
        end
      end
    end
    for _, c in ipairs(self.cyclers) do
      if c:mousepressed(x, y, button) then
        return true
      end
    end
    for _, s in ipairs(self.sliders) do
      if s:mousepressed(x, y, button) then
        return true
      end
    end
  end
  for _, b in ipairs(self.tabs) do
    if b:mousepressed(x, y, button) then
      return true
    end
  end
  if self.backButton:mousepressed(x, y, button) then
    return true
  end
  return self.resetButton:mousepressed(x, y, button)
end

--- Wheel over the panel scrolls the content.
function Panel:wheelmoved(_dx, dy)
  if self.maxScroll <= 0 or not self:inPanel(love.mouse.getPosition()) then
    return false
  end
  self.scroll = math.max(0, math.min(self.scroll - dy * SCROLL_STEP, self.maxScroll))
  return true
end

return Panel
