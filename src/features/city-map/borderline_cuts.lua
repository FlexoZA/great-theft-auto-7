-- Thousand Papercuts (docs/borderline.md, "7. Thousand Papercuts"), the
-- seventh of the Borderline maps, built for borderline.lua: Hyperbole's
-- service road winding up a cliff at dusk, the drop on its west side with
-- an ore ropeway down it, the rock on its east with sentry nests cut into
-- it, the bunker's door at the top with a crane still building over it.
-- Everything Max has left comes up the road behind you (the borderline
-- feature's pursuit.lua, from `map.pursuit`), and at the top you hold the
-- door while Yappy opens it, the waves coming up the road at you.

local Cuts = {}

Cuts.ROAD_WIDTH = 6 -- tiles
Cuts.HOLD_TIME = 60 -- seconds of standing at the door while Yappy opens it

--- The middle of the road on row r, in tiles: it winds as it climbs.
function Cuts.middle(cols, r)
  return cols / 2 + 7 * math.sin(r / 11) + 2 * math.sin(r / 4.3)
end

-- The waves at the door while Yappy opens it: how far through the hack
-- each comes, what it is, and the row down the road it comes up from.
Cuts.DOOR_WAVES = {
  { 0.15, { "GUN", "GUN", "JNK" }, 34 },
  { 0.35, { "EXP", "EXP", "GUN" }, 38 },
  { 0.55, { "STK", "GUN", "RPG" }, 34 },
  { 0.75, { "GUN", "GUN", "EXP", "ARC" }, 40 },
  { 0.9, { "BAD" }, 34 },
}

--- The road: open tiles up every row (`map.cutsRoad`: its columns on each,
--- for the render), straight at both ends, and what the pursuit needs of
--- it (`map.pursuit`: its middle and half width on every row, px).
local function road(map, b)
  local T = b.T
  map.cutsRoad = {}
  local rows = {}
  for r = 0, map.rows - 1 do
    local m = Cuts.middle(map.cols, math.max(3, math.min(r, map.rows - 9))) -- straight at both ends
    local c0 = math.floor(m - Cuts.ROAD_WIDTH / 2 + 0.5)
    local c1 = c0 + Cuts.ROAD_WIDTH - 1
    map.cutsRoad[r] = { c0, c1 }
    rows[r] = { x = b:x((c0 + c1 + 1) / 2), half = Cuts.ROAD_WIDTH * T / 2 }
    b:open(c0, r, c1, r)
  end
  map.pursuit = { tile = T, y0 = map.y0, rows = rows, bottom = b:y(map.rows - 2), stop = b:y(22) }
  b:ground("road", 0, 0, map.cols - 1, map.rows - 1)
end

--- The works along it: the crane over the door, the ore ropeway down the
--- drop, lamps up the east edge, beacons on the bends and at the door, the
--- sentry nests in the rock.
local function works(map, b, crane)
  local top = map.cutsRoad[0]
  b:place("bunkerdoor", top[1], 0, Cuts.ROAD_WIDTH, 2, { flat = true })
  crane(map, b, { top[2] + 2, 3, 0, 0 }, "nw", { top[1] + 3, 1 })
  local points = {}
  for r = map.rows - 3, 3, -8 do
    local here = map.cutsRoad[r]
    points[#points + 1] = { x = b:x(math.max(0.7, here[1] - 2)), y = b:y(r) }
  end
  map.ropeway = { points = points, period = 90 }
  for r = map.rows - 6, 4, -10 do
    local here = map.cutsRoad[r]
    b:place("lamp", here[2] + 0.55, r, 0.3, 0.3, { flat = true, round = true })
    map.lights[#map.lights + 1] = { x = b:x(here[2] + 0.7), y = b:y(r + 0.15), r = 300, color = { 1, 0.88, 0.6 },
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
  for r = 12, map.rows - 14, 14 do -- sentry nests cut into the cliff, on the road's east edge
    local here = map.cutsRoad[r]
    b:place("nest", here[2] - 0.2, r, 1.2, 1.2, { flat = true, round = true })
    b:post("SEN", here[2] + 0.4, r + 0.6) -- its sentry, flush in the rock
  end
end

--- Build Thousand Papercuts on `map` with blockout `b` (borderline.lua's),
--- `crane(map, b, p, corner, at)` putting up a tower crane.
function Cuts.build(map, rng, b, crane)
  map.outside = "cliff"
  map.cranes, map.beacons, map.ropeway = {}, {}, nil
  road(map, b)
  works(map, b, crane)
  local top, bottom = map.cutsRoad[0], map.cutsRoad[map.rows - 1]
  local function middle(r)
    local here = map.cutsRoad[r]
    return (here[1] + here[2] + 1) / 2, r
  end
  -- The bunker door: held while Yappy opens it, the waves coming up the road.
  b:hold(top[1], 2.4, Cuts.ROAD_WIDTH, 3.6, Cuts.HOLD_TIME)
  for _, w in ipairs(Cuts.DOOR_WAVES) do
    local c, r = middle(w[3])
    b:wave(w[1], w[2], c, r)
  end
  -- Not much ahead of you: the danger is behind. Rocket haulers on three
  -- of the bends to slow you down (and the sentries in the rock).
  for _, r in ipairs({ 84, 56, 28 }) do
    b:post("RPG", middle(r))
  end
  local keep = { { bottom[1], map.rows - 7, bottom[2], map.rows - 1 }, { top[1], 0, top[2], 7 } }
  b:keepArmy(keep)
  b:scatter(rng, "boulder", 16, 52, 8, map.rows - 8, keep)
  b:scatter(rng, "drum", 8, 40, 8, map.rows - 8, keep)
  b:scatter(rng, "cone", 14, 22, 8, map.rows - 8, keep, { flat = true })
  b:zone("The Foot of the Cliff", 100, map.rows - 1)
  b:zone("The Cuts", 20, 99)
  b:zone("The Bunker Door", 0, 19)
  b:ends(bottom[1], map.rows - 6, top[1] + 2, 1, 4)
  b:commit()
end

return Cuts
