-- Halcyon's roadblocks on the Overpass (docs/cyber-feud.md, "The
-- Overpass"): blast gates right across the road (the map's `gates`) that
-- nothing gets past while they are shut: not a car, not anyone on foot,
-- not a round. To open one, somebody has to get out of their car, stand at
-- the control panel on the shoulder short of it and hold the action key
-- (F) for `workTime` seconds; let go and what they had done drains away
-- again. Working a panel sets off an alarm: Halcyon's officers near the
-- gate come for whoever is at it, so the others had better cover them.
-- Once open, a gate stays open for everyone until the level is played
-- again (the map is built anew).
--
-- A gate is a solid in the map like any wall (the map's `solids` and its
-- `cells`, which city-map's collision reads), on the host and on every
-- screen; opening one takes it out of both, so a car's own prediction
-- drives through it as the host does.
--
-- Messages
--   client -> server  GATE_WORK <gate>             (I am holding the key at its panel; every WORK_EVERY)
--   server -> all     GATE_PROG <gate> <progress>  (how far it is: 0..1, while somebody works at it or it drains)
--   server -> all     GATE_OPEN <gate>             (it opened; to a joiner, every open one)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Layout = require("src.features.city-map.layout")

local Gates = {}

-- Tuning ------------------------------------------------------------------
Gates.workTime = 3 -- seconds of holding the key at a panel to open its gate
Gates.drain = 0.5 -- of the whole a second it loses again while nobody works it
Gates.reach = 70 -- px from a panel's middle that counts as at it
Gates.alarmHeard = 900 -- px; Halcyon's officers this near the panel come
Gates.alarmEvery = 6 -- seconds between alarms while somebody keeps at it

local WORK_EVERY = 0.2 -- seconds between a holder's GATE_WORK
local WORK_GRACE = 0.45 -- seconds without one before the host takes it they let go
local SLACK = 40 -- px the host allows for a worker drawn a little off

local MAGENTA = { 1.00, 0.24, 0.78 }
local STEEL = { 0.36, 0.38, 0.42 }
local DARK = { 0.12, 0.13, 0.15 }
local HAZARD = { 0.92, 0.78, 0.18 }

local function cityMap()
  local c = Features.byName["city-map"]
  return c and c.map
end

local function gatesOf(map)
  return map and map.gates or {}
end

--- Take gate `g`'s solid out of `map` (its `solids` and its `cells`): open.
local function unblock(map, g)
  local s = g.solid
  if not s or g.open then
    return
  end
  g.open = true
  for i = #map.solids, 1, -1 do
    if map.solids[i] == s then
      table.remove(map.solids, i)
    end
  end
  local CELL = Layout.CELL
  for c = math.floor(s.x / CELL), math.floor((s.x + s.w) / CELL) do
    for r = math.floor(s.y / CELL), math.floor((s.y + s.h) / CELL) do
      local list = map.cells[c] and map.cells[c][r]
      for i = #(list or {}), 1, -1 do
        if list[i] == s then
          table.remove(list, i)
        end
      end
    end
  end
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server --------------------------------------------------------------------

local sv = nil -- { [gate] = { progress, lastWork, alarmAt, sent } } while a map with gates is up

function Gates.serverStart()
  sv = {}
  for i in ipairs(gatesOf(cityMap())) do
    sv[i] = { progress = 0, lastWork = -1, alarmAt = -1e9, sent = 0 }
  end
end

function Gates.serverStop()
  sv = nil
end

local now = 0

function Gates.serverStep(server, dt)
  now = now + dt
  local map = cityMap()
  if not (sv and map) then
    return
  end
  for i, g in ipairs(gatesOf(map)) do
    local st = sv[i]
    if st and not g.open then
      if now - st.lastWork > WORK_GRACE then
        st.progress = math.max(0, st.progress - Gates.drain * dt)
      end
      if math.abs(st.progress - st.sent) > 0.04 or (st.progress == 0 and st.sent > 0) then
        st.sent = st.progress
        server:broadcast(Protocol.encode("GATE_PROG", i, ("%.2f"):format(st.progress)))
      end
    end
  end
end

--- A player joining after a gate opened sees it open.
function Gates.serverPlayerJoined(server, player)
  for i, g in ipairs(gatesOf(cityMap())) do
    if g.open and not player.bot then
      server:send(player, Protocol.encode("GATE_OPEN", i))
    end
  end
end

Gates.serverMessages = {
  GATE_WORK = function(server, player, args)
    local i = tonumber(args[1])
    local map = cityMap()
    local g = map and i and gatesOf(map)[i]
    local st = sv and i and sv[i]
    if not (g and st) or g.open or player.vehicle or not Features.present(player)
      or Features.any("serverHeld", server, player) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, g.panel.x, g.panel.y) > (Gates.reach + SLACK) ^ 2 then
      return
    end
    -- Count the time since the last word, but never more than a word's worth (no saving up).
    local dt = st.lastWork >= 0 and math.min(now - st.lastWork, WORK_EVERY * 1.5) or WORK_EVERY
    st.lastWork = now
    st.progress = math.min(1, st.progress + dt / Gates.workTime)
    if now - st.alarmAt >= Gates.alarmEvery then
      st.alarmAt = now -- the panel squeals: Halcyon comes running
      local troops = require("src.features.cyber-feud.troops").server()
      local halcyon = troops and troops.sides.halcyon
      if halcyon then
        halcyon.troops:alarm(g.panel.x, g.panel.y, Gates.alarmHeard, { most = 4 })
      end
    end
    if st.progress >= 1 then
      unblock(map, g)
      server:broadcast(Protocol.encode("GATE_OPEN", i))
    end
  end,
}

-- Client --------------------------------------------------------------------

local shown = {} -- [gate] = { progress, openT }
local near = nil -- the gate whose panel I am at, on foot
local nearInCar = nil -- the gate whose panel I am at, still in my car
local sendIn = 0
local clock = 0

function Gates.clear()
  shown, near, nearInCar = {}, nil, nil
end

local function state(i)
  shown[i] = shown[i] or { progress = 0, openT = nil }
  return shown[i]
end

function Gates.update(dt, client)
  clock = clock + dt
  near, nearInCar = nil, nil
  local map = cityMap()
  local x, y = client:myPose()
  for i, g in ipairs(gatesOf(map)) do
    local st = state(i)
    if st.openT then
      st.openT = st.openT + dt
    elseif x and dist2(x, y, g.panel.x, g.panel.y) <= Gates.reach ^ 2 then
      if client:myVehicle() then
        nearInCar = i
      else
        near = i
      end
    end
  end
  sendIn = sendIn - dt
  if near and Controls.isDown("enter-exit") and sendIn <= 0 then
    sendIn = WORK_EVERY
    client:send(Protocol.encode("GATE_WORK", near))
  end
end

--- The `actionTaken` convention: at a panel on foot the action key works it,
--- so on-foot leaves the cars alone.
function Gates.actionTaken()
  return near ~= nil
end

--- A gate: posts either side, and the shutter across the road between them,
--- Halcyon's grey steel with a hazard stripe and its magenta lights; drawn
--- sliding back into the right-hand post as it opens.
local function drawGate(g, st)
  local s = g.frame
  local k = st.openT and math.min(1, st.openT / 1.2) or 0
  -- The shutter.
  if k < 1 then
    local w = (s.w - 40) * (1 - k)
    local x = s.x + 20 + (s.w - 40) - w
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", x + 4, s.y + 6, w, s.h)
    love.graphics.setColor(STEEL)
    love.graphics.rectangle("fill", x, s.y, w, s.h)
    love.graphics.setColor(HAZARD)
    for sx = x, x + w - 16, 32 do
      love.graphics.polygon("fill", sx, s.y + s.h, sx + 12, s.y, sx + 24, s.y, sx + 12, s.y + s.h)
    end
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.85)
    love.graphics.rectangle("fill", x, s.y + s.h / 2 - 1.5, w, 3)
  end
  -- The posts.
  for _, px in ipairs({ s.x, s.x + s.w - 20 }) do
    love.graphics.setColor(0, 0, 0, 0.4)
    love.graphics.rectangle("fill", px + 4, s.y - 8, 20, s.h + 16)
    love.graphics.setColor(DARK)
    love.graphics.rectangle("fill", px, s.y - 12, 20, s.h + 24, 3)
    local on = st.openT or math.floor(clock * 2) % 2 == 0
    love.graphics.setColor(st.openT and { 0.43, 1, 0.6 } or MAGENTA)
    if on then
      love.graphics.circle("fill", px + 10, s.y + s.h / 2, 4, 10)
    end
  end
end

--- The control panel: a pillar with a screen, and how far it has got.
local function drawPanel(g, st)
  local p = g.panel
  love.graphics.setColor(0, 0, 0, 0.4)
  love.graphics.rectangle("fill", p.x - 9, p.y - 9, 22, 22, 3)
  love.graphics.setColor(DARK)
  love.graphics.rectangle("fill", p.x - 11, p.y - 11, 22, 22, 3)
  local done = st.openT ~= nil
  love.graphics.setColor(done and { 0.43, 1, 0.6 } or MAGENTA)
  love.graphics.rectangle("fill", p.x - 7, p.y - 7, 14, 9, 2)
  if not done and st.progress > 0 then -- how far, round it (under the screen's glow, over its shadow)
    UI.ring(p.x, p.y - 30, 10, st.progress, MAGENTA, 3)
  end
end

function Gates.drawBelowCars()
  for i, g in ipairs(gatesOf(cityMap())) do
    local st = state(i)
    drawGate(g, st)
    drawPanel(g, st)
  end
  love.graphics.setColor(1, 1, 1)
end

function Gates.drawNightLights(glow)
  for i, g in ipairs(gatesOf(cityMap())) do
    local st = state(i)
    local color = st.openT and { 0.43, 1, 0.6 } or MAGENTA
    glow(g.panel.x, g.panel.y, 70, color, 0.7)
    if not st.openT then
      glow(g.frame.x + g.frame.w / 2, g.frame.y + g.frame.h / 2, g.frame.w * 0.4, MAGENTA, 0.35)
    end
  end
end

--- What to do here, over the ability row: get out, or hold the key.
function Gates.drawHUD()
  local i = near or nearInCar
  if not i then
    return
  end
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local text
  if nearInCar then
    text = "Halcyon roadblock.  " .. key .. ": get out to open the gate"
  else
    local p = state(i).progress
    text = p > 0 and ("Opening the gate... %d%%"):format(math.floor(p * 100))
      or ("Halcyon roadblock.  Hold " .. key .. ": open the gate")
  end
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(MAGENTA)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

Gates.clientMessages = {
  GATE_PROG = function(_client, args)
    local i, p = tonumber(args[1]), tonumber(args[2])
    if i and p then
      state(i).progress = p
    end
  end,
  GATE_OPEN = function(_client, args)
    local i = tonumber(args[1])
    local map = cityMap()
    local g = map and i and gatesOf(map)[i]
    if g then
      unblock(map, g) -- (the host's client shares the host's map: already open, and unblock knows)
      local st = state(i)
      st.openT, st.progress = st.openT or 0, 1
    end
  end,
}

return Gates
