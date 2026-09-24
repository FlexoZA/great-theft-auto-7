-- The horde on the host: the simps an open-borders cast lets in and the
-- fires they light. init.lua drives it from serverStep and owns the wire.
--
-- A simp runs about near whoever let it in (a new spot every few seconds,
-- a little way off them), dropping a fire at its feet every couple of
-- seconds. Anyone who comes close gets chased and punched, the caster
-- included; after landing a punch a simp runs off for a few seconds before
-- it picks on anyone again. After its time is up it is gone. Two pistol rounds put one
-- down; a car at speed flattens one.
--
-- A fire burns where it was lit for its time and hurts everything that
-- touches it, a little every half second: players on foot and in cars,
-- parked cars, and every soft target (the crowd, officers, Karen and her
-- simps) through the `serverShotAt` convention. Not the simps: they carry
-- the torches.

local Features = require("src.features")
local Car = require("src.car")

local Horde = {}
Horde.__index = Horde

-- Tuning --------------------------------------------------------------------

Horde.SIMPS = 25 -- per cast
Horde.SPAWN_MIN = 50 -- px from the caster they pour out...
Horde.SPAWN_MAX = 120 -- ...out to here
Horde.RADIUS = 6 -- px; a pedestrian's size
Horde.HEALTH = 40 -- two pistol rounds
Horde.SHOT_DAMAGE = 20 -- what one round takes off one
Horde.RUN_SPEED = 115 -- px/s, give or take a fifth per simp
Horde.ROAM_MIN = 50 -- px from the caster a simp runs to...
Horde.ROAM_MAX = 260 -- ...out to here
Horde.ROAM_EVERY = 3 -- seconds at most before it picks somewhere new
Horde.SIGHT = 90 -- px; anyone this close gets chased
Horde.REACH = 14 -- px past its body a punch lands
Horde.PUNCH_DAMAGE = 5
Horde.PUNCH_INTERVAL = 1.1 -- seconds between punches
Horde.CALM_MIN = 2 -- seconds a simp runs about after a punch...
Horde.CALM_MAX = 4 -- ...up to here, before it picks on anyone again
Horde.SPLAT_SPEED = 90 -- car speed (px/s) that turns one into a stain
Horde.LOOKS = 6 -- hoodie colours to pick from (the client has the palette)

Horde.FIRE_EVERY_MIN = 1.2 -- seconds between fires one simp lights...
Horde.FIRE_EVERY_MAX = 2.4 -- ...up to here
Horde.FIRE_SECONDS = 30 -- how long a fire burns
Horde.FIRE_RADIUS = 18 -- px that burn
Horde.FIRE_SPACING = 26 -- px; no fire is lit this close to another
Horde.MAX_FIRES = 220 -- in the world at once
Horde.BURN_EVERY = 0.5 -- seconds between burns
Horde.BURN_DAMAGE = 5 -- to a player or car touching a fire, per burn

local FOOT_RADIUS = 6 -- a player on foot, as weapons sees one
local random = love.math.random

-- Walking -------------------------------------------------------------------

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
local function blockedAt(x, y, r)
  r = r or Horde.RADIUS
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
local function walk(s, angle, speed, dt)
  local px, py = s.x, s.y
  local nx = s.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, s.y) then
    s.x = nx
  end
  local ny = s.y + math.sin(angle) * speed * dt
  if not blockedAt(s.x, ny) then
    s.y = ny
  end
  if (s.x - px) ^ 2 + (s.y - py) ^ 2 < (speed * dt * 0.4) ^ 2 then
    s.stuck = s.stuck + dt
  else
    s.stuck = 0
  end
end

-- The horde -----------------------------------------------------------------

function Horde.new()
  return setmetatable({
    time = 0,
    simps = {}, -- { id, by, x, y, facing, hp, untilT, ... }
    fires = {}, -- { id, by, x, y, untilT }
    nextSimp = 1,
    nextFire = 1,
    burnIn = Horde.BURN_EVERY,
    kills = {}, -- this tick's dead simps: { id, x, y, angle, by }
    lit = {}, -- this tick's new fires
  }, Horde)
end

--- Somewhere open within SPAWN_MIN..SPAWN_MAX of (x, y); (x, y) itself
--- if there is nowhere.
local function spawnSpot(x, y)
  for _ = 1, 10 do
    local a = random() * 2 * math.pi
    local d = Horde.SPAWN_MIN + random() * (Horde.SPAWN_MAX - Horde.SPAWN_MIN)
    local sx, sy = x + math.cos(a) * d, y + math.sin(a) * d
    if not blockedAt(sx, sy) then
      return sx, sy
    end
  end
  return x, y
end

--- Let `Horde.SIMPS` simps in round (x, y) for `seconds`, on `by`'s account.
function Horde:unleash(by, x, y, seconds)
  for _ = 1, Horde.SIMPS do
    local sx, sy = spawnSpot(x, y)
    local id = self.nextSimp
    self.nextSimp = id + 1
    self.simps[#self.simps + 1] = {
      id = id,
      by = by,
      x = sx,
      y = sy,
      facing = math.atan2(sy - y, sx - x),
      speed = Horde.RUN_SPEED * (0.8 + random() * 0.4),
      hp = Horde.HEALTH,
      untilT = self.time + seconds,
      anchorX = x, -- where the caster was last seen
      anchorY = y,
      fireIn = 0.3 + random() * 1.2,
      goalIn = 0, -- pick a spot at once
      punchTimer = Horde.PUNCH_INTERVAL * random(),
      swing = 0,
      stuck = 0,
      sidestep = 0,
      side = random() < 0.5 and -1 or 1,
      frozen = 0,
      calm = 0.5 + random(), -- a moment to spread out before anyone is picked on
      look = random(Horde.LOOKS),
    }
  end
end

function Horde:clear()
  self.simps, self.fires = {}, {}
end

--- The first simp within `radius` of (x, y), and its index, or nil.
function Horde:simpAt(x, y, radius)
  local r2 = (radius + Horde.RADIUS) ^ 2
  for i, s in ipairs(self.simps) do
    if (s.x - x) ^ 2 + (s.y - y) ^ 2 < r2 then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off simp `i`. Returns the kill if that finished it (it is
--- gone from the list then), else nil.
function Horde:hurt(i, amount, by, angle)
  local s = self.simps[i]
  s.hp = s.hp - amount
  if s.hp > 0 then
    return nil
  end
  table.remove(self.simps, i)
  return { id = s.id, x = s.x, y = s.y, angle = angle or 0, by = by }
end

--- Everything inside (x, y, radius) stands still for `seconds`.
function Horde:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.simps) do
    if (s.x - x) ^ 2 + (s.y - y) ^ 2 <= (radius + Horde.RADIUS) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Something stinks at (x, y): every simp within `radius` runs from it
--- for `seconds` (renewed while the cloud hangs).
function Horde:scare(x, y, radius, seconds)
  for _, s in ipairs(self.simps) do
    if (s.x - x) ^ 2 + (s.y - y) ^ 2 <= (radius + Horde.RADIUS) ^ 2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

--- Is there a fire within FIRE_SPACING of (x, y)?
function Horde:fireNear(x, y)
  local r2 = Horde.FIRE_SPACING ^ 2
  for _, f in ipairs(self.fires) do
    if (f.x - x) ^ 2 + (f.y - y) ^ 2 < r2 then
      return true
    end
  end
  return false
end

--- Light a fire at (x, y) unless one is burning right there or the world
--- is full of them. Returns it, or nil.
function Horde:light(by, x, y)
  if #self.fires >= Horde.MAX_FIRES or self:fireNear(x, y) then
    return nil
  end
  local id = self.nextFire
  self.nextFire = id + 1
  local f = { id = id, by = by, x = x, y = y, untilT = self.time + Horde.FIRE_SECONDS }
  self.fires[#self.fires + 1] = f
  self.lit[#self.lit + 1] = f
  return f
end

--- Everyone present this tick, with where their body is.
local function bodies(server)
  local list = {}
  for id, player in pairs(server.players) do
    if Features.present(player) then
      local x, y, onFoot = Features.bodyPose(server, player)
      list[#list + 1] = { id = id, player = player, car = player.vehicle, x = x, y = y, onFoot = onFoot }
    end
  end
  return list
end

--- The nearest body within SIGHT of simp `s`, and how far.
local function nearest(s, list)
  local best, bestD2
  for _, e in ipairs(list) do
    local d2 = (e.x - s.x) ^ 2 + (e.y - s.y) ^ 2
    if d2 <= Horde.SIGHT ^ 2 and (not bestD2 or d2 < bestD2) then
      best, bestD2 = e, d2
    end
  end
  return best, bestD2
end

--- Run at `target` and punch it once in reach. Wedged, sidestep.
local function hunt(server, s, dt, target, dist)
  s.facing = math.atan2(target.y - s.y, target.x - s.x)
  local reach = Horde.RADIUS + Horde.REACH + (target.onFoot and 0 or Car.HEIGHT / 2)
  if s.sidestep > 0 then
    s.sidestep = s.sidestep - dt
    walk(s, s.facing + s.side * math.pi / 2, s.speed, dt)
  elseif dist > reach then
    walk(s, s.facing, s.speed, dt)
    if s.stuck > 0.4 then
      s.stuck, s.sidestep, s.side = 0, 0.6, -s.side
    end
  end
  s.punchTimer = s.punchTimer - dt
  if dist <= reach and s.punchTimer <= 0 then
    s.punchTimer = Horde.PUNCH_INTERVAL
    s.swing = 0.3
    s.calm = Horde.CALM_MIN + random() * (Horde.CALM_MAX - Horde.CALM_MIN) -- hit and run
    s.goalIn = 0
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, target.player, nil, Horde.PUNCH_DAMAGE, s.facing)
    end
  end
end

--- Nobody close: run to a spot near the caster, a new one when it gets
--- there, gets stuck or has been at it a while.
local function roam(s, dt)
  s.goalIn = s.goalIn - dt
  local near = s.goalX and (s.goalX - s.x) ^ 2 + (s.goalY - s.y) ^ 2 < 12 * 12
  if not s.goalX or near or s.goalIn <= 0 or s.stuck > 0.5 then
    local a = random() * 2 * math.pi
    local d = Horde.ROAM_MIN + random() * (Horde.ROAM_MAX - Horde.ROAM_MIN)
    s.goalX, s.goalY = s.anchorX + math.cos(a) * d, s.anchorY + math.sin(a) * d
    s.goalIn = Horde.ROAM_EVERY * (0.5 + random() * 0.5)
    s.stuck = 0
  end
  s.facing = math.atan2(s.goalY - s.y, s.goalX - s.x)
  walk(s, s.facing, s.speed, dt)
end

--- A car touching simp `s`: flattened at speed, shoved aside below it.
--- Returns the kill (by the driver), or nil.
local function trampled(server, s, dt)
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed) and (car.x - s.x) ^ 2 + (car.y - s.y) ^ 2 < (Car.WIDTH + Horde.RADIUS) ^ 2
      and Car.hitTest(car, s.x, s.y, Horde.RADIUS) then
      local speed = math.abs(car.speed or 0)
      if speed >= Horde.SPLAT_SPEED then
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        return { id = s.id, x = s.x, y = s.y, angle = travel, by = car.driver }
      end
      local away = math.atan2(s.y - car.y, s.x - car.x)
      local push = (Horde.RUN_SPEED + speed) * dt * 2
      s.x, s.y = s.x + math.cos(away) * push, s.y + math.sin(away) * push
    end
  end
  return nil
end

--- Everything a fire touches takes a burn. Players and cars once per burn
--- however many fires they stand in; soft targets once per fire.
function Horde:burn(server, skip)
  local weapons = Features.byName.weapons
  local fires = self.fires
  if #fires == 0 then
    return
  end
  local R = Horde.FIRE_RADIUS
  local function touching(x, y, reach, car)
    for _, f in ipairs(fires) do
      if car then
        if (f.x - car.x) ^ 2 + (f.y - car.y) ^ 2 < (Car.WIDTH + R) ^ 2 and Car.hitTest(car, f.x, f.y, R) then
          return f
        end
      elseif (f.x - x) ^ 2 + (f.y - y) ^ 2 < (R + reach) ^ 2 then
        return f
      end
    end
    return nil
  end
  -- Work out who is burning first, then hurt them: a wreck moves its driver.
  local caught = {}
  for _, e in ipairs(bodies(server)) do
    local f = touching(e.x, e.y, FOOT_RADIUS, not e.onFoot and e.car or nil)
    if f then
      caught[#caught + 1] = { player = e.player, fire = f, x = e.x, y = e.y }
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.driver or car.hidden or car.stowed) then
      local f = touching(car.x, car.y, 0, car)
      if f then
        caught[#caught + 1] = { car = car, fire = f, x = car.x, y = car.y }
      end
    end
  end
  if weapons then
    for _, c in ipairs(caught) do
      local angle = math.atan2(c.y - c.fire.y, c.x - c.fire.x)
      local by = c.fire.by
      if c.player and weapons.serverDamage then
        -- Walking into your own fire is nobody's kill.
        weapons:serverDamage(server, c.player, by ~= c.player.id and server.players[by] or nil, Horde.BURN_DAMAGE,
          angle)
      elseif c.car and weapons.damageCar then
        weapons:damageCar(server, c.car, server.players[by] and by or nil, Horde.BURN_DAMAGE, 0, angle)
      end
    end
  end
  -- The crowd, officers, Karen and her simps: one burn per fire each.
  for _, f in ipairs(fires) do
    for _, feature in ipairs(Features.list) do
      if feature ~= skip and feature.serverShotAt then
        feature:serverShotAt(server, f.x, f.y, R, f.by, random() * 2 * math.pi)
      end
    end
  end
end

--- One host tick. `skip` is the open-borders feature (its own simps don't
--- burn). Returns this tick's dead simps and newly lit fires (both reused
--- lists).
function Horde:step(server, dt, skip)
  self.time = self.time + dt
  local now = self.time
  for i = #self.kills, 1, -1 do
    self.kills[i] = nil
  end
  for i = #self.lit, 1, -1 do
    self.lit[i] = nil
  end

  local list = #self.simps > 0 and bodies(server) or {}
  local i = 1
  while i <= #self.simps do
    local s = self.simps[i]
    local kill
    if now >= s.untilT then
      table.remove(self.simps, i) -- their time is up: gone
    else
      local caster = server.players[s.by]
      if caster and Features.present(caster) then
        s.anchorX, s.anchorY = Features.bodyPose(server, caster)
      end
      s.swing = math.max(0, s.swing - dt)
      if s.frozen > 0 then
        s.frozen = s.frozen - dt
      else
        s.calm = math.max(0, s.calm - dt)
        local target, d2
        if s.calm <= 0 then
          target, d2 = nearest(s, list)
        end
        if s.panic then
          -- A stink: away from it at a run, whoever is about (torches still lit).
          s.panic.left = s.panic.left - dt
          s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
          walk(s, s.facing, s.speed, dt)
          if s.panic.left <= 0 then
            s.panic = nil
          end
        elseif target then
          hunt(server, s, dt, target, math.sqrt(d2))
        else
          roam(s, dt)
        end
        s.fireIn = s.fireIn - dt
        if s.fireIn <= 0 then
          s.fireIn = Horde.FIRE_EVERY_MIN + random() * (Horde.FIRE_EVERY_MAX - Horde.FIRE_EVERY_MIN)
          self:light(s.by, s.x, s.y)
        end
      end
      kill = trampled(server, s, dt)
      if kill then
        self.kills[#self.kills + 1] = kill
        table.remove(self.simps, i)
      else
        i = i + 1
      end
    end
  end

  for k = #self.fires, 1, -1 do
    if now >= self.fires[k].untilT then
      table.remove(self.fires, k)
    end
  end
  self.burnIn = self.burnIn - dt
  if self.burnIn <= 0 then
    self.burnIn = self.burnIn + Horde.BURN_EVERY
    self:burn(server, skip)
  end
  return self.kills, self.lit
end

return Horde
