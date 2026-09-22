-- Vision: a cursor that stays inside the window, plus an edge-scrolling camera.
--
-- Self-contained feature. Set Vision.enabled = false below (or delete the five
-- Vision.* calls in main.lua) to switch it off without touching anything else:
-- the offsets stay at 0 and the zoom at 1, so the camera behaves as before.

local Vision = {}

Vision.enabled = true

-- Tuning.
Vision.edgeMargin = 64 -- px from a screen edge where panning starts
Vision.panSpeed = 900 -- world px/s when the cursor is hard against the edge
Vision.maxDistance = 700 -- how far the camera may drift from the player
Vision.minZoom = 0.65 -- zoom once the camera is a full maxDistance away
Vision.zoomRate = 4 -- how quickly the zoom follows that distance
Vision.recenterRate = 9 -- how quickly the recentre key snaps back to the player
Vision.recenterKey = "c"

-- Camera state; main.lua reads these after Vision.update.
Vision.offsetX = 0
Vision.offsetY = 0
Vision.zoom = 1

local recentering = false

-- Cursor styles. Add another with Vision.cursors.name = function(x, y) ... end
-- and select it with Vision.cursor = "name".
Vision.cursors = {}

function Vision.cursors.target(x, y)
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

Vision.cursor = "target"

function Vision.load()
  if not Vision.enabled then
    return
  end
  love.mouse.setGrabbed(true)
  love.mouse.setVisible(false)
  local w, h = love.graphics.getDimensions()
  love.mouse.setPosition(w / 2, h / 2)
end

-- How hard the cursor pushes each axis, -1..1, 0 when it is away from an edge.
local function edgePush()
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local m = Vision.edgeMargin
  local dx, dy = 0, 0
  if mx < m then
    dx = -(m - mx) / m
  elseif mx > w - m then
    dx = (mx - (w - m)) / m
  end
  if my < m then
    dy = -(m - my) / m
  elseif my > h - m then
    dy = (my - (h - m)) / m
  end
  return math.max(-1, math.min(dx, 1)), math.max(-1, math.min(dy, 1))
end

function Vision.update(dt)
  if not Vision.enabled then
    return
  end

  local dx, dy = edgePush()
  if dx ~= 0 or dy ~= 0 then
    recentering = false
  end

  if recentering then
    local t = math.min(Vision.recenterRate * dt, 1)
    Vision.offsetX = Vision.offsetX - Vision.offsetX * t
    Vision.offsetY = Vision.offsetY - Vision.offsetY * t
    if math.abs(Vision.offsetX) < 1 and math.abs(Vision.offsetY) < 1 then
      Vision.offsetX, Vision.offsetY = 0, 0
      recentering = false
    end
  else
    Vision.offsetX = Vision.offsetX + dx * Vision.panSpeed * dt
    Vision.offsetY = Vision.offsetY + dy * Vision.panSpeed * dt
  end

  -- Keep the camera inside a circle around the player.
  local dist = math.sqrt(Vision.offsetX * Vision.offsetX + Vision.offsetY * Vision.offsetY)
  if dist > Vision.maxDistance then
    local scale = Vision.maxDistance / dist
    Vision.offsetX = Vision.offsetX * scale
    Vision.offsetY = Vision.offsetY * scale
    dist = Vision.maxDistance
  end

  -- Zoom out in step with that distance, easing so it never snaps.
  local target = 1 + (Vision.minZoom - 1) * (dist / Vision.maxDistance)
  Vision.zoom = Vision.zoom + (target - Vision.zoom) * math.min(Vision.zoomRate * dt, 1)
end

function Vision.keypressed(key)
  if Vision.enabled and key == Vision.recenterKey then
    recentering = true
  end
end

function Vision.draw()
  if not Vision.enabled then
    return
  end
  local cursor = Vision.cursors[Vision.cursor]
  if cursor then
    cursor(love.mouse.getPosition())
  end
end

return Vision
