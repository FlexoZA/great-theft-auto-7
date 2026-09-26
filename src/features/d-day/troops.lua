-- The defenders, on the host. Two kinds:
--
--   guard     stands at a post off the beach (in a bunker's embrasure, a gap
--             in a trench's sandbags, by a hut, on the hilltop) and sweeps
--             a thirty-degree cone of sight slowly from side to side over
--             the ground below.
--   rifleman  comes out of a barracks door and walks down the map towards
--             the nearest player, looking where he is going.
--
-- Either one that gets someone in his cone turns to follow them and, after
-- a moment to take aim, opens fire, and keeps firing for as long as he can
-- see them. Duck behind a hedgehog or a sandbag wall, or get out of his
-- cone faster than he can turn, and he stops; a guard goes back to his
-- sweep, a rifleman carries on down the hill.
--
-- They shoot through weapons' ownerless entry point (the police officers on
-- foot do the same), so their rounds hurt any player and credit nobody.
-- This module only thinks; init.lua owns the wire.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")

local Troops = {}
Troops.__index = Troops

-- Tuning --------------------------------------------------------------------

Troops.RADIUS = 7 -- px; as fat as an officer on foot
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
Troops.MUZZLE = 12 -- px from the body a round leaves
Troops.LOOK_EVERY = 3 -- host ticks between sight checks (staggered by soldier)
Troops.WALK = 62 -- px/s a rifleman walks down the hill
Troops.SCAN = math.rad(20) -- a walking rifleman looks this far either side of his path

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

function Troops.new()
  return setmetatable({ list = {}, nextId = 1, time = 0, ticks = 0 }, Troops)
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
    hp = Troops.HEALTH,
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
local function spot(server, s)
  local best, bestD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Sight.canSee(s.x, s.y, s.facing, x, y, Troops.RANGE)
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

--- One round at (tx, ty), from the muzzle, a little off.
local function fire(server, s, tx, ty)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local aim = math.atan2(ty - s.y, tx - s.x) + (random() * 2 - 1) * Troops.SPREAD
  local mx, my = s.x + math.cos(aim) * Troops.MUZZLE, s.y + math.sin(aim) * Troops.MUZZLE
  weapons:serverFireFrom(server, 0, mx, my, aim, require("src.features.weapons.guns").ak47)
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
    if not (tx and Sight.canSee(s.x, s.y, s.facing, tx, ty, Troops.RANGE, Troops.TRACK_FOV)) then
      s.target = spot(server, s)
      if s.target then
        s.fireIn = Troops.REACT
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
    s.facing = turn(s.facing, math.atan2(ty - s.y, tx - s.x), Troops.TURN, dt)
    s.fireIn = s.fireIn - dt
    if s.fireIn <= 0 then
      s.fireIn = Troops.FIRE_EVERY * (0.85 + random() * 0.3)
      fire(server, s, tx, ty)
    end
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
    return true
  end
  if angle and not s.target then
    s.facing = angle + math.pi -- back the way the round came
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
