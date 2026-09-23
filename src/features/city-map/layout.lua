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
-- (see `buildForest`).
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
    tiles = {}, -- [c][r] = "road" | "walk" | "core" (block interior) | "ground" (open field); nil outside the city
    blocks = {}, -- { tx, ty, tw, th, bi, bj, kind = "buildings"|"park"|"lot"|"plot" }
    blockAt = {}, -- "bi,bj" -> block
    grown = {}, -- { bi, bj } in the order the city grew
    buildings = {}, -- { x, y, w, h, color, style } in world px
    trees = {}, -- { x, y } canopy centres, world px
    solids = {}, -- { x, y, w, h } world px, top-left + size
    spawns = {}, -- { x, y, angle }
  }

  if map.kind == "culdesac" or map.kind == "forest" then
    if map.kind == "forest" then
      buildForest(map, rng)
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
