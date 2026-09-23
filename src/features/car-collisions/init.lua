-- Car-to-car collisions on the server. Cars are capsules of three circles
-- (like the map collision); overlapping cars are pushed apart, they swap
-- momentum along the line of impact (so a hit car is shoved and a pushing
-- car keeps pushing), and every feature hears about it:
--
--   feature:serverCarsCollided(server, rammer, rammed, closingSpeed)
--
-- `rammer` is the player whose car was moving into the other one faster.
-- Bots use this to take offence at being rammed.
--
-- Players on foot get run over: a car moving
-- faster than `runOverSpeed` that touches a body deals `runOverDamage` scaled
-- up with speed through Weapons:serverDamage, so a fast car is lethal.

local Features = require("src.features")
local Car = require("src.car")

local CarCollisions = {
  name = "car-collisions",
  priority = 25, -- after the map has settled cars against walls (20)
}

CarCollisions.radius = 11
CarCollisions.offsets = { -12, 0, 12 }
CarCollisions.restitution = 0.35 -- bounciness of a hit: 0 = stick together, 1 = fully elastic
CarCollisions.scrape = 1.5 -- per second; speed lost along the contact while the cars rub
CarCollisions.bodyRadius = 8 -- px; a player on foot, for the bumper test
CarCollisions.runOverSpeed = 90 -- px/s; slower than this just nudges
CarCollisions.runOverDamage = 60 -- at runOverSpeed, rising to 2x at full speed
CarCollisions.runOverGrace = 0.6 -- seconds before the same car can hurt the same body again

local function circles(car, out)
  local ca, sa = math.cos(car.angle), math.sin(car.angle)
  for i, off in ipairs(CarCollisions.offsets) do
    out[i] = out[i] or {}
    out[i][1], out[i][2] = car.x + ca * off, car.y + sa * off
  end
  return out
end

local ca, cb = {}, {}

--- Resolve one pair. Returns closing speed and the normal from a to b if they touched.
local function resolvePair(a, b, dt)
  local r2 = CarCollisions.radius * 2
  circles(a, ca)
  circles(b, cb)
  local nx, ny, hit = 0, 0, false
  for i = 1, #ca do
    for j = 1, #cb do
      local dx, dy = cb[j][1] - ca[i][1], cb[j][2] - ca[i][2]
      local d2 = dx * dx + dy * dy
      if d2 < r2 * r2 and d2 > 1e-6 then
        local d = math.sqrt(d2)
        local push = (r2 - d) / 2
        local ux, uy = dx / d, dy / d
        a.x, a.y = a.x - ux * push, a.y - uy * push
        b.x, b.y = b.x + ux * push, b.y + uy * push
        nx, ny = nx + ux, ny + uy
        hit = true
        circles(a, ca)
        circles(b, cb)
      end
    end
  end
  if not hit then
    return nil
  end
  local len = math.sqrt(nx * nx + ny * ny)
  if len < 1e-6 then
    return 0, 1, 0
  end
  nx, ny = nx / len, ny / len
  local tx, ty = -ny, nx
  local avx, avy = a.vx or math.cos(a.angle) * a.speed, a.vy or math.sin(a.angle) * a.speed
  local bvx, bvy = b.vx or math.cos(b.angle) * b.speed, b.vy or math.sin(b.angle) * b.speed
  local van = avx * nx + avy * ny
  local vbn = bvx * nx + bvy * ny
  local closing = van - vbn -- > 0 when a moves into b (or b into a)
  if closing > 0 then
    -- Equal masses: trade momentum along the normal, bouncing a little,
    -- and rub off some of the speed along the contact.
    local j = (1 + CarCollisions.restitution) * closing / 2
    local rub = math.exp(-CarCollisions.scrape * dt)
    local vat = (avx * tx + avy * ty) * rub
    local vbt = (bvx * tx + bvy * ty) * rub
    a.vx, a.vy = nx * (van - j) + tx * vat, ny * (van - j) + ty * vat
    b.vx, b.vy = nx * (vbn + j) + tx * vbt, ny * (vbn + j) + ty * vbt
    a.speed = a.vx * math.cos(a.angle) + a.vy * math.sin(a.angle)
    b.speed = b.vx * math.cos(b.angle) + b.vy * math.sin(b.angle)
    a.lastSpeed, b.lastSpeed = a.speed, b.speed
  end
  return closing, van, -vbn
end

--- Cars hitting people on foot.
function CarCollisions:runOver(server)
  local weapons = Features.byName.weapons
  if not weapons or not weapons.serverDamage then
    return
  end
  self.hitAt = self.hitAt or {}
  local now = love.timer.getTime()
  for _, walker in pairs(server.players) do
    if Features.present(walker) then
      local bx, by, onFoot = Features.bodyPose(server, walker)
      if onFoot then
        for _, car in pairs(server.vehicles) do
          if not car.hidden and math.abs(car.speed) >= self.runOverSpeed then
            if Car.hitTest(car, bx, by, self.bodyRadius) then
              local key = car.id .. ":" .. walker.id
              if (self.hitAt[key] or -1) + self.runOverGrace <= now then
                self.hitAt[key] = now
                local frac = math.min(1, math.abs(car.speed) / car.maxSpeed)
                local amount = self.runOverDamage * (1 + frac)
                local travel = car.speed >= 0 and car.angle or car.angle + math.pi
                local driver = car.driver and server.players[car.driver] -- nil for a runaway parked car
                weapons:serverDamage(server, walker, driver, amount, travel)
              end
            end
          end
        end
      end
    end
  end
end

--- Every car in the world against every other, parked or not. The
--- collision event names the drivers, so it is only raised when both cars
--- have one.
function CarCollisions:serverStep(server, dt)
  dt = dt or 1 / 30
  self:runOver(server)
  local list = {}
  for _, car in pairs(server.vehicles) do
    if not car.hidden then
      list[#list + 1] = car
    end
  end
  for i = 1, #list do
    for j = i + 1, #list do
      local a, b = list[i], list[j]
      local closing, aInto, bInto = resolvePair(a, b, dt)
      if closing and closing > 0 then
        local da, db = a.driver and server.players[a.driver], b.driver and server.players[b.driver]
        if da and db then
          -- Whoever was moving into the other faster did the ramming.
          local rammer, rammed = da, db
          if bInto > aInto then
            rammer, rammed = db, da
          end
          Features.call("serverCarsCollided", server, rammer, rammed, closing)
        end
      end
    end
  end
end

return CarCollisions
