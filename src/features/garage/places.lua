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

--- The hospital over the building it took: a white roof with a red cross,
--- a helipad when there is room, and a sign by the door.
function Places.drawHospital(h)
  local s = math.min(h.w, h.h)
  love.graphics.setColor(0.72, 0.74, 0.76)
  love.graphics.rectangle("fill", h.x, h.y, h.w, h.h)
  love.graphics.setColor(0.94, 0.95, 0.96)
  love.graphics.rectangle("fill", h.x + 6, h.y + 6, h.w - 12, h.h - 12)
  love.graphics.setColor(0.85, 0.12, 0.14)
  local wide = h.w >= h.h * 1.4
  local crossX = wide and h.x + h.w * 0.3 or h.x + h.w / 2
  cross(crossX, h.y + h.h / 2, s * 0.45)
  if wide or s >= BIG then
    -- A helipad in the far corner: a ring and an H.
    local r = s * 0.16
    local hx, hy = h.x + h.w - r - 18, h.y + r + 18
    love.graphics.setColor(0.3, 0.32, 0.35)
    love.graphics.circle("fill", hx, hy, r)
    love.graphics.setColor(1, 0.85, 0.3)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", hx, hy, r - 5)
    love.graphics.setLineWidth(1)
    label("H", hx - r, hy - UI.fonts.heading:getHeight() / 2, r * 2, UI.fonts.heading, { 1, 1, 1 })
  end
  label("HOSPITAL", h.x, h.y + h.h - 34, h.w, UI.fonts.body, { 0.85, 0.12, 0.14 })
  -- The sign on the sidewalk where the dead come back.
  love.graphics.setColor(1, 1, 1, 0.9)
  love.graphics.rectangle("fill", h.doorX - 12, h.doorY - 12, 24, 24, 4)
  love.graphics.setColor(0.85, 0.12, 0.14)
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
