-- Hyperbole's army on a level (docs/borderline.md, "The army"): the robots
-- on the host, and how they look on every screen. init.lua passes its hooks
-- on to this module.
--
-- The map says who stands where (city-map's `map.army`, borderline.lua):
--   packs   { code, x, y, count }  a pack picking about a spot; `count` for
--           one human and one more for each human past the first
--           (Bosses.plus). Seeing somebody, or hurt, one wakes the lot.
--   posts   { code, x, y, watch, dock }  one standing watch, facing `watch`;
--           a hauler dock (DCK) carries its `dock` key, the terminal that
--           shuts it down carries the same (the terminals feature)
--   squads  { codes, route, start }  a squad walking `route` (a loop of
--           { x, y }) from corner `start`, `codes[1]` leading
-- Each model's brain (`BRAINS`, by code) thinks for it; the body they all
-- share is chassis.lua's. One spotting somebody calls those of the army
-- within `Army.CALL` px (and the rest of its pack, wherever they are) to
-- come and look.
--
-- The army is all one side: its rounds carry its name (weapons' `from`),
-- and an ownerless round or blast passes through every one of them. Only
-- players' rounds and blasts reach them, with two exceptions that hurt
-- their own side too: a plasma hauler's tank bursting and a kamikaze
-- hauler going off (each brain's `burst`). A dozer's blade stops rounds
-- from in front (`blocks`), an arc hauler's dome rounds from outside it
-- (domes.lua), a shield drone's bubble soaks hits first (chassis.lua).
-- What comes down out of the sky on red rings is barrage.lua's (the rocket
-- haulers' pods, the jet haulers' runs, the badass hauler's); the plasma
-- bolts are bolts.lua's, the stalker haulers' flechettes darts.lua's.
--
-- The terminals' alarm (`serverAlarm`) brings the army near one being
-- hacked, and a terminal done shuts down the dock it runs (`serverShutDock`).
--
-- Messages
--   server -> all  HYP_STATE <tick> [<id> <code> <x> <y> <facing> <hp> <state> <aim> <link> <shield> <breath>
--                  <winded>]...
--                  (unreliable, 15 Hz; state 0 calm, 1 after somebody, 2 crawling, 3 in the air, 4 a sentry up;
--                  aim 1 while it is lining up a shot or winding up: its coils, pods or thrusters glow, its core
--                  races; link the hauler a drone's beam is on (0 none); shield its bubble's points; breath and
--                  winded a model with breath's (bosses/stamina.lua's wire: the stalker's), -1 and 0 for the rest)
--   server -> all  HYP_DOWN  <id> <x> <y> <angle> <code>   one went down
--   server -> all  HYP_ALERT <id>                          one spotted somebody (its beep)
--   server -> all  HYP_CRAWL <id>                          one lost its legs and fights on
--   server -> all  HYP_STOMP <id>                          a badass hauler stamped
--   (and barrage.lua's HYP_RAIN, bolts.lua's HYP_BOLT and HYP_SPLASH, darts.lua's HYP_DART and HYP_STICK,
--   domes.lua's HYP_DOME)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Nav = require("src.features.d-day.nav")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Chassis = require("src.features.borderline.chassis")
local Look = require("src.features.borderline.hauler_look")
local Junk = require("src.features.borderline.junk_brain")
local Gun = require("src.features.borderline.gun_brain")
local Rpg = require("src.features.borderline.rpg_brain")
local Plz = require("src.features.borderline.plz_brain")
local Jet = require("src.features.borderline.jet_brain")
local Exp = require("src.features.borderline.exp_brain")
local Dzr = require("src.features.borderline.dzr_brain")
local Arc = require("src.features.borderline.arc_brain")
local Drone = require("src.features.borderline.drone_brain")
local Sentry = require("src.features.borderline.sentry_brain")
local Dock = require("src.features.borderline.dock_brain")
local Bad = require("src.features.borderline.bad_brain")
local Stk = require("src.features.borderline.stk_brain")
local Domes = require("src.features.borderline.domes")
local DroneLook = require("src.features.borderline.drone_look")
local DockLook = require("src.features.borderline.dock_look")
local Barrage = require("src.features.borderline.barrage")
local Bolts = require("src.features.borderline.bolts")
local Darts = require("src.features.borderline.darts")

local Army = {}

-- Tuning ------------------------------------------------------------------
Army.FROM = "hyperbole" -- the name on its rounds
Army.CALL = 520 -- px; the army this near one that spots somebody comes to look
Army.drops = { JNK = 1, GUN = 3, RPG = 5, PLZ = 4, JET = 4, EXP = 2, DZR = 6, ARC = 4, FIX = 1, SHD = 1, SEN = 2,
  BAD = 15, DCK = 10, STK = 6 } -- koins each spills
Army.pickupChance = { JNK = 0.2, EXP = 0.2, FIX = 0.3, SHD = 0.3, SEN = 0.3 } -- the chance it drops anything at
-- all (pickups' own odds after); every other model always does

local BRAINS = { JNK = Junk, GUN = Gun, RPG = Rpg, PLZ = Plz, JET = Jet, EXP = Exp, DZR = Dzr, ARC = Arc, FIX = Drone,
  SHD = Drone, SEN = Sentry, BAD = Bad, DCK = Dock, STK = Stk }
local MACHINES = { FIX = true, SHD = true, SEN = true, DCK = true } -- drawn by drone_look.lua and dock_look.lua

local SYNC_EVERY = 2
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local HURT = 0.18
local MAX_WRECKS = 60

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { roster, syncIn, sentEmpty }

--- Put the army on `map` (its `army`), or nothing on a map without one.
function Army.serverStart(server, map)
  Army.serverStop(server)
  local spec = map and map.army
  if not spec then
    return
  end
  local nav = Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
  local roster = Chassis.new({ nav = nav, from = Army.FROM, firstId = 1 })
  roster.bounds = { x0 = map.left, y0 = map.top, x1 = map.left + map.w, y1 = map.top + map.h }
  for i, pack in ipairs(spec.packs or {}) do
    local brain = BRAINS[pack.code]
    local n = Bosses.plus(pack.count or 3, server)
    for k = 1, n do
      local a, d = k / n * 2 * math.pi, n > 1 and 40 + random() * 30 or 0
      local s = roster:add(brain, pack.code, pack.x + math.cos(a) * d, pack.y + math.sin(a) * d, random() * 2 * math.pi)
      s.pack = i
    end
  end
  for _, post in ipairs(spec.posts or {}) do
    local s = roster:add(BRAINS[post.code], post.code, post.x, post.y, post.watch)
    s.dock = post.dock
  end
  for _, squad in ipairs(spec.squads or {}) do
    local from = squad.route[squad.start or 1]
    local members = {}
    for _, code in ipairs(squad.codes) do
      members[#members + 1] = roster:add(BRAINS[code], code, from.x, from.y, 0)
    end
    local brain = BRAINS[squad.codes[1]]
    if brain.formSquad then
      brain.formSquad(members, squad.route, squad.start)
    end
  end
  Barrage.serverStart()
  Bolts.serverStart()
  Darts.serverStart()
  sv = { roster = roster, syncIn = 0, sentEmpty = false }
end

function Army.serverStop(server)
  Barrage.serverStop()
  Bolts.serverStop()
  Darts.serverStop()
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("HYP_STATE", server.tick))
  end
end

--- `s` has spotted somebody: it beeps, and the army near it (and its pack)
--- comes to look where it is looking.
local function callOut(server, s)
  server:broadcast(Protocol.encode("HYP_ALERT", s.id))
  sv.alerted = true
  local x, y = s.seenX or s.x, s.seenY or s.y
  for _, o in ipairs(sv.roster.list) do
    if o ~= s and o.brain.wake
      and ((s.pack and o.pack == s.pack) or Chassis.dist2(o.x, o.y, s.x, s.y) <= Army.CALL * Army.CALL) then
      o.brain.wake(o, x, y)
    end
  end
end

local down

--- What `s` leaves going off where it fell (a plasma hauler's tank, a
--- kamikaze's core): `splash` over the players near, and into its own
--- side, credited to whoever set it off.
local function burst(server, s, splash, by)
  local dtype = splash.type or "plasma"
  local weapons = Features.byName.weapons
  if dtype == "plasma" then
    Bolts.serverSplash(server, s.x, s.y, splash.radius, splash.damage)
  elseif weapons and weapons.explode then -- nobody's blast: the boom and the players (pid 0, no round)
    weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
      blast = { radius = splash.radius, damage = splash.damage * Bosses.enemyPower(), soft = 0, type = dtype } },
      s.x, s.y)
  end
  -- Who it catches, picked out first: one going down may set off another.
  local roster, caught = sv.roster, {}
  for _, o in ipairs(roster.list) do
    if not o.flying and Chassis.dist2(o.x, o.y, s.x, s.y) <= (splash.radius + o.radius) ^ 2 then
      caught[#caught + 1] = o
    end
  end
  for _, o in ipairs(caught) do
    local i = roster:indexOf(o)
    if i then
      local d = math.sqrt(Chassis.dist2(o.x, o.y, s.x, s.y))
      local amount = splash.damage * (1 - (2 / 3) * math.min(1, d / splash.radius))
      local angle = math.atan2(o.y - s.y, o.x - s.x)
      if roster:hurt(o, i, amount, by, angle) == "down" then
        down(server, o, by, angle, dtype)
      end
    end
  end
end

function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("HYP_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or s.facing), s.code))
  if s.brain.gone then
    s.brain.gone(s)
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Army.drops[s.code] or 1)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy and random() < (Army.pickupChance[s.code] or 1) then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "robot", what = s.code, x = s.x, y = s.y, by = by, angle = angle,
    cause = cause })
  local splash = s.brain.burst and s.brain.burst(s, angle)
  if splash then
    burst(server, s, splash, by)
  end
  -- The rest come to see what happened.
  for _, o in ipairs(sv.roster.list) do
    if o.brain.wake and Chassis.dist2(o.x, o.y, s.x, s.y) <= Army.CALL * Army.CALL then
      o.brain.wake(o, s.x, s.y)
    end
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.roster.list
  if #list == 0 and sv.sentEmpty then
    return
  end
  sv.sentEmpty = #list == 0
  local parts = { server.tick }
  for _, s in ipairs(list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = s.code
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    local up = s.brain == Sentry and s.rise > 0
    parts[#parts + 1] = s.crawl and 2 or s.flying and 3 or up and 4 or (s.target and 1 or 0)
    local lining = s.target and s.aimFor > 0 and s.aimFor < s.conf.aim
    parts[#parts + 1] = (s.charging or lining) and 1 or 0
    parts[#parts + 1] = s.beaming and s.link or 0
    parts[#parts + 1] = ("%.0f"):format(s.shield or 0)
    local breath, winded = -1, 0
    if s.breath then
      breath, winded = s.breath:wire()
    end
    parts[#parts + 1] = breath
    parts[#parts + 1] = winded
  end
  local msg = Protocol.encode("HYP_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Army.serverStep(server, dt)
  if not sv then
    return
  end
  Barrage.serverStep(server, dt)
  Bolts.serverStep(server, dt)
  Darts.serverStep(server, dt)
  for _, s in ipairs(sv.roster:update(server, dt)) do
    down(server, s, s.lastBy, s.facing + math.pi, "bullet") -- a crawl that gave out
  end
  Drone.fade(sv.roster, dt)
  Domes.serverStep(server, sv.roster, dt)
  -- Kamikazes that reached somebody go off: picked out first, since each
  -- blast may take others off the list.
  local going = {}
  for _, s in ipairs(sv.roster.list) do
    if s.detonate then
      going[#going + 1] = s
    end
  end
  for _, s in ipairs(going) do
    local i = sv.roster:indexOf(s)
    if i then
      table.remove(sv.roster.list, i)
      down(server, s, nil, s.facing, "explosive")
    end
  end
  for _, s in ipairs(sv.roster.list) do
    if s.spotted then
      s.spotted = nil
      callOut(server, s)
    end
  end
  sync(server)
end

--- A round through (x, y): the `serverShotAt` convention. Players' rounds
--- and blasts hit; an ownerless one (the army's own) passes through.
function Army.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.roster:at(x, y, radius)
  if not s then
    return false
  end
  if (s.brain.blocks and s.brain.blocks(s, angle, dtype)) or Domes.shields(server, sv.roster, s, by) then
    return true -- stopped at the blade or the dome
  end
  local result = sv.roster:hurt(s, i, damage or 20, by, angle)
  if result == "down" then
    down(server, s, by, angle, dtype)
  elseif result == "crawl" then
    server:broadcast(Protocol.encode("HYP_CRAWL", s.id))
  end
  return true
end

--- A terminal's alarm (the terminals feature) at (x, y): the army within
--- `radius` comes to look.
function Army.serverAlarm(_server, x, y, radius)
  for _, o in ipairs(sv and sv.roster.list or {}) do
    if o.brain.wake and Chassis.dist2(o.x, o.y, x, y) <= radius * radius then
      o.brain.wake(o, x, y)
    end
  end
end

--- The terminal that runs dock `key` was hacked by player `by`: the dock
--- shuts down, as good as shot (its koins, its wreck).
function Army.serverShutDock(server, key, by)
  for i, s in ipairs(sv and key and sv.roster.list or {}) do
    if s.dock == key then
      table.remove(sv.roster.list, i)
      down(server, s, by, s.facing + math.pi, "shock")
      return
    end
  end
end

--- A wave of `codes` coming in from (x, y) at (toX, toY) (hold.lua): one
--- more gun hauler for each human past the first (Bosses.plus). Each makes
--- (toX, toY) its post, so whoever survives stays there.
function Army.serverWave(server, codes, x, y, toX, toY)
  if not sv then
    return
  end
  local list = { unpack(codes) }
  for _ = 1, Bosses.plus(#codes, server) - #codes do
    list[#list + 1] = "GUN"
  end
  for k, code in ipairs(list) do
    local a = k / #list * 2 * math.pi
    local s = sv.roster:add(BRAINS[code], code, x + math.cos(a) * 50, y + math.sin(a) * 50,
      math.atan2(toY - y, toX - x))
    s.homeX, s.homeY = toX + math.cos(a) * 120, toY + math.sin(a) * 60
    if s.brain.wake then
      s.brain.wake(s, toX, toY)
    end
  end
end

--- The level's walking grid, for the terminals' walls coming down.
function Army.nav()
  return sv and sv.roster.nav
end

--- Every robot out on the level, for the audit (tools/audit).
function Army.serverEnemies(_server, add)
  for _, s in ipairs(sv and sv.roster.list or {}) do
    add({ id = s, kind = "borderline/" .. s.code:lower(), x = s.x, y = s.y, hp = s.hp + (s.shield or 0),
      radius = s.radius, flying = (s.brain == Jet or s.brain == Drone) or nil, immune = (s.flying or s.sunk) or nil })
  end
end

function Army.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.roster:freeze(x, y, radius, seconds)
  end
end

--- Has the army spotted anyone yet on this level?
function Army.alerted()
  return sv ~= nil and sv.alerted == true
end

--- For tests.
function Army.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { code, x, y, dx, dy, facing, hp, max, state, aim, link, shield, stride, hurt, rise }
local wrecks = {} -- { x, y, angle, code }
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

function Army.load()
  Bolts.load()
  Darts.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- Spotting somebody: two quick rising beeps.
  bank.beep = make(0.3, 0.5, function(buf)
    buf:tone(0, 0.09, 880, { wave = "square", amp = 0.25, decay = 0.08 })
    buf:tone(0.12, 0.12, 1320, { wave = "square", amp = 0.25, decay = 0.1 })
  end)
  -- Going down: a crunch of metal and a falling whine.
  bank.crash = make(0.7, 0.7, function(buf)
    buf:noiseBurst(0, 0.4, { amp = 0.7, decay = 0.12 })
    buf:sweep(0, 0.6, 600, 90, { wave = "saw", amp = 0.25, decay = 0.4 })
    buf:lowpass(2600)
  end)
  -- A badass hauler's stamp: a deep thud.
  bank.stomp = make(0.6, 0.8, function(buf)
    buf:sweep(0, 0.5, 120, 40, { wave = "sine", amp = 0.8, decay = 0.25 })
    buf:noiseBurst(0, 0.2, { amp = 0.5, decay = 0.08 })
    buf:lowpass(600)
  end)
  -- Losing its legs: a snap and a grinding scrape.
  bank.snap = make(0.5, 0.6, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 0.8, decay = 0.03 })
    buf:noiseBurst(0.1, 0.35, { amp = 0.3, decay = 0.3 })
    buf:highpass(900)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + random() * 0.2)
    s:setVolume(0.6 * Audio.volume("weapons"))
    s:play()
  end
end

function Army.clear()
  shown, wrecks, lastTick = {}, {}, 0
  Barrage.clear()
  Bolts.clear()
  Darts.clear()
  Domes.clear()
end

--- Ease the one shown at `s` towards where the host last said it was
--- (`k` of the way this frame), jumping there when it is far off.
local function follow(s, k)
  local gapX, gapY = s.x - s.dx, s.y - s.dy
  local gap = math.sqrt(gapX * gapX + gapY * gapY)
  if gap > SNAP then
    s.dx, s.dy = s.x, s.y
    return
  end
  s.dx, s.dy = s.dx + gapX * k, s.dy + gapY * k
  s.stride = s.stride + gap * k -- the legs step with the ground covered
end

function Army.update(dt, client)
  clock = clock + dt
  Barrage.update(dt)
  Bolts.update(dt)
  Darts.update(dt, client)
  Domes.update(dt)
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {} -- nothing heard for a while: they are gone
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    follow(s, k)
    s.hurt = math.max(0, s.hurt - dt)
    s.charge = s.aim and math.min(1, (s.charge or 0) + dt * 2) or 0
    s.rise = math.max(0, math.min(1, (s.rise or 0) + (s.state == 4 and dt or -dt) * 2))
  end
end

function Army.drawBelowCars()
  for _, w in ipairs(wrecks) do
    if w.code == "DCK" then
      DockLook.drawWreck(w.x, w.y, clock)
    elseif MACHINES[w.code] then
      DroneLook.drawDebris(w.x, w.y, w.x % 5)
    else
      Look.drawWreck(w, clock)
    end
  end
  Barrage.drawBelowCars(clock)
  Darts.drawBelowCars(clock)
end

--- Its health under it once hurt, and under that its breath (a model with
--- breath, once it has spent some): blue, throbbing red while it is winded.
local function healthBar(s)
  local r = s.code == "DCK" and DockLook.RADIUS or Look.radius(s.code)
  local bw, y = 24, s.dy + r + 5
  if s.hp < s.max then
    local f = math.max(0, s.hp / s.max)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", s.dx - bw / 2 - 1, y, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", s.dx - bw / 2, y + 1, bw * f, 2)
    y = y + 4
  end
  if s.breath and s.breath >= 0 and (s.breath < 100 or s.winded) then
    local f = math.min(1, s.breath / 100)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", s.dx - bw / 2 - 1, y, bw + 2, 4)
    if s.winded then
      love.graphics.setColor(1, 0.2, 0.15, 0.55 + 0.45 * math.sin(clock * 10))
    else
      love.graphics.setColor(0.35, 0.65, 1)
    end
    love.graphics.rectangle("fill", s.dx - bw / 2, y + 1, math.max(1, bw * f), 2)
  end
end

local function drawOne(s)
  local flash = s.hurt / HURT
  if s.code == "DCK" then
    DockLook.draw({ dx = s.dx, dy = s.dy, aim = s.facing, charge = s.charge, flash = flash }, clock)
  elseif s.code == "SEN" then
    DroneLook.drawSentry({ dx = s.dx, dy = s.dy, aim = s.facing, rise = s.rise, charge = s.charge, flash = flash },
      clock)
  elseif MACHINES[s.code] then
    local ward = shown[s.link or 0]
    DroneLook.drawDrone({ dx = s.dx, dy = s.dy, facing = s.facing, code = s.code, flash = flash,
      beamX = ward and ward.dx, beamY = ward and ward.dy }, clock)
  else
    Look.draw({ dx = s.dx, dy = s.dy, facing = s.facing, code = s.code, stride = s.stride, charge = s.charge,
      flash = flash, crawl = s.state == 2, flying = s.state == 3 }, clock)
    if (s.shield or 0) > 0 then
      DroneLook.drawBubble(s.dx, s.dy, Look.radius(s.code) + 10, clock, s.shield / Drone.SHIELD)
    end
  end
  if s.state ~= 3 and (s.code ~= "SEN" or s.rise > 0.5) then
    healthBar(s)
  end
end

--- Where hauler `id` is shown, for its dome.
local function shownAt(id)
  local s = shown[id]
  if s then
    return s.dx, s.dy
  end
end

--- Those on the ground, the domes and the bolts, then those in the air
--- (jets, drones) and the rockets coming down over everything.
local function flies(s)
  return s.state == 3 or s.code == "FIX" or s.code == "SHD"
end

function Army.drawAboveCars()
  for _, s in pairs(shown) do
    if not flies(s) then
      drawOne(s)
    end
  end
  Domes.draw(shownAt, clock)
  Bolts.draw(clock)
  Darts.drawAboveCars(clock)
  for _, s in pairs(shown) do
    if flies(s) then
      drawOne(s)
    end
  end
  Barrage.drawAboveCars(clock)
  love.graphics.setColor(1, 1, 1)
end

--- Their clanking feet, for the footsteps feature.
function Army.walkers()
  local list = {}
  for id, s in pairs(shown) do
    if s.state ~= 2 and not MACHINES[s.code] and not flies(s) then
      list[#list + 1] = { key = "arm" .. id, x = s.dx, y = s.dy, size = "heavy" }
    end
  end
  return list
end

Army.clientMessages = {
  HYP_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 11, 12 do
      local id, code, x, y = tonumber(args[i]), args[i + 1], tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y and (Look.KITS[code] or MACHINES[code]) then
        local s = shown[id]
        local hp = tonumber(args[i + 5]) or 0
        if not s then
          s = { code = code, dx = x, dy = y, stride = 0, hurt = 0, hp = hp, max = hp }
          shown[id] = s
        end
        if hp < s.hp then
          s.hurt = HURT
        end
        s.x, s.y, s.hp = x, y, hp
        s.max = math.max(s.max, hp)
        s.facing = tonumber(args[i + 4]) or s.facing or 0
        s.state = tonumber(args[i + 6]) or 0
        s.aim = args[i + 7] == "1"
        s.link = tonumber(args[i + 8])
        s.shield = tonumber(args[i + 9]) or 0
        s.breath, s.winded = Stamina.read(args, i + 10)
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  HYP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y and (Look.KITS[args[5] or ""] or MACHINES[args[5] or ""]) then
      wrecks[#wrecks + 1] = { x = s and s.dx or x, y = s and s.dy or y, angle = angle, code = args[5] }
      if #wrecks > MAX_WRECKS then
        table.remove(wrecks, 1)
      end
      play("crash", x, y)
    end
  end,
  HYP_ALERT = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      play("beep", s.dx, s.dy)
    end
  end,
  HYP_STOMP = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      play("stomp", s.dx, s.dy)
    end
  end,
  HYP_CRAWL = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.state = 2
      play("snap", s.dx, s.dy)
    end
  end,
}
for _, part in ipairs({ Barrage, Bolts, Darts, Domes }) do
  for kind, handler in pairs(part.clientMessages) do
    Army.clientMessages[kind] = handler
  end
end

return Army
