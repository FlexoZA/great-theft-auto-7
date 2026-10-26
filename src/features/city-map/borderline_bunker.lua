-- The Bunker (docs/borderline.md, "8. The Bunker"), the last of the
-- Borderline maps, built for borderline.lua: its roof at dusk above the
-- clouds, an armour-plated deck, four engine intakes with their fans
-- turning, a radar, a gantry loading a missile, and round the rim eleven
-- cannons lobbing shells at whoever is on it. The way on (the eye's hatch
-- in the middle) stays shut until every cannon is down (a lock with no
-- terminals or walls, which the borderline feature opens).

local Bunker = {}

Bunker.CANNONS = 11 -- round the rim

-- The bunker's engine intakes, a turbine fan spinning down in each (tile
-- centres; radius in tiles): it flies on them.
Bunker.INTAKES = { { 9.5, 9.5 }, { 30.5, 9.5 }, { 9.5, 30.5 }, { 30.5, 30.5 } }
Bunker.INTAKE_R = 2.2

--- The cannons, evenly round a square just inside the rim: each its mount
--- (flat) and its gun (a CAN of the army).
local function cannons(b, n)
  local lo, hi = 4.2, n - 5.2
  local per = 4 * (hi - lo)
  for i = 0, Bunker.CANNONS - 1 do
    local d = (i + 0.5) * per / Bunker.CANNONS
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
    b:place("cannon", c - 0.8, r - 0.8, 1.6, 1.6, { round = true, flat = true })
    b:post("CAN", c, r)
  end
end

--- The deck's works: the walkway painted round it and across it, the
--- zebra at the hatch, the intakes and their fans, the radar, the gantry
--- with its missile, floodlights in the corners, beacons on the rim.
local function deck(map, b, n)
  local T = b.T
  for _, k in ipairs({ 6.6, n - 6.7 }) do
    b:place("laneline", 6.6, k, n - 13.2, 0.12, { flat = true })
    b:place("laneline", k, 6.6, 0.12, n - 13.2, { flat = true })
  end
  for _, from in ipairs({ 6.6, n / 2 + 4 }) do -- the cross, stopping at the eye's hatch
    b:place("laneline", n / 2 - 0.06, from, 0.12, n / 2 - 10.6, { flat = true })
    b:place("laneline", from, n / 2 - 0.06, n / 2 - 10.6, 0.12, { flat = true })
  end
  b:place("zebra", 17.5, n - 4.6, 5, 1.2, { flat = true })
  local R = Bunker.INTAKE_R
  for _, at in ipairs(Bunker.INTAKES) do
    b:place("intake", at[1] - R, at[2] - R, 2 * R, 2 * R, { water = true, round = true })
    b:place("paint", at[1] - R, at[2] + R + 0.2, 2 * R, 0.8, { flat = true, text = "NO STEP", small = true })
    map.fans[#map.fans + 1] = { x = b:x(at[1]), y = b:y(at[2]), r = (R - 0.35) * T, phase = #map.fans * 0.7 }
  end
  b:place("mast", 30.4, 19.4, 1.2, 1.2, { round = true })
  map.radars[1] = { x = b:x(31), y = b:y(20), r = 70 }
  map.bridgecranes[1] = { x0 = b:x(3), x1 = b:x(n - 3), y0 = b:y(6), y1 = b:y(n - 7), period = 36, phase = 0.5,
    load = "missile" }
  for _, at in ipairs({ { 5.8, 5.8 }, { n - 6.5, 5.8 }, { 5.8, n - 6.5 }, { n - 7.2, n - 7.2 } }) do
    b:place("flood", at[1], at[2], 0.7, 0.7, { round = true })
    map.lights[#map.lights + 1] = { x = b:x(at[1] + 0.35), y = b:y(at[2] + 0.35), r = 460,
      color = { 1, 0.92, 0.75 }, a = 0.75 }
  end
  for _, at in ipairs({ { 3, 3 }, { n - 3, 3 }, { 3, n - 3 }, { n - 3, n - 3 }, { 17.5, n - 3 }, { 22.5, n - 3 } }) do
    map.beacons[#map.beacons + 1] = { x = b:x(at[1]), y = b:y(at[2]), color = "red" }
  end
end

--- Build the Bunker on `map` with blockout `b` (borderline.lua's).
function Bunker.build(map, rng, b)
  map.outside = "sky"
  map.beacons, map.fans, map.radars, map.bridgecranes = {}, {}, {}, {}
  local n = map.cols
  b:open(3, 3, n - 4, n - 4)
  b:open(18, n - 3, 21, n - 1) -- the hatch up from inside
  b:ground("roof", 0, 0, n - 1, n - 1)
  b:place("hatch", 18, n - 3, 4, 3, { flat = true })
  b:place("eyehatch", n / 2 - 4, n / 2 - 4, 8, 8, { flat = true, round = true })
  cannons(b, n)
  b:lock("rim", "THE EYE'S HATCH", true) -- no terminals, no walls: every cannon down opens it
  deck(map, b, n)
  local keep = { { n / 2 - 5, n / 2 - 5, n / 2 + 4, n / 2 + 4 }, { 16, n - 8, 23, n - 1 } }
  b:keepArmy(keep) -- no vent on a cannon
  b:scatter(rng, "vent", 12, 72, 7, n - 8, keep)
  b:zone("The Bunker", 0, n - 1)
  b:ends(17, n - 9, n / 2 - 1, n / 2 - 1)
  b:commit()
end

return Bunker
