-- Halcyon's watcher drones (docs/cyber-feud.md, "Halcyon"): small flying
-- discs with a magenta eye and no gun, on beats over the Market's stalls
-- and down Halcyon Tower's aisles, where walls hide you from them (the
-- brain's `indoors`) (the map's `watchers`). troops.lua starts, steps and stops them with the
-- rest of Halcyon, and passes rounds on to them; their heads are
-- watcher_brain.lua.
--
-- A watcher sees over the stalls. When a player is in its cone it stops
-- over them and calls them in: Halcyon's nearest few officers not holding
-- a post (`callAnswer`, within `callHeard`) come to look, again every few
-- seconds while it still has them. Shoot it down (it has little health,
-- but it is quick), or get out of its cone. An EMP knocks it out
-- (`serverEmp`, the Static's sparkers): it sinks and goes dark for a few
-- seconds. In the feud they are the sparkers' `rivals`, and only the
-- sparkers': the factions' rounds pass under them, up there (shot at by
-- the gangers, or caught by the strays of the fights below, they were gone
-- before any player got near). A player's rounds bring them down.
--
-- Messages
--   server -> all  WCH_STATE <tick> (<id> <x> <y> <facing> <hp> <state>)...
--                  (unreliable, 15 Hz; state 0 on its beat, 1 has somebody, 2 knocked out)
--   server -> all  WCH_CALL  <id> <x> <y>    one called somebody in, seen at (x, y)
--   server -> all  WCH_DOWN  <id> <x> <y>    one was shot down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Brain = require("src.features.cyber-feud.watcher_brain")
local Rooms = require("src.features.cyber-feud.rooms")

local Watchers = {}

-- Tuning ------------------------------------------------------------------
Watchers.health = 20
Watchers.fov = math.rad(70)
Watchers.callHeard = 1100 -- px; Halcyon's officers this near whoever it saw may come
Watchers.callAnswer = 3 -- of them at most, nearest first
Watchers.empTime = 5 -- seconds an EMP knocks one out
Watchers.drops = 4 -- koins one spills
Watchers.firstId = 14001

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 12
local SNAP = 200
local STALE = 1
local HURT = 0.18
local CALL_SHOWN = 1.0 -- seconds a call's ping spreads
local LIFT = 14 -- px the drone is drawn above its shadow
local STATE_CODE = { 0, 1, 2 }

local MAGENTA = { 1.00, 0.24, 0.78 }
local CASING = { 0.62, 0.64, 0.68 }
local DARK = { 0.20, 0.21, 0.24 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

--- Somebody seen at (x, y): Halcyon's nearest officers on their feet go to look.
local function alarm(_server, _s, x, y)
  local troops = require("src.features.cyber-feud.troops").server()
  local halcyon = troops and troops.sides.halcyon
  if halcyon then
    halcyon.troops:alarm(x, y, Watchers.callHeard, { most = Watchers.callAnswer })
  end
end

function Watchers.serverStart(server, map, calm)
  Watchers.serverStop(server)
  if not map.watchers then
    return nil
  end
  local brain = Brain.new({
    fov = Watchers.fov, health = Bosses.enemyHealth(Watchers.health), alarm = alarm, firstId = Watchers.firstId,
    calm = calm, indoors = map.kind == "tower", sameRoom = Rooms.of(map),
  })
  for _, w in ipairs(map.watchers) do
    brain:add(w.route, w.start or 1)
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0 }
  return brain
end

function Watchers.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Watchers.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("WCH_STATE", server.tick))
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
    parts[#parts + 1] = s.stunned > 0 and STATE_CODE[3] or (s.target and STATE_CODE[2] or STATE_CODE[1])
  end
  local msg = Protocol.encode("WCH_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Watchers.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for _, s in ipairs(sv.brain.list) do
    if s.called then
      s.called = nil
      local p = s.target and server.players[s.target]
      local x, y = s.x, s.y
      if p then
        x, y = Features.bodyPose(server, p)
      end
      server:broadcast(Protocol.encode("WCH_CALL", s.id, fmt(x), fmt(y)))
    end
  end
  sync(server)
end

--- An EMP at (x, y): every watcher within `radius` is knocked out.
function Watchers.serverEmp(x, y, radius)
  if sv then
    sv.brain:stun(x, y, radius, Watchers.empTime)
  end
end

local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("WCH_DOWN", s.id, fmt(s.x), fmt(s.y)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Watchers.drops)
  end
  Features.call("serverKill", server, { kind = "drone", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
end

--- A round through (x, y): the `serverShotAt` convention. Only a
--- player's hits; the factions' pass under. Returns true when it hit one.
function Watchers.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.brain:at(x, y, radius)
  if not s then
    return false
  end
  if sv.brain:hurt(s, i, damage or 20) then
    down(server, s, by, angle, dtype)
  end
  return true, true
end

--- Every watcher in the air, for the audit (tools/audit). Outdoors it flies
--- over the stalls; indoors (the tower) it goes round what stands there.
function Watchers.serverEnemies(_server, add)
  for _, s in ipairs(sv and sv.brain.list or {}) do
    add({ id = s, kind = "cyber-feud/watcher", x = s.x, y = s.y, hp = s.hp, radius = Brain.RADIUS,
      flying = not sv.brain.indoors })
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Watchers.wikiEnemies(add)
  add({
    kind = "cyber-feud/watcher",
    name = "Watcher drone",
    quests = { "cyber-feud-market", "cyber-feud-tower" },
    where = "Over the Market's stalls, and in Halcyon Tower's lobby and offices",
    about = "A small flying disc with a magenta eye and no gun. It finds you, and Halcyon's officers come.",
    stats = {
      { "Health", Watchers.health },
      { "Speed", ("%g px/s on its beat, %g following somebody"):format(Brain.FLY, Brain.CHASE) },
      { "Sight", ("%g px, a %g degree cone, over the stalls"):format(Brain.RANGE, math.deg(Watchers.fov)) },
    },
    abilities = {
      ("Sees over walls outdoors; in the tower only who is in the same room. Seeing you, it hangs %g px off you and "
        .. "calls in up to %g of Halcyon's officers within %g px, again every %g s while it has you."):format(
        Brain.HOVER, Watchers.callAnswer, Watchers.callHeard, Brain.ALARM_EVERY),
      ("Out of its cone for %g s, you are gone and it flies back to its beat."):format(Brain.LOST_AFTER),
      ("A sparker's EMP knocks it out for %g s: it sinks and goes dark."):format(Watchers.empTime),
      "Only players' rounds reach it: the factions' pass under it.",
    },
    tips = {
      "Shoot it down before it calls: it has little health.",
      "Get out of its cone, or out of the room in the tower.",
    },
    drops = ("%g koins"):format(Watchers.drops),
  })
end

function Watchers.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Watchers.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, state, hurt, sink }
local calls = {} -- { x, y, t }
local lastTick, heardAt, clock = 0, 0, 0
local beep = nil

--- The call: two quick rising beeps, synthesised once.
function Watchers.load()
  local buf = Synth.newBuffer(0.36)
  buf:tone(0, 0.12, 1320, { wave = "square", amp = 0.3, decay = 0.1, sustain = 0.6 })
  buf:tone(0.16, 0.16, 1760, { wave = "square", amp = 0.3, decay = 0.12, sustain = 0.6 })
  buf:lowpass(4000)
  beep = love.audio.newSource(buf:toSoundData(0.7), "static")
  beep:setAttenuationDistances(300, 2200)
end

function Watchers.clear()
  shown, calls, lastTick = {}, {}, 0
end

function Watchers.update(dt)
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
    end
    s.hurt = math.max(0, s.hurt - dt)
    local sink = s.state == 2 and 1 or 0 -- knocked out, it drops low
    s.sink = s.sink + (sink - s.sink) * math.min(1, dt * 3)
  end
  for i = #calls, 1, -1 do
    calls[i].t = calls[i].t + dt
    if calls[i].t > CALL_SHOWN then
      table.remove(calls, i)
    end
  end
end

--- Their shadows on the ground and their cones. A drone sees over the
--- stalls, so its cone is a plain fan, not cut by the walls the way the
--- officers' are.
function Watchers.drawBelowCars()
  local cones = not Features.any("hideSightCones")
  for _, s in pairs(shown) do
    love.graphics.setColor(0, 0, 0, 0.3)
    love.graphics.ellipse("fill", s.dx + 3, s.dy + 3, 8, 6, 14)
    if cones and s.state ~= 2 then
      local half = Watchers.fov / 2
      local a = s.state == 1 and 0.16 or 0.08
      love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], a)
      love.graphics.arc("fill", s.dx, s.dy, Brain.RANGE, s.facing - half, s.facing + half, 24)
      love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], a * 2.5)
      love.graphics.arc("line", s.dx, s.dy, Brain.RANGE, s.facing - half, s.facing + half, 24)
    end
  end
end

local function drawDrone(s)
  local lift = LIFT * (1 - 0.7 * s.sink)
  local x, y = s.dx, s.dy - lift
  local out = s.state == 2
  love.graphics.push()
  love.graphics.translate(x, y)
  if out then
    love.graphics.rotate(math.sin(clock * 9 + s.dx) * 0.2) -- wobbling down
  end
  -- Four rotors, a blur round each.
  for k = 0, 3 do
    local a = k * math.pi / 2 + math.pi / 4
    local rx, ry = math.cos(a) * 8, math.sin(a) * 8
    love.graphics.setColor(DARK)
    love.graphics.line(0, 0, rx, ry)
    love.graphics.setColor(0.8, 0.82, 0.86, out and 0.15 or 0.35)
    love.graphics.circle("fill", rx, ry, 3.6, 10)
  end
  -- The disc.
  local c = s.hurt > 0 and { 1, 1, 1 } or CASING
  love.graphics.setColor(c)
  love.graphics.circle("fill", 0, 0, 5.5, 16)
  love.graphics.setColor(DARK)
  love.graphics.circle("line", 0, 0, 5.5, 16)
  -- The eye, on the side it looks out of.
  local ex, ey = math.cos(s.facing) * 3, math.sin(s.facing) * 3
  if out then
    love.graphics.setColor(0.15, 0.05, 0.12)
    love.graphics.circle("fill", ex, ey, 2, 8)
    if math.sin(clock * 23 + s.dx) > 0.7 then -- a spark now and then
      love.graphics.setColor(0.6, 1, 1)
      love.graphics.circle("fill", -ex, -ey, 1.2, 6)
    end
  else
    love.graphics.setColor(MAGENTA)
    love.graphics.circle("fill", ex, ey, s.state == 1 and 2.6 or 2, 8)
    love.graphics.setColor(1, 0.85, 0.95)
    love.graphics.circle("fill", ex, ey, 0.9, 6)
  end
  love.graphics.pop()
  if s.hp < s.top then
    local bw, f = 18, math.max(0, s.hp / s.top)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + 12, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + 13, bw * f, 2)
  end
end

--- Above everything on the ground: they fly.
function Watchers.drawAboveCars()
  for _, c in ipairs(calls) do
    local k = c.t / CALL_SHOWN
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.7 * (1 - k))
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", c.x, c.y, 20 + k * 160, 40)
    love.graphics.setLineWidth(1)
  end
  for _, s in pairs(shown) do
    drawDrone(s)
  end
  love.graphics.setColor(1, 1, 1)
end

function Watchers.drawNightLights(glow)
  for _, s in pairs(shown) do
    if s.state ~= 2 then
      glow(s.dx, s.dy - LIFT, s.state == 1 and 70 or 40, MAGENTA, s.state == 1 and 0.8 or 0.45)
    end
  end
end

Watchers.clientMessages = {
  WCH_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        if not s then
          s = { dx = x, dy = y, hurt = 0, sink = 0, hp = Watchers.health }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 3]) or s.facing or 0
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.top = math.max(s.top or Watchers.health, hp) -- (tougher on a job finished before)
        s.state = tonumber(args[i + 5]) or 0
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  WCH_CALL = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    calls[#calls + 1] = { x = x, y = y, t = 0 }
    local s = id and shown[id]
    if beep then
      local src = beep:clone()
      src:setPosition(s and s.dx or x, 0, s and s.dy or y)
      src:setPitch(0.97 + random() * 0.06)
      src:setVolume(0.5 * Audio.volume("weapons"))
      src:play()
    end
  end,
  WCH_DOWN = function(client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      local weapons = Features.byName.weapons
      if weapons and weapons.explosionAt then
        weapons:explosionAt(client, s and s.dx or x, s and s.dy or y, MAGENTA) -- a small pop of its battery
      end
    end
  end,
}

return Watchers
