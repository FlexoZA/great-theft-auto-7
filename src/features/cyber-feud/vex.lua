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
-- `pulseEvery`. Every relay lost, her face breaks up more. On the last she
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
--   server -> all     VX_PULSE <x> <y> <radius> her shock ring out round her relay

local Protocol = require("src.net.protocol")
local Features = require("src.features")
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
Vex.drain = 0.4 -- of the whole a second a relay loses while nobody works it
Vex.reach = 75 -- px from a relay's middle that counts as at it
Vex.moveEvery = 11 -- seconds she stays at a relay before moving to another
Vex.pulseEvery = 4 -- seconds between her shock rings at her relay
Vex.pulseRadius = 190 -- px
Vex.pulseDamage = 18 -- shock (under a stun: damage's stunMin is 20)
Vex.turrets = 4 -- turrets she drives, for one human (one more for each past the first)
Vex.revealTime = 12 -- seconds after the Shard is handed over (the reveal screen) before she takes the roof

local WORK_EVERY = 0.2
local WORK_GRACE = 0.45
local SLACK = 40
local GREEN = Face.GREEN
local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }

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
    sv.relays[i] = { x = r.x, y = r.y, progress = 0, lastWork = -1, sent = 0, done = false }
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
      if now - r.lastWork > WORK_GRACE then
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
  if sv.pulseIn <= 0 then
    sv.pulseIn = Vex.pulseEvery
    local r = sv.relays[sv.at]
    server:broadcast(Protocol.encode("VX_PULSE", ("%.0f"):format(r.x), ("%.0f"):format(r.y), Vex.pulseRadius))
    local weapons = Features.byName.weapons
    for _, p in pairs(server.players) do
      if Features.visible(server, p) then
        local x, y = Features.bodyPose(server, p)
        if dist2(x, y, r.x, r.y) <= Vex.pulseRadius ^ 2 and weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, Vex.pulseDamage, math.atan2(y - r.y, x - r.x), "shock")
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
local face = nil
local near = nil
local sendIn, clock = 0, 0

local ESCAPE = 2.2 -- seconds of her getting away: shrinking, then the pixel streaking off

function Vex.clear()
  local map = cityMap()
  if map and map.bosses and map.bosses.lock and cl.stage == "on" then
    setSolid(map, map.bosses.lock, false)
  end
  cl = { stage = nil, relays = {}, at = nil, pulses = {}, gone = nil }
  near = nil
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

--- The nearest relay still up, from (x, y), for the objective line's distance.
function Vex.nearestRelay(x, y)
  local map = cityMap()
  local best, bx, by, bestD2
  for i, r in ipairs(map and map.relays or {}) do
    local d2 = x and dist2(x, y, r.x, r.y) or 0
    if not relay(i).done and (not bestD2 or d2 < bestD2) then
      best, bx, by, bestD2 = i, r.x, r.y, d2
    end
  end
  return best and bx, by
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
  near = nil
  local map = cityMap()
  if cl.stage ~= "on" or not map or not map.relays then
    return
  end
  local x, y = client:myPose()
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

--- The relays: dead and sparking once breached, her green ring round the
--- one she is at, a breach's progress over it; her pulses; the lock.
function Vex.drawAboveCars()
  local map = cityMap()
  if not (map and map.relays) or cl.stage ~= "on" then
    return
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
      if i == cl.at then
        love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.5 + 0.4 * math.abs(math.sin(clock * 3)))
        love.graphics.setLineWidth(3)
        love.graphics.circle("line", r.x, r.y, 46, 32)
        love.graphics.setLineWidth(1)
      end
      if st.progress > 0 then
        UI.ring(r.x, r.y - 52, 10, st.progress, GREEN, 3)
      end
    end
  end
  for _, p in ipairs(cl.pulses) do
    local k = p.t / 0.6
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], 0.8 * (1 - k))
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", p.x, p.y, p.r * k, 48)
    love.graphics.setLineWidth(1)
  end
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
    glow(p.x, p.y, p.r * (p.t / 0.6) + 40, GREEN, 0.5 * (1 - p.t / 0.6))
  end
end

function Vex.drawHUD()
  if cl.gone and cl.gone < ESCAPE then
    drawEscape()
  end
  local st = near and relay(near)
  if not st then
    return
  end
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local text = st.progress > 0 and ("Breaching the relay... %d%%"):format(math.floor(st.progress * 100))
    or ("VEX's relay.  Hold " .. key .. ": breach it" .. (near == cl.at and "  (she's here: slow going)" or ""))
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
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
    end
  end,
}

return Vex
