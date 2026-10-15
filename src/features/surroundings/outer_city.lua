-- The Outer City past its edges (surroundings' entry for `outercity`):
-- City 17's outskirts carry on, out of reach. Rows of decayed blocks
-- between streets in the map's own colours (city-map's render.lua), some
-- fallen to rubble, roofs holed and grown over, a few burning; a square
-- or an overgrown park in place of a block here and there; the map's two
-- waterways running on out of its top and left edges, and more canals
-- crossing the outskirts further out. A Combine wall runs round the map's
-- edge where nobody gets past, grilles over the waterways where they go
-- through it, and further north City 17's own wall runs right across. A
-- haze hangs over all of it, thicker further out (City 17's).
--
-- Every tile and block is worked out from where it sits, so it is the same
-- on every machine and never runs out; it is drawn once into chunks
-- (chunks.lua) and the fires on top every frame (city-map's fires.lua).

local Layout = require("src.features.city-map.layout")
local Buildings = require("src.features.city-map.buildings")
local Fires = require("src.features.city-map.fires")
local City17 = require("src.features.surroundings.city17")
local Chunks = require("src.features.surroundings.chunks")

local OuterCity = {}

local T = Layout.TILE
local PERIOD = 9 -- tiles from one street to the next
local STREET = 2 -- tiles of road in each
local WALL = 28 -- px; the Combine's wall round the map
local NORTH_WALL = -18 -- the row City 17's wall runs along, north of the map
local CANAL_EVERY = 0.22 -- of the streets well clear of the map, how many are canals instead

-- The map's waterways where they leave it: the north one's columns, the west one's rows.
local NORTH_CANAL = { 34, 37 }
local WEST_CANAL = { 30, 32 }

-- city-map's Outer City colours (render.lua's OC and C17).
local C = {
  slab = { 0.50, 0.49, 0.46 }, slabDark = { 0.45, 0.44, 0.41 }, joint = { 0.38, 0.38, 0.36 },
  stain = { 0.38, 0.37, 0.33 }, earth = { 0.33, 0.28, 0.21 }, weed = { 0.30, 0.42, 0.20 },
  weedLight = { 0.42, 0.54, 0.26 }, moss = { 0.30, 0.36, 0.22, 0.45 }, grass = { 0.33, 0.45, 0.22 },
  grassDry = { 0.46, 0.47, 0.27 }, canopy = { 0.16, 0.36, 0.16 }, canopyLight = { 0.28, 0.52, 0.24 },
  road = { 0.20, 0.20, 0.21 }, roadLine = { 0.62, 0.60, 0.52 }, water = { 0.13, 0.22, 0.24 },
  waterLight = { 0.20, 0.32, 0.34 }, algae = { 0.20, 0.32, 0.16, 0.45 }, bank = { 0.55, 0.54, 0.50 },
  concrete = { 0.64, 0.62, 0.57 }, concreteDark = { 0.50, 0.48, 0.44 }, rubble = { 0.45, 0.43, 0.40 },
  rubbleDark = { 0.33, 0.31, 0.29 }, rust = { 0.45, 0.24, 0.12 }, rustDark = { 0.28, 0.15, 0.09 },
  hole = { 0.10, 0.09, 0.09 }, soot = { 0, 0, 0, 0.22 }, vine = { 0.20, 0.36, 0.16 },
  vineLight = { 0.30, 0.48, 0.20 }, metal = { 0.12, 0.14, 0.17 }, glow = { 0.45, 0.85, 1.00 },
  shadow = { 0, 0, 0, 0.35 },
}
-- The map's roofs: concrete, mostly, greys and dirty pale tones, a brick or two.
local ROOFS = {
  { 0.46, 0.46, 0.45 }, { 0.38, 0.39, 0.41 }, { 0.52, 0.50, 0.46 }, { 0.33, 0.34, 0.36 }, { 0.48, 0.38, 0.32 },
  { 0.42, 0.44, 0.40 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- 0..1 from `n`, the same on every machine.
local function hash(n)
  local v = math.sin(n * 1.731 + 0.37) * 43758.5453
  return v - math.floor(v)
end

local chunks = Chunks.new(1024, 24, 1)

-- The plan: what is where ---------------------------------------------------

--- Is street line `i` (columns or rows, by `axis`) a canal? Only ones that
--- never meet the map: wholly left or right of it (columns), above or below it (rows).
local function canalLine(map, i, axis)
  local from, to = i * PERIOD, i * PERIOD + STREET - 1
  local size = axis == "c" and map.cols or map.rows
  if to >= -3 and from <= size + 2 then
    return false
  end
  return hash(i * 3.71 + (axis == "c" and 11 or 29)) < CANAL_EVERY
end

--- What is on tile (c, r) past the map: "water", "bridgeEW" or "bridgeNS"
--- (a street over it, running that way), "quay" (paving along a canal),
--- "ring" (the pavement under the wall round the map), "wall" (under City
--- 17's wall), "road" or "walk". nil inside the map.
local function tileKind(map, c, r)
  if c >= 0 and c < map.cols and r >= 0 and r < map.rows then
    return nil
  end
  local sc, sr = c % PERIOD < STREET, r % PERIOD < STREET
  local canalC = sc and canalLine(map, math.floor(c / PERIOD), "c")
  local canalR = sr and canalLine(map, math.floor(r / PERIOD), "r")
  -- The map's waterways, on out of its top and left edges.
  local north = r < 0 and c >= NORTH_CANAL[1] and c <= NORTH_CANAL[2]
  local west = c < 0 and r >= WEST_CANAL[1] and r <= WEST_CANAL[2]
  local ring = c >= -1 and c <= map.cols and r >= -1 and r <= map.rows
  local wall = r == NORTH_WALL or r == NORTH_WALL + 1
  if north or west or canalC or canalR then
    -- A street crossing the water goes over it on a bridge (not by the map
    -- or under the wall, where nothing crosses).
    if not ring and not wall then
      if (north or canalC) and sr and not canalR then
        return "bridgeEW"
      elseif (west or canalR) and sc and not canalC then
        return "bridgeNS"
      end
    end
    return "water"
  end
  local northQuay = r < 0 and (c == NORTH_CANAL[1] - 1 or c == NORTH_CANAL[2] + 1) and not sr
  local westQuay = c < 0 and (r == WEST_CANAL[1] - 1 or r == WEST_CANAL[2] + 1) and not sc
  if northQuay or westQuay then
    return "quay"
  end
  if ring then
    return "ring"
  elseif wall then
    return "wall"
  elseif sc or sr then
    return "road"
  end
  return "walk"
end

local blocks = { map = nil, list = {} }

--- Block (bc, br) between the streets: { kind = "square" | "park" | "built",
--- buildings, ruins, trees, fires }, worked out once. nil where it runs into
--- the map, its wall or a waterway.
local function block(map, bc, br)
  if blocks.map ~= map then
    blocks.map, blocks.list = map, {}
  end
  local key = bc .. "," .. br
  local got = blocks.list[key]
  if got ~= nil then
    return got or nil
  end
  -- The block's tiles between the streets, less a pavement round it and
  -- anything that isn't paving (the ring, a quay, the wall): the longest
  -- run of clear rows, then the longest run of clear columns across them.
  local first, last = STREET + 1, PERIOD - 2
  local function run(clear)
    local best0, bestN, from = nil, 0, nil
    for k = first, last + 1 do
      local ok = k <= last and clear(k)
      if ok and not from then
        from = k
      elseif not ok and from then
        if k - from > bestN then
          best0, bestN = from, k - from
        end
        from = nil
      end
    end
    return best0, bestN
  end
  local function walk(c, r)
    for dc = -1, 1 do
      for dr = -1, 1 do
        if tileKind(map, c + dc, r + dr) ~= "walk" then
          return false
        end
      end
    end
    return true
  end
  local rk, nr = run(function(k)
    for k2 = first, last do
      if walk(bc * PERIOD + k2, br * PERIOD + k) then
        return true
      end
    end
    return false
  end)
  local ck, nc
  if rk then
    ck, nc = run(function(k)
      for k2 = rk, rk + nr - 1 do
        if not walk(bc * PERIOD + k, br * PERIOD + k2) then
          return false
        end
      end
      return true
    end)
  end
  if not ck or nc < 2 or nr < 2 then
    blocks.list[key] = false
    return nil
  end
  local c0, r0 = bc * PERIOD + ck, br * PERIOD + rk
  local seed = bc * 71.3 + br * 13.9
  local x, y = map.x0 + c0 * T, map.y0 + r0 * T
  got = { x = x, y = y, w = nc * T, h = nr * T, buildings = {}, ruins = {}, trees = {}, fires = {}, seed = seed }
  local fate = hash(seed)
  if fate < 0.07 then
    got.kind = "square"
  elseif fate < 0.16 then
    got.kind = "park"
    for i = 1, 9 do
      local tx, ty = x + 40 + hash(seed + i * 2.3) * (got.w - 80), y + 40 + hash(seed + i * 4.1) * (got.h - 80)
      got.trees[#got.trees + 1] = { x = tx, y = ty, r = 18 + hash(seed + i * 6.7) * 14 }
    end
  else
    -- Packed tight: the block cut in two each way at odd places, a cut
    -- left out now and then so some buildings run across.
    got.kind = "built"
    local function cuts(n, h)
      if n < 4 or h > 0.8 then
        return { { 0, n } }
      end
      local cut = 2 + math.floor(hash(seed + h * 10) * (n - 3))
      return { { 0, cut }, { cut, n } }
    end
    local cols, rows = cuts(nc, hash(seed + 3)), cuts(nr, hash(seed + 4))
    for i, cc in ipairs(cols) do
      for j, rr in ipairs(rows) do
        local s = seed + i * 7.7 + j * 3.3
        local b = { x = x + cc[1] * T, y = y + rr[1] * T, w = (cc[2] - cc[1]) * T, h = (rr[2] - rr[1]) * T,
          color = ROOFS[math.floor(hash(s + 5) * #ROOFS) + 1], style = 1 + math.floor(hash(s + 6) * 3),
          seed = math.floor(hash(s + 7) * 1000) }
        local roll = hash(s + 8)
        if roll < 0.15 then -- come down: a heap where it stood
          got.ruins[#got.ruins + 1] = b
        else
          if roll < 0.45 then
            b.holes = {}
            for k = 1, 1 + math.floor(hash(s + 9) * 2) do
              b.holes[k] = { x = 24 + hash(s + k * 1.3) * (b.w - 48), y = 24 + hash(s + k * 2.9) * (b.h - 48),
                r = 8 + hash(s + k * 4.4) * 12, seed = s + k }
            end
          end
          b.vines = hash(s + 10) < 0.35 and math.floor(hash(s + 11) * 1000) or nil
          if hash(s + 12) < 0.09 and b.w >= 2 * T and b.h >= 2 * T then
            b.burning = true
            got.fires[#got.fires + 1] = { kind = "roof", x = b.x + b.w * (0.3 + hash(s + 13) * 0.4),
              y = b.y + b.h * (0.3 + hash(s + 14) * 0.4), r = 26, seed = b.seed }
          end
          got.buildings[#got.buildings + 1] = b
        end
      end
    end
  end
  blocks.list[key] = got
  return got
end

--- Every block with a tile in the box (left, top, right, bottom).
local function eachBlock(map, left, top, right, bottom, fn)
  local P = PERIOD * T
  for bc = math.floor((left - map.x0) / P), math.floor((right - map.x0) / P) do
    for br = math.floor((top - map.y0) / P), math.floor((bottom - map.y0) / P) do
      local b = block(map, bc, br)
      if b then
        fn(b)
      end
    end
  end
end

-- Drawing a chunk -------------------------------------------------------------

--- A tuft of weeds up through the paving.
local function weeds(x, y, size, seed)
  love.graphics.setLineWidth(2)
  for i = 1, 4 do
    color(i % 2 == 0 and C.weed or C.weedLight)
    local a = -math.pi / 2 + (hash(seed + i) - 0.5) * 2.4
    love.graphics.line(x, y, x + math.cos(a) * size, y + math.sin(a) * size)
  end
  love.graphics.setLineWidth(1)
end

--- Tile (c, r) of `kind`: the slabs, the road, the canal.
local function ground(map, c, r, kind)
  local x, y = map.x0 + c * T, map.y0 + r * T
  local h = hash(c * 13.1 + r * 7.7)
  if kind == "road" then
    color(C.road)
    love.graphics.rectangle("fill", x, y, T, T)
    if h < 0.08 then -- a pothole
      color(C.hole, 0.6)
      love.graphics.ellipse("fill", x + 20 + h * 200, y + 32, 12, 8)
    end
    -- The worn line down the middle of the street, where its two lanes meet.
    color(C.roadLine, 0.8)
    local alongC, alongR = c % PERIOD == 0, r % PERIOD == 0
    if alongC and r % PERIOD >= STREET and h > 0.3 then
      love.graphics.rectangle("fill", x + T - 2, y + 14, 4, 36)
    elseif alongR and c % PERIOD >= STREET and h > 0.3 then
      love.graphics.rectangle("fill", x + 14, y + T - 2, 36, 4)
    end
  elseif kind == "bridgeEW" or kind == "bridgeNS" then
    -- A worn concrete deck, a rail along each side of the street over it.
    local ew = kind == "bridgeEW"
    color(C.concrete)
    love.graphics.rectangle("fill", x, y, T, T)
    color(C.concreteDark)
    local k = (ew and r or c) % PERIOD
    if k == 0 then
      love.graphics.rectangle("fill", x, y, ew and T or 8, ew and 8 or T)
    elseif k == STREET - 1 then
      love.graphics.rectangle("fill", ew and x or x + T - 8, ew and y + T - 8 or y, ew and T or 8, ew and 8 or T)
    end
    if h < 0.3 then -- a crack across it
      love.graphics.setLineWidth(2)
      love.graphics.line(x + 12, y + 20 + h * 60, x + 40, y + 30, x + 56, y + 18 + h * 40)
      love.graphics.setLineWidth(1)
    end
  elseif kind == "water" then
    color(C.water)
    love.graphics.rectangle("fill", x, y, T, T)
    if h < 0.5 then
      color(C.waterLight)
      love.graphics.rectangle("fill", x + h * 50, y + 10 + hash(h * 7) * 40, 30, 4)
    end
    if h > 0.8 then
      color(C.algae)
      love.graphics.circle("fill", x + hash(h * 3) * T, y + hash(h * 5) * T, 14 + h * 16, 14)
    end
  else
    color((c + r) % 2 == 0 and C.slab or C.slabDark)
    love.graphics.rectangle("fill", x, y, T, T)
    if h < 0.06 then -- the slab is gone: earth, and weeds in it
      color(C.earth)
      love.graphics.rectangle("fill", x + 3, y + 3, T - 6, T - 6, 4)
      weeds(x + T * 0.5, y + T * 0.6, 11, c + r * 3)
      return
    end
    if h > 0.78 then -- a stain spreading over it
      color(C.stain)
      love.graphics.circle("fill", x + hash(h * 31) * T, y + hash(h * 17) * T, 12 + hash(h * 5) * 16, 12)
    end
    color(C.joint)
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
    if hash(c * 2.1 + r * 5.3) < 0.2 then
      weeds(x + 2 + hash(c + r * 9) * (T - 4), y + 2, 6 + hash(c * 5 + r) * 6, c * 11 + r)
    end
    if hash(c * 7.9 + r * 3.1) < 0.1 then
      color(C.moss)
      love.graphics.circle("fill", x + hash(c * 4 + r) * T, y + hash(c + r * 4) * T, 16, 12)
    end
  end
end

--- The canals' lips, where the water meets the paving, over the tiles of
--- (c0, r0)-(c1, r1).
local function lips(map, c0, r0, c1, r1)
  color(C.bank)
  for c = c0, c1 do
    for r = r0, r1 do
      if tileKind(map, c, r) == "water" then
        local x, y = map.x0 + c * T, map.y0 + r * T
        for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          local k = tileKind(map, c + e[1], r + e[2])
          if k and k ~= "water" and k ~= "bridgeEW" and k ~= "bridgeNS" then
            love.graphics.rectangle("fill", e[1] > 0 and x + T - 8 or x, e[2] > 0 and y + T - 8 or y,
              e[1] == 0 and T or 8, e[2] == 0 and T or 8)
          end
        end
      end
    end
  end
end

--- A park: grass gone to seed, trees.
local function park(b)
  color(C.grass)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  for i = 1, 12 do
    color(C.grassDry)
    love.graphics.circle("fill", b.x + hash(b.seed + i) * b.w, b.y + hash(b.seed + i * 1.9) * b.h,
      20 + hash(b.seed + i * 3.7) * 30, 14)
  end
  for _, t in ipairs(b.trees) do
    color(C.shadow)
    love.graphics.circle("fill", t.x + 8, t.y + 8, t.r)
  end
  for _, t in ipairs(b.trees) do
    color(C.canopy)
    love.graphics.circle("fill", t.x, t.y, t.r)
    color(C.canopyLight)
    love.graphics.circle("fill", t.x - t.r / 4, t.y - t.r / 4, t.r / 2)
  end
end

--- A square: two broken rings of darker slabs round the middle and a dry
--- fountain in it, a wreck left on it.
local function square(b)
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  local r = b.w * 0.36
  color(C.concreteDark, 0.6)
  love.graphics.setLineWidth(20)
  for k = 0, 7 do
    if hash(b.seed + k * 3.7) > 0.25 then
      love.graphics.arc("line", "open", cx, cy, r, k * math.pi / 4, (k + 1) * math.pi / 4, 8)
    end
  end
  love.graphics.setLineWidth(1)
  color(C.concrete)
  love.graphics.circle("fill", cx, cy, 52, 28)
  color(C.earth)
  love.graphics.circle("fill", cx, cy, 42, 28)
  weeds(cx - 8, cy + 10, 14, b.seed)
  weeds(cx + 12, cy - 6, 10, b.seed + 5)
  local wx, wy = b.x + b.w * (0.15 + hash(b.seed + 9) * 0.5), b.y + b.h * 0.82
  color(C.shadow)
  love.graphics.rectangle("fill", wx + 6, wy + 6, 84, 42, 6)
  color(C.rustDark)
  love.graphics.rectangle("fill", wx, wy, 84, 42, 6)
  color(C.rust)
  love.graphics.rectangle("fill", wx + 3, wy + 3, 78, 36, 5)
  color(C.hole)
  love.graphics.rectangle("fill", wx + 26, wy + 7, 30, 28, 3)
end

--- A building come down: a heap of broken concrete where it stood.
local function ruin(b)
  color(C.rubbleDark)
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12, 10)
  for i = 1, math.floor(b.w * b.h / 1500) do
    color(i % 3 == 0 and C.rubbleDark or C.rubble)
    love.graphics.rectangle("fill", b.x + 8 + hash(b.seed + i * 1.7) * (b.w - 30),
      b.y + 8 + hash(b.seed + i * 2.9) * (b.h - 30), 10 + hash(b.seed + i * 4.1) * 18,
      8 + hash(b.seed + i * 5.3) * 14, 2)
  end
end

--- What the years have done to a roof: holes through it, vines over its
--- edges, soot round a fire.
local function damage(b)
  for _, h in ipairs(b.holes or {}) do
    local x, y = b.x + h.x, b.y + h.y
    color(C.soot)
    love.graphics.circle("fill", x, y, h.r * 1.5, 12)
    color(C.hole)
    love.graphics.circle("fill", x, y, h.r, 7)
    color(C.rubbleDark)
    love.graphics.setLineWidth(3)
    love.graphics.line(x - h.r, y - h.r * 0.2, x + h.r, y + h.r * 0.1) -- a joist still across it
    love.graphics.setLineWidth(1)
  end
  if b.vines then
    for i = 1, math.floor((b.w + b.h) / 40) do
      local t, side = hash(b.vines + i * 1.7), math.floor(hash(b.vines + i * 3.1) * 4)
      local x = side < 2 and b.x + t * b.w or (side == 2 and b.x or b.x + b.w)
      local y = side >= 2 and b.y + t * b.h or (side == 0 and b.y or b.y + b.h)
      color(i % 2 == 0 and C.vine or C.vineLight)
      love.graphics.circle("fill", x, y, 10 + hash(b.vines + i) * 12, 10)
    end
  end
  if b.burning then
    color(C.soot)
    love.graphics.circle("fill", b.x + b.w / 2, b.y + b.h / 2, math.min(b.w, b.h) * 0.3, 16)
  end
end

--- The tiles round a building, for Buildings.draw to find its front by:
--- each column a table that works its tiles out as they are asked for.
local column = {
  __index = function(col, r)
    return tileKind(col.map, col.c, r)
  end,
}
local function tilesOf(map)
  return setmetatable({}, {
    __index = function(_, c)
      return setmetatable({ map = map, c = c }, column)
    end,
  })
end

--- A grille in a wall over the water (x, y, w, h): the water between bars
--- across the way it flows (`across` for water flowing north-south).
local function grille(x, y, w, h, across)
  color(C.water)
  love.graphics.rectangle("fill", x, y, w, h)
  color(C.metal)
  for k = 0, (across and w or h) - 1, 16 do
    love.graphics.rectangle("fill", across and x + k or x, across and y or y + k, across and 6 or w, across and h or 6)
  end
  color(C.glow, 0.6)
  love.graphics.rectangle("fill", across and x or x + w / 2 - 2, across and y + h / 2 - 2 or y, across and w or 4,
    across and 4 or h)
end

local function paint(map, x0, y0, x1, y1)
  local c0, c1 = math.floor((x0 - map.x0) / T), math.floor((x1 - map.x0) / T)
  local r0, r1 = math.floor((y0 - map.y0) / T), math.floor((y1 - map.y0) / T)
  for c = c0, c1 do
    for r = r0, r1 do
      local kind = tileKind(map, c, r)
      if kind then
        ground(map, c, r, kind)
      end
    end
  end
  lips(map, c0, r0, c1, r1)
  -- Blocks a little past the chunk too: their shadows and trees reach into it.
  local tiles = tilesOf(map)
  eachBlock(map, x0 - 2 * T, y0 - 2 * T, x1 + T, y1 + T, function(b)
    if b.kind == "park" then
      park(b)
    elseif b.kind == "square" then
      square(b)
    else
      for _, o in ipairs(b.ruins) do
        ruin(o)
      end
      color(C.shadow)
      for _, o in ipairs(b.buildings) do
        love.graphics.rectangle("fill", o.x + 14, o.y + 14, o.w, o.h)
      end
      Buildings.draw({ kind = "outercity", x0 = map.x0, y0 = map.y0, tiles = tiles, buildings = b.buildings })
      for _, o in ipairs(b.buildings) do
        damage(o)
      end
    end
  end)
  local wy = map.y0 + NORTH_WALL * T
  if wy < y1 and wy + 2 * T > y0 then
    City17.wall(x0 - 64, x1 + 64, wy, 2 * T - 16)
    for c = c0, c1 do -- grilles where the water goes under it
      if tileKind(map, c, NORTH_WALL) == "water" then
        grille(map.x0 + c * T, wy, T, 2 * T - 16, true)
      end
    end
  end
end

-- Every frame -----------------------------------------------------------------

--- City 17's wall round the map's edge, with grilles where the waterways
--- pass under it.
local function perimeter(map)
  City17.perimeter(map)
  local x0, y0 = map.left - WALL, map.top - WALL
  local north = NORTH_CANAL[2] - NORTH_CANAL[1] + 1
  local west = WEST_CANAL[2] - WEST_CANAL[1] + 1
  grille(map.x0 + NORTH_CANAL[1] * T, y0, north * T, WALL, true)
  grille(x0, map.y0 + WEST_CANAL[1] * T, WALL, west * T, false)
end

--- Draw it all over the box (left, top, right, bottom) the camera sees.
function OuterCity.draw(map, camera, left, top, right, bottom, clock)
  color(C.slabDark) -- under any chunk not made yet
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  chunks:draw(map, left, top, right, bottom, function(x0, y0, x1, y1)
    paint(map, x0, y0, x1, y1)
  end)
  City17.haze(map, left, top, right, bottom)
  local fires = {}
  eachBlock(map, left - 300, top - 300, right + 300, bottom + 300, function(b)
    for _, f in ipairs(b.fires) do
      fires[#fires + 1] = f
    end
  end)
  Fires.draw({ fires = fires }, camera, clock)
  perimeter(map)
end

return OuterCity
