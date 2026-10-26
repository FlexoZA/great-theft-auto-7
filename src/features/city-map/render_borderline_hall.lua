-- The Refinery's smelting hall (borderline.lua's `refinery`,
-- borderline_refinery.lua), drawn into the map's canvas by
-- render_borderline.lua: the molten river and the kerbs along its banks
-- (its bridges are live: the borderline feature's bridges.lua), the
-- smelting tanks, the pipe racks, the casting pit and its moulds, the steam
-- vents' grilles, ladles parked for the cranes, stacks of ingots, slag gone
-- hard where the river spilled. Each is a `DRAW[kind](s)` for a thing of
-- `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Hall = {}

local INK, C = Kit.INK, Kit.C
local color, hash, lengthwise = Kit.color, Kit.hash, Kit.lengthwise
local box, blob, hazard = Kit.box, Kit.blob, Kit.hazard

local DRAW = {}
Hall.DRAW = DRAW

local MOLTEN = { 0.50, 0.16, 0.82 } -- the river under its crust
local HOT = { 1.00, 0.80, 1.00 } -- the hottest of it
local KERB = 14 -- px of steel kerb along a bank

--- A crust floe on the river at (x, y), `r` across: a dark plate of
--- Bragium gone hard, a glowing rim where it melts at the edges, a crack.
local function floe(x, y, r, seed)
  local pts = {}
  for k = 0, 6 do
    local a = k / 7 * math.pi * 2 + seed
    local rr = r * (0.65 + 0.4 * hash(seed * 3 + k))
    pts[#pts + 1] = x + math.cos(a) * rr * 1.5
    pts[#pts + 1] = y + math.sin(a) * rr * 0.8
  end
  color(C.purpleLight, 0.8)
  love.graphics.setLineWidth(5)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
  color(C.slag)
  love.graphics.polygon("fill", pts)
  color(C.white, 0.12)
  love.graphics.ellipse("fill", x - r * 0.4, y - r * 0.2, r * 0.6, r * 0.2, 10)
  color(C.purple, 0.8)
  love.graphics.setLineWidth(2)
  love.graphics.line(x - r * 0.8, y + r * 0.1, x - r * 0.1, y - r * 0.15, x + r * 0.7, y + r * 0.2)
  love.graphics.setLineWidth(1)
end

--- A steel kerb along a bank from (x, y), `len` long, `across` it runs
--- along x (else along y): the plate, hazard paint on its lip, the posts
--- of the railing on the floor's side (`out` +1 or -1: which way that is).
local function kerb(x, y, len, along, out)
  if along then
    box(x, y, len, KERB, C.gunmetalLight)
    hazard(x, y + (out > 0 and KERB - 5 or 0), len, 5)
    color(INK)
    for a = x + 14, x + len - 6, 48 do
      love.graphics.rectangle("fill", a, y + (out > 0 and KERB + 2 or -8), 6, 6)
    end
  else
    box(x, y, KERB, len, C.gunmetalLight)
    hazard(x + (out > 0 and KERB - 5 or 0), y, 5, len)
    color(INK)
    for a = y + 14, y + len - 6, 48 do
      love.graphics.rectangle("fill", x + (out > 0 and KERB + 2 or -8), a, 6, 6)
    end
  end
end

--- A bank's kerb along an edge from `a0` to `a1`, leaving out `gap` ({ from,
--- to }, the same axis) where a bend joins the run.
local function bank(a0, a1, at, along, out, gap)
  if gap then
    if gap[1] > a0 then
      kerb(along and a0 or at, along and at or a0, gap[1] - a0, along, out)
    end
    if a1 > gap[2] then
      kerb(along and gap[2] or at, along and at or gap[2], a1 - gap[2], along, out)
    end
  else
    kerb(along and a0 or at, along and at or a0, a1 - a0, along, out)
  end
end

--- A run or a bend of the molten river, drawn whole (its bridges stand
--- over it): deep purple, a hotter core down the middle the way it runs,
--- crust floes riding it, bubbles; a steel kerb with a railing along each
--- bank (`north` / `south`: where a bend leaves a run, no kerb there; a
--- bend's `wall`, the side it runs along a wall, none there either).
function DRAW.river(s)
  local along = s.w >= s.h
  local seed = s.seed or 1
  color(MOLTEN)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  local len, wide = along and s.w or s.h, along and s.h or s.w
  for k = 0, 2 do -- the hot core, in bands either side of the middle
    color(k == 0 and C.purple or C.purpleLight, k == 0 and 0.9 or 0.35 + 0.15 * (k - 1))
    local band = wide * (0.62 - k * 0.2)
    if along then
      love.graphics.rectangle("fill", s.x, s.y + (s.h - band) / 2, s.w, band)
    else
      love.graphics.rectangle("fill", s.x + (s.w - band) / 2, s.y, band, s.h)
    end
  end
  color(HOT, 0.5) -- the brightest thread, wandering
  love.graphics.setLineWidth(3)
  local pts = {}
  for a = 0, len, 32 do
    local off = math.sin(a / 70 + seed) * wide * 0.12
    pts[#pts + 1] = along and s.x + a or s.x + wide / 2 + off
    pts[#pts + 1] = along and s.y + wide / 2 + off or s.y + a
  end
  if #pts >= 4 then
    love.graphics.line(pts)
  end
  love.graphics.setLineWidth(1)
  for i = 0, math.floor(len / 110) do -- the crust, riding near the banks
    local h = hash(seed * 7 + i * 1.9)
    local side = (i % 2 == 0 and 0.2 or 0.8) + (h - 0.5) * 0.1
    local a = i * 110 + h * 60
    local r = 12 + 14 * hash(seed + i * 3.1)
    if a < len - 20 then
      floe(along and s.x + a or s.x + wide * side, along and s.y + wide * side or s.y + a, r, seed + i)
    end
  end
  color(HOT, 0.6) -- bubbles
  for i = 0, math.floor(len / 60) do
    local h = hash(seed * 3 + i * 2.7)
    local a, b = i * 60 + h * 40, wide * (0.3 + 0.4 * hash(h + i))
    love.graphics.circle("line", along and s.x + a or s.x + b, along and s.y + b or s.y + a, 3 + 4 * h, 8)
  end
  -- The banks.
  if along then
    bank(s.x, s.x + s.w, s.y - KERB, true, -1, s.north and { s.north[1], s.north[2] })
    bank(s.x, s.x + s.w, s.y + s.h, true, 1, s.south and { s.south[1], s.south[2] })
  else -- (a bend runs along a wall: no kerb on that side)
    if s.wall ~= "w" then
      kerb(s.x - KERB, s.y, s.h, false, -1)
    end
    if s.wall ~= "e" then
      kerb(s.x + s.w, s.y, s.h, false, 1)
    end
  end
end

--- A smelting tank, from above: its glow on the floor, the jacket in
--- riveted segments, a band of Hyperbole yellow, the domed top with its
--- charging hatch, the ports glowing purple round it, a ladder up the side
--- and the pipes stubbed out of it.
function DRAW.tank(s)
  local h = hash(s.seed or 1)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.purple, 0.18)
  love.graphics.circle("fill", cx, cy, r * 1.3, 24)
  local a0 = h * math.pi * 2
  for _, a in ipairs({ a0, a0 + 2.4 }) do -- the pipes out of it
    local ca, sa = math.cos(a), math.sin(a)
    color(INK)
    love.graphics.setLineWidth(18)
    love.graphics.line(cx + ca * r * 0.8, cy + sa * r * 0.8, cx + ca * (r + 26), cy + sa * (r + 26))
    color(C.gunmetalLight)
    love.graphics.setLineWidth(10)
    love.graphics.line(cx + ca * r * 0.8, cy + sa * r * 0.8, cx + ca * (r + 24), cy + sa * (r + 24))
    love.graphics.setLineWidth(1)
  end
  local la = a0 + 4.2 -- the ladder up its side
  love.graphics.push()
  love.graphics.translate(cx + math.cos(la) * r, cy + math.sin(la) * r)
  love.graphics.rotate(la)
  box(-2, -9, 16, 18, C.gunmetal)
  color(C.gunmetalLight)
  for a = 0, 12, 4 do
    love.graphics.rectangle("fill", a, -9, 2, 18)
  end
  love.graphics.pop()
  blob(s.x, s.y, s.w, s.h, C.steel)
  color(INK, 0.35) -- the jacket's segments, riveted
  for k = 0, 11 do
    local a = k / 12 * math.pi * 2
    love.graphics.line(cx + math.cos(a) * r * 0.72, cy + math.sin(a) * r * 0.72, cx + math.cos(a) * r,
      cy + math.sin(a) * r)
  end
  color(C.yellow)
  love.graphics.setLineWidth(8)
  love.graphics.circle("line", cx, cy, r * 0.82, 28)
  love.graphics.setLineWidth(1)
  color(INK, 0.5)
  love.graphics.circle("line", cx, cy, r * 0.78, 28)
  color(C.gunmetalLight) -- the dome, lit from up and to the left
  love.graphics.circle("fill", cx, cy, r * 0.62, 24)
  color(C.white, 0.2)
  love.graphics.circle("fill", cx - r * 0.18, cy - r * 0.18, r * 0.36, 18)
  box(cx - r * 0.2, cy - r * 0.2, r * 0.4, r * 0.4, C.gunmetal) -- the charging hatch
  color(C.gunmetalLight)
  love.graphics.rectangle("fill", cx - r * 0.2, cy - r * 0.05, r * 0.4, r * 0.1)
  for k = 0, 3 do -- the ports, glowing
    local a = a0 + 0.8 + k * math.pi / 2
    local px, py = cx + math.cos(a) * r * 0.9, cy + math.sin(a) * r * 0.9
    color(INK)
    love.graphics.circle("fill", px, py, 7, 10)
    color(C.purpleLight)
    love.graphics.circle("fill", px, py, 4.5, 10)
  end
end

--- A pipe rack along the bank: two pipes side by side up on their
--- supports, lit along the top, flanged every so often, a red valve wheel
--- halfway.
function DRAW.pipe(s)
  lengthwise(s, function(L, W)
    color(C.shadow)
    for a = -L / 2 + 30, L / 2 - 30, 128 do
      love.graphics.rectangle("fill", a, -W / 2, 14, W + 10)
    end
    for _, y in ipairs({ -W / 2, 0 }) do
      box(-L / 2, y, L, W / 2, C.gunmetalLight)
      color(C.white, 0.25)
      love.graphics.rectangle("fill", -L / 2, y + 2, L, 3)
      color(INK, 0.6)
      for a = -L / 2 + 40, L / 2 - 20, 64 do -- the flanges
        love.graphics.rectangle("fill", a, y - 2, 5, W / 2 + 4)
      end
    end
    color(C.yellowDark) -- the supports' saddles
    for a = -L / 2 + 26, L / 2 - 30, 128 do
      love.graphics.rectangle("fill", a, -W / 2 - 4, 14, 5)
    end
    color(INK) -- the valve wheel
    love.graphics.circle("fill", 0, 0, 13, 14)
    color({ 0.80, 0.16, 0.12 })
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", 0, 0, 10, 14)
    love.graphics.line(-10, 0, 10, 0)
    love.graphics.line(0, -10, 0, 10)
    love.graphics.setLineWidth(1)
  end)
end

--- The casting pit by the outflow: sunk in the floor, its walls going
--- down, a runner channel across it carrying molten Bragium to rows of
--- moulds, the fresh ones still glowing, the older ones gone dark, hazard
--- paint round the lip.
function DRAW.casting(s)
  box(s.x, s.y, s.w, s.h, C.pitWall)
  color(C.pitDeep)
  love.graphics.rectangle("fill", s.x + 18, s.y + 18, s.w - 36, s.h - 36)
  color(INK, 0.4) -- the walls dropping into it, darker going down
  love.graphics.rectangle("fill", s.x + 18, s.y + 18, s.w - 36, 10)
  love.graphics.rectangle("fill", s.x + 18, s.y + 18, 10, s.h - 36)
  local ry = s.y + s.h / 2 - 6 -- the runner
  box(s.x + 24, ry, s.w - 48, 12, C.gunmetal)
  color(C.purple)
  love.graphics.rectangle("fill", s.x + 26, ry + 3, s.w - 52, 6)
  color(HOT, 0.6)
  love.graphics.rectangle("fill", s.x + 26, ry + 5, s.w - 52, 2)
  local i = 0
  for _, y in ipairs({ s.y + 36, s.y + s.h / 2 + 18 }) do
    for x = s.x + 36, s.x + s.w - 76, 60 do
      i = i + 1
      box(x, y, 40, s.h / 2 - 54, C.gunmetal)
      local fresh = hash((s.seed or 1) + i) < 0.55
      color(fresh and C.purple or C.slag)
      love.graphics.rectangle("fill", x + 5, y + 5, 30, s.h / 2 - 64)
      if fresh then
        color(HOT, 0.55)
        love.graphics.rectangle("fill", x + 12, y + 10, 16, s.h / 2 - 74)
      else
        color(C.purpleLight, 0.25)
        love.graphics.rectangle("fill", x + 7, y + 7, 26, 4)
      end
    end
  end
  hazard(s.x, s.y, s.w, 12)
  hazard(s.x, s.y + s.h - 12, s.w, 12)
  hazard(s.x, s.y, 12, s.h)
  hazard(s.x + s.w - 12, s.y, 12, s.h)
end

--- A steam vent in the floor: a frame round a grille over the dark, the
--- floor sooted round it (the steam is works.lua's).
function DRAW.grille(s)
  color(INK, 0.22)
  love.graphics.ellipse("fill", s.x + s.w / 2, s.y + s.h / 2, s.w * 0.75, s.h * 0.6, 16)
  box(s.x + 4, s.y + 4, s.w - 8, s.h - 8, C.gunmetal)
  color(INK)
  love.graphics.rectangle("fill", s.x + 10, s.y + 10, s.w - 20, s.h - 20)
  color(C.gunmetalLight)
  for x = s.x + 12, s.x + s.w - 14, 8 do
    love.graphics.rectangle("fill", x, s.y + 10, 3, s.h - 20)
  end
  color(C.purple, 0.3) -- the heat down there
  love.graphics.rectangle("fill", s.x + 12, s.y + s.h / 2 - 2, s.w - 24, 4)
end

--- A ladle parked for the cranes: a thick refractory cup in a steel shell,
--- the trunnions out either side for the crane's hook, the pouring lip;
--- in it, Bragium gone hard on top, still glowing through the cracks.
function DRAW.ladle(s)
  local h = hash(s.seed or 1)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  local a = h * math.pi
  local ca, sa = math.cos(a), math.sin(a)
  for _, side in ipairs({ -1, 1 }) do -- the trunnions
    box(cx + ca * side * r - 9, cy + sa * side * r - 9, 18, 18, C.gunmetal)
  end
  blob(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(C.yellow) -- the pouring lip
  love.graphics.polygon("fill", cx - sa * r * 0.9 - ca * 10, cy + ca * r * 0.9 - sa * 10,
    cx - sa * (r + 12), cy + ca * (r + 12), cx - sa * r * 0.9 + ca * 10, cy + ca * r * 0.9 + sa * 10)
  color(C.firebrick)
  love.graphics.circle("fill", cx, cy, r * 0.78, 20)
  color(C.slag)
  love.graphics.circle("fill", cx, cy, r * 0.64, 18)
  color(C.purple, 0.9) -- the cracks in the crust, glowing
  love.graphics.setLineWidth(2)
  for k = 0, 2 do
    local b = a + k * 2.1
    love.graphics.line(cx, cy, cx + math.cos(b) * r * 0.55, cy + math.sin(b) * r * 0.55)
  end
  love.graphics.setLineWidth(1)
  color(C.white, 0.15)
  love.graphics.circle("fill", cx - r * 0.25, cy - r * 0.25, r * 0.2, 10)
end

--- A stack of Bragium ingots on a pallet: layers laid crosswise, each bar
--- lit along its top, a steel strap round the lot.
function DRAW.ingots(s)
  box(s.x, s.y, s.w, s.h, C.woodDark)
  local n = 3
  for k = 0, n - 1 do -- the top layer, bars across
    local y = s.y + 4 + k * (s.h - 8) / n
    local bh = (s.h - 8) / n - 3
    box(s.x + 4, y, s.w - 8, bh, C.slag)
    color(C.purpleLight, 0.45)
    love.graphics.rectangle("fill", s.x + 6, y + 1, s.w - 12, 3)
  end
  color(C.gunmetalLight) -- the strap
  love.graphics.rectangle("fill", s.x + s.w / 2 - 3, s.y - 2, 6, s.h + 4)
end

--- Slag, a spill of the river gone hard on the floor: a dark glossy pool,
--- splashes round it, a faint glow left in a crack.
function DRAW.slag(s)
  local h = hash(s.seed or 1)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(C.slag)
  love.graphics.ellipse("fill", cx, cy, s.w * 0.5, s.h * 0.34, 18)
  for k = 0, 3 do
    local a = h * 6 + k * 1.7
    love.graphics.circle("fill", cx + math.cos(a) * s.w * 0.55, cy + math.sin(a) * s.h * 0.4, 4 + 5 * hash(h + k), 8)
  end
  color(C.white, 0.14)
  love.graphics.ellipse("fill", cx - s.w * 0.15, cy - s.h * 0.1, s.w * 0.22, s.h * 0.08, 12)
  color(C.purple, 0.5)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - s.w * 0.25, cy + 2, cx, cy - 3, cx + s.w * 0.2, cy + 4)
  love.graphics.setLineWidth(1)
end

return Hall
