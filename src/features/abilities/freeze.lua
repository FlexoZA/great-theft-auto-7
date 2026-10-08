-- Freeze: everything inside the target area stops dead for a few seconds.
-- Players on foot or behind a wheel, cars nobody is driving, and whatever
-- else lives in the world (pedestrians, officers, Karen) through the
-- `serverFreezeArea` event. The caster is never caught in their own cast.
--
-- It does not land at once: for `windup` seconds a warning ring shows on
-- every screen where it is coming down, frost filling it in from the
-- middle as the moment nears, so anyone can get out of it. The host keeps
-- the freezes still to land (`serverIncoming`, which the abilities feature
-- hands to whoever dodges: hunters, bosses, bots) and holds whoever is
-- inside when the time is up (ABL_HELD tells the clients who).

local Features = require("src.features")
local Protocol = require("src.net.protocol")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")

local Freeze = {
  key = "freeze", -- on the wire and in a bag ("ability-freeze")
  title = "freeze",
  blurb = "A moment after you cast it, everything in the target area stops dead for a few seconds: players, cars, "
    .. "the crowd. Never you.",
  sound = "freeze-warn", -- on the cast; "freeze" itself when it lands
  color = { 0.55, 0.85, 1.0 }, -- ice
}

-- Tuning ------------------------------------------------------------------
Freeze.radius = 110 -- px; the area caught
Freeze.range = 380 -- px; how far from you it can be placed
Freeze.windup = 0.75 -- seconds the warning shows before it lands
Freeze.seconds = 3 -- how long the catch lasts
Freeze.cooldown = 12 -- seconds before the next cast
Freeze.afterglow = 0.5 -- seconds the effect lingers on screen once the hold ends
Freeze.tierStats = { "cooldown", "seconds", "radius", "range" } -- what a better tier improves, in order

local pending = {} -- host: freezes still to land, { ability, by, x, y, landsAt, castAt }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

-- Server --------------------------------------------------------------------

function Freeze.serverReset()
  pending = {}
end

--- Mark the spot; it lands `windup` seconds from now. Nobody is held yet:
--- the effect runs through the warning and the hold.
function Freeze.serverCast(_server, caster, x, y, abilities, A)
  A = A or Freeze -- the freeze in the caster's tier
  local now = abilities.sv.time
  pending[#pending + 1] = { ability = A, by = caster.id, x = x, y = y, landsAt = now + A.windup, castAt = now }
  return {}, 0, x, y, A.windup + A.seconds
end

--- Hold everyone and everything inside the area; returns the ids of the
--- players caught.
local function land(server, f, abilities)
  local A = f.ability
  local held = {}
  local r = A.radius
  for id, p in pairs(server.players) do
    if id ~= f.by and Features.present(p) then
      local px, py, onFoot = Features.bodyPose(server, p)
      local pad = onFoot and Body.RADIUS or Car.WIDTH / 2
      if dist2(px, py, f.x, f.y) <= (r + pad) ^ 2 and abilities:serverHold(server, p, A.seconds) then
        held[#held + 1] = id
      end
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed or car.driver) and dist2(car.x, car.y, f.x, f.y) <= (r + Car.WIDTH / 2) ^ 2 then
      abilities:serverHoldCar(server, car, A.seconds)
    end
  end
  Features.call("serverFreezeArea", server, f.x, f.y, r, A.seconds, f.by)
  return held
end

--- Land every freeze whose warning has run out.
function Freeze.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  for i = #pending, 1, -1 do
    local f = pending[i]
    if now >= f.landsAt then
      table.remove(pending, i)
      local held = land(server, f, abilities)
      if #held > 0 then
        server:broadcast(Protocol.encode("ABL_HELD", ("%.2f"):format(f.ability.seconds), unpack(held)))
      end
    end
  end
end

--- The freezes about to land, for whoever wants out of the way: added to
--- `list` as { x, y, radius, age (seconds since the cast), left (until it lands) }.
function Freeze.serverIncoming(list, now)
  for _, f in ipairs(pending) do
    list[#list + 1] = { x = f.x, y = f.y, radius = f.ability.radius, age = now - f.castAt, left = f.landsAt - now }
  end
end

--- What is still to land: for tests.
function Freeze.serverPending()
  return pending
end

-- Client --------------------------------------------------------------------

local TAU = 2 * math.pi
local WHITE = { 0.92, 0.98, 1 }
local DEEP = { 0.25, 0.55, 0.85 } -- the blue in the ice's shadows
local BURST = 0.4 -- seconds the landing's flash and shockwave take
local POP = 0.18 -- seconds the crystals take to shoot up

--- A random stream of its own per cast, so every client draws the same
--- frost and it holds still from frame to frame.
local function rng(seed)
  local s = seed % 2147483647
  if s <= 0 then
    s = s + 2147483646
  end
  return function()
    s = (s * 16807) % 2147483647
    return s / 2147483647
  end
end

--- Everything the frost is made of, worked out once per cast: the jagged
--- rim, cracks running out from the middle, ice crystals standing up out
--- of the ground, snowflakes and the motes the warning draws in.
local function build(e)
  local r = (e.ability or Freeze).radius
  local rand = rng(math.floor(e.x * 13 + e.y * 7 + 1e6))
  local f = { rim = {}, cracks = {}, crystals = {}, flakes = {}, motes = {} }
  for i = 0, 35 do
    local a = i / 36 * TAU
    local k = 0.95 + rand() * 0.09
    f.rim[#f.rim + 1] = math.cos(a) * r * k
    f.rim[#f.rim + 1] = math.sin(a) * r * k
  end
  for i = 1, 7 do
    local a = (i + rand() * 0.6) / 7 * TAU
    local x, y = math.cos(a) * r * 0.08, math.sin(a) * r * 0.08
    local line = { x, y }
    local reach = r * (0.5 + rand() * 0.3)
    local steps = 4
    for s = 1, steps do
      a = a + (rand() - 0.5) * 0.7
      local d = reach / steps
      x, y = x + math.cos(a) * d, y + math.sin(a) * d
      local out = math.sqrt(x * x + y * y) / (r * 0.85)
      if out > 1 then
        x, y = x / out, y / out -- inside the rim
      end
      line[#line + 1], line[#line + 1] = x, y
      if s == 2 and rand() < 0.7 then
        local b = a + (rand() < 0.5 and -1 or 1) * (0.5 + rand() * 0.4)
        local bl = r * (0.1 + rand() * 0.1)
        f.cracks[#f.cracks + 1] = { x, y, x + math.cos(b) * bl, y + math.sin(b) * bl }
      end
    end
    f.cracks[#f.cracks + 1] = line
  end
  for _ = 1, 14 do
    local a = rand() * TAU
    local d = r * (0.3 + 0.62 * math.sqrt(rand())) -- more out towards the rim
    f.crystals[#f.crystals + 1] = {
      x = math.cos(a) * d, y = math.sin(a) * d,
      angle = a + (rand() - 0.5) * 0.9, -- leaning outwards
      len = 12 + rand() * 14, w = 4 + rand() * 3,
      twinkle = rand() * TAU, delay = rand() * 0.08,
    }
  end
  for _ = 1, 12 do
    f.flakes[#f.flakes + 1] = {
      a = rand() * TAU, d = r * math.sqrt(rand()) * 0.9, spin = (rand() - 0.5) * 2,
      drift = 6 + rand() * 10, size = 2 + rand() * 2.5, phase = rand() * TAU,
    }
  end
  for _ = 1, 20 do
    f.motes[#f.motes + 1] = { a = rand() * TAU, phase = rand(), swirl = 0.4 + rand() * 0.5 }
  end
  e.frost = f
  return f
end

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a)
end

--- A small six-armed flake at (x, y).
local function flake(x, y, size, angle)
  for i = 0, 2 do
    local a = angle + i * math.pi / 3
    local dx, dy = math.cos(a) * size, math.sin(a) * size
    love.graphics.line(x - dx, y - dy, x + dx, y + dy)
  end
end

--- One ice crystal, `grow` (0..1) of the way up: a long diamond leaning
--- out of the ground, its lit face paler than its shadowed one.
local function crystal(cx, cy, c, grow, alpha, time)
  if grow <= 0 then
    return
  end
  local ux, uy = math.cos(c.angle), math.sin(c.angle)
  local px, py = -uy, ux
  local len, w = c.len * grow, c.w * math.min(1, grow * 1.5)
  local bx, by = cx + c.x - ux * len * 0.25, cy + c.y - uy * len * 0.25
  local tx, ty = bx + ux * len, by + uy * len
  local mx, my = bx + ux * len * 0.35, by + uy * len * 0.35
  local lx, ly, rx, ry = mx + px * w, my + py * w, mx - px * w, my - py * w
  setColor(DEEP, 0.75 * alpha)
  love.graphics.polygon("fill", bx, by, rx, ry, tx, ty)
  setColor(Freeze.color, 0.85 * alpha)
  love.graphics.polygon("fill", bx, by, lx, ly, tx, ty)
  setColor(WHITE, 0.9 * alpha)
  love.graphics.setLineWidth(1)
  love.graphics.line(bx, by, lx, ly, tx, ty, rx, ry, bx, by)
  love.graphics.line(bx, by, tx, ty)
  -- Now and then the light catches the tip.
  local glint = math.sin(time * 2.3 + c.twinkle)
  if grow >= 1 and glint > 0.86 then
    local s = (glint - 0.86) / 0.14 * 5
    setColor(WHITE, alpha)
    love.graphics.line(tx - s, ty, tx + s, ty)
    love.graphics.line(tx, ty - s, tx, ty + s)
  end
end

--- The warning, `k` (0..1) of the way to landing: a ring turning round
--- the area and blinking faster as it nears, frost filling it in from the
--- middle, motes drawn in towards it.
local function drawWarning(e, f, r, k)
  local c = Freeze.color
  local x, y = e.x, e.y
  setColor(c, 0.07 + 0.08 * k)
  love.graphics.circle("fill", x, y, r, 48)
  setColor(c, 0.16 + 0.12 * k)
  love.graphics.circle("fill", x, y, r * k, 48)
  love.graphics.setLineWidth(1.5)
  setColor(WHITE, 0.35 + 0.4 * k)
  love.graphics.circle("line", x, y, r * k, 48)
  -- The ring: dashes turning round, blinking quicker as it comes.
  local blink = 0.5 + 0.5 * math.sin(e.t * (10 + 26 * k))
  local turn = e.t * 0.9
  love.graphics.setLineWidth(3)
  setColor(WHITE, 0.55 + 0.4 * blink)
  local dashes = 16
  for i = 0, dashes - 1 do
    local a0 = turn + i / dashes * TAU
    love.graphics.arc("line", "open", x, y, r, a0, a0 + TAU / dashes * 0.6, 6)
  end
  love.graphics.setLineWidth(1.5)
  setColor(c, 0.5)
  love.graphics.circle("line", x, y, r + 6, 48)
  -- Motes: in from past the rim, swirling a little as they come.
  for _, m in ipairs(f.motes) do
    local p = (e.t * 1.4 + m.phase) % 1
    local d = r * (1.25 - p)
    local a = m.a + p * m.swirl
    setColor(WHITE, 0.8 * math.sin(p * math.pi))
    love.graphics.circle("fill", x + math.cos(a) * d, y + math.sin(a) * d, 1.8, 6)
  end
  -- The snowflake at the middle, growing as it comes.
  love.graphics.setLineWidth(2)
  setColor(WHITE, 0.5 + 0.4 * k)
  flake(x, y, 6 + 10 * k, e.t * 1.5)
end

--- The ground once it has landed: frosted over to a jagged rim, cracked,
--- crystals standing up out of it and snowflakes drifting over, a ring
--- round the rim running down the hold. `since` is seconds since it
--- landed, `fade` 1 until the hold ends and down to 0 after.
local function drawFrost(e, f, r, since, hold, fade)
  local c = Freeze.color
  local x, y = e.x, e.y
  setColor(DEEP, 0.16 * fade)
  love.graphics.circle("fill", x, y, r, 48)
  setColor(c, 0.12 * fade)
  love.graphics.circle("fill", x, y, r * 0.9, 48)
  setColor(WHITE, 0.08 * fade)
  love.graphics.circle("fill", x, y, r * 0.55, 40)
  -- A frosted band in from the rim, then the rim itself.
  love.graphics.setLineWidth(7)
  setColor(WHITE, 0.12 * fade)
  love.graphics.circle("line", x, y, r * 0.93, 48)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.setLineWidth(2)
  setColor(WHITE, 0.7 * fade)
  love.graphics.polygon("line", f.rim)
  love.graphics.setLineWidth(1.5)
  setColor(WHITE, 0.4 * fade)
  for _, line in ipairs(f.cracks) do
    love.graphics.line(line)
  end
  -- Crystals: up with the landing, a little apart and fading when it ends.
  local spread = (1 - fade) * 10
  for _, cr in ipairs(f.crystals) do
    local grow = math.max(0, math.min(1, (since - cr.delay) / POP))
    grow = 1 + 2.2 * (grow - 1) ^ 3 + 1.2 * (grow - 1) ^ 2 -- overshoots a touch, then settles
    local ox, oy = math.cos(cr.angle) * spread, math.sin(cr.angle) * spread
    crystal(ox, oy, cr, since > cr.delay and grow or 0, fade, e.t)
  end
  -- Snowflakes drifting and turning over it.
  love.graphics.setLineWidth(1)
  for _, s in ipairs(f.flakes) do
    local a = s.a + since * 0.05 * s.spin
    local fx = math.cos(a) * s.d + math.sin(since * 0.7 + s.phase) * 4
    local fy = math.sin(a) * s.d + ((since * s.drift + s.phase * 20) % 40) - 20
    setColor(WHITE, 0.55 * fade)
    flake(fx, fy, s.size, since * s.spin + s.phase)
  end
  love.graphics.pop()
  -- How long the hold has left, run down round the rim.
  if since < hold then
    local left = 1 - since / hold
    love.graphics.setLineWidth(3)
    setColor(WHITE, 0.55)
    love.graphics.arc("line", "open", x, y, r + 7, -math.pi / 2, -math.pi / 2 + TAU * left, 48)
  end
end

--- The cast: the warning first, then a flash and a shockwave as it lands
--- and the frost that stays until the hold is over.
function Freeze.drawEffect(e)
  local A = e.ability or Freeze
  local f = e.frost or build(e)
  local r = A.radius
  local windup = A.windup or 0
  if e.t < windup then
    drawWarning(e, f, r, e.t / windup)
    love.graphics.setLineWidth(1)
    return
  end
  local since = e.t - windup
  local hold = e.seconds - windup
  local fade = math.max(0, math.min(1, (e.seconds + A.afterglow - e.t) / A.afterglow))
  drawFrost(e, f, r, since, hold, fade)
  if since < BURST then
    local u = since / BURST
    setColor(WHITE, 0.6 * (1 - u) ^ 2)
    love.graphics.circle("fill", e.x, e.y, r * (0.9 + 0.1 * u), 48)
    love.graphics.setLineWidth(1 + 5 * (1 - u))
    setColor(WHITE, 1 - u)
    love.graphics.circle("line", e.x, e.y, r * (0.95 + 0.45 * u), 48)
  end
  love.graphics.setLineWidth(1)
end

--- The moment it lands, every client hears it.
function Freeze.updateEffect(e)
  local A = e.ability or Freeze
  if not e.landed and e.t >= (A.windup or 0) then
    e.landed = true
    Sounds.play("freeze", e.x, e.y)
  end
end

--- Whoever is held, cased in ice: a six-sided block with a lit facet, a
--- glint running along its top edges, and cracks in it as the hold runs
--- out (`left` seconds, if known).
function Freeze.drawHeld(x, y, radius, time, left)
  local c = Freeze.color
  local pulse = 0.5 + 0.5 * math.sin(time * 4)
  local pts = {}
  for i = 0, 5 do
    local a = i / 6 * TAU + 0.26
    pts[#pts + 1] = x + math.cos(a) * radius
    pts[#pts + 1] = y + math.sin(a) * radius
  end
  setColor(c, 0.4)
  love.graphics.polygon("fill", pts)
  -- The lit facet: the top-left of the block, paler.
  setColor(WHITE, 0.22)
  love.graphics.polygon("fill", x, y, pts[7], pts[8], pts[9], pts[10], pts[11], pts[12])
  setColor(DEEP, 0.25)
  love.graphics.polygon("fill", x, y, pts[1], pts[2], pts[3], pts[4], pts[5], pts[6])
  love.graphics.setLineWidth(1)
  setColor(WHITE, 0.35)
  for i = 1, 11, 4 do
    love.graphics.line(x, y, pts[i], pts[i + 1])
  end
  love.graphics.setLineWidth(2)
  setColor(WHITE, 0.55 + 0.35 * pulse)
  love.graphics.polygon("line", pts)
  -- A glint sliding along the upper edges now and then.
  local g = (time * 0.6) % 1.6
  if g < 1 then
    local i = g < 0.5 and 7 or 9
    local k = (g % 0.5) * 2
    local ax, ay, bx, by = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
    local gx, gy = ax + (bx - ax) * k, ay + (by - ay) * k
    love.graphics.setLineWidth(3)
    setColor(WHITE, 0.9 * math.sin(k * math.pi))
    love.graphics.line(gx - (bx - ax) * 0.12, gy - (by - ay) * 0.12, gx + (bx - ax) * 0.12, gy + (by - ay) * 0.12)
  end
  -- About to break: cracks run out across it.
  if left and left < 0.9 then
    local k = 1 - left / 0.9
    love.graphics.setLineWidth(1.5)
    setColor(WHITE, 0.5 + 0.5 * k)
    for i = 1, 11, 4 do
      local mx, my = x + (pts[i] - x) * 0.25, y + (pts[i + 1] - y) * 0.25
      local ex, ey = x + (pts[i + 2] - x) * k, y + (pts[i + 3] - y) * k
      love.graphics.line(x, y, mx + (my - y) * 0.3, my - (mx - x) * 0.3, ex, ey)
    end
  end
  love.graphics.setLineWidth(1)
end

return Freeze
