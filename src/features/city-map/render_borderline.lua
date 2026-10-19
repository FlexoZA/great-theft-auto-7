-- Drawing the Borderline quest line's maps (borderline.lua) into the map
-- canvas, in the style of a cel-shaded comic: flat bright colours and a hard
-- black outline round everything, the floors' edges included. Each map's
-- outside (`map.outside`) round its floors, the floors' finishes
-- (`map.grounds`), then everything flat on them and everything standing,
-- each standing thing with a flat shadow. Drawn once, by day.

local RenderBorderline = {}

local INK = { 0.07, 0.07, 0.09 } -- the outlines
local LINE = 5 -- px, at full size: the canvas is half, so a little over 2 there

local C = {
  snow = { 0.90, 0.93, 0.97 },
  snowShade = { 0.78, 0.84, 0.92 },
  bank = { 0.66, 0.73, 0.83 }, -- the snowbanks past the floors' edges
  bankRock = { 0.40, 0.42, 0.48 },
  ice = { 0.70, 0.84, 0.95 },
  sea = { 0.20, 0.40, 0.56 },
  floe = { 0.84, 0.90, 0.96 },
  rock = { 0.42, 0.36, 0.32 },
  rockLight = { 0.54, 0.47, 0.41 },
  abyss = { 0.10, 0.12, 0.18 },
  glass = { 0.56, 0.78, 0.88 },
  wall = { 0.20, 0.21, 0.24 },
  sky = { 0.62, 0.78, 0.92 },
  quay = { 0.52, 0.52, 0.56 },
  yard = { 0.68, 0.68, 0.70 },
  gravel = { 0.60, 0.53, 0.46 },
  terrace = { 0.66, 0.56, 0.47 },
  pitfloor = { 0.52, 0.43, 0.42 },
  street = { 0.80, 0.78, 0.72 },
  plaza = { 0.93, 0.86, 0.60 },
  grate = { 0.31, 0.31, 0.35 },
  steel = { 0.45, 0.47, 0.51 },
  upper = { 0.55, 0.52, 0.42 },
  road = { 0.82, 0.85, 0.89 },
  roof = { 0.48, 0.50, 0.55 },
  ballast = { 0.46, 0.43, 0.41 }, -- the rail bed
  works = { 0.27, 0.29, 0.33 }, -- the factory's roofs past the yard
  worksRidge = { 0.20, 0.22, 0.25 },
  pitWall = { 0.36, 0.31, 0.28 },
  pitDeep = { 0.10, 0.09, 0.10 },
  paintWhite = { 0.92, 0.92, 0.88 },
  drum = { 0.70, 0.20, 0.14 },
  cone = { 1.00, 0.45, 0.10 },
  hull = { 0.55, 0.16, 0.12 }, -- ships' red
  hullDark = { 0.32, 0.09, 0.08 },
  rust = { 0.50, 0.26, 0.15 }, -- an old hull rusting in the dry dock
  deck = { 0.40, 0.42, 0.40 },
  dockWater = { 0.16, 0.26, 0.34 },
  yellow = { 0.95, 0.76, 0.19 }, -- Hyperbole's
  yellowDark = { 0.78, 0.58, 0.10 },
  gunmetal = { 0.23, 0.25, 0.28 },
  gunmetalLight = { 0.36, 0.38, 0.42 },
  wood = { 0.62, 0.44, 0.26 },
  woodDark = { 0.48, 0.33, 0.19 },
  window = { 0.26, 0.36, 0.48 },
  purple = { 0.71, 0.30, 1.00 }, -- Bragium
  purpleLight = { 0.88, 0.66, 1.00 },
  green = { 0.40, 0.70, 0.30 },
  gold = { 0.96, 0.78, 0.30 },
  white = { 0.94, 0.94, 0.92 },
  shadow = { 0, 0, 0, 0.28 },
  containers = {
    { 0.80, 0.26, 0.20 },
    { 0.22, 0.44, 0.72 },
    { 0.28, 0.58, 0.34 },
    { 0.90, 0.52, 0.16 },
  },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- A filled box with the outline round it.
local function box(x, y, w, h, fill)
  color(INK)
  love.graphics.rectangle("fill", x - LINE, y - LINE, w + 2 * LINE, h + 2 * LINE)
  color(fill)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- A filled ellipse in (x, y, w, h) with the outline round it.
local function blob(x, y, w, h, fill)
  local cx, cy = x + w / 2, y + h / 2
  color(INK)
  love.graphics.ellipse("fill", cx, cy, w / 2 + LINE, h / 2 + LINE, 20)
  color(fill)
  love.graphics.ellipse("fill", cx, cy, w / 2, h / 2, 20)
end

--- Black and yellow blocks along a strip, the long way.
local function hazard(x, y, w, h)
  local along = w >= h
  local len, step = along and w or h, 24
  for i = 0, math.ceil(len / step) - 1 do
    color(i % 2 == 0 and C.yellow or INK)
    local a = i * step
    local s = math.min(step, len - a)
    if along then
      love.graphics.rectangle("fill", x + a, y, s, h)
    else
      love.graphics.rectangle("fill", x, y + a, w, s)
    end
  end
end

local font = nil
local function signFont()
  font = font or love.graphics.newFont(22)
  return font
end

-- The outside and the floors ---------------------------------------------------------

--- What the outside is at tile (c, r) on `map`.
local function outsideAt(map, c, r)
  local o = map.outside
  if o == "works" then
    return C.works
  elseif o == "harbour" then
    return r < 2 and C.sea or C.bank
  elseif o == "rock" then
    return C.rock
  elseif o == "dome" then
    return C.bank
  elseif o == "plant" then
    return C.wall
  elseif o == "cliff" then
    local road = map.cutsRoad[r]
    return road and c < road[1] and C.abyss or C.rock
  elseif o == "sky" then
    return C.sky
  end
  return C.bank
end

local function floorAt(map, x, y)
  local floor = nil
  for _, g in ipairs(map.grounds) do
    if x >= g.x0 and x < g.x1 and y >= g.y0 and y < g.y1 then
      floor = g.floor
    end
  end
  return C[floor] or C.yard
end

local function open(map, c, r)
  return map.tiles[c] ~= nil and map.tiles[c][r] ~= nil
end

local function drawTiles(map, T)
  color(outsideAt(map, -1, -1))
  love.graphics.rectangle("fill", map.left - 600, map.top - 600, map.w + 1200, map.h + 1200)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      local x, y = map.x0 + c * T, map.y0 + r * T
      local h = hash(c * 7.1 + r * 13.7)
      if open(map, c, r) then
        local f = floorAt(map, x + T / 2, y + T / 2)
        color(f)
        love.graphics.rectangle("fill", x, y, T, T)
        if f == C.snow or f == C.road or (f == C.yard and h < 0.5) then -- drifts
          color(C.snowShade)
          love.graphics.ellipse("fill", x + h * T, y + hash(h) * T, 14 + h * 12, 5 + h * 4)
        elseif f ~= C.ice and f ~= C.plaza then -- slabs and plates
          color(INK, 0.18)
          love.graphics.rectangle("fill", x, y, T, 2)
          love.graphics.rectangle("fill", x, y, 2, T)
        end
      else
        local o = outsideAt(map, c, r)
        color(o)
        love.graphics.rectangle("fill", x, y, T, T)
        if o == C.works then -- corrugated roofs: ridges, and a vent box now and then
          color(C.worksRidge)
          for k = 4, T - 4, 10 do
            love.graphics.rectangle("fill", x, y + k, T, 3)
          end
          if h < 0.18 then
            box(x + 14, y + 14, 34, 30, C.gunmetalLight)
          end
        elseif o == C.rock and h < 0.4 then
          color(C.rockLight)
          love.graphics.polygon("fill", x + 10, y + 50, x + 30 + h * 20, y + 14, x + 54, y + 48)
        elseif o == C.sea and h < 0.3 then
          blob(x + h * 30, y + 20, 26 + h * 20, 14, C.floe)
        elseif map.outside == "dome" and (open(map, c - 1, r) or open(map, c + 1, r)
            or open(map, c, r - 1) or open(map, c, r + 1)) then
          color(C.glass)
          love.graphics.rectangle("fill", x, y, T, T)
        elseif o == C.bank and h < 0.3 then -- rocks poking out of the snow
          blob(x + 8 + h * 20, y + 14, 22 + h * 40, 16 + h * 24, C.bankRock)
          color(C.snow)
          love.graphics.ellipse("fill", x + 20 + h * 30, y + 18, 8 + h * 12, 4 + h * 6)
        end
      end
    end
  end
end

--- The comic outline along every edge where a floor meets the outside.
local function drawEdges(map, T)
  color(INK)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if open(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if not open(map, c - 1, r) then
          love.graphics.rectangle("fill", x - LINE, y - LINE, LINE, T + 2 * LINE)
        end
        if not open(map, c + 1, r) then
          love.graphics.rectangle("fill", x + T, y - LINE, LINE, T + 2 * LINE)
        end
        if not open(map, c, r - 1) then
          love.graphics.rectangle("fill", x - LINE, y - LINE, T + 2 * LINE, LINE)
        end
        if not open(map, c, r + 1) then
          love.graphics.rectangle("fill", x - LINE, y + T, T + 2 * LINE, LINE)
        end
      end
    end
  end
end

-- What lies and stands about ------------------------------------------------------------

local DRAW = {}

function DRAW.rails(s)
  color(C.woodDark)
  for y = s.y, s.y + s.h - 8, 28 do
    love.graphics.rectangle("fill", s.x - 14, y, s.w + 28, 9)
  end
  color(C.gunmetal)
  love.graphics.rectangle("fill", s.x - 6, s.y, 5, s.h)
  love.graphics.rectangle("fill", s.x + s.w + 1, s.y, 5, s.h)
end

function DRAW.cave(s)
  blob(s.x, s.y - s.h * 0.4, s.w, s.h * 1.4, INK)
end

function DRAW.carriage(s)
  box(s.x, s.y, s.w, s.h, C.yellow)
  local along = s.w >= s.h
  color(C.window)
  local len = along and s.w or s.h
  for a = 24, len - 48, 56 do
    if along then
      love.graphics.rectangle("fill", s.x + a, s.y + s.h * 0.3, 34, s.h * 0.4)
    else
      love.graphics.rectangle("fill", s.x + s.w * 0.3, s.y + a, s.w * 0.4, 34)
    end
  end
  color(C.gunmetal)
  if along then
    love.graphics.rectangle("fill", s.x, s.y + s.h - 12, s.w, 12)
  else
    love.graphics.rectangle("fill", s.x + s.w - 12, s.y, 12, s.h)
  end
end

function DRAW.loco(s)
  box(s.x, s.y, s.w, s.h, C.gunmetal)
  hazard(s.x, s.y, s.w, 20)
  color(C.yellow)
  love.graphics.rectangle("fill", s.x + s.w * 0.4, s.y + 30, s.w * 0.2, s.h - 60)
  blob(s.x + s.w * 0.25, s.y + s.h * 0.2, s.w * 0.5, s.w * 0.5, C.gunmetalLight) -- the stack
end

function DRAW.crate(s)
  box(s.x, s.y, s.w, s.h, C.wood)
  color(C.woodDark)
  love.graphics.rectangle("fill", s.x, s.y + s.h * 0.45, s.w, s.h * 0.1)
  love.graphics.rectangle("fill", s.x + s.w * 0.45, s.y, s.w * 0.1, s.h)
end

function DRAW.chest(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.yellow)
  love.graphics.rectangle("fill", s.x, s.y + s.h * 0.35, s.w, s.h * 0.15)
end

function DRAW.rock(s)
  blob(s.x, s.y, s.w, s.h * 0.85, C.rockLight)
  color(C.snow) -- snow on top
  love.graphics.ellipse("fill", s.x + s.w * 0.45, s.y + s.h * 0.3, s.w * 0.3, s.h * 0.16)
end
DRAW.boulder = DRAW.rock

function DRAW.container(s)
  local tint = C.containers[s.tint or 1]
  box(s.x, s.y, s.w, s.h, tint)
  color(INK, 0.3)
  local along = s.w >= s.h
  for a = 16, (along and s.w or s.h) - 8, 22 do
    if along then
      love.graphics.rectangle("fill", s.x + a, s.y + 6, 4, s.h - 12)
    else
      love.graphics.rectangle("fill", s.x + 6, s.y + a, s.w - 12, 4)
    end
  end
end

function DRAW.crane(s)
  box(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.setLineWidth(8)
  love.graphics.line(s.x, s.y, s.x + s.w, s.y + s.h)
  love.graphics.line(s.x + s.w, s.y, s.x, s.y + s.h)
  love.graphics.setLineWidth(1)
end

function DRAW.bollard(s)
  blob(s.x, s.y, s.w, s.h, C.gunmetal)
end

function DRAW.lift(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  hazard(s.x, s.y, s.w, 16)
  hazard(s.x, s.y + s.h - 16, s.w, 16)
end
DRAW.gate = DRAW.lift
DRAW.door = DRAW.lift
DRAW.bay = DRAW.lift
DRAW.hatch = DRAW.lift

function DRAW.ledge(s)
  box(s.x, s.y, s.w, s.h, C.rock)
end

function DRAW.ramp(s)
  color(C.gravel)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(INK, 0.25)
  local along = s.w >= s.h
  for a = 0, (along and s.h or s.w), 14 do
    if along then
      love.graphics.rectangle("fill", s.x, s.y + a, s.w, 3)
    else
      love.graphics.rectangle("fill", s.x + a, s.y, 3, s.h)
    end
  end
end

--- A conveyor's belt and rollers (the ore riding it moves: borderline/works.lua).
function DRAW.conveyor(s)
  box(s.x, s.y, s.w, s.h, C.gunmetal)
  color(C.gunmetalLight)
  local along = s.w >= s.h
  for a = 8, (along and s.w or s.h) - 8, 24 do
    if along then
      love.graphics.rectangle("fill", s.x + a, s.y + 3, 4, s.h - 6)
    else
      love.graphics.rectangle("fill", s.x + 3, s.y + a, s.w - 6, 4)
    end
  end
end

--- A mine shaft: a square of black going straight down, a grating over
--- part of it, hazard striped round its collar (the headframe over it is
--- works.lua's).
function DRAW.shaft(s)
  box(s.x, s.y, s.w, s.h, C.gunmetal)
  color(INK)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - 32, s.h - 32)
  color(C.gunmetalLight)
  for x = s.x + 16, s.x + s.w * 0.45, 10 do -- the grating over the near half
    love.graphics.rectangle("fill", x, s.y + 16, 3, s.h - 32)
  end
  hazard(s.x, s.y, s.w, 10)
  hazard(s.x, s.y + s.h - 10, s.w, 10)
  hazard(s.x, s.y, 10, s.h)
  hazard(s.x + s.w - 10, s.y, 10, s.h)
end

--- A haul truck, parked: a yellow bed full of purple ore, the cab to one
--- side up front, big black wheels.
function DRAW.truck(s)
  local along = s.w >= s.h
  color(INK)
  for _, k in ipairs({ 0.15, 0.85 }) do -- the wheels
    if along then
      love.graphics.rectangle("fill", s.x + s.w * k - 22, s.y - 8, 44, s.h + 16, 6)
    else
      love.graphics.rectangle("fill", s.x - 8, s.y + s.h * k - 22, s.w + 16, 44, 6)
    end
  end
  box(s.x, s.y, s.w, s.h, C.yellow)
  local bx, by, bw, bh = s.x + 10, s.y + 10, s.w - 20, s.h - 20 -- the bed
  if along then
    bw = bw * 0.7
  else
    by, bh = by + bh * 0.3, bh * 0.7
  end
  box(bx, by, bw, bh, C.yellowDark)
  color(C.purple)
  for i = 0, 5 do
    local h = hash((s.seed or 1) + i)
    love.graphics.circle("fill", bx + bw * (0.15 + 0.7 * h), by + bh * (0.2 + 0.6 * hash(h + i)), 10 + h * 8, 6)
  end
  local cx, cy = along and s.x + s.w - 44 or s.x + 10, along and s.y + 10 or s.y + 10 -- the cab
  box(cx, cy, 34, 30, C.gunmetal)
  color(C.window)
  love.graphics.rectangle("fill", cx + 6, cy + 6, 22, 10)
end

function DRAW.crystal(s)
  blob(s.x, s.y, s.w, s.h, C.purple)
  color(C.purpleLight)
  love.graphics.polygon("fill", s.x + s.w * 0.3, s.y + s.h * 0.6, s.x + s.w * 0.45, s.y + s.h * 0.15,
    s.x + s.w * 0.6, s.y + s.h * 0.6)
end

function DRAW.pad(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + LINE, 40)
  for i = 0, 15 do
    color(i % 2 == 0 and C.yellow or INK)
    love.graphics.arc("fill", cx, cy, r, i * math.pi / 8, (i + 1) * math.pi / 8)
  end
  color(C.steel)
  love.graphics.circle("fill", cx, cy, r * 0.8, 40)
end

--- A factory block in Jerry's town: a corrugated roof, rows of sawtooth
--- skylights, Hyperbole yellow round the edge, plant on the roof, and its
--- chimney (`stackX`, `stackY`; the smoke is borderline/works.lua's).
function DRAW.tower(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.gunmetal)
  for y = s.y + 12, s.y + s.h - 8, 14 do -- the corrugations
    love.graphics.rectangle("fill", s.x, y, s.w, 4)
  end
  for x = s.x + 40, s.x + s.w - 60, 90 do -- the sawtooth skylights
    color(INK)
    love.graphics.rectangle("fill", x, s.y + 30, 40, s.h - 60)
    color(C.window)
    love.graphics.rectangle("fill", x + 4, s.y + 34, 20, s.h - 68)
  end
  color(C.yellow) -- the trim round the roof
  love.graphics.rectangle("fill", s.x, s.y, s.w, 10)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 10, s.w, 10)
  local h = hash(s.seed or 1)
  box(s.x + s.w * (0.55 + h * 0.2), s.y + s.h * 0.15, 60, 44, C.steel) -- plant on the roof
  if s.stackX then
    blob(s.stackX - 26, s.stackY - 26, 52, 52, C.rust)
    color(INK)
    love.graphics.circle("fill", s.stackX, s.stackY, 16, 16)
    color(C.yellow) -- its warning bands
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", s.stackX, s.stackY, 22, 18)
    love.graphics.setLineWidth(1)
  end
end

--- A loading lot: darker concrete, painted bays along it.
function DRAW.lot(s)
  box(s.x, s.y, s.w, s.h, C.quay)
  color(C.paintWhite, 0.7)
  for y = s.y + 20, s.y + s.h - 20, 70 do
    love.graphics.rectangle("fill", s.x + s.w * 0.45, y, s.w * 0.5, 5)
  end
  hazard(s.x, s.y, s.w, 10)
end

--- A street lamp, from above: its head on the post.
function DRAW.lamp(s)
  blob(s.x, s.y, s.w, s.h, C.gunmetal)
  color(C.paintWhite)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.25, 8)
end

function DRAW.statue(s)
  blob(s.x, s.y, s.w, s.h, C.gunmetalLight) -- the plinth
  blob(s.x + s.w * 0.3, s.y + s.h * 0.3, s.w * 0.4, s.h * 0.4, C.gold) -- Jerry, from above: all hair
end

function DRAW.lawn(s)
  box(s.x, s.y, s.w, s.h, C.green)
end

function DRAW.billboard(s)
  box(s.x, s.y, s.w, s.h, INK)
  color(C.yellow)
  love.graphics.setFont(signFont())
  love.graphics.printf("JERRY LOVES YOU", s.x, s.y + (s.h - 22) / 2, s.w, "center")
end

--- The molten river: purple, a crust here and there (its flow is
--- borderline/works.lua's), a railing along each bank with hazard stripes.
function DRAW.river(s)
  color(C.purple)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.purpleLight)
  for i = 0, math.floor(s.w * s.h / 9000) do
    local h = hash(s.x + s.y * 3 + i * 17)
    love.graphics.ellipse("fill", s.x + h * s.w, s.y + hash(h + i) * s.h, 22, 6)
  end
  local along = s.w >= s.h
  if along then
    hazard(s.x, s.y - 10, s.w, 10)
    hazard(s.x, s.y + s.h, s.w, 10)
  else
    hazard(s.x - 10, s.y, 10, s.h)
    hazard(s.x + s.w, s.y, 10, s.h)
  end
end

--- The casting pit: a deep box, rows of moulds in it, the fresh ones
--- glowing with Bragium.
function DRAW.casting(s)
  box(s.x, s.y, s.w, s.h, C.pitWall)
  color(C.pitDeep)
  love.graphics.rectangle("fill", s.x + 18, s.y + 18, s.w - 36, s.h - 36)
  local i = 0
  for y = s.y + 34, s.y + s.h - 70, 64 do
    for x = s.x + 34, s.x + s.w - 70, 64 do
      i = i + 1
      box(x, y, 40, 40, C.gunmetal)
      color(hash((s.seed or 1) + i) < 0.5 and C.purple or C.rust)
      love.graphics.rectangle("fill", x + 6, y + 6, 28, 28)
    end
  end
  hazard(s.x, s.y, s.w, 12)
  hazard(s.x, s.y + s.h - 12, s.w, 12)
  hazard(s.x, s.y, 12, s.h)
  hazard(s.x + s.w - 12, s.y, 12, s.h)
end

--- A steam vent in the floor: a grille over the dark (the steam is works.lua's).
function DRAW.grille(s)
  box(s.x + 6, s.y + 6, s.w - 12, s.h - 12, INK)
  color(C.gunmetalLight)
  for x = s.x + 12, s.x + s.w - 14, 9 do
    love.graphics.rectangle("fill", x, s.y + 8, 3, s.h - 16)
  end
end

function DRAW.bridge(s)
  box(s.x, s.y, s.w, s.h, C.grate)
  color(C.yellow) -- the rails
  love.graphics.rectangle("fill", s.x, s.y, 10, s.h)
  love.graphics.rectangle("fill", s.x + s.w - 10, s.y, 10, s.h)
end

function DRAW.tank(s)
  blob(s.x, s.y, s.w, s.h, C.steel)
  color(C.yellow)
  love.graphics.setLineWidth(10)
  love.graphics.circle("line", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.3)
  love.graphics.setLineWidth(1)
end

function DRAW.pipe(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.yellowDark)
  for a = 30, s.w - 20, 90 do
    love.graphics.rectangle("fill", s.x + a, s.y, 10, s.h)
  end
end

function DRAW.belt(s)
  color(C.gunmetal)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.gunmetalLight)
  for a = 10, s.w - 30, 40 do -- chevrons: which way it runs
    love.graphics.polygon("fill", s.x + a, s.y + 10, s.x + a + 20, s.y + s.h / 2, s.x + a, s.y + s.h - 10)
  end
  hazard(s.x, s.y - 8, s.w, 8)
  hazard(s.x, s.y + s.h, s.w, 8)
end

function DRAW.arm(s)
  blob(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.setLineWidth(12)
  local a = hash(s.seed or 1) * math.pi * 2
  love.graphics.line(s.x + s.w / 2, s.y + s.h / 2, s.x + s.w / 2 + math.cos(a) * 60, s.y + s.h / 2 + math.sin(a) * 60)
  love.graphics.setLineWidth(1)
end

function DRAW.press(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  hazard(s.x, s.y, s.w, 18)
end

function DRAW.booth(s)
  box(s.x, s.y, s.w, s.h, C.white)
  color(C.yellow, 0.6) -- overspray
  love.graphics.ellipse("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.3, s.h * 0.25)
end

function DRAW.stairs(s)
  color(C.steel)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(INK, 0.4)
  for y = s.y, s.y + s.h, 16 do
    love.graphics.rectangle("fill", s.x, y, s.w, 4)
  end
end

function DRAW.nest(s)
  blob(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.32)
end

function DRAW.cannon(s)
  blob(s.x, s.y, s.w, s.h, C.gunmetal)
  color(C.yellow)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.18)
end

function DRAW.vent(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(INK, 0.5)
  for y = s.y + 8, s.y + s.h - 8, 12 do
    love.graphics.rectangle("fill", s.x + 8, y, s.w - 16, 4)
  end
end

function DRAW.tunnel(s)
  box(s.x - 18, s.y, s.w + 36, s.h, C.gunmetal) -- the portal's frame
  hazard(s.x - 18, s.y + s.h - 14, s.w + 36, 14)
  color(INK)
  love.graphics.rectangle("fill", s.x + 6, s.y, s.w - 12, s.h - 16)
end

--- Painted safety lines: two yellow edge lines with the walkway between.
function DRAW.walkway(s)
  color(C.yellow, 0.9)
  love.graphics.rectangle("fill", s.x, s.y, 8, s.h)
  love.graphics.rectangle("fill", s.x + s.w - 8, s.y, 8, s.h)
  color(C.yellow, 0.55)
  for y = s.y + 40, s.y + s.h - 40, 160 do -- arrows up it: the way out
    love.graphics.polygon("fill", s.x + s.w / 2, y, s.x + s.w / 2 + 22, y + 30, s.x + s.w / 2 - 22, y + 30)
  end
end

function DRAW.zebra(s)
  for x = s.x, s.x + s.w - 20, 40 do
    color(C.paintWhite, 0.85)
    love.graphics.rectangle("fill", x, s.y, 20, s.h)
  end
end

local paintFonts = {}
function DRAW.paint(s)
  local size = s.small and 22 or 30
  paintFonts[size] = paintFonts[size] or love.graphics.newFont(size)
  love.graphics.setFont(paintFonts[size])
  color(C.yellow, 0.85)
  love.graphics.printf(s.text or "", s.x, s.y + (s.h - size) / 2, s.w, "center")
end

--- A lane's painted line: yellow dashes.
function DRAW.laneline(s)
  color(C.yellow, 0.7)
  local along = s.w >= s.h
  for a = 0, (along and s.w or s.h) - 24, 48 do
    if along then
      love.graphics.rectangle("fill", s.x + a, s.y, 28, s.h)
    else
      love.graphics.rectangle("fill", s.x, s.y + a, s.w, 28)
    end
  end
end

--- A ship's hull from above, `s` its bounds, its bow at the right: red
--- sides, a grey deck, hatches in a row, and its bridge at the stern.
local function hullShape(s, fill, dark)
  local nose = math.min(s.h * 0.9, s.w * 0.15)
  local pts = { s.x, s.y, s.x + s.w - nose, s.y, s.x + s.w, s.y + s.h / 2, s.x + s.w - nose, s.y + s.h, s.x,
    s.y + s.h }
  color(INK)
  love.graphics.polygon("fill", pts[1] - LINE, pts[2] - LINE, pts[3], pts[4] - LINE, pts[5] + LINE, pts[6], pts[7],
    pts[8] + LINE, pts[9] - LINE, pts[10] + LINE)
  color(fill)
  love.graphics.polygon("fill", pts)
  color(dark)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - nose - 24, s.h - 32)
  return nose
end

--- The freighter moored along the quay: most of it past the map's top.
function DRAW.ship(s)
  local nose = hullShape(s, C.hull, C.deck)
  for x = s.x + 160, s.x + s.w - nose - 120, 150 do -- hatch covers, some open
    box(x, s.y + 40, 110, s.h - 80, hash(x) < 0.3 and INK or C.containers[1 + math.floor(hash(x * 3) * 4)])
  end
  box(s.x + 30, s.y + 30, 90, s.h - 60, C.paintWhite) -- the bridge
  color(C.window)
  love.graphics.rectangle("fill", s.x + 108, s.y + 40, 8, s.h - 80)
end

--- The dry dock: a deep basin, its stepped walls going down, a little
--- water frozen at the bottom and a rusting hull sat on blocks in it.
function DRAW.drydock(s)
  box(s.x, s.y, s.w, s.h, C.pitWall)
  for i = 1, 3 do
    local inset = i * 18
    color(i == 3 and C.dockWater or C.pitDeep, i == 3 and 1 or 0.5)
    love.graphics.rectangle("fill", s.x + inset, s.y + inset, s.w - 2 * inset, s.h - 2 * inset)
  end
  -- The hull, bow north, rusted, on its blocks.
  local hw, hl = s.w * 0.55, s.h * 0.82
  love.graphics.push()
  love.graphics.translate(s.x + s.w / 2, s.y + s.h / 2)
  love.graphics.rotate(-math.pi / 2)
  hullShape({ x = -hl / 2, y = -hw / 2, w = hl, h = hw }, C.rust, C.hullDark)
  love.graphics.pop()
  hazard(s.x, s.y, s.w, 12)
  hazard(s.x, s.y + s.h - 12, s.w, 12)
  hazard(s.x, s.y, 12, s.h)
  hazard(s.x + s.w - 12, s.y, 12, s.h)
end

--- A gantry crane's foot on the quay (the crane is overhead: works.lua).
function DRAW.foot(s)
  box(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.2, 8)
end

function DRAW.cone(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(INK)
  love.graphics.rectangle("fill", cx - 9, cy - 9, 18, 18)
  color(C.cone)
  love.graphics.circle("fill", cx, cy, 7, 10)
  color(C.paintWhite)
  love.graphics.circle("fill", cx, cy, 3, 8)
end

function DRAW.drum(s)
  blob(s.x, s.y, s.w, s.h, C.drum)
  color(INK, 0.6)
  love.graphics.circle("line", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.3, 14)
end

--- A shed: a corrugated roof in Hyperbole's colours, the H on it, and a
--- loading door on the side facing the yard.
function DRAW.shed(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.gunmetal)
  for y = s.y + 10, s.y + s.h - 6, 14 do
    love.graphics.rectangle("fill", s.x, y, s.w, 4)
  end
  color(C.yellow)
  love.graphics.rectangle("fill", s.x, s.y, s.w, 10)
  local cx, cy, k = s.x + s.w / 2, s.y + s.h / 2, math.min(s.w, s.h) * 0.18
  love.graphics.rectangle("fill", cx - k, cy - k, k * 0.4, 2 * k) -- the H
  love.graphics.rectangle("fill", cx + k * 0.6, cy - k, k * 0.4, 2 * k)
  love.graphics.rectangle("fill", cx - k, cy - k * 0.2, 2 * k, k * 0.4)
  local west = s.x < 0 -- the yard is towards the middle of the map
  hazard(west and s.x + s.w - 14 or s.x, s.y + s.h * 0.3, 14, s.h * 0.4)
end

--- A deep excavation: a hazard-striped lip, the walls stepping down into
--- the dark, a puddle and rubble at the bottom, a railing round the top.
function DRAW.pit(s)
  box(s.x, s.y, s.w, s.h, C.pitWall)
  for i = 1, 4 do -- the steps down, each darker and further in
    local inset = i * 22
    local k = i / 5
    love.graphics.setColor(C.pitWall[1] * (1 - k) + C.pitDeep[1] * k, C.pitWall[2] * (1 - k) + C.pitDeep[2] * k,
      C.pitWall[3] * (1 - k) + C.pitDeep[3] * k)
    love.graphics.rectangle("fill", s.x + inset, s.y + inset, s.w - 2 * inset, s.h - 2 * inset)
  end
  local h = hash(s.seed or 1)
  color(C.window, 0.7) -- a puddle down there, catching the light
  love.graphics.ellipse("fill", s.x + s.w * (0.35 + h * 0.3), s.y + s.h * 0.6, s.w * 0.12, s.h * 0.06, 16)
  color(C.rock)
  for i = 1, 5 do
    love.graphics.circle("fill", s.x + s.w * (0.3 + hash(h + i) * 0.4), s.y + s.h * (0.3 + hash(h * 3 + i) * 0.4),
      6 + hash(i + h) * 8, 8)
  end
  -- The lip, hazard striped, and the railing posts round it.
  hazard(s.x, s.y, s.w, 12)
  hazard(s.x, s.y + s.h - 12, s.w, 12)
  hazard(s.x, s.y, 12, s.h)
  hazard(s.x + s.w - 12, s.y, 12, s.h)
  color(C.yellow)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle("line", s.x - 14, s.y - 14, s.w + 28, s.h + 28)
  love.graphics.setLineWidth(1)
  color(INK)
  for x = s.x - 14, s.x + s.w + 14, 64 do
    love.graphics.circle("fill", x, s.y - 14, 5, 8)
    love.graphics.circle("fill", x, s.y + s.h + 14, 5, 8)
  end
  for y = s.y - 14, s.y + s.h + 14, 64 do
    love.graphics.circle("fill", s.x - 14, y, 5, 8)
    love.graphics.circle("fill", s.x + s.w + 14, y, 5, 8)
  end
end

--- A crane's mast foot (the crane itself turns overhead: borderline/works.lua).
function DRAW.mast(s)
  box(s.x, s.y, s.w, s.h, C.gunmetal)
  color(C.yellow)
  love.graphics.setLineWidth(5)
  love.graphics.line(s.x, s.y, s.x + s.w, s.y + s.h)
  love.graphics.line(s.x + s.w, s.y, s.x, s.y + s.h)
  love.graphics.setLineWidth(1)
end

--- A floodlight tower's foot.
function DRAW.flood(s)
  blob(s.x, s.y, s.w, s.h, C.gunmetal)
  color(C.paintWhite)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.25, 10)
end

--- Map `map` into the canvas (city-map's Render.build, at half size): the
--- outside and floors, their edges, then the flat things, the shadows and
--- whatever stands.
function RenderBorderline.draw(map, T)
  local before = love.graphics.getFont()
  drawTiles(map, T)
  for _, s in ipairs(map.cover) do
    if s.flat and DRAW[s.kind] then
      DRAW[s.kind](s)
    end
  end
  drawEdges(map, T)
  color(C.shadow)
  for _, s in ipairs(map.cover) do
    if not s.flat and not s.water then
      if s.round then
        love.graphics.ellipse("fill", s.x + s.w / 2 + 12, s.y + s.h / 2 + 12, s.w / 2, s.h / 2)
      else
        love.graphics.rectangle("fill", s.x + 12, s.y + 12, s.w, s.h)
      end
    end
  end
  for _, s in ipairs(map.cover) do
    if not s.flat and DRAW[s.kind] then
      DRAW[s.kind](s)
    end
  end
  love.graphics.setFont(before)
  love.graphics.setColor(1, 1, 1)
end

return RenderBorderline
