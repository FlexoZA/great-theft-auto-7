-- The maps of the Eternal Mood quest line (docs/eternal-mood.md), one builder
-- each, all in the dark (the spec's `night`, the night feature). So far:
--   fobos     Fobos Base: the UAC's moon base cut through, walked from the Lab
--             at the bottom, round the Ring and up through the Offices, the
--             Reactor or Toxic Storage to the Hangar's lift at the top
--   earth     Heck on Earth: one long road north through a burning city,
--             walked from the UAC's Depot at the bottom through the Suburbs,
--             Downtown and round the Crater, up the Boulevard to the
--             starport's gate at the top
--   foundry   The Foundry: the UAC's factory, half turned to Heck, walked
--             from the Landing Pad at the bottom over the Conveyors' belts
--             and through the Smelters to the Crucible and the portal behind
--             it at the top
--   heck      Heck: out of the portal onto a rock shelf at the bottom, over
--             a sea of lava by its bone bridges, across the Altar Fields
--             (the pizza box sinking in the lake to the east) and up onto
--             the Mattress's plateau before the Snooze Gate at the top
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
--                         spots (over anything: they fly), `knights` = { x, y, facing, count, wake } the Dread
--                         Knights standing at theirs (eternal-mood/dread_knight.lua), `mechas` = { route, mob }
--                         the Mecha Zombies' loops round their mobs and each mob's `meal` { x, y, angle } the
--                         body it is eating (`feast`), world px; and `boss` the level's boss, by `kind`:
--                         "floor-manager" { x, y, facing, zone, lift, doors }: where he waits, the room that
--                         wakes him, the lift he keeps out of service, the doorways his meetings use;
--                         "mancubus" { x, y, facing, zone, wake, gate }: where he sits, the patch he keeps
--                         to, where a player wakes him, the gate he keeps closed; "baron" { x, y, facing,
--                         wake, pit, portal }: where he stands, where a player wakes him (he goes anywhere
--                         once awake), the pit he calls imps out of, the portal he keeps sealed;
--                         "mattressmind" { x, y, facing, zone, wake, gate }: the same as the Mancouchbus, the
--                         gate it keeps locked
--   map.lows              { x, y, w, h, round } the lava's solids, which are `low`: sight, rounds and players
--                         pass over; a player in it burns, and the horde keeps out (eternal-mood/ground.lua)
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
-- The Foundry's also leaves `outside` "tarmac" (what's past its walls), `heckFrom` (world y: north of it
-- the walls are Heck's rock), `belts` { x, y, w, h, vx, vy } (the moving floor: whoever stands on one is
-- carried at vx, vy px/s, the eternal-mood feature's belts.lua) and kinds belt, vat, lava, crucible, ring,
-- bridge, gateway (the portal), chain, growth, spire, booth (Dr. Seek's), bones (clutter).
-- Heck's: `outside` "abyss", lava poured over whatever isn't rock or bridge (low, as `lows`), and kinds
-- bonebridge, altar, firepit (low: it burns), pizzabox, snoozegate; `map.pizza` { x, y } where
-- the pizza box is.

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
  map.lows = {}
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

--- Something standing on the map, in world px. Solid unless `solid` is
--- false; `low` (in `extra`: lava) is no wall to sight, rounds or players
--- (city-map's collision): it goes in `map.lows` too, which the horde keeps
--- out of and which burns a player walking in it (eternal-mood/ground.lua).
local function cover(map, kind, x, y, w, h, solid, extra)
  local s = { kind = kind, x = x, y = y, w = w, h = h, solid = solid ~= false }
  for k, v in pairs(extra or {}) do
    s[k] = v
  end
  map.cover[#map.cover + 1] = s
  if s.solid then
    map.solids[#map.solids + 1] = { x = x, y = y, w = w, h = h, low = s.low }
    if s.low then
      map.lows[#map.lows + 1] = { x = x, y = y, w = w, h = h, round = s.round }
    end
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
  bin = 28, tipped = 44, trash = 70, papers = 80, blood = 70, scorch = 90, glass = 50, fallen = 40, bones = 60,
  -- Heck on Earth's yards and streets
  trampoline = 96, swing = 84, gardenbed = 72, doghouse = 48, lawnchair = 34, bike = 44, mailbox = 20, hydrant = 22,
  debris = 64, oil = 60, skid = 120,
  -- the Foundry's
  slag = 70, skulls = 50, spike = 34, ingots = 44,
  -- Heck's
  ribcage = 120, runes = 150, drag = 140,
}
local CLUTTER_ORDER = { "runes", "ribcage", "trampoline", "swing", "gardenbed", "doghouse", "bin", "ingots", "spike",
  "drag", "mailbox",
  "hydrant", "tipped", "fallen", "lawnchair", "bike", "trash", "papers", "debris", "slag", "skulls", "blood", "scorch",
  "oil", "skid", "glass", "bones" }
-- The ones that stand (and stop a round); the rest lie flat.
local CLUTTER_SOLID = { bin = true, doghouse = true, mailbox = true, hydrant = true, spike = true, ingots = true }

--- Scatter `kinds` (kind = how many) about room `z` (tiles): each where its
--- box is all floor, clear of everything solid already there, out of the
--- `doors` (tile boxes), and away from every spot in `avoid` (people, vents,
--- routes).
--- The CLUTTER_SOLID kinds stand; everything else lies flat.
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
        local solid = CLUTTER_SOLID[kind] == true
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

-- A feast: every Intern mob of `map.horde` crowds round a body it dragged
-- in, eating it (horde.lua puts them round `mob.meal`): the body, a trail
-- of blood back the way it came over open floor, spatter about. A Mecha
-- Zombie walks a loop round each mob, guarding it (`horde.mechas`,
-- eternal-mood/mecha_zombie.lua): its `route`, clear points in a ring,
-- and the mob it belongs to. Returns those points, for the clutter to keep
-- off.
local TRAIL = 3.5 -- tiles back along the way it was dragged
local MECHA_RINGS = { 3, 2.5, 3.5, 2 } -- tiles round the mob its loop runs at, the first that fits
local function feast(map, rng, g)
  local T = g.T
  local horde = map.horde
  local function open(x, y, margin)
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    if not g.at(c, r) then
      return false
    end
    for _, o in ipairs(map.solids) do
      if x > o.x - margin and x < o.x + o.w + margin and y > o.y - margin and y < o.y + o.h + margin then
        return false
      end
    end
    return true
  end
  horde.mechas = {}
  local keep = {}
  for i, mob in ipairs(horde.mobs or {}) do
    -- The way it was dragged in: the first of eight ways round with open
    -- floor all along it.
    local start = rng:random() * 2 * math.pi
    for k = 0, 7 do
      local a = start + k * math.pi / 4
      local ok = true
      for f = 0.15, 1, 0.17 do
        if not open(mob.x + math.cos(a) * TRAIL * T * f, mob.y + math.sin(a) * TRAIL * T * f, 4) then
          ok = false
          break
        end
      end
      if ok then
        local sx, sy = mob.x + math.cos(a) * TRAIL * T, mob.y + math.sin(a) * TRAIL * T
        flat(map, "bloodtrail", math.min(sx, mob.x) - 16, math.min(sy, mob.y) - 16, math.abs(sx - mob.x) + 32,
          math.abs(sy - mob.y) + 32, { x1 = sx, y1 = sy, x2 = mob.x, y2 = mob.y, seed = rng:random(1000) })
        break
      end
    end
    mob.meal = { x = mob.x, y = mob.y, angle = rng:random() * 2 * math.pi }
    flat(map, "meal", mob.x - 34, mob.y - 34, 68, 68, { angle = mob.meal.angle, seed = rng:random(1000) })
    for _ = 1, 3 do
      local a, d = rng:random() * 2 * math.pi, 36 + rng:random() * 40
      flat(map, "blood", mob.x + math.cos(a) * d - 30, mob.y + math.sin(a) * d - 30, 60, 60,
        { angle = rng:random() * 2 * math.pi, seed = rng:random(1000) })
    end
    -- The guard's loop: six points in a ring, the ring that fits most.
    local best
    for _, ring in ipairs(MECHA_RINGS) do
      local route = {}
      for k = 0, 5 do
        local a = k * math.pi / 3 + 0.3
        local x, y = mob.x + math.cos(a) * ring * T, mob.y + math.sin(a) * ring * T
        if open(x, y, 20) then
          route[#route + 1] = { x = math.floor(x), y = math.floor(y) }
        end
      end
      if not best or #route > #best then
        best = route
      end
      if #route == 6 then
        break
      end
    end
    if best and #best >= 3 then
      horde.mechas[#horde.mechas + 1] = { route = best, mob = i }
      for _, p in ipairs(best) do
        keep[#keep + 1] = p
      end
    end
  end
  return keep
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
  -- Server racks against the north wall either side of the way out, and
  -- the consoles' cables run up the floor to the slabs.
  for _, c in ipairs({ 23, 31, 33 }) do
    cover(map, "rack", X(c) + 4, Y(z.r0) + 4, 2 * T - 8, 44)
  end
  for _, c in ipairs({ 23, 26, 29 }) do
    flat(map, "cables", X(c + 1) - 12, Y(71), 24, 3 * T + 20, { seed = rng:random(1000) })
  end

  -- Crew Quarters: bunks along both walls, lockers at the end.
  z = rooms["Crew Quarters"]
  for r = z.r0 + 4, z.r1 - 1, 3 do
    cover(map, "bunk", X(z.c0), Y(r), 2 * T, 56)
    cover(map, "bunk", X(z.c1 - 1), Y(r), 2 * T, 56)
  end
  cover(map, "lockers", X(z.c0 + 3), Y(z.r1) + 24, 5 * T, 40)
  -- A footlocker at the foot of every bunk, a rug down the aisle, clothes
  -- dropped where they were taken off.
  for r = z.r0 + 4, z.r1 - 1, 3 do
    cover(map, "footlocker", X(z.c0 + 2) + 4, Y(r) + 10, 30, 36)
    cover(map, "footlocker", X(z.c1 - 1) - 34, Y(r) + 10, 30, 36)
  end
  flat(map, "rug", X(z.c0 + 3.25), Y(z.r0 + 1), 4.5 * T, 10 * T)
  flat(map, "laundry", X(z.c0 + 2.3), Y(z.r0 + 2), 50, 40)
  flat(map, "laundry", X(z.c1 - 2), Y(z.r1 - 1.5), 50, 40)

  -- The Mess: tables in rows, a serving counter down the east wall.
  z = rooms["The Mess"]
  for c = z.c0 + 2, z.c1 - 3, 4 do
    for r = z.r0 + 4, z.r1 - 2, 4 do
      cover(map, "table", X(c), Y(r), 2 * T, T)
      light(map, X(c + 1), Y(r) + 32, 110, EternalMood.LAMP, 0.35)
    end
  end
  cover(map, "counter", X(z.c1) + 16, Y(z.r0 + 3), 40, 7 * T)
  -- Chairs pushed back from the tables, vending machines on the west wall,
  -- lunch on the floor where it was dropped.
  for c = z.c0 + 2, z.c1 - 3, 4 do
    for r = z.r0 + 4, z.r1 - 2, 4 do
      for _, dx in ipairs({ 16, 2 * T - 44 }) do
        cover(map, "chair", X(c) + dx, Y(r) - 32, 28, 28, false)
        cover(map, "chair", X(c) + dx, Y(r) + T + 4, 28, 28, false)
      end
    end
  end
  for _, r in ipairs({ z.r0 + 1, z.r0 + 2.2 }) do
    cover(map, "vending", X(z.c0) + 4, Y(r), 44, 64)
  end
  for _, p in ipairs({ { 4.4, 6.6 }, { 7.6, 3.2 }, { 2.3, 10.5 } }) do
    flat(map, "spill", X(z.c0 + p[1]), Y(z.r0 + p[2]), 52, 40, { angle = rng:random() * 6, seed = rng:random(1000) })
  end
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
  -- Cables between the desks, coffee on the carpet.
  for _, r in ipairs({ z.r0 + 7, z.r0 + 15 }) do
    flat(map, "cables", X(z.c0 + 5), Y(r) + 6, 2 * T, 24, { seed = rng:random(1000) })
  end
  for _, p in ipairs({ { 5.2, 6.4 }, { 8.6, 11.2 }, { 4.6, 17.4 } }) do
    flat(map, "spill", X(z.c0 + p[1]), Y(z.r0 + p[2]), 44, 34, { angle = rng:random() * 6, seed = rng:random(1000) })
  end

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
  -- Hazard paint round the catwalk, the core's cables up to the north wall,
  -- coolant that leaked.
  flat(map, "hazardbox", mx - 4.5 * T - 14, my - 4.5 * T - 14, 9 * T + 28, 9 * T + 28)
  flat(map, "cables", mx - 12, Y(z.r0), 24, my - 4.5 * T - Y(z.r0) - 16, { seed = rng:random(1000) })
  flat(map, "oil", X(z.c0 + 3), Y(z.r1 - 4), 90, 50)
  flat(map, "oil", X(z.c1 - 5), Y(z.r0 + 4), 70, 40)

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
  -- Hazmat lockers against the north wall, clear of the way up; paint
  -- round every clump of barrels.
  for k = 0, 2 do
    cover(map, "hazmat", X(z.c0) + 8 + k * 50, Y(z.r0) + 4, 44, 40)
  end
  for _, p in ipairs({ { 2, 3 }, { 8, 2 }, { 3, 12 }, { 9, 15 }, { 5, 8 } }) do
    flat(map, "hazardbox", X(z.c0 + p[1]) - 12, Y(z.r0 + p[2]) - 12, 100, 100)
  end

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
  -- The workshop along the walls: a workbench and tool chests, tyres
  -- stacked, fuel drums; oil and tyre marks where the loaders have been,
  -- pallets left out.
  cover(map, "workbench", X(15), Y(z.r0) + 4, 3 * T, 44)
  cover(map, "toolchest", X(18.5), Y(z.r0) + 4, 48, 40)
  cover(map, "tires", X(37), Y(z.r0) + 6, 56, 56, true, { round = true })
  for k = 0, 3 do
    cover(map, "barrel", X(48) + 4 + (k % 2) * 40, Y(10.3) + math.floor(k / 2) * 40, 36, 36, true,
      { round = true, red = k == 2 })
  end
  cover(map, "tires", X(14), Y(z.r1 + 1) - 62, 56, 56, true, { round = true })
  cover(map, "toolchest", X(22), Y(z.r1 + 1) - 44, 48, 40)
  cover(map, "workbench", X(36), Y(z.r1 + 1) - 48, 3 * T, 44)
  for _, o in ipairs({ { 20, 9, 70, 40 }, { 30, 15, 90, 50 }, { 41.5, 15.6, 60, 36 }, { 13, 13.5, 80, 44 } }) do
    flat(map, "oil", X(o[1]), Y(o[2]), o[3], o[4])
  end
  flat(map, "skid", X(15), Y(9), 140, 60)
  flat(map, "skid", X(33), Y(12.6), 160, 70)
  flat(map, "pallet", X(31), Y(18.2), 96, 56)
  flat(map, "pallet", X(17), Y(18.3), 80, 52)
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
    kind = "floor-manager",
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

  -- Each mob at its meal, a Mecha Zombie walking round it (`feast`).
  local guarded = feast(map, rng, g)

  -- The mess the night left, room by room (`clutter`): kept off everyone's
  -- spots and the doorways, and only where it fits on the floor.
  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY }, { x = horde.boss.x, y = horde.boss.y } }
  for _, p in ipairs(guarded) do
    avoid[#avoid + 1] = p
  end
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
  ["Downtown"] = { bin = 3, tipped = 4, trash = 6, papers = 6, blood = 4, scorch = 5, glass = 5, debris = 6,
    oil = 3 },
  ["The Crater"] = { scorch = 8, blood = 4, glass = 3, trash = 3 },
  ["The Boulevard"] = { bin = 2, tipped = 3, trash = 4, papers = 4, blood = 5, scorch = 6, glass = 3, debris = 6,
    oil = 4, skid = 3 },
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
  local yards = {} -- the front yards, in tiles: what was left in them goes in last
  local function houses(r0, r1)
    local r = r0
    while r + 3 <= r1 do
      local r2 = math.min(r + 5, r1)
      for _, side in ipairs({ { 3, 8, 9, 12 }, { 31, 36, 27, 30 } }) do
        local b = block(side[1], r, side[2], r2, "house", rng:random() < 0.4)
        ground(side[3], r, side[4], r2, "lawn")
        yards[#yards + 1] = { c0 = side[3], c1 = side[4], r0 = r, r1 = r2 }
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
  cover(map, "crater", X(15), Y(45), 10 * T, 13 * T, true, { round = true, low = true, seed = rng:random(1000) })
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
  for r = 18, 35, 5 do -- none in front of the gate: that's his
    cover(map, "tree", X(19) + 32, Y(r), 64, 64, true, { round = true, planter = true })
  end
  for _, p in ipairs({ { 11, 26 }, { 25, 26 }, { 10, 19 }, { 26, 19 } }) do -- clear of the gate: that's his
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
  post("guard", 12, 18.6, S)
  post("guard", 28, 18.6, S)
  post("overtime", 12, 6.5, S) -- by the starport's gate
  post("staffer", 10, 20, E)
  post("staffer", 30, 30, W)
  patrol({ "guard", "staffer", "staffer" }, { { 11, 30 }, { 28, 30 }, { 28, 18 }, { 11, 18 } })
  mob(12, 34, 7, 420)
  mob(27.5, 21, 6, 420)
  mob(27.5, 9, 6, 400)
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

  -- The Dread Knights (eternal-mood/dread_knight.lua): one on the road past
  -- the overpass's gap, one before the Boulevard's sandbags.
  horde.knights = {
    { x = math.floor(X(20)), y = math.floor(Y(72)), facing = S, count = 1, wake = 480 },
    { x = math.floor(X(20)), y = math.floor(Y(32)), facing = S, count = 1, wake = 520 },
  }

  -- The Mancouchbus (eternal-mood/mancubus.lua) in his recliner in front
  -- of the starport's gate, facing down the Boulevard: he wakes when
  -- somebody comes up past the burning tower (`wake`), never leaves the
  -- Boulevard (`zone`), and keeps the gate (`gate`) closed until he is down.
  horde.boss = {
    kind = "mancubus", x = math.floor(X(20)), y = math.floor(Y(10)), facing = S,
    zone = { x0 = X(7), y0 = Y(2), x1 = X(33), y1 = Y(38) },
    wake = { x0 = X(7), y0 = Y(2), x1 = X(33), y1 = Y(30) },
    gate = { x = X(14), y = Y(2), w = 12 * T, h = 2 * T },
  }

  -- Everyone comes down the shuttle's ramp into the Depot; the way home is
  -- back by the shuttle, well clear of where they arrive.
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = X(17) + (i % 6) * 2 * T + 32, y = Y(148) + math.floor(i / 6) * 96, angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(20)), math.floor(Y(156))

  -- Each mob at its meal, a Mecha Zombie walking round it (`feast`).
  local guarded = feast(map, rng, g)

  -- The mess, stretch by stretch, kept off everyone's spots.
  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY } }
  for _, p in ipairs(guarded) do
    avoid[#avoid + 1] = p
  end
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
  -- What people left in their front yards: something to play on, a garden
  -- bed gone to ash, a chair, a bike, the mailbox, a kennel now and then;
  -- and hydrants and debris along Downtown's sidewalks.
  for _, y in ipairs(yards) do
    local kinds = { gardenbed = 1, mailbox = 1, lawnchair = rng:random(0, 2) }
    local roll = rng:random()
    if roll < 0.3 then
      kinds.trampoline = 1
    elseif roll < 0.55 then
      kinds.swing = 1
    end
    kinds.bike = rng:random() < 0.4 and 1 or 0
    kinds.doghouse = rng:random() < 0.3 and 1 or 0
    clutter(map, rng, g, y, kinds, avoid)
  end
  for _, c0 in ipairs({ 13, 25 }) do
    clutter(map, rng, g, { c0 = c0, c1 = c0 + 1, r0 = 66, r1 = 107 }, { hydrant = 3, debris = 2 }, avoid)
  end

  map.openKinds = { walk = true }
  commit(map, g)
end

-- The Foundry -------------------------------------------------------------------

EternalMood.MOLTEN = { 1.00, 0.42, 0.08 } -- lava, in the vats, the moat and the Crucible
EternalMood.PORTAL = { 1.00, 0.20, 0.30 } -- the way down into Heck

EternalMood.FOUNDRY_POSTERS = {
  "NOW HIRING. SOULS PREFERRED.",
  "UAC FOUNDRY: WE MELT HECK",
  "DAYS WITHOUT A LOST SOUL: 0",
  "HARD HATS ON. HORNS OPTIONAL.",
  "MIND THE LAVA",
  "DO NOT RIDE THE BELTS",
}

-- The rooms, in tiles (inclusive), bottom to top, each with its floor. The
-- south half is still the UAC's; going north it's Heck's (`map.heckFrom`).
EternalMood.FOUNDRY = {
  { name = "The Landing Pad", c0 = 4, r0 = 50, c1 = 17, r1 = 59, floor = "concrete" },
  { name = "The Loading Bay", c0 = 20, r0 = 52, c1 = 35, r1 = 57, floor = "plate" },
  { name = "The Front Office", c0 = 38, r0 = 50, c1 = 51, r1 = 59, floor = "lino" },
  { name = "The Conveyors", c0 = 4, r0 = 38, c1 = 51, r1 = 47, floor = "plate" },
  { name = "The Smelters", c0 = 4, r0 = 22, c1 = 51, r1 = 35, floor = "grate" },
  { name = "The Crucible", c0 = 8, r0 = 3, c1 = 47, r1 = 19, floor = "rock" },
}

EternalMood.FOUNDRY_DOORS = {
  { c0 = 18, r0 = 53, c1 = 19, r1 = 56 }, -- the Pad through to the Loading Bay
  { c0 = 36, r0 = 53, c1 = 37, r1 = 56 }, -- the Loading Bay through to the Front Office
  { c0 = 9, r0 = 48, c1 = 11, r1 = 49, ns = true }, -- up into the Conveyors from the Pad...
  { c0 = 26, r0 = 48, c1 = 29, r1 = 51, ns = true }, -- ...the Loading Bay...
  { c0 = 44, r0 = 48, c1 = 46, r1 = 49, ns = true }, -- ...and the Front Office
  { c0 = 9, r0 = 36, c1 = 11, r1 = 37, ns = true }, -- up into the Smelters
  { c0 = 26, r0 = 36, c1 = 29, r1 = 37, ns = true },
  { c0 = 44, r0 = 36, c1 = 46, r1 = 37, ns = true },
  { c0 = 12, r0 = 20, c1 = 14, r1 = 21, ns = true }, -- up into the Crucible
  { c0 = 26, r0 = 20, c1 = 29, r1 = 21, ns = true },
  { c0 = 41, r0 = 20, c1 = 43, r1 = 21, ns = true },
}

-- The belts across the Conveyors (rows, inclusive) and which way they run.
EternalMood.BELTS = { { r0 = 39, r1 = 40, dir = 1 }, { r0 = 42, r1 = 43, dir = -1 }, { r0 = 45, r1 = 46, dir = 1 } }
EternalMood.BELT_SPEED = 70 -- px/s: faster than walking (45), slower than a sprint (170)

EternalMood.FOUNDRY_CLUTTER = {
  ["The Landing Pad"] = { papers = 1, scorch = 1, oil = 2 },
  ["The Loading Bay"] = { bin = 1, tipped = 1, trash = 2, blood = 1, papers = 1, oil = 2, skid = 1 },
  ["The Front Office"] = { papers = 4, fallen = 2, blood = 1, tipped = 1 },
  ["The Conveyors"] = { scorch = 2, blood = 1, trash = 1, debris = 2 },
  ["The Smelters"] = { scorch = 4, blood = 2, bones = 3, glass = 1, slag = 6, ingots = 3, debris = 3 },
  ["The Crucible"] = { scorch = 3, blood = 2, bones = 10, spike = 6, skulls = 5 },
}

local function buildFoundry(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local cols, rows = map.cols, map.rows
  local N, E, S, W = -math.pi / 2, 0, math.pi / 2, math.pi
  map.base = { x = X(2), y = Y(2), w = (cols - 4) * T, h = (rows - 4) * T }
  map.outside = "tarmac" -- the starport's, past the shed's walls
  map.heckFrom = Y(36) -- north of this the walls are Heck's rock
  map.belts = {}
  local rooms = {}
  for _, z in ipairs(EternalMood.FOUNDRY) do
    g.fill(z.c0, z.r0, z.c1, z.r1, "walk")
    rooms[z.name] = z
    map.zones[#map.zones + 1] = {
      name = z.name, x0 = X(z.c0), y0 = Y(z.r0), x1 = X(z.c1 + 1), y1 = Y(z.r1 + 1), floor = z.floor,
    }
    if z.r0 >= 36 then -- the UAC's half: strip lights, some on the blink
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
  end
  for _, d in ipairs(EternalMood.FOUNDRY_DOORS) do
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

  -- The Landing Pad: the shuttle down from Earth on its pad, crates.
  local z = rooms["The Landing Pad"]
  flat(map, "pad", X(4), Y(50), 8 * T, 10 * T)
  cover(map, "shuttle", X(5), Y(50) + 16, 6 * T, 8 * T)
  for _, p in ipairs({ { 14, 58 }, { 16, 58 } }) do
    cover(map, "crate", X(p[1]), Y(p[2]), 2 * T - 8, 2 * T - 8)
  end
  light(map, X(8), Y(54), 300, EternalMood.ALARM, 0.3)
  poster(map, X(12), Y(z.r0), EternalMood.FOUNDRY_POSTERS[1])
  flat(map, "cables", X(12.2), Y(51), 24, 5 * T, { seed = rng:random(1000) }) -- the fuel hose to the shuttle
  flat(map, "hazardbox", X(13.6), Y(57.6), 4 * T + 16, 2 * T + 16)

  -- The Loading Bay: crates, barrels and a parked loader.
  z = rooms["The Loading Bay"]
  for _, p in ipairs({ { 21, 52 }, { 23, 56 }, { 32, 52 }, { 34, 56 } }) do
    cover(map, "crate", X(p[1]), Y(p[2]), 2 * T - 8, 2 * T - 8)
  end
  cover(map, "loader", X(30), Y(54), 2 * T, 3 * T)
  flat(map, "pallet", X(26.5), Y(52.2), 96, 56)
  cover(map, "tires", X(20) + 8, Y(54.5), 56, 56, true, { round = true })
  for k = 0, 2 do
    cover(map, "barrel", X(25) + k * 40, Y(56) + 16, 36, 36, true, { round = true, red = k == 1 })
  end
  poster(map, X(21), Y(z.r0), EternalMood.FOUNDRY_POSTERS[4])

  -- The Front Office: Dr. Seek's booth, his jar on the desk in it, desks
  -- and filing round it.
  z = rooms["The Front Office"]
  cover(map, "booth", X(42), Y(52), 5 * T, 3 * T)
  light(map, X(44.5), Y(53.5), 200, EternalMood.SCREEN, 0.5)
  for _, p in ipairs({ { 39, 57 }, { 47, 57 } }) do
    cover(map, "desk", X(p[1]), Y(p[2]), 2 * T, 40)
    cover(map, "chair", X(p[1]) + 44, Y(p[2]) + 46, 28, 28, false)
    light(map, X(p[1] + 1), Y(p[2]) + 20, 90, EternalMood.SCREEN, 0.35)
  end
  for r = 51, 57, 3 do
    cover(map, "cabinet", X(z.c1) + 20, Y(r), 36, 2 * T - 16)
  end
  cover(map, "cooler", X(z.c0) + 8, Y(z.r0) + 8, 40, 40)
  poster(map, X(39), Y(z.r0), EternalMood.FOUNDRY_POSTERS[3])
  cover(map, "copier", X(43.5), Y(z.r1 + 1) - 48, 64, 44) -- against the south wall, between the desks
  flat(map, "cables", X(41), Y(57) + 10, 6 * T, 24, { seed = rng:random(1000) })
  flat(map, "spill", X(40.6), Y(55.4), 44, 34, { angle = rng:random() * 6, seed = rng:random(1000) })

  -- The Conveyors: belts right across the hall, each running its own way,
  -- the hoppers they feed at the walls, a walkway between each.
  z = rooms["The Conveyors"]
  for _, b in ipairs(EternalMood.BELTS) do
    local x, y, w, h = X(z.c0), Y(b.r0), (z.c1 - z.c0 + 1) * T, (b.r1 - b.r0 + 1) * T
    local belt = { x = x, y = y, w = w, h = h, vx = b.dir * EternalMood.BELT_SPEED, vy = 0 }
    map.belts[#map.belts + 1] = belt
    flat(map, "belt", x, y, w, h, { dir = b.dir, speed = EternalMood.BELT_SPEED, seed = rng:random(1000) })
  end
  for _, c in ipairs({ 6, 20, 35, 49 }) do
    light(map, X(c), Y(z.r0) + 20, 160, EternalMood.STRIP, 0.25)
  end
  poster(map, X(16), Y(z.r0), EternalMood.FOUNDRY_POSTERS[6])
  poster(map, X(33), Y(z.r0), EternalMood.FOUNDRY_POSTERS[2])

  -- The Smelters: vats of lava with walkways between, chains hanging,
  -- pipes; Heck's rock and bone coming up through the floor, more of it
  -- further north, and spires of it.
  z = rooms["The Smelters"]
  for _, c in ipairs({ 12, 28, 44 }) do
    for _, r in ipairs({ 25.5, 31.5 }) do
      cover(map, "vat", X(c) - 1.5 * T, Y(r) - 1.5 * T, 3 * T, 3 * T, true,
        { round = true, low = true, seed = rng:random(1000) })
      light(map, X(c), Y(r), 320, EternalMood.MOLTEN, 0.6)
    end
  end
  for _, p in ipairs({ { 20, 24 }, { 36, 24 }, { 20, 30 }, { 36, 30 }, { 7, 28 }, { 49, 28 } }) do
    flat(map, "chain", X(p[1]), Y(p[2]), 24, 2 * T, { seed = rng:random(1000) })
  end
  for k = 0, 14 do -- the growth, thicker north
    local r = z.r0 + math.floor((rng:random() ^ 1.6) * (z.r1 - z.r0 - 1))
    local c = z.c0 + rng:random() * (z.c1 - z.c0 - 2)
    flat(map, "growth", X(c), Y(r), 2 * T, 2 * T, { seed = rng:random(1000) + k })
  end
  for _, p in ipairs({ { 6, 23 }, { 50, 24 }, { 20, 22.5 }, { 37, 22.5 } }) do
    cover(map, "spire", X(p[1]) - 24, Y(p[2]) - 24, 48, 48, true, { round = true, seed = rng:random(1000) })
  end
  -- Pipes along the south wall between the doorways down, ingot moulds by
  -- the vats, the last of each row still hot.
  for _, span in ipairs({ { 13, 24 }, { 31, 42 } }) do
    cover(map, "pipe", X(span[1]), Y(z.r1 + 1) - 20, (span[2] - span[1] + 1) * T, 16)
  end
  for _, c in ipairs({ 12, 28, 44 }) do
    flat(map, "molds", X(c) - 1.5 * T, Y(28.5) - 18, 3 * T, 36, { seed = rng:random(1000) })
  end
  poster(map, X(30), Y(z.r0), EternalMood.FOUNDRY_POSTERS[5])

  -- The Crucible: a pit of lava in a stone ring, a lava moat round the
  -- ring with a bridge in from each side, and the portal down into Heck
  -- behind it all, at the top.
  z = rooms["The Crucible"]
  local function lava(c0, r0, c1, r1)
    local w, h = (c1 - c0 + 1) * T, (r1 - r0 + 1) * T
    cover(map, "lava", X(c0), Y(r0), w, h, true, { low = true, seed = rng:random(1000) })
  end
  lava(21, 6, 26, 7) -- the moat: north (either side of its bridge)...
  lava(30, 6, 35, 7)
  lava(21, 17, 26, 18) -- ...south...
  lava(30, 17, 35, 18)
  lava(21, 8, 22, 10) -- ...west...
  lava(21, 14, 22, 16)
  lava(34, 8, 35, 10) -- ...and east
  lava(34, 14, 35, 16)
  for _, b in ipairs({ { 27, 6, 29, 7 }, { 27, 17, 29, 18 }, { 21, 11, 22, 13 }, { 34, 11, 35, 13 } }) do
    flat(map, "bridge", X(b[1]), Y(b[2]), (b[3] - b[1] + 1) * T, (b[4] - b[2] + 1) * T, { ns = b[2] ~= 11 })
  end
  flat(map, "ring", X(23), Y(8), 11 * T, 9 * T)
  cover(map, "crucible", X(26), Y(10), 5 * T, 5 * T, true, { round = true, low = true, seed = rng:random(1000) })
  light(map, X(28.5), Y(12.5), 640, EternalMood.MOLTEN, 0.8)
  for _, p in ipairs({ { 21, 6 }, { 30, 6 }, { 21, 17 }, { 30, 17 } }) do
    light(map, X(p[1] + 3), Y(p[2] + 1), 260, EternalMood.MOLTEN, 0.4)
  end
  flat(map, "gateway", X(26), Y(3), 5 * T, 2 * T)
  light(map, X(28.5), Y(4), 360, EternalMood.PORTAL, 0.7)
  map.exitX, map.exitY = math.floor(X(28.5)), math.floor(Y(4.5))
  for k = 0, 10 do
    flat(map, "growth", X(z.c0 + rng:random() * (z.c1 - z.c0 - 2)), Y(z.r0 + rng:random() * (z.r1 - z.r0 - 2)),
      2 * T, 2 * T, { seed = rng:random(1000) + 50 + k })
  end
  for _, p in ipairs({ { 11, 6 }, { 15, 15 }, { 44, 6 }, { 40, 15 }, { 11, 17 } }) do
    cover(map, "spire", X(p[1]) - 28, Y(p[2]) - 28, 56, 56, true, { round = true, seed = rng:random(1000) })
  end
  -- Braziers burning at the flanks of the way to the portal and the bridge south.
  for _, p in ipairs({ { 18, 4.5 }, { 38.5, 4.5 }, { 18, 18.5 }, { 38.5, 18.5 } }) do
    cover(map, "brazier", X(p[1]) - 22, Y(p[2]) - 22, 44, 44, true, { round = true, seed = rng:random(1000) })
    map.flickers[#map.flickers + 1] = { x = X(p[1]), y = Y(p[2]), r = 230, color = EternalMood.MOLTEN, a = 0.5,
      seed = rng:random(1000), fire = true }
  end

  -- Heck's horde (eternal-mood/horde.lua), in tiles. The UAC's half has
  -- its possessed staff at work, guards on the way north, interns about;
  -- the Smelters and the Crucible are thick with imps and mobs, two
  -- Cacodaemons over the Crucible's pit.
  local horde = { posts = {}, vents = {}, patrols = {}, mobs = {}, cacos = {} }
  map.horde = horde
  local function post(rank, c, r, watch)
    horde.posts[#horde.posts + 1] = { rank = rank, x = math.floor(X(c)), y = math.floor(Y(r)), watch = watch }
  end
  local function vent(c, r, out, count)
    local x, y = math.floor(X(c)), math.floor(Y(r))
    horde.vents[#horde.vents + 1] = { x = x, y = y, out = out, count = count }
    flat(map, "vent", x - 22, y - 16, 44, 32)
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
  -- The Loading Bay and the Front Office.
  post("staffer", 22, 54.5, W)
  post("staffer", 33.5, 54.5, W)
  post("guard", 28, 52.5, S)
  post("staffer", 40.5, 58.6, N)
  post("staffer", 48.5, 58.6, N)
  post("guard", 45.5, 50.6, S)
  patrol({ "staffer", "staffer" }, { { 24.5, 53 }, { 29.5, 53 } })
  mob(49.5, 53.5, 5, 380)
  -- The Conveyors: guards at the doors up, staff on the belts (going round
  -- and round), a patrol along the middle walkway.
  post("guard", 10.5, 38.4, S)
  post("guard", 28, 38.4, S)
  post("guard", 45.5, 38.4, S)
  post("staffer", 18, 42.5, S)
  post("staffer", 38, 39.5, S)
  post("staffer", 30, 45.5, S)
  patrol({ "guard", "staffer" }, { { 6, 44.5 }, { 49.5, 44.5 } })
  mob(7, 41.5, 6, 420)
  -- The Smelters.
  post("overtime", 28, 23.4, S)
  post("staffer", 6, 32, E)
  post("staffer", 20, 28, E)
  post("staffer", 36, 28, W)
  post("staffer", 50, 32, W)
  patrol({ "guard", "staffer", "staffer" }, { { 7, 34.5 }, { 49, 34.5 }, { 49, 22.6 }, { 7, 22.6 } })
  mob(20, 33.5, 6, 420)
  mob(36, 26.5, 6, 420)
  vent(5, 25.5, E, 3)
  vent(50.5, 30.5, W, 3)
  vent(28, 28.5, S, 3)
  -- The Crucible.
  mob(14, 8, 6, 420)
  mob(42, 8, 6, 420)
  vent(10, 18, E, 2)
  vent(45.5, 18, W, 2)
  horde.cacos[#horde.cacos + 1] = { x = math.floor(X(28.5)), y = math.floor(Y(12.5)), count = 2, wake = 620 }
  -- The Dread Knights (eternal-mood/dread_knight.lua), on the Smelters'
  -- walkways, one either side.
  horde.knights = {
    { x = math.floor(X(14)), y = math.floor(Y(31)), facing = S, count = 1, wake = 460 },
    { x = math.floor(X(42)), y = math.floor(Y(26)), facing = S, count = 1, wake = 460 },
  }
  -- The Baron of Heck (eternal-mood/baron.lua) on the ring south of the
  -- pit, facing the south bridge: he wakes when somebody comes over a
  -- bridge (`wake`, the moat's box) or into his sight, then goes after
  -- them wherever they are, calls imps up out of the pit's lava (`pit`),
  -- and keeps the portal (`portal`) sealed until his key is picked up.
  horde.boss = {
    kind = "baron", x = math.floor(X(28.5)), y = math.floor(Y(15.6)), facing = S,
    wake = { x0 = X(21), y0 = Y(6), x1 = X(36), y1 = Y(19) },
    pit = { x = math.floor(X(28.5)), y = math.floor(Y(12.5)), r = 3.3 * T },
    portal = { x = X(26), y = Y(3), w = 5 * T, h = 2 * T },
  }

  -- Everyone comes down the shuttle's ramp onto the Pad; the way home is
  -- back by the shuttle's tail.
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = math.floor(X(12.5) + (i % 3) * 96), y = math.floor(Y(51.5) + math.floor(i / 3) * 96), angle = -math.pi / 2,
    }
  end
  map.cx, map.cy = math.floor(X(7.5)), math.floor(Y(59))

  -- Each mob at its meal, a Mecha Zombie walking round it (`feast`).
  local guarded = feast(map, rng, g)
  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY } }
  for _, p in ipairs(guarded) do
    avoid[#avoid + 1] = p
  end
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
  for _, room in ipairs(EternalMood.FOUNDRY) do
    if room.name ~= "The Conveyors" then -- nothing lies still on a belt
      clutter(map, rng, g, room, EternalMood.FOUNDRY_CLUTTER[room.name] or {}, avoid, EternalMood.FOUNDRY_DOORS)
    end
  end

  map.openKinds = { walk = true }
  commit(map, g)
end

-- Heck --------------------------------------------------------------------------

-- The stretches, bottom to top (rows, inclusive), all the map's width.
EternalMood.HECK = {
  { name = "The Arrival Shelf", r0 = 84, r1 = 92, c0 = 21, c1 = 38, floor = "rock" },
  { name = "The Bone Bridges", r0 = 59, r1 = 83, c0 = 3, c1 = 56, floor = "rock" },
  { name = "The Altar Fields", r0 = 30, r1 = 58, c0 = 3, c1 = 56, floor = "rock" },
  { name = "The Mattress", r0 = 7, r1 = 26, c0 = 10, c1 = 49, floor = "rock" },
}

-- Rock in the sea of lava across the Bone Bridges (tiles, inclusive): the
-- islands, and the bones bridging them. Everything else in that band is
-- lava, and burns.
EternalMood.HECK_ISLANDS = {
  { 24, 75, 35, 79 }, -- the south island, off the shelf
  { 6, 66, 15, 71 }, -- west
  { 44, 66, 53, 71 }, -- east
  { 25, 61, 34, 65 }, -- the middle
}
EternalMood.HECK_BRIDGES = {
  { 28, 80, 31, 83, ns = true }, -- the shelf up to the south island
  { 13, 76, 23, 77 }, { 10, 72, 12, 77, ns = true }, -- west: across, then up to the west island
  { 36, 76, 46, 77 }, { 47, 72, 49, 77, ns = true }, -- east
  { 10, 59, 12, 65, ns = true }, { 47, 59, 49, 65, ns = true }, -- the west and east islands up to the Fields
  { 29, 66, 30, 74, ns = true }, { 29, 59, 30, 60, ns = true }, -- the narrow way up the middle
}

EternalMood.HECK_CLUTTER = {
  ["The Arrival Shelf"] = { bones = 2, scorch = 1, skulls = 2 },
  ["The Altar Fields"] = { bones = 14, scorch = 8, blood = 5, skulls = 8, spike = 8, ribcage = 5, runes = 3 },
  ["The Mattress"] = { bones = 6, scorch = 3, skulls = 3, drag = 4 }, -- flat only: its owner's arena
}

local function buildHeck(map, rng, T)
  local g = grid(map, T)
  local X, Y = g.X, g.Y
  local cols, rows = map.cols, map.rows
  local N, E, S, W = -math.pi / 2, 0, math.pi / 2, math.pi
  map.base = { x = X(2), y = Y(2), w = (cols - 4) * T, h = (rows - 4) * T }
  map.outside = "abyss"
  map.heckFrom = Y(rows) -- it's all Heck's rock
  local rooms = {}
  for _, z in ipairs(EternalMood.HECK) do
    g.fill(z.c0, z.r0, z.c1, z.r1, "walk")
    rooms[z.name] = z
    map.zones[#map.zones + 1] = {
      name = z.name, x0 = X(z.c0), y0 = Y(z.r0), x1 = X(z.c1 + 1), y1 = Y(z.r1 + 1), floor = z.floor,
    }
  end
  -- The way up from the Fields onto the Mattress's plateau: a wide ramp,
  -- steps cut into the rock.
  g.fill(22, 27, 37, 29, "walk")
  map.zones[#map.zones + 1] = { name = "The Mattress", x0 = X(22), y0 = Y(27), x1 = X(38), y1 = Y(30), floor = "steps" }

  --- Lava over every tile of `lava` (c -> r -> true), merged into as few
  --- rectangles as it takes, each its own glow.
  local function pour(lava, c0, r0, c1, r1)
    local done = {}
    for r = r0, r1 do
      local c = c0
      while c <= c1 do
        if lava[c] and lava[c][r] and not (done[c] and done[c][r]) then
          local e = c
          while e + 1 <= c1 and lava[e + 1] and lava[e + 1][r] and not (done[e + 1] and done[e + 1][r]) do
            e = e + 1
          end
          local b = r
          local function rowFull(rr)
            for cc = c, e do
              if not (lava[cc] and lava[cc][rr]) or (done[cc] and done[cc][rr]) then
                return false
              end
            end
            return true
          end
          while b + 1 <= r1 and rowFull(b + 1) do
            b = b + 1
          end
          for cc = c, e do
            done[cc] = done[cc] or {}
            for rr = r, b do
              done[cc][rr] = true
            end
          end
          local w, h = (e - c + 1) * T, (b - r + 1) * T
          cover(map, "lava", X(c), Y(r), w, h, true, { low = true, seed = rng:random(1000) })
          if w * h >= 4 * T * T then
            light(map, X(c) + w / 2, Y(r) + h / 2, math.min(520, 120 + math.sqrt(w * h) * 0.8), EternalMood.MOLTEN,
              0.55)
          end
          c = e + 1
        else
          c = c + 1
        end
      end
    end
  end
  local function rect(list, c0, r0, c1, r1)
    for c = c0, c1 do
      list[c] = list[c] or {}
      for r = r0, r1 do
        list[c][r] = true
      end
    end
  end

  -- The Bone Bridges: lava from wall to wall, the islands and bridges out of it.
  local z = rooms["The Bone Bridges"]
  local lava = {}
  rect(lava, z.c0, z.r0, z.c1, z.r1)
  for _, i in ipairs(EternalMood.HECK_ISLANDS) do
    for c = i[1], i[3] do
      for r = i[2], i[4] do
        lava[c][r] = nil
      end
    end
  end
  for _, b in ipairs(EternalMood.HECK_BRIDGES) do
    for c = b[1], b[3] do
      for r = b[2], b[4] do
        lava[c][r] = nil
      end
    end
    flat(map, "bonebridge", X(b[1]), Y(b[2]), (b[3] - b[1] + 1) * T, (b[4] - b[2] + 1) * T,
      { ns = b.ns, seed = rng:random(1000) })
  end
  pour(lava, z.c0, z.r0, z.c1, z.r1)

  -- The Altar Fields: open rock, altars and spikes for cover, fire pits,
  -- and in the east a lake of lava with a pizza box sinking in it.
  local lake = {}
  rect(lake, 46, 34, 56, 50)
  rect(lake, 43, 38, 45, 47)
  pour(lake, 43, 34, 56, 50)
  cover(map, "pizzabox", X(46) + 16, Y(37), 8 * T, 8 * T, false, { angle = 0.18 }) -- over the lava, not solid
  map.pizza = { x = X(50), y = Y(41) }
  for _, p in ipairs({ { 9, 36 }, { 20, 34 }, { 33, 33 }, { 13, 46 }, { 26, 42 }, { 37, 48 }, { 8, 54 }, { 22, 52 },
    { 32, 55 } }) do
    cover(map, "altar", X(p[1]), Y(p[2]), 2 * T, T, true, { seed = rng:random(1000) })
    light(map, X(p[1] + 1), Y(p[2]) + 32, 140, EternalMood.FIRE, 0.45)
  end
  for _, p in ipairs({ { 15, 40 }, { 30, 38 }, { 6, 44 }, { 39, 41 }, { 18, 49 }, { 28, 47 }, { 41, 54 }, { 14, 56 },
    { 26, 32 }, { 36, 31 } }) do
    cover(map, "spire", X(p[1]) - 24, Y(p[2]) - 24, 48, 48, true, { round = true, seed = rng:random(1000) })
  end
  for _, p in ipairs({ { 18, 38 }, { 34, 44 }, { 10, 51 }, { 28, 57 } }) do
    cover(map, "firepit", X(p[1]) - 40, Y(p[2]) - 40, 80, 80, true, { round = true, low = true,
      seed = rng:random(1000) })
    map.flickers[#map.flickers + 1] = { x = X(p[1]), y = Y(p[2]), r = 260, color = EternalMood.FIRE, a = 0.7,
      seed = rng:random(1000), fire = true }
  end

  -- Braziers at the Fields' edges, lighting them.
  for _, p in ipairs({ { 4.5, 33 }, { 54.5, 31.5 }, { 4.5, 49 }, { 52, 53.5 } }) do
    cover(map, "brazier", X(p[1]) - 22, Y(p[2]) - 22, 44, 44, true, { round = true, seed = rng:random(1000) })
    map.flickers[#map.flickers + 1] = { x = X(p[1]), y = Y(p[2]), r = 230, color = EternalMood.FIRE, a = 0.55,
      seed = rng:random(1000), fire = true }
  end

  -- The Mattress: the plateau before the Snooze Gate, worn smooth where
  -- its owner drags its mattress about; the gate at the top, a clock over it.
  cover(map, "snoozegate", X(22), Y(3), 16 * T, 4 * T)
  light(map, X(30), Y(6), 420, EternalMood.PORTAL, 0.6)
  map.exitX, map.exitY = math.floor(X(30)), math.floor(Y(8))
  for _, p in ipairs({ { 12, 9 }, { 47, 9 }, { 12, 24 }, { 47, 24 } }) do
    cover(map, "spire", X(p[1]) - 28, Y(p[2]) - 28, 56, 56, true, { round = true, seed = rng:random(1000) })
  end
  for _, c in ipairs({ 16, 43 }) do
    map.flickers[#map.flickers + 1] = { x = X(c), y = Y(8), r = 240, color = EternalMood.FIRE, a = 0.6,
      seed = rng:random(1000), fire = true }
    flat(map, "fire", X(c) - 30, Y(8) - 30, 60, 60, { seed = rng:random(1000) })
  end

  -- The Arrival Shelf: out of the portal.
  flat(map, "gateway", X(27), Y(89), 6 * T, 2 * T)
  light(map, X(30), Y(90), 300, EternalMood.PORTAL, 0.6)
  for _, p in ipairs({ { 23, 86 }, { 36, 86 } }) do
    cover(map, "spire", X(p[1]) - 24, Y(p[2]) - 24, 48, 48, true, { round = true, seed = rng:random(1000) })
  end

  -- Heck's own (eternal-mood/horde.lua): demons only. Imps up out of the
  -- cracks on the islands and all over the Fields, Cacodaemons over the
  -- lava and the Fields.
  local horde = { posts = {}, vents = {}, patrols = {}, mobs = {}, cacos = {} }
  map.horde = horde
  local function vent(c, r, out, count)
    local x, y = math.floor(X(c)), math.floor(Y(r))
    horde.vents[#horde.vents + 1] = { x = x, y = y, out = out, count = count, look = "crack" }
    flat(map, "crack", x - 22, y - 22, 44, 44)
  end
  local function cacos(c, r, count, wake)
    horde.cacos[#horde.cacos + 1] = { x = math.floor(X(c)), y = math.floor(Y(r)), count = count, wake = wake }
  end
  -- The Bone Bridges.
  vent(26, 77, E, 2)
  vent(10.5, 68.5, E, 3)
  vent(48.5, 68.5, W, 3)
  vent(29.5, 63, S, 2)
  cacos(18, 70, 1, 560)
  cacos(40, 70, 1, 560)
  cacos(30, 60, 1, 520)
  -- The Altar Fields: the biggest crowd on the line.
  vent(7, 57, N, 3)
  vent(52, 56, N, 2)
  vent(16, 45, E, 3)
  vent(31, 51, N, 3)
  vent(24, 37, S, 3)
  vent(38, 35, W, 3)
  vent(9, 32, E, 3)
  cacos(20, 44, 2, 600)
  cacos(36, 38, 1, 600)
  cacos(50, 44, 1, 600) -- over the pizza
  -- The Dread Knights (eternal-mood/dread_knight.lua): three about the
  -- Fields, between the bridges and the ramp up to the Mattress.
  horde.knights = {
    { x = math.floor(X(29)), y = math.floor(Y(47)), facing = S, count = 1, wake = 520 },
    { x = math.floor(X(13)), y = math.floor(Y(38)), facing = S, count = 1, wake = 480 },
    { x = math.floor(X(42.5)), y = math.floor(Y(40)), facing = S, count = 1, wake = 480 },
  }
  -- The Mattress's plateau stays quiet: its owner wants it that way. The
  -- Spider Mattressmind (eternal-mood/mattressmind.lua) on its mattress
  -- before the gate, facing down the ramp: it wakes when somebody comes up
  -- onto the plateau (`wake`), keeps to it and the ramp (`zone`), and keeps
  -- the Snooze Gate (`gate`) locked until it's down.
  horde.boss = {
    kind = "mattressmind", x = math.floor(X(30)), y = math.floor(Y(15)), facing = S,
    zone = { x0 = X(10), y0 = Y(7), x1 = X(50), y1 = Y(30) },
    wake = { x0 = X(10), y0 = Y(7), x1 = X(50), y1 = Y(27) },
    gate = { x = X(22), y = Y(3), w = 16 * T, h = 4 * T },
  }

  -- Everyone comes out of the portal onto the shelf; the way home is back
  -- into it.
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = math.floor(X(24.5) + (i % 6) * 2 * T), y = math.floor(Y(85) + math.floor(i / 6) * 96), angle = N,
    }
  end
  map.cx, map.cy = math.floor(X(30)), math.floor(Y(91))

  local avoid = { { x = map.cx, y = map.cy }, { x = map.exitX, y = map.exitY } }
  for _, list in ipairs({ horde.vents, map.spawns }) do
    for _, p in ipairs(list) do
      avoid[#avoid + 1] = { x = p.x, y = p.y }
    end
  end
  for _, room in ipairs(EternalMood.HECK) do
    if EternalMood.HECK_CLUTTER[room.name] then
      clutter(map, rng, g, room, EternalMood.HECK_CLUTTER[room.name], avoid)
    end
  end

  map.openKinds = { walk = true }
  commit(map, g)
end

EternalMood.builders = {
  fobos = buildFobos,
  earth = buildEarth,
  foundry = buildFoundry,
  heck = buildHeck,
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
