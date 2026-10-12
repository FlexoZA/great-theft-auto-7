-- How Halcyon's sentry turrets think (docs/cyber-feud.md, "Halcyon"): a
-- grey tripod with a magenta lens, bolted down. turrets.lua puts them on
-- the map and draws them; this is only their heads, on the host.
--
-- A turret sweeps its arc (`arc` either side of `watch`... half of it each
-- way) with a narrow cone out to RANGE, and sees only along a clear line.
-- Whoever it spots it tracks (at TURN, never past the ends of its arc) with
-- a laser on them for WARN seconds, then fires bursts of BURST down the
-- laser while it still has them; out of its sight for LOST, it goes back
-- to sweeping. Fast across its front up close, you outrun its turn.
--
-- Breached (`breach`), it is on your side for a while: it goes for the
-- nearest of its `rivals()` (every list of Halcyon and the Static on the
-- map) in its sight instead, and leaves the players alone. Knocked out (an
-- EMP, `stun`), it droops and sees nothing for that long.
--
-- A `calm` brain sees nobody, until turrets.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 12 -- px, to be hit
Brain.RANGE = 620 -- px it sees and shoots out to
Brain.FOV = math.rad(50) -- its cone
Brain.TRACK_FOV = math.rad(80) -- once it has someone, it keeps them in a wider one
Brain.SWEEP_TIME = 5 -- seconds for one sweep of its arc there and back
Brain.TURN = 2.2 -- rad/s tracking someone
Brain.WARN = 0.6 -- seconds of laser before the first round
Brain.BURST = 4 -- rounds...
Brain.BURST_GAP = 0.09 -- (seconds between them)...
Brain.PAUSE = 0.9 -- ...then a breather
Brain.AIMED = 0.15 -- radians: it fires when it is pointing this near them
Brain.LOST = 1.0 -- seconds out of its sight before it gives them up
Brain.LOOK_EVERY = 3 -- host ticks between looks while sweeping

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

--- A new brain. `opts`: health, firstId, calm, `fire(server, turret,
--- aim)` (one round along `aim`), and `rivals()` (the lists, each of
--- { x, y, hp }, a breached turret goes for).
function Brain.new(opts)
  return setmetatable({
    list = {},
    health = opts.health,
    fire = opts.fire,
    rivals = opts.rivals or function()
      return {}
    end,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
    time = 0,
  }, Brain)
end

--- A turret at (x, y), watching `watch` and sweeping `arc` radians in all.
function Brain:add(x, y, watch, arc)
  local t = {
    id = self.nextId,
    x = x,
    y = y,
    watch = watch,
    arc = arc,
    aim = watch,
    hp = self.health,
    state = "sweep",
    target = nil,
    t = 0,
    lostFor = 0,
    fireIn = 0,
    burstLeft = Brain.BURST,
    stunned = 0,
    frozen = 0,
    breachedBy = nil, -- the player it is fighting for
    breachLeft = 0,
    phase = self.nextId * 2.3,
    look = self.nextId,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = t
  return t
end

--- Where `who` is (a player id, or a rival's soldier), if still there to shoot.
local function poseOf(server, who)
  if type(who) == "table" then
    if who.hp > 0 then
      return who.x, who.y
    end
    return nil
  end
  local p = server.players[who]
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    return x, y
  end
  return nil
end

--- `a` kept within `t`'s arc.
local function clampToArc(t, a)
  local half = t.arc / 2
  local d = Sight.angleDiff(a, t.watch)
  if d > half then
    return t.watch + half
  elseif d < -half then
    return t.watch - half
  end
  return t.watch + d
end

--- Can `t` see (x, y) in a cone `fov` wide round where it points?
local function sees(t, x, y, fov)
  return Sight.canSee(t.x, t.y, t.aim, x, y, Brain.RANGE, fov) ~= nil
end

--- The nearest it can see that it wants: players, or once breached its rivals.
function Brain:spot(server, t)
  if self.calm then
    return nil
  end
  local best, bestD2
  local function consider(who, x, y)
    local d2 = dist2(t.x, t.y, x, y)
    if (not bestD2 or d2 < bestD2) and sees(t, x, y, Brain.FOV) then
      best, bestD2 = who, d2
    end
  end
  if t.breachedBy then
    for _, rival in ipairs(self.rivals()) do
      for _, r in ipairs(rival.list) do
        if r.hp > 0 and dist2(t.x, t.y, r.x, r.y) <= Brain.RANGE * Brain.RANGE then
          consider(r, r.x, r.y)
        end
      end
    end
  else
    for id, p in pairs(server.players) do
      if Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        consider(id, x, y)
      end
    end
  end
  return best
end

--- `t` fights for player `id` for `seconds`: whoever it had, it drops.
function Brain:breach(t, id, seconds)
  t.breachedBy, t.breachLeft = id, seconds
  t.target, t.state, t.t = nil, "sweep", 0
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  self.time = self.time + dt
  for _, t in ipairs(self.list) do
    if t.breachedBy then
      t.breachLeft = t.breachLeft - dt
      if t.breachLeft <= 0 or not server.players[t.breachedBy] then
        t.breachedBy, t.target, t.state = nil, nil, "sweep" -- back to Halcyon
      end
    end
    if t.stunned > 0 then
      t.stunned = t.stunned - dt
      t.target, t.state = nil, "sweep"
    elseif t.frozen > 0 then
      t.frozen = t.frozen - dt
    else
      self:think(server, t, dt)
    end
  end
end

function Brain:think(server, t, dt)
  t.fired = false
  local x, y
  if t.target then
    x, y = poseOf(server, t.target)
    if x and sees(t, x, y, Brain.TRACK_FOV) then
      t.lostFor = 0
    else
      t.lostFor = t.lostFor + dt
    end
    if not x or t.lostFor > Brain.LOST then
      t.target, t.state = nil, "sweep"
    end
  end
  if not t.target then
    local s = math.sin(self.time * 2 * math.pi / Brain.SWEEP_TIME + t.phase)
    t.aim = turn(t.aim, t.watch + t.arc / 2 * s, Brain.TURN, dt)
    if (self.tick + t.look) % Brain.LOOK_EVERY == 0 then
      local who = self:spot(server, t)
      if who then
        t.target, t.state, t.t, t.lostFor = who, "warn", 0, 0
      end
    end
    return
  end
  -- Tracking: the laser on them, then bursts down it.
  local to = math.atan2(y - t.y, x - t.x)
  t.aim = turn(t.aim, clampToArc(t, to), Brain.TURN, dt)
  t.t = t.t + dt
  if t.state == "warn" then
    if t.t >= Brain.WARN then
      t.state, t.fireIn, t.burstLeft = "fire", 0, Brain.BURST
    end
    return
  end
  t.fireIn = t.fireIn - dt
  if t.fireIn <= 0 and t.lostFor == 0 and math.abs(Sight.angleDiff(to, t.aim)) < Brain.AIMED then
    self.fire(server, t, t.aim)
    t.fired = true
    t.burstLeft = t.burstLeft - 1
    if t.burstLeft > 0 then
      t.fireIn = Brain.BURST_GAP
    else
      t.burstLeft, t.fireIn = Brain.BURST, Brain.PAUSE
    end
  end
end

function Brain:at(x, y, radius)
  local r = Brain.RADIUS + (radius or 0)
  for i, t in ipairs(self.list) do
    if dist2(t.x, t.y, x, y) <= r * r then
      return t, i
    end
  end
  return nil
end

--- Take `amount` off `t` (index `i`). Returns true when that destroyed it
--- (and it is off the list).
function Brain:hurt(t, i, amount)
  t.hp = t.hp - amount
  if t.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  return false
end

--- Knock out every one within `radius` of (x, y) for `seconds` (an EMP).
function Brain:stun(x, y, radius, seconds)
  for _, t in ipairs(self.list) do
    if dist2(t.x, t.y, x, y) <= (radius + Brain.RADIUS) ^ 2 then
      t.stunned = math.max(t.stunned, seconds)
    end
  end
end

function Brain:freeze(x, y, radius, seconds)
  for _, t in ipairs(self.list) do
    if dist2(t.x, t.y, x, y) <= radius * radius then
      t.frozen = math.max(t.frozen, seconds)
    end
  end
end

return Brain
