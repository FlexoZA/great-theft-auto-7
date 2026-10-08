-- Respawn points: places along a long quest map (City 17, the Coast, the
-- Winding Road, the Citadel, Shotgun's Bluff) where a player who died can
-- come back, instead of at the way in. Each player finds them for
-- themselves by passing within `reach` of one (walking or driving); found
-- ones light up, on the ground and on the minimap. Where they stand is
-- placement.lua's business: a map's own list, its car stations, or points
-- worked out along the walk to the boss.
--
-- Dying on a map where you have found one puts a list up under WASTED: the
-- way in and every point found, the furthest along picked. Click one, or
-- press its number, or move with the arrows and confirm with Enter. The
-- host holds the respawn (weapons' `serverRespawnHeld`) until you choose,
-- or for `chooseTime` seconds at most, then brings you back there on foot
-- (weapons' `serverRespawnPoint`). On a driven map the points are its car
-- station pads, so a car is one key away. The finds are forgotten on every
-- trip to another map; the city has none (the garage looks after it).
--
-- Messages
--   client -> server  RSP_PICK   <index>     (where to come back: 0 the way in, else a point)
--   server -> player  RSP_FOUND  <index>     (you found that point)
--   server -> player  RSP_CHOOSE <seconds>   (dead: pick where to come back, within that long)
--   server -> player  RSP_DONE               (the choice is made, or ran out)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Placement = require("src.features.respawn-points.placement")

local Points = {
  name = "respawn-points",
}

-- Tuning ------------------------------------------------------------------
Points.reach = 180 -- px from a point that finds it
Points.chooseTime = 20 -- seconds the host waits for a dead player to choose
Points.noticeTime = 2.5 -- seconds "Respawn point found" stays up

-- The points on the map in play, in route order; the same on every machine.
local points = {}

local function cityMap()
  return Features.byName["city-map"]
end

--- Work the points out again for `map` (nil: the one in play).
local function place(map)
  local city = cityMap()
  map = map or (city and city.map)
  points = Placement.of(map, not city or city.current == city.DEFAULT)
end

-- Client --------------------------------------------------------------------

local found = {} -- [index] = true: the points I have found here
local choosing = nil -- { pick, left }: the list is up (pick 0 is the way in)
local notice = nil -- { text, t }

--- The list's rows: { index, name }, the way in first, then every point found.
local function rows()
  local list = { { index = 0, name = "Where you came in" } }
  for i, p in ipairs(points) do
    if found[i] then
      list[#list + 1] = { index = i, name = p.name }
    end
  end
  return list
end

local function resetClient()
  found, choosing, notice = {}, nil, nil
end

function Points:load()
  Controls.register("respawn-pick", "Come back at the picked respawn point (when dead)", "return")
end

function Points:enterGame()
  resetClient()
  place()
end

function Points:exitGame()
  resetClient()
  points = {}
end

--- The list's rectangles: a panel under WASTED, a row per choice.
local ROW_H, PANEL_W = 34, 380
local function layout(list)
  local w, h = love.graphics.getDimensions()
  local x = math.floor((w - PANEL_W) / 2)
  local y = math.floor(h / 2 + 10)
  local L = { panel = { x = x, y = y, w = PANEL_W, h = 52 + #list * ROW_H + 26 }, rows = {} }
  for i = 1, #list do
    L.rows[i] = { x = x + 12, y = y + 44 + (i - 1) * ROW_H, w = PANEL_W - 24, h = ROW_H - 4 }
  end
  return L
end

local function inside(r, x, y)
  return x >= r.x and x <= r.x + r.w and y >= r.y and y <= r.y + r.h
end

local function pick(client, index)
  client:send(Protocol.encode("RSP_PICK", index))
  choosing = nil
end

function Points:update(dt)
  if choosing then
    choosing.left = math.max(0, choosing.left - dt)
  end
  if notice then
    notice.t = notice.t - dt
    if notice.t <= 0 then
      notice = nil
    end
  end
end

--- Weapons keeps WASTED up while the list is (the `respawnHeld` convention).
function Points:respawnHeld()
  return choosing ~= nil
end

--- The mouse and the number keys are ours while the list is up.
function Points:pointerTaken()
  return choosing ~= nil
end

function Points:menuOpen()
  return choosing ~= nil
end

function Points:keypressed(key, client)
  if not choosing then
    return
  end
  local list = rows()
  local at = 1
  for i, r in ipairs(list) do
    if r.index == choosing.pick then
      at = i
    end
  end
  local n = tonumber(key)
  if n and list[n] then
    pick(client, list[n].index)
  elseif key == "up" or key == "w" then
    choosing.pick = list[math.max(1, at - 1)].index
  elseif key == "down" or key == "s" then
    choosing.pick = list[math.min(#list, at + 1)].index
  elseif Controls.is("respawn-pick", key) then
    pick(client, choosing.pick)
  end
end

function Points:mousepressed(x, y, button, client)
  if not choosing or button ~= 1 then
    return
  end
  local list = rows()
  for i, r in ipairs(layout(list).rows) do
    if inside(r, x, y) then
      pick(client, list[i].index)
      return
    end
  end
end

--- A point on the ground: a ring with a flag, grey until found, then green.
function Points:drawBelowCars()
  local t = love.timer.getTime()
  for i, p in ipairs(points) do
    local lit = found[i]
    if lit then
      love.graphics.setColor(0.35, 1, 0.55, 0.16 + 0.08 * math.sin(t * 3 + i))
      love.graphics.circle("fill", p.x, p.y, 34)
      love.graphics.setColor(0.35, 1, 0.55, 0.9)
    else
      love.graphics.setColor(0.75, 0.78, 0.8, 0.55)
    end
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", p.x, p.y, 34)
    love.graphics.setLineWidth(2)
    love.graphics.line(p.x, p.y + 8, p.x, p.y - 26) -- the pole
    love.graphics.polygon("fill", p.x, p.y - 26, p.x + 18, p.y - 20, p.x, p.y - 14) -- the flag
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- Found points on the minimap and the big map: small green diamonds.
function Points:drawOnMinimap(_client, toMap)
  for i, p in ipairs(points) do
    if found[i] then
      local x, y = toMap(p.x, p.y)
      love.graphics.setColor(0, 0, 0, 0.8)
      love.graphics.polygon("fill", x, y - 6, x + 6, y, x, y + 6, x - 6, y)
      love.graphics.setColor(0.35, 1, 0.55)
      love.graphics.polygon("fill", x, y - 4, x + 4, y, x, y + 4, x - 4, y)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Points:drawHUD()
  if not notice then
    return
  end
  local w = love.graphics.getWidth()
  love.graphics.setFont(UI.fonts.body)
  local a = math.min(1, notice.t * 2)
  love.graphics.setColor(0, 0, 0, 0.6 * a)
  love.graphics.printf(notice.text, 1, 79, w, "center")
  love.graphics.setColor(0.35, 1, 0.55, a)
  love.graphics.printf(notice.text, 0, 78, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The list goes over the whole HUD, WASTED included (the core's `drawScreen`).
function Points:drawScreen(client)
  if not choosing then
    return
  end
  local list = rows()
  local L = layout(list)
  local P = L.panel
  UI.panel(P.x, P.y, P.w, P.h)
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf("Come back at", P.x, P.y + 12, P.w, "center")
  local mx, my = love.mouse.getPosition()
  love.graphics.setFont(UI.fonts.small)
  for i, r in ipairs(L.rows) do
    local row = list[i]
    local on = row.index == choosing.pick or inside(r, mx, my)
    love.graphics.setColor(on and 0.36 or 0.2, on and 0.56 or 0.26, on and 0.92 or 0.36)
    love.graphics.rectangle("fill", r.x, r.y, r.w, r.h, 5)
    love.graphics.setColor(1, 1, 1)
    local text = (i <= 9 and (i .. "   ") or "    ") .. row.name
    love.graphics.print(text, r.x + 10, r.y + math.floor((r.h - UI.fonts.small:getHeight()) / 2))
  end
  love.graphics.setColor(0.75, 0.75, 0.8)
  local key = Controls.name(Controls.bindings("respawn-pick")[1])
  love.graphics.printf(("%s: come back there  (picked for you in %d s)"):format(key, math.ceil(choosing.left)),
    P.x, P.y + P.h - 24, P.w, "center")
  local vision = Features.byName.vision
  if vision then
    vision:drawCursor(client)
  end
  love.graphics.setColor(1, 1, 1)
end

Points.clientMessages = {
  RSP_FOUND = function(_client, args)
    local i = tonumber(args[1])
    local p = i and points[i]
    if p and not found[i] then
      found[i] = true
      notice = { text = "Respawn point found: " .. p.name, t = Points.noticeTime }
    end
  end,
  RSP_CHOOSE = function(_client, args)
    local best = 0
    for i in pairs(found) do
      best = math.max(best, i)
    end
    choosing = { pick = best, left = tonumber(args[1]) or Points.chooseTime }
  end,
  RSP_DONE = function()
    choosing = nil
  end,
}

-- Server --------------------------------------------------------------------

-- found = { [player id] = { [index] = true } }
-- spots = { [player id] = { x, y, angle } }: where a dead player comes back,
--   the table weapons holds (`serverRespawnPoint`), rewritten by their pick
-- waiting = { [player id] = time the choice runs out }
-- entrance = { [player id] = { x, y, angle } }: where they came onto the map
local sv = nil

function Points:serverStart()
  sv = { time = 0, found = {}, spots = {}, waiting = {}, entrance = {} }
end

local function setSpot(spot, at)
  spot.x, spot.y, spot.angle = at.x, at.y, at.angle or -math.pi / 2
end

--- Everyone is somewhere new: the old map's finds are gone, and anyone
--- dead comes back where the map put them.
function Points:mapChanged(map, server)
  place(map)
  resetClient()
  if not (server and sv) then
    return
  end
  sv.found, sv.waiting, sv.entrance = {}, {}, {}
  for id, p in pairs(server.players) do
    if p.body then
      sv.entrance[id] = { x = p.body.x, y = p.body.y, angle = p.body.facing }
      if sv.spots[id] then
        setSpot(sv.spots[id], sv.entrance[id])
      end
    end
  end
end

function Points:serverPlayerJoined(_server, player)
  if sv and player.body then
    sv.entrance[player.id] = { x = player.body.x, y = player.body.y, angle = player.body.facing }
  end
end

function Points:serverPlayerLeft(_server, player)
  if sv then
    sv.found[player.id], sv.spots[player.id], sv.waiting[player.id], sv.entrance[player.id] = nil, nil, nil, nil
  end
end

--- The furthest point along that `id` has found, or nil.
local function furthest(id)
  local best = nil
  for i in pairs(sv.found[id] or {}) do
    best = math.max(best or 0, i)
  end
  return best
end

--- Weapons asks where a dead player comes back: a dead player who has
--- found a point here gets a spot (the furthest found, until they pick)
--- and the list.
function Points:serverRespawnPoint(spot, server, player)
  if spot or not sv or player.bot then
    return spot
  end
  local best = furthest(player.id)
  if not best then
    return nil
  end
  spot = {}
  setSpot(spot, points[best])
  sv.spots[player.id] = spot
  sv.waiting[player.id] = sv.time + Points.chooseTime
  server:send(player, Protocol.encode("RSP_CHOOSE", Points.chooseTime))
  return spot
end

--- Weapons asks whether to keep a dead player down past their time: yes
--- while they are choosing.
function Points:serverRespawnHeld(_server, player)
  return sv ~= nil and sv.waiting[player.id] ~= nil
end

local function stopWaiting(server, player)
  sv.waiting[player.id] = nil
  server:send(player, Protocol.encode("RSP_DONE"))
end

function Points:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for id, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      sv.spots[id] = nil -- back on their feet
      local x, y = Features.bodyPose(server, p)
      local mine = sv.found[id] or {}
      for i, pt in ipairs(points) do
        if not mine[i] and (pt.x - x) ^ 2 + (pt.y - y) ^ 2 <= Points.reach ^ 2 then
          mine[i] = true
          server:send(p, Protocol.encode("RSP_FOUND", i))
        end
      end
      sv.found[id] = mine
    end
    local until_ = sv.waiting[id]
    if until_ and sv.time >= until_ then
      stopWaiting(server, p) -- out of time: they come back where they were going to
    end
  end
end

Points.serverMessages = {
  RSP_PICK = function(server, player, args)
    local i = tonumber(args[1])
    local spot = sv and sv.spots[player.id]
    if not (spot and sv.waiting[player.id] and i) then
      return
    end
    if i == 0 then
      local s = server.spawnPoints and server.spawnPoints[1]
      local at = sv.entrance[player.id] or (s and { x = s.x, y = s.y, angle = s.angle })
      if at then
        setSpot(spot, at)
      end
    elseif points[i] and sv.found[player.id] and sv.found[player.id][i] then
      setSpot(spot, points[i])
    end
    stopWaiting(server, player)
  end,
}

return Points
