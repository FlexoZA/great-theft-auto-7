-- Weapons: left mouse button fires a projectile from your car toward the
-- cursor. The server owns projectiles, hit detection, health and respawns.
-- Clients predict projectile flight from WPN_SHOT and draw everything.
--
-- There is more than one gun (guns.lua): the number keys pick one, the
-- client tells the host, and the host fires whatever it has on record for
-- that player, with that gun's damage, rate of fire and scatter. The
-- pistol hits hard and straight; the uzi sprays.
--
-- The rocket launcher fires a missile (a gun with a `blast` in guns.lua):
-- it flies slower, trails smoke, and explodes where it hits a player, a car,
-- a wall or a soft target, or in mid-air when its flight runs out. The blast
-- hurts everyone and every car within its radius, the shooter included, less
-- towards the edge, and takes out a few soft targets (pedestrians, officers,
-- Karen's simps) around it through the `serverShotAt` convention.
-- A round that stops at a wall raises `serverWallHit` and every blast
-- raises `serverBlast`, so walls that can be hurt (players' buildings) take
-- the damage.
-- Everyone starts with a gun's `stock` of rounds (5 rockets, for testing).
--
-- You carry your guns in `slotCount` weapon slots, one per number key:
-- key 1 fires whatever is in slot 1. Everyone starts with the pistol in
-- slot 1 and any gun with a `stock` (guns.lua, for testing) in the next
-- ones. A gun is also an item ("gun-<key>", a weapons factory makes them):
-- on the inventory screen you drag one from your bag onto an empty slot to
-- carry it (WPN_EQUIP takes the item), drag a gun from its slot into the
-- bag to put it down (WPN_UNEQUIP gives the item back and leaves the slot
-- empty; the pistol stays), or drag it onto another slot to change its key
-- (WPN_MOVE, swapping with whatever was there). The host keeps the slots
-- and tells you them (WPN_GUNS); the HUD only lists those, and the host
-- refuses to select or fire a gun that isn't in one (serverOwns). Putting
-- down the gun in hand leaves you holding the pistol. Nothing is trusted
-- from the client but the ask. A saved world keeps a player's slots and
-- magazines for next time (serverSavePlayer); health comes back full.
--
-- Guns come in tiers (tiers/init.lua): a "gun-uzi@rare" item is an uzi
-- that hits harder and fires faster (guns.lua's `tierStats`). A player
-- carries one of each gun, in whatever tier they put in its slot; the host
-- keeps the tier with the slot, fires the gun's tuned numbers and gives the
-- item back in that tier when it is put down. Dragging another tier of a
-- gun you carry onto the slots swaps it for the one you have (the pistol
-- too: it can be traded up, never put down).
--
-- Guns hold a magazine (guns.lua): the pistol 15 rounds, the uzi 30. The
-- reload key (X) refills the one in hand from the ammo in your inventory
-- (the buildings feature keeps it, "ammo-pistol"), any time it isn't full;
-- pulling the trigger on an empty magazine reloads too. A reload takes a
-- moment, sounds for everyone near, and is lost if you switch guns or die.
-- Everyone starts with full magazines and no spare rounds, and comes back
-- from the dead with a full pistol, so nobody is left unarmed for good.
-- Without the buildings feature the reserve is bottomless. Bots, police
-- and shots nobody owns never run dry, and nor does a player handed
-- infinite ammo (the cheats feature does it, Weapons:serverSetInfiniteAmmo):
-- their magazines stay full and they never reload.
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
-- Another feature may take both over (the garage): a player it gives a
-- place to (`serverRespawnPoint`) comes back there on foot, their car left
-- where it is, and a wreck it claims (`serverWreckClaimed`) is its to keep.
--
-- Messages
--   client -> server  WPN_FIRE <aimAngle>
--   client -> server  WPN_SELECT <gun>                 (index into guns.lua)
--   client -> server  WPN_RELOAD
--   client -> server  WPN_EQUIP <gun>[@<tier>] <slot>  (the gun item I carry, into that slot)
--   client -> server  WPN_UNEQUIP <slot>               (the gun in that slot, into my bag)
--   client -> server  WPN_MOVE <slot> <slot>           (swap two slots)
--   server -> all     WPN_SHOT <pid> <owner> <x> <y> <vx> <vy> <gun> [<quiet>]
--                                              (quiet 1: a pellet after the first; no sound)
--   server -> all     WPN_HIT  <pid> <victim> <hp>                (someone on foot)
--   server -> all     WPN_KILL <pid> <killer> <victim> <killerKills> <deathTime>
--   server -> all     WPN_CARHIT <pid> <vid> <hp>                 (a car)
--   server -> all     WPN_WRECK <pid> <killer> <vid> <driver> <killerKills> <deathTime>
--   server -> all     WPN_CARHP <vid> <hp>           (a repair or a respawn; no hit effects)
--   server -> all     WPN_HEALTH <id> <hp>          (a heal; no hit effects)
--   server -> all     WPN_MAX <id> <max>            (their health ceiling changed)
--   server -> all     WPN_CARMAX <vid> <max>        (a car's health ceiling, when it isn't CAR_HEALTH)
--   server -> all     WPN_STOP <pid>                (shot swallowed by a soft target)
--   server -> all     WPN_BOOM <pid> <x> <y> <radius>  (a missile went off there)
--   server -> all     WPN_RELOADING <id> <gun> <seconds>   (a reload began)
--   server -> player  WPN_MAG <gun> <rounds>        (what is in a magazine now)
--   server -> player  WPN_INFINITE <0|1>            (infinite ammo off / on)
--   server -> player  WPN_GUNS <gun[@tier] per slot>...  (what is in each weapon slot; 0 = empty)
--
-- Health has a ceiling per player, MAX_HEALTH to start with; another feature
-- can raise it (upgrades buys it with koins) through Weapons:serverSetMaxHealth.
-- Every car has CAR_HEALTH unless another feature gives it its own through
-- Weapons:serverSetCarMaxHealth (vehicles does, per model); Weapons:serverHeal tops up the body first and
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
local Rockets = require("src.features.weapons.rockets")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Icons = require("src.features.weapons.icons")
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
--- one pedestrian out of a crowd rather than the whole queue. `team` is the
--- side a round fired for a side carries (nil for a player's).
local function shotSomething(server, x, y, by, angle, team)
  for _, f in ipairs(Features.list) do
    if f.serverShotAt and f:serverShotAt(server, x, y, PROJECTILE_RADIUS, by, angle, team) then
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

-- Client state (reset in enterGame and resetSynced) -------------------------

Weapons.projectiles = {} -- pid -> { x, y, vx, vy, age, owner }
Weapons.health = {} -- player id -> hp (absent = full)
Weapons.maxHealth = {} -- player id -> ceiling (absent = MAX_HEALTH)
Weapons.carHealth = {} -- vehicle id -> hp (absent = full)
Weapons.carMax = {} -- vehicle id -> health ceiling (absent = CAR_HEALTH)
Weapons.kills = {} -- player id -> kills
Weapons.hitFlash = {} -- player id -> seconds left (on foot)
Weapons.carFlash = {} -- vehicle id -> seconds left
Weapons.feed = nil -- { text, t }
Weapons.cooldown = 0
local LOW_HEALTH = 0.3 -- below this fraction the health bar flashes
Weapons.hudSlot = 0 -- health's slot in the bottom-left row of stat bars (UI.drawStatBar)
Weapons.hudIconScale = 1.8 -- the gun in hand, drawn big beside the ability circles (icons are 60 x 30 at 1)
Weapons.hudIconW, Weapons.hudIconH = 140, 54 -- room for the longest gun (the shotgun) at that scale
Weapons.lowMagazine = 0.25 -- at or under this share of a magazine the reload key flashes over the gun
Weapons.gun = Guns.DEFAULT -- index of the gun I hold (the host keeps its own record)
Weapons.slotCount = 4 -- weapon slots, on the number keys 1..slotCount
Weapons.slots = {} -- slot -> gun index for the guns I carry (the host says: WPN_GUNS)
Weapons.tiers = {} -- gun index -> tier key of the one I carry, when it isn't common (WPN_GUNS too)
Weapons.mags = {} -- gun index -> rounds in my magazine (predicted; the host corrects)
Weapons.reloading = nil -- { gun, t, total } while my reload runs
Weapons.ammoNotice = nil -- { text, t }: "out of ammo" and the like
Weapons.infiniteAmmo = false -- my magazines never empty (the host says so: WPN_INFINITE)
Weapons.showHitboxes = false
Weapons.deadTimer = 0 -- seconds until my own car respawns (client)
Weapons.armed = false -- held fire only counts once the button has been seen released in-game
Weapons.camera = nil -- last camera seen in update; needed to aim through pans and zoom

function Weapons:load()
  Sounds.load()
  self:resetSynced()
  Controls.register("fire", "Fire", "mouse1")
  Controls.register("hitboxes", "Show hitboxes", "f1")
  Controls.register("reload", "Reload", "x") -- R went to the abilities
  for i = 1, self.slotCount do
    Controls.register("weapon-" .. i, ("Weapon slot %d"):format(i), tostring(i))
  end
end

--- What the host tells us about everyone (health, ceilings, my slots and
--- magazines). It arrives just before the game is entered -- WPN_GUNS from
--- serverStart, a latecomer's catch-up from serverPlayerJoined -- so it is
--- only cleared on the way out, never on the way in.
function Weapons:resetSynced()
  self.health = {}
  self.maxHealth = {}
  self.carHealth = {}
  self.carMax = {}
  self.kills = {}
  self.slots = self:startSlots()
  self.tiers = {}
  self.mags = {}
  for i, gun in ipairs(Guns.list) do
    self.mags[i] = gun.magazine
  end
  self.infiniteAmmo = false
end

--- Gun `index` as I carry it: its tier's numbers (tiers/init.lua).
function Weapons:gunAt(index)
  return Tiers.apply(Guns.at(index), self.tiers[index])
end

--- The tier key of gun `index` as I carry it.
function Weapons:tierOf(index)
  return self.tiers[index] or Tiers.DEFAULT
end

function Weapons:enterGame()
  self.projectiles = {}
  self.hitFlash = {}
  self.carFlash = {}
  self.feed = nil
  self.cooldown = 0
  self.gun = Guns.DEFAULT
  self.reloading = nil
  self.ammoNotice = nil
  self.camera = nil
  self.deadTimer = 0
  self.armed = false -- the click on "Start game" is still held on the first frame
  Explosions.clear()
  Rockets.clear()
end

function Weapons:exitGame()
  self:resetSynced()
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

--- Spare rounds for gun `index` in my inventory (bottomless without the
--- buildings feature, as on the host).
function Weapons:reserve(index)
  local buildings = Features.byName.buildings
  if not (buildings and buildings.inventory) then
    return math.huge
  end
  return buildings.inventory["ammo-" .. Guns.at(index).key] or 0
end

local function notify(self, text)
  self.ammoNotice = { text = text, t = 1.6 }
end

--- Ask the host to reload the gun in hand. Refused here when it can't
--- happen: already reloading, magazine full, nothing to load.
function Weapons:tryReload(client)
  local gun = self:gunAt(self.gun)
  if self.reloading or self.infiniteAmmo then
    return
  elseif (self.mags[self.gun] or 0) >= gun.magazine then
    notify(self, "Magazine full")
  elseif self:reserve(self.gun) < 1 then
    notify(self, "No " .. gun.name .. " ammo")
  else
    client:send(Protocol.encode("WPN_RELOAD"))
  end
end

function Weapons:tryFire(client)
  if self.cooldown > 0 or self.reloading or Features.any("held", client, client.myId) then
    return -- cooling down, reloading, or held still (frozen)
  elseif Features.any("pointerTaken", client) then
    return -- a screen (the inventory) has the mouse
  elseif Features.any("fireTaken", client) then
    return -- the fire button is placing an ability (the MG nest)
  end
  local aim = self:aimAngle(client)
  if not aim then
    return
  end
  local gun = self:gunAt(self.gun)
  self.cooldown = gun.cooldown
  if (self.mags[self.gun] or 0) < 1 then
    -- Click. Reload if there is anything to load, say so if not.
    local x, y = client:myPose()
    Sounds.play("dry", x, y)
    self.armed = false -- one click per pull, not a buzz while held
    if self:reserve(self.gun) > 0 then
      self:tryReload(client)
    else
      notify(self, "Out of " .. gun.name .. " ammo")
    end
    return
  end
  if not self.infiniteAmmo then
    self.mags[self.gun] = self.mags[self.gun] - 1
  end
  client:send(Protocol.encode("WPN_FIRE", ("%.3f"):format(aim)))
end

--- Switch to gun `index` and tell the host. The cooldown carries over, so
--- swapping is no faster than waiting.
--- The weapon slots everyone starts with: the pistol in slot 1, then any
--- gun with a `stock`, as far as the slots go.
function Weapons:startSlots()
  local slots = { [1] = Guns.DEFAULT }
  local n = 1
  for i, gun in ipairs(Guns.list) do
    if gun.stock and i ~= Guns.DEFAULT and n < self.slotCount then
      n = n + 1
      slots[n] = i
    end
  end
  return slots
end

--- The slot gun `index` sits in, or nil. Works on any slot map.
local function slotOf(slots, index)
  for slot, gun in pairs(slots) do
    if gun == index then
      return slot
    end
  end
  return nil
end

--- Do I carry gun `index`, as far as the host has told me?
function Weapons:owns(index)
  return slotOf(self.slots, index) ~= nil
end

--- The slot gun `index` is in, or nil.
function Weapons:slotOf(index)
  return slotOf(self.slots, index)
end

--- Ask to put the gun item I carry for gun `index` in tier `tier` into
--- weapon slot `slot` (the inventory screen does, on a drag); another tier
--- of a gun I carry swaps with it wherever it is. The host answers with WPN_GUNS.
function Weapons:equip(client, index, slot, tier)
  tier = tier or Tiers.DEFAULT
  if Guns.list[index] and (not self:owns(index) or self:tierOf(index) ~= tier)
    and slot >= 1 and slot <= self.slotCount then
    client:send(Protocol.encode("WPN_EQUIP", Tiers.join(tostring(index), tier), slot))
  end
end

--- Ask to put the gun in weapon slot `slot` down into my bag.
function Weapons:unequip(client, slot)
  local gun = self.slots[slot]
  if gun and gun ~= Guns.DEFAULT then
    client:send(Protocol.encode("WPN_UNEQUIP", slot))
  end
end

--- Ask to swap weapon slots `from` and `to` (either may be empty).
function Weapons:move(client, from, to)
  if from ~= to and self.slots[from] and to >= 1 and to <= self.slotCount then
    client:send(Protocol.encode("WPN_MOVE", from, to))
  end
end

function Weapons:selectGun(client, index)
  if not Guns.list[index] or index == self.gun then
    return
  elseif not self:owns(index) then
    notify(self, "No " .. Guns.at(index).name .. ": a weapons factory makes them")
    return
  end
  self.gun = index
  self.reloading = nil -- the host drops it too
  client:send(Protocol.encode("WPN_SELECT", index))
end

function Weapons:mousepressed(_x, _y, button, client)
  if Controls.isMouse("fire", button) then
    self:tryFire(client)
  end
end

--- The wheel steps through the guns in my weapon slots, down for the next
--- slot and up for the one before, round the end, skipping empty slots.
--- Not while a screen or menu of anyone's has the mouse or the number keys.
function Weapons:wheelmoved(_dx, dy, client)
  if dy == 0 or Features.any("menuOpen", client) or Features.any("pointerTaken", client) then
    return
  end
  local from = 1
  for slot = 1, self.slotCount do
    if self.slots[slot] == self.gun then
      from = slot
    end
  end
  local step = dy < 0 and 1 or -1
  for k = 1, self.slotCount - 1 do
    local slot = (from - 1 + step * k) % self.slotCount + 1
    if self.slots[slot] and Guns.list[self.slots[slot]] then
      self:selectGun(client, self.slots[slot])
      return
    end
  end
end

function Weapons:keypressed(key, client)
  if Controls.is("hitboxes", key) then
    self.showHitboxes = not self.showHitboxes
  elseif Controls.is("fire", key) then
    self:tryFire(client)
  elseif Controls.is("reload", key) then
    self:tryReload(client)
  else
    -- The number keys, unless a menu (the upgrade shop, a building) has them
    -- for the moment.
    if Features.any("menuOpen", client) then
      return
    end
    for i = 1, self.slotCount do
      if Controls.is("weapon-" .. i, key) then
        if self.slots[i] then
          self:selectGun(client, self.slots[i])
        end
        return
      end
    end
  end
end

function Weapons:update(dt, client, camera)
  self.camera = camera
  self.cooldown = math.max(0, self.cooldown - dt)
  if not self:owns(self.gun) then
    self.gun, self.reloading = Guns.DEFAULT, nil -- the host does the same when a gun is put down
  end
  local held = Controls.isDown("fire")
  if not held then
    self.armed = true
  elseif self.armed then
    self:tryFire(client)
  end
  for pid, p in pairs(self.projectiles) do
    local gun = Guns.at(p.gun)
    p.x = p.x + p.vx * dt
    p.y = p.y + p.vy * dt
    p.age = p.age + dt
    local spent = p.age > (gun.ttl or PROJECTILE_TTL) or blocked(p.x, p.y)
    if gun.blast then
      Rockets.trail(p, dt)
      -- A missile goes off when the host says so (WPN_BOOM); until then it
      -- sits where it struck. Dropped only if that message never comes.
      if spent then
        p.vx, p.vy = 0, 0
      end
      if p.age > (gun.ttl or PROJECTILE_TTL) + 1 then
        self.projectiles[pid] = nil
      end
    elseif spent then
      self.projectiles[pid] = nil
    end
  end
  Rockets.update(dt)
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
  if self.reloading then
    self.reloading.t = self.reloading.t + dt -- the host says when it's done (WPN_MAG)
  end
  if self.ammoNotice then
    self.ammoNotice.t = self.ammoNotice.t - dt
    if self.ammoNotice.t <= 0 then
      self.ammoNotice = nil
    end
  end
  Explosions.update(dt)
  Explosions.shakeCamera(camera)
end

function Weapons:drawBelowCars()
  Explosions.drawBelow()
end

function Weapons:drawAboveCars(client)
  Rockets.drawTrail()
  Explosions.drawAbove()

  -- Projectiles as short streaks along their direction of travel; missiles
  -- as themselves.
  love.graphics.setLineWidth(2)
  local now = love.timer.getTime()
  for _, p in pairs(self.projectiles) do
    local gun = Guns.at(p.gun)
    if gun.blast then
      Rockets.drawMissile(p, now)
    else
      local len = math.sqrt(p.vx * p.vx + p.vy * p.vy)
      local nx, ny = p.vx / len * gun.streak, p.vy / len * gun.streak
      love.graphics.setColor(1, 0.9, 0.3)
      love.graphics.line(p.x - nx, p.y - ny, p.x, p.y)
    end
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
    local max = self.carMax[vid] or CAR_HEALTH
    bar(v.dx, v.dy, self.carHealth[vid] or max, max, Car.WIDTH, Car.HEIGHT / 2 + 8)
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

--- The gun in hand, bottom centre just left of the ability circles: its
--- icon drawn large on a dark backing, and under it the name, rounds over
--- magazine size and spares; red (and the gun faded) when the magazine is
--- empty, amber with a bar under the gun while it reloads. Over the block,
--- once the magazine is nearly out, the reload key flashes red; a notice
--- (out of ammo, no such gun) takes its place while it shows.
function Weapons:drawMagazine()
  local w, h = love.graphics.getDimensions()
  if not Guns.list[self.gun] then
    return
  end
  local gun = self:gunAt(self.gun)
  local abilities = Features.byName.abilities
  local right = abilities and abilities.hudLeft and abilities:hudLeft() - 16 or math.floor(w / 2 + 80)
  local small, body = UI.fonts.small, UI.fonts.body
  local mag, spare = self.mags[self.gun] or 0, self:reserve(self.gun)
  local count = self.infiniteAmmo and "inf" or ("%d/%d"):format(mag, gun.magazine)
  local extra = (not self.infiniteAmmo and spare ~= math.huge) and (" +%d"):format(spare) or ""
  local empty = not self.infiniteAmmo and mag < 1
  local color, alpha = { 1, 1, 1 }, 1
  if self.reloading then
    color, alpha = { 1, 0.9, 0.3 }, 0.6
  elseif empty then
    color, alpha = { 1, 0.45, 0.4 }, 0.45
  end
  -- Over the block once the magazine is nearly out: the reload key, or
  -- that there is nothing left to load. Not while a reload runs.
  local hint
  if not (self.infiniteAmmo or self.reloading) and mag <= gun.magazine * self.lowMagazine then
    hint = spare < 1 and "no ammo" or Controls.name(Controls.bindings("reload")[1]) .. ": reload"
  end
  local name = gun.name .. "  "
  local nameW, countW, extraW = small:getWidth(name), body:getWidth(count), small:getWidth(extra)
  local textW = nameW + countW + extraW
  -- The same width whichever gun is up: the widest line any gun could
  -- have, and room for the longest picture.
  local blockW = self.hudIconW
  for _, g in ipairs(Guns.list) do
    local full = ("%d/%d"):format(g.magazine, g.magazine)
    blockW = math.max(blockW, small:getWidth(g.name .. "  ") + body:getWidth(full) + small:getWidth(" +999"))
  end
  local cx = right - blockW / 2
  local y = h - 8 - body:getHeight() -- the count line, along the bottom
  local top = y - 12 - self.hudIconH
  -- A dark backing so the steel reads over a pale road as well as a dark one.
  love.graphics.setColor(0.05, 0.05, 0.07, 0.55)
  love.graphics.rectangle("fill", math.floor(cx - blockW / 2) - 8, top, blockW + 16, h - 4 - top, 8)
  Icons.draw(gun.key, cx, y - 6 - self.hudIconH / 2, self.hudIconScale, alpha)
  if self.ammoNotice then
    -- Why a pick or a reload didn't happen, over the block while it fades.
    local text = self.ammoNotice.text
    love.graphics.setFont(body)
    UI.label(text, math.floor(cx - body:getWidth(text) / 2), top - 4 - body:getHeight(),
      { 1, 0.45, 0.4, math.min(1, self.ammoNotice.t * 2) })
  elseif hint then
    local blink = 0.5 + 0.5 * math.sin(love.timer.getTime() * 10)
    local big = UI.fonts.heading
    love.graphics.setFont(big)
    UI.label(hint, math.floor(cx - big:getWidth(hint) / 2), top - 4 - big:getHeight(),
      { 1, 0.25 + 0.2 * blink, 0.2 + 0.2 * blink, 0.45 + 0.55 * blink })
  end
  local x = math.floor(cx - textW / 2)
  local baseline = y + body:getHeight() - small:getHeight() - 1
  love.graphics.setFont(small)
  UI.label(name, x, baseline, Tiers.color(self:tierOf(self.gun))) -- in its tier's colour
  love.graphics.setFont(body)
  UI.label(count, x + nameW, y, color)
  love.graphics.setFont(small)
  UI.label(extra, x + nameW + countW, baseline, { 0.75, 0.75, 0.8 })
  if self.reloading then
    local r = self.reloading
    local bw = self.hudIconW
    UI.meter(math.floor(cx - bw / 2), y - 6, bw, 4, math.min(1, r.t / r.total), color)
  end
  love.graphics.setFont(small)
end

function Weapons:drawHUD(client)
  local max = self.maxHealth[client.myId] or MAX_HEALTH
  local hp = self.health[client.myId] or max
  -- Kills top left; health, the car's and the guns have their own readouts
  -- (the bar bottom left, the one over the car, the gun in hand).
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(1, 1, 1)
  love.graphics.print(("kills %d"):format(self.kills[client.myId] or 0), 10, 46)
  -- Health stands first in the bottom-left row of stat bars: always red,
  -- and flashing once it is down to under 30%.
  local frac = hp / max
  local color, valueColor = { 0.9, 0.2, 0.2 }, { 1, 1, 1 }
  if frac < LOW_HEALTH then
    local blink = 0.5 + 0.5 * math.sin(love.timer.getTime() * 12)
    color = { 0.9 + 0.1 * blink, 0.2 + 0.3 * blink, 0.2 + 0.3 * blink, 0.55 + 0.45 * blink }
    valueColor = { 1, 0.5 + 0.5 * blink, 0.45 + 0.55 * blink }
  end
  UI.drawStatBar(self.hudSlot, "health", frac, color, ("%d"):format(hp), valueColor)
  self:drawMagazine()

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
  return client:nameOf(id) or ("#" .. tostring(id)) -- a shot can land after its owner left
end

--- An explosion at (x, y) on this screen, with the camera shaking the
--- nearer I am. `color` tints the debris.
local function boom(client, x, y, color)
  Sounds.play("explosion", x, y)
  Explosions.spawn(x, y, color)
  local mx, my = client:myPose()
  if mx and Video.get("screenShake") then
    local dist = math.sqrt((x - mx) ^ 2 + (y - my) ^ 2)
    Explosions.addShake(SHAKE_MAX * math.max(0, 1 - dist / SHAKE_RADIUS))
  end
end

--- Where a player is drawn, as a point, or nil while they are out of the world.
--- An explosion drawn and heard at (x, y) on this machine, for another
--- feature's blast (a building coming down). `color` tints the debris.
function Weapons:explosionAt(client, x, y, color)
  boom(client, x, y, color)
end

local function poseOf(client, id)
  local x, y = clientPose(client, id)
  return x and { x = x, y = y } or nil
end

Weapons.clientMessages = {
  WPN_MAG = function(_client, args)
    local gun, rounds = tonumber(args[1]), tonumber(args[2])
    if Guns.list[gun] and rounds then
      Weapons.mags[gun] = rounds
      if Weapons.reloading and Weapons.reloading.gun == gun then
        Weapons.reloading = nil
      end
    end
  end,
  WPN_GUNS = function(_client, args)
    local slots, tiers = {}, {}
    for slot, a in ipairs(args) do
      local base, tier = Tiers.split(a)
      local index = tonumber(base)
      if Guns.list[index] and tier and slot <= Weapons.slotCount then
        slots[slot] = index
        tiers[index] = tier ~= Tiers.DEFAULT and tier or nil
      end
    end
    Weapons.slots, Weapons.tiers = slots, tiers
  end,
  WPN_INFINITE = function(_client, args)
    Weapons.infiniteAmmo = args[1] == "1"
    if Weapons.infiniteAmmo then
      Weapons.reloading, Weapons.ammoNotice = nil, nil
    end
  end,
  WPN_RELOADING = function(client, args)
    local id, gun, seconds = tonumber(args[1]), Guns.list[tonumber(args[2]) or 0], tonumber(args[3])
    if not (id and gun and seconds) then
      return
    end
    local x, y = clientPose(client, id)
    if x then
      Sounds.play(gun.reloadSound, x, y)
    end
    if id == client.myId then
      Weapons.reloading = { gun = gun.index, t = 0, total = seconds }
    end
  end,
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
    local quiet = args[8] == "1"
    if pid and x and y and vx and vy then
      Weapons.projectiles[pid] = {
        x = x, y = y, vx = vx, vy = vy, age = 0, owner = owner, gun = gun.index, angle = math.atan2(vy, vx),
      }
      if not quiet then
        Sounds.play(gun.sound, x, y, gun.pitch * (0.9 + love.math.random() * 0.2))
      end
    end
  end,
  --- A missile went off. Whatever it hurt follows as the usual hits, kills
  --- and wrecks.
  WPN_BOOM = function(client, args)
    local pid, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if pid then
      Weapons.projectiles[pid] = nil
    end
    if x and y then
      boom(client, x, y, { 0.35, 0.38, 0.3 })
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
  WPN_CARMAX = function(_client, args)
    local vid, max = tonumber(args[1]), tonumber(args[2])
    if vid and max then
      Weapons.carMax[vid] = max
    end
  end,
  --- A car blew up. Its driver, if it had one, is standing beside it now.
  WPN_WRECK = function(client, args)
    local pid, killer, vid = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local driver, kills = tonumber(args[4]), tonumber(args[5])
    local v = vid and client.vehicles[vid]
    local at = (pid and Weapons.projectiles[pid]) or (v and { x = v.dx, y = v.dy })
    if at then
      boom(client, at.x, at.y, v and Car.paletteColor(v.color))
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
      boom(client, at.x, at.y, victim and Car.colorFor(victim))
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

--- Gun `index` as `st` (a player's record on the host) carries it: its
--- tier's numbers.
local function gunOf(st, index)
  return Tiers.apply(Guns.at(index), st.tiers and st.tiers[index])
end

--- The item gun `index` is as `st` carries it: "gun-uzi", "gun-uzi@rare".
local function gunItem(st, index)
  return Tiers.join("gun-" .. Guns.at(index).key, st.tiers and st.tiers[index])
end

--- Every gun loaded: how a player starts.
local function fullMagazines()
  local mags = {}
  for i, gun in ipairs(Guns.list) do
    mags[i] = gun.magazine
  end
  return mags
end

function Weapons:serverStart(server)
  local sv = { time = 0, projectiles = {}, nextId = 1, players = {}, cars = {}, targets = {} }
  for id, p in pairs(server.players) do
    if p.body then
      sv.players[id] = {
        hp = MAX_HEALTH,
        max = MAX_HEALTH,
        kills = 0,
        gun = Guns.DEFAULT,
        slots = self:startSlots(),
        tiers = {}, -- gun index -> tier key of the one in their slots, when it isn't common
        mags = fullMagazines(),
        spawn = { x = p.body.x, y = p.body.y, angle = p.body.facing },
        lastFire = -math.huge,
        protectedUntil = SPAWN_PROTECTION,
      }
    end
  end
  self.sv = sv
  for _, p in pairs(server.players) do
    self:giveStock(server, p)
    self:sendGuns(server, p)
  end
end

--- Tell `player` what is in each of their weapon slots (WPN_GUNS). Bots
--- aren't listening.
function Weapons:sendGuns(server, player)
  local st = self.sv and self.sv.players[player.id]
  if not st or player.bot then
    return
  end
  local list = {}
  for slot = 1, self.slotCount do
    local index = st.slots[slot]
    list[slot] = index and Tiers.join(tostring(index), st.tiers and st.tiers[index]) or 0
  end
  server:send(player, Protocol.encode("WPN_GUNS", unpack(list)))
end

--- Spare rounds of every gun with a `stock` (guns.lua) into a human player's
--- inventory: the stock less the magazine they start with loaded. Bots never
--- run dry, so they get none.
function Weapons:giveStock(server, player)
  local buildings = Features.byName.buildings
  if player.bot or not (player.body and buildings and buildings.serverGive) then
    return
  end
  for _, gun in ipairs(Guns.list) do
    if gun.stock and gun.stock > gun.magazine then
      buildings:serverGive(server, player, "ammo-" .. gun.key, gun.stock - gun.magazine)
    end
  end
end

--- A player (human or bot) added while the game is running.
function Weapons:serverPlayerJoined(server, player)
  if self.sv and player.body and not self.sv.players[player.id] then
    self.sv.players[player.id] = {
      hp = MAX_HEALTH,
      max = MAX_HEALTH,
      kills = 0,
      gun = Guns.DEFAULT,
      slots = self:startSlots(),
      tiers = {},
      mags = fullMagazines(),
      spawn = { x = player.body.x, y = player.body.y, angle = player.body.facing },
      lastFire = -math.huge,
      protectedUntil = self.sv.time + SPAWN_PROTECTION,
    }
    self:giveStock(server, player)
    self:sendGuns(server, player)
  end
  if self.sv and player.body and not player.bot then
    self:sendHealth(server, player)
  end
end

--- A latecomer catches up on everyone's health and every car's that isn't
--- the default (absent means full on the client), sent only on change.
function Weapons:sendHealth(server, player)
  for id, st in pairs(self.sv.players) do
    if id ~= player.id then
      if st.max ~= MAX_HEALTH then
        server:send(player, Protocol.encode("WPN_MAX", id, st.max))
      end
      if st.hp ~= st.max then
        server:send(player, Protocol.encode("WPN_HEALTH", id, st.hp))
      end
    end
  end
  for vid, cs in pairs(self.sv.cars) do
    if server.vehicles[vid] then
      if cs.max ~= CAR_HEALTH then
        server:send(player, Protocol.encode("WPN_CARMAX", vid, cs.max))
      end
      if cs.hp ~= cs.max and not cs.deadUntil then
        server:send(player, Protocol.encode("WPN_CARHP", vid, cs.hp))
      end
    end
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

function Weapons:serverPlayerLeft(server, player)
  if self.sv then
    -- Left while dead: their own car stays in the world (the core keeps it)
    -- but nobody is coming back to unhide it, so it is back at the slot now.
    local st = self.sv.players[player.id]
    local own = player.car
    local cs = own and self.sv.cars[own.id]
    if st and st.deadUntil and not st.respawnAt and own and own.hidden and not own.kept and server.vehicles[own.id]
      and not (cs and cs.deadUntil) then
      own.hidden = false
      own.x, own.y, own.angle = st.spawn.x, st.spawn.y, st.spawn.angle
      own:stop()
    end
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

--- `player`'s hit points and ceiling on the host, or nil for a player this
--- feature doesn't know. A passive heal reads this to stop at the body.
function Weapons:serverHealth(player)
  local st = self.sv and self.sv.players[player.id]
  if not st then
    return nil
  end
  return st.hp, st.max
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

--- A car's hit points and ceiling on the host, hidden or not (the garage
--- shows the cars it keeps off the road).
function Weapons:serverCarHealth(car)
  if not self.sv then
    return nil
  end
  local cs = self:carState(car)
  return cs.hp, cs.max
end

--- Set a car's hit points outright, hidden or not, between 1 and its
--- ceiling (the garage mends the cars it keeps, and puts back saved damage).
function Weapons:serverSetCarHealth(server, car, hp)
  if not (self.sv and car) then
    return
  end
  local cs = self:carState(car)
  cs.hp = math.max(1, math.min(cs.max, math.floor(hp)))
  server:broadcast(Protocol.encode("WPN_CARHP", car.id, cs.hp))
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

--- Give `car` a health ceiling of its own, `max`, for as long as it exists
--- (wrecks come back with it), and fill it up to it. Vehicles gives each
--- model its hitpoints this way. Returns the new ceiling, or nil before a
--- game.
function Weapons:serverSetCarMaxHealth(server, car, max)
  if not (self.sv and car) then
    return nil
  end
  local cs = self:carState(car)
  max = math.max(1, math.floor(max))
  cs.max, cs.hp = max, max
  server:broadcast(Protocol.encode("WPN_CARMAX", car.id, max))
  server:broadcast(Protocol.encode("WPN_CARHP", car.id, max))
  return max
end

--- Put a projectile into the world at (x, y), flying along `aim` (radians)
--- and belonging to player `ownerId`. Pass 0 for a shot that belongs to no
--- player: the police officers on foot fire this way, so their bullets hit
--- everyone (nobody is the owner) and their kills go on nobody's scoreboard.
--- No cooldown is applied here; the caller owns its own rate of fire. `gun`
--- is a table from guns.lua (the pistol when not given); its scatter is
--- applied here. `team` marks a round fired by one side of a team fight (a
--- turf war tower's): it flies through and spares anyone `serverFriendly`
--- says is on that side.
function Weapons:serverFireFrom(server, ownerId, x, y, aim, gun, team)
  local sv = self.sv
  if not (sv and aim) then
    return false
  end
  gun = gun or Guns.at(Guns.DEFAULT)
  ownerId = ownerId or NO_OWNER
  -- A shotgun sends several pellets per pull, each scattered on its own;
  -- clients sound only the first (the trailing 1 marks the rest quiet).
  for pellet = 1, gun.pellets or 1 do
    local a = aim
    if gun.spread > 0 then
      a = a + (love.math.random() * 2 - 1) * gun.spread
    end
    local pid = sv.nextId
    sv.nextId = pid + 1
    local vx = math.cos(a) * gun.speed
    local vy = math.sin(a) * gun.speed
    sv.projectiles[#sv.projectiles + 1] = {
      id = pid, owner = ownerId, x = x, y = y, vx = vx, vy = vy, age = 0, damage = gun.damage,
      ttl = gun.ttl or PROJECTILE_TTL, blast = gun.blast, team = team,
    }
    server:broadcast(Protocol.encode("WPN_SHOT", pid, ownerId,
      ("%.1f"):format(x), ("%.1f"):format(y), ("%.1f"):format(vx), ("%.1f"):format(vy), gun.index,
      pellet > 1 and 1 or 0))
  end
  -- `player` is nil for an ownerless shot; features that listen must allow it.
  Features.call("serverShotFired", server, server.players[ownerId], x, y)
  return true
end

--- Does `player` carry gun `index` in a weapon slot on the host? Bots and
--- police carry them all.
function Weapons:serverOwns(player, index)
  local st = self.sv and self.sv.players[player.id]
  if not (st and Guns.list[index]) then
    return false
  end
  return player.bot or slotOf(st.slots, index) ~= nil
end

--- `player` takes the gun item they carry for gun `index` in tier `tier`
--- and puts the gun in weapon slot `slot`. A gun already there goes back
--- into the bag as an item, in its tier; the pistol never leaves its slots,
--- so it can't be swapped out. Another tier of a gun they already carry
--- swaps with that one in its own slot, whatever `slot` says (the pistol
--- too). Returns true if it happened.
function Weapons:serverEquip(server, player, index, slot, tier)
  local st = self.sv and self.sv.players[player.id]
  local gun = Guns.list[index]
  local buildings = Features.byName.buildings
  tier = tier or Tiers.DEFAULT
  if not (st and gun and slot and Tiers.byKey[tier] and buildings and buildings.serverTake
    and Features.present(player)) then
    return false
  elseif slot < 1 or slot > self.slotCount then
    return false -- no such slot
  end
  st.tiers = st.tiers or {}
  local have = slotOf(st.slots, index)
  if have then
    if (st.tiers[index] or Tiers.DEFAULT) == tier then
      return false -- they carry that one already
    end
    slot = have -- trading it for another tier, where it is
  end
  local old = st.slots[slot]
  if old == Guns.DEFAULT and index ~= Guns.DEFAULT then
    return false
  end
  local item = Tiers.join("gun-" .. gun.key, tier)
  if buildings:serverTake(server, player, item, 1) < 1 then
    return false -- they don't carry one
  end
  if old and buildings:serverGive(server, player, gunItem(st, old), 1) < 1 then
    buildings:serverGive(server, player, item, 1) -- no room for the old one: nothing changes
    return false
  end
  if old and old ~= index then
    st.tiers[old] = nil
  end
  if st.gun == old then
    st.gun, st.reloadUntil = index, nil -- the hand holds what is in that slot now
  end
  st.slots[slot] = index
  st.tiers[index] = tier ~= Tiers.DEFAULT and tier or nil
  local most = gunOf(st, index).magazine
  if (st.mags[index] or 0) > most then
    st.mags[index] = most -- a smaller magazine than the last one's
    server:send(player, Protocol.encode("WPN_MAG", index, most))
  end
  self:sendGuns(server, player)
  return true
end

--- `player` puts the gun in weapon slot `slot` down into their bag as an
--- item, if there is room, leaving the slot empty; the pistol can't be put
--- down. Returns true if they do.
function Weapons:serverUnequip(server, player, slot)
  local st = self.sv and self.sv.players[player.id]
  local index = st and slot and st.slots[slot]
  local gun = index and Guns.list[index]
  local buildings = Features.byName.buildings
  if not (gun and buildings and buildings.serverGive and Features.present(player)) or index == Guns.DEFAULT then
    return false
  end
  if buildings:serverGive(server, player, gunItem(st, index), 1) < 1 then
    return false -- no room in their bag
  end
  st.slots[slot] = nil
  if st.tiers then
    st.tiers[index] = nil
  end
  if st.gun == index then
    st.gun, st.reloadUntil = Guns.DEFAULT, nil
  end
  self:sendGuns(server, player)
  return true
end

--- `player` swaps weapon slots `from` and `to` (either may be empty): the
--- guns change keys, nothing else. Returns true if they did.
function Weapons:serverMove(server, player, from, to)
  local st = self.sv and self.sv.players[player.id]
  if not (st and from and to and Features.present(player)) or from == to then
    return false
  elseif from < 1 or from > self.slotCount or to < 1 or to > self.slotCount or not st.slots[from] then
    return false
  end
  st.slots[from], st.slots[to] = st.slots[to], st.slots[from]
  self:sendGuns(server, player)
  return true
end

-- Saved worlds (docs/persistence.md) ----------------------------------------

local SAVE_VERSION = 1

--- `player`'s part of a saved world: the gun key in each weapon slot (with
--- its tier: "uzi@rare") and the rounds in each magazine, by gun key so a reordered guns.lua can't
--- mix them up. Spare rounds are items in the bag (buildings saves those);
--- health, kills, the gun in hand and infinite ammo are not kept.
function Weapons:serverSavePlayer(_server, player)
  local st = self.sv and self.sv.players[player.id]
  if not st or player.bot then
    return nil
  end
  local slots, mags = {}, {}
  for slot = 1, self.slotCount do
    local gun = st.slots[slot] and Guns.list[st.slots[slot]]
    if gun then
      slots[slot] = Tiers.join(gun.key, st.tiers and st.tiers[gun.index])
    end
  end
  for i, gun in ipairs(Guns.list) do
    mags[gun.key] = st.mags[i] or 0
  end
  if st.deadUntil then
    local pistol = gunOf(st, Guns.DEFAULT)
    mags[pistol.key] = math.max(mags[pistol.key], pistol.magazine) -- they'd be back with it loaded
  end
  return { version = SAVE_VERSION, slots = slots, mags = mags }
end

--- Put back what serverSavePlayer kept, over the start loadout. Guns no
--- longer in guns.lua, bad slots and repeats are dropped; the pistol always
--- has a slot; magazines hold 0 to their size.
function Weapons:serverLoadPlayer(server, player, data)
  local st = self.sv and self.sv.players[player.id]
  if not st or type(data) ~= "table" or (tonumber(data.version) or 0) > SAVE_VERSION then
    return
  end
  if type(data.slots) == "table" then
    local slots, tiers = {}, {}
    for slot = 1, self.slotCount do
      local key, tier
      if type(data.slots[slot]) == "string" then
        key, tier = Tiers.split(data.slots[slot])
      end
      local gun = key and Guns[key]
      if type(gun) == "table" and gun.key == key and tier and not slotOf(slots, gun.index) then
        slots[slot] = gun.index
        tiers[gun.index] = tier ~= Tiers.DEFAULT and tier or nil
      end
    end
    st.tiers = tiers
    if not slotOf(slots, Guns.DEFAULT) then
      local free = 1 -- the first empty slot, or slot 1 when all are full
      for slot = self.slotCount, 1, -1 do
        if not slots[slot] then
          free = slot
        end
      end
      slots[free] = Guns.DEFAULT
    end
    st.slots = slots
    if not slotOf(slots, st.gun) then
      st.gun, st.reloadUntil = Guns.DEFAULT, nil
    end
  end
  if type(data.mags) == "table" then
    for i, gun in ipairs(Guns.list) do
      local rounds = tonumber(data.mags[gun.key])
      if rounds and rounds == rounds then
        st.mags[i] = math.max(0, math.min(gunOf(st, i).magazine, math.floor(rounds)))
      end
    end
  end
  self:sendGuns(server, player)
  if not player.bot then
    for i in ipairs(Guns.list) do
      server:send(player, Protocol.encode("WPN_MAG", i, st.mags[i]))
    end
  end
end

--- The gun `player` holds, dropped back to the pistol if it is no longer
--- theirs. The client does the same on its own.
local function heldGun(self, player, st)
  if not self:serverOwns(player, st.gun) then
    st.gun, st.reloadUntil = Guns.DEFAULT, nil
  end
  return st.gun
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
  local gun = gunOf(st, heldGun(self, player, st))
  if sv.time - st.lastFire < gun.cooldown * 0.9 then
    return false -- firing faster than allowed; drop it
  end
  if Features.any("serverHeld", server, player) then
    return false -- held still (frozen): the trigger is stuck too
  end
  local counted = not (player.bot or st.infiniteAmmo) -- bots, police and cheaters never run dry
  if counted and (st.reloadUntil or (st.mags[st.gun] or 0) < 1) then
    -- Reloading, or empty: nothing leaves the barrel. Put the shooter's
    -- count right, in case their prediction ran ahead.
    server:send(player, Protocol.encode("WPN_MAG", st.gun, st.mags[st.gun] or 0))
    return false
  end
  if counted then
    st.mags[st.gun] = st.mags[st.gun] - 1
  end
  st.lastFire = sv.time

  local bx, by, onFoot = bodyPose(server, player)
  local muzzle = onFoot and FOOT_MUZZLE or MUZZLE_OFFSET
  return self:serverFireFrom(server, player.id, bx + math.cos(aim) * muzzle, by + math.sin(aim) * muzzle, aim, gun)
end

--- Turn infinite ammo on or off for `player`, for the rest of the game
--- (death doesn't end it). On, every magazine is filled and any reload
--- dropped; off, they carry on from full. Other features reach this via
--- Features.byName.weapons (cheats does). Returns the new setting, or nil
--- for a player this feature doesn't know.
function Weapons:serverSetInfiniteAmmo(server, player, on)
  local st = self.sv and self.sv.players[player.id]
  if not st then
    return nil
  end
  st.infiniteAmmo = on and true or nil
  if on then
    st.reloadUntil = nil
    for i in ipairs(Guns.list) do
      st.mags[i] = gunOf(st, i).magazine
      server:send(player, Protocol.encode("WPN_MAG", i, st.mags[i]))
    end
  end
  server:send(player, Protocol.encode("WPN_INFINITE", on and 1 or 0))
  return on and true or false
end

--- Whether `player` has infinite ammo, on the host.
function Weapons:serverHasInfiniteAmmo(player)
  local st = self.sv and self.sv.players[player.id]
  return st ~= nil and st.infiniteAmmo == true
end

--- Hand `player` gun `index` on the host (bots could pick one this way).
--- A reload under way is dropped.
function Weapons:serverSelectGun(_server, player, index)
  local st = self.sv and self.sv.players[player.id]
  if not (st and Guns.list[index]) or not self:serverOwns(player, index) then
    return false
  end
  if index ~= st.gun then
    st.reloadUntil = nil
  end
  st.gun = index
  return true
end

--- Spare rounds `player` carries for `gun` (bottomless without buildings).
local function spareRounds(player, gun)
  local buildings = Features.byName.buildings
  if not (buildings and buildings.serverCount) then
    return math.huge
  end
  return buildings:serverCount(player.id, "ammo-" .. gun.key)
end

--- Start reloading the gun `player` holds, if its magazine isn't full and
--- they carry rounds for it. The rounds are taken when it finishes
--- (finishReloads). Returns true if a reload began.
function Weapons:serverReload(server, player)
  local sv = self.sv
  local st = sv and sv.players[player.id]
  if not (st and player.body and Features.present(player)) or st.reloadUntil or st.deadUntil or st.infiniteAmmo then
    return false
  end
  local gun = gunOf(st, heldGun(self, player, st))
  if (st.mags[st.gun] or 0) >= gun.magazine or spareRounds(player, gun) < 1 then
    return false
  end
  st.reloadUntil = sv.time + gun.reload
  server:broadcast(Protocol.encode("WPN_RELOADING", player.id, st.gun, gun.reload))
  return true
end

--- Fill the magazines whose reload is done from the shooter's inventory.
function Weapons:finishReloads(server)
  local sv = self.sv
  for id, st in pairs(sv.players) do
    if st.reloadUntil and sv.time >= st.reloadUntil then
      st.reloadUntil = nil
      local p = server.players[id]
      local gun = gunOf(st, st.gun)
      local need = gun.magazine - (st.mags[st.gun] or 0)
      local buildings = Features.byName.buildings
      local got = need
      if p and buildings and buildings.serverTake then
        got = buildings:serverTake(server, p, "ammo-" .. gun.key, need)
      end
      st.mags[st.gun] = (st.mags[st.gun] or 0) + got
      if p then
        server:send(p, Protocol.encode("WPN_MAG", st.gun, st.mags[st.gun]))
      end
    end
  end
end

Weapons.serverMessages = {
  WPN_FIRE = function(server, player, args)
    Weapons:serverFire(server, player, tonumber(args[1]))
  end,
  WPN_SELECT = function(server, player, args)
    Weapons:serverSelectGun(server, player, tonumber(args[1]))
  end,
  WPN_EQUIP = function(server, player, args)
    local index, tier = Tiers.split(args[1] or "")
    if tier then
      Weapons:serverEquip(server, player, tonumber(index), tonumber(args[2]), tier)
    end
  end,
  WPN_UNEQUIP = function(server, player, args)
    Weapons:serverUnequip(server, player, tonumber(args[1]))
  end,
  WPN_MOVE = function(server, player, args)
    Weapons:serverMove(server, player, tonumber(args[1]), tonumber(args[2]))
  end,
  WPN_RELOAD = function(server, player)
    Weapons:serverReload(server, player)
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
    if
      st
      and Features.present(player)
      and id ~= p.owner
      and self.sv.time >= st.protectedUntil
      and not Features.any("serverFriendly", server, p.owner, player, p.team) -- a team fight: friends are flown through
    then
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
--- building, a pedestrian), or nil when it flew on; then where it stopped.
--- Players are tested before soft targets, so a pedestrian can't be used as
--- a body shield.
function Weapons:sweep(server, p, nx, ny)
  local dx, dy = nx - p.x, ny - p.y
  local steps = math.max(1, math.ceil(math.sqrt(dx * dx + dy * dy) / SWEEP_STEP))
  local angle = math.atan2(p.vy, p.vx)
  local targets, ntargets = self:targets(server, p)
  for s = 1, steps do
    local t = s / steps
    local px, py = p.x + dx * t, p.y + dy * t
    if blocked(px, py) then
      return "wall", px, py
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
        return e, px, py
      end
    end
    if shotSomething(server, px, py, p.owner, angle, p.team) then
      return "soft", px, py
    end
  end
  return nil
end

--- Missile `p` goes off at (x, y). Everyone present and not protected within
--- the blast radius is hurt, the shooter too, from `damage` at the centre
--- down to a third at the edge (measured to the edge of a car or a body);
--- cars nobody drives take it themselves. Soft targets get `soft` rounds'
--- worth: each feature with a `serverShotAt` is asked that many times, so
--- a crowd loses a few and Karen feels it.
function Weapons:explode(server, p, x, y)
  local sv = self.sv
  local blast = p.blast
  local R = blast.radius
  server:broadcast(Protocol.encode("WPN_BOOM", p.id, ("%.1f"):format(x), ("%.1f"):format(y), R))
  local function falloff(d)
    return math.floor(blast.damage * (1 - (2 / 3) * math.min(1, d / R)) + 0.5)
  end
  -- Work out who is caught first, then hurt them: a wreck moves its driver.
  local caught = {}
  for id, player in pairs(server.players) do
    local st = sv.players[id]
    if
      st
      and Features.present(player)
      and sv.time >= st.protectedUntil
      and not Features.any("serverFriendly", server, p.owner, player, p.team)
    then
      local px, py, onFoot = bodyPose(server, player)
      local reach = onFoot and FOOT_RADIUS or Car.WIDTH / 2
      local d = math.max(0, math.sqrt((px - x) ^ 2 + (py - y) ^ 2) - reach)
      if d <= R then
        caught[#caught + 1] = { player = player, amount = falloff(d), angle = math.atan2(py - y, px - x) }
      end
    end
  end
  for _, car in pairs(server.vehicles) do
    if not (car.driver or car.hidden or car.stowed) then
      local d = math.max(0, math.sqrt((car.x - x) ^ 2 + (car.y - y) ^ 2) - Car.WIDTH / 2)
      if d <= R then
        caught[#caught + 1] = { car = car, amount = falloff(d), angle = math.atan2(car.y - y, car.x - x) }
      end
    end
  end
  local by = p.owner ~= NO_OWNER and p.owner or nil
  for _, c in ipairs(caught) do
    if c.player then
      -- Blowing yourself up is nobody's kill.
      self:damage(server, c.player, c.player.id ~= by and by or nil, c.amount, 0, c.angle)
    else
      self:damageCar(server, c.car, by, c.amount, 0, c.angle)
    end
  end
  -- Walls that can take it (a player's building) work out their own share.
  Features.call("serverBlast", server, x, y, R, blast.damage, p.owner)
  local angle = math.atan2(p.vy, p.vx)
  for _, f in ipairs(Features.list) do
    if f.serverShotAt then
      for _ = 1, blast.soft or 0 do
        if not f:serverShotAt(server, x, y, R * 0.75, p.owner, angle, p.team) then
          break
        end
      end
    end
  end
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
  -- A team fight (the `serverFriendly` question): nothing lands between friends.
  if byId and byId ~= NO_OWNER and Features.any("serverFriendly", server, byId, victim) then
    return false
  end
  if victim.vehicle then
    return self:damageCar(server, victim.vehicle, byId, amount, pid, angle) -- the car takes it
  end
  pid = pid or 0
  -- Armor takes its share first (the `serverAbsorbDamage` convention); the
  -- hit still counts as one for everyone listening, even if nothing got through.
  st.hp = st.hp - Features.reduce("serverAbsorbDamage", amount, server, victim)
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
--- `player`'s own car, if it is theirs to take back to their slot: not
--- while somebody else is driving it. A stolen car stays with the thief;
--- hiding it would drag them off the map with it (and leave the owner
--- unable to sit in it when they come back), which is what used to happen.
--- A car another feature keeps out of the world (`car.kept`: the garage's)
--- is not ours to move either.
local function ownCar(player)
  local own = player.car
  if own and ((own.driver and own.driver ~= player.id) or own.kept) then
    return nil
  end
  return own
end

function Weapons:die(server, victim, byId, pid, angle)
  local sv = self.sv
  local st = sv.players[victim.id]
  local kills = self:creditKill(byId)
  st.hp = st.max
  st.reloadUntil = nil
  st.deadUntil = sv.time + DEATH_TIME
  st.protectedUntil = st.deadUntil + SPAWN_PROTECTION
  -- Where it went up: the car they drove, or their feet.
  local wx, wy, wasOnFoot = bodyPose(server, victim)
  victim.body.dead = true
  -- Somewhere else to come back (the garage: a garage or the hospital)? Then
  -- they come back there on foot and their own car stays where it is.
  st.respawnAt = not victim.bot and Features.reduce("serverRespawnPoint", nil, server, victim) or nil
  local own = not st.respawnAt and ownCar(victim)
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
  -- A player's own car goes back to their slot; any other car they own
  -- (one they bought) would land on top of it there, so it stays put. Unless
  -- another feature claims the wreck (the garage): then it is theirs to keep.
  local ownerPlayer = car.owner and server.players[car.owner]
  local owner = ownerPlayer and ownerPlayer.car == car and sv.players[car.owner]
  cs.hp = cs.max
  local deathTime = 0
  if not Features.any("serverWreckClaimed", server, car) then
    deathTime = DEATH_TIME
    cs.deadUntil = sv.time + DEATH_TIME
    cs.spawn = owner and owner.spawn or { x = wx, y = wy, angle = car.angle }
    car.hidden = true
    car.x, car.y, car.angle = cs.spawn.x, cs.spawn.y, cs.spawn.angle
    car:stop()
  end
  server:broadcast(Protocol.encode("WPN_WRECK", pid or 0, byId or 0, car.id, driver and driver.id or 0, kills,
    deathTime))
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
--- is up: alive again at the slot, behind the wheel of their own car (on
--- foot, if somebody drove off in it).
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
      local own = p and not st.respawnAt and ownCar(p)
      if not (p and p.body) then
        st.deadUntil = nil
      elseif sv.time < st.deadUntil then
        if own then
          own.hidden = true
          own.x, own.y, own.angle = st.spawn.x, st.spawn.y, st.spawn.angle
          own:stop()
        end
      else
        local at = st.respawnAt or st.spawn
        st.deadUntil, st.respawnAt = nil, nil
        p.body.dead = false
        p.body.x, p.body.y, p.body.facing = at.x, at.y, at.angle
        -- Back with a loaded pistol, whatever else ran dry.
        st.mags[Guns.DEFAULT] = math.max(st.mags[Guns.DEFAULT] or 0, gunOf(st, Guns.DEFAULT).magazine)
        server:send(p, Protocol.encode("WPN_MAG", Guns.DEFAULT, st.mags[Guns.DEFAULT]))
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
  self:finishReloads(server)
  local i = 1
  while i <= #sv.projectiles do
    local p = sv.projectiles[i]
    p.age = p.age + dt
    local nx, ny = p.x + p.vx * dt, p.y + p.vy * dt
    local victim, hx, hy = self:sweep(server, p, nx, ny)
    p.x, p.y = nx, ny
    if p.blast and (victim or p.age > p.ttl) then
      -- A missile goes off at whatever stopped it, or where it ran out.
      table.remove(sv.projectiles, i)
      self:explode(server, p, hx or nx, hy or ny)
    elseif victim == "wall" then
      table.remove(sv.projectiles, i) -- clients notice the same wall themselves
      Features.call("serverWallHit", server, hx, hy, p.damage or Guns.at(Guns.DEFAULT).damage, p.owner)
    elseif victim == "soft" then
      -- Nothing on the client predicts a pedestrian stepping into a bullet,
      -- so the streak has to be called back explicitly.
      server:broadcast(Protocol.encode("WPN_STOP", p.id))
      table.remove(sv.projectiles, i)
    elseif victim then
      self:hit(server, p, victim)
      table.remove(sv.projectiles, i)
    elseif p.age > p.ttl then
      table.remove(sv.projectiles, i)
    else
      i = i + 1
    end
  end
end

return Weapons
