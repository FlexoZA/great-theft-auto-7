-- How Halcyon's sting drones fly (docs/cyber-feud.md, "Halcyon"): small,
-- fast, armed, in swarms. stings.lua puts them in the air and draws them;
-- this is only their heads, on the host.
--
-- A swarm hangs over its home (a gantry on the Overpass), each drone in
-- its own slot round it, until a player comes within SPOT: no line of
-- sight needed, they are up high. Then the swarm makes strafing runs: each
-- drone picks a point a little ahead of where the target is going (LEAD),
-- off to its own side of it, and flies straight through it and PAST on
-- the other side, its gun going whenever the target is in front of it and
-- within RANGE; then it turns (at TURN, so it loops wide at speed) and
-- comes in again. They fly faster than a car (SPEED), so a driver can't
-- just outrun them; they give up past GIVE_UP and fly home. Knocked out
-- (an EMP, `stun`), one drops low and hangs there, dark, for that long.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 8 -- px, to be hit
Brain.SPOT = 700 -- px; a player this near wakes the swarm
Brain.GIVE_UP = 1500 -- px; further than this and they go home
Brain.SPEED = 560 -- px/s on a run (a car tops out round 500)
Brain.HOME_SPEED = 260 -- px/s going home
Brain.TURN = 3.4 -- rad/s
Brain.LEAD = 0.45 -- seconds ahead of the target each run aims for
Brain.PAST = 260 -- px a run carries on past the point before turning back
Brain.SIDE = 70 -- px either side of the target a drone passes, by its slot
Brain.RANGE = 420 -- px it shoots out to
Brain.CONE = 0.35 -- radians: it shoots when the target is this near straight ahead
Brain.BURST = 3 -- rounds, then...
Brain.BURST_GAP = 0.11 -- (seconds between them)...
Brain.PAUSE = 0.7 -- ...a breather
Brain.ORBIT = 34 -- px a hovering drone circles its slot by

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

--- A new brain. `opts`: health, firstId, and `fire(server, drone, aim)`:
--- one round from where the drone is along `aim`.
function Brain.new(opts)
  return setmetatable({
    list = {},
    swarms = {},
    health = opts.health,
    fire = opts.fire,
    nextId = opts.firstId or 1,
    time = 0,
  }, Brain)
end

--- A swarm of `size` over (x, y).
function Brain:addSwarm(x, y, size)
  local swarm = { x = x, y = y, members = {}, target = nil }
  self.swarms[#self.swarms + 1] = swarm
  for i = 1, size do
    local a = (i - 1) / size * 2 * math.pi
    local s = {
      id = self.nextId,
      swarm = swarm,
      slot = i,
      side = i % 2 == 0 and 1 or -1, -- which side of the target its runs pass
      x = x + math.cos(a) * 40,
      y = y + math.sin(a) * 40,
      heading = a,
      hp = self.health,
      run = nil, -- { x, y } the point it is flying through, then PAST it
      past = nil, -- { x, y } where the run ends
      fireIn = 0,
      burstLeft = Brain.BURST,
      stunned = 0,
      frozen = 0,
      phase = i * 1.9,
    }
    self.nextId = self.nextId + 1
    swarm.members[#swarm.members + 1] = s
    self.list[#self.list + 1] = s
  end
  return swarm
end

--- The nearest player within `range` of (x, y), and where they are, and their car.
local function nearestPlayer(server, x, y, range)
  local best, bx, by, bc, bestD2
  for id, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = dist2(px, py, x, y)
      if d2 <= range * range and (not bestD2 or d2 < bestD2) then
        best, bx, by, bestD2 = id, px, py, d2
        bc = p.vehicle and not p.vehicle.hidden and p.vehicle or nil
      end
    end
  end
  return best, bx, by, bc
end

--- `s` flies towards (x, y) at `speed`, turning at most TURN.
local function fly(s, x, y, speed, dt)
  s.heading = turn(s.heading, math.atan2(y - s.y, x - s.x), Brain.TURN, dt)
  s.x, s.y = s.x + math.cos(s.heading) * speed * dt, s.y + math.sin(s.heading) * speed * dt
end

--- A new run for `s` at the target (at x, y, in car `c` if driving): through
--- a point a little ahead of them, off to its side, and on past it.
local function newRun(s, x, y, c)
  local px, py = x, y
  if c then
    px, py = x + math.cos(c.angle) * c.speed * Brain.LEAD, y + math.sin(c.angle) * c.speed * Brain.LEAD
  end
  local dx, dy = px - s.x, py - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 1 then
    d, dx, dy = 1, 1, 0
  end
  local nx, ny = -dy / d, dx / d -- across the run
  s.run = { x = px + nx * s.side * Brain.SIDE * 0.5, y = py + ny * s.side * Brain.SIDE * 0.5 }
  s.past = { x = s.run.x + dx / d * Brain.PAST, y = s.run.y + dy / d * Brain.PAST }
  s.passed = false
end

function Brain:update(server, dt)
  self.time = self.time + dt
  for _, swarm in ipairs(self.swarms) do
    -- The swarm's target: whoever is nearest its home, or the one it has while in reach.
    local cx, cy = swarm.x, swarm.y -- from the middle of the swarm, or its home with none left
    local sx, sy, n = 0, 0, 0
    for _, s in ipairs(swarm.members) do
      sx, sy, n = sx + s.x, sy + s.y, n + 1
    end
    if n > 0 then
      cx, cy = sx / n, sy / n
    end
    local who, x, y, c = nearestPlayer(server, cx, cy, swarm.target and Brain.GIVE_UP or Brain.SPOT)
    swarm.target, swarm.tx, swarm.ty, swarm.tc = who, x, y, c
  end
  for _, s in ipairs(self.list) do
    s.fired = false
    if s.stunned > 0 then
      s.stunned = s.stunned - dt
      s.run = nil
    elseif s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  local swarm = s.swarm
  if not swarm.target then -- home: circling its slot over the gantry
    s.run = nil
    local a = self.time * 1.4 + s.phase
    local hx = swarm.x + math.cos(s.slot * 2.1) * 50 + math.cos(a) * Brain.ORBIT
    local hy = swarm.y + math.sin(s.slot * 2.1) * 30 + math.sin(a) * Brain.ORBIT
    fly(s, hx, hy, Brain.HOME_SPEED * (dist2(s.x, s.y, hx, hy) > 200 * 200 and 1 or 0.4), dt)
    return
  end
  local x, y, c = swarm.tx, swarm.ty, swarm.tc
  if not s.run then
    newRun(s, x, y, c)
  end
  local goal = s.passed and s.past or s.run
  fly(s, goal.x, goal.y, Brain.SPEED, dt)
  if not s.passed and dist2(s.x, s.y, s.run.x, s.run.y) < 50 * 50 then
    s.passed = true
  elseif s.passed and dist2(s.x, s.y, s.past.x, s.past.y) < 60 * 60 then
    newRun(s, x, y, c) -- round again
  end
  -- The gun: whenever they are in front of it and near enough.
  s.fireIn = s.fireIn - dt
  local toThem = math.atan2(y - s.y, x - s.x)
  if s.fireIn <= 0 and dist2(s.x, s.y, x, y) < Brain.RANGE ^ 2
    and math.abs(Sight.angleDiff(toThem, s.heading)) < Brain.CONE then
    self.fire(server, s, toThem)
    s.fired = true
    s.burstLeft = s.burstLeft - 1
    if s.burstLeft > 0 then
      s.fireIn = Brain.BURST_GAP
    else
      s.burstLeft, s.fireIn = Brain.BURST, Brain.PAUSE
    end
  end
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
--- down (and it is off the list and its swarm).
function Brain:hurt(s, i, amount)
  s.hp = s.hp - amount
  if s.hp > 0 then
    return false
  end
  table.remove(self.list, i)
  local members = s.swarm.members
  for k = #members, 1, -1 do
    if members[k] == s then
      table.remove(members, k)
    end
  end
  return true
end

--- Knock out every one within `radius` of (x, y) for `seconds` (an EMP).
function Brain:stun(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      s.stunned = math.max(s.stunned, seconds)
    end
  end
end

function Brain:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

return Brain
