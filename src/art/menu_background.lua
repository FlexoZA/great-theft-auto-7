-- Animated menu backdrop: slowly rotating rays behind the face, the face
-- itself, and CRT scanlines over everything.

local Face = require("src.art.face")

local Background = {}
Background.__index = Background

local RAYS = 18
local RAY_SPEED = 0.12 -- rad/s

function Background.new()
  return setmetatable({ face = Face.new(), t = 0 }, Background)
end

function Background:update(dt)
  self.t = self.t + dt
  self.face:update(dt)
end

--- faceX, faceY: where the face is centred. faceScale: pixels per art pixel.
function Background:draw(faceX, faceY, faceScale)
  local w, h = love.graphics.getDimensions()
  local radius = math.sqrt(w * w + h * h)

  -- Rays.
  local a0 = self.t * RAY_SPEED
  for i = 0, RAYS - 1 do
    if i % 2 == 0 then
      local a1 = a0 + i / RAYS * 2 * math.pi
      local a2 = a0 + (i + 1) / RAYS * 2 * math.pi
      love.graphics.setColor(0.20, 0.07, 0.10)
      love.graphics.polygon("fill", faceX, faceY,
        faceX + math.cos(a1) * radius, faceY + math.sin(a1) * radius,
        faceX + math.cos(a2) * radius, faceY + math.sin(a2) * radius)
    end
  end

  -- Soft dark halo so the face pops off the rays.
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", faceX, faceY, faceScale * 40)

  self.face:draw(faceX, faceY, faceScale)

  -- Scanlines.
  love.graphics.setColor(0, 0, 0, 0.18)
  for y = 0, h, 4 do
    love.graphics.rectangle("fill", 0, y, w, 1)
  end
  love.graphics.setColor(1, 1, 1)
end

return Background
