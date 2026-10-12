-- Director Saye, Halcyon's boss (docs/cyber-feud.md, "Director Saye"), on
-- the Roof: calm, precise, a grey suit over the best hardware money can
-- buy. She waits by the billboard (the map's `bosses.saye`) until the roof
-- wakes, then fights at range: her sightline, three executive drones round
-- her, and sentry turrets she drops and walks away from. This module is
-- the woman (her numbers, lines, body and drones), the wire and how she
-- looks; what she does is her brain's (saye_brain.lua). troops.lua starts,
-- steps and stops her with the rest and passes rounds on to her; while she
-- is up the Roof isn't done (init.lua asks `serverUp`).
--
-- Like every boss (bosses/init.lua) she has breath, scales with the humans
-- (her health), has the boss bar (the second row, over Kilowatt's), goes
-- for medkits when badly hurt, dodges abilities, and going down raises
-- `serverKill` "boss", spills koins and a pickup or two. Only players'
-- rounds reach her or her drones.
--
-- Messages
--   server -> all  SYE_STATE <tick> <x> <y> <facing> <hp> <max> <aiming> <aim> <phase2> <stamina> <winded>
--                  [<drone x> <drone y>]...  (unreliable, 15 Hz; aiming 1 while her sightline is up, 2 for its
--                  last moment; empty (just the tick) once she is gone)
--   server -> all  SYE_SAY   <line>              she says Saye.lines[line]
--   server -> all  SYE_SHOT                      her pistol (the crack, the flash)
--   server -> all  SYE_DRONE <x> <y>             one of her drones was shot down
--   server -> all  SYE_DOWN  <x> <y> <angle>     she went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Radio = require("src.features.a-man.radio")
local Hud = require("src.features.cyber-feud.hud")
local Turrets = require("src.features.cyber-feud.turrets")

local Saye = {}
Saye.__index = Saye

local Brain -- her brain, required at the bottom: it reads her numbers

-- Tuning --------------------------------------------------------------------

Saye.HEALTH = 2000 -- for one player (more humans, more: bosses/init.lua)
Saye.RADIUS = 11 -- px
Saye.WALK = 70 -- px/s: she never runs...
Saye.WALK_2 = 95 -- ...but in phase 2 she walks faster
Saye.STROLL = 38 -- px/s winded
Saye.BREATH = { drain = 8, regen = 14, recovered = 50, breath = 40 } -- (bosses/stamina.lua)
Saye.RANGE = 760 -- px she sees
Saye.KEEP = 420 -- px she keeps between herself and whoever she has
Saye.AIM = 1.0 -- seconds her sightline shows before the shot...
Saye.AIM_2 = 0.5 -- ...in phase 2
Saye.SIGHT_EVERY = 3.2 -- seconds from one shot to the next line...
Saye.SIGHT_EVERY_2 = 2.4 -- ...in phase 2
Saye.SHOT_DAMAGE = 45 -- one heavy round
Saye.SHOT_SPEED = 1800 -- px/s
Saye.V = 0.16 -- radians either side of the line, her phase-2 pair
Saye.DRONES = 3 -- executive drones round her
Saye.DRONE_HEALTH = 30
Saye.DRONE_ORBIT = 50 -- px from her
Saye.DRONE_RANGE = 520 -- px they shoot out to
Saye.DRONE_DAMAGE = 5
Saye.DRONE_EVERY = 1.7 -- seconds between a drone's bursts of two
Saye.DRONES_BACK = 12 -- seconds after losing drones before she calls the rest back up
Saye.TURRET_EVERY = 14 -- seconds between turrets
Saye.TURRET_COST = 25 -- breath
Saye.TURRETS_MAX = 3 -- of hers up at once
Saye.LEAVE = 2.5 -- seconds she walks away from a turret she dropped
Saye.SAY_EVERY = { 8, 13 }
Saye.DROPS = 40
Saye.PICKUPS = 2

--- What she says (docs/cyber-feud.md, "Voice"), and which is which.
Saye.lines = {
  "You've been let go.",
  "Let's take this offline.",
  "I'm afraid your position has been made redundant.",
  "Security, please escort the contractor. Permanently.",
  "We'll circle back to you.",
  "This is coming out of your severance.",
  "Noted.",
  "Ah. The contractor. You're late.",
  "Drones. Re-onboard.",
  "Restructuring.",
  "A minor write-down.",
}
Saye.LINE = { intro = 8, taunt = { 1, 2, 3, 4, 5 }, phase2 = 6, down = 7, drones = 9, turret = 10, heal = 11 }

local MAGENTA = { 1.00, 0.24, 0.78 }
local HOT = { 1.00, 0.70, 0.92 }
local LOOK = {
  shirt = { 0.42, 0.45, 0.48 }, pants = { 0.36, 0.38, 0.41 }, shoes = { 0.08, 0.08, 0.09 },
  skin = { 0.87, 0.84, 0.81 }, hair = { 0.91, 0.91, 0.93 }, gun = true, gunLength = 14,
}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The woman -------------------------------------------------------------------

--- Her, at (x, y), with `hp`, finding her way round on `nav`.
function Saye.new(x, y, hp, nav)
  local s = setmetatable({
    x = x,
    y = y,
    facing = math.pi / 2,
    aim = math.pi / 2,
    hp = hp,
    max = hp,
    nav = nav,
    time = 0,
    aiming = false,
    aimT = 0,
    sightIn = 2,
    turretIn = 8,
    sayIn = 6,
    frozen = 0,
    stuck = 0,
    phase2 = false,
    drones = {},
    dronesIn = 0,
    turrets = {},
    breath = Stamina.new(Saye.BREATH),
    running = false,
    mode = "hunt",
  }, Saye)
  s:callDrones()
  return s
end

local function fits(x, y)
  local r = Saye.RADIUS
  return not (Sight.blocked(x, y) or Sight.blocked(x - r, y) or Sight.blocked(x + r, y)
    or Sight.blocked(x, y - r) or Sight.blocked(x, y + r))
end

function Saye:walk(angle, speed, dt)
  local mx, my = math.cos(angle) * speed * dt, math.sin(angle) * speed * dt
  if fits(self.x + mx, self.y + my) then
    self.x, self.y = self.x + mx, self.y + my
  elseif fits(self.x + mx, self.y) then
    self.x = self.x + mx
  elseif fits(self.x, self.y + my) then
    self.y = self.y + my
  else
    self.stuck = self.stuck + dt
    return
  end
  self.stuck = 0
end

function Saye:pace()
  return self.breath:pace(self.phase2 and Saye.WALK_2 or Saye.WALK, Saye.STROLL)
end

--- Her drones back up to DRONES.
function Saye:callDrones()
  for i = #self.drones + 1, Saye.DRONES do
    self.drones[i] = { hp = Saye.DRONE_HEALTH, fireIn = 1 + i * 0.4, burst = 0, x = self.x, y = self.y }
  end
end

local gun = nil
local droneGun = nil

--- One heavy round from her pistol along `aim`.
function Saye:fire(server, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  if not gun then
    local base = Tiers.apply(Guns.ak47, Tiers.DEFAULT)
    gun = setmetatable({ damage = Saye.SHOT_DAMAGE, speed = Saye.SHOT_SPEED, ttl = 0.6, spread = 0, streak = 34,
      tint = "ff3ec8" }, { __index = base })
  end
  weapons:serverFireFrom(server, 0, self.x + math.cos(aim) * 20, self.y + math.sin(aim) * 20, aim, gun, "halcyon")
end

--- Her drones: round her, each firing short bursts at the nearest player
--- it can see; lost ones come back after a while.
function Saye:stepDrones(server, dt, events)
  local n = #self.drones
  for i, d in ipairs(self.drones) do
    local a = self.time * 1.7 + i * 2 * math.pi / math.max(1, n)
    d.x, d.y = self.x + math.cos(a) * Saye.DRONE_ORBIT, self.y + math.sin(a) * Saye.DRONE_ORBIT
    d.fireIn = d.fireIn - dt
    if d.fireIn <= 0 then
      local best, bx, by, bestD2 = nil, nil, nil, Saye.DRONE_RANGE ^ 2
      for _, p in pairs(server.players) do
        if Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          local d2 = dist2(x, y, d.x, d.y)
          if d2 < bestD2 and Sight.clear(d.x, d.y, x, y) then
            best, bx, by, bestD2 = p, x, y, d2
          end
        end
      end
      if best then
        local weapons = Features.byName.weapons
        if not droneGun then
          local base = Tiers.apply(Guns.uzi, Tiers.DEFAULT)
          droneGun = setmetatable({ damage = Saye.DRONE_DAMAGE, tint = "ff3ec8", spread = 0.06 }, { __index = base })
        end
        local aim = math.atan2(by - d.y, bx - d.x)
        if weapons and weapons.serverFireFrom then
          local mx, my = d.x + math.cos(aim) * 10, d.y + math.sin(aim) * 10
          weapons:serverFireFrom(server, 0, mx, my, aim, droneGun, "halcyon")
        end
        d.burst = d.burst + 1
        d.fireIn = d.burst % 2 == 1 and 0.14 or Saye.DRONE_EVERY
      else
        d.fireIn = 0.3
      end
    end
  end
  if #self.drones < Saye.DRONES then
    self.dronesIn = self.dronesIn - dt
    if self.dronesIn <= 0 then
      self:callDrones()
      events[#events + 1] = { "say", Saye.LINE.drones }
    end
  end
end

--- How many of the turrets she dropped are still up.
function Saye:turretsUp()
  local n = 0
  for i = #self.turrets, 1, -1 do
    if self.turrets[i].hp > 0 then
      n = n + 1
    else
      table.remove(self.turrets, i)
    end
  end
  return n
end

-- Server --------------------------------------------------------------------

local sv = nil -- { s, awake, greet, syncIn, down }

function Saye.serverStart(server, map, nav, calm)
  Saye.serverStop(server)
  local spot = map.bosses and map.bosses.saye
  if not spot then
    return
  end
  sv = { s = Saye.new(spot.x, spot.y, Bosses.health(Saye.HEALTH, server), nav), awake = not calm, syncIn = 0 }
end

function Saye.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("SYE_STATE", server.tick))
  end
end

function Saye.serverWake()
  if sv and not sv.awake then
    sv.awake, sv.greet = true, true
  end
end

--- Is she still up (the Roof isn't done while she is)?
function Saye.serverUp()
  return sv ~= nil and not sv.down
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local s = sv.s
  local stamina, winded = s.breath:wire()
  local aiming = 0
  if s.aiming then
    aiming = s.aimT > (s.phase2 and Saye.AIM_2 or Saye.AIM) - 0.25 and 2 or 1
  end
  local parts = { server.tick, ("%.0f"):format(s.x), ("%.0f"):format(s.y), ("%.2f"):format(s.facing),
    ("%.0f"):format(math.max(0, s.hp)), ("%.0f"):format(s.max), aiming, ("%.3f"):format(s.aim), s.phase2 and 1 or 0,
    stamina, winded }
  for _, d in ipairs(s.drones) do
    parts[#parts + 1] = ("%.0f"):format(d.x)
    parts[#parts + 1] = ("%.0f"):format(d.y)
  end
  local msg = Protocol.encode("SYE_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Saye.serverStep(server, dt)
  if not sv or sv.down then
    return
  end
  if sv.greet then
    sv.greet = false
    server:broadcast(Protocol.encode("SYE_SAY", Saye.LINE.intro))
  end
  if sv.awake then
    for _, e in ipairs(Brain.think(sv.s, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("SYE_SAY", e[2]))
      elseif e[1] == "shot" then
        server:broadcast(Protocol.encode("SYE_SHOT"))
      elseif e[1] == "turret" then
        local t = Turrets.serverJoin(e[2], e[3], e[4], 2 * math.pi)
        if t then
          sv.s.turrets[#sv.s.turrets + 1] = t
        end
      end
    end
  end
  sync(server)
end

local function down(server, by, angle)
  local s = sv.s
  sv.down = true
  server:broadcast(Protocol.encode("SYE_SAY", Saye.LINE.down))
  server:broadcast(Protocol.encode("SYE_DOWN", ("%.0f"):format(s.x), ("%.0f"):format(s.y), ("%.3f"):format(angle or 0)))
  server:broadcast(Protocol.encode("SYE_STATE", server.tick + 1))
  for _, d in ipairs(s.drones) do -- her drones drop with her
    server:broadcast(Protocol.encode("SYE_DRONE", ("%.0f"):format(d.x), ("%.0f"):format(d.y)))
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Saye.DROPS)
  end
  local pickups = Features.byName.pickups
  for _ = 1, Saye.PICKUPS do
    if pickups and pickups.serverDropEnemy then
      pickups:serverDropEnemy(server, s.x + random(-40, 40), s.y + random(-40, 40))
    end
  end
  Features.call("serverKill", server, { kind = "boss", x = s.x, y = s.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches her or her drones. Returns true when it hit.
function Saye.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local s = sv.s
  for i, d in ipairs(s.drones) do
    if dist2(x, y, d.x, d.y) <= (8 + (radius or 0)) ^ 2 then
      d.hp = d.hp - (damage or 20)
      if d.hp <= 0 then
        table.remove(s.drones, i)
        s.dronesIn = Saye.DRONES_BACK
        server:broadcast(Protocol.encode("SYE_DRONE", ("%.0f"):format(d.x), ("%.0f"):format(d.y)))
        Features.call("serverKill", server, { kind = "drone", x = d.x, y = d.y, by = by, angle = angle })
      end
      return true
    end
  end
  if dist2(x, y, s.x, s.y) > (Saye.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  if not sv.awake then
    require("src.features.cyber-feud.troops").serverWake()
  end
  s.hp = s.hp - (damage or 20)
  if s.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

function Saye.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.s.x, sv.s.y) <= radius * radius then
    sv.s.frozen = math.max(sv.s.frozen, seconds)
  end
end

--- For tests.
function Saye.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil -- { x, y, dx, dy, facing, hp, max, aiming, aim, phase2, stamina, winded, drones, flash }
local say = nil
local lastTick, heardAt, clock = 0, 0, 0

function Saye.clear()
  shown, say, lastTick = nil, nil, 0
end

--- Is she up, as far as this screen knows (the objective line)?
function Saye.up()
  return shown ~= nil
end

function Saye.update(dt)
  clock = clock + dt
  if shown and love.timer.getTime() - heardAt > 1.5 then
    shown = nil
  end
  if shown then
    local k = math.min(1, dt * 14)
    local ex, ey = shown.x - shown.dx, shown.y - shown.dy
    if ex * ex + ey * ey > 300 * 300 then
      shown.dx, shown.dy = shown.x, shown.y
    else
      shown.dx, shown.dy = shown.dx + ex * k, shown.dy + ey * k
      shown.stride = shown.stride + math.sqrt(ex * ex + ey * ey) * k
    end
    shown.flash = math.max(0, (shown.flash or 0) - dt)
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

--- Her sightline: thin while it holds, bright for its last moment.
local function drawLine(s)
  if s.aiming == 0 then
    return
  end
  local aims = s.phase2 and { s.aim - Saye.V, s.aim + Saye.V } or { s.aim }
  for _, a in ipairs(aims) do
    local x1, y1 = Sight.reach(s.dx, s.dy, a, 1400)
    if s.aiming == 2 then
      local pulse = 0.6 + 0.4 * math.abs(math.sin(clock * 30))
      love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.35 * pulse)
      love.graphics.setLineWidth(5)
      love.graphics.line(s.dx, s.dy, x1, y1)
      love.graphics.setColor(HOT[1], HOT[2], HOT[3], pulse)
      love.graphics.setLineWidth(1.5)
    else
      love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.5)
      love.graphics.setLineWidth(1)
    end
    love.graphics.line(s.dx, s.dy, x1, y1)
  end
  love.graphics.setLineWidth(1)
end

--- An executive drone: a dark disc with a magenta ring, hovering.
local function drawDrone(x, y)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", x + 4, y + 6, 6, 4, 10)
  love.graphics.setColor(0.16, 0.16, 0.19)
  love.graphics.circle("fill", x, y - 12, 6, 12)
  love.graphics.setColor(MAGENTA)
  love.graphics.setLineWidth(1.4)
  love.graphics.circle("line", x, y - 12, 6, 12)
  love.graphics.setLineWidth(1)
  love.graphics.circle("fill", x, y - 12, 1.8, 8)
end

function Saye.drawAboveCars()
  if not shown then
    return
  end
  local s = shown
  drawLine(s)
  local angle = s.aiming > 0 and s.aim or s.facing
  local walk = s.aiming == 0 and math.sin(s.stride * 0.2) * 1.2 or 0
  Body.person(s.dx, s.dy, angle, walk, LOOK)
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy)
  love.graphics.rotate(angle)
  love.graphics.setColor(MAGENTA)
  love.graphics.rectangle("fill", 1, -5.5, 2, 2) -- the pocket square
  if s.phase2 then -- the skin cracked open: chrome under it, lit from inside
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.6 + 0.4 * math.abs(math.sin(clock * 3)))
    love.graphics.setLineWidth(1)
    love.graphics.line(2, 1, 4, 2.5, 3, 4)
    love.graphics.line(-1, 4, 1, 6)
  end
  if s.flash > 0 then
    love.graphics.setColor(1, 0.85, 0.95, s.flash / 0.12)
    love.graphics.circle("fill", 20, 0, 5, 10)
  end
  love.graphics.pop()
  for _, d in ipairs(s.drones) do
    drawDrone(d.x, d.y)
  end
  if say then
    Hud.drawBubble(s.dx, s.dy - Body.SHOULDERS - 10, say.text, math.min(1, say.t * 2), MAGENTA)
  end
  love.graphics.setColor(1, 1, 1)
end

function Saye.drawNightLights(glow)
  if not shown then
    return
  end
  glow(shown.dx, shown.dy, shown.phase2 and 70 or 40, MAGENTA, 0.55)
  for _, d in ipairs(shown.drones) do
    glow(d.x, d.y - 12, 30, MAGENTA, 0.7)
  end
  if shown.flash > 0 then
    glow(shown.dx, shown.dy, 90, HOT, 0.9)
  end
end

--- Her bar on the HUD, at `row` (over Kilowatt's while he is up).
function Saye.drawHUD(row)
  if not shown then
    return
  end
  Bar.draw({
    title = "DIRECTOR SAYE", titleColor = MAGENTA, fill = shown.phase2 and HOT or MAGENTA, hp = shown.hp,
    max = shown.max, stamina = shown.stamina, staminaMax = 100, winded = shown.winded, row = row,
  })
end

Saye.clientMessages = {
  SYE_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      shown = nil
      return
    end
    if not shown then
      shown = { dx = x, dy = y, stride = 0, flash = 0 }
    end
    local s = shown
    s.x, s.y = x, y
    s.facing = tonumber(args[4]) or s.facing or 0
    s.hp = tonumber(args[5]) or s.hp
    s.max = tonumber(args[6]) or s.max
    s.aiming = tonumber(args[7]) or 0
    s.aim = tonumber(args[8]) or s.facing
    s.phase2 = args[9] == "1"
    s.stamina, s.winded = Stamina.read(args, 10)
    s.drones = {}
    for i = 12, #args - 1, 2 do
      local dx, dy = tonumber(args[i]), tonumber(args[i + 1])
      if dx and dy then
        s.drones[#s.drones + 1] = { x = dx, y = dy }
      end
    end
  end,
  SYE_SAY = function(_client, args)
    local text = Saye.lines[tonumber(args[1]) or 0]
    if text then
      say = { text = text, t = Radio.sayTime(text) }
    end
  end,
  SYE_SHOT = function()
    if shown then
      shown.flash = 0.12
    end
  end,
  SYE_DRONE = function(client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    local weapons = Features.byName.weapons
    if x and y and weapons and weapons.explosionAt then
      weapons:explosionAt(client, x, y - 12, MAGENTA)
    end
  end,
  SYE_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      Corpses.add(x, y, angle, LOOK)
    end
    shown = nil
  end,
}

Brain = require("src.features.cyber-feud.saye_brain")

return Saye
