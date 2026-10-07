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
    else
      color(C.console)
      love.graphics.rectangle("fill", s.x, s.y, s.w, s.h, 6)
      color(C.glow, 0.85)
      love.graphics.rectangle("fill", s.x + 8, s.y + 8, s.w - 16, s.h - 20, 3)
      color(C.warm)
      love.graphics.rectangle("fill", s.x + 8, s.y + s.h - 9, 8, 4)
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
  drawCover(map)
  drawEmplacements(map)
end

return RenderCitadel
