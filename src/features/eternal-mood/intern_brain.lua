-- How the Interns think (docs/eternal-mood.md, "The possessed"): the UAC's
-- unpaid interns, Heck's now like everyone else, the lowest rank there is.
-- No guns and next to no health, but never one at a time: they come in
-- mobs, the way the old zombies did. horde.lua puts them on the map and
-- draws them; this is only their heads, on the host.
--
-- A mob stands about its spot (asleep in the bunks, at lunch in the Mess),
-- swaying, until it wakes (`Brain:wake`, a mob at a time): horde.lua wakes
-- one when a player comes near it or sees it from across the room, or when
-- one of it is hurt. Awake, each goes for the nearest player, finding its
-- way on `nav`: a shamble from afar, a lurch once it is close (LURCH_FROM),
-- and right up against somebody it raises its arms (WINDUP, a tell) and
-- claws. They keep a little apart (SPACE) so a mob comes as a crowd, not a
-- column.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9 -- px
Brain.HEALTH = 20 -- a pistol round or two
Brain.SHAMBLE = 55 -- px/s from afar (a player walks at 45, sprints at 170)
Brain.LURCH = 100 -- px/s once close...
Brain.LURCH_FROM = 200 -- ...this close
Brain.REACH = 24 -- px: this near, it claws
Brain.WINDUP = 0.35 -- seconds its arms go up first
Brain.CLAW_DAMAGE = 7 -- melee: one is nothing, a mob is not
Brain.CLAW_EVERY = 1.0
Brain.SPACE = 22 -- px it keeps from the next one
Brain.HUNTS = 1600 -- px: awake, it goes for the nearest player this near
Brain.TURN = 5
Brain.LOOK_EVERY = 4
Brain.REPATH = 0.7

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function turn(from, to, rate, dt)
  local d = Sight.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- A new brain. `opts`: nav, firstId, and `claw(server, intern, playerId,
--- damage, angle)`.
function Brain.new(opts)
  return setmetatable({
    list = {},
    nav = opts.nav,
    claw = opts.claw,
    nextId = opts.firstId or 1,
    tick = 0,
  }, Brain)
end

--- One of mob `mob` standing at (x, y) facing `facing`, asleep until its mob
--- wakes; `awake` for one that comes in already after somebody (a meeting).
function Brain:add(x, y, facing, mob, awake)
  local s = {
    id = self.nextId,
    x = x,
    y = y,
    facing = facing or random() * 2 * math.pi,
    hp = Brain.HEALTH,
    mob = mob,
    state = awake and "hunt" or "idle", -- idle, hunt, windup
    t = 0,
    target = nil,
    clawIn = 0,
    path = nil,
    step = 1,
    pathIn = random() * Brain.REPATH,
    frozen = 0,
    look = self.nextId,
    stride = 0,
    sway = random() * 6,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Wake mob `mob` (all of it at once). Returns true when any of it was asleep.
function Brain:wake(mob)
  local any = false
  for _, s in ipairs(self.list) do
    if s.mob == mob and s.state == "idle" then
      s.state, s.t, any = "hunt", 0, true
      s.pathIn = random() * 0.6 -- not all on the same tick
    end
  end
  return any
end

local function poseOf(server, who)
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- The nearest player within HUNTS.
local function pick(server, s)
  local best, bestD
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(s.x, s.y, x, y)
      if d2 <= Brain.HUNTS * Brain.HUNTS and (not bestD or d2 < bestD) then
        best, bestD = id, d2
      end
    end
  end
  return best
end

local function fits(x, y)
  local r = Brain.RADIUS
  return not (Sight.blocked(x, y) or Sight.blocked(x - r, y) or Sight.blocked(x + r, y)
    or Sight.blocked(x, y - r) or Sight.blocked(x, y + r))
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

--- A shove away from whoever of the mob is too near, so they spread out.
function Brain:space(s, dt)
  local px, py = 0, 0
  for _, o in ipairs(self.list) do
    if o ~= s then
      local dx, dy = s.x - o.x, s.y - o.y
      local d2 = dx * dx + dy * dy
      if d2 < Brain.SPACE * Brain.SPACE and d2 > 0.01 then
        local d = math.sqrt(d2)
        local k = (Brain.SPACE - d) / Brain.SPACE
        px, py = px + dx / d * k, py + dy / d * k
      end
    end
  end
  if px ~= 0 or py ~= 0 then
    move(s, px * 60 * dt, py * 60 * dt)
  end
end

local function goTo(self, s, x, y, speed, dt)
  local gx, gy = x, y
  if not Sight.clear(s.x, s.y, x, y) and self.nav then
    s.pathIn = s.pathIn - dt
    if not s.path or s.pathIn <= 0 then
      s.path, s.step, s.pathIn = self.nav:path(s.x, s.y, x, y), 1, Brain.REPATH
    end
    local p = s.path and s.path[s.step]
    while p and dist2(s.x, s.y, p.x, p.y) < 16 * 16 do
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

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.clawed = nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  s.clawIn = s.clawIn - dt
  if s.state == "idle" then
    s.sway = s.sway + dt
    s.facing = s.facing + math.sin(s.sway * 0.7) * 0.3 * dt -- swaying where it stands
    return
  end
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 or not s.target then
    s.target = pick(server, s)
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
  end
  if not tx then
    s.target = nil
    if s.state == "windup" then
      s.state, s.t = "hunt", 0
    end
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x)
  local d2 = dist2(s.x, s.y, tx, ty)
  if s.state == "windup" then
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
    if s.t >= Brain.WINDUP then
      if d2 <= (Brain.REACH + Brain.RADIUS + 6) ^ 2 then -- still in reach: the claws land
        self.claw(server, s, s.target, Brain.CLAW_DAMAGE, aim)
      end
      s.clawed = true
      s.clawIn = Brain.CLAW_EVERY
      s.state, s.t = "hunt", 0
    end
    return
  end
  if d2 <= (Brain.REACH + Brain.RADIUS) ^ 2 and s.clawIn <= 0 then
    s.state, s.t = "windup", 0
    return
  end
  if d2 > (Brain.REACH * 0.8) ^ 2 then
    goTo(self, s, tx, ty, d2 <= Brain.LURCH_FROM * Brain.LURCH_FROM and Brain.LURCH or Brain.SHAMBLE, dt)
  else
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
  end
  self:space(s, dt)
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
function Brain:hurt(s, i, amount)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
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
