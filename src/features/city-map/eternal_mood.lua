-- The maps of the Eternal Mood quest line (docs/eternal-mood.md), one builder
-- each, all in the dark (the spec's `night`, the night feature). So far:
--   fobos     Fobos Base: the UAC's moon base cut through, walked from the Lab
--             at the bottom, round the Ring and up through the Offices, the
--             Reactor or Toxic Storage to the Hangar's lift at the top
--   earth     Heck on Earth: one long road north through a burning city,
--             walked from the UAC's Depot at the bottom through the Suburbs,
--             Downtown and round the Crater, up the Boulevard to the
--             starport's gate at the top
-- Everyone travels north (up the screen), the way both quest lines before
-- it do.
--
-- Tiles are "walk" (the base's floors, the city's streets); nil is wall
-- inside the base (`map.base`) and the moon outside it, or the city's
-- buildings (`map.roofs`), and the layout's walls make them solid.
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
--                         catwalk, paint, stripe, vent; and what lies about (`clutter`, each with an
--                         `angle` and a `seed`): bin (solid), tipped, trash, papers, blood, scorch, glass,
--                         fallen
--   map.signs             { x, y, w, h, text } posters and signs on the walls, world px
--   map.lights            { x, y, r, color, a } what glows in the dark (the night feature draws them), world px
--   map.alarms            { x, y } the red alarm lamps over the doors, world px; they turn like beacons
--                         (render_eternal_mood.lua's `alarmFlash`), so their light is the eternal-mood
--                         feature's, not in `lights`
--   map.flickers          { x, y, r, color, a, seed, dying } strip lights on the blink, not in `lights`:
--                         the eternal-mood feature flickers them (`dying` ones are mostly out)
--   map.horde             { posts = { rank, x, y, watch }, patrols = { ranks, route, start },
--                         mobs = { x, y, count, wake }, vents = { x, y, out, count } } Heck's horde
--                         (eternal-mood/horde.lua): the possessed at their posts (rank staffer, guard or
--                         overtime) and on patrol (a file of ranks walking `route`, a loop of { x, y }, from
--                         corner `start`), the Interns' mobs standing about their spot until woken, and the
--                         vents the imps crawl out of (`look` manhole or crack where they aren't vents),
--                         and `cacos` = { x, y, count, wake } the Cacodaemons' flocks floating about their
--                         spots (over anything: they fly), world px; and `boss` { x, y, facing,
--                         zone, lift, doors } the level's boss (the Floor Manager): where he waits, the room
--                         that wakes him, the lift he keeps out of service, the doorways his meetings use
--   map.openKinds         { walk = true }: pickups and the like go on the floor
-- Heck on Earth's also leaves (and no `base`):
--   map.grounds           { x0, y0, x1, y1, floor } the floor finish over each walked patch, world px: a later
--                         one over an earlier (asphalt, sidewalk, lawn, cracked)
--   map.roofs             { x, y, w, h, style, seed, burning } the buildings, world px, their roofs drawn in
--                         `style` (house, tower, warehouse, ruin, overpass, hedge, starport)
-- and more kinds in `map.cover`: car, van, bus (wrecks, `across` or nose north, maybe `police` or
-- `burning`), lamp (`dead` ones out), tree, barricade, deck, rubble, crater, sandbags, gate, shuttle, and
-- flat: lanes, zebra, fire, pad, manhole and crack (the imps' ways out, as Fobos Base's vents);
-- `map.flickers` with `fire` are flames (they flicker their own way).

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
  function g.at(c, r)
    return g.kind[c] and g.kind[c][r]
  end
  map.cover, map.zones, map.signs, map.lights, map.alarms, map.flickers = {}, {}, {}, {}, {}, {}
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

-- What lies about each room (kind = how many), eternal_mood.lua's
-- `clutter`; render_eternal_mood.lua draws them. Bins stand (solid); the
-- rest is on the floor, walked over: a tipped bin and its rubbish, trash,
-- papers, blood, scorch marks, glass, a chair knocked over.
EternalMood.CLUTTER = {
  ["The Lab"] = { blood = 2, papers = 2, glass = 2, scorch = 1 },
  ["Crew Quarters"] = { tipped = 1, trash = 1, blood = 1, papers = 1 },
  ["The Mess"] = { bin = 1, tipped = 2, trash = 3, blood = 1, fallen = 1 },
  ["The Ring"] = { bin = 2, tipped = 2, trash = 2, blood = 2, scorch = 1 },
  ["The Offices"] = { bin = 1, tipped = 1, papers = 4, fallen = 2, blood = 1 },
  ["The Reactor"] = { scorch = 2, blood = 1, glass = 1 },
  ["Toxic Storage"] = { tipped = 1, trash = 2, blood = 1, scorch = 1 },
  ["The Hangar"] = { bin = 2, tipped = 2, trash = 2, blood = 2, scorch = 2, papers = 1 },
}
local CLUTTER_SIZE = { -- px across
  bin = 28, tipped = 44, trash = 70, papers = 80, blood = 70, scorch = 90, glass = 50, fallen = 40,
}
local CLUTTER_ORDER = { "bin", "tipped", "fallen", "trash", "papers", "blood", "scorch", "glass" }

--- Scatter `kinds` (kind = how many) about room `z` (tiles): each where its
--- box is all floor, clear of everything solid already there, out of the
--- `doors` (tile boxes), and away from every spot in `avoid` (people, vents,
--- routes).
--- A bin is solid; everything else lies flat.
local function clutter(map, rng, g, z, kinds, avoid, doors)
  local X, Y, T = g.X, g.Y, g.T
  local function free(x, y, w, h, solid)
    for _, c in ipairs({ { x, y }, { x + w, y }, { x, y + h }, { x + w, y + h }, { x + w / 2, y + h / 2 } }) do
      local col, row = math.floor((c[1] - map.x0) / T), math.floor((c[2] - map.y0) / T)
      if not g.at(col, row) or col < z.c0 or col > z.c1 or row < z.r0 or row > z.r1 then
        return false
      end
    end
    local m = solid and 40 or 6 -- a bin keeps a body's width from anything else that stands
    for _, o in ipairs(map.solids) do
      if x + w + m > o.x and x - m < o.x + o.w and y + h + m > o.y and y - m < o.y + o.h then
        return false
      end
    end
    local keep = solid and 70 or 30
    for _, p in ipairs(avoid) do
      if (p.x - x - w / 2) ^ 2 + (p.y - y - h / 2) ^ 2 < keep * keep then
        return false
      end
    end
    for _, d in ipairs(doors or {}) do
      if x + w > X(d.c0) - 24 and x < X(d.c1 + 1) + 24 and y + h > Y(d.r0) - 24 and y < Y(d.r1 + 1) + 24 then
        return false
      end
    end
    return true
  end
  for _, kind in ipairs(CLUTTER_ORDER) do
    for _ = 1, kinds[kind] or 0 do
      local size = CLUTTER_SIZE[kind]
      for _ = 1, 30 do -- a few goes at somewhere it fits
        local x = X(z.c0) + rng:random() * ((z.c1 - z.c0 + 1) * T - size)
        local y = Y(z.r0) + rng:random() * ((z.r1 - z.r0 + 1) * T - size)
        local solid = kind == "bin"
        if free(x, y, size, size, solid) then
          local extra = { angle = rng:random() * 2 * math.pi, seed = rng:random(1000) }
          if solid then
            cover(map, kind, x, y, size, size, true, extra)
          else
            flat(map, kind, x, y, size, size, extra)
          end
          break
        end
      end
    end
  end
end

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
    -- Strip lights down the room, a pool every few tiles; one in four is
    -- on the blink (`map.flickers`, the eternal-mood feature flickers it),
    -- and one in twelve has all but died.
    for c = z.c0 + 2, z.c1, 6 do
      for r = z.r0 + 2, z.r1, 6 do
        local roll = rng:random()
        if roll < 0.25 then
          map.flickers[#map.flickers + 1] = { x = X(c), y = Y(r), r = 190, color = EternalMood.STRIP, a = 0.35,
            seed = rng:random(1000), dying = roll < 0.08 }
        else
          light(map, X(c), Y(r), 190, EternalMood.STRIP, 0.3)
        end
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
  -- Patrols: a file of the possessed walking a loop (corners in tiles), the
  -- first setting off from corner `start`: up and down the Ring, round the
  -- Offices' desks, round the Reactor's catwalk, through Toxic Storage and
  -- round the Hangar's floor.
  horde.patrols = {}
  local function patrol(ranks, corners, start)
    local route = {}
    for _, c in ipairs(corners) do
      route[#route + 1] = { x = math.floor(X(c[1])), y = math.floor(Y(c[2])) }
    end
    horde.patrols[#horde.patrols + 1] = { ranks = ranks, route = route, start = start or 1 }
  end
  patrol({ "guard", "staffer", "staffer" }, { { 6, 50.5 }, { 49.5, 50.5 } }) -- the Ring
  patrol({ "staffer", "staffer" }, { { 5.6, 27.5 }, { 15.5, 27.5 }, { 15.5, 43.5 }, { 5.6, 43.5 } }) -- the Offices
  patrol({ "guard", "staffer" }, { { 24.5, 29.5 }, { 31.5, 29.5 }, { 31.5, 42.5 }, { 24.5, 42.5 } }, 3) -- the Reactor
  patrol({ "staffer", "staffer" }, { { 40.5, 32.5 }, { 50.5, 32.5 }, { 50.5, 44 }, { 40.5, 44 } }, 2) -- Toxic Storage
  patrol({ "guard", "staffer", "staffer" }, { { 10, 11 }, { 46, 11 }, { 46, 17.5 }, { 10, 17.5 } }) -- the Hangar

  -- The Interns' mobs (in tiles, with how many for one human and how near a
  -- player wakes them): asleep in the Crew Quarters' bunks, on their lunch
  -- in the Mess, loitering at the Ring's west end, in Toxic Storage and in
  -- the Offices' far corner.
  horde.mobs = {}
  local function mob(c, r, count, wake)
    horde.mobs[#horde.mobs + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), count = count, wake = wake }
  end
  mob(9.5, 62, 6, 380) -- Crew Quarters
  mob(46, 62, 8, 420) -- the Mess
  mob(8, 50.5, 5, 420) -- the Ring's west end
  mob(45, 40.5, 5, 400) -- Toxic Storage
  mob(14, 38.5, 5, 380) -- the Offices' far corner

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

  -- The mess the night left, room by room (`clutter`): kept off everyone's
  -- spots and the doorways, and only where it fits on the floor.
  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY }, { x = horde.boss.x, y = horde.boss.y } }
  for _, list in ipairs({ horde.posts, horde.vents, horde.mobs, map.spawns }) do
    for _, p in ipairs(list) do
      avoid[#avoid + 1] = { x = p.x, y = p.y }
    end
  end
  for _, p in ipairs(horde.patrols) do
    for _, c in ipairs(p.route) do
      avoid[#avoid + 1] = { x = c.x, y = c.y }
    end
  end
  for _, d in ipairs(horde.boss.doors) do
    avoid[#avoid + 1] = { x = d.x, y = d.y }
  end
  for _, room in ipairs(EternalMood.FOBOS) do
    clutter(map, rng, g, room, EternalMood.CLUTTER[room.name] or {}, avoid, EternalMood.FOBOS_DOORS)
  end

  map.openKinds = { walk = true }
  commit(map, g)
end

-- Heck on Earth ----------------------------------------------------------------

EternalMood.FIRE = { 1.00, 0.45, 0.10 } -- everything that's burning
EternalMood.STREET = { 1.00, 0.58, 0.38 } -- the street lamps still on
EternalMood.LAVA = { 1.00, 0.35, 0.05 } -- the Crater

-- The billboards over the side streets: the city's adverts, and the radio's
-- sofa sale got onto them too (the dream leaking in).
EternalMood.BILLBOARDS = {
  "SOFA SALE! SOFAS! SOFAS! SOFAS!",
  "UAC: A HECK OF A JOB",
  "HECK: NOW HIRING",
  "EVACUATE: STARPORT, STRAIGHT ON",
  "MIND THE LAVA",
  "SNOOZE-O-MATIC: FIVE MORE MINUTES",
}

-- The road's stretches, bottom to top (rows, inclusive), all the map's width.
EternalMood.EARTH = {
  { name = "The Depot", r0 = 142, r1 = 158 },
  { name = "The Suburbs", r0 = 108, r1 = 141 },
  { name = "Downtown", r0 = 66, r1 = 107 },
  { name = "The Crater", r0 = 38, r1 = 65 },
  { name = "The Boulevard", r0 = 2, r1 = 37 },
}

-- The crossroads (rows, inclusive): a side street off each side, blocked a
-- block in.
EternalMood.EARTH_CROSSROADS = { { 129, 132 }, { 115, 118 }, { 94, 97 }, { 76, 79 } }

-- What lies about each stretch (kind = how many), as Fobos Base's rooms.
EternalMood.EARTH_CLUTTER = {
  ["The Depot"] = { papers = 2, blood = 1, scorch = 2, tipped = 1 },
  ["The Suburbs"] = { bin = 3, tipped = 4, trash = 5, papers = 3, blood = 3, scorch = 4, glass = 3 },
  ["Downtown"] = { bin = 3, tipped = 4, trash = 6, papers = 6, blood = 4, scorch = 5, glass = 5 },
  ["The Crater"] = { scorch = 8, blood = 4, glass = 3, trash = 3 },
  ["The Boulevard"] = { bin = 2, tipped = 3, trash = 4, papers = 4, blood = 5, scorch = 6, glass = 3 },
}

local function buildEarth(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local cols = map.cols
  map.grounds, map.roofs = {}, {}
  local N, E, S, W = -math.pi / 2, 0, math.pi / 2, math.pi

  --- Floor `finish` over tiles c0..c1, r0..r1 (a later one over an earlier).
  local function ground(c0, r0, c1, r1, finish)
    g.fill(c0, r0, c1, r1, "walk")
    map.grounds[#map.grounds + 1] = { x0 = X(c0), y0 = Y(r0), x1 = X(c1 + 1), y1 = Y(r1 + 1), floor = finish }
  end
  --- A building over tiles c0..c1, r0..r1 (they stay nil: solid), its roof in `style`.
  local function block(c0, r0, c1, r1, style, burning)
    local b = { x = X(c0), y = Y(r0), w = (c1 - c0 + 1) * T, h = (r1 - r0 + 1) * T, style = style,
      seed = rng:random(1000), burning = burning }
    map.roofs[#map.roofs + 1] = b
    return b
  end
  --- Flames at (x, y), `size` px across, and their light, flickering.
  local function fire(x, y, size)
    flat(map, "fire", x - size / 2, y - size / 2, size, size, { seed = rng:random(1000) })
    map.flickers[#map.flickers + 1] = { x = x, y = y, r = 120 + size * 1.6, color = EternalMood.FIRE, a = 0.55,
      seed = rng:random(1000), fire = true }
  end
  --- Fires across a burning building's roof.
  local function burn(b)
    for _ = 1, 1 + math.floor(b.w * b.h / (T * T * 24)) do
      fire(b.x + b.w * (0.2 + rng:random() * 0.6), b.y + b.h * (0.2 + rng:random() * 0.6), 60 + rng:random(60))
    end
  end
  --- A wreck on the road: a car (or a police car, `police`), a bus or a
  --- van, nose north unless `across`, burning maybe.
  local SIZES = { car = { 56, 112 }, bus = { 72, 232 }, van = { 64, 128 } }
  local function wreck(kind, c, r, across, extra)
    local w, h = SIZES[kind][1], SIZES[kind][2]
    if across then
      w, h = h, w
    end
    local s = cover(map, kind, X(c), Y(r), w, h, true, {
      across = across, seed = rng:random(1000), tilt = (rng:random() - 0.5) * 0.2,
    })
    for k, v in pairs(extra or {}) do
      s[k] = v
    end
    if s.burning then
      fire(s.x + s.w / 2, s.y + s.h / 2, 70)
    end
    return s
  end
  --- The main road over rows r0..r1: six lanes, a sidewalk either side.
  local function street(r0, r1)
    ground(13, r0, 14, r1, "sidewalk")
    ground(25, r0, 26, r1, "sidewalk")
    ground(15, r0, 24, r1, "asphalt")
  end
  --- Lane markings over rows r0..r1 of the road at column c (`n` tiles
  --- across); `oneway` for half of the Boulevard (no centre line).
  local function lanes(c, n, r0, r1, oneway)
    flat(map, "lanes", X(c), Y(r0), n * T, (r1 - r0 + 1) * T, { oneway = oneway })
  end
  --- A street lamp on each sidewalk every few rows over r0..r1 (posts at
  --- columns wc and ec): some lit, some on the blink, a lot of them dead.
  local function lamps(r0, r1, wc, ec, every)
    for r = r0 + 2, r1 - 1, every do
      for _, side in ipairs({ { X(wc) + 6, X(wc + 1) + 40 }, { X(ec + 1) - 20, X(ec) - 40 } }) do
        local post = cover(map, "lamp", side[1], Y(r), 14, 14, true, { round = true })
        local roll = rng:random()
        if roll < 0.4 then
          post.dead = true
        elseif roll < 0.6 then
          map.flickers[#map.flickers + 1] = { x = side[2], y = Y(r) + 7, r = 210, color = EternalMood.STREET, a = 0.4,
            seed = rng:random(1000), dying = roll < 0.48 }
        else
          light(map, side[2], Y(r) + 7, 210, EternalMood.STREET, 0.4)
        end
      end
    end
  end
  --- A side street off each side over rows r0..r1, blocked a block in by a
  --- burning barricade, zebra crossings over the main road either side of
  --- it, and a billboard on the corner past it.
  local function crossroads(r0, r1, board)
    ground(15, r0, 24, r1, "asphalt")
    ground(3, r0, 14, r1, "asphalt")
    ground(25, r0, 36, r1, "asphalt")
    for _, c in ipairs({ 3, 36 }) do
      cover(map, "barricade", X(c), Y(r0), T, (r1 - r0 + 1) * T, true, { seed = rng:random(1000) })
      fire(X(c) + T / 2, Y(r0) + (r1 - r0 + 1) * T / 2, 80)
    end
    flat(map, "zebra", X(15), Y(r0 - 1) + 8, 10 * T, 48)
    flat(map, "zebra", X(15), Y(r1 + 1) + 8, 10 * T, 48)
    poster(map, X(5), Y(r0), EternalMood.BILLBOARDS[board])
    poster(map, X(29), Y(r0), EternalMood.BILLBOARDS[board % #EternalMood.BILLBOARDS + 1])
  end

  for _, z in ipairs(EternalMood.EARTH) do
    map.zones[#map.zones + 1] = { name = z.name, x0 = X(0), y0 = Y(z.r0), x1 = X(cols), y1 = Y(z.r1 + 1) }
  end

  -- The Depot: the UAC's yard at the bottom, where the shuttle down from
  -- Fobos Base has landed; the gate out onto the road at its top.
  ground(6, 145, 33, 157, "asphalt")
  ground(15, 142, 24, 144, "asphalt")
  flat(map, "stripe", X(15), Y(142) + 8, 10 * T, 24)
  flat(map, "stripe", X(15), Y(145) - 32, 10 * T, 24)
  map.alarms[#map.alarms + 1] = { x = X(15) - 14, y = Y(143) + 32 }
  map.alarms[#map.alarms + 1] = { x = X(25) + 14, y = Y(143) + 32 }
  flat(map, "pad", X(7), Y(147), 8 * T, 10 * T)
  cover(map, "shuttle", X(8), Y(148), 6 * T, 8 * T)
  light(map, X(11), Y(152), 300, EternalMood.ALARM, 0.35)
  for _, p in ipairs({ { 30, 146 }, { 32, 146 }, { 32, 148 }, { 30, 154 }, { 32, 155 } }) do
    cover(map, "crate", X(p[1]), Y(p[2]), 2 * T - 8, 2 * T - 8)
  end
  for _, p in ipairs({ { 17, 146 }, { 28, 146 }, { 17, 156 }, { 28, 156 } }) do
    light(map, X(p[1]), Y(p[2]), 260, EternalMood.STRIP, 0.35)
  end
  poster(map, X(7), Y(145), "UAC DEPOT: NO DEMONS PAST HERE")
  block(2, 142, 14, 144, "warehouse")
  block(25, 142, 37, 144, "warehouse")
  block(2, 145, 5, 157, "warehouse")
  block(34, 145, 37, 157, "warehouse")

  -- The Suburbs: houses either side behind their front yards, some of them
  -- burning, hedges between the yards.
  street(108, 141)
  local function houses(r0, r1)
    local r = r0
    while r + 3 <= r1 do
      local r2 = math.min(r + 5, r1)
      for _, side in ipairs({ { 3, 8, 9, 12 }, { 31, 36, 27, 30 } }) do
        local b = block(side[1], r, side[2], r2, "house", rng:random() < 0.4)
        ground(side[3], r, side[4], r2, "lawn")
        if b.burning then
          burn(b)
        end
        local roll = rng:random()
        if roll < 0.35 then -- a burnt-out tree in the yard
          local tc = side[3] + 1 + rng:random(0, 1)
          cover(map, "tree", X(tc) + 8, Y(r + 1 + rng:random(0, r2 - r - 2)) + 8, 48, 48, true, { round = true })
        elseif roll < 0.6 then -- the car on the drive
          wreck("car", side[3] + 1, r + 1, false, { burning = rng:random() < 0.3 })
        end
      end
      if r2 + 1 <= r1 then
        block(3, r2 + 1, 12, r2 + 1, "hedge")
        block(27, r2 + 1, 36, r2 + 1, "hedge")
      end
      r = r2 + 2
    end
  end
  houses(133, 141)
  houses(119, 128)
  houses(108, 114)
  crossroads(129, 132, 1)
  crossroads(115, 118, 4)
  lanes(15, 10, 134, 141)
  lanes(15, 10, 120, 127)
  wreck("car", 16, 137, false)
  wreck("car", 21, 122, true, { burning = true })
  wreck("van", 23, 110, false)
  wreck("car", 18, 112, false, { police = true })

  -- Downtown: taller blocks flush to the sidewalks, wrecks all over the
  -- road, and the overpass that crossed it come down, the road squeezed
  -- to a gap in the rubble.
  street(66, 107)
  for _, span in ipairs({ { 98, 107 }, { 90, 93 }, { 80, 85 }, { 66, 75 } }) do
    local west = block(2, span[1], 12, span[2], "tower", rng:random() < 0.5)
    local east = block(27, span[1], 37, span[2], "tower", rng:random() < 0.5)
    for _, b in ipairs({ west, east }) do
      if b.burning then
        burn(b)
      end
    end
  end
  block(2, 86, 12, 89, "overpass")
  block(27, 86, 37, 89, "overpass")
  cover(map, "deck", X(13), Y(86) + 16, 6 * T, 4 * T - 32, true, { seed = rng:random(1000) })
  cover(map, "deck", X(22), Y(86) + 16, 5 * T, 4 * T - 32, true, { seed = rng:random(1000) })
  crossroads(94, 97, 2)
  crossroads(76, 79, 5)
  lanes(15, 10, 99, 113)
  lanes(15, 10, 81, 92)
  lanes(15, 10, 66, 74)
  wreck("bus", 16, 95, true, { burning = true }) -- across the first crossroads
  wreck("car", 22, 95, true)
  wreck("car", 18, 103, false)
  wreck("car", 23, 106, false, { police = true })
  wreck("van", 15, 100, false)
  wreck("car", 15, 77, true)
  wreck("car", 21, 77, true, { burning = true }) -- across the second
  wreck("bus", 23, 68, false)
  wreck("car", 17, 71, false, { burning = true })
  wreck("car", 19, 82, false)

  -- The Crater: a portal's opened in the road, lava in it. The blocks
  -- round it have fallen in, the road split either side of it, cracked.
  street(38, 65)
  ground(7, 40, 32, 63, "cracked")
  block(2, 38, 6, 65, "ruin")
  block(33, 38, 37, 65, "ruin")
  block(7, 38, 12, 39, "ruin")
  block(27, 38, 32, 39, "ruin")
  block(7, 64, 12, 65, "ruin")
  block(27, 64, 32, 65, "ruin")
  cover(map, "crater", X(15), Y(45), 10 * T, 13 * T, true, { round = true, seed = rng:random(1000) })
  light(map, X(20), Y(51.5), 600, EternalMood.LAVA, 0.6)
  for _, p in ipairs({ { 8, 44 }, { 30, 47 }, { 9, 59 }, { 29, 58 }, { 12, 53 }, { 26, 42 } }) do
    cover(map, "rubble", X(p[1]), Y(p[2]), 84, 60, true, { seed = rng:random(1000) })
  end
  for _ = 1, 4 do
    fire(X(8 + rng:random() * 24), Y(40 + rng:random() * 23), 50 + rng:random(40))
  end

  -- The Boulevard: long, straight and wide, planters of burnt trees down
  -- the middle, the UAC's sandbags across it, a tower on fire at the
  -- bottom of it, and the starport's gate at the top.
  ground(7, 6, 8, 37, "sidewalk")
  ground(31, 6, 32, 37, "sidewalk")
  ground(9, 6, 30, 37, "asphalt")
  lanes(9, 10, 6, 37, true)
  lanes(21, 10, 6, 37, true)
  for r = 8, 35, 5 do
    cover(map, "tree", X(19) + 32, Y(r), 64, 64, true, { round = true, planter = true })
  end
  for _, p in ipairs({ { 11, 26 }, { 25, 26 }, { 14, 14 }, { 22, 14 } }) do
    cover(map, "sandbags", X(p[1]), Y(p[2]) + 16, 4 * T, 32)
  end
  wreck("car", 10, 31, false, { burning = true })
  wreck("van", 28, 33, true)
  wreck("car", 26, 19, false)
  wreck("car", 12, 9, true, { police = true })
  local tower = block(2, 28, 6, 37, "tower", true)
  burn(tower)
  burn(tower)
  block(2, 18, 6, 27, "tower")
  block(2, 2, 6, 17, "tower", rng:random() < 0.5)
  block(33, 26, 37, 37, "tower", rng:random() < 0.5)
  block(33, 12, 37, 25, "tower")
  block(33, 2, 37, 11, "tower")
  for _, b in ipairs(map.roofs) do
    if b.style == "tower" and b.burning and b ~= tower and b.y < Y(38) then
      burn(b)
    end
  end
  lamps(6, 37, 7, 32, 6)
  lamps(66, 141, 13, 26, 7)
  -- The starport's gate: pillars either side of the way through, the
  -- terminal beyond.
  ground(9, 2, 30, 5, "asphalt")
  cover(map, "gate", X(9), Y(2), 5 * T, 2 * T)
  cover(map, "gate", X(26), Y(2), 5 * T, 2 * T)
  flat(map, "stripe", X(14), Y(4) + 8, 12 * T, 24)
  block(2, 0, 37, 1, "starport")
  poster(map, X(15) + 16, Y(2), "STARPORT: LAST SHUTTLE OUT")
  map.exitX, map.exitY = math.floor(X(20)), math.floor(Y(3))
  for _, c in ipairs({ 14, 26 }) do
    map.alarms[#map.alarms + 1] = { x = X(c), y = Y(4) }
  end

  -- Heck's horde (eternal-mood/horde.lua), in tiles. Nobody in the Depot.
  -- Possessed neighbours in the Suburbs' yards, guards behind the wrecks
  -- at the crossroads, an overtime guy holding the overpass's gap and
  -- another the starport's gate; Interns' mobs in the side streets, the
  -- imps under the manholes and in the Crater's cracks.
  local horde = { posts = {}, vents = {}, patrols = {}, mobs = {} }
  map.horde = horde
  local function post(rank, c, r, watch)
    horde.posts[#horde.posts + 1] = { rank = rank, x = math.floor(X(c)), y = math.floor(Y(r)), watch = watch }
  end
  local function vent(c, r, out, count, kind)
    local x, y = math.floor(X(c)), math.floor(Y(r))
    horde.vents[#horde.vents + 1] = { x = x, y = y, out = out, count = count, look = kind }
    flat(map, kind, x - 22, y - 22, 44, 44)
  end
  local function patrol(ranks, corners, start)
    local route = {}
    for _, c in ipairs(corners) do
      route[#route + 1] = { x = math.floor(X(c[1])), y = math.floor(Y(c[2])) }
    end
    horde.patrols[#horde.patrols + 1] = { ranks = ranks, route = route, start = start or 1 }
  end
  local function mob(c, r, count, wake)
    horde.mobs[#horde.mobs + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), count = count, wake = wake }
  end
  -- The Suburbs.
  post("staffer", 11, 136.5, E)
  post("staffer", 28.5, 124, W)
  post("staffer", 10.5, 110.5, E)
  post("staffer", 20, 126, S)
  post("staffer", 24, 135, S)
  patrol({ "staffer", "staffer" }, { { 16, 139 }, { 16, 120 }, { 23.5, 120 }, { 23.5, 139 } })
  mob(7, 131, 5, 400)
  mob(32, 117, 6, 420)
  mob(33, 131, 4, 380)
  vent(20, 113, S, 2, "manhole")
  vent(18, 136, S, 2, "manhole")
  -- Downtown.
  post("guard", 17.5, 94.3, S) -- behind the bus
  post("guard", 22.5, 94.3, S)
  post("guard", 16, 76.3, S) -- behind the wrecks at the second crossroads
  post("guard", 22, 76.3, S)
  post("overtime", 20.5, 84.5, S) -- holding the gap in the overpass
  post("staffer", 14, 104, E)
  post("staffer", 25.5, 101, W)
  post("staffer", 13.5, 72, E)
  post("staffer", 25.5, 69, W)
  patrol({ "guard", "staffer", "staffer" }, { { 14, 106 }, { 14, 99.5 }, { 25.5, 99.5 }, { 25.5, 106 } })
  patrol({ "staffer", "staffer" }, { { 14, 73 }, { 25.5, 73 } })
  mob(7, 95.5, 6, 420)
  mob(32, 78, 6, 420)
  mob(8, 77.5, 5, 380)
  mob(20.5, 91.5, 6, 400) -- in front of the gap
  vent(20, 101.5, S, 2, "manhole")
  vent(19, 70, S, 2, "manhole")
  -- The Crater.
  post("guard", 10, 41.5, S)
  post("guard", 29.5, 41.5, S)
  post("staffer", 10.5, 62, N)
  post("staffer", 28.5, 61, N)
  patrol({ "guard", "staffer", "staffer" }, { { 10, 43 }, { 30, 43 }, { 30, 61.5 }, { 10, 61.5 } }, 3)
  mob(10, 51, 6, 420)
  mob(29.5, 53, 6, 420)
  vent(13, 50, W, 3, "crack")
  vent(26.5, 52, E, 3, "crack")
  vent(20, 60, S, 3, "crack")
  vent(20, 43, N, 3, "crack")
  -- The Boulevard.
  post("guard", 13, 25.6, S) -- behind the sandbags
  post("guard", 27, 25.6, S)
  post("guard", 16, 13.6, S)
  post("guard", 24, 13.6, S)
  post("overtime", 20, 7.5, S) -- at the starport's gate
  post("staffer", 10, 20, E)
  post("staffer", 30, 30, W)
  patrol({ "guard", "staffer", "staffer" }, { { 11, 30 }, { 28, 30 }, { 28, 18 }, { 11, 18 } })
  mob(12, 34, 7, 420)
  mob(27.5, 21, 6, 420)
  mob(20, 11, 6, 400)
  vent(10.5, 22, E, 2, "manhole")
  vent(29.5, 11, W, 2, "manhole")
  -- The Cacodaemons (horde.lua), floating over the roofs, the road and the
  -- Crater's lava, a flock to each spot (how many for one human, how near
  -- wakes them): one over the Suburbs, three Downtown, two over the lava,
  -- two over the Boulevard's towers.
  horde.cacos = {}
  local function cacos(c, r, count, wake)
    horde.cacos[#horde.cacos + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), count = count, wake = wake }
  end
  cacos(5.5, 124, 1, 520)
  cacos(7, 102, 1, 560)
  cacos(32, 87.5, 1, 560)
  cacos(20, 70, 1, 520)
  cacos(20, 51.5, 2, 640)
  cacos(4, 22, 1, 560)
  cacos(35.5, 15, 1, 560)

  -- Everyone comes down the shuttle's ramp into the Depot; the way home is
  -- back by the shuttle, well clear of where they arrive.
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = X(17) + (i % 6) * 2 * T + 32, y = Y(148) + math.floor(i / 6) * 96, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(20)), math.floor(Y(156))

  -- The mess, stretch by stretch, kept off everyone's spots.
  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY } }
  for _, list in ipairs({ horde.posts, horde.vents, horde.mobs, map.spawns }) do
    for _, p in ipairs(list) do
      avoid[#avoid + 1] = { x = p.x, y = p.y }
    end
  end
  for _, p in ipairs(horde.patrols) do
    for _, c in ipairs(p.route) do
      avoid[#avoid + 1] = { x = c.x, y = c.y }
    end
  end
  for _, z in ipairs(EternalMood.EARTH) do
    local room = { c0 = 0, c1 = cols - 1, r0 = z.r0, r1 = z.r1 }
    clutter(map, rng, g, room, EternalMood.EARTH_CLUTTER[z.name] or {}, avoid)
  end

  map.openKinds = { walk = true }
  commit(map, g)
end

EternalMood.builders = {
  fobos = buildFobos,
  earth = buildEarth,
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
