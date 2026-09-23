-- Great Theft Auto 7 — entry point.
-- Forwards LÖVE callbacks to the current state (see src/state.lua).

local State = require("src.state")
local Net = require("src.net")
local Features = require("src.features")
local Video = require("src.video")

function love.load()
  Video.apply() -- saved display mode, size and vsync
  love.graphics.setBackgroundColor(0.16, 0.16, 0.18)
  love.graphics.setDefaultFilter("nearest", "nearest")
  love.keyboard.setKeyRepeat(true)
  Features.load()
  print("features: " .. Features.names())
  State.switch("menu")
end

function love.update(dt)
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
