-- Kilowatt, the Static's boss (docs/cyber-feud.md, "Kilowatt"), on the
-- Roof: huge, loud, more machine than man, a reactor for a heart. He waits
-- on the helipad (the map's `bosses.kilowatt`) until the roof wakes (a
-- player up from the stairs, troops.lua's wake), then comes for you up
-- close. This module is the man (his numbers, his lines, his body), the
-- wire and how he looks; what he does is his brain's (kilowatt_brain.lua).
-- troops.lua starts, steps and stops him with the rest and passes rounds
-- on to him; while he is up the Roof isn't done (init.lua asks `serverUp`).
--
-- While he fights, the Static's brutes come up the stairs at the roof's
-- south edge to help (brutes.lua, `map.bosses.stairs`), one every
-- HELP_EVERY, walking a beat round the helipad (`map.bosses.beat`).
--
-- Like every boss (bosses/init.lua) he has breath, scales with the humans
-- (his health), has the boss bar, goes for medkits when badly hurt, dodges
-- abilities, and going down raises `serverKill` "boss", spills koins and a
-- pickup or two. Only players' rounds reach him; while he vents, every hit
-- counts double.
--
-- Messages (KWB_: the Overpass's cameo has KW_)
--   server -> all  KWB_STATE <tick> <x> <y> <facing> <hp> <max> <action> <aim> <lift> <phase2> <stamina> <winded>
--                  <shielded>  (shielded 1 while Saye's drones are round him venting)
--                  (unreliable, 15 Hz; action 0 none, 1 brace, 2 charge, 3 hop, 4 whip, 5 punch, 6 vent,
--                  7 recover; phase2 1 once he is past half health; empty (just the tick) once he is gone)
--   server -> all  KWB_SAY   <line>                   he says Kilowatt.lines[line]
--   server -> all  KWB_SLAM  <x> <y> <radius>         he slammed: a ring of shock rolling out to `radius`
--   server -> all  KWB_ARC   <x> <y> <x> <y>...       his whip: from his fist through whoever it hit
--   server -> all  KWB_THUMP                          a blow landed, or he hit a wall (the sound)
--   server -> all  KWB_PATCH <x> <y> <radius> <seconds>  a shock patch his slam left (meltdown)
--   server -> all  KWB_DOWN  <x> <y> <angle>          he went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Radio = require("src.features.a-man.radio")
local Hud = require("src.features.cyber-feud.hud")
local Duo = require("src.features.cyber-feud.duo")
local Brutes = require("src.features.cyber-feud.brutes")

local Kilowatt = {}
Kilowatt.__index = Kilowatt

local Brain -- his brain, required at the bottom: it reads his numbers

-- Tuning --------------------------------------------------------------------

Kilowatt.HEALTH = 2400 -- for one player (more humans, more: bosses/init.lua)
Kilowatt.RADIUS = 20 -- px; huge
Kilowatt.RUN = 120 -- px/s coming at you (a player sprints at 170)
Kilowatt.WALK = 40 -- px/s winded: a walking player (45) leaves him behind
Kilowatt.BREATH = { -- his stamina (bosses/stamina.lua has the rule)
  drain = 14, -- per second running at you (~7 s of it)
  regen = 16,
  recovered = 50,
  breath = 40, -- in him before a charge or a slam
}
Kilowatt.RANGE = 700 -- px he sees
Kilowatt.CHARGE_FROM = 460 -- px from his target he lowers his head...
Kilowatt.CHARGE_MIN = 130 -- ...and no nearer than this (he slams instead)
Kilowatt.BRACE = 0.6 -- seconds braced, the line on the floor, before he goes
Kilowatt.BRACE_2 = 0.45 -- in phase 2
Kilowatt.CHARGE_SPEED = 540 -- px/s
Kilowatt.CHARGE_TIME = 0.9 -- seconds: about 490 px
Kilowatt.CHARGE_EVERY = 5 -- seconds between charges...
Kilowatt.CHARGE_EVERY_2 = 0.8 -- ...back to back in phase 2
Kilowatt.CHARGE_DAMAGE = 40
Kilowatt.CHARGE_SHOVE = 140 -- px it throws you
Kilowatt.CHARGE_COST = 20 -- breath
Kilowatt.STAGGER = 1.0 -- seconds he reels after charging into something solid
Kilowatt.SLAM_REACH = 170 -- px; this near, he hops and slams
Kilowatt.HOP = 0.5 -- seconds in the air: the tell
Kilowatt.SLAM_RADIUS = 230 -- px the ring rolls out to...
Kilowatt.SLAM_RADIUS_2 = 330 -- ...in phase 2
Kilowatt.RING_SPEED = 520 -- px/s
Kilowatt.SLAM_DAMAGE = 26 -- shock: enough to stun (damage's stunMin is 20)
Kilowatt.SLAM_EVERY = 6
Kilowatt.SLAM_COST = 15
Kilowatt.WHIP_RANGE = 380 -- px
Kilowatt.WHIP_WIND = 0.45 -- seconds his fist crackles first
Kilowatt.WHIP_EVERY = 4.5
Kilowatt.WHIP_DAMAGE = 22 -- shock, each it reaches
Kilowatt.WHIP_HITS = 3 -- players at most down the chain
Kilowatt.WHIP_CHAIN = 170 -- px from one to the next
Kilowatt.PUNCH_REACH = 30 -- px past his body
Kilowatt.PUNCH_WIND = 0.35
Kilowatt.PUNCH_DAMAGE = 30
Kilowatt.VENT_AFTER = 4 -- moves between vents...
Kilowatt.VENT_AFTER_2 = 6 -- ...in phase 2
Kilowatt.VENT_TIME = 3 -- seconds venting: hits count double...
Kilowatt.VENT_TIME_2 = 4.5 -- ...in phase 2
Kilowatt.VENT_HURT = 2
Kilowatt.SAY_EVERY = { 7, 12 } -- seconds between taunts
Kilowatt.DROPS = 40 -- koins
Kilowatt.PICKUPS = 2 -- pickups he drops

--- What he says (docs/cyber-feud.md, "Voice"), and which is which.
Kilowatt.lines = {
  "THERE you are, spark!",
  "Hold still, I just wanna hug you. Hard.",
  "Ha! That tickled. Do it again.",
  "You run like a corp. Fight like one too?",
  "Ooh, hot hot hot, gimme a second.",
  "Now we're LIT!",
  "...good fight, spark.",
  "Snack break!",
  "Spare parts! Don't mind if I do.",
  "C'mon, spark, I'm just getting warm!",
  "Every day I get paid for this. EVERY DAY.",
  "You said this kid was a nobody!",
  "It was ugly.",
  "Sixty-forty, Saye. It was always supposed to be sixty-forty.",
  "I AM hitting them! The building's just in the way!",
  "MELTDOWN!",
  "Hey! Hands off the suit, spark!",
  "Boys! Up here! Bring the big ones!",
  "Ha! Here comes the help!",
}
Kilowatt.LINE = {
  intro = 1, taunt = { 2, 3, 4, 10, 11 }, vent = 5, phase2 = 6, down = 7, heal = { 8, 9 },
  bicker = { 12, 13, 14, 15 }, rage = 16, grudge = 17, -- (duo.lua's: with Saye)
  help = { 18, 19 }, -- a brute up the stairs
}
Kilowatt.HELP_FIRST = 15 -- seconds into the fight before the first brute comes up the stairs...
Kilowatt.HELP_EVERY = 25 -- ...and between one and the next, while he is up...
Kilowatt.HELP_MOST = 2 -- ...while fewer than this of them are up (and one more for each human past the first)
Kilowatt.PATCH_RADIUS = 120 -- px: a meltdown slam's shock patch (duo.lua: Saye down)...
Kilowatt.PATCH_TIME = 4 -- ...seconds it crackles...
Kilowatt.PATCH_DAMAGE = 8 -- ...shock, every PATCH_EVERY to whoever stands in it
Kilowatt.PATCH_EVERY = 0.5

local ACTION_CODE = { brace = 1, charge = 2, hop = 3, whip = 4, punch = 5, vent = 6, recover = 7 }

local CYAN = { 0.18, 0.90, 1.00 }
local HOT = { 0.78, 0.98, 1.00 }
local CHROME = { 0.78, 0.82, 0.86 }
local LOOK = {
  shirt = { 0.20, 0.22, 0.24 }, pants = { 0.14, 0.14, 0.16 }, skin = { 0.48, 0.35, 0.27 },
  hair = { 0.13, 0.15, 0.17 }, shoes = { 0.06, 0.06, 0.07 },
}
local SCALE = 2.2 -- drawn this much bigger than anyone

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The man ---------------------------------------------------------------------

--- Him, at (x, y), with `hp`, finding his way round on `nav`.
function Kilowatt.new(x, y, hp, nav)
  return setmetatable({
    x = x,
    y = y,
    facing = math.pi / 2,
    aim = math.pi / 2,
    hp = hp,
    max = hp,
    nav = nav,
    time = 0,
    t = 0,
    action = nil,
    lift = 0,
    moves = 0,
    chargeIn = 2,
    slamIn = 1,
    whipIn = 3,
    sayIn = 6,
    frozen = 0,
    stuck = 0,
    rings = {},
    patches = {},
    phase2 = false,
    breath = Stamina.new(Kilowatt.BREATH),
    running = false,
    mode = "hunt",
  }, Kilowatt)
end

local function fits(x, y)
  local r = Kilowatt.RADIUS
  return not (Sight.blocked(x, y) or Sight.blocked(x - r, y) or Sight.blocked(x + r, y)
    or Sight.blocked(x, y - r) or Sight.blocked(x, y + r))
end

--- Move by (mx, my), sliding along walls. Returns false when he went nowhere.
function Kilowatt:move(mx, my)
  if fits(self.x + mx, self.y + my) then
    self.x, self.y = self.x + mx, self.y + my
  elseif fits(self.x + mx, self.y) then
    self.x = self.x + mx
  elseif fits(self.x, self.y + my) then
    self.y = self.y + my
  else
    self.stuck = self.stuck + 1 / 60
    return false
  end
  self.stuck = 0
  return true
end

function Kilowatt:walk(angle, speed, dt)
  self:move(math.cos(angle) * speed * dt, math.sin(angle) * speed * dt)
end

--- How fast he may go: running, or winded.
function Kilowatt:pace()
  return self.breath:pace(Kilowatt.RUN, Kilowatt.WALK)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { k, awake, syncIn, down }

--- Him on `map`'s `bosses.kilowatt` spot, waiting while `calm`; finding his
--- way on `nav`. Nothing on a map without him.
function Kilowatt.serverStart(server, map, nav, calm)
  Kilowatt.serverStop(server)
  local spot = map.bosses and map.bosses.kilowatt
  if not spot then
    return
  end
  sv = { k = Kilowatt.new(spot.x, spot.y, Bosses.health(Kilowatt.HEALTH, server), nav), awake = not calm, syncIn = 0,
    stairs = map.bosses.stairs, beat = map.bosses.beat, helpIn = Kilowatt.HELP_FIRST, help = {} }
end

function Kilowatt.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("KWB_STATE", server.tick))
  end
end

--- The roof woke: he is coming (and says so, on his next step).
function Kilowatt.serverWake()
  if sv and not sv.awake then
    sv.awake, sv.greet = true, true
  end
end

--- Is he still up (the Roof isn't done while he is)?
function Kilowatt.serverUp()
  return sv ~= nil and not sv.down
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local k = sv.k
  local stamina, winded = k.breath:wire()
  local msg = Protocol.encode("KWB_STATE", server.tick, ("%.0f"):format(k.x), ("%.0f"):format(k.y),
    ("%.2f"):format(k.facing), ("%.0f"):format(math.max(0, k.hp)), ("%.0f"):format(k.max), ACTION_CODE[k.action] or 0,
    ("%.2f"):format(k.aim), ("%.0f"):format(k.lift), k.phase2 and 1 or 0, stamina, winded, Duo.shielding() and 1 or 0)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- His brutes up the stairs: one every HELP_EVERY while fewer than
--- HELP_MOST of them are up, and he shouts for them.
local function callHelp(server, dt)
  if not (sv.stairs and sv.beat) then
    return
  end
  sv.helpIn = sv.helpIn - dt
  if sv.helpIn > 0 then
    return
  end
  sv.helpIn = Kilowatt.HELP_EVERY
  for i = #sv.help, 1, -1 do
    if sv.help[i].hp <= 0 then
      table.remove(sv.help, i)
    end
  end
  if #sv.help >= Bosses.plus(Kilowatt.HELP_MOST, server) then
    return
  end
  local b = Brutes.serverJoin(sv.stairs.x, sv.stairs.y, sv.beat, #sv.beat) -- (heading for the first corner)
  if b then
    b.facing = -math.pi / 2
    sv.help[#sv.help + 1] = b
    local lines = Kilowatt.LINE.help
    server:broadcast(Protocol.encode("KWB_SAY", lines[random(#lines)]))
  end
end

function Kilowatt.serverStep(server, dt)
  if not sv or sv.down then
    return
  end
  if sv.greet then
    sv.greet = false
    server:broadcast(Protocol.encode("KWB_SAY", Kilowatt.LINE.intro))
  end
  if sv.awake then
    callHelp(server, dt)
    for _, e in ipairs(Brain.think(sv.k, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("KWB_SAY", e[2]))
      elseif e[1] == "slam" then
        server:broadcast(Protocol.encode("KWB_SLAM", ("%.0f"):format(e[2]), ("%.0f"):format(e[3]), e[4]))
      elseif e[1] == "arc" then
        local parts = {}
        for i, v in ipairs(e[2]) do
          parts[i] = ("%.0f"):format(v)
        end
        server:broadcast(Protocol.encode("KWB_ARC", unpack(parts)))
      elseif e[1] == "thump" then
        server:broadcast(Protocol.encode("KWB_THUMP"))
      elseif e[1] == "patch" then
        server:broadcast(Protocol.encode("KWB_PATCH", ("%.0f"):format(e[2]), ("%.0f"):format(e[3]), e[4], e[5]))
      end
    end
  end
  sync(server)
end

--- He's down: his last word, his body, koins, a pickup or two, the kill.
local function down(server, by, angle)
  local k = sv.k
  sv.down = true
  server:broadcast(Protocol.encode("KWB_SAY", Kilowatt.LINE.down))
  server:broadcast(Protocol.encode("KWB_DOWN", ("%.0f"):format(k.x), ("%.0f"):format(k.y), ("%.3f"):format(angle or 0)))
  server:broadcast(Protocol.encode("KWB_STATE", server.tick + 1))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, k.x, k.y, Kilowatt.DROPS)
  end
  local pickups = Features.byName.pickups
  for _ = 1, Kilowatt.PICKUPS do
    if pickups and pickups.serverDropEnemy then
      pickups:serverDropEnemy(server, k.x + random(-40, 40), k.y + random(-40, 40))
    end
  end
  Features.call("serverKill", server, { kind = "boss", x = k.x, y = k.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him; double while he vents. Returns true when it hit him.
function Kilowatt.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local k = sv.k
  if dist2(x, y, k.x, k.y) > (Kilowatt.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  if not sv.awake then
    require("src.features.cyber-feud.troops").serverWake() -- shot while he waits: that's it, then
  end
  local open = k.action == "vent" and not Duo.shielding() -- (Saye's drones round him: no window yet)
  k.hp = k.hp - (damage or 20) * (open and Kilowatt.VENT_HURT or 1)
  if k.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

function Kilowatt.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.k.x, sv.k.y) <= radius * radius then
    sv.k.frozen = math.max(sv.k.frozen, seconds)
  end
end

--- For tests.
function Kilowatt.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil -- { x, y, dx, dy, facing, hp, max, action, aim, lift, phase2, stamina, winded }
local say = nil -- { text, t }
local rings = {} -- { x, y, r, max }
local patches = {} -- { x, y, r, t, max }
local arcs = {} -- { pts, t }
local steam = {} -- { x, y, vx, vy, t }
local lastTick, heardAt, clock = 0, 0, 0
local thump = nil

local ARC_TIME = 0.3
local STEAM_TIME = 0.8

function Kilowatt.load()
  local buf = Synth.newBuffer(0.5)
  buf:noiseBurst(0, 0.14, { amp = 0.9, decay = 0.06 })
  buf:sweep(0, 0.45, 110, 35, { wave = "sine", amp = 1, decay = 0.18 })
  buf:lowpass(1500)
  thump = love.audio.newSource(buf:toSoundData(0.95), "static")
  thump:setAttenuationDistances(300, 2400)
end

local function play(x, y, pitch)
  if thump then
    local s = thump:clone()
    s:setPosition(x, 0, y)
    s:setPitch(pitch or 1)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Kilowatt.clear()
  shown, say, rings, arcs, steam, patches, lastTick = nil, nil, {}, {}, {}, {}, 0
end

--- Is he up, as far as this screen knows (the objective line)?
function Kilowatt.up()
  return shown ~= nil
end

function Kilowatt.update(dt)
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
    if shown.action == 6 and random() < dt * 30 then -- steam out of the open cage
      local a = random() * 2 * math.pi
      steam[#steam + 1] = { x = shown.dx, y = shown.dy, vx = math.cos(a) * 40, vy = math.sin(a) * 40 - 30, t = 0 }
    end
  end
  for i = #steam, 1, -1 do
    local p = steam[i]
    p.t = p.t + dt
    p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
    if p.t > STEAM_TIME then
      table.remove(steam, i)
    end
  end
  for i = #rings, 1, -1 do
    local g = rings[i]
    g.r = g.r + Kilowatt.RING_SPEED * dt
    if g.r >= g.max + 30 then
      table.remove(rings, i)
    end
  end
  for i = #patches, 1, -1 do
    patches[i].t = patches[i].t + dt
    if patches[i].t >= patches[i].max then
      table.remove(patches, i)
    end
  end
  for i = #arcs, 1, -1 do
    arcs[i].t = arcs[i].t + dt
    if arcs[i].t > ARC_TIME then
      table.remove(arcs, i)
    end
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

--- Under everyone: a bracing charge's line, the slam's rings and patches, his shadow.
function Kilowatt.drawBelowCars()
  for _, p in ipairs(patches) do -- crackling cyan on the ground
    local fade = math.min(1, (p.max - p.t) / 0.5)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.16 * fade)
    love.graphics.circle("fill", p.x, p.y, p.r, 40)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.7 * fade)
    for _ = 1, 3 do
      local a, d = random() * 2 * math.pi, random() * p.r
      local x, y = p.x + math.cos(a) * d, p.y + math.sin(a) * d
      love.graphics.line(x, y, x + (random() - 0.5) * 24, y + (random() - 0.5) * 24)
    end
  end
  for _, g in ipairs(rings) do
    local fade = math.max(0, 1 - g.r / (g.max + 30))
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.25 * fade)
    love.graphics.setLineWidth(40)
    love.graphics.circle("line", g.x, g.y, g.r, 64)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.9 * fade)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", g.x, g.y, g.r, 64)
  end
  love.graphics.setLineWidth(1)
  if not shown then
    return
  end
  if shown.action == 1 then
    local ex, ey = Sight.reach(shown.dx, shown.dy, shown.aim, Kilowatt.CHARGE_SPEED * Kilowatt.CHARGE_TIME + 30)
    local pulse = 0.5 + 0.5 * math.abs(math.sin(clock * 16))
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.15 + 0.2 * pulse)
    love.graphics.setLineWidth((Kilowatt.RADIUS + 14) * 2)
    love.graphics.line(shown.dx, shown.dy, ex, ey)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * pulse)
    love.graphics.setLineWidth(2)
    love.graphics.line(shown.dx, shown.dy, ex, ey)
    love.graphics.setLineWidth(1)
  end
  if shown.action == 3 then -- where he'll come down
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.35)
    love.graphics.circle("line", shown.dx, shown.dy, Kilowatt.SLAM_REACH, 48)
  end
  local lift = shown.lift or 0
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", shown.dx + 5, shown.dy + 6, 22 - lift * 0.2, 16 - lift * 0.15, 16)
end

--- Him: the Overpass's Kilowatt (war_rigs.lua), facing his way, the cage
--- open and steaming while he vents, sparking in phase 2.
local function drawHim(k)
  love.graphics.push()
  love.graphics.translate(k.dx, k.dy - (k.lift or 0))
  love.graphics.scale(SCALE)
  local walk = k.action == 0 and math.sin(k.stride * 0.12) * 1.3 or 0
  local angle = k.action == 1 and k.aim or k.facing
  Body.person(0, 0, angle, walk, LOOK)
  love.graphics.rotate(angle)
  love.graphics.setColor(CHROME)
  love.graphics.ellipse("fill", 0, -7.5, 3.2, 2.4, 10) -- the shoulders
  love.graphics.ellipse("fill", 0, 7.5, 3.2, 2.4, 10)
  love.graphics.rectangle("fill", 3, -2, 2, 4, 0.6) -- the jaw
  local venting = k.action == 6
  local rate = k.phase2 and 12 or 5
  local pulse = venting and 1 or (0.55 + 0.45 * math.abs(math.sin(clock * rate)))
  local c = venting and HOT or CYAN
  love.graphics.setColor(c[1], c[2], c[3], pulse)
  love.graphics.circle("fill", 2, 0, venting and 3.4 or 2.6, 10) -- the reactor
  if venting then -- the cage swung open
    love.graphics.setColor(CHROME)
    love.graphics.setLineWidth(0.8)
    love.graphics.line(4.5, -3, 6.5, -5)
    love.graphics.line(4.5, 3, 6.5, 5)
  end
  love.graphics.setColor(0.13, 0.15, 0.17)
  love.graphics.setLineWidth(1.2)
  for i = -2, 2 do -- the mohawk's cables
    love.graphics.line(-1, i * 1.1, -4.6 + math.abs(i) * 0.5, i * 1.6)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(CYAN)
  for i = -2, 2 do
    love.graphics.circle("fill", -4.6 + math.abs(i) * 0.5, i * 1.6, 0.8, 6)
  end
  if k.action == 4 then -- the whip crackling in his fist
    love.graphics.setColor(HOT)
    love.graphics.circle("fill", 7, 6, 1.6 + random() * 1.2, 8)
  end
  if k.phase2 and random() < 0.4 then -- arcs off his shoulders
    love.graphics.setColor(HOT)
    local s = random() < 0.5 and -1 or 1
    love.graphics.line(0, s * 7.5, -2 + random() * 4, s * (10 + random() * 3), random() * 3, s * 12)
  end
  love.graphics.pop()
end

--- A jagged line through `pts`, the whip's lightning.
local function drawArc(pts, alpha)
  local jag = {}
  for i = 1, #pts - 2, 2 do
    local x0, y0, x1, y1 = pts[i], pts[i + 1], pts[i + 2], pts[i + 3]
    jag[#jag + 1], jag[#jag + 2] = x0, y0
    for s = 1, 5 do
      local f = s / 6
      jag[#jag + 1] = x0 + (x1 - x0) * f + (random() - 0.5) * 22
      jag[#jag + 1] = y0 + (y1 - y0) * f + (random() - 0.5) * 22
    end
  end
  jag[#jag + 1], jag[#jag + 2] = pts[#pts - 1], pts[#pts]
  if #jag < 4 then
    return
  end
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.4 * alpha)
  love.graphics.setLineWidth(6)
  love.graphics.line(jag)
  love.graphics.setColor(HOT[1], HOT[2], HOT[3], alpha)
  love.graphics.setLineWidth(2)
  love.graphics.line(jag)
  love.graphics.setLineWidth(1)
end

function Kilowatt.drawAboveCars()
  for _, p in ipairs(steam) do
    love.graphics.setColor(0.85, 0.9, 0.92, 0.35 * (1 - p.t / STEAM_TIME))
    love.graphics.circle("fill", p.x, p.y, 6 + p.t * 18, 12)
  end
  if shown then
    drawHim(shown)
    if say then
      Hud.drawBubble(shown.dx, shown.dy - Body.SHOULDERS * SCALE - 8 - (shown.lift or 0), say.text,
        math.min(1, say.t * 2), CYAN)
    end
  end
  for _, a in ipairs(arcs) do
    drawArc(a.pts, 1 - a.t / ARC_TIME)
  end
  love.graphics.setColor(1, 1, 1)
end

function Kilowatt.drawNightLights(glow)
  if shown then
    glow(shown.dx, shown.dy - (shown.lift or 0), shown.action == 6 and 160 or 100, CYAN, shown.action == 6 and 1 or 0.7)
  end
  for _, g in ipairs(rings) do
    glow(g.x, g.y, g.r + 40, CYAN, 0.25 * math.max(0, 1 - g.r / (g.max + 30)))
  end
  for _, a in ipairs(arcs) do
    local pts = a.pts
    glow(pts[#pts - 1], pts[#pts], 80, HOT, 0.8)
  end
  for _, p in ipairs(patches) do
    glow(p.x, p.y, p.r + 30, CYAN, 0.35 * math.min(1, (p.max - p.t) / 0.5))
  end
end

function Kilowatt.drawHUD()
  if not shown then
    return
  end
  Bar.draw({
    title = shown.action == 6 and (shown.shielded and "KILOWATT  -  VENTING (SHIELDED)" or "KILOWATT  -  VENTING!")
      or "KILOWATT", titleColor = CYAN,
    fill = shown.phase2 and { 0.75, 0.98, 1 } or CYAN, hp = shown.hp, max = shown.max,
    stamina = shown.stamina, staminaMax = 100, winded = shown.winded,
  })
end

Kilowatt.clientMessages = {
  KWB_STATE = function(_client, args)
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
      shown = { dx = x, dy = y, stride = 0 }
    end
    local k = shown
    k.x, k.y = x, y
    k.facing = tonumber(args[4]) or k.facing or 0
    k.hp = tonumber(args[5]) or k.hp
    k.max = tonumber(args[6]) or k.max
    k.action = tonumber(args[7]) or 0
    k.aim = tonumber(args[8]) or k.facing
    k.lift = tonumber(args[9]) or 0
    k.phase2 = args[10] == "1"
    k.stamina, k.winded = Stamina.read(args, 11)
    k.shielded = args[13] == "1"
  end,
  KWB_SAY = function(_client, args)
    local text = Kilowatt.lines[tonumber(args[1]) or 0]
    if text then
      say = { text = text, t = Radio.sayTime(text) }
    end
  end,
  KWB_SLAM = function(_client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and r then
      rings[#rings + 1] = { x = x, y = y, r = 0, max = r }
      play(x, y, 0.7)
    end
  end,
  KWB_ARC = function(_client, args)
    local pts = {}
    for i = 1, #args do
      pts[i] = tonumber(args[i]) or 0
    end
    if #pts >= 4 then
      arcs[#arcs + 1] = { pts = pts, t = 0 }
    end
  end,
  KWB_PATCH = function(_client, args)
    local x, y, r, secs = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r and secs then
      patches[#patches + 1] = { x = x, y = y, r = r, t = 0, max = secs }
    end
  end,
  KWB_THUMP = function()
    if shown then
      play(shown.dx, shown.dy, 1)
    end
  end,
  KWB_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      local body = { size = SCALE }
      for key, v in pairs(LOOK) do
        body[key] = v
      end
      Corpses.add(x, y, angle, body) -- as big lying down
      play(x, y, 0.6)
    end
    shown = nil
  end,
}

Brain = require("src.features.cyber-feud.kilowatt_brain")

return Kilowatt
