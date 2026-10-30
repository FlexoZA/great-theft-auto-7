-- The Bragium Pit (docs/borderline.md, "3. The Bragium Pit"), the third of
-- the Borderline maps, built for borderline.lua: an open-pit mine at dusk,
-- rings of terraces stepping down to the floor where Wilbur lands, a rim at
-- either end joined to it by a ramp each, the mine at work round it
-- (cranes, shafts with headframes, conveyors, haul trucks), the ramps down
-- onto the floor gated until the power terminals round the terraces are
-- hacked, and Hyperbole's army throughout.

local Pit = {}

-- The rings of terraces, by how far in from the map's edge they stand
-- (tiles), and where each ring's ledge is cut for a ramp down.
Pit.RINGS = {
  { inset = 15, gaps = { "w", "e" } },
  { inset = 22, gaps = { "s", "n" } },
}

-- The power terminals that open the way down onto the pit's floor, round
-- the terraces: two out on the outer terrace's sides, two on the bench's corners (tiles): `terminal` and
-- the hauler `dock` guarding it, `guns` gun haulers posted by it, `junk`
-- a pack of junk haulers about it ({ c, r, count }).
Pit.POSTS = {
  { key = "west", terminal = { 11.5, 24 }, dock = { 11.8, 36 }, guns = { { 12.5, 27 } }, junk = { 12, 40, 2 } },
  { key = "east", terminal = { 47.5, 36 }, dock = { 47.2, 24 }, guns = { { 46.5, 33 } }, junk = { 47, 20, 2 } },
  { key = "nw", terminal = { 17.5, 20.5 }, dock = { 20.5, 17.5 }, guns = {}, junk = { 19, 19.5, 2 } },
  { key = "se", terminal = { 41.5, 38.5 }, dock = { 38.5, 41.5 }, guns = {}, junk = { 40, 40, 2 } },
}

-- The mine shafts on the inner terrace (tiles: c, r, w, h), each with a
-- headframe over it winding its cage up and down (works.lua's `headframes`).
Pit.SHAFTS = { { 17, 34, 2.5, 2.5 }, { 40, 23, 2.5, 2.5 } }

--- Each ring's ledge: four walls, cut in the middle of a side for its
--- ramps, each with its rock face dropping inward to the level below.
local function terraces(b, n)
  local thick = 0.4
  local inward = { n = "s", s = "n", w = "e", e = "w" }
  for _, ring in ipairs(Pit.RINGS) do
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
      local face = { face = inward[name] }
      if cut[name] then
        if s[5] then -- along the top or bottom: the cut is a gap across it
          b:place("ledge", s[1], s[2], mid0 - s[1], s[4], face)
          b:place("ledge", mid1, s[2], s[1] + s[3] - mid1, s[4], face)
          b:place("ramp", mid0, s[2] - 0.3, 4, 1, { flat = true, down = inward[name] })
        else
          b:place("ledge", s[1], s[2], s[3], mid0 - s[2], face)
          b:place("ledge", s[1], mid1, s[3], s[2] + s[4] - mid1, face)
          b:place("ramp", s[1] - 0.3, mid0, 1, 4, { flat = true, down = inward[name] })
        end
      else
        b:place("ledge", s[1], s[2], s[3], s[4], face)
      end
    end
  end
end

--- The mine at work round the terraces: the pad, the haul road, the
--- conveyors, the cranes, the shafts and their headframes, the trucks'
--- tracks and the trucks, beacons and floodlights.
local function workings(map, rng, b, n, crane)
  local T = b.T
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
  for _, sh in ipairs(Pit.SHAFTS) do
    b:place("shaft", sh[1], sh[2], sh[3], sh[4], { water = true })
    map.headframes[#map.headframes + 1] = { x = b:x(sh[1] + sh[3] / 2), y = b:y(sh[2] + sh[4] / 2),
      phase = #map.headframes * 2.3 }
    map.beacons[#map.beacons + 1] = { x = b:x(sh[1]), y = b:y(sh[2]), color = "red" }
    map.beacons[#map.beacons + 1] = { x = b:x(sh[1] + sh[3]), y = b:y(sh[2] + sh[4]), color = "red" }
  end
  -- The haul trucks' tracks round the outer terrace and round the bench.
  map.tracks = {}
  for _, d in ipairs({ 11.5, 18.5 }) do
    local line = {}
    for _, p in ipairs({ { d, d }, { n - d, d }, { n - d, n - d }, { d, n - d }, { d, d } }) do
      line[#line + 1] = { b:x(p[1]), b:y(p[2]) }
    end
    map.tracks[#map.tracks + 1] = line
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
end

--- Hyperbole's army in the pit (tiles).
local function army(b, n)
  -- Plasma haulers on the terraces' corners, gun haulers at the ramps and
  -- walking the outer terrace and the bench, a pair of stalkers the other
  -- way round, rocket haulers over the way out, drones with the squads,
  -- junk haulers on the floor (Wilbur lands there later) and round the
  -- power terminals.
  for _, at in ipairs({ { 11, 11 }, { n - 12, 11 }, { 11, n - 12 }, { n - 12, n - 12 }, { 41, 18 }, { 18, 41 } }) do
    b:post("PLZ", at[1], at[2])
  end
  b:post("GUN", 13, n / 2, 0) -- either side of the first ring's ramps, watching across
  b:post("GUN", n - 13, n / 2, math.pi)
  b:post("GUN", 18, 18)
  b:post("GUN", 41, 41)
  b:squad({ "GUN", "GUN" }, { { 11.5, 11.5 }, { n - 12, 11.5 }, { n - 12, n - 12 }, { 11.5, n - 12 } })
  b:squad({ "GUN", "GUN", "GUN" }, { { 18.5, 18.5 }, { n - 18.5, 18.5 }, { n - 18.5, n - 18.5 }, { 18.5, n - 18.5 } })
  b:squad({ "STK", "STK" }, { { n - 12, n - 12 }, { 11.5, n - 12 }, { 11.5, 11.5 }, { n - 12, 11.5 } }) -- the other way
  b:pack("JNK", n / 2, n / 2, 4)
  b:post("SHD", 40, 20) -- shield drones by the inner plasma haulers
  b:post("SHD", 20, 40)
  b:post("FIX", 20, 19) -- medic drones with the bench's squad
  b:post("FIX", 40, 41)
  b:post("RPG", 14, 9.5) -- rocket haulers up on the outer terrace's north side, over the way out
  b:post("RPG", n - 14, 9.5)
  b:post("GUN", 26.5, 9.5) -- and gun haulers at the foot of the ramp up to the mine lift
  b:post("GUN", 33.5, 9.5)
  for _, post in ipairs(Pit.POSTS) do -- and round each of the power terminals
    for _, g in ipairs(post.guns) do
      b:post("GUN", g[1], g[2])
    end
    b:pack("JNK", post.junk[1], post.junk[2], post.junk[3])
  end
end

--- Build the Bragium Pit on `map` with blockout `b` (borderline.lua's),
--- `crane(map, b, p, corner, at)` putting up a tower crane.
function Pit.build(map, rng, b, crane)
  local T = b.T
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
  b:ground("bench", 15, 15, n - 16, n - 16)
  b:ground("pitfloor", 22, 22, n - 23, n - 23)
  b:place("ramp", 28, n - 8, 4, 1, { flat = true, down = "n" })
  b:place("ramp", 28, 7, 4, 1, { flat = true, down = "s" })
  -- The lifts on the rims: the ferry's top station you come up on, the
  -- mine lift up to Prosperity you leave by.
  b:place("lift", 26.5, n - 6.6, 7, 3, { flat = true })
  b:place("lift", 26, 2.2, 7, 2.6, { flat = true, text = "MINE LIFT" })
  terraces(b, n)
  workings(map, rng, b, n, crane)
  local keep = { { 26, 26, 33, 33 }, { 26, n - 9, 33, n - 3 }, { 26, 2, 33, 9 }, { 13, 28, 24, 31 },
    { n - 25, 28, n - 13, 31 }, { 28, 20, 31, 24 }, { 28, n - 25, 31, n - 21 } }
  -- The two ramps down onto the pit's floor gated until the power terminals
  -- round the terraces are all hacked, each guarded by the hauler dock it
  -- runs: nobody gets to Wilbur's pad before then.
  local floor = b:lock("floor", "THE PIT'S FLOOR", true)
  b:lockWall(floor, b:x(28), b:y(22), 4 * T, 0.4 * T)
  b:lockWall(floor, b:x(28), b:y(n - 22.4), 4 * T, 0.4 * T)
  for _, post in ipairs(Pit.POSTS) do
    local t, d = post.terminal, post.dock
    b:dockPost(floor, post.key, t[1], t[2], d[1], d[2])
    keep[#keep + 1] = { math.floor(t[1]) - 1, math.floor(t[2]) - 1, math.floor(t[1]) + 1, math.floor(t[2]) + 1 }
    keep[#keep + 1] = { math.floor(d[1]) - 1, math.floor(d[2]) - 1, math.floor(d[1]) + 1, math.floor(d[2]) + 1 }
  end
  army(b, n)
  b:keepArmy(keep) -- nothing scattered on anyone's spot
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
  -- Wilbur comes down onto the pad when somebody first sets foot on the
  -- pit's floor; the mine lift stays shut until his keycard is picked up.
  map.boss = { kind = "wilbur", x = b:x(30), y = b:y(30),
    wake = { x0 = b:x(22), y0 = b:y(22), x1 = b:x(n - 22), y1 = b:y(n - 22) } }
  b:zone("The Rim", n - 8, n - 1)
  b:zone("The Pit", 8, n - 9)
  b:zone("The Mine Lift", 0, 7)
  b:ends(27, n - 6, 29, 3)
  b:commit()
end

return Pit
