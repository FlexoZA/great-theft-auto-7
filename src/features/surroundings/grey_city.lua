-- Grey City past a map's edge (surroundings' entry for the Drop): downtown
-- carries on, out of reach. A grid of wide streets and blocks of grey
-- towers in the Drop's own colours, neon signs on their edges (the
-- Static's cyan out west, Halcyon's magenta out east, either between, now
-- and then VEX's green), street lamps along the kerbs, and traffic going
-- by: cars on every street, both ways, headlights in front and tail lights
-- behind. A haze hangs over it, thicker further out.
--
-- At night (the night feature) all of it is dark but what glows: the neon,
-- the lamps, lit windows here and there, the traffic's lights (`lights`,
-- surroundings' drawNightLights). So past the edge the city is a sea of
-- lights.
--
-- The streets and blocks are worked out from the tile they sit on, the
-- same on every machine and never running out, and drawn once into chunks
-- (canvases at half resolution, a few a frame as the camera finds them,
-- the least used thrown away past MAX_CHUNKS), as City 17's are
-- (city17.lua). The traffic and the lights are drawn every frame.

local Layout = require("src.features.city-map.layout")
local Buildings = require("src.features.city-map.buildings")

local GreyCity = {}

local T = Layout.TILE
local PERIOD = 13 -- tiles from one street to the next
local STREET = 3 -- tiles of road in each
local CHUNK = 1024 -- px of world in a chunk, each way
local MAX_CHUNKS = 40
local BUILD_PER_FRAME = 1
local HAZE = { 0.10, 0.11, 0.15 }
local HAZE_LAYERS = 14 -- the haze thickens out to HAZE_LAYERS * HAZE_STEP px past the edge
local HAZE_STEP = 140
local HAZE_EACH = 0.04 -- how much each layer adds
local CARS_PER_STREET = 3 -- each way, along one street's period
local CAR_SPEED = { 140, 260 } -- px/s
local LAMP_EVERY = 4 -- tiles between street lamps

-- city-map's Grey City colours (render_cyber_feud.lua), so it runs on unbroken.
local C = {
  asphalt = { 0.24, 0.25, 0.28 },
  lane = { 0.62, 0.56, 0.30 },
  walk = { 0.40, 0.41, 0.44 },
  walkLine = { 0.33, 0.34, 0.37 },
  kerb = { 0.34, 0.35, 0.37 },
  puddle = { 0.30, 0.33, 0.40 },
  shadow = { 0, 0, 0, 0.4 },
  car = { { 0.20, 0.21, 0.24 }, { 0.42, 0.44, 0.48 }, { 0.30, 0.12, 0.14 }, { 0.14, 0.18, 0.26 } },
  glass = { 0.08, 0.10, 0.13 },
}
local ROOFS = {
  { 0.34, 0.35, 0.37 },
  { 0.29, 0.30, 0.33 },
  { 0.40, 0.40, 0.41 },
  { 0.25, 0.26, 0.29 },
  { 0.37, 0.36, 0.38 },
}
local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }
local GREEN = { 0.43, 1.00, 0.60 }
local LAMP = { 0.80, 0.88, 1.00 }
local WINDOW = { { 1.00, 0.86, 0.62 }, { 0.70, 0.82, 1.00 } }
local HEAD = { 1.00, 0.95, 0.82 }
local TAIL = { 1.00, 0.15, 0.12 }

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- 0..1 from `n`, the same on every machine.
local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

-- The plan ------------------------------------------------------------------

local plan = nil -- { map, blocks = { ["bc,br"] = buildings } }

local function planFor(map)
  if not (plan and plan.map == map) then
    plan = { map = map, blocks = {} }
  end
  return plan
end

--- Is tile (c, r) the map's own, or the pavement right round it?
local function nearMap(map, c, r)
  return c >= -1 and c <= map.cols and r >= -1 and r <= map.rows
end

--- What is on tile (c, r) past the map: "road" or "walk". nil inside it.
local function tileKind(map, c, r)
  if c >= 0 and c < map.cols and r >= 0 and r < map.rows then
    return nil
  end
  if nearMap(map, c, r) then
    return "walk" -- a pavement along the map's edge
  end
  if c % PERIOD < STREET or r % PERIOD < STREET then
    return "road"
  end
  return "walk"
end

--- The neon of the side of town (x) a sign is on.
local function neonAt(map, x, n)
  if hash(n * 2.3) < 0.12 then
    return GREEN -- VEX can see you
  end
  if x < map.left then
    return CYAN
  elseif x > map.left + map.w then
    return MAGENTA
  end
  return hash(n * 5.1) < 0.5 and CYAN or MAGENTA
end

--- The buildings on block (bc, br): { x, y, w, h, color, style, seed, sign },
--- worked out once. None where the block runs into the map.
local function block(p, bc, br)
  local key = bc .. "," .. br
  local got = p.blocks[key]
  if got then
    return got
  end
  got = {}
  p.blocks[key] = got
  local map = p.map
  local c0, c1 = bc * PERIOD + STREET + 1, bc * PERIOD + PERIOD - 2 -- a tile of pavement round it
  local r0, r1 = br * PERIOD + STREET + 1, br * PERIOD + PERIOD - 2
  if c1 >= -1 and c0 <= map.cols and r1 >= -1 and r0 <= map.rows then
    -- Up against the map: only the biggest part of it clear of the map and
    -- the pavement round it, if there is room for one.
    local best, area = nil, 0
    for _, part in ipairs({
      { c0, r0, math.min(c1, -2), r1 }, { math.max(c0, map.cols + 1), r0, c1, r1 },
      { c0, r0, c1, math.min(r1, -2) }, { c0, math.max(r0, map.rows + 1), c1, r1 },
    }) do
      local w, h = part[3] - part[1] + 1, part[4] - part[2] + 1
      if w >= 2 and h >= 2 and w * h > area then
        best, area = part, w * h
      end
    end
    if not best then
      return got
    end
    c0, r0, c1, r1 = best[1], best[2], best[3], best[4]
  end
  local seed = bc * 73.13 + br * 19.71
  local w, h = c1 - c0 + 1, r1 - r0 + 1
  local rects
  local split = hash(seed)
  if split < 0.3 or (w < 6 and h < 6) then
    rects = { { c0, r0, w, h } }
  elseif split < 0.6 and w >= 6 then
    local cut = 3 + math.floor(hash(seed + 1) * (w - 5))
    rects = { { c0, r0, cut, h }, { c0 + cut + 1, r0, w - cut - 1, h } }
  elseif split < 0.85 and h >= 6 then
    local cut = 3 + math.floor(hash(seed + 2) * (h - 5))
    rects = { { c0, r0, w, cut }, { c0, r0 + cut + 1, w, h - cut - 1 } }
  elseif w >= 6 and h >= 6 then
    local cx, cy = 3 + math.floor(hash(seed + 1) * (w - 5)), 3 + math.floor(hash(seed + 2) * (h - 5))
    rects = {
      { c0, r0, cx, cy }, { c0 + cx + 1, r0, w - cx - 1, cy },
      { c0, r0 + cy + 1, cx, h - cy - 1 }, { c0 + cx + 1, r0 + cy + 1, w - cx - 1, h - cy - 1 },
    }
  else
    rects = { { c0, r0, w, h } }
  end
  for i, rc in ipairs(rects) do
    local s = seed + i * 7.7
    local b = {
      x = map.x0 + rc[1] * T, y = map.y0 + rc[2] * T, w = rc[3] * T, h = rc[4] * T,
      color = ROOFS[math.floor(hash(s + 3) * #ROOFS) + 1], style = 1 + math.floor(hash(s + 4) * 3),
      seed = math.floor(hash(s + 5) * 1000),
    }
    if hash(s + 6) < 0.65 then
      -- A neon sign along the edge facing the street (south or north, east or west).
      local side = math.floor(hash(s + 7) * 4)
      local len = math.min(b.w, b.h) * (0.4 + hash(s + 8) * 0.35)
      local sg
      if side < 2 then
        local x = b.x + 12 + (b.w - len - 24) * hash(s + 9)
        sg = { x = x, y = side == 0 and b.y + b.h - 10 or b.y + 2, w = len, h = 8, out = { 0, side == 0 and 1 or -1 } }
      else
        local y = b.y + 12 + (b.h - len - 24) * hash(s + 9)
        sg = { x = side == 2 and b.x + b.w - 10 or b.x + 2, y = y, w = 8, h = len, out = { side == 2 and 1 or -1, 0 } }
      end
      sg.color = neonAt(map, b.x + b.w / 2, s)
      b.sign = sg
    end
    got[#got + 1] = b
  end
  return got
end

--- Every block with a tile in the box (left, top, right, bottom), once each.
local function eachBlock(p, left, top, right, bottom, fn)
  local P = PERIOD * T
  local bx0, bx1 = math.floor((left - p.map.x0) / P), math.floor((right - p.map.x0) / P)
  local by0, by1 = math.floor((top - p.map.y0) / P), math.floor((bottom - p.map.y0) / P)
  for bc = bx0, bx1 do
    for br = by0, by1 do
      for _, b in ipairs(block(p, bc, br)) do
        fn(b)
      end
    end
  end
end

-- Drawing a chunk -------------------------------------------------------------

local function ground(map, c, r, kind)
  local x, y = map.x0 + c * T, map.y0 + r * T
  local h = hash(c * 7.1 + r * 13.7)
  if kind == "road" then
    color(C.asphalt)
    love.graphics.rectangle("fill", x, y, T, T)
    -- The dashes down the middle of a street, between its two ways.
    color(C.lane)
    local cm, rm = c % PERIOD, r % PERIOD
    if cm == 1 and rm >= STREET then
      love.graphics.rectangle("fill", x + T / 2 - 2, y + 14, 4, 36)
    elseif rm == 1 and cm >= STREET then
      love.graphics.rectangle("fill", x + 14, y + T / 2 - 2, 36, 4)
    end
  else
    color(C.walk)
    love.graphics.rectangle("fill", x, y, T, T)
    color(C.walkLine)
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
  end
  if h > 0.86 then -- a puddle, where the rain sits
    color(C.puddle, 0.9)
    love.graphics.ellipse("fill", x + 16 + h * 30, y + 14 + hash(h * 31) * 30, 14, 7, 12)
  end
end

--- The tiles round a building, for Buildings.draw to find its front by.
local function tilesOf(map)
  return setmetatable({}, {
    __index = function(_, c)
      return setmetatable({}, {
        __index = function(_, r)
          return tileKind(map, c, r)
        end,
      })
    end,
  })
end

local function drawChunk(p, cx, cy)
  local x0, y0 = cx * CHUNK, cy * CHUNK
  local map = p.map
  local c0, c1 = math.floor((x0 - map.x0) / T), math.floor((x0 + CHUNK - map.x0) / T)
  local r0, r1 = math.floor((y0 - map.y0) / T), math.floor((y0 + CHUNK - map.y0) / T)
  for c = c0, c1 do
    for r = r0, r1 do
      local kind = tileKind(map, c, r)
      if kind then
        ground(map, c, r, kind)
      end
    end
  end
  -- Blocks a little past the chunk too: their shadows fall into it.
  local standing = {}
  eachBlock(p, x0 - 2 * T, y0 - 2 * T, x0 + CHUNK + T, y0 + CHUNK + T, function(b)
    standing[#standing + 1] = b
    color(C.shadow)
    love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
  end)
  Buildings.draw({ kind = "drop", x0 = map.x0, y0 = map.y0, tiles = tilesOf(map), buildings = standing })
  for _, b in ipairs(standing) do
    local s = b.sign
    if s then
      color(s.color)
      love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
      color({ 1, 1, 1 }, 0.6)
      if s.w > s.h then
        love.graphics.rectangle("fill", s.x + 3, s.y + s.h / 2 - 1, s.w - 6, 2)
      else
        love.graphics.rectangle("fill", s.x + s.w / 2 - 1, s.y + 3, 2, s.h - 6)
      end
    end
  end
end

local chunks = { map = nil, list = {}, used = 0 } -- "cx,cy" -> { canvas, used }

local function chunk(p, cx, cy, budget)
  if chunks.map ~= p.map then
    for _, ch in pairs(chunks.list) do
      ch.canvas:release()
    end
    chunks.map, chunks.list = p.map, {}
  end
  local key = cx .. "," .. cy
  local ch = chunks.list[key]
  chunks.used = chunks.used + 1
  if ch then
    ch.used = chunks.used
    return ch
  end
  if budget.left <= 0 then
    return nil
  end
  budget.left = budget.left - 1
  local count, oldest = 0, nil
  for k, o in pairs(chunks.list) do
    count = count + 1
    if not oldest or o.used < chunks.list[oldest].used then
      oldest = k
    end
  end
  local canvas
  if count >= MAX_CHUNKS then -- the least used one's canvas does for this one
    canvas = chunks.list[oldest].canvas
    chunks.list[oldest] = nil
  else
    canvas = love.graphics.newCanvas(CHUNK / 2, CHUNK / 2)
    canvas:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.scale(0.5)
  love.graphics.translate(-cx * CHUNK, -cy * CHUNK)
  drawChunk(p, cx, cy)
  love.graphics.setCanvas()
  love.graphics.pop()
  ch = { canvas = canvas, used = chunks.used }
  chunks.list[key] = ch
  return ch
end

-- The traffic -------------------------------------------------------------------

--- Every car on the streets in the box, as fn(x, y, angle, n): along each
--- street, both ways, moving with the clock. None inside the map or on
--- the pavement round it.
local function eachCar(map, left, top, right, bottom, clock, fn)
  local P = PERIOD * T
  local function street(k, across, lo, hi, along)
    -- Street k's two lanes, at `across` + a quarter of the road either way.
    for way = -1, 1, 2 do
      local lane = across + way * STREET * T / 4
      for i = 1, CARS_PER_STREET do
        local n = k * 31.7 + i * 5.3 + way * 2.9
        local speed = CAR_SPEED[1] + hash(n) * (CAR_SPEED[2] - CAR_SPEED[1])
        local pos = (hash(n + 1) * P + way * speed * clock) % P
        local base = math.floor((lo - pos) / P) * P + pos
        for at = base, hi, P do
          local x, y
          if along == "x" then
            x, y = at, lane
          else
            x, y = lane, at
          end
          local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
          if not nearMap(map, c, r) then
            local angle = along == "x" and (way > 0 and 0 or math.pi) or (way > 0 and math.pi / 2 or -math.pi / 2)
            fn(x, y, angle, n)
          end
        end
      end
    end
  end
  local mid = STREET * T / 2
  for br = math.floor((top - map.y0) / P), math.floor((bottom - map.y0) / P) do
    street(br, map.y0 + br * P + mid, left, right, "x")
  end
  for bc = math.floor((left - map.x0) / P), math.floor((right - map.x0) / P) do
    street(bc + 1000, map.x0 + bc * P + mid, top, bottom, "y")
  end
end

local function drawCar(x, y, angle, n)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  color(C.shadow)
  love.graphics.rectangle("fill", -18, -7, 40, 18, 5)
  color(C.car[math.floor(hash(n + 2) * #C.car) + 1])
  love.graphics.rectangle("fill", -20, -9, 40, 18, 5)
  color(C.glass)
  love.graphics.rectangle("fill", 4, -7, 8, 14, 2)
  love.graphics.rectangle("fill", -12, -7, 6, 14, 2)
  color(HEAD)
  love.graphics.rectangle("fill", 18, -7, 2, 4)
  love.graphics.rectangle("fill", 18, 3, 2, 4)
  color(TAIL)
  love.graphics.rectangle("fill", -20, -7, 2, 4)
  love.graphics.rectangle("fill", -20, 3, 2, 4)
  love.graphics.pop()
end

-- Every frame -----------------------------------------------------------------

--- The haze over everything past the map: thin at the edge, thicker and
--- thicker further out, in thin layers so it has no edges to see.
local function haze(map, left, top, right, bottom)
  local mx0, my0, mx1, my1 = map.left, map.top, map.left + map.w, map.top + map.h
  for i = 0, HAZE_LAYERS - 1 do
    local d = i * HAZE_STEP
    local x0, y0, x1, y1 = mx0 - d, my0 - d, mx1 + d, my1 + d
    love.graphics.setColor(HAZE[1], HAZE[2], HAZE[3], i == 0 and 0.12 or HAZE_EACH)
    love.graphics.rectangle("fill", left, top, right - left, math.max(0, y0 - top))
    love.graphics.rectangle("fill", left, y1, right - left, math.max(0, bottom - y1))
    love.graphics.rectangle("fill", left, y0, math.max(0, x0 - left), y1 - y0)
    love.graphics.rectangle("fill", x1, y0, math.max(0, right - x1), y1 - y0)
  end
end

--- Draw it all over the box (left, top, right, bottom) the camera sees.
function GreyCity.draw(map, left, top, right, bottom, clock)
  local p = planFor(map)
  color(C.walk) -- under any chunk not made yet
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local budget = { left = BUILD_PER_FRAME }
  for cx = math.floor(left / CHUNK), math.floor(right / CHUNK) do
    for cy = math.floor(top / CHUNK), math.floor(bottom / CHUNK) do
      local ch = chunk(p, cx, cy, budget)
      if ch then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(ch.canvas, cx * CHUNK, cy * CHUNK, 0, 2, 2)
      end
    end
  end
  eachCar(map, left - 40, top - 40, right + 40, bottom + 40, clock, drawCar)
  haze(map, left, top, right, bottom)
end

--- What glows past the edge at night (the night feature's drawNightLights):
--- the neon and the light it spills on the street, lit windows, the street
--- lamps, and the traffic's head and tail lights.
function GreyCity.lights(map, left, top, right, bottom, clock, glow)
  local p = planFor(map)
  eachBlock(p, left - 300, top - 300, right + 300, bottom + 300, function(b)
    local s = b.sign
    if s then
      local flick = hash(b.seed + math.floor(clock * 8)) < 0.04 and 0.3 or 1 -- a tube on the blink now and then
      local cx, cy = s.x + s.w / 2, s.y + s.h / 2
      glow(cx, cy, 30 + math.max(s.w, s.h) * 0.5, s.color, 0.9 * flick)
      glow(cx + s.out[1] * 50, cy + s.out[2] * 50, 110 + math.max(s.w, s.h) * 0.5, s.color, 0.5 * flick)
    end
    for k = 1, 3 do -- windows still lit up on the roof
      if hash(b.seed + k * 3.7) < 0.5 then
        local wx = b.x + 16 + hash(b.seed + k * 1.9) * (b.w - 32)
        local wy = b.y + 16 + hash(b.seed + k * 2.6) * (b.h - 32)
        glow(wx, wy, 26, WINDOW[k % 2 + 1], 0.55)
      end
    end
  end)
  -- Street lamps along the kerbs of the streets past the map.
  for c = math.floor((left - map.x0) / T), math.floor((right - map.x0) / T) do
    for r = math.floor((top - map.y0) / T), math.floor((bottom - map.y0) / T) do
      local cm, rm = c % PERIOD, r % PERIOD
      local lamp = (cm == 0 and rm % LAMP_EVERY == 0 and rm >= STREET)
        or (rm == 0 and cm % LAMP_EVERY == 2 and cm >= STREET)
      if lamp and not nearMap(map, c, r) then
        glow(map.x0 + c * T + 6, map.y0 + r * T + 6, 150, LAMP, 0.3)
      end
    end
  end
  eachCar(map, left - 60, top - 60, right + 60, bottom + 60, clock, function(x, y, angle)
    local cx, cy = math.cos(angle), math.sin(angle)
    glow(x + cx * 60, y + cy * 60, 70, HEAD, 0.45) -- the beam ahead
    glow(x + cx * 22, y + cy * 22, 22, HEAD, 0.8)
    glow(x - cx * 22, y - cy * 22, 18, TAIL, 0.8)
  end)
end

return GreyCity
