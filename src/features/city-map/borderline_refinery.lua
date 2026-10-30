-- The Refinery (docs/borderline.md, "5. The Refinery"), the fifth of the
-- Borderline maps, built for borderline.lua: a smelting hall, dark, a river
-- of molten Bragium snaking across its floor in four runs, the banks
-- between them the only floor there is; smelting tanks, ingots and ladles
-- on the banks, a casting pit by the outflow, bridge cranes running the
-- hall overhead. Every bridge over the river is drawn up: a bridge control
-- terminal on the bank below lowers the next run's (each guarded by a
-- hauler dock), so everyone fights up the hall a crossing at a time.

local Refinery = {}

-- The river's runs across the floor, bottom to top (the row of each run's
-- top; each is three tiles deep), the side it bends round on the way to
-- the next, and the columns its bridges cross at.
Refinery.RIVER = {
  { r = 64, bend = "w", bridges = { 10, 34 } },
  { r = 50, bend = "e", bridges = { 22 } },
  { r = 36, bend = "w", bridges = { 8, 36 } },
  { r = 22, bend = "e", bridges = { 24 } },
}

-- The bridges' locks, one a run, bottom to top: what the HUD calls each.
Refinery.LOCKS = { "THE FIRST BRIDGES", "THE SECOND BRIDGE", "THE THIRD BRIDGES", "THE LAST BRIDGE" }

-- The bridge control terminal on the bank below each run, away from the
-- bridges so somebody has to go and find it (tiles): `terminal`, the
-- hauler `dock` guarding it, `guns` gun haulers posted by it.
Refinery.POSTS = {
  { terminal = { 4.5, 70.5 }, dock = { 8.5, 74.5 }, guns = { { 7, 69 }, { 11.5, 71.5 } } },
  { terminal = { 43.5, 56.5 }, dock = { 39.5, 60.5 }, guns = { { 40.5, 54.5 }, { 43, 61 } } },
  { terminal = { 3.5, 47 }, dock = { 7.5, 43.5 }, guns = { { 6.5, 47.5 }, { 11, 45 } } },
  { terminal = { 43.5, 27.5 }, dock = { 39.5, 31.5 }, guns = { { 41, 26 }, { 43, 33 } } },
}

-- The casting pit by the outflow (tiles), where the ladles pour.
Refinery.CASTING = { 34, 3, 8, 6 }
-- Steam vents in the floor (tiles), venting now and then.
Refinery.VENTS = { { 6, 70 }, { 40, 68 }, { 14, 46 }, { 34, 54 }, { 6, 18 }, { 40, 33 }, { 28, 26 }, { 12, 10 } }
-- Ladles parked on the banks, waiting for the cranes (tiles).
Refinery.LADLES = { { 16, 75 }, { 30, 59 }, { 31, 41 }, { 15, 27 }, { 9, 6 } }

--- Molten Bragium over tiles (c, r, w, h): it stops walking, not rounds or
--- sight (the river is drawn whole, one run at a time; this is only what
--- stands in the way).
local function molten(b, c, r, w, h)
  local solids = b.map.solids
  solids[#solids + 1] = { x = b:x(c), y = b:y(r), w = w * b.T, h = h * b.T, water = true }
end

--- Where the bend joining run `i` to the next meets them (tiles: c0, c1),
--- for the bank's rail to stop there.
local function bendAt(i, w)
  local run = Refinery.RIVER[i]
  if run and Refinery.RIVER[i + 1] then
    local c = run.bend == "w" and 2 or w - 5
    return { c, c + 3 }
  end
end

--- The river: each run across the floor drawn whole, molten either side of
--- its bridges' gaps, each gap shut by its bridge standing up (a wall of
--- the run's lock, `water`, that comes down when it is lowered); the bends
--- along the walls joining one run to the next. Each run's `north` and
--- `south` say where along that bank a bend leaves it (no rail there, world
--- px). Leaves `keep` holding the river's tiles, so nothing is scattered on it.
local function river(map, b, w, keep)
  local T = b.T
  local before = nil
  for i, run in ipairs(Refinery.RIVER) do
    local l = b:lock("bridge" .. i, Refinery.LOCKS[i], true, before)
    before = l.name
    local up, down = bendAt(i, w), bendAt(i - 1, w)
    b:place("river", 2, run.r, w - 4, 3, { flat = true, seed = i * 31,
      north = up and { b:x(up[1]), b:x(up[2]) }, south = down and { b:x(down[1]), b:x(down[2]) } })
    map.flows[#map.flows + 1] = { x = b:x(2), y = b:y(run.r), w = (w - 4) * T, h = 3 * T,
      dir = i % 2 == 1 and "w" or "e" }
    keep[#keep + 1] = { 2, run.r, w - 3, run.r + 2 }
    local from = 2
    for _, c in ipairs(run.bridges) do
      molten(b, from, run.r, c - from, 3)
      b:lockWall(l, b:x(c), b:y(run.r), 3 * T, 3 * T, "drawbridge", true)
      map.drawbridges[#map.drawbridges + 1] = { x = b:x(c), y = b:y(run.r - 0.25), w = 3 * T, h = 3.5 * T,
        lock = l.name }
      map.beacons[#map.beacons + 1] = { x = b:x(c), y = b:y(run.r - 0.4), color = "amber" }
      map.beacons[#map.beacons + 1] = { x = b:x(c + 3), y = b:y(run.r + 3.4), color = "amber" }
      b:place("paint", c - 0.5, run.r + 3.35, 4, 0.7, { flat = true, text = "BRIDGE " .. i, small = true })
      from = c + 3
    end
    molten(b, from, run.r, w - 2 - from, 3)
    local nextRun = Refinery.RIVER[i + 1]
    if nextRun then -- the bend round to the next run, along the wall
      local c = run.bend == "w" and 2 or w - 5
      local h = run.r - nextRun.r - 3
      b:place("river", c, nextRun.r + 3, 3, h, { flat = true, seed = i * 17, wall = run.bend })
      molten(b, c, nextRun.r + 3, 3, h)
      map.flows[#map.flows + 1] = { x = b:x(c), y = b:y(nextRun.r + 3), w = 3 * T, h = h * T, dir = "n" }
      keep[#keep + 1] = { c, nextRun.r + 3, c + 2, run.r - 1 }
    end
  end
end

--- The works: the casting pit and its beacons, the steam vents, the
--- parked ladles, the bridge cranes and the pipes overhead, the work lamps
--- on the walls, the river's glow.
local function workings(map, rng, b, w)
  local T = b.T
  local K = Refinery.CASTING
  b:place("casting", K[1], K[2], K[3], K[4], { water = true, seed = rng:random(1000) })
  b:place("paint", K[1], K[2] + K[4] + 0.15, K[3], 0.8, { flat = true, text = "MOLTEN METAL", small = true })
  map.beacons[#map.beacons + 1] = { x = b:x(K[1]), y = b:y(K[2] + K[4]), color = "red" }
  map.beacons[#map.beacons + 1] = { x = b:x(K[1] + K[3]), y = b:y(K[2] + K[4]), color = "red" }
  for i, v in ipairs(Refinery.VENTS) do
    b:place("grille", v[1], v[2], 1, 1, { flat = true })
    map.steam[#map.steam + 1] = { x = b:x(v[1] + 0.5), y = b:y(v[2] + 0.5), phase = i * 1.37 }
  end
  for _, at in ipairs(Refinery.LADLES) do
    b:place("ladle", at[1], at[2], 1.6, 1.6, { round = true, seed = rng:random(1000) })
  end
  -- Two bridge cranes running the hall's length, a ladle under each.
  map.bridgecranes[1] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(14), y1 = b:y(52), period = 34, phase = 0 }
  map.bridgecranes[2] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(56), y1 = b:y(74), period = 26, phase = 2.4 }
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
  map.lights[#map.lights + 1] = { x = b:x(K[1] + K[3] / 2), y = b:y(K[2] + K[4] / 2), r = 380, color = { 0.8, 0.4, 1 },
    a = 0.9 }
end

--- Hyperbole's army in the hall (tiles).
local function army(b)
  -- Arc haulers hold the far end of every bridge under their domes,
  -- plasma haulers stand by the tanks, gun haulers walk the banks,
  -- kamikazes wait in the middle, a dozer and a badass guard the outflow,
  -- rocket haulers watch the last bridge from it; and round each bridge
  -- control, its dock and the gun haulers posted by it.
  for _, run in ipairs(Refinery.RIVER) do
    for _, c in ipairs(run.bridges) do
      b:post("ARC", c + 1.5, run.r - 1.5)
    end
  end
  b:post("PLZ", 20, 57)
  b:post("PLZ", 30, 43)
  b:post("PLZ", 15, 29)
  b:post("PLZ", 26, 71)
  b:squad({ "GUN", "GUN" }, { { 8, 58 }, { 40, 58 } })
  b:squad({ "GUN", "GUN" }, { { 8, 30 }, { 40, 30 } })
  b:squad({ "GUN", "STK" }, { { 12, 41 }, { 40, 41 } })
  b:pack("JNK", 34, 72, 3)
  b:pack("EXP", 24, 44, 3)
  b:post("DZR", 24, 9)
  b:post("BAD", 20, 6)
  b:post("FIX", 30, 6)
  b:post("FIX", 38, 58)
  b:post("SHD", 18, 44)
  b:post("SHD", 30, 28)
  b:post("RPG", 14, 15)
  b:post("RPG", 34, 15)
  for _, post in ipairs(Refinery.POSTS) do
    for _, g in ipairs(post.guns) do
      b:post("GUN", g[1], g[2])
    end
  end
end

--- Build the Refinery on `map` with blockout `b` (borderline.lua's).
function Refinery.build(map, rng, b)
  local T = b.T
  map.outside = "hall"
  map.beacons, map.flows, map.steam, map.bridgecranes, map.overpipes = {}, {}, {}, {}, {}
  map.drawbridges = {}
  local w = map.cols
  b:open(2, 2, w - 3, map.rows - 3)
  b:open(21, map.rows - 2, 26, map.rows - 1) -- the way in
  b:open(20, 0, 27, 1) -- the freight door
  b:ground("grate", 0, 0, w - 1, map.rows - 1)
  b:ground("outflow", 2, 2, w - 3, 12) -- the outflow, where the Smelter waits
  b:place("door", 20, 0, 8, 2, { flat = true })
  local keep = { { 18, map.rows - 6, 29, map.rows - 1 }, { 18, 0, 29, 4 } }
  river(map, b, w, keep)
  for _, run in ipairs(Refinery.RIVER) do -- the bridges' ends kept clear
    for _, c in ipairs(run.bridges) do
      keep[#keep + 1] = { c - 1, run.r - 3, c + 3, run.r + 5 }
    end
  end
  workings(map, rng, b, w)
  -- The bridge controls, each run's on the bank below it, each guarded by
  -- the hauler dock it runs.
  for i, post in ipairs(Refinery.POSTS) do
    local t, d = post.terminal, post.dock
    b:dockPost(map.locks[i], "bridge" .. i, t[1], t[2], d[1], d[2])
    keep[#keep + 1] = { math.floor(t[1]) - 1, math.floor(t[2]) - 1, math.floor(t[1]) + 1, math.floor(t[2]) + 1 }
    keep[#keep + 1] = { math.floor(d[1]) - 1, math.floor(d[2]) - 1, math.floor(d[1]) + 1, math.floor(d[2]) + 1 }
  end
  -- The freight door, shut until the Smelter is out (borderline/smelter.lua
  -- opens it): after the bridges', whose terminals go by their place in `locks`.
  local door = b:lock("door", "THE FREIGHT DOOR", true)
  b:lockWall(door, b:x(20), b:y(1.2), 8 * T, 0.5 * T)
  for _, at in ipairs(Refinery.LADLES) do
    keep[#keep + 1] = { at[1] - 1, at[2] - 1, at[1] + 2, at[2] + 2 }
  end
  local K = Refinery.CASTING
  keep[#keep + 1] = { K[1] - 1, K[2] - 1, K[1] + K[3], K[2] + K[4] + 1 }
  army(b)
  b:keepArmy(keep)
  -- Smelting tanks and the pipes between them, ingots stacked for the
  -- cranes, drums and crates, slag gone hard where the river spilled.
  b:scatter(rng, "tank", 14, 110, 4, map.rows - 6, keep)
  for _, at in ipairs({ { 6, 61 }, { 30, 44 }, { 12, 30 }, { 32, 16 } }) do
    if b:clear(b:x(at[1]), b:y(at[2]), 8 * T, 0.5 * T, 24) then
      b:place("pipe", at[1], at[2], 8, 0.5)
    end
  end
  b:scatter(rng, "ingots", 12, 56, 4, map.rows - 6, keep, { round = false })
  b:scatter(rng, "crate", 8, 48, 4, map.rows - 6, keep)
  b:scatter(rng, "drum", 10, 40, 4, map.rows - 6, keep)
  b:scatter(rng, "slag", 16, 70, 4, map.rows - 6, keep, { flat = true })
  for _, c in ipairs(map.cover) do
    if c.kind == "tank" then -- each glows through its ports
      map.lights[#map.lights + 1] = { x = c.x + c.w / 2, y = c.y + c.h / 2, r = 140, color = { 0.75, 0.35, 1 },
        a = 0.4 }
    end
  end
  -- The Smelter climbs out of the casting pit when the last bridge comes
  -- down, and stands beside it at the outflow, clear of the dozer and the
  -- badass posted there.
  map.boss = { kind = "smelter", x = b:x(28), y = b:y(6), fromX = b:x(K[1] + K[3] / 2),
    fromY = b:y(K[2] + K[4] / 2), after = "bridge" .. #Refinery.RIVER, unlocks = "door" }
  b:zone("The Intake", 54, map.rows - 1)
  b:zone("The Smelting Floor", 13, 53)
  b:zone("The Outflow", 0, 12)
  b:ends(21, map.rows - 7, 23, 1)
  b:commit()
end

return Refinery
