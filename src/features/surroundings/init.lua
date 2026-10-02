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
-- Looz'er Beach runs on along the coast both ways, band by band (hill,
-- barracks, mud, sand, surf), hedgehogs on the sand, barbed wire fencing
-- the battle off at the sides; hedgerowed fields north of the hill, and
-- the sea south with warships steaming along offshore.
--
-- Shotgun's Bluff runs on both ways (the plateau, the cliff face, the
-- flowered meadow, boulders), walled in by dry-stone walls at the sides; a
-- canyon drops away past the plateau's north edge, a river at its bottom,
-- and the meadow gives way to woods south.
--
-- The outskirts are fenced round with post and rail; past the fence is
-- farmland, a patchwork of fields in rows with dirt tracks between them,
-- a lone tree here and there, and a farm with a tractor working a field.
--
-- City 17 carries on past its edges, out of reach behind the Combine's
-- wall round it: streets and blocks of flats, some bombed out, some
-- burning, the railway, the canal and the wall running on, all under a
-- haze (city17.lua).
--
-- Other maps keep the grid for now; a map gets surroundings by an entry in
-- `DRAW`, keyed by map name.
--
-- Client only: nothing here touches the world.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local City17 = require("src.features.surroundings.city17")

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

--- Waves over the box (left, top, right, bottom): short crests on a grid
--- anchored in the world, each rising and falling on its own and drifting
--- a little with the swell.
local function crests(left, top, right, bottom)
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
        if y > top then
          local len = 8 + 10 * n
          love.graphics.setColor(WAVE[1], WAVE[2], WAVE[3], (crest - 0.2) * 0.6)
          love.graphics.arc("line", "open", x, y + 6, len, -math.pi * 0.8, -math.pi * 0.2, 8)
        end
      end
    end
  end
  love.graphics.setLineWidth(1)
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
  crests(left, top, right, bottom)
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

-- Looz'er Beach: the coast goes on, fenced off; fields north, sea south ----

-- city-map's beach colours, so the bands carry on past the sides unbroken.
local BEACH = {
  hill = { 0.33, 0.45, 0.24 }, hillDark = { 0.28, 0.39, 0.20 },
  camp = { 0.40, 0.42, 0.28 }, campDark = { 0.35, 0.36, 0.24 },
  mud = { 0.42, 0.36, 0.26 }, mudDark = { 0.36, 0.30, 0.21 },
  trench = { 0.25, 0.20, 0.14 },
  sand = { 0.84, 0.76, 0.55 }, sandDark = { 0.77, 0.68, 0.47 },
  wet = { 0.62, 0.58, 0.44 },
  sea = { 0.20, 0.42, 0.52 }, seaDeep = { 0.14, 0.32, 0.44 },
  foam = { 0.88, 0.93, 0.95 },
  steel = { 0.30, 0.30, 0.32 }, steelLight = { 0.48, 0.48, 0.50 },
}
local HEDGEROW_FIELD = 360 -- px across a field between hedgerows, north of the hill
local WIRE_POST_EVERY = 46 -- px between the barbed wire's posts
local SHIPS = {
  { out = 520, speed = 9, phase = 0, length = 150 },
  { out = 820, speed = -6, phase = 900, length = 190 },
}

--- A band of the beach from y0 to y1 across the whole view, speckled like
--- the map's (world-anchored, so it lines up at the edge).
local function beachBand(left, right, y0, y1, c, dark, every)
  love.graphics.setColor(c)
  love.graphics.rectangle("fill", left, y0, right - left, y1 - y0)
  love.graphics.setColor(dark)
  local x0 = math.floor(left / (every * 1.7)) * every * 1.7
  local i = 0
  for yy = y0 + 10, y1 - 30, every do
    for xx = x0 + (i % 3) * 37, right, every * 1.7 do
      love.graphics.rectangle("fill", xx + (yy * 7) % 23, yy, 34, 18)
    end
    i = i + 1
  end
end

--- A Czech hedgehog from above: three steel beams crossed.
local function hedgehog(x, y, a)
  love.graphics.setColor(BEACH.steel)
  love.graphics.setLineWidth(4)
  for k = 0, 2 do
    local b = a + k * math.pi / 3
    love.graphics.line(x - math.cos(b) * 12, y - math.sin(b) * 12, x + math.cos(b) * 12, y + math.sin(b) * 12)
  end
  love.graphics.setColor(BEACH.steelLight)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(x - math.cos(a) * 11, y - math.sin(a) * 11 - 1, x + math.cos(a) * 11, y + math.sin(a) * 11 - 1)
  love.graphics.setLineWidth(1)
end

--- Barbed wire down x from y0 to y1: posts, and coils of wire between them.
local function wire(x, y0, y1)
  love.graphics.setColor(0, 0, 0, 0.2)
  love.graphics.rectangle("fill", x - 8, y0, 20, y1 - y0) -- its shadow on the ground
  for y = y0, y1, WIRE_POST_EVERY do
    love.graphics.setColor(0.22, 0.24, 0.26, 0.95)
    love.graphics.setLineWidth(2)
    for k = 0, 3 do
      love.graphics.circle("line", x, y + 6 + k * 10, 9, 12)
    end
    love.graphics.setColor(0.35, 0.26, 0.16)
    love.graphics.rectangle("fill", x - 3.5, y - 3.5, 7, 7, 1)
  end
  love.graphics.setLineWidth(1)
end

--- A warship offshore from above: a grey hull, its decks, two turrets, a
--- funnel and a wake.
local function warship(x, y, length, dir)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(dir, 1)
  local L, W = length, length * 0.16
  love.graphics.setColor(BEACH.foam[1], BEACH.foam[2], BEACH.foam[3], 0.3)
  love.graphics.polygon("fill", -L * 0.5, -W * 0.4, -L * 1.1, -W * 1.2, -L * 1.1, W * 1.2, -L * 0.5, W * 0.4)
  love.graphics.setColor(0, 0, 0, 0.25)
  love.graphics.polygon("fill", -L * 0.5 + 6, -W / 2 + 6, L * 0.3 + 6, -W / 2 + 6, L * 0.5 + 6, 6, L * 0.3 + 6,
    W / 2 + 6, -L * 0.5 + 6, W / 2 + 6)
  love.graphics.setColor(0.45, 0.47, 0.5)
  love.graphics.polygon("fill", -L * 0.5, -W / 2, L * 0.3, -W / 2, L * 0.5, 0, L * 0.3, W / 2, -L * 0.5, W / 2)
  love.graphics.setColor(0.55, 0.57, 0.6)
  love.graphics.rectangle("fill", -L * 0.2, -W * 0.3, L * 0.3, W * 0.6, 3) -- the superstructure
  love.graphics.setColor(0.3, 0.31, 0.34)
  for _, tx in ipairs({ L * 0.22, -L * 0.34 }) do -- turrets, guns out
    love.graphics.circle("fill", tx, 0, W * 0.28, 12)
    love.graphics.setLineWidth(2)
    love.graphics.line(tx, 0, tx + (tx > 0 and 1 or -1) * W * 0.8, 0)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.18, 0.18, 0.2)
  love.graphics.circle("fill", -L * 0.05, 0, W * 0.16, 10) -- the funnel
  love.graphics.pop()
end

local function beach(map, camera)
  local left, top, right, bottom = view(camera)
  local B = map.bands
  local surf = B.surf
  -- North of the hill: fields between hedgerows, trees here and there.
  love.graphics.setColor(BEACH.hill)
  love.graphics.rectangle("fill", left, top, right - left, math.max(0, B.hill.y0 - top))
  if top < B.hill.y0 then
    -- Rows of fields, each row's hedges staggered and each field its own
    -- width, like a patchwork of farmland seen from the air.
    local f = HEDGEROW_FIELD
    local bottomRow = B.hill.y0 - 40
    local row = math.floor((bottomRow - top) / f) + 1
    for k = 0, row do
      local fy1 = bottomRow - k * f
      local fy0 = fy1 - f
      if fy1 > top then
        local shift = love.math.noise(k * 0.9, 3.3) * f
        local fx = math.floor((left - shift) / f) * f + shift - f
        while fx < right do
          local width = f * (0.7 + love.math.noise(fx * 0.013, k * 1.7) * 0.8)
          if love.math.noise(fx * 0.01, fy0 * 0.01) > 0.5 then
            love.graphics.setColor(BEACH.hillDark)
            love.graphics.rectangle("fill", fx + 8, fy0 + 8, width - 16, f - 16) -- a field ploughed darker
          end
          hedge(fx - 8, fy0, 16, f) -- the hedge between it and the next
          fx = fx + width
        end
        hedge(left, fy1 - 8, right - left, 16) -- along the bottom of the row
      end
    end
  end
  -- The bands, on along the coast both ways.
  beachBand(left, right, B.hill.y0, B.hill.y1, BEACH.hill, BEACH.hillDark, 70)
  beachBand(left, right, B.barracks.y0, B.barracks.y1, BEACH.camp, BEACH.campDark, 80)
  beachBand(left, right, B.bunkers.y0, B.bunkers.y1, BEACH.mud, BEACH.mudDark, 60)
  beachBand(left, right, B.beach.y0, B.beach.y1, BEACH.sand, BEACH.sandDark, 90)
  for _, t in ipairs(map.trenches or {}) do
    love.graphics.setColor(BEACH.trench)
    love.graphics.rectangle("fill", left, t.y, right - left, t.h)
    love.graphics.setColor(BEACH.mudDark)
    love.graphics.rectangle("fill", left, t.y, right - left, 6)
  end
  -- The sea: wet sand at the waterline, the surf, deep water on south.
  love.graphics.setColor(BEACH.wet)
  love.graphics.rectangle("fill", left, surf.y0 - 60, right - left, 60)
  love.graphics.setColor(BEACH.sea)
  love.graphics.rectangle("fill", left, surf.y0, right - left, math.max(0, bottom - surf.y0))
  local deep = surf.y0 + (surf.y1 - surf.y0) * 0.6
  love.graphics.setColor(BEACH.seaDeep)
  love.graphics.rectangle("fill", left, deep, right - left, math.max(0, bottom - deep))
  love.graphics.setColor(BEACH.foam)
  love.graphics.setLineWidth(4)
  for k = 0, 3 do
    local yy = surf.y0 + 4 + k * 70
    local pts = {}
    for xx = math.floor(left / 32) * 32, right + 32, 32 do
      pts[#pts + 1] = xx
      pts[#pts + 1] = yy + math.sin(xx / 60 + k) * 6
    end
    love.graphics.line(pts)
  end
  love.graphics.setLineWidth(1)
  crests(left, math.max(top, surf.y1), right, bottom)
  -- Hedgehogs strewn on the sand past the sides.
  local cell = 240
  for c = math.floor(left / cell), math.ceil(right / cell) do
    for r = math.floor(B.beach.y0 / cell), math.floor((B.beach.y1 - 40) / cell) do
      local n = love.math.noise(c * 0.63, r * 0.77)
      local x, y = (c + n) * cell, (r + (n * 3) % 1) * cell
      if n > 0.55 and y > B.beach.y0 + 30 and y < B.beach.y1 - 30 and outside(map, x, y) > 40 then
        hedgehog(x, y, n * 6)
      end
    end
  end
  -- Barbed wire fencing the battle off on both sides, from the hill down to the water.
  wire(map.left - 14, B.hill.y0, surf.y0 - 60)
  wire(map.left + map.w + 14, B.hill.y0, surf.y0 - 60)
  -- Warships steaming slowly along the coast, far out.
  for _, sh in ipairs(SHIPS) do
    local span = map.w + 2400
    local x = map.left - 1200 + ((sh.phase + clock * sh.speed) % span + span) % span
    local y = surf.y1 + sh.out
    if y - 40 < bottom and y + 40 > top and x + sh.length > left and x - sh.length < right then
      warship(x, y, sh.length, sh.speed > 0 and 1 or -1)
    end
  end
end

-- Shotgun's Bluff: the cliff runs on, walled in; a canyon north, woods south --

-- city-map's bluff colours, so the plateau, cliff and meadow carry on unbroken.
local CLIFF = {
  meadow = { 0.38, 0.52, 0.28 }, meadowDark = { 0.33, 0.46, 0.24 }, flowers = { 0.92, 0.86, 0.45 },
  plateau = { 0.55, 0.52, 0.36 }, plateauDark = { 0.49, 0.46, 0.31 },
  rock = { 0.47, 0.43, 0.38 }, rockDark = { 0.33, 0.30, 0.27 }, rockLight = { 0.60, 0.56, 0.50 },
  stone = { 0.62, 0.61, 0.58 }, stoneDark = { 0.46, 0.45, 0.43 },
}
local CLIFF_FACE = 70 -- px of rock from the lip down (city-map's layout)
local RIM = 70 -- px of plateau past the top edge before the canyon
local CANYON = 760 -- px across the canyon, rim to far rim
local RIVER = { 0.22, 0.45, 0.58 }
local BOULDER_CELL = 260 -- px between the boulders' grid points
local BLUFF_TREES = { 1, 3, 2, 5 }

--- Speckle the box (x0..x1, y0..y1) like the map's ground, anchored in the world.
local function speckles(x0, x1, y0, y1, dark, every)
  love.graphics.setColor(dark)
  local step = every * 1.7
  local i = math.floor(y0 / every)
  for yy = math.floor(y0 / every) * every + 10, y1 - 30, every do
    for xx = math.floor(x0 / step) * step + (i % 3) * 37, x1, step do
      love.graphics.rectangle("fill", xx + (yy * 7) % 23, yy, 34, 18)
    end
    i = i + 1
  end
end

--- The cliff from x0 to x1: rock from the lip down, a ragged lit lip,
--- cracks down the face, and its shadow on the meadow under it.
local function cliffFace(x0, x1, y)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", x0, y + 60, x1 - x0, 46)
  love.graphics.setColor(CLIFF.rockDark)
  love.graphics.rectangle("fill", x0, y, x1 - x0, CLIFF_FACE)
  love.graphics.setColor(CLIFF.rock)
  love.graphics.rectangle("fill", x0, y + 6, x1 - x0, CLIFF_FACE - 20)
  love.graphics.setColor(CLIFF.rockLight)
  local start = math.floor(x0 / 24) * 24
  for xx = start, x1, 24 do
    local a, b = y - 4 + (xx * 13) % 11, y - 4 + ((xx + 24) * 13) % 11
    love.graphics.polygon("fill", xx, a, xx + 24, b, xx + 24, y + 12, xx, y + 12)
  end
  love.graphics.setColor(CLIFF.rockDark)
  love.graphics.setLineWidth(3)
  for xx = math.floor(x0 / 57) * 57 + 30, x1, 57 do
    local jog = (xx * 7) % 17 - 8
    love.graphics.line(xx, y + 14, xx + jog, y + CLIFF_FACE * 0.5, xx - jog / 2, y + CLIFF_FACE - 8)
  end
  love.graphics.setLineWidth(1)
end

--- A dry-stone wall down x from y0 to y1: a dark bed, rounded stones.
local function stoneWall(x, y0, y1)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - 7, y0 + 5, 18, y1 - y0, 5)
  love.graphics.setColor(CLIFF.stoneDark)
  love.graphics.rectangle("fill", x - 9, y0, 18, y1 - y0, 5)
  for y = math.floor(y0 / 16) * 16, y1 - 8, 16 do
    local k = math.floor(y / 16)
    local k9 = k % 2 == 0 and 1 or 0.9
    love.graphics.setColor(CLIFF.stone[1] * k9, CLIFF.stone[2] * k9, CLIFF.stone[3] * k9)
    love.graphics.circle("fill", x, y + 8, 7 + k % 4 * 0.5, 8)
  end
end

--- A boulder: a lumpy grey heap lit from the top left, its shadow down right.
local function boulder(x, y, r)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + 6, y + 6, r * 1.1, 14)
  love.graphics.setColor(CLIFF.rockDark)
  love.graphics.circle("fill", x, y, r * 1.08, 14)
  love.graphics.setColor(CLIFF.rock)
  love.graphics.circle("fill", x - r * 0.12, y - r * 0.12, r * 0.8, 12)
  love.graphics.setColor(CLIFF.rockLight)
  love.graphics.circle("fill", x - r * 0.35, y - r * 0.35, r * 0.35, 10)
end

--- The canyon north of the plateau: the rim, sheer walls going down into
--- the dark, a river winding along the bottom, the far wall and the far
--- plateau beyond it.
local function canyon(left, right, rimY, top)
  local floor = rimY - CANYON / 2
  local far = rimY - CANYON
  -- The far plateau, hazy with distance.
  love.graphics.setColor(CLIFF.plateau[1] * 0.85, CLIFF.plateau[2] * 0.85, CLIFF.plateau[3] * 0.9)
  love.graphics.rectangle("fill", left, top, right - left, math.max(0, far - top))
  -- The walls, darker the deeper they go, both sides down to the river.
  local steps = 12
  for k = 0, steps - 1 do
    local t = k / steps
    local shade = 0.95 - t * 0.6
    love.graphics.setColor(CLIFF.rock[1] * shade, CLIFF.rock[2] * shade, CLIFF.rock[3] * shade)
    local y0 = far + (floor - far) * t -- the far wall, lit, going down
    love.graphics.rectangle("fill", left, y0, right - left, (floor - far) / steps + 1)
    local y1 = rimY - (rimY - floor) * (t + 1 / steps) -- our wall, in shadow
    love.graphics.setColor(CLIFF.rockDark[1] * shade, CLIFF.rockDark[2] * shade, CLIFF.rockDark[3] * shade)
    love.graphics.rectangle("fill", left, y1, right - left, (rimY - floor) / steps + 1)
  end
  -- Ledges and cracks down the walls.
  love.graphics.setLineWidth(2)
  for xx = math.floor(left / 90) * 90, right, 90 do
    local n = love.math.noise(xx * 0.01, 5.5)
    love.graphics.setColor(0, 0, 0, 0.25)
    love.graphics.line(xx, far + 20, xx + (n - 0.5) * 40, far + (floor - far) * 0.6)
    love.graphics.line(xx + 40, rimY - 30, xx + 40 + (n - 0.5) * 50, rimY - (rimY - floor) * 0.7)
  end
  -- The river, winding along the bottom and glinting.
  local pts = {}
  for xx = math.floor(left / 30) * 30 - 30, right + 30, 30 do
    pts[#pts + 1] = xx
    pts[#pts + 1] = floor + math.sin(xx / 260) * 40 + math.sin(xx / 90) * 8
  end
  if #pts >= 4 then
    love.graphics.setColor(RIVER)
    love.graphics.setLineWidth(26)
    love.graphics.line(pts)
    love.graphics.setColor(0.6, 0.8, 0.9, 0.5)
    love.graphics.setLineWidth(3)
    for i = 1, #pts - 3, 6 do
      local g = (clock * 60 + pts[i]) % 60
      love.graphics.line(pts[i] + g, pts[i + 1] - 4, pts[i] + g + 12, pts[i + 1] - 4)
    end
  end
  love.graphics.setLineWidth(1)
  -- Our rim: the plateau's ragged edge, lit.
  love.graphics.setColor(CLIFF.rockLight)
  for xx = math.floor(left / 24) * 24, right, 24 do
    local a, b = rimY - 6 - (xx * 7) % 9, rimY - 8 - (xx * 13) % 9
    love.graphics.polygon("fill", xx, rimY, xx + 24, rimY, xx + 24, b, xx, a)
  end
end

local function bluff(map, camera)
  local left, top, right, bottom = view(camera)
  local cy = map.cliffY
  local rimY = map.top - RIM
  local south = map.top + map.h
  -- The plateau, on north to the canyon's rim, and the canyon beyond it.
  love.graphics.setColor(CLIFF.plateau)
  love.graphics.rectangle("fill", left, math.max(top, rimY), right - left, cy - math.max(top, rimY))
  speckles(left, right, math.max(top, rimY), cy, CLIFF.plateauDark, 70)
  if top < rimY then
    canyon(left, right, rimY, top)
  end
  -- The meadow below the cliff, flowered, on south into woods.
  love.graphics.setColor(CLIFF.meadow)
  love.graphics.rectangle("fill", left, cy, right - left, math.max(0, bottom - cy))
  speckles(left, right, cy, bottom, CLIFF.meadowDark, 80)
  love.graphics.setColor(CLIFF.flowers)
  local fc = 48
  for c = math.floor(left / fc), math.ceil(right / fc) do
    for r = math.floor(math.max(top, cy + 120) / fc), math.ceil(bottom / fc) do
      local n = love.math.noise(c * 0.53, r * 0.61)
      if n > 0.62 then
        love.graphics.rectangle("fill", (c + n) * fc, (r + (n * 5) % 1) * fc, 4, 4)
      end
    end
  end
  -- The cliff, on across both sides.
  cliffFace(left, map.left, cy)
  cliffFace(map.left + map.w, right, cy)
  -- Boulders here and there on the plateau and the meadow.
  for c = math.floor(left / BOULDER_CELL), math.ceil(right / BOULDER_CELL) do
    for r = math.floor(math.max(top, rimY) / BOULDER_CELL), math.ceil(bottom / BOULDER_CELL) do
      local n = love.math.noise(c * 0.81, r * 0.67)
      local x, y = (c + n) * BOULDER_CELL, (r + (n * 3) % 1) * BOULDER_CELL
      local offCliff = y < cy - 40 or y > cy + CLIFF_FACE + 60
      if n > 0.6 and offCliff and y > rimY + 30 and y < south + 60 and outside(map, x, y) > 60 then
        boulder(x, y, 14 + n * 14)
      end
    end
  end
  -- Woods south of the meadow.
  local function north(_, y)
    return y < south + 40
  end
  woods(map, camera, 150, 90, BLUFF_TREES, north)
  -- Dry-stone walls down both sides, over the cliff's lip only where there is ground.
  stoneWall(map.left - 18, math.max(top, rimY + 10), cy - 6)
  stoneWall(map.left + map.w + 18, math.max(top, rimY + 10), cy - 6)
  stoneWall(map.left - 18, cy + CLIFF_FACE + 4, math.min(bottom, south + 120))
  stoneWall(map.left + map.w + 18, cy + CLIFF_FACE + 4, math.min(bottom, south + 120))
end

-- The outskirts: a fence, then farmland -------------------------------------

local FENCE_OUT = 60 -- px of grass past the edge before the fence
local FIELDS_OUT = 110 -- px out where the fields start
local FIELD_W, FIELD_H = 430, 300 -- a field's size, give or take
local TRACK = 22 -- px of dirt track between fields
local DIRT = { 0.45, 0.37, 0.27 }
local DIRT_DARK = { 0.39, 0.32, 0.23 }
local RAIL = { 0.5, 0.36, 0.22 }
local CROPS = { -- a field's colour and the colour of its rows
  { { 0.78, 0.68, 0.35 }, { 0.68, 0.58, 0.28 } }, -- wheat
  { { 0.35, 0.55, 0.25 }, { 0.27, 0.45, 0.19 } }, -- green crops
  { { 0.45, 0.36, 0.26 }, { 0.36, 0.28, 0.2 } }, -- ploughed
  { { 0.36, 0.46, 0.27 }, { 0.33, 0.43, 0.25 } }, -- fallow
  { { 0.62, 0.64, 0.3 }, { 0.52, 0.55, 0.24 } }, -- rapeseed going over
}

--- The field at (fx, fy, w, h): its crop in rows, one way or the other.
local function field(fx, fy, w, h, n)
  local crop = CROPS[math.floor(n * 53) % #CROPS + 1]
  love.graphics.setColor(crop[1])
  love.graphics.rectangle("fill", fx, fy, w, h, 4)
  love.graphics.setColor(crop[2])
  love.graphics.setLineWidth(3)
  if n > 0.5 then
    for y = fy + 8, fy + h - 4, 12 do
      love.graphics.line(fx + 6, y, fx + w - 6, y)
    end
  else
    for x = fx + 8, fx + w - 4, 12 do
      love.graphics.line(x, fy + 6, x, fy + h - 6)
    end
  end
  love.graphics.setLineWidth(1)
end

--- A post-and-rail fence round the box (x, y, w, h).
local function fence(x, y, w, h)
  love.graphics.setColor(0, 0, 0, 0.22)
  love.graphics.setLineWidth(5)
  love.graphics.rectangle("line", x + 4, y + 4, w, h)
  love.graphics.setColor(RAIL)
  love.graphics.rectangle("line", x, y, w, h)
  love.graphics.setColor(RAIL[1] * 1.25, RAIL[2] * 1.25, RAIL[3] * 1.25)
  love.graphics.setLineWidth(1.5)
  love.graphics.rectangle("line", x - 1, y - 1, w, h) -- light along the rail's top
  love.graphics.setLineWidth(1)
  love.graphics.setColor(RAIL[1] * 0.7, RAIL[2] * 0.7, RAIL[3] * 0.7)
  for px = x, x + w, 48 do
    love.graphics.rectangle("fill", px - 5, y - 5, 10, 10, 2)
    love.graphics.rectangle("fill", px - 5, y + h - 5, 10, 10, 2)
  end
  for py = y, y + h, 48 do
    love.graphics.rectangle("fill", x - 5, py - 5, 10, 10, 2)
    love.graphics.rectangle("fill", x + w - 5, py - 5, 10, 10, 2)
  end
end

--- A building from above: a pitched roof in `roof` with its ridge, a shadow.
local function building(x, y, w, h, roof)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x + 8, y + 8, w, h)
  love.graphics.setColor(roof)
  love.graphics.rectangle("fill", x, y, w, h / 2)
  love.graphics.setColor(roof[1] * 0.78, roof[2] * 0.78, roof[3] * 0.78)
  love.graphics.rectangle("fill", x, y + h / 2, w, h / 2)
  love.graphics.setColor(roof[1] * 0.6, roof[2] * 0.6, roof[3] * 0.6)
  love.graphics.setLineWidth(3)
  love.graphics.line(x, y + h / 2, x + w, y + h / 2)
  love.graphics.setLineWidth(1)
end

--- A tractor from above, going along `angle`: a green body, a cab, big back wheels.
local function tractor(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  love.graphics.scale(1.8) -- a tractor is bigger than a car
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", -12, -9, 28, 20, 3)
  love.graphics.setColor(0.12, 0.12, 0.12)
  love.graphics.rectangle("fill", -12, -12, 10, 5, 2) -- back wheels
  love.graphics.rectangle("fill", -12, 7, 10, 5, 2)
  love.graphics.rectangle("fill", 8, -9, 6, 3, 1) -- front wheels
  love.graphics.rectangle("fill", 8, 6, 6, 3, 1)
  love.graphics.setColor(0.2, 0.5, 0.2)
  love.graphics.rectangle("fill", -10, -7, 26, 14, 3)
  love.graphics.setColor(0.8, 0.85, 0.9)
  love.graphics.rectangle("fill", -9, -5, 9, 10, 2) -- the cab roof
  love.graphics.pop()
end

local function outskirts(map, camera)
  local left, top, right, bottom = view(camera)
  -- The grass carries on, worn in patches as the map's is.
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
  -- The fields: rows of them, each row staggered and each field its own
  -- width, dirt tracks between, none nearer the map than FIELDS_OUT.
  local x0, y0 = map.left - FIELDS_OUT, map.top - FIELDS_OUT
  local x1, y1 = map.left + map.w + FIELDS_OUT, map.top + map.h + FIELDS_OUT
  for k = math.floor(top / FIELD_H), math.ceil(bottom / FIELD_H) do
    local fy = k * FIELD_H
    love.graphics.setColor(DIRT)
    if fy + TRACK < y0 or fy > y1 then
      love.graphics.rectangle("fill", left, fy, right - left, TRACK) -- the track along the row
    else -- not across the grass round the map: either side of it
      love.graphics.rectangle("fill", left, fy, math.max(0, x0 - left), TRACK)
      love.graphics.rectangle("fill", x1, fy, math.max(0, right - x1), TRACK)
    end
    local shift = love.math.noise(k * 0.9, 7.7) * FIELD_W
    local fx = math.floor((left - shift) / FIELD_W) * FIELD_W + shift - FIELD_W
    while fx < right do
      local width = FIELD_W * (0.7 + love.math.noise(fx * 0.011, k * 1.3) * 0.8)
      local ax, ay, bx, by = fx, fy + TRACK, fx + width - TRACK, fy + FIELD_H
      local clear = bx < x0 or ax > x1 or by < y0 or ay > y1 -- nowhere near the map
      if clear then
        love.graphics.setColor(DIRT)
        love.graphics.rectangle("fill", bx, fy, TRACK, FIELD_H) -- the track down its side
        love.graphics.setColor(DIRT_DARK)
        love.graphics.rectangle("fill", bx + 8, fy, 3, FIELD_H) -- a rut
        field(ax, ay, bx - ax, by - ay, love.math.noise(fx * 0.017, k * 0.71))
      end
      fx = fx + width
    end
  end
  -- A lone tree at some field corners.
  local pics = treePictures()
  for k = math.floor(top / FIELD_H), math.ceil(bottom / FIELD_H) do
    for c = math.floor(left / FIELD_W), math.ceil(right / FIELD_W) do
      local n = love.math.noise(c * 0.77, k * 0.93)
      local x, y = c * FIELD_W + n * 60, k * FIELD_H + 10
      if n > 0.62 and outside(map, x, y) > FIELDS_OUT then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(pics[n > 0.8 and 3 or 5], x, y, 0, 1.1, 1.1, TREE_SIZE / 2, TREE_SIZE / 2)
      end
    end
  end
  -- The farm, off the left side, and its tractor working the field beside it.
  local farmX, farmY = map.left - 620, map.top + map.h * 0.35
  if farmX + 300 > left and farmX - 50 < right and farmY + 260 > top and farmY - 60 < bottom then
    love.graphics.setColor(DIRT)
    love.graphics.rectangle("fill", farmX - 30, farmY - 30, 320, 250, 8) -- the yard
    building(farmX, farmY, 120, 90, { 0.62, 0.55, 0.5 }) -- the farmhouse
    building(farmX + 150, farmY + 10, 110, 150, { 0.62, 0.18, 0.14 }) -- the barn
  end
  local tx0, ty0, span = farmX - 20, farmY + 280, 280
  local k = (clock * 0.05) % 2
  local along = k < 1 and k or 2 - k
  local lane = math.floor(clock * 0.05) % 6
  tractor(tx0 + along * span, ty0 + lane * 30, k < 1 and 0 or math.pi)
  -- The fence all round, a little out from the edge.
  fence(map.left - FENCE_OUT, map.top - FENCE_OUT, map.w + 2 * FENCE_OUT, map.h + 2 * FENCE_OUT)
end

local DRAW = {
  city = function(map, camera)
    sea(map, camera)
    boats(map, camera)
  end,
  forest = forest,
  culdesac = culdesac,
  beach = beach,
  cliff = bluff,
  outskirts = outskirts,
  city17 = function(map, camera)
    local left, top, right, bottom = view(camera)
    City17.draw(map, camera, left, top, right, bottom, clock)
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
