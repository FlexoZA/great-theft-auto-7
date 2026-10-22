-- The Borderline maps' drawing kit (render_borderline.lua and what it
-- draws past their edges): the palette, the comic outline, and the
-- helpers everything is drawn with.

local Kit = {}

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
  trainRoof = { 0.60, 0.62, 0.66 }, -- the carriages' roofs, silver under the dirt
  concrete = { 0.56, 0.56, 0.58 },
  concreteDark = { 0.42, 0.42, 0.45 },
  ember = { 1.00, 0.52, 0.16 },
  emberHot = { 1.00, 0.86, 0.40 },
  sheetLight = { 0.46, 0.48, 0.53 }, -- a pitched roof's sunny side
  sheetDark = { 0.31, 0.33, 0.37 }, -- and its shady side
  skylightLit = { 0.95, 0.78, 0.42 }, -- a factory working late under it
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

--- Smooth noise over the plane, 0..1: the hash at whole (x, y), blended
--- between them. Patches of snow come and go with it.
local function noise(x, y)
  local x0, y0 = math.floor(x), math.floor(y)
  local fx, fy = x - x0, y - y0
  fx, fy = fx * fx * (3 - 2 * fx), fy * fy * (3 - 2 * fy)
  local function at(i, j)
    return hash(i * 17.31 + j * 91.7 + 3.1)
  end
  local top = at(x0, y0) + (at(x0 + 1, y0) - at(x0, y0)) * fx
  local bottom = at(x0, y0 + 1) + (at(x0 + 1, y0 + 1) - at(x0, y0 + 1)) * fx
  return top + (bottom - top) * fy
end

--- Draw `fn(L, W)` for `s` turned so its long side runs along x, centred
--- on the origin: x across -L/2..L/2, y across -W/2..W/2. Anything long
--- and thin (a carriage, a shed) is drawn once for either way it lies.
local function lengthwise(s, fn)
  local along = s.w >= s.h
  love.graphics.push()
  love.graphics.translate(s.x + s.w / 2, s.y + s.h / 2)
  if not along then
    love.graphics.rotate(math.pi / 2)
  end
  fn(along and s.w or s.h, along and s.h or s.w)
  love.graphics.pop()
end

--- A heap of snow: a few lumps along (x, y) .. (x + dx, y + dy), `r` px
--- high, its own lumps by `seed`.
local function drift(x, y, dx, dy, r, seed, a)
  local n = math.max(2, math.floor(math.sqrt(dx * dx + dy * dy) / (r * 0.9)))
  for i = 0, n do
    local k = i / n
    local lump = r * (0.55 + 0.6 * hash(seed + i * 1.7))
    color(C.snowShade, a)
    love.graphics.circle("fill", x + dx * k, y + dy * k + lump * 0.2, lump, 14)
    color(C.snow, a)
    love.graphics.circle("fill", x + dx * k - lump * 0.15, y + dy * k - lump * 0.1, lump * 0.8, 14)
  end
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

Kit.INK, Kit.LINE, Kit.C = INK, LINE, C
Kit.color, Kit.hash, Kit.noise, Kit.lengthwise, Kit.drift = color, hash, noise, lengthwise, drift
Kit.box, Kit.blob, Kit.hazard, Kit.signFont = box, blob, hazard, signFont

return Kit
