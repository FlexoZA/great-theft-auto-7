-- The Runner: a city event (see init.lua). A man in a tracksuit comes onto
-- a crossing somewhere away from everyone and sprints the streets, three
-- times as fast as a player's sprint, picking a street at every crossing.
-- He goes after nobody: he keeps to the street grid (bots/traffic.lua's
-- graph), in one lane or the other, and whatever is in his way pays for
-- it. A car he runs into is wrecked on the spot (its driver bails out, the
-- way any wreck goes), a pedestrian he runs through is gibbed, and a player
-- on foot in his way is trampled for `trample` (once per `trampleEvery`
-- seconds each, so standing in his lane hurts but isn't instant death).
--
-- He has a huge lungful (bosses/stamina.lua): about half a minute flat out
-- before he is winded, and then he walks it off for a few seconds, the
-- moment to catch him. Frozen, he stands still; a panic fart turns him
-- round.
--
-- Down, he spills koins and drops his second wind (abilities/secondwind.lua)
-- as a pickup, its tier rolled from `dropTiers`: common half the time,
-- legendary three times in a hundred.
--
-- The host owns him; clients hear where he is at 15 Hz and draw him ahead
-- along the way he is running, so he doesn't trail his own position.
--
-- Messages (the events feature registers them)
--   server -> all  ERN_STATE <tick> <x> <y> <facing> <speed> <hp> <max> <stamina> <winded>  (unreliable, 15 Hz)
--   server -> all  ERN_DOWN  <x> <y> <angle>        he went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Car = require("src.car")
local Traffic = require("src.features.bots.traffic")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")

local Runner = {
  key = "runner",
  title = "THE RUNNER IS LOOSE",
  subtitle = "He tears down the streets wrecking everything in his way. Catch him when he's winded.",
  wonTitle = "THE RUNNER IS DOWN",
  wonSubtitle = "He dropped his second wind. First one there takes it.",
  color = { 1, 0.85, 0.2 },
  menu = "A sprinter three times your speed wrecks cars and people on the streets. Drops second wind.",
}

-- Tuning ------------------------------------------------------------------
Runner.health = 1200 -- 60 pistol rounds, for one player (more humans, more: bosses/init.lua)
Runner.radius = 10
Runner.speed = 510 -- px/s; three times a player's sprint (on-foot's sprintSpeed, 170)
Runner.walkSpeed = 45 -- px/s winded: a player's walk
Runner.breath = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  max = 300, -- three bars' worth: lots of it
  drain = 10, -- per second flat out (30 s)
  regen = 40,
  recovered = 150, -- back before a winded runner runs again (~5 s, the window to get him)
}
Runner.lane = 32 -- px off the centre line he runs at (bots/traffic.lua's lane): one lane or the other
Runner.carReach = 6 -- px past his body and a car's half width that counts as running into it
Runner.carDamage = 100000 -- what running into a car does to it: a wreck, whatever the model
Runner.pedReach = 8 -- px round him that knocks a pedestrian down
Runner.trample = 30 -- what running into a player on foot does to them
Runner.trampleEvery = 1 -- seconds before the same player can be trampled again
Runner.bulletDamage = 20 -- what a round takes off him when it doesn't say (a blast)
Runner.spawnNear = 900 -- px; he comes in about this far from the nearest player
Runner.spawnFar = 1800
Runner.drops = 40 -- koins he spills
Runner.drop = "ability-secondwind" -- the pickup he leaves, in a tier from `dropTiers`
Runner.dropTiers = { -- chance in a hundred of each tier
  { "common", 50 },
  { "uncommon", 30 },
  { "rare", 17 },
  { "legendary", 3 },
}

local SYNC_EVERY = 2 -- server ticks between ERN_STATE packets
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a spawn, not a step
local DRAW_SCALE = 1.4 -- he is drawn a size up from a player, so he reads as a boss

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local Body = require("src.body")

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- A tier from `Runner.dropTiers`, as likely as its weight.
function Runner.rollTier()
  local total = 0
  for _, t in ipairs(Runner.dropTiers) do
    total = total + t[2]
  end
  local roll = random() * total
  for _, t in ipairs(Runner.dropTiers) do
    roll = roll - t[2]
    if roll < 0 then
      return t[1]
    end
  end
  return Runner.dropTiers[1][1]
end

-- Server --------------------------------------------------------------------

local sv = nil -- { r = the runner, events, syncIn }

function Runner.serverStop()
  sv = nil
end

--- The street grid of the city in play, or nil.
local function graph()
  local city = Features.byName["city-map"]
  return city and city.map and Traffic.graph(city.map) or nil
end

--- A crossing away from everyone: about `spawnNear`..`spawnFar` px from the
--- nearest player, the nearest thing to it otherwise.
local function spawnNode(g, server)
  local people = {}
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      people[#people + 1] = { x = x, y = y }
    end
  end
  local best, bestScore
  for _, node in pairs(g.nodes) do
    if #node.exits > 0 then
      local near = Runner.spawnNear
      for i, h in ipairs(people) do
        local d = math.sqrt(dist2(node.x, node.y, h.x, h.y))
        near = i == 1 and d or math.min(near, d)
      end
      local score = -math.max(0, Runner.spawnNear - near) * 2 - math.max(0, near - Runner.spawnFar) + random() * 200
      if not bestScore or score > bestScore then
        best, bestScore = node, score
      end
    end
  end
  return best
end

--- Where the street he is on ends for him: the far crossing, over in his lane.
local function waypoint(r)
  local e = r.street
  -- Right of the way he runs is (-dy, dx) with y pointing down.
  return r.to.x - e.dy * r.side * Runner.lane, r.to.y + e.dx * r.side * Runner.lane
end

--- A street out of crossing `node`: any but straight back where he came
--- from, unless it is a dead end. He takes it in a lane picked at random.
local function pickStreet(r, node)
  local options = {}
  for _, e in ipairs(node.exits) do
    if not (r.street and e.dx == -r.street.dx and e.dy == -r.street.dy) then
      options[#options + 1] = e
    end
  end
  if #options == 0 then
    options = node.exits
  end
  local e = options[random(#options)]
  r.street, r.from, r.to = e, node, e.node
  r.side = random() < 0.5 and 1 or -1
end

function Runner.serverBegin(server, events)
  local g = graph()
  local node = g and spawnNode(g, server)
  if not node then
    return nil
  end
  local hp = Bosses.health(Runner.health, server)
  local r = {
    x = node.x, y = node.y, facing = 0, hp = hp, max = hp, frozen = 0, speed = 0,
    breath = Stamina.new(Runner.breath),
    trampled = {}, -- player id -> when they can be trampled again
  }
  pickStreet(r, node)
  sv = { r = r, events = events, syncIn = 0, time = 0 }
  return node.x, node.y
end

--- Turn round on the street he is on: a stink ahead.
local function turnBack(r)
  local back
  for _, e in ipairs(r.to.exits) do
    if e.node == r.from then
      back = e
    end
  end
  if back then
    r.street, r.from, r.to = back, r.to, r.from
  end
end

--- Run `dist` px along his route, taking the next street at each crossing.
local function run(r, dist)
  for _ = 1, 8 do -- a few crossings at most in one tick
    local wx, wy = waypoint(r)
    local d = math.sqrt(dist2(wx, wy, r.x, r.y))
    if d > dist then
      r.x, r.y = r.x + (wx - r.x) / d * dist, r.y + (wy - r.y) / d * dist
      r.facing = math.atan2(wy - r.y, wx - r.x)
      return
    end
    r.x, r.y, dist = wx, wy, dist - d
    -- The graph is rebuilt when the city grows: carry on from the new one's crossing.
    local g = graph()
    local node = g and g.nodes[r.to.key] or r.to
    pickStreet(r, node)
  end
end

--- Players on foot in his way are trampled: he goes after nobody, but he
--- doesn't go round anybody either. Drivers are hurt through their car.
local function trample(server, r, weapons)
  local reach = Runner.radius + Body.RADIUS
  for _, p in pairs(server.players) do
    if Features.present(p) and (r.trampled[p.id] or 0) <= sv.time then
      local x, y, onFoot = Features.bodyPose(server, p)
      if onFoot and dist2(x, y, r.x, r.y) <= reach * reach then
        r.trampled[p.id] = sv.time + Runner.trampleEvery
        weapons:serverDamage(server, p, nil, Runner.trample, r.facing, "impact")
      end
    end
  end
end

--- Cars in his way are wrecked, pedestrians knocked down, players trampled.
local function smash(server, r)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverDamage then
    trample(server, r, weapons)
  end
  if weapons and weapons.damageCar then
    local reach = Runner.radius + Car.WIDTH / 2 + Runner.carReach
    for _, car in pairs(server.vehicles) do
      if not (car.hidden or car.stowed) and dist2(car.x, car.y, r.x, r.y) <= reach * reach then
        weapons:damageCar(server, car, nil, Runner.carDamage, 0, r.facing, "impact")
      end
    end
  end
  local peds = Features.byName.pedestrians
  if peds and peds.serverShotAt then
    for _ = 1, 6 do -- one at a time, and a crowd is a few
      if not peds:serverShotAt(server, r.x, r.y, Runner.radius + Runner.pedReach, 0, r.facing, nil, "impact") then
        break
      end
    end
  end
end

--- Where he is, to everyone.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local r = sv.r
  local stamina, winded = r.breath:wire()
  local msg = Protocol.encode("ERN_STATE", server.tick, fmt(r.x), fmt(r.y), ("%.2f"):format(r.facing),
    math.floor(r.speed), math.max(0, math.floor(r.hp)), r.max, stamina, winded)
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Runner.serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local r = sv.r
  local running = false
  if r.frozen > 0 then
    r.frozen = r.frozen - dt
    r.speed = 0
  else
    if r.panic then
      r.panic = nil
      turnBack(r)
    end
    r.speed = r.breath:pace(Runner.speed, Runner.walkSpeed)
    running = not r.breath:winded()
    run(r, r.speed * dt)
    smash(server, r)
  end
  r.breath:step(running, dt)
  sync(server)
end

--- He takes `amount`. At zero he goes down: koins, his second wind on the
--- ground, and the event is over.
local function hurt(server, amount, by, angle)
  local r = sv.r
  r.hp = r.hp - amount
  if r.hp > 0 then
    return
  end
  local x, y = r.x, r.y
  server:broadcast(Protocol.encode("ERN_DOWN", fmt(x), fmt(y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, Runner.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    -- Beside the koins, not under them, on clear ground.
    local dx, dy = x, y
    for i = 0, 7 do
      local a = math.pi / 2 + i * math.pi / 4
      local ox, oy = x + math.cos(a) * 60, y + math.sin(a) * 60
      if not Features.any("blocksPoint", ox, oy) then
        dx, dy = ox, oy
        break
      end
    end
    pickups:serverDrop(server, Runner.drop .. "@" .. Runner.rollTier(), dx, dy)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  sv.events:serverFinish(server, x, y)
end

--- A bullet passing through (x, y): the `serverShotAt` convention.
function Runner.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv then
    return false
  end
  local r = sv.r
  if dist2(r.x, r.y, x, y) >= (radius + Runner.radius) ^ 2 then
    return false
  end
  hurt(server, damage or Runner.bulletDamage, by ~= 0 and by or nil, angle)
  return true
end

--- Something stinks at (x, y): he turns round.
function Runner.serverPanicArea(_server, x, y, radius)
  local r = sv and sv.r
  if r and not r.panic and dist2(r.x, r.y, x, y) <= (radius + Runner.radius) ^ 2 then
    -- Only if it is ahead of him: once he is running away it can't turn him again.
    if math.cos(r.facing) * (x - r.x) + math.sin(r.facing) * (y - r.y) > 0 then
      r.panic = true
    end
  end
end

--- A freeze landed on (x, y): he stands still.
function Runner.serverFreezeArea(_server, x, y, radius, seconds)
  local r = sv and sv.r
  if r and dist2(r.x, r.y, x, y) <= (radius + Runner.radius) ^ 2 then
    r.frozen = math.max(r.frozen, seconds)
  end
end

--- For tests.
function Runner.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { r, lastTick, puffs }
local time = 0

--- The sound of him coming: a cry from the crowd, heard wherever you are.
function Runner.announce(x, y)
  if Features.byName.pedestrians then
    require("src.features.pedestrians.sounds").play("yelp", x, y, 0.8)
  end
end

function Runner.start()
  cl = { r = nil, lastTick = 0, puffs = {}, puffIn = 0 }
end

function Runner.stop()
  cl = nil
end

--- Where he is drawn now, for the minimap.
function Runner.where()
  local r = cl and cl.r
  if r then
    return r.dx, r.dy
  end
  return nil
end

function Runner.update(dt)
  time = time + dt
  if not (cl and cl.r) then
    return
  end
  local r = cl.r
  -- He keeps running between packets: the server's point moves on with him.
  r.x, r.y = r.x + math.cos(r.angle) * r.speed * dt, r.y + math.sin(r.angle) * r.speed * dt
  local ex, ey = r.x - r.dx, r.y - r.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    r.dx, r.dy = r.x, r.y
  else
    local k = math.min(1, dt * SMOOTHING)
    r.dx, r.dy = r.dx + ex * k, r.dy + ey * k
  end
  r.stride = r.stride + dt * (r.speed > 100 and 16 or 5)
  -- Dust behind him at full tilt.
  cl.puffIn = cl.puffIn - dt
  if r.speed > 100 and cl.puffIn <= 0 then
    cl.puffIn = 0.03
    cl.puffs[#cl.puffs + 1] = { x = r.dx, y = r.dy, t = 0 }
  end
  for i = #cl.puffs, 1, -1 do
    local p = cl.puffs[i]
    p.t = p.t + dt
    if p.t > 0.5 then
      table.remove(cl.puffs, i)
    end
  end
end

function Runner.drawBelowCars()
  if not cl then
    return
  end
  for _, p in ipairs(cl.puffs) do
    local k = p.t / 0.5
    love.graphics.setColor(0.8, 0.76, 0.66, (1 - k) * 0.45)
    love.graphics.circle("fill", p.x, p.y, 4 + k * 9, 10)
  end
end

--- Him from above: a yellow tracksuit, arms and legs pumping, a red
--- headband, and streaks behind him at full tilt.
local function drawRunner(r)
  love.graphics.push()
  love.graphics.translate(r.dx, r.dy)
  love.graphics.scale(DRAW_SCALE)
  local x, y = 0, 0
  local fx, fy = math.cos(r.angle), math.sin(r.angle)
  local sx, sy = -fy, fx -- his right
  local swing = math.sin(r.stride) * 7
  if r.speed > 100 then
    love.graphics.setLineWidth(2)
    for i = -1, 1 do
      local ox, oy = x + sx * i * 6, y + sy * i * 6
      love.graphics.setColor(1, 0.9, 0.5, 0.35)
      love.graphics.line(ox - fx * 14, oy - fy * 14, ox - fx * (40 + 10 * (1 - math.abs(i))), oy - fy * 40)
    end
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", x + 3, y + 3, 11, 11)
  -- Legs, one forward while the other goes back.
  love.graphics.setColor(0.15, 0.15, 0.2)
  love.graphics.circle("fill", x + sx * 4 + fx * swing, y + sy * 4 + fy * swing, 3.5, 8)
  love.graphics.circle("fill", x - sx * 4 - fx * swing, y - sy * 4 - fy * swing, 3.5, 8)
  -- Arms, the other way round.
  love.graphics.setColor(0.95, 0.75, 0.1)
  love.graphics.circle("fill", x + sx * 9 - fx * swing * 0.8, y + sy * 9 - fy * swing * 0.8, 3, 8)
  love.graphics.circle("fill", x - sx * 9 + fx * swing * 0.8, y - sy * 9 + fy * swing * 0.8, 3, 8)
  -- The tracksuit, with a stripe down the back.
  love.graphics.setColor(1, 0.82, 0.15)
  love.graphics.ellipse("fill", x, y, 8, 8)
  love.graphics.setColor(0.1, 0.1, 0.12)
  love.graphics.setLineWidth(2)
  love.graphics.line(x - fx * 7, y - fy * 7, x + fx * 2, y + fy * 2)
  love.graphics.setLineWidth(1)
  -- His head and the headband.
  love.graphics.setColor(0.78, 0.56, 0.4)
  love.graphics.circle("fill", x + fx * 2, y + fy * 2, 5, 12)
  love.graphics.setColor(0.9, 0.12, 0.12)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", x + fx * 2, y + fy * 2, 5, 12)
  love.graphics.setLineWidth(1)
  -- A bar over him once he is hurt.
  local frac = math.max(0, r.hp / math.max(1, r.max))
  if frac < 1 then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - 16, y - 22, 32, 6)
    love.graphics.setColor(1 - frac, frac, 0.2)
    love.graphics.rectangle("fill", x - 15, y - 21, 30 * frac, 4)
  end
  love.graphics.pop()
end

function Runner.drawAboveCars()
  if cl and cl.r then
    drawRunner(cl.r)
  end
  love.graphics.setColor(1, 1, 1)
end

--- An arrow at the edge of the screen pointing at him while he is off it.
local function drawPointer(camera, r)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local sx, sy = w / 2 + (r.dx - camera.x) * s, h / 2 + (r.dy - camera.y) * s
  local m = 40
  if sx >= 0 and sx <= w and sy >= 0 and sy <= h then
    return
  end
  local a = math.atan2(sy - h / 2, sx - w / 2)
  local pulse = 0.6 + 0.4 * math.sin(time * 8)
  love.graphics.push()
  love.graphics.translate(math.max(m, math.min(w - m, sx)), math.max(m, math.min(h - m, sy)))
  love.graphics.rotate(a)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.polygon("fill", 16, 0, -8, -11, -8, 11)
  love.graphics.setColor(1, 0.8, 0.1, pulse)
  love.graphics.polygon("fill", 13, 0, -6, -8, -6, 8)
  love.graphics.pop()
end

--- His health and breath along the bottom, and a pointer to him when he is
--- off screen.
function Runner.drawHUD(_client, camera)
  local r = cl and cl.r
  if not r then
    return
  end
  if camera then
    drawPointer(camera, r)
  end
  BossBar.draw({
    title = r.winded and "THE RUNNER  -  winded, get him!" or "THE RUNNER",
    titleColor = { 1, 0.85, 0.3 }, fill = { 0.9, 0.7, 0.1 },
    hp = r.hp, max = r.max, stamina = r.stamina, staminaMax = Runner.breath.max, winded = r.winded,
  })
end

local function splat(x, y, angle, pitch)
  if Features.byName.pedestrians then
    require("src.features.pedestrians.gibs").splat(x, y, angle)
    require("src.features.pedestrians.sounds").play("splat", x, y, pitch)
  end
end

Runner.clientMessages = {
  ERN_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.lastTick then
      return
    end
    cl.lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    local r = cl.r or { dx = x, dy = y, stride = 0 }
    r.x, r.y = x, y
    r.angle = tonumber(args[4]) or r.angle or 0
    r.speed = tonumber(args[5]) or 0
    r.hp = tonumber(args[6]) or r.hp or Runner.health
    r.max = tonumber(args[7]) or r.max or Runner.health
    local stamina, winded = Stamina.read(args, 8)
    r.stamina, r.winded = stamina or r.stamina, winded
    cl.r = r
  end,
  ERN_DOWN = function(_client, args)
    local x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]) or 0
    if not (x and y) then
      return
    end
    for _ = 1, 3 do
      splat(x + (random() - 0.5) * 20, y + (random() - 0.5) * 20, angle + (random() - 0.5) * 2, 0.9)
    end
  end,
}

return Runner
