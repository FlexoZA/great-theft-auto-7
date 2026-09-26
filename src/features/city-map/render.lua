-- Draws the whole city once into a half-resolution canvas, shown at 2x with
-- nearest filtering for a chunky pixel look. One draw call per frame.

local Layout = require("src.features.city-map.layout")

local Render = {}

local C = {
  asphalt = { 0.17, 0.17, 0.19 },
  lane = { 0.85, 0.72, 0.30 },
  edge = { 0.80, 0.80, 0.78 },
  walk = { 0.52, 0.52, 0.55 },
  walkLine = { 0.46, 0.46, 0.49 },
  kerb = { 0.66, 0.66, 0.68 },
  grass = { 0.30, 0.50, 0.26 },
  grassDark = { 0.25, 0.42, 0.22 },
  canopy = { 0.16, 0.36, 0.16 },
  canopyLight = { 0.28, 0.52, 0.24 },
  lot = { 0.22, 0.22, 0.24 },
  bay = { 0.75, 0.75, 0.72 },
  ground = { 0.36, 0.46, 0.27 }, -- open field
  groundDark = { 0.31, 0.40, 0.23 },
  dirt = { 0.45, 0.37, 0.27 },
  dirtDark = { 0.39, 0.32, 0.23 },
  stake = { 0.85, 0.80, 0.70 },
  shadow = { 0, 0, 0, 0.35 },
  ac = { 0.60, 0.62, 0.64 },
  forestFloor = { 0.20, 0.32, 0.17 },
  moss = { 0.17, 0.28, 0.15 },
  trail = { 0.42, 0.33, 0.22 },
  trailDark = { 0.35, 0.27, 0.18 },
  clearing = { 0.30, 0.44, 0.22 },
  shrub = { 0.18, 0.40, 0.18 },
  shrubLight = { 0.26, 0.50, 0.22 },
  berry = { 0.70, 0.12, 0.20 },
  pine = { 0.10, 0.27, 0.16 },
  pineLight = { 0.16, 0.36, 0.20 },
}

local function color(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

local function shade(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function drawRoads(map)
  local T = Layout.TILE
  local P = Layout.PERIOD
  -- Tarmac and sidewalk, tile by tile: the city need not be a rectangle.
  -- Open ground gets a worn patch here and there so driving reads as moving.
  local forest = map.kind == "forest"
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      local kind = col and col[r]
      if kind == "ground" then
        color(forest and C.forestFloor or C.ground)
        love.graphics.rectangle("fill", map.x0 + c * T, map.y0 + r * T, T, T)
        if (c * 31 + r * 17) % 5 == 0 then
          color(forest and C.moss or C.groundDark)
          love.graphics.rectangle("fill", map.x0 + c * T + (c * 7) % 24, map.y0 + r * T + (r * 11) % 24, 36, 28)
        end
      elseif kind then
        color(kind == "road" and C.asphalt or C.walk)
        love.graphics.rectangle("fill", map.x0 + c * T, map.y0 + r * T, T, T)
      end
    end
  end
  -- Paving lines and kerbs around each block.
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + (b.tx - 1) * T, map.y0 + (b.ty - 1) * T
    local w, h = 8 * T, 8 * T
    color(C.walkLine)
    love.graphics.setLineWidth(2)
    for i = 1, 7 do
      love.graphics.line(x + i * T, y, x + i * T, y + h)
      love.graphics.line(x, y + i * T, x + w, y + i * T)
    end
    color(C.kerb)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", x, y, w, h)
  end

  -- Lane centrelines: dashed between the two lanes of each road, skipping
  -- the crossroads.
  color(C.lane)
  love.graphics.setLineWidth(4)
  local function road(c, r)
    return map.tiles[c] and map.tiles[c][r] == "road"
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if road(c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if c % P == 1 and r % P >= 2 and road(c - 1, r) then
          love.graphics.line(x, y + 12, x, y + T - 12)
        end
        if r % P == 1 and c % P >= 2 and road(c, r - 1) then
          love.graphics.line(x + 12, y, x + T - 12, y)
        end
      end
    end
  end

  -- Zebra crossings where each block edge meets a road.
  color(C.edge)
  love.graphics.setLineWidth(1)
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + (b.tx - 1) * T, map.y0 + (b.ty - 1) * T
    local w, h = 8 * T, 8 * T
    local cx, cy = x + w / 2, y + h / 2
    for i = -3, 3 do
      love.graphics.rectangle("fill", cx + i * 24 - 6, y - 2 * T + 10, 12, 2 * T - 20)
      love.graphics.rectangle("fill", cx + i * 24 - 6, y + h + 10, 12, 2 * T - 20)
      love.graphics.rectangle("fill", x - 2 * T + 10, cy + i * 24 - 6, 2 * T - 20, 12)
      love.graphics.rectangle("fill", x + w + 10, cy + i * 24 - 6, 2 * T - 20, 12)
    end
  end
end

local function drawParksAndLots(map)
  local T = Layout.TILE
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + b.tx * T, map.y0 + b.ty * T
    local w, h = b.tw * T, b.th * T
    if b.kind == "park" then
      color(C.grass)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.grassDark)
      for i = 0, 5 do
        love.graphics.rectangle("fill", x + (i * 97) % (w - 40), y + (i * 61) % (h - 30), 40, 30)
      end
    elseif b.kind == "lot" then
      color(C.lot)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.bay)
      love.graphics.setLineWidth(3)
      for i = 0, 7 do
        love.graphics.line(x + 20 + i * 48, y + 16, x + 20 + i * 48, y + 90)
        love.graphics.line(x + 20 + i * 48, y + h - 16, x + 20 + i * 48, y + h - 90)
      end
      love.graphics.line(x + 20, y + 16, x + 20 + 7 * 48, y + 16)
      love.graphics.line(x + 20, y + h - 16, x + 20 + 7 * 48, y + h - 16)
    elseif b.kind == "plot" then
      -- Cleared ground waiting for a builder: packed dirt, a few worn
      -- patches and survey stakes at every other tile corner.
      color(C.dirt)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.dirtDark)
      for i = 0, 4 do
        love.graphics.rectangle("fill", x + 20 + (i * 83) % (w - 80), y + 24 + (i * 131) % (h - 70), 60, 36)
      end
      color(C.stake)
      for i = 0, b.tw, 2 do
        for j = 0, b.th, 2 do
          love.graphics.rectangle("fill", x + i * T - 3, y + j * T - 3, 6, 6)
        end
      end
    end
  end
end

local function drawBuildings(map)
  -- Shadows first so they never fall on a neighbouring roof.
  color(C.shadow)
  for _, b in ipairs(map.buildings) do
    love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
  end
  for _, b in ipairs(map.buildings) do
    color(shade(b.color, 0.55))
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
    color(b.color)
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12)
    -- lit edge top-left
    color(shade(b.color, 1.25))
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, 8)
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, 8, b.h - 12)
    -- roof furniture, placed by the building's own seed
    local s = b.seed
    if b.style == 1 then
      color(C.ac)
      for i = 0, 2 do
        local ax = b.x + 30 + ((s * 7 + i * 53) % math.max(1, b.w - 70))
        local ay = b.y + 30 + ((s * 11 + i * 37) % math.max(1, b.h - 70))
        love.graphics.rectangle("fill", ax, ay, 22, 22)
        color(shade(C.ac, 0.6))
        love.graphics.rectangle("fill", ax + 4, ay + 4, 14, 14)
        color(C.ac)
      end
    elseif b.style == 2 then
      color(shade(b.color, 0.75))
      love.graphics.rectangle("fill", b.x + 24, b.y + 24, b.w - 48, b.h - 48)
      color(shade(b.color, 1.1))
      love.graphics.rectangle("fill", b.x + 34, b.y + 34, b.w - 68, b.h - 68)
    else
      color(shade(b.color, 0.7))
      for i = 1, 3 do
        love.graphics.rectangle("fill", b.x + 20, b.y + i * (b.h / 4) - 3, b.w - 40, 6)
      end
    end
  end
end

--- The forest's trail: clearings of lighter grass, then the dirt path
--- joining them, worn darker down the middle.
local function drawTrail(map)
  for _, w in ipairs(map.waypoints) do
    color(C.clearing)
    love.graphics.circle("fill", w.x, w.y, (w == map.lair and map.lairRadius or map.clearing) - 20, 48)
  end
  for pass, c in ipairs({ C.trail, C.trailDark }) do
    local width = pass == 1 and 56 or 22
    color(c)
    love.graphics.setLineWidth(width)
    for i = 1, #map.trail - 1 do
      local a, b = map.trail[i], map.trail[i + 1]
      love.graphics.line(a.x, a.y, b.x, b.y)
    end
    for _, n in ipairs(map.trail) do
      love.graphics.circle("fill", n.x, n.y, width / 2, 24)
    end
  end
  love.graphics.setLineWidth(1)
end

--- Bushes: a few overlapping blobs, some with berries.
local function drawShrubs(map)
  for _, s in ipairs(map.shrubs) do
    color(C.shadow)
    love.graphics.circle("fill", s.x + 4, s.y + 4, s.r)
  end
  for _, s in ipairs(map.shrubs) do
    local r = s.r
    color(C.shrub)
    love.graphics.circle("fill", s.x, s.y, r)
    love.graphics.circle("fill", s.x - r * 0.6, s.y + r * 0.3, r * 0.7)
    love.graphics.circle("fill", s.x + r * 0.6, s.y + r * 0.2, r * 0.7)
    color(C.shrubLight)
    love.graphics.circle("fill", s.x - r * 0.25, s.y - r * 0.3, r * 0.45)
    if s.berries then
      color(C.berry)
      love.graphics.circle("fill", s.x + r * 0.3, s.y - r * 0.1, 2)
      love.graphics.circle("fill", s.x - r * 0.5, s.y + r * 0.4, 2)
      love.graphics.circle("fill", s.x + r * 0.1, s.y + r * 0.5, 2)
    end
  end
end

--- A pine from above: stacked stars of needles, darkest at the rim.
local function drawPine(t)
  local r = t.r
  for k, c in ipairs({ C.pine, C.pineLight, C.pine }) do
    local rr = r * (1.08 - k * 0.28)
    local pts = {}
    for i = 0, 15 do
      local a = i * math.pi / 8 + k * 0.2
      local d = i % 2 == 0 and rr or rr * 0.72
      pts[#pts + 1] = t.x + math.cos(a) * d
      pts[#pts + 1] = t.y + math.sin(a) * d
    end
    color(c)
    love.graphics.circle("fill", t.x, t.y, rr * 0.72)
    for i = 0, 7 do
      local j = i * 4
      love.graphics.polygon("fill", t.x, t.y, pts[j + 1], pts[j + 2], pts[j + 3], pts[j + 4],
        pts[(j + 4) % 32 + 1], pts[(j + 4) % 32 + 2])
    end
  end
end

local function drawTrees(map)
  for _, t in ipairs(map.trees) do
    color(C.shadow)
    love.graphics.circle("fill", t.x + 8, t.y + 8, t.r or 24)
  end
  for _, t in ipairs(map.trees) do
    if t.pine then
      drawPine(t)
    else
      local r = t.r or 24
      color(C.canopy)
      love.graphics.circle("fill", t.x, t.y, r)
      color(C.canopyLight)
      love.graphics.circle("fill", t.x - r / 4, t.y - r / 4, r / 2)
    end
  end
end

local BEACH = {
  hill = { 0.33, 0.45, 0.24 },
  hillDark = { 0.28, 0.39, 0.20 },
  camp = { 0.40, 0.42, 0.28 },
  campDark = { 0.35, 0.36, 0.24 },
  mud = { 0.42, 0.36, 0.26 },
  mudDark = { 0.36, 0.30, 0.21 },
  trench = { 0.25, 0.20, 0.14 },
  sand = { 0.84, 0.76, 0.55 },
  sandDark = { 0.77, 0.68, 0.47 },
  wet = { 0.62, 0.58, 0.44 },
  sea = { 0.20, 0.42, 0.52 },
  seaDeep = { 0.14, 0.32, 0.44 },
  foam = { 0.88, 0.93, 0.95 },
  steel = { 0.30, 0.30, 0.32 },
  steelLight = { 0.48, 0.48, 0.50 },
  bag = { 0.62, 0.55, 0.38 },
  bagDark = { 0.48, 0.42, 0.28 },
  concrete = { 0.58, 0.58, 0.55 },
  concreteDark = { 0.40, 0.40, 0.38 },
  slit = { 0.08, 0.08, 0.08 },
  hut = { 0.36, 0.40, 0.30 },
  hutRoof = { 0.44, 0.48, 0.36 },
  craft = { 0.38, 0.44, 0.40 },
  craftDark = { 0.26, 0.30, 0.28 },
}

--- The ground of the landing beach, band by band from the hilltop down to
--- the sea, each speckled so walking over it reads as moving.
local function drawBeachGround(map)
  local B = map.bands
  local x, w = map.left, map.w
  local function band(b, c, dark, every)
    color(c)
    love.graphics.rectangle("fill", x, b.y0, w, b.y1 - b.y0)
    color(dark)
    local i = 0
    for yy = b.y0 + 10, b.y1 - 30, every do
      for xx = x + (i % 3) * 37, x + w - 40, every * 1.7 do
        love.graphics.rectangle("fill", xx + (yy * 7) % 23, yy, 34, 18)
      end
      i = i + 1
    end
  end
  band(B.hill, BEACH.hill, BEACH.hillDark, 70)
  band(B.barracks, BEACH.camp, BEACH.campDark, 80)
  band(B.bunkers, BEACH.mud, BEACH.mudDark, 60)
  band(B.beach, BEACH.sand, BEACH.sandDark, 90)
  -- The hill rises: lighter rings round the flag.
  for k = 3, 1, -1 do
    local c = shade(BEACH.hill, 1 + k * 0.05)
    color(c)
    love.graphics.circle("fill", map.flagX, map.flagY, 120 + (3 - k) * 110, 48)
  end
  -- Wet sand at the waterline, then the sea with lines of surf.
  local surf = B.surf
  color(BEACH.wet)
  love.graphics.rectangle("fill", x, surf.y0 - 60, w, 60)
  color(BEACH.sea)
  love.graphics.rectangle("fill", x, surf.y0, w, surf.y1 - surf.y0)
  color(BEACH.seaDeep)
  love.graphics.rectangle("fill", x, surf.y0 + (surf.y1 - surf.y0) * 0.6, w, (surf.y1 - surf.y0) * 0.4)
  color(BEACH.foam)
  love.graphics.setLineWidth(4)
  for k = 0, 3 do
    local yy = surf.y0 + 4 + k * 70
    local pts = {}
    for xx = x, x + w, 32 do
      pts[#pts + 1] = xx
      pts[#pts + 1] = yy + math.sin(xx / 60 + k) * 6
    end
    love.graphics.line(pts)
  end
  -- The trenches: dark ditches right across the map.
  for _, t in ipairs(map.trenches) do
    color(BEACH.trench)
    love.graphics.rectangle("fill", x, t.y, w, t.h)
    color(BEACH.mudDark)
    love.graphics.rectangle("fill", x, t.y, w, 6)
  end
  love.graphics.setLineWidth(1)
end

--- A Czech hedgehog from above: three steel beams crossed.
local function drawHedgehog(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.shadow)
  love.graphics.circle("fill", cx + 5, cy + 5, 12)
  love.graphics.setLineWidth(6)
  for k = 0, 2 do
    local a = s.angle + k * math.pi / 3
    local dx, dy = math.cos(a) * 16, math.sin(a) * 16
    color(BEACH.steel)
    love.graphics.line(cx - dx, cy - dy, cx + dx, cy + dy)
  end
  love.graphics.setLineWidth(2)
  color(BEACH.steelLight)
  local a = s.angle
  love.graphics.line(cx - math.cos(a) * 14, cy - math.sin(a) * 14, cx + math.cos(a) * 14, cy + math.sin(a) * 14)
  love.graphics.setLineWidth(1)
end

--- A wall of sandbags: rows of fat rounded bags, staggered.
local function drawSandbags(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w, s.h, 6)
  color(BEACH.bagDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 6)
  local long = s.w >= s.h
  local len = long and s.w or s.h
  local thick = long and s.h or s.w
  for k = 0, math.floor(len / 22) do
    local off = k * 22 + 2
    color(k % 2 == 0 and BEACH.bag or shade(BEACH.bag, 0.92))
    if long then
      love.graphics.rectangle("fill", s.x + off, s.y + 2, math.min(20, s.w - off - 2), thick - 4, 5)
    else
      love.graphics.rectangle("fill", s.x + 2, s.y + off, thick - 4, math.min(20, s.h - off - 2), 5)
    end
  end
end

--- A pillbox: thick concrete, a dark firing slit along its south face.
local function drawBunker(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 12, s.y + 12, s.w, s.h, 10)
  color(BEACH.concreteDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 10)
  color(BEACH.concrete)
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, s.h - 16, 8)
  color(shade(BEACH.concrete, 1.15))
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, 8, 4)
  color(BEACH.slit)
  love.graphics.rectangle("fill", s.x + s.w * 0.2, s.y + s.h - 14, s.w * 0.6, 8, 2)
end

--- A barracks hut: a long corrugated roof and a door on the south side.
local function drawHut(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 12, s.y + 12, s.w, s.h)
  color(shade(BEACH.hut, 0.7))
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(BEACH.hutRoof)
  love.graphics.rectangle("fill", s.x + 4, s.y + 4, s.w - 8, s.h - 8)
  color(BEACH.hut)
  for xx = s.x + 10, s.x + s.w - 12, 14 do
    love.graphics.rectangle("fill", xx, s.y + 6, 6, s.h - 12)
  end
  color(shade(BEACH.hut, 0.5))
  love.graphics.rectangle("fill", s.x + 4, s.y + s.h / 2 - 2, s.w - 8, 4) -- the ridge
  color(BEACH.slit)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 14, s.y + s.h - 6, 28, 6) -- the door
end

--- A landing craft beached nose first, the ramp down on the sand.
local function drawCraft(c)
  local w, h = 90, 150
  color(C.shadow)
  love.graphics.rectangle("fill", c.x - w / 2 + 8, c.y - h / 2 + 8, w, h, 8)
  color(BEACH.craftDark)
  love.graphics.rectangle("fill", c.x - w / 2, c.y - h / 2, w, h, 8)
  color(BEACH.craft)
  love.graphics.rectangle("fill", c.x - w / 2 + 8, c.y - h / 2 + 8, w - 16, h - 16, 4)
  color(BEACH.craftDark)
  love.graphics.rectangle("fill", c.x - w / 2 + 8, c.y - h / 2 - 50, w - 16, 52, 3) -- the ramp
  for k = 1, 4 do
    color(shade(BEACH.craft, 1.2))
    love.graphics.rectangle("fill", c.x - w / 2 + 12, c.y - h / 2 - 50 + k * 10, w - 24, 3)
  end
  color(BEACH.foam)
  love.graphics.setLineWidth(3)
  love.graphics.arc("line", "open", c.x, c.y + h / 2, w / 2 + 6, 0.2, math.pi - 0.2, 12)
  love.graphics.setLineWidth(1)
end

local function drawBeach(map)
  drawBeachGround(map)
  for _, c in ipairs(map.craft) do
    drawCraft(c)
  end
  for _, s in ipairs(map.cover) do
    if s.kind == "hedgehog" then
      drawHedgehog(s)
    elseif s.kind == "sandbag" then
      drawSandbags(s)
    elseif s.kind == "bunker" then
      drawBunker(s)
    elseif s.kind == "hut" then
      drawHut(s)
    end
  end
end

local CLIFF = {
  meadow = { 0.38, 0.52, 0.28 },
  meadowDark = { 0.33, 0.46, 0.24 },
  flowers = { 0.92, 0.86, 0.45 },
  plateau = { 0.55, 0.52, 0.36 },
  plateauDark = { 0.49, 0.46, 0.31 },
  rock = { 0.47, 0.43, 0.38 },
  rockDark = { 0.33, 0.30, 0.27 },
  rockLight = { 0.60, 0.56, 0.50 },
  dirt = { 0.52, 0.42, 0.30 },
  dirtDark = { 0.44, 0.35, 0.24 },
  stone = { 0.62, 0.61, 0.58 },
  stoneDark = { 0.46, 0.45, 0.43 },
}

--- Speckle a rectangle so walking over it reads as moving.
local function speckle(x, y, w, h, dark, every)
  color(dark)
  local i = 0
  for yy = y + 10, y + h - 30, every do
    for xx = x + (i % 3) * 37, x + w - 40, every * 1.7 do
      love.graphics.rectangle("fill", xx + (yy * 7) % 23, yy, 34, 18)
    end
    i = i + 1
  end
end

--- The ground: meadow below with a scatter of flowers, the dry plateau
--- above, the cliff face between them with its shadow on the grass, and
--- the ramp at the far left.
local function drawCliffGround(map)
  local x, w = map.left, map.w
  local cy = map.cliffY
  color(CLIFF.meadow)
  love.graphics.rectangle("fill", x, cy, w, map.top + map.h - cy)
  speckle(x, cy, w, map.top + map.h - cy, CLIFF.meadowDark, 80)
  color(CLIFF.flowers)
  local function hash(n) -- 0..1, the same on every machine
    local v = math.sin(n) * 43758.5453
    return v - math.floor(v)
  end
  for i = 1, 260 do
    local fx = x + hash(i * 12.9898) * w
    local fy = cy + 120 + hash(i * 78.233) * (map.top + map.h - cy - 140)
    love.graphics.rectangle("fill", fx, fy, 4, 4)
  end
  color(CLIFF.plateau)
  love.graphics.rectangle("fill", x, map.top, w, cy - map.top)
  speckle(x, map.top, w, cy - map.top, CLIFF.plateauDark, 70)
  -- The shadow the cliff throws on the meadow.
  color(C.shadow)
  love.graphics.rectangle("fill", map.ramp.x1, cy + 60, x + w - map.ramp.x1, 46)
  -- The ramp: a dirt track climbing from the meadow, worn into steps.
  local r = map.ramp
  color(CLIFF.dirt)
  love.graphics.rectangle("fill", r.x0, r.y0, r.x1 - r.x0, r.y1 - r.y0)
  color(CLIFF.dirtDark)
  for yy = r.y0 + 14, r.y1 - 10, 22 do
    love.graphics.rectangle("fill", r.x0 + 30, yy, r.x1 - r.x0 - 60, 6)
  end
end

--- The cliff: grey rock from the lip down, a ragged edge along the top and
--- cracks down the face.
local function drawCliffFace(s)
  color(CLIFF.rockDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(CLIFF.rock)
  love.graphics.rectangle("fill", s.x, s.y + 6, s.w, s.h - 20)
  local pts = {}
  for xx = s.x, s.x + s.w, 24 do
    pts[#pts + 1] = { xx, s.y - 4 + (xx * 13) % 11 }
  end
  color(CLIFF.rockLight)
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    love.graphics.polygon("fill", a[1], a[2], b[1], b[2], b[1], s.y + 12, a[1], s.y + 12)
  end
  color(CLIFF.rockDark)
  love.graphics.setLineWidth(3)
  for xx = s.x + 30, s.x + s.w - 30, 57 do
    local jog = (xx * 7) % 17 - 8
    love.graphics.line(xx, s.y + 14, xx + jog, s.y + s.h * 0.5, xx - jog / 2, s.y + s.h - 8)
  end
  love.graphics.setLineWidth(1)
end

--- A dry-stone wall: a dark bed and rounded stones along it.
local function drawStoneWall(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w, s.h, 5)
  color(CLIFF.stoneDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 5)
  local long = s.w >= s.h
  local len = long and s.w or s.h
  for k = 0, math.floor(len / 16) do
    local off = k * 16 + 2
    local size = 7 + (k * 5) % 4
    color(k % 2 == 0 and CLIFF.stone or shade(CLIFF.stone, 0.9))
    if long then
      love.graphics.circle("fill", s.x + math.min(off + 6, s.w - 7), s.y + s.h / 2, size, 8)
    else
      love.graphics.circle("fill", s.x + s.w / 2, s.y + math.min(off + 6, s.h - 7), size, 8)
    end
  end
end

--- A boulder: a lumpy grey heap, lit from the top left.
local function drawBoulder(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  local seed = s.seed or 0
  local pts = {}
  for i = 0, 8 do
    local a = i / 9 * 2 * math.pi
    local d = r * (1.05 + 0.18 * math.sin(seed + i * 2.1))
    pts[#pts + 1] = cx + math.cos(a) * d
    pts[#pts + 1] = cy + math.sin(a) * d
  end
  color(C.shadow)
  love.graphics.circle("fill", cx + 6, cy + 6, r * 1.1, 16)
  color(CLIFF.rockDark)
  for _, tri in ipairs(love.math.triangulate(pts)) do
    love.graphics.polygon("fill", tri)
  end
  color(CLIFF.rock)
  love.graphics.circle("fill", cx - r * 0.12, cy - r * 0.12, r * 0.8, 14)
  color(CLIFF.rockLight)
  love.graphics.circle("fill", cx - r * 0.35, cy - r * 0.35, r * 0.35, 10)
end

local function drawCliff(map)
  drawCliffGround(map)
  for _, s in ipairs(map.cover) do
    if s.kind == "cliff" then
      drawCliffFace(s)
    elseif s.kind == "wall" then
      drawStoneWall(s)
    elseif s.kind == "rock" then
      drawBoulder(s)
    end
  end
  drawTrees(map)
end

--- Build the canvas. Call once with graphics available.
function Render.build(map)
  local canvas = love.graphics.newCanvas(map.w / 2, map.h / 2)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.scale(0.5)
  love.graphics.translate(-map.left, -map.top)
  if map.kind == "beach" or map.kind == "cliff" then
    if map.kind == "beach" then
      drawBeach(map)
    else
      drawCliff(map)
    end
    love.graphics.setCanvas()
    love.graphics.pop()
    return canvas
  end
  drawRoads(map)
  if map.trail then
    drawTrail(map)
  end
  drawParksAndLots(map)
  drawBuildings(map)
  if map.shrubs then
    drawShrubs(map)
  end
  drawTrees(map)
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas
end

function Render.draw(map, canvas)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, map.left, map.top, 0, 2, 2)
end

return Render
