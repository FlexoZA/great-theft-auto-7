-- Settings screen. Sections down the left; "Sound" is the first, with a
-- slider per volume channel that features registered with src/audio.
-- Changes apply and save immediately; dragging a slider plays that
-- channel's preview so you can hear the level.

local State = require("src.state")
local UI = require("src.ui")
local Audio = require("src.audio")
local Background = require("src.art.menu_background")

local SettingsState = {}

local PANEL_W = 760
local TABS_W = 160
local PREVIEW_GAP = 0.35 -- seconds between preview sounds while dragging

SettingsState.sections = {
  { key = "sound", label = "Sound" },
}

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
    Audio.resetVolumes()
    self:build()
  end })
  self:build()
end

--- Rebuild the widgets for the current section from live values.
function SettingsState:build()
  self.sliders = {}
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
  local py = math.floor(h * 0.12)
  local ph = math.floor(h * 0.76)
  self.panel = { x = px, y = py, w = PANEL_W, h = ph }
  for i, b in ipairs(self.tabs) do
    b.x, b.y = px + 10, py + 70 + (i - 1) * 52
  end
  local sx = px + TABS_W + 30
  local sw = PANEL_W - TABS_W - 60
  for i, s in ipairs(self.sliders) do
    s.x, s.y, s.w = sx, py + 135 + (i - 1) * 64, sw
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

  for _, b in ipairs(self.tabs) do
    b:draw()
  end
  for _, s in ipairs(self.sliders) do
    s:draw()
  end

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.5, 0.5, 0.55)
  love.graphics.print("Drag a slider to hear it. Saved automatically.", p.x + TABS_W + 30, p.y + 70)

  self.backButton:draw()
  self.resetButton:draw()
end

function SettingsState:keypressed(key)
  if key == "escape" then
    State.switch("menu")
  elseif key == "m" then
    Audio.toggleMute()
  end
end

function SettingsState:mousepressed(x, y, button)
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
