-- Weapons: left mouse button fires a projectile from your car toward the
-- cursor. The server owns projectiles, hit detection, health and respawns.
-- Clients predict projectile flight from WPN_SHOT and draw everything.
--
-- Messages
--   client -> server  WPN_FIRE <aimAngle>
--   server -> all     WPN_SHOT <pid> <owner> <x> <y> <vx> <vy>
--   server -> all     WPN_HIT  <pid> <victim> <hp>
--   server -> all     WPN_KILL <pid> <killer> <victim> <killerKills> <deathTime>
--   server -> all     WPN_HEALTH <id> <hp>          (a heal; no hit effects)
--   server -> all     WPN_STOP <pid>                (shot swallowed by a soft target)
--
-- A wrecked car explodes, vanishes for DEATH_TIME seconds, then respawns at
-- its slot with brief protection.
--
-- A player need not be in their car: a feature that takes them out of it
-- (on-foot) answers the `playerPose` / `clientPlayerPose` conventions, and
-- then shots leave from their body, hits land on it, and the car they parked
-- is not a target.

local Protocol = require("src.net.protocol")
local Car = require("src.car")
local UI = require("src.ui")
local Sounds = require("src.features.weapons.sounds")
local Explosions = require("src.features.weapons.explosions")
local Features = require("src.features")
local Controls = require("src.controls")
local Video = require("src.video")

local Weapons = {
  name = "weapons",
  priority = 950, -- after "vision" (900) so the camera is final when we aim
  PROJECTILE_SPEED = 900, -- px/s; other features (bots) read this to lead their shots
}

local PROJECTILE_SPEED = Weapons.PROJECTILE_SPEED -- shots fly exactly along the aim, regardless of car speed
local PROJECTILE_TTL = 1.2 -- seconds
local PROJECTILE_RADIUS = 3
local FIRE_COOLDOWN = 0.2 -- seconds between shots
local DAMAGE = 20
local MAX_HEALTH = 100
local SPAWN_PROTECTION = 1.5 -- seconds of invulnerability after respawn
local DEATH_TIME = 2.5 -- seconds a wreck stays gone before respawning
local SHAKE_RADIUS = 1100 -- px; explosions further away don't shake the screen
local SHAKE_MAX = 18
local MUZZLE_OFFSET = 26 -- px from car centre along the aim
local FOOT_MUZZLE = 14 -- px from a body on foot, which is smaller than a car
local FOOT_RADIUS = 8 -- px; how fat a player on foot is for hit tests
local SWEEP_STEP = 6 -- px between hit samples along a projectile's path per tick
local FEED_TIME = 3

--- Any feature may declare solid ground with a blocksPoint(x, y) hook (the
--- city map does). Bullets stop there, on both server and client.
local function blocked(x, y)
  for _, f in ipairs(Features.list) do
    if f.blocksPoint and f:blocksPoint(x, y) then
      return true
    end
  end
  return false
end

--- Everything shootable that isn't a car belongs to some other feature, so
--- ask them: a feature with a serverShotAt hook kills whatever of its own is
--- standing at (x, y) and returns true if it did (the pedestrians do). The
--- first one to answer swallows the bullet, which is why a single shot takes
--- one pedestrian out of a crowd rather than the whole queue.
local function shotSomething(server, x, y, by, angle)
  for _, f in ipairs(Features.list) do
    if f.serverShotAt and f:serverShotAt(server, x, y, PROJECTILE_RADIUS, by, angle) then
      return true
    end
  end
  return false
end

--- Where `player`'s body is on the host: their car, unless a feature has
--- taken them out of it and answers the `playerPose` convention (the on-foot
--- feature does). The third return says which of the two it is.
local function bodyPose(server, player)
  for _, f in ipairs(Features.list) do
    if f.playerPose then
      local x, y = f:playerPose(server, player)
      if x then
        return x, y, true
      end
    end
  end
  local car = player.car
  return car.x, car.y, false
end

--- The same question on a client, where the answer is what is drawn: the
--- `clientPlayerPose` convention, falling back to the car snapshot `c`.
local function clientPose(client, id, c)
  for _, f in ipairs(Features.list) do
    if f.clientPlayerPose then
      local x, y = f:clientPlayerPose(client, id)
      if x then
        return x, y
      end
    end
  end
  return c.dx, c.dy
end

-- Client state (also reset in enterGame) ------------------------------------

Weapons.projectiles = {} -- pid -> { x, y, vx, vy, age, owner }
Weapons.health = {} -- player id -> hp (absent = full)
Weapons.kills = {} -- player id -> kills
Weapons.hitFlash = {} -- player id -> seconds left
Weapons.feed = nil -- { text, t }
Weapons.cooldown = 0
Weapons.showHitboxes = false
Weapons.deadTimer = 0 -- seconds until my own car respawns (client)
Weapons.armed = false -- held fire only counts once the button has been seen released in-game
Weapons.camera = nil -- last camera seen in update; needed to aim through pans and zoom

function Weapons:load()
  Sounds.load()
  Controls.register("fire", "Fire", "mouse1")
  Controls.register("hitboxes", "Show hitboxes", "f1")
end

function Weapons:enterGame()
  self.projectiles = {}
  self.health = {}
  self.kills = {}
  self.hitFlash = {}
  self.feed = nil
  self.cooldown = 0
  self.camera = nil
  self.deadTimer = 0
  self.armed = false -- the click on "Start game" is still held on the first frame
  Explosions.clear()
end

function Weapons:exitGame()
  self:enterGame()
end

--- Mouse position in world space, inverting the game state's draw transform
--- (centre, scale, translate by -camera). Falls back to a centred camera.
local function mouseToWorld(camera, me)
  local mx, my = love.mouse.getPosition()
  local w, h = love.graphics.getDimensions()
  local cx, cy, s = me.dx, me.dy, 1
  if camera then
    cx, cy, s = camera.x, camera.y, camera.scale or 1
  end
  return cx + (mx - w / 2) / s, cy + (my - h / 2) / s
end

--- Angle from wherever I am -- car or feet -- to the cursor, in world space.
function Weapons:aimAngle(client)
  local me = client:myCar()
  if not me then
    return nil
  end
  local ox, oy = clientPose(client, client.myId, me)
  local wx, wy = mouseToWorld(self.camera, me)
  return math.atan2(wy - oy, wx - ox)
end

function Weapons:tryFire(client)
  if self.cooldown > 0 then
    return
  end
  local aim = self:aimAngle(client)
  if not aim then
    return
  end
  self.cooldown = FIRE_COOLDOWN
  client:send(Protocol.encode("WPN_FIRE", ("%.3f"):format(aim)))
end

function Weapons:mousepressed(_x, _y, button, client)
  if Controls.isMouse("fire", button) then
    self:tryFire(client)
  end
end

function Weapons:keypressed(key, client)
  if Controls.is("hitboxes", key) then
    self.showHitboxes = not self.showHitboxes
  elseif Controls.is("fire", key) then
    self:tryFire(client)
  end
end

function Weapons:update(dt, client, camera)
  self.camera = camera
  self.cooldown = math.max(0, self.cooldown - dt)
  local held = Controls.isDown("fire")
  if not held then
    self.armed = true
  elseif self.armed then
    self:tryFire(client)
  end
  for pid, p in pairs(self.projectiles) do
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.age = p.age + dt
    if p.age > PROJECTILE_TTL or blocked(p.x, p.y) then
      self.projectiles[pid] = nil
    end
  end
  for id, t in pairs(self.hitFlash) do
    if t - dt <= 0 then
      self.hitFlash[id] = nil
    else
      self.hitFlash[id] = t - dt
    end
  end
  if self.feed then
    self.feed.t = self.feed.t - dt
    if self.feed.t <= 0 then
      self.feed = nil
    end
  end
  self.deadTimer = math.max(0, self.deadTimer - dt)
  Explosions.update(dt)
  Explosions.shakeCamera(camera)
end

function Weapons:drawBelowCars()
  Explosions.drawBelow()
end

function Weapons:drawAboveCars(client)
  Explosions.drawAbove()

  -- Projectiles as short streaks along their direction of travel.
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.9, 0.3)
  for _, p in pairs(self.projectiles) do
    local len = math.sqrt(p.vx * p.vx + p.vy * p.vy)
    local nx, ny = p.vx / len * 10, p.vy / len * 10
    love.graphics.line(p.x - nx, p.y - ny, p.x, p.y)
  end
  love.graphics.setLineWidth(1)

  for id, c in pairs(client.cars) do
    -- Health bar under whoever owns the car, which is not always in it.
    local px, py = clientPose(client, id, c)
    local hp = self.health[id] or MAX_HEALTH
    local bw, bh = Car.WIDTH, 4
    local bx, by = px - bw / 2, py + Car.HEIGHT / 2 + 8
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
    love.graphics.setColor(1 - hp / MAX_HEALTH, hp / MAX_HEALTH, 0.2)
    love.graphics.rectangle("fill", bx, by, bw * hp / MAX_HEALTH, bh)

    if self.hitFlash[id] then
      love.graphics.setColor(1, 1, 1, self.hitFlash[id] * 4)
      love.graphics.circle("line", px, py, Car.WIDTH * 0.7)
    end
    if self.showHitboxes then
      love.graphics.push()
      love.graphics.translate(c.dx, c.dy)
      love.graphics.rotate(c.dangle)
      love.graphics.setColor(0.3, 1, 0.3, 0.9)
      love.graphics.rectangle("line", -Car.WIDTH / 2, -Car.HEIGHT / 2, Car.WIDTH, Car.HEIGHT)
      love.graphics.pop()
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Weapons:drawHUD(client)
  love.graphics.setFont(UI.fonts.small)
  local hp = self.health[client.myId] or MAX_HEALTH
  local kills = self.kills[client.myId] or 0
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(("HP %d   kills %d"):format(hp, kills), 10, 46)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local fireKey = Controls.name(Controls.bindings("fire")[1])
  local boxKey = Controls.name(Controls.bindings("hitboxes")[1])
  love.graphics.print(fireKey .. ": fire   " .. boxKey .. ": hitboxes", 10, 64)

  if self.feed then
    local w = love.graphics.getWidth()
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1, math.min(1, self.feed.t))
    love.graphics.printf(self.feed.text, 0, 40, w, "center")
  end
  if self.deadTimer > 0 then
    local w, h = love.graphics.getDimensions()
    love.graphics.setColor(0.5, 0, 0, 0.35)
    love.graphics.rectangle("fill", 0, 0, w, h)
    love.graphics.setFont(UI.fonts.title)
    love.graphics.setColor(1, 0.3, 0.2)
    love.graphics.printf("WRECKED", 0, h / 2 - 60, w, "center")
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1)
    love.graphics.printf(("respawning in %.1f"):format(self.deadTimer), 0, h / 2, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

local function playerName(client, id)
  local p = client.players[id]
  return p and p.name or ("#" .. tostring(id))
end

Weapons.clientMessages = {
  WPN_HEALTH = function(_client, args)
    local id, hp = tonumber(args[1]), tonumber(args[2])
    if id and hp then
      Weapons.health[id] = hp
    end
  end,
  WPN_STOP = function(_client, args)
    local pid = tonumber(args[1])
    if pid then
      Weapons.projectiles[pid] = nil
    end
  end,
  WPN_SHOT = function(_client, args)
    local pid, owner = tonumber(args[1]), tonumber(args[2])
    local x, y, vx, vy = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if pid and x and y and vx and vy then
      Weapons.projectiles[pid] = { x = x, y = y, vx = vx, vy = vy, age = 0, owner = owner }
      Sounds.play("shot", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
  WPN_HIT = function(client, args)
    local pid, victim, hp = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local at = (pid and Weapons.projectiles[pid]) or (victim and client.cars[victim])
    if at then
      Sounds.play("hit", at.x, at.y, 0.9 + love.math.random() * 0.2)
    end
    if pid then
      Weapons.projectiles[pid] = nil
    end
    if victim and hp then
      Weapons.health[victim] = hp
      Weapons.hitFlash[victim] = 0.15
    end
  end,
  WPN_KILL = function(client, args)
    local pid, killer, victim, kills = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local deathTime = tonumber(args[5]) or DEATH_TIME
    local at = (pid and Weapons.projectiles[pid]) or (victim and client.cars[victim])
    if at then
      Sounds.play("explosion", at.x, at.y)
      Explosions.spawn(at.x, at.y, victim and Car.colorFor(victim))
      local me = client:myCar()
      if me and Video.get("screenShake") then
        local dist = math.sqrt((at.x - me.dx) ^ 2 + (at.y - me.dy) ^ 2)
        Explosions.addShake(SHAKE_MAX * math.max(0, 1 - dist / SHAKE_RADIUS))
      end
    end
    if victim == client.myId then
      Weapons.deadTimer = deathTime
      if Video.get("screenShake") then
        Explosions.addShake(SHAKE_MAX)
      end
    end
    if pid then
      Weapons.projectiles[pid] = nil
    end
    if victim then
      Weapons.health[victim] = MAX_HEALTH
      Weapons.hitFlash[victim] = 0.3
    end
    if killer and kills then
      Weapons.kills[killer] = kills
    end
    if killer and victim then
      Weapons.feed = { text = playerName(client, killer) .. " wrecked " .. playerName(client, victim), t = FEED_TIME }
    end
  end,
}

-- Server ----------------------------------------------------------------

function Weapons:serverStart(server)
  local sv = { time = 0, projectiles = {}, nextId = 1, players = {}, targets = {} }
  for id, p in pairs(server.players) do
    if p.car then
      sv.players[id] = {
        hp = MAX_HEALTH,
        kills = 0,
        spawn = { x = p.car.x, y = p.car.y, angle = p.car.angle },
        lastFire = -math.huge,
        protectedUntil = SPAWN_PROTECTION,
      }
    end
  end
  self.sv = sv
end

--- A player (human or bot) added while the game is running.
function Weapons:serverPlayerJoined(_server, player)
  if self.sv and player.car and not self.sv.players[player.id] then
    self.sv.players[player.id] = {
      hp = MAX_HEALTH,
      kills = 0,
      spawn = { x = player.car.x, y = player.car.y, angle = player.car.angle },
      lastFire = -math.huge,
      protectedUntil = self.sv.time + SPAWN_PROTECTION,
    }
  end
end

function Weapons:serverPlayerLeft(_server, player)
  if self.sv then
    self.sv.players[player.id] = nil
  end
end

--- Restore up to `amount` health to a living player. Returns true if any
--- health was gained (so a pickup knows whether it was used). Other features
--- reach this via Features.byName.weapons.
function Weapons:serverHeal(server, player, amount)
  local sv = self.sv
  local st = sv and sv.players[player.id]
  if not st or not player.car or player.car.hidden or st.hp >= MAX_HEALTH then
    return false
  end
  st.hp = math.min(MAX_HEALTH, st.hp + amount)
  server:broadcast(Protocol.encode("WPN_HEALTH", player.id, st.hp))
  return true
end

--- Fire a projectile for `player` toward `aim` (radians), subject to the
--- cooldown. Used by WPN_FIRE and by other features (bots). Returns true if
--- a shot was fired.
function Weapons:serverFire(server, player, aim)
  local sv = self.sv
  local st = sv and sv.players[player.id]
  local car = player.car
  if not (st and car and aim) then
    return false
  end
  if sv.time - st.lastFire < FIRE_COOLDOWN * 0.9 then
    return false -- firing faster than allowed; drop it
  end
  st.lastFire = sv.time

  local pid = sv.nextId
  sv.nextId = pid + 1
  local bx, by, onFoot = bodyPose(server, player)
  local muzzle = onFoot and FOOT_MUZZLE or MUZZLE_OFFSET
  local x = bx + math.cos(aim) * muzzle
  local y = by + math.sin(aim) * muzzle
  local vx = math.cos(aim) * PROJECTILE_SPEED
  local vy = math.sin(aim) * PROJECTILE_SPEED
  sv.projectiles[#sv.projectiles + 1] = { id = pid, owner = player.id, x = x, y = y, vx = vx, vy = vy, age = 0 }
  server:broadcast(Protocol.encode("WPN_SHOT", pid, player.id,
    ("%.1f"):format(x), ("%.1f"):format(y), ("%.1f"):format(vx), ("%.1f"):format(vy)))
  Features.call("serverShotFired", server, player, x, y)
  return true
end

Weapons.serverMessages = {
  WPN_FIRE = function(server, player, args)
    Weapons:serverFire(server, player, tonumber(args[1]))
  end,
}

--- Everyone projectile `p` could hit, with where their body is this tick: a
--- driver is their car, a player on foot a small circle where they stand, so
--- the car they parked stops being a target. Returns the (reused) list and
--- how many entries are live, the way the crowd does it.
function Weapons:targets(server, p)
  local list, n = self.sv.targets, 0
  for id, player in pairs(server.players) do
    local st = self.sv.players[id]
    if st and player.car and not player.car.hidden and id ~= p.owner and self.sv.time >= st.protectedUntil then
      n = n + 1
      local e = list[n]
      if not e then
        e = {}
        list[n] = e
      end
      e.player = player
      e.x, e.y, e.onFoot = bodyPose(server, player)
    end
  end
  return list, n
end

--- Walk the projectile's path for this tick in small steps so fast shots
--- can't tunnel through a car. Returns the first player hit, or the string
--- "wall" / "soft" when something that isn't a player swallowed the shot (a
--- building, a pedestrian), or nil when it flew on. Players are tested before
--- soft targets, so a pedestrian can't be used as a body shield.
function Weapons:sweep(server, p, nx, ny)
  local dx, dy = nx - p.x, ny - p.y
  local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / SWEEP_STEP))
  local angle = math.atan2(p.vy, p.vx)
  local targets, ntargets = self:targets(server, p)
  for s = 1, steps do
    local t = s / steps
    local px, py = p.x + dx * t, p.y + dy * t
    if blocked(px, py) then
      return "wall"
    end
    for i = 1, ntargets do
      local e = targets[i]
      local struck
      if e.onFoot then
        local ex, ey = px - e.x, py - e.y
        struck = ex * ex + ey * ey <= (FOOT_RADIUS + PROJECTILE_RADIUS) ^ 2
      else
        struck = Car.hitTest(e.player.car, px, py, PROJECTILE_RADIUS)
      end
      if struck then
        return e.player
      end
    end
    if shotSomething(server, px, py, p.owner, angle) then
      return "soft"
    end
  end
  return nil
end

function Weapons:hit(server, p, victim)
  local sv = self.sv
  local st = sv.players[victim.id]
  st.hp = st.hp - DAMAGE
  -- Let other features react (bots take offence at being shot).
  Features.call("serverPlayerDamaged", server, victim, server.players[p.owner], DAMAGE)
  if st.hp > 0 then
    server:broadcast(Protocol.encode("WPN_HIT", p.id, victim.id, st.hp))
    return
  end

  local killer = sv.players[p.owner]
  local kills = 0
  if killer then
    killer.kills = killer.kills + 1
    kills = killer.kills
  end
  st.hp = MAX_HEALTH
  st.deadUntil = sv.time + DEATH_TIME
  st.protectedUntil = st.deadUntil + SPAWN_PROTECTION
  local car = victim.car
  -- Where it went up, before the wreck parks at its slot: the car, or the
  -- body if they were out of it (on-foot puts them back behind the wheel
  -- when it hears the kill).
  local wx, wy = bodyPose(server, victim)
  car.hidden = true -- core stops broadcasting it until we clear this
  car.x, car.y, car.angle = st.spawn.x, st.spawn.y, st.spawn.angle
  car:stop()
  server:broadcast(Protocol.encode("WPN_KILL", p.id, p.owner, victim.id, kills, DEATH_TIME))
  Features.call("serverKill", server, { kind = "car", x = wx, y = wy, by = p.owner, victim = victim.id })
end

--- Keep wrecks parked at their slot and bring them back when their time is up.
function Weapons:updateWrecks(server)
  local sv = self.sv
  for id, st in pairs(sv.players) do
    if st.deadUntil then
      local car = server.players[id] and server.players[id].car
      if not car then
        st.deadUntil = nil
      elseif sv.time < st.deadUntil then
        car.x, car.y, car.angle = st.spawn.x, st.spawn.y, st.spawn.angle
        car:stop()
      else
        car.hidden = false
        st.deadUntil = nil
      end
    end
  end
end

function Weapons:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  sv.time = sv.time + dt
  self:updateWrecks(server)
  local i = 1
  while i <= #sv.projectiles do
    local p = sv.projectiles[i]
    p.age = p.age + dt
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    local victim = self:sweep(server, p, nx, ny)
    p.x, p.y = nx, ny
    if victim == "wall" then
      table.remove(sv.projectiles, i) -- clients notice the same wall themselves
    elseif victim == "soft" then
      -- Nothing on the client predicts a pedestrian stepping into a bullet,
      -- so the streak has to be called back explicitly.
      server:broadcast(Protocol.encode("WPN_STOP", p.id))
      table.remove(sv.projectiles, i)
    elseif victim then
      self:hit(server, p, victim)
      table.remove(sv.projectiles, i)
    elseif p.age > PROJECTILE_TTL then
      table.remove(sv.projectiles, i)
    else
      i = i + 1
    end
  end
end

return Weapons
