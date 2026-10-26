-- Vehicle explosions: client-side particles in a chunky pixel style, plus a
-- flash, a shockwave ring, a scorch mark that lingers and camera shake.
-- Bullet impacts on walls are the same particles, small: a few sparks, grit
-- and dust, and a pock mark. A round into a body (Explosions.hit) sprays
-- blood out of the far side and leaves drops on the ground; into a machine,
-- sparks.

local Explosions = {
  list = {}, -- live explosions
  scorches = {}, -- { x, y, t }
  shake = 0, -- current shake amplitude in px
  impacts = {}, -- live bullet impacts, oldest first
  marks = {}, -- { x, y, t }: pock marks where rounds hit walls, oldest first
  stains = {}, -- { x, y, size, color, t }: drops of blood on the ground, oldest first
}

local SCORCH_TIME = 8
local SHAKE_DECAY = 6 -- per second
local IMPACT_MAX = 40 -- live impacts at once; the oldest goes first
local MARK_MAX = 60
local MARK_TIME = 4 -- seconds a pock mark lingers
local STAIN_MAX = 80
local STAIN_TIME = 6 -- seconds a drop of blood lingers

-- What a round into a body throws up, by the material its feature answered
-- `serverShotAt` with ("flesh" when it said true). `mist` and `drops` are
-- the puff and the droplets' colours; "solid" is a wall's impact.
local BODIES = {
  flesh = {
    mist = { 0.6, 0.06, 0.05 }, drops = { 0.72, 0.05, 0.05 }, stain = { 0.4, 0.03, 0.03 }, flash = { 1, 0.2, 0.15 },
  },
  goo = {
    mist = { 0.55, 0.62, 0.12 }, drops = { 0.62, 0.78, 0.1 }, stain = { 0.36, 0.44, 0.06 }, flash = { 0.8, 1, 0.3 },
  },
  metal = { sparks = 7, drops = { 0.3, 0.3, 0.32 }, flash = { 1, 0.95, 0.7 } },
  shield = { sparks = 6, drops = { 0.45, 0.75, 1 }, flash = { 0.6, 0.85, 1 } }, -- the shield wall's dome
}
local SPARK = { 1, 0.95, 0.7 }
local DUST = { 0.62, 0.58, 0.52 }
local GRIT = { 0.35, 0.33, 0.3 }

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

--- Onto the end of `list`, dropping its oldest past `max`.
local function push(list, item, max)
  if #list >= max then
    table.remove(list, 1)
  end
  list[#list + 1] = item
end

--- A round stopped at a wall at (x, y), having flown along (dx, dy): a few
--- sparks and chips of grit kicked back the way it came, a puff of dust
--- and a pock mark that fades. Capped, oldest first, so a minigun into a
--- wall costs no more than IMPACT_MAX of them.
function Explosions.impact(x, y, dx, dy)
  local len = math.sqrt(dx * dx + dy * dy)
  local bx, by = len > 0 and -dx / len or 0, len > 0 and -dy / len or 0 -- back out of the wall
  local e = { x = x, y = y, t = 0, sparks = {}, dust = {}, chips = {} }
  burst(e.sparks, 4, { x = x, y = y, speed = { 160, 340 }, life = { 0.08, 0.2 }, size = 2, drag = 4 })
  burst(e.dust, 3, { x = x, y = y, spread = 4, speed = { 10, 40 }, life = { 0.3, 0.55 }, size = 4, drag = 3 })
  burst(e.chips, 3, { x = x, y = y, speed = { 60, 140 }, life = { 0.2, 0.4 }, size = 2, drag = 5 })
  -- Mostly back out of the wall rather than into it.
  for _, list in ipairs({ e.sparks, e.dust, e.chips }) do
    for _, p in ipairs(list) do
      local s = math.sqrt(p.vx * p.vx + p.vy * p.vy)
      p.vx, p.vy = p.vx * 0.5 + bx * s, p.vy * 0.5 + by * s
    end
  end
  push(Explosions.impacts, e, IMPACT_MAX)
  push(Explosions.marks, { x = x + bx * 2, y = y + by * 2, t = MARK_TIME }, MARK_MAX)
end

--- A round struck a body at (x, y), flying along (dx, dy); `material` is
--- what the body is made of (BODIES; nil is flesh, "solid" a wall's
--- impact). Flesh sprays droplets mostly out of the far side and a little
--- back the way the round came, puffs a red mist and drops a few spots on
--- the ground ahead; a machine throws sparks and grit back at the shooter.
function Explosions.hit(x, y, dx, dy, material)
  if material == "solid" then
    Explosions.impact(x, y, dx, dy)
    return
  end
  local body = BODIES[material] or BODIES.flesh
  local len = math.sqrt(dx * dx + dy * dy)
  local fx, fy = len > 0 and dx / len or 0, len > 0 and dy / len or 0 -- on through the body
  local e = { x = x, y = y, t = 0, sparks = {}, dust = {}, chips = {}, mist = body.mist, grit = body.drops,
    flash = body.flash }
  if body.sparks then
    burst(e.sparks, body.sparks, { x = x, y = y, speed = { 180, 380 }, life = { 0.08, 0.22 }, size = 2, drag = 4 })
    burst(e.chips, 2, { x = x, y = y, speed = { 60, 140 }, life = { 0.2, 0.4 }, size = 2, drag = 5 })
    for _, list in ipairs({ e.sparks, e.chips }) do
      for _, p in ipairs(list) do -- back at the shooter, off the plating
        local s = math.sqrt(p.vx * p.vx + p.vy * p.vy)
        p.vx, p.vy = p.vx * 0.5 - fx * s, p.vy * 0.5 - fy * s
      end
    end
  else
    burst(e.dust, 3, { x = x, y = y, spread = 3, speed = { 10, 40 }, life = { 0.2, 0.35 }, size = 4, drag = 4 })
    burst(e.chips, 10, { x = x, y = y, speed = { 90, 280 }, life = { 0.15, 0.35 }, size = 2, drag = 6 })
    for k, p in ipairs(e.chips) do -- most out of the far side, the odd one back
      local s = math.sqrt(p.vx * p.vx + p.vy * p.vy)
      local way = k <= 3 and -0.6 or 1
      p.vx, p.vy = p.vx * 0.4 + fx * s * way, p.vy * 0.4 + fy * s * way
    end
    for _ = 1, 2 + math.floor(rnd() * 2) do
      local d = 14 + rnd() * 22 -- past the body, which stands over the rest
      push(Explosions.stains, {
        x = x + fx * d + (rnd() - 0.5) * 8,
        y = y + fy * d + (rnd() - 0.5) * 8,
        size = rnd() < 0.3 and 4 or 2,
        color = body.stain,
        t = STAIN_TIME,
      }, STAIN_MAX)
    end
  end
  push(Explosions.impacts, e, IMPACT_MAX)
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

  for k = #Explosions.impacts, 1, -1 do -- backwards, so a removal skips nothing
    local e = Explosions.impacts[k]
    e.t = e.t + dt
    step(e.sparks, dt)
    step(e.dust, dt)
    step(e.chips, dt)
    if #e.sparks == 0 and #e.dust == 0 and #e.chips == 0 then
      table.remove(Explosions.impacts, k)
    end
  end
  for _, list in ipairs({ Explosions.marks, Explosions.stains }) do
    for k = #list, 1, -1 do
      local m = list[k]
      m.t = m.t - dt
      if m.t <= 0 then
        table.remove(list, k)
      end
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
  for _, s in ipairs(Explosions.stains) do -- blood on the ground, under whoever walks through it
    local c = s.color
    love.graphics.setColor(c[1], c[2], c[3], 0.85 * math.min(1, s.t / 2))
    love.graphics.rectangle("fill", snap(s.x), snap(s.y), s.size, s.size)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Bullet impacts, drawn over the cars like the rest of a fight: the pock
--- marks first (they sit on the wall's face, which is drawn under the cars
--- along with the map), then the dust, grit and sparks.
local function drawImpacts()
  for _, m in ipairs(Explosions.marks) do
    local a = math.min(1, m.t / 1.5)
    love.graphics.setColor(0.08, 0.07, 0.06, 0.75 * a)
    love.graphics.rectangle("fill", snap(m.x) - 2, snap(m.y) - 2, 4, 4)
    love.graphics.setColor(0.55, 0.52, 0.48, 0.5 * a)
    love.graphics.rectangle("fill", snap(m.x) - 2, snap(m.y) - 4, 4, 2)
  end
  love.graphics.setLineWidth(1)
  for _, e in ipairs(Explosions.impacts) do
    local mist, grit = e.mist or DUST, e.grit or GRIT
    for _, p in ipairs(e.dust) do
      local f = p.life / p.maxLife
      local size = snap(p.size + (1 - f) * 8)
      love.graphics.setColor(mist[1], mist[2], mist[3], f * 0.6)
      love.graphics.rectangle("fill", snap(p.x) - size / 2, snap(p.y) - size / 2, size, size)
    end
    for _, p in ipairs(e.chips) do
      love.graphics.setColor(grit[1], grit[2], grit[3], p.life / p.maxLife)
      love.graphics.rectangle("fill", snap(p.x) - 1, snap(p.y) - 1, p.size, p.size)
    end
    for _, p in ipairs(e.sparks) do
      love.graphics.setColor(1, 0.85, 0.4, p.life / p.maxLife)
      love.graphics.line(p.x, p.y, p.x - p.vx * 0.025, p.y - p.vy * 0.025)
    end
    if e.t < 0.05 then -- the flash of the strike itself
      local c = e.flash or SPARK
      love.graphics.setColor(c[1], c[2], c[3], 1 - e.t / 0.05)
      love.graphics.circle("fill", e.x, e.y, 4)
    end
  end
end

function Explosions.drawAbove()
  drawImpacts()
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
  Explosions.impacts = {}
  Explosions.marks = {}
  Explosions.stains = {}
  Explosions.shake = 0
end

return Explosions
