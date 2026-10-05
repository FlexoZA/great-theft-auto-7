-- A-Man drops by in City 17 (city17.lua runs it). The first time a player
-- walks into the plaza he blinks in near one of them, snaps his briefcase
-- open, leaves a horde of sentry turrets (turrets.lua) and blinks out
-- again before anyone can draw a bead on him; `visits` times in all,
-- `gap` seconds apart. He can't be hurt here, he isn't there long enough:
-- this is a warning, the fight comes later. His turrets can be knocked
-- over as ever, and their rounds hurt players, not the Combine.
--
-- Another feature can call him in once, on any map the level runs
-- (`Cameo.serverVisit`, the a-man feature's `serverVisit`): he blinks in
-- near a player, and when his case opens it is that feature's call what
-- comes out of it (the Hunter-Chopper's Hunters); then he blinks out.
--
-- Messages
--   server -> all  C17_AMAN_IN  <x> <y> <facing>   he blinked in there
--   server -> all  C17_AMAN_CASE <x> <y>           the case opened and the turrets came out
--   server -> all  C17_AMAN_OUT <x> <y>            he blinked out from there
--   server -> all  C17_TURRETS <tick> (<id> <x> <y> <facing> <firing>)...  (unreliable, 15 Hz while any stand)
--   server -> all  C17_POP     <id> <x> <y> <facing>   a turret fell over

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Teleport = require("src.features.abilities.teleport")
local Event = require("src.features.a-man.event")
local Sounds = require("src.features.a-man.sounds")
local Turrets = require("src.features.a-man.turrets")

local Cameo = {}

-- Tuning ------------------------------------------------------------------
Cameo.zone = "plaza" -- the part of the map (city-map's `map.zones`) that brings him
Cameo.visits = 3 -- times he drops by
Cameo.firstAfter = 1.5 -- seconds after someone walks in before the first
Cameo.gap = 8 -- seconds between one visit and the next
Cameo.openAfter = 0.7 -- seconds he stands there before the case opens
Cameo.leaveAfter = 0.6 -- seconds after that before he blinks out
Cameo.distance = { 170, 280 } -- px from the player he comes for that he lands
Cameo.turrets = 5 -- out of the case each time, for one player (more humans, more: bosses/init.lua)

local SYNC_EVERY = 2 -- server ticks between C17_TURRETS
local TEAR_TIME = 0.5 -- seconds the tear he comes and goes through hangs
local TEAR_LENGTH = 70 -- px either way of him

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { left, nextIn, him, turrets, syncIn, sentEmpty }

--- `visits` false: no plaza visits of his own on this map, only called-in ones.
function Cameo.serverStart(visits)
  local left = visits == false and 0 or Cameo.visits
  sv = { left = left, nextIn = nil, him = nil, turrets = Turrets.new("C17_POP"), syncIn = 0 }
end

function Cameo.serverStop(server)
  if not sv then
    return
  end
  Turrets.clear(sv.turrets, server)
  if sv.him then
    server:broadcast(Protocol.encode("C17_AMAN_OUT", fmt(sv.him.x), fmt(sv.him.y)))
  end
  sv = nil
end

local function zoneOf(map)
  for _, z in ipairs(map.zones or {}) do
    if z.name == Cameo.zone then
      return z
    end
  end
end

--- The players in the zone, on foot or not, here and alive.
local function inZone(server, z)
  local list = {}
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local _, y = Features.bodyPose(server, p)
      if y >= z.y0 and y <= z.y1 then
        list[#list + 1] = p
      end
    end
  end
  return list
end

local function clear(x, y)
  for _, k in ipairs({ { 0, 0 }, { 12, 0 }, { -12, 0 }, { 0, 12 }, { 0, -12 } }) do
    if Features.any("blocksPoint", x + k[1], y + k[2]) then
      return false
    end
  end
  return true
end

--- He blinks in somewhere open near `p`, facing them; `opened` (optional)
--- is what his case lets out instead of turrets. False if there was nowhere.
local function arrive(server, p, opened)
  local px, py = Features.bodyPose(server, p)
  for _ = 1, 20 do
    local a = random() * 2 * math.pi
    local d = Cameo.distance[1] + random() * (Cameo.distance[2] - Cameo.distance[1])
    local x, y = px + math.cos(a) * d, py + math.sin(a) * d
    if clear(x, y) then
      local facing = math.atan2(py - y, px - x)
      sv.him = { x = x, y = y, facing = facing, t = Cameo.openAfter, opened = false, call = opened }
      server:broadcast(Protocol.encode("C17_AMAN_IN", fmt(x), fmt(y), ("%.2f"):format(facing)))
      return true
    end
  end
  return false
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local none = Turrets.standing(sv.turrets) == 0
  if none and sv.sentEmpty then
    return
  end
  sv.sentEmpty = none -- one empty list, so every screen clears the last of them
  local msg = Protocol.encode("C17_TURRETS", server.tick, unpack(Turrets.wire(sv.turrets)))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Call him in once for the player nearest (x, y): `opened(server, x, y)`
--- is called where he stands when his case opens. False if he is busy
--- (already here), there is nobody, or nowhere to land.
function Cameo.serverVisit(server, x, y, opened)
  if not sv or sv.him then
    return false
  end
  local best, bestD2 = nil, math.huge
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local px, py = Features.bodyPose(server, p)
      local d2 = (px - x) ^ 2 + (py - y) ^ 2
      if d2 < bestD2 then
        best, bestD2 = p, d2
      end
    end
  end
  return best ~= nil and arrive(server, best, opened)
end

function Cameo.serverStep(server, dt, map)
  if not sv then
    return
  end
  Turrets.step(sv.turrets, server, dt)
  sync(server)
  local him = sv.him
  if him then
    him.t = him.t - dt
    if him.t > 0 then
      return
    end
    if not him.opened then
      him.opened, him.t = true, Cameo.leaveAfter
      if him.call then
        him.call(server, him.x, him.y)
      else
        Turrets.spill(sv.turrets, him.x, him.y, Bosses.count(Cameo.turrets, server))
      end
      server:broadcast(Protocol.encode("C17_AMAN_CASE", fmt(him.x), fmt(him.y)))
    else
      server:broadcast(Protocol.encode("C17_AMAN_OUT", fmt(him.x), fmt(him.y)))
      sv.him = nil
      if not him.call then -- a called-in visit isn't one of his own
        sv.left = sv.left - 1
        sv.nextIn = sv.left > 0 and Cameo.gap or nil
      end
    end
    return
  end
  local z = map and zoneOf(map)
  if not z or sv.left <= 0 then
    return
  end
  if not sv.nextIn then
    if sv.left == Cameo.visits and inZone(server, z)[1] then
      sv.nextIn = Cameo.firstAfter -- somebody walked in: here he comes
    end
    return
  end
  sv.nextIn = sv.nextIn - dt
  if sv.nextIn > 0 then
    return
  end
  -- For somebody in the plaza; if they have all left it, he waits for one.
  local here = inZone(server, z)
  if not (here[1] and arrive(server, here[random(#here)])) then
    sv.nextIn = 1
  end
end

--- A round through (x, y): his turrets go over, he is never hit. Rounds
--- owned by nobody (the turrets' own, the Combine's) pass by.
function Cameo.serverShotAt(server, x, y, radius, by)
  return sv ~= nil and by ~= 0 and Turrets.hit(sv.turrets, server, x, y, radius)
end

function Cameo.serverFreezeArea(x, y, radius, seconds)
  if sv then
    Turrets.freeze(sv.turrets, x, y, radius, seconds)
  end
end

--- For tests.
function Cameo.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = { him = nil, tears = {}, turrets = Turrets.clientNew(), turretTick = 0 }
local time = 0

function Cameo.clear()
  cl = { him = nil, tears = {}, turrets = Turrets.clientNew(), turretTick = 0 }
end

local function tear(x, y)
  cl.tears[#cl.tears + 1] = { x = x, y = y, t = 0 }
end

function Cameo.update(dt)
  time = time + dt
  Turrets.update(cl.turrets, dt)
  for i = #cl.tears, 1, -1 do
    local t = cl.tears[i]
    t.t = t.t + dt
    if t.t > TEAR_TIME then
      table.remove(cl.tears, i)
    end
  end
  local him = cl.him
  if him then
    him.since = him.since + dt
    him.alpha = math.min(1, him.since * 5) * (0.75 + 0.25 * math.abs(math.sin(time * 18))) -- never quite here
  end
end

function Cameo.drawBelowCars()
  for _, t in ipairs(cl.tears) do
    Teleport.drawTear(t.x, t.y - TEAR_LENGTH, t.x, t.y + TEAR_LENGTH, t.t / TEAR_TIME, Event.color)
  end
end

function Cameo.drawAboveCars()
  Turrets.draw(cl.turrets, time)
  if cl.him then
    Event.drawFigure(cl.him)
  end
  love.graphics.setColor(1, 1, 1)
end

Cameo.clientMessages = {
  C17_AMAN_IN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    cl.him = { dx = x, dy = y, angle = tonumber(args[3]) or 0, stride = 0, hp = 1, max = 1, alpha = 0, since = 0 }
    tear(x, y)
    Sounds.play("appear", x, y, 1.6)
  end,
  C17_AMAN_CASE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("clasp", x, y)
      Sounds.play("turret", x, y)
    end
  end,
  C17_AMAN_OUT = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    cl.him = nil
    if x and y then
      tear(x, y)
      Sounds.play("vanish", x, y)
    end
  end,
  C17_TURRETS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= cl.turretTick then
      return
    end
    cl.turretTick = tick
    Turrets.read(cl.turrets, args, 2)
  end,
  C17_POP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id and x and y then
      Turrets.pop(cl.turrets, id, x, y, tonumber(args[4]) or 0)
      Sounds.play("pop", x, y, 0.9 + random() * 0.25)
    end
  end,
}

return Cameo
