-- A-Man's turrets: Aperture Science sentry turrets, a horde of them, out of
-- his briefcase (event.lua decides when). White pods on three thin legs
-- with one red eye and a laser sight. They are not clever: each scuttles
-- about at random, changing its mind every second or so and turning off
-- any wall it walks into, and every so often stops to spray a short burst
-- in whatever direction it happens to pick. The rounds are real (weapons'
-- serverFireFrom, owned by nobody), so they hurt whoever they meet, but
-- nobody is aimed at. One round of anything knocks one over, and one
-- that lasts `life` falls over by itself.
--
-- The host keeps a set (`Turrets.new()`) and steps it; clients keep their
-- own (`Turrets.clientNew()`) fed by the boss's messages and draw it.

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Guns = require("src.features.weapons.guns")

local Turrets = {}

-- Tuning ------------------------------------------------------------------
Turrets.count = 8 -- in a horde, for one player (more humans, more: bosses/init.lua)
Turrets.health = 1 -- anything knocks one over
Turrets.radius = 7 -- px
Turrets.speed = 110 -- px/s, scuttling
Turrets.turnEvery = { 0.4, 1.4 } -- seconds before one changes its mind about where it is going
Turrets.wait = { 0.3, 0.9 } -- seconds a new one sits before it goes
Turrets.spillRange = { 18, 70 } -- px from him that they land when the case opens
Turrets.burst = 4 -- rounds in a burst
Turrets.burstGap = 0.08 -- seconds between them
Turrets.pause = { 0.6, 1.6 } -- seconds between bursts
Turrets.damage = 6 -- a round
Turrets.life = 20 -- seconds before one falls over by itself

-- Their gun: the uzi's rounds (and its sound on every client), weaker.
local GUN = {}
for k, v in pairs(Guns.uzi) do
  GUN[k] = v
end
GUN.damage = Turrets.damage
GUN.spread = 0.04

local random = love.math.random

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

--- A set on the host. `popKind` is the message that tells everyone one fell
--- over (EAM_POP, the event's, when nil).
function Turrets.new(popKind)
  return { list = {}, nextId = 1, n = 0, popKind = popKind or "EAM_POP" }
end

--- How many are standing.
function Turrets.standing(set)
  return set.n
end

--- `n` of them out of a case at (x, y).
function Turrets.spill(set, x, y, n)
  for _ = 1, n do
    local a = random() * 2 * math.pi
    local d = between(Turrets.spillRange)
    local tx, ty = x + math.cos(a) * d, y + math.sin(a) * d
    if Features.any("blocksPoint", tx, ty) then
      tx, ty = x, y
    end
    local id = set.nextId
    set.nextId = id + 1
    set.list[id] = {
      id = id, x = tx, y = ty, heading = a, facing = a, hp = Turrets.health,
      wait = between(Turrets.wait), turnIn = between(Turrets.turnEvery),
      fireIn = between(Turrets.pause), shots = 0, aim = 0, life = Turrets.life, frozen = 0,
    }
    set.n = set.n + 1
  end
end

--- Turret `t` falls over, and everyone hears.
local function topple(set, server, t)
  if set.list[t.id] then
    set.list[t.id] = nil
    set.n = set.n - 1
    server:broadcast(Protocol.encode(set.popKind, t.id, fmt(t.x), fmt(t.y), ("%.2f"):format(t.facing)))
  end
end

--- Every one falls over (he went down).
function Turrets.clear(set, server)
  for _, t in pairs(set.list) do
    topple(set, server, t)
  end
end

local function fire(server, t)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    local r = Turrets.radius + 4
    weapons:serverFireFrom(server, 0, t.x + math.cos(t.aim) * r, t.y + math.sin(t.aim) * r, t.aim, GUN)
  end
end

function Turrets.step(set, server, dt)
  for _, t in pairs(set.list) do
    t.life = t.life - dt
    if t.life <= 0 then
      topple(set, server, t)
    elseif t.frozen > 0 then
      t.frozen = t.frozen - dt
    elseif t.wait > 0 then
      t.wait = t.wait - dt
    else
      -- Wander: a new way every so often, and a new one off any wall.
      t.turnIn = t.turnIn - dt
      if t.turnIn <= 0 then
        t.heading = random() * 2 * math.pi
        t.turnIn = between(Turrets.turnEvery)
      end
      if t.shots == 0 then
        local nx = t.x + math.cos(t.heading) * Turrets.speed * dt
        local ny = t.y + math.sin(t.heading) * Turrets.speed * dt
        if Features.any("blocksPoint", nx, ny) then
          t.heading = random() * 2 * math.pi
        else
          t.x, t.y = nx, ny
        end
        t.facing = t.heading
      end
      -- Shoot: pick any direction at all and spray a burst along it.
      t.fireIn = t.fireIn - dt
      if t.fireIn <= 0 then
        if t.shots == 0 then
          t.aim = random() * 2 * math.pi
          t.facing = t.aim
          t.shots = Turrets.burst
        end
        fire(server, t)
        t.shots = t.shots - 1
        t.fireIn = t.shots > 0 and Turrets.burstGap or between(Turrets.pause)
      end
    end
  end
end

--- A round through (x, y): knocks over the first turret there. True if it did.
function Turrets.hit(set, server, x, y, radius)
  for _, t in pairs(set.list) do
    if (t.x - x) ^ 2 + (t.y - y) ^ 2 < (radius + Turrets.radius) ^ 2 then
      t.hp = t.hp - 1
      if t.hp <= 0 then
        topple(set, server, t)
      end
      return true
    end
  end
  return false
end

--- A freeze at (x, y): the ones inside stand still, guns and all.
function Turrets.freeze(set, x, y, radius, seconds)
  for _, t in pairs(set.list) do
    if (t.x - x) ^ 2 + (t.y - y) ^ 2 <= (radius + Turrets.radius) ^ 2 then
      t.frozen = math.max(t.frozen, seconds)
    end
  end
end

--- EAM_TURRETS' fields after the tick: <id> <x> <y> <facing> <firing> for each.
function Turrets.wire(set)
  local parts = {}
  for id, t in pairs(set.list) do
    parts[#parts + 1] = id
    parts[#parts + 1] = fmt(t.x)
    parts[#parts + 1] = fmt(t.y)
    parts[#parts + 1] = ("%.2f"):format(t.facing)
    parts[#parts + 1] = (t.shots > 0 and t.frozen <= 0) and 1 or 0
  end
  return parts
end

-- Client --------------------------------------------------------------------

local SMOOTHING = 14 -- per second, the easing of what is drawn
local DOWN_TIME = 2 -- seconds a toppled one lies there

function Turrets.clientNew()
  return { list = {}, down = {} }
end

--- EAM_TURRETS from `args[i]` on: the ones standing now. Any not named
--- has gone (its EAM_POP says how).
function Turrets.read(cset, args, i)
  local seen = {}
  while args[i + 4] do
    local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
    if id and x and y then
      local t = cset.list[id] or { dx = x, dy = y, legs = random() * 6 }
      t.x, t.y = x, y
      t.facing = tonumber(args[i + 3]) or 0
      t.firing = args[i + 4] == "1"
      cset.list[id] = t
      seen[id] = true
    end
    i = i + 5
  end
  for id in pairs(cset.list) do
    if not seen[id] then
      cset.list[id] = nil
    end
  end
end

--- One fell over at (x, y).
function Turrets.pop(cset, id, x, y, facing)
  cset.list[id] = nil
  cset.down[#cset.down + 1] = { x = x, y = y, facing = facing, t = 0 }
end

function Turrets.update(cset, dt)
  local k = math.min(1, dt * SMOOTHING)
  for _, t in pairs(cset.list) do
    local ex, ey = t.x - t.dx, t.y - t.dy
    t.dx, t.dy = t.dx + ex * k, t.dy + ey * k
    if ex * ex + ey * ey > 0.5 then
      t.legs = t.legs + dt * 22
    end
  end
  for i = #cset.down, 1, -1 do
    local d = cset.down[i]
    d.t = d.t + dt
    if d.t > DOWN_TIME then
      table.remove(cset.down, i)
    end
  end
end

--- One turret from above, facing `facing`: three thin legs, a white pod
--- split down the middle, and the red eye in front.
local function pod(x, y, facing, legs, alpha)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(facing)
  love.graphics.setColor(0.15, 0.15, 0.17, alpha)
  love.graphics.setLineWidth(1)
  for i = 0, 2 do
    local a = math.pi + (i - 1) * 1.1 + math.sin(legs + i * 2) * 0.25
    love.graphics.line(0, 0, math.cos(a) * 9, math.sin(a) * 9)
  end
  love.graphics.setColor(0.08, 0.08, 0.1, alpha)
  love.graphics.ellipse("fill", 0, 0, 5.6, 4.4, 14)
  love.graphics.setColor(0.94, 0.95, 0.96, alpha)
  love.graphics.ellipse("fill", 0, 0, 5, 3.8, 14)
  love.graphics.setColor(0.7, 0.72, 0.76, alpha)
  love.graphics.line(-4.5, 0, 3, 0) -- the seam the guns come out of
  love.graphics.setColor(0.95, 0.1, 0.08, alpha)
  love.graphics.circle("fill", 3.6, 0, 1.3, 8)
  love.graphics.pop()
end

function Turrets.draw(cset, time)
  for _, d in ipairs(cset.down) do
    local fade = 1 - d.t / DOWN_TIME
    pod(d.x, d.y, d.facing + math.pi / 2, 0, 0.7 * fade) -- on its side
    love.graphics.setColor(1, 0.8, 0.3, fade * (0.5 + 0.5 * math.sin(time * 40)))
    love.graphics.circle("fill", d.x + 2, d.y - 1, 1.2 + fade * 1.5, 6) -- sparks
  end
  for _, t in pairs(cset.list) do
    -- The laser sight, out along wherever it is looking.
    local len = t.firing and 90 or 40
    love.graphics.setColor(1, 0.1, 0.05, t.firing and 0.6 or 0.3)
    love.graphics.setLineWidth(1)
    love.graphics.line(t.dx + math.cos(t.facing) * 5, t.dy + math.sin(t.facing) * 5,
      t.dx + math.cos(t.facing) * len, t.dy + math.sin(t.facing) * len)
    if t.firing then
      -- The guns out of the sides.
      local sx, sy = -math.sin(t.facing), math.cos(t.facing)
      love.graphics.setColor(1, 0.85, 0.4, 0.5 + 0.5 * math.sin(time * 60))
      love.graphics.circle("fill", t.dx + sx * 5 + math.cos(t.facing) * 4, t.dy + sy * 5 + math.sin(t.facing) * 4, 1.4)
      love.graphics.circle("fill", t.dx - sx * 5 + math.cos(t.facing) * 4, t.dy - sy * 5 + math.sin(t.facing) * 4, 1.4)
    end
    pod(t.dx, t.dy, t.facing, t.legs, 1)
  end
  love.graphics.setColor(1, 1, 1)
end

return Turrets
