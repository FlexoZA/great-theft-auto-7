-- Settings screen: the settings panel (src/settings_panel.lua) over the
-- menu background, reached from the main menu. The same panel opens from
-- the pause menu while a game is running.

local State = require("src.state")
local UI = require("src.ui")
local Audio = require("src.audio")
local Background = require("src.art.menu_background")
local Panel = require("src.settings_panel")

local SettingsState = {}

SettingsState.sections = Panel.sections

function SettingsState:enter()
  UI.load()
  Audio.playMenuTheme()
  self.background = Background.shared()
  self.panel = self.panel or Panel.new({ onClose = function()
    State.switch("menu")
  end })
  self.panel:build() -- live values may have changed since last time
end

function SettingsState:update(dt)
  self.background:update(dt)
  self.panel:update(dt)
end

function SettingsState:draw()
  self.background:drawDimmed()
  self.panel:draw()
end

function SettingsState:keypressed(key)
  self.panel:keypressed(key)
end

function SettingsState:mousepressed(x, y, button)
  self.panel:mousepressed(x, y, button)
end

function SettingsState:wheelmoved(dx, dy)
  self.panel:wheelmoved(dx, dy)
end

return SettingsState
