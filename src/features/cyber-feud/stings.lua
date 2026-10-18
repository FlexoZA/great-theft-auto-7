-- Halcyon's sting drones (docs/cyber-feud.md, "Halcyon"): small, fast and
-- armed, in swarms over the Overpass's gantries and in Halcyon Tower's
-- server room, where they keep to the floor's aisles (the brain's
-- `indoors`) (the map's `stings`).
-- troops.lua starts, steps and stops them with the rest of Halcyon; their
-- heads are sting_brain.lua.
--
-- A swarm hangs over its gantry until a player comes near, then strafes
-- them: run after run straight through where they are going, a light gun
-- firing as each comes in (Halcyon's rounds), looping round to come again,
-- faster than a car. `count` swarms of `size` for one human, one
-- more swarm for each human past the first. 20 health each: one or two
-- rounds. Only players' rounds reach them (the factions' pass under), and
-- an EMP knocks them out (`serverEmp`, the sparkers' bursts).
--
-- Messages
--   server -> all  STG_STATE <tick> (<id> <x> <y> <heading> <hp> <state> <fired>)...
--                  (unreliable, 15 Hz; state 0 home, 1 on a run, 2 knocked out)
--   server -> all  STG_DOWN  <id> <x> <y>    one was shot down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Brain = require("src.features.cyber-feud.sting_brain")
local Rooms = require("src.features.cyber-feud.rooms")

local UZI_TTL = 1.2 -- its uzi's rounds fly the full way (weapons' default): the player's uzi is close-range only

local Stings = {}

-- Tuning ------------------------------------------------------------------
Stings.count = 2 -- swarms for one human, one more for each human past the first (Bosses.plus), and more on a
-- job finished before
Stings.size = 3 -- drones to a swarm
Stings.health = 20
Stings.damage = 6 -- a round
Stings.empTime = 5 -- seconds an EMP knocks one out
Stings.drops = 3 -- koins one spills
Stings.firstId = 15001

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 16
local SNAP = 260
local STALE = 1
local FLASH = 0.1
local HURT = 0.18
local LIFT = 18 -- px the drone is drawn above its shadow
local TRAIL = 0.18 -- seconds its trail shows

local MAGENTA = { 1.00, 0.24, 0.78 }
local CASING = { 0.30, 0.31, 0.35 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }
local gun = nil

--- One round from drone `s` along `aim`: a light gun, Halcyon's.
local function fire(server, s, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  if not gun then
    local base = Tiers.apply(Guns.uzi, Tiers.DEFAULT)
    gun = setmetatable({ damage = Stings.damage, tint = "ff3ec8", spread = 0.05, ttl = UZI_TTL }, { __index = base })
  end
  local x, y = s.x + math.cos(aim) * 12, s.y + math.sin(aim) * 12
  weapons:serverFireFrom(server, 0, x, y, aim, gun, "halcyon")
end

--- Swarms over `map`'s `stings` homes. Nothing on a map without them.
function Stings.serverStart(server, map)
  Stings.serverStop(server)
  if not map.stings then
    return
  end
  local brain = Brain.new({ health = Bosses.enemyHealth(Stings.health), fire = fire, firstId = Stings.firstId,
    indoors = map.kind == "tower", sameRoom = Rooms.of(map) })
  local n = math.min(#map.stings, Bosses.plus(Stings.count, server))
  for i = 1, n do
    brain:addSwarm(map.stings[i].x, map.stings[i].y, Stings.size)
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0 }
end

function Stings.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("STG_STATE", server.tick))
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.brain.list
  if #list == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { server.tick }
  for _, s in ipairs(list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.heading)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.stunned > 0 and 2 or (s.swarm.target and 1 or 0)
    parts[#parts + 1] = s.firedSince and 1 or 0
    s.firedSince = false
  end
  local msg = Protocol.encode("STG_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Stings.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for _, s in ipairs(sv.brain.list) do
    s.firedSince = s.firedSince or s.fired
  end
  sync(server)
end

function Stings.serverEmp(x, y, radius)
  if sv then
    sv.brain:stun(x, y, radius, Stings.empTime)
  end
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- hits; the factions' pass under. Returns true when it hit one.
function Stings.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.brain:at(x, y, radius)
  if not s then
    return false
  end
  if sv.brain:hurt(s, i, damage or 20) then
    server:broadcast(Protocol.encode("STG_DOWN", s.id, fmt(s.x), fmt(s.y)))
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, s.x, s.y, Stings.drops)
    end
    Features.call("serverKill", server, { kind = "drone", x = s.x, y = s.y, by = by, angle = angle, cause = dtype })
  end
  return true
end

--- Every sting in the air, for the audit (tools/audit). Outdoors it flies
--- over everything; indoors (the tower) it goes round what stands there.
function Stings.serverEnemies(_server, add)
  for _, s in ipairs(sv and sv.brain.list or {}) do
    add({ id = s, kind = "cyber-feud/sting", x = s.x, y = s.y, hp = s.hp, radius = Brain.RADIUS,
      flying = not sv.brain.indoors })
  end
end

function Stings.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Stings.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, heading, hp, state, flash, hurt, trail, sink }
local lastTick, heardAt, clock = 0, 0, 0

function Stings.clear()
  shown, lastTick = {}, 0
end

function Stings.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
    end
    s.flash = math.max(0, s.flash - dt)
    s.hurt = math.max(0, s.hurt - dt)
    s.sink = s.sink + ((s.state == 2 and 1 or 0) - s.sink) * math.min(1, dt * 3)
    for i = #s.trail, 1, -1 do
      s.trail[i].t = s.trail[i].t + dt
      if s.trail[i].t > TRAIL then
        table.remove(s.trail, i)
      end
    end
    if s.state == 1 then
      s.trail[#s.trail + 1] = { x = s.dx, y = s.dy - LIFT, t = 0 }
    end
  end
end

function Stings.drawBelowCars()
  for _, s in pairs(shown) do -- their shadows on the road
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", s.dx + 4, s.dy + 4, 7, 4, 12)
  end
end

--- One drone: a dart of a body, two rotors either side, a magenta eye on
--- the nose and the gun under it; a streak behind it on a run.
local function drawDrone(s)
  for _, p in ipairs(s.trail) do
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.25 * (1 - p.t / TRAIL))
    love.graphics.circle("fill", p.x, p.y, 3, 8)
  end
  local out = s.state == 2
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy - LIFT * (1 - 0.7 * s.sink))
  love.graphics.rotate(s.heading + (out and math.sin(clock * 9 + s.dx) * 0.3 or 0))
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.setColor(0.8, 0.82, 0.86, out and 0.15 or 0.35)
    love.graphics.circle("fill", -2, side * 7, 3.6, 10)
  end
  love.graphics.setColor(s.hurt > 0 and { 1, 1, 1 } or CASING)
  love.graphics.polygon("fill", 8, 0, -5, -4, -3, 0, -5, 4)
  love.graphics.setColor(0.12, 0.12, 0.14)
  love.graphics.rectangle("fill", 1, 2, 7, 1.6) -- the gun
  love.graphics.setColor(out and { 0.15, 0.05, 0.12 } or MAGENTA)
  love.graphics.circle("fill", 4, 0, 1.6, 8)
  if s.flash > 0 then
    love.graphics.setColor(1, 0.85, 0.6, s.flash / FLASH)
    love.graphics.circle("fill", 10, 3, 3, 8)
  end
  love.graphics.pop()
end

function Stings.drawAboveCars()
  for _, s in pairs(shown) do
    drawDrone(s)
  end
  love.graphics.setColor(1, 1, 1)
end

function Stings.drawNightLights(glow)
  for _, s in pairs(shown) do
    if s.state ~= 2 then
      glow(s.dx, s.dy - LIFT, s.state == 1 and 50 or 30, MAGENTA, 0.6)
      if s.flash > 0 then
        glow(s.dx, s.dy - LIFT, 50, { 1, 0.85, 0.6 }, 0.9)
      end
    end
  end
end

Stings.clientMessages = {
  STG_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        if not s then
          s = { dx = x, dy = y, flash = 0, hurt = 0, sink = 0, trail = {}, hp = Stings.health }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.heading = tonumber(args[i + 3]) or s.heading or 0
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.state = tonumber(args[i + 5]) or 0
        if args[i + 6] == "1" then
          s.flash = FLASH
        end
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  STG_DOWN = function(client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    local weapons = Features.byName.weapons
    if x and y and weapons and weapons.explosionAt then
      weapons:explosionAt(client, s and s.dx or x, s and s.dy or y, MAGENTA)
    end
  end,
}

return Stings
