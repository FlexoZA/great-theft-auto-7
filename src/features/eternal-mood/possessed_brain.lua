-- How the possessed think (docs/eternal-mood.md, "The possessed"): the
-- UAC's staff, Heck's now, its lowest armed rank. horde.lua puts them on the
-- map and draws them; this is only their heads, on the host. They fight the
-- way City 17's Combine do (a-man/combine.lua, ported here into a brain of
-- their own), each rank as much of it as suits it (`Brain.RANKS`):
--
--   staffer   still mostly at work: shambles at whoever it sees and fires its
--             pistol now and then. No cover, no tactics; it answers an
--             alarm and goes with its squad.
--   guard     the UAC's security, and the one that fights smart. Posted, it
--             sweeps its cone across the doorway it watches; in a fight it
--             fights from cover (ducks behind something solid, steps out to
--             shoot, ducks back); shot at by somebody it can't see it goes
--             to ground and, after a while, out to sweep where it came from;
--             some carry a grenade.
--   overtime  the big man with the chaingun: holds his ground near his post
--             and fights from cover, spinning up each time he steps out; he
--             goes to ground with the rest, but never out on a sweep.
--
-- Everyone: a cone in front (wider once on edge) and a little all round;
-- spotting somebody, it groans (`call`: horde.lua tells the possessed near
-- it to come and look); one of them going down raises the alarm round where
-- he fell. Lose whoever it had and it goes to where it last saw them, looks
-- about, then back to its post or its squad. A squad (`addSquad`) walks a
-- beat (a loop of { x, y }) behind its leader, the rest a step behind him
-- either side; when one of them has somebody the rest go with him.
--
-- They are Heck's: their rounds carry the horde's name (weapons' `from`),
-- and pass through the rest of it; so do their grenades.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local Brain = {}
Brain.__index = Brain

Brain.RADIUS = 9 -- px
Brain.MUZZLE = 14 -- px in front of it its rounds leave from
Brain.LOOK_EVERY = 3 -- host ticks between sight checks (staggered)
Brain.LOST_AFTER = 2.5 -- seconds without seeing whoever it had before it goes looking
Brain.SEARCH = 6 -- seconds it looks about where it lost them before going back
Brain.CALL = 380 -- px; the horde this near hears it groan, and comes to look
Brain.ALARM = 520 -- px; one going down sends those this near to look where he fell
Brain.REPATH = 0.6 -- seconds between new paths
Brain.TURN = 3.5 -- rad/s
Brain.TRACK = math.rad(40) -- once it has somebody it keeps them in a cone this much wider
Brain.SWEEP = math.rad(55) -- a posted guard's cone swings this far either side of its watch...
Brain.SWEEP_TIME = 6 -- ...there and back in this many seconds
Brain.SCAN = math.rad(20) -- one walking looks this far either side of its way
Brain.PATROL_WALK = 45 -- px/s a squad walks its beat
Brain.FORMATION = { { 0, 0 }, { -38, -30 }, { -38, 30 }, { -76, 0 } } -- slots behind the leader, his frame
Brain.COVER_RANGE = 170 -- px from its place it goes for cover
Brain.HIDE = { 1.2, 2.6 } -- seconds in cover between one look out and the next
Brain.PEEK = { 1.4, 2.2 } -- seconds out shooting before it ducks back
Brain.PEEK_REACH = 90 -- px from its cover it steps out to shoot from
Brain.THREAT_KEEP = 10 -- seconds it keeps to cover after it last saw or felt anyone
Brain.PIN_SHARE = 400 -- px; those this near one shot by somebody unseen go to ground with it
Brain.PIN_GUESS = 420 -- px back along the round they reckon the shooter is
Brain.QUIET = 8 -- seconds without a round from out there before a sweep goes out
Brain.RELEASE = 30 -- seconds without one before everyone pinned gets up
Brain.SWEEP_SQUAD = 3 -- guards to a sweep, at most
Brain.SPOT_SHARE = 900 -- px; a siege this near whoever gets the shooter in sight is over
Brain.GRENADE_MIN = 140 -- px; no nearer than this
Brain.GRENADE_EVERY = 20 -- seconds between one throw and the next
Brain.GRENADE_ROLL = { 2, 0.12 } -- every this many seconds it has somebody in range, this chance it throws
Brain.LOST_THROW = 4 -- seconds after losing somebody that it may lob one at where they were
Brain.SPLASH_CLEAR = 120 -- px; none of the horde this near where it would land

-- Each rank: health, the gun (a base and what is changed on it), how it
-- fires (`aim` seconds on a target before the first round, then `burst`
-- rounds `every` apart and a `pause`, `spinUp` for the chaingun), how far it
-- sees and shoots, its cone calm and on edge, the range it closes to, how
-- fast it walks, how far from its post it will go (`leash`, nil for
-- anywhere), and what it knows: `sweeps` (its cone, posted), `cover` (fights
-- from cover), `pins` (goes to ground when sniped), `sweepsOut` (goes out on
-- a sweep after), `holds` (never chases: fights from round its post),
-- `grenadier` (the share that carry a grenade).
Brain.RANKS = {
  staffer = {
    health = 40, base = "pistol", gun = { damage = 8, spread = 0.10 },
    aim = 0.7, burst = 1, every = 0.4, pause = { 1.2, 1.9 },
    fov = math.rad(70), alertFov = math.rad(90), aware = 140, range = 520, close = 260, speed = 60, walk = 40,
  },
  guard = {
    health = 60, base = "shotgun", gun = { damage = 7, pellets = 6, spread = 0.15 },
    aim = 0.5, burst = 1, every = 0.4, pause = { 1.4, 1.9 },
    fov = math.rad(80), alertFov = math.rad(110), aware = 160, range = 400, close = 200, speed = 75, walk = 45,
    leash = 560, sweeps = true, cover = true, pins = true, sweepsOut = true, grenadier = 0.35,
  },
  overtime = {
    health = 100, base = "minigun", gun = { damage = 6, spread = 0.08 },
    aim = 0, spinUp = 0.6, burst = 1, every = 0.125, pause = { 0, 0 },
    fov = math.rad(80), alertFov = math.rad(100), aware = 180, range = 650, close = 420, speed = 35, walk = 30,
    leash = 260, cover = true, pins = true, holds = true,
    turn = 1.6, -- rad/s: he sweeps after you, he doesn't snap
  },
}

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

local guns = {}
--- Rank `rank`'s gun: its base gun, common, with the rank's numbers on it.
local function gunOf(rank)
  if not guns[rank] then
    local conf = Brain.RANKS[rank]
    local base = Tiers.apply(Guns[conf.base], Tiers.DEFAULT)
    guns[rank] = setmetatable(conf.gun, { __index = base })
  end
  return guns[rank]
end

--- A new brain. `opts`: nav, firstId, from (the horde's name on its rounds),
--- and `call(x, y, tx, ty)`: one of them has spotted somebody at (tx, ty)
--- from (x, y) (horde.lua tells the rest of the horde).
function Brain.new(opts)
  return setmetatable({
    list = {},
    nav = opts.nav,
    from = opts.from,
    call = opts.call,
    nextId = opts.firstId or 1,
    tick = 0,
    time = 0,
    sieges = {},
  }, Brain)
end

--- One of rank `rank` at its post (x, y), facing `watch`.
function Brain:add(rank, x, y, watch)
  local conf = Brain.RANKS[rank]
  local s = {
    id = self.nextId,
    rank = rank,
    conf = conf,
    x = x,
    y = y,
    postX = x,
    postY = y,
    watch = watch or 0,
    facing = watch or 0,
    phase = random() * 2 * math.pi,
    hp = conf.health,
    state = "post", -- post or beat, hunt, search, back
    t = 0,
    target = nil,
    lostFor = 0,
    seenX = nil,
    seenY = nil,
    aimFor = 0, -- seconds on its target so far
    fireIn = 0,
    left = 0, -- rounds left in this burst
    spun = 0, -- the chaingun's wind-up, seconds
    grenades = random() < (conf.grenadier or 0) and 1 or 0,
    path = nil,
    step = 1,
    pathIn = 0,
    frozen = 0,
    look = self.nextId,
    stride = 0,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- A squad of `ranks` (a list, the first leads) walking `route` (a loop of
--- { x, y }) from corner `start`, in formation.
function Brain:addSquad(route, ranks, start)
  start = start or 1
  local from = route[start]
  local leg = start % #route + 1
  local to = route[leg]
  local heading = math.atan2(to.y - from.y, to.x - from.x)
  local squad = { route = route, leg = leg, members = {} }
  local c, sn = math.cos(heading), math.sin(heading)
  for i, rank in ipairs(ranks) do
    local slot = Brain.FORMATION[(i - 1) % #Brain.FORMATION + 1]
    local x, y = from.x + slot[1] * c - slot[2] * sn, from.y + slot[1] * sn + slot[2] * c
    if Sight.blocked(x, y) then -- (its slot in a wall: it starts on the leader's spot and falls in)
      x, y = from.x, from.y
    end
    local s = self:add(rank, x, y, heading)
    s.squad, s.state = squad, "beat"
    squad.members[i] = s
  end
  return squad
end

-- Walking ----------------------------------------------------------------------

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
  else
    return false
  end
  s.stride = s.stride + math.sqrt(mx * mx + my * my)
  return true
end

--- `s` heads for (x, y) at `speed`: straight there when it can see it,
--- else along a path on the walking grid. Returns the distance left and
--- the way it is going. `look` false: it doesn't face where it walks (it is
--- watching somebody).
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
    return math.sqrt(dist2(s.x, s.y, x, y)), nil
  end
  local way = math.atan2(dy, dx)
  if look ~= false then
    s.facing = turn(s.facing, way, s.conf.turn or Brain.TURN, dt)
  end
  local k = math.min(d, speed * dt) / d
  move(s, dx * k, dy * k)
  return math.sqrt(dist2(s.x, s.y, x, y)), way
end

local function enter(s, state)
  s.state, s.t = state, 0
end

-- Seeing ---------------------------------------------------------------------

--- Is `s` on edge (somebody in its sights, out looking, in cover, pinned)?
local function wary(s)
  return s.target ~= nil or s.state == "search" or s.cv ~= nil or s.pin ~= nil
end

--- Where player `who` is, if still about.
local function poseOf(server, who)
  local p = server.players[who]
  if p and Features.visible(server, p) then
    return Features.bodyPose(server, p)
  end
  return nil
end

--- The nearest player `s` can see in `fov`, or is close enough to hear.
local function spot(server, s, fov)
  local best, bestD
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, s.conf.range, fov)
        or Sight.canSee(s.x, s.y, s.facing, x, y, s.conf.aware, 2 * math.pi)
      if d2 and (not bestD or d2 < bestD) then
        best, bestD = id, d2
      end
    end
  end
  return best
end

--- How wide `s`'s cone is right now: wider once it is on edge.
function Brain.fovOf(s)
  return wary(s) and s.conf.alertFov or s.conf.fov
end

-- Shooting -------------------------------------------------------------------

--- Fire one round (or one shotgun pull) along `aim`.
local function fire(self, server, s, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local mx, my = s.x + math.cos(aim) * Brain.MUZZLE, s.y + math.sin(aim) * Brain.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, gunOf(s.rank), self.from)
end

--- Its trigger, with somebody at (tx, ty) in sight: round to them, a moment
--- to aim (or the chaingun's wind-up), then its bursts.
local function shoot(self, server, s, tx, ty, dt)
  local conf = s.conf
  local aim = math.atan2(ty - s.y, tx - s.x)
  s.facing = turn(s.facing, aim, conf.turn or Brain.TURN, dt)
  if math.abs(Sight.angleDiff(aim, s.facing)) > 0.35 then
    return -- not round to them yet
  end
  if conf.spinUp then
    if s.spun < conf.spinUp then
      s.spinning = s.spun == 0 -- horde.lua: the wind-up's sound, once
      s.spun = s.spun + dt
      return
    end
  else
    s.aimFor = s.aimFor + dt
    if s.aimFor < conf.aim then
      return
    end
  end
  s.fireIn = s.fireIn - dt
  if s.fireIn > 0 then
    return
  end
  fire(self, server, s, s.facing)
  s.left = s.left - 1
  if s.left > 0 then
    s.fireIn = conf.every
  else
    s.left = conf.burst
    s.fireIn = conf.every + between(conf.pause)
  end
end

--- Maybe a grenade from `s`: at whoever it has at (tx, ty) now and then, or
--- with nobody in sight at where it lost somebody a moment ago. Never too
--- near, past its range, short of them behind a wall, or onto the horde.
function Brain:maybeLob(server, s, tx, ty, dt)
  if s.grenades < 1 or s.pin or self.time < (s.lobAt or 0) then
    return
  end
  local G = Features.byName.grenades
  if not (G and G.serverLob) then
    return
  end
  local x, y
  if tx then
    s.lobRoll = (s.lobRoll or 0) - dt
    if s.lobRoll > 0 then
      return
    end
    s.lobRoll = Brain.GRENADE_ROLL[1]
    if random() >= Brain.GRENADE_ROLL[2] then
      return
    end
    x, y = tx, ty
  elseif s.lostAt and self.time - s.lostAt < Brain.LOST_THROW and s.seenX then
    x, y = s.seenX, s.seenY
  else
    return
  end
  s.lostAt = nil -- one try at where they went
  local d2 = dist2(s.x, s.y, x, y)
  if d2 < Brain.GRENADE_MIN * Brain.GRENADE_MIN or d2 > G.range * G.range then
    return
  end
  local lx, ly = G.landing(s.x, s.y, x, y)
  if dist2(lx, ly, x, y) > (G.blast.radius * 0.6) ^ 2 then
    return
  end
  for _, m in ipairs(self.list) do
    if dist2(m.x, m.y, lx, ly) < Brain.SPLASH_CLEAR * Brain.SPLASH_CLEAR then
      return
    end
  end
  if G:serverLob(server, s.x, s.y, x, y) then
    s.grenades, s.lobAt, s.threw = s.grenades - 1, self.time + Brain.GRENADE_EVERY, true
    s.fireIn = math.max(s.fireIn, 0.5)
  end
end

-- Fighting from cover --------------------------------------------------------

--- Somewhere open within `reach` of (cx, cy), reached in a straight line
--- from (fx, fy), that `ok(x, y)` likes; the one nearest (fx, fy) plus
--- `pull` times its distance from (cx, cy).
local function search(cx, cy, reach, fx, fy, pull, ok)
  local best, bestScore
  for ring = 0, 6 do
    local d = ring / 6 * reach
    local n = ring == 0 and 1 or 12
    for k = 1, n do
      local a = k / n * 2 * math.pi + ring * 0.4
      local x, y = cx + math.cos(a) * d, cy + math.sin(a) * d
      if fits(x, y) and Sight.clear(fx, fy, x, y) and ok(x, y) then
        local score = math.sqrt(dist2(x, y, fx, fy)) + pull * d
        if not bestScore or score < bestScore then
          best, bestScore = { x = x, y = y }, score
        end
      end
    end
  end
  return best
end

--- Somewhere near (x, y) with something solid between it and `th`.
local function coverNear(x, y, th)
  return search(x, y, Brain.COVER_RANGE, x, y, 0.5, function(cx, cy)
    return not Sight.clear(th.x, th.y, cx, cy)
  end)
end

--- Somewhere a step out from its cover it can see the threat from.
local function peekFrom(s, th)
  return search(s.x, s.y, Brain.PEEK_REACH, s.x, s.y, 0, function(x, y)
    return Sight.clear(x, y, th.x, th.y)
  end)
end

--- Walk straight to `to` (a step away) at `speed`; true while still on its way.
local function stepTo(s, to, speed, dt)
  if not to or dist2(s.x, s.y, to.x, to.y) <= 5 * 5 then
    return false
  end
  local a = math.atan2(to.y - s.y, to.x - s.x)
  move(s, math.cos(a) * speed * dt, math.sin(a) * speed * dt)
  return true
end

--- A rank that fights from cover, with somebody to fight: in and out of
--- cover near where it is (round its post for one that holds), shooting
--- whenever it has them. Returns false once the threat is old.
function Brain:fightFromCover(server, s, tx, ty, dt)
  local now, conf = self.time, s.conf
  if tx then
    s.threat = { x = tx, y = ty, untilT = now + Brain.THREAT_KEEP }
  end
  local th = s.threat
  if not th or now > th.untilT then
    s.threat, s.cv = nil, nil
    return false
  end
  local cv = s.cv
  if not cv then
    local hx, hy = conf.holds and s.postX or s.x, conf.holds and s.postY or s.y
    cv = { phase = "hide", t = 0, hideFor = between(Brain.HIDE) * 0.5, spot = coverNear(hx, hy, th) }
    s.cv, s.tookCover = cv, true
  end
  cv.t = cv.t + dt
  local look = math.atan2((ty or th.y) - s.y, (tx or th.x) - s.x)
  if cv.phase == "hide" then
    if stepTo(s, cv.spot, conf.speed, dt) then
      cv.t = 0 -- the wait starts once it is behind it
      s.facing = turn(s.facing, look, (conf.turn or Brain.TURN) * 1.5, dt)
      return true
    end
    s.facing = turn(s.facing, look, conf.turn or Brain.TURN, dt)
    s.spun = math.max(0, s.spun - dt) -- the barrels run down behind cover
    if tx then -- its cover doesn't hide it from this one: shoot back
      shoot(self, server, s, tx, ty, dt)
    end
    if cv.t >= cv.hideFor then
      cv.phase, cv.t, cv.peekFor, cv.peek = "peek", 0, between(Brain.PEEK), peekFrom(s, th)
      s.aimFor = 0 -- a moment to bring the gun up
    end
    return true
  end
  local stepping = stepTo(s, cv.peek, conf.speed, dt)
  if tx then
    shoot(self, server, s, tx, ty, dt)
  else
    s.facing = turn(s.facing, look, conf.turn or Brain.TURN, dt)
  end
  if not stepping and (cv.t >= cv.peekFor or cv.ducking) then
    cv.phase, cv.t, cv.ducking = "hide", 0, nil
    cv.hideFor = between(Brain.HIDE)
    cv.spot = coverNear(s.x, s.y, th) or cv.spot
    s.tookCover = true
  end
  return true
end

-- Pinned down ----------------------------------------------------------------

--- A round from somebody nobody saw hit (x, y), flying `angle`: those near
--- it who know to (`pins`) and have nobody in sight go to ground, in the
--- siege already there or a new one, and the quiet starts again.
function Brain:underFire(x, y, angle, hit)
  local r2 = Brain.PIN_SHARE * Brain.PIN_SHARE
  local siege = nil
  for _, sg in ipairs(self.sieges) do
    if dist2(sg.at.x, sg.at.y, x, y) <= r2 then
      siege = sg
      break
    end
  end
  if not siege then
    siege = { members = {}, quiet = 0, at = { x = x, y = y } }
    self.sieges[#self.sieges + 1] = siege
  end
  siege.x, siege.y = x - math.cos(angle) * Brain.PIN_GUESS, y - math.sin(angle) * Brain.PIN_GUESS
  siege.quiet = 0
  for _, s in ipairs(self.list) do
    if s.pin == siege then
      if s == hit then
        s.pinCover = nil -- they can reach it there: somewhere else
      end
    elseif s.conf.pins and not s.target and s.frozen <= 0 and dist2(s.x, s.y, x, y) <= r2 then
      s.pin, s.pinCover, s.cv, s.tookCover = siege, nil, nil, true
      siege.members[#siege.members + 1] = s
    end
  end
end

--- A pinned one's tick: to its cover, then down there watching the way the
--- rounds came from.
function Brain:holdDown(s, dt)
  local sg = s.pin
  if not s.pinCover then
    s.pinCover = coverNear(s.x, s.y, sg) or { x = s.x, y = s.y }
  end
  if stepTo(s, s.pinCover, s.conf.speed, dt) then
    s.facing = turn(s.facing, math.atan2(s.pinCover.y - s.y, s.pinCover.x - s.x), Brain.TURN * 2, dt)
    return
  end
  local look = math.atan2(sg.y - s.y, sg.x - s.x) + Brain.SCAN * math.sin(self.time * 0.8 + s.phase)
  s.facing = turn(s.facing, look, Brain.TURN, dt)
end

--- The siege is over: the pinned get up; with the shooter seen at (tx,
--- ty), those who go out after people go there, the rest back.
function Brain:release(sg, tx, ty)
  for _, m in ipairs(sg.members) do
    if m.pin == sg then
      m.pin, m.pinCover = nil, nil
      if tx and not m.conf.holds then
        self:alert(m, tx, ty)
      else
        enter(m, m.squad and "beat" or "back")
      end
    end
  end
end

--- QUIET is up: out to look round where the rounds came from. The guards
--- among the pinned, nearest first, up to SWEEP_SQUAD; the first says so.
function Brain:sendSweep(sg)
  local pool = {}
  for _, m in ipairs(sg.members) do
    if m.pin == sg and m.conf.sweepsOut then
      pool[#pool + 1] = { s = m, d2 = dist2(m.x, m.y, sg.x, sg.y) }
    end
  end
  table.sort(pool, function(a, b)
    return a.d2 < b.d2
  end)
  for i, c in ipairs(pool) do
    if i > Brain.SWEEP_SQUAD then
      break
    end
    local m = c.s
    m.pin, m.pinCover = nil, nil
    local a = (i - 1) * 2 * math.pi / Brain.SWEEP_SQUAD
    local off = i > 1 and 50 or 0
    self:alert(m, sg.x + math.cos(a) * off, sg.y + math.sin(a) * off)
    m.sentOut = i == 1 -- horde.lua: it says so
  end
end

--- `by` has somebody in sight at (tx, ty): every siege near it is over.
function Brain:spotted(by, tx, ty)
  local r2 = Brain.SPOT_SHARE * Brain.SPOT_SHARE
  for i = #self.sieges, 1, -1 do
    local sg = self.sieges[i]
    local near = dist2(sg.at.x, sg.at.y, by.x, by.y) <= r2
    for _, m in ipairs(sg.members) do
      near = near or dist2(m.x, m.y, by.x, by.y) <= r2
    end
    if near then
      self:release(sg, tx, ty)
      table.remove(self.sieges, i)
    end
  end
end

function Brain:stepSieges(dt)
  for i = #self.sieges, 1, -1 do
    local sg = self.sieges[i]
    sg.quiet = sg.quiet + dt
    for k = #sg.members, 1, -1 do
      local m = sg.members[k]
      if m.pin ~= sg or m.hp <= 0 then
        table.remove(sg.members, k)
      end
    end
    if not sg.swept and sg.quiet >= Brain.QUIET then
      sg.swept = true
      self:sendSweep(sg)
    end
    if sg.quiet >= Brain.RELEASE or #sg.members == 0 then
      self:release(sg)
      table.remove(self.sieges, i)
    end
  end
end

-- Thinking ---------------------------------------------------------------------

function Brain:update(server, dt)
  self.tick = self.tick + 1
  self.time = self.time + dt
  for _, s in ipairs(self.list) do
    s.spinning = nil
    if s.frozen > 0 then
      s.frozen = s.frozen - dt
      s.target = nil
    else
      self:think(server, s, dt)
    end
  end
  self:stepSieges(dt)
end

--- Something worth a look at (x, y): `s`, if it has nobody, goes to see
--- (and comes back after).
function Brain:alert(s, x, y)
  if not s.target and not s.pin and dist2(s.x, s.y, x, y) > 1 then
    s.seenX, s.seenY = x, y
    enter(s, "search")
  end
end

--- One of them went down at (x, y): those near enough go to look.
function Brain:alarm(x, y)
  for _, s in ipairs(self.list) do
    if not s.target and not s.pin and not s.conf.holds and dist2(s.x, s.y, x, y) <= Brain.ALARM * Brain.ALARM then
      self:alert(s, x, y)
    end
  end
end

function Brain:think(server, s, dt)
  local conf = s.conf
  s.t = s.t + dt
  -- Look, a few times a second: keep whoever it has while it can, in a
  -- wider eye, else whoever just walked into its cone.
  if (self.tick + s.look) % Brain.LOOK_EVERY == 0 then
    local tx, ty
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    local fov = Brain.fovOf(s)
    local kept = tx and (Sight.canSee(s.x, s.y, s.facing, tx, ty, conf.range, fov + Brain.TRACK)
      or Sight.canSee(s.x, s.y, s.facing, tx, ty, conf.aware, 2 * math.pi))
    if not kept then
      local who = spot(server, s, fov)
      if who and who ~= s.target then
        local fresh = s.target == nil
        s.target, s.lostFor, s.aimFor = who, 0, 0
        local px, py = poseOf(server, who)
        if fresh and px then
          s.spotted = true -- horde.lua: it groans, and says so
          if self.call then
            self.call(s.x, s.y, px, py)
          end
          self:spotted(s, px, py)
        end
      end
    end
  end
  local tx, ty
  if s.target then
    tx, ty = poseOf(server, s.target)
    local seen = tx and Sight.clear(s.x, s.y, tx, ty) and dist2(s.x, s.y, tx, ty) <= conf.range * conf.range
    if seen then
      s.lostFor, s.seenX, s.seenY = 0, tx, ty
    else
      s.lostFor = s.lostFor + dt
      tx, ty = nil, nil
      if s.lostFor > Brain.LOST_AFTER or not poseOf(server, s.target) then
        s.target, s.lostAt, s.left = nil, self.time, 0
        if not conf.cover and s.seenX then
          enter(s, "search")
        end
      end
    end
  end
  if s.pin and not tx then
    self:holdDown(s, dt)
    return
  end
  if conf.cover and (tx or s.threat) then
    if s.target and s.state ~= "hunt" then
      enter(s, "hunt") -- (so every screen sees it on edge)
    end
    if self:fightFromCover(server, s, tx, ty, dt) then
      if tx then
        self:maybeLob(server, s, tx, ty, dt)
      elseif s.lostAt then
        self:maybeLob(server, s, nil, nil, dt)
      end
      return
    end
    -- The threat is old: look where they went, if it goes after people.
    if s.seenX and not conf.holds and s.state ~= "search" then
      enter(s, "search")
    elseif conf.holds and s.state ~= "back" then
      enter(s, "back")
    end
  end
  if s.target then
    if s.state ~= "hunt" then
      enter(s, "hunt")
    end
    self:fight(server, s, tx, ty, dt)
    return
  end
  if s.state == "hunt" then
    enter(s, s.seenX and "search" or (s.squad and "beat" or "back"))
  end
  if s.state == "search" then
    -- To where it last saw them (or heard something), then look about.
    local left = goTo(self, s, s.seenX, s.seenY, conf.speed * 0.8, dt)
    if left < 30 then
      s.facing = s.facing + dt * 1.2
    end
    if s.t > Brain.SEARCH + (left < 30 and 0 or 6) then
      enter(s, s.squad and "beat" or "back")
    end
  elseif s.state == "back" then
    if goTo(self, s, s.postX, s.postY, conf.walk, dt) < 12 then
      enter(s, "post")
    end
  elseif s.state == "beat" then
    self:patrol(s, dt)
  else -- at its post: a guard sweeps its cone across what it watches
    local want = s.watch
    if conf.sweeps then
      want = s.watch + Brain.SWEEP * math.sin(2 * math.pi * self.time / Brain.SWEEP_TIME + s.phase)
    end
    s.facing = turn(s.facing, want, conf.turn or Brain.TURN, dt)
  end
  if s.lostAt and conf.grenadier then
    self:maybeLob(server, s, nil, nil, dt)
  end
end

--- A squad member with nobody of its own: with a mate who has somebody (to
--- where it is shooting); else the leader walks the beat and the rest keep
--- their slots behind it.
function Brain:patrol(s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m ~= s and m.target and m.seenX then
      self:alert(s, m.seenX, m.seenY)
      return
    end
  end
  local leader = squad.members[1]
  local gx, gy, speed
  if leader == s then
    local to = squad.route[squad.leg]
    if dist2(s.x, s.y, to.x, to.y) < 24 * 24 then
      squad.leg = squad.leg % #squad.route + 1
      to = squad.route[squad.leg]
    end
    gx, gy, speed = to.x, to.y, Brain.PATROL_WALK
  else
    local slot = Brain.FORMATION[1]
    for i, m in ipairs(squad.members) do
      if m == s then
        slot = Brain.FORMATION[(i - 1) % #Brain.FORMATION + 1]
      end
    end
    local heading = leader.heading or leader.facing
    local c, sn = math.cos(heading), math.sin(heading)
    gx, gy = leader.x + slot[1] * c - slot[2] * sn, leader.y + slot[1] * sn + slot[2] * c
    local d = math.sqrt(dist2(s.x, s.y, gx, gy))
    if d < 6 then
      s.facing = turn(s.facing, heading, Brain.TURN, dt)
      return
    end
    speed = Brain.PATROL_WALK * math.min(1.8, 0.6 + d / 60) -- catch up when behind
  end
  local _, way = goTo(self, s, gx, gy, speed, dt, false)
  if way then
    if leader == s then
      s.heading = way
    end
    s.facing = turn(s.facing, way + Brain.SCAN * math.sin(self.time * 1.3 + s.phase), Brain.TURN, dt)
  end
end

--- `s` has somebody it can see at (tx, ty), or has just lost sight of them
--- (tx nil): close in (as far as its leash allows), and fire.
function Brain:fight(server, s, tx, ty, dt)
  local conf = s.conf
  local leashed = conf.leash and not s.squad and dist2(s.x, s.y, s.postX, s.postY) > conf.leash * conf.leash
  if not tx then
    s.aimFor, s.spun = 0, math.max(0, s.spun - dt)
    if leashed then
      goTo(self, s, s.postX, s.postY, conf.walk, dt)
    elseif s.seenX and not conf.holds then
      goTo(self, s, s.seenX, s.seenY, conf.speed, dt)
    end
    return
  end
  local d2 = dist2(s.x, s.y, tx, ty)
  if leashed then
    goTo(self, s, s.postX, s.postY, conf.walk, dt, false)
  elseif d2 > conf.close * conf.close and not conf.holds then
    goTo(self, s, tx, ty, conf.speed, dt, false)
  end
  shoot(self, server, s, tx, ty, dt)
  self:maybeLob(server, s, tx, ty, dt)
end

--- The one whose body covers (x, y) (within `radius` more), and its index.
function Brain:at(x, y, radius)
  local r = Brain.RADIUS + (radius or 0)
  for i, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= r * r then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off `s` (index `i`), hit along `angle`. Returns true when
--- that put it down (and it is off the list, the alarm raised). Hit by
--- somebody none of them can see, those who know to go to ground; a staffer
--- just turns that way and comes.
function Brain:hurt(s, i, amount, angle)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    table.remove(self.list, i)
    if s.squad then -- the next one leads
      for k, m in ipairs(s.squad.members) do
        if m == s then
          table.remove(s.squad.members, k)
          break
        end
      end
    end
    self:alarm(s.x, s.y)
    if angle and not s.target then
      self:underFire(s.x, s.y, angle)
    end
    return true
  end
  if angle and s.conf.cover then
    -- Somebody that way: into cover from them, out of the open at once.
    local th = s.threat or { x = s.x - math.cos(angle) * 300, y = s.y - math.sin(angle) * 300 }
    th.untilT = self.time + Brain.THREAT_KEEP
    s.threat = th
    if s.cv and s.cv.phase == "peek" then
      s.cv.ducking, s.cv.peek = true, nil
    end
  end
  if angle and not s.target then
    s.facing = angle + math.pi
    if s.conf.pins then
      self:underFire(s.x, s.y, angle, s)
    else
      self:alert(s, s.x - math.cos(angle) * 200, s.y - math.sin(angle) * 200)
    end
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
