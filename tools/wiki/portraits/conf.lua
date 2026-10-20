-- The portrait run's window (tools/wiki/portraits.lua): small and out of the way.
function love.conf(t)
  t.identity = "great-theft-auto-7-wiki"
  t.version = "11.5"
  t.window.title = "Great Theft Auto 7 wiki portraits"
  t.window.width = 640
  t.window.height = 360
  t.window.vsync = 0
  t.modules.audio = false
  t.modules.sound = true
  t.modules.joystick = false
end
