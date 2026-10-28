-- Night: a map marked `night` (city-map's maps: Grey City's, the Cyber Feud
-- quest line's) is played in the dark. Every frame a light map the size of
-- the window is drawn: a dim blue ambient, and on top of it, added, the
-- map's own lights (`map.lights`: neon, lamps, screens), every driven car's
-- headlights and tail lights, a pool round everyone on foot with a torch
-- beam where they face, and whatever other features light up. The world is
-- then multiplied by it, under the HUD, so what is lit shows in its own
-- colours and the rest falls away into the dark.
--
-- A map's `night` may be a colour { r, g, b } instead of true: that map's
-- own ambient, what its dark leaves of the world (Fobos Base's is red).
--
-- Another feature lights something with `drawNightLights(client, camera,
-- glow)`: called in world space while the light map is drawn, additive;
-- `glow(x, y, r, color, a)` puts a soft round light there (quests lights
-- its stars this way).
--
-- Purely local: nothing is sent, nothing changes in the world.

local Features = require("src.features")

local Night = {
  name = "night",
  priority = 400, -- drawLens under the weapons' low-health halo and scope (950)
}

-- Tuning ------------------------------------------------------------------
Night.ambient = { 0.34, 0.36, 0.50 } -- what the dark leaves of the world, by channel
Night.headlight = { 1.00, 0.95, 0.82 }
Night.headlightReach = 520 -- px of beam ahead of a car
Night.tail = { 1.00, 0.15, 0.12 }
Night.walker = { 0.70, 0.78, 1.00 } -- the pool of light round someone on foot
Night.walkerRadius = 150
Night.torchReach = 300 -- px of torch beam ahead of someone on foot
Night.margin = 80 -- px past the edge of the view a light may reach in from

local glowImage, coneImage = nil, nil
local canvas = nil
local camera = nil

--- A white disc fading out from the middle, `size` px across.
local function makeGlow(size)
  local data = love.image.newImageData(size, size)
  local half = size / 2
  data:mapPixel(function(x, y)
    local d = math.sqrt((x + 0.5 - half) ^ 2 + (y + 0.5 - half) ^ 2) / half
    local a = math.max(0, 1 - d)
    return 1, 1, 1, a * a
  end)
  local img = love.graphics.newImage(data)
  img:setFilter("linear", "linear")
  return img
end

--- A beam: from a point on the middle of the left edge, widening to the
--- right, fading with distance and towards its sides.
local function makeCone(w, h, spread)
  local data = love.image.newImageData(w, h)
  local half = h / 2
  data:mapPixel(function(x, y)
    local d = (x + 0.5) / w
    local side = math.abs(y + 0.5 - half) / half
    local width = math.max(0.06, d * spread)
    local across = math.max(0, 1 - side / width)
    local a = across ^ 0.7 * (1 - d) ^ 1.4 * math.min(1, d * 12)
    return 1, 1, 1, a
  end)
  local img = love.graphics.newImage(data)
  img:setFilter("linear", "linear")
  return img
end

function Night:load()
  if not love.graphics then
    return
  end
  glowImage = makeGlow(128)
  coneImage = makeCone(256, 128, 0.9)
end

local function map()
  local city = Features.byName["city-map"]
  return city and city.map
end

--- Is the map in play dark?
function Night:dark()
  local m = map()
  return m ~= nil and (m.night == true or type(m.night) == "table")
end

function Night:update(_dt, _client, cam)
  camera = cam
end

function Night:exitGame()
  if canvas then
    canvas:release()
    canvas = nil
  end
end

--- The view in world px, with a margin: x0, y0, x1, y1.
local function view(w, h)
  local s = camera.scale or 1
  local hw, hh = w / 2 / s + Night.margin, h / 2 / s + Night.margin
  return camera.x - hw, camera.y - hh, camera.x + hw, camera.y + hh
end

--- A soft round light of radius `r` at (x, y), in `color` at strength `a`.
local function glow(x, y, r, color, a)
  love.graphics.setColor(color[1], color[2], color[3], a or 1)
  local k = r * 2 / glowImage:getWidth()
  love.graphics.draw(glowImage, x, y, 0, k, k, glowImage:getWidth() / 2, glowImage:getHeight() / 2)
end

--- A beam from (x, y) along `angle`, `reach` px long.
local function beam(x, y, angle, reach, color, a)
  love.graphics.setColor(color[1], color[2], color[3], a)
  local k = reach / coneImage:getWidth()
  love.graphics.draw(coneImage, x, y, angle, k, k, 0, coneImage:getHeight() / 2)
end

local function drawLights(client, x0, y0, x1, y1)
  for _, l in ipairs(map().lights or {}) do
    if l.x + l.r > x0 and l.x - l.r < x1 and l.y + l.r > y0 and l.y - l.r < y1 then
      glow(l.x, l.y, l.r, l.color, l.a)
    end
  end
  -- Cars being driven: headlights ahead, tail lights behind.
  for _, c in pairs(client.vehicles) do
    if c.driver and c.dx and c.dx > x0 - 500 and c.dx < x1 + 500 and c.dy > y0 - 500 and c.dy < y1 + 500
      and not Features.any("hidden", client, c.driver) then
      local fx, fy = math.cos(c.dangle), math.sin(c.dangle)
      local sx, sy = -fy, fx
      for _, side in ipairs({ -1, 1 }) do
        local hx, hy = c.dx + fx * 22 + sx * side * 7, c.dy + fy * 22 + sy * side * 7
        beam(hx, hy, c.dangle, Night.headlightReach, Night.headlight, 0.7)
        glow(hx, hy, 26, Night.headlight, 0.9)
        glow(c.dx - fx * 24 + sx * side * 8, c.dy - fy * 24 + sy * side * 8, 30, Night.tail, 0.7)
      end
      glow(c.dx, c.dy, 70, Night.headlight, 0.3)
    end
  end
  -- Everyone on foot: a pool round them and a torch where they face.
  for id, b in pairs(client.bodies) do
    if b.dx and b.dx > x0 - 300 and b.dx < x1 + 300 and b.dy > y0 - 300 and b.dy < y1 + 300
      and not Features.any("hidden", client, id) then
      local mine = id == client.myId
      glow(b.dx, b.dy, Night.walkerRadius * (mine and 1.3 or 1), Night.walker, mine and 0.6 or 0.45)
      beam(b.dx, b.dy, b.dangle or 0, Night.torchReach, Night.headlight, 0.4)
    end
  end
  Features.call("drawNightLights", client, camera, glow)
end

--- Darken the world drawn so far, under the HUD.
function Night:drawLens(client)
  if not (glowImage and camera and self:dark()) then
    return
  end
  local w, h = love.graphics.getDimensions()
  if not canvas or canvas:getWidth() ~= w or canvas:getHeight() ~= h then
    if canvas then
      canvas:release()
    end
    canvas = love.graphics.newCanvas(w, h)
  end
  love.graphics.push("all")
  love.graphics.setCanvas(canvas)
  local own = map().night
  local ambient = type(own) == "table" and own or Night.ambient
  love.graphics.clear(ambient[1], ambient[2], ambient[3], 1)
  love.graphics.setBlendMode("add")
  love.graphics.origin()
  love.graphics.translate(math.floor(w / 2), math.floor(h / 2))
  love.graphics.scale(camera.scale or 1)
  love.graphics.translate(-math.floor(camera.x), -math.floor(camera.y))
  drawLights(client, view(w, h))
  love.graphics.pop()

  love.graphics.push("all")
  love.graphics.setBlendMode("multiply", "premultiplied")
  love.graphics.setColor(1, 1, 1, 1)
  love.graphics.draw(canvas, 0, 0)
  love.graphics.pop()
end

return Night
