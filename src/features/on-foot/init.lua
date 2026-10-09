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
-- The local player is predicted (OnFoot:advance is the host's own step,
-- run here too): every move moves my copy at once and is kept, the host
-- applies each move once, a tick each, and says where it has me after the
-- last one (OF_YOU); the copy starts again from there, replays the rest and
-- fades the difference in, so walking, sprinting and dodging answer the keys
-- at once however far away the host is.
--
-- A car you get out of stops where it is and stays there for anyone to
-- take. On a map with no vehicles (city-map's `map.vehicles`), everyone is
-- turned out and their cars are stowed: out of the world, off every
-- screen, until the group is back on a map with roads worth driving.
--
-- Low on breath (under `breathBelow` of your stamina, on foot) a cold blue
-- halo creeps in from the screen's edges, stronger the less is left and
-- strongest while you are winded, swelling and fading slowly like heavy
-- breathing; the stamina bar flashes with it. It is the low-health halo's
-- twin (weapons), drawn from `drawLens` the same way, under the HUD.
--
-- Movement reuses the driving bindings (W A S D by default) as plain world
-- directions and you face the cursor, so aiming and walking are independent.
-- Space (the dodge action) dashes you the way you are walking, or the way
-- you face when standing still: a short dash, faster than a sprint, for
-- some stamina and a moment's cooldown. It shares its default key with the
-- handbrake, which only matters in a car. The host
-- does the dash (and refuses one you can't afford); your own is predicted
-- like a step, so it feels instant, and everyone sees the dust.
--
-- Stamina has a ceiling per player, maxStamina to start with, and comes back
-- at a rate per player, staminaRegen to start with; another feature can
-- raise either (upgrades sells both) through OnFoot:serverSetMaxStamina and
-- OnFoot:serverSetStaminaRegen. Only the host needs the rate, so it is
-- never sent; the bar the client sees already reflects it. How far a dodge
-- carries you is per player too, dodgeDistance to start with, raised
-- through OnFoot:serverSetDodgeScale (the gym sells it); that one is sent
-- (OF_DASH), since each client predicts its own dash. Walking pace (not the
-- sprint) is per player the same way: walkSpeed to start with, raised
-- through OnFoot:serverSetWalkScale (the gym sells that too) and sent
-- (OF_WALK) so each client predicts its own steps.
--
-- Messages
--   client -> server  OF_TOGGLE
--   client -> server  OF_MOVE  <seq> <facing> [<mx> <my> <sprint> <dodge x> <dodge y>]x3  (unreliable, 30 Hz;
--                     this move and the two before it; a dodge rides in the move it was pressed in)
--   client -> server  OF_DODGE <dx> <dy>                         the dodge key, to a host without OF_YOU
--   server -> walker  OF_YOU <tick> <applied> <x> <y> <stamina> <spent> <regenIn> <dash x> <dash y> <dash t>
--                     <cooldown> <max> <regen> <pinned>   where the host has me, for my prediction (unreliable)
--   server -> all     OF_DODGED <id> <x> <y> <dx> <dy>           they dashed from here, this way
--   server -> all     OF_STATE <tick> [<id> <stamina>]...  (unreliable; everyone on foot)
--   server -> all     OF_GIB   <id> <x> <y> <angle> <type>   died on foot here, of that damage type
--   server -> all     OF_MAX   <id> <max>       their stamina ceiling changed
--   server -> all     OF_DASH  <id> <scale>     their dodge carries them dodgeDistance * scale
--   server -> all     OF_WALK  <id> <scale>     they walk at walkSpeed * scale

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
OnFoot.moveQueue = 6 -- moves a walker may have waiting on the host; more and the oldest go

OnFoot.breathBelow = 0.3 -- under this share of my stamina the blue halo creeps in...
OnFoot.breathFaint = 0 -- ...from nothing at the line, so hovering on it does not flicker...
OnFoot.breathFull = 0.45 -- ...and this strong with none left, or winded
OnFoot.breath = 0 -- how strong it is now, easing towards what my stamina says (client)

-- Slots in the HUD's bottom-left row of stat bars (UI.drawStatBar): health
-- is 0 (weapons), then stamina and the dodge; abilities carry on from there.
OnFoot.hudSlot = 1

local MOVE_INTERVAL = 1 / 30 -- seconds between OF_MOVE packets
local CORRECTION = 6 -- per second; how fast the loose prediction (no OF_YOU yet) is pulled onto the server
local SNAP = 120 -- px; a correction bigger than this is a teleport
local CORRECT = 10 -- per second; how fast a correction of the replayed prediction fades in
local MOVE_REPEAT = 3 -- moves in each OF_MOVE: this one and the ones before it
local KEEP = 90 -- moves kept for replay at most (3 s)

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
OnFoot.dashOf = {} -- player id -> dodge distance scale (absent = 1)
OnFoot.walkOf = {} -- player id -> walking pace scale (absent = 1)
OnFoot.stamina = {} -- player id -> stamina, as the host last said (walkers only)
OnFoot.moveTimer = 0
OnFoot.moveSeq = 0
OnFoot.hitbox = {} -- reused table for the "is that car within reach?" test
OnFoot.dash = nil -- { x, y, t }: my own dodge under way, predicted
OnFoot.dodgeReadyAt = 0 -- client time my next dodge may start
OnFoot.puffs = {} -- { x, y, dx, dy, t }: dust where somebody dodged
OnFoot.dodgeHeld = false -- the dodge key is down since the press that counted; its repeats don't
local spent = false -- my breath, for prediction: an emptied bar sprints again only once recovered
local time = 0 -- client clock, seconds in the game

local haloImage = nil -- white, clear in the middle and opaque at the edges; tinted blue when drawn

--- The halo's picture: a soft oval of nothing inside a white rim that
--- thickens into the corners (the same shape as weapons' low-health one).
local function makeHalo()
  local n = 128
  local data = love.image.newImageData(n, n)
  for y = 0, n - 1 do
    for x = 0, n - 1 do
      local nx, ny = (x + 0.5) / n * 2 - 1, (y + 0.5) / n * 2 - 1
      local k = math.max(0, math.min(1, (math.sqrt(nx * nx + ny * ny) - 0.55) / 0.75))
      data:setPixel(x, y, 1, 1, 1, k * k * (3 - 2 * k)) -- smoothstep
    end
  end
  local image = love.graphics.newImage(data)
  image:setFilter("linear", "linear")
  return image
end

function OnFoot:load()
  haloImage = makeHalo()
  Controls.register("enter-exit", "Enter / exit vehicle", "f") -- the action key: real-estate and buildings share it
  Controls.register("sprint", "Sprint (on foot)", "lshift", "rshift")
  Controls.register("dodge", "Dodge (on foot)", "space") -- shared with the handbrake: one on foot, one in a car
end

function OnFoot:enterGame()
  self.moveTimer = 0
  self.moveSeq = 0
  self.dash, self.puffs = nil, {}
  self.pred, self.pendingDodge, self.sentMoves, self.youTick = nil, nil, nil, 0
  self.dodgeHeld = false
  self.dodgeReadyAt = 0
  self.breath = 0
  spent = false
  time = 0
end

function OnFoot:exitGame()
  self.maxOf = {}
  self.dashOf = {}
  self.walkOf = {}
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

--- What scales my own step, as the host's serverScales scales it there.
function OnFoot:myScales(client)
  local id = client.myId
  return {
    speed = Features.reduce("stat", 1, client, id, "speed"),
    drain = Features.reduce("stat", 1, client, id, "stamina"),
    walk = self.walkOf[id] or 1,
    dash = self.dashOf[id] or 1,
  }
end

-- My own walker, driven here ahead of the host. Every move I send also
-- moves the copy a tick with OnFoot:advance (the host's own step) and is
-- kept; OF_YOU says where the host has me after the last move it applied,
-- with my stamina, breath, dash and dodge cooldown, and the copy starts
-- again from there and replays the moves the host hasn't got to. What that
-- moves me by fades in (CORRECT) instead of jumping; more than SNAP is a
-- jump (a respawn). Like the car's (src/net/predict.lua). Until the first
-- OF_YOU (a host from before it) the loose prediction below stands in.

--- One tick of the copy: the dodge in `move`, if it can, then the step.
function OnFoot:predictStep(p, client, move, dt)
  local st = p.st
  local held = Features.any("held", client, client.myId) or p.pinned
  if move.dodge and not held and self:canDodge(st, st.cooling) then
    self:startDodge(st, move.dodge.x, move.dodge.y)
    st.cooling = self.dodgeCooldown
  end
  if not held then
    p.running = self:advance(st, p.pos, move, dt, self:myScales(client)) or st.dash ~= nil
  else
    p.running = false
  end
  st.cooling = math.max(0, st.cooling - dt)
end

--- OF_YOU: start the copy again from the host's word and replay the rest.
function OnFoot:onYou(client, args)
  local me = self:me(client)
  local tick, applied = tonumber(args[1]), tonumber(args[2])
  local x, y = tonumber(args[3]), tonumber(args[4])
  if not (me and tick and applied and x and y) or tick <= (self.youTick or 0) then
    return
  end
  self.youTick = tick
  local p = self.pred
  if not p then
    p = { pos = { x = x, y = y }, prev = { x = x, y = y }, ox = 0, oy = 0, history = {}, st = {} }
    self.pred = p
  end
  local oldX, oldY = p.pos.x, p.pos.y
  local st = p.st
  st.stamina, st.spent, st.regenIn = tonumber(args[5]) or 0, args[6] == "1", tonumber(args[7]) or 0
  local dt = tonumber(args[10]) or 0
  st.dash = dt > 0 and { x = tonumber(args[8]) or 0, y = tonumber(args[9]) or 0, t = dt } or nil
  -- The host counts its cooldown from the tick it reported; the copy has
  -- already taken that tick off.
  st.cooling = math.max(0, (tonumber(args[11]) or 0) - MOVE_INTERVAL)
  st.max, st.regen = tonumber(args[12]) or self.maxStamina, tonumber(args[13]) or self.staminaRegen
  p.pinned = args[14] == "1" -- shoved or held: the host moves me, not my keys
  p.pos.x, p.pos.y = x, y
  local keep = {}
  for _, move in ipairs(p.history) do
    if move.seq > applied then
      keep[#keep + 1] = move
    end
  end
  p.history = keep
  if not p.pinned then
    for _, move in ipairs(keep) do
      self:predictStep(p, client, move, MOVE_INTERVAL)
    end
  end
  local ex, ey = oldX - p.pos.x, oldY - p.pos.y
  if ex * ex + ey * ey > SNAP * SNAP then
    p.ox, p.oy = 0, 0
    p.prev.x, p.prev.y = p.pos.x, p.pos.y
  else
    -- Carry what is drawn along, so nothing moves on screen this frame.
    p.ox, p.oy = p.ox + ex, p.oy + ey
    p.prev.x, p.prev.y = p.prev.x - ex, p.prev.y - ey
  end
end

--- Walk my own figure with the keys I am holding, then ease it back onto the
--- server's last word so a disagreement never lasts. The stand-in until the
--- host's first OF_YOU starts the replayed prediction.
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
    local reach = self.dodgeDistance * (self.dashOf[client.myId] or 1)
    me.dx, me.dy = step(me.dx, me.dy, d.x, d.y, reach / self.dodgeTime, slice)
    d.t = d.t - dt
    if d.t <= 0 then
      self.dash = nil
    end
    sprinting = true -- legs going: draw it running
  elseif (mx ~= 0 or my ~= 0) and not held then
    local scale = Features.reduce("stat", 1, client, client.myId, "speed") -- clothes (gear)
    local walk = self.walkSpeed * (self.walkOf[client.myId] or 1) -- the gym's
    local speed = (sprinting and self.sprintSpeed or walk) * scale
    me.dx, me.dy = step(me.dx, me.dy, mx, my, speed, dt)
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
  local dodge = self.pendingDodge
  self.pendingDodge = nil
  local move = { seq = self.moveSeq, x = mx, y = my, sprint = Controls.isDown("sprint"), dodge = dodge }
  -- This move and the ones before it, in case a packet is lost on the way.
  local sent = self.sentMoves or {}
  self.sentMoves = sent
  table.insert(sent, 1, move)
  sent[MOVE_REPEAT + 1] = nil
  local fields = { self.moveSeq, ("%.3f"):format(me.dangle or 0) }
  for _, m in ipairs(sent) do
    fields[#fields + 1] = ("%.3f"):format(m.x)
    fields[#fields + 1] = ("%.3f"):format(m.y)
    fields[#fields + 1] = m.sprint and 1 or 0
    fields[#fields + 1] = m.dodge and ("%.3f"):format(m.dodge.x) or 0
    fields[#fields + 1] = m.dodge and ("%.3f"):format(m.dodge.y) or 0
  end
  client:send(Protocol.encode("OF_MOVE", unpack(fields)), true)
  -- The same move moves my own copy a tick, kept for replay.
  local p = self.pred
  if p then
    p.history[#p.history + 1] = move
    if #p.history > KEEP then
      table.remove(p.history, 1)
    end
    p.prev.x, p.prev.y = p.pos.x, p.pos.y
    self:predictStep(p, client, move, MOVE_INTERVAL)
  end
end

--- Draw me from the copy: between its last two ticks as the next comes up,
--- plus what is left of the last correction (which fades).
function OnFoot:drawPredicted(dt, _client, me, p)
  me.predicted = true
  local k = math.exp(-CORRECT * dt)
  p.ox, p.oy = p.ox * k, p.oy * k
  local alpha = 1 - math.max(0, math.min(1, self.moveTimer / MOVE_INTERVAL))
  me.dx = p.prev.x + (p.pos.x - p.prev.x) * alpha + p.ox
  me.dy = p.prev.y + (p.pos.y - p.prev.y) * alpha + p.oy
  me.running = p.running
  me.dangle = self:cursorAngle(me.dx, me.dy)
  self.dash = p.st.dash -- the HUD's dodge bar
end

--- The dodge key: dash the way I am walking (the way I face if I am
--- standing still) if I am on foot, free, rested enough and not still
--- recovering from the last one. The host has the final word.
function OnFoot:tryDodge(client)
  local me = self:me(client)
  if not me or self.dash or time < self.dodgeReadyAt or Features.any("held", client, client.myId) then
    return false
  end
  local stamina = self.stamina[client.myId] or self.maxOf[client.myId] or self.maxStamina
  if stamina < self.dodgeStamina then
    return false
  end
  local dx, dy = moveInput()
  if dx == 0 and dy == 0 then
    local facing = me.dangle or 0
    dx, dy = math.cos(facing), math.sin(facing)
  end
  self.dodgeReadyAt = time + self.dodgeCooldown
  if self.pred then
    self.pendingDodge = { x = dx, y = dy } -- rides in the next move, here and on the host
  else
    self.dash = { x = dx, y = dy, t = self.dodgeTime }
    client:send(Protocol.encode("OF_DODGE", ("%.3f"):format(dx), ("%.3f"):format(dy)))
  end
  return true
end

--- How strong the low-stamina halo should be: nothing on foot over
--- `breathBelow` of my stamina or in a car, `breathFaint` just under it,
--- growing to `breathFull` as the last of it goes, and full while winded.
function OnFoot:breathTarget(client, onFoot)
  if not onFoot then
    return 0
  end
  local max = self.maxOf[client.myId] or self.maxStamina
  local frac = (self.stamina[client.myId] or max) / max
  if spent then
    return self.breathFull
  elseif frac >= self.breathBelow then
    return 0
  end
  local t = 1 - frac / self.breathBelow -- 0 just under the line, 1 at none left
  return self.breathFaint + (self.breathFull - self.breathFaint) * t
end

function OnFoot:update(dt, client, camera)
  time = time + dt
  -- Ease the halo in and out, slower than the health one: a dodge or a burst of sprint should not flash it.
  self.breath = self.breath + (self:breathTarget(client, self:me(client) ~= nil) - self.breath) * math.min(1, dt * 1.5)
  if not Controls.isDown("dodge") then
    self.dodgeHeld = false
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
    self.dash, self.pred = nil, nil -- in a car, or out of the world: the next walk starts afresh
    return
  end
  if self.pred then
    self:sendMove(dt, client, me)
    self:drawPredicted(dt, client, me, self.pred)
  else
    self:predict(dt, client, me)
    self:sendMove(dt, client, me)
  end
  -- The camera and the ears belong to the predicted body, a step ahead of
  -- where the game state anchored them this frame.
  camera.x, camera.y = me.dx, me.dy
  love.audio.setPosition(me.dx, 0, me.dy)
end

function OnFoot:keypressed(key, client)
  if Controls.is("enter-exit", key) and client then
    -- The action key is shared: a plot for sale or a building's square
    -- underfoot has first call on it (`actionTaken`, docs/features.md).
    if not Features.any("actionTaken", client) then
      client:send(Protocol.encode("OF_TOGGLE"))
    end
    return
  end
  -- The dodge key; held down it repeats its press, and a repeat is not a dodge.
  if Controls.is("dodge", key) and client and not self.dodgeHeld then
    self.dodgeHeld = true
    self:tryDodge(client)
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

--- The stamina and dodge bars of the bottom-left row. Dimmed while
--- driving: nothing to spend them on until you step out.
--- The low-stamina halo: cold blue creeping in from the edges of the
--- screen, over the world and under the HUD, swelling and fading like
--- heavy breathing, quicker the less breath is left.
function OnFoot:drawLens()
  if self.breath < 0.01 or not haloImage then
    return
  end
  local w, h = love.graphics.getDimensions()
  local urgency = math.max(0, (self.breath - self.breathFaint) / (self.breathFull - self.breathFaint))
  local pant = 0.88 + 0.12 * math.sin(time * (1.6 + 1.2 * urgency))
  love.graphics.setColor(0.35, 0.6, 1, self.breath * pant)
  love.graphics.draw(haloImage, 0, 0, 0, w / haloImage:getWidth(), h / haloImage:getHeight())
  love.graphics.setColor(1, 1, 1)
end

function OnFoot:drawStatBars(client, onFoot)
  local alpha = onFoot and 1 or 0.45
  local max = self.maxOf[client.myId] or self.maxStamina
  local stamina = onFoot and (self.stamina[client.myId] or max) or max
  local frac = math.max(0, math.min(1, stamina / max))
  local color = UI.rampColor(frac)
  local winded = onFoot and spent
  if winded then
    -- Winded: the bar throbs dim red until enough is back to sprint on.
    color = { 0.9, 0.3, 0.3, 0.45 + 0.25 * math.sin(time * 8) }
  elseif onFoot and frac < self.breathBelow then
    -- Running low: it flashes, as the health bar does when that is low.
    local blink = 0.5 + 0.5 * math.sin(time * 12)
    color = { color[1], color[2], color[3], 0.55 + 0.45 * blink }
  end
  local readout = winded and "winded" or ("%d"):format(stamina)
  UI.drawStatBar(self.hudSlot, "stamina", frac, color, readout, winded and { 1, 0.5, 0.45 } or { 1, 1, 1 },
    { self.dodgeStamina / max }, alpha)

  -- The dodge: lit when one is there for the taking, filling back up
  -- through the cooldown, dim red while there is no breath for one.
  local cooling = onFoot and math.max(0, self.dodgeReadyAt - time) or 0
  local dodgeColor, value, valueColor
  if not onFoot then
    dodgeColor = { 0.78, 0.65, 1, 0.9 }
  elseif self.dash then
    dodgeColor = { 1, 1, 1, 0.9 }
  elseif stamina < self.dodgeStamina then
    dodgeColor, value, valueColor = { 0.9, 0.3, 0.3, 0.4 }, "tired", { 1, 0.5, 0.45 }
  elseif cooling > 0 then
    dodgeColor, value, valueColor = { 1, 1, 1, 0.45 }, ("%.1f"):format(cooling), { 0.85, 0.85, 0.9 }
  else
    dodgeColor, value, valueColor = { 0.78, 0.65, 1, 0.9 }, "ready", { 0.85, 0.78, 1 }
  end
  local dfrac = self.dash and 1 or (1 - cooling / self.dodgeCooldown)
  UI.drawStatBar(self.hudSlot + 1, "dodge", dfrac, dodgeColor, value, valueColor, nil, alpha)
end

function OnFoot:drawHUD(client)
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local me = self:me(client)
  self:drawStatBars(client, me ~= nil)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0.8, 0.8, 0.85)
  if me then
    local sprintKey = Controls.name(Controls.bindings("sprint")[1])
    local dodgeKey = Controls.name(Controls.bindings("dodge")[1])
    local hint = sprintKey .. ": sprint   " .. dodgeKey .. ": dodge"
    if self:vehicleInReach(client, me) then
      hint = key .. ": get in   " .. hint
    end
    love.graphics.print(hint, 10, 136)
  else
    local car = client:myVehicle()
    if car and math.abs(car.speed) <= self.exitMaxSpeed then
      love.graphics.print(key .. ": get out", 10, 136)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

OnFoot.clientMessages = {
  OF_YOU = function(client, args)
    OnFoot:onYou(client, args)
  end,
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
  OF_DASH = function(_client, args)
    local id, scale = tonumber(args[1]), tonumber(args[2])
    if id and scale then
      OnFoot.dashOf[id] = scale
    end
  end,
  OF_WALK = function(_client, args)
    local id, scale = tonumber(args[1]), tonumber(args[2])
    if id and scale then
      OnFoot.walkOf[id] = scale
    end
  end,
  --- Somebody died on foot: the pedestrians' gibs and splat, if that feature is around.
  OF_DODGED = function(_client, args)
    local x, y, dx, dy = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    if x and y and dx and dy then
      OnFoot.puffs[#OnFoot.puffs + 1] = { x = x, y = y, dx = dx, dy = dy, t = 0 }
    end
  end,
  --- What is left of them is the damage feature's call, by what killed
  --- them (ash, a scorch mark, a splat); a splat if it isn't around.
  OF_GIB = function(_client, args)
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (x and y) then
      return
    end
    local damage = Features.byName.damage
    if damage and damage.deathAt then
      damage:deathAt(x, y, angle, args[5])
    elseif Features.byName.pedestrians then
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
    dash = {}, -- player id -> dodge distance scale (absent = 1)
    walk = {}, -- player id -> walking pace scale (absent = 1)
  }
end

--- A player joining a running game hears every raised stamina ceiling,
--- dodge and walking pace (OF_MAX, OF_DASH and OF_WALK are only sent when
--- one changes). Their own
--- walking record is made when needed.
function OnFoot:serverPlayerJoined(server, player)
  if not (self.sv and server.started) or player.bot then
    return
  end
  for id, max in pairs(self.sv.maxStamina) do
    server:send(player, Protocol.encode("OF_MAX", id, max))
  end
  for id, scale in pairs(self.sv.dash) do
    server:send(player, Protocol.encode("OF_DASH", id, ("%.3f"):format(scale)))
  end
  for id, scale in pairs(self.sv.walk) do
    server:send(player, Protocol.encode("OF_WALK", id, ("%.3f"):format(scale)))
  end
end

function OnFoot:serverPlayerLeft(_server, player)
  if self.sv then
    self.sv.walkers[player.id] = nil
    self.sv.maxStamina[player.id] = nil
    self.sv.regen[player.id] = nil
    self.sv.dash[player.id] = nil
    self.sv.walk[player.id] = nil
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

--- A walking player's stamina and ceiling on the host; nil for a driver,
--- who has no bar. Other features read it via Features.byName["on-foot"]
--- (the second wind ability does).
function OnFoot:serverStamina(player)
  if not self.sv or player.vehicle or not player.body then
    return nil
  end
  local st = self:walker(player)
  return st.stamina, st.max
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

--- Set how far a player's dodge carries them, as a multiple of
--- dodgeDistance, for the rest of the game; it takes the same dodgeTime, so
--- a longer dodge is a faster one. Other features reach this via
--- Features.byName["on-foot"] (upgrades does). Returns the scale set.
function OnFoot:serverSetDodgeScale(server, player, scale)
  if not self.sv then
    return nil
  end
  scale = math.max(0.1, scale)
  self.sv.dash[player.id] = scale
  server:broadcast(Protocol.encode("OF_DASH", player.id, ("%.3f"):format(scale)))
  return scale
end

--- Set how fast a player walks (not sprints), as a multiple of walkSpeed,
--- for the rest of the game. Other features reach this via
--- Features.byName["on-foot"] (upgrades does). Returns the scale set.
function OnFoot:serverSetWalkScale(server, player, scale)
  if not self.sv then
    return nil
  end
  scale = math.max(0.1, scale)
  self.sv.walk[player.id] = scale
  server:broadcast(Protocol.encode("OF_WALK", player.id, ("%.3f"):format(scale)))
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

--- Died on foot (weapons blew up the body): what is left of them where they
--- stood, by what did it (`kill.cause`). The respawn is weapons' business,
--- the same as for a driver.
function OnFoot:serverKill(server, kill)
  if kill.kind == "car" and kill.onFoot and kill.victim then
    server:broadcast(Protocol.encode("OF_GIB", kill.victim, ("%.0f"):format(kill.x), ("%.0f"):format(kill.y),
      ("%.3f"):format(kill.angle or 0), kill.cause or "bullet"))
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
  st.moves = nil -- what was queued before the drive is long out of date
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

--- What scales one walker's step on the host: clothes (gear) may make them
--- faster or their sprint cheaper, the gym walks them faster and dodges them
--- further. The client builds the same for itself (OnFoot:myScales).
function OnFoot:serverScales(server, player)
  return {
    speed = Features.reduce("serverStat", 1, server, player, "speed"),
    drain = Features.reduce("serverStat", 1, server, player, "stamina"),
    walk = self.sv.walk[player.id] or 1,
    dash = self.sv.dash[player.id] or 1,
  }
end

--- One walker's step, the same on the host and in my own prediction:
--- spend or regain stamina, then walk `pos` (x, y) by `move` ({ x, y,
--- sprint }) for `dt`, or let a dodge under way carry it. Leaning on the
--- sprint key with an empty bar keeps it empty; you get your breath back by
--- letting go, not by running on. `st` holds stamina, max, regen, regenIn,
--- spent and dash; `scales` is what serverScales gives.
function OnFoot:advance(st, pos, move, dt, scales)
  local mx, my = move.x, move.y
  local len = math.sqrt(mx * mx + my * my)
  local asking = len > 0 and move.sprint
  local sprinting = asking and st.stamina > 0 and not st.spent
  local speedScale, drainScale = scales.speed, scales.drain
  if sprinting then
    st.stamina = math.max(0, st.stamina - self.sprintDrain * drainScale * dt)
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
    local reach = self.dodgeDistance * scales.dash
    pos.x, pos.y = step(pos.x, pos.y, d.x, d.y, reach / self.dodgeTime, slice)
    d.t = d.t - dt
    if d.t <= 0 then
      st.dash = nil
    end
    st.regenIn = self.regenDelay
  elseif len > 0 then
    local walk = self.walkSpeed * scales.walk -- the gym's
    local speed = (sprinting and self.sprintSpeed or walk) * speedScale
    pos.x, pos.y = step(pos.x, pos.y, mx / len, my / len, speed, dt)
  end
  return sprinting
end

--- Can `st` dodge now (`cooling` seconds of the last one's cooldown left)?
function OnFoot:canDodge(st, cooling)
  return not st.dash and cooling <= 0 and st.stamina >= self.dodgeStamina
end

--- Start a dodge along the unit direction (dx, dy): its stamina, the dash.
function OnFoot:startDodge(st, dx, dy)
  st.stamina = st.stamina - self.dodgeStamina
  st.regenIn = self.regenDelay
  st.dash = { x = dx, y = dy, t = self.dodgeTime }
end

--- The host's step for one walker.
function OnFoot:walk(st, body, dt, server, player)
  self:advance(st, body, st.move, dt, self:serverScales(server, player))
end

--- A dodge for `player` in direction (dx, dy), if they are on foot, free,
--- rested and not still recovering from the last one. Returns true if it
--- started. Everyone hears OF_DODGED for the dust, and every feature
--- `serverDodged` (a dodge puts out a fire).
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
  if not self:canDodge(st, st.dodgeReadyAt - sv.time) then
    return false
  end
  self:startDodge(st, dx, dy)
  st.dodgeReadyAt = sv.time + self.dodgeCooldown
  local b = player.body
  server:broadcast(Protocol.encode("OF_DODGED", player.id, ("%.0f"):format(b.x), ("%.0f"):format(b.y),
    ("%.2f"):format(dx), ("%.2f"):format(dy)))
  Features.call("serverDodged", server, player)
  return true
end

--- Knock `player` (on foot) `distance` px along the unit direction (dx, dy)
--- over `seconds`, sliding along walls as a step does. A dodge under way is
--- cut short. The damage feature knocks people back this way (an impact, a
--- blast); it holds them for the while, so their own prediction waits for it.
function OnFoot:serverShove(_server, player, dx, dy, distance, seconds)
  if not (self.sv and player.body) or player.vehicle or player.body.dead or distance <= 0 then
    return false
  end
  local st = self:walker(player)
  seconds = math.max(0.05, seconds or 0.25)
  st.dash = nil
  st.shove = { x = dx, y = dy, speed = distance / seconds, t = seconds }
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
      -- Their next move off the queue (with none waiting the last one holds),
      -- and the dodge in it.
      local nextMove = st.moves and table.remove(st.moves, 1)
      if nextMove then
        st.move.x, st.move.y, st.move.sprint = nextMove.x, nextMove.y, nextMove.sprint
        st.applied = nextMove.seq
        if nextMove.dodge then
          self:serverDodge(server, player, nextMove.dodge.x, nextMove.dodge.y)
        end
      end
      if st.shove then
        -- Knocked back: carried along whatever holds them (a knock holds them).
        local s = st.shove
        local slice = math.min(dt, s.t)
        player.body.x, player.body.y = step(player.body.x, player.body.y, s.x, s.y, s.speed, slice)
        s.t = s.t - dt
        if s.t <= 0 then
          st.shove = nil
        end
      elseif not Features.any("serverHeld", server, player) then
        self:walk(st, player.body, dt, server, player) -- a held walker (frozen) stays put
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
  -- Each walker hears exactly where they are and how they stand after the
  -- last move applied, for their prediction to start again from.
  for _, player in pairs(server.players) do
    local st = sv.walkers[player.id]
    if st and st.applied and not player.bot and player.body and not player.vehicle and not player.body.dead then
      local d = st.dash
      local pinned = st.shove ~= nil or Features.any("serverHeld", server, player)
      server:send(player, Protocol.encode("OF_YOU", server.tick, st.applied, ("%.2f"):format(player.body.x),
        ("%.2f"):format(player.body.y), ("%.2f"):format(st.stamina), st.spent and 1 or 0, ("%.3f"):format(st.regenIn),
        d and ("%.3f"):format(d.x) or 0, d and ("%.3f"):format(d.y) or 0, d and ("%.3f"):format(d.t) or 0,
        ("%.3f"):format(math.max(0, st.dodgeReadyAt - sv.time)), ("%.2f"):format(st.max), ("%.3f"):format(st.regen),
        pinned and 1 or 0), true)
    end
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
  -- OF_MOVE <seq> <facing> then <mx> <my> <sprint> <dodge x> <dodge y> for
  -- <seq>, <seq - 1>, ...: the ones before come along in case their own
  -- packet was lost. Queued oldest first, each once, and taken one a tick
  -- (serverStep), so every one moves them exactly once: what their own
  -- prediction replays. A dodge rides in its move, so it starts on the same
  -- tick here as there.
  OF_MOVE = function(_server, player, args)
    if not (OnFoot.sv and player.body) or player.vehicle then
      return -- they are driving; nothing to move
    end
    local st = OnFoot:walker(player)
    local seq = tonumber(args[1])
    if not seq or seq <= st.lastSeq then
      return -- stale or garbage
    end
    player.body.facing = tonumber(args[2]) or player.body.facing
    local queue = st.moves or {}
    st.moves = queue
    for k = math.min(math.floor((#args - 2) / 5), 8) - 1, 0, -1 do
      local s, at = seq - k, 3 + k * 5
      if s > st.lastSeq then
        local dx, dy = tonumber(args[at + 3]) or 0, tonumber(args[at + 4]) or 0
        queue[#queue + 1] = {
          seq = s,
          x = clamp(tonumber(args[at]) or 0, -1, 1),
          y = clamp(tonumber(args[at + 1]) or 0, -1, 1),
          sprint = args[at + 2] == "1",
          dodge = (dx ~= 0 or dy ~= 0) and { x = dx, y = dy } or nil,
        }
      end
    end
    st.lastSeq = seq
    while #queue > OnFoot.moveQueue do
      table.remove(queue, 1)
    end
  end,
}

return OnFoot
