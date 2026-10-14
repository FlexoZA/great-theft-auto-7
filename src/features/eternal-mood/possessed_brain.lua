-- How the possessed think (docs/eternal-mood.md, "The possessed"): the
-- UAC's staff, Heck's now, its lowest rank, slow and stupid and still at
-- work. horde.lua puts them on the map and draws them; this is only their
-- heads, on the host.
--
-- Three ranks, one head (`Brain.RANKS`): a staffer shambles at whoever it
-- sees and fires its pistol now and then; a guard holds the doorway it was
-- posted to and steps in to shotgun range; the overtime guy stays by his
-- post, spins his chaingun up when he sees somebody (you hear it) and keeps
-- firing at them while he can see them, sweeping slowly after them.
--
-- Each stands at its post facing `watch`, or walks a patrol (`route`, a
-- loop of { x, y }), until it sees somebody (a cone in front, and a little
-- all round) or a round hits it, when it turns to where that came from.
-- Spotting somebody, it groans for the rest of the horde near it (`call`),
-- who come and look. Lose whoever it had and it goes to where it last saw
-- them, looks about, then shambles back to its post, or to the nearest
-- corner of its patrol and on round it. A guard on patrol keeps to no
-- doorway: its leash is for a post.
--
-- They are Heck's: their rounds carry the horde's name (weapons' `from`), and
-- pass through the rest of it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9 -- px
Brain.MUZZLE = 14 -- px in front of it its rounds leave from
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)
Brain.LOST_AFTER = 2.5 -- seconds without seeing whoever it had before it goes looking
Brain.SEARCH = 6 -- seconds it looks about where it lost them before going back
Brain.CALL = 380 -- px; the horde this near hears it groan, and comes to look
Brain.REPATH = 0.6 -- seconds between new paths
Brain.TURN = 3.5 -- rad/s; slow and stupid

-- Each rank: health, the gun (a base and what is changed on it), how it
-- fires (`aim` seconds on a target before the first round, then `burst`
-- rounds `every` apart and a `pause`, `spinUp` for the chaingun), how far it
-- sees and shoots, the range it closes to, how fast it walks, and how far
-- from its post it will go (`leash`, nil for anywhere).
Brain.RANKS = {
  staffer = {
    health = 40, base = "pistol", gun = { damage = 8, spread = 0.10 },
    aim = 0.7, burst = 1, every = 0.4, pause = { 1.2, 1.9 },
    fov = math.rad(70), aware = 140, range = 520, close = 260, speed = 60, walk = 40,
  },
  guard = {
    health = 60, base = "shotgun", gun = { damage = 7, pellets = 6, spread = 0.15 },
    aim = 0.5, burst = 1, every = 0.4, pause = { 1.4, 1.9 },
    fov = math.rad(80), aware = 160, range = 330, close = 200, speed = 70, walk = 45, leash = 560,
  },
  overtime = {
    health = 100, base = "minigun", gun = { damage = 6, spread = 0.08 },
    aim = 0, spinUp = 0.6, burst = 1, every = 0.125, pause = { 0, 0 },
    fov = math.rad(80), aware = 180, range = 650, close = 420, speed = 35, walk = 30, leash = 260,
    turn = 1.6, -- rad/s: he sweeps after you, he doesn't snap
  },
}

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

local guns = {}
--- Rank `rank`'s gun: its base gun, common, with the rank's numbers on it.
local function gunOf(rank)
  if not guns[rank] then
    local conf = Brain.RANKS[rank]
    local base = Tiers.apply(Guns[conf.base], Tiers.DEFAULT)
    guns[rank] = setmetatable(conf.gun, { __index = base })
  end
  return guns[rank]
end

--- A new brain. `opts`: nav, firstId, from (the horde's name on its rounds),
--- and `call(x, y, tx, ty)`: one of them has spotted somebody at (tx, ty)
--- from (x, y) (horde.lua tells the rest of the horde).
function Brain.new(opts)
  return setmetatable({
    list = {},
    nav = opts.nav,
    from = opts.from,
    call = opts.call,
    nextId = opts.firstId or 1,
    tick = 0,
  }, Brain)
end

--- One of rank `rank` at its post (x, y), facing `watch`; or, given a
--- `route` (a loop of { x, y }), walking it from corner `start` (after
--- `wait` seconds, for one behind another in a file).
function Brain:add(rank, x, y, watch, route, start, wait)
  local conf = Brain.RANKS[rank]
  if route then
    start = start or 1
    x, y = route[start].x, route[start].y
  end
  local s = {
    id = self.nextId,
    rank = rank,
    conf = conf,
    x = x,
    y = y,
    postX = x,
    postY = y,
    watch = watch or 0,
    facing = watch or 0,
    hp = conf.health,
    state = route and "beat" or "post", -- post or beat, hunt, search, back
    route = route,
    leg = route and (start % #route + 1) or nil,
    waitFor = wait or 0,
    t = 0,
    target = nil,
    lostFor = 0,
    seenX = nil,
    seenY = nil,
    aimFor = 0, -- seconds on its target so far
    fireIn = 0,
    left = 0, -- rounds left in this burst
    spun = 0, -- the chaingun's wind-up, seconds
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

--- Where player `who` is, if still about.
local function poseOf(server, who)
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- The nearest player `s` can see, or is close enough to hear.
local function pick(server, s)
  local best, bestD
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, s.conf.range, s.conf.fov)
        or Sight.canSee(s.x, s.y, s.facing, x, y, s.conf.aware, 2 * math.pi)
      if d2 and (not bestD or d2 < bestD) then
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

--- `s` heads for (x, y) at `speed`: straight there when it can see it,
--- else along a path on the walking grid. Returns the distance left.
local function goTo(self, s, x, y, speed, dt)
  local gx, gy = x, y
  if not Sight.clear(s.x, s.y, x, y) and self.nav then
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
    return math.sqrt(dist2(s.x, s.y, x, y))
  end
  s.facing = turn(s.facing, math.atan2(dy, dx), s.conf.turn or Brain.TURN, dt)
  local k = math.min(d, speed * dt) / d
  move(s, dx * k, dy * k)
  return math.sqrt(dist2(s.x, s.y, x, y))
end

local function enter(s, state)
  s.state, s.t = state, 0
end

--- Fire one round (or one shotgun pull) at `aim`.
local function fire(self, server, s, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local mx, my = s.x + math.cos(aim) * Brain.MUZZLE, s.y + math.sin(aim) * Brain.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, gunOf(s.rank), self.from)
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.spinning = nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

--- Something worth a look at (x, y): `s`, if it has nobody, goes to see.
function Brain:alert(s, x, y)
  if not s.target and dist2(s.x, s.y, x, y) > 1 then
    s.seenX, s.seenY = x, y
    enter(s, "search")
  end
end

function Brain:think(server, s, dt)
  local conf = s.conf
  s.t = s.t + dt
  s.fireIn = s.fireIn - dt
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local who = pick(server, s)
    if who and who ~= s.target then
      local fresh = s.target == nil
      s.target, s.lostFor, s.aimFor = who, 0, 0
      if fresh then
        s.spotted = true -- horde.lua: it groans, and says so
        local tx, ty = poseOf(server, who)
        if self.call and tx then
          self.call(s.x, s.y, tx, ty)
        end
      end
    end
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
    local seen = tx and Sight.clear(s.x, s.y, tx, ty) and dist2(s.x, s.y, tx, ty) <= conf.range * conf.range
    if seen then
      s.lostFor, s.seenX, s.seenY = 0, tx, ty
    else
      s.lostFor = s.lostFor + dt
      if not tx or s.lostFor > Brain.LOST_AFTER then
        s.target, s.spun, s.left = nil, 0, 0
        if s.seenX then
          enter(s, "search")
        else
          enter(s, "back")
        end
        return
      end
    end
    if s.state ~= "hunt" then
      enter(s, "hunt")
    end
    self:fight(server, s, tx, ty, seen, dt)
    return
  end
  if s.state == "search" then
    -- To where it last saw them, then look about.
    local left = goTo(self, s, s.seenX, s.seenY, conf.walk, dt)
    if left < 30 then
      s.facing = s.facing + dt * 1.2
    end
    if s.t > Brain.SEARCH then
      enter(s, "back")
    end
  elseif s.state == "back" then
    if s.route then -- to the nearest corner of its patrol, and on from there
      if not s.backTo then
        local best, bestD
        for i, p in ipairs(s.route) do
          local d2 = dist2(s.x, s.y, p.x, p.y)
          if not bestD or d2 < bestD then
            best, bestD = i, d2
          end
        end
        s.backTo = best
      end
      local p = s.route[s.backTo]
      if goTo(self, s, p.x, p.y, conf.walk, dt) < 24 then
        s.leg, s.backTo = s.backTo % #s.route + 1, nil
        enter(s, "beat")
      end
    elseif goTo(self, s, s.postX, s.postY, conf.walk, dt) < 12 then
      enter(s, "post")
    end
  elseif s.state == "beat" then
    if s.waitFor > 0 then
      s.waitFor = s.waitFor - dt
      return
    end
    local p = s.route[s.leg]
    if goTo(self, s, p.x, p.y, conf.walk, dt) < 24 then
      s.leg = s.leg % #s.route + 1
    end
  else
    s.facing = turn(s.facing, s.watch, Brain.TURN, dt)
  end
end

--- `s` has somebody at (tx, ty), seen or not: close in, aim, fire.
function Brain:fight(server, s, tx, ty, seen, dt)
  local conf = s.conf
  local aim = math.atan2(ty - s.y, tx - s.x)
  local d2 = dist2(s.x, s.y, tx, ty)
  local leashed = conf.leash and not s.route and dist2(s.x, s.y, s.postX, s.postY) > conf.leash * conf.leash
  if not seen or d2 > conf.close * conf.close then
    if leashed then
      goTo(self, s, s.postX, s.postY, conf.walk, dt)
    elseif not (s.rank == "overtime" and seen) then -- the overtime guy fires as he goes
      goTo(self, s, seen and tx or s.seenX, seen and ty or s.seenY, conf.speed, dt)
    end
  end
  if not seen then
    s.aimFor, s.spun = 0, math.max(0, s.spun - dt)
    return
  end
  s.facing = turn(s.facing, aim, conf.turn or Brain.TURN, dt)
  if math.abs(Sight.angleDiff(aim, s.facing)) > 0.35 then
    return -- not round to them yet
  end
  if conf.spinUp then
    if s.spun < conf.spinUp then
      s.spinning = s.spun == 0 -- horde.lua: the wind-up's sound, once
      s.spun = s.spun + dt
      if s.rank == "overtime" and d2 > conf.close * conf.close and not leashed then
        goTo(self, s, tx, ty, conf.speed, dt)
      end
      return
    end
  else
    s.aimFor = s.aimFor + dt
    if s.aimFor < conf.aim then
      return
    end
  end
  if s.fireIn > 0 then
    return
  end
  fire(self, server, s, s.facing)
  s.left = s.left - 1
  if s.left > 0 then
    s.fireIn = conf.every
  else
    s.left = conf.burst
    s.fireIn = conf.every + between(conf.pause)
  end
end

--- The one whose body covers (x, y) (within `radius` more), and its index.
function Brain:at(x, y, radius)
  local r = Brain.RADIUS + (radius or 0)
  for i, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= r * r then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off `s` (index `i`). Returns true when that put it down
--- (and it is off the list). Hit from out of sight, it turns that way.
function Brain:hurt(s, i, amount, angle)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if angle and not s.target then
    s.facing = angle + math.pi
    self:alert(s, s.x - math.cos(angle) * 200, s.y - math.sin(angle) * 200)
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
