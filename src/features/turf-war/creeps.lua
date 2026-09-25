-- The creeps on the host: each side's foot soldiers, of two kinds.
--
--   simp     a hanger-on with his fists, like Karen's: runs at the nearest
--            enemy he sees and punches. The opening creep on every lane.
--   soldier  a rifleman, like D-Day's, in the side's colours: stops and
--            fires rifle bursts at the nearest enemy he sees. A side sends
--            soldiers down a lane once it has broken that lane: every one
--            of the other side's towers on it down (Dota's mega creeps).
--
-- They come in waves out of a base's three gates and walk their lane
-- towards the other base, a file of them a little off the centreline, and
-- on past the far gate to the enemy vault, where they stand. Every creep
-- watches all round himself as far as a tower does (Creeps.RANGE, the
-- towers' detection zone) and only where nothing solid stands in the way;
-- the nearest enemy he sees, player or creep, is his target. Lose him
-- behind a wall or a tree and he walks on.
--
-- A soldier's rounds belong to nobody (weapons' ownerless entry point) but
-- carry his side, so they pass through his own team and its towers take no
-- notice of them. Two pistol rounds put a creep down; a car at speed
-- flattens one. Both sides send waves the whole war, whoever is on the
-- map, so a lone player has creeps of their own to march with.
--
-- This module only thinks; init.lua owns the wire, the waves' timing, the
-- lane rule and what a kill drops.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")
local Car = require("src.car")
local Towers = require("src.features.turf-war.towers")

local Creeps = {}
Creeps.__index = Creeps

-- Tuning --------------------------------------------------------------------

Creeps.RADIUS = 7 -- px; as fat as a player on foot
Creeps.HEALTH = 40 -- two pistol rounds
Creeps.SHOT_DAMAGE = 20 -- what one round takes off (matches the pistol)
Creeps.RANGE = Towers.RANGE -- px he sees, all round: the same as a tower's zone
Creeps.TURN = 3.5 -- rad/s turning to face someone
Creeps.LOOK_EVERY = 3 -- host ticks between looks round (staggered by creep)
Creeps.STEP = 12 -- px between line-of-sight samples
Creeps.WALK = 62 -- px/s down the lane
Creeps.SCAN = math.rad(25) -- a walking creep looks this far either side of his path
Creeps.SPLAT_SPEED = 90 -- car speed (px/s) that turns one into a stain
Creeps.PER_WAVE = 5 -- creeps in a wave, spread over the three lanes
Creeps.WAVE_EVERY = 45 -- seconds between a side's waves
Creeps.FIRST_WAVE = 4 -- seconds after the war starts before the first
Creeps.MAX_ALIVE = 15 -- a side sends no more while this many of its are out
Creeps.SPACING = 40 -- px between the creeps of a file at the gate
Creeps.LATERAL = 55 -- px either side of the lane's centreline a creep keeps to
Creeps.NODE_REACH = 26 -- px from a lane node that counts as reaching it
Creeps.VAULT_STANDOFF = 150 -- px from the enemy vault they stop at
Creeps.DROP = 1 -- koins a creep drops, like a pedestrian
-- Soldiers.
Creeps.REACT = 0.6 -- seconds from spotting someone to the first shot
Creeps.FIRE_EVERY = 0.6 -- seconds between rounds while he can see them
Creeps.SPREAD = 0.06 -- radians of aim error, on top of the rifle's own
Creeps.MUZZLE = 12 -- px from the body a round leaves
Creeps.gun = Guns.ak47 -- what a soldier fires: rifle bursts
-- Simps.
Creeps.CHASE = 135 -- px/s once a simp has picked someone
Creeps.REACH = 14 -- px past his body a punch lands
Creeps.PUNCH_DAMAGE = 8
Creeps.PUNCH_EVERY = 1.0 -- seconds between punches

local random = love.math.random
local TOUCH2 = (Car.WIDTH / 2 + Creeps.RADIUS + 2) ^ 2
local LANES = { "top", "bottom", "mid" } -- the order a wave is dealt over the lanes: 2, 2, 1

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function Creeps.new()
  return setmetatable({ list = {}, nextId = 1, time = 0, ticks = 0, kills = {} }, Creeps)
end

--- A creep of `kind` ("simp" or "soldier") and `team` on `lane` (its
--- polyline, walked from its own gate) at (x, y), facing `facing`.
function Creeps:add(kind, team, lane, x, y, facing)
  local s = {
    id = self.nextId,
    kind = kind,
    team = team,
    lane = lane,
    x = x,
    y = y,
    facing = facing,
    hp = Creeps.HEALTH,
    node = nil, -- the next lane node to reach (set by the walk), nil past the far gate
    lateral = (random() * 2 - 1) * Creeps.LATERAL,
    target = nil, -- { kind = "player", id } or { kind = "creep", s }
    fireIn = 0,
    punchIn = Creeps.PUNCH_EVERY,
    swing = 0, -- seconds left of a simp's punch, for clients
    alert = false,
    frozen = 0,
    panic = nil,
    stuck = 0,
    sidestep = 0,
    side = random() < 0.5 and -1 or 1,
    phase = random() * 2 * math.pi,
    arrived = false,
    dead = false,
  }
  self.nextId = self.nextId + 1
  self.list[#self.list + 1] = s
  return s
end

--- A wave of `count` creeps of `team` out of its gates on `map`: a file
--- back into the courtyard from each gate, two on the top lane, two on the
--- bottom, one down the middle for five. `kindOf(laneName)` says what
--- kind goes down each lane. Returns the new creeps.
function Creeps:wave(map, team, count, kindOf)
  local out = {}
  local perLane = {}
  for k = 1, count do
    local name = LANES[(k - 1) % #LANES + 1]
    local lane = map.lanes.byName[name]
    local pts = lane.points
    local gate, next = pts[1], pts[2]
    if team == 2 then
      gate, next = pts[#pts], pts[#pts - 1]
    end
    local len = math.sqrt(dist2(gate.x, gate.y, next.x, next.y))
    local dx, dy = (next.x - gate.x) / len, (next.y - gate.y) / len
    perLane[name] = (perLane[name] or 0) + 1
    local back = 30 + perLane[name] * Creeps.SPACING
    local s = self:add(kindOf(name), team, lane, gate.x - dx * back, gate.y - dy * back, math.atan2(dy, dx))
    s.x, s.y = s.x - dy * s.lateral, s.y + dx * s.lateral
    out[#out + 1] = s
  end
  return out
end

function Creeps:count(team, kind)
  local n = 0
  for _, s in ipairs(self.list) do
    if (not team or s.team == team) and (not kind or s.kind == kind) then
      n = n + 1
    end
  end
  return n
end

-- Walking -------------------------------------------------------------------

--- Solid ground, through the `blocksPoint` convention, at the four extremes
--- of the body.
local function blockedAt(x, y)
  local r = Creeps.RADIUS
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
  local d = Towers.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- Where a creep is heading right now: the next node of his lane, kept a
--- little to his side of the centreline, then the enemy vault. Nil once he
--- stands before it.
local function goal(s, map)
  local pts = s.lane.points
  local n = #pts
  if s.node == nil then
    s.node = s.team == 1 and 2 or n - 1
  end
  local i = s.node
  local step = s.team == 1 and 1 or -1
  if i >= 1 and i <= n then
    local a, b = pts[i - step], pts[i]
    local len = math.sqrt(dist2(a.x, a.y, b.x, b.y))
    local dx, dy = (b.x - a.x) / len, (b.y - a.y) / len
    local gx, gy = b.x - dy * s.lateral, b.y + dx * s.lateral
    if dist2(s.x, s.y, gx, gy) <= Creeps.NODE_REACH ^ 2 then
      s.node = i + step
      return goal(s, map)
    end
    return gx, gy
  end
  local vault = map.bases[3 - s.team].vault
  if dist2(s.x, s.y, vault.x, vault.y) <= Creeps.VAULT_STANDOFF ^ 2 then
    s.arrived = true
    return nil
  end
  return vault.x, vault.y
end

-- Seeing --------------------------------------------------------------------

--- Is the straight line from (x0, y0) to (x1, y1) free of walls?
local function clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Creeps.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Features.any("blocksPoint", x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Where a target is, if it is still there to be fought: x, y, and true
--- for a player driving (a punch has to reach past the car).
local function poseOf(server, target)
  if target.kind == "player" then
    local p = server.players[target.id]
    if p and Features.present(p) then
      local x, y, onFoot = Features.bodyPose(server, p)
      return x, y, not onFoot
    end
    return nil
  end
  local s = target.s
  if not s.dead then
    return s.x, s.y, false
  end
  return nil
end

--- Can the creep see (x, y) from where he stands? Within range and clear.
local function canSee(s, x, y)
  local d2 = dist2(s.x, s.y, x, y)
  return d2 <= Creeps.RANGE * Creeps.RANGE and clear(s.x, s.y, x, y) and d2 or nil
end

--- The nearest enemy in sight: a player of the other side (or of no side)
--- or one of the other side's creeps.
function Creeps:spot(server, s, teamOf)
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.present(p) and teamOf(p) ~= s.team then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(s.x, s.y, x, y)
      if d2 <= Creeps.RANGE * Creeps.RANGE and (not bestD2 or d2 < bestD2) and clear(s.x, s.y, x, y) then
        best, bestD2 = { kind = "player", id = id }, d2
      end
    end
  end
  for _, o in ipairs(self.list) do
    if o.team ~= s.team then
      local d2 = dist2(s.x, s.y, o.x, o.y)
      if d2 <= Creeps.RANGE * Creeps.RANGE and (not bestD2 or d2 < bestD2) and clear(s.x, s.y, o.x, o.y) then
        best, bestD2 = { kind = "creep", s = o }, d2
      end
    end
  end
  return best
end

-- Thinking ------------------------------------------------------------------

--- One round at (tx, ty), from the muzzle, a little off, carrying his side.
local function fire(server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Creeps.SPREAD
  local mx, my = s.x + math.cos(aim) * Creeps.MUZZLE, s.y + math.sin(aim) * Creeps.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, Creeps.gun, s.team)
end

--- A simp's punch on his target: a player is hurt through weapons (nobody's
--- blow; the target is an enemy by choice), a creep is hurt here. Returns
--- the kill when a creep went down.
function Creeps:punch(server, s, target)
  s.punchIn = Creeps.PUNCH_EVERY
  s.swing = 0.3
  if target.kind == "player" then
    local weapons = Features.byName.weapons
    local p = server.players[target.id]
    if weapons and weapons.serverDamage and p then
      weapons:serverDamage(server, p, nil, Creeps.PUNCH_DAMAGE, s.facing)
    end
    return nil
  end
  for i, o in ipairs(self.list) do
    if o == target.s then
      if self:hurt(o, i, Creeps.PUNCH_DAMAGE, s.facing) then
        return { s = o, by = nil, angle = s.facing }
      end
      return nil
    end
  end
  return nil
end

--- Everyone's tick: who they can see, whether they fight, else the walk.
--- `teamOf(player)` is a player's side. Returns this tick's kills by cars
--- and fists (a reused list of { s, by, angle }); the caller announces
--- them (the dead are already out of the list).
function Creeps:update(server, dt, map, teamOf)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  local kills = self.kills
  for i = #kills, 1, -1 do
    kills[i] = nil
  end
  local i = 1
  while i <= #self.list do
    local s = self.list[i]
    local kill = self:think(server, s, dt, map, teamOf) or self:trampled(server, s, dt)
    if kill and kill.s == s then
      self:remove(s)
      kills[#kills + 1] = kill
    else
      if kill then
        kills[#kills + 1] = kill -- somebody else went down (a punch); he is out of the list already
      end
      i = i + 1
    end
  end
  return kills
end

function Creeps:think(server, s, dt, map, teamOf)
  s.swing = math.max(0, s.swing - dt)
  if s.frozen > 0 then
    s.frozen = s.frozen - dt -- frozen stiff: no looking, no fighting
    s.alert, s.target = false, nil
    return nil
  end
  if s.panic then
    -- A stink: away from it, the fight forgotten.
    s.alert, s.target = false, nil
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    walk(s, s.facing, Creeps.WALK * 2, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return nil
  end

  -- Look, a few times a second: keep the one he has while he still can,
  -- otherwise whoever is nearest in sight.
  if (self.ticks + s.id) % Creeps.LOOK_EVERY == 0 then
    local tx, ty = nil, nil
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    if not (tx and canSee(s, tx, ty)) then
      s.target = self:spot(server, s, teamOf)
      if s.target then
        s.fireIn = Creeps.REACT
      end
    end
  end

  local tx, ty, driving = nil, nil, false
  if s.target then
    tx, ty, driving = poseOf(server, s.target)
    if not tx then
      s.target = nil
    end
  end
  s.alert = s.target ~= nil

  if tx and s.kind == "soldier" then
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Creeps.TURN, dt)
    s.fireIn = s.fireIn - dt
    if s.fireIn <= 0 then
      s.fireIn = Creeps.FIRE_EVERY * (0.85 + random() * 0.3)
      fire(server, s, tx, ty)
    end
  elseif tx then
    -- A simp: run at them and swing whatever is in reach.
    s.facing = math.atan2(ty - s.y, tx - s.x)
    local reach = Creeps.RADIUS + Creeps.REACH + (driving and Car.HEIGHT / 2 or Creeps.RADIUS)
    local d = math.sqrt(dist2(s.x, s.y, tx, ty))
    if d > reach then
      advance(s, s.facing, Creeps.CHASE, dt)
    end
    s.punchIn = s.punchIn - dt
    if d <= reach and s.punchIn <= 0 then
      return self:punch(server, s, s.target)
    end
  elseif not s.arrived then
    local gx, gy = goal(s, map)
    if gx then
      local path = math.atan2(gy - s.y, gx - s.x)
      advance(s, path, Creeps.WALK, dt)
      local look = path + Creeps.SCAN * math.sin(self.time * 2.2 + s.phase)
      s.facing = turn(s.facing, look, Creeps.TURN * 1.5, dt)
    end
  end
  return nil
end

--- A car touching this creep: flattened at speed, shoved aside below it.
--- Returns the kill ({ s, by, angle }) for the caller to announce.
function Creeps:trampled(server, s, dt)
  for id, p in pairs(server.players) do
    local car = p.vehicle
    local near = car and Features.present(p) and dist2(car.x, car.y, s.x, s.y) < TOUCH2
    if near and Car.hitTest(car, s.x, s.y, Creeps.RADIUS) then
      local speed = math.abs(car.speed)
      if speed >= Creeps.SPLAT_SPEED then
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        return { s = s, by = id, angle = travel }
      end
      local away = math.atan2(s.y - car.y, s.x - car.x)
      local push = (Creeps.WALK + speed) * dt * 2
      s.x, s.y = s.x + math.cos(away) * push, s.y + math.sin(away) * push
    end
  end
  return nil
end

-- Being shot at -------------------------------------------------------------

--- The creep standing within `radius` of (x, y), and his index. With
--- `team`, only one of the other side (a side's own rounds fly through).
function Creeps:at(x, y, radius, team)
  local r2 = (radius + Creeps.RADIUS) ^ 2
  for i, s in ipairs(self.list) do
    if s.team ~= team and dist2(s.x, s.y, x, y) < r2 then
      return s, i
    end
  end
  return nil
end

--- Take `amount` off `s` (the i-th). Returns true if that killed him; he
--- is gone from the list then. A living one who is hurt turns to look for
--- whoever did it.
function Creeps:hurt(s, i, amount, angle)
  s.hp = s.hp - amount
  if s.hp <= 0 then
    s.dead = true
    table.remove(self.list, i)
    return true
  end
  if angle and not s.target then
    s.facing = angle + math.pi -- back the way the round came
  end
  return false
end

--- Take `s` out of the world (a car got him).
function Creeps:remove(s)
  for i, o in ipairs(self.list) do
    if o == s then
      s.dead = true
      table.remove(self.list, i)
      return
    end
  end
end

--- Everyone inside a freeze stands stiff for `seconds`.
function Creeps:freeze(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Creeps.RADIUS) ^ 2 then
      s.frozen = math.max(s.frozen, seconds)
    end
  end
end

--- Everyone inside a stink runs from it for `seconds`.
function Creeps:scare(x, y, radius, seconds)
  for _, s in ipairs(self.list) do
    if dist2(s.x, s.y, x, y) <= (radius + Creeps.RADIUS) ^ 2 then
      s.panic = { x = x, y = y, left = seconds }
    end
  end
end

function Creeps:clear()
  for _, s in ipairs(self.list) do
    s.dead = true
  end
  self.list = {}
end

return Creeps
