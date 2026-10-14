-- The Foundry's conveyor belts (docs/eternal-mood.md, "The Foundry"): a
-- moving floor. City-map's `map.belts` says where each runs and how fast
-- (vx, vy px/s); on the host, whoever stands on one is carried along it
-- every tick: players on foot, and Heck's horde on the ground (the
-- possessed, the interns, the imps; the Cacodaemons float over). A belt
-- runs faster than a walk (45) and slower than a sprint (170), so walking
-- against one gets you nowhere. Nobody is carried into a wall: they stop
-- against it. Players see themselves carried as the host's word comes in
-- (on-foot eases it in); render_eternal_mood.lua draws the belts running.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Belts = {}

Belts.REACH = 10 -- px ahead of whoever it carries that must be clear

--- The belt (x, y) is on in `map`, or nil.
function Belts.at(map, x, y)
  for _, b in ipairs(map and map.belts or {}) do
    if x >= b.x and x < b.x + b.w and y >= b.y and y < b.y + b.h then
      return b
    end
  end
  return nil
end

--- Carry `o` (anything with x and y) along belt `b` for `dt`.
local function carry(o, b, dt)
  local mx, my = b.vx * dt, b.vy * dt
  local ax = mx > 0 and Belts.REACH or mx < 0 and -Belts.REACH or 0
  local ay = my > 0 and Belts.REACH or my < 0 and -Belts.REACH or 0
  if not Sight.blocked(o.x + mx + ax, o.y + my + ay) then
    o.x, o.y = o.x + mx, o.y + my
  end
end

--- One tick on the host: everyone standing on a belt of `map` is carried;
--- `horde` is horde.lua's server state (or nil).
function Belts.serverStep(server, map, dt, horde)
  if not (map and map.belts and #map.belts > 0) then
    return
  end
  for _, p in pairs(server.players) do
    local body = p.body
    if body and not p.vehicle and not body.dead and Features.present(p) then
      local b = Belts.at(map, body.x, body.y)
      if b then
        carry(body, b, dt)
      end
    end
  end
  if horde then
    for _, list in ipairs({ horde.possessed.list, horde.interns.list, horde.imps.list }) do
      for _, s in ipairs(list) do
        local b = Belts.at(map, s.x, s.y)
        if b then
          carry(s, b, dt)
        end
      end
    end
  end
end

return Belts
