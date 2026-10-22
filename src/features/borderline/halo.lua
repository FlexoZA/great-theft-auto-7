-- The halo over what the objective line is after (tale.lua): every
-- terminal still to hack while the way on is shut, then the way on itself
-- until the level is done. In the world, a golden ring hovering over it,
-- bobbing, with a beam down to a ripple spreading on the ground (and a glow
-- at dusk); on the minimap and the big map, a ring pinging round its mark.

local Terminals = require("src.features.terminals")

local Halo = {}

Halo.LIFT = 54 -- px the ring hovers over the ground
local GOLD = { 1.00, 0.84, 0.32 }

local clock = 0

function Halo.update(dt)
  clock = clock + dt
end

--- Where the objectives are on `map` now: a list of { x, y }. `done`: the
--- level is finished (the EXIT star says where to go then).
function Halo.objectives(map, done)
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

--- The halo over each of `list`, in the world.
function Halo.draw(list)
  for i, o in ipairs(list) do
    local k = breath(i * 0.37)
    local y = o.y - Halo.LIFT - 5 * math.sin((clock + i) * 2.2)
    -- The ripple on the ground, spreading and fading.
    local r = (clock * 0.7 + i * 0.29) % 1
    love.graphics.setLineWidth(3)
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.5 * (1 - r))
    love.graphics.ellipse("line", o.x, o.y, 18 + 34 * r, 8 + 15 * r, 32)
    -- The beam down from the ring.
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.08 + 0.06 * k)
    love.graphics.polygon("fill", o.x - 16, y, o.x + 16, y, o.x + 6, o.y, o.x - 6, o.y)
    -- The ring: a dark edge, the gold, a bright line on it.
    love.graphics.setLineWidth(7)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.ellipse("line", o.x, y + 2, 22, 8, 32)
    love.graphics.setLineWidth(5)
    love.graphics.setColor(GOLD[1], GOLD[2], GOLD[3], 0.75 + 0.25 * k)
    love.graphics.ellipse("line", o.x, y, 22, 8, 32)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(1, 0.97, 0.8, 0.6 + 0.4 * k)
    love.graphics.ellipse("line", o.x, y - 1, 20, 6.5, 32)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- Their glow at dusk (the night feature's `glow`).
function Halo.drawNightLights(list, glow)
  for i, o in ipairs(list) do
    glow(o.x, o.y - Halo.LIFT, 70, GOLD, 0.45 + 0.3 * breath(i * 0.37))
  end
end

--- A ring pinging round each of `list` on the minimap or the big map
--- (`toMap` turns world px into its px).
function Halo.drawOnMinimap(list, toMap)
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

return Halo
