-- How the Static's rippers think (docs/cyber-feud.md, "The Static"): lean,
-- fast, two chrome blades out from the forearms. rippers.lua puts them on
-- the map and draws them; this is only their heads, on the host.
--
-- A ripper walks its beat (a loop of { x, y }) until it sees or hears
-- somebody: a player, or one of its `rivals` (another brain's or troop's
-- `list`, the way a-man/combine.lua's rivals work). It goes for whoever is
-- most alone: the nearest, counting anyone else within CROWD of them as
-- that much further off. It runs in, finding its way round the stalls on
-- `nav` (d-day/nav.lua), and from within LUNGE_FROM it crouches for
-- CROUCH seconds, set on where its target stands at that moment, then
-- lunges a long way down that line at LUNGE_SPEED. The line is fixed once
-- it crouches, so stepping sideways dodges it. Whoever it passes through
-- on the way is cut once (`hit`); after it catches its breath (RECOVER)
-- and can lunge again after LUNGE_EVERY. Right up against somebody it
-- slashes a couple of times, then backs off to lunge again: hit and run.
-- It goes back to its beat once it has lost them.
--
-- A `calm` brain sees nobody, until rippers.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 8 -- px; lean
Brain.RANGE = 600 -- px it can see
Brain.WALK = 60 -- px/s on its beat
Brain.RUN = 150 -- px/s going in (a player sprints at 170)
Brain.TURN = 6 -- rad/s
Brain.CROWD = 260 -- px; anyone else this near somebody makes them less alone...
Brain.CROWD_COST = 300 -- ...and counts as this much further off
Brain.LUNGE_FROM = 200 -- px from its target it crouches to lunge
Brain.CROUCH = 0.5 -- seconds crouched, the line set, before the lunge
Brain.LUNGE_SPEED = 560 -- px/s
Brain.LUNGE_TIME = 0.4 -- seconds the lunge lasts: about 220 px
Brain.LUNGE_EVERY = 1.8 -- seconds from one lunge to the next
Brain.RECOVER = 0.6 -- seconds standing after a lunge
Brain.LUNGE_DAMAGE = 28
Brain.SLASH_DAMAGE = 10
Brain.SLASH_REACH = 26 -- px; this near, it slashes
Brain.SLASH_EVERY = 0.55
Brain.SLASHES = 2 -- slashes before it backs off to lunge again...
Brain.BACK_OFF = 0.7 -- ...for this many seconds, at a run
Brain.HIT_REACH = 18 -- px; how near its line a lunge cuts somebody
Brain.LOST_AFTER = 3 -- seconds without seeing whoever it had before it gives up
Brain.REPATH = 0.5 -- seconds between new paths while it runs in
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)

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

--- A new brain. `opts`: fov, aware (px it hears all round), health, nav,
--- firstId, calm, and `hit(server, ripper, who, damage, angle)`: cut `who`
--- (a player id or a rival's soldier).
function Brain.new(opts)
  return setmetatable({
    list = {},
    rivals = {},
    fov = opts.fov,
    aware = opts.aware,
    health = opts.health,
    nav = opts.nav,
    hit = opts.hit,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
  }, Brain)
end

--- A ripper walking `route` (a loop of { x, y }) from corner `start`.
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
    state = "beat", -- beat, run, crouch, lunge, recover
    t = 0, -- seconds into the state
    target = nil,
    lostFor = 0,
    lungeIn = 0,
    slashIn = 0,
    slashes = 0, -- in a row, before it backs off
    backFor = 0,
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

--- Where `who` is (a player id or a rival soldier), if still there.
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

--- Everyone it could go for, as { who, x, y }: players and rivals' soldiers.
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

--- Whoever `s` can see or hear that is most alone, if anyone.
function Brain:pick(server, s)
  if self.calm then
    return nil
  end
  local all = everyone(self, server)
  local best, bestScore
  for _, c in ipairs(all) do
    local d2 = Sight.canSee(s.x, s.y, s.facing, c.x, c.y, Brain.RANGE, self.fov)
      or Sight.canSee(s.x, s.y, s.facing, c.x, c.y, self.aware, 2 * math.pi)
    if d2 or c.who == s.target then
      local score = math.sqrt(dist2(s.x, s.y, c.x, c.y))
      for _, o in ipairs(all) do
        if o ~= c and dist2(o.x, o.y, c.x, c.y) <= Brain.CROWD * Brain.CROWD then
          score = score + Brain.CROWD_COST
        end
      end
      if c.who == s.target then
        score = score - 150 -- it keeps to whoever it has, unless somebody is much easier
        if not (d2 or Sight.clear(s.x, s.y, c.x, c.y)) then
          score = math.huge -- lost behind something
        end
      end
      if score < math.huge and (not bestScore or score < bestScore) then
        best, bestScore = c.who, score
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

--- `s` heads for (x, y) at `speed`: straight there when it can see it,
--- else along a path on the walking grid.
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
    return
  end
  local angle = math.atan2(dy, dx)
  s.facing = turn(s.facing, angle, Brain.TURN, dt)
  local k = math.min(d, speed * dt) / d
  move(s, dx * k, dy * k)
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.cut = nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

--- `s` goes into `state`.
local function enter(s, state)
  s.state, s.t = state, 0
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  s.lungeIn = s.lungeIn - dt
  s.slashIn = s.slashIn - dt
  if s.state == "crouch" then
    if s.t >= Brain.CROUCH then
      enter(s, "lunge")
      s.lunged = true -- for the sound, on every screen
      s.struck = {}
    end
    return
  elseif s.state == "lunge" then
    local step = Brain.LUNGE_SPEED * dt
    local ok = move(s, math.cos(s.lungeAngle) * step, math.sin(s.lungeAngle) * step)
    for _, c in ipairs(everyone(self, server)) do
      if not s.struck[c.who] and dist2(s.x, s.y, c.x, c.y) <= (Brain.HIT_REACH + Brain.RADIUS) ^ 2 then
        s.struck[c.who] = true
        self.hit(server, s, c.who, Brain.LUNGE_DAMAGE, s.lungeAngle)
        s.cut = true
      end
    end
    if not ok or s.t >= Brain.LUNGE_TIME then
      enter(s, "recover")
      s.lungeIn = Brain.LUNGE_EVERY
    end
    return
  elseif s.state == "recover" then
    if s.t >= Brain.RECOVER then
      enter(s, s.target and "run" or "beat")
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
    if s.backFor > 0 then -- getting room for the next lunge
      s.backFor = s.backFor - dt
      local away = math.atan2(s.y - ty, s.x - tx) + (s.id % 2 == 0 and 0.5 or -0.5)
      move(s, math.cos(away) * Brain.RUN * dt, math.sin(away) * Brain.RUN * dt)
      s.facing = turn(s.facing, away + math.pi, Brain.TURN, dt) -- still watching them
    elseif seen and d2 <= Brain.SLASH_REACH ^ 2 then
      s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Brain.TURN, dt)
      if s.slashIn <= 0 then
        s.slashIn = Brain.SLASH_EVERY
        self.hit(server, s, s.target, Brain.SLASH_DAMAGE, s.facing)
        s.cut = true
        s.slashes = s.slashes + 1
        if s.slashes >= Brain.SLASHES then
          s.slashes, s.backFor = 0, Brain.BACK_OFF
        end
      end
    elseif seen and s.lungeIn <= 0 and d2 <= Brain.LUNGE_FROM ^ 2 then
      s.lungeAngle = math.atan2(ty - s.y, tx - s.x) -- set now: step off this line
      s.facing = s.lungeAngle
      enter(s, "crouch")
    else
      goTo(self, s, tx, ty, Brain.RUN, dt)
    end
    return
  end
  -- Its beat.
  local to = s.route[s.leg]
  if dist2(s.x, s.y, to.x, to.y) < 24 * 24 then
    s.leg = s.leg % #s.route + 1
    to = s.route[s.leg]
  end
  goTo(self, s, to.x, to.y, Brain.WALK, dt)
end

--- The ripper whose body covers (x, y) (within `radius` more), and its index.
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

--- Something frightening at (x, y): a ripper about to lunge thinks again.
function Brain:scare(x, y, radius)
  for _, s in ipairs(self.list) do
    if s.state == "crouch" and dist2(s.x, s.y, x, y) <= radius * radius then
      enter(s, "recover")
      s.lungeIn = Brain.LUNGE_EVERY * random()
    end
  end
end

return Brain
