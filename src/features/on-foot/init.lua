-- On foot: E gets you out of your car and back into it. Out of the car you
-- walk at the pace of the crowd, sprint on Shift until your stamina runs out
-- (it comes back slowly), and keep your gun: shots leave from where you are
-- standing rather than from the car you parked.
--
-- The host owns the walk. Clients send the direction they are pushing and
-- the way they are facing; the server moves them, keeps them out of
-- buildings, spends and regenerates stamina and broadcasts where everyone
-- is. The local player is predicted from the same numbers and eased back
-- towards the server, so walking feels immediate on a slow link.
--
-- The car you left stays parked where you left it: the server pins it every
-- tick, so the driving keys you press while walking can't drive it away.
-- Bullets pass through it while you are out; you are the target, not it.
--
-- Movement reuses the driving bindings (W A S D by default) as plain world
-- directions and you face the cursor, so aiming and walking are independent.
--
-- Conventions this feature answers (docs/features.md):
--   playerPose / clientPlayerPose  where a player's body is when they are
--                                  not behind the wheel; weapons fires from
--                                  there, hits land there
--   hidesCarLabel                  the parked car drops its name tag; the
--                                  figure carries it instead
--
-- Messages
--   client -> server  OF_TOGGLE
--   client -> server  OF_MOVE  <seq> <mx> <my> <sprint> <facing>  (unreliable, 30 Hz)
--   server -> all     OF_OUT   <tick> <id> <x> <y> <facing>
--   server -> all     OF_IN    <tick> <id>
--   server -> all     OF_STATE <tick> [<id> <x> <y> <facing> <stamina>]...  (unreliable)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local Car = require("src.car")
local UI = require("src.ui")
local Render = require("src.features.on-foot.render")

local OnFoot = {
  name = "on-foot",
  priority = 80, -- update before vision (900) so its pan rides on the figure
}

-- Tuning ------------------------------------------------------------------
OnFoot.walkSpeed = 45 -- px/s; Crowd.WALK_SPEED, so you keep up with the crowd
OnFoot.sprintSpeed = 170 -- px/s; Crowd.FLEE_SPEED, the pace of a scared pedestrian
OnFoot.maxStamina = 100
OnFoot.sprintDrain = 22 -- stamina per second while sprinting (~4.5s flat out)
OnFoot.staminaRegen = 9 -- stamina per second once you stop
OnFoot.regenDelay = 1.2 -- seconds of not sprinting before it starts coming back
OnFoot.recovered = 25 -- stamina needed before an emptied bar can sprint again
OnFoot.radius = 7 -- px; how fat you are against walls
OnFoot.exitMaxSpeed = 140 -- px/s; no bailing out of a car at speed
OnFoot.exitOffset = 34 -- px from the car centre you step out at
OnFoot.enterReach = 26 -- px of padding around the car that counts as within reach

local MOVE_INTERVAL = 1 / 30 -- seconds between OF_MOVE packets
local CORRECTION = 6 -- per second; how fast prediction is pulled onto the server
local SNAP = 120 -- px; a correction bigger than this is a teleport

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

--- Solid ground, through the `blocksPoint` convention (the city map owns it).
--- The body is a circle, so the point is tested with its four extremes.
local function blockedAt(x, y)
  local r = OnFoot.radius
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

--- One step of walking, each axis on its own so a wall is slid along rather
--- than run into. Returns the new x, y. Shared by the host and the local
--- prediction so both agree on where a step ends.
local function step(x, y, mx, my, speed, dt)
  local nx = x + mx * speed * dt
  if not blockedAt(nx, y) then
    x = nx
  end
  local ny = y + my * speed * dt
  if not blockedAt(x, ny) then
    y = ny
  end
  return x, y
end

--- The walking direction the local keys are asking for, as a unit vector in
--- world space (up is up, whatever the car is doing).
local function moveInput()
  local x, y = 0, 0
  if Controls.isDown("left") then
    x = x - 1
  end
  if Controls.isDown("right") then
    x = x + 1
  end
  if Controls.isDown("accelerate") then
    y = y - 1
  end
  if Controls.isDown("brake") then
    y = y + 1
  end
  local len = math.sqrt(x * x + y * y)
  if len > 0 then
    x, y = x / len, y / len
  end
  return x, y
end

-- Client --------------------------------------------------------------------

OnFoot.view = { x = 0, y = 0, scale = 1 } -- last camera actually drawn with
OnFoot.moveTimer = 0
OnFoot.moveSeq = 0
OnFoot.hitbox = {} -- reused table for the "am I next to my car?" test

function OnFoot:load()
  Controls.register("enter-exit", "Enter / exit vehicle", "e")
  Controls.register("sprint", "Sprint (on foot)", "lshift", "rshift")
end

function OnFoot:enterGame()
  self.moveTimer = 0
  self.moveSeq = 0
end

function OnFoot:exitGame()
  Render.clear()
  self.view.x, self.view.y, self.view.scale = 0, 0, 1
end

--- Am I out of my car? Returns the figure, which carries dx, dy and stamina.
function OnFoot:me(client)
  return client.myId and Render.get(client.myId) or nil
end

--- Angle from (x, y) to the cursor, using the camera the last frame drew
--- with; this feature updates before vision pans, so the live camera is a
--- pan behind at this point in the frame.
function OnFoot:cursorAngle(x, y)
  local mx, my = love.mouse.getPosition()
  local w, h = love.graphics.getDimensions()
  local s = self.view.scale ~= 0 and self.view.scale or 1
  return math.atan2(self.view.y + (my - h / 2) / s - y, self.view.x + (mx - w / 2) / s - x)
end

--- Is my car close enough to climb into?
function OnFoot:carInReach(client, me)
  local car = client:myCar()
  if not car then
    return false
  end
  local box = self.hitbox
  box.x, box.y, box.angle = car.dx, car.dy, car.dangle
  return Car.hitTest(box, me.dx, me.dy, self.enterReach)
end

--- Walk my own figure with the keys I am holding, then ease it back onto the
--- server's last word so a disagreement never lasts.
function OnFoot:predict(dt, me)
  local mx, my = moveInput()
  -- The host's "get your breath back" rule, read off the stamina it sends,
  -- so prediction doesn't sprint while the host is still walking it off.
  local stamina = me.stamina or 0
  if stamina <= 0 then
    me.spent = true
  elseif me.spent and stamina >= self.recovered then
    me.spent = false
  end
  local sprinting = (mx ~= 0 or my ~= 0) and Controls.isDown("sprint") and stamina > 0 and not me.spent
  if mx ~= 0 or my ~= 0 then
    me.dx, me.dy = step(me.dx, me.dy, mx, my, sprinting and self.sprintSpeed or self.walkSpeed, dt)
  end
  me.sprinting = sprinting
  me.angle = self:cursorAngle(me.dx, me.dy)

  local ex, ey = me.x - me.dx, me.y - me.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    me.dx, me.dy = me.x, me.y -- respawned or shoved: take the server's word
  else
    local k = math.min(1, CORRECTION * dt)
    me.dx, me.dy = me.dx + ex * k, me.dy + ey * k
  end
end

function OnFoot:sendMove(dt, client, me)
  self.moveTimer = self.moveTimer - dt
  if self.moveTimer > 0 then
    return
  end
  self.moveTimer = self.moveTimer + MOVE_INTERVAL
  self.moveSeq = self.moveSeq + 1
  local mx, my = moveInput()
  local sprint = Controls.isDown("sprint") and 1 or 0
  local msg = Protocol.encode("OF_MOVE", self.moveSeq, ("%.3f"):format(mx), ("%.3f"):format(my), sprint,
    ("%.3f"):format(me.angle))
  client:send(msg, true)
end

function OnFoot:update(dt, client, camera)
  Render.update(dt, client.myId)
  local me = self:me(client)
  if not me then
    return
  end
  self:predict(dt, me)
  self:sendMove(dt, client, me)
  -- The camera and the ears belong to the body, not to the parked car.
  camera.x, camera.y = me.dx, me.dy
  love.audio.setPosition(me.dx, 0, me.dy)
end

function OnFoot:keypressed(key, client)
  if Controls.is("enter-exit", key) and client then
    client:send(Protocol.encode("OF_TOGGLE"))
  end
end

function OnFoot:drawAboveCars(client, camera)
  self.view.x, self.view.y, self.view.scale = camera.x, camera.y, camera.scale or 1
  Render.draw(client, camera)
end

function OnFoot:drawHUD(client)
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local me = self:me(client)
  love.graphics.setFont(UI.fonts.small)

  if me then
    local frac = math.max(0, math.min(1, (me.stamina or 0) / self.maxStamina))
    local bw, bh = 120, 6
    love.graphics.setColor(0.6, 0.6, 0.65)
    love.graphics.print("stamina", 10, 136)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", 69, 139, bw + 2, bh + 2)
    love.graphics.setColor(0.3 + 0.7 * (1 - frac), 0.75 * frac + 0.25, 0.3)
    love.graphics.rectangle("fill", 70, 140, bw * frac, bh)
    love.graphics.setColor(0.8, 0.8, 0.85)
    local sprintKey = Controls.name(Controls.bindings("sprint")[1])
    local hint = sprintKey .. ": sprint"
    if self:carInReach(client, me) then
      hint = key .. ": get in   " .. hint
    end
    love.graphics.print(hint, 10, 154)
  else
    local car = client:myCar()
    if car and math.abs(car.speed) <= self.exitMaxSpeed then
      love.graphics.setColor(0.8, 0.8, 0.85)
      love.graphics.print(key .. ": get out", 10, 136)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The core skips the name over a car whose driver is out walking; the
--- figure carries the name instead (see docs/features.md).
function OnFoot:hidesCarLabel(_client, id)
  return Render.get(id) ~= nil
end

--- Where player `id`'s body is on this machine, or nil when they are driving.
--- Weapons aims and draws health from here.
function OnFoot:clientPlayerPose(_client, id)
  local p = Render.get(id)
  if p then
    return p.dx, p.dy, p.angle
  end
  return nil
end

OnFoot.clientMessages = {
  OF_OUT = function(_client, args)
    local tick, id = tonumber(args[1]), tonumber(args[2])
    local x, y, facing = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if id and x and y then
      Render.spawn(id, x, y, facing or 0, tick)
    end
  end,
  OF_IN = function(_client, args)
    local tick, id = tonumber(args[1]), tonumber(args[2])
    if id then
      Render.remove(id, tick)
    end
  end,
  OF_STATE = function(_client, args)
    Render.sync(args)
  end,
}

-- Server --------------------------------------------------------------------

function OnFoot:serverStart()
  self.sv = { onFoot = {} } -- player id -> { x, y, facing, stamina, ... }
end

function OnFoot:serverPlayerLeft(server, player)
  if self.sv and self.sv.onFoot[player.id] then
    self.sv.onFoot[player.id] = nil
    server:broadcast(Protocol.encode("OF_IN", server.tick, player.id))
  end
end

--- Where `player` stands when they are not behind the wheel. The `playerPose`
--- convention; weapons fires from here and lands hits here.
function OnFoot:playerPose(_server, player)
  local st = self.sv and self.sv.onFoot[player.id]
  if st then
    return st.x, st.y, st.facing
  end
  return nil
end

--- Wrecked while walking (weapons blew up the body): the corpse goes back
--- behind the wheel and respawns with the car, like any other death.
function OnFoot:serverKill(server, kill)
  if kill.kind == "car" and kill.victim and self.sv and self.sv.onFoot[kill.victim] then
    self.sv.onFoot[kill.victim] = nil
    server:broadcast(Protocol.encode("OF_IN", server.tick, kill.victim))
  end
end

--- The first free spot beside the car: driver's side, then the other side,
--- then behind it. Falls back to the car itself if the city has walled it in.
function OnFoot:exitSpot(car)
  local offsets = { -math.pi / 2, math.pi / 2, math.pi, 0 }
  for _, off in ipairs(offsets) do
    local a = car.angle + off
    local x, y = car.x + math.cos(a) * self.exitOffset, car.y + math.sin(a) * self.exitOffset
    if not blockedAt(x, y) then
      return x, y
    end
  end
  return car.x, car.y
end

function OnFoot:getOut(server, player)
  local car = player.car
  if math.abs(car.speed) > self.exitMaxSpeed then
    return -- still moving too fast to step out
  end
  local x, y = self:exitSpot(car)
  car:stop()
  self.sv.onFoot[player.id] = {
    x = x,
    y = y,
    facing = car.angle,
    stamina = self.maxStamina,
    regenIn = 0,
    spent = false,
    lastSeq = 0,
    move = { x = 0, y = 0, sprint = false },
    car = { x = car.x, y = car.y, angle = car.angle }, -- where it stays parked
  }
  local fx, fy, facing = ("%.1f"):format(x), ("%.1f"):format(y), ("%.3f"):format(car.angle)
  server:broadcast(Protocol.encode("OF_OUT", server.tick, player.id, fx, fy, facing))
end

function OnFoot:getIn(server, player, st)
  if not Car.hitTest(player.car, st.x, st.y, self.enterReach) then
    return -- too far from your car; walk back to it
  end
  self.sv.onFoot[player.id] = nil
  server:broadcast(Protocol.encode("OF_IN", server.tick, player.id))
end

--- One player's step: spend or regain stamina, then walk. Leaning on the
--- sprint key with an empty bar keeps it empty; you get your breath back by
--- letting go, not by running on.
function OnFoot:walk(st, dt)
  local mx, my = st.move.x, st.move.y
  local len = math.sqrt(mx * mx + my * my)
  local asking = len > 0 and st.move.sprint
  local sprinting = asking and st.stamina > 0 and not st.spent

  if asking then
    st.regenIn = self.regenDelay
    if sprinting then
      st.stamina = math.max(0, st.stamina - self.sprintDrain * dt)
      if st.stamina <= 0 then
        st.spent = true -- blown: walk it off before you can sprint again
      end
    end
  else
    st.regenIn = st.regenIn - dt
    if st.regenIn <= 0 then
      st.stamina = math.min(self.maxStamina, st.stamina + self.staminaRegen * dt)
      if st.spent and st.stamina >= self.recovered then
        st.spent = false
      end
    end
  end

  if len > 0 then
    local speed = sprinting and self.sprintSpeed or self.walkSpeed
    st.x, st.y = step(st.x, st.y, mx / len, my / len, speed, dt)
  end
end

function OnFoot:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  local parts, n = { server.tick }, 0
  for id, st in pairs(sv.onFoot) do
    local player = server.players[id]
    if not player or not player.car then
      sv.onFoot[id] = nil
    else
      self:walk(st, dt)
      -- The car they left is furniture until they come back for it.
      local car = player.car
      car.x, car.y, car.angle = st.car.x, st.car.y, st.car.angle
      car:stop()
      n = n + 1
      parts[#parts + 1] = id
      parts[#parts + 1] = ("%.1f"):format(st.x)
      parts[#parts + 1] = ("%.1f"):format(st.y)
      parts[#parts + 1] = ("%.3f"):format(st.facing)
      parts[#parts + 1] = ("%.0f"):format(st.stamina)
    end
  end
  if n == 0 then
    return -- nobody is walking, so there is nothing to say
  end
  local msg = Protocol.encode("OF_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    server:send(player, msg, true)
  end
end

OnFoot.serverMessages = {
  OF_TOGGLE = function(server, player)
    local sv = OnFoot.sv
    if not sv or not player.car or player.car.hidden then
      return -- wrecked, or the game hasn't started
    end
    local st = sv.onFoot[player.id]
    if st then
      OnFoot:getIn(server, player, st)
    else
      OnFoot:getOut(server, player)
    end
  end,
  OF_MOVE = function(_server, player, args)
    local st = OnFoot.sv and OnFoot.sv.onFoot[player.id]
    if not st then
      return -- they are driving; nothing to move
    end
    local seq = tonumber(args[1])
    if not seq or seq <= st.lastSeq then
      return -- stale or garbage
    end
    st.lastSeq = seq
    st.move.x = clamp(tonumber(args[2]) or 0, -1, 1)
    st.move.y = clamp(tonumber(args[3]) or 0, -1, 1)
    st.move.sprint = args[4] == "1"
    st.facing = tonumber(args[5]) or st.facing
  end,
}

return OnFoot
