-- Shoeman as a city event (src/features/events; docs/tutorial.md, "Cast"):
-- the tutorial's teacher, done teaching. He comes into the city somewhere
-- away from everyone and walks it throwing shoes: at the nearest player he
-- can see, or with nobody near, at the nearest building a player owns. He
-- is bigger than a player and heavier, and drawn as he is on the tutorial's
-- maps (shoeman_render.lua); his portrait sits by his boss bar.
--
-- The shoe is the tutorial's (shoe.lua), a thrower of his own: one every
-- `throwEvery` seconds, the red "DODGE!!!!" over him as he winds up, aimed
-- at where the player stands when it leaves his hand. Whatever it touches
-- that can take damage is destroyed at once, players on foot, cars,
-- enemies; it flies on through them and stops at the first wall, which
-- takes `wallDamage` (two or three shoes bring a building down). Dodge it,
-- or put a wall between you.
--
-- He follows the bosses' standard (src/features/bosses): breath (running
-- spends it, winded he walks), the boss bar, health for the humans in the
-- game, koins and `serverKill` "boss" when he goes down, a medkit when he
-- is badly hurt, out from under a player's ability, walking that doesn't
-- get stuck. What he does is his brain's (event_brain.lua). A freeze holds
-- him and his throw waits; a stink in his face sends him running out of it.
--
-- Locked until the tutorial is finished in this world (events/init.lua's
-- `Events.after`).
--
-- The host owns him; clients hear where he is at 15 Hz.
--
-- Messages (the events feature registers them)
--   server -> all  ESM_STATE <tick> <x> <y> <facing> <moving> <hp> <max> <stamina> <winded>  (unreliable, 15 Hz)
--   server -> all  ESM_THROW, ESM_SHOE, ESM_SHOE_END   his shoes: shoe.lua's messages under his own kinds

local Protocol = require("src.net.protocol")
local Drawn = require("src.features.drawn")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")
local Heal = require("src.features.bosses.heal")
local Shoe = require("src.features.tutorial.shoe")
local ShoemanRender = require("src.features.tutorial.shoeman_render")
local ShoemanFace = require("src.features.tutorial.shoeman_face")
local Brain = require("src.features.tutorial.event_brain")

-- His own thrower, never the tutorial's.
local Shoes = Shoe.new({ throw = "ESM_THROW", shoe = "ESM_SHOE", stop = "ESM_SHOE_END" })

local Shoeman = {
  key = "shoeman",
  title = "SHOEMAN IS IN TOWN",
  subtitle = "School's back in. Dodge his shoes, or keep a wall between you.",
  wonTitle = "SHOEMAN IS DOWN",
  wonSubtitle = "Class dismissed. Pick up his koins.",
  color = { 0.45, 0.6, 1 },
  menu = "Your old teacher walks the city throwing shoes at players and their buildings. "
    .. "One shoe kills whatever it touches. Drops koins.",
}

-- Tuning ------------------------------------------------------------------
Shoeman.health = 1800 -- 90 pistol rounds, for one player (more humans, more: bosses/init.lua)
Shoeman.radius = ShoemanRender.RADIUS -- px; bigger than a player
Shoeman.runSpeed = 150 -- px/s; a sprint (170) gets away from him
Shoeman.walkSpeed = 45 -- px/s winded or close; a walking player keeps their distance
Shoeman.breath = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  drain = 18, -- per second running: ~5.5 s, a little longer than a player's sprint
  regen = 14,
  recovered = 50,
}
Shoeman.throwEvery = 5 -- seconds from one throw to the next
Shoeman.firstThrow = 3 -- seconds after he comes in before the first
Shoeman.throwRange = 650 -- px; a player this close and in the clear gets a shoe
Shoeman.keepAway = 260 -- px; he walks no closer to a player he can hit than this
Shoeman.runFrom = 450 -- px; further off than this he runs (breath allowing)
Shoeman.aggroRange = 1000 -- px; a player this close comes before any building
Shoeman.buildingRange = 260 -- px from a building's wall he throws at it
Shoeman.wallDamage = 250 -- what a shoe does to the wall it stops at (a quarry has 600)
Shoeman.bulletDamage = 20 -- what a round takes off him when it doesn't say
Shoeman.panicTime = 1.5 -- seconds a stink sends him running
Shoeman.healRange = Heal.range -- px; how far he will go for a medkit
Shoeman.spawnNear = 1000 -- px; he comes in about this far from the nearest player
Shoeman.spawnFar = 1800
Shoeman.drops = 60 -- koins he spills

local SYNC_EVERY = 2 -- server ticks between ESM_STATE packets
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a jump, not a step

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server --------------------------------------------------------------------

local sv = nil -- { s = Shoeman, events, syncIn, time, own (his shoe is flying this tick) }

function Shoeman.serverStop()
  sv = nil
  Shoes:serverStop()
end

function Shoeman.serverBegin(server, events)
  local node = events:serverSpawnNode(server, Shoeman.spawnNear, Shoeman.spawnFar)
  if not node then
    return nil
  end
  local hp = Bosses.health(Shoeman.health, server)
  local map = Features.byName["city-map"].map
  sv = {
    s = {
      x = node.x, y = node.y, facing = 0, hp = hp, max = hp, frozen = 0, throwing = 0,
      moving = false, running = false, cool = Shoeman.firstThrow,
      breath = Stamina.new(Shoeman.breath),
      nav = Brain.nav({ x = map.left, y = map.top, w = map.w, h = map.h }, Shoeman.radius),
    },
    events = events, syncIn = 0, time = 0,
  }
  Shoes:serverStop()
  return node.x, node.y
end

--- He winds up at `throw` ({ x, y, player }): planted until the arm comes
--- through, the next one `throwEvery` later.
local function throwAt(server, s, throw)
  s.facing = math.atan2(throw.y - s.y, throw.x - s.x)
  s.throwing = Shoes.THROW_TIME
  s.cool = Shoeman.throwEvery
  Shoes:serverThrowAt(server, s.x, s.y, throw.x, throw.y, Shoeman.wallDamage * Bosses.power(), throw.player)
end

--- Where he is, to everyone.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local s = sv.s
  local stamina, winded = s.breath:wire()
  local msg = Protocol.encode("ESM_STATE", server.tick, fmt(s.x), fmt(s.y), ("%.2f"):format(s.facing),
    s.moving and 1 or 0, math.max(0, math.floor(s.hp)), s.max, stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Shoeman.serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local s = sv.s
  local throw = Brain.think(Shoeman, s, server, dt, sv.time)
  if throw then
    throwAt(server, s, throw)
  end
  s.breath:step(s.running, dt)
  sv.own = true -- his own shoe doesn't hit him (the events feature passes serverShotAt on to him)
  Shoes:serverStep(server, dt)
  if not sv then
    return -- the event ended under him
  end
  sv.own = false
  sync(server)
end

--- He takes `amount`. At zero he goes down: koins, and the event is over.
local function hurt(server, amount, by, angle)
  local s = sv.s
  s.hp = s.hp - amount
  if s.hp > 0 then
    return
  end
  local x, y = s.x, s.y
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Shoeman.drops)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  sv.events:serverFinish(server, x, y)
end

--- A bullet passing through (x, y): the `serverShotAt` convention. His own
--- shoe goes past him.
function Shoeman.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.own or sv.s.hp <= 0 then
    return false
  end
  local s = sv.s
  if dist2(s.x, s.y, x, y) >= (radius + Shoeman.radius) ^ 2 then
    return false
  end
  hurt(server, damage or Shoeman.bulletDamage, by ~= 0 and by or nil, angle)
  return true
end

--- Him, for the audit (tools/audit).
function Shoeman.serverEnemies(_server, add)
  local s = sv and sv.s
  if s and s.hp > 0 then
    add({ id = s, kind = "tutorial/shoeman", x = s.x, y = s.y, hp = s.hp, radius = Shoeman.radius })
  end
end

--- Something stinks at (x, y): he runs out of it.
function Shoeman.serverPanicArea(_server, x, y, radius)
  local s = sv and sv.s
  if s and dist2(s.x, s.y, x, y) <= (radius + Shoeman.radius) ^ 2 then
    s.panic = { x = x, y = y, left = Shoeman.panicTime }
  end
end

--- A freeze landed on (x, y): he stands still, his throw and all.
function Shoeman.serverFreezeArea(_server, x, y, radius, seconds)
  local s = sv and sv.s
  if s and dist2(s.x, s.y, x, y) <= (radius + Shoeman.radius) ^ 2 then
    s.frozen = math.max(s.frozen, seconds)
  end
end

--- For tests.
function Shoeman.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { s, lastTick }
local face = nil
local time = 0

function Shoeman.start()
  cl = { s = nil, lastTick = 0 }
  face = face or ShoemanFace.new()
  Shoes:clear()
end

function Shoeman.stop()
  cl = nil
  Shoes:clear()
end

--- Where he is drawn now, for the minimap.
function Shoeman.where()
  local s = cl and cl.s
  if s then
    return s.dx, s.dy
  end
  return nil
end

--- Where he walks, for footsteps.
function Shoeman.footing()
  local x, y = Shoeman.where()
  return x, y, "person"
end

function Shoeman.update(dt)
  time = time + dt
  Shoes:update(dt)
  if face then
    face.shouting = Shoes:pose() ~= nil
    face:update(dt)
  end
  local s = cl and cl.s
  if not s then
    return
  end
  Drawn.step(s, dt, SMOOTHING, SNAP)
  if s.moving then
    s.stride = s.stride + dt * 5
  end
end

function Shoeman.drawBelowCars() end

--- Him, throwing or walking, and his shoes in the air and on the ground.
function Shoeman.drawAboveCars()
  local s = cl and cl.s
  local throw, angle = Shoes:pose()
  if s then
    ShoemanRender.draw(s.dx, s.dy, angle or s.angle, { throw = throw, swing = math.sin(s.stride) * 0.8 })
    local frac = math.max(0, s.hp / math.max(1, s.max))
    if frac < 1 then
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.dx - 26, s.dy - 34, 52, 6)
      love.graphics.setColor(1 - frac, frac, 0.2)
      love.graphics.rectangle("fill", s.dx - 25, s.dy - 33, 50 * frac, 4)
    end
  end
  Shoes:draw(s and s.dx, s and s.dy)
  love.graphics.setColor(1, 1, 1)
end

--- An arrow at the edge of the screen pointing at him while he is off it.
local function drawPointer(camera, s)
  local w, h = love.graphics.getDimensions()
  local k = camera.scale or 1
  local sx, sy = w / 2 + (s.dx - camera.x) * k, h / 2 + (s.dy - camera.y) * k
  if sx >= 0 and sx <= w and sy >= 0 and sy <= h then
    return
  end
  local m = 40
  local pulse = 0.6 + 0.4 * math.sin(time * 8)
  local c = Shoeman.color
  love.graphics.push()
  love.graphics.translate(math.max(m, math.min(w - m, sx)), math.max(m, math.min(h - m, sy)))
  love.graphics.rotate(math.atan2(sy - h / 2, sx - w / 2))
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.polygon("fill", 16, 0, -8, -11, -8, 11)
  love.graphics.setColor(c[1], c[2], c[3], pulse)
  love.graphics.polygon("fill", 13, 0, -6, -8, -6, 8)
  love.graphics.pop()
end

--- His health and breath along the bottom with his portrait beside them,
--- and a pointer to him when he is off screen.
function Shoeman.drawHUD(_client, camera)
  local s = cl and cl.s
  if not s then
    return
  end
  if camera then
    drawPointer(camera, s)
  end
  BossBar.draw({
    title = "SHOEMAN", titleColor = { 0.7, 0.8, 1 }, fill = { 0.3, 0.42, 0.85 },
    hp = s.hp, max = s.max, stamina = s.stamina, staminaMax = 100, winded = s.winded,
  })
  if face then
    local w, h = love.graphics.getDimensions()
    local bx = math.floor((w - BossBar.width) / 2)
    face:draw(bx - ShoemanFace.W / 2 - 10, h - BossBar.bottom - 6, 1)
  end
end

Shoeman.clientMessages = {
  ESM_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.lastTick then
      return
    end
    cl.lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    local s = cl.s or { dx = x, dy = y, stride = 0 }
    Drawn.heard(s, x, y, tick)
    s.angle = tonumber(args[4]) or s.angle or 0
    s.moving = args[5] == "1"
    s.hp = tonumber(args[6]) or s.hp or Shoeman.health
    s.max = tonumber(args[7]) or s.max or Shoeman.health
    local stamina, winded = Stamina.read(args, 8)
    s.stamina, s.winded = stamina or s.stamina, winded
    cl.s = s
  end,
}
for kind, handler in pairs(Shoes.clientMessages) do
  Shoeman.clientMessages[kind] = handler
end

--- The wiki's page on him (tools/wiki, docs/wiki.md), asked for by the
--- events feature, which lists and draws him; `opens` says when his event
--- opens.
function Shoeman.wikiEnemies(add, opens)
  local S = Shoeman
  add({
    kind = "tutorial/shoeman",
    name = "Shoeman (city event)",
    boss = true,
    where = "The city, as an event" .. opens .. ": he walks in from somewhere away from everyone",
    about = "The tutorial's teacher, done teaching: a big bald man in a navy t-shirt who believes a thrown "
      .. "shoe fixes most things. He walks the city throwing them at players and their buildings.",
    stats = {
      { "Health", S.health },
      { "Speed", ("%g px/s running, %g px/s walking or winded"):format(S.runSpeed, S.walkSpeed) },
    },
    weapons = {
      { "Shoe", ("every %g s at the nearest player he can see within %g px (with nobody within %g px, the "
        .. "nearest building a player owns): it kills whatever it touches, players on foot, cars and enemies, "
        .. "flies on through them and takes %g off the wall it stops at"):format(S.throwEvery, S.throwRange,
        S.aggroRange, S.wallDamage) },
    },
    abilities = {
      ("He shouts \"%s\" as he winds up, and the shoe goes where you stand %g s later, when it leaves his "
        .. "hand."):format(Shoes.SHOUT, Shoes.THROW_TIME * ShoemanRender.RELEASE),
      ("Running spends his breath (%g a second); winded, he walks until he has %g back."):format(
        S.breath.drain, S.breath.recovered),
      ("Under %g%% health he goes for a medkit within %g px, and it puts back %g."):format(Heal.below * 100,
        S.healRange, Heal.amount),
    },
    tips = {
      "Dodge once the shoe is in the air, not while he winds up: he aims where you stand when he lets go.",
      "A wall between you and him stops the shoe, though the wall takes the hit.",
      "A freeze holds him and his throw waits; a stink in his face sends him running.",
    },
    drops = ("%g koins"):format(S.drops),
  })
end

return Shoeman
