-- The poison headcrabs the zombie throws, on the host (init.lua runs them
-- and owns the wire). Simple creatures: no stamina, no medkits.
--
--   fly      thrown: from his hand to where it was aimed over `flight`
--            seconds, in an arc. Landing on somebody is a bite.
--   crawl    after the nearest player it can see within `CHASE`, slower
--            than a sprint (`CRAWL`). Within `LEAP` of somebody on foot, or
--            close to a car, with a clear line, it leaps:
--   leap     at them, `LEAP_SPEED`, a little past where they stood. Touching
--            them on the way is a bite (`BITE`, poison: init.lua deals it and
--            the damage feature poisons them), or on a car, a scratch.
--   rest     `REST` seconds where it landed (`BITE_REST` after a bite),
--            gathering itself, then crawls on.
--   idle     nobody to go after: it sits there until somebody comes.
--
-- `HEALTH` each; rounds owned by nobody (the Combine's) pass by. A car
-- going faster than `SQUASH` over one is the end of it.

local Features = require("src.features")
local Car = require("src.car")
local Sight = require("src.features.d-day.sight")

local Crabs = {}
Crabs.__index = Crabs

-- Tuning --------------------------------------------------------------------

Crabs.RADIUS = 7 -- px; for hitting one (render.lua's CRAB_RADIUS and a bit)
Crabs.HEALTH = 30 -- a couple of pistol rounds
Crabs.THROW_SPEED = 430 -- px/s across the ground when he throws one
Crabs.CHASE = 1100 -- px it will go after somebody from
Crabs.CRAWL = 125 -- px/s: a sprint gets away, a walk doesn't
Crabs.LEAP = 150 -- px from somebody on foot that it leaps from
Crabs.LEAP_CAR = 70 -- px from a car's side that it leaps from
Crabs.LEAP_SPEED = 380 -- px/s through the air
Crabs.LEAP_PAST = 30 -- px past where they stood that it aims
Crabs.FOOT = 9 -- px; somebody on foot, for a bite
Crabs.REST = 1.3 -- seconds after a leap before it goes again
Crabs.BITE_REST = 2.2 -- ...or after one that bit somebody: two crabs on you are not over in a blink
Crabs.BITE = 15 -- poison damage a bite does, and they are poisoned after (the damage feature)
Crabs.SCRATCH = 6 -- damage a crab landing on a car does to it
Crabs.SQUASH = 60 -- px/s a car must be doing to run one over
Crabs.SPACE = 18 -- px they keep from each other
Crabs.PANIC = 1.2 -- seconds a stink sends one off for

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function blockedAt(x, y)
  return Features.any("blocksPoint", x, y)
end

function Crabs.new()
  return setmetatable({ list = {}, nextId = 1 }, Crabs)
end

local function setMode(c, mode)
  c.mode, c.t = mode, 0
end

--- Where a crab heading from (x, y) to (tx, ty) can come down: short of anything solid.
local function landing(x, y, tx, ty)
  for k = 1, 0, -0.1 do
    local lx, ly = x + (tx - x) * k, y + (ty - y) * k
    if not blockedAt(lx, ly) then
      return lx, ly
    end
  end
  return x, y
end

--- One thrown from (x, y) at (tx, ty).
function Crabs:throw(x, y, tx, ty)
  tx, ty = landing(x, y, tx, ty)
  local d = math.sqrt(dist2(x, y, tx, ty))
  local c = {
    id = self.nextId, x = x, y = y, facing = math.atan2(ty - y, tx - x), hp = Crabs.HEALTH, mode = "fly", t = 0,
    fromX = x, fromY = y, toX = tx, toY = ty, flight = math.max(0.35, d / Crabs.THROW_SPEED), frozen = 0,
    side = random() < 0.5 and -1 or 1,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = c
  return c
end

--- How far through its time in the air one is (0 on the ground).
function Crabs.air(c)
  if c.mode == "fly" then
    return math.min(1, c.t / c.flight)
  elseif c.mode == "leap" then
    return math.min(1, c.t / c.flight)
  end
  return 0
end

--- Everyone it could go after: id -> { x, y, car, p }.
local function quarry(server)
  local out = {}
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      out[id] = { x = x, y = y, car = not onFoot and p.vehicle or nil, p = p }
    end
  end
  return out
end

local function touching(c, q)
  if q.car then
    return Car.hitTest(q.car, c.x, c.y, Crabs.RADIUS)
  end
  return dist2(c.x, c.y, q.x, q.y) <= (Crabs.RADIUS + Crabs.FOOT) ^ 2
end

--- Off into the air from where it is to (tx, ty).
local function leap(c, tx, ty)
  tx, ty = landing(c.x, c.y, tx, ty)
  local d = math.sqrt(dist2(c.x, c.y, tx, ty))
  c.fromX, c.fromY, c.toX, c.toY = c.x, c.y, tx, ty
  c.flight = math.max(0.2, d / Crabs.LEAP_SPEED)
  c.facing = math.atan2(ty - c.y, tx - c.x)
  c.bit = false
  setMode(c, "leap")
end

--- A step that way, round whatever is in the way, keeping off the others.
local function crawl(self, c, angle, dt)
  local step = Crabs.CRAWL * dt
  local ax, ay = math.cos(angle), math.sin(angle)
  for _, o in ipairs(self.list) do
    if o ~= c and o.mode ~= "fly" then
      local d2 = dist2(o.x, o.y, c.x, c.y)
      if d2 < Crabs.SPACE * Crabs.SPACE and d2 > 0.01 then
        local d = math.sqrt(d2)
        ax, ay = ax + (c.x - o.x) / d, ay + (c.y - o.y) / d
      end
    end
  end
  local a = math.atan2(ay, ax)
  for _, off in ipairs({ 0, c.side * 0.9, -c.side * 0.9, c.side * 1.6 }) do
    local nx, ny = c.x + math.cos(a + off) * step, c.y + math.sin(a + off) * step
    if not blockedAt(nx, ny) then
      c.x, c.y = nx, ny
      c.facing = a + off
      return
    end
  end
  c.side = -c.side
end

--- One tick of crab `c`.
function Crabs:step(c, people, dt, bite)
  c.t = c.t + dt
  if c.frozen > 0 then
    c.frozen = c.frozen - dt
  elseif c.mode == "fly" or c.mode == "leap" then
    local k = math.min(1, c.t / c.flight)
    c.x, c.y = c.fromX + (c.toX - c.fromX) * k, c.fromY + (c.toY - c.fromY) * k
    -- A thrown one bites whoever it comes down on; a leaping one, whoever it reaches.
    if not c.bit and (c.mode == "leap" or k >= 0.85) then
      for _, q in pairs(people) do
        if touching(c, q) then
          c.bit = true
          bite(c, q)
          break
        end
      end
    end
    if k >= 1 then
      c.rest = c.bit and Crabs.BITE_REST or Crabs.REST
      c.bit = false
      setMode(c, "rest")
    end
  elseif c.mode == "rest" then
    if c.t >= (c.rest or Crabs.REST) then
      setMode(c, "crawl")
    end
  elseif c.panic then
    c.panic = c.panic - dt
    crawl(self, c, c.panicAngle, dt)
    if c.panic <= 0 then
      c.panic = nil
    end
  else
    local best, bestD2 = nil, Crabs.CHASE * Crabs.CHASE
    for _, q in pairs(people) do
      local d2 = dist2(q.x, q.y, c.x, c.y)
      if d2 < bestD2 then
        best, bestD2 = q, d2
      end
    end
    if not best then
      c.mode = "idle"
    else
      c.mode = "crawl"
      local d = math.sqrt(bestD2)
      local toward = math.atan2(best.y - c.y, best.x - c.x)
      local near = best.car and Car.hitTest(best.car, c.x, c.y, Crabs.LEAP_CAR) or (not best.car and d <= Crabs.LEAP)
      if near and Sight.clear(c.x, c.y, best.x, best.y) then
        local past = best.car and 0 or Crabs.LEAP_PAST
        leap(c, best.x + math.cos(toward) * past, best.y + math.sin(toward) * past)
      else
        crawl(self, c, toward, dt)
      end
    end
  end
end

--- One tick of every crab. `bite(c, q)` is called for each bite on
--- somebody (q: { x, y, car, p }); returns nothing. One shot dead this
--- tick (not swept up yet) bites nobody.
function Crabs:update(server, dt, bite)
  local people = quarry(server)
  for _, c in ipairs(self.list) do
    if not c.dead then
      self:step(c, people, dt, bite)
    end
  end
end

--- Cars running them over: returns the ones squashed, each with the driver's id as `by`.
function Crabs:squashed(server)
  local out = nil
  for _, car in pairs(server.vehicles) do
    if car.driver and not car.hidden and math.abs(car.speed or 0) >= Crabs.SQUASH then
      for _, c in ipairs(self.list) do
        if Crabs.air(c) < 0.15 and not c.dead and Car.hitTest(car, c.x, c.y, Crabs.RADIUS * 0.5) then
          c.dead, c.by = true, car.driver
          c.angle = car.speed >= 0 and car.angle or car.angle + math.pi
          out = out or {}
          out[#out + 1] = c
        end
      end
    end
  end
  return out
end

--- The crab a round or blast through (x, y) `radius` across hits, and its index.
function Crabs:at(x, y, radius)
  for i, c in ipairs(self.list) do
    if not c.dead and dist2(c.x, c.y, x, y) <= (Crabs.RADIUS + radius) ^ 2 then
      return c, i
    end
  end
  return nil
end

--- `amount` off it; true if that killed it.
function Crabs:hurt(c, amount)
  c.hp = c.hp - amount
  if c.hp <= 0 and not c.dead then
    c.dead = true
    return true
  end
  return false
end

--- How many are still alive.
function Crabs:alive()
  local n = 0
  for _, c in ipairs(self.list) do
    if not c.dead then
      n = n + 1
    end
  end
  return n
end

--- Take the dead out of the list.
function Crabs:sweep()
  for i = #self.list, 1, -1 do
    if self.list[i].dead then
      table.remove(self.list, i)
    end
  end
end

function Crabs:freeze(x, y, radius, seconds)
  for _, c in ipairs(self.list) do
    if dist2(c.x, c.y, x, y) <= (radius + Crabs.RADIUS) ^ 2 then
      c.frozen = math.max(c.frozen, seconds)
    end
  end
end

function Crabs:scare(x, y, radius)
  for _, c in ipairs(self.list) do
    if (c.mode == "crawl" or c.mode == "idle") and dist2(c.x, c.y, x, y) <= (radius + Crabs.RADIUS) ^ 2 then
      c.panic, c.panicAngle = Crabs.PANIC, math.atan2(c.y - y, c.x - x)
    end
  end
end

return Crabs
