-- How the Static's brutes think (docs/cyber-feud.md, "The Static"): a
-- small Kilowatt, huge, one giant chrome arm and a cyan reactor in his
-- chest. brutes.lua puts them on the map and draws them; this is only
-- their heads, on the host.
--
-- A brute walks his beat (a loop of { x, y }) until he sees or hears
-- somebody: a player, or one of his `rivals` (another brain's or troop's
-- `list`). He goes for the nearest, slowly (soaking fire for the pack),
-- finding his way on `nav`. From within CHARGE_FROM, with a clear line, he
-- braces for BRACE seconds, set on where they stand right then, and
-- charges a long way down that line: whoever he runs through takes the
-- arm (`hit`, impact). If the charge ends against a wall he is dazed for a
-- moment. Right up against somebody he winds up and punches.
--
-- His arm is a breach target (`breach`): for HAYWIRE seconds it locks up
-- and he spins on the spot, swinging at whatever is next to him, his own
-- side as often as not (`swing(server, brute, x, y, angle)`, at a point
-- just past his reach).
--
-- A `calm` brain sees nobody, until brutes.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 15 -- px; huge
Brain.RANGE = 520 -- px he can see
Brain.WALK = 45 -- px/s on his beat
Brain.RUN = 85 -- px/s going in: slow
Brain.TURN = 2.6 -- rad/s
Brain.CHARGE_FROM = 280 -- px from his target he braces to charge...
Brain.CHARGE_MIN = 70 -- ...but not nearer than this (he just punches)
Brain.BRACE = 0.7 -- seconds braced, the line set, before he goes
Brain.CHARGE_SPEED = 400 -- px/s
Brain.CHARGE_TIME = 0.75 -- seconds a charge lasts: about 300 px
Brain.CHARGE_EVERY = 4 -- seconds from one charge to the next
Brain.CHARGE_DAMAGE = 34
Brain.DAZED = 1.2 -- seconds standing after he hits a wall
Brain.PUNCH_REACH = 36 -- px; this near, he punches
Brain.PUNCH_WIND = 0.35 -- seconds winding up a punch
Brain.PUNCH_EVERY = 1.3
Brain.PUNCH_DAMAGE = 24
Brain.HIT_REACH = 20 -- px; how near his line a charge hits somebody
Brain.HAYWIRE = 4 -- seconds a breached arm swings at everything
Brain.SPIN = 5 -- rad/s he spins, breached (so a swing lands somewhere new each time round)
Brain.SWING_EVERY = 0.45 -- seconds between haywire swings
Brain.LOST_AFTER = 4
Brain.REPATH = 0.6
Brain.LOOK_EVERY = 3

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

--- A new brain. `opts`: fov, aware (px he hears all round), health, nav,
--- firstId, calm, `hit(server, brute, who, damage, angle)` (the arm on
--- `who`: a player id or a rival's soldier) and `swing(server, brute, x,
--- y, angle)` (a haywire swing through (x, y)).
function Brain.new(opts)
  return setmetatable({
    list = {},
    rivals = {},
    fov = opts.fov,
    aware = opts.aware,
    health = opts.health,
    nav = opts.nav,
    hit = opts.hit,
    swing = opts.swing,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
  }, Brain)
end

--- A brute walking `route` (a loop of { x, y }) from corner `start`.
function Brain:add(route, start)
  local p = route[start]
  local s = {
    id = self.nextId,
    x = p.x,
    y = p.y,
    route = route,
    leg = start % #route + 1,
    facing = 0,
    hp = self.health,
    state = "beat", -- beat, run, brace, charge, dazed, wind, haywire
    t = 0,
    target = nil,
    lostFor = 0,
    chargeIn = 1,
    punchIn = 0,
    swingIn = 0,
    path = nil,
    step = 1,
    pathIn = 0,
    frozen = 0,
    look = self.nextId,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

local function poseOf(server, who)
  if type(who) == "table" then
    if who.hp > 0 then
      return who.x, who.y
    end
    return nil
  end
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- Everyone he could go for, as { who, x, y }.
local function everyone(self, server)
  local out = {}
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      out[#out + 1] = { who = id, x = x, y = y }
    end
  end
  for _, rival in ipairs(self.rivals) do
    for _, r in ipairs(rival.list) do
      if r.hp > 0 then
        out[#out + 1] = { who = r, x = r.x, y = r.y }
      end
    end
  end
  return out
end

--- The nearest `s` can see or hear, if anyone.
function Brain:pick(server, s)
  if self.calm then
    return nil
  end
  local best, bestD2
  for _, c in ipairs(everyone(self, server)) do
    local d2 = Sight.canSee(s.x, s.y, s.facing, c.x, c.y, Brain.RANGE, self.fov)
      or Sight.canSee(s.x, s.y, s.facing, c.x, c.y, self.aware, 2 * math.pi)
    if d2 and (not bestD2 or d2 < bestD2) then
      best, bestD2 = c.who, d2
    end
  end
  return best
end

local function fits(x, y)
  local r = Brain.RADIUS
  return not (Sight.blocked(x, y) or Sight.blocked(x - r, y) or Sight.blocked(x + r, y)
    or Sight.blocked(x, y - r) or Sight.blocked(x, y + r))
end

--- Move `s` by (mx, my), sliding along walls. Returns false when it went nowhere.
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
  return true
end

--- `s` heads for (x, y) at `speed`: straight there when he can see it,
--- else along a path on the walking grid.
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
    s.hitNow = nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

local function enter(s, state)
  s.state, s.t = state, 0
end

--- `s`'s arm is breached: it swings at everything for HAYWIRE seconds.
function Brain:breach(s)
  enter(s, "haywire")
  s.swingIn = 0.2
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  s.chargeIn = s.chargeIn - dt
  s.punchIn = s.punchIn - dt
  if s.state == "haywire" then
    s.facing = s.facing + Brain.SPIN * dt
    s.swingIn = s.swingIn - dt
    if s.swingIn <= 0 then
      s.swingIn = Brain.SWING_EVERY
      local reach = Brain.RADIUS + Brain.PUNCH_REACH
      self.swing(server, s, s.x + math.cos(s.facing) * reach, s.y + math.sin(s.facing) * reach, s.facing)
      s.hitNow = true
    end
    if s.t >= Brain.HAYWIRE then
      enter(s, s.target and "run" or "beat")
    end
    return
  elseif s.state == "brace" then
    if s.t >= Brain.BRACE then
      enter(s, "charge")
      s.struck = {}
    end
    return
  elseif s.state == "charge" then
    local step = Brain.CHARGE_SPEED * dt
    local ok = move(s, math.cos(s.chargeAngle) * step, math.sin(s.chargeAngle) * step)
    for _, c in ipairs(everyone(self, server)) do
      if not s.struck[c.who] and dist2(s.x, s.y, c.x, c.y) <= (Brain.HIT_REACH + Brain.RADIUS) ^ 2 then
        s.struck[c.who] = true
        self.hit(server, s, c.who, Brain.CHARGE_DAMAGE, s.chargeAngle)
        s.hitNow = true
      end
    end
    if not ok then
      enter(s, "dazed") -- into the wall
      s.chargeIn = Brain.CHARGE_EVERY
    elseif s.t >= Brain.CHARGE_TIME then
      enter(s, "run")
      s.chargeIn = Brain.CHARGE_EVERY
    end
    return
  elseif s.state == "dazed" then
    if s.t >= Brain.DAZED then
      enter(s, s.target and "run" or "beat")
    end
    return
  elseif s.state == "wind" then
    if s.t >= Brain.PUNCH_WIND then
      local tx, ty = poseOf(server, s.target)
      if tx and dist2(s.x, s.y, tx, ty) <= (Brain.PUNCH_REACH + Brain.RADIUS) ^ 2 then
        self.hit(server, s, s.target, Brain.PUNCH_DAMAGE, s.facing)
      end
      s.hitNow = true -- (a swing and a miss sounds too)
      s.punchIn = Brain.PUNCH_EVERY
      enter(s, "run")
    end
    return
  end
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local who = self:pick(server, s)
    if who then
      s.target, s.lostFor = who, 0
    end
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
    if tx and not Sight.clear(s.x, s.y, tx, ty) then
      s.lostFor = s.lostFor + dt
      if s.lostFor > Brain.LOST_AFTER then
        tx = nil
      end
    else
      s.lostFor = 0
    end
    if not tx then
      s.target, s.path = nil, nil
      enter(s, "beat")
    end
  end
  if tx then
    if s.state ~= "run" then
      enter(s, "run")
    end
    local d2 = dist2(s.x, s.y, tx, ty)
    local seen = Sight.clear(s.x, s.y, tx, ty)
    local toThem = math.atan2(ty - s.y, tx - s.x)
    if seen and d2 <= (Brain.PUNCH_REACH + Brain.RADIUS) ^ 2 then
      s.facing = turn(s.facing, toThem, Brain.TURN * 2, dt)
      if s.punchIn <= 0 then
        enter(s, "wind")
      end
    elseif seen and s.chargeIn <= 0 and d2 <= Brain.CHARGE_FROM ^ 2 and d2 >= Brain.CHARGE_MIN ^ 2 then
      s.chargeAngle = toThem -- set now: get off this line
      s.facing = toThem
      enter(s, "brace")
    else
      goTo(self, s, tx, ty, Brain.RUN, dt)
    end
    return
  end
  local to = s.route[s.leg]
  if dist2(s.x, s.y, to.x, to.y) < 28 * 28 then
    s.leg = s.leg % #s.route + 1
    to = s.route[s.leg]
  end
  goTo(self, s, to.x, to.y, Brain.WALK, dt)
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

--- Take `amount` off `s` (index `i`). Returns true when that put him down
--- (and he is off the list). Hit from out of sight, he turns that way.
function Brain:hurt(s, i, amount, angle)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if angle and not s.target and s.state == "beat" then
    s.facing = angle + math.pi
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
