-- Plasma bolts (docs/borderline.md, "Plasma"): what the plasma haulers
-- fire, purple with Bragium. Big, glowing and slow, so you see one coming
-- and step out of its way. The host flies them; every screen flies its own
-- copy from where and how fast it set off, and drops it when the host says
-- it splashed.
--
-- A bolt splashes on the first player it reaches, the first wall, or at
-- the end of its flight: whoever it hit takes its `damage`, everyone else
-- within `splash` px from that down to a third at the edge, all of it
-- `plasma` (which melts their armor: the damage feature). It never hurts
-- the army. A splash on its own (`serverSplash`: a Bragium tank bursting)
-- hurts whoever is in it the same way.
--
-- Messages
--   server -> all  HYP_BOLT   <id> <x> <y> <vx> <vy> <ttl>   one set off
--   server -> all  HYP_SPLASH <id> <x> <y> <radius>          it (or nothing, id 0) splashed there

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Hauler = require("src.features.borderline.hauler_look")

local Bolts = {}

Bolts.FOOT = 10 -- px; how fat a player on foot is to a bolt (weapons' FOOT_RADIUS)
Bolts.RADIUS = 9 -- px, the bolt itself
Bolts.SPLASH_FOR = 0.45 -- seconds a splash shows

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list, nextId }

function Bolts.serverStart()
  sv = { list = {}, nextId = 1 }
end

function Bolts.serverStop()
  sv = nil
end

--- Everyone within `radius` of (x, y) takes plasma: `damage` at the middle
--- (all of it to `direct`, the one a bolt struck), down to a third at the edge.
function Bolts.serverSplash(server, x, y, radius, damage, direct, id)
  server:broadcast(Protocol.encode("HYP_SPLASH", id or 0, fmt(x), fmt(y), radius))
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverDamage) then
    return
  end
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d = math.max(0, math.sqrt((px - x) ^ 2 + (py - y) ^ 2) - Bolts.FOOT)
      if p == direct or d <= radius then
        local amount = p == direct and damage or damage * (1 - (2 / 3) * d / radius)
        weapons:serverDamage(server, p, nil, math.floor(amount + 0.5), math.atan2(py - y, px - x), "plasma")
      end
    end
  end
end

--- A bolt from (x, y) along `angle`: { speed, ttl, damage, splash }.
function Bolts.serverFire(server, x, y, angle, kind)
  if not sv then
    return
  end
  local b = {
    id = sv.nextId, x = x, y = y, vx = math.cos(angle) * kind.speed, vy = math.sin(angle) * kind.speed, age = 0,
    ttl = kind.ttl, damage = kind.damage * Bosses.enemyPower(), splash = kind.splash,
  }
  sv.nextId = sv.nextId + 1
  sv.list[#sv.list + 1] = b
  server:broadcast(Protocol.encode("HYP_BOLT", b.id, fmt(x), fmt(y), fmt(b.vx), fmt(b.vy), ("%.2f"):format(b.ttl)))
end

--- The player a bolt at (x, y) has run into, if any.
local function struck(server, x, y)
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if (px - x) ^ 2 + (py - y) ^ 2 <= (Bolts.RADIUS + Bolts.FOOT) ^ 2 then
        return p
      end
    end
  end
  return nil
end

function Bolts.serverStep(server, dt)
  for i = #(sv and sv.list or {}), 1, -1 do
    local b = sv.list[i]
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    local who = struck(server, b.x, b.y)
    if who or b.age >= b.ttl or Features.any("blocksShot", b.x, b.y) then
      table.remove(sv.list, i)
      Bolts.serverSplash(server, b.x, b.y, b.splash, b.damage, who, b.id)
    end
  end
end

-- Client --------------------------------------------------------------------

local flying = {} -- id -> { x, y, vx, vy, age, ttl }
local splashes = {} -- { x, y, r, t }
local bank = {}

function Bolts.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- Set off: a deep, wobbling zap.
  bank.fire = make(0.35, 0.6, function(buf)
    buf:sweep(0, 0.3, 700, 180, { wave = "saw", amp = 0.3, decay = 0.15, vibRate = 30, vibDepth = 40 })
    buf:noiseBurst(0, 0.08, { amp = 0.2, decay = 0.03 })
    buf:lowpass(2400)
  end)
  -- Splashed: a hiss and a crackle.
  bank.splash = make(0.4, 0.6, function(buf)
    buf:noiseBurst(0, 0.35, { amp = 0.6, decay = 0.1 })
    buf:sweep(0, 0.2, 300, 120, { wave = "square", amp = 0.2, decay = 0.08 })
    buf:highpass(600)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + love.math.random() * 0.2)
    s:setVolume(0.6 * Audio.volume("weapons"))
    s:play()
  end
end

function Bolts.clear()
  flying, splashes = {}, {}
end

function Bolts.update(dt)
  for id, b in pairs(flying) do
    b.age = b.age + dt
    b.x, b.y = b.x + b.vx * dt, b.y + b.vy * dt
    if b.age > b.ttl + 0.5 then
      flying[id] = nil -- never heard it splash: let it go
    end
  end
  for i = #splashes, 1, -1 do
    splashes[i].t = splashes[i].t + dt
    if splashes[i].t > Bolts.SPLASH_FOR then
      table.remove(splashes, i)
    end
  end
end

--- The bolts with their trails, and the splashes, over everyone.
function Bolts.draw(clock)
  local C = Hauler.C
  love.graphics.setBlendMode("add")
  for _, b in pairs(flying) do
    local speed = math.sqrt(b.vx * b.vx + b.vy * b.vy)
    local ux, uy = b.vx / speed, b.vy / speed
    for k = 4, 1, -1 do -- the trail, fading behind it
      love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.12 * (5 - k))
      love.graphics.circle("fill", b.x - ux * k * 7, b.y - uy * k * 7, Bolts.RADIUS * (1 - k * 0.15), 14)
    end
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.35)
    love.graphics.circle("fill", b.x, b.y, Bolts.RADIUS * 1.8 + math.sin(clock * 30) * 1.5, 18)
  end
  for _, s in ipairs(splashes) do
    local k = s.t / Bolts.SPLASH_FOR
    love.graphics.setColor(C.plasma[1], C.plasma[2], C.plasma[3], 0.5 * (1 - k))
    love.graphics.circle("fill", s.x, s.y, s.r * (0.4 + 0.6 * k), 24)
  end
  love.graphics.setBlendMode("alpha")
  for _, b in pairs(flying) do
    love.graphics.setColor(C.plasma)
    love.graphics.circle("fill", b.x, b.y, Bolts.RADIUS, 16)
    love.graphics.setColor(C.plasmaHot)
    love.graphics.circle("fill", b.x, b.y, Bolts.RADIUS * 0.5, 12)
  end
  for _, s in ipairs(splashes) do
    local k = s.t / Bolts.SPLASH_FOR
    love.graphics.setColor(C.plasmaHot[1], C.plasmaHot[2], C.plasmaHot[3], 1 - k)
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", s.x, s.y, s.r * k, 24)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

Bolts.clientMessages = {
  HYP_BOLT = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    local vx, vy, ttl = tonumber(args[4]), tonumber(args[5]), tonumber(args[6])
    if id and x and y and vx and vy and ttl and (vx ~= 0 or vy ~= 0) then
      flying[id] = { x = x, y = y, vx = vx, vy = vy, age = 0, ttl = ttl }
      play("fire", x, y)
    end
  end,
  HYP_SPLASH = function(_client, args)
    local id, x, y, r = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if id then
      flying[id] = nil
    end
    if x and y and r then
      splashes[#splashes + 1] = { x = x, y = y, r = r, t = 0 }
      play("splash", x, y)
    end
  end,
}

return Bolts
