-- Vehicle explosions: client-side particles in a chunky pixel style, plus a
-- flash, a shockwave ring, a scorch mark that lingers and camera shake.

local Explosions = {
  list = {}, -- live explosions
  scorches = {}, -- { x, y, t }
  shake = 0, -- current shake amplitude in px
}

local SCORCH_TIME = 8
local SHAKE_DECAY = 6 -- per second

local rnd = love.math.random

local function snap(v)
  return math.floor(v / 2) * 2
end

local function burst(list, n, opts)
  for _ = 1, n do
    local a = rnd() * 2 * math.pi
    local speed = opts.speed[1] + rnd() * (opts.speed[2] - opts.speed[1])
    local life = opts.life[1] + rnd() * (opts.life[2] - opts.life[1])
    list[#list + 1] = {
      x = opts.x + (rnd() - 0.5) * (opts.spread or 0),
      y = opts.y + (rnd() - 0.5) * (opts.spread or 0),
      vx = math.cos(a) * speed,
      vy = math.sin(a) * speed,
      life = life,
      maxLife = life,
      size = opts.size,
      drag = opts.drag or 1.5,
      spin = (rnd() - 0.5) * 12,
      angle = rnd() * 2 * math.pi,
    }
  end
end

--- color: the destroyed car's colour, used for debris.
function Explosions.spawn(x, y, color)
  local e = { x = x, y = y, t = 0, color = color or { 0.8, 0.8, 0.8 }, fire = {}, smoke = {}, sparks = {}, debris = {} }
  burst(e.fire, 60, { x = x, y = y, spread = 30, speed = { 20, 170 }, life = { 0.4, 1.0 }, size = 16, drag = 3.0 })
  burst(e.smoke, 26, { x = x, y = y, spread = 40, speed = { 10, 60 }, life = { 1.4, 2.6 }, size = 18, drag = 1.0 })
  burst(e.sparks, 30, { x = x, y = y, speed = { 250, 520 }, life = { 0.15, 0.45 }, size = 2, drag = 1.2 })
  burst(e.debris, 9, { x = x, y = y, spread = 10, speed = { 90, 260 }, life = { 0.8, 1.5 }, size = 8, drag = 1.8 })
  Explosions.list[#Explosions.list + 1] = e
  Explosions.scorches[#Explosions.scorches + 1] = { x = x, y = y, t = SCORCH_TIME }
end

--- amount: peak shake in px (already scaled for distance by the caller).
function Explosions.addShake(amount)
  Explosions.shake = math.max(Explosions.shake, amount)
end

local function step(list, dt)
  local i = 1
  while i <= #list do
    local p = list[i]
    p.life = p.life - dt
    if p.life <= 0 then
      list[i] = list[#list]
      list[#list] = nil
    else
      local k = math.max(0, 1 - p.drag * dt)
      p.vx, p.vy = p.vx * k, p.vy * k
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.angle = p.angle + p.spin * dt
      i = i + 1
    end
  end
end

function Explosions.update(dt)
  local i = 1
  while i <= #Explosions.list do
    local e = Explosions.list[i]
    e.t = e.t + dt
    step(e.fire, dt)
    step(e.smoke, dt)
    step(e.sparks, dt)
    step(e.debris, dt)
    if e.t > 0.6 and #e.fire == 0 and #e.smoke == 0 and #e.sparks == 0 and #e.debris == 0 then
      table.remove(Explosions.list, i)
    else
      i = i + 1
    end
  end

  i = 1
  while i <= #Explosions.scorches do
    local s = Explosions.scorches[i]
    s.t = s.t - dt
    if s.t <= 0 then
      table.remove(Explosions.scorches, i)
    else
      i = i + 1
    end
  end

  Explosions.shake = math.max(0, Explosions.shake - Explosions.shake * SHAKE_DECAY * dt - dt * 2)
end

--- Apply the current shake to the camera (call from an update hook).
function Explosions.shakeCamera(camera)
  if camera and Explosions.shake > 0.5 then
    camera.x = camera.x + (rnd() - 0.5) * 2 * Explosions.shake
    camera.y = camera.y + (rnd() - 0.5) * 2 * Explosions.shake
  end
end

function Explosions.drawBelow()
  for _, s in ipairs(Explosions.scorches) do
    local a = math.min(1, s.t / 2) * 0.7
    love.graphics.setColor(0.05, 0.04, 0.04, a)
    love.graphics.ellipse("fill", snap(s.x), snap(s.y), 34, 26)
    love.graphics.setColor(0.12, 0.10, 0.09, a)
    love.graphics.ellipse("fill", snap(s.x) + 6, snap(s.y) - 4, 18, 12)
  end
  love.graphics.setColor(1, 1, 1)
end

function Explosions.drawAbove()
  for _, e in ipairs(Explosions.list) do
    -- Smoke first so fire sits on top of it.
    for _, p in ipairs(e.smoke) do
      local f = p.life / p.maxLife
      local size = snap(p.size + (1 - f) * 30)
      love.graphics.setColor(0.22, 0.20, 0.19, math.min(1, f * 1.4) * 0.85)
      love.graphics.rectangle("fill", snap(p.x) - size / 2, snap(p.y) - size / 2, size, size)
    end
    -- Fireball core: a blob that swells and burns out under the particles.
    if e.t < 0.45 then
      local k = e.t / 0.45
      local r = snap(14 + k * 44)
      love.graphics.setColor(1, 0.5, 0.1, 1 - k)
      love.graphics.rectangle("fill", snap(e.x) - r, snap(e.y) - r, r * 2, r * 2)
      love.graphics.setColor(1, 0.95, 0.55, (1 - k) ^ 2)
      love.graphics.rectangle("fill", snap(e.x) - r * 0.6, snap(e.y) - r * 0.6, r * 1.2, r * 1.2)
    end
    for _, p in ipairs(e.fire) do
      local f = p.life / p.maxLife
      local size = snap(p.size * (0.3 + f * 0.9))
      if f > 0.6 then
        love.graphics.setColor(1, 0.95, 0.5)
      elseif f > 0.3 then
        love.graphics.setColor(1, 0.45, 0.1)
      else
        love.graphics.setColor(0.6, 0.1, 0.05, f * 3)
      end
      love.graphics.rectangle("fill", snap(p.x) - size / 2, snap(p.y) - size / 2, size, size)
    end
    for _, p in ipairs(e.debris) do
      love.graphics.push()
      love.graphics.translate(snap(p.x), snap(p.y))
      love.graphics.rotate(p.angle)
      love.graphics.setColor(e.color[1], e.color[2], e.color[3])
      love.graphics.rectangle("fill", -p.size / 2, -p.size / 2, p.size, p.size * 0.6)
      love.graphics.pop()
    end
    love.graphics.setLineWidth(2)
    for _, p in ipairs(e.sparks) do
      love.graphics.setColor(1, 0.9, 0.4, p.life / p.maxLife)
      love.graphics.line(p.x, p.y, p.x - p.vx * 0.03, p.y - p.vy * 0.03)
    end
    love.graphics.setLineWidth(1)

    -- Flash and shockwave.
    if e.t < 0.15 then
      love.graphics.setColor(1, 1, 1, 1 - e.t / 0.15)
      love.graphics.circle("fill", e.x, e.y, 70)
    end
    if e.t < 0.5 then
      local k = e.t / 0.5
      love.graphics.setLineWidth(6 * (1 - k) + 1)
      love.graphics.setColor(1, 0.8, 0.5, 1 - k)
      love.graphics.circle("line", e.x, e.y, 20 + k * 200)
      love.graphics.setLineWidth(1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Explosions.clear()
  Explosions.list = {}
  Explosions.scorches = {}
  Explosions.shake = 0
end

return Explosions
