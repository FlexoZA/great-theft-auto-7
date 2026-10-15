-- What lies past Heck's edge (surroundings' entry for `heck`): a red abyss
-- with lava falling into it, black castles hanging upside down in it, embers
-- drifting up, and off the Altar Fields' west edge a crack across the sky
-- with the sofa's ceiling showing through it and a lampshade hanging in it
-- (the dream, leaking in). Worked out from the cell it sits on, the same on every
-- machine, and drawn each frame over what the camera sees, skipping the map
-- itself (its canvas lands on top). At night (`lights`) the lava falls glow.

local Heck = {}

local CELL = 448

local C = {
  abyss = { 0.10, 0.02, 0.02 },
  abyssDeep = { 0.07, 0.01, 0.02 },
  castle = { 0.04, 0.02, 0.03 },
  castleLit = { 0.85, 0.30, 0.08 },
  ceiling = { 0.86, 0.80, 0.70 },
  shade = { 0.82, 0.70, 0.50 },
}
local LAVA = { 1.00, 0.42, 0.08 }

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
        fn(x, y, hash(c * 3.91 + r * 7.73))
      end
    end
  end
end

--- An upside-down castle: towers hanging point down from a block of rock.
local function castle(x, y, h)
  love.graphics.setColor(C.castle)
  love.graphics.rectangle("fill", x + 60, y + 40, CELL - 120, 90)
  for k = 0, 3 do
    local tx = x + 90 + k * (CELL - 180) / 3
    local len = 120 + hash(h * 13 + k) * 140
    love.graphics.rectangle("fill", tx - 22, y + 120, 44, len)
    love.graphics.polygon("fill", tx - 30, y + 120 + len, tx + 30, y + 120 + len, tx, y + 170 + len)
    love.graphics.setColor(C.castleLit[1], C.castleLit[2], C.castleLit[3], 0.6)
    love.graphics.rectangle("fill", tx - 4, y + 140 + len * 0.4, 8, 12) -- a window, lit
    love.graphics.setColor(C.castle)
  end
end

--- The crack in the sky beside the Altar Fields, out past the west edge,
--- running north and south, the sofa's ceiling through it.
local CRACK_OUT = 330 -- px past the map's west edge
local function crack(map, t)
  local cx, cy = 0, 0
  love.graphics.push()
  love.graphics.translate(map.left - CRACK_OUT, map.top + map.h * 0.45)
  love.graphics.rotate(math.pi / 2)
  local pts = {}
  for k = 0, 12 do
    local x = cx - 900 + k * 150
    pts[#pts + 1] = x
    pts[#pts + 1] = cy + (k % 2 == 0 and -90 or 90) + math.sin(k * 1.7) * 40
  end
  love.graphics.setColor(C.ceiling)
  for k = 1, #pts - 3, 2 do
    love.graphics.polygon("fill", pts[k], pts[k + 1] - 70, pts[k + 2], pts[k + 3] - 70, pts[k + 2], pts[k + 3] + 70,
      pts[k], pts[k + 1] + 70)
  end
  love.graphics.setColor(1, 0.95, 0.8, 0.5 + 0.1 * math.sin(t))
  love.graphics.setLineWidth(6)
  love.graphics.line(pts)
  love.graphics.setLineWidth(1)
  -- The lampshade hanging down through it on its flex.
  love.graphics.setColor(0.2, 0.2, 0.2)
  love.graphics.line(cx + 120, cy - 60, cx + 120, cy + 40)
  love.graphics.setColor(C.shade)
  love.graphics.polygon("fill", cx + 70, cy + 120, cx + 170, cy + 120, cx + 145, cy + 40, cx + 95, cy + 40)
  love.graphics.setColor(1, 0.95, 0.7, 0.8)
  love.graphics.ellipse("fill", cx + 120, cy + 120, 50, 12, 16)
  love.graphics.pop()
end

function Heck.draw(map, left, top, right, bottom, t)
  each(map, left, top, right, bottom, function(x, y, h)
    love.graphics.setColor(h < 0.5 and C.abyss or C.abyssDeep)
    love.graphics.rectangle("fill", x, y, CELL, CELL)
    if h > 0.78 then
      castle(x, y, h)
    elseif h < 0.2 then -- a fall of lava, pouring
      local fx = x + CELL * (0.3 + h * 2)
      love.graphics.setColor(LAVA[1], LAVA[2], LAVA[3], 0.85)
      love.graphics.rectangle("fill", fx - 18, y, 36, CELL)
      love.graphics.setColor(1, 0.85, 0.4, 0.8)
      for k = 0, 5 do
        local yy = y + ((t * 220 + k * CELL / 6 + h * 999) % CELL)
        love.graphics.rectangle("fill", fx - 6, yy, 12, 30)
      end
    end
  end)
  for k = 0, 24 do -- embers drifting up out of it
    local span = bottom - top + 600
    local ex = left + hash(k * 3.3) * (right - left)
    local ey = bottom + 300 - ((t * (40 + k * 3) + hash(k * 7.1) * span) % span)
    love.graphics.setColor(1, 0.5, 0.15, 0.7)
    love.graphics.circle("fill", ex + math.sin(t + k) * 20, ey, 3, 6)
  end
  if left < map.left - CRACK_OUT + 200 then
    crack(map, t)
  end
end

--- The lava falls, glowing.
function Heck.lights(map, left, top, right, bottom, t, glow)
  each(map, left - 200, top - 200, right + 200, bottom + 200, function(x, y, h)
    if h < 0.2 then
      local fx = x + CELL * (0.3 + h * 2)
      glow(fx, y + CELL / 2, 300, LAVA, 0.6 + 0.1 * math.sin(t * 2 + h * 10))
    end
  end)
end

return Heck
