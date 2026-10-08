-- Police: patrol cars that cruise the city slowly and mind their own
-- business until they witness a crime. Shooting, wrecking a car, flattening
-- a pedestrian or ramming someone within a unit's sight makes you wanted;
-- every unit that can see you then chases and shoots, siren on, until the
-- wanted time runs out with no new crimes, or you get wrecked.
--
-- Sight is a 180 degree fan out of the windscreen (vision.lua), and walls
-- block it: a crime behind a building goes unseen, and a wanted player who
-- breaks line of sight for a few seconds is lost. Clients draw every cone
-- as a faint white fan, so you can see where you are being watched.
--
-- Units are NPCs from the bots feature with a police brain. On a chase
-- they stop and shoot once they are near and have you in sight, drive
-- after you by the streets when you are not, and back off for a moment
-- when you shoot back (pursuit.lua). Clients draw
-- the livery and flashing lights over the car and play the siren.
--
-- The force also walks a beat: officers on foot (officers.lua) patrol the
-- streets around the players, witness crimes exactly as a patrol car does,
-- and draw a pistol on anyone wanted -- sprinting after them, shooting from
-- where they stand. They are soft targets in return: shoot one and you are
-- wanted on the spot, run one down and dispatch hears about it either way.
-- Clients only draw what POL_FOOT tells them (render.lua), and mark them on
-- the minimap and the big map as small blue dots (`drawOnMinimap`).
--
-- A cop who sees something can pass remark on it without doing anything
-- (`Police:serverRemark`, another feature's line): the nearest witness says
-- it in a bubble over their head.
--
-- With inclusive mode on (the menu toggle), every human starts the game
-- wanted with the whole force already in pursuit: get away first.
--
-- The force keeps out of a city event's way (a boss loose in the streets):
-- while any feature answers `serverEventActive` the units keep cruising and
-- the beat keeps walking, but nobody is wanted and no crime is seen, so
-- nobody gets chased or shot. The units run their roof lights the whole
-- time (no siren). Back to normal once the event is over.
--
-- Messages
--   server -> all  POL_UNIT   <id>              this player is a police car
--   server -> all  POL_SIREN  <id> <0|1>        chasing state changed
--   server -> all  POL_WANTED <playerId> <0|1>  wanted state changed
--   server -> all  POL_LIGHTS <0|1>             an event is on: every unit's lights flash
--   server -> all  POL_FOOT   <tick> [<id> <x> <y> <facing> <alert> <hp>]...
--                                               (unreliable, 15 Hz)
--   server -> all  POL_DOWN   <id> <x> <y> <angle>   an officer went down
--   server -> all  POL_SAY    <u|o> <id> <text>  a unit (its player id) or an officer says something

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local UI = require("src.ui")
local Car = require("src.car")
local Sounds = require("src.features.police.sounds")
local Officers = require("src.features.police.officers")
local Render = require("src.features.police.render")
local Vision = require("src.features.police.vision")
local Pursuit = require("src.features.police.pursuit")
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
Police.patrolSpeed = 150 -- px/s on patrol, by the traffic rules (bots/traffic.lua); a chase has no limit
Police.ramCrime = 220 -- closing speed (px/s) of a ram that counts as a crime
Police.hotStartTime = 30 -- seconds of heat everyone starts with in inclusive mode
Police.whistleRange = 1200 -- px; an officer blowing their whistle further away isn't heard
Police.loseSightTime = 4 -- seconds a chasing unit keeps after someone it can no longer see
Police.remarkEvery = 6 -- seconds before the same cop passes another remark

local FOOT_SYNC_EVERY = 2 -- server ticks between POL_FOOT broadcasts

-- Client state --------------------------------------------------------------
Police.units = {} -- id -> { siren = Source|nil, chasing = bool }
Police.wanted = {} -- player id -> true
Police.lights = false -- an event is on: every unit flashes its lights
Police.remarks = {} -- "u<id>" / "o<id>" -> { kind, id, text, t }: what a cop is saying
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
  self.lights = false
  self.remarks = {}
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
  for key, r in pairs(self.remarks) do
    r.t = r.t - dt
    if r.t <= 0 then
      self.remarks[key] = nil
    end
  end
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
--- car's left, blue on its right. While chasing (or during an event) the
--- halves strobe against each other and throw alternating red/blue light on
--- the road.
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
--- Every cone of vision on screen, then the officers. A cone is only worth
--- drawing when its owner is near enough to the camera for it to show;
--- one whose owner is chasing or has drawn a gun strobes red and blue.
local function drawCones(client, camera)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local reach = (math.sqrt(w * w + h * h) / 2) / s
  local function near(x, y, range)
    return (x - camera.x) ^ 2 + (y - camera.y) ^ 2 <= (reach + range) ^ 2
  end
  for id, u in pairs(Police.units) do
    local c = client:vehicleOf(id)
    if c and near(c.dx, c.dy, Police.sightRange) then
      Vision.draw(c.dx, c.dy, c.dangle, Police.sightRange, u.chasing, flash)
    end
  end
  for _, o in pairs(Render.officers) do
    if o.hp > 0 and near(o.dx, o.dy, Officers.SIGHT) then
      Vision.draw(o.dx, o.dy, o.angle, Officers.SIGHT, o.alert, flash)
    end
  end
end

function Police:drawBelowCars(client, camera)
  if not Features.any("hideSightCones") then -- the ` key (sight-cones)
    drawCones(client, camera)
  end
  Render.draw(camera, flash)
end

--- Officers on foot on the minimap and the big map (the `drawOnMinimap`
--- hook; the minimap draws the units in their cars itself): a small blue
--- dot each, flashing red and blue while I am wanted, as the units do. A
--- little bigger on the big map, which is wider than 400 px.
function Police:drawOnMinimap(client, toMap, w)
  local r = w > 400 and 4 or 2
  local red = self.wanted[client.myId] and math.floor(flash * 4) % 2 == 1
  for _, o in pairs(Render.officers) do
    if o.hp > 0 then
      local px, py = toMap(o.dx, o.dy)
      love.graphics.setColor(0, 0, 0, 0.75)
      love.graphics.circle("fill", px, py, r + 1)
      if red then
        love.graphics.setColor(1, 0.2, 0.2)
      else
        love.graphics.setColor(0.25, 0.45, 1)
      end
      love.graphics.circle("fill", px, py, r)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- `text` in a police-blue bubble over (x, y), the tail pointing down.
local function drawRemark(x, y, text, alpha)
  local font = UI.fonts.small
  local maxW = 200
  local w, wrapped = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 14
  local h = #wrapped * font:getHeight() + 10
  local bx, by = x - w / 2, y - h - 22
  love.graphics.setColor(0, 0, 0, 0.4 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 5)
  love.graphics.setColor(0.10, 0.14, 0.30, 0.92 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 5)
  love.graphics.polygon("fill", x - 5, by + h - 1, x + 5, by + h - 1, x, by + h + 8)
  love.graphics.setColor(0.55, 0.70, 1.00, 0.85 * alpha)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("line", bx, by, w, h, 5)
  love.graphics.setFont(font)
  love.graphics.setColor(0.90, 0.94, 1.00, alpha)
  love.graphics.printf(text, bx + 7, by + 5, w - 14, "center")
end

function Police:drawAboveCars(client)
  for id, u in pairs(self.units) do
    local c = client:vehicleOf(id)
    if c then
      drawLivery(c, u.chasing or self.lights)
    end
  end
  for _, r in pairs(self.remarks) do
    local x, y
    if r.kind == "u" then
      local c = client:vehicleOf(r.id)
      x, y = c and c.dx, c and c.dy
    else
      local o = Render.officers[r.id]
      x, y = o and o.dx, o and o.dy
    end
    if x then
      drawRemark(x, y, r.text, math.min(1, r.t * 2))
    end
  end
  love.graphics.setColor(1, 1, 1)
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
  POL_LIGHTS = function(_client, args)
    Police.lights = args[1] == "1"
  end,
  POL_SAY = function(_client, args)
    local kind, id, text = args[1], tonumber(args[2]), args[3]
    if (kind == "u" or kind == "o") and id and text then
      Police.remarks[kind .. id] = { kind = kind, id = id, text = text, t = 2.5 + #text / 20 }
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

local sv = nil -- { units = {}, wanted = { id -> until }, time, remarked = { "u<id>"/"o<id>" -> time } }

local function bots()
  return Features.byName.bots
end

local function unitsInSight(x, y, range)
  local n = 0
  for _, u in pairs(sv.units) do
    local car = u.car
    if car and not car.hidden and Vision.canSee(car.x, car.y, car.angle, x, y, range) then
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

--- A cop who can see (x, y) passes remark `text` on it, and does nothing
--- else: the first patrol car in sight, else an officer on the beat facing
--- it. The same cop says nothing more for `remarkEvery` seconds. Returns
--- true if somebody said it.
function Police:serverRemark(server, x, y, text)
  if not sv then
    return false
  end
  local kind, id
  for _, u in ipairs(sv.units) do
    local car = u.car
    if car and not car.hidden and Vision.canSee(car.x, car.y, car.angle, x, y, self.sightRange) then
      kind, id = "u", u.id
      break
    end
  end
  if not kind then
    local o = sv.officers:seer(x, y, Officers.SIGHT)
    kind, id = o and "o", o and o.id
  end
  if not kind then
    return false
  end
  local key = kind .. id
  if (sv.remarked[key] or -math.huge) + self.remarkEvery > sv.time then
    return true -- they saw it, and have said their piece
  end
  sv.remarked[key] = sv.time
  server:broadcast(Protocol.encode("POL_SAY", kind, id, text))
  return true
end

--- Nobody is wanted while an event is on (`sv.event`): the force keeps out of it.
function Police:setWanted(server, player)
  if not (sv and not sv.event and player and not player.police and player.body) then
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
  local victim = kill.victim and server.players[kill.victim]
  -- An officer on foot down (their own announcement, officerDown, comes
  -- through here too) or a unit wrecked: maybe something to pick up, by
  -- pickups' odds like any enemy.
  local lost = kill.kind == "police" or (kill.kind == "car" and victim and victim.police)
  local pickups = Features.byName.pickups
  if lost and pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, kill.x, kill.y)
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
    Pursuit.shotBy(victim, attacker.id, sv and sv.time or 0) -- shot by who it is after: it backs off a moment
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

function Police:serverShotAt(server, x, y, radius, by, angle, _damage, _dtype, from)
  -- The force's own rounds belong to nobody; so do a gang's, but those say
  -- where they came from (`from`) and do hit.
  if not sv or (by == Officers.OWNER and not from) then
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
  else
    sv.officers:shotAt(server, o, by, angle) -- they turn on whoever it was
  end
  return true
end

--- The officers on foot after player `id` right now (after anybody, for no
--- `id`), on the host: { id, x, y } each. For something that stands up to
--- them (a Gang Hangout's guards).
function Police:serverOfficersAfter(id)
  local out = {}
  local of = sv and sv.officers
  for i = 1, of and of.n or 0 do
    local o = of.list[i]
    if o.target and (id == nil or o.target == id) then
      out[#out + 1] = { id = o.id, x = o.x, y = o.y }
    end
  end
  return out
end

--- Where officer `id` stands on the host, or nil once they are down or off duty.
function Police:serverOfficer(id)
  local of = sv and sv.officers
  for i = 1, of and of.n or 0 do
    local o = of.list[i]
    if o.id == id then
      return o.x, o.y
    end
  end
  return nil
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

--- The wanted player this unit goes after: the nearest one it can see. A
--- unit not yet chasing has to see them out of the windscreen; one already
--- on a chase watches all round, out to pursuit range, and keeps after the
--- last person it saw for loseSightTime once a building hides them.
local function nearestWanted(server, unit, dt)
  local ai = unit.ai
  local chasing = ai.chasing
  local range = chasing and Police.pursuitRange or Police.sightRange
  local best, bestD2
  for id in pairs(sv.wanted) do
    local p = server.players[id]
    if p and Features.visible(server, p) then
      local bx, by = Features.bodyPose(server, p) -- them on foot, or their car
      local d2 = Vision.canSee(unit.car.x, unit.car.y, unit.car.angle, bx, by, range, chasing)
      if d2 and (not bestD2 or d2 < bestD2) then
        best, bestD2 = p, d2
      end
    end
  end
  if best then
    ai.lastSeen, ai.lostFor = best.id, 0
    return best
  end
  -- Out of sight: stay on the last one for a while, if they are still about.
  if chasing and ai.lastSeen then
    local p = server.players[ai.lastSeen]
    ai.lostFor = (ai.lostFor or 0) + dt
    if p and sv.wanted[p.id] and Features.visible(server, p) and ai.lostFor < Police.loseSightTime then
      local bx, by = Features.bodyPose(server, p)
      if (bx - unit.car.x) ^ 2 + (by - unit.car.y) ^ 2 <= Police.pursuitRange ^ 2 then
        return p
      end
    end
  end
  ai.lastSeen = nil
  return nil
end

function Brain.think(server, unit, dt)
  local B = bots()
  local target = nearestWanted(server, unit, dt)
  local chasing = target ~= nil
  if chasing ~= (unit.ai.chasing or false) then
    unit.ai.chasing = chasing
    server:broadcast(Protocol.encode("POL_SIREN", unit.id, chasing and 1 or 0))
  end
  if target then
    Pursuit.drive(server, B, unit, target, sv.time, dt) -- stop and shoot, or chase (pursuit.lua)
  else
    Pursuit.reset(unit)
    B:cruise(server, unit, Police.patrolSpeed)
    B.unstick(unit, dt)
  end
end

function Brain.wrecked(server, unit)
  Pursuit.reset(unit)
  if unit.ai.chasing then
    unit.ai.chasing = false
    server:broadcast(Protocol.encode("POL_SIREN", unit.id, 0))
  end
end

function Police:serverStart(server)
  sv = { units = {}, wanted = {}, time = 0, officers = Officers.new(), footSync = 0, remarked = {} }
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
      -- Onto the nearest human for the whole hot start, walls or not.
      local nearest, nearD2
      for id in pairs(sv.wanted) do
        local p = server.players[id]
        if p and p.body then
          local bx, by = Features.bodyPose(server, p)
          local d2 = (bx - unit.car.x) ^ 2 + (by - unit.car.y) ^ 2
          if not nearD2 or d2 < nearD2 then
            nearest, nearD2 = id, d2
          end
        end
      end
      unit.ai.lastSeen, unit.ai.lostFor = nearest, -self.hotStartTime
      server:broadcast(Protocol.encode("POL_SIREN", unit.id, 1))
    end
  end
end

--- An event started (`on`) or ended. Everyone's heat is dropped and every
--- screen flashes the units' lights; setWanted refuses anyone meanwhile.
local function standDown(server, on)
  for id in pairs(sv.wanted) do
    Police:clearWanted(server, id)
  end
  server:broadcast(Protocol.encode("POL_LIGHTS", on and 1 or 0))
end

function Police:serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local event = Features.any("serverEventActive", server)
  if event ~= (sv.event or false) then
    sv.event = event
    standDown(server, event)
  end
  for id, until_ in pairs(sv.wanted) do
    local p = server.players[id]
    if not p or not Features.present(p) or sv.time >= until_ then
      self:clearWanted(server, id) -- got away, gave up, or got wrecked
    end
  end

  -- The beat, after the heat is settled so an officer hunts this tick's
  -- wanted list, not the last one's. No beat on a map with no crowd or no
  -- police (city-map's `map.crowd`, `map.police`); the patrol cars are
  -- bots' NPCs, and bots parks those.
  local city = Features.byName["city-map"]
  if city and city.map and (city.map.crowd == false or city.map.police == false) then
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

--- A human who joins a running game hears which cars are units, which of
--- them are chasing, who is wanted and whether the lights are on for an
--- event (all sent only on change). With
--- inclusive mode on they start wanted, like everyone did.
function Police:serverPlayerJoined(server, player)
  if not (sv and server.started) or player.bot then
    return
  end
  for _, unit in ipairs(sv.units) do
    if server.players[unit.id] then
      server:send(player, Protocol.encode("POL_UNIT", unit.id))
      if unit.ai.chasing then
        server:send(player, Protocol.encode("POL_SIREN", unit.id, 1))
      end
    end
  end
  for id in pairs(sv.wanted) do
    server:send(player, Protocol.encode("POL_WANTED", id, 1))
  end
  if sv.event then
    server:send(player, Protocol.encode("POL_LIGHTS", 1))
  end
  if Face.inclusive() and player.body and not sv.event then
    sv.wanted[player.id] = sv.time + self.hotStartTime
    server:broadcast(Protocol.encode("POL_WANTED", player.id, 1))
  end
end

function Police:serverPlayerLeft(server, player)
  if sv then
    self:clearWanted(server, player.id)
  end
end

--- The `serverWalkers` convention: officers on foot, so the traffic stops
--- for them too.
function Police:serverWalkers(_server, add)
  local officers = sv and sv.officers
  if officers then
    for i = 1, officers.n do
      local o = officers.list[i]
      add(o.x, o.y)
    end
  end
end

--- For tests.
function Police.server()
  return sv
end

--- The footsteps feature's hook: who of mine is walking about, and where.
function Police:footstepWalkers()
  local list = {}
  for id, o in pairs(Render.officers) do
    list[#list + 1] = { key = id, x = o.dx, y = o.dy, size = "person" }
  end
  return list
end

return Police
