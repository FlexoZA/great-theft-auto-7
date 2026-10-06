-- What each rollermine does, on the host (init.lua runs them and owns the wire).
--
--   dormant  half sunk in the ground where it was set, shell shut, still. A
--            player (on foot or driving, anyone the game shows) within
--            `WAKE` of one wakes it.
--   popping  it hops up out of the ground and its blades snap out, `POP`
--            seconds; it can be shot.
--   roll     after the nearest player within `CHASE`: it accelerates at
--            `ACCEL` towards where they are going to be (it leads a moving
--            target by `LEAD` seconds), up to `TOP` px/s, a little short of
--            a car flat out. It has momentum: it overshoots a turn, swings
--            round, and bounces off walls (`BOUNCE`). Within `ARM` of them it
--            starts beeping, and touching them (or their car) sets it off;
--            somebody on foot it touched (`zap`) takes a shock as well
--            (`SHOCK`: init.lua deals it), enough to stun them.
--   idle     nobody to go after for `GIVE_UP` seconds: it rolls to a stop
--            where it is, blades out, and wakes again the way a dormant one does.
-- It goes off on contact, when it is shot to pieces (`HEALTH`), or
-- caught in a blast (another mine's included, a moment later: `CHAIN`),
-- and the blast (`BLAST`) hurts everyone and every car near it. Init.lua
-- sets it off; the brain only says which ones are due (`due`).
--
-- Frozen, one stops dead; a stink sends it rolling off the other way for a moment.

local Features = require("src.features")
local Car = require("src.car")

local Brain = {}
Brain.__index = Brain

-- Tuning --------------------------------------------------------------------

Brain.RADIUS = 12 -- px; its shell (render.lua draws it this size)
Brain.HEALTH = 40 -- two pistol rounds and change: worth shooting, not trivial
Brain.WAKE = 460 -- px from a dormant one that wakes it
Brain.POP = 0.55 -- seconds hopping up out of the ground
Brain.CHASE = 1600 -- px it will go after somebody from
Brain.GIVE_UP = 7 -- seconds with nobody to go after before it stops
Brain.ACCEL = 520 -- px/s^2 it can put down
Brain.TOP = 430 -- px/s; a car flat out (500) gets away, slowly
Brain.LEAD = 0.45 -- seconds ahead of a moving target that it aims
Brain.GRIP = 1.6 -- per second, how fast sideways momentum bleeds off (low: it slides)
Brain.BOUNCE = 0.55 -- of its speed it keeps off a wall
Brain.ARM = 140 -- px from its target that it starts beeping
Brain.FOOT = 16 -- px; somebody on foot, for contact: its blade tips reach them (RADIUS + 16 = 28)
Brain.SHOCK = 35 -- shock damage to somebody on foot it touches, as it goes off: a jolt that stuns them
Brain.SPACE = 34 -- px it keeps from the others
Brain.CHAIN = 0.18 -- seconds after a blast catches one before it goes off too
Brain.PANIC = 1.4 -- seconds a stink sends it off for
Brain.BLAST = { radius = 95, damage = 45, soft = 3 } -- weapons' blast: nobody's, explosive

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function Brain.new()
  return setmetatable({ list = {}, nextId = 1, time = 0 }, Brain)
end

--- One set dormant at (x, y), or the nearest open spot round it.
function Brain:place(x, y)
  for _ = 1, 20 do
    if not Features.any("blocksPoint", x, y) then
      break
    end
    x, y = x + (random() - 0.5) * 60, y + (random() - 0.5) * 60
  end
  local m = {
    id = self.nextId, x = x, y = y, vx = 0, vy = 0, hp = Brain.HEALTH, mode = "dormant", t = 0, lost = 0,
    frozen = 0, side = random() < 0.5 and -1 or 1, spin = random() * 2 * math.pi,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = m
  return m
end

local function setMode(m, mode)
  m.mode, m.t = mode, 0
end

--- Everyone it could go after: id -> { x, y, vx, vy, car, p }.
local function quarry(server)
  local out = {}
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      local car = not onFoot and p.vehicle or nil
      out[id] = { x = x, y = y, vx = car and car.vx or 0, vy = car and car.vy or 0, car = car, p = p }
    end
  end
  return out
end

local function nearest(people, x, y, reach)
  local best, bestD2 = nil, reach * reach
  for id, q in pairs(people) do
    local d2 = dist2(q.x, q.y, x, y)
    if d2 < bestD2 then
      best, bestD2 = id, d2
    end
  end
  return best, bestD2
end

--- Is it touching `q`: their car's box, or them on foot?
local function touching(m, q)
  if q.car then
    return Car.hitTest(q.car, m.x, m.y, Brain.RADIUS)
  end
  return dist2(m.x, m.y, q.x, q.y) <= (Brain.RADIUS + Brain.FOOT) ^ 2
end

local function blockedAt(x, y)
  local r = Brain.RADIUS
  return Features.any("blocksPoint", x - r, y) or Features.any("blocksPoint", x + r, y)
    or Features.any("blocksPoint", x, y - r) or Features.any("blocksPoint", x, y + r)
end

--- Roll on by its momentum, each axis on its own, bouncing off whatever is in the way.
local function roll(m, dt)
  local nx = m.x + m.vx * dt
  if blockedAt(nx, m.y) then
    m.vx = -m.vx * Brain.BOUNCE
  else
    m.x = nx
  end
  local ny = m.y + m.vy * dt
  if blockedAt(m.x, ny) then
    m.vy = -m.vy * Brain.BOUNCE
  else
    m.y = ny
  end
  m.spin = m.spin + math.sqrt(m.vx * m.vx + m.vy * m.vy) * dt / Brain.RADIUS
end

--- Push it towards `angle` at full acceleration, bleeding off whatever
--- momentum runs across that way, and hold it to its top speed.
local function drive(m, angle, dt, accel)
  local ax, ay = math.cos(angle), math.sin(angle)
  local along = m.vx * ax + m.vy * ay
  local sx, sy = m.vx - ax * along, m.vy - ay * along
  local keep = math.exp(-Brain.GRIP * dt)
  along = along + (accel or Brain.ACCEL) * dt
  m.vx, m.vy = ax * along + sx * keep, ay * along + sy * keep
  local speed = math.sqrt(m.vx * m.vx + m.vy * m.vy)
  if speed > Brain.TOP then
    m.vx, m.vy = m.vx / speed * Brain.TOP, m.vy / speed * Brain.TOP
  end
end

--- Slow it down, rolling free.
local function brake(m, dt, rate)
  local k = math.exp(-(rate or 2) * dt)
  m.vx, m.vy = m.vx * k, m.vy * k
end

--- Away from the others of its kind near it, added to a heading.
function Brain:spread(m, angle)
  local sx, sy = math.cos(angle), math.sin(angle)
  for _, o in ipairs(self.list) do
    if o ~= m and o.mode ~= "dormant" then
      local dd = dist2(m.x, m.y, o.x, o.y)
      if dd < Brain.SPACE * Brain.SPACE and dd > 0.01 then
        local d = math.sqrt(dd)
        local k = 1 - d / Brain.SPACE
        sx, sy = sx + (m.x - o.x) / d * k * 1.5, sy + (m.y - o.y) / d * k * 1.5
      end
    end
  end
  return math.atan2(sy, sx)
end

function Brain:update(server, dt)
  self.time = self.time + dt
  local people = quarry(server)
  for _, m in ipairs(self.list) do
    self:think(m, people, dt)
  end
end

function Brain:think(m, people, dt)
  m.t = m.t + dt
  m.armed = false
  if m.fuse then
    m.fuse = m.fuse - dt
    return
  end
  if m.mode == "dormant" or m.mode == "idle" then
    if m.mode == "idle" then
      brake(m, dt)
      roll(m, dt)
    end
    if nearest(people, m.x, m.y, Brain.WAKE) then
      m.lost = 0
      setMode(m, m.mode == "dormant" and "popping" or "roll")
    end
    return
  end
  if m.frozen > 0 then
    m.frozen = m.frozen - dt
    m.vx, m.vy = 0, 0
    return
  end
  if m.mode == "popping" then
    if m.t >= Brain.POP then
      setMode(m, "roll")
    end
    return
  end
  if m.panic then
    m.panic.left = m.panic.left - dt
    drive(m, math.atan2(m.y - m.panic.y, m.x - m.panic.x), dt)
    roll(m, dt)
    if m.panic.left <= 0 then
      m.panic = nil
    end
    return
  end

  -- Rolling: after the nearest it can reach.
  local id, d2 = nearest(people, m.x, m.y, Brain.CHASE)
  m.target = id
  if not id then
    m.lost = m.lost + dt
    brake(m, dt)
    roll(m, dt)
    if m.lost >= Brain.GIVE_UP then
      setMode(m, "idle")
    end
    return
  end
  m.lost = 0
  local q = people[id]
  if touching(m, q) then
    m.fuse = 0 -- contact: off it goes
    m.zap = not q.car and q.p or nil -- and on foot, its blades shock them first
    return
  end
  local d = math.sqrt(d2)
  m.armed = d <= Brain.ARM
  -- Where they will be by the time it gets there, not where they are.
  local lead = math.min(Brain.LEAD, d / Brain.TOP)
  local tx, ty = q.x + q.vx * lead, q.y + q.vy * lead
  local angle = self:spread(m, math.atan2(ty - m.y, tx - m.x))
  drive(m, angle, dt)
  local before = m.vx * m.vx + m.vy * m.vy
  roll(m, dt)
  if before > 400 and (m.vx * m.vx + m.vy * m.vy) < before * 0.4 then
    -- Hit something head on: a shove round it, the way it favours.
    drive(m, angle + m.side * math.pi / 2, dt, Brain.ACCEL * 4)
  end
end

--- The ones whose fuse has run out, taken off the list: init.lua sets them off.
function Brain:due()
  local out
  for i = #self.list, 1, -1 do
    local m = self.list[i]
    if m.fuse and m.fuse <= 0 then
      table.remove(self.list, i)
      out = out or {}
      out[#out + 1] = m
    end
  end
  return out
end

--- The one within `radius` of (x, y), and its index.
function Brain:at(x, y, radius)
  local r2 = (radius + Brain.RADIUS) ^ 2
  for i, m in ipairs(self.list) do
    if not m.fuse and dist2(m.x, m.y, x, y) < r2 then
      return m, i
    end
  end
  return nil
end

--- Take `amount` off `m`. Shot to pieces, it goes off at once; caught in a
--- blast (`blast`), a moment later. Any hit wakes it.
function Brain:hurt(m, amount, blast)
  m.hp = m.hp - amount
  if m.hp <= 0 then
    m.fuse = blast and Brain.CHAIN or 0
    return true
  end
  if m.mode == "dormant" or m.mode == "idle" then
    setMode(m, m.mode == "dormant" and "popping" or "roll")
  end
  return false
end

--- Everyone inside a freeze stops dead for `seconds`.
function Brain:freeze(x, y, radius, seconds)
  for _, m in ipairs(self.list) do
    if dist2(m.x, m.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      m.frozen = math.max(m.frozen, seconds)
    end
  end
end

--- Everyone rolling inside a stink rolls off from it for a moment.
function Brain:scare(x, y, radius)
  for _, m in ipairs(self.list) do
    if m.mode == "roll" and dist2(m.x, m.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      m.panic = { x = x, y = y, left = Brain.PANIC }
    end
  end
end

return Brain
