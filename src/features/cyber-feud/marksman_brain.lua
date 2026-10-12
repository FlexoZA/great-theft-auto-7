-- How Halcyon's marksmen think (docs/cyber-feud.md, "Halcyon"): a dark
-- helmet and a long rifle, up on a catwalk where nothing on the road gets
-- in the way. marksmen.lua puts them there and draws them; this is only
-- their heads, on the host.
--
-- A marksman watches the way he faces, in a wide cone out to RANGE, over
-- everything (he is up high). Whoever he spots, a player or one of his
-- `rivals` (another troop's or brain's `list`), he aims at: a thin magenta
-- line from his rifle that follows them for AIM seconds, then holds still
-- for LOCK (brighter) and he fires down it. He leads a car: the line
-- points where it will be when the round gets there if it keeps on as it
-- is going, so whoever drives straight on is hit, and whoever swerves
-- while the line holds is missed. Then he works the bolt (RELOAD) and aims
-- again, at whoever is nearest now.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9
Brain.RANGE = 950 -- px he sees and shoots out to
Brain.FOV = math.rad(130) -- his cone, from the catwalk rail
Brain.AIM = 1.0 -- seconds the line follows them...
Brain.LOCK = 0.4 -- ...then holds still before the shot
Brain.TRACK = 1.6 -- rad/s the line can swing at while it follows
Brain.RELOAD = 2.4 -- seconds working the bolt after a shot
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

--- A new brain. `opts`: health, firstId, calm, roundSpeed (px/s, for the
--- lead), and `fire(server, s, aim)`: the rifle's round from where he
--- stands along `aim`.
function Brain.new(opts)
  return setmetatable({
    list = {},
    rivals = {},
    roundSpeed = opts.roundSpeed or 1500,
    health = opts.health,
    fire = opts.fire,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
  }, Brain)
end

--- A marksman at (x, y), watching `watch`.
function Brain:add(x, y, watch)
  local s = {
    id = self.nextId,
    x = x,
    y = y,
    watch = watch,
    aim = watch, -- where the rifle (and the line) points
    hp = self.health,
    target = nil,
    state = "watch", -- watch, aim, lock, reload
    t = 0,
    frozen = 0,
    look = self.nextId,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Where `who` is, and how fast it is going (px/s each way): a player on
--- foot or in their car, or a rival soldier (taken as standing still).
local function poseOf(server, who)
  if type(who) == "table" then
    if who.hp > 0 then
      return who.x, who.y, 0, 0
    end
    return nil
  end
  local p = server.players[who]
  if p and Features.visible(server, p) then
    local x, y, onFoot = Features.bodyPose(server, p)
    local c = not onFoot and p.vehicle
    if c then
      return x, y, math.cos(c.angle) * c.speed, math.sin(c.angle) * c.speed
    end
    return x, y, 0, 0
  end
  return nil
end

--- The nearest player or rival in his cone, if any.
function Brain:spot(server, s)
  if self.calm then
    return nil
  end
  local best, bestD2
  local function consider(who, x, y)
    local dx, dy = x - s.x, y - s.y
    local d2 = dx * dx + dy * dy
    if d2 <= Brain.RANGE * Brain.RANGE and math.abs(Sight.angleDiff(math.atan2(dy, dx), s.watch)) <= Brain.FOV / 2
      and (not bestD2 or d2 < bestD2) then
      best, bestD2 = who, d2
    end
  end
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      consider(id, x, y)
    end
  end
  for _, rival in ipairs(self.rivals) do
    for _, r in ipairs(rival.list) do
      if r.hp > 0 then
        consider(r, r.x, r.y)
      end
    end
  end
  return best
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.fired = false
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  if s.state == "reload" then
    if s.t >= Brain.RELOAD then
      s.state, s.t, s.target = "watch", 0, nil
    end
    return
  end
  if s.state == "lock" then
    if s.t >= Brain.LOCK then
      self.fire(server, s, s.aim)
      s.fired = true
      s.state, s.t = "reload", 0
    end
    return
  end
  if s.state == "watch" then
    s.aim = turn(s.aim, s.watch, Brain.TRACK * 0.5, dt)
    if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
      local who = self:spot(server, s)
      if who then
        s.target, s.state, s.t = who, "aim", 0
      end
    end
    return
  end
  -- Aiming: the line follows where they will be when the round gets
  -- there, and he takes the shot once it has had long enough.
  local x, y, vx, vy = poseOf(server, s.target)
  if not x or dist2(s.x, s.y, x, y) > (Brain.RANGE * 1.2) ^ 2 then
    s.state, s.t, s.target = "watch", 0, nil
    return
  end
  local lead = Brain.LOCK + math.sqrt(dist2(s.x, s.y, x, y)) / self.roundSpeed
  local px, py = x + vx * lead, y + vy * lead
  s.aim = turn(s.aim, math.atan2(py - s.y, px - s.x), Brain.TRACK, dt)
  if s.t >= Brain.AIM then
    s.state, s.t = "lock", 0
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

--- Take `amount` off `s` (index `i`). Returns true when that put him down
--- (and he is off the list).
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
