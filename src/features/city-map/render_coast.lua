-- Draws the Coast (coast.lua builds it) into the map canvas: the sea, light
-- in the shallows and deep blue further out with waves on it; the sand,
-- wet and dark at the water's edge with foam washing up on it, dry and
-- pale up the beach, the headland's rocks; the mountains, shaded by how
-- high they stand (lit from the north west, a contour line every so often,
-- grass at their foot, forest up their sides and over the ridges) with
-- boulders tumbled along their foot; then the cover on the sand and the
-- trees on the slopes.

local RenderCoast = {}

local C = {
  deep = { 0.07, 0.24, 0.42 },
  shallow = { 0.20, 0.58, 0.64 },
  wave = { 0.55, 0.80, 0.86 },
  foam = { 0.93, 0.97, 1.00 },
  wetSand = { 0.62, 0.55, 0.42 },
  sand = { 0.86, 0.78, 0.58 },
  sandLight = { 0.92, 0.86, 0.68 },
  sandDark = { 0.76, 0.68, 0.50 },
  shell = { 0.96, 0.92, 0.86 },
  stone = { 0.52, 0.50, 0.46 },
  stoneDark = { 0.38, 0.37, 0.34 },
  stoneLight = { 0.64, 0.62, 0.58 },
  foot = { 0.42, 0.56, 0.28 }, -- grass at the mountains' foot
  slope = { 0.24, 0.45, 0.20 },
  high = { 0.17, 0.34, 0.17 },
  peak = { 0.30, 0.48, 0.24 }, -- the tops, lighter, catching the light
  ridge = { 0.47, 0.49, 0.43 }, -- bare rock showing through up top
  canopy = { 0.16, 0.38, 0.16 },
  canopyLight = { 0.26, 0.52, 0.22 },
  pine = { 0.10, 0.28, 0.15 },
  pineLight = { 0.16, 0.38, 0.20 },
  wood = { 0.55, 0.43, 0.30 },
  woodDark = { 0.38, 0.29, 0.20 },
  woodLight = { 0.68, 0.56, 0.42 },
  hull = { 0.62, 0.30, 0.22 },
  hullDark = { 0.40, 0.20, 0.16 },
  deck = { 0.60, 0.50, 0.36 },
  rust = { 0.48, 0.28, 0.16 },
  shadow = { 0, 0, 0, 0.28 },
}

local SUB = 4 -- cells a tile is drawn in, each way

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function mix(a, b, k)
  k = math.max(0, math.min(1, k))
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local function scale(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

--- A field ([c][r], nil where it doesn't reach) sampled smoothly: the
--- value at tile corner (c, r) is the mean of the four tiles round it,
--- nothing counting as 0.
local function corners(field, cols, rows)
  local out = {}
  for c = 0, cols do
    out[c] = {}
    for r = 0, rows do
      local sum = 0
      for _, k in ipairs({ { -1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 0 } }) do
        local col = field[c + k[1]]
        sum = sum + (col and col[r + k[2]] or 0)
      end
      out[c][r] = sum / 4
    end
  end
  return out
end

--- Each cell of tile (c, r): `paint(x, y, size, v, gx, gy, i, j)` with the
--- field `k`'s value there and its slope, eased between the corners.
local function cells(map, T, k, c, r, paint)
  local s = T / SUB
  local a, b, d, e = k[c][r], k[c + 1][r], k[c][r + 1], k[c + 1][r + 1]
  local gx, gy = (b - a + e - d) / 2, (d - a + e - b) / 2
  local x0, y0 = map.x0 + c * T, map.y0 + r * T
  for i = 0, SUB - 1 do
    for j = 0, SUB - 1 do
      local u, v = (i + 0.5) / SUB, (j + 0.5) / SUB
      local top, bottom = a + (b - a) * u, d + (e - d) * u
      paint(x0 + i * s, y0 + j * s, s, top + (bottom - top) * v, gx, gy, i, j)
    end
  end
end

local function drawSea(map, T, depth)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.depth[c][r] then
        cells(map, T, depth, c, r, function(x, y, s, v)
          color(mix(C.shallow, C.deep, (v - 0.4) / 4.5))
          love.graphics.rectangle("fill", x, y, s, s)
        end)
      end
    end
  end
  -- Waves: short light streaks, thicker in close, rolling in from the west.
  color(C.wave, 0.5)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      local d = map.depth[c][r]
      if d and hash(c * 7.1 + r * 3.9) < 0.55 then
        local x = map.x0 + c * T + hash(c + r * 1.7) * T * 0.6
        local y = map.y0 + r * T + hash(c * 2.3 + r) * T
        local len = 18 + hash(c * r + 1.3) * 26
        love.graphics.rectangle("fill", x, y, 3, len * (d < 2 and 1.3 or 1))
      end
    end
  end
end

--- How wet the sand is at each tile corner: the mean of the sand round it,
--- the sea counting as 0, the mountains not at all.
local function wetness(map)
  local out = {}
  for c = 0, map.cols do
    out[c] = {}
    for r = 0, map.rows do
      local sum, n = 0, 0
      for _, k in ipairs({ { -1, -1 }, { 0, -1 }, { -1, 0 }, { 0, 0 } }) do
        local cc, rr = c + k[1], r + k[2]
        local wet = map.wet[cc] and map.wet[cc][rr]
        if wet then
          sum, n = sum + wet, n + 1
        elseif map.depth[cc] and map.depth[cc][rr] then
          n = n + 1
        end
      end
      out[c][r] = n > 0 and sum / n or 3
    end
  end
  return out
end

local function drawSand(map, T)
  local wetCorners = wetness(map)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      local wet = map.wet[c][r]
      if wet then
        local x, y = map.x0 + c * T, map.y0 + r * T
        cells(map, T, wetCorners, c, r, function(cx, cy, size, w)
          color(mix(C.wetSand, C.sand, (w - 0.5) / 1.5))
          love.graphics.rectangle("fill", cx, cy, size, size)
        end)
        -- Ripples and speckle; on the headland, stones.
        for i = 0, 5 do
          local h = hash(c * 13.1 + r * 7.7 + i)
          local px, py = x + hash(h * 91) * T, y + hash(h * 57) * T
          if map.rocky[c][r] then
            local s = 8 + hash(h * 33) * 16
            color(C.stoneDark)
            love.graphics.ellipse("fill", px + 2, py + 2, s, s * 0.75)
            color(i % 2 == 0 and C.stone or C.stoneLight)
            love.graphics.ellipse("fill", px, py, s, s * 0.75)
          else
            color(i % 3 == 0 and C.sandLight or C.sandDark, 0.7)
            love.graphics.rectangle("fill", px, py, 6, 2)
          end
        end
        if not map.rocky[c][r] and hash(c * 5.5 + r * 2.1) < 0.12 then
          color(C.shell)
          love.graphics.circle("fill", x + hash(c + r) * T, y + hash(r * 3 + c) * T, 2.5)
        end
      end
    end
  end
end

--- Foam along every edge between sand and sea, scalloped where the waves break.
local function drawFoam(map, T)
  local function sea(c, r)
    return map.depth[c] and map.depth[c][r] ~= nil
  end
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.wet[c][r] then
        local x, y = map.x0 + c * T, map.y0 + r * T
        for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          if sea(c + e[1], r + e[2]) then
            for k = 0, 3 do
              local t = (k + 0.5) / 4
              local fx = e[1] == 0 and x + t * T or (e[1] < 0 and x or x + T)
              local fy = e[2] == 0 and y + t * T or (e[2] < 0 and y or y + T)
              local rad = 9 + hash(c * 3.1 + r * 5.3 + k) * 8
              color(C.foam, 0.55)
              love.graphics.circle("fill", fx, fy, rad + 5)
              color(C.foam, 0.9)
              love.graphics.circle("fill", fx, fy, rad)
            end
          end
        end
      end
    end
  end
end

--- Smooth noise over tile corners, -1..1: a lattice every `every` tiles, eased between.
local function noise(c, r, every, seed)
  local i, j = math.floor(c / every), math.floor(r / every)
  local u, v = c / every - i, r / every - j
  u, v = u * u * (3 - 2 * u), v * v * (3 - 2 * v)
  local function at(a, b)
    return hash(a * 12.9898 + b * 78.233 + seed) * 2 - 1
  end
  local top = at(i, j) + (at(i + 1, j) - at(i, j)) * u
  local bottom = at(i, j + 1) + (at(i + 1, j + 1) - at(i, j + 1)) * u
  return top + (bottom - top) * v
end

--- How high each tile corner stands, 0 at the beach: rising fast off the
--- sand and levelling out, ridges and peaks worked in by noise. And how
--- lit each corner is, from the north west.
local function relief(map)
  local mean = corners(map.height, map.cols, map.rows)
  local elev, lit = {}, {}
  for c = 0, map.cols do
    elev[c] = {}
    for r = 0, map.rows do
      local h = mean[c][r]
      local rise = 1 - math.exp(-h / 2.5) -- 0 at the foot, nearly 1 a few tiles in
      local ridges = noise(c, r, 7, 3.1) * 0.65 + noise(c, r, 3, 8.7) * 0.35
      elev[c][r] = h <= 0 and 0 or rise * (5 + ridges * 3) + math.min(h, 4) * 0.25
    end
  end
  for c = 0, map.cols do
    lit[c] = {}
    for r = 0, map.rows do
      local l = elev[math.max(0, c - 1)][math.max(0, r - 1)]
      local h = elev[math.min(map.cols, c + 1)][math.min(map.rows, r + 1)]
      lit[c][r] = math.max(0.62, math.min(1.3, 1 + (l - h) * 0.32))
    end
  end
  return elev, lit
end

local function drawMountains(map, T)
  local elev, lit = relief(map)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.height[c][r] then
        cells(map, T, elev, c, r, function(x, y, s, e, _, _, i, j)
          local u, v = (i + 0.5) / SUB, (j + 0.5) / SUB
          local lt = lit[c][r] + (lit[c + 1][r] - lit[c][r]) * u
          local lb = lit[c][r + 1] + (lit[c + 1][r + 1] - lit[c][r + 1]) * u
          local l = lt + (lb - lt) * v
          local base
          if e < 1 then
            base = mix(C.foot, C.slope, e)
          elseif e < 5 then
            base = mix(C.slope, C.high, (e - 1) / 4)
          else
            base = mix(C.high, C.peak, (e - 5) / 3)
          end
          if e > 6.2 and hash(x * 0.013 + y * 0.029) < 0.25 then
            base = mix(base, C.ridge, 0.6) -- rock showing through on the tops
          end
          color(scale(base, l * (0.97 + hash(x * 0.37 + y * 0.11) * 0.06)))
          love.graphics.rectangle("fill", x, y, s, s)
          -- A contour line where the height crosses a whole step.
          if e > 1.2 and (e * 1.4) % 1 < 0.09 then
            color(scale(base, l * 0.8), 0.7)
            love.graphics.rectangle("fill", x, y, s, s)
          end
        end)
      end
    end
  end
  -- Boulders tumbled along the foot, hiding the tile edges.
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.height[c][r] then
        local x, y = map.x0 + c * T, map.y0 + r * T
        for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          local col = map.wet[c + e[1]]
          if col and col[r + e[2]] then
            for k = 0, 2 do
              local t = (k + 0.2 + hash(c * 1.9 + r * 4.1 + k) * 0.6) / 3
              local bx = e[1] == 0 and x + t * T or (e[1] < 0 and x + 6 or x + T - 6)
              local by = e[2] == 0 and y + t * T or (e[2] < 0 and y + 6 or y + T - 6)
              local rad = 10 + hash(c * 7.3 + r * 2.9 + k) * 12
              color(C.shadow)
              love.graphics.ellipse("fill", bx + e[1] * 4 + 3, by + e[2] * 4 + 4, rad, rad * 0.8)
              color(C.stoneDark)
              love.graphics.ellipse("fill", bx, by, rad, rad * 0.8)
              color(k % 2 == 0 and C.stone or C.ridge)
              love.graphics.ellipse("fill", bx - 2, by - 2, rad * 0.8, rad * 0.62)
            end
          end
        end
      end
    end
  end
end

local function drawRock(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.shadow)
  love.graphics.ellipse("fill", cx + 6, cy + 8, s.w / 2 + 2, s.h / 2 + 2)
  color(C.stoneDark)
  love.graphics.ellipse("fill", cx, cy, s.w / 2 + 2, s.h / 2 + 2)
  color(C.stone)
  love.graphics.ellipse("fill", cx - 3, cy - 3, s.w / 2 - 2, s.h / 2 - 3)
  color(C.stoneLight)
  love.graphics.ellipse("fill", cx - s.w * 0.15, cy - s.h * 0.18, s.w * 0.2, s.h * 0.14)
  color(C.foot, 0.8) -- a little weed in the cracks
  love.graphics.circle("fill", cx + s.w * 0.22 * (hash(s.seed) - 0.5), cy + s.h * 0.3, 4)
end

local function drawLog(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 6, s.w, s.h, 10, 10)
  color(C.woodDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 10, 10)
  color(C.wood)
  love.graphics.rectangle("fill", s.x + 3, s.y + 3, s.w - 6, s.h - 6, 8, 8)
  color(C.woodLight)
  local along = s.w > s.h
  for k = 1, 3 do
    local t = k / 4 + (hash(s.seed + k) - 0.5) * 0.1
    if along then
      love.graphics.rectangle("fill", s.x + s.w * t, s.y + 5, 14, 2)
    else
      love.graphics.rectangle("fill", s.x + 5, s.y + s.h * t, 2, 14)
    end
  end
  color(C.woodDark) -- its sawn ends
  if along then
    love.graphics.circle("line", s.x + 7, s.y + s.h / 2, 6)
  else
    love.graphics.circle("line", s.x + s.w / 2, s.y + 7, 6)
  end
end

--- The boat on the sand: a fishing boat's hull, bow to the east, listing,
--- its deck planked and its wheelhouse caved in.
local function drawBoat(s)
  local x, y, w, h = s.x, s.y, s.w, s.h
  local hull = { x, y + h * 0.15, x + w * 0.72, y, x + w, y + h / 2, x + w * 0.72, y + h, x, y + h * 0.85 }
  love.graphics.push()
  love.graphics.translate(8, 10)
  color(C.shadow)
  love.graphics.polygon("fill", hull)
  love.graphics.pop()
  color(C.hullDark)
  love.graphics.polygon("fill", hull)
  color(C.hull)
  love.graphics.polygon("fill", x + 6, y + h * 0.2, x + w * 0.7, y + 6, x + w - 10, y + h / 2,
    x + w * 0.7, y + h - 6, x + 6, y + h * 0.8)
  color(C.deck)
  love.graphics.polygon("fill", x + 14, y + h * 0.26, x + w * 0.68, y + 14, x + w - 24, y + h / 2,
    x + w * 0.68, y + h - 14, x + 14, y + h * 0.74)
  color(C.woodDark, 0.6)
  for k = 1, 5 do
    local py = y + 14 + k * (h - 28) / 6
    love.graphics.line(x + 16, py, x + w * 0.7, py)
  end
  color(C.rust) -- holes rusted through
  love.graphics.circle("fill", x + w * 0.3, y + h * 0.7, 9)
  love.graphics.circle("fill", x + w * 0.55, y + h * 0.3, 6)
  -- The wheelhouse, its roof fallen in.
  color(C.woodDark)
  love.graphics.rectangle("fill", x + w * 0.2, y + h * 0.3, w * 0.22, h * 0.4)
  color(C.wood)
  love.graphics.polygon("fill", x + w * 0.2 + 4, y + h * 0.3 + 4, x + w * 0.42 - 4, y + h * 0.3 + 4,
    x + w * 0.36, y + h * 0.62, x + w * 0.2 + 4, y + h * 0.7 - 4)
end

local function drawCrate(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 6, s.w, s.h)
  color(C.woodDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.wood)
  love.graphics.rectangle("fill", s.x + 4, s.y + 4, s.w - 8, s.h - 8)
  color(C.woodDark)
  love.graphics.setLineWidth(3)
  love.graphics.line(s.x + 4, s.y + 4, s.x + s.w - 4, s.y + s.h - 4)
  love.graphics.setLineWidth(1)
end

local function drawSlopeTree(t)
  color(C.shadow)
  love.graphics.circle("fill", t.x + t.r * 0.35, t.y + t.r * 0.45, t.r)
  if t.pine then
    color(C.pine)
    love.graphics.circle("fill", t.x, t.y, t.r)
    color(C.pineLight)
    love.graphics.circle("fill", t.x - t.r * 0.2, t.y - t.r * 0.2, t.r * 0.55)
    color(C.pine)
    love.graphics.circle("fill", t.x - t.r * 0.25, t.y - t.r * 0.25, t.r * 0.2)
  else
    color(C.canopy)
    love.graphics.circle("fill", t.x, t.y, t.r)
    color(C.canopyLight)
    love.graphics.circle("fill", t.x - t.r * 0.3, t.y - t.r * 0.3, t.r * 0.5)
  end
end

--- Draw the whole map. `T` is the tile size.
function RenderCoast.draw(map, T)
  local depth = corners(map.depth, map.cols, map.rows)
  drawSea(map, T, depth)
  drawSand(map, T)
  drawFoam(map, T)
  drawMountains(map, T)
  for _, s in ipairs(map.cover) do
    if s.kind == "rock" then
      drawRock(s)
    elseif s.kind == "log" then
      drawLog(s)
    elseif s.kind == "boat" then
      drawBoat(s)
    elseif s.kind == "crate" then
      drawCrate(s)
    end
  end
  for _, t in ipairs(map.slopes) do
    drawSlopeTree(t)
  end
  love.graphics.setColor(1, 1, 1)
end

return RenderCoast
