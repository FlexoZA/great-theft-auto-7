-- Missiles in flight, client side: the body with its motor flame, and the
-- smoke trail it leaves. The trail is its own list of puffs, so it hangs in
-- the air and drifts apart after the missile has gone off.

local Rockets = {
  puffs = {}, -- { x, y, vx, vy, life, maxLife, size }
}

local PUFF_EVERY = 9 -- px of flight between puffs
local PUFF_LIFE = { 0.9, 1.5 } -- seconds
local PUFF_DRIFT = 18 -- px/s a puff wanders off
local LENGTH, WIDTH = 16, 5 -- px, the missile's body

local rnd = love.math.random

--- Lay smoke behind missile `p` ({ x, y, vx, vy }) for the ground it covered
--- this frame, one puff every PUFF_EVERY px so the trail is as dense at any
--- frame rate.
function Rockets.trail(p, dt)
  local speed = math.sqrt(p.vx * p.vx + p.vy * p.vy)
  if speed < 1 then
    return
  end
  p.smoke = (p.smoke or 0) + speed * dt
  local ux, uy = p.vx / speed, p.vy / speed
  while p.smoke >= PUFF_EVERY do
    p.smoke = p.smoke - PUFF_EVERY
    -- Back along the path to where this puff belongs, behind the nozzle.
    local back = p.smoke + LENGTH / 2
    local a = rnd() * 2 * math.pi
    local life = PUFF_LIFE[1] + rnd() * (PUFF_LIFE[2] - PUFF_LIFE[1])
    Rockets.puffs[#Rockets.puffs + 1] = {
      x = p.x - ux * back + (rnd() - 0.5) * 3,
      y = p.y - uy * back + (rnd() - 0.5) * 3,
      vx = math.cos(a) * PUFF_DRIFT * rnd(),
      vy = math.sin(a) * PUFF_DRIFT * rnd(),
      life = life,
      maxLife = life,
      size = 3 + rnd() * 2,
    }
  end
end

function Rockets.update(dt)
  local list = Rockets.puffs
  local i = 1
  while i <= #list do
    local s = list[i]
    s.life = s.life - dt
    if s.life <= 0 then
      list[i] = list[#list]
      list[#list] = nil
    else
      s.x, s.y = s.x + s.vx * dt, s.y + s.vy * dt
      i = i + 1
    end
  end
end

--- The trail, under the missiles.
function Rockets.drawTrail()
  for _, s in ipairs(Rockets.puffs) do
    local f = s.life / s.maxLife
    local r = s.size + (1 - f) * 12
    local shade = 0.55 + (1 - f) * 0.25 -- sooty at the nozzle, paler as it spreads
    love.graphics.setColor(shade, shade, shade, 0.55 * f)
    love.graphics.circle("fill", s.x, s.y, r)
  end
end

--- One missile ({ x, y, angle }), pointing along its flight, `time`
--- flickering the flame.
function Rockets.drawMissile(p, time)
  love.graphics.push()
  love.graphics.translate(p.x, p.y)
  love.graphics.rotate(p.angle or math.atan2(p.vy, p.vx))
  local flick = 0.75 + 0.25 * math.sin(time * 60 + p.x)
  love.graphics.setColor(1, 0.55, 0.1, 0.9)
  love.graphics.polygon("fill", -LENGTH / 2, -WIDTH / 2, -LENGTH / 2, WIDTH / 2, -LENGTH / 2 - 12 * flick, 0)
  love.graphics.setColor(1, 0.95, 0.5)
  love.graphics.polygon("fill", -LENGTH / 2, -WIDTH / 4, -LENGTH / 2, WIDTH / 4, -LENGTH / 2 - 6 * flick, 0)
  love.graphics.setColor(0.25, 0.25, 0.25)
  love.graphics.polygon("fill", -LENGTH / 2, -WIDTH / 2, -LENGTH / 2 - 3, -WIDTH, -LENGTH / 2 + 4, -WIDTH / 2)
  love.graphics.polygon("fill", -LENGTH / 2, WIDTH / 2, -LENGTH / 2 - 3, WIDTH, -LENGTH / 2 + 4, WIDTH / 2)
  love.graphics.setColor(0.4, 0.45, 0.3)
  love.graphics.rectangle("fill", -LENGTH / 2, -WIDTH / 2, LENGTH - 4, WIDTH)
  love.graphics.setColor(0.85, 0.2, 0.15)
  love.graphics.polygon("fill", LENGTH / 2 - 4, -WIDTH / 2, LENGTH / 2 - 4, WIDTH / 2, LENGTH / 2 + 2, 0)
  love.graphics.pop()
end

function Rockets.clear()
  Rockets.puffs = {}
end

return Rockets
