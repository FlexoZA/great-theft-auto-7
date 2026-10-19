-- Hyperbole's army on a level (docs/borderline.md, "The army"): the robots
-- on the host, and how they look on every screen. init.lua passes its hooks
-- on to this module.
--
-- The map says who stands where (city-map's `map.army`, borderline.lua):
--   packs   { code, x, y, count }  a pack picking about a spot; `count` for
--           one human and one more for each human past the first
--           (Bosses.plus). Seeing somebody, or hurt, one wakes the lot.
--   posts   { code, x, y, watch }  one standing watch, facing `watch`
--   squads  { codes, route, start }  a squad walking `route` (a loop of
--           { x, y }) from corner `start`, `codes[1]` leading
-- Each model's brain (`BRAINS`, by code) thinks for it; the body they all
-- share is chassis.lua's. One spotting somebody calls those of the army
-- within `Army.CALL` px (and the rest of its pack, wherever they are) to
-- come and look.
--
-- The army is all one side: its rounds carry its name (weapons' `from`),
-- and an ownerless round or blast passes through every one of them. Only
-- players' rounds and blasts reach them.
--
-- Messages
--   server -> all  HYP_STATE <tick> [<id> <code> <x> <y> <facing> <hp> <state> <aim>]...  (unreliable, 15 Hz;
--                  state 0 calm, 1 after somebody, 2 crawling; aim 1 while it is lining up a shot)
--   server -> all  HYP_DOWN  <id> <x> <y> <angle> <code>   one went down
--   server -> all  HYP_ALERT <id>                          one spotted somebody (its beep)
--   server -> all  HYP_CRAWL <id>                          one lost its legs and fights on

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Nav = require("src.features.d-day.nav")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Chassis = require("src.features.borderline.chassis")
local Look = require("src.features.borderline.hauler_look")
local Junk = require("src.features.borderline.junk_brain")
local Gun = require("src.features.borderline.gun_brain")

local Army = {}

-- Tuning ------------------------------------------------------------------
Army.FROM = "hyperbole" -- the name on its rounds
Army.CALL = 520 -- px; the army this near one that spots somebody comes to look
Army.drops = { JNK = 1, GUN = 3 } -- koins each spills
Army.pickupChance = { JNK = 0.2, GUN = 1 } -- the chance it drops anything at all (pickups' own odds after)

local BRAINS = { JNK = Junk, GUN = Gun }

local SYNC_EVERY = 2
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local HURT = 0.18
local MAX_WRECKS = 60

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { roster, syncIn, sentEmpty }

--- Put the army on `map` (its `army`), or nothing on a map without one.
function Army.serverStart(server, map)
  Army.serverStop(server)
  local spec = map and map.army
  if not spec then
    return
  end
  local nav = Nav.build({ x = map.left, y = map.top, w = map.w, h = map.h })
  local roster = Chassis.new({ nav = nav, from = Army.FROM, firstId = 1 })
  for i, pack in ipairs(spec.packs or {}) do
    local brain = BRAINS[pack.code]
    local n = Bosses.plus(pack.count or 3, server)
    for k = 1, n do
      local a, d = k / n * 2 * math.pi, n > 1 and 40 + random() * 30 or 0
      local s = roster:add(brain, pack.code, pack.x + math.cos(a) * d, pack.y + math.sin(a) * d, random() * 2 * math.pi)
      s.pack = i
    end
  end
  for _, post in ipairs(spec.posts or {}) do
    roster:add(BRAINS[post.code], post.code, post.x, post.y, post.watch)
  end
  for _, squad in ipairs(spec.squads or {}) do
    local from = squad.route[squad.start or 1]
    local members = {}
    for _, code in ipairs(squad.codes) do
      members[#members + 1] = roster:add(BRAINS[code], code, from.x, from.y, 0)
    end
    local brain = BRAINS[squad.codes[1]]
    if brain.formSquad then
      brain.formSquad(members, squad.route, squad.start)
    end
  end
  sv = { roster = roster, syncIn = 0, sentEmpty = false }
end

function Army.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("HYP_STATE", server.tick))
  end
end

--- `s` has spotted somebody: it beeps, and the army near it (and its pack)
--- comes to look where it is looking.
local function callOut(server, s)
  server:broadcast(Protocol.encode("HYP_ALERT", s.id))
  local x, y = s.seenX or s.x, s.seenY or s.y
  for _, o in ipairs(sv.roster.list) do
    if o ~= s and o.brain.wake
      and ((s.pack and o.pack == s.pack) or Chassis.dist2(o.x, o.y, s.x, s.y) <= Army.CALL * Army.CALL) then
      o.brain.wake(o, x, y)
    end
  end
end

local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("HYP_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or s.facing), s.code))
  if s.brain.gone then
    s.brain.gone(s)
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Army.drops[s.code] or 1)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy and random() < (Army.pickupChance[s.code] or 0.3) then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, { kind = "robot", x = s.x, y = s.y, by = by, angle = angle, cause = cause })
  -- The rest come to see what happened.
  for _, o in ipairs(sv.roster.list) do
    if o.brain.wake and Chassis.dist2(o.x, o.y, s.x, s.y) <= Army.CALL * Army.CALL then
      o.brain.wake(o, s.x, s.y)
    end
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local list = sv.roster.list
  if #list == 0 and sv.sentEmpty then
    return
  end
  sv.sentEmpty = #list == 0
  local parts = { server.tick }
  for _, s in ipairs(list) do
    parts[#parts + 1] = s.id
    parts[#parts + 1] = s.code
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = s.crawl and 2 or (s.target and 1 or 0)
    parts[#parts + 1] = (s.target and s.aimFor > 0 and s.aimFor < s.conf.aim) and 1 or 0
  end
  local msg = Protocol.encode("HYP_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Army.serverStep(server, dt)
  if not sv then
    return
  end
  for _, s in ipairs(sv.roster:update(server, dt)) do
    down(server, s, s.lastBy, s.facing + math.pi, "bullet") -- a crawl that gave out
  end
  for _, s in ipairs(sv.roster.list) do
    if s.spotted then
      s.spotted = nil
      callOut(server, s)
    end
  end
  sync(server)
end

--- A round through (x, y): the `serverShotAt` convention. Players' rounds
--- and blasts hit; an ownerless one (the army's own) passes through.
function Army.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.roster:at(x, y, radius)
  if not s then
    return false
  end
  local result = sv.roster:hurt(s, i, damage or 20, by, angle)
  if result == "down" then
    down(server, s, by, angle, dtype)
  elseif result == "crawl" then
    server:broadcast(Protocol.encode("HYP_CRAWL", s.id))
  end
  return true
end

--- Every robot out on the level, for the audit (tools/audit).
function Army.serverEnemies(_server, add)
  for _, s in ipairs(sv and sv.roster.list or {}) do
    add({ id = s, kind = "borderline/" .. s.code:lower(), x = s.x, y = s.y, hp = s.hp, radius = s.radius })
  end
end

function Army.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.roster:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Army.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { code, x, y, dx, dy, facing, hp, max, state, aim, stride, hurt, crawl }
local wrecks = {} -- { x, y, angle, code }
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

function Army.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- Spotting somebody: two quick rising beeps.
  bank.beep = make(0.3, 0.5, function(buf)
    buf:tone(0, 0.09, 880, { wave = "square", amp = 0.25, decay = 0.08 })
    buf:tone(0.12, 0.12, 1320, { wave = "square", amp = 0.25, decay = 0.1 })
  end)
  -- Going down: a crunch of metal and a falling whine.
  bank.crash = make(0.7, 0.7, function(buf)
    buf:noiseBurst(0, 0.4, { amp = 0.7, decay = 0.12 })
    buf:sweep(0, 0.6, 600, 90, { wave = "saw", amp = 0.25, decay = 0.4 })
    buf:lowpass(2600)
  end)
  -- Losing its legs: a snap and a grinding scrape.
  bank.snap = make(0.5, 0.6, function(buf)
    buf:noiseBurst(0, 0.08, { amp = 0.8, decay = 0.03 })
    buf:noiseBurst(0.1, 0.35, { amp = 0.3, decay = 0.3 })
    buf:highpass(900)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.9 + random() * 0.2)
    s:setVolume(0.6 * Audio.volume("weapons"))
    s:play()
  end
end

function Army.clear()
  shown, wrecks, lastTick = {}, {}, 0
end

--- Ease the one shown at `s` towards where the host last said it was
--- (`k` of the way this frame), jumping there when it is far off.
local function follow(s, k)
  local gapX, gapY = s.x - s.dx, s.y - s.dy
  local gap = math.sqrt(gapX * gapX + gapY * gapY)
  if gap > SNAP then
    s.dx, s.dy = s.x, s.y
    return
  end
  s.dx, s.dy = s.dx + gapX * k, s.dy + gapY * k
  s.stride = s.stride + gap * k -- the legs step with the ground covered
end

function Army.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {} -- nothing heard for a while: they are gone
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, s in pairs(shown) do
    follow(s, k)
    s.hurt = math.max(0, s.hurt - dt)
    s.charge = s.aim and math.min(1, (s.charge or 0) + dt * 2) or 0
  end
end

function Army.drawBelowCars()
  for _, w in ipairs(wrecks) do
    Look.drawWreck(w, clock)
  end
end

local function healthBar(s)
  if s.hp < s.max then
    local r = Look.radius(s.code)
    local bw, f = 24, math.max(0, s.hp / s.max)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 5, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 6, bw * f, 2)
  end
end

function Army.drawAboveCars()
  for _, s in pairs(shown) do
    Look.draw({ dx = s.dx, dy = s.dy, facing = s.facing, code = s.code, stride = s.stride, charge = s.charge,
      flash = s.hurt / HURT, crawl = s.state == 2 }, clock)
    healthBar(s)
  end
  love.graphics.setColor(1, 1, 1)
end

--- Their clanking feet, for the footsteps feature.
function Army.walkers()
  local list = {}
  for id, s in pairs(shown) do
    if s.state ~= 2 then
      list[#list + 1] = { key = "arm" .. id, x = s.dx, y = s.dy, size = "heavy" }
    end
  end
  return list
end

Army.clientMessages = {
  HYP_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, code, x, y = tonumber(args[i]), args[i + 1], tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y and Look.KITS[code] then
        local s = shown[id]
        local hp = tonumber(args[i + 5]) or 0
        if not s then
          s = { code = code, dx = x, dy = y, stride = 0, hurt = 0, hp = hp, max = hp }
          shown[id] = s
        end
        if hp < s.hp then
          s.hurt = HURT
        end
        s.x, s.y, s.hp = x, y, hp
        s.max = math.max(s.max, hp)
        s.facing = tonumber(args[i + 4]) or s.facing or 0
        s.state = tonumber(args[i + 6]) or 0
        s.aim = args[i + 7] == "1"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  HYP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y and Look.KITS[args[5] or ""] then
      wrecks[#wrecks + 1] = { x = s and s.dx or x, y = s and s.dy or y, angle = angle, code = args[5] }
      if #wrecks > MAX_WRECKS then
        table.remove(wrecks, 1)
      end
      play("crash", x, y)
    end
  end,
  HYP_ALERT = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      play("beep", s.dx, s.dy)
    end
  end,
  HYP_CRAWL = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.state = 2
      play("snap", s.dx, s.dy)
    end
  end,
}

return Army
