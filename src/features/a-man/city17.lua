-- City 17, the first level of A-Man's quest (the map is city-map's
-- `city17`). Combine soldiers guard every checkpoint on the way up: the
-- station's concourse, the mouth of the avenue on the plaza, the gate in
-- the wall, the far end of each bridge and the Citadel's doors (the map's
-- `posts`). They are the D-Day landing's guards on other uniforms
-- (d-day/troops.lua and d-day/sight.lua): each stands at his post sweeping
-- a narrow cone of sight, turns to follow whoever walks into it and opens
-- fire. Cover breaks his sight. He takes what each round carries, out of
-- 60 (`Level.health`): three pistol rounds, a sniper round. Each carries
-- one of the guns, picked by `Level.loadout`'s weights (every gun in
-- weapons/guns.lua can turn up; one missing from the list is as likely as
-- the pistol), fired in bursts once you are in its reach.
-- They hunt (troops' `hunt`): one who spots somebody closes in on them,
-- and goes to where he saw them last when he loses them, his squad with
-- him; one shot from somewhere he can't see goes that way to look. When a
-- soldier goes down, everyone near enough to hear it goes to see. Each
-- walks back to his post or his beat after.
-- Squads of three walk beats between them (the map's `patrols`): through
-- the old town, round the plaza and the Citadel's square. They talk over
-- the radio (radio.lua): guards at a checkpoint and squads on their beat
-- now and then, a mate answering; whoever spots somebody shouts it, and
-- one near a soldier who goes down calls it in, those going to look say
-- so, and one who found nothing says that on his way back.
-- The first player to reach the Citadel's doors finishes the level
-- (quests' `serverComplete`): a star comes up there.
--
-- The a-man feature (init.lua) passes its hooks on to this module.
--
-- Messages
--   server -> all  C17_TROOPS <tick> [<id> <x> <y> <facing> <hp> <alert> <gun>]...   (unreliable, 15 Hz)
--   server -> all  C17_DOWN   <id> <x> <y> <angle>     a soldier went down
--   server -> all  C17_SAY    <id> <category> <index>  a soldier says radio.lines[category][index]

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Troops = require("src.features.d-day.troops")
local Sight = require("src.features.d-day.sight")
local Radio = require("src.features.a-man.radio")
local Guns = require("src.features.weapons.guns")
local Tiers = require("src.features.tiers")

local Level = {}

-- Tuning ------------------------------------------------------------------
Level.questId = "a-man" -- the quest this level belongs to (quests' `boss`)
Level.reach = 140 -- px from the Citadel's doors that counts as reaching them
Level.soldierDrops = 3 -- koins a soldier spills
Level.squadSize = 3 -- soldiers in a patrol
Level.fov = math.rad(60) -- how wide their cone of sight is (D-Day's guards see 30 degrees)
Level.aware = 170 -- px all round them they notice somebody in, any way they face (not drawn)
Level.health = 60 -- three rounds (D-Day's soldiers take 40, two)
-- What they carry, by gun key: `weight` how likely, `burst` rounds at the
-- gun's own rate then `pause` seconds; `damage` per round instead of the
-- gun's (a soldier's sniper rifle doesn't kill in one). A gun not listed
-- has weight 1, a burst of 4 if it fires fast and 1 if not, a 1.2 s pause.
Level.loadout = {
  ak47 = { weight = 4, burst = 3, pause = 1.1 },
  uzi = { weight = 2, burst = 5, pause = 1.2 },
  shotgun = { weight = 2, burst = 1, pause = 1.3 },
  pistol = { weight = 1, burst = 2, pause = 0.9 },
  flamethrower = { weight = 1, burst = 10, pause = 1.0 },
  rocket = { weight = 0.5, burst = 1, pause = 3.0 },
  sniper = { weight = 0.5, burst = 1, pause = 2.5, damage = 60 },
}
local ROUND_TTL = 1.2 -- seconds a round flies when its gun doesn't say (weapons' default)
Level.chatEvery = { 12, 26 } -- seconds between a checkpoint's or a squad's idle chatter (min, max)
Level.replyAfter = { 1.3, 2.1 } -- seconds before a mate answers
Level.chatGap = 4 -- seconds, map-wide, between one conversation starting and the next
Level.shoutEvery = 6 -- seconds a soldier keeps quiet after shouting that he has someone
Level.downHeard = 700 -- px; a soldier this near one who goes down calls it in, and goes to look

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

local sv = nil -- { troops, syncIn, reached, time, groups, pending }

local random = love.math.random

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

--- A gun for a soldier, picked by the loadout's weights, and how he uses it.
local function pickArms()
  local total = 0
  for _, gun in ipairs(Guns.list) do
    local l = Level.loadout[gun.key]
    total = total + (l and l.weight or 1)
  end
  local roll = random() * total
  local gun = Guns.list[1]
  for _, g in ipairs(Guns.list) do
    local w = Level.loadout[g.key]
    roll = roll - (w and w.weight or 1)
    if roll < 0 then
      gun = g
      break
    end
  end
  local l = Level.loadout[gun.key] or {}
  local tuned = Tiers.apply(gun, Tiers.DEFAULT) -- they carry common ones
  if l.damage then
    tuned = setmetatable({ damage = l.damage }, { __index = tuned })
  end
  return {
    gun = tuned,
    key = gun.key,
    index = gun.index,
    burst = l.burst or (gun.cooldown < 0.15 and 4 or 1),
    pause = l.pause or 1.2,
    reach = gun.speed * (gun.ttl or ROUND_TTL) * 0.85, -- a little short of where its rounds give out
  }
end

--- Everyone arrived: a soldier on every post.
function Level.serverQuestStarted(_server, quest)
  local map = cityMap()
  if not (quest.boss == Level.questId and map and map.posts) then
    return
  end
  local troops = Troops.new({ hunt = true, fov = Level.fov, aware = Level.aware, health = Level.health })
  sv = { troops = troops, syncIn = 0, reached = false, time = 0 }
  sv.groups, sv.pending, sv.quietUntil = {}, {}, 0
  local T = require("src.features.city-map.layout").TILE
  sv.troops:navigate({ x = map.x0, y = map.y0, w = map.cols * T, h = map.rows * T })
  -- Who chats together: the guards at one checkpoint, or one squad.
  local posts = {}
  for _, p in ipairs(map.posts) do
    local g = posts[p.at]
    if not g then
      g = { kind = "post", members = {}, chatIn = between(Level.chatEvery) * random() }
      posts[p.at] = g
      sv.groups[#sv.groups + 1] = g
    end
    g.members[#g.members + 1] = sv.troops:add("guard", p.x, p.y, p.watch)
  end
  for _, route in ipairs(map.patrols or {}) do
    local squad = sv.troops:addSquad(route, Level.squadSize)
    local chatIn = between(Level.chatEvery) * random()
    sv.groups[#sv.groups + 1] = { kind = "patrol", members = squad.members, chatIn = chatIn }
  end
  for _, s in ipairs(sv.troops.list) do
    sv.troops:arm(s, pickArms())
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
    parts[#parts + 1] = s.arms and s.arms.index or 0
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

-- Talk ----------------------------------------------------------------------

--- `s` says a line out of `category`, on every screen.
local function say(server, s, category)
  local lines = Radio.lines[category]
  server:broadcast(Protocol.encode("C17_SAY", s.id, category, random(#lines)))
end

--- `s` says something out of `category` in `after` seconds, if he is still up.
local function later(s, category, after)
  sv.pending[#sv.pending + 1] = { s = s, category = category, t = after }
end

local function alive(s)
  return s.hp > 0
end

--- Somebody in `g` still up other than `s`, at random.
local function mate(g, s)
  local others = {}
  for _, m in ipairs(g.members) do
    if m ~= s and alive(m) then
      others[#others + 1] = m
    end
  end
  return others[1] and others[random(#others)] or nil
end

--- The idle chatter, the shouts and the replies.
local function talk(server, dt)
  sv.time = sv.time + dt
  for _, s in ipairs(sv.troops.list) do
    if s.alert and not s.wasAlert and (s.quietUntil or 0) <= sv.time then
      s.quietUntil = sv.time + Level.shoutEvery
      say(server, s, "alert")
    end
    s.wasAlert = s.alert
    if s.gaveUp then -- looked, found nothing, on his way back
      s.gaveUp = false
      if random() < 0.6 and (s.quietUntil or 0) <= sv.time then
        s.quietUntil = sv.time + Level.shoutEvery
        say(server, s, "lost")
      end
    end
  end
  for _, g in ipairs(sv.groups) do
    g.chatIn = g.chatIn - dt
    if g.chatIn <= 0 and sv.time < sv.quietUntil then
      g.chatIn = 0.5 + random() * 3 -- somebody else is talking: wait a moment, not all at once after
    elseif g.chatIn <= 0 then
      g.chatIn = between(Level.chatEvery)
      local busy = false
      for _, m in ipairs(g.members) do
        busy = busy or (alive(m) and m.alert)
      end
      -- A squad's leader is the first of them; at a checkpoint, anyone.
      local speaker = g.kind == "patrol" and g.members[1] or mate(g, nil)
      if speaker and not busy then
        sv.quietUntil = sv.time + Level.chatGap
        say(server, speaker, g.kind)
        local other = mate(g, speaker)
        if other then
          later(other, "reply", between(Level.replyAfter))
        end
      end
    end
  end
  for i = #sv.pending, 1, -1 do
    local p = sv.pending[i]
    p.t = p.t - dt
    if p.t <= 0 then
      table.remove(sv.pending, i)
      if alive(p.s) then
        say(server, p.s, p.category)
      end
    end
  end
end

--- Everyone near enough to hear `down` go down goes to look; the nearest
--- of them calls it in, the next says he is on his way. If nobody is free
--- to go, the nearest still calls it in.
local function callDown(down)
  local went = sv.troops:alarm(down.x, down.y, Level.downHeard)
  if went[1] then
    later(went[1], "down", 0.5)
    if went[2] then
      later(went[2], "investigate", 1.8)
    end
    return
  end
  local best, bestD2 = nil, Level.downHeard ^ 2
  for _, s in ipairs(sv.troops.list) do
    local d2 = (s.x - down.x) ^ 2 + (s.y - down.y) ^ 2
    if s ~= down and d2 < bestD2 then
      best, bestD2 = s, d2
    end
  end
  if best then
    later(best, "down", 0.5)
  end
end

function Level.serverStep(server, dt)
  if not sv then
    return
  end
  sv.troops:update(server, dt)
  talk(server, dt)
  checkReached(server)
  sync(server)
end

--- One soldier down: gibs on every screen, a few koins, maybe a pickup.
local function soldierDown(server, s, by, angle)
  server:broadcast(Protocol.encode("C17_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  callDown(s)
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
--- (owned by nobody) pass through their side. A round takes off what it
--- carries (the gun's damage, tier and all); a blast, which carries
--- nothing and asks a few times over, 20 a time.
function Level.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.troops:at(x, y, radius)
  if not s then
    return false
  end
  if sv.troops:hurt(s, i, damage or Troops.SHOT_DAMAGE, angle) then
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

local troops = {} -- id -> { x, y, dx, dy, angle, hp, alert, bob, stride, say, sayT, shout }
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
      s.stride = s.stride + math.sqrt(ex * ex + ey * ey) * k -- how far he has walked, for his legs
    end
    if s.say then
      s.sayT = s.sayT - dt
      if s.sayT <= 0 then
        s.say = nil
      end
    end
  end
end

--- Their cones of sight, on the ground under everything.
function Level.drawBelowCars()
  for _, s in pairs(troops) do
    Sight.draw(s.dx, s.dy, s.angle, Troops.RANGE, s.alert, time, Level.fov)
  end
end

--- How each gun shows in his hands: how far the barrel reaches, and a pack
--- on his back for the flamethrower's tank and the launcher's missiles.
local HELD = {
  pistol = { gunLength = 4 },
  uzi = { gunLength = 8 },
  ak47 = { gunLength = 15 },
  shotgun = { gunLength = 14 },
  sniper = { gunLength = 21 },
  rocket = { gunLength = 18, pack = { 0.28, 0.32, 0.24 } },
  flamethrower = { gunLength = 12, pack = { 0.78, 0.36, 0.12 } },
}
local looks = {} -- gun index -> LOOK with that gun in his hands

local function lookFor(index)
  local look = looks[index or 0]
  if not look then
    look = {}
    for k, v in pairs(LOOK) do
      look[k] = v
    end
    local gun = index and Guns.list[index]
    local held = gun and HELD[gun.key] or {}
    look.gunLength, look.pack = held.gunLength or 15, held.pack
    looks[index or 0] = look
  end
  return look
end

--- One soldier: the core's person in Combine gear with whatever gun he
--- carries, the mask's two lenses glowing (hot when he has somebody), a "!"
--- over him then, and a bar under him once he is hurt.
local function drawSoldier(s)
  local x, y, r = s.dx, s.dy, Body.SHOULDERS
  Body.person(x, y, s.angle, math.sin(s.stride * 0.18) * 1.2, lookFor(s.gun))
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
  if s.hp < Level.health then
    local bw, f = 20, math.max(0, s.hp / Level.health)
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
  -- What they say, over all of them.
  for _, s in pairs(troops) do
    if s.say then
      local lift = s.alert and 34 or 8
      Radio.drawBubble(s.dx, s.dy - Body.SHOULDERS - lift, s.say, math.min(1, s.sayT * 2), s.shout)
    end
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
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = troops[id]
        if not s then
          s = { dx = x, dy = y, bob = love.math.random() * 6, stride = 0 }
          troops[id] = s
        end
        s.x, s.y = x, y
        s.angle = tonumber(args[i + 3]) or s.angle or 0
        s.hp = tonumber(args[i + 4]) or Level.health
        s.alert = args[i + 5] == "1"
        s.gun = tonumber(args[i + 6])
        seen[id] = true
      end
    end
    for id in pairs(troops) do
      if not seen[id] then
        troops[id] = nil
      end
    end
  end,
  C17_SAY = function(_client, args)
    local s = troops[tonumber(args[1])]
    local lines = Radio.lines[args[2]]
    local text = lines and lines[tonumber(args[3])]
    if s and text then
      s.say, s.sayT = text, Radio.sayTime(text)
      s.shout = args[2] == "alert" or args[2] == "down"
      Radio.play(text, s.x, s.y, s.shout)
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
