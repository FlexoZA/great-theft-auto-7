-- Suppressors: the Combine's heavy soldiers, a minigun at the hip and an
-- energy shield round them. Slow on their feet and slow to turn, they hold
-- a post; whoever walks into their sights hears the barrels wind up, then
-- a stream of rounds sweeps after them as fast as the Suppressor can turn.
-- After a few seconds of fire the gun has to vent: that is the moment to
-- step out of cover. Lose them and they hose where they saw you last, then
-- plod over to look, never far from their post.
--
-- The shield soaks every hit first (shock tears it down twice as fast)
-- and comes back a few seconds after the last one; a blue skin round them
-- lights up where rounds land on it and bursts in sparks when it goes
-- down. Only then does their health go. They think for themselves
-- (brain.lua).
--
-- Their gun is the minigun players can buy (weapons/guns.lua), at half a
-- player's damage a round. Their rounds belong to nobody (weapons' serverFireFrom, as the Combine's
-- do): they hurt any player and credit nobody, and pass by every Combine
-- soldier, Hunter and Suppressor. Anyone else's rounds hurt them. They go
-- down as a body (the corpses feature), in their plate, the minigun beside
-- them; a blast or fire leaves what it leaves of anyone.
--
-- Another feature puts them on the map: `suppressors:serverPost(server,
-- x, y, watch)` stands one at (x, y) watching `watch` (radians). The
-- Citadel has two (a-man/city17.lua, the map's `suppressors`).
-- `suppressors:serverClear(server)` takes them away; a map change does too.
--
-- The host owns them; clients hear where they are at 15 Hz.
--
-- Messages
--   server -> all  SUP_STATE <tick> (<id> <x> <y> <facing> <hp> <shield> <alert> <spin> <gun>)...
--                  (unreliable, 15 Hz; alert 1 has somebody, 2 hosing or searching, 0 neither;
--                  spin 0-9 how fast the barrels turn; gun 1 fired since the last, 2 venting, 0 neither)
--   server -> all  SUP_BREAK <id>                        its shield went down
--   server -> all  SUP_DOWN  <id> <x> <y> <angle> <cause> one went down (cause: the damage type)
--
-- Modules
--   brain.lua    what each one does, on the host
--   render.lua   one drawn from above, its minigun and its shield
--   sounds.lua   the barrels, the rounds, the vent, the shield going

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Nav = require("src.features.d-day.nav")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Corpses = require("src.features.corpses")
local Brain = require("src.features.suppressors.brain")
local Render = require("src.features.suppressors.render")
local Sounds = require("src.features.suppressors.sounds")

local Suppressors = {
  name = "suppressors",
}

-- Tuning ------------------------------------------------------------------
-- Their eyes: City 17's Combine soldiers' (a-man/city17.lua).
Suppressors.fov = math.rad(60) -- how wide their cone of sight is
Suppressors.alertFov = math.rad(90) -- and while one is on edge
Suppressors.aware = 150 -- px all round them they notice somebody in, any way they face
Suppressors.health = 220 -- under the shield: eleven pistol rounds (a Combine soldier takes 60)
Suppressors.shield = 160 -- what the shield soaks before the health goes
Suppressors.damage = 5 -- a round of his minigun (a player's does 10): it is the number of them that hurts
Suppressors.blastDamage = 45 -- what a blast's share (a rocket, a grenade) takes off one
Suppressors.drops = 12 -- koins one spills

local SYNC_EVERY = 2 -- server ticks between SUP_STATE
local SMOOTHING = 12 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 40 -- px walked in one full step cycle
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local FLASH = 0.06 -- seconds a muzzle flash shows
local HURT = 0.18 -- seconds one flashes white after a hit to its health
local GLOW = 0.35 -- seconds the shield glows after a hit on it
local FIRING_HELD = 0.2 -- seconds of rounds a "fired" in one state is good for, on screen
local BREAK_SHOWN = 0.5 -- seconds a shield's sparks fly
local MAX_TURN = 40 -- rad/s the barrels turn flat out

local function fmt(v)
  return ("%.1f"):format(v)
end

--- The minigun (weapons/guns.lua's, common), its rounds weaker than a
--- player's and sounded here rather than by weapons (one sound per round,
--- out of sounds.lua). His own brain winds it up and paces it.
local function minigun()
  return setmetatable({ damage = Suppressors.damage, quiet = true }, {
    __index = Tiers.apply(Guns.minigun, Tiers.DEFAULT),
  })
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

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
      fov = Suppressors.fov, alertFov = Suppressors.alertFov, aware = Suppressors.aware,
      health = Suppressors.health, shield = Suppressors.shield, radius = Render.RADIUS, nav = nav,
    }),
    syncIn = 0,
    emptySends = 0,
  }
  return sv
end

--- One standing at (x, y), watching `watch`. Returns it.
function Suppressors:serverPost(_server, x, y, watch)
  return server().brain:add(x, y, watch or 0, minigun())
end

--- Take every one away.
function Suppressors:serverClear()
  if sv then
    sv.brain.list = {}
  end
end

local shown = {} -- client: id -> what is drawn of it
local breaks = {} -- client: { x, y, t, seed } a shield going down

function Suppressors:mapChanged()
  sv, shown, breaks = nil, {}, {}
end

function Suppressors:serverStart()
  sv = nil
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
  for _, u in ipairs(list) do
    parts[#parts + 1] = u.id
    parts[#parts + 1] = ("%.0f"):format(u.x)
    parts[#parts + 1] = ("%.0f"):format(u.y)
    parts[#parts + 1] = ("%.2f"):format(u.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, u.hp))
    parts[#parts + 1] = ("%.0f"):format(math.max(0, u.shield))
    parts[#parts + 1] = u.target and 1 or (Brain.wary(u) and 2 or 0)
    parts[#parts + 1] = math.floor(u.spin * 9 + 0.5)
    parts[#parts + 1] = u.firedSince and 1 or (u.vent > 0 and 2 or 0)
    u.firedSince = false
  end
  local msg = Protocol.encode("SUP_STATE", unpack(parts))
  for _, player in pairs(srv.players) do
    if not player.bot then
      srv:send(player, msg, true)
    end
  end
end

function Suppressors:serverStep(srv, dt)
  if not sv then
    return
  end
  sv.brain:update(srv, dt)
  for _, u in ipairs(sv.brain.list) do
    u.firedSince = u.firedSince or u.fired
  end
  sync(srv)
end

--- One down: a body on every screen, a few koins, maybe a pickup.
local function down(srv, u, by, angle, dtype)
  srv:broadcast(Protocol.encode("SUP_DOWN", u.id, fmt(u.x), fmt(u.y), ("%.3f"):format(angle or 0), dtype or "bullet"))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(srv, u.x, u.y, Suppressors.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(srv, u.x, u.y)
  end
  Features.call("serverKill", srv, { kind = "suppressor", x = u.x, y = u.y, by = by, angle = angle, cause = dtype })
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the Combine's, the turrets', their own) pass by; a blast's
--- share (no `damage`) takes `blastDamage`.
function Suppressors:serverShotAt(srv, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local u, i = sv.brain:at(x, y, radius)
  if not u then
    return false
  end
  local hadShield = u.shield > 0
  local dead = sv.brain:hurt(u, i, damage or Suppressors.blastDamage, angle, dtype)
  if dead then
    down(srv, u, by, angle, dtype)
  elseif hadShield and u.shield <= 0 then
    srv:broadcast(Protocol.encode("SUP_BREAK", u.id))
  end
  return true
end

--- A gun went off at (x, y) (weapons' `serverShotFired`): a player's or a
--- bot's is heard by any within earshot.
function Suppressors:serverShotFired(_server, player, x, y)
  if sv and player then
    sv.brain:heard(x, y)
  end
end

function Suppressors:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- The host's Suppressors, for tests.
function Suppressors.state()
  return sv
end

-- Client --------------------------------------------------------------------

local lastTick = 0
local clock = 0
local heardAt = 0
local STALE = 1 -- seconds without word from the host before what it last sent is dropped

function Suppressors:load()
  Sounds.load()
end

function Suppressors:exitGame()
  shown, breaks, lastTick = {}, {}, 0
end

function Suppressors:update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, u in pairs(shown) do
    local ex, ey = u.x - u.dx, u.y - u.dy
    local moved = math.sqrt(ex * ex + ey * ey) * k
    if ex * ex + ey * ey > SNAP * SNAP then
      u.dx, u.dy = u.x, u.y
    else
      u.dx, u.dy = u.dx + ex * k, u.dy + ey * k
      u.cycle = u.cycle + moved / STEP
    end
    local speed = moved / math.max(dt, 1e-6)
    u.stride = u.stride + (math.min(1, speed / 30) - u.stride) * math.min(1, dt * 6)
    local fov = u.wary and Suppressors.alertFov or Suppressors.fov
    u.fov = u.fov + (fov - u.fov) * math.min(1, dt * 4)
    u.spinShown = u.spinShown + (u.spin - u.spinShown) * math.min(1, dt * 5)
    u.turn = u.turn + u.spinShown * MAX_TURN * dt
    u.hurt = math.max(0, u.hurt - dt)
    u.glow = math.max(0, u.glow - dt)
    u.flash = math.max(0, u.flash - dt)
    u.venting = math.max(0, u.venting - dt * 0.6)
    -- The roar: one round's sound every so often while the host says it fires.
    if u.firingFor > 0 then
      u.firingFor = u.firingFor - dt
      u.roundIn = u.roundIn - dt
      if u.roundIn <= 0 then
        u.roundIn = u.roundIn + Brain.FIRE_EVERY
        u.flash = FLASH
        Sounds.play("shot", u.dx, u.dy, 0.94 + love.math.random() * 0.12, 0.7)
      end
    end
  end
  for i = #breaks, 1, -1 do
    breaks[i].t = breaks[i].t + dt
    if breaks[i].t > BREAK_SHOWN then
      table.remove(breaks, i)
    end
  end
end

--- Their cones of sight, on the ground under everything, as the Combine's are.
function Suppressors:drawBelowCars()
  for _, u in pairs(shown) do
    Sight.draw(u.dx, u.dy, u.facing, Brain.RANGE, u.alert, clock, u.fov)
  end
end

function Suppressors:drawAboveCars()
  for _, u in pairs(shown) do
    Render.draw(u.dx, u.dy, u.facing, {
      swing = math.sin(u.cycle * 2 * math.pi) * u.stride, turn = u.turn, flash = u.flash > 0, alert = u.alert,
      hurt = u.hurt / HURT * 0.7, shield = u.shield / Suppressors.shield, glow = u.glow / GLOW, venting = u.venting,
    }, clock)
    if u.hp < Suppressors.health or u.shield < Suppressors.shield then -- bars under it once it is hit
      local bw, y = 34, u.dy + Render.RADIUS + 8
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", u.dx - bw / 2 - 1, y - 1, bw + 2, 9)
      local s = math.max(0, u.shield / Suppressors.shield)
      love.graphics.setColor(Render.SHIELD[1], Render.SHIELD[2], Render.SHIELD[3])
      love.graphics.rectangle("fill", u.dx - bw / 2, y, bw * s, 3)
      local f = math.max(0, u.hp / Suppressors.health)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", u.dx - bw / 2, y + 4, bw * f, 3)
    end
  end
  for _, b in ipairs(breaks) do
    Render.shieldBreak(b.x, b.y, b.t / BREAK_SHOWN, b.seed)
  end
  love.graphics.setColor(1, 1, 1)
end

Suppressors.clientMessages = {
  SUP_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 8, 9 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local u = shown[id]
        if not u then
          u = { dx = x, dy = y, x = x, y = y, cycle = love.math.random(), stride = 0, fov = Suppressors.fov,
            hp = Suppressors.health, shield = Suppressors.shield, spin = 0, spinShown = 0, turn = 0, hurt = 0,
            glow = 0, flash = 0, venting = 0, firingFor = 0, roundIn = 0 }
          shown[id] = u
        end
        u.x, u.y = x, y
        u.facing = tonumber(args[i + 3]) or u.facing or 0
        local hp, shield = tonumber(args[i + 4]) or u.hp, tonumber(args[i + 5]) or u.shield
        if hp < u.hp then
          u.hurt = HURT
        end
        if shield < u.shield then
          u.glow = GLOW
        end
        u.hp, u.shield = hp, shield
        u.alert = args[i + 6] == "1"
        u.wary = args[i + 6] ~= "0"
        local spin = (tonumber(args[i + 7]) or 0) / 9
        if spin > 0 and u.spin == 0 then
          Sounds.play("spinup", x, y)
        end
        u.spin = spin
        local gun = args[i + 8]
        if gun == "1" then
          u.firingFor = FIRING_HELD
        elseif gun == "2" and u.venting <= 0 then
          u.firingFor = 0
          Sounds.play("vent", x, y)
          Sounds.play("spindown", x, y)
        end
        if gun == "2" then
          u.venting = 1
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
  SUP_BREAK = function(_client, args)
    local u = shown[tonumber(args[1]) or -1]
    if u then
      u.shield = 0
      breaks[#breaks + 1] = { x = u.dx, y = u.dy, t = 0, seed = love.math.random() * 6.28 }
      Sounds.play("shieldbreak", u.dx, u.dy)
    end
  end,
  SUP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.down(x, y, angle, Render.LOOK, args[5])
    end
  end,
}

--- The footsteps feature's hook: who of mine is walking about, and where.
function Suppressors:footstepWalkers()
  local list = {}
  for id, u in pairs(shown) do
    list[#list + 1] = { key = "sup" .. id, x = u.dx, y = u.dy, size = "heavy" }
  end
  return list
end

return Suppressors
