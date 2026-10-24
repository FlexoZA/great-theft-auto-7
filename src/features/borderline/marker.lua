-- The marker over what the objective line is after (tale.lua): every
-- terminal still to hack while the way on is shut, then the way on itself
-- until the level is done. In the world, a gold chevron bouncing over it,
-- pointing down, a fainter one breathing above it and a shadow under it
-- (and a glow at dusk); on the minimap and the big map, a ring pinging
-- round its mark.

local Terminals = require("src.features.terminals")

local Marker = {}

Marker.LIFT = 36 -- px the chevron's tip sits over the mark at the bottom of a bounce
Marker.BOUNCE = 12 -- px it rises at the top of one
Marker.WIDE = 20 -- px from the tip out to each arm's end
Marker.DEEP = 21 -- px from the tip up to the arms' ends
Marker.NOTCH = 10 -- px from the tip up to the notch inside the arms
local GOLD = { 1.00, 0.84, 0.32 }

local clock = 0

function Marker.update(dt)
  clock = clock + dt
end

--- Where the objectives are on `map` now: a list of { x, y }. `done`: the
--- level is finished (the EXIT star says where to go then).
function Marker.objectives(map, done)
  local list = {}
  if not map or done then
    return list
  end
  for _, t in ipairs(Terminals.waiting()) do
    list[#list + 1] = { x = t.x, y = t.y }
  end
  if #list == 0 and map.exitX then
    list[1] = { x = map.exitX, y = map.exitY }
  end
  return list
end

--- 0..1, breathing in and out.
local function breath(phase)
  return 0.5 - 0.5 * math.cos((clock + phase) * 2 * math.pi / 1.8)
end

--- 0 (down) to 1 (up), a bounce that drops fast and hangs at the top.
local function bounce(phase)
  return math.abs(math.sin((clock + phase) * 3.2))
end

--- A chevron with its tip at (x, y), filled in the colour set now: two
--- arms, each a convex quad, since a filled polygon has to be convex.
local function fillChevron(x, y)
  local w, d, n = Marker.WIDE, Marker.DEEP, Marker.NOTCH
  local t = w * (d - n) / d -- how far in from the end the arm's inner edge starts
  love.graphics.polygon("fill", x - w, y - d, x - w + t, y - d, x, y - n, x, y)
  love.graphics.polygon("fill", x + w, y - d, x, y, x, y - n, x + w - t, y - d)
end

--- Its outline, the dark edge round it.
local function lineChevron(x, y)
  local w, d, n = Marker.WIDE, Marker.DEEP, Marker.NOTCH
  local t = w * (d - n) / d
  love.graphics.polygon("line", x - w, y - d, x - w + t, y - d, x, y - n, x + w - t, y - d, x + w, y - d, x, y)
end

--- The marker over each of `list`, in the world.
function Marker.draw(list)
  for i, o in ipairs(list) do
    local b = bounce(i * 0.37)
    local k = breath(i * 0.37)
    local y = o.y - Marker.LIFT - Marker.BOUNCE * b
    -- Its shadow, on top of the console: smaller and fainter the higher it is.
    love.graphics.setColor(0, 0, 0, 0.35 - 0.15 * b)
    love.graphics.ellipse("fill", o.x, o.y - Marker.LIFT + 18, 13 - 4 * b, 4 - b, 16)
    -- The fainter one above, breathing.
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.3 + 0.4 * k)
    fillChevron(o.x, y - Marker.DEEP)
    -- The chevron: a dark edge, the gold, a bright inner notch.
    love.graphics.setLineWidth(4)
    love.graphics.setColor(0, 0, 0, 0.6)
    lineChevron(o.x, y)
    love.graphics.setColor(GOLD)
    fillChevron(o.x, y)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 0.97, 0.8, 0.5 + 0.5 * k)
    local w, d, n = Marker.WIDE, Marker.DEEP, Marker.NOTCH
    love.graphics.line(o.x - w + 3, y - d + 2, o.x, y - n + 1, o.x + w - 3, y - d + 2)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- Their glow at dusk (the night feature's `glow`).
function Marker.drawNightLights(list, glow)
  for i, o in ipairs(list) do
    local y = o.y - Marker.LIFT - Marker.BOUNCE * bounce(i * 0.37) - Marker.DEEP
    glow(o.x, y, 50, GOLD, 0.4 + 0.3 * breath(i * 0.37))
  end
end

--- A ring pinging round each of `list` on the minimap or the big map
--- (`toMap` turns world px into its px).
function Marker.drawOnMinimap(list, toMap)
  for i, o in ipairs(list) do
    local x, y = toMap(o.x, o.y)
    local r = (clock * 0.9 + i * 0.29) % 1
    love.graphics.setLineWidth(1.5)
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 1 - r)
    love.graphics.circle("line", x, y, 4 + 9 * r, 20)
    love.graphics.setColor(0, 0, 0, 0.7)
    love.graphics.circle("line", x, y, 6, 16)
    love.graphics.setColor(GOLD)
    love.graphics.circle("line", x, y, 5, 16)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Marker
