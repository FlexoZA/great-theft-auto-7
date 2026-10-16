-- Drawing the Eternal Mood quest line's maps (eternal_mood.lua). Fobos Base:
-- the UAC's moon base cut through, steel walls, each room's own floor, and
-- outside the base's walls the moon's dust and craters; Heck on Earth: the
-- city's streets, sidewalks and yards, and the roofs of its buildings (houses,
-- towers, the fallen overpass), drawn once into the map canvas (`draw`);
-- and everything standing or lying
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
  -- Heck on Earth
  waste = { 0.22, 0.19, 0.16 }, -- the ground nobody built on, burnt
  wasteDark = { 0.16, 0.14, 0.12 },
  roofFlat = { 0.36, 0.36, 0.37 },
  parapet = { 0.50, 0.50, 0.52 },
  roofTin = { 0.40, 0.42, 0.44 },
  concrete = { 0.55, 0.54, 0.52 },
  concreteDark = { 0.38, 0.37, 0.36 },
  hedge = { 0.22, 0.25, 0.13 },
  hedgeDark = { 0.15, 0.17, 0.09 },
  bark = { 0.16, 0.12, 0.10 },
  char = { 0.10, 0.08, 0.07 },
  paint = { 0.82, 0.80, 0.72 },
  yellowLine = { 0.95, 0.75, 0.15 },
  tyre = { 0.07, 0.07, 0.08 },
  windscreen = { 0.12, 0.14, 0.18 },
  lava = { 1.00, 0.38, 0.04 },
  lavaHot = { 1.00, 0.80, 0.30 },
  crust = { 0.22, 0.07, 0.04 },
  -- the Foundry
  tarmac = { 0.16, 0.16, 0.18 }, -- the starport's, past the walls
  tarmacDark = { 0.12, 0.12, 0.14 },
  rockWall = { 0.24, 0.12, 0.09 }, -- Heck's rock where the shed's steel was
  rockWallDark = { 0.15, 0.07, 0.05 },
  bone = { 0.86, 0.80, 0.66 },
  belt = { 0.12, 0.12, 0.13 },
  beltLine = { 0.24, 0.24, 0.26 },
  glassBooth = { 0.55, 0.70, 0.75, 0.35 },
  jar = { 0.60, 0.85, 0.70, 0.55 },
  brain = { 0.92, 0.58, 0.60 },
}

-- Roofs and car paint, picked by seed.
local ROOF_TILES = { { 0.48, 0.22, 0.17 }, { 0.32, 0.30, 0.33 }, { 0.42, 0.32, 0.22 } }
local PAINT = { { 0.55, 0.12, 0.10 }, { 0.20, 0.30, 0.50 }, { 0.70, 0.68, 0.62 }, { 0.15, 0.15, 0.17 },
  { 0.35, 0.45, 0.30 }, { 0.75, 0.55, 0.15 } }

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
  -- Heck on Earth's (eternal_mood.lua's `map.grounds`)
  asphalt = { { 0.22, 0.22, 0.24 }, { 0.17, 0.17, 0.19 }, "asphalt" },
  sidewalk = { { 0.50, 0.49, 0.46 }, { 0.40, 0.39, 0.36 }, "slabs" },
  lawn = { { 0.30, 0.27, 0.15 }, { 0.21, 0.19, 0.10 }, "lawn" },
  cracked = { { 0.21, 0.20, 0.20 }, { 0.09, 0.07, 0.07 }, "cracked" },
  -- the Foundry's north half: Heck's own rock
  rock = { { 0.30, 0.17, 0.13 }, { 0.19, 0.09, 0.07 }, "rock" },
}

-- Everything in this universe is evil: every colour above gets a red cast
-- (more red, less green and blue), but for the sludge, which stays sick
-- green, and the colours already set red by hand.
local KEEP = { sludge = true, sludgeLight = true, green = true, glass = true, red = true, hazard = true,
  lava = true, lavaHot = true, crust = true, yellowLine = true, jar = true, brain = true, glassBooth = true }
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
for _, list in ipairs({ ROOF_TILES, PAINT }) do
  for i, c in ipairs(list) do
    list[i] = evil(c)
  end
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
  elseif kind == "asphalt" or kind == "cracked" then
    for k = 0, 7 do -- grit
      local hx, hy = hash(x * 0.11 + k * 1.3), hash(y * 0.19 + k * 2.7)
      love.graphics.rectangle("fill", x + hx * (T - 3), y + hy * (T - 3), 3, 3)
    end
    if kind == "cracked" or h > 0.9 then -- cracks running across it
      love.graphics.setLineWidth(kind == "cracked" and 3 or 2)
      local px, py = x + hash(h * 31) * T, y
      for k = 1, 4 do
        local nx, ny = x + hash(h * 17 + k) * T, y + k * T / 4
        love.graphics.line(px, py, nx, ny)
        px, py = nx, ny
      end
      love.graphics.setLineWidth(1)
    end
  elseif kind == "rock" then
    for k = 0, 3 do -- lumps
      local hx, hy = hash(x * 0.09 + k * 2.1), hash(y * 0.15 + k * 1.7)
      love.graphics.ellipse("fill", x + 6 + hx * (T - 12), y + 6 + hy * (T - 12), 7, 5, 8)
    end
    if h > 0.7 then -- a seam of something glowing
      love.graphics.setColor(0.85, 0.25, 0.05, 0.7)
      love.graphics.setLineWidth(2)
      local px, py = x, y + hash(h * 7) * T
      love.graphics.line(px, py, x + T * 0.4, py + (hash(h * 3) - 0.5) * 30, x + T, y + hash(h * 11) * T)
      love.graphics.setLineWidth(1)
    end
  elseif kind == "slabs" then
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y + T / 2, T, 2)
    love.graphics.rectangle("fill", x + ((r % 2) * T / 2), y, 2, T / 2)
    love.graphics.rectangle("fill", x + ((r + 1) % 2 * T / 2), y + T / 2, 2, T / 2)
  elseif kind == "lawn" then
    for k = 0, 9 do -- dead tufts
      local hx, hy = hash(x * 0.07 + k * 3.3), hash(y * 0.13 + k * 1.9)
      love.graphics.rectangle("fill", x + hx * (T - 6), y + hy * (T - 6), 6, 3)
    end
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

-- Outside -------------------------------------------------------------------

-- What lies past a map's walls is drawn in three passes so nothing in it
-- shows a tile's edge: one colour under everything, then soft blotches of
-- a second colour that run across the tiles (from a smooth noise), then
-- the grain and the odd thing lying there, tile by tile.
local OUTSIDE = {
  moon = { base = "dust", blotch = "dustDark", grain = "crater" },
  tarmac = { base = "tarmac", blotch = "tarmacDark", grain = "black" },
  waste = { base = "waste", blotch = "wasteDark", grain = "concreteDark" },
}

--- A soft blotch of `c` round (x, y): rings fading out from the middle.
local function blotch(c, x, y, r, a)
  for k = 3, 1, -1 do
    color(c, a * (4 - k) / 3)
    love.graphics.circle("fill", x, y, r * k / 3, 18)
  end
end

--- The blotches over the outside tile at (x, y): wherever the noise is high.
local function outsideBlotches(look, x, y, T)
  local n = love.math.noise(x / 700, y / 700)
  if n > 0.45 then
    blotch(C[look.blotch], x + T / 2, y + T / 2, T * (0.6 + n * 0.6), 0.5 * (n - 0.45) / 0.55 + 0.25)
  end
end

--- The grain on the outside tile at (x, y), and what lies there by `look`.
local function outsideGrain(look, kind, x, y, T, h)
  color(C[look.grain], 0.35)
  for k = 0, 9 do
    local s = 2 + hash(h * 5 + k) * 3
    love.graphics.rectangle("fill", x + hash(h * 13 + k) * (T - s), y + hash(h * 29 + k) * (T - s), s, s)
  end
  if kind == "moon" then -- craters now and then, a pebble
    if h > 0.86 then
      local r = 10 + (h - 0.86) * 160
      local cx, cy = x + T / 2 + (hash(h * 3) - 0.5) * 20, y + T / 2 + (hash(h * 7) - 0.5) * 20
      color(C.craterRim)
      love.graphics.circle("fill", cx - 2, cy - 2, r + 3, 18)
      color(C.crater)
      love.graphics.circle("fill", cx, cy, r, 18)
      color(C.shadow) -- the inside of the far rim, out of the light
      love.graphics.arc("fill", cx, cy, r, math.pi * 1.1, math.pi * 1.9, 10)
    elseif h < 0.12 then
      color(C.craterRim)
      love.graphics.circle("fill", x + 10 + h * 360, y + 12 + h * 300, 3, 6)
    end
  elseif kind == "tarmac" then -- slab joints every other tile, an oil stain now and then
    local c, r = math.floor(x / T), math.floor(y / T)
    color(C.black, 0.45)
    if c % 2 == 0 then
      love.graphics.rectangle("fill", x, y, 2, T)
    end
    if r % 2 == 0 then
      love.graphics.rectangle("fill", x, y, T, 2)
    end
    if h > 0.88 then
      love.graphics.setColor(0, 0, 0, 0.22)
      love.graphics.ellipse("fill", x + 16 + h * 30, y + 30, 14 + h * 12, 9, 12)
    end
  else -- waste ground: ash, rubble, a burnt stump now and then
    if h > 0.7 then
      color(C.concreteDark)
      local rx, ry = x + hash(h * 17) * (T - 16), y + hash(h * 23) * (T - 12)
      love.graphics.polygon("fill", rx, ry + 6, rx + 7, ry, rx + 14, ry + 4, rx + 10, ry + 11, rx + 2, ry + 12)
    end
    if h < 0.06 then
      color(C.char)
      love.graphics.circle("fill", x + T / 2, y + T / 2, 6, 8)
    end
  end
end

--- A tile of Heck's abyss past its edge: dark, a red glow far below
--- breathing through it in soft patches.
local function abyssTile(x, y, T)
  love.graphics.setColor(0.09, 0.02, 0.02)
  love.graphics.rectangle("fill", x, y, T, T)
end

local function abyssGlow(x, y, T, h)
  local n = love.math.noise(x / 500, y / 500)
  if n > 0.55 then
    for k = 3, 1, -1 do
      love.graphics.setColor(0.45, 0.08, 0.02, (n - 0.55) * 0.5 * (4 - k) / 3)
      love.graphics.circle("fill", x + T / 2, y + T / 2, T * 0.9 * k / 3, 16)
    end
  end
  if h > 0.9 then -- an ember drifting up
    love.graphics.setColor(1, 0.4, 0.1, 0.5)
    love.graphics.circle("fill", x + hash(h * 7) * T, y + hash(h * 11) * T, 2, 6)
  end
end

-- Walls ----------------------------------------------------------------------

-- The walls stand up out of the floor, lit from the top left as everything
-- is: the top of a wall is its colour, darker the deeper into a thick wall
-- it is; the side of it facing a floor to the south shows as a face
-- (FACE px, a lit lip over it), and it throws a shadow across the floor to
-- its south (SHADOW_S px) and east (SHADOW_E px). So a wall reads as
-- something no round goes over.
local FACE, SHADOW_S, SHADOW_E = 18, 36, 16
local ROCK_FACE = 26 -- Heck's rock stands taller and rougher

--- How deep into a wall tile (c, r) is: 0 next to a floor, more further in.
local function depth(map, c, r)
  for d = 1, 2 do
    for dc = -d, d do
      for dr = -d, d do
        if isWalk(map, c + dc, r + dr) then
          return d - 1
        end
      end
    end
  end
  return 2
end

--- A tile of wall gone to Heck's rock: lumps and ridges, a bone now and
--- then caught in it, every one its own way.
local function rockWallTop(c, r, x, y, T)
  local h = hash(c * 3.7 + r * 5.3)
  love.graphics.setColor(C.rockWall[1] * 0.72, C.rockWall[2] * 0.72, C.rockWall[3] * 0.72) -- darker than the floor
  love.graphics.rectangle("fill", x, y, T, T)
  color(C.rockWallDark)
  for k = 0, 4 do
    local rx, ry = x + 6 + hash(h + k) * (T - 12), y + 6 + hash(h * 2 + k) * (T - 12)
    love.graphics.ellipse("fill", rx, ry, 5 + hash(h * 3 + k) * 6, 4 + hash(h * 5 + k) * 4, 8)
  end
  love.graphics.setColor(C.rockWall[1] * 1.25, C.rockWall[2] * 1.2, C.rockWall[3] * 1.2) -- ridges catching the light
  love.graphics.setLineWidth(2)
  local px, py = x + hash(h * 9) * T, y
  for k = 1, 3 do
    local nx, ny = x + hash(h * 13 + k) * T, y + k * T / 3
    love.graphics.line(px, py, nx, ny)
    px, py = nx, ny
  end
  love.graphics.setLineWidth(1)
  if h > 0.88 then -- a bone caught in it, at its own angle and length
    local a, len = hash(h * 17) * math.pi, 18 + hash(h * 19) * 20
    local cx, cy = x + T / 2, y + T / 2
    local dx, dy = math.cos(a) * len / 2, math.sin(a) * len / 2
    color(C.bone, 0.7)
    love.graphics.setLineWidth(4)
    love.graphics.line(cx - dx, cy - dy, cx + dx, cy + dy)
    love.graphics.setLineWidth(1)
    love.graphics.circle("fill", cx - dx, cy - dy, 3.5, 6)
    love.graphics.circle("fill", cx + dx, cy + dy, 3.5, 6)
  end
end

--- A tile of the base's wall from above: dark steel panels, their seams,
--- a bolt at two corners; a vent or a run of conduit now and then deep in.
local function steelWallTop(c, r, x, y, T, d)
  color(C.wall)
  love.graphics.rectangle("fill", x, y, T, T)
  color(C.wallSeam)
  love.graphics.rectangle("fill", x, y + T / 2 - 1, T, 2)
  love.graphics.rectangle("fill", x + ((c + r) % 2) * T / 2, y, 2, T / 2)
  color(C.wallTop)
  love.graphics.rectangle("fill", x + 4, y + 4, 6, 6)
  love.graphics.rectangle("fill", x + T - 10, y + T - 10, 6, 6)
  local h = hash(c * 5.9 + r * 2.3)
  if d >= 2 and h > 0.85 then -- a vent in the roof
    color(C.wallSeam)
    love.graphics.rectangle("fill", x + 14, y + 18, T - 28, T - 36, 3)
    color(C.wallTop)
    for k = 0, 3 do
      love.graphics.rectangle("fill", x + 17, y + 21 + k * 6, T - 34, 2)
    end
  elseif d >= 1 and h < 0.12 then -- conduit along it
    color(C.steelDark)
    love.graphics.rectangle("fill", x, y + 20, T, 8)
    color(C.wallTop)
    love.graphics.rectangle("fill", x, y + 20, T, 2)
  end
end

--- A tile of wall: its top, darker deeper in; a lit trim along the sides
--- facing a floor; its face over a floor to the south.
local function wallTile(map, c, r, x, y, T)
  local rock = map.heckFrom and y < map.heckFrom
  local d = depth(map, c, r)
  if rock then
    rockWallTop(c, r, x, y, T)
  else
    steelWallTop(c, r, x, y, T, d)
  end
  if d > 0 then -- deeper in, further from the light of the rooms
    love.graphics.setColor(0, 0, 0, 0.12 * d)
    love.graphics.rectangle("fill", x, y, T, T)
  end
  local lip = rock and { C.rockWall[1] * 1.6, C.rockWall[2] * 1.5, C.rockWall[3] * 1.5 } or C.trim
  color(lip)
  if isWalk(map, c, r - 1) then
    love.graphics.rectangle("fill", x, y, T, 3)
  end
  if isWalk(map, c - 1, r) then
    love.graphics.rectangle("fill", x, y, 3, T)
  end
  if isWalk(map, c + 1, r) then
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.rectangle("fill", x + T - 3, y, 3, T)
  end
  if isWalk(map, c, r + 1) then -- the face, down to the floor
    if rock then
      color(C.rockWallDark)
    else
      love.graphics.setColor(C.wall[1] * 0.7, C.wall[2] * 0.7, C.wall[3] * 0.7)
    end
    local face = rock and ROCK_FACE or FACE
    love.graphics.rectangle("fill", x, y + T - face, T, face)
    color(lip)
    love.graphics.rectangle("fill", x, y + T - face - 3, T, 3)
    if rock then
      love.graphics.setColor(0.7, 0.2, 0.05, 0.8) -- Heck glowing at its foot
      love.graphics.rectangle("fill", x, y + T - 3, T, 3)
    else
      color(C.wallSeam) -- the face's panel lines
      for px = x + ((c % 2) * T / 2), x + T - 1, T / 2 do
        love.graphics.rectangle("fill", px, y + T - FACE, 2, FACE)
      end
    end
  end
end

--- The walls' shadows over the floor: south of a wall, and east of one.
local function wallShadows(map, T)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if isWalk(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if not isWalk(map, c, r - 1) then
          love.graphics.setColor(0, 0, 0, 0.4)
          love.graphics.rectangle("fill", x, y, T, SHADOW_S * 0.55)
          love.graphics.setColor(0, 0, 0, 0.2)
          love.graphics.rectangle("fill", x, y + SHADOW_S * 0.55, T, SHADOW_S * 0.45)
        end
        if not isWalk(map, c - 1, r) then
          love.graphics.setColor(0, 0, 0, 0.3)
          love.graphics.rectangle("fill", x, y, SHADOW_E, T)
        end
      end
    end
  end
end

local function drawGround(map, T)
  local kind = map.outside == "tarmac" and "tarmac" or map.outside == "abyss" and "abyss" or "moon"
  local look = OUTSIDE[kind]
  local function outside(c, r)
    local col = map.tiles[c]
    local x, y = map.x0 + c * T, map.y0 + r * T
    return not (col and col[r]) and not inBase(map, x, y), x, y
  end
  -- The outside: its colour, then the blotches across it, then its grain.
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      local out, x, y = outside(c, r)
      if out then
        if look then
          color(C[look.base])
          love.graphics.rectangle("fill", x, y, T, T)
        else
          abyssTile(x, y, T)
        end
      end
    end
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      local out, x, y = outside(c, r)
      if out then
        local h = hash(c * 7.1 + r * 13.7)
        if look then
          outsideBlotches(look, x, y, T)
          outsideGrain(look, kind, x, y, T, h)
        else
          abyssGlow(x, y, T, h)
        end
      end
    end
  end
  -- The floors and the walls over it, then the walls' shadows.
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      local x, y = map.x0 + c * T, map.y0 + r * T
      if col and col[r] then
        local z = zoneAt(map, x + 1, y + 1)
        floorTile(FLOORS[z and z.floor or "plate"], x, y, T, hash(c * 7.1 + r * 13.7))
      elseif inBase(map, x, y) then
        wallTile(map, c, r, x, y, T)
      end
    end
  end
  wallShadows(map, T)
end

-- Heck on Earth's ground ---------------------------------------------------------

--- The finish over (x, y): the last of `map.grounds` there.
local function groundAt(map, x, y)
  local list = map.grounds
  for i = #list, 1, -1 do
    local z = list[i]
    if x >= z.x0 and x < z.x1 and y >= z.y0 and y < z.y1 then
      return z
    end
  end
  return nil
end

-- The buildings' roofs, by style (eternal_mood.lua's `map.roofs`).
local ROOFS = {}

-- How tall each style stands, px: its shadow falls this far (south-east,
-- lit from the top left). Hedges and ruins hardly stand at all.
local ROOF_HEIGHT = { house = 26, tower = 64, warehouse = 30, overpass = 22, starport = 36, ruin = 10 }

--- A house: a pitched roof, ridge across its long side, a chimney; holes
--- burnt through it if it's on fire.
function ROOFS.house(b)
  local tile = ROOF_TILES[b.seed % #ROOF_TILES + 1]
  local x, y, w, h = b.x + 6, b.y + 6, b.w - 12, b.h - 12
  color(C.char)
  love.graphics.rectangle("fill", x - 4, y - 4, w + 8, h + 8)
  local alongX = (b.seed % 2 == 0)
  color(tile)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(0, 0, 0, 0.25) -- the side away from the light
  if alongX then
    love.graphics.rectangle("fill", x, y + h / 2, w, h / 2)
  else
    love.graphics.rectangle("fill", x + w / 2, y, w / 2, h)
  end
  love.graphics.setColor(0, 0, 0, 0.18) -- rows of tiles
  if alongX then
    for ty = y + 10, y + h - 4, 12 do
      love.graphics.rectangle("fill", x, ty, w, 2)
    end
  else
    for tx = x + 10, x + w - 4, 12 do
      love.graphics.rectangle("fill", tx, y, 2, h)
    end
  end
  color(C.char)
  if alongX then
    love.graphics.rectangle("fill", x, y + h / 2 - 3, w, 6) -- the ridge
  else
    love.graphics.rectangle("fill", x + w / 2 - 3, y, 6, h)
  end
  color(C.concreteDark)
  love.graphics.rectangle("fill", x + w * 0.7, y + h * 0.18, 22, 22) -- the chimney
  if b.burning then
    for k = 0, 2 do
      color(C.char)
      local hx, hy = x + w * (0.2 + hash(b.seed + k) * 0.6), y + h * (0.2 + hash(b.seed * 3 + k) * 0.6)
      love.graphics.ellipse("fill", hx, hy, 26 + k * 6, 20 + k * 4, 12)
    end
  end
end

--- A tower block: a flat roof behind a parapet, air-con units, a water
--- tank and a hatch; scorched if it's on fire.
function ROOFS.tower(b)
  color(C.parapet)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(C.roofFlat)
  love.graphics.rectangle("fill", b.x + 10, b.y + 10, b.w - 20, b.h - 20)
  color(C.concreteDark)
  for k = 0, 40 do -- gravel
    local gx, gy = b.x + 12 + hash(b.seed + k) * (b.w - 28), b.y + 12 + hash(b.seed * 2 + k) * (b.h - 28)
    love.graphics.rectangle("fill", gx, gy, 4, 4)
  end
  for k = 0, 2 + b.seed % 3 do -- air-con units
    local ux, uy = b.x + 30 + hash(b.seed * 5 + k) * (b.w - 110), b.y + 30 + hash(b.seed * 7 + k) * (b.h - 100)
    color(C.shadow)
    love.graphics.rectangle("fill", ux + 6, uy + 6, 56, 40)
    color(C.steel)
    love.graphics.rectangle("fill", ux, uy, 56, 40)
    color(C.steelDark)
    love.graphics.circle("fill", ux + 28, uy + 20, 14, 12)
  end
  local tx, ty = b.x + b.w * (0.25 + hash(b.seed * 11) * 0.5), b.y + b.h * (0.25 + hash(b.seed * 13) * 0.5)
  color(C.shadow)
  love.graphics.circle("fill", tx + 8, ty + 8, 30, 20)
  color(C.wood)
  love.graphics.circle("fill", tx, ty, 30, 20) -- the water tank
  color(C.crateDark)
  love.graphics.circle("line", tx, ty, 24, 20)
  if b.burning then
    for k = 0, 3 do
      love.graphics.setColor(0.04, 0.03, 0.02, 0.6)
      love.graphics.circle("fill", b.x + b.w * hash(b.seed + k * 9), b.y + b.h * hash(b.seed * 4 + k), 50 + k * 10, 16)
    end
  end
end

--- A warehouse: a tin roof, corrugated, skylights down the middle.
function ROOFS.warehouse(b)
  color(C.roofTin)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(C.steelDark)
  if b.w >= b.h then
    for x = b.x + 8, b.x + b.w, 16 do
      love.graphics.rectangle("fill", x, b.y, 4, b.h)
    end
  else
    for y = b.y + 8, b.y + b.h, 16 do
      love.graphics.rectangle("fill", b.x, y, b.w, 4)
    end
  end
  color(C.black)
  love.graphics.rectangle("line", b.x + 2, b.y + 2, b.w - 4, b.h - 4)
end

--- What's left of a building that fell into the Crater: broken slabs over
--- the dark of the floors below, girders sticking out.
function ROOFS.ruin(b)
  color(C.char)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  for k = 0, math.floor(b.w * b.h / 9000) do
    local px, py = b.x + hash(b.seed + k * 3) * b.w, b.y + hash(b.seed * 7 + k) * b.h
    local s = 30 + hash(k + b.seed) * 50
    color(k % 2 == 0 and C.concreteDark or C.roofFlat)
    love.graphics.polygon("fill", px - s, py - s * 0.4, px + s * 0.6, py - s * 0.7, px + s, py + s * 0.5,
      px - s * 0.3, py + s * 0.8)
  end
  color(C.steelDark)
  love.graphics.setLineWidth(5)
  for k = 0, math.floor(b.h / 200) do
    local py = b.y + hash(b.seed * 5 + k) * b.h
    love.graphics.line(b.x + 10, py, b.x + b.w * (0.4 + hash(k) * 0.5), py + 20)
  end
  love.graphics.setLineWidth(1)
end

--- The overpass that crossed Downtown, standing on its pillars as far as
--- the road, and broken off there.
function ROOFS.overpass(b)
  color(C.wasteDark)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  local mid = b.x + b.w / 2
  local towardsRoad = mid < 0 and 1 or -1 -- the road's the middle of the map
  local y0, y1 = b.y + 14, b.y + b.h - 14
  color(C.concrete)
  love.graphics.rectangle("fill", b.x, y0, b.w, y1 - y0)
  color(C.concreteDark)
  love.graphics.rectangle("fill", b.x, y0, b.w, 8) -- the railings
  love.graphics.rectangle("fill", b.x, y1 - 8, b.w, 8)
  color(C.paint)
  for x = b.x + 16, b.x + b.w - 40, 72 do
    love.graphics.rectangle("fill", x, (y0 + y1) / 2 - 2, 40, 4)
  end
  -- The broken end: jagged, rebar hanging off it.
  local ex = towardsRoad > 0 and b.x + b.w or b.x
  color(C.wasteDark)
  local pts = {}
  for k = 0, 6 do
    local py = y0 + (y1 - y0) * k / 6
    pts[#pts + 1] = ex - towardsRoad * (8 + hash(b.seed + k) * 40)
    pts[#pts + 1] = py
  end
  pts[#pts + 1], pts[#pts + 2] = ex, y1
  pts[#pts + 1], pts[#pts + 2] = ex, y0
  love.graphics.polygon("fill", pts)
  color(C.steelDark)
  for k = 0, 5 do
    local py = y0 + 10 + k * (y1 - y0 - 20) / 5
    love.graphics.line(ex - towardsRoad * 30, py, ex + towardsRoad * 6, py + 6)
  end
end

--- A hedge between two yards, dead.
function ROOFS.hedge(b)
  color(C.waste)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  for x = b.x + 14, b.x + b.w - 10, 22 do
    local r = 14 + hash(x * 0.3) * 6
    color(C.hedgeDark)
    love.graphics.circle("fill", x + 3, b.y + b.h / 2 + 4, r, 10)
    color(C.hedge)
    love.graphics.circle("fill", x, b.y + b.h / 2, r - 3, 10)
  end
end

--- The starport's terminal past the gate: a long roof, a hazard edge.
function ROOFS.starport(b)
  color(C.roofTin)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(C.steelDark)
  for x = b.x + 64, b.x + b.w, 128 do
    love.graphics.rectangle("fill", x, b.y, 6, b.h)
  end
  color(C.hazard)
  love.graphics.rectangle("fill", b.x, b.y + b.h - 16, b.w, 16)
  color(C.black)
  for x = b.x, b.x + b.w, 32 do
    love.graphics.rectangle("fill", x, b.y + b.h - 16, 16, 16)
  end
end

--- The city's ground: every walked tile in its finish, burnt ground
--- elsewhere, the buildings' shadows, and their roofs over it.
local function drawCity(map, T)
  local look = OUTSIDE.waste
  local function waste(c, r)
    local col = map.tiles[c]
    return not (col and col[r])
  end
  for pass = 1, 3 do -- the waste ground in three passes, as past a base's walls
    for c = map.c0, map.c1 do
      for r = map.r0, map.r1 do
        if waste(c, r) then
          local x, y = map.x0 + c * T, map.y0 + r * T
          if pass == 1 then
            color(C[look.base])
            love.graphics.rectangle("fill", x, y, T, T)
          elseif pass == 2 then
            outsideBlotches(look, x, y, T)
          else
            outsideGrain(look, "waste", x, y, T, hash(c * 7.1 + r * 13.7))
          end
        end
      end
    end
  end
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      if col and col[r] then
        local x, y = map.x0 + c * T, map.y0 + r * T
        local z = groundAt(map, x + 1, y + 1)
        floorTile(FLOORS[z and z.floor or "asphalt"], x, y, T, hash(c * 7.1 + r * 13.7))
      end
    end
  end
  for _, b in ipairs(map.roofs) do -- the shadows, as long as the building is tall
    local tall = ROOF_HEIGHT[b.style] or 0
    if tall > 0 then
      love.graphics.setColor(0, 0, 0, 0.38)
      love.graphics.rectangle("fill", b.x + tall * 0.5, b.y + tall * 0.6, b.w, b.h)
      love.graphics.setColor(0, 0, 0, 0.18)
      love.graphics.rectangle("fill", b.x + tall * 0.8, b.y + tall, b.w, b.h)
    end
  end
  for _, b in ipairs(map.roofs) do
    ROOFS[b.style](b)
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

-- Heck on Earth's props ----------------------------------------------------------

--- Lane markings down a stretch of road: dashes between the lanes, a double
--- yellow line down the middle unless it's `oneway`.
function DRAW.lanes(s)
  local n = s.oneway and 3 or 6
  for k = 1, n - 1 do
    local x = s.x + s.w * k / n
    if not s.oneway and k == n / 2 then
      color(C.yellowLine, 0.7)
      love.graphics.rectangle("fill", x - 6, s.y, 4, s.h)
      love.graphics.rectangle("fill", x + 2, s.y, 4, s.h)
    else
      color(C.paint, 0.55)
      for y = s.y + 16, s.y + s.h - 40, 112 do
        love.graphics.rectangle("fill", x - 2, y, 4, 56)
      end
    end
  end
end

--- A zebra crossing over the road.
function DRAW.zebra(s)
  color(C.paint, 0.6)
  for x = s.x + 8, s.x + s.w - 24, 40 do
    love.graphics.rectangle("fill", x, s.y, 20, s.h)
  end
end

--- Flames: a bed of embers and tongues of fire licking up and dying, each
--- on its own beat, added so they brighten what's under them.
function DRAW.fire(s, t)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  love.graphics.setColor(0.08, 0.03, 0.02, 0.5)
  love.graphics.circle("fill", cx, cy, r * 0.9, 16)
  love.graphics.setBlendMode("add")
  for k = 0, 7 do
    local phase = (t * (1.3 + hash(s.seed + k) * 0.9) + hash(s.seed * 3 + k)) % 1
    local a = hash(s.seed * 5 + k) * 2 * math.pi
    local d = r * 0.45 * hash(s.seed * 7 + k)
    local fx, fy = cx + math.cos(a) * d, cy + math.sin(a) * d - phase * r * 0.5 -- rising
    local size = r * (0.55 - phase * 0.4)
    love.graphics.setColor(1, 0.35 + 0.3 * (1 - phase), 0.06, 0.55 * (1 - phase))
    love.graphics.ellipse("fill", fx, fy, size * 0.7, size, 10)
    love.graphics.setColor(1, 0.85, 0.4, 0.35 * (1 - phase))
    love.graphics.ellipse("fill", fx, fy + size * 0.2, size * 0.3, size * 0.45, 8)
  end
  love.graphics.setBlendMode("alpha")
end

--- A wreck, drawn nose up in its own frame (turned for one `across`), a
--- little skewed.
local function vehicle(s, draw)
  love.graphics.push()
  love.graphics.translate(s.x + s.w / 2, s.y + s.h / 2)
  love.graphics.rotate((s.across and math.pi / 2 or 0) + (s.tilt or 0))
  local w, h = s.w, s.h
  if s.across then
    w, h = h, w
  end
  color(C.shadow)
  love.graphics.rectangle("fill", -w / 2 + 6, -h / 2 + 8, w, h, 10)
  draw(w, h)
  love.graphics.pop()
end

local function wheels(w, h)
  color(C.tyre)
  for _, y in ipairs({ -h * 0.32, h * 0.28 }) do
    love.graphics.rectangle("fill", -w / 2 - 3, y - 10, 8, 20, 2)
    love.graphics.rectangle("fill", w / 2 - 5, y - 10, 8, 20, 2)
  end
end

--- A car left in the road: its paint (or the police's black and white), a
--- windscreen, the roof; burnt to the metal if it burned.
function DRAW.car(s)
  vehicle(s, function(w, h)
    wheels(w, h)
    local paint = s.police and C.white or PAINT[s.seed % #PAINT + 1]
    color(s.burning and C.char or paint)
    love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 12)
    if s.police and not s.burning then
      color(C.black)
      love.graphics.rectangle("fill", -w / 2, -h * 0.1, w, h * 0.35)
    end
    color(C.windscreen)
    love.graphics.rectangle("fill", -w / 2 + 6, -h * 0.28, w - 12, 18, 3) -- the windscreen
    love.graphics.rectangle("fill", -w / 2 + 7, h * 0.22, w - 14, 12, 3) -- the back window
    color(s.burning and C.wasteDark or paint)
    love.graphics.rectangle("fill", -w / 2 + 6, -h * 0.28 + 20, w - 12, h * 0.46, 4) -- the roof
    love.graphics.setColor(0, 0, 0, 0.2)
    love.graphics.rectangle("fill", -w / 2 + 6, -h * 0.28 + 20, (w - 12) / 2, h * 0.46, 4)
    if s.police then
      color(C.red)
      love.graphics.rectangle("fill", -w / 2 + 10, -4, w - 20, 8) -- the light bar
    end
    if not s.burning then
      color(C.paint, 0.8)
      love.graphics.polygon("fill", -6, -h * 0.28 + 2, 4, -h * 0.28 + 6, -2, -h * 0.28 + 14) -- a crack in the glass
    end
  end)
end

--- A van: boxier, a long flat roof.
function DRAW.van(s)
  vehicle(s, function(w, h)
    wheels(w, h)
    color(s.burning and C.char or PAINT[s.seed % #PAINT + 1])
    love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 6)
    color(C.windscreen)
    love.graphics.rectangle("fill", -w / 2 + 6, -h / 2 + 10, w - 12, 16, 3)
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", -w / 2 + 6, -h / 2 + 34, w - 12, h - 44, 3)
  end)
end

--- A bus: long, its roof vents in a row, a strip of windows down each side.
function DRAW.bus(s)
  vehicle(s, function(w, h)
    color(C.tyre)
    for _, y in ipairs({ -h * 0.36, h * 0.3 }) do
      love.graphics.rectangle("fill", -w / 2 - 3, y - 12, 8, 24, 2)
      love.graphics.rectangle("fill", w / 2 - 5, y - 12, 8, 24, 2)
    end
    color(s.burning and C.char or C.hazard)
    love.graphics.rectangle("fill", -w / 2, -h / 2, w, h, 8)
    color(C.windscreen)
    love.graphics.rectangle("fill", -w / 2 + 4, -h / 2 + 4, w - 8, 14, 3)
    love.graphics.rectangle("fill", -w / 2 + 2, -h / 2 + 24, 6, h - 40)
    love.graphics.rectangle("fill", w / 2 - 8, -h / 2 + 24, 6, h - 40)
    color(s.burning and C.wasteDark or C.white)
    for y = -h / 2 + 40, h / 2 - 40, 46 do
      love.graphics.rectangle("fill", -10, y, 20, 24, 3) -- the roof vents
    end
  end)
end

--- A street lamp: its post, the arm out over the road, the lamp lit or not.
function DRAW.lamp(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local dir = cx < 0 and 1 or -1 -- out over the road
  color(C.shadow)
  love.graphics.circle("fill", cx + 4, cy + 4, 7, 8)
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, 7, 8)
  love.graphics.setLineWidth(4)
  love.graphics.line(cx, cy, cx + dir * 40, cy)
  love.graphics.setLineWidth(1)
  if s.dead then
    color(C.steel)
  else
    love.graphics.setColor(1, 0.85, 0.6)
  end
  love.graphics.ellipse("fill", cx + dir * 40, cy, 9, 6, 10)
end

--- A tree burnt to its branches (in a planter down the Boulevard).
function DRAW.tree(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  if s.planter then
    color(C.concreteDark)
    love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 4)
    color(C.wasteDark)
    love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w - 12, s.h - 12, 3)
  end
  color(C.shadow)
  love.graphics.circle("fill", cx + 10, cy + 10, r * 0.8, 12)
  color(C.bark)
  love.graphics.setLineWidth(4)
  for k = 0, 6 do
    local a = k * 0.9 + cx * 0.01
    local ex, ey = cx + math.cos(a) * r * 1.1, cy + math.sin(a) * r * 1.1
    love.graphics.line(cx, cy, ex, ey)
    love.graphics.setLineWidth(2)
    love.graphics.line(ex, ey, ex + math.cos(a + 0.7) * 12, ey + math.sin(a + 0.7) * 12)
    love.graphics.setLineWidth(4)
  end
  love.graphics.setLineWidth(1)
  love.graphics.circle("fill", cx, cy, 9, 10)
end

--- A barricade across a side street: crates, tyres and planks piled up.
function DRAW.barricade(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 8, s.w, s.h)
  for k = 0, 9 do
    local px, py = s.x + hash(s.seed + k) * (s.w - 30), s.y + hash(s.seed * 3 + k) * (s.h - 30)
    if k % 3 == 0 then
      color(C.tyre)
      love.graphics.circle("fill", px + 14, py + 14, 14, 12)
      color(C.steelDark)
      love.graphics.circle("fill", px + 14, py + 14, 6, 8)
    elseif k % 3 == 1 then
      color(C.crateDark)
      love.graphics.rectangle("fill", px, py, 34, 30)
      color(C.crate)
      love.graphics.rectangle("fill", px + 3, py + 3, 28, 24)
    else
      color(C.wood)
      love.graphics.push()
      love.graphics.translate(px + 15, py + 15)
      love.graphics.rotate(hash(k + s.seed) * 3)
      love.graphics.rectangle("fill", -30, -5, 60, 10)
      love.graphics.pop()
    end
  end
end

--- A slab of the fallen overpass across the road, broken, rebar out of it.
function DRAW.deck(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 10, s.y + 14, s.w, s.h)
  local n = math.max(2, math.floor(s.w / 120))
  for k = 0, n - 1 do
    local x0, x1 = s.x + s.w * k / n, s.x + s.w * (k + 1) / n
    local j = (hash(s.seed + k) - 0.5) * 16
    color(k % 2 == 0 and C.concrete or C.concreteDark)
    love.graphics.polygon("fill", x0 + 4, s.y + j, x1 - 2, s.y - j, x1 + 4, s.y + s.h + j, x0 - 2, s.y + s.h - j)
  end
  color(C.paint, 0.6)
  love.graphics.rectangle("fill", s.x + 20, s.y + s.h / 2 - 2, s.w - 40, 4)
  color(C.steelDark)
  love.graphics.setLineWidth(3)
  for k = 0, 4 do
    local x = s.x + hash(s.seed * 7 + k) * s.w
    love.graphics.line(x, s.y + s.h, x + 10 - k * 4, s.y + s.h + 18)
  end
  love.graphics.setLineWidth(1)
end

--- A heap of broken concrete.
function DRAW.rubble(s)
  color(C.shadow)
  love.graphics.ellipse("fill", s.x + s.w / 2 + 8, s.y + s.h / 2 + 8, s.w / 2, s.h / 2, 14)
  for k = 0, 5 do
    local px, py = s.x + 10 + hash(s.seed + k) * (s.w - 20), s.y + 8 + hash(s.seed * 3 + k) * (s.h - 16)
    local r = 12 + hash(s.seed * 5 + k) * 14
    color(k % 2 == 0 and C.concrete or C.concreteDark)
    love.graphics.polygon("fill", px - r, py, px - r * 0.3, py - r * 0.8, px + r, py - r * 0.2,
      px + r * 0.4, py + r * 0.7)
  end
end

--- How hot the lava glows at `t`.
function RenderEternalMood.lavaPulse(t)
  return 0.8 + 0.12 * math.sin(t * 1.1) + 0.08 * math.sin(t * 4.7)
end

--- The Crater: a rim of broken road round a pit of lava, crust floating on
--- it and bright seams opening and closing.
function DRAW.crater(s, t)
  local cx, cy, rx, ry = s.x + s.w / 2, s.y + s.h / 2, s.w / 2, s.h / 2
  local pulse = RenderEternalMood.lavaPulse(t)
  color(C.char)
  love.graphics.ellipse("fill", cx, cy, rx, ry, 40)
  color(C.crust)
  love.graphics.ellipse("fill", cx, cy, rx - 18, ry - 18, 40)
  love.graphics.setColor(1, 0.30 + 0.1 * pulse, 0.04, 0.95)
  love.graphics.ellipse("fill", cx, cy, rx - 34, ry - 34, 40)
  for k = 0, 9 do -- plates of crust drifting round
    local a = k * 0.63 + t * 0.05 * (k % 2 == 0 and 1 or -1)
    local d = 0.25 + hash(s.seed + k) * 0.45
    local px, py = cx + math.cos(a) * (rx - 40) * d, cy + math.sin(a) * (ry - 40) * d
    local pr = 18 + hash(s.seed * 3 + k) * 26
    color(C.crust)
    love.graphics.ellipse("fill", px, py, pr, pr * 0.7, 10)
  end
  love.graphics.setBlendMode("add")
  love.graphics.setLineWidth(3)
  for k = 0, 7 do -- bright seams, opening and closing
    local glow = math.max(0, math.sin(t * (0.8 + hash(k) * 0.9) + k * 1.7))
    local a = hash(s.seed * 5 + k) * 2 * math.pi
    local px, py = cx + math.cos(a) * rx * 0.35, cy + math.sin(a) * ry * 0.35
    love.graphics.setColor(1, 0.8, 0.3, 0.6 * glow)
    love.graphics.line(px, py, px + math.cos(a + 1) * 40, py + math.sin(a + 1) * 30, px + math.cos(a) * 70,
      py + math.sin(a) * 60)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 0.85, 0.4, 0.35 * pulse)
  love.graphics.ellipse("fill", cx, cy, rx * 0.3, ry * 0.3, 24) -- the portal, deep in it
  love.graphics.setBlendMode("alpha")
end

--- The heat off the Crater over everything near it: a glow breathing with
--- the lava, embers rising out of it.
local function drawCraterGlow(s, t)
  local cx, cy, rx, ry = s.x + s.w / 2, s.y + s.h / 2, s.w / 2, s.h / 2
  local pulse = RenderEternalMood.lavaPulse(t)
  love.graphics.setBlendMode("add")
  for k = 1, 4 do
    local f = 0.9 + k * 0.15
    love.graphics.setColor(1, 0.3, 0.05, 0.05 * pulse * (1 - k / 5))
    love.graphics.ellipse("fill", cx, cy, rx * f, ry * f, 40)
  end
  for k = 0, 13 do -- embers drifting up off it
    local phase = (t * (0.25 + hash(k * 3.7) * 0.2) + hash(k * 9.1)) % 1
    local a = hash(k * 5.3) * 2 * math.pi
    local x = cx + math.cos(a) * rx * 0.7 + math.sin(t + k) * 12
    local y = cy + math.sin(a) * ry * 0.7 - phase * 260
    love.graphics.setColor(1, 0.6, 0.2, 0.8 * (1 - phase))
    love.graphics.circle("fill", x, y, 3 * (1 - phase) + 1, 6)
  end
  love.graphics.setBlendMode("alpha")
end

--- A crack in the road with Heck glowing in it (an imp's way out).
function DRAW.crack(s, t)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local glow = 0.6 + 0.4 * math.sin(t * 2 + cx * 0.01)
  color(C.char)
  love.graphics.setLineWidth(7)
  love.graphics.line(cx - 26, cy - 6, cx - 8, cy + 4, cx + 6, cy - 5, cx + 26, cy + 6)
  love.graphics.setLineWidth(3)
  love.graphics.setColor(1, 0.4, 0.05, glow)
  love.graphics.line(cx - 24, cy - 6, cx - 8, cy + 4, cx + 6, cy - 5, cx + 24, cy + 6)
  love.graphics.setLineWidth(1)
end

--- A manhole cover (an imp's waiting under it).
function DRAW.manhole(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2 - 2
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 20)
  color(C.black)
  love.graphics.circle("line", cx, cy, r - 4, 20)
  for k = -12, 12, 6 do
    love.graphics.line(cx - 14, cy + k, cx + 14, cy + k)
  end
end

--- The UAC's sandbags, two rows of them.
function DRAW.sandbags(s)
  color(C.shadow)
  love.graphics.rectangle("fill", s.x + 6, s.y + 8, s.w, s.h, 8)
  for row = 0, 1 do
    for x = s.x + 14 + row * 14, s.x + s.w - 14, 28 do
      color(row == 0 and C.crateDark or C.crate)
      love.graphics.ellipse("fill", x, s.y + 9 + row * 14, 15, 9, 10)
    end
  end
end

--- One of the starport gate's pillars: concrete, hazard-striped, a lamp.
function DRAW.gate(s)
  shadow(s)
  box(s, C.concreteDark)
  box(s, C.concrete, 6)
  color(C.hazard)
  love.graphics.rectangle("fill", s.x + 6, s.y + s.h - 22, s.w - 12, 16)
  color(C.black)
  for x = s.x + 6, s.x + s.w - 20, 24 do
    love.graphics.rectangle("fill", x, s.y + s.h - 22, 12, 16)
  end
end

--- The landing pad in the Depot: a ring and an H.
function DRAW.pad(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.concreteDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.hazard)
  love.graphics.setLineWidth(10)
  love.graphics.circle("line", cx, cy, math.min(s.w, s.h) / 2 - 20, 40)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("fill", s.x, s.y, s.w, 10)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 10, s.w, 10)
end

-- The shuttle's outline, in its own frame (384 x 512 px, nose at the top
-- middle): half the hull's width every so far down it, nose to tail.
local HULL = { { 0, 6 }, { 16, 22 }, { 40, 38 }, { 75, 52 }, { 120, 62 }, { 160, 64 }, { 440, 64 }, { 480, 58 },
  { 494, 50 } }

--- The hull's outline, `k` of its width: a polygon round the middle (192).
local function hull(k)
  local pts = {}
  for _, p in ipairs(HULL) do
    pts[#pts + 1], pts[#pts + 2] = 192 + p[2] * k, p[1]
  end
  for i = #HULL, 1, -1 do
    pts[#pts + 1], pts[#pts + 2] = 192 - HULL[i][2] * k, HULL[i][1]
  end
  return pts
end

--- Its half width `y` px down it.
local function hullAt(y)
  for i = 2, #HULL do
    local a, b = HULL[i - 1], HULL[i]
    if y <= b[1] then
      return a[2] + (b[2] - a[2]) * (y - a[1]) / (b[1] - a[1])
    end
  end
  return HULL[#HULL][2]
end

--- One wing, `side` 1 east, -1 west: a delta, root along the hull.
local function wing(side)
  local x = function(dx)
    return 192 + dx * side
  end
  return { x(58), 200, x(188), 392, x(188), 440, x(58), 440 }
end

--- The shuttle down from Fobos Base (or Earth), nose north, on the pad,
--- drawn in its own 384 x 512 frame and stretched to fit its box: a
--- rounded hull with its panels seamed and riveted, portholes lit along its
--- sides, a cargo bay, a hatch, a framed canopy at the nose with the light
--- catching it; delta wings with their flaps, hazard chevrons, the UAC's
--- name and its number, nav lights blinking red and green at the tips;
--- canards, a tail fin and its stabilisers; three engines still warm,
--- glowing, steaming, the pad scorched behind them; a beacon strobing on
--- its back; and its ramp down on the east side, lit from inside.
function DRAW.shuttle(s, t)
  local lg = love.graphics
  lg.push()
  lg.translate(s.x, s.y)
  lg.scale(s.w / 384, s.h / 512)
  -- The pad scorched black behind the engines, and the shadow.
  color(C.char, 0.55)
  lg.ellipse("fill", 192, 548, 96, 46, 24)
  color(C.char, 0.35)
  lg.ellipse("fill", 192, 530, 130, 70, 24)
  lg.push()
  lg.translate(16, 16)
  color(C.shadow)
  lg.polygon("fill", hull(1))
  lg.polygon("fill", wing(1))
  lg.polygon("fill", wing(-1))
  lg.pop()

  -- The wings: a darker underside showing at the edge, the top, the
  -- leading edge, panel lines, flaps, chevrons, the lettering.
  for _, side in ipairs({ -1, 1 }) do
    local x = function(dx)
      return 192 + dx * side
    end
    color(C.black)
    lg.polygon("fill", x(56), 196, x(192), 390, x(192), 444, x(56), 444)
    color(C.steelDark)
    lg.polygon("fill", wing(side))
    color(C.steel)
    lg.polygon("fill", x(70), 236, x(176), 392, x(176), 420, x(70), 420)
    color(C.trim) -- the leading edge
    lg.setLineWidth(6)
    lg.line(x(60), 203, x(186), 391)
    color(C.wallSeam) -- panels
    lg.setLineWidth(1.5)
    for k = 1, 3 do
      local dx = 58 + k * 32
      lg.line(x(dx), 200 + (dx - 58) * 1.48 + 6, x(dx), 426)
    end
    lg.line(x(70), 380, x(176), 380)
    for k = 0, 3 do -- the flaps, one down a touch
      color(k == 1 and C.wallSeam or C.steelDark)
      lg.rectangle("fill", side == 1 and x(66 + k * 30) or x(66 + k * 30) - 26, 424, 26, 16)
    end
    color(C.hazard) -- chevrons near the tip
    for k = 0, 2 do
      local cx, cy = x(150 + k * 12), 404
      lg.polygon("fill", cx, cy - 8, cx + 6 * side, cy, cx, cy + 8, cx - 4 * side, cy)
    end
    color(C.char, 0.35) -- grime off the engines
    lg.ellipse("fill", x(84), 434, 26, 8, 10)
    -- The nav light: red to port (west), green to starboard (east),
    -- blinking out of step.
    local on = (t * 1.2 + (side == 1 and 0.5 or 0)) % 1 < 0.18
    local r, g, b = 1, 0.15, 0.1
    if side == 1 then
      r, g, b = 0.2, 1, 0.35
    end
    lg.setColor(r * 0.5, g * 0.5, b * 0.5)
    lg.circle("fill", x(186), 416, 5, 10)
    if on then
      lg.setBlendMode("add")
      lg.setColor(r, g, b, 0.5)
      lg.circle("fill", x(186), 416, 18, 16)
      lg.setColor(r, g, b, 1)
      lg.circle("fill", x(186), 416, 5, 10)
      lg.setBlendMode("alpha")
    end
    color(C.black) -- a thruster block at the tip
    lg.rectangle("fill", side == 1 and x(176) or x(176) - 10, 396, 10, 8)
    -- The canards up by the nose.
    color(C.steelDark)
    lg.polygon("fill", x(48), 96, x(98), 124, x(98), 134, x(46), 132)
    color(C.trim)
    lg.setLineWidth(3)
    lg.line(x(49), 98, x(97), 125)
    -- The tail's stabilisers.
    color(C.steelDark)
    lg.polygon("fill", x(48), 452, x(112), 486, x(112), 496, x(48), 492)
    color(C.trim)
    lg.line(x(50), 454, x(111), 487)
    lg.setLineWidth(1)
  end
  lg.setFont(signFont())
  color(C.paint, 0.85)
  lg.print("UAC", 192 + 100, 352, 0, 1.2, 1.2)
  lg.print("FB-07", 192 - 152, 334, 0, 1.0, 1.0)

  -- The hull: dark at its edges, lighter up its back, a gleam down the spine.
  color(C.wallSeam)
  lg.polygon("fill", hull(1.04))
  color(C.steelDark)
  lg.polygon("fill", hull(1))
  color(C.steel)
  lg.polygon("fill", hull(0.82))
  color(C.trim, 0.6)
  lg.polygon("fill", hull(0.3))
  color(C.white, 0.25)
  lg.rectangle("fill", 186, 110, 6, 340)
  -- The nose cap, scorched from coming in.
  color(C.wallSeam)
  lg.ellipse("fill", 192, 12, 9, 14, 12)
  color(C.char, 0.35)
  lg.ellipse("fill", 192, 22, 16, 20, 14)

  -- Seams across it and down it, rivets along them.
  color(C.wallSeam)
  lg.setLineWidth(1.5)
  for y = 150, 430, 40 do
    local hw = hullAt(y) - 3
    lg.line(192 - hw, y, 192 + hw, y)
    color(C.trim)
    for x = 192 - hw + 6, 192 + hw - 6, 12 do
      lg.circle("fill", x, y + 4, 1, 4)
    end
    color(C.wallSeam)
  end
  for _, dx in ipairs({ -34, 34 }) do
    lg.line(192 + dx, 120, 192 + dx, 470)
  end
  -- The cargo bay doors, shut, hinged down the middle.
  lg.setLineWidth(2)
  lg.rectangle("line", 192 - 30, 196, 60, 150, 3)
  lg.line(192, 196, 192, 346)
  for y = 210, 330, 40 do
    lg.rectangle("fill", 188, y, 8, 6)
  end
  lg.setLineWidth(1)
  -- Portholes down both sides, lit warm inside.
  for _, dx in ipairs({ -50, 50 }) do
    for y = 140, 320, 26 do
      color(C.black)
      lg.circle("fill", 192 + dx, y, 6, 12)
      lg.setColor(1, 0.75, 0.4, 0.55 + 0.1 * math.sin(t * 2 + y))
      lg.circle("fill", 192 + dx, y, 3.5, 10)
    end
  end
  -- The UAC's stripes, the white band, a hatch, the sensor dome, aerials.
  color(C.white)
  lg.rectangle("fill", 192 - 62, 170, 124, 12)
  color(C.hazard)
  lg.rectangle("fill", 192 - 62, 400, 124, 12)
  color(C.black)
  for x = 192 - 62, 192 + 50, 24 do
    lg.polygon("fill", x, 400, x + 12, 400, x + 18, 412, x + 6, 412)
  end
  color(C.wallSeam)
  lg.circle("fill", 192, 372, 13, 16)
  color(C.steelDark)
  lg.circle("fill", 192, 372, 10, 16)
  color(C.wallSeam)
  lg.setLineWidth(2)
  lg.line(184, 372, 200, 372)
  lg.line(192, 364, 192, 380)
  color(C.trim)
  lg.circle("fill", 192, 128, 8, 14)
  color(C.white, 0.6)
  lg.circle("fill", 190, 126, 3, 8)
  color(C.black)
  lg.line(176, 140, 168, 160)
  lg.line(208, 140, 216, 162)
  lg.setLineWidth(1)
  for _, dx in ipairs({ -1, 1 }) do -- thruster blocks at the nose
    color(C.black)
    lg.rectangle("fill", 192 + dx * 40 - 4, 62, 8, 10)
  end

  -- The canopy: framed panes, the light catching the glass.
  color(C.wallSeam)
  lg.polygon("fill", 192, 26, 226, 68, 230, 100, 154, 100, 158, 68)
  color(C.windscreen)
  lg.polygon("fill", 192, 32, 222, 70, 225, 95, 159, 95, 162, 70)
  lg.setColor(0.95, 0.55, 0.35, 0.18) -- Heck's light in it
  lg.polygon("fill", 192, 32, 222, 70, 192, 70)
  color(C.wallSeam)
  lg.setLineWidth(3)
  lg.line(192, 30, 192, 96)
  lg.line(160, 72, 224, 72)
  lg.setLineWidth(2)
  lg.setColor(1, 1, 1, 0.35)
  lg.line(172, 64, 186, 44)
  lg.line(176, 88, 182, 80)
  lg.setLineWidth(1)

  -- The tail fin, seen from above: a blade down the spine.
  color(C.wallSeam)
  lg.polygon("fill", 192, 392, 199, 430, 199, 500, 185, 500, 185, 430)
  color(C.trim)
  lg.polygon("fill", 192, 396, 196, 430, 196, 496, 192, 496)
  color(C.red)
  lg.rectangle("fill", 186, 470, 12, 8)

  -- The engines, three bells at the tail pointing aft, seen from above: each
  -- flares out from its mount to an oval mouth, still glowing, still ticking.
  -- The middle one sits further back, so it goes on last.
  local warm = 0.55 + 0.15 * math.sin(t * 3) + 0.05 * math.sin(t * 17)
  for _, ex in ipairs({ -40, 40, 0 }) do
    local mid = ex == 0
    local r = mid and 18 or 24
    local x, y = 192 + ex, 492 + (mid and 10 or 0) -- the mouth's centre
    local ry = r * 0.38
    local top, throat = y - r * 1.5, r * 0.55
    color(C.steelDark)
    lg.rectangle("fill", x - throat - 2, top - 14, (throat + 2) * 2, 16)
    color(C.wallSeam)
    lg.polygon("fill", x - throat - 2, top, x + throat + 2, top, x + r + 3, y, x - r - 3, y)
    color(C.steelDark)
    lg.polygon("fill", x - throat, top, x + throat, top, x + r, y, x - r, y)
    color(C.trim, 0.5) -- the light down its curve
    lg.polygon("fill", x - throat * 0.5, top, x - throat * 0.1, top, x - r * 0.2, y, x - r * 0.7, y)
    color(C.wallSeam)
    lg.ellipse("fill", x, y, r + 3, ry + 3, 20)
    color(C.black)
    lg.ellipse("fill", x, y, r, ry, 20)
    lg.setColor(1, 0.4, 0.1, warm)
    lg.ellipse("fill", x, y + ry * 0.15, r * 0.65, ry * 0.6, 16)
    lg.setColor(1, 0.85, 0.5, warm * 0.6)
    lg.ellipse("fill", x, y + ry * 0.2, r * 0.3, ry * 0.3, 12)
    color(C.trim)
    lg.setLineWidth(2)
    lg.ellipse("line", x, y, r, ry, 20)
    lg.setLineWidth(1)
    lg.setBlendMode("add") -- the heat off it, trailing aft
    lg.setColor(1, 0.35, 0.08, 0.12 * warm)
    lg.ellipse("fill", x, y + r * 0.9, r * 1.2, r * 1.5, 20)
    lg.setBlendMode("alpha")
  end
  for k = 0, 5 do -- steam curling off them
    local ph = (t * 0.35 + k / 6) % 1
    local ex = ({ -40, 0, 40 })[k % 3 + 1]
    local drift = (hash(k + 3) - 0.5) * 60
    lg.setColor(0.75, 0.72, 0.70, 0.28 * (1 - ph) * math.min(1, ph * 6))
    lg.circle("fill", 192 + ex + drift * ph, 500 + ph * 60, 8 + ph * 26, 14)
  end

  -- The beacon on its back, strobing red.
  local strobe = (t * 0.8) % 1 < 0.1
  color(C.wallSeam)
  lg.circle("fill", 192, 300, 6, 10)
  lg.setColor(strobe and 1 or 0.4, 0.1, 0.08)
  lg.circle("fill", 192, 300, 4, 10)
  if strobe then
    lg.setBlendMode("add")
    lg.setColor(1, 0.15, 0.1, 0.45)
    lg.circle("fill", 192, 300, 34, 20)
    lg.setBlendMode("alpha")
  end

  -- The ramp, down on the east side: hinged at the hull, treads across it,
  -- hazard edges, guide lights, its rams, the light from inside.
  local hx = 192 + 64
  lg.setBlendMode("add")
  local spill = 0.10 + 0.02 * math.sin(t * 2)
  for k = 1, 3 do -- fading out across the pad
    lg.setColor(1, 0.7, 0.4, spill)
    local reach = 86 + k * 14
    lg.polygon("fill", hx, 232, hx + reach, 232 - k * 4, hx + reach, 330 + k * 4, hx, 330)
  end
  lg.setBlendMode("alpha")
  color(C.wallSeam)
  lg.polygon("fill", hx - 2, 222, hx + 90, 234, hx + 90, 328, hx - 2, 340)
  color(C.steelDark)
  lg.polygon("fill", hx, 226, hx + 86, 237, hx + 86, 325, hx, 336)
  color(C.wallSeam)
  lg.setLineWidth(2)
  for x = hx + 10, hx + 80, 10 do
    local k = (x - hx) / 86
    lg.line(x, 226 + 11 * k + 8, x, 336 - 11 * k - 8)
  end
  color(C.hazard)
  lg.setLineWidth(5)
  lg.line(hx, 228, hx + 86, 239)
  lg.line(hx, 334, hx + 86, 323)
  for k = 0, 3 do -- guide lights down its edges
    local x = hx + 12 + k * 22
    lg.setColor(1, 0.8, 0.5, 0.6 + 0.4 * (((t * 2 - k * 0.25) % 1) < 0.3 and 1 or 0))
    lg.circle("fill", x, 236 + k * 3, 2.5, 6)
    lg.circle("fill", x, 326 - k * 3, 2.5, 6)
  end
  color(C.black) -- the rams
  lg.setLineWidth(4)
  lg.line(hx - 6, 246, hx + 40, 246)
  lg.line(hx - 6, 316, hx + 40, 316)
  color(C.trim)
  lg.setLineWidth(2)
  lg.line(hx - 6, 246, hx + 18, 246)
  lg.line(hx - 6, 316, hx + 18, 316)
  lg.setLineWidth(1)
  color(C.black) -- the doorway
  lg.rectangle("fill", hx - 4, 232, 6, 98)
  lg.pop()
end

-- The Foundry's props -------------------------------------------------------------

--- A conveyor belt running `dir` (1 east, -1 west) at `speed` px/s: dark
--- rubber with ribs going by, rollers at its edges, chevrons showing which
--- way, and lumps of Heck's ore riding on it.
function DRAW.belt(s, t)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.belt)
  love.graphics.rectangle("fill", s.x, s.y + 6, s.w, s.h - 12)
  local shift = (t * s.speed * s.dir) % 32
  color(C.beltLine)
  for x = s.x - 32 + shift, s.x + s.w, 32 do
    if x >= s.x then
      love.graphics.rectangle("fill", x, s.y + 6, 3, s.h - 12)
    end
  end
  color(C.hazard, 0.7) -- chevrons
  local mid = s.y + s.h / 2
  local step = 256
  local cshift = (t * s.speed * s.dir) % step
  for x = s.x - step + cshift, s.x + s.w, step do
    if x > s.x + 20 and x < s.x + s.w - 20 then
      local d = s.dir * 14
      love.graphics.polygon("fill", x - d, mid - 18, x + d, mid, x - d, mid + 18, x - d * 0.4, mid)
    end
  end
  for k = 0, math.floor(s.w / 180) do -- ore riding along
    local base = hash(s.seed + k) * s.w
    local x = s.x + (base + t * s.speed * s.dir) % s.w
    local y = s.y + 16 + hash(s.seed * 3 + k) * (s.h - 40)
    color(C.rockWallDark)
    love.graphics.ellipse("fill", x, y, 14, 10, 8)
    love.graphics.setColor(1, 0.4, 0.08, 0.8)
    love.graphics.circle("fill", x + 2, y - 1, 3, 6)
  end
  color(C.steel) -- the rollers' edges
  love.graphics.rectangle("fill", s.x, s.y, s.w, 6)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 6, s.w, 6)
end

--- How hot the lava is at `t`, for anything of the Foundry's lava.
local function molten(t, seed)
  return 0.8 + 0.12 * math.sin(t * 1.3 + seed) + 0.08 * math.sin(t * 5.1 + seed * 2)
end

--- A vat of lava: a thick steel rim, the lava in it churning, bubbles.
function DRAW.vat(s, t)
  shadow(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  local m = molten(t, s.seed)
  color(C.steelDark)
  love.graphics.circle("fill", cx, cy, r, 32)
  color(C.steel)
  love.graphics.circle("line", cx, cy, r - 4, 32)
  for k = 0, 7 do
    local a = k * math.pi / 4
    color(C.wallSeam)
    love.graphics.circle("fill", cx + math.cos(a) * (r - 8), cy + math.sin(a) * (r - 8), 3, 6)
  end
  love.graphics.setColor(1, 0.32 + 0.12 * m, 0.04)
  love.graphics.circle("fill", cx, cy, r - 14, 28)
  for k = 0, 4 do
    local phase = (t * (0.4 + hash(s.seed + k) * 0.5) + hash(s.seed * 2 + k)) % 1
    local bx = cx + (hash(s.seed + k * 3) - 0.5) * (r - 30) * 1.4
    local by = cy + (hash(s.seed * 5 + k) - 0.5) * (r - 30) * 1.4
    love.graphics.setColor(1, 0.85, 0.4, 1 - phase)
    love.graphics.circle(phase < 0.85 and "fill" or "line", bx, by, 3 + phase * 8, 10)
  end
  for k = 0, 3 do -- crust drifting round on it
    local a = t * 0.15 * (k % 2 == 0 and 1 or -1) + k * 1.6 + s.seed
    local d = (r - 26) * (0.3 + hash(s.seed + k * 7) * 0.5)
    color(C.crust)
    love.graphics.ellipse("fill", cx + math.cos(a) * d, cy + math.sin(a) * d, 8 + k * 2, 5 + k, 10)
  end
end

-- A stretch of lava (the Foundry's moat, Heck's sea) is a rectangle, and
-- several side by side make one body: only where an edge meets rock does it
-- get a shore. Worked out once a map (`prepareLava`): each edge in SHORE_STEP
-- px pieces, a piece a shore unless more lava lies just past it, each with
-- how deep its crust runs in at either end.
local SHORE_STEP = 32
local CRUST_MIN, CRUST_MAX = 8, 26

local function lavaAt(list, x, y)
  for _, o in ipairs(list) do
    if x >= o.x and x <= o.x + o.w and y >= o.y and y <= o.y + o.h then
      return true
    end
  end
  return false
end

--- Each stretch of `map`'s lava, its shore: { ax, ay, bx, by, nx, ny, da, db }
--- pieces, (nx, ny) pointing into the lava, da and db the crust's depth.
local function prepareLava(map)
  if map.lavaShores then
    return
  end
  map.lavaShores = true
  local list = {}
  for _, o in ipairs(map.cover) do
    if o.kind == "lava" then
      list[#list + 1] = o
    end
  end
  local function depthAt(x, y)
    return CRUST_MIN + hash(x * 0.37 + y * 0.71) * (CRUST_MAX - CRUST_MIN)
  end
  for _, o in ipairs(list) do
    o.shore = {}
    local edges = { -- start, end, the way in
      { o.x, o.y, o.x + o.w, o.y, 0, 1 }, { o.x, o.y + o.h, o.x + o.w, o.y + o.h, 0, -1 },
      { o.x, o.y, o.x, o.y + o.h, 1, 0 }, { o.x + o.w, o.y, o.x + o.w, o.y + o.h, -1, 0 },
    }
    for _, e in ipairs(edges) do
      local len = math.max(math.abs(e[3] - e[1]), math.abs(e[4] - e[2]))
      local n = math.max(1, math.floor(len / SHORE_STEP + 0.5))
      for i = 0, n - 1 do
        local ax, ay = e[1] + (e[3] - e[1]) * i / n, e[2] + (e[4] - e[2]) * i / n
        local bx, by = e[1] + (e[3] - e[1]) * (i + 1) / n, e[2] + (e[4] - e[2]) * (i + 1) / n
        local mx, my = (ax + bx) / 2 - e[5] * 4, (ay + by) / 2 - e[6] * 4 -- just past the edge
        if not lavaAt(list, mx, my) then
          o.shore[#o.shore + 1] = { ax, ay, bx, by, e[5], e[6], depthAt(ax, ay), depthAt(bx, by) }
        end
      end
    end
  end
end

--- A plate of crust: a lumpy polygon round (x, y), `r` across, its own shape.
local function plate(x, y, r, seed)
  local pts = {}
  for k = 0, 5 do
    local a = k / 6 * 2 * math.pi
    local d = r * (0.7 + hash(seed + k * 1.9) * 0.5)
    pts[#pts + 1], pts[#pts + 2] = x + math.cos(a) * d, y + math.sin(a) * d * 0.75
  end
  love.graphics.polygon("fill", pts)
end

--- A stretch of lava: molten, plates of crust drifting on a slow current,
--- bright seams opening and closing; and where it meets rock a ragged
--- shore of cooled crust with the heat showing along its edge.
function DRAW.lava(s, t)
  local m = molten(t, 0) -- one pulse for all of it: stretches side by side are one body
  love.graphics.setColor(1, 0.30 + 0.12 * m, 0.04)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  local ox, oy, ow, oh = love.graphics.getScissor() -- the plates stay inside it
  local sx, sy = love.graphics.transformPoint(s.x, s.y)
  local ex, ey = love.graphics.transformPoint(s.x + s.w, s.y + s.h)
  love.graphics.intersectScissor(math.floor(sx), math.floor(sy), math.ceil(ex - sx), math.ceil(ey - sy))
  local drift = (s.seed % 2 == 0) and 1 or -1
  for k = 0, math.floor(s.w * s.h / 5000) do
    local speed = 5 + hash(s.seed * 7 + k) * 7
    local px = s.x + (hash(s.seed + k) * (s.w + 80) + t * speed * drift) % (s.w + 80) - 40
    local py = s.y + hash(s.seed * 3 + k) * s.h + math.sin(t * 0.3 + k) * 6
    local r = 10 + hash(k * 1.7 + s.seed) * 18
    love.graphics.setColor(C.crust[1], C.crust[2], C.crust[3], 0.75 + hash(k) * 0.25)
    plate(px, py, r, s.seed + k)
  end
  love.graphics.setBlendMode("add")
  love.graphics.setLineWidth(2)
  for k = 0, math.floor(s.w * s.h / 20000) do -- seams opening and closing
    local glow = math.max(0, math.sin(t * (0.6 + hash(s.seed + k * 5) * 0.8) + k * 2.1))
    local px, py = s.x + hash(s.seed * 11 + k) * s.w, s.y + hash(s.seed * 13 + k) * s.h
    local a = hash(s.seed * 17 + k) * math.pi
    love.graphics.setColor(1, 0.8, 0.3, 0.55 * glow)
    love.graphics.line(px, py, px + math.cos(a) * 26, py + math.sin(a) * 18, px + math.cos(a + 0.6) * 50,
      py + math.sin(a + 0.6) * 34)
  end
  love.graphics.setColor(1, 0.8, 0.3, 0.18 * m)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  love.graphics.setBlendMode("alpha")
  love.graphics.setScissor(ox, oy, ow, oh)
  -- The shore: crust in from the rock, the heat showing along its edge.
  for _, p in ipairs(s.shore or {}) do
    local ax, ay, bx, by, nx, ny, da, db = p[1], p[2], p[3], p[4], p[5], p[6], p[7], p[8]
    color(C.crust)
    love.graphics.polygon("fill", ax, ay, bx, by, bx + nx * db, by + ny * db, ax + nx * da, ay + ny * da)
    color(C.char)
    love.graphics.polygon("fill", ax, ay, bx, by, bx + nx * db * 0.4, by + ny * db * 0.4, ax + nx * da * 0.4,
      ay + ny * da * 0.4)
  end
  love.graphics.setBlendMode("add")
  love.graphics.setLineWidth(3)
  for _, p in ipairs(s.shore or {}) do
    local nx, ny, da, db = p[5], p[6], p[7], p[8]
    love.graphics.setColor(1, 0.75, 0.25, 0.55 * m)
    love.graphics.line(p[1] + nx * da, p[2] + ny * da, p[3] + nx * db, p[4] + ny * db)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setBlendMode("alpha")
end

--- The Crucible's pit: the Crater's lava, deeper.
function DRAW.crucible(s, t)
  DRAW.crater(s, t)
end

--- The stone ring round the Crucible: flagstones in a band, worn.
function DRAW.ring(s)
  color(C.concreteDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 18)
  color(C.concrete)
  for x = s.x, s.x + s.w - 1, 48 do
    for y = s.y, s.y + s.h - 1, 48 do
      love.graphics.rectangle("fill", x + 3, y + 3, math.min(42, s.x + s.w - x - 6), math.min(42, s.y + s.h - y - 6), 4)
    end
  end
  love.graphics.setColor(0.6, 0.15, 0.05, 0.5) -- runes scorched into it
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", s.x + 14, s.y + 14, s.w - 28, s.h - 28, 14)
  love.graphics.setLineWidth(1)
end

--- A stone bridge over the moat: slabs across, a kerb either side.
function DRAW.bridge(s)
  color(C.concreteDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.concrete)
  if s.ns then
    for y = s.y + 4, s.y + s.h - 20, 24 do
      love.graphics.rectangle("fill", s.x + 10, y, s.w - 20, 18, 2)
    end
  else
    for x = s.x + 4, s.x + s.w - 20, 24 do
      love.graphics.rectangle("fill", x, s.y + 10, 18, s.h - 20, 2)
    end
  end
end

--- The way down into Heck: a ring of bone round a swirl of red, turning.
function DRAW.gateway(s, t)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local rx, ry = s.w / 2, s.h / 2
  love.graphics.setColor(0.10, 0.02, 0.03)
  love.graphics.ellipse("fill", cx, cy, rx, ry, 32)
  love.graphics.setBlendMode("add")
  for k = 0, 5 do
    local a = t * (0.8 + k * 0.2) + k
    love.graphics.setColor(1, 0.2 + k * 0.05, 0.3, 0.18)
    love.graphics.arc("fill", cx, cy, rx * (0.9 - k * 0.12), a, a + 2.2, 16)
  end
  love.graphics.setColor(1, 0.6, 0.5, 0.4 + 0.2 * math.sin(t * 3))
  love.graphics.ellipse("fill", cx, cy, rx * 0.2, ry * 0.3, 16)
  love.graphics.setBlendMode("alpha")
  color(C.bone)
  for k = 0, 13 do -- the ring of bones round it
    local a = k / 14 * 2 * math.pi
    love.graphics.circle("fill", cx + math.cos(a) * rx, cy + math.sin(a) * ry, 7, 8)
  end
end

--- Chains hanging from the roof, swinging a little.
function DRAW.chain(s, t)
  local sway = math.sin(t * 0.9 + s.seed) * 6
  color(C.steelDark)
  for k = 0, math.floor(s.h / 10) do
    local f = k / (s.h / 10)
    love.graphics.ellipse("line", s.x + s.w / 2 + sway * f, s.y + k * 10, 3, 5, 6)
  end
  color(C.steel)
  love.graphics.polygon("fill", s.x + s.w / 2 + sway - 6, s.y + s.h, s.x + s.w / 2 + sway + 6, s.y + s.h,
    s.x + s.w / 2 + sway, s.y + s.h + 12) -- the hook
end

--- Heck coming up through the floor: a patch of rock, bones in it.
function DRAW.growth(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.rockWall, 0.85)
  local pts = {}
  for k = 0, 9 do
    local a = k / 10 * 2 * math.pi
    local d = r * (0.6 + hash(s.seed + k) * 0.4)
    pts[#pts + 1] = cx + math.cos(a) * d
    pts[#pts + 1] = cy + math.sin(a) * d
  end
  love.graphics.polygon("fill", pts)
  color(C.rockWallDark)
  love.graphics.circle("fill", cx + r * 0.2, cy - r * 0.1, r * 0.3, 10)
  color(C.bone)
  local a = hash(s.seed * 7) * math.pi
  love.graphics.setLineWidth(4)
  love.graphics.line(cx - math.cos(a) * r * 0.5, cy - math.sin(a) * r * 0.5, cx + math.cos(a) * r * 0.5,
    cy + math.sin(a) * r * 0.5)
  love.graphics.setLineWidth(1)
end

--- A spire of Heck's rock, come up through the floor: solid, sharp.
function DRAW.spire(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.shadow)
  love.graphics.circle("fill", cx + 8, cy + 10, r, 12)
  color(C.rockWallDark)
  love.graphics.circle("fill", cx, cy, r, 8)
  color(C.rockWall)
  love.graphics.polygon("fill", cx - r * 0.8, cy + r * 0.3, cx, cy - r * 0.9, cx + r * 0.6, cy + r * 0.5)
  color(C.bone)
  love.graphics.circle("fill", cx + 2, cy - r * 0.4, 4, 6) -- its point
end

--- Dr. Seek's booth: glass walls round a desk, his jar on it, the brain in
--- the jar bubbling and its little light blinking as he talks.
function DRAW.booth(s, t)
  shadow(s)
  color(C.steelDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.steel)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w - 12, s.h - 12)
  color(C.wood)
  love.graphics.rectangle("fill", s.x + s.w * 0.25, s.y + s.h * 0.35, s.w * 0.5, s.h * 0.4) -- the desk
  local cx, cy = s.x + s.w / 2, s.y + s.h * 0.55
  color(C.jar)
  love.graphics.circle("fill", cx, cy, 26, 20)
  color(C.brain)
  love.graphics.ellipse("fill", cx, cy, 15, 12, 16)
  love.graphics.setColor(0.7, 0.35, 0.40)
  love.graphics.line(cx - 10, cy, cx + 10, cy)
  love.graphics.line(cx, cy - 9, cx - 4, cy + 9)
  for k = 0, 3 do -- bubbles
    local phase = (t * 0.8 + k / 4) % 1
    love.graphics.setColor(1, 1, 1, 0.6 * (1 - phase))
    love.graphics.circle("line", cx - 12 + k * 8, cy + 18 - phase * 36, 2.5, 6)
  end
  local talk = math.sin(t * 9) > 0 and 1 or 0.3
  love.graphics.setColor(0.3, 1, 0.4, talk)
  love.graphics.circle("fill", cx + 22, cy - 18, 4, 8) -- the speaker light
  color(C.glassBooth) -- the glass
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  love.graphics.setColor(1, 1, 1, 0.35)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", s.x + 2, s.y + 2, s.w - 4, s.h - 4)
  love.graphics.setLineWidth(1)
end

--- Bones lying about: a skull and a few long ones.
function DRAW.bones(s)
  turned(s, function()
    color(C.bone)
    love.graphics.circle("fill", 0, 0, 8, 10) -- the skull
    color(C.black)
    love.graphics.circle("fill", -3, -2, 2, 6)
    love.graphics.circle("fill", 3, -2, 2, 6)
    color(C.bone)
    love.graphics.setLineWidth(4)
    for k = 0, 2 do
      local a = hash(s.seed + k) * math.pi
      local ox, oy = (hash(s.seed * 2 + k) - 0.5) * s.w, (hash(s.seed * 3 + k) - 0.5) * s.h
      love.graphics.line(ox - math.cos(a) * 12, oy - math.sin(a) * 12, ox + math.cos(a) * 12, oy + math.sin(a) * 12)
    end
    love.graphics.setLineWidth(1)
  end)
end

-- Heck's props -----------------------------------------------------------------

--- A bridge of bones over the lava: ribs laid across, a spine down each side.
function DRAW.bonebridge(s)
  color(C.char, 0.6)
  love.graphics.rectangle("fill", s.x + 4, s.y + 6, s.w, s.h)
  if s.ns then
    for y = s.y + 4, s.y + s.h - 8, 14 do
      color(C.bone)
      love.graphics.rectangle("fill", s.x + 4, y, s.w - 8, 8, 4)
      color(C.bone, 0.7)
      love.graphics.circle("fill", s.x + 6, y + 4, 5, 6)
      love.graphics.circle("fill", s.x + s.w - 6, y + 4, 5, 6)
    end
    color(C.bone)
    love.graphics.rectangle("fill", s.x, s.y, 6, s.h)
    love.graphics.rectangle("fill", s.x + s.w - 6, s.y, 6, s.h)
  else
    for x = s.x + 4, s.x + s.w - 8, 14 do
      color(C.bone)
      love.graphics.rectangle("fill", x, s.y + 4, 8, s.h - 8, 4)
      love.graphics.circle("fill", x + 4, s.y + 6, 5, 6)
      love.graphics.circle("fill", x + 4, s.y + s.h - 6, 5, 6)
    end
    color(C.bone)
    love.graphics.rectangle("fill", s.x, s.y, s.w, 6)
    love.graphics.rectangle("fill", s.x, s.y + s.h - 6, s.w, 6)
  end
  if hash(s.seed) > 0.4 then -- a skull at the end of it
    color(C.bone)
    love.graphics.circle("fill", s.x + 10, s.y + 10, 9, 10)
    color(C.black)
    love.graphics.circle("fill", s.x + 7, s.y + 8, 2.5, 6)
    love.graphics.circle("fill", s.x + 13, s.y + 8, 2.5, 6)
  end
end

--- An altar: a slab of black stone, candles burning on it, a smear of red.
function DRAW.altar(s, t)
  shadow(s)
  color(C.rockWallDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 4)
  color(C.char)
  love.graphics.rectangle("fill", s.x + 6, s.y + 6, s.w - 12, s.h - 12, 3)
  love.graphics.setColor(0.45, 0.04, 0.03, 0.9)
  love.graphics.ellipse("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.25, s.h * 0.2, 12)
  for k = 0, 3 do
    local cx = s.x + 12 + k * (s.w - 24) / 3
    local cy = s.y + (k % 2 == 0 and 10 or s.h - 10)
    color(C.bone)
    love.graphics.circle("fill", cx, cy, 3.5, 8)
    local f = 0.7 + 0.3 * math.sin(t * 12 + k * 2 + s.seed)
    love.graphics.setColor(1, 0.7, 0.2, 0.9)
    love.graphics.circle("fill", cx, cy - 4, 2.5 * f, 6)
  end
end

--- A fire pit: a ring of stones round flames that never go out (it burns).
function DRAW.firepit(s, t)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.rockWallDark)
  for k = 0, 9 do
    local a = k / 10 * 2 * math.pi
    love.graphics.circle("fill", cx + math.cos(a) * (r - 6), cy + math.sin(a) * (r - 6), 9, 8)
  end
  color(C.char)
  love.graphics.circle("fill", cx, cy, r - 12, 20)
  DRAW.fire({ x = s.x + 10, y = s.y + 10, w = s.w - 20, h = s.h - 20, seed = s.seed }, t)
end

--- A pizza box the size of a house, half sunk in the lava, lid open: the
--- pizza in it, a slice gone. Big enough to see from across the map.
function DRAW.pizzabox(s, t)
  love.graphics.push()
  love.graphics.translate(s.x + s.w / 2, s.y + s.h / 2)
  love.graphics.rotate(s.angle or 0)
  local w, h = s.w, s.h
  local sink = 0.5 + 0.5 * math.sin(t * 0.3) -- bobbing in it
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.rectangle("fill", -w / 2 + 12, -h / 2 + 14, w, h)
  love.graphics.setColor(0.70, 0.52, 0.32) -- the box
  love.graphics.rectangle("fill", -w / 2, -h / 2, w, h)
  love.graphics.setColor(0.55, 0.40, 0.24)
  love.graphics.rectangle("line", -w / 2 + 6, -h / 2 + 6, w - 12, h - 12)
  love.graphics.setColor(0.62, 0.45, 0.28) -- the lid, open, flat behind it
  love.graphics.rectangle("fill", -w / 2, -h / 2 - h * 0.55, w, h * 0.55)
  love.graphics.setColor(0.85, 0.20, 0.15)
  love.graphics.setFont(signFont())
  love.graphics.printf("PIZZA", -w / 2, -h / 2 - h * 0.35, w, "center")
  local r = w * 0.42 -- the pizza
  love.graphics.setColor(0.85, 0.62, 0.30)
  love.graphics.arc("fill", 0, 0, r, 0.6, 2 * math.pi, 40)
  love.graphics.setColor(0.86, 0.30, 0.15)
  love.graphics.arc("fill", 0, 0, r - 12, 0.6, 2 * math.pi, 40)
  love.graphics.setColor(0.98, 0.88, 0.55)
  for k = 0, 7 do -- cheese
    local a = 0.9 + k * 0.7
    love.graphics.circle("fill", math.cos(a) * r * 0.55, math.sin(a) * r * 0.55, r * 0.12, 12)
  end
  love.graphics.setColor(0.55, 0.12, 0.10) -- pepperoni
  for k = 0, 6 do
    local a = 1.2 + k * 0.78
    love.graphics.circle("fill", math.cos(a) * r * 0.3, math.sin(a) * r * 0.3, r * 0.09, 12)
  end
  love.graphics.setColor(0.70, 0.52, 0.32) -- the slice gone: the box shows
  love.graphics.polygon("fill", 0, 0, r, 0, math.cos(0.6) * r, math.sin(0.6) * r)
  -- The lava lapping over its near corner.
  love.graphics.setColor(1, 0.35, 0.05, 0.85)
  love.graphics.polygon("fill", w / 2 - w * (0.25 + 0.05 * sink), h / 2, w / 2, h / 2 - h * (0.3 + 0.05 * sink),
    w / 2, h / 2)
  love.graphics.pop()
end

--- The Snooze Gate: a huge stone door, bones in its frame, a clock face
--- over it, its hands going round too fast.
function DRAW.snoozegate(s, t)
  shadow(s)
  color(C.rockWallDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.rockWall)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - 32, s.h - 16)
  color(C.char)
  love.graphics.rectangle("fill", s.x + s.w * 0.3, s.y + s.h * 0.35, s.w * 0.4, s.h * 0.65) -- the doors
  love.graphics.setColor(0.6, 0.15, 0.05)
  love.graphics.rectangle("fill", s.x + s.w / 2 - 2, s.y + s.h * 0.35, 4, s.h * 0.65)
  color(C.bone)
  for k = 0, 9 do
    love.graphics.circle("fill", s.x + 20 + k * (s.w - 40) / 9, s.y + 10, 7, 8)
  end
  local cx, cy, r = s.x + s.w / 2, s.y + s.h * 0.2, s.h * 0.28
  color(C.bone)
  love.graphics.circle("fill", cx, cy, r + 6, 32)
  love.graphics.setColor(0.95, 0.92, 0.80)
  love.graphics.circle("fill", cx, cy, r, 32)
  color(C.black)
  for k = 0, 11 do
    local a = k / 12 * 2 * math.pi
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.82, cy + math.sin(a) * r * 0.82, 2.5, 6)
  end
  love.graphics.setLineWidth(4)
  local m = t * 1.4
  love.graphics.line(cx, cy, cx + math.cos(m) * r * 0.75, cy + math.sin(m) * r * 0.75)
  love.graphics.setLineWidth(6)
  love.graphics.line(cx, cy, cx + math.cos(m / 12) * r * 0.5, cy + math.sin(m / 12) * r * 0.5)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.8, 0.1, 0.1)
  love.graphics.circle("fill", cx, cy, 4, 8)
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

--- Draw `map`'s floors and walls (one of eternal_mood.lua's: a base's, or
--- a city's streets and roofs) into the canvas, `T` the tile size.
--- Everything on them is `drawProps`'.
function RenderEternalMood.draw(map, T)
  if map.grounds then
    drawCity(map, T)
  else
    drawGround(map, T)
  end
  love.graphics.setColor(1, 1, 1)
end

local function inView(s, left, top, right, bottom)
  return s.x + s.w >= left and s.x <= right and s.y + s.h >= top and s.y <= bottom
end

--- Everything on `map`'s floor within (left, top, right, bottom), world px,
--- at full size, at time `t`: flat things first, then what stands up, the
--- posters, the alarms, and the reactor's halo (or the Crater's heat) over
--- it all.
function RenderEternalMood.drawProps(map, left, top, right, bottom, t)
  local before = love.graphics.getFont()
  prepareLava(map)
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
    elseif (s.kind == "crater" or s.kind == "crucible")
      and inView(s, left - 400, top - 400, right + 400, bottom + 400) then
      drawCraterGlow(s, t)
    end
  end
  love.graphics.setFont(before)
  love.graphics.setColor(1, 1, 1)
end

return RenderEternalMood
