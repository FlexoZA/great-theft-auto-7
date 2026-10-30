-- Liar's Landing (docs/borderline.md, "2. Liar's Landing"), the second of
-- the Borderline maps, built for borderline.lua: a frozen container port,
-- stacks of containers in a grid with lanes clear between them, the dry
-- dock down the west side, the quay along the north with the gantries and
-- the freighter, the ferry lift shuttered until the four control terminals
-- round the yard are hacked and then held while Yappy hacks it, Hyperbole's
-- army throughout, and the frozen sea all round.

local Landing = {}

-- The dry dock on the yard's west side (tiles: c, r, w, h): a deep basin
-- with a frozen hull in it, a tower crane at either end working over it.
Landing.DRY_DOCK = { 3, 14, 7, 30 }
-- The quay's gantry cranes (tile column of each one's middle): they stand
-- over the quay and reach out over the freighter moored along it.
Landing.GANTRIES = { 11.5, 43.5 }
Landing.LIFT_HOLD = 60 -- seconds the ferry lift has to be held for Yappy's hack
-- Where the lanes the stacks leave clear cross (down columns 10-11 and
-- every 8 after, across rows 18-19 and every 9 after): a gun hauler posted
-- at each of these (tiles).
Landing.GUNS = { { 19, 46 }, { 35, 46 }, { 11, 37 }, { 43, 37 }, { 27, 28 }, { 51, 28 }, { 19, 19 },
  { 35, 19 }, { 11, 28 }, { 27, 37 } }
-- The ferry's control terminals, one out in each corner of the yard, so the
-- lift's shutters only come down once you have been all round (tiles):
-- `terminal` and the hauler `dock` guarding it, `guns` gun haulers posted
-- by it, `junk` a pack of junk haulers about it ({ c, r, count }).
Landing.POSTS = {
  { key = "sw", terminal = { 4, 58 }, dock = { 9, 56.5 }, guns = { { 7, 59.5 }, { 12.5, 58 } }, junk = { 15, 59, 3 } },
  { key = "east", terminal = { 52.5, 31 }, dock = { 52.5, 36 }, guns = { { 52, 27 }, { 51.5, 40.5 } },
    junk = { 52, 44, 2 } },
  { key = "nw", terminal = { 3, 10.2 }, dock = { 7.5, 9 }, guns = { { 5.5, 11.5 } }, junk = { 3, 12.5, 2 } },
  { key = "ne", terminal = { 52.5, 10.5 }, dock = { 47.5, 9.5 }, guns = { { 50.5, 13 } }, junk = { 53, 15, 2 } },
}

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
  local D = Landing.DRY_DOCK
  local mid, side = D[1] + D[3] / 2, D[3] * 0.55 / 2 + 0.1
  for i, at in ipairs({ { mid + side, D[2] + 7 }, { mid - side, D[2] + 15 }, { mid + side, D[2] + 22 } }) do
    map.welders[#map.welders + 1] = { x = b:x(at[1]), y = b:y(at[2]), phase = i * 1.7 }
  end
end

--- Hyperbole's army on Liar's Landing (tiles). Gun haulers hold the yard:
--- posted where the lanes cross (`GUNS`), watching the way in, and
--- round each of the ferry's terminals; three squads walk loops along the
--- lanes and a pair of stalkers hunts the stacks; two guard the lift;
--- rocket haulers under the gantries and out in the yard, drones with the
--- squads, junk haulers scavenging the edges. Then the waves that come at
--- the lift while it is held for Yappy's hack, off both ends of the quay
--- and up the lanes.
local function landingArmy(b)
  for _, at in ipairs(Landing.GUNS) do
    b:post("GUN", at[1], at[2])
  end
  for _, post in ipairs(Landing.POSTS) do -- and round each of the ferry's terminals
    for _, g in ipairs(post.guns) do
      b:post("GUN", g[1], g[2])
    end
    b:pack("JNK", post.junk[1], post.junk[2], post.junk[3])
  end
  b:post("GUN", 23, 5.5)
  b:post("GUN", 33, 5.5)
  b:squad({ "GUN", "GUN", "GUN" }, { { 11, 19 }, { 43, 19 }, { 43, 37 }, { 11, 37 } })
  b:squad({ "GUN", "GUN" }, { { 19, 28 }, { 35, 28 }, { 35, 46 }, { 19, 46 } })
  b:squad({ "GUN", "GUN", "GUN" }, { { 11, 37 }, { 27, 37 }, { 27, 46 }, { 11, 46 } })
  b:squad({ "STK", "STK" }, { { 27, 28 }, { 51, 28 }, { 51, 46 }, { 27, 46 } }) -- a pair of stalkers hunting the stacks
  b:pack("JNK", 5, 48, 3)
  b:pack("JNK", 50, 12, 3)
  b:post("RPG", 9, 7) -- the first rocket haulers, under the gantries
  b:post("RPG", 46, 7)
  b:post("RPG", 27, 19) -- and two more out in the yard
  b:post("RPG", 43, 46)
  b:post("FIX", 12, 21) -- a pair of medic drones with the first squad
  b:post("FIX", 14, 21)
  b:post("SHD", 36, 21) -- a shield drone with the second post's squad
  b:pack("JNK", 47, 58, 3)
  -- The ferry lift stays shut until it has been held for Yappy's hack, the
  -- army coming at it off both ends of the quay and up the lanes.
  b:hold(25, 2, 6, 3, Landing.LIFT_HOLD)
  b:wave(0, { "GUN", "GUN", "FIX" }, 4, 4)
  b:wave(0.2, { "JNK", "JNK", "JNK", "JNK", "GUN" }, 27, 19)
  b:wave(0.4, { "GUN", "GUN", "GUN" }, 52, 4)
  b:wave(0.6, { "RPG", "GUN", "GUN" }, 43, 19)
  b:wave(0.8, { "STK", "GUN", "GUN", "FIX" }, 11, 19)
  b:wave(0.9, { "RPG", "GUN", "GUN", "SHD" }, 4, 4)
end

--- Build Liar's Landing on `map` with blockout `b` (borderline.lua's),
--- `crane(map, b, p, corner, at)` putting up a tower crane.
function Landing.build(map, rng, b, crane)
  local T = b.T
  map.outside = "harbour"
  map.cranes, map.beacons, map.gantries, map.tracks, map.welders = {}, {}, {}, {}, {}
  b:open(2, 2, map.cols - 3, map.rows - 4)
  b:open(25, map.rows - 3, 30, map.rows - 1) -- out of the tunnel
  b:ground("port", 0, 0, map.cols - 1, map.rows - 1)
  b:ground("quay", 2, 2, map.cols - 3, 6)
  -- The quay walls all round, the sea past them: the north where the ships moor, then the west, the east,
  -- and the south either side of the way in from the tunnel.
  local bottom = map.rows - 3
  b:place("quayedge", 2, 2, map.cols - 4, 0.18, { flat = true })
  b:place("quayedge", 2, 2, 0.18, bottom - 2, { flat = true, side = "w" })
  b:place("quayedge", map.cols - 2.18, 2, 0.18, bottom - 2, { flat = true, side = "e" })
  b:place("quayedge", 2, bottom - 0.18, 23, 0.18, { flat = true, side = "s" })
  b:place("quayedge", 31, bottom - 0.18, map.cols - 33, 0.18, { flat = true, side = "s" })
  for _, r in ipairs({ 2.3, 5.6 }) do -- the gantries' rails, the length of the quay
    b:place("craneRail", 2, r, map.cols - 4, 0.3, { flat = true })
  end
  b:place("tunnel", 25, map.rows - 2.5, 6, 2.5, { flat = true })
  b:place("ship", 4, -2.2, map.cols - 8, 3.9, { flat = true }) -- the freighter moored along the quay
  -- The dry dock, and its two cranes.
  local D = Landing.DRY_DOCK
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
  for _, c in ipairs(Landing.GANTRIES) do
    for _, f in ipairs({ { -1.8, 2.2 }, { 1.3, 2.2 }, { -1.8, 5.5 }, { 1.3, 5.5 } }) do
      b:place("foot", c + f[1], f[2], 0.5, 0.5)
    end
    map.gantries[#map.gantries + 1] = { x = b:x(c), y = b:y(4), span = 3.6 * T, depth = 3.8 * T, reach = 4.5 * T,
      period = 11 + #map.gantries * 4, phase = #map.gantries * 1.9 }
    map.beacons[#map.beacons + 1] = { x = b:x(c - 1.55), y = b:y(2.45), color = "amber" }
    map.beacons[#map.beacons + 1] = { x = b:x(c + 1.55), y = b:y(2.45), color = "amber" }
  end
  for c = 3, map.cols - 4, 4 do
    if (c < 24 or c > 31) and math.abs(c + 0.5 - Landing.GANTRIES[1]) > 2.5
      and math.abs(c + 0.5 - Landing.GANTRIES[2]) > 2.5 then
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
  -- The lift shut behind shutters on its three landward sides until the
  -- ferry's control terminals round the yard are all hacked, each guarded
  -- by the hauler dock it runs.
  local ferry = b:lock("ferry", "THE FERRY LIFT", true)
  b:lockWall(ferry, b:x(24.3), b:y(2), 0.35 * T, 3.85 * T)
  b:lockWall(ferry, b:x(31.35), b:y(2), 0.35 * T, 3.85 * T)
  b:lockWall(ferry, b:x(24.3), b:y(5.5), 7.4 * T, 0.35 * T)
  local keep = { { 22, 54, 33, 63 }, { 24, 2, 32, 7 } }
  for _, at in ipairs(Landing.GUNS) do -- no crate dropped on a post
    keep[#keep + 1] = { at[1] - 1, at[2] - 1, at[1] + 1, at[2] + 1 }
  end
  for _, post in ipairs(Landing.POSTS) do
    local t, d = post.terminal, post.dock
    b:dockPost(ferry, post.key, t[1], t[2], d[1], d[2])
    keep[#keep + 1] = { math.floor(t[1]) - 1, math.floor(t[2]) - 1, math.floor(t[1]) + 1, math.floor(t[2]) + 1 }
    keep[#keep + 1] = { math.floor(d[1]) - 1, math.floor(d[2]) - 1, math.floor(d[1]) + 1, math.floor(d[2]) + 1 }
  end
  b:scatter(rng, "crate", 14, 48, 8, 56, keep)
  b:scatter(rng, "drum", 12, 40, 8, 56, keep)
  b:scatter(rng, "cone", 16, 22, 7, 56, keep, { flat = true })
  landingArmy(b)
  b:zone("The Yard", 8, map.rows - 1)
  b:zone("The Quay", 0, 7)
  b:ends(25, 56, 27, 3)
  portLitter(map, b)
  b:commit()
end

return Landing
