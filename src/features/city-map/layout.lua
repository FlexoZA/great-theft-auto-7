-- City layout: a deterministic grid of roads and blocks generated from a
-- seed, so every machine builds the identical map. The city can grow by
-- whole blocks past its limits (`Layout.grow`); every machine grows it the
-- same way in the same order, so they still agree. Blocks hold buildings
-- (with alleys), parks (with trees) or parking lots. Everything solid ends
-- up in `solids`, bucketed into a coarse grid for fast collision queries.
--
-- `Layout.generate` takes a spec ({ seed, cols, rows, plots, empty, crowd,
-- traffic, kind }) so the same generator builds every map the game knows
-- (city-map's `maps` table lists them); a bare number is the seed of a
-- city-sized map. An `empty` map is open ground inside the same walls: every
-- tile is "ground", no blocks. `crowd = false` and `traffic = false` keep
-- pedestrians, officers and NPC cars off it (those features read the flags).
-- `kind = "culdesac"` builds a suburban dead end instead of a grid: one
-- street in from the bottom edge, a turning circle at the top, houses on
-- their lawns either side (see `buildCuldesac`). `kind = "forest"` is open
-- ground thick with trees and shrubs, a trail winding through clearings
-- (see `buildForest`). `kind = "beach"` is a landing beach under a defended
-- hill: surf, sand with tank stoppers, bunkers and trenches, barracks and a
-- flag on the hilltop (see `buildBeach`). `kind = "arena"` is the turf
-- war's map: a base in two opposite corners, three lanes of tarmac between
-- them, a storm channel across the middle and a jungle of trees around it
-- (see `buildArena` and docs/turf-war.md).
--
-- World origin is the centre of the map. The east-west road nearest the
-- middle runs through it, and the cars spawn along that road.

local Layout = {}

Layout.TILE = 64
Layout.COLS, Layout.ROWS = 52, 42 -- 3328 x 2688 px, unless the spec says otherwise
Layout.PERIOD = 10 -- tiles between road centrelines: 2 road + 8 block
Layout.SEED = 7
Layout.CELL = 256 -- collision bucket size, px
-- Blocks (column, row of blocks) left empty as plots for sale: the four
-- corners of the city, each ringed by four streets. A spec may list its own.
Layout.PLOTS = { { 0, 0 }, { 4, 0 }, { 0, 3 }, { 4, 3 } }
-- How many blocks the city may grow past its original edge on each side.
-- Keeps the drawn map within a texture every graphics card can hold.
Layout.GROW = 3

local ROOFS = {
  { 0.55, 0.25, 0.20 }, -- brick
  { 0.74, 0.64, 0.46 }, -- tan
  { 0.44, 0.46, 0.50 }, -- concrete
  { 0.30, 0.35, 0.50 }, -- steel blue
  { 0.45, 0.50, 0.35 }, -- olive
  { 0.40, 0.16, 0.16 }, -- dark red
}

-- Suburban roofs for the cul-de-sac: lighter and fussier than downtown.
local HOUSES = {
  { 0.82, 0.55, 0.60 }, -- dusty pink
  { 0.60, 0.78, 0.70 }, -- mint
  { 0.86, 0.80, 0.60 }, -- cream
  { 0.58, 0.68, 0.84 }, -- powder blue
  { 0.80, 0.66, 0.50 }, -- peach
  { 0.66, 0.60, 0.78 }, -- lilac
}

local function isRoadIndex(i)
  return i % Layout.PERIOD < 2
end

--- What tile (c, r) is inside the city. Works for negative indices too, so
--- blocks grown past the original edge follow the same pattern.
local function kindAt(c, r)
  if isRoadIndex(c) or isRoadIndex(r) then
    return "road"
  end
  local lc, lr = c % Layout.PERIOD - 2, r % Layout.PERIOD - 2
  return (lc == 0 or lc == 7 or lr == 0 or lr == 7) and "walk" or "core"
end

--- Split a core rectangle (tile units) into 1-4 buildings with 1-tile alleys.
local function splitCore(rng, cx, cy, cw, ch, out)
  local roll = rng:random()
  local function add(x, y, w, h)
    -- Random inset for variety; never below 2 tiles.
    local ix = (w > 3 and rng:random() < 0.3) and 1 or 0
    local iy = (h > 3 and rng:random() < 0.3) and 1 or 0
    out[#out + 1] = { tx = x + ix, ty = y + iy, tw = w - ix * 2, th = h - iy * 2 }
  end
  if roll < 0.15 then
    add(cx, cy, cw, ch)
  elseif roll < 0.5 then
    if rng:random() < 0.5 then
      local s = rng:random(2, ch - 3)
      add(cx, cy, cw, s)
      add(cx, cy + s + 1, cw, ch - s - 1)
    else
      local s = rng:random(2, cw - 3)
      add(cx, cy, s, ch)
      add(cx + s + 1, cy, cw - s - 1, ch)
    end
  else
    local sx = rng:random(2, cw - 3)
    local sy = rng:random(2, ch - 3)
    add(cx, cy, sx, sy)
    add(cx + sx + 1, cy, cw - sx - 1, sy)
    add(cx, cy + sy + 1, sx, ch - sy - 1)
    add(cx + sx + 1, cy + sy + 1, cw - sx - 1, ch - sy - 1)
  end
end

--- Empty the plot blocks. Done after the whole city is generated so the
--- random stream, and with it every other block, is the same as without them.
local function clearPlots(map)
  local T = Layout.TILE
  -- Keep what lies outside the block; a tile of margin catches trees whose
  -- jitter nudged them over the edge.
  local function outside(list, x0, y0, x1, y1)
    local kept = {}
    for _, item in ipairs(list) do
      local cx, cy = item.x + (item.w or 0) / 2, item.y + (item.h or 0) / 2
      if cx < x0 - T or cx >= x1 + T or cy < y0 - T or cy >= y1 + T then
        kept[#kept + 1] = item
      end
    end
    return kept
  end
  for _, block in ipairs(map.blocks) do
    for _, p in ipairs(map.plots) do
      if block.bi == p[1] and block.bj == p[2] then
        block.kind = "plot"
        local x0, y0 = map.x0 + block.tx * T, map.y0 + block.ty * T
        local x1, y1 = x0 + block.tw * T, y0 + block.th * T
        map.buildings = outside(map.buildings, x0, y0, x1, y1)
        map.trees = outside(map.trees, x0, y0, x1, y1)
        map.solids = outside(map.solids, x0, y0, x1, y1)
      end
    end
  end
end

--- Walls around whatever shape the city has: every tile outside it, out to
--- a margin, is solid, merged into as few rectangles as possible, with a
--- thick ring beyond the margin so nothing escapes.
local function buildWalls(map)
  local T, M, B = Layout.TILE, 6, 400
  local c0, c1, r0, r1 = map.c0 - M, map.c1 + M, map.r0 - M, map.r1 + M
  local walls, open = {}, {} -- open: "c,len" -> the wall that reached the previous row
  for r = r0, r1 do
    local row, c = {}, c0
    while c <= c1 do
      local col = map.tiles[c]
      if col and col[r] then
        c = c + 1
      else
        local start = c
        repeat
          c = c + 1
          col = map.tiles[c]
        until c > c1 or (col and col[r])
        local key = start .. "," .. (c - start)
        local wall = open[key]
        if wall then
          wall.h = wall.h + T
        else
          wall = { x = map.x0 + start * T, y = map.y0 + r * T, w = (c - start) * T, h = T, wall = true }
          walls[#walls + 1] = wall
        end
        row[key] = wall
      end
    end
    open = row
  end
  local x, y = map.x0 + c0 * T, map.y0 + r0 * T
  local w, h = (c1 - c0 + 1) * T, (r1 - r0 + 1) * T
  walls[#walls + 1] = { x = x - B, y = y - B, w = w + 2 * B, h = B, wall = true }
  walls[#walls + 1] = { x = x - B, y = y + h, w = w + 2 * B, h = B, wall = true }
  walls[#walls + 1] = { x = x - B, y = y, w = B, h = h, wall = true }
  walls[#walls + 1] = { x = x + w, y = y, w = B, h = h, wall = true }
  return walls
end

--- Rebuild everything derived from the tiles: world bounds, walls and the
--- collision buckets.
local function finish(map)
  local T = Layout.TILE
  map.left, map.top = map.x0 + map.c0 * T, map.y0 + map.r0 * T
  map.w, map.h = (map.c1 - map.c0 + 1) * T, (map.r1 - map.r0 + 1) * T

  map.solids = {}
  for _, s in ipairs(map.fixed) do
    map.solids[#map.solids + 1] = s
  end
  for _, s in ipairs(buildWalls(map)) do
    map.solids[#map.solids + 1] = s
  end

  map.cells = {}
  local CELL = Layout.CELL
  for _, s in ipairs(map.solids) do
    local c0, c1 = math.floor(s.x / CELL), math.floor((s.x + s.w) / CELL)
    local r0, r1 = math.floor(s.y / CELL), math.floor((s.y + s.h) / CELL)
    for c = c0, c1 do
      map.cells[c] = map.cells[c] or {}
      for r = r0, r1 do
        local list = map.cells[c][r]
        if not list then
          list = {}
          map.cells[c][r] = list
        end
        list[#list + 1] = s
      end
    end
  end
end

--- A suburban dead end. The street comes in from the bottom edge, two
--- lanes with a sidewalk each side, and ends in a turning circle near the
--- top; houses sit on lawns either side of it and around the circle, with
--- a tree here and there. Everything off the tarmac is "ground" (lawn), so
--- cars can cut across gardens, and the houses are solid like downtown's.
--- Cars spawn in the street by the entrance and `map.cx, map.cy` is the
--- entrance too; the circle's centre is `map.circleX, map.circleY`.
local function buildCuldesac(map, rng)
  local T = Layout.TILE
  local cols, rows = map.cols, map.rows
  local mid = math.floor(cols / 2) -- the street runs down columns mid-1 and mid
  local circleR, circleRow = 4 * T, 10 -- turning circle: radius, and the tile row of its centre
  local ccx, ccy = map.x0 + mid * T, map.y0 + circleRow * T + T / 2
  map.circleX, map.circleY = ccx, ccy
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      local tx, ty = map.x0 + (c + 0.5) * T, map.y0 + (r + 0.5) * T
      local d = math.sqrt((tx - ccx) ^ 2 + (ty - ccy) ^ 2)
      local kind = "ground"
      if d <= circleR or ((c == mid - 1 or c == mid) and r >= circleRow) then
        kind = "road"
      elseif d <= circleR + T or ((c == mid - 2 or c == mid + 1) and r >= circleRow) then
        kind = "walk"
      end
      map.tiles[c][r] = kind
    end
  end

  -- Houses: three each side of the street and five around the circle, each
  -- three tiles square, set back a lawn's width from the sidewalk.
  local function house(tc, tr, tw, th)
    local b = {
      x = map.x0 + tc * T,
      y = map.y0 + tr * T,
      w = tw * T,
      h = th * T,
      color = HOUSES[rng:random(#HOUSES)],
      style = rng:random(3),
      seed = rng:random(1000),
    }
    map.buildings[#map.buildings + 1] = b
    map.solids[#map.solids + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
  end
  for _, r in ipairs({ circleRow + 4, circleRow + 9, circleRow + 14 }) do
    house(mid - 6, r, 3, 3)
    house(mid + 3, r, 3, 3)
  end
  house(mid - 1, circleRow - 9, 3, 3) -- top of the circle
  house(mid - 8, circleRow - 6, 3, 3)
  house(mid + 5, circleRow - 6, 3, 3)
  house(mid - 9, circleRow - 1, 3, 3)
  house(mid + 6, circleRow - 1, 3, 3)

  -- Trees on the lawns, clear of the houses and the street.
  for _, tc in ipairs({ { mid - 9, circleRow + 6 }, { mid + 8, circleRow + 8 }, { mid - 8, circleRow + 12 },
    { mid + 9, circleRow + 13 }, { mid - 4, circleRow - 8 }, { mid + 4, circleRow - 8 } }) do
    local x = map.x0 + (tc[1] + 0.5) * T + (rng:random() - 0.5) * 20
    local y = map.y0 + (tc[2] + 0.5) * T + (rng:random() - 0.5) * 20
    map.trees[#map.trees + 1] = { x = x, y = y }
    map.solids[#map.solids + 1] = { x = x - 7, y = y - 7, w = 14, h = 14, tree = true }
  end

  -- Spawns: parked on the verges either side of the entrance, nose to the
  -- street, leaving the entrance itself (map.cx, map.cy) clear for a
  -- quest's star. This is a street you walk up; the cars wait here.
  map.cx, map.cy = ccx, map.y0 + (rows - 2.5) * T
  for i = 0, 7 do
    local y = map.y0 + (rows - 5) * T + i * 36
    map.spawns[#map.spawns + 1] = { x = ccx - 158, y = y, angle = 0 }
    map.spawns[#map.spawns + 1] = { x = ccx + 158, y = y, angle = math.pi }
  end
end

--- Distance from (x, y) to the segment a-b.
local function segmentDist(x, y, ax, ay, bx, by)
  local vx, vy = bx - ax, by - ay
  local len2 = vx * vx + vy * vy
  local t = len2 > 0 and math.max(0, math.min(1, ((x - ax) * vx + (y - ay) * vy) / len2)) or 0
  return math.sqrt((x - ax - vx * t) ^ 2 + (y - ay - vy * t) ^ 2)
end

-- The forest trail, entrance to lair, as fractions of the map's half-size
-- (so it scales with the map). `wp` marks the stops along it.
local TRAIL = {
  { 0, 0.78 },
  { -0.14, 0.66 },
  { -0.42, 0.56, wp = true },
  { -0.24, 0.40 },
  { 0.30, 0.30, wp = true },
  { 0.30, 0.12 },
  { -0.32, 0.00, wp = true },
  { -0.36, -0.20 },
  { 0.34, -0.32, wp = true },
  { 0.24, -0.50 },
  { 0, -0.68, wp = true },
}

--- A forest: open ground packed with trees and shrubs, a dirt trail
--- winding up it from the entrance at the bottom through clearings to a
--- big one near the top. `map.trail` is the trail ({ x, y, wp }),
--- `map.waypoints` the clearings along it in order (the last is
--- `map.lair`), `map.shrubs` bushes to draw (not solid: you push through
--- them). Trees are solid trunks. Cars park either side of the entrance,
--- which is `map.cx, map.cy`; it is a walking map.
local function buildForest(map, rng)
  local T = Layout.TILE
  local cols, rows = map.cols, map.rows
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      map.tiles[c][r] = "ground"
    end
  end
  local hw, hh = cols * T / 2, rows * T / 2
  map.trail, map.waypoints, map.shrubs = {}, {}, {}
  for _, n in ipairs(TRAIL) do
    local node = { x = math.floor(n[1] * hw), y = math.floor(n[2] * hh), wp = n.wp }
    map.trail[#map.trail + 1] = node
    if node.wp then
      map.waypoints[#map.waypoints + 1] = node
    end
  end
  map.lair = map.waypoints[#map.waypoints]
  map.cx, map.cy = map.trail[1].x, math.floor(hh - 1.8 * T)
  map.clearing, map.lairRadius = 150, 380 -- px; radius kept free of trees

  --- How far (x, y) is from the trail and its clearings; negative inside a clearing.
  local function openness(x, y)
    local d = math.huge
    for i = 1, #map.trail - 1 do
      local a, b = map.trail[i], map.trail[i + 1]
      d = math.min(d, segmentDist(x, y, a.x, a.y, b.x, b.y))
    end
    for _, w in ipairs(map.waypoints) do
      local r = w == map.lair and map.lairRadius or map.clearing
      d = math.min(d, math.sqrt((x - w.x) ^ 2 + (y - w.y) ^ 2) - r)
    end
    if math.abs(x - map.cx) < 320 and y > map.cy - 330 then
      d = -1 -- the car park at the entrance
    end
    return d
  end

  local margin = 40
  local function spot()
    return (rng:random() * 2 - 1) * (hw - margin), (rng:random() * 2 - 1) * (hh - margin)
  end
  for _ = 1, math.floor(cols * rows * 0.36) do
    local x, y = spot()
    if openness(x, y) > 70 then
      local close = false
      for _, t in ipairs(map.trees) do
        if (t.x - x) ^ 2 + (t.y - y) ^ 2 < 46 * 46 then
          close = true
          break
        end
      end
      if not close then
        map.trees[#map.trees + 1] = { x = x, y = y, r = 18 + rng:random() * 12, pine = rng:random() < 0.45 }
        map.solids[#map.solids + 1] = { x = x - 7, y = y - 7, w = 14, h = 14, tree = true }
      end
    end
  end
  for _ = 1, math.floor(cols * rows * 0.2) do
    local x, y = spot()
    if openness(x, y) > 34 then
      map.shrubs[#map.shrubs + 1] = { x = x, y = y, r = 8 + rng:random() * 7, berries = rng:random() < 0.25 }
    end
  end

  for i = 0, 7 do
    local y = map.cy - 250 + i * 36
    map.spawns[#map.spawns + 1] = { x = map.cx - 200, y = y, angle = 0 }
    map.spawns[#map.spawns + 1] = { x = map.cx + 200, y = y, angle = math.pi }
  end
end

--- A landing beach under a defended hill, in bands from the bottom (south)
--- up: shallow surf with landing craft where everyone wades ashore, open
--- sand strewn with steel tank stoppers ("hedgehogs") and sandbag walls to
--- hide behind, a line of concrete bunkers with two trenches behind them,
--- the barracks huts, and the hilltop with the flag. Everything built is
--- solid, so it stops people, bullets and eyes alike. The trenches' sandbag
--- lips have gaps every few tiles to fire from and run through.
---
--- `map.bands` names each band's world y range (`y0` top, `y1` bottom):
--- hill, barracks, bunkers, beach, surf. `map.flagX, flagY` is the flag,
--- `map.posts` the spots a defender may stand ({ x, y, band }), off the
--- beach, `map.doors` the barracks doors reinforcements come out of,
--- `map.cover` what the canvas draws ({ kind = "hedgehog" | "sandbag" |
--- "bunker" | "hut", x, y, w, h }) and `map.craft` the landing craft.
--- Walked, like the forest; the cars wait in the surf.
local function buildBeach(map, rng)
  local T = Layout.TILE
  local cols, rows = map.cols, map.rows
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      map.tiles[c][r] = "ground"
    end
  end
  local function ty(r)
    return map.y0 + r * T
  end
  local left, right = map.x0, map.x0 + cols * T
  local hillEnd, barracksEnd = math.floor(rows * 0.16), math.floor(rows * 0.34)
  local bunkersEnd, beachEnd = math.floor(rows * 0.56), math.floor(rows * 0.89)
  map.bands = {
    hill = { y0 = ty(0), y1 = ty(hillEnd) },
    barracks = { y0 = ty(hillEnd), y1 = ty(barracksEnd) },
    bunkers = { y0 = ty(barracksEnd), y1 = ty(bunkersEnd) },
    beach = { y0 = ty(bunkersEnd), y1 = ty(beachEnd) },
    surf = { y0 = ty(beachEnd), y1 = ty(rows) },
  }
  map.cover, map.posts, map.doors, map.craft = {}, {}, {}, {}
  map.flagX, map.flagY = 0, math.floor(ty(hillEnd * 0.4))

  local function solid(kind, x, y, w, h, extra)
    local s = { kind = kind, x = x, y = y, w = w, h = h }
    for k, v in pairs(extra or {}) do
      s[k] = v
    end
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = x, y = y, w = w, h = h }
    return s
  end
  local function post(x, y, band)
    map.posts[#map.posts + 1] = { x = x, y = y, band = band }
  end

  -- The hilltop: four sandbag walls round the flag, a gap at every corner,
  -- and defenders on the far side of each.
  local fx, fy = map.flagX, map.flagY
  solid("sandbag", fx - 150, fy - 230, 300, 20)
  solid("sandbag", fx - 150, fy + 210, 300, 20)
  solid("sandbag", fx - 250, fy - 110, 20, 220)
  solid("sandbag", fx + 230, fy - 110, 20, 220)
  for _, p in ipairs({ { -420, 120 }, { 420, 120 }, { -300, 330 }, { 300, 330 }, { 0, 330 } }) do
    post(fx + p[1], fy + p[2], "hill")
  end

  -- The barracks: two rows of long huts, staggered, a door on the south
  -- side of each for the reinforcements.
  local hutW, hutH = 5 * T, 2 * T
  local hutRows = { ty(hillEnd + 2), ty(hillEnd + 6.5) }
  for i, y in ipairs(hutRows) do
    local xs = i == 1 and { -0.36, -0.07, 0.22 } or { -0.22, 0.08 }
    for _, f in ipairs(xs) do
      local x = math.floor(f * cols * T)
      solid("hut", x, y, hutW, hutH)
      map.buildings[#map.buildings + 1] = { x = x, y = y, w = hutW, h = hutH, color = { 0.36, 0.40, 0.30 } }
      map.doors[#map.doors + 1] = { x = x + hutW / 2, y = y + hutH + 22 }
      post(x - 40, y + hutH + 40, "barracks")
      post(x + hutW + 40, y + hutH / 2, "barracks")
    end
  end

  -- The bunker line: pillboxes across the top of the beach, a defender in
  -- the embrasure of each (the south face).
  local bunkerY = ty(barracksEnd + 2)
  local bw, bh = 3 * T, 2 * T
  for k = 0, 4 do
    local x = math.floor(left + (k + 0.5) * (cols * T / 5) - bw / 2 + (rng:random() - 0.5) * T)
    local y = bunkerY + (k % 2) * T
    solid("bunker", x, y, bw, bh)
    map.buildings[#map.buildings + 1] = { x = x, y = y, w = bw, h = bh, color = { 0.55, 0.55, 0.52 } }
    post(x + bw / 2, y + bh + 18, "bunkers")
  end

  -- Two trenches behind the bunkers: a dirt ditch the width of the map,
  -- sandbags along its south lip with a gap every few tiles. Defenders
  -- stand in the gaps.
  map.trenches = {}
  for k, r in ipairs({ bunkersEnd - 5, bunkersEnd - 2 }) do
    local y = ty(r)
    map.trenches[#map.trenches + 1] = { y = y - 44, h = 44 }
    local x = left + T * (k == 1 and 1 or 2.5)
    while x < right - T do
      local len = T * (2 + rng:random(0, 2))
      solid("sandbag", x, y, math.min(len, right - T - x), 18)
      x = x + len
      if x < right - T then
        post(x + T / 2, y - 22, "bunkers")
      end
      x = x + T
    end
  end

  -- The beach: hedgehogs and sandbag walls scattered over the sand, never
  -- too close together, so there is always a way between them.
  local beach = map.bands.beach
  local placed = {}
  local function clear(x, y, gap)
    for _, p in ipairs(placed) do
      if (p.x - x) ^ 2 + (p.y - y) ^ 2 < gap * gap then
        return false
      end
    end
    return true
  end
  local area = cols * (beachEnd - bunkersEnd)
  for _ = 1, area * 3 do
    if #placed >= math.floor(area / 7) then
      break
    end
    local x = left + T + rng:random() * (cols - 2) * T
    local y = beach.y0 + T + rng:random() * (beach.y1 - beach.y0 - 2 * T)
    if clear(x, y, 118) then
      placed[#placed + 1] = { x = x, y = y }
      if rng:random() < 0.3 then
        local w = T * (1.2 + rng:random() * 0.6)
        solid("sandbag", math.floor(x - w / 2), math.floor(y - 9), math.floor(w), 18)
      else
        solid("hedgehog", math.floor(x - 10), math.floor(y - 10), 20, 20, { angle = rng:random() * math.pi })
      end
    end
  end

  -- The surf: landing craft beached with their ramps down (drawn, not
  -- solid), and everyone wading ashore between them.
  local surf = map.bands.surf
  for _, k in ipairs({ 0, 1, 3, 4 }) do -- the middle is left for the star home
    local x = math.floor(left + (k + 0.5) * (cols * T / 5) + (rng:random() - 0.5) * T)
    map.craft[#map.craft + 1] = { x = x, y = surf.y0 + 2.6 * T }
  end
  map.cx, map.cy = 0, math.floor(surf.y0 + 3.2 * T)
  for i = 0, 7 do
    local x = 110 + i * 70
    for _, sign in ipairs({ -1, 1 }) do
      map.spawns[#map.spawns + 1] = { x = sign * x, y = surf.y0 + 0.9 * T + (i % 2) * 40, angle = -math.pi / 2 }
    end
  end
end

-- The turf war's map (docs/turf-war.md): a walled square with a base in
-- the bottom-left corner (the Southside, team 1) and one in the top-right
-- (the Northside, team 2), three lanes of tarmac between them and a
-- jungle of trees in between. Everything is built for the Southside and
-- turned 180 degrees about the origin for the Northside, so both sides
-- walk the same distances. Distances below are world px.
local ARENA = {
  laneW = 192, -- tarmac width, three tiles
  edge = 1760, -- an edge lane's centreline, in from the origin (288 px off the wall)
  base = 768, -- a base compound's side; it sits flush in its corner
  wall = 28, -- its walls' thickness
  gate = 240, -- a gate's width (the lane and a verge each side)
  corner = 150, -- how much of each wall the corner gate for the mid lane takes
  vault = 120, -- the vault's side
  fountain = 70, -- the fountain ring's radius
  tower = 56, -- a tower's side
  towerOff = 124, -- a tower's centre off the lane's centreline (on the verge)
  riverW = 200, -- the storm channel's width
  camp = 130, -- a jungle camp's clearing radius
  pathW = 64, -- a footpath's width (trees keep off it)
  treeGap = 60, -- the jittered grid trees grow on
}
-- The team colours, for the roofs, braziers and the HUD later.
ARENA.teams = {
  { name = "Southside", color = { 0.25, 0.75, 0.65 } },
  { name = "Northside", color = { 0.95, 0.45, 0.25 } },
}

--- Distance from (x, y) to polyline `pts` ({ x, y } nodes).
local function polylineDist(x, y, pts)
  local d = math.huge
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    d = math.min(d, segmentDist(x, y, a.x, a.y, b.x, b.y))
  end
  return d
end

--- The point `dist` px along polyline `pts`, and the direction there.
local function alongPolyline(pts, dist)
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    if dist <= len or i == #pts - 1 then
      local t = math.max(0, math.min(1, dist / len))
      return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, (b.x - a.x) / len, (b.y - a.y) / len
    end
    dist = dist - len
  end
end

--- The other team's copy of a Southside point.
local function mirror(x, y)
  return -x, -y
end

local function buildArena(map, rng)
  local T = Layout.TILE
  local A = ARENA
  local cols, rows = map.cols, map.rows
  local H = cols * T / 2 -- half the map; the origin is its centre
  local E, B = A.edge, H - A.base -- an edge lane's centreline; a base's inner walls
  local W2 = A.laneW / 2
  map.teams = A.teams
  map.arena = A

  -- Lanes, Southside gate to Northside gate. The edge lanes round their
  -- corner in two short bends; the mid lane is straight through the origin.
  local function lane(name, pts)
    local l = { name = name, points = {} }
    for _, p in ipairs(pts) do
      l.points[#l.points + 1] = { x = p[1], y = p[2] }
    end
    return l
  end
  map.lanes = {
    lane("top", { { -E, B }, { -E, -E + 160 }, { -E + 40, -E + 40 }, { -E + 160, -E }, { B, -E } }),
    lane("mid", { { -B, B }, { B, -B } }),
    lane("bottom", { { -B, E }, { E - 160, E }, { E - 40, E - 40 }, { E, E - 160 }, { E, -B } }),
  }
  map.lanes.byName = {}
  for _, l in ipairs(map.lanes) do
    map.lanes.byName[l.name] = l
  end

  -- The river: a storm channel down the other diagonal, corner to corner,
  -- with a bridge where each lane crosses it.
  map.river = { x0 = -H, y0 = -H, x1 = H, y1 = H, w = A.riverW }
  local bx = E - 40 -- the bend's middle, where the edge lanes cross it
  map.bridges = { -- `len` is the deck's length: the corner ones stop short of the bend's outside
    { x = 0, y = 0, angle = -math.pi / 4, len = A.riverW + 70 },
    { x = -bx, y = -bx, angle = -math.pi / 4, len = A.riverW + 10 },
    { x = bx, y = bx, angle = -math.pi / 4, len = A.riverW + 10 },
  }

  local function solid(x, y, w, h, extra)
    local s = { x = x, y = y, w = w, h = h }
    for k, v in pairs(extra or {}) do
      s[k] = v
    end
    map.solids[#map.solids + 1] = s
    return s
  end
  --- A solid that also shows on the minimap (it draws `map.buildings`).
  local function building(x, y, w, h, color, extra)
    local s = solid(x, y, w, h, extra)
    map.buildings[#map.buildings + 1] = { x = x, y = y, w = w, h = h, color = color }
    return s
  end

  -- The bases. Each is `{ team, x0, y0, x1, y1, vault, fountain, shop,
  -- gates, walls }`; `walls` are the wall pieces (drawn), the compound's
  -- outer two sides are the map wall.
  map.bases, map.towers, map.camps, map.paths, map.shrubs = {}, {}, {}, {}, {}
  local WALL = { 0.50, 0.48, 0.44 }
  local function base(team)
    local sign = team == 1 and 1 or -1
    local function pt(x, y)
      return sign * x, sign * y
    end
    local vx, vy = pt(-(B + A.base / 2), B + A.base / 2) -- the courtyard's centre
    local fx, fy = pt(-(H - 208), H - 208)
    local b = {
      team = team,
      x0 = math.min(sign * -H, sign * -B),
      y0 = math.min(sign * H, sign * B),
      x1 = math.max(sign * -H, sign * -B),
      y1 = math.max(sign * H, sign * B),
      vault = { x = vx, y = vy, r = A.vault / 2 },
      fountain = { x = fx, y = fy, r = A.fountain },
      shop = { x = sign * -(H - 140), y = sign * (H - 360), w = 48, h = 32 },
      gates = {}, -- by lane name: where that lane leaves the compound
      walls = {},
    }
    for _, l in ipairs(map.lanes) do
      local g = l.points[team == 1 and 1 or #l.points]
      b.gates[l.name] = { x = g.x, y = g.y }
    end
    local color = A.teams[team].color
    building(vx - A.vault / 2, vy - A.vault / 2, A.vault, A.vault, color, { vault = team })
    -- The shop stand by the fountain, a kiosk you walk up to.
    local s = b.shop
    building(s.x - s.w / 2, s.y - s.h / 2, s.w, s.h, { 0.85, 0.75, 0.35 }, { shop = team })
    -- The two inner walls, each in pieces: the corner cut off for the mid
    -- lane and a gate for the edge lane.
    local t, g2, c = A.wall, A.gate / 2, A.corner
    local function wall(x, y, w, h)
      b.walls[#b.walls + 1] = building(x, y, w, h, WALL, { wall = true })
    end
    -- Along y = B from the map wall to the corner cut (in Southside terms).
    local pieces = {
      { -H, -E - g2 }, -- map wall to the edge gate
      { -E + g2, -B - c }, -- edge gate to the corner cut
    }
    for _, p in ipairs(pieces) do
      local x0, x1 = p[1], p[2]
      if team == 1 then
        wall(x0, B - t / 2, x1 - x0, t) -- the north wall, along y = B
        wall(-B - t / 2, -x1, t, x1 - x0) -- the east wall, along x = -B (mirrored across the diagonal)
      else
        wall(-x1, -B - t / 2, x1 - x0, t)
        wall(B - t / 2, x0, t, x1 - x0)
      end
    end
    map.bases[team] = b
    return b
  end
  base(1)
  base(2)

  -- Towers: three a lane a side, on the verge on the lane's inner side
  -- (the mid lane's on its north-west side for the Southside), tier 3 at
  -- the gate out to tier 1 short of the river.
  local TIERS = { edge = { 2300, 1300, 300 }, mid = { 1300, 760, 220 } }
  for _, l in ipairs(map.lanes) do
    local dists = TIERS[l.name == "mid" and "mid" or "edge"]
    for tier, d in ipairs(dists) do
      local x, y, dx, dy = alongPolyline(l.points, d)
      -- The verge on the side facing the origin; the mid lane runs through
      -- it, so that one takes its left-hand verge.
      local nx, ny = -dy, dx
      if l.name == "mid" then
        nx, ny = -math.sqrt(0.5), -math.sqrt(0.5) -- its north-west verge
      elseif nx * -x + ny * -y < 0 then
        nx, ny = -nx, -ny
      end
      local tx, ty = x + nx * A.towerOff, y + ny * A.towerOff
      for team = 1, 2 do
        local px, py = tx, ty
        if team == 2 then
          px, py = mirror(tx, ty)
        end
        map.towers[#map.towers + 1] = { x = px, y = py, team = team, lane = l.name, tier = tier }
        building(px - A.tower / 2, py - A.tower / 2, A.tower, A.tower, A.teams[team].color, { tower = team })
      end
    end
  end

  -- Jungle camps, two in each wedge between an edge lane and the mid lane,
  -- and the footpaths that join them to the lanes and each other.
  local CAMPS = { { -1250, -650 }, { -850, 350 }, { -350, 850 }, { 650, 1250 } }
  local PATHS = {
    { { -E + W2, -650 }, { -1250, -650 }, { -850, 350 }, { -600, 600 } },
    { { -850, 350 }, { -E + W2, 350 } },
    { { 650, E - W2 }, { 650, 1250 }, { -350, 850 }, { -600, 600 } },
    { { -350, 850 }, { -350, E - W2 } },
  }
  for team = 1, 2 do
    for _, c in ipairs(CAMPS) do
      local x, y = c[1], c[2]
      if team == 2 then
        x, y = mirror(x, y)
      end
      map.camps[#map.camps + 1] = { x = x, y = y, r = A.camp, team = team }
    end
    for _, p in ipairs(PATHS) do
      local path = {}
      for _, n in ipairs(p) do
        local x, y = n[1], n[2]
        if team == 2 then
          x, y = mirror(x, y)
        end
        path[#path + 1] = { x = x, y = y }
      end
      map.paths[#map.paths + 1] = path
    end
  end

  -- Tiles: grass everywhere, water down the river, tarmac on the lanes (over
  -- the water: those are the bridges) and paving in the courtyards. The
  -- minimap draws them; other features only care that there is ground.
  local function inBase(x, y, margin)
    margin = margin or 0
    for _, b in ipairs(map.bases) do
      if x >= b.x0 - margin and x <= b.x1 + margin and y >= b.y0 - margin and y <= b.y1 + margin then
        return true
      end
    end
    return false
  end
  local riverDist = function(x, y)
    return segmentDist(x, y, map.river.x0, map.river.y0, map.river.x1, map.river.y1)
  end
  local function laneDist(x, y)
    local d = math.huge
    for _, l in ipairs(map.lanes) do
      d = math.min(d, polylineDist(x, y, l.points))
    end
    return d
  end
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      local x, y = map.x0 + (c + 0.5) * T, map.y0 + (r + 0.5) * T
      local kind = "ground"
      if riverDist(x, y) <= A.riverW / 2 then
        kind = "water"
      end
      if inBase(x, y) then
        kind = "walk"
      end
      if laneDist(x, y) <= W2 then
        kind = "road"
      end
      map.tiles[c][r] = kind
    end
  end

  -- Trees on a jittered grid over the jungle, kept off everything built,
  -- and shrubs (not solid) in among them.
  local function open(x, y)
    if inBase(x, y, 40) or laneDist(x, y) <= W2 + 44 or riverDist(x, y) <= A.riverW / 2 + 40 then
      return false
    end
    for _, t in ipairs(map.towers) do
      if (t.x - x) ^ 2 + (t.y - y) ^ 2 < 80 * 80 then
        return false
      end
    end
    for _, cp in ipairs(map.camps) do
      if (cp.x - x) ^ 2 + (cp.y - y) ^ 2 < cp.r * cp.r then
        return false
      end
    end
    for _, p in ipairs(map.paths) do
      if polylineDist(x, y, p) <= A.pathW / 2 + 20 then
        return false
      end
    end
    return true
  end
  local margin = 50
  for gy = -H + margin, H - margin, A.treeGap do
    for gx = -H + margin, H - margin, A.treeGap do
      local x = gx + (rng:random() - 0.5) * A.treeGap * 0.8
      local y = gy + (rng:random() - 0.5) * A.treeGap * 0.8
      local roll = rng:random()
      if open(x, y) then
        if roll < 0.8 then
          map.trees[#map.trees + 1] = { x = x, y = y, r = 17 + rng:random() * 11, pine = rng:random() < 0.4 }
          solid(x - 7, y - 7, 14, 14, { tree = true })
        elseif roll < 0.92 then
          map.shrubs[#map.shrubs + 1] = { x = x, y = y, r = 8 + rng:random() * 7, berries = rng:random() < 0.25 }
        end
      end
    end
  end

  -- Spawns: eight car slots a side along each base's two outer walls, a
  -- Southside slot and a Northside slot in turn, so a group placed in
  -- player order (city-map's `placePlayers`) lands half in each base.
  -- `map.cx, map.cy` is the Southside fountain.
  local f1 = map.bases[1].fountain
  map.cx, map.cy = f1.x, f1.y
  for i = 0, 3 do
    local sx, sy = -(H - 528) - i * 80, H - 58 -- along the south wall, facing north
    local wx, wy = -(H - 58), (H - 328) - i * 80 -- along the west wall, facing east
    local slots = { { sx, sy, -math.pi / 2 }, { wx, wy, 0 } }
    for _, s in ipairs(slots) do
      map.spawns[#map.spawns + 1] = { x = s[1], y = s[2], angle = s[3] }
      local mx, my = mirror(s[1], s[2])
      map.spawns[#map.spawns + 1] = { x = mx, y = my, angle = s[3] + math.pi }
    end
  end
end

--- Build a map. `spec` is { seed, cols, rows, plots, empty, kind } (every
--- field optional, defaulting to the city above) or just a seed.
function Layout.generate(spec)
  if type(spec) ~= "table" then
    spec = { seed = spec }
  end
  local rng = love.math.newRandomGenerator(spec.seed or Layout.SEED)
  local T, P = Layout.TILE, Layout.PERIOD
  local cols, rows = spec.cols or Layout.COLS, spec.rows or Layout.ROWS
  local empty = spec.empty or false
  local W, H = cols * T, rows * T
  local map = {
    kind = spec.kind or "grid",
    cols = cols, -- original size in tiles; the city may grow past it
    rows = rows,
    empty = empty, -- open ground: every tile "ground", nothing built on it
    crowd = spec.crowd ~= false, -- pedestrians and officers walk here (pedestrians, police read it)
    traffic = spec.traffic ~= false, -- NPC cars drive here (bots parks them otherwise)
    vehicles = spec.vehicles ~= false, -- players may drive here (on-foot keeps everyone walking otherwise)
    plots = spec.plots or ((empty or spec.kind) and {} or Layout.PLOTS), -- { bi, bj } blocks left empty for sale
    x0 = -W / 2, -- world x of tile column 0 (the original left edge)
    y0 = -H / 2,
    -- Tile bounds of the city (inclusive) and the same in world px. They
    -- move when the city grows; the tile origin x0, y0 never does.
    c0 = 0,
    c1 = cols - 1,
    r0 = 0,
    r1 = rows - 1,
    left = -W / 2,
    top = -H / 2,
    w = W,
    h = H,
    version = 1, -- bumped on every change, so drawings know to redo themselves
    tiles = {}, -- [c][r] = "road" | "walk" | "core" (block interior) | "ground" (open field) | "water"; nil outside
    blocks = {}, -- { tx, ty, tw, th, bi, bj, kind = "buildings"|"park"|"lot"|"plot" }
    blockAt = {}, -- "bi,bj" -> block
    grown = {}, -- { bi, bj } in the order the city grew
    buildings = {}, -- { x, y, w, h, color, style } in world px
    trees = {}, -- { x, y } canopy centres, world px
    solids = {}, -- { x, y, w, h } world px, top-left + size
    spawns = {}, -- { x, y, angle }
  }

  if map.kind == "culdesac" or map.kind == "forest" or map.kind == "beach" or map.kind == "arena" then
    if map.kind == "forest" then
      buildForest(map, rng)
    elseif map.kind == "beach" then
      buildBeach(map, rng)
    elseif map.kind == "arena" then
      buildArena(map, rng)
    else
      buildCuldesac(map, rng)
    end
    map.fixed = map.solids
    finish(map)
    return map
  end

  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      map.tiles[c][r] = empty and "ground" or kindAt(c, r)
    end
  end

  local function px(tx)
    return map.x0 + tx * T
  end
  local function py(ty)
    return map.y0 + ty * T
  end

  -- Blocks: core is tiles 3..8 of each 10-tile period (6x6). None on open ground.
  for bi = 0, empty and -1 or math.floor((cols - 1) / P) do
    for bj = 0, math.floor((rows - 1) / P) do
      local cx, cy = bi * P + 3, bj * P + 3
      if cx + 6 <= cols and cy + 6 <= rows then
        local roll = rng:random()
        local block = { tx = cx, ty = cy, tw = 6, th = 6, bi = bi, bj = bj }
        if roll < 0.15 then
          block.kind = "park"
          for i = 0, 2 do
            for j = 0, 2 do
              local x = px(cx + 1 + i * 2) + (rng:random() - 0.5) * 30
              local y = py(cy + 1 + j * 2) + (rng:random() - 0.5) * 30
              map.trees[#map.trees + 1] = { x = x, y = y }
              map.solids[#map.solids + 1] = { x = x - 7, y = y - 7, w = 14, h = 14, tree = true }
            end
          end
        elseif roll < 0.27 then
          block.kind = "lot"
        else
          block.kind = "buildings"
          local rects = {}
          splitCore(rng, cx, cy, 6, 6, rects)
          for _, b in ipairs(rects) do
            local building = {
              x = px(b.tx),
              y = py(b.ty),
              w = b.tw * T,
              h = b.th * T,
              color = ROOFS[rng:random(#ROOFS)],
              style = rng:random(3),
              seed = rng:random(1000),
            }
            map.buildings[#map.buildings + 1] = building
            map.solids[#map.solids + 1] = { x = building.x, y = building.y, w = building.w, h = building.h }
          end
        end
        map.blocks[#map.blocks + 1] = block
        map.blockAt[bi .. "," .. bj] = block
      end
    end
  end

  clearPlots(map)

  -- Spawns: both lanes of the east-west road nearest the middle of the map,
  -- either side of its centre. Road rows come in pairs at every PERIOD, so
  -- the pair nearest the middle row is the one the origin sits on (or the
  -- closest to it when the height is not a multiple of the period). Open
  -- ground has no roads; the same rows serve, they are just grass there.
  local roadRow = math.floor((math.floor(rows / 2) + P / 2) / P) * P
  roadRow = math.max(0, math.min(roadRow, rows - 2))
  map.cx, map.cy = 0, map.y0 + (roadRow + 1) * T -- the middle of that road, on the map's centre line
  for i = 0, 7 do
    local dx = 120 + i * 90
    if dx + 60 < W / 2 then -- stay inside narrow maps
      map.spawns[#map.spawns + 1] = { x = map.cx - dx, y = map.cy + 32, angle = 0 }
      map.spawns[#map.spawns + 1] = { x = map.cx + dx, y = map.cy - 32, angle = math.pi }
    end
  end

  map.fixed = map.solids -- buildings and trees; the walls are rebuilt as the city grows
  finish(map)
  return map
end

--- May block (bi, bj) be added to the city? It must be new, share a side
--- with a block that is already there and stay within Layout.GROW of the
--- original edge. Returns the neighbour it would grow from, or nil.
function Layout.canGrow(map, bi, bj)
  local P = Layout.PERIOD
  local maxI = math.floor((map.cols - 1) / P) - 1 + Layout.GROW
  local maxJ = math.floor((map.rows - 1) / P) - 1 + Layout.GROW
  if map.blockAt[bi .. "," .. bj] or bi < -Layout.GROW or bj < -Layout.GROW or bi > maxI or bj > maxJ then
    return nil
  end
  for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
    local next = map.blockAt[(bi + d[1]) .. "," .. (bj + d[2])]
    if next then
      return next
    end
  end
  return nil
end

--- Every block the city could grow into, each with the neighbour it would
--- grow from, in a fixed order so every machine lists them alike.
function Layout.growthSites(map)
  local sites, seen = {}, {}
  for _, block in ipairs(map.blocks) do
    for _, d in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      local bi, bj = block.bi + d[1], block.bj + d[2]
      local key = bi .. "," .. bj
      if not seen[key] and Layout.canGrow(map, bi, bj) then
        seen[key] = true
        sites[#sites + 1] = { bi = bi, bj = bj, from = block }
      end
    end
  end
  return sites
end

--- Add block (bi, bj) to the city: an empty plot with a street on every
--- side, paved where there was no street yet. Returns the new block, or nil
--- if it cannot grow there (already part of the city, or not next to it).
function Layout.grow(map, bi, bj)
  if not Layout.canGrow(map, bi, bj) then
    return nil
  end
  local P = Layout.PERIOD
  for c = bi * P, bi * P + P + 1 do
    map.tiles[c] = map.tiles[c] or {}
    for r = bj * P, bj * P + P + 1 do
      map.tiles[c][r] = kindAt(c, r)
    end
  end
  map.c0, map.c1 = math.min(map.c0, bi * P), math.max(map.c1, bi * P + P + 1)
  map.r0, map.r1 = math.min(map.r0, bj * P), math.max(map.r1, bj * P + P + 1)
  local block = { tx = bi * P + 3, ty = bj * P + 3, tw = 6, th = 6, bi = bi, bj = bj, kind = "plot" }
  map.blocks[#map.blocks + 1] = block
  map.blockAt[bi .. "," .. bj] = block
  map.grown[#map.grown + 1] = { bi = bi, bj = bj }
  finish(map)
  map.version = map.version + 1
  return block
end

function Layout.tileAt(map, x, y)
  local c = math.floor((x - map.x0) / Layout.TILE)
  local r = math.floor((y - map.y0) / Layout.TILE)
  local col = map.tiles[c]
  return col and col[r] or nil
end

return Layout
