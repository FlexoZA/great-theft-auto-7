-- Weapons: left mouse button fires a projectile from your car toward the
-- cursor. The server owns projectiles, hit detection, health and respawns.
-- Clients predict projectile flight from WPN_SHOT and draw everything.
--
-- There is more than one gun (guns.lua): the number keys pick one, the
-- client tells the host, and the host fires whatever it has on record for
-- that player, with that gun's damage, rate of fire and scatter. The
-- pistol hits hard and straight; the uzi sprays.
--
-- People and cars have separate health. A shot at a driver dents the car;
-- when a car has taken CAR_HEALTH it explodes and its driver bails out
-- beside the wreck, alive and briefly protected, and carries on on foot.
-- The wreck is gone for DEATH_TIME seconds and comes back whole at its
-- owner's slot (or where it died, for a car nobody owns). A shot at someone
-- on foot hurts them; at zero they die, and DEATH_TIME later they are back
-- at their slot behind the wheel of their own car. NPC drivers (bots, police
-- units) go down with their car, so their respawn is the same as ever.
-- Cars nobody is driving can be shot too: they take the bullet, so a parked
-- car is cover, and they blow up like any other.
--
-- Messages
--   client -> server  WPN_FIRE <aimAngle>
--   client -> server  WPN_SELECT <gun>                 (index into guns.lua)
--   server -> all     WPN_SHOT <pid> <owner> <x> <y> <vx> <vy> <gun>
--   server -> all     WPN_HIT  <pid> <victim> <hp>                (someone on foot)
--   server -> all     WPN_KILL <pid> <killer> <victim> <killerKills> <deathTime>
--   server -> all     WPN_CARHIT <pid> <vid> <hp>                 (a car)
--   server -> all     WPN_WRECK <pid> <killer> <vid> <driver> <killerKills> <deathTime>
--   server -> all     WPN_CARHP <vid> <hp>           (a repair or a respawn; no hit effects)
--   server -> all     WPN_HEALTH <id> <hp>          (a heal; no hit effects)
--   server -> all     WPN_MAX <id> <max>            (their health ceiling changed)
--   server -> all     WPN_STOP <pid>                (shot swallowed by a soft target)
--
-- Health has a ceiling per player, MAX_HEALTH to start with; another feature
-- can raise it (upgrades buys it with koins) through Weapons:serverSetMaxHealth.
-- Every car has CAR_HEALTH; Weapons:serverHeal tops up the body first and
-- then the car you are driving, so a health pack works from behind the wheel.
--
-- Not every shot has a player behind it: Weapons:serverFireFrom puts a
-- projectile into the world for whoever asks (the police officers on foot),
-- owned by nobody, hurting anyone it hits and crediting no scoreboard.
--
-- A player need not be in a car: on foot, shots leave from their body,
-- hits land on it, and the car they left is not a target (the core says
-- where everyone is; see "Bodies and vehicles" in docs/features.md).

local Protocol = require("src.net.protocol")
local Car = require("src.car")
local UI = require("src.ui")
local Sounds = require("src.features.weapons.sounds")
local Explosions = require("src.features.weapons.explosions")
local Guns = require("src.features.weapons.guns")
local Features = require("src.features")
local Controls = require("src.controls")
local Video = require("src.video")

local Weapons = {
  name = "weapons",
  priority = 950, -- after "vision" (900) so the camera is final when we aim
  PROJECTILE_SPEED = Guns.at(Guns.DEFAULT).speed, -- px/s; other features (bots) read this to lead their shots
}

local PROJECTILE_TTL = 1.2 -- seconds
local PROJECTILE_RADIUS = 3
local MAX_HEALTH = 100
local CAR_HEALTH = 100
local SPAWN_PROTECTION = 1.5 -- seconds of invulnerability after respawn
local DEATH_TIME = 2.5 -- seconds a wreck stays gone before respawning
local SHAKE_RADIUS = 1100 -- px; explosions further away don't shake the screen
local SHAKE_MAX = 18
local MUZZLE_OFFSET = 26 -- px from car centre along the aim
local FOOT_MUZZLE = 14 -- px from a body on foot, which is smaller than a car
local FOOT_RADIUS = 8 -- px; how fat a player on foot is for hit tests
local SWEEP_STEP = 6 -- px between hit samples along a projectile's path per tick
local FEED_TIME = 3
local NO_OWNER = 0 -- projectile owner for a shot no player fired (police on foot)

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

--- Where `player`'s body is on the host: the car they drive, or their feet.
--- The third return says which of the two it is.
local function bodyPose(server, player)
  return Features.bodyPose(server, player)
end

--- The same question on a client, where the answer is what is drawn, or
--- nil while they are out of the world.
local function clientPose(client, id)
  return Features.clientBodyPose(client, id)
end

-- Client state (also reset in enterGame) ------------------------------------

Weapons.projectiles = {} -- pid -> { x, y, vx, vy, age, owner }
Weapons.health = {} -- player id -> hp (absent = full)
Weapons.maxHealth = {} -- player id -> ceiling (absent = MAX_HEALTH)
Weapons.carHealth = {} -- vehicle id -> hp (absent = full)
Weapons.kills = {} -- player id -> kills
Weapons.hitFlash = {} -- player id -> seconds left (on foot)
Weapons.carFlash = {} -- vehicle id -> seconds left
Weapons.feed = nil -- { text, t }
Weapons.cooldown = 0
Weapons.gun = Guns.DEFAULT -- index of the gun I hold (the host keeps its own record)
Weapons.showHitboxes = false
Weapons.deadTimer = 0 -- seconds until my own car respawns (client)
Weapons.armed = false -- held fire only counts once the button has been seen released in-game
Weapons.camera = nil -- last camera seen in update; needed to aim through pans and zoom

function Weapons:load()
  Sounds.load()
  Controls.register("fire", "Fire", "mouse1")
  Controls.register("hitboxes", "Show hitboxes", "f1")
  for i, gun in ipairs(Guns.list) do
    Controls.register("weapon-" .. i, ("Weapon %d: %s"):format(i, gun.name), tostring(i))
  end
end

function Weapons:enterGame()
  self.projectiles = {}
  self.health = {}
  self.maxHealth = {}
  self.carHealth = {}
  self.kills = {}
  self.hitFlash = {}
  self.carFlash = {}
  self.feed = nil
  self.cooldown = 0
  self.gun = Guns.DEFAULT
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
  local ox, oy = client:myPose()
  if not ox then
    return nil
  end
  local wx, wy = mouseToWorld(self.camera, { dx = ox, dy = oy })
  return math.atan2(wy - oy, wx - ox)
end

function Weapons:tryFire(client)
  if self.cooldown > 0 or Features.any("held", client, client.myId) then
    return -- cooling down, or held still (frozen)
  end
  local aim = self:aimAngle(client)
  if not aim then
    return
  end
  self.cooldown = Guns.at(self.gun).cooldown
  client:send(Protocol.encode("WPN_FIRE", ("%.3f"):format(aim)))
end

--- Switch to gun `index` and tell the host. The cooldown carries over, so
--- swapping is no faster than waiting.
function Weapons:selectGun(client, index)
  if not Guns.list[index] or index == self.gun then
    return
  end
  self.gun = index
  client:send(Protocol.encode("WPN_SELECT", index))
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
  else
    -- The number keys, unless the upgrade shop has them for the moment.
    local shop = Features.byName.upgrades
    if shop and shop.open then
      return
    end
    for i in ipairs(Guns.list) do
      if Controls.is("weapon-" .. i, key) then
        self:selectGun(client, i)
        return
      end
    end
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
  for _, flashes in ipairs({ self.hitFlash, self.carFlash }) do
    for id, t in pairs(flashes) do
      if t - dt <= 0 then
        flashes[id] = nil
      else
        flashes[id] = t - dt
      end
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
    local streak = Guns.at(p.gun).streak
    local nx, ny = p.vx / len * streak, p.vy / len * streak
    love.graphics.line(p.x - nx, p.y - ny, p.x, p.y)
  end
  love.graphics.setLineWidth(1)

  local function bar(px, py, hp, max, bw, dy)
    local bh = 4
    local bx, by = px - bw / 2, py + dy
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", bx - 1, by - 1, bw + 2, bh + 2)
    love.graphics.setColor(1 - hp / max, hp / max, 0.2)
    love.graphics.rectangle("fill", bx, by, bw * hp / max, bh)
  end
  -- A bar under every car in the world, driven or not: the car's own health.
  for vid, v in pairs(client.vehicles) do
    bar(v.dx, v.dy, self.carHealth[vid] or CAR_HEALTH, CAR_HEALTH, Car.WIDTH, Car.HEIGHT / 2 + 8)
    if self.carFlash[vid] then
      love.graphics.setColor(1, 1, 1, self.carFlash[vid] * 4)
      love.graphics.circle("line", v.dx, v.dy, Car.WIDTH * 0.7)
    end
  end
  -- And one under everyone on foot: theirs. It grows with their ceiling, so
  -- an upgraded player looks it.
  for id, b in pairs(client.bodies) do
    local max = self.maxHealth[id] or MAX_HEALTH
    bar(b.dx, b.dy, self.health[id] or max, max, Car.WIDTH * 0.6 * math.sqrt(max / MAX_HEALTH), 12)
    if self.hitFlash[id] then
      love.graphics.setColor(1, 1, 1, self.hitFlash[id] * 4)
      love.graphics.circle("line", b.dx, b.dy, FOOT_RADIUS * 2)
    end
  end
  if self.showHitboxes then
    love.graphics.setColor(0.3, 1, 0.3, 0.9)
    for _, c in pairs(client.vehicles) do
      love.graphics.push()
      love.graphics.translate(c.dx, c.dy)
      love.graphics.rotate(c.dangle)
      love.graphics.rectangle("line", -Car.WIDTH / 2, -Car.HEIGHT / 2, Car.WIDTH, Car.HEIGHT)
      love.graphics.pop()
    end
    for _, b in pairs(client.bodies) do
      love.graphics.circle("line", b.dx, b.dy, FOOT_RADIUS)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- Wrecked: the world goes soft under the WRECKED overlay, right where the
--- car went up, until it respawns (the `worldBlur` hook, docs/features.md).
function Weapons:worldBlur()
  return self.deadTimer > 0 and 1 or 0
end

function Weapons:drawHUD(client)
  love.graphics.setFont(UI.fonts.small)
  local max = self.maxHealth[client.myId] or MAX_HEALTH
  local hp = self.health[client.myId] or max
  local kills = self.kills[client.myId] or 0
  love.graphics.setColor(1, 1, 1)
  local line = ("HP %d/%d"):format(hp, max)
  local car = client:myVehicle()
  if car then
    line = line .. ("   car %d/%d"):format(self.carHealth[car.id] or CAR_HEALTH, CAR_HEALTH)
  end
  love.graphics.print(line .. ("   kills %d"):format(kills), 10, 46)
  love.graphics.setColor(0.6, 0.6, 0.65)
  local fireKey = Controls.name(Controls.bindings("fire")[1])
  local boxKey = Controls.name(Controls.bindings("hitboxes")[1])
  local hints = fireKey .. ": fire   " .. boxKey .. ": hitboxes   "
  love.graphics.print(hints, 10, 64)
  -- The guns on the same row, the one in hand lit up.
  local font = UI.fonts.small
  local x = 10 + font:getWidth(hints)
  for i, gun in ipairs(Guns.list) do
    local label = Controls.name(Controls.bindings("weapon-" .. i)[1]) .. ": " .. gun.name
    if i == self.gun then
      love.graphics.setColor(1, 0.9, 0.3)
    else
      love.graphics.setColor(0.6, 0.6, 0.65)
    end
    love.graphics.print(label, x, 64)
    x = x + font:getWidth(label) + 14
  end

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
    love.graphics.printf("WASTED", 0, h / 2 - 60, w, "center")
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

--- Where a player is drawn, as a point, or nil while they are out of the world.
local function poseOf(client, id)
  local x, y = clientPose(client, id)
  return x and { x = x, y = y } or nil
end

Weapons.clientMessages = {
  WPN_HEALTH = function(_client, args)
    local id, hp = tonumber(args[1]), tonumber(args[2])
    if id and hp then
      Weapons.health[id] = hp
    end
  end,
  WPN_MAX = function(_client, args)
    local id, max = tonumber(args[1]), tonumber(args[2])
    if id and max then
      Weapons.maxHealth[id] = max
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
    local gun = Guns.at(tonumber(args[7]))
    if pid and x and y and vx and vy then
      Weapons.projectiles[pid] = { x = x, y = y, vx = vx, vy = vy, age = 0, owner = owner, gun = gun.index }
      Sounds.play(gun.sound, x, y, gun.pitch * (0.9 + love.math.random() * 0.2))
    end
  end,
  WPN_HIT = function(client, args)
    local pid, victim, hp = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local at = (pid and Weapons.projectiles[pid]) or (victim and poseOf(client, victim))
    if at then
      Sounds.play("hit", at.x, at.y, 0.9 + love.math.random() * 0.2)
    end
    if pid and pid > 0 then
      Weapons.projectiles[pid] = nil
    end
    if victim and hp then
      Weapons.health[victim] = hp
      Weapons.hitFlash[victim] = 0.15
    end
  end,
  WPN_CARHIT = function(client, args)
    local pid, vid, hp = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local v = vid and client.vehicles[vid]
    local at = (pid and Weapons.projectiles[pid]) or (v and { x = v.dx, y = v.dy })
    if at then
      Sounds.play("hit", at.x, at.y, 0.9 + love.math.random() * 0.2)
    end
    if pid and pid > 0 then
      Weapons.projectiles[pid] = nil
    end
    if vid and hp then
      Weapons.carHealth[vid] = hp
      Weapons.carFlash[vid] = 0.15
    end
  end,
  WPN_CARHP = function(_client, args)
    local vid, hp = tonumber(args[1]), tonumber(args[2])
    if vid and hp then
      Weapons.carHealth[vid] = hp
    end
  end,
  --- A car blew up. Its driver, if it had one, is standing beside it now.
  WPN_WRECK = function(client, args)
    local pid, killer, vid = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local driver, kills = tonumber(args[4]), tonumber(args[5])
    local v = vid and client.vehicles[vid]
    local at = (pid and Weapons.projectiles[pid]) or (v and { x = v.dx, y = v.dy })
    if at then
      Sounds.play("explosion", at.x, at.y)
      Explosions.spawn(at.x, at.y, v and Car.paletteColor(v.color))
      local mx, my = client:myPose()
      if mx and Video.get("screenShake") then
        local dist = math.sqrt((at.x - mx) ^ 2 + (at.y - my) ^ 2)
        Explosions.addShake(SHAKE_MAX * math.max(0, 1 - dist / SHAKE_RADIUS))
      end
    end
    if pid then
      Weapons.projectiles[pid] = nil
    end
    if vid then
      Weapons.carHealth[vid] = nil
      Weapons.carFlash[vid] = 0.3
    end
    if killer and kills then
      Weapons.kills[killer] = kills
    end
    local text
    if driver and driver ~= 0 then
      local name = playerName(client, driver) .. "'s car"
      text = name .. " was wrecked"
      if killer and killer ~= NO_OWNER then
        text = playerName(client, killer) .. " wrecked " .. name
      end
    elseif killer and killer ~= NO_OWNER then
      text = playerName(client, killer) .. " blew up a parked car"
    end
    if text then
      Weapons.feed = { text = text, t = FEED_TIME }
    end
  end,
  WPN_KILL = function(client, args)
    local pid, killer, victim, kills = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    local deathTime = tonumber(args[5]) or DEATH_TIME
    local at = (pid and Weapons.projectiles[pid]) or (victim and poseOf(client, victim))
    if at then
      Sounds.play("explosion", at.x, at.y)
      Explosions.spawn(at.x, at.y, victim and Car.colorFor(victim))
      local mx, my = client:myPose()
      if mx and Video.get("screenShake") then
        local dist = math.sqrt((at.x - mx) ^ 2 + (at.y - my) ^ 2)
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
      Weapons.health[victim] = Weapons.maxHealth[victim] or MAX_HEALTH
      Weapons.hitFlash[victim] = 0.3
    end
    if killer and kills then
      Weapons.kills[killer] = kills
    end
    if victim then
      local name = playerName(client, victim)
      local text = name .. " was wasted" -- an ownerless shot: nobody to name
      if killer and killer ~= NO_OWNER then
        text = playerName(client, killer) .. " wasted " .. name
      end
      Weapons.feed = { text = text, t = FEED_TIME }
    end
  end,
}

-- Server ----------------------------------------------------------------

function Weapons:serverStart(server)
  local sv = { time = 0, projectiles = {}, nextId = 1, players = {}, cars = {}, targets = {} }
  for id, p in pairs(server.players) do
    if p.body then
      sv.players[id] = {
        hp = MAX_HEALTH,
        max = MAX_HEALTH,
        kills = 0,
        gun = Guns.DEFAULT,
        spawn = { x = p.body.x, y = p.body.y, angle = p.body.facing },
        lastFire = -math.huge,
        protectedUntil = SPAWN_PROTECTION,
      }
    end
  end
  self.sv = sv
end

--- A player (human or bot) added while the game is running.
function Weapons:serverPlayerJoined(_server, player)
  if self.sv and player.body and not self.sv.players[player.id] then
    self.sv.players[player.id] = {
      hp = MAX_HEALTH,
      max = MAX_HEALTH,
      kills = 0,
      gun = Guns.DEFAULT,
      spawn = { x = player.body.x, y = player.body.y, angle = player.body.facing },
      lastFire = -math.huge,
      protectedUntil = self.sv.time + SPAWN_PROTECTION,
    }
  end
end

--- Everyone was moved to another map (city-map's `mapChanged`; the host
--- passes `server`, clients get nil). The cars now stand on the new map's
--- spawn points, so that is where wrecks come back from now.
function Weapons:mapChanged(_map, server)
  if not (server and self.sv) then
    return
  end
  for id, st in pairs(self.sv.players) do
    local p = server.players[id]
    if p and p.body then
      st.spawn = { x = p.body.x, y = p.body.y, angle = p.body.facing }
    end
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
  if not st or not Features.present(player) then
    return false
  end
  if st.hp < st.max then
    st.hp = math.min(st.max, st.hp + amount)
    server:broadcast(Protocol.encode("WPN_HEALTH", player.id, st.hp))
    return true
  end
  return player.vehicle ~= nil and self:serverRepair(server, player.vehicle, amount)
end

--- A car's health record, made the first time it is needed: every car
--- starts whole.
function Weapons:carState(car)
  local cs = self.sv.cars[car.id]
  if not cs then
    cs = { hp = CAR_HEALTH, max = CAR_HEALTH, deadUntil = nil, spawn = nil }
    self.sv.cars[car.id] = cs
  end
  return cs
end

--- Repair up to `amount` of a car's damage. Returns true if any was
--- repaired. Other features reach this via Features.byName.weapons.
function Weapons:serverRepair(server, car, amount)
  local sv = self.sv
  if not (sv and car) or car.hidden or car.stowed then
    return false
  end
  local cs = self:carState(car)
  if cs.deadUntil or cs.hp >= cs.max then
    return false
  end
  cs.hp = math.min(cs.max, cs.hp + amount)
  server:broadcast(Protocol.encode("WPN_CARHP", car.id, cs.hp))
  return true
end

--- Raise (or lower) a player's health ceiling to `max`, for the rest of the
--- game: respawns come back with it. Raising it heals by the difference, so
--- an upgrade is felt at once. Other features reach this via
--- Features.byName.weapons (upgrades does). Returns the new ceiling, or nil
--- for a player this feature doesn't know.
function Weapons:serverSetMaxHealth(server, player, max)
  local sv = self.sv
  local st = sv and sv.players[player.id]
  if not st then
    return nil
  end
  max = math.max(1, math.floor(max))
  local gained = max - st.max
  st.max = max
  st.hp = math.min(max, gained > 0 and st.hp + gained or st.hp)
  server:broadcast(Protocol.encode("WPN_MAX", player.id, max))
  server:broadcast(Protocol.encode("WPN_HEALTH", player.id, st.hp))
  return max
end

--- Put a projectile into the world at (x, y), flying along `aim` (radians)
--- and belonging to player `ownerId`. Pass 0 for a shot that belongs to no
--- player: the police officers on foot fire this way, so their bullets hit
--- everyone (nobody is the owner) and their kills go on nobody's scoreboard.
--- No cooldown is applied here; the caller owns its own rate of fire. `gun`
--- is a table from guns.lua (the pistol when not given); its scatter is
--- applied here.
function Weapons:serverFireFrom(server, ownerId, x, y, aim, gun)
  local sv = self.sv
  if not (sv and aim) then
    return false
  end
  gun = gun or Guns.at(Guns.DEFAULT)
  if gun.spread > 0 then
    aim = aim + (love.math.random() * 2 - 1) * gun.spread
  end
  ownerId = ownerId or NO_OWNER
  local pid = sv.nextId
  sv.nextId = pid + 1
  local vx = math.cos(aim) * gun.speed
  local vy = math.sin(aim) * gun.speed
  sv.projectiles[#sv.projectiles + 1] = {
    id = pid, owner = ownerId, x = x, y = y, vx = vx, vy = vy, age = 0, damage = gun.damage,
  }
  server:broadcast(Protocol.encode("WPN_SHOT", pid, ownerId,
    ("%.1f"):format(x), ("%.1f"):format(y), ("%.1f"):format(vx), ("%.1f"):format(vy), gun.index))
  -- `player` is nil for an ownerless shot; features that listen must allow it.
  Features.call("serverShotFired", server, server.players[ownerId], x, y)
  return true
end

--- Fire a projectile for `player` toward `aim` (radians), subject to the
--- cooldown. Used by WPN_FIRE and by other features (bots). Returns true if
--- a shot was fired.
function Weapons:serverFire(server, player, aim)
  local sv = self.sv
  local st = sv and sv.players[player.id]
  if not (st and player.body and aim) then
    return false
  end
  local gun = Guns.at(st.gun)
  if sv.time - st.lastFire < gun.cooldown * 0.9 then
    return false -- firing faster than allowed; drop it
  end
  if Features.any("serverHeld", server, player) then
    return false -- held still (frozen): the trigger is stuck too
  end
  st.lastFire = sv.time

  local bx, by, onFoot = bodyPose(server, player)
  local muzzle = onFoot and FOOT_MUZZLE or MUZZLE_OFFSET
  return self:serverFireFrom(server, player.id, bx + math.cos(aim) * muzzle, by + math.sin(aim) * muzzle, aim, gun)
end

--- Hand `player` gun `index` on the host (bots could pick one this way).
function Weapons:serverSelectGun(_server, player, index)
  local st = self.sv and self.sv.players[player.id]
  if not (st and Guns.list[index]) then
    return false
  end
  st.gun = index
  return true
end

Weapons.serverMessages = {
  WPN_FIRE = function(server, player, args)
    Weapons:serverFire(server, player, tonumber(args[1]))
  end,
  WPN_SELECT = function(server, player, args)
    Weapons:serverSelectGun(server, player, tonumber(args[1]))
  end,
}

--- Everyone projectile `p` could hit, with where their body is this tick: a
--- driver is their car, a player on foot a small circle where they stand, so
--- the car they parked stops being a target. Returns the (reused) list and
--- how many entries are live, the way the crowd does it.
function Weapons:targets(server, p)
  local list, n = self.sv.targets, 0
  local function entry()
    n = n + 1
    local e = list[n]
    if not e then
      e = {}
      list[n] = e
    end
    return e
  end
  for id, player in pairs(server.players) do
    local st = self.sv.players[id]
    if st and Features.present(player) and id ~= p.owner and self.sv.time >= st.protectedUntil then
      local e = entry()
      e.player, e.car = player, player.vehicle
      e.x, e.y, e.onFoot = bodyPose(server, player)
    end
  end
  -- Cars nobody is driving stop bullets too, and take the damage.
  for _, car in pairs(server.vehicles) do
    if not (car.driver or car.hidden or car.stowed) then
      local e = entry()
      e.player, e.car = nil, car
      e.x, e.y, e.onFoot = car.x, car.y, false
    end
  end
  return list, n
end

--- Walk the projectile's path for this tick in small steps so fast shots
--- can't tunnel through a car. Returns the first target entry hit (`player`
--- for someone on foot or driving, `car` for the car), or the string
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
        struck = Car.hitTest(e.car, px, py, PROJECTILE_RADIUS)
      end
      if struck then
        return e
      end
    end
    if shotSomething(server, px, py, p.owner, angle) then
      return "soft"
    end
  end
  return nil
end

function Weapons:hit(server, p, target)
  local angle = p.vx and math.atan2(p.vy, p.vx) or nil
  local amount = p.damage or Guns.at(Guns.DEFAULT).damage
  if target.player then
    self:damage(server, target.player, p.owner, amount, p.id, angle)
  else
    self:damageCar(server, target.car, p.owner, amount, p.id, angle)
  end
end

--- Hurt a living player by `amount` from any cause. `byId` is the attacker's
--- id (or nil), `pid` the projectile (0 when it wasn't a bullet), `angle`
--- the direction the blow travelled, for gibs. Other features call
--- Weapons:serverDamage; this is the shared path behind bullets too.
function Weapons:damage(server, victim, byId, amount, pid, angle)
  local sv = self.sv
  local st = sv and sv.players[victim.id]
  if not st or not Features.present(victim) or st.deadUntil then
    return false
  end
  if victim.vehicle then
    return self:damageCar(server, victim.vehicle, byId, amount, pid, angle) -- the car takes it
  end
  pid = pid or 0
  st.hp = st.hp - amount
  -- Let other features react (bots take offence at being shot).
  Features.call("serverPlayerDamaged", server, victim, byId and server.players[byId], amount)
  if st.hp > 0 then
    server:broadcast(Protocol.encode("WPN_HIT", pid, victim.id, st.hp))
    return true
  end
  self:die(server, victim, byId, pid, angle)
  return true
end

--- Credit `byId` with a kill; returns their total (0 for nobody).
function Weapons:creditKill(byId)
  local killer = byId and self.sv.players[byId]
  if not killer then
    return 0
  end
  killer.kills = killer.kills + 1
  return killer.kills
end

--- The end of `victim`: out of the world until DEATH_TIME is up, then back
--- at their slot in their own car. Their own car goes with them, a wreck
--- waiting at the slot, whole again; a car they had borrowed is left where
--- it stands for the next driver. NPC drivers die this way when their car
--- is wrecked; a human bails out instead (see wreck).
function Weapons:die(server, victim, byId, pid, angle)
  local sv = self.sv
  local st = sv.players[victim.id]
  local kills = self:creditKill(byId)
  st.hp = st.max
  st.deadUntil = sv.time + DEATH_TIME
  st.protectedUntil = st.deadUntil + SPAWN_PROTECTION
  -- Where it went up: the car they drove, or their feet.
  local wx, wy, wasOnFoot = bodyPose(server, victim)
  victim.body.dead = true
  local own = victim.car
  if victim.vehicle and victim.vehicle ~= own then
    server:unseat(victim)
  end
  if own then
    own.hidden = true -- the core stops broadcasting it until we clear this
    own.x, own.y, own.angle = st.spawn.x, st.spawn.y, st.spawn.angle
    own:stop()
    local cs = self:carState(own)
    cs.hp, cs.deadUntil = cs.max, nil -- it comes back with them, whole
    if not victim.vehicle then
      server:seat(victim, own) -- the corpse rides the wreck back to the slot
    end
  end
  server:broadcast(Protocol.encode("WPN_KILL", pid or 0, byId or 0, victim.id, kills, DEATH_TIME))
  Features.call("serverKill", server, {
    kind = "car", x = wx, y = wy, by = byId, victim = victim.id, angle = angle, onFoot = wasOnFoot,
  })
end

--- Dent a car by `amount`. Its driver, if any, hears about it the way they
--- would a hit on foot (bots take offence). At zero it is wrecked.
function Weapons:damageCar(server, car, byId, amount, pid, angle)
  local sv = self.sv
  if not (sv and car) or car.hidden or car.stowed then
    return false
  end
  local cs = self:carState(car)
  if cs.deadUntil then
    return false
  end
  local driver = car.driver and server.players[car.driver]
  if driver then
    local st = sv.players[driver.id]
    if not st or st.deadUntil or not Features.present(driver) then
      return false
    end
  end
  pid = pid or 0
  cs.hp = cs.hp - amount
  if driver then
    Features.call("serverPlayerDamaged", server, driver, byId and server.players[byId], amount)
  end
  if cs.hp > 0 then
    server:broadcast(Protocol.encode("WPN_CARHIT", pid, car.id, cs.hp))
    return true
  end
  self:wreck(server, car, byId, pid, angle)
  return true
end

--- A car blows up. A human driver bails out beside it, alive and briefly
--- protected, and walks on; an NPC driver goes down with it (its brain
--- knows how to wait out a wreck). The car is gone for DEATH_TIME and comes
--- back whole at its owner's slot, or where it died if nobody owns it.
function Weapons:wreck(server, car, byId, pid, angle)
  local sv = self.sv
  local cs = self:carState(car)
  local driver = car.driver and server.players[car.driver]
  local wx, wy = car.x, car.y
  if driver and driver.bot then
    return self:die(server, driver, byId, pid, angle)
  end
  local kills = driver and self:creditKill(byId) or 0
  if driver then
    local onFoot = Features.byName["on-foot"]
    if onFoot and onFoot.getOut then
      onFoot:getOut(server, driver, true)
    else
      server:unseat(driver)
    end
    sv.players[driver.id].protectedUntil = sv.time + SPAWN_PROTECTION
  end
  local owner = car.owner and sv.players[car.owner]
  cs.hp = cs.max
  cs.deadUntil = sv.time + DEATH_TIME
  cs.spawn = owner and owner.spawn or { x = wx, y = wy, angle = car.angle }
  car.hidden = true
  car.x, car.y, car.angle = cs.spawn.x, cs.spawn.y, cs.spawn.angle
  car:stop()
  server:broadcast(Protocol.encode("WPN_WRECK", pid or 0, byId or 0, car.id, driver and driver.id or 0, kills,
    DEATH_TIME))
  Features.call("serverKill", server, {
    kind = "car", x = wx, y = wy, by = byId, victim = driver and driver.id, angle = angle, onFoot = false,
  })
end

--- Public: damage from something that isn't a bullet (a car running you
--- over, Karen's slap). Lands on the car they are driving, or on them.
--- Returns true if the victim was alive to take it.
function Weapons:serverDamage(server, victim, attacker, amount, angle)
  return self:damage(server, victim, attacker and attacker.id, amount, 0, angle)
end

--- Keep wrecks parked at their slot and bring the dead back when their time
--- is up: alive again at the slot, behind the wheel of their own car.
function Weapons:updateWrecks(server)
  local sv = self.sv
  for vid, cs in pairs(sv.cars) do
    local car = server.vehicles[vid]
    if not car then
      sv.cars[vid] = nil -- gone for good (its owner left)
    elseif cs.deadUntil then
      if sv.time < cs.deadUntil then
        car.hidden = true
        car.x, car.y, car.angle = cs.spawn.x, cs.spawn.y, cs.spawn.angle
        car:stop()
      else
        cs.deadUntil, cs.hp = nil, cs.max
        car.hidden = false
        car.x, car.y, car.angle = cs.spawn.x, cs.spawn.y, cs.spawn.angle
        car:stop()
        server:broadcast(Protocol.encode("WPN_CARHP", car.id, cs.hp))
      end
    end
  end
  for id, st in pairs(sv.players) do
    if st.deadUntil then
      local p = server.players[id]
      local own = p and p.car
      if not (p and p.body) then
        st.deadUntil = nil
      elseif sv.time < st.deadUntil then
        if own then
          own.hidden = true
          own.x, own.y, own.angle = st.spawn.x, st.spawn.y, st.spawn.angle
          own:stop()
        end
      else
        st.deadUntil = nil
        p.body.dead = false
        p.body.x, p.body.y, p.body.facing = st.spawn.x, st.spawn.y, st.spawn.angle
        if own then
          own.hidden = false
          own.x, own.y, own.angle = st.spawn.x, st.spawn.y, st.spawn.angle
          own:stop()
          if not p.vehicle then
            server:seat(p, own)
          end
        end
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
