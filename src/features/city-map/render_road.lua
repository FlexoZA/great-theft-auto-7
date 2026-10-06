-- Draws the Winding Road (road.lua builds it) into the map canvas: grass
-- over everything open, pebbles along the river's banks; the river, pale
-- in the shallows and dark down the middle, streaked the way it runs; the
-- gravel verge, the tarmac with its edge lines and the dashed line down
-- the middle; the bridges' decks and railings over the water; then the
-- mountains, shaded as the Coast's are (render_coast.lua) with boulders
-- along their foot, bare rock and snow on the tops further north, and the
-- trees on their sides.

local RenderCoast = require("src.features.city-map.render_coast")
local Road = require("src.features.city-map.road")

local RenderRoad = {}

local corners, cells, relief = RenderCoast.corners, RenderCoast.cells, RenderCoast.relief
local hash, mix = RenderCoast.hash, RenderCoast.mix

local C = {
  grass = { 0.40, 0.56, 0.27 },
  grassLight = { 0.48, 0.64, 0.32 },
  grassDark = { 0.32, 0.47, 0.22 },
  flower = { 0.92, 0.88, 0.55 },
  pebble = { 0.62, 0.60, 0.55 },
  pebbleDark = { 0.46, 0.45, 0.41 },
  shallow = { 0.26, 0.56, 0.62 },
  deep = { 0.10, 0.30, 0.42 },
  flow = { 0.70, 0.88, 0.92 },
  foam = { 0.92, 0.96, 1.00 },
  gravel = { 0.56, 0.52, 0.45 },
  gravelDark = { 0.44, 0.41, 0.36 },
  asphalt = { 0.24, 0.24, 0.26 },
  asphaltLight = { 0.30, 0.30, 0.32 },
  edge = { 0.88, 0.88, 0.84 },
  centre = { 0.92, 0.78, 0.28 },
  deck = { 0.58, 0.57, 0.55 },
  deckDark = { 0.44, 0.43, 0.42 },
  rail = { 0.78, 0.78, 0.76 },
  railDark = { 0.40, 0.40, 0.40 },
  foot = { 0.40, 0.54, 0.27 },
  slope = { 0.24, 0.43, 0.21 },
  high = { 0.18, 0.33, 0.18 },
  peak = { 0.30, 0.44, 0.25 },
  rock = { 0.50, 0.49, 0.46 },
  snow = { 0.93, 0.95, 0.98 },
  stone = { 0.52, 0.50, 0.46 },
  stoneDark = { 0.38, 0.37, 0.34 },
  shadow = { 0, 0, 0, 0.28 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function scale(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function open(map, c, r)
  local col = map.tiles[c]
  return col and col[r] ~= nil and col[r] ~= "water"
end

local function isWater(map, c, r)
  return map.depth[c] and map.depth[c][r] ~= nil
end

--- Grass over everything open, in patches; a flower here and there.
local function drawGround(map, T)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if open(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        color(C.grass)
        love.graphics.rectangle("fill", x, y, T, T)
        for i = 0, 5 do
          local h = hash(c * 13.1 + r * 7.7 + i)
          color(i % 2 == 0 and C.grassLight or C.grassDark, 0.6)
          love.graphics.circle("fill", x + hash(h * 91) * T, y + hash(h * 57) * T, 6 + hash(h * 33) * 10)
        end
        if hash(c * 5.5 + r * 2.1) < 0.1 then
          color(C.flower)
          love.graphics.circle("fill", x + hash(c + r) * T, y + hash(r * 3 + c) * T, 2.5)
        end
      end
    end
  end
end

--- A thick line through `pts` ({ x, y }), every `every`th of them.
local function band(pts, width, every)
  local flat = {}
  for i = 1, #pts, every do
    flat[#flat + 1], flat[#flat + 2] = pts[i].x, pts[i].y
  end
  local last = pts[#pts]
  flat[#flat + 1], flat[#flat + 2] = last.x, last.y
  love.graphics.setLineWidth(width)
  love.graphics.line(flat)
  for i = 1, #flat, 2 do -- round the joins, so a tight bend has no notch in it
    love.graphics.circle("fill", flat[i], flat[i + 1], width / 2)
  end
end

--- `pts` moved `off` px to the left of the way they run.
local function offset(pts, off)
  local out = {}
  for i = 1, #pts do
    local a, b = pts[math.max(1, i - 1)], pts[math.min(#pts, i + 1)]
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    if len > 0 then
      out[#out + 1] = { x = pts[i].x + dy / len * off, y = pts[i].y - dx / len * off }
    end
  end
  return out
end

--- The river: shallow at the banks, dark down the middle, pebbles along
--- its edges, streaks of current running the way it flows.
local function drawRiver(map, T)
  local depth = corners(map.depth, map.cols, map.rows)
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.depth[c][r] then
        cells(map, T, depth, c, r, function(x, y, s, v)
          color(mix(C.shallow, C.deep, (v - 0.4) / 1.6))
          love.graphics.rectangle("fill", x, y, s, s)
        end)
      end
    end
  end
  -- Pebbles where the water meets the bank, a little foam where it meets rock.
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.depth[c][r] then
        local x, y = map.x0 + c * T, map.y0 + r * T
        for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          local nc, nr = c + e[1], r + e[2]
          if not isWater(map, nc, nr) and nc >= 0 and nc < map.cols and nr >= 0 and nr < map.rows then
            local bank = open(map, nc, nr)
            for k = 0, 3 do
              local t = (k + 0.2 + hash(c * 3.1 + r * 5.3 + k) * 0.6) / 4
              local fx = e[1] == 0 and x + t * T or (e[1] < 0 and x or x + T)
              local fy = e[2] == 0 and y + t * T or (e[2] < 0 and y or y + T)
              local rad = 6 + hash(c * 7.3 + r * 2.9 + k) * 7
              if bank then
                color(C.pebbleDark)
                love.graphics.ellipse("fill", fx + 1, fy + 2, rad + 2, rad * 0.8 + 2)
                color(k % 2 == 0 and C.pebble or C.stone)
                love.graphics.ellipse("fill", fx, fy, rad, rad * 0.8)
              else
                color(C.foam, 0.45)
                love.graphics.circle("fill", fx, fy, rad + 3)
              end
            end
          end
        end
      end
    end
  end
  -- The current: short streaks along the river's line, across its width.
  local river = map.river
  for i = 2, #river - 1, 3 do
    local p, a, b = river[i], river[i - 1], river[i + 1]
    local dx, dy = b.x - a.x, b.y - a.y
    local len = math.sqrt(dx * dx + dy * dy)
    dx, dy = dx / len, dy / len
    local across = (hash(i * 1.37) * 2 - 1) * p.half * 0.75
    local x, y = p.x - dy * across, p.y + dx * across
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    local l2 = 14 + hash(i * 2.11) * 22
    if isWater(map, c, r) then
      color(C.flow, 0.35 + hash(i * 0.7) * 0.25)
      love.graphics.setLineWidth(3)
      love.graphics.line(x, y, x + dx * l2, y + dy * l2)
    end
  end
end

--- The gravel verge, under the river so its banks cut it off at the bridges.
local function drawVerge(map, T)
  local path = map.path
  local half = Road.ASPHALT * T
  love.graphics.setLineJoin("bevel")
  color(C.gravelDark)
  band(path, half * 2 + 44, 2)
  color(C.gravel)
  band(path, half * 2 + 30, 2)
end

--- The tarmac, its edge lines and the dashed line down the middle.
local function drawTarmac(map, T)
  local path = map.path
  local half = Road.ASPHALT * T
  color(C.asphalt)
  band(path, half * 2, 1)
  -- Wear down the lanes, where the wheels go.
  color(C.asphaltLight, 0.5)
  for _, side in ipairs({ -1, 1 }) do
    band(offset(path, side * half * 0.5), 22, 2)
  end
  -- The edge lines.
  color(C.edge)
  for _, side in ipairs({ -1, 1 }) do
    local line = offset(path, side * (half - 8))
    local flat = {}
    for i = 1, #line do
      flat[#flat + 1], flat[#flat + 2] = line[i].x, line[i].y
    end
    love.graphics.setLineWidth(4)
    love.graphics.line(flat)
  end
  -- The dashed line down the middle: 40 px on, 40 off.
  color(C.centre)
  love.graphics.setLineWidth(4)
  local run, on = 0, true
  for i = 2, #path do
    local a, b = path[i - 1], path[i]
    local d = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    if on then
      love.graphics.line(a.x, a.y, b.x, b.y)
    end
    run = run + d
    if run >= 40 then
      run, on = run - 40, not on
    end
  end
  love.graphics.setLineWidth(1)
end

--- A bridge's deck over the water, its shadow on the water downstream and
--- the piers holding it up showing under its edges.
local function drawDeck(b)
  color(C.shadow)
  love.graphics.rectangle("fill", b.x + 10, b.y + 14, b.w, b.h)
  color(C.deckDark)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(C.deck)
  love.graphics.rectangle("fill", b.x + 4, b.y + 4, b.w - 8, b.h - 8)
  -- Joints across the deck, every so often along the way it runs.
  color(C.deckDark)
  if b.along == "ew" then
    for x = b.x + 48, b.x + b.w - 20, 64 do
      love.graphics.rectangle("fill", x, b.y + 4, 3, b.h - 8)
    end
  else
    for y = b.y + 48, b.y + b.h - 20, 64 do
      love.graphics.rectangle("fill", b.x + 4, y, b.w - 8, 3)
    end
  end
end

--- A railing: a steel rail on posts.
local function drawRail(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 3, s.y + 4, s.w, s.h)
  color(C.railDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.rail)
  love.graphics.rectangle("fill", s.x + 1, s.y + 1, s.w - 2, s.h - 3)
  color(C.railDark)
  if s.w > s.h then
    for x = s.x + 6, s.x + s.w - 6, 32 do
      love.graphics.rectangle("fill", x, s.y - 1, 5, s.h + 2)
    end
  else
    for y = s.y + 6, s.y + s.h - 6, 32 do
      love.graphics.rectangle("fill", s.x - 1, y, s.w + 2, 5)
    end
  end
end

--- The mountains: the Coast's relief, bare rock and then snow on the tops
--- coming lower the further north they stand.
local function drawMountains(map, T)
  local elev, lit = relief(map)
  local SUB = 4
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.height[c][r] then
        local north = 1 - r / map.rows
        local snowline = 10.6 - north * 4.6 -- how high the snow starts: only the tops, and only up north
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
          local bare = snowline - 1.4 -- the trees give out to rock below the snow
          if e > bare then
            base = mix(base, C.rock, (e - bare) / 1.4 * (0.7 + hash(x * 0.013 + y * 0.029) * 0.3))
          end
          if e > snowline then
            base = mix(C.rock, C.snow, math.min(1, (e - snowline) * 1.6))
          end
          color(scale(base, l * (0.97 + hash(x * 0.37 + y * 0.11) * 0.06)))
          love.graphics.rectangle("fill", x, y, s, s)
          if e > 1.2 and e < snowline and (e * 1.4) % 1 < 0.09 then -- a contour line, under the snow
            color(scale(base, l * 0.8), 0.7)
            love.graphics.rectangle("fill", x, y, s, s)
          end
        end)
      end
    end
  end
  -- Boulders tumbled along the foot, hiding the tile edges, by the road and the river alike.
  for c = 0, map.cols - 1 do
    for r = 0, map.rows - 1 do
      if map.height[c][r] then
        local x, y = map.x0 + c * T, map.y0 + r * T
        for _, e in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
          local col = map.tiles[c + e[1]]
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
              color(k % 2 == 0 and C.stone or C.rock)
              love.graphics.ellipse("fill", bx - 2, by - 2, rad * 0.8, rad * 0.62)
            end
          end
        end
      end
    end
  end
end

--- Draw the whole map. `T` is the tile size.
function RenderRoad.draw(map, T)
  drawGround(map, T)
  drawVerge(map, T)
  drawRiver(map, T)
  for _, b in ipairs(map.bridges) do
    drawDeck(b)
  end
  drawTarmac(map, T)
  for _, s in ipairs(map.cover) do
    if s.kind == "rail" then
      drawRail(s)
    end
  end
  drawMountains(map, T)
  for _, t in ipairs(map.slopes) do
    RenderCoast.drawSlopeTree(t)
    if t.pine and t.y < map.y0 + map.rows * T * 0.35 then -- snow on the pines up north
      color(C.snow, 0.8)
      love.graphics.circle("fill", t.x - t.r * 0.25, t.y - t.r * 0.3, t.r * 0.35)
    end
  end
  love.graphics.setLineJoin("miter")
  love.graphics.setColor(1, 1, 1)
end

return RenderRoad
