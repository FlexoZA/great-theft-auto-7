-- Draws the Colosseum's arena (arena.lua) into the map canvas: the raked
-- sand, the streams in their stone channels with their basins, statues and
-- bridges, the podium wall round it with its shadow on the sand, the lions'
-- heads the streams spring from, the braziers on top, the gate in the south
-- wall and the cover about the sand (other maps' pieces). What moves (the
-- water running, the fire) is the colosseum feature's (water.lua). Past
-- the wall the canvas stays clear: the stands are
-- the colosseum feature's, drawn past the map's edge by surroundings, and
-- they show through.

local Arena = require("src.features.city-map.arena")
local RenderBorderline = require("src.features.city-map.render_borderline")
local RenderRoad = require("src.features.city-map.render_road")

local offset = RenderRoad.offset

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
  goldDark = { 0.58, 0.40, 0.10 },
  damp = { 0.70, 0.60, 0.40 },
  kerb = { 0.86, 0.82, 0.72 },
  kerbEdge = { 0.50, 0.45, 0.36 },
  shallow = { 0.30, 0.58, 0.60 },
  water = { 0.20, 0.45, 0.52 },
  deep = { 0.13, 0.33, 0.42 },
  glint = { 0.78, 0.92, 0.92 },
  shade = { 0.17, 0.36, 0.42 }, -- the kerb's shadow on the shallows
  reed = { 0.38, 0.52, 0.24 },
  reedLight = { 0.54, 0.66, 0.32 },
  lily = { 0.30, 0.52, 0.26 },
  marble = { 0.92, 0.90, 0.85 },
  marbleDark = { 0.66, 0.63, 0.58 },
  bronze = { 0.50, 0.40, 0.22 },
  bronzeLight = { 0.72, 0.60, 0.34 },
  iron = { 0.22, 0.20, 0.19 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

--- The sand: grainy, raked in long rings round the middle, scuffed here and
--- there, darker in the wall's lee.
local function drawSand(o)
  color(C.sand)
  love.graphics.ellipse("fill", o.x, o.y, o.rx + 4, o.ry + 4, 96)
  for k = 1, 6000 do -- the grain
    local a, d = hash(k * 1.7) * 2 * math.pi, math.sqrt(hash(k * 2.3 + 1))
    color(k % 3 == 0 and C.sandLight or C.sandDark, 0.55)
    love.graphics.rectangle("fill", o.x + math.cos(a) * o.rx * d, o.y + math.sin(a) * o.ry * d, 3, 3)
  end
  love.graphics.setLineWidth(70)
  color(C.sandDark, 0.35)
  love.graphics.ellipse("line", o.x, o.y, o.rx - 35, o.ry - 35, 128)
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

--- `pts` ({ x, y }) as one thick line `width` px wide, the joins rounded.
local function band(pts, width)
  local flat = {}
  for _, p in ipairs(pts) do
    flat[#flat + 1], flat[#flat + 2] = p.x, p.y
  end
  love.graphics.setLineWidth(width)
  love.graphics.line(flat)
  for _, p in ipairs(pts) do
    love.graphics.circle("fill", p.x, p.y, width / 2, 16)
  end
end

--- One layer of every stream and basin: the stream `extra` px wider each
--- side than its water, the basin the same, in `c`.
local function layer(map, c, extra, a)
  color(c, a)
  for _, s in ipairs(map.streams) do
    band(s.pts, 2 * (s.half + extra))
  end
  for _, b in ipairs(map.basins) do
    love.graphics.circle("fill", b.x, b.y, b.r + extra, 64)
  end
end

--- The streams and basins: damp sand round them, reeds, the stone kerb,
--- the water deep down the middle and shallow at the edges, the kerb's
--- shadow on it, lily pads in the basins.
local function drawStreams(map)
  layer(map, C.damp, 40, 0.5)
  layer(map, C.damp, 24, 0.7)
  for i, s in ipairs(map.streams) do -- reeds in clumps along both banks
    for _, side in ipairs({ -1, 1 }) do
      local bank = offset(s.pts, side * (s.half + Arena.KERB + 10))
      for j = 3, #bank - 3, 7 do
        if hash(i * 31 + j * side) > 0.45 then
          local p = bank[j]
          for k = 0, 5 do
            local h = hash(j * 7 + k + side)
            local x, y = p.x + (hash(j + k * 3) - 0.5) * 22, p.y + (hash(j * 3 + k) - 0.5) * 22
            color(k % 2 == 0 and C.reed or C.reedLight)
            love.graphics.setLineWidth(3)
            love.graphics.line(x, y, x + (h - 0.5) * 14, y - 10 - h * 10)
          end
        end
      end
    end
  end
  layer(map, C.kerbEdge, Arena.KERB + 3)
  layer(map, C.kerb, Arena.KERB)
  layer(map, C.kerbEdge, 2)
  layer(map, C.shallow, 0)
  layer(map, C.water, -10)
  for _, s in ipairs(map.streams) do
    color(C.deep)
    band(s.pts, s.half * 0.9)
    color(C.shade) -- the kerb's shadow on the west bank, the light coming over it (they run south)
    band(offset(s.pts, -(s.half - 5)), 10)
  end
  for _, b in ipairs(map.basins) do
    color(C.deep)
    love.graphics.circle("fill", b.x, b.y, b.r * 0.75, 48)
    color(C.shade)
    love.graphics.setLineWidth(10)
    love.graphics.arc("line", "open", b.x, b.y, b.r - 5, math.pi * 0.75, math.pi * 1.6, 24)
    for k = 1, 7 do -- lily pads
      local a, d = hash(k * 4.1 + b.x) * 2 * math.pi, b.statue + 22 + hash(k * 2.7) * (b.r - b.statue - 40)
      local x, y = b.x + math.cos(a) * d, b.y + math.sin(a) * d
      color(C.lily)
      love.graphics.arc("fill", x, y, 9 + hash(k) * 5, a + 0.5, a + 2 * math.pi - 0.2, 12)
      if k % 3 == 0 then
        color(C.marble)
        love.graphics.circle("fill", x + 3, y - 2, 3)
      end
    end
  end
  love.graphics.setLineWidth(1)
end

--- The statue in each basin: an octagonal marble plinth, a bronze
--- gladiator on it, shield up and spear raised, a red crest on his helmet;
--- the plinth's shadow on the water.
local function drawStatue(b)
  local x, y, r = b.x, b.y, b.statue
  local k = r / 20 -- the figure's scale
  color(C.shadow)
  love.graphics.circle("fill", x + 14, y + 16, r, 8)
  color(C.marbleDark)
  love.graphics.circle("fill", x, y, r, 8)
  color(C.marble)
  love.graphics.circle("fill", x - 2, y - 2, r - 4, 8)
  color(C.marbleDark)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x - 2, y - 2, r - 9, 8)
  color(C.shadow)
  love.graphics.ellipse("fill", x + 4 * k, y + 5 * k, 13 * k, 8 * k) -- the figure's own shadow on the plinth
  color(C.iron)
  love.graphics.setLineWidth(3 * k)
  love.graphics.line(x + 14 * k, y + 12 * k, x + 7 * k, y - 24 * k) -- the spear
  color(C.bronze)
  love.graphics.ellipse("fill", x, y + 1 * k, 12 * k, 7 * k) -- shoulders
  love.graphics.setLineWidth(4 * k)
  love.graphics.line(x + 9 * k, y, x + 10 * k, y - 8 * k) -- the arm up to the spear
  love.graphics.circle("fill", x - 11 * k, y + 2 * k, 7.5 * k, 16) -- the shield
  color(C.bronzeLight)
  love.graphics.circle("fill", x - 11 * k, y + 2 * k, 5 * k, 16)
  color(C.bronze)
  love.graphics.circle("fill", x - 11 * k, y + 2 * k, 2 * k, 8) -- its boss
  color(C.bronzeLight)
  love.graphics.circle("fill", x, y - 1 * k, 5.5 * k, 16) -- the helmet
  color(C.banner)
  love.graphics.setLineWidth(3 * k)
  love.graphics.line(x - 6 * k, y - 1 * k, x + 6 * k, y - 1 * k) -- its crest
  love.graphics.setLineWidth(1)
end

--- A stone bridge over a stream: its shadow on the water, the deck paved
--- across, parapets along both sides with posts at the ends.
local function drawBridge(d)
  local P = 10 -- px, a parapet's thickness
  color(C.shadow)
  love.graphics.rectangle("fill", d.x + 10, d.y + 14, d.w, d.h)
  color(C.kerbEdge)
  love.graphics.rectangle("fill", d.x, d.y, d.w, d.h)
  color(C.kerb)
  love.graphics.rectangle("fill", d.x + 2, d.y + 2, d.w - 4, d.h - 4)
  color(C.wallTop) -- the arch's crown, lighter down the middle
  love.graphics.rectangle("fill", d.x + d.w * 0.3, d.y + P, d.w * 0.4, d.h - 2 * P)
  color(C.kerbEdge, 0.6)
  for x = d.x + 18, d.x + d.w - 10, 22 do -- the paving, across the way it runs
    love.graphics.rectangle("fill", x, d.y + P, 2, d.h - 2 * P)
  end
  for _, y in ipairs({ d.y, d.y + d.h - P }) do
    color(C.kerbEdge)
    love.graphics.rectangle("fill", d.x, y, d.w, P)
    color(C.marble)
    love.graphics.rectangle("fill", d.x + 1, y + 1, d.w - 2, P - 4)
    for _, x in ipairs({ d.x, d.x + d.w - 16 }) do -- the posts at the ends
      color(C.kerbEdge)
      love.graphics.rectangle("fill", x - 2, y - 3, 18, P + 6)
      color(C.marble)
      love.graphics.rectangle("fill", x, y - 1, 14, P + 1)
    end
  end
end

--- Where a stream springs, on the wall's face: a lion's head in gold, its
--- mane in rays, water pouring from its mouth onto the sand.
local function drawSpring(s, o)
  local x = s.pts[1].x
  local y = o.y - o.ry * math.sqrt(math.max(0, 1 - ((x - o.x) / o.rx) ^ 2)) + 2 -- the wall's face above it
  color(C.shadow)
  love.graphics.circle("fill", x + 8, y + 2, 28, 20)
  color(C.goldDark)
  for k = 0, 15 do -- the mane
    local a = k * math.pi / 8
    love.graphics.polygon("fill", x + math.cos(a - 0.22) * 16, y - 6 + math.sin(a - 0.22) * 16,
      x + math.cos(a) * 30, y - 6 + math.sin(a) * 30, x + math.cos(a + 0.22) * 16, y - 6 + math.sin(a + 0.22) * 16)
  end
  color(C.gold)
  love.graphics.circle("fill", x, y - 6, 20, 20)
  color(C.goldDark)
  love.graphics.circle("fill", x, y - 6, 15, 20) -- the face
  color(C.gold)
  love.graphics.circle("fill", x, y - 8, 14, 20)
  color(C.sandLight)
  love.graphics.ellipse("fill", x, y - 1, 8, 6) -- the muzzle
  color(C.iron)
  love.graphics.polygon("fill", x - 4, y - 7, x + 4, y - 7, x, y - 3) -- the nose
  love.graphics.setLineWidth(3)
  love.graphics.line(x - 10, y - 16, x - 4, y - 13) -- the brows over the eyes
  love.graphics.line(x + 10, y - 16, x + 4, y - 13)
  love.graphics.ellipse("fill", x, y + 4, 6, 4) -- the mouth
  color(C.shallow)
  love.graphics.rectangle("fill", x - 7, y + 4, 14, 26)
  color(C.glint, 0.8)
  love.graphics.rectangle("fill", x - 3, y + 6, 4, 22)
  love.graphics.setLineWidth(1)
end

--- A brazier on the wall: an iron bowl on a stone footing, its coals.
local function drawBrazier(b)
  color(C.shadow)
  love.graphics.circle("fill", b.x + 6, b.y + 6, 13, 12)
  color(C.wallEdge)
  love.graphics.rectangle("fill", b.x - 14, b.y - 14, 28, 28)
  color(C.iron)
  love.graphics.circle("fill", b.x, b.y, 12, 12)
  love.graphics.setColor(0.55, 0.16, 0.06)
  love.graphics.circle("fill", b.x, b.y, 8, 12)
  love.graphics.setColor(0.95, 0.45, 0.10)
  love.graphics.circle("fill", b.x - 2, b.y - 1, 4, 8)
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
  drawStreams(map)
  -- Where a stream runs back under the wall to its spring, clear the canvas past the wall again, for the stands.
  love.graphics.setBlendMode("replace")
  love.graphics.setColor(0, 0, 0, 0)
  love.graphics.setLineWidth(400)
  local o = map.oval
  love.graphics.ellipse("line", o.x, o.y, o.rx + Arena.WALL + 200, o.ry + Arena.WALL + 200, 128)
  love.graphics.setBlendMode("alpha")
  love.graphics.setLineWidth(1)
  drawWall(map.oval, Arena.WALL)
  for _, s in ipairs(map.streams) do
    drawSpring(s, map.oval)
  end
  for _, b in ipairs(map.braziers) do
    drawBrazier(b)
  end
  drawGate(map, Arena.WALL)
  drawCover(map, props or {})
  for _, b in ipairs(map.basins) do
    drawStatue(b)
  end
  for _, d in ipairs(map.footbridges) do
    drawBridge(d)
  end
end

return RenderArena
