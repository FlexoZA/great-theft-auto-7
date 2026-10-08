-- The boost: a car model with a `boost` (catalog.lua: the scout car) goes
-- faster while its driver holds the boost key (Shift, the on-foot sprint's
-- key), the way a sprint does on foot. Up to `speed` times its top speed
-- and `accel` times its acceleration, for as long as its meter lasts
-- (`seconds` of holding from full); let go and the meter fills back up from
-- empty in `refill` seconds, after a moment (`DELAY`). Run it dry and the
-- key has to come up before it boosts again, as a spent sprint does. When a boost ends
-- the top speed eases back down rather than snapping, so the car coasts
-- down to cruising speed.
--
-- The host runs it (the car's handling is the host's), from the driver's
-- VH_BOOST 1 / 0 as the key goes down and up, and tells the driver how
-- much is left (VH_BOOSTLEFT) while it is not full; the meter stands in the
-- row of stat bars beside the health while they drive such a car.
--
-- Messages
--   client -> server  VH_BOOST <0|1>          (the boost key held or let go)
--   server -> player  VH_BOOSTLEFT <vid> <0..1>  (how full that car's meter is)

local Protocol = require("src.net.protocol")
local Controls = require("src.controls")
local UI = require("src.ui")
local Catalog = require("src.features.vehicles.catalog")

local Boost = {}

Boost.DELAY = 0.6 -- seconds after letting go before the meter starts to fill
Boost.EASE = 300 -- px/s^2 the top speed comes back down at once a boost ends
Boost.SEND_EVERY = 0.15 -- seconds between VH_BOOSTLEFT while it changes
Boost.HUD_SLOT = 4 -- the meter's place in the row of stat bars (health 0, stamina 1, dodge 2, armour 3)

local function boostOf(key)
  local model = key and Catalog.byKey[key]
  return model and model.boost, model
end

-- Client --------------------------------------------------------------------

local held = false
local left = {} -- vehicle id -> 0..1, as the host last said

function Boost.load()
  Controls.register("boost", "Boost (driving)", "lshift", "rshift") -- the sprint's keys: one on foot, one at the wheel
end

function Boost.clear()
  held, left = false, {}
end

--- Tell the host when the key goes down or up, while driving a car that boosts.
function Boost.update(client, models)
  local v = client:myVehicle()
  local can = v and boostOf(models[v.id])
  local down = can and Controls.isDown("boost") or false
  if down ~= held then
    held = down
    client:send(Protocol.encode("VH_BOOST", down and 1 or 0))
  end
end

--- The meter, beside the health, while I drive a car that boosts.
function Boost.drawHUD(client, models)
  local v = client:myVehicle()
  if not (v and boostOf(models[v.id])) then
    return
  end
  local frac = left[v.id] or 1
  local color = held and frac > 0 and { 1, 0.75, 0.2 } or { 0.95, 0.6, 0.15 }
  UI.drawStatBar(Boost.HUD_SLOT, "boost", frac, color, frac >= 1 and "ready" or nil, nil, nil, frac > 0 and 1 or 0.55)
end

function Boost.onLeft(args)
  local vid, frac = tonumber(args[1]), tonumber(args[2])
  if vid and frac then
    left[vid] = frac
  end
end

-- Server --------------------------------------------------------------------

local sv = nil -- { want = { [player id] = true }, cars = { [vid] = { left, wait, send, spent, told, toldTo } } }

function Boost.serverStart()
  sv = { want = {}, cars = {} }
end

function Boost.serverWant(player, on)
  if sv then
    sv.want[player.id] = on or nil
  end
end

function Boost.serverPlayerLeft(player)
  if sv then
    sv.want[player.id] = nil
  end
end

--- Every car that boosts: drain or fill its meter, set its top speed and
--- acceleration, and keep its driver told.
function Boost.serverStep(server, dt)
  if not sv then
    return
  end
  for vid, car in pairs(server.vehicles) do
    local b, model = boostOf(car.model)
    if b then
      local st = sv.cars[vid]
      if not st then
        st = { left = b.seconds, wait = 0, send = 0 }
        sv.cars[vid] = st
      end
      local want = car.driver and sv.want[car.driver]
      if not want then
        st.spent = nil -- let go: the next press may boost again
      end
      local on = want and st.left > 0 and not st.spent and not car.hidden
      if on then
        st.left, st.wait = math.max(0, st.left - dt), Boost.DELAY
        st.spent = st.left <= 0 or nil -- run dry: not again till the key comes up
        car.maxSpeed, car.accel = model.topSpeed * b.speed, model.acceleration * b.accel
      else
        st.wait = math.max(0, st.wait - dt)
        if st.wait <= 0 then
          st.left = math.min(b.seconds, st.left + dt * b.seconds / b.refill)
        end
        car.maxSpeed = math.max(model.topSpeed, car.maxSpeed - Boost.EASE * dt) -- coast back down
        car.accel = model.acceleration
      end
      st.send = st.send - dt
      local driver = car.driver and server.players[car.driver]
      local frac = ("%.2f"):format(st.left / b.seconds)
      if driver and not driver.bot and st.send <= 0 and (frac ~= st.told or driver.id ~= st.toldTo) then
        st.send, st.told, st.toldTo = Boost.SEND_EVERY, frac, driver.id -- only what changed, the full mark included
        server:send(driver, Protocol.encode("VH_BOOSTLEFT", vid, frac))
      end
    end
  end
  for vid in pairs(sv.cars) do
    if not server.vehicles[vid] then
      sv.cars[vid] = nil
    end
  end
end

return Boost
