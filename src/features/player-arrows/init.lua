-- Player arrows: while something worth finding is off screen, a marker sits
-- on the edge of the window towards it, in its owner's colour, fading the
-- further away it is, so a distant one is a faint hint and a near one is
-- hard to miss:
--   another player   a little walker (their car or their feet, wherever they are)
--   a police unit    an arrow, police blue whoever the unit is
--   your own car     a little car, while you are not in it, so a car you left
--                    (or lost) is never lost for good
-- Civilian bots get nothing: they are scenery.
--
-- Purely local: it only reads the snapshots the client already has, sends
-- nothing and has no server hooks. Delete the folder (or set
-- Arrows.enabled = false) to switch it off.

local Car = require("src.car")
local Body = require("src.body")
local Features = require("src.features")

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
Arrows.ownCars = true -- mark my own cars as well as other players
Arrows.policeColor = { 0.25, 0.45, 1 } -- the blue of a patrol car's light bar
Arrows.carScale = 0.5 -- the car marker, as a fraction of a car on the ground at scale 1
Arrows.walkerScale = 1.6 -- the walker marker, as a multiple of a walker on the ground

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

--- An arrow at (x, y) pointing along `angle`.
local function drawArrow(x, y, angle, color, alpha)
  local size = Arrows.size
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  -- A darker triangle behind the coloured one keeps it readable on any map.
  love.graphics.setColor(0, 0, 0, alpha * 0.55)
  love.graphics.polygon("fill", size * 1.35, 0, -size * 0.75, size * 0.9, -size * 0.75, -size * 0.9)
  love.graphics.setColor(color[1], color[2], color[3], alpha)
  love.graphics.polygon("fill", size, 0, -size * 0.6, size * 0.62, -size * 0.6, -size * 0.62)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- A dark disc behind a marker, so it reads on any map.
local function backing(x, y, r, alpha)
  love.graphics.setColor(0, 0, 0, alpha * 0.55)
  love.graphics.circle("fill", x, y, r, 24)
end

--- A little walker at (x, y) facing `angle`: another player.
local function drawWalker(x, y, angle, color, alpha)
  local s = Arrows.walkerScale
  backing(x, y, Body.RADIUS * s + 4, alpha)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(s)
  Body.draw(0, 0, angle, { color[1], color[2], color[3], alpha }, 0)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- A little car at (x, y) heading along `angle`: one of mine.
local function drawCar(x, y, angle, color, alpha)
  local s = Arrows.carScale
  backing(x, y, Car.WIDTH * s * 0.6 + 4, alpha)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(s)
  Car.draw(0, 0, angle, { color[1], color[2], color[3], alpha })
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

local DRAW = { arrow = drawArrow, walker = drawWalker, car = drawCar }

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

  --- A marker of `kind` on the edge towards world point (px, py), if it is off screen.
  local function pointAt(px, py, color, kind)
    local sx = (px - camera.x) * scale + cx
    local sy = (py - camera.y) * scale + cy
    local offScreen = sx < -slackX or sx > w + slackX or sy < -slackY or sy > h + slackY
    if offScreen then
      local dx, dy = sx - cx, sy - cy
      -- Push the direction out to whichever edge it meets first.
      local t = math.min(halfW / math.max(math.abs(dx), 0.001), halfH / math.max(math.abs(dy), 0.001))
      local wx, wy = px - meX, py - meY
      local alpha = self:alphaFor(math.sqrt(wx * wx + wy * wy))
      DRAW[kind](cx + dx * t, cy + dy * t, math.atan2(dy, dx), color, alpha)
    end
  end

  local bots, police = Features.byName.bots, Features.byName.police
  for id in pairs(client.players) do
    local px, py = client:pose(id)
    if id ~= client.myId and px and not (bots and bots.ids[id]) then
      local unit = police and police.units[id]
      if unit then
        pointAt(px, py, self.policeColor, "arrow")
      else
        pointAt(px, py, Car.colorFor(id), "walker")
      end
    end
  end
  if self.ownCars then
    for _, v in pairs(client.vehicles) do
      if v.owner == client.myId and v.driver ~= client.myId then
        pointAt(v.dx, v.dy, Car.colorFor(client.myId), "car")
      end
    end
  end
end

return Arrows
