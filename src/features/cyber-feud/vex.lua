-- VEX's phase on the Roof (docs/cyber-feud.md, "On the Roof"): the end of
-- the line. When Saye and Kilowatt are both down, the Shard's carrier
-- hands it over at her uplink (init.lua: `serverDelivered`); every screen
-- shows what is on it (`revealTime`), and then VEX locks the roof (a
-- green barrier across the top of the stairs) and comes up huge, her face
-- projected over the whole roof with both tells flickering at once. She
-- can't be shot. She drives the tower's turrets (a ring of them comes up
-- round the roof, the map's `bosses.vexTurrets`), and the four relay
-- terminals near the corners (`relays`) keep her there.
--
-- Breach the relays one by one: on foot at one, hold the action key (F)
-- for `relayTime` seconds (it drains when you let go). She sits at one of
-- the relays left (`at`) and moves between them: working the one she is at
-- goes at half the pace, and she pulses a ring of shock out round it every
-- `pulseEvery`. For `warnTime` before each pulse the relay charges: its
-- reach lights up blue on the ground, filling in from the middle, static
-- crackling in it thicker and further out as it builds (only to look at:
-- the pulse is the hit), and it whines (the tell: step out, step back in). From the tell until `holdAfter` past
-- the pulse that relay keeps its breach with nobody at it, so stepping out
-- costs nothing. Every relay lost, her face breaks up more. On the last she
-- gets away: her face shrinks to a single green pixel that streaks off,
-- the roof unlocks, her turrets go dead, and init.lua puts the HOME star
-- up on the helipad (`serverGone`).
--
-- troops.lua starts, steps and stops it with the bosses and draws it;
-- init.lua passes on the breach, the prompt and the objective line.
--
-- Messages
--   server -> all     VX_STAGE <stage>          on (she has the roof) | gone (she got away); to a joiner too
--   server -> all     VX_AT    <relay>          the relay she is at now
--   client -> server  VX_WORK  <relay>          (I am holding the key at it; every WORK_EVERY)
--   server -> all     VX_PROG  <relay> <0..1>   how far a relay's breach is
--   server -> all     VX_RELAY <relay>          it's breached (to a joiner, every one that is)
--   server -> all     VX_CHARGE <relay> <seconds>  her relay is charging: a pulse in that long
--   server -> all     VX_PULSE <x> <y> <radius> her shock ring out round her relay

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Controls = require("src.controls")
local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")
local Bosses = require("src.features.bosses")
local Face = require("src.features.cyber-feud.face")
local Turrets = require("src.features.cyber-feud.turrets")

local Vex = {}

-- Tuning ------------------------------------------------------------------
Vex.relayTime = 5 -- seconds of holding the key at a relay to breach it...
Vex.guarded = 0.5 -- ...at this pace at the one she is at
Vex.drain = 0.4 -- of the whole a second a relay loses while nobody works it...
Vex.drainAfter = 1.5 -- ...from this many seconds after the last of the work on it
Vex.reach = 75 -- px from a relay's middle that counts as at it
Vex.moveEvery = 20 -- seconds she stays at a relay before moving to another
Vex.pulseEvery = 6 -- seconds between her shock rings at her relay
Vex.warnTime = 2 -- seconds her relay charges, its reach lit, before each one (the tell)
Vex.holdAfter = 1 -- seconds after a pulse her relay keeps its breach without anyone at it (from the tell on)
Vex.pulseRadius = 190 -- px
Vex.pulseDamage = 18 -- shock (under a stun: damage's stunMin is 20)
Vex.turrets = 4 -- turrets she drives, for one human (one more for each past the first)
Vex.revealTime = 12 -- seconds after the Shard is handed over (the reveal screen) before she takes the roof

local WORK_EVERY = 0.2
local SLACK = 40
local GREEN = Face.GREEN
local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }
local BLUE = { 0.30, 0.62, 1.00 } -- her relay's charge and pulse
local RED = { 1.00, 0.22, 0.20 } -- the ring round the relay she is at: keep off
local SPARK = { 0.82, 0.92, 1.00 } -- the core of a bolt of its static

local function cityMap()
  local c = Features.byName["city-map"]
  return c and c.map
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Put `s` into `map`'s solids and cells (lock), or take it out (unlock).
local function setSolid(map, s, on)
  local CELL = Layout.CELL
  local function each(fn)
    for c = math.floor(s.x / CELL), math.floor((s.x + s.w) / CELL) do
      for r = math.floor(s.y / CELL), math.floor((s.y + s.h) / CELL) do
        map.cells[c] = map.cells[c] or {}
        map.cells[c][r] = map.cells[c][r] or {}
        fn(map.cells[c][r])
      end
    end
  end
  local function drop(list)
    for i = #list, 1, -1 do
      if list[i] == s then
        table.remove(list, i)
      end
    end
  end
  drop(map.solids)
  each(drop)
  if on then
    map.solids[#map.solids + 1] = s
    each(function(list)
      list[#list + 1] = s
    end)
  end
end

local function bossesDown()
  local k = require("src.features.cyber-feud.kilowatt").server()
  local s = require("src.features.cyber-feud.saye").server()
  return k and s and k.down and s.down
end

-- Server --------------------------------------------------------------------

local sv = nil -- { stage, relays, at, moveIn, pulseIn, startIn, turrets, lock }

--- On `map` with `relays` (the Roof): waiting for the bosses to fall.
function Vex.serverStart(_server, map)
  sv = nil
  local b = map.bosses
  if not (map.relays and b and b.lock) then
    return
  end
  sv = { stage = "waiting", relays = {}, at = 1, moveIn = Vex.moveEvery, pulseIn = Vex.pulseEvery, turrets = {},
    lock = b.lock, turretSpots = b.vexTurrets or {} }
  for i, r in ipairs(map.relays) do
    sv.relays[i] = { x = r.x, y = r.y, progress = 0, lastWork = -1, sent = 0, done = false, holdUntil = 0 }
  end
end

function Vex.serverStop(server)
  if sv then
    local map = cityMap()
    if map and sv.stage == "on" then
      setSolid(map, sv.lock, false)
    end
    sv = nil
    if server then
      server:broadcast(Protocol.encode("VX_STAGE", "off"))
    end
  end
end

--- The Shard is hers (init.lua, at her uplink): she takes the roof once
--- everyone has seen what is on it.
function Vex.serverDelivered()
  if sv and sv.stage == "waiting" and not sv.startIn then
    sv.startIn = Vex.revealTime
  end
end

--- Is she there to beat (the Roof isn't done until she's gone)?
function Vex.serverUp()
  return sv ~= nil and sv.stage ~= "gone"
end

--- Did she get away (the Roof is done)?
function Vex.serverGone()
  return sv ~= nil and sv.stage == "gone"
end

--- Her, while she has the roof, for the audit (tools/audit): at the relay
--- she sits at. She is a projection, so she can't be shot and stands over
--- whatever is there. Her turrets are turrets.lua's.
function Vex.serverEnemies(_server, add)
  if sv and sv.stage == "on" and sv.relays[sv.at] then
    local r = sv.relays[sv.at]
    add({ id = sv, kind = "cyber-feud/vex", x = r.x, y = r.y, radius = 0, immune = true, flying = true })
  end
end

--- The wiki's page on her (tools/wiki, docs/wiki.md). She has no health to
--- scale; what grows is her pulse, said in so many words.
function Vex.wikiEnemies(add)
  local rage = Bosses.rage
  local function times(n)
    return n == 2 and "twice" or ("%g times"):format(n)
  end
  add({
    kind = "cyber-feud/vex",
    boss = true,
    drawImmune = true,
    scaling = "none",
    name = "VEX",
    quests = { "cyber-feud-roof" },
    where = "The Roof, once Saye and Kilowatt are down and the Shard is in her uplink",
    about = "The voice in your earpiece the whole way, and the one who wanted the Shard all along. She locks the "
      .. "roof, comes up huge, her face projected over all of it, and turns the tower's turrets on you. She can't "
      .. "be shot: you beat her by breaching the relays that keep her there.",
    stats = {
      { "Numbers", ("%g turrets for one player, %g more for each human past the first"):format(Vex.turrets,
        Bosses.extra) },
    },
    weapons = {
      { "Shock pulse", ("a ring of %g shock damage out to %g px round the relay she is at, every %g s"):format(
        Vex.pulseDamage, Vex.pulseRadius, Vex.pulseEvery) },
      { "Her turrets", "sentry turrets that come up round the roof when she takes it (Sentry turret's page)" },
    },
    abilities = {
      ("%g s after the Shard is handed over she takes the roof: a green barrier drops across the stairs."):format(
        Vex.revealTime),
      ("Her relays: on foot within %g px of one, hold the action key for %g s to breach it. Let go and after %g s it "
        .. "drains away."):format(Vex.reach, Vex.relayTime, Vex.drainAfter),
      ("She sits at one of the relays left, moving to another every %g s; breaching the one she is at takes %s "
        .. "as long."):format(Vex.moveEvery, times(1 / Vex.guarded)),
      ("Before each pulse her relay charges for %g s, its reach lighting up blue and whining: the tell. From then "
        .. "until %g s after the pulse it keeps its breach with nobody at it."):format(Vex.warnTime, Vex.holdAfter),
      "Every relay that falls, her face breaks up more, and Halcyon's dropship comes at once if it isn't in the air.",
      "On the last relay she gets away into the net: the roof unlocks and her turrets go dead.",
      ("Each time the job has been finished before (up to %g), her pulse hits %g%% harder."):format(rage.max,
        math.floor(rage.damage * 100 + 0.5)),
    },
    tips = {
      "Step out of the blue ring when it lights up and back in after the pulse: you lose nothing.",
      ("Work the relays she isn't at: they go %s as fast."):format(times(1 / Vex.guarded)),
      "Breach or shoot her turrets first if they have the relay covered.",
    },
  })
end

local function left()
  local out = {}
  for i, r in ipairs(sv.relays) do
    if not r.done then
      out[#out + 1] = i
    end
  end
  return out
end

--- She moves to another relay left: the one furthest along, to hold it.
local function move(server)
  local best, bestP = nil, -1
  for _, i in ipairs(left()) do
    local p = sv.relays[i].progress + love.math.random() * 0.2
    if i ~= sv.at and p > bestP then
      best, bestP = i, p
    end
  end
  if best then
    sv.at = best
    server:broadcast(Protocol.encode("VX_AT", best))
    sv.pulseIn, sv.warned = math.max(sv.pulseIn, Vex.warnTime + 0.5), false -- (the new one charges in full first)
  end
  sv.moveIn = Vex.moveEvery
end

local now = 0

local function takeRoof(server)
  sv.stage = "on"
  setSolid(cityMap(), sv.lock, true)
  server:broadcast(Protocol.encode("VX_STAGE", "on"))
  server:broadcast(Protocol.encode("CF_BEAT", "roof.vexLock"))
  local n = math.min(#sv.turretSpots, Bosses.plus(Vex.turrets, server))
  local Sight = require("src.features.d-day.sight")
  for i = 1, n do
    local p = sv.turretSpots[i]
    local x, y = p.x, p.y
    for d = 16, 160, 16 do -- not inside an AC unit that happens to stand there
      if not Sight.blocked(x, y) then
        break
      end
      x, y = p.x + math.cos(p.watch) * d, p.y + math.sin(p.watch) * d
    end
    local t = Turrets.serverJoin(x, y, p.watch, 2 * math.pi)
    if t then
      sv.turrets[#sv.turrets + 1] = t
    end
  end
  sv.at = love.math.random(#sv.relays)
  server:broadcast(Protocol.encode("VX_AT", sv.at))
end

--- She's gone: the roof unlocks, her turrets die with her signal.
local function getAway(server)
  sv.stage = "gone"
  setSolid(cityMap(), sv.lock, false)
  server:broadcast(Protocol.encode("VX_STAGE", "gone"))
  local tsv = Turrets.server()
  if tsv then
    for _, t in ipairs(sv.turrets) do
      for i = #tsv.brain.list, 1, -1 do
        if tsv.brain.list[i] == t then
          table.remove(tsv.brain.list, i)
          server:broadcast(Protocol.encode("TUR_DOWN", t.id, ("%.1f"):format(t.x), ("%.1f"):format(t.y)))
        end
      end
    end
  end
end

function Vex.serverStep(server, dt)
  now = now + dt
  if not sv then
    return
  end
  if sv.stage == "waiting" then
    if bossesDown() and sv.startIn then -- (set when the Shard is handed over)
      sv.startIn = sv.startIn - dt
      if sv.startIn <= 0 then
        takeRoof(server)
      end
    end
    return
  end
  if sv.stage ~= "on" then
    return
  end
  for i, r in ipairs(sv.relays) do
    if not r.done then
      if now - r.lastWork > Vex.drainAfter and now >= r.holdUntil then
        r.progress = math.max(0, r.progress - Vex.drain * dt)
      end
      if math.abs(r.progress - r.sent) > 0.04 or (r.progress == 0 and r.sent > 0) then
        r.sent = r.progress
        server:broadcast(Protocol.encode("VX_PROG", i, ("%.2f"):format(r.progress)))
      end
    end
  end
  sv.moveIn = sv.moveIn - dt
  if sv.moveIn <= 0 then
    move(server)
  end
  sv.pulseIn = sv.pulseIn - dt
  if sv.pulseIn <= Vex.warnTime and not sv.warned then
    sv.warned = true
    local r = sv.relays[sv.at]
    r.holdUntil = now + math.max(0, sv.pulseIn) + Vex.holdAfter -- (step out of the tell: it keeps what you had done)
    server:broadcast(Protocol.encode("VX_CHARGE", sv.at, ("%.2f"):format(math.max(0, sv.pulseIn))))
  end
  if sv.pulseIn <= 0 then
    sv.pulseIn, sv.warned = Vex.pulseEvery, false
    local r = sv.relays[sv.at]
    server:broadcast(Protocol.encode("VX_PULSE", ("%.0f"):format(r.x), ("%.0f"):format(r.y), Vex.pulseRadius))
    local weapons = Features.byName.weapons
    local amount = Vex.pulseDamage * Bosses.power() -- (harder on a job finished before)
    for _, p in pairs(server.players) do
      if Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, r.x, r.y) <= Vex.pulseRadius ^ 2 and weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, amount, math.atan2(y - r.y, x - r.x), "shock")
        end
      end
    end
  end
end

function Vex.serverPlayerJoined(server, player)
  if not sv or player.bot or sv.stage == "waiting" then
    return
  end
  server:send(player, Protocol.encode("VX_STAGE", sv.stage))
  for i, r in ipairs(sv.relays) do
    if r.done then
      server:send(player, Protocol.encode("VX_RELAY", i))
    end
  end
  server:send(player, Protocol.encode("VX_AT", sv.at))
end

Vex.serverMessages = {
  VX_WORK = function(server, player, args)
    local i = tonumber(args[1])
    local r = sv and sv.stage == "on" and i and sv.relays[i]
    if not r or r.done or player.vehicle or not Features.present(player)
      or Features.any("serverHeld", server, player) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, r.x, r.y) > (Vex.reach + SLACK) ^ 2 then
      return
    end
    local step = r.lastWork >= 0 and math.min(now - r.lastWork, WORK_EVERY * 1.5) or WORK_EVERY
    r.lastWork = now
    r.progress = math.min(1, r.progress + step / Vex.relayTime * (i == sv.at and Vex.guarded or 1))
    if r.progress < 1 then
      return
    end
    r.done = true
    server:broadcast(Protocol.encode("VX_RELAY", i))
    local remaining = #left()
    if remaining == 0 then
      getAway(server)
      return
    end
    server:broadcast(Protocol.encode("CF_BEAT", "roof.vex" .. (#sv.relays - remaining)))
    if i == sv.at then
      move(server)
    end
  end,
}

--- For tests.
function Vex.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = { stage = nil, relays = {}, at = nil, pulses = {}, gone = nil } -- relays [i] = { progress, done }
local charge = nil -- { relay, left, max } while her relay charges for a pulse
local inCharge = false -- am I in its reach (the HUD's warning)
local bolts = {} -- { pts, t, life }: the static in a charge or a pulse, drawn only
local boltIn = 0
local whine = nil
local face = nil
local near = nil
local myX, myY = nil, nil -- where I am (update), for the marker over the relay to go for
local sendIn, clock = 0, 0

local ESCAPE = 2.2 -- seconds of her getting away: shrinking, then the pixel streaking off

function Vex.clear()
  local map = cityMap()
  if map and map.bosses and map.bosses.lock and cl.stage == "on" then
    setSolid(map, map.bosses.lock, false)
  end
  cl = { stage = nil, relays = {}, at = nil, pulses = {}, gone = nil }
  near, charge, inCharge, bolts = nil, nil, false, {}
end

--- The whine of her relay charging: a rising buzz the length of the tell.
function Vex.load()
  local buf = Synth.newBuffer(Vex.warnTime)
  buf:sweep(0, Vex.warnTime, 140, 620, { wave = "saw", amp = 0.5 })
  buf:lowpass(2200)
  whine = love.audio.newSource(buf:toSoundData(0.7), "static")
  whine:setAttenuationDistances(300, 2000)
end

--- A bolt of static from (x, y) out `len` px at `angle`: a jagged line.
local function bolt(x, y, angle, len, life)
  local pts, steps = { x, y }, 7
  local dx, dy = math.cos(angle), math.sin(angle)
  for i = 1, steps do
    local d = len * i / steps
    local j = i < steps and (love.math.random() - 0.5) * len * 0.28 or 0
    pts[#pts + 1], pts[#pts + 2] = x + dx * d - dy * j, y + dy * d + dx * j
  end
  bolts[#bolts + 1] = { pts = pts, t = 0, life = life }
end

local function relay(i)
  cl.relays[i] = cl.relays[i] or { progress = 0, done = false }
  return cl.relays[i]
end

--- Is she on the roof, as this screen knows it? And how many relays are left.
function Vex.active()
  if cl.stage ~= "on" then
    return false, 0
  end
  local map = cityMap()
  local n = 0
  for i in ipairs(map and map.relays or {}) do
    if not relay(i).done then
      n = n + 1
    end
  end
  return true, n
end

--- Which corner of the roof relay `i` is in ("top-left"...), against the
--- middle of all of them.
local function corner(relays, i)
  local cx, cy = 0, 0
  for _, r in ipairs(relays) do
    cx, cy = cx + r.x / #relays, cy + r.y / #relays
  end
  local r = relays[i]
  return (r.y < cy and "top" or "bottom") .. "-" .. (r.x < cx and "left" or "right")
end

--- The relay to go for from (x, y), for the objective line and the marker
--- over it: one already being breached first, else the nearest; not the
--- one she is at while any other is left. Its index, where it is, its
--- corner ("top-left"...), and whether she is at it.
function Vex.target(x, y)
  local map = cityMap()
  local relays = map and map.relays or {}
  local best, bestScore
  for i, r in ipairs(relays) do
    local st = relay(i)
    if not st.done then
      local score = (x and dist2(x, y, r.x, r.y) or 0) - st.progress * 1e8 -- (one under way beats any distance)
      if i == cl.at then
        score = score + 1e9 -- hers last
      end
      if not bestScore or score < bestScore then
        best, bestScore = i, score
      end
    end
  end
  if not best then
    return nil
  end
  local r = relays[best]
  return best, r.x, r.y, corner(relays, best), best == cl.at
end

local function broken()
  local map = cityMap()
  local total, done = #(map and map.relays or {}), 0
  for i = 1, total do
    if relay(i).done then
      done = done + 1
    end
  end
  return total > 0 and done / total or 0
end

function Vex.update(dt, client)
  clock = clock + dt
  if face then
    face:update(dt)
  end
  if cl.gone then
    cl.gone = cl.gone + dt
  end
  for i = #cl.pulses, 1, -1 do
    local p = cl.pulses[i]
    p.t = p.t + dt
    if p.t > 0.6 then
      table.remove(cl.pulses, i)
    end
  end
  for i = #bolts, 1, -1 do
    local b = bolts[i]
    b.t = b.t + dt
    if b.t >= b.life then
      table.remove(bolts, i)
    end
  end
  if charge then
    charge.left = charge.left - dt
    local cm = cityMap()
    local cr = cm and cm.relays and cm.relays[charge.relay]
    boltIn = boltIn - dt
    if cr and boltIn <= 0 then -- the static building: more of it, further out, as the charge fills
      local k = 1 - math.max(0, charge.left) / charge.max
      boltIn = 0.14 - 0.1 * k
      for _ = 1, 1 + math.floor(k * 2.5) do
        local reach = Vex.pulseRadius * (0.3 + 0.7 * k) * (0.6 + 0.4 * love.math.random())
        bolt(cr.x, cr.y, love.math.random() * 2 * math.pi, reach, 0.1 + 0.06 * love.math.random())
      end
    end
    if charge.left <= 0 then
      charge = nil -- (the pulse is due: VX_PULSE)
    end
  end
  near, inCharge = nil, false
  local map = cityMap()
  if cl.stage ~= "on" or not map or not map.relays then
    return
  end
  local x, y = client:myPose()
  myX, myY = x, y
  local cr = charge and map.relays[charge.relay]
  inCharge = cr and x and dist2(x, y, cr.x, cr.y) <= Vex.pulseRadius ^ 2 or false
  if x and not client:myVehicle() then
    for i, r in ipairs(map.relays) do
      if not relay(i).done and dist2(x, y, r.x, r.y) <= Vex.reach ^ 2 then
        near = i
      end
    end
  end
  sendIn = sendIn - dt
  if near and Controls.isDown("enter-exit") and sendIn <= 0 then
    sendIn = WORK_EVERY
    client:send(Protocol.encode("VX_WORK", near))
  end
end

function Vex.actionTaken()
  return near ~= nil
end

--- Her face over the whole roof, faint, breaking up as the relays go; both
--- tells flickering at once. Under everyone, so the fight stays readable
--- over her.
function Vex.drawBelowCars()
  local map = cityMap()
  if not (map and map.relays) or cl.stage ~= "on" then
    return
  end
  face = face or Face.new()
  local cx, cy = map.x0 + map.cols * Layout.TILE / 2, map.y0 + map.rows * Layout.TILE / 2
  local tell = math.floor(clock * 12) % 2 == 0 and MAGENTA or CYAN
  face:draw(cx, cy, 16, tell, { alpha = 0.3, broken = broken() })
  local r = charge and map.relays[charge.relay]
  if r then -- her relay charging: its reach, filling in from the middle until it goes
    local k = 1 - math.max(0, charge.left) / charge.max
    local flicker = 0.5 + 0.5 * math.abs(math.sin(clock * (10 + 20 * k)))
    love.graphics.setColor(BLUE[1], BLUE[2], BLUE[3], 0.06 + 0.06 * flicker)
    love.graphics.circle("fill", r.x, r.y, Vex.pulseRadius, 64)
    love.graphics.setColor(BLUE[1], BLUE[2], BLUE[3], 0.15 + 0.2 * k)
    love.graphics.circle("fill", r.x, r.y, Vex.pulseRadius * k, 64)
    love.graphics.setColor(BLUE[1], BLUE[2], BLUE[3], 0.5 + 0.5 * flicker)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", r.x, r.y, Vex.pulseRadius, 64)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Her getting away, on every screen whatever it is looking at: her face
--- in the middle of it shrinking to a single green pixel, which streaks
--- off the right-hand edge.
local function drawEscape()
  face = face or Face.new()
  local w, h = love.graphics.getDimensions()
  local cx, cy = w / 2, h / 2 - 40
  if cl.gone < 1.2 then
    local k = cl.gone / 1.2
    face:draw(cx, cy, 6 * (1 - k) + 0.15 * k, MAGENTA, { alpha = 0.85, broken = 1 - k * 0.5 })
  else
    local s = (cl.gone - 1.2) / (ESCAPE - 1.2)
    local x = cx + s * s * (w / 2 + 40)
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.45)
    love.graphics.rectangle("fill", x - 220 * s, cy - 2, 220 * s, 4)
    love.graphics.setColor(GREEN)
    love.graphics.rectangle("fill", x, cy - 4, 8, 8)
  end
  love.graphics.setColor(1, 1, 1)
end

--- The relays: dead and sparking once breached, a red ring breathing round
--- the one she is at and her face on its screen, a breach's progress over it, a white arrow bobbing over
--- the one to go for (`Vex.target`); her pulses; the lock.
function Vex.drawAboveCars()
  local map = cityMap()
  if not (map and map.relays) or cl.stage ~= "on" then
    return
  end
  local goal, gx, gy = Vex.target(myX, myY)
  if goal and relay(goal).progress <= 0 then
    local bob = gy - 70 - 6 * math.abs(math.sin(clock * 4))
    love.graphics.setColor(1, 1, 1, 0.85)
    love.graphics.polygon("fill", gx - 10, bob - 12, gx + 10, bob - 12, gx, bob)
  end
  for i, r in ipairs(map.relays) do
    local st = relay(i)
    if st.done then
      love.graphics.setColor(0.08, 0.08, 0.08, 0.85)
      love.graphics.rectangle("fill", r.x - 18, r.y - 18, 36, 36)
      if math.random() < 0.3 then
        love.graphics.setColor(1, 0.9, 0.6)
        love.graphics.circle("fill", r.x + math.random(-14, 14), r.y + math.random(-14, 14), 1.5, 6)
      end
    else
      if i == cl.at then -- hers: a red ring breathing round it, her face on its screen
        local breath = 0.5 + 0.5 * math.sin(clock * 2.2) -- slow, in and out
        local ring = 42 + 8 * breath
        love.graphics.setColor(RED[1], RED[2], RED[3], 0.2 * breath) -- a soft halo round it
        love.graphics.setLineWidth(8)
        love.graphics.circle("line", r.x, r.y, ring + 4, 40)
        love.graphics.setColor(RED[1], RED[2], RED[3], 0.4 + 0.5 * breath)
        love.graphics.setLineWidth(2 + 2 * breath)
        love.graphics.circle("line", r.x, r.y, ring, 40)
        love.graphics.setLineWidth(1)
        love.graphics.setColor(0.03, 0.07, 0.05)
        love.graphics.rectangle("fill", r.x - 24, r.y - 26, 48, 52) -- (inside the relay's 64 px casing)
        face = face or Face.new()
        face:draw(r.x, r.y, 0.7, nil)
      end
      if st.progress > 0 then
        UI.ring(r.x, r.y - 52, 10, st.progress, GREEN, 3)
      end
    end
  end
  for _, p in ipairs(cl.pulses) do
    local k = p.t / 0.6
    love.graphics.setColor(BLUE[1], BLUE[2], BLUE[3], 0.8 * (1 - k))
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", p.x, p.y, p.r * k, 48)
    love.graphics.setLineWidth(1)
  end
  for _, b in ipairs(bolts) do -- the static: a blue glow round a white-blue core
    local a = 1 - b.t / b.life
    love.graphics.setColor(BLUE[1], BLUE[2], BLUE[3], 0.4 * a)
    love.graphics.setLineWidth(5)
    love.graphics.line(b.pts)
    love.graphics.setColor(SPARK[1], SPARK[2], SPARK[3], 0.95 * a)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(b.pts)
  end
  love.graphics.setLineWidth(1)
  local s = map.bosses and map.bosses.lock
  if s then -- the lock: green laser bars across the stairs
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.55 + 0.3 * math.abs(math.sin(clock * 6)))
    for yy = s.y + 3, s.y + s.h - 3, 6 do
      love.graphics.line(s.x, yy, s.x + s.w, yy)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Vex.drawNightLights(glow)
  local map = cityMap()
  if not (map and map.relays) or cl.stage ~= "on" then
    return
  end
  for i, r in ipairs(map.relays) do
    if not relay(i).done then
      glow(r.x, r.y, i == cl.at and 200 or 110, GREEN, i == cl.at and 0.9 or 0.5)
    end
  end
  for _, p in ipairs(cl.pulses) do
    glow(p.x, p.y, p.r * (p.t / 0.6) + 40, BLUE, 0.5 * (1 - p.t / 0.6))
  end
  local r = charge and map.relays[charge.relay]
  if r then
    local k = 1 - math.max(0, charge.left) / charge.max
    glow(r.x, r.y, 60 + Vex.pulseRadius * k, BLUE, 0.3 + 0.5 * k)
  end
end

function Vex.drawHUD()
  if cl.gone and cl.gone < ESCAPE then
    drawEscape()
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  if inCharge then -- in her relay's reach as it charges
    local text = "VEX's relay is charging - get clear!"
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 159, w, "center")
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.6 + 0.4 * math.abs(math.sin(clock * 12)))
    love.graphics.printf(text, 0, h - 160, w, "center")
  end
  local st = near and relay(near)
  if not st then
    love.graphics.setColor(1, 1, 1)
    return
  end
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local text = st.progress > 0 and ("Breaching the relay... %d%%"):format(math.floor(st.progress * 100))
    or ("VEX's relay.  Hold " .. key .. ": breach it" .. (near == cl.at and "  (she's here: slow going)" or ""))
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(GREEN)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Vex.clientMessages = {
  VX_STAGE = function(_client, args)
    local stage = args[1]
    local map = cityMap()
    local lock = map and map.bosses and map.bosses.lock
    if stage == "on" and cl.stage ~= "on" then
      if lock then
        setSolid(map, lock, true) -- (the host's client shares the host's map: setSolid never doubles it)
      end
    elseif stage ~= "on" and cl.stage == "on" and lock then
      setSolid(map, lock, false)
    end
    if stage == "gone" and cl.stage == "on" then
      cl.gone = 0
    end
    cl.stage = stage
  end,
  VX_AT = function(_client, args)
    cl.at = tonumber(args[1])
    charge = nil -- (she moved: any charge was the old relay's)
  end,
  VX_CHARGE = function(_client, args)
    local i, secs = tonumber(args[1]), tonumber(args[2])
    local map = cityMap()
    local r = map and map.relays and i and map.relays[i]
    if r and secs then
      charge = { relay = i, left = secs, max = math.max(secs, 0.01) }
      if whine then
        local s = whine:clone()
        s:setPosition(r.x, 0, r.y)
        s:setVolume(0.7 * Audio.volume("weapons"))
        s:seek(math.max(0, Vex.warnTime - secs))
        s:play()
      end
    end
  end,
  VX_PROG = function(_client, args)
    local i, p = tonumber(args[1]), tonumber(args[2])
    if i and p then
      relay(i).progress = p
    end
  end,
  VX_RELAY = function(client, args)
    local i = tonumber(args[1])
    local map = cityMap()
    local r = map and map.relays and i and map.relays[i]
    if r then
      local st = relay(i)
      st.done, st.progress = true, 1
      local weapons = Features.byName.weapons
      if weapons and weapons.explosionAt then
        weapons:explosionAt(client, r.x, r.y, GREEN)
      end
    end
  end,
  VX_PULSE = function(_client, args)
    local x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if x and y and r then
      cl.pulses[#cl.pulses + 1] = { x = x, y = y, r = r, t = 0 }
      for i = 1, 10 do -- the static let go, out to the edge
        bolt(x, y, (i + love.math.random()) * 2 * math.pi / 10, r * (0.8 + 0.2 * love.math.random()), 0.25)
      end
    end
    charge = nil
  end,
}

return Vex
