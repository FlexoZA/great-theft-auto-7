-- Drawing the Eternal Mood quest line's maps (eternal_mood.lua). Fobos Base
-- so far: the UAC's moon base cut through, steel walls, each room's own
-- floor, and outside the base's walls the moon's dust and craters, drawn
-- once into the map canvas (`draw`); and everything standing or lying
-- about (`map.cover`: hazard stripes across the doorways, desks, the
-- reactor, tipped-over bins, blood and papers), the posters and the alarm
-- lamps, drawn every frame at full size by the eternal-mood feature
-- (`drawProps`), crisp and some of it moving: the reactor's core pulses
-- inside a halo, the sludge bubbles, the screens scroll, the alarms turn.
-- All lit as if by day; the night feature darkens it every frame and
-- lights it again where `map.lights` glow.

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

function DRAW.console(s, t)
  shadow(s)
  box(s, C.steelDark)
  color(C.screen)
  love.graphics.rectangle("fill", s.x + 6, s.y + 4, s.w - 12, s.h - 16)
  color(C.green)
  local row = math.floor(t * 3 + hash(s.x) * 10) -- the text scrolling
  for k = 0, 2 do
    love.graphics.rectangle("fill", s.x + 10, s.y + 8 + k * 6, (s.w - 24) * (0.3 + hash(s.x + k + row) * 0.7), 2)
  end
  if math.floor(t * 2 + s.x) % 2 == 0 then -- the cursor blinking
    love.graphics.rectangle("fill", s.x + 10, s.y + 26, 4, 3)
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

--- How bright the reactor's core is at `t`: a slow breath with a quicker
--- throb in it (the halo and the night's glow follow it too).
function RenderEternalMood.corePulse(t)
  return 0.75 + 0.15 * math.sin(t * 1.7) + 0.1 * math.sin(t * 6.3)
end

function DRAW.reactor(s, t)
  shadow(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  local pulse = RenderEternalMood.corePulse(t)
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 40)
  color(C.steel)
  love.graphics.circle("fill", cx, cy, r - 14, 40)
  for k = 0, 11 do -- bolts round the rim
    local a = k * math.pi / 6
    color(C.steelDark)
    love.graphics.circle("fill", cx + math.cos(a) * (r - 7), cy + math.sin(a) * (r - 7), 3, 8)
  end
  color(C.black)
  love.graphics.circle("fill", cx, cy, r * 0.55, 32)
  love.graphics.setColor(1.0, 0.40 + 0.15 * pulse, 0.08, 0.95) -- the core, glowing: Heck's fire
  love.graphics.circle("fill", cx, cy, r * (0.38 + 0.05 * pulse), 32)
  love.graphics.setColor(1.0, 0.85, 0.55, 0.95)
  love.graphics.circle("fill", cx, cy, r * (0.14 + 0.06 * pulse), 20)
  color(C.steelDark)
  love.graphics.setLineWidth(6)
  for k = 0, 7 do -- the vanes over it, turning slowly
    local a = k * math.pi / 4 + t * 0.25
    love.graphics.line(cx + math.cos(a) * r * 0.2, cy + math.sin(a) * r * 0.2, cx + math.cos(a) * r * 0.55,
      cy + math.sin(a) * r * 0.55)
  end
  love.graphics.setLineWidth(1)
end

--- The halo round the reactor's core, added over everything near it:
--- soft rings breathing with the core, an arc of energy running round it,
--- and the odd spark thrown off.
local function drawHalo(s, t)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  local pulse = RenderEternalMood.corePulse(t)
  love.graphics.setBlendMode("add")
  for k = 1, 6 do
    local rr = r * (0.5 + k * 0.2) * (0.96 + 0.06 * pulse)
    love.graphics.setColor(1.0, 0.35, 0.08, 0.065 * pulse * (1 - k / 7))
    love.graphics.circle("fill", cx, cy, rr, 48)
  end
  love.graphics.setLineWidth(3)
  for k = 0, 2 do -- energy running round it, three arcs at their own speeds
    local a = t * (0.9 + k * 0.45) + k * 2.1
    local rr = r * (1.25 + k * 0.22)
    love.graphics.setColor(1.0, 0.6, 0.25, 0.35 * pulse)
    love.graphics.arc("line", "open", cx, cy, rr, a, a + 0.9 + 0.3 * math.sin(t * 2 + k), 16)
  end
  love.graphics.setLineWidth(1)
  for k = 0, 5 do -- sparks flung off, flying out and fading
    local phase = (t * 0.8 + hash(k * 7.3)) % 1
    local a = hash(k * 3.1 + math.floor(t * 0.8 + hash(k * 7.3))) * 2 * math.pi
    local d = r * (0.6 + phase * 1.6)
    love.graphics.setColor(1.0, 0.8, 0.4, 0.8 * (1 - phase))
    love.graphics.circle("fill", cx + math.cos(a) * d, cy + math.sin(a) * d, 2.5 * (1 - phase) + 1, 6)
  end
  love.graphics.setBlendMode("alpha")
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

function DRAW.sludge(s, t)
  color(C.sludge)
  love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, s.h - 16, 18, 18)
  for k = 0, 5 do -- bubbles coming up and bursting
    local phase = (t * (0.5 + hash(s.x + k * 3) * 0.6) + hash(s.y + k)) % 1
    local bx, by = s.x + 20 + hash(s.x + k) * (s.w - 40), s.y + 20 + hash(s.y + k * 7) * (s.h - 40)
    color(C.sludgeLight, 1 - phase)
    love.graphics.circle(phase < 0.85 and "fill" or "line", bx, by, 2 + phase * 6, 10)
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

function DRAW.vent(s)
  -- A floor grille an imp is waiting under (eternal-mood/horde.lua bursts it).
  box(s, C.black)
  color(C.steelDark)
  for x = s.x + 4, s.x + s.w - 6, 8 do
    love.graphics.rectangle("fill", x, s.y + 3, 4, s.h - 6)
  end
  color(C.steel)
  love.graphics.rectangle("line", s.x, s.y, s.w, s.h)
end

-- The mess the night left: bins, rubbish, papers, blood, scorch marks,
-- glass and chairs knocked over (eternal_mood.lua's `clutter`). Each
-- carries its own `angle` and `seed`.

local function turned(s, draw)
  love.graphics.push()
  love.graphics.translate(s.x + s.w / 2, s.y + s.h / 2)
  love.graphics.rotate(s.angle or 0)
  draw()
  love.graphics.pop()
end

--- A bin, standing: a steel drum with a lid.
function DRAW.bin(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.shadow)
  love.graphics.circle("fill", cx + 4, cy + 4, r, 16)
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 16)
  color(C.steel)
  love.graphics.circle("fill", cx, cy, r - 3, 16)
  color(C.steelDark)
  love.graphics.rectangle("fill", cx - 5, cy - 1.5, 10, 3) -- the lid's handle
end

--- A bin knocked over on its side, its mouth to +x, rubbish spilling out.
function DRAW.tipped(s)
  turned(s, function()
    local l, h = s.w * 0.6, s.h * 0.6
    color(C.shadow)
    love.graphics.rectangle("fill", -l / 2 + 4, -h / 2 + 4, l, h, 4)
    color(C.steelDark)
    love.graphics.rectangle("fill", -l / 2, -h / 2, l, h, 4)
    color(C.steel)
    for x = -l / 2 + 5, l / 2 - 4, 7 do -- the ribs
      love.graphics.rectangle("fill", x, -h / 2 + 2, 2, h - 4)
    end
    color(C.black)
    love.graphics.ellipse("fill", l / 2, 0, 4, h / 2 - 1, 12) -- its open mouth
    -- what came out of it
    for k = 0, 6 do
      local px, py = l / 2 + 6 + hash(s.seed + k) * s.w * 0.5, (hash(s.seed * 3 + k) - 0.5) * s.h * 0.8
      local c = k % 3 == 0 and C.paper or k % 3 == 1 and C.crate or C.steelDark
      color(c)
      love.graphics.rectangle("fill", px, py, 5 + hash(k + s.seed) * 6, 4 + hash(k * 2 + s.seed) * 5)
    end
    color(C.steelDark)
    love.graphics.ellipse("fill", -l / 2 - 12, h / 2 + 4, 8, 3, 10) -- the lid, rolled off
  end)
end

--- Rubbish spread across the floor.
function DRAW.trash(s)
  for k = 0, 9 do
    local px, py = s.x + hash(s.seed + k) * s.w, s.y + hash(s.seed * 5 + k) * s.h
    local c = k % 4 == 0 and C.paper or k % 4 == 1 and C.crate or k % 4 == 2 and C.steel or C.blanket
    color(c, 0.9)
    love.graphics.push()
    love.graphics.translate(px, py)
    love.graphics.rotate(hash(k * 3 + s.seed) * 3)
    love.graphics.rectangle("fill", -3, -2, 6 + hash(k + s.seed * 2) * 6, 4)
    love.graphics.pop()
  end
end

--- Papers blown about: the memos nobody will read now.
function DRAW.papers(s)
  for k = 0, 6 do
    local px, py = s.x + hash(s.seed + k * 1.3) * s.w, s.y + hash(s.seed * 7 + k) * s.h
    love.graphics.push()
    love.graphics.translate(px, py)
    love.graphics.rotate(hash(k * 5 + s.seed) * 6)
    color(C.shadow)
    love.graphics.rectangle("fill", -6, -8, 13, 17)
    color(C.paper)
    love.graphics.rectangle("fill", -7, -9, 13, 17)
    color(C.black, 0.35)
    for line = -6, 4, 3 do
      love.graphics.rectangle("fill", -5, line, 6 + hash(k + line) * 3, 1)
    end
    love.graphics.pop()
  end
end

--- A blood smear: a pool and a drag mark, dried dark.
function DRAW.blood(s)
  turned(s, function()
    love.graphics.setColor(0.32, 0.03, 0.03, 0.85)
    love.graphics.ellipse("fill", 0, 0, s.w * 0.3, s.h * 0.25, 18)
    love.graphics.setColor(0.28, 0.02, 0.02, 0.6)
    love.graphics.polygon("fill", s.w * 0.1, -6, s.w * 0.5, -3, s.w * 0.5, 3, s.w * 0.1, 6) -- dragged off
    for k = 0, 5 do -- spatter
      local a = hash(s.seed + k) * 6.28
      local d = s.w * (0.3 + hash(s.seed * 2 + k) * 0.2)
      love.graphics.circle("fill", math.cos(a) * d, math.sin(a) * d * 0.8, 2 + hash(k) * 3, 8)
    end
  end)
end

--- A scorch mark, where something burned (or burst).
function DRAW.scorch(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  for k = 3, 1, -1 do
    love.graphics.setColor(0.05, 0.03, 0.02, 0.22 * k)
    love.graphics.circle("fill", cx, cy, r * k / 3, 20)
  end
  love.graphics.setColor(0.05, 0.03, 0.02, 0.5)
  for k = 0, 7 do -- the streaks out from it
    local a = k * 0.785 + hash(s.seed + k) * 0.5
    love.graphics.polygon("fill", cx, cy, cx + math.cos(a - 0.08) * r * 1.4, cy + math.sin(a - 0.08) * r * 1.4,
      cx + math.cos(a + 0.08) * r * 1.4, cy + math.sin(a + 0.08) * r * 1.4)
  end
end

--- Broken glass: glints on the floor.
function DRAW.glass(s, t)
  for k = 0, 8 do
    local px, py = s.x + hash(s.seed + k * 2) * s.w, s.y + hash(s.seed * 3 + k) * s.h
    local glint = 0.4 + 0.6 * math.abs(math.sin(t * 2 + k * 1.7))
    love.graphics.setColor(0.75, 0.85, 0.85, 0.5 * glint)
    love.graphics.polygon("fill", px, py, px + 4 + hash(k) * 4, py + 1, px + 2, py + 3 + hash(k * 2) * 3)
  end
end

--- An office chair knocked over: the wheels' star in the air.
function DRAW.fallen(s)
  turned(s, function()
    color(C.shadow)
    love.graphics.rectangle("fill", -10, -6, 26, 18, 3)
    color(C.black)
    love.graphics.rectangle("fill", -12, -8, 24, 16, 3) -- the seat, on its side
    color(C.steelDark)
    love.graphics.rectangle("fill", 12, -10, 6, 20, 2) -- the back
    love.graphics.setLineWidth(2)
    for k = 0, 4 do -- the base's five legs, wheels on the end
      local a = k * 1.2566
      local ex, ey = -14 + math.cos(a) * 9, math.sin(a) * 9
      love.graphics.line(-14, 0, ex, ey)
      love.graphics.circle("fill", ex, ey, 2, 6)
    end
    love.graphics.setLineWidth(1)
  end)
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

--- How bright an alarm lamp is at `t`: a turning beacon, a sharp flash as
--- its mirror comes round, each lamp on its own turn.
function RenderEternalMood.alarmFlash(a, t)
  local turn = (t * 1.6 + hash(a.x * 0.37 + a.y * 0.11)) % 1
  return math.max(0, math.cos(turn * 2 * math.pi)) ^ 6
end

local function drawAlarms(map, t)
  for _, a in ipairs(map.alarms) do
    local f = RenderEternalMood.alarmFlash(a, t)
    color(C.black)
    love.graphics.circle("fill", a.x, a.y, 12, 12)
    love.graphics.setColor(0.45 + 0.55 * f, 0.08, 0.05)
    love.graphics.circle("fill", a.x, a.y, 8, 12)
    if f > 0.05 then -- the beam sweeping round
      local turn = (t * 1.6 + hash(a.x * 0.37 + a.y * 0.11)) % 1 * 2 * math.pi
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 0.15, 0.08, 0.35 * f)
      love.graphics.arc("fill", a.x, a.y, 70, turn - 0.35, turn + 0.35, 10)
      love.graphics.setBlendMode("alpha")
    end
  end
end

--- Draw `map` (one of eternal_mood.lua's) into the canvas, `T` the tile size.
--- Draw `map`'s floors and walls (one of eternal_mood.lua's) into the
--- canvas, `T` the tile size. Everything on them is `drawProps`'.
function RenderEternalMood.draw(map, T)
  drawGround(map, T)
  love.graphics.setColor(1, 1, 1)
end

local function inView(s, left, top, right, bottom)
  return s.x + s.w >= left and s.x <= right and s.y + s.h >= top and s.y <= bottom
end

--- Everything on `map`'s floor within (left, top, right, bottom), world px,
--- at full size, at time `t`: flat things first, then what stands up, the
--- posters, the alarms, and the reactor's halo over it all.
function RenderEternalMood.drawProps(map, left, top, right, bottom, t)
  local before = love.graphics.getFont()
  for _, s in ipairs(map.cover) do
    if s.flat and DRAW[s.kind] and inView(s, left, top, right, bottom) then
      DRAW[s.kind](s, t)
    end
  end
  for _, s in ipairs(map.cover) do
    if not s.flat and DRAW[s.kind] and inView(s, left, top, right, bottom) then
      DRAW[s.kind](s, t)
    end
  end
  drawSigns(map)
  drawAlarms(map, t)
  for _, s in ipairs(map.cover) do
    if s.kind == "reactor" and inView(s, left - 400, top - 400, right + 400, bottom + 400) then
      drawHalo(s, t)
    end
  end
  love.graphics.setFont(before)
  love.graphics.setColor(1, 1, 1)
end

return RenderEternalMood
