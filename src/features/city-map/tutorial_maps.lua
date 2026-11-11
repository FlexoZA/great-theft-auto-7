-- The maps of Shoeman's school of survival (the tutorial feature,
-- docs/tutorial.md). So far one is built; the park, the scrap yard and the
-- town are still open fields (city-map/init.lua's `empty` specs):
--   tutorial-road  Shoeman's Road (level 1): small and tall. At the bottom
--                  the school yard, where everyone arrives: the checkpoint,
--                  Shoeman, the HOME star. Above it four two-way streets
--                  running left to right, two lanes each way, with a strip
--                  of pavement between them where nothing drives; each
--                  street runs into a tunnel under the embankment at both
--                  edges. At the top a lawn and the way on.
--
-- Tiles are "road" (the streets, into their tunnels) and "walk" (the
-- pavement, the yard, the lawn); nil is the embankment either side (the
-- layout's walls make it solid). Walked: nobody about, no traffic of the
-- usual kind. The tutorial's own traffic (tutorial/traffic.lua) drives the
-- lanes this leaves on the map:
--   map.streets   { n, y0, y1 } world px, bottom (1, the slowest) to top (4, the fastest)
--   map.lanes     { y, dir, street, lane, angle, fromX, toX } every lane's middle, world px: `dir` 1
--                 drives east (angle 0), -1 west (angle pi); a car comes out of the tunnel at `fromX`
--                 and is gone into the other at `toX`, both out of sight under the roofs. `lane` 1 is
--                 the one by the centre line, 2 the one by the kerb. Bottom street first, south lane
--                 first.
--   map.tunnels   { x, y, w, h, side } the roof over each street's ends ("w" or "e"), world px: drawn
--                 over the cars (render_tutorial.lua `drawAbove`), so they come and go unseen
--   map.cx, cy    the start: the middle of the spawns, and the checkpoint (tutorial/checkpoint.lua)
--   map.exitX, exitY  the way on, in the middle of the top lawn (Tutorial.EXITS)
--   map.homeX, homeY  the HOME star, south of the start (quests' `home-tutorial-road`)
--   map.shoemanX, shoemanY  where Shoeman stands (Tutorial.SHOEMAN), between the start and the star
--   map.decor     { kind, x, y, ... } what the canvas draws and nothing else: skid (a tyre mark, `len`,
--                 `a`), crack (`len`, `a`, `seed`), stain (oil, `r`), manhole, grate, bed (a flower bed,
--                 `w`, `h`, `seed`), bench (`a` the way it faces), board (the school's sign), tree
--                 (a small one in a bed, `r`), look (a "LOOK" warning painted on the kerb, `text`)
--   map.openKinds { walk = true }: pickups go on the pavement too

local TutorialMaps = {}

-- Shoeman's Road, in tiles. The rows from the top: the lawn with the way
-- on (`top`), then each street (`street` rows, two lanes each way) with a
-- strip of pavement (`strip` rows) between it and the next, then the yard
-- (the rest). `verge` columns of embankment either side, the tunnels
-- under them.
TutorialMaps.ROAD = { top = 6, street = 4, strip = 3, streets = 4, verge = 2 }

local function buildRoad(map, rng, T)
  local R = TutorialMaps.ROAD
  local cols, rows = map.cols, map.rows
  local function X(c)
    return map.x0 + c * T
  end
  local function Y(r)
    return map.y0 + r * T
  end
  local c0, c1 = R.verge, cols - 1 - R.verge -- the walked columns
  for c = 0, cols - 1 do
    map.tiles[c] = {}
    for r = 0, rows - 1 do
      map.tiles[c][r] = (c >= c0 and c <= c1) and "walk" or nil
    end
  end
  map.streets, map.lanes, map.tunnels, map.decor = {}, {}, {}, {}
  map.openKinds = { walk = true }

  -- The streets, top (the fastest, 4) down to the bottom (1).
  local first = {}
  for i = 1, R.streets do
    local r0 = R.top + (i - 1) * (R.street + R.strip)
    first[R.streets + 1 - i] = r0
  end
  local yardRow = first[1] + R.street -- the first row of the yard
  local left, right = X(0), X(cols)
  for n = 1, R.streets do
    local r0 = first[n]
    for c = 0, cols - 1 do
      for r = r0, r0 + R.street - 1 do
        map.tiles[c][r] = "road"
      end
    end
    local y0, y1 = Y(r0), Y(r0 + R.street)
    map.streets[n] = { n = n, y0 = y0, y1 = y1 }
    -- Drive on the right: the south half runs east, the north half west.
    -- Each half lists its lane by the centre line first.
    local half = R.street / 2
    for k = 1, half do
      local y = Y(r0 + half + k - 1) + T / 2
      map.lanes[#map.lanes + 1] = { y = y, dir = 1, street = n, lane = k, angle = 0,
        fromX = left + T / 2, toX = right - T / 2 }
    end
    for k = 1, half do
      local y = Y(r0 + half - k) + T / 2
      map.lanes[#map.lanes + 1] = { y = y, dir = -1, street = n, lane = k, angle = math.pi,
        fromX = right - T / 2, toX = left + T / 2 }
    end
    map.tunnels[#map.tunnels + 1] = { x = left, y = y0, w = R.verge * T, h = y1 - y0, side = "w" }
    map.tunnels[#map.tunnels + 1] = { x = X(c1 + 1), y = y0, w = R.verge * T, h = y1 - y0, side = "e" }
  end

  -- Where everyone arrives: twelve spawns facing the streets, two rows of
  -- six, three rows into the yard; the start (and the checkpoint) between
  -- the rows, Shoeman south-east of it and the HOME star south of him.
  local sr = yardRow + 2
  for i = 0, 11 do
    map.spawns[#map.spawns + 1] = { x = (i % 6 - 2.5) * 80, y = Y(sr + math.floor(i / 6)) + T / 2,
      angle = -math.pi / 2 }
  end
  map.cx, map.cy = 0, Y(sr + 1)
  map.shoemanX, map.shoemanY = 160, map.cy + 120
  map.homeX, map.homeY = 0, map.cy + 240
  map.exitX, map.exitY = 0, Y(R.top / 2)

  -- What the canvas draws. On every street: tyre marks where somebody
  -- braked too late, cracks, oil, a manhole or two; at the kerb under each
  -- street, "LOOK" painted the way the first lane comes from.
  local d = map.decor
  local inL, inR = X(c0), X(c1 + 1)
  for _, s in ipairs(map.streets) do
    for _ = 1, 3 + s.n do
      local x, y = inL + 100 + rng:random() * (inR - inL - 200), s.y0 + rng:random(0, 3) * T + 18 + rng:random() * 28
      d[#d + 1] = { kind = "skid", x = x, y = y, len = 60 + rng:random() * 120, a = (rng:random() - 0.5) * 0.25 }
    end
    for _ = 1, 4 do
      local x, y = inL + rng:random() * (inR - inL), s.y0 + 12 + rng:random() * (s.y1 - s.y0 - 24)
      d[#d + 1] = { kind = "crack", x = x, y = y, len = 30 + rng:random() * 50, a = rng:random() * math.pi,
        seed = rng:random(1000) }
    end
    for _ = 1, 3 do
      d[#d + 1] = { kind = "stain", x = inL + rng:random() * (inR - inL), y = s.y0 + rng:random(0, 3) * T + T / 2,
        r = 8 + rng:random() * 12 }
    end
    d[#d + 1] = { kind = "manhole", x = math.floor(inL + (0.2 + rng:random() * 0.6) * (inR - inL)),
      y = s.y0 + (rng:random() < 0.5 and 1 or 3) * T }
    d[#d + 1] = { kind = "grate", x = math.floor(inL + rng:random() * (inR - inL - 40) + 20), y = s.y1 - 10 }
    d[#d + 1] = { kind = "grate", x = math.floor(inL + rng:random() * (inR - inL - 40) + 20), y = s.y0 + 10 }
    d[#d + 1] = { kind = "look", x = 0, y = s.y1 + 26, text = "LOOK LEFT" }
  end

  -- The yard: flower beds and small trees down either side, benches facing
  -- the middle, Shoeman's board by the HOME star.
  local yard0, yard1 = Y(yardRow), Y(rows)
  for _, side in ipairs({ -1, 1 }) do
    local bx = side < 0 and inL + 40 or inR - 40 - 150
    d[#d + 1] = { kind = "bed", x = bx, y = yard0 + 120, w = 150, h = yard1 - yard0 - 240, seed = rng:random(1000) }
    for k = 0, 2 do
      d[#d + 1] = { kind = "tree", x = bx + 75, y = yard0 + 210 + k * ((yard1 - yard0 - 420) / 2),
        r = 30 + rng:random() * 8 }
    end
    d[#d + 1] = { kind = "bench", x = bx + (side < 0 and 190 or -40), y = map.cy + 40, a = side < 0 and 0 or math.pi }
  end
  d[#d + 1] = { kind = "board", x = -110, y = map.homeY + 90 }

  -- The lawn at the top: beds either side of the path to the way on.
  for _, side in ipairs({ -1, 1 }) do
    local bx = side < 0 and inL + 40 or inR - 40 - 220
    d[#d + 1] = { kind = "bed", x = bx, y = Y(1), w = 220, h = (R.top - 2) * T, seed = rng:random(1000) }
    d[#d + 1] = { kind = "tree", x = bx + 110, y = Y(R.top / 2), r = 34 }
  end
end

local BUILDERS = { ["tutorial-road"] = buildRoad }

--- Does this file build maps of `kind`?
function TutorialMaps.builds(kind)
  return BUILDERS[kind] ~= nil
end

function TutorialMaps.build(map, rng, T)
  BUILDERS[map.kind](map, rng, T)
end

return TutorialMaps
