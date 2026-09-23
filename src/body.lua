-- A player's body: where they are when they are not behind a wheel, and
-- what everyone sees of them then. The server keeps one per player in
-- `player.body` from the moment the game starts; while the player drives,
-- the body rides along inside the vehicle and is not drawn. `dead` is set
-- by whatever kills them (weapons) until they respawn.
--
-- Drawing is two circles and a barrel in the player's colour, the same
-- figure the crowd and the officers use, so a player on foot reads as a
-- person in the street.

local Body = {}
Body.__index = Body

Body.RADIUS = 7 -- px; how fat a player is against walls and bullets
Body.DRAW_RADIUS = 6 -- px, the body circle
Body.HEAD = 3.5
Body.GUN = 9 -- px the barrel sticks out past the body
Body.SKIN = { 0.92, 0.78, 0.63 }

function Body.new(x, y, facing)
  return setmetatable({
    x = x or 0,
    y = y or 0,
    facing = facing or 0, -- radians, the way they look
    dead = false,
  }, Body)
end

--- Is the point (px, py), padded by `radius`, on this body? Works on any
--- table with x, y (server bodies and client snapshots alike).
function Body.hitTest(body, px, py, radius)
  local r = Body.RADIUS + (radius or 0)
  return (px - body.x) ^ 2 + (py - body.y) ^ 2 <= r * r
end

--- Draw a figure at (x, y) looking along `angle`. `swing` is the sideways
--- waddle for this frame (px), `sprinting` swaps the stroll for a run.
function Body.draw(x, y, angle, color, swing)
  local fx, fy = math.cos(angle), math.sin(angle)
  swing = swing or 0
  local sx, sy = -fy * swing, fx * swing
  local r = Body.DRAW_RADIUS
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(color)
  love.graphics.circle("fill", x + sx, y + sy, r, 10)
  love.graphics.setColor(0.12, 0.12, 0.15)
  love.graphics.setLineWidth(2)
  love.graphics.line(x + fx * r, y + fy * r, x + fx * (r + Body.GUN), y + fy * (r + Body.GUN))
  love.graphics.setLineWidth(1)
  love.graphics.setColor(Body.SKIN)
  love.graphics.circle("fill", x + fx * 1.6 + sx * 0.5, y + fy * 1.6 + sy * 0.5, Body.HEAD, 8)
  love.graphics.setColor(1, 1, 1)
end

return Body
