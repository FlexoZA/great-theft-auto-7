-- The moon past Fobos Base's edge (surroundings' entry for `fobos`): the
-- same grey dust and craters as the margin round the base
-- (city-map's render_eternal_mood.lua), running on out of reach, with a
-- boulder here and there and the odd set of tyre tracks from the UAC's
-- rovers. Worked out from the cell it sits on, the same on every machine,
-- and drawn each frame over what the camera sees, skipping the map itself
-- (its canvas lands on top).

local FobosMoon = {}

local CELL = 128 -- px of dust in a cell; craters and boulders are placed per cell
local C = {
  dust = { 0.42, 0.42, 0.44 },
  dustDark = { 0.36, 0.36, 0.38 },
  crater = { 0.30, 0.30, 0.32 },
  craterRim = { 0.52, 0.52, 0.54 },
  rock = { 0.26, 0.26, 0.28 },
  track = { 0.33, 0.33, 0.35 },
}

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- Draw the moon over the box (left, top, right, bottom), world px.
function FobosMoon.draw(map, left, top, right, bottom)
  local mx0, my0, mx1, my1 = map.left, map.top, map.left + map.w, map.top + map.h
  local c0, c1 = math.floor(left / CELL), math.ceil(right / CELL)
  local r0, r1 = math.floor(top / CELL), math.ceil(bottom / CELL)
  for c = c0, c1 do
    for r = r0, r1 do
      local x, y = c * CELL, r * CELL
      if not (x >= mx0 and x + CELL <= mx1 and y >= my0 and y + CELL <= my1) then
        local h = hash(c * 7.31 + r * 17.17)
        love.graphics.setColor(h < 0.5 and C.dust or C.dustDark)
        love.graphics.rectangle("fill", x, y, CELL, CELL)
        if h > 0.86 then
          local rad = 16 + (h - 0.86) * 300
          local cx, cy = x + CELL / 2 + (hash(h * 3) - 0.5) * 40, y + CELL / 2 + (hash(h * 5) - 0.5) * 40
          love.graphics.setColor(C.craterRim)
          love.graphics.circle("fill", cx - 3, cy - 3, rad + 4, 20)
          love.graphics.setColor(C.crater)
          love.graphics.circle("fill", cx, cy, rad, 20)
        elseif h < 0.08 then
          love.graphics.setColor(C.rock)
          love.graphics.ellipse("fill", x + 30 + h * 600, y + 70, 14, 10, 10)
        end
      end
    end
  end
  -- Rover tracks running north-south past the base, either side of it.
  love.graphics.setColor(C.track)
  for _, tx in ipairs({ mx0 - 300, mx1 + 260 }) do
    if tx > left - 40 and tx < right + 40 then
      love.graphics.rectangle("fill", tx, top, 10, bottom - top)
      love.graphics.rectangle("fill", tx + 34, top, 10, bottom - top)
    end
  end
end

return FobosMoon
