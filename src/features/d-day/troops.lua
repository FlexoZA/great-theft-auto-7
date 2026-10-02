-- The defenders, on the host. Two kinds:
--
--   guard     stands at a post off the beach (in a bunker's embrasure, a gap
--             in a trench's sandbags, by a hut, on the hilltop) and sweeps
--             a thirty-degree cone of sight slowly from side to side over
--             the ground below.
--   rifleman  comes out of a barracks door and walks down the map towards
--             the nearest player, looking where he is going.
--
-- City 17 (a-man/city17.lua) adds a third:
--
--   patrol    one of a squad walking a beat round and round: the first of
--             them leads from corner to corner, the rest keep a step
--             behind him either side. When one of them has somebody the
--             squad stops and the others turn to look the same way.
--
-- A troop made with `hunt` on (City 17's) also leaves its place to hunt:
-- whoever has somebody in his sights closes in on them (to CHASE_KEEP,
-- never more than LEASH from where he started), and when he loses them he
-- goes to where he saw them last and looks round. A squad's mates go with
-- him. Troops:alarm sends anyone near enough to look into something (a
-- soldier going down, or one calling in who he has spotted). Either way he walks back the way he came after,
-- on the trail of breadcrumbs he dropped, and takes up his post or his
-- beat again. Given a walking grid (Troops:navigate, d-day/nav.lua) he
-- finds his way round walls to where he is going instead of walking
-- straight at it.
--
-- Any one that gets someone in his cone turns to follow them and, after
-- a moment to take aim, opens fire, and keeps firing for as long as he can
-- see them. Duck behind a hedgehog or a sandbag wall, or get out of his
-- cone faster than he can turn, and he stops; a guard goes back to his
-- sweep, a rifleman carries on down the hill.
--
-- Each one carries an AK unless he has been handed `arms` (Troops:arm,
-- City 17 does): any of the guns, fired in bursts and only once whoever he
-- is shooting at is within its reach.
--
-- They shoot through weapons' ownerless entry point (the police officers on
-- foot do the same), so their rounds hurt any player and credit nobody.
-- This module only thinks; init.lua owns the wire.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")

local Troops = {}
Troops.__index = Troops

-- Tuning --------------------------------------------------------------------

Troops.RADIUS = 9 -- px; as fat as an officer on foot (drawn as a person: src/body.lua)
Troops.HEALTH = 40 -- two pistol rounds
Troops.SHOT_DAMAGE = 20 -- what one round takes off (matches the pistol)
Troops.RANGE = 640 -- px they can see
Troops.SWEEP = math.rad(55) -- a guard's scan swings this far either side of where he watches
Troops.SWEEP_TIME = 6 -- seconds for one full swing there and back
Troops.TRACK_FOV = math.rad(60) -- once he has someone, he keeps them in a wider eye while turning
Troops.TURN = 2.0 -- rad/s turning to follow someone; sprint across his cone and he loses you
Troops.REACT = 0.7 -- seconds from spotting someone to the first shot
Troops.FIRE_EVERY = 0.6 -- seconds between rounds while he can see you
Troops.SPREAD = 0.06 -- radians of aim error, on top of the rifle's own
Troops.MUZZLE = 23 -- px from the body a round leaves: the tip of the rifle in his hands
Troops.LOOK_EVERY = 3 -- host ticks between sight checks (staggered by soldier)
Troops.WALK = 62 -- px/s a rifleman walks down the hill
Troops.SCAN = math.rad(20) -- a walking rifleman looks this far either side of his path
Troops.PATROL_WALK = 48 -- px/s a squad walks its beat
Troops.FORMATION = { { 0, 0 }, { -38, -30 }, { -38, 30 }, { -76, 0 } } -- slots behind the leader, his frame
Troops.CHASE_WALK = 90 -- px/s closing in or hunting: faster than a walk, slower than a sprint
Troops.CHASE_KEEP = 200 -- px; he stops closing in this near and just shoots
Troops.LEASH = 900 -- px from where he started that he will go after somebody
Troops.INVESTIGATE_WALK = 75 -- px/s going to look into something
Troops.SEARCH_TIME = 5 -- seconds looking round where he lost them, or at what he came to look into
Troops.SEARCH_SWEEP = math.rad(100) -- how far either way he looks round then
Troops.CRUMB = 40 -- px between the breadcrumbs he drops on his way, for the way back

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
---   health  what each one can take (Troops.HEALTH)
---   alertFov  how wide his cone is while he is on edge: has somebody, or
---           is searching or looking into something (`fov` throughout)
function Troops.new(opts)
  opts = opts or {}
  local t = { list = {}, nextId = 1, time = 0, ticks = 0, hunt = opts.hunt or false, fov = opts.fov,
    aware = opts.aware or 0, health = opts.health or Troops.HEALTH, alertFov = opts.alertFov }
  return setmetatable(t, Troops)
end

--- Is `s` on edge: somebody in his sights, or out searching or looking
--- into something?
function Troops.wary(s)
  return s.alert or s.goal ~= nil
end

--- How wide `s`'s cone of sight is right now.
function Troops:fovOf(s)
  if self.alertFov and Troops.wary(s) then
    return self.alertFov
  end
  return self.fov or Sight.FOV
end

--- A soldier of `kind` at (x, y), watching `watch` (radians).
function Troops:add(kind, x, y, watch)
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
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- Put `count` guards on the map's posts, picked at random, each watching
--- down the hill (south) give or take a little.
function Troops:placeGuards(map, count)
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
function Troops:reinforce(map)
  local door = map.doors[random(#map.doors)]
  return self:add("rifleman", door.x + (random() - 0.5) * 30, door.y, math.pi / 2)
end

--- A squad of `size` walking `route` (a loop of { x, y }), starting at
--- corner `start` (one picked at random when nil), heading for the next.
function Troops:addSquad(route, size, start)
  local leg = start or random(#route)
  local from = route[leg]
  leg = leg % #route + 1
  local squad = { route = route, leg = leg, members = {} }
  local to = route[leg]
  local heading = math.atan2(to.y - from.y, to.x - from.x)
  for i = 1, size do
    local slot = Troops.FORMATION[(i - 1) % #Troops.FORMATION + 1]
    local c, sn = math.cos(heading), math.sin(heading)
    local s = self:add("patrol", from.x + slot[1] * c - slot[2] * sn, from.y + slot[1] * sn + slot[2] * c, heading)
    s.squad = squad
    squad.members[i] = s
  end
  return squad
end

function Troops:count(kind)
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
  local r = Troops.RADIUS
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
  if dist2(s.x, s.y, last.x, last.y) >= Troops.CRUMB * Troops.CRUMB then
    trail[#trail + 1] = { x = s.x, y = s.y }
  end
end

--- Is (x, y) past his leash, from where he left?
local function leashed(s, x, y)
  local home = s.trail and s.trail[1]
  return home ~= nil and dist2(home.x, home.y, x, y) > Troops.LEASH * Troops.LEASH
end

--- The way to (x, y) for `s`: corners to walk through, the last being
--- (x, y). Straight there without a walking grid; nil if the grid has no
--- way, or only one too long to bother with.
local function route(self, s, x, y)
  if not self.nav then
    return { { x = x, y = y } }
  end
  local corners, length = self.nav:path(s.x, s.y, x, y)
  if not corners or length > Troops.LEASH * 1.6 then
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
    local around = g.facing + Troops.SEARCH_SWEEP * math.sin(2 * math.pi * g.look / Troops.SEARCH_TIME * 1.5)
    s.facing = turn(s.facing, around, Troops.TURN, dt)
    return g.look > 0
  end
  local speed = g.kind == "investigate" and Troops.INVESTIGATE_WALK or Troops.CHASE_WALK
  local to = g.corners[g.at]
  local last = g.at == #g.corners
  if dist2(s.x, s.y, to.x, to.y) < (last and 28 or 18) ^ 2 then
    if last then
      g.look, g.facing = Troops.SEARCH_TIME, s.facing
      return true
    end
    g.at = g.at + 1
    to = g.corners[g.at]
  end
  local path = math.atan2(to.y - s.y, to.x - s.x)
  advance(s, path, speed, dt)
  crumb(s)
  s.facing = turn(s.facing, path + Troops.SCAN * math.sin(self.time * 2 + s.phase), Troops.TURN, dt)
  if s.stuck > 1.5 then
    -- Caught on something after all: find the way again from here, once;
    -- after that, look round from where he got to.
    local corners = not g.replanned and route(self, s, g.x, g.y)
    if corners then
      g.corners, g.at, g.replanned, s.stuck = corners, 1, true, 0
    else
      g.look, g.facing = Troops.SEARCH_TIME, path
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
  advance(s, path, Troops.INVESTIGATE_WALK, dt)
  s.facing = turn(s.facing, path + Troops.SCAN * math.sin(self.time * 1.3 + s.phase), Troops.TURN, dt)
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
function Troops:navigate(bounds)
  self.nav = Nav.build(bounds)
end

--- Something happened at (x, y) (a soldier went down, or one called in
--- somebody he spotted): everyone within `radius` who has nobody in his
--- sights goes to look into it, nearest first. `opts` (optional):
---   from  the one calling it in: neither he nor his squad (they go with
---         him anyway) answers
---   most  how many go at most (everyone)
--- Returns who went, nearest first.
function Troops:alarm(x, y, radius, opts)
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
    if not own and not s.target and not s.panic and d2 <= radius * radius then
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
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Troops.RANGE, fov)
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
function Troops:arm(s, arms)
  s.arms, s.burstLeft = arms, arms.burst
end

--- One round (or one pull of a shotgun) at (tx, ty), from the muzzle, a little off.
local function fire(server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Troops.SPREAD
  local mx, my = s.x + math.cos(aim) * Troops.MUZZLE, s.y + math.sin(aim) * Troops.MUZZLE
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
    s.fireIn = Troops.FIRE_EVERY * (0.85 + random() * 0.3)
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
function Troops:update(server, dt)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  for _, s in ipairs(self.list) do
    self:think(server, s, dt)
  end
end

function Troops:think(server, s, dt)
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
    walk(s, s.facing, Troops.WALK * 2, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end

  -- Look, a few times a second: keep the one in his sights while he still
  -- can, otherwise whoever has just walked into his cone.
  if (self.ticks + s.id) % Troops.LOOK_EVERY == 0 then
    local tx, ty = nil, nil
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    -- Once he has someone he keeps them in a wider eye: TRACK_FOV, or more for a wide cone.
    local fov = self:fovOf(s)
    local track = math.max(Troops.TRACK_FOV, fov + math.rad(30))
    local kept = tx
      and (Sight.canSee(s.x, s.y, s.facing, tx, ty, Troops.RANGE, track)
        or (self.aware > 0 and Sight.canSee(s.x, s.y, s.facing, tx, ty, self.aware, 2 * math.pi)))
    if not kept then
      s.target = spot(server, s, fov, self.aware)
      if s.target then
        -- A moment to take aim, and longer if he has to turn round first.
        local px, py = poseOf(server, s.target)
        local behind = px and math.abs(Sight.angleDiff(math.atan2(py - s.y, px - s.x), s.facing)) or 0
        s.fireIn = Troops.REACT + behind / Troops.TURN
      end
    end
  end

  local tx, ty = nil, nil
  if s.target then
    tx, ty = poseOf(server, s.target)
    if not tx then
      s.target = nil
    end
  end
  if self.hunt and s.alert and not tx and s.aimX then
    setGoal(self, s, s.aimX, s.aimY, "search") -- lost them: to where they were last
  end
  s.alert = s.target ~= nil

  if tx then
    s.aimX, s.aimY = tx, ty
    s.goal = nil
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Troops.TURN, dt)
    -- Close in to CHASE_KEEP, or nearer with a gun that doesn't reach that far.
    local keep = s.arms and math.min(Troops.CHASE_KEEP, s.arms.reach * 0.6) or Troops.CHASE_KEEP
    if self.hunt and dist2(s.x, s.y, tx, ty) > keep * keep then
      crumb(s)
      if not leashed(s, s.x + (tx - s.x) * 0.1, s.y + (ty - s.y) * 0.1) then
        walk(s, math.atan2(ty - s.y, tx - s.x), Troops.CHASE_WALK, dt) -- close in, rifle up
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
  elseif s.kind == "guard" then
    local sweep = s.watch + Troops.SWEEP * math.sin(2 * math.pi * self.time / Troops.SWEEP_TIME + s.phase)
    s.facing = turn(s.facing, sweep, Troops.TURN, dt)
  else
    local nx, ny = nearest(server, s)
    if nx then
      local path = math.atan2(ny - s.y, nx - s.x)
      advance(s, path, Troops.WALK, dt)
      local look = path + Troops.SCAN * math.sin(self.time * 2.2 + s.phase)
      s.facing = turn(s.facing, look, Troops.TURN * 1.5, dt)
    end
  end
end

--- A squad member's tick when he has nobody himself: hold still and look
--- where a mate is shooting, or walk the beat (the leader) or his slot.
function Troops:patrol(s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m.alert and m ~= s then
      if self.hunt then
        setGoal(self, s, m.aimX, m.aimY, "search") -- with him
        if s.goal then
          return
        end
      end
      s.facing = turn(s.facing, math.atan2(m.aimY - s.y, m.aimX - s.x), Troops.TURN, dt)
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
    gx, gy, speed = to.x, to.y, Troops.PATROL_WALK
  else
    local slot = Troops.FORMATION[1]
    for i, m in ipairs(squad.members) do
      if m == s then
        slot = Troops.FORMATION[(i - 1) % #Troops.FORMATION + 1]
      end
    end
    local heading = leader.heading or leader.facing -- where he walks, not where he glances
    local c, sn = math.cos(heading), math.sin(heading)
    gx, gy = leader.x + slot[1] * c - slot[2] * sn, leader.y + slot[1] * sn + slot[2] * c
    local d = math.sqrt(dist2(s.x, s.y, gx, gy))
    if d < 6 then
      s.facing = turn(s.facing, heading, Troops.TURN, dt)
      return
    end
    speed = Troops.PATROL_WALK * math.min(1.6, 0.6 + d / 60) -- catch up when behind, ease in when there
  end
  local path = math.atan2(gy - s.y, gx - s.x)
  if leader == s then
    s.heading = path
  end
  advance(s, path, speed, dt)
  local look = path + Troops.SCAN * math.sin(self.time * 1.3 + s.phase)
  s.facing = turn(s.facing, look, Troops.TURN, dt)
end

-- Being shot at -------------------------------------------------------------

--- The soldier standing within `radius` of (x, y), and his index.
function Troops:at(x, y, radius)
  local r2 = (radius + Troops.RADIUS) ^ 2
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
function Troops:hurt(s, i, amount, angle)
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
  if angle and not s.target then
    s.facing = angle + math.pi -- back the way the round came
    if self.hunt then -- and off that way to find who sent it
      setGoal(self, s, s.x - math.cos(angle) * 260, s.y - math.sin(angle) * 260, "search")
    end
  end
  return false
end

--- Everyone inside a freeze stands stiff for `seconds`.
function Troops:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Troops.RADIUS) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Everyone inside a stink runs from it for `seconds`.
function Troops:scare(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Troops.RADIUS) ^ 2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

return Troops
