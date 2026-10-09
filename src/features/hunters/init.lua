-- Hunters: the Combine's tripod hunters, a ranged enemy. Quick on their
-- three legs, they keep their distance and shoot uzi rounds that carry
-- shock damage, throw themselves aside from incoming fire and players'
-- abilities, and when badly hurt go after medkits and energy drinks lying
-- nearby.
--
-- They think for themselves (brain.lua): patrol a beat, fight at range,
-- strafing and backing off, search where they lost somebody, dodge, and
-- break off to heal. They see as City 17's Combine soldiers do: the same
-- cone of sight, wider while they are on edge, and anyone close by
-- whichever way they face. Their rounds are shock (the damage feature)
-- and zap whoever they hit, the shock running on through them the way a
-- flame burns on, until it wears off or they dodge it off. Every so often
-- one charges its pods and fires a stun shot instead, which holds you
-- still. Rounds owned by nobody (the Combine's, the turrets', their own)
-- pass by them; anyone else's hurt them.
--
-- What they dodge, read each tick on the host: every round in flight that
-- a player or bot fired (weapons' `sv.projectiles`), a rocket with room to
-- spare for its blast; and every area a player's ability is about to hit
-- (abilities' serverIncoming): a freeze's warning ring, where a leaper is
-- coming down, a heat ray's burning spot or sweep. A teleport lands at
-- once: nothing to see coming.
--
-- They know when they are shot at, from any side: a round of a player's
-- that flies close or hits turns one on whoever fired it, and a shot within
-- earshot (`serverShotFired`) sends it to look. One that starts a fight or
-- is shot at calls the others in range to the spot (a blue pulse and a
-- whine on every screen).
--
-- What they heal with: a medkit (pickups' "health") puts back
-- `medkitHealth`; an energy drink ("stamina") `drinkHealth`, and makes it
-- quicker on its feet for `drinkHaste` seconds. They take it off the
-- ground as a player would (pickups' serverTake).
--
-- Another feature puts them on the map (City 17 has three round the
-- Citadel; the Winding Road and the Citadel walk their `hunterBeats`; the
-- Hunter-Chopper and A-Man's briefcase bring them in round a point):
-- `hunters:serverPatrol(server, route, count)` spreads `count` of them
-- round `route`, a loop of { x, y } corners they walk round and round.
-- `hunters:serverClear(server)` takes them all away again; a map change
-- does too.
--
-- The host owns them; clients hear where they are at 15 Hz.
--
-- Messages
--   server -> all  HTR_STATE <tick> (<id> <x> <y> <facing> <hp> <alert> <firing> <dodging>)...
--                  (firing 1 just fired, 2 charging its stun shot)
--                  (unreliable, 15 Hz; alert 1 has somebody, 2 searching, 0 neither)
--   server -> all  HTR_DOWN  <id> <x> <y> <angle>     one went down
--   server -> all  HTR_CALL  <id> <x> <y>             one called the others
--
-- Modules
--   brain.lua    what each one does, on the host
--   render.lua   one drawn from above, walking, firing, hit and dodging
--   sounds.lua   their noises: the call

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Nav = require("src.features.d-day.nav")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Brain = require("src.features.hunters.brain")
local Render = require("src.features.hunters.render")
local Sounds = require("src.features.hunters.sounds")

local Hunters = {
  name = "hunters",
}

-- Tuning ------------------------------------------------------------------
-- Their eyes: City 17's Combine soldiers' (a-man/city17.lua).
Hunters.fov = math.rad(90) -- how wide their cone of sight is
Hunters.alertFov = math.rad(130) -- and while one is on edge
Hunters.aware = 170 -- px all round them they notice somebody in, any way they face
Hunters.health = 180 -- three times a Combine soldier's: nine pistol rounds
Hunters.damage = 8 -- a round (an uzi's is 12)...
Hunters.zap = { seconds = 3, dps = 8 } -- ...and the shock runs on through you, as a flame burns on
Hunters.stunDamage = 10 -- its stun shot...
Hunters.stunTime = 1.2 -- ...holds you still this long
Hunters.burst = 5 -- rounds at the uzi's rate...
Hunters.pause = 1.4 -- ...then this many seconds
Hunters.drops = 8 -- koins one spills
Hunters.medkitHealth = 70 -- what a medkit puts back
Hunters.drinkHealth = 30 -- what an energy drink puts back...
Hunters.drinkHaste = 6 -- ...and seconds it is quicker on its feet after

local SYNC_EVERY = 2 -- server ticks between HTR_STATE
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 34 -- px walked in one full step cycle, for the legs
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local FLASH = 0.12 -- seconds a muzzle flash shows
local HURT = 0.18 -- seconds one flashes white after a hit
local DODGE_SHOWN = 0.3 -- seconds a dodge's smear shows
local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)
local HEALS = { health = true, stamina = true }

local function fmt(v)
  return ("%.1f"):format(v)
end

--- Their guns: the uzi, its rounds weaker but zapping whoever they hit,
--- and the stun shot, slower and brighter, that stuns them outright.
local function arms()
  local uzi = Tiers.apply(Guns.uzi, Tiers.DEFAULT)
  local gun = setmetatable({ damage = Hunters.damage, damageType = "shock", electrify = Hunters.zap },
    { __index = uzi })
  local stunGun = setmetatable({ damage = Hunters.stunDamage, damageType = "shock", stun = Hunters.stunTime,
    speed = 700, streak = 16 }, { __index = uzi })
  return {
    gun = gun,
    stunGun = stunGun,
    burst = Hunters.burst,
    pause = Hunters.pause,
    reach = uzi.speed * (uzi.ttl or ROUND_TTL) * 0.85,
  }
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

--- Healing, through the pickups feature.
local function findHeal(x, y, range)
  local pickups = Features.byName.pickups
  if not (pickups and pickups.serverNearest) then
    return nil
  end
  local id, it = pickups:serverNearest(x, y, range, HEALS)
  return id and { id = id, kind = it.kind, x = it.x, y = it.y } or nil
end

local function stillThere(p)
  local pickups = Features.byName.pickups
  return pickups ~= nil and pickups:serverHas(p.id)
end

local function takeHeal(srv, p)
  local pickups = Features.byName.pickups
  local it = pickups and pickups:serverTake(srv, p.id, 0)
  if not it then
    return 0, 0
  end
  if it.kind == "health" then
    return Hunters.medkitHealth, 0
  end
  return Hunters.drinkHealth, Hunters.drinkHaste
end

--- The host's set, with a walking grid over the map in play.
local function server()
  if sv then
    return sv
  end
  local city = Features.byName["city-map"]
  local map = city and city.map
  local nav = map and Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
  sv = {
    brain = Brain.new({
      fov = Hunters.fov, alertFov = Hunters.alertFov, aware = Hunters.aware, health = Hunters.health,
      radius = Render.RADIUS, nav = nav, find = findHeal, there = stillThere, take = takeHeal,
    }),
    syncIn = 0,
    emptySends = 0,
  }
  return sv
end

--- `route` with every corner moved to the nearest open spot.
local function settle(nav, route)
  if not nav then
    return route
  end
  local out = {}
  for _, p in ipairs(route) do
    local c, r = nav:nearestOpen(p.x, p.y)
    if c then
      local x, y = nav:centre(c, r)
      out[#out + 1] = { x = x, y = y }
    end
  end
  return out
end

--- `count` hunters spread evenly round `route` ({ x, y } corners, a loop),
--- walking it. Returns them.
function Hunters:serverPatrol(_server, route, count)
  local s = server()
  route = settle(s.brain.nav, route)
  local added = {}
  if #route < 2 then
    return added
  end
  for i = 1, count do
    added[#added + 1] = s.brain:add(route, math.floor((i - 1) * #route / count) + 1, arms())
  end
  return added
end

--- Take every hunter away.
function Hunters:serverClear()
  if sv then
    sv.brain.list = {}
  end
end

local shown = {} -- client: id -> { x, y, dx, dy, facing, hp, alert, wary, fov, cycle, stride, flash, hurt, dodge }

--- Another map: none left on either side, and the next ones get a walking
--- grid over their own map.
function Hunters:mapChanged()
  sv, shown = nil, {}
end

function Hunters:serverStart()
  sv = nil
end

--- Everything a hunter might need to get out of the way of, this tick.
local function threats(srv, brain)
  local weapons = Features.byName.weapons
  local rounds = weapons and weapons.sv and weapons.sv.projectiles
  for _, r in ipairs(rounds or {}) do
    if r.owner ~= 0 then -- a player's or a bot's
      local speed = math.sqrt(r.vx * r.vx + r.vy * r.vy)
      if speed > 0 then
        local width = r.blast and r.blast.radius * 0.6 or 0
        local fx, fy = r.x - r.vx * r.age, r.y - r.vy * r.age -- where it was fired from
        brain:threatLine(srv, r.owner, fx, fy, r.x, r.y, r.vx / speed, r.vy / speed, speed,
          speed * (r.ttl - r.age), width)
      end
    end
  end
  local abilities = Features.byName.abilities
  if abilities and abilities.serverIncoming then
    for _, a in ipairs(abilities:serverIncoming()) do
      brain:threatArea(a.x, a.y, a.radius)
    end
  end
  local grenades = Features.byName.grenades
  if grenades and grenades.serverIncoming then
    for _, a in ipairs(grenades:serverIncoming()) do
      brain:threatArea(a.x, a.y, a.radius)
    end
  end
end

local function sync(srv)
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
  local parts = { srv.tick }
  for _, h in ipairs(list) do
    parts[#parts + 1] = h.id
    parts[#parts + 1] = ("%.0f"):format(h.x)
    parts[#parts + 1] = ("%.0f"):format(h.y)
    parts[#parts + 1] = ("%.2f"):format(h.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, h.hp))
    parts[#parts + 1] = h.target and 1 or (Brain.wary(h) and 2 or 0)
    parts[#parts + 1] = h.charge and 2 or (h.shotSince and 1 or 0)
    parts[#parts + 1] = h.dodgedSince and 1 or 0
    h.shotSince, h.dodgedSince = false, false
  end
  local msg = Protocol.encode("HTR_STATE", unpack(parts))
  for _, player in pairs(srv.players) do
    if not player.bot then
      srv:send(player, msg, true)
    end
  end
end

function Hunters:serverStep(srv, dt)
  if not sv then
    return
  end
  local brain = sv.brain
  threats(srv, brain)
  brain:update(srv, dt)
  for _, h in ipairs(brain.calls) do
    srv:broadcast(Protocol.encode("HTR_CALL", h.id, fmt(h.x), fmt(h.y)))
  end
  brain.calls = {}
  for _, h in ipairs(brain.list) do -- what happened since the last sync, for the flash and the smear
    h.shotSince = h.shotSince or h.fired
    h.dodgedSince = h.dodgedSince or h.dodging ~= nil
  end
  sync(srv)
end

--- One down: pieces on every screen, a few koins, maybe a pickup.
local function down(srv, h, by, angle)
  srv:broadcast(Protocol.encode("HTR_DOWN", h.id, fmt(h.x), fmt(h.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(srv, h.x, h.y, Hunters.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(srv, h.x, h.y)
  end
  Features.call("serverKill", srv, { kind = "hunter", x = h.x, y = h.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the Combine's, the turrets', their own) pass by.
function Hunters:serverShotAt(srv, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  local h, i = sv.brain:at(x, y, radius)
  if not h then
    return false
  end
  if sv.brain:hurt(srv, h, i, damage or 20, angle, by) then
    down(srv, h, by, angle)
  end
  return true
end

--- A gun went off at (x, y) (weapons' `serverShotFired`): a player's or a
--- bot's is heard by any within earshot. Their own side's (owned by
--- nobody) is just noise.
function Hunters:serverShotFired(_server, player, x, y)
  if sv and player then
    sv.brain:heard(x, y)
  end
end

function Hunters:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Hunters:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius, 0.5)
  end
end

--- The host's hunters, for tests.
function Hunters.state()
  return sv
end

-- Client --------------------------------------------------------------------

local lastTick = 0
local clock = 0
local heardAt = 0 -- when the last HTR_STATE came
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer
local calls = {} -- { x, y, t }: the pulse of a call going out
local CALL_SHOWN = 0.9 -- seconds a call's pulse spreads

function Hunters:load()
  Sounds.load()
end

function Hunters:exitGame()
  shown, lastTick, calls = {}, 0, {}
end

function Hunters:update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, h in pairs(shown) do
    local ex, ey = h.x - h.dx, h.y - h.dy
    local moved = math.sqrt(ex * ex + ey * ey) * k
    if ex * ex + ey * ey > SNAP * SNAP then
      h.dx, h.dy = h.x, h.y
    else
      h.dx, h.dy = h.dx + ex * k, h.dy + ey * k
      h.cycle = h.cycle + moved / STEP -- the legs keep up with the ground
    end
    local speed = moved / math.max(dt, 1e-6)
    h.stride = h.stride + (math.min(1, speed / 40) - h.stride) * math.min(1, dt * 6)
    -- The cone opens out while it is on edge and closes again after.
    local fov = h.wary and Hunters.alertFov or Hunters.fov
    h.fov = h.fov + (fov - h.fov) * math.min(1, dt * 4)
    h.flash = math.max(0, h.flash - dt)
    h.hurt = math.max(0, h.hurt - dt)
    h.dodge = math.max(0, h.dodge - dt)
  end
  for i = #calls, 1, -1 do
    calls[i].t = calls[i].t + dt
    if calls[i].t > CALL_SHOWN then
      table.remove(calls, i)
    end
  end
end

--- Their cones of sight, on the ground under everything: a radar sweeping.
--- Always shown, sight-cones or
--- not: the one enemy whose eyes you get to see.
function Hunters:drawBelowCars()
  for id, h in pairs(shown) do
    Sight.draw(h.dx, h.dy, h.facing, Brain.RANGE, h.alert, clock, h.fov, { seed = id })
  end
end

function Hunters:drawAboveCars()
  -- A call going out: rings of blue spreading from the one that called.
  for _, c in ipairs(calls) do
    local k = c.t / CALL_SHOWN
    for ring = 0, 1 do
      local kr = math.max(0, k - ring * 0.2)
      love.graphics.setColor(Render.GLOW[1], Render.GLOW[2], Render.GLOW[3], 0.7 * (1 - kr))
      love.graphics.setLineWidth(3 - ring)
      love.graphics.circle("line", c.x, c.y, 20 + kr * 160, 40)
    end
  end
  love.graphics.setLineWidth(1)
  for _, h in pairs(shown) do
    Render.draw(h.dx, h.dy, h.facing, {
      cycle = h.cycle, stride = h.stride, firing = h.flash > 0, hurt = h.hurt / HURT * 0.7, charging = h.charging,
      dodge = h.dodge / DODGE_SHOWN, dodgeX = h.dodgeX, dodgeY = h.dodgeY,
    }, clock)
    if h.hp < Hunters.health then -- a bar under it once it is hurt
      local bw, f = 30, math.max(0, h.hp / Hunters.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", h.dx - bw / 2 - 1, h.dy + Render.RADIUS + 6, bw + 2, 5)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", h.dx - bw / 2, h.dy + Render.RADIUS + 7, bw * f, 3)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Hunters.clientMessages = {
  HTR_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local h = shown[id]
        if not h then
          h = { dx = x, dy = y, x = x, y = y, cycle = love.math.random(), stride = 0, fov = Hunters.fov, flash = 0,
            hurt = 0, dodge = 0, hp = Hunters.health }
          shown[id] = h
        end
        if args[i + 7] == "1" then -- dodging: its smear trails back the way it came
          local mx, my = x - h.x, y - h.y
          local len = math.sqrt(mx * mx + my * my)
          if len > 1 then
            h.dodgeX, h.dodgeY, h.dodge = mx / len, my / len, DODGE_SHOWN
          end
        end
        h.x, h.y = x, y
        h.facing = tonumber(args[i + 3]) or h.facing or 0
        local hp = tonumber(args[i + 4]) or h.hp
        if hp < h.hp then
          h.hurt = HURT
        end
        h.hp = hp
        h.alert = args[i + 5] == "1"
        h.wary = args[i + 5] ~= "0"
        if args[i + 6] == "1" then
          h.flash = FLASH
        end
        h.charging = args[i + 6] == "2"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  HTR_CALL = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y then
      local h = id and shown[id]
      calls[#calls + 1] = { x = h and h.dx or x, y = h and h.dy or y, t = 0 }
      Sounds.play("call", x, y)
    end
  end,
  HTR_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      shown[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.8)
    end
  end,
}

--- The footsteps feature's hook: who of mine is walking about, and where.
function Hunters:footstepWalkers()
  local list = {}
  for id, h in pairs(shown) do
    list[#list + 1] = { key = id, x = h.dx, y = h.dy, size = "claw" }
  end
  return list
end

return Hunters
