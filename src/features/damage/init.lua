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
--   shock      a hard jolt (`stunMin` or more in one hit) stuns you: held
--              still for a moment; a lighter one does nothing by itself.
--              Something that means it can zap you (`Damage:electrify`):
--              the shock runs on through you after the hit, the way a fire
--              burns on, or stun you outright (`Damage:stun`)
--   impact     knocked back a little, and down: held still for a moment
--   explosive  blown back from the blast, further the harder it hit, and
--              dazed: your screen swims
--   poison     you are poisoned for a while: it hurts on after the hit,
--              until it runs out or a medkit cures it
--
-- Burning, being zapped, bleeding and being poisoned hurt a little every
-- quarter second until they run out. Another dose while one is on tops its
-- time back up at the stronger rate; it never stacks. A dodge puts a fire
-- out and shakes off a zap (the on-foot feature raises `serverDodged`), a
-- medkit stops the bleeding and cures the poison (buildings calls
-- `serverTreat`). Getting into a car, dying or leaving ends them all.
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
-- What it looks like is effects.lua's: every status on a body, a number
-- in the type's colour floating up off every hit (weapons raises
-- `clientHit`; `Damage.numbers` turns them off), and what a body leaves by
-- what killed it (`Damage:deathAt`, from on-foot's OF_GIB): ash for fire
-- and shock, a scorch mark and pieces every way for a blast, a splat.
--
-- Messages
--   server -> all  DMG_FX <id> <status> <seconds>   a status is on for this
--                                                   long now (0: it is over)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Effects = require("src.features.damage.effects")

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
  poison = { name = "Poison", color = { 0.55, 0.9, 0.3 }, killed = "poisoned", died = "was poisoned" },
}

-- Tuning ------------------------------------------------------------------
Damage.burnTime = 3 -- seconds someone burns when a fire doesn't say
Damage.burnDps = 8 -- fire damage a second while they do, likewise
Damage.bleedTime = 4 -- seconds a melee hit leaves you bleeding
Damage.bleedDps = 3 -- melee damage a second while you do
Damage.poisonTime = 6 -- seconds a poison hit leaves you poisoned
Damage.poisonDps = 4 -- poison damage a second while you are
Damage.stunTime = 1 -- seconds a shock holds you still
Damage.stunMin = 20 -- damage a single shock hit must do to stun you by itself
Damage.zapTime = 3 -- seconds a zap runs on through you when it doesn't say
Damage.zapDps = 8 -- shock damage a second while it does, likewise
Damage.downTime = 0.6 -- seconds an impact puts you on the ground
Damage.impactShove = 36 -- px an impact knocks you back
Damage.blastShovePerDamage = 1.5 -- px an explosive hit throws you per point of damage...
Damage.blastShoveMax = 110 -- ...up to this
Damage.blastShoveMin = 10 -- damage a blast must do to throw you at all
Damage.shoveTime = 0.25 -- seconds a knock takes; you are held for it
Damage.dazeTime = 2 -- seconds an explosive hit leaves your screen swimming
Damage.numbers = true -- damage numbers float up off every hit
Damage.maxResist = 0.8 -- the most of any type anything worn, alone or together, can stop

local TICK = 0.25 -- seconds between bites of a burn, a zap or a bleed

--- The statuses there are, and the type the ones that hurt deal.
local HURTS = { burn = "fire", zap = "shock", bleed = "melee", poison = "poison" }
local STATUSES = { burn = true, zap = true, bleed = true, poison = true, stun = true, down = true, daze = true }

--- The entry for type `dtype`, the default's for nil or anything unknown.
function Damage.of(dtype)
  return Damage.types[dtype] or Damage.types[Damage.DEFAULT]
end

--- `dtype` when it is a known type, else the default: what goes on the wire.
function Damage.key(dtype)
  return Damage.types[dtype] and dtype or Damage.DEFAULT
end

--- The types in the order everything lists them (cards, the inventory).
Damage.order = { "bullet", "explosive", "fire", "impact", "shock", "melee", "poison" }

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
local clock = 0
local dripIn = 0

local DRIP_EVERY = 0.12 -- seconds between drips a bleeding body leaves

function Damage:exitGame()
  self.fx = {}
  Effects.clear()
end

--- A new map: what lay on the old one's ground goes with it.
function Damage:mapChanged()
  Effects.clear()
end

--- Is `status` on for player `id` on this screen?
function Damage:has(id, status)
  local f = self.fx[id]
  return f ~= nil and f[status] ~= nil and f[status] > clock
end

function Damage:update(dt, client)
  clock = clock + dt
  Effects.update(dt)
  -- Every bleeding body on foot leaves a drip every so often.
  dripIn = dripIn - dt
  if dripIn <= 0 then
    dripIn = DRIP_EVERY
    for id in pairs(self.fx) do
      local x, y, onFoot = client:pose(id)
      if x and onFoot and self:has(id, "bleed") then
        Effects.drip(x, y)
      end
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

--- The `clientHit` event (weapons raises it for every WPN_HIT and
--- WPN_CARHIT): `hit` is { x, y, amount, dtype, key }, `key` naming the
--- target so hits on it in quick succession add up into one number.
function Damage:clientHit(_client, hit)
  if self.numbers then
    Effects.number(hit.key, hit.x, hit.y, hit.amount, hit.dtype)
  end
end

--- Somebody died on foot at (x, y), `cause` the type that did it, `angle`
--- the way the blow travelled: what is left of them, by type. Burned or
--- fried leaves ash; a blast throws the pieces all round and scorches the
--- road; anything else splats (the pedestrians' gibs, if that feature is
--- around), a crash harder than a bullet.
function Damage:deathAt(x, y, angle, cause)
  angle = angle or 0
  if cause == "fire" or cause == "shock" then
    Effects.leave("ash", x, y, angle)
    return
  end
  if cause == "explosive" then
    Effects.leave("scorch", x, y, love.math.random() * math.pi)
  end
  if not Features.byName.pedestrians then
    return
  end
  local Gibs = require("src.features.pedestrians.gibs")
  Gibs.splat(x, y, angle)
  if cause == "explosive" or cause == "impact" then
    Gibs.splat(x, y, angle + math.pi) -- more of them, and every way
  end
  require("src.features.pedestrians.sounds").play("splat", x, y, 0.8 + love.math.random() * 0.2)
end

--- The colour a type is drawn in (numbers, hit rings, the kill feed).
function Damage.colorOf(dtype)
  return Damage.of(dtype).color
end

--- What lies on the ground: ash, scorch marks, drips of blood.
function Damage:drawBelowCars()
  Effects.drawGround()
end

function Damage:drawAboveCars(client, camera)
  for id in pairs(self.fx) do
    local x, y, onFoot = client:pose(id)
    if x and onFoot and not (id ~= client.myId and Features.any("hidden", client, id)) then
      if self:has(id, "bleed") then
        Effects.blood(x, y, id, clock)
      end
      if self:has(id, "poison") then
        Effects.bubbles(x, y, id, clock)
      end
      if self:has(id, "burn") then
        Effects.flames(x, y, id, clock)
      end
      if self:has(id, "stun") or self:has(id, "zap") then
        Effects.sparks(x, y, id, clock)
      end
      if self:has(id, "down") then
        Effects.stars(x, y, id, clock)
      end
    end
  end
  Effects.drawNumbers(Damage.colorOf, camera and camera.scale)
  love.graphics.setColor(1, 1, 1)
end

function Damage:drawHUD(client)
  local me = client.myId
  local says = {}
  if self:has(me, "burn") then
    says[#says + 1] = "ON FIRE: dodge to put it out"
  end
  if self:has(me, "zap") then
    says[#says + 1] = "ELECTRIFIED: dodge to shake it off"
  end
  local key = Controls.bindings("use-medkit")[1]
  local medkit = "a medkit" .. (key and " (" .. Controls.name(key) .. ")" or "")
  if self:has(me, "bleed") then
    says[#says + 1] = "BLEEDING: " .. medkit .. " stops it"
  end
  if self:has(me, "poison") then
    says[#says + 1] = "POISONED: " .. medkit .. " cures it"
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

--- Zap `victim`: the shock runs on through them for `seconds`
--- (Damage.zapTime when nil) at `dps` shock damage a second
--- (Damage.zapDps), the kill going to player id `by` (nil for nobody). Only
--- a player on foot is zapped. Returns true if they are.
function Damage:electrify(server, victim, seconds, dps, by)
  return self:serverAfflict(server, victim, "zap", seconds or self.zapTime, dps or self.zapDps, by)
end

--- Stun `victim` outright for `seconds`, less what they wear against shock.
function Damage:stun(server, victim, seconds)
  if not takes(victim) then
    return false
  end
  return self:serverAfflict(server, victim, "stun", seconds * self:serverShare(server, victim, "shock"))
end

--- Put player `id` out, if they are burning.
function Damage:extinguish(server, id)
  return self:serverCure(server, id, "burn")
end

--- Is player `id` on fire on the host?
function Damage:serverBurning(id)
  return self:serverHas(id, "burn")
end

--- Stop player `id` bleeding. Returns true if they were.
function Damage:serverStopBleeding(server, id)
  return self:serverCure(server, id, "bleed")
end

--- A medkit: stops player `id` bleeding and cures their poison. Returns
--- true if there was anything to stop.
function Damage:serverTreat(server, id)
  local bled = self:serverCure(server, id, "bleed")
  local poisoned = self:serverCure(server, id, "poison")
  return bled or poisoned
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
  elseif dtype == "poison" then
    self:serverAfflict(server, victim, "poison", self.poisonTime, self.poisonDps, attacker and attacker.id)
  elseif dtype == "shock" and amount >= self.stunMin then
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

--- Stop, drop and roll: a dodge puts the flames out and shakes off a zap.
function Damage:serverDodged(server, player)
  self:extinguish(server, player.id)
  self:serverCure(server, player.id, "zap")
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
