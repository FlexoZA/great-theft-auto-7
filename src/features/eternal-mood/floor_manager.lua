-- The Floor Manager, Fobos Base's boss (docs/eternal-mood.md, "The bosses,
-- one a level"), the way Heck makes an Arachnotron: the UAC's shift
-- supervisor, promoted out of his body. His brain sits in a glass dome on a
-- four-legged spider walker with a plasma cannon slung under the front, his
-- clipboard taped to its side. He stands on the Hangar's lift (the map's
-- `horde.boss`), and nobody leaves Fobos Base while he is up: the lift is
-- OUT OF SERVICE (`serverLocked`) until he is down.
--
-- He waits until a player walks into the Hangar (or shoots him), then
-- fights: streams of plasma from his cannon, his aim dragging after you, and
-- his legs stomped down on whoever gets close. At two thirds and a third of
-- his health he calls a quick meeting: staffers and a file of interns come
-- in through the Hangar's doorways (horde.lua's `serverCall`). The cannon is a weak point
-- with health of its own (`CANNON`): rounds that land on it, at the front of
-- him, wreck it, and then he has no plasma, but he comes at you faster to
-- stomp. This module is the man, the wire and the lock; what he does is his
-- brain's (floor_manager_brain.lua). His plasma flies as fireballs.lua's
-- "plasma".
--
-- Like every boss (bosses/init.lua) he has breath, scales with the humans
-- (his health, his cannon's, his meetings), has the boss bar, goes for
-- medkits when badly hurt, dodges abilities, and going down raises
-- `serverKill` "boss" and spills koins. He is Heck's: only players' rounds
-- reach him.
--
-- Messages
--   server -> all  FM_STATE <tick> <x> <y> <facing> <hp> <max> <move> <aim> <phase2> <awake> <cannon> <stamina>
--                  <winded>  (unreliable, 15 Hz; move 0 none, 1 legs up for a stomp, 2 the cannon charging, 3 the
--                  stream going; cannon its share of health left, 0 shot off; empty once he is gone)
--   server -> all  FM_SAY    <line>              he says FloorManager.lines[line]
--   server -> all  FM_STOMP  <x> <y>             his legs came down there
--   server -> all  FM_SOUND  <name>              rear (the legs going up) or charge (the cannon)
--   server -> all  FM_CANNON <x> <y>             his cannon was shot off there
--   server -> all  FM_DOWN   <x> <y> <angle>     he went down: the lift works again (to a joiner too)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Bar = require("src.features.bosses.bar")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Fireballs = require("src.features.eternal-mood.fireballs")
local Look = require("src.features.eternal-mood.floor_manager_look")

local FloorManager = {}
FloorManager.__index = FloorManager

local Brain

-- Tuning --------------------------------------------------------------------

FloorManager.HEALTH = 2250 -- for one player (more humans, more: bosses/init.lua); Volt has 1800
FloorManager.CANNON = 600 -- the cannon's own, for one player: a fair bit of shooting
FloorManager.RADIUS = 40 -- px: the walker's hull (floor_manager_look.lua draws him)
FloorManager.WALK = 90 -- px/s, on four legs, any way he likes
FloorManager.STROLL = 40 -- px/s winded
FloorManager.RAGE = 1.35 -- his pace once the cannon is gone
FloorManager.TURN = 3 -- rad/s the body turns
FloorManager.BREATH = { drain = 9, regen = 14, recovered = 50, breath = 40 }
FloorManager.RANGE = 760 -- px he sees
FloorManager.KEEP = 340 -- px he keeps from whoever he has, cannon and all
FloorManager.SIDE_EVERY = { 1.5, 3 } -- seconds before he side-steps the other way
FloorManager.MUZZLE = 68 -- px in front of his middle: the cannon's end (and where it's hit), as drawn
FloorManager.CANNON_HIT = 18 -- px round the cannon a round counts as on it
FloorManager.PLASMA_RANGE = 700 -- px
FloorManager.PLASMA_EVERY = 3.2 -- seconds from one stream to the next...
FloorManager.PLASMA_EVERY_2 = 2.4 -- ...in phase 2
FloorManager.PLASMA_COST = 15 -- breath
FloorManager.CHARGE = 0.55 -- seconds the cannon glows first
FloorManager.STREAM = 10 -- bolts in a stream
FloorManager.STREAM_EVERY = 0.09 -- seconds between bolts
FloorManager.STREAM_TURN = 1.1 -- rad/s the aim drags after them while it streams
FloorManager.FAN = 0.28 -- radians either side, phase 2's three streams
FloorManager.STOMP_REACH = 120 -- px: this near, the legs go up...
FloorManager.STOMP_RADIUS = 115 -- ...and come down on everyone this near
FloorManager.STOMP_WINDUP = 0.6 -- seconds up first (the ring shows)
FloorManager.STOMP_DAMAGE = 30 -- impact
FloorManager.STOMP_SHOVE = 140 -- px
FloorManager.STOMP_EVERY = 2.2
FloorManager.MEETING_AT = { 2 / 3, 1 / 3 } -- shares of his health he calls a meeting at
FloorManager.MEETING = 1 -- staffers through each doorway (more players, more: Bosses.plus)...
FloorManager.MEETING_INTERNS = 3 -- ...and interns behind them
FloorManager.SAY_EVERY = { 8, 13 }
FloorManager.DROPS = 25

FloorManager.lines = {
  "You're not on the rota.",
  "Let's circle back to you.",
  "This is going in your review.",
  "Per my last memo: die.",
  "Who signed off on you?",
  "Quick meeting, everyone. Hangar. Now.",
  "All hands! Mandatory fun!",
  "Right. I'm escalating this.",
  "Taking my statutory break.",
  "I want... to speak... to my manager...",
  "Nobody leaves before end of shift.",
  "I've been promoted. Out of my body.",
  "My presentation! You'll pay for that.",
}
FloorManager.LINE = {
  intro = 1, taunt = { 2, 3, 4, 5, 11, 12 }, meeting = { 6, 7 }, phase2 = 8, heal = 9, down = 10, cannon = 13,
}

local GREEN = { 0.35, 1.00, 0.45 } -- plasma
local RED = { 1.00, 0.18, 0.10 }
local STEEL_DARK = { 0.20, 0.19, 0.19 }
local BRAIN = { 0.92, 0.58, 0.60 }

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The man ---------------------------------------------------------------------

function FloorManager.new(x, y, facing, hp, cannon, nav)
  return setmetatable({
    x = x, y = y, facing = facing, aim = facing, hp = hp, max = hp, cannon = true, cannonHp = cannon,
    cannonMax = cannon, nav = nav, time = 0, move = nil, moveT = 0, stompIn = 1, plasmaIn = 1.2, sayIn = 6,
    frozen = 0, stuck = 0, side = 1, sideIn = 2, left = 0, boltIn = 0, phase2 = false, meetings = 0,
    breath = Stamina.new(FloorManager.BREATH), running = false, mode = "hunt",
  }, FloorManager)
end

local function fits(x, y)
  local r = FloorManager.RADIUS
  local k = r * 0.7
  return not (Ground.blocked(x, y) or Ground.blocked(x - r, y) or Ground.blocked(x + r, y)
    or Ground.blocked(x, y - r) or Ground.blocked(x, y + r) or Ground.blocked(x - k, y - k)
    or Ground.blocked(x + k, y - k) or Ground.blocked(x - k, y + k) or Ground.blocked(x + k, y + k))
end

--- Turn the body towards `angle`.
function FloorManager:turn(angle, dt)
  local d = Sight.angleDiff(angle, self.facing)
  local step = FloorManager.TURN * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

--- Walk along `angle` at `speed`, whichever way he faces (four legs),
--- sliding along walls.
function FloorManager:walk(angle, speed, dt)
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

function FloorManager:pace()
  return self.breath:pace(FloorManager.WALK, FloorManager.STROLL)
end

--- Where his cannon's end is.
function FloorManager:muzzle()
  return self.x + math.cos(self.facing) * FloorManager.MUZZLE, self.y + math.sin(self.facing) * FloorManager.MUZZLE
end

-- Server --------------------------------------------------------------------

local sv = nil -- { m, spec, awake, syncIn, down }

--- Him on `map`'s lift (its `horde.boss` of kind "floor-manager"), finding his way on `nav`. Nothing on a
--- map without him.
function FloorManager.serverStart(server, map, nav)
  FloorManager.serverStop(server)
  local spec = map.horde and map.horde.boss
  if not (spec and spec.kind == "floor-manager") then
    return
  end
  sv = { m = FloorManager.new(spec.x, spec.y, spec.facing or math.pi / 2, Bosses.health(FloorManager.HEALTH, server),
    Bosses.health(FloorManager.CANNON, server), nav), spec = spec, awake = false, syncIn = 0 }
end

function FloorManager.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("FM_STATE", server.tick))
  end
end

--- Is the lift still out of service (he is up)?
function FloorManager.serverLocked()
  return sv ~= nil and not sv.down
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    server:broadcast(Protocol.encode("FM_SAY", FloorManager.LINE.intro))
  end
end

--- A quick meeting: staffers in through each of the Hangar's doorways, at
--- whoever he has.
local function meeting(server)
  local Horde = require("src.features.eternal-mood.horde")
  local m = sv.m
  local _, tx, ty = Brain.target(m, server)
  local each = Bosses.plus(FloorManager.MEETING, server)
  local mob = Bosses.plus(FloorManager.MEETING_INTERNS, server)
  for _, door in ipairs(sv.spec.doors or {}) do
    for k = 1, each do
      Horde.serverCall(server, "staffer", door.x + (k - (each + 1) / 2) * 30, door.y, tx or m.x, ty or m.y)
    end
    for k = 1, mob do -- the interns file in behind, down the corridor
      Horde.serverCall(server, "intern", door.x + (k % 2 == 0 and 14 or -14), door.y + 26 * k, tx or m.x, ty or m.y)
    end
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local MOVE = { stomp = 1, charge = 2, stream = 3 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local m = sv.m
  local stamina, winded = m.breath:wire()
  local cannon = m.cannon and math.max(0.01, m.cannonHp / m.cannonMax) or 0
  local msg = Protocol.encode("FM_STATE", server.tick, fmt(m.x), fmt(m.y), ("%.2f"):format(m.facing),
    fmt(math.max(0, m.hp)), fmt(m.max), MOVE[m.move] or 0, ("%.3f"):format(m.aim), m.phase2 and 1 or 0,
    sv.awake and 1 or 0, ("%.2f"):format(cannon), stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function FloorManager.serverStep(server, dt)
  if not sv or sv.down then
    return
  end
  if not sv.awake then
    local z = sv.spec.zone
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if x >= z.x0 and x <= z.x1 and y >= z.y0 and y <= z.y1 then
          wake(server)
        end
      end
    end
  end
  if sv.awake then
    for _, e in ipairs(Brain.think(sv.m, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("FM_SAY", e[2]))
      elseif e[1] == "stomp" then
        server:broadcast(Protocol.encode("FM_STOMP", fmt(e[2]), fmt(e[3])))
      elseif e[1] == "bolt" then
        Fireballs.serverThrow(server, e[2], e[3], e[4], "plasma")
      elseif e[1] == "sound" then
        server:broadcast(Protocol.encode("FM_SOUND", e[2]))
      elseif e[1] == "meeting" then
        meeting(server)
      end
    end
  end
  sync(server)
end

--- Down: his last word, his wreck, koins, the kill, and the lift working again.
local function down(server, by, angle)
  local m = sv.m
  sv.down = true
  server:broadcast(Protocol.encode("FM_SAY", FloorManager.LINE.down))
  server:broadcast(Protocol.encode("FM_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)))
  server:broadcast(Protocol.encode("FM_STATE", server.tick + 1))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, m.x, m.y, FloorManager.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, m.x, m.y)
    pickups:serverDropEnemy(server, m.x + 40, m.y)
  end
  Features.call("serverKill", server, { kind = "boss", x = m.x, y = m.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him (and wakes him). One on his cannon hurts the cannon (and him
--- a quarter as much); anywhere else on him, him. Returns true when it hit.
function FloorManager.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local m = sv.m
  damage = damage or 20
  local mx, my = m:muzzle()
  local onCannon = m.cannon and dist2(x, y, mx, my) <= (FloorManager.CANNON_HIT + (radius or 0)) ^ 2
  if not onCannon and dist2(x, y, m.x, m.y) > (FloorManager.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  wake(server)
  if onCannon then
    m.cannonHp = m.cannonHp - damage
    damage = damage * 0.25
    if m.cannonHp <= 0 then
      m.cannon = false
      server:broadcast(Protocol.encode("FM_CANNON", fmt(mx), fmt(my)))
      server:broadcast(Protocol.encode("FM_SAY", FloorManager.LINE.cannon))
    end
  end
  m.hp = m.hp - damage
  if m.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

function FloorManager.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.m.x, sv.m.y) <= radius * radius then
    sv.m.frozen = math.max(sv.m.frozen, seconds)
  end
end

function FloorManager.serverPlayerJoined(server, player)
  if sv and sv.down and not player.bot then
    local m = sv.m
    server:send(player, Protocol.encode("FM_DOWN", fmt(m.x), fmt(m.y), ("%.3f"):format(m.facing)), true)
  end
end

--- For tests.
function FloorManager.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil
local say = nil
local stomps = {} -- { x, y, t }
local scrap = nil -- { x, y, t } where his cannon came off
local wreck = nil -- { x, y, angle } where he went down
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local STOMP_SHOWN = 0.45

function FloorManager.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(300, 2400)
    return src
  end
  bank.stomp = make(0.6, 0.9, function(buf) -- steel feet on concrete
    buf:noiseBurst(0, 0.3, { amp = 0.8, decay = 0.07 })
    buf:sweep(0, 0.5, 110, 40, { wave = "sine", amp = 0.8, decay = 0.15 })
    buf:tone(0, 0.4, 410, { wave = "square", amp = 0.12, decay = 0.1, sustain = 0 })
    buf:lowpass(2600)
  end)
  bank.rear = make(0.6, 0.6, function(buf) -- servos lifting the legs
    buf:sweep(0, 0.55, 260, 520, { wave = "saw", amp = 0.2, decay = 2 })
    buf:noiseBurst(0, 0.5, { amp = 0.1, decay = 0.4 })
    buf:lowpass(1800)
  end)
  bank.charge = make(0.6, 0.7, function(buf) -- the cannon winding up
    buf:sweep(0, 0.55, 300, 1600, { wave = "sine", amp = 0.35, decay = 2 })
    buf:sweep(0, 0.55, 600, 3200, { wave = "square", amp = 0.08, decay = 2 })
  end)
  bank.scrap = make(0.7, 0.9, function(buf) -- the cannon torn off
    buf:noiseBurst(0, 0.5, { amp = 0.8, decay = 0.12 })
    buf:sweep(0, 0.6, 900, 80, { wave = "square", amp = 0.3, decay = 0.2 })
    buf:lowpass(3500)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    if x then
      s:setPosition(x, 0, y)
    elseif shown then
      s:setPosition(shown.dx, 0, shown.dy)
    end
    s:setPitch(0.92 + random() * 0.16)
    s:setVolume(0.75 * Audio.volume("weapons"))
    s:play()
  end
end

function FloorManager.clear()
  shown, say, stomps, scrap, wreck, lastTick = nil, nil, {}, nil, nil, 0
end

function FloorManager.update(dt)
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
    -- How far into a stomp's rearing, or a charge's glow, for the look.
    local into = clock - (shown.moveAt or clock)
    shown.rearT = into / FloorManager.STOMP_WINDUP
    shown.chargeT = into / FloorManager.CHARGE
    Look.update(shown.look, shown, dt)
  end
  for i = #stomps, 1, -1 do
    stomps[i].t = stomps[i].t + dt
    if stomps[i].t > STOMP_SHOWN then
      table.remove(stomps, i)
    end
  end
  if scrap then
    scrap.t = scrap.t + dt
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

--- The lift's sign while he is up: OUT OF SERVICE, over the pad.
local function drawLiftSign(map)
  local spec = map and map.horde and map.horde.boss
  local lift = spec and spec.lift
  if not lift or wreck then
    return
  end
  love.graphics.setColor(0.10, 0.03, 0.02, 0.55)
  love.graphics.rectangle("fill", lift.x, lift.y, lift.w, lift.h)
  local pulse = 0.6 + 0.3 * math.abs(math.sin(clock * 3))
  love.graphics.setColor(RED[1], RED[2], RED[3], pulse)
  love.graphics.setLineWidth(4)
  love.graphics.line(lift.x + 12, lift.y + 12, lift.x + lift.w - 12, lift.y + lift.h - 12)
  love.graphics.line(lift.x + lift.w - 12, lift.y + 12, lift.x + 12, lift.y + lift.h - 12)
  love.graphics.setLineWidth(1)
  -- Along the pad's top edge, clear of him standing on it.
  love.graphics.setFont(UI.fonts.heading)
  local ty = lift.y + 18
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf("OUT OF SERVICE", lift.x + 2, ty + 2, lift.w, "center")
  love.graphics.setColor(1, 0.85, 0.3)
  love.graphics.printf("OUT OF SERVICE", lift.x, ty, lift.w, "center")
  love.graphics.setFont(UI.fonts.small)
  love.graphics.printf("SEE FLOOR MANAGER", lift.x, lift.y + lift.h - 30, lift.w, "center")
end

function FloorManager.drawBelowCars()
  local c = Features.byName["city-map"]
  drawLiftSign(c and c.map)
  local m = shown
  if m and m.move == 1 then -- the legs up: how far the stomp reaches
    local k = math.min(1, (clock - (m.moveAt or clock)) / FloorManager.STOMP_WINDUP)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.12 + 0.18 * k)
    love.graphics.circle("fill", m.dx, m.dy, FloorManager.STOMP_RADIUS, 40)
    love.graphics.setColor(1, 0.6, 0.3, 0.5 + 0.4 * k)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", m.dx, m.dy, FloorManager.STOMP_RADIUS * (1.25 - 0.25 * k), 40)
    love.graphics.setLineWidth(1)
  elseif m and m.move == 2 then -- the cannon charging: where it is pointing
    local ex, ey = Sight.reach(m.dx, m.dy, m.aim, FloorManager.PLASMA_RANGE)
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.12 + 0.2 * math.abs(math.sin(clock * 14)))
    love.graphics.setLineWidth(3)
    love.graphics.line(m.dx, m.dy, ex, ey)
    love.graphics.setLineWidth(1)
  end
  for _, s in ipairs(stomps) do -- dust off the floor
    local k = s.t / STOMP_SHOWN
    love.graphics.setColor(0.6, 0.5, 0.4, 0.5 * (1 - k))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", s.x, s.y, FloorManager.STOMP_RADIUS * (0.5 + 0.7 * k), 40)
    love.graphics.setLineWidth(1)
  end
  if scrap then -- his cannon, lying where it came off
    love.graphics.setColor(STEEL_DARK)
    love.graphics.rectangle("fill", scrap.x - 14, scrap.y - 6, 28, 12, 3)
    love.graphics.setColor(0.25, 0.25, 0.25, math.max(0, 0.6 - scrap.t * 0.05))
    love.graphics.circle("fill", scrap.x + 4, scrap.y - 10 - (scrap.t * 8) % 16, 5, 8) -- smoke
  end
  love.graphics.setColor(1, 1, 1)
end

function FloorManager.drawAboveCars()
  if wreck then
    Look.drawWreck(wreck, clock)
  end
  local m = shown
  if m then
    Look.draw(m.look, m, clock)
    if m.cannon > 0 and m.cannon < 1 then -- the cannon's own health, over it
      local cx = m.dx + math.cos(m.facing) * FloorManager.MUZZLE
      local cy = m.dy + math.sin(m.facing) * FloorManager.MUZZLE - 16
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", cx - 15, cy - 1, 30, 5)
      love.graphics.setColor(GREEN)
      love.graphics.rectangle("fill", cx - 14, cy, 28 * m.cannon, 3)
    end
    if say then
      require("src.features.eternal-mood.horde").drawBubble(m.dx, m.dy - FloorManager.RADIUS - 14, say.text)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function FloorManager.drawNightLights(glow)
  local m = shown
  if m then
    glow(m.dx, m.dy, 120, BRAIN, 0.45) -- his dome
    if m.cannon > 0 then
      local hot = m.move == 2 or m.move == 3
      glow(m.dx + math.cos(m.facing) * FloorManager.MUZZLE, m.dy + math.sin(m.facing) * FloorManager.MUZZLE,
        hot and 130 or 50, GREEN, hot and 0.9 or 0.5)
    end
  end
  local c = Features.byName["city-map"]
  local lift = c and c.map and c.map.horde and c.map.horde.boss and c.map.horde.boss.lift
  if lift and not wreck then
    glow(lift.x + lift.w / 2, lift.y + lift.h / 2, 200, RED, 0.5)
  end
end

--- His bar, once he is fighting.
function FloorManager.drawHUD()
  if not (shown and shown.awake) then
    return
  end
  Bar.draw({
    title = shown.cannon > 0 and "THE FLOOR MANAGER" or "THE FLOOR MANAGER  -  CANNON DOWN", titleColor = BRAIN,
    fill = shown.phase2 and RED or BRAIN, hp = shown.hp, max = shown.max, stamina = shown.stamina, staminaMax = 100,
    winded = shown.winded,
  })
end

FloorManager.clientMessages = {
  FM_STATE = function(_client, args)
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
      shown = { dx = x, dy = y, stride = 0, look = Look.new() }
    end
    local m = shown
    m.x, m.y = x, y
    m.facing = tonumber(args[4]) or m.facing or 0
    m.hp, m.max = tonumber(args[5]) or m.hp, tonumber(args[6]) or m.max
    local move = tonumber(args[7]) or 0
    if move ~= m.move then
      m.moveAt = clock
    end
    m.move = move
    m.aim = tonumber(args[8]) or m.facing
    m.phase2 = args[9] == "1"
    m.awake = args[10] == "1"
    m.cannon = tonumber(args[11]) or 1
    m.stamina, m.winded = Stamina.read(args, 12)
  end,
  FM_SAY = function(_client, args)
    local text = FloorManager.lines[tonumber(args[1]) or 0]
    if text then
      say = { text = text, t = 1.5 + #text * 0.05 }
    end
  end,
  FM_STOMP = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      stomps[#stomps + 1] = { x = x, y = y, t = 0 }
      play("stomp", x, y)
    end
  end,
  FM_SOUND = function(_client, args)
    play(args[1] == "charge" and "charge" or "rear")
  end,
  FM_CANNON = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      scrap = { x = x, y = y, t = 0 }
      play("scrap", x, y)
    end
  end,
  FM_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      wreck = { x = x, y = y, angle = angle }
      play("stomp", x, y)
    end
    shown = nil
  end,
}

Brain = require("src.features.eternal-mood.floor_manager_brain")

return FloorManager
