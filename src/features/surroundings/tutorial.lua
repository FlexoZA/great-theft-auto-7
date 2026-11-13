-- Past the edges of Shoeman's school of survival (the tutorial feature,
-- docs/tutorial.md), each map its own:
--
--   tutorial-road  The embankment the streets tunnel under carries on both
--                  ways, a railway along the top of each bank with a train
--                  going by now and then; south of the yard, past its
--                  railings, the school's playground and the school; north
--                  of the lawn, and out past the railways, woods.
--   tutorial-park  The park sits in a town: a street round the hedge with
--                  cars going round it, then blocks of terraced houses with
--                  back gardens, street after street.
--   tutorial-yard  The scrap yard sits on an industrial estate: a road round
--                  its fence, then warehouses and stacks of containers on
--                  concrete lots.
--
-- Shoeman's Town gets the city's sea (init.lua's DRAW): it is an island too.
-- init.lua hands in its helpers (`kit`): woods, building, treePictures.

local Tutorial = {}

local C = { -- render_tutorial.lua's colours, so the edges don't show
  grass = { 0.36, 0.53, 0.26 },
  grassLight = { 0.44, 0.61, 0.31 },
  grassDark = { 0.29, 0.44, 0.21 },
  slab = { 0.66, 0.65, 0.62 },
  slabDark = { 0.58, 0.57, 0.54 },
  kerb = { 0.80, 0.79, 0.76 },
  asphalt = { 0.22, 0.22, 0.24 },
  line = { 0.92, 0.92, 0.88 },
  yellow = { 0.95, 0.78, 0.22 },
  concrete = { 0.62, 0.62, 0.60 },
  concreteDark = { 0.45, 0.45, 0.44 },
  concreteLight = { 0.74, 0.74, 0.72 },
  shadow = { 0, 0, 0, 0.3 },
  gravel = { 0.50, 0.47, 0.42 },
  sleeper = { 0.33, 0.25, 0.18 },
  rail = { 0.68, 0.68, 0.70 },
  lawn = { 0.38, 0.58, 0.28 },
  sheet = { 0.56, 0.58, 0.58 },
}

local CAR_COLORS = {
  { 0.75, 0.2, 0.18 }, { 0.2, 0.35, 0.7 }, { 0.85, 0.85, 0.82 }, { 0.2, 0.2, 0.22 }, { 0.85, 0.65, 0.2 },
}
local ROOFS = {
  { 0.55, 0.28, 0.22 }, { 0.42, 0.40, 0.42 }, { 0.62, 0.36, 0.26 }, { 0.36, 0.34, 0.38 }, { 0.5, 0.45, 0.4 },
}
local CONTAINERS = {
  { 0.70, 0.22, 0.16 }, { 0.16, 0.36, 0.62 }, { 0.20, 0.50, 0.30 }, { 0.80, 0.55, 0.15 }, { 0.45, 0.45, 0.48 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A number in [0, 1) from `n`, the same every frame.
local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- Grass over the view, speckled on a grid anchored in the world.
local function grass(left, top, right, bottom)
  color(C.grass)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local G = 40
  for c = math.floor(left / G), math.ceil(right / G) do
    for r = math.floor(top / G), math.ceil(bottom / G) do
      local k = c * 7.31 + r * 3.17
      color(hash(k) < 0.5 and C.grassLight or C.grassDark, 0.7)
      love.graphics.rectangle("fill", c * G + hash(k * 1.3) * 30, r * G + hash(k * 2.1) * 34, 4 + hash(k * 3.7) * 6, 3)
    end
  end
end

--- A car from above going along `angle`, `len` px long.
local function car(x, y, angle, col, len)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  local l, w = len or 44, 22
  color(C.shadow)
  love.graphics.rectangle("fill", -l / 2 + 3, -w / 2 + 3, l, w, 5)
  color(col)
  love.graphics.rectangle("fill", -l / 2, -w / 2, l, w, 5)
  love.graphics.setColor(0.15, 0.2, 0.25)
  love.graphics.rectangle("fill", l * 0.08, -w / 2 + 3, l * 0.18, w - 6, 2) -- the windscreen
  love.graphics.rectangle("fill", -l * 0.36, -w / 2 + 4, l * 0.12, w - 8, 2) -- the back window
  love.graphics.pop()
end

-- Shoeman's Road ----------------------------------------------------------

local RAIL_OUT = 260 -- px out from each side to the middle of its railway
local BALLAST = 70 -- px across the railway's stones
local TRAIN_EVERY = 34 -- seconds between trains, each line its own
local SCHOOL_OUT = 260 -- px south of the map's edge the school starts (the playground before it)
local SCHOOL_H = 380 -- px deep the school building is

--- A railway down the world at `x` between `top` and `bottom`: stones, sleepers, two rails.
local function railway(x, top, bottom)
  color(C.gravel)
  love.graphics.rectangle("fill", x - BALLAST / 2, top, BALLAST, bottom - top)
  color(C.sleeper)
  for y = math.floor(top / 18) * 18, bottom, 18 do
    love.graphics.rectangle("fill", x - 24, y, 48, 7)
  end
  color(C.rail)
  love.graphics.setLineWidth(3)
  love.graphics.line(x - 14, top, x - 14, bottom)
  love.graphics.line(x + 14, top, x + 14, bottom)
  love.graphics.setLineWidth(1)
end

--- A train on the railway at `x`: its front at `y`, heading `dir` (-1 north, 1 south).
local function train(x, y, dir)
  local cars = { { 110, { 0.80, 0.25, 0.15 } } } -- the engine first
  for _ = 1, 6 do
    cars[#cars + 1] = { 120, { 0.30, 0.40, 0.55 } }
  end
  local at = y
  for _, c in ipairs(cars) do
    local y0 = dir < 0 and at or at - c[1]
    color(C.shadow)
    love.graphics.rectangle("fill", x - 18 + 5, y0 + 5, 36, c[1], 4)
    color(c[2])
    love.graphics.rectangle("fill", x - 18, y0, 36, c[1], 4)
    love.graphics.setColor(c[2][1] * 0.75, c[2][2] * 0.75, c[2][3] * 0.75)
    love.graphics.rectangle("fill", x - 12, y0 + 8, 24, c[1] - 16, 3)
    at = at - dir * (c[1] + 8)
  end
end

--- The school south of the yard: railings, the playground with its court, the building.
local function school(map, edge, left, right)
  local x0, x1 = map.left - RAIL_OUT + BALLAST, map.left + map.w + RAIL_OUT - BALLAST -- between the railways
  if x1 > left and x0 < right then
    color(C.slab)
    love.graphics.rectangle("fill", x0, edge, x1 - x0, 40)
    color(C.asphalt)
    love.graphics.rectangle("fill", x0, edge + 40, x1 - x0, SCHOOL_OUT - 40)
    color(C.yellow, 0.8)
    love.graphics.setLineWidth(3)
    local cx = map.left + map.w / 2
    love.graphics.rectangle("line", cx - 220, edge + 70, 440, 160) -- the court
    love.graphics.line(cx, edge + 70, cx, edge + 230)
    love.graphics.circle("line", cx, edge + 150, 34)
    for k = 0, 7 do -- hopscotch
      love.graphics.rectangle("line", map.left + 120, edge + 70 + k * 22, 26, 22)
    end
    love.graphics.setLineWidth(1)
    -- Railings along the yard's foot, a post every 16 px.
    love.graphics.setColor(0.12, 0.14, 0.18)
    love.graphics.setLineWidth(2)
    love.graphics.line(x0, edge + 4, x1, edge + 4)
    for x = x0, x1, 16 do
      love.graphics.circle("fill", x, edge + 4, 2.5, 6)
    end
    love.graphics.setLineWidth(1)
    -- The building: a flat roof, plant on it, skylights down its length.
    local y0 = edge + SCHOOL_OUT
    color(C.shadow)
    love.graphics.rectangle("fill", x0 + 12, y0 + 12, x1 - x0, SCHOOL_H)
    color(C.concrete)
    love.graphics.rectangle("fill", x0, y0, x1 - x0, SCHOOL_H)
    color(C.concreteLight)
    love.graphics.rectangle("fill", x0, y0, x1 - x0, 8)
    color(C.concreteDark)
    love.graphics.rectangle("line", x0 + 14, y0 + 14, x1 - x0 - 28, SCHOOL_H - 28)
    for x = x0 + 80, x1 - 120, 160 do
      love.graphics.setColor(0.55, 0.68, 0.74)
      love.graphics.rectangle("fill", x, y0 + 60, 70, 40, 3)
      color(C.concreteDark)
      love.graphics.rectangle("fill", x + 10, y0 + 220, 50, 50, 4)
      love.graphics.setColor(0.3, 0.3, 0.32)
      love.graphics.circle("fill", x + 35, y0 + 245, 16, 12) -- a fan
    end
  end
end

function Tutorial.road(map, camera, left, top, right, bottom, t, kit)
  grass(left, top, right, bottom)
  local L, R, edge = map.left, map.left + map.w, map.top + map.h
  local schoolEnd = edge + SCHOOL_OUT + SCHOOL_H + 80
  local railW, railE = L - RAIL_OUT, R + RAIL_OUT
  -- Woods north of the lawn, beyond the school, and out past the railways.
  kit.woods(map, camera, 40, 80, kit.BROADLEAF, function(x, y)
    local nearRail = math.abs(x - railW) < BALLAST or math.abs(x - railE) < BALLAST
    local open = y < map.top - 40 or y > schoolEnd or x < railW - BALLAST or x > railE + BALLAST
    return nearRail or not open
  end)
  railway(railW, top, bottom)
  railway(railE, top, bottom)
  -- A train down one line and, half a lap later, up the other.
  local span = map.h + 4000
  for i, line in ipairs({ { x = railW, dir = 1, phase = 0 }, { x = railE, dir = -1, phase = 0.5 } }) do
    local k = ((t / TRAIN_EVERY) + line.phase + i * 0.13) % 1
    local y = line.dir > 0 and map.top - 2000 + k * span or edge + 2000 - k * span
    if y > top - 1000 and y < bottom + 1000 then
      train(line.x, y, line.dir)
    end
  end
  school(map, edge, left, right)
end

-- Town blocks: the park's houses and the yard's estate ----------------------

local STREET = 128 -- px across a street, kerb to kerb
local PAVE = 36 -- px of pavement either side of it

--- The street round the map (it meets the edge), then blocks of `size` on a
--- grid anchored at the ring, `fill(x, y, w, h, n)` drawing each; a block
--- the ring cuts is trimmed to what is left of it outside.
local function blocks(map, left, top, right, bottom, size, fill)
  color(C.asphalt)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  local out = 2 * PAVE + STREET -- to the far side of the street's far pavement
  local rx0, ry0 = map.left - out, map.top - out
  local rx1, ry1 = map.left + map.w + out, map.top + map.h + out
  -- The pavement along the map's edge, on the street's near side.
  color(C.slab)
  love.graphics.rectangle("fill", map.left - PAVE, map.top - PAVE, map.w + 2 * PAVE, map.h + 2 * PAVE)
  -- Blocks about `size` across, stretched a little each way so a whole
  -- number of them spans the ring and they line up on its far side too.
  local function fit(span)
    local period = (span - STREET) / math.max(1, math.floor((span - STREET) / (size + STREET) + 0.5))
    return period, period - STREET
  end
  local px, sx = fit(rx1 - rx0)
  local py, sy = fit(ry1 - ry0)
  for i = math.floor((left - rx0) / px) - 1, math.ceil((right - rx0) / px) + 1 do
    for j = math.floor((top - ry0) / py) - 1, math.ceil((bottom - ry0) / py) + 1 do
      local x0, y0 = rx0 + i * px - sx, ry0 + j * py - sy
      local x1, y1 = x0 + sx, y0 + sy
      if x1 > rx0 and x0 < rx1 and y1 > ry0 and y0 < ry1 then
        -- Cut by the ring: keep the biggest piece of it outside.
        local best, area = nil, 0
        for _, p in ipairs({ { x0, y0, math.min(x1, rx0), y1 }, { math.max(x0, rx1), y0, x1, y1 },
          { x0, y0, x1, math.min(y1, ry0) }, { x0, math.max(y0, ry1), x1, y1 } }) do
          local a = (p[3] - p[1]) * (p[4] - p[2])
          if p[3] - p[1] > 150 and p[4] - p[2] > 150 and a > area then
            best, area = p, a
          end
        end
        if best then -- its own pavement lands on the street's far one
          x0, y0, x1, y1 = best[1], best[2], best[3], best[4]
        else
          x0 = nil
        end
      end
      if x0 and x1 > left and x0 < right and y1 > top and y0 < bottom then
        color(C.slab)
        love.graphics.rectangle("fill", x0 - PAVE, y0 - PAVE, x1 - x0 + 2 * PAVE, y1 - y0 + 2 * PAVE)
        color(C.kerb)
        love.graphics.rectangle("line", x0 - PAVE, y0 - PAVE, x1 - x0 + 2 * PAVE, y1 - y0 + 2 * PAVE)
        fill(x0, y0, x1 - x0, y1 - y0, hash(i * 7.7 + j * 3.3))
      end
    end
  end
  -- The centre line round the ring.
  local m = PAVE + STREET / 2
  color(C.line, 0.7)
  love.graphics.setLineWidth(3)
  for _, s in ipairs({ { map.left - m, map.top - m, map.left + map.w + m, map.top - m },
    { map.left - m, map.top + map.h + m, map.left + map.w + m, map.top + map.h + m },
    { map.left - m, map.top - m, map.left - m, map.top + map.h + m },
    { map.left + map.w + m, map.top - m, map.left + map.w + m, map.top + map.h + m } }) do
    local len = math.abs(s[3] - s[1]) + math.abs(s[4] - s[2])
    local dx, dy = (s[3] - s[1]) / len, (s[4] - s[2]) / len
    for d = 0, len - 30, 64 do
      love.graphics.line(s[1] + dx * d, s[2] + dy * d, s[1] + dx * (d + 30), s[2] + dy * (d + 30))
    end
  end
  love.graphics.setLineWidth(1)
end

--- Cars driving round the ring, clockwise in the outer lane, the other way
--- in the inner, each at its own pace.
local RING_CARS = {
  { speed = 0.020, phase = 0.1, lane = 1 },
  { speed = 0.016, phase = 0.55, lane = 1 },
  { speed = -0.018, phase = 0.3, lane = -1 },
  { speed = -0.014, phase = 0.8, lane = -1 },
}

local function ringCars(map, t)
  local m = PAVE + STREET / 2
  for i, c in ipairs(RING_CARS) do
    local inset = m - c.lane * STREET / 4
    local x0, y0 = map.left - inset, map.top - inset
    local w, h = map.w + 2 * inset, map.h + 2 * inset
    local per = 2 * (w + h)
    local d = ((c.phase + t * c.speed) % 1) * per
    local x, y, a
    if d < w then
      x, y, a = x0 + d, y0, 0
    elseif d < w + h then
      x, y, a = x0 + w, y0 + d - w, math.pi / 2
    elseif d < 2 * w + h then
      x, y, a = x0 + w - (d - w - h), y0 + h, math.pi
    else
      x, y, a = x0, y0 + h - (d - 2 * w - h), -math.pi / 2
    end
    if c.speed < 0 then
      a = a + math.pi
    end
    car(x, y, a, CAR_COLORS[(i - 1) % #CAR_COLORS + 1])
  end
end

local HOUSE_W, HOUSE_D = 64, 84 -- a terraced house's frontage and depth, px

--- A block of terraced houses: a row along each long side facing the
--- street, their back gardens meeting in the middle, a tree in some.
local function houses(kit)
  return function(x, y, w, h, n)
    color(C.lawn)
    love.graphics.rectangle("fill", x, y, w, h)
    local count = math.floor(w / HOUSE_W)
    local x0 = x + (w - count * HOUSE_W) / 2
    for k = 0, count - 1 do
      local hx = x0 + k * HOUSE_W
      local roof = ROOFS[math.floor(hash(n * 31 + k) * #ROOFS) + 1]
      kit.building(hx + 1, y, HOUSE_W - 2, HOUSE_D, roof)
      if h > 2 * HOUSE_D + 40 then
        kit.building(hx + 1, y + h - HOUSE_D, HOUSE_W - 2, HOUSE_D, ROOFS[math.floor(hash(n * 17 + k) * #ROOFS) + 1])
      end
      love.graphics.setColor(0.45, 0.33, 0.22, 0.8) -- the garden fences
      love.graphics.line(hx, y + HOUSE_D, hx, y + h - HOUSE_D)
    end
    local pics = kit.treePictures()
    for k = 0, count - 1, 3 do
      local hx = x0 + (k + 0.5) * HOUSE_W
      if hash(n * 5 + k) > 0.45 and h > 2 * HOUSE_D + 60 then
        love.graphics.setColor(1, 1, 1)
        love.graphics.draw(pics[3], hx, y + h / 2, 0, 0.9, 0.9, kit.TREE_SIZE / 2, kit.TREE_SIZE / 2)
      end
    end
  end
end

function Tutorial.park(map, _camera, left, top, right, bottom, t, kit)
  blocks(map, left, top, right, bottom, 420, houses(kit))
  ringCars(map, t)
end

--- A warehouse filling the lot: a ribbed metal roof, skylights, a loading
--- yard in front with a lorry's trailer at the dock.
local function warehouse(x, y, w, h, n)
  color(C.concreteDark)
  love.graphics.rectangle("fill", x, y, w, h)
  local yard = math.min(110, h * 0.3)
  local rx, ry, rw, rh = x + 20, y + 20, w - 40, h - yard - 20
  color(C.shadow)
  love.graphics.rectangle("fill", rx + 12, ry + 12, rw, rh)
  local tint = 0.85 + n * 0.25
  love.graphics.setColor(C.sheet[1] * tint, C.sheet[2] * tint, C.sheet[3] * tint)
  love.graphics.rectangle("fill", rx, ry, rw, rh)
  love.graphics.setColor(C.sheet[1] * tint * 0.8, C.sheet[2] * tint * 0.8, C.sheet[3] * tint * 0.8)
  for xx = rx + 6, rx + rw - 4, 12 do
    love.graphics.rectangle("fill", xx, ry, 4, rh)
  end
  love.graphics.setColor(0.55, 0.68, 0.74, 0.9)
  for xx = rx + 40, rx + rw - 60, 90 do
    love.graphics.rectangle("fill", xx, ry + rh * 0.3, 30, rh * 0.4)
  end
  -- The trailer at the dock, and the yard's painted bays.
  local tx = rx + rw * (0.2 + n * 0.5)
  color(C.shadow)
  love.graphics.rectangle("fill", tx + 4, ry + rh + 4, 34, yard - 24)
  color(CONTAINERS[math.floor(n * 97) % #CONTAINERS + 1])
  love.graphics.rectangle("fill", tx, ry + rh, 34, yard - 24, 2)
  color(C.line, 0.6)
  for bx = rx, rx + rw - 40, 50 do
    love.graphics.line(bx, y + h - 6, bx, y + h - 40)
  end
end

--- A lot of shipping containers stacked in rows, a gap down the middle for the forklift.
local function containers(x, y, w, h, n)
  color(C.concrete)
  love.graphics.rectangle("fill", x, y, w, h)
  local CW, CH = 120, 32
  for row = 0, math.floor((h - 30) / (CH + 6)) - 1 do
    local cy = y + 15 + row * (CH + 6)
    for col = 0, math.floor((w - 30) / (CW + 8)) - 1 do
      local k = n * 131 + row * 7 + col * 3
      if hash(k) > 0.15 then
        local cx = x + 15 + col * (CW + 8)
        local c = CONTAINERS[math.floor(hash(k * 1.7) * #CONTAINERS) + 1]
        color(C.shadow)
        love.graphics.rectangle("fill", cx + 6, cy + 6, CW, CH)
        color(c)
        love.graphics.rectangle("fill", cx, cy, CW, CH)
        love.graphics.setColor(c[1] * 0.75, c[2] * 0.75, c[3] * 0.75)
        for rib = cx + 6, cx + CW - 4, 9 do
          love.graphics.line(rib, cy + 2, rib, cy + CH - 2)
        end
      end
    end
  end
end

function Tutorial.yard(map, _camera, left, top, right, bottom, t, _kit)
  blocks(map, left, top, right, bottom, 520, function(x, y, w, h, n)
    if n < 0.65 then
      warehouse(x, y, w, h, n)
    else
      containers(x, y, w, h, n)
    end
  end)
  ringCars(map, t * 0.7)
end

return Tutorial
