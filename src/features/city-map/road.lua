-- The Winding Road: the last stop on A-Man's trail before the Citadel
-- (city-map's `road`), and the one that is driven. One long mountain road
-- climbs north from the valley floor to the pass at the top, in and out
-- of the mountains, up a stack of hairpins, and over the river that runs
-- down beside it again and again on its bridges.
--
-- The road and the river are each a line of points (`Road.ROAD`,
-- `Road.RIVER`, in tiles) eased into a curve. Every tile is decided by how
-- far it lies from them:
--   "road"   the tarmac, near the road's line (asphalt drawn smooth over it)
--   "ground" the verge either side of it, the river's banks, the meadows
--            in the valleys and the wide spots (`Road.SPOTS`): walked and driven
--   "water"  the river: solid, `map.cover` kind "water" over it
--   nil      the mountains: the layout's walls fill every empty tile, so
--            they are solid, and stop rounds and sight like any wall
-- Where the road crosses the river the water under it is a bridge deck
-- ("road" tiles, `map.bridges`), railings along both sides of it.
--
-- What it leaves on the map, besides tiles, solids and spawns:
--   map.cx, map.cy        the way home, on the verge by the arrival
--   map.exitX, map.exitY  the far end, on the pass
--   map.path              { x, y } the road's middle every few px, world px, bottom to top
--   map.river             { x, y, half } the river's middle, world px, top (its source) to bottom
--   map.bridges           { x, y, w, h, along = "ns" | "ew", name } decks over the water, world px;
--                         `along` is the way the road runs over it
--   map.spots             { name, x, y, r } the wide spots, world px
--   map.zones             { name, y0, y1 } as City 17's: the stretches of the road
--   map.cover             { kind = "water" | "rail", x, y, w, h }, solid; and kind "mountain",
--                         not solid, only to colour the minimap
--   map.height            [c][r] tiles from the nearest open tile, for a mountain tile
--   map.depth             [c][r] tiles from the nearest bank, for a river tile
--   map.slopes            { x, y, r, pine } trees on the mountainsides: drawn only, never touched
--   map.posts             empty, for the Combine later
-- render_road.lua draws it all.

local Coast = require("src.features.city-map.coast")

local Road = {}

-- The road's middle, bottom to top: { column, row }. The ends run straight
-- (the arrival, the pass); everything between is eased through.
Road.ROAD = {
  { 30, 232 }, -- off the bottom edge, so the road comes from somewhere
  { 30, 214 }, -- the arrival
  { 30, 204 },
  { 36, 192 },
  { 46, 184 },
  { 56, 182 },
  { 64, 182 }, -- over the river, the first bridge
  { 70, 178 },
  { 72, 166 },
  { 66, 152 },
  { 54, 146 },
  { 40, 144 }, -- the meadow
  { 28, 145 }, -- the second bridge
  { 16, 140 },
  { 16, 132 },
  { 26, 128 },
  { 40, 130 },
  -- The hairpins: up the mountainside in five legs, east and west.
  { 62, 128 },
  { 68, 122 },
  { 62, 116 },
  { 40, 114 },
  { 34, 108 },
  { 40, 102 },
  { 62, 100 },
  { 68, 94 },
  { 62, 88 },
  { 44, 86 },
  -- The gorge: west along the ledge and straight over it on the high bridge.
  { 30, 82 },
  { 14, 76 },
  { 8, 66 },
  { 14, 56 }, -- the lookout
  { 24, 50 },
  { 36, 46 }, -- the third bridge
  { 48, 42 },
  { 62, 36 },
  { 66, 26 },
  { 60, 18 },
  { 52, 15 },
  { 44, 15 }, -- the top bridge
  { 40, 10 }, -- the pass
  { 40, 0 },
  { 40, -8 }, -- off the top edge: on to the Citadel
}
-- The river from its source at the top down to where it leaves at the
-- bottom: { column, row, half width in tiles, banks either side in tiles }.
Road.RIVER = {
  { 48, -4, 1.2, 0 },
  { 48, 10, 1.2, 0.6 },
  { 42, 28, 1.3, 0.6 },
  { 34, 40, 1.4, 1 },
  { 30, 54, 1.4, 1.5 },
  { 36, 66, 1.3, 0 }, -- down the gorge, under the ledge
  { 30, 80, 1.3, 0 },
  { 20, 96, 1.5, 0 },
  { 14, 110, 1.6, 0.6 },
  { 20, 122, 1.8, 2 },
  { 22, 133, 1.9, 4 }, -- through the meadow
  { 23, 143, 1.9, 4 },
  { 27, 151, 2, 4 },
  { 40, 156, 2, 3 },
  { 56, 160, 2, 2.5 },
  { 63, 170, 2.1, 2 },
  { 63, 182, 2.1, 2 },
  { 58, 190, 2.1, 3 },
  { 48, 196, 2.2, 4 }, -- the valley floor
  { 44, 210, 2.2, 5 },
  { 46, 224, 2.3, 4 },
  { 46, 232, 2.3, 4 },
}
-- The wide spots, open ground round a point on the road: { name, column, row, radius in tiles }.
Road.SPOTS = {
  { name = "the arrival", c = 30, r = 210, rad = 7 },
  { name = "the meadow", c = 38, r = 148, rad = 6 },
  { name = "the lookout", c = 12, r = 58, rad = 5 },
  { name = "the pass", c = 40, r = 9, rad = 7 },
}
-- The stretches of the road, by row (inclusive), top to bottom: what the HUD calls where you are.
Road.ZONES = {
  { name = "the pass", r0 = 0, r1 = 16 },
  { name = "the high road", r0 = 17, r1 = 52 },
  { name = "the gorge", r0 = 53, r1 = 85 },
  { name = "the hairpins", r0 = 86, r1 = 129 },
  { name = "the meadow", r0 = 130, r1 = 168 },
  { name = "the valley", r0 = 169, r1 = 223 },
}
-- What the bridges are called, in the order they are driven over.
Road.BRIDGES = {
  "the valley bridge", "the meadow bridge", "the ford", "the gorge bridge", "the old bridge", "the top bridge",
}
Road.ASPHALT = 1.05 -- tiles either side of the road's middle that are tarmac (drawn 64 px either side)
Road.VERGE = 2.3 -- tiles either side of it that are open: the tarmac and the verge
Road.DECK = 1.6 -- tiles either side of it that a bridge spans
Road.STEP = 0.25 -- tiles between the points the curves are sampled at
Road.RAIL = 8 -- px thick, a bridge's railings

-- How each kind shows on the minimap (minimap draws any cover with a `mapColor`).
local MAP = {
  mountain = { 0.24, 0.36, 0.22 },
  rail = { 0.70, 0.70, 0.68 },
}

--- A Catmull-Rom curve through `pts` ({ c, r, ... }), sampled every `step`
--- tiles or so. Any extra values on the points are eased along with it.
local function curve(pts, step)
  local out = {}
  for i = 1, #pts - 1 do
    local p0, p1, p2, p3 = pts[math.max(1, i - 1)], pts[i], pts[i + 1], pts[math.min(#pts, i + 2)]
    local len = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
    local n = math.max(1, math.ceil(len / step))
    for k = 0, n - 1 do
      local t = k / n
      local t2, t3 = t * t, t * t * t
      local q = {}
      for j = 1, 2 do
        q[j] = 0.5 * (2 * p1[j] + (p2[j] - p0[j]) * t + (2 * p0[j] - 5 * p1[j] + 4 * p2[j] - p3[j]) * t2
          + (3 * p1[j] - p0[j] - 3 * p2[j] + p3[j]) * t3)
      end
      for j = 3, #p1 do
        q[j] = p1[j] + (p2[j] - p1[j]) * t
      end
      out[#out + 1] = q
    end
  end
  out[#out + 1] = { unpack(pts[#pts]) }
  return out
end

--- For every tile within `reach` tiles of the curve, how far its middle is
--- from the nearest sample and which sample that is: dist[c][r], near[c][r].
local function stamp(samples, cols, rows, reach)
  local dist, near = {}, {}
  for c = 0, cols - 1 do
    dist[c], near[c] = {}, {}
  end
  for i, s in ipairs(samples) do
    for c = math.max(0, math.floor(s[1] - reach)), math.min(cols - 1, math.ceil(s[1] + reach)) do
      for r = math.max(0, math.floor(s[2] - reach)), math.min(rows - 1, math.ceil(s[2] + reach)) do
        local d = math.sqrt((c + 0.5 - s[1]) ^ 2 + (r + 0.5 - s[2]) ^ 2)
        if d <= reach and d < (dist[c][r] or math.huge) then
          dist[c][r], near[c][r] = d, i
        end
      end
    end
  end
  return dist, near
end

--- Build it into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function Road.build(map, rng, T)
  local cols, rows = map.cols, map.rows
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  map.cover, map.zones, map.bridges, map.spots, map.slopes, map.posts = {}, {}, {}, {}, {}, {}

  local road, river = curve(Road.ROAD, Road.STEP), curve(Road.RIVER, Road.STEP)
  local roadDist = stamp(road, cols, rows, Road.VERGE + 1)
  local riverDist, riverNear = stamp(river, cols, rows, 8)

  -- Tile by tile: the river (or a bridge over it), the road and its verge,
  -- the river's banks, the wide spots; the mountains everywhere else.
  local water, deck = {}, {}
  for c = 0, cols - 1 do
    map.tiles[c], water[c], deck[c] = {}, {}, {}
    for r = 0, rows - 1 do
      local dr, dw = roadDist[c][r], riverDist[c][r]
      local w = dw and river[riverNear[c][r]]
      local kind
      if w and dw <= w[3] then
        if dr and dr <= Road.DECK then
          deck[c][r] = true
          kind = "road"
        else
          water[c][r] = true
          kind = "water"
        end
      elseif dr and dr <= Road.VERGE then
        kind = dr <= Road.ASPHALT + 0.5 and "road" or "ground"
      elseif w and dw <= w[3] + w[4] then
        kind = "ground"
      end
      map.tiles[c][r] = kind
    end
  end
  for _, s in ipairs(Road.SPOTS) do
    for c = math.max(0, s.c - s.rad), math.min(cols - 1, s.c + s.rad) do
      for r = math.max(0, s.r - s.rad), math.min(rows - 1, s.r + s.rad) do
        if (c + 0.5 - s.c) ^ 2 + (r + 0.5 - s.r) ^ 2 <= s.rad * s.rad and not map.tiles[c][r] then
          map.tiles[c][r] = "ground"
        end
      end
    end
    map.spots[#map.spots + 1] = { name = s.name, x = X(s.c), y = Y(s.r), r = s.rad * T }
  end

  -- The bridges: each run of deck squared off to the box round it, the
  -- water under it decked over too, railings down both sides.
  local seen = {}
  for c = 0, cols - 1 do
    seen[c] = {}
  end
  for c = 0, cols - 1 do
    for r = 0, rows - 1 do
      if deck[c][r] and not seen[c][r] then
        local c0, c1, r0, r1 = c, c, r, r
        local stack = { { c, r } }
        seen[c][r] = true
        while #stack > 0 do
          local p = table.remove(stack)
          c0, c1, r0, r1 = math.min(c0, p[1]), math.max(c1, p[1]), math.min(r0, p[2]), math.max(r1, p[2])
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = p[1] + d[1], p[2] + d[2]
            if deck[nc] and deck[nc][nr] and not seen[nc][nr] then
              seen[nc][nr] = true
              stack[#stack + 1] = { nc, nr }
            end
          end
        end
        for bc = c0, c1 do
          for br = r0, r1 do
            if water[bc][br] then
              water[bc][br] = nil
              map.tiles[bc][br] = "road"
            end
          end
        end
        -- Which way the road runs over it, from the road at its middle.
        local mc, mr, best, at = (c0 + c1 + 1) / 2, (r0 + r1 + 1) / 2, math.huge, 1
        for i, q in ipairs(road) do
          local d = (q[1] - mc) ^ 2 + (q[2] - mr) ^ 2
          if d < best then
            best, at = d, i
          end
        end
        local a, z = road[math.max(1, at - 2)], road[math.min(#road, at + 2)]
        local b = { x = X(c0), y = Y(r0), w = (c1 - c0 + 1) * T, h = (r1 - r0 + 1) * T }
        b.along = math.abs(z[1] - a[1]) > math.abs(z[2] - a[2]) and "ew" or "ns"
        map.bridges[#map.bridges + 1] = b
      end
    end
  end
  table.sort(map.bridges, function(a, b) -- bottom to top, the way they are driven
    return a.y > b.y
  end)
  for i, b in ipairs(map.bridges) do
    b.name = Road.BRIDGES[i] or "a bridge"
    local R = Road.RAIL
    local rails = b.along == "ns"
        and { { b.x, b.y, R, b.h }, { b.x + b.w - R, b.y, R, b.h } }
      or { { b.x, b.y, b.w, R }, { b.x, b.y + b.h - R, b.w, R } }
    for _, q in ipairs(rails) do
      local s = { kind = "rail", x = q[1], y = q[2], w = q[3], h = q[4], mapColor = MAP.rail }
      map.cover[#map.cover + 1] = s
      map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
    end
  end

  -- How high the mountains stand and how deep the river runs.
  map.height = Coast.distances(cols, rows, function(c, r)
    return map.tiles[c][r] ~= nil
  end, function(c, r)
    return map.tiles[c][r] == nil
  end)
  map.depth = Coast.distances(cols, rows, function(c, r)
    return not water[c][r]
  end, function(c, r)
    return water[c][r]
  end)

  -- The river solid; the mountains only for the minimap (they are walls already).
  for _, s in ipairs(Coast.rects(cols, rows, T, map.x0, map.y0, function(c, r)
    return water[c][r]
  end, "water")) do
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
  end
  for _, s in ipairs(Coast.rects(cols, rows, T, map.x0, map.y0, function(c, r)
    return map.tiles[c][r] == nil
  end, "mountain", MAP.mountain)) do
    table.insert(map.cover, 1, s) -- under everything else on the minimap
  end

  -- The road and the river in world px, for drawing them and for whatever comes to drive them.
  map.path, map.river = {}, {}
  for _, s in ipairs(road) do
    map.path[#map.path + 1] = { x = X(s[1]), y = Y(s[2]) }
  end
  for _, s in ipairs(river) do
    map.river[#map.river + 1] = { x = X(s[1]), y = Y(s[2]), half = s[3] * T }
  end

  for _, z in ipairs(Road.ZONES) do
    map.zones[#map.zones + 1] = { name = z.name, y0 = Y(z.r0), y1 = Y(z.r1 + 1) }
  end

  -- Everyone arrives on the road at the bottom, two by two up both lanes,
  -- facing the way on; the way home is on the verge beside them.
  local arrival, pass = Road.SPOTS[1], Road.SPOTS[#Road.SPOTS]
  local ax = X(arrival.c)
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = ax + (i % 2 == 0 and -32 or 32), y = Y(arrival.r + 4) - math.floor(i / 2) * 80, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(ax - 4 * T), math.floor(Y(arrival.r + 2))
  map.exitX, map.exitY = math.floor(X(pass.c)), math.floor(Y(pass.r - 2))

  -- The mountainsides: thick with trees low down, thinning higher up and
  -- further north, where the snow is.
  for _ = 1, math.floor(cols * rows * 1.4) do
    local x, y = X(rng:random() * cols), Y(rng:random() * rows)
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    local h = map.height[c] and map.height[c][r]
    local north = 1 - r / rows
    if h and h > 0.6 and rng:random() < math.max(0.15, 0.95 - h / 12 - north * 0.35) then
      local pine = rng:random() < 0.4 + north * 0.5
      map.slopes[#map.slopes + 1] = { x = x, y = y, r = 13 + rng:random() * 12, pine = pine }
    end
  end
  table.sort(map.slopes, function(a, b) -- drawn top to bottom, the nearer canopy over the one behind
    return a.y < b.y
  end)
end

return Road
