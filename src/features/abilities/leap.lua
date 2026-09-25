-- Leap: jump to a spot within reach and slam down on it. Press the key and
-- the landing ring follows the cursor, kept within `range` of you, so the
-- leap can be a hop or a bound to the edge; the fire button (left click)
-- leaps there, the key again or right-click thinks better of it
-- (`aim = "point"`). You sail over whatever is in the way (walls, cars, the crowd)
-- and land where you aimed, or a little short of it if that is inside a
-- wall. Only on foot (`onFoot = true`): behind the wheel the key does
-- nothing.
--
-- The landing hurts everything around it: other players and cars nobody
-- is driving take `damage` at the centre down to half at the edge of
-- `radius` (weapons' serverDamage, so it is your kill), and a few soft
-- targets (pedestrians, officers, Karen's simps) go down through the
-- `serverShotAt` convention. The caster is never hurt by their own slam.
--
-- The host flies the leaper: from the cast on it puts them on the line to
-- the landing spot every tick, after everything else has moved them (the
-- abilities feature runs last), and answers `serverHeld` for them so they
-- don't walk, shoot or climb out mid-air. Nothing can hold them while
-- they are up (a freeze cast on them misses). Every client flies the same
-- arc from ABL_FIRED (`seconds` is the flight time) so it looks smooth,
-- the local player's own figure and camera included, and answers `held`
-- for the leaper meanwhile. A leap past `range` (the reachforthestars
-- cheat lifts it) keeps the same speed and flies longer instead.
--
-- `Leap.variant(tuning)` is another leap on the same machinery with its
-- own numbers (bigleap.lua, the one Bigfoot drops): everything below reads
-- the tuning of the leap that was cast.

local Features = require("src.features")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")

local Leap = {
  key = "leap", -- on the wire and in a bag ("ability-leap")
  title = "leap",
  sound = "leap",
  color = { 1.0, 0.45, 0.3 }, -- a hot orange-red
  onFoot = true, -- no leaping out of a driver's seat
  aim = "point", -- a press shows the landing, a click leaps
}

-- Tuning ------------------------------------------------------------------
Leap.radius = 90 -- px; the area the landing hurts
Leap.range = 320 -- px; the furthest you can leap
Leap.seconds = 0.5 -- how long you are in the air, up to a leap of `range`
Leap.cooldown = 10 -- seconds before the next one
Leap.afterglow = 0.7 -- seconds the landing's dust and cracks linger
Leap.damage = 45 -- to someone right where you land; half that at the edge
Leap.soft = 3 -- soft targets (pedestrians, officers) the landing can drop
Leap.lift = 22 -- px the shadow drifts from the leaper at the top of the arc

-- A leaper found this far from where the leap last put them was moved by
-- something else (a respawn, a new map): the leap is over.
local LOST = 64

local leaps = {} -- player id -> { ability, sx, sy, x, y, angle, startT, flight, lastX, lastY }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- Is a circle of radius `r` at (x, y) in a wall (the `blocksPoint`
--- convention)? Tested at the centre and its four extremes.
local function blocked(x, y, r)
  return Features.any("blocksPoint", x, y)
    or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y)
    or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

--- How high up the arc is, 0..1, `k` of the way through the flight.
local function height(k)
  return 4 * k * (1 - k)
end

-- Server --------------------------------------------------------------------

function Leap.serverReset()
  leaps = {}
end

function Leap.serverForget(player)
  leaps[player.id] = nil
end

--- Is player `id` in the air on the host?
function Leap.serverLeaping(id)
  return leaps[id] ~= nil
end

--- Up they go on leap `A`, towards (x, y): pulled back towards the caster
--- until the landing is clear of walls. Nobody is held; the landing spot
--- and the way the leap goes out with ABL_FIRED, and how long it flies if
--- that is longer than usual.
local function cast(A, server, caster, x, y, abilities)
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  local d = math.sqrt(dist2(x, y, ox, oy))
  while d > 0 and blocked(x, y, Body.RADIUS) do
    d = math.max(0, d - 8)
    x, y = ox + math.cos(angle) * d, oy + math.sin(angle) * d
  end
  local flight = math.max(A.seconds, d / A.range * A.seconds) -- no faster than a full leap
  leaps[caster.id] = {
    ability = A,
    sx = ox, sy = oy, x = x, y = y, angle = angle, startT = abilities.sv.time, flight = flight,
    lastX = ox, lastY = oy,
  }
  return {}, angle, x, y, flight
end

--- The landing at (x, y): everyone and every parked car around it is hurt,
--- more towards the middle, and a few soft targets go down.
local function slam(A, server, caster, x, y)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverDamage) then
    return
  end
  local R = A.radius
  local function amount(d)
    return math.floor(A.damage * (1 - 0.5 * math.min(1, d / R)) + 0.5)
  end
  -- Work out who is caught first, then hurt them: a wreck moves its driver.
  local caught = {}
  for _, p in pairs(server.players) do
    if p ~= caster and Features.present(p) then
      local px, py, onFoot = Features.bodyPose(server, p)
      local reach = onFoot and Body.RADIUS or Car.WIDTH / 2
      local d = math.max(0, math.sqrt(dist2(px, py, x, y)) - reach)
      if d <= R then
        caught[#caught + 1] = { player = p, amount = amount(d), angle = math.atan2(py - y, px - x) }
      end
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.driver or car.hidden or car.stowed) then
      local d = math.max(0, math.sqrt(dist2(car.x, car.y, x, y)) - Car.WIDTH / 2)
      if d <= R then
        caught[#caught + 1] = { car = car, amount = amount(d), angle = math.atan2(car.y - y, car.x - x) }
      end
    end
  end
  for _, c in ipairs(caught) do
    if c.player then
      weapons:serverDamage(server, c.player, caster, c.amount, c.angle)
    elseif weapons.damageCar then
      weapons:damageCar(server, c.car, caster.id, c.amount, 0, c.angle)
    end
  end
  if A.walls then
    -- A leap heavy enough cracks buildings too, the way a rocket does.
    Features.call("serverBlast", server, x, y, R, A.walls, caster.id)
  end
  for _, f in ipairs(Features.list) do
    if f.serverShotAt then
      for _ = 1, A.soft do
        if not f:serverShotAt(server, x, y, R * 0.75, caster.id, math.random() * 2 * math.pi) then
          break
        end
      end
    end
  end
end

--- Fly every leaper on leap `A` along their line; whoever has arrived lands.
local function step(A, server, abilities)
  local now = abilities.sv.time
  for id, l in pairs(leaps) do
    local player = server.players[id]
    local body = player and player.body
    if l.ability ~= A then -- luacheck: ignore 542
      -- Another leap's: it flies them itself.
    elseif not (body and Features.present(player)) or player.vehicle
      or dist2(body.x, body.y, l.lastX, l.lastY) > LOST * LOST then
      leaps[id] = nil -- dead, in a car or moved away: no landing
    else
      local k = math.min(1, (now - l.startT) / l.flight)
      local x, y = l.sx + (l.x - l.sx) * k, l.sy + (l.y - l.sy) * k
      body.x, body.y, body.facing = x, y, l.angle
      l.lastX, l.lastY = x, y
      if k >= 1 then
        leaps[id] = nil
        slam(A, server, player, x, y)
      end
    end
  end
end

function Leap.serverCast(server, caster, x, y, abilities)
  return cast(Leap, server, caster, x, y, abilities)
end

function Leap.serverStep(server, _dt, abilities)
  step(Leap, server, abilities)
end

--- For tests.
function Leap.serverLeaps()
  return leaps
end

-- Client --------------------------------------------------------------------

--- Is effect `e` a leaper still in the air?
function Leap.airborne(e)
  return e.t < e.seconds
end

--- ABL_FIRED: the leap starts from where the leaper is drawn right now.
function Leap.onFired(e, client)
  local x, y = client:pose(e.by)
  e.sx, e.sy = x or e.x, y or e.y
end

--- Where the leaper is `k` of the way through the flight.
local function along(e, k)
  return e.sx + (e.x - e.sx) * k, e.sy + (e.y - e.sy) * k
end

--- Every frame: put the leaper on the arc (the camera too, if it's me),
--- unless the host has them somewhere else entirely. The landing thuds,
--- and a leap with a `shake` rocks the view of anyone near it for that long.
function Leap.updateEffect(e, client, camera)
  local A = e.ability
  if e.t >= e.seconds then
    if not e.landed then
      e.landed = true
      Sounds.play("leapland", e.x, e.y, A.pitch)
    end
    local left = (A.shake or 0) - (e.t - e.seconds)
    local mx, my = client:myPose()
    if left > 0 and camera and mx and dist2(mx, my, e.x, e.y) < (A.radius * 3) ^ 2 then
      local a = left / A.shake * 10
      camera.x = camera.x + (love.math.random() - 0.5) * a
      camera.y = camera.y + (love.math.random() - 0.5) * a
    end
    return
  end
  local body = client.bodies[e.by]
  if not body then
    return
  end
  local x, y = along(e, e.t / e.seconds)
  if dist2(body.x, body.y, x, y) > (LOST * 2) ^ 2 then
    return -- the host has them elsewhere (dead, respawned): stop drawing the leap
  end
  if e.by == client.myId and camera then
    camera.x, camera.y = camera.x + x - body.dx, camera.y + y - body.dy
  end
  body.dx, body.dy = x, y
end

--- Under the leaper: a shadow on the ground that shrinks and drifts away
--- as they rise, and closes back in as they come down.
function Leap.drawBelow(e)
  if e.t >= e.seconds then
    return
  end
  local k = e.t / e.seconds
  local h = height(k)
  local x, y = along(e, k)
  local r = (Body.RADIUS + 2) * (1 - 0.35 * h)
  love.graphics.setColor(0, 0, 0, 0.35 - 0.15 * h)
  local lift = e.ability.lift
  love.graphics.ellipse("fill", x + lift * 0.6 * h, y + lift * h, r, r * 0.8, 24)
end

local CRACKS = 7

--- In the air: a streak behind the leaper and the landing ring closing in
--- on the spot. Down: a shockwave out to the edge, cracks and settling dust.
function Leap.drawEffect(e)
  local c = e.ability.color
  local r = e.ability.radius
  if e.t < e.seconds then
    local k = e.t / e.seconds
    local x, y = along(e, k)
    local tx, ty = along(e, math.max(0, k - 0.3))
    love.graphics.setLineWidth(4)
    love.graphics.setColor(c[1], c[2], c[3], 0.35)
    love.graphics.line(tx, ty, x, y)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.2 * k)
    love.graphics.circle("fill", e.x, e.y, r * (1 - 0.6 * k), 48)
    love.graphics.setColor(c[1], c[2], c[3], 0.7)
    love.graphics.circle("line", e.x, e.y, r, 48)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 1, 1)
    return
  end
  local t = e.t - e.seconds
  local fade = math.max(0, 1 - t / e.ability.afterglow)
  -- The shockwave: out past the edge in the first moment.
  local k = math.min(1, t / 0.25)
  love.graphics.setLineWidth(4 * (1 - k) + 1)
  love.graphics.setColor(1, 0.85, 0.6, 1 - k)
  love.graphics.circle("line", e.x, e.y, r * (0.2 + 0.9 * k), 48)
  -- Cracks: fixed per landing, so they don't flicker.
  local seed = math.floor(e.x * 3 + e.y * 7)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(0.25, 0.18, 0.12, 0.7 * fade)
  for i = 1, CRACKS do
    local a = (i + seed % CRACKS) * (2 * math.pi / CRACKS) + (seed % 13) * 0.1
    local len = r * (0.3 + ((seed * i) % 4) * 0.1)
    local bend = a + 0.35 * (((seed + i) % 3) - 1)
    local mx, my = e.x + math.cos(a) * len * 0.5, e.y + math.sin(a) * len * 0.5
    love.graphics.line(e.x, e.y, mx, my, mx + math.cos(bend) * len * 0.5, my + math.sin(bend) * len * 0.5)
  end
  -- Dust: a soft ring billowing out and thinning.
  love.graphics.setColor(0.75, 0.68, 0.58, 0.3 * fade)
  love.graphics.circle("fill", e.x, e.y, r * (0.5 + 0.5 * math.min(1, t / 0.4)), 48)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- Another leap with its own tuning over this one's: a table with a new
--- `key` and whatever numbers, title and colour differ. It shares the
--- flying, the landing and the drawing, and the host's list of who is in
--- the air (so abilities holds its leapers too).
function Leap.variant(tuning)
  local A = {}
  for k, v in pairs(Leap) do
    A[k] = v
  end
  for k, v in pairs(tuning) do
    A[k] = v
  end
  A.variant = nil
  A.serverCast = function(server, caster, x, y, abilities)
    return cast(A, server, caster, x, y, abilities)
  end
  A.serverStep = function(server, _dt, abilities)
    step(A, server, abilities)
  end
  return A
end

return Leap
