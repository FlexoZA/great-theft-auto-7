-- Rooms on an indoor map, for the drones that keep to one (watchers.lua,
-- stings.lua): on Halcyon Tower each of its floors (city-map's
-- `map.floors`) is a room, walls and slab between them.

local Rooms = {}

--- `sameRoom(x0, y0, x1, y1)` for `map`: are the two points on the same
--- floor? nil on a map without floors (outdoors: everywhere is one room).
function Rooms.of(map)
  local floors = map.floors
  if not floors then
    return nil
  end
  return function(_x0, y0, _x1, y1)
    for _, f in ipairs(floors) do
      if y0 >= f.y0 and y0 < f.y1 then
        return y1 >= f.y0 and y1 < f.y1
      end
    end
    return false
  end
end

return Rooms
