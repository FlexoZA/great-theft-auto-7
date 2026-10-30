-- The Colosseum's arena (city-map's `colosseum`, the colosseum feature's
-- map): one big oval of open sand to fight on, walled all round by the
-- podium, the stands rising past it (drawn by the colosseum feature, past
-- the wall). The only way in or out is the gate in the middle of the south
-- wall; everyone comes in there and the star home stands just inside it.
-- Nothing stands on the sand yet: cover and the wave fights come later.
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

local Arena = {}

Arena.RX, Arena.RY = 1800, 1200 -- px radii of the sand
Arena.WALL = 64 -- px thick, the podium wall round it
Arena.STRIP = 16 -- px high, each band of the wall's solid strips
Arena.HOME = 110 -- px in from the gate, the star home

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

  -- The gate, and everyone in a row just inside it facing the sand.
  map.gateX, map.gateY = cx, cy + Arena.RY
  map.cx, map.cy = cx, map.gateY - Arena.HOME
  for i = 0, 7 do
    local dx = (i % 2 == 0 and 1 or -1) * (90 + math.floor(i / 2) * 70)
    map.spawns[#map.spawns + 1] = { x = cx + dx, y = map.cy - 40, angle = -math.pi / 2 }
  end
end

return Arena
