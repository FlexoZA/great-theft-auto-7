-- The Borderline maps' floors and what lies round them (render_borderline.lua
-- draws them into the map's canvas; surroundings/borderline.lua the same past
-- its edges): the floors' finishes and the snow on them, the outside tile by
-- tile, the outline where they meet, snow heaped against the walls and
-- whatever stands, forklifts' tracks, the hollow at the Wreck's arrival.

local Kit = require("src.features.city-map.render_borderline_kit")

local Ground = {}

local INK, LINE, C = Kit.INK, Kit.LINE, Kit.C
local color, hash, noise, drift, blob, box = Kit.color, Kit.hash, Kit.noise, Kit.drift, Kit.blob, Kit.box


--- What the outside is at tile (c, r) on `map`.
local function outsideAt(map, c, r)
  local o = map.outside
  if o == "works" then
    return C.works
  elseif o == "harbour" then
    return r < 2 and C.sea or C.bank
  elseif o == "rock" then
    return C.rock
  elseif o == "dome" then
    return C.bank
  elseif o == "plant" then
    return C.wall
  elseif o == "cliff" then
    local road = map.cutsRoad[r]
    return road and c < road[1] and C.abyss or C.rock
  elseif o == "sky" then
    return C.sky
  end
  return C.bank
end

local function floorAt(map, x, y)
  local floor = nil
  for _, g in ipairs(map.grounds) do
    if x >= g.x0 and x < g.x1 and y >= g.y0 and y < g.y1 then
      floor = g.floor
    end
  end
  return C[floor] or C.yard
end

local function open(map, c, r)
  return map.tiles[c] ~= nil and map.tiles[c][r] ~= nil
end

--- How deep the snow lies on a yard at tile (c, r): 0 bare .. 1 deep.
local function snowAt(c, r)
  return noise(c / 4.5, r / 4.5) * 0.75 + noise(c / 1.7 + 40, r / 1.7) * 0.25
end

--- The factory's roofs round the Wreck's yard, one tile of them: buildings
--- 6 x 4 tiles, each its own shade with its corrugations one way or the
--- other, parapets between them; skylights down some (lit where the night
--- shift is on), pipes along others, turbine vents, extractors and stacks
--- here and there, snow lying in patches. Tiles past the map's edge are
--- drawn the same, so the roofs run on.
local function drawWorksRoof(c, r, x, y, T)
  local bc, br = math.floor(c / 6), math.floor(r / 4)
  local lc, lr = c - bc * 6, r - br * 4
  local bh = hash(bc * 3.3 + br * 7.7 + 0.5)
  local h = hash(c * 7.1 + r * 13.7)
  local k = 0.85 + 0.3 * bh
  love.graphics.setColor(C.works[1] * k, C.works[2] * k, C.works[3] * k)
  love.graphics.rectangle("fill", x, y, T, T)
  love.graphics.setColor(C.worksRidge[1] * k, C.worksRidge[2] * k, C.worksRidge[3] * k)
  for a = 4, T - 4, 10 do
    if bh < 0.5 then
      love.graphics.rectangle("fill", x, y + a, T, 3)
    else
      love.graphics.rectangle("fill", x + a, y, 3, T)
    end
  end
  if bh > 0.25 and bh < 0.7 and lr == 2 then -- a skylight down the building
    color(INK)
    love.graphics.rectangle("fill", x, y + 14, T, 32)
    local lit = bh > 0.45
    color(lit and C.skylightLit or C.window, lit and 0.85 or 1)
    love.graphics.rectangle("fill", x, y + 17, T, 26)
    color(INK)
    for a = 0, T - 1, 16 do
      love.graphics.rectangle("fill", x + a, y + 17, 3, 26)
    end
  elseif bh > 0.75 and lr == 1 then -- pipes along it
    for _, py in ipairs({ y + 18, y + 38 }) do
      color(INK)
      love.graphics.rectangle("fill", x, py, T, 12)
      color(C.gunmetalLight)
      love.graphics.rectangle("fill", x, py + 3, T, 5)
    end
  elseif lc > 0 and lr > 0 then
    if h < 0.08 then -- a turbine vent
      blob(x + 18, y + 18, 28, 28, C.gunmetalLight)
      color(INK)
      love.graphics.rectangle("fill", x + 22, y + 31, 20, 3)
      love.graphics.rectangle("fill", x + 31, y + 22, 3, 20)
    elseif h < 0.12 then -- an extractor, its fan
      box(x + 10, y + 14, 44, 34, C.gunmetalLight)
      color(INK)
      love.graphics.circle("fill", x + 32, y + 31, 12, 14)
      color(C.gunmetal)
      love.graphics.rectangle("fill", x + 21, y + 29, 22, 4)
    elseif h < 0.14 then -- a stack
      blob(x + 18, y + 18, 28, 28, C.rust)
      color(INK)
      love.graphics.circle("fill", x + 32, y + 32, 8, 10)
    end
  end
  if lc == 0 then -- the parapets between buildings
    color(INK)
    love.graphics.rectangle("fill", x, y, 5, T)
    color(C.gunmetalLight, 0.8)
    love.graphics.rectangle("fill", x + 5, y, 3, T)
  end
  if lr == 0 then
    color(INK)
    love.graphics.rectangle("fill", x, y, T, 5)
    color(C.gunmetalLight, 0.8)
    love.graphics.rectangle("fill", x, y + 5, T, 3)
  end
  local n = noise(c / 3 + 11, r / 3 + 5)
  if n > 0.66 then -- snow lying in the corrugations
    color(C.snow, 0.9)
    for i = 0, 1 do
      local sx, sy = x + T * 0.5 * hash(h * 3 + i), y + T * (0.25 + 0.5 * hash(h * 5 + i))
      love.graphics.rectangle("fill", sx, sy, T * (0.3 + 0.4 * hash(h * 7 + i)), 4)
    end
  end
end

--- The frozen harbour, one tile of it: plates of sea ice with dark water
--- in the leads between them, the plates smaller the nearer the quay,
--- where the ships keep it broken up into shards and slush.
local function drawSeaIce(c, r, x, y, T)
  local near = math.max(0, math.min(1, (r + 4) / 5)) -- 1 at the quay, 0 far out
  local n = 2 + math.floor(near * 4)
  for i = 1, n do
    local h1, h2, h3 = hash(c * 3.3 + r * 7.9 + i * 1.1), hash(c * 5.1 + r * 2.3 + i * 2.7), hash(c * 9.7 + r + i)
    local size = T * (0.55 - 0.3 * near) * (0.7 + 0.6 * h3)
    local px, py = x + T * h1, y + T * h2
    local pts = {}
    for k = 0, 5 do
      local a = k * math.pi / 3 + h3 * 2
      local rr = size * (0.6 + 0.5 * hash(h1 * 13 + k))
      pts[#pts + 1] = px + math.cos(a) * rr
      pts[#pts + 1] = py + math.sin(a) * rr * 0.75
    end
    color(C.snowShade, 0.95)
    love.graphics.polygon("fill", pts)
    for k = 1, #pts, 2 do
      pts[k], pts[k + 1] = px + (pts[k] - px) * 0.85 - 2, py + (pts[k + 1] - py) * 0.85 - 2
    end
    color(h3 < 0.3 and C.ice or C.floe)
    love.graphics.polygon("fill", pts)
  end
  if near > 0.6 then -- slush between the shards
    color(C.white, 0.18)
    love.graphics.ellipse("fill", x + T * hash(c + r * 3.1), y + T * hash(c * 2 + r), T * 0.3, T * 0.08, 10)
  end
end

--- One tile of the map's outside at (c, r), (x, y) in world px.
local function drawOutside(map, c, r, x, y, T)
  local o = outsideAt(map, c, r)
  if o == C.works then
    drawWorksRoof(c, r, x, y, T)
    return
  end
  local h = hash(c * 7.1 + r * 13.7)
  color(o)
  love.graphics.rectangle("fill", x, y, T, T)
  if o == C.rock and h < 0.4 then
    color(C.rockLight)
    love.graphics.polygon("fill", x + 10, y + 50, x + 30 + h * 20, y + 14, x + 54, y + 48)
  elseif o == C.sea then
    drawSeaIce(c, r, x, y, T)
  elseif map.outside == "dome" and (open(map, c - 1, r) or open(map, c + 1, r)
      or open(map, c, r - 1) or open(map, c, r + 1)) then
    color(C.glass)
    love.graphics.rectangle("fill", x, y, T, T)
  elseif o == C.sky and h < 0.22 then -- cloud far below
    color(C.white, 0.5)
    love.graphics.ellipse("fill", x + 32, y + 32, 40 + h * 60, 18 + h * 20, 16)
  elseif o == C.bank and h < 0.3 then -- rocks poking out of the snow
    blob(x + 8 + h * 20, y + 14, 22 + h * 40, 16 + h * 24, C.bankRock)
    color(C.snow)
    love.graphics.ellipse("fill", x + 20 + h * 30, y + 18, 8 + h * 12, 4 + h * 6)
  end
end

--- One tile of quay concrete (Liar's Landing's yard and quay): slabs two
--- tiles square, each poured its own shade, the joints between them, a
--- saw cut across the middle, a crack now and then.
local function drawSlab(c, r, x, y, T, f)
  local sc, sr = math.floor(c / 2), math.floor(r / 2)
  local k = 0.95 + 0.1 * hash(sc * 3.7 + sr * 9.1 + 0.3)
  love.graphics.setColor(f[1] * k, f[2] * k, f[3] * k)
  love.graphics.rectangle("fill", x, y, T, T)
  color(INK, 0.24)
  if c % 2 == 0 then
    love.graphics.rectangle("fill", x, y, 3, T)
  end
  if r % 2 == 0 then
    love.graphics.rectangle("fill", x, y, T, 3)
  end
  color(INK, 0.08)
  if c % 2 == 1 then
    love.graphics.rectangle("fill", x, y, 1, T)
  end
  if r % 2 == 1 then
    love.graphics.rectangle("fill", x, y, T, 1)
  end
  local h = hash(c * 7.1 + r * 13.7)
  if h < 0.07 then
    color(INK, 0.2)
    love.graphics.setLineWidth(2)
    love.graphics.line(x + 6, y + T * h * 10, x + T * 0.4, y + T * 0.5, x + T * 0.6, y + T * 0.45, x + T - 4,
      y + T * (1 - h * 8))
    love.graphics.setLineWidth(1)
  end
end

--- One tile of floor at (c, r), finish `f`.
local function drawFloor(c, r, x, y, T, f)
  if f == C.port or f == C.quay then
    drawSlab(c, r, x, y, T, f)
    return
  end
  local h = hash(c * 7.1 + r * 13.7)
  color(f)
  love.graphics.rectangle("fill", x, y, T, T)
  if f == C.snow or f == C.road then -- drifts
    color(C.snowShade)
    love.graphics.ellipse("fill", x + h * T, y + hash(h) * T, 14 + h * 12, 5 + h * 4)
  elseif f == C.roof then -- armour plates, riveted
    color(INK, 0.3)
    love.graphics.rectangle("fill", x, y, T, 3)
    love.graphics.rectangle("fill", x, y, 3, T)
    color(C.gunmetalLight, 0.8)
    for _, k in ipairs({ { 8, 8 }, { T - 10, 8 }, { 8, T - 10 }, { T - 10, T - 10 } }) do
      love.graphics.circle("fill", x + k[1], y + k[2], 2.5, 6)
    end
  elseif f ~= C.ice and f ~= C.plaza then -- slabs and plates
    color(INK, 0.18)
    love.graphics.rectangle("fill", x, y, T, 2)
    love.graphics.rectangle("fill", x, y, 2, T)
  end
end

--- The snow on a yard's tile: where it lies deep, a couple of wide flat
--- lumps running into the next tile's, so the patches join up into one
--- shape (`shade` draws the grey rim under them all first, then again
--- without it for the snow on top); where it is thin, a few flecks.
local function drawYardSnow(c, r, x, y, T, shade)
  local n = snowAt(c, r)
  if n > 0.58 then
    for i = 0, 1 do
      local hx, hy = hash(c * 3.1 + r * 5.3 + i), hash(c * 7.7 + r * 2.9 + i * 1.3)
      local rx = T * (0.62 + 0.2 * hash(c + r * 0.7 + i * 3.3))
      if shade then
        color(C.snowShade)
        love.graphics.ellipse("fill", x + hx * T, y + hy * T + 5, rx + 2, rx * 0.58, 18)
      else
        color(C.snow)
        love.graphics.ellipse("fill", x + hx * T, y + hy * T, rx, rx * 0.55, 18)
      end
    end
  elseif n > 0.46 and not shade then
    for i = 0, 2 do
      local hx, hy = hash(c * 5.9 + r * 3.7 + i), hash(c * 2.3 + r * 9.1 + i * 1.7)
      local k = hash(c * 1.3 + r * 4.1 + i)
      color(C.snow, 0.7)
      love.graphics.ellipse("fill", x + hx * T, y + hy * T, 3 + 8 * k, 2 + 3 * k, 10)
    end
  end
end

--- Snow heaped against the walls round a yard: lumps along each edge
--- where it meets the outside, on the yard's side of it.
local function drawWallDrifts(map, T)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if open(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        local edges = {
          { not open(map, c - 1, r) and c > map.c0, x, y, 0, 1, -math.pi / 2, math.pi / 2 },
          { not open(map, c + 1, r) and c < map.c1, x + T, y, 0, 1, math.pi / 2, math.pi * 1.5 },
          { not open(map, c, r - 1) and r > map.r0, x, y, 1, 0, 0, math.pi },
          { not open(map, c, r + 1) and r < map.r1, x, y + T, 1, 0, math.pi, math.pi * 2 },
        }
        for i, e in ipairs(edges) do
          if e[1] then
            for k = 0, 2 do
              local seed = c * 3.7 + r * 1.9 + i * 5.1 + k
              local rad = 12 + 14 * hash(seed)
              local px, py = e[2] + e[4] * T * (k + 0.5) / 3, e[3] + e[5] * T * (k + 0.5) / 3
              color(C.snowShade, 0.95)
              love.graphics.arc("fill", px, py, rad, e[6], e[7], 10)
              color(C.snow)
              love.graphics.arc("fill", px, py, rad * 0.8, e[6], e[7], 10)
            end
          end
        end
      end
    end
  end
end

--- The floors, the snow on them, then the outside round them (drawn last,
--- so no lump of snow spills over a wall).
local function drawTiles(map, T)
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if open(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        drawFloor(c, r, x, y, T, floorAt(map, x + T / 2, y + T / 2))
      end
    end
  end
  for _, shade in ipairs({ true, false }) do
    for c = map.c0, map.c1 do
      for r = map.r0, map.r1 do
        local x, y = map.x0 + c * T, map.y0 + r * T
        local f = open(map, c, r) and floorAt(map, x + T / 2, y + T / 2)
        if f == C.yard or f == C.port then
          drawYardSnow(c, r, x, y, T, shade)
        end
      end
    end
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if not open(map, c, r) then
        drawOutside(map, c, r, map.x0 + c * T, map.y0 + r * T, T)
      end
    end
  end
end

--- The comic outline along every edge where a floor meets the outside
--- (not along the map's own edge, where the floor runs on past it).
local function drawEdges(map, T)
  color(INK)
  local function shut(c, r)
    return not open(map, c, r) and c >= map.c0 and c <= map.c1 and r >= map.r0 and r <= map.r1
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if open(map, c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if shut(c - 1, r) then
          love.graphics.rectangle("fill", x - LINE, y - LINE, LINE, T + 2 * LINE)
        end
        if shut(c + 1, r) then
          love.graphics.rectangle("fill", x + T, y - LINE, LINE, T + 2 * LINE)
        end
        if shut(c, r - 1) then
          love.graphics.rectangle("fill", x - LINE, y - LINE, T + 2 * LINE, LINE)
        end
        if shut(c, r + 1) then
          love.graphics.rectangle("fill", x - LINE, y + T, T + 2 * LINE, LINE)
        end
      end
    end
  end
end

--- Forklifts' tracks through the snow (`map.tracks`, lines of world
--- points): two rows of tread, smoothed through the points, pressed grey
--- into the snow and fainter where the yard is bare.
local function drawTracks(map, T)
  local function tread(x, y)
    local c, r = math.floor((x - map.x0) / T), math.floor((y - map.y0) / T)
    if snowAt(c, r) > 0.44 then
      love.graphics.setColor(0.60, 0.66, 0.76, 0.9)
    else
      color(INK, 0.12)
    end
    love.graphics.rectangle("fill", x - 3, y - 3, 6, 6)
  end
  for _, line in ipairs(map.tracks or {}) do
    for i = 1, #line - 1 do
      local p0, p1, p2, p3 = line[math.max(1, i - 1)], line[i], line[i + 1], line[math.min(#line, i + 2)]
      local len = math.sqrt((p2[1] - p1[1]) ^ 2 + (p2[2] - p1[2]) ^ 2)
      local steps = math.max(2, math.floor(len / 9))
      for j = 0, steps - 1 do
        local t = j / steps
        local t2, t3 = t * t, t * t * t
        local function at(k)
          return 0.5 * ((2 * p1[k]) + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
            + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3)
        end
        local x, y = at(1), at(2)
        local dx, dy = p2[1] - p1[1], p2[2] - p1[2]
        local d = math.max(1, math.sqrt(dx * dx + dy * dy))
        local nx, ny = -dy / d * 13, dx / d * 13
        tread(x + nx, y + ny)
        tread(x - nx, y - ny)
      end
    end
  end
end

--- Snow heaped against the sides of what stands in the Wreck's yard: the
--- sheds, the carriages and the engine.
local DRIFTS = { shed = true, carriage = true, loco = true }

local function drawCoverDrifts(map)
  for i, s in ipairs(map.cover) do
    if DRIFTS[s.kind] then
      drift(s.x + 10, s.y + s.h + 4, s.w - 20, 0, 13, i * 7.3, 0.95) -- south
      drift(s.x - 4, s.y + 14, 0, s.h - 28, 12, i * 3.1, 0.95) -- west
    end
  end
end

--- Where you were dug out of the snow (`map.dugout`): a hollow with the
--- snow thrown up round it, and footprints leading off north.
local function drawDugout(map)
  local d = map.dugout
  if not d then
    return
  end
  for i = 0, 9 do
    local a = i / 10 * math.pi * 2
    drift(d.x + math.cos(a) * 34, d.y + math.sin(a) * 22, 0, 0, 14, i * 1.7, 0.95)
  end
  love.graphics.setColor(0.56, 0.62, 0.72)
  love.graphics.ellipse("fill", d.x, d.y, 30, 18, 16)
  color(INK, 0.25)
  for i = 1, 9 do
    local side = i % 2 == 0 and 1 or -1
    love.graphics.ellipse("fill", d.x - 30 - i * 6 + side * 7, d.y - 30 - i * 28, 5, 8, 8)
  end
end

Ground.outsideAt, Ground.floorAt, Ground.open, Ground.snowAt = outsideAt, floorAt, open, snowAt
Ground.drawOutside, Ground.drawFloor, Ground.drawYardSnow = drawOutside, drawFloor, drawYardSnow
Ground.drawTiles, Ground.drawEdges, Ground.drawTracks = drawTiles, drawEdges, drawTracks
Ground.drawWallDrifts, Ground.drawCoverDrifts, Ground.drawDugout = drawWallDrifts, drawCoverDrifts, drawDugout

return Ground
