-- Draws the tutorial's maps (tutorial_maps.lua builds them). So far
-- Shoeman's Road: into the canvas, the grass embankment down both sides
-- with its concrete retaining walls; the pavement in slabs; the four
-- streets in tarmac, dark into their tunnels, with kerbs, edge lines,
-- dashed lane lines, the double yellow down the middle and an arrow on
-- every lane the way it runs; tyre marks, cracks, oil and manholes; "LOOK
-- LEFT" at every kerb; the school yard's beds, trees and benches and
-- Shoeman's board, and the lawn at the top. Over the cars, every frame
-- (`drawAbove`), the embankment over each tunnel and the portal's
-- headwall, so a car drives out of the dark and back into it.

local TutorialMaps = require("src.features.city-map.tutorial_maps")

local RenderTutorial = {}

local C = {
  grass = { 0.36, 0.53, 0.26 },
  grassLight = { 0.44, 0.61, 0.31 },
  grassDark = { 0.29, 0.44, 0.21 },
  slab = { 0.66, 0.65, 0.62 },
  slabDark = { 0.58, 0.57, 0.54 },
  joint = { 0.50, 0.49, 0.47 },
  kerb = { 0.80, 0.79, 0.76 },
  asphalt = { 0.22, 0.22, 0.24 },
  asphaltLight = { 0.27, 0.27, 0.29 },
  line = { 0.92, 0.92, 0.88 },
  yellow = { 0.95, 0.78, 0.22 },
  skid = { 0.08, 0.08, 0.09, 0.55 },
  crack = { 0.12, 0.12, 0.13, 0.8 },
  oil = { 0.06, 0.06, 0.08, 0.45 },
  iron = { 0.30, 0.30, 0.31 },
  ironDark = { 0.18, 0.18, 0.19 },
  concrete = { 0.62, 0.62, 0.60 },
  concreteDark = { 0.45, 0.45, 0.44 },
  concreteLight = { 0.74, 0.74, 0.72 },
  shadow = { 0, 0, 0, 0.3 },
  soil = { 0.36, 0.26, 0.18 },
  leaf = { 0.25, 0.46, 0.22 },
  leafLight = { 0.34, 0.57, 0.28 },
  wood = { 0.52, 0.36, 0.22 },
  woodDark = { 0.38, 0.26, 0.16 },
  chalkboard = { 0.16, 0.24, 0.20 },
  chalk = { 0.92, 0.92, 0.88 },
  flowers = { { 0.92, 0.30, 0.32 }, { 0.98, 0.84, 0.30 }, { 0.70, 0.45, 0.88 }, { 0.98, 0.98, 0.95 } },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function hash(n)
  local s = math.sin(n * 12.9898) * 43758.5453
  return s - math.floor(s)
end

local fonts = {}
local function font(size)
  fonts[size] = fonts[size] or love.graphics.newFont(size)
  return fonts[size]
end

--- A patch of grass over (x, y, w, h), tufted.
local function grass(x, y, w, h, seed)
  color(C.grass)
  love.graphics.rectangle("fill", x, y, w, h)
  for i = 1, math.floor(w * h / 900) do
    local k = seed + i
    color(hash(k) < 0.5 and C.grassLight or C.grassDark, 0.7)
    love.graphics.rectangle("fill", x + hash(k * 1.3) * (w - 6), y + hash(k * 2.1) * (h - 4), 4 + hash(k * 3.7) * 6, 3)
  end
end

--- The pavement over (x, y, w, h): slabs 32 px square, a few a shade darker.
local function pavement(x, y, w, h)
  color(C.slab)
  love.graphics.rectangle("fill", x, y, w, h)
  local S = 32
  for i = 0, math.ceil(w / S) - 1 do
    for j = 0, math.ceil(h / S) - 1 do
      if hash(x + i * 7.1 + (y + j) * 3.3) < 0.18 then
        color(C.slabDark)
        love.graphics.rectangle("fill", x + i * S, y + j * S, math.min(S, w - i * S), math.min(S, h - j * S))
      end
    end
  end
  color(C.joint)
  love.graphics.setLineWidth(2)
  for i = 1, math.ceil(w / S) - 1 do
    love.graphics.line(x + i * S, y, x + i * S, y + h)
  end
  for j = 1, math.ceil(h / S) - 1 do
    love.graphics.line(x, y + j * S, x + w, y + j * S)
  end
end

--- An arrow painted on a lane at (x, y), pointing `dir` (1 east, -1 west).
local function arrow(x, y, dir)
  color(C.line, 0.85)
  love.graphics.rectangle("fill", x - 30 * dir - (dir < 0 and 36 or 0), y - 4, 36, 8)
  local tip = x + 26 * dir
  love.graphics.polygon("fill", tip, y, tip - 22 * dir, y - 14, tip - 22 * dir, y + 14)
end

--- One street: tarmac across the map, darkening into the tunnels under
--- the verges, its kerbs and markings between them.
local function street(map, s, inL, inR)
  local T = 64
  color(C.asphalt)
  love.graphics.rectangle("fill", map.left, s.y0, map.w, s.y1 - s.y0)
  for i = 0, math.floor((inR - inL) / 24) do
    local k = s.n * 100 + i
    if hash(k) < 0.35 then
      color(C.asphaltLight, 0.6)
      local y = s.y0 + hash(k * 1.7) * (s.y1 - s.y0 - 10)
      love.graphics.rectangle("fill", inL + i * 24, y, 12 + hash(k * 2.9) * 20, 4)
    end
  end
  -- Edge lines, the lane lines, the double yellow.
  local mid = (s.y0 + s.y1) / 2
  color(C.line)
  love.graphics.rectangle("fill", map.left, s.y0 + 6, map.w, 4)
  love.graphics.rectangle("fill", map.left, s.y1 - 10, map.w, 4)
  for x = inL + 8, inR - 40, 64 do
    love.graphics.rectangle("fill", x, s.y0 + T - 2, 32, 4)
    love.graphics.rectangle("fill", x, s.y1 - T - 2, 32, 4)
  end
  color(C.yellow)
  love.graphics.rectangle("fill", map.left, mid - 6, map.w, 3)
  love.graphics.rectangle("fill", map.left, mid + 3, map.w, 3)
  for _, lane in ipairs(map.lanes) do
    if lane.street == s.n then
      for k = 1, 3 do
        arrow(inL + (inR - inL) * (k - 0.5) / 3 + lane.dir * 40 * lane.lane, lane.y, lane.dir)
      end
    end
  end
  -- Into the dark: the road in the tunnel's shade for a car's length in
  -- front of each mouth, black under the verge (the roof hides it, but
  -- not from the big map's eye).
  love.graphics.setColor(0.02, 0.02, 0.03, 0.92)
  love.graphics.rectangle("fill", map.left, s.y0, inL - map.left, s.y1 - s.y0)
  love.graphics.rectangle("fill", inR, s.y0, map.left + map.w - inR, s.y1 - s.y0)
  local steps, shade = 8, 64
  for i = 0, steps - 1 do
    love.graphics.setColor(0.02, 0.02, 0.03, (steps - i) / steps * 0.6)
    love.graphics.rectangle("fill", inL + i * shade / steps, s.y0, shade / steps, s.y1 - s.y0)
    love.graphics.rectangle("fill", inR - (i + 1) * shade / steps, s.y0, shade / steps, s.y1 - s.y0)
  end
  -- The kerbs along the pavement, the gutter's shadow below.
  color(C.kerb)
  love.graphics.rectangle("fill", inL, s.y0 - 6, inR - inL, 6)
  love.graphics.rectangle("fill", inL, s.y1, inR - inL, 6)
  color(C.shadow)
  love.graphics.rectangle("fill", inL, s.y0, inR - inL, 4)
end

local function decor(d)
  if d.kind == "skid" then
    color(C.skid)
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    love.graphics.rectangle("fill", 0, -9, d.len, 5)
    love.graphics.rectangle("fill", 0, 5, d.len * 0.9, 5)
    love.graphics.pop()
  elseif d.kind == "crack" then
    color(C.crack)
    love.graphics.setLineWidth(2)
    local x, y, a = d.x, d.y, d.a
    for i = 1, 5 do
      a = a + (hash(d.seed + i) - 0.5) * 1.2
      local nx, ny = x + math.cos(a) * d.len / 5, y + math.sin(a) * d.len / 5
      love.graphics.line(x, y, nx, ny)
      x, y = nx, ny
    end
  elseif d.kind == "stain" then
    color(C.oil)
    love.graphics.ellipse("fill", d.x, d.y, d.r * 1.4, d.r, 16)
    love.graphics.ellipse("fill", d.x + d.r * 0.8, d.y + d.r * 0.3, d.r * 0.6, d.r * 0.45, 12)
  elseif d.kind == "manhole" then
    color(C.ironDark)
    love.graphics.circle("fill", d.x, d.y, 17, 20)
    color(C.iron)
    love.graphics.circle("fill", d.x, d.y, 14, 20)
    color(C.ironDark)
    love.graphics.setLineWidth(2)
    for k = -2, 2 do
      love.graphics.line(d.x - 12, d.y + k * 5, d.x + 12, d.y + k * 5)
    end
  elseif d.kind == "grate" then
    color(C.ironDark)
    love.graphics.rectangle("fill", d.x - 18, d.y - 6, 36, 12)
    color(C.iron)
    for k = 0, 5 do
      love.graphics.rectangle("fill", d.x - 16 + k * 6, d.y - 4, 3, 8)
    end
  elseif d.kind == "look" then
    color(C.line, 0.9)
    local f = font(22)
    love.graphics.setFont(f)
    love.graphics.printf(d.text, d.x - 200, d.y - 11, 400, "center")
    local w = f:getWidth(d.text)
    arrow(d.x - w / 2 - 40, d.y, -1)
  elseif d.kind == "bed" then
    color(C.concreteDark)
    love.graphics.rectangle("fill", d.x - 6, d.y - 6, d.w + 12, d.h + 12, 6)
    color(C.soil)
    love.graphics.rectangle("fill", d.x, d.y, d.w, d.h, 4)
    grass(d.x + 6, d.y + 6, d.w - 12, d.h - 12, d.seed)
    for i = 1, math.floor(d.w * d.h / 500) do
      local k = d.seed * 3 + i
      color(C.flowers[math.floor(hash(k) * #C.flowers) + 1])
      love.graphics.circle("fill", d.x + 10 + hash(k * 1.9) * (d.w - 20), d.y + 10 + hash(k * 2.7) * (d.h - 20), 3, 6)
    end
  elseif d.kind == "tree" then
    color(C.shadow)
    love.graphics.circle("fill", d.x + 8, d.y + 10, d.r, 20)
    color(C.leaf)
    love.graphics.circle("fill", d.x, d.y, d.r, 20)
    color(C.leafLight)
    love.graphics.circle("fill", d.x - d.r * 0.25, d.y - d.r * 0.25, d.r * 0.6, 16)
  elseif d.kind == "bench" then
    love.graphics.push()
    love.graphics.translate(d.x, d.y)
    love.graphics.rotate(d.a)
    color(C.shadow)
    love.graphics.rectangle("fill", -10, -26, 30, 60)
    color(C.woodDark)
    love.graphics.rectangle("fill", -14, -30, 8, 60)
    color(C.wood)
    for k = 0, 2 do
      love.graphics.rectangle("fill", -4 + k * 7, -30, 5, 60)
    end
    love.graphics.pop()
  elseif d.kind == "board" then
    color(C.shadow)
    love.graphics.rectangle("fill", d.x + 8, d.y + 8, 220, 70)
    color(C.woodDark)
    love.graphics.rectangle("fill", d.x - 6, d.y - 6, 232, 82)
    color(C.chalkboard)
    love.graphics.rectangle("fill", d.x, d.y, 220, 70)
    color(C.chalk)
    love.graphics.setFont(font(15))
    love.graphics.printf("SHOEMAN'S SCHOOL\nOF SURVIVAL", d.x, d.y + 14, 220, "center")
  end
end

--- Into the map's canvas (render.lua's Render.build), in world px.
function RenderTutorial.draw(map, T)
  local before = love.graphics.getFont()
  local verge = TutorialMaps.ROAD.verge
  local inL, inR = map.x0 + (map.c0 + verge) * T, map.x0 + (map.c1 + 1 - verge) * T
  -- The embankment everywhere; the pavement over every walked tile.
  grass(map.left, map.top, map.w, map.h, 7)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if map.tiles[c][r] == "walk" then
        pavement(map.x0 + c * T, map.y0 + r * T, T, T)
      end
    end
  end
  for _, s in ipairs(map.streets) do
    street(map, s, inL, inR)
  end
  -- The retaining walls down the pavement's sides, their shadow on it.
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      local here = map.tiles[c][r] == "walk"
      local west = map.tiles[c - 1] and map.tiles[c - 1][r]
      local east = map.tiles[c + 1] and map.tiles[c + 1][r]
      if here and not west then
        local x = map.x0 + c * T
        color(C.shadow)
        love.graphics.rectangle("fill", x, map.y0 + r * T, 10, T)
        color(C.concrete)
        love.graphics.rectangle("fill", x - 10, map.y0 + r * T, 10, T)
        color(C.concreteLight)
        love.graphics.rectangle("fill", x - 10, map.y0 + r * T, 3, T)
      elseif here and not east then
        local x = map.x0 + (c + 1) * T
        color(C.concrete)
        love.graphics.rectangle("fill", x, map.y0 + r * T, 10, T)
        color(C.concreteDark)
        love.graphics.rectangle("fill", x + 7, map.y0 + r * T, 3, T)
      end
    end
  end
  for _, d in ipairs(map.decor) do
    decor(d)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(before)
end

--- Over the cars, every frame: the embankment over each tunnel and the
--- portal on its mouth, a concrete headwall across the road with a wing
--- wall slanting back into the bank at either end.
function RenderTutorial.drawAbove(map)
  for i, t in ipairs(map.tunnels) do
    grass(t.x, t.y - 8, t.w, t.h + 16, 50 + i)
    local out = t.side == "w" and 1 or -1 -- towards the road
    local face = t.side == "w" and t.x + t.w or t.x -- the mouth's edge
    local W = 22 -- the headwall's thickness
    local x = face - (out > 0 and W or 0)
    color(C.concreteDark)
    for _, y in ipairs({ t.y - 20, t.y + t.h + 20 }) do
      local dy = y < t.y and -1 or 1
      love.graphics.polygon("fill", face, y, face - out * 54, y + dy * 40, face - out * 54 - out * 12,
        y + dy * 32, face - out * 12, y - dy * 8)
    end
    color(C.shadow)
    love.graphics.rectangle("fill", out > 0 and face or face - 12, t.y - 20, 12, t.h + 40)
    color(C.concrete)
    love.graphics.rectangle("fill", x, t.y - 22, W, t.h + 44)
    color(C.concreteLight)
    love.graphics.rectangle("fill", x, t.y - 22, W, 5)
    love.graphics.rectangle("fill", out > 0 and x + W - 4 or x, t.y - 22, 4, t.h + 44)
    color(C.concreteDark)
    love.graphics.rectangle("fill", x, t.y + t.h + 17, W, 5)
    for k = 1, 3 do -- joints between the headwall's panels
      love.graphics.rectangle("fill", x, t.y - 22 + k * (t.h + 44) / 4, W, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return RenderTutorial
