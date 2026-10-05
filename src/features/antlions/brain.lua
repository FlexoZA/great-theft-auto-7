-- What each antlion does, on the host (init.lua runs them and owns the wire).
--
--   under    buried in the sand, nothing to see. A player (on foot or not,
--            anyone the game shows) within `WAKE` of one wakes its whole
--            swarm: each comes up a moment after the last (`WAKE_SPREAD`).
--   rising   crawling up out of the sand for `RISE` seconds; it can be shot.
--   run      after the nearest player it can get at, within `CHASE`: at
--            `RUN` px/s, a little short of a sprint, spreading out round
--            them rather than piling up behind each other. Close enough
--            (`REACH`) and ready, it bites; from `LEAP_NEAR`..`LEAP_FAR`
--            away it now and then leaps the last of the way.
--   bite     the mandibles open and snap shut: `BITE_HIT` seconds in, if
--            whoever it went for is still in reach, they take `BITE`
--            (melee). Then `BITE_EVERY` before the next.
--   air      a leap: `LEAP_TIME` seconds in the air at `LEAP_SPEED` straight
--            at where they were going, landing ready to bite.
--   sinking  nobody to go after for `GIVE_UP` seconds: it burrows back
--            down where it is, `SINK` seconds, and is under again, to wake
--            the same way.
--
-- Frozen, one stands stiff; a stink sends it scuttling off for a moment.
-- No sight cones: they come up already knowing where you are.

local Features = require("src.features")

local Brain = {}
Brain.__index = Brain

-- Tuning --------------------------------------------------------------------

Brain.RADIUS = 11 -- px; its body (render.lua's RADIUS)
Brain.HEALTH = 30 -- two pistol rounds
Brain.WAKE = 320 -- px from a buried one that brings its swarm up
Brain.WAKE_SPREAD = 1.1 -- seconds over which a swarm's antlions come up
Brain.RISE = 0.9 -- seconds crawling up out of the sand
Brain.SINK = 1.2 -- seconds burrowing back down
Brain.CHASE = 1400 -- px it will go after somebody from
Brain.GIVE_UP = 6 -- seconds with nobody to go after before it goes back under
Brain.RUN = 150 -- px/s; a sprint (170) gets away, slowly
Brain.REACH = 26 -- px between their middles that a bite reaches
Brain.BITE = 5 -- what a bite takes off
Brain.BITE_HIT = 0.22 -- seconds into a bite that the mandibles close
Brain.BITE_TIME = 0.38 -- seconds a bite takes
Brain.BITE_EVERY = 0.75 -- seconds after one bite before the next can start
Brain.LEAP_NEAR, Brain.LEAP_FAR = 110, 240 -- px from its target that it may leap from
Brain.LEAP_TIME = 0.55 -- seconds in the air
Brain.LEAP_SPEED = 360 -- px/s through the air
Brain.LEAP_EVERY = 4 -- seconds at least between one's leaps
Brain.LEAP_CHANCE = 0.6 -- per second, the chance it leaps while it may
Brain.SPACE = 30 -- px it keeps from the others of its kind
Brain.FLANK = 0.6 -- radians it curves round to its own side of whoever it is after, close in
Brain.PANIC = 1.2 -- seconds a stink sends it off for

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function turn(from, to, rate, dt)
  local d = wrap(to - from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

function Brain.new()
  return setmetatable({ list = {}, swarms = {}, nextId = 1, time = 0, bites = {} }, Brain)
end

--- A swarm of `count` buried within `r` of (x, y), on open ground.
function Brain:bury(x, y, r, count)
  local swarm = { members = {} }
  self.swarms[#self.swarms + 1] = swarm
  for _ = 1, count do
    local ax, ay = x, y
    for _ = 1, 20 do
      local a, d = random() * 2 * math.pi, math.sqrt(random()) * r
      local tx, ty = x + math.cos(a) * d, y + math.sin(a) * d
      if not Features.any("blocksPoint", tx, ty) then
        ax, ay = tx, ty
        break
      end
    end
    local a = {
      id = self.nextId, x = ax, y = ay, facing = random() * 2 * math.pi, hp = Brain.HEALTH,
      mode = "under", t = 0, swarm = swarm, biteIn = 0, leapIn = random() * Brain.LEAP_EVERY, lost = 0,
      frozen = 0, side = random() < 0.5 and -1 or 1,
    }
    self.nextId = self.nextId + 1
    self.list[#self.list + 1] = a
    swarm.members[#swarm.members + 1] = a
  end
  return swarm
end

--- Out of the sand: anything but buried (or about to come up).
function Brain.above(a)
  return a.mode ~= "under"
end

local function setMode(a, mode)
  a.mode, a.t = mode, 0
end

--- Everyone it could go after: id -> { x, y } of each player the game shows.
local function quarry(server)
  local out = {}
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      out[id] = { x = x, y = y, p = p }
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

--- Solid ground at the four extremes of its body.
local function blockedAt(x, y)
  local r = Brain.RADIUS
  return Features.any("blocksPoint", x, y) or Features.any("blocksPoint", x - r, y)
    or Features.any("blocksPoint", x + r, y) or Features.any("blocksPoint", x, y - r)
    or Features.any("blocksPoint", x, y + r)
end

--- A step that way, each axis on its own so it slides along whatever is in the way.
local function move(a, angle, speed, dt)
  local px, py = a.x, a.y
  local nx = a.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, a.y) then
    a.x = nx
  end
  local ny = a.y + math.sin(angle) * speed * dt
  if not blockedAt(a.x, ny) then
    a.y = ny
  end
  return (a.x - px) ^ 2 + (a.y - py) ^ 2 > (speed * dt * 0.3) ^ 2
end

--- Its swarm comes up, staggered; the one that felt them first leads.
local function wake(a)
  for _, m in ipairs(a.swarm.members) do
    if m.mode == "under" and not m.wakeIn then
      m.wakeIn = m == a and 0 or random() * Brain.WAKE_SPREAD
    end
  end
end

--- Which way to go for (tx, ty): straight at it from afar, curving round to
--- its own side close in, and away from the others near it.
function Brain:steer(a, tx, ty)
  local d = math.sqrt(dist2(a.x, a.y, tx, ty))
  local angle = math.atan2(ty - a.y, tx - a.x)
  if d < 160 then
    angle = angle + a.side * Brain.FLANK * (1 - d / 160)
  end
  local sx, sy = math.cos(angle), math.sin(angle)
  for _, o in ipairs(self.list) do
    if o ~= a and o.mode ~= "under" then
      local dd = dist2(a.x, a.y, o.x, o.y)
      if dd < Brain.SPACE * Brain.SPACE and dd > 0.01 then
        local k = 1 - math.sqrt(dd) / Brain.SPACE
        sx, sy = sx + (a.x - o.x) / math.sqrt(dd) * k * 1.5, sy + (a.y - o.y) / math.sqrt(dd) * k * 1.5
      end
    end
  end
  return math.atan2(sy, sx)
end

local function bite(server, a, q)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    weapons:serverDamage(server, q.p, nil, Brain.BITE, a.facing, "melee")
  end
end

function Brain:update(server, dt)
  self.time = self.time + dt
  local people = quarry(server)
  for _, a in ipairs(self.list) do
    self:think(server, a, people, dt)
  end
end

function Brain:think(server, a, people, dt)
  a.t = a.t + dt
  a.biteIn = math.max(0, a.biteIn - dt)
  a.leapIn = math.max(0, a.leapIn - dt)
  if a.mode == "under" then
    if a.wakeIn then
      a.wakeIn = a.wakeIn - dt
      if a.wakeIn <= 0 then
        a.wakeIn, a.lost, a.target = nil, 0, nil
        setMode(a, "rising")
      end
    elseif nearest(people, a.x, a.y, Brain.WAKE) then
      wake(a)
    end
    return
  end
  if a.frozen > 0 then
    a.frozen = a.frozen - dt
    return
  end
  if a.mode == "rising" then
    local id = nearest(people, a.x, a.y, Brain.CHASE)
    if id then
      a.facing = turn(a.facing, math.atan2(people[id].y - a.y, people[id].x - a.x), 4, dt)
    end
    if a.t >= Brain.RISE then
      setMode(a, "run")
    end
    return
  elseif a.mode == "sinking" then
    if a.t >= Brain.SINK then
      setMode(a, "under")
    end
    return
  end
  if a.panic then
    a.panic.left = a.panic.left - dt
    a.facing = math.atan2(a.y - a.panic.y, a.x - a.panic.x)
    move(a, a.facing, Brain.RUN * 1.2, dt)
    if a.panic.left <= 0 then
      a.panic = nil
    end
    return
  end

  local q = a.target and people[a.target]
  if a.mode == "air" then
    move(a, a.leapAngle, Brain.LEAP_SPEED, dt)
    if a.t >= Brain.LEAP_TIME then
      a.biteIn = 0
      setMode(a, "run")
    end
    return
  elseif a.mode == "bite" then
    if q then
      a.facing = turn(a.facing, math.atan2(q.y - a.y, q.x - a.x), 6, dt)
    end
    if not a.bit and a.t >= Brain.BITE_HIT then
      a.bit = true
      if q and dist2(a.x, a.y, q.x, q.y) <= (Brain.REACH + 6) ^ 2 then
        bite(server, a, q)
      end
    end
    if a.t >= Brain.BITE_TIME then
      a.biteIn, a.bit = Brain.BITE_EVERY, nil
      setMode(a, "run")
    end
    return
  end

  -- Running: after the nearest it can reach.
  local id, d2 = nearest(people, a.x, a.y, Brain.CHASE)
  a.target = id
  if not id then
    a.lost = a.lost + dt
    if a.lost >= Brain.GIVE_UP then
      setMode(a, "sinking")
    end
    return
  end
  a.lost = 0
  q = people[id]
  local d = math.sqrt(d2)
  local toward = math.atan2(q.y - a.y, q.x - a.x)
  if d <= Brain.REACH then
    a.facing = turn(a.facing, toward, 8, dt)
    if a.biteIn <= 0 then
      setMode(a, "bite")
    end
    return
  end
  if d >= Brain.LEAP_NEAR and d <= Brain.LEAP_FAR and a.leapIn <= 0 and random() < Brain.LEAP_CHANCE * dt then
    a.leapIn = Brain.LEAP_EVERY + random() * 2
    a.leapAngle = toward
    a.facing = toward
    setMode(a, "air")
    return
  end
  local way = self:steer(a, q.x, q.y)
  a.facing = turn(a.facing, way, 7, dt)
  if not move(a, way, Brain.RUN, dt) then
    -- Stuck on something: try round it, the way it favours.
    move(a, way + a.side * math.pi / 2, Brain.RUN, dt)
  end
end

--- The one (above the sand) within `radius` of (x, y), and its index.
function Brain:at(x, y, radius)
  local r2 = (radius + Brain.RADIUS) ^ 2
  for i, a in ipairs(self.list) do
    if a.mode ~= "under" and dist2(a.x, a.y, x, y) < r2 then
      return a, i
    end
  end
  return nil
end

--- Take `amount` off `a` (the i-th). Returns true if that killed it; it is
--- gone from the list then. Hurt, it turns on whoever did it.
function Brain:hurt(a, i, amount, by)
  a.hp = a.hp - amount
  if a.hp <= 0 then
    table.remove(self.list, i)
    for k, m in ipairs(a.swarm.members) do
      if m == a then
        table.remove(a.swarm.members, k)
        break
      end
    end
    return true
  end
  if by and by ~= 0 then
    a.target, a.lost = by, 0
  end
  return false
end

--- Everyone out of the sand inside a freeze stands stiff for `seconds`.
function Brain:freeze(x, y, radius, seconds)
  for _, a in ipairs(self.list) do
    if a.mode ~= "under" and dist2(a.x, a.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      a.frozen = math.max(a.frozen, seconds)
    end
  end
end

--- Everyone out of the sand inside a stink scuttles off from it for a moment.
function Brain:scare(x, y, radius)
  for _, a in ipairs(self.list) do
    if a.mode ~= "under" and dist2(a.x, a.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      a.panic = { x = x, y = y, left = Brain.PANIC }
    end
  end
end

return Brain
