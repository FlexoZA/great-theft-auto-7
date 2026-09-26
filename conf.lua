function love.conf(t)
  -- GTA7_SERVER=1: a dedicated server (docs/dedicated-server.md). No window, no
  -- sound, its own save directory; main.lua sees love.window == nil and runs it.
  if os.getenv("GTA7_SERVER") then
    t.identity = "great-theft-auto-7-server"
    t.window = nil
    local off = {
      "window", "graphics", "audio", "sound", "image", "font", "video",
      "joystick", "keyboard", "mouse", "touch", "physics",
    }
    for _, m in ipairs(off) do
      t.modules[m] = false
    end
    return
  end

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
