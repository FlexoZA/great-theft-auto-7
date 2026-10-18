-- Halcyon's marksmen (docs/cyber-feud.md, "Halcyon"): up on the Overpass's
-- gantries (the map's `marksmen`), drawn over the cars; in Halcyon Tower
-- on the floor in its far corners, where walls hide you from them (the
-- brain's `indoors`). troops.lua starts,
-- steps and stops them with the rest of Halcyon, and passes rounds on to
-- them; their heads are marksman_brain.lua.
--
-- A marksman's rifle shows where it is going: a thin magenta line from
-- him to where whoever he has will be (he leads a car), following them for
-- a second, then holding still and brighter for a moment before he fires
-- down it (one heavy round, Halcyon's). Swerve while it holds and it misses. Then the
-- bolt, and again. 40 health: a couple of rounds. A player's rounds, or
-- the Static's, reach him; Halcyon's pass him by. In the feud (a flare-up
-- on the Overpass) the Static are his rivals and he is theirs.
--
-- Messages
--   server -> all  MRK_STATE <tick> (<id> <x> <y> <aim> <hp> <state>)...
--                  (unreliable, 15 Hz; state 0 watching, 1 aiming, 2 about to fire, 3 working the bolt)
--   server -> all  MRK_SHOT  <id>                   one fired (the crack, the flash)
--   server -> all  MRK_DOWN  <id> <x> <y> <angle>   one went down, off the gantry

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")
local Bosses = require("src.features.bosses")
local Corpses = require("src.features.corpses")
local Brain = require("src.features.cyber-feud.marksman_brain")
local Sight = require("src.features.d-day.sight")

local Marksmen = {}

-- Tuning ------------------------------------------------------------------
Marksmen.count = 3 -- for one human, one more for each human past the first (Bosses.plus), and more on a job
-- finished before
Marksmen.health = 40
Marksmen.damage = 40 -- one round of the rifle: hits hard
Marksmen.roundSpeed = 1700 -- px/s
Marksmen.drops = 4 -- koins one spills
Marksmen.firstId = 16001

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 14
local STALE = 1
local FLASH = 0.12
local HURT = 0.18
local LINE = Brain.RANGE * 1.1 -- px the sightline is drawn out to
local STATE_CODE = { watch = 0, aim = 1, lock = 2, reload = 3 }

local MAGENTA = { 1.00, 0.24, 0.78 }
local HOT = { 1.00, 0.70, 0.92 }
local LOOK = {
  shirt = { 0.30, 0.31, 0.35 }, pants = { 0.18, 0.19, 0.21 }, vest = { 0.38, 0.39, 0.44 },
  shoes = { 0.06, 0.06, 0.07 }, skin = { 0.78, 0.68, 0.60 }, hat = { 0.12, 0.12, 0.14 }, gun = true, gunLength = 22,
}

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }
local rifle = nil

--- One round of the rifle from `s` along `aim`: fast, straight, heavy.
local function fire(server, s, aim)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverFireFrom) then
    return
  end
  if not rifle then
    local base = Tiers.apply(Guns.ak47, Tiers.DEFAULT)
    rifle = setmetatable({ damage = Marksmen.damage, speed = Marksmen.roundSpeed, ttl = 0.7, spread = 0, streak = 34,
      tint = "ff3ec8" }, { __index = base })
  end
  weapons:serverFireFrom(server, 0, s.x + math.cos(aim) * 24, s.y + math.sin(aim) * 24, aim, rifle, "halcyon")
  server:broadcast(Protocol.encode("MRK_SHOT", s.id))
end

--- Marksmen on `map`'s `marksmen` posts, the first `count` (more with more players).
function Marksmen.serverStart(server, map, calm)
  Marksmen.serverStop(server)
  if not map.marksmen then
    return nil
  end
  local brain = Brain.new({ health = Bosses.enemyHealth(Marksmen.health), fire = fire, firstId = Marksmen.firstId,
    calm = calm, roundSpeed = Marksmen.roundSpeed, indoors = map.kind == "tower" })
  local n = math.min(#map.marksmen, Bosses.plus(Marksmen.count, server))
  for i = 1, n do
    local p = map.marksmen[i]
    brain:add(p.x, p.y, p.watch)
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0 }
  return brain
end

function Marksmen.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Marksmen.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("MRK_STATE", server.tick))
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
    parts[#parts + 1] = ("%.3f"):format(s.aim)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = STATE_CODE[s.state] or 0
  end
  local msg = Protocol.encode("MRK_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Marksmen.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  sync(server)
end

--- A round through (x, y): the `serverShotAt` convention. A player's, or
--- one carrying the Static's name, hits; Halcyon's own pass by. Returns
--- true when it hit one, and whether a player's round did.
function Marksmen.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
  if not sv then
    return false
  end
  if by == 0 and (from == nil or from == "halcyon") then
    return false
  end
  local s, i = sv.brain:at(x, y, radius)
  if not s then
    return false
  end
  if sv.brain:hurt(s, i, damage or 20) then
    server:broadcast(Protocol.encode("MRK_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, s.x, s.y, Marksmen.drops)
    end
    Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by ~= 0 and by or nil,
      angle = angle, cause = dtype })
  end
  return true, by ~= 0
end

--- Every marksman standing, for the audit (tools/audit).
function Marksmen.serverEnemies(_server, add)
  for _, s in ipairs(sv and sv.brain.list or {}) do
    add({ id = s, kind = "cyber-feud/marksman", x = s.x, y = s.y, hp = s.hp, radius = Brain.RADIUS })
  end
end

function Marksmen.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Marksmen.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, aim, dAim, hp, state, flash, hurt }
local lastTick, heardAt, clock = 0, 0, 0

function Marksmen.clear()
  shown, lastTick = {}, 0
end

function Marksmen.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    local d = (s.aim - s.dAim + math.pi) % (2 * math.pi) - math.pi
    s.dAim = s.dAim + d * k
    s.flash = math.max(0, s.flash - dt)
    s.hurt = math.max(0, s.hurt - dt)
  end
end

--- His sightline while he aims: thin and faint while it follows, bright
--- and pulsing once it holds; it stops at the first wall.
local function drawLine(s)
  if s.state ~= 1 and s.state ~= 2 then
    return
  end
  local x0, y0 = s.x + math.cos(s.dAim) * 20, s.y + math.sin(s.dAim) * 20
  local x1, y1 = Sight.reach(s.x, s.y, s.dAim, LINE)
  s.lineLen = math.sqrt((x1 - s.x) ^ 2 + (y1 - s.y) ^ 2)
  if s.state == 2 then
    local pulse = 0.6 + 0.4 * math.abs(math.sin(clock * 24))
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.3 * pulse)
    love.graphics.setLineWidth(5)
    love.graphics.line(x0, y0, x1, y1)
    love.graphics.setColor(HOT[1], HOT[2], HOT[3], 0.95 * pulse)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(x0, y0, x1, y1)
  else
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], 0.45)
    love.graphics.setLineWidth(1)
    love.graphics.line(x0, y0, x1, y1)
  end
  love.graphics.setLineWidth(1)
end

--- Over the cars: they are up on the gantry.
function Marksmen.drawAboveCars()
  for _, s in pairs(shown) do
    drawLine(s)
  end
  for _, s in pairs(shown) do
    Body.person(s.x, s.y, s.dAim, 0, LOOK)
    love.graphics.push()
    love.graphics.translate(s.x, s.y)
    love.graphics.rotate(s.dAim)
    love.graphics.setColor(MAGENTA[1], MAGENTA[2], MAGENTA[3], s.state == 2 and 1 or 0.7)
    love.graphics.setLineWidth(1.4)
    love.graphics.line(3.4, -2, 3.4, 2) -- the visor
    love.graphics.setLineWidth(1)
    if s.flash > 0 then
      love.graphics.setColor(1, 0.9, 0.7, s.flash / FLASH)
      love.graphics.circle("fill", 31, 0, 5, 10)
    end
    love.graphics.pop()
    if s.hurt > 0 then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.6)
      love.graphics.circle("fill", s.x, s.y, Body.SHOULDERS, 12)
    end
    if s.hp < s.top then
      local bw, f, r = 20, math.max(0, s.hp / s.top), Body.SHOULDERS
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.x - bw / 2 - 1, s.y + r + 3, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", s.x - bw / 2, s.y + r + 4, bw * f, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Marksmen.drawNightLights(glow)
  for _, s in pairs(shown) do
    glow(s.x, s.y, 30, MAGENTA, 0.5)
    if s.state == 2 then -- the line, lit along its length
      for d = 1, 5 do
        local r = d * (s.lineLen or LINE) / 6
        glow(s.x + math.cos(s.dAim) * r, s.y + math.sin(s.dAim) * r, 22, MAGENTA, 0.5)
      end
    end
    if s.flash > 0 then
      glow(s.x + math.cos(s.dAim) * 30, s.y + math.sin(s.dAim) * 30, 70, { 1, 0.9, 0.7 }, 0.9)
    end
  end
end

Marksmen.clientMessages = {
  MRK_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        local aim = tonumber(args[i + 3]) or 0
        if not s then
          s = { dAim = aim, flash = 0, hurt = 0, hp = Marksmen.health }
          shown[id] = s
        end
        s.x, s.y, s.aim = x, y, aim
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.top = math.max(s.top or Marksmen.health, hp) -- (tougher on a job finished before)
        s.state = tonumber(args[i + 5]) or 0
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  MRK_SHOT = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.flash = FLASH
    end
  end,
  MRK_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.add(x, y, angle, LOOK) -- off the gantry, onto the road
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.9)
      end
    end
  end,
}

return Marksmen
