-- Halcyon's enforcers (docs/cyber-feud.md, "Halcyon"): riot shields in the
-- Market's gates and on Halcyon Tower's security and executive floors (the
-- map's `enforcers`). troops.lua starts, steps and
-- stops them with the rest of Halcyon, and passes rounds on to them; their
-- heads are enforcer_brain.lua.
--
-- An enforcer holds his gate behind a riot shield that stops every round
-- from in front (a spark and a ping where it hits), turns slowly to face
-- whoever he has, steps up on them, and fires a shotgun up close. Get
-- round his side while he turns, or blow him up: blasts and fire go
-- through the shield. In the feud he is Halcyon: the Static are his
-- `rivals` and he is theirs, and his own side's rounds pass him by.
--
-- Messages
--   server -> all  ENF_STATE <tick> (<id> <x> <y> <facing> <hp> <alert> <fired>)...
--                  (unreliable, 15 Hz; alert 1 has somebody, 2 looking round, 0 neither)
--   server -> all  ENF_BLOCK <x> <y> <angle>   a round stopped by a shield, where and going which way
--   server -> all  ENF_DOWN  <id> <x> <y> <angle>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Sight = require("src.features.d-day.sight")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Corpses = require("src.features.corpses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Brain = require("src.features.cyber-feud.enforcer_brain")

local Enforcers = {}

-- Tuning ------------------------------------------------------------------
Enforcers.health = 120 -- an officer has 60
Enforcers.fov = math.rad(70)
Enforcers.alertFov = math.rad(110)
Enforcers.aware = 160 -- px all round he hears somebody in
Enforcers.pause = 1.4 -- seconds between pulls of his shotgun
Enforcers.pellet = 9 -- per pellet, six a pull (a player's common shotgun: 11)
Enforcers.drops = 6 -- koins one spills (an officer 3)
Enforcers.firstId = 9001

local SYNC_EVERY = 2 -- server ticks between ENF_STATE
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local FLASH = 0.12 -- seconds a muzzle flash shows
local HURT = 0.18 -- seconds one flashes after a hit
local SPARK_TIME = 0.35 -- seconds a shield spark lasts

local MAGENTA = { 1.00, 0.24, 0.78 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

--- His shotgun: a player's common one, a little lighter per pellet, pumped slower.
local function arms()
  local base = Tiers.apply(Guns.shotgun, Tiers.DEFAULT)
  local gun = setmetatable({ damage = Enforcers.pellet }, { __index = base })
  return { gun = gun, pause = Enforcers.pause, reach = base.speed * base.ttl * 0.9 }
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

--- Put an enforcer on each of `map`'s `enforcers` posts, calm while `calm`.
--- Returns the brain (for the other side's `rivals`), or nil on a map without them.
function Enforcers.serverStart(server, map, calm)
  Enforcers.serverStop(server)
  if not map.enforcers then
    return nil
  end
  local brain = Brain.new({
    fov = Enforcers.fov, alertFov = Enforcers.alertFov, aware = Enforcers.aware, health = Enforcers.health,
    from = "halcyon", firstId = Enforcers.firstId, calm = calm,
  })
  for _, p in ipairs(map.enforcers) do
    brain:add(p.x, p.y, p.watch, arms())
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0 }
  return brain
end

function Enforcers.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Enforcers.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("ENF_STATE", server.tick))
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.brain.list
  if #list == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { server.tick }
  for _, s in ipairs(list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.target and 1 or (Brain.wary(s) and 2 or 0)
    parts[#parts + 1] = s.firedSince and 1 or 0
    s.firedSince = false
  end
  local msg = Protocol.encode("ENF_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Enforcers.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for _, s in ipairs(sv.brain.list) do
    s.firedSince = s.firedSince or s.fired
  end
  sync(server)
end

--- One down: his body on every screen, koins, maybe a pickup.
local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("ENF_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Enforcers.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
end

--- A round through (x, y): the `serverShotAt` convention. A player's, or
--- one carrying another side's name (`from`), hits; Halcyon's own pass by.
--- The shield takes one from in front (and the round is spent on it).
--- Returns true when it hit one, and whether a player's round did.
function Enforcers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  if not sv then
    return false
  end
  if by == 0 and (from == nil or from == "halcyon") then
    return false
  end
  local s, i = sv.brain:at(x, y, radius)
  if not s then
    return false
  end
  if Brain.blocks(s, angle, dtype) then
    local bx, by2 = s.x + math.cos(s.facing) * Brain.RADIUS, s.y + math.sin(s.facing) * Brain.RADIUS
    server:broadcast(Protocol.encode("ENF_BLOCK", fmt(bx), fmt(by2), ("%.2f"):format(angle)))
    sv.brain:hurt(s, i, 0, angle) -- he still knows where it came from
    return true, by ~= 0
  end
  if sv.brain:hurt(s, i, damage or 20, angle) then
    down(server, s, by ~= 0 and by or nil, angle, dtype)
  end
  return true, by ~= 0
end

function Enforcers.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Enforcers.serverPanicArea(x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius)
  end
end

--- For tests.
function Enforcers.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, alert, wary, stride, flash, hurt }
local sparks = {} -- { x, y, angle, t }
local lastTick, heardAt, clock = 0, 0, 0
local ping = nil -- the shield's ping, a base Source

-- Darker grey than an officer, the same white helmet; the shield is drawn over him.
local LOOK = {
  shirt = { 0.34, 0.35, 0.39 }, pants = { 0.18, 0.19, 0.21 }, vest = { 0.44, 0.45, 0.50 },
  shoes = { 0.06, 0.06, 0.07 }, skin = { 0.78, 0.68, 0.60 }, hat = { 0.88, 0.89, 0.92 }, gun = true, gunLength = 13,
}

--- The ping of a round off a shield, synthesised once.
function Enforcers.load()
  local buf = Synth.newBuffer(0.22)
  buf:tone(0, 0.2, 2350, { wave = "sine", amp = 0.5, decay = 0.05, sustain = 0 })
  buf:tone(0, 0.16, 3420, { wave = "sine", amp = 0.3, decay = 0.03, sustain = 0 })
  buf:noiseBurst(0, 0.03, { amp = 0.6, decay = 0.01 })
  buf:highpass(900)
  ping = love.audio.newSource(buf:toSoundData(0.8), "static")
  ping:setAttenuationDistances(260, 2000)
end

function Enforcers.clear()
  shown, sparks, lastTick = {}, {}, 0
end

function Enforcers.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
      s.stride = s.stride + math.sqrt(ex * ex + ey * ey) * k
    end
    s.flash = math.max(0, s.flash - dt)
    s.hurt = math.max(0, s.hurt - dt)
  end
  for i = #sparks, 1, -1 do
    sparks[i].t = sparks[i].t + dt
    if sparks[i].t > SPARK_TIME then
      table.remove(sparks, i)
    end
  end
end

--- Their cones, on the ground, in Halcyon's magenta (unless the toggle hides them).
function Enforcers.drawBelowCars()
  if Features.any("hideSightCones") then
    return
  end
  for id, s in pairs(shown) do
    local fov = s.wary and Enforcers.alertFov or Enforcers.fov
    Sight.draw(s.dx, s.dy, s.facing, Brain.RANGE, s.alert, clock, fov, { seed = id, color = MAGENTA })
  end
end

--- The riot shield: a curved slab in front of him, dark glass with a magenta rim.
local function drawShield(s)
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy)
  love.graphics.rotate(s.facing)
  local hot = s.hurt > 0 and 0.35 or 0
  love.graphics.setColor(0.12 + hot, 0.13 + hot, 0.17 + hot, 0.95)
  love.graphics.setLineWidth(5)
  love.graphics.arc("line", "open", -1, 0, 12.5, -1.15, 1.15, 14)
  love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], s.alert and 1 or 0.8)
  love.graphics.setLineWidth(1.6)
  love.graphics.arc("line", "open", -1, 0, 15.2, -1.15, 1.15, 14)
  love.graphics.setLineWidth(1)
  love.graphics.pop()
end

function Enforcers.drawAboveCars()
  for _, s in pairs(shown) do
    Body.person(s.dx, s.dy, s.facing, math.sin(s.stride * 0.18) * 0.8, LOOK)
    if s.flash > 0 then
      local mx, my = s.dx + math.cos(s.facing) * 20, s.dy + math.sin(s.facing) * 20
      love.graphics.setColor(1, 0.85, 0.5, s.flash / FLASH)
      love.graphics.circle("fill", mx, my, 5, 10)
    end
    drawShield(s)
    local r = Body.SHOULDERS
    if s.alert then
      love.graphics.setFont(require("src.ui").fonts.heading)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.printf("!", s.dx - 19, s.dy - r - 30, 40, "center")
      love.graphics.setColor(MAGENTA)
      love.graphics.printf("!", s.dx - 20, s.dy - r - 31, 40, "center")
    end
    if s.hp < Enforcers.health then
      local bw, f = 24, math.max(0, s.hp / Enforcers.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 5, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 6, bw * f, 2)
    end
  end
  for _, p in ipairs(sparks) do -- rounds glancing off: a fan of sparks thrown back
    local k = p.t / SPARK_TIME
    love.graphics.setColor(1, 0.9, 0.7, 1 - k)
    for n = -2, 2 do
      local a = p.angle + math.pi + n * 0.35
      local d0, d1 = 3 + k * 10, 6 + k * 22
      love.graphics.line(p.x + math.cos(a) * d0, p.y + math.sin(a) * d0, p.x + math.cos(a) * d1, p.y + math.sin(a) * d1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- At night, the shield's rim glows a little.
function Enforcers.drawNightLights(glow)
  for _, s in pairs(shown) do
    glow(s.dx + math.cos(s.facing) * 12, s.dy + math.sin(s.facing) * 12, 44, MAGENTA, s.alert and 0.7 or 0.45)
  end
  for _, p in ipairs(sparks) do
    glow(p.x, p.y, 40, { 1, 0.85, 0.6 }, 0.8 * (1 - p.t / SPARK_TIME))
  end
end

function Enforcers.walkers()
  local list = {}
  for id, s in pairs(shown) do
    list[#list + 1] = { key = "enf" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

Enforcers.clientMessages = {
  ENF_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        if not s then
          s = { dx = x, dy = y, stride = 0, flash = 0, hurt = 0, hp = Enforcers.health }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 3]) or s.facing or 0
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.alert = args[i + 5] == "1"
        s.wary = args[i + 5] ~= "0"
        if args[i + 6] == "1" then
          s.flash = FLASH
        end
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  ENF_BLOCK = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (x and y and angle) then
      return
    end
    sparks[#sparks + 1] = { x = x, y = y, angle = angle, t = 0 }
    if ping then
      local s = ping:clone()
      s:setPosition(x, 0, y)
      s:setPitch(0.9 + random() * 0.25)
      s:setVolume(0.6 * Audio.volume("weapons"))
      s:play()
    end
  end,
  ENF_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, LOOK)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.85)
      end
    end
  end,
}

return Enforcers
