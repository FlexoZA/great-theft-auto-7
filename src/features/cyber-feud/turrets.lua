-- Halcyon's sentry turrets (docs/cyber-feud.md, "Halcyon"): grey tripods
-- with a magenta lens, bolted down in Halcyon Tower's labs and on its
-- security floor (the map's `turrets`), and dropped by Saye on the Roof
-- (`serverJoin`). troops.lua starts, steps and stops
-- them with the rest of Halcyon and passes rounds on to them; init.lua
-- passes on the breach and the prompt. Their heads are turret_brain.lua.
--
-- A turret sweeps its arc; whoever it sees gets its laser on them for a
-- moment, then bursts of rounds down it (Halcyon's). 80 health; only
-- players' rounds reach it (the factions' pass by). Get round behind it,
-- out of its arc, and it is a breach target: on foot, hold the action key
-- (F) next to it for `breachTime` seconds and it is yours for `breachFor`,
-- its lens VEX's green, shooting Halcyon and the Static (as you: the kills
-- are yours). Let go and what you had done drains away. An EMP (the
-- sparkers', `serverEmp`) knocks it out for `empTime`.
--
-- Messages
--   server -> all     TUR_STATE <tick> (<id> <x> <y> <aim> <hp> <state>)...
--                     (unreliable, 15 Hz; state 0 sweeping, 1 laser on somebody, 2 firing, 3 breached, 4 knocked out)
--   client -> server  TUR_WORK  <id>              (I am holding the key at it; every WORK_EVERY)
--   server -> all     TUR_PROG  <id> <progress>   (how far a breach is: 0..1)
--   server -> all     TUR_DOWN  <id> <x> <y>      one was destroyed

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Sight = require("src.features.d-day.sight")
local Brain = require("src.features.cyber-feud.turret_brain")

local UZI_TTL = 1.2 -- its uzi's rounds fly the full way (weapons' default): the player's uzi is close-range only

local Turrets = {}

-- Tuning ------------------------------------------------------------------
Turrets.health = 80
Turrets.damage = 8 -- a round
Turrets.breachTime = 2.5 -- seconds of holding the key next to one
Turrets.breachFor = 15 -- seconds it fights for you
Turrets.drain = 0.5 -- of the whole a second a breach loses while nobody works it
Turrets.reach = 60 -- px from one that counts as next to it
Turrets.empTime = 5
Turrets.drops = 5
Turrets.firstId = 17001

local WORK_EVERY = 0.2
local WORK_GRACE = 0.45
local SLACK = 40
local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local STALE = 1
local SMOOTHING = 14
local HURT = 0.18
local STATE_CODE = { sweep = 0, warn = 1, fire = 2 }

local MAGENTA = { 1.00, 0.24, 0.78 }
local GREEN = { 0.43, 1.00, 0.60 }
local GREY = { 0.44, 0.46, 0.50 }
local DARK = { 0.16, 0.17, 0.19 }

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, work = { [id] = { progress, lastWork, sent } }, syncIn, emptySends }
local guns = {}
local now = 0

--- One round from `t` along `aim`: Halcyon's, or once breached the breacher's.
local function fire(server, t, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  local tint = t.breachedBy and "6dff9a" or "ff3ec8"
  if not guns[tint] then
    local base = Tiers.apply(Guns.uzi, Tiers.DEFAULT)
    guns[tint] = setmetatable({ damage = Turrets.damage, tint = tint, spread = 0.04, ttl = UZI_TTL },
      { __index = base })
  end
  local x, y = t.x + math.cos(aim) * 22, t.y + math.sin(aim) * 22
  if t.breachedBy then
    weapons:serverFireFrom(server, t.breachedBy, x, y, aim, guns[tint])
  else
    weapons:serverFireFrom(server, 0, x, y, aim, guns[tint], "halcyon")
  end
end

--- Turrets on `map`'s `turrets` posts, calm while `calm`; `rivals()` the
--- lists a breached one goes for. Returns the brain, or nil on a map without them.
function Turrets.serverStart(server, map, calm, rivals)
  Turrets.serverStop(server)
  if not (map.turrets or map.bosses) then
    return nil -- (the Roof has none to start with: Saye drops hers, `serverJoin`)
  end
  local brain = Brain.new({ health = Bosses.enemyHealth(Turrets.health), fire = fire, firstId = Turrets.firstId,
    calm = calm, rivals = rivals })
  for _, p in ipairs(map.turrets or {}) do
    brain:add(p.x, p.y, p.watch, p.arc)
  end
  sv = { brain = brain, work = {}, syncIn = 0, emptySends = 0 }
  return brain
end

--- One more, bolted down at (x, y) watching `watch` over `arc` (Saye's
--- "restructuring"). Returns it, or nil when there are no turrets here.
function Turrets.serverJoin(x, y, watch, arc)
  if not sv then
    return nil
  end
  return sv.brain:add(x, y, watch, arc)
end

function Turrets.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Turrets.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("TUR_STATE", server.tick))
  end
end

local function stateOf(t)
  if t.stunned > 0 then
    return 4
  elseif t.breachedBy then
    return 3
  end
  return STATE_CODE[t.state] or 0
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
  for _, t in ipairs(list) do
    parts[#parts + 1] = t.id
    parts[#parts + 1] = ("%.0f"):format(t.x)
    parts[#parts + 1] = ("%.0f"):format(t.y)
    parts[#parts + 1] = ("%.3f"):format(t.aim)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, t.hp))
    parts[#parts + 1] = stateOf(t)
  end
  local msg = Protocol.encode("TUR_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Turrets.serverStep(server, dt)
  now = now + dt
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  -- Breaches nobody is working drain away.
  for id, w in pairs(sv.work) do
    if now - w.lastWork > WORK_GRACE then
      w.progress = math.max(0, w.progress - Turrets.drain * dt)
    end
    if math.abs(w.progress - w.sent) > 0.04 or (w.progress == 0 and w.sent > 0) then
      w.sent = w.progress
      server:broadcast(Protocol.encode("TUR_PROG", id, ("%.2f"):format(w.progress)))
    end
    if w.progress == 0 then
      sv.work[id] = nil
    end
  end
  sync(server)
end

--- The turret with id `id`, if it is still up.
local function byId(id)
  for _, t in ipairs(sv and sv.brain.list or {}) do
    if t.id == id then
      return t
    end
  end
  return nil
end

Turrets.serverMessages = {
  TUR_WORK = function(server, player, args)
    local t = byId(tonumber(args[1]))
    if not t or t.breachedBy or player.vehicle or not Features.present(player)
      or Features.any("serverHeld", server, player) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, t.x, t.y) > (Turrets.reach + SLACK) ^ 2 then
      return
    end
    local w = sv.work[t.id] or { progress = 0, lastWork = -1, sent = 0 }
    sv.work[t.id] = w
    local dt = w.lastWork >= 0 and math.min(now - w.lastWork, WORK_EVERY * 1.5) or WORK_EVERY
    w.lastWork = now
    w.progress = math.min(1, w.progress + dt / Turrets.breachTime)
    if w.progress >= 1 then
      sv.work[t.id] = nil
      sv.brain:breach(t, player.id, Turrets.breachFor)
      server:broadcast(Protocol.encode("TUR_PROG", t.id, 0))
    end
  end,
}

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches one. Returns true when it hit one, and that a player's did.
function Turrets.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local t, i = sv.brain:at(x, y, radius)
  if not t or t.breachedBy == by then
    return false -- (its own rounds, and its breacher's, pass it by)
  end
  if sv.brain:hurt(t, i, damage or 20) then
    sv.work[t.id] = nil
    server:broadcast(Protocol.encode("TUR_DOWN", t.id, fmt(t.x), fmt(t.y)))
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, t.x, t.y, Turrets.drops)
    end
    Features.call("serverKill", server, { kind = "turret", x = t.x, y = t.y, by = by, angle = angle, cause = dtype })
  end
  return true, true
end

--- Every turret still up, for the audit (tools/audit): Halcyon's and
--- VEX's. A breached one is its breacher's now, no enemy, and left out.
function Turrets.serverEnemies(_server, add)
  for _, t in ipairs(sv and sv.brain.list or {}) do
    if not t.breachedBy then
      add({ id = t, kind = "cyber-feud/turret", x = t.x, y = t.y, hp = t.hp, radius = Brain.RADIUS })
    end
  end
end

--- The wiki's page on them (tools/wiki, docs/wiki.md).
function Turrets.wikiEnemies(add)
  local Saye = require("src.features.cyber-feud.saye")
  local Vex = require("src.features.cyber-feud.vex")
  add({
    kind = "cyber-feud/turret",
    portraitLayers = "all", -- (its portrait wants what it draws under cars too)
    name = "Sentry turret",
    quests = { "cyber-feud-tower", "cyber-feud-roof" },
    where = "Bolted down in Halcyon Tower's labs and round its security floor; on the Roof, dropped by Saye and "
      .. "driven by VEX",
    about = "A grey tripod with a magenta lens. It sweeps its arc, puts a laser on whoever it sees, and fires down "
      .. "it. Get next to one and it can be yours.",
    stats = {
      { "Health", Turrets.health },
      { "Sight", ("%g px, a %g degree cone sweeping its arc, along a clear line"):format(Brain.RANGE,
        math.deg(Brain.FOV)) },
      { "Numbers", ("On the Roof, up to %g of Saye's at once, and %g of VEX's for one player (%g more for each "
        .. "human past the first)"):format(Saye.TURRETS_MAX, Vex.turrets, Bosses.extra) },
    },
    weapons = {
      { "Burst fire", ("%g damage a round, in bursts of %g (%g s apart), then %g s, out to %g px"):format(
        Turrets.damage, Brain.BURST, Brain.BURST_GAP, Brain.PAUSE, Brain.RANGE) },
    },
    abilities = {
      ("Its laser is on you for %g s before the first round; it turns at %g rad/s and never past the ends of its "
        .. "arc."):format(Brain.WARN, Brain.TURN),
      ("Breachable: on foot within %g px of it, hold the action key for %g s and it fights for you for %g s, "
        .. "shooting Halcyon and the Static (the kills are yours). Let go and the breach drains away."):format(
        Turrets.reach, Turrets.breachTime, Turrets.breachFor),
      ("A sparker's EMP knocks it out for %g s."):format(Turrets.empTime),
      "Only players' rounds reach it.",
    },
    tips = {
      "Come at it from behind, out of its arc, and breach it.",
      ("Cross its front fast up close: at %g rad/s you outrun its turn."):format(Brain.TURN),
    },
    drops = ("%g koins"):format(Turrets.drops),
  })
end

function Turrets.serverEmp(x, y, radius)
  if sv then
    sv.brain:stun(x, y, radius, Turrets.empTime)
  end
end

function Turrets.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Turrets.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, aim, dAim, hp, state, hurt, progress }
local lastTick, heardAt, clock = 0, 0, 0
local near = nil -- the turret I am next to, on foot, that I could breach
local sendIn = 0

function Turrets.clear()
  shown, lastTick, near = {}, 0, nil
end

function Turrets.update(dt, client)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, t in pairs(shown) do
    t.dAim = t.dAim + Sight.angleDiff(t.aim, t.dAim) * k
    t.hurt = math.max(0, t.hurt - dt)
  end
  near = nil
  local x, y = client:myPose()
  if x and not client:myVehicle() then
    local best = Turrets.reach ^ 2
    for id, t in pairs(shown) do
      local d2 = dist2(x, y, t.x, t.y)
      if t.state ~= 3 and d2 <= best then
        near, best = id, d2
      end
    end
  end
  sendIn = sendIn - dt
  if near and Controls.isDown("enter-exit") and sendIn <= 0 then
    sendIn = WORK_EVERY
    client:send(Protocol.encode("TUR_WORK", near))
  end
end

--- The `actionTaken` convention: next to a turret on foot, the action key breaches it.
function Turrets.actionTaken()
  return near ~= nil
end

function Turrets.drawBelowCars()
  for _, t in pairs(shown) do -- the tripod's legs and its shadow
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.circle("fill", t.x + 4, t.y + 5, 15, 16)
    love.graphics.setColor(DARK)
    love.graphics.setLineWidth(3)
    for i = 0, 2 do
      local a = i * 2 * math.pi / 3 + math.pi / 2
      love.graphics.line(t.x, t.y, t.x + math.cos(a) * 17, t.y + math.sin(a) * 17)
    end
    love.graphics.setLineWidth(1)
  end
end

local function lensColor(t)
  return t.state == 3 and GREEN or MAGENTA
end

--- Its laser on whoever it has: thin while it warns, solid while it fires.
local function drawLaser(t)
  if t.state ~= 1 and t.state ~= 2 then
    return
  end
  local c = lensColor(t)
  local x0, y0 = t.x + math.cos(t.dAim) * 14, t.y + math.sin(t.dAim) * 14
  local x1, y1 = Sight.reach(t.x, t.y, t.dAim, Brain.RANGE)
  local pulse = t.state == 1 and (0.5 + 0.5 * math.abs(math.sin(clock * 18))) or 1
  love.graphics.setColor(c[1], c[2], c[3], 0.55 * pulse)
  love.graphics.setLineWidth(t.state == 2 and 2 or 1)
  love.graphics.line(x0, y0, x1, y1)
  love.graphics.setLineWidth(1)
end

--- The head: a grey dome turning on the tripod, its barrel and the lens.
function Turrets.drawAboveCars()
  for _, t in pairs(shown) do
    drawLaser(t)
    local out = t.state == 4
    love.graphics.push()
    love.graphics.translate(t.x, t.y)
    love.graphics.rotate(t.dAim + (out and 0.25 or 0))
    love.graphics.setColor(DARK)
    love.graphics.rectangle("fill", 4, -3, 18, 6, 1) -- the barrel
    love.graphics.setColor(t.hurt > 0 and { 1, 1, 1 } or GREY)
    love.graphics.circle("fill", 0, 0, 10, 16)
    love.graphics.setColor(DARK)
    love.graphics.circle("line", 0, 0, 10, 16)
    local c = lensColor(t)
    love.graphics.setColor(out and { 0.15, 0.05, 0.12 } or c)
    love.graphics.circle("fill", 6, 0, 3.2, 10)
    love.graphics.pop()
    if t.progress and t.progress > 0 then
      UI.ring(t.x, t.y - 26, 9, t.progress, GREEN, 3)
    end
    if t.hp < t.top then
      local bw, f = 24, math.max(0, t.hp / t.top)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", t.x - bw / 2 - 1, t.y + 16, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", t.x - bw / 2, t.y + 17, bw * f, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Turrets.drawNightLights(glow)
  for _, t in pairs(shown) do
    if t.state ~= 4 then
      glow(t.x + math.cos(t.dAim) * 6, t.y + math.sin(t.dAim) * 6, t.state == 0 and 40 or 60, lensColor(t), 0.7)
    end
  end
end

--- What to do here, over the ability row: hold the key.
function Turrets.drawHUD()
  local t = near and shown[near]
  if not t then
    return
  end
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local p = t.progress or 0
  local text = p > 0 and ("Breaching the turret... %d%%"):format(math.floor(p * 100))
    or ("Sentry turret.  Hold " .. key .. ": breach it (it fights for you)")
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(GREEN)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Turrets.clientMessages = {
  TUR_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local aim = tonumber(args[i + 3]) or 0
        local t = shown[id]
        if not t then
          t = { dAim = aim, hurt = 0, hp = Turrets.health }
          shown[id] = t
        end
        t.x, t.y, t.aim = x, y, aim
        local hp = tonumber(args[i + 4]) or t.hp
        if hp < t.hp then
          t.hurt = HURT
        end
        t.hp = hp
        t.top = math.max(t.top or Turrets.health, hp) -- (tougher on a job finished before)
        t.state = tonumber(args[i + 5]) or 0
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  TUR_PROG = function(_client, args)
    local t = shown[tonumber(args[1]) or -1]
    if t then
      t.progress = tonumber(args[2]) or 0
    end
  end,
  TUR_DOWN = function(client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if id then
      shown[id] = nil
    end
    local weapons = Features.byName.weapons
    if x and y and weapons and weapons.explosionAt then
      weapons:explosionAt(client, x, y, MAGENTA)
    end
  end,
}

return Turrets
