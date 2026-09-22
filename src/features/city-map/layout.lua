-- City layout: a deterministic grid of roads and blocks generated from a
-- seed, so every machine builds the identical map. Blocks hold buildings
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

function Layout.generate(seed)
  local rng = love.math.newRandomGenerator(seed or Layout.SEED)
  local T = Layout.TILE
  local W, H = Layout.COLS * T, Layout.ROWS * T
  local map = {
    w = W,
    h = H,
    x0 = -W / 2, -- world x of the left edge
    y0 = -H / 2,
    tiles = {}, -- [c][r] = "road" | "walk" | "core" (block interior)
    blocks = {}, -- { tx, ty, kind = "buildings"|"park"|"lot", ... }
    buildings = {}, -- { x, y, w, h, color, style } in world px
    trees = {}, -- { x, y } canopy centres, world px
    solids = {}, -- { x, y, w, h } world px, top-left + size
    spawns = {}, -- { x, y, angle }
  }

  for c = 0, Layout.COLS - 1 do
    map.tiles[c] = {}
    for r = 0, Layout.ROWS - 1 do
      local kind
      if isRoadIndex(c) or isRoadIndex(r) then
        kind = "road"
      else
        local lc, lr = c % Layout.PERIOD - 2, r % Layout.PERIOD - 2
        kind = (lc == 0 or lc == 7 or lr == 0 or lr == 7) and "walk" or "core"
      end
      map.tiles[c][r] = kind
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
        local block = { tx = cx, ty = cy, tw = 6, th = 6 }
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
      end
    end
  end

  -- Boundary walls so nothing leaves the map.
  local B = 400
  map.solids[#map.solids + 1] = { x = map.x0 - B, y = map.y0 - B, w = W + 2 * B, h = B, wall = true }
  map.solids[#map.solids + 1] = { x = map.x0 - B, y = map.y0 + H, w = W + 2 * B, h = B, wall = true }
  map.solids[#map.solids + 1] = { x = map.x0 - B, y = map.y0, w = B, h = H, wall = true }
  map.solids[#map.solids + 1] = { x = map.x0 + W, y = map.y0, w = B, h = H, wall = true }

  -- Spawns: both lanes of the central east-west road, either side of the crossroads.
  for i = 0, 7 do
    map.spawns[#map.spawns + 1] = { x = -120 - i * 90, y = 32, angle = 0 }
    map.spawns[#map.spawns + 1] = { x = 120 + i * 90, y = -32, angle = math.pi }
  end

  -- Collision buckets.
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

  return map
end

function Layout.tileAt(map, x, y)
  local c = math.floor((x - map.x0) / Layout.TILE)
  local r = math.floor((y - map.y0) / Layout.TILE)
  local col = map.tiles[c]
  return col and col[r] or nil
end

return Layout
