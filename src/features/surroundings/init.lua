-- Surroundings: the world past a map's edge, so a map never ends in the
-- bare grid. Drawn over the grid and under the map (city-map's canvas lands
-- on top), made up as the camera looks so it never runs out.
--
-- The city is an island: sea all round it, deep blue further out and
-- lighter in the shallows, waves rolling across it, foam washing up against
-- a concrete harbour wall with bollards along it, and a few boats sailing
-- slow loops round the island. The shore follows the city's land tile by
-- tile, so a block the city grows (real-estate) gets its own quay.
--
-- Other maps keep the grid for now; a map gets surroundings by an entry in
-- `DRAW`, keyed by map name.
--
-- Client only: nothing here touches the world.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")

local Surroundings = {
  name = "surroundings",
  priority = 15, -- over the grid (10), under the city map (20)
}

local DEEP = { 0.09, 0.25, 0.40 }
local SHALLOW = { 0.20, 0.52, 0.62 }
local WAVE = { 0.55, 0.78, 0.9 }
local FOAM = { 0.92, 0.96, 1 }
local QUAY = { 0.56, 0.56, 0.6 }
local QUAY_EDGE = { 0.3, 0.3, 0.34 }

local WAVE_CELL = 56 -- px between the waves' grid points
local QUAY_W = 8 -- px of harbour wall past the land
local SHALLOWS = 170 -- px out from the shore the water starts to get lighter
local BOLLARD_EVERY = 72 -- px along the wall

local clock = 0

function Surroundings:update(dt)
  clock = clock + dt
end

-- The shore ---------------------------------------------------------------

local shore = { map = nil, version = nil, segments = {} }

local function land(map, c, r)
  local col = map.tiles[c]
  return col ~= nil and col[r] ~= nil
end

--- Every stretch of coast of `map`: a straight run along tile edges with
--- land on one side and sea on the other, `nx, ny` pointing out to sea.
--- Worked out again only when the city changes (map.version).
local function segments(map)
  if shore.map == map and shore.version == map.version then
    return shore.segments
  end
  local T = Layout.TILE
  local list = {}
  -- Runs along rows (coast facing up or down), then along columns.
  for _, dir in ipairs({ { 0, -1 }, { 0, 1 } }) do
    for r = map.r0, map.r1 do
      local run
      for c = map.c0, map.c1 + 1 do
        local edge = land(map, c, r) and not land(map, c, r + dir[2])
        if edge and not run then
          run = c
        elseif not edge and run then
          local y = map.y0 + (dir[2] < 0 and r or r + 1) * T
          list[#list + 1] = { x1 = map.x0 + run * T, y1 = y, x2 = map.x0 + c * T, y2 = y, nx = 0, ny = dir[2] }
          run = nil
        end
      end
    end
  end
  for _, dir in ipairs({ { -1, 0 }, { 1, 0 } }) do
    for c = map.c0, map.c1 do
      local run
      for r = map.r0, map.r1 + 1 do
        local edge = land(map, c, r) and not land(map, c + dir[1], r)
        if edge and not run then
          run = r
        elseif not edge and run then
          local x = map.x0 + (dir[1] < 0 and c or c + 1) * T
          list[#list + 1] = { x1 = x, y1 = map.y0 + run * T, x2 = x, y2 = map.y0 + r * T, nx = dir[1], ny = 0 }
          run = nil
        end
      end
    end
  end
  shore.map, shore.version, shore.segments = map, map.version, list
  return list
end

--- A band `from` to `to` px out to sea along segment `s`.
local function band(s, from, to)
  local x1, y1 = math.min(s.x1, s.x2), math.min(s.y1, s.y2)
  local x2, y2 = math.max(s.x1, s.x2), math.max(s.y1, s.y2)
  if s.ny ~= 0 then
    local y = s.ny < 0 and y1 - to or y1 + from
    love.graphics.rectangle("fill", x1 - to, y, x2 - x1 + 2 * to, to - from)
  else
    local x = s.nx < 0 and x1 - to or x1 + from
    love.graphics.rectangle("fill", x, y1 - to, to - from, y2 - y1 + 2 * to)
  end
end

-- The city: an island -----------------------------------------------------

--- What part of the world the camera sees, padded.
local function view(camera)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local hw, hh = w / 2 / s + 80, h / 2 / s + 80
  return camera.x - hw, camera.y - hh, camera.x + hw, camera.y + hh
end

local function sea(map, camera)
  local left, top, right, bottom = view(camera)
  love.graphics.setColor(DEEP)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local list = segments(map)
  -- The shallows: lighter water the nearer the shore, in rounded bands
  -- round the island, so they curve round its corners.
  love.graphics.setColor(SHALLOW[1], SHALLOW[2], SHALLOW[3], 0.07)
  for out = SHALLOWS, 4, -12 do
    love.graphics.rectangle("fill", map.left - out, map.top - out, map.w + 2 * out, map.h + 2 * out, out, out, 16)
  end
  -- Waves: short crests on a grid anchored in the world, each rising and
  -- falling on its own and drifting a little with the swell.
  love.graphics.setLineWidth(2)
  local c0, c1 = math.floor(left / WAVE_CELL), math.ceil(right / WAVE_CELL)
  local r0, r1 = math.floor(top / WAVE_CELL), math.ceil(bottom / WAVE_CELL)
  for c = c0, c1 do
    for r = r0, r1 do
      local n = love.math.noise(c * 0.37, r * 0.41)
      local phase = clock * (0.6 + n * 0.5) + n * 20
      local crest = math.sin(phase)
      if crest > 0.2 then
        local x = c * WAVE_CELL + (n - 0.5) * WAVE_CELL + math.sin(clock * 0.4 + r) * 6
        local y = r * WAVE_CELL + ((n * 7) % 1 - 0.5) * WAVE_CELL
        local len = 8 + 10 * n
        love.graphics.setColor(WAVE[1], WAVE[2], WAVE[3], (crest - 0.2) * 0.6)
        love.graphics.arc("line", "open", x, y + 6, len, -math.pi * 0.8, -math.pi * 0.2, 8)
      end
    end
  end
  -- Foam washing against the wall, coming and going.
  love.graphics.setLineWidth(1)
  for _, s in ipairs(list) do
    local len = math.abs(s.x2 - s.x1) + math.abs(s.y2 - s.y1)
    local tx, ty = (s.x2 - s.x1) / len, (s.y2 - s.y1) / len
    for d = 0, len, 9 do
      local px, py = s.x1 + tx * d, s.y1 + ty * d
      local wash = 0.5 + 0.5 * math.sin(clock * 1.6 + d * 0.05 + love.math.noise(px * 0.02, py * 0.02) * 6)
      local out = QUAY_W + 2 + wash * 7
      love.graphics.setColor(FOAM[1], FOAM[2], FOAM[3], 0.35 + 0.35 * wash)
      love.graphics.circle("fill", px + s.nx * out, py + s.ny * out, 1.6 + wash * 1.6, 6)
    end
  end
  -- The harbour wall: concrete lit along its top, a dark lip over the
  -- water, bollards along it.
  love.graphics.setColor(QUAY)
  for _, s in ipairs(list) do
    band(s, 0, QUAY_W)
  end
  love.graphics.setColor(QUAY[1] * 1.2, QUAY[2] * 1.2, QUAY[3] * 1.2)
  for _, s in ipairs(list) do
    band(s, 0, 2.5)
  end
  love.graphics.setColor(QUAY_EDGE)
  for _, s in ipairs(list) do
    band(s, QUAY_W - 2, QUAY_W)
    local len = math.abs(s.x2 - s.x1) + math.abs(s.y2 - s.y1)
    local tx, ty = (s.x2 - s.x1) / len, (s.y2 - s.y1) / len
    for d = BOLLARD_EVERY / 2, len, BOLLARD_EVERY do
      love.graphics.circle("fill", s.x1 + tx * d + s.nx * 4, s.y1 + ty * d + s.ny * 4, 2.4, 8)
    end
  end
end

--- A few boats sailing slow loops round the island, each at its own
--- distance and pace, a wake trailing behind.
local BOATS = {
  { out = 260, speed = 0.018, phase = 0.3, hull = { 0.9, 0.9, 0.92 }, sail = { 0.95, 0.95, 0.9 } },
  { out = 420, speed = -0.012, phase = 2.1, hull = { 0.55, 0.3, 0.2 }, sail = { 0.9, 0.5, 0.3 } },
  { out = 330, speed = 0.014, phase = 4.4, hull = { 0.25, 0.35, 0.55 }, sail = { 0.95, 0.9, 0.7 } },
}

local function boats(map, camera)
  local left, top, right, bottom = view(camera)
  local cx, cy = map.left + map.w / 2, map.top + map.h / 2
  for _, b in ipairs(BOATS) do
    local a = b.phase + clock * b.speed
    local rx, ry = map.w / 2 + b.out, map.h / 2 + b.out
    local x, y = cx + math.cos(a) * rx, cy + math.sin(a) * ry
    if x > left and x < right and y > top and y < bottom then
      -- Heading along the loop, the way it is going.
      local dir = b.speed > 0 and 1 or -1
      local heading = math.atan2(math.cos(a) * ry * dir, -math.sin(a) * rx * dir)
      love.graphics.push()
      love.graphics.translate(x, y)
      love.graphics.rotate(heading)
      love.graphics.scale(1.7) -- a proper boat next to a car
      love.graphics.setColor(FOAM[1], FOAM[2], FOAM[3], 0.35)
      love.graphics.polygon("fill", -14, -3, -40, -9, -40, 9, -14, 3) -- the wake
      love.graphics.setColor(0, 0, 0, 0.25)
      love.graphics.ellipse("fill", 2, 3, 18, 7, 12)
      love.graphics.setColor(b.hull)
      love.graphics.polygon("fill", -16, -6, 10, -6, 20, 0, 10, 6, -16, 6) -- the hull
      love.graphics.setColor(b.hull[1] * 0.7, b.hull[2] * 0.7, b.hull[3] * 0.7)
      love.graphics.polygon("line", -16, -6, 10, -6, 20, 0, 10, 6, -16, 6)
      love.graphics.setColor(b.sail)
      love.graphics.polygon("fill", -6, -1, 8, -1, -6, -13 + math.sin(clock * 2 + b.phase)) -- the sail, filling
      love.graphics.setColor(0.35, 0.28, 0.2)
      love.graphics.line(-6, 0, -6, -14) -- the mast
      love.graphics.pop()
    end
  end
end

local DRAW = {
  city = function(map, camera)
    sea(map, camera)
    boats(map, camera)
  end,
}

function Surroundings:drawBelowCars(_client, camera)
  local city = Features.byName["city-map"]
  local map = city and city.map
  local draw = map and DRAW[map.name]
  if draw and map.tiles then
    draw(map, camera)
    love.graphics.setColor(1, 1, 1)
    love.graphics.setLineWidth(1)
  end
end

return Surroundings
