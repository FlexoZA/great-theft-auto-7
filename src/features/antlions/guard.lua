-- The Antlion Guard: the Coast's boss (quests' "a-man-coast"). init.lua
-- passes its hooks on to this module.
--
-- When everyone in the Coast's final section has fallen (`map.finale`:
-- every antlion of the swarms buried there and every Combine soldier
-- inside it, the a-man feature's `serverTroopsIn`), the sand heaves at
-- `map.bossX, bossY` and the Guard digs its way up. What it does is its
-- brain's (guard_brain.lua): it hunts the nearest player, swipes up close,
-- paws the sand and charges, reels when it runs into something, rears up
-- and screams down a cone, a sound wave that hurts and blows back everyone
-- in it, and goes for a medkit when badly hurt. It tires like every boss
-- (bosses/stamina.lua): running and charging spend its breath, and it has
-- none for a charge or a scream while it is winded.
--
-- `health` for one human, more with more (Bosses.health), on the boss bar.
-- Down, it spills koins, raises `serverKill` with kind "boss" and finishes
-- the level (quests' `serverComplete`): the EXIT star comes up by it.
--
-- Messages (init.lua registers them)
--   server -> all  ANT_GUARD <tick> [<x> <y> <facing> <hp> <max> <mode> <aim> <stamina> <winded>]
--                  (unreliable, 15 Hz; nothing after the tick: no Guard; mode 1 coming up, 2 about,
--                  3 swipe, 4 paw, 5 charge, 6 rear, 7 scream, 8 stunned)
--   server -> all  ANT_GUARD_SCREAM <x> <y> <angle> <range> <half> [<playerId>]...   it screamed; these were caught
--   server -> all  ANT_GUARD_DOWN <x> <y> <angle>   it fell there

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Brain = require("src.features.antlions.guard_brain")
local Render = require("src.features.antlions.guard_render")
local Sounds = require("src.features.antlions.sounds")

local Guard = {}

-- Tuning ------------------------------------------------------------------
Guard.questId = "a-man-coast" -- the quest it is the boss of
Guard.health = 2400 -- for one human (more humans, more: bosses/init.lua)
Guard.radius = Render.RADIUS
Guard.breath = { -- its stamina (bosses/stamina.lua has the rule and the defaults)
  max = 100,
  drain = 14, -- ~7 s of running: a little longer than a player's sprint
  regen = 14,
  regenDelay = 1,
  recovered = 50,
  breath = 45, -- held before a charge or a scream
}
Guard.rise = 2.4 -- seconds digging its way up
Guard.sight = 1600 -- px it goes after somebody from
Guard.runSpeed = 150 -- px/s while it has the breath
Guard.prowlSpeed = 90 -- px/s closing in on somebody near: no breath spent
Guard.walkSpeed = 42 -- px/s winded: about a player's walk
Guard.turn = 2.4 -- rad/s it turns
Guard.swipeReach = 62 -- px from its middle to whoever it swipes at
Guard.swipeDamage = 22
Guard.swipeShove = 110 -- px it knocks them back
Guard.swipeHit = 0.32 -- seconds into a swipe that it lands
Guard.swipeTime = 0.6
Guard.swipeEvery = 0.9 -- seconds after one before the next
Guard.chargeNear, Guard.chargeFar = 200, 650 -- px off it may charge from
Guard.chargeCost = 30 -- breath a charge takes
Guard.chargeChance = 0.8 -- per second, while it may
Guard.pawTime = 0.9 -- seconds of pawing the sand before it goes: the warning
Guard.chargeSpeed = 440 -- px/s
Guard.chargeTime = 1.4 -- seconds at most
Guard.chargeDamage = 35
Guard.chargeShove = 240 -- px whoever it hits flies
Guard.chargeEvery = 5 -- seconds after one before the next
Guard.stunTime = 2.2 -- seconds it reels after running into something
Guard.screamRange = 520 -- px down the cone
Guard.screamHalf = math.rad(32) -- either side of its line
Guard.screamCost = 35 -- breath a scream takes
Guard.screamChance = 0.7 -- per second, while it may
Guard.rearTime = 1.0 -- seconds rearing up, the cone showing: the time to get out of it
Guard.screamDamage = 30 -- right in front of it; less towards the far end
Guard.screamShove = 320 -- px it blows them back, right in front of it
Guard.screamRecover = 0.8 -- seconds it stands after
Guard.screamEvery = 7 -- seconds after one before the next
Guard.drops = 60 -- koins it spills

local SYNC_EVERY = 2
local SMOOTHING = 10
local SNAP = 300
local STEP = 60 -- px walked in one full step cycle, for the legs
local HURT = 0.15
local WAVE_TIME = 0.7 -- seconds a scream's wave takes to roll out
local DEAD_TIME = 40 -- seconds its body lies there
local TITLE_COLOR = { 0.95, 0.80, 0.45 }
local BAR_FILL = { 0.80, 0.55, 0.20 }
local MODES = { emerge = 1, hunt = 2, heal = 2, dodge = 2, swipe = 3, paw = 4, charge = 5, rear = 6, scream = 7,
  stunned = 8 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { g, syncIn, time } while it is up; `done` once it has been beaten

function Guard.serverReset()
  sv = nil
end

--- Is everyone in the final section down? `brain` the antlions'.
local function sectionClear(server, map, brain)
  local f = map.finale
  local function inside(x, y)
    return x >= f.x and x <= f.x + f.w and y >= f.y and y <= f.y + f.h
  end
  for _, a in ipairs(brain.list) do
    if a.swarm.finale then
      return false
    end
  end
  local aman = Features.byName["a-man"]
  if aman and aman.serverTroopsIn and aman:serverTroopsIn(server, f) > 0 then
    return false
  end
  -- And somebody is there to see it.
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and inside(Features.bodyPose(server, p)) then
      return true
    end
  end
  return false
end

--- Clear ground for its whole body nearest (x, y).
local function roomAt(x, y)
  local r = Guard.radius
  local function clear(cx, cy)
    for _, k in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r }, { r * 0.7, r * 0.7 },
      { -r * 0.7, r * 0.7 }, { r * 0.7, -r * 0.7 }, { -r * 0.7, -r * 0.7 } }) do
      if Features.any("blocksPoint", cx + k[1], cy + k[2]) then
        return false
      end
    end
    return true
  end
  for d = 0, 300, 20 do
    for k = 0, 11 do
      local a = k / 12 * 2 * math.pi
      local cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
      if clear(cx, cy) then
        return cx, cy
      end
      if d == 0 then
        break
      end
    end
  end
  return x, y
end

--- The Guard digs its way up at (x, y), or the nearest place it fits.
local function spawn(server, x, y)
  x, y = roomAt(x, y)
  local max = Bosses.health(Guard.health, server)
  sv = {
    time = 0, syncIn = 0,
    g = {
      x = x, y = y, facing = math.pi / 2, hp = max, max = max, mode = "emerge", t = 0, frozen = 0,
      breath = Stamina.new(Guard.breath), swipeIn = 0, chargeIn = 2, screamIn = 3, aim = math.pi / 2,
      side = love.math.random() < 0.5 and -1 or 1,
    },
  }
end

--- Every host tick from init.lua: wait for the section to clear, then fight.
function Guard.serverStep(server, dt, map, brain)
  if not sv then
    if map and map.finale and brain and sectionClear(server, map, brain) then
      spawn(server, map.bossX, map.bossY)
    end
    return
  end
  if sv.done then
    return
  end
  sv.time = sv.time + dt
  local g = sv.g
  local what, caught = Brain.think(Guard, g, server, dt, sv.time)
  if what == "scream" then
    local parts = { fmt(g.x), fmt(g.y), ("%.3f"):format(g.aim), Guard.screamRange, ("%.3f"):format(Guard.screamHalf) }
    for _, id in ipairs(caught) do
      parts[#parts + 1] = id
    end
    server:broadcast(Protocol.encode("ANT_GUARD_SCREAM", unpack(parts)))
  end
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local stamina, winded = g.breath:wire()
  local msg = Protocol.encode("ANT_GUARD", server.tick, ("%.0f"):format(g.x), ("%.0f"):format(g.y),
    ("%.3f"):format(g.facing), math.ceil(g.hp), g.max, MODES[g.mode] or 2, ("%.3f"):format(g.aim), stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- It falls: koins, the kill, the level done.
local function down(server, by, angle)
  local g = sv.g
  sv.done = true
  server:broadcast(Protocol.encode("ANT_GUARD", server.tick))
  server:broadcast(Protocol.encode("ANT_GUARD_DOWN", fmt(g.x), fmt(g.y), ("%.3f"):format(g.facing)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, g.x, g.y, Guard.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = g.x, y = g.y, by = by, angle = angle })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, Guard.questId, g.x, g.y)
  end
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the Combine's) pass by; a blast's share, which carries nothing, takes 20.
function Guard.serverShotAt(server, x, y, radius, by, angle, damage)
  local g = sv and not sv.done and sv.g
  if not g or by == 0 or (x - g.x) ^ 2 + (y - g.y) ^ 2 > (radius + Guard.radius) ^ 2 then
    return false
  end
  g.hp = g.hp - (damage or 20)
  if g.hp <= 0 then
    g.hp = 0
    down(server, by, angle)
  end
  return true
end

function Guard.serverFreezeArea(x, y, radius, seconds)
  local g = sv and not sv.done and sv.g
  if g and (g.x - x) ^ 2 + (g.y - y) ^ 2 <= (radius + Guard.radius) ^ 2 then
    g.frozen = math.max(g.frozen, seconds * 0.5) -- big: it shakes a freeze off in half the time
  end
end

function Guard.serverPanicArea(x, y, radius)
  local g = sv and not sv.done and sv.g
  if g and (g.x - x) ^ 2 + (g.y - y) ^ 2 <= (radius + Guard.radius) ^ 2 then
    g.panic = { x = x, y = y, left = 0.8 }
  end
end

--- For tests.
function Guard.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { x, y, dx, dy, facing, hp, max, mode, t, aim, stamina, winded, cycle, stride, hurt }
local waves = {} -- { x, y, angle, range, half, t }
local body = nil -- { x, y, facing, t } where it fell
local lastTick = 0
local clock = 0
local heardAt = 0 -- when the last ANT_GUARD came
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer

function Guard.clear()
  cl, waves, body, lastTick = nil, {}, nil, 0
end

function Guard.update(dt)
  clock = clock + dt
  if cl and love.timer.getTime() - heardAt > STALE then
    cl = nil
  end
  for i = #waves, 1, -1 do
    waves[i].t = waves[i].t + dt
    if waves[i].t > WAVE_TIME then
      table.remove(waves, i)
    end
  end
  if body then
    body.t = body.t + dt
    if body.t > DEAD_TIME then
      body = nil
    end
  end
  if not cl then
    return
  end
  cl.t = cl.t + dt
  local k = math.min(1, dt * SMOOTHING)
  local ex, ey = cl.x - cl.dx, cl.y - cl.dy
  local moved = math.sqrt(ex * ex + ey * ey) * k
  if ex * ex + ey * ey > SNAP * SNAP then
    cl.dx, cl.dy = cl.x, cl.y
  else
    cl.dx, cl.dy = cl.dx + ex * k, cl.dy + ey * k
    cl.cycle = cl.cycle + moved / STEP
  end
  cl.stride = cl.stride + (math.min(1, moved / math.max(dt, 1e-6) / 80) - cl.stride) * math.min(1, dt * 6)
  cl.hurt = math.max(0, cl.hurt - dt)
end

function Guard.drawBelowCars()
  if body then
    Render.draw(body.x, body.y, body.facing, { dead = true, alpha = math.min(1, (DEAD_TIME - body.t) / 4) }, clock)
  end
  if cl and cl.mode == MODES.rear then -- where the scream will go
    Render.cone(cl.dx, cl.dy, cl.aim, Guard.screamRange, Guard.screamHalf, math.min(1, cl.t / Guard.rearTime))
  end
  for _, w in ipairs(waves) do
    Render.cone(w.x, w.y, w.angle, w.range, w.half, 1, w.t / WAVE_TIME)
  end
end

function Guard.drawAboveCars()
  if not cl then
    return
  end
  local m = cl.mode
  Render.draw(cl.dx, cl.dy, cl.facing, {
    cycle = cl.cycle, stride = cl.stride, hurt = cl.hurt / HURT * 0.6,
    burrow = m == MODES.emerge and 1 - math.min(1, cl.t / Guard.rise) or 0,
    swipe = m == MODES.swipe and math.min(1, cl.t / Guard.swipeTime) or nil,
    paw = m == MODES.paw, charge = m == MODES.charge, rear = m == MODES.rear, scream = m == MODES.scream,
    stunned = m == MODES.stunned,
  }, clock)
end

function Guard.drawHUD()
  if cl and cl.max and cl.mode ~= MODES.emerge then
    Bar.draw({ title = "ANTLION GUARD", titleColor = TITLE_COLOR, fill = BAR_FILL, hp = cl.hp, max = cl.max,
      stamina = cl.stamina, staminaMax = Guard.breath.max, winded = cl.winded })
  end
end

Guard.clientMessages = {
  ANT_GUARD = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      cl = nil
      return
    end
    local mode = tonumber(args[7]) or MODES.hunt
    if not cl then
      cl = { dx = x, dy = y, cycle = 0, stride = 0, hurt = 0, t = 0, mode = mode }
      if mode == MODES.emerge then
        Sounds.play("rumble", x, y)
      end
    elseif cl.mode ~= mode then
      cl.mode, cl.t = mode, 0
      if mode == MODES.paw or mode == MODES.rear then
        Sounds.play("growl", x, y, mode == MODES.rear and 1.15 or 0.9)
      elseif mode == MODES.charge then
        Sounds.play("buzz", x, y, 0.5)
      elseif mode == MODES.swipe then
        Sounds.play("bite", x, y, 0.55)
      elseif mode == MODES.stunned then
        Sounds.play("thud", x, y)
      end
    end
    local hp = tonumber(args[5])
    if cl.hp and hp and hp < cl.hp then
      cl.hurt = HURT
    end
    cl.x, cl.y, cl.facing, cl.hp, cl.max = x, y, tonumber(args[4]) or 0, hp, tonumber(args[6])
    cl.aim = tonumber(args[8]) or cl.facing
    cl.stamina, cl.winded = Stamina.read(args, 9)
  end,
  ANT_GUARD_SCREAM = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      waves[#waves + 1] = { x = x, y = y, angle = tonumber(args[3]) or 0, range = tonumber(args[4]) or 500,
        half = tonumber(args[5]) or 0.5, t = 0 }
      Sounds.play("scream", x, y)
    end
  end,
  ANT_GUARD_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      body = { x = x, y = y, facing = tonumber(args[3]) or 0, t = 0 }
      cl = nil
      Sounds.play("rumble", x, y, 0.7)
    end
  end,
}

return Guard
