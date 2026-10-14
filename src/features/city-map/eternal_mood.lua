-- The maps of the Eternal Mood quest line (docs/eternal-mood.md), one builder
-- each, all in the dark (the spec's `night`, the night feature). So far:
--   fobos     Fobos Base: the UAC's moon base cut through, walked from the Lab
--             at the bottom, round the Ring and up through the Offices, the
--             Reactor or Toxic Storage to the Hangar's lift at the top
-- Everyone travels north (up the screen), the way both quest lines before
-- it do.
--
-- Tiles are "walk" (the base's floors); nil is wall inside the base
-- (`map.base`) and the moon outside it, and the layout's walls make both
-- solid.
--
-- What every one leaves on the map, besides tiles, solids and spawns:
--   map.cx, map.cy        the way home (a HOME star in quests), by the arrival
--   map.exitX, map.exitY  the way on: the first player there finishes the level (eternal-mood)
--   map.base              { x, y, w, h } the base's walls, world px: nil tiles inside are wall, outside moon
--   map.zones             { name, x0, y0, x1, y1, floor } the rooms and corridors, world px; `floor`
--                         is the finish render_eternal_mood.lua lays there
--   map.cover             { kind, x, y, w, h, solid, round, flat, color, text } world px; solid ones are
--                         in the solids too, `flat` ones (a lift pad, sludge, paint) are drawn first.
--                         Kinds: slab, tank, portal, console, desk, chair, cabinet, cooler, reactor, pipe,
--                         barrel, sludge, crane, crate, loader, lift, bunk, table, counter, lockers,
--                         catwalk, paint, stripe, vent
--   map.signs             { x, y, w, h, text } posters and signs on the walls, world px
--   map.lights            { x, y, r, color, a } what glows in the dark (the night feature draws them), world px
--   map.alarms            { x, y } the red alarm lamps over the doors, world px
--   map.horde             { posts = { rank, x, y, watch }, vents = { x, y, out, count } } Heck's horde
--                         (eternal-mood/horde.lua): the possessed at their posts (rank staffer, guard or
--                         overtime) and the vents the imps crawl out of, world px; and `boss` { x, y, facing,
--                         zone, lift, doors } the level's boss (the Floor Manager): where he waits, the room
--                         that wakes him, the lift he keeps out of service, the doorways his meetings use
--   map.openKinds         { walk = true }: pickups and the like go on the floor

local EternalMood = {}

-- Light, by what gives it. Everything in this universe is evil, so nearly
-- all of it is red: only the toxic sludge glows another colour, sick green.
EternalMood.STRIP = { 1.00, 0.42, 0.30 } -- the base's strip lights, burning red-orange
EternalMood.SCREEN = { 1.00, 0.30, 0.12 } -- the computer screens, red text on black
EternalMood.CORE = { 1.00, 0.50, 0.15 } -- the reactor, running on something from Heck
EternalMood.SLUDGE = { 0.55, 1.00, 0.20 } -- toxic sludge
EternalMood.ALARM = { 1.00, 0.10, 0.06 } -- the alarms
EternalMood.LAMP = { 1.00, 0.62, 0.40 } -- desk lamps, the mess

-- The posters on the walls (docs/eternal-mood.md, "Shared look").
EternalMood.POSTERS = {
  "UAC: WE OPENED IT SO YOU DON'T HAVE TO",
  "PORTAL SAFETY WEEK: 0 DAYS SINCE LAST INCIDENT",
  "DEMON PARKING ONLY",
  "HAVE YOU TRIED TURNING IT OFF AND ON AGAIN?",
  "WASH YOUR HANDS. THEN WASH THEM AGAIN.",
  "OVERTIME IS ITS OWN REWARD",
}

-- Building blocks ------------------------------------------------------------

--- The grid a builder works on: `kind[c][r]` for the tiles, and the helpers
--- to fill it and to put things on the map in tile units.
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
  map.cover, map.zones, map.signs, map.lights, map.alarms = {}, {}, {}, {}, {}
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

--- A poster on the wall over (x, y), the top of the floor below it: on
--- the wall tile itself, so it never covers the floor.
local POSTER_W, POSTER_H = 5 * 64, 58
local function poster(map, x, y, text)
  map.signs[#map.signs + 1] = { x = x, y = y - POSTER_H - 4, w = POSTER_W, h = POSTER_H, text = text }
end

--- Something flat on the floor, walked over.
local function flat(map, kind, x, y, w, h, extra)
  local s = cover(map, kind, x, y, w, h, false, extra)
  s.flat = true
  return s
end

-- Fobos Base -------------------------------------------------------------------

-- The rooms and corridors, in tiles (inclusive), bottom to top, each with
-- the finish its floor gets. The Lab is the way in, the Hangar the way out;
-- the Ring joins the bottom rooms to the three in the middle, and each of
-- those has its own way up into the Hangar.
EternalMood.FOBOS = {
  { name = "The Lab", c0 = 18, r0 = 56, c1 = 37, r1 = 74, floor = "lab" },
  { name = "Crew Quarters", c0 = 4, r0 = 56, c1 = 14, r1 = 68, floor = "carpet" },
  { name = "The Mess", c0 = 41, r0 = 56, c1 = 51, r1 = 68, floor = "lino" },
  { name = "The Ring", c0 = 4, r0 = 49, c1 = 51, r1 = 51, floor = "plate" },
  { name = "The Offices", c0 = 4, r0 = 26, c1 = 16, r1 = 45, floor = "carpet" },
  { name = "The Reactor", c0 = 20, r0 = 26, c1 = 35, r1 = 45, floor = "grate" },
  { name = "Toxic Storage", c0 = 39, r0 = 26, c1 = 51, r1 = 45, floor = "concrete" },
  { name = "The Hangar", c0 = 6, r0 = 4, c1 = 49, r1 = 19, floor = "hangar" },
}

-- The doorways and short corridors between them, in tiles (inclusive): each
-- a gap in the wall, an alarm over it and hazard stripes across it. `ns`
-- runs north-south (the stripes go across it east-west).
EternalMood.FOBOS_DOORS = {
  { c0 = 26, r0 = 52, c1 = 29, r1 = 55, ns = true }, -- the Lab up to the Ring
  { c0 = 8, r0 = 52, c1 = 10, r1 = 55, ns = true }, -- Crew Quarters
  { c0 = 45, r0 = 52, c1 = 47, r1 = 55, ns = true }, -- the Mess
  { c0 = 9, r0 = 46, c1 = 11, r1 = 48, ns = true }, -- the Ring up into the Offices
  { c0 = 26, r0 = 46, c1 = 29, r1 = 48, ns = true }, -- the Reactor
  { c0 = 44, r0 = 46, c1 = 46, r1 = 48, ns = true }, -- Toxic Storage
  { c0 = 17, r0 = 30, c1 = 19, r1 = 32 }, -- the Offices through to the Reactor
  { c0 = 36, r0 = 38, c1 = 38, r1 = 40 }, -- the Reactor through to Toxic Storage
  { c0 = 9, r0 = 20, c1 = 11, r1 = 25, ns = true }, -- the Offices up into the Hangar
  { c0 = 26, r0 = 20, c1 = 29, r1 = 25, ns = true }, -- the Reactor
  { c0 = 44, r0 = 20, c1 = 46, r1 = 25, ns = true }, -- Toxic Storage
}

local function buildFobos(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local cols, rows = map.cols, map.rows
  map.base = { x = X(2), y = Y(2), w = (cols - 4) * T, h = (rows - 4) * T }
  local rooms = {}
  for _, z in ipairs(EternalMood.FOBOS) do
    g.fill(z.c0, z.r0, z.c1, z.r1, "walk")
    rooms[z.name] = z
    map.zones[#map.zones + 1] = {
      name = z.name, x0 = X(z.c0), y0 = Y(z.r0), x1 = X(z.c1 + 1), y1 = Y(z.r1 + 1), floor = z.floor,
    }
    -- Blue strip lights down the room, a pool every few tiles.
    for c = z.c0 + 2, z.c1, 6 do
      for r = z.r0 + 2, z.r1, 6 do
        light(map, X(c), Y(r), 190, EternalMood.STRIP, 0.3)
      end
    end
  end
  for _, d in ipairs(EternalMood.FOBOS_DOORS) do
    g.fill(d.c0, d.r0, d.c1, d.r1, "walk")
    local x0, y0, x1, y1 = X(d.c0), Y(d.r0), X(d.c1 + 1), Y(d.r1 + 1)
    if d.ns then
      flat(map, "stripe", x0, y0 + 8, x1 - x0, 24)
      flat(map, "stripe", x0, y1 - 32, x1 - x0, 24)
      map.alarms[#map.alarms + 1] = { x = math.floor((x0 + x1) / 2), y = y0 }
    else
      flat(map, "stripe", x0 + 8, y0, 24, y1 - y0, { across = true })
      flat(map, "stripe", x1 - 32, y0, 24, y1 - y0, { across = true })
      map.alarms[#map.alarms + 1] = { x = x0, y = math.floor((y0 + y1) / 2) }
    end
  end
  for _, a in ipairs(map.alarms) do
    light(map, a.x, a.y, 150, EternalMood.ALARM, 0.6)
  end

  -- The Lab: slabs in two rows where everyone wakes, tanks down the east
  -- wall, consoles along the south, and the portal ring that started it,
  -- smashed, in the west.
  local z = rooms["The Lab"]
  for i = 0, 5 do
    for j = 0, 1 do
      cover(map, "slab", X(z.c0 + 6 + i * 2) + 8, Y(z.r0 + 9 + j * 4), 48, 96)
    end
  end
  for r = z.r0 + 2, z.r1 - 3, 3 do
    cover(map, "tank", X(z.c1 - 1) - 8, Y(r), 72, 72, true, { round = true })
    light(map, X(z.c1 - 1) + 28, Y(r) + 36, 110, EternalMood.SCREEN, 0.5)
  end
  for c = z.c0 + 2, z.c1 - 4, 3 do
    cover(map, "console", X(c), Y(z.r1) + 24, 2 * T - 16, 40)
    light(map, X(c + 1), Y(z.r1), 90, EternalMood.SCREEN, 0.6)
  end
  flat(map, "portal", X(z.c0 + 1), Y(z.r0 + 1), 4 * T, 4 * T)
  light(map, X(z.c0 + 3), Y(z.r0 + 3), 220, EternalMood.ALARM, 0.5)
  poster(map, X(z.c0 + 13), Y(z.r0), EternalMood.POSTERS[2])

  -- Crew Quarters: bunks along both walls, lockers at the end.
  z = rooms["Crew Quarters"]
  for r = z.r0 + 4, z.r1 - 1, 3 do
    cover(map, "bunk", X(z.c0), Y(r), 2 * T, 56)
    cover(map, "bunk", X(z.c1 - 1), Y(r), 2 * T, 56)
  end
  cover(map, "lockers", X(z.c0 + 3), Y(z.r1) + 24, 5 * T, 40)

  -- The Mess: tables in rows, a serving counter down the east wall.
  z = rooms["The Mess"]
  for c = z.c0 + 2, z.c1 - 3, 4 do
    for r = z.r0 + 4, z.r1 - 2, 4 do
      cover(map, "table", X(c), Y(r), 2 * T, T)
      light(map, X(c + 1), Y(r) + 32, 110, EternalMood.LAMP, 0.35)
    end
  end
  cover(map, "counter", X(z.c1) + 16, Y(z.r0 + 3), 40, 7 * T)
  poster(map, X(z.c0 + 1), Y(z.r1 + 2) + 4, EternalMood.POSTERS[5]) -- on the wall south of it

  -- The Ring: a long corridor, pipes along its south wall.
  z = rooms["The Ring"]
  for _, span in ipairs({ { 12, 23 }, { 31, 43 } }) do -- clear of the doorways down
    cover(map, "pipe", X(span[1]), Y(z.r1 + 1) - 16, (span[2] - span[1] + 1) * T, 16)
  end
  poster(map, X(14), Y(z.r0), EternalMood.POSTERS[1])
  poster(map, X(33), Y(z.r0), EternalMood.POSTERS[6])

  -- The Offices: rows of desks with a chair at each, filing cabinets along
  -- the west wall and a water cooler.
  z = rooms["The Offices"]
  for c = z.c0 + 3, z.c1 - 2, 4 do
    for r = z.r0 + 3, z.r1 - 3, 4 do
      cover(map, "desk", X(c), Y(r), 2 * T, 40)
      cover(map, "chair", X(c) + 44, Y(r) + 46, 28, 28, false)
      light(map, X(c + 1), Y(r) + 20, 90, EternalMood.SCREEN, 0.35)
    end
  end
  for r = z.r0 + 2, z.r1 - 2, 3 do
    cover(map, "cabinet", X(z.c0) + 4, Y(r), 36, 2 * T - 16)
  end
  cover(map, "cooler", X(z.c1) + 8, Y(z.r0 + 1), 40, 40)
  poster(map, X(12), Y(z.r0), EternalMood.POSTERS[4]) -- clear of the door up

  -- The Reactor: the core in the middle (round, solid, humming), a catwalk
  -- ring round it, pipes out to the walls.
  z = rooms["The Reactor"]
  local mx, my = (X(z.c0) + X(z.c1 + 1)) / 2, (Y(z.r0) + Y(z.r1 + 1)) / 2
  flat(map, "catwalk", mx - 4.5 * T, my - 4.5 * T, 9 * T, 9 * T)
  cover(map, "reactor", mx - 2.2 * T, my - 2.2 * T, 4.4 * T, 4.4 * T, true, { round = true })
  light(map, mx, my, 520, EternalMood.CORE, 0.8)
  cover(map, "pipe", X(z.c0), my - 12, mx - 4.5 * T - X(z.c0), 24) -- west, under the door from the Offices
  cover(map, "pipe", mx + 4.5 * T, my - 12, X(z.c1 + 1) - mx - 4.5 * T, 24)
  for _, c in ipairs({ z.c0 + 1, z.c1 - 2 }) do
    for _, r in ipairs({ z.r0 + 1, z.r1 - 2 }) do
      cover(map, "crate", X(c), Y(r), 2 * T - 8, 2 * T - 8)
    end
  end

  -- Toxic Storage: barrels in clumps, pools of sludge, a crane over it all.
  z = rooms["Toxic Storage"]
  for _, p in ipairs({ { 2, 3 }, { 8, 2 }, { 3, 12 }, { 9, 15 }, { 5, 8 } }) do
    local c, r = z.c0 + p[1], z.r0 + p[2]
    for k = 0, 2 do
      local bx, by = X(c) + (k % 2) * 40, Y(r) + math.floor(k / 2) * 40
      cover(map, "barrel", bx, by, 36, 36, true, { round = true, red = rng:random() < 0.3 })
    end
  end
  for _, p in ipairs({ { 4, 4, 3, 2 }, { 7, 10, 4, 3 }, { 1, 16, 3, 2 } }) do
    local x, y = X(z.c0 + p[1]), Y(z.r0 + p[2])
    flat(map, "sludge", x, y, p[3] * T, p[4] * T)
    light(map, x + p[3] * T / 2, y + p[4] * T / 2, 80 + p[3] * 40, EternalMood.SLUDGE, 0.7)
  end
  flat(map, "crane", X(z.c0), Y(z.r0 + 9) + 16, (z.c1 - z.c0 + 1) * T, 32)

  -- The Hangar: the lift pad in the middle of the north wall, crates
  -- stacked round the walls, parked loaders, landing lines on the floor.
  z = rooms["The Hangar"]
  local lx, ly = X(24), Y(z.r0)
  flat(map, "lift", lx, ly, 8 * T, 4 * T)
  light(map, lx + 4 * T, ly + 2 * T, 360, EternalMood.ALARM, 0.45)
  map.exitX, map.exitY = math.floor(lx + 4 * T), math.floor(ly + 2 * T)
  local crates = {
    { 8, 5 }, { 11, 5 }, { 8, 8 }, { 40, 5 }, { 43, 5 }, { 46, 5 }, { 46, 8 }, { 14, 15 }, { 38, 14 },
    { 21, 14 }, { 23, 14 }, { 31, 11 }, { 44, 12 }, { 9, 12 }, -- stacks out on the floor, cover
  }
  for _, p in ipairs(crates) do
    cover(map, "crate", X(p[1]), Y(p[2]), 2 * T - 8, 2 * T - 8)
  end
  for _, p in ipairs({ { 17, 7 }, { 34, 9 } }) do
    cover(map, "loader", X(p[1]), Y(p[2]), 2 * T, 3 * T)
  end
  for c = 13, 42, 6 do
    flat(map, "paint", X(c), Y(12), 3 * T, 10)
  end
  poster(map, X(33), Y(z.r0), EternalMood.POSTERS[3])

  -- Heck's horde (eternal-mood/horde.lua). The possessed at their posts,
  -- in tiles (fractions for the middle of a tile) and facing `watch`: none
  -- in the Lab, where everyone wakes; staffers about the Crew Quarters, the
  -- Mess and the Ring; a guard just inside each doorway up from the Ring;
  -- staffers at the Offices' desks; the overtime guy by the Hangar's lift
  -- with guards and staffers round him. The imps wait in the vents, the
  -- Reactor's first, each with the way they crawl out (`out`) and how many
  -- for one human.
  local N, E, S, W = -math.pi / 2, 0, math.pi / 2, math.pi
  local horde = { posts = {}, vents = {} }
  map.horde = horde
  local function post(rank, c, r, watch)
    horde.posts[#horde.posts + 1] = { rank = rank, x = math.floor(X(c)), y = math.floor(Y(r)), watch = watch }
  end
  local function vent(c, r, out, count)
    local x, y = math.floor(X(c)), math.floor(Y(r))
    horde.vents[#horde.vents + 1] = { x = x, y = y, out = out, count = count }
    flat(map, "vent", x - 22, y - 16, 44, 32)
  end
  post("staffer", 9.5, 60, N) -- Crew Quarters
  post("staffer", 9.5, 64.5, N)
  post("staffer", 45.5, 58.5, W) -- the Mess
  post("staffer", 49.5, 62.5, W)
  post("staffer", 42.5, 66.5, N)
  post("staffer", 20, 50.5, E) -- the Ring
  post("staffer", 38, 50.5, W)
  post("guard", 10.5, 44.3, S) -- inside each doorway up from the Ring
  post("guard", 28, 44.3, S)
  post("guard", 45.5, 44.3, S)
  for _, d in ipairs({ { 7, 29 }, { 11, 29 }, { 11, 33 }, { 7, 37 }, { 11, 41 } }) do -- the Offices' desks
    post("staffer", d[1] + 0.9, d[2] + 0.95, N)
  end
  post("staffer", 24, 37, E) -- the Reactor's catwalk
  post("staffer", 32, 31, W)
  post("staffer", 41, 36, E) -- Toxic Storage
  post("staffer", 49.5, 33, W)
  post("overtime", 34.5, 6.5, S) -- the Hangar, beside the lift
  post("guard", 20, 12, S)
  post("guard", 36.5, 12.5, S)
  post("staffer", 12, 17, S)
  post("staffer", 44, 17, S)
  post("staffer", 28, 16, S)
  -- The Floor Manager (eternal-mood/floor_manager.lua) on the lift, facing
  -- the Hangar: he wakes when somebody walks into it, the lift is out of
  -- service until he is down, and his meetings come in through the three
  -- doorways up into it.
  local hz = rooms["The Hangar"]
  horde.boss = {
    x = math.floor(lx + 4 * T), y = math.floor(ly + 2 * T), facing = S,
    zone = { x0 = X(hz.c0), y0 = Y(hz.r0), x1 = X(hz.c1 + 1), y1 = Y(hz.r1 + 1) },
    lift = { x = lx, y = ly, w = 8 * T, h = 4 * T },
    doors = { { x = math.floor(X(10.5)), y = math.floor(Y(20.5)) }, { x = math.floor(X(28)), y = math.floor(Y(20.5)) },
      { x = math.floor(X(45.5)), y = math.floor(Y(20.5)) } },
  }
  vent(21, 33, E, 3) -- the Reactor
  vent(35, 30, W, 3)
  vent(50.5, 38, W, 3) -- Toxic Storage
  vent(7, 16, E, 2) -- the Hangar
  vent(48.5, 15, W, 2)

  -- Everyone wakes up in the Lab, at the head of the slabs; the way home is
  -- by the consoles behind them, well clear of where they wake.
  z = rooms["The Lab"]
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = X(z.c0 + 6) + (i % 6) * 2 * T + 32, y = Y(z.r0 + 6) + math.floor(i / 6) * 80, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(z.c0 + 10)), math.floor(Y(z.r1 - 1))
  map.openKinds = { walk = true }
  commit(map, g)
end

EternalMood.builders = {
  fobos = buildFobos,
}

--- Does `kind` name one of these maps?
function EternalMood.builds(kind)
  return EternalMood.builders[kind] ~= nil
end

--- Build map `map.kind` into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function EternalMood.build(map, rng, T)
  EternalMood.builders[map.kind](map, rng, T)
end

return EternalMood
