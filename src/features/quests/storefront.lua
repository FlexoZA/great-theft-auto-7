-- The look the Jobs building and the shop beside it share: a storefront
-- facing the street its door is on. A roof with a parapet lit from the top
-- left like the city's own buildings, air conditioners with turning fans
-- and a skylight at the back, a glass front under a striped awning, and a
-- mat at the entrance. Each place adds its own things on top
-- (`Storefront.front` hands out a frame where the front is always down).
--
-- `b` is { x, y, w, h, doorX, doorY, nx, ny }, as quests/jobs.lua gives the
-- Jobs building and the shop; `style` is
-- { roof, rim, awning = { a, b }, glass } (colours).

local UI = require("src.ui")

local Storefront = {}

local AC = { 0.60, 0.62, 0.64 }
local AWNING = 18 -- px the awning hangs out over the sidewalk

local function shade(c, k)
  return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k), c[4] }
end

--- Run `fn(W, D, doorD)` in a frame centred on `b` and turned so the front
--- is at the bottom: x runs along the front (-W/2 .. W/2), y into the
--- building's depth (-D/2 at the back, D/2 at the front), and the door is
--- at (0, doorD).
function Storefront.front(b, fn)
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  local angle, W, D
  if b.ny ~= 0 then
    angle, W, D = b.ny > 0 and 0 or math.pi, b.w, b.h
  else
    angle, W, D = b.nx > 0 and -math.pi / 2 or math.pi / 2, b.h, b.w
  end
  local doorD = (b.doorX - cx) * b.nx + (b.doorY - cy) * b.ny
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(angle)
  fn(W, D, doorD)
  love.graphics.pop()
end

--- An air conditioner, a box with a fan turning in it, centred on (x, y).
local function aircon(x, y, t)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - 11 + 3, y - 11 + 3, 22, 22, 2)
  love.graphics.setColor(AC)
  love.graphics.rectangle("fill", x - 11, y - 11, 22, 22, 2)
  love.graphics.setColor(shade(AC, 0.55))
  love.graphics.circle("fill", x, y, 8)
  love.graphics.setColor(shade(AC, 1.3))
  love.graphics.setLineWidth(2)
  for i = 0, 2 do
    local a = t * 9 + i * 2 * math.pi / 3
    love.graphics.line(x, y, x + math.cos(a) * 7, y + math.sin(a) * 7)
  end
  love.graphics.setLineWidth(1)
end

--- The roof and front of `b` in `style`, at `time` seconds.
function Storefront.draw(b, style, time)
  -- The roof, lit from the top left the way the city draws its own.
  love.graphics.setColor(style.rim)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  love.graphics.setColor(style.roof)
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12)
  love.graphics.setColor(shade(style.roof, 1.25))
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, 6)
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, 6, b.h - 12)

  Storefront.front(b, function(W, D, doorD)
    local back, front = -D / 2, D / 2
    -- A skylight and two air conditioners along the back.
    local sw = math.min(W * 0.3, 70)
    love.graphics.setColor(shade(style.glass, 0.6))
    love.graphics.rectangle("fill", -sw / 2, back + 14, sw, 20, 2)
    love.graphics.setColor(style.glass[1], style.glass[2], style.glass[3], 0.5)
    for i = 0, 2 do
      love.graphics.rectangle("fill", -sw / 2 + 3 + i * (sw - 6) / 3, back + 17, (sw - 6) / 3 - 3, 14)
    end
    aircon(-W / 2 + 30, back + 30, time)
    aircon(W / 2 - 30, back + 30, time * 0.8 + 1)
    -- A pipe run from the units to the skylight.
    love.graphics.setColor(shade(AC, 0.8))
    love.graphics.setLineWidth(3)
    love.graphics.line(-W / 2 + 41, back + 30, -sw / 2 - 4, back + 30)
    love.graphics.line(W / 2 - 41, back + 30, sw / 2 + 4, back + 30)
    love.graphics.setLineWidth(1)

    -- The glass front, lit from inside.
    local glow = 0.75 + 0.1 * math.sin(time * 1.3)
    love.graphics.setColor(shade(style.glass, 0.5))
    love.graphics.rectangle("fill", -W / 2 + 6, front - 16, W - 12, 10)
    love.graphics.setColor(style.glass[1], style.glass[2], style.glass[3], glow)
    for x = -W / 2 + 10, W / 2 - 30, 24 do
      love.graphics.rectangle("fill", x, front - 14, 20, 6)
    end

    -- The awning over the sidewalk, stripes and a scalloped edge.
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", -W / 2 + 10, front + 4, W - 20, AWNING + 4)
    local n = math.max(4, math.floor((W - 20) / 16))
    local sw2 = (W - 20) / n
    for i = 0, n - 1 do
      love.graphics.setColor(i % 2 == 0 and style.awning[1] or style.awning[2])
      local x = -W / 2 + 10 + i * sw2
      love.graphics.rectangle("fill", x, front, sw2, AWNING)
      love.graphics.arc("fill", x + sw2 / 2, front + AWNING, sw2 / 2, 0, math.pi)
    end
    love.graphics.setColor(shade(style.awning[1], 0.6))
    love.graphics.setLineWidth(2)
    love.graphics.line(-W / 2 + 10, front, W / 2 - 10, front)
    love.graphics.setLineWidth(1)

    -- The path from the front to the door, and a mat at the step.
    local walk = doorD - front - AWNING - 6
    if walk > 4 then
      love.graphics.setColor(0.58, 0.58, 0.56)
      love.graphics.rectangle("fill", -22, front + AWNING + 6, 44, walk)
    end
    love.graphics.setColor(shade(style.awning[1], 0.5))
    love.graphics.rectangle("fill", -18, front + AWNING + 8, 36, 12, 3)
  end)
  love.graphics.setColor(1, 1, 1)
end

--- The roof left free between the units at the back and the glass at the
--- front, in the world: x, y, w, h. The emblem and the sign go here, one
--- over the other, level on the screen whichever way the front faces.
function Storefront.roofArea(b)
  local BACK, FRONT, SIDE = 46, 20, 10
  local l, t, r, d = SIDE, SIDE, SIDE, SIDE -- left, top, right, bottom insets
  if b.ny > 0 then
    t, d = BACK, FRONT
  elseif b.ny < 0 then
    t, d = FRONT, BACK
  elseif b.nx > 0 then
    l, r = BACK, FRONT
  else
    l, r = FRONT, BACK
  end
  return b.x + l, b.y + t, b.w - l - r, b.h - t - d
end

--- Where the place's emblem goes and how big it can be: x, y, radius.
function Storefront.emblem(b, most)
  local x, y, w, h = Storefront.roofArea(b)
  return x + w / 2, y + h * 0.36, math.min(w * 0.4, h * 0.3, most)
end

--- The place's name under its emblem, on a dark plate.
function Storefront.sign(b, text, color, font)
  font = font or UI.fonts.heading
  local ax, ay, aw, ah = Storefront.roofArea(b)
  local tw, th = font:getWidth(text) + 20, font:getHeight() + 4
  local x, y = ax + (aw - tw) / 2, ay + ah * 0.8 - th / 2
  love.graphics.setColor(0.06, 0.06, 0.08, 0.85)
  love.graphics.rectangle("fill", x, y, tw, th, 5)
  love.graphics.setColor(color[1], color[2], color[3], 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x, y, tw, th, 5)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(font)
  love.graphics.setColor(color)
  love.graphics.printf(text, x, y + 2, tw, "center")
  love.graphics.setColor(1, 1, 1)
end

--- Where (along, depth) of `Storefront.front`'s frame is in the world.
function Storefront.at(b, along, depth)
  return b.x + b.w / 2 + b.ny * along + b.nx * depth, b.y + b.h / 2 - b.nx * along + b.ny * depth
end

--- How deep `b` is from its front to its back.
function Storefront.depth(b)
  return b.ny ~= 0 and b.h or b.w
end

--- How wide `b`'s front is.
function Storefront.width(b)
  return b.ny ~= 0 and b.w or b.h
end

--- Where the sidewalk starts in front of the awning, in the frame: the
--- depth to put things standing outside.
function Storefront.outside(D)
  return D / 2 + AWNING + 16
end

--- A potted plant, round and leafy, centred on (x, y).
function Storefront.plant(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 3, y + 3, 10)
  love.graphics.setColor(0.55, 0.32, 0.2)
  love.graphics.circle("fill", x, y, 10)
  love.graphics.setColor(0.22, 0.5, 0.25)
  for i = 0, 4 do
    local a = i * 2 * math.pi / 5
    love.graphics.circle("fill", x + math.cos(a) * 5, y + math.sin(a) * 5, 5)
  end
  love.graphics.setColor(0.32, 0.64, 0.33)
  love.graphics.circle("fill", x - 1, y - 1, 4)
end

return Storefront
