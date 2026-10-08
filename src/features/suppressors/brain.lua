-- The Suppressors' brain, on the host: where each one goes, what it looks
-- at and when its minigun turns. init.lua owns the wire.
--
-- A Suppressor is a heavy: slow on its feet, slow to turn, and the minigun
-- has to spin up before it fires and vent after it has fired for a while.
-- Each one is always in one of these:
--
--   guard     standing at its post, sweeping a slow cone over the way it
--             watches
--   fight     somebody in its sights: it turns towards them (no quicker
--             than TURN, so running round it works), spins the gun up
--             (SPIN_UP) and, once it turns, fires a round every FIRE_EVERY
--             wherever the barrels point, while it plods closer (to KEEP,
--             never more than LEASH from its post). After BURST seconds of
--             fire the gun vents (VENT): no rounds, the barrels winding
--             down. That is the moment to step out
--   suppress  lost them: it keeps hosing where it last saw them for
--             SUPPRESS seconds, then searches
--   search    walks to where it last saw them and looks round there for
--             SEARCH_TIME, then walks back to its post
--
-- Its shield: `shieldMax` points that soak every hit first. Shock tears it
-- down at SHOCK_SHIELD times the damage. Whatever gets past an empty shield
-- comes off its health. SHIELD_DELAY seconds after the last hit the shield
-- starts to come back, SHIELD_REGEN a second, full in the end.
--
-- It doesn't need to see you to know you are shooting at it: a hit from
-- out of sight turns it the way the round came and sends it to look (no
-- further than its leash), and a shot within HEAR does the same. Too heavy
-- to scare: a panic fart doesn't move it. A freeze holds it like anyone.
--
-- Its eyes are City 17's Combine soldiers' (d-day/sight.lua), its way round
-- walls a walking grid (d-day/nav.lua).

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

-- Tuning --------------------------------------------------------------------

Brain.RANGE = 640 -- px it can see (the Combine's)
Brain.WALK = 42 -- px/s: a heavy plod (a Combine soldier walks 62)
Brain.ADVANCE = 34 -- px/s closing in while it fires
Brain.TURN = 1.5 -- rad/s turning: sprint round it and it can't keep up
Brain.GUARD_SWEEP = math.rad(40) -- its post's scan swings this far either side
Brain.GUARD_SWEEP_TIME = 9 -- seconds for one full swing there and back
Brain.KEEP = 260 -- px; it stops closing in this near
Brain.LEASH = 520 -- px from its post it will go after anybody
Brain.SPIN_UP = 0.9 -- seconds from still barrels to firing
Brain.SPIN_DOWN = 1.6 -- seconds for them to stop again
Brain.FIRE_EVERY = 0.085 -- seconds between rounds once it turns (about 12 a second)
Brain.AIM = math.rad(30) -- it only fires with them (or where it saw them) this near ahead
Brain.SPREAD = 0.05 -- radians of shake, on top of the gun's own
Brain.BURST = 3.2 -- seconds of fire before the gun has to vent...
Brain.VENT = 1.8 -- ...and seconds it vents for
Brain.SUPPRESS = 2.0 -- seconds it keeps firing where it lost somebody
Brain.SEARCH_TIME = 5 -- seconds looking round where it lost them
Brain.MUZZLE = 27 -- px ahead of its middle the rounds leave (render.lua's muzzle, sized up)...
Brain.MUZZLE_SIDE = 6.5 -- ...and this far to its right, where the gun hangs
Brain.HEAR = 480 -- px; a shot this near is heard
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)
Brain.SHOCK_SHIELD = 2 -- shock damage hits the shield this many times over
Brain.SHIELD_DELAY = 5 -- seconds after the last hit before the shield comes back...
Brain.SHIELD_REGEN = 30 -- ...this many points a second

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

--- A set of Suppressors. `opts`: fov, alertFov, aware, health, shield,
--- radius, nav (a walking grid, d-day/nav.lua, or nil to walk straight).
function Brain.new(opts)
  return setmetatable({
    list = {}, nextId = 1, time = 0, ticks = 0,
    fov = opts.fov, alertFov = opts.alertFov or opts.fov, aware = opts.aware or 0,
    health = opts.health, shield = opts.shield, radius = opts.radius, nav = opts.nav,
  }, Brain)
end

--- One standing at (x, y), watching `watch`, armed with `gun` (a guns.lua table).
function Brain:add(x, y, watch, gun)
  local u = {
    id = self.nextId, x = x, y = y, facing = watch, hp = self.health, max = self.health,
    shield = self.shield, shieldMax = self.shield, hitAt = -math.huge,
    post = { x = x, y = y, watch = watch }, mode = "guard", phase = random() * 6.28,
    gun = gun, spin = 0, firing = 0, vent = 0, fireIn = 0, frozen = 0, stuck = 0, fired = false,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = u
  return u
end

--- Is `u` on edge: somebody in its sights, hosing, or out searching?
function Brain.wary(u)
  return u.target ~= nil or u.mode ~= "guard"
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

--- A step along (ux, uy) at `speed`, each axis on its own so a wall is slid along.
function Brain:step(u, ux, uy, speed, dt)
  local px, py = u.x, u.y
  local nx = u.x + ux * speed * dt
  if not self:blocked(nx, u.y) then
    u.x = nx
  end
  local ny = u.y + uy * speed * dt
  if not self:blocked(u.x, ny) then
    u.y = ny
  end
  local moved = dist2(u.x, u.y, px, py) > (speed * dt * 0.3) ^ 2
  u.stuck = moved and 0 or u.stuck + dt
  u.moving = moved
  return moved
end

--- Towards (x, y) at `speed`, round walls on the walking grid. Returns the
--- way it is heading, and true once it is there.
function Brain:goTo(u, x, y, speed, dt)
  local g = u.goal
  if not g or dist2(g.x, g.y, x, y) > 64 * 64 or u.stuck > 0.8 or self.time > g.replanAt then
    local corners = self.nav and self.nav:path(u.x, u.y, x, y)
    g = { x = x, y = y, corners = corners or { { x = x, y = y } }, at = 1, replanAt = self.time + 1.5 }
    u.goal, u.stuck = g, 0
  end
  local c = g.corners[g.at]
  local d = math.sqrt(dist2(u.x, u.y, c.x, c.y))
  if d < 12 then
    if g.at >= #g.corners then
      return u.facing, true
    end
    g.at = g.at + 1
    c = g.corners[g.at]
    d = math.sqrt(dist2(u.x, u.y, c.x, c.y))
  end
  local ux, uy = (c.x - u.x) / math.max(d, 1e-6), (c.y - u.y) / math.max(d, 1e-6)
  self:step(u, ux, uy, math.min(speed, d / dt), dt)
  return math.atan2(uy, ux), false
end

--- Would (x, y) take `u` past its leash?
local function leashed(u, x, y)
  return dist2(x, y, u.post.x, u.post.y) > Brain.LEASH * Brain.LEASH
end

-- Seeing --------------------------------------------------------------------

local function poseOf(server, id)
  local p = id and server.players[id]
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    return x, y
  end
end

function Brain:fovOf(u)
  return Brain.wary(u) and self.alertFov or self.fov
end

function Brain:sees(u, x, y, fov)
  return Sight.canSee(u.x, u.y, u.facing, x, y, Brain.RANGE, fov)
    or (self.aware > 0 and Sight.canSee(u.x, u.y, u.facing, x, y, self.aware, 2 * math.pi))
end

--- Keep its target while it can still see them, or pick up whoever is nearest in view.
function Brain:look(server, u)
  if u.target then
    local x, y = poseOf(server, u.target)
    if x and self:sees(u, x, y, math.max(self:fovOf(u), math.rad(80))) then
      u.lastX, u.lastY = x, y
      return
    end
    u.target = nil -- lost them: hose where they were
    if u.lastX then
      u.mode, u.suppressFor, u.searchFor, u.goal = "suppress", Brain.SUPPRESS, nil, nil
    end
  end
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = self:sees(u, x, y, self:fovOf(u))
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = id, d2
      end
    end
  end
  if best then
    u.target = best
    u.lastX, u.lastY = poseOf(server, best)
    u.mode = "fight"
  end
end

--- Go and look at (x, y), unless it has somebody already (and never past its leash).
function Brain:investigate(u, x, y)
  if u.target or u.mode == "fight" or u.mode == "suppress" then
    return
  end
  if leashed(u, x, y) then
    local a = math.atan2(y - u.post.y, x - u.post.x)
    x, y = u.post.x + math.cos(a) * Brain.LEASH * 0.9, u.post.y + math.sin(a) * Brain.LEASH * 0.9
  end
  u.lastX, u.lastY = x, y
  u.mode, u.searchFor, u.goal = "search", nil, nil
end

--- A shot went off at (x, y): any within earshot with nobody to fight go to look.
function Brain:heard(x, y)
  for _, u in ipairs(self.list) do
    if dist2(u.x, u.y, x, y) <= Brain.HEAR * Brain.HEAR then
      self:investigate(u, x, y)
    end
  end
end

-- The gun ---------------------------------------------------------------------

local function fire(server, u)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local c, s = math.cos(u.facing), math.sin(u.facing)
  local mx = u.x + c * Brain.MUZZLE - s * Brain.MUZZLE_SIDE
  local my = u.y + s * Brain.MUZZLE + c * Brain.MUZZLE_SIDE
  weapons:serverFireFrom(server, 0, mx, my, u.facing + (random() * 2 - 1) * Brain.SPREAD, u.gun)
  u.fired = true
end

--- The barrels, every tick: spinning up while it wants to shoot (and isn't
--- venting), down otherwise; once they turn, a round every FIRE_EVERY at
--- whatever is ahead, if (tx, ty) is near enough ahead and in the gun's reach.
function Brain:gun(server, u, tx, ty, dt)
  u.vent = math.max(0, u.vent - dt)
  local wants = tx ~= nil and u.vent <= 0
  if wants then
    u.spin = math.min(1, u.spin + dt / Brain.SPIN_UP)
  else
    u.spin = math.max(0, u.spin - dt / Brain.SPIN_DOWN)
  end
  if not (wants and u.spin >= 1) then
    u.fireIn = 0
    return
  end
  local reach = u.gun.speed * (u.gun.ttl or 1.2) * 0.9
  local onTarget = dist2(u.x, u.y, tx, ty) <= reach * reach
    and math.abs(Sight.angleDiff(math.atan2(ty - u.y, tx - u.x), u.facing)) <= Brain.AIM
  if not onTarget then
    return -- spun up and waiting for the barrels to come round
  end
  u.firing = u.firing + dt
  u.fireIn = u.fireIn - dt
  while u.fireIn <= 0 do
    fire(server, u)
    u.fireIn = u.fireIn + Brain.FIRE_EVERY
  end
  if u.firing >= Brain.BURST then
    u.firing, u.vent = 0, Brain.VENT -- too hot: it vents
  end
end

-- The modes -------------------------------------------------------------------

function Brain:guard(u, dt)
  local p = u.post
  if dist2(u.x, u.y, p.x, p.y) > 20 * 20 then
    local heading = self:goTo(u, p.x, p.y, Brain.WALK, dt)
    u.facing = turn(u.facing, heading, Brain.TURN, dt)
    return
  end
  u.goal = nil
  local sweep = math.sin(self.time * 2 * math.pi / Brain.GUARD_SWEEP_TIME + u.phase) * Brain.GUARD_SWEEP
  u.facing = turn(u.facing, p.watch + sweep, Brain.TURN * 0.5, dt)
end

--- Plod towards (tx, ty) until KEEP, inside its leash, turning to face them.
function Brain:fight(u, tx, ty, dt)
  u.facing = turn(u.facing, math.atan2(ty - u.y, tx - u.x), Brain.TURN, dt)
  local d = math.sqrt(dist2(u.x, u.y, tx, ty))
  if d > Brain.KEEP then
    local ux, uy = (tx - u.x) / d, (ty - u.y) / d
    if not leashed(u, u.x + ux * 30, u.y + uy * 30) then
      self:step(u, ux, uy, Brain.ADVANCE, dt)
    end
  end
end

function Brain:search(u, dt)
  if not u.searchFor then
    local heading, there = self:goTo(u, u.lastX, u.lastY, Brain.WALK, dt)
    u.facing = turn(u.facing, heading, Brain.TURN, dt)
    if there or u.stuck > 2 then
      u.searchFor, u.lookFrom = Brain.SEARCH_TIME, u.facing
    end
    return
  end
  u.searchFor = u.searchFor - dt
  u.facing = turn(u.facing, u.lookFrom + 1.4 * math.sin(u.searchFor * 1.6), Brain.TURN, dt)
  if u.searchFor <= 0 then
    u.mode, u.searchFor, u.lastX, u.lastY, u.goal = "guard", nil, nil, nil, nil -- back to its post
  end
end

-- Every tick --------------------------------------------------------------------

function Brain:think(server, u, dt)
  u.fired, u.moving = false, false
  if self.time - u.hitAt > Brain.SHIELD_DELAY then
    u.shield = math.min(u.shieldMax, u.shield + Brain.SHIELD_REGEN * dt)
  end
  if u.frozen > 0 then
    u.frozen = u.frozen - dt -- frozen stiff: the barrels run down
    u.spin = math.max(0, u.spin - dt / Brain.SPIN_DOWN)
    return
  end
  if (self.ticks + u.id) % Brain.LOOK_EVERY == 0 then
    self:look(server, u)
  end
  local tx, ty = poseOf(server, u.target)
  if tx then
    u.mode = "fight"
    self:fight(u, tx, ty, dt)
    self:gun(server, u, tx, ty, dt)
  elseif u.mode == "suppress" then
    u.suppressFor = u.suppressFor - dt
    u.facing = turn(u.facing, math.atan2(u.lastY - u.y, u.lastX - u.x), Brain.TURN, dt)
    self:gun(server, u, u.lastX, u.lastY, dt)
    if u.suppressFor <= 0 then
      u.mode, u.searchFor, u.goal = "search", nil, nil
    end
  else
    if u.mode == "search" then
      self:search(u, dt)
    else
      u.mode = "guard"
      self:guard(u, dt)
    end
    self:gun(server, u, nil, nil, dt)
  end
  if not u.fired then
    u.firing = math.max(0, u.firing - dt * 0.5) -- the barrels cool between bursts
  end
end

function Brain:update(server, dt)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  for _, u in ipairs(self.list) do
    self:think(server, u, dt)
  end
end

-- Being hit -------------------------------------------------------------------

--- The one within `radius` of (x, y), and its index.
function Brain:at(x, y, radius)
  for i, u in ipairs(self.list) do
    if dist2(u.x, u.y, x, y) < (radius + self.radius) ^ 2 then
      return u, i
    end
  end
end

--- `amount` of damage type `dtype` on `u` (the i-th), from a round going
--- along `angle`: the shield first, the rest off its health. Returns true
--- if that killed it (it is gone from the list then), and what the shield
--- took. A hit it didn't see coming turns it the way the round came.
function Brain:hurt(u, i, amount, angle, dtype)
  u.hitAt = self.time
  local soaked = 0
  if u.shield > 0 then
    local k = dtype == "shock" and Brain.SHOCK_SHIELD or 1
    soaked = math.min(u.shield, amount * k)
    u.shield = u.shield - soaked
    amount = amount - soaked / k
  end
  u.hp = u.hp - amount
  if u.hp <= 0 then
    table.remove(self.list, i)
    return true, soaked
  end
  if angle and not u.target then
    local fx, fy = u.x - math.cos(angle) * 300, u.y - math.sin(angle) * 300
    u.facing = turn(u.facing, math.atan2(fy - u.y, fx - u.x), math.pi / 2, 1) -- it starts round, heavily
    self:investigate(u, fx, fy)
  end
  return false, soaked
end

function Brain:freeze(x, y, radius, seconds)
  for _, u in ipairs(self.list) do
    if dist2(u.x, u.y, x, y) <= (radius + self.radius) ^ 2 then
      u.frozen = math.max(u.frozen, seconds)
    end
  end
end

return Brain
