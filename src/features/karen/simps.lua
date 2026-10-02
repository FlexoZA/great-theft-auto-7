-- Karen's simps: the hangers-on who turn up to defend her. While she stands,
-- one arrives every few seconds until five are about, each with a name
-- that starts "Simpin" (Simpin Jim, Simpin Ben...). They run at the nearest
-- player and punch, take a couple of pistol rounds, and burst like any
-- pedestrian; a car at speed flattens one. Once she is down no more come,
-- but the ones already out keep swinging until they are dealt with.
--
-- What each one does is the simps' brain's (simp_brain.lua): stay by her,
-- go for whoever shot her, and come at you from all sides.
--
-- The host owns them (init.lua drives this module from Karen's step and
-- owns the wire format); clients draw what KRN_SIMPS tells them.

local Features = require("src.features")
local Car = require("src.car")
local Brain = require("src.features.karen.simp_brain")

local Simps = {}
Simps.__index = Simps

-- Tuning --------------------------------------------------------------------

Simps.MAX = 5 -- at a time, for one player (karen sets `max` on a gang for the humans there)
Simps.SPAWN_EVERY = 4 -- seconds between arrivals while there is room
Simps.FIRST_AFTER = 3 -- seconds after she appears before the first one
Simps.SPAWN_MIN = 140 -- px from her they appear...
Simps.SPAWN_MAX = 260 -- ...out to here
Simps.RADIUS = 8 -- px; a pedestrian's size (drawn as a person: src/body.lua)
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

-- The gang --------------------------------------------------------------------

function Simps.new()
  return setmetatable({
    list = {},
    n = 0,
    nextId = 1,
    spawnIn = Simps.FIRST_AFTER,
    time = 0, -- the gang's clock (how long since she was shot, for their brain)
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
  self.time = self.time + dt
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
    Brain.think(Simps, s, server, dt, bodies, nbodies, boss, self.time)
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
