function love.conf(t)
  t.identity = "great-theft-auto-7" -- save directory name
  t.version = "11.5"               -- LÖVE version this game was made for
  t.console = false

  t.window.title = "Great Theft Auto 7"
  t.window.width = 1280
  t.window.height = 720
  t.window.resizable = true
  t.window.minwidth = 640
  t.window.minheight = 360
  t.window.vsync = 1

  t.modules.joystick = true
  t.modules.physics = true
end
