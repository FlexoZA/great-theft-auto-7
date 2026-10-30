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
  { "container", 1050, -650, 240, 112, 9, 1 },
  { "crate", 1210, -545, 52, 52, 4 },
  { "container", 1050, 650, 240, 112, 13, 3 },
  { "crate", 1210, 545, 52, 52, 5 },
  { "sandbag", 900, -400, 220, 22 },
  { "crate", 1260, -34, 56, 56, 1 },
  { "crate", 1316, 30, 50, 50, 2 },
  { "crate", 1240, 70, 44, 44, 3 },
  { "barrier", 1520, -300, 34, 180 },
  { "barrier", 1520, 300, 34, 180 },
  { "sandbag", 720, 820, 260, 22 }, -- either side of the way in from the gate
}
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

  -- The gate, and everyone in a row just inside it facing the sand.
  map.gateX, map.gateY = cx, cy + Arena.RY
  map.cx, map.cy = cx, map.gateY - Arena.HOME
  for i = 0, 7 do
    local dx = (i % 2 == 0 and 1 or -1) * (90 + math.floor(i / 2) * 70)
    map.spawns[#map.spawns + 1] = { x = cx + dx, y = map.cy - 40, angle = -math.pi / 2 }
  end
end

return Arena
