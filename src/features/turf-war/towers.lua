-- The towers on the host: the eighteen stone towers on the lanes of The
-- Lanes (city-map's `map.towers`), each with a machine gun on top. A
-- tower watches a circle round itself, its detection zone, in every
-- direction; the first enemy who steps into it with nothing solid in the
-- way is its target, and after a moment to swing the gun round it fires at
-- them at the pistol's rate with the pistol's rounds, for as long as it
-- can see them. Its rounds belong to nobody (weapons' ownerless entry
-- point) but carry the tower's team, so they fly through its own side.
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
Towers.HEALTH = 400 -- twenty pistol rounds
Towers.RANGE = 400 -- px, the detection zone's radius
Towers.REACT = 0.5 -- seconds from spotting someone to the first shot
Towers.TURN = 5 -- rad/s the gun swings
Towers.AIMED = 0.2 -- radians off the target the gun still fires at
Towers.SPREAD = 0.03 -- radians of aim error either side
Towers.LOOK_EVERY = 3 -- host ticks between looks round (staggered by tower)
Towers.STEP = 12 -- px between line-of-sight samples
Towers.DROP = 10 -- koins a tower spills when it comes down
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
      target = nil, -- player id in its sights
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

--- The nearest player inside the zone that `enemy(player)` says is fair
--- game and that the tower can see from its edge.
local function look(t, server, enemy)
  local best, bestD2
  local R2 = Towers.RANGE * Towers.RANGE
  local edge = Towers.SIZE / 2 + 6
  for _, player in pairs(server.players) do
    if Features.present(player) and enemy(player) then
      local px, py = Features.bodyPose(server, player)
      local d2 = (px - t.x) ^ 2 + (py - t.y) ^ 2
      if d2 <= R2 and (not bestD2 or d2 < bestD2) then
        local d = math.sqrt(d2)
        if d > edge and clear(t.x + (px - t.x) / d * edge, t.y + (py - t.y) / d * edge, px, py) then
          best, bestD2 = player, d2
        end
      end
    end
  end
  return best
end

--- One host tick for every standing tower. `teamOf(player)` is the side a
--- player is on (nil for nobody's: fair game to every tower).
function Towers:update(server, dt, teamOf)
  self.ticks = self.ticks + 1
  local weapons = Features.byName.weapons
  for _, t in ipairs(self.list) do
    if not t.down then
      local target = t.target and server.players[t.target]
      if (self.ticks + t.id) % Towers.LOOK_EVERY == 0 or not target then
        local seen = look(t, server, function(p)
          return teamOf(p) ~= t.team
        end)
        if seen and seen.id ~= t.target then
          t.fireIn = math.max(t.fireIn, Towers.REACT) -- somebody new: a moment to swing round
        end
        t.target = seen and seen.id or nil
        target = seen
      end
      if target and Features.present(target) then
        t.alert = true
        local px, py = Features.bodyPose(server, target)
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
