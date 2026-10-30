-- Prosperity (docs/borderline.md, "4. Prosperity"), the fourth of the
-- Borderline maps, built for borderline.lua: Max's factory town under a
-- glass dome at dusk, a grid of blocks (factories with smoking chimneys,
-- loading lots, two "Phase 2" building sites with their cranes) with
-- pavements round them, the avenue up the middle, the plaza with his
-- statue, and in the four corner blocks his four big screens, each on its
-- square guarded by a hauler dock. The north gate stays shut until all
-- four are shot down (the borderline feature's screens.lua opens it).

local Prosperity = {}

-- The blocks between the streets, in tiles: columns and rows (inclusive).
-- The plaza takes the middle rows; the avenue runs up the middle.
Prosperity.COLS = { { 6, 13 }, { 18, 25 }, { 30, 37 }, { 42, 49 } }
Prosperity.ROWS = { { 6, 15 }, { 20, 29 }, { 56, 65 }, { 70, 79 } }
Prosperity.PLAZA = { 34, 52 } -- rows

-- The blocks that are building sites ("Prosperity Phase 2": by index into
-- COLS, ROWS), each a deep foundation hole with a tower crane at a corner.
Prosperity.SITES = { { 2, 2, crane = "nw" }, { 3, 3, crane = "se" } }

-- The corner blocks that are Max's screens' squares (by index into COLS,
-- ROWS): a paved square, the screen up on two legs in the middle of it
-- (`map.screens`), a hauler dock and a couple of gun haulers guarding it.
Prosperity.SCREENS = { { 1, 1 }, { 4, 1 }, { 1, 4 }, { 4, 4 } }
Prosperity.SCREEN_W, Prosperity.SCREEN_H = 5, 3 -- tiles, the panel

--- A factory block over tiles (c, r, w, h), its chimney's smoke rising (works.lua's `stacks`).
local function factory(map, b, rng, c, r, w, h)
  local f = b:place("tower", c, r, w, h, { seed = rng:random(1000) })
  local k1, k2 = rng:random(), rng:random()
  f.stackX, f.stackY = f.x + f.w * (0.2 + 0.6 * k1), f.y + f.h * (0.25 + 0.5 * k2)
  map.stacks[#map.stacks + 1] = { x = f.stackX, y = f.stackY, phase = k1 * 7 }
end

--- Is block (ci, ri) in `list` ({ ci, ri } each)? Returns its entry.
local function blockIn(list, ci, ri)
  for _, e in ipairs(list) do
    if e[1] == ci and e[2] == ri then
      return e
    end
  end
  return nil
end

--- One of Max's screens' squares on block tiles `cs`, `rs`: paved, the
--- screen's legs and planters at its corners; the panel itself up on the
--- legs goes in `map.screens` (screens.lua draws and hits it), its guards
--- in the army.
local function screenSquare(map, b, cs, rs)
  local T = b.T
  local w = cs[2] - cs[1] + 1
  b:ground("square", cs[1], rs[1], cs[2], rs[2])
  local sw, sh = Prosperity.SCREEN_W, Prosperity.SCREEN_H
  local sx, sy = cs[1] + (w - sw) / 2, rs[1] + 1.5
  map.screens[#map.screens + 1] = { x = b:x(sx), y = b:y(sy), w = sw * T, h = sh * T }
  for _, k in ipairs({ 0.9, sw - 1.6 }) do -- its two legs
    b:place("pylon", sx + k, sy + sh + 0.1, 0.7, 0.7, { round = true })
  end
  for _, at in ipairs({ { cs[1] + 0.2, rs[1] + 0.2 }, { cs[2] - 0.8, rs[1] + 0.2 }, { cs[1] + 0.2, rs[2] - 0.8 },
    { cs[2] - 0.8, rs[2] - 0.8 } }) do
    b:place("planter", at[1], at[2], 0.9, 0.9, { round = true, seed = at[1] * 7 + at[2] })
  end
  local cx = cs[1] + w / 2
  b:post("DCK", cx, rs[2] - 1.8)
  b:post("GUN", cs[1] + 1.2, rs[2] - 1)
  b:post("GUN", cs[2] - 0.2, rs[2] - 1)
  map.lights[#map.lights + 1] = { x = b:x(cx), y = b:y(sy + sh / 2), r = 380, color = { 1, 0.86, 0.4 }, a = 0.6 }
end

--- The blocks: each its pavement round it, then what it is: one of Max's
--- screens' squares, a Phase 2 building site, a loading lot, or one or two
--- factories.
local function blocks(map, rng, b, crane)
  for ci, cs in ipairs(Prosperity.COLS) do
    for ri, rs in ipairs(Prosperity.ROWS) do
      local w, h = cs[2] - cs[1] + 1, rs[2] - rs[1] + 1
      b:place("sidewalk", cs[1] - 0.6, rs[1] - 0.6, w + 1.2, h + 1.2, { flat = true })
      local site = blockIn(Prosperity.SITES, ci, ri)
      if blockIn(Prosperity.SCREENS, ci, ri) then
        screenSquare(map, b, cs, rs)
      elseif site then -- Phase 2: a foundation hole, fenced, its crane over it
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
end

--- The plaza: its pavement, Max larger than life in the middle on a gold
--- ring set in the paving, planters round its edges.
local function plaza(b, mr)
  local P0, P1 = Prosperity.PLAZA[1], Prosperity.PLAZA[2]
  b:place("sidewalk", 5.4, P0 - 0.6, 45.2, P1 - P0 + 2.2, { flat = true })
  b:place("inlay", 23, mr - 5, 10, 10, { flat = true, round = true })
  b:place("statue", 26, mr - 2, 4, 4, { round = true })
  for _, c in ipairs({ 9, 15, 21, 34, 40, 46 }) do
    for _, r in ipairs({ P0 + 0.6, P1 - 0.5 }) do
      b:place("planter", c, r, 0.9, 0.9, { round = true, seed = c * 3 + r })
    end
  end
end

--- The streets: centre lines down them (not across the plaza), zebra
--- crossings where the avenue meets it, street lamps down them, floodlights
--- on the plaza's corners, beacons at the gates, pipe bridges over the avenue.
local function streets(map, b)
  local P0, P1 = Prosperity.PLAZA[1], Prosperity.PLAZA[2]
  for _, c in ipairs({ 16, 28, 40 }) do
    b:place("laneline", c - 0.06, 2, 0.12, P0 - 3, { flat = true })
    b:place("laneline", c - 0.06, P1 + 1, 0.12, map.rows - P1 - 4, { flat = true })
  end
  for _, r in ipairs({ 18, 32, 54, 68 }) do
    b:place("laneline", 2, r - 0.06, map.cols - 4, 0.12, { flat = true })
  end
  b:place("zebra", 25.5, P0 - 1.4, 5, 1.2, { flat = true })
  b:place("zebra", 25.5, P1 + 0.2, 5, 1.2, { flat = true })
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
  for _, r in ipairs({ 10.5, 74.5 }) do
    map.overpipes[#map.overpipes + 1] = { x0 = b:x(25.6), x1 = b:x(30.4), y = b:y(r) }
  end
end

--- Max's garrison (tiles): jet haulers round the plaza and up north, rocket
--- and plasma haulers on the cross streets, a squad walking the avenue and
--- one round the north district and one the south; kamikazes about the
--- plaza and the districts, dozers across the avenue, the first badass by
--- the statue with its drones. (The screens' guards are screenSquare's.)
local function garrison(b, mr)
  local P0, P1 = Prosperity.PLAZA[1], Prosperity.PLAZA[2]
  b:post("JET", 20, P0 + 3)
  b:post("JET", 36, P0 + 3)
  b:post("JET", 28, 18)
  b:post("JET", 28, 68)
  b:post("RPG", 16, 67)
  b:post("RPG", 40, 31)
  b:post("RPG", 40, 55)
  b:post("PLZ", 40, 67)
  b:post("PLZ", 16, 31)
  b:post("PLZ", 16, 55)
  b:post("GUN", 22, P1 - 2)
  b:post("GUN", 34, P1 - 2)
  b:squad({ "GUN", "GUN", "GUN" }, { { 28, 55 }, { 28, 81 } })
  b:squad({ "GUN", "GUN" }, { { 16, 31 }, { 40, 31 }, { 40, 18 }, { 16, 18 } })
  b:squad({ "GUN", "GUN", "FIX" }, { { 16, 55 }, { 40, 55 }, { 40, 68 }, { 16, 68 } })
  b:pack("EXP", 16, 50, 3)
  b:pack("EXP", 40, 18, 3)
  b:pack("EXP", 40, 70, 3)
  b:post("DZR", 28, P1 + 1)
  b:post("DZR", 28, 16)
  b:post("BAD", 28, mr + 5)
  b:post("FIX", 24, mr + 6)
  b:post("SHD", 32, mr + 6)
end

--- Build Prosperity on `map` with blockout `b` (borderline.lua's),
--- `crane(map, b, p, corner, at)` putting up a tower crane.
function Prosperity.build(map, rng, b, crane)
  local T = b.T
  map.outside = "dome"
  map.cranes, map.beacons, map.stacks, map.overpipes, map.screens = {}, {}, {}, {}, {}
  b:open(2, 2, map.cols - 3, map.rows - 3)
  b:open(25, map.rows - 2, 30, map.rows - 1) -- the south gate
  b:open(25, 0, 30, 1) -- the north gate
  b:ground("street", 0, 0, map.cols - 1, map.rows - 1)
  b:ground("plaza", 6, Prosperity.PLAZA[1], 49, Prosperity.PLAZA[2])
  b:place("gate", 25, map.rows - 2, 6, 2, { flat = true })
  b:place("gate", 25, 0, 6, 2, { flat = true })
  -- The north gate shut until Max's four screens are shot down
  -- (the borderline feature's screens.lua opens the lock).
  local gate = b:lock("gate", "THE NORTH GATE", true)
  b:lockWall(gate, b:x(25), b:y(1.55), 6 * T, 0.45 * T)
  local mr = (Prosperity.PLAZA[1] + Prosperity.PLAZA[2]) / 2
  blocks(map, rng, b, crane)
  plaza(b, mr)
  streets(map, b)
  garrison(b, mr)
  local keep = { { 22, 80, 33, 87 }, { 22, 0, 33, 4 }, { 22, mr - 6, 33, mr + 6 } }
  b:keepArmy(keep)
  b:scatter(rng, "crate", 18, 44, 3, map.rows - 4, keep)
  b:scatter(rng, "drum", 14, 40, 3, map.rows - 4, keep)
  b:scatter(rng, "cone", 18, 22, 3, map.rows - 4, keep, { flat = true })
  b:zone("South District", 53, map.rows - 1)
  b:zone("Max Plaza", Prosperity.PLAZA[1], Prosperity.PLAZA[2])
  b:zone("North District", 0, 33)
  b:ends(25, map.rows - 7, 27, 1)
  b:commit()
end

return Prosperity
