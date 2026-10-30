-- Draws the Colosseum's arena (arena.lua) into the map canvas: the raked
-- sand, the podium wall round it with its shadow on the sand, the gate in
-- the south wall and the cover about the sand (other maps' pieces). Past
-- the wall the canvas stays clear: the stands are
-- the colosseum feature's, drawn past the map's edge by surroundings, and
-- they show through.

local Arena = require("src.features.city-map.arena")
local RenderBorderline = require("src.features.city-map.render_borderline")

local RenderArena = {}

local C = {
  sand = { 0.84, 0.73, 0.50 },
  sandDark = { 0.76, 0.64, 0.42 },
  sandLight = { 0.90, 0.81, 0.60 },
  shadow = { 0, 0, 0, 0.32 },
  wall = { 0.78, 0.72, 0.60 },
  wallTop = { 0.86, 0.81, 0.70 },
  wallEdge = { 0.45, 0.40, 0.32 },
  gate = { 0.12, 0.10, 0.09 },
  bars = { 0.35, 0.33, 0.32 },
  banner = { 0.62, 0.10, 0.12 },
  gold = { 0.90, 0.70, 0.20 },
}

local function color(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- The sand: raked in long rings round the middle, scuffed here and there.
local function drawSand(o)
  color(C.sand)
  love.graphics.ellipse("fill", o.x, o.y, o.rx + 4, o.ry + 4, 96)
  love.graphics.setLineWidth(3)
  for k = 1, 9 do
    color(k % 2 == 0 and C.sandDark or C.sandLight)
    love.graphics.ellipse("line", o.x, o.y, o.rx * k / 10, o.ry * k / 10, 96)
  end
  love.graphics.setLineWidth(1)
  color(C.sandDark)
  for k = 1, 40 do -- scuffs and footprints of fights before
    local a, d = hash(k) * 2 * math.pi, 0.15 + hash(k + 50) * 0.75
    local x, y = o.x + math.cos(a) * o.rx * d, o.y + math.sin(a) * o.ry * d
    love.graphics.ellipse("fill", x, y, 18 + hash(k + 9) * 40, 8 + hash(k + 3) * 16, 12)
  end
  -- The emblem in the middle: a ring and a cross of darker sand.
  local ex, ey = o.rx * 0.125, o.ry * 0.125 -- its size goes with the sand's
  love.graphics.setLineWidth(10)
  love.graphics.ellipse("line", o.x, o.y, ex, ey, 64)
  love.graphics.line(o.x - ex * 0.73, o.y, o.x + ex * 0.73, o.y)
  love.graphics.line(o.x, o.y - ey * 0.72, o.x, o.y + ey * 0.72)
  love.graphics.setLineWidth(1)
end

--- The podium wall: its shadow on the sand (the light from up and to the
--- left), the wall's top, a dark line where it meets the sand, banners hung
--- along it.
local function drawWall(o, W)
  local mid = W / 2
  love.graphics.setLineWidth(W)
  color(C.shadow)
  love.graphics.ellipse("line", o.x + 16, o.y + 16, o.rx + mid, o.ry + mid, 128)
  color(C.wall)
  love.graphics.ellipse("line", o.x, o.y, o.rx + mid, o.ry + mid, 128)
  love.graphics.setLineWidth(W * 0.4)
  color(C.wallTop)
  love.graphics.ellipse("line", o.x, o.y, o.rx + W * 0.65, o.ry + W * 0.65, 128)
  love.graphics.setLineWidth(4)
  color(C.wallEdge)
  love.graphics.ellipse("line", o.x, o.y, o.rx + 2, o.ry + 2, 128)
  love.graphics.ellipse("line", o.x, o.y, o.rx + W, o.ry + W, 128)
  love.graphics.setLineWidth(1)
  for k = 0, 23 do -- banners down the wall's face, red and gold by turns
    local a = k * math.pi / 12 + math.pi / 24
    local x, y = o.x + math.cos(a) * (o.rx + 6), o.y + math.sin(a) * (o.ry + 6)
    color(k % 2 == 0 and C.banner or C.gold)
    love.graphics.circle("fill", x, y, 9, 10)
  end
end

--- The gate in the middle of the south wall: a dark way through, a
--- portcullis raised into it, a pillar each side.
local function drawGate(map, W)
  local x, y = map.gateX, map.gateY
  color(C.gate)
  love.graphics.rectangle("fill", x - 70, y, 140, W + 4)
  color(C.bars)
  for k = -3, 3 do
    love.graphics.rectangle("fill", x + k * 18 - 2, y + W * 0.45, 4, W * 0.55)
  end
  love.graphics.rectangle("fill", x - 66, y + W * 0.45, 132, 5)
  for _, side in ipairs({ -1, 1 }) do
    color(C.shadow)
    love.graphics.rectangle("fill", x + side * 88 - 18 + 10, y - 14 + 10, 36, W + 22)
    color(C.wallEdge)
    love.graphics.rectangle("fill", x + side * 88 - 19, y - 15, 38, W + 24)
    color(C.wallTop)
    love.graphics.rectangle("fill", x + side * 88 - 17, y - 13, 34, W + 20)
  end
end

-- The kinds Borderline draws (render_borderline.lua); they leave their shadows to the map.
local BORDERLINE = { container = true, crate = true, drum = true }

--- The cover on the sand: the shadows of Borderline's pieces first, then
--- every piece, Borderline's its way and the rest by `props` (render.lua's
--- own: D-Day's sandbags, the Outer City's barriers, each with its shadow).
local function drawCover(map, props)
  local font = love.graphics.getFont()
  color(C.shadow)
  for _, s in ipairs(map.cover) do
    if s.kind == "drum" then
      love.graphics.ellipse("fill", s.x + s.w / 2 + 10, s.y + s.h / 2 + 10, s.w / 2, s.h / 2, 16)
    elseif BORDERLINE[s.kind] then
      love.graphics.rectangle("fill", s.x + 12, s.y + 12, s.w, s.h)
    end
  end
  for _, s in ipairs(map.cover) do
    if BORDERLINE[s.kind] then
      RenderBorderline.drawCover(s)
    elseif props[s.kind] then
      props[s.kind](s)
    end
  end
  love.graphics.setFont(font)
end

--- `props` draws the pieces render.lua owns, by kind.
function RenderArena.draw(map, _T, props)
  drawSand(map.oval)
  drawWall(map.oval, Arena.WALL)
  drawGate(map, Arena.WALL)
  drawCover(map, props or {})
end

return RenderArena
