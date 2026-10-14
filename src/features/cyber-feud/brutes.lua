-- The Static's brutes (docs/cyber-feud.md, "The Static"): big men in
-- rust-orange work jackets and welding masks with a cyan visor slit, a
-- giant chrome arm and a cyan reactor in the chest. Drawn smaller than
-- Kilowatt and nothing like him (no mohawk, no chrome shoulders), so on the
-- Roof the help up the stairs isn't taken for more of him. In Halcyon
-- Tower they come in with the break-in packs from the third floor up
-- (troops.lua's `serverJoin` calls), and on the Roof up the stairs while
-- Kilowatt fights (kilowatt.lua's); the map's `brutes` (beats, as the
-- rippers') puts them anywhere else. troops.lua starts, steps and stops
-- them with the rest of the Static and passes rounds on to them; init.lua
-- passes on the breach and the prompt. Their heads are brute_brain.lua.
--
-- A brute is slow and soaks fire for the pack: 150 health. He braces with
-- a cyan line on the ground showing where he will go, then charges down
-- it (34, `impact`): get off the line. Into a wall, he is dazed for a
-- moment. Up close he punches (24). His arm is a breach target: on foot
-- next to him, hold the action key (F) for `breachTime` and it locks up:
-- he spins, swinging at whatever is next to him for 4 s, his own side as
-- often as not, and you too if you stay (the swings are yours: kills
-- count). Let go and what you had done drains away. In the feud he is the
-- Static's: Halcyon are his `rivals`, and the Static's own rounds pass him.
--
-- Messages
--   server -> all     BRT_STATE <tick> (<id> <x> <y> <facing> <hp> <state> <charge> <alert>)...
--                     (unreliable, 15 Hz; state 0 beat, 1 run, 2 brace, 3 charge, 4 dazed, 5 winding up a
--                     punch, 6 haywire; charge the angle he braced on; alert 1 has somebody)
--   server -> all     BRT_HIT   <id>              he punched, hit somebody charging, or swung (the thump)
--   client -> server  BRT_WORK  <id>              (I am holding the key next to him; every WORK_EVERY)
--   server -> all     BRT_PROG  <id> <progress>   (how far a breach of his arm is: 0..1)
--   server -> all     BRT_DOWN  <id> <x> <y> <angle>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Controls = require("src.controls")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Brain = require("src.features.cyber-feud.brute_brain")

local Brutes = {}

-- Tuning ------------------------------------------------------------------
Brutes.health = 150
Brutes.fov = math.rad(100)
Brutes.aware = 200
Brutes.swingDamage = 30 -- a haywire swing
Brutes.breachTime = 1.5 -- seconds of holding the key next to him
Brutes.drain = 0.5
Brutes.reach = 70 -- px from him that counts as next to him
Brutes.drops = 8
Brutes.firstId = 18001

local WORK_EVERY = 0.2
local WORK_GRACE = 0.45
local SLACK = 40
local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 14
local SNAP = 260
local STALE = 1
local HURT = 0.18
local SCALE = 1.7 -- drawn this much bigger than anyone (Kilowatt, 2.2, stands well over them)
local LINE = Brain.CHARGE_SPEED * Brain.CHARGE_TIME

local CYAN = { 0.18, 0.90, 1.00 }
local GREEN = { 0.43, 1.00, 0.60 }
local CHROME = { 0.78, 0.82, 0.86 }
local STATE_CODE = { beat = 0, run = 1, brace = 2, charge = 3, dazed = 4, wind = 5, haywire = 6 }
local RUST = { 0.62, 0.30, 0.12 } -- his work jacket
local MASK = { 0.16, 0.17, 0.19 }
local LOOK = {
  shirt = RUST, pants = { 0.20, 0.18, 0.16 }, skin = { 0.55, 0.40, 0.31 },
  hair = MASK, shoes = { 0.06, 0.06, 0.07 }, size = 1.7, -- (his body lies as big as he stood)
}

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

local function troops()
  return require("src.features.cyber-feud.troops")
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, work, syncIn, emptySends }
local now = 0

--- The arm on `who`: a player takes it as impact damage; a rival soldier as
--- a blow of the Static's through where he stands (troops.lua decides).
local function hit(server, _s, who, damage, angle)
  if type(who) == "table" then
    troops().serverShotAt(server, who.x, who.y, 2, 0, angle, damage, "impact", "static")
    return
  end
  local weapons = Features.byName.weapons
  local p = server.players[who]
  if p and weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, damage, angle, "impact")
  end
end

--- A haywire swing through (x, y): whoever is there, any side, players
--- too. The blow is the breacher's.
local function swing(server, s, x, y, angle)
  local by = s.breachedBy or 0
  local weapons = Features.byName.weapons
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if dist2(px, py, x, y) <= 30 * 30 and weapons and weapons.serverDamage then
        weapons:serverDamage(server, p, server.players[by], Brutes.swingDamage, angle, "impact")
      end
    end
  end
  if by ~= 0 then
    troops().serverShotAt(server, x, y, 26, by, angle, Brutes.swingDamage, "impact")
  end
end

--- Brutes on `map`'s `brutes` beats (none on the tower or the Roof: they
--- come in with the break-ins, or up the stairs for Kilowatt), finding
--- their way on `nav`, calm while `calm`. Returns the brain, or nil on a
--- map with none of those.
function Brutes.serverStart(server, map, nav, calm)
  Brutes.serverStop(server)
  if not (nav and (map.brutes or map.breakIns or map.bosses)) then
    return nil
  end
  local brain = Brain.new({
    fov = Brutes.fov, aware = Brutes.aware, health = Brutes.health, nav = nav, hit = hit, swing = swing,
    firstId = Brutes.firstId, calm = calm,
  })
  for _, r in ipairs(map.brutes or {}) do
    brain:add(r.route, r.start or 1)
  end
  sv = { brain = brain, work = {}, syncIn = 0, emptySends = 0 }
  return brain
end

--- One more, at (x, y), walking `route` from corner `start` (a break-in).
function Brutes.serverJoin(x, y, route, start)
  if not sv then
    return nil
  end
  local s = sv.brain:add(route, start)
  s.x, s.y = x, y
  return s
end

function Brutes.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Brutes.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("BRT_STATE", server.tick))
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.brain.list
  if #list == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { server.tick }
  for _, s in ipairs(list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = STATE_CODE[s.state] or 0
    parts[#parts + 1] = ("%.2f"):format(s.chargeAngle or s.facing)
    parts[#parts + 1] = s.target and 1 or 0
  end
  local msg = Protocol.encode("BRT_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Brutes.serverStep(server, dt)
  now = now + dt
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for _, s in ipairs(sv.brain.list) do
    if s.hitNow then
      server:broadcast(Protocol.encode("BRT_HIT", s.id))
    end
    if s.state ~= "haywire" then
      s.breachedBy = nil
    end
  end
  for id, w in pairs(sv.work) do
    if now - w.lastWork > WORK_GRACE then
      w.progress = math.max(0, w.progress - Brutes.drain * dt)
    end
    if math.abs(w.progress - w.sent) > 0.04 or (w.progress == 0 and w.sent > 0) then
      w.sent = w.progress
      server:broadcast(Protocol.encode("BRT_PROG", id, ("%.2f"):format(w.progress)))
    end
    if w.progress == 0 then
      sv.work[id] = nil
    end
  end
  sync(server)
end

local function byId(id)
  for _, s in ipairs(sv and sv.brain.list or {}) do
    if s.id == id then
      return s
    end
  end
  return nil
end

Brutes.serverMessages = {
  BRT_WORK = function(server, player, args)
    local s = byId(tonumber(args[1]))
    if not s or s.state == "haywire" or player.vehicle or not Features.present(player)
      or Features.any("serverHeld", server, player) then
      return
    end
    local x, y = Features.bodyPose(server, player)
    if dist2(x, y, s.x, s.y) > (Brutes.reach + SLACK) ^ 2 then
      return
    end
    local w = sv.work[s.id] or { progress = 0, lastWork = -1, sent = 0 }
    sv.work[s.id] = w
    local dt = w.lastWork >= 0 and math.min(now - w.lastWork, WORK_EVERY * 1.5) or WORK_EVERY
    w.lastWork = now
    w.progress = math.min(1, w.progress + dt / Brutes.breachTime)
    if w.progress >= 1 then
      sv.work[s.id] = nil
      sv.brain:breach(s)
      s.breachedBy = player.id
      server:broadcast(Protocol.encode("BRT_PROG", s.id, 0))
    end
  end,
}

local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("BRT_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  sv.work[s.id] = nil
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Brutes.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
end

--- A round through (x, y): the `serverShotAt` convention. A player's, or
--- one carrying another side's name, hits; the Static's own pass by.
--- Returns true when it hit one, and whether a player's round did.
function Brutes.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  if not sv then
    return false
  end
  if by == 0 and (from == nil or from == "static") then
    return false
  end
  local s, i = sv.brain:at(x, y, radius)
  if not s then
    return false
  end
  if sv.brain:hurt(s, i, damage or 20, angle) then
    down(server, s, by ~= 0 and by or nil, angle, dtype)
  end
  return true, by ~= 0
end

function Brutes.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- For tests, and the break-ins' counting.
function Brutes.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, state, charge, alert, stride, hurt, progress }
local lastTick, heardAt, clock = 0, 0, 0
local near = nil
local sendIn = 0
local thump = nil

--- The thump of the arm, synthesised once.
function Brutes.load()
  local buf = Synth.newBuffer(0.35)
  buf:noiseBurst(0, 0.1, { amp = 0.8, decay = 0.05 })
  buf:sweep(0, 0.3, 140, 45, { wave = "sine", amp = 0.9, decay = 0.12 })
  buf:lowpass(1800)
  thump = love.audio.newSource(buf:toSoundData(0.9), "static")
  thump:setAttenuationDistances(260, 2000)
end

local function play(x, y)
  if thump then
    local s = thump:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + random() * 0.2)
    s:setVolume(0.7 * Audio.volume("weapons"))
    s:play()
  end
end

function Brutes.clear()
  shown, lastTick, near = {}, 0, nil
end

function Brutes.update(dt, client)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
      s.stride = s.stride + math.sqrt(ex * ex + ey * ey) * k
    end
    s.hurt = math.max(0, s.hurt - dt)
  end
  near = nil
  local x, y = client:myPose()
  if x and not client:myVehicle() then
    local best = Brutes.reach ^ 2
    for id, s in pairs(shown) do
      local d2 = dist2(x, y, s.dx, s.dy)
      if s.state ~= 6 and d2 <= best then
        near, best = id, d2
      end
    end
  end
  sendIn = sendIn - dt
  if near and Controls.isDown("enter-exit") and sendIn <= 0 then
    sendIn = WORK_EVERY
    client:send(Protocol.encode("BRT_WORK", near))
  end
end

--- The `actionTaken` convention: next to a brute on foot, the action key breaches his arm.
function Brutes.actionTaken()
  return near ~= nil
end

--- His cone, and a bracing brute's line: where his charge will go.
function Brutes.drawBelowCars()
  local cones = not Features.any("hideSightCones")
  for id, s in pairs(shown) do
    if cones and s.state ~= 6 then
      Sight.draw(s.dx, s.dy, s.facing, Brain.RANGE, s.alert, clock, Brutes.fov, { seed = id, color = CYAN })
    end
    if s.state == 2 then
      local ex, ey = Sight.reach(s.dx, s.dy, s.charge, LINE + 20)
      local pulse = 0.5 + 0.5 * math.abs(math.sin(clock * 14))
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.16 + 0.18 * pulse)
      love.graphics.setLineWidth((Brain.HIT_REACH + Brain.RADIUS) * 2)
      love.graphics.line(s.dx, s.dy, ex, ey)
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * pulse)
      love.graphics.setLineWidth(2)
      love.graphics.line(s.dx, s.dy, ex, ey)
      love.graphics.setLineWidth(1)
    end
  end
end

--- One brute: a big body, chrome shoulders, the reactor, and the arm, out
--- on his right: drawn back winding up, straight out charging, sparking
--- green and swinging round once breached.
local function drawBrute(s)
  local angle = s.state == 2 and s.charge or s.facing
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy)
  love.graphics.scale(SCALE)
  local walk = (s.state == 0 or s.state == 1) and math.sin(s.stride * 0.15) * 1.4 or 0
  Body.person(0, 0, angle, walk, LOOK)
  love.graphics.rotate(angle)
  love.graphics.setColor(0.95, 0.75, 0.15) -- hi-vis strips over the jacket's shoulders
  love.graphics.rectangle("fill", -2.5, -7.5, 1.2, 5)
  love.graphics.rectangle("fill", -2.5, 2.5, 1.2, 5)
  love.graphics.setColor(CHROME)
  love.graphics.ellipse("fill", 0, 7.8, 4.2, 3.2, 10) -- the arm's socket
  love.graphics.setColor(MASK) -- the welding mask, its visor a cyan slit
  love.graphics.circle("fill", 0, 0, 3.3, 12)
  love.graphics.setColor(CYAN)
  love.graphics.rectangle("fill", 1.8, -1.8, 1, 3.6)
  local reach = s.state == 5 and -3 or (s.state == 3 and 6 or 2)
  local haywire = s.state == 6
  love.graphics.setColor(haywire and GREEN or CHROME)
  love.graphics.rectangle("fill", -2 + reach * 0.3, 7, 10 + reach, 4.4, 1.6) -- the arm
  love.graphics.setColor(0.30, 0.33, 0.36)
  love.graphics.circle("fill", 8.5 + reach * 1.3, 9.2, 3.1, 10) -- the fist
  if haywire and math.floor(clock * 20) % 2 == 0 then
    love.graphics.setColor(GREEN)
    love.graphics.circle("fill", 4 + random() * 6, 7 + random() * 4, 1, 6)
  end
  local pulse = 0.55 + 0.45 * math.abs(math.sin(clock * 4))
  love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], pulse)
  love.graphics.circle("fill", 2, 0, 2.2, 10) -- the reactor
  if s.state == 4 then -- dazed: stars over his head
    love.graphics.setColor(1, 1, 0.7, 0.8)
    for i = 0, 2 do
      local a = clock * 5 + i * 2.1
      love.graphics.circle("fill", math.cos(a) * 6, math.sin(a) * 6, 1, 6)
    end
  end
  love.graphics.pop()
end

function Brutes.drawAboveCars()
  for _, s in pairs(shown) do
    drawBrute(s)
    local r = Body.SHOULDERS * SCALE
    if s.hurt > 0 then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.5)
      love.graphics.circle("fill", s.dx, s.dy, r, 14)
    end
    if s.alert then
      love.graphics.setFont(UI.fonts.heading)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.printf("!", s.dx - 19, s.dy - r - 30, 40, "center")
      love.graphics.setColor(CYAN)
      love.graphics.printf("!", s.dx - 20, s.dy - r - 31, 40, "center")
    end
    if s.progress and s.progress > 0 then
      UI.ring(s.dx, s.dy - r - 14, 9, s.progress, GREEN, 3)
    end
    if s.hp < Brutes.health then
      local bw, f = 30, math.max(0, s.hp / Brutes.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 3, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 4, bw * f, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Brutes.drawNightLights(glow)
  for _, s in pairs(shown) do
    glow(s.dx, s.dy, s.state == 2 and 80 or 50, s.state == 6 and GREEN or CYAN, 0.6)
  end
end

--- What to do here, over the ability row: hold the key.
function Brutes.drawHUD()
  local s = near and shown[near]
  if not s then
    return
  end
  local key = Controls.name(Controls.bindings("enter-exit")[1])
  local p = s.progress or 0
  local text = p > 0 and ("Breaching his arm... %d%%"):format(math.floor(p * 100))
    or ("Brute.  Hold " .. key .. ": breach his arm (it swings at everyone)")
  local w, h = love.graphics.getDimensions()
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(text, 1, h - 129, w, "center")
  love.graphics.setColor(GREEN)
  love.graphics.printf(text, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

function Brutes.walkers()
  local list = {}
  for id, s in pairs(shown) do
    list[#list + 1] = { key = "brt" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

Brutes.clientMessages = {
  BRT_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        if not s then
          s = { dx = x, dy = y, stride = 0, hurt = 0, hp = Brutes.health }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 3]) or s.facing or 0
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.state = tonumber(args[i + 5]) or 0
        s.charge = tonumber(args[i + 6]) or s.facing
        s.alert = args[i + 7] == "1"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  BRT_HIT = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      play(s.dx, s.dy)
    end
  end,
  BRT_PROG = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.progress = tonumber(args[2]) or 0
    end
  end,
  BRT_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, LOOK)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.8)
      end
    end
  end,
}

return Brutes
