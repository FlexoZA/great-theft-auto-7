-- A-Man at the top of the Citadel: the end of his trail and the last fight
-- (quests' "a-man-citadel"; citadel.lua runs it). The same man as the city
-- event (event.lua), no disguise any better, and the same brain (brain.lua):
-- he stalks the nearest player, blinks straight through anyone close (the
-- line shows for `windup`; everyone on it takes `damage`), goes for a
-- medkit when badly hurt and gets out from under what players drop on him.
-- Here he is much stronger (`health`), and his briefcase holds more than
-- turrets.
--
-- He is not there to begin with. The first player to step onto the top
-- platform (the map's platform of kind "top") brings him: he blinks in by
-- the lift up, stands a moment taking them in (`arriveTime`), and the
-- fight is on.
--
-- His briefcase: it is the damage that opens it. Every `caseShare` of his
-- health he loses earns a case (a big hit can earn more than one: they
-- wait their turn, `caseGap` apart). With one owed, a player near and the
-- breath for it, he stops and holds it up for `caseTime` (the warning; he
-- flickers green and the clasps go), then it snaps open and out comes one of `SUMMONS`, never the
-- same twice running, round him: Combine soldiers (city17.lua's drop),
-- Hunters on a ring round him (the hunters feature), rollermines already
-- awake (the rollermines feature), a swarm of antlions up out of the floor
-- (the antlions feature) or his sentry turrets (turrets.lua, only when
-- none of the last lot are standing). Under `rage` of his health two come
-- out at once. Every count is for one human, more with more (Bosses.count).
--
-- Down: the disguise is left lying there, he spills koins and his teleport
-- (a better roll than the event's, `dropTiers`), raises `serverKill` with
-- kind "boss", and the level is done (quests' `serverComplete`): the EXIT
-- star comes up where he fell.
--
-- Messages (the a-man feature registers them)
--   server -> all  AMF_STATE <tick> [<x> <y> <facing> <moving> <hp> <max> <aimX|-> <aimY|-> <stamina> <winded>
--                  <opening>]  (unreliable, 15 Hz; nothing after the tick: not here)
--   server -> all  AMF_IN    <x> <y> <facing>       he blinked in there
--   server -> all  AMF_BLINK <sx> <sy> <ex> <ey>    he teleported from one to the other
--   server -> all  AMF_OPEN  <x> <y>                he holds the case up: something is coming
--   server -> all  AMF_CASE  <x> <y> <kind>...      it opened and these came out
--   server -> all  AMF_TURRETS <tick> (<id> <x> <y> <facing> <firing>)...  (unreliable, 15 Hz)
--   server -> all  AMF_POP   <id> <x> <y> <facing>  a turret fell over
--   server -> all  AMF_DOWN  <x> <y>                he went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")
local Teleport = require("src.features.abilities.teleport")
local Event = require("src.features.a-man.event")
local Brain = require("src.features.a-man.brain")
local Face = require("src.features.a-man.face")
local Sounds = require("src.features.a-man.sounds")
local Turrets = require("src.features.a-man.turrets")

local Finale = {}

-- Tuning ------------------------------------------------------------------
Finale.questId = "a-man-citadel" -- the quest he is the boss of
Finale.health = 5000 -- for one human (more humans, more: bosses/init.lua); the event's is 1400
Finale.radius = Body.RADIUS
Finale.walkSpeed = 60
Finale.keepAway = 90
Finale.breath = { max = 100, regen = 13, regenDelay = 1.2, breath = 40 }
Finale.blinkCost = 35 -- breath a blink takes
Finale.blinkEvery = 2.4 -- seconds at least between blinks
Finale.blinkJitter = 1.5 -- and up to this much more
Finale.windup = 0.7 -- seconds the line shows before he goes
Finale.strikeRange = 600 -- px; a target this close gets a blink straight through them
Finale.overshoot = 200 -- px he comes out past them
Finale.reach = 2600 -- px; a target further than this he walks towards
Finale.approachGap = 220 -- px from a far target he lands
Finale.damage = 70 -- to everyone on his line
Finale.width = Teleport.width
Finale.healRange = 1600
Finale.hordeRange = 1000 -- px; he opens the case with a player this close (the brain's name for it)
Finale.hordeCost = 30 -- breath opening it takes
Finale.arriveTime = 1.5 -- seconds he stands there after he blinks in
Finale.caseShare = 0.1 -- of his health lost for each case: nine in all on the way down
Finale.caseGap = 2.5 -- seconds at least between one case and the next
Finale.caseTime = 1.0 -- seconds he holds it up before it opens: the warning
Finale.rage = 0.3 -- share of his health under which two things come out at once
Finale.bulletDamage = 20 -- what a round takes off him when it doesn't say (a blast)
Finale.drops = 150 -- koins he spills
Finale.drop = "ability-teleport"
Finale.dropTiers = { { "uncommon", 40 }, { "rare", 45 }, { "legendary", 15 } }
-- What can come out of the case, how likely, and how many for one human.
Finale.SUMMONS = {
  { kind = "soldiers", weight = 3, count = 4, say = "Some... colleagues." },
  { kind = "hunters", weight = 2, count = 2, say = "Do meet my... associates." },
  { kind = "rollermines", weight = 2, count = 4, say = "Something to... keep you rolling." },
  { kind = "antlions", weight = 2, count = 7, say = "From the coast. They followed me." },
  { kind = "turrets", weight = 2, count = 8, say = "Aperture sends its... regards." },
}
local HUNTER_RING = 160 -- px out from him that called-in Hunters walk

local SYNC_EVERY = 2
local SMOOTHING = 14
local SNAP = 200
local TEAR_TIME = 0.8
local SAY_TIME = 3 -- seconds what he says over the case hangs there
local EMPTY = "-"

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function summonOf(kind)
  for _, s in ipairs(Finale.SUMMONS) do
    if s.kind == kind then
      return s
    end
  end
end

-- Server --------------------------------------------------------------------

local sv = nil -- { waiting, a, turrets, syncIn, time, owed, nextCaseAt, caseIn, last, blinking, done }

function Finale.serverStart()
  sv = { waiting = true, turrets = Turrets.new("AMF_POP"), syncIn = 0, time = 0 }
end

function Finale.serverStop(server)
  if sv and server then
    Turrets.clear(sv.turrets, server)
    server:broadcast(Protocol.encode("AMF_STATE", server.tick))
  end
  sv = nil
end

local function topOf(map)
  for _, p in ipairs(map.platforms or {}) do
    if p.kind == "top" then
      return p
    end
  end
end

--- Somebody on the top platform?
local function someoneOnTop(server, top)
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if x >= top.x and x <= top.x + top.w and y >= top.y and y <= top.y + top.h then
        return p
      end
    end
  end
end

--- He blinks in by the lift up, facing whoever came.
local function arrive(server, map, p)
  local x, y = map.exitX, map.exitY
  for _ = 1, 30 do
    if not Features.any("blocksPoint", x, y) then
      break
    end
    x, y = map.exitX + (random() - 0.5) * 160, map.exitY + random() * 120
  end
  local px, py = Features.bodyPose(server, p)
  local hp = Bosses.health(Finale.health, server)
  sv.waiting = false
  sv.a = {
    x = x, y = y, facing = math.atan2(py - y, px - x), hp = hp, max = hp, frozen = Finale.arriveTime,
    moving = false, breath = Stamina.new(Finale.breath), cool = Finale.arriveTime + Finale.blinkEvery,
  }
  sv.owed, sv.nextCaseAt, sv.caseIn = 0, hp * (1 - Finale.caseShare), 0
  server:broadcast(Protocol.encode("AMF_IN", fmt(x), fmt(y), ("%.2f"):format(sv.a.facing)))
end

--- He goes: everyone on the line is torn through and he is at the other end.
local function blink(server, a)
  local sx, sy, ex, ey = a.x, a.y, a.aimX, a.aimY
  a.aimX, a.aimY = nil, nil
  sv.blinking = true -- his own line doesn't hit him
  Teleport.serverThrough(server, sx, sy, ex, ey, Finale.damage, Finale.width, nil, nil)
  if not sv then
    return
  end
  sv.blinking = false
  a.x, a.y = ex, ey
  a.breath:spend(Finale.blinkCost)
  a.cool = Finale.blinkEvery + random() * Finale.blinkJitter
  server:broadcast(Protocol.encode("AMF_BLINK", fmt(sx), fmt(sy), fmt(ex), fmt(ey)))
end

--- One of SUMMONS, as likely as its weight, but not `except` (the last one)
--- nor turrets while any of his are standing.
local function pick(except)
  local options, total = {}, 0
  for _, s in ipairs(Finale.SUMMONS) do
    if s.kind ~= except and not (s.kind == "turrets" and Turrets.standing(sv.turrets) > 0) then
      options[#options + 1] = s
      total = total + s.weight
    end
  end
  if #options == 0 then
    return Finale.SUMMONS[1] -- nothing else he may: the first again
  end
  local roll = random() * total
  for _, s in ipairs(options) do
    roll = roll - s.weight
    if roll < 0 then
      return s
    end
  end
  return options[#options]
end

--- `s` out of the case at (x, y).
local function release(server, s, x, y)
  local n = Bosses.count(s.count, server)
  if s.kind == "turrets" then
    Turrets.spill(sv.turrets, x, y, n)
  elseif s.kind == "soldiers" then
    local aman = Features.byName["a-man"]
    if aman and aman.serverDropTroops then
      aman:serverDropTroops(server, x, y, s.count) -- it scales them itself
    end
  elseif s.kind == "hunters" then
    local hunters = Features.byName.hunters
    if hunters and hunters.serverPatrol then
      local route = {}
      for i = 0, 7 do
        local a = i / 8 * 2 * math.pi
        route[#route + 1] = { x = x + math.cos(a) * HUNTER_RING, y = y + math.sin(a) * HUNTER_RING }
      end
      hunters:serverPatrol(server, route, n)
    end
  else
    local feature = Features.byName[s.kind] -- "rollermines" or "antlions"
    if feature and feature.serverSummon then
      feature:serverSummon(server, x, y, n, 90)
    end
  end
end

--- The case snaps open.
local function open(server, a)
  local first = pick(sv.last)
  local out = { first }
  if a.hp < a.max * Finale.rage then
    out[2] = pick(first.kind)
  end
  sv.last = out[#out].kind
  local parts = { fmt(a.x), fmt(a.y) }
  for _, s in ipairs(out) do
    release(server, s, a.x, a.y)
    parts[#parts + 1] = s.kind
  end
  server:broadcast(Protocol.encode("AMF_CASE", unpack(parts)))
  sv.owed = sv.owed - 1
  sv.caseIn = Finale.caseGap
  a.cool = math.max(a.cool, 1.2) -- a moment to admire what he let out
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local a = sv.a
  local stamina, winded = a.breath:wire()
  local msg = Protocol.encode("AMF_STATE", server.tick, fmt(a.x), fmt(a.y), ("%.2f"):format(a.facing),
    a.moving and 1 or 0, math.max(0, math.floor(a.hp)), a.max, a.aimX and fmt(a.aimX) or EMPTY,
    a.aimY and fmt(a.aimY) or EMPTY, stamina, winded, a.opening and 1 or 0)
  local turrets = Protocol.encode("AMF_TURRETS", server.tick, unpack(Turrets.wire(sv.turrets)))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
      server:send(player, turrets, true)
    end
  end
end

function Finale.serverStep(server, dt, map)
  if not sv or sv.done then
    return
  end
  sv.time = sv.time + dt
  Turrets.step(sv.turrets, server, dt)
  if sv.waiting then
    local top = map and topOf(map)
    local p = top and someoneOnTop(server, top)
    if p then
      arrive(server, map, p)
    end
    return
  end
  local a = sv.a
  sv.caseIn = sv.caseIn - dt
  -- Every share of his health gone earns a case.
  while sv.nextCaseAt > 0 and a.hp <= sv.nextCaseAt do
    sv.owed = sv.owed + 1
    sv.nextCaseAt = sv.nextCaseAt - a.max * Finale.caseShare
  end
  if a.opening then
    a.moving = false
    a.opening = a.opening - dt
    if a.opening <= 0 then
      a.opening = nil
      open(server, a)
    end
  else
    local act = Brain.think(Finale, a, server, dt, sv.owed > 0 and sv.caseIn <= 0, sv.time)
    if act == "blink" then
      blink(server, a)
      if not sv then
        return
      end
    elseif act == "horde" then
      a.breath:spend(Finale.hordeCost)
      a.opening = Finale.caseTime
      server:broadcast(Protocol.encode("AMF_OPEN", fmt(a.x), fmt(a.y)))
    end
  end
  a.breath:step(false, dt) -- he never runs
  sync(server)
end

--- A tier from `dropTiers`, as likely as its weight.
local function rollTier()
  local total = 0
  for _, t in ipairs(Finale.dropTiers) do
    total = total + t[2]
  end
  local roll = random() * total
  for _, t in ipairs(Finale.dropTiers) do
    roll = roll - t[2]
    if roll < 0 then
      return t[1]
    end
  end
  return Finale.dropTiers[1][1]
end

--- He goes down: the disguise, koins, his teleport, the level done.
local function down(server, by, angle)
  local a = sv.a
  local x, y = a.x, a.y
  sv.done = true
  Turrets.clear(sv.turrets, server)
  server:broadcast(Protocol.encode("AMF_STATE", server.tick))
  server:broadcast(Protocol.encode("AMF_DOWN", fmt(x), fmt(y)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Finale.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    local dx, dy = x, y
    for i = 0, 7 do
      local t = math.pi / 2 + i * math.pi / 4
      local ox, oy = x + math.cos(t) * 60, y + math.sin(t) * 60
      if not Features.any("blocksPoint", ox, oy) then
        dx, dy = ox, oy
        break
      end
    end
    pickups:serverDrop(server, Finale.drop .. "@" .. rollTier(), dx, dy)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  local quests = Features.byName.quests
  if quests and quests.serverComplete then
    quests:serverComplete(server, Finale.questId, x, y)
  end
end

--- A round through (x, y): the `serverShotAt` convention. A turret in the
--- way goes over; rounds owned by nobody (his turrets', the Combine's) and
--- his own blink pass him by.
function Finale.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.done or sv.blinking or by == 0 then
    return false
  end
  if Turrets.hit(sv.turrets, server, x, y, radius) then
    return true
  end
  local a = sv.a
  if not a or dist2(a.x, a.y, x, y) >= (radius + Finale.radius) ^ 2 then
    return false
  end
  a.hp = a.hp - (damage or Finale.bulletDamage)
  if a.hp <= 0 then
    a.hp = 0
    down(server, by, angle)
  end
  return true
end

--- A stink at (x, y) throws him off the blink he was aiming.
function Finale.serverPanicArea(x, y, radius)
  local a = sv and not sv.done and sv.a
  if a and a.aimX and dist2(a.x, a.y, x, y) <= (radius + Finale.radius) ^ 2 then
    a.aimX, a.aimY = nil, nil
    a.cool = Finale.blinkEvery
  end
end

--- A freeze at (x, y): he stands still (half as long: he is used to worse), and so do his turrets.
function Finale.serverFreezeArea(x, y, radius, seconds)
  if not sv then
    return
  end
  Turrets.freeze(sv.turrets, x, y, radius, seconds)
  local a = not sv.done and sv.a
  if a and dist2(a.x, a.y, x, y) <= (radius + Finale.radius) ^ 2 then
    a.frozen = math.max(a.frozen, seconds * 0.5)
  end
end

--- For tests.
function Finale.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { a, lastTick, turretTick, tears, turrets, says }
local face = nil
local time = 0

local function client()
  cl = cl or { lastTick = 0, turretTick = 0, tears = {}, turrets = Turrets.clientNew() }
  return cl
end

function Finale.clear()
  cl = nil
end

--- Where he is drawn, for footsteps; nil while he isn't here.
function Finale.where()
  local a = cl and cl.a
  if a then
    return a.dx, a.dy
  end
end

function Finale.update(dt)
  time = time + dt
  if not cl then
    return
  end
  if face then
    face:update(dt)
  end
  Turrets.update(cl.turrets, dt)
  for i = #cl.tears, 1, -1 do
    local t = cl.tears[i]
    t.t = t.t + dt
    if t.t > TEAR_TIME then
      table.remove(cl.tears, i)
    end
  end
  if cl.says then
    cl.says.t = cl.says.t - dt
    if cl.says.t <= 0 then
      cl.says = nil
    end
  end
  local a = cl.a
  if not a then
    return
  end
  local ex, ey = a.x - a.dx, a.y - a.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    a.dx, a.dy = a.x, a.y
  else
    local k = math.min(1, dt * SMOOTHING)
    a.dx, a.dy = a.dx + ex * k, a.dy + ey * k
  end
  if a.moving then
    a.stride = a.stride + dt * 6
  end
end

function Finale.drawBelowCars()
  if not cl then
    return
  end
  for _, t in ipairs(cl.tears) do
    Teleport.drawTear(t.sx, t.sy, t.ex, t.ey, t.t / TEAR_TIME, Event.color)
  end
end

function Finale.drawAboveCars()
  if not cl then
    return
  end
  Turrets.draw(cl.turrets, time)
  local a = cl.a
  if a then
    if a.opening then
      -- The case held up: a green glow swelling round him.
      local c, k = Event.color, 0.5 + 0.5 * math.sin(time * 14)
      love.graphics.setColor(c[1], c[2], c[3], 0.15 + 0.15 * k)
      love.graphics.circle("fill", a.dx, a.dy, 26 + 8 * k, 24)
      love.graphics.setColor(c[1], c[2], c[3], 0.7)
      love.graphics.setLineWidth(2)
      love.graphics.circle("line", a.dx, a.dy, 30 + 10 * k, 24)
      love.graphics.setLineWidth(1)
    end
    if a.aimX then
      Event.drawAimLine(a)
    end
    Event.drawFigure(a)
    if cl.says then
      love.graphics.setFont(UI.fonts.small)
      local w = UI.fonts.small:getWidth(cl.says.text)
      local alpha = math.min(1, cl.says.t)
      love.graphics.setColor(0, 0, 0, 0.6 * alpha)
      love.graphics.rectangle("fill", a.dx - w / 2 - 6, a.dy - 58, w + 12, 20, 4)
      local c = Event.color
      love.graphics.setColor(c[1], c[2], c[3], alpha)
      love.graphics.print(cl.says.text, a.dx - w / 2, a.dy - 56)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Finale.drawHUD()
  local a = cl and cl.a
  if not a then
    return
  end
  BossBar.draw({
    title = "A-MAN", titleColor = { 0.7, 1, 0.75 }, fill = { 0.35, 0.75, 0.45 },
    hp = a.hp, max = a.max, stamina = a.stamina, staminaMax = Finale.breath.max, winded = a.winded,
  })
  if face then
    local w, h = love.graphics.getDimensions()
    local bx = math.floor((w - BossBar.width) / 2)
    face:draw(bx - Face.W / 2 - 10, h - BossBar.bottom - 6, 1)
  end
end

Finale.clientMessages = {
  AMF_STATE = function(_client, args)
    local c = client()
    local tick = tonumber(args[1])
    if not tick or tick <= c.lastTick then
      return
    end
    c.lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      c.a = nil
      return
    end
    local a = c.a or { dx = x, dy = y, stride = 0 }
    a.x, a.y = x, y
    a.angle = tonumber(args[4]) or a.angle or 0
    a.moving = args[5] == "1"
    a.hp = tonumber(args[6]) or a.hp or Finale.health
    a.max = tonumber(args[7]) or a.max or Finale.health
    a.aimX, a.aimY = tonumber(args[8]), tonumber(args[9])
    local stamina, winded = Stamina.read(args, 10)
    a.stamina, a.winded = stamina or a.stamina, winded
    a.opening = args[12] == "1"
    c.a = a
    face = face or Face.new()
  end,
  AMF_IN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    local c = client()
    c.a = { x = x, y = y, dx = x, dy = y, angle = tonumber(args[3]) or 0, stride = 0, hp = Finale.health,
      max = Finale.health }
    c.tears[#c.tears + 1] = { sx = x, sy = y - 70, ex = x, ey = y + 70, t = 0 }
    c.says = { text = "Ah. You made it. All the way... up.", t = SAY_TIME }
    face = face or Face.new()
    Sounds.play("appear", x, y)
  end,
  AMF_BLINK = function(_client, args)
    local sx, sy, ex, ey = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (sx and sy and ex and ey) then
      return
    end
    local c = client()
    c.tears[#c.tears + 1] = { sx = sx, sy = sy, ex = ex, ey = ey, t = 0 }
    local a = c.a
    if a then
      a.x, a.y, a.dx, a.dy, a.aimX, a.aimY = ex, ey, ex, ey, nil, nil
    end
    Sounds.play("vanish", sx, sy)
    Sounds.play("appear", ex, ey, 1.6)
  end,
  AMF_OPEN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("clasp", x, y)
    end
  end,
  AMF_CASE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    local s = summonOf(args[3] or "")
    if s then
      client().says = { text = s.say, t = SAY_TIME }
    end
    Sounds.play("clasp", x, y)
    Sounds.play("turret", x, y)
  end,
  AMF_TURRETS = function(_client, args)
    local c = client()
    local tick = tonumber(args[1])
    if not tick or tick <= c.turretTick then
      return
    end
    c.turretTick = tick
    Turrets.read(c.turrets, args, 2)
  end,
  AMF_POP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id and x and y then
      Turrets.pop(client().turrets, id, x, y, tonumber(args[4]) or 0)
      Sounds.play("pop", x, y, 0.9 + random() * 0.25)
    end
  end,
  AMF_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    client().a = nil
    Event.leaveRemains(x, y)
    Sounds.play("rip", x, y)
    Sounds.play("clasp", x, y)
  end,
}

return Finale
