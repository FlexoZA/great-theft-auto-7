-- How Heck's Cacodaemons think (docs/eternal-mood.md, "The demons"): a
-- floating red tomato with one green eye and a big mouth. Not a boss, but
-- the heaviest thing in the horde so far. horde.lua puts them on the map
-- (the map's `horde.cacos`) and draws them, fireballs.lua flies what they
-- spit; this is only their heads, on the host.
--
-- A Cacodaemon floats, so walls, roofs and lava are nothing to it: it flies
-- straight over them. It hangs about its spot, bobbing, until a player comes
-- within its `wake` px, it sees one across open ground, or it is hurt; then
-- its whole flock comes. It drifts round its target at a distance (KEEP),
-- slowly, and every few seconds, over open ground with a clear line, it
-- opens its mouth for OPEN seconds (the tell, drawn on every screen) and
-- spits a ball of fire at where they stand: big and slow, a step to the
-- side does it. Shot while its mouth is open it takes a mouthful (MOUTHFUL
-- times the damage), reels back for REEL seconds and doesn't spit. Too
-- close, it bites (its mouth opening first, shorter).

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 26 -- px; a big round thing
Brain.HEALTH = 220
Brain.FLY = 70 -- px/s, slow
Brain.TURN = 2.4 -- rad/s; slow to come round, too
Brain.HOVER = 40 -- px round its spot it drifts about in, waiting
Brain.SEES = 700 -- px; up high, it sees over everything...
Brain.HUNTS = 1600 -- ...and once woken it goes after the nearest player this near
Brain.KEEP = { 200, 400 } -- px; it backs off nearer than the first, closes in further than the second
Brain.ORBIT = 0.35 -- rad/s it circles round its target
Brain.SPACE = 70 -- px it keeps from others of its kind
Brain.SPIT_EVERY = { 2.6, 3.8 } -- seconds between spits
Brain.SPIT_RANGE = 640 -- px
Brain.OPEN = 0.5 -- seconds its mouth is open before it spits: the tell
Brain.MOUTHFUL = 1.5 -- damage taken with its mouth open
Brain.REEL = 0.9 -- seconds reeling, shot in the mouth
Brain.REEL_BACK = 90 -- px/s it is knocked back while it reels
Brain.BITE_REACH = 24 -- px past its edge
Brain.BITE_OPEN = 0.3 -- seconds its mouth opens before it bites
Brain.BITE_EVERY = 1.2
Brain.BITE_DAMAGE = 30
Brain.LOOK_EVERY = 3

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

--- A new brain. `opts`: firstId, `bounds` { x0, y0, x1, y1 } it stays in
--- (world px), and the host's hands: `spit(server, caco, x, y, angle)` a
--- ball of fire from (x, y) along `angle`, `bite(server, caco, playerId,
--- damage, angle)`.
function Brain.new(opts)
  return setmetatable({
    list = {},
    bounds = opts.bounds,
    spit = opts.spit,
    bite = opts.bite,
    nextId = opts.firstId or 1,
    tick = 0,
  }, Brain)
end

--- One waiting at (x, y), woken by a player within `wake` px; `flock`
--- names the ones that wake together.
function Brain:add(x, y, wake, flock)
  local s = {
    id = self.nextId,
    x = x,
    y = y,
    homeX = x,
    homeY = y,
    wake = wake or 520,
    flock = flock,
    facing = math.pi / 2,
    hp = Brain.HEALTH,
    state = "idle", -- idle, hunt, open, bite, reel
    t = 0,
    target = nil,
    side = random() < 0.5 and 1 or -1,
    spitIn = between(Brain.SPIT_EVERY) * 0.5,
    biteIn = 0,
    frozen = 0,
    look = self.nextId,
    phase = random() * 2 * math.pi,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

local function enter(s, state)
  s.state, s.t = state, 0
end

--- Wake `s`, and the rest of its flock.
function Brain:wakeUp(s)
  for _, o in ipairs(self.list) do
    if o.state == "idle" and (o == s or (s.flock and o.flock == s.flock)) then
      enter(o, "hunt")
      o.woke = true
    end
  end
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

--- Fly by (mx, my), kept apart from the others and inside the map.
function Brain:fly(s, mx, my)
  for _, o in ipairs(self.list) do
    if o ~= s then
      local dx, dy = s.x - o.x, s.y - o.y
      local d2 = dx * dx + dy * dy
      if d2 > 0.01 and d2 < Brain.SPACE * Brain.SPACE then
        local d = math.sqrt(d2)
        local push = (Brain.SPACE - d) / Brain.SPACE * 0.6
        mx, my = mx + dx / d * push, my + dy / d * push
      end
    end
  end
  local b = self.bounds
  s.x, s.y = s.x + mx, s.y + my
  if b then
    local r = Brain.RADIUS
    s.x = math.max(b.x0 + r, math.min(b.x1 - r, s.x))
    s.y = math.max(b.y0 + r, math.min(b.y1 - r, s.y))
  end
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    s.spat, s.bit = nil, nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

--- Is a player near enough (or in plain sight) to wake it?
local function stirred(server, s)
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(s.x, s.y, x, y)
      if d2 <= s.wake * s.wake or (d2 <= Brain.SEES * Brain.SEES and Sight.clear(s.x, s.y, x, y)) then
        return true
      end
    end
  end
  return false
end

function Brain:think(server, s, dt)
  s.t = s.t + dt
  s.spitIn = s.spitIn - dt
  s.biteIn = s.biteIn - dt
  if s.state == "idle" then
    -- Drifting about its spot, slowly round and back.
    local a = s.phase + s.t * 0.3
    local gx, gy = s.homeX + math.cos(a) * Brain.HOVER, s.homeY + math.sin(a * 1.3) * Brain.HOVER * 0.6
    local dx, dy = gx - s.x, gy - s.y
    local d = math.sqrt(dx * dx + dy * dy)
    if d > 1 then
      local k = math.min(d, Brain.FLY * 0.4 * dt) / d
      self:fly(s, dx * k, dy * k)
      s.facing = turn(s.facing, math.atan2(dy, dx), Brain.TURN * 0.5, dt)
    end
    if (self.tick + s.look) % Brain.LOOK_EVERY == 0 and stirred(server, s) then
      self:wakeUp(s)
    end
    return
  end
  if s.state == "reel" then
    -- Knocked back, spinning, mouth full of lead.
    self:fly(s, math.cos(s.reelAngle) * Brain.REEL_BACK * dt, math.sin(s.reelAngle) * Brain.REEL_BACK * dt)
    s.facing = s.facing + 7 * dt
    if s.t >= Brain.REEL then
      enter(s, "hunt")
    end
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
    if s.state ~= "hunt" then
      enter(s, "hunt")
    end
    return -- nobody about: it hangs there
  end
  local aim = math.atan2(ty - s.y, tx - s.x)
  local d2 = dist2(s.x, s.y, tx, ty)
  if s.state == "open" then
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
    if s.t >= Brain.OPEN then
      -- At where they stand now: moving sidesteps it.
      local mx, my = s.x + math.cos(s.facing) * Brain.RADIUS, s.y + math.sin(s.facing) * Brain.RADIUS
      self.spit(server, s, mx, my, math.atan2(ty - my, tx - mx))
      s.spat = true
      s.spitIn = between(Brain.SPIT_EVERY)
      enter(s, "hunt")
    end
    return
  end
  local reach = Brain.RADIUS + Brain.BITE_REACH
  if s.state == "bite" then
    s.facing = turn(s.facing, aim, Brain.TURN * 2, dt)
    if s.t >= Brain.BITE_OPEN then
      if d2 <= (reach + 12) ^ 2 then
        self.bite(server, s, s.target, Brain.BITE_DAMAGE, aim)
        s.bit = true
      end
      s.biteIn = Brain.BITE_EVERY
      enter(s, "hunt")
    end
    return
  end
  if d2 <= reach * reach and s.biteIn <= 0 then
    enter(s, "bite")
    return
  end
  if s.spitIn <= 0 and d2 <= Brain.SPIT_RANGE * Brain.SPIT_RANGE and d2 > reach * reach
    and Sight.clear(s.x, s.y, tx, ty) then
    s.facing = turn(s.facing, aim, Brain.TURN, dt)
    if math.abs(Sight.angleDiff(aim, s.facing)) < 0.5 then
      enter(s, "open")
    end
    return
  end
  -- Circle round them at its distance, slowly coming round to face them,
  -- making for open ground (it can't spit from over a roof, nor be shot
  -- there): a goal over a building comes in nearer, or it turns about.
  local d = math.sqrt(d2)
  local want = math.max(Brain.KEEP[1], math.min(Brain.KEEP[2], d))
  local around = math.atan2(s.y - ty, s.x - tx) + s.side * Brain.ORBIT * dt * 4
  local gx, gy = tx + math.cos(around) * want, ty + math.sin(around) * want
  if Sight.blocked(gx, gy) then
    gx, gy = tx + math.cos(around) * Brain.KEEP[1], ty + math.sin(around) * Brain.KEEP[1]
    if Sight.blocked(gx, gy) then
      s.side = -s.side
    end
  end
  local dx, dy = gx - s.x, gy - s.y
  local gd = math.sqrt(dx * dx + dy * dy)
  if gd > 1 then
    local k = math.min(gd, Brain.FLY * dt) / gd
    self:fly(s, dx * k, dy * k)
  end
  s.facing = turn(s.facing, aim, Brain.TURN, dt)
  if random() < dt * 0.15 then
    s.side = -s.side
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

--- Take `amount` off `s` (index `i`), the round coming along `angle`.
--- Returns true when that put it down. Hurt, it wakes with its flock; hurt
--- with its mouth open, it takes a mouthful and reels.
function Brain:hurt(s, i, amount, angle)
  if s.state == "open" then
    amount = amount * Brain.MOUTHFUL
  end
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if s.state == "idle" then
    self:wakeUp(s)
  elseif s.state == "open" then
    s.reelAngle = angle or (s.facing + math.pi)
    s.spitIn = between(Brain.SPIT_EVERY) * 0.6
    s.reeled = true
    enter(s, "reel")
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
