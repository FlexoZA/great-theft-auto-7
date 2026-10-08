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

--- A scope's crosshair, for a gun with a scope (the sniper rifle): a black
--- ring with black lines through it from edge to edge, a white halo under
--- it so it reads on dark ground too.
function Cursors.scope(x, y)
  local r = 16
  for pass = 1, 2 do
    if pass == 1 then
      love.graphics.setColor(1, 1, 1, 0.45)
      love.graphics.setLineWidth(5)
    else
      love.graphics.setColor(0, 0, 0, 0.95)
      love.graphics.setLineWidth(2)
    end
    love.graphics.circle("line", x, y, r, 32)
    love.graphics.line(x - r, y, x + r, y)
    love.graphics.line(x, y - r, x, y + r)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- A plain pointer, for screens where the mouse picks things up.
function Cursors.arrow(x, y)
  local shape = { x, y, x, y + 17, x + 4, y + 13, x + 7, y + 19, x + 10, y + 18, x + 7, y + 12, x + 12, y + 12 }
  love.graphics.setColor(0.1, 0.1, 0.12, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.polygon("line", shape)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
  for _, tri in ipairs(love.math.triangulate(shape)) do
    love.graphics.polygon("fill", tri)
  end
end

return Cursors
