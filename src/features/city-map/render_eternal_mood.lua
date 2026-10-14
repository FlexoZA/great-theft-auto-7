-- Drawing the Eternal Mood quest line's maps (eternal_mood.lua) into the map
-- canvas. Fobos Base so far: the UAC's moon base cut through, steel walls
-- with hazard stripes across the doorways, each room's own floor, and
-- everything standing about; outside the base's walls, the moon's grey
-- dust and craters. Drawn once, lit as if by day; the night feature
-- darkens it every frame and lights it again where `map.lights` glow.

local RenderEternalMood = {}

local C = {
  dust = { 0.42, 0.42, 0.44 }, -- the moon
  dustDark = { 0.36, 0.36, 0.38 },
  crater = { 0.30, 0.30, 0.32 },
  craterRim = { 0.52, 0.52, 0.54 },
  wall = { 0.20, 0.22, 0.25 }, -- the base's steel
  wallTop = { 0.30, 0.32, 0.36 },
  wallSeam = { 0.14, 0.15, 0.17 },
  trim = { 0.52, 0.55, 0.60 },
  hazard = { 0.95, 0.75, 0.10 },
  black = { 0.08, 0.08, 0.09 },
  steel = { 0.46, 0.49, 0.53 },
  steelDark = { 0.30, 0.32, 0.35 },
  white = { 0.84, 0.86, 0.88 },
  screen = { 0.04, 0.10, 0.05 },
  green = { 1.00, 0.28, 0.10 }, -- the screens' text: red, like everything else
  glass = { 0.55, 0.22, 0.12, 0.55 }, -- the tanks: something orange in there
  wood = { 0.40, 0.30, 0.20 },
  crate = { 0.50, 0.40, 0.24 },
  crateDark = { 0.38, 0.30, 0.17 },
  sludge = { 0.38, 0.75, 0.12 },
  sludgeLight = { 0.62, 0.95, 0.30 },
  red = { 0.75, 0.16, 0.12 },
  blanket = { 0.30, 0.36, 0.52 },
  paper = { 0.92, 0.90, 0.82 },
  shadow = { 0, 0, 0, 0.35 },
}

-- Each room's floor (eternal_mood.lua's `floor`): a base, a second colour,
-- and the pattern they make.
local FLOORS = {
  lab = { { 0.78, 0.80, 0.82 }, { 0.66, 0.68, 0.71 }, "tile" },
  carpet = { { 0.28, 0.31, 0.38 }, { 0.25, 0.28, 0.35 }, "carpet" },
  lino = { { 0.62, 0.58, 0.48 }, { 0.55, 0.51, 0.42 }, "checker" },
  plate = { { 0.40, 0.42, 0.45 }, { 0.48, 0.50, 0.53 }, "plate" },
  grate = { { 0.18, 0.20, 0.22 }, { 0.30, 0.32, 0.35 }, "grate" },
  concrete = { { 0.44, 0.43, 0.38 }, { 0.38, 0.37, 0.32 }, "concrete" },
  hangar = { { 0.36, 0.37, 0.39 }, { 0.31, 0.32, 0.34 }, "concrete" },
}

-- Everything in this universe is evil: every colour above gets a red cast
-- (more red, less green and blue), but for the sludge, which stays sick
-- green, and the colours already set red by hand.
local KEEP = { sludge = true, sludgeLight = true, green = true, glass = true, red = true, hazard = true }
local function evil(c)
  return { math.min(1, c[1] * 1.10 + 0.05), c[2] * 0.70, c[3] * 0.62, c[4] }
end
for k, c in pairs(C) do
  if not KEEP[k] and k ~= "shadow" then
    C[k] = evil(c)
  end
end
for _, f in pairs(FLOORS) do
  f[1], f[2] = evil(f[1]), evil(f[2])
end

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local font = nil
local function signFont()
  font = font or love.graphics.newFont(20) -- drawn at half size into the canvas: about 10 px on screen
  return font
end

-- Ground ---------------------------------------------------------------------

--- The zone (x, y) is in, or nil.
local function zoneAt(map, x, y)
  for _, z in ipairs(map.zones) do
    if x >= z.x0 and x < z.x1 and y >= z.y0 and y < z.y1 then
      return z
    end
  end
  return nil
end

--- One floor tile at (x, y) in finish `f`.
local function floorTile(f, x, y, T, h)
  local base, second, kind = f[1], f[2], f[3]
  local c, r = math.floor(x / T), math.floor(y / T)
  color(base)
  love.graphics.rectangle("fill", x, y, T, T)
  color(second)
  if kind == "tile" then
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
    love.graphics.rectangle("fill", x + T / 2, y, 2, T)
    love.graphics.rectangle("fill", x, y + T / 2, T, 2)
  elseif kind == "carpet" then
    love.graphics.rectangle("fill", x + ((c + r) % 2) * T / 2, y, T / 2, T / 2)
    love.graphics.rectangle("fill", x + (1 - (c + r) % 2) * T / 2, y + T / 2, T / 2, T / 2)
  elseif kind == "checker" then
    if (c + r) % 2 == 0 then
      love.graphics.rectangle("fill", x, y, T, T)
    end
  elseif kind == "plate" then
    -- Diamond plate: rows of short slanted ridges.
    for py = y + 6, y + T - 6, 12 do
      for px = x + 6, x + T - 6, 12 do
        local flip = ((px + py) / 12) % 2 < 1
        local d = flip and -3 or 3
        love.graphics.polygon("fill", px, py, px + 5, py + d, px + 6, py + d + 1, px + 1, py + 1)
      end
    end
    color(C.wallSeam)
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
  elseif kind == "grate" then
    for k = 4, T - 4, 8 do
      love.graphics.rectangle("fill", x + k, y + 2, 3, T - 4)
    end
    love.graphics.rectangle("fill", x, y, T, 3)
  else -- concrete
    for k = 0, 5 do
      local hx, hy = hash(x * 0.13 + k), hash(y * 0.17 + k * 3)
      love.graphics.rectangle("fill", x + hx * (T - 4), y + hy * (T - 4), 4, 4)
    end
    if h > 0.8 then -- an oil stain
      love.graphics.setColor(0, 0, 0, 0.18)
      love.graphics.ellipse("fill", x + 20 + h * 20, y + 26, 16 + h * 10, 9, 12)
    end
  end
end

local function inBase(map, x, y)
  local b = map.base
  return x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h
end

local function isWalk(map, c, r)
  local col = map.tiles[c]
  return col and col[r] ~= nil
end

--- A tile of the moon: grey dust, a crater now and then, a rock.
local function moonTile(x, y, T, h)
  color(h < 0.5 and C.dust or C.dustDark)
  love.graphics.rectangle("fill", x, y, T, T)
  if h > 0.82 then
    local r = 10 + (h - 0.82) * 120
    local cx, cy = x + T / 2, y + T / 2
    color(C.craterRim)
    love.graphics.circle("fill", cx - 2, cy - 2, r + 3, 16)
    color(C.crater)
    love.graphics.circle("fill", cx, cy, r, 16)
  elseif h < 0.1 then
    color(C.crater)
    love.graphics.circle("fill", x + 14 + h * 300, y + 40, 5, 8)
  end
end

--- A tile of the base's wall: dark steel panels, its seams, and a lit trim
--- along every side that faces a floor, a shadow cast onto the floor south.
local function wallTile(map, c, r, x, y, T)
  color(C.wall)
  love.graphics.rectangle("fill", x, y, T, T)
  color(C.wallSeam)
  love.graphics.rectangle("fill", x, y + T / 2 - 1, T, 2)
  love.graphics.rectangle("fill", x + ((c + r) % 2) * T / 2, y, 2, T / 2)
  color(C.wallTop)
  love.graphics.rectangle("fill", x + 4, y + 4, 6, 6)
  love.graphics.rectangle("fill", x + T - 10, y + T - 10, 6, 6)
  color(C.trim)
  if isWalk(map, c, r + 1) then
    love.graphics.rectangle("fill", x, y + T - 6, T, 6)
  end
  if isWalk(map, c, r - 1) then
    love.graphics.rectangle("fill", x, y, T, 4)
  end
  if isWalk(map, c - 1, r) then
    love.graphics.rectangle("fill", x, y, 4, T)
  end
  if isWalk(map, c + 1, r) then
    love.graphics.rectangle("fill", x + T - 4, y, 4, T)
  end
end

local function drawGround(map, T)
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      local x, y = map.x0 + c * T, map.y0 + r * T
      local h = hash(c * 7.1 + r * 13.7)
      if col and col[r] then
        local z = zoneAt(map, x + 1, y + 1)
        floorTile(FLOORS[z and z.floor or "plate"], x, y, T, h)
      elseif inBase(map, x, y) then
        wallTile(map, c, r, x, y, T)
      else
        moonTile(x, y, T, h)
      end
    end
  end
  -- The walls' shadow on the floor south of them.
  color(C.shadow)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if isWalk(map, c, r) and not isWalk(map, c, r - 1) then
        love.graphics.rectangle("fill", map.x0 + c * T, map.y0 + r * T, T, 12)
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

local function shadow(s)
  color(C.shadow)
  if s.round then
    love.graphics.ellipse("fill", s.x + s.w / 2 + 8, s.y + s.h / 2 + 8, s.w / 2, s.h / 2, 24)
  else
    love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w, s.h)
  end
end

local DRAW = {}

function DRAW.stripe(s)
  color(C.hazard)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.black)
  local step = 20 -- yellow and black bands across the doorway's width
  if s.across then
    for k = 0, s.h - 1, step do
      love.graphics.rectangle("fill", s.x, s.y + k, s.w, math.min(step / 2, s.h - k))
    end
  else
    for k = 0, s.w - 1, step do
      love.graphics.rectangle("fill", s.x + k, s.y, math.min(step / 2, s.w - k), s.h)
    end
  end
end

function DRAW.portal(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2 - 8
  love.graphics.setColor(0.35, 0.08, 0.05, 0.8) -- scorched floor
  love.graphics.circle("fill", cx, cy, r + 10, 32)
  love.graphics.setLineWidth(18)
  color(C.steelDark)
  love.graphics.arc("line", "open", cx, cy, r, 0.4, 2.6, 24) -- the ring, broken in three
  love.graphics.arc("line", "open", cx, cy, r, 2.9, 4.3, 16)
  love.graphics.arc("line", "open", cx, cy, r, 4.7, 5.9, 16)
  love.graphics.setLineWidth(1)
  color(C.red)
  for k = 0, 5 do -- glowing cracks across the scorch
    local a = k * 1.05 + 0.3
    love.graphics.line(cx, cy, cx + math.cos(a) * r * 0.8, cy + math.sin(a) * r * 0.8)
  end
  -- a chunk of the ring, thrown clear
  color(C.steelDark)
  love.graphics.rectangle("fill", cx + r + 4, cy + r * 0.4, 30, 14)
end

function DRAW.slab(s)
  shadow(s)
  box(s, C.steel)
  box(s, C.white, 5) -- the sheet
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x + 8, s.y + 6, s.w - 16, 16) -- the pillow end
end

function DRAW.tank(s)
  shadow(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 24)
  color(C.glass)
  love.graphics.circle("fill", cx, cy, r - 6, 24)
  love.graphics.setColor(0.2, 0.15, 0.12, 0.7) -- something floating in it
  love.graphics.ellipse("fill", cx, cy + 2, r * 0.3, r * 0.45, 12)
  love.graphics.setColor(1, 1, 1, 0.25)
  love.graphics.arc("fill", cx - 4, cy - 4, r - 10, 3.6, 4.6, 8)
end

function DRAW.console(s)
  shadow(s)
  box(s, C.steelDark)
  color(C.screen)
  love.graphics.rectangle("fill", s.x + 6, s.y + 4, s.w - 12, s.h - 16)
  color(C.green)
  for k = 0, 2 do
    love.graphics.rectangle("fill", s.x + 10, s.y + 8 + k * 6, (s.w - 24) * (0.4 + hash(s.x + k) * 0.6), 2)
  end
end

function DRAW.desk(s)
  shadow(s)
  box(s, C.wood)
  color(C.steelDark) -- a monitor
  love.graphics.rectangle("fill", s.x + s.w / 2 - 16, s.y + 4, 32, 18)
  color(C.green)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 13, s.y + 7, 26, 12)
  color(C.paper)
  love.graphics.rectangle("fill", s.x + 8, s.y + 12, 18, 22)
  love.graphics.setColor(0.85, 0.85, 0.80) -- the coffee mug
  love.graphics.circle("fill", s.x + s.w - 16, s.y + 26, 6, 10)
end

function DRAW.chair(s)
  color(C.black)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w / 2, 12)
  color(C.steelDark)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w / 2 - 4, 12)
end

function DRAW.cabinet(s)
  shadow(s)
  box(s, C.steel)
  color(C.steelDark)
  for y = s.y + 14, s.y + s.h - 10, 26 do
    love.graphics.rectangle("fill", s.x + 6, y, s.w - 12, 3)
  end
end

function DRAW.cooler(s)
  shadow(s)
  box(s, C.white)
  love.graphics.setColor(0.80, 0.35, 0.30, 0.9) -- the water's not right either
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w / 2 - 6, 16)
end

function DRAW.reactor(s)
  shadow(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 40)
  color(C.steel)
  love.graphics.circle("fill", cx, cy, r - 14, 40)
  color(C.black)
  love.graphics.circle("fill", cx, cy, r * 0.55, 32)
  love.graphics.setColor(1.0, 0.45, 0.10, 0.95) -- the core, glowing: Heck's fire
  love.graphics.circle("fill", cx, cy, r * 0.42, 32)
  love.graphics.setColor(1.0, 0.85, 0.55, 0.95)
  love.graphics.circle("fill", cx, cy, r * 0.18, 20)
  color(C.steelDark)
  for k = 0, 7 do -- the vanes over it
    local a = k * math.pi / 4
    love.graphics.setLineWidth(6)
    love.graphics.line(cx + math.cos(a) * r * 0.2, cy + math.sin(a) * r * 0.2, cx + math.cos(a) * r * 0.55,
      cy + math.sin(a) * r * 0.55)
  end
  love.graphics.setLineWidth(1)
end

function DRAW.catwalk(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.steelDark)
  love.graphics.setLineWidth(70)
  love.graphics.circle("line", cx, cy, s.w / 2 - 40, 48)
  love.graphics.setLineWidth(4)
  color(C.hazard)
  love.graphics.circle("line", cx, cy, s.w / 2 - 6, 48)
  love.graphics.circle("line", cx, cy, s.w / 2 - 74, 48)
  love.graphics.setLineWidth(1)
end

function DRAW.pipe(s)
  shadow(s)
  box(s, C.steelDark)
  color(C.steel)
  if s.w >= s.h then
    love.graphics.rectangle("fill", s.x, s.y + 3, s.w, s.h / 3)
    for x = s.x + 40, s.x + s.w - 10, 80 do -- the flanges
      color(C.wallSeam)
      love.graphics.rectangle("fill", x, s.y - 2, 6, s.h + 4)
    end
  else
    love.graphics.rectangle("fill", s.x + 3, s.y, s.w / 3, s.h)
  end
end

function DRAW.barrel(s)
  shadow(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(s.red and C.red or C.hazard)
  love.graphics.circle("fill", cx, cy, r, 16)
  color(C.black)
  love.graphics.circle("line", cx, cy, r - 4, 16)
  love.graphics.circle("fill", cx, cy, 3, 8)
  if not s.red then -- the trefoil, roughly
    for k = 0, 2 do
      local a = k * 2.09 - 1.57
      love.graphics.arc("fill", cx, cy, r - 8, a - 0.4, a + 0.4, 6)
    end
  end
end

function DRAW.sludge(s)
  color(C.sludge)
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, s.h - 16, 18, 18)
  color(C.sludgeLight)
  for k = 0, 3 do
    local bx, by = s.x + 20 + hash(s.x + k) * (s.w - 40), s.y + 20 + hash(s.y + k * 7) * (s.h - 40)
    love.graphics.circle("fill", bx, by, 5, 10)
  end
end

function DRAW.crane(s)
  -- A gantry rail across the room, the hook block hanging off it.
  color(C.hazard)
  love.graphics.rectangle("fill", s.x, s.y, s.w, 10)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 10, s.w, 10)
  color(C.black)
  for x = s.x, s.x + s.w, 24 do
    love.graphics.line(x, s.y + 10, x + 24, s.y + s.h - 10)
  end
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x + s.w * 0.55, s.y - 8, 40, s.h + 16)
end

function DRAW.crate(s)
  shadow(s)
  box(s, C.crateDark)
  box(s, C.crate, 5)
  color(C.crateDark)
  love.graphics.setLineWidth(5)
  love.graphics.line(s.x + 5, s.y + 5, s.x + s.w - 5, s.y + s.h - 5)
  love.graphics.setLineWidth(1)
  color(C.black)
  love.graphics.print("UAC", s.x + s.w / 2 - 12, s.y + s.h / 2 - 8)
end

function DRAW.loader(s)
  shadow(s)
  color(C.hazard)
  love.graphics.rectangle("fill", s.x + 10, s.y + 30, s.w - 20, s.h - 40, 8, 8)
  color(C.black)
  love.graphics.rectangle("fill", s.x + 2, s.y + 40, 10, s.h - 56) -- tracks
  love.graphics.rectangle("fill", s.x + s.w - 12, s.y + 40, 10, s.h - 56)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x + 20, s.y, 12, 40) -- forks
  love.graphics.rectangle("fill", s.x + s.w - 32, s.y, 12, 40)
  love.graphics.setColor(0.45, 0.30, 0.28, 0.8) -- the cab
  love.graphics.rectangle("fill", s.x + 24, s.y + 60, s.w - 48, 50)
end

function DRAW.lift(s)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.steel)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - 32, s.h - 32)
  -- hazard border and the arrow up
  color(C.hazard)
  love.graphics.setLineWidth(8)
  love.graphics.rectangle("line", s.x + 8, s.y + 8, s.w - 16, s.h - 16)
  love.graphics.setLineWidth(1)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  love.graphics.polygon("fill", cx, cy - 60, cx + 50, cy, cx + 18, cy, cx + 18, cy + 60, cx - 18, cy + 60, cx - 18, cy,
    cx - 50, cy)
end

function DRAW.bunk(s)
  shadow(s)
  box(s, C.steelDark)
  box(s, C.blanket, 5)
  color(C.white)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, 24, s.h - 12) -- the pillow
end

function DRAW.table(s)
  shadow(s)
  box(s, C.steel)
  color(C.paper) -- trays
  love.graphics.rectangle("fill", s.x + 10, s.y + 10, 22, 16)
  love.graphics.rectangle("fill", s.x + s.w - 34, s.y + s.h - 28, 22, 16)
end

function DRAW.counter(s)
  shadow(s)
  box(s, C.steel)
  color(C.steelDark)
  for y = s.y + 20, s.y + s.h - 40, 70 do -- the hot plates
    love.graphics.rectangle("fill", s.x + 6, y, s.w - 12, 40)
  end
end

function DRAW.lockers(s)
  shadow(s)
  box(s, C.steel)
  color(C.steelDark)
  for x = s.x + 32, s.x + s.w - 8, 32 do
    love.graphics.rectangle("fill", x, s.y, 3, s.h)
  end
end

function DRAW.paint(s)
  color(C.hazard, 0.85)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
end

local function drawSigns(map)
  local f = signFont()
  love.graphics.setFont(f)
  for _, s in ipairs(map.signs) do
    color(C.paper)
    love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
    color(C.red)
    love.graphics.rectangle("fill", s.x, s.y, 8, s.h)
    color(C.black)
    local _, lines = f:getWrap(s.text, s.w - 18)
    love.graphics.printf(s.text, s.x + 12, s.y + (s.h - #lines * f:getHeight()) / 2, s.w - 18, "center")
  end
end

local function drawAlarms(map)
  for _, a in ipairs(map.alarms) do
    color(C.black)
    love.graphics.circle("fill", a.x, a.y, 12, 12)
    color(C.red)
    love.graphics.circle("fill", a.x, a.y, 8, 12)
  end
end

--- Draw `map` (one of eternal_mood.lua's) into the canvas, `T` the tile size.
function RenderEternalMood.draw(map, T)
  drawGround(map, T)
  -- Flat things first, then what stands up.
  for _, s in ipairs(map.cover) do
    if s.flat and DRAW[s.kind] then
      DRAW[s.kind](s)
    end
  end
  for _, s in ipairs(map.cover) do
    if not s.flat and DRAW[s.kind] then
      DRAW[s.kind](s)
    end
  end
  drawSigns(map)
  drawAlarms(map)
  love.graphics.setColor(1, 1, 1)
end

return RenderEternalMood
