-- Heat ray: the tripod's own weapon, torn off its wreck (the events
-- feature's tripod drops it; never sold). The first ability with modes:
-- tap its key to aim the mode it is on and the fire button to cast; hold
-- the key and the abilities feature offers its `modes` to pick between.
--
--   beam   a white-hot ray from you onto the spot you pick (within
--          `range`), burning it for `seconds`: `damage` to anyone standing
--          in it the whole time.
--   sweep  the ray dragged across the ground in front of you, an arc
--          `sweepRadius` out and `sweepArc` wide, from one side to the
--          other over `seconds`. It is on each spot only a moment, so it
--          burns hotter (`sweepHeat` times the beam).
--
-- Either one hurts everything in `radius` of where it is burning but you:
-- other players and bots on foot (setting them alight: they burn on for
-- `afterburnTime` at `afterburnDps`), every car but the one you are driving,
-- and whatever other features answer `serverShotAt` (pedestrians,
-- officers, simps, a boss: the tripod can be burned with its own ray).
-- Kills and hits are yours.

local Features = require("src.features")
local Car = require("src.car")
local TripodRender = require("src.features.tripod.render")

local Heat = {
  key = "heatray", -- on the wire and in a bag ("ability-heatray")
  title = "heat ray",
  blurb = "The tripod's heat ray. Tap to aim, hold to switch between beam and sweep. Only won by beating it.",
  hud = "heat ray",
  sound = "heatray",
  color = { 0.60, 0.88, 1.00 },
  aim = "point", -- a press shows where it would burn, the fire button burns it
  unsold = true, -- the shop leaves it off the shelf
  modes = {
    { key = "beam", title = "beam" },
    { key = "sweep", title = "sweep" },
  },
}

-- Tuning ------------------------------------------------------------------
Heat.range = 450 -- px: the furthest spot the beam reaches
Heat.radius = 30 -- px round the burning spot that it hurts
Heat.seconds = 1.2 -- how long it burns (a beam) or takes to cross (a sweep)
Heat.cooldown = 12 -- seconds before the next, whichever mode
Heat.afterglow = 0.4 -- seconds the scorch glows once it is done
Heat.damage = 100 -- a whole beam to somebody standing in it
Heat.sweepHeat = 4.5 -- how much hotter a sweep burns: it passes a spot in a fifth of a second (~75)
Heat.carHeat = 1.3 -- how much more a car takes than a body
Heat.afterburnTime = 3 -- seconds somebody it caught on foot burns on afterwards
Heat.afterburnDps = 10 -- fire damage a second while they do
Heat.sweepRadius = 200 -- px out in front the sweep crosses
Heat.sweepArc = 1.8 -- radians the sweep covers, side to side
Heat.tierStats = { "cooldown", "damage", "radius" } -- what a better tier improves, in order

local BITE = 0.1 -- seconds between bites of the ray

local burns = {} -- { by, mode, x, y, angle, t, seconds, damage, radius, biteIn }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- Where a burn is on fire `k` (0..1) of the way through: the beam's spot,
--- or the point of the sweep along its arc round (x, y).
local function burnPoint(mode, x, y, angle, k)
  if mode ~= "sweep" then
    return x, y
  end
  local a = angle - Heat.sweepArc / 2 + Heat.sweepArc * k
  return x + math.cos(a) * Heat.sweepRadius, y + math.sin(a) * Heat.sweepRadius
end

-- Server --------------------------------------------------------------------

function Heat.serverReset()
  burns = {}
end

--- A beam onto (x, y), or a sweep in front of the caster towards it. Nobody
--- is held; the sweep goes out from where the caster stands.
function Heat.serverCast(server, caster, x, y, _abilities, A, mode)
  A = A or Heat -- the heat ray in the caster's tier
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  local sweep = mode == "sweep"
  if sweep then
    x, y = ox, oy
  end
  burns[#burns + 1] = {
    by = caster.id, mode = sweep and "sweep" or "beam", x = x, y = y, angle = angle, t = 0, seconds = A.seconds,
    damage = A.damage, radius = A.radius, biteIn = 0,
  }
  return {}, angle, x, y
end

--- One bite of burn `b` at (x, y): everyone on foot but the caster, every
--- car but theirs, and whatever else answers `serverShotAt`. Anyone on foot
--- it catches is set alight, and burns on for a while once out of it.
local function bite(server, b, x, y, amount)
  local caster = server.players[b.by]
  local weapons = Features.byName.weapons
  local damage = Features.byName.damage
  local r = b.radius
  if weapons then
    for id, p in pairs(server.players) do
      if id ~= b.by and Features.present(p) then
        local px, py, onFoot = Features.bodyPose(server, p)
        if onFoot and dist2(px, py, x, y) <= r * r then
          weapons:serverDamage(server, p, caster, amount, math.atan2(py - y, px - x), "fire")
          if damage then
            damage:ignite(server, p, Heat.afterburnTime, Heat.afterburnDps, b.by)
          end
        end
      end
    end
    if weapons.damageCar then
      local reach = r + Car.WIDTH / 2
      local own = caster and caster.vehicle
      for _, car in pairs(server.vehicles) do
        if car ~= own and not (car.hidden or car.stowed) and dist2(car.x, car.y, x, y) <= reach * reach then
          weapons:damageCar(server, car, b.by, amount * Heat.carHeat, 0, b.angle, "fire")
        end
      end
    end
  end
  for _, f in ipairs(Features.list) do
    if f.serverShotAt then
      f:serverShotAt(server, x, y, r, b.by, b.angle, amount, "fire")
    end
  end
end

--- Every burn bites where it is on fire, a tenth of a second at a time.
function Heat.serverStep(server, dt)
  for i = #burns, 1, -1 do
    local b = burns[i]
    b.t = b.t + dt
    b.biteIn = b.biteIn - dt
    while b.biteIn <= 0 and b.t <= b.seconds + BITE / 2 do
      b.biteIn = b.biteIn + BITE
      local x, y = burnPoint(b.mode, b.x, b.y, b.angle, math.min(1, b.t / b.seconds))
      local heat = b.mode == "sweep" and Heat.sweepHeat or 1
      bite(server, b, x, y, b.damage / b.seconds * BITE * heat)
    end
    if b.t > b.seconds then
      table.remove(burns, i)
    end
  end
end

--- For tests.
function Heat.serverBurns()
  return burns
end

-- Client --------------------------------------------------------------------

--- While it is selected: for a beam, a dotted line from me to the spot and
--- the ring it would burn; for a sweep, the arc it would cross in front of me.
function Heat.drawAim(ox, oy, x, y, time, mode)
  local c = Heat.color
  local pulse = 0.5 + 0.5 * math.sin(time * 6)
  if mode == "sweep" then
    local angle = math.atan2(y - oy, x - ox)
    local lo, hi = angle - Heat.sweepArc / 2, angle + Heat.sweepArc / 2
    love.graphics.setLineWidth(Heat.radius * 2)
    love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.08 * pulse)
    love.graphics.arc("line", "open", ox, oy, Heat.sweepRadius, lo, hi, 32)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(c[1], c[2], c[3], 0.7)
    love.graphics.arc("line", "open", ox, oy, Heat.sweepRadius - Heat.radius, lo, hi, 32)
    love.graphics.arc("line", "open", ox, oy, Heat.sweepRadius + Heat.radius, lo, hi, 32)
    -- An arrowhead at the far end: the way it goes.
    local ex, ey = ox + math.cos(hi) * Heat.sweepRadius, oy + math.sin(hi) * Heat.sweepRadius
    local tx, ty = -math.sin(hi), math.cos(hi)
    love.graphics.polygon("fill", ex + tx * 12, ey + ty * 12, ex - ty * 8, ey + tx * 8, ex + ty * 8, ey - tx * 8)
  else
    local d = math.sqrt(dist2(x, y, ox, oy))
    love.graphics.setColor(c[1], c[2], c[3], 0.6)
    love.graphics.setLineWidth(2)
    for s = 14, d - Heat.radius, 16 do
      local k0, k1 = s / d, math.min(s + 8, d - Heat.radius) / d
      love.graphics.line(ox + (x - ox) * k0, oy + (y - oy) * k0, ox + (x - ox) * k1, oy + (y - oy) * k1)
    end
    love.graphics.setColor(c[1], c[2], c[3], 0.16 + 0.1 * pulse)
    love.graphics.circle("fill", x, y, Heat.radius, 32)
    love.graphics.setColor(c[1], c[2], c[3], 0.85)
    love.graphics.circle("line", x, y, Heat.radius, 32)
  end
  love.graphics.setLineWidth(1)
end

--- The scorch it leaves: the spot, or the stretch of arc burned so far.
function Heat.drawBelow(e)
  local fade = math.max(0, math.min(1, (e.seconds + e.ability.afterglow - e.t) / e.ability.afterglow))
  local k = math.min(1, e.t / e.seconds)
  love.graphics.setColor(0.08, 0.05, 0.04, 0.45 * fade)
  if e.mode == "sweep" then
    local lo = e.angle - Heat.sweepArc / 2
    love.graphics.setLineWidth(e.ability.radius * 1.4)
    love.graphics.arc("line", "open", e.x, e.y, Heat.sweepRadius, lo, lo + Heat.sweepArc * k, 32)
    love.graphics.setLineWidth(1)
  else
    love.graphics.circle("fill", e.x, e.y, e.ability.radius * (0.6 + 0.4 * k), 24)
  end
end

--- The ray itself while it burns, from the caster (where they are drawn
--- now) to where it is on fire, the tripod's look.
function Heat.drawEffect(e, client)
  if e.t > e.seconds then
    return
  end
  local x, y = burnPoint(e.mode, e.x, e.y, e.angle, math.min(1, e.t / e.seconds))
  local ox, oy = client:pose(e.by)
  if not ox then
    ox, oy = e.mode == "sweep" and e.x or x, e.mode == "sweep" and e.y or y
  end
  TripodRender.heatRay(ox, oy, x, y, love.timer.getTime())
end

return Heat
