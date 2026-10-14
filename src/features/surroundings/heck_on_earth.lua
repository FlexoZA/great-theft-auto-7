-- The city past Heck on Earth's edge (surroundings' entry for `earth`):
-- more of the same city, blocks of roofs between dark streets, running on
-- out of reach, a good few of them burning, and smoke drifting over it.
-- Worked out from the cell it sits on, the same on every machine, and drawn
-- each frame over what the camera sees, skipping the map itself (its
-- canvas lands on top). At night (`lights`) the fires glow.

local HeckOnEarth = {}

local CELL = 320 -- px: a block and its half of the street round it
local STREET = 56 -- px of street between two blocks

-- The map's roofs' colours, with the same red cast (render_eternal_mood.lua's `evil`).
local C = {
  street = { 0.27, 0.13, 0.11 },
  roofs = { { 0.45, 0.25, 0.22 }, { 0.38, 0.21, 0.19 }, { 0.58, 0.20, 0.15 }, { 0.32, 0.18, 0.16 } },
  parapet = { 0.60, 0.35, 0.32 },
  char = { 0.12, 0.05, 0.04 },
  smoke = { 0.10, 0.06, 0.06 },
}
local FIRE = { 1.00, 0.45, 0.10 }

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local function onMap(map, x, y)
  return x >= map.left and x + CELL <= map.left + map.w and y >= map.top and y + CELL <= map.top + map.h
end

--- Each block past the map in the box, with its own `seed`.
local function eachBlock(map, left, top, right, bottom, fn)
  for c = math.floor(left / CELL), math.ceil(right / CELL) do
    for r = math.floor(top / CELL), math.ceil(bottom / CELL) do
      local x, y = c * CELL, r * CELL
      if not onMap(map, x, y) then
        fn(x, y, hash(c * 7.31 + r * 17.17))
      end
    end
  end
end

--- Draw the city over the box (left, top, right, bottom), world px, at `t`.
function HeckOnEarth.draw(map, left, top, right, bottom, t)
  eachBlock(map, left, top, right, bottom, function(x, y, h)
    love.graphics.setColor(C.street)
    love.graphics.rectangle("fill", x, y, CELL, CELL)
    local bx, by, bw = x + STREET / 2, y + STREET / 2, CELL - STREET
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", bx + 10, by + 14, bw, bw)
    love.graphics.setColor(C.parapet)
    love.graphics.rectangle("fill", bx, by, bw, bw)
    love.graphics.setColor(C.roofs[math.floor(h * #C.roofs) + 1])
    love.graphics.rectangle("fill", bx + 8, by + 8, bw - 16, bw - 16)
    if h > 0.62 then -- burning: the roof charred and flames on it
      love.graphics.setColor(C.char)
      love.graphics.circle("fill", bx + bw * 0.5, by + bw * 0.5, bw * 0.3, 16)
      love.graphics.setBlendMode("add")
      for k = 0, 4 do
        local phase = (t * (1.1 + hash(h + k) * 0.8) + hash(h * 3 + k)) % 1
        local fx = bx + bw * (0.3 + hash(h * 5 + k) * 0.4)
        local fy = by + bw * (0.3 + hash(h * 7 + k) * 0.4) - phase * 30
        love.graphics.setColor(1, 0.4 + 0.3 * (1 - phase), 0.06, 0.5 * (1 - phase))
        love.graphics.ellipse("fill", fx, fy, 20 * (1 - phase * 0.6), 30 * (1 - phase * 0.6), 10)
      end
      love.graphics.setBlendMode("alpha")
    end
  end)
  -- Smoke drifting east over the whole of it.
  for k = 0, 11 do
    local span = right - left + 800
    local sx = left - 400 + ((hash(k * 3.3) * span + t * (20 + k * 2)) % span)
    local sy = top + hash(k * 5.9) * (bottom - top)
    love.graphics.setColor(C.smoke[1], C.smoke[2], C.smoke[3], 0.25)
    love.graphics.circle("fill", sx, sy, 90 + hash(k) * 80, 20)
  end
end

--- The burning blocks' fires, glowing in the dark.
function HeckOnEarth.lights(map, left, top, right, bottom, t, glow)
  eachBlock(map, left - 300, top - 300, right + 300, bottom + 300, function(x, y, h)
    if h > 0.62 then
      local flick = 0.7 + 0.3 * love.math.noise(t * 3, h * 50)
      glow(x + CELL / 2, y + CELL / 2, 260, FIRE, 0.6 * flick)
    end
  end)
end

return HeckOnEarth
