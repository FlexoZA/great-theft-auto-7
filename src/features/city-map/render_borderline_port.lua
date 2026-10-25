-- Liar's Landing's port (borderline.lua's `landing`), drawn into the map's
-- canvas by render_borderline.lua: the containers, the freighter along the
-- quay, the dry dock and the hull in it, the quay's edge, its crane rails,
-- bollards and gantry feet, the ferry lift, and what lies about the yard
-- (frozen puddles, oil, lashing gear, a spare spreader). Each is a
-- `DRAW[kind](s)` for a thing of `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Port = {}

local INK, LINE, C = Kit.INK, Kit.LINE, Kit.C
local color, hash, lengthwise = Kit.color, Kit.hash, Kit.lengthwise
local box, blob, hazard, signFont = Kit.box, Kit.blob, Kit.hazard, Kit.signFont

local DRAW = {}
Port.DRAW = DRAW

local smallFont = nil
local function codeFont()
  smallFont = smallFont or love.graphics.newFont(13)
  return smallFont
end

--- Hyperbole's logo: a yellow hexagon with an H on it, `r` px across the
--- middle, centred on (x, y).
local function logo(x, y, r, a)
  local pts = {}
  for i = 0, 5 do
    local ang = math.pi / 6 + i * math.pi / 3
    pts[#pts + 1] = x + math.cos(ang) * r
    pts[#pts + 1] = y + math.sin(ang) * r
  end
  color(INK, a)
  love.graphics.setLineWidth(4)
  love.graphics.polygon("line", pts)
  love.graphics.setLineWidth(1)
  color(C.yellow, a)
  love.graphics.polygon("fill", pts)
  color(INK, a)
  love.graphics.rectangle("fill", x - r * 0.42, y - r * 0.5, r * 0.22, r)
  love.graphics.rectangle("fill", x + r * 0.2, y - r * 0.5, r * 0.22, r)
  love.graphics.rectangle("fill", x - r * 0.25, y - r * 0.1, r * 0.5, r * 0.2)
end

-- The containers ------------------------------------------------------------

-- The colours one may be painted, past the first four (C.containers, which
-- the minimap shows): Hyperbole's own yellow ones and old grey ones.
local PAINT = { C.containers[1], C.containers[2], C.containers[3], C.containers[4], C.yellow, { 0.62, 0.64, 0.66 } }

--- One shipping container from above, `L` long down x and `W` across,
--- centred on (x, y): a corrugated roof inside its frame, a casting at each
--- corner, its doors at one end with the locking bars across, rust run from
--- the seams, maybe snow lying on it and a stencil. `h` picks its own way.
local function container(x, y, L, W, fill, h, high)
  local x0, y0 = x - L / 2, y - W / 2
  local k = high and 1.1 or 1 -- the top of a stack, nearer the light
  box(x0, y0, L, W, { fill[1] * 0.72, fill[2] * 0.72, fill[3] * 0.72 })
  love.graphics.setColor(math.min(1, fill[1] * k), math.min(1, fill[2] * k), math.min(1, fill[3] * k))
  love.graphics.rectangle("fill", x0 + 4, y0 + 4, L - 8, W - 8)
  color(INK, 0.2) -- the corrugations, across it
  for a = x0 + 12, x0 + L - 12, 9 do
    love.graphics.rectangle("fill", a, y0 + 5, 3, W - 10)
  end
  color(C.white, 0.12)
  for a = x0 + 16, x0 + L - 12, 9 do
    love.graphics.rectangle("fill", a, y0 + 5, 2, W - 10)
  end
  -- The doors at one end, the locking bars across them.
  local doorX = hash(h * 3.1) < 0.5 and x0 + 4 or x0 + L - 14
  color(INK, 0.45)
  love.graphics.rectangle("fill", doorX, y0 + 4, 10, W - 8)
  color(C.gunmetalLight)
  for i = 1, 4 do
    love.graphics.rectangle("fill", doorX + 2, y0 + 4 + (W - 8) * i / 5 - 1, 6, 2)
  end
  -- Rust run from the seams.
  for i = 1, 4 do
    local rx = x0 + 14 + (L - 30) * hash(h * 5.3 + i)
    color(C.rust, 0.3 + 0.25 * hash(h * 2.2 + i))
    love.graphics.rectangle("fill", rx, y0 + 5, 3 + 4 * hash(h + i), (W - 10) * (0.3 + 0.6 * hash(h * 8.1 + i)))
  end
  -- A stencil: Hyperbole's logo, or the box's number down its length.
  local mark = hash(h * 4.7)
  if mark < 0.3 and L > 120 then
    logo(x0 + L * (0.3 + 0.4 * hash(h * 6.6)), y, W * 0.3, 0.9)
  elseif mark < 0.65 and L > 160 then
    love.graphics.setFont(codeFont())
    color(C.white, 0.75)
    love.graphics.print(("HYPR %05d"):format(math.floor(hash(h * 9.9) * 99999)), x0 + 22, y - 7)
  end
  -- Snow lying on the roof.
  local snow = hash(h * 7.3)
  if snow < 0.55 then
    local sx = x0 + 20 + (L - 40) * hash(h * 1.9)
    for i = 0, 2 do
      local r = W * (0.18 + 0.12 * hash(h * 3.7 + i))
      local px = math.max(x0 + r + 4, math.min(x0 + L - r - 4, sx + (i - 1) * r * 1.4))
      color(C.snowShade)
      love.graphics.ellipse("fill", px, y + 2, r * 1.1, math.min(r * 0.7, W / 2 - 6), 14)
      color(C.snow)
      love.graphics.ellipse("fill", px - 2, y - 1, r * 0.9, math.min(r * 0.55, W / 2 - 8), 14)
    end
  end
  -- The corner castings.
  for _, cx in ipairs({ x0 + 1, x0 + L - 10 }) do
    for _, cy in ipairs({ y0 + 1, y0 + W - 10 }) do
      color(C.gunmetal)
      love.graphics.rectangle("fill", cx, cy, 9, 9)
      color(INK)
      love.graphics.rectangle("fill", cx + 3, cy + 3, 3, 3)
    end
  end
end

--- A stack of shipping containers: the footprint holds two side by side
--- the long way, each its own colour, some of them two high (a deeper
--- shadow off them, a lighter roof). The first is the colour the minimap
--- shows (`tint`).
function DRAW.container(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    local n = math.max(1, math.floor(W / 56 + 0.5))
    local gap = 6
    local w = (W - gap * (n - 1)) / n
    for i = 1, n do
      local hi = hash(h * 13.1 + i * 7.7)
      local high = hi < 0.4
      local y = -W / 2 + (i - 1) * (w + gap) + w / 2
      if high then -- a box on top throws a longer shadow
        color(C.shadow)
        love.graphics.rectangle("fill", -L / 2 + 14, y - w / 2 + 14, L, w)
      end
      local fill = i == 1 and C.containers[s.tint or 1] or PAINT[1 + math.floor(hash(hi * 31) * #PAINT)]
      container(0, y, L, w, fill, hi * 100 + i, high)
    end
  end)
end

-- The freighter -------------------------------------------------------------

--- The freighter moored along the quay, most of it past the map's top, its
--- bow at the east: red hull, the deck inside its railing, the bridge and
--- its funnel at the stern with lifeboats either side, then bay after bay
--- of containers stacked on the hatch covers (a hold left open here and
--- there, its stack deep below), and the forecastle with the anchor
--- windlass at the bow.
function DRAW.ship(s)
  local nose = math.min(s.h * 0.9, s.w * 0.15)
  local pts = { s.x, s.y, s.x + s.w - nose, s.y, s.x + s.w, s.y + s.h / 2, s.x + s.w - nose, s.y + s.h, s.x,
    s.y + s.h }
  color(INK)
  love.graphics.polygon("fill", pts[1] - LINE, pts[2] - LINE, pts[3], pts[4] - LINE, pts[5] + LINE, pts[6], pts[7],
    pts[8] + LINE, pts[9] - LINE, pts[10] + LINE)
  color(C.hull)
  love.graphics.polygon("fill", pts)
  color(C.hullDark, 0.6) -- the hull's flare in shade along the quay side
  love.graphics.rectangle("fill", s.x, s.y + s.h - 10, s.w - nose, 10)
  -- The deck inside the bulwark, and its railing.
  local dx0, dy0, dx1, dy1 = s.x + 14, s.y + 14, s.x + s.w - nose * 0.4, s.y + s.h - 14
  color(C.deck)
  love.graphics.polygon("fill", dx0, dy0, s.x + s.w - nose - 6, dy0, dx1, s.y + s.h / 2, s.x + s.w - nose - 6, dy1,
    dx0, dy1)
  color(C.white, 0.5)
  love.graphics.setLineWidth(2)
  love.graphics.line(dx0 + 4, dy0 + 4, s.x + s.w - nose - 8, dy0 + 4, dx1 - 8, s.y + s.h / 2,
    s.x + s.w - nose - 8, dy1 - 4, dx0 + 4, dy1 - 4)
  love.graphics.setLineWidth(1)
  -- The stern: the bridge across the beam, the funnel, a lifeboat each side.
  local bx = s.x + 40
  box(bx, s.y + 22, 120, s.h - 44, C.paintWhite)
  color(C.window)
  for _, wy in ipairs({ s.y + 22, s.y + s.h - 30 }) do -- the bridge wings' windows
    love.graphics.rectangle("fill", bx + 92, wy, 22, 8)
  end
  love.graphics.rectangle("fill", bx + 108, s.y + 30, 8, s.h - 60)
  color(INK, 0.2)
  love.graphics.rectangle("fill", bx + 8, s.y + 30, 80, 4)
  love.graphics.rectangle("fill", bx + 8, s.y + s.h - 34, 80, 4)
  box(bx + 20, s.y + s.h / 2 - 30, 50, 60, C.yellow) -- the funnel
  color(INK)
  love.graphics.rectangle("fill", bx + 26, s.y + s.h / 2 - 24, 38, 48)
  logo(bx + 45, s.y + s.h / 2, 16)
  for _, ly in ipairs({ s.y + 6, s.y + s.h - 24 }) do
    blob(bx + 10, ly, 70, 18, C.cone)
    color(C.white, 0.6)
    love.graphics.rectangle("fill", bx + 24, ly + 7, 42, 4)
  end
  -- Bay after bay of containers on the hatch covers, the long way.
  local base = s.x + s.w - nose -- where the bow starts
  local first, last = bx + 150, base - 140
  local rows = math.max(3, math.floor((s.h - 60) / 34))
  local cw = (s.h - 60) / rows
  for x = first, last, 140 do
    local hb = hash(x * 0.37 + 2.1)
    color(INK)
    love.graphics.rectangle("fill", x - 4, s.y + 26, 128, s.h - 52)
    if hb < 0.18 then -- a hold open, its stack deep in it
      color(C.pitDeep)
      love.graphics.rectangle("fill", x, s.y + 30, 120, s.h - 60)
      for r = 0, rows - 1 do
        local fill = PAINT[1 + math.floor(hash(x + r * 3.3) * 4)]
        love.graphics.setColor(fill[1] * 0.35, fill[2] * 0.35, fill[3] * 0.35)
        love.graphics.rectangle("fill", x + 8, s.y + 30 + r * cw + 3, 104, cw - 6)
      end
    else
      color(C.gunmetalLight) -- the hatch cover, its ribs
      love.graphics.rectangle("fill", x, s.y + 30, 120, s.h - 60)
      color(INK, 0.25)
      for a = x + 10, x + 112, 14 do
        love.graphics.rectangle("fill", a, s.y + 30, 3, s.h - 60)
      end
      local stacked = math.floor(rows * (0.4 + 0.6 * hash(x * 1.3 + 5)))
      local from = math.floor(hash(x * 2.9 + 1) * (rows - stacked + 1))
      for r = from, from + stacked - 1 do
        local fill = PAINT[1 + math.floor(hash(x * 0.7 + r * 5.1) * #PAINT)]
        container(x + 60, s.y + 30 + r * cw + cw / 2, 116, cw - 2, fill, x + r * 11, hash(x + r) < 0.5)
      end
    end
  end
  -- The forecastle: the windlass and its chains running out to the hawse pipes.
  local fx = base + nose * 0.22
  for _, side in ipairs({ -1, 1 }) do
    local cy = s.y + s.h / 2 + side * s.h * 0.17
    color(INK)
    love.graphics.setLineWidth(4)
    love.graphics.line(fx, cy, base + nose * 0.55, s.y + s.h / 2 + side * s.h * 0.17)
    love.graphics.setLineWidth(1)
    blob(fx - 14, cy - 14, 28, 28, C.gunmetal)
    color(C.yellow)
    love.graphics.circle("fill", fx, cy, 5, 8)
  end
  box(base + nose * 0.05, s.y + s.h / 2 - 6, 30, 12, C.paintWhite) -- the foremast's foot
end

-- The dry dock --------------------------------------------------------------

--- A ship's hull from above, `s` its bounds, its bow at the right: the
--- sides in `fill`, the deck in `dark`. Returns how long the bow is.
local function hullShape(s, fill, dark)
  local nose = math.min(s.h * 0.9, s.w * 0.15)
  local pts = { s.x, s.y, s.x + s.w - nose, s.y, s.x + s.w, s.y + s.h / 2, s.x + s.w - nose, s.y + s.h, s.x,
    s.y + s.h }
  color(INK)
  love.graphics.polygon("fill", pts[1] - LINE, pts[2] - LINE, pts[3], pts[4] - LINE, pts[5] + LINE, pts[6], pts[7],
    pts[8] + LINE, pts[9] - LINE, pts[10] + LINE)
  color(fill)
  love.graphics.polygon("fill", pts)
  color(dark)
  love.graphics.rectangle("fill", s.x + 16, s.y + 16, s.w - nose - 24, s.h - 32)
  return nose
end

--- The dry dock: a deep basin, its stepped walls going down with ladders
--- down them, frozen water at the bottom, and the old hull up on its keel
--- blocks, shored to the walls with struts: scaffolding down one side of
--- it, its plates patched with red primer here and there, the propeller
--- and rudder off its stern. The welders working on it are works.lua's
--- (`map.welders`).
function DRAW.drydock(s)
  local h = hash(s.seed or 1)
  box(s.x, s.y, s.w, s.h, C.pitWall)
  for i = 1, 3 do -- the altars, stepping down
    local inset = i * 18
    color(i == 3 and C.dockWater or C.pitDeep, i == 3 and 1 or 0.5)
    love.graphics.rectangle("fill", s.x + inset, s.y + inset, s.w - 2 * inset, s.h - 2 * inset)
    color(C.white, 0.12)
    love.graphics.rectangle("fill", s.x + inset, s.y + inset, s.w - 2 * inset, 2)
  end
  color(C.white, 0.25) -- cracks in the ice at the bottom
  love.graphics.setLineWidth(2)
  for i = 1, 6 do
    local cx, cy = s.x + 60 + (s.w - 120) * hash(h + i), s.y + 70 + (s.h - 140) * hash(h * 3 + i)
    love.graphics.line(cx, cy, cx + 30 * (hash(h * 5 + i) - 0.5), cy + 40, cx + 50 * (hash(h * 7 + i) - 0.5), cy + 80)
  end
  love.graphics.setLineWidth(1)
  for _, ly in ipairs({ s.y + s.h * 0.2, s.y + s.h * 0.55, s.y + s.h * 0.85 }) do -- ladders down the walls
    for _, lx in ipairs({ s.x + 8, s.x + s.w - 52 }) do
      color(C.gunmetalLight)
      love.graphics.rectangle("fill", lx, ly, 44, 4)
      love.graphics.rectangle("fill", lx, ly + 20, 44, 4)
      for a = lx + 4, lx + 40, 8 do
        love.graphics.rectangle("fill", a, ly, 3, 24)
      end
    end
  end
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  local hw, hl = s.w * 0.55, s.h * 0.82
  color(INK) -- the keel blocks, showing past either end
  for y = cy - hl / 2 - 30, cy + hl / 2 + 10, 36 do
    love.graphics.rectangle("fill", cx - 14, y, 28, 20)
  end
  color(C.gunmetalLight) -- the shores, wall to hull
  love.graphics.setLineWidth(6)
  for y = cy - hl / 2 + 80, cy + hl / 2 - 60, 110 do
    love.graphics.line(s.x + 54, y, cx - hw / 2, y + 20)
    love.graphics.line(s.x + s.w - 54, y, cx + hw / 2, y + 20)
  end
  love.graphics.setLineWidth(1)
  -- The propeller and rudder off the stern (south).
  color(INK)
  love.graphics.rectangle("fill", cx - 5, cy + hl / 2 - 6, 10, 46)
  blob(cx - 26, cy + hl / 2 + 12, 52, 18, C.gold)
  -- The hull, bow north.
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.rotate(-math.pi / 2)
  local nose = hullShape({ x = -hl / 2, y = -hw / 2, w = hl, h = hw }, C.rust, C.hullDark)
  for i = 1, 5 do -- patches of fresh red primer on the plates
    local px = -hl / 2 + 30 + (hl - nose - 100) * hash(h * 11 + i)
    color(C.hull, 0.85)
    local py = hash(h * 13 + i) < 0.5 and -hw / 2 + 2 or hw / 2 - 14
    love.graphics.rectangle("fill", px, py, 40 + 50 * hash(i + h), 12)
  end
  color(INK, 0.3) -- the plating's seams
  for a = -hl / 2 + 60, hl / 2 - nose, 60 do
    love.graphics.rectangle("fill", a, -hw / 2 + 16, 3, hw - 32)
  end
  for a = -hl / 2 + 140, hl / 2 - nose - 120, 170 do -- the holds, their hatches off
    box(a, -hw / 2 + 34, 110, hw - 68, C.pitDeep)
    color(C.hullDark)
    for k = a + 12, a + 100, 22 do -- the frames down in the hold
      love.graphics.rectangle("fill", k, -hw / 2 + 34, 4, hw - 68)
    end
  end
  for i = 1, 4 do -- deck plates taken up, the beams under them showing
    local px = -hl / 2 + 120 + (hl - nose - 240) * hash(h * 17 + i)
    color(INK, 0.55)
    love.graphics.rectangle("fill", px, -hw / 2 + 18, 30, 14)
  end
  box(-hl / 2 + 24, -hw * 0.3, 70, hw * 0.6, C.gunmetalLight) -- the bridge, stripped
  color(C.window)
  love.graphics.rectangle("fill", -hl / 2 + 82, -hw * 0.25, 6, hw * 0.5)
  love.graphics.pop()
  -- Scaffolding down the hull's east side: planks on poles.
  local sx = cx + hw / 2 + 4
  color(INK)
  love.graphics.rectangle("fill", sx, cy - hl * 0.35, 18, hl * 0.6)
  color(C.wood)
  love.graphics.rectangle("fill", sx + 2, cy - hl * 0.35 + 2, 14, hl * 0.6 - 4)
  color(C.woodDark)
  for y = cy - hl * 0.35 + 30, cy + hl * 0.25, 30 do
    love.graphics.rectangle("fill", sx + 2, y, 14, 2)
  end
  color(C.gunmetalLight)
  for y = cy - hl * 0.35, cy + hl * 0.25, 60 do
    love.graphics.circle("fill", sx + 9, y, 4, 8)
  end
  hazard(s.x, s.y, s.w, 12)
  hazard(s.x, s.y + s.h - 12, s.w, 12)
  hazard(s.x, s.y, 12, s.h)
  hazard(s.x + s.w - 12, s.y, 12, s.h)
end

-- The quay ------------------------------------------------------------------

--- The quay's edge over the water: a concrete coping painted yellow along
--- its lip, black rubber fenders hung off it every few metres.
function DRAW.quayedge(s)
  color(C.concrete)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  color(C.yellow)
  love.graphics.rectangle("fill", s.x, s.y + s.h - 6, s.w, 6)
  for x = s.x + 60, s.x + s.w - 60, 190 do
    color(INK)
    love.graphics.rectangle("fill", x - 2, s.y - 16, 40, 20)
    color(C.gunmetal)
    love.graphics.rectangle("fill", x + 2, s.y - 13, 32, 12)
  end
end

--- A crane rail down the quay: a groove in the concrete, the rail in it,
--- clipped down every so often.
function DRAW.craneRail(s)
  color(C.concreteDark)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  local my = s.y + s.h / 2
  color(INK)
  love.graphics.rectangle("fill", s.x, my - 4, s.w, 8)
  color(C.steel)
  love.graphics.rectangle("fill", s.x, my - 2, s.w, 3)
  color(C.gunmetalLight)
  for x = s.x + 20, s.x + s.w - 10, 48 do
    love.graphics.rectangle("fill", x, s.y + 2, 6, s.h - 4)
  end
end

--- A bollard on the quay's edge: a mushroom head on its base, a mooring
--- line off it to the freighter (`rope`: how far north it runs, world y).
function DRAW.bollard(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  if s.rope then -- the line, sagging out to the ship's side
    local dir = hash(cx * 0.013) < 0.5 and -1 or 1
    local tx, ty = cx + dir * (60 + 50 * hash(cx)), s.rope
    for pass = 1, 2 do
      color(pass == 1 and INK or C.wood)
      love.graphics.setLineWidth(pass == 1 and 7 or 3)
      love.graphics.line(cx, cy, cx + (tx - cx) * 0.5 + dir * 4, cy + (ty - cy) * 0.5 + 3, tx, ty)
    end
    love.graphics.setLineWidth(1)
  end
  blob(s.x - 6, s.y - 6, s.w + 12, s.h + 12, C.gunmetal)
  blob(s.x, s.y, s.w, s.h, C.yellow)
  color(INK, 0.5)
  love.graphics.circle("fill", cx, cy, s.w * 0.18, 8)
  if s.rope then -- the line's eye over the head
    color(C.wood)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", cx, cy, s.w * 0.36, 10)
    love.graphics.setLineWidth(1)
  end
end

--- A gantry crane's foot on its rail (the crane is overhead: works.lua):
--- the bogie, its wheels along the rail, buffers at each end, and the leg's
--- base plate on it, hazard striped.
function DRAW.foot(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  box(cx - 34, cy - 9, 68, 18, C.gunmetal)
  color(INK)
  for _, wx in ipairs({ -26, -14, 8, 20 }) do
    love.graphics.rectangle("fill", cx + wx, cy - 7, 6, 14)
  end
  color(C.yellow)
  love.graphics.rectangle("fill", cx - 38, cy - 5, 4, 10)
  love.graphics.rectangle("fill", cx + 34, cy - 5, 4, 10)
  box(s.x, s.y, s.w, s.h, C.yellow)
  color(INK)
  love.graphics.polygon("fill", s.x, s.y + s.h * 0.5, s.x + s.w * 0.5, s.y, s.x + s.w * 0.75, s.y,
    s.x, s.y + s.h * 0.75)
  love.graphics.polygon("fill", s.x + s.w * 0.5, s.y + s.h, s.x + s.w, s.y + s.h * 0.5, s.x + s.w, s.y + s.h * 0.75,
    s.x + s.w * 0.75, s.y + s.h)
  love.graphics.circle("fill", cx, cy, s.w * 0.14, 8)
end

--- The ferry lift: a steel deck in tread plate, hazard bands at both ends,
--- railings down its sides, the hinges along its north end where it meets
--- the ferry, chevrons painted pointing out to it, and a control pedestal
--- in one corner.
function DRAW.lift(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  color(INK, 0.18) -- the tread plate
  for y = s.y + 8, s.y + s.h - 8, 12 do
    local off = (math.floor((y - s.y) / 12) % 2) * 9
    for x = s.x + 8 + off, s.x + s.w - 12, 18 do
      love.graphics.rectangle("fill", x, y, 7, 3)
    end
  end
  color(INK, 0.3) -- the deck's plates
  love.graphics.rectangle("fill", s.x + s.w / 3, s.y, 3, s.h)
  love.graphics.rectangle("fill", s.x + s.w * 2 / 3, s.y, 3, s.h)
  hazard(s.x, s.y + 12, s.w, 16)
  hazard(s.x, s.y + s.h - 16, s.w, 16)
  color(INK) -- the hinges where it meets the ferry
  for x = s.x + 20, s.x + s.w - 30, 52 do
    love.graphics.rectangle("fill", x, s.y - 4, 26, 16)
    color(C.gunmetalLight)
    love.graphics.rectangle("fill", x + 3, s.y - 1, 20, 10)
    color(INK)
  end
  for _, rx in ipairs({ s.x + 4, s.x + s.w - 12 }) do -- the railings
    color(INK)
    love.graphics.rectangle("fill", rx - 1, s.y + 28, 10, s.h - 44)
    color(C.yellow)
    love.graphics.rectangle("fill", rx + 1, s.y + 28, 6, s.h - 44)
    color(INK)
    for y = s.y + 34, s.y + s.h - 20, 30 do
      love.graphics.rectangle("fill", rx, y, 8, 5)
    end
  end
  color(C.yellow, 0.85) -- chevrons out to the ferry
  local mx = s.x + s.w / 2
  for k = 0, 2 do
    local y = s.y + s.h * 0.62 - k * 30
    love.graphics.polygon("fill", mx - 44, y + 18, mx, y - 6, mx + 44, y + 18, mx + 44, y + 30, mx, y + 6,
      mx - 44, y + 30)
  end
  love.graphics.setFont(signFont())
  color(C.paintWhite, 0.8)
  love.graphics.printf("FERRY", s.x, s.y + s.h - 50, s.w, "center")
  box(s.x + s.w - 54, s.y + s.h - 62, 30, 24, C.gunmetal) -- the pedestal
  color(C.green)
  love.graphics.circle("fill", s.x + s.w - 46, s.y + s.h - 50, 4, 8)
  color(C.drum)
  love.graphics.circle("fill", s.x + s.w - 33, s.y + s.h - 50, 4, 8)
end

-- What lies about ------------------------------------------------------------

--- A frozen puddle: grey ice, a white rim of frost, cracks and a shine.
function DRAW.puddle(s)
  local h = hash(s.seed or 1)
  local cx, cy, rx, ry = s.x + s.w / 2, s.y + s.h / 2, s.w / 2, s.h / 2
  color(C.snowShade, 0.9)
  love.graphics.ellipse("fill", cx, cy, rx + 4, ry + 3, 20)
  love.graphics.setColor(0.58, 0.68, 0.78)
  love.graphics.ellipse("fill", cx, cy, rx, ry, 20)
  color(C.white, 0.45)
  love.graphics.ellipse("fill", cx - rx * 0.35, cy - ry * 0.35, rx * 0.35, ry * 0.18, 12)
  color(C.white, 0.35)
  love.graphics.setLineWidth(2)
  for i = 1, 3 do
    local a = h * 6 + i * 2.1
    love.graphics.line(cx, cy, cx + math.cos(a) * rx * 0.8, cy + math.sin(a) * ry * 0.8)
  end
  love.graphics.setLineWidth(1)
end

--- Oil spilt on the concrete: a dark stain, a drip or two off it.
function DRAW.stain(s)
  local h = hash(s.seed or 1)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(INK, 0.22)
  love.graphics.ellipse("fill", cx, cy, s.w / 2, s.h / 2.6, 16)
  for i = 1, 3 do
    local a = h * 5 + i * 2
    love.graphics.circle("fill", cx + math.cos(a) * s.w * 0.45, cy + math.sin(a) * s.h * 0.35,
      s.w * (0.08 + 0.1 * hash(h + i)), 10)
  end
end

--- Lashing gear dropped off a ship: a bundle of lashing rods, hooks on
--- their ends, and a bin of twistlocks beside it.
function DRAW.lashing(s)
  lengthwise(s, function(L, W)
    for i = 0, 4 do
      local y = -W / 2 + 6 + i * (W - 26) / 4
      color(INK)
      love.graphics.rectangle("fill", -L / 2, y - 3, L - 30, 6)
      color(C.steel)
      love.graphics.rectangle("fill", -L / 2 + 1, y - 1, L - 32, 2)
      color(C.yellow)
      love.graphics.rectangle("fill", -L / 2 - 4, y - 3, 6, 6)
    end
    box(L / 2 - 26, -W / 2 + 2, 24, W - 4, C.gunmetalLight) -- the twistlock bin
    color(INK)
    for i = 0, 2 do
      love.graphics.rectangle("fill", L / 2 - 20, -W / 2 + 8 + i * (W - 16) / 3, 12, 6)
    end
  end)
end

--- A spare spreader, the frame a gantry lifts a container by, lying on
--- the quay: two long beams, the cross members, a twistlock pin at each
--- corner, the hydraulics on it.
function DRAW.spreader(s)
  lengthwise(s, function(L, W)
    for _, y in ipairs({ -W / 2 + 4, W / 2 - 14 }) do
      box(-L / 2, y, L, 10, C.yellow)
    end
    for _, x in ipairs({ -L / 2 + 6, -12, L / 2 - 18 }) do
      box(x, -W / 2 + 4, 12, W - 8, C.yellowDark)
    end
    box(-30, -12, 60, 24, C.gunmetal) -- the hydraulic power pack
    color(INK)
    for _, x in ipairs({ -L / 2 - 4, L / 2 - 4 }) do
      for _, y in ipairs({ -W / 2, W / 2 - 8 }) do
        love.graphics.rectangle("fill", x, y, 8, 8)
      end
    end
  end)
end

return Port
