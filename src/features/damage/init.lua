-- Damage: what kind of hit a hit is. Every bit of damage in the game says
-- its type (docs/damage-types.md): the weapons API takes it as the last
-- argument (`serverDamage`, `damageCar`), guns declare it (`damageType`,
-- `blast.type`), and every hook that hears about damage passes it on
-- (`serverAbsorbDamage`, `serverPlayerDamaged`, `serverShotAt`,
-- `serverBlast`, `serverWallHit`, and `cause` on `serverKill`). Clients get
-- it on WPN_KILL and WPN_WRECK and word the kill feed with it.
--
-- A new type is a new entry in `Damage.types`.
--
-- What a type does to a player on foot besides the damage (cars take every
-- type the same, for now):
--
--   bullet     nothing more
--   fire       nothing by itself; a fire that means it sets you alight
--              (`Damage:ignite`): you burn on after you are out of it
--   melee      you bleed for a while
--   shock      stunned: held still for a moment
--   impact     knocked back a little, and down: held still for a moment
--   explosive  blown back from the blast, further the harder it hit, and
--              dazed: your screen swims
--
-- Burning and bleeding hurt a little every quarter second until they run
-- out. Another dose while one is on tops its time back up at the stronger
-- rate; it never stacks. A dodge puts a fire out (the on-foot feature
-- raises `serverDodged`), a medkit stops the bleeding (buildings calls
-- `serverStopBleeding`). Getting into a car, dying or leaving ends them all.
-- Stunned or down, you are held (the `serverHeld` / `held` conventions: no
-- walking, shooting or dodging). Everyone sees every status on everyone.
--
-- Resistances: what a player wears can stop a share of a type (a vest's or
-- a piece of clothing's `resist = { fire = 0.4 }`). Every feature that
-- dresses a player answers `serverResist(share, server, player, type)` on
-- the host and `resist(share, client, id, type)` on a client, multiplying
-- the share that gets through by (1 - its resistance); so two pieces that
-- each stop 30% stop 51% together. No more than `maxResist` of any type is
-- ever stopped. The host takes the resisted share off every hit to a body
-- here, in `serverAbsorbDamage`, before the vest soaks up the rest (this
-- feature goes before armor), and a stun, a knockdown, a daze or a knock
-- is that much shorter too. A burn's or a bleed's bites are hits like any
-- other, so a fire jacket makes a burn hurt less.
--
-- Messages
--   server -> all  DMG_FX <id> <status> <seconds>   a status is on for this
--                                                   long now (0: it is over)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")

local Damage = {
  name = "damage",
  priority = 90, -- before armor (100): resistances come off a hit before the vest soaks up the rest
}

--- Anything that hurts without saying what it is.
Damage.DEFAULT = "bullet"

--- type -> { name, color, killed = "<killer> killed <victim>" verb,
--- died = "<victim> died" words when nobody did it }
Damage.types = {
  bullet = { name = "Bullet", color = { 1, 0.85, 0.3 }, killed = "wasted", died = "was wasted" },
  explosive = { name = "Explosive", color = { 1, 0.5, 0.15 }, killed = "blew up", died = "was blown up" },
  fire = { name = "Fire", color = { 1, 0.3, 0.1 }, killed = "burned", died = "burned to a crisp" },
  impact = { name = "Impact", color = { 0.75, 0.75, 0.8 }, killed = "flattened", died = "was flattened" },
  shock = { name = "Shock", color = { 0.5, 0.8, 1 }, killed = "fried", died = "was fried" },
  melee = { name = "Melee", color = { 0.9, 0.4, 0.4 }, killed = "beat down", died = "was beaten down" },
}

-- Tuning ------------------------------------------------------------------
Damage.burnTime = 3 -- seconds someone burns when a fire doesn't say
Damage.burnDps = 8 -- fire damage a second while they do, likewise
Damage.bleedTime = 4 -- seconds a melee hit leaves you bleeding
Damage.bleedDps = 3 -- melee damage a second while you do
Damage.stunTime = 1 -- seconds a shock holds you still
Damage.downTime = 0.6 -- seconds an impact puts you on the ground
Damage.impactShove = 36 -- px an impact knocks you back
Damage.blastShovePerDamage = 1.5 -- px an explosive hit throws you per point of damage...
Damage.blastShoveMax = 110 -- ...up to this
Damage.blastShoveMin = 10 -- damage a blast must do to throw you at all
Damage.shoveTime = 0.25 -- seconds a knock takes; you are held for it
Damage.dazeTime = 2 -- seconds an explosive hit leaves your screen swimming
Damage.maxResist = 0.8 -- the most of any type anything worn, alone or together, can stop

local TICK = 0.25 -- seconds between bites of a burn or a bleed

--- The statuses there are, and the type the ones that hurt deal.
local HURTS = { burn = "fire", bleed = "melee" }
local STATUSES = { burn = true, bleed = true, stun = true, down = true, daze = true }

--- The entry for type `dtype`, the default's for nil or anything unknown.
function Damage.of(dtype)
  return Damage.types[dtype] or Damage.types[Damage.DEFAULT]
end

--- `dtype` when it is a known type, else the default: what goes on the wire.
function Damage.key(dtype)
  return Damage.types[dtype] and dtype or Damage.DEFAULT
end

--- The types in the order everything lists them (cards, the inventory).
Damage.order = { "bullet", "explosive", "fire", "impact", "shock", "melee" }

--- One piece's resistance `r` as it counts: a number from 0 to maxResist.
function Damage.clampResist(r)
  return math.max(0, math.min(Damage.maxResist, tonumber(r) or 0))
end

--- The share of a hit that gets through, from what `reduce` answered,
--- never below what `maxResist` allows.
local function through(share)
  return math.max(1 - Damage.maxResist, math.min(1, share))
end

--- The share of a `dtype` hit that gets through to player `id` on this
--- screen (1: nothing stopped), from what they wear.
function Damage:share(client, id, dtype)
  return through(Features.reduce("resist", 1, client, id, dtype))
end

-- Client --------------------------------------------------------------------

Damage.fx = {} -- player id -> { [status] = client time it ends }
Damage.drips = {} -- { x, y, r, t }: blood a bleeding body left on the ground
local clock = 0
local dripIn = 0

local DRIP_EVERY = 0.12 -- seconds between drips a bleeding body leaves
local DRIP_LIFE = 3 -- seconds a drip stays on the ground
local DRIPS_MAX = 300

function Damage:exitGame()
  self.fx = {}
  self.drips = {}
end

--- Is `status` on for player `id` on this screen?
function Damage:has(id, status)
  local f = self.fx[id]
  return f ~= nil and f[status] ~= nil and f[status] > clock
end

function Damage:update(dt, client)
  clock = clock + dt
  -- Every bleeding body on foot leaves a drip every so often; old ones dry up.
  dripIn = dripIn - dt
  if dripIn <= 0 then
    dripIn = DRIP_EVERY
    for id in pairs(self.fx) do
      local x, y, onFoot = client:pose(id)
      if x and onFoot and self:has(id, "bleed") and #self.drips < DRIPS_MAX then
        local a = love.math.random() * 2 * math.pi
        local d = love.math.random() * 7
        self.drips[#self.drips + 1] = {
          x = x + math.cos(a) * d, y = y + math.sin(a) * d, r = 1.8 + love.math.random() * 2, t = DRIP_LIFE,
        }
      end
    end
  end
  for i = #self.drips, 1, -1 do
    local drip = self.drips[i]
    drip.t = drip.t - dt
    if drip.t <= 0 then
      table.remove(self.drips, i)
    end
  end
  for id, f in pairs(self.fx) do
    for status, untilT in pairs(f) do
      if untilT <= clock then
        f[status] = nil
      end
    end
    if next(f) == nil then
      self.fx[id] = nil
    end
  end
end

--- Flames licking up off a body: a glow on the ground, then a few tongues
--- flickering at their own pace, hot at the heart.
local function drawFlames(x, y, seed)
  love.graphics.setColor(1, 0.45, 0.1, 0.22 + 0.08 * math.sin(clock * 11 + seed))
  love.graphics.circle("fill", x, y, 22)
  for i = 1, 6 do
    local phase = clock * (1.6 + i * 0.25) + seed * 1.7 + i * 0.37
    local rise = (phase % 1) -- each tongue climbs and fades, then starts again
    local ox = math.sin(phase * 6.3 + i) * 4 + (i - 3.5) * 3.5
    local oy = 4 - rise * 26
    local r = 8 * (1 - rise * 0.6)
    love.graphics.setColor(1, 0.35 + 0.3 * (1 - rise), 0.05, 0.75 * (1 - rise))
    love.graphics.circle("fill", x + ox, y + oy, r)
    love.graphics.setColor(1, 0.9, 0.4, 0.8 * (1 - rise))
    love.graphics.circle("fill", x + ox, y + oy + 1, r * 0.45)
  end
end

--- Blood: drops falling off a body, each its own way (the drips it leaves
--- on the ground are drawn under the cars).
local function drawBlood(x, y, seed)
  for i = 1, 6 do
    local phase = clock * 1.8 + seed * 0.9 + i * 0.29
    local fall = phase % 1
    local a = seed * 2.3 + i * 1.7
    local ox, oy = math.cos(a) * 9, math.sin(a) * 5
    love.graphics.setColor(0.85, 0.05, 0.05, 0.95 * (1 - fall * 0.7))
    love.graphics.circle("fill", x + ox, y + oy + fall * 16, 3.2 - fall)
  end
end

--- Sparks crackling round a body: a few jagged blue arcs, a new shape
--- every flicker, over a pale glow.
local function drawSparks(x, y, seed)
  love.graphics.setColor(0.6, 0.85, 1, 0.25)
  love.graphics.circle("fill", x, y, 16)
  local flicker = math.floor(clock * 18)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(0.55, 0.85, 1, 0.95)
  for i = 1, 3 do
    local a = (flicker * 2.39 + i * 2.1 + seed) % (2 * math.pi)
    local px, py = x + math.cos(a) * 6, y + math.sin(a) * 6
    local pts = { px, py }
    for k = 1, 3 do
      local j = ((flicker * 7 + i * 13 + k * 5) % 11) / 11 - 0.5
      px = px + math.cos(a + j) * 5
      py = py + math.sin(a + j) * 5
      pts[#pts + 1], pts[#pts + 2] = px, py
    end
    love.graphics.line(pts)
  end
  love.graphics.setLineWidth(1)
end

--- Knocked down: stars going round over the head.
local function drawStars(x, y, seed)
  for i = 1, 3 do
    local a = clock * 5 + seed + i * (2 * math.pi / 3)
    local sx, sy = x + math.cos(a) * 13, y - 16 + math.sin(a) * 5
    love.graphics.setColor(1, 0.9, 0.3, 0.95)
    love.graphics.circle("fill", sx, sy, 3.5)
    love.graphics.setColor(1, 1, 0.85, 0.95)
    love.graphics.circle("fill", sx, sy, 1.5)
  end
end

--- The drips on the ground, fading as they dry.
function Damage:drawBelowCars()
  for _, drip in ipairs(self.drips) do
    love.graphics.setColor(0.7, 0.02, 0.02, 0.85 * math.min(1, drip.t / DRIP_LIFE * 2))
    love.graphics.circle("fill", drip.x, drip.y, drip.r)
  end
  love.graphics.setColor(1, 1, 1)
end

function Damage:drawAboveCars(client)
  for id in pairs(self.fx) do
    local x, y, onFoot = client:pose(id)
    if x and onFoot and not (id ~= client.myId and Features.any("hidden", client, id)) then
      if self:has(id, "bleed") then
        drawBlood(x, y, id)
      end
      if self:has(id, "burn") then
        drawFlames(x, y, id)
      end
      if self:has(id, "stun") then
        drawSparks(x, y, id)
      end
      if self:has(id, "down") then
        drawStars(x, y, id)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Damage:drawHUD(client)
  local me = client.myId
  local says = {}
  if self:has(me, "burn") then
    says[#says + 1] = "ON FIRE: dodge to put it out"
  end
  if self:has(me, "bleed") then
    local key = Controls.bindings("use-medkit")[1]
    says[#says + 1] = "BLEEDING: a medkit" .. (key and " (" .. Controls.name(key) .. ")" or "") .. " stops it"
  end
  if self:has(me, "stun") then
    says[#says + 1] = "STUNNED"
  elseif self:has(me, "down") then
    says[#says + 1] = "KNOCKED DOWN"
  end
  if #says > 0 then
    love.graphics.setFont(UI.fonts.small)
    local pulse = 0.65 + 0.35 * math.abs(math.sin(clock * 6))
    love.graphics.setColor(1, 0.5, 0.15, pulse)
    love.graphics.print(table.concat(says, "   "), 10, 118)
    love.graphics.setColor(1, 1, 1)
  end
end

--- The `held` convention: stunned or down, I don't walk ahead of the host.
function Damage:held(_client, id)
  return self:has(id, "stun") or self:has(id, "down")
end

--- The `worldBlur` convention: a blast I took leaves the world swimming,
--- clearing as the daze wears off.
function Damage:worldBlur(client)
  local f = self.fx[client.myId]
  local untilT = f and f.daze
  if not untilT or untilT <= clock then
    return 0
  end
  return math.min(1, (untilT - clock) / self.dazeTime * 1.5)
end

Damage.clientMessages = {
  DMG_FX = function(_client, args)
    local id, status, seconds = tonumber(args[1]), args[2], tonumber(args[3])
    if not (id and STATUSES[status] and seconds) then
      return
    end
    local f = Damage.fx[id] or {}
    Damage.fx[id] = f
    f[status] = seconds > 0 and clock + seconds or nil
  end,
}

-- Server --------------------------------------------------------------------

-- { time, fx = { [player id] = { [status] = { untilT, dps, by, biteIn } } },
--   ticking = true while a burn or a bleed is biting }
local sv = nil

function Damage:serverStart()
  sv = { time = 0, fx = {} }
end

--- The share of a `dtype` hit that gets through to `player` on the host.
function Damage:serverShare(server, player, dtype)
  return through(Features.reduce("serverResist", 1, server, player, Damage.key(dtype)))
end

--- The `serverAbsorbDamage` convention, first in line: what `victim` wears
--- stops its share of the hit; the rest goes on (to the vest, then them).
function Damage:serverAbsorbDamage(amount, server, victim, dtype)
  if amount <= 0 then
    return amount
  end
  return amount * self:serverShare(server, victim, dtype)
end

local function tell(server, id, status, seconds)
  server:broadcast(Protocol.encode("DMG_FX", id, status, ("%.2f"):format(math.max(0, seconds))))
end

--- Can `victim` take a status: in the game, alive, on foot?
local function takes(victim)
  return sv ~= nil and victim ~= nil and Features.present(victim) and not victim.vehicle
end

--- Put status `status` on `victim` for `seconds`, or top up the one on:
--- whichever lasts longer, at whichever `dps` is higher, the kill (for a
--- status that hurts) going to player id `by`. Returns true if it is on.
function Damage:serverAfflict(server, victim, status, seconds, dps, by)
  if not (STATUSES[status] and takes(victim)) then
    return false
  end
  local mine = sv.fx[victim.id] or {}
  sv.fx[victim.id] = mine
  local untilT = sv.time + seconds
  local s = mine[status]
  if s then
    if untilT <= s.untilT and (dps or 0) <= (s.dps or 0) then
      return true -- nothing new to say
    end
    s.untilT = math.max(s.untilT, untilT)
    s.dps = math.max(s.dps or 0, dps or 0)
    s.by = by or s.by
  else
    s = { untilT = untilT, dps = dps, by = by, biteIn = TICK }
    mine[status] = s
  end
  tell(server, victim.id, status, s.untilT - sv.time)
  return true
end

--- End status `status` on player `id`, if it is on. Returns true if it was.
function Damage:serverCure(server, id, status)
  local mine = sv and sv.fx[id]
  if mine and mine[status] then
    mine[status] = nil
    tell(server, id, status, 0)
    return true
  end
  return false
end

--- Is `status` on for player `id` on the host?
function Damage:serverHas(id, status)
  local mine = sv and sv.fx[id]
  return mine ~= nil and mine[status] ~= nil
end

--- Set `victim` alight: they burn for `seconds` (Damage.burnTime when nil)
--- at `dps` fire damage a second (Damage.burnDps), the kill going to
--- player id `by` (nil for nobody). Only a player on foot catches fire.
--- Returns true if they are burning now.
function Damage:ignite(server, victim, seconds, dps, by)
  return self:serverAfflict(server, victim, "burn", seconds or self.burnTime, dps or self.burnDps, by)
end

--- Put player `id` out, if they are burning.
function Damage:extinguish(server, id)
  return self:serverCure(server, id, "burn")
end

--- Is player `id` on fire on the host?
function Damage:serverBurning(id)
  return self:serverHas(id, "burn")
end

--- Stop player `id` bleeding (a medkit). Returns true if they were.
function Damage:serverStopBleeding(server, id)
  return self:serverCure(server, id, "bleed")
end

--- Knock `victim` `distance` px along `angle` over Damage.shoveTime (on-foot
--- moves the body), held still while it carries them.
local function shove(server, victim, angle, distance)
  local onFoot = Features.byName["on-foot"]
  if not (angle and distance > 0 and onFoot and onFoot.serverShove) then
    return
  end
  onFoot:serverShove(server, victim, math.cos(angle), math.sin(angle), distance, Damage.shoveTime)
  Damage:serverAfflict(server, victim, "down", Damage.shoveTime)
end

--- What a hit of type `dtype` does to a player on foot besides the damage
--- (the `serverPlayerDamaged` event, after the hit is taken): see the top
--- of this file. `angle` is the way the blow travelled, for a knock. What
--- they wear against the type makes a stun, a knockdown, a daze or a knock
--- that much shorter (a bleed's bites are resisted as they land). The
--- bites of a burn or a bleed don't set anything off.
function Damage:serverPlayerDamaged(server, victim, attacker, amount, dtype, angle)
  if not takes(victim) or sv.ticking then
    return
  end
  local weapons = Features.byName.weapons
  local hp = weapons and weapons.serverHealth and weapons:serverHealth(victim)
  if hp and hp <= 0 then
    return -- that one killed them
  end
  local share = self:serverShare(server, victim, dtype)
  if dtype == "melee" then
    self:serverAfflict(server, victim, "bleed", self.bleedTime, self.bleedDps, attacker and attacker.id)
  elseif dtype == "shock" then
    self:serverAfflict(server, victim, "stun", self.stunTime * share)
  elseif dtype == "impact" then
    shove(server, victim, angle, self.impactShove * share)
    self:serverAfflict(server, victim, "down", self.downTime * share)
  elseif dtype == "explosive" and amount >= self.blastShoveMin then
    shove(server, victim, angle, math.min(self.blastShoveMax, amount * self.blastShovePerDamage) * share)
    self:serverAfflict(server, victim, "daze", self.dazeTime * share)
  end
end

--- The `serverHeld` convention: stunned or down, they stay where they are
--- (a knock still carries them: on-foot moves a shove whatever holds them).
function Damage:serverHeld(_server, player)
  return self:serverHas(player.id, "stun") or self:serverHas(player.id, "down")
end

function Damage:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local weapons = Features.byName.weapons
  for id, mine in pairs(sv.fx) do
    local p = server.players[id]
    local gone = not (p and Features.present(p)) or p.vehicle -- died, left, or got in a car
    for status, s in pairs(mine) do
      if gone or sv.time >= s.untilT then
        mine[status] = nil
        tell(server, id, status, 0)
      elseif HURTS[status] then
        s.biteIn = s.biteIn - dt
        if s.biteIn <= 0 and weapons and weapons.serverDamage then
          s.biteIn = s.biteIn + TICK
          -- Hurting yourself (your own fire) is nobody's kill.
          local by = s.by ~= id and server.players[s.by] or nil
          sv.ticking = true
          weapons:serverDamage(server, p, by, s.dps * TICK, nil, HURTS[status])
          sv.ticking = false
        end
      end
    end
    if next(mine) == nil then
      sv.fx[id] = nil
    end
  end
end

--- Stop, drop and roll: a dodge puts the flames out.
function Damage:serverDodged(server, player)
  self:extinguish(server, player.id)
end

function Damage:serverPlayerJoined(server, player)
  if not sv or player.bot then
    return
  end
  for id, mine in pairs(sv.fx) do
    for status, s in pairs(mine) do
      server:send(player, Protocol.encode("DMG_FX", id, status, ("%.2f"):format(s.untilT - sv.time)))
    end
  end
end

function Damage:serverPlayerLeft(_server, player)
  if sv then
    sv.fx[player.id] = nil -- nobody left to tell about them
  end
end

--- For tests.
function Damage.server()
  return sv
end

return Damage
