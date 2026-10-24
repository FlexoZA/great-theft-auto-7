-- The Borderline maps past their edges (borderline.lua), drawn every frame
-- under the canvas when the surroundings feature asks (CityMap:drawPastEdges):
-- the outside running on round the map, tile by tile, the same as the canvas
-- draws it inside (render_borderline_ground.lua), so the Wreck's factory
-- roofs, Liar's Landing's sea and snowbanks, the cliff, the sky never stop.
-- Where a floor meets the map's edge (a tunnel, a road out) it runs on,
-- into the dark for a tunnel, its rails with it; and anything the map put
-- across its own edge (Liar's Landing's freighter) is drawn whole.

local Layout = require("src.features.city-map.layout")
local Kit = require("src.features.city-map.render_borderline_kit")
local Ground = require("src.features.city-map.render_borderline_ground")
local RenderBorderline = require("src.features.city-map.render_borderline")

local Beyond = {}

local INK, LINE, C = Kit.INK, Kit.LINE, Kit.C
local color = Kit.color

--- The edge tile that tile (c, r) past `map` runs straight on from, if it is open.
local function runsOn(map, c, r)
  local ec, er = math.max(map.c0, math.min(map.c1, c)), math.max(map.r0, math.min(map.r1, r))
  if (ec == c or er == r) and Ground.open(map, ec, er) then
    return ec, er
  end
end

--- The cover of `kind` over (x, y), give or take a tile along y.
local function under(map, kind, x, y, T)
  for _, s in ipairs(map.cover) do
    if s.kind == kind and x >= s.x and x < s.x + s.w and y >= s.y - T and y < s.y + s.h + T then
      return s
    end
  end
end

--- A floor running on at tile (c, r) from edge tile (ec, er).
local function runOn(map, c, r, ec, er, T)
  local x, y = map.x0 + c * T, map.y0 + r * T
  local ex, ey = map.x0 + ec * T + T / 2, map.y0 + er * T + T / 2
  if under(map, "tunnel", ex, ey, T) then
    color(INK)
    love.graphics.rectangle("fill", x, y, T, T)
    return
  end
  local f = Ground.floorAt(map, ex, ey)
  Ground.drawFloor(c, r, x, y, T, f)
  local rails = under(map, "rails", ex, ey, T)
  if rails and x + T > rails.x - 14 and x < rails.x + rails.w + 14 then
    color(C.woodDark)
    for sy = rails.y + math.ceil((y - rails.y) / 28) * 28, y + T - 1, 28 do
      love.graphics.rectangle("fill", rails.x - 14, sy, rails.w + 28, 9)
    end
    color(C.gunmetal)
    love.graphics.rectangle("fill", rails.x - 6, y, 5, T)
    love.graphics.rectangle("fill", rails.x + rails.w + 1, y, 5, T)
  end
  if f == C.yard then
    Ground.drawYardSnow(c, r, x, y, T, true)
    Ground.drawYardSnow(c, r, x, y, T, false)
  end
end

--- Draw what lies past `map`'s edges inside (left, top, right, bottom), world px.
function Beyond.draw(map, left, top, right, bottom)
  local T = Layout.TILE
  local c0, c1 = math.floor((left - map.x0) / T), math.floor((right - map.x0) / T)
  local r0, r1 = math.floor((top - map.y0) / T), math.floor((bottom - map.y0) / T)
  if c0 >= map.c0 and c1 <= map.c1 and r0 >= map.r0 and r1 <= map.r1 then
    return
  end
  local function beyond(c, r)
    return c < map.c0 or c > map.c1 or r < map.r0 or r > map.r1
  end
  local floors = {}
  for c = c0, c1 do
    for r = r0, r1 do
      if beyond(c, r) then
        local ec, er = runsOn(map, c, r)
        if ec then
          floors[c .. "," .. r] = true
          runOn(map, c, r, ec, er, T)
        end
      end
    end
  end
  for c = c0, c1 do
    for r = r0, r1 do
      if beyond(c, r) and not floors[c .. "," .. r] then
        Ground.drawOutside(map, c, r, map.x0 + c * T, map.y0 + r * T, T)
      end
    end
  end
  color(INK) -- the outline down either side of a floor running on
  for key in pairs(floors) do
    local c, r = key:match("(-?%d+),(-?%d+)")
    c, r = tonumber(c), tonumber(r)
    local x, y = map.x0 + c * T, map.y0 + r * T
    if not floors[(c - 1) .. "," .. r] then
      love.graphics.rectangle("fill", x - LINE, y, LINE, T)
    end
    if not floors[(c + 1) .. "," .. r] then
      love.graphics.rectangle("fill", x + T, y, LINE, T)
    end
  end
  local font = love.graphics.getFont()
  for _, s in ipairs(map.cover) do
    if s.x < map.left or s.y < map.top or s.x + s.w > map.left + map.w or s.y + s.h > map.top + map.h then
      RenderBorderline.drawCover(s)
    end
  end
  love.graphics.setFont(font)
end

return Beyond
