-- How the Colosseum looks at each stage of its building, top down. Most of
-- it is drawn once per stage into a canvas (`Look.bake`); what moves (the
-- flags on a finished building) is drawn every frame (`Look.drawFlags`).
--
-- The building is an elliptical ring of `BAYS` bays round a sand floor.
-- Each bay stands up to four levels: three tiers of arcades, then the attic.
-- Seen from above, each level covers the ring from its own inner edge (`T0`,
-- a fraction of the way from the floor's edge to the outside wall) out to
-- the wall, so the seating steps down to the floor and the attic is the
-- outermost band. A bay with no level yet is its foundations. The levels go
-- up a bay at a time, clockwise from the north, so a half-built level is a
-- half ring; scaffolding stands round the outside of what is built, and
-- formwork where the next bay is going up.
--
-- Around it, inside the site hoarding: churned dirt, site cabins, a cement
-- mixer, stacked stone and timber, the cranes' mast feet (the cranes
-- themselves are borderline's, see init.lua), and a sign by the gate with
-- the progress on it. Finished, the yard is paved, the hoarding becomes a
-- low stone wall, the gate stands open and flags fly at the corners.

local UI = require("src.ui")

local Look = {}

Look.BAYS = 40
Look.LEVELS = 4
Look.OUTER = { 168, 140 } -- px radii of the outside wall
Look.INNER = { 82, 50 } -- px radii of the sand floor
Look.T0 = { 0, 0.3, 0.58, 0.84 } -- where each level starts, 0 the floor's edge, 1 the outside wall
Look.MARGIN = 24 -- px of canvas round the site, for shadows falling off it
Look.GATE = 72 -- px wide
Look.CRANE_CORNER = 158 -- px from the middle, both ways, a crane's mast stands

local C = {
  shadow = { 0, 0, 0, 0.35 },
  dirt = { 0.47, 0.38, 0.27 },
  dirtDark = { 0.38, 0.30, 0.21 },
  paving = { 0.72, 0.68, 0.60 },
  pavingJoint = { 0.62, 0.58, 0.50 },
  sand = { 0.86, 0.76, 0.52 },
  sandDark = { 0.76, 0.65, 0.42 },
  footing = { 0.46, 0.46, 0.48 },
  footingDark = { 0.34, 0.34, 0.36 },
  rebar = { 0.58, 0.30, 0.16 },
  stone = { { 0.70, 0.64, 0.52 }, { 0.76, 0.70, 0.58 }, { 0.82, 0.76, 0.64 }, { 0.88, 0.83, 0.72 } },
  riser = { 0.48, 0.42, 0.33 },
  seats = { 0.60, 0.54, 0.43 },
  arch = { 0.25, 0.21, 0.17 },
  plank = { 0.66, 0.50, 0.30 },
  tube = { 0.64, 0.66, 0.70 },
  hoarding = { 0.16, 0.30, 0.22 },
  hoardingJoint = { 0.10, 0.20, 0.14 },
  yellow = { 0.95, 0.76, 0.19 },
  ink = { 0.06, 0.06, 0.07 },
  gunmetal = { 0.23, 0.25, 0.28 },
  cabin = { 0.85, 0.85, 0.80 },
  cabinRoof = { 0.70, 0.71, 0.68 },
  barrier = { 0.85, 0.15, 0.12 },
  white = { 0.95, 0.95, 0.93 },
  flag = { { 0.62, 0.10, 0.12 }, { 0.90, 0.70, 0.20 } },
}

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A point of the ring: angle `a` (0 east, clockwise as y grows down) and
--- `t` from the floor's edge (0) to the outside wall (1); beyond 1 is
--- outside it.
local function at(a, t)
  local rx = Look.INNER[1] + (Look.OUTER[1] - Look.INNER[1]) * t
  local ry = Look.INNER[2] + (Look.OUTER[2] - Look.INNER[2]) * t
  return math.cos(a) * rx, math.sin(a) * ry
end

--- Bay `i`'s angles, from and to (bay 1 starts at the north).
local function bayAngles(i)
  local step = 2 * math.pi / Look.BAYS
  local a0 = -math.pi / 2 + (i - 1) * step
  return a0, a0 + step
end

--- The quad of bay `i` from `t0` to `t1`, nudged by (dx, dy).
local function quad(i, t0, t1, dx, dy, mode)
  local a0, a1 = bayAngles(i)
  local x1, y1 = at(a0, t0)
  local x2, y2 = at(a1, t0)
  local x3, y3 = at(a1, t1)
  local x4, y4 = at(a0, t1)
  dx, dy = dx or 0, dy or 0
  love.graphics.polygon(mode or "fill", x1 + dx, y1 + dy, x2 + dx, y2 + dy, x3 + dx, y3 + dy, x4 + dx, y4 + dy)
end

--- The arc along the ring at `t` over bay `i`, from fraction f0 to f1 of the bay.
local function arcLine(i, t, f0, f1)
  local a0, a1 = bayAngles(i)
  local xa, ya = at(a0 + (a1 - a0) * (f0 or 0), t)
  local xb, yb = at(a0 + (a1 - a0) * (f1 or 1), t)
  love.graphics.line(xa, ya, xb, yb)
end

--- What stands at stage `done` of `total` jobs: the levels built (a
--- fraction while one is going up), which bay has how many, and the rest.
--- Three tiers go up over the first three quarters of the jobs and the
--- attic over the rest, all but the last; the last job finishes it.
function Look.plan(done, total)
  total = math.max(1, total)
  local f = math.min(1, done / total)
  local finished = done >= total
  local levels = finished and Look.LEVELS or f <= 0.75 and 4 * f or math.min(Look.LEVELS, 3 + (f - 0.75) * 8)
  local whole = math.floor(levels)
  local partBays = math.floor((levels - whole) * Look.BAYS + 1e-6)
  local heights = {}
  for i = 1, Look.BAYS do
    heights[i] = math.min(Look.LEVELS, whole + (i <= partBays and 1 or 0))
  end
  local frontier = nil -- the bay going up next, and to what level
  if not finished and whole < Look.LEVELS then
    frontier = { bay = partBays + 1, level = whole + 1 }
  end
  return {
    done = done,
    total = total,
    finished = finished,
    levels = levels,
    heights = heights,
    frontier = frontier,
    -- Scaffolding stands round the built bays until the attic is up, then
    -- comes down half the ring at a time; finished, it is all gone.
    scaffold = function(i)
      return not finished and heights[i] >= 1 and (levels < Look.LEVELS or i > Look.BAYS / 2)
    end,
    cranes = finished and 0 or levels >= Look.LEVELS and 1 or 2,
  }
end

--- The yard inside the hoarding: dirt with tyre tracks while it is a
--- site, paving once it is done. Coordinates from the site's middle.
local function drawYard(plan, half)
  if plan.finished then
    color(C.paving)
    love.graphics.rectangle("fill", -half, -half, 2 * half, 2 * half)
    color(C.pavingJoint)
    for k = -half, half, 32 do
      love.graphics.line(k, -half, k, half)
      love.graphics.line(-half, k, half, k)
    end
    return
  end
  color(C.dirt)
  love.graphics.rectangle("fill", -half, -half, 2 * half, 2 * half)
  color(C.dirtDark)
  love.graphics.setLineWidth(5)
  for _, side in ipairs({ -1, 1 }) do -- the trucks' tracks in from the gate, round both ways
    for _, off in ipairs({ -10, 10 }) do
      love.graphics.arc("line", "open", 0, 0, 176 + off, math.pi / 2, math.pi / 2 - side * 1.3, 24)
    end
  end
  love.graphics.setLineWidth(1)
  for k = 0, 6 do -- puddled patches
    local x, y = ((k * 97) % 300) - 150, ((k * 61) % 300) - 150
    love.graphics.ellipse("fill", x, y, 16 + k % 3 * 6, 9 + k % 2 * 4, 12)
  end
end

--- The sand floor in the middle, or the dirt it will be, with a pile on it.
local function drawFloor(plan)
  color(plan.finished and C.sand or C.dirt)
  love.graphics.ellipse("fill", 0, 0, Look.INNER[1] + 2, Look.INNER[2] + 2, 48)
  if plan.finished then
    color(C.sandDark)
    love.graphics.setLineWidth(2)
    love.graphics.ellipse("line", 0, 0, Look.INNER[1] * 0.82, Look.INNER[2] * 0.82, 48)
    love.graphics.setLineWidth(1)
    love.graphics.circle("fill", 0, 0, 6, 16)
    return
  end
  for k = 0, 2 do -- stone blocks waiting to go up, on the floor
    color(C.shadow)
    love.graphics.rectangle("fill", -30 + k * 22 + 4, -8 + 4, 18, 14)
    color(C.stone[1])
    love.graphics.rectangle("fill", -30 + k * 22, -8, 18, 14)
  end
end

--- Every shadow first, so none falls on a higher part next to it.
local function drawShadows(plan)
  color(C.shadow)
  for i = 1, Look.BAYS do
    local h = plan.heights[i]
    if h > 0 then
      local d = 3 + 4 * h -- the outside wall's, long; the low seats inside throw a short one on the floor
      quad(i, 0, 0.5, 5, 5)
      quad(i, 0.5, 1, d, d)
      if plan.scaffold(i) then
        quad(i, 1, 1.09, d, d)
      end
    end
  end
end

--- Bay `i` at its height: each level from its inner edge out to the wall,
--- seat rows on the steps, a riser where each level starts, arcade
--- openings along the top of an unfinished one and windows in the attic.
local function drawBay(plan, i)
  local h = plan.heights[i]
  if h == 0 then
    color(C.footing)
    quad(i, 0, 1)
    color(C.footingDark)
    quad(i, 0, 1, 0, 0, "line")
    color(C.rebar)
    local a0 = bayAngles(i)
    for _, t in ipairs({ 0.2, 0.5, 0.8 }) do
      local x, y = at(a0, t)
      love.graphics.circle("fill", x, y, 2, 6)
    end
    return
  end
  for k = 1, h do
    color(C.stone[k])
    quad(i, Look.T0[k], 1)
    if k > 1 then
      color(C.riser)
      love.graphics.setLineWidth(2)
      arcLine(i, Look.T0[k])
      love.graphics.setLineWidth(1)
    end
    local top = Look.T0[k + 1] or 1
    if k < Look.LEVELS then -- rows of seats on the step
      color(C.seats)
      for t = Look.T0[k] + 0.08, top - 0.04, 0.08 do
        arcLine(i, t)
      end
    end
  end
  if h < Look.LEVELS then
    color(C.arch) -- the top arcade's openings, along the outside
    quad(i, 0.92, 1)
    color(C.stone[h])
    local a0, a1 = bayAngles(i)
    local x1, y1 = at(a0, 0.92)
    local x2, y2 = at(a0, 1)
    local x3, y3 = at(a0 + (a1 - a0) * 0.25, 1)
    local x4, y4 = at(a0 + (a1 - a0) * 0.25, 0.92)
    love.graphics.polygon("fill", x1, y1, x2, y2, x3, y3, x4, y4) -- the pier between two arches
  else
    color(C.arch) -- the attic's small square windows, every other bay
    if i % 2 == 0 then
      local a0, a1 = bayAngles(i)
      local x, y = at((a0 + a1) / 2, 0.95)
      love.graphics.rectangle("fill", x - 2, y - 2, 4, 4)
    end
    color(C.riser)
    arcLine(i, 1)
  end
end

--- Scaffolding round the outside of built bays: planks on tubes, braced;
--- and the formwork, in timber, where the next bay goes up.
local function drawScaffold(plan)
  for i = 1, Look.BAYS do
    if plan.scaffold(i) then
      color(C.plank)
      quad(i, 1, 1.09)
      color(C.tube)
      local a0, a1 = bayAngles(i)
      local xa, ya = at(a0, 1)
      local xb, yb = at(a0, 1.09)
      local xc, yc = at(a1, 1.09)
      love.graphics.line(xa, ya, xb, yb)
      love.graphics.line(xa, ya, xc, yc)
      arcLine(i, 1.09)
    end
  end
  local fr = plan.frontier
  if fr then
    color(C.plank)
    love.graphics.setLineWidth(2)
    quad(fr.bay, Look.T0[fr.level], 1, 0, 0, "line")
    love.graphics.setLineWidth(1)
  end
end

--- A box with a shadow and a dark edge.
local function block(x, y, w, h, fill, lift)
  color(C.shadow)
  love.graphics.rectangle("fill", x + (lift or 5), y + (lift or 5), w, h)
  color(C.ink)
  love.graphics.rectangle("fill", x - 1, y - 1, w + 2, h + 2)
  color(fill)
  love.graphics.rectangle("fill", x, y, w, h)
end

--- What lies about a building site: cabins, a mixer, a portable toilet,
--- stacked stone and timber, rebar, the cranes' mast feet.
local function drawSiteKit(plan)
  for _, y in ipairs({ 108, 140 }) do -- two site cabins by the gate
    block(124, y, 56, 28, C.cabin, 6)
    color(C.cabinRoof)
    love.graphics.rectangle("fill", 124, y + 8, 56, 12)
  end
  block(44, 166, 14, 14, { 0.25, 0.50, 0.75 }, 4) -- the portable toilet
  color(C.shadow)
  love.graphics.circle("fill", 80, 168, 12, 16)
  color(C.ink)
  love.graphics.circle("fill", 76, 164, 12, 16)
  color(C.barrier)
  love.graphics.circle("fill", 76, 164, 10, 16) -- the cement mixer's drum
  color(C.yellow)
  love.graphics.circle("fill", 76, 164, 4, 10)
  for k = 0, 3 do -- stacked stone in the north-west corner
    block(-176 + (k % 2) * 24, -176 + math.floor(k / 2) * 18, 20, 14, C.stone[2], 5)
  end
  for k = 0, 4 do -- a timber stack and bundles of rebar down the west side
    block(-180, -110 + k * 7, 40, 5, C.plank, 3)
  end
  color(C.rebar)
  for k = 0, 3 do
    love.graphics.line(-180 + k * 3, 80, -180 + k * 3, 128)
  end
  -- The cranes' mast feet; the cranes turn overhead.
  local cc = Look.CRANE_CORNER
  local feet = { { cc, -cc }, { -cc, cc } }
  for n = 1, plan.cranes do
    local x, y = feet[n][1], feet[n][2]
    block(x - 22, y - 22, 44, 44, C.gunmetal, 8)
    color(C.yellow)
    love.graphics.setLineWidth(5)
    love.graphics.line(x - 22, y - 22, x + 22, y + 22)
    love.graphics.line(x + 22, y - 22, x - 22, y + 22)
    love.graphics.setLineWidth(1)
  end
end

--- The site hoarding round the block (a low stone wall once it is done),
--- with its gate on the south side: shut and barred, or standing open.
local function drawFence(plan, half)
  local g = Look.GATE / 2
  local t = 8
  local wall = plan.finished and C.stone[3] or C.hoarding
  local sides = {
    { -half, -half, 2 * half, t }, { -half, -half, t, 2 * half }, { half - t, -half, t, 2 * half },
    { -half, half - t, half - g, t }, { g, half - t, half - g, t },
  }
  color(C.shadow)
  for _, s in ipairs(sides) do
    love.graphics.rectangle("fill", s[1] + 5, s[2] + 5, s[3], s[4])
  end
  for _, s in ipairs(sides) do
    color(wall)
    love.graphics.rectangle("fill", s[1], s[2], s[3], s[4])
    if not plan.finished then
      color(C.yellow)
      love.graphics.rectangle("fill", s[1], s[2], s[3], 2)
      color(C.hoardingJoint)
      for k = 0, math.max(s[3], s[4]), 32 do
        if s[3] > s[4] then
          love.graphics.line(s[1] + k, s[2], s[1] + k, s[2] + s[4])
        else
          love.graphics.line(s[1], s[2] + k, s[1] + s[3], s[2] + k)
        end
      end
    end
  end
  local y = half - t / 2
  if plan.finished then -- the gate's leaves swung in against the wall
    color(C.gunmetal)
    love.graphics.setLineWidth(4)
    love.graphics.line(-g, y - 4, -g - 10, y - 24)
    love.graphics.line(g, y - 4, g + 10, y - 24)
    love.graphics.setLineWidth(1)
    return
  end
  for k = 0, 7 do -- the gate shut: red and white, a padlock where the leaves meet
    color(k % 2 == 0 and C.barrier or C.white)
    love.graphics.rectangle("fill", -g + k * g / 4, y - 4, g / 4, 8)
  end
  block(-4, y - 5, 8, 10, C.yellow, 2)
end

--- The board by the gate: what is going up and how far it has got.
local function drawSign(plan, half)
  local x, y, w, h = -132, half - 34, 92, 26
  block(x, y, w, h, C.white, 4)
  color(C.barrier)
  love.graphics.rectangle("fill", x, y, w, 5)
  if not UI.fonts then
    return
  end
  love.graphics.setFont(UI.fonts.small)
  color(C.ink)
  local line = plan.finished and "NOW OPEN" or ("%d/%d JOBS DONE"):format(plan.done, plan.total)
  love.graphics.printf("COLOSSEUM", x, y + 3, w / 0.7, "center", 0, 0.7, 0.7)
  love.graphics.printf(line, x, y + 13, w / 0.7, "center", 0, 0.7, 0.7)
end

--- Draw everything that stays put at this stage into `canvas`, for `site`
--- ({ x, y, w, h } world px). Draw the canvas at `Look.origin(site)`.
function Look.bake(canvas, site, plan)
  local half = site.w / 2
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.translate(Look.MARGIN + half, Look.MARGIN + site.h / 2)
  drawYard(plan, half)
  if not plan.finished then
    drawSiteKit(plan)
  end
  drawFloor(plan)
  drawShadows(plan)
  for i = 1, Look.BAYS do
    drawBay(plan, i)
  end
  drawScaffold(plan)
  drawFence(plan, half)
  drawSign(plan, half)
  if plan.finished then
    for _, c in ipairs(Look.corners(half)) do -- the flagpoles' feet and shadows
      color(C.shadow)
      love.graphics.line(c[1], c[2], c[1] + 30, c[2] + 30)
      block(c[1] - 3, c[2] - 3, 6, 6, C.gunmetal, 1)
    end
  end
  love.graphics.pop()
end

--- Where the baked canvas goes, world px.
function Look.origin(site)
  return site.x - Look.MARGIN, site.y - Look.MARGIN
end

--- The corners flags fly at, from the site's middle.
function Look.corners(half)
  local k = half - 18
  return { { -k, -k }, { k, -k }, { -k, k }, { k, k } }
end

--- The flags on the finished building, flapping (`time` in seconds),
--- above everyone: the poles are tall.
function Look.drawFlags(site, time)
  local cx, cy = site.x + site.w / 2, site.y + site.h / 2
  for n, c in ipairs(Look.corners(site.w / 2)) do
    local x, y = cx + c[1] + 6, cy + c[2] - 18 -- the pole's top, up off the ground
    color(C.gunmetal)
    love.graphics.setLineWidth(2)
    love.graphics.line(cx + c[1], cy + c[2], x, y)
    love.graphics.setLineWidth(1)
    for k = 0, 3 do
      local wave = math.sin(time * 4 + n + k * 0.9) * 3
      local wave2 = math.sin(time * 4 + n + (k + 1) * 0.9) * 3
      color(C.flag[k % 2 + 1])
      love.graphics.polygon("fill", x + k * 6, y + wave, x + k * 6 + 6, y + wave2, x + k * 6 + 6, y + wave2 + 10,
        x + k * 6, y + wave + 10)
    end
  end
end

--- The tower cranes over the site, in borderline's crane format: one from
--- the north-east corner, one from the south-west, their jibs swinging over
--- the ring. `count` of them (the second leaves first).
function Look.cranes(site, count)
  local cx, cy = site.x + site.w / 2, site.y + site.h / 2
  local cc = Look.CRANE_CORNER
  local list = {}
  for n, c in ipairs({ { cc, -cc }, { -cc, cc } }) do
    if n <= count then
      local x, y = cx + c[1], cy + c[2]
      local toward = math.atan2(cy - y, cx - x)
      list[#list + 1] = { x = x, y = y, jib = math.sqrt(c[1] ^ 2 + c[2] ^ 2) + 24,
        from = toward - 0.5, sweep = 1.0, period = 16 + n * 3, phase = n * 2.1 }
    end
  end
  return list
end

return Look
