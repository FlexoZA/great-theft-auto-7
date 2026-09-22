-- Video settings: display mode, window size and vsync, persisted through
-- src/settings.lua and applied with love.window.setMode. Also home to the
-- small display toggles other code reads (show FPS, screen shake, scanlines).

local Settings = require("src.settings")

local Video = {}

Video.SIZES = {
  { 1024, 576 },
  { 1280, 720 },
  { 1366, 768 },
  { 1600, 900 },
  { 1920, 1080 },
  { 2560, 1440 },
}

Video.DEFAULTS = {
  fullscreen = false,
  width = 1280,
  height = 720,
  vsync = true,
  showFps = true,
  screenShake = true,
  scanlines = true,
}

function Video.get(key)
  return Settings.get("video." .. key, Video.DEFAULTS[key])
end

function Video.set(key, value)
  Settings.set("video." .. key, value)
  if key == "fullscreen" or key == "width" or key == "height" or key == "vsync" then
    Video.apply()
  end
end

function Video.reset()
  for k, v in pairs(Video.DEFAULTS) do
    Settings.set("video." .. k, v)
  end
  Video.apply()
end

--- Index into SIZES of the saved window size (nearest if it isn't listed).
function Video.sizeIndex()
  local w = Video.get("width")
  local best, bestD = 2, math.huge
  for i, s in ipairs(Video.SIZES) do
    local d = math.abs(s[1] - w)
    if d < bestD then
      best, bestD = i, d
    end
  end
  return best
end

--- Push the saved settings to the window. Skips setMode when nothing would
--- change, so calling it at startup is free when the defaults are in use.
function Video.apply()
  if not love.window then
    return
  end
  local fullscreen = Video.get("fullscreen")
  local w, h = Video.get("width"), Video.get("height")
  local vsync = Video.get("vsync") and 1 or 0

  local cw, ch, flags = love.window.getMode()
  local sameMode = flags.fullscreen == fullscreen and (fullscreen or (cw == w and ch == h))
  if sameMode then
    if flags.vsync ~= vsync and love.window.setVSync then
      love.window.setVSync(vsync)
    end
    return
  end
  love.window.setMode(w, h, {
    fullscreen = fullscreen,
    fullscreentype = "desktop",
    vsync = vsync,
    resizable = true,
    minwidth = 640,
    minheight = 360,
  })
end

return Video
