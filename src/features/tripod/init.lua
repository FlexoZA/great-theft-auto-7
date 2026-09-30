-- The tripod: a boss out of War of the Worlds, a war machine that stands on
-- three long legs over the city, burns what it looks at with its heat ray
-- and picks people up with its tentacles. It comes as a city event
-- (src/features/events/tripod.lua, the F8 menu), which runs the fight; this
-- folder is the character: how it looks, its portrait and its noises, and
-- what it leaves behind when it goes down (its wreck), which stays after
-- the event is over. The ash of anyone its heat ray or lightning killed is
-- the damage feature's, as for any fire or shock death.
--
-- Modules
--   src/features/tripod/render.lua   the tripod from above, its heat ray,
--                                    red weed, its wreck
--   src/features/tripod/face.lua     its portrait
--   src/features/tripod/sounds.lua   its horn, heat ray and tentacles

local Sounds = require("src.features.tripod.sounds")
local Render = require("src.features.tripod.render")

local Tripod = {
  name = "tripod",
  priority = 55, -- remains under the pedestrians (60) and the pickups (70)
}

-- Tuning ------------------------------------------------------------------
Tripod.remainsTime = 90 -- seconds a wreck stays

local remains = {} -- { kind = "wreck", x, y, angle, t }
local time = 0

function Tripod:load()
  Sounds.load()
end

function Tripod:exitGame()
  remains = {}
end

function Tripod:mapChanged()
  remains = {}
end

--- A felled tripod lies at (x, y) from now on (for `remainsTime`).
function Tripod.wreckAt(x, y, angle)
  remains[#remains + 1] = { kind = "wreck", x = x, y = y, angle = angle, t = Tripod.remainsTime }
end

function Tripod:update(dt)
  time = time + dt
  for i = #remains, 1, -1 do
    local r = remains[i]
    r.t = r.t - dt
    if r.t <= 0 then
      table.remove(remains, i)
    end
  end
end

function Tripod:drawBelowCars()
  for _, r in ipairs(remains) do
    Render.wreck(r, time)
  end
  love.graphics.setColor(1, 1, 1)
end

return Tripod
