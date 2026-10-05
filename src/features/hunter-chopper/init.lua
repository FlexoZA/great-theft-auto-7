-- The Hunter-Chopper: the Combine's gunship-helicopter, the Outer City's
-- boss (A-Man's trail, quests' "a-man-2"). When everyone arrives in the
-- Outer City it is already up, flying round and round the square on the
-- island (flight.lua), and its gun (brain.lua) locks on to whoever it can
-- see, warns them with a beam and a whine for a second and fires a burst;
-- every so often it goes on a bombing run instead, diving over a player
-- and dropping bombs off both sides of it (bombs.lua).
-- You hear its rotor from across the city (sounds.lua). Nothing can hurt
-- it yet.
--
-- The host flies it and tells everyone where it is; every machine eases
-- what it draws towards that and draws it over everything on the ground
-- (render.lua).
--
-- Modules
--   render.lua  the chopper from above: hull, rotors, the gun, its shadow
--   flight.lua  where it flies, on the host
--   brain.lua   its brain, on the host: who it goes after, the lock, the burst, the runs
--   bombs.lua   its bombs: falling and going off on the host, their rings on every screen
--   sounds.lua  its rotor loop, the lock-on whine, the klaxon and the bombs' whistle
--
-- Messages
--   server -> all  HC_STATE <tick> [<x> <y> <angle> <bank> <altitude> <aim> <lock> <firing> <run>]
--                  (unreliable, 15 Hz; nothing after the tick: no chopper; lock 0..1 the gun
--                  locking on, firing 1 while it fires, run 1 on a bombing run)
--   and bombs.lua's HC_BOMB

local Protocol = require("src.net.protocol")
local Features = require("src.features")
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

local SYNC_EVERY = 2 -- server ticks between HC_STATE
local SMOOTHING = 10 -- per second, the easing of what is drawn
local SNAP = 300 -- px; a jump this big is a placement, not flight

local function wrap(a)
  return (a + math.pi) % (2 * math.pi) - math.pi
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == HunterChopper.map and city.map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { flight, brain, bombs, syncIn } while it is up

function HunterChopper:load()
  Sounds.load()
end

--- Everyone arrived in the Outer City: it is up and flying.
function HunterChopper:serverQuestStarted(_server, quest)
  local map = cityMap()
  if quest.id == self.questId and map and map.bossX then
    local flight = Flight.new(map.bossX, map.bossY, math.pi / 2)
    sv = { flight = flight, brain = Brain.new(flight.angle), bombs = Bombs.new(), syncIn = 0 }
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

function HunterChopper:mapChanged(_map, server)
  if server then
    stop(server)
  end
end

function HunterChopper:serverStep(server, dt)
  if not sv then
    return
  end
  local f = sv.flight
  Flight.step(f, dt)
  local b = sv.brain
  Brain.step(b, f, server, dt, sv.bombs)
  Bombs.step(sv.bombs, server, dt)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local msg = Protocol.encode("HC_STATE", server.tick, ("%.0f"):format(f.x), ("%.0f"):format(f.y),
    ("%.3f"):format(f.angle), ("%.2f"):format(f.bank), ("%.0f"):format(f.altitude), ("%.3f"):format(b.aim),
    ("%.2f"):format(Brain.lock(b)), b.mode == "fire" and 1 or 0, b.mode == "run" and 1 or 0)
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

local cl = nil -- { x, y, angle, bank, altitude, aim, lock, firing } as drawn, with `to` what the host last said
local lastTick = 0
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

function HunterChopper:exitGame()
  gone()
  lastTick = 0
end

function HunterChopper:update(dt)
  time = time + dt
  Bombs.update(dt)
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
  cl.lock, cl.firing = to.lock, to.firing
  -- The rotor works harder leaning into a turn.
  rotor = rotor or Sounds.rotor(cl.x, cl.y)
  if rotor then
    Sounds.place(rotor, cl.x, cl.y, 1 + math.abs(cl.bank) * 0.06)
  end
end

function HunterChopper:drawBelowCars()
  Bombs.drawBelowCars(time)
end

function HunterChopper:drawAboveCars()
  Bombs.drawAboveCars(time)
  if cl then
    Render.chopper(cl, time)
  end
end

HunterChopper.clientMessages = {
  HC_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      gone()
      return
    end
    local to = {
      x = x, y = y, angle = tonumber(args[4]) or 0, bank = tonumber(args[5]) or 0,
      altitude = tonumber(args[6]) or Render.ALTITUDE, aim = tonumber(args[7]) or 0,
      lock = tonumber(args[8]) or 0, firing = args[9] == "1", run = args[10] == "1",
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
    cl.to = to
  end,
}
for kind, handler in pairs(Bombs.clientMessages) do
  HunterChopper.clientMessages[kind] = handler
end

return HunterChopper
