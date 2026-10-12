-- The turf war past the Market's edge (grey_city.lua's war layer, for the
-- maps in GreyCity.WAR): Grey City carries on as it does round the Drop,
-- but the feud is out on its streets. A front runs north to south through
-- the city in line with the middle of the map: the Static hold the west
-- (cyan), Halcyon the east (magenta), as they do in the Market itself.
--
--   - No-man's-land, a band either side of the front: blocks bombed to
--     rubble or burning, craters in the streets, no neon left.
--   - Barricades across every street at the band's edges: the Static's
--     junk walls (wrecks, tyres, burning drums) facing Halcyon's concrete
--     blocks with a magenta stripe. Behind them, the Static's war-rigs and
--     Halcyon's interceptors, light bars flashing.
--   - Across the band, tracer fire in bursts down the streets both ways,
--     and now and then a shell coming down in the rubble.
--   - Searchlights from Halcyon's side sweeping over no-man's-land.
--   - Further back on either side, the streets are the factions': burnt
--     wrecks, burning drums on the Static's pavements, a block or two
--     burning, cyan tags sprayed over the Static's roofs and Halcyon's
--     mark on its own.
--
-- Everything is worked out from where it is and the clock, the same on
-- every machine. What stands still goes into grey_city.lua's chunks; what
-- moves (fires, tracers, shells, searchlights, light bars) is drawn every
-- frame. At night (the night feature) all of it is lit (`lights`).

local Layout = require("src.features.city-map.layout")
local Fires = require("src.features.city-map.fires")

local TurfWar = {}

local T = Layout.TILE
TurfWar.BAND = 640 -- px either side of the front that is no-man's-land

local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }
local FLASH = { 1.00, 0.85, 0.55 }
local FIRE = { 1.00, 0.50, 0.15 }
local BLUE = { 0.30, 0.50, 1.00 }
local SEARCH = { 0.85, 0.92, 1.00 }

local C = {
  rubble = { 0.36, 0.35, 0.34 },
  rubbleDark = { 0.22, 0.21, 0.21 },
  scorch = { 0.10, 0.09, 0.09 },
  crater = { 0.12, 0.12, 0.13 },
  craterRim = { 0.30, 0.29, 0.28 },
  concrete = { 0.62, 0.63, 0.66 },
  junk = { { 0.30, 0.22, 0.18 }, { 0.24, 0.24, 0.26 }, { 0.36, 0.30, 0.20 } },
  tyre = { 0.08, 0.08, 0.09 },
  drum = { 0.32, 0.20, 0.14 },
  wreck = { 0.12, 0.11, 0.11 },
  interceptor = { 0.48, 0.50, 0.55 },
  rig = { 0.26, 0.24, 0.22 },
  chrome = { 0.70, 0.74, 0.78 },
  shadow = { 0, 0, 0, 0.4 },
}

local TRACER_SPEED = 1500 -- px/s
local BURST_ROUNDS = 6
local BURST_GAP = 0.07 -- seconds between rounds in a burst
local BOOM_EVERY = 6 -- seconds between shells on one block of no-man's-land (each its own time)
local BOOM_TIME = 0.6 -- seconds a shell's burst shows

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

--- The war's lines on `map`: where the front is, and the band's edges.
function TurfWar.lines(map)
  local front = map.left + map.w / 2
  return front, front - TurfWar.BAND, front + TurfWar.BAND
end

--- Whose ground (x) is: "static", "halcyon" or "none" (no-man's-land).
function TurfWar.side(map, x)
  local _, west, east = TurfWar.lines(map)
  if x < west then
    return "static"
  elseif x > east then
    return "halcyon"
  end
  return "none"
end

--- How a building fares, from its seed `s`: b.ruin, b.burning (with
--- b.fire), b.mark ("tag" or "logo"), and no sign in no-man's-land.
function TurfWar.fate(map, b, s)
  local side = TurfWar.side(map, b.x + b.w / 2)
  local fate = hash(s + 10)
  if side == "none" then
    b.ruin = fate < 0.65
    b.burning = not b.ruin
    b.sign = nil
  else
    b.ruin = fate < 0.1
    b.burning = not b.ruin and fate < 0.22
    if not (b.ruin or b.burning) and hash(s + 11) < 0.45 then
      b.mark = side == "static" and "tag" or "logo"
    end
  end
  if b.ruin or b.burning then
    b.sign = nil -- the neon went with the roof
  end
  if b.burning then
    b.fire = { kind = "roof", x = b.x + b.w * (0.3 + hash(s + 12) * 0.4), y = b.y + b.h * (0.3 + hash(s + 13) * 0.4),
      r = 30, seed = b.seed }
  end
  if b.sign then -- the neon is whoever holds that side now
    b.sign.color = side == "static" and CYAN or MAGENTA
  end
end

-- In the chunks (still) -------------------------------------------------------

--- A heap of what used to be a tower.
local function ruin(b)
  local seed = b.seed
  color(C.rubbleDark)
  love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12, 10)
  for i = 1, math.floor(b.w * b.h / 1400) do
    local x = b.x + 8 + hash(seed + i * 1.7) * (b.w - 30)
    local y = b.y + 8 + hash(seed + i * 2.9) * (b.h - 30)
    color(i % 3 == 0 and C.rubbleDark or C.rubble)
    love.graphics.rectangle("fill", x, y, 10 + hash(seed + i * 4.1) * 18, 8 + hash(seed + i * 5.3) * 14, 2)
  end
  color(C.rubbleDark)
  love.graphics.rectangle("fill", b.x + 4, b.y + 4, b.w * (0.3 + hash(seed) * 0.5), 10)
  love.graphics.rectangle("fill", b.x + 4, b.y + 4, 10, b.h * (0.3 + hash(seed + 1) * 0.5))
end

--- A black scorch round a burning roof, and the hole through it.
local function burnt(b)
  local f = b.fire
  color(C.scorch)
  love.graphics.circle("fill", f.x, f.y, f.r * 2.2, 20)
  for i = 1, 6 do
    local a = hash(f.seed + i * 3.1) * 2 * math.pi
    local d = f.r * 2.2 * (0.6 + hash(f.seed + i * 1.3) * 0.5)
    love.graphics.circle("fill", f.x + math.cos(a) * d, f.y + math.sin(a) * d, f.r * 0.7, 10)
  end
  love.graphics.setColor(0.03, 0.02, 0.02)
  love.graphics.rectangle("fill", f.x - f.r * 0.6, f.y - f.r * 0.5, f.r * 1.2, f.r, 4)
end

--- Sprayed over a Static roof: a few fat cyan strokes. Over a Halcyon one:
--- its mark, a hexagon round an H.
local function mark(b)
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  local size = math.min(b.w, b.h) * 0.28
  if b.mark == "tag" then
    color(CYAN, 0.75)
    love.graphics.setLineWidth(5)
    local pts = {}
    for i = 0, 5 do
      pts[#pts + 1] = cx - size + i * size * 0.4
      pts[#pts + 1] = cy + (hash(b.seed + i * 2.3) - 0.5) * size * 1.2
    end
    love.graphics.line(pts)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", cx + size * 0.9, cy - size * 0.5, size * 0.3, 10)
  else
    color(MAGENTA, 0.6)
    love.graphics.setLineWidth(4)
    local hex = {}
    for i = 0, 5 do
      local a = i * math.pi / 3
      hex[#hex + 1] = cx + math.cos(a) * size
      hex[#hex + 1] = cy + math.sin(a) * size
    end
    love.graphics.polygon("line", hex)
    love.graphics.line(cx - size * 0.4, cy - size * 0.5, cx - size * 0.4, cy + size * 0.5)
    love.graphics.line(cx + size * 0.4, cy - size * 0.5, cx + size * 0.4, cy + size * 0.5)
    love.graphics.line(cx - size * 0.4, cy, cx + size * 0.4, cy)
  end
  love.graphics.setLineWidth(1)
end

--- A building as the war left it, drawn over grey_city's own.
function TurfWar.drawBuilding(b)
  if b.ruin then
    ruin(b)
  elseif b.burning then
    burnt(b)
  elseif b.mark then
    mark(b)
  end
end

--- A burnt-out car, nose along `angle`.
local function wreck(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  color(C.scorch)
  love.graphics.ellipse("fill", 0, 0, 30, 18, 14)
  color(C.wreck)
  love.graphics.rectangle("fill", -20, -9, 40, 18, 5)
  love.graphics.setColor(0.05, 0.05, 0.05)
  love.graphics.rectangle("fill", -10, -7, 18, 14, 2)
  love.graphics.pop()
end

--- What the war left on ground tile (c, r) at (x, y), of `kind` ("road"/"walk").
function TurfWar.drawGround(map, c, r, kind, x, y)
  local side = TurfWar.side(map, x + T / 2)
  local h = hash(c * 3.7 + r * 11.3)
  if side == "none" then
    local k = hash(h * 17.9)
    if h < (kind == "road" and 0.1 or 0.03) then -- a crater, a shell's
      local cx, cy, rr = x + T / 2 + (k - 0.5) * 30, y + T / 2 + (hash(k * 5) - 0.5) * 30, 10 + k * 22
      color(C.craterRim)
      love.graphics.circle("fill", cx, cy, rr + 6, 18)
      color(C.scorch)
      love.graphics.circle("fill", cx, cy, rr + 1, 16)
      color(C.crater)
      love.graphics.circle("fill", cx + 2, cy + 2, rr * 0.7, 14)
    elseif h < 0.35 then -- rubble blown into the street, a few lumps
      for i = 1, 1 + math.floor(k * 3) do
        color(hash(h * i) < 0.5 and C.rubble or C.rubbleDark)
        local rx, ry = x + hash(h * i * 3.1) * 50, y + hash(h * i * 7.3) * 50
        love.graphics.rectangle("fill", rx, ry, 6 + k * 12, 5 + k * 9, 2)
      end
    end
  elseif kind == "road" and h < 0.05 then
    wreck(x + T / 2, y + T / 2, hash(h * 13) * math.pi)
  end
end

--- One street's barricades (an east-west street, its middle at y, `width` px
--- of road): the Static's junk wall and Halcyon's concrete line.
local function barricades(y, width, west, east, seed)
  local n = math.floor(width / 26)
  for i = 0, n - 1 do -- the Static's: whatever they could drag there
    local by = y - width / 2 + 6 + i * 26
    local k = hash(seed + i * 1.9)
    if k < 0.35 then
      color(C.tyre)
      love.graphics.circle("fill", west, by + 10, 11, 12)
      love.graphics.setColor(0.18, 0.18, 0.2)
      love.graphics.circle("fill", west, by + 10, 5, 10)
    elseif k < 0.55 then
      color(C.drum)
      love.graphics.circle("fill", west, by + 10, 10, 12)
    else
      color(C.junk[math.floor(k * 10) % #C.junk + 1])
      love.graphics.rectangle("fill", west - 12 + (k - 0.5) * 10, by, 24, 22, 3)
    end
  end
  for i = 0, n - 1 do -- Halcyon's: blocks in a row, a magenta stripe on each
    local by = y - width / 2 + 4 + i * 26
    color(C.shadow)
    love.graphics.rectangle("fill", east - 9, by + 3, 20, 22, 2)
    color(C.concrete)
    love.graphics.rectangle("fill", east - 11, by, 20, 22, 2)
    color(MAGENTA, 0.85)
    love.graphics.rectangle("fill", east - 11, by + 9, 20, 4)
  end
end

--- Everything still that goes into a chunk: the barricades on the
--- east-west streets. `streets(fn)` names each street in the box as
--- fn(k, y, width).
function TurfWar.drawStill(map, streets)
  local _, west, east = TurfWar.lines(map)
  streets(function(k, y, width)
    barricades(y, width, west, east, k * 17.3)
  end)
end

-- Every frame (moving) ----------------------------------------------------------

--- The parked machines behind each barricade: Halcyon's interceptors (light
--- bars flashing magenta and blue) and the Static's war-rigs (a spiked ram,
--- a cyan lamp).
local function machines(map, streets, clock, fn)
  local _, west, east = TurfWar.lines(map)
  streets(function(k, y, width)
    for way = -1, 1, 2 do
      local lane = y + way * width / 4
      local n = k * 7.7 + way
      fn("halcyon", east + 90 + hash(n) * 60, lane, math.pi, n, clock)
      fn("static", west - 110 - hash(n + 1) * 60, lane, 0, n, clock)
    end
  end)
end

local function drawMachine(kind, x, y, angle, n, clock)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  color(C.shadow)
  love.graphics.rectangle("fill", -20, -7, 44, 20, 5)
  if kind == "halcyon" then
    color(C.interceptor)
    love.graphics.rectangle("fill", -22, -10, 44, 20, 5)
    love.graphics.setColor(0.08, 0.10, 0.13)
    love.graphics.rectangle("fill", 4, -8, 9, 16, 2)
    local on = math.floor(clock * 6 + n) % 2 == 0
    color(on and MAGENTA or BLUE)
    love.graphics.rectangle("fill", -6, -8, 4, 8)
    color(on and BLUE or MAGENTA)
    love.graphics.rectangle("fill", -6, 0, 4, 8)
  else
    color(C.rig)
    love.graphics.rectangle("fill", -26, -12, 52, 24, 3)
    color(C.chrome)
    for i = -1, 1 do -- the ram's spikes
      love.graphics.polygon("fill", 26, i * 8 - 4, 26, i * 8 + 4, 34, i * 8)
    end
    love.graphics.setColor(0.10, 0.10, 0.11)
    love.graphics.rectangle("fill", 10, -10, 10, 20, 2)
    color(CYAN, 0.6 + 0.4 * math.abs(math.sin(clock * 3 + n)))
    love.graphics.circle("fill", -18, 0, 3, 8)
  end
  love.graphics.pop()
end

--- Every round of tracer fire in flight on the streets: fn(x, y, dir, side)
--- with `dir` 1 going east, -1 going west. Each street, each way, fires a
--- burst every few seconds, at its own time.
local function tracers(map, streets, clock, fn)
  local _, west, east = TurfWar.lines(map)
  local span = east - west
  local flight = span / TRACER_SPEED
  streets(function(k, y, width)
    for way = -1, 1, 2 do
      local n = k * 13.1 + way * 3.3
      local every = 2.2 + hash(n) * 2.5
      local since = (clock + hash(n + 1) * every) % every -- seconds since this burst began
      for i = 0, BURST_ROUNDS - 1 do
        local t = since - i * BURST_GAP
        if t >= 0 and t <= flight then
          local lane = y + (hash(n + i * 0.7) - 0.5) * width * 0.7
          if way > 0 then -- the Static firing east
            fn(west + 16 + t * TRACER_SPEED, lane, 1, "static", t)
          else
            fn(east - 16 - t * TRACER_SPEED, lane, -1, "halcyon", t)
          end
        end
      end
    end
  end)
end

--- Every shell coming down in no-man's-land in the box: fn(x, y, k) with
--- k 0..1 through its burst. One block of the band at a time, each on its own clock.
local function booms(map, top, bottom, clock, fn)
  local front = TurfWar.lines(map)
  local cell = 260
  for row = math.floor((top - map.y0) / cell) - 1, math.floor((bottom - map.y0) / cell) + 1 do
    for col = -2, 2 do
      local n = row * 5.9 + col * 2.1
      local every = BOOM_EVERY * (0.7 + hash(n) * 0.9)
      local since = (clock + hash(n + 1) * every) % every
      if since < BOOM_TIME then
        local x = front + col * cell + (hash(n + math.floor((clock + hash(n + 1) * every) / every)) - 0.5) * cell
        local y = map.y0 + row * cell + hash(n + 2) * cell
        if y < map.top - 2 * T or y > map.top + map.h + 2 * T then -- not on the Market's own roof
          fn(x, y, since / BOOM_TIME)
        end
      end
    end
  end
end

--- Halcyon's searchlights, from just behind its barricade, sweeping over
--- no-man's-land: fn(x, y, angle) for each, one to a street.
local function searchlights(map, streets, clock, fn)
  local _, _, east = TurfWar.lines(map)
  streets(function(k, y)
    if k % 2 == 0 then
      local angle = math.pi + math.sin(clock * 0.4 + k * 1.3) * 0.7
      fn(east + 40, y, angle)
    end
  end)
end

--- The fires burning at the barricades: a drum alight on the Static's, on
--- every street, added to `list`.
function TurfWar.fires(map, streets, list)
  local _, west = TurfWar.lines(map)
  streets(function(k, y, width)
    list[#list + 1] = { kind = "barrel", x = west - 30, y = y + (hash(k * 2.7) - 0.5) * width * 0.6, r = 12,
      seed = math.floor(hash(k * 4.1) * 1000) }
  end)
  return list
end

--- Draw what moves, over the chunks: fires, the machines, the searchlight
--- beams, the tracers and the shells.
function TurfWar.draw(map, streets, top, bottom, clock, camera, fires)
  Fires.draw({ fires = fires }, camera, clock)
  machines(map, streets, clock, drawMachine)
  searchlights(map, streets, clock, function(x, y, angle)
    local len, spread = 900, 0.12
    color(SEARCH, 0.06)
    love.graphics.polygon("fill", x, y, x + math.cos(angle - spread) * len, y + math.sin(angle - spread) * len,
      x + math.cos(angle + spread) * len, y + math.sin(angle + spread) * len)
  end)
  love.graphics.setLineWidth(2)
  tracers(map, streets, clock, function(x, y, dir, side)
    color(side == "static" and CYAN or MAGENTA)
    love.graphics.line(x, y, x - dir * 26, y)
    color(FLASH)
    love.graphics.line(x, y, x - dir * 6, y)
  end)
  booms(map, top, bottom, clock, function(x, y, k)
    color(FIRE, 0.8 * (1 - k))
    love.graphics.circle("fill", x, y, 20 + k * 50, 20)
    color(FLASH, 1 - k)
    love.graphics.circle("fill", x, y, 14 * (1 - k) + 4, 14)
    color(C.rubbleDark, 1 - k)
    for i = 1, 6 do -- debris thrown out
      local a = i / 6 * 2 * math.pi + x
      love.graphics.circle("fill", x + math.cos(a) * k * 80, y + math.sin(a) * k * 80, 3, 6)
    end
  end)
  love.graphics.setLineWidth(1)
  local _, west, east = TurfWar.lines(map)
  streets(function(k, y, width) -- the muzzle flashes along the barricades while a burst is going
    for way = -1, 1, 2 do
      local n = k * 13.1 + way * 3.3
      local every = 2.2 + hash(n) * 2.5
      local since = (clock + hash(n + 1) * every) % every
      if since < BURST_ROUNDS * BURST_GAP and math.floor(since / BURST_GAP) % 2 == 0 then
        color(FLASH)
        love.graphics.circle("fill", way > 0 and west + 14 or east - 14, y + (hash(n) - 0.5) * width * 0.5, 5, 8)
      end
    end
  end)
end

--- What glows at night: the fires, the barricades' drums, the muzzle
--- flashes and tracers, the shells, the searchlights, the light bars.
function TurfWar.lights(map, streets, top, bottom, clock, glow, fires)
  for _, f in ipairs(fires) do
    local flicker = 0.8 + 0.2 * math.sin(clock * 9 + f.seed)
    glow(f.x, f.y, f.kind == "roof" and 220 or 110, FIRE, 0.75 * flicker)
  end
  machines(map, streets, clock, function(kind, x, y, _angle, n)
    if kind == "halcyon" then
      local on = math.floor(clock * 6 + n) % 2 == 0
      glow(x, y, 60, on and MAGENTA or BLUE, 0.7)
    else
      glow(x, y, 40, CYAN, 0.4)
    end
  end)
  searchlights(map, streets, clock, function(x, y, angle)
    for d = 1, 6 do -- a beam is a row of glows growing wider out
      local r = d * 150
      glow(x + math.cos(angle) * r, y + math.sin(angle) * r, 40 + d * 18, SEARCH, 0.32 - d * 0.03)
    end
  end)
  tracers(map, streets, clock, function(x, y, _dir, side)
    glow(x, y, 26, side == "static" and CYAN or MAGENTA, 0.8)
  end)
  local _, west, east = TurfWar.lines(map)
  streets(function(k, y)
    for way = -1, 1, 2 do
      local n = k * 13.1 + way * 3.3
      local every = 2.2 + hash(n) * 2.5
      local since = (clock + hash(n + 1) * every) % every
      if since < BURST_ROUNDS * BURST_GAP then
        glow(way > 0 and west + 14 or east - 14, y, 70, FLASH, 0.8)
      end
    end
  end)
  booms(map, top, bottom, clock, function(x, y, k)
    glow(x, y, 260 * (0.5 + k), FIRE, 1 - k)
  end)
end

return TurfWar
