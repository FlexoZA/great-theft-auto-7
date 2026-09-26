-- Karen's simps: the hangers-on who turn up to defend her. While she stands,
-- one arrives every few seconds until five are about, each with a name
-- that starts "Simpin" (Simpin Jim, Simpin Ben...). They run at the nearest
-- player and punch, take a couple of pistol rounds, and burst like any
-- pedestrian; a car at speed flattens one. Once she is down no more come,
-- but the ones already out keep swinging until they are dealt with.
--
-- The host owns them (init.lua drives this module from Karen's step and
-- owns the wire format); clients draw what KRN_SIMPS tells them.

local Features = require("src.features")
local Car = require("src.car")

local Simps = {}
Simps.__index = Simps

-- Tuning --------------------------------------------------------------------

Simps.MAX = 5 -- at a time, for one player (karen sets `max` on a gang for the humans there)
Simps.SPAWN_EVERY = 4 -- seconds between arrivals while there is room
Simps.FIRST_AFTER = 3 -- seconds after she appears before the first one
Simps.SPAWN_MIN = 140 -- px from her they appear...
Simps.SPAWN_MAX = 260 -- ...out to here
Simps.RADIUS = 6 -- px; a pedestrian's size
Simps.HEALTH = 40 -- two pistol rounds
Simps.SHOT_DAMAGE = 20 -- what one round takes off one (matches the pistol)
Simps.WALK_SPEED = 70 -- px/s ambling about
Simps.CHASE_SPEED = 135 -- px/s once they have picked someone
Simps.SIGHT = 900 -- px; they go for anyone inside this
Simps.REACH = 14 -- px past their body a punch lands
Simps.PUNCH_DAMAGE = 8
Simps.PUNCH_INTERVAL = 1.0 -- seconds between punches
Simps.SPLAT_SPEED = 90 -- car speed (px/s) that turns one into a stain
Simps.PREFIX = "Simpin"
Simps.NAMES = {
  "Jim", "Ben", "Todd", "Gary", "Kyle", "Chad", "Dave", "Rob", "Steve", "Bruce",
  "Kev", "Dean", "Craig", "Trevor", "Neil", "Wayne", "Colin", "Barry", "Glen", "Ross",
}

local TOUCH2 = (Car.WIDTH / 2 + Simps.RADIUS + 2) ^ 2
local random = love.math.random

-- Walking -------------------------------------------------------------------

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
local function blockedAt(x, y)
  local r = Simps.RADIUS
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
--- whether it got anywhere (wedged, they sidestep).
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

-- The gang --------------------------------------------------------------------

function Simps.new()
  return setmetatable({
    list = {},
    n = 0,
    nextId = 1,
    spawnIn = Simps.FIRST_AFTER,
    kills = {}, -- reused every tick: { id, x, y, angle, by }
    bodies = {}, -- reused every tick: see collect()
  }, Simps)
end

--- A name nobody out right now is using, if there is one.
function Simps:pickName()
  for _ = 1, 12 do
    local name = Simps.PREFIX .. " " .. Simps.NAMES[random(#Simps.NAMES)]
    local taken = false
    for i = 1, self.n do
      if self.list[i].name == name then
        taken = true
        break
      end
    end
    if not taken then
      return name
    end
  end
  return Simps.PREFIX .. " " .. Simps.NAMES[random(#Simps.NAMES)]
end

function Simps:spawn(x, y)
  local id = self.nextId
  self.nextId = id + 1
  local s = {
    id = id,
    name = self:pickName(),
    x = x,
    y = y,
    facing = random() * 2 * math.pi,
    hp = Simps.HEALTH,
    target = nil,
    punchTimer = Simps.PUNCH_INTERVAL,
    swing = 0, -- seconds left of the punch animation, for clients
    stuck = 0,
    sidestep = 0,
    side = random() < 0.5 and -1 or 1,
  }
  self.n = self.n + 1
  self.list[self.n] = s
  return s
end

--- Somewhere on open ground within SPAWN_MIN..SPAWN_MAX of (x, y), or nil.
function Simps.spawnSpot(x, y)
  for _ = 1, 10 do
    local a = random() * 2 * math.pi
    local d = Simps.SPAWN_MIN + random() * (Simps.SPAWN_MAX - Simps.SPAWN_MIN)
    local sx, sy = x + math.cos(a) * d, y + math.sin(a) * d
    if not blockedAt(sx, sy) then
      return sx, sy
    end
  end
  return nil
end

function Simps:clear()
  for i = self.n, 1, -1 do
    self.list[i] = nil
  end
  self.n = 0
end

function Simps:removeAt(i)
  self.list[i] = self.list[self.n]
  self.list[self.n] = nil
  self.n = self.n - 1
end

--- The first simp within `radius` of (x, y), or nil.
function Simps:at(x, y, radius)
  local r2 = (radius + Simps.RADIUS) ^ 2
  for i = 1, self.n do
    local s = self.list[i]
    if (s.x - x) ^ 2 + (s.y - y) ^ 2 < r2 then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off a simp. Returns the kill record if that finished it
--- (the caller removes and announces it), else nil.
function Simps:hurt(s, amount, by, angle)
  s.hp = s.hp - amount
  if s.hp > 0 then
    return nil
  end
  return { id = s.id, x = s.x, y = s.y, angle = angle or 0, by = by }
end

--- Everyone in the world this tick, with where their body is. Returns the
--- (reused) list and how many entries are live.
function Simps:collect(server)
  local list, n = self.bodies, 0
  for id, player in pairs(server.players) do
    if Features.visible(server, player) then
      n = n + 1
      local e = list[n]
      if not e then
        e = {}
        list[n] = e
      end
      e.id, e.player, e.car = id, player, player.vehicle
      e.x, e.y, e.onFoot = Features.bodyPose(server, player)
    end
  end
  return list, n
end

--- The nearest player inside sight, and how far.
local function nearest(s, bodies, nbodies)
  local best, bestD2
  for i = 1, nbodies do
    local e = bodies[i]
    local d2 = (e.x - s.x) ^ 2 + (e.y - s.y) ^ 2
    if d2 <= Simps.SIGHT * Simps.SIGHT and (not bestD2 or d2 < bestD2) then
      best, bestD2 = e, d2
    end
  end
  return best, bestD2
end

--- Run at the target and punch whatever is in reach. Wedged against a wall
--- they sidestep around it.
function Simps:hunt(server, s, dt, target, dist)
  s.facing = math.atan2(target.y - s.y, target.x - s.x)
  local reach = Simps.RADIUS + Simps.REACH + (target.onFoot and 0 or Car.HEIGHT / 2)
  if s.sidestep > 0 then
    s.sidestep = s.sidestep - dt
    walk(s, s.facing + s.side * math.pi / 2, Simps.CHASE_SPEED, dt)
  elseif dist > reach then
    walk(s, s.facing, Simps.CHASE_SPEED, dt)
    if s.stuck > 0.4 then
      s.stuck, s.sidestep, s.side = 0, 0.6, -s.side
    end
  end
  s.punchTimer = s.punchTimer - dt
  if dist <= reach and s.punchTimer <= 0 then
    s.punchTimer = Simps.PUNCH_INTERVAL
    s.swing = 0.3
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, target.player, nil, Simps.PUNCH_DAMAGE, s.facing)
    end
  end
end

--- Nobody about: mill around near where they are.
function Simps:loiter(s, dt)
  if s.stuck > 0.5 or random() < dt * 0.6 then
    s.facing = s.facing + (random() - 0.5) * 2.5
    s.stuck = 0
  end
  walk(s, s.facing, Simps.WALK_SPEED * 0.5, dt)
end

--- Something stinks at (x, y): every simp within `radius` runs from it
--- for `seconds`.
function Simps:scare(x, y, radius, seconds)
  local r2 = (radius + Simps.RADIUS) ^ 2
  for i = 1, self.n do
    local s = self.list[i]
    if (s.x - x) ^ 2 + (s.y - y) ^ 2 <= r2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

--- A car touching this simp: flattened at speed, shoved aside below it.
--- Returns the kill, for the caller to announce.
function Simps:trampled(s, dt, bodies, nbodies)
  for i = 1, nbodies do
    local car = bodies[i].car
    if car and (car.x - s.x) ^ 2 + (car.y - s.y) ^ 2 < TOUCH2 and Car.hitTest(car, s.x, s.y, Simps.RADIUS) then
      local speed = math.abs(car.speed)
      if speed >= Simps.SPLAT_SPEED then
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        return { id = s.id, x = s.x, y = s.y, angle = travel, by = bodies[i].id }
      end
      local away = math.atan2(s.y - car.y, s.x - car.x)
      local push = (Simps.WALK_SPEED + speed) * dt * 2
      s.x, s.y = s.x + math.cos(away) * push, s.y + math.sin(away) * push
    end
  end
  return nil
end

--- One tick for the gang. `boss` is Karen (nil once she is down: nobody
--- else arrives). Returns this tick's kills (a reused list) and the simp
--- that just arrived, if one did.
function Simps:update(server, dt, boss)
  local bodies, nbodies = self:collect(server)
  local kills = self.kills
  for i = #kills, 1, -1 do
    kills[i] = nil
  end

  local arrived
  if boss then
    self.spawnIn = self.spawnIn - dt
    if self.spawnIn <= 0 and self.n < (self.max or Simps.MAX) then
      self.spawnIn = Simps.SPAWN_EVERY
      local x, y = Simps.spawnSpot(boss.x, boss.y)
      if x then
        arrived = self:spawn(x, y)
      end
    end
  end

  local i = 1
  while i <= self.n do
    local s = self.list[i]
    s.swing = math.max(0, s.swing - dt)
    local target, d2 = nearest(s, bodies, nbodies)
    s.target = target and target.id or nil
    if s.panic then
      -- A stink: away from it at a run, whoever is about.
      s.panic.left = s.panic.left - dt
      s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
      walk(s, s.facing, Simps.WALK_SPEED, dt)
      if s.panic.left <= 0 then
        s.panic = nil
      end
    elseif target then
      self:hunt(server, s, dt, target, math.sqrt(d2))
    else
      self:loiter(s, dt)
    end
    local kill = self:trampled(s, dt, bodies, nbodies)
    if kill then
      kills[#kills + 1] = kill
      self:removeAt(i)
    else
      i = i + 1
    end
  end
  return kills, arrived
end

return Simps
