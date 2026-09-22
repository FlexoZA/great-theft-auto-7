-- Cursor styles for the vision feature. Each one draws in screen space at the
-- mouse position. Add another here and select it with Vision.cursor = "name".

local Cursors = {}

function Cursors.target(x, y)
  local r = 12
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.circle("line", x, y, r)
  love.graphics.line(x - r - 7, y, x - 4, y)
  love.graphics.line(x + 4, y, x + r + 7, y)
  love.graphics.line(x, y - r - 7, x, y - 4)
  love.graphics.line(x, y + 4, x, y + r + 7)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Cursors
