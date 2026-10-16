-- The terminals that open the way on (docs/eternal-mood.md, "Terminals"):
-- every level hides a few off the straight way through, and you have to go
-- and find them. Each belongs to a lock (the map's `locks`, its terminals
-- the map's `terminals` naming it); once all of a lock's terminals are
-- done the lock opens: its walls come down (solids across a doorway or the
-- road, built into the map like any wall: nothing gets past them, not a
-- person, not a round), and a lock that holds the level's way on (`exit`)
-- lets it go (`serverLocked`, as a boss does). Heck's are seals, not
-- terminals (`look`), lit the same way.
--
-- To do one, stand at it and hold the action key (F) for WORK_TIME
-- seconds; let go and what was done drains away again. Working one sets
-- off an alarm every ALARM_EVERY: every mob and every one of the possessed
-- within ALARM_HEARD comes (horde.lua's `serverScream`), so the others had
-- better cover whoever is at it. Done is done, for everyone, until the
-- level is played again.
--
-- The map's side (city-map/eternal_mood.lua):
--   map.terminals  { x, y, look = "terminal" | "seal", lock = name }
--   map.locks      { name, label, exit = true | nil, walls = { solid, look = "blast" | "roadgate" | "bone" } }
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
local Horde = require("src.features.eternal-mood.horde")
local Onscreen = require("src.features.eternal-mood.onscreen")

local Terminals = {}

-- Tuning ------------------------------------------------------------------
Terminals.WORK_TIME = 3 -- seconds of holding the key at one to do it
Terminals.DRAIN = 0.5 -- of the whole a second it loses while nobody holds it
Terminals.REACH = 60 -- px from it that counts as at it
Terminals.ALARM_EVERY = 6 -- seconds between alarms while somebody keeps at one
Terminals.ALARM_HEARD = 700 -- px: the horde this near comes

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

local sv = nil -- { nav, [terminal] = { progress, lastWork, alarmAt, sent, done } } while a map has terminals

local now = 0

function Terminals.serverStart(_server, map, nav)
  sv = nil
  if #terminalsOf(map) == 0 then
    return
  end
  sv = { nav = nav }
  for i in ipairs(terminalsOf(map)) do
    sv[i] = { progress = 0, lastWork = -1, alarmAt = -1e9, sent = 0, done = false }
  end
end

function Terminals.serverStop()
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

function Terminals.serverStep(server, dt)
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
function Terminals.serverPlayerJoined(server, player)
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

--- Terminal `i` done: and its lock, if that was the last of it.
local function finish(server, map, i)
  local t = terminalsOf(map)[i]
  sv[i].done, sv[i].progress = true, 1
  server:broadcast(Protocol.encode("TRM_DONE", i))
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
      st.alarmAt = now -- it squeals: the horde near it comes running
      Horde.serverScream(server, t.x, t.y, Terminals.ALARM_HEARD, t.x, t.y)
    end
    if st.progress >= 1 then
      finish(server, map, i)
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

function Terminals.load()
  bank.done = Onscreen.sound(0.5, 0.6, function(buf) -- a terminal done: two bright beeps
    buf:tone(0, 0.12, 1320, { wave = "square", amp = 0.18, decay = 0.1, sustain = 0 })
    buf:tone(0.14, 0.2, 1760, { wave = "square", amp = 0.18, decay = 0.18, sustain = 0 })
  end, 200, 1600)
  bank.open = Onscreen.sound(1.4, 0.9, function(buf) -- a wall coming down: a groan and a slam
    buf:sweep(0, 1.1, 90, 40, { wave = "saw", amp = 0.4, attack = 0.05, decay = 1 })
    buf:noiseBurst(0, 1.2, { amp = 0.3, decay = 0.9 })
    buf:kick(1.1, 1)
    buf:lowpass(1400)
  end, 400, 3200)
end

function Terminals.clear()
  shown, opened, news, near = {}, {}, nil, nil
end

local function state(i)
  shown[i] = shown[i] or { progress = 0, doneT = nil }
  return shown[i]
end

function Terminals.update(dt, client)
  clock = clock + dt
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
function Terminals.actionTaken()
  return near ~= nil
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
  if s.look == "bone" then
    local h = s.h * (1 - k)
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", s.x + 6, s.y + 8, s.w, h)
    love.graphics.setColor(0.30, 0.10, 0.07)
    love.graphics.rectangle("fill", s.x, s.y, s.w, h)
    love.graphics.setColor(BONE)
    for x = s.x + 6, s.x + s.w - 10, 14 do -- ribs and long bones, stacked
      for y = s.y + 4, s.y + h - 8, 12 do
        local tilt = ((x + y) / 14) % 2 < 1 and 3 or -3
        love.graphics.setLineWidth(4)
        love.graphics.line(x, y + 4 - tilt, x + 10, y + 4 + tilt)
      end
    end
    love.graphics.setLineWidth(1)
    love.graphics.setColor(RED[1], RED[2], RED[3], 0.6 + 0.3 * math.sin(clock * 3)) -- Heck glowing through it
    love.graphics.rectangle("fill", s.x, s.y + h - 4, s.w, 4)
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

function Terminals.drawBelowCars()
  local map = cityMap()
  for i, l in ipairs(locksOf(map)) do
    for _, s in ipairs(l.walls or {}) do
      drawWall(s, opened[i])
    end
  end
  for i, t in ipairs(terminalsOf(map)) do
    local st = state(i)
    if t.look == "seal" then
      drawSeal(t, st)
    else
      drawTerminal(t, st)
    end
    if not st.doneT and st.progress > 0 then
      UI.ring(t.x, t.y - 32, 10, st.progress, t.look == "seal" and FIRE or RED, 3)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Terminals.drawNightLights(glow)
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
function Terminals.drawOnMinimap(toMap)
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
function Terminals.drawHUD()
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
      local seal = terminalsOf(map)[1] and terminalsOf(map)[1].look == "seal"
      local text = ("%s: %d/%d %s"):format(l.label, done, of, seal and "seals lit" or "terminals")
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.print(text, 13, y + 1)
      love.graphics.setColor(RED)
      love.graphics.print(text, 12, y)
      y = y + 18
    end
  end
  if near then
    local key = Controls.name(Controls.bindings("enter-exit")[1])
    local t = terminalsOf(map)[near]
    local p = state(near).progress
    local verb = t.look == "seal" and "light the seal" or "hack the terminal"
    local text = p > 0 and ("%s... %d%%"):format(t.look == "seal" and "Lighting" or "Hacking", math.floor(p * 100))
      or ("Hold " .. key .. ": " .. verb .. " (the horde will hear)")
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
        Onscreen.play(bank, "done", t.x, t.y)
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
        Onscreen.play(bank, "open", s.x + s.w / 2, s.y + s.h / 2)
      end
      news = { text = l.label .. " OPEN", t = 0 }
    end
  end,
}

return Terminals
