-- Car tags: a parked car that belongs to somebody carries their name, the
-- way a driven car carries its driver's, so you can tell whose car you are
-- about to borrow, and spot your own from across the street. A player can
-- own several (the starter car and any from the vehicle factory); every
-- one of them is tagged.
--
-- Purely local: it reads the car snapshots the client already has (owner
-- from VEHICLE, driver from STATE) and sends nothing. A car whose owner has
-- left the game stays in the world and keeps their name.

local UI = require("src.ui")
local Car = require("src.car")

local Tags = {
  name = "car-tags",
  priority = 110, -- just over the cars and walkers, under effects
}

Tags.alpha = 0.7 -- a tag is quieter than a driver's name
Tags.lift = Car.HEIGHT + 18 -- px above the car's centre, where the driver's name goes

function Tags:drawAboveCars(client)
  love.graphics.setFont(UI.fonts.small)
  for _, c in pairs(client.vehicles) do
    local owner = c.owner and not c.driver and client:nameOf(c.owner)
    if owner then
      love.graphics.setColor(1, 1, 1, c.owner == client.myId and self.alpha + 0.2 or self.alpha)
      love.graphics.printf(owner .. "'s", c.dx - 60, c.dy - self.lift, 120, "center")
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Tags
