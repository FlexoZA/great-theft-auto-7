-- Grey City far below the Overpass (surroundings' entry for it): you are
-- up on a bridge, and the city is a long way down. Everything here is
-- drawn smaller than the map and slides by slower as you drive (parallax,
-- DEPTH), under a haze, so it sits deep below the deck: blocks of towers
-- seen from above, streets with traffic crawling along them, and a wide
-- river the bridge crosses in its middle stretch, the city's lights
-- smeared on the water.
--
-- At night (the night feature) only its lights show (`lights`): lit
-- windows and neon on the towers, street lamps, the traffic's headlights
-- and tail lights, and their glimmer on the river, all dimmed by the
-- distance.
--
-- The blocks are worked out from where they sit, the same on every machine
-- and never running out. Client only.

local Layout = require("src.features.city-map.layout")

local Below = {}

Below.DEPTH = 0.45 -- how big the city below is drawn, and how fast it slides by, against the map
local PERIOD = 900 -- px (down there) from one street to the next
local STREET = 150 -- px of street
local LAMP_EVERY = 170 -- px between street lamps
local CARS = 3 -- each way along a street's period
local CAR_SPEED = { 90, 170 } -- px/s down there
local HAZE = { 0.07, 0.08, 0.12, 0.3 } -- over all of it, pushing it down
local RIVER_W = 2400 -- px across, down there
local RIVER_AT = 0.52 -- how far up the map (from the bottom) the river runs under the bridge

local GROUND = { 0.13, 0.14, 0.16 }
local STREET_C = { 0.17, 0.18, 0.20 }
local WATER = { 0.05, 0.08, 0.12 }
local WATER_LIGHT = { 0.10, 0.15, 0.22 }
local BANK = { 0.24, 0.24, 0.26 }
local ROOFS = { { 0.24, 0.25, 0.28 }, { 0.20, 0.21, 0.24 }, { 0.28, 0.28, 0.30 }, { 0.18, 0.19, 0.22 } }
local NEON = { { 0.18, 0.90, 1.00 }, { 1.00, 0.24, 0.78 }, { 0.43, 1.00, 0.60 }, { 1.00, 0.86, 0.62 } }
local WINDOW = { 1.00, 0.86, 0.62 }
local LAMP = { 1.00, 0.80, 0.55 }
local HEAD = { 1.00, 0.95, 0.82 }
local TAIL = { 1.00, 0.15, 0.12 }

local function hash(a, b)
  local x = math.sin(a * 12.9898 + b * 78.233) * 43758.5453
  return x - math.floor(x)
end

--- Where the river runs (down there): its middle, from the map.
local function riverY(map)
  return map.top + map.h * (1 - RIVER_AT)
end

local function inRiver(map, y0, y1)
  local ry = riverY(map)
  return y1 > ry - RIVER_W / 2 and y0 < ry + RIVER_W / 2
end

--- Push the view down there: drawn about the camera, `DEPTH` the size.
--- Returns the view's bounds down there.
local function enter(camera, left, top, right, bottom)
  local k = Below.DEPTH
  love.graphics.push()
  love.graphics.translate(camera.x, camera.y)
  love.graphics.scale(k)
  love.graphics.translate(-camera.x, -camera.y)
  return camera.x + (left - camera.x) / k, camera.y + (top - camera.y) / k,
    camera.x + (right - camera.x) / k, camera.y + (bottom - camera.y) / k
end

--- The buildings of block (bx, by): { x, y, w, h, roof, neon } each.
local cache = {}
local function blockOf(bx, by)
  local key = bx * 100003 + by
  local b = cache[key]
  if b then
    return b
  end
  b = {}
  local x0, y0 = bx * PERIOD + STREET, by * PERIOD + STREET
  local size = PERIOD - STREET
  local n = 2 + math.floor(hash(bx, by) * 3) -- 2 to 4 towers, in a row or a grid
  local cols = n >= 3 and 2 or 1
  local rows = math.ceil(n / cols)
  local cw, ch = size / cols, size / rows
  for i = 0, n - 1 do
    local c, r = i % cols, math.floor(i / cols)
    local h = hash(bx * 3 + i, by * 7 - i)
    local inset = 18 + h * 40
    b[#b + 1] = {
      x = x0 + c * cw + inset, y = y0 + r * ch + inset, w = cw - 2 * inset, h = ch - 2 * inset,
      roof = ROOFS[1 + math.floor(h * #ROOFS) % #ROOFS], neon = h > 0.55 and NEON[1 + math.floor(h * 97) % #NEON],
      lit = h,
    }
  end
  cache[key] = b
  local count = 0
  for _ in pairs(cache) do
    count = count + 1
  end
  if count > 400 then
    cache = {}
  end
  return b
end

--- Every block in view (down there) off the river: fn(bx, by, buildings).
local function eachBlock(map, left, top, right, bottom, fn)
  for bx = math.floor(left / PERIOD), math.floor(right / PERIOD) do
    for by = math.floor(top / PERIOD), math.floor(bottom / PERIOD) do
      if not inRiver(map, by * PERIOD, (by + 1) * PERIOD) then
        fn(bx, by, blockOf(bx, by))
      end
    end
  end
end

--- Cars on the streets in view, both ways: fn(x, y, dx, dy).
local function eachCar(map, left, top, right, bottom, clock, fn)
  for k = math.floor(top / PERIOD), math.floor(bottom / PERIOD) do
    local y = k * PERIOD + STREET / 2
    if not inRiver(map, y, y) then
      for i = 1, CARS * 2 do
        local dir = i % 2 == 0 and 1 or -1
        local speed = CAR_SPEED[1] + hash(k, i) * (CAR_SPEED[2] - CAR_SPEED[1])
        local span = right - left + 400
        local x = left - 200 + ((hash(i, k) * span + dir * speed * clock) % span)
        fn(x, y + dir * STREET / 4, dir, 0)
      end
    end
  end
  for k = math.floor(left / PERIOD), math.floor(right / PERIOD) do
    local x = k * PERIOD + STREET / 2
    for i = 1, CARS * 2 do
      local dir = i % 2 == 0 and 1 or -1
      local speed = CAR_SPEED[1] + hash(i, k + 0.5) * (CAR_SPEED[2] - CAR_SPEED[1])
      local span = bottom - top + 400
      local y = top - 200 + ((hash(k, i + 0.5) * span + dir * speed * clock) % span)
      if not inRiver(map, y, y) then
        fn(x - dir * STREET / 4, y, 0, dir)
      end
    end
  end
end

function Below.draw(map, camera, left, top, right, bottom, clock)
  if not camera then
    return
  end
  local l, t, r, b = enter(camera, left, top, right, bottom)
  love.graphics.setColor(GROUND)
  love.graphics.rectangle("fill", l, t, r - l, b - t)
  -- The streets, a grid.
  love.graphics.setColor(STREET_C)
  for k = math.floor(t / PERIOD), math.floor(b / PERIOD) do
    love.graphics.rectangle("fill", l, k * PERIOD, r - l, STREET)
  end
  for k = math.floor(l / PERIOD), math.floor(r / PERIOD) do
    love.graphics.rectangle("fill", k * PERIOD, t, STREET, b - t)
  end
  -- The towers, each with a shadow, its roof and a plant room on top.
  eachBlock(map, l, t, r, b, function(_, _, list)
    for _, bd in ipairs(list) do
      love.graphics.setColor(0, 0, 0, 0.45)
      love.graphics.rectangle("fill", bd.x + 30, bd.y + 30, bd.w, bd.h)
      love.graphics.setColor(bd.roof)
      love.graphics.rectangle("fill", bd.x, bd.y, bd.w, bd.h)
      love.graphics.setColor(bd.roof[1] * 0.8, bd.roof[2] * 0.8, bd.roof[3] * 0.8)
      love.graphics.rectangle("fill", bd.x + bd.w * 0.3, bd.y + bd.h * 0.3, bd.w * 0.3, bd.h * 0.25)
    end
  end)
  -- The traffic, as little dark cars.
  eachCar(map, l, t, r, b, clock, function(x, y, dx)
    love.graphics.setColor(0.10, 0.11, 0.13)
    if dx ~= 0 then
      love.graphics.rectangle("fill", x - 22, y - 10, 44, 20, 4)
    else
      love.graphics.rectangle("fill", x - 10, y - 22, 20, 44, 4)
    end
  end)
  -- The river, banked both sides, its surface rippling.
  local ry = riverY(map)
  local y0, y1 = ry - RIVER_W / 2, ry + RIVER_W / 2
  if y1 > t and y0 < b then
    love.graphics.setColor(BANK)
    love.graphics.rectangle("fill", l, y0 - 40, r - l, 40)
    love.graphics.rectangle("fill", l, y1, r - l, 40)
    love.graphics.setColor(WATER)
    love.graphics.rectangle("fill", l, y0, r - l, y1 - y0)
    love.graphics.setColor(WATER_LIGHT[1], WATER_LIGHT[2], WATER_LIGHT[3], 0.6)
    for y = y0 + 60, y1 - 60, 90 do
      local drift = (clock * 30 + y * 7) % 400
      for x = math.floor(l / 400) * 400 - 400 + drift, r, 400 do
        love.graphics.rectangle("fill", x, y + math.sin(x * 0.01 + clock) * 6, 120, 6)
      end
    end
  end
  love.graphics.pop()
  -- The haze over all of it: it is a long way down.
  love.graphics.setColor(HAZE)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
end

--- At night: what glows down there, dimmed by the distance.
function Below.lights(map, camera, left, top, right, bottom, clock, light)
  if not camera then
    return
  end
  -- Nothing down there lights the deck up here: a light under it is left out.
  local depth, T = Below.DEPTH, Layout.TILE
  local function glow(x, y, rad, c, a)
    local wx, wy = camera.x + (x - camera.x) * depth, camera.y + (y - camera.y) * depth
    local col = map.tiles[math.floor((wx - map.x0) / T)]
    if not (col and col[math.floor((wy - map.y0) / T)]) then
      light(x, y, rad, c, a)
    end
  end
  local l, t, r, b = enter(camera, left, top, right, bottom)
  local dim = 0.85
  eachBlock(map, l, t, r, b, function(_, _, list)
    for i, bd in ipairs(list) do
      for k = 0, 2 do -- a few lit windows
        local h = hash(bd.lit * 100 + k, i)
        if h > 0.35 then
          glow(bd.x + bd.w * (0.15 + 0.7 * h), bd.y + bd.h * (0.15 + 0.7 * hash(h, k)), 110, WINDOW, 0.6 * dim)
        end
      end
      if bd.neon then -- a sign on its south edge
        glow(bd.x + bd.w / 2, bd.y + bd.h, 260, bd.neon, 0.9 * dim)
      end
    end
  end)
  for k = math.floor(t / PERIOD), math.floor(b / PERIOD) do
    local y = k * PERIOD + STREET / 2
    if not inRiver(map, y, y) then
      for x = math.floor(l / LAMP_EVERY) * LAMP_EVERY, r, LAMP_EVERY do
        glow(x, y, 170, LAMP, 0.65 * dim)
      end
    end
  end
  for k = math.floor(l / PERIOD), math.floor(r / PERIOD) do
    local x = k * PERIOD + STREET / 2
    for y = math.floor(t / LAMP_EVERY) * LAMP_EVERY, b, LAMP_EVERY do
      if not inRiver(map, y, y) then
        glow(x, y, 170, LAMP, 0.65 * dim)
      end
    end
  end
  eachCar(map, l, t, r, b, clock, function(x, y, dx, dy)
    glow(x + dx * 26, y + dy * 26, 90, HEAD, 1.0 * dim)
    glow(x - dx * 24, y - dy * 24, 70, TAIL, 1.0 * dim)
  end)
  -- The city's lights on the river: streaks of them glimmering on the water.
  local ry = riverY(map)
  local y0, y1 = ry - RIVER_W / 2, ry + RIVER_W / 2
  if y1 > t and y0 < b then
    -- Lamps along both banks' promenades, and their light on the water by them.
    for x = math.floor(l / 120) * 120, r, 120 do
      glow(x, y0 - 20, 130, LAMP, 0.8 * dim)
      glow(x, y1 + 20, 130, LAMP, 0.8 * dim)
      glow(x + 20, y0 + 70, 90, LAMP, 0.3 * dim * (0.6 + 0.4 * math.sin(clock * 2 + x)))
      glow(x + 20, y1 - 70, 90, LAMP, 0.3 * dim * (0.6 + 0.4 * math.sin(clock * 2.3 + x)))
    end
    for x = math.floor(l / 180) * 180, r, 180 do
      for y = y0 + 80, y1 - 80, 130 do
        local h = hash(x, y)
        if h > 0.45 then
          local shimmer = 0.5 + 0.5 * math.sin(clock * 3 + h * 40)
          glow(x + h * 120, y, 170, NEON[1 + math.floor(h * 13) % #NEON], 0.75 * dim * shimmer)
        end
      end
    end
  end
  love.graphics.pop()
end

return Below
