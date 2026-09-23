-- Abilities: powers a character casts on the world. Hold the ability's key
-- and a target area follows the cursor, kept within the ability's range of
-- you; let go to cast it there, or right-click to think better of it. Each
-- ability then waits out its cooldown. For now everyone has the same one
-- ability, freeze (freeze.lua); character classes will hand out others
-- later, so an ability is a small module in this folder and this file is
-- the machinery around it: aiming, cooldowns, the HUD, and holding things
-- still on the host.
--
-- Holding: the host keeps a frozen player or car where it is by putting it
-- back every tick after everything else has moved it (this feature runs
-- last), and answers `serverHeld(server, player)` so on-foot stops walking
-- them and weapons stops their gun. Clients hear who is held and answer
-- `held(client, id)` the same way, so prediction and the HUD agree. Another
-- feature can hold a player through Features.byName.abilities:serverHold.
--
-- Messages
--   client -> server  ABL_CAST  <slot> <x> <y>
--   server -> all     ABL_FIRED <by> <slot> <x> <y> <seconds> [<heldId>]...

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Controls = require("src.controls")
local UI = require("src.ui")
local Car = require("src.car")
local Body = require("src.body")
local Sounds = require("src.features.abilities.sounds")
local Freeze = require("src.features.abilities.freeze")

local Abilities = {
  name = "abilities",
  priority = 990, -- last: holds override every other mover; the aim ring draws over everything
}

Abilities.slots = { Freeze } -- slot i is cast with action "ability-<i>"
Abilities.defaultKeys = { "q" }
-- The ability circles along the bottom centre of the screen: `hudSlots` of
-- them, `hudStep` apart, empty ones dim until a release fills them.
Abilities.hudSlots = 4
Abilities.hudStep = 64
Abilities.hudRadius = 24
Abilities.hudBottom = 48 -- px up from the bottom edge to the circles' centres

local function dist2(ax, ay, bx, by)
  local dx, dy = ax - bx, ay - by
  return dx * dx + dy * dy
end

-- Client --------------------------------------------------------------------

Abilities.camera = nil -- last camera seen in update, to put the cursor in the world
Abilities.time = 0
Abilities.aiming = nil -- slot index while its key is held
Abilities.spent = nil -- slot whose key must be released before it aims again (cancelled)
Abilities.cooldowns = {} -- slot -> seconds left
Abilities.readyFlash = {} -- slot -> seconds of "it's back" flash left on the HUD
Abilities.effects = {} -- { ability, x, y, t, seconds }
Abilities.heldUntil = {} -- player id -> client time their hold ends

function Abilities:load()
  for i, ability in ipairs(self.slots) do
    Controls.register("ability-" .. i, ("Ability %d: %s"):format(i, ability.title), self.defaultKeys[i])
  end
  Controls.register("ability-cancel", "Cancel ability", "mouse2")
  Sounds.load()
end

function Abilities:enterGame()
  self.camera = nil
  self.time = 0
  self.aiming = nil
  self.spent = nil
  self.cooldowns = {}
  self.readyFlash = {}
  self.effects = {}
  self.heldUntil = {}
end

function Abilities:exitGame()
  self:enterGame()
end

--- Is this player held still, as far as this machine knows? The `held`
--- convention: on-foot and weapons ask every feature.
function Abilities:held(_client, id)
  return (self.heldUntil[id] or 0) > self.time
end

--- The cursor in world space, inverting the game state's draw transform.
local function mouseToWorld(camera, ox, oy)
  local mx, my = love.mouse.getPosition()
  local w, h = love.graphics.getDimensions()
  local cx, cy, s = ox, oy, 1
  if camera then
    cx, cy, s = camera.x, camera.y, camera.scale or 1
  end
  return cx + (mx - w / 2) / s, cy + (my - h / 2) / s
end

--- Where the ability would land: the cursor, pulled back to within its
--- range of me. Nil while I am out of the world.
function Abilities:target(client, ability)
  local ox, oy = client:myPose()
  if not ox then
    return nil
  end
  local x, y = mouseToWorld(self.camera, ox, oy)
  local d = math.sqrt(dist2(x, y, ox, oy))
  if d > ability.range then
    x, y = ox + (x - ox) / d * ability.range, oy + (y - oy) / d * ability.range
  end
  return x, y
end

function Abilities:cast(client, slot)
  local x, y = self:target(client, self.slots[slot])
  if x then
    client:send(Protocol.encode("ABL_CAST", slot, ("%.1f"):format(x), ("%.1f"):format(y)))
  end
end

function Abilities:update(dt, client, camera)
  self.camera = camera
  self.time = self.time + dt
  for slot, left in pairs(self.cooldowns) do
    if left - dt > 0 then
      self.cooldowns[slot] = left - dt
    else
      self.cooldowns[slot] = nil
      self.readyFlash[slot] = 0.6
    end
  end
  for slot, left in pairs(self.readyFlash) do
    self.readyFlash[slot] = left - dt > 0 and left - dt or nil
  end
  for i = #self.effects, 1, -1 do
    local e = self.effects[i]
    e.t = e.t + dt
    if e.t > e.seconds + e.ability.afterglow then
      table.remove(self.effects, i)
    end
  end

  local canAim = client:myPose() ~= nil and not self:held(client, client.myId)
  for i in ipairs(self.slots) do
    local down = Controls.isDown("ability-" .. i)
    if self.aiming == i then
      if Controls.suspended or Controls.isDown("ability-cancel") then
        self.aiming, self.spent = nil, i -- the menu came up, or they changed their mind
      elseif not down then
        self.aiming = nil
        self:cast(client, i)
      end
    elseif down and not self.aiming and self.spent ~= i and canAim and not self.cooldowns[i] then
      self.aiming = i
    end
    if not down and self.spent == i then
      self.spent = nil
    end
  end
end

--- The aim ring while a key is held, then every effect in the world and a
--- glaze over whoever is held.
function Abilities:drawAboveCars(client)
  local ability = self.aiming and self.slots[self.aiming]
  if ability then
    local ox, oy = client:myPose()
    local x, y = self:target(client, ability)
    if x then
      local c = ability.color
      love.graphics.setLineWidth(1)
      love.graphics.setColor(c[1], c[2], c[3], 0.18)
      love.graphics.circle("line", ox, oy, ability.range, 64)
      love.graphics.setColor(c[1], c[2], c[3], 0.16)
      love.graphics.circle("fill", x, y, ability.radius, 48)
      love.graphics.setLineWidth(2)
      love.graphics.setColor(c[1], c[2], c[3], 0.85)
      love.graphics.circle("line", x, y, ability.radius, 48)
      love.graphics.setLineWidth(1)
    end
  end
  for _, e in ipairs(self.effects) do
    e.ability.drawEffect(e)
  end
  for id in pairs(self.heldUntil) do
    if self:held(client, id) then
      local px, py, onFoot = client:pose(id)
      if px then
        Freeze.drawHeld(px, py, onFoot and Body.RADIUS + 4 or Car.WIDTH * 0.62, self.time)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Abilities:drawHUD(client)
  -- A row of circles along the bottom centre, one per slot. The key sits
  -- in the circle and the title under it; on cast the ring empties and
  -- fills back up through the cooldown with the seconds left inside. Full
  -- and lit means ready. Slots with no ability yet are just dim rings.
  local small, body = UI.fonts.small, UI.fonts.body
  local w, h = love.graphics.getDimensions()
  local r, n = self.hudRadius, math.max(self.hudSlots, #self.slots)
  local cy = h - self.hudBottom
  local x0 = math.floor(w / 2 - (n - 1) * self.hudStep / 2)
  for i = 1, n do
    local cx = x0 + (i - 1) * self.hudStep
    local ability = self.slots[i]
    if not ability then
      UI.ring(cx, cy, r, 0, { 1, 1, 1 }, 4)
    else
      local key = Controls.name(Controls.bindings("ability-" .. i)[1])
      local left = self.cooldowns[i]
      local c = ability.color
      local middle, middleColor, title, titleColor
      if left then
        UI.ring(cx, cy, r, 1 - left / ability.cooldown, { c[1], c[2], c[3], 0.85 }, 5)
        middle = left >= 10 and ("%d"):format(left) or ("%.1f"):format(left)
        middleColor = { 1, 1, 1 }
        title, titleColor = ability.title, { 0.7, 0.7, 0.75 }
      else
        local flash = self.readyFlash[i]
        if flash then
          -- Just back: a burst swelling out of the ring and fading.
          local k = flash / 0.6
          love.graphics.setLineWidth(2)
          love.graphics.setColor(c[1], c[2], c[3], 0.8 * k)
          love.graphics.circle("line", cx, cy, r + 5 + (1 - k) * 18, 48)
          love.graphics.setLineWidth(1)
        end
        local aiming = self.aiming == i
        local pulse = aiming and (0.5 + 0.5 * math.sin(self.time * 10)) or 0
        love.graphics.setColor(c[1], c[2], c[3], 0.2 + 0.3 * pulse)
        love.graphics.circle("fill", cx, cy, r + 6, 48)
        UI.ring(cx, cy, r, 1, c, 5)
        middle, middleColor = key, { 1, 1, 1 }
        title = aiming and "release" or ability.title
        titleColor = aiming and c or { 0.9, 0.9, 0.95 }
      end
      love.graphics.setFont(body)
      UI.label(middle, cx - math.floor(body:getWidth(middle) / 2), cy - math.floor(body:getHeight() / 2), middleColor)
      love.graphics.setFont(small)
      UI.label(title, cx - math.floor(small:getWidth(title) / 2), cy + r + 4, titleColor)
    end
  end
  if self:held(client, client.myId) then
    love.graphics.setFont(body)
    local c = Freeze.color
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("FROZEN", 1, 89, w, "center")
    love.graphics.setColor(c[1], c[2], c[3])
    love.graphics.printf("FROZEN", 0, 88, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

Abilities.clientMessages = {
  ABL_FIRED = function(client, args)
    local by, slot = tonumber(args[1]), tonumber(args[2])
    local x, y, seconds = tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    local ability = slot and Abilities.slots[slot]
    if not (ability and x and y and seconds) then
      return
    end
    Abilities.effects[#Abilities.effects + 1] = { ability = ability, x = x, y = y, t = 0, seconds = seconds }
    for i = 6, #args do
      local id = tonumber(args[i])
      if id then
        Abilities.heldUntil[id] = Abilities.time + seconds
      end
    end
    if by == client.myId then
      Abilities.cooldowns[slot] = ability.cooldown
    end
    Sounds.play(ability.sound, x, y)
  end,
}

-- Server --------------------------------------------------------------------

Abilities.sv = nil

function Abilities:serverStart()
  self.sv = {
    time = 0,
    readyAt = {}, -- player id -> slot -> time the ability may be cast again
    players = {}, -- player id -> time their hold ends
    bodies = {}, -- player id -> { until, x, y }: a walker kept on the spot
    cars = {}, -- vehicle id -> { until, x, y, angle }: a car kept on the spot
  }
end

function Abilities:serverPlayerLeft(_server, player)
  local sv = self.sv
  if sv then
    sv.readyAt[player.id], sv.players[player.id], sv.bodies[player.id] = nil, nil, nil
  end
end

--- Everything moved to a new map: nothing is held there.
function Abilities:mapChanged(_map, server)
  if server and self.sv then
    self.sv.players, self.sv.bodies, self.sv.cars = {}, {}, {}
  end
end

--- The `serverHeld` convention: is this player held still on the host?
function Abilities:serverHeld(_server, player)
  local sv = self.sv
  return sv ~= nil and (sv.players[player.id] or 0) > sv.time
end

--- Keep a car where it stands for `seconds`, whoever is in it.
function Abilities:serverHoldCar(_server, car, seconds)
  local sv = self.sv
  if not (sv and car) then
    return
  end
  local h = sv.cars[car.id]
  local untilT = sv.time + seconds
  if h and h.untilT >= untilT then
    return -- already held for longer
  end
  sv.cars[car.id] = { untilT = untilT, x = car.x, y = car.y, angle = car.angle }
  car:stop()
end

--- Hold a player still for `seconds`: their car if they are driving, their
--- feet if not, and their trigger finger either way. Other features reach
--- this via Features.byName.abilities.
function Abilities:serverHold(server, player, seconds)
  local sv = self.sv
  if not (sv and Features.present(player)) then
    return false
  end
  sv.players[player.id] = math.max(sv.players[player.id] or 0, sv.time + seconds)
  if player.vehicle then
    self:serverHoldCar(server, player.vehicle, seconds)
  else
    local b = player.body
    local h = sv.bodies[player.id]
    if not (h and h.untilT >= sv.time + seconds) then
      sv.bodies[player.id] = { untilT = sv.time + seconds, x = b.x, y = b.y }
    end
  end
  return true
end

--- Put everything held back where it was when the hold began. Runs after
--- every other feature's step, so this is the last word before STATE.
function Abilities:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for vid, h in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if not car or h.untilT <= sv.time or car.hidden or car.stowed then
      sv.cars[vid] = nil
    else
      car.x, car.y, car.angle = h.x, h.y, h.angle
      car:stop()
    end
  end
  for id, h in pairs(sv.bodies) do
    local player = server.players[id]
    if not player or h.untilT <= sv.time or player.vehicle or not Features.present(player) then
      sv.bodies[id] = nil
    else
      player.body.x, player.body.y = h.x, h.y
    end
  end
  for id, untilT in pairs(sv.players) do
    if untilT <= sv.time then
      sv.players[id] = nil
    end
  end
end

Abilities.serverMessages = {
  ABL_CAST = function(server, player, args)
    local sv = Abilities.sv
    local slot = tonumber(args[1])
    local x, y = tonumber(args[2]), tonumber(args[3])
    local ability = slot and Abilities.slots[slot]
    if not (sv and ability and x and y) or not Features.present(player) then
      return
    end
    if Abilities:serverHeld(server, player) then
      return -- frozen people cast nothing
    end
    local ready = sv.readyAt[player.id]
    if not ready then
      ready = {}
      sv.readyAt[player.id] = ready
    end
    if (ready[slot] or 0) > sv.time then
      return -- still cooling down; the client knows, so this was a stale or forged cast
    end
    -- Never further than the ability reaches, whatever the client said.
    local ox, oy = Features.bodyPose(server, player)
    local d = math.sqrt(dist2(x, y, ox, oy))
    if d > ability.range then
      x, y = ox + (x - ox) / d * ability.range, oy + (y - oy) / d * ability.range
    end
    ready[slot] = sv.time + ability.cooldown
    local held = ability.serverCast(server, player, x, y, Abilities)
    server:broadcast(Protocol.encode("ABL_FIRED", player.id, slot, ("%.1f"):format(x), ("%.1f"):format(y),
      ("%.2f"):format(ability.seconds), unpack(held)))
  end,
}

return Abilities
