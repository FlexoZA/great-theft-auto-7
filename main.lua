-- Great Theft Auto 7 — entry point.
-- Forwards LÖVE callbacks to the current state (see src/state.lua).

if not love.window then
  require("src.dedicated") -- headless dedicated server (GTA7_SERVER=1, see conf.lua)
  return
end

local State = require("src.state")
local Net = require("src.net")
local Features = require("src.features")
local Video = require("src.video")
local Launch = require("src.launch")

function love.load(args)
  Video.apply() -- saved display mode, size and vsync
  love.graphics.setBackgroundColor(0.16, 0.16, 0.18)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.keyboard.setKeyRepeat(true)
  Features.load()
  print("features: " .. Features.names())
  if not Launch.start(args) then -- `love . --world <slug>` skips the menus (src/launch.lua)
    State.switch("menu")
  end
end

function love.update(dt)
  Launch.update()
  local s = State.current
  if s and s.update then
    s:update(dt)
  end
end

function love.draw()
  local s = State.current
  if s and s.draw then
    s:draw()
  end
end

function love.keypressed(key)
  local s = State.current
  if s and s.keypressed then
    s:keypressed(key)
  end
end

function love.textinput(t)
  local s = State.current
  if s and s.textinput then
    s:textinput(t)
  end
end

function love.mousepressed(x, y, button)
  local s = State.current
  if s and s.mousepressed then
    s:mousepressed(x, y, button)
  end
end

function love.wheelmoved(dx, dy)
  local s = State.current
  if s and s.wheelmoved then
    s:wheelmoved(dx, dy)
  end
end

function love.quit()
  Net.shutdown()
end
