-- Terminals that open the way on: a quest line's levels hide a few off the
-- straight way through, and you have to go and find them. Eternal Mood's
-- every level (docs/eternal-mood.md, "Terminals") and Borderline's Frozen
-- Wreck (docs/borderline.md) use them. Each belongs to a lock (the map's
-- `locks`, its terminals the map's `terminals` naming it); once all of a
-- lock's terminals are done the lock opens: its walls come down (solids
-- across a doorway or the road, built into the map like any wall: nothing
-- gets past them, not a person, not a round), and a lock that holds the
-- level's way on (`exit`) lets it go (`serverLocked`, as a boss does).
-- Heck's are seals, not terminals (`look`), lit the same way.
--
-- To do one, stand at it and hold the action key (F) for WORK_TIME
-- seconds; let go and what was done drains away again. Working one sets
-- off an alarm every ALARM_EVERY: the quest's `alarm` (given to
-- `serverOpen`) brings whoever is within ALARM_HEARD, so the others had
-- better cover whoever is at it. Done is done, for everyone, until the
-- level is played again; every feature hears of it (`serverTerminalDone`).
--
-- A lock may have no terminals at all: the quest opens it itself
-- (`Terminals.serverUnlock(server, name)`) when its own goal is met.
--
-- The quest's side: `Terminals.serverOpen(map, nav, alarm)` when its level
-- starts (`nav` its walking grid, refreshed as walls come down; `alarm(server,
-- x, y, radius)`), `Terminals.serverClose()` when it ends, and
-- `Terminals.serverLocked()` before it lets anyone through the way on.
-- Drawing and the HUD go by the map alone.
--
-- The map's side (city-map/eternal_mood.lua, city-map/borderline.lua):
--   map.terminals  { x, y, look = "terminal" | "seal" | "hyperbole", lock = name, warn = text | nil, dock = key | nil }
--   map.locks      { name, label, exit = true | nil, walls = { solid, look = "blast" | "roadgate" | "bone" } }
-- `warn` is who hears the alarm, on the HUD ("the horde" when not given).
--
-- Messages
--   client -> server  TRM_WORK <terminal>         (I am holding the key at it; every WORK_EVERY)
--   server -> all     TRM_PROG <terminal> <0..1>  (how far it is, while worked or draining)
--   server -> all     TRM_DONE <terminal>         (done; to a joiner, every done one)
--   server -> all     TRM_OPEN <lock>             (its walls came down, it lets go; to a joiner, every open one)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")

local Terminals = {
  name = "terminals",
  priority = 27, -- with the quest lines' props, over the map canvas (20)
}

-- Tuning ------------------------------------------------------------------
Terminals.WORK_TIME = 3 -- seconds of holding the key at one to do it
Terminals.DRAIN = 0.5 -- of the whole a second it loses while nobody holds it
Terminals.REACH = 60 -- px from it that counts as at it
Terminals.ALARM_EVERY = 6 -- seconds between alarms while somebody keeps at one
Terminals.ALARM_HEARD = 700 -- px: whoever is this near comes

local WORK_EVERY = 0.2 -- seconds between a holder's TRM_WORK
local WORK_GRACE = 0.45 -- seconds without one before the host takes it they let go
local SLACK = 40 -- px the host allows for a worker drawn a little off
local OPEN_FOR = 1.2 -- seconds a wall takes to come down
local NEWS_FOR = 4 -- seconds the news of a lock opening stays up

local RED = { 1.00, 0.22, 0.12 }
local GREEN = { 0.43, 1, 0.6 }
local FIRE = { 1.00, 0.55, 0.15 }
local STEEL = { 0.36, 0.38, 0.42 }
local DARK = { 0.12, 0.13, 0.15 }
local HAZARD = { 0.92, 0.78, 0.18 }
local YELLOW = { 0.95, 0.76, 0.19 }
local BONE = { 0.86, 0.80, 0.66 }

local function cityMap()
  local c = Features.byName["city-map"]
  return c and c.map
end

local function terminalsOf(map)
  return map and map.terminals or {}
end

local function locksOf(map)
  return map and map.locks or {}
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- Lock `name` of `map`, and its index.
local function lockNamed(map, name)
  for i, l in ipairs(locksOf(map)) do
    if l.name == name then
      return l, i
    end
  end
  return nil
end

--- Take lock `l`'s walls out of `map` (its solids, `fixed` and its cells) and out of
--- `nav`, the horde's walking grid, when given: open.
local function unblock(map, l, nav)
  if l.open then
    return
  end
  l.open = true
  local CELL = Layout.CELL
  for _, s in ipairs(l.walls or {}) do
    for _, list in ipairs({ map.solids, map.fixed or {} }) do -- (a rebuild of the cells starts from `fixed`)
      for i = #list, 1, -1 do
        if list[i] == s then
          table.remove(list, i)
        end
      end
    end
    for c = math.floor(s.x / CELL), math.floor((s.x + s.w) / CELL) do
      for r = math.floor(s.y / CELL), math.floor((s.y + s.h) / CELL) do
        local list = map.cells and map.cells[c] and map.cells[c][r]
        for i = #(list or {}), 1, -1 do
          if list[i] == s then
            table.remove(list, i)
          end
        end
      end
    end
    if nav then
      nav:refresh(s.x, s.y, s.w, s.h)
    end
  end
end

-- Server --------------------------------------------------------------------

local sv = nil -- { nav, alarm, [terminal] = { progress, lastWork, alarmAt, sent, done } } while a map has terminals

local now = 0

function Terminals.serverOpen(map, nav, alarm)
  sv = nil
  if #terminalsOf(map) == 0 and #locksOf(map) == 0 then
    return
  end
  sv = { nav = nav, alarm = alarm }
  for i in ipairs(terminalsOf(map)) do
    sv[i] = { progress = 0, lastWork = -1, alarmAt = -1e9, sent = 0, done = false }
  end
end

function Terminals.serverClose()
  sv = nil
end

--- Does a lock that holds the way on still hold it?
function Terminals.serverLocked()
  if not sv then
    return false
  end
  for _, l in ipairs(locksOf(cityMap())) do
    if l.exit and not l.open then
      return true
    end
  end
  return false
end

function Terminals:serverStep(server, dt)
  now = now + dt
  local map = cityMap()
  if not (sv and map) then
    return
  end
  for i in ipairs(terminalsOf(map)) do
    local st = sv[i]
    if st and not st.done then
      if now - st.lastWork > WORK_GRACE then
        st.progress = math.max(0, st.progress - Terminals.DRAIN * dt)
      end
      if math.abs(st.progress - st.sent) > 0.04 or (st.progress == 0 and st.sent > 0) then
        st.sent = st.progress
        server:broadcast(Protocol.encode("TRM_PROG", i, ("%.2f"):format(st.progress)))
      end
    end
  end
end

--- A joiner sees what is done and what is open.
function Terminals:serverPlayerJoined(server, player)
  if not sv or player.bot then
    return
  end
  local map = cityMap()
  for i in ipairs(terminalsOf(map)) do
    if sv[i] and sv[i].done then
      server:send(player, Protocol.encode("TRM_DONE", i))
    end
  end
  for i, l in ipairs(locksOf(map)) do
    if l.open then
      server:send(player, Protocol.encode("TRM_OPEN", i))
    end
  end
end

--- Open lock `name` of the map in play by something other than its
--- terminals (a quest's own goal: Prosperity's screens shot down, the
--- borderline feature): its walls come down for everyone, as when its last
--- terminal is done.
function Terminals.serverUnlock(server, name)
  local map = cityMap()
  local l, li = lockNamed(map, name)
  if not (sv and l) or l.open then
    return
  end
  unblock(map, l, sv.nav)
  server:broadcast(Protocol.encode("TRM_OPEN", li))
end

--- Terminal `i` done by `player`: and its lock, if that was the last of it.
local function finish(server, map, i, player)
  local t = terminalsOf(map)[i]
  sv[i].done, sv[i].progress = true, 1
  server:broadcast(Protocol.encode("TRM_DONE", i))
  Features.call("serverTerminalDone", server, t, player)
  local l, li = lockNamed(map, t.lock)
  if not l or l.open then
    return
  end
  for j, o in ipairs(terminalsOf(map)) do
    if o.lock == t.lock and not (sv[j] and sv[j].done) then
      return
    end
  end
  unblock(map, l, sv.nav)
  server:broadcast(Protocol.encode("TRM_OPEN", li))
end

Terminals.serverMessages = {
  TRM_WORK = function(server, player, args)
    local i = tonumber(args[1])
    local map = cityMap()
    local t = map and i and terminalsOf(map)[i]
    local st = sv and i and sv[i]
    if not (t and st) or st.done or player.vehicle or not Features.present(player)
      or Features.any("serverHeld", server, player) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, t.x, t.y) > (Terminals.REACH + SLACK) ^ 2 then
      return
    end
    -- Count the time since the last word, but never more than a word's worth (no saving up).
    local dt = st.lastWork >= 0 and math.min(now - st.lastWork, WORK_EVERY * 1.5) or WORK_EVERY
    st.lastWork = now
    st.progress = math.min(1, st.progress + dt / Terminals.WORK_TIME)
    if now - st.alarmAt >= Terminals.ALARM_EVERY then
      st.alarmAt = now -- it squeals: whoever is near it comes running
      if sv.alarm then
        sv.alarm(server, t.x, t.y, Terminals.ALARM_HEARD)
      end
    end
    if st.progress >= 1 then
      finish(server, map, i, player)
    end
  end,
}

--- For tests.
function Terminals.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- [terminal] = { progress, doneT }
local opened = {} -- [lock] = seconds since its walls started coming down
local news = nil -- { text, t } a lock opening
local near = nil -- the terminal I am at, on foot
local sendIn = 0
local clock = 0
local bank = {}

--- A sound `seconds` long, `build(buf)` writing it, at `volume`, heard from
--- `from` to `far` px off.
local function sound(seconds, volume, build, from, far)
  local buf = Synth.newBuffer(seconds)
  build(buf)
  local src = love.audio.newSource(buf:toSoundData(volume), "static")
  src:setAttenuationDistances(from, far)
  return src
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setVolume(0.8 * Audio.volume("weapons"))
    s:play()
  end
end

function Terminals:load()
  bank.done = sound(0.5, 0.6, function(buf) -- a terminal done: two bright beeps
    buf:tone(0, 0.12, 1320, { wave = "square", amp = 0.18, decay = 0.1, sustain = 0 })
    buf:tone(0.14, 0.2, 1760, { wave = "square", amp = 0.18, decay = 0.18, sustain = 0 })
  end, 200, 1600)
  bank.open = sound(1.4, 0.9, function(buf) -- a wall coming down: a groan and a slam
    buf:sweep(0, 1.1, 90, 40, { wave = "saw", amp = 0.4, attack = 0.05, decay = 1 })
    buf:noiseBurst(0, 1.2, { amp = 0.3, decay = 0.9 })
    buf:kick(1.1, 1)
    buf:lowpass(1400)
  end, 400, 3200)
end

local function clear()
  shown, opened, news, near = {}, {}, nil, nil
end

--- A map change of any kind ends a level: the host's terminals go with it.
function Terminals:mapChanged(_map, server)
  if server then
    sv = nil
  end
  clear()
end

function Terminals:exitGame()
  clear()
end

--- A level starting afresh (the same map played again) starts its terminals afresh.
function Terminals:questStarted()
  clear()
end

local function state(i)
  shown[i] = shown[i] or { progress = 0, doneT = nil }
  return shown[i]
end

function Terminals:update(dt, client)
  clock = clock + dt
  if not client then
    return
  end
  near = nil
  local map = cityMap()
  local x, y = client:myPose()
  for i, t in ipairs(terminalsOf(map)) do
    local st = state(i)
    if st.doneT then
      st.doneT = st.doneT + dt
    elseif x and not client:myVehicle() and dist2(x, y, t.x, t.y) <= Terminals.REACH ^ 2 then
      near = i
    end
  end
  for i, t in pairs(opened) do
    opened[i] = t + dt
  end
  if news then
    news.t = news.t + dt
    if news.t > NEWS_FOR then
      news = nil
    end
  end
  sendIn = sendIn - dt
  if near and Controls.isDown("enter-exit") and sendIn <= 0 then
    sendIn = WORK_EVERY
    client:send(Protocol.encode("TRM_WORK", near))
  end
end

--- The `actionTaken` convention: at a terminal the action key works it.
function Terminals:actionTaken()
  return near ~= nil
end

--- On this screen: every terminal not done yet whose lock holds the way
--- on (empty once the way on is open, or on a map without any).
function Terminals.waiting()
  local map = cityMap()
  local list = {}
  for i, t in ipairs(terminalsOf(map)) do
    local l = lockNamed(map, t.lock)
    if l and l.exit and not l.open and not state(i).doneT then
      list[#list + 1] = t
    end
  end
  return list
end

--- On this screen: the nearest of those to (x, y), and how many are left
--- (0 and nil once the way on is open, or on a map without any).
function Terminals.nearestWaiting(x, y)
  local list = Terminals.waiting()
  local best, bestD2 = nil, math.huge
  for _, t in ipairs(list) do
    local d2 = x and dist2(x, y, t.x, t.y) or 0
    if d2 < bestD2 then
      best, bestD2 = t, d2
    end
  end
  return #list, best
end

--- How far through its slow glow a waiting terminal is: 0 (dim) to 1 (bright).
local function pulse()
  return 0.5 - 0.5 * math.cos(clock * 2 * math.pi / 2.5)
end

--- A UAC terminal: a console on a pillar, its screen red until it is done,
--- then green; a waiting one glows slowly in and out round its foot.
local function drawTerminal(t, st)
  local done = st.doneT ~= nil
  if not done then
    local k = pulse()
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.08 + 0.2 * k)
    love.graphics.circle("fill", t.x, t.y, 22 + 16 * k, 32)
  end
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", t.x - 11, t.y - 9, 26, 24, 3)
  love.graphics.setColor(DARK)
  love.graphics.rectangle("fill", t.x - 14, t.y - 13, 28, 26, 3)
  love.graphics.setColor(STEEL)
  love.graphics.rectangle("line", t.x - 14, t.y - 13, 28, 26, 3)
  love.graphics.setColor(done and GREEN or RED)
  love.graphics.rectangle("fill", t.x - 10, t.y - 9, 20, 11, 2)
  love.graphics.setColor(0, 0, 0, 0.5)
  for k = 0, 2 do -- lines of text on the screen
    love.graphics.rectangle("fill", t.x - 8, t.y - 7 + k * 3, 6 + ((k * 5 + math.floor(clock * 3)) % 9), 1)
  end
  love.graphics.setColor(HAZARD) -- the keys
  love.graphics.rectangle("fill", t.x - 9, t.y + 5, 18, 4)
end

--- A Hyperbole terminal (Borderline): a yellow console with a hard black
--- outline, its screen red until it is done, then green, the H in its
--- hexagon on the casing, hazard stripes along its foot.
local function drawHyperbole(t, st)
  local done = st.doneT ~= nil
  local x, y = t.x, t.y
  if not done then
    local k = pulse()
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.08 + 0.2 * k)
    love.graphics.circle("fill", x, y, 26 + 16 * k, 32)
  end
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", x - 12, y - 10, 32, 30, 3)
  love.graphics.setColor(0.06, 0.06, 0.07)
  love.graphics.rectangle("fill", x - 18, y - 18, 36, 34, 5)
  love.graphics.setColor(YELLOW)
  love.graphics.rectangle("fill", x - 16, y - 16, 32, 30, 4)
  love.graphics.setColor(DARK)
  love.graphics.rectangle("fill", x - 12, y - 13, 24, 13, 2)
  love.graphics.setColor(done and GREEN or RED)
  love.graphics.rectangle("fill", x - 10, y - 11, 20, 9, 1)
  love.graphics.setColor(0, 0, 0, 0.5)
  for k = 0, 1 do -- lines of text on the screen
    love.graphics.rectangle("fill", x - 8, y - 9 + k * 3, 6 + ((k * 5 + math.floor(clock * 3)) % 9), 1)
  end
  -- The H in its hexagon.
  local hx, hy = x - 8, y + 6
  local hex = {}
  for k = 0, 5 do
    local a = k * math.pi / 3
    hex[#hex + 1] = hx + math.cos(a) * 5
    hex[#hex + 1] = hy + math.sin(a) * 5
  end
  love.graphics.setColor(0.06, 0.06, 0.07)
  love.graphics.polygon("fill", hex)
  love.graphics.setColor(YELLOW)
  love.graphics.rectangle("fill", hx - 2.5, hy - 2.5, 1.2, 5)
  love.graphics.rectangle("fill", hx + 1.3, hy - 2.5, 1.2, 5)
  love.graphics.rectangle("fill", hx - 2.5, hy - 0.5, 5, 1)
  love.graphics.setColor(DARK) -- the keys
  love.graphics.rectangle("fill", x - 1, y + 3, 13, 6, 1)
  love.graphics.setColor(0.06, 0.06, 0.07) -- hazard stripes along its foot
  for k = 0, 3 do
    love.graphics.polygon("fill", x - 16 + k * 8, y + 14, x - 12 + k * 8, y + 14, x - 8 + k * 8, y + 10,
      x - 12 + k * 8, y + 10)
  end
end

--- A seal of Heck's: a ring of bone round a skull on a stake, dark until it
--- is lit, then burning.
local function drawSeal(t, st)
  local done = st.doneT ~= nil
  local k = pulse()
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", t.x + 4, t.y + 4, 26, 24)
  love.graphics.setColor(BONE)
  love.graphics.setLineWidth(5)
  love.graphics.circle("line", t.x, t.y, 24, 24)
  love.graphics.setLineWidth(1)
  for a = 0, 5 do -- knuckles of bone round it
    local ang = a / 6 * 2 * math.pi + 0.3
    love.graphics.circle("fill", t.x + math.cos(ang) * 24, t.y + math.sin(ang) * 24, 4, 8)
  end
  local c = done and FIRE or RED
  love.graphics.setColor(c[1], c[2], c[3], done and 0.8 or 0.25 + 0.3 * k)
  love.graphics.circle("fill", t.x, t.y, 16, 20)
  love.graphics.setColor(BONE)
  love.graphics.circle("fill", t.x, t.y, 6, 10)
  love.graphics.setColor(0.1, 0.05, 0.04)
  love.graphics.circle("fill", t.x - 2, t.y - 1, 1.3, 5)
  love.graphics.circle("fill", t.x + 2, t.y - 1, 1.3, 5)
  if done then -- burning
    love.graphics.setBlendMode("add")
    for j = 0, 2 do
      local f = 0.7 + 0.3 * math.sin(clock * (11 + j * 3) + j)
      love.graphics.setColor(1, 0.5 + j * 0.15, 0.1, 0.4 * f)
      love.graphics.circle("fill", t.x, t.y - j * 3, 14 * f - j * 3, 12)
    end
    love.graphics.setBlendMode("alpha")
  end
end

--- A lock's wall, shut or coming down: a UAC blast door (steel, hazard
--- stripes, a red lock light) sliding into the wall, a roadblock across the
--- road doing the same, or a wall of Heck's bone crumbling.
local function drawWall(s, t)
  local k = t and math.min(1, t / OPEN_FOR) or 0
  if k >= 1 then
    return
  end
  local across = s.w >= s.h
  if s.look == "bone" then -- heaped bones and skulls, settling and falling apart as it opens
    local h = s.h * (1 - k)
    local y0 = s.y + s.h - h
    love.graphics.setColor(0, 0, 0, 0.45)
    love.graphics.rectangle("fill", s.x + 6, y0 + 10, s.w, h)
    love.graphics.setColor(0.24, 0.08, 0.06)
    love.graphics.rectangle("fill", s.x, y0, s.w, h, 6)
    for x = s.x + 4, s.x + s.w - 16, 18 do -- long bones heaped every which way
      for row = 0, 2 do
        local y = y0 + 8 + row * (h - 14) / 3
        if y < s.y + s.h - 8 then
          local tilt = ((x / 18 + row) % 3 - 1) * 5
          love.graphics.setColor(BONE[1] * (0.8 + row * 0.1), BONE[2] * (0.8 + row * 0.1), BONE[3] * (0.8 + row * 0.1))
          love.graphics.setLineWidth(5)
          love.graphics.line(x, y - tilt, x + 16, y + tilt)
          love.graphics.circle("fill", x, y - tilt, 3.5, 6)
          love.graphics.circle("fill", x + 16, y + tilt, 3.5, 6)
        end
      end
    end
    love.graphics.setLineWidth(1)
    for x = s.x + 30, s.x + s.w - 30, 74 do -- skulls set into it
      local y = y0 + h * 0.45
      love.graphics.setColor(BONE)
      love.graphics.circle("fill", x, y, 9, 12)
      love.graphics.rectangle("fill", x - 5, y + 5, 10, 6, 2)
      love.graphics.setColor(RED[1], RED[2], RED[3], 0.6 + 0.4 * math.sin(clock * 3 + x)) -- Heck looking out of it
      love.graphics.circle("fill", x - 3.5, y - 1, 2.2, 6)
      love.graphics.circle("fill", x + 3.5, y - 1, 2.2, 6)
    end
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.5 + 0.3 * math.sin(clock * 3)) -- glowing at its foot
    love.graphics.rectangle("fill", s.x, s.y + s.h - 4, s.w, 4)
    return
  end
  -- A shutter: steel, hazard stripes at its leading edge, the lock light.
  local len = (across and s.w or s.h) * (1 - k)
  local x, y, w, h = s.x, s.y, across and len or s.w, across and s.h or len
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", x + 6, y + 8, w, h)
  love.graphics.setColor(STEEL)
  love.graphics.rectangle("fill", x, y, w, h)
  love.graphics.setColor(DARK)
  if across then
    for sx = x + 24, x + w - 8, 24 do
      love.graphics.rectangle("fill", sx, y + 3, 2, h - 6)
    end
  else
    for sy = y + 24, y + h - 8, 24 do
      love.graphics.rectangle("fill", x + 3, sy, w - 6, 2)
    end
  end
  love.graphics.setColor(HAZARD)
  if across then
    love.graphics.rectangle("fill", x + w - 16, y, 16, h)
  else
    love.graphics.rectangle("fill", x, y + h - 16, w, 16)
  end
  love.graphics.setColor(0, 0, 0)
  love.graphics.rectangle("line", x, y, w, h)
  local on = math.floor(clock * 2) % 2 == 0
  love.graphics.setColor(on and RED or DARK)
  love.graphics.circle("fill", x + w / 2, y + h / 2, 5, 10)
end

function Terminals:drawBelowCars()
  local map = cityMap()
  for i, l in ipairs(locksOf(map)) do
    if not (l.open and not opened[i]) then -- (open before we heard: nothing left to draw)
      for _, s in ipairs(l.walls or {}) do
        drawWall(s, opened[i])
      end
    end
  end
  for i, t in ipairs(terminalsOf(map)) do
    local st = state(i)
    if t.look == "seal" then
      drawSeal(t, st)
    elseif t.look == "hyperbole" then
      drawHyperbole(t, st)
    else
      drawTerminal(t, st)
    end
    if not st.doneT and st.progress > 0 then
      UI.ring(t.x, t.y - 32, 10, st.progress, t.look == "seal" and FIRE or RED, 3)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Terminals:drawNightLights(_client, _camera, glow)
  local map = cityMap()
  for i, t in ipairs(terminalsOf(map)) do
    local done = state(i).doneT ~= nil
    if t.look == "seal" then
      glow(t.x, t.y, done and 160 or 60 + 40 * pulse(), done and FIRE or RED, done and 0.8 or 0.4)
    else
      glow(t.x, t.y, done and 70 or 80 + 70 * pulse(), done and GREEN or RED, done and 0.6 or 0.4 + 0.4 * pulse())
    end
  end
  for i, l in ipairs(locksOf(map)) do
    if not opened[i] then
      for _, s in ipairs(l.walls or {}) do
        glow(s.x + s.w / 2, s.y + s.h / 2, math.max(s.w, s.h) * 0.35, l.walls[1].look == "bone" and FIRE or RED, 0.3)
      end
    end
  end
end

--- The terminals on the minimap: red until done, then green (Heck's seals
--- orange once lit).
function Terminals:drawOnMinimap(_client, toMap)
  for i, t in ipairs(terminalsOf(cityMap())) do
    local x, y = toMap(t.x, t.y)
    local done = state(i).doneT ~= nil
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - 4, y - 4, 8, 8)
    local c = done and (t.look == "seal" and FIRE or GREEN) or RED
    love.graphics.setColor(c)
    love.graphics.rectangle("fill", x - 3, y - 3, 6, 6)
  end
  love.graphics.setColor(1, 1, 1)
end

--- How far each lock still to open is, down the left (the free row); what
--- to do at the terminal you are at; the news of a lock opening.
function Terminals:drawHUD()
  local map = cityMap()
  local locks = locksOf(map)
  if #locks == 0 then
    return
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  local y = 118
  for _, l in ipairs(locks) do
    if not l.open then
      local done, of = 0, 0
      for i, t in ipairs(terminalsOf(map)) do
        if t.lock == l.name then
          of = of + 1
          if state(i).doneT then
            done = done + 1
          end
        end
      end
      if of > 0 then -- (a lock with none is opened some other way, which says so itself)
        local seal = terminalsOf(map)[1] and terminalsOf(map)[1].look == "seal"
        local text = ("%s: %d/%d %s"):format(l.label, done, of, seal and "seals lit" or "terminals")
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.print(text, 13, y + 1)
        love.graphics.setColor(RED)
        love.graphics.print(text, 12, y)
        y = y + 18
      end
    end
  end
  if near then
    local key = Controls.name(Controls.bindings("enter-exit")[1])
    local t = terminalsOf(map)[near]
    local p = state(near).progress
    local verb = t.look == "seal" and "light the seal" or "hack the terminal"
    local text = p > 0 and ("%s... %d%%"):format(t.look == "seal" and "Lighting" or "Hacking", math.floor(p * 100))
      or ("Hold " .. key .. ": " .. verb .. " (" .. (t.warn or "the horde") .. " will hear)")
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf(text, 1, h - 129, w, "center")
    love.graphics.setColor(RED)
    love.graphics.printf(text, 0, h - 130, w, "center")
  end
  if news then
    local a = math.min(1, news.t * 3, (NEWS_FOR - news.t) / 0.6)
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.7 * a)
    love.graphics.printf(news.text, 2, h * 0.3 + 2, w, "center")
    love.graphics.setColor(GREEN[1], GREEN[2], GREEN[3], a)
    love.graphics.printf(news.text, 0, h * 0.3, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Terminals.clientMessages = {
  TRM_PROG = function(_client, args)
    local i, p = tonumber(args[1]), tonumber(args[2])
    if i and p then
      state(i).progress = p
    end
  end,
  TRM_DONE = function(_client, args)
    local i = tonumber(args[1])
    local t = i and terminalsOf(cityMap())[i]
    if t then
      local st = state(i)
      if not st.doneT then
        st.doneT, st.progress = 0, 1
        play("done", t.x, t.y)
      end
    end
  end,
  TRM_OPEN = function(_client, args)
    local i = tonumber(args[1])
    local map = cityMap()
    local l = map and i and locksOf(map)[i]
    if l and not opened[i] then
      unblock(map, l) -- (the host's client shares the host's map: already open, and unblock knows)
      opened[i] = 0
      local s = l.walls and l.walls[1]
      if s then
        play("open", s.x + s.w / 2, s.y + s.h / 2)
      end
      news = { text = l.label .. " OPEN", t = 0 }
    end
  end,
}

return Terminals
