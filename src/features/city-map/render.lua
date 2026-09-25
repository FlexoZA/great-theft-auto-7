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

local ARENA = {
  grass = { 0.27, 0.42, 0.22 },
  grassDark = { 0.23, 0.36, 0.19 },
  camp = { 0.36, 0.50, 0.25 },
  channel = { 0.62, 0.62, 0.58 },
  channelDark = { 0.50, 0.50, 0.47 },
  water = { 0.22, 0.40, 0.50 },
  waterDeep = { 0.17, 0.33, 0.43 },
  kerb = { 0.72, 0.72, 0.70 },
  deck = { 0.24, 0.24, 0.26 },
  rail = { 0.82, 0.82, 0.80 },
  paving = { 0.44, 0.44, 0.46 },
  pavingLine = { 0.39, 0.39, 0.41 },
  wall = { 0.50, 0.48, 0.44 },
  wallDark = { 0.36, 0.34, 0.31 },
  stone = { 0.58, 0.56, 0.52 },
  stoneDark = { 0.42, 0.40, 0.37 },
  vault = { 0.30, 0.30, 0.33 },
  vaultDark = { 0.19, 0.19, 0.22 },
  gold = { 0.95, 0.78, 0.25 },
  fountain = { 0.35, 0.60, 0.80 },
  fountainLight = { 0.60, 0.80, 0.92 },
  kiosk = { 0.85, 0.75, 0.35 },
  kioskDark = { 0.55, 0.45, 0.20 },
}

--- A polyline as one thick stroke with round joins and ends.
local function stroke(pts, width)
  love.graphics.setLineWidth(width)
  for i = 1, #pts - 1 do
    love.graphics.line(pts[i].x, pts[i].y, pts[i + 1].x, pts[i + 1].y)
  end
  for _, p in ipairs(pts) do
    love.graphics.circle("fill", p.x, p.y, width / 2, 24)
  end
end

--- Dashes down the middle of a polyline.
local function dashes(pts, dash, gap, width)
  love.graphics.setLineWidth(width)
  for i = 1, #pts - 1 do
    local a, b = pts[i], pts[i + 1]
    local len = math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
    local dx, dy = (b.x - a.x) / len, (b.y - a.y) / len
    local d = gap / 2
    while d + dash < len do
      love.graphics.line(a.x + dx * d, a.y + dy * d, a.x + dx * (d + dash), a.y + dy * (d + dash))
      d = d + dash + gap
    end
  end
end

--- The jungle floor: grass with a worn patch here and there, the camps'
--- clearings and the footpaths between them.
local function drawArenaGround(map)
  color(ARENA.grass)
  love.graphics.rectangle("fill", map.left, map.top, map.w, map.h)
  color(ARENA.grassDark)
  local i = 0
  for yy = map.top + 10, map.top + map.h - 30, 70 do
    for xx = map.left + (i % 3) * 37, map.left + map.w - 40, 119 do
      love.graphics.rectangle("fill", xx + (yy * 7) % 23, yy, 34, 18)
    end
    i = i + 1
  end
  color(ARENA.camp)
  for _, c in ipairs(map.camps) do
    love.graphics.circle("fill", c.x, c.y, c.r - 16, 40)
  end
  for pass, c in ipairs({ C.trail, C.trailDark }) do
    color(c)
    for _, p in ipairs(map.paths) do
      stroke(p, pass == 1 and 48 or 18)
    end
  end
end

--- The storm channel: concrete banks, a foot of water and the dark line
--- of the drain down the middle.
local function drawRiver(map)
  local r = map.river
  local pts = { { x = r.x0, y = r.y0 }, { x = r.x1, y = r.y1 } }
  color(ARENA.channel)
  stroke(pts, r.w)
  color(ARENA.channelDark)
  stroke(pts, r.w - 16)
  color(ARENA.water)
  stroke(pts, r.w - 56)
  color(ARENA.waterDeep)
  stroke(pts, 24)
  color(ARENA.channel)
  dashes(pts, 6, 90, r.w - 60) -- expansion joints across the concrete
end

--- The lanes: a kerb, the tarmac, a dashed centreline.
local function drawLanes(map)
  local w = map.arena.laneW
  for _, l in ipairs(map.lanes) do
    color(ARENA.kerb)
    stroke(l.points, w + 12)
  end
  for _, l in ipairs(map.lanes) do
    color(C.asphalt)
    stroke(l.points, w)
  end
  color(C.lane)
  for _, l in ipairs(map.lanes) do
    dashes(l.points, 28, 28, 4)
  end
end

--- A bridge deck where a lane crosses the channel: planks and a railing
--- each side, the length of the crossing.
local function drawBridge(b, map)
  local w, len = map.arena.laneW, b.len
  love.graphics.push()
  love.graphics.translate(b.x, b.y)
  love.graphics.rotate(b.angle)
  color(C.shadow)
  love.graphics.rectangle("fill", -len / 2 + 6, -w / 2 + 8, len, w + 8)
  color(ARENA.deck)
  love.graphics.rectangle("fill", -len / 2, -w / 2 - 4, len, w + 8)
  color(shade(ARENA.deck, 1.25))
  for xx = -len / 2 + 6, len / 2 - 8, 14 do
    love.graphics.rectangle("fill", xx, -w / 2 - 2, 6, w + 4)
  end
  color(ARENA.rail)
  love.graphics.setLineWidth(5)
  love.graphics.line(-len / 2, -w / 2 - 6, len / 2, -w / 2 - 6)
  love.graphics.line(-len / 2, w / 2 + 6, len / 2, w / 2 + 6)
  for xx = -len / 2, len / 2, 30 do
    love.graphics.rectangle("fill", xx - 3, -w / 2 - 10, 6, 8)
    love.graphics.rectangle("fill", xx - 3, w / 2 + 2, 6, 8)
  end
  love.graphics.pop()
end

--- A stone tower with the team's brazier lit on top.
local function drawTower(t, map)
  local s = map.arena.tower
  local x, y = t.x - s / 2, t.y - s / 2
  local team = map.teams[t.team].color
  color(C.shadow)
  love.graphics.rectangle("fill", x + 10, y + 10, s, s, 4)
  color(ARENA.stoneDark)
  love.graphics.rectangle("fill", x, y, s, s, 4)
  color(ARENA.stone)
  love.graphics.rectangle("fill", x + 6, y + 6, s - 12, s - 12, 3)
  color(ARENA.stoneDark)
  for k = 0, 3 do -- the battlements
    love.graphics.rectangle("fill", x + 4 + k * 14, y + 4, 8, 6)
    love.graphics.rectangle("fill", x + 4 + k * 14, y + s - 10, 8, 6)
  end
  color(shade(team, 0.55))
  love.graphics.circle("fill", t.x, t.y, 12, 16)
  color(team)
  love.graphics.circle("fill", t.x, t.y, 8, 16)
  color(shade(team, 1.4))
  love.graphics.circle("fill", t.x - 2, t.y - 2, 3.5, 10)
end

--- The strongroom at the heart of a base: thick dark walls, the team's
--- colour on the roof and a koin over the door.
local function drawVault(v, team)
  local r = v.r
  color(C.shadow)
  love.graphics.rectangle("fill", v.x - r + 14, v.y - r + 14, r * 2, r * 2, 6)
  color(ARENA.vaultDark)
  love.graphics.rectangle("fill", v.x - r, v.y - r, r * 2, r * 2, 6)
  color(ARENA.vault)
  love.graphics.rectangle("fill", v.x - r + 10, v.y - r + 10, r * 2 - 20, r * 2 - 20, 4)
  color(team)
  love.graphics.rectangle("fill", v.x - r + 10, v.y - r + 10, r * 2 - 20, 14)
  love.graphics.rectangle("fill", v.x - r + 10, v.y + r - 24, r * 2 - 20, 14)
  color(shade(ARENA.gold, 0.6))
  love.graphics.circle("fill", v.x + 2, v.y + 2, 22, 24)
  color(ARENA.gold)
  love.graphics.circle("fill", v.x, v.y, 20, 24)
  color(shade(ARENA.gold, 0.75))
  love.graphics.circle("fill", v.x, v.y, 12, 20)
  color(ARENA.gold)
  love.graphics.circle("fill", v.x, v.y, 5, 12)
end

--- A base: the paved courtyard, its walls, the fountain, the shop stand,
--- the parking bays and the vault.
local function drawBase(b, map)
  local team = map.teams[b.team].color
  color(ARENA.paving)
  love.graphics.rectangle("fill", b.x0, b.y0, b.x1 - b.x0, b.y1 - b.y0)
  color(ARENA.pavingLine)
  love.graphics.setLineWidth(2)
  for xx = b.x0, b.x1, 64 do
    love.graphics.line(xx, b.y0, xx, b.y1)
  end
  for yy = b.y0, b.y1, 64 do
    love.graphics.line(b.x0, yy, b.x1, yy)
  end
  -- The fountain: a pool with the team's ring round it.
  local f = b.fountain
  color(shade(team, 0.7))
  love.graphics.circle("fill", f.x, f.y, f.r + 10, 40)
  color(ARENA.fountain)
  love.graphics.circle("fill", f.x, f.y, f.r, 40)
  color(ARENA.fountainLight)
  love.graphics.circle("fill", f.x - f.r * 0.25, f.y - f.r * 0.25, f.r * 0.45, 24)
  color(team)
  love.graphics.circle("fill", f.x, f.y, 12, 16)
  -- The shop stand: a kiosk with a striped awning.
  local s = b.shop
  color(C.shadow)
  love.graphics.rectangle("fill", s.x - s.w / 2 + 6, s.y - s.h / 2 + 6, s.w, s.h, 3)
  color(ARENA.kioskDark)
  love.graphics.rectangle("fill", s.x - s.w / 2, s.y - s.h / 2, s.w, s.h, 3)
  for k = 0, 5 do
    color(k % 2 == 0 and ARENA.kiosk or { 1, 1, 1 })
    love.graphics.rectangle("fill", s.x - s.w / 2 + 3 + k * 7, s.y - s.h / 2 + 3, 7, s.h - 6)
  end
  -- The walls: stone with the team's banner hung every so often.
  for _, w in ipairs(b.walls) do
    color(C.shadow)
    love.graphics.rectangle("fill", w.x + 10, w.y + 10, w.w, w.h)
    color(ARENA.wallDark)
    love.graphics.rectangle("fill", w.x, w.y, w.w, w.h)
    color(ARENA.wall)
    love.graphics.rectangle("fill", w.x + 4, w.y + 4, w.w - 8, w.h - 8)
    color(team)
    if w.w > w.h then
      for xx = w.x + 40, w.x + w.w - 40, 120 do
        love.graphics.rectangle("fill", xx - 4, w.y - 2, 8, w.h + 4)
      end
    else
      for yy = w.y + 40, w.y + w.h - 40, 120 do
        love.graphics.rectangle("fill", w.x - 2, yy - 4, w.w + 4, 8)
      end
    end
  end
  drawVault(b.vault, team)
end

--- The parking bays the cars stand in, one per spawn.
local function drawBays(map)
  color(C.bay)
  love.graphics.setLineWidth(3)
  for _, s in ipairs(map.spawns) do
    love.graphics.push()
    love.graphics.translate(s.x, s.y)
    love.graphics.rotate(s.angle)
    love.graphics.rectangle("line", -30, -18, 60, 36, 3)
    love.graphics.pop()
  end
end

local function drawArena(map)
  drawArenaGround(map)
  drawRiver(map)
  drawLanes(map)
  for _, b in ipairs(map.bridges) do
    drawBridge(b, map)
  end
  for _, b in ipairs(map.bases) do
    drawBase(b, map) -- over the lanes: the paving takes their ends at the gates
  end
  drawBays(map)
  for _, t in ipairs(map.towers) do
    drawTower(t, map)
  end
  love.graphics.setLineWidth(1)
  drawShrubs(map)
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
  if map.kind == "beach" or map.kind == "arena" then
    if map.kind == "beach" then
      drawBeach(map)
    else
      drawArena(map)
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
