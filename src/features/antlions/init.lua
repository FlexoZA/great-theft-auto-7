-- Antlions: the Coast's insects out of the sand, after Half-Life's. Not a
-- ranged enemy: they come in swarms, burst up out of the sand when a
-- player comes near, run you down and bite.
--
-- Any map that marks `map.swarms` ({ x, y, r, count }: the Coast does)
-- gets them buried there when everyone arrives on a quest: `count` to a
-- swarm for one human, more with more (Bosses.count). What each does is
-- its brain's (brain.lua): buried, coming up, running, biting, leaping,
-- going back under when there is nobody left to go after. A quest's end or
-- a map change takes them all away.
--
-- They take whatever a round carries (`Brain.HEALTH`, 36: two pistol
-- rounds), and rounds owned by nobody (the Combine's) pass by them, so the
-- bunkers' guns don't thin them out for you. One down spills a koin, now
-- and then a pickup, and lies dead on the sand on every screen for a while.
--
-- The host owns them; clients hear about the ones out of the sand at
-- 15 Hz (the buried ones are never sent: nobody knows they are there).
--
-- Messages
--   server -> all  ANT_STATE <tick> (<id> <x> <y> <facing> <hp> <mode>)...  (unreliable, 15 Hz;
--                  mode 1 coming up, 2 running, 3 biting, 4 in the air, 5 going under)
--   server -> all  ANT_DOWN  <id> <x> <y> <angle>   one died there
--
-- Modules
--   brain.lua    what each one does, on the host
--   render.lua   one drawn from above, walking, biting, in the air, burrowing and dead
--   sounds.lua   their noises: coming up, the chitter, the bite, the buzz of a leap

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Brain = require("src.features.antlions.brain")
local Render = require("src.features.antlions.render")
local Sounds = require("src.features.antlions.sounds")

local Antlions = {
  name = "antlions",
}

-- Tuning ------------------------------------------------------------------
Antlions.drops = 1 -- koins one spills
Antlions.pickupChance = 0.25 -- of the pickups feature's usual chance of an enemy's drop: there are a lot of them

local SYNC_EVERY = 2 -- server ticks between ANT_STATE
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes under, so every screen clears
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
local STEP = 26 -- px run in one full step cycle, for the legs
local HURT = 0.15 -- seconds one flashes white after a hit
local DEAD_TIME = 12 -- seconds a dead one lies on the sand
local DEAD_FADE = 3 -- the last of them fading out
local CHITTER_EVERY = { 1.5, 4 } -- seconds between one running one's chitters (min, max)
local MODES = { rising = 1, run = 2, bite = 3, air = 4, sinking = 5 }

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

--- Everyone arrived on a quest: a swarm buried at each of the map's spots.
function Antlions:serverQuestStarted(server)
  local map = cityMap()
  sv = nil
  if not (map and map.swarms) then
    return
  end
  sv = { brain = Brain.new(), syncIn = 0, emptySends = 0 }
  for _, s in ipairs(map.swarms) do
    sv.brain:bury(s.x, s.y, s.r, Bosses.count(s.count, server))
  end
end

local function clear(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("ANT_STATE", server.tick)) -- an empty list clears every screen
  end
end

function Antlions:serverQuestEnded(server)
  clear(server)
end

function Antlions:mapChanged(_map, server)
  if server then
    clear(server)
  end
end

function Antlions:serverStart()
  sv = nil
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, a in ipairs(sv.brain.list) do
    if Brain.above(a) then
      parts[#parts + 1] = a.id
      parts[#parts + 1] = ("%.0f"):format(a.x)
      parts[#parts + 1] = ("%.0f"):format(a.y)
      parts[#parts + 1] = ("%.2f"):format(a.facing)
      parts[#parts + 1] = ("%.0f"):format(math.max(0, a.hp))
      parts[#parts + 1] = MODES[a.mode]
    end
  end
  if #parts == 1 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local msg = Protocol.encode("ANT_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Antlions:serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  sync(server)
end

--- One down: its body on every screen, a koin, now and then a pickup.
local function down(server, a, by, angle)
  server:broadcast(Protocol.encode("ANT_DOWN", a.id, fmt(a.x), fmt(a.y), ("%.2f"):format(a.facing)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, a.x, a.y, Antlions.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy and love.math.random() < Antlions.pickupChance then
    pickups:serverDropEnemy(server, a.x, a.y)
  end
  Features.call("serverKill", server, { kind = "antlion", x = a.x, y = a.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Rounds owned by
--- nobody (the Combine's) pass by; a blast, which carries nothing, takes 20 a time.
function Antlions:serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  local a, i = sv.brain:at(x, y, radius)
  if not a then
    return false
  end
  if sv.brain:hurt(a, i, damage or 20, by) then
    down(server, a, by, angle)
  end
  return true
end

function Antlions:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Antlions:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius)
  end
end

--- The host's antlions, for tests.
function Antlions.state()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, mode, t, cycle, stride, hurt, chitterIn }
local dead = {} -- { x, y, facing, t }
local lastTick = 0
local clock = 0

function Antlions:load()
  Sounds.load()
end

function Antlions:exitGame()
  shown, dead, lastTick = {}, {}, 0
end

function Antlions:update(dt)
  clock = clock + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, a in pairs(shown) do
    a.t = a.t + dt
    local ex, ey = a.x - a.dx, a.y - a.dy
    local moved = math.sqrt(ex * ex + ey * ey) * k
    if ex * ex + ey * ey > SNAP * SNAP then
      a.dx, a.dy = a.x, a.y
    else
      a.dx, a.dy = a.dx + ex * k, a.dy + ey * k
      a.cycle = a.cycle + moved / STEP
    end
    local speed = moved / math.max(dt, 1e-6)
    a.stride = a.stride + (math.min(1, speed / 60) - a.stride) * math.min(1, dt * 8)
    a.hurt = math.max(0, a.hurt - dt)
    if a.mode == MODES.run then
      a.chitterIn = a.chitterIn - dt
      if a.chitterIn <= 0 then
        a.chitterIn = CHITTER_EVERY[1] + love.math.random() * (CHITTER_EVERY[2] - CHITTER_EVERY[1])
        Sounds.play("chitter", a.dx, a.dy, 0.85 + love.math.random() * 0.3)
      end
    end
  end
  for i = #dead, 1, -1 do
    dead[i].t = dead[i].t + dt
    if dead[i].t > DEAD_TIME then
      table.remove(dead, i)
    end
  end
end

--- The dead, on the sand under everything moving.
function Antlions:drawBelowCars()
  for _, d in ipairs(dead) do
    local alpha = math.min(1, (DEAD_TIME - d.t) / DEAD_FADE)
    Render.draw(d.x, d.y, d.facing, { dead = true, alpha = alpha }, clock)
  end
end

--- How far through what it is doing one is, as the model wants it.
local function pose(a)
  local p = { cycle = a.cycle, stride = a.stride, hurt = a.hurt / HURT * 0.7 }
  if a.mode == MODES.rising then
    p.burrow = 1 - math.min(1, a.t / Brain.RISE)
  elseif a.mode == MODES.sinking then
    p.burrow = math.min(1, a.t / Brain.SINK)
  elseif a.mode == MODES.bite then
    p.bite = math.min(1, a.t / Brain.BITE_TIME)
  elseif a.mode == MODES.air then
    p.air = math.sin(math.min(1, a.t / Brain.LEAP_TIME) * math.pi)
  end
  return p
end

function Antlions:drawAboveCars()
  -- The ones in the air over the rest.
  for pass = 1, 2 do
    for _, a in pairs(shown) do
      if (a.mode == MODES.air) == (pass == 2) then
        Render.draw(a.dx, a.dy, a.facing, pose(a), clock)
        if a.hp < Brain.HEALTH and a.mode ~= MODES.rising then -- a bar under it once it is hurt
          local bw, f = 22, math.max(0, a.hp / Brain.HEALTH)
          love.graphics.setColor(0, 0, 0, 0.6)
          love.graphics.rectangle("fill", a.dx - bw / 2 - 1, a.dy + Render.RADIUS + 5, bw + 2, 4)
          love.graphics.setColor(1 - f, f, 0.2)
          love.graphics.rectangle("fill", a.dx - bw / 2, a.dy + Render.RADIUS + 6, bw * f, 2)
        end
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Antlions.clientMessages = {
  ANT_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      local mode = tonumber(args[i + 5])
      if id and x and y and mode then
        local a = shown[id]
        if not a then
          a = { dx = x, dy = y, x = x, y = y, cycle = love.math.random(), stride = 0, hurt = 0, hp = Brain.HEALTH,
            mode = mode, t = 0, chitterIn = love.math.random() * CHITTER_EVERY[2] }
          shown[id] = a
          if mode == MODES.rising then
            Sounds.play("emerge", x, y, 0.85 + love.math.random() * 0.3)
          end
        elseif a.mode ~= mode then
          a.mode, a.t = mode, 0
          if mode == MODES.bite then
            Sounds.play("bite", x, y, 0.9 + love.math.random() * 0.25)
          elseif mode == MODES.air then
            Sounds.play("buzz", x, y, 0.9 + love.math.random() * 0.2)
          elseif mode == MODES.sinking then
            Sounds.play("emerge", x, y, 1.2)
          end
        end
        a.x, a.y = x, y
        a.facing = tonumber(args[i + 3]) or a.facing or 0
        local hp = tonumber(args[i + 4]) or a.hp
        if hp < a.hp then
          a.hurt = HURT
        end
        a.hp = hp
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil -- gone under (or died: ANT_DOWN says so)
      end
    end
  end,
  ANT_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y = tonumber(args[2]), tonumber(args[3])
    local a = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      dead[#dead + 1] = { x = a and a.dx or x, y = a and a.dy or y, facing = tonumber(args[4]) or 0, t = 0 }
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 1.3)
      end
    end
  end,
}

--- The footsteps feature's hook: who of mine is walking about, and where.
function Antlions:footstepWalkers()
  local list = {}
  for id, a in pairs(shown) do
    if a.mode == MODES.run or a.mode == MODES.bite then
      list[#list + 1] = { key = "ant" .. id, x = a.dx, y = a.dy, size = "claw" }
    end
  end
  return list
end

return Antlions
