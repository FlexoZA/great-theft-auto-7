-- Player arrows: while another player is off screen, a small arrow sits on the
-- edge of the window pointing at them, wherever they are: their car or their
-- feet. The arrow carries that player's colour and fades out the further
-- away they are, so a distant player is a faint hint and a near one is hard
-- to miss. Your own cars get an arrow too while you are not in them, drawn
-- hollow in your colour, so a car you left (or lost) is never lost for good.
--
-- Purely local: it only reads the snapshots the client already has, sends
-- nothing and has no server hooks. Delete the folder (or set
-- Arrows.enabled = false) to switch it off.

local Car = require("src.car")

local Arrows = {
  name = "player-arrows",
  priority = 500, -- after the camera has moved, under the vision cursor
}

Arrows.enabled = true

-- Tuning.
Arrows.margin = 28 -- px from the window edge the arrow tip sits at
Arrows.size = 11 -- arrow length in px, tip to base
Arrows.slack = 0.6 -- car half-sizes a car may leave the screen before it counts as gone
Arrows.fadeStart = 900 -- world px: closer than this the arrow is at full strength
Arrows.fadeEnd = 5000 -- world px: at or beyond this it is at minAlpha
Arrows.maxAlpha = 0.9
Arrows.minAlpha = 0.15
Arrows.ownCars = true -- point at my own cars as well as at other players

--- Alpha for a player `dist` world px away, easing between the two distances.
function Arrows:alphaFor(dist)
  local span = self.fadeEnd - self.fadeStart
  local t = span > 0 and (dist - self.fadeStart) / span or 1
  t = math.max(0, math.min(t, 1))
  return self.maxAlpha + (self.minAlpha - self.maxAlpha) * t
end

--- The camera is only handed to update/world draws, so keep a reference to it
--- for drawHUD. It is the same table every frame, already moved by any feature
--- that steers the view.
function Arrows:update(_dt, _client, camera)
  self.camera = camera
end

function Arrows:exitGame()
  self.camera = nil
end

--- An arrow at (x, y) pointing along `angle`; `hollow` draws just its
--- outline (an arrow to a thing rather than a player).
local function drawArrow(x, y, angle, color, alpha, hollow)
  local size = Arrows.size
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  -- A darker triangle behind the coloured one keeps it readable on any map.
  love.graphics.setColor(0, 0, 0, alpha * 0.55)
  love.graphics.polygon("fill", size * 1.35, 0, -size * 0.75, size * 0.9, -size * 0.75, -size * 0.9)
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  if hollow then
    love.graphics.setLineWidth(2)
    love.graphics.polygon("line", size, 0, -size * 0.6, size * 0.62, -size * 0.6, -size * 0.62)
    love.graphics.setLineWidth(1)
  else
    love.graphics.polygon("fill", size, 0, -size * 0.6, size * 0.62, -size * 0.6, -size * 0.62)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

function Arrows:drawHUD(client)
  local camera = self.camera
  if not self.enabled or not camera or not client then
    return
  end
  local meX, meY = client:myPose()
  if not meX then
    return
  end

  local w, h = love.graphics.getDimensions()
  local cx, cy = w / 2, h / 2
  local scale = camera.scale or 1
  -- How far past an edge a car's centre may sit while part of it is still visible.
  local slackX = Car.WIDTH * self.slack * scale
  local slackY = Car.HEIGHT * self.slack * scale
  -- The rectangle the arrow tips ride on.
  local halfW = math.max(cx - self.margin, 1)
  local halfH = math.max(cy - self.margin, 1)

  --- An arrow on the edge towards world point (px, py), if it is off screen.
  local function pointAt(px, py, color, hollow)
    local sx = (px - camera.x) * scale + cx
    local sy = (py - camera.y) * scale + cy
    local offScreen = sx < -slackX or sx > w + slackX or sy < -slackY or sy > h + slackY
    if offScreen then
      local dx, dy = sx - cx, sy - cy
      -- Push the direction out to whichever edge it meets first.
      local t = math.min(halfW / math.max(math.abs(dx), 0.001), halfH / math.max(math.abs(dy), 0.001))
      local wx, wy = px - meX, py - meY
      local alpha = self:alphaFor(math.sqrt(wx * wx + wy * wy))
      drawArrow(cx + dx * t, cy + dy * t, math.atan2(dy, dx), color, alpha, hollow)
    end
  end

  for id in pairs(client.players) do
    local px, py = client:pose(id)
    if id ~= client.myId and px then
      pointAt(px, py, Car.colorFor(id), false)
    end
  end
  if self.ownCars then
    for _, v in pairs(client.vehicles) do
      if v.owner == client.myId and v.driver ~= client.myId then
        pointAt(v.dx, v.dy, Car.colorFor(client.myId), true)
      end
    end
  end
end

return Arrows
