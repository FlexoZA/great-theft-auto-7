-- Freeze: everything inside the target area stops dead for a few seconds.
-- Players on foot or behind a wheel, cars nobody is driving, and whatever
-- else lives in the world (pedestrians, officers, Karen) through the
-- `serverFreezeArea` event. The caster is never caught in their own cast.

local Features = require("src.features")
local Car = require("src.car")
local Body = require("src.body")

local Freeze = {
  key = "freeze", -- on the wire and in a bag ("ability-freeze")
  title = "freeze",
  sound = "freeze",
  color = { 0.55, 0.85, 1.0 }, -- ice
}

-- Tuning ------------------------------------------------------------------
Freeze.radius = 110 -- px; the area caught
Freeze.range = 380 -- px; how far from you it can be placed
Freeze.seconds = 3 -- how long the catch lasts
Freeze.cooldown = 12 -- seconds before the next cast
Freeze.afterglow = 0.5 -- seconds the effect lingers on screen once the hold ends
Freeze.tierStats = { "cooldown", "seconds", "radius", "range" } -- what a better tier improves, in order

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

-- Server --------------------------------------------------------------------

--- Hold everyone and everything inside the area; returns the ids of the
--- players caught, for the broadcast.
function Freeze.serverCast(server, caster, x, y, abilities, A)
  A = A or Freeze -- the freeze in the caster's tier
  local held = {}
  local r = A.radius
  for id, p in pairs(server.players) do
    if p ~= caster and Features.present(p) then
      local px, py, onFoot = Features.bodyPose(server, p)
      local pad = onFoot and Body.RADIUS or Car.WIDTH / 2
      if dist2(px, py, x, y) <= (r + pad) ^ 2 and abilities:serverHold(server, p, A.seconds) then
        held[#held + 1] = id
      end
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed or car.driver) and dist2(car.x, car.y, x, y) <= (r + Car.WIDTH / 2) ^ 2 then
      abilities:serverHoldCar(server, car, A.seconds)
    end
  end
  Features.call("serverFreezeArea", server, x, y, r, A.seconds, caster.id)
  return held
end

-- Client --------------------------------------------------------------------

local SHARDS = 9

--- The area on the ground: a burst ring on the cast, then a frosted disc
--- with a few shards that fades out as the hold ends.
function Freeze.drawEffect(e)
  local c = Freeze.color
  local r = (e.ability or Freeze).radius
  local fade = math.max(0, math.min(1, (e.seconds + Freeze.afterglow - e.t) / Freeze.afterglow))
  love.graphics.setColor(c[1], c[2], c[3], 0.14 * fade)
  love.graphics.circle("fill", e.x, e.y, r, 48)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(c[1], c[2], c[3], 0.5 * fade)
  love.graphics.circle("line", e.x, e.y, r, 48)
  -- Shards: fixed per cast, so they don't flicker.
  local seed = math.floor(e.x + e.y * 7)
  for i = 1, SHARDS do
    local a = (i + seed % SHARDS) * (2 * math.pi / SHARDS) + (seed % 17) * 0.1
    local len = r * (0.35 + ((seed * i) % 5) * 0.1)
    love.graphics.line(e.x, e.y, e.x + math.cos(a) * len, e.y + math.sin(a) * len)
  end
  if e.t < 0.35 then
    -- The cast itself: a ring that flashes out past the edge.
    local k = e.t / 0.35
    love.graphics.setLineWidth(3)
    love.graphics.setColor(0.9, 0.97, 1, 1 - k)
    love.graphics.circle("line", e.x, e.y, r * (0.3 + 0.9 * k), 48)
  end
  love.graphics.setLineWidth(1)
end

--- Ice over whoever is held: a glaze and a slow pulse of light.
function Freeze.drawHeld(x, y, radius, time)
  local c = Freeze.color
  local pulse = 0.5 + 0.5 * math.sin(time * 5)
  love.graphics.setColor(c[1], c[2], c[3], 0.35)
  love.graphics.circle("fill", x, y, radius, 24)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.9, 0.97, 1, 0.5 + 0.4 * pulse)
  love.graphics.circle("line", x, y, radius, 24)
  love.graphics.setLineWidth(1)
end

return Freeze
