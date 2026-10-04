-- The Hunter-Chopper: the Combine's gunship-helicopter, the Outer City's
-- boss (A-Man's trail, quests' "a-man-2"). When everyone arrives in the
-- Outer City it is already up, flying round and round the square on the
-- island (flight.lua), its gun turning after the nearest player in reach.
-- It does not shoot yet, and nothing can hurt it.
--
-- The host flies it and tells everyone where it is; every machine eases
-- what it draws towards that and draws it over everything on the ground
-- (render.lua).
--
-- Modules
--   render.lua  the chopper from above: hull, rotors, the gun, its shadow
--   flight.lua  where it flies, on the host
--
-- Messages
--   server -> all  HC_STATE <tick> [<x> <y> <angle> <bank> <altitude> <aim>]   (unreliable, 15 Hz;
--                  nothing after the tick: no chopper)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Render = require("src.features.hunter-chopper.render")
local Flight = require("src.features.hunter-chopper.flight")

local HunterChopper = {
  name = "hunter-chopper",
  priority = 120, -- in the air: over the cars and walkers (car tags 110), under the arrows (500)
}

-- Tuning ------------------------------------------------------------------
HunterChopper.questId = "a-man-2" -- the quest it is the boss of
HunterChopper.map = "outercity" -- the map it flies over
HunterChopper.sees = 900 -- px; its gun turns after the nearest player this near

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

local sv = nil -- { flight, aim, syncIn } while it is up

--- Everyone arrived in the Outer City: it is up and flying.
function HunterChopper:serverQuestStarted(_server, quest)
  local map = cityMap()
  if quest.id == self.questId and map and map.bossX then
    sv = { flight = Flight.new(map.bossX, map.bossY, math.pi / 2), syncIn = 0 }
    sv.aim = sv.flight.angle
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

--- The nearest player in reach, for the gun to turn after.
local function nearest(server, x, y)
  local best, bestD2 = nil, HunterChopper.sees ^ 2
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = (px - x) ^ 2 + (py - y) ^ 2
      if d2 < bestD2 then
        best, bestD2 = { x = px, y = py }, d2
      end
    end
  end
  return best
end

function HunterChopper:serverStep(server, dt)
  if not sv then
    return
  end
  local f = sv.flight
  Flight.step(f, dt)
  local target = nearest(server, f.x, f.y)
  local want = target and math.atan2(target.y - f.y, target.x - f.x) or f.angle
  sv.aim = sv.aim + wrap(want - sv.aim) * math.min(1, dt * 4)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local msg = Protocol.encode("HC_STATE", server.tick, ("%.0f"):format(f.x), ("%.0f"):format(f.y),
    ("%.3f"):format(f.angle), ("%.2f"):format(f.bank), ("%.0f"):format(f.altitude), ("%.3f"):format(sv.aim))
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

local cl = nil -- { x, y, angle, bank, altitude, aim } as drawn, with `to` what the host last said
local lastTick = 0
local time = 0

function HunterChopper:exitGame()
  cl, lastTick = nil, 0
end

function HunterChopper:update(dt)
  time = time + dt
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
end

function HunterChopper:drawAboveCars()
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
      cl = nil
      return
    end
    local to = {
      x = x, y = y, angle = tonumber(args[4]) or 0, bank = tonumber(args[5]) or 0,
      altitude = tonumber(args[6]) or Render.ALTITUDE, aim = tonumber(args[7]) or 0,
    }
    if not cl then
      cl = { x = to.x, y = to.y, angle = to.angle, bank = to.bank, altitude = to.altitude, aim = to.aim }
    end
    cl.to = to
  end,
}

return HunterChopper
