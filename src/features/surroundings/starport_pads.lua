-- The starport round the Foundry (surroundings' entry for `foundry`): dark
-- tarmac running on past the shed's walls, landing pads with their rings
-- and numbers here and there, rows of runway lights, a parked shuttle now
-- and then, all with the red cast of everything in this dream. Worked out
-- from the cell it sits on, the same on every machine, and drawn each frame
-- over what the camera sees, skipping the map itself (its canvas lands on
-- top). At night (`lights`) the runway lights blink.

local StarportPads = {}

local CELL = 384 -- px: a pad's stand, or plain tarmac

local C = {
  tarmac = { 0.19, 0.10, 0.09 },
  tarmacDark = { 0.15, 0.08, 0.07 },
  paint = { 0.80, 0.55, 0.20 },
  pad = { 0.24, 0.13, 0.11 },
  shuttle = { 0.42, 0.30, 0.28 },
  shuttleDark = { 0.28, 0.18, 0.17 },
}
local LIGHT = { 1.00, 0.55, 0.25 }

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local function onMap(map, x, y)
  return x >= map.left and x + CELL <= map.left + map.w and y >= map.top and y + CELL <= map.top + map.h
end

local function each(map, left, top, right, bottom, fn)
  for c = math.floor(left / CELL), math.ceil(right / CELL) do
    for r = math.floor(top / CELL), math.ceil(bottom / CELL) do
      local x, y = c * CELL, r * CELL
      if not onMap(map, x, y) then
        fn(x, y, hash(c * 5.17 + r * 11.31), c, r)
      end
    end
  end
end

function StarportPads.draw(map, left, top, right, bottom)
  each(map, left, top, right, bottom, function(x, y, h, c)
    love.graphics.setColor(h < 0.5 and C.tarmac or C.tarmacDark)
    love.graphics.rectangle("fill", x, y, CELL, CELL)
    local cx, cy = x + CELL / 2, y + CELL / 2
    if h > 0.55 then -- a pad
      love.graphics.setColor(C.pad)
      love.graphics.circle("fill", cx, cy, CELL * 0.42, 32)
      love.graphics.setColor(C.paint)
      love.graphics.setLineWidth(8)
      love.graphics.circle("line", cx, cy, CELL * 0.38, 32)
      love.graphics.setLineWidth(1)
      love.graphics.rectangle("fill", cx - 30, cy - 4, 60, 8) -- an H
      love.graphics.rectangle("fill", cx - 30, cy - 36, 8, 72)
      love.graphics.rectangle("fill", cx + 22, cy - 36, 8, 72)
      if h > 0.85 then -- a shuttle parked on it
        love.graphics.setColor(C.shuttleDark)
        love.graphics.polygon("fill", cx, cy - 120, cx + 110, cy + 60, cx - 110, cy + 60)
        love.graphics.setColor(C.shuttle)
        love.graphics.polygon("fill", cx, cy - 140, cx + 40, cy - 60, cx + 40, cy + 100, cx - 40, cy + 100, cx - 40,
          cy - 60)
      end
    else -- taxiway lines
      love.graphics.setColor(C.paint[1], C.paint[2], C.paint[3], 0.5)
      if c % 2 == 0 then
        love.graphics.rectangle("fill", cx - 3, y, 6, CELL)
      else
        love.graphics.rectangle("fill", x, cy - 3, CELL, 6)
      end
    end
  end)
end

--- The runway lights round the pads, blinking in turn.
function StarportPads.lights(map, left, top, right, bottom, t, glow)
  each(map, left - 200, top - 200, right + 200, bottom + 200, function(x, y, h)
    if h > 0.55 then
      local cx, cy = x + CELL / 2, y + CELL / 2
      for k = 0, 7 do
        local on = (math.floor(t * 4) - k) % 8 < 2
        local a = k / 8 * 2 * math.pi
        glow(cx + math.cos(a) * CELL * 0.45, cy + math.sin(a) * CELL * 0.45, 40, LIGHT, on and 0.9 or 0.25)
      end
    end
  end)
end

return StarportPads
