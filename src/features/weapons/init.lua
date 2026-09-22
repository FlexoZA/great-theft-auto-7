-- Weapons: left mouse button fires a projectile from your car toward the
-- cursor. The server owns projectiles, hit detection, health and respawns.
-- Clients predict projectile flight from WPN_SHOT and draw everything.
--
-- Messages
--   client -> server  WPN_FIRE <aimAngle>
--   server -> all     WPN_SHOT <pid> <owner> <x> <y> <vx> <vy>
--   server -> all     WPN_HIT  <pid> <victim> <hp>
--   server -> all     WPN_KILL <pid> <killer> <victim> <killerKills>

local Protocol = require("src.net.protocol")
local Car = require("src.car")
local UI = require("src.ui")

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
local MUZZLE_OFFSET = 26 -- px from car centre along the aim
local SWEEP_STEP = 6 -- px between hit samples along a projectile's path per tick
local FEED_TIME = 3

-- Client state (also reset in enterGame) ------------------------------------

Weapons.projectiles = {} -- pid -> { x, y, vx, vy, age, owner }
Weapons.health = {} -- player id -> hp (absent = full)
Weapons.kills = {} -- player id -> kills
Weapons.hitFlash = {} -- player id -> seconds left
Weapons.feed = nil -- { text, t }
Weapons.cooldown = 0
Weapons.showHitboxes = false
Weapons.camera = nil -- last camera seen in update; needed to aim through pans and zoom

function Weapons:enterGame()
  self.projectiles = {}
  self.health = {}
  self.kills = {}
  self.hitFlash = {}
  self.feed = nil
  self.cooldown = 0
  self.camera = nil
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

--- Angle from my car to the cursor, in world space.
function Weapons:aimAngle(client)
  local me = client:myCar()
  if not me then
    return nil
  end
  local wx, wy = mouseToWorld(self.camera, me)
  return math.atan2(wy - me.dy, wx - me.dx)
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
  if button == 1 then
    self:tryFire(client)
  end
end

function Weapons:keypressed(key)
  if key == "f1" then
    self.showHitboxes = not self.showHitboxes
  end
end

function Weapons:update(dt, client, camera)
  self.camera = camera
  self.cooldown = math.max(0, self.cooldown - dt)
  if love.mouse.isDown(1) then
    self:tryFire(client)
  end
  for pid, p in pairs(self.projectiles) do
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.age = p.age + dt
    if p.age > PROJECTILE_TTL then
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
end

function Weapons:drawAboveCars(client)
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
    -- Health bar under the car.
    local hp = self.health[id] or MAX_HEALTH
    local bw, bh = Car.WIDTH, 4
    local bx, by = c.dx - bw / 2, c.dy + Car.HEIGHT / 2 + 8
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
    love.graphics.setColor(1 - hp / MAX_HEALTH, hp / MAX_HEALTH, 0.2)
    love.graphics.rectangle("fill", bx, by, bw * hp / MAX_HEALTH, bh)

    if self.hitFlash[id] then
      love.graphics.setColor(1, 1, 1, self.hitFlash[id] * 4)
      love.graphics.circle("line", c.dx, c.dy, Car.WIDTH * 0.7)
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
  love.graphics.print("Left mouse: fire   F1: hitboxes", 10, 64)

  if self.feed then
    local w = love.graphics.getWidth()
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(1, 1, 1, math.min(1, self.feed.t))
    love.graphics.printf(self.feed.text, 0, 40, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

local function playerName(client, id)
  local p = client.players[id]
  return p and p.name or ("#" .. tostring(id))
end

Weapons.clientMessages = {
  WPN_SHOT = function(_client, args)
    local pid, owner = tonumber(args[1]), tonumber(args[2])
    local x, y, vx, vy = tonumber(args[3]), tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if pid and x and y and vx and vy then
      Weapons.projectiles[pid] = { x = x, y = y, vx = vx, vy = vy, age = 0, owner = owner }
    end
  end,
  WPN_HIT = function(_client, args)
    local pid, victim, hp = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
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
  local sv = { time = 0, projectiles = {}, nextId = 1, players = {} }
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
  local x = car.x + math.cos(aim) * MUZZLE_OFFSET
  local y = car.y + math.sin(aim) * MUZZLE_OFFSET
  local vx = math.cos(aim) * PROJECTILE_SPEED
  local vy = math.sin(aim) * PROJECTILE_SPEED
  sv.projectiles[#sv.projectiles + 1] = { id = pid, owner = player.id, x = x, y = y, vx = vx, vy = vy, age = 0 }
  server:broadcast(Protocol.encode("WPN_SHOT", pid, player.id,
    ("%.1f"):format(x), ("%.1f"):format(y), ("%.1f"):format(vx), ("%.1f"):format(vy)))
  return true
end

Weapons.serverMessages = {
  WPN_FIRE = function(server, player, args)
    Weapons:serverFire(server, player, tonumber(args[1]))
  end,
}

--- Walk the projectile's path for this tick in small steps so fast shots
--- can't tunnel through a car. Returns the first player hit, if any.
function Weapons:sweep(server, p, nx, ny)
  local dx, dy = nx - p.x, ny - p.y
  local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / SWEEP_STEP))
  for s = 1, steps do
    local t = s / steps
    local px, py = p.x + dx * t, p.y + dy * t
    for id, player in pairs(server.players) do
      local st = self.sv.players[id]
      if st and player.car and id ~= p.owner and self.sv.time >= st.protectedUntil then
        if Car.hitTest(player.car, px, py, PROJECTILE_RADIUS) then
          return player
        end
      end
    end
  end
  return nil
end

function Weapons:hit(server, p, victim)
  local sv = self.sv
  local st = sv.players[victim.id]
  st.hp = st.hp - DAMAGE
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
  st.protectedUntil = sv.time + SPAWN_PROTECTION
  local car = victim.car
  car.x, car.y, car.angle, car.speed = st.spawn.x, st.spawn.y, st.spawn.angle, 0
  server:broadcast(Protocol.encode("WPN_KILL", p.id, p.owner, victim.id, kills))
end

function Weapons:serverStep(server, dt)
  local sv = self.sv
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local i = 1
  while i <= #sv.projectiles do
    local p = sv.projectiles[i]
    p.age = p.age + dt
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    local victim = self:sweep(server, p, nx, ny)
    p.x, p.y = nx, ny
    if victim then
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
