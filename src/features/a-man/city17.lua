-- City 17, the first level of A-Man's quest (the map is city-map's
-- `city17`). Combine soldiers guard every checkpoint on the way up: the
-- station's concourse, the mouth of the avenue on the plaza, the gate in
-- the wall, the far end of each bridge and the Citadel's doors (the map's
-- `posts`). They are the D-Day landing's guards on other uniforms
-- (d-day/troops.lua and d-day/sight.lua): each stands at his post sweeping
-- a narrow cone of sight, turns to follow whoever walks into it and opens
-- fire with a rifle. Cover breaks his sight; two pistol rounds drop him.
-- The first player to reach the Citadel's doors finishes the level
-- (quests' `serverComplete`): a star comes up there.
--
-- The a-man feature (init.lua) passes its hooks on to this module.
--
-- Messages
--   server -> all  C17_TROOPS <tick> [<id> <x> <y> <facing> <hp> <alert>]...   (unreliable, 15 Hz)
--   server -> all  C17_DOWN   <id> <x> <y> <angle>     a soldier went down

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Troops = require("src.features.d-day.troops")
local Sight = require("src.features.d-day.sight")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man" -- the quest this level belongs to (quests' `boss`)
Level.reach = 140 -- px from the Citadel's doors that counts as reaching them
Level.soldierDrops = 3 -- koins a soldier spills

local SYNC_EVERY = 2 -- server ticks between C17_TROOPS
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a step
-- Combine soldiers: dark grey-blue fatigues and armour, gloved hands, a
-- masked head with two lenses that glow.
local LOOK = {
  shirt = { 0.34, 0.40, 0.48 }, pants = { 0.18, 0.21, 0.25 }, skin = { 0.13, 0.14, 0.16 },
  hood = { 0.17, 0.19, 0.22 }, shoes = { 0.06, 0.06, 0.07 }, vest = { 0.45, 0.51, 0.59 }, gun = true,
}
local LENS = { 0.45, 0.85, 1.00 }
local LENS_ALERT = { 1.00, 0.45, 0.20 }

local function fmt(v)
  return ("%.1f"):format(v)
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == "city17" and city.map or nil
end

-- Server --------------------------------------------------------------------

local sv = nil -- { troops, syncIn, reached }

--- Everyone arrived: a soldier on every post.
function Level.serverQuestStarted(_server, quest)
  local map = cityMap()
  if not (quest.boss == Level.questId and map and map.posts) then
    return
  end
  sv = { troops = Troops.new(), syncIn = 0, reached = false }
  for _, p in ipairs(map.posts) do
    sv.troops:add("guard", p.x, p.y, p.watch)
  end
end

--- Over: nothing left to step or draw.
function Level.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("C17_TROOPS", server.tick)) -- an empty list clears every screen
  end
end

--- Every soldier, to everyone, unreliably.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, s in ipairs(sv.troops.list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.alert and 1 or 0
  end
  local msg = Protocol.encode("C17_TROOPS", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Has anyone got to the Citadel's doors? The first one there finishes the
--- level: a star comes up at the doors.
local function checkReached(server)
  local map = cityMap()
  if sv.reached or not map then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      if (x - map.citadelX) ^ 2 + (y - map.citadelY) ^ 2 <= Level.reach ^ 2 then
        sv.reached = true
        local quests = Features.byName.quests
        if quests and quests.serverComplete then
          quests:serverComplete(server, Level.questId, map.citadelX, map.citadelY)
        end
        return
      end
    end
  end
end

function Level.serverStep(server, dt)
  if not sv then
    return
  end
  sv.troops:update(server, dt)
  checkReached(server)
  sync(server)
end

--- One soldier down: gibs on every screen, a few koins, maybe a pickup.
local function soldierDown(server, s, by, angle)
  server:broadcast(Protocol.encode("C17_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Level.soldierDrops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "soldier", x = s.x, y = s.y, by = by, angle = angle })
end

--- A bullet through (x, y): the `serverShotAt` convention. Their own rounds
--- (owned by nobody) pass through their side.
function Level.serverShotAt(server, x, y, radius, by, angle)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.troops:at(x, y, radius)
  if not s then
    return false
  end
  if sv.troops:hurt(s, i, Troops.SHOT_DAMAGE, angle) then
    soldierDown(server, s, by, angle)
  end
  return true
end

function Level.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.troops:freeze(x, y, radius, seconds)
  end
end

function Level.serverPanicArea(x, y, radius)
  if sv then
    sv.troops:scare(x, y, radius, 0.5)
  end
end

--- For tests.
function Level.server()
  return sv
end

-- Client --------------------------------------------------------------------

local troops = {} -- id -> { x, y, dx, dy, angle, hp, alert, bob }
local lastTick = 0
local time = 0

function Level.clear()
  troops, lastTick = {}, 0
end

function Level.update(dt)
  time = time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(troops) do
    local ex, ey = s.x - s.dx, s.y - s.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      s.dx, s.dy = s.x, s.y
    else
      s.dx, s.dy = s.dx + ex * k, s.dy + ey * k
    end
  end
end

--- Their cones of sight, on the ground under everything.
function Level.drawBelowCars()
  for _, s in pairs(troops) do
    Sight.draw(s.dx, s.dy, s.angle, Troops.RANGE, s.alert, time)
  end
end

--- One soldier: the core's person in Combine gear with a rifle, the mask's
--- two lenses glowing (hot when he has somebody), a "!" over him then, and
--- a bar under him once he is hurt.
local function drawSoldier(s)
  local x, y, r = s.dx, s.dy, Body.SHOULDERS
  Body.person(x, y, s.angle, 0, LOOK)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(s.angle)
  local lens = s.alert and LENS_ALERT or LENS
  love.graphics.setColor(lens)
  love.graphics.circle("fill", 3.4, -1.5, 1.1, 6)
  love.graphics.circle("fill", 3.4, 1.5, 1.1, 6)
  love.graphics.pop()
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(1, 0.45, 0.2)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < Troops.HEALTH then
    local bw, f = 20, math.max(0, s.hp / Troops.HEALTH)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

function Level.drawAboveCars()
  for _, s in pairs(troops) do
    drawSoldier(s)
  end
  love.graphics.setColor(1, 1, 1)
end

Level.clientMessages = {
  C17_TROOPS = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick = tick
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = troops[id]
        if not s then
          s = { dx = x, dy = y, bob = love.math.random() * 6 }
          troops[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.hp = tonumber(args[i + 4]) or Troops.HEALTH
        s.alert = args[i + 5] == "1"
        seen[id] = true
      end
    end
    for id in pairs(troops) do
      if not seen[id] then
        troops[id] = nil
      end
    end
  end,
  C17_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if id then
      troops[id] = nil
    end
    if x and y and Features.byName.pedestrians then
      require("src.features.pedestrians.gibs").splat(x, y, angle)
      require("src.features.pedestrians.sounds").play("splat", x, y, 0.9 + love.math.random() * 0.2)
    end
  end,
}

return Level
