-- Grey City: the five maps of the Cyber Feud quest line (docs/cyber-feud.md),
-- one builder each, all at night (the spec's `night`, the night feature):
--   drop      The Drop: downtown, a grid of tall blocks and wide avenues, walked
--             from a garage in the bottom left to a tunnel at the top
--   market    The Market: a covered market of stalls round Noodle Square, walked
--             from the tunnel at the bottom to a loading dock at the top
--   overpass  The Overpass: an elevated highway with the city far below, driven
--             north, with an off-ramp into the Knot (VEX's "shortcut") and back
--   tower     Halcyon Tower: six floors stacked up the map, a stairwell at
--             alternating ends of each, walked up to the executive lift
--   roof      The Roof: the tower's top, the arena
-- Everyone travels north (up the screen), the way A-Man's trail does.
--
-- Tiles are "road" (driven tarmac) and "walk" (paving, floors, under the
-- buildings); nil is built on or a drop, and the layout's walls make it solid.
--
-- What every one leaves on the map, besides tiles, solids, buildings and spawns:
--   map.cx, map.cy        the way home (a HOME star in quests), by the arrival
--   map.exitX, map.exitY  the far end: the first player there finishes the level (cyber-feud)
--   map.zones             { name, y0, y1 } the stretches of the map, bottom to top
--   map.roads             { x, y, w, h, along = "ns" | "ew" } stretches of road, world px, for the lane lines
--   map.cover             { kind, x, y, w, h, solid, round, color } world px; solid ones are in the solids too.
--                         Kinds: barrier, wreck, drum, vending, stall, screen, desk, rack, tank, table,
--                         reception, lift, relay, ac, mast, gantry, door, tunnel, dock, billboard
--   map.signs             { x, y, w, h, color, text } neon signs on building edges, world px
--   map.lights            { x, y, r, color, a } what glows at night (the night feature draws them), world px
--   map.below             { x, y, r, color } lights far below the overpass (render only), world px
--   map.floors            { name, y0, y1 } the tower's floors (= its zones)
--   map.pickupX, pickupY  the vending machine with the Shard in it (the Drop)
--   map.vexY              the line past which VEX boots up (the Drop)
--   map.helipad           { x, y, r } the Roof's helipad
--   map.knot              { x, y, w, h } the Overpass's dead-end interchange, world px
--   map.troops            { halcyon = side, static = side } the factions' troops (the Drop, the Market, the
--                         Overpass, the tower), each
--                         side { posts = { x, y, watch, at, hold }, patrols = { route } }, world px;
--                         `at` groups the posts of one place (they chat), a route is a loop of { x, y };
--                         and `stations` { nest = { x, y, angle, arc }, posts, garrison = { x, y, reach,
--                         door = { x, y, nx, ny }, count } }: guard stations, an MG nest (or none) and its
--                         crew's posts
--   map.enforcers         { x, y, watch } Halcyon's riot shields on posts (the Market's gates), world px
--   map.rippers           { route, start } the Static's rippers (the Market), each on a beat (a loop of
--                         { x, y }, world px) from corner `start`
--   map.sparkers          { route, start } the Static's sparkers (the Market), as `rippers`
--   map.watchers          { route, start } Halcyon's watcher drones (the Market), flown straight from
--                         corner to corner (corners in the lanes, so they stay where they can be shot)
--   map.interceptors      { x, y, angle } posts Halcyon's interceptors wait on (the Overpass), world px
--   map.rigs              { x, y, angle } posts the Static's war-rigs wait on (the Overpass), world px
--   map.kilowatt          { x, y, startY, exitAngle } where Kilowatt's rig sets off from, the line past
--                         which it does, and the way he jumps off (the Overpass)
--   map.stings            { x, y } where Halcyon's sting drone swarms hang, over the gantries (the Overpass)
--   map.marksmen          { x, y, watch } Halcyon's marksmen up on the gantries (the Overpass), world px
--   map.carStations       { name, x, y, angle } pads where a Courier is called back (the Overpass, the
--                         car-stations feature); the respawn points there too
--   map.gates             { name, solid, frame = { x, y, w, h }, panel = { x, y } } Halcyon's roadblocks across
--                         the road (the Overpass, cyber-feud/gates.lua): `solid` is in map.solids until opened
--   map.breakIns          { x, y, beat } where the Static break in to each of the tower's floors (the lobby's
--                         doors, then the stairwell from below) and the beat they walk there (a loop of { x, y })
--   map.wakeY             the line a player walks past to wake the troops (the Market, the tower: they are on
--                         edge already, but nobody fires at the way in)
--   map.nests             { nest, faction } every station's MG nest (a-man/nests.lua draws the guns)
--   map.droids            { route } the assassin droids' beat (the Drop), a loop of { x, y }, world px
--   map.openKinds         { walk = true } on the walked maps: pickups and the like go on the floor
--   map.crowdClothes      { shirts, pants } what the Drop's crowd wears (pedestrians reads it)
-- render_cyber_feud.lua draws them.

local CyberFeud = {}

-- Neon, by who holds the block.
CyberFeud.MAGENTA = { 1.00, 0.24, 0.78 } -- Halcyon
CyberFeud.CYAN = { 0.18, 0.90, 1.00 } -- the Static
CyberFeud.GREEN = { 0.43, 1.00, 0.60 } -- VEX
CyberFeud.LAMP = { 1.00, 0.86, 0.62 } -- street lamps, lanterns
CyberFeud.WHITE = { 0.80, 0.88, 1.00 } -- office light

-- Concrete, in cold greys.
local ROOFS = {
  { 0.34, 0.35, 0.37 },
  { 0.29, 0.30, 0.33 },
  { 0.40, 0.40, 0.41 },
  { 0.25, 0.26, 0.29 },
  { 0.37, 0.36, 0.38 },
}

CyberFeud.SIGNS = {
  "NOODLZ", "CHROME 4 LESS", "RIPPERDOC", "NO REFUNDS", "SOYLENT FRIED", "KARMA KREDIT", "MEAT (REAL*)",
  "24/7", "SYNTH SUSHI", "BIT BAR", "PAWN", "HOTEL", "DATA DEN", "VAPES", "LOANS", "CLONE CARE",
}

-- Building blocks ------------------------------------------------------------

--- The grid every builder works on: `kind[c][r]` for the tiles, and the
--- helpers to fill it and to put things on the map in tile units.
local function grid(map, T)
  local g = { kind = {}, T = T }
  for c = 0, map.cols - 1 do
    g.kind[c] = {}
  end
  function g.X(c)
    return map.x0 + c * T
  end
  function g.Y(r)
    return map.y0 + r * T
  end
  function g.fill(c0, r0, c1, r1, k)
    for c = math.max(0, c0), math.min(map.cols - 1, c1) do
      for r = math.max(0, r0), math.min(map.rows - 1, r1) do
        g.kind[c][r] = k
      end
    end
  end
  function g.at(c, r)
    return g.kind[c] and g.kind[c][r]
  end
  map.cover, map.zones, map.roads, map.signs, map.lights = {}, {}, {}, {}, {}
  return g
end

--- Copy the grid's tiles onto the map.
local function commit(map, g)
  for c = 0, map.cols - 1 do
    map.tiles[c] = {}
    for r = 0, map.rows - 1 do
      map.tiles[c][r] = g.kind[c][r]
    end
  end
end

local function light(map, x, y, r, color, a)
  map.lights[#map.lights + 1] = { x = x, y = y, r = r, color = color, a = a or 1 }
end

--- Something standing on the map, in world px. Solid unless `solid` is false.
local function cover(map, kind, x, y, w, h, solid, extra)
  local s = { kind = kind, x = x, y = y, w = w, h = h, solid = solid ~= false }
  for k, v in pairs(extra or {}) do
    s[k] = v
  end
  map.cover[#map.cover + 1] = s
  if s.solid then
    map.solids[#map.solids + 1] = { x = x, y = y, w = w, h = h }
  end
  return s
end

local function road(map, x, y, w, h, along)
  map.roads[#map.roads + 1] = { x = x, y = y, w = w, h = h, along = along }
end

--- A building over tiles (tx, ty, tw, th), solid, with a neon sign on one
--- edge in `neon` (a colour, or nil for none) glowing at night.
local function building(map, rng, g, tx, ty, tw, th, neon)
  local b = {
    x = g.X(tx),
    y = g.Y(ty),
    w = tw * g.T,
    h = th * g.T,
    color = ROOFS[rng:random(#ROOFS)],
    style = rng:random(3),
    seed = rng:random(1000),
  }
  map.buildings[#map.buildings + 1] = b
  map.solids[#map.solids + 1] = { x = b.x, y = b.y, w = b.w, h = b.h }
  if neon then
    -- Along the edge facing the street, whichever one has open ground in front.
    local text = CyberFeud.SIGNS[rng:random(#CyberFeud.SIGNS)]
    local sides = {}
    if g.at(tx + math.floor(tw / 2), ty + th) then
      sides[#sides + 1] = "s"
    end
    if g.at(tx + math.floor(tw / 2), ty - 1) then
      sides[#sides + 1] = "n"
    end
    if g.at(tx - 1, ty + math.floor(th / 2)) then
      sides[#sides + 1] = "w"
    end
    if g.at(tx + tw, ty + math.floor(th / 2)) then
      sides[#sides + 1] = "e"
    end
    local side = sides[rng:random(math.max(1, #sides))] or "s"
    local len = math.min(b.w, b.h) * (0.5 + rng:random() * 0.3)
    local s
    if side == "s" or side == "n" then
      len = math.min(b.w - 24, math.max(len, 90))
      local x = b.x + (b.w - len) * rng:random()
      s = { x = x, y = side == "s" and b.y + b.h - 10 or b.y + 2, w = len, h = 8 }
    else
      len = math.min(b.h - 24, math.max(len, 90))
      local y = b.y + (b.h - len) * rng:random()
      s = { x = side == "e" and b.x + b.w - 10 or b.x + 2, y = y, w = 8, h = len }
    end
    s.color, s.text, s.side = neon, text, side
    map.signs[#map.signs + 1] = s
    -- The glow spills onto the street in front of it.
    local ox = side == "e" and 40 or side == "w" and -40 or 0
    local oy = side == "s" and 40 or side == "n" and -40 or 0
    light(map, s.x + s.w / 2 + ox, s.y + s.h / 2 + oy, 110 + len * 0.6, neon, 0.75)
  end
  return b
end

--- Split tiles (tx, ty, tw, th) into one to four buildings with 1-tile
--- alleys between them, the way the city's blocks are split.
local function splitBlock(map, rng, g, tx, ty, tw, th, neon)
  local parts
  if tw >= 6 and th >= 6 and rng:random() < 0.6 then
    local sx, sy = rng:random(2, tw - 3), rng:random(2, th - 3)
    parts = {
      { tx, ty, sx, sy },
      { tx + sx + 1, ty, tw - sx - 1, sy },
      { tx, ty + sy + 1, sx, th - sy - 1 },
      { tx + sx + 1, ty + sy + 1, tw - sx - 1, th - sy - 1 },
    }
  elseif tw >= 5 and rng:random() < 0.5 then
    local sx = rng:random(2, tw - 3)
    parts = { { tx, ty, sx, th }, { tx + sx + 1, ty, tw - sx - 1, th } }
  elseif th >= 5 then
    local sy = rng:random(2, th - 3)
    parts = { { tx, ty, tw, sy }, { tx, ty + sy + 1, tw, th - sy - 1 } }
  else
    parts = { { tx, ty, tw, th } }
  end
  for _, p in ipairs(parts) do
    if p[3] >= 1 and p[4] >= 1 then
      local lit = neon and rng:random() < 0.7 and neon(g.X(p[1] + p[3] / 2)) or nil
      building(map, rng, g, p[1], p[2], p[3], p[4], lit)
    end
  end
end

--- A barrier across a road, from x0 to x1 at y (or y0 to y1 at x with
--- `upright`), in 64 px sections, leaving `gap` px open at the `open` end.
local function barrierLine(map, a0, a1, at, upright, gap, open)
  if open == "start" then
    a0 = a0 + gap
  else
    a1 = a1 - gap
  end
  local a = a0
  while a < a1 - 8 do
    local len = math.min(64, a1 - a)
    if upright then
      cover(map, "barrier", at - 8, a, 16, len - 4)
    else
      cover(map, "barrier", a, at - 8, len - 4, 16)
    end
    a = a + 64
  end
end

-- The Drop ---------------------------------------------------------------------

-- Guard stations: block (i, j) lies between avenues i and i + 1 and streets
-- j and j + 1; `face` is the avenue side its yard opens on ("w" or "e").
CyberFeud.DROP_STATIONS = {
  { i = 3, j = 1, side = "halcyon", face = "w" }, -- over the middle avenue, by the tunnel
  { i = 4, j = 3, side = "halcyon", face = "w" },
  { i = 3, j = 5, side = "halcyon", face = "w" },
  { i = 1, j = 3, side = "static", face = "e" },
  { i = 2, j = 4, side = "static", face = "e" },
}
CyberFeud.NEST_ARC = math.rad(55) -- either side of where a station's nest faces, how far its gun turns
CyberFeud.GARRISON = 3 -- soldiers in a station house, for one human (more humans, more)
CyberFeud.GARRISON_REACH = 650 -- px from the house a player brings them out at

--- A faction's guard station over block tiles c0..c1, r0..r1 (its ring of
--- pavement included): buildings in the back half, and in the front half,
--- open on the avenue, a yard with the station house, an MG nest out in
--- front of it facing the avenue and cover either side of the nest.
--- Returns the station for `map.troops`: { nest, posts, garrison }.
local function guardStation(map, rng, g, st, c0, r0, c1, r1, neon)
  local T, X, Y = g.T, g.X, g.Y
  local half = math.floor((c1 - c0 + 1) / 2)
  local inner = c1 - c0 - half - 1 -- tiles of buildings across the back half
  local dir = st.face == "e" and 1 or -1 -- out of the yard, onto the avenue
  if dir < 0 then
    splitBlock(map, rng, g, c0 + half + 1, r0 + 1, inner, r1 - r0 - 1, neon)
  else
    splitBlock(map, rng, g, c0 + 1, r0 + 1, inner, r1 - r0 - 1, neon)
  end
  local fx = dir < 0 and X(c0) or X(c1 + 1) -- the yard's open edge
  local depth = half * T
  local my = Y((r0 + r1 + 1) / 2)
  local halcyon = st.side == "halcyon"
  local glow = halcyon and CyberFeud.MAGENTA or CyberFeud.CYAN
  -- The house, back in the yard, its door on the face towards the avenue.
  local hw, hh = 104, 136
  local hx = fx - dir * depth * 0.62
  local house = cover(map, "station", hx - hw / 2, my - hh / 2, hw, hh, true, { faction = st.side, face = dir })
  local door = { x = math.floor(hx + dir * hw / 2), y = math.floor(my), nx = dir, ny = 0 }
  house.door = door
  light(map, door.x + dir * 30, door.y, 150, glow, 0.8)
  -- The nest, a tile in from the avenue, and cover a little behind it either side.
  local angle = dir > 0 and 0 or math.pi
  local nest = { x = math.floor(fx - dir * T), y = math.floor(my), angle = angle, arc = CyberFeud.NEST_ARC }
  map.nests[#map.nests + 1] = { nest = nest, faction = st.side }
  light(map, nest.x, nest.y, 120, glow, 0.6)
  local posts = {}
  for _, k in ipairs({ -1, 1 }) do
    local cx, cy = fx - dir * 1.5 * T, my + k * 1.7 * T
    if halcyon then
      cover(map, "barrier", cx - 8, cy - 34, 16, 68)
    else
      cover(map, "wreck", cx - 20, cy - 38, 40, 76, true, { color = { 0.30, 0.22, 0.18 } })
      cover(map, "drum", cx - dir * 40 - 11, cy - 11, 22, 22, true, { round = true })
      light(map, cx - dir * 40, cy, 110, { 1.0, 0.55, 0.20 }, 0.6)
    end
    posts[#posts + 1] = { x = math.floor(cx - dir * 40), y = math.floor(cy + k * 10), watch = angle }
  end
  posts[#posts + 1] = { x = math.floor(door.x + dir * 34), y = math.floor(my + 60), watch = angle }
  return {
    side = st.side,
    nest = nest,
    posts = posts,
    garrison = { x = math.floor(hx), y = math.floor(my), reach = CyberFeud.GARRISON_REACH, door = door,
      count = CyberFeud.GARRISON },
  }
end

CyberFeud.DROP_AVENUES = { { 3, 5 }, { 16, 18 }, { 30, 33 }, { 45, 47 }, { 58, 60 } } -- columns, north-south
CyberFeud.DROP_STREETS = { -- rows, east-west; the last is the one past the garage
  { 6, 8 }, { 18, 20 }, { 30, 32 }, { 42, 44 }, { 54, 56 }, { 66, 68 }, { 78, 80 }, { 88, 90 },
}

local function buildDrop(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  map.nests = {}
  -- The crowd out late: dark coats, now and then a jacket in somebody's neon
  -- or a yellow raincoat.
  map.crowdClothes = {
    shirts = {
      { 0.16, 0.16, 0.19 }, { 0.22, 0.20, 0.24 }, { 0.28, 0.13, 0.18 }, { 0.12, 0.18, 0.24 },
      { 0.30, 0.30, 0.32 }, { 0.85, 0.22, 0.65 }, { 0.20, 0.72, 0.85 }, { 0.92, 0.82, 0.22 },
    },
    pants = { { 0.10, 0.10, 0.12 }, { 0.18, 0.18, 0.20 }, { 0.14, 0.12, 0.16 } },
  }
  local avenues, streets = CyberFeud.DROP_AVENUES, CyberFeud.DROP_STREETS
  local first, last = avenues[1][1], avenues[#avenues][2]
  local top, bottom = streets[1][1], streets[#streets][2]

  -- Streets and avenues: the avenues run from the top street down to the
  -- bottom one, the middle one on up through the tunnel to the edge.
  for _, a in ipairs(avenues) do
    g.fill(a[1], top, a[2], bottom, "road")
    road(map, X(a[1]), Y(top), (a[2] - a[1] + 1) * T, (bottom - top + 1) * T, "ns")
  end
  for _, s in ipairs(streets) do
    g.fill(first, s[1], last, s[2], "road")
    road(map, X(first), Y(s[1]), (last - first + 1) * T, (s[2] - s[1] + 1) * T, "ew")
  end
  local mid = avenues[3]
  g.fill(mid[1], 0, mid[2], top - 1, "road")
  road(map, X(mid[1]), Y(0), (mid[2] - mid[1] + 1) * T, top * T, "ns")
  -- The garage everyone comes up out of, off the bottom street.
  g.fill(first, bottom + 1, 14, bottom + 4, "road")

  -- Who holds the block: the Static the west third, Halcyon the east,
  -- either along the middle.
  local W = map.cols * T
  local function neon(x)
    local k = (x - map.x0) / W
    if k < 0.36 then
      return CyberFeud.CYAN
    elseif k > 0.64 then
      return CyberFeud.MAGENTA
    end
    return rng:random() < 0.5 and CyberFeud.CYAN or CyberFeud.MAGENTA
  end

  -- The blocks between them: a ring of pavement, buildings inside; a guard
  -- station's block (CyberFeud.DROP_STATIONS) only in its back half.
  local stationAt, stations = {}, {}
  for _, st in ipairs(CyberFeud.DROP_STATIONS) do
    stationAt[st.i .. "," .. st.j] = st
  end
  for i = 1, #avenues - 1 do
    for j = 1, #streets - 1 do
      local c0, c1 = avenues[i][2] + 1, avenues[i + 1][1] - 1
      local r0, r1 = streets[j][2] + 1, streets[j + 1][1] - 1
      g.fill(c0, r0, c1, r1, "walk")
      local st = stationAt[i .. "," .. j]
      if st then
        stations[#stations + 1] = guardStation(map, rng, g, st, c0, r0, c1, r1, neon)
      else
        splitBlock(map, rng, g, c0 + 1, r0 + 1, c1 - c0 - 1, r1 - r0 - 1, neon)
      end
    end
  end
  -- The pavement along the outer avenues and under the top street, and the
  -- buildings behind it: a wall of them all round.
  g.fill(first - 1, top, first - 1, bottom, "walk")
  g.fill(last + 1, top, last + 1, bottom, "walk")
  g.fill(first, top - 1, mid[1] - 1, top - 1, "walk")
  g.fill(mid[2] + 1, top - 1, last, top - 1, "walk")

  -- Street lamps along every avenue, white, a dim pool each.
  for _, a in ipairs(avenues) do
    for r = top + 4, bottom, 6 do
      light(map, X(a[1]) + 6, Y(r), 170, CyberFeud.WHITE, 0.35)
      light(map, X(a[2] + 1) - 6, Y(r + 3), 170, CyberFeud.WHITE, 0.35)
    end
  end

  -- The vending machine the Shard is in, on the pavement by the garage.
  local vx, vy = X(8), Y(streets[#streets - 1][2] + 7) + 20
  cover(map, "vending", vx - 14, vy - 18, 28, 36)
  map.pickupX, map.pickupY = vx, vy + 34
  light(map, vx, vy + 10, 160, CyberFeud.GREEN, 0.9)

  -- Halcyon's roadblocks, at crossings in the east and the middle, each
  -- leaving a gap to slip through, and the big one in front of the
  -- tunnel.
  local blocks = { { 4, 6, "end" }, { 4, 3, "start" }, { 3, 5, "start" }, { 3, 2, "end" }, { 2, 7, "end" } }
  for _, b in ipairs(blocks) do
    local a, s = avenues[b[1]], streets[b[2]]
    barrierLine(map, X(a[1]), X(a[2] + 1), Y(s[2] + 1) + 24, false, 110, b[3])
    light(map, X((a[1] + a[2] + 1) / 2), Y(s[2] + 1) + 24, 150, CyberFeud.MAGENTA, 0.8)
  end
  barrierLine(map, X(mid[1]), X(mid[2] + 1), Y(top) - 40, false, 120, "start")
  barrierLine(map, X(mid[1]), X(mid[2] + 1), Y(top - 3), false, 120, "end")
  light(map, X(mid[1] + 2), Y(top - 1), 240, CyberFeud.MAGENTA, 0.9)
  -- The Static's wrecks and burning drums in the west.
  for _ = 1, 14 do
    local a = avenues[rng:random(1, 2)]
    local r = rng:random(top + 3, bottom - 3)
    local x = X(a[1]) + 30 + rng:random() * ((a[2] - a[1] + 1) * T - 100)
    if rng:random() < 0.5 then
      cover(map, "wreck", x, Y(r), 40, 76, true, { color = { 0.30, 0.22, 0.18 } })
    else
      cover(map, "drum", x, Y(r), 22, 22, true, { round = true })
      light(map, x + 11, Y(r) + 11, 130, { 1.0, 0.55, 0.20 }, 0.7)
    end
  end

  -- Who holds the streets (cyber-feud/troops.lua puts them there): Halcyon's
  -- officers on every roadblock, watching back down the avenue, and squads
  -- on beats round the blocks in the east; the Static's gangers on corners
  -- in the west and packs walking round their blocks, two of them out
  -- through the middle into roadblocks. The last stretch before the tunnel
  -- (the Tunnel zone) is Halcyon's alone, so it is still standing when you
  -- get there: the big roadblock, a guard station, a squad, and the
  -- assassin droids walking the last crossings (`map.droids`,
  -- cyber-feud/droids.lua). No Static post or beat comes up past street 3.
  local function cross(i, j) -- the middle of avenue i's crossing with street j
    return { x = X((avenues[i][1] + avenues[i][2] + 1) / 2), y = Y((streets[j][1] + streets[j][2] + 1) / 2) }
  end
  local function loop(i0, i1, j0, j1)
    return { cross(i0, j0), cross(i1, j0), cross(i1, j1), cross(i0, j1) }
  end
  local halcyon, static = { posts = {}, patrols = {} }, { posts = {}, patrols = {} }
  for k, b in ipairs(blocks) do
    local a, s = avenues[b[1]], streets[b[2]]
    local w = (a[2] - a[1] + 1) * T
    for n = 1, 2 do
      halcyon.posts[#halcyon.posts + 1] = { x = X(a[1]) + w * n / 3, y = Y(s[2] + 1) - 36, watch = math.pi / 2, at = k }
    end
  end
  local mw = (mid[2] - mid[1] + 1) * T
  for n = 1, 3 do
    halcyon.posts[#halcyon.posts + 1] = {
      x = X(mid[1]) + mw * n / 4, y = Y(top) - 100, watch = math.pi / 2, at = #blocks + 1, hold = true,
    }
  end
  halcyon.patrols = { loop(4, 5, 2, 4), loop(4, 5, 5, 7), loop(3, 4, 1, 2), loop(3, 4, 6, 7) }
  for k, c in ipairs({ { 1, 3 }, { 2, 3 }, { 1, 4 }, { 2, 5 }, { 1, 6 } }) do
    local a, s = avenues[c[1]], streets[c[2]]
    static.posts[#static.posts + 1] = { x = X(a[2] + 1) - 30, y = Y(s[2] + 1) - 30, watch = math.pi / 2 + 0.5, at = k }
    static.posts[#static.posts + 1] = { x = X(a[1]) + 30, y = Y(s[1]) + 30, watch = -math.pi / 2 - 0.5, at = k }
  end
  static.patrols = { loop(1, 2, 3, 4), loop(1, 2, 4, 5), loop(1, 2, 5, 6), loop(2, 3, 4, 5), loop(2, 3, 6, 7) }
  halcyon.stations, static.stations = {}, {}
  for _, st in ipairs(stations) do
    local list = st.side == "halcyon" and halcyon.stations or static.stations
    list[#list + 1] = st
  end
  map.troops = { halcyon = halcyon, static = static }
  map.droids = { route = loop(2, 4, 1, 2) } -- round the last two crossings before the tunnel

  -- The tunnel mouth at the top, the way on.
  cover(map, "tunnel", X(mid[1]), Y(0), (mid[2] - mid[1] + 1) * T, 3 * T, false)
  map.exitX, map.exitY = math.floor(X(mid[1] + 2)), math.floor(Y(2.5))

  map.zones = {
    { name = "The Garage", y0 = Y(bottom - 12), y1 = Y(map.rows) },
    { name = "Downtown", y0 = Y(streets[3][1]), y1 = Y(bottom - 12) },
    { name = "The Tunnel", y0 = Y(0), y1 = Y(streets[3][1]) },
  }
  map.vexY = Y(48)

  -- Everyone comes up out of the garage, two rows of eight, facing north.
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = X(first + 0.6) + (i % 8) * 72, y = Y(bottom + 2) + math.floor(i / 8) * 100, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(14)), math.floor(Y(bottom + 3.5))
  commit(map, g)
end

-- The Market -------------------------------------------------------------------

local STALLS = {
  { 0.55, 0.20, 0.22 },
  { 0.20, 0.42, 0.40 },
  { 0.48, 0.40, 0.18 },
  { 0.30, 0.26, 0.45 },
  { 0.42, 0.44, 0.46 },
}

local function buildMarket(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local n = map.cols
  -- The hall: everything inside its walls open, the tunnel in at the
  -- bottom, the loading dock out at the top.
  g.fill(2, 2, n - 3, n - 3, "walk")
  g.fill(24, n - 2, 31, n - 1, "walk")
  g.fill(22, 0, 33, 1, "walk")

  -- Noodle Square in the middle, the chop shop on the west side.
  local sq = { c0 = 21, r0 = 20, c1 = 34, r1 = 33 }
  local shop = { c0 = 2, r0 = 18, c1 = 10, r1 = 33 }
  building(map, rng, g, shop.c0, shop.r0, shop.c1 - shop.c0 + 1, shop.r1 - shop.r0 + 1, CyberFeud.CYAN)
  light(map, X(shop.c1 + 1), Y(26), 220, CyberFeud.CYAN, 0.7)
  -- VEX's giant screen over the square's north side.
  cover(map, "screen", X(sq.c0 + 3), Y(sq.r0) - 20, 8 * T, 28)
  light(map, X(sq.c0 + 7), Y(sq.r0 + 2), 420, CyberFeud.GREEN, 0.8)

  -- Stalls in rows with lanes between, all over the hall but the square,
  -- the shop, the arrival and the dock.
  local function clear(c0, r0, c1, r1)
    if c1 >= sq.c0 - 1 and c0 <= sq.c1 + 1 and r1 >= sq.r0 - 1 and r0 <= sq.r1 + 1 then
      return false
    elseif c1 >= shop.c0 and c0 <= shop.c1 + 1 and r1 >= shop.r0 - 1 and r0 <= shop.r1 + 1 then
      return false
    end
    return r0 >= 4 and r1 <= n - 9
  end
  for c = 4, n - 7, 6 do
    for r = 4, n - 9, 5 do
      if clear(c, r, c + 3, r + 2) then
        local col = STALLS[rng:random(#STALLS)]
        cover(map, "stall", X(c), Y(r) + 8, 4 * T, 3 * T - 16, true, { color = col, seed = rng:random(1000) })
        local side = (c > n / 2) and CyberFeud.MAGENTA or (c < n / 3) and CyberFeud.CYAN or CyberFeud.LAMP
        light(map, X(c + 2), Y(r + 3) + 16, 150, side, 0.55)
      end
    end
  end
  -- Lanterns down the lanes.
  for c = 3, n - 4, 6 do
    for r = 6, n - 8, 10 do
      if g.at(c, r) and not (c >= sq.c0 and c <= sq.c1 and r >= sq.r0 and r <= sq.r1) then
        light(map, X(c) + 32, Y(r), 120, CyberFeud.LAMP, 0.45)
      end
    end
  end

  -- Halcyon's cordon across the south end and down the east side, with gaps.
  for c = 3, n - 5, 4 do
    if c % 8 ~= 3 then
      cover(map, "barrier", X(c), Y(n - 10) + 20, 3 * T - 8, 16)
    end
  end
  for r = 6, n - 12, 4 do
    if r % 8 ~= 6 then
      cover(map, "barrier", X(n - 9) + 24, Y(r), 16, 3 * T - 8)
    end
  end
  for r = 8, n - 12, 12 do
    light(map, X(n - 9) + 32, Y(r), 160, CyberFeud.MAGENTA, 0.6)
  end

  -- The dock: parked vans at the top, the way out between them.
  cover(map, "dock", X(22), Y(0), 12 * T, 2 * T, false)
  cover(map, "wreck", X(23), Y(2) + 10, 44, 84, true, { color = { 0.36, 0.38, 0.42 } })
  cover(map, "wreck", X(32) + 10, Y(2) + 10, 44, 84, true, { color = { 0.36, 0.38, 0.42 } })
  map.exitX, map.exitY = math.floor(X(28)), math.floor(Y(3))

  -- Who holds the hall (cyber-feud/troops.lua puts them there). Halcyon:
  -- enforcers in three gaps of the south cordon and officers behind them
  -- and in the rest, watching the tunnel, and
  -- behind the east line; a squad up and down the east strip and one round
  -- Noodle Square. The Static: their chop shop on the west side, gangers at
  -- its door and on the western corners, a garrison inside that comes out
  -- once a player is near, and packs walking the west lanes, one of them
  -- through the square, where they meet Halcyon's. Stall lanes run north to
  -- south at columns 8, 14, ... 44 (two wide) and east to west at rows 7,
  -- 12, ... 42; a lane's middle is X(c + 1) or Y(r + 1). Everyone is calm
  -- until a player walks past `wakeY`, out of the tunnel's mouth.
  local P = function(c, r)
    return { x = math.floor(X(c)), y = math.floor(Y(r)) }
  end
  local halcyon = { posts = {}, patrols = {} }
  local gates = { { 26.5, 27.5 }, { 15 }, { 21 }, { 39 }, { 45 }, { 51, 52.5 } }
  for k, gate in ipairs(gates) do
    for _, c in ipairs(gate) do
      halcyon.posts[#halcyon.posts + 1] = { x = math.floor(X(c)), y = math.floor(Y(44.2)), watch = math.pi / 2, at = k }
    end
  end
  for _, r in ipairs({ 12, 22, 32 }) do
    halcyon.posts[#halcyon.posts + 1] = { x = math.floor(X(51.5)), y = math.floor(Y(r)), watch = math.pi, at = r }
  end
  halcyon.patrols = {
    { P(45, 8), P(51.5, 8), P(51.5, 43), P(45, 43) }, -- the east strip
    { P(45, 18), P(21, 18), P(21, 38), P(45, 38) }, -- round the square
  }
  local static = { posts = {}, patrols = {}, stations = {} }
  for k, corner in ipairs({ { 9, 13 }, { 15, 38 } }) do
    local c, r = corner[1], corner[2]
    static.posts[#static.posts + 1] = { x = math.floor(X(c - 0.5)), y = math.floor(Y(r - 0.5)), watch = 0, at = k }
    static.posts[#static.posts + 1] = { x = math.floor(X(c + 0.5)), y = math.floor(Y(r + 0.4)), watch = 0.6, at = k }
  end
  static.patrols = {
    { P(3, 8), P(27, 8), P(27, 17.4), P(3, 17.4) }, -- the north-west lanes
    { P(13, 18), P(13, 38), P(33, 38), P(33, 18) }, -- out of the shop's front and through the square
    { P(3, 38), P(21, 38), P(21, 43), P(3, 43) }, -- the south-west lanes, up to the cordon
  }
  -- The chop shop's door, on its east face: no gun out front, just the gang.
  local door = { x = math.floor(X(shop.c1 + 1)), y = math.floor(Y(26)), nx = 1, ny = 0 }
  light(map, door.x + 30, door.y, 150, CyberFeud.CYAN, 0.8)
  static.stations[1] = {
    side = "static",
    posts = {
      { x = door.x + 60, y = door.y - 90, watch = 0 },
      { x = door.x + 60, y = door.y + 90, watch = 0 },
    },
    garrison = { x = door.x - 4 * T, y = door.y, reach = CyberFeud.GARRISON_REACH, door = door,
      count = CyberFeud.GARRISON },
  }
  map.troops = { halcyon = halcyon, static = static }
  -- Enforcers' riot shields fill three of the gates, in front of the officers.
  map.enforcers = {}
  for _, c in ipairs({ 27, 15, 45 }) do
    map.enforcers[#map.enforcers + 1] = { x = math.floor(X(c)), y = math.floor(Y(46.2)), watch = math.pi / 2 }
  end
  -- Rippers on the Static's beats: two through the square, two down the
  -- south-west lanes, and one round the north-west.
  map.rippers = {
    { route = static.patrols[2], start = 2 }, { route = static.patrols[2], start = 4 },
    { route = static.patrols[3], start = 2 }, { route = static.patrols[3], start = 4 },
    { route = static.patrols[1], start = 3 },
  }
  -- Two sparkers hanging back on the Static's beats: the square's and the north-west's.
  map.sparkers = { { route = static.patrols[2], start = 3 }, { route = static.patrols[1], start = 1 } }
  -- Halcyon's watcher drones fly the lanes (over a stall, rounds would
  -- stop at its wall before they reached one): the east strip, round the
  -- square and up the middle, and the lanes behind the south gate.
  map.watchers = {
    { route = { P(45, 8), P(51.5, 8), P(51.5, 43), P(45, 43) }, start = 1 },
    { route = { P(21, 13), P(39, 13), P(39, 33), P(21, 33) }, start = 3 },
    { route = { P(9, 38), P(33, 38), P(33, 43), P(9, 43) }, start = 2 },
  }
  map.wakeY = Y(n - 8)

  map.zones = {
    { name = "The South Gate", y0 = Y(n - 10), y1 = Y(n) },
    { name = "The Lanes", y0 = Y(sq.r1 + 1), y1 = Y(n - 10) },
    { name = "Noodle Square", y0 = Y(sq.r0), y1 = Y(sq.r1 + 1) },
    { name = "The Dock", y0 = Y(0), y1 = Y(sq.r0) },
  }
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = X(24.5) + (i % 8) * 56, y = Y(n - 6) + math.floor(i / 8) * 70, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(21.5)), math.floor(Y(n - 3.5))
  map.openKinds = { walk = true }
  commit(map, g)
end

-- The Overpass -----------------------------------------------------------------

CyberFeud.OVERPASS_ROAD = { 12, 19 } -- columns of the highway
CyberFeud.KNOT = { c0 = 21, r0 = 50, c1 = 30, r1 = 66 } -- the dead-end interchange off the ramp

local function buildOverpass(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local a, b = CyberFeud.OVERPASS_ROAD[1], CyberFeud.OVERPASS_ROAD[2]
  local rows = map.rows
  g.fill(a, 0, b, rows - 1, "road")
  road(map, X(a), Y(0), (b - a + 1) * T, rows * T, "ns")

  -- The off-ramp: out to the right at row 94, up to the Knot, and back onto
  -- the highway above it at row 46.
  local k = CyberFeud.KNOT
  g.fill(b + 1, 94, k.c0 + 2, 97, "road")
  g.fill(k.c0, k.r1, k.c0 + 2, 97, "road")
  g.fill(k.c0, k.r0, k.c1, k.r1, "road")
  g.fill(b + 1, 46, k.c0 + 2, 49, "road")
  g.fill(k.c0, 46, k.c0 + 2, k.r0, "road")
  road(map, X(k.c0), Y(46), 3 * T, (97 - 46 + 1) * T, "ns")
  road(map, X(k.c0), Y(k.r0), (k.c1 - k.c0 + 1) * T, (k.r1 - k.r0 + 1) * T, "pad")
  map.knot = { x = X(k.c0), y = Y(k.r0), w = (k.c1 - k.c0 + 1) * T, h = (k.r1 - k.r0 + 1) * T }
  light(map, X((k.c0 + k.c1 + 1) / 2), Y((k.r0 + k.r1 + 1) / 2), 380, CyberFeud.MAGENTA, 0.35)
  light(map, X((k.c0 + k.c1 + 1) / 2), Y((k.r0 + k.r1 + 1) / 2) + 120, 300, CyberFeud.CYAN, 0.35)
  light(map, X(b + 2), Y(95), 220, CyberFeud.GREEN, 0.7) -- VEX's sign: SHORTCUT

  -- Gantries over the road every 30 rows, lamps on each.
  for r = 20, rows - 20, 30 do
    cover(map, "gantry", X(a - 1), Y(r), (b - a + 3) * T, 24, false)
    light(map, X(a) + 40, Y(r) + 12, 200, CyberFeud.WHITE, 0.45)
    light(map, X(b + 1) - 40, Y(r) + 12, 200, CyberFeud.WHITE, 0.45)
  end
  -- Lamps down the middle between them.
  for r = 5, rows - 5, 10 do
    light(map, X((a + b + 1) / 2), Y(r), 210, CyberFeud.LAMP, 0.3)
  end

  -- Roadworks squeeze it down past the ramp: a line of barriers down one
  -- lane, then the other.
  for r = 58, 88, 2 do
    local x = (r < 74) and X(a + 2) or X(b - 1)
    cover(map, "barrier", x, Y(r), 16, 2 * T - 10)
  end
  -- Stalled traffic and wrecks to weave round.
  for _ = 1, 22 do
    local r = rng:random(8, rows - 18)
    if r < 56 or r > 90 then
      local lane = rng:random(0, 3)
      local x = X(a) + 30 + lane * 2 * T
      cover(map, "wreck", x, Y(r), 40, 76, true, { color = ROOFS[rng:random(#ROOFS)] })
    end
  end

  -- The city far below, either side: just lights.
  map.below = {}
  local palette = { CyberFeud.CYAN, CyberFeud.MAGENTA, CyberFeud.LAMP, CyberFeud.WHITE, CyberFeud.LAMP }
  for _ = 1, 900 do
    local c = rng:random() * map.cols
    local cc = math.floor(c)
    if cc < a - 1 or cc > b + 1 then
      local r = rng:random() * rows
      if not g.at(cc, math.floor(r)) then
        map.below[#map.below + 1] = {
          x = X(c), y = Y(r), r = 1.5 + rng:random() * 2.5, color = palette[rng:random(#palette)],
        }
      end
    end
  end

  -- Who is waiting on the road (cyber-feud/troops.lua puts them there).
  -- The Static: gangers in pairs on the shoulders of the long stretch,
  -- watching back down the road for you. Halcyon: a checkpoint where the
  -- road forks for the ramp, posts along the roadworks, and the last
  -- roadblock across the tower ramp with a squad on the stretch below it.
  -- And the Knot, VEX's "shortcut": both of them waiting there together,
  -- Halcyon along its north and east edges, the Static along its south
  -- edge over the ramp in and a pack walking the pad.
  local P = function(c, r)
    return { x = math.floor(X(c)), y = math.floor(Y(r)) }
  end
  local function post(list, c, r, watch, at)
    list[#list + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), watch = watch, at = at }
  end
  local south, north, west = math.pi / 2, -math.pi / 2, math.pi
  local halcyon, static = { posts = {} }, { posts = {} }
  for _, r in ipairs({ 172, 146, 120 }) do
    post(static.posts, a + 0.5, r, south, "shoulder" .. r)
    post(static.posts, b + 0.5, r + 1, south, "shoulder" .. r)
  end
  post(halcyon.posts, (a + b + 1) / 2 - 0.6, 100, south, "fork")
  post(halcyon.posts, (a + b + 1) / 2 + 0.6, 100, south, "fork")
  post(halcyon.posts, a + 1, 76, south, "works")
  post(halcyon.posts, b, 62, south, "works")
  for c = a + 0.5, b + 0.5, 2 do
    post(halcyon.posts, c, 9, south, "ramp")
  end
  halcyon.patrols = { { P(a + 1, 14), P(b, 14), P(b, 40), P(a + 1, 40) } }
  for _, c in ipairs({ k.c0 + 2, k.c0 + 5, k.c1 - 0.5 }) do
    post(halcyon.posts, c, k.r0 + 1, south, "knot north")
  end
  for _, r in ipairs({ k.r0 + 6, k.r0 + 11 }) do
    post(halcyon.posts, k.c1 + 0.5, r, west, "knot east")
  end
  for _, c in ipairs({ k.c0 + 3.5, k.c0 + 6, k.c1 - 0.5 }) do
    post(static.posts, c, k.r1, north, "knot south")
  end
  static.patrols = { { P(k.c0 + 3, k.r0 + 3), P(k.c1 - 1, k.r0 + 3), P(k.c1 - 1, k.r1 - 3), P(k.c0 + 3, k.r1 - 3) } }
  map.troops = { halcyon = halcyon, static = static }
  -- Halcyon's interceptors, parked on the shoulder facing up the road, to
  -- pull out after whoever drives past (cyber-feud/interceptors.lua). In
  -- the order they are used: the first few spread over the whole run, more
  -- with more players.
  map.interceptors = {}
  for _, p in ipairs({ { b + 0.4, 160 }, { a + 0.6, 108 }, { b + 0.4, 36 }, { a + 0.6, 134 }, { b + 0.4, 92 } }) do
    map.interceptors[#map.interceptors + 1] = { x = math.floor(X(p[1])), y = math.floor(Y(p[2])), angle = north }
  end

  -- Halcyon's roadblocks (cyber-feud/gates.lua): blast gates right across
  -- the road, solid until somebody on foot works the panel on the shoulder
  -- short of them, guarded from behind by a few officers. The one at the
  -- roadworks the Knot gets round (VEX's shortcut does have its upside);
  -- the others it doesn't.
  map.gates = {}
  for _, gt in ipairs({ { "the long stretch", 132, b }, { "the roadworks", 70, a }, { "the tower ramp", 26, b } }) do
    local gy = Y(gt[2])
    local s = { x = X(a), y = gy - 12, w = (b - a + 1) * T, h = 24 }
    map.solids[#map.solids + 1] = s
    local px = gt[3] == a and X(a) + 26 or X(b + 1) - 26
    map.gates[#map.gates + 1] = { name = gt[1], solid = s, frame = { x = s.x, y = s.y, w = s.w, h = s.h },
      panel = { x = math.floor(px), y = math.floor(gy + 110) } }
    for _, c in ipairs({ a + 1.5, (a + b + 1) / 2, b - 0.5 }) do
      post(halcyon.posts, c, gt[2] - 2, south, "gate " .. gt[2])
    end
  end

  -- Car stations (the car-stations feature): pads on the shoulder about
  -- every thirty rows, clear of the posts, where anyone on foot calls their
  -- Courier back whole. They are the map's respawn points too
  -- (respawn-points), so a wreck doesn't send you back to the on-ramp.
  map.carStations = {}
  for _, st in ipairs({
    { "the long stretch", a, 158 }, { "the overhead signs", b, 128 }, { "the off-ramp", a, 96 },
    { "the roadworks", a, 66 }, { "the tower ramp", a, 38 },
  }) do
    local x = st[2] == a and X(a) + 52 or X(b + 1) - 52
    map.carStations[#map.carStations + 1] = { name = st[1], x = math.floor(x), y = math.floor(Y(st[3])), angle = north }
    light(map, x, Y(st[3]), 140, CyberFeud.GREEN, 0.7) -- lit at night
  end

  -- Halcyon's marksmen on the gantries' catwalks, an end each, looking back
  -- down the road (cyber-feud/marksmen.lua), in the order they are used.
  map.marksmen = {}
  for _, p in ipairs({ { b + 0.7, 140 }, { a + 0.3, 80 }, { b + 0.7, 20 }, { a + 0.3, 110 }, { b + 0.7, 50 } }) do
    map.marksmen[#map.marksmen + 1] = { x = math.floor(X(p[1])), y = math.floor(Y(p[2]) + 12), watch = south }
  end
  -- Halcyon's sting drone swarms, each over a gantry (cyber-feud/stings.lua),
  -- in the order they are used.
  map.stings = {}
  for _, r in ipairs({ 140, 80, 20, 110, 50 }) do
    map.stings[#map.stings + 1] = { x = math.floor(X((a + b + 1) / 2)), y = math.floor(Y(r)) }
  end
  -- The Static's war-rigs, parked on the shoulder between the interceptors
  -- (cyber-feud/war_rigs.lua), in the order they are used.
  map.rigs = {}
  for _, p in ipairs({ { a + 0.6, 176 }, { b + 0.4, 120 }, { a + 0.6, 60 }, { b + 0.4, 148 } }) do
    map.rigs[#map.rigs + 1] = { x = math.floor(X(p[1])), y = math.floor(Y(p[2])), angle = north }
  end
  -- Kilowatt's ride: up the right-hand edge of the road from behind
  -- everyone (clear of the spawns' lanes), once someone drives past
  -- `startY` or a moment after arriving; he jumps off the east edge.
  map.kilowatt = { x = math.floor(X(b + 0.6)), y = math.floor(Y(rows - 0.6)), startY = Y(rows - 10), exitAngle = 0 }

  -- Halcyon Tower's garage ramp at the top.
  cover(map, "tunnel", X(a), Y(0), (b - a + 1) * T, 2 * T, false)
  light(map, X((a + b + 1) / 2), Y(2), 300, CyberFeud.MAGENTA, 0.7)
  map.exitX, map.exitY = math.floor(X((a + b + 1) / 2)), math.floor(Y(3))

  map.zones = {
    { name = "The On-Ramp", y0 = Y(rows - 30), y1 = Y(rows) },
    { name = "The Overpass", y0 = Y(98), y1 = Y(rows - 30) },
    { name = "The Roadworks", y0 = Y(46), y1 = Y(98) },
    { name = "The Tower Ramp", y0 = Y(0), y1 = Y(46) },
  }
  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = X(a) + 64 + (i % 4) * 2 * T, y = Y(rows - 4) - math.floor(i / 4) * 110, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X((a + b + 1) / 2)), math.floor(Y(rows - 1.5))
  commit(map, g)
end

-- Halcyon Tower ----------------------------------------------------------------

CyberFeud.FLOORS = { "Lobby", "Offices", "Servers", "Labs", "Security", "Executive" }
CyberFeud.FLOOR_ROWS = 16 -- open rows on each floor; two rows of slab between floors

local function buildTower(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local cols, rows = map.cols, map.rows
  local H = CyberFeud.FLOOR_ROWS
  map.floors = {}
  local floors = {}
  for i = 0, #CyberFeud.FLOORS - 1 do
    local r1 = rows - 3 - i * (H + 2)
    local f = { name = CyberFeud.FLOORS[i + 1], c0 = 2, c1 = cols - 3, r0 = r1 - H + 1, r1 = r1 }
    floors[#floors + 1] = f
    g.fill(f.c0, f.r0, f.c1, f.r1, "walk")
    map.floors[#map.floors + 1] = { name = f.name, y0 = Y(f.r0), y1 = Y(f.r1 + 1) }
    -- Office light, a pool every few tiles along the floor.
    for c = f.c0 + 3, f.c1, 8 do
      light(map, X(c), Y(f.r0 + 4), 210, CyberFeud.WHITE, 0.25)
      light(map, X(c + 4), Y(f.r1 - 3), 210, CyberFeud.WHITE, 0.25)
    end
  end
  map.zones = map.floors
  -- The way in through the bottom, and a stairwell up from each floor to
  -- the next, at alternating ends, the climb zigzagging up.
  g.fill(21, rows - 2, 26, rows - 1, "walk")
  for i = 1, #floors - 1 do
    local f = floors[i]
    local c0 = (i % 2 == 1) and f.c1 - 4 or f.c0 + 1
    g.fill(c0, f.r0 - 2, c0 + 3, f.r0 - 1, "walk")
    cover(map, "door", X(c0), Y(f.r0 - 2) + 40, 4 * T, 48, false)
    light(map, X(c0 + 2), Y(f.r0 - 1), 160, CyberFeud.GREEN, 0.7)
  end

  -- What stands on each floor.
  local function avoidStairs(f, c0, c1)
    return c1 < f.c0 + 7 or c0 > f.c1 - 7
  end
  -- The lobby: reception, the lifts, planters.
  local f = floors[1]
  cover(map, "reception", X(18), Y(f.r0 + 6), 12 * T, 48)
  cover(map, "lift", X(6), Y(f.r0), 3 * T, 3 * T)
  cover(map, "lift", X(cols - 9), Y(f.r0), 3 * T, 3 * T)
  for _, c in ipairs({ 8, 14, cols - 14, cols - 8 }) do -- either side of the doors, clear of the arrival
    cover(map, "planter", X(c), Y(f.r1 - 3), 48, 48)
  end
  -- Offices: rows of desks.
  f = floors[2]
  for c = f.c0 + 8, f.c1 - 9, 4 do
    for r = f.r0 + 2, f.r1 - 2, 3 do
      cover(map, "desk", X(c), Y(r), 2 * T, 40)
    end
  end
  -- Servers: long racks.
  f = floors[3]
  for c = f.c0 + 8, f.c1 - 12, 6 do
    for r = f.r0 + 2, f.r1 - 3, 4 do
      cover(map, "rack", X(c), Y(r), 4 * T, 36)
      light(map, X(c + 2), Y(r) + 18, 90, rng:random() < 0.5 and CyberFeud.GREEN or CyberFeud.CYAN, 0.4)
    end
  end
  -- Labs: tanks of spare bodies.
  f = floors[4]
  for c = f.c0 + 8, f.c1 - 9, 5 do
    for r = f.r0 + 3, f.r1 - 3, 5 do
      cover(map, "tank", X(c), Y(r), 80, 80, true, { round = true })
      light(map, X(c) + 40, Y(r) + 40, 130, CyberFeud.MAGENTA, 0.6)
    end
  end
  -- Security: barricades at angles across the floor.
  f = floors[5]
  for _ = 1, 16 do
    local c = rng:random(f.c0 + 8, f.c1 - 10)
    local r = rng:random(f.r0 + 2, f.r1 - 2)
    if not avoidStairs(f, c, c + 2) then
      if rng:random() < 0.5 then
        cover(map, "barrier", X(c), Y(r), 2 * T, 16)
      else
        cover(map, "barrier", X(c), Y(r), 16, 2 * T)
      end
    end
  end
  -- Executive: the long boardroom table, Saye's desk, the lift up.
  f = floors[6]
  cover(map, "table", X(16), Y(f.r0 + 7), 16 * T, 2 * T)
  cover(map, "desk", X(22), Y(f.r0 + 2), 4 * T, 48)
  cover(map, "lift", X(22), Y(f.r0 - 2), 4 * T, 2 * T, false)
  light(map, X(24), Y(f.r0 + 1), 260, CyberFeud.MAGENTA, 0.6)
  map.exitX, map.exitY = math.floor(X(24)), math.floor(Y(f.r0 + 1))

  -- Who is in the tower (cyber-feud/troops.lua puts them there). Halcyon
  -- holds every floor: a pair on the stair door up (at the far end from
  -- where you come in, so the climb is a walk across each floor past
  -- them), a few more posts, and a squad walking a beat round the floor's
  -- middle (no squad in the lobby: they hold the lifts). The Static aren't
  -- in yet: they break in from below (`breakIns`), a pack at a time up the
  -- stairwell onto the lowest floor anyone is on, and walk that floor's
  -- beat after them.
  local south, west, east = math.pi / 2, math.pi, 0
  local function P(c, r)
    return { x = math.floor(X(c)), y = math.floor(Y(r)) }
  end
  local halcyon = { posts = {}, patrols = {} }
  local function post(c, r, watch, at)
    halcyon.posts[#halcyon.posts + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), watch = watch, at = at }
  end
  -- Each floor's beat: a loop round what stands in the middle, on the rows
  -- and columns it leaves clear.
  local beats = {
    { { 11, 103.5 }, { 36, 103.5 }, { 36, 108 }, { 11, 108 } }, -- the lobby, round the reception and planters
    { { 8.5, 77.2 }, { 38.5, 77.2 }, { 38.5, 90.3 }, { 8.5, 90.3 } }, -- the offices, round the desks
    { { 8.5, 62.3 }, { 34, 62.3 }, { 34, 70.6 }, { 8.5, 70.6 } }, -- the servers, down the racks' aisles
    { { 8.5, 41.5 }, { 38, 41.5 }, { 38, 52 }, { 8.5, 52 } }, -- the labs, round the tanks
    { { 5, 23 }, { 40, 23 }, { 40, 37.4 }, { 9, 37.4 } }, -- security, round the barricades (where they fall)
    { { 13, 9 }, { 35, 9 }, { 35, 15 }, { 13, 15 } }, -- the executive floor, round the boardroom table
  }
  for i, beat in ipairs(beats) do
    for k, p in ipairs(beat) do
      beat[k] = P(p[1], p[2])
    end
    if i > 1 then
      halcyon.patrols[#halcyon.patrols + 1] = beat
    end
  end
  halcyon.patrols[#halcyon.patrols + 1] = beats[5] -- the guard floor: two squads on its beat
  -- The stair doors up, the pair on each.
  for i = 1, #floors - 1 do
    local fl = floors[i]
    local c0 = (i % 2 == 1) and fl.c1 - 4 or fl.c0 + 1
    post(c0 + 0.6, fl.r0 + 1.6, south, "stairs " .. i)
    post(c0 + 3.4, fl.r0 + 1.6, south, "stairs " .. i)
  end
  -- The lobby's lifts, watching over the reception to the doors.
  local lobby = floors[1]
  for _, c in ipairs({ 6.5, 8.5 }) do
    post(c, lobby.r0 + 3.6, south, "lifts west")
  end
  for _, c in ipairs({ cols - 9.5, cols - 7.5 }) do
    post(c, lobby.r0 + 3.6, south, "lifts east")
  end
  -- A few more, floor by floor, watching across where you have to go.
  post(cols - 4, floors[2].r0 + 4, west, "offices east")
  post(cols - 10, floors[3].r0 + 8, west, "racks east")
  post(23, floors[4].r0 + 6.5, east, "tanks")
  post(23, floors[5].r0 + 8.5, south, "checkpoint")
  post(14, floors[5].r0 + 4, east, "checkpoint")
  post(cols - 8, floors[5].r0 + 12, west, "security east")
  post(14.5, floors[6].r0 + 8, south, "boardroom")
  post(33.5, floors[6].r0 + 8, south, "boardroom")
  post(20.6, floors[6].r0 + 1.5, south, "saye's office")
  post(27.4, floors[6].r0 + 1.5, south, "saye's office")
  map.troops = { halcyon = halcyon, static = { posts = {} } }
  -- Where the Static come in to each floor: the lobby's front doors, and
  -- above it the top of the stairwell from the floor below.
  map.breakIns = {}
  for i, fl in ipairs(floors) do
    local x, y
    if i == 1 then
      x, y = X(24), Y(rows - 1.5)
    else
      local c0 = ((i - 1) % 2 == 1) and floors[i - 1].c1 - 4 or floors[i - 1].c0 + 1
      x, y = X(c0 + 2), Y(fl.r1 + 1.5)
    end
    map.breakIns[i] = { x = math.floor(x), y = math.floor(y), beat = beats[i] }
  end
  -- Nobody is looking until somebody is past the reception: not a shot at the doors.
  map.wakeY = math.floor(Y(lobby.r1 - 5))

  for i = 0, 15 do
    map.spawns[#map.spawns + 1] = {
      x = X(19) + (i % 8) * 80, y = Y(rows - 6) + math.floor(i / 8) * 80, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(20)), math.floor(Y(rows - 2.75))
  map.openKinds = { walk = true }
  commit(map, g)
end

-- The Roof -----------------------------------------------------------------------

local function buildRoof(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local n = map.cols
  g.fill(2, 2, n - 3, n - 3, "walk")
  g.fill(15, n - 2, 20, n - 1, "walk") -- the stairs up
  local mid = n / 2
  map.helipad = { x = X(mid), y = Y(mid), r = 3 * T }
  light(map, X(mid), Y(mid), 300, CyberFeud.WHITE, 0.3)
  -- The relays near the corners.
  for _, p in ipairs({ { 6, 6 }, { n - 7, 6 }, { 6, n - 8 }, { n - 7, n - 8 } }) do
    cover(map, "relay", X(p[1]), Y(p[2]), T, T)
    light(map, X(p[1] + 0.5), Y(p[2] + 0.5), 160, CyberFeud.GREEN, 0.8)
  end
  -- AC units and vents, antenna masts.
  for _ = 1, 10 do
    local c, r = rng:random(4, n - 7), rng:random(4, n - 10)
    if (c - mid) ^ 2 + (r - mid) ^ 2 > 25 then
      cover(map, "ac", X(c), Y(r), (rng:random() < 0.5 and 2 or 1) * T, T)
    end
  end
  for _, p in ipairs({ { 11, 4 }, { n - 12, 4 }, { 4, mid }, { n - 5, mid } }) do
    cover(map, "mast", X(p[1]) + 16, Y(p[2]) + 16, 32, 32)
    light(map, X(p[1]) + 32, Y(p[2]) + 32, 70, { 1, 0.2, 0.2 }, 0.9)
  end
  -- VEX's billboard along the north edge.
  cover(map, "billboard", X(6), Y(0) + 24, (n - 12) * T, 64, false)
  light(map, X(mid), Y(2), 520, CyberFeud.GREEN, 0.6)
  map.exitX, map.exitY = math.floor(X(mid)), math.floor(Y(mid))

  map.zones = { { name = "The Roof", y0 = Y(0), y1 = Y(n) } }
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = X(14) + (i % 6) * 80, y = Y(n - 6) + math.floor(i / 6) * 80, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(14.5)), math.floor(Y(n - 2.5))
  map.openKinds = { walk = true }
  commit(map, g)
end

CyberFeud.builders = {
  drop = buildDrop,
  market = buildMarket,
  overpass = buildOverpass,
  tower = buildTower,
  roof = buildRoof,
}

--- Does `kind` name one of these maps?
function CyberFeud.builds(kind)
  return CyberFeud.builders[kind] ~= nil
end

--- Build map `map.kind` into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function CyberFeud.build(map, rng, T)
  CyberFeud.builders[map.kind](map, rng, T)
end

return CyberFeud
