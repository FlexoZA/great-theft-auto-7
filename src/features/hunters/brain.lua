-- The Hunters' brain, on the host: where each one goes, what it looks at,
-- when it shoots and when it throws itself aside. init.lua owns the wire.
--
-- Each one is always in one of these, and the later ones cut in on the
-- earlier:
--
--   patrol   walking its beat (a loop of corners), glancing either side
--   search   lost whoever it was fighting: goes to where it last saw them
--            and looks round there, then back to its beat
--   fight    somebody in its sights: it keeps them at range (KEEP_MIN to
--            KEEP_MAX), closing in when they are far, backing off when
--            they rush it, strafing side to side in between, and fires
--            uzi bursts at them whenever it has a clear line
--   heal     badly hurt (under HEAL_BELOW of its health) with a medkit or
--            an energy drink lying within HEAL_RANGE: it breaks off and runs
--            for it, takes it, and goes back to whatever it was doing
--   dodge    something is about to hit it (Brain.threatLine, a round on
--            its way; Brain.threatArea, an ability about to land): a quick
--            dash out of the way, then on with the rest. It can't dodge
--            again straight away (DODGE_COOL)
--
-- Its eyes are City 17's Combine soldiers': a cone of sight (wider while
-- it is on edge, `alertFov`), walls in the way, and anyone within `aware`
-- whichever way it faces (d-day/sight.lua). It finds its way round walls
-- with a walking grid (d-day/nav.lua).

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

-- Tuning --------------------------------------------------------------------

Brain.RANGE = 640 -- px they can see (the Combine's)
Brain.PATROL = 85 -- px/s walking a beat
Brain.RUN = 150 -- px/s closing in, backing off, searching, going for a pickup
Brain.STRAFE = 115 -- px/s side to side while fighting
Brain.TURN = 7 -- rad/s turning to face where it looks
Brain.KEEP_MIN = 260 -- px; nearer than this and it backs off
Brain.KEEP_MAX = 440 -- px; further than this and it closes in
Brain.STRAFE_TIME = { 0.9, 2.2 } -- seconds before it changes which way it strafes
Brain.REACT = 0.45 -- seconds from spotting someone to the first round
Brain.AIM = math.rad(12) -- it only fires with the target this near straight ahead
Brain.SPREAD = 0.05 -- radians of aim error, on top of the gun's own
Brain.MUZZLE = 24 -- px from the middle a round leaves, off one pod or the other
Brain.POD = 5 -- px either side of the middle the pods sit
Brain.LEASH = 1100 -- px from where a fight started that it will follow anyone
Brain.SEARCH_TIME = 4 -- seconds looking round where it lost them
Brain.DODGE_SPEED = 430 -- px/s in a dodge
Brain.DODGE_TIME = 0.22 -- seconds a dodge lasts
Brain.DODGE_COOL = 1.1 -- seconds before it can dodge again
Brain.DODGE_WARN = 0.45 -- seconds' warning it needs of a round to get out of its way
Brain.HEAL_BELOW = 0.45 -- share of its health under which it goes for a pickup
Brain.HEAL_RANGE = 700 -- px; how far it will go for one
Brain.HASTE = 1.3 -- how much quicker it moves while an energy drink lasts
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)

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

--- A set of hunters. `opts`: fov, alertFov, aware, health, radius, nav (a
--- walking grid, d-day/nav.lua, or nil to walk straight), and for healing:
---   find(x, y, range)       the nearest pickup to heal with, { x, y, ... }, or nil
---   there(pickup)           is it still lying there?
---   take(server, pickup, h) take it: returns the hp it gives and how many
---                           seconds of haste (quicker on its feet)
function Brain.new(opts)
  return setmetatable({
    list = {}, nextId = 1, time = 0, ticks = 0,
    fov = opts.fov, alertFov = opts.alertFov or opts.fov, aware = opts.aware or 0,
    health = opts.health, radius = opts.radius, nav = opts.nav,
    find = opts.find, there = opts.there, take = opts.take,
  }, Brain)
end

--- One on `route` (a loop of { x, y }), standing at corner `start`, armed
--- with `arms` ({ gun, burst, pause, reach }).
function Brain:add(route, start, arms)
  local p = route[start]
  local h = {
    id = self.nextId, x = p.x, y = p.y, facing = 0, hp = self.health, max = self.health,
    route = route, leg = start % #route + 1, mode = "patrol", phase = random() * 6.28,
    arms = arms, burstLeft = arms.burst, fireIn = 0, pod = 1, side = random() < 0.5 and -1 or 1,
    strafeIn = between(Brain.STRAFE_TIME), dodgeCool = 0, frozen = 0, stuck = 0, fired = false, haste = 0,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = h
  return h
end

--- Is `h` on edge: somebody in its sights, or out searching?
function Brain.wary(h)
  return h.target ~= nil or h.mode == "search"
end

-- Moving --------------------------------------------------------------------

function Brain:blocked(x, y)
  local r = self.radius
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if f:blocksPoint(x, y) or f:blocksPoint(x - r, y) or f:blocksPoint(x + r, y) or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r) then
        return true
      end
    end
  end
  return false
end

--- A step along (ux, uy) at `speed`, each axis on its own so a wall is
--- slid along. Returns false if it got nowhere.
function Brain:step(h, ux, uy, speed, dt)
  if h.haste > 0 then
    speed = speed * Brain.HASTE
  end
  local px, py = h.x, h.y
  local nx = h.x + ux * speed * dt
  if not self:blocked(nx, h.y) then
    h.x = nx
  end
  local ny = h.y + uy * speed * dt
  if not self:blocked(h.x, ny) then
    h.y = ny
  end
  local moved = dist2(h.x, h.y, px, py) > (speed * dt * 0.3) ^ 2
  h.stuck = moved and 0 or h.stuck + dt
  return moved
end

--- Towards (x, y) at `speed`, round walls on the walking grid. Returns the
--- way it is heading, and true once it is there.
function Brain:goTo(h, x, y, speed, dt)
  local g = h.goal
  if not g or dist2(g.x, g.y, x, y) > 64 * 64 or h.stuck > 0.8 or self.time > g.replanAt then
    local corners = self.nav and self.nav:path(h.x, h.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = self.time + 1.5 }
    h.goal, h.stuck = g, 0
  end
  local c = g.corners[g.at]
  local d = math.sqrt(dist2(h.x, h.y, c.x, c.y))
  if d < 14 then
    if g.at >= #g.corners then
      return h.facing, true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
    d = math.sqrt(dist2(h.x, h.y, c.x, c.y))
  end
  local ux, uy = (c.x - h.x) / math.max(d, 1e-6), (c.y - h.y) / math.max(d, 1e-6)
  self:step(h, ux, uy, math.min(speed, d / dt), dt)
  return math.atan2(uy, ux), false
end

-- Seeing --------------------------------------------------------------------

local function poseOf(server, id)
  local p = id and server.players[id]
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    return x, y
  end
end

--- How wide `h` sees now.
function Brain:fovOf(h)
  return Brain.wary(h) and self.alertFov or self.fov
end

--- Can `h` see (x, y): in its cone, or close enough to notice any way it faces?
function Brain:sees(h, x, y, fov)
  return Sight.canSee(h.x, h.y, h.facing, x, y, Brain.RANGE, fov)
    or (self.aware > 0 and Sight.canSee(h.x, h.y, h.facing, x, y, self.aware, 2 * math.pi))
end

--- Keep its target while it can still see them, or pick up whoever is nearest in view.
function Brain:look(server, h)
  if h.target then
    local x, y = poseOf(server, h.target)
    if x and self:sees(h, x, y, math.max(self:fovOf(h), math.rad(90))) then
      h.lastX, h.lastY = x, y
      return
    end
    h.target = nil -- lost them
    if h.lastX and h.mode ~= "heal" then -- healing comes first; it looks for them after
      h.mode, h.searchFor, h.goal = "search", nil, nil
    end
  end
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = self:sees(h, x, y, self:fovOf(h))
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = id, d2
      end
    end
  end
  if best then
    h.target = best
    h.lastX, h.lastY = poseOf(server, best)
    h.fireIn = math.max(h.fireIn, Brain.REACT)
    if h.mode ~= "heal" then
      h.mode = "fight"
    end
    h.home = h.home or { x = h.x, y = h.y }
  end
end

-- Shooting --------------------------------------------------------------------

local function fire(server, h, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  h.pod = -h.pod -- the other pod each round
  local c, s = math.cos(h.facing), math.sin(h.facing)
  local mx = h.x + c * Brain.MUZZLE - s * Brain.POD * h.pod
  local my = h.y + s * Brain.MUZZLE + c * Brain.POD * h.pod
  local aim = math.atan2(ty - my, tx - mx) + (random() * 2 - 1) * Brain.SPREAD
  weapons:serverFireFrom(server, 0, mx, my, aim, h.arms.gun)
  h.fired = true
end

--- Its trigger, while it has somebody at (tx, ty) in its sights.
function Brain:shoot(server, h, tx, ty, dt)
  h.fireIn = h.fireIn - dt
  if h.fireIn > 0 then
    return
  end
  local arms = h.arms
  if dist2(h.x, h.y, tx, ty) > arms.reach * arms.reach then
    return
  end
  if math.abs(Sight.angleDiff(math.atan2(ty - h.y, tx - h.x), h.facing)) > Brain.AIM then
    return
  end
  if not Sight.clear(h.x, h.y, tx, ty) then
    return
  end
  fire(server, h, tx, ty)
  h.burstLeft = h.burstLeft - 1
  if h.burstLeft > 0 then
    h.fireIn = arms.gun.cooldown
  else
    h.burstLeft = arms.burst
    h.fireIn = arms.pause * (0.85 + random() * 0.3)
  end
end

-- The modes -------------------------------------------------------------------

function Brain:patrol(h, dt)
  local to = h.route[h.leg]
  local heading, there = self:goTo(h, to.x, to.y, Brain.PATROL, dt)
  if there then
    h.leg = h.leg % #h.route + 1
    h.goal = nil
  end
  h.facing = turn(h.facing, heading + 0.35 * math.sin(self.time * 1.4 + h.phase), Brain.TURN * 0.5, dt)
  h.moving = true
end

function Brain:search(h, dt)
  if not h.searchFor then
    local heading, there = self:goTo(h, h.lastX, h.lastY, Brain.RUN, dt)
    h.facing = turn(h.facing, heading, Brain.TURN, dt)
    h.moving = true
    if there or h.stuck > 2 then
      h.searchFor, h.lookFrom = Brain.SEARCH_TIME, h.facing
    end
    return
  end
  -- There: stand and look round, then back to the beat.
  h.moving = false
  h.searchFor = h.searchFor - dt
  h.facing = turn(h.facing, h.lookFrom + 1.6 * math.sin(h.searchFor * 2.4), Brain.TURN * 0.6, dt)
  if h.searchFor <= 0 then
    h.mode, h.searchFor, h.lastX, h.lastY, h.home, h.goal = "patrol", nil, nil, nil, nil, nil
  end
end

--- Keep `tx, ty` at range: close in, back off or strafe across, facing them throughout.
function Brain:fight(server, h, tx, ty, dt)
  local dx, dy = tx - h.x, ty - h.y
  local d = math.sqrt(dx * dx + dy * dy)
  local ux, uy = dx / math.max(d, 1e-6), dy / math.max(d, 1e-6)
  h.facing = turn(h.facing, math.atan2(dy, dx), Brain.TURN, dt)
  h.strafeIn = h.strafeIn - dt
  if h.strafeIn <= 0 or h.stuck > 0.3 then
    h.side, h.strafeIn, h.stuck = -h.side, between(Brain.STRAFE_TIME), 0
  end
  local mx, my, speed = -uy * h.side, ux * h.side, Brain.STRAFE -- across, by default
  if d > Brain.KEEP_MAX then
    mx, my, speed = ux * 0.8 - uy * h.side * 0.6, uy * 0.8 + ux * h.side * 0.6, Brain.RUN -- in, weaving
  elseif d < Brain.KEEP_MIN then
    mx, my, speed = -ux * 0.85 - uy * h.side * 0.5, -uy * 0.85 + ux * h.side * 0.5, Brain.RUN -- back off
  end
  local len = math.sqrt(mx * mx + my * my)
  mx, my = mx / len, my / len
  local home = h.home
  if home and dist2(h.x + mx * 40, h.y + my * 40, home.x, home.y) > Brain.LEASH * Brain.LEASH then
    mx, my = -uy * h.side, ux * h.side -- at the end of its leash: only across
  end
  self:step(h, mx, my, speed, dt)
  h.moving = true
  self:shoot(server, h, tx, ty, dt)
end

--- What `h` goes back to once it has healed: the fight, looking for whoever
--- it lost, or its beat.
function Brain.after(h)
  if h.target then
    return "fight"
  end
  h.searchFor, h.goal = nil, nil
  return h.lastX and "search" or "patrol"
end

--- After the pickup it chose; back to what it was doing once it has it,
--- or if somebody else got there first.
function Brain:heal(server, h, dt)
  local p = h.pickup
  if not p or (self.there and not self.there(p)) then
    h.pickup, h.mode = nil, Brain.after(h)
    return
  end
  local heading, there = self:goTo(h, p.x, p.y, Brain.RUN, dt)
  h.facing = turn(h.facing, heading, Brain.TURN, dt)
  h.moving = true
  if there or dist2(h.x, h.y, p.x, p.y) < 24 * 24 then
    local hp, haste = 0, 0
    if self.take then
      hp, haste = self.take(server, p, h)
    end
    h.hp = math.min(h.max, h.hp + (hp or 0))
    h.haste = math.max(h.haste, haste or 0)
    h.pickup, h.goal = nil, nil
    h.mode = Brain.after(h)
  end
end

--- Should `h` go for a pickup now? Picks the nearest one in reach.
function Brain:wantsHeal(h)
  if h.mode == "heal" or h.hp >= h.max * Brain.HEAL_BELOW or not self.find then
    return false
  end
  if (h.healCheck or 0) > self.time then
    return false
  end
  h.healCheck = self.time + 1 -- not every tick
  local p = self.find(h.x, h.y, Brain.HEAL_RANGE)
  if p then
    h.pickup, h.mode, h.goal = p, "heal", nil
    return true
  end
  return false
end

-- Dodging ---------------------------------------------------------------------

--- `h` throws itself along (ux, uy), if it can dodge now: far enough to
--- clear `far` px if given, otherwise a quick sidestep.
function Brain:dodge(h, ux, uy, far)
  if h.dodging or h.dodgeCool > 0 or h.frozen > 0 then
    return false
  end
  local left = math.max(Brain.DODGE_TIME, (far or 0) / Brain.DODGE_SPEED)
  h.dodging = { x = ux, y = uy, left = left }
  h.dodgeCool = Brain.DODGE_COOL
  return true
end

--- A round on its way from (x, y) along (ux, uy) at `speed` px/s, `reach`
--- px at most, hurting `width` px either side of its line (a rocket's
--- blast is wide): anyone it will pass close enough to, soon enough,
--- dashes aside, away from its line.
function Brain:threatLine(x, y, ux, uy, speed, reach, width)
  for _, h in ipairs(self.list) do
    local rx, ry = h.x - x, h.y - y
    local along = rx * ux + ry * uy
    if along > 0 and along < reach and along / speed < Brain.DODGE_WARN then
      local across = rx * -uy + ry * ux
      if math.abs(across) < self.radius + (width or 0) + 10 then
        local side = across >= 0 and 1 or -1
        self:dodge(h, -uy * side, ux * side)
      end
    end
  end
end

--- Something is about to land on everything within `radius` of (x, y):
--- anyone there dashes straight away from it.
function Brain:threatArea(x, y, radius)
  for _, h in ipairs(self.list) do
    local d2 = dist2(h.x, h.y, x, y)
    if d2 < (radius + self.radius + 30) ^ 2 then
      local d = math.sqrt(d2)
      local ux, uy
      if d < 1 then
        local a = random() * 2 * math.pi
        ux, uy = math.cos(a), math.sin(a)
      else
        ux, uy = (h.x - x) / d, (h.y - y) / d
      end
      self:dodge(h, ux, uy, radius + self.radius + 20 - d)
    end
  end
end

-- Every tick --------------------------------------------------------------------

function Brain:think(server, h, dt)
  h.fired, h.moving = false, false
  h.dodgeCool = math.max(0, h.dodgeCool - dt)
  h.haste = math.max(0, h.haste - dt)
  if h.frozen > 0 then
    h.frozen = h.frozen - dt -- frozen stiff: nothing
    return
  end
  if h.panic then
    h.panic.left = h.panic.left - dt
    local a = math.atan2(h.y - h.panic.y, h.x - h.panic.x)
    self:step(h, math.cos(a), math.sin(a), Brain.RUN, dt)
    h.facing, h.moving = a, true
    if h.panic.left <= 0 then
      h.panic = nil
    end
    return
  end
  if h.dodging then
    local dg = h.dodging
    dg.left = dg.left - dt
    self:step(h, dg.x, dg.y, Brain.DODGE_SPEED, dt)
    h.moving = true
    if dg.left <= 0 then
      h.dodging = nil
    end
    return
  end
  if (self.ticks + h.id) % Brain.LOOK_EVERY == 0 then
    self:look(server, h)
  end
  self:wantsHeal(h)
  if h.mode == "heal" then
    self:heal(server, h, dt)
    local tx, ty = poseOf(server, h.target)
    if tx and h.mode == "heal" then
      self:shoot(server, h, tx, ty, dt) -- if it happens to face them on the way
    end
    return
  end
  local tx, ty = poseOf(server, h.target)
  if tx then
    h.mode = "fight"
    self:fight(server, h, tx, ty, dt)
  elseif h.mode == "search" then
    self:search(h, dt)
  else
    h.mode = "patrol"
    self:patrol(h, dt)
  end
end

function Brain:update(server, dt)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  for _, h in ipairs(self.list) do
    self:think(server, h, dt)
  end
end

-- Being hit -------------------------------------------------------------------

--- The hunter within `radius` of (x, y), and its index.
function Brain:at(x, y, radius)
  for i, h in ipairs(self.list) do
    if dist2(h.x, h.y, x, y) < (radius + self.radius) ^ 2 then
      return h, i
    end
  end
end

--- Take `amount` off `h` (the i-th). True if that killed it; it is gone
--- from the list then. Hit from somewhere it can't see, it turns and goes
--- that way to look.
function Brain:hurt(h, i, amount, angle)
  h.hp = h.hp - amount
  if h.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if angle and not h.target and h.mode ~= "heal" then
    h.facing = angle + math.pi
    h.lastX, h.lastY = h.x - math.cos(angle) * 300, h.y - math.sin(angle) * 300
    h.mode, h.searchFor, h.goal = "search", nil, nil
    h.home = h.home or { x = h.x, y = h.y }
  end
  return false
end

function Brain:freeze(x, y, radius, seconds)
  for _, h in ipairs(self.list) do
    if dist2(h.x, h.y, x, y) <= (radius + self.radius) ^ 2 then
      h.frozen = math.max(h.frozen, seconds)
      h.dodging = nil
    end
  end
end

function Brain:scare(x, y, radius, seconds)
  for _, h in ipairs(self.list) do
    if dist2(h.x, h.y, x, y) <= (radius + self.radius) ^ 2 then
      h.panic = { x = x, y = y, left = seconds }
    end
  end
end

return Brain
