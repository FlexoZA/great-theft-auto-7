-- Vision: a cursor that stays inside the window, plus an edge-scrolling camera.
--
-- Purely local: it never touches the world, so it sends nothing to the server
-- and has no server hooks. It moves the camera the game state hands it in
-- `update` and draws its own cursor in `drawHUD`. Delete the folder (or set
-- Vision.enabled = false) to switch it off: the camera then sits on the
-- player at scale 1, exactly as before.

local Cursors = require("src.features.vision.cursors")
local Controls = require("src.controls")

local Vision = {
  name = "vision",
  priority = 900, -- update last so the camera is final; draw the cursor on top
}

Vision.enabled = true

-- Tuning.
Vision.edgeMargin = 64 -- px from a screen edge where panning starts
Vision.panSpeed = 900 -- world px/s when the cursor is hard against the edge
Vision.maxDistance = 700 -- how far the camera may drift from the player
Vision.minZoom = 0.65 -- zoom once the camera is a full maxDistance away
Vision.zoomRate = 4 -- how quickly the zoom follows that distance
Vision.recenterRate = 9 -- how quickly the recentre key snaps back to the player
Vision.recenterKey = "c" -- default binding of the "recentre" action (rebind in Settings)

-- Camera state, in world px from the player.
Vision.offsetX = 0
Vision.offsetY = 0
Vision.zoom = 1

Vision.cursors = Cursors
Vision.cursor = "target"

local recentering = false

function Vision:load()
  Controls.register("recentre", "Recentre camera", self.recenterKey)
end

--- Grab the mouse while driving; the menus need a normal cursor.
function Vision:enterGame()
  if not self.enabled then
    return
  end
  love.mouse.setGrabbed(true)
  love.mouse.setVisible(false)
  local w, h = love.graphics.getDimensions()
  love.mouse.setPosition(w / 2, h / 2)
end

function Vision:exitGame()
  love.mouse.setGrabbed(false)
  love.mouse.setVisible(true)
  self.offsetX, self.offsetY, self.zoom = 0, 0, 1
  recentering = false
end

-- How hard the cursor pushes each axis, -1..1, 0 when it is away from an edge.
local function edgePush(margin)
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local dx, dy = 0, 0
  if mx < margin then
    dx = -(margin - mx) / margin
  elseif mx > w - margin then
    dx = (mx - (w - margin)) / margin
  end
  if my < margin then
    dy = -(margin - my) / margin
  elseif my > h - margin then
    dy = (my - (h - margin)) / margin
  end
  return math.max(-1, math.min(dx, 1)), math.max(-1, math.min(dy, 1))
end

function Vision:update(dt, _client, camera)
  if not self.enabled then
    return
  end

  local dx, dy = edgePush(self.edgeMargin)
  if dx ~= 0 or dy ~= 0 then
    recentering = false
  end

  if recentering then
    local t = math.min(self.recenterRate * dt, 1)
    self.offsetX = self.offsetX - self.offsetX * t
    self.offsetY = self.offsetY - self.offsetY * t
    if math.abs(self.offsetX) < 1 and math.abs(self.offsetY) < 1 then
      self.offsetX, self.offsetY = 0, 0
      recentering = false
    end
  else
    self.offsetX = self.offsetX + dx * self.panSpeed * dt
    self.offsetY = self.offsetY + dy * self.panSpeed * dt
  end

  -- Keep the camera inside a circle around the player.
  local dist = math.sqrt(self.offsetX * self.offsetX + self.offsetY * self.offsetY)
  if dist > self.maxDistance then
    local scale = self.maxDistance / dist
    self.offsetX = self.offsetX * scale
    self.offsetY = self.offsetY * scale
    dist = self.maxDistance
  end

  -- Zoom out in step with that distance, easing so it never snaps.
  local target = 1 + (self.minZoom - 1) * (dist / self.maxDistance)
  self.zoom = self.zoom + (target - self.zoom) * math.min(self.zoomRate * dt, 1)

  camera.x = camera.x + self.offsetX
  camera.y = camera.y + self.offsetY
  camera.scale = self.zoom
end

function Vision:keypressed(key)
  if self.enabled and Controls.is("recentre", key) then
    recentering = true
  end
end

function Vision:drawHUD()
  if not self.enabled then
    return
  end
  local cursor = self.cursors[self.cursor]
  if cursor then
    cursor(love.mouse.getPosition())
  end
end

return Vision
