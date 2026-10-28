-- How Halcyon's enforcers think (docs/cyber-feud.md, "Halcyon"): slow,
-- tough men behind riot shields who hold a choke point. enforcers.lua puts
-- them on the map and draws them; this is only their heads, on the host.
--
-- Each has a post (a gate, a doorway) and a way he watches. He sees in a
-- cone in front, out to RANGE, and hears anyone within `aware` all round.
-- Whoever he spots, a player or one of his `rivals` (another brain's or
-- troop's `list`, the way a-man/combine.lua's rivals work), he turns to
-- face, slowly: the shield is in front of him and stops every round from
-- there, so the way to beat him is to get round his side while he turns,
-- or to blow him up. He steps up on whoever he has to get them inside his
-- shotgun's reach, but never further than LEASH from his post, and goes
-- back to it once he has lost them, after a look round where they were.
-- Shot from where he isn't looking, he turns that way.
--
-- A `calm` brain sees nobody, until enforcers.lua wakes it.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 10 -- px; a little broader than an officer, with the shield
Brain.RANGE = 560 -- px he can see
Brain.TURN = 1.3 -- rad/s he turns: slow, so you can get round him (an officer turns at 2)
Brain.WALK = 34 -- px/s stepping up behind the shield (an officer walks at 62)
Brain.BACK = 46 -- px/s walking back to his post
Brain.LEASH = 300 -- px from his post he will step up
Brain.KEEP = 150 -- px; he stops stepping up this near and just shoots
Brain.AIMED = math.rad(14) -- he fires once whoever he has is this near straight ahead
Brain.REACT = 0.8 -- seconds from spotting someone to the first shot
Brain.SHIELD = math.rad(70) -- the shield covers rounds coming at him within this of straight on
Brain.SEARCH = 4 -- seconds he looks round where he lost somebody
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)
Brain.MUZZLE = 20 -- px from his middle the pellets leave, past the shield's edge
Brain.SPREAD = 0.05 -- radians of aim error, on top of the shotgun's own
Brain.THROUGH = { explosive = true, fire = true } -- what the shield doesn't stop

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Turn `from` towards `to` by at most `rate` * dt.
local function turn(from, to, rate, dt)
  local d = Sight.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- A new brain. `opts`: fov and alertFov (his cone calm and once he has
--- somebody or is looking), aware (px he hears all round), health, from
--- (the side's name, on his rounds), firstId, calm.
function Brain.new(opts)
  return setmetatable({
    list = {},
    rivals = {},
    fov = opts.fov,
    alertFov = opts.alertFov,
    aware = opts.aware,
    health = opts.health,
    from = opts.from,
    nextId = opts.firstId or 1,
    calm = opts.calm == true,
    tick = 0,
  }, Brain)
end

--- One enforcer on post (x, y) watching `watch`, carrying `arms`
--- ({ gun, pause, reach }, the gun a weapons/guns.lua table).
function Brain:add(x, y, watch, arms)
  local s = {
    id = self.nextId,
    x = x,
    y = y,
    post = { x = x, y = y, watch = watch },
    facing = watch,
    hp = self.health,
    arms = arms,
    fireIn = 0,
    target = nil, -- a player id, or a rival's soldier
    lastX = nil, -- where he last saw whoever he had
    lastY = nil,
    searchFor = 0,
    frozen = 0,
    look = self.nextId, -- staggers his sight checks
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Is `s` on edge: looking for somebody he lost, or turned by a round?
function Brain.wary(s)
  return s.searchFor > 0
end

--- Where `who` is (a player id or a rival soldier), if still there to be shot at.
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

--- The nearest player or rival he can see or hear right now, if any.
function Brain:spot(server, s)
  if self.calm then
    return nil
  end
  local fov = (s.target or s.searchFor > 0) and self.alertFov or self.fov
  local best, bestD2
  local function consider(who, x, y)
    local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Brain.RANGE, fov)
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
      if r.hp > 0 and dist2(r.x, r.y, s.x, s.y) <= Brain.RANGE * Brain.RANGE then
        consider(r, r.x, r.y)
      end
    end
  end
  return best
end

--- Can `s` stand at (x, y)? Nothing solid round him.
local function fits(x, y)
  local r = Brain.RADIUS
  return not (Sight.blocked(x, y) or Sight.blocked(x - r, y) or Sight.blocked(x + r, y)
    or Sight.blocked(x, y - r) or Sight.blocked(x, y + r))
end

--- `s` steps towards (x, y) at `speed`, sliding along whatever is in the way.
local function step(s, x, y, speed, dt)
  local dx, dy = x - s.x, y - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  if d < 2 then
    return true
  end
  local move = math.min(d, speed * dt)
  local mx, my = dx / d * move, dy / d * move
  if fits(s.x + mx, s.y + my) then
    s.x, s.y = s.x + mx, s.y + my
  elseif fits(s.x + mx, s.y) then
    s.x = s.x + mx
  elseif fits(s.x, s.y + my) then
    s.y = s.y + my
  end
  return false
end

--- A pull of his shotgun at (tx, ty).
local function fire(self, server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Brain.SPREAD
  local mx, my = s.x + math.cos(aim) * Brain.MUZZLE, s.y + math.sin(aim) * Brain.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, s.arms.gun, self.from)
  s.fired = true
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
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local seen = self:spot(server, s)
    if seen and seen ~= s.target then
      s.fireIn = math.max(s.fireIn, Brain.REACT)
    end
    if seen then
      s.target = seen
    end
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
    if tx and not Sight.clear(s.x, s.y, tx, ty) then
      tx = nil -- behind something: lost
    end
    if not tx then
      s.target, s.searchFor = nil, Brain.SEARCH
    end
  end
  local px, py = s.post.x, s.post.y
  if tx then
    s.lastX, s.lastY, s.searchFor = tx, ty, Brain.SEARCH
    local want = math.atan2(ty - s.y, tx - s.x)
    s.facing = turn(s.facing, want, Brain.TURN, dt)
    -- Step up behind the shield, but not off his post's leash.
    local d2 = dist2(s.x, s.y, tx, ty)
    if d2 > Brain.KEEP * Brain.KEEP and math.abs(Sight.angleDiff(want, s.facing)) < 0.6 then
      local nx, ny = s.x + math.cos(want) * 8, s.y + math.sin(want) * 8
      if dist2(nx, ny, px, py) <= Brain.LEASH * Brain.LEASH then
        step(s, nx, ny, Brain.WALK, dt)
      end
    end
    s.fireIn = s.fireIn - dt
    local reach = s.arms.reach
    if s.fireIn <= 0 and d2 <= reach * reach and math.abs(Sight.angleDiff(want, s.facing)) <= Brain.AIMED then
      fire(self, server, s, tx, ty)
      s.fireIn = s.arms.pause * (0.85 + random() * 0.3)
    end
    return
  end
  if s.searchFor > 0 then
    s.searchFor = s.searchFor - dt
    if s.lastX then -- facing where they were, then a look either side
      local base = math.atan2(s.lastY - s.y, s.lastX - s.x)
      s.facing = turn(s.facing, base + math.sin(s.searchFor * 1.6) * 0.8, Brain.TURN, dt)
    end
    return
  end
  -- Nobody: back to his post, then watching the way he watches.
  if dist2(s.x, s.y, px, py) > 6 * 6 then
    s.facing = turn(s.facing, math.atan2(py - s.y, px - s.x), Brain.TURN, dt)
    step(s, px, py, Brain.BACK, dt)
  else
    s.facing = turn(s.facing, s.post.watch, Brain.TURN * 0.5, dt)
  end
end

--- The enforcer whose body covers (x, y) (within `radius` more), and his index.
function Brain:at(x, y, radius)
  local r = Brain.RADIUS + (radius or 0)
  for i, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= r * r then
      return s, i
    end
  end
  return nil
end

--- Does his shield stop a round travelling along `angle`, of `dtype`?
--- Only one coming at him from in front, and not a blast or fire.
function Brain.blocks(s, angle, dtype)
  if not angle or Brain.THROUGH[dtype or ""] then
    return false
  end
  local towards = angle + math.pi -- the way back to whoever fired it
  return math.abs(Sight.angleDiff(towards, s.facing)) <= Brain.SHIELD
end

--- Take `amount` off `s` (index `i`), hit by a round going along `angle`.
--- Returns true when that put him down (and he is off the list). Hit from
--- where he wasn't looking, he turns to look that way.
function Brain:hurt(s, i, amount, angle)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    return true
  end
  if angle and not s.target then
    local back = angle + math.pi
    s.lastX, s.lastY = s.x + math.cos(back) * 300, s.y + math.sin(back) * 300
    s.searchFor = Brain.SEARCH
  end
  return false
end

--- Stop every one within `radius` of (x, y) for `seconds`.
function Brain:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Something frightening at (x, y): those near turn to face it.
function Brain:scare(x, y, radius)
  for _, s in ipairs(self.list) do
    if not s.target and dist2(s.x, s.y, x, y) <= radius * radius then
      s.lastX, s.lastY, s.searchFor = x, y, Brain.SEARCH
    end
  end
end

return Brain
