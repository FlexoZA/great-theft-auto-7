-- The Static's war-rigs on the Overpass (docs/cyber-feud.md, "The Static"),
-- and Kilowatt's cameo riding the first of them ("Before the Roof").
-- troops.lua starts, steps and stops them with the rest of the level; their
-- heads are rig_brain.lua.
--
-- A war-rig is an NPC driver from the bots feature (Bots:spawnNpc), parked
-- on the shoulder at the map's `rigs` posts: a rusty truck tractor with a
-- spiked chrome ram bolted on the nose, junk plates welded on, and a ganger
-- riding on the back with a shotgun. It rams whoever comes by, and while
-- the two sides are at it (troops.lua's flare-up) Halcyon's interceptors
-- too. `count` for one human, `perHuman` more for each extra. Wrecked, it
-- spills koins and is gone. Enemies don't go after them (`serverHidden`).
--
-- Kilowatt's cameo, once a level (the map's `kilowatt`): a moment after
-- everyone arrives, or as soon as the first of them drives off, his rig
-- comes roaring up the edge of the road from behind with him standing on
-- the back, shouting. Up the road it swerves into the crash barrier; he
-- leaps off onto the road just before it goes up, laughs, runs for the edge
-- and jumps off the overpass. He is not fought here: that is for the Roof.
--
-- Messages
--   server -> all  RIG_UNITS [<id>]...           the players who are war-rigs (all of them, on each change)
--   server -> all  KW_RIDE  <rig id>             Kilowatt is on that rig, shouting
--   server -> all  KW_LEAP  <x0> <y0> <x1> <y1>  he jumps off it onto the road at (x1, y1)
--   server -> all  KW_EXIT  <x> <y> <angle>      he runs off the edge that way, laughing

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Bosses = require("src.features.bosses")
local Story = require("src.features.cyber-feud.story")
local Hud = require("src.features.cyber-feud.hud")
local Radio = require("src.features.a-man.radio")
local Brain = require("src.features.cyber-feud.rig_brain")

local WarRigs = {}

-- Tuning ------------------------------------------------------------------
WarRigs.count = 2 -- for one human...
WarRigs.perHuman = 1 -- ...and this many more for each human past the first
WarRigs.model = "coe-heavy-horse-yellow"
WarRigs.maxSpeed = 500 -- px/s
WarRigs.health = 380 -- junk welded all over it (the truck takes 220)
WarRigs.drops = 10 -- koins one spills
-- Kilowatt's ride: when it starts, how fast, where it crashes.
WarRigs.cameoAfter = 11 -- seconds after arriving (VEX's screen and the banner), unless someone drives off first
WarRigs.cameoSpeed = 560 -- px/s up the road
WarRigs.cameoFor = 3.4 -- seconds before it swerves into the barrier
WarRigs.leapTime = 0.6 -- seconds he is in the air off the rig
WarRigs.exitAfter = 2.4 -- seconds on the road before he runs for the edge

local WRECK_GONE = 0.3
local CYAN = { 0.18, 0.90, 1.00 }
local CHROME = { 0.72, 0.76, 0.80 }
local RUST = { 0.42, 0.26, 0.16 }
local GANGER = { shirt = { 0.16, 0.14, 0.18 }, pants = { 0.12, 0.12, 0.14 }, skin = { 0.55, 0.40, 0.30 },
  hair = { 0.07, 0.07, 0.09 }, gun = true, gunLength = 14, shadow = false }

local function bots()
  return Features.byName.bots
end

-- Server --------------------------------------------------------------------

local sv = nil -- { units, rivals, cameo = { stage, t, rig } }

local function ids()
  local out = {}
  for _, npc in ipairs(sv and sv.units or {}) do
    out[#out + 1] = npc.id
  end
  return out
end

--- A rig's head: rig_brain.lua, with the interceptors as fair game while
--- the two sides are at it.
local function brainFor()
  return {
    think = function(server, npc, dt)
      local troops = require("src.features.cyber-feud.troops").server()
      local atWar = troops and troops.atWar
      local interceptors = require("src.features.cyber-feud.interceptors").server()
      Brain.think(server, npc, dt, atWar and interceptors and interceptors.units or nil)
    end,
    wrecked = Brain.wrecked,
  }
end

--- One rig at (x, y), facing `angle`.
local function spawn(server, B, x, y, angle, name)
  local npc = B:spawnNpc(server, { name = name, x = x, y = y, angle = angle, brain = brainFor(), warRig = true })
  B:park(npc, false) -- the Overpass has no traffic, so it was born parked
  local vehicles = Features.byName.vehicles
  local model = require("src.features.vehicles.catalog").byKey[WarRigs.model]
  if vehicles and model then
    vehicles:serverSetModel(server, npc.car, model)
  end
  npc.car.maxSpeed = math.max(npc.car.maxSpeed, WarRigs.maxSpeed)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverSetCarMaxHealth then
    weapons:serverSetCarMaxHealth(server, npc.car, WarRigs.health)
  end
  sv.units[#sv.units + 1] = npc
  return npc
end

--- Park rigs on `map`'s `rigs` posts, and ready Kilowatt's ride if it has one.
function WarRigs.serverStart(server, map)
  WarRigs.serverStop(server)
  local B = bots()
  if not ((map.rigs or map.kilowatt) and B) then
    return
  end
  sv = { units = {}, time = 0 }
  local posts = map.rigs or {}
  local n = math.min(#posts, WarRigs.count + WarRigs.perHuman * (Bosses.humans(server) - 1))
  for i = 1, n do
    spawn(server, B, posts[i].x, posts[i].y, posts[i].angle, "War-rig " .. i)
  end
  if map.kilowatt then
    sv.cameo = { stage = "waiting", spec = map.kilowatt }
  end
  server:broadcast(Protocol.encode("RIG_UNITS", unpack(ids())))
end

function WarRigs.serverStop(server)
  if not sv then
    return
  end
  local B = bots()
  for _, npc in ipairs(sv.units) do
    if B and server.players[npc.id] then
      B:removeNpc(server, npc)
    end
  end
  sv = nil
  server:broadcast(Protocol.encode("RIG_UNITS"))
end

--- Kilowatt's rig: straight up its lane flat out, then into the barrier.
local function cameoScript(server, npc, dt)
  local c = sv.cameo
  c.t = c.t + dt
  local spec = c.spec
  if c.t < WarRigs.cameoFor then
    Brain.driveAt(npc, -math.pi / 2 + (spec.x - npc.car.x) * 0.004, WarRigs.cameoSpeed)
    npc.input.throttle = 1 -- whatever is ahead: he wants to be seen
    return
  end
  -- Into the barrier on the right, and he is off it just before it goes.
  npc.input.throttle, npc.input.steer = 1, 1
  if c.stage == "riding" then
    c.stage = "leaping"
    local car = npc.car
    local x1, y1 = car.x - 90, car.y - 40
    c.landX, c.landY, c.leapAt = x1, y1, c.t
    server:broadcast(Protocol.encode("KW_LEAP", ("%.0f"):format(car.x), ("%.0f"):format(car.y), ("%.0f"):format(x1),
      ("%.0f"):format(y1)))
  end
  if c.t > WarRigs.cameoFor + 0.5 and not npc.wreckedAt then
    local weapons = Features.byName.weapons
    if weapons and weapons.damageCar then
      weapons:damageCar(server, npc.car, nil, 1e6, 0, -math.pi / 2, "impact")
    end
  end
end

--- Start Kilowatt's ride: his rig behind everyone at the bottom of the road.
local function startCameo(server)
  local B = bots()
  local spec = sv.cameo.spec
  local npc = spawn(server, B, spec.x, spec.y, -math.pi / 2, "Kilowatt's rig")
  npc.script = cameoScript
  npc.cameo = true
  sv.cameo.stage, sv.cameo.t, sv.cameo.rig = "riding", 0, npc
  server:broadcast(Protocol.encode("RIG_UNITS", unpack(ids())))
  server:broadcast(Protocol.encode("KW_RIDE", npc.id))
end

local function stepCameo(server, dt)
  local c = sv.cameo
  if not c then
    return
  end
  if c.stage == "waiting" then
    local off = sv.time >= WarRigs.cameoAfter
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local _, y = Features.bodyPose(server, p)
        off = off or y < c.spec.startY
      end
    end
    if off then
      startCameo(server)
    end
  elseif c.stage == "leaping" and c.t >= (c.leapAt or 0) + WarRigs.leapTime + WarRigs.exitAfter then
    c.stage = "gone"
    server:broadcast(Protocol.encode("KW_EXIT", ("%.0f"):format(c.landX), ("%.0f"):format(c.landY),
      ("%.2f"):format(c.spec.exitAngle)))
  elseif c.stage == "leaping" then
    c.t = c.t + (c.rig.wreckedAt and dt or 0) -- the rig's script keeps the clock while it runs
  end
end

function WarRigs.serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  stepCameo(server, dt)
  local now = love.timer.getTime()
  local B = bots()
  for i = #sv.units, 1, -1 do
    local npc = sv.units[i]
    if npc.wreckedAt and not npc.paid then
      npc.paid = true
      local money = Features.byName.money
      if money and money.drop and not npc.cameo then
        money:drop(server, npc.car.x, npc.car.y, WarRigs.drops)
      end
    end
    if npc.wreckedAt and now - npc.wreckedAt >= WRECK_GONE then
      table.remove(sv.units, i)
      if B and server.players[npc.id] then
        B:removeNpc(server, npc)
      end
      server:broadcast(Protocol.encode("RIG_UNITS", unpack(ids())))
    end
  end
end

function WarRigs.serverPlayerJoined(server, player)
  if sv and not player.bot then
    server:send(player, Protocol.encode("RIG_UNITS", unpack(ids())))
  end
end

--- Is `player` one of them (for `serverHidden`)?
function WarRigs.isOne(player)
  return player.warRig == true
end

--- Kilowatt on his cameo, for the audit (tools/audit): riding his rig, then
--- on the road after the leap until he runs off the edge. He is not fought
--- here (nothing of his takes a round), so he can't be hurt. The rigs
--- themselves are bots, players' business, and left out.
function WarRigs.serverEnemies(_server, add)
  local c = sv and sv.cameo
  if not c or (c.stage ~= "riding" and c.stage ~= "leaping") then
    return
  end
  local x, y = c.landX, c.landY
  if c.stage == "riding" then
    x, y = c.rig.car.x, c.rig.car.y
  end
  local radius = require("src.features.cyber-feud.kilowatt").RADIUS
  add({ id = c, kind = "cyber-feud/kilowatt-cameo", x = x, y = y, radius = radius, immune = true })
end

--- For tests.
function WarRigs.server()
  return sv
end

-- Client --------------------------------------------------------------------

local units = {} -- player id -> true
local kw = nil -- { stage, rig, x, y, t, line, lineT, ... } Kilowatt, while he is in sight
local clock = 0

function WarRigs.clear()
  units, kw = {}, nil
end

--- Kilowatt says `key` (Story.kilowatt) over where he is.
local function shout(key, x, y)
  local text = Story.kilowatt[key]
  if kw and text then
    kw.line, kw.lineT = text, Radio.sayTime(text)
    Radio.play(text, x, y, true)
  end
end

function WarRigs.update(dt, client)
  clock = clock + dt
  if not kw then
    return
  end
  kw.t = kw.t + dt
  if kw.lineT then
    kw.lineT = kw.lineT - dt
    if kw.lineT <= 0 then
      kw.line = nil
    end
  end
  if kw.stage == "riding" then
    local c = client:vehicleOf(kw.rig)
    if c then
      kw.x, kw.y, kw.angle = c.dx - math.cos(c.dangle) * 16, c.dy - math.sin(c.dangle) * 16, c.dangle
    end
  elseif kw.stage == "leaping" then
    local k = math.min(1, kw.t / WarRigs.leapTime)
    kw.x, kw.y = kw.x0 + (kw.x1 - kw.x0) * k, kw.y0 + (kw.y1 - kw.y0) * k
    kw.lift = math.sin(math.pi * k) * 40
    if k >= 1 and not kw.landed then
      kw.landed, kw.lift = true, 0
      shout("land", kw.x, kw.y)
    end
  elseif kw.stage == "exit" then
    local run = 220 * dt
    kw.x, kw.y = kw.x + math.cos(kw.angle) * run, kw.y + math.sin(kw.angle) * run
    kw.lift = math.max(0, math.sin(math.min(1, kw.t / 0.9) * math.pi) * 50)
    kw.scale = math.max(0.1, 1 - math.max(0, kw.t - 0.6) * 0.9) -- falling away, far below
    if kw.t > 1.6 then
      kw = nil
    end
  end
end

--- The ram, the plates, the cyan lamp, and the ganger on the back.
local function drawRig(c)
  love.graphics.push()
  love.graphics.translate(c.dx, c.dy)
  love.graphics.rotate(c.dangle)
  love.graphics.setColor(CHROME)
  love.graphics.rectangle("fill", 26, -12, 4, 24, 1)
  for i = -1, 1 do -- the spikes
    love.graphics.polygon("fill", 30, i * 9 - 3.5, 30, i * 9 + 3.5, 39, i * 9)
  end
  love.graphics.setColor(RUST)
  love.graphics.rectangle("fill", -6, -12, 14, 3, 1) -- plates welded down its flanks
  love.graphics.rectangle("fill", -6, 9, 14, 3, 1)
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * math.abs(math.sin(clock * 3)))
  love.graphics.circle("fill", 10, 0, 2.5, 8)
  Body.person(-18, 0, 0, 0, GANGER) -- riding on the back
  love.graphics.pop()
end

--- Kilowatt: huge, a mohawk of cables with glowing tips, chrome shoulders
--- and jaw, a reactor in his chest pulsing cyan. Drawn twice as big as anyone.
local function drawKilowatt()
  local s = 2.2 * (kw.scale or 1)
  love.graphics.push()
  love.graphics.translate(kw.x, kw.y - (kw.lift or 0))
  love.graphics.scale(s)
  if (kw.lift or 0) > 2 then
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", 0, (kw.lift or 0) / s, 8, 6, 12)
  end
  Body.person(0, 0, kw.angle or -math.pi / 2, math.sin(kw.t * 14) * (kw.stage == "exit" and 1.8 or 0), {
    shirt = { 0.20, 0.22, 0.24 }, pants = { 0.14, 0.14, 0.16 }, skin = { 0.48, 0.35, 0.27 },
    hair = { 0.13, 0.15, 0.17 }, shoes = { 0.06, 0.06, 0.07 },
  })
  love.graphics.rotate(kw.angle or -math.pi / 2)
  love.graphics.setColor(CHROME)
  love.graphics.ellipse("fill", 0, -7.5, 3.2, 2.4, 10) -- the shoulders
  love.graphics.ellipse("fill", 0, 7.5, 3.2, 2.4, 10)
  love.graphics.rectangle("fill", 3, -2, 2, 4, 0.6) -- the jaw
  local pulse = 0.55 + 0.45 * math.abs(math.sin(clock * 5))
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], pulse)
  love.graphics.circle("fill", 2, 0, 2.6, 10) -- the reactor, through the cage
  love.graphics.setColor(0.13, 0.15, 0.17)
  love.graphics.setLineWidth(1.2)
  for i = -2, 2 do -- the cables of his mohawk, a glowing tip on each
    love.graphics.line(-1, i * 1.1, -4.6 + math.abs(i) * 0.5, i * 1.6)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(CYAN)
  for i = -2, 2 do
    love.graphics.circle("fill", -4.6 + math.abs(i) * 0.5, i * 1.6, 0.8, 6)
  end
  love.graphics.pop()
end

function WarRigs.drawAboveCars(client)
  for id in pairs(units) do
    local c = client:vehicleOf(id)
    if c and not c.hidden then
      drawRig(c)
    end
  end
  if kw then
    drawKilowatt()
    if kw.line then
      Hud.drawBubble(kw.x, kw.y - 40 - (kw.lift or 0), kw.line, math.min(1, kw.lineT * 2), CYAN)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function WarRigs.drawNightLights(client, glow)
  for id in pairs(units) do
    local c = client:vehicleOf(id)
    if c and not c.hidden then
      glow(c.dx + math.cos(c.dangle) * 10, c.dy + math.sin(c.dangle) * 10, 50, CYAN, 0.5)
    end
  end
  if kw then -- his reactor lights him up, and the road round him
    glow(kw.x, kw.y - (kw.lift or 0), 120 * (kw.scale or 1), CYAN, 0.95)
  end
end

WarRigs.clientMessages = {
  RIG_UNITS = function(_client, args)
    units = {}
    for _, a in ipairs(args) do
      local id = tonumber(a)
      if id then
        units[id] = true
      end
    end
  end,
  KW_RIDE = function(client, args)
    local id = tonumber(args[1])
    local c = id and client:vehicleOf(id)
    kw = { stage = "riding", rig = id, x = c and c.dx or 0, y = c and c.dy or 0, t = 0 }
    shout("ride", kw.x, kw.y)
  end,
  KW_LEAP = function(_client, args)
    local x0, y0, x1, y1 = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if kw and x0 and y1 then
      kw.stage, kw.t, kw.x0, kw.y0, kw.x1, kw.y1 = "leaping", 0, kw.x or x0, kw.y or y0, x1, y1
      kw.angle = math.atan2(y1 - y0, x1 - x0)
    end
  end,
  KW_EXIT = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if kw and x and angle then
      kw.stage, kw.t, kw.x, kw.y, kw.angle = "exit", 0, x, y, angle
      shout("exit", x, y)
    end
  end,
}

return WarRigs
