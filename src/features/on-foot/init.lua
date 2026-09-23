-- On foot: E gets you out of your car, and into any car within reach that
-- nobody is driving. Out of a car you walk at the pace of the crowd, sprint
-- on Shift until your stamina runs out (it comes back slowly), and keep
-- your gun: shots leave from where you are standing.
--
-- The body itself belongs to the core (src/body.lua): the server keeps one
-- per player, STATE says who is on foot where, and the game state draws
-- them. This feature is the walking: the host moves a walker with the
-- direction they push and the way they face, keeps them out of buildings,
-- spends and regenerates stamina, and seats and unseats them on request.
-- The local player is predicted from the same numbers and eased back
-- towards the server, so walking feels immediate on a slow link.
--
-- A car you get out of stops where it is and stays there for anyone to
-- take. On a map with no vehicles (city-map's `map.vehicles`), everyone is
-- turned out and their cars are stowed: out of the world, off every
-- screen, until the group is back on a map with roads worth driving.
--
-- Movement reuses the driving bindings (W A S D by default) as plain world
-- directions and you face the cursor, so aiming and walking are independent.
-- Tap one of them twice quickly and you dodge: a short dash that way,
-- faster than a sprint, for some stamina and a moment's cooldown. The host
-- does the dash (and refuses one you can't afford); your own is predicted
-- like a step, so it feels instant, and everyone sees the dust.
--
-- Stamina has a ceiling per player, maxStamina to start with, and comes back
-- at a rate per player, staminaRegen to start with; another feature can
-- raise either (upgrades sells both) through OnFoot:serverSetMaxStamina and
-- OnFoot:serverSetStaminaRegen. Only the host needs the rate, so it is
-- never sent; the bar the client sees already reflects it.
--
-- Messages
--   client -> server  OF_TOGGLE
--   client -> server  OF_MOVE  <seq> <mx> <my> <sprint> <facing>  (unreliable, 30 Hz)
--   client -> server  OF_DODGE <dx> <dy>                         a double-tap: dash this way
--   server -> all     OF_DODGED <id> <x> <y> <dx> <dy>           they dashed from here, this way
--   server -> all     OF_STATE <tick> [<id> <stamina>]...  (unreliable; everyone on foot)
--   server -> all     OF_GIB   <id> <x> <y> <angle>   died on foot: splat here
--   server -> all     OF_MAX   <id> <max>       their stamina ceiling changed

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local Car = require("src.car")
local Body = require("src.body")
local UI = require("src.ui")

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
OnFoot.radius = Body.RADIUS -- px; how fat you are against walls
OnFoot.exitMaxSpeed = 140 -- px/s; no bailing out of a car at speed
OnFoot.exitOffset = 34 -- px from the car centre you step out at
OnFoot.enterReach = 26 -- px of padding around a car that counts as within reach
OnFoot.dodgeDistance = 96 -- px a dodge carries you
OnFoot.dodgeTime = 0.22 -- seconds it takes
OnFoot.dodgeCooldown = 0.9 -- seconds before the next one
OnFoot.dodgeStamina = 20 -- what one costs; can't dodge on less
OnFoot.doubleTap = 0.28 -- seconds between two taps of a key that count as one double-tap

-- The HUD's bottom-left cluster of vertical bars: stamina, then the dodge,
-- each `hudStep` apart; abilities carry the row on from the next slot.
OnFoot.hudX = 24
OnFoot.hudStep = 70 -- room for a name under each bar
OnFoot.hudBarW = 28 -- px wide
OnFoot.hudBarH = 100 -- px tall
OnFoot.hudBottom = 58 -- px up from the bottom edge the bars stand on

-- The movement actions and the world direction each one dodges in.
local DODGE_DIRS = {
  { action = "left", x = -1, y = 0 },
  { action = "right", x = 1, y = 0 },
  { action = "accelerate", x = 0, y = -1 },
  { action = "brake", x = 0, y = 1 },
}

local MOVE_INTERVAL = 1 / 30 -- seconds between OF_MOVE packets
local CORRECTION = 6 -- per second; how fast prediction is pulled onto the server
local SNAP = 120 -- px; a correction bigger than this is a teleport

local function clamp(v, lo, hi)
  return math.max(lo, math.min(hi, v))
end

--- May anyone drive on the map in play? (city-map's `map.vehicles`; a
--- quest's map can say no, and then everyone walks.)
local function vehiclesAllowed()
  local city = Features.byName["city-map"]
  return not (city and city.map and city.map.vehicles == false)
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

--- One step, each axis on its own so a wall is slid along rather than run
--- into. Shared by the server's walk and the client's prediction so both
--- agree on where a step ends.
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
OnFoot.maxOf = {} -- player id -> stamina ceiling (absent = maxStamina)
OnFoot.stamina = {} -- player id -> stamina, as the host last said (walkers only)
OnFoot.moveTimer = 0
OnFoot.moveSeq = 0
OnFoot.hitbox = {} -- reused table for the "is that car within reach?" test
OnFoot.dash = nil -- { x, y, t }: my own dodge under way, predicted
OnFoot.dodgeReadyAt = 0 -- client time my next dodge may start
OnFoot.lastTap = nil -- { action, at }: the last movement key press, for the double-tap
OnFoot.tapReady = {} -- action -> true once its key has been seen up since the last press it counted
OnFoot.puffs = {} -- { x, y, dx, dy, t }: dust where somebody dodged
local spent = false -- my breath, for prediction: an emptied bar sprints again only once recovered
local time = 0 -- client clock, seconds in the game

function OnFoot:load()
  Controls.register("enter-exit", "Enter / exit vehicle", "e")
  Controls.register("sprint", "Sprint (on foot)", "lshift", "rshift")
end

function OnFoot:enterGame()
  self.moveTimer = 0
  self.moveSeq = 0
  self.dash, self.lastTap, self.puffs = nil, nil, {}
  self.tapReady = {}
  self.dodgeReadyAt = 0
  spent = false
  time = 0
end

function OnFoot:exitGame()
  self.maxOf = {}
  self.stamina = {}
  self.view.x, self.view.y, self.view.scale = 0, 0, 1
  spent = false
end

--- Am I on foot? Returns my body snapshot, which carries dx, dy, dangle.
function OnFoot:me(client)
  return client:myBody()
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

--- A car nobody is driving, close enough to climb into, on a map where I may.
function OnFoot:vehicleInReach(client, me)
  if not vehiclesAllowed() then
    return nil
  end
  local box = self.hitbox
  for _, v in pairs(client.vehicles) do
    if not v.driver then
      box.x, box.y, box.angle = v.dx, v.dy, v.dangle
      if Car.hitTest(box, me.dx, me.dy, self.enterReach) then
        return v
      end
    end
  end
  return nil
end

--- Walk my own figure with the keys I am holding, then ease it back onto the
--- server's last word so a disagreement never lasts.
function OnFoot:predict(dt, client, me)
  me.predicted = true
  local mx, my = moveInput()
  -- The host's "get your breath back" rule, read off the stamina it sends,
  -- so prediction doesn't sprint while the host is still walking it off.
  local stamina = self.stamina[client.myId] or self.maxOf[client.myId] or self.maxStamina
  if stamina <= 0 then
    spent = true
  elseif spent and stamina >= self.recovered then
    spent = false
  end
  -- Held still by some feature (frozen): the host won't move me, so don't
  -- walk ahead of it (the `held` convention, docs/features.md).
  local held = Features.any("held", client, client.myId)
  local sprinting = (mx ~= 0 or my ~= 0) and Controls.isDown("sprint") and stamina > 0 and not spent and not held
  if self.dash and not held then
    -- Mid-dodge: the dash carries me, the keys don't.
    local d = self.dash
    local slice = math.min(dt, d.t) -- the last step only goes as far as is left
    me.dx, me.dy = step(me.dx, me.dy, d.x, d.y, self.dodgeDistance / self.dodgeTime, slice)
    d.t = d.t - dt
    if d.t <= 0 then
      self.dash = nil
    end
    sprinting = true -- legs going: draw it running
  elseif (mx ~= 0 or my ~= 0) and not held then
    me.dx, me.dy = step(me.dx, me.dy, mx, my, sprinting and self.sprintSpeed or self.walkSpeed, dt)
  end
  me.running = sprinting
  me.dangle = self:cursorAngle(me.dx, me.dy)

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
    ("%.3f"):format(me.dangle))
  client:send(msg, true)
end

--- A double-tap: dash that way if I am on foot, free, rested enough and
--- not still recovering from the last one. The host has the final word.
function OnFoot:tryDodge(client, dir)
  local me = self:me(client)
  if not me or self.dash or time < self.dodgeReadyAt or Features.any("held", client, client.myId) then
    return false
  end
  local stamina = self.stamina[client.myId] or self.maxOf[client.myId] or self.maxStamina
  if stamina < self.dodgeStamina then
    return false
  end
  self.dash = { x = dir.x, y = dir.y, t = self.dodgeTime }
  self.dodgeReadyAt = time + self.dodgeCooldown
  client:send(Protocol.encode("OF_DODGE", dir.x, dir.y))
  return true
end

function OnFoot:update(dt, client, camera)
  time = time + dt
  -- A key held down repeats its press event; only a press after a release
  -- is a tap. Note which movement keys are up right now.
  for _, dir in ipairs(DODGE_DIRS) do
    if not Controls.isDown(dir.action) then
      self.tapReady[dir.action] = true
    end
  end
  for i = #self.puffs, 1, -1 do
    local puff = self.puffs[i]
    puff.t = puff.t + dt
    if puff.t > 0.45 then
      table.remove(self.puffs, i)
    end
  end
  local me = self:me(client)
  if not me then
    self.dash = nil
    return
  end
  self:predict(dt, client, me)
  self:sendMove(dt, client, me)
  -- The camera and the ears belong to the predicted body, a step ahead of
  -- where the game state anchored them this frame.
  camera.x, camera.y = me.dx, me.dy
  love.audio.setPosition(me.dx, 0, me.dy)
end

function OnFoot:keypressed(key, client)
  if Controls.is("enter-exit", key) and client then
    client:send(Protocol.encode("OF_TOGGLE"))
    return
  end
  -- A movement key: the second tap of the same one inside doubleTap dodges.
  -- A press while the key is already down is the key repeating, not a tap.
  for _, dir in ipairs(DODGE_DIRS) do
    if Controls.is(dir.action, key) then
      if self.tapReady[dir.action] == false then
        return -- held down: a repeat
      end
      self.tapReady[dir.action] = false
      local last = self.lastTap
      if last and last.action == dir.action and time - last.at <= self.doubleTap then
        self.lastTap = nil -- used up: a third tap starts over
        if client then
          self:tryDodge(client, dir)
        end
      else
        self.lastTap = { action = dir.action, at = time }
      end
      return
    end
  end
end

--- Dust kicked up where somebody dodged: a few puffs drifting back the way
--- they came, fading.
function OnFoot:drawAboveCars(_client, camera)
  self.view.x, self.view.y, self.view.scale = camera.x, camera.y, camera.scale or 1
  for _, puff in ipairs(self.puffs) do
    local k = puff.t / 0.45
    for i = 0, 2 do
      local d = 6 + i * 9 + k * 14
      love.graphics.setColor(0.75, 0.72, 0.62, (1 - k) * 0.5)
      local px = puff.x - puff.dx * d + (i - 1) * puff.dy * 5
      local py = puff.y - puff.dy * d + (i - 1) * puff.dx * 5
      love.graphics.circle("fill", px, py, 3 + k * 4 - i * 0.5, 8)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- The stamina bar's colour: green with plenty, amber when it is getting
--- low, red when nearly gone.
local function staminaColor(frac)
  if frac > 0.5 then
    local k = (frac - 0.5) * 2
    return { 0.4 + 0.6 * (1 - k), 0.85, 0.35 }
  end
  local k = frac * 2
  return { 1, 0.35 + 0.5 * k, 0.3 }
end

--- One bar of the bottom-left cluster: the value above, the bar, its
--- name under it. `value` may be nil.
function OnFoot.drawStatBar(slot, name, frac, color, value, valueColor, marks)
  local font = UI.fonts.small
  local x = OnFoot.hudX + slot * OnFoot.hudStep
  local w, h = OnFoot.hudBarW, OnFoot.hudBarH
  local y = love.graphics.getHeight() - OnFoot.hudBottom - h
  local cx = x + w / 2
  love.graphics.setFont(font)
  UI.vmeter(x, y, w, h, frac, color, marks)
  UI.label(name, math.floor(cx - font:getWidth(name) / 2), y + h + 6, { 0.85, 0.85, 0.9 })
  if value then
    UI.label(value, math.floor(cx - font:getWidth(value) / 2), y - font:getHeight() - 2, valueColor)
  end
  return x, y, w, h
end

function OnFoot:drawHUD(client)
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local me = self:me(client)
  love.graphics.setFont(UI.fonts.small)

  if me then
    -- The bar grows with the ceiling, so an upgrade shows on the HUD; the
    -- notch marks what a dodge costs.
    local max = self.maxOf[client.myId] or self.maxStamina
    local stamina = self.stamina[client.myId] or max
    local frac = math.max(0, math.min(1, stamina / max))
    local color = staminaColor(frac)
    if spent then
      -- Winded: the bar throbs dim red until enough is back to sprint on.
      color = { 0.9, 0.3, 0.3, 0.45 + 0.25 * math.sin(time * 8) }
    end
    local readout = spent and "winded" or ("%d"):format(stamina)
    self.drawStatBar(0, "stamina", frac, color, readout, spent and { 1, 0.5, 0.45 } or { 1, 1, 1 },
      { self.dodgeStamina / max })

    -- The dodge: lit when one is there for the taking, filling back up
    -- through the cooldown, dim red while there is no breath for one.
    local cooling = math.max(0, self.dodgeReadyAt - time)
    local dodgeColor, value, valueColor
    if self.dash then
      dodgeColor = { 1, 1, 1, 0.9 }
    elseif stamina < self.dodgeStamina then
      dodgeColor, value, valueColor = { 0.9, 0.3, 0.3, 0.4 }, "tired", { 1, 0.5, 0.45 }
    elseif cooling > 0 then
      dodgeColor, value, valueColor = { 1, 1, 1, 0.45 }, ("%.1f"):format(cooling), { 0.85, 0.85, 0.9 }
    else
      dodgeColor, value, valueColor = { 0.78, 0.65, 1, 0.9 }, "ready", { 0.85, 0.78, 1 }
    end
    local dfrac = self.dash and 1 or (1 - cooling / self.dodgeCooldown)
    self.drawStatBar(1, "dodge", dfrac, dodgeColor, value, valueColor)

    love.graphics.setColor(0.8, 0.8, 0.85)
    local sprintKey = Controls.name(Controls.bindings("sprint")[1])
    local hint = sprintKey .. ": sprint   double-tap: dodge"
    if self:vehicleInReach(client, me) then
      hint = key .. ": get in   " .. hint
    end
    love.graphics.print(hint, 10, 136)
  else
    local car = client:myVehicle()
    if car and math.abs(car.speed) <= self.exitMaxSpeed then
      love.graphics.setColor(0.8, 0.8, 0.85)
      love.graphics.print(key .. ": get out", 10, 136)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

OnFoot.clientMessages = {
  OF_STATE = function(_client, args)
    local stamina = {}
    for i = 2, #args - 1, 2 do
      local id, s = tonumber(args[i]), tonumber(args[i + 1])
      if id and s then
        stamina[id] = s
      end
    end
    OnFoot.stamina = stamina
  end,
  OF_MAX = function(_client, args)
    local id, max = tonumber(args[1]), tonumber(args[2])
    if id and max then
      OnFoot.maxOf[id] = max
    end
  end,
  --- Somebody died on foot: the pedestrians' gibs and splat, if that feature is around.
  OF_DODGED = function(_client, args)
    local x, y, dx, dy = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if x and y and dx and dy then
      OnFoot.puffs[#OnFoot.puffs + 1] = { x = x, y = y, dx = dx, dy = dy, t = 0 }
    end
  end,
  OF_GIB = function(_client, args)
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle or 0)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.8 + love.math.random() * 0.2)
    end
  end,
}

-- Server ----------------------------------------------------------------

OnFoot.sv = nil

function OnFoot:serverStart()
  self.sv = {
    walkers = {}, -- player id -> { stamina, max, regen, regenIn, spent, lastSeq, move, dash, dodgeReadyAt }
    time = 0, -- seconds since the game started
    maxStamina = {}, -- player id -> ceiling (absent = OnFoot.maxStamina)
    regen = {}, -- player id -> regen scale (absent = 1)
  }
end

function OnFoot:serverPlayerLeft(_server, player)
  if self.sv then
    self.sv.walkers[player.id] = nil
    self.sv.maxStamina[player.id] = nil
    self.sv.regen[player.id] = nil
  end
end

--- A player's stamina ceiling on the host.
function OnFoot:maxFor(id)
  return self.sv and self.sv.maxStamina[id] or self.maxStamina
end

--- How fast a player's stamina comes back on the host, per second.
function OnFoot:regenFor(id)
  return self.staminaRegen * (self.sv and self.sv.regen[id] or 1)
end

--- The host's walking record for a player, made the first time it is needed.
function OnFoot:walker(player)
  local st = self.sv.walkers[player.id]
  if not st then
    local max = self:maxFor(player.id)
    st = {
      stamina = max,
      max = max,
      regen = self:regenFor(player.id),
      regenIn = 0,
      spent = false,
      lastSeq = 0,
      move = { x = 0, y = 0, sprint = false },
      dash = nil, -- { x, y, t } while dodging
      dodgeReadyAt = 0,
    }
    self.sv.walkers[player.id] = st
  end
  return st
end

--- Give a walking player back up to `amount` stamina and their breath with
--- it (a blown bar can sprint again at once). Returns true if any was
--- gained, so a pickup knows whether it was used; false for a driver, who
--- has no bar to fill, and the drink stays on the road for later. Other
--- features reach this via Features.byName["on-foot"] (pickups does).
function OnFoot:serverRestoreStamina(_server, player, amount)
  if not self.sv or player.vehicle or not player.body then
    return false
  end
  local st = self:walker(player)
  if st.stamina >= st.max then
    return false
  end
  st.stamina = math.min(st.max, st.stamina + amount)
  st.spent = false
  return true
end

--- Set how fast a player's stamina comes back, as a multiple of staminaRegen,
--- for the rest of the game. Other features reach this via
--- Features.byName["on-foot"] (upgrades does). Returns the scale set.
function OnFoot:serverSetStaminaRegen(_server, player, scale)
  if not self.sv then
    return nil
  end
  scale = math.max(0.1, scale)
  self.sv.regen[player.id] = scale
  local st = self.sv.walkers[player.id]
  if st then
    st.regen = self.staminaRegen * scale
  end
  return scale
end

--- Raise (or lower) a player's stamina ceiling to `max` for the rest of the
--- game. Raising it tops them up by the difference, so an upgrade is felt
--- at once. Other features reach this via Features.byName["on-foot"]
--- (upgrades does). Returns the new ceiling.
function OnFoot:serverSetMaxStamina(server, player, max)
  if not self.sv then
    return nil
  end
  max = math.max(1, math.floor(max))
  local st = self.sv.walkers[player.id]
  if st then
    local gained = max - st.max
    st.max = max
    st.stamina = math.min(max, gained > 0 and st.stamina + gained or st.stamina)
  end
  self.sv.maxStamina[player.id] = max
  server:broadcast(Protocol.encode("OF_MAX", player.id, max))
  return max
end

--- Died on foot (weapons blew up the body): a splat where they stood. The
--- respawn is weapons' business, the same as for a driver.
function OnFoot:serverKill(server, kill)
  if kill.kind == "car" and kill.onFoot and kill.victim then
    server:broadcast(Protocol.encode("OF_GIB", kill.victim, ("%.0f"):format(kill.x), ("%.0f"):format(kill.y),
      ("%.3f"):format(kill.angle or 0)))
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

--- Step out beside the car. `force` ignores how fast it is going (a map
--- with no vehicles turns everyone out the moment they are behind a wheel).
function OnFoot:getOut(server, player, force)
  local car = player.vehicle
  if not car then
    return false
  end
  if not force and math.abs(car.speed) > self.exitMaxSpeed then
    return false -- still moving too fast to step out
  end
  local x, y = self:exitSpot(car)
  server:unseat(player, x, y)
  local st = self:walker(player)
  st.stamina, st.spent, st.regenIn = st.max, false, 0
  st.move.x, st.move.y, st.move.sprint = 0, 0, false
  st.dash = nil
  return true
end

--- Into the nearest car within reach that nobody is driving, on a map
--- where anyone may drive.
function OnFoot:getIn(server, player)
  if not vehiclesAllowed() or not player.body then
    return false
  end
  local b = player.body
  for _, car in pairs(server.vehicles) do
    if not (car.driver or car.hidden or car.stowed) and Car.hitTest(car, b.x, b.y, self.enterReach) then
      return server:seat(player, car)
    end
  end
  return false
end

--- Back on a map with vehicles (city-map's `mapChanged`; the host passes
--- `server`): every car stowed on the walking map is back in the world.
--- City-map has already seated everyone in their own car at the spawns.
function OnFoot:mapChanged(map, server)
  if not (server and self.sv) or map.vehicles == false then
    return
  end
  for _, car in pairs(server.vehicles) do
    car.stowed = false
  end
end

--- One walker's step: spend or regain stamina, then walk. Leaning on the
--- sprint key with an empty bar keeps it empty; you get your breath back by
--- letting go, not by running on.
function OnFoot:walk(st, body, dt)
  local mx, my = st.move.x, st.move.y
  local len = math.sqrt(mx * mx + my * my)
  local asking = len > 0 and st.move.sprint
  local sprinting = asking and st.stamina > 0 and not st.spent
  if sprinting then
    st.stamina = math.max(0, st.stamina - self.sprintDrain * dt)
    st.regenIn = self.regenDelay
    if st.stamina <= 0 then
      st.spent = true
    end
  elseif asking then
    st.regenIn = self.regenDelay -- still leaning on it: no breath back yet
  else
    st.regenIn = math.max(0, st.regenIn - dt)
    if st.regenIn <= 0 then
      st.stamina = math.min(st.max, st.stamina + st.regen * dt)
      if st.spent and st.stamina >= self.recovered then
        st.spent = false
      end
    end
  end

  if st.dash then
    -- Mid-dodge: the dash carries them, whatever the keys say.
    local d = st.dash
    local slice = math.min(dt, d.t) -- the last step only goes as far as is left
    body.x, body.y = step(body.x, body.y, d.x, d.y, self.dodgeDistance / self.dodgeTime, slice)
    d.t = d.t - dt
    if d.t <= 0 then
      st.dash = nil
    end
    st.regenIn = self.regenDelay
  elseif len > 0 then
    local speed = sprinting and self.sprintSpeed or self.walkSpeed
    body.x, body.y = step(body.x, body.y, mx / len, my / len, speed, dt)
  end
end

--- A dodge for `player` in direction (dx, dy), if they are on foot, free,
--- rested and not still recovering from the last one. Returns true if it
--- started. Everyone hears OF_DODGED for the dust.
function OnFoot:serverDodge(server, player, dx, dy)
  local sv = self.sv
  if not (sv and player.body) or player.vehicle or player.body.dead then
    return false
  end
  if Features.any("serverHeld", server, player) then
    return false -- held still (frozen)
  end
  local len = math.sqrt(dx * dx + dy * dy)
  if len < 0.5 then
    return false -- no direction
  end
  dx, dy = dx / len, dy / len
  local st = self:walker(player)
  if st.dash or sv.time < st.dodgeReadyAt or st.stamina < self.dodgeStamina then
    return false
  end
  st.stamina = st.stamina - self.dodgeStamina
  st.regenIn = self.regenDelay
  st.dash = { x = dx, y = dy, t = self.dodgeTime }
  st.dodgeReadyAt = sv.time + self.dodgeCooldown
  local b = player.body
  server:broadcast(Protocol.encode("OF_DODGED", player.id, ("%.0f"):format(b.x), ("%.0f"):format(b.y),
    ("%.2f"):format(dx), ("%.2f"):format(dy)))
  return true
end

function OnFoot:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  sv.time = sv.time + dt
  if not vehiclesAllowed() then
    -- Nobody drives here: anyone behind a wheel (just arrived, or just
    -- respawned in their car) is turned out where the car stands, and their
    -- own car is stowed out of the world. NPC drivers are parked out of
    -- sight by bots and left alone.
    for _, player in pairs(server.players) do
      if not player.bot and player.body and not player.body.dead then
        if player.vehicle then
          self:getOut(server, player, true)
        end
        if player.car then
          player.car.stowed = true
        end
      end
    end
  end
  local parts, n = { server.tick }, 0
  for id, player in pairs(server.players) do
    if player.body and not player.vehicle and not player.body.dead then
      local st = self:walker(player)
      if not Features.any("serverHeld", server, player) then
        self:walk(st, player.body, dt) -- a held walker (frozen) stays put
      end
      n = n + 1
      parts[#parts + 1] = id
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
    if not OnFoot.sv or not Features.present(player) then
      return -- wrecked, or the game hasn't started
    end
    if Features.any("serverHeld", server, player) then
      return -- held still (frozen): no climbing in or out
    end
    if player.vehicle then
      OnFoot:getOut(server, player)
    else
      OnFoot:getIn(server, player)
    end
  end,
  OF_DODGE = function(server, player, args)
    local dx, dy = tonumber(args[1]), tonumber(args[2])
    if dx and dy then
      OnFoot:serverDodge(server, player, dx, dy)
    end
  end,
  OF_MOVE = function(_server, player, args)
    if not (OnFoot.sv and player.body) or player.vehicle then
      return -- they are driving; nothing to move
    end
    local st = OnFoot:walker(player)
    local seq = tonumber(args[1])
    if not seq or seq <= st.lastSeq then
      return -- stale or garbage
    end
    st.lastSeq = seq
    st.move.x = clamp(tonumber(args[2]) or 0, -1, 1)
    st.move.y = clamp(tonumber(args[3]) or 0, -1, 1)
    st.move.sprint = args[4] == "1"
    player.body.facing = tonumber(args[5]) or player.body.facing
  end,
}

return OnFoot
