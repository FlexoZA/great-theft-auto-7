-- Draws the background grid. Also the smallest real example of a feature.

local Grid = {
  name = "grid",
  priority = 10, -- draw early so everything else lands on top
  size = 128,
}

function Grid:drawBelowCars(_client, camera)
  love.graphics.setColor(0.25, 0.25, 0.28)
  local w, h = love.graphics.getDimensions()
  local x0 = math.floor((camera.x - w) / self.size) * self.size
  local y0 = math.floor((camera.y - h) / self.size) * self.size
  for x = x0, camera.x + w, self.size do
    love.graphics.line(x, camera.y - h, x, camera.y + h)
  end
  for y = y0, camera.y + h, self.size do
    love.graphics.line(camera.x - w, y, camera.x + w, y)
  end
  love.graphics.setColor(1, 1, 1)
end

return Grid
