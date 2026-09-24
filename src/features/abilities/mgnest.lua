-- MG nest: a machine gun on a tripod behind sandbags, put down a short way
-- from you, facing the way you point. For five seconds it sprays
-- its forty-five-degree arc with rifle fire, sweeping from side to side
-- (weapons' AK-47 rounds, owned by whoever placed it, so its kills are
-- theirs and it never hits them). It picks no targets: the rounds hurt
-- whatever they meet the way any bullet does, other players, cars, the
-- crowd, officers, Karen and her simps alike. Then it is gone.
--
-- It aims differently from freeze: press its key to select it and an
-- arrow from you shows where the nest would go and which way it would
-- face (towards the cursor); the fire button puts it there, the key again
-- or right-click puts it away. `aim = "direction"` asks the abilities
-- feature for that flow.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")

local Nest = {
  key = "mgnest", -- on the wire and in a bag ("ability-mgnest")
  title = "MG nest",
  sound = "mgnest",
  color = { 1, 0.62, 0.25 }, -- brass
  aim = "direction",
}

-- Tuning ------------------------------------------------------------------
Nest.range = 80 -- px in front of you the nest is put down: just clear of a car's nose
Nest.radius = 22 -- px, the sandbag ring
Nest.arc = math.rad(45) -- the whole arc it covers, centred on its facing
Nest.reach = 420 -- px of the arc drawn on the ground (the rounds fly on like any rifle round)
Nest.seconds = 5 -- how long it stands: a short, savage burst
Nest.cooldown = 30 -- seconds before the next one
Nest.afterglow = 0.6 -- seconds the sandbags linger on screen once it is spent
Nest.gun = Guns.ak47 -- what it fires; its damage, speed and scatter
Nest.fireEvery = 0.04 -- seconds between rounds: twenty-five a second, a proper machine gun
Nest.sweep = 1.6 -- seconds one pass from one side of the arc to the other and back takes
Nest.barrel = 16 -- px from the middle to the muzzle

local nests = {} -- { owner, x, y, angle, placedAt, untilT, nextShot }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

-- Server --------------------------------------------------------------------

function Nest.serverReset()
  nests = {}
end

--- Put a nest down at (x, y), facing away from the caster. Nobody is held,
--- so the list is empty; the facing goes out with ABL_FIRED.
function Nest.serverCast(server, caster, x, y, abilities)
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  -- Not inside a wall: pulled back towards the caster until it stands clear.
  local d = math.sqrt(dist2(x, y, ox, oy))
  while d > 0 and Features.any("blocksPoint", x, y) do
    d = math.max(0, d - 8)
    x, y = ox + math.cos(angle) * d, oy + math.sin(angle) * d
  end
  local now = abilities.sv.time
  nests[#nests + 1] = {
    owner = caster.id, x = x, y = y, angle = angle, placedAt = now, untilT = now + Nest.seconds, nextShot = 0,
  }
  return {}, angle, x, y
end

--- Where a nest is pointing `t` seconds after it was put down: swinging
--- across its arc and back, a little short of the edges.
local function sweepAngle(nest, t)
  return nest.angle + (Nest.arc / 2) * 0.9 * math.sin(2 * math.pi * t / Nest.sweep)
end

--- Every nest sprays its arc, a round at a time, sweeping as it goes.
function Nest.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  local weapons = Features.byName.weapons
  for i = #nests, 1, -1 do
    local nest = nests[i]
    if now >= nest.untilT then
      table.remove(nests, i)
    elseif weapons and weapons.serverFireFrom then
      -- Faster than the host ticks: every round owed since the last tick.
      if nest.nextShot < now - Nest.fireEvery * 3 then
        nest.nextShot = now -- don't make up for time lost to a stall
      end
      while now >= nest.nextShot do
        local aim = sweepAngle(nest, nest.nextShot - nest.placedAt)
        local mx, my = nest.x + math.cos(aim) * Nest.barrel, nest.y + math.sin(aim) * Nest.barrel
        weapons:serverFireFrom(server, nest.owner, mx, my, aim, Nest.gun)
        nest.nextShot = nest.nextShot + Nest.fireEvery
      end
    end
  end
end

--- For tests.
function Nest.serverNests()
  return nests
end

-- Client --------------------------------------------------------------------

--- The arc a nest at (x, y) facing `angle` covers, as a wedge.
local function wedge(mode, x, y, angle, reach)
  love.graphics.arc(mode, "pie", x, y, reach, angle - Nest.arc / 2, angle + Nest.arc / 2, 24)
end

--- Sandbags in a ring, the gun on its tripod pointing along `angle`.
local function drawNest(x, y, angle, alpha)
  local c = Nest.color
  love.graphics.setColor(0.45, 0.4, 0.28, alpha)
  love.graphics.circle("fill", x, y, Nest.radius, 24)
  love.graphics.setColor(0.6, 0.53, 0.36, alpha)
  for k = 0, 7 do
    local a = k * math.pi / 4 + angle
    love.graphics.circle("fill", x + math.cos(a) * (Nest.radius - 5), y + math.sin(a) * (Nest.radius - 5), 6, 12)
  end
  love.graphics.setColor(0.2, 0.2, 0.22, alpha)
  love.graphics.circle("fill", x, y, 7, 16)
  love.graphics.setLineWidth(4)
  love.graphics.line(x, y, x + math.cos(angle) * (Nest.barrel + 8), y + math.sin(angle) * (Nest.barrel + 8))
  love.graphics.setLineWidth(2)
  love.graphics.setColor(c[1], c[2], c[3], alpha)
  love.graphics.line(x, y, x + math.cos(angle) * Nest.barrel, y + math.sin(angle) * Nest.barrel)
  love.graphics.setLineWidth(1)
end

--- While the ability is selected: an arrow from me to where the nest would
--- stand, the nest as a ghost there, and the arc it would cover.
function Nest.drawAim(ox, oy, x, y, time)
  local c = Nest.color
  local angle = math.atan2(y - oy, x - ox)
  local pulse = 0.5 + 0.5 * math.sin(time * 6)
  love.graphics.setColor(c[1], c[2], c[3], 0.10 + 0.06 * pulse)
  wedge("fill", x, y, angle, Nest.reach)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(c[1], c[2], c[3], 0.5)
  wedge("line", x, y, angle, Nest.reach)
  -- The arrow: a shaft from me, a head at the nest.
  love.graphics.setLineWidth(3)
  love.graphics.setColor(c[1], c[2], c[3], 0.9)
  local sx, sy = ox + math.cos(angle) * 24, oy + math.sin(angle) * 24
  local hx, hy = x - math.cos(angle) * (Nest.radius + 4), y - math.sin(angle) * (Nest.radius + 4)
  love.graphics.line(sx, sy, hx, hy)
  local left, right = angle + 2.5, angle - 2.5
  love.graphics.polygon("fill", hx + math.cos(angle) * 10, hy + math.sin(angle) * 10,
    hx + math.cos(left) * 12, hy + math.sin(left) * 12, hx + math.cos(right) * 12, hy + math.sin(right) * 12)
  love.graphics.setLineWidth(1)
  drawNest(x, y, angle, 0.55)
end

--- The nest in the world for as long as it stands, its arc faint on the
--- ground, fading out through the afterglow once it is spent.
function Nest.drawEffect(e)
  local c = Nest.color
  local fade = math.max(0, math.min(1, (e.seconds + Nest.afterglow - e.t) / Nest.afterglow))
  local angle = e.angle or 0
  love.graphics.setColor(c[1], c[2], c[3], 0.07 * fade)
  wedge("fill", e.x, e.y, angle, Nest.reach)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(c[1], c[2], c[3], 0.3 * fade)
  wedge("line", e.x, e.y, angle, Nest.reach)
  drawNest(e.x, e.y, angle, fade)
  if e.t < 0.3 then
    -- Just put down: a puff of dust settling round the sandbags.
    local k = e.t / 0.3
    love.graphics.setColor(0.7, 0.62, 0.45, 0.5 * (1 - k))
    love.graphics.circle("fill", e.x, e.y, Nest.radius + 4 + k * 22, 24)
  end
  love.graphics.setColor(1, 1, 1)
end

return Nest
