-- The Coast: a stop on A-Man's trail (city-map's `coast`). One long beach
-- winds north between the sea, out to the west, and green mountains that
-- come down to the sand on the east and keep everyone on it. It is narrow
-- most of the way, a few strides of sand, and opens out into wide coves
-- where there is room to fight: the landing everyone arrives in at the
-- bottom, the cove, the wreck (a boat lies beached in it) and the point
-- at the top, the way on. Between the cove and the long beach a spur of
-- the mountains runs down to the water and the way squeezes over the
-- rocks at its foot (the headland).
--
-- Tiles are "ground" (the sand, and the headland's rocks: walked) and
-- "water" (the sea: solid, `map.cover` kind "water" over it). The
-- mountains are no tile at all: the layout's walls fill every empty tile,
-- so they are solid to walk into and, like any wall, stop rounds and sight.
--
-- What it leaves on the map, besides tiles, solids and spawns:
--   map.cx, map.cy        the way home, on the landing's sand
--   map.exitX, map.exitY  the far end, on the point
--   map.coves             { name, x, y, w, h } each wide spot's sand, world px
--   map.zones             { name, y0, y1 } as City 17's: the coves and the headland
--   map.cover             { kind = "water" | "rock" | "log" | "boat" | "crate", x, y, w, h }, all solid;
--                         and kind "mountain" and "sand", not solid, only to colour the minimap
--   map.height            [c][r] tiles from the nearest walked or wet tile, for a mountain tile
--   map.depth             [c][r] tiles from the nearest dry tile, for a sea tile
--   map.wet               [c][r] tiles of sand between it and the sea (1 at the water's edge)
--   map.rocky             [c][r] true where the sand is the headland's rocks
--   map.slopes            { x, y, r, pine } trees on the mountainsides: drawn only, never touched
-- render_coast.lua draws it all.

local Coast = {}

-- The way up, bottom to top: { row, centre column, half width in tiles }.
-- Between two points the beach eases from one to the next.
Coast.SPINE = {
  { 112, 22, 7 }, -- the landing
  { 103, 22, 7 },
  { 97, 24, 3 },
  { 90, 29, 3 },
  { 85, 33, 8 }, -- the cove
  { 76, 33, 8 },
  { 72, 31, 2 }, -- the headland
  { 66, 27, 2 },
  { 60, 23, 3 }, -- the long beach
  { 50, 24, 3 },
  { 44, 30, 9 }, -- the wreck
  { 34, 33, 9 },
  { 29, 36, 3 },
  { 20, 40, 3 },
  { 15, 42, 7 }, -- the point
  { 8, 42, 6 },
}
-- The wide spots, by row (inclusive): the fights happen here.
Coast.COVES = {
  { name = "the landing", r0 = 101, r1 = 114, rocks = 3, logs = 3 },
  { name = "the cove", r0 = 75, r1 = 87, rocks = 6, logs = 3 },
  { name = "the wreck", r0 = 33, r1 = 46, rocks = 4, logs = 3, boat = true },
  { name = "the point", r0 = 6, r1 = 17, rocks = 5, logs = 2 },
}
Coast.HEADLAND = { r0 = 64, r1 = 73 } -- rows where the way runs over rocks
Coast.RAGGED = 1.3 -- tiles the sea's edge and the mountains' foot wander either way

-- How each kind shows on the minimap (minimap draws any cover with a `mapColor`).
local MAP = {
  mountain = { 0.22, 0.40, 0.20 },
  sand = { 0.80, 0.72, 0.52 },
  rock = { 0.45, 0.45, 0.42 },
  log = { 0.45, 0.33, 0.22 },
  boat = { 0.55, 0.30, 0.22 },
  crate = { 0.50, 0.40, 0.26 },
}

local function smooth(k)
  return k * k * (3 - 2 * k)
end

--- The spine at row `r`: centre column and half width, eased between points.
local function spineAt(r)
  local s = Coast.SPINE
  if r >= s[1][1] then
    return s[1][2], s[1][3]
  end
  for i = 1, #s - 1 do
    local a, b = s[i], s[i + 1]
    if r <= a[1] and r >= b[1] then
      local k = smooth((a[1] - r) / (a[1] - b[1]))
      return a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k
    end
  end
  return s[#s][2], s[#s][3]
end

--- Wandering by row: rng values every few rows, eased between, -1..1.
local function wander(rng, rows, every)
  local knots = {}
  for i = 0, math.ceil(rows / every) + 1 do
    knots[i] = rng:random() * 2 - 1
  end
  return function(r)
    local i = math.floor(r / every)
    local k = smooth(r / every - i)
    return knots[i] + (knots[i + 1] - knots[i]) * k
  end
end

--- Distance in tiles from every cell of the grid to the nearest cell `from`
--- says yes to (0 there), by two chamfer passes; nil for cells `inside`
--- says no to.
local function distances(cols, rows, from, inside)
  local d = {}
  local D, DD = 1, 1.414
  for c = 0, cols - 1 do
    d[c] = {}
    for r = 0, rows - 1 do
      d[c][r] = from(c, r) and 0 or math.huge
    end
  end
  local function relax(c, r, nc, nr, cost)
    if nc >= 0 and nc < cols and nr >= 0 and nr < rows and d[nc][nr] + cost < d[c][r] then
      d[c][r] = d[nc][nr] + cost
    end
  end
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      relax(c, r, c - 1, r, D)
      relax(c, r, c, r - 1, D)
      relax(c, r, c - 1, r - 1, DD)
      relax(c, r, c + 1, r - 1, DD)
    end
  end
  for r = rows - 1, 0, -1 do
    for c = cols - 1, 0, -1 do
      relax(c, r, c + 1, r, D)
      relax(c, r, c, r + 1, D)
      relax(c, r, c + 1, r + 1, DD)
      relax(c, r, c - 1, r + 1, DD)
    end
  end
  for c = 0, cols - 1 do
    for r = 0, rows - 1 do
      if not inside(c, r) then
        d[c][r] = nil
      end
    end
  end
  return d
end

--- Build it into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function Coast.build(map, rng, T)
  local cols, rows = map.cols, map.rows
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  map.cover, map.zones, map.coves, map.slopes = {}, {}, {}, {}
  map.rocky = {}

  -- Row by row: sea up to the waterline, sand to the mountains' foot,
  -- mountains past it. Past either end of the beach the mountains run down
  -- into the sea.
  local first, last = Coast.SPINE[#Coast.SPINE][1] - 2, Coast.SPINE[1][1] + 3
  local seaSide, hillSide = wander(rng, rows, 3), wander(rng, rows, 4)
  local sea, sand = {}, {}
  for c = 0, cols - 1 do
    map.tiles[c], sea[c], sand[c], map.rocky[c] = {}, {}, {}, {}
  end
  for r = 0, rows - 1 do
    local centre, half = spineAt(r)
    local wl = math.floor(centre - half + seaSide(r) * Coast.RAGGED + 0.5)
    local ml = math.floor(centre + half + hillSide(r) * Coast.RAGGED + 0.5)
    if r < first or r > last then
      ml = wl -- the mountains' end runs down into the sea
    end
    for c = 0, cols - 1 do
      if c < wl then
        sea[c][r] = true
        map.tiles[c][r] = "water"
      elseif c < ml then
        sand[c][r] = true
        map.tiles[c][r] = "ground"
        map.rocky[c][r] = r >= Coast.HEADLAND.r0 and r <= Coast.HEADLAND.r1 or nil
      end
    end
  end

  -- How high the mountains stand, how deep the sea runs, how wet the sand is.
  map.height = distances(cols, rows, function(c, r)
    return map.tiles[c][r] ~= nil
  end, function(c, r)
    return map.tiles[c][r] == nil
  end)
  map.depth = distances(cols, rows, function(c, r)
    return not sea[c][r]
  end, function(c, r)
    return sea[c][r]
  end)
  map.wet = distances(cols, rows, function(c, r)
    return sea[c][r]
  end, function(c, r)
    return sand[c][r]
  end)

  --- Every tile `is` says yes to as the fewest rectangles: a row's run
  --- merged with the one above when they line up.
  local function rects(is, kind, mapColor)
    local out, open = {}, {}
    for r = 0, rows - 1 do
      local row, c = {}, 0
      while c < cols do
        if is(c, r) then
          local start = c
          while c < cols and is(c, r) do
            c = c + 1
          end
          local key = start .. "," .. c
          local rc = open[key]
          if rc then
            rc.h = rc.h + T
          else
            rc = { kind = kind, x = X(start), y = Y(r), w = (c - start) * T, h = T, mapColor = mapColor }
            out[#out + 1] = rc
          end
          row[key] = rc
        else
          c = c + 1
        end
      end
      open = row
    end
    return out
  end
  -- The sea, solid; the mountains and the sand only for the minimap (the
  -- mountains are walls already), first so whatever is on the sand shows over it.
  for _, s in ipairs(rects(function(c, r)
    return sea[c][r]
  end, "water")) do
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
  end
  for _, s in ipairs(rects(function(c, r)
    return map.tiles[c][r] == nil
  end, "mountain", MAP.mountain)) do
    map.cover[#map.cover + 1] = s
  end
  for _, s in ipairs(rects(function(c, r)
    return sand[c][r]
  end, "sand", MAP.sand)) do
    map.cover[#map.cover + 1] = s
  end

  -- The wide spots: their sand's bounds, as zones.
  local function sandBounds(r0, r1)
    local c0, c1 = math.huge, -math.huge
    for r = r0, r1 do
      for c = 0, cols - 1 do
        if sand[c][r] then
          c0, c1 = math.min(c0, c), math.max(c1, c)
        end
      end
    end
    return X(c0), Y(r0), (c1 - c0 + 1) * T, (r1 - r0 + 1) * T
  end
  for _, def in ipairs(Coast.COVES) do
    local x, y, w, h = sandBounds(def.r0, def.r1)
    local cove = { name = def.name, x = x, y = y, w = w, h = h, def = def }
    map.coves[#map.coves + 1] = cove
    map.zones[#map.zones + 1] = { name = def.name, y0 = y, y1 = y + h }
  end
  map.zones[#map.zones + 1] = { name = "the headland", y0 = Y(Coast.HEADLAND.r0), y1 = Y(Coast.HEADLAND.r1 + 1) }

  -- Arrival on the landing, the way home beside it, the way on at the top.
  local landing, point = map.coves[1], map.coves[#map.coves]
  local function sandMiddle(r)
    local c0, c1
    for c = 0, cols - 1 do
      if sand[c][r] then
        c0, c1 = c0 or c, c
      end
    end
    return X((c0 + c1 + 1) / 2)
  end
  local arriveRow = landing.def.r1 - 4
  local ax = sandMiddle(arriveRow)
  map.cx, map.cy = math.floor(ax - 200), math.floor(Y(arriveRow + 0.5))
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = ax - 120 + (i % 4) * 90, y = Y(arriveRow - 1) + math.floor(i / 4) * 70, angle = -math.pi / 2,
    }
  end
  map.exitX, map.exitY = math.floor(sandMiddle(point.def.r0 + 2)), math.floor(Y(point.def.r0 + 2.5))

  -- Cover on the sand: kept off the surf, the mountains' foot, the arrival
  -- and the way on.
  local placed = {
    { x = map.cx, y = map.cy, r = 120 }, { x = ax, y = Y(arriveRow + 1), r = 260 },
    { x = map.exitX, y = map.exitY, r = 150 },
  }
  local function free(x, y, r)
    for _, q in ipairs(placed) do
      if (q.x - x) ^ 2 + (q.y - y) ^ 2 < (q.r + r + 60) ^ 2 then
        return false
      end
    end
    return true
  end
  local function onDrySand(x, y, pad)
    for _, k in ipairs({ { 0, 0 }, { pad, 0 }, { -pad, 0 }, { 0, pad }, { 0, -pad } }) do
      local c, r = math.floor((x + k[1] - map.x0) / T), math.floor((y + k[2] - map.y0) / T)
      local wet = map.wet[c] and map.wet[c][r]
      if not wet or wet < 1.5 then
        return false
      end
    end
    -- Not hard against the mountains either: a stride of sand behind it.
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    for dc = -1, 1 do
      for dr = -1, 1 do
        if not (map.tiles[c + dc] and map.tiles[c + dc][r + dr]) then
          return false
        end
      end
    end
    return true
  end
  local function cover(kind, x, y, w, h)
    local s = { kind = kind, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
      mapColor = MAP[kind], seed = rng:random(1000) }
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
    placed[#placed + 1] = { x = x + w / 2, y = y + h / 2, r = math.max(w, h) / 2 }
    return s
  end
  --- `n` of `kind` somewhere on cove `cv`.
  local function scatter(cv, kind, n)
    local got = 0
    for _ = 1, 400 do
      if got >= n then
        return
      end
      local x, y = cv.x + rng:random() * cv.w, cv.y + rng:random() * cv.h
      local w, h
      if kind == "rock" then
        w = 50 + rng:random() * 50
        h = w * (0.7 + rng:random() * 0.3)
      else -- a log of driftwood, lying either way
        local len = 110 + rng:random() * 70
        if rng:random() < 0.5 then
          w, h = len, 24
        else
          w, h = 24, len
        end
      end
      if onDrySand(x, y, math.max(w, h) / 2 + 20) and free(x, y, math.max(w, h) / 2) then
        cover(kind, x - w / 2, y - h / 2, w, h)
        got = got + 1
      end
    end
  end
  for _, cv in ipairs(map.coves) do
    if cv.def.boat then
      -- The wreck: a boat run up the sand, bow to the mountains, crates spilled round it.
      local x, y = cv.x + cv.w * 0.45, cv.y + cv.h * 0.5
      for _ = 1, 40 do
        if onDrySand(x, y, 140) then
          break
        end
        x = x + 20
      end
      cover("boat", x - 130, y - 48, 260, 96)
      for i = 1, 4 do
        local a = i * 1.6
        local cx, cy = x + math.cos(a) * 220, y + math.sin(a) * 150
        if onDrySand(cx, cy, 40) and free(cx, cy, 30) then
          cover("crate", cx - 26, cy - 26, 52, 52)
        end
      end
    end
    scatter(cv, "rock", cv.def.rocks)
    scatter(cv, "log", cv.def.logs)
  end
  -- Now and then a rock along the narrow stretches, against the mountains' foot.
  for r = 4, rows - 5, 5 do
    local inCove = false
    for _, cv in ipairs(map.coves) do
      inCove = inCove or (r >= cv.def.r0 - 1 and r <= cv.def.r1 + 1)
    end
    if not inCove and rng:random() < 0.6 then
      local c1
      for c = 0, cols - 1 do
        if sand[c][r] then
          c1 = c
        end
      end
      if c1 then
        local s = 40 + rng:random() * 24
        local x, y = X(c1 + 1) - s - 8, Y(r) + rng:random() * (T - s)
        local c, rr = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
        if sand[c] and sand[c][rr] and (map.wet[c][rr] or 0) >= 2 then
          cover("rock", x, y, s, s * 0.85)
        end
      end
    end
  end

  -- The mountainsides: thick with trees low down, thinning a little higher up.
  for _ = 1, math.floor(cols * rows * 1.6) do
    local x, y = X(rng:random() * cols), Y(rng:random() * rows)
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    local h = map.height[c] and map.height[c][r]
    if h and h > 0.6 and rng:random() < math.max(0.3, 0.9 - h / 25) then
      map.slopes[#map.slopes + 1] = { x = x, y = y, r = 14 + rng:random() * 12, pine = rng:random() < 0.55 }
    end
  end
  table.sort(map.slopes, function(a, b) -- drawn top to bottom, the nearer canopy over the one behind
    return a.y < b.y
  end)
end

return Coast
