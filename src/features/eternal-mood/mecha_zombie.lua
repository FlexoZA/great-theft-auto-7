-- The Mecha Zombies (docs/eternal-mood.md, "The possessed"): a zombie the
-- UAC rebuilt, a plasma cannon for a right arm, a flamethrower and talons
-- on the left, a red optic where an eye was. Ranged fodder: one walks a
-- loop round each Intern mob while it eats (city-map's `feast`, the map's
-- `horde.mechas`), on Fobos Base, Earth and the Foundry.
--
-- It wakes when a player comes into its sight (SEES, no wall in between),
-- shoots it, or its mob wakes; waking, it screams, and every mob and every
-- one of the possessed within SCREAM_RADIUS comes (horde.lua's
-- `serverScream`), the other Mecha Zombies too. Then it fights by range:
-- plasma from afar, its flamethrower at mid range, talons up close (what
-- it does is its brain's, mecha_zombie_brain.lua; how it looks
-- mecha_zombie_look.lua's). Its rounds are the horde's (Horde.FROM): they
-- never hurt anything of Heck's.
--
-- Down, it drops koins and maybe a pickup, and raises `serverKill`.
--
-- Messages
--   server -> all  MZ_STATE  <tick> [<id> <x> <y> <facing> <hp> <max> <move> <awake>]...  (unreliable, 15 Hz; move
--                  0 none, 1 cannon glowing, 2 firing plasma, 3 pilot light flaring, 4 flaming, 5 talons up,
--                  6 screaming)
--   server -> all  MZ_SCREAM <id> <x> <y> <radius>   it screamed: the sound wave goes out that far
--   server -> all  MZ_HIT    <name> <x> <y>          talons (they landed)
--   server -> all  MZ_DOWN   <id> <x> <y> <angle>    one went down (to a joiner too, for the bodies)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Onscreen = require("src.features.eternal-mood.onscreen")
local Horde = require("src.features.eternal-mood.horde")
local Look = require("src.features.eternal-mood.mecha_zombie_look")

local Mecha = {}
Mecha.__index = Mecha

local Brain

-- Tuning --------------------------------------------------------------------

Mecha.HEALTH = 80 -- a guard has 60, the overtime guy 100
Mecha.RADIUS = 11 -- px (mecha_zombie_look.lua draws it); a person is 9
Mecha.WALK = 70 -- px/s
Mecha.PATROL = 40 -- px/s round its loop
Mecha.TURN = 4 -- rad/s
Mecha.SEES = 600 -- px, no wall in between
Mecha.HUNTS = 1300 -- px: awake, it goes after the nearest player this near
Mecha.LOOK_FOR = 1.2 -- seconds it stops at each corner of its loop
Mecha.KEEP = { 140, 380 } -- px it holds at from whoever it's fighting
Mecha.PLASMA_FROM = 300 -- px: past this, plasma...
Mecha.PLASMA_WINDUP = 0.4 -- seconds its cannon glows first
Mecha.BURST = 3 -- bolts a go...
Mecha.PLASMA_GAP = 0.18 -- ...this far apart
Mecha.PLASMA_EVERY = { 1.6, 2.4 } -- seconds between bursts
Mecha.FLAME_WINDUP = 0.35 -- seconds its pilot light flares first...
Mecha.FLAME_FOR = 1.4 -- ...then it sprays this long...
Mecha.FLAME_EVERY = 2.0 -- ...and waits this long
Mecha.TALON_REACH = 40 -- px: this near, talons...
Mecha.TALON_WINDUP = 0.3
Mecha.TALON_DAMAGE = 16 -- melee
Mecha.TALON_EVERY = 0.9
Mecha.SCREAM_WINDUP = 0.9 -- seconds of it before it carries
Mecha.SCREAM_RADIUS = 560 -- px it carries
Mecha.SCREAM_EVERY = 18 -- seconds before it screams again, still seeing somebody
Mecha.HAND = 9 -- px either side of its middle: the cannon (right) and the flamer (left)...
Mecha.MUZZLE = 20 -- ...this far ahead of it
Mecha.DROPS = 4 -- koins
Mecha.PICKUP = 0.35 -- chance of a pickup

-- Its plasma: bolts of it, slow and bright, burning (`fire`).
Mecha.PLASMA = { damage = 9, damageType = "fire", ignite = { seconds = 1.5, dps = 4 }, speed = 520, ttl = 1.5,
  spread = 0.03, tint = "7fe8ff", streak = 14 }
-- Its flamethrower: the flamethrower's, weaker, reaching about 280 px.
Mecha.FLAME = { damage = 3, ttl = 0.78, ignite = { seconds = 2, dps = 6 } }

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The zombie ---------------------------------------------------------------

local plasmaGun, flameGun

--- Its two guns, built once: the SMG's bolts and the flamethrower's flame,
--- with its own numbers over them.
local function guns()
  if not plasmaGun then
    plasmaGun = setmetatable(Mecha.PLASMA, { __index = Tiers.apply(Guns.smg, Tiers.DEFAULT) })
    flameGun = setmetatable(Mecha.FLAME, { __index = Tiers.apply(Guns.flamethrower, Tiers.DEFAULT) })
  end
  return plasmaGun, flameGun
end

function Mecha.new(id, spec, nav)
  local start = spec.route[1]
  local plasma, flame = guns()
  local hp = Bosses.enemyHealth(Mecha.HEALTH) -- tougher on a job finished before
  return setmetatable({
    id = id, x = start.x, y = start.y, facing = random() * 2 * math.pi, hp = hp, max = hp,
    nav = nav, route = spec.route, mob = spec.mob, leg = math.min(2, #spec.route), lookFor = 0, time = 0,
    move = nil, moveT = 0, plasmaIn = 0.5, flameCool = 0, talonIn = 0, screamIn = 0, frozen = 0, stuck = 0,
    side = random() < 0.5 and 1 or -1, awake = false, mode = "patrol",
    plasmaGun = plasma, flameGun = flame,
  }, Mecha)
end

function Mecha.fits(x, y)
  return Ground.fits(x, y, Mecha.RADIUS)
end

function Mecha:turn(angle, dt, rate)
  local d = Sight.angleDiff(angle, self.facing)
  local step = (rate or Mecha.TURN) * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

function Mecha:walk(angle, speed, dt)
  return Ground.walk(self, angle, speed, dt, Mecha.RADIUS)
end

--- Where its cannon (`side` 1) or flamer (-1) fires from.
function Mecha:muzzle(side)
  local fx, fy = math.cos(self.facing), math.sin(self.facing)
  return self.x + fx * Mecha.MUZZLE - fy * Mecha.HAND * side, self.y + fy * Mecha.MUZZLE + fx * Mecha.HAND * side
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list, fallen = { { id, x, y, angle } }, syncIn }

--- One round each mob's loop (`map.horde.mechas`), finding its way on `nav`.
function Mecha.serverStart(server, map, nav)
  Mecha.serverStop(server)
  local specs = map.horde and map.horde.mechas
  if not (specs and #specs > 0) then
    return
  end
  sv = { list = {}, fallen = {}, syncIn = 0 }
  for _, spec in ipairs(specs) do
    local route = {} -- the corners it fits at (the map only knows the floor, not its width)
    for _, p in ipairs(spec.route) do
      if Mecha.fits(p.x, p.y) then
        route[#route + 1] = p
      end
    end
    if #route >= 2 then
      sv.list[#sv.list + 1] = Mecha.new(#sv.list + 1, { route = route, mob = spec.mob }, nav)
    end
  end
end

function Mecha.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("MZ_STATE", server.tick))
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local function wake(z)
  z.awake = true
end

-- Its hands, for its brain.
local hands = {}

function hands.fire(server, _z, x, y, angle, gun)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    weapons:serverFireFrom(server, 0, x, y, angle, gun, Horde.FROM)
  end
end

function hands.cut(server, _z, p, damage, angle)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage and p then
    weapons:serverDamage(server, p, nil, damage * Bosses.enemyPower(), angle, "melee") -- harder on a job done before
  end
end

--- The scream: the horde near it comes, the other Mecha Zombies too.
function hands.scream(server, z, tx, ty)
  Horde.serverScream(server, z.x, z.y, Mecha.SCREAM_RADIUS, tx, ty)
  for _, o in ipairs(sv.list) do
    if o ~= z and dist2(o.x, o.y, z.x, z.y) <= Mecha.SCREAM_RADIUS ^ 2 then
      wake(o)
    end
  end
  server:broadcast(Protocol.encode("MZ_SCREAM", z.id, fmt(z.x), fmt(z.y), Mecha.SCREAM_RADIUS))
end

local MOVE = { plasma = 1, burst = 2, light = 3, flame = 4, talons = 5, scream = 6 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local parts = { server.tick }
  for _, z in ipairs(sv.list) do
    for _, v in ipairs({ z.id, fmt(z.x), fmt(z.y), ("%.2f"):format(z.facing), fmt(math.max(0, z.hp)), fmt(z.max),
      MOVE[z.move] or 0, z.awake and 1 or 0 }) do
      parts[#parts + 1] = v
    end
  end
  local msg = Protocol.encode("MZ_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Can it see a player, or has its mob woken?
local function stirred(server, z)
  if Horde.serverMobAwake(z.mob) then
    return true
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      if dist2(x, y, z.x, z.y) <= Mecha.SEES ^ 2 and Sight.clear(z.x, z.y, x, y) then
        return true
      end
    end
  end
  return false
end

function Mecha.serverStep(server, dt)
  if not sv then
    return
  end
  for _, z in ipairs(sv.list) do
    if not z.awake and not z.move and stirred(server, z) then
      wake(z)
    end
    for _, e in ipairs(Brain.think(z, server, dt, hands)) do
      if e[1] == "hit" then
        server:broadcast(Protocol.encode("MZ_HIT", e[2], fmt(e[3]), fmt(e[4])))
      end
    end
  end
  sync(server)
end

local function down(server, z, i, by, angle)
  table.remove(sv.list, i)
  local fell = { z.id, fmt(z.x), fmt(z.y), ("%.3f"):format(angle or z.facing) }
  sv.fallen[#sv.fallen + 1] = fell
  server:broadcast(Protocol.encode("MZ_DOWN", unpack(fell)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, z.x, z.y, Mecha.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy and random() < Mecha.PICKUP then
    pickups:serverDropEnemy(server, z.x, z.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = z.x, y = z.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches it (and wakes it). Returns true when it hit.
function Mecha.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  for i, z in ipairs(sv.list) do
    if dist2(x, y, z.x, z.y) <= (Mecha.RADIUS + (radius or 0)) ^ 2 then
      wake(z)
      z.hp = z.hp - (damage or 20)
      if z.hp <= 0 then
        down(server, z, i, by, angle)
      end
      return true
    end
  end
  return false
end

--- Every one still up, for the audit (tools/audit).
function Mecha.serverEnemies(_server, add)
  for _, z in ipairs(sv and sv.list or {}) do
    add({ id = z, kind = "eternal-mood/mecha-zombie", x = z.x, y = z.y, hp = z.hp, radius = Mecha.RADIUS })
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Mecha.wikiEnemies(add)
  local plasma, flame = guns()
  add({
    kind = "eternal-mood/mecha-zombie",
    name = "Mecha Zombie",
    quests = { "eternal-mood", "eternal-mood-earth", "eternal-mood-foundry" },
    where = "Fobos Base, Heck on Earth and the Foundry, walking a loop round each Intern mob",
    about = "A zombie the UAC rebuilt: a plasma cannon for a right arm, a flamethrower and talons on the left, a red "
      .. "optic where an eye was. It guards the Interns while they eat, and screams the horde down on you.",
    stats = {
      { "Health", Mecha.HEALTH },
      { "Speed", ("%g px/s fighting, %g on its loop"):format(Mecha.WALK, Mecha.PATROL) },
      { "Sight", ("%g px, no wall in between; awake, it hunts the nearest player within %g px"):format(Mecha.SEES,
        Mecha.HUNTS) },
    },
    weapons = {
      { "Plasma cannon", ("past %g px: the cannon glows for %g s, then %g bolts %g s apart, every %g to %g s; each "
        .. "%g fire damage and sets you alight (%g s at %g a second), flying about %g px"):format(Mecha.PLASMA_FROM,
        Mecha.PLASMA_WINDUP, Mecha.BURST, Mecha.PLASMA_GAP, Mecha.PLASMA_EVERY[1], Mecha.PLASMA_EVERY[2],
        plasma.damage, plasma.ignite.seconds, plasma.ignite.dps, math.floor(plasma.speed * plasma.ttl + 0.5)) },
      { "Flamethrower", ("at mid range: the pilot light flares for %g s, then %g s of fire, %g fire damage a lick, "
        .. "%g licks a second, reaching about %g px and setting you alight (%g s at %g a second); then %g s off")
        :format(Mecha.FLAME_WINDUP, Mecha.FLAME_FOR, flame.damage, math.floor(1 / flame.cooldown + 0.5),
        math.floor(flame.speed * flame.ttl + 0.5), flame.ignite.seconds, flame.ignite.dps, Mecha.FLAME_EVERY) },
      { "Talons", ("within %g px: claws up for %g s, then %g melee damage, one every %g s"):format(Mecha.TALON_REACH,
        Mecha.TALON_WINDUP, Mecha.TALON_DAMAGE, Mecha.TALON_EVERY) },
    },
    abilities = {
      ("Wakes when it sees you, you shoot it, or its mob wakes. Waking, it throws its head back for %g s and "
        .. "screams: every mob, every one of the possessed and every other Mecha Zombie within %g px comes."):format(
        Mecha.SCREAM_WINDUP, Mecha.SCREAM_RADIUS),
      ("Screams again every %g s while it can still see somebody."):format(Mecha.SCREAM_EVERY),
      ("Ranged fodder: it holds %g to %g px from you, side-stepping, rather than charging in."):format(Mecha.KEEP[1],
        Mecha.KEEP[2]),
    },
    tips = {
      "Kill it before it sees you, or the whole room comes when it screams.",
      "Its plasma bolts are slow: side-step them, and keep out of its flame's reach between bursts.",
      "A freeze holds it stiff.",
    },
    drops = ("%g koins, and %g%% of the time a pickup"):format(Mecha.DROPS, Mecha.PICKUP * 100),
  })
end

function Mecha.serverFreezeArea(x, y, radius, seconds)
  for _, z in ipairs(sv and sv.list or {}) do
    if dist2(x, y, z.x, z.y) <= radius * radius then
      z.frozen = math.max(z.frozen, seconds)
    end
  end
end

function Mecha.serverPlayerJoined(server, player)
  if sv and not player.bot then
    for _, fell in ipairs(sv.fallen) do
      server:send(player, Protocol.encode("MZ_DOWN", unpack(fell)), true)
    end
  end
end

--- For tests.
function Mecha.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, max, move, moveAt, awake, stride }
local bodies = {} -- { x, y, angle }
local waves = {} -- { x, y, r, t } screams going out
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local WAVE_FOR = 1.1 -- seconds a scream's sound wave takes to go out

function Mecha.load()
  local function make(seconds, volume, build)
    return Onscreen.sound(seconds, volume, build, 300, 2600)
  end
  bank.scream = make(1.3, 0.9, function(buf) -- a shriek through a broken speaker
    buf:sweep(0, 1.2, 900, 1400, { wave = "saw", amp = 0.4, attack = 0.05, decay = 1, vibRate = 23, vibDepth = 60 })
    buf:sweep(0.05, 1.1, 450, 700, { wave = "square", amp = 0.25, attack = 0.1, decay = 0.9, vibRate = 17,
      vibDepth = 30 })
    buf:noiseBurst(0, 1.2, { amp = 0.3, decay = 0.9 })
    buf:drive(3)
    buf:highpass(300)
  end)
  bank.charge = make(0.45, 0.6, function(buf) -- the cannon coming up
    buf:sweep(0, 0.42, 200, 1600, { wave = "sine", amp = 0.35, attack = 0.02, decay = 0.4 })
    buf:noiseBurst(0, 0.4, { amp = 0.1, decay = 0.35 })
  end)
  bank.pilot = make(0.35, 0.5, function(buf) -- the pilot light catching
    buf:noiseBurst(0, 0.3, { amp = 0.5, decay = 0.25 })
    buf:lowpass(1400)
  end)
  bank.talons = make(0.35, 0.8, function(buf)
    buf:noiseBurst(0, 0.22, { amp = 0.8, decay = 0.06 })
    buf:tone(0, 0.2, 2600, { wave = "square", amp = 0.08, decay = 0.15, sustain = 0 })
    buf:highpass(900)
  end)
  bank.fall = make(0.7, 0.8, function(buf)
    buf:kick(0, 0.9)
    buf:noiseBurst(0, 0.4, { amp = 0.5, decay = 0.2 })
    buf:sweep(0.05, 0.5, 400, 60, { wave = "saw", amp = 0.2, decay = 0.4 }) -- powering down
    buf:lowpass(2500)
  end)
end

local function play(name, x, y)
  Onscreen.play(bank, name, x, y)
end

function Mecha.clear()
  shown, bodies, waves, lastTick = {}, {}, {}, 0
end

function Mecha.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > 1.5 then
    shown = {}
  end
  Onscreen.ease(shown, dt)
  for i = #waves, 1, -1 do
    waves[i].t = waves[i].t + dt
    if waves[i].t > WAVE_FOR then
      table.remove(waves, i)
    end
  end
end

function Mecha.drawBelowCars()
  for _, b in ipairs(bodies) do
    Look.drawBody(b, clock)
  end
end

function Mecha.drawAboveCars()
  for _, m in pairs(shown) do
    Look.draw(m, clock)
    if m.hp and m.max and m.hp < m.max then -- its health, once hurt
      local w, x, y = 28, m.dx, m.dy - Mecha.RADIUS - 12
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", x - w / 2 - 1, y, w + 2, 5)
      love.graphics.setColor(0.95, 0.15, 0.12)
      love.graphics.rectangle("fill", x - w / 2, y + 1, w * math.max(0, m.hp / m.max), 3)
    end
  end
  for _, w in ipairs(waves) do -- the scream going out: rings, a ripple behind each
    local f = w.t / WAVE_FOR
    for k = 0, 2 do
      local g = f - k * 0.12
      if g > 0 then
        love.graphics.setColor(1, 0.35, 0.25, 0.5 * (1 - g) * (1 - k * 0.3))
        love.graphics.setLineWidth(4 - k)
        love.graphics.circle("line", w.x, w.y, w.r * g, 48)
      end
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- Its optic in the dark; its cannon charging, its pilot light.
function Mecha.drawNightLights(glow)
  for _, m in pairs(shown) do
    local fx, fy = math.cos(m.facing or 0), math.sin(m.facing or 0)
    glow(m.dx + fx * 6, m.dy + fy * 6, 30, { 1, 0.2, 0.1 }, 0.6)
    local h = Mecha.HAND
    if m.move == 1 or m.move == 2 then -- the cannon, on its right
      glow(m.dx + fx * 18 - fy * h, m.dy + fy * 18 + fx * h, 60, { 0.5, 0.9, 1 }, 0.8)
    elseif m.move == 3 or m.move == 4 then -- the flamer, on its left
      glow(m.dx + fx * 18 + fy * h, m.dy + fy * 18 - fx * h, 70, { 1, 0.5, 0.15 }, 0.8)
    end
  end
end

Mecha.clientMessages = {
  MZ_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        seen[id] = true
        local m = shown[id]
        if not m then
          m = { dx = x, dy = y, stride = 0 }
          shown[id] = m
        end
        m.x, m.y = x, y
        m.facing = tonumber(args[i + 3]) or m.facing or 0
        m.hp, m.max = tonumber(args[i + 4]) or m.hp, tonumber(args[i + 5]) or m.max
        local move = tonumber(args[i + 6]) or 0
        if move ~= m.move then
          m.moveAt = clock
          if move == 1 then
            play("charge", m.dx, m.dy)
          elseif move == 3 then
            play("pilot", m.dx, m.dy)
          end
        end
        m.move = move
        m.awake = args[i + 7] == "1"
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  MZ_SCREAM = function(_client, args)
    local x, y, r = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and r then
      waves[#waves + 1] = { x = x, y = y, r = r, t = 0 }
      play("scream", x, y)
    end
  end,
  MZ_HIT = function(_client, args)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if x and y then
      play("talons", x, y)
    end
  end,
  MZ_DOWN = function(_client, args)
    local id, x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if x and y then
      bodies[#bodies + 1] = { x = x, y = y, angle = angle }
      play("fall", x, y)
    end
    if id then
      shown[id] = nil
    end
  end,
}

Brain = require("src.features.eternal-mood.mecha_zombie_brain")

return Mecha
