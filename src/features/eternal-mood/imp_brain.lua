-- How Heck's imps think (docs/eternal-mood.md, "The demons"): the common
-- demon, brown and spiky, throwing fireballs. horde.lua puts them on the map
-- (out of the vents) and draws them, fireballs.lua flies what they throw;
-- this is only their heads, on the host.
--
-- An imp crawls out of its vent (EMERGE seconds) and goes for the nearest
-- player it can see, or the nearest at all if it can see nobody: it is
-- hunting, and it finds its way on `nav`. It keeps its distance (NEAR to
-- FAR), strafing sideways and turning back when it runs into something, and
-- every so often it stops, holds a fireball up for WINDUP seconds (a tell,
-- drawn on every screen) and throws it at where its target stands: slow
-- enough to sidestep. Caught up close, it claws.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 12 -- px; hunched, wider than a person (horde.lua draws it bigger too)
Brain.HEALTH = 60
Brain.EMERGE = 1.0 -- seconds crawling out of its vent
Brain.SEES = 640 -- px; it sees all round (they're everywhere at once)
Brain.HUNTS = 1400 -- px; seeing nobody, it goes after the nearest player this near
Brain.RUN = 140 -- px/s closing in
Brain.STRAFE = 105 -- px/s sideways
Brain.STRAFE_FOR = { 0.9, 1.8 } -- seconds before it switches sides
Brain.NEAR = 150 -- px; it backs off nearer than this (unless it can claw)...
Brain.FAR = 380 -- ...and closes in further than this
Brain.THROW_EVERY = { 1.8, 2.8 } -- seconds between fireballs
Brain.THROW_RANGE = 650 -- px
Brain.WINDUP = 0.45 -- seconds the fireball is held up before it goes
Brain.CLAW_REACH = 30 -- px
Brain.CLAW_EVERY = 0.8
Brain.CLAW_DAMAGE = 10
Brain.TURN = 7 -- rad/s
Brain.LOOK_EVERY = 3
Brain.REPATH = 0.5

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

local function turn(from, to, rate, dt)
  local d = Sight.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- A new brain. `opts`: nav, firstId, and the host's hands:
--- `throw(server, imp, x, y, angle)` a fireball from (x, y) along `angle`,
--- `claw(server, imp, playerId, damage, angle)`.
function Brain.new(opts)
  return setmetatable({
    list = {},
    nav = opts.nav,
    throw = opts.throw,
    claw = opts.claw,
    nextId = opts.firstId or 1,
    tick = 0,
  }, Brain)
end

--- An imp crawling out of a vent at (x, y), heading out along `angle`.
function Brain:add(x, y, angle)
  local s = {
    id = self.nextId,
    x = x,
    y = y,
    facing = angle or 0,
    out = angle or 0,
    hp = Brain.HEALTH,
    state = "emerge", -- emerge, hunt, windup
    t = 0,
    target = nil,
    side = random() < 0.5 and 1 or -1,
    sideFor = between(Brain.STRAFE_FOR),
    throwIn = between(Brain.THROW_EVERY) * 0.6,
    clawIn = 0,
    path = nil,
    step = 1,
    pathIn = 0,
    frozen = 0,
    look = self.nextId,
    stride = 0,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

local function poseOf(server, who)
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- The nearest player it can see; else the nearest within HUNTS at all.
local function pick(server, s)
  local seen, seenD, any, anyD
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(s.x, s.y, x, y)
      if d2 <= Brain.SEES * Brain.SEES and Sight.clear(s.x, s.y, x, y) and (not seenD or d2 < seenD) then
        seen, seenD = id, d2
      end
      if d2 <= Brain.HUNTS * Brain.HUNTS and (not anyD or d2 < anyD) then
        any, anyD = id, d2
      end
    end
  end
  return seen or any
end

local function fits(x, y)
  local r = Brain.RADIUS
  return not (Ground.blocked(x, y) or Ground.blocked(x - r, y) or Ground.blocked(x + r, y)
    or Ground.blocked(x, y - r) or Ground.blocked(x, y + r))
end

local function move(s, mx, my)
  if fits(s.x + mx, s.y + my) then
    s.x, s.y = s.x + mx, s.y + my
  elseif fits(s.x + mx, s.y) then
    s.x = s.x + mx
  elseif fits(s.x, s.y + my) then
    s.y = s.y + my
  else
    return false
  end
  s.stride = s.stride + math.sqrt(mx * mx + my * my)
  return true
end

local function goTo(self, s, x, y, speed, dt)
  local gx, gy = x, y
  if not Ground.clear(s.x, s.y, x, y) and self.nav then
    s.pathIn = s.pathIn - dt
    if not s.path or s.pathIn <= 0 then
      s.path, s.step, s.pathIn = self.nav:path(s.x, s.y, x, y), 1, Brain.REPATH
    end
    local p = s.path and s.path[s.step]
    while p and dist2(s.x, s.y, p.x, p.y) < 14 * 14 do
      s.step = s.step + 1
      p = s.path[s.step]
    end
    if p then
      gx, gy = p.x, p.y
    end
  else
    s.path = nil
  end
  local dx, dy = gx - s.x, gy - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then
    return
  end
  s.facing = turn(s.facing, math.atan2(dy, dx), Brain.TURN, dt)
  local k = math.min(d, speed * dt) / d
  move(s, dx * k, dy * k)
end

local function enter(s, state)
  s.state, s.t = state, 0
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.threw, s.clawed = nil, nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  s.throwIn = s.throwIn - dt
  s.clawIn = s.clawIn - dt
  if s.state == "emerge" then
    -- Out of the vent along `out`, not yet in the fight.
    move(s, math.cos(s.out) * 40 * dt, math.sin(s.out) * 40 * dt)
    if s.t >= Brain.EMERGE then
      enter(s, "hunt")
    end
    return
  end
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    s.target = pick(server, s)
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
  end
  if not tx then
    s.target = nil
    if s.state == "windup" then
      enter(s, "hunt")
    end
    return -- nobody about: it waits, growling
  end
  local aim = math.atan2(ty - s.y, tx - s.x)
  if s.state == "windup" then
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
    if s.t >= Brain.WINDUP then
      -- At where they stand now: moving sidesteps it.
      local hx, hy = s.x + math.cos(s.facing) * 12, s.y + math.sin(s.facing) * 12
      self.throw(server, s, hx, hy, math.atan2(ty - hy, tx - hx))
      s.threw = true
      s.throwIn = between(Brain.THROW_EVERY)
      enter(s, "hunt")
    end
    return
  end
  local d2 = dist2(s.x, s.y, tx, ty)
  local seen = Sight.clear(s.x, s.y, tx, ty)
  if seen and d2 <= (Brain.CLAW_REACH + Brain.RADIUS) ^ 2 then
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
    if s.clawIn <= 0 then
      s.clawIn = Brain.CLAW_EVERY
      self.claw(server, s, s.target, Brain.CLAW_DAMAGE, aim)
      s.clawed = true
    end
    return
  end
  if seen and s.throwIn <= 0 and d2 <= Brain.THROW_RANGE * Brain.THROW_RANGE then
    s.facing = aim
    enter(s, "windup")
    return
  end
  if not seen or d2 > Brain.FAR * Brain.FAR then
    goTo(self, s, tx, ty, Brain.RUN, dt)
    return
  end
  -- In its band: strafe across them, backing off if they get too near.
  s.sideFor = s.sideFor - dt
  if s.sideFor <= 0 then
    s.side, s.sideFor = -s.side, between(Brain.STRAFE_FOR)
  end
  local across = aim + s.side * math.pi / 2
  local mx, my = math.cos(across) * Brain.STRAFE * dt, math.sin(across) * Brain.STRAFE * dt
  if d2 < Brain.NEAR * Brain.NEAR then
    mx, my = mx - math.cos(aim) * Brain.STRAFE * dt, my - math.sin(aim) * Brain.STRAFE * dt
  end
  if not move(s, mx, my) then
    s.side, s.sideFor = -s.side, between(Brain.STRAFE_FOR)
  end
  s.facing = turn(s.facing, aim, Brain.TURN, dt)
end

function Brain:at(x, y, radius)
  local r = Brain.RADIUS + (radius or 0)
  for i, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= r * r then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off `s` (index `i`). Returns true when that put it down.
--- A hit puts it off its throw.
function Brain:hurt(s, i, amount)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if s.state == "windup" then
    enter(s, "hunt")
    s.throwIn = 0.6
  end
  return false
end

function Brain:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

return Brain
