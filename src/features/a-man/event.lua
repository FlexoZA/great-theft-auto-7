-- A-Man: a city event (src/features/events). A man in a navy suit, joke-shop
-- glasses and a stuck-on moustache comes into the city somewhere away from
-- everyone and walks towards the nearest player, never hurrying, briefcase
-- in hand. He is a player's size.
--
-- He doesn't need to hurry: he teleports. Every few seconds, if he has the
-- breath for it, he stops, flickers, and a line shows where he is about to
-- go; `windup` later he is there. Within `strikeRange` of his target he
-- goes straight through them and out the far side by `overshoot`; further
-- off he blinks across the map to land `approachGap` from them. Either way
-- everyone on the line is torn through (abilities/teleport.lua's
-- `serverThrough`): players and bots on foot or at the wheel take `damage`,
-- pedestrians and officers go down. Step off the line while it shows.
--
-- He has a short breath (bosses/stamina.lua): a blink costs `blinkCost`,
-- so two in a row leave him walking until it is back. He never runs, so he
-- is never winded. Frozen, he stands still and his wind-up waits; a stink
-- in his face throws him off his aim.
--
-- His other trick is his briefcase. With a player within `hordeRange`
-- and the breath for it (`hordeCost`), he snaps it open and a horde of
-- Aperture Science sentry turrets spills out round him (turrets.lua): they
-- scuttle about at random spraying bursts in random directions, real
-- rounds that hurt whoever they meet, and one round knocks one over. Only
-- one horde at a time; `hordeDelay` after the last one falls he may open
-- the case again. His own blinks and the turrets' rounds don't hurt each
-- other or him.
--
-- What he does is his brain's (brain.lua): stalk, blink, open the
-- briefcase, and badly hurt go for a medkit within `healRange`, by blink
-- when he has the breath (the bosses' standard, bosses/heal.lua).
--
-- Down, the disguise comes off (it is left lying where he fell), he spills
-- koins and drops his teleport as a pickup, its tier rolled from
-- `dropTiers`. While he is loose his theme plays and his portrait sits
-- beside his boss bar.
--
-- The host owns him; clients hear where he is at 15 Hz.
--
-- Messages (the events feature registers them)
--   server -> all  EAM_STATE <tick> <x> <y> <facing> <moving> <hp> <max> <aimX|-> <aimY|-> <stamina> <winded>
--                                                      (unreliable, 15 Hz; aim while he winds up)
--   server -> all  EAM_BLINK <sx> <sy> <ex> <ey>        he teleported from one to the other
--   server -> all  EAM_DOWN  <x> <y>                     he went down
--   server -> all  EAM_HORDE <x> <y>                     the case opened there and the turrets came out
--   server -> all  EAM_TURRETS <tick> (<id> <x> <y> <facing> <firing>)...  (unreliable, 15 Hz)
--   server -> all  EAM_POP   <id> <x> <y> <facing>        a turret fell over

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Audio = require("src.audio")
local Traffic = require("src.features.bots.traffic")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")
local Teleport = require("src.features.abilities.teleport")
local Face = require("src.features.a-man.face")
local Theme = require("src.features.a-man.theme")
local OuterCityTheme = require("src.features.a-man.theme_outercity")
local CoastTheme = require("src.features.a-man.theme_coast")
local RoadTheme = require("src.features.a-man.theme_road")
local CitadelTheme = require("src.features.a-man.theme_citadel")
local Sounds = require("src.features.a-man.sounds")
local Turrets = require("src.features.a-man.turrets")
local Brain = require("src.features.a-man.brain")

local AMan = {
  key = "a-man",
  title = "A-MAN IS IN TOWN",
  subtitle = "Nobody recognises him in that moustache. He teleports straight through people: get off his line.",
  wonTitle = "A-MAN IS DOWN",
  wonSubtitle = "He dropped his teleport. First one there takes it.",
  color = { 0.55, 0.95, 0.65 },
  menu = "A man in a very fake disguise walks the city, teleports straight through anyone in his way "
    .. "and unpacks sentry turrets from his briefcase. Drops teleport.",
}

-- Tuning ------------------------------------------------------------------
AMan.health = 1400 -- 70 pistol rounds, for one player (more humans, more: bosses/init.lua)
AMan.radius = Body.RADIUS -- a player's size
AMan.walkSpeed = 55 -- px/s; a little quicker than a player's walk, far slower than a sprint
AMan.keepAway = 70 -- px; he stops walking this close to his target
AMan.breath = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  max = 100,
  regen = 10,
  regenDelay = 1.5,
  breath = 50, -- held before he blinks
}
AMan.blinkCost = 45 -- breath a blink takes: two in a row, then a rest
AMan.blinkEvery = 3 -- seconds at least between blinks
AMan.blinkJitter = 2 -- and up to this much more
AMan.windup = 0.8 -- seconds the line shows before he goes: the time to get off it
AMan.strikeRange = 600 -- px; a target this close gets a blink straight through them
AMan.overshoot = 220 -- px he comes out past them
AMan.reach = 2600 -- px; a target further than this he walks towards
AMan.approachGap = 240 -- px from a far target he lands
AMan.damage = 60 -- to everyone on his line
AMan.hordeCost = 40 -- breath opening the briefcase takes
AMan.hordeRange = 900 -- px; he only opens it with a player this close
AMan.hordeFirst = 8 -- seconds after he arrives before the first horde
AMan.hordeDelay = 10 -- seconds after the last turret falls before the next horde
AMan.width = Teleport.width -- px either side of the line it tears through
AMan.bulletDamage = 20 -- what a round takes off him when it doesn't say (a blast)
AMan.healRange = 1600 -- px; how far he will go for a medkit (he blinks there)
AMan.spawnNear = 900 -- px; he comes in about this far from the nearest player
AMan.spawnFar = 1800
AMan.drops = 50 -- koins he spills
AMan.drop = "ability-teleport" -- the pickup he leaves, in a tier from `dropTiers`
AMan.dropTiers = { -- chance in a hundred of each tier
  { "common", 50 },
  { "uncommon", 30 },
  { "rare", 17 },
  { "legendary", 3 },
}

local SYNC_EVERY = 2 -- server ticks between EAM_STATE packets
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a blink, not a step
local TEAR_TIME = 0.8 -- seconds a blink's tear hangs
local REMAINS_TIME = 30 -- seconds the disguise lies where he fell
local EMPTY = "-"
local LOOK = {
  shirt = { 0.16, 0.22, 0.38 }, pants = { 0.12, 0.16, 0.28 }, skin = { 0.84, 0.77, 0.66 },
  hair = { 0.25, 0.19, 0.14 }, shoes = { 0.05, 0.05, 0.06 },
}

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

--- A tier from `AMan.dropTiers`, as likely as its weight.
function AMan.rollTier()
  local total = 0
  for _, t in ipairs(AMan.dropTiers) do
    total = total + t[2]
  end
  local roll = random() * total
  for _, t in ipairs(AMan.dropTiers) do
    roll = roll - t[2]
    if roll < 0 then
      return t[1]
    end
  end
  return AMan.dropTiers[1][1]
end

-- Server --------------------------------------------------------------------

local sv = nil -- { a = A-Man, events, syncIn, time, blinking }

function AMan.serverStop()
  sv = nil
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
    local near = AMan.spawnNear
    for i, h in ipairs(people) do
      local d = math.sqrt(dist2(node.x, node.y, h.x, h.y))
      near = i == 1 and d or math.min(near, d)
    end
    local score = -math.max(0, AMan.spawnNear - near) * 2 - math.max(0, near - AMan.spawnFar) + random() * 200
    if not bestScore or score > bestScore then
      best, bestScore = node, score
    end
  end
  return best
end

function AMan.serverBegin(server, events)
  local city = Features.byName["city-map"]
  local g = city and city.map and Traffic.graph(city.map)
  local node = g and spawnNode(g, server)
  if not node then
    return nil
  end
  local hp = Bosses.health(AMan.health, server)
  sv = {
    a = {
      x = node.x, y = node.y, facing = 0, hp = hp, max = hp, frozen = 0, moving = false,
      breath = Stamina.new(AMan.breath),
      cool = AMan.blinkEvery, -- a moment to take in the moustache before the first one
    },
    turrets = Turrets.new(), hordeIn = AMan.hordeFirst,
    events = events, syncIn = 0, time = 0,
  }
  return node.x, node.y
end

--- He goes: everyone on the line is torn through and he is at the other end.
local function blink(server, a)
  local sx, sy, ex, ey = a.x, a.y, a.aimX, a.aimY
  a.aimX, a.aimY = nil, nil
  sv.blinking = true -- his own line doesn't hit him (the events feature passes serverShotAt on to him)
  Teleport.serverThrough(server, sx, sy, ex, ey, AMan.damage, AMan.width, nil, nil)
  if not sv then
    return -- the event ended under him (the last player went down and something called it off)
  end
  sv.blinking = false
  a.x, a.y = ex, ey
  a.breath:spend(AMan.blinkCost)
  a.cool = AMan.blinkEvery + random() * AMan.blinkJitter
  server:broadcast(Protocol.encode("EAM_BLINK", fmt(sx), fmt(sy), fmt(ex), fmt(ey)))
end

--- Where he is, to everyone.
local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local a = sv.a
  local stamina, winded = a.breath:wire()
  local msg = Protocol.encode("EAM_STATE", server.tick, fmt(a.x), fmt(a.y), ("%.2f"):format(a.facing),
    a.moving and 1 or 0, math.max(0, math.floor(a.hp)), a.max, a.aimX and fmt(a.aimX) or EMPTY,
    a.aimY and fmt(a.aimY) or EMPTY, stamina, winded)
  local turrets = Protocol.encode("EAM_TURRETS", server.tick, unpack(Turrets.wire(sv.turrets)))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
      server:send(player, turrets, true)
    end
  end
end

--- He snaps his briefcase open and the turrets spill out round him.
local function horde(server, a)
  a.breath:spend(AMan.hordeCost)
  a.cool = math.max(a.cool, 1.5) -- a moment to admire them before he blinks off
  Turrets.spill(sv.turrets, a.x, a.y, Bosses.count(Turrets.count, server))
  server:broadcast(Protocol.encode("EAM_HORDE", fmt(a.x), fmt(a.y)))
end

function AMan.serverStep(server, dt)
  if not sv then
    return
  end
  sv.time = sv.time + dt
  local a = sv.a
  local canHorde = sv.hordeIn <= 0 and Turrets.standing(sv.turrets) == 0
  local act = Brain.think(AMan, a, server, dt, canHorde, sv.time)
  if act == "blink" then
    blink(server, a)
    if not sv then
      return
    end
  elseif act == "horde" then
    horde(server, a)
  end
  a.breath:step(false, dt) -- he never runs
  if Turrets.standing(sv.turrets) == 0 then
    sv.hordeIn = sv.hordeIn - dt
  else
    sv.hordeIn = math.max(sv.hordeIn, AMan.hordeDelay)
  end
  Turrets.step(sv.turrets, server, dt)
  sync(server)
end

--- He takes `amount`. At zero he goes down: the disguise off, koins, his
--- teleport on the ground, and the event is over.
local function hurt(server, amount, by, angle)
  local a = sv.a
  a.hp = a.hp - amount
  if a.hp > 0 then
    return
  end
  local x, y = a.x, a.y
  Turrets.clear(sv.turrets, server)
  server:broadcast(Protocol.encode("EAM_DOWN", fmt(x), fmt(y)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, x, y, AMan.drops)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDrop then
    -- Beside the koins, not under them, on clear ground.
    local dx, dy = x, y
    for i = 0, 7 do
      local t = math.pi / 2 + i * math.pi / 4
      local ox, oy = x + math.cos(t) * 60, y + math.sin(t) * 60
      if not Features.any("blocksPoint", ox, oy) then
        dx, dy = ox, oy
        break
      end
    end
    pickups:serverDrop(server, AMan.drop .. "@" .. AMan.rollTier(), dx, dy)
  end
  Features.call("serverKill", server, { kind = "boss", x = x, y = y, by = by, angle = angle })
  sv.events:serverFinish(server, x, y)
end

--- A bullet passing through (x, y): the `serverShotAt` convention. A turret
--- in the way goes over; a round owned by nobody (his turrets') or his own
--- blink hurts neither them nor him.
function AMan.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or sv.blinking or by == 0 then
    return false
  end
  if Turrets.hit(sv.turrets, server, x, y, radius) then
    return true
  end
  local a = sv.a
  if dist2(a.x, a.y, x, y) >= (radius + AMan.radius) ^ 2 then
    return false
  end
  hurt(server, damage or AMan.bulletDamage, by ~= 0 and by or nil, angle)
  return true
end

--- Something stinks at (x, y): it throws him off whatever he was aiming at.
function AMan.serverPanicArea(_server, x, y, radius)
  local a = sv and sv.a
  if a and a.aimX and dist2(a.x, a.y, x, y) <= (radius + AMan.radius) ^ 2 then
    a.aimX, a.aimY = nil, nil
    a.cool = AMan.blinkEvery
  end
end

--- A freeze landed on (x, y): he stands still, wind-up and all, and so do
--- the turrets caught in it.
function AMan.serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    Turrets.freeze(sv.turrets, x, y, radius, seconds)
  end
  local a = sv and sv.a
  if a and dist2(a.x, a.y, x, y) <= (radius + AMan.radius) ^ 2 then
    a.frozen = math.max(a.frozen, seconds)
  end
end

--- For tests.
function AMan.server()
  return sv
end

-- Client --------------------------------------------------------------------

local cl = nil -- { a, lastTick, turretTick, tears, turrets }
local remains = nil -- { x, y, t }: the disguise where he fell, outliving the event
local time = 0
local face, music = nil, nil -- `music`: whichever theme is playing (or last played)
local THEMES = { -- by the map they go with
  city17 = Theme, outercity = OuterCityTheme, coast = CoastTheme, road = RoadTheme, citadel = CitadelTheme,
}
local themes = {} -- map -> Source, rendered the first time it is wanted

--- The theme for `map` (City 17's, his own, for any map without one) from the top.
local function startMusic(map)
  local key = THEMES[map] and map or "city17"
  local source = themes[key]
  if not source then
    source = love.audio.newSource(THEMES[key].render(), "static")
    source:setLooping(true)
    source:setRelative(true)
    themes[key] = source
  end
  if music and music ~= source then
    music:stop()
  end
  music = source
  music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  music:seek(0)
  music:play()
end

--- His theme from the top, for his quest too (init.lua): it plays from his
--- intro screen to the end of the quest, the way Karen's does hers. Each of
--- his quest's maps has its own (`map`): City 17's industrial rock (his own,
--- the event's too), the Outer City's chase (theme_outercity.lua), the
--- Coast's (theme_coast.lua), the Winding Road's heavy metal (theme_road.lua)
--- and the Citadel's industrial metal (theme_citadel.lua).
function AMan.playTheme(map)
  startMusic(map)
end

function AMan.stopTheme()
  if music then
    music:stop()
  end
end

--- Keep a playing theme at the music volume (the slider may move).
function AMan.themeVolume()
  if music and music:isPlaying() then
    music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  end
end

--- The sound of him arriving, heard wherever you are.
function AMan.announce(x, y)
  Sounds.play("appear", x, y)
end

function AMan.start()
  cl = { a = nil, lastTick = 0, turretTick = 0, tears = {}, turrets = Turrets.clientNew() }
  face = face or Face.new()
  startMusic()
end

function AMan.stop()
  cl = nil
  if music then
    music:stop()
  end
end

--- Where he is drawn now, for the minimap.
--- Where he walks, for footsteps.
function AMan.footing()
  local x, y = AMan.where()
  return x, y, "person"
end

function AMan.where()
  local a = cl and cl.a
  if a then
    return a.dx, a.dy
  end
  return nil
end

function AMan.update(dt)
  time = time + dt
  if face then
    face:update(dt)
  end
  if music and music:isPlaying() then
    music:setVolume(Audio.muted and 0 or Audio.volume("music"))
  end
  if not cl then
    return
  end
  Turrets.update(cl.turrets, dt)
  for i = #cl.tears, 1, -1 do
    local t = cl.tears[i]
    t.t = t.t + dt
    if t.t > TEAR_TIME then
      table.remove(cl.tears, i)
    end
  end
  local a = cl.a
  if not a then
    return
  end
  local ex, ey = a.x - a.dx, a.y - a.dy
  if ex * ex + ey * ey > SNAP * SNAP then
    a.dx, a.dy = a.x, a.y
  else
    local k = math.min(1, dt * SMOOTHING)
    a.dx, a.dy = a.dx + ex * k, a.dy + ey * k
  end
  if a.moving then
    a.stride = a.stride + dt * 6
  end
end

--- The disguise where he fell: the glasses and the moustache, apart.
local function drawRemains(r)
  local fade = math.min(1, (REMAINS_TIME - r.t) / 3)
  love.graphics.setColor(0.04, 0.04, 0.05, fade)
  love.graphics.setLineWidth(1.2)
  love.graphics.circle("line", r.x - 4, r.y + 2, 2.4, 12)
  love.graphics.circle("line", r.x + 1.5, r.y + 2.6, 2.4, 12)
  love.graphics.line(r.x - 1.6, r.y + 2.2, r.x - 0.9, r.y + 2.4)
  love.graphics.setColor(0.03, 0.03, 0.03, fade)
  love.graphics.ellipse("fill", r.x + 7, r.y - 4, 3.2, 1.2, 10)
  love.graphics.setColor(0.93, 0.9, 0.78, fade) -- the tape still on it
  love.graphics.rectangle("fill", r.x + 8.5, r.y - 5, 1, 2)
  love.graphics.setLineWidth(1)
end

--- The disguise lies where he fell for a while after the event is over;
--- the a-man feature (init.lua) calls these from its own hooks.
function AMan.updateRemains(dt)
  if remains then
    remains.t = remains.t + dt
    if remains.t > REMAINS_TIME then
      remains = nil
    end
  end
end

function AMan.drawRemains()
  if remains then
    drawRemains(remains)
  end
end

function AMan.clearRemains()
  remains = nil
end

function AMan.drawBelowCars()
  if not cl then
    return
  end
  for _, t in ipairs(cl.tears) do
    Teleport.drawTear(t.sx, t.sy, t.ex, t.ey, t.t / TEAR_TIME, AMan.color)
  end
end

--- Where he is about to go: a line that fills in from him to the spot as
--- the wind-up runs out, and a ring on the spot. Get off it.
local function drawAim(a)
  local c = AMan.color
  local pulse = 0.5 + 0.5 * math.sin(time * 20)
  love.graphics.setLineWidth(AMan.width * 2)
  love.graphics.setColor(c[1], c[2], c[3], 0.12 + 0.08 * pulse)
  love.graphics.line(a.dx, a.dy, a.aimX, a.aimY)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.35, 0.3, 0.55 + 0.35 * pulse)
  local len = math.sqrt(dist2(a.dx, a.dy, a.aimX, a.aimY))
  local n = math.floor(len / 18)
  for i = 0, n - 1 do
    local k0, k1 = i / n, (i + 0.5) / n
    love.graphics.line(a.dx + (a.aimX - a.dx) * k0, a.dy + (a.aimY - a.dy) * k0,
      a.dx + (a.aimX - a.dx) * k1, a.dy + (a.aimY - a.dy) * k1)
  end
  love.graphics.circle("line", a.aimX, a.aimY, AMan.radius + 6 + 4 * pulse, 24)
  love.graphics.setLineWidth(1)
end

--- Him from above: the core's person in a navy suit, the briefcase in his
--- right hand, the glasses and the moustache on the front of his head. He
--- flickers while he winds up.
local function drawHim(a)
  local alpha = a.alpha or 1
  if a.aimX then
    alpha = 0.45 + 0.55 * math.abs(math.sin(time * 25))
  end
  local look = { alpha = alpha }
  for k, v in pairs(LOOK) do
    look[k] = v
  end
  local _, _, rx, ry = Body.person(a.dx, a.dy, a.angle, math.sin(a.stride) * 0.8, look)
  -- The briefcase, hanging from his right hand.
  love.graphics.push()
  love.graphics.translate(rx, ry)
  love.graphics.rotate(a.angle)
  love.graphics.setColor(0.07, 0.06, 0.06, alpha)
  love.graphics.rectangle("fill", -4.5, 0.4, 9, 4.2, 0.8)
  love.graphics.setColor(0.45, 0.28, 0.16, alpha)
  love.graphics.rectangle("fill", -4, 0.9, 8, 3.2, 0.6)
  love.graphics.setColor(0.88, 0.72, 0.3, alpha)
  love.graphics.rectangle("fill", -2.5, 0.9, 1, 1)
  love.graphics.rectangle("fill", 1.5, 0.9, 1, 1)
  love.graphics.pop()
  -- The disguise, on the front of his head.
  love.graphics.push()
  love.graphics.translate(a.dx, a.dy)
  love.graphics.rotate(a.angle)
  love.graphics.setColor(0.04, 0.04, 0.05, alpha)
  love.graphics.setLineWidth(0.8)
  love.graphics.circle("line", 3.6, -1.4, 1, 8)
  love.graphics.circle("line", 3.6, 1.4, 1, 8)
  love.graphics.setColor(0.03, 0.03, 0.03, alpha)
  love.graphics.ellipse("fill", 5, 0.3, 0.8, 2.2, 8) -- too big, a little crooked
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  -- A bar over him once he is hurt.
  local frac = math.max(0, a.hp / math.max(1, a.max))
  if frac < 1 then
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", a.dx - 22, a.dy - 28, 44, 6)
    love.graphics.setColor(1 - frac, frac, 0.2)
    love.graphics.rectangle("fill", a.dx - 21, a.dy - 27, 42 * frac, 4)
  end
end

function AMan.drawAboveCars()
  if cl then
    Turrets.draw(cl.turrets, time)
  end
  local a = cl and cl.a
  if a then
    if a.aimX then
      drawAim(a)
    end
    drawHim(a)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Him, drawn as the event draws him, for anyone else who shows him (his
--- quest's levels): `a` is { dx, dy, angle, stride, hp, max, alpha }.
function AMan.drawFigure(a)
  drawHim(a)
end

--- An arrow at the edge of the screen pointing at him while he is off it.
local function drawPointer(camera, a)
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  local sx, sy = w / 2 + (a.dx - camera.x) * s, h / 2 + (a.dy - camera.y) * s
  local m = 40
  if sx >= 0 and sx <= w and sy >= 0 and sy <= h then
    return
  end
  local t = math.atan2(sy - h / 2, sx - w / 2)
  local pulse = 0.6 + 0.4 * math.sin(time * 8)
  local c = AMan.color
  love.graphics.push()
  love.graphics.translate(math.max(m, math.min(w - m, sx)), math.max(m, math.min(h - m, sy)))
  love.graphics.rotate(t)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.polygon("fill", 16, 0, -8, -11, -8, 11)
  love.graphics.setColor(c[1], c[2], c[3], pulse)
  love.graphics.polygon("fill", 13, 0, -6, -8, -6, 8)
  love.graphics.pop()
end

--- His health and breath along the bottom with his portrait beside them,
--- and a pointer to him when he is off screen.
function AMan.drawHUD(_client, camera)
  local a = cl and cl.a
  if not a then
    return
  end
  if camera then
    drawPointer(camera, a)
  end
  BossBar.draw({
    title = "A-MAN", titleColor = { 0.7, 1, 0.75 }, fill = { 0.35, 0.75, 0.45 },
    hp = a.hp, max = a.max, stamina = a.stamina, staminaMax = AMan.breath.max, winded = a.winded,
  })
  if face then
    local w, h = love.graphics.getDimensions()
    local bx = math.floor((w - BossBar.width) / 2)
    face:draw(bx - Face.W / 2 - 10, h - BossBar.bottom - 6, 1)
  end
end

AMan.clientMessages = {
  EAM_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.lastTick then
      return
    end
    cl.lastTick = tick
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    local a = cl.a or { dx = x, dy = y, stride = 0 }
    a.x, a.y = x, y
    a.angle = tonumber(args[4]) or a.angle or 0
    a.moving = args[5] == "1"
    a.hp = tonumber(args[6]) or a.hp or AMan.health
    a.max = tonumber(args[7]) or a.max or AMan.health
    a.aimX, a.aimY = tonumber(args[8]), tonumber(args[9])
    local stamina, winded = Stamina.read(args, 10)
    a.stamina, a.winded = stamina or a.stamina, winded
    cl.a = a
  end,
  EAM_BLINK = function(_client, args)
    local sx, sy, ex, ey = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4])
    if not (cl and sx and sy and ex and ey) then
      return
    end
    cl.tears[#cl.tears + 1] = { sx = sx, sy = sy, ex = ex, ey = ey, t = 0 }
    local a = cl.a
    if a then
      a.x, a.y, a.dx, a.dy, a.aimX, a.aimY = ex, ey, ex, ey, nil, nil -- no easing across a blink
    end
    Sounds.play("vanish", sx, sy)
    Sounds.play("appear", ex, ey, 1.6) -- quicker than his entrance
  end,
  EAM_TURRETS = function(_client, args)
    local tick = tonumber(args[1])
    if not (cl and tick) or tick <= cl.turretTick then
      return
    end
    cl.turretTick = tick
    Turrets.read(cl.turrets, args, 2)
  end,
  EAM_HORDE = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if x and y then
      Sounds.play("clasp", x, y)
      Sounds.play("turret", x, y)
    end
  end,
  EAM_POP = function(_client, args)
    local id, x, y = tonumber(args[1]), tonumber(args[2]), tonumber(args[3])
    if cl and id and x and y then
      Turrets.pop(cl.turrets, id, x, y, tonumber(args[4]) or 0)
      Sounds.play("pop", x, y, 0.9 + love.math.random() * 0.25)
    end
  end,
  EAM_DOWN = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (cl and x and y) then
      return
    end
    remains = { x = x, y = y, t = 0 }
    Sounds.play("rip", x, y)
    Sounds.play("clasp", x, y)
  end,
}

return AMan
