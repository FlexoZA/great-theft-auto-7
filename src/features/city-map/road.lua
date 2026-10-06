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
--   map.cover             { kind = "water" | "rail" | "bunker" | "block" | "wreck", x, y, w, h }, solid (a
--                         wreck: a burnt-out car short of a bridge, for cover, `facing` the way its nose is; a rail
--                         only to cars and people: its solid is `low`, so sight and rounds go over it)
--                         (a block: a concrete block, laid in a chicane past each bridge); and kind "mountain",
--                         not solid, only to colour the minimap
--   map.height            [c][r] tiles from the nearest open tile, for a mountain tile
--   map.depth             [c][r] tiles from the nearest bank, for a river tile
--   map.slopes            { x, y, r, pine } trees on the mountainsides: drawn only, never touched
--   map.rollermines       { x, y, r, count } where rollermines lie in wait (the rollermines feature):
--                         a few at a time on the road every `Road.MINE_EVERY` px of it
--   map.rollermineScatter { count, clear }: `Road.MINE_SCATTER` more scattered anywhere open, different
--                         every game, but none near the arrival or the pass
--   map.nests             { name, nest = { x, y, angle, arc }, posts = { { x, y, watch } x2 } }: the
--                         Combine's MG nests, two at the far end of every bridge facing back
--                         across it (sandbags, drawn only), each with two riflemen's posts
--   map.garrisons         { at, x, y, reach, door = { x, y, nx, ny }, waves = { every, alive, total } }:
--                         a bunker beside each bridge's far end that sends soldiers out of its
--                         door while anyone is near (a-man/city17.lua)
--   map.checkpoints       { name, x, y } the far end of each bridge, where all that stands
--   map.posts             empty: City 17's level reads it (it mans the nests)
--   map.wreckRide         true: a wrecked car takes its driver back to the start with it (weapons)
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
Road.VERGE = 4 -- tiles either side of it that are open: the tarmac and a verge wide enough for 8 cars abreast
Road.DECK = 2.2 -- tiles either side of it that a bridge spans
Road.DECK_MIN = 6 -- tiles of deck at least for a bridge: fewer is the road brushing past the river
Road.STEP = 0.25 -- tiles between the points the curves are sampled at
Road.RAIL = 8 -- px thick, a bridge's railings
-- The Combine's checkpoint past each bridge, in tiles along the road from the end of its deck.
Road.NEST_AT, Road.NEST_OFF = 1.2, 1.55 -- the MG nests: how far on, and how far either side of the middle
Road.NEST_ARC = math.rad(50) -- either side of where a nest faces, how far its gun turns
Road.NEST_SEES = 10 -- tiles: how far a gunner sees (the Combine's 640 px)
-- Where a nest may go (tiles on from the deck, tiles out from the middle, either side): of the
-- spots on open ground, the two that see the most of the way onto the bridge, NEST_APART apart.
Road.NEST_TRY_AT = { 1.2, 0.8, 1.6, 2.0, 2.4 }
Road.NEST_TRY_OFF = { 2.2, 1.8, 2.6, 1.55, 3 }
Road.NEST_APART = 2.2 -- tiles at least between a bridge's two nests
Road.BUNKER_AT, Road.BUNKER_OFF = 2.4, 5.3 -- the bunker: how far on, and how far off to one side (past the verge)
Road.CLEARING = 3.6 -- tiles round the bunker cut out of the mountainside to stand it in
Road.CHICANE = { 3.6, 5.0 } -- where the concrete blocks close each side in turn, lane and verge
Road.CHICANE_OFF = { 0.25, 0.72, 1.5, 2.3, 3.1 } -- tiles out from the middle that its blocks stand at
-- Wrecked cars short of each bridge, for cover: tiles back from the deck, how far out from the
-- middle they may lie (0.4 to 0.4 + spread, either side in turn) and their size along and across.
Road.WRECKS = { 2.6, 4.5, 6.5 }
Road.WRECK_SPREAD = 2.4
Road.WRECK_SIZE = { 62, 32 }
Road.WAVES = { every = 6, alive = 3, total = 8 } -- the bunker's soldiers: seconds apart, up at once, in all
Road.MINE_FROM = 3000 -- px up the road before the first rollermines, and before the pass after the last
Road.MINE_EVERY = 2400 -- px of road between one lot of rollermines and the next
Road.MINE_COUNT = { 2, 3, 2, 4 } -- how many in each lot, for one human, round and round
Road.MINE_SCATTER = 18 -- more, for one human, scattered at random over all the open ground
Road.MINE_CLEAR = 1500 -- px round the arrival kept free of scattered ones (and half that round the pass)

-- How each kind shows on the minimap (minimap draws any cover with a `mapColor`).
local MAP = {
  mountain = { 0.24, 0.36, 0.22 },
  rail = { 0.70, 0.70, 0.68 },
  bunker = { 0.55, 0.56, 0.58 },
  block = { 0.62, 0.62, 0.60 },
  wreck = { 0.36, 0.26, 0.20 },
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
        local stack, got = { { c, r } }, {}
        seen[c][r] = true
        while #stack > 0 do
          local p = table.remove(stack)
          got[#got + 1] = p
          c0, c1, r0, r1 = math.min(c0, p[1]), math.max(c1, p[1]), math.min(r0, p[2]), math.max(r1, p[2])
          for _, d in ipairs({ { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }) do
            local nc, nr = p[1] + d[1], p[2] + d[2]
            if deck[nc] and deck[nc][nr] and not seen[nc][nr] then
              seen[nc][nr] = true
              stack[#stack + 1] = { nc, nr }
            end
          end
        end
        -- A scrap of a few tiles is only the road brushing past the river: water it stays.
        local scrap = #got < Road.DECK_MIN
        for _, q in ipairs(scrap and got or {}) do
          water[q[1]][q[2]], map.tiles[q[1]][q[2]] = true, "water"
        end
        for bc = c0, scrap and c0 - 1 or c1 do
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
        if not scrap then
          map.bridges[#map.bridges + 1] = b
        end
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
      map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h, low = true } -- no wall to sight or rounds
    end
  end

  -- The Combine's checkpoint past each bridge: two MG nests either side of
  -- the road facing back over it, a bunker in a clearing off to one side
  -- with its door on the road, and concrete blocks closing one lane and
  -- then the other further on.
  map.nests, map.garrisons, map.checkpoints = {}, {}, {}
  local function sampleAt(i)
    return road[math.max(1, math.min(#road, i))]
  end
  --- The road `tiles` on from sample `i`: where (tile units), which way it runs and its left.
  local function along(i, tiles)
    local k = i + math.floor(tiles / Road.STEP + 0.5)
    local p, a, z = sampleAt(k), sampleAt(k - 2), sampleAt(k + 2)
    local dx, dy = z[1] - a[1], z[2] - a[2]
    local len = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / len, dy / len
    return p[1], p[2], dx, dy, dy, -dx
  end
  local function open(c, r)
    local col = map.tiles[math.floor(c)]
    local kind = col and col[math.floor(r)]
    return kind ~= nil and kind ~= "water"
  end
  local function solid(kind, cx, cy, w, h)
    local q = { kind = kind, x = math.floor(cx - w / 2), y = math.floor(cy - h / 2), w = w, h = h, mapColor = MAP[kind],
      seed = rng:random(1000) }
    map.cover[#map.cover + 1] = q
    map.solids[#map.solids + 1] = { x = q.x, y = q.y, w = q.w, h = q.h }
    return q
  end
  for bi, b in ipairs(map.bridges) do
    local last
    for i, q in ipairs(road) do
      local x, y = X(q[1]), Y(q[2])
      if x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
        last = i
      end
    end
    if last then
      local side = bi % 2 == 0 and 1 or -1 -- the bunker's side, turn and turn about
      local mx, my = (b.x + b.w / 2 - map.x0) / T, (b.y + b.h / 2 - map.y0) / T -- the bridge's middle, in tiles
      local fx, fy = along(last, 0)
      map.checkpoints[#map.checkpoints + 1] = { name = b.name, x = math.floor(X(fx)), y = math.floor(Y(fy)) }
      -- The bunker, its clearing cut first so it has ground round it.
      local cx, cy, dx, dy, nx, ny = along(last, Road.BUNKER_AT)
      local bx, by = cx + nx * side * Road.BUNKER_OFF, cy + ny * side * Road.BUNKER_OFF
      for c = math.floor(bx - Road.CLEARING), math.ceil(bx + Road.CLEARING) do
        for r = math.floor(by - Road.CLEARING), math.ceil(by + Road.CLEARING) do
          if map.tiles[c] and r >= 0 and r < rows and not map.tiles[c][r]
            and (c + 0.5 - bx) ^ 2 + (r + 0.5 - by) ^ 2 <= Road.CLEARING ^ 2 then
            map.tiles[c][r] = "ground"
          end
        end
      end
      local wide = math.abs(dx) > math.abs(dy) -- long side along the road
      local w, h = wide and 120 or 88, wide and 88 or 120
      local bunker = solid("bunker", X(bx), Y(by), w, h)
      -- Its door on the face towards the road.
      local vx, vy = -nx * side, -ny * side
      local door
      if math.abs(vx) > math.abs(vy) then
        local sx = vx > 0 and 1 or -1
        door = { x = math.floor(X(bx) + sx * w / 2), y = math.floor(Y(by)), nx = sx, ny = 0 }
      else
        local sy = vy > 0 and 1 or -1
        door = { x = math.floor(X(bx)), y = math.floor(Y(by) + sy * h / 2), nx = 0, ny = sy }
      end
      bunker.door = door
      map.garrisons[#map.garrisons + 1] = { at = b.name, x = math.floor(X(bx)), y = math.floor(Y(by)), reach = 750,
        door = door, waves = Road.WAVES }
      -- The nests, either side of the road, facing back over the bridge.
      -- Each goes where it is on open ground and sees the most of the road
      -- onto the bridge: water and the mountainside block sight like walls.
      local first = last
      for i, q in ipairs(road) do
        local x, y = X(q[1]), Y(q[2])
        if i < first and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
          first = i
        end
      end
      local function sightOf(px, py)
        local angle, n = math.atan2(my - py, mx - px), 0
        for i = math.max(1, first - math.floor(Road.NEST_SEES / Road.STEP)), last do
          local q = road[i]
          local lx, ly = q[1] - px, q[2] - py
          local d = math.sqrt(lx * lx + ly * ly)
          local off = (math.atan2(ly, lx) - angle + math.pi) % (2 * math.pi) - math.pi
          if d <= Road.NEST_SEES and math.abs(off) <= Road.NEST_ARC then
            local ok = true
            for k = 1, math.floor(d / 0.125) do
              local t = k * 0.125 / d
              if not open(px + lx * t, py + ly * t) then
                ok = false
                break
              end
            end
            n = n + (ok and 1 or 0)
          end
        end
        return n
      end
      local ex, ey, ndx, ndy, nnx, nny = along(last, Road.NEST_AT)
      -- Every spot either side that has room for a nest, and how much it sees.
      local spots = {}
      for _, way in ipairs({ -1, 1 }) do
        for _, at in ipairs(Road.NEST_TRY_AT) do
          for _, off in ipairs(Road.NEST_TRY_OFF) do
            local cx2, cy2, _, _, cnx, cny = along(last, at)
            local qx, qy = cx2 + cnx * way * off, cy2 + cny * way * off
            if open(qx, qy) and open(qx + 0.35, qy) and open(qx - 0.35, qy) and open(qx, qy + 0.35)
              and open(qx, qy - 0.35) then
              spots[#spots + 1] = { x = qx, y = qy, side = way, score = sightOf(qx, qy) }
            end
          end
        end
      end
      -- The first nest on the best of them; the second on the best a little
      -- way from it, the other side of the road if that is near as good (a
      -- bend along the river can leave one side with nowhere to see from).
      local placed = {}
      for k = 1, 2 do
        local pick, best = nil, -math.huge
        for _, q in ipairs(spots) do
          local a = placed[1]
          local far = not a or (q.x - a.x) ^ 2 + (q.y - a.y) ^ 2 >= Road.NEST_APART ^ 2
          local score = q.score + (a and q.side ~= a.side and 3 or 0)
          if far and score > best then
            pick, best = q, score
          end
        end
        placed[k] = pick or { x = ex + nnx * (k == 1 and -1 or 1) * Road.NEST_OFF,
          y = ey + nny * (k == 1 and -1 or 1) * Road.NEST_OFF, side = k == 1 and -1 or 1 }
      end
      for _, q in ipairs(placed) do
        local px, py, s2 = q.x, q.y, q.side
        local angle = math.atan2(my - py, mx - px)
        local nest = { x = math.floor(X(px)), y = math.floor(Y(py)), angle = angle, arc = Road.NEST_ARC }
        local posts = {}
        -- A rifleman behind the nest and one in the middle of the road behind both.
        for _, off in ipairs({ { 1.3, s2 * Road.NEST_OFF }, { 2.0, s2 * 0.5 } }) do
          local qx = ex + ndx * off[1] + nnx * off[2]
          local qy = ey + ndy * off[1] + nny * off[2]
          if not open(qx, qy) then
            qx, qy = ex + ndx * off[1], ey + ndy * off[1] -- the road's middle, then
          end
          posts[#posts + 1] = { x = math.floor(X(qx)), y = math.floor(Y(qy)), watch = math.atan2(my - qy, mx - qx) }
        end
        map.nests[#map.nests + 1] = { name = b.name, nest = nest, posts = posts }
      end
      -- The chicane: blocks across one lane, then the other.
      for k, at in ipairs(Road.CHICANE) do
        local qx, qy, _, _, qnx, qny = along(last, at)
        local lane = (k % 2 == 0 and 1 or -1) * side
        for _, off in ipairs(Road.CHICANE_OFF) do
          solid("block", X(qx + qnx * lane * off), Y(qy + qny * lane * off), 30, 30)
        end
      end
      -- Burnt-out cars on the way onto the bridge, staggered across it: cover
      -- to fight the nests from, one after another. Each lies along the road
      -- as near as a box can, on open ground off the deck.
      for k, at in ipairs(Road.WRECKS) do
        local wx, wy, wdx, wdy, wnx, wny = along(first, -at)
        local off = (k % 2 == 0 and 1 or -1) * side * (0.4 + rng:random() * Road.WRECK_SPREAD)
        local cx3, cy3 = wx + wnx * off, wy + wny * off
        local long = math.abs(wdx) > math.abs(wdy)
        local size = Road.WRECK_SIZE
        local ww, wh = long and size[1] or size[2], long and size[2] or size[1]
        local hw, hh = ww / 2 / T, wh / 2 / T
        local px3, py3 = X(cx3), Y(cy3)
        local onDeck = px3 + ww / 2 >= b.x and px3 - ww / 2 <= b.x + b.w
          and py3 + wh / 2 >= b.y and py3 - wh / 2 <= b.y + b.h
        if not onDeck and open(cx3 - hw, cy3 - hh) and open(cx3 + hw, cy3 - hh) and open(cx3 - hw, cy3 + hh)
          and open(cx3 + hw, cy3 + hh) then
          local wreck = solid("wreck", px3, py3, ww, wh)
          wreck.facing = (long and (wdx > 0 and 0 or math.pi) or (wdy > 0 and math.pi / 2 or -math.pi / 2))
            + (rng:random() < 0.5 and math.pi or 0) -- nose either way
        end
      end
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

  -- Rollermines every so often along the road, from a little way up it to a little short of the pass.
  map.rollermines = {}
  local run, total = 0, 0
  for i = 2, #map.path do
    total = total + math.sqrt((map.path[i].x - map.path[i - 1].x) ^ 2 + (map.path[i].y - map.path[i - 1].y) ^ 2)
  end
  local nextAt = Road.MINE_FROM
  for i = 2, #map.path do
    local a, b = map.path[i - 1], map.path[i]
    run = run + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    if run >= nextAt and run <= total - Road.MINE_FROM then
      local count = Road.MINE_COUNT[#map.rollermines % #Road.MINE_COUNT + 1]
      map.rollermines[#map.rollermines + 1] = { x = math.floor(b.x), y = math.floor(b.y), r = 110, count = count }
      nextAt = nextAt + Road.MINE_EVERY
    end
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
  map.wreckRide = true -- the road is driven: a wreck sends you back to the start in your car
  map.rollermineScatter = { count = Road.MINE_SCATTER, clear = {
    { x = ax, y = Y(arrival.r), r = Road.MINE_CLEAR }, { x = map.exitX, y = map.exitY, r = Road.MINE_CLEAR / 2 },
  } }

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
