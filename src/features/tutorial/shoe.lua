-- Shoeman's shoe (docs/tutorial.md, "Cast"): one every PERIOD seconds at
-- the nearest player. He shouts "DODGE!!!!" as he winds up (the telegraph),
-- lets go RELEASE through the throw and the shoe flies in a straight line at
-- where the target stood at that moment. Whatever it touches that can take
-- damage is destroyed at once, and it flies on through: players on foot die
-- (`Weapons:serverKill`), cars are wrecked (their drivers bail out as from
-- any wreck), enemies are asked through `serverShotAt` until none is left
-- there. It stops at the first wall (`blocksShot`: a hedge, a tree, the
-- pond's edge, a building), which takes a blast of KILL (`serverBlast`:
-- players' buildings fall), or after RANGE px.
--
-- A dodge: the player a shoe was thrown at dodges (`Shoe.serverDodged`)
-- while it is in the air, and it goes past them, or stops short, without
-- touching them. Dodging during the wind-up is too soon: he aims where
-- they stand when he lets go.
--
-- Host: `Shoe.serverStart(x, y)` starts throwing from (x, y),
-- `Shoe.serverStop()` stops (shoes in the air vanish with the level),
-- `Shoe.serverStep(server, dt, on)` with optional callbacks `on.threw(server)`
-- (a throw starts: time for the shout) and `on.dodged(server, playerId)`,
-- `Shoe.serverDodged(player)` (on-foot's `serverDodged`),
-- `Shoe.serverNextIn()` (seconds to the next throw: level 2's countdown),
-- `Shoe.serverShoes()` (the shoes in flight: { id, x, y, vx, vy, target =
-- player id, hit = { [player id] = true }, dodged, settled }).
-- Client: `Shoe.update(dt)`, `Shoe.pose()` (throw fraction for
-- `ShoemanRender.draw`, nil standing, and the angle he throws along),
-- `Shoe.draw(x, y)` (the shoes, and the shout over him at (x, y)),
-- `Shoe.clear()`.
--
-- Messages
--   server -> all  TUT_THROW <angle>              he winds up, facing angle
--   server -> all  TUT_SHOE <id> <x> <y> <angle>  a shoe leaves his hand
--   server -> all  TUT_SHOE_END <id> <x> <y>       it stopped there (a wall, its range)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Car = require("src.car")
local UI = require("src.ui")
local ShoemanRender = require("src.features.tutorial.shoeman_render")

local Shoe = {}

-- Tuning ------------------------------------------------------------------
Shoe.PERIOD = 5 -- seconds from one throw to the next
Shoe.FIRST_AFTER = 10 -- seconds into the level before the first (he explains the dodge first)
Shoe.THROW_TIME = 1.2 -- seconds of the throw, the shout at its start
Shoe.SPEED = 900 -- px/s a shoe flies
Shoe.RANGE = 1600 -- px it flies at most
Shoe.RADIUS = 8 -- px, how fat it is for hit tests
Shoe.FOOT_RADIUS = 10 -- px, how fat a player on foot is (weapons' FOOT_RADIUS)
Shoe.HAND = 22 -- px in front of him the shoe starts
Shoe.KILL = 1e6 -- the damage it does: more than anything has
Shoe.SOFT_MAX = 8 -- enemies at one spot it asks for at most per sample
Shoe.STEP = 6 -- px between hit samples along its path
Shoe.SPIN = 16 -- radians a second it tumbles as it flies (drawn only)
Shoe.SIZE = 1.6 -- times the shoe in his hand it is drawn flying and lying (bigger, to be seen; drawn only)
Shoe.LIE_TIME = 4 -- seconds a stopped shoe lies on the ground before it fades (drawn only)
Shoe.SHOUT = "DODGE!!!!"

local RELEASE = ShoemanRender.RELEASE

-- Server --------------------------------------------------------------------

local sv = nil -- { x, y, nextIn, throw = { t, target, angle, released }, shoes = {}, nextId }

function Shoe.serverStart(x, y)
  sv = { x = x, y = y, nextIn = Shoe.FIRST_AFTER, shoes = {}, nextId = 0 }
end

function Shoe.serverStop()
  sv = nil
end

--- Seconds to the next throw, or nil while not throwing.
function Shoe.serverNextIn()
  return sv and math.max(0, sv.nextIn) or nil
end

function Shoe.serverShoes()
  return sv and sv.shoes or {}
end

local function alive(player)
  return Features.present(player) and player.body ~= nil and not player.body.dead
end

--- The nearest living human within range, or nil.
local function pick(server)
  local best, bestD = nil, Shoe.RANGE ^ 2
  for _, player in pairs(server.players) do
    if not player.bot and alive(player) then
      local px, py = Features.bodyPose(server, player)
      local d = px and (px - sv.x) ^ 2 + (py - sv.y) ^ 2
      if d and d < bestD then
        best, bestD = player, d
      end
    end
  end
  return best
end

local function aimAt(server, player, fallback)
  local px, py = nil, nil
  if player and alive(player) then
    px, py = Features.bodyPose(server, player)
  end
  if not px then
    return fallback
  end
  return math.atan2(py - sv.y, px - sv.x)
end

--- Destroy whatever can take damage at (x, y). `shoe.hit` remembers the
--- players already dealt with, so a body is not struck twice.
local function strike(server, shoe, x, y, angle)
  local weapons = Features.byName.weapons
  if not weapons then
    return
  end
  for id, player in pairs(server.players) do
    if not shoe.hit[id] and alive(player) then
      local px, py, onFoot = Features.bodyPose(server, player)
      if onFoot and px and (px - x) ^ 2 + (py - y) ^ 2 <= (Shoe.FOOT_RADIUS + Shoe.RADIUS) ^ 2 then
        shoe.hit[id] = true
        weapons:serverKill(server, player, nil, angle, "impact")
      end
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.hidden or car.stowed) and Car.hitTest(car, x, y, Shoe.RADIUS) then
      if car.driver then
        shoe.hit[car.driver] = true
      end
      weapons:damageCar(server, car, nil, Shoe.KILL, 0, angle, "impact")
    end
  end
  for _, f in ipairs(Features.list) do
    if f.serverShotAt then
      for _ = 1, Shoe.SOFT_MAX do
        if not f:serverShotAt(server, x, y, Shoe.RADIUS, 0, angle, Shoe.KILL, "impact") then
          break
        end
      end
    end
  end
end

--- Decide, once, whether shoe `shoe` was dodged: its target dodged while
--- it flew, and it never touched them.
local function settle(server, shoe, on)
  if shoe.settled or not shoe.target then
    return
  end
  shoe.settled = true
  local target = server.players[shoe.target]
  if shoe.dodged and not shoe.hit[shoe.target] and target and alive(target) and on.dodged then
    on.dodged(server, shoe.target)
  end
end

--- Has shoe `shoe` gone past its target (or is the target gone)? Then it
--- can no longer touch them.
local function passed(server, shoe, ux, uy)
  local target = server.players[shoe.target]
  if not (target and alive(target)) or shoe.hit[shoe.target] then
    return true
  end
  local px, py = Features.bodyPose(server, target)
  if not px then
    return true
  end
  return (px - shoe.x) * ux + (py - shoe.y) * uy < -(Shoe.FOOT_RADIUS + Shoe.RADIUS)
end

local function land(server, i, x, y, on)
  local shoe = table.remove(sv.shoes, i)
  settle(server, shoe, on)
  server:broadcast(Protocol.encode("TUT_SHOE_END", shoe.id, ("%.1f"):format(x), ("%.1f"):format(y)))
end

--- One step of shoe `i`: sampled every STEP px so it can't fly through
--- anything. Returns true if it stopped.
local function fly(server, i, dt, on)
  local shoe = sv.shoes[i]
  local dist = math.min(Shoe.SPEED * dt, Shoe.RANGE - shoe.flown)
  local angle = math.atan2(shoe.vy, shoe.vx)
  local ux, uy = math.cos(angle), math.sin(angle)
  local steps = math.max(1, math.ceil(dist / Shoe.STEP))
  for s = 1, steps do
    local d = dist * s / steps
    local x, y = shoe.x + ux * d, shoe.y + uy * d
    if Features.any("blocksShot", x, y) then
      Features.call("serverBlast", server, x, y, Shoe.RADIUS, Shoe.KILL, 0, "impact")
      land(server, i, x, y, on)
      return true
    end
    strike(server, shoe, x, y, angle)
  end
  shoe.x, shoe.y = shoe.x + ux * dist, shoe.y + uy * dist
  shoe.flown = shoe.flown + dist
  if not shoe.settled and passed(server, shoe, ux, uy) then
    settle(server, shoe, on)
  end
  if shoe.flown >= Shoe.RANGE then
    land(server, i, shoe.x, shoe.y, on)
    return true
  end
  return false
end

--- The shoe leaves his hand at whoever was picked, where they stand now.
local function release(server, throw)
  local angle = aimAt(server, throw.target, throw.angle)
  sv.nextId = sv.nextId + 1
  local x, y = sv.x + math.cos(angle) * Shoe.HAND, sv.y + math.sin(angle) * Shoe.HAND
  local shoe = {
    id = sv.nextId,
    x = x,
    y = y,
    vx = math.cos(angle) * Shoe.SPEED,
    vy = math.sin(angle) * Shoe.SPEED,
    flown = 0,
    target = throw.target and throw.target.id,
    hit = {},
  }
  sv.shoes[#sv.shoes + 1] = shoe
  server:broadcast(Protocol.encode("TUT_SHOE", shoe.id, ("%.1f"):format(x), ("%.1f"):format(y),
    ("%.3f"):format(angle)))
end

--- `player` started a dodge: every shoe in the air at them notes it.
function Shoe.serverDodged(player)
  for _, shoe in ipairs(sv and sv.shoes or {}) do
    if shoe.target == player.id and not shoe.settled then
      shoe.dodged = true
    end
  end
end

--- Fly the shoes, run the throw under way, start the next when it is time.
--- `on.threw(server)` is called when a throw starts, `on.dodged(server, id)` when
--- a shoe was dodged (see the top).
function Shoe.serverStep(server, dt, on)
  on = on or {}
  if not sv then
    return
  end
  for i = #sv.shoes, 1, -1 do
    fly(server, i, dt, on)
  end
  local throw = sv.throw
  if throw then
    throw.t = throw.t + dt
    if not throw.released and throw.t >= Shoe.THROW_TIME * RELEASE then
      throw.released = true
      release(server, throw)
    end
    if throw.t >= Shoe.THROW_TIME then
      sv.throw = nil
    end
  end
  sv.nextIn = sv.nextIn - dt
  if sv.nextIn > 0 or sv.throw then
    return
  end
  local target = pick(server)
  if not target then
    sv.nextIn = 0.5 -- nobody to throw at: look again shortly
    return
  end
  sv.nextIn = Shoe.PERIOD
  local angle = aimAt(server, target, 0)
  sv.throw = { t = 0, target = target, angle = angle, released = false }
  server:broadcast(Protocol.encode("TUT_THROW", ("%.3f"):format(angle)))
  if on.threw then
    on.threw(server)
  end
end

-- Client --------------------------------------------------------------------

local cl = {
  throw = nil, -- { t, angle } while he throws
  shoes = {}, -- id -> { x, y, angle, flown, spin }
  lying = {}, -- { id, x, y, spin, t }: stopped shoes on the ground
}

function Shoe.clear()
  cl.throw, cl.shoes, cl.lying = nil, {}, {}
end

local function lie(shoe, x, y)
  cl.lying[#cl.lying + 1] = { id = shoe.id, x = x, y = y, spin = shoe.spin, t = 0 }
end

function Shoe.update(dt)
  if cl.throw then
    cl.throw.t = cl.throw.t + dt
    if cl.throw.t >= Shoe.THROW_TIME then
      cl.throw = nil
    end
  end
  for id, shoe in pairs(cl.shoes) do
    local d = math.min(Shoe.SPEED * dt, Shoe.RANGE - shoe.flown)
    shoe.x, shoe.y = shoe.x + math.cos(shoe.angle) * d, shoe.y + math.sin(shoe.angle) * d
    shoe.flown = shoe.flown + d
    shoe.spin = shoe.spin + Shoe.SPIN * dt
    -- At a wall or past its range the host's end is on its way; don't
    -- keep drawing it flying.
    if shoe.flown >= Shoe.RANGE or Features.any("blocksShot", shoe.x, shoe.y) then
      cl.shoes[id] = nil
      lie(shoe, shoe.x, shoe.y)
    end
  end
  for i = #cl.lying, 1, -1 do
    local l = cl.lying[i]
    l.t = l.t + dt
    if l.t >= Shoe.LIE_TIME + 1 then
      table.remove(cl.lying, i)
    end
  end
end

--- His throw as `ShoemanRender.draw` wants it (0 to 1, nil standing) and
--- the angle he throws along (nil standing).
function Shoe.pose()
  if not cl.throw then
    return nil, nil
  end
  return cl.throw.t / Shoe.THROW_TIME, cl.throw.angle
end

--- The shoes on the ground and in the air, and the shout over Shoeman at
--- (x, y) while he winds up.
function Shoe.draw(x, y)
  for _, l in ipairs(cl.lying) do
    ShoemanRender.shoe(l.x, l.y, l.spin, Shoe.SIZE, math.min(1, Shoe.LIE_TIME + 1 - l.t))
  end
  for _, shoe in pairs(cl.shoes) do
    ShoemanRender.shoe(shoe.x, shoe.y, shoe.spin, Shoe.SIZE)
  end
  local throw = cl.throw
  if not (throw and x) then
    return
  end
  local k = throw.t / Shoe.THROW_TIME
  local a = math.min(1, (1 - k) * 4)
  local font = UI.fonts.heading
  love.graphics.setFont(font)
  local w = font:getWidth(Shoe.SHOUT)
  local shake = (1 - k) * 2
  local tx = x - w / 2 + (love.math.random() - 0.5) * shake
  local ty = y - ShoemanRender.RADIUS - 30 + (love.math.random() - 0.5) * shake
  love.graphics.setColor(0, 0, 0, 0.7 * a)
  love.graphics.print(Shoe.SHOUT, tx + 2, ty + 2)
  love.graphics.setColor(1, 0.42, 0.36, a)
  love.graphics.print(Shoe.SHOUT, tx, ty)
  love.graphics.setColor(1, 1, 1)
end

Shoe.clientMessages = {
  TUT_THROW = function(_client, args)
    cl.throw = { t = 0, angle = tonumber(args[1]) or 0 }
  end,
  TUT_SHOE = function(_client, args)
    local id, x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if id and x and y and angle then
      cl.shoes[id] = { id = id, x = x, y = y, angle = angle, flown = 0, spin = angle }
      if cl.throw then
        cl.throw.angle = angle -- he follows through the way it went
      end
    end
  end,
  TUT_SHOE_END = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local shoe = id and cl.shoes[id]
    if shoe and x and y then
      cl.shoes[id] = nil
      lie(shoe, x, y)
    elseif x and y then
      -- Already stopped here (a wall it reached first on this screen): put it where the host says.
      for _, l in ipairs(cl.lying) do
        if l.id == id then
          l.x, l.y = x, y
        end
      end
    end
  end,
}

return Shoe
