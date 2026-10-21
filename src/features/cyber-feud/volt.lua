-- General Volt, the Static's general (docs/cyber-feud.md, "General Volt"),
-- in the Market: Kilowatt's right hand, a long coat of cable, a Tesla coil
-- on each shoulder, lightning for a temper. He holds Noodle Square (the
-- map's `volt`) and the loading dock's pass code, and nobody leaves the
-- Market without it: the dock stays locked (`serverLocked`) until he is
-- down and somebody picks the code up off the floor where he fell.
--
-- He waits in the square until a player steps into it (or shoots him),
-- then fights: bolts of lightning down a line he shows you first, lightning
-- grenades that leave a crackling field, and at three quarters, half and a
-- quarter of his health he shouts for backup and a pack of the Static's
-- runs in from the lanes (troops.lua's `serverPack`). This module is the
-- man, the wire, the code and the lock; what he does is his brain's
-- (volt_brain.lua). troops.lua starts, steps and stops him and passes
-- rounds on to him.
--
-- The weather comes with him (the weather feature's): the moment he wakes
-- it starts to rain, and a storm breaks over the square, flashes in the sky
-- and lightning striking round whoever is fighting him (`STRIKE_*`, marked
-- on the ground first), more often in phase 2. The lightning stops when he
-- goes down; the rain keeps on until you leave the Market.
--
-- Like every boss (bosses/init.lua) he has breath, scales with the humans
-- (his health), has the boss bar, goes for medkits when badly hurt, dodges
-- abilities, and going down raises `serverKill` "boss" and spills koins. He
-- also drops his electric grenades, a stack each player can pick up, which
-- unlocks them (the grenades feature's, with the reward screen).
-- Only players' rounds reach him (the feud's pass him by).
--
-- Messages
--   server -> all  VLT_STATE <tick> <x> <y> <facing> <hp> <max> <aiming> <aim> <phase2> <stamina> <winded>
--                  (unreliable, 15 Hz; aiming 1 while his bolt's line is up, 2 for its last moment; empty once
--                  he is gone)
--   server -> all  VLT_SAY   <line>                     he says Volt.lines[line]
--   server -> all  VLT_BOLT  <x0> <y0> <x1> <y1>         a bolt struck down that line
--   server -> all  VLT_LOB   <x0> <y0> <x1> <y1>         a grenade thrown, to land at (x1, y1)
--   server -> all  VLT_FIELD <x> <y>                     it landed: a field crackling there
--   server -> all  VLT_DOWN  <x> <y> <angle>             he went down
--   server -> all  VLT_CODE  <x> <y>                     the pass code lying there (to a joiner too)
--   server -> all  VLT_TAKEN <player>                    somebody picked it up: the dock is open (to a joiner too)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Walk = require("src.features.bosses.walk")
local Bar = require("src.features.bosses.bar")
local Radio = require("src.features.a-man.radio")
local Hud = require("src.features.cyber-feud.hud")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Volt = {}
Volt.__index = Volt

local Brain

-- Tuning --------------------------------------------------------------------

Volt.HEALTH = 1800 -- for one player (more humans, more: bosses/init.lua)
Volt.RADIUS = 14 -- px
Volt.WALK = 85 -- px/s
Volt.STROLL = 40 -- px/s winded
Volt.BREATH = { drain = 10, regen = 14, recovered = 50, breath = 40 }
Volt.RANGE = 720 -- px he sees
Volt.KEEP = 320 -- px he keeps from whoever he has
Volt.KITE_FAR = 200 -- px: kiting to a medkit, he stops to bolt only while it is further than this
Volt.BOLT_RANGE = 640 -- px a bolt reaches (or the first wall)
Volt.BOLT_WIDTH = 20 -- px either side of its line it hits
Volt.BOLT_DAMAGE = 30 -- shock: a stun
Volt.AIM = 0.9 -- seconds his line shows before the bolt...
Volt.AIM_2 = 0.65 -- ...in phase 2
Volt.SET = 0.35 -- ...the last of which it holds still: step off it
Volt.BOLT_EVERY = 3.2
Volt.BOLT_EVERY_2 = 2.4
Volt.FORK = 0.2 -- radians either side, his phase-2 pair
Volt.LOB_RANGE = 560 -- px
Volt.LOB_EVERY = 7
Volt.LOB_COST = 20 -- breath
Volt.FLIGHT = 0.9 -- seconds a grenade is in the air (the ring on the ground shows where)
Volt.FIELD_RADIUS = 110 -- px
Volt.FIELD_TIME = 4 -- seconds a field crackles
Volt.FIELD_FIRST = 22 -- shock, the first jolt it gives anyone (a stun)...
Volt.FIELD_DAMAGE = 8 -- ...and every FIELD_EVERY after while they stay
Volt.FIELD_EVERY = 0.5
Volt.BACKUP_AT = { 0.75, 0.5, 0.25 } -- shares of his health he shouts for backup at
Volt.BACKUP_PACK = 3 -- gangers in a pack (and a sparker with them; more players, more: Bosses.plus)
Volt.SAY_EVERY = { 8, 13 }
Volt.DROPS = 30
Volt.CODE_REACH = 44 -- px from the pass code that picks it up
Volt.STRIKE_EVERY = { 3.5, 6 } -- seconds between lightning strikes while he fights...
Volt.STRIKE_EVERY_2 = { 2.2, 4 } -- ...in phase 2
Volt.STRIKE_WARN = 1.1 -- seconds a strike is marked on the ground first
Volt.STRIKE_RADIUS = 55 -- px
Volt.STRIKE_DAMAGE = 20 -- shock, to someone on foot
Volt.STRIKE_AIMED = 0.4 -- chance it comes down right on them (within 30 px)...
Volt.STRIKE_NEAR, Volt.STRIKE_FAR = 90, 320 -- ...the rest this far off
Volt.GRENADES_AWAY = 160 -- px from his body his electric grenades land: well clear of the pass code

Volt.lines = {
  "You want the dock code? Come and get it, courier.",
  "Kilowatt sends his regards. All of them. At once.",
  "Feel that? That's ten thousand volts of personality.",
  "Stand still. I'm trying to ground you.",
  "Boys! The square! NOW!",
  "Backup! Everybody! Bring the cables!",
  "Now I'm charged.",
  "Recharging. Don't go anywhere.",
  "Tell Kilowatt... I went out... in a blaze...",
  "Nobody walks out of my square.",
}
Volt.LINE = { intro = 1, taunt = { 2, 3, 4, 10 }, backup = { 5, 6 }, phase2 = 7, heal = 8, down = 9 }

local CYAN = { 0.18, 0.90, 1.00 }
local HOT = { 0.80, 0.98, 1.00 }
local LOOK = {
  shirt = { 0.16, 0.20, 0.23 }, pants = { 0.12, 0.13, 0.15 }, shoes = { 0.05, 0.05, 0.06 },
  skin = { 0.62, 0.47, 0.38 }, hair = { 0.85, 0.92, 0.95 }, size = 1.5,
}
local SCALE = 1.5

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The man ---------------------------------------------------------------------

function Volt.new(x, y, hp, nav)
  return setmetatable({
    x = x, y = y, facing = math.pi / 2, aim = math.pi / 2, hp = hp, max = hp, time = 0,
    aiming = false, aimT = 0, boltIn = 1.5, lobIn = 4, sayIn = 6, frozen = 0, stuck = 0, side = 0.5,
    phase2 = false, backups = 0, grenades = {}, breath = Stamina.new(Volt.BREATH), running = false, mode = "hunt",
    power = Bosses.power(), -- what his hits are multiplied by: harder on a job finished before
    nav = nav and Walk.nav(nav, Sight.blocked, Volt.RADIUS), -- the walking grid as he fits through it
  }, Volt)
end

--- A tick along `angle` at `speed`, round the stalls (bosses/walk.lua).
--- False when he got nowhere.
function Volt:walk(angle, speed, dt)
  return Walk.step(self, Sight.blocked, angle, speed, dt, Volt.RADIUS)
end

function Volt:pace()
  return self.breath:pace(Volt.WALK, Volt.STROLL)
end

-- Server --------------------------------------------------------------------

local function weather()
  return Features.byName.weather
end

local sv = nil -- { v, spec, awake, greet, syncIn, down, code = { x, y } | nil, taken }

--- Him in `map`'s `volt` square, finding his way on `nav`. Nothing on a map without him.
function Volt.serverStart(server, map, nav)
  Volt.serverStop(server)
  local spec = map.volt
  if not spec then
    return
  end
  sv = { v = Volt.new(spec.x, spec.y, Bosses.health(Volt.HEALTH, server), nav), spec = spec, awake = false,
    syncIn = 0 }
end

function Volt.serverStop(server)
  if sv then
    if sv.awake and not sv.down and weather() then
      weather():serverSetStorm(server, false)
    end
    sv = nil
    server:broadcast(Protocol.encode("VLT_STATE", server.tick))
  end
end

--- Is the dock still locked (he has the code, or it lies where he fell)?
function Volt.serverLocked()
  return sv ~= nil and not sv.taken
end

local function wake(server)
  if not sv.awake then
    sv.awake = true
    sv.strikeIn = Volt.STRIKE_EVERY[1]
    local w = weather()
    if w then
      w:serverSetRain(server, true)
      w:serverSetStorm(server, true)
    end
    server:broadcast(Protocol.encode("VLT_SAY", Volt.LINE.intro))
    server:broadcast(Protocol.encode("CF_BEAT", "market.volt"))
  end
end

--- His backup: a pack of the Static's from each lane he has, running at
--- whoever he has.
local function backup(server)
  local Troops = require("src.features.cyber-feud.troops")
  local spec, v = sv.spec, sv.v
  local _, tx, ty = Brain.target(v, server)
  local size = Bosses.plus(Volt.BACKUP_PACK, server)
  local spot = spec.backup[(v.backups - 1) % #spec.backup + 1]
  Troops.serverPack(server, "static", spot, spec.beat, size, true, tx or v.x, ty or v.y)
end

--- Lightning round whoever is fighting him: a human in the square (or the
--- nearest one near him), on them or a little off.
local function lightning(server, dt)
  local w = weather()
  sv.strikeIn = sv.strikeIn - dt
  if not w or sv.strikeIn > 0 then
    return
  end
  local e = sv.v.phase2 and Volt.STRIKE_EVERY_2 or Volt.STRIKE_EVERY
  sv.strikeIn = e[1] + random() * (e[2] - e[1])
  local sq, v = sv.spec.square, sv.v
  local near = {}
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x >= sq.x0 and x <= sq.x1 and y >= sq.y0 and y <= sq.y1) or dist2(x, y, v.x, v.y) <= Volt.RANGE ^ 2 then
        near[#near + 1] = { x = x, y = y }
      end
    end
  end
  if #near == 0 then
    return
  end
  local t = near[random(#near)]
  local a, d = random() * 2 * math.pi, random() * 30
  if random() >= Volt.STRIKE_AIMED then
    d = Volt.STRIKE_NEAR + random() * (Volt.STRIKE_FAR - Volt.STRIKE_NEAR)
  end
  w:serverStrike(server, t.x + math.cos(a) * d, t.y + math.sin(a) * d,
    { warn = Volt.STRIKE_WARN, radius = Volt.STRIKE_RADIUS, damage = Volt.STRIKE_DAMAGE * sv.v.power })
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local v = sv.v
  local stamina, winded = v.breath:wire()
  local aiming = 0
  if v.aiming then
    aiming = v.aimT > (v.phase2 and Volt.AIM_2 or Volt.AIM) - Volt.SET and 2 or 1
  end
  local msg = Protocol.encode("VLT_STATE", server.tick, ("%.0f"):format(v.x), ("%.0f"):format(v.y),
    ("%.2f"):format(v.facing), ("%.0f"):format(math.max(0, v.hp)), ("%.0f"):format(v.max), aiming,
    ("%.3f"):format(v.aim), v.phase2 and 1 or 0, stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

function Volt.serverStep(server, dt)
  if not sv then
    return
  end
  if sv.down then -- the code on the floor: the first player on foot over it has it
    if sv.code and not sv.taken then
      for _, p in pairs(server.players) do
        if not p.bot and Features.present(p) then
          local x, y = Features.bodyPose(server, p)
          if dist2(x, y, sv.code.x, sv.code.y) <= Volt.CODE_REACH ^ 2 then
            sv.taken = true
            server:broadcast(Protocol.encode("VLT_TAKEN", p.id))
            server:broadcast(Protocol.encode("CF_BEAT", "market.code"))
            break
          end
        end
      end
    end
    return
  end
  if not sv.awake then
    local sq = sv.spec.square
    for _, p in pairs(server.players) do
      if not p.bot and Features.present(p) then
        local x, y = Features.bodyPose(server, p)
        if x >= sq.x0 and x <= sq.x1 and y >= sq.y0 and y <= sq.y1 then
          wake(server)
        end
      end
    end
  end
  if sv.awake then
    lightning(server, dt)
    for _, e in ipairs(Brain.think(sv.v, server, dt)) do
      if e[1] == "say" then
        server:broadcast(Protocol.encode("VLT_SAY", e[2]))
      elseif e[1] == "bolt" then
        server:broadcast(Protocol.encode("VLT_BOLT", fmt(e[2]), fmt(e[3]), fmt(e[4]), fmt(e[5])))
      elseif e[1] == "lob" then
        server:broadcast(Protocol.encode("VLT_LOB", fmt(e[2]), fmt(e[3]), fmt(e[4]), fmt(e[5])))
      elseif e[1] == "field" then
        server:broadcast(Protocol.encode("VLT_FIELD", fmt(e[2]), fmt(e[3])))
      elseif e[1] == "backup" then
        backup(server)
      end
    end
  end
  sync(server)
end

--- Open ground `Volt.GRENADES_AWAY` from (x, y) with nothing solid on the
--- way there (the `blocksPoint` convention), for his grenades: the first of
--- eight directions round him that is clear, or right beside him if none is.
local function grenadeSpot(x, y)
  local d = Volt.GRENADES_AWAY
  for i = 0, 7 do
    local a = i * math.pi / 4
    local clear = true
    for k = 1, 8 do
      local px, py = x + math.cos(a) * d * k / 8, y + math.sin(a) * d * k / 8
      if Features.any("blocksPoint", px, py) then
        clear = false
        break
      end
    end
    if clear then
      return x + math.cos(a) * d, y + math.sin(a) * d
    end
  end
  return x + 48, y + 10
end

--- Down: his last word, his body, koins, the kill, and the pass code on the floor.
local function down(server, by, angle)
  local v = sv.v
  sv.down = true
  if weather() then
    weather():serverSetStorm(server, false) -- the rain keeps on
  end
  sv.code = { x = v.x, y = v.y }
  server:broadcast(Protocol.encode("VLT_SAY", Volt.LINE.down))
  server:broadcast(Protocol.encode("VLT_DOWN", fmt(v.x), fmt(v.y), ("%.3f"):format(angle or 0)))
  server:broadcast(Protocol.encode("VLT_STATE", server.tick + 1))
  server:broadcast(Protocol.encode("VLT_CODE", fmt(v.x), fmt(v.y)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, v.x, v.y, Volt.DROPS)
  end
  -- His electric grenades: a stack for every player (each takes their own),
  -- which unlocks them (the grenades feature's). Away from his body, so
  -- going for them and their reward screen isn't mistaken for the pass code.
  local pickups, grenades = Features.byName.pickups, Features.byName.grenades
  if pickups and pickups.serverDrop and grenades and grenades.kinds then
    local gx, gy = grenadeSpot(v.x, v.y)
    pickups:serverDrop(server, "grenade-electric", gx, gy, grenades.kinds["grenade-electric"].reward,
      { perPlayer = true, unlocks = true })
  end
  Features.call("serverKill", server, { kind = "boss", x = v.x, y = v.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him (and wakes him). Returns true when it hit.
function Volt.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.down or by == 0 then
    return false
  end
  local v = sv.v
  if dist2(x, y, v.x, v.y) > (Volt.RADIUS + (radius or 0)) ^ 2 then
    return false
  end
  wake(server)
  v.hp = v.hp - (damage or 20)
  if v.hp <= 0 then
    down(server, by, angle)
  end
  return true
end

--- Him, until he is down, for the audit (tools/audit).
function Volt.serverEnemies(_server, add)
  if sv and not sv.down then
    local v = sv.v
    add({ id = v, kind = "cyber-feud/volt", x = v.x, y = v.y, hp = v.hp, radius = Volt.RADIUS })
  end
end

--- The wiki's page on him (tools/wiki, docs/wiki.md).
function Volt.wikiEnemies(add)
  local function pcts(list)
    local out = {}
    for i, share in ipairs(list) do
      out[i] = ("%g%%"):format(share * 100)
    end
    return table.concat(out, ", ")
  end
  add({
    kind = "cyber-feud/volt",
    boss = true,
    name = "General Volt",
    quests = { "cyber-feud-market" },
    where = "The Market's Noodle Square, holding the loading dock's pass code",
    about = "The Static's general and Kilowatt's right hand: a long coat of cable, a Tesla coil on each shoulder and "
      .. "lightning for a temper. Nobody leaves the Market until he is down and somebody picks his pass code up off "
      .. "the floor.",
    stats = {
      { "Health", Volt.HEALTH },
      { "Speed", ("%g px/s, %g winded"):format(Volt.WALK, Volt.STROLL) },
      { "Sight", Volt.RANGE, "px" },
    },
    weapons = {
      { "Bolt", ("%g shock damage (a stun) to whoever is within %g px of its line, out to %g px; the line shows for "
        .. "%g s first (%g in phase 2), set for the last %g s; every %g s (%g in phase 2)"):format(Volt.BOLT_DAMAGE,
        Volt.BOLT_WIDTH, Volt.BOLT_RANGE, Volt.AIM, Volt.AIM_2, Volt.SET, Volt.BOLT_EVERY, Volt.BOLT_EVERY_2) },
      { "Lightning grenade", ("thrown up to %g px every %g s, landing %g s later as a crackling field %g px round "
        .. "for %g s: %g shock damage (a stun) on the first jolt, then %g every %g s while you stay"):format(
        Volt.LOB_RANGE, Volt.LOB_EVERY, Volt.FLIGHT, Volt.FIELD_RADIUS, Volt.FIELD_TIME, Volt.FIELD_FIRST,
        Volt.FIELD_DAMAGE, Volt.FIELD_EVERY) },
      { "The storm", ("lightning strikes round whoever is fighting him every %g to %g s (%g to %g in phase 2), "
        .. "marked on the ground %g s first: %g shock damage within %g px"):format(Volt.STRIKE_EVERY[1],
        Volt.STRIKE_EVERY[2], Volt.STRIKE_EVERY_2[1], Volt.STRIKE_EVERY_2[2], Volt.STRIKE_WARN, Volt.STRIKE_DAMAGE,
        Volt.STRIKE_RADIUS) },
    },
    abilities = {
      "Waits in the square until a player steps into it or shoots him; then the rain starts and a storm breaks.",
      ("Keeps %g px from whoever he has."):format(Volt.KEEP),
      ("Shouts for backup at %s of his health: a pack of %g gangers and a sparker runs in from the lanes."):format(
        pcts(Volt.BACKUP_AT), Volt.BACKUP_PACK),
      "Phase 2 at half health: his bolts come in a forked pair and he throws two grenades at once.",
      "Goes for a medkit when badly hurt, dodges abilities about to land on him, and runs out of breath.",
      "Only players' rounds reach him.",
    },
    tips = {
      "Step off his crackling line before it strikes: it holds still at the end.",
      "Keep out of the rings where his grenades and the storm's strikes will land.",
      "Hit him while he is winded, and thin out his backup before it gets to you.",
    },
    drops = ("%g koins, his pass code, and electric grenades for every player (unlocking them)"):format(Volt.DROPS),
  })
end

function Volt.serverFreezeArea(x, y, radius, seconds)
  if sv and not sv.down and dist2(x, y, sv.v.x, sv.v.y) <= radius * radius then
    sv.v.frozen = math.max(sv.v.frozen, seconds)
  end
end

function Volt.serverPlayerJoined(server, player)
  if not sv or player.bot then
    return
  end
  if sv.taken then
    server:send(player, Protocol.encode("VLT_TAKEN", 0))
  elseif sv.code then
    server:send(player, Protocol.encode("VLT_CODE", fmt(sv.code.x), fmt(sv.code.y)))
  end
end

--- For tests.
function Volt.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = nil
local say = nil
local bolts = {} -- { x0, y0, x1, y1, t }
local lobs = {} -- { x0, y0, x1, y1, t }
local fields = {} -- { x, y, t }
local code = nil -- { x, y } on the floor
local taken = false
local lastTick, heardAt, clock = 0, 0, 0

local BOLT_SHOWN = 0.25
local zap = nil

--- His bolt's crack, synthesised once: a snap of noise and a falling buzz.
function Volt.load()
  local buf = Synth.newBuffer(0.4)
  buf:noiseBurst(0, 0.12, { amp = 0.8, decay = 0.04 })
  buf:sweep(0, 0.35, 900, 120, { wave = "square", amp = 0.35, decay = 0.1 })
  buf:highpass(150)
  zap = love.audio.newSource(buf:toSoundData(0.9), "static")
  zap:setAttenuationDistances(300, 2400)
end

local function play(x, y)
  if zap then
    local s = zap:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + random() * 0.2)
    s:setVolume(0.7 * Audio.volume("weapons"))
    s:play()
  end
end

function Volt.clear()
  shown, say, bolts, lobs, fields, code, taken, lastTick = nil, nil, {}, {}, {}, nil, false, 0
end

--- What this screen knows of him: "up" while he fights or waits, "code"
--- while the pass code lies on the floor, "open" once it is picked up, nil
--- on a map without him. And where (him, or the code).
function Volt.status()
  local c = Features.byName["city-map"]
  if not (c and c.map and c.map.volt) then
    return nil
  end
  if taken then
    return "open"
  elseif code then
    return "code", code.x, code.y
  end
  return "up", shown and shown.dx or c.map.volt.x, shown and shown.dy or c.map.volt.y
end

function Volt.update(dt)
  clock = clock + dt
  if shown and love.timer.getTime() - heardAt > 1.5 then
    shown = nil
  end
  if shown then
    local k = math.min(1, dt * 14)
    shown.dx, shown.dy = shown.dx + (shown.x - shown.dx) * k, shown.dy + (shown.y - shown.dy) * k
    shown.stride = shown.stride + math.sqrt((shown.x - shown.dx) ^ 2 + (shown.y - shown.dy) ^ 2) * k
  end
  for _, list in ipairs({ bolts, lobs, fields }) do
    for i = #list, 1, -1 do
      list[i].t = list[i].t + dt
    end
  end
  for i = #bolts, 1, -1 do
    if bolts[i].t > BOLT_SHOWN then
      table.remove(bolts, i)
    end
  end
  for i = #lobs, 1, -1 do
    if lobs[i].t > Volt.FLIGHT then
      table.remove(lobs, i)
    end
  end
  for i = #fields, 1, -1 do
    if fields[i].t > Volt.FIELD_TIME then
      table.remove(fields, i)
    end
  end
  if say then
    say.t = say.t - dt
    if say.t <= 0 then
      say = nil
    end
  end
end

--- A jagged line from (x0, y0) to (x1, y1).
local function jagged(x0, y0, x1, y1, n, spread)
  local pts = { x0, y0 }
  for s = 1, n - 1 do
    local f = s / n
    pts[#pts + 1] = x0 + (x1 - x0) * f + (random() - 0.5) * spread
    pts[#pts + 1] = y0 + (y1 - y0) * f + (random() - 0.5) * spread
  end
  pts[#pts + 1], pts[#pts + 2] = x1, y1
  return pts
end

function Volt.drawBelowCars()
  local c = Features.byName["city-map"]
  Volt.drawDock(c and c.map)
  for _, f in ipairs(fields) do -- the crackling fields
    local fade = math.min(1, (Volt.FIELD_TIME - f.t) / 0.4)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.18 * fade)
    love.graphics.circle("fill", f.x, f.y, Volt.FIELD_RADIUS, 40)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 * fade)
    love.graphics.circle("line", f.x, f.y, Volt.FIELD_RADIUS, 40)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.8 * fade)
    for _ = 1, 4 do
      local a, d = random() * 2 * math.pi, random() * Volt.FIELD_RADIUS
      local x, y = f.x + math.cos(a) * d, f.y + math.sin(a) * d
      love.graphics.line(jagged(x, y, x + (random() - 0.5) * 50, y + (random() - 0.5) * 50, 3, 10))
    end
  end
  for _, l in ipairs(lobs) do -- where each grenade will come down
    local k = l.t / Volt.FLIGHT
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.3 + 0.4 * k)
    love.graphics.setLineWidth(2)
    love.graphics.circle("line", l.x1, l.y1, Volt.FIELD_RADIUS * (0.4 + 0.6 * k), 32)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

local CODE_GOLD = { 1, 0.82, 0.25 } -- not cyan: his grenades and fields are that

--- The pass code on the floor, over his body, the koins and any car: a gold
--- keycard in a pulsing ring, with a beam up from it and PASS CODE over it.
local function drawCode()
  local x, y = code.x, code.y
  local pulse = 0.5 + 0.5 * math.sin(clock * 5)
  local bob = math.sin(clock * 4) * 2
  local g = CODE_GOLD
  love.graphics.setColor(g[1], g[2], g[3], 0.12 + 0.12 * pulse)
  love.graphics.circle("fill", x, y, 30 + 6 * pulse, 32)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(g[1], g[2], g[3], 0.5 + 0.4 * pulse)
  love.graphics.circle("line", x, y, Volt.CODE_REACH * (0.7 + 0.3 * (clock * 0.8 % 1)), 40)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(g[1], g[2], g[3], 0.18)
  love.graphics.polygon("fill", x - 4, y, x + 4, y, x + 1, y - 60, x - 1, y - 60) -- a beam up from it
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", x - 12, y - 5, 26, 17, 3)
  love.graphics.setColor(0.12, 0.14, 0.16)
  love.graphics.rectangle("fill", x - 13, y - 9 + bob, 26, 17, 3)
  love.graphics.setColor(g)
  love.graphics.rectangle("line", x - 13, y - 9 + bob, 26, 17, 3)
  love.graphics.rectangle("fill", x - 9, y - 5 + bob, 10, 3)
  love.graphics.rectangle("fill", x - 9, y + bob, 16, 3)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local text = "PASS CODE"
  UI.label(text, x - math.floor(font:getWidth(text) / 2), y - 34 + bob, g)
  love.graphics.setColor(1, 1, 1)
end

local function drawLine(v)
  if v.aiming == 0 then
    return
  end
  local aims = v.phase2 and { v.aim - Volt.FORK, v.aim + Volt.FORK } or { v.aim }
  for _, a in ipairs(aims) do
    local x1, y1 = Sight.reach(v.dx, v.dy, a, Volt.BOLT_RANGE)
    local set = v.aiming == 2
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], set and 0.3 or 0.15)
    love.graphics.setLineWidth(Volt.BOLT_WIDTH * 2)
    love.graphics.line(v.dx, v.dy, x1, y1)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], set and 0.9 or 0.45)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(jagged(v.dx, v.dy, x1, y1, 10, set and 6 or 12))
  end
  love.graphics.setLineWidth(1)
end

function Volt.drawAboveCars()
  if code then
    drawCode()
  end
  for _, b in ipairs(bolts) do
    local fade = 1 - b.t / BOLT_SHOWN
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.5 * fade)
    love.graphics.setLineWidth(8)
    love.graphics.line(jagged(b.x0, b.y0, b.x1, b.y1, 12, 26))
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], fade)
    love.graphics.setLineWidth(2.5)
    love.graphics.line(jagged(b.x0, b.y0, b.x1, b.y1, 12, 18))
    love.graphics.setLineWidth(1)
  end
  for _, l in ipairs(lobs) do -- the canister in the air
    local k = l.t / Volt.FLIGHT
    local x, y = l.x0 + (l.x1 - l.x0) * k, l.y0 + (l.y1 - l.y0) * k - math.sin(k * math.pi) * 90
    love.graphics.setColor(0.2, 0.22, 0.25)
    love.graphics.circle("fill", x, y, 5, 10)
    love.graphics.setColor(CYAN)
    love.graphics.circle("fill", x, y, 2.4, 8)
  end
  local v = shown
  if v then
    drawLine(v)
    local angle = v.aiming > 0 and v.aim or v.facing
    love.graphics.push()
    love.graphics.translate(v.dx, v.dy)
    love.graphics.scale(SCALE)
    Body.person(0, 0, angle, math.sin(v.stride * 0.15) * 1.2, LOOK)
    love.graphics.rotate(angle)
    for _, s in ipairs({ -1, 1 }) do -- the Tesla coils on his shoulders
      love.graphics.setColor(0.3, 0.32, 0.35)
      love.graphics.circle("fill", -1, s * 7.5, 2.6, 10)
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * math.abs(math.sin(clock * 9 + s)))
      love.graphics.circle("fill", -1, s * 7.5, 1.4, 8)
    end
    if v.aiming > 0 or (v.phase2 and random() < 0.5) then -- arcs off his coils and his hand
      love.graphics.setColor(HOT)
      love.graphics.line(jagged(-1, -7.5, 8, 4, 3, 4))
      love.graphics.line(jagged(-1, 7.5, 8, 4, 3, 4))
    end
    love.graphics.pop()
    if say then
      Hud.drawBubble(v.dx, v.dy - Body.SHOULDERS * SCALE - 10, say.text, math.min(1, say.t * 2), CYAN)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Volt.drawNightLights(glow)
  if shown then
    glow(shown.dx, shown.dy, shown.aiming > 0 and 120 or 70, CYAN, 0.7)
  end
  for _, b in ipairs(bolts) do
    glow((b.x0 + b.x1) / 2, (b.y0 + b.y1) / 2, 200, CYAN, 0.6 * (1 - b.t / BOLT_SHOWN))
  end
  for _, f in ipairs(fields) do
    glow(f.x, f.y, Volt.FIELD_RADIUS + 40, CYAN, 0.4)
  end
  if code then
    glow(code.x, code.y, 60, CYAN, 0.8)
  end
end

--- His bar (only once he is fighting: waiting, he isn't on the wire as hurt).
function Volt.drawHUD()
  if not (shown and shown.awake) then
    return
  end
  Bar.draw({
    title = "GENERAL VOLT", titleColor = CYAN, fill = shown.phase2 and HOT or CYAN, hp = shown.hp, max = shown.max,
    stamina = shown.stamina, staminaMax = 100, winded = shown.winded,
  })
end

--- The dock, shut while the code isn't picked up: a shutter of cyan bars
--- over the way out with LOCKED on it. (The map's `volt.dock`.)
function Volt.drawDock(map)
  local d = map and map.volt and map.volt.dock
  if not d or taken then
    return
  end
  love.graphics.setColor(0.08, 0.09, 0.1, 0.85)
  love.graphics.rectangle("fill", d.x, d.y, d.w, d.h)
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.3 * math.abs(math.sin(clock * 3)))
  for x = d.x + 8, d.x + d.w - 8, 16 do
    love.graphics.rectangle("fill", x, d.y + 4, 3, d.h - 8)
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 0.4, 0.4)
  love.graphics.printf("LOCKED  -  PASS CODE", d.x, d.y + d.h / 2 - 7, d.w, "center")
  love.graphics.setColor(1, 1, 1)
end

Volt.clientMessages = {
  VLT_STATE = function(_client, args)
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
    local v = shown
    v.x, v.y = x, y
    v.facing = tonumber(args[4]) or v.facing or 0
    local hp, max = tonumber(args[5]), tonumber(args[6])
    v.awake = v.awake or (hp and max and hp < max) or (tonumber(args[7]) or 0) > 0
    v.hp, v.max = hp or v.hp, max or v.max
    v.aiming = tonumber(args[7]) or 0
    v.aim = tonumber(args[8]) or v.facing
    v.phase2 = args[9] == "1"
    v.stamina, v.winded = Stamina.read(args, 10)
  end,
  VLT_SAY = function(_client, args)
    local n = tonumber(args[1]) or 0
    local text = Volt.lines[n]
    if text then
      say = { text = text, t = Radio.sayTime(text) }
      if shown and n == Volt.LINE.intro then
        shown.awake = true
      end
    end
  end,
  VLT_BOLT = function(_client, args)
    local x0, y0, x1, y1 = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x0 and y0 and x1 and y1 then
      bolts[#bolts + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, t = 0 }
      play(x0, y0)
    end
  end,
  VLT_LOB = function(_client, args)
    local x0, y0, x1, y1 = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x0 and y0 and x1 and y1 then
      lobs[#lobs + 1] = { x0 = x0, y0 = y0, x1 = x1, y1 = y1, t = 0 }
    end
  end,
  VLT_FIELD = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      fields[#fields + 1] = { x = x, y = y, t = 0 }
    end
  end,
  VLT_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if x and y then
      Corpses.add(x, y, angle, LOOK)
    end
    shown = nil
  end,
  VLT_CODE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      code = { x = x, y = y }
    end
  end,
  VLT_TAKEN = function()
    code, taken = nil, true
  end,
}

Brain = require("src.features.cyber-feud.volt_brain")

return Volt
