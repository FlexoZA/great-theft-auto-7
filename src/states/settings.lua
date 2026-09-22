-- Settings screen. Sections down the left: Sound (a slider per volume
-- channel registered with src/audio) and Controls (primary and secondary
-- binding per action registered with src/controls; click a slot, press a
-- key or mouse button). Changes apply and save immediately.

local State = require("src.state")
local UI = require("src.ui")
local Audio = require("src.audio")
local Controls = require("src.controls")
local Background = require("src.art.menu_background")

local SettingsState = {}

local PANEL_W = 760
local TABS_W = 160
local PREVIEW_GAP = 0.35 -- seconds between preview sounds while dragging

SettingsState.sections = {
  { key = "sound", label = "Sound" },
  { key = "controls", label = "Controls" },
}

local ROW_H = 40

function SettingsState:enter()
  UI.load()
  Audio.playMenuTheme()
  self.background = self.background or Background.new()
  self.section = self.section or "sound"
  self.previewAt = {}

  self.tabs = {}
  for _, sec in ipairs(self.sections) do
    self.tabs[#self.tabs + 1] = UI.button({ label = sec.label, w = TABS_W - 20, onClick = function()
      self.section = sec.key
      self:build()
    end })
  end
  self.backButton = UI.button({ label = "Back", w = 140, onClick = function()
    State.switch("menu")
  end })
  self.resetButton = UI.button({ label = "Reset to defaults", w = 200, onClick = function()
    if self.section == "sound" then
      Audio.resetVolumes()
    else
      Controls.reset()
    end
    self:build()
  end })
  self.capturing = nil -- { action, slot } while waiting for a key
  self:build()
end

--- Rebuild the widgets for the current section from live values.
function SettingsState:build()
  self.sliders = {}
  self.rows = {}
  self.capturing = nil
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

function SettingsState:preview(ch)
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

function SettingsState:layout()
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
  for i, s in ipairs(self.sliders) do
    s.x, s.y, s.w = sx, py + 135 + (i - 1) * 64, sw
  end
  for i, row in ipairs(self.rows) do
    local y = py + 100 + (i - 1) * ROW_H
    row.y = y
    row.x = sx
    row.buttons[1].x, row.buttons[1].y = sx + sw - 320, y
    row.buttons[2].x, row.buttons[2].y = sx + sw - 155, y
  end
  self.backButton.x, self.backButton.y = px + 10, py + ph - 56
  self.resetButton.x, self.resetButton.y = px + PANEL_W - 210, py + ph - 56
  self.faceX, self.faceY = math.floor(w * 0.5), math.floor(h * 0.55)
  self.faceScale = math.floor(math.min(h / 76, (w * 0.55) / 64))
end

function SettingsState:update(dt)
  self:layout()
  self.background:update(dt)
  for _, s in ipairs(self.sliders) do
    s:update()
  end
end

function SettingsState:draw()
  local w, h = love.graphics.getDimensions()
  self.background:draw(self.faceX, self.faceY, self.faceScale)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.rectangle("fill", 0, 0, w, h)

  local p = self.panel
  love.graphics.setColor(0.08, 0.08, 0.10, 0.92)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 8)
  love.graphics.setColor(0.3, 0.3, 0.35)
  love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 8)
  love.graphics.line(p.x + TABS_W, p.y + 60, p.x + TABS_W, p.y + p.h - 70)

  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print("Settings", p.x + 20, p.y + 16)

  for i, b in ipairs(self.tabs) do
    b.selected = self.sections[i].key == self.section
    b:draw()
  end
  for _, s in ipairs(self.sliders) do
    s:draw()
  end

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.5, 0.5, 0.55)
  if self.section == "sound" then
    love.graphics.print("Drag a slider to hear it. Saved automatically.", p.x + TABS_W + 30, p.y + 70)
  else
    love.graphics.print("Click a slot, then press a key or mouse button. Backspace clears it, Esc cancels.",
      p.x + TABS_W + 30, p.y + 70)
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

  self.backButton:draw()
  self.resetButton:draw()
end

function SettingsState:keypressed(key)
  if self.capturing then
    local c = self.capturing
    self.capturing = nil
    if key == "backspace" or key == "delete" then
      Controls.clear(c.action.key, c.slot)
    elseif key ~= "escape" then
      Controls.set(c.action.key, c.slot, key)
    end
    return
  end
  if key == "escape" then
    State.switch("menu")
  elseif Controls.is("mute", key) then
    Audio.toggleMute()
  end
end

function SettingsState:mousepressed(x, y, button)
  if self.capturing then
    local c = self.capturing
    self.capturing = nil
    Controls.set(c.action.key, c.slot, "mouse" .. button)
    return
  end
  for _, row in ipairs(self.rows) do
    for slot = 1, 2 do
      if row.buttons[slot]:mousepressed(x, y, button) then
        return
      end
    end
  end
  for _, s in ipairs(self.sliders) do
    if s:mousepressed(x, y, button) then
      return
    end
  end
  for _, b in ipairs(self.tabs) do
    if b:mousepressed(x, y, button) then
      return
    end
  end
  if self.backButton:mousepressed(x, y, button) then
    return
  end
  self.resetButton:mousepressed(x, y, button)
end

return SettingsState
