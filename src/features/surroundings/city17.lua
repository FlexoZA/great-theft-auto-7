-- City 17 past its edges (surroundings' entry for the map): the city carries
-- on, out of reach. A grid of streets and blocks of flats in the same grim
-- colours, some bombed down to rubble, some burning; the railway, the
-- canal, the Combine's wall and the cross street run on out of both sides.
-- A haze hangs over all of it, thicker further out, and a Combine wall runs
-- round the map's edge where nobody gets past.
--
-- The streets and blocks are worked out from the tile they sit on, so they
-- are the same on every machine and never run out. They are drawn once
-- into chunks (canvases at the map's half resolution, a few made a frame
-- as the camera finds them, the least used thrown away past MAX_CHUNKS);
-- the fires on top move, so they are drawn every frame (city-map's
-- fires.lua).

local Layout = require("src.features.city-map.layout")
local Buildings = require("src.features.city-map.buildings")
local Fires = require("src.features.city-map.fires")

local City17 = {}

local T = Layout.TILE
local PERIOD = 10 -- tiles from one street to the next
local STREET = 2 -- tiles of road in each
local CHUNK = 1024 -- px of world in a chunk, each way
local MAX_CHUNKS = 40
local BUILD_PER_FRAME = 1
local WALL = 28 -- px; the wall round the map
local HAZE = { 0.13, 0.14, 0.17 }
local HAZE_LAYERS = 16 -- the haze thickens out to HAZE_LAYERS * HAZE_STEP px past the wall
local HAZE_STEP = 120
local HAZE_EACH = 0.045 -- how much each layer adds

-- city-map's City 17 colours, so the streets run on unbroken.
local C = {
  paving = { 0.47, 0.47, 0.45 },
  pavingDark = { 0.45, 0.45, 0.43 },
  joint = { 0.38, 0.38, 0.36 },
  road = { 0.20, 0.20, 0.21 },
  roadLine = { 0.62, 0.60, 0.52 },
  ballast = { 0.32, 0.29, 0.26 },
  rail = { 0.62, 0.62, 0.64 },
  sleeper = { 0.26, 0.20, 0.15 },
  water = { 0.13, 0.22, 0.24 },
  waterLight = { 0.20, 0.32, 0.34 },
  bank = { 0.55, 0.54, 0.50 },
  metal = { 0.12, 0.14, 0.17 },
  panel = { 0.19, 0.22, 0.26 },
  panelLight = { 0.27, 0.31, 0.36 },
  glow = { 0.45, 0.85, 1.00 },
  rubble = { 0.45, 0.43, 0.40 },
  rubbleDark = { 0.33, 0.31, 0.29 },
  scorch = { 0.06, 0.05, 0.05, 0.55 },
  shadow = { 0, 0, 0, 0.35 },
}
-- city-map's grim roofs.
local GRIM = {
  { 0.42, 0.42, 0.40 },
  { 0.30, 0.31, 0.33 },
  { 0.48, 0.40, 0.30 },
  { 0.38, 0.30, 0.26 },
  { 0.52, 0.48, 0.38 },
  { 0.34, 0.37, 0.36 },
}

local function color(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

--- 0..1 from `n`, the same on every machine.
local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

-- The plan ------------------------------------------------------------------

--- Everything about the map the plan needs, worked out once per map.
local plan = nil -- { map, bands = { [row] = kind }, cross, water0, water1, wallY, wallH, rail }

local function planFor(map)
  if plan and plan.map == map then
    return plan
  end
  local p = { map = map, bands = {}, blocks = {} }
  local function rows(y0, y1, kind)
    for r = math.floor((y0 - map.y0) / T + 0.5), math.floor((y1 - map.y0) / T + 0.5) - 1 do
      p.bands[r] = kind
    end
  end
  for _, z in ipairs(map.zones or {}) do
    if z.name == "canal" then
      p.water0, p.water1 = z.y0 + T, z.y1 - T
      rows(p.water0, p.water1, "water")
      rows(z.y0, p.water0, "bank")
      rows(p.water1, z.y1, "bank")
    elseif z.name == "wall" then
      p.wallY, p.wallH = z.y0, 2 * T - 16
      rows(z.y0, z.y1, "wall")
    end
  end
  for _, s in ipairs(map.cover or {}) do
    if s.kind == "train" then
      p.rail = s
    end
  end
  for _, o in ipairs(map.offLimits or {}) do
    rows(o.y, o.y + o.h, "rail")
  end
  for _, l in ipairs(map.lanes or {}) do
    if l[2] == l[4] then -- the cross street, the one road across the whole map
      p.cross = l[2]
      rows(l[2] - T, l[2] + T, "road")
    end
  end
  plan = p
  return p
end

--- What is on tile (c, r) past the map: "walk", "road", or a band running
--- on out of it ("rail", "water", "bank", "wall"). nil inside the map.
local function tileKind(p, c, r)
  local map = p.map
  if c >= 0 and c < map.cols and r >= 0 and r < map.rows then
    return nil
  end
  local band = p.bands[r]
  if band then
    return band
  end
  if c >= -1 and c <= map.cols and r >= -1 and r <= map.rows then
    return "walk" -- a pavement along the wall round the map
  end
  if c % PERIOD < STREET or r % PERIOD < STREET then
    return "road"
  end
  return "walk"
end

--- The buildings on block (bc, br): { x, y, w, h, color, style, seed, ruin,
--- burning }, worked out once. None where the block runs into the map or a band.
local function block(p, bc, br)
  local key = bc .. "," .. br
  local got = p.blocks[key]
  if got then
    return got
  end
  got = {}
  p.blocks[key] = got
  local map = p.map
  local c0, c1 = bc * PERIOD + STREET + 1, bc * PERIOD + PERIOD - 2
  local r0, r1 = br * PERIOD + STREET + 1, br * PERIOD + PERIOD - 2
  if c1 >= -1 and c0 <= map.cols and r1 >= -1 and r0 <= map.rows then
    return got -- up against the map
  end
  -- The longest run of rows clear of any band, with a pavement's gap.
  local best0, bestN, run0 = nil, 0, nil
  for r = r0, r1 + 1 do
    local clear = r <= r1 and not (p.bands[r - 1] or p.bands[r] or p.bands[r + 1])
    if clear and not run0 then
      run0 = r
    elseif not clear and run0 then
      if r - run0 > bestN then
        best0, bestN = run0, r - run0
      end
      run0 = nil
    end
  end
  if bestN < 2 then
    return got
  end
  local seed = bc * 73.13 + br * 19.71
  local w, h = c1 - c0 + 1, bestN
  local rects
  local split = hash(seed)
  if split < 0.35 or (w < 4 and h < 4) then
    rects = { { c0, best0, w, h } }
  elseif split < 0.7 and w >= 4 then
    local cut = 2 + math.floor(hash(seed + 1) * (w - 3))
    rects = { { c0, best0, cut, h }, { c0 + cut, best0, w - cut, h } }
  elseif h >= 4 then
    local cut = 2 + math.floor(hash(seed + 2) * (h - 3))
    rects = { { c0, best0, w, cut }, { c0, best0 + cut, w, h - cut } }
  else
    rects = { { c0, best0, w, h } }
  end
  for i, rc in ipairs(rects) do
    local s = seed + i * 7.7
    local b = {
      x = map.x0 + rc[1] * T, y = map.y0 + rc[2] * T, w = rc[3] * T, h = rc[4] * T,
      color = GRIM[math.floor(hash(s + 3) * #GRIM) + 1], style = 1 + math.floor(hash(s + 4) * 3),
      seed = math.floor(hash(s + 5) * 1000),
    }
    local fate = hash(s + 6)
    b.ruin = fate < 0.2
    b.burning = not b.ruin and fate < 0.32
    if b.burning then
      b.fire = { kind = "roof", x = b.x + b.w * (0.3 + hash(s + 8) * 0.4), y = b.y + b.h * (0.3 + hash(s + 9) * 0.4),
        r = 30, seed = b.seed }
    end
    got[#got + 1] = b
  end
  return got
end

--- Every block with a tile in the box (left, top, right, bottom), once each.
local function eachBlock(p, left, top, right, bottom, fn)
  local P = PERIOD * T
  local bx0, bx1 = math.floor((left - p.map.x0) / P), math.floor((right - p.map.x0) / P)
  local by0, by1 = math.floor((top - p.map.y0) / P), math.floor((bottom - p.map.y0) / P)
  for bc = bx0, bx1 do
    for br = by0, by1 do
      for _, b in ipairs(block(p, bc, br)) do
        fn(b)
      end
    end
  end
end

-- Drawing a chunk -------------------------------------------------------------

--- What lies on tile (c, r) over the paving the chunk starts with: the
--- darker slab of the checker, a crack, or the road, rails or water.
local function ground(p, c, r, kind)
  local x, y = p.map.x0 + c * T, p.map.y0 + r * T
  if kind == "walk" or kind == "bank" or kind == "wall" then
    if (c + r) % 2 == 1 then
      color(C.pavingDark)
      love.graphics.rectangle("fill", x + 2, y + 2, T - 2, T - 2)
    end
    if kind ~= "wall" and hash(c * 13.1 + r * 7.7) < 0.12 then -- a crack
      color(C.joint)
      love.graphics.setLineWidth(2)
      love.graphics.line(x + 10, y + 14, x + 30, y + 26, x + 44, y + 22)
      love.graphics.setLineWidth(1)
    end
  elseif kind == "road" then
    color(C.road)
    love.graphics.rectangle("fill", x, y, T, T)
    -- The worn line down the middle, between a street's two lanes.
    color(C.roadLine)
    if p.bands[r] ~= "road" and c % PERIOD == 1 and r % PERIOD >= STREET and hash(c * 3.1 + r) > 0.25 then
      love.graphics.rectangle("fill", x + T - 2, y + 14, 4, 36)
    elseif r % PERIOD == 1 and c % PERIOD >= STREET and hash(c + r * 3.1) > 0.25 and p.bands[r] ~= "road" then
      love.graphics.rectangle("fill", x + 14, y + T - 2, 36, 4)
    elseif p.bands[r] == "road" and y + T == p.cross and hash(c * 0.37) > 0.25 then
      love.graphics.rectangle("fill", x + 14, y + T - 2, 36, 4)
    end
  elseif kind == "rail" then
    color(C.ballast)
    love.graphics.rectangle("fill", x, y, T, T)
  elseif kind == "water" then
    color(C.water)
    love.graphics.rectangle("fill", x, y, T, T)
    if hash(c * 5.7 + r * 2.3) < 0.5 then
      color(C.waterLight)
      love.graphics.rectangle("fill", x + hash(c + r) * 30, y + 10 + hash(c * 2 + r) * 40, 30, 4)
    end
  end
end

--- The bands' long features across (x0, x1): the rails and sleepers, the
--- canal's lips, the Combine's wall. Each is anchored in the world.
local function bands(p, x0, x1)
  local s = p.rail
  if s then
    color(C.sleeper)
    for x = math.floor(x0 / 26) * 26, x1, 26 do
      love.graphics.rectangle("fill", x, s.y + s.h * 0.15, 10, s.h * 0.7)
    end
    color(C.rail)
    love.graphics.rectangle("fill", x0, s.y + s.h * 0.25, x1 - x0, 4)
    love.graphics.rectangle("fill", x0, s.y + s.h * 0.75, x1 - x0, 4)
  end
  if p.water0 then
    color(C.bank)
    love.graphics.rectangle("fill", x0, p.water0 - 8, x1 - x0, 8)
    love.graphics.rectangle("fill", x0, p.water1, x1 - x0, 8)
  end
  if p.wallY then
    local y, h = p.wallY, p.wallH
    color(C.shadow)
    love.graphics.rectangle("fill", x0, y + 12, x1 - x0, h)
    color(C.metal)
    love.graphics.rectangle("fill", x0, y, x1 - x0, h)
    for x = math.floor(x0 / 48) * 48, x1, 48 do
      color(math.floor(x / 48) % 2 == 0 and C.panel or C.panelLight)
      love.graphics.rectangle("fill", x + 4, y + 4, 40, h - 8)
    end
    color(C.glow)
    love.graphics.rectangle("fill", x0, y + h / 2 - 2, x1 - x0, 4)
  end
end

--- A heap of what used to be a block of flats.
local function ruin(b)
  local seed = b.seed
  color(C.rubbleDark)
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12, 10)
  for i = 1, math.floor(b.w * b.h / 1400) do
    local x = b.x + 8 + hash(seed + i * 1.7) * (b.w - 30)
    local y = b.y + 8 + hash(seed + i * 2.9) * (b.h - 30)
    color(i % 3 == 0 and C.rubbleDark or C.rubble)
    love.graphics.rectangle("fill", x, y, 10 + hash(seed + i * 4.1) * 18, 8 + hash(seed + i * 5.3) * 14, 2)
  end
  -- A wall or two still standing.
  color(C.rubbleDark)
  love.graphics.rectangle("fill", b.x + 4, b.y + 4, b.w * (0.3 + hash(seed) * 0.5), 10)
  love.graphics.rectangle("fill", b.x + 4, b.y + 4, 10, b.h * (0.3 + hash(seed + 1) * 0.5))
end

--- A black scorch round where a roof is burning, and the hole through it.
local function burnt(b)
  local f = b.fire
  color(C.scorch)
  love.graphics.circle("fill", f.x, f.y, f.r * 2.2, 20)
  for i = 1, 6 do
    local a = hash(f.seed + i * 3.1) * 2 * math.pi
    local d = f.r * 2.2 * (0.6 + hash(f.seed + i * 1.3) * 0.5)
    love.graphics.circle("fill", f.x + math.cos(a) * d, f.y + math.sin(a) * d, f.r * 0.7, 10)
  end
  love.graphics.setColor(0.03, 0.02, 0.02)
  love.graphics.rectangle("fill", f.x - f.r * 0.6, f.y - f.r * 0.5, f.r * 1.2, f.r, 4)
end

--- The tiles round a building, for Buildings.draw to find its front by.
local function tilesOf(p)
  return setmetatable({}, {
    __index = function(_, c)
      return setmetatable({}, {
        __index = function(_, r)
          return tileKind(p, c, r)
        end,
      })
    end,
  })
end

local function drawChunk(p, cx, cy)
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local x1, y1 = x0 + CHUNK, y0 + CHUNK
  local map = p.map
  local c0, c1 = math.floor((x0 - map.x0) / T), math.floor((x1 - map.x0) / T)
  local r0, r1 = math.floor((y0 - map.y0) / T), math.floor((y1 - map.y0) / T)
  -- Paving and its joints across the whole chunk in a few strokes, then
  -- whatever lies over it tile by tile.
  color(C.paving)
  love.graphics.rectangle("fill", x0, y0, CHUNK, CHUNK)
  color(C.joint)
  for c = c0, c1 do
    love.graphics.rectangle("fill", map.x0 + c * T, y0, 2, CHUNK)
  end
  for r = r0, r1 do
    love.graphics.rectangle("fill", x0, map.y0 + r * T, CHUNK, 2)
  end
  for c = c0, c1 do
    for r = r0, r1 do
      local kind = tileKind(p, c, r)
      if kind then
        ground(p, c, r, kind)
      end
    end
  end
  bands(p, x0 - 64, x1 + 64)
  -- Blocks a little past the chunk too: their shadows fall into it.
  local standing = {}
  eachBlock(p, x0 - 2 * T, y0 - 2 * T, x1 + T, y1 + T, function(b)
    if b.ruin then
      ruin(b)
    else
      standing[#standing + 1] = b
      color(C.shadow)
      love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
    end
  end)
  Buildings.draw({ kind = "city17", x0 = map.x0, y0 = map.y0, tiles = tilesOf(p), buildings = standing })
  for _, b in ipairs(standing) do
    if b.burning then
      burnt(b)
    end
  end
end

local chunks = { map = nil, list = {}, used = 0 } -- "cx,cy" -> { canvas, used }

local function chunk(p, cx, cy, budget)
  if chunks.map ~= p.map then
    for _, ch in pairs(chunks.list) do
      ch.canvas:release()
    end
    chunks.map, chunks.list = p.map, {}
  end
  local key = cx .. "," .. cy
  local ch = chunks.list[key]
  chunks.used = chunks.used + 1
  if ch then
    ch.used = chunks.used
    return ch
  end
  if budget.left <= 0 then
    return nil
  end
  budget.left = budget.left - 1
  local count, oldest = 0, nil
  for k, o in pairs(chunks.list) do
    count = count + 1
    if not oldest or o.used < chunks.list[oldest].used then
      oldest = k
    end
  end
  local canvas
  if count >= MAX_CHUNKS then -- the least used one's canvas does for this one
    canvas = chunks.list[oldest].canvas
    chunks.list[oldest] = nil
  else
    canvas = love.graphics.newCanvas(CHUNK / 2, CHUNK / 2)
    canvas:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.scale(0.5)
  love.graphics.translate(-cx * CHUNK, -cy * CHUNK)
  drawChunk(p, cx, cy)
  love.graphics.setCanvas()
  love.graphics.pop()
  ch = { canvas = canvas, used = chunks.used }
  chunks.list[key] = ch
  return ch
end

-- Every frame -----------------------------------------------------------------

--- The haze over everything past the map: thin by the wall, thicker and
--- thicker further out, in thin layers so it has no edges to see.
local function haze(map, left, top, right, bottom)
  local mx0, my0, mx1, my1 = map.left, map.top, map.left + map.w, map.top + map.h
  for i = 0, HAZE_LAYERS - 1 do
    local d = i * HAZE_STEP
    local x0, y0, x1, y1 = mx0 - d, my0 - d, mx1 + d, my1 + d
    love.graphics.setColor(HAZE[1], HAZE[2], HAZE[3], i == 0 and 0.2 or HAZE_EACH)
    love.graphics.rectangle("fill", left, top, right - left, math.max(0, y0 - top))
    love.graphics.rectangle("fill", left, y1, right - left, math.max(0, bottom - y1))
    love.graphics.rectangle("fill", left, y0, math.max(0, x0 - left), y1 - y0)
    love.graphics.rectangle("fill", x1, y0, math.max(0, right - x1), y1 - y0)
  end
end

--- The Combine's wall round the map, panels and a glowing seam, just past the edge.
local function perimeter(map)
  local x0, y0 = map.left - WALL, map.top - WALL
  local w, h = map.w + 2 * WALL, map.h + 2 * WALL
  local sides = {
    { x0, y0, w, WALL }, { x0, map.top + map.h, w, WALL },
    { x0, y0, WALL, h }, { map.left + map.w, y0, WALL, h },
  }
  for _, s in ipairs(sides) do
    color(C.shadow)
    love.graphics.rectangle("fill", s[1] + 10, s[2] + 10, s[3], s[4])
  end
  for _, s in ipairs(sides) do
    local x, y, sw, sh = s[1], s[2], s[3], s[4]
    color(C.metal)
    love.graphics.rectangle("fill", x, y, sw, sh)
    local long = sw > sh
    for k = 0, math.floor((long and sw or sh) / 48) - 1 do
      color(k % 2 == 0 and C.panel or C.panelLight)
      if long then
        love.graphics.rectangle("fill", x + k * 48 + 4, y + 4, 40, sh - 8)
      else
        love.graphics.rectangle("fill", x + 4, y + k * 48 + 4, sw - 8, 40)
      end
    end
    color(C.glow)
    if long then
      love.graphics.rectangle("fill", x, y + sh / 2 - 2, sw, 4)
    else
      love.graphics.rectangle("fill", x + sw / 2 - 2, y, 4, sh)
    end
  end
end

--- Draw it all over the box (left, top, right, bottom) the camera sees.
function City17.draw(map, camera, left, top, right, bottom, clock)
  local p = planFor(map)
  color(C.pavingDark) -- under any chunk not made yet
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local budget = { left = BUILD_PER_FRAME }
  love.graphics.setColor(1, 1, 1)
  for cx = math.floor(left / CHUNK), math.floor(right / CHUNK) do
    for cy = math.floor(top / CHUNK), math.floor(bottom / CHUNK) do
      local ch = chunk(p, cx, cy, budget)
      if ch then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(ch.canvas, cx * CHUNK, cy * CHUNK, 0, 2, 2)
      end
    end
  end
  haze(map, left, top, right, bottom)
  local fires = {}
  eachBlock(p, left - 300, top - 300, right + 300, bottom + 300, function(b)
    if b.fire then
      fires[#fires + 1] = b.fire
    end
  end)
  Fires.draw({ fires = fires }, camera, clock)
  perimeter(map)
end

return City17
