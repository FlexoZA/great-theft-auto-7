-- D-Day's soldiers' brain, on the host (init.lua runs them and owns the
-- wire): the City 17 Combine soldiers' brain (a-man/combine.lua) in other
-- uniforms, with D-Day's riflemen. Two kinds:
--
--   guard     stands at a post off the beach (in a bunker's embrasure, a gap
--             in a trench's sandbags, by a hut, on the hilltop) and sweeps
--             a thirty-degree cone of sight slowly from side to side over
--             the ground below.
--   rifleman  comes out of a barracks door and walks down the map towards
--             the nearest player, looking where he is going.
--
-- Any one that gets someone in his cone turns to follow them and, after
-- a moment to take aim, opens fire, and keeps firing for as long as he can
-- see them. Duck behind a hedgehog or a sandbag wall, or get out of his
-- cone faster than he can turn, and he stops.
--
-- They hunt as the Combine do (`hunt`, on unless told otherwise): whoever
-- has somebody in his sights closes in on them (to CHASE_KEEP, never more
-- than LEASH from where he started), and when he loses them he goes to
-- where he saw them last and looks round. Soldiers:alarm sends anyone near
-- enough to look into something (a soldier going down, or one calling in
-- who he has spotted). Either way he walks back the way he came after, on
-- the trail of breadcrumbs he dropped, and takes up his post again; a
-- rifleman carries on down the hill. Given a walking grid
-- (Soldiers:navigate, nav.lua) he finds his way round walls.
--
-- Shot at by somebody none of them can see (sniped from past their sight),
-- they don't walk into it, as the Combine don't: the one hit and every mate
-- within PIN_SHARE go to ground behind whatever is between them and where
-- the round came from (a "siege") and wait; every round from out there
-- starts the wait again. After QUIET seconds without one, squads of
-- SWEEP_SQUAD of them (SWEEPS at most) go out to look round where the shots
-- came from. The moment anyone within SPOT_SHARE gets the shooter in his
-- sights the siege is over and every one of them goes for them. RELEASE
-- seconds of quiet ends it too: guards back to their posts, riflemen on
-- down the hill.
--
-- Each one carries an AK unless he has been handed `arms` (Soldiers:arm).
-- GRENADIER of them carry GRENADES hand grenades as well (the grenades
-- feature's, through Grenades:serverLob): now and then at somebody in his
-- sights between GRENADE_MIN and the grenade's range, or at where he last
-- saw somebody who has just ducked out of sight, never where it would land
-- on one of his own. They shoot through weapons' ownerless entry point, so
-- their rounds (and grenades) hurt any player and credit nobody. Like the Combine's, it can walk squads on
-- a beat too (Soldiers:addSquad); D-Day doesn't put any out yet.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")

local Soldiers = {}
Soldiers.__index = Soldiers

-- Tuning --------------------------------------------------------------------

Soldiers.RADIUS = 9 -- px; as fat as an officer on foot (drawn as a person: src/body.lua)
Soldiers.HEALTH = 40 -- two pistol rounds
Soldiers.SHOT_DAMAGE = 20 -- what one round takes off (matches the pistol)
Soldiers.RANGE = 640 -- px they can see
Soldiers.SWEEP = math.rad(55) -- a guard's scan swings this far either side of where he watches
Soldiers.SWEEP_TIME = 6 -- seconds for one full swing there and back
Soldiers.TRACK_FOV = math.rad(60) -- once he has someone, he keeps them in a wider eye while turning
Soldiers.TURN = 2.0 -- rad/s turning to follow someone; sprint across his cone and he loses you
Soldiers.REACT = 0.7 -- seconds from spotting someone to the first shot
Soldiers.FIRE_EVERY = 0.6 -- seconds between rounds while he can see you
Soldiers.SPREAD = 0.06 -- radians of aim error, on top of the rifle's own
Soldiers.MUZZLE = 23 -- px from the body a round leaves: the tip of the rifle in his hands
Soldiers.LOOK_EVERY = 3 -- host ticks between sight checks (staggered by soldier)
Soldiers.WALK = 62 -- px/s a rifleman walks down the hill
Soldiers.SCAN = math.rad(20) -- a walking rifleman looks this far either side of his path
Soldiers.PATROL_WALK = 48 -- px/s a squad walks its beat
Soldiers.FORMATION = { { 0, 0 }, { -38, -30 }, { -38, 30 }, { -76, 0 } } -- slots behind the leader, his frame
Soldiers.CHASE_WALK = 90 -- px/s closing in or hunting: faster than a walk, slower than a sprint
Soldiers.CHASE_KEEP = 200 -- px; he stops closing in this near and just shoots
Soldiers.LEASH = 900 -- px from where he started that he will go after somebody
Soldiers.INVESTIGATE_WALK = 75 -- px/s going to look into something
Soldiers.SEARCH_TIME = 5 -- seconds looking round where he lost them, or at what he came to look into
Soldiers.SEARCH_SWEEP = math.rad(100) -- how far either way he looks round then
Soldiers.CRUMB = 40 -- px between the breadcrumbs he drops on his way, for the way back
Soldiers.COVER_RANGE = 170 -- px from where he stands he will go for cover
Soldiers.PIN_SHARE = 400 -- px; mates this near one shot by somebody unseen take cover with him
Soldiers.PIN_GUESS = 420 -- px back along the round that they reckon the shooter is
Soldiers.QUIET = 8 -- seconds without a round from out there before a sweep goes out
Soldiers.RELEASE = 30 -- seconds without one before everyone pinned gets up again
Soldiers.SWEEP_SQUAD = 3 -- soldiers to a sweep
Soldiers.SWEEPS = 2 -- sweeps out of one siege at most
Soldiers.SPOT_SHARE = 900 -- px; a siege this near whoever gets the shooter in his sights is over
Soldiers.GRENADIER = 0.25 -- share of soldiers who carry grenades
Soldiers.GRENADES = 2 -- grenades each of them carries
Soldiers.GRENADE_MIN = 140 -- px; no nearer than this (the blast would reach him)
Soldiers.GRENADE_EVERY = 8 -- seconds between one throw and the next
Soldiers.GRENADE_ROLL = { 1.2, 0.3 } -- every this many seconds he has somebody in range, this chance he throws
Soldiers.LOST_THROW = 4 -- seconds after losing sight of somebody that he may lob one at where they were
Soldiers.SPLASH_CLEAR = 120 -- px; nobody of his own this near where it would land

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
---   health  what each one can take (Soldiers.HEALTH)
---   alertFov  how wide his cone is while he is on edge: has somebody, or
---           is searching or looking into something (`fov` throughout)
function Soldiers.new(opts)
  opts = opts or {}
  local t = { list = {}, nextId = 1, time = 0, ticks = 0, hunt = opts.hunt ~= false, fov = opts.fov,
    aware = opts.aware or 0, health = opts.health or Soldiers.HEALTH, alertFov = opts.alertFov, sieges = {} }
  return setmetatable(t, Soldiers)
end

--- Is `s` on edge: somebody in his sights, out searching or looking into
--- something, or pinned down?
function Soldiers.wary(s)
  return s.alert or s.goal ~= nil or s.pin ~= nil
end

--- How wide `s`'s cone of sight is right now.
function Soldiers:fovOf(s)
  if self.alertFov and Soldiers.wary(s) then
    return self.alertFov
  end
  return self.fov or Sight.FOV
end

--- A soldier of `kind` at (x, y), watching `watch` (radians).
function Soldiers:add(kind, x, y, watch)
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
    grenades = random() < Soldiers.GRENADIER and Soldiers.GRENADES or 0,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Put `count` guards on the map's posts, picked at random, each watching
--- down the hill (south) give or take a little.
function Soldiers:placeGuards(map, count)
  local posts = {}
  for i, p in ipairs(map.posts) do
    posts[i] = p
  end
  for i = #posts, 2, -1 do
    local j = random(i)
    posts[i], posts[j] = posts[j], posts[i]
  end
  for i = 1, math.min(count, #posts) do
    local p = posts[i]
    self:add("guard", p.x, p.y, math.pi / 2 + (random() - 0.5) * 0.6)
  end
end

--- A rifleman out of one of the barracks doors.
function Soldiers:reinforce(map)
  local door = map.doors[random(#map.doors)]
  return self:add("rifleman", door.x + (random() - 0.5) * 30, door.y, math.pi / 2)
end

--- A squad of `size` walking `route` (a loop of { x, y }), starting at
--- corner `start` (one picked at random when nil), heading for the next.
function Soldiers:addSquad(route, size, start)
  local leg = start or random(#route)
  local from = route[leg]
  leg = leg % #route + 1
  local squad = { route = route, leg = leg, members = {} }
  local to = route[leg]
  local heading = math.atan2(to.y - from.y, to.x - from.x)
  for i = 1, size do
    local slot = Soldiers.FORMATION[(i - 1) % #Soldiers.FORMATION + 1]
    local c, sn = math.cos(heading), math.sin(heading)
    local s = self:add("patrol", from.x + slot[1] * c - slot[2] * sn, from.y + slot[1] * sn + slot[2] * c, heading)
    s.squad = squad
    squad.members[i] = s
  end
  return squad
end

function Soldiers:count(kind)
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
  local r = Soldiers.RADIUS
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
--- one; the first is where he left from.
local function crumb(s)
  local trail = s.trail
  if not trail then
    s.trail = { { x = s.x, y = s.y } }
    return
  end
  local last = trail[#trail]
  if dist2(s.x, s.y, last.x, last.y) >= Soldiers.CRUMB * Soldiers.CRUMB then
    trail[#trail + 1] = { x = s.x, y = s.y }
  end
end

--- Is (x, y) past his leash, from where he left?
local function leashed(s, x, y)
  local home = s.trail and s.trail[1]
  return home ~= nil and dist2(home.x, home.y, x, y) > Soldiers.LEASH * Soldiers.LEASH
end

--- The way to (x, y) for `s`: corners to walk through, the last being
--- (x, y). Straight there without a walking grid; nil if the grid has no
--- way, or only one too long to bother with.
local function route(self, s, x, y)
  if not self.nav then
    return { { x = x, y = y } }
  end
  local corners, length = self.nav:path(s.x, s.y, x, y)
  if not corners or length > Soldiers.LEASH * 1.6 then
    return nil
  end
  return corners
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
    local around = g.facing + Soldiers.SEARCH_SWEEP * math.sin(2 * math.pi * g.look / Soldiers.SEARCH_TIME * 1.5)
    s.facing = turn(s.facing, around, Soldiers.TURN, dt)
    return g.look > 0
  end
  local speed = g.kind == "investigate" and Soldiers.INVESTIGATE_WALK or Soldiers.CHASE_WALK
  local to = g.corners[g.at]
  local last = g.at == #g.corners
  if dist2(s.x, s.y, to.x, to.y) < (last and 28 or 18) ^ 2 then
    if last then
      g.look, g.facing = Soldiers.SEARCH_TIME, s.facing
      return true
    end
    g.at = g.at + 1
    to = g.corners[g.at]
  end
  local path = math.atan2(to.y - s.y, to.x - s.x)
  advance(s, path, speed, dt)
  crumb(s)
  s.facing = turn(s.facing, path + Soldiers.SCAN * math.sin(self.time * 2 + s.phase), Soldiers.TURN, dt)
  if s.stuck > 1.5 then
    -- Caught on something after all: find the way again from here, once;
    -- after that, look round from where he got to.
    local corners = not g.replanned and route(self, s, g.x, g.y)
    if corners then
      g.corners, g.at, g.replanned, s.stuck = corners, 1, true, 0
    else
      g.look, g.facing = Soldiers.SEARCH_TIME, path
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
  advance(s, path, Soldiers.INVESTIGATE_WALK, dt)
  s.facing = turn(s.facing, path + Soldiers.SCAN * math.sin(self.time * 1.3 + s.phase), Soldiers.TURN, dt)
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
function Soldiers:navigate(bounds)
  self.nav = Nav.build(bounds)
end

--- Something happened at (x, y) (a soldier went down, or one called in
--- somebody he spotted): everyone within `radius` who has nobody in his
--- sights goes to look into it, nearest first. `opts` (optional):
---   from  the one calling it in: neither he nor his squad (they go with
---         him anyway) answers
---   most  how many go at most (everyone)
--- Returns who went, nearest first.
function Soldiers:alarm(x, y, radius, opts)
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
    if not own and not s.target and not s.panic and not s.pin and d2 <= radius * radius then
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
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Soldiers.RANGE, fov)
        or (aware > 0 and Sight.canSee(s.x, s.y, s.facing, x, y, aware, 2 * math.pi))
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = id, d2
      end
    end
  end
  return best
end

--- The nearest player anywhere, for a rifleman to walk towards.
local function nearest(server, s)
  local bx, by, bestD2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, s.x, s.y)
      if not bestD2 or d2 < bestD2 then
        bx, by, bestD2 = x, y, d2
      end
    end
  end
  return bx, by
end

-- Thinking ------------------------------------------------------------------

--- Hand `s` a gun: `arms` is { gun, burst, pause, reach }, `gun` a table
--- from weapons/guns.lua (tiered, or tuned for a soldier), `burst` rounds
--- at the gun's own rate, then `pause` seconds, and he only fires at
--- somebody within `reach` px.
function Soldiers:arm(s, arms)
  s.arms, s.burstLeft = arms, arms.burst
end

--- One round (or one pull of a shotgun) at (tx, ty), from the muzzle, a little off.
local function fire(server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Soldiers.SPREAD
  local mx, my = s.x + math.cos(aim) * Soldiers.MUZZLE, s.y + math.sin(aim) * Soldiers.MUZZLE
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
    s.fireIn = Soldiers.FIRE_EVERY * (0.85 + random() * 0.3)
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
function Soldiers:update(server, dt)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  for _, s in ipairs(self.list) do
    self:think(server, s, dt)
  end
  self:stepSieges(dt)
end

function Soldiers:think(server, s, dt)
  if s.frozen > 0 then
    s.frozen = s.frozen - dt -- frozen stiff: no looking, no shooting
    s.alert, s.target = false, nil
    return
  end
  if s.panic then
    -- A stink: away from it, rifle forgotten.
    s.alert, s.target = false, nil
    if self.hunt then
      crumb(s) -- and back again after
    end
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    walk(s, s.facing, Soldiers.WALK * 2, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end

  -- Look, a few times a second: keep the one in his sights while he still
  -- can, otherwise whoever has just walked into his cone.
  if (self.ticks + s.id) % Soldiers.LOOK_EVERY == 0 then
    local tx, ty = nil, nil
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    -- Once he has someone he keeps them in a wider eye: TRACK_FOV, or more for a wide cone.
    local fov = self:fovOf(s)
    local track = math.max(Soldiers.TRACK_FOV, fov + math.rad(30))
    local kept = tx
      and (Sight.canSee(s.x, s.y, s.facing, tx, ty, Soldiers.RANGE, track)
        or (self.aware > 0 and Sight.canSee(s.x, s.y, s.facing, tx, ty, self.aware, 2 * math.pi)))
    if not kept then
      s.target = spot(server, s, fov, self.aware)
      if s.target then
        -- A moment to take aim, and longer if he has to turn round first.
        local px, py = poseOf(server, s.target)
        local behind = px and math.abs(Sight.angleDiff(math.atan2(py - s.y, px - s.x), s.facing)) or 0
        s.fireIn = Soldiers.REACT + behind / Soldiers.TURN
      end
    end
  end
  -- Somebody new in his sights ends any siege near him; losing them is
  -- the moment to lob a grenade where they went.
  local had = s.hadTarget
  s.hadTarget = s.target
  if s.target and s.target ~= had then
    local px, py = poseOf(server, s.target)
    if px then
      self:spotted(s, px, py)
    end
  elseif had and not s.target then
    s.lostAt = self.time
  end
  if s.sweep and not s.goal and not s.trail then
    s.sweep = nil -- back from looking round
  end

  local tx, ty = nil, nil
  if s.target then
    tx, ty = poseOf(server, s.target)
    if not tx then
      s.target = nil
    end
  end
  if s.pin and not tx then
    self:holdDown(s, dt) -- pinned down by somebody he can't see
    return
  end
  if s.returnTo and self:goBack(server, s, tx, ty, dt) then
    return
  end
  if self.hunt and s.alert and not tx and s.aimX then
    setGoal(self, s, s.aimX, s.aimY, "search") -- lost them: to where they were last
  end
  s.alert = s.target ~= nil

  if tx then
    s.aimX, s.aimY = tx, ty
    s.goal = nil
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Soldiers.TURN, dt)
    -- Close in to CHASE_KEEP, or nearer with a gun that doesn't reach that far.
    local keep = s.arms and math.min(Soldiers.CHASE_KEEP, s.arms.reach * 0.6) or Soldiers.CHASE_KEEP
    if self.hunt and dist2(s.x, s.y, tx, ty) > keep * keep then
      crumb(s)
      if not leashed(s, s.x + (tx - s.x) * 0.1, s.y + (ty - s.y) * 0.1) then
        walk(s, math.atan2(ty - s.y, tx - s.x), Soldiers.CHASE_WALK, dt) -- close in, rifle up
      end
    end
    shoot(server, s, tx, ty, dt)
    self:maybeLob(server, s, tx, ty, dt)
  elseif s.goal then
    if not pursue(self, s, dt) then
      s.goal, s.gaveUp = nil, true -- nothing there: back he goes
    end
  elseif s.trail then
    retrace(self, s, dt)
  elseif s.kind == "patrol" then
    self:patrol(s, dt)
  elseif s.kind == "guard" then
    local sweep = s.watch + Soldiers.SWEEP * math.sin(2 * math.pi * self.time / Soldiers.SWEEP_TIME + s.phase)
    s.facing = turn(s.facing, sweep, Soldiers.TURN, dt)
  else
    local nx, ny = nearest(server, s)
    if nx then
      local path = math.atan2(ny - s.y, nx - s.x)
      advance(s, path, Soldiers.WALK, dt)
      local look = path + Soldiers.SCAN * math.sin(self.time * 2.2 + s.phase)
      s.facing = turn(s.facing, look, Soldiers.TURN * 1.5, dt)
    end
  end
  if not tx and s.lostAt then
    self:maybeLob(server, s, nil, nil, dt)
  end
end

--- A squad member's tick when he has nobody himself: hold still and look
--- where a mate is shooting, or walk the beat (the leader) or his slot.
function Soldiers:patrol(s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m.alert and m ~= s then
      if self.hunt then
        setGoal(self, s, m.aimX, m.aimY, "search") -- with him
        if s.goal then
          return
        end
      end
      s.facing = turn(s.facing, math.atan2(m.aimY - s.y, m.aimX - s.x), Soldiers.TURN, dt)
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
    gx, gy, speed = to.x, to.y, Soldiers.PATROL_WALK
  else
    local slot = Soldiers.FORMATION[1]
    for i, m in ipairs(squad.members) do
      if m == s then
        slot = Soldiers.FORMATION[(i - 1) % #Soldiers.FORMATION + 1]
      end
    end
    local heading = leader.heading or leader.facing -- where he walks, not where he glances
    local c, sn = math.cos(heading), math.sin(heading)
    gx, gy = leader.x + slot[1] * c - slot[2] * sn, leader.y + slot[1] * sn + slot[2] * c
    local d = math.sqrt(dist2(s.x, s.y, gx, gy))
    if d < 6 then
      s.facing = turn(s.facing, heading, Soldiers.TURN, dt)
      return
    end
    speed = Soldiers.PATROL_WALK * math.min(1.6, 0.6 + d / 60) -- catch up when behind, ease in when there
  end
  local path = math.atan2(gy - s.y, gx - s.x)
  if leader == s then
    s.heading = path
  end
  advance(s, path, speed, dt)
  local look = path + Soldiers.SCAN * math.sin(self.time * 1.3 + s.phase)
  s.facing = turn(s.facing, look, Soldiers.TURN, dt)
end

-- Pinned down ----------------------------------------------------------------

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

--- Somewhere near (x, y) with something solid between it and `th`.
local function coverNear(x, y, th)
  return search(x, y, Soldiers.COVER_RANGE, x, y, 0.5, function(cx, cy)
    return not Sight.clear(th.x, th.y, cx, cy)
  end)
end

--- Walk straight to `to` if he isn't there yet; true while still on his way.
local function goTo(s, to, dt)
  if not to or dist2(s.x, s.y, to.x, to.y) <= 5 * 5 then
    return false
  end
  advance(s, math.atan2(to.y - s.y, to.x - s.x), Soldiers.CHASE_WALK, dt)
  return true
end

--- One step of `s` towards `to` by the walking grid, round whatever is in
--- the way: the way is worked out once for that spot, and again if he gets
--- caught on something. Returns the way he is heading, or nil once there.
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

--- Where `s` goes back to once a siege is over: a guard to where he left
--- his post from (or where he stands); a rifleman, or a squad on a beat,
--- just carries on from wherever he is.
local function placeOf(s)
  if s.returnTo then
    return s.returnTo
  elseif s.kind ~= "guard" then
    return nil
  end
  local home = s.trail and s.trail[1]
  return home and { x = home.x, y = home.y } or { x = s.x, y = s.y }
end

--- A round from somebody nobody saw hit (x, y), flying `angle`: the one it
--- hit (`hit`, if he lived) and everyone within PIN_SHARE with nobody in
--- his sights goes to ground, in the siege already there or a new one, and
--- the quiet starts again.
function Soldiers:underFire(x, y, angle, hit)
  local r2 = Soldiers.PIN_SHARE * Soldiers.PIN_SHARE
  local siege = nil
  for _, sg in ipairs(self.sieges) do
    for _, m in ipairs(sg.members) do
      if m.pin == sg and dist2(m.x, m.y, x, y) <= r2 then
        siege = sg
        break
      end
    end
    if siege then
      break
    end
  end
  if not siege then
    siege = { members = {}, quiet = 0 }
    self.sieges[#self.sieges + 1] = siege
  end
  siege.x, siege.y = x - math.cos(angle) * Soldiers.PIN_GUESS, y - math.sin(angle) * Soldiers.PIN_GUESS
  siege.quiet = 0
  for _, s in ipairs(self.list) do
    if s.pin == siege then
      if s == hit then
        s.pinCover = nil -- they can reach him there: somewhere else
      end
    elseif not (s.target or s.panic or s.frozen > 0) and dist2(s.x, s.y, x, y) <= r2 then
      s.back = placeOf(s) -- one out on a sweep: his post, the start of his trail
      s.pin, s.pinCover, s.goal, s.trail, s.returnTo, s.sweep = siege, nil, nil, nil, nil, nil
      s.alert = false
      siege.members[#siege.members + 1] = s
    end
  end
end

--- A pinned soldier's tick: to his cover, then crouched there watching the
--- way the rounds came from.
function Soldiers:holdDown(s, dt)
  local sg = s.pin
  s.alert = false
  if not s.pinCover then
    s.pinCover = coverNear(s.x, s.y, sg) or { x = s.x, y = s.y }
  end
  if goTo(s, s.pinCover, dt) then
    s.facing = turn(s.facing, math.atan2(s.pinCover.y - s.y, s.pinCover.x - s.x), Soldiers.TURN * 2, dt)
    return
  end
  local look = math.atan2(sg.y - s.y, sg.x - s.x) + Soldiers.SCAN * math.sin(self.time * 0.8 + s.phase)
  s.facing = turn(s.facing, look, Soldiers.TURN, dt)
end

--- Back to his post (`returnTo`) after a siege, shooting at whoever he has
--- on the way. True while still on his way.
function Soldiers:goBack(server, s, tx, ty, dt)
  s.backFor = (s.backFor or 0) + dt
  local path = s.backFor < 25 and walkTo(self, s, s.returnTo, Soldiers.CHASE_WALK, dt) -- or lost: this will do
  if not path then
    s.returnTo, s.backFor, s.way = nil, 0, nil
    return false
  end
  s.alert = tx ~= nil
  if tx then
    s.aimX, s.aimY = tx, ty
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Soldiers.TURN, dt)
    shoot(server, s, tx, ty, dt)
  else
    s.facing = turn(s.facing, path, Soldiers.TURN, dt)
  end
  return true
end

--- `s` sends himself to look round (x, y), or as near it as there is a way
--- to; false when there is none.
local function sendLooking(self, s, x, y)
  for _, f in ipairs({ 1, 0.75, 0.5 }) do
    setGoal(self, s, s.x + (x - s.x) * f, s.y + (y - s.y) * f, "search")
    if s.goal then
      return true
    end
    s.noRouteUntil = nil -- try the next one straight away
  end
  return false
end

--- QUIET is up: squads of them out to look round where the rounds came
--- from, nearest first. Each walks back to his post after (a rifleman
--- carries on down the hill).
function Soldiers:sendSweep(sg)
  if not self.hunt then
    return -- they hold their places: they wait it out
  end
  local pool = {}
  for _, m in ipairs(sg.members) do
    if m.pin == sg then
      pool[#pool + 1] = { s = m, d2 = dist2(m.x, m.y, sg.x, sg.y) }
    end
  end
  table.sort(pool, function(a, b)
    return a.d2 < b.d2
  end)
  local size = Soldiers.SWEEP_SQUAD
  sg.sent = {}
  for _, c in ipairs(pool) do
    if #sg.sent >= size * Soldiers.SWEEPS then
      break
    end
    local m, slot = c.s, #sg.sent % size
    -- The first of a squad to the spot, his mates a step to either side of it.
    local a = slot * 2 * math.pi / size
    local ox, oy = slot > 0 and math.cos(a) * 50 or 0, slot > 0 and math.sin(a) * 50 or 0
    local back = m.back
    m.trail = back and { { x = back.x, y = back.y } } or nil
    m.pin, m.pinCover = nil, nil
    if sendLooking(self, m, sg.x + ox, sg.y + oy) then
      m.back, m.sweep = nil, true
      sg.sent[#sg.sent + 1] = m
    else
      m.pin, m.trail = sg, nil -- no way there from his cover: he stays down
    end
  end
end

--- The siege is over (`tx`, `ty`: somebody has the shooter in his sights
--- there, or nil when it just went quiet): the pinned get up and go for the
--- shooter, or back to their posts; those out looking go for the shooter too.
function Soldiers:release(sg, tx, ty)
  for _, m in ipairs(sg.members) do
    if m.pin == sg then
      local back = m.back
      m.pin, m.pinCover, m.back = nil, nil, nil
      if tx and self.hunt then
        m.trail = back and { { x = back.x, y = back.y } } or nil
        setGoal(self, m, tx, ty, "search")
        if not m.goal then
          m.trail, m.returnTo = nil, back
        end
      else
        m.returnTo = back
      end
    end
  end
  for _, m in ipairs(sg.sent or {}) do
    if tx and m.hp > 0 and m.sweep and not m.target then
      setGoal(self, m, tx, ty, "search") -- out looking already: on to where the shooter is
    end
  end
end

--- `by` has somebody in his sights at (tx, ty): every siege near him is over.
function Soldiers:spotted(by, tx, ty)
  local r2 = Soldiers.SPOT_SHARE * Soldiers.SPOT_SHARE
  for i = #self.sieges, 1, -1 do
    local sg = self.sieges[i]
    local near = dist2(sg.x, sg.y, by.x, by.y) <= r2
    for _, m in ipairs(sg.members) do
      near = near or dist2(m.x, m.y, by.x, by.y) <= r2
    end
    for _, m in ipairs(sg.sent or {}) do
      near = near or m == by
    end
    if near then
      self:release(sg, tx, ty)
      table.remove(self.sieges, i)
    end
  end
end

--- The sieges' clocks: a sweep out after QUIET, over after RELEASE or once
--- nobody is left pinned or out on its sweep.
function Soldiers:stepSieges(dt)
  for i = #self.sieges, 1, -1 do
    local sg = self.sieges[i]
    sg.quiet = sg.quiet + dt
    for k = #sg.members, 1, -1 do
      local m = sg.members[k]
      if m.pin ~= sg or m.hp <= 0 then
        table.remove(sg.members, k)
      end
    end
    if not sg.swept and sg.quiet >= Soldiers.QUIET then
      sg.swept = true
      self:sendSweep(sg)
    end
    local out = false
    for _, m in ipairs(sg.sent or {}) do
      out = out or (m.hp > 0 and m.sweep == true)
    end
    if sg.quiet >= Soldiers.RELEASE or (#sg.members == 0 and not out) then
      self:release(sg)
      table.remove(self.sieges, i)
    end
  end
end

-- Grenades ---------------------------------------------------------------------

--- Maybe a grenade from `s`: at whoever he has at (tx, ty) now and then,
--- or with nobody in his sights at where he lost somebody a moment ago.
--- Never nearer than GRENADE_MIN, past its range, into a wall in the way
--- or where it would land on one of his own.
function Soldiers:maybeLob(server, s, tx, ty, dt)
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
    s.lobRoll = Soldiers.GRENADE_ROLL[1]
    if random() >= Soldiers.GRENADE_ROLL[2] then
      return
    end
    x, y = tx, ty
  elseif s.lostAt and self.time - s.lostAt < Soldiers.LOST_THROW and s.aimX then
    x, y = s.aimX, s.aimY
  else
    return
  end
  s.lostAt = nil -- one try at where they went
  local d2 = dist2(s.x, s.y, x, y)
  if d2 < Soldiers.GRENADE_MIN * Soldiers.GRENADE_MIN or d2 > G.range * G.range then
    return
  end
  local lx, ly = G.landing(s.x, s.y, x, y)
  if dist2(lx, ly, x, y) > (G.blast.radius * 0.6) ^ 2 then
    return -- a wall in the way would stop it short of them
  end
  for _, m in ipairs(self.list) do
    if dist2(m.x, m.y, lx, ly) < Soldiers.SPLASH_CLEAR * Soldiers.SPLASH_CLEAR then
      return
    end
  end
  if G:serverLob(server, s.x, s.y, x, y) then
    s.grenades, s.lobAt = s.grenades - 1, self.time + Soldiers.GRENADE_EVERY
    s.fireIn = math.max(s.fireIn, 0.5) -- the rifle waits while he throws
  end
end

-- Being shot at -------------------------------------------------------------

--- The soldier standing within `radius` of (x, y), and his index.
function Soldiers:at(x, y, radius)
  local r2 = (radius + Soldiers.RADIUS) ^ 2
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
function Soldiers:hurt(s, i, amount, angle)
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
    if angle and not s.target then
      self:underFire(s.x, s.y, angle) -- dropped by somebody none of them saw: the rest get down
    end
    return true
  end
  if angle and not s.target then
    s.facing = angle + math.pi -- back the way the round came
    self:underFire(s.x, s.y, angle, s) -- and down, with his mates, out of the line of it
  end
  return false
end

--- Everyone inside a freeze stands stiff for `seconds`.
function Soldiers:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Soldiers.RADIUS) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Everyone inside a stink runs from it for `seconds`.
function Soldiers:scare(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Soldiers.RADIUS) ^ 2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

return Soldiers
