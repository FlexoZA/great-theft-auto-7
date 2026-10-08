-- Prediction of my own car. Without it the car I drive is drawn easing
-- towards the server's last word, so at 200 ms of ping it answers the keys
-- a third of a second late and every late or lost snapshot pulls it about.
--
-- So the client drives a copy of it: every input it sends (one per server
-- tick, INPUT_INTERVAL in client.lua) also moves the copy one tick with the
-- same physics (src/car.lua) and whatever features add through the
-- `predictCar(client, car, dt)` hook (the city map's walls, a model's
-- handling and boost), and is kept until the server says it is done with
-- it. The server applies each input exactly once, one a tick, and after
-- every tick tells the driver where their car is and which input it has
-- applied last (YOU, server.lua). The copy then starts again from there and
-- replays every input the server hasn't got to yet. Whatever that moves
-- the car by is not shown at once: it goes into an offset that fades away
-- (`CORRECT`), so a small disagreement is never a jump. A big one (a
-- respawn, a teleport) is.
--
-- The copy moves a tick at a time; it is drawn between its last two places
-- as the next tick comes up, so it moves smoothly at any frame rate.
--
-- Other cars, and anything the server does to mine that the copy doesn't
-- know about (a car in the way, a shove), are still the server's: the
-- replay picks them up a round trip later and the offset smooths them in.

local Car = require("src.car")
local Features = require("src.features")

local Predict = {}

Predict.CORRECT = 10 -- per second; how fast a correction fades in
Predict.SNAP = 160 -- px; a correction bigger than this is a jump (respawn, teleport): shown at once
Predict.KEEP = 90 -- inputs kept for replay at most (3 s at 30 a second)

local function angleDiff(a, b)
  return (a - b + math.pi) % (2 * math.pi) - math.pi
end

--- A prediction for vehicle `v` (a client snapshot), starting where it is.
function Predict.new(client, v)
  local car = Car.new(v.x, v.y, v.angle)
  car.id = v.id
  car:setSpeed(v.speed or 0)
  Features.call("predictCar", client, car, 0) -- its model's handling, before the first step
  return {
    vid = v.id,
    car = car,
    history = {}, -- { seq, throttle, steer, handbrake } sent and not yet applied by the server
    px = car.x, -- where it was before the last step: drawn between there and the car
    py = car.y,
    pangle = car.angle,
    ox = 0, -- correction still to fade in
    oy = 0,
    oangle = 0,
  }
end

local function step(client, car, dt, input)
  car:update(dt, input.throttle, input.steer, input.handbrake)
  Features.call("predictCar", client, car, dt)
end

--- Input `seq` was just sent: move the car a tick with it and keep it.
function Predict.input(p, client, dt, seq, throttle, steer, handbrake)
  local input = { seq = seq, throttle = throttle, steer = steer, handbrake = handbrake }
  p.history[#p.history + 1] = input
  if #p.history > Predict.KEEP then
    table.remove(p.history, 1)
  end
  p.px, p.py, p.pangle = p.car.x, p.car.y, p.car.angle
  step(client, p.car, dt, input)
end

--- The server's word (YOU): after input `applied` the car was at (x, y),
--- facing `angle`, moving at (vx, vy). Start again from there, replay the
--- rest, and fade in the difference.
function Predict.correct(p, client, dt, applied, x, y, angle, vx, vy)
  local car = p.car
  local oldX, oldY, oldAngle = car.x, car.y, car.angle
  local keep = {}
  for _, input in ipairs(p.history) do
    if input.seq > applied then
      keep[#keep + 1] = input
    end
  end
  p.history = keep
  car.x, car.y, car.angle, car.vx, car.vy = x, y, angle, vx, vy
  car.speed = vx * math.cos(angle) + vy * math.sin(angle)
  car.lastSpeed = car.speed
  for _, input in ipairs(keep) do
    step(client, car, dt, input)
  end
  local dx, dy = oldX - car.x, oldY - car.y
  if dx * dx + dy * dy > Predict.SNAP * Predict.SNAP then
    p.ox, p.oy, p.oangle = 0, 0, 0
    p.px, p.py, p.pangle = car.x, car.y, car.angle
    return
  end
  -- The car jumped by (-dx, -dy): carry the drawn point with it, so what is
  -- on screen doesn't move this frame, and let the offset fade.
  p.ox, p.oy = p.ox + dx, p.oy + dy
  p.oangle = p.oangle + angleDiff(oldAngle, car.angle)
  p.px, p.py = p.px - dx, p.py - dy
  p.pangle = p.pangle - angleDiff(oldAngle, car.angle)
end

--- Let the correction fade (every frame).
function Predict.update(p, dt)
  local k = math.exp(-Predict.CORRECT * dt)
  p.ox, p.oy, p.oangle = p.ox * k, p.oy * k, p.oangle * k
end

--- Where to draw it: `alpha` (0..1) of the way from its last place to the
--- car, plus what is left of the correction.
function Predict.pose(p, alpha)
  local car = p.car
  local x = p.px + (car.x - p.px) * alpha + p.ox
  local y = p.py + (car.y - p.py) * alpha + p.oy
  local angle = p.pangle + angleDiff(car.angle, p.pangle) * alpha + p.oangle
  return x, y, angle
end

return Predict
