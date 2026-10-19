-- The working parts of Hyperbole's grounds (docs/borderline.md, "Maps"),
-- drawn every frame on every screen, moving: the tower cranes swinging
-- their jibs back and forth over the excavations, a trolley running in and
-- out along each jib with a load swaying under it, a red light blinking
-- at its tip; the quay's gantry cranes, a trolley running out along each
-- boom over the freighter and back with a container on its spreader; and
-- the mine shafts' headframes, their wheels turning and a cage running up
-- and down; ore riding the conveyors; and the emergency beacons turning,
-- amber and red, their beams sweeping the ground. From the map (city-map's
-- borderline.lua: `map.cranes`, `map.gantries`, `map.headframes`,
-- `map.conveyors`, `map.beacons`); over Prosperity, the factories'
-- chimneys smoking (`map.stacks`) and pipe bridges across the avenue
-- (`map.overpipes`); and in the Refinery, the molten river flowing
-- (`map.flows`), steam venting from the floor (`map.steam`) and the bridge
-- cranes running the hall with their ladles (`map.bridgecranes`); and on
-- the Assembly Line, hauler parts riding the belts (`map.conveyors` with
-- `cargo` "parts"), the arms swinging in to weld with sparks flying
-- (`map.arms`), the presses stamping (`map.presses`) and a finished hauler
-- carried up the line by the bridge crane (`load` "hauler"). Scenery only: nothing here is on the host
-- or touches anyone, and each screen keeps its own clock.

local Hauler = require("src.features.borderline.hauler_look")

local Works = {}

local C = Hauler.C
local BEACON = { amber = { 1.00, 0.62, 0.10 }, red = { 1.00, 0.15, 0.10 } }
local LIFT = 26 -- px the cranes' parts are drawn up off the ground (their shadows lie there)

local clock = 0

function Works.update(dt)
  clock = clock + dt
end

local function ease(t)
  return 0.5 - 0.5 * math.cos(t)
end

--- Where crane `c`'s jib points, and how far out its trolley is, now.
local function pose(c)
  local a = c.from + c.sweep * ease(2 * math.pi * clock / c.period + c.phase)
  local out = c.jib * (0.35 + 0.5 * ease(2 * math.pi * clock / (c.period * 0.63) + c.phase * 1.7))
  return a, out
end

--- The beam a beacon `b` throws, turning (0..1 how bright it faces you).
local function flash(b)
  local turn = (clock * 1.4 + (b.x * 0.37 + b.y * 0.11) % 1) % 1
  return math.max(0, math.cos(turn * 2 * math.pi)) ^ 6, turn * 2 * math.pi
end

--- Where gantry `g`'s trolley is along its boom (px north of the portal's
--- middle, negative over the quay), and whether it carries a container.
local function gantryPose(g)
  local cycle = 2 * math.pi * clock / g.period + g.phase
  local out = -g.depth * 0.3 + (g.reach + g.depth * 0.8) * ease(cycle)
  return out, math.sin(cycle) < 0 -- coming back in from the ship: loaded
end

local ORE_GAP = 70 -- px between lumps of ore on a belt
local ORE_SPEED = 60 -- px/s the belts run

--- The ore riding the conveyors (on the belt, under everyone).
local function drawOre(map)
  for _, c in ipairs(map.conveyors or {}) do
    local along = c.dir == "e" or c.dir == "w"
    local len = along and c.w or c.h
    local back = c.dir == "w" or c.dir == "n" -- running towards its start
    local shift = (clock * ORE_SPEED) % ORE_GAP
    for a = 0, len - 1, ORE_GAP do
      local d = back and (a - shift) % len or (a + shift) % len
      local x = along and c.x + d or c.x + c.w / 2
      local y = along and c.y + c.h / 2 or c.y + d
      local r = (along and c.h or c.w) * 0.32
      if c.cargo == "parts" then -- a torso, then a pair of legs, then an arm
        local kind = math.floor(a / ORE_GAP) % 3
        love.graphics.setColor(C.ink)
        love.graphics.rectangle("fill", x - r - 2, y - r * 0.8 - 2, 2 * r + 4, 1.6 * r + 4, 4)
        love.graphics.setColor(kind == 0 and C.yellow or C.gunmetalLight)
        love.graphics.rectangle("fill", x - r, y - r * 0.8, 2 * r, 1.6 * r, 3)
        if kind == 0 then
          love.graphics.setColor(C.eye) -- its eye, not lit yet
          love.graphics.circle("fill", x + r * 0.4, y, r * 0.3, 10)
        end
      else
        love.graphics.setColor(C.ink)
        love.graphics.circle("fill", x, y, r + 1.5, 6)
        love.graphics.setColor(C.plasma)
        love.graphics.circle("fill", x, y, r, 6)
      end
    end
  end
end

local FLOW_SPEED = 45 -- px/s the river runs

--- Bright streaks riding the molten river the way it flows.
local function drawFlow(map)
  love.graphics.setBlendMode("add")
  for _, f in ipairs(map.flows or {}) do
    local along = f.w >= f.h
    local len, wide = along and f.w or f.h, along and f.h or f.w
    local sign = (f.dir == "w" or f.dir == "n") and -1 or 1
    for k = 0, math.floor(len / 50) do
      local lane = ((k * 37) % 5 + 0.5) / 5 * wide
      local d = (k * 50 + sign * clock * FLOW_SPEED * (0.8 + (k % 3) * 0.2)) % len
      local x, y = along and f.x + d or f.x + lane, along and f.y + lane or f.y + d
      love.graphics.setColor(C.plasmaHot[1], C.plasmaHot[2], C.plasmaHot[3], 0.35)
      love.graphics.ellipse("fill", x, y, along and 26 or 4, along and 4 or 26, 10)
    end
  end
  love.graphics.setBlendMode("alpha")
end

--- On the ground: the river flowing, the ore on the belts, then each crane's shadow, the jib's and its load's.
function Works.drawBelowCars(map)
  drawFlow(map)
  drawOre(map)
  love.graphics.setColor(0, 0, 0, 0.22)
  for _, g in ipairs(map.gantries or {}) do
    local x, y = g.x + LIFT, g.y + LIFT
    love.graphics.rectangle("fill", x - g.span / 2 - 10, y - g.depth / 2, 20, g.depth)
    love.graphics.rectangle("fill", x + g.span / 2 - 10, y - g.depth / 2, 20, g.depth)
    love.graphics.rectangle("fill", x - 18, y - g.depth / 2 - g.reach, 36, g.reach + g.depth)
  end
  for _, c in ipairs(map.cranes or {}) do
    local a, out = pose(c)
    local ca, sa = math.cos(a), math.sin(a)
    local sx, sy = c.x + LIFT, c.y + LIFT -- the light comes from up and to the left
    love.graphics.setLineWidth(14)
    love.graphics.line(sx - ca * c.jib * 0.3, sy - sa * c.jib * 0.3, sx + ca * c.jib, sy + sa * c.jib)
    love.graphics.setLineWidth(1)
    love.graphics.rectangle("fill", sx + ca * out - 22, sy + sa * out - 14, 44, 28)
  end
  love.graphics.setColor(1, 1, 1)
end

--- A lattice of the jib from (x0, y0) to (x1, y1), `w` px wide.
local function truss(x0, y0, x1, y1, w)
  local len = math.sqrt((x1 - x0) ^ 2 + (y1 - y0) ^ 2)
  love.graphics.push()
  love.graphics.translate(x0, y0)
  love.graphics.rotate(math.atan2(y1 - y0, x1 - x0))
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", -2, -w / 2 - 2, len + 4, w + 4)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", 0, -w / 2, len, w)
  love.graphics.setColor(C.ink)
  love.graphics.setLineWidth(1.5)
  for k = 0, len - w, w do -- the zig-zag bracing
    love.graphics.line(k, -w / 2, k + w, w / 2)
  end
  love.graphics.setLineWidth(1)
  love.graphics.pop()
end

local function drawCrane(c)
  local a, out = pose(c)
  local ca, sa = math.cos(a), math.sin(a)
  local x, y = c.x, c.y - LIFT
  -- The load first, under the jib: a bundle of girders on its cable, swaying.
  local sway = math.sin(clock * 1.7 + c.phase) * 6
  local lx, ly = x + ca * out - sa * sway, y + sa * out + ca * sway + LIFT * 0.6
  love.graphics.setColor(C.ink)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(x + ca * out, y + sa * out, lx, ly)
  love.graphics.setLineWidth(1)
  love.graphics.push()
  love.graphics.translate(lx, ly)
  love.graphics.rotate(a + math.pi / 2)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", -22, -12, 44, 24)
  love.graphics.setColor(C.rust)
  for k = -1, 1 do
    love.graphics.rectangle("fill", -20, k * 7 - 3, 40, 6)
  end
  love.graphics.pop()
  -- The counter-jib behind, its weight, the jib out front, the trolley on it.
  truss(x, y, x - ca * c.jib * 0.3, y - sa * c.jib * 0.3, 14)
  love.graphics.setColor(C.ink)
  love.graphics.push()
  love.graphics.translate(x - ca * c.jib * 0.28, y - sa * c.jib * 0.28)
  love.graphics.rotate(a)
  love.graphics.rectangle("fill", -14, -14, 24, 28)
  love.graphics.setColor(C.gunmetalLight)
  love.graphics.rectangle("fill", -12, -12, 20, 24)
  love.graphics.pop()
  truss(x, y, x + ca * c.jib, y + sa * c.jib, 14)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x + ca * out - 9, y + sa * out - 9, 18, 18)
  love.graphics.setColor(C.gunmetal)
  love.graphics.rectangle("fill", x + ca * out - 7, y + sa * out - 7, 14, 14)
  -- The cab at the top of the mast, and the light at the jib's tip.
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 14, y - 14, 28, 28)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", x - 12, y - 12, 24, 24)
  love.graphics.setColor(0.26, 0.36, 0.48)
  love.graphics.rectangle("fill", x - 6, y - 10, 14, 10)
  local on = math.floor(clock * 1.5 + c.phase) % 2 == 0
  love.graphics.setColor(on and 1 or 0.35, 0.1, 0.08)
  love.graphics.circle("fill", x + ca * c.jib, y + sa * c.jib, 5, 10)
end

local function drawGantry(g)
  local x, y = g.x, g.y - LIFT
  local top = y - g.depth / 2
  local out, loaded = gantryPose(g)
  -- The portal: a leg frame each side, a beam across front and back.
  for _, side in ipairs({ -1, 1 }) do
    truss(x + side * g.span / 2, top, x + side * g.span / 2, top + g.depth, 16)
  end
  truss(x - g.span / 2 - 8, top, x + g.span / 2 + 8, top, 14)
  truss(x - g.span / 2 - 8, top + g.depth, x + g.span / 2 + 8, top + g.depth, 14)
  -- The load under the trolley: a container on the spreader when coming in.
  local ty = top + g.depth / 2 - out
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 30, ty - 12, 60, 24)
  if loaded then
    local tint = (math.floor(clock / g.period + g.phase) % 3) + 1
    local fill = ({ { 0.80, 0.26, 0.20 }, { 0.22, 0.44, 0.72 }, { 0.28, 0.58, 0.34 } })[tint]
    love.graphics.setColor(fill)
    love.graphics.rectangle("fill", x - 28, ty - 10, 56, 20)
  else
    love.graphics.setColor(C.yellow)
    love.graphics.rectangle("fill", x - 28, ty - 3, 56, 6) -- the empty spreader
  end
  -- The boom out over the water, the machinery house on the back of it.
  truss(x, top + g.depth + 20, x, top - g.reach, 18)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 22, top + g.depth - 6, 44, 34)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", x - 20, top + g.depth - 4, 40, 30)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 12, ty - 10, 24, 20) -- the trolley
  love.graphics.setColor(C.gunmetalLight)
  love.graphics.rectangle("fill", x - 10, ty - 8, 20, 16)
  local on = math.floor(clock * 1.5 + g.phase) % 2 == 0
  love.graphics.setColor(on and 1 or 0.35, 0.1, 0.08)
  love.graphics.circle("fill", x, top - g.reach, 5, 10)
end

--- A headframe over a shaft: an A-frame of girders, two wheels on top
--- turning as the cage below runs up and down, the cables off them.
local function drawHeadframe(h)
  local x, y = h.x, h.y - LIFT * 1.4
  local spin = clock * 2.2 + h.phase
  love.graphics.setColor(0, 0, 0, 0.22)
  love.graphics.rectangle("fill", h.x - 50 + LIFT, h.y - 10 + LIFT, 100, 20)
  -- The legs, splayed out to the shaft's corners, and the beam across the top.
  love.graphics.setColor(C.ink)
  love.graphics.setLineWidth(9)
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    love.graphics.line(h.x + c[1] * 70, h.y + c[2] * 70, x + c[1] * 34, y)
  end
  love.graphics.setColor(C.rust)
  love.graphics.setLineWidth(5)
  for _, c in ipairs({ { -1, -1 }, { 1, -1 }, { -1, 1 }, { 1, 1 } }) do
    love.graphics.line(h.x + c[1] * 70, h.y + c[2] * 70, x + c[1] * 34, y)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", x - 44, y - 9, 88, 18)
  love.graphics.setColor(C.rust)
  love.graphics.rectangle("fill", x - 42, y - 7, 84, 14)
  -- The two wheels, spokes turning (one each way).
  for k, side in ipairs({ -1, 1 }) do
    local wx = x + side * 22
    love.graphics.setColor(C.ink)
    love.graphics.circle("fill", wx, y, 16, 18)
    love.graphics.setColor(C.gunmetalLight)
    love.graphics.circle("fill", wx, y, 13, 18)
    love.graphics.setColor(C.ink)
    love.graphics.setLineWidth(2)
    local a = (k == 1 and spin or -spin)
    for sp = 0, 2 do
      local t = a + sp * math.pi / 3
      love.graphics.line(wx - math.cos(t) * 12, y - math.sin(t) * 12, wx + math.cos(t) * 12, y + math.sin(t) * 12)
    end
    love.graphics.setLineWidth(1)
  end
  -- The cage: a yellow box under the frame, coming up out of the shaft and going back down.
  local up = ease(spin * 0.25)
  local cy = h.y + 10 - up * 22
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", h.x - 16, cy - 12, 32, 24)
  love.graphics.setColor(C.yellow[1] * (0.4 + 0.6 * up), C.yellow[2] * (0.4 + 0.6 * up), C.yellow[3] * (0.4 + 0.6 * up))
  love.graphics.rectangle("fill", h.x - 14, cy - 10, 28, 20)
end

local SMOKE_PUFFS = 7
local SMOKE_LIFE = 5 -- seconds a puff lasts
local WIND = { 34, -18 } -- px/s the smoke drifts

--- A chimney's smoke: puffs rising out of it, growing, drifting downwind, fading.
local function drawSmoke(st)
  for i = 0, SMOKE_PUFFS - 1 do
    local age = ((clock + st.phase) / SMOKE_LIFE + i / SMOKE_PUFFS) % 1
    local t = age * SMOKE_LIFE
    local x, y = st.x + WIND[1] * t, st.y + WIND[2] * t - LIFT * 2 * age
    local r = 14 + 46 * age
    love.graphics.setColor(0.28, 0.28, 0.30, 0.42 * (1 - age))
    love.graphics.circle("fill", x, y, r, 16)
    love.graphics.setColor(0.45, 0.45, 0.48, 0.28 * (1 - age))
    love.graphics.circle("fill", x - r * 0.25, y - r * 0.25, r * 0.6, 14)
  end
end

--- A pipe bridge over a street: three pipes on a trestle, a hazard band
--- where it crosses.
local function drawOverpipe(p)
  local y = p.y - LIFT
  love.graphics.setColor(0, 0, 0, 0.2)
  love.graphics.rectangle("fill", p.x0 + LIFT, p.y + LIFT - 18, p.x1 - p.x0, 36)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", p.x0, y - 22, p.x1 - p.x0, 44)
  for k, col in ipairs({ C.gunmetalLight, C.rust, C.gunmetalLight }) do
    love.graphics.setColor(col)
    love.graphics.rectangle("fill", p.x0, y - 20 + (k - 1) * 14, p.x1 - p.x0, 11)
  end
  love.graphics.setColor(C.yellow)
  local mid = (p.x0 + p.x1) / 2
  for k = -2, 1 do
    love.graphics.rectangle("fill", mid + k * 24, y - 22, 12, 4)
  end
end

local STEAM_EVERY = 6 -- seconds between a vent's bursts...
local STEAM_FOR = 2.2 -- ...each lasting this long

--- A vent's burst of steam: white puffs rising off it and spreading.
local function drawSteam(v)
  local t = (clock + v.phase) % STEAM_EVERY
  if t > STEAM_FOR then
    return
  end
  for i = 0, 5 do
    local age = (t / STEAM_FOR + i / 6) % 1
    local r = 10 + 40 * age
    love.graphics.setColor(0.92, 0.92, 0.96, 0.4 * (1 - age) * math.min(1, (STEAM_FOR - t) * 2))
    love.graphics.circle("fill", v.x + math.sin(i * 2.1 + clock) * 8 * age, v.y - LIFT * 2 * age, r, 14)
  end
end

--- A bridge crane: two girders across the hall, end carriages on the
--- walls, the trolley running along it with a ladle of molten Bragium.
local function drawBridgeCrane(c)
  local y = c.y0 + (c.y1 - c.y0) * ease(2 * math.pi * clock / c.period + c.phase) - LIFT
  local tx = c.x0 + 120 + (c.x1 - c.x0 - 240) * ease(2 * math.pi * clock / (c.period * 0.37) + c.phase)
  love.graphics.setColor(0, 0, 0, 0.2)
  love.graphics.rectangle("fill", c.x0 + LIFT, y - 20 + LIFT * 2, c.x1 - c.x0, 40)
  -- Its load first, under the trolley: a ladle glowing, or a finished hauler.
  if c.load == "hauler" then
    Hauler.draw({ dx = tx, dy = y + 10, facing = math.pi / 2, code = "GUN", stride = 0 }, clock)
  else
    love.graphics.setColor(C.ink)
    love.graphics.circle("fill", tx, y + 6, 22, 18)
    love.graphics.setColor(C.gunmetal)
    love.graphics.circle("fill", tx, y + 6, 19, 18)
    love.graphics.setColor(C.plasmaHot)
    love.graphics.circle("fill", tx, y + 6, 13 + math.sin(clock * 6) * 1.5, 16)
  end
  truss(c.x0, y - 14, c.x1, y - 14, 14)
  truss(c.x0, y + 14, c.x1, y + 14, 14)
  for _, x in ipairs({ c.x0 + 6, c.x1 - 26 }) do -- the end carriages on their rails
    love.graphics.setColor(C.ink)
    love.graphics.rectangle("fill", x - 2, y - 32, 24, 64)
    love.graphics.setColor(C.yellow)
    love.graphics.rectangle("fill", x, y - 30, 20, 60)
  end
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", tx - 22, y - 22, 44, 44)
  love.graphics.setColor(C.gunmetalLight)
  love.graphics.rectangle("fill", tx - 19, y - 19, 38, 38)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", tx - 19, y - 19, 38, 6)
end

--- Where arm `a`'s torch is now, and whether it is down on the belt welding.
local function armPose(a)
  local t = clock * 0.9 + a.phase
  local reach = ease(t * 2) -- in to the belt and back out
  local ang = (a.side < 0 and math.pi / 2 or -math.pi / 2) + math.sin(t) * 0.6
  local len = 40 + 40 * reach
  return a.x + math.cos(ang) * len, a.y + math.sin(ang) * len - LIFT * 0.5, reach > 0.85
end

--- An assembly arm: swinging in over the belt, welding there in a shower of sparks.
local function drawArm(a)
  local tx, ty, welding = armPose(a)
  local ex, ey = (a.x + tx) / 2, (a.y + ty) / 2 - 14 -- the elbow, up
  for pass = 1, 2 do
    love.graphics.setColor(pass == 1 and C.ink or C.yellow)
    love.graphics.setLineWidth(pass == 1 and 11 or 7)
    love.graphics.line(a.x, a.y, ex, ey, tx, ty)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(C.ink)
  love.graphics.circle("fill", ex, ey, 6, 10)
  love.graphics.setColor(C.gunmetal)
  love.graphics.circle("fill", tx, ty, 5, 10)
  if welding then
    love.graphics.setColor(C.arcHot)
    love.graphics.circle("fill", tx, ty, 4, 8)
    love.graphics.setColor(C.flame)
    for k = 0, 5 do -- sparks flying off the weld
      local sa = clock * 37 + k * 1.9 + a.phase
      local sr = 8 + ((clock * 5 + k * 0.3) % 1) * 22
      love.graphics.circle("fill", tx + math.cos(sa) * sr, ty + math.sin(sa) * sr, 1.6, 4)
    end
  end
end

--- A press: its head coming down and going back up.
local function drawPress(p)
  local k = math.max(0, math.sin(clock * 2.4 + p.phase)) ^ 3 -- 1 when slammed down
  local up = (1 - k) * LIFT
  love.graphics.setColor(0, 0, 0, 0.25 * (1 - k))
  love.graphics.rectangle("fill", p.x + 10, p.y + 10, p.w - 20, p.h - 20)
  love.graphics.setColor(C.ink)
  love.graphics.rectangle("fill", p.x + 6, p.y + 6 - up, p.w - 12, p.h - 12)
  love.graphics.setColor(C.gunmetalLight)
  love.graphics.rectangle("fill", p.x + 9, p.y + 9 - up, p.w - 18, p.h - 18)
  love.graphics.setColor(C.yellow)
  love.graphics.rectangle("fill", p.x + 9, p.y + 9 - up, p.w - 18, 8)
end

local function drawBeacon(b)
  local col = BEACON[b.color] or BEACON.amber
  local f, turn = flash(b)
  love.graphics.setColor(C.ink)
  love.graphics.circle("fill", b.x, b.y, 10, 12)
  love.graphics.setColor(col[1] * (0.45 + 0.55 * f), col[2] * (0.45 + 0.55 * f), col[3] * (0.45 + 0.55 * f))
  love.graphics.circle("fill", b.x, b.y, 7, 12)
  love.graphics.setBlendMode("add") -- the beam sweeping round
  love.graphics.setColor(col[1], col[2], col[3], 0.18 + 0.25 * f)
  love.graphics.arc("fill", b.x, b.y, 110, turn - 0.3, turn + 0.3, 10)
  love.graphics.setBlendMode("alpha")
end

--- Overhead: the beacons, then the cranes over everything.
function Works.drawAboveCars(map)
  for _, b in ipairs(map.beacons or {}) do
    drawBeacon(b)
  end
  for _, c in ipairs(map.cranes or {}) do
    drawCrane(c)
  end
  for _, g in ipairs(map.gantries or {}) do
    drawGantry(g)
  end
  for _, h in ipairs(map.headframes or {}) do
    drawHeadframe(h)
  end
  for _, p in ipairs(map.presses or {}) do
    drawPress(p)
  end
  for _, a in ipairs(map.arms or {}) do
    drawArm(a)
  end
  for _, v in ipairs(map.steam or {}) do
    drawSteam(v)
  end
  for _, p in ipairs(map.overpipes or {}) do
    drawOverpipe(p)
  end
  for _, c in ipairs(map.bridgecranes or {}) do
    drawBridgeCrane(c)
  end
  for _, st in ipairs(map.stacks or {}) do
    drawSmoke(st)
  end
  love.graphics.setColor(1, 1, 1)
end

--- At dusk (the night feature): the beacons and the cranes' tip lights glow.
function Works.drawNightLights(map, glow)
  for _, b in ipairs(map.beacons or {}) do
    local f = flash(b)
    glow(b.x, b.y, 90 + 90 * f, BEACON[b.color] or BEACON.amber, 0.35 + 0.6 * f)
  end
  for _, c in ipairs(map.cranes or {}) do
    local a = pose(c)
    if math.floor(clock * 1.5 + c.phase) % 2 == 0 then
      glow(c.x + math.cos(a) * c.jib, c.y - LIFT + math.sin(a) * c.jib, 60, BEACON.red, 0.8)
    end
    glow(c.x, c.y - LIFT, 80, { 1, 0.9, 0.7 }, 0.4) -- the cab's lamp
  end
  for _, h in ipairs(map.headframes or {}) do
    glow(h.x, h.y - LIFT * 1.4, 110, { 1, 0.85, 0.6 }, 0.5) -- the lamps on the headframe
  end
  for _, c in ipairs(map.bridgecranes or {}) do -- the ladle's glow, moving with it
    if c.load ~= "hauler" then
      local y = c.y0 + (c.y1 - c.y0) * ease(2 * math.pi * clock / c.period + c.phase) - LIFT
      local tx = c.x0 + 120 + (c.x1 - c.x0 - 240) * ease(2 * math.pi * clock / (c.period * 0.37) + c.phase)
      glow(tx, y + 6, 220, C.plasma, 0.8)
    end
  end
  for _, a in ipairs(map.arms or {}) do -- a weld lights up round it
    local tx, ty, welding = armPose(a)
    if welding then
      glow(tx, ty, 90, C.arcHot, 0.7 + 0.3 * math.sin(clock * 40 + a.phase))
    end
  end
  for _, g in ipairs(map.gantries or {}) do
    local top = g.y - LIFT - g.depth / 2
    local out = gantryPose(g)
    glow(g.x, top + g.depth / 2 - out, 140, { 1, 0.92, 0.75 }, 0.6) -- its floodlight on the load
    if math.floor(clock * 1.5 + g.phase) % 2 == 0 then
      glow(g.x, top - g.reach, 60, BEACON.red, 0.8)
    end
  end
end

return Works
