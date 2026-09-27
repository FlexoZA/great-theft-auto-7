-- The city's own buildings, the ones nobody has taken over, in the look the
-- hospital, the storefronts and the players' buildings have: a roof behind
-- a parapet lit from the top left, things standing on it with their
-- shadows, and a front on the street side. Drawn once into the map canvas,
-- so nothing here moves.
--
-- Downtown has three looks, picked by the building's `style`: offices (panel
-- seams, air conditioners, a lift house and a water tank, a glass front),
-- apartments (gravel, a stair hut, satellite dishes, vent pipes, a roof
-- garden on the big ones, balconies along the front) and shops (a ribbed
-- roof with skylights and turbine vents, a lit window under a striped
-- awning). The cul-de-sac's houses get pitched roofs with a chimney, solar
-- panels or a skylight, a porch and a path to the sidewalk.

local Layout = require("src.features.city-map.layout")

local Buildings = {}

local T = Layout.TILE
local AC = { 0.60, 0.62, 0.64 }
local GLASS = { 0.62, 0.85, 0.95 }
local FRAME = { 0.24, 0.30, 0.36 }
local SLAB = { 0.70, 0.70, 0.68 }
local PAVING = { 0.62, 0.60, 0.56 }
local BRICK = { 0.55, 0.30, 0.24 }
local SOIL = { 0.36, 0.26, 0.18 }
local LEAF = { 0.24, 0.50, 0.24 }
local DECK = { 0.58, 0.44, 0.30 }
local SOLAR = { 0.14, 0.20, 0.36 }
local DARK = { 0.08, 0.08, 0.09 }
local AWNINGS = {
  { { 0.80, 0.22, 0.20 }, { 0.95, 0.92, 0.85 } },
  { { 0.20, 0.55, 0.32 }, { 0.95, 0.92, 0.85 } },
  { { 0.22, 0.40, 0.72 }, { 0.92, 0.94, 0.96 } },
  { { 0.90, 0.55, 0.15 }, { 0.40, 0.26, 0.16 } },
  { { 0.55, 0.25, 0.60 }, { 0.95, 0.90, 0.95 } },
}

-- Towards the light (the world's top left) and away from it, in the frame
-- the building is being drawn in; set by `inFrame`.
local LX, LY = -1, -1

local function shade(c, k)
  return { math.min(1, c[1] * k), math.min(1, c[2] * k), math.min(1, c[3] * k) }
end

local function rect(x, y, w, h, c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
  love.graphics.rectangle("fill", x, y, w, h)
end

local function shadowRect(x, y, w, h, height)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - LX * height, y - LY * height, w, h)
end

local function shadowCircle(x, y, r, height)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x - LX * height, y - LY * height, r)
end

--- The same number in 0..1 for `i` every time, for scatter.
local function hash(i)
  local v = math.sin(i * 12.9898 + 78.233) * 43758.5453
  return v - math.floor(v)
end

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

--- Run `fn(W, D)` in a frame centred on `b` and turned so its front (the
--- side facing `nx, ny`) is at the bottom: x runs along the front, y from
--- the back (-D/2) to the front (D/2). Quarter turns only, so the pixels
--- stay square.
local function inFrame(b, nx, ny, fn)
  local angle, W, D
  if ny ~= 0 then
    angle, W, D = ny > 0 and 0 or math.pi, b.w, b.h
  else
    angle, W, D = nx > 0 and -math.pi / 2 or math.pi / 2, b.h, b.w
  end
  local c, s = math.cos(angle), math.sin(angle)
  LX = (-c - s) < 0 and -1 or 1
  LY = (s - c) < 0 and -1 or 1
  love.graphics.push()
  love.graphics.translate(b.x + b.w / 2, b.y + b.h / 2)
  love.graphics.rotate(angle)
  fn(W, D)
  love.graphics.pop()
end

--- A box standing `height` px off the roof: its shadow, a darker rim and
--- the edges facing the light picked out.
local function raised(x, y, w, h, c, height)
  shadowRect(x, y, w, h, height)
  rect(x, y, w, h, shade(c, 0.75))
  rect(x + 3, y + 3, w - 6, h - 6, c)
  local lit = shade(c, 1.22)
  rect(LX < 0 and x + 3 or x + w - 6, y + 3, 3, h - 6, lit)
  rect(x + 3, LY < 0 and y + 3 or y + h - 6, w - 6, 3, lit)
end

--- An air conditioner, its fan stopped at some angle, centred on (x, y).
local function aircon(x, y, seed)
  shadowRect(x - 11, y - 11, 22, 22, 4)
  rect(x - 11, y - 11, 22, 22, AC)
  love.graphics.setColor(shade(AC, 0.55))
  love.graphics.circle("fill", x, y, 8)
  love.graphics.setColor(shade(AC, 1.3))
  love.graphics.setLineWidth(2)
  for i = 0, 2 do
    local a = seed + i * 2 * math.pi / 3
    love.graphics.line(x, y, x + math.cos(a) * 7, y + math.sin(a) * 7)
  end
  love.graphics.setLineWidth(1)
end

--- A water tank on legs, centred on (x, y).
local function tank(x, y, r)
  shadowCircle(x, y, r, 10)
  love.graphics.setColor(0.42, 0.34, 0.26)
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(0.56, 0.46, 0.34)
  love.graphics.circle("fill", x, y, r - 3)
  love.graphics.setColor(0.42, 0.34, 0.26)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x, y, r * 0.55)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.3, 0.24, 0.18)
  love.graphics.circle("fill", x + LX * r * 0.3, y + LY * r * 0.3, 3)
end

--- A satellite dish, centred on (x, y), turned towards the sky's south.
local function dish(x, y, r)
  shadowCircle(x, y, r, 5)
  love.graphics.setColor(0.72, 0.73, 0.74)
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(0.88, 0.89, 0.9)
  love.graphics.circle("fill", x + LX * 2, y + LY * 2, r - 3)
  love.graphics.setColor(0.4, 0.4, 0.42)
  love.graphics.setLineWidth(2)
  love.graphics.line(x, y, x + r * 0.7, y + r * 0.7)
  love.graphics.setLineWidth(1)
  love.graphics.circle("fill", x + r * 0.7, y + r * 0.7, 2)
end

--- A vent pipe poking out of the roof.
local function pipe(x, y)
  shadowCircle(x, y, 5, 4)
  love.graphics.setColor(0.5, 0.5, 0.52)
  love.graphics.circle("fill", x, y, 5)
  love.graphics.setColor(0.15, 0.15, 0.16)
  love.graphics.circle("fill", x, y, 2.5)
end

--- A turbine vent: a round cowl with its vanes.
local function turbine(x, y)
  shadowCircle(x, y, 10, 5)
  love.graphics.setColor(0.58, 0.6, 0.62)
  love.graphics.circle("fill", x, y, 10)
  love.graphics.setColor(0.42, 0.44, 0.46)
  love.graphics.setLineWidth(2)
  for i = 0, 5 do
    local a = i * math.pi / 3
    love.graphics.line(x + math.cos(a) * 3, y + math.sin(a) * 3, x + math.cos(a + 0.6) * 9, y + math.sin(a + 0.6) * 9)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.72, 0.74, 0.76)
  love.graphics.circle("fill", x, y, 3)
end

--- A glass pane set in a frame, lit along one edge.
local function pane(x, y, w, h)
  rect(x, y, w, h, FRAME)
  rect(x + 2, y + 2, w - 4, h - 4, GLASS, 0.7)
  rect(x + 3, y + 3, (w - 6) * 0.5, 2, { 1, 1, 1 }, 0.45)
end

--- A planter box with a few shrubs in it.
local function planter(x, y, w, h, seed)
  shadowRect(x, y, w, h, 3)
  rect(x, y, w, h, BRICK)
  rect(x + 3, y + 3, w - 6, h - 6, SOIL)
  for i = 0, math.floor(w / 14) - 1 do
    local r = 4 + hash(seed + i) * 3
    love.graphics.setColor(LEAF)
    love.graphics.circle("fill", x + 8 + i * 14, y + h / 2, r)
    love.graphics.setColor(shade(LEAF, 1.3))
    love.graphics.circle("fill", x + 8 + i * 14 + LX, y + h / 2 + LY, r * 0.45)
  end
end

--- The roof of a downtown building, in the world: a darker parapet, the
--- roof inside it, lit along the top and left.
local function flatRoof(b)
  local c = b.color
  rect(b.x, b.y, b.w, b.h, shade(c, 0.6))
  rect(b.x + 6, b.y + 6, b.w - 12, b.h - 12, c)
  rect(b.x + 6, b.y + 6, b.w - 12, 6, shade(c, 1.22))
  rect(b.x + 6, b.y + 6, 6, b.h - 12, shade(c, 1.22))
  rect(b.x + 6, b.y + b.h - 10, b.w - 12, 4, shade(c, 0.85))
  rect(b.x + b.w - 10, b.y + 6, 4, b.h - 12, shade(c, 0.85))
end

--- Offices: seams between the roof panels, a row of air conditioners at
--- the back, a lift house with a water tank beside it, and a glass front.
local function office(b, W, D)
  local back, front = -D / 2 + 6, D / 2 - 26
  love.graphics.setColor(shade(b.color, 0.88))
  for x = -W / 2 + 40, W / 2 - 20, 40 do
    love.graphics.rectangle("fill", x, back + 6, 2, front - back - 6)
  end
  local n = clamp(math.floor((W - 70) / 32), 1, 6)
  for i = 0, n - 1 do
    aircon(-W / 2 + 28 + i * 32, back + 20, b.seed + i)
  end
  local lw, lh = clamp(W * 0.28, 36, 80), clamp(D * 0.24, 30, 64)
  local lx, ly = W / 2 - 16 - lw, math.min(back + 40, front - 4 - lh)
  raised(lx, ly, lw, lh, shade(b.color, 1.05), 10)
  rect(lx + lw / 2 - 7, ly + lh - 5, 14, 5, DARK)
  tank(lx - 24, ly + lh / 2, 14)
  if W >= 250 and D >= 250 then
    -- A radio mast on the big ones, guyed to the roof.
    local mx, my = -W / 2 + 50, front - 40
    love.graphics.setColor(0.35, 0.35, 0.37)
    love.graphics.setLineWidth(2)
    for _, g in ipairs({ { -18, -18 }, { 18, -18 }, { 0, 20 } }) do
      love.graphics.line(mx, my, mx + g[1], my + g[2])
    end
    love.graphics.setLineWidth(1)
    shadowCircle(mx, my, 5, 16)
    love.graphics.setColor(0.8, 0.2, 0.2)
    love.graphics.circle("fill", mx, my, 5)
    for i = 0, 2 do
      aircon(W / 2 - 40 - i * 32, front - 22, b.seed * 3 + i)
    end
  end
  -- The glass front, a band of lit panes along the street.
  local F = D / 2
  rect(-W / 2 + 6, F - 20, W - 12, 14, FRAME)
  for x = -W / 2 + 10, W / 2 - 26, 20 do
    rect(x, F - 18, 16, 10, GLASS, 0.85)
    rect(x + 2, F - 17, 6, 2, { 1, 1, 1 }, 0.5)
  end
  rect(-10, F - 20, 20, 14, DARK)
end

--- Apartments: a gravel roof with a stair hut, satellite dishes and vent
--- pipes, a roof garden on the big ones, and balconies along the front.
local function apartments(b, W, D)
  local back, front = -D / 2 + 8, D / 2 - 28
  local s = b.seed
  for i = 1, math.floor(W * (front - back) / 110) do
    local x = -W / 2 + 8 + hash(s + i * 3) * (W - 20)
    local y = back + hash(s + i * 7) * (front - back - 4)
    rect(x, y, 4, 4, shade(b.color, i % 2 == 0 and 0.84 or 1.14))
  end
  local hw, hh = 44, 36
  raised(-W / 2 + 14, back + 6, hw, hh, shade(b.color, 0.92), 12)
  rect(-W / 2 + 14 + hw / 2 - 7, back + 6 + hh - 5, 14, 5, DARK)
  dish(W / 2 - 24, back + 20, 10)
  if W >= 180 then
    dish(W / 2 - 54, back + 18, 8)
  end
  for i = 0, 2 do
    pipe(-W / 2 + 30 + hash(s + i * 11) * (W - 60), back + 56 + hash(s + i * 13) * math.max(1, front - back - 64))
  end
  if W >= 250 and D >= 250 then
    local gx, gy, gw, gh = -W / 2 + 70, back + 70, W - 140, front - back - 90
    rect(gx, gy, gw, gh, DECK)
    love.graphics.setColor(shade(DECK, 0.8))
    for y = gy + 8, gy + gh - 4, 8 do
      love.graphics.rectangle("fill", gx, y, gw, 2)
    end
    planter(gx + 10, gy + 10, gw - 20, 16, s)
    planter(gx + 10, gy + gh - 26, gw - 20, 16, s + 5)
    love.graphics.setColor(0.9, 0.9, 0.88)
    love.graphics.circle("fill", gx + gw / 2, gy + gh / 2, 10) -- a table
  end
  -- Balconies: a slab and a railing under each lit window.
  local F = D / 2
  for x = -W / 2 + 14, W / 2 - 40, 38 do
    rect(x + 4, F - 24, 20, 4, GLASS, 0.75)
    rect(x, F - 18, 28, 12, SLAB)
    rect(x, F - 8, 28, 2, DARK, 0.7)
    if hash(s + x) < 0.4 then
      love.graphics.setColor(LEAF)
      love.graphics.circle("fill", x + 6, F - 13, 3)
    end
  end
end

--- Shops and warehouses: a ribbed roof, a row of skylights, turbine
--- vents, and a lit shop window under a striped awning.
local function shop(b, W, D)
  local back, front = -D / 2 + 6, D / 2 - 30
  love.graphics.setColor(shade(b.color, 0.86))
  for x = -W / 2 + 10, W / 2 - 14, 12 do
    love.graphics.rectangle("fill", x, back + 2, 5, front - back - 2)
  end
  local sy = back + (front - back) * 0.4 - 8
  for x = -W / 2 + 22, W / 2 - 48, 44 do
    pane(x, sy, 26, 16)
  end
  turbine(-W / 2 + 26, back + 16)
  turbine(W / 2 - 26, back + 16)
  if W >= 250 then
    turbine(0, back + 16)
  end
  local F = D / 2
  local colors = AWNINGS[b.seed % #AWNINGS + 1]
  rect(-W / 2 + 8, F - 28, W - 16, 8, GLASS, 0.8)
  local n = math.max(4, math.floor((W - 20) / 16))
  local sw = (W - 20) / n
  for i = 0, n - 1 do
    local c = colors[i % 2 + 1]
    local x = -W / 2 + 10 + i * sw
    rect(x, F - 20, sw, 12, c)
    love.graphics.arc("fill", x + sw / 2, F - 8, sw / 2, 0, math.pi)
  end
  rect(-W / 2 + 10, F - 20, W - 20, 2, shade(colors[1], 0.6))
end

--- A house: a pitched roof with the ridge along the front, the slope that
--- faces the light brighter, a chimney, solar panels or a skylight, and a
--- porch over the door.
local function house(b, W, D)
  local c = b.color
  local backLit = LY < 0
  rect(-W / 2, -D / 2, W, D / 2, shade(c, backLit and 1.08 or 0.78))
  rect(-W / 2, 0, W, D / 2, shade(c, backLit and 0.78 or 1.08))
  love.graphics.setColor(0, 0, 0, 0.14)
  for y = -D / 2 + 10, D / 2 - 6, 12 do
    if math.abs(y) > 8 then
      love.graphics.rectangle("fill", -W / 2 + 4, y, W - 8, 2)
    end
  end
  love.graphics.setColor(shade(c, 0.55))
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", -W / 2 + 1.5, -D / 2 + 1.5, W - 3, D - 3)
  love.graphics.setLineWidth(1)
  rect(-W / 2 + 2, -4, W - 4, 8, shade(c, 0.62))
  rect(-W / 2 + 2, -4, W - 4, 2, shade(c, 0.95))
  local chx = -W / 2 + 26 + hash(b.seed) * (W - 72)
  raised(chx, -D / 2 + 20, 20, 20, BRICK, 14)
  rect(chx + 6, -D / 2 + 26, 8, 8, DARK)
  if b.seed % 2 == 0 then
    local pw, ph = 18, 14
    local px = W / 2 - 22 - 3 * pw
    for i = 0, 2 do
      for j = 0, 1 do
        rect(px + i * pw, 16 + j * ph, pw - 2, ph - 2, SOLAR)
        rect(px + i * pw + 2, 18 + j * ph, pw - 8, 2, { 0.5, 0.6, 0.85 }, 0.6)
      end
    end
  else
    pane(W / 2 - 50, -D / 2 + 24, 24, 20)
  end
  raised(-24, D / 2 - 8, 48, 20, shade(c, 0.7), 4)
end

--- Where tile kind (x, y) is, or nil off the map.
local function tileAt(map, x, y)
  local col = map.tiles[math.floor((x - map.x0) / T)]
  return col and col[math.floor((y - map.y0) / T)]
end

local function inside(o, x, y)
  return x >= o.x and x < o.x + o.w and y >= o.y and y < o.y + o.h
end

local SIDES = { { 0, 1 }, { 1, 0 }, { -1, 0 }, { 0, -1 } }

--- Which way `b` faces: the side with the least open ground between it
--- and a sidewalk or road, no other building in the way, the bottom first
--- when there is a tie. Returns nx, ny and the px of ground to cross.
local function frontOf(map, b)
  local cx, cy = b.x + b.w / 2, b.y + b.h / 2
  local open = { true, true, true, true }
  for step = 1, 4 do
    for i, s in ipairs(SIDES) do
      if open[i] then
        local d = step * T - T / 2
        local x, y = cx + s[1] * (b.w / 2 + d), cy + s[2] * (b.h / 2 + d)
        for _, o in ipairs(map.buildings) do
          if o ~= b and inside(o, x, y) then
            open[i] = false
            break
          end
        end
        local kind = open[i] and tileAt(map, x, y)
        if kind == "walk" or kind == "road" then
          return s[1], s[2], (step - 1) * T
        end
      end
    end
  end
  return 0, 1, 0
end

local LOOKS = { office, apartments, shop }

--- Draw every building of `map`; call with their shadows already down.
function Buildings.draw(map)
  local houses = map.kind == "culdesac"
  for _, b in ipairs(map.buildings) do
    local nx, ny, walk = frontOf(map, b)
    if houses then
      -- The path across the lawn goes down first, under the porch.
      inFrame(b, nx, ny, function(W, D)
        if walk > 0 then
          rect(-14, D / 2, 28, walk, PAVING)
          rect(-14, D / 2, 3, walk, shade(PAVING, 0.8))
        end
        house(b, W, D)
      end)
    else
      flatRoof(b)
      local look = LOOKS[(b.style or 1) % #LOOKS + 1]
      inFrame(b, nx, ny, function(W, D)
        look(b, W, D)
      end)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Buildings
