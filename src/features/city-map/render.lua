-- Draws the whole city once into a half-resolution canvas, shown at 2x with
-- nearest filtering for a chunky pixel look. One draw call per frame.

local Layout = require("src.features.city-map.layout")

local Render = {}

local C = {
  asphalt = { 0.17, 0.17, 0.19 },
  lane = { 0.85, 0.72, 0.30 },
  edge = { 0.80, 0.80, 0.78 },
  walk = { 0.52, 0.52, 0.55 },
  walkLine = { 0.46, 0.46, 0.49 },
  kerb = { 0.66, 0.66, 0.68 },
  grass = { 0.30, 0.50, 0.26 },
  grassDark = { 0.25, 0.42, 0.22 },
  canopy = { 0.16, 0.36, 0.16 },
  canopyLight = { 0.28, 0.52, 0.24 },
  lot = { 0.22, 0.22, 0.24 },
  bay = { 0.75, 0.75, 0.72 },
  dirt = { 0.45, 0.37, 0.27 },
  dirtDark = { 0.39, 0.32, 0.23 },
  stake = { 0.85, 0.80, 0.70 },
  shadow = { 0, 0, 0, 0.35 },
  ac = { 0.60, 0.62, 0.64 },
}

local function color(c)
  love.graphics.setColor(c[1], c[2], c[3], c[4] or 1)
end

local function shade(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

local function drawRoads(map)
  local T = Layout.TILE
  local P = Layout.PERIOD
  -- Tarmac and sidewalk, tile by tile: the city need not be a rectangle.
  for c = map.c0, map.c1 do
    local col = map.tiles[c]
    for r = map.r0, map.r1 do
      local kind = col and col[r]
      if kind then
        color(kind == "road" and C.asphalt or C.walk)
        love.graphics.rectangle("fill", map.x0 + c * T, map.y0 + r * T, T, T)
      end
    end
  end
  -- Paving lines and kerbs around each block.
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + (b.tx - 1) * T, map.y0 + (b.ty - 1) * T
    local w, h = 8 * T, 8 * T
    color(C.walkLine)
    love.graphics.setLineWidth(2)
    for i = 1, 7 do
      love.graphics.line(x + i * T, y, x + i * T, y + h)
      love.graphics.line(x, y + i * T, x + w, y + i * T)
    end
    color(C.kerb)
    love.graphics.setLineWidth(4)
    love.graphics.rectangle("line", x, y, w, h)
  end

  -- Lane centrelines: dashed between the two lanes of each road, skipping
  -- the crossroads.
  color(C.lane)
  love.graphics.setLineWidth(4)
  local function road(c, r)
    return map.tiles[c] and map.tiles[c][r] == "road"
  end
  for c = map.c0, map.c1 do
    for r = map.r0, map.r1 do
      if road(c, r) then
        local x, y = map.x0 + c * T, map.y0 + r * T
        if c % P == 1 and r % P >= 2 and road(c - 1, r) then
          love.graphics.line(x, y + 12, x, y + T - 12)
        end
        if r % P == 1 and c % P >= 2 and road(c, r - 1) then
          love.graphics.line(x + 12, y, x + T - 12, y)
        end
      end
    end
  end

  -- Zebra crossings where each block edge meets a road.
  color(C.edge)
  love.graphics.setLineWidth(1)
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + (b.tx - 1) * T, map.y0 + (b.ty - 1) * T
    local w, h = 8 * T, 8 * T
    local cx, cy = x + w / 2, y + h / 2
    for i = -3, 3 do
      love.graphics.rectangle("fill", cx + i * 24 - 6, y - 2 * T + 10, 12, 2 * T - 20)
      love.graphics.rectangle("fill", cx + i * 24 - 6, y + h + 10, 12, 2 * T - 20)
      love.graphics.rectangle("fill", x - 2 * T + 10, cy + i * 24 - 6, 2 * T - 20, 12)
      love.graphics.rectangle("fill", x + w + 10, cy + i * 24 - 6, 2 * T - 20, 12)
    end
  end
end

local function drawParksAndLots(map)
  local T = Layout.TILE
  for _, b in ipairs(map.blocks) do
    local x, y = map.x0 + b.tx * T, map.y0 + b.ty * T
    local w, h = b.tw * T, b.th * T
    if b.kind == "park" then
      color(C.grass)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.grassDark)
      for i = 0, 5 do
        love.graphics.rectangle("fill", x + (i * 97) % (w - 40), y + (i * 61) % (h - 30), 40, 30)
      end
    elseif b.kind == "lot" then
      color(C.lot)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.bay)
      love.graphics.setLineWidth(3)
      for i = 0, 7 do
        love.graphics.line(x + 20 + i * 48, y + 16, x + 20 + i * 48, y + 90)
        love.graphics.line(x + 20 + i * 48, y + h - 16, x + 20 + i * 48, y + h - 90)
      end
      love.graphics.line(x + 20, y + 16, x + 20 + 7 * 48, y + 16)
      love.graphics.line(x + 20, y + h - 16, x + 20 + 7 * 48, y + h - 16)
    elseif b.kind == "plot" then
      -- Cleared ground waiting for a builder: packed dirt, a few worn
      -- patches and survey stakes at every other tile corner.
      color(C.dirt)
      love.graphics.rectangle("fill", x, y, w, h)
      color(C.dirtDark)
      for i = 0, 4 do
        love.graphics.rectangle("fill", x + 20 + (i * 83) % (w - 80), y + 24 + (i * 131) % (h - 70), 60, 36)
      end
      color(C.stake)
      for i = 0, b.tw, 2 do
        for j = 0, b.th, 2 do
          love.graphics.rectangle("fill", x + i * T - 3, y + j * T - 3, 6, 6)
        end
      end
    end
  end
end

local function drawBuildings(map)
  -- Shadows first so they never fall on a neighbouring roof.
  color(C.shadow)
  for _, b in ipairs(map.buildings) do
    love.graphics.rectangle("fill", b.x + 14, b.y + 14, b.w, b.h)
  end
  for _, b in ipairs(map.buildings) do
    color(shade(b.color, 0.55))
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
    color(b.color)
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, b.h - 12)
    -- lit edge top-left
    color(shade(b.color, 1.25))
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, b.w - 12, 8)
    love.graphics.rectangle("fill", b.x + 6, b.y + 6, 8, b.h - 12)
    -- roof furniture, placed by the building's own seed
    local s = b.seed
    if b.style == 1 then
      color(C.ac)
      for i = 0, 2 do
        local ax = b.x + 30 + ((s * 7 + i * 53) % math.max(1, b.w - 70))
        local ay = b.y + 30 + ((s * 11 + i * 37) % math.max(1, b.h - 70))
        love.graphics.rectangle("fill", ax, ay, 22, 22)
        color(shade(C.ac, 0.6))
        love.graphics.rectangle("fill", ax + 4, ay + 4, 14, 14)
        color(C.ac)
      end
    elseif b.style == 2 then
      color(shade(b.color, 0.75))
      love.graphics.rectangle("fill", b.x + 24, b.y + 24, b.w - 48, b.h - 48)
      color(shade(b.color, 1.1))
      love.graphics.rectangle("fill", b.x + 34, b.y + 34, b.w - 68, b.h - 68)
    else
      color(shade(b.color, 0.7))
      for i = 1, 3 do
        love.graphics.rectangle("fill", b.x + 20, b.y + i * (b.h / 4) - 3, b.w - 40, 6)
      end
    end
  end
end

local function drawTrees(map)
  for _, t in ipairs(map.trees) do
    color(C.shadow)
    love.graphics.circle("fill", t.x + 8, t.y + 8, 24)
  end
  for _, t in ipairs(map.trees) do
    color(C.canopy)
    love.graphics.circle("fill", t.x, t.y, 24)
    color(C.canopyLight)
    love.graphics.circle("fill", t.x - 6, t.y - 6, 12)
  end
end

--- Build the canvas. Call once with graphics available.
function Render.build(map)
  local canvas = love.graphics.newCanvas(map.w / 2, map.h / 2)
  canvas:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(canvas)
  love.graphics.clear(0, 0, 0, 0)
  love.graphics.setLineStyle("rough")
  love.graphics.scale(0.5)
  love.graphics.translate(-map.left, -map.top)
  drawRoads(map)
  drawParksAndLots(map)
  drawBuildings(map)
  drawTrees(map)
  love.graphics.setCanvas()
  love.graphics.pop()
  return canvas
end

function Render.draw(map, canvas)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(canvas, map.left, map.top, 0, 2, 2)
end

return Render
