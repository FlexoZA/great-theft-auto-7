-- The soldiers on the host: each side's creeps. They come in waves out of
-- a base's three gates and walk their lane towards the other base, a file
-- of them a little off the centreline, and on past the far gate to the
-- enemy vault, where they stand. Every soldier watches all round himself
-- as far as a tower does (Soldiers.RANGE, the towers' detection zone) and
-- only where nothing solid stands in the way; the first enemy he sees,
-- player or soldier, stops him, and after a moment to aim he fires rifle
-- bursts at them for as long as he can see them. Lose him behind a wall or
-- a tree and he walks on.
--
-- Their rounds belong to nobody (weapons' ownerless entry point) but carry
-- their side, so they pass through their own team and its towers take no
-- notice of them. Two pistol rounds put one down; a car at speed flattens
-- one. A wave is only sent down a lane while the other side has a human
-- to fight, so nobody marches on an empty base.
--
-- This module only thinks; init.lua owns the wire, the waves' timing and
-- what a kill drops.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")
local Car = require("src.car")
local Towers = require("src.features.turf-war.towers")

local Soldiers = {}
Soldiers.__index = Soldiers

-- Tuning --------------------------------------------------------------------

Soldiers.RADIUS = 7 -- px; as fat as a player on foot
Soldiers.HEALTH = 40 -- two pistol rounds
Soldiers.SHOT_DAMAGE = 20 -- what one round takes off (matches the pistol)
Soldiers.RANGE = Towers.RANGE -- px he sees, all round: the same as a tower's zone
Soldiers.TURN = 3.5 -- rad/s turning to face someone
Soldiers.REACT = 0.6 -- seconds from spotting someone to the first shot
Soldiers.FIRE_EVERY = 0.6 -- seconds between rounds while he can see them
Soldiers.SPREAD = 0.06 -- radians of aim error, on top of the rifle's own
Soldiers.MUZZLE = 12 -- px from the body a round leaves
Soldiers.LOOK_EVERY = 3 -- host ticks between looks round (staggered by soldier)
Soldiers.STEP = 12 -- px between line-of-sight samples
Soldiers.WALK = 62 -- px/s down the lane
Soldiers.SCAN = math.rad(25) -- a walking soldier looks this far either side of his path
Soldiers.SPLAT_SPEED = 90 -- car speed (px/s) that turns one into a stain
Soldiers.PER_WAVE = 5 -- soldiers in a wave, spread over the three lanes
Soldiers.WAVE_EVERY = 45 -- seconds between a side's waves
Soldiers.FIRST_WAVE = 4 -- seconds after the war starts before the first
Soldiers.MAX_ALIVE = 15 -- a side sends no more while this many of its are out
Soldiers.SPACING = 40 -- px between the soldiers of a file at the gate
Soldiers.LATERAL = 55 -- px either side of the lane's centreline a soldier keeps to
Soldiers.NODE_REACH = 26 -- px from a lane node that counts as reaching it
Soldiers.VAULT_STANDOFF = 150 -- px from the enemy vault they stop at
Soldiers.DROP = 1 -- koins a soldier drops, like a pedestrian
Soldiers.gun = Guns.ak47 -- what he fires: rifle bursts

local random = love.math.random
local TOUCH2 = (Car.WIDTH / 2 + Soldiers.RADIUS + 2) ^ 2
local LANES = { "top", "bottom", "mid" } -- the order a wave is dealt over the lanes: 2, 2, 1

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function Soldiers.new()
  return setmetatable({ list = {}, nextId = 1, time = 0, ticks = 0 }, Soldiers)
end

--- A soldier of `team` on `lane` (its polyline, walked from its own gate)
--- at (x, y), facing `facing`.
function Soldiers:add(team, lane, x, y, facing)
  local s = {
    id = self.nextId,
    team = team,
    lane = lane,
    x = x,
    y = y,
    facing = facing,
    hp = Soldiers.HEALTH,
    node = nil, -- the next lane node to reach (set by the walk), nil past the far gate
    lateral = (random() * 2 - 1) * Soldiers.LATERAL,
    target = nil, -- { kind = "player", id } or { kind = "soldier", s }
    fireIn = 0,
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

--- A wave of `count` soldiers of `team` out of its gates on `map`: a file
--- back into the courtyard from each gate, two on the top lane, two on the
--- bottom, one down the middle for five. Returns the new soldiers.
function Soldiers:wave(map, team, count)
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
    local back = 30 + perLane[name] * Soldiers.SPACING
    local s = self:add(team, lane, gate.x - dx * back, gate.y - dy * back, math.atan2(dy, dx))
    s.x, s.y = s.x - dy * s.lateral, s.y + dx * s.lateral
    out[#out + 1] = s
  end
  return out
end

function Soldiers:count(team)
  local n = 0
  for _, s in ipairs(self.list) do
    if not team or s.team == team then
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
  local d = Towers.angleDiff(to, from)
  local step = rate * dt
  if math.abs(d) <= step then
    return to
  end
  return from + (d > 0 and step or -step)
end

--- Where a soldier is heading right now: the next node of his lane, kept
--- a little to his side of the centreline, then the enemy vault. Nil once
--- he stands before it.
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
    if dist2(s.x, s.y, gx, gy) <= Soldiers.NODE_REACH ^ 2 then
      s.node = i + step
      return goal(s, map)
    end
    return gx, gy
  end
  local vault = map.bases[3 - s.team].vault
  if dist2(s.x, s.y, vault.x, vault.y) <= Soldiers.VAULT_STANDOFF ^ 2 then
    s.arrived = true
    return nil
  end
  return vault.x, vault.y
end

-- Seeing --------------------------------------------------------------------

--- Is the straight line from (x0, y0) to (x1, y1) free of walls?
local function clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Soldiers.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Features.any("blocksPoint", x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Where a target is, if it is still there to be shot at.
local function poseOf(server, target)
  if target.kind == "player" then
    local p = server.players[target.id]
    if p and Features.present(p) then
      return Features.bodyPose(server, p)
    end
    return nil
  end
  local s = target.s
  if not s.dead then
    return s.x, s.y
  end
  return nil
end

--- Can the soldier see (x, y) from where he stands? Within range and clear.
local function canSee(s, x, y)
  local d2 = dist2(s.x, s.y, x, y)
  return d2 <= Soldiers.RANGE * Soldiers.RANGE and clear(s.x, s.y, x, y) and d2 or nil
end

--- The nearest enemy in sight: a player of the other side (or of no side)
--- or one of the other side's soldiers.
function Soldiers:spot(server, s, teamOf)
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.present(p) and teamOf(p) ~= s.team then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(s.x, s.y, x, y)
      if d2 <= Soldiers.RANGE * Soldiers.RANGE and (not bestD2 or d2 < bestD2) and clear(s.x, s.y, x, y) then
        best, bestD2 = { kind = "player", id = id }, d2
      end
    end
  end
  for _, o in ipairs(self.list) do
    if o.team ~= s.team then
      local d2 = dist2(s.x, s.y, o.x, o.y)
      if d2 <= Soldiers.RANGE * Soldiers.RANGE and (not bestD2 or d2 < bestD2) and clear(s.x, s.y, o.x, o.y) then
        best, bestD2 = { kind = "soldier", s = o }, d2
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
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Soldiers.SPREAD
  local mx, my = s.x + math.cos(aim) * Soldiers.MUZZLE, s.y + math.sin(aim) * Soldiers.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, Soldiers.gun, s.team)
end

--- Everyone's tick: who they can see, whether they shoot, else the walk.
--- `teamOf(player)` is a player's side. Returns this tick's kills by cars
--- (a reused list of { s, by, angle }); the caller removes and announces.
function Soldiers:update(server, dt, map, teamOf)
  self.time = self.time + dt
  self.ticks = self.ticks + 1
  local kills = self.kills or {}
  self.kills = kills
  for i = #kills, 1, -1 do
    kills[i] = nil
  end
  for _, s in ipairs(self.list) do
    self:think(server, s, dt, map, teamOf)
    local kill = self:trampled(server, s, dt)
    if kill then
      kills[#kills + 1] = kill
    end
  end
  return kills
end

function Soldiers:think(server, s, dt, map, teamOf)
  if s.frozen > 0 then
    s.frozen = s.frozen - dt -- frozen stiff: no looking, no shooting
    s.alert, s.target = false, nil
    return
  end
  if s.panic then
    -- A stink: away from it, rifle forgotten.
    s.alert, s.target = false, nil
    s.panic.left = s.panic.left - dt
    s.facing = math.atan2(s.y - s.panic.y, s.x - s.panic.x)
    walk(s, s.facing, Soldiers.WALK * 2, dt)
    if s.panic.left <= 0 then
      s.panic = nil
    end
    return
  end

  -- Look, a few times a second: keep the one in his sights while he still
  -- can, otherwise whoever is nearest in sight.
  if (self.ticks + s.id) % Soldiers.LOOK_EVERY == 0 then
    local tx, ty = nil, nil
    if s.target then
      tx, ty = poseOf(server, s.target)
    end
    if not (tx and canSee(s, tx, ty)) then
      s.target = self:spot(server, s, teamOf)
      if s.target then
        s.fireIn = Soldiers.REACT
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
  s.alert = s.target ~= nil

  if tx then
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Soldiers.TURN, dt)
    s.fireIn = s.fireIn - dt
    if s.fireIn <= 0 then
      s.fireIn = Soldiers.FIRE_EVERY * (0.85 + random() * 0.3)
      fire(server, s, tx, ty)
    end
  elseif not s.arrived then
    local gx, gy = goal(s, map)
    if gx then
      local path = math.atan2(gy - s.y, gx - s.x)
      advance(s, path, Soldiers.WALK, dt)
      local look = path + Soldiers.SCAN * math.sin(self.time * 2.2 + s.phase)
      s.facing = turn(s.facing, look, Soldiers.TURN * 1.5, dt)
    end
  end
end

--- A car touching this soldier: flattened at speed, shoved aside below it.
--- Returns the kill ({ s, by, angle }) for the caller to announce.
function Soldiers:trampled(server, s, dt)
  for id, p in pairs(server.players) do
    local car = p.vehicle
    local near = car and Features.present(p) and dist2(car.x, car.y, s.x, s.y) < TOUCH2
    if near and Car.hitTest(car, s.x, s.y, Soldiers.RADIUS) then
      local speed = math.abs(car.speed)
      if speed >= Soldiers.SPLAT_SPEED then
        local travel = car.speed >= 0 and car.angle or car.angle + math.pi
        return { s = s, by = id, angle = travel }
      end
      local away = math.atan2(s.y - car.y, s.x - car.x)
      local push = (Soldiers.WALK + speed) * dt * 2
      s.x, s.y = s.x + math.cos(away) * push, s.y + math.sin(away) * push
    end
  end
  return nil
end

-- Being shot at -------------------------------------------------------------

--- The soldier standing within `radius` of (x, y), and his index. With
--- `team`, only one of the other side (a side's own rounds fly through).
function Soldiers:at(x, y, radius, team)
  local r2 = (radius + Soldiers.RADIUS) ^ 2
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
function Soldiers:hurt(s, i, amount, angle)
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
function Soldiers:remove(s)
  for i, o in ipairs(self.list) do
    if o == s then
      s.dead = true
      table.remove(self.list, i)
      return
    end
  end
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

function Soldiers:clear()
  for _, s in ipairs(self.list) do
    s.dead = true
  end
  self.list = {}
end

return Soldiers
