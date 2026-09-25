-- Minimap: a small map in the bottom-right corner. Shows the city (drawn
-- once from the city-map layout), every player as a dot in their colour
-- (driving or walking), you with a heading tick, parked cars as small
-- squares (your own ringed in white, so you can always find them), and the
-- rectangle the camera currently sees. Without the city-map feature it
-- becomes a radar centred on you.
--
-- Purely local. Tab toggles it.

local Features = require("src.features")
local Car = require("src.car")
local Controls = require("src.controls")

local Minimap = {
  name = "minimap",
  priority = 890, -- over the arrows (500), under the vision cursor (900)
}

-- Tuning ------------------------------------------------------------------
Minimap.width = 220 -- px on screen
Minimap.margin = 12
Minimap.top = 34 -- px from the top edge: under the connection line at the top right
Minimap.alpha = 0.88
Minimap.radarRange = 2400 -- px of world shown across the radar when there is no map
Minimap.visible = true

local canvas, mapRef, scale, height = nil, nil, 1, 0
local drawnMap, drawnVersion = nil, nil -- the map and map.version the canvas shows
local camera = nil

local C = {
  asphalt = { 0.17, 0.17, 0.19 },
  walk = { 0.40, 0.40, 0.43 },
  grass = { 0.28, 0.46, 0.25 },
  ground = { 0.30, 0.40, 0.24 },
  lot = { 0.22, 0.22, 0.24 },
  plot = { 0.45, 0.37, 0.27 },
  frame = { 0.85, 0.85, 0.85 },
  outside = { 0.08, 0.08, 0.09 },
}

--- Draw the city layout into a canvas the size of the minimap.
local function buildCanvas(map)
  local T = 64
  scale = Minimap.width / map.w
  height = math.floor(map.h * scale)
  local c = love.graphics.newCanvas(Minimap.width, height)
  c:setFilter("nearest", "nearest")
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(c)
  love.graphics.clear(C.outside[1], C.outside[2], C.outside[3], 1)
  love.graphics.scale(scale)
  love.graphics.translate(-map.left, -map.top)
  -- Open ground, tile by tile (an empty map has no blocks to draw).
  love.graphics.setColor(C.ground)
  for tc = map.c0, map.c1 do
    local col = map.tiles[tc]
    for tr = map.r0, map.r1 do
      if col and col[tr] == "ground" then
        love.graphics.rectangle("fill", map.x0 + tc * T, map.y0 + tr * T, T, T)
      end
    end
  end
  -- Each block with the streets around it; the city grows block by block,
  -- so it need not be a rectangle.
  love.graphics.setColor(C.asphalt)
  for _, b in ipairs(map.blocks) do
    love.graphics.rectangle("fill", map.x0 + (b.tx - 3) * T, map.y0 + (b.ty - 3) * T, 12 * T, 12 * T)
  end
  for _, b in ipairs(map.blocks) do
    love.graphics.setColor(C.walk)
    love.graphics.rectangle("fill", map.x0 + (b.tx - 1) * T, map.y0 + (b.ty - 1) * T, 8 * T, 8 * T)
    if b.kind == "park" then
      love.graphics.setColor(C.grass)
      love.graphics.rectangle("fill", map.x0 + b.tx * T, map.y0 + b.ty * T, b.tw * T, b.th * T)
    elseif b.kind == "lot" or b.kind == "plot" then
      love.graphics.setColor(C[b.kind])
      love.graphics.rectangle("fill", map.x0 + b.tx * T, map.y0 + b.ty * T, b.tw * T, b.th * T)
    end
  end
  for _, b in ipairs(map.buildings) do
    love.graphics.setColor(b.color)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return c
end

function Minimap:load()
  Controls.register("minimap", "Toggle minimap", "tab")
end

--- Follow the city map, redrawing when it is replaced or grows.
local function refresh()
  local city = Features.byName["city-map"]
  mapRef = city and city.map or nil
  if mapRef and love.graphics and (drawnMap ~= mapRef or drawnVersion ~= mapRef.version) then
    if canvas then
      canvas:release()
    end
    canvas = buildCanvas(mapRef)
    drawnMap, drawnVersion = mapRef, mapRef.version
  end
  if not mapRef then
    height = Minimap.width
    scale = Minimap.width / Minimap.radarRange
  end
end

function Minimap:enterGame()
  refresh()
end

function Minimap:update(_dt, _client, cam)
  camera = cam
  refresh()
end

function Minimap:keypressed(key)
  if Controls.is("minimap", key) then
    self.visible = not self.visible
  end
end

--- World -> minimap pixel, relative to the minimap's top-left.
local function project(x, y, me)
  if mapRef then
    return (x - mapRef.left) * scale, (y - mapRef.top) * scale
  end
  local cx, cy = me and me.dx or 0, me and me.dy or 0
  return Minimap.width / 2 + (x - cx) * scale, height / 2 + (y - cy) * scale
end

function Minimap:drawHUD(client)
  if not self.visible then
    return
  end
  local w, h = love.graphics.getDimensions()
  local x0 = w - self.width - self.margin
  local y0 = self.top
  local mx, my = client:myPose()
  local me = mx and { dx = mx, dy = my } or nil -- the radar's centre when there is no map

  love.graphics.push()
  love.graphics.translate(x0, y0)

  -- Backing and map.
  love.graphics.setColor(0, 0, 0, self.alpha * 0.6)
  love.graphics.rectangle("fill", -3, -3, self.width + 6, height + 6)
  if canvas then
    love.graphics.setColor(1, 1, 1, self.alpha)
    love.graphics.draw(canvas, 0, 0)
  else
    love.graphics.setColor(C.asphalt[1], C.asphalt[2], C.asphalt[3], self.alpha)
    love.graphics.rectangle("fill", 0, 0, self.width, height)
    love.graphics.setColor(1, 1, 1, 0.12)
    love.graphics.circle("line", self.width / 2, height / 2, self.width / 4)
    love.graphics.circle("line", self.width / 2, height / 2, self.width / 2)
  end

  -- Clip everything else to the map area.
  love.graphics.setScissor(x0, y0, self.width, height)

  -- Camera viewport.
  if camera then
    local s = camera.scale or 1
    local vx, vy = project(camera.x - w / 2 / s, camera.y - h / 2 / s, me)
    love.graphics.setColor(1, 1, 1, 0.35)
    love.graphics.rectangle("line", vx, vy, w / s * scale, h / s * scale)
  end

  -- Parked cars, small and in their colour; my own cars ringed in white,
  -- parked or not, unless I am the one driving (then I am the dot on it).
  for _, v in pairs(client.vehicles) do
    local mine = v.owner == client.myId and v.driver ~= client.myId
    if not v.driver or mine then
      local px, py = project(v.dx, v.dy, me)
      if mine then
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.rectangle("fill", px - 4, py - 4, 8, 8)
      end
      love.graphics.setColor(Car.paletteColor(v.color))
      love.graphics.rectangle("fill", px - 2, py - 2, 4, 4)
    end
  end
  -- Players, driving or walking.
  for id in pairs(client.players) do
    local x, y, _, angle = client:pose(id)
    if x then
      local px, py = project(x, y, me)
      local col = Car.colorFor(id)
      if id == client.myId then
        love.graphics.setColor(1, 1, 1)
        love.graphics.circle("fill", px, py, 4.5)
        love.graphics.setColor(col)
        love.graphics.circle("fill", px, py, 3)
        love.graphics.setColor(1, 1, 1)
        love.graphics.setLineWidth(2)
        love.graphics.line(px, py, px + math.cos(angle) * 8, py + math.sin(angle) * 8)
        love.graphics.setLineWidth(1)
      else
        love.graphics.setColor(0, 0, 0, 0.7)
        love.graphics.circle("fill", px, py, 4)
        love.graphics.setColor(col)
        love.graphics.circle("fill", px, py, 3)
      end
    end
  end

  love.graphics.setScissor()

  -- Frame.
  love.graphics.setColor(C.frame[1], C.frame[2], C.frame[3], self.alpha)
  love.graphics.rectangle("line", 0, 0, self.width, height)

  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- For tests.
function Minimap.project(x, y, me)
  return project(x, y, me)
end

return Minimap
