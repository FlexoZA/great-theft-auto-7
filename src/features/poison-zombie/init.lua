-- The Poison Zombie: the Winding Road's boss (quests' "a-man-road"), after
-- Half-Life 2's. A man swollen and hunched under a poison headcrab, with
-- more of them riding on his back, that he throws.
--
-- He waits on the pass at the top of the road (`map.bossX, bossY`, city-map's
-- road.lua) until somebody comes up over the last bridge, howls, and comes
-- for them. What he does is his brain's (brain.lua): he shuffles after the
-- nearest player, lurches when they are far off, rakes them with his claws
-- up close, and from further off reaches back for a crab and throws it at
-- them. A new crab grows on his back every so often. He tires like every
-- boss (bosses/stamina.lua): lurching and throwing spend his breath. Badly
-- hurt, he goes for a medkit; he dodges what players drop on him.
--
-- The crabs (crabs.lua) crawl after whoever is nearest and leap at them;
-- a bite is `Crabs.BITE` poison damage, and poison leaves you poisoned for
-- a while (the damage feature's status, like a bleed: a medkit cures it).
-- They leap at cars too and scratch them (`Crabs.SCRATCH`), and a car
-- running one over squashes it. `Crabs.HEALTH` each; one down spills a koin.
--
-- He is solid to cars: one that drives into him bounces off, and at speed
-- (`ramMinSpeed`) it hurts him (`ramScale` per px/s) and the car (`ramDamageToCar`).
--
-- `health` for one human, more with more (Bosses.health), on the boss bar.
-- Down, he spills koins, raises `serverKill` with kind "boss" and finishes
-- the level (quests' `serverComplete`): the EXIT star comes up by him. The
-- Combine's rounds (owned by nobody) pass by him and his crabs.
--
-- Messages
--   server -> all     PZM_BOSS <tick> [<x> <y> <facing> <hp> <max> <mode> <crabs> <stamina> <winded>]
--                     (unreliable, 15 Hz; nothing after the tick: no zombie; mode 1 waiting,
--                     2 howling, 3 about, 4 throwing, 5 swiping)
--   server -> all     PZM_CRABS <tick> (<id> <x> <y> <facing> <hp> <mode> <air>)...  (unreliable, 15 Hz;
--                     mode 1 thrown, 2 crawling, 3 leaping, 4 resting; air 0..1 through a flight)
--   server -> all     PZM_CRAB_DOWN <id> <x> <y> <facing>   one died there
--   server -> all     PZM_BITE <x> <y>                      a bite went home there
--   server -> all     PZM_DOWN <x> <y> <facing>             he fell there
--
-- Modules
--   brain.lua    what he does, on the host
--   crabs.lua    what the crabs he throws do, on the host
--   render.lua   him and a crab drawn from above
--   sounds.lua   his breathing, his howl, the crabs' rattle and bite

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Brain = require("src.features.poison-zombie.brain")
local Crabs = require("src.features.poison-zombie.crabs")
local Car = require("src.car")
local Render = require("src.features.poison-zombie.render")
local Sounds = require("src.features.poison-zombie.sounds")

local Zombie = {
  name = "poison-zombie",
}

-- Tuning ------------------------------------------------------------------
Zombie.questId = "a-man-road" -- the quest he is the boss of
Zombie.health = 1800 -- for one human (more humans, more: bosses/init.lua)
Zombie.radius = Render.RADIUS
Zombie.breath = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  max = 100,
  drain = 15, -- ~6.5 s of lurching
  regen = 12,
  regenDelay = 1,
  recovered = 50,
  breath = 30, -- held before a throw
}
Zombie.wake = 750 -- px off somebody he can see wakes him
Zombie.howlTime = 1.6 -- seconds he howls before he comes
Zombie.sight = 1400 -- px he goes after somebody from
Zombie.leash = 1900 -- px from the pass he will go, at most
Zombie.shuffleSpeed = 58 -- px/s: a little over a player's walk
Zombie.lurchSpeed = 115 -- px/s with the breath for it: slower than a sprint
Zombie.walkSpeed = 40 -- px/s winded
Zombie.lurchFrom = 320 -- px off somebody before he lurches
Zombie.turn = 2.2 -- rad/s he turns
Zombie.swipeReach = 52 -- px from his middle to whoever he claws
Zombie.carReach = 18 -- px more to a car's middle: its side is further out than a man
Zombie.swipeDamage = 20 -- melee: they bleed too
Zombie.swipeHit = 0.4 -- seconds into a swipe that it lands
Zombie.swipeTime = 0.75
Zombie.swipeEvery = 0.9 -- seconds after one before the next
Zombie.crabs = 3 -- on his back when he is whole
Zombie.regrow = 9 -- seconds to grow another while he has fewer
Zombie.maxOut = 4 -- crabs about at once for one human (more with more), before he throws another
Zombie.throwNear, Zombie.throwFar = 120, 640 -- px off somebody he throws from
Zombie.throwCost = 18 -- breath a throw takes
Zombie.throwChance = 1.2 -- per second, while he may
Zombie.throwRelease = 0.6 -- seconds into a throw that the crab goes (render: the reach ends at 0.55)
Zombie.throwTime = 1.0
Zombie.throwEvery = 2.2 -- seconds after one before the next
Zombie.throwSpread = 40 -- px off where they stood that a crab may land
Zombie.ramMinSpeed = 60 -- px/s; slower than this a car just stops against him
Zombie.ramScale = 0.12 -- hp he loses per px/s of a car that hits him
Zombie.ramDamageToCar = 15 -- hp the car loses hitting him
Zombie.drops = 50 -- koins he spills
Zombie.crabDrops = 1 -- koins a crab spills

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 10
local CRAB_SMOOTHING = 16
local SNAP = 300
local STEP = 34 -- px shuffled in one full step cycle (two steps)
local CRAB_STEP = 18 -- px a crab crawls in one cycle of its legs
local HURT = 0.15
local DEAD_TIME = 40 -- seconds his body lies there
local CRAB_DEAD_TIME = 12
local BREATH_EVERY = 1.8 -- seconds between his breaths
local CHITTER_EVERY = { 1.2, 3 }
local TITLE_COLOR = { 0.70, 0.85, 0.55 }
local BAR_FILL = { 0.42, 0.62, 0.28 }
local MODES = { wait = 1, howl = 2, hunt = 3, heal = 3, dodge = 3, throw = 4, swipe = 5 }
local CRAB_MODES = { fly = 1, crawl = 2, idle = 2, leap = 3, rest = 4 }

local function fmt(v)
  return ("%.1f"):format(v)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

-- Server --------------------------------------------------------------------

local sv = nil -- { z, crabs, maxOut, syncIn, emptySends, time, done }

-- On every machine (the Client section), declared here for mapChanged.
local cl = nil -- him: { x, y, dx, dy, facing, hp, max, mode, crabs, stamina, winded, t, cycle, stride, hurt }
local shown = {} -- crab id -> { x, y, dx, dy, facing, hp, mode, air, t, cycle, hurt, chitterIn }
local bodies = {} -- { x, y, facing, t, crab }

--- Clear ground for his whole body nearest (x, y).
local function roomAt(x, y)
  local r = Zombie.radius
  for d = 0, 300, 20 do
    for k = 0, 11 do
      local a = k / 12 * 2 * math.pi
      local cx, cy = x + math.cos(a) * d, y + math.sin(a) * d
      local clear = true
      for _, o in ipairs({ { 0, 0 }, { r, 0 }, { -r, 0 }, { 0, r }, { 0, -r } }) do
        if Features.any("blocksPoint", cx + o[1], cy + o[2]) then
          clear = false
          break
        end
      end
      if clear then
        return cx, cy
      end
      if d == 0 then
        break
      end
    end
  end
  return x, y
end

function Zombie:serverQuestStarted(server, quest)
  local map = cityMap()
  sv = nil
  if not (quest.id == Zombie.questId and map and map.bossX) then
    return
  end
  local x, y = roomAt(map.bossX, map.bossY)
  local max = Bosses.health(Zombie.health, server)
  sv = {
    time = 0, syncIn = 0, emptySends = 0, crabs = Crabs.new(), maxOut = Bosses.count(Zombie.maxOut, server),
    z = {
      x = x, y = y, homeX = x, homeY = y, facing = math.pi / 2, hp = max, max = max, mode = "wait", t = 0,
      frozen = 0, breath = Stamina.new(Zombie.breath), swipeIn = 0, throwIn = 1, crabs = Zombie.crabs,
      regrowIn = Zombie.regrow, side = love.math.random() < 0.5 and -1 or 1, rammed = {},
    },
  }
end

local function clear(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("PZM_BOSS", server.tick))
    server:broadcast(Protocol.encode("PZM_CRABS", server.tick))
  end
end

function Zombie:serverQuestEnded(server)
  clear(server)
end

function Zombie:mapChanged(_map, server)
  if server then
    clear(server)
  end
  -- Off every screen at once, the host's too: the bodies belong to the map
  -- they fell on, and the clearing messages may carry a tick already seen.
  cl, shown, bodies = nil, {}, {}
end

function Zombie:serverStart()
  sv = nil
end

--- He falls: koins, the kill, the level done.
local function down(server, by, angle, cause)
  local z = sv.z
  sv.done = true
  server:broadcast(Protocol.encode("PZM_BOSS", server.tick))
  server:broadcast(Protocol.encode("PZM_DOWN", fmt(z.x), fmt(z.y), ("%.3f"):format(z.facing)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, z.x, z.y, Zombie.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = z.x, y = z.y, by = by, angle = angle, cause = cause })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, Zombie.questId, z.x, z.y)
  end
end

--- A crab dies: its body on every screen, and a koin if a player did it.
local function crabDown(server, c, by, angle, cause)
  c.dead = true
  server:broadcast(Protocol.encode("PZM_CRAB_DOWN", c.id, fmt(c.x), fmt(c.y), ("%.2f"):format(c.facing)))
  if by and by ~= 0 then
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, c.x, c.y, Zombie.crabDrops)
    end
    Features.call("serverKill", server, { kind = "headcrab", x = c.x, y = c.y, by = by, angle = angle, cause = cause })
  end
end

--- Cars driving into him: he stands, the car stops against him and
--- bounces off; at speed it hurts him and the car.
local function rams(server, z, dt)
  for id, t in pairs(z.rammed) do
    z.rammed[id] = t - dt
  end
  for id, p in pairs(server.players) do
    local car = p.vehicle
    if car and Features.present(p) and Car.hitTest(car, z.x, z.y, Zombie.radius) then
      local speed = math.abs(car.speed)
      local away = math.atan2(car.y - z.y, car.x - z.x)
      -- Out of him, the way it came from: he does not budge.
      for _ = 1, 20 do
        if not Car.hitTest(car, z.x, z.y, Zombie.radius) then
          break
        end
        car.x, car.y = car.x + math.cos(away) * 2, car.y + math.sin(away) * 2
      end
      if speed >= Zombie.ramMinSpeed and (z.rammed[id] or 0) <= 0 then
        z.rammed[id] = 0.6
        local weapons = Features.byName.weapons
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, Zombie.ramDamageToCar, away, "impact")
        end
        Brain.wake(z)
        z.hp = z.hp - speed * Zombie.ramScale
        if z.hp <= 0 then
          z.hp = 0
          car.speed = -car.speed * 0.35
          return down(server, id, car.angle, "impact")
        end
      end
      car.speed = -car.speed * 0.35 -- the car re-derives its velocity from this
    end
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local msgs = {}
  if not sv.done then
    local z = sv.z
    local stamina, winded = z.breath:wire()
    msgs[1] = Protocol.encode("PZM_BOSS", server.tick, ("%.0f"):format(z.x), ("%.0f"):format(z.y),
      ("%.3f"):format(z.facing), math.ceil(z.hp), z.max, MODES[z.mode] or 3, z.crabs, stamina, winded)
  end
  local parts = { server.tick }
  for _, c in ipairs(sv.crabs.list) do
    parts[#parts + 1] = c.id
    parts[#parts + 1] = ("%.0f"):format(c.x)
    parts[#parts + 1] = ("%.0f"):format(c.y)
    parts[#parts + 1] = ("%.2f"):format(c.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, c.hp))
    parts[#parts + 1] = CRAB_MODES[c.mode] or 2
    parts[#parts + 1] = ("%.2f"):format(Crabs.air(c))
  end
  local send = true
  if #parts == 1 then
    send = sv.emptySends < EMPTY_AFTER
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  if send then
    msgs[#msgs + 1] = Protocol.encode("PZM_CRABS", unpack(parts))
  end
  for _, player in pairs(server.players) do
    if not player.bot then
      for _, msg in ipairs(msgs) do
        server:send(player, msg, true)
      end
    end
  end
end

function Zombie:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  if not sv.done then
    local z = sv.z
    local what, at = Brain.think(Zombie, z, server, dt, sv.time, sv.crabs:alive() < sv.maxOut)
    if what == "throw" then
      sv.crabs:throw(at.x, at.y, at.tx, at.ty)
    end
    rams(server, z, dt)
    if not sv then
      return -- the ram that finished him ended the quest
    end
  end
  sv.crabs:update(server, dt, function(c, q)
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, q.p, nil, q.car and Crabs.SCRATCH or Crabs.BITE, c.facing, "poison")
    end
    server:broadcast(Protocol.encode("PZM_BITE", fmt(c.x), fmt(c.y)))
  end)
  if not sv then
    return -- a bite ended the quest
  end
  for _, c in ipairs(sv.crabs:squashed(server) or {}) do
    crabDown(server, c, c.by, c.angle, "impact")
  end
  sv.crabs:sweep()
  sync(server)
end

--- A round or a blast through (x, y): the `serverShotAt` convention.
--- Rounds and blasts owned by nobody (the Combine's, a rollermine going off)
--- pass by; a player's blast's share, which carries nothing, takes 20.
function Zombie:serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local z = not sv.done and sv.z
  if z and (x - z.x) ^ 2 + (y - z.y) ^ 2 <= (radius + Zombie.radius) ^ 2 then
    Brain.wake(z)
    z.hp = z.hp - (damage or 20)
    if z.hp <= 0 then
      z.hp = 0
      down(server, by, angle, dtype)
    end
    return true
  end
  local c = sv.crabs:at(x, y, radius)
  if not c then
    return false
  end
  if sv.crabs:hurt(c, damage or 20) then
    crabDown(server, c, by, angle, dtype)
  end
  return true
end

function Zombie:serverFreezeArea(_server, x, y, radius, seconds)
  if not sv then
    return
  end
  local z = not sv.done and sv.z
  if z and (z.x - x) ^ 2 + (z.y - y) ^ 2 <= (radius + Zombie.radius) ^ 2 then
    z.frozen = math.max(z.frozen, seconds * 0.6) -- big: he shakes a freeze off sooner
  end
  sv.crabs:freeze(x, y, radius, seconds)
end

function Zombie:serverPanicArea(_server, x, y, radius)
  if not sv then
    return
  end
  local z = not sv.done and sv.z
  if z and (z.x - x) ^ 2 + (z.y - y) ^ 2 <= (radius + Zombie.radius) ^ 2 then
    z.panic = { x = x, y = y, left = 0.8 }
  end
  sv.crabs:scare(x, y, radius)
end

--- For tests.
function Zombie.server()
  return sv
end

-- Client --------------------------------------------------------------------

local lastTick, lastCrabTick = 0, 0
local clock = 0
local heardAt, crabsHeardAt = 0, 0 -- when the last PZM_BOSS and PZM_CRABS came
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer
local breathIn = 0

function Zombie:load()
  Sounds.load()
end

function Zombie:exitGame()
  cl, shown, bodies, lastTick, lastCrabTick = nil, {}, {}, 0, 0
end

function Zombie:update(dt)
  clock = clock + dt
  if cl and love.timer.getTime() - heardAt > STALE then
    cl = nil
  end
  if next(shown) and love.timer.getTime() - crabsHeardAt > STALE then
    shown = {}
  end
  for i = #bodies, 1, -1 do
    local b = bodies[i]
    b.t = b.t + dt
    if b.t > (b.crab and CRAB_DEAD_TIME or DEAD_TIME) then
      table.remove(bodies, i)
    end
  end
  local k = math.min(1, dt * CRAB_SMOOTHING)
  for _, c in pairs(shown) do
    c.t = c.t + dt
    local ex, ey = c.x - c.dx, c.y - c.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      c.dx, c.dy = c.x, c.y
    else
      c.dx, c.dy = c.dx + ex * k, c.dy + ey * k
      c.cycle = c.cycle + math.sqrt(ex * ex + ey * ey) * k / CRAB_STEP
    end
    c.hurt = math.max(0, c.hurt - dt)
    if c.mode == CRAB_MODES.crawl then
      c.chitterIn = c.chitterIn - dt
      if c.chitterIn <= 0 then
        c.chitterIn = CHITTER_EVERY[1] + love.math.random() * (CHITTER_EVERY[2] - CHITTER_EVERY[1])
        Sounds.play("chitter", c.dx, c.dy, 0.85 + love.math.random() * 0.3)
      end
    end
  end
  if not cl then
    return
  end
  cl.t = cl.t + dt
  k = math.min(1, dt * SMOOTHING)
  local ex, ey = cl.x - cl.dx, cl.y - cl.dy
  local moved = math.sqrt(ex * ex + ey * ey) * k
  if ex * ex + ey * ey > SNAP * SNAP then
    cl.dx, cl.dy = cl.x, cl.y
  else
    cl.dx, cl.dy = cl.dx + ex * k, cl.dy + ey * k
    cl.cycle = cl.cycle + moved / STEP
  end
  cl.stride = cl.stride + (math.min(1, moved / math.max(dt, 1e-6) / 50) - cl.stride) * math.min(1, dt * 6)
  cl.hurt = math.max(0, cl.hurt - dt)
  breathIn = breathIn - dt
  if breathIn <= 0 then
    breathIn = BREATH_EVERY * (cl.winded and 0.6 or 1)
    Sounds.play("breath", cl.dx, cl.dy, 0.9 + love.math.random() * 0.15)
  end
end

function Zombie:drawBelowCars()
  for _, b in ipairs(bodies) do
    local life = b.crab and CRAB_DEAD_TIME or DEAD_TIME
    local alpha = math.min(1, (life - b.t) / 3)
    if b.crab then
      Render.crab(b.x, b.y, b.facing, { dead = true, alpha = alpha })
    else
      Render.draw(b.x, b.y, b.facing, { dead = true, crabs = 0, alpha = alpha }, clock)
    end
  end
end

function Zombie:drawAboveCars()
  for _, c in pairs(shown) do
    local leaping = c.mode == CRAB_MODES.fly or c.mode == CRAB_MODES.leap
    Render.crab(c.dx, c.dy, c.facing, { cycle = c.cycle, leap = leaping and c.air or nil, hurt = c.hurt / HURT * 0.6 })
  end
  if not cl then
    return
  end
  local m = cl.mode
  Render.draw(cl.dx, cl.dy, cl.facing, {
    cycle = cl.cycle, stride = cl.stride, crabs = cl.crabs, hurt = cl.hurt / HURT * 0.6,
    throw = m == MODES.throw and math.min(1, cl.t / Zombie.throwTime) or nil,
    swipe = m == MODES.swipe and math.min(1, cl.t / Zombie.swipeTime) or nil,
    howl = m == MODES.howl,
  }, clock)
end

function Zombie:drawHUD()
  if cl and cl.max and cl.mode ~= MODES.wait then
    Bar.draw({ title = "POISON ZOMBIE", titleColor = TITLE_COLOR, fill = BAR_FILL, hp = cl.hp, max = cl.max,
      stamina = cl.stamina, staminaMax = Zombie.breath.max, winded = cl.winded })
  end
end

Zombie.clientMessages = {
  PZM_BOSS = function(_client, args)
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
    elseif cl.mode ~= mode then
      cl.mode, cl.t = mode, 0
      if mode == MODES.howl then
        Sounds.play("howl", x, y)
      elseif mode == MODES.throw then
        Sounds.play("grunt", x, y, 0.9 + love.math.random() * 0.2)
      elseif mode == MODES.swipe then
        Sounds.play("claw", x, y)
      end
    end
    local hp = tonumber(args[5])
    if cl.hp and hp and hp < cl.hp then
      cl.hurt = HURT
    end
    cl.x, cl.y, cl.facing, cl.hp, cl.max = x, y, tonumber(args[4]) or 0, hp, tonumber(args[6])
    cl.crabs = tonumber(args[8]) or 0
    cl.stamina, cl.winded = Stamina.read(args, 9)
  end,
  PZM_CRABS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastCrabTick then
      return
    end
    lastCrabTick, crabsHeardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      local mode = tonumber(args[i + 5])
      if id and x and y and mode then
        local c = shown[id]
        local hp = tonumber(args[i + 4]) or Crabs.HEALTH
        if not c then
          c = { dx = x, dy = y, cycle = 0, hurt = 0, t = 0, mode = mode, hp = hp, chitterIn = 0.5 }
          shown[id] = c
        elseif c.mode ~= mode then
          c.mode, c.t = mode, 0
          if mode == CRAB_MODES.leap then
            Sounds.play("screech", x, y, 0.9 + love.math.random() * 0.25)
          end
        end
        if hp < c.hp then
          c.hurt = HURT
        end
        c.x, c.y, c.hp = x, y, hp
        c.facing = tonumber(args[i + 3]) or 0
        c.air = tonumber(args[i + 6]) or 0
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  PZM_CRAB_DOWN = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id then
      shown[id] = nil
    end
    if x and y then
      bodies[#bodies + 1] = { x = x, y = y, facing = tonumber(args[4]) or 0, t = 0, crab = true }
      Sounds.play("squish", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
  PZM_BITE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("bite", x, y)
    end
  end,
  PZM_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      bodies[#bodies + 1] = { x = x, y = y, facing = tonumber(args[3]) or 0, t = 0 }
      cl = nil
      Sounds.play("howl", x, y, 0.7)
    end
  end,
}

return Zombie
