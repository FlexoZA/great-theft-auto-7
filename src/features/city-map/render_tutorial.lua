-- Draws the tutorial's maps (tutorial_maps.lua builds them). Shoeman's
-- Road: into the canvas, the grass embankment down both sides
-- with its concrete retaining walls; the pavement in slabs; the four
-- streets in tarmac, dark into their tunnels, with kerbs, edge lines,
-- dashed lane lines, the double yellow down the middle and an arrow on
-- every lane the way it runs; tyre marks, cracks, oil and manholes; "LOOK
-- LEFT" at every kerb; the school yard's beds, trees and benches and
-- Shoeman's board, and the lawn at the top. Over the cars, every frame
-- (`drawAbove`), the embankment over each tunnel and the portal's
-- headwall, so a car drives out of the dark and back into it.
-- Shoeman's Park: mown lawn in stripes inside a clipped hedge; the gravel
-- path up the middle through his paved circle to the iron gate at the
-- top; the chalk ring round the dodging ground with old shoes lying in
-- the grass; the pond, beds, trees, lamps, benches and his board.
-- Shoeman's Scrap Yard: packed dirt with tyre tracks, oil and puddles
-- inside a corrugated fence; the concrete pad and site office in the
-- bottom-left corner; wrecks piled along the fences, the crusher under
-- its crane, lone wrecks and tyre heaps out in the yard, junk lying about,
-- the squirrels' burrows, and the gate in the top fence.

local TutorialMaps = require("src.features.city-map.tutorial_maps")

local RenderTutorial = {}

local C = {
  grass = { 0.36, 0.53, 0.26 },
  grassLight = { 0.44, 0.61, 0.31 },
  grassDark = { 0.29, 0.44, 0.21 },
  slab = { 0.66, 0.65, 0.62 },
  slabDark = { 0.58, 0.57, 0.54 },
  joint = { 0.50, 0.49, 0.47 },
  kerb = { 0.80, 0.79, 0.76 },
  asphalt = { 0.22, 0.22, 0.24 },
  asphaltLight = { 0.27, 0.27, 0.29 },
  line = { 0.92, 0.92, 0.88 },
  yellow = { 0.95, 0.78, 0.22 },
  skid = { 0.08, 0.08, 0.09, 0.55 },
  crack = { 0.12, 0.12, 0.13, 0.8 },
  oil = { 0.06, 0.06, 0.08, 0.45 },
  iron = { 0.30, 0.30, 0.31 },
  ironDark = { 0.18, 0.18, 0.19 },
  concrete = { 0.62, 0.62, 0.60 },
  concreteDark = { 0.45, 0.45, 0.44 },
  concreteLight = { 0.74, 0.74, 0.72 },
  shadow = { 0, 0, 0, 0.3 },
  soil = { 0.36, 0.26, 0.18 },
  leaf = { 0.25, 0.46, 0.22 },
  leafLight = { 0.34, 0.57, 0.28 },
  wood = { 0.52, 0.36, 0.22 },
  woodDark = { 0.38, 0.26, 0.16 },
  chalkboard = { 0.16, 0.24, 0.20 },
  chalk = { 0.92, 0.92, 0.88 },
  flowers = { { 0.92, 0.30, 0.32 }, { 0.98, 0.84, 0.30 }, { 0.70, 0.45, 0.88 }, { 0.98, 0.98, 0.95 } },
  lawn = { 0.38, 0.58, 0.28 },
  lawnStripe = { 0.34, 0.53, 0.25 },
  hedge = { 0.17, 0.33, 0.15 },
  hedgeLight = { 0.23, 0.42, 0.19 },
  gravel = { 0.72, 0.66, 0.54 },
  gravelDark = { 0.60, 0.55, 0.44 },
  gravelEdge = { 0.50, 0.46, 0.37 },
  water = { 0.22, 0.46, 0.66 },
  waterLight = { 0.38, 0.62, 0.82 },
  reed = { 0.40, 0.48, 0.22 },
  lampPost = { 0.14, 0.14, 0.16 },
  lamp = { 1.00, 0.93, 0.70 },
  shoe = { 0.30, 0.20, 0.13 },
  shoeSole = { 0.12, 0.10, 0.09 },
  dirt = { 0.45, 0.39, 0.31 },
  dirtLight = { 0.53, 0.47, 0.38 },
  dirtDark = { 0.36, 0.31, 0.25 },
  track = { 0.30, 0.26, 0.21, 0.55 },
  puddle = { 0.25, 0.30, 0.33, 0.75 },
  sheet = { 0.56, 0.58, 0.58 },
  sheetDark = { 0.42, 0.44, 0.45 },
  rust = { 0.55, 0.30, 0.16 },
  rustDark = { 0.38, 0.20, 0.11 },
  glass = { 0.55, 0.68, 0.74 },
  tyre = { 0.10, 0.10, 0.11 },
  tyreLight = { 0.22, 0.22, 0.23 },
  hazard = { 0.95, 0.75, 0.15 },
  office = { 0.86, 0.84, 0.76 },
  officeRoof = { 0.66, 0.64, 0.58 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local s = math.sin(n * 12.9898) * 43758.5453
  return s - math.floor(s)
end

local fonts = {}
local function font(size)
  fonts[size] = fonts[size] or love.graphics.newFont(size)
  return fonts[size]
end

--- A patch of grass over (x, y, w, h), tufted.
local function grass(x, y, w, h, seed)
  color(C.grass)
  love.graphics.rectangle("fill", x, y, w, h)
  for i = 1, math.floor(w * h / 900) do
    local k = seed + i
    color(hash(k) < 0.5 and C.grassLight or C.grassDark, 0.7)
    love.graphics.rectangle("fill", x + hash(k * 1.3) * (w - 6), y + hash(k * 2.1) * (h - 4), 4 + hash(k * 3.7) * 6, 3)
  end
end

--- The pavement over (x, y, w, h): slabs 32 px square, a few a shade darker.
local function pavement(x, y, w, h)
  color(C.slab)
  love.graphics.rectangle("fill", x, y, w, h)
  local S = 32
  for i = 0, math.ceil(w / S) - 1 do
    for j = 0, math.ceil(h / S) - 1 do
      if hash(x + i * 7.1 + (y + j) * 3.3) < 0.18 then
        color(C.slabDark)
        love.graphics.rectangle("fill", x + i * S, y + j * S, math.min(S, w - i * S), math.min(S, h - j * S))
      end
    end
  end
  color(C.joint)
  love.graphics.setLineWidth(2)
  for i = 1, math.ceil(w / S) - 1 do
    love.graphics.line(x + i * S, y, x + i * S, y + h)
  end
  for j = 1, math.ceil(h / S) - 1 do
    love.graphics.line(x, y + j * S, x + w, y + j * S)
  end
end

--- An arrow painted on a lane at (x, y), pointing `dir` (1 east, -1 west).
local function arrow(x, y, dir)
  color(C.line, 0.85)
  love.graphics.rectangle("fill", x - 30 * dir - (dir < 0 and 36 or 0), y - 4, 36, 8)
  local tip = x + 26 * dir
  love.graphics.polygon("fill", tip, y, tip - 22 * dir, y - 14, tip - 22 * dir, y + 14)
end

--- One street: tarmac across the map, darkening into the tunnels under
--- the verges, its kerbs and markings between them.
local function street(map, s, inL, inR)
  local T = 64
  color(C.asphalt)
  love.graphics.rectangle("fill", map.left, s.y0, map.w, s.y1 - s.y0)
  for i = 0, math.floor((inR - inL) / 24) do
    local k = s.n * 100 + i
    if hash(k) < 0.35 then
      color(C.asphaltLight, 0.6)
      local y = s.y0 + hash(k * 1.7) * (s.y1 - s.y0 - 10)
      love.graphics.rectangle("fill", inL + i * 24, y, 12 + hash(k * 2.9) * 20, 4)
    end
  end
  -- Edge lines, the lane lines, the double yellow.
  local mid = (s.y0 + s.y1) / 2
  color(C.line)
  love.graphics.rectangle("fill", map.left, s.y0 + 6, map.w, 4)
  love.graphics.rectangle("fill", map.left, s.y1 - 10, map.w, 4)
  for x = inL + 8, inR - 40, 64 do
    love.graphics.rectangle("fill", x, s.y0 + T - 2, 32, 4)
    love.graphics.rectangle("fill", x, s.y1 - T - 2, 32, 4)
  end
  color(C.yellow)
  love.graphics.rectangle("fill", map.left, mid - 6, map.w, 3)
  love.graphics.rectangle("fill", map.left, mid + 3, map.w, 3)
  for _, lane in ipairs(map.lanes) do
    if lane.street == s.n then
      for k = 1, 3 do
        arrow(inL + (inR - inL) * (k - 0.5) / 3 + lane.dir * 40 * lane.lane, lane.y, lane.dir)
      end
    end
  end
  -- Into the dark: the road in the tunnel's shade for a car's length in
  -- front of each mouth, black under the verge (the roof hides it, but
  -- not from the big map's eye).
  love.graphics.setColor(0.02, 0.02, 0.03, 0.92)
  love.graphics.rectangle("fill", map.left, s.y0, inL - map.left, s.y1 - s.y0)
  love.graphics.rectangle("fill", inR, s.y0, map.left + map.w - inR, s.y1 - s.y0)
  local steps, shade = 8, 64
  for i = 0, steps - 1 do
    love.graphics.setColor(0.02, 0.02, 0.03, (steps - i) / steps * 0.6)
    love.graphics.rectangle("fill", inL + i * shade / steps, s.y0, shade / steps, s.y1 - s.y0)
    love.graphics.rectangle("fill", inR - (i + 1) * shade / steps, s.y0, shade / steps, s.y1 - s.y0)
  end
  -- The kerbs along the pavement, the gutter's shadow below.
  color(C.kerb)
  love.graphics.rectangle("fill", inL, s.y0 - 6, inR - inL, 6)
  love.graphics.rectangle("fill", inL, s.y1, inR - inL, 6)
  color(C.shadow)
  love.graphics.rectangle("fill", inL, s.y0, inR - inL, 4)
end

local function decor(d)
  if d.kind == "skid" then
    color(C.skid)
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    love.graphics.rectangle("fill", 0, -9, d.len, 5)
    love.graphics.rectangle("fill", 0, 5, d.len * 0.9, 5)
    love.graphics.pop()
  elseif d.kind == "crack" then
    color(C.crack)
    love.graphics.setLineWidth(2)
    local x, y, a = d.x, d.y, d.a
    for i = 1, 5 do
      a = a + (hash(d.seed + i) - 0.5) * 1.2
      local nx, ny = x + math.cos(a) * d.len / 5, y + math.sin(a) * d.len / 5
      love.graphics.line(x, y, nx, ny)
      x, y = nx, ny
    end
  elseif d.kind == "stain" then
    color(C.oil)
    love.graphics.ellipse("fill", d.x, d.y, d.r * 1.4, d.r, 16)
    love.graphics.ellipse("fill", d.x + d.r * 0.8, d.y + d.r * 0.3, d.r * 0.6, d.r * 0.45, 12)
  elseif d.kind == "manhole" then
    color(C.ironDark)
    love.graphics.circle("fill", d.x, d.y, 17, 20)
    color(C.iron)
    love.graphics.circle("fill", d.x, d.y, 14, 20)
    color(C.ironDark)
    love.graphics.setLineWidth(2)
    for k = -2, 2 do
      love.graphics.line(d.x - 12, d.y + k * 5, d.x + 12, d.y + k * 5)
    end
  elseif d.kind == "grate" then
    color(C.ironDark)
    love.graphics.rectangle("fill", d.x - 18, d.y - 6, 36, 12)
    color(C.iron)
    for k = 0, 5 do
      love.graphics.rectangle("fill", d.x - 16 + k * 6, d.y - 4, 3, 8)
    end
  elseif d.kind == "look" then
    color(C.line, 0.9)
    local f = font(22)
    love.graphics.setFont(f)
    love.graphics.printf(d.text, d.x - 200, d.y - 11, 400, "center")
    local w = f:getWidth(d.text)
    arrow(d.x - w / 2 - 40, d.y, -1)
  elseif d.kind == "bed" then
    color(C.concreteDark)
    love.graphics.rectangle("fill", d.x - 6, d.y - 6, d.w + 12, d.h + 12, 6)
    color(C.soil)
    love.graphics.rectangle("fill", d.x, d.y, d.w, d.h, 4)
    grass(d.x + 6, d.y + 6, d.w - 12, d.h - 12, d.seed)
    for i = 1, math.floor(d.w * d.h / 500) do
      local k = d.seed * 3 + i
      color(C.flowers[math.floor(hash(k) * #C.flowers) + 1])
      love.graphics.circle("fill", d.x + 10 + hash(k * 1.9) * (d.w - 20), d.y + 10 + hash(k * 2.7) * (d.h - 20), 3, 6)
    end
  elseif d.kind == "tree" then
    color(C.shadow)
    love.graphics.circle("fill", d.x + 8, d.y + 10, d.r, 20)
    color(C.leaf)
    love.graphics.circle("fill", d.x, d.y, d.r, 20)
    color(C.leafLight)
    love.graphics.circle("fill", d.x - d.r * 0.25, d.y - d.r * 0.25, d.r * 0.6, 16)
  elseif d.kind == "bench" then
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    color(C.shadow)
    love.graphics.rectangle("fill", -10, -26, 30, 60)
    color(C.woodDark)
    love.graphics.rectangle("fill", -14, -30, 8, 60)
    color(C.wood)
    for k = 0, 2 do
      love.graphics.rectangle("fill", -4 + k * 7, -30, 5, 60)
    end
    love.graphics.pop()
  elseif d.kind == "board" then
    color(C.shadow)
    love.graphics.rectangle("fill", d.x + 8, d.y + 8, 220, 70)
    color(C.woodDark)
    love.graphics.rectangle("fill", d.x - 6, d.y - 6, 232, 82)
    color(C.chalkboard)
    love.graphics.rectangle("fill", d.x, d.y, 220, 70)
    color(C.chalk)
    love.graphics.setFont(font(15))
    love.graphics.printf("SHOEMAN'S SCHOOL\nOF SURVIVAL", d.x, d.y + 14, 220, "center")
  elseif d.kind == "lamp" then
    color(C.shadow)
    love.graphics.circle("fill", d.x + 5, d.y + 5, 9, 12)
    color(C.lampPost)
    love.graphics.circle("fill", d.x, d.y, 8, 12)
    color(C.lamp)
    love.graphics.circle("fill", d.x, d.y, 5, 12)
  elseif d.kind == "shoe" then
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    color(C.shadow)
    love.graphics.ellipse("fill", 3, 3, 14, 7, 12)
    color(C.shoeSole)
    love.graphics.ellipse("fill", 0, 0, 14, 7, 12)
    color(C.shoe)
    love.graphics.ellipse("fill", -1, 0, 12, 5.5, 12)
    color(C.shoeSole)
    love.graphics.ellipse("fill", -4, 0, 4, 3, 8)
    love.graphics.pop()
  elseif d.kind == "gate" then
    -- Iron gates, shut, in a gap in the hedge, a post either side (the
    -- hedge row is solid: the EXIT star is the way through).
    local x0, x1 = d.x - d.w / 2, d.x + d.w / 2
    color(C.gravel)
    love.graphics.rectangle("fill", x0, d.y - 64, d.w, 64)
    color(C.lampPost)
    love.graphics.rectangle("fill", x0, d.y - 36, d.w, 5)
    love.graphics.rectangle("fill", x0, d.y - 14, d.w, 4)
    for x = x0 + 8, x1 - 4, 12 do
      love.graphics.rectangle("fill", x, d.y - 44, 3, 36)
    end
    love.graphics.rectangle("fill", d.x - 2, d.y - 46, 4, 40)
    color(C.concreteDark)
    love.graphics.rectangle("fill", x0 - 16, d.y - 70, 16, 76)
    love.graphics.rectangle("fill", x1, d.y - 70, 16, 76)
    color(C.concreteLight)
    love.graphics.rectangle("fill", x0 - 16, d.y - 70, 16, 4)
    love.graphics.rectangle("fill", x1, d.y - 70, 16, 4)
  end
end

--- Shoeman's Road into the canvas.
local function drawRoad(map, T)
  local verge = TutorialMaps.ROAD.verge
  local inL, inR = map.x0 + (map.c0 + verge) * T, map.x0 + (map.c1 + 1 - verge) * T
  -- The embankment everywhere; the pavement over every walked tile.
  grass(map.left, map.top, map.w, map.h, 7)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if map.tiles[c][r] == "walk" then
        pavement(map.x0 + c * T, map.y0 + r * T, T, T)
      end
    end
  end
  for _, s in ipairs(map.streets) do
    street(map, s, inL, inR)
  end
  -- The retaining walls down the pavement's sides, their shadow on it.
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      local here = map.tiles[c][r] == "walk"
      local west = map.tiles[c - 1] and map.tiles[c - 1][r]
      local east = map.tiles[c + 1] and map.tiles[c + 1][r]
      if here and not west then
        local x = map.x0 + c * T
        color(C.shadow)
        love.graphics.rectangle("fill", x, map.y0 + r * T, 10, T)
        color(C.concrete)
        love.graphics.rectangle("fill", x - 10, map.y0 + r * T, 10, T)
        color(C.concreteLight)
        love.graphics.rectangle("fill", x - 10, map.y0 + r * T, 3, T)
      elseif here and not east then
        local x = map.x0 + (c + 1) * T
        color(C.concrete)
        love.graphics.rectangle("fill", x, map.y0 + r * T, 10, T)
        color(C.concreteDark)
        love.graphics.rectangle("fill", x + 7, map.y0 + r * T, 3, T)
      end
    end
  end
  for _, d in ipairs(map.decor) do
    decor(d)
  end
end

--- A tree in the park, its shadow first.
local function tree(t)
  color(C.shadow)
  love.graphics.circle("fill", t.x + 9, t.y + 11, t.r, 20)
  color(C.leaf)
  love.graphics.circle("fill", t.x, t.y, t.r, 20)
  for k = 0, 5 do -- a ragged edge
    local a = k / 6 * math.pi * 2 + t.r
    love.graphics.circle("fill", t.x + math.cos(a) * t.r * 0.7, t.y + math.sin(a) * t.r * 0.7, t.r * 0.45, 12)
  end
  color(C.leafLight)
  love.graphics.circle("fill", t.x - t.r * 0.25, t.y - t.r * 0.25, t.r * 0.55, 16)
end

--- Shoeman's Park into the canvas.
local function drawPark(map, T)
  local P = TutorialMaps.PARK
  -- The hedge everywhere, the lawn inside it in mown stripes.
  color(C.hedge)
  love.graphics.rectangle("fill", map.left, map.top, map.w, map.h)
  for i = 1, math.floor(map.w * map.h / 700) do
    color(C.hedgeLight, 0.8)
    love.graphics.circle("fill", map.left + hash(i * 1.3) * map.w, map.top + hash(i * 2.1) * map.h,
      6 + hash(i * 3.7) * 8, 8)
  end
  local h = P.hedge * T
  local x0, y0, w, hh = map.left + h, map.top + h, map.w - 2 * h, map.h - 2 * h
  color(C.shadow)
  love.graphics.rectangle("fill", x0, y0, w, hh)
  color(C.lawn)
  love.graphics.rectangle("fill", x0 + 6, y0 + 8, w - 6, hh - 8)
  color(C.lawnStripe)
  for i = 0, math.floor(w / (2 * T)) do
    love.graphics.rectangle("fill", x0 + 6 + i * 2 * T, y0 + 8, T, hh - 8)
  end
  for i = 1, math.floor(w * hh / 1400) do
    color(hash(i * 5.1) < 0.5 and C.grassLight or C.grassDark, 0.5)
    love.graphics.rectangle("fill", x0 + hash(i * 1.7) * (w - 6), y0 + hash(i * 2.3) * (hh - 4), 4, 3)
  end
  -- The gravel paths, edged.
  for _, p in ipairs(map.paths) do
    color(C.gravelEdge)
    love.graphics.rectangle("fill", p.x - 4, p.y - 4, p.w + 8, p.h + 8, 6)
  end
  for i, p in ipairs(map.paths) do
    color(C.gravel)
    love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 4)
    for k = 1, math.floor(p.w * p.h / 220) do
      color(C.gravelDark, 0.7)
      love.graphics.rectangle("fill", p.x + hash(i * 1000 + k) * (p.w - 3), p.y + hash(i * 2000 + k * 1.3) * (p.h - 3),
        3, 3)
    end
  end
  -- His circle, paved, edged with a kerb.
  local ring = map.ring
  color(C.kerb)
  love.graphics.circle("fill", ring.x, ring.y, P.plaza + 6, 40)
  color(C.slab)
  love.graphics.circle("fill", ring.x, ring.y, P.plaza, 40)
  color(C.joint)
  love.graphics.setLineWidth(2)
  for k = 1, 2 do
    love.graphics.circle("line", ring.x, ring.y, P.plaza * k / 3, 32)
  end
  for k = 0, 7 do
    local a = k / 8 * math.pi * 2
    love.graphics.line(ring.x + math.cos(a) * P.plaza / 3, ring.y + math.sin(a) * P.plaza / 3,
      ring.x + math.cos(a) * P.plaza, ring.y + math.sin(a) * P.plaza)
  end
  -- The pond.
  local pd = map.pond
  color(C.soil)
  love.graphics.ellipse("fill", pd.x, pd.y, pd.rx + 10, pd.ry + 10, 40)
  color(C.water)
  love.graphics.ellipse("fill", pd.x, pd.y, pd.rx, pd.ry, 40)
  color(C.waterLight, 0.6)
  love.graphics.ellipse("fill", pd.x - pd.rx * 0.25, pd.y - pd.ry * 0.3, pd.rx * 0.45, pd.ry * 0.25, 24)
  color(C.reed)
  for k = 1, 30 do
    local a = hash(k * 4.3) * math.pi * 2
    local rx, ry = pd.rx + 4 + hash(k * 7.7) * 10, pd.ry + 4 + hash(k * 7.7) * 10
    love.graphics.rectangle("fill", pd.x + math.cos(a) * rx - 2, pd.y + math.sin(a) * ry - 6, 3, 12)
  end
  for _, d in ipairs(map.decor) do
    if d.kind == "chalk" then
      -- The dodging ground: a chalk ring on the grass, in dashes.
      color(C.chalk, 0.75)
      love.graphics.setLineWidth(6)
      local n = 72
      for k = 0, n - 1, 2 do
        local a0, a1 = k / n * math.pi * 2, (k + 1) / n * math.pi * 2
        love.graphics.line(ring.x + math.cos(a0) * ring.r, ring.y + math.sin(a0) * ring.r,
          ring.x + math.cos(a1) * ring.r, ring.y + math.sin(a1) * ring.r)
      end
    else
      decor(d)
    end
  end
  for _, t in ipairs(map.trees) do
    tree(t)
  end
end

--- A wrecked car, centred on (0, 0) and lying along x, `w` long and `h`
--- wide: dented paint, a smashed windscreen, a door or the bonnet gone,
--- rust; `burnt` ones black through.
local function carWreck(w, h, c, seed, burnt)
  color(C.shadow)
  love.graphics.rectangle("fill", -w / 2 + 5, -h / 2 + 6, w, h, 6)
  if burnt then
    love.graphics.setColor(0.16, 0.14, 0.13)
  else
    color(c)
  end
  love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 6)
  -- The cabin: roof between the windscreens.
  love.graphics.setColor(0, 0, 0, 0.25)
  love.graphics.rectangle("fill", -w * 0.18, -h / 2 + 3, w * 0.42, h - 6, 4)
  color(burnt and C.ironDark or C.glass, 0.9)
  love.graphics.polygon("fill", w * 0.24, -h / 2 + 4, w * 0.32, -h / 2 + 6, w * 0.32, h / 2 - 6, w * 0.24, h / 2 - 4)
  love.graphics.rectangle("fill", -w * 0.26, -h / 2 + 5, w * 0.07, h - 10)
  -- Cracks across the screen, rust patches, a dent.
  color(C.chalk, 0.7)
  love.graphics.setLineWidth(1)
  love.graphics.line(w * 0.25, -h * 0.2, w * 0.31, h * 0.1, w * 0.26, h * 0.3)
  for k = 1, 3 do
    color(hash(seed + k) < 0.5 and C.rust or C.rustDark, burnt and 0.5 or 0.85)
    love.graphics.circle("fill", (hash(seed * 1.7 + k) - 0.5) * w * 0.8, (hash(seed * 2.3 + k) - 0.5) * h * 0.7,
      3 + hash(seed + k * 3.1) * 5, 8)
  end
  if hash(seed * 4.1) < 0.5 then -- no bonnet: the engine bay
    color(C.ironDark)
    love.graphics.rectangle("fill", w * 0.33, -h / 2 + 5, w * 0.14, h - 10, 2)
    color(C.iron)
    love.graphics.rectangle("fill", w * 0.36, -h * 0.2, w * 0.07, h * 0.4)
  end
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("line", -w / 2, -h / 2, w, h, 6)
end

--- A lone wreck in the yard.
local function wreck(k)
  love.graphics.push()
  love.graphics.translate(k.x, k.y)
  love.graphics.rotate(k.a + (k.w < k.h and math.pi / 2 or 0) + (k.flip and math.pi or 0))
  local long, wide = math.max(k.w, k.h), math.min(k.w, k.h)
  carWreck(long, wide, k.color, k.seed, k.burnt)
  love.graphics.pop()
end

--- Wrecks piled along a fence: each car in the row on top of the ones
--- under it, a shade lighter the higher it sits.
local function pile(p)
  color(C.shadow)
  love.graphics.rectangle("fill", p.x + 8, p.y + 10, p.w, p.h)
  local across = p.along == "x" and p.h or p.w
  local step = (p.along == "x" and p.w or p.h) / math.max(1, #p.cars)
  for _, car in ipairs(p.cars) do
    for level = 1, car.tall do
      love.graphics.push()
      local o = car.k * step + step / 2 + car.jx * level
      local q = across / 2 + car.jy * level - (level - 1) * 3
      if p.along == "x" then
        love.graphics.translate(p.x + o, p.y + q)
      else
        love.graphics.translate(p.x + q, p.y + o)
        love.graphics.rotate(math.pi / 2)
      end
      love.graphics.rotate((hash(p.seed + car.k * 7 + level) - 0.5) * 0.25)
      carWreck(step - 6, across - 10, car.color, p.seed + car.k * 13 + level, false)
      love.graphics.setColor(1, 1, 1, 0.07 * (level - 1))
      love.graphics.rectangle("fill", -(step - 6) / 2, -(across - 10) / 2, step - 6, across - 10, 6)
      love.graphics.pop()
    end
  end
end

--- A heap of tyres.
local function tyres(t)
  color(C.shadow)
  love.graphics.circle("fill", t.x + 6, t.y + 8, 26, 16)
  for k = 0, 4 do
    local a = hash(t.seed + k) * math.pi * 2
    local r = k == 4 and 0 or 12
    local x, y = t.x + math.cos(a) * r, t.y + math.sin(a) * r
    color(C.tyre)
    love.graphics.circle("fill", x, y, 13, 16)
    color(C.tyreLight)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", x, y, 10, 16)
    color(C.dirtDark)
    love.graphics.circle("fill", x, y, 5, 10)
  end
end

local function yardDecor(d)
  if d.kind == "track" then
    color(C.track)
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    love.graphics.rectangle("fill", 0, -14, d.len, 7)
    love.graphics.rectangle("fill", 0, 7, d.len, 7)
    love.graphics.pop()
  elseif d.kind == "puddle" then
    color(C.puddle)
    love.graphics.ellipse("fill", d.x, d.y, d.r * 1.6, d.r, 16)
    color(C.glass, 0.35)
    love.graphics.ellipse("fill", d.x - d.r * 0.4, d.y - d.r * 0.3, d.r * 0.5, d.r * 0.2, 10)
  elseif d.kind == "drum" then
    color(C.shadow)
    love.graphics.circle("fill", d.x + 4, d.y + 5, 13, 14)
    color(hash(d.seed) < 0.5 and C.rust or { 0.20, 0.36, 0.55 })
    love.graphics.circle("fill", d.x, d.y, 13, 14)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", d.x, d.y, 9, 14)
  elseif d.kind == "part" then -- an engine block
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    color(C.ironDark)
    love.graphics.rectangle("fill", -14, -10, 28, 20, 3)
    color(C.iron)
    for k = 0, 3 do
      love.graphics.circle("fill", -9 + k * 6, 0, 2.5, 6)
    end
    love.graphics.pop()
  elseif d.kind == "door" then
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    color(TutorialMaps.WRECK_COLORS[math.floor(hash(d.seed) * #TutorialMaps.WRECK_COLORS) + 1])
    love.graphics.rectangle("fill", -18, -8, 36, 16, 3)
    color(C.glass, 0.8)
    love.graphics.rectangle("fill", -14, -6, 14, 12, 2)
    color(C.rust, 0.8)
    love.graphics.circle("fill", 8, 3, 4, 8)
    love.graphics.pop()
  elseif d.kind == "wheel" then
    color(C.tyre)
    love.graphics.circle("fill", d.x, d.y, 11, 14)
    color(C.iron)
    love.graphics.circle("fill", d.x, d.y, 5, 10)
  elseif d.kind == "sign" then
    color(C.lampPost)
    love.graphics.rectangle("fill", d.x + 4, d.y + 50, 6, 30)
    love.graphics.rectangle("fill", d.x + 150, d.y + 50, 6, 30)
    color(C.hazard)
    love.graphics.rectangle("fill", d.x, d.y, 160, 54)
    color(C.ironDark)
    love.graphics.setFont(font(14))
    love.graphics.printf("SHOEMAN'S SCRAP\nNO REFUNDS", d.x, d.y + 9, 160, "center")
  else
    decor(d)
  end
end

--- The site office: a portacabin with a door and a window to the yard.
local function office(o)
  color(C.shadow)
  love.graphics.rectangle("fill", o.x + 10, o.y + 12, o.w, o.h)
  color(C.office)
  love.graphics.rectangle("fill", o.x, o.y, o.w, o.h)
  color(C.officeRoof)
  for k = 0, math.floor(o.h / 16) - 1 do
    love.graphics.rectangle("fill", o.x + 4, o.y + 4 + k * 16, o.w - 8, 10)
  end
  color(C.hazard)
  love.graphics.rectangle("fill", o.x, o.y + o.h - 8, o.w, 8)
  color(C.ironDark)
  for k = 0, math.floor(o.w / 16) - 1, 2 do
    love.graphics.rectangle("fill", o.x + k * 16, o.y + o.h - 8, 8, 8)
  end
  color(C.woodDark)
  love.graphics.rectangle("fill", o.x + o.w - 14, o.y + 40, 14, 40)
end

--- The crusher, its press open, and the crane's arm over it.
local function crusher(c)
  color(C.shadow)
  love.graphics.rectangle("fill", c.x + 12, c.y + 14, c.w, c.h)
  color(C.concreteDark)
  love.graphics.rectangle("fill", c.x, c.y, c.w, c.h)
  color(C.ironDark)
  love.graphics.rectangle("fill", c.x + 16, c.y + 16, c.w - 32, c.h - 32)
  color(C.hazard)
  love.graphics.rectangle("fill", c.x, c.y, c.w, 12)
  love.graphics.rectangle("fill", c.x, c.y + c.h - 12, c.w, 12)
  color(C.ironDark)
  for x = c.x, c.x + c.w - 12, 24 do
    love.graphics.polygon("fill", x, c.y, x + 12, c.y, x + 4, c.y + 12, x - 8, c.y + 12)
    love.graphics.polygon("fill", x, c.y + c.h - 12, x + 12, c.y + c.h - 12, x + 4, c.y + c.h, x - 8, c.y + c.h)
  end
  -- A cube of crushed car in the press.
  love.graphics.push()
  love.graphics.translate(c.x + c.w * 0.4, c.y + c.h / 2)
  carWreck(c.w * 0.45, c.h * 0.35, TutorialMaps.WRECK_COLORS[2], 77, false)
  love.graphics.pop()
  -- The crane: its cab beside the press, the arm across it, the magnet.
  local bx, by = c.x + c.w + 50, c.y + c.h + 40
  local mx, my = c.x + c.w / 2, c.y + c.h / 2
  color(C.shadow)
  love.graphics.setLineWidth(14)
  love.graphics.line(bx + 14, by + 18, mx + 14, my + 18)
  color(C.hazard)
  love.graphics.line(bx, by, mx, my)
  color(C.ironDark)
  love.graphics.setLineWidth(2)
  for k = 1, 9 do
    local t0, t1 = (k - 1) / 9, k / 9
    love.graphics.line(bx + (mx - bx) * t0, by + (my - by) * t0 - 6, bx + (mx - bx) * t1, by + (my - by) * t1 + 6)
  end
  color(C.ironDark)
  love.graphics.circle("fill", mx, my, 20, 20)
  color(C.iron)
  love.graphics.circle("fill", mx, my, 14, 20)
  color(C.hazard)
  love.graphics.rectangle("fill", bx - 22, by - 18, 44, 36, 4)
  color(C.glass)
  love.graphics.rectangle("fill", bx - 14, by - 12, 18, 14, 2)
end

--- A squirrel burrow: a mound of turned dirt with a dark hole and nut shells.
local function den(dn)
  color(C.dirtDark)
  love.graphics.ellipse("fill", dn.x, dn.y, 46, 34, 20)
  color(C.dirtLight)
  love.graphics.ellipse("fill", dn.x - 6, dn.y - 6, 36, 24, 20)
  love.graphics.setColor(0.08, 0.06, 0.05)
  love.graphics.ellipse("fill", dn.x + 4, dn.y + 2, 16, 11, 14)
  color(C.wood)
  for k = 1, 6 do
    local a = hash(dn.x + k * 3.3) * math.pi * 2
    love.graphics.circle("fill", dn.x + math.cos(a) * 52, dn.y + math.sin(a) * 40, 3, 6)
  end
end

--- The gate in the top fence: two chain-link leaves, shut, between posts.
local function gate(g)
  local x0, x1 = g.x - g.w / 2, g.x + g.w / 2
  color(C.dirt)
  love.graphics.rectangle("fill", x0, g.y - 64, g.w, 64)
  color(C.lampPost)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", x0 + 4, g.y - 40, g.w / 2 - 6, 28)
  love.graphics.rectangle("line", g.x + 2, g.y - 40, g.w / 2 - 6, 28)
  color(C.iron, 0.8)
  love.graphics.setLineWidth(1)
  for x = x0 + 8, x1 - 8, 8 do
    love.graphics.line(x, g.y - 40, x + 8, g.y - 12)
    love.graphics.line(x + 8, g.y - 40, x, g.y - 12)
  end
  color(C.hazard)
  love.graphics.rectangle("fill", x0 - 16, g.y - 72, 16, 78)
  love.graphics.rectangle("fill", x1, g.y - 72, 16, 78)
  color(C.ironDark)
  for k = 0, 3 do
    love.graphics.rectangle("fill", x0 - 16, g.y - 66 + k * 20, 16, 8)
    love.graphics.rectangle("fill", x1, g.y - 66 + k * 20, 16, 8)
  end
end

--- Shoeman's Scrap Yard into the canvas.
local function drawYard(map, T)
  local F = TutorialMaps.YARD.fence * T
  -- The yard inside the fence: packed dirt, speckled.
  local x0, y0, w, h = map.left + F, map.top + F, map.w - 2 * F, map.h - 2 * F
  color(C.dirt)
  love.graphics.rectangle("fill", x0, y0, w, h)
  for i = 1, math.floor(w * h / 600) do
    color(hash(i * 1.9) < 0.5 and C.dirtLight or C.dirtDark, 0.6)
    love.graphics.rectangle("fill", x0 + hash(i * 1.3) * (w - 6), y0 + hash(i * 2.7) * (h - 4), 3 + hash(i * 4.1) * 5,
      3)
  end
  -- The pad, slabs of concrete with a hazard stripe at its edge.
  local p = map.pad
  color(C.concrete)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h)
  color(C.concreteDark)
  love.graphics.setLineWidth(2)
  for x = p.x + 128, p.x + p.w - 1, 128 do
    love.graphics.line(x, p.y, x, p.y + p.h)
  end
  for y = p.y + 128, p.y + p.h - 1, 128 do
    love.graphics.line(p.x, y, p.x + p.w, y)
  end
  color(C.hazard)
  love.graphics.rectangle("fill", p.x, p.y - 10, p.w, 10)
  love.graphics.rectangle("fill", p.x + p.w, p.y - 10, 10, p.h + 10)
  color(C.ironDark)
  for x = p.x, p.x + p.w - 8, 20 do
    love.graphics.rectangle("fill", x, p.y - 10, 10, 10)
  end
  for y = p.y, p.y + p.h - 8, 20 do
    love.graphics.rectangle("fill", p.x + p.w, y, 10, 10)
  end
  for _, d in ipairs(map.decor) do
    if d.kind == "track" or d.kind == "stain" or d.kind == "puddle" then
      yardDecor(d)
    end
  end
  -- The fence all round, over the ends of any tyre tracks: corrugated
  -- sheets, some rusted through; its shadow on the dirt.
  for i, s in ipairs({ { map.left, map.top, map.w, F }, { map.left, y0 + h, map.w, F }, { map.left, y0, F, h },
    { x0 + w, y0, F, h } }) do
    color(C.sheet)
    love.graphics.rectangle("fill", s[1], s[2], s[3], s[4])
    color(C.sheetDark)
    if s[3] > s[4] then
      for x = s[1], s[1] + s[3] - 5, 12 do
        love.graphics.rectangle("fill", x, s[2], 5, s[4])
      end
    else
      for y = s[2], s[2] + s[4] - 5, 12 do
        love.graphics.rectangle("fill", s[1], y, s[3], 5)
      end
    end
    for k = 1, 15 do
      color(C.rust, 0.55)
      love.graphics.circle("fill", s[1] + hash(i * 50 + k * 3.1) * s[3], s[2] + hash(i * 50 + k * 5.3) * s[4],
        5 + hash(i * 50 + k * 7.7) * 12, 10)
    end
  end
  color(C.shadow)
  love.graphics.rectangle("fill", x0, y0, w, 10)
  love.graphics.rectangle("fill", x0, y0, 10, h)
  gate(map.gate)
  for _, dn in ipairs(map.dens) do
    den(dn)
  end
  for _, d in ipairs(map.decor) do
    if not (d.kind == "track" or d.kind == "stain" or d.kind == "puddle") then
      yardDecor(d)
    end
  end
  for _, t in ipairs(map.tyres) do
    tyres(t)
  end
  for _, k in ipairs(map.wrecks) do
    wreck(k)
  end
  for _, s in ipairs(map.piles) do
    pile(s)
  end
  office(map.office)
  crusher(map.crusher)
end

local DRAW = { ["tutorial-road"] = drawRoad, ["tutorial-park"] = drawPark, ["tutorial-yard"] = drawYard }

--- Into the map's canvas (render.lua's Render.build), in world px.
function RenderTutorial.draw(map, T)
  local before = love.graphics.getFont()
  DRAW[map.kind](map, T)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(before)
end

--- Over the cars, every frame: the embankment over each tunnel and the
--- portal on its mouth, a concrete headwall across the road with a wing
--- wall slanting back into the bank at either end.
function RenderTutorial.drawAbove(map)
  for i, t in ipairs(map.tunnels) do
    grass(t.x, t.y - 8, t.w, t.h + 16, 50 + i)
    local out = t.side == "w" and 1 or -1 -- towards the road
    local face = t.side == "w" and t.x + t.w or t.x -- the mouth's edge
    local W = 22 -- the headwall's thickness
    local x = face - (out > 0 and W or 0)
    color(C.concreteDark)
    for _, y in ipairs({ t.y - 20, t.y + t.h + 20 }) do
      local dy = y < t.y and -1 or 1
      love.graphics.polygon("fill", face, y, face - out * 54, y + dy * 40, face - out * 54 - out * 12,
        y + dy * 32, face - out * 12, y - dy * 8)
    end
    color(C.shadow)
    love.graphics.rectangle("fill", out > 0 and face or face - 12, t.y - 20, 12, t.h + 40)
    color(C.concrete)
    love.graphics.rectangle("fill", x, t.y - 22, W, t.h + 44)
    color(C.concreteLight)
    love.graphics.rectangle("fill", x, t.y - 22, W, 5)
    love.graphics.rectangle("fill", out > 0 and x + W - 4 or x, t.y - 22, 4, t.h + 44)
    color(C.concreteDark)
    love.graphics.rectangle("fill", x, t.y + t.h + 17, W, 5)
    for k = 1, 3 do -- joints between the headwall's panels
      love.graphics.rectangle("fill", x, t.y - 22 + k * (t.h + 44) / 4, W, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return RenderTutorial
