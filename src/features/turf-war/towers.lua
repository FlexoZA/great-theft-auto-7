-- The towers on the host: the eighteen stone towers on the lanes of The
-- Lanes (city-map's `map.towers`), each with a machine gun on top. A
-- tower watches a circle round itself, its detection zone, in every
-- direction, and picks its target Dota's way: a player who hit it in the
-- last few seconds and is still in sight, else the nearest of the other
-- side's creeps (creeps.lua) it can see, else the nearest enemy player.
-- After a moment to swing the gun round it fires at them at the pistol's
-- rate with the pistol's rounds, for as long as it can see them. Its
-- rounds belong to nobody (weapons' ownerless entry point) but carry the
-- tower's team, so they fly through its own side.
--
-- A tower has hit points and takes them off from every player's round that
-- stops at it (`serverWallHit`) and every blast that reaches it. It is
-- covered while a tower of its side further out on the same lane stands:
-- hits do nothing then. At zero it is down for good: rubble, and a pile of
-- koins. This module only thinks; init.lua owns the wire.

local Features = require("src.features")
local Guns = require("src.features.weapons.guns")

local Towers = {}
Towers.__index = Towers

-- Tuning --------------------------------------------------------------------

Towers.SIZE = 56 -- px, the square the map built (layout's ARENA.tower)
Towers.HEALTH = 800 -- forty pistol rounds
Towers.RANGE = 400 -- px, the detection zone's radius
Towers.REACT = 0.5 -- seconds from spotting someone to the first shot
Towers.TURN = 5 -- rad/s the gun swings
Towers.AIMED = 0.2 -- radians off the target the gun still fires at
Towers.SPREAD = 0.03 -- radians of aim error either side
Towers.LOOK_EVERY = 3 -- host ticks between looks round (staggered by tower)
Towers.STEP = 12 -- px between line-of-sight samples
Towers.DROP = 10 -- koins a tower spills when it comes down
Towers.AGGRO = 4 -- seconds a tower keeps after a player who hit it
Towers.gun = Guns.at(Guns.DEFAULT) -- the pistol: its damage, speed and rate
Towers.FIRE_EVERY = Towers.gun.cooldown

local random = love.math.random
local TWO_PI = 2 * math.pi

--- Shortest signed turn from heading b to heading a.
function Towers.angleDiff(a, b)
  return (a - b + math.pi) % TWO_PI - math.pi
end

--- The towers of `map`, in the map's order, all standing and full.
function Towers.new(map)
  local self = setmetatable({ list = {}, byId = {}, ticks = 0 }, Towers)
  for i, t in ipairs(map.towers) do
    local tower = {
      id = i,
      x = t.x,
      y = t.y,
      team = t.team,
      lane = t.lane,
      tier = t.tier,
      hp = Towers.HEALTH,
      max = Towers.HEALTH,
      aim = math.atan2(-t.y, -t.x), -- watching the middle of the map to start with
      target = nil, -- { kind = "player", id } or { kind = "creep", s } in its sights
      hitBy = nil, -- id of the last player to hit it, and when: { id, at }
      fireIn = Towers.REACT,
      alert = false,
      down = false,
      noticeTick = -1000, -- the last tick a shooter was told it is covered
    }
    self.list[i] = tower
    self.byId[i] = tower
  end
  return self
end

--- The tower whose square holds (x, y), give or take `pad` px.
function Towers:at(x, y, pad)
  local h = Towers.SIZE / 2 + (pad or 0)
  for _, t in ipairs(self.list) do
    if math.abs(x - t.x) <= h and math.abs(y - t.y) <= h then
      return t
    end
  end
  return nil
end

--- The standing tower of the same side further out on the same lane that
--- covers `t`, or nil. Works on a client's list too (same fields).
function Towers.coveredIn(list, t)
  for _, u in ipairs(list) do
    if u ~= t and u.team == t.team and u.lane == t.lane and u.tier < t.tier and not u.down then
      return u
    end
  end
  return nil
end

--- Take `amount` off tower `t`. Returns "covered" (nothing happened),
--- "hit" or "down".
function Towers:hurt(t, amount)
  if t.down then
    return nil
  end
  if Towers.coveredIn(self.list, t) then
    return "covered"
  end
  t.hp = t.hp - amount
  if t.hp > 0 then
    return "hit"
  end
  t.hp, t.down, t.target, t.alert = 0, true, nil, false
  return "down"
end

--- Standing towers of `team`.
function Towers:standing(team)
  local n = 0
  for _, t in ipairs(self.list) do
    if t.team == team and not t.down then
      n = n + 1
    end
  end
  return n
end

-- Looking ---------------------------------------------------------------------

--- Is the straight line from (x0, y0) to (x1, y1) free of walls? Walls are
--- every feature's `blocksPoint`, the rule bullets follow.
local function clear(x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / Towers.STEP)
  for i = 1, n do
    local k = i / (n + 1)
    if Features.any("blocksPoint", x0 + dx * k, y0 + dy * k) then
      return false
    end
  end
  return true
end

--- Can the tower see (x, y) from its edge, and how far is it? Nil when it
--- can't.
local function sees(t, x, y)
  local d2 = (x - t.x) ^ 2 + (y - t.y) ^ 2
  if d2 > Towers.RANGE * Towers.RANGE then
    return nil
  end
  local edge = Towers.SIZE / 2 + 6
  local d = math.sqrt(d2)
  if d <= edge then
    return d2
  end
  return clear(t.x + (x - t.x) / d * edge, t.y + (y - t.y) / d * edge, x, y) and d2 or nil
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
  if not target.s.dead then
    return target.s.x, target.s.y
  end
  return nil
end

--- Are two targets the same one?
local function same(a, b)
  return a and b and a.kind == b.kind and (a.kind == "player" and a.id == b.id or a.kind == "creep" and a.s == b.s)
end

--- A player hit the tower: it holds that against them for a while.
function Towers:hitBy(t, id, now)
  t.hitBy = { id = id, at = now }
end

--- What the tower goes for, Dota's way: the player who hit it lately if
--- they are in sight, else the nearest of the other side's creeps it can
--- see (`creeps` may be nil), else the nearest player `enemy(player)` says
--- is fair game.
local function look(t, server, enemy, creeps, now)
  local hit = t.hitBy
  if hit and now - hit.at <= Towers.AGGRO then
    local p = server.players[hit.id]
    if p and Features.present(p) and enemy(p) then
      local px, py = Features.bodyPose(server, p)
      if sees(t, px, py) then
        return { kind = "player", id = hit.id }
      end
    end
  end
  local best, bestD2
  for _, s in ipairs(creeps and creeps.list or {}) do
    if s.team ~= t.team then
      local d2 = (s.x - t.x) ^ 2 + (s.y - t.y) ^ 2
      if (not bestD2 or d2 < bestD2) and sees(t, s.x, s.y) then
        best, bestD2 = { kind = "creep", s = s }, d2
      end
    end
  end
  if best then
    return best
  end
  for id, player in pairs(server.players) do
    if Features.present(player) and enemy(player) then
      local px, py = Features.bodyPose(server, player)
      local d2 = (px - t.x) ^ 2 + (py - t.y) ^ 2
      if (not bestD2 or d2 < bestD2) and sees(t, px, py) then
        best, bestD2 = { kind = "player", id = id }, d2
      end
    end
  end
  return best
end

--- One host tick for every standing tower. `teamOf(player)` is the side a
--- player is on (nil for nobody's: fair game to every tower); `creeps` is
--- the other side's creeps to shoot at too; `now` is the host's clock,
--- the one `hitBy` is stamped with.
function Towers:update(server, dt, teamOf, creeps, now)
  self.ticks = self.ticks + 1
  local weapons = Features.byName.weapons
  for _, t in ipairs(self.list) do
    if not t.down then
      local px, py = nil, nil
      if t.target then
        px, py = poseOf(server, t.target)
      end
      if (self.ticks + t.id) % Towers.LOOK_EVERY == 0 or not px then
        local seen = look(t, server, function(p)
          return teamOf(p) ~= t.team
        end, creeps, now or 0)
        if seen and not same(seen, t.target) then
          t.fireIn = math.max(t.fireIn, Towers.REACT) -- somebody new: a moment to swing round
        end
        t.target = seen
        px, py = nil, nil
        if seen then
          px, py = poseOf(server, seen)
        end
      end
      if px then
        t.alert = true
        local diff = Towers.angleDiff(math.atan2(py - t.y, px - t.x), t.aim)
        local step = Towers.TURN * dt
        t.aim = t.aim + math.max(-step, math.min(step, diff))
        t.fireIn = t.fireIn - dt
        if t.fireIn <= 0 and math.abs(diff) <= Towers.AIMED and weapons and weapons.serverFireFrom then
          t.fireIn = Towers.FIRE_EVERY
          local m = Towers.SIZE / 2 + 16 -- the muzzle, clear of the tower's own square on a diagonal too
          local aim = t.aim + (random() * 2 - 1) * Towers.SPREAD
          weapons:serverFireFrom(server, 0, t.x + math.cos(t.aim) * m, t.y + math.sin(t.aim) * m, aim, Towers.gun,
            t.team)
        end
      else
        t.target, t.alert = nil, false
        t.fireIn = Towers.REACT
      end
    end
  end
end

return Towers
