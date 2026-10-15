-- The Winding Road past its edges (surroundings' entry for `road`): the
-- mountains run on both ways, shaded and forested as the map's own are
-- (city-map's render_road.lua, on render_coast.lua's relief), the trees
-- thinning out higher up and further north. The road and the river run on
-- out of both ends of the map down their valley: south along the valley
-- floor, wandering a little, and north towards the Citadel, where the
-- river narrows to the stream it starts as and stops under the snow. The
-- snow comes further down the mountains the further north they stand,
-- and lies on the verges and the pines up there too; past the bottom
-- there is none.
--
-- The mountains past the edge stand as high as how far they are from open
-- ground, the map's or the road's and river's past it, the same way the
-- map's own do, so its edge meets them without a seam: the ridges come
-- from the same noise, lit from the same side. Everything is worked out
-- from where it sits, the same on every machine and never running out,
-- and drawn once into chunks (chunks.lua).

local Layout = require("src.features.city-map.layout")
local Coast = require("src.features.city-map.coast")
local RenderCoast = require("src.features.city-map.render_coast")
local Road = require("src.features.city-map.road")
local Chunks = require("src.features.surroundings.chunks")

local WindingRoad = {}

local T = Layout.TILE
local SUB = 4 -- cells a tile is drawn in, each way (render_coast.lua's)
local PAD = 14 -- tiles round the map that the mountains' height is worked out over exactly
local FAR = 12 -- tiles from open ground past which a mountain is as high as it gets
local WANDER = 2.5 -- tiles the road and the river wander either way past the ends
local SOURCE = 22 -- rows past the top the river's stream runs on before it gives out

local hash, mix = RenderCoast.hash, RenderCoast.mix

-- render_road.lua's colours, so the edge doesn't show.
local C = {
  grass = { 0.40, 0.56, 0.27 }, grassLight = { 0.48, 0.64, 0.32 }, grassDark = { 0.32, 0.47, 0.22 },
  pebble = { 0.62, 0.60, 0.55 }, pebbleDark = { 0.46, 0.45, 0.41 }, shallow = { 0.26, 0.56, 0.62 },
  deep = { 0.10, 0.30, 0.42 }, flow = { 0.70, 0.88, 0.92 }, gravel = { 0.56, 0.52, 0.45 },
  gravelDark = { 0.44, 0.41, 0.36 }, asphalt = { 0.24, 0.24, 0.26 }, asphaltLight = { 0.30, 0.30, 0.32 },
  edge = { 0.88, 0.88, 0.84 }, centre = { 0.92, 0.78, 0.28 }, foot = { 0.40, 0.54, 0.27 },
  slope = { 0.24, 0.43, 0.21 }, high = { 0.18, 0.33, 0.18 }, peak = { 0.30, 0.44, 0.25 }, rock = { 0.50, 0.49, 0.46 },
  snow = { 0.93, 0.95, 0.98 }, stone = { 0.52, 0.50, 0.46 }, stoneDark = { 0.38, 0.37, 0.34 },
  shadow = { 0, 0, 0, 0.28 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

local chunks = Chunks.new(1024, 24, 1)

-- The lines past the ends -------------------------------------------------------

--- How far past the map's ends row `r` (tiles, may be fractional) lies:
--- negative above the top, positive below the bottom, 0 beside the map.
local function past(map, r)
  if r < 0 then
    return r
  elseif r > map.rows then
    return r - map.rows
  end
  return 0
end

--- How far the valley has wandered from straight at row `r`: nothing at
--- the map's edge, easing in further out. The road and the river wander
--- together, so they never meet.
local function wander(map, r)
  local p = past(map, r)
  if p == 0 then
    return 0
  end
  local fade = math.min(1, math.abs(p) / 24)
  return (love.math.noise(r * 0.035, p < 0 and 3.3 or 7.7) - 0.5) * 2 * WANDER * fade
end

--- The road's middle column at row `r` past the ends.
local function roadAt(map, r)
  local p = r < map.rows / 2 and Road.ROAD[#Road.ROAD] or Road.ROAD[1]
  return p[1] + wander(map, r)
end

--- The river's middle column at row `r` past the ends, its half width and
--- its banks (tiles). North it narrows to nothing past its source.
local function riverAt(map, r)
  local p = r < map.rows / 2 and Road.RIVER[1] or Road.RIVER[#Road.RIVER]
  local half = p[3]
  if r < p[2] and r < 0 then
    half = half * math.max(0, 1 - (p[2] - r) / SOURCE)
  end
  return p[1] + wander(map, r), half, p[4]
end

--- What tile (c, r) past the map is: "water", "road" (the tarmac), "ground"
--- (verge and banks) or nil for the mountains. Beside the map only mountains.
local function kindAt(map, c, r)
  if r >= 0 and r < map.rows then
    return nil
  end
  local y = r + 0.5
  local x = c + 0.5
  local rc, wc, half, banks = roadAt(map, y), riverAt(map, y)
  local dr, dw = math.abs(x - rc), math.abs(x - wc)
  if half > 0.15 and dw <= half then
    return "water"
  elseif dr <= Road.ASPHALT + 0.5 then
    return "road"
  elseif dr <= Road.VERGE or (half > 0.15 and dw <= half + banks) then
    return "ground"
  end
  return nil
end

--- Is tile (c, r) open ground (anything but the mountains), in the map or past it?
local function open(map, c, r)
  if c >= 0 and c < map.cols and r >= 0 and r < map.rows then
    return map.tiles[c][r] ~= nil
  end
  return kindAt(map, c, r) ~= nil
end

-- How high the mountains stand --------------------------------------------------

local field = { map = nil } -- tiles from open ground over the map and PAD round it

local function heights(map)
  if field.map == map then
    return field
  end
  local cols, rows = map.cols + 2 * PAD, map.rows + 2 * PAD
  local d = Coast.distances(cols, rows, function(c, r)
    return open(map, c - PAD, r - PAD)
  end, function()
    return true
  end)
  field = { map = map, d = d }
  return field
end

--- Tiles from the nearest open ground for mountain tile (c, r) past the map,
--- at most FAR.
local function heightOut(map, c, r)
  local f = heights(map)
  local col = f.d[c + PAD]
  local h = col and col[r + PAD]
  if h then
    return math.min(FAR, h)
  end
  if past(map, r) == 0 then
    return FAR
  end
  -- Far out past the ends: across to the road or the river's valley.
  local y, x = r + 0.5, c + 0.5
  local wc, half, banks = riverAt(map, y)
  local toRoad = math.abs(x - roadAt(map, y)) - Road.VERGE
  local toRiver = half > 0.15 and math.abs(x - wc) - half - banks or FAR
  return clamp(math.min(toRoad, toRiver), 0.5, FAR)
end

--- Tile (c, r)'s height for the relief: the map's own inside it, 0 on open ground.
local function heightAt(map, c, r)
  if c >= 0 and c < map.cols and r >= 0 and r < map.rows then
    return map.height[c][r] or 0
  end
  if kindAt(map, c, r) then
    return 0
  end
  return heightOut(map, c, r)
end

--- Smooth noise over tile corners, -1..1 (render_coast.lua's ridges): a
--- lattice every `every` tiles with an eased step between its points.
local function ridgeNoise(c, r, every, seed)
  local i, j = math.floor(c / every), math.floor(r / every)
  local u, v = c / every - i, r / every - j
  u = u * u * (3 - 2 * u)
  v = v * v * (3 - 2 * v)
  local p00 = hash(i * 12.9898 + j * 78.233 + seed) * 2 - 1
  local p10 = hash((i + 1) * 12.9898 + j * 78.233 + seed) * 2 - 1
  local p01 = hash(i * 12.9898 + (j + 1) * 78.233 + seed) * 2 - 1
  local p11 = hash((i + 1) * 12.9898 + (j + 1) * 78.233 + seed) * 2 - 1
  local a, b = p00 + (p10 - p00) * u, p01 + (p11 - p01) * u
  return a + (b - a) * v
end

--- Is tile corner (c, r) on the map's edge?
local function onEdge(map, c, r)
  local inside = c >= 0 and c <= map.cols and r >= 0 and r <= map.rows
  return inside and (c == 0 or r == 0 or c == map.cols or r == map.rows)
end

--- How high tile corner (c, r) stands, as render_coast.lua's relief works
--- it out. On the map's edge exactly as the map has it, which counts
--- nothing past its edge, so the two meet there without a step.
local function elevation(map, c, r)
  local edge = onEdge(map, c, r)
  local function at(cc, rr)
    if edge and not (cc >= 0 and cc < map.cols and rr >= 0 and rr < map.rows) then
      return 0
    end
    return heightAt(map, cc, rr)
  end
  local h = (at(c - 1, r - 1) + at(c, r - 1) + at(c - 1, r) + at(c, r)) / 4
  if h <= 0 then
    return 0
  end
  local ridges = ridgeNoise(c, r, 7, 3.1) * 0.65 + ridgeNoise(c, r, 3, 8.7) * 0.35
  return (1 - math.exp(-h / 2.5)) * (5 + ridges * 3) + math.min(h, 4) * 0.25
end

--- How far up the snow starts on row `r`: only the tops at the map's
--- north end, lower and lower past it, none south of the map.
local function snowline(map, r)
  return math.max(2.6, 10.6 - (1 - r / map.rows) * 4.6)
end

-- Drawing a chunk -------------------------------------------------------------

--- How much snow lies on open ground at row `r`: none in the map's own
--- rows, settling in past the top.
local function snowCover(r)
  return r < 0 and clamp((-r - 4) / 26, 0, 0.8) or 0
end

local function ground(map, c, r)
  local x, y = map.x0 + c * T, map.y0 + r * T
  local s = snowCover(r)
  color(mix(C.grass, C.snow, s))
  love.graphics.rectangle("fill", x, y, T, T)
  for i = 0, 5 do
    local h = hash(c * 13.1 + r * 7.7 + i)
    color(mix(i % 2 == 0 and C.grassLight or C.grassDark, C.snow, s), 0.6)
    love.graphics.circle("fill", x + hash(h * 91) * T, y + hash(h * 57) * T, 6 + hash(h * 33) * 10)
  end
end

--- The river through tile (c, r), cell by cell: shallow at the banks, dark
--- down the middle; ground where it doesn't reach.
local function water(map, c, r)
  local s = T / SUB
  for j = 0, SUB - 1 do
    local yr = r + (j + 0.5) / SUB
    local wc, half = riverAt(map, yr)
    for i = 0, SUB - 1 do
      local into = half - math.abs(c + (i + 0.5) / SUB - wc)
      if into >= 0 then
        color(mix(C.shallow, C.deep, (into - 0.4) / 1.6))
        love.graphics.rectangle("fill", map.x0 + c * T + i * s, map.y0 + r * T + j * s, s, s)
      end
    end
  end
end

--- The road's and the river's lines over rows (r0, r1): the verge, the
--- tarmac with its edge lines and dashes, and pebbles along the banks.
local function lines(map, r0, r1)
  local from, to = r0 - 2, r1 + 2
  if from >= 0 and to <= map.rows then
    return
  end
  local half = Road.ASPHALT * T
  -- Only the stretch past one end: a chunk is never tall enough to reach both.
  if to > map.rows then
    from = math.max(from, map.rows - 1)
  else
    to = math.min(to, 1)
  end
  local pts = {}
  for r = from, to, 0.25 do
    pts[#pts + 1] = { x = map.x0 + roadAt(map, r) * T, y = map.y0 + r * T }
  end
  local function stroke(width, off, every)
    local flat = {}
    for i = 1, #pts, every do
      flat[#flat + 1], flat[#flat + 2] = pts[i].x + off, pts[i].y
    end
    if #flat >= 4 then
      love.graphics.setLineWidth(width)
      love.graphics.line(flat)
    end
  end
  local s = snowCover(r0)
  color(mix(C.gravelDark, C.snow, s * 0.6))
  stroke(half * 2 + 44, 0, 1)
  color(mix(C.gravel, C.snow, s * 0.5))
  stroke(half * 2 + 30, 0, 1)
  color(C.asphalt)
  stroke(half * 2, 0, 1)
  color(C.asphaltLight, 0.5)
  stroke(22, -half * 0.5, 1)
  stroke(22, half * 0.5, 1)
  color(C.edge)
  stroke(4, -(half - 8), 1)
  stroke(4, half - 8, 1)
  -- The dashed line down the middle: 40 px on, 40 off, anchored in the world.
  color(C.centre)
  love.graphics.setLineWidth(4)
  for i = 2, #pts do
    local a, b = pts[i - 1], pts[i]
    if math.floor(a.y / 40) % 2 == 0 then
      love.graphics.line(a.x, a.y, b.x, b.y)
    end
  end
  -- Pebbles where the river meets its banks, and streaks of its current.
  for r = math.floor(from * 4) / 4, to, 0.25 do
    local wc, wh = riverAt(map, r)
    if past(map, r) ~= 0 and wh > 0.15 then
      local y = map.y0 + r * T
      for side = -1, 1, 2 do
        local x = map.x0 + (wc + side * wh) * T
        local rad = 5 + hash(r * 7.3 + side) * 6
        color(C.pebbleDark)
        love.graphics.ellipse("fill", x + 1, y + 2, rad + 2, rad * 0.8 + 2)
        color(hash(r * 3.1 + side) < 0.5 and C.pebble or C.stone)
        love.graphics.ellipse("fill", x, y, rad, rad * 0.8)
      end
      if hash(r * 1.37) < 0.25 then
        local across = (hash(r * 2.11) * 2 - 1) * wh * 0.7
        color(C.flow, 0.35 + hash(r * 0.7) * 0.25)
        love.graphics.setLineWidth(3)
        love.graphics.line(map.x0 + (wc + across) * T, y, map.x0 + (wc + across) * T, y + 14 + hash(r) * 22)
      end
    end
  end
  love.graphics.setLineWidth(1)
end

--- The mountains over tile (c, r), cell by cell, from the corners' heights
--- and light (`elev`, `lit`, keyed by corner).
local function mountain(map, c, r, elev, lit)
  local a, b, d, e = elev[c][r], elev[c + 1][r], elev[c][r + 1], elev[c + 1][r + 1]
  local la, lb, ld, le = lit[c][r], lit[c + 1][r], lit[c][r + 1], lit[c + 1][r + 1]
  local line = snowline(map, r)
  local bare = line - 1.4 -- the trees give out to rock below the snow
  local s = T / SUB
  local x0, y0 = map.x0 + c * T, map.y0 + r * T
  for i = 0, SUB - 1 do
    for j = 0, SUB - 1 do
      local u, v = (i + 0.5) / SUB, (j + 0.5) / SUB
      local top, bottom = a + (b - a) * u, d + (e - d) * u
      local h = top + (bottom - top) * v
      local lt, lbm = la + (lb - la) * u, ld + (le - ld) * u
      local l = lt + (lbm - lt) * v
      local x, y = x0 + i * s, y0 + j * s
      local base
      if h < 1 then
        base = mix(C.foot, C.slope, h)
      elseif h < 5 then
        base = mix(C.slope, C.high, (h - 1) / 4)
      else
        base = mix(C.high, C.peak, (h - 5) / 3)
      end
      if h > bare then
        base = mix(base, C.rock, (h - bare) / 1.4 * (0.7 + hash(x * 0.013 + y * 0.029) * 0.3))
      end
      if h > line then
        base = mix(C.rock, C.snow, math.min(1, (h - line) * 1.6))
      end
      local k = l * (0.97 + hash(x * 0.37 + y * 0.11) * 0.06)
      love.graphics.setColor(base[1] * k, base[2] * k, base[3] * k)
      love.graphics.rectangle("fill", x, y, s, s)
      if h > 1.2 and h < line and (h * 1.4) % 1 < 0.09 then -- a contour line, under the snow
        love.graphics.setColor(base[1] * l * 0.8, base[2] * l * 0.8, base[3] * l * 0.8, 0.7)
        love.graphics.rectangle("fill", x, y, s, s)
      end
    end
  end
end

--- A boulder at (x, y), `rad` across, its shadow cast away from the
--- mountain (dx, dy), a lighter top: stone or bare rock.
local function boulder(x, y, rad, dx, dy, rock)
  color(C.shadow)
  love.graphics.ellipse("fill", x + dx * 4 + 3, y + dy * 4 + 4, rad, rad * 0.8)
  color(C.stoneDark)
  love.graphics.ellipse("fill", x, y, rad, rad * 0.8)
  color(rock and C.rock or C.stone)
  love.graphics.ellipse("fill", x - 2, y - 2, rad * 0.8, rad * 0.62)
end

--- Boulders tumbled along a mountain tile's foot where it meets open
--- ground, as the map's own (render_road.lua), hiding the tile edges.
local function boulders(map, c, r)
  local x, y = map.x0 + c * T, map.y0 + r * T
  for n, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    if open(map, c + e[1], r + e[2]) then
      for k = 0, 2 do
        local along = (k + 0.2 + hash(c * 1.9 + r * 4.1 + k + n) * 0.6) / 3
        local edge = e[1] + e[2] < 0 and 6 or T - 6
        local bx = e[1] == 0 and x + along * T or x + edge
        local by = e[2] == 0 and y + along * T or y + edge
        boulder(bx, by, 10 + hash(c * 7.3 + r * 2.9 + k) * 12, e[1], e[2], k % 2 == 1)
      end
    end
  end
end

--- The trees on mountain tile (c, r): thick low down, thinning higher up
--- and further north, none on the rock and snow; pines more the further
--- north, snow on them up there.
local function treesOn(map, c, r, elev, out)
  local h = heightAt(map, c, r)
  local north = 1 - r / map.rows
  local chance = math.max(0.15, 0.95 - h / 12 - north * 0.35)
  if north > 1 then
    chance = chance * math.max(0, 1 - (north - 1) * 6) -- the treeline
  end
  for k = 1, 2 do
    local seed = c * 31.7 + r * 17.3 + k * 5.1
    if h > 0.6 and hash(seed) < 0.7 * chance then
      local u, v = hash(seed + 1), hash(seed + 2)
      local top = elev[c][r] + (elev[c + 1][r] - elev[c][r]) * u
      local bottom = elev[c][r + 1] + (elev[c + 1][r + 1] - elev[c][r + 1]) * u
      if top + (bottom - top) * v < snowline(map, r) - 0.6 then
        out[#out + 1] = { x = map.x0 + (c + u) * T, y = map.y0 + (r + v) * T, r = 13 + hash(seed + 3) * 12,
          pine = hash(seed + 4) < 0.4 + north * 0.5, snow = north > 0.65 }
      end
    end
  end
end

local function paint(map, x0, y0, x1, y1)
  local c0, c1 = math.floor((x0 - map.x0) / T) - 1, math.floor((x1 - map.x0) / T) + 1
  local r0, r1 = math.floor((y0 - map.y0) / T) - 1, math.floor((y1 - map.y0) / T) + 1
  -- Every corner's height and light, one further round for the light.
  local raw, elev, lit = {}, {}, {}
  for c = c0 - 1, c1 + 2 do
    raw[c] = {}
    for r = r0 - 1, r1 + 2 do
      raw[c][r] = elevation(map, c, r)
    end
  end
  for c = c0, c1 + 1 do
    elev[c], lit[c] = raw[c], {}
    for r = r0, r1 + 1 do
      local lc, lr, hc, hr = c - 1, r - 1, c + 1, r + 1
      if onEdge(map, c, r) then -- the map's own light there: its corners only
        lc, lr, hc, hr = math.max(0, lc), math.max(0, lr), math.min(map.cols, hc), math.min(map.rows, hr)
      end
      lit[c][r] = clamp(1 + (raw[lc][lr] - raw[hc][hr]) * 0.32, 0.62, 1.3)
    end
  end
  local inMap = function(c, r)
    return c >= 0 and c < map.cols and r >= 0 and r < map.rows
  end
  for c = c0, c1 do
    for r = r0, r1 do
      if not inMap(c, r) and kindAt(map, c, r) then
        ground(map, c, r)
      end
    end
  end
  lines(map, r0, r1)
  for c = c0, c1 do
    for r = r0, r1 do
      if not inMap(c, r) and kindAt(map, c, r) == "water" then
        water(map, c, r)
      end
    end
  end
  local trees = {}
  for c = c0, c1 do
    for r = r0, r1 do
      if not inMap(c, r) and not kindAt(map, c, r) then
        mountain(map, c, r, elev, lit)
      end
    end
  end
  for c = c0, c1 do
    for r = r0, r1 do
      if not inMap(c, r) and not kindAt(map, c, r) then
        boulders(map, c, r)
        treesOn(map, c, r, elev, trees)
      end
    end
  end
  table.sort(trees, function(a, b) -- top to bottom, the nearer canopy over the one behind
    return a.y < b.y
  end)
  for _, t in ipairs(trees) do
    RenderCoast.drawSlopeTree(t)
    if t.pine and t.snow then
      color(C.snow, 0.8)
      love.graphics.circle("fill", t.x - t.r * 0.25, t.y - t.r * 0.3, t.r * 0.35)
    end
  end
end

--- Draw it all over the box (left, top, right, bottom) the camera sees.
function WindingRoad.draw(map, left, top, right, bottom)
  color(C.high) -- under any chunk not made yet
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  chunks:draw(map, left, top, right, bottom, function(x0, y0, x1, y1)
    paint(map, x0, y0, x1, y1)
  end)
end

return WindingRoad
