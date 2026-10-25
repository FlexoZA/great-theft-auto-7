-- Drawing the Borderline quest line's maps (borderline.lua) into the map
-- canvas, in the style of a cel-shaded comic: flat bright colours and a hard
-- black outline round everything, the floors' edges included. Each map's
-- outside (`map.outside`) round its floors, the floors' finishes
-- (`map.grounds`), then everything flat on them and everything standing,
-- each standing thing with a flat shadow. Drawn once, by day. The palette
-- and helpers are render_borderline_kit.lua's, the floors, the outside and
-- the snow render_borderline_ground.lua's (surroundings draws them past the
-- map's edges too).

local RenderBorderline = {}

local Kit = require("src.features.city-map.render_borderline_kit")
local Ground = require("src.features.city-map.render_borderline_ground")
local Port = require("src.features.city-map.render_borderline_port")
local Mine = require("src.features.city-map.render_borderline_mine")

local INK, LINE, C = Kit.INK, Kit.LINE, Kit.C
local color, hash, lengthwise, drift = Kit.color, Kit.hash, Kit.lengthwise, Kit.drift
local box, blob, hazard, signFont = Kit.box, Kit.blob, Kit.hazard, Kit.signFont

-- What lies and stands about ------------------------------------------------------------

local DRAW = {}
for _, kit in ipairs({ Port.DRAW, Mine.DRAW }) do
  for kind, fn in pairs(kit) do
    DRAW[kind] = fn
  end
end

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

--- A bogie torn out from under a carriage or the engine, lying beside it
--- on its side: the frame, the wheels sticking up. Centred on (x, y).
local function bogie(x, y)
  box(x - 40, y - 20, 80, 40, C.gunmetal)
  color(INK)
  for _, wx in ipairs({ -24, 24 }) do
    love.graphics.rectangle("fill", x + wx - 11, y - 26, 22, 12)
    love.graphics.rectangle("fill", x + wx - 11, y + 14, 22, 12)
    love.graphics.rectangle("fill", x + wx - 3, y - 20, 6, 40) -- the axle
  end
  color(C.gunmetalLight)
  love.graphics.rectangle("fill", x - 30, y - 4, 60, 8)
end

--- A hole burnt through a roof at (x, y), `rx` x `ry`: the scorch round it,
--- the ribs showing, embers still glowing in it.
local function burnt(x, y, rx, ry, seed)
  color(INK, 0.3)
  love.graphics.ellipse("fill", x + rx * 0.3, y, rx * 2.2, ry * 1.5, 20)
  color(INK, 0.5)
  love.graphics.ellipse("fill", x, y, rx * 1.4, ry * 1.15, 18)
  local pts = {}
  for i = 0, 11 do
    local a = i / 12 * math.pi * 2
    local k = 0.7 + 0.45 * hash(seed + i * 2.3)
    pts[#pts + 1] = x + math.cos(a) * rx * k
    pts[#pts + 1] = y + math.sin(a) * ry * k
  end
  color(INK)
  love.graphics.polygon("fill", pts)
  color(C.gunmetal) -- the ribs over the hole
  for rib = x - rx + 10, x + rx - 6, 16 do
    love.graphics.rectangle("fill", rib, y - ry * 0.8, 4, ry * 1.6)
  end
  for i = 1, 9 do
    local ex, ey = x + (hash(seed + i * 5.1) - 0.5) * rx * 1.2, y + (hash(seed + i * 7.9) - 0.5) * ry * 1.1
    color(C.ember)
    love.graphics.circle("fill", ex, ey, 4 + 4 * hash(seed + i), 8)
    color(C.emberHot)
    love.graphics.circle("fill", ex, ey, 2 + 2 * hash(seed + i), 6)
  end
end

--- A carriage of Max's train off the rails, seen from above: a silver
--- roof between Hyperbole yellow sides, panel seams and two air-con units
--- on it, a gangway at each end. Each lies its own way (by `seed`): tipped
--- so the windows along one side show (some smashed), a bogie torn out
--- beside it, an end crumpled, dents, snow on the roof. A `burning` one
--- has a hole burnt through its roof, embers glowing in it (its smoke and
--- glow are borderline/works.lua's and the night feature's).
function DRAW.carriage(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    local side = h < 0.5 and -1 or 1 -- the side it has tipped towards
    local tipped = hash(h * 3) < 0.65
    if hash(h * 7) < 0.6 then
      bogie((hash(h * 11) < 0.5 and -1 or 1) * (L / 2 - 64), side * (W / 2 + 6))
    end
    box(-L / 2, -W / 2, L, W, C.yellow)
    -- The roof between the sides, wider on the side still up.
    local shown = tipped and 30 or 10
    local y0 = side < 0 and -W / 2 + shown or -W / 2 + 10
    local y1 = side < 0 and W / 2 - 10 or W / 2 - shown
    if tipped then -- the windows down the side it lies towards
      local wy = side < 0 and -W / 2 + 5 or W / 2 - shown + 5
      for i = 0, math.floor((L - 60) / 46) - 1 do
        local wx = -L / 2 + 26 + i * 46
        color(INK)
        love.graphics.rectangle("fill", wx - 3, wy - 2, 36, shown - 6)
        if hash(h * 5 + i) < 0.35 then -- smashed
          color(C.paintWhite, 0.8)
          love.graphics.polygon("fill", wx, wy, wx + 12, wy, wx, wy + shown - 14)
          love.graphics.polygon("fill", wx + 30, wy + shown - 10, wx + 22, wy + shown - 10, wx + 30, wy + 4)
        else
          color(C.window)
          love.graphics.rectangle("fill", wx, wy + 1, 30, shown - 10)
          color(C.white, 0.35)
          love.graphics.rectangle("fill", wx + 4, wy + 1, 6, shown - 10)
        end
      end
    end
    color(INK)
    love.graphics.rectangle("fill", -L / 2 + 10, y0 - 3, L - 20, y1 - y0 + 6)
    color(C.trainRoof)
    love.graphics.rectangle("fill", -L / 2 + 12, y0, L - 24, y1 - y0)
    color(INK, 0.22) -- the panels' seams
    for x = -L / 2 + 56, L / 2 - 40, 52 do
      love.graphics.rectangle("fill", x, y0, 3, y1 - y0)
    end
    local mid = (y0 + y1) / 2
    for _, ax in ipairs({ -L * 0.27, L * 0.27 }) do -- the air-con units
      box(ax - 30, mid - 17, 60, 34, C.gunmetalLight)
      color(INK)
      love.graphics.circle("fill", ax + 12, mid, 11, 12)
      color(C.gunmetal)
      love.graphics.rectangle("fill", ax - 24, mid - 10, 18, 4)
      love.graphics.rectangle("fill", ax - 24, mid + 6, 18, 4)
    end
    color(INK) -- the gangways
    love.graphics.rectangle("fill", -L / 2 - 2, -W / 2 + 18, 12, W - 36)
    love.graphics.rectangle("fill", L / 2 - 10, -W / 2 + 18, 12, W - 36)
    -- Snow along the edge still up, a patch or two on the roof.
    drift(-L / 2 + 22, side < 0 and y1 - 2 or y0 + 2, L - 44, 0, 9, h * 31, 0.95)
    for i = 1, 2 do
      color(C.snow, 0.85)
      love.graphics.ellipse("fill", (hash(h * 9 + i) - 0.5) * L * 0.7, mid + (hash(h * 13 + i) - 0.5) * 20,
        18 + 16 * hash(h + i), 7, 12)
    end
    color(INK, 0.25) -- dents
    for i = 1, 3 do
      love.graphics.ellipse("fill", (hash(h * 17 + i) - 0.5) * L * 0.8, y0 + (y1 - y0) * hash(h * 19 + i),
        10 + 10 * hash(h * 23 + i), 5, 10)
    end
    if hash(h * 29) < 0.45 then -- an end crumpled in the crash
      local e = hash(h * 31) < 0.5 and -1 or 1
      local x = e * L / 2
      for i = 0, 3 do
        local ya, yb = -W / 2 + i * W / 4, -W / 2 + (i + 1) * W / 4
        color(i % 2 == 0 and C.yellowDark or C.gunmetal)
        love.graphics.polygon("fill", x, ya, x - e * (18 + 10 * hash(h + i)), (ya + yb) / 2, x, yb)
      end
    end
    if s.burning then
      burnt((hash(h * 37) - 0.5) * L * 0.3, mid, 40, (y1 - y0) * 0.38, h * 41)
    end
  end)
end

--- Max's locomotive, nose to the north: a chamfered nose with hazard
--- chevrons and its headlights, the cab and its windscreen, then the long
--- hood with the exhaust stack (the smoke is borderline/works.lua's), the
--- radiator grilles and two cooling fans; a bogie torn out beside it, the
--- nose crumpled, the hood scorched and snowed on.
function DRAW.loco(s)
  lengthwise(s, function(L, W)
    local nose, ch = -L / 2, 34
    bogie(L / 2 - 80, -W / 2 - 8)
    color(INK)
    love.graphics.polygon("fill", nose + ch - 2, -W / 2 - LINE, L / 2 + LINE, -W / 2 - LINE, L / 2 + LINE,
      W / 2 + LINE, nose + ch - 2, W / 2 + LINE, nose - LINE, W / 2 - ch + 2, nose - LINE, -W / 2 + ch - 2)
    color(C.yellow)
    love.graphics.polygon("fill", nose + ch, -W / 2, L / 2, -W / 2, L / 2, W / 2, nose + ch, W / 2, nose, W / 2 - ch,
      nose, -W / 2 + ch)
    hazard(nose + 4, -W / 2 + ch - 4, 22, W - 2 * ch + 8)
    for _, y in ipairs({ -W / 2 + 18, W / 2 - 18 }) do -- the headlights, still on
      color(INK)
      love.graphics.circle("fill", nose + 26, y, 10, 12)
      color(C.emberHot)
      love.graphics.circle("fill", nose + 26, y, 7, 12)
    end
    color(C.yellowDark, 0.9) -- the nose stove in
    love.graphics.polygon("fill", nose + 30, -W / 2 + 4, nose + 50, -W / 2 + 22, nose + 34, -W / 2 + 30)
    love.graphics.polygon("fill", nose + 28, W / 2 - 40, nose + 46, W / 2 - 12, nose + 30, W / 2 - 6)
    -- The cab: its roof, the windscreen across the front, the side windows.
    box(nose + 46, -W / 2 + 12, 80, W - 24, C.gunmetalLight)
    color(C.window)
    love.graphics.rectangle("fill", nose + 46, -W / 2 + 16, 14, W - 32)
    love.graphics.rectangle("fill", nose + 74, -W / 2 + 12, 40, 8)
    love.graphics.rectangle("fill", nose + 74, W / 2 - 20, 40, 8)
    color(C.white, 0.4)
    love.graphics.rectangle("fill", nose + 48, -W / 2 + 22, 4, W - 60)
    color(C.yellow) -- Hyperbole's H on the cab roof
    love.graphics.circle("fill", nose + 96, 0, 18, 18)
    color(INK)
    love.graphics.rectangle("fill", nose + 86, -9, 5, 18)
    love.graphics.rectangle("fill", nose + 101, -9, 5, 18)
    love.graphics.rectangle("fill", nose + 86, -2, 20, 4)
    -- The long hood.
    local h0, h1 = nose + 140, L / 2 - 16
    box(h0, -W / 2 + 20, h1 - h0, W - 40, C.gunmetal)
    color(C.paintWhite, 0.75) -- handrails down both sides
    love.graphics.rectangle("fill", h0, -W / 2 + 9, h1 - h0, 3)
    love.graphics.rectangle("fill", h0, W / 2 - 12, h1 - h0, 3)
    local ex = nose + 170
    color(INK, 0.45) -- soot round the stack
    love.graphics.ellipse("fill", ex + 24, 0, 54, W / 2 - 22, 16)
    blob(ex - 17, -17, 34, 34, C.gunmetalLight)
    color(INK)
    love.graphics.circle("fill", ex, 0, 10, 12)
    for x = ex + 40, ex + 104, 9 do -- the radiator grilles
      love.graphics.rectangle("fill", x, -W / 2 + 28, 4, W - 56)
    end
    for _, fx in ipairs({ h1 - 108, h1 - 46 }) do -- the cooling fans
      blob(fx - 25, -25, 50, 50, C.gunmetalLight)
      color(INK)
      love.graphics.circle("fill", fx, 0, 19, 16)
      color(C.gunmetalLight)
      for k = 0, 3 do
        local a = k * math.pi / 2 + fx
        love.graphics.arc("fill", fx, 0, 17, a, a + 0.55, 6)
      end
      color(INK)
      love.graphics.circle("fill", fx, 0, 4, 8)
    end
    drift(h0 + 12, W / 2 - 22, h1 - h0 - 24, 0, 8, 7, 0.95)
    color(INK) -- the coupler at the back
    love.graphics.rectangle("fill", L / 2 - 14, -10, 14, 20)
  end)
end

--- The ground torn up where a carriage slid off the rails: churned dirt,
--- the grooves its wheels cut, snow ploughed up along both edges, glass
--- and bits strewn along it.
function DRAW.scar(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    color(C.gravel, 0.9)
    for x = -L / 2, L / 2, 18 do
      local k = 0.7 + 0.4 * hash(h + x * 0.13)
      love.graphics.ellipse("fill", x, (hash(h * 3 + x) - 0.5) * 6, 16, W / 2 * k, 10)
    end
    color(C.woodDark, 0.55)
    for _, y in ipairs({ -W * 0.2, W * 0.2 }) do
      love.graphics.rectangle("fill", -L / 2 + 6, y - 3, L - 12, 6)
    end
    drift(-L / 2, -W / 2 - 2, L, 0, 9, h * 7, 0.9)
    drift(-L / 2, W / 2 + 2, L, 0, 9, h * 11, 0.9)
    for i = 1, 8 do
      local x, y = (hash(h * 13 + i) - 0.5) * L, (hash(h * 17 + i) - 0.5) * W * 0.8
      color(i % 3 == 0 and C.window or (i % 3 == 1 and C.yellowDark or C.gunmetal))
      love.graphics.rectangle("fill", x, y, 6 + 6 * hash(h + i), 4 + 4 * hash(h * 2 + i))
    end
  end)
end

--- A crate: planks, battens round the edge and across, corner brackets.
function DRAW.crate(s)
  box(s.x, s.y, s.w, s.h, C.wood)
  color(C.woodDark)
  for y = s.y + s.h / 3, s.y + s.h - 4, s.h / 3 do -- the gaps between planks
    love.graphics.rectangle("fill", s.x, y - 1, s.w, 3)
  end
  love.graphics.rectangle("fill", s.x, s.y, s.w, 5) -- the battens
  love.graphics.rectangle("fill", s.x, s.y + s.h - 5, s.w, 5)
  love.graphics.rectangle("fill", s.x, s.y, 5, s.h)
  love.graphics.rectangle("fill", s.x + s.w - 5, s.y, 5, s.h)
  love.graphics.polygon("fill", s.x + 5, s.y + 5, s.x + 11, s.y + 5, s.x + s.w - 5, s.y + s.h - 11, s.x + s.w - 5,
    s.y + s.h - 5, s.x + s.w - 11, s.y + s.h - 5, s.x + 5, s.y + 11)
  color(C.gunmetalLight)
  for _, k in ipairs({ { 0, 0 }, { 1, 0 }, { 0, 1 }, { 1, 1 } }) do
    love.graphics.rectangle("fill", s.x + k[1] * (s.w - 8), s.y + k[2] * (s.h - 8), 8, 8)
  end
end

function DRAW.chest(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.yellow)
  love.graphics.rectangle("fill", s.x, s.y + s.h * 0.35, s.w, s.h * 0.15)
end

function DRAW.crane(s)
  box(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.setLineWidth(8)
  love.graphics.line(s.x, s.y, s.x + s.w, s.y + s.h)
  love.graphics.line(s.x + s.w, s.y, s.x, s.y + s.h)
  love.graphics.setLineWidth(1)
end

--- A steel plate in the floor, hazard striped at both ends: a door, a bay, a hatch.
function DRAW.door(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  hazard(s.x, s.y, s.w, 16)
  hazard(s.x, s.y + s.h - 16, s.w, 16)
end
DRAW.bay = DRAW.door
DRAW.hatch = DRAW.door

--- A factory block in Max's town: a corrugated roof, rows of sawtooth
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
  blob(s.x + s.w * 0.3, s.y + s.h * 0.3, s.w * 0.4, s.h * 0.4, C.gold) -- Max, from above: all hair
end

function DRAW.lawn(s)
  box(s.x, s.y, s.w, s.h, C.green)
end

function DRAW.billboard(s)
  box(s.x, s.y, s.w, s.h, INK)
  color(C.yellow)
  love.graphics.setFont(signFont())
  love.graphics.printf("MAX LOVES YOU", s.x, s.y + (s.h - 22) / 2, s.w, "center")
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

--- An assembly arm's base (the arm itself swings and welds: borderline/works.lua).
function DRAW.arm(s)
  blob(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.circle("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.22, 10)
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

--- A tunnel's mouth, opening towards the middle of the map: a concrete
--- portal in courses of blocks, the bore going dark further in with its
--- lamps fading, a hazard band across the lip, snow heaped at its feet;
--- the rails running in when it has them (`railsX`, their left edge).
function DRAW.tunnel(s)
  love.graphics.push()
  if s.y > 0 then -- at the bottom of the map: the mouth faces north
    love.graphics.translate(0, 2 * s.y + s.h)
    love.graphics.scale(1, -1)
  end
  box(s.x - 34, s.y, s.w + 68, s.h, C.concrete)
  color(INK, 0.3)
  for y = s.y + 18, s.y + s.h - 20, 30 do -- the courses of the portal's blocks
    love.graphics.rectangle("fill", s.x - 34, y, 34, 3)
    love.graphics.rectangle("fill", s.x + s.w, y, 34, 3)
  end
  color(C.concreteDark)
  love.graphics.rectangle("fill", s.x - 8, s.y, 8, s.h - 14)
  love.graphics.rectangle("fill", s.x + s.w, s.y, 8, s.h - 14)
  local bands, deep = 8, s.h - 14
  for i = 0, bands - 1 do -- black at the back, a little light at the mouth
    local k = i / (bands - 1)
    love.graphics.setColor(INK[1] + 0.13 * k, INK[2] + 0.13 * k, INK[3] + 0.16 * k)
    love.graphics.rectangle("fill", s.x, s.y + deep * i / bands, s.w, deep / bands + 1)
  end
  if s.railsX then
    for y = s.y + deep - 14, s.y, -28 do
      local k = (y - s.y) / deep
      color(C.woodDark, 0.85 * k)
      love.graphics.rectangle("fill", s.railsX - 14, y, 48, 9)
    end
    for i = 0, 5 do
      local y0 = s.y + deep * i / 6
      color(C.gunmetalLight, 0.9 * (i + 1) / 6)
      love.graphics.rectangle("fill", s.railsX - 6, y0, 5, deep / 6 + 1)
      love.graphics.rectangle("fill", s.railsX + 21, y0, 5, deep / 6 + 1)
    end
  end
  for i = 0, 3 do -- the lamps along the bore
    color(C.ember, 0.9 - i * 0.22)
    local y = s.y + deep - 26 - i * 30
    love.graphics.circle("fill", s.x + 10, y, 5, 8)
    love.graphics.circle("fill", s.x + s.w - 10, y, 5, 8)
  end
  hazard(s.x - 34, s.y + s.h - 14, s.w + 68, 14)
  love.graphics.pop()
  local foot = s.y > 0 and s.y - 10 or s.y + s.h + 10
  drift(s.x - 56, foot, 40, 0, 13, s.x * 0.01, 0.95)
  drift(s.x + s.w + 16, foot, 40, 0, 13, s.x * 0.01 + 1, 0.95)
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
--- Words painted on the floor. Where it snows (`snowy`), snow has drifted
--- over bits of them.
function DRAW.paint(s)
  local size = s.small and 22 or 30
  paintFonts[size] = paintFonts[size] or love.graphics.newFont(size)
  love.graphics.setFont(paintFonts[size])
  color(C.yellow, 0.85)
  love.graphics.printf(s.text or "", s.x, s.y + (s.h - size) / 2, s.w, "center")
  if s.snowy then
    local h = hash(s.x * 0.37 + s.y * 0.11)
    for i = 1, 4 do
      color(C.snow, 0.85)
      love.graphics.ellipse("fill", s.x + s.w * (0.1 + 0.8 * hash(h + i)), s.y + s.h * (0.3 + 0.4 * hash(h * 3 + i)),
        10 + 18 * hash(h * 5 + i), 5 + 4 * hash(h * 7 + i), 12)
    end
  end
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

--- A traffic cone: its square rubber base, the cone with a white band
--- round it, from above; one in four knocked over, lying on its side.
function DRAW.cone(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local r = math.max(7, s.w * 0.5)
  local h = hash(s.seed or cx)
  if h < 0.25 then
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(h * 25)
    color(INK)
    love.graphics.polygon("fill", -r - 3, -r * 0.7 - 3, r + 4, -2, r + 4, 2, -r - 3, r * 0.7 + 3)
    color(C.cone)
    love.graphics.polygon("fill", -r, -r * 0.6, r, -1, r, 1, -r, r * 0.6)
    color(C.paintWhite)
    love.graphics.polygon("fill", -r * 0.15, -r * 0.33, r * 0.25, -r * 0.2, r * 0.25, r * 0.2, -r * 0.15, r * 0.33)
    color(INK)
    love.graphics.rectangle("fill", -r - 4, -r * 0.8, 5, r * 1.6) -- the base, on its edge
    love.graphics.pop()
    return
  end
  color(INK)
  love.graphics.rectangle("fill", cx - r - 2, cy - r - 2, 2 * r + 4, 2 * r + 4, 3)
  color(C.coneDark)
  love.graphics.rectangle("fill", cx - r, cy - r, 2 * r, 2 * r, 2)
  color(C.cone)
  love.graphics.circle("fill", cx, cy, r * 0.8, 12)
  color(C.paintWhite)
  love.graphics.circle("fill", cx, cy, r * 0.55, 12)
  color(C.cone)
  love.graphics.circle("fill", cx, cy, r * 0.35, 10)
  color(INK)
  love.graphics.circle("fill", cx, cy, r * 0.12, 6)
end

-- What a drum may be painted, and what it holds: red fuel, blue, yellow
-- Bragium coolant, plain steel.
local DRUMS = { C.drum, { 0.20, 0.40, 0.66 }, C.yellow, C.gunmetalLight }

--- An oil drum: standing, its lid ringed and two bungs in it, a hazard
--- diamond on the yellow ones; or knocked over, rolled on its side with its
--- hoops showing. A few stand on a pallet.
function DRAW.drum(s)
  local h = hash(s.seed or s.x)
  local fill = DRUMS[1 + math.floor(hash(h * 7.1) * #DRUMS)]
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  if h < 0.2 then
    love.graphics.push()
    love.graphics.translate(cx, cy)
    love.graphics.rotate(h * 30)
    box(-r * 1.3, -r * 0.8, r * 2.6, r * 1.6, fill)
    color(INK, 0.35)
    for _, x in ipairs({ -r * 0.5, r * 0.4 }) do
      love.graphics.rectangle("fill", x, -r * 0.8, 4, r * 1.6)
    end
    color(C.white, 0.25)
    love.graphics.rectangle("fill", -r * 1.3, -r * 0.5, r * 2.6, 4)
    blob(r * 1.2, -r * 0.8, r * 0.35, r * 1.6, fill)
    love.graphics.pop()
    return
  end
  if h > 0.8 then -- on a pallet
    color(INK)
    love.graphics.rectangle("fill", cx - r * 1.35, cy - r * 1.35, r * 2.7, r * 2.7)
    color(C.wood)
    for k = 0, 3 do
      love.graphics.rectangle("fill", cx - r * 1.3, cy - r * 1.3 + k * r * 0.68, r * 2.6, r * 0.5)
    end
  end
  blob(s.x, s.y, s.w, s.h, fill)
  color(INK, 0.45)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", cx, cy, r * 0.82, 16)
  love.graphics.setLineWidth(1)
  color(C.white, 0.3)
  love.graphics.arc("fill", cx, cy, r * 0.78, math.pi * 1.05, math.pi * 1.45, 6)
  color(INK, 0.7)
  love.graphics.circle("fill", cx - r * 0.4, cy - r * 0.1, r * 0.13, 6)
  love.graphics.circle("fill", cx + r * 0.35, cy + r * 0.25, r * 0.09, 6)
  if fill == C.yellow then
    color(INK)
    love.graphics.polygon("fill", cx, cy - r * 0.42, cx + r * 0.32, cy, cx, cy + r * 0.42, cx - r * 0.32, cy)
    color(C.yellow)
    love.graphics.polygon("fill", cx, cy - r * 0.26, cx + r * 0.18, cy, cx, cy + r * 0.26, cx - r * 0.18, cy)
  end
end

local bayFont = nil
--- A shed: a pitched roof of corrugated sheet, its ridge down the long
--- way, the sunny side lighter than the shady. Skylights down the sunny
--- side, turbine vents on the ridge, rust run down from the fixings, snow
--- along the shady eave and in patches, its bay number painted big and
--- Hyperbole yellow along its end; a loading door on the side facing
--- the yard.
function DRAW.shed(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    box(-L / 2, -W / 2, L, W, C.sheetLight)
    color(C.sheetDark)
    love.graphics.rectangle("fill", -L / 2, 0, L, W / 2)
    color(INK, 0.22) -- the corrugations, down the slope
    for x = -L / 2 + 6, L / 2 - 6, 12 do
      love.graphics.rectangle("fill", x, -W / 2, 3, W)
    end
    for x = -L / 2 + 36, L / 2 - 90, 104 do -- the skylights
      color(INK)
      love.graphics.rectangle("fill", x - 3, -W / 2 + 14, 52, W / 2 - 28)
      color(C.window)
      love.graphics.rectangle("fill", x, -W / 2 + 17, 46, W / 2 - 34)
      color(C.white, 0.3)
      love.graphics.rectangle("fill", x + 5, -W / 2 + 17, 8, W / 2 - 34)
    end
    for i = 1, 7 do -- rust run down from the fixings
      local up = hash(h * 7 + i) < 0.5
      color(C.rust, 0.4)
      love.graphics.rectangle("fill", -L / 2 + 10 + (L - 20) * hash(h * 5 + i), up and -W / 2 + 4 or 8, 4,
        W / 2 * (0.25 + 0.4 * hash(h * 9 + i)))
    end
    drift(-L / 2 + 12, W / 2 - 6, L - 24, 0, 13, h * 13, 0.95) -- along the shady eave
    for i = 1, 4 do
      color(C.snow, 0.8)
      love.graphics.ellipse("fill", -L / 2 + L * hash(h * 17 + i), (hash(h * 19 + i) - 0.5) * W * 0.8,
        18 + 22 * hash(h * 23 + i), 7 + 3 * hash(h * 29 + i), 12)
    end
    color(INK) -- the ridge cap
    love.graphics.rectangle("fill", -L / 2, -6, L, 12)
    color(C.gunmetalLight)
    love.graphics.rectangle("fill", -L / 2, -3, L, 6)
    local n = 1 + math.floor(h * 3)
    for i = 1, n do -- turbine vents on it
      local vx = -L / 2 + L * i / (n + 1)
      blob(vx - 16, -16, 32, 32, C.gunmetalLight)
      color(INK)
      love.graphics.rectangle("fill", vx - 11, -2, 22, 4)
      love.graphics.rectangle("fill", vx - 2, -11, 4, 22)
    end
    bayFont = bayFont or love.graphics.newFont(46)
    love.graphics.setFont(bayFont)
    color(C.paintWhite, 0.8)
    love.graphics.printf(("B%d"):format(s.bay or 1), L / 2 - 150, W / 4 - 26, 120, "center")
    color(C.yellow)
    love.graphics.rectangle("fill", L / 2 - 12, -W / 2, 12, W)
    love.graphics.circle("fill", -L / 2 + 44, W / 4, 20, 18) -- Hyperbole's H
    color(INK)
    love.graphics.rectangle("fill", -L / 2 + 33, W / 4 - 10, 5, 20)
    love.graphics.rectangle("fill", -L / 2 + 50, W / 4 - 10, 5, 20)
    love.graphics.rectangle("fill", -L / 2 + 33, W / 4 - 2, 22, 4)
  end)
  local west = s.x < 0 -- the yard is towards the middle of the map
  hazard(west and s.x + s.w - 14 or s.x, s.y + s.h * 0.3, 14, s.h * 0.4)
end

--- A yard gate standing open, the way through clear: posts striped at
--- either side, the track the gate runs on set in the ground across the
--- way, the gate itself run back into a pocket past the east post.
function DRAW.gate(s)
  local cy = s.y + s.h / 2
  color(INK, 0.6) -- the track
  love.graphics.rectangle("fill", s.x, cy - 4, s.w, 8)
  color(C.gunmetalLight)
  love.graphics.rectangle("fill", s.x, cy - 1, s.w, 2)
  local px = s.x + s.w + 14 -- the pocket the gate runs back into
  box(px, s.y + 10, 22, s.h - 20, C.gunmetal)
  color(C.gunmetalLight)
  for y = s.y + 16, s.y + s.h - 16, 10 do
    love.graphics.rectangle("fill", px + 3, y, 16, 3)
  end
  for _, x in ipairs({ s.x - 14, s.x + s.w - 14 }) do -- the posts
    box(x, s.y + 4, 28, s.h - 8, C.yellow)
    color(INK)
    for y = s.y + 14, s.y + s.h - 14, 22 do
      love.graphics.polygon("fill", x, y, x + 28, y - 10, x + 28, y, x, y + 10)
    end
  end
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
  if s.scrap then -- a heap of rejected hauler parts down there
    for i = 1, 14 do
      local px, py = s.x + s.w * (0.2 + hash(h + i) * 0.6), s.y + s.h * (0.2 + hash(h * 3 + i) * 0.6)
      box(px - 10, py - 7, 20 + hash(i) * 14, 14, i % 3 == 0 and C.gunmetalLight or C.yellowDark)
    end
  else
    color(C.window, 0.7) -- a puddle down there, catching the light
    love.graphics.ellipse("fill", s.x + s.w * (0.35 + h * 0.3), s.y + s.h * 0.6, s.w * 0.12, s.h * 0.06, 16)
    color(C.rock)
    for i = 1, 5 do
      love.graphics.circle("fill", s.x + s.w * (0.3 + hash(h + i) * 0.4), s.y + s.h * (0.3 + hash(h * 3 + i) * 0.4),
        6 + hash(i + h) * 8, 8)
    end
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

--- An engine intake: a round hole going deep into the bunker, rings
--- stepping down to where its fan turns (borderline/works.lua), a hazard
--- ring round its lip.
function DRAW.intake(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + LINE, 40)
  for i = 0, 15 do
    color(i % 2 == 0 and C.yellow or INK)
    love.graphics.arc("fill", cx, cy, r, i * math.pi / 8, (i + 1) * math.pi / 8, 4)
  end
  for i = 1, 3 do
    local k = i / 4
    love.graphics.setColor(C.gunmetal[1] * (1 - k), C.gunmetal[2] * (1 - k), C.gunmetal[3] * (1 - k))
    love.graphics.circle("fill", cx, cy, r * (0.92 - i * 0.06), 40)
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

--- Thousand Papercuts' road: yellow lines along both edges and dashes
--- down the middle, a crash barrier along the drop, following each row of
--- the road (`map.cutsRoad`) and stepping across where it bends.
local function drawRoadLines(map, T)
  local function at(c)
    return map.x0 + c * T
  end
  for r = map.r0, map.r1 do
    local road, prev = map.cutsRoad[r], map.cutsRoad[r - 1]
    local y = map.y0 + r * T
    local x0, x1 = at(road[1]), at(road[2] + 1)
    color(C.yellow, 0.85)
    love.graphics.rectangle("fill", x0 + 10, y, 5, T)
    love.graphics.rectangle("fill", x1 - 15, y, 5, T)
    if r % 2 == 0 then
      love.graphics.rectangle("fill", (x0 + x1) / 2 - 3, y + 10, 6, T - 20)
    end
    color(C.gunmetalLight) -- the barrier over the drop
    love.graphics.rectangle("fill", x0 - 8, y, 8, T)
    color(INK)
    love.graphics.rectangle("fill", x0 - 10, y + T / 2 - 4, 12, 8) -- a post
    if prev and prev[1] ~= road[1] then -- the bend: lines and barrier across
      local a, b = at(math.min(prev[1], road[1])), at(math.max(prev[1], road[1]))
      color(C.gunmetalLight)
      love.graphics.rectangle("fill", a - 8, y - 4, b - a + 8, 8)
      color(C.yellow, 0.85)
      love.graphics.rectangle("fill", a + 10, y - 2, b - a, 5)
      a, b = at(math.min(prev[2], road[2]) + 1), at(math.max(prev[2], road[2]) + 1)
      love.graphics.rectangle("fill", a - 15, y - 2, b - a, 5)
    end
  end
end

--- Map `map` into the canvas (city-map's Render.build, at half size): the
--- outside and floors, the flat things, the snow heaped about, their edges,
--- then the shadows and whatever stands.
function RenderBorderline.draw(map, T)
  local before = love.graphics.getFont()
  Ground.drawTiles(map, T)
  for _, s in ipairs(map.cover) do
    if s.flat and DRAW[s.kind] then
      DRAW[s.kind](s)
    end
  end
  Ground.drawTracks(map, T)
  Ground.drawDugout(map)
  if map.outside == "works" then
    Ground.drawWallDrifts(map, T)
    Ground.drawCoverDrifts(map)
  end
  Ground.drawEdges(map, T)
  if map.cutsRoad then
    drawRoadLines(map, T)
  end
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

--- One thing of `map.cover` drawn on its own (surroundings/borderline.lua
--- draws what crosses the map's edge, past it).
function RenderBorderline.drawCover(s)
  if DRAW[s.kind] then
    DRAW[s.kind](s)
  end
end

return RenderBorderline
