-- Police: patrol cars that cruise the city slowly and mind their own
-- business until they witness a crime. Shooting, wrecking a car, flattening
-- a pedestrian or ramming someone within a unit's sight makes you wanted;
-- every unit that can see you then chases and shoots, siren on, until the
-- wanted time runs out with no new crimes, or you get wrecked.
--
-- Units are NPCs from the bots feature with a police brain. Clients draw
-- the livery and flashing lights over the car and play the siren.
--
-- The force also walks a beat: officers on foot (officers.lua) patrol the
-- streets around the players, witness crimes exactly as a patrol car does,
-- and draw a pistol on anyone wanted -- sprinting after them, shooting from
-- where they stand. They are soft targets in return: shoot one and you are
-- wanted on the spot, run one down and dispatch hears about it either way.
-- Clients only draw what POL_FOOT tells them (render.lua).
--
-- With inclusive mode on (the menu toggle), every human starts the game
-- wanted with the whole force already in pursuit: get away first.
--
-- Messages
--   server -> all  POL_UNIT   <id>              this player is a police car
--   server -> all  POL_SIREN  <id> <0|1>        chasing state changed
--   server -> all  POL_WANTED <playerId> <0|1>  wanted state changed
--   server -> all  POL_FOOT   <tick> [<id> <x> <y> <facing> <alert> <hp>]...
--                                               (unreliable, 15 Hz)
--   server -> all  POL_DOWN   <id> <x> <y> <angle>   an officer went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Sounds = require("src.features.police.sounds")
local Officers = require("src.features.police.officers")
local Render = require("src.features.police.render")
local Face = require("src.art.face")

local Police = {
  name = "police",
  priority = 810, -- after bots (800): they drive the units, we decide who is wanted
}

-- Tuning ------------------------------------------------------------------
Police.count = 2 -- patrol cars at start
Police.sightRange = 750 -- px; a unit witnesses crimes and spots wanted players inside this
Police.pursuitRange = 1400 -- px; a chasing unit keeps after you out to this distance
Police.wantedTime = 25 -- seconds since the last crime before the heat is off
Police.patrolThrottle = 0.45
Police.ramCrime = 220 -- closing speed (px/s) of a ram that counts as a crime
Police.hotStartTime = 30 -- seconds of heat everyone starts with in inclusive mode
Police.whistleRange = 1200 -- px; an officer blowing their whistle further away isn't heard

local FOOT_SYNC_EVERY = 2 -- server ticks between POL_FOOT broadcasts

-- Client state --------------------------------------------------------------
Police.units = {} -- id -> { siren = Source|nil, chasing = bool }
Police.wanted = {} -- player id -> true
local flash = 0

function Police:load()
  Sounds.load()
end

-- POL_UNIT for every patrol car arrives in the same burst as START, just
-- before the game state is entered, so nothing is cleared on the way in.
function Police:enterGame() end

function Police:exitGame()
  for _, u in pairs(self.units) do
    if u.siren then
      u.siren:stop()
    end
  end
  self.units = {}
  self.wanted = {}
  Render.clear()
end

--- One whistle when a nearby officer spots someone wanted. Only the nearest
--- of them, however many turned round at once.
function Police:whistles(client)
  local mx, my = client:myPose()
  if not mx then
    Render.alertedN = 0
    return
  end
  for i = 1, Render.alertedN do
    local o = Render.alerted[i]
    local dx, dy = o.x - mx, o.y - my
    if dx * dx + dy * dy < self.whistleRange * self.whistleRange then
      Sounds.whistle(o.x, o.y)
      break
    end
  end
  Render.alertedN = 0
end

function Police:update(dt, client)
  flash = flash + dt
  Render.update(dt)
  for id, u in pairs(self.units) do
    local c = client:vehicleOf(id)
    if u.chasing and c then
      if not u.siren then
        u.siren = Sounds.newSiren()
        u.siren:play()
      end
      u.siren:setPosition(c.dx, 0, c.dy)
      u.siren:setVolume(Sounds.volumeNow())
    elseif u.siren then
      u.siren:stop()
      u.siren = nil
    end
  end
end

--- White body, dark doors, and a siren bar across the roof: red half on the
--- car's left, blue on its right. While chasing the halves strobe against
--- each other and throw alternating red/blue light on the road.
local STROBE_HZ = 9

local function drawLivery(c, chasing)
  local phase = math.floor(flash * STROBE_HZ) % 2 == 0
  local half = Car.HEIGHT / 2 - 3

  if chasing then
    -- Light thrown on the ground, offset to the side that is lit.
    local side = phase and -1 or 1
    local ox, oy = -math.sin(c.dangle) * side * 10, math.cos(c.dangle) * side * 10
    if phase then
      love.graphics.setColor(1, 0.15, 0.15, 0.28)
    else
      love.graphics.setColor(0.25, 0.45, 1, 0.28)
    end
    love.graphics.circle("fill", c.dx + ox, c.dy + oy, 60)
  end

  love.graphics.push()
  love.graphics.translate(c.dx, c.dy)
  love.graphics.rotate(c.dangle)
  love.graphics.setColor(0.92, 0.92, 0.94)
  love.graphics.rectangle("fill", -Car.WIDTH / 2, -Car.HEIGHT / 2, Car.WIDTH, Car.HEIGHT, 4)
  love.graphics.setColor(0.10, 0.10, 0.14)
  love.graphics.rectangle("fill", -8, -Car.HEIGHT / 2, 14, Car.HEIGHT) -- doors
  love.graphics.rectangle("fill", -Car.WIDTH / 2 + 2, -Car.HEIGHT / 2 + 4, 6, Car.HEIGHT - 8) -- boot stripe
  love.graphics.setColor(0.6, 0.8, 1)
  love.graphics.rectangle("fill", 6, -Car.HEIGHT / 2 + 3, 10, Car.HEIGHT - 6) -- windscreen

  -- Siren bar on the roof, spanning the car's width.
  love.graphics.setColor(0.08, 0.08, 0.12)
  love.graphics.rectangle("fill", -5, -half - 1, 10, half * 2 + 2, 2)
  local redA, blueA = 0.45, 0.45
  if chasing then
    redA = phase and 1 or 0.25
    blueA = phase and 0.25 or 1
  end
  love.graphics.setColor(1, 0.15, 0.15, redA)
  love.graphics.rectangle("fill", -4, -half, 8, half - 1)
  love.graphics.setColor(0.25, 0.45, 1, blueA)
  love.graphics.rectangle("fill", -4, 1, 8, half - 1)
  if chasing then
    -- hot centre of the lit half
    if phase then
      love.graphics.setColor(1, 0.8, 0.8, 0.9)
      love.graphics.rectangle("fill", -2, -half + 2, 4, half - 5)
    else
      love.graphics.setColor(0.8, 0.9, 1, 0.9)
      love.graphics.rectangle("fill", -2, 3, 4, half - 5)
    end
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Officers go under the cars, like the crowd: they are on the road, not
--- above it, and a bumper passes over whatever is left of them.
function Police:drawBelowCars(_client, camera)
  Render.draw(camera, flash)
end

function Police:drawAboveCars(client)
  for id, u in pairs(self.units) do
    local c = client:vehicleOf(id)
    if c then
      drawLivery(c, u.chasing)
    end
  end
end

function Police:drawHUD(client)
  if self.wanted[client.myId] then
    local w = love.graphics.getWidth()
    love.graphics.setFont(UI.fonts.heading)
    local pulse = 0.6 + 0.4 * math.abs(math.sin(flash * 4))
    love.graphics.setColor(1, 0.25, 0.25, pulse)
    love.graphics.printf("WANTED", 0, 70, w, "center")
    love.graphics.setColor(1, 1, 1)
  end
end

Police.clientMessages = {
  POL_UNIT = function(_client, args)
    local id = tonumber(args[1])
    if id then
      Police.units[id] = Police.units[id] or { chasing = false }
    end
  end,
  POL_SIREN = function(_client, args)
    local id, on = tonumber(args[1]), args[2] == "1"
    local u = id and Police.units[id]
    if u then
      u.chasing = on
    end
  end,
  POL_WANTED = function(_client, args)
    local id, on = tonumber(args[1]), args[2] == "1"
    if id then
      Police.wanted[id] = on or nil
    end
  end,
  POL_FOOT = function(client, args)
    Render.sync(args)
    Police:whistles(client)
  end,
  --- An officer went down: the pedestrians' gibs and splat, if that feature
  --- is around, and stop drawing them before the next snapshot says so.
  POL_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if id then
      Render.remove(id)
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle or 0)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.8 + love.math.random() * 0.2)
    end
  end,
}

-- Server ----------------------------------------------------------------

local sv = nil -- { units = {}, wanted = { id -> until }, time }

local function bots()
  return Features.byName.bots
end

local function unitsInSight(x, y, range)
  local n = 0
  for _, u in ipairs(sv.units) do
    if u.car and not u.car.hidden and (u.car.x - x) ^ 2 + (u.car.y - y) ^ 2 <= range * range then
      n = n + 1
    end
  end
  return n
end

--- Did anyone in uniform see that? A patrol car within sight range, or an
--- officer on the beat standing near enough to turn their head.
local function witnessed(x, y)
  if not sv then
    return false
  end
  return unitsInSight(x, y, Police.sightRange) > 0 or sv.officers:sees(x, y, Officers.SIGHT)
end

function Police:setWanted(server, player)
  if not (sv and player and not player.police and player.body) then
    return
  end
  local wasWanted = sv.wanted[player.id] ~= nil
  sv.wanted[player.id] = sv.time + self.wantedTime
  if not wasWanted then
    server:broadcast(Protocol.encode("POL_WANTED", player.id, 1))
  end
end

function Police:clearWanted(server, id)
  if sv and sv.wanted[id] then
    sv.wanted[id] = nil
    server:broadcast(Protocol.encode("POL_WANTED", id, 0))
  end
end

-- Crimes ------------------------------------------------------------------

function Police:serverShotFired(server, player, x, y)
  if witnessed(x, y) then
    self:setWanted(server, player)
  end
end

function Police:serverKill(server, kill)
  local killer = server.players[kill.by]
  if killer and witnessed(kill.x, kill.y) then
    self:setWanted(server, killer)
  end
end

function Police:serverCarsCollided(server, rammer, _rammed, closing)
  if closing >= self.ramCrime and rammer.vehicle and witnessed(rammer.vehicle.x, rammer.vehicle.y) then
    self:setWanted(server, rammer)
  end
end

--- Shooting a police car is always noticed by that car.
function Police:serverPlayerDamaged(server, victim, attacker)
  if victim.police and attacker then
    self:setWanted(server, attacker)
  end
end

-- Officers on foot ----------------------------------------------------------

--- An officer is down: splat them on every screen, let the other features
--- price it (money pays out on kind "police"), and put the heat on whoever
--- did it. Dispatch hears about a dead officer whether anyone watched or not.
function Police:officerDown(server, kill)
  server:broadcast(Protocol.encode("POL_DOWN", kill.id, ("%.0f"):format(kill.x), ("%.0f"):format(kill.y),
    ("%.3f"):format(kill.angle or 0)))
  Features.call("serverKill", server, {
    kind = "police", x = kill.x, y = kill.y, by = kill.by, angle = kill.angle,
  })
  self:setWanted(server, kill.by and server.players[kill.by])
end

--- A bullet passed through (x, y). Officers are soft targets the way
--- pedestrians are (the `serverShotAt` convention), except that it takes a
--- few rounds and the shooter is wanted from the moment they miss. The
--- force's own bullets pass straight through: police don't shoot police.
--- Something froze the world around (x, y) (the `serverFreezeArea` event):
--- officers on foot inside it stand to attention for `seconds`.
function Police:serverFreezeArea(_server, x, y, radius, seconds)
  if sv and sv.officers then
    sv.officers:freeze(x, y, radius, seconds)
  end
end

function Police:serverShotAt(server, x, y, radius, by, angle)
  if not sv or by == Officers.OWNER then
    return false
  end
  local o = sv.officers:at(x, y, radius)
  if not o then
    return false
  end
  o.hp = o.hp - Officers.SHOT_DAMAGE
  self:setWanted(server, server.players[by])
  if o.hp <= 0 then
    sv.officers:remove(o)
    self:officerDown(server, { id = o.id, x = o.x, y = o.y, angle = angle or 0, by = by })
  end
  return true
end

--- One POL_FOOT line for the whole beat. An empty one (just the tick) is
--- worth sending: it tells clients the last officer walked off.
function Police:syncOfficers(server)
  local of = sv.officers
  local parts = { server.tick }
  for i = 1, of.n do
    local o = of.list[i]
    parts[#parts + 1] = o.id
    parts[#parts + 1] = ("%.0f"):format(o.x)
    parts[#parts + 1] = ("%.0f"):format(o.y)
    parts[#parts + 1] = ("%.2f"):format(o.facing)
    parts[#parts + 1] = o.target and 1 or 0
    parts[#parts + 1] = ("%.0f"):format(math.max(0, o.hp))
  end
  local msg = Protocol.encode("POL_FOOT", unpack(parts))
  for _, player in pairs(server.players) do
    server:send(player, msg, true)
  end
end

-- The police brain ----------------------------------------------------------

local Brain = {}

local function nearestWanted(server, unit)
  local best, bestD2
  local range = unit.ai.chasing and Police.pursuitRange or Police.sightRange
  for id in pairs(sv.wanted) do
    local p = server.players[id]
    if p and Features.present(p) then
      local bx, by = Features.bodyPose(server, p) -- them on foot, or their car
      local d2 = (bx - unit.car.x) ^ 2 + (by - unit.car.y) ^ 2
      if d2 <= range * range and (not bestD2 or d2 < bestD2) then
        best, bestD2 = p, d2
      end
    end
  end
  return best
end

function Brain.think(server, unit, dt)
  local B = bots()
  local target = nearestWanted(server, unit)
  local chasing = target ~= nil
  if chasing ~= (unit.ai.chasing or false) then
    unit.ai.chasing = chasing
    server:broadcast(Protocol.encode("POL_SIREN", unit.id, chasing and 1 or 0))
  end
  if target then
    B:fight(server, unit, target)
  else
    B:cruise(unit, Police.patrolThrottle)
  end
  B.unstick(unit, dt)
end

function Brain.wrecked(server, unit)
  if unit.ai.chasing then
    unit.ai.chasing = false
    server:broadcast(Protocol.encode("POL_SIREN", unit.id, 0))
  end
end

function Police:serverStart(server)
  sv = { units = {}, wanted = {}, time = 0, officers = Officers.new(), footSync = 0 }
  local B = bots()
  if not B then
    return
  end
  local spawns = server.spawnPoints or {}
  for i = 1, self.count do
    local x, y, angle = (i - 1) * 140, -500, math.pi / 2
    if #spawns > 0 then
      local s = spawns[#spawns - (i - 1) % #spawns]
      x, y, angle = s.x, s.y, s.angle
    end
    local unit = B:spawnNpc(server, {
      name = "Police " .. i, x = x, y = y, angle = angle, brain = Brain, police = true,
    })
    unit.ai.chasing = false
    sv.units[#sv.units + 1] = unit
    server:broadcast(Protocol.encode("POL_UNIT", unit.id))
  end

  if Face.inclusive() then
    -- Hot start: every human is wanted and every unit is already hunting.
    for _, p in pairs(server.players) do
      if not p.bot and p.body then
        sv.wanted[p.id] = sv.time + self.hotStartTime
        server:broadcast(Protocol.encode("POL_WANTED", p.id, 1))
      end
    end
    for _, unit in ipairs(sv.units) do
      unit.ai.chasing = true -- pursuit range from the first tick
      server:broadcast(Protocol.encode("POL_SIREN", unit.id, 1))
    end
  end
end

function Police:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for id, until_ in pairs(sv.wanted) do
    local p = server.players[id]
    if not p or not Features.present(p) or sv.time >= until_ then
      self:clearWanted(server, id) -- got away, gave up, or got wrecked
    end
  end

  -- The beat, after the heat is settled so an officer hunts this tick's
  -- wanted list, not the last one's. No beat on a map with no crowd
  -- (city-map's `map.crowd`); the patrol cars are bots' NPCs, and bots
  -- parks those.
  local city = Features.byName["city-map"]
  if city and city.map and city.map.crowd == false then
    sv.officers:clear() -- the next POL_FOOT, an empty one, sends them off every screen
  else
    for _, kill in ipairs(sv.officers:update(server, dt, sv.wanted, next(sv.wanted) ~= nil)) do
      self:officerDown(server, kill) -- run down in the street
    end
  end
  sv.footSync = sv.footSync - 1
  if sv.footSync <= 0 then
    sv.footSync = FOOT_SYNC_EVERY
    self:syncOfficers(server)
  end
end

function Police:serverPlayerLeft(server, player)
  if sv then
    self:clearWanted(server, player.id)
  end
end

--- For tests.
function Police.server()
  return sv
end

return Police
