-- How the Static's sparkers think (docs/cyber-feud.md, "The Static"):
-- hooded, a belt of EMP grenades, never in the thick of it. sparkers.lua
-- puts them on the map, flies their EMPs and draws them; this is only
-- their heads, on the host.
--
-- A sparker walks its beat (a loop of { x, y }) until it sees or hears a
-- player, or one of its `rivals` (another brain's `list`: whatever of
-- Halcyon's an EMP is good against). Then it keeps its distance: it backs
-- off when they come nearer than NEAR, closes in, round the stalls on
-- `nav` (d-day/nav.lua), when they are further than FAR, and otherwise
-- stands and lobs. A lob is a WIND_UP with the grenade raised, then
-- `lob(server, sparker, x, y)` at where they stand at that moment, every
-- LOB_EVERY. It goes back to its beat once it has lost them.
--
-- A `calm` brain sees nobody, until sparkers.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9 -- px
Brain.RANGE = 600 -- px it can see
Brain.WALK = 50 -- px/s on its beat
Brain.RUN = 110 -- px/s getting where it wants to be
Brain.TURN = 4 -- rad/s
Brain.NEAR = 230 -- px; nearer than this, it backs off
Brain.FAR = 400 -- px; further than this, it closes in
Brain.LOB_REACH = 440 -- px it throws at most
Brain.LOB_EVERY = 3.6 -- seconds from one lob to the next
Brain.WIND_UP = 0.6 -- seconds the grenade is raised before it goes
Brain.LOST_AFTER = 3 -- seconds without seeing whoever it had before it gives up
Brain.REPATH = 0.5
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

--- A new brain. `opts`: fov, aware (px it hears all round), health, nav,
--- firstId, calm, and `lob(server, sparker, x, y)`: throw an EMP at (x, y).
function Brain.new(opts)
  return setmetatable({
    list = {},
    rivals = {},
    fov = opts.fov,
    aware = opts.aware,
    health = opts.health,
    nav = opts.nav,
    lob = opts.lob,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
  }, Brain)
end

--- A sparker walking `route` (a loop of { x, y }) from corner `start`.
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
    target = nil,
    lostFor = 0,
    lobIn = 1, -- a moment before the first
    windUp = nil, -- seconds left raising a grenade, while it is
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

--- The nearest player or rival `s` can see or hear, if any.
function Brain:spot(server, s)
  if self.calm then
    return nil
  end
  local best, bestD2
  local function consider(who, x, y)
    local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Brain.RANGE, self.fov)
      or Sight.canSee(s.x, s.y, s.facing, x, y, self.aware, 2 * math.pi)
    if d2 and (not bestD2 or d2 < bestD2) then
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
  end
end

--- `s` heads for (x, y) at `speed`, along a path when it can't see it. It
--- faces the way it goes unless `look` says where to look.
local function goTo(self, s, x, y, speed, dt, look)
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
  s.facing = turn(s.facing, look or math.atan2(dy, dx), Brain.TURN, dt)
  local k = math.min(d, speed * dt) / d
  move(s, dx * k, dy * k)
end

function Brain:update(server, dt)
  self.tick = self.tick + 1
  for _, s in ipairs(self.list) do
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
    else
      self:think(server, s, dt)
    end
  end
end

function Brain:think(server, s, dt)
  s.lobIn = s.lobIn - dt
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local who = self:spot(server, s)
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
      s.target, s.path, s.windUp = nil, nil, nil
    end
  end
  if tx then
    local toThem = math.atan2(ty - s.y, tx - s.x)
    local d2 = dist2(s.x, s.y, tx, ty)
    local seen = Sight.clear(s.x, s.y, tx, ty)
    if s.windUp then -- arm back: it throws at wherever they are when it lets go
      s.facing = turn(s.facing, toThem, Brain.TURN, dt)
      s.windUp = s.windUp - dt
      if s.windUp <= 0 then
        s.windUp, s.lobIn = nil, Brain.LOB_EVERY
        if seen then
          local reach = math.min(math.sqrt(d2), Brain.LOB_REACH)
          self.lob(server, s, s.x + math.cos(toThem) * reach, s.y + math.sin(toThem) * reach)
        end
      end
      return
    end
    if d2 < Brain.NEAR * Brain.NEAR then -- too near: away, still watching them
      local away = toThem + math.pi + (s.id % 2 == 0 and 0.4 or -0.4)
      goTo(self, s, s.x + math.cos(away) * 60, s.y + math.sin(away) * 60, Brain.RUN, dt, toThem)
    elseif d2 > Brain.FAR * Brain.FAR or not seen then
      goTo(self, s, tx, ty, Brain.RUN, dt)
    else
      s.facing = turn(s.facing, toThem, Brain.TURN, dt)
    end
    if seen and s.lobIn <= 0 and d2 <= (Brain.LOB_REACH + 40) ^ 2 and d2 >= (Brain.NEAR * 0.6) ^ 2 then
      s.windUp = Brain.WIND_UP
    end
    return
  end
  local to = s.route[s.leg]
  if dist2(s.x, s.y, to.x, to.y) < 24 * 24 then
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
  end
  return false
end

function Brain:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
      s.windUp = nil
    end
  end
end

--- Something frightening at (x, y): one winding up drops the throw.
function Brain:scare(x, y, radius)
  for _, s in ipairs(self.list) do
    if s.windUp and dist2(s.x, s.y, x, y) <= radius * radius then
      s.windUp, s.lobIn = nil, Brain.LOB_EVERY * 0.5
    end
  end
end

return Brain
