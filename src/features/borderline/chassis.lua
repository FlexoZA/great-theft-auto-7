-- The body every hauler shares, on the host (docs/borderline.md, "The
-- army"): what walks, looks, shoots and falls apart. The thinking is each
-- model's own brain (junk_brain.lua, gun_brain.lua, ...), which steers the
-- body with the helpers here; army.lua puts them on the map and shows them.
--
-- A roster (`Chassis.new`) is every hauler on a level: `add` one with its
-- brain, `update` runs them all, `at` and `hurt` are for rounds coming in.
--
-- The torso crawl: a hauler with legs that takes a killing hit, one time in
-- `Chassis.CRAWL_CHANCE`, loses its legs instead of dying. It drags itself
-- on (half its health back, half its speed) and keeps shooting for
-- `Chassis.CRAWL_FOR` seconds, then gives out; a hit finishes it sooner.
-- Whoever hit it last gets the kill either way.
--
-- Hyperbole's rounds carry the army's name (weapons' `from`), and an
-- ownerless round or blast (by 0) passes through every hauler, so they never
-- hurt each other.

local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Look = require("src.features.borderline.hauler_look")

local Chassis = {}
Chassis.__index = Chassis

Chassis.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)
Chassis.REPATH = 0.6 -- seconds between new paths
Chassis.TURN = 4 -- rad/s
Chassis.MUZZLE = 16 -- px in front of it its rounds leave from
Chassis.CRAWL_CHANCE = 1 / 3
Chassis.CRAWL_FOR = 4 -- seconds a torso drags itself on
Chassis.CRAWL_SPEED = 0.5 -- of its walk

local random = love.math.random

function Chassis.dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function Chassis.between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- The shortest signed turn from heading `from` to heading `to`.
function Chassis.turnBetween(from, to)
  local d = to - from
  return math.atan2(math.sin(d), math.cos(d))
end

function Chassis.turn(from, to, rate, dt)
  local d = Chassis.turnBetween(from, to)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- Is (x, y) in a wall, or anywhere feet can't go (the Refinery's river)?
function Chassis.blocked(x, y)
  return Features.any("blocksPoint", x, y)
end

--- Can a body of radius `r` stand at (x, y)?
function Chassis.fits(x, y, r)
  local b = Chassis.blocked
  return not (b(x, y) or b(x - r, y) or b(x + r, y) or b(x, y - r) or b(x, y + r))
end

--- (x, y) if a hauler fits there, else the nearest spot round it that it
--- does (a post drawn against a container stands beside it).
function Chassis.clearSpot(x, y, r)
  if Chassis.fits(x, y, r) then
    return x, y
  end
  for ring = 1, 8 do
    for k = 0, 11 do
      local a = k * math.pi / 6
      local cx, cy = x + math.cos(a) * ring * 16, y + math.sin(a) * ring * 16
      if Chassis.fits(cx, cy, r) then
        return cx, cy
      end
    end
  end
  return x, y
end

local guns = {}
--- A hauler's gun: `base` (a key of weapons' guns), common, with `numbers`
--- over it. Made once per model (`code`).
function Chassis.gun(code, base, numbers)
  if not guns[code] then
    guns[code] = setmetatable(numbers, { __index = Tiers.apply(Guns[base], Tiers.DEFAULT) })
  end
  return guns[code]
end

--- A roster for a level. `opts`: nav (the level's walking grid), from (the
--- army's name on its rounds), firstId.
function Chassis.new(opts)
  return setmetatable({ list = {}, nav = opts.nav, from = opts.from, nextId = opts.firstId or 1, tick = 0, time = 0 },
    Chassis)
end

--- A hauler of model `code`, thought for by `brain` (its module), at (x, y)
--- facing `facing`. Its numbers (health, speed, range...) are the brain's
--- `CONF`.
function Chassis:add(brain, code, x, y, facing)
  local conf = brain.CONF
  local r = brain.RADIUS or Look.radius(code)
  x, y = Chassis.clearSpot(x, y, r)
  local hp = Bosses.enemyHealth(conf.health) -- tougher on a job done before
  local s = {
    id = self.nextId, code = code, brain = brain, conf = conf, radius = r,
    x = x, y = y, homeX = x, homeY = y, facing = facing or 0, watch = facing or 0,
    hp = hp, max = hp, state = "calm", t = 0, look = self.nextId, stride = 0, frozen = 0,
    target = nil, lostFor = 0, fireIn = 0, aimFor = 0, left = 0, pathIn = 0,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  if brain.init then
    brain.init(s)
  end
  return s
end

-- Walking ----------------------------------------------------------------------

--- Step `s` by (mx, my), sliding along a wall it would walk into.
function Chassis.move(s, mx, my)
  local r = s.radius
  if Chassis.fits(s.x + mx, s.y + my, r) then
    s.x, s.y = s.x + mx, s.y + my
  elseif Chassis.fits(s.x + mx, s.y, r) then
    s.x = s.x + mx
  elseif Chassis.fits(s.x, s.y + my, r) then
    s.y = s.y + my
  else
    return false
  end
  s.stride = s.stride + math.sqrt(mx * mx + my * my)
  return true
end

--- `s` heads for (x, y) at `speed`: straight there when the way is clear,
--- else along a path on the walking grid. Returns the distance left. With
--- `look` false it doesn't turn to where it walks (it is watching somebody).
function Chassis:goTo(s, x, y, speed, dt, look)
  local gx, gy = x, y
  if self.nav and not self.nav:clear(s.x, s.y, x, y) then
    s.pathIn = s.pathIn - dt
    if not s.path or s.pathIn <= 0 then
      s.path, s.step, s.pathIn = self.nav:path(s.x, s.y, x, y), 1, Chassis.REPATH
    end
    local p = s.path and s.path[s.step]
    while p and Chassis.dist2(s.x, s.y, p.x, p.y) < 16 * 16 do
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
  if d >= 1 then
    if look ~= false then
      s.facing = Chassis.turn(s.facing, math.atan2(dy, dx), Chassis.TURN, dt)
    end
    local k = math.min(d, speed * dt) / d
    Chassis.move(s, dx * k, dy * k)
  end
  return math.sqrt(Chassis.dist2(s.x, s.y, x, y))
end

-- Hitting -----------------------------------------------------------------------

--- A boss's slam (Wilbur's landing, the Knuckle Scrapper's swing and its
--- scrap): everyone within `radius` of (x, y) takes `damage` (`impact`) and is
--- thrown `shove` px out from it. With `facing` and `half`, only those
--- within `half` radians of `facing` (a swing's arc). Returns how many it caught.
function Chassis.slam(server, x, y, radius, damage, shove, facing, half)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  local caught = 0
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local a = math.atan2(py - y, px - x)
      if Chassis.dist2(px, py, x, y) <= radius * radius
        and not (facing and math.abs(Chassis.turnBetween(facing, a)) > half) then
        caught = caught + 1
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, math.floor(damage + 0.5), a, "impact")
        end
        if onFoot and onFoot.serverShove then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), shove, 0.35)
        end
      end
    end
  end
  return caught
end

-- Seeing ------------------------------------------------------------------------

--- Is player `p` in the game and seen (not hidden, not dead)?
function Chassis.visible(server, p)
  return Features.visible(server, p)
end

--- Where player `p` is (driving or walking).
function Chassis.pose(server, p)
  return Features.bodyPose(server, p)
end

--- Where player `who` is, if still about.
function Chassis.poseOf(server, who)
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- Is the line from (x0, y0) to (x1, y1) clear of anything a round or a
--- look stops at (every feature's `blocksShot`)? Sampled every 12 px.
function Chassis.lineClear(x0, y0, x1, y1)
  local len = math.sqrt(Chassis.dist2(x0, y0, x1, y1))
  local steps = math.floor(len / 12)
  for k = 1, steps do
    local f = k / (steps + 1)
    if Features.any("blocksShot", x0 + (x1 - x0) * f, y0 + (y1 - y0) * f) then
      return false
    end
  end
  return true
end

--- Does `s` see (x, y): within `range`, inside its cone `fov` wide round its
--- facing, nothing in between? Returns the squared distance when it does.
function Chassis.sees(s, x, y, range, fov)
  local d2 = Chassis.dist2(s.x, s.y, x, y)
  if d2 > range * range then
    return nil
  end
  local off = math.abs(Chassis.turnBetween(s.facing, math.atan2(y - s.y, x - s.x)))
  if off > fov / 2 or not Chassis.lineClear(s.x, s.y, x, y) then
    return nil
  end
  return d2
end

--- Who `s` notices: the nearest visible player in its cone, or close
--- enough all round (its `aware`) to hear.
function Chassis.spot(server, s, fov)
  local nearest, nearestD2 = nil, math.huge
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = Chassis.sees(s, px, py, s.conf.range, fov) or Chassis.sees(s, px, py, s.conf.aware, 2 * math.pi + 1)
      if d2 and d2 < nearestD2 then
        nearest, nearestD2 = id, d2
      end
    end
  end
  return nearest
end

--- Keep `s`'s target up to date, a few times a second. Returns where its
--- target is while it can see them (else nil), and true the moment it first
--- spots somebody.
function Chassis:track(server, s, fov, dt)
  local fresh = false
  if (self.tick + s.look) % Chassis.LOOK_EVERY == 0 and not s.target then
    local who = Chassis.spot(server, s, fov)
    if who then
      s.target, s.lostFor, s.aimFor = who, 0, 0
      fresh = true
    end
  end
  if not s.target then
    return nil, nil, false
  end
  local tx, ty = Chassis.poseOf(server, s.target)
  if tx and Chassis.lineClear(s.x, s.y, tx, ty) and Chassis.dist2(s.x, s.y, tx, ty) <= s.conf.range * s.conf.range then
    s.lostFor, s.seenX, s.seenY = 0, tx, ty
    return tx, ty, fresh
  end
  s.lostFor = s.lostFor + dt
  if s.lostFor > (s.conf.lostAfter or 2.5) or not tx then
    s.target = nil
  end
  return nil, nil, fresh
end

-- Shooting -----------------------------------------------------------------------

--- Fire `gun` once from `s`'s muzzle along `aim`.
function Chassis:fire(server, s, aim, gun)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    local m = Chassis.MUZZLE * (s.radius / 13)
    weapons:serverFireFrom(server, 0, s.x + math.cos(aim) * m, s.y + math.sin(aim) * m, aim, gun, self.from)
  end
end

--- `s`'s trigger with somebody at (tx, ty) in sight, from its conf: `aim`
--- seconds on target first, then bursts of `burst` rounds `every` apart and
--- a `pause` between bursts. `gun` is a weapons gun, or a function
--- (server, s, aim) that fires something of the brain's own (a bolt).
function Chassis:shoot(server, s, tx, ty, gun, dt)
  local conf = s.conf
  local aim = math.atan2(ty - s.y, tx - s.x)
  s.facing = Chassis.turn(s.facing, aim, Chassis.TURN, dt)
  if math.abs(Chassis.turnBetween(s.facing, aim)) > 0.3 then
    return
  end
  s.aimFor = s.aimFor + dt
  if s.aimFor < conf.aim then
    return
  end
  s.fireIn = s.fireIn - dt
  if s.fireIn > 0 then
    return
  end
  if type(gun) == "function" then
    gun(server, s, s.facing)
  else
    self:fire(server, s, s.facing, gun)
  end
  s.left = s.left - 1
  if s.left > 0 then
    s.fireIn = conf.every
  else
    s.left = conf.burst
    s.fireIn = conf.every + Chassis.between(conf.pause)
  end
end

-- Waking ------------------------------------------------------------------------

--- Something worth a look at (x, y) (one of the army saw somebody there):
--- `s`, if it has nobody of its own, goes to see.
function Chassis.wake(s, x, y)
  if not s.target then
    s.seenX, s.seenY, s.state, s.t = x, y, "search", 0
  end
end

--- Shot along `angle` by somebody `s` hadn't seen: it turns round, goes
--- `reach` px back the way the round came, and calls the rest
--- (army.lua reads `spotted`).
function Chassis.shotFromNowhere(s, angle, reach)
  if angle and not s.target then
    s.facing = angle + math.pi
    Chassis.wake(s, s.x - math.cos(angle) * reach, s.y - math.sin(angle) * reach)
    s.spotted = true
  end
end

-- Running them -------------------------------------------------------------------

--- A torso dragging itself after whoever it can see, shooting.
local function crawl(self, server, s, dt)
  s.crawlFor = s.crawlFor - dt
  local tx, ty = self:track(server, s, math.pi, dt)
  if tx then
    if Chassis.dist2(s.x, s.y, tx, ty) > 160 * 160 then
      self:goTo(s, tx, ty, s.conf.speed * Chassis.CRAWL_SPEED, dt, false)
    end
    if s.brain.gun then -- (a dozer has nothing to shoot: it just drags itself at you)
      self:shoot(server, s, tx, ty, s.brain.gun(), dt)
    end
  end
end

--- Run every hauler a tick. Returns the ones whose crawl gave out this
--- tick (dead now: army.lua drops them).
function Chassis:update(server, dt)
  self.tick, self.time = self.tick + 1, self.time + dt
  local spent = {}
  for i = #self.list, 1, -1 do
    local s = self.list[i]
    s.t = s.t + dt
    if s.frozen > 0 then
      s.frozen, s.target = s.frozen - dt, nil
    elseif s.crawl then
      crawl(self, server, s, dt)
      if s.crawlFor <= 0 then
        table.remove(self.list, i)
        spent[#spent + 1] = s
      end
    else
      s.brain.think(self, server, s, dt)
    end
  end
  return spent
end

--- The hauler whose body covers (x, y) (within `radius` more), and its
--- index. One in the air (a jet hauler's run) or sunk in the floor (a
--- sentry, down) is out of reach.
function Chassis:at(x, y, radius)
  for i, s in ipairs(self.list) do
    local r = s.radius + (radius or 0)
    if not (s.flying or s.sunk) and Chassis.dist2(s.x, s.y, x, y) <= r * r then
      return s, i
    end
  end
  return nil
end

--- `amount` into `s` (index `i`) from player `by`, along `angle` (through
--- its bubble first, if a shield drone gave it one). Returns
--- "down" when that finished it (it is off the list), "crawl" when it lost
--- its legs instead, or nil.
function Chassis:hurt(s, i, amount, by, angle)
  if s.shield then -- a shield drone's bubble takes it first
    local stopped = math.min(s.shield, amount)
    s.shield, amount = s.shield - stopped, amount - stopped
    if s.shield <= 0 then
      s.shield = nil
    end
  end
  s.hp = s.hp - amount
  s.lastBy = by
  if s.hp > 0 then
    if s.brain.hurt then
      s.brain.hurt(self, s, angle)
    end
    return nil
  end
  if not s.crawl and s.brain.LEGS and random() < Chassis.CRAWL_CHANCE then
    s.crawl, s.crawlFor = true, Chassis.CRAWL_FOR
    s.hp = math.floor(s.max / 2 + 0.5)
    return "crawl"
  end
  table.remove(self.list, i)
  return "down"
end

--- Where `s` is in the list now, or nil once it is gone.
function Chassis:indexOf(s)
  for i, o in ipairs(self.list) do
    if o == s then
      return i
    end
  end
  return nil
end

--- A freeze over (x, y): everyone on the ground within `radius` stands
--- stiff for `seconds` (one in the air, out of reach, is not caught).
function Chassis:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if not s.flying and Chassis.dist2(s.x, s.y, x, y) <= radius * radius then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

return Chassis
