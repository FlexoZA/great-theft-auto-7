-- The Colosseum's arena (city-map's `colosseum`, the colosseum feature's
-- map): one big oval of open sand to fight on, walled all round by the
-- podium, the stands rising past it (drawn by the colosseum feature, past
-- the wall). The only way in or out is the gate in the middle of the south
-- wall; everyone comes in there and the star home stands just inside it.
-- Cover stands about the sand (`Arena.COVER`), the same layout every time
-- and mirrored left and right, the middle and the way in from the gate kept
-- open: other maps' pieces (render_arena.lua draws them their way), all
-- solid, stopping rounds like any wall. The wave fights come later.
--
-- Tiles are "ground" wherever any of the tile is on the sand; everything
-- past the oval is walled off by thin solid strips that follow its curve
-- (`STRIP` px a band), so the wall you bump into is the one you see, and
-- the layout's walls fill every tile wholly past it.
--
-- What it leaves on the map, besides tiles, solids and spawns:
--   map.oval              { x, y, rx, ry } the sand's edge, world px (the wall's inside face)
--   map.cx, map.cy        the way home: just inside the gate
--   map.gateX, map.gateY  the gate, in the middle of the south wall
--   map.cover             { kind, x, y, w, h, seed, tint, mapColor }: the cover, all solid
--   map.streams           { pts = { { x, y }... } spring first, half, side }: the streams' middles
--   map.basins            { x, y, r, statue }: the basin each stream ends in, its statue's radius
--   map.footbridges       { x, y, w, h }: the stone bridges' decks, walkable over the water
--   map.braziers          { x, y }: braziers along the top of the wall (scenery; the fire is drawn live)

local Arena = {}

Arena.RX, Arena.RY = 1800, 1200 -- px radii of the sand
Arena.WALL = 64 -- px thick, the podium wall round it
Arena.STRIP = 16 -- px high, each band of the wall's solid strips
Arena.HOME = 110 -- px in from the gate, the star home

-- The cover, from the sand's middle: { kind, x, y, w, h (px, its centre and size), seed, tint }. Everything
-- with x > 0 is put down again mirrored on the left; on the centre line it stands once. Kinds are the other maps'
-- pieces: "sandbag" (D-Day's walls), "barrier" (the Outer City's concrete), "container", "crate" and "drum"
-- (Borderline's; the containers' seeds are ones that draw no snow on them).
Arena.COVER = {
  { "barrier", 0, -520, 220, 34 }, -- the middle ring, round the open centre
  { "barrier", 0, 520, 220, 34 },
  { "sandbag", 580, -280, 280, 22 },
  { "sandbag", 580, 280, 280, 22 },
  { "sandbag", 740, 0, 22, 240 },
  { "drum", 430, -90, 36, 36, 3 },
  { "drum", 430, 90, 36, 36, 7 },
  { "container", 0, -930, 280, 112, 1, 2 }, -- the outer ring
  { "drum", 250, -900, 36, 36, 11 },
  { "sandbag", 440, -780, 220, 22 },
  { "container", 1010, -650, 240, 112, 9, 1 },
  { "crate", 1210, -545, 52, 52, 4 },
  { "container", 1050, 650, 240, 112, 13, 3 },
  { "crate", 1320, 575, 52, 52, 5 },
  { "sandbag", 900, -400, 220, 22 },
  { "crate", 1080, -60, 56, 56, 1 },
  { "crate", 1136, 4, 50, 50, 2 },
  { "crate", 1060, 44, 44, 44, 3 },
  { "barrier", 1560, -300, 34, 180 }, -- past the streams, by the wall
  { "barrier", 1560, 240, 34, 180 },
  { "sandbag", 720, 820, 260, 22 }, -- either side of the way in from the gate
}

-- The streams, put down on the right and again mirrored on the left: each
-- springs from a lion's head in the north wall, winds down the side of the
-- sand in a stone channel and ends in a round basin with a statue in it,
-- short of the south wall so there is always a way round. Water stops
-- walking, not rounds or sight. Points are px from the sand's middle, the
-- spring first; the curve is smoothed through them.
Arena.STREAM = { { 1100, -1010 }, { 1170, -790 }, { 1320, -590 }, { 1370, -380 }, { 1300, -150 }, { 1330, 60 },
  { 1240, 240 } }
Arena.STREAM_HALF = 44 -- px either side of the stream's middle that is water
Arena.KERB = 12 -- px of stone either side, walkable
Arena.BASIN = { 1180, 370, 130 } -- x, y, radius of the basin it ends in
Arena.STATUE = 38 -- px radius, the statue in the basin (solid: it stops rounds too)
-- The bridges over it, each a stone deck crossing east to west at height y: { y, length, width } px.
Arena.BRIDGES = { { -470, 200, 76 }, { -40, 190, 76 } }
Arena.WATER_CELL = 16 -- px, the grid the water's solids are laid on
Arena.BRAZIERS = 28 -- round the top of the wall, evenly, but none over the gate
-- How each kind shows on the minimap.
local MAP_COLORS = {
  sandbag = { 0.62, 0.55, 0.38 },
  barrier = { 0.62, 0.62, 0.60 },
  container = { 0.55, 0.28, 0.22 },
  crate = { 0.55, 0.40, 0.24 },
  drum = { 0.45, 0.25, 0.20 },
}

--- Half the oval's width at height `y` (px from its middle), 0 past its ends.
local function halfWidth(y)
  local k = 1 - (y / Arena.RY) ^ 2
  return k > 0 and Arena.RX * math.sqrt(k) or 0
end

--- A smooth curve through `pts` ({ x, y } pairs, px from the sand's middle),
--- a point every 10 px or so, its x times `sx` (1 or -1, the side), moved to (ox, oy).
local function smooth(pts, sx, ox, oy)
  local out, n = {}, #pts
  for i = 1, n - 1 do
    local p0, p1, p2, p3 = pts[math.max(1, i - 1)], pts[i], pts[i + 1], pts[math.min(n, i + 2)]
    local steps = math.max(2, math.floor(math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2) / 10))
    for s = 0, steps - 1 do
      local t = s / steps
      local function cr(k) -- Catmull-Rom on coordinate k
        local a, b, c, d = p0[k], p1[k], p2[k], p3[k]
        return 0.5 * (2 * b + (c - a) * t + (2 * a - 5 * b + 4 * c - d) * t * t + (3 * b - a - 3 * c + d) * t * t * t)
      end
      out[#out + 1] = { x = ox + sx * cr(1), y = oy + cr(2) }
    end
  end
  out[#out + 1] = { x = ox + sx * pts[n][1], y = oy + pts[n][2] }
  return out
end

--- How far (x, y) is from the line through `pts`.
local function distance(pts, x, y)
  local best = math.huge
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local t = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / (dx * dx + dy * dy)))
    local ex, ey = a.x + dx * t - x, a.y + dy * t - y
    best = math.min(best, ex * ex + ey * ey)
  end
  return math.sqrt(best)
end

--- Where the line through `pts` is at height `y` (the first point that low), its x.
local function xAt(pts, y)
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    if (a.y - y) * (b.y - y) <= 0 and a.y ~= b.y then
      return a.x + (b.x - a.x) * (y - a.y) / (b.y - a.y)
    end
  end
end

local function inside(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

--- The streams, their basins and the bridges over them (see Arena.STREAM),
--- one each side; the water solid (`water`: it stops walking only) on a grid
--- of WATER_CELL px, row by row, but not under the bridges; the statues solid.
local function streams(map, cx, cy)
  map.streams, map.basins, map.footbridges = {}, {}, {}
  local G, half = Arena.WATER_CELL, Arena.STREAM_HALF
  for _, sx in ipairs({ 1, -1 }) do
    local B = Arena.BASIN
    local pts = smooth(Arena.STREAM, sx, cx, cy)
    pts[#pts + 1] = { x = cx + sx * B[1], y = cy + B[2] } -- on into the basin's middle
    map.streams[#map.streams + 1] = { pts = pts, half = half, side = sx }
    local basin = { x = cx + sx * B[1], y = cy + B[2], r = B[3], statue = Arena.STATUE }
    map.basins[#map.basins + 1] = basin
    local decks = {}
    for _, b in ipairs(Arena.BRIDGES) do
      local x = xAt(pts, cy + b[1])
      local deck = { x = x - b[2] / 2, y = cy + b[1] - b[3] / 2, w = b[2], h = b[3] }
      decks[#decks + 1] = deck
      map.footbridges[#map.footbridges + 1] = deck
    end
    local x0, x1, y0, y1 = math.huge, -math.huge, math.huge, -math.huge
    for _, p in ipairs(pts) do
      x0, x1, y0, y1 = math.min(x0, p.x), math.max(x1, p.x), math.min(y0, p.y), math.max(y1, p.y)
    end
    x0, x1 = math.min(x0, basin.x - basin.r) - half, math.max(x1, basin.x + basin.r) + half
    y0, y1 = y0 - half, math.max(y1, basin.y + basin.r) + half
    for y = math.floor(y0 / G) * G, y1, G do
      local run = nil
      for x = math.floor(x0 / G) * G, x1 + G, G do
        local mx, my = x + G / 2, y + G / 2
        local wet = (distance(pts, mx, my) < half or (mx - basin.x) ^ 2 + (my - basin.y) ^ 2 < basin.r ^ 2)
          and ((mx - cx) / Arena.RX) ^ 2 + ((my - cy) / Arena.RY) ^ 2 < 1
        for _, d in ipairs(decks) do
          wet = wet and not inside(d, mx, my)
        end
        if wet then
          run = run or { x = x, y = y, w = 0, h = G, water = true }
          run.w = run.w + G
        elseif run then
          map.solids[#map.solids + 1] = run
          run = nil
        end
      end
      if run then
        map.solids[#map.solids + 1] = run
      end
    end
    local r = basin.statue
    map.solids[#map.solids + 1] = { x = basin.x - r, y = basin.y - r, w = 2 * r, h = 2 * r }
  end
end

function Arena.build(map, _rng, T)
  local cols, rows = map.cols, map.rows
  local cx, cy = 0, 0 -- the oval sits in the middle of the map
  map.oval = { x = cx, y = cy, rx = Arena.RX, ry = Arena.RY }

  -- Ground where any of the tile is on the sand: its nearest point to the middle is inside the oval.
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    local x0 = map.x0 + c * T
    local nx = math.max(x0, math.min(cx, x0 + T)) - cx
    for r = 0, rows - 1 do
      local y0 = map.y0 + r * T
      local ny = math.max(y0, math.min(cy, y0 + T)) - cy
      if (nx / Arena.RX) ^ 2 + (ny / Arena.RY) ^ 2 < 1 then
        map.tiles[c][r] = "ground"
      end
    end
  end

  -- The wall's solid, band by band: each band walled from the map's edge in
  -- to the oval, measured at the band's edge furthest from the middle so
  -- nothing of it pokes out past the wall onto the sand.
  local left, right = map.x0, map.x0 + cols * T
  for y = map.y0, map.y0 + rows * T - 1, Arena.STRIP do
    local far = math.max(math.abs(y - cy), math.abs(y + Arena.STRIP - cy))
    if y < cy and y + Arena.STRIP > cy then
      far = 0
    end
    local hw = halfWidth(far)
    if hw <= 0 then
      map.solids[#map.solids + 1] = { x = left, y = y, w = right - left, h = Arena.STRIP }
    else
      map.solids[#map.solids + 1] = { x = left, y = y, w = cx - hw - left, h = Arena.STRIP }
      map.solids[#map.solids + 1] = { x = cx + hw, y = y, w = right - cx - hw, h = Arena.STRIP }
    end
  end

  -- The cover, each piece solid.
  map.cover = {}
  for _, c in ipairs(Arena.COVER) do
    for _, side in ipairs(c[2] > 0 and { 1, -1 } or { 1 }) do
      local piece = { kind = c[1], x = cx + side * c[2] - c[4] / 2, y = cy + c[3] - c[5] / 2, w = c[4], h = c[5],
        seed = c[6] and c[6] + (side < 0 and 100 or 0), tint = c[7], mapColor = MAP_COLORS[c[1]] }
      if c[1] == "container" then
        piece.seed = c[6] -- a mirrored container keeps a snowless seed
      end
      map.cover[#map.cover + 1] = piece
      map.solids[#map.solids + 1] = { x = piece.x, y = piece.y, w = piece.w, h = piece.h }
    end
  end

  streams(map, cx, cy)
  map.braziers = {}
  for k = 0, Arena.BRAZIERS - 1 do
    local a = (k + 0.5) * 2 * math.pi / Arena.BRAZIERS
    if math.abs(a - math.pi / 2) > 0.12 then
      local x, y = cx + math.cos(a) * (Arena.RX + Arena.WALL * 0.65), cy + math.sin(a) * (Arena.RY + Arena.WALL * 0.65)
      map.braziers[#map.braziers + 1] = { x = x, y = y }
    end
  end

  -- The gate, and everyone in a row just inside it facing the sand.
  map.gateX, map.gateY = cx, cy + Arena.RY
  map.cx, map.cy = cx, map.gateY - Arena.HOME
  for i = 0, 7 do
    local dx = (i % 2 == 0 and 1 or -1) * (90 + math.floor(i / 2) * 70)
    map.spawns[#map.spawns + 1] = { x = cx + dx, y = map.cy - 40, angle = -math.pi / 2 }
  end
end

return Arena
