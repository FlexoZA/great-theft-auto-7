-- The city's hospital and impound lot: two of the buildings the city
-- already has, picked from the map the same way on every machine, so there
-- is nothing to send. The hospital is the biggest building near the middle
-- of town (at least four tiles a side, when there is one); the impound lot
-- is the parking lot block nearest the middle. Neither can be bought, built
-- on or shot down: they are part of the map.
--
-- `Places.of(map)` answers for a city grid ({ hospital, impound }, either
-- may be nil) and nil for any other map. It is worked out once per map
-- table; a city that grows only adds plots, which are neither.

local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")

local Places = {}

local T = Layout.TILE
local BIG = 4 * T -- px a side a building needs to be the hospital when there is a choice
local BAY_PITCH = 48 -- px between the parking lot's bay lines (city-map/render.lua)
local cache = setmetatable({}, { __mode = "k" }) -- map -> places, or false for none

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function blockRect(map, b)
  return map.x0 + b.tx * T, map.y0 + b.ty * T, b.tw * T, b.th * T
end

local function inside(x, y, w, h, r)
  return r.x >= x and r.y >= y and r.x + r.w <= x + w and r.y + r.h <= y + h
end

--- The hospital: a building of a "buildings" block, with the door on the
--- sidewalk under its block, where the dead come back (facing the road).
local function findHospital(map, cx, cy)
  local best, bestBig, bestScore
  for _, block in ipairs(map.blocks) do
    if block.kind == "buildings" then
      local x, y, w, h = blockRect(map, block)
      for _, b in ipairs(map.buildings) do
        if inside(x, y, w, h, b) then
          -- A big one near the middle beats any small one; among the big,
          -- the nearest wins, among the small the biggest.
          local big = b.w >= BIG and b.h >= BIG
          local score = big and -dist2(b.x + b.w / 2, b.y + b.h / 2, cx, cy) or b.w * b.h
          if not best or (big and not bestBig) or (big == bestBig and score > bestScore) then
            best, bestBig, bestScore = { building = b, block = { x = x, y = y, w = w, h = h } }, big, score
          end
        end
      end
    end
  end
  if not best then
    return nil
  end
  local b, blk = best.building, best.block
  return {
    x = b.x, y = b.y, w = b.w, h = b.h,
    doorX = b.x + b.w / 2,
    doorY = blk.y + blk.h + T / 2, -- the sidewalk under the block
  }
end

--- The impound lot: the "lot" block nearest the middle. Its gate (where you
--- pay) is on the sidewalk under it; cars come out into its bays.
local function findImpound(map, cx, cy)
  local best, bestD2
  for _, block in ipairs(map.blocks) do
    if block.kind == "lot" then
      local x, y, w, h = blockRect(map, block)
      local d2 = dist2(x + w / 2, y + h / 2, cx, cy)
      if not best or d2 < bestD2 then
        best, bestD2 = { x = x, y = y, w = w, h = h }, d2
      end
    end
  end
  if not best then
    return nil
  end
  -- The bays between the painted lines, top row nose down, bottom row nose up.
  local bays = {}
  local n = math.floor((best.w - 40) / BAY_PITCH)
  for i = 0, n - 1 do
    bays[#bays + 1] = { x = best.x + 20 + BAY_PITCH * (i + 0.5), y = best.y + 53, angle = math.pi / 2 }
  end
  for i = 0, n - 1 do
    bays[#bays + 1] = { x = best.x + 20 + BAY_PITCH * (i + 0.5), y = best.y + best.h - 53, angle = -math.pi / 2 }
  end
  best.padX, best.padY = best.x + best.w / 2, best.y + best.h + T / 2
  best.bays = bays
  return best
end

--- The hospital and impound lot of `map`, or nil when it isn't a city grid.
function Places.of(map)
  if not map or map.kind ~= "grid" or map.empty then
    return nil
  end
  local p = cache[map]
  if p == nil then
    local cx, cy = map.cx or 0, map.cy or 0
    p = { hospital = findHospital(map, cx, cy), impound = findImpound(map, cx, cy) }
    if not (p.hospital or p.impound) then
      p = false
    end
    cache[map] = p
  end
  return p or nil
end

-- Drawing -------------------------------------------------------------------

local function label(text, x, y, w, font, color)
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, x + 1, y + 1, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, x, y, w, "center")
end

--- A red cross, `s` px across, centred on (x, y).
local function cross(x, y, s)
  local t = s / 3
  love.graphics.rectangle("fill", x - t / 2, y - s / 2, t, s)
  love.graphics.rectangle("fill", x - s / 2, y - t / 2, s, t)
end

local RED = { 0.85, 0.12, 0.14 }
local AC = { 0.60, 0.62, 0.64 }
local GLASS = { 0.62, 0.85, 0.95 }

--- An air conditioner, a box with a fan turning in it, centred on (x, y).
local function aircon(x, y, t)
  love.graphics.setColor(0, 0, 0, 0.25)
  love.graphics.rectangle("fill", x - 11 + 3, y - 11 + 3, 22, 22, 2)
  love.graphics.setColor(AC)
  love.graphics.rectangle("fill", x - 11, y - 11, 22, 22, 2)
  love.graphics.setColor(AC[1] * 0.55, AC[2] * 0.55, AC[3] * 0.55)
  love.graphics.circle("fill", x, y, 8)
  love.graphics.setColor(0.8, 0.82, 0.84)
  love.graphics.setLineWidth(2)
  for i = 0, 2 do
    local a = t * 9 + i * 2 * math.pi / 3
    love.graphics.line(x, y, x + math.cos(a) * 7, y + math.sin(a) * 7)
  end
  love.graphics.setLineWidth(1)
end

--- A red cross, `s` px across, centred on (x, y), with a shadow.
local function bigCross(x, y, s)
  love.graphics.setColor(0, 0, 0, 0.18)
  cross(x + 4, y + 4, s)
  love.graphics.setColor(1, 1, 1)
  cross(x, y, s + 10)
  love.graphics.setColor(RED)
  cross(x, y, s)
end

--- The helipad in a corner: a dark pad, a yellow ring, an H and a light
--- blinking at each quarter, one after the other.
local function helipad(x, y, r, t)
  love.graphics.setColor(0, 0, 0, 0.2)
  love.graphics.circle("fill", x + 4, y + 4, r)
  love.graphics.setColor(0.3, 0.32, 0.35)
  love.graphics.circle("fill", x, y, r)
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.setLineWidth(3)
  love.graphics.circle("line", x, y, r - 6)
  love.graphics.setLineWidth(1)
  label("H", x - r, y - UI.fonts.heading:getHeight() / 2, r * 2, UI.fonts.heading, { 1, 1, 1 })
  local lit = math.floor(t * 3) % 4
  for i = 0, 3 do
    local a = i * math.pi / 2 + math.pi / 4
    local on = i == lit
    love.graphics.setColor(0.4, 1, 0.5, on and 1 or 0.3)
    love.graphics.circle("fill", x + math.cos(a) * (r - 2), y + math.sin(a) * (r - 2), on and 4 or 3)
  end
end

--- An ambulance parked facing left, centred on (x, y), its lights flashing.
local function ambulance(x, y, t)
  local w, h = 64, 30
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", x - w / 2 + 4, y - h / 2 + 4, w, h, 5)
  love.graphics.setColor(0.97, 0.97, 0.95)
  love.graphics.rectangle("fill", x - w / 2, y - h / 2, w, h, 5)
  -- The cab and its windscreen at the front.
  love.graphics.setColor(0.86, 0.87, 0.86)
  love.graphics.rectangle("fill", x - w / 2, y - h / 2, 18, h, 5)
  love.graphics.setColor(0.2, 0.3, 0.38)
  love.graphics.rectangle("fill", x - w / 2 + 4, y - h / 2 + 4, 8, h - 8, 2)
  -- A stripe down each side and a cross on the roof.
  love.graphics.setColor(RED)
  love.graphics.rectangle("fill", x - w / 2 + 18, y - h / 2 + 2, w - 20, 4)
  love.graphics.rectangle("fill", x - w / 2 + 18, y + h / 2 - 6, w - 20, 4)
  cross(x + 10, y, 14)
  -- The light bar over the cab: red and blue by turns.
  local flip = math.floor(t * 4) % 2 == 0
  local lx = x - w / 2 + 20
  love.graphics.setColor(1, 0.2, 0.2, flip and 1 or 0.35)
  love.graphics.rectangle("fill", lx - 3, y - h / 2 + 3, 6, h / 2 - 3, 2)
  love.graphics.setColor(0.25, 0.45, 1, flip and 0.35 or 1)
  love.graphics.rectangle("fill", lx - 3, y, 6, h / 2 - 3, 2)
  love.graphics.setColor(1, flip and 0.2 or 0.45, flip and 0.2 or 1, 0.18)
  love.graphics.circle("fill", lx, y, 22)
end

--- The hospital over the building it took: a white roof lit from the top
--- left, a red cross, a helipad when there is room, air conditioners along
--- the back, a lit glass front with the emergency canopy over the
--- entrance, the name on a plate, an ambulance waiting on the sidewalk and
--- the sign by the door where the dead come back.
function Places.drawHospital(h, time)
  time = time or 0
  local s = math.min(h.w, h.h)
  -- The roof: a grey parapet, white panels with faint seams, a lit edge.
  love.graphics.setColor(0.72, 0.74, 0.76)
  love.graphics.rectangle("fill", h.x, h.y, h.w, h.h)
  love.graphics.setColor(0.94, 0.95, 0.96)
  love.graphics.rectangle("fill", h.x + 6, h.y + 6, h.w - 12, h.h - 12)
  love.graphics.setColor(0.86, 0.87, 0.89)
  for x = h.x + 54, h.x + h.w - 12, 48 do
    love.graphics.line(x, h.y + 12, x, h.y + h.h - 12)
  end
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", h.x + 6, h.y + 6, h.w - 12, 6)
  love.graphics.rectangle("fill", h.x + 6, h.y + 6, 6, h.h - 12)

  local wide = h.w >= h.h * 1.4
  local helipadHere = wide or s >= BIG
  -- Air conditioners along the back, clear of the helipad's corner.
  local units = math.max(1, math.floor((helipadHere and h.w * 0.55 or h.w - 40) / 34))
  for i = 0, units - 1 do
    aircon(h.x + 30 + i * 34, h.y + 30, time + i * 0.7)
  end
  -- A plant room in the other back corner when the roof is big enough.
  if s >= BIG then
    local px, py = h.x + 20, h.y + 56
    love.graphics.setColor(0, 0, 0, 0.18)
    love.graphics.rectangle("fill", px + 4, py + 4, 56, 44, 3)
    love.graphics.setColor(0.78, 0.8, 0.82)
    love.graphics.rectangle("fill", px, py, 56, 44, 3)
    love.graphics.setColor(0.6, 0.62, 0.65)
    for i = 0, 3 do
      love.graphics.rectangle("fill", px + 8, py + 8 + i * 8, 40, 3)
    end
  end

  local crossX = wide and h.x + h.w * 0.3 or h.x + h.w / 2
  bigCross(crossX, h.y + h.h / 2 - 6, s * 0.38)
  if helipadHere then
    local r = s * 0.16
    helipad(h.x + h.w - r - 18, h.y + r + 18, r, time)
  end

  -- The glass front, lit from inside, and the emergency canopy over the
  -- entrance in the middle of it.
  local front = h.y + h.h
  love.graphics.setColor(0.4, 0.55, 0.62)
  love.graphics.rectangle("fill", h.x + 6, front - 18, h.w - 12, 12)
  love.graphics.setColor(GLASS[1], GLASS[2], GLASS[3], 0.8 + 0.1 * math.sin(time * 1.3))
  for x = h.x + 10, h.x + h.w - 34, 26 do
    love.graphics.rectangle("fill", x, front - 16, 22, 8)
  end
  local cw = math.min(150, h.w - 40)
  local cx = h.x + h.w / 2
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.rectangle("fill", cx - cw / 2 + 4, front - 6 + 4, cw, 34, 4)
  love.graphics.setColor(RED)
  love.graphics.rectangle("fill", cx - cw / 2, front - 6, cw, 34, 4)
  love.graphics.setColor(0.6, 0.08, 0.1)
  love.graphics.rectangle("fill", cx - cw / 2, front - 6, cw, 5)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1, 0.85 + 0.15 * math.sin(time * 3))
  love.graphics.printf("EMERGENCY", cx - cw / 2, front + 11 - UI.fonts.small:getHeight() / 2, cw, "center")

  -- The name on a plate over the glass.
  local font = UI.fonts.body
  local tw, th = font:getWidth("HOSPITAL") + 24, font:getHeight() + 6
  local py = front - 30 - th
  love.graphics.setColor(1, 1, 1)
  love.graphics.rectangle("fill", cx - tw / 2, py, tw, th, 5)
  love.graphics.setColor(RED)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", cx - tw / 2, py, tw, th, 5)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(font)
  love.graphics.printf("HOSPITAL", cx - tw / 2, py + 3, tw, "center")

  -- An ambulance waiting on the sidewalk beside the door.
  ambulance(h.doorX + 110, h.doorY, time)

  -- The sign on the sidewalk where the dead come back.
  love.graphics.setColor(RED[1], RED[2], RED[3], 0.15 + 0.1 * math.sin(time * 2))
  love.graphics.circle("fill", h.doorX, h.doorY, 24)
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", h.doorX - 12, h.doorY - 12, 24, 24, 4)
  love.graphics.setColor(RED)
  cross(h.doorX, h.doorY, 16)
  love.graphics.setColor(1, 1, 1)
end

--- The impound lot: a chain-link fence round the parking lot with a gap
--- for the gate, a sign, and the square at the gate where you pay.
function Places.drawImpound(im, lit, time)
  local x, y, w, h = im.x + 4, im.y + 4, im.w - 8, im.h - 8
  local gate = 90 -- px gap in the bottom fence
  love.graphics.setColor(0.62, 0.64, 0.66, 0.9)
  love.graphics.setLineWidth(3)
  love.graphics.line(im.padX - gate / 2, y + h, x, y + h, x, y, x + w, y, x + w, y + h, im.padX + gate / 2, y + h)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.45, 0.47, 0.5)
  for px = x, x + w, 32 do
    love.graphics.circle("fill", px, y, 3)
    if math.abs(px - im.padX) > gate / 2 then
      love.graphics.circle("fill", px, y + h, 3)
    end
  end
  for py = y, y + h, 32 do
    love.graphics.circle("fill", x, py, 3)
    love.graphics.circle("fill", x + w, py, 3)
  end
  -- The sign across the middle of the lot.
  love.graphics.setColor(0.95, 0.75, 0.15)
  love.graphics.rectangle("fill", im.x + im.w / 2 - 90, im.y + im.h / 2 - 18, 180, 36, 4)
  love.graphics.setColor(0.1, 0.1, 0.1)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", im.x + im.w / 2 - 90, im.y + im.h / 2 - 18, 180, 36, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.printf("IMPOUND LOT", im.x + im.w / 2 - 90, im.y + im.h / 2 - UI.fonts.body:getHeight() / 2, 180,
    "center")
  -- The pay square at the gate.
  local s = 40
  local pulse = lit and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.85
  love.graphics.setColor(0.12, 0.12, 0.14, pulse)
  love.graphics.rectangle("fill", im.padX - s / 2, im.padY - s / 2, s, s, 4)
  love.graphics.setColor(0.95, 0.75, 0.15, pulse)
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", im.padX - s / 2, im.padY - s / 2, s, s, 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1, pulse)
  love.graphics.printf("$", im.padX - s / 2, im.padY - UI.fonts.body:getHeight() / 2, s, "center")
  love.graphics.setColor(1, 1, 1)
end

return Places
