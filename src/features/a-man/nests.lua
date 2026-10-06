-- The MG nests (the Coast's beside its bunkers, the Winding Road's past
-- its bridges), as every screen draws them (city17.lua mans them on the
-- host; the sandbags and the bunkers are on the map's canvas,
-- render_coast.lua and render_road.lua). Each gun stands on its tripod in its nest: swung the
-- way whoever is on it faces, or at rest along the nest's facing when
-- nobody is.

local Nests = {}

local MAN = 16 -- px from the nest's middle that counts as on the gun
local STEEL = { 0.20, 0.22, 0.24 }
local STEEL_LIGHT = { 0.34, 0.37, 0.40 }
local LEG = { 0.15, 0.16, 0.17 }
local AMMO = { 0.36, 0.38, 0.26 }
local BELT = { 0.80, 0.66, 0.30 }

--- Every nest of `map` and its gun, `troops` the soldiers as drawn
--- (id -> { dx, dy, angle }).
function Nests.draw(map, troops)
  for _, b in ipairs(map and (map.nests or map.bunkers) or {}) do
    local n = b.nest
    local angle, manned = n.angle, false
    for _, s in pairs(troops) do
      if (s.dx - n.x) ^ 2 + (s.dy - n.y) ^ 2 < MAN * MAN then
        angle, manned = s.angle, true
        break
      end
    end
    love.graphics.push()
    love.graphics.translate(n.x, n.y)
    love.graphics.rotate(angle)
    -- The tripod, in front of whoever is on it, its legs splayed on the sand.
    love.graphics.setColor(LEG)
    love.graphics.setLineWidth(2)
    love.graphics.line(14, 0, 24, -9)
    love.graphics.line(14, 0, 24, 9)
    love.graphics.line(14, 0, 4, 0)
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.rectangle("fill", 9, -3, 32, 8)
    -- The gun: receiver, barrel with its cooling jacket, the ammo box and belt.
    love.graphics.setColor(STEEL)
    love.graphics.rectangle("fill", 6, -3.5, 14, 7)
    love.graphics.rectangle("fill", 20, -2.5, 12, 5)
    love.graphics.setColor(STEEL_LIGHT)
    love.graphics.rectangle("fill", 20, -1.5, 12, 1)
    love.graphics.setColor(STEEL)
    love.graphics.rectangle("fill", 32, -1, 9, 2)
    love.graphics.setColor(AMMO)
    love.graphics.rectangle("fill", 8, 3.5, 8, 6)
    love.graphics.setColor(BELT)
    love.graphics.rectangle("fill", 12, 2, 3, 2)
    if not manned then -- nobody on it: the grips stand empty
      love.graphics.setColor(LEG)
      love.graphics.rectangle("fill", 2, -2, 4, 4)
    end
    love.graphics.pop()
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Nests
