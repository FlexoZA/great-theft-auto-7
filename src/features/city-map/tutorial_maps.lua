-- The maps of Shoeman's school of survival (the tutorial feature,
-- docs/tutorial.md). So far three are built; the town is still an open
-- field (city-map/init.lua's `empty` spec):
--   tutorial-road  Shoeman's Road (level 1): small and tall. At the bottom
--                  the school yard, where everyone arrives: the checkpoint,
--                  Shoeman, the HOME star. Above it four two-way streets
--                  running left to right, two lanes each way, with a strip
--                  of pavement between them where nothing drives; each
--                  street runs into a tunnel under the embankment at both
--                  edges. At the top a lawn and the way on.
--   tutorial-park  Shoeman's Park (level 2): large and square, hedged all
--                  round. Shoeman stands on a small paved circle in the
--                  middle of a wide open lawn (the dodging ground, a chalk
--                  ring round it), nothing on it to hide behind. A gravel
--                  path runs from the start at the bottom (the checkpoint,
--                  the HOME star, his board) up through his circle to the
--                  gate at the top, the way on. Trees, a pond, beds and
--                  benches in the corners, outside the ring.
--   tutorial-yard  Shoeman's Scrap Yard (level 3): square, fenced in
--                  corrugated sheet. Everyone arrives on a concrete pad in
--                  the bottom-left corner (the checkpoint, Shoeman, the
--                  HOME star, his board, the site office); the way on is
--                  the gate in the top fence, right of the middle. Wrecks
--                  piled along three fences and the crusher in the top-left
--                  corner; out in the yard single wrecks and tyre heaps for
--                  cover, room to run between them, and the squirrels'
--                  burrows in the far half.
--
-- Tiles are "road" (the streets, into their tunnels) and "walk" (the
-- pavement, the yard, the lawn); nil is the embankment either side (the
-- layout's walls make it solid). Walked: nobody about, no traffic of the
-- usual kind. The tutorial's own traffic (tutorial/traffic.lua) drives the
-- lanes this leaves on the map:
--   map.streets   { n, y0, y1 } world px, bottom (1, the slowest) to top (4, the fastest)
--   map.lanes     { y, dir, street, lane, angle, fromX, toX } every lane's middle, world px: `dir` 1
--                 drives east (angle 0), -1 west (angle pi); a car comes out of the tunnel at `fromX`
--                 and is gone into the other at `toX`, both out of sight under the roofs. `lane` 1 is
--                 the one by the centre line, 2 the one by the kerb. Bottom street first, south lane
--                 first.
--   map.tunnels   { x, y, w, h, side } the roof over each street's ends ("w" or "e"), world px: drawn
--                 over the cars (render_tutorial.lua `drawAbove`), so they come and go unseen
--   map.cx, cy    the start: the middle of the spawns, and the checkpoint (tutorial/checkpoint.lua)
--   map.exitX, exitY  the way on, in the middle of the top lawn (Tutorial.EXITS)
--   map.homeX, homeY  the HOME star, south of the start (quests' `home-tutorial-road`)
--   map.shoemanX, shoemanY  where Shoeman stands (Tutorial.SHOEMAN), between the start and the star
--   map.decor     { kind, x, y, ... } what the canvas draws and nothing else: skid (a tyre mark, `len`,
--                 `a`), crack (`len`, `a`, `seed`), stain (oil, `r`), manhole, grate, bed (a flower bed,
--                 `w`, `h`, `seed`), bench (`a` the way it faces), board (the school's sign), tree
--                 (a small one in a bed, `r`), look (a "LOOK" warning painted on the kerb, `text`)
--   map.openKinds { walk = true }: pickups go on the pavement too
--
-- The park leaves the same `cx, cy`, `exitX, exitY`, `homeX, homeY`,
-- `shoemanX, shoemanY` and `openKinds` (every tile inside the hedge is
-- "walk"; the hedge row round the edge is nil), and:
--   map.ring      { x, y, r } the dodging ground round Shoeman, world px: open lawn, nothing solid
--   map.paths     { x, y, w, h } the gravel paths, world px
--   map.pond      { x, y, rx, ry } the pond (solid, as three boxes inside its ellipse)
--   map.trees     { x, y, r } every tree (a small solid box round each trunk)
--   map.decor     as the road's, plus lamp, shoe (an old one in the grass, `a`), gate (the way on
--                 through the top hedge, `w`) and chalk (the ring, drawn from map.ring)
--
-- The scrap yard leaves the same `cx, cy`, `exitX, exitY`, `homeX, homeY`,
-- `shoemanX, shoemanY` and `openKinds` (inside the fence "walk", the fence
-- row nil), and, all world px:
--   map.pad       { x, y, w, h } the concrete pad everyone arrives on
--   map.dropX, dropY  where Shoeman puts the pistol down, in front of him (tutorial/pistol.lua)
--   map.office    the site office (a solid), against the west fence above the pad
--   map.crusher   the crusher (a solid), top-left corner; its crane is drawn over it
--   map.gate      { x, y, w } the way on through the top fence (drawn shut; the EXIT star is the way)
--   map.wrecks    { x, y, w, h, a, color, seed, flip, burnt } a lone wreck, centred, its `solid` the
--                 box; `a` only tilts the drawing
--   map.piles     the piled wrecks along the fences (each a solid), `along` "x" or "y", `cars` drawn
--   map.tyres     { x, y, seed } a heap of tyres (a 44 px solid box each)
--   map.dens      { x, y } the squirrels' burrows, in the far half (tutorial/waves.lua)
--   map.decor     track (`len`, `a`), stain and puddle (`r`), drum, part, door, wheel (`a`, `seed`),
--                 board (Shoeman's), sign (the yard's, by the office)

local TutorialMaps = {}

-- Shoeman's Road, in tiles. The rows from the top: the lawn with the way
-- on (`top`), then each street (`street` rows, two lanes each way) with a
-- strip of pavement (`strip` rows) between it and the next, then the yard
-- (the rest). `verge` columns of embankment either side, the tunnels
-- under them.
TutorialMaps.ROAD = { top = 6, street = 4, strip = 3, streets = 4, verge = 2 }

local function buildRoad(map, rng, T)
  local R = TutorialMaps.ROAD
  local cols, rows = map.cols, map.rows
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  local c0, c1 = R.verge, cols - 1 - R.verge -- the walked columns
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      map.tiles[c][r] = (c >= c0 and c <= c1) and "walk" or nil
    end
  end
  map.streets, map.lanes, map.tunnels, map.decor = {}, {}, {}, {}
  map.openKinds = { walk = true }

  -- The streets, top (the fastest, 4) down to the bottom (1).
  local first = {}
  for i = 1, R.streets do
    local r0 = R.top + (i - 1) * (R.street + R.strip)
    first[R.streets + 1 - i] = r0
  end
  local yardRow = first[1] + R.street -- the first row of the yard
  local left, right = X(0), X(cols)
  for n = 1, R.streets do
    local r0 = first[n]
    for c = 0, cols - 1 do
      for r = r0, r0 + R.street - 1 do
        map.tiles[c][r] = "road"
      end
    end
    local y0, y1 = Y(r0), Y(r0 + R.street)
    map.streets[n] = { n = n, y0 = y0, y1 = y1 }
    -- Drive on the right: the south half runs east, the north half west.
    -- Each half lists its lane by the centre line first.
    local half = R.street / 2
    for k = 1, half do
      local y = Y(r0 + half + k - 1) + T / 2
      map.lanes[#map.lanes + 1] = { y = y, dir = 1, street = n, lane = k, angle = 0,
        fromX = left + T / 2, toX = right - T / 2 }
    end
    for k = 1, half do
      local y = Y(r0 + half - k) + T / 2
      map.lanes[#map.lanes + 1] = { y = y, dir = -1, street = n, lane = k, angle = math.pi,
        fromX = right - T / 2, toX = left + T / 2 }
    end
    map.tunnels[#map.tunnels + 1] = { x = left, y = y0, w = R.verge * T, h = y1 - y0, side = "w" }
    map.tunnels[#map.tunnels + 1] = { x = X(c1 + 1), y = y0, w = R.verge * T, h = y1 - y0, side = "e" }
  end

  -- Where everyone arrives: twelve spawns facing the streets, two rows of
  -- six, three rows into the yard; the start (and the checkpoint) between
  -- the rows, Shoeman south-east of it and the HOME star south of him.
  local sr = yardRow + 2
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = { x = (i % 6 - 2.5) * 80, y = Y(sr + math.floor(i / 6)) + T / 2,
      angle = -math.pi / 2 }
  end
  map.cx, map.cy = 0, Y(sr + 1)
  map.shoemanX, map.shoemanY = 160, map.cy + 120
  map.homeX, map.homeY = 0, map.cy + 240
  map.exitX, map.exitY = 0, Y(R.top / 2)

  -- What the canvas draws. On every street: tyre marks where somebody
  -- braked too late, cracks, oil, a manhole or two; at the kerb under each
  -- street, "LOOK" painted the way the first lane comes from.
  local d = map.decor
  local inL, inR = X(c0), X(c1 + 1)
  for _, s in ipairs(map.streets) do
    for _ = 1, 3 + s.n do
      local x, y = inL + 100 + rng:random() * (inR - inL - 200), s.y0 + rng:random(0, 3) * T + 18 + rng:random() * 28
      d[#d + 1] = { kind = "skid", x = x, y = y, len = 60 + rng:random() * 120, a = (rng:random() - 0.5) * 0.25 }
    end
    for _ = 1, 4 do
      local x, y = inL + rng:random() * (inR - inL), s.y0 + 12 + rng:random() * (s.y1 - s.y0 - 24)
      d[#d + 1] = { kind = "crack", x = x, y = y, len = 30 + rng:random() * 50, a = rng:random() * math.pi,
        seed = rng:random(1000) }
    end
    for _ = 1, 3 do
      d[#d + 1] = { kind = "stain", x = inL + rng:random() * (inR - inL), y = s.y0 + rng:random(0, 3) * T + T / 2,
        r = 8 + rng:random() * 12 }
    end
    d[#d + 1] = { kind = "manhole", x = math.floor(inL + (0.2 + rng:random() * 0.6) * (inR - inL)),
      y = s.y0 + (rng:random() < 0.5 and 1 or 3) * T }
    d[#d + 1] = { kind = "grate", x = math.floor(inL + rng:random() * (inR - inL - 40) + 20), y = s.y1 - 10 }
    d[#d + 1] = { kind = "grate", x = math.floor(inL + rng:random() * (inR - inL - 40) + 20), y = s.y0 + 10 }
    d[#d + 1] = { kind = "look", x = 0, y = s.y1 + 26, text = "LOOK LEFT" }
  end

  -- The yard: flower beds and small trees down either side, benches facing
  -- the middle, Shoeman's board by the HOME star.
  local yard0, yard1 = Y(yardRow), Y(rows)
  for _, side in ipairs({ -1, 1 }) do
    local bx = side < 0 and inL + 40 or inR - 40 - 150
    d[#d + 1] = { kind = "bed", x = bx, y = yard0 + 120, w = 150, h = yard1 - yard0 - 240, seed = rng:random(1000) }
    for k = 0, 2 do
      d[#d + 1] = { kind = "tree", x = bx + 75, y = yard0 + 210 + k * ((yard1 - yard0 - 420) / 2),
        r = 30 + rng:random() * 8 }
    end
    d[#d + 1] = { kind = "bench", x = bx + (side < 0 and 190 or -40), y = map.cy + 40, a = side < 0 and 0 or math.pi }
  end
  d[#d + 1] = { kind = "board", x = -110, y = map.homeY + 90 }

  -- The lawn at the top: beds either side of the path to the way on.
  for _, side in ipairs({ -1, 1 }) do
    local bx = side < 0 and inL + 40 or inR - 40 - 220
    d[#d + 1] = { kind = "bed", x = bx, y = Y(1), w = 220, h = (R.top - 2) * T, seed = rng:random(1000) }
    d[#d + 1] = { kind = "tree", x = bx + 110, y = Y(R.top / 2), r = 34 }
  end
end

-- Shoeman's Park, in px from its middle (where Shoeman stands): the
-- dodging ground's radius, his paved circle's, the path's width, how far
-- south the start is (the checkpoint: a shoe needs time to dodge), and
-- how many tiles of hedge round the edge.
TutorialMaps.PARK = { ring = 640, plaza = 96, path = 64, start = 768, hedge = 1 }

local function buildPark(map, rng, T)
  local P = TutorialMaps.PARK
  local cols, rows = map.cols, map.rows
  local function Y(r)
    return map.y0 + r * T
  end
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      local inside = c >= P.hedge and c < cols - P.hedge and r >= P.hedge and r < rows - P.hedge
      map.tiles[c][r] = inside and "walk" or nil
    end
  end
  map.decor, map.paths = {}, {}
  map.openKinds = { walk = true }
  map.shoemanX, map.shoemanY = 0, 0
  map.ring = { x = 0, y = 0, r = P.ring }
  local inL, inR = map.x0 + P.hedge * T, map.x0 + (cols - P.hedge) * T
  local inT, inB = Y(P.hedge), Y(rows - P.hedge)

  -- Where everyone arrives: twelve spawns facing Shoeman, two rows of six
  -- either side of the start, the HOME star south of it.
  map.cx, map.cy = 0, P.start
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = { x = (i % 6 - 2.5) * 80, y = P.start + (math.floor(i / 6) * 2 - 1) * T / 2,
      angle = -math.pi / 2 }
  end
  map.homeX, map.homeY = 0, P.start + 240
  map.exitX, map.exitY = 0, inT + 2.5 * T
  -- The path from the hedge at the bottom to the gate at the top, through
  -- his circle; a wider square of gravel where everyone arrives.
  local half = P.path / 2
  map.paths[#map.paths + 1] = { x = -half, y = inT, w = P.path, h = inB - inT }
  map.paths[#map.paths + 1] = { x = -560, y = P.start - 96, w = 1120, h = 192 }
  map.paths[#map.paths + 1] = { x = -160, y = map.exitY - 112, w = 320, h = 224 }

  local d = map.decor
  d[#d + 1] = { kind = "chalk" }
  d[#d + 1] = { kind = "gate", x = 0, y = inT, w = 3 * T }
  d[#d + 1] = { kind = "board", x = -340, y = map.homeY - 40 }
  -- Lamps and benches beside the path, outside the ring.
  for _, y in ipairs({ P.start + 200, -P.ring - 80, -P.ring - 300, map.exitY + 220 }) do
    d[#d + 1] = { kind = "lamp", x = -half - 26, y = y }
    d[#d + 1] = { kind = "lamp", x = half + 26, y = y - 60 }
  end
  for _, side in ipairs({ -1, 1 }) do
    d[#d + 1] = { kind = "bench", x = side * 620, y = P.start - 40, a = side < 0 and 0 or math.pi }
  end
  -- Old shoes in the grass, most of them round the ring where he has
  -- missed before.
  for _ = 1, 22 do
    local a, dist = rng:random() * math.pi * 2, P.plaza + 60 + rng:random() * (P.ring + 200)
    local x, y = math.cos(a) * dist, math.sin(a) * dist
    if math.abs(x) > half + 20 then
      d[#d + 1] = { kind = "shoe", x = x, y = y, a = rng:random() * math.pi * 2 }
    end
  end

  -- The corners, outside the ring: the pond on the west side, beds, and
  -- trees wherever there is room.
  local pond = { x = inL + 330, y = -340, rx = 220, ry = 140 }
  map.pond = pond
  for _, f in ipairs({ { 1, 0.55 }, { 0.85, 0.85 }, { 0.55, 1 } }) do -- boxes inside the ellipse
    local w, h = pond.rx * 2 * f[1], pond.ry * 2 * f[2]
    map.solids[#map.solids + 1] = { x = pond.x - w / 2, y = pond.y - h / 2, w = w, h = h }
  end
  local beds = {
    { x = inR - 420, y = -360, w = 260, h = 140 },
    { x = inL + 160, y = 300, w = 220, h = 120 },
    { x = inR - 380, y = 360, w = 220, h = 120 },
  }
  for _, b in ipairs(beds) do
    d[#d + 1] = { kind = "bed", x = b.x, y = b.y, w = b.w, h = b.h, seed = rng:random(1000) }
  end
  local function clear(x, y, r)
    if x * x + y * y < (P.ring + r + 60) ^ 2 or math.abs(x) < half + r + 40 then
      return false
    end
    if x < inL + r + 20 or x > inR - r - 20 or y < inT + r + 20 or y > inB - r - 20 then
      return false
    end
    if math.abs(y - P.start) < 140 + r or math.abs(y - map.exitY) < 140 + r then
      return false
    end
    local px, py = (x - pond.x) / (pond.rx + r + 30), (y - pond.y) / (pond.ry + r + 30)
    if px * px + py * py < 1 then
      return false
    end
    for _, b in ipairs(beds) do
      if x > b.x - r - 20 and x < b.x + b.w + r + 20 and y > b.y - r - 20 and y < b.y + b.h + r + 20 then
        return false
      end
    end
    for _, t in ipairs(map.trees) do
      if (t.x - x) ^ 2 + (t.y - y) ^ 2 < (t.r + r + 30) ^ 2 then
        return false
      end
    end
    return true
  end
  for _ = 1, 600 do
    if #map.trees >= 44 then
      break
    end
    local r = 26 + rng:random() * 14
    local x, y = inL + rng:random() * (inR - inL), inT + rng:random() * (inB - inT)
    if clear(x, y, r) then
      map.trees[#map.trees + 1] = { x = x, y = y, r = r }
      map.solids[#map.solids + 1] = { x = x - 8, y = y - 8, w = 16, h = 16, tree = true }
    end
  end
end

-- Shoeman's Scrap Yard. `fence` tiles of corrugated fence round the
-- edge; the start's concrete pad in the bottom-left corner (px, from the
-- fence); the gate (the way on) in the top fence, `gate` px east of the
-- middle; wrecks for cover on a jittered grid of `grid` px, one in a cell
-- with chance `fill`; `stack` px deep of piled wrecks along three fences.
TutorialMaps.YARD = { fence = 1, padW = 768, padH = 512, gate = 832, grid = 288, fill = 0.6, stack = 88 }

TutorialMaps.WRECK_COLORS = { -- the paint on wrecks; the renderer picks loose doors from it too
  { 0.55, 0.20, 0.17 }, { 0.22, 0.32, 0.50 }, { 0.62, 0.58, 0.50 }, { 0.30, 0.40, 0.28 },
  { 0.70, 0.55, 0.22 }, { 0.36, 0.36, 0.38 }, { 0.48, 0.30, 0.42 }, { 0.80, 0.78, 0.74 },
}

local function buildYard(map, rng, T)
  local YD = TutorialMaps.YARD
  local paint = TutorialMaps.WRECK_COLORS
  local cols, rows = map.cols, map.rows
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      local inside = c >= YD.fence and c < cols - YD.fence and r >= YD.fence and r < rows - YD.fence
      map.tiles[c][r] = inside and "walk" or nil
    end
  end
  map.decor, map.wrecks, map.piles, map.tyres, map.dens = {}, {}, {}, {}, {}
  map.openKinds = { walk = true }
  local inL, inR = map.x0 + YD.fence * T, map.x0 + (cols - YD.fence) * T
  local inT, inB = map.y0 + YD.fence * T, map.y0 + (rows - YD.fence) * T
  local function solid(s)
    map.solids[#map.solids + 1] = s
    return s
  end

  -- The bottom-left corner: the concrete pad everyone arrives on, the
  -- site office up against the west fence above it.
  local pad = { x = inL, y = inB - YD.padH, w = YD.padW, h = YD.padH }
  map.pad = pad
  map.cx, map.cy = pad.x + pad.w / 2 - 64, pad.y + 192
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = { x = map.cx + (i % 6 - 2.5) * 80, y = map.cy + (math.floor(i / 6) * 2 - 1) * T / 2,
      angle = -math.pi / 2 }
  end
  map.shoemanX, map.shoemanY = map.cx + 160, map.cy + 120
  map.homeX, map.homeY = map.cx, map.cy + 240
  map.dropX, map.dropY = map.shoemanX + 136, map.shoemanY - 76
  map.office = solid({ x = inL, y = pad.y - 200, w = 176, h = 152 })
  map.gate = { x = YD.gate, y = inT, w = 3 * T }
  map.exitX, map.exitY = YD.gate, inT + 2.5 * T

  -- Piled wrecks along the top, east and west fences, kept clear of the
  -- gate and the office; the crusher and its crane in the top-left corner.
  local S = YD.stack
  local function pile(x, y, w, h, along)
    local p = solid({ x = x, y = y, w = w, h = h })
    p.along, p.seed, p.cars = along, rng:random(1000), {}
    local len = along == "x" and w or h
    for k = 0, math.floor(len / 84) - 1 do
      p.cars[#p.cars + 1] = { color = paint[rng:random(#paint)], tall = rng:random(1, 3),
        jx = (rng:random() - 0.5) * 8, jy = (rng:random() - 0.5) * 8, k = k }
    end
    map.piles[#map.piles + 1] = p
  end
  local crusher = { x = inL + 40, y = inT + 40, w = 224, h = 160 }
  map.crusher = solid(crusher)
  local topL, topR = crusher.x + crusher.w + 120, YD.gate - 3 * T / 2 - 120
  pile(topL, inT, topR - topL, S, "x")
  pile(YD.gate + 3 * T / 2 + 120, inT, inR - (YD.gate + 3 * T / 2 + 120), S, "x")
  pile(inR - S, inT + S + 160, S, inB - 320 - (inT + S + 160), "y")
  pile(inL, crusher.y + crusher.h + 160, S, map.office.y - 160 - (crusher.y + crusher.h + 160), "y")

  -- The squirrels' burrows (waves.lua brings them out here): mounds of
  -- dirt in the far half of the yard, away from the pad.
  for _, p in ipairs({ { -300, -900 }, { 320, -700 }, { 900, -220 }, { 520, 320 }, { -560, -320 } }) do
    map.dens[#map.dens + 1] = { x = p[1], y = p[2] }
  end

  -- Room kept clear: the pad and a margin, the office's door, the way to
  -- the gate, Shoeman's spot, the dens.
  local function clear(x, y, r)
    if x < inL + S + r + 30 or x > inR - S - r - 30 or y < inT + S + r + 30 or y > inB - r - 30 then
      return false
    end
    if x < pad.x + pad.w + r + 60 and y > pad.y - r - 60 then
      return false
    end
    if (x - map.exitX) ^ 2 + (y - map.exitY) ^ 2 < (240 + r) ^ 2 then
      return false
    end
    for _, s in ipairs(map.solids) do
      if x > s.x - r - 70 and x < s.x + s.w + r + 70 and y > s.y - r - 70 and y < s.y + s.h + r + 70 then
        return false
      end
    end
    for _, dn in ipairs(map.dens) do
      if (x - dn.x) ^ 2 + (y - dn.y) ^ 2 < (100 + r) ^ 2 then
        return false
      end
    end
    return true
  end

  -- Wrecks for cover: a car on its own, long side either way, on a
  -- jittered grid so there is always a way between them. Its solid box is
  -- the body (rounds stop on it); the drawing tilts it a touch.
  local G = YD.grid
  for gx = inL + G / 2, inR - G / 2, G do
    for gy = inT + G / 2, inB - G / 2, G do
      if rng:random() < YD.fill then
        local x, y = gx + (rng:random() - 0.5) * G * 0.4, gy + (rng:random() - 0.5) * G * 0.4
        local long = rng:random() < 0.5
        local w, h = long and 80 or 40, long and 40 or 80
        if clear(x, y, 40) then
          local s = solid({ x = x - w / 2, y = y - h / 2, w = w, h = h })
          map.wrecks[#map.wrecks + 1] = { x = x, y = y, w = w, h = h, solid = s, a = (rng:random() - 0.5) * 0.12,
            color = paint[rng:random(#paint)], seed = rng:random(1000), flip = rng:random() < 0.5,
            burnt = rng:random() < 0.2 }
        end
      end
    end
  end
  -- Tyre heaps here and there (solid), oil drums, puddles, tyre tracks,
  -- loose parts (not solid).
  for _ = 1, 200 do
    if #map.tyres >= 10 then
      break
    end
    local x, y = inL + rng:random() * (inR - inL), inT + rng:random() * (inB - inT)
    if clear(x, y, 34) then
      map.tyres[#map.tyres + 1] = { x = x, y = y, seed = rng:random(1000) }
      solid({ x = x - 22, y = y - 22, w = 44, h = 44 })
    end
  end
  local d = map.decor
  for _ = 1, 26 do
    local x, y = inL + 60 + rng:random() * (inR - inL - 120), inT + 60 + rng:random() * (inB - inT - 120)
    d[#d + 1] = { kind = "track", x = x, y = y, len = 120 + rng:random() * 260, a = rng:random() * math.pi * 2 }
  end
  for _ = 1, 20 do
    d[#d + 1] = { kind = rng:random() < 0.6 and "stain" or "puddle", x = inL + rng:random() * (inR - inL),
      y = inT + rng:random() * (inB - inT), r = 10 + rng:random() * 22 }
  end
  local junk = 0
  for _ = 1, 200 do
    if junk >= 40 then
      break
    end
    local x, y = inL + rng:random() * (inR - inL), inT + rng:random() * (inB - inT)
    if clear(x, y, 18) then
      junk = junk + 1
      local kinds = { "drum", "drum", "part", "part", "door", "wheel" }
      d[#d + 1] = { kind = kinds[rng:random(#kinds)], x = x, y = y, a = rng:random() * math.pi * 2,
        seed = rng:random(1000) }
    end
  end
  d[#d + 1] = { kind = "board", x = pad.x + pad.w - 260, y = map.homeY - 30 }
  d[#d + 1] = { kind = "sign", x = map.office.x + map.office.w + 24, y = map.office.y + 24 }
end

local BUILDERS = { ["tutorial-road"] = buildRoad, ["tutorial-park"] = buildPark, ["tutorial-yard"] = buildYard }

--- Does this file build maps of `kind`?
function TutorialMaps.builds(kind)
  return BUILDERS[kind] ~= nil
end

function TutorialMaps.build(map, rng, T)
  BUILDERS[map.kind](map, rng, T)
end

return TutorialMaps
