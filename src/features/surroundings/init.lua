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
-- Whispering Pines goes on as forest: pines and broadleaf trees on the
-- same floor, a ragged treeline at the edge, thicker and darker further
-- out, swaying a little.
--
-- Karen's cul-de-sac is fenced in by a garden hedge; past it are the
-- neighbours' lawns and then woods, and the street carries on south out of
-- the entrance, hedged both sides and lit by street lamps.
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

-- Whispering Pines: the forest goes on --------------------------------------

local FLOOR = { 0.20, 0.32, 0.17 } -- city-map's forest floor, so the edge doesn't show
local PINE = { 0.10, 0.27, 0.16 }
local PINE_LIGHT = { 0.16, 0.36, 0.20 }
local CANOPY = { 0.16, 0.36, 0.16 }
local CANOPY_LIGHT = { 0.28, 0.52, 0.24 }
local TREE_CELL = 42 -- px between trees on the grid they grow on
local TREE_SIZE = 64 -- px square each tree picture is drawn in

-- A few tree pictures, drawn once and stamped: over a thousand trees fill a
-- zoomed-out screen, and a picture is one draw (LÖVE batches them).
local trees = nil

--- A pine from above, as city-map draws them: three rings of needles.
local function pine(x, y, r)
  for k, c in ipairs({ PINE, PINE_LIGHT, PINE }) do
    local rr = r * (1.08 - k * 0.28)
    love.graphics.setColor(c)
    love.graphics.circle("fill", x, y, rr * 0.72, 16)
    local inner = rr * 0.72
    for i = 0, 7 do
      local a = i * math.pi / 4 + k * 0.2
      love.graphics.polygon("fill", x, y, x + math.cos(a - 0.28) * inner, y + math.sin(a - 0.28) * inner,
        x + math.cos(a) * rr, y + math.sin(a) * rr, x + math.cos(a + 0.28) * inner, y + math.sin(a + 0.28) * inner)
    end
  end
end

--- A broadleaf tree from above: a round canopy lit on one side.
local function broadleaf(x, y, r)
  love.graphics.setColor(CANOPY)
  love.graphics.circle("fill", x, y, r, 20)
  love.graphics.setColor(CANOPY_LIGHT)
  love.graphics.circle("fill", x - r / 4, y - r / 4, r / 2, 16)
end

local function treePictures()
  if trees then
    return trees
  end
  trees = {}
  local c = TREE_SIZE / 2
  for i, spec in ipairs({ { pine, 22 }, { pine, 26 }, { broadleaf, 20 }, { pine, 18 }, { broadleaf, 24 } }) do
    local canvas = love.graphics.newCanvas(TREE_SIZE, TREE_SIZE)
    love.graphics.push("all")
    love.graphics.origin()
    love.graphics.setCanvas(canvas)
    love.graphics.clear(0, 0, 0, 0)
    love.graphics.setColor(0, 0, 0, 0.35) -- its shadow, down and right
    love.graphics.circle("fill", c + 6, c + 6, spec[2] * 0.9, 20)
    spec[1](c - 2, c - 2, spec[2])
    love.graphics.setCanvas()
    love.graphics.pop()
    trees[i] = canvas
  end
  return trees
end

--- How far (x, y) is outside the map's rectangle, 0 inside it.
local function outside(map, x, y)
  local dx = math.max(map.left - x, 0, x - (map.left + map.w))
  local dy = math.max(map.top - y, 0, y - (map.top + map.h))
  return math.sqrt(dx * dx + dy * dy)
end

--- The forest past the edge: floor, then a tree on every point of a grid
--- anchored in the world, jittered, of a size and kind of its own, thinner
--- right by the edge (a ragged treeline) and darker the further out, as
--- the canopy closes in; each sways a little in the wind.
--- Trees past the edge on a grid anchored in the world, jittered, each of
--- a size and kind of its own, darker the further out as the canopy closes
--- in, swaying a little. They start `from` px out, only some of them for the
--- first `ragged` px (a ragged treeline); `skip(x, y)` keeps them off
--- somewhere (a road). `pics` picks from the tree pictures by number.
local function woods(map, camera, from, ragged, pics, skip)
  local left, top, right, bottom = view(camera)
  local all = treePictures()
  local c0, c1 = math.floor((left - 40) / TREE_CELL), math.ceil((right + 40) / TREE_CELL)
  local r0, r1 = math.floor((top - 40) / TREE_CELL), math.ceil((bottom + 40) / TREE_CELL)
  local half = TREE_SIZE / 2
  for c = c0, c1 do
    for r = r0, r1 do
      local n1 = love.math.noise(c * 0.71, r * 0.93)
      local n2 = love.math.noise(c * 1.37 + 11, r * 1.19 + 7)
      local x = (c + 0.5) * TREE_CELL + (n1 - 0.5) * TREE_CELL * 0.9
      local y = (r + 0.5) * TREE_CELL + (n2 - 0.5) * TREE_CELL * 0.9
      local d = outside(map, x, y)
      if d > from and (d > from + ragged or n1 > 0.45) and not (skip and skip(x, y)) then
        local shade = 1 - math.min(0.5, (d - from) / 1400)
        local size = 0.85 + n2 * 0.45 + math.min(0.3, d / 1500)
        local sway = math.sin(clock * 0.8 + n1 * 12) * 0.8
        love.graphics.setColor(shade, shade, shade)
        love.graphics.draw(all[pics[math.floor(n1 * 97) % #pics + 1]], x + sway, y, 0, size, size, half, half)
      end
    end
  end
end

local EVERY_TREE = { 1, 2, 3, 4, 5 }

local function forest(map, camera)
  local left, top, right, bottom = view(camera)
  love.graphics.setColor(FLOOR)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  woods(map, camera, 12, 58, EVERY_TREE)
end

-- Karen's cul-de-sac: a hedge, the neighbours' lawns, woods, the road out ----

local LAWN = { 0.36, 0.46, 0.27 } -- city-map's open ground, the cul-de-sac's lawns
local LAWN_DARK = { 0.31, 0.40, 0.23 }
local HEDGE = { 0.13, 0.30, 0.13 }
local HEDGE_LIGHT = { 0.2, 0.4, 0.18 }
local ASPHALT = { 0.17, 0.17, 0.19 }
local SIDEWALK = { 0.52, 0.52, 0.55 }
local LANE = { 0.85, 0.72, 0.30 }
local HEDGE_W = 30 -- px of hedge past the edge
local GARDENS = 110 -- px of lawn between the hedge and the woods
local LAMP_EVERY = 190 -- px down the road between street lamps
local BROADLEAF = { 3, 5, 3, 2 } -- mostly broadleaf in the suburbs' woods

--- Where the street leaves the cul-de-sac: its x from sidewalk to sidewalk,
--- and the middle of it (city-map's layout: the street runs down the middle
--- two columns, a sidewalk each side).
local function street(map)
  local T = Layout.TILE
  local mid = math.floor(map.cols / 2)
  return map.x0 + (mid - 2) * T, map.x0 + (mid + 2) * T, map.x0 + mid * T
end

--- A hedge from above over the box (x, y, w, h): dark leaves, a bumpy top
--- lit here and there.
local function hedge(x, y, w, h)
  love.graphics.setColor(HEDGE)
  love.graphics.rectangle("fill", x, y, w, h, 6)
  local long = math.max(w, h)
  local step = 11
  for d = 0, long, step do
    local n = love.math.noise((x + d) * 0.05, (y + d) * 0.05)
    local px, py = w >= h and x + d or x + w / 2, w >= h and y + h / 2 or y + d
    love.graphics.setColor(HEDGE)
    love.graphics.circle("fill", px, py, math.min(w, h) * 0.55 + n * 3, 10)
    love.graphics.setColor(HEDGE_LIGHT)
    love.graphics.circle("fill", px - 2, py - 2, 3 + n * 3, 8)
  end
end

local function culdesac(map, camera)
  local left, top, right, bottom = view(camera)
  -- The neighbours' lawns, mown in patches.
  love.graphics.setColor(LAWN)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local T = Layout.TILE
  love.graphics.setColor(LAWN_DARK)
  for c = math.floor(left / T), math.ceil(right / T) do
    for r = math.floor(top / T), math.ceil(bottom / T) do
      if (c * 31 + r * 17) % 5 == 0 then
        love.graphics.rectangle("fill", c * T + (c * 7) % 24, r * T + (r * 11) % 24, 36, 28)
      end
    end
  end
  -- The road out, south past the entrance, off into the distance.
  local sx0, sx1, smid = street(map)
  local edge = map.top + map.h
  local farY = math.max(bottom, edge)
  if farY > edge then
    love.graphics.setColor(SIDEWALK)
    love.graphics.rectangle("fill", sx0, edge, sx1 - sx0, farY - edge)
    love.graphics.setColor(ASPHALT)
    love.graphics.rectangle("fill", sx0 + T, edge, sx1 - sx0 - 2 * T, farY - edge)
    love.graphics.setColor(LANE)
    love.graphics.setLineWidth(4)
    for y = edge + 12, farY, T do
      love.graphics.line(smid, y, smid, y + T - 24)
    end
    love.graphics.setLineWidth(1)
  end
  -- Woods beyond the gardens, never on the road.
  local function onRoad(x, y)
    return y > edge - 20 and x > sx0 - HEDGE_W - 30 and x < sx1 + HEDGE_W + 30
  end
  woods(map, camera, HEDGE_W + GARDENS, 70, BROADLEAF, onRoad)
  -- The hedge all round the gardens, with a gap where the street leaves,
  -- and down both sides of the road out.
  local L, R, Tp = map.left, map.left + map.w, map.top
  hedge(L - HEDGE_W, Tp - HEDGE_W, map.w + 2 * HEDGE_W, HEDGE_W) -- top
  hedge(L - HEDGE_W, Tp, HEDGE_W, map.h + HEDGE_W) -- left
  hedge(R, Tp, HEDGE_W, map.h + HEDGE_W) -- right
  hedge(L, edge, sx0 - L, HEDGE_W) -- bottom, either side of the street
  hedge(sx1, edge, R - sx1, HEDGE_W)
  if farY > edge + HEDGE_W then
    hedge(sx0 - HEDGE_W, edge + HEDGE_W, HEDGE_W, farY - edge - HEDGE_W)
    hedge(sx1, edge + HEDGE_W, HEDGE_W, farY - edge - HEDGE_W)
  end
  -- Street lamps down the road out, each throwing a little light.
  for y = edge + LAMP_EVERY / 2, farY, LAMP_EVERY do
    for _, x in ipairs({ sx0 + 10, sx1 - 10 }) do
      love.graphics.setColor(1, 0.9, 0.6, 0.12)
      love.graphics.circle("fill", x + (x < smid and 22 or -22), y, 34, 16)
      love.graphics.setColor(0.25, 0.25, 0.28)
      love.graphics.circle("fill", x, y, 4, 8)
      love.graphics.setLineWidth(2)
      love.graphics.line(x, y, x + (x < smid and 14 or -14), y)
      love.graphics.setLineWidth(1)
      love.graphics.setColor(1, 0.95, 0.75)
      love.graphics.circle("fill", x + (x < smid and 15 or -15), y, 2.5, 8)
    end
  end
end

local DRAW = {
  city = function(map, camera)
    sea(map, camera)
    boats(map, camera)
  end,
  forest = forest,
  culdesac = culdesac,
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
