-- The Assembly Line (docs/borderline.md, "6. The Assembly Line"), the
-- sixth of the Borderline maps, built for borderline.lua: the factory floor
-- under strip lights, four belts across it carrying hauler parts and
-- whoever stands on them (each the other way from the last), welding arms
-- either side of them, presses and paint booths between, scrap pits, racks
-- of parts along the walls; a Fabricator on a pad each side of the floor,
-- building haulers; and up a step at the top the Foreman's floor, its
-- stairs shuttered until both Fabricators are down.

local Assembly = {}

-- The belts across the floor, bottom to top (each two tiles deep), and the
-- Foreman's floor up top (rows).
Assembly.BELT_ROWS = { 58, 46, 34, 22 }
Assembly.UPPER = { 3, 12 }
Assembly.BELT_SPEED = 40 -- px/s the belts carry everything on them, parts and people

-- The scrap pits beside the line (tiles), where the rejects go.
Assembly.SCRAP_PITS = { { 2.2, 49, 4.6, 6 }, { 49.4, 26, 4.6, 6 } }

-- The Fabricators' pads either side of the floor (tiles: c, r, the pad's
-- side) and the way each one's haulers walk out, towards the middle.
Assembly.PADS = { { 3, 38, 5, "e" }, { 48, 38, 5, "w" } }

-- Racks of hauler parts along the walls (tiles: c, r, w, h).
Assembly.RACKS = { { 2.2, 61, 1, 5 }, { 52.8, 61, 1, 5 }, { 2.2, 26, 1, 5 }, { 52.8, 49, 1, 5 }, { 2.2, 15.5, 1, 4 },
  { 52.8, 15.5, 1, 4 } }

--- The belts, and round each the arms welding over it, a press and a paint
--- booth between it and the next, the aisle's walkway line, its beacons.
local function line(map, rng, b, w)
  for i, r in ipairs(Assembly.BELT_ROWS) do
    local dir = i % 2 == 1 and "e" or "w"
    local belt = b:place("belt", 6, r, w - 12, 2, { flat = true, dir = dir })
    -- Hauler parts ride it (works.lua), and so does anyone standing on it.
    map.conveyors[#map.conveyors + 1] = { x = belt.x, y = belt.y, w = belt.w, h = belt.h, dir = dir,
      cargo = "parts", carry = true, speed = Assembly.BELT_SPEED }
    map.beacons[#map.beacons + 1] = { x = b:x(5.6), y = b:y(r + 1), color = "amber" }
    map.beacons[#map.beacons + 1] = { x = b:x(w - 5.6), y = b:y(r + 1), color = "amber" }
    b:place("laneline", 3, r - 2.4, w - 6, 0.12, { flat = true }) -- the aisle's walkway line
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
      local press = b:place("press", 14 + rng:random(0, 4), mid, 3, 2) -- in from the aisles' posts
      map.presses[#map.presses + 1] = { x = press.x, y = press.y, w = press.w, h = press.h, phase = rng:random() * 3 }
      b:place("booth", w - 24 + rng:random(0, 4), mid - 0.5, 4, 3, { seed = rng:random(1000) })
    end
  end
  for _, sp in ipairs(Assembly.SCRAP_PITS) do
    b:place("pit", sp[1], sp[2], sp[3], sp[4], { water = true, seed = rng:random(1000), scrap = true })
    b:place("paint", sp[1] - 0.5, sp[2] + sp[4] + 0.1, sp[3] + 1, 0.8, { flat = true, text = "SCRAP", small = true })
    map.beacons[#map.beacons + 1] = { x = b:x(sp[1]), y = b:y(sp[2]), color = "red" }
  end
  for _, rk in ipairs(Assembly.RACKS) do
    b:place("rack", rk[1], rk[2], rk[3], rk[4], { seed = rng:random(1000) })
  end
  map.bridgecranes[1] = { x0 = b:x(2), x1 = b:x(w - 2), y0 = b:y(16), y1 = b:y(62), period = 40, phase = 1,
    load = "hauler" }
  for _, rr in ipairs({ 52, 40, 28, 16, 64 }) do -- strip lights over the aisles
    for c = 6, w - 6, 8 do
      map.lights[#map.lights + 1] = { x = b:x(c), y = b:y(rr), r = 280, color = { 0.85, 0.9, 1 }, a = 0.6 }
    end
  end
  for c = 8, w - 8, 10 do -- lamps over the Foreman's floor
    map.lights[#map.lights + 1] = { x = b:x(c), y = b:y(7), r = 300, color = { 1, 0.85, 0.6 }, a = 0.6 }
  end
end

--- The Fabricators on their pads, each a `water` solid (no walking through
--- it, rounds fly to it), and the lock on the stairs they keep shut.
local function fabricators(map, b, w, edge)
  local T = b.T
  map.fabricators = {}
  for i, p in ipairs(Assembly.PADS) do
    b:place("fabpad", p[1], p[2], p[3], p[3], { flat = true, n = i })
    local f = { x = b:x(p[1] + 0.5), y = b:y(p[2] + 0.5), w = (p[3] - 1) * T, h = (p[3] - 1) * T, face = p[4] }
    map.fabricators[i] = f
    map.solids[#map.solids + 1] = { x = f.x, y = f.y, w = f.w, h = f.h, water = true }
  end
  local stairs = b:lock("stairs", "THE FOREMAN'S FLOOR", true)
  b:lockWall(stairs, b:x(2), b:y(edge), 4 * T, 0.4 * T)
  b:lockWall(stairs, b:x(w - 6), b:y(edge), 4 * T, 0.4 * T)
end

--- Hyperbole's army on the line (tiles).
local function army(b, w, edge)
  -- Gun haulers in the aisles between the belts and round the Fabricators,
  -- a squad down the middle aisle, a gun and stalker pair the other way,
  -- kamikazes, rocket and plasma haulers on the line, shield drones by the
  -- Fabricators; a dozer at the foot of the Foreman's floor, and up on it
  -- a badass and two sentries, rocket haulers watching the stairs.
  for _, at in ipairs({ { 10, 52 }, { w - 11, 52 }, { 10, 28 }, { w - 11, 28 }, { 10, 37 }, { 10, 44 }, { w - 11, 37 },
    { w - 11, 44 } }) do
    b:post("GUN", at[1], at[2])
  end
  b:post("RPG", 28, 52)
  b:post("PLZ", 28, 28)
  b:post("PLZ", 20, 64)
  b:squad({ "GUN", "GUN", "GUN" }, { { 10, 40 }, { w - 11, 40 } })
  b:squad({ "GUN", "STK" }, { { w - 14, 31 }, { 14, 31 } })
  b:pack("EXP", 20, 50, 3)
  b:pack("EXP", 36, 26, 3)
  b:post("SHD", 9, 41)
  b:post("SHD", w - 10, 41)
  b:post("FIX", 28, 40)
  b:post("DZR", 28, edge + 3)
  b:post("RPG", 4, edge + 3)
  b:post("RPG", w - 5, edge + 3)
  b:post("BAD", 28, 7)
  b:post("SEN", 12, 7)
  b:post("SEN", w - 13, 7)
  b:post("FIX", 26, 9)
  b:post("SHD", 30, 9)
end

--- Build the Assembly Line on `map` with blockout `b` (borderline.lua's).
function Assembly.build(map, rng, b)
  map.outside = "plant"
  map.beacons, map.conveyors, map.arms, map.presses, map.bridgecranes = {}, {}, {}, {}, {}
  local w = map.cols
  b:open(2, 2, w - 3, map.rows - 3)
  b:open(25, map.rows - 2, 30, map.rows - 1) -- the way in
  b:open(24, 0, 31, 1) -- the shipping bay
  b:ground("steel", 0, 0, w - 1, map.rows - 1)
  b:ground("upper", 2, 2, w - 3, Assembly.UPPER[2])
  b:place("bay", 24, 0, 8, 2.5, { flat = true })
  -- The Foreman's floor is up a step: a wall across with stairs at both ends.
  local edge = Assembly.UPPER[2] + 1
  b:place("step", 6, edge, w - 12, 0.4)
  b:place("stairs", 2, edge - 0.5, 4, 1.5, { flat = true })
  b:place("stairs", w - 6, edge - 0.5, 4, 1.5, { flat = true })
  line(map, rng, b, w)
  fabricators(map, b, w, edge)
  for _, at in ipairs({ { 2, edge - 0.5 }, { 6, edge - 0.5 }, { w - 6, edge - 0.5 }, { w - 2, edge - 0.5 },
    { 23.5, 2.5 }, { 32.5, 2.5 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "amber" }
  end
  local keep = { { 22, map.rows - 7, 33, map.rows - 1 }, { 22, 0, 33, 4 }, { 2, 37, 9, 44 }, { w - 10, 37, w - 3, 44 },
    { 2, edge - 1, 6, edge + 1 }, { w - 6, edge - 1, w - 2, edge + 1 } }
  for _, r in ipairs(Assembly.BELT_ROWS) do -- nothing scattered on a belt
    keep[#keep + 1] = { 6, r - 1, w - 7, r + 2 }
  end
  army(b, w, edge)
  b:keepArmy(keep)
  b:scatter(rng, "crate", 12, 48, 3, map.rows - 6, keep)
  b:scatter(rng, "drum", 8, 40, 3, map.rows - 6, keep)
  b:scatter(rng, "cart", 8, 52, 3, map.rows - 6, keep, { round = false })
  b:zone("The Line", edge + 1, map.rows - 1)
  b:zone("The Foreman's Floor", 0, edge)
  b:ends(25, map.rows - 7, 27, 1)
  b:commit()
end

return Assembly
