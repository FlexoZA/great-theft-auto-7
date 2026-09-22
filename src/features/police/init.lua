-- Police: patrol cars that cruise the city slowly and mind their own
-- business until they witness a crime. Shooting, wrecking a car, flattening
-- a pedestrian or ramming someone within a unit's sight makes you wanted;
-- every unit that can see you then chases and shoots, siren on, until the
-- wanted time runs out with no new crimes, or you get wrecked.
--
-- Units are NPCs from the bots feature with a police brain. Clients draw
-- the livery and flashing lights over the car and play the siren.
--
-- Messages
--   server -> all  POL_UNIT   <id>              this player is a police car
--   server -> all  POL_SIREN  <id> <0|1>        chasing state changed
--   server -> all  POL_WANTED <playerId> <0|1>  wanted state changed

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Sounds = require("src.features.police.sounds")

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

-- Client state --------------------------------------------------------------
Police.units = {} -- id -> { siren = Source|nil, chasing = bool }
Police.wanted = {} -- player id -> true
local flash = 0

function Police:load()
  Sounds.load()
end

function Police:enterGame()
  for _, u in pairs(self.units) do
    if u.siren then
      u.siren:stop()
    end
  end
  self.units = {}
  self.wanted = {}
end

function Police:exitGame()
  self:enterGame()
end

function Police:update(dt, client)
  flash = flash + dt
  for id, u in pairs(self.units) do
    local c = client.cars[id]
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

--- White body, dark doors, roof bar; lights strobe red/blue while chasing.
local function drawLivery(c, chasing)
  love.graphics.push()
  love.graphics.translate(c.dx, c.dy)
  love.graphics.rotate(c.dangle)
  love.graphics.setColor(0.92, 0.92, 0.94)
  love.graphics.rectangle("fill", -Car.WIDTH / 2, -Car.HEIGHT / 2, Car.WIDTH, Car.HEIGHT, 4)
  love.graphics.setColor(0.10, 0.10, 0.14)
  love.graphics.rectangle("fill", -6, -Car.HEIGHT / 2, 12, Car.HEIGHT) -- doors
  love.graphics.rectangle("fill", -Car.WIDTH / 2 + 2, -Car.HEIGHT / 2 + 4, 6, Car.HEIGHT - 8) -- boot stripe
  love.graphics.setColor(0.6, 0.8, 1)
  love.graphics.rectangle("fill", 4, -Car.HEIGHT / 2 + 3, 10, Car.HEIGHT - 6) -- windscreen
  -- light bar
  local on = chasing and (math.floor(flash * 8) % 2 == 0)
  love.graphics.setColor(chasing and (on and 1 or 0.4) or 0.5, 0.1, 0.1)
  love.graphics.rectangle("fill", -3, -Car.HEIGHT / 2 - 1, 4, 5)
  love.graphics.setColor(0.1, 0.2, chasing and (on and 0.4 or 1) or 0.5)
  love.graphics.rectangle("fill", -3, Car.HEIGHT / 2 - 4, 4, 5)
  love.graphics.pop()
  if chasing then
    love.graphics.setColor(on and 1 or 0.2, 0.2, on and 0.2 or 1, 0.18)
    love.graphics.circle("fill", c.dx, c.dy, 46)
  end
  love.graphics.setColor(1, 1, 1)
end

function Police:drawAboveCars(client)
  for id, u in pairs(self.units) do
    local c = client.cars[id]
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

local function witnessed(x, y)
  return sv and unitsInSight(x, y, Police.sightRange) > 0
end

function Police:setWanted(server, player)
  if not (sv and player and not player.police and player.car) then
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
  if closing >= self.ramCrime and rammer.car and witnessed(rammer.car.x, rammer.car.y) then
    self:setWanted(server, rammer)
  end
end

--- Shooting a police car is always noticed by that car.
function Police:serverPlayerDamaged(server, victim, attacker)
  if victim.police and attacker then
    self:setWanted(server, attacker)
  end
end

-- The police brain ----------------------------------------------------------

local Brain = {}

local function nearestWanted(server, unit)
  local best, bestD2
  local range = unit.ai.chasing and Police.pursuitRange or Police.sightRange
  for id in pairs(sv.wanted) do
    local p = server.players[id]
    if p and p.car and not p.car.hidden then
      local d2 = (p.car.x - unit.car.x) ^ 2 + (p.car.y - unit.car.y) ^ 2
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
  sv = { units = {}, wanted = {}, time = 0 }
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
end

function Police:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  for id, until_ in pairs(sv.wanted) do
    local p = server.players[id]
    if not p or not p.car or p.car.hidden or sv.time >= until_ then
      self:clearWanted(server, id) -- got away, gave up, or got wrecked
    end
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
