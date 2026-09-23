-- City layout: a deterministic grid of roads and blocks generated from a
-- seed, so every machine builds the identical map. The city can grow by
-- whole blocks past its limits (`Layout.grow`); every machine grows it the
-- same way in the same order, so they still agree. Blocks hold buildings
-- (with alleys), parks (with trees) or parking lots. Everything solid ends
-- up in `solids`, bucketed into a coarse grid for fast collision queries.
--
-- World origin is the centre of the map; the central crossroads sits on it.

local Layout = {}

Layout.TILE = 64
Layout.COLS, Layout.ROWS = 52, 42 -- 3328 x 2688 px
Layout.PERIOD = 10 -- tiles between road centrelines: 2 road + 8 block
Layout.SEED = 7
Layout.CELL = 256 -- collision bucket size, px
-- Blocks (column, row of blocks) left empty as plots for sale: the four
-- corners of the city, each ringed by four streets.
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
    for _, p in ipairs(Layout.PLOTS) do
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

function Layout.generate(seed)
  local rng = love.math.newRandomGenerator(seed or Layout.SEED)
  local T = Layout.TILE
  local W, H = Layout.COLS * T, Layout.ROWS * T
  local map = {
    x0 = -W / 2, -- world x of tile column 0 (the original left edge)
    y0 = -H / 2,
    -- Tile bounds of the city (inclusive) and the same in world px. They
    -- move when the city grows; the tile origin x0, y0 never does.
    c0 = 0,
    c1 = Layout.COLS - 1,
    r0 = 0,
    r1 = Layout.ROWS - 1,
    left = -W / 2,
    top = -H / 2,
    w = W,
    h = H,
    version = 1, -- bumped on every change, so drawings know to redo themselves
    tiles = {}, -- [c][r] = "road" | "walk" | "core" (block interior); nil outside the city
    blocks = {}, -- { tx, ty, tw, th, bi, bj, kind = "buildings"|"park"|"lot"|"plot" }
    blockAt = {}, -- "bi,bj" -> block
    grown = {}, -- { bi, bj } in the order the city grew
    buildings = {}, -- { x, y, w, h, color, style } in world px
    trees = {}, -- { x, y } canopy centres, world px
    solids = {}, -- { x, y, w, h } world px, top-left + size
    spawns = {}, -- { x, y, angle }
  }

  for c = 0, Layout.COLS - 1 do
    map.tiles[c] = {}
    for r = 0, Layout.ROWS - 1 do
      map.tiles[c][r] = kindAt(c, r)
    end
  end

  local function px(tx)
    return map.x0 + tx * T
  end
  local function py(ty)
    return map.y0 + ty * T
  end

  -- Blocks: core is tiles 3..8 of each 10-tile period (6x6).
  for bi = 0, math.floor((Layout.COLS - 1) / Layout.PERIOD) do
    for bj = 0, math.floor((Layout.ROWS - 1) / Layout.PERIOD) do
      local cx, cy = bi * Layout.PERIOD + 3, bj * Layout.PERIOD + 3
      if cx + 6 <= Layout.COLS and cy + 6 <= Layout.ROWS then
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

  -- Spawns: both lanes of the central east-west road, either side of the crossroads.
  for i = 0, 7 do
    map.spawns[#map.spawns + 1] = { x = -120 - i * 90, y = 32, angle = 0 }
    map.spawns[#map.spawns + 1] = { x = 120 + i * 90, y = -32, angle = math.pi }
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
  local maxI = math.floor((Layout.COLS - 1) / P) - 1 + Layout.GROW
  local maxJ = math.floor((Layout.ROWS - 1) / P) - 1 + Layout.GROW
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
