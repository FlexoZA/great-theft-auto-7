-- Draws the Citadel's inside (citadel.lua builds it) into the map canvas:
-- the drop first, deepest things darkest (lights, girders, pillars, the
-- pod rails, the core's glow), then the catwalks and platforms over it,
-- each with a shadow far below it, a rail along every edge over the drop,
-- the cover on the platforms and the shield of the MG emplacement.

local RenderCitadel = {}

local C = {
  void = { 0.035, 0.045, 0.06 },
  haze = { 0.10, 0.16, 0.22 },
  steel = { 0.16, 0.19, 0.23 },
  steelLight = { 0.24, 0.28, 0.33 },
  glow = { 0.40, 0.80, 1.00 },
  warm = { 1.00, 0.55, 0.20 },
  grate = { 0.27, 0.30, 0.34 },
  grateDark = { 0.19, 0.21, 0.25 },
  plate = { 0.31, 0.34, 0.38 },
  plateDark = { 0.25, 0.28, 0.31 },
  rivet = { 0.42, 0.46, 0.50 },
  rail = { 0.55, 0.60, 0.66 },
  railDark = { 0.12, 0.13, 0.15 },
  stripe = { 0.85, 0.65, 0.15 },
  crate = { 0.33, 0.37, 0.41 },
  crateDark = { 0.22, 0.25, 0.28 },
  barrier = { 0.18, 0.22, 0.27 },
  console = { 0.14, 0.17, 0.20 },
  cabinet = { 0.12, 0.14, 0.17 },
  screen = { 0.03, 0.06, 0.08 },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

local function mix(a, b, k)
  return { a[1] + (b[1] - a[1]) * k, a[2] + (b[2] - a[2]) * k, a[3] + (b[3] - a[3]) * k }
end

local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

--- Something `depth` down (0 at the catwalks, 1 lost in the dark): its colour fades into the void.
local function deep(c, depth)
  return mix(c, C.void, depth)
end

local function drawCore(b)
  -- Light welling up out of the bottom of the shaft, ring on ring.
  for i = 12, 1, -1 do
    local k = i / 12
    color(C.glow, 0.05 + (1 - k) * 0.05)
    love.graphics.circle("fill", b.x, b.y, b.r * k * 1.35, 64)
  end
  color(deep(C.steel, 0.3))
  love.graphics.setLineWidth(10)
  for _, k in ipairs({ 0.95, 0.7, 0.45 }) do
    love.graphics.circle("line", b.x, b.y, b.r * k, 64)
  end
  for a = 0, 11 do -- spokes holding the rings
    local ang = a / 12 * 2 * math.pi
    love.graphics.line(b.x + math.cos(ang) * b.r * 0.45, b.y + math.sin(ang) * b.r * 0.45,
      b.x + math.cos(ang) * b.r * 0.95, b.y + math.sin(ang) * b.r * 0.95)
  end
  love.graphics.setLineWidth(1)
  color({ 0.75, 0.95, 1 }, 0.55)
  love.graphics.circle("fill", b.x, b.y, b.r * 0.22, 48)
  color({ 1, 1, 1 }, 0.7)
  love.graphics.circle("fill", b.x, b.y, b.r * 0.1, 32)
end

local function drawGirder(b)
  local c = deep(C.steel, b.depth)
  color(c)
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(deep(C.steelLight, b.depth))
  love.graphics.setLineWidth(3)
  -- A lattice down its length.
  if b.w > b.h then
    love.graphics.rectangle("fill", b.x, b.y, b.w, 3)
    for x = b.x, b.x + b.w - b.h, b.h * 1.2 do
      love.graphics.line(x, b.y + b.h, x + b.h, b.y)
    end
  else
    love.graphics.rectangle("fill", b.x, b.y, 3, b.h)
    for y = b.y, b.y + b.h - b.w, b.w * 1.2 do
      love.graphics.line(b.x, y + b.w, b.x + b.w, y)
    end
  end
  love.graphics.setLineWidth(1)
end

local function drawPillar(b)
  color(deep(C.steel, b.depth))
  love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  color(deep(C.steelLight, b.depth))
  love.graphics.rectangle("fill", b.x, b.y, b.w, 6)
  love.graphics.rectangle("fill", b.x, b.y, 6, b.h)
  color(deep({ 0, 0, 0 }, 0.4), 0.5)
  love.graphics.rectangle("fill", b.x + b.w - 10, b.y, 10, b.h)
  -- A light or two on top.
  local n = 1 + math.floor(hash(b.seed) * 3)
  for i = 1, n do
    local warm = hash(b.seed + i * 3.1) < 0.3
    color(warm and C.warm or C.glow, 0.7 * (1 - b.depth * 0.6))
    love.graphics.circle("fill", b.x + b.w * hash(b.seed + i), b.y + b.h * hash(b.seed + i * 7.3), 4)
  end
end

local function drawRail(b)
  color(deep(C.steelLight, 0.35))
  love.graphics.setLineWidth(8)
  love.graphics.line(b.x0, b.y0, b.x1, b.y1)
  color(C.glow, 0.25)
  love.graphics.setLineWidth(2)
  love.graphics.line(b.x0, b.y0, b.x1, b.y1)
  love.graphics.setLineWidth(1)
  local ang = math.atan2(b.y1 - b.y0, b.x1 - b.x0)
  for _, k in ipairs(b.pods) do
    local x, y = b.x0 + (b.x1 - b.x0) * k, b.y0 + (b.y1 - b.y0) * k
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.rotate(ang)
    color(deep(C.crate, 0.3))
    love.graphics.rectangle("fill", -44, -26, 88, 52, 8)
    color(deep(C.steelLight, 0.2))
    love.graphics.rectangle("fill", -44, -26, 88, 8, 4)
    color(C.warm, 0.6)
    love.graphics.rectangle("fill", -30, -6, 60, 12, 4)
    love.graphics.pop()
  end
end

local function drawLight(b)
  color(b.warm and C.warm or C.glow, 0.18)
  love.graphics.circle("fill", b.x, b.y, b.r * 3)
  color(b.warm and C.warm or C.glow, 0.6)
  love.graphics.circle("fill", b.x, b.y, b.r)
end

--- The drop: everything down in it, deepest first.
local function drawDrop(map)
  color(C.void)
  love.graphics.rectangle("fill", map.left, map.top, map.w, map.h)
  -- Haze drifting in great slow patches.
  for i = 1, 40 do
    color(C.haze, 0.12)
    love.graphics.circle("fill", map.left + hash(i * 1.7) * map.w, map.top + hash(i * 9.1) * map.h,
      300 + hash(i * 4.3) * 500, 40)
  end
  local order = { "light", "girder", "pillar", "rail", "core" }
  for _, kind in ipairs(order) do
    for _, b in ipairs(map.backdrop) do
      if b.kind == kind then
        if kind == "light" then
          drawLight(b)
        elseif kind == "girder" then
          drawGirder(b)
        elseif kind == "pillar" then
          drawPillar(b)
        elseif kind == "rail" then
          drawRail(b)
        else
          drawCore(b)
        end
      end
    end
  end
end

local function walk(map, c, r)
  local col = map.tiles[c]
  return col ~= nil and col[r] == "walk"
end

--- The catwalks' and platforms' shadow, far below and off to one side.
local function drawShadows(map, T)
  color({ 0, 0, 0 }, 0.45)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if walk(map, c, r) then
        love.graphics.rectangle("fill", map.x0 + c * T + 46, map.y0 + r * T + 70, T, T)
      end
    end
  end
  -- Struts down from under each edge into the dark.
  color(deep(C.steel, 0.2))
  for _, w in ipairs(map.catwalks) do
    local step = 220
    if w.w > w.h then
      for x = w.x + 60, w.x + w.w - 60, step do
        love.graphics.polygon("fill", x, w.y + w.h, x + 18, w.y + w.h, x + 64, w.y + w.h + 70, x + 46, w.y + w.h + 70)
      end
    else
      for y = w.y + 60, w.y + w.h - 60, step do
        love.graphics.polygon("fill", w.x + w.w, y, w.x + w.w, y + 18, w.x + w.w + 46, y + 88, w.x + w.w + 46, y + 70)
      end
    end
  end
end

local function onPlatform(map, x, y)
  for _, p in ipairs(map.platforms) do
    if x >= p.x and x < p.x + p.w and y >= p.y and y < p.y + p.h then
      return p
    end
  end
  return nil
end

--- Grating on the catwalks, riveted plates on the platforms, a rail along
--- every edge over the drop.
local function drawDecks(map, T)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if walk(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if onPlatform(map, x + 1, y + 1) then
          color((c + r) % 2 == 0 and C.plate or C.plateDark)
          love.graphics.rectangle("fill", x, y, T, T)
          color(C.grateDark)
          love.graphics.rectangle("fill", x, y, T, 2)
          love.graphics.rectangle("fill", x, y, 2, T)
          color(C.rivet)
          for _, k in ipairs({ { 6, 6 }, { T - 8, 6 }, { 6, T - 8 }, { T - 8, T - 8 } }) do
            love.graphics.rectangle("fill", x + k[1], y + k[2], 3, 3)
          end
        else
          color(C.grate)
          love.graphics.rectangle("fill", x, y, T, T)
          color(C.grateDark)
          for k = 4, T - 4, 8 do
            love.graphics.rectangle("fill", x + 2, y + k, T - 4, 3)
          end
        end
      end
    end
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if walk(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        local edges = {
          { not walk(map, c, r - 1), x, y, T, 6 },
          { not walk(map, c, r + 1), x, y + T - 6, T, 6 },
          { not walk(map, c - 1, r), x, y, 6, T },
          { not walk(map, c + 1, r), x + T - 6, y, 6, T },
        }
        for _, e in ipairs(edges) do
          if e[1] then
            color(C.railDark)
            love.graphics.rectangle("fill", e[2] - 1, e[3] - 1, e[4] + 2, e[5] + 2)
            color(C.rail)
            love.graphics.rectangle("fill", e[2] + 1, e[3] + 1, e[4] - 2, e[5] - 2)
          end
        end
      end
    end
  end
end

--- Hazard stripes round the lift, and the lift up at the top.
local function drawLifts(map)
  for _, p in ipairs(map.platforms) do
    if p.kind == "lift" then
      color(C.stripe)
      love.graphics.setLineWidth(10)
      love.graphics.rectangle("line", p.x + 30, p.y + 30, p.w - 60, p.h - 60)
      love.graphics.setLineWidth(1)
    end
  end
  local x, y = map.exitX, map.exitY
  color(C.railDark)
  love.graphics.rectangle("fill", x - 110, y - 80, 220, 160, 10)
  color(C.steelLight)
  love.graphics.rectangle("fill", x - 100, y - 70, 200, 140, 8)
  color(C.glow, 0.5)
  love.graphics.rectangle("fill", x - 80, y - 50, 160, 100, 6)
  color(C.stripe)
  love.graphics.setLineWidth(6)
  love.graphics.rectangle("line", x - 100, y - 70, 200, 140, 8)
  love.graphics.setLineWidth(1)
end

--- A Combine bunker against a rail: a steel pod, plated and ribbed, a
--- vent on the roof, firing slits glowing either side of its door, the door
--- itself with hazard stripes on the deck outside and a light over it (the
--- door opening is drawn live: a-man/city17.lua).
local function drawBunker(s)
  local x, y, w, h = s.x, s.y, s.w, s.h
  color(C.railDark)
  love.graphics.rectangle("fill", x, y, w, h, 10)
  color(C.steel)
  love.graphics.rectangle("fill", x + 5, y + 5, w - 10, h - 10, 8)
  color(C.steelLight)
  love.graphics.rectangle("fill", x + 5, y + 5, w - 10, 5, 3)
  -- Ribs across the roof, the long way.
  color(C.railDark)
  if w > h then
    for k = x + 22, x + w - 22, 21 do
      love.graphics.rectangle("fill", k, y + 12, 3, h - 24)
    end
  else
    for k = y + 22, y + h - 22, 21 do
      love.graphics.rectangle("fill", x + 12, k, w - 24, 3)
    end
  end
  -- The roof vent with the Combine's blue under it.
  color(C.railDark)
  love.graphics.circle("fill", x + w / 2, y + h / 2, 15, 20)
  color(C.glow, 0.7)
  love.graphics.circle("fill", x + w / 2, y + h / 2, 9, 20)
  color(C.railDark)
  love.graphics.setLineWidth(2)
  love.graphics.line(x + w / 2 - 9, y + h / 2, x + w / 2 + 9, y + h / 2)
  love.graphics.line(x + w / 2, y + h / 2 - 9, x + w / 2, y + h / 2 + 9)
  love.graphics.setLineWidth(1)
  local d = s.door
  if not d then
    return
  end
  -- Everything on the face is a box from `t0` to `t1` along it and from
  -- `k0` to `k1` out of it (negative: into the bunker).
  local ax, ay = d.ny ~= 0 and 1 or 0, d.nx ~= 0 and 1 or 0
  local function box(t0, t1, k0, k1)
    local xa, xb = d.x + ax * t0 + d.nx * k0, d.x + ax * t1 + d.nx * k1
    local ya, yb = d.y + ay * t0 + d.ny * k0, d.y + ay * t1 + d.ny * k1
    love.graphics.rectangle("fill", math.min(xa, xb), math.min(ya, yb), math.abs(xb - xa), math.abs(yb - ya))
  end
  color(C.glow, 0.8) -- firing slits either side of the door
  box(-50, -32, -7, -3)
  box(32, 50, -7, -3)
  color(C.railDark) -- the door, set into the face
  box(-22, 22, -10, 0)
  color(C.plateDark)
  box(-19, -1, -8, 0)
  box(1, 19, -8, 0)
  color(C.stripe) -- hazard stripes on the deck outside it
  for k = 0, 3 do
    box(-18 + k * 10, -13 + k * 10, 2, 9)
  end
  color(C.warm) -- the light over it
  box(25, 30, -8, -2)
end

--- A computer terminal from above: a dark desk, the screen at its back
--- with lines of readout on it, a keyboard in front. The screens' flicker
--- and the cursor are drawn live (a-man/upkeep.lua).
local function drawTerminal(s)
  color(C.console)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 6)
  color(C.steelLight)
  love.graphics.rectangle("line", s.x + 1, s.y + 1, s.w - 2, s.h - 2, 6)
  color(C.screen)
  love.graphics.rectangle("fill", s.x + 6, s.y + 5, s.w - 12, s.h * 0.55, 3)
  color(C.glow, 0.9)
  local lines = math.floor((s.h * 0.55 - 6) / 5)
  for i = 0, lines - 1 do
    local len = (0.3 + 0.6 * hash(s.seed + i * 2.3)) * (s.w - 22)
    love.graphics.rectangle("fill", s.x + 10, s.y + 9 + i * 5, len, 2)
  end
  color(C.crateDark)
  love.graphics.rectangle("fill", s.x + 10, s.y + s.h * 0.55 + 10, s.w - 20, s.h * 0.45 - 16, 2)
  color(C.rivet)
  for k = 0, 7 do
    love.graphics.rectangle("fill", s.x + 13 + k * (s.w - 26) / 8, s.y + s.h * 0.55 + 13, (s.w - 26) / 8 - 2, 3)
    love.graphics.rectangle("fill", s.x + 13 + k * (s.w - 26) / 8, s.y + s.h * 0.55 + 18, (s.w - 26) / 8 - 2, 3)
  end
end

--- A row of computer cabinets against a rail, from above: one cabinet
--- every 40 px or so, each with a vent grille and a strip of lights along
--- its front (the side facing into the platform). The lights blink live
--- (a-man/upkeep.lua).
local function drawBank(s)
  local across = s.w > s.h -- the row runs left to right
  local len = across and s.w or s.h
  local n = math.max(1, math.floor(len / 40))
  local step = len / n
  for i = 0, n - 1 do
    local x, y, w, h
    if across then
      x, y, w, h = s.x + i * step, s.y, step - 3, s.h
    else
      x, y, w, h = s.x, s.y + i * step, s.w, step - 3
    end
    color(C.cabinet)
    love.graphics.rectangle("fill", x, y, w, h, 3)
    color(C.steelLight)
    love.graphics.rectangle("line", x + 0.5, y + 0.5, w - 1, h - 1, 3)
    color(C.railDark)
    if across then
      for k = y + 8, y + h - 16, 5 do
        love.graphics.rectangle("fill", x + 6, k, w - 12, 2)
      end
    else
      for k = x + 8, x + w - 16, 5 do
        love.graphics.rectangle("fill", k, y + 6, 2, h - 12)
      end
    end
  end
  -- The front, along the side away from the rail: a dark strip the lights sit in.
  color(C.screen)
  if s.side == "top" then
    love.graphics.rectangle("fill", s.x + 2, s.y + s.h - 9, s.w - 4, 7, 2)
  elseif s.side == "bottom" then
    love.graphics.rectangle("fill", s.x + 2, s.y + 2, s.w - 4, 7, 2)
  elseif s.side == "left" then
    love.graphics.rectangle("fill", s.x + s.w - 9, s.y + 2, 7, s.h - 4, 2)
  else
    love.graphics.rectangle("fill", s.x + 2, s.y + 2, 7, s.h - 4, 2)
  end
  -- Cables trailing off the back, over the rail and down into the drop.
  love.graphics.setLineWidth(3)
  color(C.railDark)
  for i = 0, n - 1, 2 do
    local k = (i + 0.5) * step
    if s.side == "top" then
      love.graphics.line(s.x + k, s.y, s.x + k + 6, s.y - 22)
    elseif s.side == "bottom" then
      love.graphics.line(s.x + k, s.y + s.h, s.x + k + 6, s.y + s.h + 22)
    elseif s.side == "left" then
      love.graphics.line(s.x, s.y + k, s.x - 22, s.y + k + 6)
    else
      love.graphics.line(s.x + s.w, s.y + k, s.x + s.w + 22, s.y + k + 6)
    end
  end
  love.graphics.setLineWidth(1)
end

--- A cable across the floor from each computer bank to the nearest
--- terminal on its platform, round the corner rather than straight across.
local function drawCables(map)
  local function platformOf(s)
    return onPlatform(map, s.x + s.w / 2, s.y + s.h / 2)
  end
  love.graphics.setLineJoin("bevel")
  for _, b in ipairs(map.cover) do
    local p = b.kind == "bank" and platformOf(b)
    local bx, by = b.x + b.w / 2, b.y + b.h / 2
    local best, bestD = nil, math.huge
    for _, c in ipairs(map.cover) do
      if p and c.kind == "console" and platformOf(c) == p then
        local d = (c.x - bx) ^ 2 + (c.y - by) ^ 2
        if d < bestD then
          best, bestD = c, d
        end
      end
    end
    if best then
      local cx, cy = best.x + best.w / 2, best.y + best.h / 2
      local pts = b.w > b.h and { bx, by, bx, cy, cx, cy } or { bx, by, cx, by, cx, cy }
      love.graphics.setLineWidth(10)
      color(C.railDark, 0.9)
      love.graphics.line(pts)
      love.graphics.setLineWidth(5)
      color(C.cabinet)
      love.graphics.line(pts)
      love.graphics.setLineWidth(2)
      color(C.glow, 0.35)
      love.graphics.line(pts)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setLineJoin("miter")
end

local function drawCover(map)
  for _, s in ipairs(map.cover) do
    color({ 0, 0, 0 }, 0.35)
    love.graphics.rectangle("fill", s.x + 8, s.y + 10, s.w, s.h, 4)
    if s.kind == "crate" then
      color(C.crate)
      love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 3)
      color(C.crateDark)
      love.graphics.setLineWidth(4)
      love.graphics.rectangle("line", s.x + 4, s.y + 4, s.w - 8, s.h - 8, 2)
      love.graphics.line(s.x + 4, s.y + 4, s.x + s.w - 4, s.y + s.h - 4)
      love.graphics.setLineWidth(1)
    elseif s.kind == "barrier" then
      color(C.barrier)
      love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 4)
      color(C.glow, 0.8)
      if s.w > s.h then
        love.graphics.rectangle("fill", s.x + 8, s.y + s.h / 2 - 2, s.w - 16, 4)
      else
        love.graphics.rectangle("fill", s.x + s.w / 2 - 2, s.y + 8, 4, s.h - 16)
      end
    elseif s.kind == "bank" then
      drawBank(s)
    elseif s.kind == "bunker" then
      drawBunker(s)
    else
      drawTerminal(s)
    end
  end
end

--- An MG emplacement's shield: steel plates in an arc round the front of
--- where the gun stands, open at the back, a glow strip along the top
--- (the gun is drawn live: a-man/nests.lua).
local function drawEmplacements(map)
  for _, b in ipairs(map.nests or {}) do
    local n = b.nest
    local reach = n.arc + math.rad(30)
    local steps = 6
    for k = 0, steps do
      local a = n.angle - reach + k * 2 * reach / steps
      love.graphics.push()
      love.graphics.translate(n.x + math.cos(a) * 30, n.y + math.sin(a) * 30)
      love.graphics.rotate(a)
      color({ 0, 0, 0 }, 0.35)
      love.graphics.rectangle("fill", -2, -8, 9, 18, 2)
      color(C.barrier)
      love.graphics.rectangle("fill", -5, -10, 9, 20, 2)
      color(C.steelLight)
      love.graphics.rectangle("line", -5, -10, 9, 20, 2)
      color(C.glow, 0.75)
      love.graphics.rectangle("fill", 1, -7, 2, 14)
      love.graphics.pop()
    end
  end
end

--- Draw the whole map; the canvas is set up and scaled by Render.build.
function RenderCitadel.draw(map, T)
  drawDrop(map)
  drawShadows(map, T)
  drawDecks(map, T)
  drawLifts(map)
  drawCables(map)
  drawCover(map)
  drawEmplacements(map)
end

return RenderCitadel
