-- Car stations: pads on a driven map (the Winding Road's `map.carStations`,
-- one short of every bridge) where a player on foot calls up a car of the
-- map's `loaner` model (a Scout Car) and is put behind its wheel. Lost your
-- buggy to a nest, or left it a long way back? Walk to the nearest pad.
--
-- Standing on a pad on foot, the action key (F, shared with getting into a
-- car) calls it: the car the map lent you, wherever it is (wrecked and
-- waiting to come back, or parked a mile off), whole again and loaded on
-- the pad; or, if you came in your own car, a new one lent to you
-- (city-map's `serverLend`; your own stays where you left it, and is yours
-- again when you leave). Each player waits `cooldown` seconds between
-- calls, so a pad is no free repair in the middle of a fight. The host
-- checks everything: on foot, in the world, not held, on the pad, the wait
-- over, and nobody else driving the car.
--
-- Messages
--   client -> server  CST_CALL <station>     (index into map.carStations)
--   server -> player  CST_WAIT <seconds>      (refused: the wait left, 0 for any other reason)
--   server -> all     CST_CALLED <x> <y>      (a car came up on a pad: a flash there)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")

local Stations = {
  name = "car-stations",
}

-- Tuning ------------------------------------------------------------------
Stations.reach = 56 -- px from a pad's middle that counts as standing on it
Stations.cooldown = 10 -- seconds a player waits between calls
Stations.flashTime = 0.7 -- seconds a call's flash lasts

local function stations()
  local city = Features.byName["city-map"]
  return city and city.map and city.map.carStations or {}
end

--- The pad within `reach` of (x, y), and its index.
local function padAt(x, y, slack)
  local r = Stations.reach + (slack or 0)
  for i, st in ipairs(stations()) do
    if (st.x - x) ^ 2 + (st.y - y) ^ 2 <= r * r then
      return st, i
    end
  end
  return nil
end

-- Client --------------------------------------------------------------------

local near, wait, flashes, notice = nil, 0, {}, nil -- notice: { text, t }

function Stations:load()
  Controls.register("car-station", "Call a car (on a car station's pad)", "f") -- the action key, like the shop's
end

function Stations:exitGame()
  near, wait, flashes, notice = nil, 0, {}, nil
end

function Stations:update(dt, client)
  wait = math.max(0, wait - dt)
  near = nil
  if not client:myVehicle() then
    local x, y, onFoot = client:myPose()
    if x and onFoot then
      near = select(2, padAt(x, y))
    end
  end
  for i = #flashes, 1, -1 do
    flashes[i].t = flashes[i].t + dt
    if flashes[i].t > Stations.flashTime then
      table.remove(flashes, i)
    end
  end
  if notice then
    notice.t = notice.t - dt
    if notice.t <= 0 then
      notice = nil
    end
  end
end

--- The `actionTaken` convention: on a pad the action key calls a car, so
--- on-foot doesn't take it to climb into whatever car is in reach.
function Stations:actionTaken()
  return near ~= nil
end

function Stations:keypressed(key, client)
  if not (near and Controls.is("car-station", key)) or Features.any("menuOpen", client) then
    return
  end
  if wait > 0 then
    notice = { text = ("Next car in %d s"):format(math.ceil(wait)), t = 1.5 }
    return
  end
  wait = Stations.cooldown -- the host says otherwise if it disagrees (CST_WAIT)
  client:send(Protocol.encode("CST_CALL", near))
end

--- A call's flash on the pad: a ring going out from it.
function Stations:drawAboveCars()
  for _, f in ipairs(flashes) do
    local k = f.t / Stations.flashTime
    love.graphics.setColor(1, 0.85, 0.35, 0.8 * (1 - k))
    love.graphics.setLineWidth(4)
    love.graphics.circle("line", f.x, f.y, 20 + k * 70)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- On a pad on foot: the offer (or the wait), where the shop's stands.
function Stations:drawHUD()
  if not near then
    return
  end
  local w, h = love.graphics.getDimensions()
  local text = notice and notice.text
  if not text then
    local key = Controls.name(Controls.bindings("car-station")[1])
    text = wait > 0 and ("Car station.  Next car in %d s"):format(math.ceil(wait))
      or ("Car station.  " .. key .. ": call a Scout Car")
  end
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(1, 0.85, 0.35)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- The pads on the minimap and the big map: small yellow squares.
function Stations:drawOnMinimap(_client, toMap)
  for _, st in ipairs(stations()) do
    local x, y = toMap(st.x, st.y)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", x - 4, y - 4, 8, 8)
    love.graphics.setColor(1, 0.85, 0.35)
    love.graphics.rectangle("fill", x - 3, y - 3, 6, 6)
  end
  love.graphics.setColor(1, 1, 1)
end

Stations.clientMessages = {
  CST_WAIT = function(_client, args)
    local seconds = tonumber(args[1]) or 0
    wait = seconds
    if seconds > 0 then
      notice = { text = ("Next car in %d s"):format(math.ceil(seconds)), t = 1.5 }
    end
  end,
  CST_CALLED = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      flashes[#flashes + 1] = { x = x, y = y, t = 0 }
    end
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { time, readyAt = { [id] = time } }

function Stations:serverStart()
  sv = { time = 0, readyAt = {} }
end

function Stations:serverStep(_server, dt)
  if sv then
    sv.time = sv.time + dt
  end
end

function Stations:serverPlayerLeft(_server, player)
  if sv then
    sv.readyAt[player.id] = nil
  end
end

--- `player` asks for a car at pad `index`: up it comes, and in they get.
local function call(server, player, index)
  local st = stations()[index or 0]
  local city = Features.byName["city-map"]
  if not (sv and st and city) or player.vehicle or not Features.present(player)
    or Features.any("serverHeld", server, player) then
    return false
  end
  local x, y = Features.bodyPose(server, player)
  if select(2, padAt(x, y, 24)) ~= index then -- on the pad (with room for the trip there)
    return false
  end
  local left = (sv.readyAt[player.id] or 0) - sv.time
  if left > 0 then
    server:send(player, Protocol.encode("CST_WAIT", ("%.1f"):format(left)))
    return true
  end
  local spot = { x = st.x, y = st.y, angle = st.angle }
  local car, new = city:serverLend(server, player, spot)
  if not car or car.driver then
    return false -- no loaner here, or somebody else is driving theirs
  end
  local weapons = Features.byName.weapons
  if not new and weapons and weapons.serverRestoreCar then
    weapons:serverRestoreCar(server, car, st.x, st.y, st.angle) -- whole again, on the pad
  end
  server:seat(player, car)
  sv.readyAt[player.id] = sv.time + Stations.cooldown
  server:broadcast(Protocol.encode("CST_CALLED", st.x, st.y))
  return true
end

Stations.serverMessages = {
  CST_CALL = function(server, player, args)
    if not call(server, player, tonumber(args[1])) then
      server:send(player, Protocol.encode("CST_WAIT", 0)) -- refused: the client's wait was a guess
    end
  end,
}

return Stations
