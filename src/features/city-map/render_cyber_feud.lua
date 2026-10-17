-- Drawing Grey City's five maps (cyber_feud.lua) into the map canvas: wet
-- dark ground, grey roofs, neon signs and everything standing about. Drawn
-- once, lit as if by day; the night feature darkens it every frame and
-- lights it again where `map.lights` glow, so the neon here is what shows
-- through.

local Buildings = require("src.features.city-map.buildings")
local Shade = require("src.features.city-map.shade")

local RenderCyberFeud = {}

local C = {
  beyond = { 0.22, 0.23, 0.26 }, -- the roofs of the city past the edge
  beyondDark = { 0.17, 0.18, 0.21 },
  girder = { 0.30, 0.32, 0.35 }, -- the overpass's steel
  girderLight = { 0.52, 0.55, 0.58 },
  rail = { 0.70, 0.72, 0.74 },
  pier = { 0.36, 0.36, 0.38 },
  pierTop = { 0.46, 0.46, 0.48 },
  cable = { 0.78, 0.80, 0.84 },
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

-- Halcyon Tower's floors, each its own finish, by name (CyberFeud.FLOORS):
-- a base, a second colour, and the pattern they make.
local FLOORS = {
  Lobby = { { 0.60, 0.60, 0.64 }, { 0.50, 0.50, 0.55 }, "checker" }, -- marble
  Offices = { { 0.28, 0.31, 0.38 }, { 0.25, 0.28, 0.35 }, "carpet" },
  Servers = { { 0.21, 0.22, 0.25 }, { 0.14, 0.15, 0.17 }, "raised" }, -- raised floor, vented tiles
  Labs = { { 0.72, 0.74, 0.77 }, { 0.60, 0.63, 0.66 }, "tile" },
  Security = { { 0.34, 0.34, 0.36 }, { 0.28, 0.28, 0.30 }, "concrete" },
  Executive = { { 0.30, 0.21, 0.15 }, { 0.24, 0.16, 0.11 }, "planks" },
}

--- Which of the tower's floors (x, y) is on, as its finish, or nil.
local function floorAt(map, y)
  for _, f in ipairs(map.floors or {}) do
    if y >= f.y0 and y < f.y1 then
      return FLOORS[f.name]
    end
  end
  return nil
end

--- One tile (x, y) of a tower floor in `f`'s finish.
local function floorTile(f, x, y, T, h)
  local base, second, kind = f[1], f[2], f[3]
  local c, r = math.floor(x / T), math.floor(y / T)
  if kind == "checker" then
    color((c + r) % 2 == 0 and base or second)
    love.graphics.rectangle("fill", x, y, T, T)
    love.graphics.setColor(1, 1, 1, 0.06 + h * 0.05) -- a vein in the marble
    love.graphics.polygon("fill", x + h * T, y, x + h * T + 3, y, x + T * 0.3, y + T, x + T * 0.3 - 3, y + T)
  elseif kind == "carpet" then
    color(base)
    love.graphics.rectangle("fill", x, y, T, T)
    color(second)
    love.graphics.rectangle("fill", x + ((c + r) % 2) * T / 2, y, T / 2, T / 2)
    love.graphics.rectangle("fill", x + (1 - (c + r) % 2) * T / 2, y + T / 2, T / 2, T / 2)
  elseif kind == "raised" then
    color(base)
    love.graphics.rectangle("fill", x, y, T, T)
    color(second)
    love.graphics.rectangle("fill", x, y, T, 3)
    love.graphics.rectangle("fill", x, y, 3, T)
    if (c * 3 + r) % 4 == 0 then -- a vented tile
      for vx = x + 10, x + T - 10, 9 do
        for vy = y + 10, y + T - 10, 9 do
          love.graphics.rectangle("fill", vx, vy, 4, 4)
        end
      end
    end
  elseif kind == "tile" then
    color(base)
    love.graphics.rectangle("fill", x, y, T, T)
    color(second)
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
    love.graphics.rectangle("fill", x + T / 2, y, 2, T)
    love.graphics.rectangle("fill", x, y + T / 2, T, 2)
  elseif kind == "concrete" then
    color(base)
    love.graphics.rectangle("fill", x, y, T, T)
    color(second)
    for k = 0, 5 do
      local hx, hy = hash(x * 0.13 + k), hash(y * 0.17 + k * 3)
      love.graphics.rectangle("fill", x + hx * (T - 4), y + hy * (T - 4), 4, 4)
    end
  else -- planks
    color(base)
    love.graphics.rectangle("fill", x, y, T, T)
    color(second)
    for k = 0, 3 do
      love.graphics.rectangle("fill", x, y + k * T / 4, T, 2)
      local joint = (hash(c * 5.3 + r * 1.7 + k) * T)
      love.graphics.rectangle("fill", x + joint, y + k * T / 4, 2, T / 4)
    end
  end
end

local function drawGround(map, T)
  if map.kind == "tower" then
    -- The tower itself, its slabs between the floors; outside its glass
    -- is the city far below (left clear for surroundings).
    color(C.slab)
    love.graphics.rectangle("fill", map.left + T * 2, map.top, map.w - T * 4, map.h)
    love.graphics.setColor(0.20, 0.21, 0.24)
    for y = map.top, map.top + map.h, T / 2 do -- the slab's layers, cut through
      love.graphics.rectangle("fill", map.left + T * 2, y, map.w - T * 4, 3)
    end
  elseif map.kind == "roof" then
    -- The tower's top: its slab out to the parapet; past it the drop to
    -- the city far below (surroundings).
    color(C.slab)
    love.graphics.rectangle("fill", map.left + T * 1.5, map.top + T * 1.5, map.w - T * 3, map.h - T * 3)
  elseif map.kind ~= "overpass" then -- off the overpass is a long way down: left clear for surroundings' city below
    color(C.beyond)
    love.graphics.rectangle("fill", map.left - 400, map.top - 400, map.w + 800, map.h + 800)
  end
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
      elseif kind == "walk" and map.kind == "tower" and floorAt(map, y) then
        floorTile(floorAt(map, y), x, y, T, h)
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
  -- Its chair, pushed in under the south side.
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h + 10, 11, 12)
  love.graphics.setColor(0.20, 0.20, 0.24)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 10, s.y + s.h + 14, 20, 6, 2)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w, s.h)
  box(s, C.wood)
  love.graphics.setColor(0.08, 0.09, 0.1)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 12, s.y + 4, 24, 10)
  love.graphics.setColor(0.6, 0.85, 1, 0.8)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 10, s.y + 5, 20, 7)
  love.graphics.setColor(0.15, 0.15, 0.17) -- the keyboard
  love.graphics.rectangle("fill", s.x + s.w / 2 - 12, s.y + s.h - 14, 24, 7)
  local h = hash(s.x + s.y * 0.3)
  love.graphics.setColor(0.88, 0.88, 0.84) -- papers
  love.graphics.rectangle("fill", s.x + 8 + h * 12, s.y + 10, 14, 18)
  if h > 0.5 then
    love.graphics.setColor(0.85, 0.30, 0.30) -- a mug
    love.graphics.circle("fill", s.x + s.w - 14, s.y + s.h - 12, 5, 10)
  end
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

-- Halcyon Tower's dressing (cyber_feud.lua's dressTower) ------------------------

local MAGENTA = { 1, 0.24, 0.78 }

--- A sofa: its seat, the back along the side away from `face` (1 faces
--- south, -1 north, 2 east) and an arm at each end.
function DRAW.sofa(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w, s.h, 6)
  local seat, back = { 0.26, 0.24, 0.30 }, { 0.20, 0.18, 0.24 }
  color(seat)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 6)
  color(back)
  if s.face == 2 then
    love.graphics.rectangle("fill", s.x, s.y, s.w * 0.35, s.h, 6)
  elseif s.face == -1 then
    love.graphics.rectangle("fill", s.x, s.y + s.h * 0.65, s.w, s.h * 0.35, 6)
  else
    love.graphics.rectangle("fill", s.x, s.y, s.w, s.h * 0.35, 6)
  end
  -- The cushions' seams.
  love.graphics.setColor(0.14, 0.13, 0.17)
  if s.w > s.h then
    for x = s.x + s.w / 3, s.x + s.w - 4, s.w / 3 do
      love.graphics.rectangle("fill", x - 1, s.y + 4, 2, s.h - 8)
    end
  else
    for y = s.y + s.h / 3, s.y + s.h - 4, s.h / 3 do
      love.graphics.rectangle("fill", s.x + 4, y - 1, s.w - 8, 2)
    end
  end
end

--- A low table: glass on a dark frame, a magazine and a cup on it.
function DRAW.coffee(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w, s.h, 4)
  love.graphics.setColor(0.10, 0.10, 0.12)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 4)
  love.graphics.setColor(0.45, 0.60, 0.70, 0.5)
  love.graphics.rectangle("fill", s.x + 4, s.y + 4, s.w - 8, s.h - 8, 3)
  love.graphics.setColor(0.85, 0.30, 0.55)
  love.graphics.rectangle("fill", s.x + s.w * 0.2, s.y + s.h * 0.25, 18, 14)
  love.graphics.setColor(0.92, 0.92, 0.9)
  love.graphics.circle("fill", s.x + s.w * 0.7, s.y + s.h * 0.5, 5, 10)
end

--- A rug in its `tint`, a darker band round it when it has a `border`.
function DRAW.rug(s)
  local t = s.tint or { 0.3, 0.2, 0.3 }
  color(t)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 4)
  if s.border then
    love.graphics.setColor(t[1] * 0.6, t[2] * 0.6, t[3] * 0.6)
    love.graphics.setLineWidth(6)
    love.graphics.rectangle("line", s.x + 10, s.y + 10, s.w - 20, s.h - 20, 3)
    love.graphics.setLineWidth(1)
  end
end

--- Halcyon's logo inlaid in the floor: a ring with a halo crescent in it.
function DRAW.logo(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  love.graphics.setColor(0.30, 0.30, 0.34)
  love.graphics.circle("fill", cx, cy, r, 40)
  love.graphics.setColor(0.86, 0.86, 0.90)
  love.graphics.circle("fill", cx, cy, r - 8, 40)
  color(MAGENTA)
  love.graphics.circle("fill", cx, cy, r * 0.62, 40)
  love.graphics.setColor(0.86, 0.86, 0.90)
  love.graphics.circle("fill", cx + r * 0.18, cy - r * 0.12, r * 0.52, 40)
  love.graphics.setColor(0.30, 0.30, 0.34)
  love.graphics.rectangle("fill", cx - r * 0.7, cy + r * 0.72, r * 1.4, 8)
end

--- A holo screen on a wall: a dark panel with bars of a chart lit on it.
function DRAW.holo(s)
  love.graphics.setColor(0.04, 0.06, 0.08)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 2)
  for i = 0, math.floor(s.w / 14) - 2 do
    local h = 0.3 + 0.7 * hash(s.x + i * 3.1)
    love.graphics.setColor(0.18, 0.9, 1, 0.8)
    love.graphics.rectangle("fill", s.x + 8 + i * 14, s.y + s.h - 4 - (s.h - 8) * h, 8, (s.h - 8) * h)
  end
end

--- Glass walls seen from above: a thin lit outline, a gap for the door
--- on its south side (`open` "s") or its east side otherwise.
function DRAW.glass(s)
  love.graphics.setColor(0.55, 0.75, 0.90, 0.14)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  love.graphics.setColor(0.70, 0.85, 1, 0.75)
  local t = 4
  love.graphics.rectangle("fill", s.x, s.y, s.w, t)
  love.graphics.rectangle("fill", s.x, s.y, t, s.h)
  if s.open == "s" then
    love.graphics.rectangle("fill", s.x + s.w - t, s.y, t, s.h)
    love.graphics.rectangle("fill", s.x, s.y + s.h - t, s.w * 0.35, t)
    love.graphics.rectangle("fill", s.x + s.w * 0.65, s.y + s.h - t, s.w * 0.35, t)
  else
    love.graphics.rectangle("fill", s.x, s.y + s.h - t, s.w, t)
    love.graphics.rectangle("fill", s.x + s.w - t, s.y, t, s.h * 0.35)
    love.graphics.rectangle("fill", s.x + s.w - t, s.y + s.h * 0.65, t, s.h * 0.35)
  end
end

function DRAW.cooler(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.shadow)
  love.graphics.circle("fill", cx + 4, cy + 4, s.w / 2, 16)
  love.graphics.setColor(0.85, 0.86, 0.88)
  love.graphics.circle("fill", cx, cy, s.w / 2, 16)
  love.graphics.setColor(0.35, 0.65, 0.95, 0.9)
  love.graphics.circle("fill", cx, cy, s.w / 2 - 6, 16)
end

function DRAW.printer(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w, s.h, 3)
  love.graphics.setColor(0.78, 0.79, 0.80)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 3)
  love.graphics.setColor(0.30, 0.31, 0.34)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w - 12, 10)
  love.graphics.setColor(0.43, 1, 0.6)
  love.graphics.rectangle("fill", s.x + s.w - 12, s.y + s.h - 10, 5, 5)
end

--- A potted plant: a round pot and leaves fanning out of it.
function DRAW.plant(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.shadow)
  love.graphics.circle("fill", cx + 5, cy + 5, r, 16)
  love.graphics.setColor(0.18, 0.18, 0.20)
  love.graphics.circle("fill", cx, cy, r, 16)
  for k = 0, 6 do
    local a = k * math.pi * 2 / 7
    love.graphics.setColor(0.16, 0.36 + 0.06 * (k % 2), 0.20)
    love.graphics.ellipse("fill", cx + math.cos(a) * r * 0.55, cy + math.sin(a) * r * 0.55, r * 0.55, r * 0.3, 10)
  end
  love.graphics.setColor(0.22, 0.46, 0.26)
  love.graphics.circle("fill", cx, cy, r * 0.35, 10)
end

--- A run of cables across a floor: a bundle in a tray, a few colours.
function DRAW.cables(s)
  love.graphics.setColor(0.10, 0.10, 0.11)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  for i, c in ipairs({ { 0.18, 0.9, 1 }, { 1, 0.86, 0.2 }, { 0.43, 1, 0.6 } }) do
    love.graphics.setColor(c[1], c[2], c[3], 0.7)
    love.graphics.rectangle("fill", s.x, s.y + i * 2, s.w, 2)
  end
end

--- Yellow and black hazard stripes: a filled box, or just round its edge (`outline`).
function DRAW.hazard(s)
  local band = 12
  local function stripes(x, y, w, h)
    love.graphics.setColor(0.95, 0.78, 0.15, 0.85)
    love.graphics.rectangle("fill", x, y, w, h)
    love.graphics.setColor(0.08, 0.08, 0.08, 0.85)
    local along = w > h
    for k = 0, (along and w or h) - 1, 24 do
      if along then
        love.graphics.rectangle("fill", x + k, y, 12, h)
      else
        love.graphics.rectangle("fill", x, y + k, w, 12)
      end
    end
  end
  if s.outline then
    stripes(s.x, s.y, s.w, band)
    stripes(s.x, s.y + s.h - band, s.w, band)
    stripes(s.x, s.y, band, s.h)
    stripes(s.x + s.w - band, s.y, band, s.h)
  else
    stripes(s.x, s.y, s.w, band)
    stripes(s.x, s.y + s.h - band, s.w, band)
  end
end

--- A lab bench: a steel top with kit on it (a screen, flasks, a microscope).
function DRAW.bench(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w, s.h, 3)
  love.graphics.setColor(0.62, 0.64, 0.67)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 3)
  love.graphics.setColor(0.08, 0.09, 0.10)
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, 22, 14)
  love.graphics.setColor(0.43, 1, 0.6, 0.85)
  love.graphics.rectangle("fill", s.x + 10, s.y + 10, 18, 10)
  for k = 0, 2 do
    local h = hash(s.x + s.y + k)
    love.graphics.setColor(h > 0.5 and 0.85 or 0.4, 0.35, h > 0.5 and 0.7 or 0.95, 0.8)
    love.graphics.circle("fill", s.x + s.w - 14 - k * 14, s.y + s.h - 14, 5, 10)
  end
end

--- Specimen cabinets: a row of glass-fronted doors, lit inside.
function DRAW.cabinet(s)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  for x = s.x + 4, s.x + s.w - 30, 30 do
    love.graphics.setColor(0.55, 0.30, 0.65, 0.7)
    love.graphics.rectangle("fill", x, s.y + 4, 26, s.h - 8)
  end
end

--- A row of lockers along a wall: grey doors with vents and a handle.
function DRAW.lockers(s)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  for x = s.x + 2, s.x + s.w - 20, 22 do
    love.graphics.setColor(0.44, 0.46, 0.50)
    love.graphics.rectangle("fill", x, s.y + 2, 20, s.h - 4)
    love.graphics.setColor(0.28, 0.30, 0.33)
    love.graphics.rectangle("fill", x + 4, s.y + 5, 12, 2)
    love.graphics.rectangle("fill", x + 4, s.y + 9, 12, 2)
    love.graphics.setColor(0.85, 0.85, 0.85)
    love.graphics.rectangle("fill", x + 15, s.y + s.h - 10, 3, 5)
  end
end

--- Paint on a floor: a yellow lane line.
function DRAW.paint(s)
  love.graphics.setColor(0.92, 0.78, 0.18, 0.75)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
end

--- A bar: a dark counter with a lit edge and bottles along it.
function DRAW.bar(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w, s.h, 3)
  love.graphics.setColor(0.10, 0.08, 0.08)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 3)
  love.graphics.setColor(1, 0.6, 0.3, 0.9)
  love.graphics.rectangle("fill", s.x, s.y, 4, s.h)
  for y = s.y + 10, s.y + s.h - 10, 18 do
    local h = hash(y)
    love.graphics.setColor(0.3 + h * 0.6, 0.6, 0.3 + (1 - h) * 0.5, 0.9)
    love.graphics.circle("fill", s.x + s.w * 0.6, y, 4, 8)
  end
end

function DRAW.stool(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  love.graphics.setColor(0.08, 0.08, 0.09)
  love.graphics.circle("fill", cx, cy, s.w / 2, 12)
  love.graphics.setColor(0.45, 0.20, 0.30)
  love.graphics.circle("fill", cx, cy, s.w / 2 - 4, 12)
end

--- Bookshelves along a wall: rows of spines in muted colours.
function DRAW.shelf(s)
  love.graphics.setColor(0.20, 0.14, 0.10)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  for x = s.x + 3, s.x + s.w - 6, 6 do
    local h = hash(x * 0.7)
    love.graphics.setColor(0.25 + h * 0.4, 0.2 + hash(x) * 0.25, 0.18 + (1 - h) * 0.3)
    love.graphics.rectangle("fill", x, s.y + 3 + h * 6, 5, s.h - 6 - h * 6)
  end
end

--- A painting on a wall, seen edge on from above: a frame and a smear of colour.
function DRAW.art(s)
  love.graphics.setColor(0.70, 0.58, 0.30)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  local h = hash(s.x)
  love.graphics.setColor(0.2 + h * 0.7, 0.3, 0.8 - h * 0.5)
  love.graphics.rectangle("fill", s.x + 3, s.y + 3, s.w - 6, s.h - 6)
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
  if s.h > s.w then -- standing the other way (the tower's server room): its fans down it
    for y = s.y + s.w / 2, s.y + s.h - 1, s.w do
      love.graphics.circle("fill", s.x + s.w / 2, y, s.w / 2 - 8, 16)
    end
    return
  end
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

--- A car station's pad (the Overpass's `carStations`): dark concrete, VEX's
--- green stripes round the edge, the bay and an arrow up the road, a lamp.
local function drawStation(st)
  local R = 44
  local green = { 0.43, 1.00, 0.60 }
  color(C.shadow)
  love.graphics.rectangle("fill", st.x - R + 4, st.y - R + 5, 2 * R, 2 * R, 6, 6)
  color(C.slab)
  love.graphics.rectangle("fill", st.x - R, st.y - R, 2 * R, 2 * R, 6, 6)
  color(green, 0.85)
  for k = -R + 4, R - 8, 12 do
    love.graphics.rectangle("fill", st.x + k, st.y - R, 5, 5)
    love.graphics.rectangle("fill", st.x + k, st.y + R - 5, 5, 5)
    love.graphics.rectangle("fill", st.x - R, st.y + k, 5, 5)
    love.graphics.rectangle("fill", st.x + R - 5, st.y + k, 5, 5)
  end
  love.graphics.push()
  love.graphics.translate(st.x, st.y)
  love.graphics.rotate(st.angle)
  color(green, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", -28, -16, 56, 32, 4, 4)
  love.graphics.polygon("fill", 6, -8, 20, 0, 6, 8)
  love.graphics.rectangle("fill", -14, -3, 20, 6)
  love.graphics.setLineWidth(1)
  love.graphics.pop()
end

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
  -- The glass down either side: tinted, see-through to the city below,
  -- a steel mullion every tile and a streak of reflection on each pane.
  for _, x in ipairs({ map.left + T * 1.5, map.left + map.w - T * 2 }) do
    love.graphics.setColor(C.glass[1], C.glass[2], C.glass[3], 0.55)
    love.graphics.rectangle("fill", x, map.top, T * 0.5, map.h)
    for y = map.top, map.top + map.h, T do
      color(C.steelDark)
      love.graphics.rectangle("fill", x, y, T * 0.5, 4)
      love.graphics.setColor(0.7, 0.85, 1, 0.12)
      love.graphics.polygon("fill", x + 4, y + T * 0.7, x + 10, y + T * 0.7, x + 26, y + 8, x + 20, y + 8)
    end
    color(C.steel)
    love.graphics.rectangle("fill", x, map.top, 3, map.h)
    love.graphics.rectangle("fill", x + T * 0.5 - 3, map.top, 3, map.h)
  end
  -- The floors' own walls along their tops and bottoms, against the slab
  -- (open where a stairwell comes through).
  love.graphics.setColor(0.52, 0.53, 0.57)
  for _, f in ipairs(map.floors or {}) do
    local r0, r1 = math.floor((f.y0 - map.y0) / T + 0.5), math.floor((f.y1 - map.y0) / T + 0.5) - 1
    for c = map.c0, map.c1 do
      local col = map.tiles[c]
      local x = map.x0 + c * T
      if col and col[r0] and not col[r0 - 1] then
        love.graphics.rectangle("fill", x, f.y0 - 6, T, 6)
      end
      if col and col[r1] and not col[r1 + 1] then
        love.graphics.rectangle("fill", x, f.y1, T, 6)
      end
    end
  end
end

-- The bridge (the Overpass) ---------------------------------------------------

--- Is (c, r) part of the deck?
local function deck(map, c, r)
  local col = map.tiles[c]
  return col ~= nil and col[r] ~= nil
end

--- Along a deck edge from (x, y), `len` px in the direction (dx, dy), with
--- (ox, oy) pointing off the deck: its shadow on the drop, the steel truss
--- girder hung off it (two chords and the zigzag between), and the railing
--- along the deck's lip. Filled shapes, not lines: the canvas is half size.
local function bridgeEdge(x, y, len, dx, dy, ox, oy)
  local function quad(a0, a1, o0, o1, c, alpha)
    color(c, alpha)
    local ax, ay, bx, by = x + dx * a0, y + dy * a0, x + dx * a1, y + dy * a1
    love.graphics.polygon("fill", ax + ox * o0, ay + oy * o0, bx + ox * o0, by + oy * o0,
      bx + ox * o1, by + oy * o1, ax + ox * o1, ay + oy * o1)
  end
  -- The shadow it throws on the drop, deeper south and east (the light is from the north west).
  local deep = (ox + oy > 0) and 0.5 or 0.3
  quad(0, len, 18, 60, { 0, 0, 0 }, deep * 0.5)
  quad(0, len, 18, 34, { 0, 0, 0 }, deep * 0.5)
  -- The girder: a dark web between two lit chords, and its diagonals.
  quad(0, len, 0, 18, C.girder)
  quad(0, len, 0, 3, C.girderLight)
  quad(0, len, 15, 18, C.girderLight)
  for k = 0, len - 16, 16 do
    color(C.girderLight, 0.8)
    local ax, ay = x + dx * k, y + dy * k
    local bx, by = x + dx * (k + 16), y + dy * (k + 16)
    local up = (k / 16) % 2 == 0
    local o0, o1 = up and 3 or 15, up and 15 or 3
    love.graphics.polygon("fill", ax + ox * o0, ay + oy * o0, ax + ox * o0 + dx * 3, ay + oy * o0 + dy * 3,
      bx + ox * o1, by + oy * o1, bx + ox * o1 - dx * 3, by + oy * o1 - dy * 3)
  end
  -- The railing on the lip: a rail and its posts.
  quad(0, len, -6, -3, C.rail)
  for k = 4, len, 16 do
    quad(k - 2, k + 2, -8, 0, C.rail)
  end
end

--- The Overpass as a bridge: a girder and railing along every edge of the
--- deck (the highway, the ramp and the Knot), expansion joints across the
--- highway, the piers' caps either side of it, and the cable-stay towers.
local function drawBridge(map, T)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if deck(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if not deck(map, c - 1, r) then
          bridgeEdge(x, y, T, 0, 1, -1, 0)
        end
        if not deck(map, c + 1, r) then
          bridgeEdge(x + T, y, T, 0, 1, 1, 0)
        end
        if not deck(map, c, r - 1) then
          bridgeEdge(x, y, T, 1, 0, 0, -1)
        end
        if not deck(map, c, r + 1) then
          bridgeEdge(x, y + T, T, 1, 0, 0, 1)
        end
      end
    end
  end
  local b = map.bridge
  for _, py in ipairs(b.piers) do
    -- The pier's cross-head, out past the deck either side, and the
    -- expansion joint over it: a steel strip with its teeth.
    local r = math.floor((py - map.y0) / T)
    local c0, c1 = nil, nil
    for c = map.c0, map.c1 do
      if deck(map, c, r) then
        c0, c1 = c0 or c, c
      end
      if c0 and not deck(map, c + 1, r) then
        break
      end
    end
    if c0 then
      local x0, x1 = map.x0 + c0 * T, map.x0 + (c1 + 1) * T
      for _, side in ipairs({ { x0 - 44, -1 }, { x1 + 20, 1 } }) do
        if not deck(map, side[2] < 0 and c0 - 1 or c1 + 1, r) then
          color({ 0, 0, 0 }, 0.35)
          love.graphics.rectangle("fill", side[1] + 10, py - 14, 24, 40)
          color(C.pier)
          love.graphics.rectangle("fill", side[1], py - 20, 24, 40)
          color(C.pierTop)
          love.graphics.rectangle("fill", side[1] + 3, py - 17, 18, 8)
        end
      end
      color(C.steelDark)
      love.graphics.rectangle("fill", x0, py - 3, x1 - x0, 6)
      color(C.steel)
      for x = x0 + 4, x1 - 8, 12 do
        love.graphics.rectangle("fill", x, py - 2, 6, 4)
      end
    end
  end
  for _, t in ipairs(b.towers) do
    -- Its cables first, fanning out up and down the deck's edge.
    for k = 1, 8 do
      for _, dir in ipairs({ -1, 1 }) do
        local ex, ey = t.edge, t.y + dir * k * 44
        local nx, ny = -(ey - t.y), ex - t.x
        local n = math.sqrt(nx * nx + ny * ny)
        nx, ny = nx / n * 1.2, ny / n * 1.2
        color(C.cable, 0.75)
        love.graphics.polygon("fill", t.x + nx, t.y + ny, ex + nx, ey + ny, ex - nx, ey - ny, t.x - nx, t.y - ny)
      end
    end
    -- The tower: its shadow down on the drop, the concrete, the lit top.
    color({ 0, 0, 0 }, 0.4)
    love.graphics.rectangle("fill", t.x - 18, t.y - 14, 56, 56)
    color(C.pier)
    love.graphics.rectangle("fill", t.x - 26, t.y - 26, 52, 52, 4)
    color(C.pierTop)
    love.graphics.rectangle("fill", t.x - 20, t.y - 20, 40, 40, 3)
    color(C.girder)
    love.graphics.rectangle("fill", t.x - 8, t.y - 8, 16, 16)
    love.graphics.setColor(1, 0.2, 0.15)
    love.graphics.circle("fill", t.x, t.y, 4, 10)
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

-- What stands up and stops a round but draws no shadow of its own, and how
-- far (px) its shadow falls: taller things further.
local SHADED = {
  barrier = 6, drum = 5, vending = 8, screen = 8, rack = 8, tank = 8, table = 6, reception = 6, lift = 8,
  planter = 6, cabinet = 6, lockers = 8, shelf = 6, relay = 8, mast = 10,
}

--- Draw `map` (one of cyber_feud.lua's) into the canvas, `T` the tile size.
function RenderCyberFeud.draw(map, T)
  drawGround(map, T)
  if map.bridge then
    drawBridge(map, T)
  end
  drawRoadLines(map, T)
  if map.kind == "tower" then
    drawCurtainWall(map, T)
  elseif map.kind == "roof" then
    drawParapet(map, T)
  end
  if not map.bridge then -- the Overpass's edges throw their own shadows on the drop
    Shade.edges(map, T)
  end
  -- Flat things first, then what stands up, so shadows fall on the ground.
  for _, s in ipairs(map.cover) do
    if s.kind == "tunnel" or s.kind == "dock" or s.kind == "door" or (s.flat and DRAW[s.kind]) then
      DRAW[s.kind](s)
    end
  end
  -- The shadows of what stands up and doesn't draw its own, all first so
  -- none falls over its neighbour.
  for _, s in ipairs(map.cover) do
    local d = SHADED[s.kind]
    if d and s.solid ~= false and not s.flat then
      if s.kind == "drum" or s.kind == "tank" then
        love.graphics.setColor(0, 0, 0, Shade.ALPHA)
        love.graphics.circle("fill", s.x + s.w / 2 + d, s.y + s.h / 2 + d, s.w / 2, 16)
      else
        Shade.box(s, d)
      end
    end
  end
  color(C.shadow)
  for _, b in ipairs(map.buildings) do
    love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
  end
  Buildings.draw(map)
  for _, s in ipairs(map.cover) do
    local draw = DRAW[s.kind]
    if draw and not s.flat and s.kind ~= "tunnel" and s.kind ~= "dock" and s.kind ~= "door" then
      draw(s)
    end
  end
  for _, st in ipairs(map.carStations or {}) do
    drawStation(st)
  end
  for _, n in ipairs(map.nests or {}) do
    drawNestBase(n.nest, n.faction)
  end
  drawSigns(map)
  love.graphics.setColor(1, 1, 1)
end

return RenderCyberFeud
