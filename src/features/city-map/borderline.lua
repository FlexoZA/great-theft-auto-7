-- The maps of the Borderline quest line (docs/borderline.md): eight maps on
-- the planet Pandoria, every one walked, everyone travelling north (up the
-- screen) from the arrival at the bottom to the way on at the top:
--   wreck       The Frozen Wreck: Hyperbole's freight yard in the snow,
--               sheds round it, three deep excavations with cranes working
--               over them, Max's derailed train zig-zagging up the
--               middle, a tunnel out at the top
--   landing     Liar's Landing: a frozen container port at dusk, a maze of
--               stacks with painted lanes, a dry dock down the west side,
--               gantry cranes on the quay unloading a freighter, the ferry
--               lift at the top
--   pit         The Bragium Pit: an open-pit mine at dusk, two rings of
--               terraces down to the floor where Wilbur lands, a
--               rim at either end joined to it by one ramp each; cranes
--               over the floor, shafts with headframes, conveyors running
--   prosperity  Prosperity: Max's factory town under a dome at dusk,
--               factory blocks with smoking chimneys on a street grid, two
--               building sites with cranes, his statue in the plaza, a gate
--               at either end
--   refinery    The Refinery: indoors and dark, a river of molten Bragium
--               snaking across the floor, crossed by bridges, tanks and
--               pipes, bridge cranes overhead, a casting pit, steam vents
--   assembly    The Assembly Line: the factory floor, dim, conveyor belts
--               carrying hauler parts across it, welding arms and presses
--               at work, scrap pits, a bridge crane, the Foreman's floor
--   cuts        Thousand Papercuts: a narrow service road winding up a cliff
--               at dusk, the drop on its west side with an ore ropeway
--               down it, the rock on its east, a crane at the bunker's door
--   bunker      The Bunker: its roof at dusk, the arena, a rim of eleven
--               cannons, four engine intakes with their fans turning, a
--               radar, a gantry loading a missile
--
-- So far each is blocked out: floors, walls, cover, the way in and the way
-- on. The robots, bosses and set pieces come in later stages.
--
-- Tiles are "walk"; nil is the map's outside (`map.outside` says what it
-- is: render_borderline.lua draws it), and the layout's walls make it solid.
--
-- What every one leaves on the map, besides tiles, solids and spawns:
--   map.cx, map.cy        the way home (a HOME star in quests), by the arrival
--   map.exitX, map.exitY  the way on: the first player there finishes the level (borderline)
--   map.outside           what the nil tiles are: "works" (the factory's roofs round a yard), "snow"
--                         (snowbanks), "harbour" (the sea north of the quay, snow round the rest),
--                         "rock" (the pit's walls), "dome"
--                         (Prosperity's glass and the snow past it), "plant" (the factory's walls),
--                         "cliff" (Thousand Papercuts: the drop west of the road, the rock east), "sky"
--                         (round the bunker's roof)
--   map.grounds           { x0, y0, x1, y1, floor } the finish of each walked patch, world px, a later one
--                         over an earlier: snow, ice, quay, yard, port (Liar's Landing's slabs), ballast,
--                         gravel, terrace, pitfloor, street, plaza, grate, steel, upper, road, roof
--   map.zones             { name, x0, y0, x1, y1 } the parts of the map, world px
--   map.cover             { kind, x, y, w, h, solid, round, flat, tint } world px; solid ones are in the
--                         solids too (`water` ones, the molten river, stop walking but not rounds or
--                         sight), `flat` ones are walked over. Kinds: carriage, loco, crate, rock, chest,
--                         rails, cave, container, crane, bollard, lift, ledge, ramp, conveyor, crystal,
--                         pad, tower, statue, lawn, billboard, gate, river, bridge, tank, pipe, belt, arm,
--                         press, booth, stairs, bay, boulder, nest, door, cannon, vent, hatch; and the
--                         Wreck's yard: pit (a deep excavation: `water`, no walking in, rounds go over),
--                         shed (`bay` its number), mast (a crane's), flood (a floodlight tower), drum, and
--                         flat: tunnel (`railsX` where rails run in), walkway, zebra, cone, scar (ground
--                         torn up by a carriage), paint (with `text`, `small`, `snowy`); a carriage may be
--                         `burning`; Liar's Landing's: drydock
--                         (`water`, like a pit), foot (a gantry's), bollard (`rope` the world y its mooring
--                         line runs out to), and flat: ship (the freighter in the water), laneline, quayedge,
--                         craneRail, puddle, stain, lashing, spreader; the Pit's: shaft (`water`), truck (a
--                         haul truck); Prosperity's towers are factories (`stackX`, `stackY` their chimney),
--                         and flat: lamp, lot; the Refinery's: casting (`water`, the casting pit), and flat:
--                         grille (a steam vent); the Bunker's: intake (`water`, round: an engine's)
--   map.cranes            { x, y, jib, from, sweep, period, phase } tower cranes working (the Wreck): the mast
--                         at (x, y), the jib `jib` px long swinging from angle `from` through `sweep` and back
--                         every `period` seconds (borderline/works.lua draws them, moving)
--   map.beacons           { x, y, color } emergency beacons turning ("amber" or "red"; works.lua)
--   map.flows             { x, y, w, h, dir } the river's runs, flowing (the Refinery; works.lua)
--   map.steam             { x, y, phase } floor vents letting off steam (the Refinery; works.lua)
--   map.bridgecranes      { x0, x1, y0, y1, period, phase, load } overhead cranes spanning x0..x1, running up
--                         and down y0..y1 with a ladle of molten Bragium (the Refinery), or a finished
--                         hauler with `load` "hauler" (the Assembly Line) or a missile, "missile" (the
--                         Bunker; works.lua)
--   map.arms              { x, y, side, phase } assembly arms welding over a belt (the Assembly Line; works.lua)
--   map.presses           { x, y, w, h, phase } presses stamping (the Assembly Line; works.lua)
--   map.ropeway           { points, period } the ore ropeway down Thousand Papercuts' drop: its pylons
--                         ({ x, y } bottom to top), buckets running the rope (works.lua)
--   map.fans              { x, y, r, phase } turbine fans spinning in the bunker's intakes (works.lua)
--   map.radars            { x, y, r } radar dishes turning (the Bunker; works.lua)
--   map.stacks            { x, y, phase } smoke rising: factory chimneys (Prosperity), the wrecked train
--                         (the Wreck; works.lua)
--   map.tracks            { { x, y }, ... } forklifts' tracks through the snow, world px (the Wreck, and
--                         the straddle carriers' down Liar's Landing's lanes)
--   map.welders           { x, y, phase } welders at work on the hull in Liar's Landing's dry dock (works.lua)
--   map.dugout            { x, y } the hollow you were dug out of, at the arrival (the Wreck)
--   map.overpipes         { x0, x1, y } pipe bridges overhead across a street (Prosperity; works.lua)
--   map.headframes        { x, y, phase } a mine shaft's headframe over (x, y), its wheels turning (the Pit)
--   map.conveyors         { x, y, w, h, dir, cargo } conveyors running ("n", "e", "s" or "w"), world px,
--                         carrying ore (the Pit) or with `cargo` "parts" hauler parts (the Assembly Line)
--   map.gantries          { x, y, span, depth, reach, period, phase } the quay's gantry cranes (Liar's
--                         Landing): the portal `span` wide and `depth` deep round (x, y), its boom `reach`
--                         px out north over the water, its trolley running out and in every `period` s
--   map.lights            { x, y, r, color, a } floodlights, for a map played at dusk (the night feature)
--   map.army              { packs, posts, squads } who of Hyperbole's army stands where (borderline/army.lua
--                         says what each is), world px; empty where nobody is placed yet
--   map.terminals,        what opens the way on, and what it opens (the terminals feature): Hyperbole's
--   map.locks             terminals and the blast door they open (the Wreck); a terminal's `dock` names the
--                         hauler dock (a DCK post in `army`) it shuts down when hacked
--   map.hold              { x, y, w, h, time, waves } a spot held while Yappy hacks it, the way on shut till
--                         then (Liar's Landing's ferry lift; borderline/hold.lua says the rest)
--   map.boss              { kind, x, y, wake } the level's boss: where it comes, and the box { x0, y0, x1,
--                         y1 } whoever walks into first brings it (the Pit's Wilbur: borderline/wilbur.lua)
--   map.cutsRoad          [row] = { c0, c1 } the road's tiles across each row (Thousand Papercuts),
--                         so the render knows which side of it is the drop
--   map.openKinds         { walk = true }: pickups and the like go on the floor
--   map.mapFloor          the floor's colour on the minimap (MAP_FLOOR); the big things in `map.cover`
--                         carry a `mapColor` (MAP_COLORS)

local Borderline = {}

-- The minimap (the minimap feature) --------------------------------------------

-- Each map's floor on the minimap and the big map, by map kind.
Borderline.MAP_FLOOR = {
  wreck = { 0.66, 0.69, 0.74 }, -- snow on concrete
  landing = { 0.62, 0.65, 0.70 },
  pit = { 0.52, 0.44, 0.40 }, -- the pit's earth
  prosperity = { 0.70, 0.67, 0.60 }, -- its streets
  refinery = { 0.30, 0.31, 0.35 }, -- indoors, dark
  assembly = { 0.34, 0.35, 0.39 },
  cuts = { 0.66, 0.69, 0.74 },
  bunker = { 0.44, 0.46, 0.50 }, -- the armour plate
}

-- What shows on the minimap, by cover kind (the clutter, crates and cones
-- and drums, stays off): `mapColor`, which the minimap draws.
local YELLOW, STEEL, DARK = { 0.95, 0.76, 0.19 }, { 0.45, 0.47, 0.51 }, { 0.30, 0.32, 0.37 }
local HOLE = { 0.12, 0.10, 0.10 }
Borderline.MAP_COLORS = {
  shed = DARK, tower = DARK, billboard = DARK, booth = DARK, press = DARK, nest = DARK, cannon = DARK, arm = DARK,
  carriage = YELLOW, loco = YELLOW, statue = YELLOW, truck = YELLOW, gate = YELLOW, door = YELLOW, lift = YELLOW,
  bay = YELLOW, hatch = YELLOW,
  pit = HOLE, drydock = HOLE, shaft = HOLE, casting = HOLE, intake = HOLE, tunnel = { 0.05, 0.05, 0.06 },
  bridge = STEEL, tank = STEEL, pad = STEEL, pipe = STEEL,
  belt = { 0.25, 0.25, 0.28 }, conveyor = { 0.25, 0.25, 0.28 },
  ledge = { 0.36, 0.31, 0.28 }, rails = { 0.40, 0.30, 0.22 },
  river = { 1.00, 0.45, 0.10 }, ship = { 0.55, 0.16, 0.12 },
}
-- Containers in their own colours, as the map draws them.
Borderline.CONTAINER_COLORS = {
  { 0.80, 0.26, 0.20 }, { 0.22, 0.44, 0.72 }, { 0.28, 0.58, 0.34 }, { 0.90, 0.52, 0.16 },
}

local function mapColor(s)
  if s.kind == "container" then
    return Borderline.CONTAINER_COLORS[s.tint or 1]
  end
  return Borderline.MAP_COLORS[s.kind]
end

-- Blockout ---------------------------------------------------------------------

--- A map under construction: its tiles and the helpers that put things on
--- it, all in tile units unless they say px.
local Blockout = {}
Blockout.__index = Blockout

function Blockout.new(map, T)
  local b = setmetatable({ map = map, T = T, cells = {} }, Blockout)
  map.cover, map.grounds, map.zones, map.lights = {}, {}, {}, {}
  map.openKinds = { walk = true }
  map.army = { packs = {}, posts = {}, squads = {} }
  return b
end

function Blockout:x(c)
  return self.map.x0 + c * self.T
end

function Blockout:y(r)
  return self.map.y0 + r * self.T
end

--- Walk on tiles c0..c1, r0..r1 (inclusive), clipped to the map.
function Blockout:open(c0, r0, c1, r1)
  local map = self.map
  for c = math.max(0, c0), math.min(map.cols - 1, c1) do
    local col = self.cells[c] or {}
    self.cells[c] = col
    for r = math.max(0, r0), math.min(map.rows - 1, r1) do
      col[r] = "walk"
    end
  end
end

--- Back to the outside (a wall) on tiles c0..c1, r0..r1.
function Blockout:shut(c0, r0, c1, r1)
  for c = c0, c1 do
    for r = r0, r1 do
      if self.cells[c] then
        self.cells[c][r] = nil
      end
    end
  end
end

function Blockout:isOpen(c, r)
  return self.cells[c] ~= nil and self.cells[c][r] == "walk"
end

--- The floor finish over tiles c0..c1, r0..r1.
function Blockout:ground(floor, c0, r0, c1, r1)
  local g = self.map.grounds
  g[#g + 1] = { x0 = self:x(c0), y0 = self:y(r0), x1 = self:x(c1 + 1), y1 = self:y(r1 + 1), floor = floor }
end

function Blockout:zone(name, r0, r1)
  local z = self.map.zones
  z[#z + 1] = { name = name, x0 = self.map.left, y0 = self:y(r0), x1 = self.map.left + self.map.w, y1 = self:y(r1 + 1) }
end

--- Something on the map over (x, y, w, h) in px. It stands in the way
--- unless `opts.flat`; `opts.water` stands in the way of walking only.
function Blockout:put(kind, x, y, w, h, opts)
  local s = { kind = kind, x = x, y = y, w = w, h = h, solid = not (opts and opts.flat) }
  for k, v in pairs(opts or {}) do
    s[k] = v
  end
  s.mapColor = s.mapColor or mapColor(s)
  self.map.cover[#self.map.cover + 1] = s
  if s.solid then
    self.map.solids[#self.map.solids + 1] = { x = x, y = y, w = w, h = h, water = s.water }
  end
  return s
end

--- The same over tiles (c, r, tw, th), fractions allowed.
function Blockout:place(kind, c, r, tw, th, opts)
  return self:put(kind, self:x(c), self:y(r), tw * self.T, th * self.T, opts)
end

--- Does (x, y, w, h), grown by `gap` px, miss everything already put?
function Blockout:clear(x, y, w, h, gap)
  for _, s in ipairs(self.map.cover) do
    if not s.flat and x - gap < s.x + s.w and x + w + gap > s.x and y - gap < s.y + s.h and y + h + gap > s.y then
      return false
    end
  end
  return true
end

--- Up to `n` of `kind` (each `size` px across, round) scattered on open
--- tiles in rows r0..r1, clear of everything else and of `keep` (tile
--- rects { c0, r0, c1, r1 } left open: the arrival, the way on, a gap).
function Blockout:scatter(rng, kind, n, size, r0, r1, keep, opts)
  local T, got = self.T, 0
  for _ = 1, n * 20 do
    if got >= n then
      return
    end
    local c, r = rng:random(0, self.map.cols - 1), rng:random(r0, r1)
    local ok = self:isOpen(c, r) and self:isOpen(c + 1, r + 1) and self:isOpen(c - 1, r - 1)
    for _, k in ipairs(keep or {}) do
      if c >= k[1] - 1 and c <= k[3] + 1 and r >= k[2] - 1 and r <= k[4] + 1 then
        ok = false
      end
    end
    local s = size * (0.7 + rng:random() * 0.5)
    local x, y = self:x(c) + rng:random() * (T - s * 0.5), self:y(r) + rng:random() * (T - s * 0.5)
    if ok and self:clear(x, y, s, s, 56) then
      local o = { round = true, seed = rng:random(1000) }
      for k, v in pairs(opts or {}) do
        o[k] = v
      end
      self:put(kind, x, y, s, s, o)
      got = got + 1
    end
  end
end

--- Twelve spawn points from tile (c, r) facing north, `perRow` to a row
--- (six unless the way in is narrower); the way home just below them; the
--- way on at tile (ec, er)'s middle.
function Blockout:ends(c, r, ec, er, perRow)
  local map = self.map
  perRow = perRow or 6
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = {
      x = self:x(c) + 40 + (i % perRow) * 80, y = self:y(r) + 40 + math.floor(i / perRow) * 80, angle = -math.pi / 2,
    }
  end
  map.cx = math.floor(self:x(c) + 40 + (perRow - 1) * 40)
  map.cy = math.floor(self:y(r) + 60 + math.ceil(12 / perRow) * 80)
  map.exitX, map.exitY = math.floor(self:x(ec + 0.5)), math.floor(self:y(er + 0.5))
end

--- The army (borderline/army.lua): a pack of `count` of `code` picking
--- about tile (c, r).
function Blockout:pack(code, c, r, count)
  local army = self.map.army
  army.packs[#army.packs + 1] = { code = code, x = self:x(c), y = self:y(r), count = count }
end

--- One of `code` posted at tile (c, r), watching `watch` (radians; south
--- by default, the way everyone comes from).
function Blockout:post(code, c, r, watch)
  local army = self.map.army
  army.posts[#army.posts + 1] = { code = code, x = self:x(c), y = self:y(r), watch = watch or math.pi / 2 }
end

--- A squad of `codes` walking a loop through tiles `corners` ({ c, r } each).
function Blockout:squad(codes, corners)
  local route = {}
  for i, t in ipairs(corners) do
    route[i] = { x = self:x(t[1]), y = self:y(t[2]) }
  end
  local army = self.map.army
  army.squads[#army.squads + 1] = { codes = codes, route = route, start = 1 }
end

--- A spot players hold while Yappy hacks it (borderline/hold.lua): tiles
--- (c, r, w, h), `time` seconds of standing on it.
function Blockout:hold(c, r, w, h, time)
  self.map.hold = { x = self:x(c), y = self:y(r), w = w * self.T, h = h * self.T, time = time, waves = {} }
end

--- A wave of `codes` coming at the hold from tile (c, r) once the hack is
--- `at` (0..1) of the way through. Add them in order.
function Blockout:wave(at, codes, c, r)
  local waves = self.map.hold.waves
  waves[#waves + 1] = { at = at, codes = codes, x = self:x(c), y = self:y(r) }
end

--- A lock (the terminals feature): `label` on the HUD, holding the level's
--- way on when `exit`; its terminals and walls follow.
function Blockout:lock(name, label, exit)
  local map = self.map
  map.locks, map.terminals = map.locks or {}, map.terminals or {}
  local l = { name = name, label = label, exit = exit, walls = {} }
  map.locks[#map.locks + 1] = l
  return l
end

--- A blast door of lock `l` over (x, y, w, h) px: solid, like any wall,
--- until the lock opens.
function Blockout:lockWall(l, x, y, w, h)
  local s = { x = x, y = y, w = w, h = h, look = "blast" }
  self.map.solids[#self.map.solids + 1] = s
  l.walls[#l.walls + 1] = s
end

--- A post (borderline/army.lua): a Hyperbole terminal of lock `l` at tile
--- (c, r), and the hauler dock it runs at tile (dc, dr), the two sharing
--- the key `key`.
function Blockout:dockPost(l, key, c, r, dc, dr)
  local map = self.map
  map.terminals[#map.terminals + 1] = { x = math.floor(self:x(c)), y = math.floor(self:y(r)), look = "hyperbole",
    lock = l.name, warn = "Hyperbole's robots", dock = key }
  local army = map.army
  army.posts[#army.posts + 1] = { code = "DCK", x = self:x(dc), y = self:y(dr), watch = math.pi / 2, dock = key }
end

function Blockout:commit()
  local map = self.map
  for c = 0, map.cols - 1 do
    map.tiles[c] = {}
    for r = 0, map.rows - 1 do
      map.tiles[c][r] = self.cells[c] and self.cells[c][r]
    end
  end
end

-- 1. The Frozen Wreck ------------------------------------------------------------

-- Hyperbole's freight yard in the snow, where Max's train came off the
-- rails: factory grounds walled in by sheds, the rails up the middle, the
-- train zig-zagging across the yard in pieces (tiles: c, r, w, h), the
-- locomotive near the top, and the tunnel out at the top.
Borderline.TRAIN = {
  { 15, 57, 6, 1.5 },
  { 27, 50, 1.5, 5 },
  { 12, 45, 1.5, 5 },
  { 20, 39, 6, 1.5 },
  { 31, 31, 1.5, 5 },
  { 13, 27, 6, 1.5 },
  { 26, 20, 1.5, 5 },
}
Borderline.LOCO = { 19, 9, 2, 6 }
-- The carriages still burning (by their place in TRAIN): smoke, a glow,
-- embers in a hole in the roof.
Borderline.BURNING = { [4] = true, [6] = true }
-- The rail bed's tiles (c0, c1): what a carriage slid off.
Borderline.RAIL_BED = { 22, 25 }

-- The excavations: deep holes in the yard (tiles: c, r, w, h), fenced off,
-- each with a tower crane working over it from the corner (`crane`: the
-- corner its mast stands at, "nw", "ne", "sw" or "se").
Borderline.WRECK_PITS = {
  { 3, 46, 8, 9, crane = "ne" },
  { 35, 29, 9, 9, crane = "sw" },
  { 4, 14, 8, 8, crane = "se" },
}
-- The sheds along the yard's sides (tiles), a loading door on each.
Borderline.WRECK_SHEDS = {
  { 2, 30, 6, 8 }, { 2, 58, 5, 7 }, { 40, 8, 6, 8 }, { 41, 47, 5, 9 }, { 2, 3, 9, 6 }, { 36, 3, 10, 4 },
}

-- The terminals that open the tunnel, one in each part of the yard, each
-- guarded by the hauler dock it runs and a few robots (tiles): `terminal`
-- and `dock` where they stand, `guns` gun haulers posted by it, `junk` a
-- pack of junk haulers about it ({ c, r, count }).
Borderline.WRECK_POSTS = {
  { key = "yard", terminal = { 40, 57 }, dock = { 37.5, 52 }, guns = { { 39.5, 59.5 } }, junk = { 35, 56, 3 } },
  { key = "wreck", terminal = { 9.5, 36.5 }, dock = { 11.5, 32 }, guns = { { 13, 35.5 }, { 8.5, 40.5 } },
    junk = { 12, 38, 2 } },
  { key = "engine", terminal = { 38.5, 10.5 }, dock = { 35.5, 13.5 }, guns = { { 37.5, 12.5 }, { 33, 11.5 } },
    junk = { 36, 17, 2 } },
}

--- A tower crane at corner `corner` of pit `p` (tiles), working over it
--- (over tile `at`, { c, r }, when given: a long hole has more than one).
local function crane(map, b, p, corner, at)
  local cx = (corner == "nw" or corner == "sw") and p[1] - 0.5 or p[1] + p[3] + 0.5
  local cy = (corner == "nw" or corner == "ne") and p[2] - 0.5 or p[2] + p[4] + 0.5
  local x, y = b:x(cx), b:y(cy)
  b:put("mast", x - 22, y - 22, 44, 44, { round = true })
  -- The jib swings back and forth across the hole: from `from` through `sweep` radians.
  local tx, ty = b:x(at and at[1] or p[1] + p[3] / 2), b:y(at and at[2] or p[2] + p[4] / 2)
  local toward = math.atan2(ty - y, tx - x)
  map.cranes[#map.cranes + 1] = { x = x, y = y, jib = math.sqrt((tx - x) ^ 2 + (ty - y) ^ 2) + 2 * b.T,
    from = toward - 0.6, sweep = 1.2, period = 14 + #map.cranes * 3, phase = #map.cranes * 2.1 }
  map.beacons[#map.beacons + 1] = { x = x, y = y - 30, color = "amber" }
end

--- What the crash left that only shows: the ground torn up between each
--- carriage and the rail bed it slid off, smoke and a glow over the engine
--- and the carriages still burning, the engine's headlights still on,
--- tyre tracks through the snow, the hollow you were dug out of. Nothing
--- here is solid, and it takes no dice, so the yard plays as before.
local function wreckage(map, b)
  local bed = Borderline.RAIL_BED
  for i, t in ipairs(Borderline.TRAIN) do
    local c, r, w, h = t[1], t[2], t[3], t[4]
    local from, to = nil, nil
    if c + w <= bed[1] then
      from, to = math.max(c + w, bed[1] - 4), bed[1]
    elseif c >= bed[2] + 1 then
      from, to = bed[2] + 1, math.min(c, bed[2] + 5)
    end
    if from and to - from >= 0.5 then
      local across = math.min(h, 1.2)
      b:place("scar", from, r + (h - across) / 2, to - from, across, { flat = true, seed = i * 37 })
    end
    if Borderline.BURNING[i] then
      local x, y = b:x(c + w / 2), b:y(r + h / 2)
      map.stacks[#map.stacks + 1] = { x = x, y = y, phase = i * 1.3 }
      map.lights[#map.lights + 1] = { x = x, y = y, r = 260, color = { 1, 0.5, 0.18 }, a = 0.7 }
    end
  end
  local L = Borderline.LOCO
  local lx, ly = b:x(L[1] + L[3] / 2), b:y(L[2])
  map.stacks[#map.stacks + 1] = { x = lx, y = ly + 170, phase = 0.4 }
  map.lights[#map.lights + 1] = { x = lx, y = ly + 170, r = 200, color = { 1, 0.5, 0.18 }, a = 0.5 }
  map.lights[#map.lights + 1] = { x = lx, y = ly - 120, r = 300, color = { 1, 0.95, 0.8 }, a = 0.6 } -- headlights
  -- Forklifts' tracks between the sheds and the rails, through the snow (world px).
  local function track(points)
    local line = {}
    for _, p in ipairs(points) do
      line[#line + 1] = { b:x(p[1]), b:y(p[2]) }
    end
    map.tracks[#map.tracks + 1] = line
  end
  track({ { 8.5, 34 }, { 12, 35 }, { 15, 33.5 }, { 21, 33 } })
  track({ { 41, 51 }, { 37, 52.5 }, { 33, 51 }, { 26, 50.5 } })
  track({ { 40, 12 }, { 36, 15 }, { 33, 19 }, { 33, 27 }, { 34, 40 }, { 36, 58 }, { 33, 66 } })
  track({ { 7, 61 }, { 10, 62 }, { 14, 64.5 }, { 18, 66 }, { 21, 68 } })
  local first = map.spawns[1]
  map.dugout = first and { x = first.x, y = first.y }
end

local function buildWreck(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "works"
  map.cranes, map.beacons, map.stacks, map.tracks = {}, {}, {}, {}
  b:open(2, 3, map.cols - 3, map.rows - 3) -- the yard
  b:open(21, 0, 26, 2) -- the tunnel out
  b:open(20, map.rows - 3, 27, map.rows - 1) -- the gate in
  b:ground("yard", 0, 0, map.cols - 1, map.rows - 1)
  b:ground("ballast", 22, 0, 25, map.rows - 1) -- the rail bed, out of the tunnel
  b:ground("ballast", 29, 12, 31, 60)
  b:put("rails", b:x(23.5), b:y(0), 20, map.rows * T, { flat = true })
  b:put("rails", b:x(30), b:y(12), 20, 48 * T, { flat = true }) -- a siding
  b:place("tunnel", 21, 0, 6, 2.5, { flat = true, railsX = b:x(23.5) })
  b:place("gate", 20, map.rows - 2, 8, 2, { flat = true })
  -- The safety lines: a painted walkway up the west of the rails, zebra
  -- crossings over them, and DANGER painted by every hole.
  b:place("walkway", 17, 6, 3, map.rows - 10, { flat = true })
  for _, r in ipairs({ 61, 43, 24 }) do
    b:place("zebra", 20, r, 12, 1.4, { flat = true })
  end
  for i, s in ipairs(Borderline.WRECK_SHEDS) do
    b:place("shed", s[1], s[2], s[3], s[4], { seed = rng:random(1000), bay = i })
  end
  for _, p in ipairs(Borderline.WRECK_PITS) do
    b:place("pit", p[1], p[2], p[3], p[4], { water = true, seed = rng:random(1000) })
    b:place("paint", p[1], p[2] + p[4] + 0.2, p[3], 0.8,
      { flat = true, text = "DANGER  DEEP EXCAVATION", snowy = true })
    crane(map, b, p, p.crane)
    -- A beacon on each of the hole's other corners.
    for _, k in ipairs({ { 0, 0 }, { 1, 1 } }) do
      map.beacons[#map.beacons + 1] = { x = b:x(p[1] + k[1] * p[3]), y = b:y(p[2] + k[2] * p[4]), color = "red" }
    end
  end
  for i, t in ipairs(Borderline.TRAIN) do
    b:place("carriage", t[1], t[2], t[3], t[4], { seed = rng:random(1000), burning = Borderline.BURNING[i] })
  end
  local L = Borderline.LOCO
  b:place("loco", L[1], L[2], L[3], L[4])
  -- What the wreck spilled, by each carriage.
  for _, t in ipairs(Borderline.TRAIN) do
    for _ = 1, 3 do
      local c, r = t[1] + rng:random() * (t[3] + 2) - 1, t[2] + t[4] + 0.3 + rng:random() * 1.2
      if b:clear(b:x(c), b:y(r), 40, 40, 16) then
        b:place(rng:random() < 0.25 and "chest" or "crate", c, r, 0.6, 0.6, { seed = rng:random(1000) })
      end
    end
  end
  -- Floodlight towers round the yard, a beacon over the tunnel and the gate.
  for _, at in ipairs({ { 14, 66 }, { 36, 62 }, { 15, 36 }, { 38, 22 }, { 14, 9 }, { 33, 9 }, { 37, 44 } }) do
    b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
    map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 420,
      color = { 1, 0.92, 0.75 }, a = 0.75 }
  end
  for _, at in ipairs({ { 20.5, 2.6 }, { 27.5, 2.6 }, { 19.5, map.rows - 2.6 }, { 28.5, map.rows - 2.6 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "amber" }
  end
  -- The tunnel shut behind a blast door until the terminals are hacked.
  local tunnel = b:lock("tunnel", "THE TUNNEL", true)
  b:lockWall(tunnel, b:x(21), b:y(2) + 10, 6 * T, 36)
  local keep = { { 18, 61, 29, 69 }, { 20, 0, 27, 5 } }
  for _, post in ipairs(Borderline.WRECK_POSTS) do
    local t, d = post.terminal, post.dock
    b:dockPost(tunnel, post.key, t[1], t[2], d[1], d[2])
    keep[#keep + 1] = { math.floor(t[1]) - 1, math.floor(t[2]) - 1, math.floor(t[1]) + 1, math.floor(t[2]) + 1 }
    keep[#keep + 1] = { math.floor(d[1]) - 1, math.floor(d[2]) - 1, math.floor(d[1]) + 1, math.floor(d[2]) + 1 }
  end
  b:scatter(rng, "drum", 22, 40, 4, 66, keep)
  b:scatter(rng, "crate", 10, 46, 4, 66, keep)
  b:scatter(rng, "cone", 30, 22, 4, 66, keep, { flat = true })
  -- Junk haulers picking the wreck over: a pack by every carriage past the
  -- first, and a bigger one at the engine.
  for i = 2, #Borderline.TRAIN do
    local t = Borderline.TRAIN[i]
    b:pack("JNK", t[1] + t[3] / 2, t[2] + t[4] + 1.5, 3)
  end
  b:pack("JNK", L[1] + 1, L[2] + L[4] + 2, 4)
  for _, post in ipairs(Borderline.WRECK_POSTS) do
    for _, g in ipairs(post.guns) do
      b:post("GUN", g[1], g[2])
    end
    b:pack("JNK", post.junk[1], post.junk[2], post.junk[3])
  end
  b:zone("The Freight Yard", 40, map.rows - 1)
  b:zone("The Wreck", 16, 39)
  b:zone("The Engine", 0, 15)
  b:ends(21, 63, 23, 1)
  wreckage(map, b)
  b:commit()
end

-- 2. Liar's Landing --------------------------------------------------------------

-- The dry dock on the yard's west side (tiles: c, r, w, h): a deep basin
-- with a frozen hull in it, a tower crane at either end working over it.
Borderline.DRY_DOCK = { 3, 14, 7, 30 }
-- The quay's gantry cranes (tile column of each one's middle): they stand
-- over the quay and reach out over the freighter moored along it.
Borderline.GANTRIES = { 11.5, 43.5 }
Borderline.LIFT_HOLD = 60 -- seconds the ferry lift has to be held for Yappy's hack

--- Dice of their own for what only shows (0..1 each roll, the same every
--- time for `seed`), so dressing a map never moves what plays on it.
local function dice(seed)
  local state = seed
  return function()
    state = (state * 16807) % 2147483647
    return state / 2147483647
  end
end

--- What lies about Liar's Landing and only shows: the straddle carriers'
--- tracks down the lanes, frozen puddles and oil in the lanes, lashing gear
--- and a spare spreader on the quay, and welders at work on the hull in the
--- dry dock (`map.welders`). Nothing here is solid, and it takes no dice
--- from the map's, so the port plays as before.
local function portLitter(map, b)
  local roll = dice(302)
  local function track(points)
    local line = {}
    for _, p in ipairs(points) do
      line[#line + 1] = { b:x(p[1]), b:y(p[2]) }
    end
    map.tracks[#map.tracks + 1] = line
  end
  track({ { 27.5, 55 }, { 27, 46 }, { 27, 37 }, { 27.5, 28 }, { 27, 19 }, { 27.5, 8 } })
  track({ { 51, 54 }, { 51, 37 }, { 50.5, 28 }, { 51, 19 }, { 45, 18.5 }, { 35, 19 } })
  track({ { 12, 55 }, { 19, 46.5 }, { 34, 46 }, { 43, 46.5 }, { 43, 37 } })
  track({ { 19, 8.5 }, { 19, 19 }, { 25, 28 }, { 35, 28 }, { 43, 28.5 } })
  local keep = { { 22, 54, 33, 63 }, { 24, 1, 32, 7 } }
  local function scatter(kind, n, tw, th, r0, r1)
    for _ = 1, n * 12 do
      if n <= 0 then
        return
      end
      local c, r = 3 + roll() * (map.cols - 7), r0 + roll() * (r1 - r0)
      local ok = b:clear(b:x(c), b:y(r), tw * b.T, th * b.T, 10)
      for _, k in ipairs(keep) do
        if c + tw > k[1] and c < k[3] and r + th > k[2] and r < k[4] then
          ok = false
        end
      end
      if ok then
        b:place(kind, c, r, tw, th, { flat = true, seed = math.floor(roll() * 1000) })
        n = n - 1
      end
    end
  end
  scatter("puddle", 14, 1.4, 0.8, 8, 56)
  scatter("stain", 12, 1, 0.7, 8, 56)
  b:place("spreader", 16.5, 3.4, 3, 0.9, { flat = true })
  b:place("spreader", 35.5, 3.5, 3, 0.9, { flat = true })
  b:place("lashing", 20.5, 4.0, 2, 0.6, { flat = true })
  b:place("lashing", 48.5, 3.6, 2, 0.6, { flat = true })
  local D = Borderline.DRY_DOCK
  local mid, side = D[1] + D[3] / 2, D[3] * 0.55 / 2 + 0.1
  for i, at in ipairs({ { mid + side, D[2] + 7 }, { mid - side, D[2] + 15 }, { mid + side, D[2] + 22 } }) do
    map.welders[#map.welders + 1] = { x = b:x(at[1]), y = b:y(at[2]), phase = i * 1.7 }
  end
end

local function buildLanding(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "harbour"
  map.cranes, map.beacons, map.gantries, map.tracks, map.welders = {}, {}, {}, {}, {}
  b:open(2, 2, map.cols - 3, map.rows - 4)
  b:open(25, map.rows - 3, 30, map.rows - 1) -- out of the tunnel
  b:ground("port", 0, 0, map.cols - 1, map.rows - 1)
  b:ground("quay", 2, 2, map.cols - 3, 6)
  b:place("quayedge", 2, 2, map.cols - 4, 0.18, { flat = true })
  for _, r in ipairs({ 2.3, 5.6 }) do -- the gantries' rails, the length of the quay
    b:place("craneRail", 2, r, map.cols - 4, 0.3, { flat = true })
  end
  b:place("tunnel", 25, map.rows - 2.5, 6, 2.5, { flat = true })
  b:place("ship", 4, -2.2, map.cols - 8, 3.9, { flat = true }) -- the freighter moored along the quay
  -- The dry dock, and its two cranes.
  local D = Borderline.DRY_DOCK
  b:place("drydock", D[1], D[2], D[3], D[4], { water = true, seed = rng:random(1000) })
  b:place("paint", D[1], D[2] + D[4] + 0.2, D[3], 0.8, { flat = true, text = "DRY DOCK 2  KEEP OUT" })
  crane(map, b, D, "ne", { D[1] + D[3] / 2, D[2] + 7 })
  crane(map, b, D, "se", { D[1] + D[3] / 2, D[2] + D[4] - 7 })
  -- The painted lanes the stacks leave clear (below), and each bay's number.
  for k = 0, 5 do
    b:place("laneline", 11 + k * 8 - 0.06, 8, 0.12, 48, { flat = true })
  end
  for k = 0, 4 do
    b:place("laneline", 3, 19 + k * 9 - 0.06, map.cols - 6, 0.12, { flat = true })
  end
  -- The stacks: one in each cell of a grid, never filling it, so there is
  -- always a lane round (none where the dry dock is).
  for bc = 0, 5 do
    for br = 0, 4 do
      local c, r = 4 + bc * 8, 11 + br * 9
      local tall = rng:random() < 0.5
      local tw, th = tall and 2 or 4, tall and 4 or 2
      c, r = c + rng:random(0, 4 - tw + 2), r + rng:random(0, 5 - th + 2)
      local inDock = bc == 0 and br <= 3
      if not inDock and not (c <= 30 and c + tw >= 25 and r >= 52) then -- the way in stays clear
        b:place("container", c, r, tw, th, { tint = rng:random(4), seed = rng:random(1000) })
      end
      if not inDock then
        b:place("paint", 4 + bc * 8, 11 + br * 9 - 1.3, 6, 0.9,
          { flat = true, text = string.char(65 + bc) .. (br + 1), small = true })
      end
    end
  end
  -- The gantries: four feet on the quay each, the rest overhead (works.lua).
  for _, c in ipairs(Borderline.GANTRIES) do
    for _, f in ipairs({ { -1.8, 2.2 }, { 1.3, 2.2 }, { -1.8, 5.5 }, { 1.3, 5.5 } }) do
      b:place("foot", c + f[1], f[2], 0.5, 0.5)
    end
    map.gantries[#map.gantries + 1] = { x = b:x(c), y = b:y(4), span = 3.6 * T, depth = 3.8 * T, reach = 4.5 * T,
      period = 11 + #map.gantries * 4, phase = #map.gantries * 1.9 }
    map.beacons[#map.beacons + 1] = { x = b:x(c - 1.55), y = b:y(2.45), color = "amber" }
    map.beacons[#map.beacons + 1] = { x = b:x(c + 1.55), y = b:y(2.45), color = "amber" }
  end
  for c = 3, map.cols - 4, 4 do
    if (c < 24 or c > 31) and math.abs(c + 0.5 - Borderline.GANTRIES[1]) > 2.5
      and math.abs(c + 0.5 - Borderline.GANTRIES[2]) > 2.5 then
      b:place("bollard", c + 0.35, 2.15, 0.3, 0.3, { round = true, rope = b:y(1.45) })
    end
  end
  b:place("lift", 25, 2, 6, 3, { flat = true })
  b:place("zebra", 24, 5.3, 8, 1.2, { flat = true })
  for _, at in ipairs({ { 25, 2 }, { 31, 2 }, { 25, 5 }, { 31, 5 } }) do -- the lift's corners
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "red" }
  end
  map.beacons[#map.beacons + 1] = { x = b:x(D[1]), y = b:y(D[2]), color = "red" }
  map.beacons[#map.beacons + 1] = { x = b:x(D[1] + D[3]), y = b:y(D[2] + D[4]), color = "red" }
  -- Floodlight towers in the corners of the lanes, where there is room.
  for _, at in ipairs({ { 12.2, 20.2 }, { 36.2, 20.2 }, { 20.2, 29.2 }, { 44.2, 38.2 }, { 28.2, 47.2 },
    { 52.2, 47.2 }, { 4.2, 8.2 }, { 50.2, 8.2 } }) do
    if b:clear(b:x(at[1]), b:y(at[2]), 0.7 * T, 0.7 * T, 8) then
      b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
      map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 420,
        color = { 1, 0.92, 0.75 }, a = 0.75 }
    end
  end
  b:scatter(rng, "crate", 14, 48, 8, 56, { { 22, 54, 33, 63 }, { 24, 2, 32, 7 } })
  b:scatter(rng, "drum", 12, 40, 8, 56, { { 22, 54, 33, 63 }, { 24, 2, 32, 7 } })
  b:scatter(rng, "cone", 16, 22, 7, 56, { { 22, 54, 33, 63 } }, { flat = true })
  -- Hyperbole's gun haulers hold the yard. The stacks always leave lanes
  -- clear between the cells of their grid: down columns 10-11 (and every 8
  -- after) and across rows 18-19 (and every 9 after). Posts stand where
  -- lanes cross, watching the way in; two squads walk loops along the
  -- lanes; two guard the lift; junk haulers scavenge the edges.
  for _, at in ipairs({ { 19, 46 }, { 35, 46 }, { 11, 37 }, { 43, 37 }, { 27, 28 }, { 51, 28 }, { 19, 19 } }) do
    b:post("GUN", at[1], at[2])
  end
  b:post("GUN", 23, 5.5)
  b:post("GUN", 33, 5.5)
  b:squad({ "GUN", "GUN", "GUN" }, { { 11, 19 }, { 43, 19 }, { 43, 37 }, { 11, 37 } })
  b:squad({ "GUN", "GUN" }, { { 19, 28 }, { 35, 28 }, { 35, 46 }, { 19, 46 } })
  b:squad({ "STK", "STK" }, { { 27, 28 }, { 51, 28 }, { 51, 46 }, { 27, 46 } }) -- a pair of stalkers hunting the stacks
  b:pack("JNK", 5, 48, 3)
  b:pack("JNK", 50, 12, 3)
  b:post("RPG", 9, 7) -- the first rocket haulers, under the gantries
  b:post("RPG", 46, 7)
  b:post("FIX", 12, 21) -- a pair of medic drones with the first squad
  b:post("FIX", 14, 21)
  -- The ferry lift stays shut until it has been held for Yappy's hack, the
  -- army coming at it off both ends of the quay and up the lanes.
  b:hold(25, 2, 6, 3, Borderline.LIFT_HOLD)
  b:wave(0, { "GUN", "GUN", "FIX" }, 4, 4)
  b:wave(0.2, { "JNK", "JNK", "JNK", "JNK" }, 27, 19)
  b:wave(0.4, { "GUN", "GUN", "GUN" }, 52, 4)
  b:wave(0.6, { "RPG", "GUN", "GUN" }, 43, 19)
  b:wave(0.8, { "STK", "GUN", "GUN", "FIX" }, 11, 19)
  b:zone("The Yard", 8, map.rows - 1)
  b:zone("The Quay", 0, 7)
  b:ends(25, 56, 27, 3)
  portLitter(map, b)
  b:commit()
end

-- 3. The Bragium Pit -------------------------------------------------------------

-- The rings of terraces, by how far in from the map's edge they stand
-- (tiles), and where each ring's ledge is cut for a ramp down.
Borderline.PIT_RINGS = {
  { inset = 15, gaps = { "w", "e" } },
  { inset = 22, gaps = { "s", "n" } },
}

-- The mine shafts on the inner terrace (tiles: c, r, w, h), each with a
-- headframe over it winding its cage up and down (works.lua's `headframes`).
Borderline.SHAFTS = { { 17, 34, 2.5, 2.5 }, { 40, 23, 2.5, 2.5 } }

local function buildPit(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "rock"
  map.cranes, map.beacons, map.headframes, map.conveyors = {}, {}, {}, {}
  local n = map.cols
  b:open(8, 8, n - 9, n - 9) -- the pit
  b:open(20, n - 7, 39, n - 3) -- the south rim, where everyone comes in
  b:open(20, 2, 39, 6) -- the north rim and the mine lift
  b:open(28, n - 8, 31, n - 8) -- the ramp down off the south rim
  b:open(28, 7, 31, 7) -- the ramp up to the north rim
  b:ground("gravel", 0, 0, n - 1, n - 1)
  b:ground("terrace", 8, 8, n - 9, n - 9)
  b:ground("pitfloor", 22, 22, n - 23, n - 23)
  b:place("ramp", 28, n - 8, 4, 1, { flat = true })
  b:place("ramp", 28, 7, 4, 1, { flat = true })
  -- Each ring's ledge: four walls, cut in the middle of a side for its ramps.
  local thick = 0.4
  for _, ring in ipairs(Borderline.PIT_RINGS) do
    local d = ring.inset
    local cut = {}
    for _, g in ipairs(ring.gaps) do
      cut[g] = true
    end
    local lo, hi, mid0, mid1 = d, n - d, n / 2 - 2, n / 2 + 2
    local sides = {
      n = { lo, lo, hi - lo, thick, true },
      s = { lo, hi - thick, hi - lo, thick, true },
      w = { lo, lo, thick, hi - lo, false },
      e = { hi - thick, lo, thick, hi - lo, false },
    }
    for name, s in pairs(sides) do
      if cut[name] then
        if s[5] then -- along the top or bottom: the cut is a gap across it
          b:place("ledge", s[1], s[2], mid0 - s[1], s[4])
          b:place("ledge", mid1, s[2], s[1] + s[3] - mid1, s[4])
          b:place("ramp", mid0, s[2] - 0.3, 4, 1, { flat = true })
        else
          b:place("ledge", s[1], s[2], s[3], mid0 - s[2])
          b:place("ledge", s[1], mid1, s[3], s[2] + s[4] - mid1)
          b:place("ramp", s[1] - 0.3, mid0, 1, 4, { flat = true })
        end
      else
        b:place("ledge", s[1], s[2], s[3], s[4])
      end
    end
  end
  b:place("pad", 26, 26, 8, 8, { flat = true, round = true })
  b:place("paint", 22.5, n - 24.4, n - 45, 0.8, { flat = true, text = "BLAST ZONE  STAND CLEAR" })
  -- The haul road's painted edge round the outer terrace.
  b:place("laneline", 8.6, 8.6, n - 17.2, 0.12, { flat = true })
  b:place("laneline", 8.6, n - 8.72, n - 17.2, 0.12, { flat = true })
  b:place("laneline", 8.6, 8.6, 0.12, n - 17.2, { flat = true })
  b:place("laneline", n - 8.72, 8.6, 0.12, n - 17.2, { flat = true })
  -- Conveyors along the outer terraces carrying the ore up (it moves: works.lua).
  for _, c in ipairs({ { 10, 17, 0.8, 26, "n" }, { n - 11, 17, 0.8, 26, "n" }, { 17, 10, 26, 0.8, "e" } }) do
    b:place("conveyor", c[1], c[2], c[3], c[4])
    map.conveyors[#map.conveyors + 1] = { x = b:x(c[1]), y = b:y(c[2]), w = c[3] * T, h = c[4] * T, dir = c[5] }
  end
  -- Two tower cranes over the pit's floor, from its corners.
  local floor = { 22, 22, n - 44, n - 44 }
  crane(map, b, floor, "nw", { 27, 27 })
  crane(map, b, floor, "se", { n - 27, n - 27 })
  -- The shafts, fenced, a headframe over each.
  for _, sh in ipairs(Borderline.SHAFTS) do
    b:place("shaft", sh[1], sh[2], sh[3], sh[4], { water = true })
    map.headframes[#map.headframes + 1] = { x = b:x(sh[1] + sh[3] / 2), y = b:y(sh[2] + sh[4] / 2),
      phase = #map.headframes * 2.3 }
    map.beacons[#map.beacons + 1] = { x = b:x(sh[1]), y = b:y(sh[2]), color = "red" }
    map.beacons[#map.beacons + 1] = { x = b:x(sh[1] + sh[3]), y = b:y(sh[2] + sh[4]), color = "red" }
  end
  -- Haul trucks parked on the terraces and the rim.
  b:place("truck", 14, n - 10.8, 3.2, 1.6, { seed = rng:random(1000) })
  b:place("truck", 34, 3, 3.2, 1.6, { seed = rng:random(1000) })
  b:place("truck", n - 14.2, 13, 1.6, 3.2, { seed = rng:random(1000) })
  -- Beacons at the top of each ramp, floodlights round the rims and corners.
  for _, at in ipairs({ { 27.5, n - 8 }, { 32.5, n - 8 }, { 27.5, 8 }, { 32.5, 8 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "amber" }
  end
  for _, at in ipairs({ { 21, 3 }, { 38, 3 }, { 21, n - 4 }, { 38, n - 4 }, { 9, 9 }, { n - 10, 9 }, { 9, n - 10 },
    { n - 10, n - 10 } }) do
    b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
    map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 440,
      color = { 1, 0.92, 0.75 }, a = 0.75 }
  end
  local keep = { { 26, 26, 33, 33 }, { 26, n - 9, 33, n - 3 }, { 26, 2, 33, 9 }, { 13, 28, 24, 31 },
    { n - 25, 28, n - 13, 31 }, { 28, 20, 31, 24 }, { 28, n - 25, 31, n - 21 } }
  b:scatter(rng, "crystal", 30, 56, 9, n - 10, keep)
  b:scatter(rng, "rock", 10, 64, 9, n - 10, keep)
  b:scatter(rng, "drum", 10, 40, 9, n - 10, keep)
  b:scatter(rng, "cone", 18, 22, 9, n - 10, keep, { flat = true })
  for _, c in ipairs(map.cover) do -- the Bragium glows in the dusk
    if c.kind == "crystal" then
      map.lights[#map.lights + 1] = { x = c.x + c.w / 2, y = c.y + c.h / 2, r = 130, color = { 0.75, 0.35, 1 },
        a = 0.6 }
    end
  end
  -- Plasma haulers on the terraces' corners, gun haulers at the ramps and
  -- walking the outer terrace, junk haulers on the floor (Wilbur lands
  -- there later).
  for _, at in ipairs({ { 11, 11 }, { n - 12, 11 }, { 11, n - 12 }, { n - 12, n - 12 }, { 41, 18 }, { 18, 41 } }) do
    b:post("PLZ", at[1], at[2])
  end
  b:post("GUN", 13, n / 2, 0) -- either side of the first ring's ramps, watching across
  b:post("GUN", n - 13, n / 2, math.pi)
  b:post("GUN", 18, 18)
  b:post("GUN", 41, 41)
  b:squad({ "GUN", "GUN" }, { { 11.5, 11.5 }, { n - 12, 11.5 }, { n - 12, n - 12 }, { 11.5, n - 12 } })
  b:pack("JNK", n / 2, n / 2, 4)
  b:post("SHD", 40, 20) -- shield drones by the inner plasma haulers
  b:post("SHD", 20, 40)
  -- Wilbur comes down onto the pad when somebody first sets foot on the
  -- pit's floor; the mine lift stays shut until he is down.
  map.boss = { kind = "wilbur", x = b:x(30), y = b:y(30),
    wake = { x0 = b:x(22), y0 = b:y(22), x1 = b:x(n - 22), y1 = b:y(n - 22) } }
  b:zone("The Rim", n - 8, n - 1)
  b:zone("The Pit", 8, n - 9)
  b:zone("The Mine Lift", 0, 7)
  b:ends(27, n - 6, 29, 3)
  b:commit()
end

-- 4. Prosperity --------------------------------------------------------------------

-- The blocks between the streets, in tiles: columns and rows (inclusive).
-- The plaza takes the middle rows; the avenue runs up the middle.
Borderline.PROSPERITY_COLS = { { 6, 13 }, { 18, 25 }, { 30, 37 }, { 42, 49 } }
Borderline.PROSPERITY_ROWS = { { 6, 15 }, { 20, 29 }, { 56, 65 }, { 70, 79 } }
Borderline.PLAZA = { 34, 52 } -- rows

-- The blocks that are building sites ("Prosperity Phase 2": by index into
-- PROSPERITY_COLS, PROSPERITY_ROWS), each a deep foundation hole with a
-- tower crane at a corner.
Borderline.PROSPERITY_SITES = { { 2, 2, crane = "nw" }, { 3, 3, crane = "se" } }

--- A factory block over tiles (c, r, w, h), its chimney's smoke rising (works.lua's `stacks`).
local function factory(map, b, rng, c, r, w, h)
  local f = b:place("tower", c, r, w, h, { seed = rng:random(1000) })
  local k1, k2 = rng:random(), rng:random()
  f.stackX, f.stackY = f.x + f.w * (0.2 + 0.6 * k1), f.y + f.h * (0.25 + 0.5 * k2)
  map.stacks[#map.stacks + 1] = { x = f.stackX, y = f.stackY, phase = k1 * 7 }
end

local function buildProsperity(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "dome"
  map.cranes, map.beacons, map.stacks, map.overpipes = {}, {}, {}, {}
  b:open(2, 2, map.cols - 3, map.rows - 3)
  b:open(25, map.rows - 2, 30, map.rows - 1) -- the south gate
  b:open(25, 0, 30, 1) -- the north gate
  b:ground("street", 0, 0, map.cols - 1, map.rows - 1)
  b:ground("plaza", 6, Borderline.PLAZA[1], 49, Borderline.PLAZA[2])
  b:place("gate", 25, map.rows - 2, 6, 2, { flat = true })
  b:place("gate", 25, 0, 6, 2, { flat = true })
  for ci, cs in ipairs(Borderline.PROSPERITY_COLS) do
    for ri, rs in ipairs(Borderline.PROSPERITY_ROWS) do
      local w, h = cs[2] - cs[1] + 1, rs[2] - rs[1] + 1
      local site = nil
      for _, st in ipairs(Borderline.PROSPERITY_SITES) do
        if st[1] == ci and st[2] == ri then
          site = st
        end
      end
      if site then -- Phase 2: a foundation hole, fenced, its crane over it
        local hole = { cs[1] + 1, rs[1] + 1, w - 2, h - 2 }
        b:place("pit", hole[1], hole[2], hole[3], hole[4], { water = true, seed = rng:random(1000) })
        b:place("paint", cs[1], rs[2] + 0.1, w, 0.8, { flat = true, text = "PHASE 2", small = true })
        crane(map, b, hole, site.crane)
        map.beacons[#map.beacons + 1] = { x = b:x(hole[1]), y = b:y(hole[2] + hole[4]), color = "red" }
        map.beacons[#map.beacons + 1] = { x = b:x(hole[1] + hole[3]), y = b:y(hole[2]), color = "red" }
      elseif rng:random() < 0.2 then -- a loading lot: painted bays, pallets, a truck
        b:place("lot", cs[1], rs[1], w, h, { flat = true })
        b:place("truck", cs[1] + 1, rs[1] + 1.5, 1.6, 3.2, { seed = rng:random(1000) })
        for k = 0, 2 do
          b:place("crate", cs[1] + 4 + (k % 2) * 1.2, rs[1] + 2 + k * 2, 0.9, 0.9, { seed = rng:random(1000) })
        end
      elseif rng:random() < 0.5 then -- one factory, or two with a yard between
        factory(map, b, rng, cs[1], rs[1], w, h)
      else
        factory(map, b, rng, cs[1], rs[1], w, math.floor(h / 2) - 1)
        factory(map, b, rng, cs[1], rs[1] + math.floor(h / 2) + 1, w, h - math.floor(h / 2) - 1)
      end
    end
  end
  -- The road markings: centre lines down the streets (not across the
  -- plaza), zebra crossings where the avenue meets it.
  local P0, P1 = Borderline.PLAZA[1], Borderline.PLAZA[2]
  for _, c in ipairs({ 16, 28, 40 }) do
    b:place("laneline", c - 0.06, 2, 0.12, P0 - 3, { flat = true })
    b:place("laneline", c - 0.06, P1 + 1, 0.12, map.rows - P1 - 4, { flat = true })
  end
  for _, r in ipairs({ 18, 32, 54, 68 }) do
    b:place("laneline", 2, r - 0.06, map.cols - 4, 0.12, { flat = true })
  end
  b:place("zebra", 25.5, P0 - 1.4, 5, 1.2, { flat = true })
  b:place("zebra", 25.5, P1 + 0.2, 5, 1.2, { flat = true })
  -- Street lamps down the streets, floodlights on the plaza's corners,
  -- beacons at the gates.
  for r = 4, map.rows - 4, 8 do
    if r < P0 or r > P1 then
      for _, c in ipairs({ 14.3, 41.7 }) do
        b:place("lamp", c - 0.15, r - 0.15, 0.3, 0.3, { flat = true, round = true })
        map.lights[#map.lights + 1] = { x = b:x(c), y = b:y(r), r = 260, color = { 1, 0.85, 0.55 }, a = 0.7 }
      end
    end
  end
  for _, at in ipairs({ { 7, P0 + 1 }, { 48, P0 + 1 }, { 7, P1 - 1.7 }, { 48, P1 - 1.7 } }) do
    b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
    map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 460,
      color = { 1, 0.92, 0.75 }, a = 0.75 }
  end
  for _, at in ipairs({ { 24.5, map.rows - 2.5 }, { 31.5, map.rows - 2.5 }, { 24.5, 2.5 }, { 31.5, 2.5 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "amber" }
  end
  -- Pipe bridges over the avenue, block to block.
  for _, r in ipairs({ 10.5, 74.5 }) do
    map.overpipes[#map.overpipes + 1] = { x0 = b:x(25.6), x1 = b:x(30.4), y = b:y(r) }
  end
  -- Max, larger than life, in the middle of the plaza.
  local mr = (Borderline.PLAZA[1] + Borderline.PLAZA[2]) / 2
  b:place("statue", 26, mr - 2, 4, 4, { round = true })
  -- His four big screens, one over each district.
  for _, at in ipairs({ { 6, 16 }, { 42, 16 }, { 6, 66 }, { 42, 66 } }) do
    b:place("billboard", at[1], at[2], 8, 0.8)
  end
  local keep = { { 22, 80, 33, 87 }, { 22, 0, 33, 4 }, { 24, mr - 4, 31, mr + 4 } }
  b:scatter(rng, "crate", 18, 44, 3, map.rows - 4, keep)
  b:scatter(rng, "drum", 14, 40, 3, map.rows - 4, keep)
  b:scatter(rng, "cone", 18, 22, 3, map.rows - 4, keep, { flat = true })
  -- Max's garrison: jet haulers round the plaza and up north, rocket and
  -- plasma haulers on the cross streets, a squad walking the avenue and one
  -- round the north district.
  b:post("JET", 20, Borderline.PLAZA[1] + 3)
  b:post("JET", 36, Borderline.PLAZA[1] + 3)
  b:post("JET", 28, 18)
  b:post("RPG", 16, 67)
  b:post("RPG", 40, 31)
  b:post("PLZ", 40, 67)
  b:post("PLZ", 16, 31)
  b:post("GUN", 22, Borderline.PLAZA[2] - 2)
  b:post("GUN", 34, Borderline.PLAZA[2] - 2)
  b:squad({ "GUN", "GUN", "GUN" }, { { 28, 55 }, { 28, 81 } })
  b:squad({ "GUN", "GUN" }, { { 16, 31 }, { 40, 31 }, { 40, 18 }, { 16, 18 } })
  -- And the newer models: kamikazes about the plaza and up north, dozers
  -- across the avenue, the first badass by the statue with its drones.
  b:pack("EXP", 16, 50, 3)
  b:pack("EXP", 40, 18, 3)
  b:post("DZR", 28, Borderline.PLAZA[2] + 1)
  b:post("DZR", 28, 16)
  b:post("BAD", 28, mr + 5)
  b:post("FIX", 24, mr + 6)
  b:post("SHD", 32, mr + 6)
  b:zone("South District", 53, map.rows - 1)
  b:zone("Max Plaza", Borderline.PLAZA[1], Borderline.PLAZA[2])
  b:zone("North District", 0, 33)
  b:ends(25, map.rows - 7, 27, 1)
  b:commit()
end

-- 5. The Refinery ---------------------------------------------------------------------

-- The river's runs across the floor, bottom to top (the row of each run's
-- top; each is three tiles deep), the side it bends round on the way to
-- the next, and the columns its two bridges cross at.
Borderline.RIVER = {
  { r = 64, bend = "w", bridges = { 10, 34 } },
  { r = 50, bend = "e", bridges = { 22 } },
  { r = 36, bend = "w", bridges = { 8, 36 } },
  { r = 22, bend = "e", bridges = { 24 } },
}

-- The casting pit by the outflow (tiles), where the ladles pour.
Borderline.CASTING = { 34, 3, 8, 6 }
-- Steam vents in the floor (tiles), venting now and then.
Borderline.REFINERY_VENTS = { { 6, 70 }, { 40, 68 }, { 14, 46 }, { 34, 54 }, { 6, 18 }, { 40, 33 }, { 28, 26 },
  { 12, 10 } }

local function buildRefinery(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "plant"
  map.beacons, map.flows, map.steam, map.bridgecranes, map.overpipes = {}, {}, {}, {}, {}
  local w = map.cols
  b:open(2, 2, w - 3, map.rows - 3)
  b:open(21, map.rows - 2, 26, map.rows - 1) -- the way in
  b:open(20, 0, 27, 1) -- the freight door
  b:ground("grate", 0, 0, w - 1, map.rows - 1)
  b:ground("steel", 2, 2, w - 3, 12) -- the outflow, where the Smelter waits
  b:place("door", 20, 0, 8, 2, { flat = true })
  for i, run in ipairs(Borderline.RIVER) do
    -- Across the floor, cut for its bridges.
    local from = 2
    local cuts = {}
    for _, c in ipairs(run.bridges) do
      cuts[#cuts + 1] = c
    end
    cuts[#cuts + 1] = w - 2
    for _, c in ipairs(cuts) do
      if c > from then
        local seg = b:place("river", from, run.r, c - from, 3, { water = true })
        map.flows[#map.flows + 1] = { x = seg.x, y = seg.y, w = seg.w, h = seg.h, dir = i % 2 == 1 and "w" or "e" }
      end
      if c < w - 2 then
        b:place("bridge", c, run.r - 0.2, 3, 3.4, { flat = true })
        map.beacons[#map.beacons + 1] = { x = b:x(c), y = b:y(run.r - 0.4), color = "amber" }
        map.beacons[#map.beacons + 1] = { x = b:x(c + 3), y = b:y(run.r + 3.4), color = "amber" }
      end
      from = c + 3
    end
    -- The bend round to the next run, along the wall.
    local nextRun = Borderline.RIVER[i + 1]
    if nextRun then
      local c = run.bend == "w" and 2 or w - 5
      local seg = b:place("river", c, nextRun.r + 3, 3, run.r - nextRun.r - 3, { water = true })
      map.flows[#map.flows + 1] = { x = seg.x, y = seg.y, w = seg.w, h = seg.h, dir = "n" }
    end
  end
  -- Smelting tanks and the pipes between them, on the banks.
  local keep = { { 18, map.rows - 6, 29, map.rows - 1 }, { 18, 0, 29, 4 } }
  for _, run in ipairs(Borderline.RIVER) do
    for _, c in ipairs(run.bridges) do
      keep[#keep + 1] = { c - 1, run.r - 3, c + 3, run.r + 5 }
    end
  end
  b:scatter(rng, "tank", 14, 110, 4, map.rows - 6, keep)
  for _, at in ipairs({ { 6, 58 }, { 30, 44 }, { 12, 30 }, { 32, 16 } }) do
    if b:clear(b:x(at[1]), b:y(at[2]), 8 * T, 0.5 * T, 24) then
      b:place("pipe", at[1], at[2], 8, 0.5)
    end
  end
  b:scatter(rng, "crate", 12, 48, 4, map.rows - 6, keep)
  b:scatter(rng, "drum", 10, 40, 4, map.rows - 6, keep)
  -- The casting pit, its beacons; the steam vents.
  local K = Borderline.CASTING
  b:place("casting", K[1], K[2], K[3], K[4], { water = true, seed = rng:random(1000) })
  b:place("paint", K[1], K[2] + K[4] + 0.15, K[3], 0.8, { flat = true, text = "MOLTEN METAL", small = true })
  map.beacons[#map.beacons + 1] = { x = b:x(K[1]), y = b:y(K[2] + K[4]), color = "red" }
  map.beacons[#map.beacons + 1] = { x = b:x(K[1] + K[3]), y = b:y(K[2] + K[4]), color = "red" }
  for i, v in ipairs(Borderline.REFINERY_VENTS) do
    b:place("grille", v[1], v[2], 1, 1, { flat = true })
    map.steam[#map.steam + 1] = { x = b:x(v[1] + 0.5), y = b:y(v[2] + 0.5), phase = i * 1.37 }
  end
  -- Two bridge cranes running the hall's length, a ladle under each.
  map.bridgecranes[1] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(14), y1 = b:y(52), period = 34, phase = 0 }
  map.bridgecranes[2] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(56), y1 = b:y(74), period = 26, phase = 2.4 }
  -- Pipes along the walls overhead, work lamps on the walls, the river's
  -- glow and the tanks'.
  for _, r in ipairs({ 13, 53 }) do
    map.overpipes[#map.overpipes + 1] = { x0 = b:x(2), x1 = b:x(w - 2), y = b:y(r) }
  end
  for r = 6, map.rows - 6, 8 do
    for _, c in ipairs({ 2.3, w - 2.6 }) do
      b:place("lamp", c, r, 0.3, 0.3, { flat = true, round = true })
      map.lights[#map.lights + 1] = { x = b:x(c + 0.15), y = b:y(r + 0.15), r = 300, color = { 1, 0.8, 0.5 }, a = 0.7 }
    end
  end
  for _, f in ipairs(map.flows) do
    local along = f.w >= f.h
    for k = 0.5, (along and f.w or f.h) / T, 4 do
      local x, y = along and f.x + k * T or f.x + f.w / 2, along and f.y + f.h / 2 or f.y + k * T
      map.lights[#map.lights + 1] = { x = x, y = y, r = 260, color = { 0.75, 0.35, 1 }, a = 0.75 }
    end
  end
  for _, c in ipairs(map.cover) do
    if c.kind == "tank" then
      map.lights[#map.lights + 1] = { x = c.x + c.w / 2, y = c.y + c.h / 2, r = 140, color = { 0.75, 0.35, 1 },
        a = 0.4 }
    end
  end
  map.lights[#map.lights + 1] = { x = b:x(K[1] + K[3] / 2), y = b:y(K[2] + K[4] / 2), r = 380, color = { 0.8, 0.4, 1 },
    a = 0.9 }
  -- Arc haulers hold the far end of every bridge under their domes, plasma
  -- haulers stand by the tanks, gun haulers walk the banks, kamikazes wait
  -- in the middle and a dozer and a badass guard the outflow.
  for _, run in ipairs(Borderline.RIVER) do
    for _, c in ipairs(run.bridges) do
      b:post("ARC", c + 1.5, run.r - 1.5)
    end
  end
  b:post("PLZ", 20, 57)
  b:post("PLZ", 30, 43)
  b:post("PLZ", 15, 29)
  b:squad({ "GUN", "GUN" }, { { 8, 58 }, { 40, 58 } })
  b:squad({ "GUN", "GUN" }, { { 8, 30 }, { 40, 30 } })
  b:pack("EXP", 24, 44, 3)
  b:post("DZR", 24, 9)
  b:post("BAD", 20, 6)
  b:post("FIX", 30, 6)
  b:post("SHD", 18, 44)
  b:zone("The Intake", 54, map.rows - 1)
  b:zone("The Smelting Floor", 13, 53)
  b:zone("The Outflow", 0, 12)
  b:ends(21, map.rows - 7, 23, 1)
  b:commit()
end

-- 6. The Assembly Line ----------------------------------------------------------------

-- The belts across the floor, bottom to top (each two tiles deep), and the
-- Foreman's floor up top (rows).
Borderline.BELT_ROWS = { 58, 46, 34, 22 }
Borderline.UPPER = { 3, 12 }

-- The scrap pits beside the line (tiles), where the rejects go.
Borderline.SCRAP_PITS = { { 2.2, 49, 4.6, 6 }, { 49.4, 26, 4.6, 6 } }

local function buildAssembly(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "plant"
  map.beacons, map.conveyors, map.arms, map.presses, map.bridgecranes = {}, {}, {}, {}, {}
  local w = map.cols
  b:open(2, 2, w - 3, map.rows - 3)
  b:open(25, map.rows - 2, 30, map.rows - 1) -- the way in
  b:open(24, 0, 31, 1) -- the shipping bay
  b:ground("steel", 0, 0, w - 1, map.rows - 1)
  b:ground("upper", 2, 2, w - 3, Borderline.UPPER[2])
  b:place("bay", 24, 0, 8, 2.5, { flat = true })
  -- The Foreman's floor is up a step: a wall across with stairs at both ends.
  local edge = Borderline.UPPER[2] + 1
  b:place("ledge", 6, edge, w - 12, 0.4)
  b:place("stairs", 2, edge - 0.5, 4, 1.5, { flat = true })
  b:place("stairs", w - 6, edge - 0.5, 4, 1.5, { flat = true })
  for i, r in ipairs(Borderline.BELT_ROWS) do
    local belt = b:place("belt", 6, r, w - 12, 2, { flat = true })
    -- Hauler parts ride it (works.lua), each belt the other way from the last.
    map.conveyors[#map.conveyors + 1] = { x = belt.x, y = belt.y, w = belt.w, h = belt.h,
      dir = i % 2 == 1 and "e" or "w", cargo = "parts" }
    map.beacons[#map.beacons + 1] = { x = b:x(5.6), y = b:y(r + 1), color = "amber" }
    map.beacons[#map.beacons + 1] = { x = b:x(w - 5.6), y = b:y(r + 1), color = "amber" }
    b:place("laneline", 3, r - 2.4, w - 6, 0.12, { flat = true }) -- the aisle's walkway line
    -- Assembly arms either side of the belt, welding (they move: works.lua),
    -- presses and booths between the belts.
    for c = 9, w - 10, 9 do
      for _, side in ipairs({ -1, 1 }) do
        local ac, ar = c + rng:random() * 2 + (side > 0 and 3 or 0), side < 0 and r - 1.2 or r + 2.2
        local arm = b:place("arm", ac, ar, 1, 1, { round = true, seed = rng:random(1000) })
        map.arms[#map.arms + 1] = { x = arm.x + arm.w / 2, y = arm.y + arm.h / 2, side = side,
          phase = rng:random() * 6 }
      end
    end
    local mid = r + 6
    if mid < map.rows - 6 then
      local press = b:place("press", 8 + rng:random(0, 6), mid, 3, 2)
      map.presses[#map.presses + 1] = { x = press.x, y = press.y, w = press.w, h = press.h, phase = rng:random() * 3 }
      b:place("booth", w - 18 + rng:random(0, 6), mid - 0.5, 4, 3)
    end
  end
  -- The scrap pits, the bridge crane carrying finished haulers up the line.
  for _, sp in ipairs(Borderline.SCRAP_PITS) do
    b:place("pit", sp[1], sp[2], sp[3], sp[4], { water = true, seed = rng:random(1000), scrap = true })
    b:place("paint", sp[1] - 0.5, sp[2] + sp[4] + 0.1, sp[3] + 1, 0.8, { flat = true, text = "SCRAP", small = true })
    map.beacons[#map.beacons + 1] = { x = b:x(sp[1]), y = b:y(sp[2]), color = "red" }
  end
  map.bridgecranes[1] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(16), y1 = b:y(62), period = 40, phase = 1,
    load = "hauler" }
  -- Strip lights over the aisles, lamps on the Foreman's floor, beacons at the stairs and the bay.
  for _, r in ipairs({ 52, 40, 28, 16, 64 }) do
    for c = 6, w - 6, 8 do
      map.lights[#map.lights + 1] = { x = b:x(c), y = b:y(r), r = 280, color = { 0.85, 0.9, 1 }, a = 0.6 }
    end
  end
  for c = 8, w - 8, 10 do
    map.lights[#map.lights + 1] = { x = b:x(c), y = b:y(7), r = 300, color = { 1, 0.85, 0.6 }, a = 0.6 }
  end
  for _, at in ipairs({ { 2, edge - 0.5 }, { 6, edge - 0.5 }, { w - 6, edge - 0.5 }, { w - 2, edge - 0.5 },
    { 23.5, 2.5 }, { 32.5, 2.5 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "amber" }
  end
  b:place("pad", 3, 38, 5, 5, { flat = true, round = true }) -- the Fabricators' pads
  b:place("pad", w - 8, 38, 5, 5, { flat = true, round = true })
  local keep = { { 22, map.rows - 7, 33, map.rows - 1 }, { 22, 0, 33, 4 }, { 2, 37, 8, 44 }, { w - 9, 37, w - 3, 44 },
    { 2, edge - 1, 6, edge + 1 }, { w - 6, edge - 1, w - 2, edge + 1 } }
  b:scatter(rng, "crate", 16, 48, 3, map.rows - 6, keep)
  b:scatter(rng, "drum", 10, 40, 3, map.rows - 6, keep)
  -- The line's guards: gun haulers in the aisles between the belts, a squad
  -- down the middle one, kamikazes, a dozer at the foot of the Foreman's
  -- floor, and up on it a badass and two sentries.
  for _, at in ipairs({ { 10, 52 }, { w - 11, 52 }, { 10, 28 }, { w - 11, 28 } }) do
    b:post("GUN", at[1], at[2])
  end
  b:post("RPG", 28, 52)
  b:post("PLZ", 28, 28)
  b:squad({ "GUN", "GUN", "GUN" }, { { 10, 40 }, { w - 11, 40 } })
  b:pack("EXP", 20, 50, 3)
  b:pack("EXP", 36, 26, 3)
  b:post("DZR", 28, edge + 3)
  b:post("BAD", 28, 7)
  b:post("SEN", 12, 7)
  b:post("SEN", w - 13, 7)
  b:post("FIX", 26, 9)
  b:post("SHD", 30, 9)
  b:zone("The Line", edge + 1, map.rows - 1)
  b:zone("The Foreman's Floor", 0, edge)
  b:ends(25, map.rows - 7, 27, 1)
  b:commit()
end

-- 7. Thousand Papercuts ---------------------------------------------------------------

Borderline.ROAD_WIDTH = 6 -- tiles

--- The middle of the road on row r, in tiles: it winds as it climbs.
function Borderline.cutsMiddle(cols, r)
  return cols / 2 + 7 * math.sin(r / 11) + 2 * math.sin(r / 4.3)
end

local function buildCuts(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "cliff"
  map.cutsRoad = {}
  map.cranes, map.beacons, map.ropeway = {}, {}, nil
  for r = 0, map.rows - 1 do
    local m = Borderline.cutsMiddle(map.cols, math.max(3, math.min(r, map.rows - 9))) -- straight at both ends
    local c0 = math.floor(m - Borderline.ROAD_WIDTH / 2 + 0.5)
    local c1 = c0 + Borderline.ROAD_WIDTH - 1
    map.cutsRoad[r] = { c0, c1 }
    b:open(c0, r, c1, r)
  end
  b:ground("road", 0, 0, map.cols - 1, map.rows - 1)
  local top, bottom = map.cutsRoad[0], map.cutsRoad[map.rows - 1]
  b:place("door", top[1], 0, Borderline.ROAD_WIDTH, 2, { flat = true })
  -- A tower crane at the top, still building the bunker, over its door.
  crane(map, b, { top[2] + 2, 3, 0, 0 }, "nw", { top[1] + 3, 1 })
  -- The ore ropeway down the drop beside the road: a pylon every few rows,
  -- a station at either end (its buckets run: works.lua).
  local points = {}
  for r = map.rows - 3, 3, -8 do
    local road = map.cutsRoad[r]
    points[#points + 1] = { x = b:x(math.max(0.7, road[1] - 2)), y = b:y(r) }
  end
  map.ropeway = { points = points, period = 90 }
  -- Lamps up the road's east edge, beacons on the west where it bends.
  for r = map.rows - 6, 4, -10 do
    local road = map.cutsRoad[r]
    b:place("lamp", road[2] + 0.55, r, 0.3, 0.3, { flat = true, round = true })
    map.lights[#map.lights + 1] = { x = b:x(road[2] + 0.7), y = b:y(r + 0.15), r = 300, color = { 1, 0.88, 0.6 },
      a = 0.75 }
  end
  local lastBeacon = math.huge
  for r = map.rows - 2, 2, -1 do
    local here, before = map.cutsRoad[r], map.cutsRoad[r + 1]
    if here[1] ~= before[1] and lastBeacon - r >= 6 then
      map.beacons[#map.beacons + 1] = { x = b:x(here[1]) + 10, y = b:y(r), color = "amber" }
      lastBeacon = r
    end
  end
  map.beacons[#map.beacons + 1] = { x = b:x(top[1]), y = b:y(2.2), color = "red" }
  map.beacons[#map.beacons + 1] = { x = b:x(top[2] + 1), y = b:y(2.2), color = "red" }
  -- Sentry nests cut into the cliff, on the road's east edge, every so often.
  for r = 12, map.rows - 14, 14 do
    local road = map.cutsRoad[r]
    b:place("nest", road[2] - 0.2, r, 1.2, 1.2, { flat = true, round = true })
    b:post("SEN", road[2] + 0.4, r + 0.6) -- its sentry, flush in the rock
  end
  b:scatter(rng, "boulder", 16, 52, 6, map.rows - 8, { { bottom[1], map.rows - 7, bottom[2], map.rows - 1 } })
  b:scatter(rng, "drum", 8, 40, 6, map.rows - 8, { { bottom[1], map.rows - 7, bottom[2], map.rows - 1 } })
  b:scatter(rng, "cone", 14, 22, 6, map.rows - 8, { { bottom[1], map.rows - 7, bottom[2], map.rows - 1 } },
    { flat = true })
  -- Up the road: rocket haulers on the bends, jets making runs down it,
  -- gun haulers and kamikazes in between, and at the door everything left.
  local function middle(r)
    local road = map.cutsRoad[r]
    return (road[1] + road[2] + 1) / 2, r
  end
  for _, r in ipairs({ 112, 84, 56, 28 }) do
    b:post("RPG", middle(r))
  end
  for _, r in ipairs({ 98, 64 }) do
    b:post("JET", middle(r))
  end
  for _, r in ipairs({ 120, 92, 70, 42 }) do
    b:post("GUN", middle(r))
  end
  for _, r in ipairs({ 104, 50 }) do
    local c = middle(r)
    b:pack("EXP", c, r, 3)
  end
  b:post("BAD", middle(10))
  b:post("ARC", middle(14))
  b:post("SHD", middle(12))
  b:zone("The Foot of the Cliff", 100, map.rows - 1)
  b:zone("The Cuts", 20, 99)
  b:zone("The Bunker Door", 0, 19)
  b:ends(bottom[1], map.rows - 6, top[1] + 2, 1, 4)
  b:commit()
end

-- 8. The Bunker ---------------------------------------------------------------------

Borderline.CANNONS = 11 -- round the rim

-- The bunker's engine intakes, a turbine fan spinning down in each (tile
-- centres; radius in tiles): it flies on them.
Borderline.INTAKES = { { 9.5, 9.5 }, { 30.5, 9.5 }, { 9.5, 30.5 }, { 30.5, 30.5 } }
Borderline.INTAKE_R = 2.2

local function buildBunker(map, rng, T)
  local b = Blockout.new(map, T)
  map.outside = "sky"
  map.beacons, map.fans, map.radars, map.bridgecranes = {}, {}, {}, {}
  local n = map.cols
  b:open(3, 3, n - 4, n - 4)
  b:open(18, n - 3, 21, n - 1) -- the hatch up from inside
  b:ground("roof", 0, 0, n - 1, n - 1)
  b:place("hatch", 18, n - 3, 4, 3, { flat = true })
  -- The cannons, evenly round a square just inside the rim.
  local lo, hi = 4.2, n - 5.2
  local per = 4 * (hi - lo)
  for i = 0, Borderline.CANNONS - 1 do
    local d = (i + 0.5) * per / Borderline.CANNONS
    local c, r
    if d < hi - lo then
      c, r = lo + d, lo
    elseif d < 2 * (hi - lo) then
      c, r = hi, lo + d - (hi - lo)
    elseif d < 3 * (hi - lo) then
      c, r = hi - (d - 2 * (hi - lo)), hi
    else
      c, r = lo, hi - (d - 3 * (hi - lo))
    end
    b:place("cannon", c - 0.6, r - 0.6, 1.2, 1.2, { round = true, flat = true }) -- its mount
    b:post("SEN", c, r) -- and its gun, flush until you come up
  end
  b:place("pad", n / 2 - 4, n / 2 - 4, 8, 8, { flat = true, round = true }) -- the eye's hatch
  -- The painted walkway round the deck and across it, NO STEP by the intakes.
  for _, k in ipairs({ 6.6, n - 6.7 }) do
    b:place("laneline", 6.6, k, n - 13.2, 0.12, { flat = true })
    b:place("laneline", k, 6.6, 0.12, n - 13.2, { flat = true })
  end
  for _, from in ipairs({ 6.6, n / 2 + 4 }) do -- the cross, stopping at the pad
    b:place("laneline", n / 2 - 0.06, from, 0.12, n / 2 - 10.6, { flat = true })
    b:place("laneline", from, n / 2 - 0.06, n / 2 - 10.6, 0.12, { flat = true })
  end
  b:place("zebra", 17.5, n - 4.6, 5, 1.2, { flat = true })
  -- The intakes, their fans; the radar; the gantry loading a missile.
  local R = Borderline.INTAKE_R
  for _, at in ipairs(Borderline.INTAKES) do
    b:place("intake", at[1] - R, at[2] - R, 2 * R, 2 * R, { water = true, round = true })
    b:place("paint", at[1] - R, at[2] + R + 0.2, 2 * R, 0.8, { flat = true, text = "NO STEP", small = true })
    map.fans[#map.fans + 1] = { x = b:x(at[1]), y = b:y(at[2]), r = (R - 0.35) * T, phase = #map.fans * 0.7 }
  end
  b:place("mast", 30.4, 19.4, 1.2, 1.2, { round = true })
  map.radars[1] = { x = b:x(31), y = b:y(20), r = 70 }
  map.bridgecranes[1] = { x0 = b:x(3), x1 = b:x(n - 3), y0 = b:y(6), y1 = b:y(n - 7), period = 36, phase = 0.5,
    load = "missile" }
  -- Floodlights in the corners, beacons on the rim and at the hatch.
  for _, at in ipairs({ { 5.8, 5.8 }, { n - 6.5, 5.8 }, { 5.8, n - 6.5 }, { n - 7.2, n - 7.2 } }) do
    b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
    map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 460,
      color = { 1, 0.92, 0.75 }, a = 0.75 }
  end
  for _, at in ipairs({ { 3, 3 }, { n - 3, 3 }, { 3, n - 3 }, { n - 3, n - 3 }, { 17.5, n - 3 }, { 22.5, n - 3 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "red" }
  end
  b:scatter(rng, "vent", 12, 72, 7, n - 8, { { n / 2 - 5, n / 2 - 5, n / 2 + 4, n / 2 + 4 }, { 16, n - 8, 23, n - 1 } })
  b:zone("The Bunker", 0, n - 1)
  b:ends(17, n - 9, n / 2 - 1, n / 2 - 1)
  b:commit()
end

Borderline.builders = {
  wreck = buildWreck,
  landing = buildLanding,
  pit = buildPit,
  prosperity = buildProsperity,
  refinery = buildRefinery,
  assembly = buildAssembly,
  cuts = buildCuts,
  bunker = buildBunker,
}

--- Does `kind` name one of these maps?
function Borderline.builds(kind)
  return Borderline.builders[kind] ~= nil
end

--- Build map `map.kind` into `map` (Layout.generate's, with tiles still empty). `T` is the tile size.
function Borderline.build(map, rng, T)
  Borderline.builders[map.kind](map, rng, T)
  map.mapFloor = Borderline.MAP_FLOOR[map.kind]
end

return Borderline
