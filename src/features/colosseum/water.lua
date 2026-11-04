-- What moves on the arena's sand, over the map's canvas (render_arena.lua
-- draws the rest): the streams running down from the lions' heads in
-- streaks of light, foam where the water pours onto the sand, rings
-- spreading over the basins, and the braziers on the wall burning. Drawn
-- by the colosseum feature in the arena, for what the camera sees.

local Water = {}

Water.STREAKS = 70 -- streaks of light a stream
Water.SPEED = 70 -- px a second the water runs
Water.RINGS = 3 -- rings spreading over a basin at once
Water.RING_EVERY = 2.4 -- seconds a ring takes to spread across

local GLINT = { 0.80, 0.94, 0.94 }
local FOAM = { 0.92, 0.97, 0.96 }

local function hash(n)
  local x = math.sin(n * 12.9898) * 43758.5453
  return x - math.floor(x)
end

local paths = nil -- { map, list = { { pts, along, total, half } } } how far along each stream every point is

--- Every stream's points with how far along it each is, worked out once a map.
local function measure(map)
  if paths and paths.map == map then
    return paths.list
  end
  local list = {}
  for _, s in ipairs(map.streams) do
    local along, total = { 0 }, 0
    for i = 2, #s.pts do
      local a, b = s.pts[i - 1], s.pts[i]
      total = total + math.sqrt((b.x - a.x) ^ 2 + (b.y - a.y) ^ 2)
      along[i] = total
    end
    list[#list + 1] = { pts = s.pts, along = along, total = total, half = s.half }
  end
  paths = { map = map, list = list }
  return list
end

--- The point `d` px along path `p`, and the way it runs there (a unit vector).
local function at(p, d)
  local i = 2
  while i < #p.pts and p.along[i] < d do
    i = i + 1
  end
  local a, b = p.pts[i - 1], p.pts[i]
  local len = p.along[i] - p.along[i - 1]
  local t = len > 0 and (d - p.along[i - 1]) / len or 0
  return a.x + (b.x - a.x) * t, a.y + (b.y - a.y) * t, (b.x - a.x) / len, (b.y - a.y) / len
end

local function onSand(o, x, y)
  return ((x - o.x) / o.rx) ^ 2 + ((y - o.y) / o.ry) ^ 2 < 1
end

--- Is (x, y) hidden: under a bridge, or on a statue?
local function hidden(map, x, y)
  for _, d in ipairs(map.footbridges) do
    if x >= d.x - 4 and x <= d.x + d.w + 4 and y >= d.y - 4 and y <= d.y + d.h + 4 then
      return true
    end
  end
  for _, b in ipairs(map.basins) do
    if (x - b.x) ^ 2 + (y - b.y) ^ 2 < (b.statue + 8) ^ 2 then
      return true
    end
  end
  return false
end

local function seen(x, y, view, pad)
  return x > view[1] - pad and x < view[3] + pad and y > view[2] - pad and y < view[4] + pad
end

--- The current: streaks of light running down each stream, fading in and out.
local function drawStreaks(map, time, view)
  love.graphics.setLineWidth(3)
  for si, p in ipairs(measure(map)) do
    for k = 1, Water.STREAKS do
      local h = hash(si * 101 + k)
      local d = (h * p.total + time * Water.SPEED * (0.8 + hash(k * 3.3) * 0.4)) % p.total
      local x, y, dx, dy = at(p, d)
      local across = (hash(k * 7.7 + si) * 2 - 1) * p.half * 0.7
      x, y = x - dy * across, y + dx * across
      local len = 10 + hash(k * 5.1) * 18
      if seen(x, y, view, 40) and onSand(map.oval, x, y) and not hidden(map, x, y)
        and not hidden(map, x + dx * len, y + dy * len) then
        local life = math.sin(math.pi * ((time * 0.6 + h * 5) % 1)) -- each one comes and goes
        love.graphics.setColor(GLINT[1], GLINT[2], GLINT[3], 0.45 * life)
        love.graphics.line(x, y, x + dx * len, y + dy * len)
      end
    end
  end
end

--- Foam where each lion's head pours onto the sand: bubbles boiling up and spreading.
local function drawSplash(map, time, view)
  for si, s in ipairs(map.streams) do
    local i = 1
    while s.pts[i + 1] and not onSand(map.oval, s.pts[i].x, s.pts[i].y) do
      i = i + 1
    end
    local x, y = s.pts[i].x, s.pts[i].y + 6
    if seen(x, y, view, 60) then
      for k = 1, 9 do
        local t = (time * 1.4 + hash(k * 2.9 + si)) % 1
        local a = hash(k * 4.3) * math.pi -- the half below the spout, downstream
        local r = 4 + t * 26
        love.graphics.setColor(FOAM[1], FOAM[2], FOAM[3], 0.7 * (1 - t))
        love.graphics.circle("fill", x + math.cos(a) * r, y + math.sin(a) * r * 0.8, 3 + (1 - t) * 4, 8)
      end
      local drop = (time * 3) % 1 -- the pour, rippling down from the mouth
      love.graphics.setColor(FOAM[1], FOAM[2], FOAM[3], 0.6)
      love.graphics.rectangle("fill", x - 5, y - 30 + drop * 22, 10, 4)
    end
  end
end

--- Rings spreading over each basin from its statue, fading as they go.
local function drawRings(map, time, view)
  love.graphics.setLineWidth(2)
  for bi, b in ipairs(map.basins) do
    if seen(b.x, b.y, view, b.r) then
      for k = 0, Water.RINGS - 1 do
        local t = (time / Water.RING_EVERY + k / Water.RINGS + bi * 0.37) % 1
        local r = b.statue + 6 + t * (b.r - b.statue - 14)
        love.graphics.setColor(GLINT[1], GLINT[2], GLINT[3], 0.35 * (1 - t))
        love.graphics.circle("line", b.x, b.y, r, 48)
      end
    end
  end
end

--- The braziers on the wall: a glow round each, the flames licking up.
local function drawFire(map, time, view)
  for i, b in ipairs(map.braziers) do
    if seen(b.x, b.y, view, 80) then
      local f = 0.8 + 0.2 * math.sin(time * 9 + i * 1.7) * math.sin(time * 5.3 + i)
      love.graphics.setBlendMode("add")
      love.graphics.setColor(1, 0.55, 0.15, 0.10 * f)
      love.graphics.circle("fill", b.x, b.y, 56 * f, 24)
      love.graphics.setColor(1, 0.65, 0.20, 0.12 * f)
      love.graphics.circle("fill", b.x, b.y, 30 * f, 20)
      love.graphics.setBlendMode("alpha")
      for k = 0, 4 do -- tongues of flame, swaying with the light
        local a = time * 4 + k * 1.3 + i
        local x, y = b.x + math.sin(a) * 4, b.y - 2 - k * 3 * f
        love.graphics.setColor(1, 0.35 + k * 0.12, 0.05 + k * 0.05, 0.9 - k * 0.12)
        love.graphics.circle("fill", x, y, (8 - k * 1.3) * f, 10)
      end
    end
  end
end

--- All of it over `view` ({ left, top, right, bottom }, world px) at `time`.
function Water.draw(map, time, view)
  if not map.streams then
    return
  end
  drawStreaks(map, time, view)
  drawSplash(map, time, view)
  drawRings(map, time, view)
  drawFire(map, time, view)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Water
