-- Drawing Grey City's five maps (cyber_feud.lua) into the map canvas: wet
-- dark ground, grey roofs, neon signs and everything standing about. Drawn
-- once, lit as if by day; the night feature darkens it every frame and
-- lights it again where `map.lights` glow, so the neon here is what shows
-- through.

local Buildings = require("src.features.city-map.buildings")

local RenderCyberFeud = {}

local C = {
  beyond = { 0.22, 0.23, 0.26 }, -- the roofs of the city past the edge
  beyondDark = { 0.17, 0.18, 0.21 },
  abyss = { 0.03, 0.04, 0.06 }, -- the drop off the overpass
  asphalt = { 0.24, 0.25, 0.28 },
  asphaltWet = { 0.30, 0.33, 0.40 },
  lane = { 0.62, 0.56, 0.30 },
  edge = { 0.58, 0.60, 0.62 },
  walk = { 0.40, 0.41, 0.44 },
  walkLine = { 0.33, 0.34, 0.37 },
  kerb = { 0.34, 0.35, 0.37 },
  floor = { 0.42, 0.43, 0.47 }, -- the tower's floors
  floorLine = { 0.37, 0.38, 0.42 },
  slab = { 0.12, 0.13, 0.15 },
  glass = { 0.16, 0.22, 0.30 },
  roof = { 0.42, 0.43, 0.45 },
  parapet = { 0.55, 0.56, 0.58 },
  market = { 0.36, 0.35, 0.36 },
  steel = { 0.42, 0.45, 0.48 },
  steelDark = { 0.26, 0.28, 0.31 },
  barrier = { 0.78, 0.79, 0.80 },
  rust = { 0.42, 0.24, 0.14 },
  screen = { 0.03, 0.05, 0.04 },
  wood = { 0.30, 0.22, 0.16 },
  marble = { 0.82, 0.82, 0.84 },
  plant = { 0.14, 0.30, 0.18 },
  shadow = { 0, 0, 0, 0.4 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local font = nil
local function signFont()
  font = font or love.graphics.newFont(13)
  return font
end

-- Ground ---------------------------------------------------------------------

local function drawGround(map, T)
  local kindBeyond = map.kind == "overpass" and C.abyss or map.kind == "tower" and C.slab or C.beyond
  color(kindBeyond)
  love.graphics.rectangle("fill", map.left - 400, map.top - 400, map.w + 800, map.h + 800)
  local walk = map.kind == "tower" and C.floor or map.kind == "roof" and C.roof
    or map.kind == "market" and C.market or C.walk
  local line = map.kind == "tower" and C.floorLine or C.walkLine
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      local kind = col and col[r]
      local x, y = map.x0 + c * T, map.y0 + r * T
      local h = hash(c * 7.1 + r * 13.7)
      if kind == "road" then
        color(C.asphalt)
        love.graphics.rectangle("fill", x, y, T, T)
      elseif kind == "walk" then
        color(walk)
        love.graphics.rectangle("fill", x, y, T, T)
        color(line) -- the joints along its top and left, filled: lines alias on the half-size canvas
        love.graphics.rectangle("fill", x, y, T, 2)
        love.graphics.rectangle("fill", x, y, 2, T)
      elseif map.kind == "drop" or map.kind == "market" then
        -- The city past the edge: roofs, a little lighter or darker each.
        color(h < 0.5 and C.beyond or C.beyondDark)
        love.graphics.rectangle("fill", x, y, T, T)
      end
      -- Puddles, where the rain sits.
      if (kind == "road" or kind == "walk") and h > 0.86 and map.kind ~= "tower" then
        local px, py = x + 16 + h * 30, y + 14 + hash(h * 31) * 30
        color(C.asphaltWet, 0.9)
        love.graphics.ellipse("fill", px, py, 14 + h * 16, 6 + h * 6, 12)
        love.graphics.setColor(0.5, 0.6, 0.75, 0.18)
        love.graphics.ellipse("line", px, py, 14 + h * 16, 6 + h * 6, 12)
      end
    end
  end
end

--- Is (c, r) road? For breaking the lane lines at crossings.
local function isRoad(map, c, r)
  local col = map.tiles[c]
  return col and col[r] == "road"
end

local function drawRoadLines(map, T)
  for _, rd in ipairs(map.roads) do
    if rd.along == "pad" then
      -- An open interchange: diagonal hatching round its edge.
      love.graphics.setColor(C.lane[1], C.lane[2], C.lane[3], 0.35)
      love.graphics.setLineWidth(6)
      love.graphics.rectangle("line", rd.x + 24, rd.y + 24, rd.w - 48, rd.h - 48)
      love.graphics.setLineWidth(1)
    else
      local ns = rd.along == "ns"
      local len = ns and rd.h or rd.w
      local span = ns and rd.w or rd.h
      local lanes = math.max(2, math.floor(span / 96 + 0.5))
      for s = 0, len - 1, T do
        -- Leave a crossing clear: the tile either side across the road is road too.
        local c0 = ns and math.floor((rd.x - map.x0) / T) - 1 or math.floor((rd.x + s - map.x0) / T)
        local r0 = ns and math.floor((rd.y + s - map.y0) / T) or math.floor((rd.y - map.y0) / T) - 1
        local c1 = ns and math.floor((rd.x + rd.w - map.x0) / T) or c0
        local r1 = ns and r0 or math.floor((rd.y + rd.h - map.y0) / T)
        if not (isRoad(map, c0, r0) and isRoad(map, c1, r1)) then
          for k = 1, lanes - 1 do
            local a = span * k / lanes
            local middle = k == lanes / 2
            color(middle and C.lane or C.edge, middle and 0.7 or 0.4)
            if ns then
              love.graphics.rectangle("fill", rd.x + a - 2, rd.y + s + 12, 4, 30)
            else
              love.graphics.rectangle("fill", rd.x + s + 12, rd.y + a - 2, 30, 4)
            end
          end
          color(C.edge, 0.45)
          if ns then
            love.graphics.rectangle("fill", rd.x + 6, rd.y + s, 3, T)
            love.graphics.rectangle("fill", rd.x + rd.w - 9, rd.y + s, 3, T)
          else
            love.graphics.rectangle("fill", rd.x + s, rd.y + 6, T, 3)
            love.graphics.rectangle("fill", rd.x + s, rd.y + rd.h - 9, T, 3)
          end
        end
      end
    end
  end
end

-- What stands about --------------------------------------------------------------

local function box(s, c, inset)
  inset = inset or 0
  color(c)
  love.graphics.rectangle("fill", s.x + inset, s.y + inset, s.w - inset * 2, s.h - inset * 2)
end

local DRAW = {}

function DRAW.barrier(s)
  box(s, C.barrier)
  love.graphics.setColor(1, 0.24, 0.78, 0.9)
  if s.w > s.h then
    love.graphics.rectangle("fill", s.x, s.y + s.h / 2 - 2, s.w, 4)
  else
    love.graphics.rectangle("fill", s.x + s.w / 2 - 2, s.y, 4, s.h)
  end
end

--- A guard station's house (cyber_feud.lua's guardStation): Halcyon's a
--- clean grey box with a white roof slab, the Static's rusted sheet metal;
--- a strip in the side's colour and the door on the face to the avenue.
function DRAW.station(s)
  local halcyon = s.faction == "halcyon"
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 10, s.y + 10, s.w, s.h, 3)
  color(halcyon and { 0.46, 0.48, 0.52 } or C.rust)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 3)
  if halcyon then
    color({ 0.84, 0.85, 0.88 })
    love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, s.h - 16, 2)
  else
    color({ 0.30, 0.17, 0.10 }) -- the sheets' ridges
    for x = s.x + 6, s.x + s.w - 6, 10 do
      love.graphics.rectangle("fill", x, s.y + 4, 3, s.h - 8)
    end
  end
  local front = s.face > 0 and s.x + s.w - 6 or s.x + 2
  if halcyon then
    love.graphics.setColor(1, 0.24, 0.78, 0.95)
  else
    love.graphics.setColor(0.18, 0.9, 1, 0.95)
  end
  love.graphics.rectangle("fill", front, s.y + 6, 4, s.h - 12)
  color({ 0.06, 0.07, 0.08 }) -- the door
  love.graphics.rectangle("fill", s.face > 0 and s.x + s.w - 4 or s.x, s.y + s.h / 2 - 20, 4, 40)
end

--- The emplacement round a station's MG nest (the gun is drawn live,
--- a-man/nests.lua): Halcyon's concrete blocks striped magenta, the
--- Static's stacked tyres.
local function drawNestBase(n, faction)
  local reach = n.arc + math.rad(35)
  local steps = 8
  for k = 0, steps do
    local a = n.angle - reach + k * 2 * reach / steps
    local bx, by = n.x + math.cos(a) * 30, n.y + math.sin(a) * 30
    if faction == "halcyon" then
      love.graphics.push()
      love.graphics.translate(bx, by)
      love.graphics.rotate(a + math.pi / 2)
      color(C.shadow)
      love.graphics.rectangle("fill", -8, -3, 16, 10, 2)
      color({ 0.70, 0.71, 0.73 })
      love.graphics.rectangle("fill", -10, -5, 17, 9, 2)
      love.graphics.setColor(1, 0.24, 0.78, 0.9)
      love.graphics.rectangle("fill", -10, -1.5, 17, 2)
      love.graphics.pop()
    else
      color(C.shadow)
      love.graphics.circle("fill", bx + 2, by + 3, 8, 12)
      color({ 0.08, 0.08, 0.09 })
      love.graphics.circle("fill", bx, by, 8, 12)
      color({ 0.20, 0.20, 0.22 })
      love.graphics.circle("fill", bx, by, 3.5, 10)
    end
  end
end

function DRAW.wreck(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w, s.h, 8)
  color(s.color or C.rust)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 8)
  color({ 0.06, 0.07, 0.08 })
  love.graphics.rectangle("fill", s.x + 5, s.y + s.h * 0.22, s.w - 10, s.h * 0.2, 3)
  love.graphics.rectangle("fill", s.x + 5, s.y + s.h * 0.62, s.w - 10, s.h * 0.14, 3)
end

function DRAW.drum(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.rust)
  love.graphics.circle("fill", cx, cy, r, 16)
  love.graphics.setColor(1, 0.55, 0.15)
  love.graphics.circle("fill", cx, cy, r * 0.6, 12)
  love.graphics.setColor(1, 0.9, 0.5)
  love.graphics.circle("fill", cx, cy, r * 0.28, 8)
end

function DRAW.vending(s)
  box(s, { 0.10, 0.12, 0.12 })
  love.graphics.setColor(0.43, 1, 0.6)
  love.graphics.rectangle("fill", s.x + 4, s.y + 4, s.w - 8, s.h * 0.55)
  love.graphics.setColor(0.05, 0.2, 0.1)
  for i = 0, 2 do
    love.graphics.rectangle("fill", s.x + 7, s.y + 8 + i * 6, s.w - 14, 3)
  end
end

function DRAW.stall(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w, s.h)
  color(s.color)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  -- The canopy's stripes, and a seam where it dips.
  local k = 1.35
  love.graphics.setColor(math.min(1, s.color[1] * k), math.min(1, s.color[2] * k), math.min(1, s.color[3] * k))
  for x = s.x, s.x + s.w - 16, 32 do
    love.graphics.rectangle("fill", x, s.y, 16, s.h)
  end
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", s.x, s.y + s.h / 2 - 2, s.w, 4)
  love.graphics.rectangle("line", s.x + 0.5, s.y + 0.5, s.w - 1, s.h - 1)
end

function DRAW.screen(s)
  box(s, C.screen)
  love.graphics.setColor(0.43, 1, 0.6, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", s.x + 2, s.y + 2, s.w - 4, s.h - 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.43, 1, 0.6, 0.35)
  for x = s.x + 8, s.x + s.w - 8, 6 do
    love.graphics.rectangle("fill", x, s.y + 6, 3, s.h - 12)
  end
end

function DRAW.desk(s)
  box(s, C.wood)
  love.graphics.setColor(0.08, 0.09, 0.1)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 12, s.y + 4, 24, 10)
  love.graphics.setColor(0.6, 0.85, 1, 0.8)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 10, s.y + 5, 20, 7)
end

function DRAW.rack(s)
  box(s, { 0.06, 0.06, 0.07 })
  for i = 0, math.floor(s.w / 12) - 1 do
    local h = hash(s.x * 0.37 + i)
    if h > 0.35 then
      if h > 0.7 then
        love.graphics.setColor(0.43, 1, 0.6)
      else
        love.graphics.setColor(0.18, 0.9, 1)
      end
      love.graphics.rectangle("fill", s.x + 6 + i * 12, s.y + 8 + (h * 100 % 3) * 7, 3, 3)
    end
  end
end

function DRAW.tank(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 24)
  love.graphics.setColor(0.35, 0.18, 0.40, 0.9)
  love.graphics.circle("fill", cx, cy, r - 6, 24)
  love.graphics.setColor(0.75, 0.70, 0.68, 0.8) -- someone spare, curled up inside
  love.graphics.circle("fill", cx, cy - 4, 8, 12)
  love.graphics.ellipse("fill", cx, cy + 9, 10, 13, 12)
  love.graphics.setColor(1, 1, 1, 0.25)
  love.graphics.circle("line", cx, cy, r - 6, 24)
end

function DRAW.table(s)
  box(s, { 0.12, 0.10, 0.10 })
  box(s, { 0.20, 0.15, 0.13 }, 6)
  love.graphics.setColor(0.08, 0.08, 0.09)
  for x = s.x + 40, s.x + s.w - 40, 80 do
    love.graphics.circle("fill", x, s.y - 14, 12, 12)
    love.graphics.circle("fill", x, s.y + s.h + 14, 12, 12)
  end
end

function DRAW.reception(s)
  box(s, C.marble)
  love.graphics.setColor(1, 0.24, 0.78, 0.8)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 6, s.w, 4)
end

function DRAW.lift(s)
  box(s, C.steelDark)
  box(s, C.steel, 6)
  love.graphics.setColor(0.15, 0.16, 0.18)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 1, s.y + 6, 2, s.h - 12)
end

function DRAW.planter(s)
  box(s, C.steelDark)
  color(C.plant)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w / 2 - 4, 12)
end

function DRAW.relay(s)
  box(s, C.steelDark)
  box(s, { 0.12, 0.14, 0.13 }, 6)
  love.graphics.setColor(0.43, 1, 0.6)
  love.graphics.rectangle("fill", s.x + 14, s.y + 14, s.w - 28, s.h - 28)
end

function DRAW.ac(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w, s.h)
  box(s, C.steel)
  love.graphics.setColor(0.2, 0.21, 0.23)
  for x = s.x + s.h / 2, s.x + s.w - 1, s.h do
    love.graphics.circle("fill", x, s.y + s.h / 2, s.h / 2 - 8, 16)
  end
end

function DRAW.mast(s)
  box(s, C.steelDark)
  love.graphics.setColor(0.5, 0.52, 0.55)
  love.graphics.line(s.x, s.y, s.x + s.w, s.y + s.h)
  love.graphics.line(s.x + s.w, s.y, s.x, s.y + s.h)
end

function DRAW.gantry(s)
  box(s, C.steelDark)
  love.graphics.setColor(0.5, 0.52, 0.55)
  for x = s.x, s.x + s.w - 24, 24 do
    love.graphics.line(x, s.y, x + 24, s.y + s.h)
  end
  love.graphics.setColor(1, 0.24, 0.78, 0.8)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 50, s.y + 6, 100, s.h - 12)
end

function DRAW.door(s)
  love.graphics.setColor(0.43, 1, 0.6, 0.85)
  love.graphics.setLineWidth(4)
  love.graphics.line(s.x, s.y, s.x + s.w, s.y)
  love.graphics.line(s.x, s.y + s.h, s.x + s.w, s.y + s.h)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.07, 0.08, 0.09)
  for y = s.y + 8, s.y + s.h - 8, 10 do -- the steps
    love.graphics.rectangle("fill", s.x + 6, y, s.w - 12, 3)
  end
end

function DRAW.tunnel(s)
  for i = 0, 7 do
    love.graphics.setColor(0, 0, 0, 0.35 + i * 0.08)
    love.graphics.rectangle("fill", s.x, s.y, s.w, s.h - i * s.h / 8)
  end
  love.graphics.setColor(0.4, 0.42, 0.45)
  love.graphics.setLineWidth(10)
  love.graphics.line(s.x - 10, s.y + s.h, s.x + s.w + 10, s.y + s.h)
  love.graphics.setLineWidth(1)
end

function DRAW.dock(s)
  box(s, { 0.16, 0.16, 0.17 })
  love.graphics.setColor(0.9, 0.75, 0.2, 0.8)
  for x = s.x, s.x + s.w - 20, 40 do
    love.graphics.polygon("fill", x, s.y + s.h - 14, x + 20, s.y + s.h - 14, x + 30, s.y + s.h, x + 10, s.y + s.h)
  end
end

function DRAW.billboard(s)
  box(s, { 0.05, 0.06, 0.06 })
  love.graphics.setColor(0.43, 1, 0.6, 0.85)
  love.graphics.setLineWidth(4)
  love.graphics.rectangle("line", s.x + 3, s.y + 3, s.w - 6, s.h - 6)
  love.graphics.setLineWidth(1)
end

-- Signs and the rest --------------------------------------------------------------

local function drawSigns(map)
  local f = signFont()
  love.graphics.setFont(f)
  for _, s in ipairs(map.signs) do
    love.graphics.setColor(0.04, 0.04, 0.05)
    love.graphics.rectangle("fill", s.x - 3, s.y - 3, s.w + 6, s.h + 6)
    love.graphics.setColor(s.color)
    love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
    love.graphics.setColor(s.color[1], s.color[2], s.color[3], 0.9)
    local tw = f:getWidth(s.text)
    if s.w >= s.h then
      if tw < s.w then
        local y = s.side == "s" and s.y - f:getHeight() - 4 or s.y + s.h + 4
        love.graphics.print(s.text, math.floor(s.x + (s.w - tw) / 2), math.floor(y))
      end
    elseif tw < s.h then
      local x = s.side == "e" and s.x - 4 or s.x + s.w + 4 + f:getHeight()
      local rot = s.side == "e" and -math.pi / 2 or math.pi / 2
      local y = s.side == "e" and s.y + (s.h + tw) / 2 or s.y + (s.h - tw) / 2
      love.graphics.print(s.text, math.floor(x), math.floor(y), rot)
    end
  end
end

--- The tower's outside walls: glass all the way up, the city behind it.
local function drawCurtainWall(map, T)
  color(C.glass)
  love.graphics.rectangle("fill", map.left + T * 1.5, map.top, T * 0.5, map.h)
  love.graphics.rectangle("fill", map.left + map.w - T * 2, map.top, T * 0.5, map.h)
  love.graphics.setColor(0.4, 0.5, 0.6, 0.6)
  for y = map.top, map.top + map.h, T do
    love.graphics.rectangle("fill", map.left + T * 1.5, y, T * 0.5, 2)
    love.graphics.rectangle("fill", map.left + map.w - T * 2, y, T * 0.5, 2)
  end
end

--- The roof's parapet, round the edge.
local function drawParapet(map, T)
  color(C.parapet)
  love.graphics.setLineWidth(20)
  love.graphics.rectangle("line", map.left + T * 2 - 10, map.top + T * 2 - 10, map.w - T * 4 + 20, map.h - T * 4 + 20)
  love.graphics.setLineWidth(1)
  local p = map.helipad
  love.graphics.setColor(0.85, 0.85, 0.8, 0.8)
  love.graphics.setLineWidth(8)
  love.graphics.circle("line", p.x, p.y, p.r, 48)
  love.graphics.line(p.x - 50, p.y - 70, p.x - 50, p.y + 70)
  love.graphics.line(p.x + 50, p.y - 70, p.x + 50, p.y + 70)
  love.graphics.line(p.x - 50, p.y, p.x + 50, p.y)
  love.graphics.setLineWidth(1)
end

--- Draw `map` (one of cyber_feud.lua's) into the canvas, `T` the tile size.
function RenderCyberFeud.draw(map, T)
  drawGround(map, T)
  for _, b in ipairs(map.below or {}) do
    love.graphics.setColor(b.color[1], b.color[2], b.color[3], 0.8)
    love.graphics.circle("fill", b.x, b.y, b.r, 6)
  end
  drawRoadLines(map, T)
  if map.kind == "tower" then
    drawCurtainWall(map, T)
  elseif map.kind == "roof" then
    drawParapet(map, T)
  end
  -- Flat things first, then what stands up, so shadows fall on the ground.
  for _, s in ipairs(map.cover) do
    if s.kind == "tunnel" or s.kind == "dock" or s.kind == "door" then
      DRAW[s.kind](s)
    end
  end
  color(C.shadow)
  for _, b in ipairs(map.buildings) do
    love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
  end
  Buildings.draw(map)
  for _, s in ipairs(map.cover) do
    local draw = DRAW[s.kind]
    if draw and s.kind ~= "tunnel" and s.kind ~= "dock" and s.kind ~= "door" then
      draw(s)
    end
  end
  for _, n in ipairs(map.nests or {}) do
    drawNestBase(n.nest, n.faction)
  end
  drawSigns(map)
  love.graphics.setColor(1, 1, 1)
end

return RenderCyberFeud
