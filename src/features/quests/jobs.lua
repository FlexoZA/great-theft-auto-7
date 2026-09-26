-- The Jobs building: one of the city's own buildings, where every job is on
-- offer instead of a star in the street. It is picked from the map the same
-- way on every machine, like the hospital (garage/places.lua), so there is
-- nothing to send: the building nearest the middle of town with at least
-- three tiles a side, in a block the hospital is not in, whose door is
-- clear of the hospital's and impound lot's doors and the spawn points (so
-- nobody starts a game on it with the action key taken). The door is on the
-- sidewalk by the side of its block the building is nearest; stand there
-- and the job board opens on the action key.
--
-- The shop (src/features/shop) is a building in the same block: the biggest
-- other one whose door is as clear and far enough from the Jobs door that
-- the two squares never overlap. A block with such a neighbour beats one
-- without, so the city has a shop whenever it can.
--
-- `Jobs.of(map)` answers for a city grid ({ x, y, w, h, doorX, doorY, shop })
-- and nil for any other map; `shop` is { x, y, w, h, doorX, doorY, nx, ny,
-- block } (nx, ny: the way out of the door, towards the road; block: the
-- block's x, y, w, h) or nil. It is worked
-- out once per map table; a city that grows only adds plots, which are
-- never picked.
--
-- `Jobs.layout(list, selected)` works out every rectangle of the board for
-- the window as it is now and `Jobs.drawBoard` paints them; init.lua
-- hit-tests the same rectangles.

local Features = require("src.features")
local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")

local Jobs = {}

local T = Layout.TILE
local BIG = 3 * T -- px a side a building needs to be picked when there is a choice
local CLEAR = 260 -- px the door keeps from other places' doors and markers
local APART = 160 -- px between the Jobs door and the shop's, so their squares never overlap
local cache = setmetatable({}, { __mode = "k" }) -- map -> building, or false for none

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Points the door must stay clear of: the spawn points, the hospital's
--- door and the impound lot's gate (garage).
local function taken(map)
  local spots, hospital = {}, nil
  for _, s in ipairs(map.spawns) do
    spots[#spots + 1] = { s.x, s.y }
  end
  local garage = Features.byName.garage
  local places = garage and garage.places and garage:places()
  if places and places.hospital then
    hospital = places.hospital
    spots[#spots + 1] = { hospital.doorX, hospital.doorY }
  end
  if places and places.impound then
    spots[#spots + 1] = { places.impound.padX, places.impound.padY }
  end
  return spots, hospital
end

--- The door of building `b` in the block at (x, y, w, h): on the sidewalk
--- round the block, on the side the building is nearest (the bottom first
--- when two are as near), facing the building's middle. Also the way out
--- of the block there (nx, ny).
local function door(b, x, y, w, h)
  local mx, my = b.x + b.w / 2, b.y + b.h / 2
  local sides = {
    { y + h - (b.y + b.h), mx, y + h + T / 2, 0, 1 },
    { b.y - y, mx, y - T / 2, 0, -1 },
    { b.x - x, x - T / 2, my, -1, 0 },
    { x + w - (b.x + b.w), x + w + T / 2, my, 1, 0 },
  }
  local best = sides[1]
  for i = 2, #sides do
    if sides[i][1] < best[1] then
      best = sides[i]
    end
  end
  return best[2], best[3], best[4], best[5]
end

local function within(b, x, y, w, h)
  return b.x >= x and b.y >= y and b.x + b.w <= x + w and b.y + b.h <= y + h
end

local function clearOf(spots, x, y)
  for _, s in ipairs(spots) do
    if dist2(x, y, s[1], s[2]) < CLEAR * CLEAR then
      return false
    end
  end
  return true
end

--- The shop's building beside the Jobs building `j` in the block at
--- (x, y, w, h): the biggest other one there whose door is clear of
--- `spots` and APART from the Jobs door, or nil.
local function neighbour(map, j, spots, x, y, w, h)
  local best
  for _, b in ipairs(map.buildings) do
    if b.x ~= j.x or b.y ~= j.y then
      local doorX, doorY, nx, ny = door(b, x, y, w, h)
      if within(b, x, y, w, h) and clearOf(spots, doorX, doorY)
        and dist2(doorX, doorY, j.doorX, j.doorY) >= APART * APART
        and (not best or b.w * b.h > best.w * best.h) then
        best = { x = b.x, y = b.y, w = b.w, h = b.h, doorX = doorX, doorY = doorY, nx = nx, ny = ny }
        best.block = { x = x, y = y, w = w, h = h }
      end
    end
  end
  return best
end

local function find(map)
  local spots, hospital = taken(map)
  local cx, cy = map.cx or 0, map.cy or 0
  local best, bestRank, bestD2
  for _, block in ipairs(map.blocks) do
    if block.kind == "buildings" then
      local x, y, w, h = map.x0 + block.tx * T, map.y0 + block.ty * T, block.tw * T, block.th * T
      local hasHospital = hospital
        and hospital.x >= x and hospital.y >= y and hospital.x < x + w and hospital.y < y + h
      for _, b in ipairs(map.buildings) do
        local doorX, doorY = door(b, x, y, w, h)
        if not hasHospital and within(b, x, y, w, h) and clearOf(spots, doorX, doorY) then
          local j = { x = b.x, y = b.y, w = b.w, h = b.h, doorX = doorX, doorY = doorY }
          j.shop = neighbour(map, j, spots, x, y, w, h)
          -- One with a shop beside it beats one without, a big one any
          -- small one; then the nearest the middle wins.
          local rank = (j.shop and 2 or 0) + ((b.w >= BIG and b.h >= BIG) and 1 or 0)
          local d2 = dist2(b.x + b.w / 2, b.y + b.h / 2, cx, cy)
          if not best or rank > bestRank or (rank == bestRank and d2 < bestD2) then
            best, bestRank, bestD2 = j, rank, d2
          end
        end
      end
    end
  end
  return best
end

--- The Jobs building of `map`, or nil when it isn't a city grid.
function Jobs.of(map)
  if not map or map.kind ~= "grid" or map.empty then
    return nil
  end
  local j = cache[map]
  if j == nil then
    j = find(map) or false
    cache[map] = j
  end
  return j or nil
end

-- Drawing -------------------------------------------------------------------

local GOLD = { 1, 0.85, 0.3 }

local function label(text, x, y, w, font, color)
  love.graphics.setFont(font)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, x + 1, y + 1, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(text, x, y, w, "center")
end

--- The building over the one it took: a dark roof with a gold star on it
--- and a sign, and the glowing square by the door where the board opens.
--- `starFn(cx, cy, r)` fills a star (the quests feature's own).
function Jobs.drawBuilding(j, starFn, radius, lit, time)
  love.graphics.setColor(0.22, 0.2, 0.26)
  love.graphics.rectangle("fill", j.x, j.y, j.w, j.h)
  love.graphics.setColor(0.32, 0.29, 0.38)
  love.graphics.rectangle("fill", j.x + 6, j.y + 6, j.w - 12, j.h - 12)
  local s = math.min(j.w, j.h)
  love.graphics.setColor(0, 0, 0, 0.35)
  starFn(j.x + j.w / 2 + 4, j.y + j.h / 2 - 10 + 4, s * 0.26)
  love.graphics.setColor(GOLD)
  starFn(j.x + j.w / 2, j.y + j.h / 2 - 10, s * 0.26)
  label("JOBS", j.x, j.y + j.h - 36, j.w, UI.fonts.heading, GOLD)
  -- The square by the door.
  local pulse = lit and 0.6 + 0.4 * math.abs(math.sin(time * 4)) or 0.5 + 0.5 * math.sin(time * 2.5)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", j.doorX, j.doorY, radius)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.35 + 0.25 * pulse)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", j.doorX, j.doorY, radius)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0, 0, 0, 0.35)
  starFn(j.doorX + 3, j.doorY + 3, 14)
  love.graphics.setColor(GOLD)
  starFn(j.doorX, j.doorY, 14)
  love.graphics.setColor(1, 1, 1)
end

-- The board ------------------------------------------------------------------

Jobs.width = 640 -- px; the panel is centred on the screen
local PAD = 24
local ROW_H = 58 -- a job's row: its title and where it is
local GAP = 8
local TITLE_H = 60
local BUTTON_H = 40

local function inside(r, x, y)
  return x >= r.x and y >= r.y and x < r.x + r.w and y < r.y + r.h
end
Jobs.inside = inside

--- Every rectangle of the board for `list` (the jobs on offer) with job
--- number `selected` picked: { panel, rows = { { x, y, w, h, quest } },
--- text = { x, y, w }, accept, close }.
function Jobs.layout(list, selected)
  local w, h = love.graphics.getDimensions()
  local pw = math.min(Jobs.width, w - 16)
  local inner = pw - 2 * PAD
  local quest = list[selected]
  local _, lines = UI.fonts.body:getWrap(quest and quest.text or "", inner)
  local textH = #lines * UI.fonts.body:getHeight()
  local ph = TITLE_H + #list * (ROW_H + GAP) + 12 + textH + 20 + UI.fonts.small:getHeight() + 12 + BUTTON_H + PAD
  local px, py = math.floor((w - pw) / 2), math.max(8, math.floor((h - ph) / 2))
  local L = { panel = { x = px, y = py, w = pw, h = ph }, rows = {} }
  local y = py + TITLE_H
  for i, q in ipairs(list) do
    L.rows[i] = { x = px + PAD, y = y, w = inner, h = ROW_H, quest = q }
    y = y + ROW_H + GAP
  end
  L.text = { x = px + PAD, y = y + 12, w = inner }
  y = y + 12 + textH + 20
  L.notice = { x = px, y = y, w = pw }
  y = y + UI.fonts.small:getHeight() + 12
  local bw = (inner - GAP) / 2
  L.accept = { x = px + PAD, y = y, w = bw, h = BUTTON_H }
  L.close = { x = px + PAD + bw + GAP, y = y, w = bw, h = BUTTON_H }
  return L
end

local function button(r, text, hot, color)
  love.graphics.setColor(color[1], color[2], color[3], hot and 0.35 or 0.18)
  love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
  love.graphics.setColor(color[1], color[2], color[3], hot and 1 or 0.7)
  love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.printf(text, r.x, r.y + (r.h - UI.fonts.body:getHeight()) / 2, r.w, "center")
end

--- The board: a row per job (its star's colour, its title, where it
--- takes you), what the picked one is about, and the buttons. `places`
--- names each job's destination; `keys` is { accept, close } for the hints.
function Jobs.drawBoard(L, selected, places, notice, keys)
  local w, h = love.graphics.getDimensions()
  local mx, my = love.mouse.getPosition()
  local p = L.panel
  love.graphics.setColor(0, 0, 0, 0.45)
  love.graphics.rectangle("fill", 0, 0, w, h)
  love.graphics.setColor(0.10, 0.10, 0.13, 0.96)
  love.graphics.rectangle("fill", p.x, p.y, p.w, p.h, 10)
  love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.8)
  love.graphics.rectangle("line", p.x, p.y, p.w, p.h, 10)

  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(GOLD)
  love.graphics.printf("JOBS", p.x, p.y + 12, p.w, "center")
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Pick a job", p.x, p.y + 12 + UI.fonts.small:getHeight() + 2, p.w, "center")

  for i, r in ipairs(L.rows) do
    local q = r.quest
    local c = q.color or GOLD
    local picked, hot = i == selected, inside(r, mx, my)
    love.graphics.setColor(c[1], c[2], c[3], picked and 0.22 or (hot and 0.12 or 0.06))
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 6)
    love.graphics.setColor(c[1], c[2], c[3], picked and 1 or 0.35)
    love.graphics.setLineWidth(picked and 2 or 1)
    love.graphics.rectangle("line", r.x, r.y, r.w, r.h, 6)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", r.x + 10, r.y + 10, 6, r.h - 20, 3)
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.print(UI.fit(q.title, UI.fonts.body, r.w - 40), r.x + 28, r.y + 8)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(0.65, 0.65, 0.7)
    love.graphics.print((q.label or "QUEST") .. "  -  " .. (places[q.id] or q.map), r.x + 28, r.y + r.h - 8
      - UI.fonts.small:getHeight())
  end

  local q = L.rows[selected] and L.rows[selected].quest
  if q then
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0.85, 0.85, 0.88)
    love.graphics.printf(q.text, L.text.x, L.text.y, L.text.w, "center")
  end
  if notice then
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(1, 0.45, 0.4, notice.alpha)
    love.graphics.printf(notice.text, L.notice.x, L.notice.y, L.notice.w, "center")
  end
  button(L.accept, "Take the job (" .. keys[1] .. ")", q and inside(L.accept, mx, my), q and { 0.5, 1, 0.55 }
    or { 0.5, 0.5, 0.5 })
  button(L.close, "Leave (" .. keys[2] .. ")", inside(L.close, mx, my), { 0.85, 0.85, 0.88 })
  love.graphics.setColor(1, 1, 1)
end

return Jobs
