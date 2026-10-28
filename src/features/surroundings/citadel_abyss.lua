-- The Citadel past its edges (surroundings' entry for `citadel`): the shaft
-- the catwalk climbs is only one part of the Citadel's inside, and the
-- drop runs on all round it, as the map's own drop is drawn (city-map's
-- render_citadel.lua, its `map.backdrop`): a dark abyss with haze drifting
-- in it and lights far below, girders crossing it, pillars rising out of
-- the dark with lights on their tops, and the map's pod rails running on
-- out of both its sides. Further out more rails cross it, pods gliding
-- along them, and other platforms hang lit in the dark, catwalk rails
-- round them and struts down from under them, too far off to reach.
-- Things further down are darker, fading into the void.
--
-- Everything is worked out from the cell it sits in, the same on every
-- machine and never running out, and drawn each frame over what the
-- camera sees, skipping cells inside the map (its canvas lands on top).

local CitadelAbyss = {}

local T = 64 -- px, a tile of the map: what pillars and platforms are sized in
local CELL = 640 -- px; lights, pillars and haze are placed per cell
local PLATFORM_CELL = 1400 -- px; a far platform at most per one of these
local LANE = 900 -- px between the lanes a girder or an outer rail may run along
local SEGMENT = 2400 -- px; a lane's girder comes and goes in stretches this long

-- render_citadel.lua's colours.
local C = {
  void = { 0.035, 0.045, 0.06 }, haze = { 0.10, 0.16, 0.22 }, steel = { 0.16, 0.19, 0.23 },
  steelLight = { 0.24, 0.28, 0.33 }, glow = { 0.40, 0.80, 1.00 }, warm = { 1.00, 0.55, 0.20 },
  grate = { 0.27, 0.30, 0.34 }, grateDark = { 0.19, 0.21, 0.25 }, plate = { 0.31, 0.34, 0.38 },
  rail = { 0.55, 0.60, 0.66 }, crate = { 0.33, 0.37, 0.41 },
}

local function hash(n)
  local v = math.sin(n * 1.913 + 0.71) * 43758.5453
  return v - math.floor(v)
end

--- Colour `c` seen `depth` down (0 at the catwalks, 1 lost in the dark), with alpha `a`.
local function deep(c, depth, a)
  local k = math.max(0, math.min(1, depth))
  love.graphics.setColor(c[1] + (C.void[1] - c[1]) * k, c[2] + (C.void[2] - c[2]) * k, c[3] + (C.void[3] - c[3]) * k,
    a or 1)
end

--- Is the box (x, y, w, h) wholly inside the map, under its canvas?
local function covered(map, x, y, w, h)
  return x >= map.left and y >= map.top and x + w <= map.left + map.w and y + h <= map.top + map.h
end

--- Every cell of `size` px in the box (left, top, right, bottom) not
--- wholly inside the map: `fn(x, y, h, i, j)`, `h` its hash.
local function cells(map, size, salt, left, top, right, bottom, fn)
  for i = math.floor(left / size), math.floor(right / size) do
    for j = math.floor(top / size), math.floor(bottom / size) do
      local x, y = i * size, j * size
      if not covered(map, x, y, size, size) then
        fn(x, y, hash(i * 7.31 + j * 3.17 + salt), i, j)
      end
    end
  end
end

-- What hangs in the drop ---------------------------------------------------------

--- A girder from (x, y), `w` by `h`, a lattice down its length.
local function girder(x, y, w, h, depth)
  deep(C.steel, depth)
  love.graphics.rectangle("fill", x, y, w, h)
  deep(C.steelLight, depth)
  love.graphics.setLineWidth(3)
  local across = w > h
  local thick = across and h or w
  love.graphics.rectangle("fill", x, y, across and w or 3, across and 3 or h)
  for k = across and x or y, (across and x + w or y + h) - thick, thick * 1.2 do
    if across then
      love.graphics.line(k, y + h, k + h, y)
    else
      love.graphics.line(x, k + w, x + w, k)
    end
  end
  love.graphics.setLineWidth(1)
end

--- Girders right across the drop, along lanes both ways, in stretches.
local function girders(map, left, top, right, bottom)
  for axis = 1, 2 do
    local lo, hi = axis == 1 and top or left, axis == 1 and bottom or right
    local from, to = axis == 1 and left or top, axis == 1 and right or bottom
    for lane = math.floor(lo / LANE) - 1, math.floor(hi / LANE) + 1 do
      local h = hash(lane * 5.7 + axis * 91)
      if h < 0.55 then
        local at = lane * LANE + hash(lane * 2.3 + axis) * LANE * 0.6
        local thick = 22 + hash(lane * 3.9 + axis) * 26
        local depth = 0.3 + hash(lane * 8.1 + axis) * 0.35
        for s = math.floor(from / SEGMENT), math.floor(to / SEGMENT) do
          local k = hash(s * 1.37 + lane * 4.1 + axis * 13)
          if k < 0.6 then
            local a = s * SEGMENT + k * 300
            local len = SEGMENT * (0.5 + hash(s * 6.1 + lane) * 0.5)
            if axis == 1 and not covered(map, a, at, len, thick) then
              girder(a, at, len, thick, depth)
            elseif axis == 2 and not covered(map, at, a, thick, len) then
              girder(at, a, thick, len, depth)
            end
          end
        end
      end
    end
  end
end

--- A pillar rising out of the dark, lit along its top and left, a light
--- or two on its top.
local function pillar(x, y, w, h, depth, seed)
  deep(C.steel, depth)
  love.graphics.rectangle("fill", x, y, w, h)
  deep(C.steelLight, depth)
  love.graphics.rectangle("fill", x, y, w, 6)
  love.graphics.rectangle("fill", x, y, 6, h)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x + w - 10, y, 10, h)
  for i = 1, 1 + math.floor(hash(seed) * 3) do
    local lit = hash(seed + i * 3.1) < 0.3 and C.warm or C.glow
    love.graphics.setColor(lit[1], lit[2], lit[3], 0.7 * (1 - depth * 0.6))
    love.graphics.circle("fill", x + w * hash(seed + i), y + h * hash(seed + i * 7.3), 4)
  end
end

--- A platform hanging far off in the dark: a deck of plates, its grating,
--- a rail round it, struts down from under it, lights along its edges and
--- something standing on it.
local function platform(x, y, w, h, depth, seed, t)
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", x + 40, y + 60, w, h)
  deep(C.steel, depth + 0.1)
  for k = 0, 2 do -- struts down into the dark
    local sx = x + w * (0.2 + k * 0.3)
    love.graphics.polygon("fill", sx, y + h, sx + 18, y + h, sx + 64, y + h + 90, sx + 46, y + h + 90)
  end
  deep(C.grateDark, depth)
  love.graphics.rectangle("fill", x, y, w, h)
  deep(C.plate, depth)
  love.graphics.rectangle("fill", x + 6, y + 6, w - 12, h - 12)
  deep(C.grate, depth)
  for gx = x + 32, x + w - 16, 32 do
    love.graphics.rectangle("fill", gx, y + 6, 2, h - 12)
  end
  deep(C.rail, depth)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x + 2, y + 2, w - 4, h - 4)
  love.graphics.setLineWidth(1)
  if hash(seed + 5) < 0.6 then -- crates
    deep(C.crate, depth)
    love.graphics.rectangle("fill", x + w * 0.2, y + h * 0.3, 44, 44, 3)
    love.graphics.rectangle("fill", x + w * 0.2 + 50, y + h * 0.3 + 10, 36, 36, 3)
  end
  -- A bank of screens against the far rail, glowing.
  local sx = x + w * (0.45 + hash(seed + 6) * 0.3)
  deep(C.steel, depth)
  love.graphics.rectangle("fill", sx, y + 10, 90, 22, 3)
  love.graphics.setColor(C.glow[1], C.glow[2], C.glow[3], 0.55 * (1 - depth * 0.5))
  for k = 0, 2 do
    love.graphics.rectangle("fill", sx + 6 + k * 28, y + 14, 22, 12, 2)
  end
  -- Lights along its edges, the warm ones flickering with work going on.
  local warm = hash(seed + 9) < 0.3
  local lit = warm and C.warm or C.glow
  for k = 0, 5 do
    local along = (k + 0.5) / 6
    local px, py = x + w * along, k % 2 == 0 and y or y + h
    local a = (0.55 + 0.25 * math.sin(t * (warm and 7 or 1.3) + seed + k)) * (1 - depth * 0.5)
    love.graphics.setColor(lit[1], lit[2], lit[3], a * 0.2)
    love.graphics.circle("fill", px, py, 30)
    love.graphics.setColor(lit[1], lit[2], lit[3], a)
    love.graphics.circle("fill", px, py, 4)
  end
end

--- A pod riding a rail, nose along `ang`.
local function pod(x, y, ang, depth)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(ang)
  deep(C.crate, depth)
  love.graphics.rectangle("fill", -44, -26, 88, 52, 8)
  deep(C.steelLight, depth - 0.1)
  love.graphics.rectangle("fill", -44, -26, 88, 8, 4)
  love.graphics.setColor(C.warm[1], C.warm[2], C.warm[3], 0.6)
  love.graphics.rectangle("fill", -30, -6, 60, 12, 4)
  love.graphics.pop()
end

--- A rail from (x0, y0) to (x1, y1): a beam with a glowing line along it.
local function rail(x0, y0, x1, y1)
  deep(C.steelLight, 0.35)
  love.graphics.setLineWidth(8)
  love.graphics.line(x0, y0, x1, y1)
  love.graphics.setColor(C.glow[1], C.glow[2], C.glow[3], 0.25)
  love.graphics.setLineWidth(2)
  love.graphics.line(x0, y0, x1, y1)
  love.graphics.setLineWidth(1)
end

--- The map's own pod rails, on out of both its sides as far as the camera
--- sees, still pods parked along them here and there.
local function mapRails(map, left, right)
  for _, b in ipairs(map.backdrop or {}) do
    if b.kind == "rail" then
      local slope = (b.y1 - b.y0) / (b.x1 - b.x0)
      local ang = math.atan(slope)
      for side = -1, 1, 2 do
        local from = side < 0 and math.min(left, b.x0) or b.x1
        local to = side < 0 and b.x0 or math.max(right, b.x1)
        if to > from then
          local ox, oy = side < 0 and b.x0 or b.x1, side < 0 and b.y0 or b.y1
          rail(from, oy + (from - ox) * slope, to, oy + (to - ox) * slope)
          for k = math.floor(from / 700), math.floor(to / 700) do
            local x = k * 700 + hash(k * 2.9 + b.y0) * 300
            if hash(k * 4.3 + b.y0) < 0.35 and x > from and x < to then
              pod(x, oy + (x - ox) * slope, ang, 0.3)
            end
          end
        end
      end
    end
  end
end

--- Rails further out, right across the drop above and below the map (east
--- to west) and either side of it (north to south), pods gliding along them.
local function outerRails(map, left, top, right, bottom, t)
  for axis = 1, 2 do
    local lo, hi = axis == 1 and top or left, axis == 1 and bottom or right
    local from, to = axis == 1 and left or top, axis == 1 and right or bottom
    local m0 = axis == 1 and map.top or map.left
    local m1 = axis == 1 and map.top + map.h or map.left + map.w
    for lane = math.floor(lo / LANE), math.floor(hi / LANE) do
      local at = lane * LANE + LANE * 0.5
      local h = hash(lane * 9.3 + axis * 41)
      if h < 0.45 and (at < m0 - 200 or at > m1 + 200) then
        local dir = hash(lane * 1.9 + axis) < 0.5 and -1 or 1
        local speed = (60 + hash(lane * 6.7 + axis) * 80) * dir
        local gap = 900 + hash(lane * 3.3 + axis) * 900
        if axis == 1 then
          rail(from, at, to, at)
        else
          rail(at, from, at, to)
        end
        local shift = (t * speed) % gap
        for k = math.floor((from - shift) / gap) - 1, math.floor((to - shift) / gap) + 1 do
          if hash(k * 2.7 + lane) < 0.7 then
            local p = k * gap + shift
            if axis == 1 then
              pod(p, at, dir < 0 and math.pi or 0, 0.3)
            else
              pod(at, p, dir < 0 and -math.pi / 2 or math.pi / 2, 0.3)
            end
          end
        end
      end
    end
  end
end

--- Draw it all over the box (left, top, right, bottom) the camera sees.
function CitadelAbyss.draw(map, left, top, right, bottom, t)
  love.graphics.setColor(C.void)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  -- Haze drifting in great slow patches, and lights far below.
  cells(map, CELL, 1, left - 700, top - 700, right + 700, bottom + 700, function(x, y, h)
    if h < 0.5 then
      love.graphics.setColor(C.haze[1], C.haze[2], C.haze[3], 0.12)
      love.graphics.circle("fill", x + hash(h * 3) * CELL, y + hash(h * 5) * CELL, 300 + hash(h * 7) * 400, 40)
    end
  end)
  cells(map, CELL / 2, 2, left - 20, top - 20, right + 20, bottom + 20, function(x, y, h)
    for k = 1, h < 0.7 and 1 or 0 do -- about as many as the map's own drop has
      local warm = hash(h * 11 + k) < 0.2
      local lit = warm and C.warm or C.glow
      local lx, ly = x + hash(h * 13 + k) * CELL / 2, y + hash(h * 17 + k) * CELL / 2
      local r = 2 + hash(h * 19 + k) * 4
      love.graphics.setColor(lit[1], lit[2], lit[3], 0.18)
      love.graphics.circle("fill", lx, ly, r * 3)
      love.graphics.setColor(lit[1], lit[2], lit[3], 0.6)
      love.graphics.circle("fill", lx, ly, r)
    end
  end)
  girders(map, left, top, right, bottom)
  cells(map, CELL, 3, left - CELL, top - CELL, right, bottom, function(x, y, h)
    if h < 0.3 then
      local w, ph = (1.5 + hash(h * 23) * 3) * T, (1.5 + hash(h * 29) * 3) * T
      local px, py = x + hash(h * 31) * (CELL - w), y + hash(h * 37) * (CELL - ph)
      pillar(px, py, w, ph, 0.5 + hash(h * 41) * 0.4, h * 1000)
    end
  end)
  -- Far platforms, lit, in among it all: never right up against the map.
  cells(map, PLATFORM_CELL, 4, left - PLATFORM_CELL, top - PLATFORM_CELL, right, bottom, function(x, y, h)
    if h < 0.5 then
      local w, ph = (4 + hash(h * 43) * 5) * T, (2 + hash(h * 47) * 3) * T
      local px = x + 100 + hash(h * 53) * (PLATFORM_CELL - w - 200)
      local py = y + 100 + hash(h * 59) * (PLATFORM_CELL - ph - 200)
      local near = px + w > map.left - 300 and px < map.left + map.w + 300 and py + ph > map.top - 300
        and py < map.top + map.h + 300
      if not near then
        platform(px, py, w, ph, 0.2 + hash(h * 61) * 0.35, h * 997, t)
      end
    end
  end)
  outerRails(map, left, top, right, bottom, t)
  mapRails(map, left, right)
end

return CitadelAbyss
