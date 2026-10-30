-- The Assembly Line's belts (docs/borderline.md, "6. The Assembly Line"):
-- they carry whoever stands on them, the way they run, each the other way
-- from the last, a little slower than you walk. The map says where and how
-- fast (city-map's `map.conveyors`; the ones that carry have `carry`, and
-- each its `speed`, the speed its parts ride at too: works.lua). A walker is
-- carried through on-foot's `floorDrift` (the host's step and your own
-- prediction alike, so it never rubber-bands); the army's robots on the
-- ground the host carries itself, after they have moved. Nothing is
-- carried into a wall.

local Features = require("src.features")

local Belts = {}

local WAYS = { e = { 1, 0 }, w = { -1, 0 }, n = { 0, -1 }, s = { 0, 1 } }

--- How the floor at (x, y) on `map` moves whoever stands there ({ x, y },
--- px/s), or nil where it doesn't.
function Belts.drift(map, x, y)
  for _, c in ipairs(map and map.conveyors or {}) do
    if c.carry and x >= c.x and x < c.x + c.w and y >= c.y and y < c.y + c.h then
      if not c.drift then -- worked out once a belt
        local way = WAYS[c.dir]
        c.drift = { x = way[1] * c.speed, y = way[2] * c.speed }
      end
      return c.drift
    end
  end
  return nil
end

--- Carry every one of `walkers` (the army's, on the ground) standing on a
--- belt of `map` along it for `dt`.
function Belts.serverCarry(map, walkers, dt)
  if not (map and map.conveyors) then
    return
  end
  for _, s in ipairs(walkers) do
    local d = Belts.drift(map, s.x, s.y)
    if d then
      local nx, ny = s.x + d.x * dt, s.y + d.y * dt
      if not Features.any("blocksPoint", nx, ny) then
        s.x, s.y = nx, ny
      end
    end
  end
end

return Belts
