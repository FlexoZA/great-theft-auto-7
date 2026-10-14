-- How Halcyon's watcher drones think (docs/cyber-feud.md, "Halcyon"): a
-- small flying disc with an eye and no gun. watchers.lua puts them in the
-- air and draws them; this is only their heads, on the host.
--
-- A watcher flies its beat (a loop of { x, y }) high over the stalls,
-- straight from corner to corner, its cone swinging from side to side. It
-- sees over walls, being up there: a player inside its cone and within
-- RANGE is seen, whatever stands between. Then it stops, hangs over them
-- (no nearer than HOVER, following as they go, and never over anything
-- solid, where a round couldn't reach it) and calls them in:
-- `alarm(server, watcher, x, y)` at once and every ALARM_EVERY while it
-- still has them. Out of its cone for LOST_AFTER, they are gone and it
-- flies back to its beat. Knocked out (an EMP, `stun`), it drops low and
-- dark for that long and sees nothing.
--
-- Indoors (`indoors`, Halcyon Tower) it flies under the ceiling: it sees
-- over the furniture but only who is in the same room as it (`sameRoom(x0,
-- y0, x1, y1)`, the tower's floors), and goes round what stands on the
-- floor (sliding along it), never over it or through a wall.
--
-- A `calm` brain sees nobody, until watchers.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9 -- px, to be hit
Brain.RANGE = 440 -- px it sees
Brain.FLY = 70 -- px/s on its beat
Brain.CHASE = 120 -- px/s following somebody
Brain.HOVER = 140 -- px; it hangs this far off whoever it has
Brain.TURN = 2.5 -- rad/s
Brain.SWEEP = math.rad(45) -- its look swings this far either side of the way it flies...
Brain.SWEEP_TIME = 3 -- ...there and back in this many seconds
Brain.ALARM_EVERY = 6 -- seconds between calls while it has somebody
Brain.LOST_AFTER = 2 -- seconds out of its cone before it gives them up
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

--- A new brain. `opts`: fov, health, firstId, calm, and
--- `alarm(server, watcher, x, y)`: somebody seen at (x, y).
function Brain.new(opts)
  return setmetatable({
    list = {},
    fov = opts.fov,
    health = opts.health,
    alarm = opts.alarm,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    indoors = opts.indoors == true,
    sameRoom = opts.sameRoom,
    tick = 0,
    time = 0,
  }, Brain)
end

--- A watcher on `route` (a loop of { x, y }) from corner `start`.
function Brain:add(route, start)
  local p = route[start]
  local nx = route[start % #route + 1]
  local s = {
    id = self.nextId,
    x = p.x,
    y = p.y,
    route = route,
    leg = start % #route + 1,
    heading = math.atan2(nx.y - p.y, nx.x - p.x),
    facing = 0,
    hp = self.health,
    target = nil,
    lostFor = 0,
    alarmIn = 0,
    stunned = 0,
    frozen = 0,
    phase = self.nextId * 1.7,
    look = self.nextId,
  }
  s.facing = s.heading
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Is `who` (a player id) where `s` can see them? Their pose if so.
local function sees(self, server, s, who)
  local p = server.players[who]
  if not (p and Features.visible(server, p)) then
    return nil
  end
  local x, y = Features.bodyPose(server, p)
  local dx, dy = x - s.x, y - s.y
  if dx * dx + dy * dy > Brain.RANGE * Brain.RANGE then
    return nil
  end
  if math.abs(Sight.angleDiff(math.atan2(dy, dx), s.facing)) > self.fov / 2 then
    return nil
  end
  if self.sameRoom and not self.sameRoom(s.x, s.y, x, y) then
    return nil
  end
  return x, y
end

--- The nearest player in `s`'s cone, if any.
function Brain:spot(server, s)
  if self.calm then
    return nil
  end
  local best, bestD2
  for id in pairs(server.players) do
    local x, y = sees(self, server, s, id)
    if x then
      local d2 = dist2(s.x, s.y, x, y)
      if not bestD2 or d2 < bestD2 then
        best, bestD2 = id, d2
      end
    end
  end
  return best
end

--- `s` flies towards (x, y) at `speed`: over everything, or `indoors`
--- round it (along it, if only one way is in the way; not at all if both).
local function fly(s, x, y, speed, dt, indoors)
  local dx, dy = x - s.x, y - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then
    return
  end
  s.heading = turn(s.heading, math.atan2(dy, dx), Brain.TURN * 1.5, dt)
  local k = math.min(d, speed * dt)
  local nx, ny = s.x + math.cos(s.heading) * k, s.y + math.sin(s.heading) * k
  if indoors then
    local r = Brain.RADIUS + 4
    local function open(px, py)
      return not (Sight.blocked(px, py) or Sight.blocked(px + r, py) or Sight.blocked(px - r, py)
        or Sight.blocked(px, py + r) or Sight.blocked(px, py - r))
    end
    if not open(nx, ny) then
      if open(nx, s.y) then
        ny = s.y
      elseif open(s.x, ny) then
        nx = s.x
      else
        return
      end
    end
  end
  s.x, s.y = nx, ny
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  self.time = self.time + dt
  for _, s in ipairs(self.list) do
    if s.stunned > 0 then
      s.stunned = s.stunned - dt
      s.target = nil
    elseif s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  s.alarmIn = s.alarmIn - dt
  if not s.target and (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local who = self:spot(server, s)
    if who then
      s.target, s.lostFor, s.alarmIn = who, 0, 0
    end
  end
  if s.target then
    local p = server.players[s.target]
    local px, py
    if p and Features.visible(server, p) then
      px, py = Features.bodyPose(server, p)
    end
    local seen = px and sees(self, server, s, s.target)
    s.lostFor = seen and 0 or s.lostFor + dt
    if not px or s.lostFor > Brain.LOST_AFTER then
      s.target = nil
    else
      local toThem = math.atan2(py - s.y, px - s.x)
      s.facing = turn(s.facing, toThem, Brain.TURN, dt)
      local d2 = dist2(s.x, s.y, px, py)
      if Sight.blocked(s.x, s.y) then -- over a stall a round can't reach it: it doesn't hang there
        fly(s, px, py, Brain.CHASE, dt, self.indoors)
      elseif d2 > (Brain.HOVER + 30) ^ 2 then
        fly(s, px, py, Brain.CHASE, dt, self.indoors)
      elseif d2 < (Brain.HOVER - 40) ^ 2 then
        fly(s, s.x - math.cos(toThem) * 40, s.y - math.sin(toThem) * 40, Brain.FLY, dt, self.indoors)
      end
      if seen and s.alarmIn <= 0 then
        s.alarmIn = Brain.ALARM_EVERY
        self.alarm(server, s, px, py)
        s.called = true -- for the ping, on every screen
      end
      return
    end
  end
  local to = s.route[s.leg]
  if dist2(s.x, s.y, to.x, to.y) < 30 * 30 then
    s.leg = s.leg % #s.route + 1
    to = s.route[s.leg]
  end
  fly(s, to.x, to.y, Brain.FLY, dt, self.indoors)
  local sweep = Brain.SWEEP * math.sin(self.time * 2 * math.pi / Brain.SWEEP_TIME + s.phase)
  s.facing = turn(s.facing, s.heading + sweep, Brain.TURN, dt)
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

--- Take `amount` off `s` (index `i`). Returns true when that brought it
--- down (and it is off the list).
function Brain:hurt(s, i, amount)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  return false
end

--- Knock out every one within `radius` of (x, y) for `seconds` (an EMP).
--- Returns how many it caught.
function Brain:stun(x, y, radius, seconds)
  local n = 0
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      s.stunned, s.target, n = math.max(s.stunned, seconds), nil, n + 1
    end
  end
  return n
end

function Brain:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

return Brain
