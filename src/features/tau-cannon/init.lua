-- The tau cannon: the gun bolted to the scout car (vehicles' "scout-car"
-- models), after Half-Life 2's buggy. Whoever is driving one fires it
-- with its own button (right mouse), on top of the gun in their hand:
--   tap   a quick bolt (`quick`): light, fast, as often as `cooldown` allows
--   hold  it charges for up to `chargeTime` (the glow at the muzzle grows,
--         the whine climbs) and lets go on release: one heavy bolt, up to
--         `fullDamage` at a full charge, and a kick that shoves the car
--         back the way it came (`kick`, px/s)
-- Hold it past the full charge for `overload` seconds and it goes off by
-- itself, a full charge, and the overload burns the car (`burn`).
--
-- It aims at the cursor, but only so far round from the car's nose
-- (`arc` either side): the mount doesn't turn any further. Its rounds are
-- the weapons feature's (serverFireFrom with a gun of its own, owned by
-- the driver, so kills are theirs), quiet there: this feature sounds them,
-- and draws the charge and the flash. No ammo: like the buggy's, it never
-- runs dry.
--
-- The host decides everything: who may fire it (driving a scout car, not
-- held still), how long it charged (its own clock, from TAU_CHARGE to
-- TAU_FIRE), the aim (clamped to the arc) and the rate of fire.
--
-- Messages
--   client -> server  TAU_CHARGE                    (button down)
--   client -> server  TAU_FIRE <aim>                (button up)
--   server -> all     TAU_CHARGING <vid> <0|1>      (a car's cannon started / stopped charging)
--   server -> all     TAU_SHOT <vid> <x> <y> <aim> <charge>   (it fired from (x, y); charge 0..1, 0 a quick bolt)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Catalog = require("src.features.vehicles.catalog")
local Guns = require("src.features.weapons.guns")
local Sounds = require("src.features.weapons.sounds")
local TauSounds = require("src.features.tau-cannon.sounds")

local Tau = {
  name = "tau-cannon",
  priority = 960, -- after weapons (950), so the camera is final when we aim
}

-- Tuning ------------------------------------------------------------------
Tau.carType = "scout-car" -- the vehicles that carry one (a catalog model's `type`)
Tau.arc = math.rad(70) -- how far either side of the nose it aims
Tau.muzzle = { 16, 7 } -- px ahead of the car's middle and to its right, where the bolts leave
Tau.tap = 0.25 -- seconds: a press shorter than this is a quick bolt
Tau.chargeTime = 2 -- seconds of holding (from the tap on) to a full charge
Tau.overload = 2 -- seconds past a full charge before it goes off by itself
Tau.burn = 25 -- what an overload does to the car
Tau.cooldown = 0.22 -- seconds between quick bolts
Tau.chargedCooldown = 0.8 -- seconds after a charged one before it fires again
Tau.kick = 420 -- px/s a full charge shoves the car back
Tau.fullDamage = 150 -- a full charge's bolt (a quick bolt's at none)
Tau.quick = setmetatable({ -- a quick bolt; a charged one is this with more damage
  damage = 18,
  cooldown = Tau.cooldown,
  spread = 0.01,
  speed = 2400,
  ttl = 0.75, -- about 1800 px
  damageType = "shock",
  tint = "ffb347",
  quiet = true, -- the sounds are ours
}, { __index = Guns.sniper }) -- the sniper's long streak on every screen

-- Shared -------------------------------------------------------------------

--- Does a vehicle of model `key` carry a tau cannon?
local function armed(key)
  local model = key and Catalog.byKey[key]
  return model ~= nil and model.type == Tau.carType
end

--- Where the bolts leave a car at (x, y) facing `angle`.
local function muzzleOf(x, y, angle)
  local ca, sa = math.cos(angle), math.sin(angle)
  return x + ca * Tau.muzzle[1] - sa * Tau.muzzle[2], y + sa * Tau.muzzle[1] + ca * Tau.muzzle[2]
end

--- `aim` turned no further than the arc from `angle`.
local function clampAim(aim, angle)
  local d = (aim - angle + math.pi) % (2 * math.pi) - math.pi
  return angle + math.max(-Tau.arc, math.min(Tau.arc, d))
end

local function fmt(v)
  return ("%.2f"):format(v)
end

-- Client --------------------------------------------------------------------

local cl = { charging = {}, flashes = {}, whine = {} }
-- charging: vid -> seconds it has charged; flashes: { x, y, aim, charge, t }
-- whine: vid -> the charge sound playing for it
local mine = { down = false, held = 0, cooldown = 0 } -- my button, and how long I have held it

function Tau:load()
  Controls.register("tau-cannon", "Tau cannon (scout car: tap, or hold to charge)", "mouse2")
  TauSounds.load(Tau.chargeTime + Tau.tap, Tau.overload)
end

local function stopWhine(vid)
  if cl.whine[vid] then
    cl.whine[vid]:stop()
    cl.whine[vid] = nil
  end
end

function Tau:exitGame()
  for vid in pairs(cl.whine) do
    stopWhine(vid)
  end
  cl = { charging = {}, flashes = {}, whine = {} }
  mine = { down = false, held = 0, cooldown = 0 }
end

--- The car I'm driving, if it carries a cannon.
local function myCannon(client)
  local v = client:myVehicle()
  local vehicles = Features.byName.vehicles
  if v and vehicles and armed(vehicles.models[v.id]) then
    return v
  end
  return nil
end

function Tau:update(dt, client)
  for vid, t in pairs(cl.charging) do
    cl.charging[vid] = t + dt
  end
  for i = #cl.flashes, 1, -1 do
    local f = cl.flashes[i]
    f.t = f.t + dt
    if f.t > 0.35 then
      table.remove(cl.flashes, i)
    end
  end
  mine.cooldown = math.max(0, mine.cooldown - dt)

  local car = myCannon(client)
  local down = car ~= nil and Controls.isDown("tau-cannon") and not Features.any("pointerTaken", client)
    and not Features.any("held", client, client.myId)
  if down and not mine.down then
    if mine.cooldown <= 0 then
      mine.down, mine.held = true, 0
      client:send(Protocol.encode("TAU_CHARGE"))
    end
  elseif mine.down then
    mine.held = mine.held + dt
    if mine.held >= Tau.tap + Tau.chargeTime + Tau.overload then
      mine.down, mine.cooldown = false, Tau.chargedCooldown -- the overload: the host fires it by itself
    elseif not down then
      mine.down = false
      mine.cooldown = mine.held < Tau.tap and Tau.cooldown or Tau.chargedCooldown
      local weapons = Features.byName.weapons
      local aim = weapons and weapons:aimAngle(client)
      client:send(Protocol.encode("TAU_FIRE", aim and ("%.3f"):format(aim) or "-"))
    end
  end
end

--- How charged a cannon that has been held `t` seconds is, 0..1.
local function chargeOf(t)
  return math.max(0, math.min(1, (t - Tau.tap) / Tau.chargeTime))
end

function Tau:drawAboveCars(client)
  local now = love.timer.getTime()
  -- The glow at the muzzle of every cannon that is charging.
  for _, v in pairs(client.vehicles) do
    local t = cl.charging[v.id]
    if t and t > Tau.tap * 0.5 then
      local k = chargeOf(t)
      local over = math.max(0, t - Tau.tap - Tau.chargeTime) / Tau.overload -- 0..1 into the overload
      local x, y = muzzleOf(v.dx, v.dy, v.dangle)
      local flicker = 0.85 + 0.15 * math.sin(now * (30 + over * 40))
      local r = (3 + k * 9 + over * 4) * flicker
      love.graphics.setColor(1, 0.55, 0.15, 0.25 + k * 0.25)
      love.graphics.circle("fill", x, y, r * 2.2)
      love.graphics.setColor(1, 0.75 - over * 0.4, 0.3 - over * 0.2, 0.8)
      love.graphics.circle("fill", x, y, r)
      love.graphics.setColor(1, 1, 0.9)
      love.graphics.circle("fill", x, y, r * 0.45)
    end
  end
  -- Every bolt's flash: a beam out from the muzzle, fading fast.
  for _, f in ipairs(cl.flashes) do
    local life = f.charge > 0 and 0.35 or 0.12
    local a = 1 - f.t / life
    if a > 0 then
      local len = 120 + f.charge * 500
      local ex, ey = f.x + math.cos(f.aim) * len, f.y + math.sin(f.aim) * len
      love.graphics.setColor(1, 0.6, 0.2, a * 0.35)
      love.graphics.setLineWidth(4 + f.charge * 14)
      love.graphics.line(f.x, f.y, ex, ey)
      love.graphics.setColor(1, 0.95, 0.8, a)
      love.graphics.setLineWidth(1.5 + f.charge * 4)
      love.graphics.line(f.x, f.y, ex, ey)
      love.graphics.setColor(1, 0.8, 0.4, a)
      love.graphics.circle("fill", f.x, f.y, 6 + f.charge * 16)
    end
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- In a scout car: the charge as a ring round the cursor while the button is held.
function Tau:drawHUD(client)
  if not (mine.down and myCannon(client)) or mine.held < Tau.tap then
    return
  end
  local mx, my = love.mouse.getPosition()
  local k = chargeOf(mine.held)
  local over = math.max(0, mine.held - Tau.tap - Tau.chargeTime) / Tau.overload
  local color = over > 0 and (math.floor(love.timer.getTime() * 10) % 2 == 0 and { 1, 0.25, 0.2 } or { 1, 0.9, 0.5 })
    or { 1, 0.65, 0.2 }
  UI.ring(mx, my, 22, k, color, 4)
  love.graphics.setColor(1, 1, 1)
end

Tau.clientMessages = {
  TAU_CHARGING = function(client, args)
    local vid = tonumber(args[1])
    if not vid then
      return
    end
    if args[2] == "1" then
      cl.charging[vid] = 0
      stopWhine(vid)
      local c = client.vehicles[vid]
      cl.whine[vid] = c and Sounds.play("tau-charge", c.dx or c.x, c.dy or c.y)
    else
      cl.charging[vid] = nil
      stopWhine(vid)
    end
  end,
  TAU_SHOT = function(_client, args)
    local vid = tonumber(args[1])
    local x, y, aim, charge = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if not (x and y and aim and charge) then
      return
    end
    cl.charging[vid or -1] = nil
    stopWhine(vid)
    cl.flashes[#cl.flashes + 1] = { x = x, y = y, aim = aim, charge = charge, t = 0 }
    if charge > 0 then
      Sounds.play("tau-blast", x, y, 1.15 - charge * 0.25)
    else
      Sounds.play("tau-zap", x, y, 0.95 + love.math.random() * 0.1)
    end
  end,
}

-- Server --------------------------------------------------------------------

local sv = nil -- { time, players = { [id] = { since, vid, ready } } }: since when, and in which car, a charge

function Tau:serverStart()
  sv = { time = 0, players = {} }
end

local function state(player)
  sv = sv or { time = 0, players = {} }
  local st = sv.players[player.id]
  if not st then
    st = { since = nil, vid = nil, ready = 0 }
    sv.players[player.id] = st
  end
  return st
end

--- The scout car `player` is driving, or nil.
local function cannonOf(player)
  local car = player.vehicle
  if car and car.driver == player.id and not car.hidden and armed(car.model) then
    return car
  end
  return nil
end

--- Stop a charge without firing (they left the car, it was wrecked, they were frozen).
local function drop(server, st)
  st.since = nil
  server:broadcast(Protocol.encode("TAU_CHARGING", st.vid, 0))
end

--- Fire `player`'s cannon at `aim` (straight ahead when nil) after a hold of `held` seconds.
local function fire(server, player, st, car, aim, held)
  local weapons = Features.byName.weapons
  if not weapons then
    return
  end
  local charge = held >= Tau.tap and math.min(1, (held - Tau.tap) / Tau.chargeTime) or 0
  aim = clampAim(aim or car.angle, car.angle)
  local x, y = muzzleOf(car.x, car.y, car.angle)
  local gun = Tau.quick
  if charge > 0 then
    gun = setmetatable({ damage = Tau.quick.damage + (Tau.fullDamage - Tau.quick.damage) * charge,
      tint = "ffe0a0", speed = 2800 }, { __index = Tau.quick })
  end
  st.ready = sv.time + (charge > 0 and Tau.chargedCooldown or Tau.cooldown) * 0.9
  server:broadcast(Protocol.encode("TAU_SHOT", car.id, fmt(x), fmt(y), ("%.3f"):format(aim), fmt(charge)))
  weapons:serverFireFrom(server, player.id, x, y, aim, gun)
  if charge > 0 then
    -- The kick: back along the bolt's line.
    car.vx = (car.vx or 0) - math.cos(aim) * Tau.kick * charge
    car.vy = (car.vy or 0) - math.sin(aim) * Tau.kick * charge
  end
end

Tau.serverMessages = {
  TAU_CHARGE = function(server, player)
    local st = state(player)
    local car = cannonOf(player)
    if not car or st.since or sv.time < st.ready or Features.any("serverHeld", server, player) then
      return
    end
    st.since, st.vid = sv.time, car.id
    server:broadcast(Protocol.encode("TAU_CHARGING", car.id, 1))
  end,
  TAU_FIRE = function(server, player, args)
    local st = state(player)
    local car = cannonOf(player)
    if not st.since then
      return -- never charging: nothing to let go of
    end
    if not car or car.id ~= st.vid or Features.any("serverHeld", server, player) then
      drop(server, st)
      return
    end
    local held = sv.time - st.since
    st.since = nil
    fire(server, player, st, car, tonumber(args[1]), held)
  end,
}

--- Charges that ran too long go off by themselves; a charge whose driver
--- left the car (or lost it) is dropped.
function Tau:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for id, st in pairs(sv.players) do
    local player = server.players[id]
    if st.since then
      local car = player and cannonOf(player)
      if not car or car.id ~= st.vid then
        drop(server, st) -- out of the car, or it was wrecked under them
      elseif sv.time - st.since >= Tau.tap + Tau.chargeTime + Tau.overload then
        st.since = nil
        fire(server, player, st, car, nil, Tau.tap + Tau.chargeTime)
        local weapons = Features.byName.weapons
        if weapons then
          weapons:serverDamage(server, player, nil, Tau.burn, car.angle, "shock")
        end
      end
    end
  end
end

function Tau:serverPlayerLeft(server, player)
  local st = sv and sv.players[player.id]
  if st and st.since then
    drop(server, st) -- gone mid-charge: the glow goes out on every screen
  end
  if sv then
    sv.players[player.id] = nil
  end
end

return Tau
