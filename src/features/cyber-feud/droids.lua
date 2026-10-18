-- Halcyon's assassin droids (docs/cyber-feud.md), a stronger enemy than the
-- officers: the last thing between you and the tunnel on the Drop, and up
-- Halcyon Tower in its server room, its labs and on the executive floor
-- (the map's `droids`: a beat each, with how many walk it). init.lua passes its hooks on to this module; troops.lua
-- starts and stops them with the rest of the street.
--
-- They think as A-Man's Hunters do (hunters/brain.lua), only quicker: a
-- beat they walk, a fight kept at range, strafing and backing off, a search
-- where they lost you, calling each other in, and above all dodging: every
-- round a player fires that would hit one, and every ability or grenade
-- about to land on one, it throws itself out of the way of, and it is ready
-- to again in `dodgeCool` (3 s). They fire rail pistol bursts and, every so often,
-- stop and charge a rail shot: a magenta sightline shows where it will go
-- for STUN_CHARGE, and the shot goes down that line, so stepping off it
-- dodges it. They don't heal.
--
-- Like the troops, they stand still and see nobody while the street is
-- calm (until the Shard is taken, or a player hurts one of them).
--
-- They walk cloaked (droid_render.lua) until they have somebody. On each
-- beat, its `count` (two when it doesn't say) for one human player and
-- `perHuman` more (one) for each human past the first, and a fifth more
-- for each time the job has been finished before. Down, one blows its
-- core and comes apart in scrap. Rounds owned by nobody (the factions',
-- their own) pass by them; a player's hurt them.
--
-- Messages
--   server -> all  DRD_STATE <tick> (<id> <x> <y> <facing> <hp> <alert> <firing> <dodging>)...
--                  (unreliable, 15 Hz; alert 1 has somebody, 2 searching, 0 neither;
--                  firing 1 just fired, 2 charging its rail shot)
--   server -> all  DRD_DOWN  <id> <x> <y> <angle>    one went down
--   server -> all  DRD_CALL  <id> <x> <y>            one called the others

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Brain = require("src.features.hunters.brain")
local Render = require("src.features.cyber-feud.droid_render")

local Droids = {}

-- Tuning ------------------------------------------------------------------
Droids.count = 2 -- for one human player...
Droids.perHuman = 1 -- ...and this many more for each human past the first
Droids.fov = math.rad(90) -- how wide their cone of sight is
Droids.alertFov = math.rad(140) -- and while one is on edge
Droids.aware = 200 -- px all round them they notice somebody in, any way they face
Droids.health = 240 -- a Hunter has 180, an officer 60
Droids.pace = 1.25 -- how much quicker than a Hunter they move
Droids.dodgeCool = 3 -- seconds before one can dodge again (a Hunter's 1.1): time to land a burst or two
Droids.damage = 14 -- a rail pistol round
Droids.burst = 3 -- rounds at the pistol's rate...
Droids.pause = 0.9 -- ...then this many seconds
Droids.railDamage = 45 -- the charged rail shot
Droids.railCharge = 0.9 -- seconds the sightline shows before it fires
Droids.railEvery = 6 -- seconds between rail shots
Droids.drops = 10 -- koins one spills
Droids.TINT = "ff3ec8" -- their rounds, Halcyon's magenta

local SYNC_EVERY = 2 -- server ticks between DRD_STATE
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 30 -- px walked in one full step cycle, for the legs
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local FLASH = 0.12 -- seconds a muzzle flash shows
local HURT = 0.18 -- seconds one flashes white after a hit
local DODGE_SHOWN = 0.3 -- seconds a dodge's afterimages show
local CALL_SHOWN = 0.9 -- seconds a call's ping spreads
local SIGHTLINE = 900 -- px the rail shot's sightline reaches, if no wall stops it
local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)

local function fmt(v)
  return ("%.1f"):format(v)
end

--- Their guns: the rail pistol, and the rail shot, heavy and fast.
local function arms()
  local pistol = Tiers.apply(Guns.pistol, Tiers.DEFAULT)
  local gun = setmetatable({ damage = Droids.damage, cooldown = 0.12, tint = Droids.TINT }, { __index = pistol })
  local rail = setmetatable({ damage = Droids.railDamage, speed = 1300, streak = 30, spread = 0, tint = Droids.TINT },
    { __index = pistol })
  return {
    gun = gun,
    stunGun = rail,
    burst = Droids.burst,
    pause = Droids.pause,
    reach = pistol.speed * (pistol.ttl or ROUND_TTL) * 0.85,
  }
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends, calm }

--- `route` with every corner moved to the nearest open spot.
local function settle(nav, route)
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

--- Put the droids on `map`'s `droids` beats ({ route, count, perHuman }
--- each, and more on a job finished before), finding their way with `nav`
--- (a walking grid, d-day/nav.lua), standing still while `calm`. Nothing on
--- a map without them.
function Droids.serverStart(server, map, nav, calm)
  sv = nil
  local spec = map.droids
  if not (spec and nav) then
    return
  end
  local brain = Brain.new({
    fov = Droids.fov, alertFov = Droids.alertFov, aware = Droids.aware,
    health = Bosses.enemyHealth(Droids.health),
    radius = Render.RADIUS, nav = nav, pace = Droids.pace, dodgeCool = Droids.dodgeCool,
    stunCharge = Droids.railCharge, stunEvery = Droids.railEvery, lockAim = true,
  })
  sv = { brain = brain, syncIn = 0, emptySends = 0, calm = calm }
  for _, beat in ipairs(spec) do
    local route = settle(nav, beat.route)
    if #route >= 2 then
      local n = (beat.count or Droids.count) + (beat.perHuman or Droids.perHuman) * (Bosses.humans(server) - 1)
      n = math.floor(n * (1 + Bosses.rage.count * Bosses.clears()) + 0.5)
      for i = 1, n do
        brain:add(route, math.floor((i - 1) * #route / n) + 1, arms())
      end
    end
  end
end

--- The street wakes: they start their beat and see whoever is there.
function Droids.serverWake()
  if sv then
    sv.calm = false
  end
end

--- Over: every screen clears.
function Droids.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("DRD_STATE", server.tick))
  end
end

--- Everything a droid might need to get out of the way of, this tick: a
--- player's rounds in flight, abilities and grenades about to land.
local function threats(server, brain)
  local weapons = Features.byName.weapons
  local rounds = weapons and weapons.sv and weapons.sv.projectiles
  for _, r in ipairs(rounds or {}) do
    if r.owner ~= 0 then -- a player's or a bot's
      local speed = math.sqrt(r.vx * r.vx + r.vy * r.vy)
      if speed > 0 then
        local width = r.blast and r.blast.radius * 0.6 or 0
        local fx, fy = r.x - r.vx * r.age, r.y - r.vy * r.age -- where it was fired from
        brain:threatLine(server, r.owner, fx, fy, r.x, r.y, r.vx / speed, r.vy / speed, speed,
          speed * (r.ttl - r.age), width)
      end
    end
  end
  for _, name in ipairs({ "abilities", "grenades" }) do
    local f = Features.byName[name]
    if f and f.serverIncoming then
      for _, a in ipairs(f:serverIncoming()) do
        brain:threatArea(a.x, a.y, a.radius)
      end
    end
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
  local msg = Protocol.encode("DRD_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Droids.serverStep(server, dt)
  if not sv then
    return
  end
  local brain = sv.brain
  if not sv.calm then
    threats(server, brain)
    brain:update(server, dt)
  end
  for _, h in ipairs(brain.calls) do
    server:broadcast(Protocol.encode("DRD_CALL", h.id, fmt(h.x), fmt(h.y)))
  end
  brain.calls = {}
  for _, h in ipairs(brain.list) do -- what happened since the last sync, for the flash and the afterimages
    h.shotSince = h.shotSince or h.fired
    h.dodgedSince = h.dodgedSince or h.dodging ~= nil
  end
  sync(server)
end

--- One down: scrap on every screen, koins, maybe a pickup.
local function down(server, h, by, angle, cause)
  server:broadcast(Protocol.encode("DRD_DOWN", h.id, fmt(h.x), fmt(h.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, h.x, h.y, Droids.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, h.x, h.y)
  end
  Features.call("serverKill", server, { kind = "droid", x = h.x, y = h.y, by = by, angle = angle, cause = cause })
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the factions', their own) pass by.
function Droids.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local h, i = sv.brain:at(x, y, radius)
  if not h then
    return false
  end
  if sv.calm then
    require("src.features.cyber-feud.troops").serverWake() -- the whole street, not just them
  end
  if sv.brain:hurt(server, h, i, damage or 20, angle, by) then
    down(server, h, by, angle, dtype)
  end
  return true
end

--- Every assassin droid standing, for the audit (tools/audit).
function Droids.serverEnemies(_server, add)
  for _, h in ipairs(sv and sv.brain.list or {}) do
    add({ id = h, kind = "cyber-feud/droid", x = h.x, y = h.y, hp = h.hp, radius = sv.brain.radius })
  end
end

--- A player's or a bot's gun went off at (x, y): any within earshot look.
function Droids.serverShotFired(player, x, y)
  if sv and player then
    sv.brain:heard(x, y)
  end
end

function Droids.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Droids.serverPanicArea(x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius, 0.5)
  end
end

--- For tests.
function Droids.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, alert, wary, cycle, stride, cloak, flash, hurt, dodge, ... }
local calls = {} -- { x, y, t }: the ping of a call going out
local scrap = {} -- { x, y, vx, vy, a, spin, t, size, glow }: what is left of one that went down
local lastTick = 0
local heardAt = 0
local STALE = 1
local clock = 0
local SCRAP_TIME = 12 -- seconds its scrap lies there

function Droids.clear()
  shown, calls, scrap, lastTick = {}, {}, {}, 0
end

function Droids.update(dt)
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
      h.cycle = h.cycle + moved / STEP
    end
    local speed = moved / math.max(dt, 1e-6)
    h.stride = h.stride + (math.min(1, speed / 50) - h.stride) * math.min(1, dt * 6)
    -- The cloak drops at once when it has somebody and comes back slowly.
    local cloak = h.wary and 0 or 1
    h.cloak = cloak < h.cloak and cloak or h.cloak + (cloak - h.cloak) * math.min(1, dt * 0.8)
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
  for i = #scrap, 1, -1 do
    local p = scrap[i]
    p.t = p.t + dt
    local drag = math.max(0, 1 - dt * 4)
    p.vx, p.vy = p.vx * drag, p.vy * drag
    p.x, p.y, p.a = p.x + p.vx * dt, p.y + p.vy * dt, p.a + p.spin * dt * drag
    p.spin = p.spin * drag
    if p.t > SCRAP_TIME then
      table.remove(scrap, i)
    end
  end
end

--- The scrap of the fallen, on the ground under everything.
function Droids.drawBelowCars()
  for _, p in ipairs(scrap) do
    local fade = math.min(1, (SCRAP_TIME - p.t) / 2)
    love.graphics.push()
    love.graphics.translate(p.x, p.y)
    love.graphics.rotate(p.a)
    local c = p.plate and Render.PLATE_SHADE or Render.FRAME
    love.graphics.setColor(c[1], c[2], c[3], fade)
    love.graphics.rectangle("fill", -p.size, -p.size * 0.5, p.size * 2, p.size)
    if p.glow then -- a part still sparking now and then
      local on = math.sin(clock * 9 + p.size * 7) > 0.6 and 1 or 0.25
      love.graphics.setColor(Render.GLOW[1], Render.GLOW[2], Render.GLOW[3], fade * on)
      love.graphics.circle("fill", 0, 0, 1.6, 6)
    end
    love.graphics.pop()
  end
end

function Droids.drawAboveCars()
  for _, c in ipairs(calls) do -- a call going out: a magenta ping
    local k = c.t / CALL_SHOWN
    love.graphics.setColor(Render.GLOW[1], Render.GLOW[2], Render.GLOW[3], 0.6 * (1 - k))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", c.x, c.y, 16 + k * 140, 40)
  end
  for _, h in pairs(shown) do
    if h.charging then
      -- Its sightline: where the rail shot will go, out to the first wall.
      local mx, my = h.dx + math.cos(h.facing) * 20, h.dy + math.sin(h.facing) * 20
      local ex, ey = Sight.reach(mx, my, h.facing, SIGHTLINE)
      local pulse = 0.55 + 0.45 * math.abs(math.sin(clock * 20))
      love.graphics.setColor(Render.GLOW[1], Render.GLOW[2], Render.GLOW[3], 0.25 * pulse)
      love.graphics.setLineWidth(5)
      love.graphics.line(mx, my, ex, ey)
      love.graphics.setColor(Render.HOT[1], Render.HOT[2], Render.HOT[3], 0.85 * pulse)
      love.graphics.setLineWidth(1)
      love.graphics.line(mx, my, ex, ey)
    end
  end
  love.graphics.setLineWidth(1)
  for _, h in pairs(shown) do
    Render.draw(h.dx, h.dy, h.facing, {
      cycle = h.cycle, stride = h.stride, alert = h.alert, cloak = h.cloak, firing = h.flash > 0,
      charging = h.charging, hurt = h.hurt / HURT * 0.7, dodge = h.dodge / DODGE_SHOWN, dodgeX = h.dodgeX,
      dodgeY = h.dodgeY,
    }, clock)
    if h.hp < h.top then
      local bw, f = 28, math.max(0, h.hp / h.top)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", h.dx - bw / 2 - 1, h.dy + Render.RADIUS + 5, bw + 2, 5)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", h.dx - bw / 2, h.dy + Render.RADIUS + 6, bw * f, 3)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- At night (the night feature), each visor glows; a cloaked one barely.
function Droids.drawNightLights(glow)
  for _, h in pairs(shown) do
    glow(h.dx, h.dy, h.charging and 90 or 40, Render.GLOW, h.charging and 0.9 or 0.25 + 0.4 * (1 - h.cloak))
  end
end

--- The footsteps feature's walkers.
function Droids.walkers()
  local list = {}
  for id, h in pairs(shown) do
    if h.cloak < 0.5 then -- cloaked, its steps are silent too
      list[#list + 1] = { key = "drd" .. id, x = h.dx, y = h.dy, size = "person" }
    end
  end
  return list
end

Droids.clientMessages = {
  DRD_STATE = function(_client, args)
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
          h = { dx = x, dy = y, x = x, y = y, cycle = love.math.random(), stride = 0, cloak = 1, flash = 0,
            hurt = 0, dodge = 0, hp = Droids.health }
          shown[id] = h
        end
        if args[i + 7] == "1" then -- dodging: its afterimages trail back the way it came
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
        h.top = math.max(h.top or Droids.health, hp) -- (tougher on a job finished before)
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
  DRD_CALL = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y then
      local h = id and shown[id]
      calls[#calls + 1] = { x = h and h.dx or x, y = h and h.dy or y, t = 0 }
    end
  end,
  DRD_DOWN = function(client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local h = id and shown[id]
    if id then
      shown[id] = nil
    end
    if not (x and y) then
      return
    end
    x, y = h and h.dx or x, h and h.dy or y
    -- It comes apart: plates and frame thrown on along the round's way.
    for k = 1, 9 do
      local a = angle + (love.math.random() - 0.5) * 2.2
      local v = 60 + love.math.random() * 180
      scrap[#scrap + 1] = { x = x, y = y, vx = math.cos(a) * v, vy = math.sin(a) * v, a = love.math.random() * 6,
        spin = (love.math.random() - 0.5) * 14, t = 0, size = 2 + love.math.random() * 3, plate = k % 2 == 0,
        glow = k <= 3 }
    end
    local weapons = Features.byName.weapons
    if weapons and weapons.explosionAt then
      weapons:explosionAt(client, x, y, Render.GLOW) -- its core going up
    end
  end,
}

return Droids
