-- City 17's Combine soldiers' brain, on the host (a-man/city17.lua runs
-- them and owns the wire). Two kinds:
--
--   guard     stands at a checkpoint post sweeping a cone of sight from side
--             to side over the way he watches.
--   patrol    one of a squad walking a beat round and round: the first of
--             them leads from corner to corner, the rest keep a step
--             behind him either side. When one of them has somebody the
--             squad stops and the others turn to look the same way.
--
-- Any one that gets someone in his cone turns to follow them and, after
-- a moment to take aim, opens fire, and keeps firing for as long as he can
-- see them. Duck behind cover, or get out of his cone faster than he can
-- turn, and he stops.
--
-- They hunt (`hunt`, on unless told otherwise): whoever has somebody in his
-- sights closes in on them (to CHASE_KEEP, never more than LEASH from
-- where he started), and when he loses them he goes to where he saw them
-- last and looks round. A squad's mates go with him. Combine:alarm sends
-- anyone near enough to look into something (a soldier going down, or one
-- calling in who he has spotted). Either way he walks back the way he came
-- after, on the trail of breadcrumbs he dropped, and takes up his post or
-- his beat again. Given a walking grid (Combine:navigate, d-day/nav.lua)
-- he finds his way round walls to where he is going instead of walking
-- straight at it.
--
-- Each carries whatever he has been handed (Combine:arm): any of the guns,
-- fired in bursts and only once whoever he is shooting at is within its
-- reach; an AK otherwise.
--
-- They shoot through weapons' ownerless entry point (the police officers on
-- foot do the same), so their rounds hurt any player and credit nobody.
-- D-Day's soldiers think the same way, in a brain of their own
-- (d-day/brain.lua).
--
-- One soldier can be told apart from the rest (fields on him, set by
-- whoever adds him):
--   hold    he holds his place even when the others hunt: never chases,
--           never goes to look, never answers a call (the MG nests' crews: the Coast, the Road, the Citadel)
--   arc     radians either side of `watch` he may turn to and shoot into,
--           and only there (a gunner behind a fixed gun)
--   fov     his own cone of sight, instead of everyone's
--   post    { x, y } to walk to, whatever is going on, before anything
--           else (a crewman running to a gun nobody is on)
--   takesCover  he fights from cover (the Coast's bunker riflemen): once
--           he has seen somebody, or been shot at, he runs to a spot near
--           his place with something solid between him and them, waits
--           there (HIDE), steps out to where he can see them (no further
--           than PEEK_REACH), shoots for a while (PEEK) and gets back into
--           cover, over and over; a hit out in the open sends him straight
--           back. THREAT_KEEP after he last saw or felt anyone he goes back
--           to his place. `tookCover` is set each time he dives for cover,
--           for whoever runs the radio.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")

local Combine = {}
Combine.__index = Combine

-- Tuning --------------------------------------------------------------------

Combine.RADIUS = 9 -- px; as fat as an officer on foot (drawn as a person: src/body.lua)
Combine.HEALTH = 40 -- two pistol rounds
Combine.SHOT_DAMAGE = 20 -- what one round takes off (matches the pistol)
Combine.RANGE = 640 -- px they can see
Combine.SWEEP = math.rad(55) -- a guard's scan swings this far either side of where he watches
Combine.SWEEP_TIME = 6 -- seconds for one full swing there and back
Combine.TRACK_FOV = math.rad(60) -- once he has someone, he keeps them in a wider eye while turning
Combine.TURN = 2.0 -- rad/s turning to follow someone; sprint across his cone and he loses you
Combine.REACT = 0.7 -- seconds from spotting someone to the first shot
Combine.FIRE_EVERY = 0.6 -- seconds between rounds while he can see you
Combine.SPREAD = 0.06 -- radians of aim error, on top of the rifle's own
Combine.MUZZLE = 23 -- px from the body a round leaves: the tip of the rifle in his hands
Combine.LOOK_EVERY = 3 -- host ticks between sight checks (staggered by soldier)
Combine.SCAN = math.rad(20) -- a walking soldier looks this far either side of his path
Combine.WALK = 62 -- px/s a soldier walks (twice this running from a stink)
Combine.PATROL_WALK = 48 -- px/s a squad walks its beat
Combine.FORMATION = { { 0, 0 }, { -38, -30 }, { -38, 30 }, { -76, 0 } } -- slots behind the leader, his frame
Combine.CHASE_WALK = 90 -- px/s closing in or hunting: faster than a walk, slower than a sprint
Combine.CHASE_KEEP = 200 -- px; he stops closing in this near and just shoots
Combine.LEASH = 900 -- px from where he started that he will go after somebody
Combine.INVESTIGATE_WALK = 75 -- px/s going to look into something
Combine.SEARCH_TIME = 5 -- seconds looking round where he lost them, or at what he came to look into
Combine.SEARCH_SWEEP = math.rad(100) -- how far either way he looks round then
Combine.CRUMB = 40 -- px between the breadcrumbs he drops on his way, for the way back
Combine.COVER_RANGE = 170 -- px from his place he will go for cover
Combine.HIDE = { 1.2, 2.6 } -- seconds in cover between one look out and the next (min, max)
Combine.PEEK = { 1.2, 2.0 } -- seconds out shooting before he ducks back (min, max)
Combine.PEEK_REACH = 90 -- px from his cover he steps out to shoot from
Combine.THREAT_KEEP = 10 -- seconds he keeps to cover after he last saw or felt anyone

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- A troop. `opts` (optional, every field too):
---   hunt    true to have them leave their places to chase and look into
---           things (City 17), false to have them hold them (D-Day)
---   fov     how wide their cone of sight is (Sight.FOV)
---   aware   px all round them that they notice somebody in, whichever way
---           they face (never through a wall; nobody draws it), 0 for none
---   health  what each one can take (Combine.HEALTH)
---   alertFov  how wide his cone is while he is on edge: has somebody, or
---           is searching or looking into something (`fov` throughout)
function Combine.new(opts)
  opts = opts or {}
  local t = { list = {}, nextId = 1, time = 0, ticks = 0, hunt = opts.hunt ~= false, fov = opts.fov,
    aware = opts.aware or 0, health = opts.health or Combine.HEALTH, alertFov = opts.alertFov }
  return setmetatable(t, Combine)
end

--- Does `s` leave his place to chase and look into things?
local function hunts(self, s)
  return self.hunt and not s.hold
end

--- Is `s` on edge: somebody in his sights, or out searching or looking
--- into something?
function Combine.wary(s)
  return s.alert or s.goal ~= nil or s.cv ~= nil
end

--- How wide `s`'s cone of sight is right now.
function Combine:fovOf(s)
  if s.fov then
    return s.fov
  end
  if self.alertFov and Combine.wary(s) then
    return self.alertFov
  end
  return self.fov or Sight.FOV
end

--- A soldier of `kind` at (x, y), watching `watch` (radians).
function Combine:add(kind, x, y, watch)
  local s = {
    id = self.nextId,
    kind = kind,
    x = x,
    y = y,
    watch = watch,
    facing = watch,
    phase = random() * 2 * math.pi,
    hp = self.health,
    target = nil, -- player id he has in his sights
    fireIn = 0,
    alert = false,
    frozen = 0,
    panic = nil,
    stuck = 0,
    sidestep = 0,
    side = random() < 0.5 and -1 or 1,
    home = { x = x, y = y }, -- his place, for one who comes back to it (takesCover)
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- A squad of `size` walking `route` (a loop of { x, y }), starting at
--- corner `start` (one picked at random when nil), heading for the next.
function Combine:addSquad(route, size, start)
  local leg = start or random(#route)
  local from = route[leg]
  leg = leg % #route + 1
  local squad = { route = route, leg = leg, members = {} }
  local to = route[leg]
  local heading = math.atan2(to.y - from.y, to.x - from.x)
  for i = 1, size do
    local slot = Combine.FORMATION[(i - 1) % #Combine.FORMATION + 1]
    local c, sn = math.cos(heading), math.sin(heading)
    local s = self:add("patrol", from.x + slot[1] * c - slot[2] * sn, from.y + slot[1] * sn + slot[2] * c, heading)
    s.squad = squad
    squad.members[i] = s
  end
  return squad
end

function Combine:count(kind)
  local n = 0
  for _, s in ipairs(self.list) do
    if not kind or s.kind == kind then
      n = n + 1
    end
  end
  return n
end

-- Walking -------------------------------------------------------------------

--- Solid ground, through the `blocksPoint` convention, at the four extremes
--- of the body.
local function blockedAt(x, y)
  local r = Combine.RADIUS
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step, each axis on its own so a wall is slid along, and a note of
--- whether it got anywhere.
local function walk(s, angle, speed, dt)
  local px, py = s.x, s.y
  local nx = s.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, s.y) then
    s.x = nx
  end
  local ny = s.y + math.sin(angle) * speed * dt
  if not blockedAt(s.x, ny) then
    s.y = ny
  end
  if dist2(s.x, s.y, px, py) < (speed * dt * 0.4) ^ 2 then
    s.stuck = s.stuck + dt
  else
    s.stuck = 0
  end
end

--- Walk towards `angle`, sidestepping for a moment whenever something is
--- in the way.
local function advance(s, angle, speed, dt)
  if s.sidestep > 0 then
    s.sidestep = s.sidestep - dt
    walk(s, angle + s.side * math.pi / 2, speed, dt)
  else
    walk(s, angle, speed, dt)
    if s.stuck > 0.4 then
      s.stuck, s.sidestep, s.side = 0, 0.7, -s.side
    end
  end
end

--- Turn `from` towards `to` by at most `rate * dt`.
local function turn(from, to, rate, dt)
  local d = Sight.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

-- Hunting -------------------------------------------------------------------

--- A breadcrumb where he stands, if he has gone far enough from the last
--- one; the first is where he left from. Back near one he dropped earlier
--- (a chase that doubles back), the trail is cut back to it, so the way
--- home never winds through the same ground twice.
local function crumb(s)
  local trail = s.trail
  if not trail then
    s.trail = { { x = s.x, y = s.y } }
    return
  end
  local last = trail[#trail]
  if dist2(s.x, s.y, last.x, last.y) < Combine.CRUMB * Combine.CRUMB then
    return
  end
  for i = 1, #trail - 1 do
    if dist2(s.x, s.y, trail[i].x, trail[i].y) < Combine.CRUMB * Combine.CRUMB then
      for k = #trail, i + 1, -1 do
        trail[k] = nil
      end
      return
    end
  end
  trail[#trail + 1] = { x = s.x, y = s.y }
end

--- Is (x, y) past his leash, from where he left?
local function leashed(s, x, y)
  local home = s.trail and s.trail[1]
  return home ~= nil and dist2(home.x, home.y, x, y) > Combine.LEASH * Combine.LEASH
end

--- The way to (x, y) for `s`: corners to walk through, the last being
--- (x, y). Straight there without a walking grid; nil if the grid has no
--- way, or only one too long to bother with.
local function route(self, s, x, y)
  if not self.nav then
    return { { x = x, y = y } }
  end
  local corners, length = self.nav:path(s.x, s.y, x, y)
  if not corners or length > Combine.LEASH * 1.6 then
    return nil
  end
  return corners
end

--- One step of `s` towards `to` ({ x, y }) by the walking grid, round
--- whatever is in the way, at `speed`: the way is worked out once for
--- that spot, and again if he gets caught on something. Returns the way
--- he is heading, or nil once he is there.
local function walkTo(self, s, to, speed, dt)
  if dist2(s.x, s.y, to.x, to.y) <= 5 * 5 then
    s.way = nil
    return nil
  end
  local w = s.way
  if not (w and w.to == to) or s.stuck > 1.5 then
    s.stuck = 0
    w = { to = to, corners = route(self, s, to.x, to.y) or { to }, at = 1 }
    s.way = w
  end
  local c = w.corners[w.at]
  if w.at < #w.corners and dist2(s.x, s.y, c.x, c.y) < 18 * 18 then
    w.at = w.at + 1
    c = w.corners[w.at]
  end
  local path = math.atan2(c.y - s.y, c.x - s.x)
  advance(s, path, speed, dt)
  return path
end

--- Go to (x, y) and look round there: `kind` "search" (where he lost
--- somebody) or "investigate" (what he heard).
local function setGoal(self, s, x, y, kind)
  if leashed(s, x, y) or (s.noRouteUntil or 0) > self.time then
    return
  end
  local corners = route(self, s, x, y)
  if not corners then
    s.noRouteUntil = self.time + 2 -- no asking again every tick
    return
  end
  crumb(s)
  s.goal = { x = x, y = y, kind = kind, look = nil, corners = corners, at = 1, replanned = false }
end

--- On his way to his goal, or looking round once there. Returns false when
--- he is done with it.
local function pursue(self, s, dt)
  local g = s.goal
  if g.look then
    g.look = g.look - dt
    local around = g.facing + Combine.SEARCH_SWEEP * math.sin(2 * math.pi * g.look / Combine.SEARCH_TIME * 1.5)
    s.facing = turn(s.facing, around, Combine.TURN, dt)
    return g.look > 0
  end
  local speed = g.kind == "investigate" and Combine.INVESTIGATE_WALK or Combine.CHASE_WALK
  local to = g.corners[g.at]
  local last = g.at == #g.corners
  if dist2(s.x, s.y, to.x, to.y) < (last and 28 or 18) ^ 2 then
    if last then
      g.look, g.facing = Combine.SEARCH_TIME, s.facing
      return true
    end
    g.at = g.at + 1
    to = g.corners[g.at]
  end
  local path = math.atan2(to.y - s.y, to.x - s.x)
  advance(s, path, speed, dt)
  crumb(s)
  s.facing = turn(s.facing, path + Combine.SCAN * math.sin(self.time * 2 + s.phase), Combine.TURN, dt)
  if s.stuck > 1.5 then
    -- Caught on something after all: find the way again from here, once;
    -- after that, look round from where he got to.
    local corners = not g.replanned and route(self, s, g.x, g.y)
    if corners then
      g.corners, g.at, g.replanned, s.stuck = corners, 1, true, 0
    else
      g.look, g.facing = Combine.SEARCH_TIME, path
    end
  end
  return true
end

--- Back along his breadcrumbs. Returns false once he is where he left from.
local function retrace(self, s, dt)
  local trail = s.trail
  local to = trail[#trail]
  if dist2(s.x, s.y, to.x, to.y) < 16 * 16 then
    trail[#trail] = nil
    if #trail == 0 then
      s.trail, s.backFor = nil, 0
      return false
    end
    to = trail[#trail]
  end
  local path = math.atan2(to.y - s.y, to.x - s.x)
  advance(s, path, Combine.INVESTIGATE_WALK, dt)
  s.facing = turn(s.facing, path + Combine.SCAN * math.sin(self.time * 1.3 + s.phase), Combine.TURN, dt)
  if s.stuck > 1.5 and self.nav then
    -- Caught on something: a fresh way home to where he left from, walked
    -- as breadcrumbs (last first).
    local home = trail[1]
    local corners = self.nav:path(s.x, s.y, home.x, home.y)
    if corners then
      s.trail, s.stuck = { home }, 0
      for i = #corners, 1, -1 do
        s.trail[#s.trail + 1] = corners[i]
      end
    end
  end
  s.backFor = (s.backFor or 0) + dt
  if s.backFor > 40 then -- lost on the way: this will do
    s.trail, s.backFor = nil, 0
    if s.kind == "guard" then
      s.watch = s.facing
    end
    return false
  end
  return true
end

--- Give them a walking grid over `bounds` ({ x, y, w, h }) to find their
--- way round walls with. Build it once the map is in place.
function Combine:navigate(bounds)
  self.nav = Nav.build(bounds)
end

--- Something happened at (x, y) (a soldier went down, or one called in
--- somebody he spotted): everyone within `radius` who has nobody in his
--- sights goes to look into it, nearest first. `opts` (optional):
---   from  the one calling it in: neither he nor his squad (they go with
---         him anyway) answers
---   most  how many go at most (everyone)
--- Returns who went, nearest first.
function Combine:alarm(x, y, radius, opts)
  opts = opts or {}
  local went = {}
  if not self.hunt then
    return went
  end
  local near = {}
  local from = opts.from
  for _, s in ipairs(self.list) do
    local d2 = dist2(s.x, s.y, x, y)
    local own = from and (s == from or (s.squad ~= nil and s.squad == from.squad))
    if not own and not s.hold and not s.target and not s.panic and d2 <= radius * radius then
      near[#near + 1] = { s = s, d2 = d2 }
    end
  end
  table.sort(near, function(a, b)
    return a.d2 < b.d2
  end)
  for _, n in ipairs(near) do
    if opts.most and #went >= opts.most then
      break
    end
    setGoal(self, n.s, x, y, "investigate")
    if n.s.goal then
      went[#went + 1] = n.s
    end
  end
  return went
end

--- Send `s` to look into (x, y), as an alarm would: he goes there, looks
--- round, and walks back to where he came from (a soldier just out of a
--- garrison's door, sent at whoever brought him out).
function Combine:sendTo(s, x, y)
  setGoal(self, s, x, y, "investigate")
end

-- Seeing --------------------------------------------------------------------

--- Where `player` is, if they are there to be shot at.
local function poseOf(server, id)
  local p = server.players[id]
  if p and Features.visible(server, p) then
    local x, y = Features.bodyPose(server, p)
    return x, y
  end
  return nil
end

--- The nearest player inside this soldier's cone right now, if any.
local function spot(server, s, fov, aware)
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Combine.RANGE, fov)
        or (aware > 0 and Sight.canSee(s.x, s.y, s.facing, x, y, aware, 2 * math.pi))
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = id, d2
      end
    end
  end
  return best
end

-- Thinking ------------------------------------------------------------------

--- Hand `s` a gun: `arms` is { gun, burst, pause, reach }, `gun` a table
--- from weapons/guns.lua (tiered, or tuned for a soldier), `burst` rounds
--- at the gun's own rate, then `pause` seconds, and he only fires at
--- somebody within `reach` px.
function Combine:arm(s, arms)
  s.arms, s.burstLeft = arms, arms.burst
end

--- One round (or one pull of a shotgun) at (tx, ty), from the muzzle, a little off.
local function fire(server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Combine.SPREAD
  local mx, my = s.x + math.cos(aim) * Combine.MUZZLE, s.y + math.sin(aim) * Combine.MUZZLE
  local gun = s.arms and s.arms.gun or require("src.features.weapons.guns").ak47
  weapons:serverFireFrom(server, 0, mx, my, aim, gun)
end

--- His trigger, while he has somebody at (tx, ty) in his sights.
local function shoot(server, s, tx, ty, dt)
  local arms = s.arms
  if arms and dist2(s.x, s.y, tx, ty) > arms.reach * arms.reach then
    return -- out of reach of what he carries: closer first
  end
  s.fireIn = s.fireIn - dt
  if s.fireIn > 0 then
    return
  end
  fire(server, s, tx, ty)
  if not arms then
    s.fireIn = Combine.FIRE_EVERY * (0.85 + random() * 0.3)
    return
  end
  s.burstLeft = s.burstLeft - 1
  if s.burstLeft > 0 then
    s.fireIn = arms.gun.cooldown
  else
    s.burstLeft = arms.burst
    s.fireIn = arms.pause * (0.85 + random() * 0.3)
  end
end

--- Everyone's tick: who they can see, where they look, whether they shoot,
--- and the riflemen's walk.
function Combine:update(server, dt)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  for _, s in ipairs(self.list) do
    self:think(server, s, dt)
  end
end

function Combine:think(server, s, dt)
  if s.frozen > 0 then
    s.frozen = s.frozen - dt -- frozen stiff: no looking, no shooting
    s.alert, s.target = false, nil
    return
  end
  if s.panic then
    -- A stink: away from it, rifle forgotten.
    s.alert, s.target = false, nil
    if hunts(self, s) then
      crumb(s) -- and back again after
    end
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    walk(s, s.facing, Combine.WALK * 2, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end

  -- Look, a few times a second: keep the one in his sights while he still
  -- can, otherwise whoever has just walked into his cone.
  if (self.ticks + s.id) % Combine.LOOK_EVERY == 0 then
    local tx, ty = nil, nil
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    -- Once he has someone he keeps them in a wider eye: TRACK_FOV, or more for a wide cone.
    local fov = self:fovOf(s)
    local track = math.max(Combine.TRACK_FOV, fov + math.rad(30))
    local kept = tx
      and (Sight.canSee(s.x, s.y, s.facing, tx, ty, Combine.RANGE, track)
        or (self.aware > 0 and Sight.canSee(s.x, s.y, s.facing, tx, ty, self.aware, 2 * math.pi)))
    if not kept then
      s.target = spot(server, s, fov, self.aware)
      if s.target then
        -- A moment to take aim, and longer if he has to turn round first.
        local px, py = poseOf(server, s.target)
        local behind = px and math.abs(Sight.angleDiff(math.atan2(py - s.y, px - s.x), s.facing)) or 0
        s.fireIn = Combine.REACT + behind / Combine.TURN
      end
    end
  end

  local tx, ty = nil, nil
  if s.target then
    tx, ty = poseOf(server, s.target)
    if not tx then
      s.target = nil
    elseif s.arc and math.abs(Sight.angleDiff(math.atan2(ty - s.y, tx - s.x), s.watch)) > s.arc then
      tx, ty, s.target = nil, nil, nil -- out past where his gun turns
    end
  end
  if s.post then
    -- To his post before anything else, rifle down, round whatever is in the way.
    local path = walkTo(self, s, s.post, Combine.CHASE_WALK, dt)
    if path then
      s.facing = turn(s.facing, path, Combine.TURN * 2, dt)
      s.alert, s.target = false, nil
      return
    end
    s.x, s.y, s.post = s.post.x, s.post.y, nil
  end
  if s.takesCover then
    s.alert = s.target ~= nil -- in and out of cover, he still has somebody (the "!", the shout, the crew's quiet)
    if tx then
      s.aimX, s.aimY = tx, ty
    end
    if self:fightFromCover(server, s, tx, ty, dt) then
      return
    end
  end
  if hunts(self, s) and s.alert and not tx and s.aimX then
    setGoal(self, s, s.aimX, s.aimY, "search") -- lost them: to where they were last
  end
  s.alert = s.target ~= nil

  if tx then
    s.aimX, s.aimY = tx, ty
    s.goal = nil
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Combine.TURN, dt)
    -- Close in to CHASE_KEEP, or nearer with a gun that doesn't reach that far.
    local keep = s.arms and math.min(Combine.CHASE_KEEP, s.arms.reach * 0.6) or Combine.CHASE_KEEP
    if hunts(self, s) and dist2(s.x, s.y, tx, ty) > keep * keep then
      crumb(s)
      if not leashed(s, s.x + (tx - s.x) * 0.1, s.y + (ty - s.y) * 0.1) then
        walk(s, math.atan2(ty - s.y, tx - s.x), Combine.CHASE_WALK, dt) -- close in, rifle up
      end
    end
    shoot(server, s, tx, ty, dt)
  elseif s.goal then
    if not pursue(self, s, dt) then
      s.goal, s.gaveUp = nil, true -- nothing there: back he goes
    end
  elseif s.trail then
    retrace(self, s, dt)
  elseif s.kind == "patrol" then
    self:patrol(s, dt)
  else -- a guard
    local reach = s.arc and math.min(Combine.SWEEP, s.arc) or Combine.SWEEP
    local sweep = s.watch + reach * math.sin(2 * math.pi * self.time / Combine.SWEEP_TIME + s.phase)
    s.facing = turn(s.facing, sweep, Combine.TURN, dt)
  end
  if s.arc then -- his gun turns no further
    local off = Sight.angleDiff(s.facing, s.watch)
    if math.abs(off) > s.arc then
      s.facing = s.watch + (off > 0 and s.arc or -s.arc)
    end
  end
end

--- A squad member's tick when he has nobody himself: hold still and look
--- where a mate is shooting, or walk the beat (the leader) or his slot.
function Combine:patrol(s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m.alert and m ~= s then
      if hunts(self, s) then
        setGoal(self, s, m.aimX, m.aimY, "search") -- with him
        if s.goal then
          return
        end
      end
      s.facing = turn(s.facing, math.atan2(m.aimY - s.y, m.aimX - s.x), Combine.TURN, dt)
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
    gx, gy, speed = to.x, to.y, Combine.PATROL_WALK
  else
    local slot = Combine.FORMATION[1]
    for i, m in ipairs(squad.members) do
      if m == s then
        slot = Combine.FORMATION[(i - 1) % #Combine.FORMATION + 1]
      end
    end
    local heading = leader.heading or leader.facing -- where he walks, not where he glances
    local c, sn = math.cos(heading), math.sin(heading)
    gx, gy = leader.x + slot[1] * c - slot[2] * sn, leader.y + slot[1] * sn + slot[2] * c
    local d = math.sqrt(dist2(s.x, s.y, gx, gy))
    if d < 6 then
      s.facing = turn(s.facing, heading, Combine.TURN, dt)
      return
    end
    speed = Combine.PATROL_WALK * math.min(1.6, 0.6 + d / 60) -- catch up when behind, ease in when there
  end
  local path = math.atan2(gy - s.y, gx - s.x)
  if leader == s then
    s.heading = path
  end
  advance(s, path, speed, dt)
  local look = path + Combine.SCAN * math.sin(self.time * 1.3 + s.phase)
  s.facing = turn(s.facing, look, Combine.TURN, dt)
end

-- Fighting from cover --------------------------------------------------------

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

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
      if not blockedAt(x, y) and Sight.clear(fx, fy, x, y) and ok(x, y) then
        local score = math.sqrt(dist2(x, y, fx, fy)) + pull * d
        if not bestScore or score < bestScore then
          best, bestScore = { x = x, y = y }, score
        end
      end
    end
  end
  return best
end

--- Somewhere near his place with something solid between it and the threat.
local function findCover(s, th)
  return search(s.home.x, s.home.y, Combine.COVER_RANGE, s.x, s.y, 0.5, function(x, y)
    return not Sight.clear(th.x, th.y, x, y)
  end)
end

--- Somewhere a step out from his cover he can see the threat from.
local function findPeek(s, th)
  return search(s.x, s.y, Combine.PEEK_REACH, s.x, s.y, 0, function(x, y)
    return Sight.clear(x, y, th.x, th.y)
  end)
end

--- Walk to `to` if he isn't there yet; true while still on his way.
local function goTo(s, to, dt)
  if not to or dist2(s.x, s.y, to.x, to.y) <= 5 * 5 then
    return false
  end
  local path = math.atan2(to.y - s.y, to.x - s.x)
  advance(s, path, Combine.CHASE_WALK, dt)
  return true
end

--- A takesCover soldier's tick: back to his place once the threat is old,
--- otherwise in and out of cover. True if it took care of the tick.
function Combine:fightFromCover(server, s, tx, ty, dt)
  local now = self.time
  if tx then
    s.threat = { x = tx, y = ty, untilT = now + Combine.THREAT_KEEP }
  end
  local th = s.threat
  if not th or now > th.untilT then
    s.threat, s.cv = nil, nil
    local path = walkTo(self, s, s.home, Combine.INVESTIGATE_WALK, dt) -- quiet again: back to his place
    if path then
      s.facing = turn(s.facing, path, Combine.TURN, dt)
      return true
    end
    return false
  end
  local cv = s.cv
  if not cv then
    cv = { phase = "hide", t = 0, hideFor = between(Combine.HIDE) * 0.5, spot = findCover(s, th) }
    s.cv, s.tookCover = cv, true
  end
  cv.t = cv.t + dt
  local look = tx and math.atan2(ty - s.y, tx - s.x) or math.atan2(th.y - s.y, th.x - s.x)
  if cv.phase == "hide" then
    if goTo(s, cv.spot, dt) then
      s.facing = turn(s.facing, math.atan2(cv.spot.y - s.y, cv.spot.x - s.x), Combine.TURN * 2, dt)
      cv.t = 0 -- the wait starts once he is behind it
      return true
    end
    s.facing = turn(s.facing, look, Combine.TURN, dt)
    if tx then -- his cover doesn't hide him from this one: shoot back
      shoot(server, s, tx, ty, dt)
    end
    if cv.t >= cv.hideFor then
      cv.phase, cv.t, cv.peekFor = "peek", 0, between(Combine.PEEK)
      cv.peek = findPeek(s, th)
      s.fireIn = math.max(s.fireIn, 0.25) -- a moment to bring the rifle up
    end
    return true
  end
  -- Out: to where he can see them, rifle up, shooting whenever he has them.
  local stepping = goTo(s, cv.peek, dt)
  s.facing = turn(s.facing, look, Combine.TURN * 1.5, dt)
  if tx then
    shoot(server, s, tx, ty, dt)
  end
  if not stepping then
    if cv.t >= cv.peekFor or cv.ducking then
      cv.phase, cv.t, cv.ducking = "hide", 0, nil
      cv.hideFor = between(Combine.HIDE)
      cv.spot = findCover(s, th) or cv.spot
      s.tookCover = true
    end
  end
  return true
end

-- Being shot at -------------------------------------------------------------

--- The soldier standing within `radius` of (x, y), and his index.
function Combine:at(x, y, radius)
  local r2 = (radius + Combine.RADIUS) ^ 2
  for i, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) < r2 then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off `s` (the i-th). Returns true if that killed him; he
--- is gone from the list then. A living one who is hurt turns to look for
--- whoever did it.
function Combine:hurt(s, i, amount, angle)
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
    return true
  end
  if s.takesCover and angle then
    -- Somebody that way: into cover from them, and out of the open at once.
    local th = s.threat or {}
    if not s.threat then
      th.x, th.y = s.x - math.cos(angle) * 300, s.y - math.sin(angle) * 300
    end
    th.untilT = self.time + Combine.THREAT_KEEP
    s.threat = th
    if s.cv and s.cv.phase == "peek" then
      s.cv.ducking, s.cv.peek = true, nil
    end
  end
  if angle and not s.target then
    s.facing = angle + math.pi -- back the way the round came
    if hunts(self, s) then -- and off that way to find who sent it
      setGoal(self, s, s.x - math.cos(angle) * 260, s.y - math.sin(angle) * 260, "search")
    end
  end
  return false
end

--- Everyone inside a freeze stands stiff for `seconds`.
function Combine:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Combine.RADIUS) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Everyone inside a stink runs from it for `seconds`.
function Combine:scare(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    -- A gunner stays on his gun (he has no way back to it if he runs).
    local gunner = s.hold and not s.takesCover
    if not gunner and dist2(s.x, s.y, x, y) <= (radius + Combine.RADIUS) ^ 2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

return Combine
