-- The hangouts' guards on the host. init.lua drives them from serverStep,
-- owns the wire and decides when a hangout is threatened; this is what each
-- guard does about it.
--
-- A guard stands at his post on the sidewalk in front of his hangout. When
-- his crew has a threat (somebody who hurt their boss nearby, one of the
-- boss's buildings, or one of them), he goes after them: a straight run
-- when he can see them, round the blocks along a walking grid (d-day's
-- nav.lua) when he can't. In range with a clear line he stops and fires
-- bursts from his crew's gun, holding fire while his boss or another guard
-- is in the way. When the threat is over (down, gone, or the crew has given
-- up on them) he walks back to his post.
--
-- Their rounds belong to nobody (weapons' ownerless `serverFireFrom`), as
-- the police officers' do: no kill is anybody's, and their boss isn't made
-- a criminal for what they do. Guards can be shot, frozen, farted at and
-- hit by cars, harder the faster they go.

local Features = require("src.features")
local Car = require("src.car")
local Vision = require("src.features.police.vision")
local hasNav, Nav = pcall(require, "src.features.d-day.nav")

local Guards = {}
Guards.__index = Guards

-- Tuning --------------------------------------------------------------------

Guards.RADIUS = 9 -- px; a person's size (drawn as one: src/body.lua)
Guards.SHOT_DAMAGE = 20 -- what a round takes off when it doesn't say (a blast)
Guards.RUN_SPEED = 150 -- px/s going after somebody: past a walk, short of a sprint
Guards.WALK_SPEED = 70 -- px/s back to his post
Guards.KEEP = 0.6 -- closes in to this share of his gun's reach, then stands and shoots
Guards.SPREAD = 0.08 -- radians of aim error, on top of the gun's own
Guards.MUZZLE = 16 -- px from the body a round leaves
Guards.REACT = 0.5 -- seconds from getting a clear line to the first round
Guards.CLEAR = 16 -- px either side of his line of fire his boss or a mate must be to let him shoot
Guards.FAN = 48 -- px from the target each guard heads for, spread along an arc on their side
Guards.APART = 24 -- px guards keep between each other, so a crew doesn't move as one lump
Guards.HOME_SECONDS = 45 -- this long on the way back and he is just at his post
Guards.REPATH = 0.8 -- seconds between fresh paths while walking round things
Guards.CAR_DAMAGE = 0.3 -- health a car takes off him per px/s it hits him at...
Guards.CAR_MIN_SPEED = 60 -- ...when it is going at least this fast (slower only shoves him)
Guards.CAR_EVERY = 0.6 -- seconds before the same guard can be hit again

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function blockedAt(x, y, r)
  r = r or Guards.RADIUS
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along, and a note of
--- whether it got anywhere.
local function walk(g, angle, speed, dt)
  local px, py = g.x, g.y
  local nx = g.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, g.y) then
    g.x = nx
  end
  local ny = g.y + math.sin(angle) * speed * dt
  if not blockedAt(g.x, ny) then
    g.y = ny
  end
  g.moving = true
  if dist2(g.x, g.y, px, py) < (speed * dt * 0.4) ^ 2 then
    g.stuck = g.stuck + dt
  else
    g.stuck = 0
  end
end

--- Is (px, py) within CLEAR of the segment from (x0, y0) to (x1, y1)?
local function inLine(x0, y0, x1, y1, px, py)
  local dx, dy = x1 - x0, y1 - y0
  local len2 = dx * dx + dy * dy
  if len2 == 0 then
    return false
  end
  local t = ((px - x0) * dx + (py - y0) * dy) / len2
  if t < 0 or t > 1 then
    return false
  end
  return dist2(px, py, x0 + dx * t, y0 + dy * t) < Guards.CLEAR * Guards.CLEAR
end

-- The guards ----------------------------------------------------------------

function Guards.new()
  return setmetatable({ time = 0, list = {}, nextId = 1, downs = {}, gridKey = nil }, Guards)
end

--- A new guard of `crew`'s level for `hangout` (init.lua's record), coming
--- out of its door at (x, y) and going to `post` ({ x, y, angle }).
function Guards:spawn(hangout, slot, crew, x, y, post)
  local g = {
    id = self.nextId, hangout = hangout, slot = slot, level = crew.level, crew = crew,
    x = x, y = y, facing = post.angle, post = post, hp = crew.health, mode = "home",
    frozen = 0, stuck = 0, sidestep = 0, side = 1, pathIn = 0, hitFor = 0, aimIn = Guards.REACT,
    burstLeft = 0, fireIn = 0, homeLeft = Guards.HOME_SECONDS,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = g
  return g
end

--- Take guard `g` out of the world without a death (his hangout is gone).
function Guards:remove(g)
  for i, other in ipairs(self.list) do
    if other == g then
      table.remove(self.list, i)
      return
    end
  end
end

--- The walking grid over `map`, built the first time somebody needs one
--- and again when the city or the buildings on it have changed (`key`).
function Guards:nav(map, key)
  if not (hasNav and map) then
    return nil
  end
  if not self.grid or self.gridKey ~= key then
    self.grid = Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
    self.gridKey = key
  end
  return self.grid
end

--- The first guard within `radius` of (x, y), or nil.
function Guards:at(x, y, radius)
  local r2 = (radius + Guards.RADIUS) ^ 2
  for _, g in ipairs(self.list) do
    if dist2(g.x, g.y, x, y) < r2 then
      return g
    end
  end
  return nil
end

--- Take `amount` off `g`; down if that finishes him. Returns true when he fell.
function Guards:hurt(g, amount, by, angle, cause)
  g.hp = g.hp - amount
  if g.hp > 0 then
    return false
  end
  self:remove(g)
  self.downs[#self.downs + 1] = { guard = g, x = g.x, y = g.y, angle = angle or 0, by = by, cause = cause }
  return true
end

--- Everything inside (x, y, radius) stands still for `seconds`.
function Guards:freeze(x, y, radius, seconds)
  for _, g in ipairs(self.list) do
    if dist2(g.x, g.y, x, y) <= (radius + Guards.RADIUS) ^ 2 then
      g.frozen = math.max(g.frozen, seconds)
    end
  end
end

--- Something stinks at (x, y): every guard within `radius` runs from it for
--- `seconds` (renewed while the cloud hangs).
function Guards:scare(x, y, radius, seconds)
  for _, g in ipairs(self.list) do
    if dist2(g.x, g.y, x, y) <= (radius + Guards.RADIUS) ^ 2 then
      g.panic = { x = x, y = y, left = seconds }
    end
  end
end

--- Towards (tx, ty) at `speed`: straight when the way is open, else along
--- a path round whatever is in it.
function Guards:towards(g, tx, ty, speed, dt)
  local gx, gy = tx, ty
  local nav = self.grid
  if nav and not nav:clear(g.x, g.y, tx, ty) then
    g.pathIn = g.pathIn - dt
    if not g.path or g.pathIn <= 0 or g.stuck > 0.6 then
      g.path, g.step, g.pathIn = nav:path(g.x, g.y, tx, ty), 1, Guards.REPATH
    end
    local path = g.path
    while path and path[g.step] and dist2(path[g.step].x, path[g.step].y, g.x, g.y) < 14 * 14 do
      g.step = g.step + 1
    end
    local corner = path and path[g.step]
    if corner then
      gx, gy = corner.x, corner.y
    end
  else
    g.path = nil
  end
  g.facing = math.atan2(gy - g.y, gx - g.x)
  if g.sidestep > 0 then
    g.sidestep = g.sidestep - dt
    walk(g, g.facing + g.side * math.pi / 2, speed, dt)
  else
    walk(g, g.facing, speed, dt)
    if g.stuck > 0.8 then
      g.stuck, g.sidestep, g.side = 0, 0.5, -g.side
    end
  end
end

--- Would a round from `g` along to (tx, ty) pass his boss or another guard?
function Guards:friendlyInLine(server, g, tx, ty)
  local boss = server.players[g.hangout.owner]
  if boss and Features.present(boss) then
    local bx, by = Features.bodyPose(server, boss)
    if bx and inLine(g.x, g.y, tx, ty, bx, by) then
      return true
    end
  end
  for _, other in ipairs(self.list) do
    if other ~= g and inLine(g.x, g.y, tx, ty, other.x, other.y) then
      return true
    end
  end
  return false
end

--- One round at (x, y), `dist` away, leading `car` (the target's, when they
--- drive) by its velocity over the round's flight the way the officers do.
--- It says it is the gang's, so it hits police officers too.
local function fire(server, g, x, y, car, dist)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local gun = g.crew.arms
  if car then
    local flight = dist / (gun.speed or weapons.PROJECTILE_SPEED or 900)
    x = x + math.cos(car.angle) * (car.speed or 0) * flight
    y = y + math.sin(car.angle) * (car.speed or 0) * flight
  end
  local aim = math.atan2(y - g.y, x - g.x) + (random() - 0.5) * 2 * Guards.SPREAD
  g.facing = aim
  local mx, my = math.cos(aim), math.sin(aim)
  weapons:serverFireFrom(server, 0, g.x + mx * Guards.MUZZLE, g.y + my * Guards.MUZZLE, aim, gun, "gang")
end

--- After the crew's threat, `target` ({ x, y, car }: a player, or a police
--- officer on foot): close in, and in range with a clear line, shoot.
function Guards:fight(server, g, target, dt)
  local x, y = target.x, target.y
  g.mode = "fight"
  local crew = g.crew
  local dist = math.sqrt(dist2(g.x, g.y, x, y))
  local seen = dist <= crew.reach and Vision.clear(g.x, g.y, x, y)
  if seen then
    g.facing = math.atan2(y - g.y, x - g.x)
    if dist > crew.reach * Guards.KEEP then
      walk(g, g.facing, Guards.RUN_SPEED * 0.6, dt) -- edging closer, still shooting
    end
    g.aimIn = g.aimIn - dt
  else
    g.aimIn = Guards.REACT
    g.burstLeft = 0
    -- Each to his own spot on an arc on their side of the target, never
    -- round the far side of it where a mate's misses would land.
    local side = math.atan2(g.y - y, g.x - x) + (g.slot - 2.5) * 0.45
    self:towards(g, x + math.cos(side) * Guards.FAN, y + math.sin(side) * Guards.FAN, Guards.RUN_SPEED, dt)
    return
  end
  g.fireIn = g.fireIn - dt
  if g.aimIn > 0 or g.fireIn > 0 then
    return
  end
  if g.burstLeft <= 0 then
    g.burstLeft = crew.burst
  end
  if self:friendlyInLine(server, g, x, y) then
    g.fireIn = 0.2 -- wait for a clear shot
    g.sidestep, g.side = 0.3, random() < 0.5 and -1 or 1
    return
  end
  fire(server, g, x, y, target.car, dist)
  g.burstLeft = g.burstLeft - 1
  if g.burstLeft > 0 then
    g.fireIn = crew.arms.cooldown
  else
    g.fireIn = math.max(crew.pause, crew.arms.cooldown) * (0.85 + random() * 0.3)
  end
end

--- No threat: back to his post, and stand there facing the street.
function Guards:homeward(g, dt)
  local p = g.post
  if g.mode ~= "home" and g.mode ~= "post" then
    g.mode, g.homeLeft, g.path = "home", Guards.HOME_SECONDS, nil
  end
  g.burstLeft, g.aimIn = 0, Guards.REACT
  if g.mode == "post" then
    if dist2(g.x, g.y, p.x, p.y) > 10 * 10 then
      g.mode, g.homeLeft = "home", Guards.HOME_SECONDS -- shoved off it
    end
    return
  end
  g.homeLeft = g.homeLeft - dt
  if g.homeLeft <= 0 or dist2(g.x, g.y, p.x, p.y) < 6 * 6 then
    g.x, g.y, g.facing, g.mode, g.path = p.x, p.y, p.angle, "post", nil
    return
  end
  self:towards(g, p.x, p.y, Guards.WALK_SPEED, dt)
end

--- Guards on the move step out of each other's way.
function Guards:spread(g)
  for _, other in ipairs(self.list) do
    if other ~= g then
      local d2 = dist2(g.x, g.y, other.x, other.y)
      if d2 < Guards.APART * Guards.APART then
        local d = math.sqrt(d2)
        local a = d > 0.01 and math.atan2(g.y - other.y, g.x - other.x) or g.slot
        local push = (Guards.APART - d) / 2
        local nx, ny = g.x + math.cos(a) * push, g.y + math.sin(a) * push
        if not blockedAt(nx, ny) then
          g.x, g.y = nx, ny
        end
      end
    end
  end
end

--- A car touching `g`: hurt by its speed and shoved out of its way. Returns
--- the driver who hit him hard enough to hurt, if any.
function Guards:trampled(server, g, dt)
  g.hitFor = math.max(0, g.hitFor - dt)
  for _, car in pairs(server.vehicles) do
    if
      not (car.hidden or car.stowed)
      and dist2(car.x, car.y, g.x, g.y) < (Car.WIDTH + Guards.RADIUS) ^ 2
      and Car.hitTest(car, g.x, g.y, Guards.RADIUS)
    then
      local speed = math.abs(car.speed or 0)
      if speed >= Guards.CAR_MIN_SPEED and g.hitFor <= 0 then
        g.hitFor = Guards.CAR_EVERY
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        if self:hurt(g, speed * Guards.CAR_DAMAGE, car.driver, travel, "impact") then
          return car.driver
        end
        g.rammedBy = car.driver
      end
      local away = math.atan2(g.y - car.y, g.x - car.x)
      local push = (Guards.RUN_SPEED + speed) * dt * 2
      if not blockedAt(g.x + math.cos(away) * push, g.y + math.sin(away) * push) then
        g.x, g.y = g.x + math.cos(away) * push, g.y + math.sin(away) * push
      end
    end
  end
  return nil
end

--- Who went down since the last call, for init.lua to tell everyone; the
--- list starts again empty.
function Guards:drain()
  local downs = self.downs
  self.downs = {}
  return downs
end

--- One host tick. `threatOf(hangout)` gives where the one the guard's crew
--- is after is ({ x, y, car }, nil for nobody); `rammed(guard, driverId)` hears about a driver who
--- hit one hard.
function Guards:step(server, dt, threatOf, rammed)
  self.time = self.time + dt
  for i = #self.list, 1, -1 do
    local g = self.list[i]
    g.moving = false
    if g.frozen > 0 then
      g.frozen = g.frozen - dt
    elseif g.panic then
      g.panic.left = g.panic.left - dt
      g.facing = math.atan2(g.y - g.panic.y, g.x - g.panic.x)
      walk(g, g.facing, Guards.RUN_SPEED, dt)
      if g.panic.left <= 0 then
        g.panic = nil
      end
    else
      local target = threatOf(g.hangout)
      if target then
        self:fight(server, g, target, dt)
      else
        self:homeward(g, dt)
      end
    end
    if self.list[i] == g then
      if g.mode ~= "post" then
        self:spread(g)
      end
      g.rammedBy = nil
      local killer = self:trampled(server, g, dt)
      local driver = killer or g.rammedBy
      if driver then
        rammed(g, driver)
      end
    end
  end
end

return Guards
