-- Sight cones: the ` key hides or shows every cone of sight drawn over the
-- world, the police's fans and the D-Day defenders' alike. Only what is
-- drawn changes; the police and the soldiers see you just the same.
--
-- The choice is this machine's own, kept in the settings file, so it
-- survives a restart. A feature that draws a cone asks
-- Features.any("hideSightCones") and skips the cone when that is true
-- (the `hideSightCones` convention, docs/features.md).

local Controls = require("src.controls")
local Settings = require("src.settings")
local UI = require("src.ui")

local SightCones = {
  name = "sight-cones",
}

SightCones.noteTime = 1.6 -- seconds the "cones hidden/shown" note stays up
SightCones.noteY = 118 -- px; a free HUD row at the left margin

SightCones.hidden = false
SightCones.note = 0 -- seconds left on the note

function SightCones:load()
  Controls.register("sight-cones", "Hide / show sight cones", "`")
  self.hidden = Settings.get("sightCones.hidden", false) == true
end

function SightCones:enterGame()
  self.note = 0
end

--- The `hideSightCones` convention: true while cones should not be drawn.
function SightCones:hideSightCones()
  return self.hidden
end

function SightCones:update(dt)
  self.note = math.max(0, self.note - dt)
end

function SightCones:keypressed(key)
  if Controls.is("sight-cones", key) then
    self.hidden = not self.hidden
    Settings.set("sightCones.hidden", self.hidden)
    self.note = self.noteTime
  end
end

function SightCones:drawHUD()
  if self.note <= 0 then
    return
  end
  local keyName = Controls.name(Controls.bindings("sight-cones")[1])
  local text = (self.hidden and "Sight cones hidden" or "Sight cones shown") .. "   " .. keyName .. ": toggle"
  love.graphics.setFont(UI.fonts.small)
  UI.label(text, 10, self.noteY, { 0.85, 0.85, 0.9 })
  love.graphics.setColor(1, 1, 1)
end

return SightCones
