-- Jet run: thrusters on your back, the way Hyperbole's jet haulers fly.
-- Press the key and a red ring for every rocket shows along a line through
-- the cursor (`aim = "point"`, kept within `range`); the fire button goes,
-- the key again or right-click thinks better of it. Your thrusters light
-- for a moment (you stand still, and can still be shot), then you take off
-- and fly straight over the spot and on past it, over walls and everything
-- else, faster than anyone runs. Nothing touches you up there: rounds pass
-- through and no blow lands. As you pass over each ring a rocket drops out
-- of your pods onto it. At the end you come down where there is room and
-- stand a moment, shootable again, before you can move.
--
-- The rockets only hurt enemies: the crowd, every enemy (the
-- `serverShotAt` convention, as many rounds' worth as `soft`) and cars
-- nobody drives. Players, you and your friends, are never hurt by them,
-- and they leave buildings alone.
--
-- The host flies the jet the way leap.lua flies a leaper: every tick, after
-- everything else has moved them, it puts them on the line, and abilities
-- answers `serverHeld` for them (`serverAirborne`) from the charge to the
-- landing, so they don't walk, shoot or get frozen meanwhile. For the
-- flight weapons protects them (`serverProtect`, as after a respawn). The
-- ring centre goes out with ABL_FIRED as its spot and the whole run as its
-- `seconds`, so every client works out the same line, rings and landing.

local Features = require("src.features")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")

local Jet = {
  key = "jetrun", -- on the wire and in a bag ("ability-jetrun")
  title = "jet run",
  hud = "jet",
  blurb = "Fly a strafing run over walls and enemies, rockets dropping behind you. Nothing hits you up there.",
  sound = "jetrun",
  color = { 1.0, 0.55, 0.15 }, -- thruster flame
  onFoot = true, -- no flying out of a driver's seat
  aim = "point", -- a press shows the rings, a click goes
}

-- Tuning ------------------------------------------------------------------
Jet.range = 420 -- px; the furthest the rings' middle can be from you
Jet.takeOff = 0.5 -- seconds the thrusters light before you go
Jet.flySpeed = 340 -- px/s in the air
Jet.past = 300 -- px past the rings' middle you fly on
Jet.landFor = 0.4 -- seconds you stand, shootable, coming down
Jet.marks = 5 -- rockets along the run
Jet.markGap = 90 -- px between them
Jet.radius = 70 -- px; each rocket's blast
Jet.damage = 40 -- to an enemy right where it lands
Jet.soft = 3 -- soft targets each rocket can drop
Jet.fall = 0.35 -- seconds from passing over a ring to its rocket landing
Jet.cooldown = 25 -- seconds before the next
Jet.afterglow = 0.8 -- seconds the last blast and the scorch marks linger
Jet.seconds = 2 -- a full run's length, for the HUD; each cast sends its own
-- What a better tier improves, in order: an uncommon run comes back sooner,
-- a rare one hits harder, a legendary one wider too.
Jet.tierStats = { "cooldown", "damage", "radius" }

-- A jet found this far from where the run last put them was moved by
-- something else (a respawn, a new map): the run is over.
local LOST = 64
local ALTITUDE = 120 -- px up a rocket is drawn when it drops

local runs = {} -- player id -> { ability, sx, sy, ux, uy, length, flyAt, landAt, endT, lastX, lastY, up }
local rockets = {} -- { x, y, at, castT, radius, damage, soft, by }

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

--- Is a body at (x, y) in a wall (the `blocksPoint` convention)? Tested at
--- the centre and its four extremes.
local function blocked(x, y)
  local r = Body.RADIUS
  return Features.any("blocksPoint", x, y)
    or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y)
    or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

--- How far from the start the rings' middle sits for a cast `d` px away:
--- never so close that the first ring is behind you.
local function middle(A, d)
  return math.max(d, (A.marks - 1) / 2 * A.markGap + A.markGap * 0.5)
end

--- How far along the line ring `k` (0-based) sits, its middle `d` along.
local function ringAlong(A, d, k)
  return d + (k - (A.marks - 1) / 2) * A.markGap
end

--- Seconds from the cast to ring `k`'s rocket landing.
local function landsAfter(A, d, k)
  return A.takeOff + ringAlong(A, d, k) / A.flySpeed + A.fall
end

-- Server --------------------------------------------------------------------

function Jet.serverReset()
  runs, rockets = {}, {}
end

function Jet.serverForget(player)
  runs[player.id] = nil
end

--- Is player `id` on a run on the host, from the charge to the landing?
function Jet.serverAirborne(id)
  return runs[id] ~= nil
end

--- Off they go on run `A` (in the caster's tier) over (x, y): the landing
--- pulled back towards the caster until it is clear of walls, a rocket
--- set for every ring. Nobody is held; the rings' middle goes out as the
--- spot and the run's length as its seconds.
function Jet.serverCast(server, caster, x, y, abilities, A)
  A = A or Jet
  local ox, oy = Features.bodyPose(server, caster)
  local angle = math.atan2(y - oy, x - ox)
  local ux, uy = math.cos(angle), math.sin(angle)
  local d = middle(A, math.sqrt(dist2(x, y, ox, oy)))
  local length = d + A.past
  while length > 0 and blocked(ox + ux * length, oy + uy * length) do
    length = math.max(0, length - 8)
  end
  local now = abilities.sv.time
  local flight = length / A.flySpeed
  local run = {
    ability = A, sx = ox, sy = oy, ux = ux, uy = uy, length = length, lastX = ox, lastY = oy,
    flyAt = now + A.takeOff, landAt = now + A.takeOff + flight,
  }
  run.endT = run.landAt + A.landFor
  runs[caster.id] = run
  for k = 0, A.marks - 1 do
    local along = ringAlong(A, d, k)
    rockets[#rockets + 1] = {
      x = ox + ux * along, y = oy + uy * along, at = now + landsAfter(A, d, k), castT = now,
      radius = A.radius, damage = A.damage, soft = A.soft, by = caster.id,
    }
  end
  return {}, angle, ox + ux * d, oy + uy * d, run.endT - now
end

--- A rocket goes off: parked cars and soft targets round it are hurt, more
--- towards the middle; players never.
local function boom(server, r)
  local function amount(d)
    return math.floor(r.damage * (1 - (2 / 3) * math.min(1, d / r.radius)) + 0.5)
  end
  local weapons = Features.byName.weapons
  if weapons and weapons.damageCar then
    for _, car in pairs(server.vehicles) do
      if not (car.driver or car.hidden or car.stowed) then
        local d = math.max(0, math.sqrt(dist2(car.x, car.y, r.x, r.y)) - Car.WIDTH / 2)
        if d <= r.radius then
          weapons:damageCar(server, car, r.by, amount(d), 0, math.atan2(car.y - r.y, car.x - r.x), "explosive")
        end
      end
    end
  end
  for _, f in ipairs(Features.list) do
    if f.serverShotAt then
      for _ = 1, r.soft do
        local angle = math.random() * 2 * math.pi
        if not f:serverShotAt(server, r.x, r.y, r.radius * 0.75, r.by, angle, amount(0), "explosive") then
          break
        end
      end
    end
  end
end

--- Fly every jet along their line, protected from takeoff to landing, and
--- set off every rocket whose time has come.
function Jet.serverStep(server, _dt, abilities)
  local now = abilities.sv.time
  for id, run in pairs(runs) do
    local player = server.players[id]
    local body = player and player.body
    if not (body and Features.present(player)) or player.vehicle
      or dist2(body.x, body.y, run.lastX, run.lastY) > LOST * LOST then
      runs[id] = nil -- dead, in a car or moved away: the run is over
    else
      if now >= run.flyAt and not run.up then
        run.up = true
        local weapons = Features.byName.weapons
        if weapons and weapons.serverProtect then
          weapons:serverProtect(server, player, run.landAt - now)
        end
      end
      local along = math.max(0, math.min(run.length, (now - run.flyAt) * run.ability.flySpeed))
      local x, y = run.sx + run.ux * along, run.sy + run.uy * along
      body.x, body.y, body.facing = x, y, math.atan2(run.uy, run.ux)
      run.lastX, run.lastY = x, y
      if now >= run.endT then
        runs[id] = nil
      end
    end
  end
  for i = #rockets, 1, -1 do
    local r = rockets[i]
    if now >= r.at then
      table.remove(rockets, i)
      boom(server, r)
    end
  end
end

--- Every rocket still to come down, for Abilities:serverIncoming.
function Jet.serverIncoming(list, now)
  for _, r in ipairs(rockets) do
    list[#list + 1] = { x = r.x, y = r.y, radius = r.radius, age = now - r.castT, left = r.at - now }
  end
end

--- Who is on a run and the rockets still to land: for tests.
function Jet.serverRuns()
  return runs, rockets
end

-- Client --------------------------------------------------------------------

--- Is effect `e` a jet still on its run (charging, flying or landing)?
function Jet.airborne(e)
  return e.t < e.seconds
end

--- ABL_FIRED: the run starts from where the jet is drawn right now; the
--- rings and the landing follow from it, the middle and the run's length.
function Jet.onFired(e, client)
  local A = e.ability
  local x, y = client:pose(e.by)
  e.sx, e.sy = x or e.x, y or e.y
  e.ux, e.uy = math.cos(e.angle), math.sin(e.angle)
  e.length = math.max(0, (e.seconds - A.takeOff - A.landFor) * A.flySpeed)
  local d = math.sqrt(dist2(e.x, e.y, e.sx, e.sy))
  e.rings = {}
  for k = 0, A.marks - 1 do
    local along = ringAlong(A, d, k)
    e.rings[#e.rings + 1] = { x = e.sx + e.ux * along, y = e.sy + e.uy * along, at = landsAfter(A, d, k) }
  end
end

--- Where the jet is `t` seconds into the run, and how far up (0..1).
local function at(e, t)
  local A = e.ability
  local along = math.max(0, math.min(e.length, (t - A.takeOff) * A.flySpeed))
  local flight = e.length / A.flySpeed
  local into = t - A.takeOff
  local up = into <= 0 and 0 or math.min(1, into / 0.15, (flight - into) / 0.15)
  return e.sx + e.ux * along, e.sy + e.uy * along, math.max(0, up)
end

--- Every frame: put the jet on the line (the camera too, if it's me),
--- unless the host has them somewhere else entirely; each rocket booms as
--- it lands, and rocks the view of anyone near it.
function Jet.updateEffect(e, client, camera)
  local mx, my = client:myPose()
  for _, r in ipairs(e.rings) do
    if not r.boomed and e.t >= r.at then
      r.boomed = true
      Sounds.play("jetrunboom", r.x, r.y, 0.9 + math.random() * 0.2)
    end
    local left = 0.25 - (e.t - r.at)
    if r.boomed and left > 0 and camera and mx and dist2(mx, my, r.x, r.y) < (e.ability.radius * 3) ^ 2 then
      camera.x = camera.x + (love.math.random() - 0.5) * left * 24
      camera.y = camera.y + (love.math.random() - 0.5) * left * 24
    end
  end
  if e.t >= e.seconds then
    return
  end
  local body = client.bodies[e.by]
  if not body then
    return
  end
  local x, y = at(e, e.t)
  if dist2(body.x, body.y, x, y) > (LOST * 2) ^ 2 then
    return -- the host has them elsewhere (dead, respawned): stop drawing the run
  end
  if e.by == client.myId and camera then
    camera.x, camera.y = camera.x + x - body.dx, camera.y + y - body.dy
  end
  body.dx, body.dy = x, y
end

--- A red ring on the ground, filling in as its rocket comes (`k` 0..1).
local function ring(x, y, r, k, alpha)
  love.graphics.setColor(1, 0.25, 0.15, (0.1 + 0.25 * k) * alpha)
  love.graphics.circle("fill", x, y, r * k, 40)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.3, 0.2, 0.75 * alpha)
  love.graphics.circle("line", x, y, r, 40)
  love.graphics.setLineWidth(1)
end

--- Under the cars: each ring as its rocket comes, then its scorch mark;
--- and the jet's shadow drifting off as they rise.
function Jet.drawBelow(e)
  local A = e.ability
  local fade = math.max(0, math.min(1, (e.seconds + A.afterglow - e.t) / A.afterglow))
  for _, r in ipairs(e.rings) do
    if e.t < r.at then
      ring(r.x, r.y, A.radius, math.min(1, e.t / r.at), 1)
    else
      love.graphics.setColor(0.08, 0.06, 0.05, 0.45 * fade)
      love.graphics.circle("fill", r.x, r.y, A.radius * 0.45, 24)
    end
  end
  if e.t < e.seconds then
    local x, y, up = at(e, e.t)
    local r = (Body.RADIUS + 2) * (1 - 0.3 * up)
    love.graphics.setColor(0, 0, 0, 0.35 - 0.15 * up)
    love.graphics.ellipse("fill", x + 14 * up, y + 22 * up, r, r * 0.8, 24)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Above the cars: the thrusters lighting, the flame and smoke trail of
--- the run, each rocket diving in and its blast.
function Jet.drawEffect(e)
  local A = e.ability
  local c = A.color
  if e.t < e.seconds then
    local x, y, up = at(e, e.t)
    local bx, by = x - e.ux * 8, y - e.uy * 8 -- the thrusters, on the jet's back
    if e.t < A.takeOff then
      local k = e.t / A.takeOff -- lighting up
      love.graphics.setColor(c[1], c[2], c[3], 0.3 + 0.4 * k)
      love.graphics.circle("fill", bx, by, 4 + 6 * k + math.random() * 2, 16)
    elseif up > 0 then
      -- The trail: a flame at the thrusters, smoke thinning out behind.
      for i = 5, 1, -1 do
        local back = i * 12
        love.graphics.setColor(0.5, 0.48, 0.45, 0.28 * up * (1 - i / 6))
        love.graphics.circle("fill", bx - e.ux * back, by - e.uy * back, 5 + i * 1.6, 12)
      end
      love.graphics.setColor(c[1], c[2], c[3], 0.85 * up)
      love.graphics.circle("fill", bx - e.ux * 6, by - e.uy * 6, 6 + math.random() * 3, 12)
      love.graphics.setColor(1, 0.95, 0.7, 0.9 * up)
      love.graphics.circle("fill", bx - e.ux * 3, by - e.uy * 3, 3.5, 10)
    end
  end
  for _, r in ipairs(e.rings) do
    local dropT = r.at - A.fall
    if e.t >= dropT and e.t < r.at then
      -- Diving in: a rocket and its flame coming down on the ring.
      local k = (e.t - dropT) / A.fall
      local h = ALTITUDE * (1 - k)
      love.graphics.setLineWidth(3)
      love.graphics.setColor(0.85, 0.85, 0.82)
      love.graphics.line(r.x, r.y - h - 10, r.x, r.y - h)
      love.graphics.setColor(c[1], c[2], c[3], 0.9)
      love.graphics.circle("fill", r.x, r.y - h - 12, 3 + math.random() * 1.5, 8)
      love.graphics.setLineWidth(1)
    elseif e.t >= r.at and e.t < r.at + 0.45 then
      -- The blast: a flash out to the edge and a fireball cooling off.
      local k = (e.t - r.at) / 0.45
      love.graphics.setColor(1, 0.9, 0.6, 0.9 * (1 - k))
      love.graphics.circle("fill", r.x, r.y, A.radius * (0.3 + 0.5 * k), 32)
      love.graphics.setColor(c[1], c[2] * 0.7, c[3] * 0.5, 0.8 * (1 - k))
      love.graphics.circle("fill", r.x, r.y, A.radius * 0.45 * (1 - 0.5 * k), 24)
      love.graphics.setLineWidth(3 * (1 - k) + 1)
      love.graphics.setColor(1, 0.8, 0.5, 1 - k)
      love.graphics.circle("line", r.x, r.y, A.radius * (0.4 + 0.7 * k), 40)
      love.graphics.setLineWidth(1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- While the ability is selected: the line of the run from me through the
--- cursor and on past, and a ring for every rocket along it. `A` is the
--- run in the tier I carry.
function Jet.drawAim(ox, oy, x, y, time, _mode, A)
  A = A or Jet
  local angle = math.atan2(y - oy, x - ox)
  local ux, uy = math.cos(angle), math.sin(angle)
  local d = middle(A, math.sqrt(dist2(x, y, ox, oy)))
  local pulse = 0.5 + 0.5 * math.sin(time * 6)
  local c = A.color
  love.graphics.setLineWidth(2)
  love.graphics.setColor(c[1], c[2], c[3], 0.5)
  love.graphics.line(ox + ux * 14, oy + uy * 14, ox + ux * (d + A.past), oy + uy * (d + A.past))
  for k = 0, A.marks - 1 do
    local along = ringAlong(A, d, k)
    ring(ox + ux * along, oy + uy * along, A.radius, 0.2 + 0.15 * pulse, 0.7)
  end
  -- Where you come down.
  local lx, ly = ox + ux * (d + A.past), oy + uy * (d + A.past)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(c[1], c[2], c[3], 0.8)
  love.graphics.circle("line", lx, ly, Body.RADIUS + 4, 24)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Jet
