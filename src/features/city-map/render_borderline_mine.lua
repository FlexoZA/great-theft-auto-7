-- The Bragium Pit's mine (borderline.lua's `pit`), drawn into the map's
-- canvas by render_borderline.lua, and what other maps borrow from it: the
-- terraces' walls (a rock face dropping to the level below, where the map
-- says which way it faces), the haul ramps between them, the conveyors,
-- the haul trucks, the Bragium crystals, boulders, the pads, the shafts.
-- Each is a `DRAW[kind](s)` for a thing of `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Mine = {}

local INK, C = Kit.INK, Kit.C
local color, hash, lengthwise = Kit.color, Kit.hash, Kit.lengthwise
local box, hazard = Kit.box, Kit.hazard

local DRAW = {}
Mine.DRAW = DRAW

Mine.FACE = 44 -- px a terrace's rock face reaches out over the level below it

--- A rock face dropping `FACE` px from an edge `len` px long, facing `face`
--- ("n", "s", "e" or "w": the way down), (x, y) the edge's west or north
--- end (where it starts along it), on the edge: bands of rock going
--- darker as they go down, the strata across it, scree heaped at its foot.
--- `seed` picks its own scree.
function Mine.face(x, y, len, face, seed)
  love.graphics.push()
  love.graphics.translate(x, y)
  if face == "n" then
    love.graphics.rotate(math.pi)
  elseif face == "e" then
    love.graphics.rotate(-math.pi / 2)
  elseif face == "w" then
    love.graphics.rotate(math.pi / 2)
  end
  -- Drawn facing south: along x from 0 (or -len, turned), down y from 0.
  local x0 = (face == "n" or face == "e") and -len or 0
  local F = Mine.FACE
  for i, k in ipairs({ 0.85, 0.7, 0.55 }) do
    love.graphics.setColor(C.rock[1] * k, C.rock[2] * k, C.rock[3] * k)
    love.graphics.rectangle("fill", x0, (i - 1) * F / 3, len, F / 3 + 1)
  end
  color(C.rockLight, 0.35) -- the strata
  for i = 1, 3 do
    love.graphics.rectangle("fill", x0, F * (i - 0.6) / 3.2, len, 2)
  end
  color(INK, 0.3) -- cracks down it
  for a = x0 + 18, x0 + len - 10, 46 do
    local h = hash(seed + a * 0.13)
    love.graphics.rectangle("fill", a + h * 20, 2, 2, F * (0.4 + 0.5 * h))
  end
  for a = x0 + 8, x0 + len - 8, 22 do -- the scree at its foot
    local h = hash(seed * 1.7 + a * 0.31)
    local r = 5 + 6 * h
    color(C.rock)
    love.graphics.ellipse("fill", a + h * 10, F + r * 0.2, r * 1.3, r * 0.7, 8)
    color(C.rockLight, 0.7)
    love.graphics.ellipse("fill", a + h * 10 - r * 0.3, F - r * 0.1, r * 0.6, r * 0.3, 8)
  end
  love.graphics.pop()
end

--- A terrace's wall: the berm along its top edge (rocks piled as a safety
--- bank), and, where it says which way is down (`face`), the rock face
--- dropping from it to the level below. Without `face` (a step indoors),
--- a plain wall.
function DRAW.ledge(s)
  if not s.face then
    box(s.x, s.y, s.w, s.h, C.rock)
    return
  end
  local h = hash(s.x * 0.37 + s.y * 0.11)
  if s.face == "s" then
    Mine.face(s.x, s.y + s.h, s.w, "s", h * 100)
  elseif s.face == "n" then
    Mine.face(s.x, s.y, s.w, "n", h * 100)
  elseif s.face == "e" then
    Mine.face(s.x + s.w, s.y, s.h, "e", h * 100)
  else
    Mine.face(s.x, s.y, s.h, "w", h * 100)
  end
  box(s.x, s.y, s.w, s.h, C.rockLight)
  local along = s.w >= s.h
  for a = 8, (along and s.w or s.h) - 8, 18 do -- the berm's rocks
    local k = hash(h * 9 + a)
    local r = 4 + 4 * k
    local px = along and s.x + a or s.x + s.w / 2 + (k - 0.5) * s.w * 0.4
    local py = along and s.y + s.h / 2 + (k - 0.5) * s.h * 0.4 or s.y + a
    color(C.rock)
    love.graphics.circle("fill", px, py, r, 7)
    if k > 0.88 then
      color(C.snow, 0.9)
      love.graphics.circle("fill", px - r * 0.2, py - r * 0.3, r * 0.5, 7)
    end
  end
end

--- A haul ramp down from one level to the next: graded gravel, light at
--- the top going dark at the bottom (`down` the way down: "n", "s", "e",
--- "w"; south if not given), the haul trucks' ruts down it, a berm of
--- rocks along each side.
function DRAW.ramp(s)
  local down = s.down or "s"
  local along = down == "e" or down == "w" -- the ramp runs along x
  local len = along and s.w or s.h
  local steps = 6
  for i = 0, steps - 1 do
    local k = (down == "n" or down == "w") and (steps - 1 - i) or i
    local f = 1.05 - 0.25 * k / (steps - 1)
    love.graphics.setColor(C.gravel[1] * f, C.gravel[2] * f, C.gravel[3] * f)
    local a = len * i / steps
    if along then
      love.graphics.rectangle("fill", s.x + a, s.y, len / steps + 1, s.h)
    else
      love.graphics.rectangle("fill", s.x, s.y + a, s.w, len / steps + 1)
    end
  end
  color(INK, 0.18) -- the ruts
  for _, k in ipairs({ 0.3, 0.38, 0.62, 0.7 }) do
    if along then
      love.graphics.rectangle("fill", s.x, s.y + s.h * k, s.w, 4)
    else
      love.graphics.rectangle("fill", s.x + s.w * k, s.y, 4, s.h)
    end
  end
  for a = 6, len - 6, 16 do -- the berms
    for _, side in ipairs({ 0.06, 0.94 }) do
      local h = hash(s.x * 0.1 + s.y * 0.3 + a + side)
      color(h > 0.5 and C.rock or C.rockLight)
      if along then
        love.graphics.circle("fill", s.x + a, s.y + s.h * side, 5 + 3 * h, 7)
      else
        love.graphics.circle("fill", s.x + s.w * side, s.y + a, 5 + 3 * h, 7)
      end
    end
  end
end

--- A conveyor carrying ore (it moves: borderline/works.lua): a steel frame
--- on legs, the rollers across it under the belt, side rails, the belt
--- worn purple with Bragium dust.
function DRAW.conveyor(s)
  lengthwise(s, function(L, W)
    color(C.shadow)
    for a = -L / 2 + 20, L / 2 - 20, 90 do -- the legs' shadows, the belt up on them
      love.graphics.rectangle("fill", a + 10, -W / 2 + 10, 10, W + 6)
    end
    box(-L / 2, -W / 2, L, W, C.gunmetalLight)
    color(INK)
    love.graphics.rectangle("fill", -L / 2, -W / 2 + 4, L, W - 8)
    color(C.gunmetal)
    love.graphics.rectangle("fill", -L / 2 + 2, -W / 2 + 6, L - 4, W - 12)
    color(C.purple, 0.25) -- the dust on the belt
    love.graphics.rectangle("fill", -L / 2 + 2, -W / 2 + 10, L - 4, W - 20)
    color(INK, 0.35)
    for a = -L / 2 + 10, L / 2 - 10, 20 do -- the rollers showing at the belt's edge
      love.graphics.rectangle("fill", a, -W / 2 + 4, 6, 3)
      love.graphics.rectangle("fill", a, W / 2 - 7, 6, 3)
    end
    color(C.yellow)
    for a = -L / 2 + 40, L / 2 - 40, 180 do -- guards over the drives
      love.graphics.rectangle("fill", a, -W / 2 - 2, 26, 6)
    end
  end)
end

--- A haul truck, parked: four huge tyres, a yellow body, the dump bed
--- ribbed and heaped with purple ore, the cab up on one side at the front
--- with a ladder up to it, its exhaust stacks.
function DRAW.truck(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    color(INK) -- the tyres, treaded
    for _, x in ipairs({ -L / 2 + 8, L / 2 - 52 }) do
      for _, y in ipairs({ -W / 2 - 10, W / 2 - 14 }) do
        love.graphics.rectangle("fill", x, y, 44, 24, 6)
        color(C.gunmetal)
        for t = x + 4, x + 40, 8 do
          love.graphics.rectangle("fill", t, y + 2, 3, 20)
        end
        color(INK)
      end
    end
    box(-L / 2, -W / 2, L, W, C.yellow)
    local bx, bw = -L / 2 + 6, L * 0.68 -- the bed
    box(bx, -W / 2 + 6, bw, W - 12, C.yellowDark)
    color(INK, 0.2)
    for a = bx + 14, bx + bw - 8, 18 do
      love.graphics.rectangle("fill", a, -W / 2 + 6, 3, W - 12)
    end
    for i = 0, 6 do -- the ore heaped in it
      local k = hash(h * 7 + i)
      local r = W * (0.16 + 0.1 * k)
      color(C.purple)
      love.graphics.circle("fill", bx + bw * (0.15 + 0.7 * hash(h + i * 1.3)), (k - 0.5) * W * 0.4, r, 6)
      color(C.purpleLight, 0.7)
      love.graphics.circle("fill", bx + bw * (0.15 + 0.7 * hash(h + i * 1.3)) - r * 0.3, (k - 0.5) * W * 0.4 - r * 0.3,
        r * 0.35, 5)
    end
    local cx = L / 2 - 46 -- the cab, up on the left at the front
    box(cx, -W / 2 + 4, 38, W * 0.45, C.gunmetal)
    color(C.window)
    love.graphics.rectangle("fill", cx + 26, -W / 2 + 8, 8, W * 0.45 - 8)
    color(C.gunmetalLight) -- the ladder up the front
    love.graphics.rectangle("fill", L / 2 - 4, -W / 2 + 8, 6, W - 16)
    color(INK)
    for a = -W / 2 + 12, W / 2 - 12, 7 do
      love.graphics.rectangle("fill", L / 2 - 4, a, 6, 2)
    end
    for _, y in ipairs({ W / 2 - 18, W / 2 - 10 }) do -- the exhaust stacks
      love.graphics.circle("fill", cx + 8, y, 4, 8)
    end
  end)
end

--- A cluster of Bragium crystal: a glow on the ground round it, then
--- shards growing out of it every which way, each a long faceted prism,
--- its lit face pale, its shaded face deep purple.
function DRAW.crystal(s)
  local h = hash(s.seed or s.x * 0.7 + s.y)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(C.purple, 0.25)
  love.graphics.circle("fill", cx, cy, r * 1.25, 18)
  color(C.purple, 0.35)
  love.graphics.circle("fill", cx, cy, r * 0.9, 16)
  local n = 4 + math.floor(h * 3)
  for i = 1, n do
    local a = h * 6.3 + i * (2 * math.pi / n) + (hash(h + i) - 0.5) * 0.6
    local len = r * (0.95 + 0.45 * hash(h * 3 + i))
    local wd = r * (0.2 + 0.12 * hash(h * 5 + i))
    local ca, sa = math.cos(a), math.sin(a)
    local tx, ty = cx + ca * len, cy + sa * len
    local lx, ly = -sa * wd, ca * wd
    local bx, by = cx + ca * r * 0.1, cy + sa * r * 0.1
    color(INK)
    love.graphics.setLineWidth(4)
    love.graphics.polygon("line", bx + lx, by + ly, tx - ca * wd + lx * 0.6, ty - sa * wd + ly * 0.6, tx, ty,
      tx - ca * wd - lx * 0.6, ty - sa * wd - ly * 0.6, bx - lx, by - ly)
    love.graphics.setLineWidth(1)
    color(C.purple)
    love.graphics.polygon("fill", bx + lx, by + ly, tx - ca * wd + lx * 0.6, ty - sa * wd + ly * 0.6, tx, ty,
      tx - ca * wd - lx * 0.6, ty - sa * wd - ly * 0.6, bx - lx, by - ly)
    color(C.purpleLight) -- the lit face, up and to the left
    local side = (lx + ly < 0) and 1 or -1
    love.graphics.polygon("fill", bx, by, tx - ca * wd + side * lx * 0.6, ty - sa * wd + side * ly * 0.6, tx, ty)
  end
  color(C.white, 0.8) -- a glint at its heart
  love.graphics.circle("fill", cx - r * 0.1, cy - r * 0.1, r * 0.12, 8)
end

--- A boulder: a lumpy rock, its facets lit from up and to the left, a
--- crack across it, snow on top.
function DRAW.rock(s)
  local h = hash(s.seed or s.x * 0.3 + s.y * 0.7)
  local cx, cy, rx, ry = s.x + s.w / 2, s.y + s.h * 0.45, s.w / 2, s.h * 0.42
  local pts = {}
  for k = 0, 7 do
    local a = k * math.pi / 4 + h
    local rr = 0.8 + 0.25 * hash(h * 11 + k)
    pts[#pts + 1] = cx + math.cos(a) * rx * rr
    pts[#pts + 1] = cy + math.sin(a) * ry * rr
  end
  color(INK)
  love.graphics.setLineWidth(5)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
  color(C.rock)
  love.graphics.polygon("fill", pts)
  color(C.rockLight) -- the lit facets
  love.graphics.polygon("fill", pts[9], pts[10], pts[11], pts[12], pts[13], pts[14], cx, cy)
  love.graphics.polygon("fill", pts[11], pts[12], pts[13], pts[14], pts[15], pts[16], cx, cy)
  color(INK, 0.4)
  love.graphics.setLineWidth(2)
  love.graphics.line(cx - rx * 0.3, cy + ry * 0.4, cx, cy, cx + rx * 0.2, cy - ry * 0.3)
  love.graphics.setLineWidth(1)
  color(C.snow) -- snow on top
  love.graphics.ellipse("fill", cx - rx * 0.15, cy - ry * 0.45, rx * 0.45, ry * 0.25, 12)
end
DRAW.boulder = DRAW.rock

--- A landing pad: hazard stripes round its rim, steel plates bolted down
--- inside, Hyperbole's logo in the middle.
function DRAW.pad(s)
  local cx, cy, r = s.x + s.w / 2, s.y + s.h / 2, s.w / 2
  color(INK)
  love.graphics.circle("fill", cx, cy, r + Kit.LINE, 40)
  for i = 0, 15 do
    color(i % 2 == 0 and C.yellow or INK)
    love.graphics.arc("fill", cx, cy, r, i * math.pi / 8, (i + 1) * math.pi / 8)
  end
  color(C.steel)
  love.graphics.circle("fill", cx, cy, r * 0.8, 40)
  color(INK, 0.25) -- the plates' seams
  for _, a in ipairs({ 0, math.pi / 2 }) do
    love.graphics.setLineWidth(3)
    love.graphics.line(cx - math.cos(a) * r * 0.8, cy - math.sin(a) * r * 0.8, cx + math.cos(a) * r * 0.8,
      cy + math.sin(a) * r * 0.8)
  end
  love.graphics.setLineWidth(1)
  color(C.gunmetalLight) -- the bolts round it
  for i = 0, 23 do
    local a = i * math.pi / 12
    love.graphics.circle("fill", cx + math.cos(a) * r * 0.72, cy + math.sin(a) * r * 0.72, 3, 6)
  end
  color(INK, 0.35) -- scorched where things come down
  love.graphics.circle("fill", cx, cy, r * 0.45, 24)
  local hr = r * 0.28 -- the logo
  local pts = {}
  for i = 0, 5 do
    local a = math.pi / 6 + i * math.pi / 3
    pts[#pts + 1] = cx + math.cos(a) * hr
    pts[#pts + 1] = cy + math.sin(a) * hr
  end
  color(C.yellow, 0.85)
  love.graphics.polygon("fill", pts)
  color(INK)
  love.graphics.rectangle("fill", cx - hr * 0.42, cy - hr * 0.5, hr * 0.22, hr)
  love.graphics.rectangle("fill", cx + hr * 0.2, cy - hr * 0.5, hr * 0.22, hr)
  love.graphics.rectangle("fill", cx - hr * 0.25, cy - hr * 0.1, hr * 0.5, hr * 0.2)
end

--- A mine shaft: a square of black going straight down, a grating over
--- part of it, hazard striped round its collar, a fence of posts and
--- chain round it (the headframe over it is works.lua's).
function DRAW.shaft(s)
  for _, side in ipairs({ { s.x - 14, s.y - 14, s.w + 28, 4 }, { s.x - 14, s.y + s.h + 10, s.w + 28, 4 },
    { s.x - 14, s.y - 14, 4, s.h + 28 }, { s.x + s.w + 10, s.y - 14, 4, s.h + 28 } }) do -- the fence
    color(C.gunmetalLight)
    love.graphics.rectangle("fill", side[1], side[2], side[3], side[4])
  end
  for _, p in ipairs({ { s.x - 16, s.y - 16 }, { s.x + s.w + 8, s.y - 16 }, { s.x - 16, s.y + s.h + 8 },
    { s.x + s.w + 8, s.y + s.h + 8 } }) do
    box(p[1], p[2], 8, 8, C.yellow)
  end
  box(s.x, s.y, s.w, s.h, C.gunmetal)
  color(INK)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - 32, s.h - 32)
  color(C.gunmetalLight)
  for x = s.x + 16, s.x + s.w * 0.45, 10 do -- the grating over the near half
    love.graphics.rectangle("fill", x, s.y + 16, 3, s.h - 32)
  end
  hazard(s.x, s.y, s.w, 10)
  hazard(s.x, s.y + s.h - 10, s.w, 10)
  hazard(s.x, s.y, 10, s.h)
  hazard(s.x + s.w - 10, s.y, 10, s.h)
end

return Mine
