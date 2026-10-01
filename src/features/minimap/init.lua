-- Minimap: a small map in the top-right corner. Shows the city (drawn
-- once from the city-map layout), every real player as a dot in their
-- colour (driving or walking), police units in blue (flashing red and
-- blue while you are wanted), you
-- with a heading tick, parked cars as small squares (your own ringed in
-- white, so you can always find them), and the rectangle the camera
-- currently sees. Civilian bots are left off: they are scenery (the edge
-- arrows leave them out too). Without the city-map feature it becomes a
-- radar centred on you. Other features mark things on it through the
-- `drawOnMinimap(client, toMap, w, h)` hook, under the people (the events
-- feature flashes it red where a boss comes into the city and marks him
-- while he is loose; buildings shows every owned plot and what is on it).
--
-- Tab hides and shows it; a line under it (or in its place, while it is
-- hidden) says so, and another under it offers the big map either way.
--
-- M opens the big map: the same city filling most of the window, drawn
-- sharp at that size, with the other players' names, a heading arrow for
-- you, a compass and a legend, and the same marks from other features. It
-- goes over the whole HUD (the core's `drawScreen`), softens the world
-- behind it (`worldBlur`) and keeps the mouse (`pointerTaken`), so a click
-- on it fires nothing. M again or Esc (`closeMenu`) closes it, and so does
-- the inventory opening. It doesn't open over another screen that has the
-- mouse (the shop, the job board). You can keep driving with it up.
--
-- Purely local.

local Features = require("src.features")
local Car = require("src.car")
local Controls = require("src.controls")
local UI = require("src.ui")

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
Minimap.bigOpen = false -- the big map is up
Minimap.bigMargin = 70 -- px the big map keeps from the window's sides
Minimap.bigTop = 64 -- px above it for the title
Minimap.bigBottom = 70 -- px under it for the legend
Minimap.policeColor = { 0.25, 0.45, 1 } -- the arrows' police blue
Minimap.sirenColor = { 1, 0.2, 0.2 } -- what it flashes with

local canvas, mapRef, scale, height = nil, nil, 1, 0
local drawnMap, drawnVersion = nil, nil -- the map and map.version the canvas shows
local big = nil -- { canvas, scale, w, h, map, version }: the big map, drawn at its size
local camera = nil
local time = 0

local C = {
  asphalt = { 0.17, 0.17, 0.19 },
  walk = { 0.40, 0.40, 0.43 },
  grass = { 0.28, 0.46, 0.25 },
  ground = { 0.30, 0.40, 0.24 },
  lot = { 0.22, 0.22, 0.24 },
  plot = { 0.45, 0.37, 0.27 },
  water = { 0.14, 0.26, 0.30 },
  frame = { 0.85, 0.85, 0.85 },
  outside = { 0.08, 0.08, 0.09 },
}

--- Draw the city layout into a canvas `width` px wide. Returns the canvas,
--- the world-to-canvas scale and its height. `smooth` filters it linearly
--- (the big map); the minimap stays crisp.
local function buildCanvas(map, width, smooth)
  local T = 64
  local s = width / map.w
  local h = math.floor(map.h * s)
  local c = love.graphics.newCanvas(width, h, { msaa = smooth and 4 or 0 })
  if not smooth then
    c:setFilter("nearest", "nearest")
  end
  love.graphics.push("all")
  love.graphics.origin()
  love.graphics.setCanvas(c)
  love.graphics.clear(C.outside[1], C.outside[2], C.outside[3], 1)
  love.graphics.scale(s)
  love.graphics.translate(-map.left, -map.top)
  -- Every tile in its colour (an empty map has no blocks to draw; a map
  -- drawn its own way, like City 17, has paving, roads and water too).
  local tileColor = { ground = C.ground, walk = C.walk, road = C.asphalt, water = C.water }
  for tc = map.c0, map.c1 do
    local col = map.tiles[tc]
    for tr = map.r0, map.r1 do
      local kind = col and tileColor[col[tr]]
      if kind then
        love.graphics.setColor(kind)
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
  if smooth then
    -- The big map has room for the lane markings: a faint dashed line down
    -- the middle of every street round a block.
    love.graphics.setColor(0.75, 0.68, 0.3, 0.35)
    love.graphics.setLineWidth(4)
    for _, b in ipairs(map.blocks) do
      local x0, y0 = map.x0 + (b.tx - 2) * T, map.y0 + (b.ty - 2) * T
      local x1, y1 = map.x0 + (b.tx + 8) * T, map.y0 + (b.ty + 8) * T
      for k = 0, 9 do
        local a, e = x0 + k * T + 16, x0 + k * T + 48
        love.graphics.line(a, y0, e, y0)
        love.graphics.line(a, y1, e, y1)
        a, e = y0 + k * T + 16, y0 + k * T + 48
        love.graphics.line(x0, a, x0, e)
        love.graphics.line(x1, a, x1, e)
      end
    end
    love.graphics.setLineWidth(1)
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
    if smooth then
      -- A shadow to the lower right, and the roof a touch lighter at the edge.
      love.graphics.setColor(0, 0, 0, 0.35)
      love.graphics.rectangle("fill", b.x + 12, b.y + 12, b.w, b.h)
    end
    love.graphics.setColor(b.color)
    love.graphics.rectangle("fill", b.x, b.y, b.w, b.h)
    if smooth then
      love.graphics.setColor(1, 1, 1, 0.12)
      love.graphics.setLineWidth(8)
      love.graphics.rectangle("line", b.x + 4, b.y + 4, b.w - 8, b.h - 8)
      love.graphics.setLineWidth(1)
    end
  end
  -- Whatever else the map marks for the minimap: anything in `map.cover`
  -- with a `mapColor`, round if it says so.
  for _, o in ipairs(map.cover or {}) do
    if o.mapColor then
      love.graphics.setColor(o.mapColor)
      if o.round then
        love.graphics.circle("fill", o.x + o.w / 2, o.y + o.h / 2, o.w / 2, 32)
      else
        love.graphics.rectangle("fill", o.x, o.y, o.w, o.h)
      end
    end
  end
  love.graphics.setCanvas()
  love.graphics.pop()
  return c, s, h
end

function Minimap:load()
  Controls.register("minimap", "Toggle minimap", "tab")
  Controls.register("map", "Open / close the big map", "m")
end

--- Follow the city map, redrawing when it is replaced or grows.
local function refresh()
  local city = Features.byName["city-map"]
  mapRef = city and city.map or nil
  if mapRef and love.graphics and (drawnMap ~= mapRef or drawnVersion ~= mapRef.version) then
    if canvas then
      canvas:release()
    end
    canvas, scale, height = buildCanvas(mapRef, Minimap.width, false)
    drawnMap, drawnVersion = mapRef, mapRef.version
  end
  if not mapRef then
    height = Minimap.width
    scale = Minimap.width / Minimap.radarRange
  end
end

--- The big map's canvas, (re)drawn for the window as it is now: as large as
--- fits between the margins, keeping the city's shape. Nil without a map.
local function bigMap()
  if not mapRef then
    return nil
  end
  local w, h = love.graphics.getDimensions()
  local availW = w - 2 * Minimap.bigMargin
  local availH = h - Minimap.bigTop - Minimap.bigBottom
  local width = math.max(100, math.floor(math.min(availW, availH * mapRef.w / mapRef.h)))
  if not big or big.map ~= mapRef or big.version ~= mapRef.version or big.w ~= width then
    if big then
      big.canvas:release()
    end
    local c, s, ch = buildCanvas(mapRef, width, true)
    big = { canvas = c, scale = s, w = width, h = ch, map = mapRef, version = mapRef.version }
  end
  return big
end

function Minimap:enterGame()
  self.bigOpen = false
  refresh()
end

function Minimap:exitGame()
  self.bigOpen = false
end

function Minimap:update(dt, _client, cam)
  camera = cam
  time = time + dt
  refresh()
end

function Minimap:keypressed(key, client)
  if Controls.is("minimap", key) then
    self.visible = not self.visible
  elseif Controls.is("map", key) then
    if self.bigOpen then
      self.bigOpen = false
    elseif not Features.any("pointerTaken", client) and not Features.any("menuOpen", client) then
      self.bigOpen = true -- not over another screen: the shop, the job board, a building's menu
    end
  end
end

--- The `closeMenu` convention: Esc (or the inventory opening) closes the big map.
function Minimap:closeMenu()
  if not self.bigOpen then
    return false
  end
  self.bigOpen = false
  return true
end

--- The `pointerTaken` convention: the mouse is ours while the big map is up.
function Minimap:pointerTaken()
  return self.bigOpen
end

--- The world softens under the big map.
function Minimap:worldBlur()
  return self.bigOpen and 0.8 or 0
end

--- World -> minimap pixel, relative to the minimap's top-left.
local function project(x, y, me)
  if mapRef then
    return (x - mapRef.left) * scale, (y - mapRef.top) * scale
  end
  local cx, cy = me and me.dx or 0, me and me.dy or 0
  return Minimap.width / 2 + (x - cx) * scale, height / 2 + (y - cy) * scale
end

--- What player `id` is on a map: "me", "police", "player", or nil for a
--- civilian bot or someone out of sight (the `hidden` convention: the
--- chicken ability), who are left off.
local function whoIs(client, id)
  if id == client.myId then
    return "me"
  end
  local bots, police = Features.byName.bots, Features.byName.police
  if (bots and bots.ids and bots.ids[id]) or Features.any("hidden", client, id) then
    return nil
  end
  if police and police.units and police.units[id] then
    return "police"
  end
  return "player"
end

--- Am I wanted (police says so: POL_WANTED)? The police markers flash
--- only then.
local function wanted(client)
  local police = Features.byName.police
  return police ~= nil and police.wanted ~= nil and police.wanted[client.myId] == true
end

--- A police unit's marker: a blue dot, flashing blue and red while I am
--- wanted (`hot`).
local function policeDot(px, py, r, hot)
  local red = hot and math.floor(time * 4) % 2 == 1
  love.graphics.setColor(0, 0, 0, 0.75)
  love.graphics.circle("fill", px, py, r + 1.5)
  love.graphics.setColor(red and Minimap.sirenColor or Minimap.policeColor)
  love.graphics.circle("fill", px, py, r)
end

--- The parked cars and the people, through `toMap`; `r` is a dot's radius
--- and `names` puts each other player's name over their dot (the big map).
local function drawPeople(client, toMap, r, names)
  -- Parked cars, small and in their colour; my own cars ringed in white,
  -- parked or not, unless I am the one driving (then I am the dot on it).
  for _, v in pairs(client.vehicles) do
    local mine = v.owner == client.myId and v.driver ~= client.myId
    if not v.driver or mine then
      local px, py = toMap(v.dx, v.dy)
      local s = r * 0.6
      if mine then
        love.graphics.setColor(1, 1, 1, 0.95)
        love.graphics.rectangle("fill", px - s - 2, py - s - 2, 2 * s + 4, 2 * s + 4)
      end
      local c = Car.paletteColor(v.color)
      love.graphics.setColor(c[1], c[2], c[3], mine and 1 or 0.8)
      love.graphics.rectangle("fill", px - s, py - s, 2 * s, 2 * s)
    end
  end
  -- People, driving or walking: the others first, then me on top.
  local mine
  local hot = wanted(client)
  for id in pairs(client.players) do
    local x, y, _, angle = client:pose(id)
    local who = x and whoIs(client, id)
    if who == "me" then
      mine = { x = x, y = y, angle = angle }
    elseif who == "police" then
      local px, py = toMap(x, y)
      policeDot(px, py, r, hot)
    elseif who == "player" then
      local px, py = toMap(x, y)
      love.graphics.setColor(0, 0, 0, 0.7)
      love.graphics.circle("fill", px, py, r + 1)
      love.graphics.setColor(Car.colorFor(id))
      love.graphics.circle("fill", px, py, r)
      if names then
        local name = client:nameOf(id) or ("player " .. id)
        love.graphics.setFont(UI.fonts.small)
        local tw = UI.fonts.small:getWidth(name)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", px - tw / 2 - 4, py - r - 22, tw + 8, 18, 4)
        love.graphics.setColor(Car.colorFor(id))
        love.graphics.print(name, px - tw / 2, py - r - 21)
      end
    end
  end
  if mine then
    local px, py = toMap(mine.x, mine.y)
    local col = Car.colorFor(client.myId)
    if names then
      -- The big map: a ring pulsing out from me and an arrow the way I face.
      local k = (time * 0.8) % 1
      love.graphics.setColor(1, 1, 1, (1 - k) * 0.6)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", px, py, r + 4 + k * 22)
      local a, s = mine.angle, r * 2.2
      local tip = { px + math.cos(a) * s, py + math.sin(a) * s }
      local left = { px + math.cos(a + 2.5) * s * 0.8, py + math.sin(a + 2.5) * s * 0.8 }
      local right = { px + math.cos(a - 2.5) * s * 0.8, py + math.sin(a - 2.5) * s * 0.8 }
      love.graphics.setColor(1, 1, 1) -- two halves: a polygon fill is convex only
      love.graphics.polygon("fill", tip[1], tip[2], left[1], left[2], px, py)
      love.graphics.polygon("fill", tip[1], tip[2], px, py, right[1], right[2])
      love.graphics.setColor(col)
      love.graphics.circle("fill", px, py, r * 0.75)
      love.graphics.setLineWidth(1)
    else
      love.graphics.setColor(1, 1, 1)
      love.graphics.circle("fill", px, py, r + 1.5)
      love.graphics.setColor(col)
      love.graphics.circle("fill", px, py, r)
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(2)
      love.graphics.line(px, py, px + math.cos(mine.angle) * 8, py + math.sin(mine.angle) * 8)
      love.graphics.setLineWidth(1)
    end
  end
end

--- A hint line in the minimap's corner, right-aligned to its edge.
local function hint(text, y)
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.small)
  local x = w - Minimap.margin - Minimap.width
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, x + 1, y + 1, Minimap.width, "right")
  love.graphics.setColor(0.85, 0.85, 0.9, 0.85)
  love.graphics.printf(text, x, y, Minimap.width, "right")
end

function Minimap:drawHUD(client)
  local keyName = Controls.name(Controls.bindings("minimap")[1])
  local mapKey = Controls.name(Controls.bindings("map")[1])
  if self.bigOpen then
    return -- the big map has it all
  elseif not self.visible then
    hint(keyName .. ": open minimap", self.top)
    hint(mapKey .. ": big map", self.top + 18)
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

  local function toMap(x, y)
    return project(x, y, me)
  end
  -- Whatever other features mark on it (the players' buildings among
  -- them), clipped to it like the rest and under the people, as on the big
  -- map. `toMap(x, y)` turns a world point into a minimap pixel.
  Features.call("drawOnMinimap", client, toMap, self.width, height)
  drawPeople(client, toMap, 3, false)

  love.graphics.setScissor()

  -- Frame.
  love.graphics.setColor(C.frame[1], C.frame[2], C.frame[3], self.alpha)
  love.graphics.rectangle("line", 0, 0, self.width, height)

  love.graphics.pop()

  hint(keyName .. ": close minimap", y0 + height + 6)
  hint(mapKey .. ": big map", y0 + height + 24)
  love.graphics.setColor(1, 1, 1)
end

--- One entry of the big map's legend at (x, y): its marker drawn by `mark`
--- and its label. Returns the x after it.
local function legendItem(x, y, mark, label)
  mark(x + 7, y + 9)
  love.graphics.setColor(0.85, 0.85, 0.9)
  love.graphics.print(label, x + 20, y)
  return x + 20 + UI.fonts.small:getWidth(label) + 22
end

--- The compass rose in a corner of the big map: N at the top, the city's
--- north being up.
local function compass(cx, cy)
  love.graphics.setColor(0, 0, 0, 0.55)
  love.graphics.circle("fill", cx, cy, 20)
  love.graphics.setColor(1, 1, 1, 0.3)
  love.graphics.circle("line", cx, cy, 20)
  love.graphics.setColor(0.95, 0.3, 0.3)
  love.graphics.polygon("fill", cx, cy - 15, cx - 5, cy, cx + 5, cy)
  love.graphics.setColor(0.9, 0.9, 0.95)
  love.graphics.polygon("fill", cx, cy + 15, cx - 5, cy, cx + 5, cy)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf("N", cx - 20, cy - 38, 40, "center")
end

--- The big map, over the whole HUD (the core's `drawScreen`).
function Minimap:drawScreen(client)
  if not self.bigOpen then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setColor(0, 0, 0, 0.9) -- dark enough that the HUD under it fades away
  love.graphics.rectangle("fill", 0, 0, w, h)
  local closeKey = Controls.name(Controls.bindings("map")[1])
  local B = bigMap()
  if not B then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0.9, 0.9, 0.95)
    love.graphics.printf("No map of this place.   " .. closeKey .. ": close", 0, h / 2 - 10, w, "center")
    return
  end
  local x0 = math.floor((w - B.w) / 2)
  local y0 = math.floor(self.bigTop + (h - self.bigTop - self.bigBottom - B.h) / 2)

  -- Title: the place.
  local city = Features.byName["city-map"]
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf((city and city.map.title or "Map"):upper(), 0, y0 - 44, w, "center")

  -- Frame with a soft shadow, then the city.
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", x0 - 6 + 8, y0 - 6 + 8, B.w + 12, B.h + 12, 10)
  love.graphics.setColor(0.12, 0.12, 0.15)
  love.graphics.rectangle("fill", x0 - 6, y0 - 6, B.w + 12, B.h + 12, 10)
  love.graphics.setColor(1, 1, 1)
  love.graphics.draw(B.canvas, x0, y0)

  love.graphics.push()
  love.graphics.translate(x0, y0)
  love.graphics.setScissor(x0, y0, B.w, B.h)
  local function toMap(x, y)
    return (x - mapRef.left) * B.scale, (y - mapRef.top) * B.scale
  end
  -- What the camera sees right now.
  if camera then
    local s = camera.scale or 1
    local vx, vy = toMap(camera.x - w / 2 / s, camera.y - h / 2 / s)
    love.graphics.setColor(1, 1, 1, 0.25)
    love.graphics.setLineWidth(1.5)
    love.graphics.rectangle("line", vx, vy, w / s * B.scale, h / s * B.scale, 4)
    love.graphics.setLineWidth(1)
  end
  Features.call("drawOnMinimap", client, toMap, B.w, B.h)
  drawPeople(client, toMap, 6, true)
  love.graphics.setScissor()
  love.graphics.pop()

  love.graphics.setColor(0.45, 0.95, 0.6, 0.7)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", x0 - 6, y0 - 6, B.w + 12, B.h + 12, 10)
  love.graphics.setLineWidth(1)
  compass(x0 + B.w - 34, y0 + 48)

  -- The legend under it, and how to close it.
  love.graphics.setFont(UI.fonts.small)
  local items = {
    { function(x, y)
      love.graphics.setColor(1, 1, 1)
      love.graphics.polygon("fill", x + 8, y, x - 5, y - 6, x - 2, y)
      love.graphics.polygon("fill", x + 8, y, x - 2, y, x - 5, y + 6)
    end, "you" },
    { function(x, y)
      love.graphics.setColor(0.9, 0.55, 0.2)
      love.graphics.circle("fill", x, y, 5)
    end, "players" },
    { function(x, y)
      policeDot(x, y, 5, wanted(client))
    end, "police cars" },
    { function(x, y)
      love.graphics.setColor(0, 0, 0, 0.75)
      love.graphics.circle("fill", x, y, 5)
      love.graphics.setColor(0.25, 0.45, 1)
      love.graphics.circle("fill", x, y, 4)
    end, "officers" },
    { function(x, y)
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("fill", x - 6, y - 6, 12, 12)
      love.graphics.setColor(Car.colorFor(client.myId))
      love.graphics.rectangle("fill", x - 4, y - 4, 8, 8)
    end, "your cars" },
    { function(x, y)
      love.graphics.setColor(0.6, 0.6, 0.65)
      love.graphics.rectangle("fill", x - 3, y - 3, 6, 6)
    end, "parked cars" },
    { function(x, y)
      love.graphics.setColor(0.7, 0.3, 0.22)
      love.graphics.rectangle("fill", x - 6, y - 6, 12, 12)
      love.graphics.setColor(1, 1, 1)
      love.graphics.setLineWidth(2)
      love.graphics.rectangle("line", x - 7, y - 7, 14, 14)
      love.graphics.setLineWidth(1)
    end, "your buildings" },
    { function(x, y)
      love.graphics.setColor(1, 1, 1)
      love.graphics.rectangle("fill", x - 2, y - 6, 4, 12)
      love.graphics.rectangle("fill", x - 6, y - 2, 12, 4)
      love.graphics.setColor(0.85, 0.12, 0.14)
      love.graphics.rectangle("fill", x - 1, y - 5, 2, 10)
      love.graphics.rectangle("fill", x - 5, y - 1, 10, 2)
    end, "hospital" },
  }
  local total = 0
  for _, it in ipairs(items) do
    total = total + 42 + UI.fonts.small:getWidth(it[2])
  end
  local lx, ly = math.floor((w - total) / 2), y0 + B.h + 16
  for _, it in ipairs(items) do
    lx = legendItem(lx, ly, it[1], it[2])
  end
  love.graphics.setColor(0.6, 0.6, 0.65)
  love.graphics.printf(closeKey .. " or Esc: close map", 0, ly + 26, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- For tests.
function Minimap.project(x, y, me)
  return project(x, y, me)
end

return Minimap
