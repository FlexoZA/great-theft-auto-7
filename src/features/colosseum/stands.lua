-- The stands round the Colosseum's arena, past the podium wall: rows of
-- stone seats rising away from the sand, walkways between the tiers,
-- aisles running up them, the emperor's box on the north side under its
-- awning, and a full crowd on its feet, bobbing. The outer wall closes it
-- off at the top. Scenery only, drawn past the map's edge (surroundings
-- asks, through `Colosseum:drawStands`) and through the clear corners of
-- the map's canvas, over whatever part of it the camera sees.

local Stands = {}

Stands.FROM = 72 -- px out from the sand's edge the first row starts (past the podium wall)
Stands.TO = 900 -- px out the last row ends, at the outer wall
Stands.ROW = 26 -- px between rows
Stands.TIER = 9 -- rows a tier; a walkway between tiers
Stands.SEAT = 20 -- px between spectators along a row
Stands.AISLES = 24
Stands.OUTER = 64 -- px thick, the outer wall

local C = {
  outside = { 0.24, 0.22, 0.20 },
  stone = { 0.66, 0.60, 0.50 },
  step = { 0.50, 0.45, 0.37 },
  walk = { 0.76, 0.71, 0.60 },
  outer = { 0.80, 0.74, 0.62 },
  outerEdge = { 0.45, 0.40, 0.32 },
  awning = { 0.62, 0.10, 0.12 },
  gold = { 0.90, 0.70, 0.20 },
}
local CROWD = {
  { 0.78, 0.22, 0.18 },
  { 0.92, 0.90, 0.84 },
  { 0.80, 0.62, 0.30 },
  { 0.38, 0.45, 0.58 },
  { 0.45, 0.52, 0.36 },
  { 0.55, 0.38, 0.30 },
}

local function color(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local crowd = nil -- { oval, groups = { [colour] = { x, y, phase... } } } for the oval it was seated round

--- Is the row `i` (from 0) a walkway between tiers?
local function walkway(i)
  return i % (Stands.TIER + 1) == Stands.TIER
end

--- Where the emperor's box is: an angle on the north side, and its half width (radians).
local BOX_ANGLE, BOX_HALF = -math.pi / 2, 0.09

--- Seat everyone round `oval` once: a spectator every SEAT px along every
--- row, but not on the walkways, in the aisles or in the emperor's box.
local function seat(oval)
  local groups = {}
  for k = 1, #CROWD do
    groups[k] = {}
  end
  local aisle = 2 * math.pi / Stands.AISLES
  local i, n = 0, 0
  for d = Stands.FROM, Stands.TO - Stands.ROW, Stands.ROW do
    if not walkway(i) then
      local rx, ry = oval.rx + d + Stands.ROW / 2, oval.ry + d + Stands.ROW / 2
      local step = Stands.SEAT / ((rx + ry) / 2)
      local gap = 14 / ((rx + ry) / 2) -- half an aisle's width, as an angle
      for a = 0, 2 * math.pi - step, step do
        local off = (a + aisle / 2) % aisle - aisle / 2 -- from the nearest aisle
        local box = math.abs(((a - BOX_ANGLE + math.pi) % (2 * math.pi)) - math.pi) < BOX_HALF and d < 220
        if math.abs(off) > gap and not box then
          n = n + 1
          local g = groups[math.floor(hash(n) * #CROWD) + 1]
          g[#g + 1] = oval.x + math.cos(a) * rx
          g[#g + 1] = oval.y + math.sin(a) * ry
          g[#g + 1] = hash(n + 0.5) * 2 * math.pi
        end
      end
    end
    i = i + 1
  end
  return { oval = oval, groups = groups }
end

--- The stone: the outside first, the stands' bowl, the steps and walkways,
--- the aisles, the outer wall.
local function drawStone(o)
  local far = Stands.TO
  color(C.stone)
  love.graphics.ellipse("fill", o.x, o.y, o.rx + far, o.ry + far, 128)
  local i = 0
  for d = Stands.FROM, far - Stands.ROW, Stands.ROW do
    if walkway(i) then
      love.graphics.setLineWidth(Stands.ROW - 4)
      color(C.walk)
      love.graphics.ellipse("line", o.x, o.y, o.rx + d + Stands.ROW / 2, o.ry + d + Stands.ROW / 2, 128)
    else
      love.graphics.setLineWidth(3)
      color(C.step)
      love.graphics.ellipse("line", o.x, o.y, o.rx + d, o.ry + d, 128)
    end
    i = i + 1
  end
  love.graphics.setLineWidth(14)
  color(C.walk)
  for k = 0, Stands.AISLES - 1 do
    local a = k * 2 * math.pi / Stands.AISLES
    local ca, sa = math.cos(a), math.sin(a)
    love.graphics.line(o.x + ca * (o.rx + Stands.FROM), o.y + sa * (o.ry + Stands.FROM),
      o.x + ca * (o.rx + far), o.y + sa * (o.ry + far))
  end
  love.graphics.setLineWidth(Stands.OUTER)
  color(C.outer)
  love.graphics.ellipse("line", o.x, o.y, o.rx + far + Stands.OUTER / 2, o.ry + far + Stands.OUTER / 2, 128)
  love.graphics.setLineWidth(4)
  color(C.outerEdge)
  love.graphics.ellipse("line", o.x, o.y, o.rx + far, o.ry + far, 128)
  love.graphics.setLineWidth(1)
end

--- The emperor's box: a red awning striped gold, over the north stands.
local function drawBox(o)
  local x, y = o.x, o.y - o.ry - 140
  color({ 0, 0, 0, 0.3 })
  love.graphics.rectangle("fill", x - 140 + 12, y - 60 + 12, 280, 120)
  color(C.awning)
  love.graphics.rectangle("fill", x - 140, y - 60, 280, 120)
  color(C.gold)
  for k = 0, 6 do
    love.graphics.rectangle("fill", x - 140 + k * 46, y - 60, 12, 120)
  end
  love.graphics.rectangle("fill", x - 140, y + 54, 280, 6)
end

--- The stands over (left, top, right, bottom), world px, round `oval`
--- ({ x, y, rx, ry }: the sand), the crowd bobbing at `time`; `scale` is
--- the camera's zoom (the crowd is drawn as points, sized on screen).
function Stands.draw(oval, left, top, right, bottom, time, scale)
  if not (crowd and crowd.oval == oval) then
    crowd = seat(oval)
  end
  color(C.outside)
  love.graphics.rectangle("fill", left, top, right - left, bottom - top)
  drawStone(oval)
  love.graphics.setPointSize(math.max(1, 9 * (scale or 1)))
  local pts = {}
  for k, g in ipairs(crowd.groups) do
    local m = 0
    for j = 1, #g, 3 do
      local x, y = g[j], g[j + 1]
      if x >= left and x <= right and y >= top and y <= bottom then
        pts[m + 1] = x
        pts[m + 2] = y - math.abs(math.sin(time * 5 + g[j + 2])) * 3 -- up on their feet and down
        m = m + 2
      end
    end
    for j = #pts, m + 1, -1 do
      pts[j] = nil
    end
    if m > 0 then
      color(CROWD[k])
      love.graphics.points(pts)
    end
  end
  love.graphics.setPointSize(1)
  drawBox(oval)
  love.graphics.setColor(1, 1, 1)
end

return Stands
