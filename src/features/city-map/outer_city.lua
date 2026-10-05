-- The Outer City: a stop on A-Man's trail before the Citadel (city-map's
-- `outercity`). A concrete jungle of packed blocks round a big open square
-- on an island in the middle, a canal ringing it and crossed by three
-- bridges, waterways running out from the ring to the edge, and parks
-- (green, trees) off the streets. Everyone arrives in the bottom left;
-- every street leads in towards the square, where the boss fight is.
--
-- Tiles are "walk" (paving: the streets, the quay round the canal, the
-- square, the bridges, under the buildings), "ground" (the parks' grass)
-- and "water" (solid, `map.cover` kind "water" over it).
--
-- What it leaves on the map, besides tiles, solids, buildings, trees and spawns:
--   map.cx, map.cy        the way home, in the arrival square
--   map.arena             { x, y, w, h } the square on the island, world px
--   map.bossX, map.bossY  the middle of it
--   map.bridges           { x, y, w, h } drawn over the water, world px
--   map.cover             { kind = "water" | "barrier" | "planter" | "rubble" | "wreck" | "barrel" | "trash",
--                         x, y, w, h }; rubble (a fallen building's, still solid, or loose, not)
--                         and trash are drawn, the rest solid too
--   map.fires             burning drums and roofs (city-map's fires.lua), never on the ground
--   map.zones             { name, y0, y1 } as City 17's
--   map.posts             where Combine guards stand ({ x, y, watch, at }), as City 17's, at the
--                         choke points on the way in
--   map.patrols           the beats their squads walk (loops of { x, y }), woven round the barriers
--   map.garrisons         guard stations with troops inside: { at, x, y, reach, door = { x, y, nx, ny } }:
--                         the first player within `reach` of (x, y) brings them out of the door
--                         (a-man/city17.lua); `door` is on the face of a building, (nx, ny) the
--                         way out of it. render.lua draws the door.
--
-- Nobody has looked after any of it in years: a building in seven or so
-- has come down (`b` gone from `map.buildings`, a heap of rubble in its
-- place, as solid as it was), a good few roofs are holed (`b.holes`, { x, y, r }
-- in px from the corner) or grown over (`b.vines`), rusted wrecks sit
-- where they were left and rubbish piles up along the streets. render.lua
-- cracks, weeds and puddles the ground and fouls the water as it draws it.
-- render.lua's drawOuterCity draws it.

local OuterCity = {}

-- Concrete, mostly: greys and dirty pale tones, a brick or two.
local ROOFS = {
  { 0.46, 0.46, 0.45 },
  { 0.38, 0.39, 0.41 },
  { 0.52, 0.50, 0.46 },
  { 0.33, 0.34, 0.36 },
  { 0.48, 0.38, 0.32 },
  { 0.42, 0.44, 0.40 },
}

-- How each kind shows on the minimap (minimap draws any cover with a `mapColor`).
local MAP = {
  barrier = { 0.62, 0.60, 0.55 },
  planter = { 0.25, 0.40, 0.22 },
  rubble = { 0.36, 0.34, 0.31 },
  wreck = { 0.42, 0.28, 0.20 },
}

--- Build it into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function OuterCity.build(map, rng, T)
  local cols, rows = map.cols, map.rows
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  local kind = {} -- [c][r] = "walk" | "ground" | "water" | "bridge"; nil is built on
  for c = 0, cols - 1 do
    kind[c] = {}
  end
  local function fill(c0, r0, c1, r1, k)
    for c = math.max(0, c0), math.min(cols - 1, c1) do
      for r = math.max(0, r0), math.min(rows - 1, r1) do
        kind[c][r] = k
      end
    end
  end
  map.cover, map.zones, map.bridges = {}, {}, {}

  -- The island, the canal round it and the quay round that.
  local i0, i1, j0, j1 = 25, 46, 15, 36 -- the island's square, in tiles
  fill(i0 - 5, j0 - 5, i1 + 5, j1 + 5, "walk") -- the quay
  fill(i0 - 3, j0 - 3, i1 + 3, j1 + 3, "water")
  fill(i0, j0, i1, j1, "walk")
  fill(34, j1 + 1, 37, j1 + 3, "bridge") -- south, from the way in
  fill(i0 - 3, 24, i0 - 1, 27, "bridge") -- west
  fill(i1 + 1, 24, i1 + 3, 27, "bridge") -- east

  -- Waterways out from the ring: north to the top edge, west to the left one.
  fill(34, 0, 37, j0 - 4, "water")
  fill(34, j0 - 5, 37, j0 - 4, "bridge") -- the quay over it
  fill(0, 30, i0 - 4, 32, "water")
  fill(i0 - 5, 30, i0 - 4, 32, "bridge")

  -- The arrival square, bottom left, and the streets in from it.
  fill(3, 46, 14, 53, "walk")
  fill(14, 49, 37, 51, "walk") -- east along the bottom...
  fill(35, j1 + 6, 37, 51, "walk") -- ...and up to the south bridge
  fill(6, 25, 8, 46, "walk") -- north up the left...
  fill(6, 30, 8, 32, "bridge") -- ...over the west waterway...
  fill(8, 25, i0 - 6, 27, "walk") -- ...and east to the west bridge
  fill(6, 14, 8, 24, "walk") -- on north into the park
  fill(i1 + 6, 29, 56, 31, "walk") -- from the quay east to the east park
  fill(i0 + 4, 4, i0 + 6, j0 - 6, "walk") -- from the quay north to the north park
  fill(i0 + 7, 4, 33, 6, "walk")

  -- Parks: grass with trees, the green in the concrete.
  local parks = {
    { 2, 3, 16, 13 }, -- north west, off the street up the left
    { 18, 43, 30, 47 }, -- between the bottom street and the quay
    { 57, 22, 68, 38 }, -- east, out past the quay
    { 20, 2, 32, 7 }, -- north, beside the waterway
  }
  for _, p in ipairs(parks) do
    fill(p[1], p[2], p[3], p[4], "ground")
  end
  fill(23, 42, 25, 42, "walk") -- the bottom park opens on the quay
  fill(23, 48, 25, 48, "walk") -- and on the bottom street

  -- Tiles, water and bridges as the map keeps them.
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      local k = kind[c][r]
      map.tiles[c][r] = (k == "water" and "water") or (k == "ground" and "ground") or "walk"
    end
  end
  --- Rectangles covering every tile of kind `k`, a row's run merged with the
  --- one above when they line up.
  local function rects(k)
    local out, open = {}, {}
    for r = 0, rows - 1 do
      local row, c = {}, 0
      while c < cols do
        if kind[c][r] == k then
          local start = c
          while c < cols and kind[c][r] == k do
            c = c + 1
          end
          local key = start .. "," .. c
          local rc = open[key]
          if rc then
            rc.h = rc.h + 1
          else
            rc = { c = start, r = r, w = c - start, h = 1 }
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
  for _, rc in ipairs(rects("water")) do
    local s = { kind = "water", x = X(rc.c), y = Y(rc.r), w = rc.w * T, h = rc.h * T }
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
  end
  for _, rc in ipairs(rects("bridge")) do
    -- A bridge's deck runs across the water: across a north-south canal it spans columns.
    map.bridges[#map.bridges + 1] = { x = X(rc.c), y = Y(rc.r), w = rc.w * T, h = rc.h * T }
  end

  -- Everything else is built on, packed tight: blocks cut into buildings no
  -- more than `most` tiles a side, so the roofs vary.
  local most = 5
  local taken = {}
  for c = 0, cols - 1 do
    taken[c] = {}
  end
  for r = 0, rows - 1 do
    for c = 0, cols - 1 do
      if not kind[c][r] and not taken[c][r] then
        local w = 1
        local wMax = 2 + rng:random(0, most - 2)
        while w < wMax and c + w < cols and not kind[c + w][r] and not taken[c + w][r] do
          w = w + 1
        end
        local h, hMax = 1, 2 + rng:random(0, most - 2)
        while h < hMax and r + h < rows do
          local ok = true
          for k = c, c + w - 1 do
            ok = ok and not kind[k][r + h] and not taken[k][r + h]
          end
          if not ok then
            break
          end
          h = h + 1
        end
        for k = c, c + w - 1 do
          for l = r, r + h - 1 do
            taken[k][l] = true
          end
        end
        local b = { x = X(c), y = Y(r), w = w * T, h = h * T,
          color = ROOFS[rng:random(#ROOFS)], style = rng:random(3), seed = rng:random(1000) }
        map.buildings[#map.buildings + 1] = b
        map.solids[#map.solids + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
      end
    end
  end

  -- Trees in the parks, a few strides apart, the edges of the paths kept clear.
  local placed = {}
  local function free(x, y, r)
    for _, q in ipairs(placed) do
      if (q.x - x) ^ 2 + (q.y - y) ^ 2 < (q.r + r) ^ 2 then
        return false
      end
    end
    return true
  end
  for _, p in ipairs(parks) do
    local area = (p[3] - p[1] + 1) * (p[4] - p[2] + 1)
    local want, got = math.floor(area / 6), 0
    for _ = 1, want * 20 do
      if got >= want then
        break
      end
      local x = X(p[1] + 0.6) + rng:random() * (p[3] - p[1] - 0.2) * T
      local y = Y(p[2] + 0.6) + rng:random() * (p[4] - p[2] - 0.2) * T
      local r = 18 + rng:random() * 12
      if free(x, y, r + 46) then
        placed[#placed + 1] = { x = x, y = y, r = r }
        map.trees[#map.trees + 1] = { x = x, y = y, r = r }
        map.solids[#map.solids + 1] = { x = x - 7, y = y - 7, w = 14, h = 14, tree = true }
        got = got + 1
      end
    end
  end

  -- The square: open for the fight, planters and barriers round its edge only.
  local ax, ay, aw, ah = X(i0), Y(j0), (i1 - i0 + 1) * T, (j1 - j0 + 1) * T
  map.arena = { x = ax, y = ay, w = aw, h = ah }
  map.bossX, map.bossY = math.floor(ax + aw / 2), math.floor(ay + ah / 2)
  local function cover(k, x, y, w, h)
    local s = { kind = k, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
      mapColor = MAP[k] }
    map.cover[#map.cover + 1] = s
    map.solids[#map.solids + 1] = { x = s.x, y = s.y, w = s.w, h = s.h }
  end
  local inset = 200
  for _, k in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    -- A planter with a tree in each corner, a barrier beside it either way.
    local cx = ax + inset + k[1] * (aw - 2 * inset)
    local cy = ay + inset + k[2] * (ah - 2 * inset)
    cover("planter", cx - 44, cy - 44, 88, 88)
    map.trees[#map.trees + 1] = { x = cx, y = cy, r = 30 }
    local sx, sy = k[1] == 0 and 1 or -1, k[2] == 0 and 1 or -1
    cover("barrier", cx + sx * 130 - 70, cy - 14, 140, 28)
    cover("barrier", cx - 14, cy + sy * 130 - 70, 28, 140)
  end
  -- Halfway along each side, a barrier to duck behind on the way in.
  cover("barrier", ax + aw / 2 - 80, ay + 120, 160, 28)
  cover("barrier", ax + 120, ay + ah / 2 - 80, 28, 160)
  cover("barrier", ax + aw - 148, ay + ah / 2 - 80, 28, 160)

  -- Barriers along the streets in: something to hide behind on the way.
  local function streetBarrier(c, r, across)
    if across then
      cover("barrier", X(c) + 8, Y(r) + T / 2 - 14, T * 1.4, 28)
    else
      cover("barrier", X(c) + T / 2 - 14, Y(r) + 8, 28, T * 1.4)
    end
  end
  streetBarrier(20, 49, false)
  streetBarrier(29, 50, false)
  streetBarrier(35, 44, true)
  streetBarrier(6, 38, true)
  streetBarrier(7, 35, true)
  streetBarrier(13, 26, false)
  streetBarrier(51, 29, false)

  -- The Combine: guards at the choke points, squads on beats, and garrisons
  -- behind doors at the guard stations. Beats are woven between the
  -- street barriers (a squad walks straight from corner to corner, three
  -- abreast: 30 px either side of the line).
  local WEST, SOUTH = math.pi, math.pi / 2
  map.posts, map.patrols, map.garrisons = {}, {}, {}
  local function P(c, r)
    return { x = math.floor(X(c)), y = math.floor(Y(r)) }
  end
  local function beat(points)
    local route = {}
    for i, pt in ipairs(points) do
      route[i] = P(pt[1], pt[2])
    end
    map.patrols[#map.patrols + 1] = route
  end
  beat({ { 21, 10.9 }, { 50.6, 10.9 }, { 50.6, 41 }, { 21, 41 } }) -- round the quay
  beat({ { 8.4, 44 }, { 8.4, 36.6 }, { 6.6, 36.6 }, { 6.6, 25.6 }, { 18.5, 25.6 }, { 6.6, 25.6 }, { 6.6, 36.6 },
    { 8.4, 36.6 } }) -- up the left street and out to the west bridge, and back
  beat({ { 19, 51.3 }, { 24.5, 51.3 }, { 24.5, 49.55 }, { 37.3, 49.55 }, { 37.3, 42.6 }, { 37.3, 49.55 },
    { 24.5, 49.55 }, { 24.5, 51.3 } }) -- along the bottom street and up to the south bridge, and back
  --- A post at tile (c, r) watching `watch`; with `garrison`, troops behind
  --- the door of the nearest building, out the first time anyone comes near.
  local function post(at, c, r, watch, garrison)
    local p = P(c, r)
    map.posts[#map.posts + 1] = { x = p.x, y = p.y, watch = watch, at = at }
    if not garrison then
      return
    end
    local best, bestD = nil, math.huge
    for _, b in ipairs(map.buildings) do
      local dx = math.max(b.x - p.x, 0, p.x - (b.x + b.w))
      local dy = math.max(b.y - p.y, 0, p.y - (b.y + b.h))
      local d = dx * dx + dy * dy
      if d < bestD and b.w >= T and b.h >= T then
        best, bestD = b, d
      end
    end
    if not best then
      return
    end
    -- The door: on the face towards the post, as near it as the face allows.
    local b = best
    local x = math.max(b.x + 24, math.min(b.x + b.w - 24, p.x))
    local y = math.max(b.y + 24, math.min(b.y + b.h - 24, p.y))
    local nx, ny = 0, 0
    if p.y >= b.y + b.h then
      y, ny = b.y + b.h, 1
    elseif p.y <= b.y then
      y, ny = b.y, -1
    elseif p.x >= b.x + b.w then
      x, nx = b.x + b.w, 1
    else
      x, nx = b.x, -1
    end
    b.garrison = true -- this one stays standing
    map.garrisons[#map.garrisons + 1] = { at = at, x = p.x, y = p.y, reach = 520,
      door = { x = math.floor(x), y = math.floor(y), nx = nx, ny = ny } }
  end
  post("the bottom street", 32, 51.2, WEST, true)
  post("the waterway crossing", 8.35, 29.2, SOUTH, true) -- east of the squad going up the street
  post("the south bridge", 35.6, 43.2, SOUTH, true)
  post("the east street", 54.5, 30, WEST, true)
  post("the west bridge", 16.5, 27.1, WEST, false)
  --- Is (x, y) `r` clear of every beat, post and door, so nothing left lying
  --- about gets in a squad's way or blocks a door?
  local function offBeats(x, y, r)
    for _, route in ipairs(map.patrols) do
      for i, a in ipairs(route) do
        local b = route[i % #route + 1]
        local dx, dy = b.x - a.x, b.y - a.y
        local k = math.max(0, math.min(1, ((x - a.x) * dx + (y - a.y) * dy) / math.max(1, dx * dx + dy * dy)))
        if (a.x + dx * k - x) ^ 2 + (a.y + dy * k - y) ^ 2 < (r + 50) ^ 2 then
          return false
        end
      end
    end
    for _, p in ipairs(map.posts) do
      if (p.x - x) ^ 2 + (p.y - y) ^ 2 < (r + 70) ^ 2 then
        return false
      end
    end
    for _, g in ipairs(map.garrisons) do
      if (g.door.x - x) ^ 2 + (g.door.y - y) ^ 2 < (r + 90) ^ 2 then
        return false
      end
    end
    return true
  end

  -- Decay ------------------------------------------------------------------
  map.fires = {}
  local function fire(k, x, y, r)
    map.fires[#map.fires + 1] = { kind = k, x = math.floor(x), y = math.floor(y), r = r, seed = rng:random(1000) }
  end
  local function decor(k, x, y, w, h)
    map.cover[#map.cover + 1] = { kind = k, x = math.floor(x), y = math.floor(y), w = math.floor(w), h = math.floor(h),
      mapColor = MAP[k], decor = true, seed = rng:random(1000) }
  end
  --- Is (x, y) open paving, `r` clear of anything solid and of the bridges?
  local function open(x, y, r)
    local col = map.tiles[math.floor((x - map.x0) / T)]
    if not col or col[math.floor((y - map.y0) / T)] ~= "walk" then
      return false
    end
    for _, b in ipairs(map.solids) do
      if x + r > b.x and x - r < b.x + b.w and y + r > b.y and y - r < b.y + b.h then
        return false
      end
    end
    for _, b in ipairs(map.bridges) do
      if x + r > b.x and x - r < b.x + b.w and y + r > b.y and y - r < b.y + b.h then
        return false
      end
    end
    return true
  end
  local start = { x = X(3), y = Y(46), w = 12 * T, h = 8 * T } -- the arrival square stays clear
  local function inStart(x, y, pad)
    return x > start.x - pad and x < start.x + start.w + pad and y > start.y - pad and y < start.y + start.h + pad
  end
  local function inArena(x, y, pad)
    return x > ax - pad and x < ax + aw + pad and y > ay - pad and y < ay + ah + pad
  end

  -- Fallen buildings: rubble where they stood, still in the way. Roofs
  -- holed and grown over on plenty of those still up.
  local standing = {}
  for _, b in ipairs(map.buildings) do
    local roll = rng:random()
    if roll < 0.15 and not b.garrison then
      decor("rubble", b.x, b.y, b.w, b.h)
      -- Some of it spilt out round the heap, to walk through.
      for _ = 1, 3 do
        local x = b.x + rng:random() * b.w
        local y = b.y + (rng:random() < 0.5 and -30 or b.h + 30)
        if open(x, y, 24) then
          decor("rubble", x - 28, y - 22, 56, 44)
        end
      end
    else
      if roll < 0.45 then
        b.holes = {}
        for k = 1, rng:random(1, 2) do
          b.holes[k] = { x = 24 + rng:random() * (b.w - 48), y = 24 + rng:random() * (b.h - 48),
            r = 8 + rng:random() * 12, seed = rng:random(1000) }
        end
      end
      if rng:random() < 0.35 then
        b.vines = rng:random(1000)
      end
      standing[#standing + 1] = b
    end
  end
  map.buildings = standing

  -- Wrecks left where they stopped, rusting: cover on the way in.
  local got = 0
  for _ = 1, 600 do
    if got >= 14 then
      break
    end
    local x, y = X(0) + rng:random() * cols * T, Y(0) + rng:random() * rows * T
    if open(x, y, 70) and not inStart(x, y, 120) and not inArena(x, y, 60) and offBeats(x, y, 50) then
      local across = rng:random() < 0.5
      local w, h = across and 84 or 42, across and 42 or 84
      cover("wreck", x - w / 2, y - h / 2, w, h)
      map.cover[#map.cover].seed = rng:random(1000)
      got = got + 1
    end
  end
  -- Drums with fires in them, and a few roofs still smouldering.
  got = 0
  for _ = 1, 400 do
    if got >= 9 then
      break
    end
    local x, y = X(0) + rng:random() * cols * T, Y(0) + rng:random() * rows * T
    if open(x, y, 40) and not inArena(x, y, 0) and not inStart(x, y, 150) and offBeats(x, y, 20) then
      cover("barrel", x - 14, y - 14, 28, 28)
      fire("barrel", x, y, 14)
      got = got + 1
    end
  end
  for _ = 1, 4 do
    local b = standing[rng:random(#standing)]
    if b.w >= 2 * T and b.h >= 2 * T and not b.burning then
      b.burning = true
      fire("roof", b.x + b.w * (0.3 + rng:random() * 0.4), b.y + b.h * (0.3 + rng:random() * 0.4), 26)
    end
  end
  -- Rubbish heaped along the streets, walked through.
  got = 0
  for _ = 1, 900 do
    if got >= 60 then
      break
    end
    local x, y = X(0) + rng:random() * cols * T, Y(0) + rng:random() * rows * T
    local w, h = 26 + rng:random() * 40, 22 + rng:random() * 30
    if open(x, y, math.max(w, h) / 2 + 6) then
      decor("trash", x - w / 2, y - h / 2, w, h)
      got = got + 1
    end
  end

  -- Zones, south to north.
  map.zones[#map.zones + 1] = { name = "the way in", y0 = Y(42), y1 = Y(rows) }
  map.zones[#map.zones + 1] = { name = "the square", y0 = ay, y1 = ay + ah }

  -- Arrival in the bottom left square, the way home at its left end.
  map.cx, map.cy = math.floor(X(4.5)), math.floor(Y(50))
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = { x = X(6.5) + (i % 8) * 56, y = Y(47.8) + math.floor(i / 8) * 150,
      angle = -math.pi / 2 }
  end
end

return OuterCity
