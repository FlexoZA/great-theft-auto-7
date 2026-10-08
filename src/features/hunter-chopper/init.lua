-- The Hunter-Chopper: the Combine's gunship-helicopter, the Outer City's
-- boss (A-Man's trail, quests' "a-man-2"). When everyone arrives in the
-- Outer City it is already up, flying round and round the square on the
-- island (flight.lua), and its gun (brain.lua) locks on to whoever it can
-- see, warns them with a beam and a whine for a second and fires a burst
-- of blue rounds; every so often it goes on a bombing run instead, diving
-- over a player and dropping bombs off both sides of it (bombs.lua). You
-- hear its rotor from across the city (sounds.lua).
--
-- It can be shot down. Rounds hit its hull and engine pods (render.lua's
-- `hits`; its own rounds and bombs pass through it) through the
-- `serverShotAt` convention, and a missile's blast through `serverBlast`.
-- Its health is `health` for one human, more with more (Bosses.health),
-- shown on the boss bar every boss shares; a machine, it has no breath, no
-- medkits and no dodging. Beaten, it spins out and falls (Flight.fall) and
-- where it hits the ground it goes up in a blast of its own (`crash`), spills
-- koins, raises `serverKill` with kind "boss" and finishes the level
-- (quests' `serverComplete`): the EXIT star comes up by the wreck, which
-- burns there for as long as everyone stays.
--
-- It calls for help as it takes damage (`waves`): at 80% health Combine
-- soldiers are set down under it, three sets of three 8 s apart (the a-man
-- feature's City 17 level, `serverDropTroops`), and go for the nearest
-- player; at 30% A-Man blinks
-- in by the player nearest it, opens his briefcase on three Hunters (the
-- hunters feature) and blinks out again (the a-man feature's `serverVisit`).
--
-- The host flies it and tells everyone where it is; every machine eases
-- what it draws towards that and draws it over everything on the ground.
--
-- Modules
--   render.lua  the chopper from above: hull, rotors, the gun, its shadow; its bombs; its wreck
--   flight.lua  where it flies, on the host, and its fall
--   brain.lua   its brain, on the host: who it goes after, the lock, the burst, the runs
--   bombs.lua   its bombs: falling and going off on the host, their rings on every screen
--   sounds.lua  its rotor loop, the lock-on whine, the klaxon and the bombs' whistle
--
-- Messages
--   server -> all  HC_STATE <tick> [<x> <y> <angle> <bank> <altitude> <aim> <lock> <firing> <run>
--                  <hp> <max> <down>] (unreliable, 15 Hz; nothing after the tick: no chopper;
--                  lock 0..1 the gun locking on, firing 1 while it fires, run 1 on a bombing
--                  run, down 1 going down)
--   server -> all  HC_DOWN  <x> <y> <angle>   it hit the ground there: its wreck
--   and bombs.lua's HC_BOMB

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Bar = require("src.features.bosses.bar")
local Render = require("src.features.hunter-chopper.render")
local Flight = require("src.features.hunter-chopper.flight")
local Brain = require("src.features.hunter-chopper.brain")
local Sounds = require("src.features.hunter-chopper.sounds")
local Bombs = require("src.features.hunter-chopper.bombs")

local HunterChopper = {
  name = "hunter-chopper",
  priority = 120, -- in the air: over the cars and walkers (car tags 110), under the arrows (500)
}

-- Tuning ------------------------------------------------------------------
HunterChopper.questId = "a-man-2" -- the quest it is the boss of
HunterChopper.map = "outercity" -- the map it flies over
HunterChopper.health = 3600 -- 180 pistol rounds, for one player (more humans, more: bosses/init.lua)
HunterChopper.blastReach = 40 -- px past a blast's radius its hull still feels it (it is big)
HunterChopper.drops = 40 -- koins it spills where it comes down
HunterChopper.crashRadius = 150 -- px the blast where it hits the ground reaches
HunterChopper.crashDamage = 60 -- at the middle of that, a third of it at the edge
-- Who it calls in, once each, as its health falls to `at` of the most it had.
HunterChopper.waves = {
  -- `sets` of `troops` Combine soldiers set down under it, `every` seconds apart; for one human (more humans, more)
  { at = 0.8, troops = 3, sets = 3, every = 8 },
  { at = 0.3, hunters = 3 }, -- A-Man drops in with these Hunters in his case, and leaves
}
HunterChopper.hunterRing = 120 -- px out from where he stood that the Hunters' beat runs

local SYNC_EVERY = 2 -- server ticks between HC_STATE
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 300 -- px; a jump this big is a placement, not flight
local FLASH = 0.15 -- seconds the hull flashes when it is hit
local TITLE_COLOR = { 0.55, 0.85, 1 }
local BAR_FILL = { 0.35, 0.6, 0.95 }

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function fmt(v)
  return ("%.1f"):format(v)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == HunterChopper.map and city.map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { flight, brain, bombs, hp, max, down, syncIn, called, drops } while it is up, or coming down

function HunterChopper:load()
  Sounds.load()
end

--- Everyone arrived in the Outer City: it is up and flying.
function HunterChopper:serverQuestStarted(server, quest)
  local map = cityMap()
  if quest.id == self.questId and map and map.bossX then
    local flight = Flight.new(map.bossX, map.bossY, math.pi / 2)
    local max = Bosses.health(self.health, server)
    sv = {
      flight = flight, brain = Brain.new(flight.angle), bombs = Bombs.new(), hp = max, max = max, syncIn = 0,
      called = 0, -- how many of `waves` have come
      drops = {}, -- { troops, left, nextIn }: sets of soldiers still to come
    }
  end
end

local function stop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("HC_STATE", server.tick)) -- an empty state clears every screen
  end
end

function HunterChopper:serverQuestEnded(server)
  stop(server)
end

--- A map change takes it away (on the host) and its wreck (everywhere).
function HunterChopper:mapChanged(_map, server)
  if server then
    stop(server)
  end
  HunterChopper.forgetWreck()
  HunterChopper.forgetFlight()
end

--- A new game: no chopper carried over from the last one.
function HunterChopper:serverStart()
  sv = nil
end

--- Take `amount` off it. At nothing, it starts to go down; `by` and the
--- `angle` of the hit are kept for the kill.
local function hurt(amount, by, angle)
  if sv.down then
    return
  end
  sv.hp = sv.hp - amount
  if sv.hp <= 0 then
    sv.hp, sv.down = 0, { by = by, angle = angle }
    Flight.fall(sv.flight)
  end
end

--- It has hit the ground: the blast, the koins, the kill and the level done.
local function crash(server)
  local f, down = sv.flight, sv.down
  local x, y = f.x, f.y
  server:broadcast(Protocol.encode("HC_DOWN", fmt(x), fmt(y), ("%.3f"):format(f.angle)))
  local weapons = Features.byName.weapons
  if weapons and weapons.explode then
    weapons:explode(server, { id = 0, owner = 0, vx = 0, vy = 1,
      blast = { radius = HunterChopper.crashRadius, damage = HunterChopper.crashDamage, soft = 4 } }, x, y)
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, HunterChopper.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = down.by, angle = down.angle })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, HunterChopper.questId, x, y) -- an EXIT star by the wreck
  end
  stop(server)
end

--- A round through (x, y): the `serverShotAt` convention. Its own rounds
--- (owner 0) pass through it, and so does the share of a blast that comes
--- this way (no `damage`): blasts reach it through `serverBlast`.
function HunterChopper:serverShotAt(_server, x, y, radius, by, angle, damage)
  local f = sv and sv.flight
  if not f or sv.down or by == 0 or not damage then
    return false
  end
  if not Render.hits(f.x, f.y, f.angle, f.altitude, x, y, radius) then
    return false
  end
  hurt(damage, by, angle)
  return true
end

--- A missile went off at (x, y): within its reach, it takes the blast's
--- damage, falling to a third at the edge as for anyone. Its own bombs
--- (owner 0) don't touch it.
function HunterChopper:serverBlast(_server, x, y, radius, damage, owner)
  local f = sv and sv.flight
  if not f or sv.down or owner == 0 or not damage then
    return
  end
  local d = math.sqrt((f.x - x) ^ 2 + (f.y - y) ^ 2)
  local reach = radius + self.blastReach
  if d <= reach then
    hurt(damage * (1 - (2 / 3) * d / reach), owner, math.atan2(f.y - y, f.x - x))
  end
end

--- `count` Hunters on a ring round (x, y), walking it.
local function hunters(server, x, y, count)
  local feature = Features.byName.hunters
  if not (feature and feature.serverPatrol) then
    return
  end
  local route, ring = {}, HunterChopper.hunterRing
  for i = 0, 7 do
    local a = i / 8 * 2 * math.pi
    route[#route + 1] = { x = x + math.cos(a) * ring, y = y + math.sin(a) * ring }
  end
  feature:serverPatrol(server, route, count)
end

--- A wave of help: soldiers set down under it, or A-Man dropping in with
--- Hunters in his case.
local function callIn(server, wave)
  local f = sv.flight
  local aman = Features.byName["a-man"]
  if not aman then
    return
  end
  if wave.troops and aman.serverDropTroops then
    aman:serverDropTroops(server, f.x, f.y, wave.troops)
    if (wave.sets or 1) > 1 then
      sv.drops[#sv.drops + 1] = { troops = wave.troops, left = wave.sets - 1, every = wave.every, nextIn = wave.every }
    end
  end
  if wave.hunters and aman.serverVisit then
    local came = aman:serverVisit(server, f.x, f.y, function(srv, x, y)
      hunters(srv, x, y, Bosses.count(wave.hunters, srv)) -- more humans, more of them
    end)
    if not came then -- nowhere for him to land: they come anyway, under it
      hunters(server, f.x, f.y, wave.hunters)
    end
  end
end

--- Each wave once, as its health falls past the wave's mark.
local function callForHelp(server)
  local wave = HunterChopper.waves[sv.called + 1]
  while wave and sv.hp <= sv.max * wave.at do
    sv.called = sv.called + 1
    callIn(server, wave)
    if not sv then
      return
    end
    wave = HunterChopper.waves[sv.called + 1]
  end
end

--- The later sets of soldiers, each under wherever it is by then.
local function stepDrops(server, dt)
  local aman = Features.byName["a-man"]
  for i = #sv.drops, 1, -1 do
    local d = sv.drops[i]
    d.nextIn = d.nextIn - dt
    if d.nextIn <= 0 then
      d.left, d.nextIn = d.left - 1, d.every
      if aman and aman.serverDropTroops then
        aman:serverDropTroops(server, sv.flight.x, sv.flight.y, d.troops)
      end
      if d.left <= 0 then
        table.remove(sv.drops, i)
      end
    end
  end
end

function HunterChopper:serverStep(server, dt)
  if not sv then
    return
  end
  local f = sv.flight
  Flight.step(f, dt)
  local b = sv.brain
  if not sv.down then
    Brain.step(b, f, server, dt, sv.bombs)
    callForHelp(server)
    if sv then
      stepDrops(server, dt)
    end
  end
  Bombs.step(sv.bombs, server, dt)
  if f.crashed then
    crash(server)
    return
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local active = not sv.down
  local msg = Protocol.encode("HC_STATE", server.tick, ("%.0f"):format(f.x), ("%.0f"):format(f.y),
    ("%.3f"):format(f.angle), ("%.2f"):format(f.bank), ("%.0f"):format(f.altitude), ("%.3f"):format(b.aim),
    active and ("%.2f"):format(Brain.lock(b)) or 0, active and b.mode == "fire" and 1 or 0,
    active and b.mode == "run" and 1 or 0, math.ceil(sv.hp), sv.max, sv.down and 1 or 0)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- For tests.
function HunterChopper.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { x, y, angle, bank, altitude, aim, lock, firing, hp, max, down, flash } as drawn, `to` from the host
local wreck = nil -- { x, y, angle } where the last one came down, on this map
local lastTick = 0
local heardAt = 0 -- when the last HC_STATE came
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer
local time = 0
local rotor = nil -- the rotor loop, while there is a chopper

local function gone()
  cl = nil
  Bombs.clear()
  if rotor then
    rotor:stop()
    rotor = nil
  end
end

--- Off every screen at once (a map change: the clearing HC_STATE may not get through).
function HunterChopper.forgetFlight()
  gone()
end

function HunterChopper:exitGame()
  gone()
  wreck, lastTick = nil, 0
end

function HunterChopper.forgetWreck()
  wreck = nil
end

function HunterChopper:update(dt)
  time = time + dt
  Bombs.update(dt)
  if cl and love.timer.getTime() - heardAt > STALE then
    gone()
  end
  if not (cl and cl.to) then
    return
  end
  local k = math.min(1, dt * SMOOTHING)
  local to = cl.to
  if (to.x - cl.x) ^ 2 + (to.y - cl.y) ^ 2 > SNAP * SNAP then
    cl.x, cl.y = to.x, to.y
  else
    cl.x, cl.y = cl.x + (to.x - cl.x) * k, cl.y + (to.y - cl.y) * k
  end
  cl.angle = cl.angle + wrap(to.angle - cl.angle) * k
  cl.aim = cl.aim + wrap(to.aim - cl.aim) * k
  cl.bank = cl.bank + (to.bank - cl.bank) * k
  cl.altitude = cl.altitude + (to.altitude - cl.altitude) * k
  cl.lock, cl.firing, cl.down = to.lock, to.firing, to.down
  cl.flash = math.max(0, (cl.flash or 0) - dt)
  -- The rotor works harder leaning into a turn, and screams going down.
  rotor = rotor or Sounds.rotor(cl.x, cl.y)
  if rotor then
    Sounds.place(rotor, cl.x, cl.y, (cl.down and 1.25 or 1) + math.abs(cl.bank) * 0.06)
  end
end

function HunterChopper:drawBelowCars()
  if wreck then
    Render.wreck(wreck, time)
  end
  Bombs.drawBelowCars(time)
end

function HunterChopper:drawAboveCars()
  Bombs.drawAboveCars(time)
  if cl then
    Render.chopper(cl, time)
  end
end

--- The boss bar while it is up.
function HunterChopper:drawHUD()
  if cl and cl.max then
    Bar.draw({ title = "HUNTER-CHOPPER", titleColor = TITLE_COLOR, fill = BAR_FILL, hp = cl.hp, max = cl.max,
      noBreath = true })
  end
end

HunterChopper.clientMessages = {
  HC_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      gone()
      return
    end
    local to = {
      x = x, y = y, angle = tonumber(args[4]) or 0, bank = tonumber(args[5]) or 0,
      altitude = tonumber(args[6]) or Render.ALTITUDE, aim = tonumber(args[7]) or 0,
      lock = tonumber(args[8]) or 0, firing = args[9] == "1", run = args[10] == "1",
      hp = tonumber(args[11]), max = tonumber(args[12]), down = args[13] == "1",
    }
    if to.run and not (cl and cl.to and cl.to.run) then
      Sounds.play("dive", x, y) -- it has peeled off on a bombing run
    end
    if to.lock > 0 and not (cl and cl.to and cl.to.lock > 0) then
      Sounds.play("lock", x, y) -- it has just locked on to somebody
    end
    if not cl then
      cl = { x = to.x, y = to.y, angle = to.angle, bank = to.bank, altitude = to.altitude, aim = to.aim }
    end
    if cl.hp and to.hp and to.hp < cl.hp then
      cl.flash = FLASH -- hit since the last word
    end
    cl.hp, cl.max = to.hp, to.max
    cl.to = to
  end,
  HC_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      wreck = { x = x, y = y, angle = tonumber(args[3]) or 0 }
      gone()
    end
  end,
}
for kind, handler in pairs(Bombs.clientMessages) do
  HunterChopper.clientMessages[kind] = handler
end

return HunterChopper
