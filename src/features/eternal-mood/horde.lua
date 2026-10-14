-- Heck's horde on a level (docs/eternal-mood.md, "The horde"): one enemy,
-- on the host, and how it looks on every screen. init.lua passes its hooks
-- on to this module.
--
-- The possessed (possessed_brain.lua: staffers, guards, the overtime guy)
-- stand at the map's posts (city-map's `map.horde.posts`) until they see
-- somebody. The imps (imp_brain.lua) wait in the vents (`map.horde.vents`):
-- the first time a player comes within a vent's `wake` px its grille bursts
-- open and its pack crawls out one after another, `count` for one human and
-- one more for each human past the first (Bosses.plus), and hunts. What
-- the imps throw is fireballs.lua's.
--
-- The horde is all one side: its rounds carry its name (weapons' `from`),
-- and an ownerless round passes through every one of them, so nothing of
-- Heck's ever hurts anything else of Heck's. Only players' rounds and
-- blasts reach them. One that spots somebody groans, and the rest of the
-- horde near it comes to look.
--
-- They talk (Story.horde): idle chatter at their posts, a shout on spotting
-- somebody, a last word going down; the imps mostly growl.
--
-- Messages
--   server -> all  HRD_STATE <tick> [<id> <kind> <x> <y> <facing> <hp> <state> <alert>]...  (unreliable,
--                  15 Hz; kind s staffer, g guard, o overtime, i imp; state for the possessed 0 at post,
--                  1 hunting, 2 looking; for an imp 0 hunting, 1 crawling out, 2 winding up a throw)
--   server -> all  HRD_DOWN  <id> <x> <y> <angle> <kind>   one went down
--   server -> all  HRD_SAY   <id> <category> <index>       one says Story.horde[side][category][index]
--   server -> all  HRD_VENT  <index>                       vent `index` of the map's burst open
--   server -> all  HRD_SPIN  <id>                          the overtime guy's chaingun winding up
--   server -> all  HRD_CLAW  <id>                          an imp clawed

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Nav = require("src.features.d-day.nav")
local Corpses = require("src.features.corpses")
local Bosses = require("src.features.bosses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Possessed = require("src.features.eternal-mood.possessed_brain")
local Imps = require("src.features.eternal-mood.imp_brain")
local Fireballs = require("src.features.eternal-mood.fireballs")
local Story = require("src.features.eternal-mood.story")

local Horde = {}

-- Tuning ------------------------------------------------------------------
Horde.FROM = "horde" -- the name on its rounds
Horde.firstPossessed = 1
Horde.firstImp = 20001
Horde.wake = 420 -- px a player comes within to burst a vent open (a vent may say its own)
Horde.crawlEvery = 0.7 -- seconds between imps out of one vent
Horde.drops = { staffer = 2, guard = 3, overtime = 6, imp = 3 } -- koins each spills
Horde.chatEvery = { 14, 32 } -- seconds between one of the possessed's idle remarks
Horde.chatNear = 900 -- px; nobody talks to an empty room
Horde.sayFor = 2.6 -- seconds a remark shows

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local HURT = 0.18

local KIND = { staffer = "s", guard = "g", overtime = "o", imp = "i" }
local RANK = { s = "staffer", g = "guard", o = "overtime" }
local POSSESSED_STATE = { post = 0, hunt = 1, search = 2, back = 2 }
local IMP_STATE = { hunt = 0, emerge = 1, windup = 2 }

local RED = { 1.00, 0.18, 0.10 }
local ORANGE = { 1.00, 0.55, 0.12 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function between(range)
  return range[1] + random() * (range[2] - range[1])
end

-- Server --------------------------------------------------------------------

local sv = nil -- { possessed, imps, vents, syncIn, emptySends, chatIn }

local function say(server, s, side, category)
  local lines = Story.horde[side] and Story.horde[side][category]
  if lines and #lines > 0 then
    server:broadcast(Protocol.encode("HRD_SAY", s.id, category, random(#lines)))
  end
end

--- An imp claws player `who`.
local function claw(server, _imp, who, damage, angle)
  local weapons = Features.byName.weapons
  local p = server.players[who]
  if p and weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, damage, angle, "melee")
  end
end

--- Put the horde on `map` (its `horde`), or nothing on a map without one.
function Horde.serverStart(server, map)
  Horde.serverStop(server)
  local spec = map.horde
  if not spec then
    return
  end
  local T = require("src.features.city-map.layout").TILE
  local nav = Nav.build({ x = map.x0, y = map.y0, w = map.cols * T, h = map.rows * T })
  local possessed
  possessed = Possessed.new({
    nav = nav, firstId = Horde.firstPossessed, from = Horde.FROM,
    -- One groans: the possessed near it come and look where it saw somebody.
    call = function(x, y, tx, ty)
      for _, o in ipairs(possessed.list) do
        if (o.x - x) ^ 2 + (o.y - y) ^ 2 <= Possessed.CALL * Possessed.CALL then
          possessed:alert(o, tx, ty)
        end
      end
    end,
  })
  for _, p in ipairs(spec.posts or {}) do
    possessed:add(p.rank, p.x, p.y, p.watch)
  end
  local imps = Imps.new({ nav = nav, firstId = Horde.firstImp, throw = function(srv, _imp, x, y, angle)
    Fireballs.serverThrow(srv, x, y, angle)
  end, claw = claw })
  local vents = {}
  for i, v in ipairs(spec.vents or {}) do
    vents[i] = { x = v.x, y = v.y, out = v.out or 0, count = v.count or 3, wake = v.wake or Horde.wake,
      open = false, left = 0, crawlIn = 0 }
  end
  Fireballs.serverStart()
  sv = { possessed = possessed, imps = imps, vents = vents, syncIn = 0, emptySends = 0,
    chatIn = between(Horde.chatEvery) }
end

function Horde.serverStop(server)
  Fireballs.serverStop()
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("HRD_STATE", server.tick))
  end
end

--- A newcomer sees the vents already burst.
function Horde.serverPlayerJoined(server, player)
  for i, v in ipairs(sv and sv.vents or {}) do
    if v.open then
      server:send(player, Protocol.encode("HRD_VENT", i), true)
    end
  end
end

--- Burst the vents players have come near, and let their imps out.
local function stepVents(server, dt)
  for i, v in ipairs(sv.vents) do
    if not v.open then
      for _, p in pairs(server.players) do
        if not p.bot and Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          if (x - v.x) ^ 2 + (y - v.y) ^ 2 <= v.wake * v.wake then
            v.open, v.left, v.crawlIn = true, Bosses.plus(v.count, server), 0.3
            server:broadcast(Protocol.encode("HRD_VENT", i))
            break
          end
        end
      end
    elseif v.left > 0 then
      v.crawlIn = v.crawlIn - dt
      if v.crawlIn <= 0 then
        v.left, v.crawlIn = v.left - 1, Horde.crawlEvery
        local imp = sv.imps:add(v.x, v.y, v.out + (random() - 0.5) * 0.8)
        if v.left == 0 or random() < 0.4 then
          say(server, imp, "imp", "alert")
        end
      end
    end
  end
end

--- Now and then one of the possessed at its post says something, if a
--- player is near enough to hear.
local function chatter(server, dt)
  sv.chatIn = sv.chatIn - dt
  if sv.chatIn > 0 then
    return
  end
  sv.chatIn = between(Horde.chatEvery)
  local idle = {}
  for _, s in ipairs(sv.possessed.list) do
    if s.state == "post" then
      for _, p in pairs(server.players) do
        if not p.bot and Features.visible(server, p) then
          local x, y = Features.bodyPose(server, p)
          if (x - s.x) ^ 2 + (y - s.y) ^ 2 <= Horde.chatNear * Horde.chatNear then
            idle[#idle + 1] = s
            break
          end
        end
      end
    end
  end
  if #idle > 0 then
    say(server, idle[random(#idle)], "possessed", "idle")
  end
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local count = #sv.possessed.list + #sv.imps.list
  if count == 0 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local parts = { server.tick }
  local function put(s, kind, state)
    parts[#parts + 1] = s.id
    parts[#parts + 1] = kind
    parts[#parts + 1] = ("%.0f"):format(s.x)
    parts[#parts + 1] = ("%.0f"):format(s.y)
    parts[#parts + 1] = ("%.2f"):format(s.facing)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, s.hp))
    parts[#parts + 1] = state
    parts[#parts + 1] = s.target and 1 or 0
  end
  for _, s in ipairs(sv.possessed.list) do
    put(s, KIND[s.rank], POSSESSED_STATE[s.state] or 0)
  end
  for _, s in ipairs(sv.imps.list) do
    put(s, "i", IMP_STATE[s.state] or 0)
  end
  local msg = Protocol.encode("HRD_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Horde.serverStep(server, dt)
  if not sv then
    return
  end
  stepVents(server, dt)
  sv.possessed:update(server, dt)
  sv.imps:update(server, dt)
  Fireballs.serverStep(server, dt)
  for _, s in ipairs(sv.possessed.list) do
    if s.spotted then
      s.spotted = nil
      if random() < 0.6 then
        say(server, s, "possessed", "alert")
      end
    end
    if s.spinning then
      server:broadcast(Protocol.encode("HRD_SPIN", s.id))
    end
  end
  for _, s in ipairs(sv.imps.list) do
    if s.clawed then
      server:broadcast(Protocol.encode("HRD_CLAW", s.id))
    end
  end
  chatter(server, dt)
  sync(server)
end

local function down(server, s, kind, by, angle, cause)
  server:broadcast(Protocol.encode("HRD_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0), KIND[kind]))
  if random() < 0.35 then
    say(server, s, kind == "imp" and "imp" or "possessed", "down")
  end
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Horde.drops[kind] or 2)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, s.x, s.y)
  end
  Features.call("serverKill", server, {
    kind = kind == "imp" and "demon" or "soldier", x = s.x, y = s.y, by = by, angle = angle, cause = cause,
  })
end

--- A round through (x, y): the `serverShotAt` convention. Players' rounds
--- and blasts hit; an ownerless one (Heck's own) passes through. Returns
--- true when it hit one.
function Horde.serverShotAt(server, x, y, radius, by, angle, damage, dtype)
  if not sv or by == 0 then
    return false
  end
  local s, i = sv.possessed:at(x, y, radius)
  if s then
    if sv.possessed:hurt(s, i, damage or 20, angle) then
      down(server, s, s.rank, by, angle, dtype)
    end
    return true
  end
  s, i = sv.imps:at(x, y, radius)
  if s then
    if sv.imps:hurt(s, i, damage or 20) then
      down(server, s, "imp", by, angle, dtype)
    end
    return true
  end
  return false
end

function Horde.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.possessed:freeze(x, y, radius, seconds)
    sv.imps:freeze(x, y, radius, seconds)
  end
end

--- For tests.
function Horde.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { kind, x, y, dx, dy, facing, hp, state, alert, stride, hurt, spinT }
local said = {} -- id -> { text, t }
local opened = {} -- vent index -> true
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

-- The possessed: torn UAC grey and hazard yellow, grey-green skin; Heck's
-- red eyes and the cracks in their skin are drawn over them.
local SKIN = { 0.52, 0.56, 0.46 }
local LOOK = {
  staffer = { shirt = { 0.46, 0.46, 0.44 }, pants = { 0.36, 0.36, 0.34 }, skin = SKIN, hair = { 0.18, 0.16, 0.14 },
    gun = true, gunLength = 4 },
  guard = { shirt = { 0.30, 0.32, 0.34 }, pants = { 0.24, 0.25, 0.27 }, skin = SKIN, vest = { 0.20, 0.21, 0.23 },
    hat = { 0.34, 0.36, 0.38 }, gun = true, gunLength = 9 },
  overtime = { shirt = { 0.46, 0.40, 0.30 }, pants = { 0.28, 0.26, 0.22 }, skin = SKIN, vest = { 0.95, 0.75, 0.10 },
    hat = { 0.95, 0.75, 0.10 }, brim = true, gun = true, gunLength = 15 },
}
-- What an imp leaves behind (corpses.lua draws people).
local IMP_CORPSE = { shirt = { 0.40, 0.24, 0.14 }, pants = { 0.32, 0.18, 0.10 }, skin = { 0.45, 0.28, 0.16 },
  hair = { 0.20, 0.12, 0.08 }, shoes = { 0.20, 0.12, 0.08 } }
local IMP = { body = { 0.58, 0.36, 0.20 }, dark = { 0.36, 0.20, 0.11 }, spike = { 0.90, 0.84, 0.70 } }
local IMP_SCALE = 1.35 -- drawn bigger than a person: a demon, hunched over

function Horde.load()
  local function make(seconds, volume, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(volume), "static")
    src:setAttenuationDistances(220, 1800)
    return src
  end
  -- A low, wet groan: the possessed spotting somebody.
  bank.groan = make(0.9, 0.7, function(buf)
    buf:tone(0, 0.8, 92, { wave = "saw", amp = 0.4, attack = 0.08, decay = 0.6, sustain = 0.5, vibRate = 5,
      vibDepth = 0.6 })
    buf:tone(0, 0.8, 139, { wave = "saw", amp = 0.2, attack = 0.1, decay = 0.5, vibRate = 4, vibDepth = 0.8 })
    buf:noiseBurst(0, 0.7, { amp = 0.12, decay = 0.4 })
    buf:lowpass(900)
  end)
  -- A screech: an imp out of a vent.
  bank.screech = make(0.5, 0.7, function(buf)
    buf:sweep(0, 0.45, 900, 1500, { wave = "saw", amp = 0.35, decay = 0.25 })
    buf:sweep(0.02, 0.4, 1350, 2100, { wave = "square", amp = 0.15, decay = 0.2 })
    buf:noiseBurst(0, 0.3, { amp = 0.2, decay = 0.1 })
    buf:highpass(500)
  end)
  -- A fireball thrown: a whoosh.
  bank.throw = make(0.45, 0.6, function(buf)
    buf:noiseBurst(0, 0.4, { amp = 0.6, decay = 0.18 })
    buf:sweep(0, 0.35, 220, 120, { wave = "sine", amp = 0.3, decay = 0.15 })
    buf:lowpass(2400)
  end)
  -- And bursting.
  bank.pop = make(0.4, 0.6, function(buf)
    buf:noiseBurst(0, 0.35, { amp = 0.7, decay = 0.09 })
    buf:sweep(0, 0.3, 160, 50, { wave = "sine", amp = 0.5, decay = 0.1 })
    buf:lowpass(1800)
  end)
  -- The chaingun winding up.
  bank.spin = make(0.7, 0.6, function(buf)
    buf:sweep(0, 0.65, 180, 900, { wave = "square", amp = 0.18, decay = 2 })
    buf:sweep(0, 0.65, 90, 450, { wave = "saw", amp = 0.15, decay = 2 })
    buf:lowpass(3000)
  end)
  bank.claw = make(0.2, 0.6, function(buf)
    buf:noiseBurst(0, 0.15, { amp = 0.7, decay = 0.04 })
    buf:highpass(1800)
  end)
  Fireballs.onThrow = function(x, y)
    Horde.play("throw", x, y)
  end
  Fireballs.onPop = function(x, y)
    Horde.play("pop", x, y)
  end
end

function Horde.play(name, x, y, pitch)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch((pitch or 1) * (0.9 + random() * 0.2))
    s:setVolume(0.6 * Audio.volume("weapons"))
    s:play()
  end
end

function Horde.clear()
  shown, said, opened, lastTick = {}, {}, {}, 0
  Fireballs.clear()
end

--- Is vent `i` of the map burst open, on this screen?
function Horde.opened(i)
  return opened[i] == true
end

function Horde.update(dt)
  clock = clock + dt
  Fireballs.update(dt)
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
  for id, b in pairs(said) do
    b.t = b.t + dt
    if b.t > Horde.sayFor then
      said[id] = nil
    end
  end
end

--- The possessed's cones, in Heck's red.
function Horde.drawBelowCars()
  if Features.any("hideSightCones") then
    return
  end
  for id, s in pairs(shown) do
    local rank = RANK[s.kind]
    if rank then
      local conf = Possessed.RANKS[rank]
      Sight.draw(s.dx, s.dy, s.facing, conf.range, s.alert, clock, conf.fov, { seed = id, color = RED })
    end
  end
end

--- Two red eyes in a possessed face, and the cracks glowing in its skin.
local function drawEyes(s)
  local fx, fy = math.cos(s.facing), math.sin(s.facing)
  local px, py = -fy, fx
  love.graphics.setColor(RED)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.circle("fill", s.dx + fx * 3.5 + px * side * 2, s.dy + fy * 3.5 + py * side * 2, 1.1, 6)
  end
end

--- An imp, seen from above: a hunched brown back with a row of bone spikes
--- down it, long arms with claws out in front, orange eyes; holding a
--- fireball up while it winds up a throw.
local function drawImp(s)
  local a = s.facing
  local fx, fy = math.cos(a), math.sin(a)
  local px, py = -fy, fx
  local x, y = s.dx, s.dy
  local swing = math.sin(s.stride * 0.25) * 3
  local emerge = s.state == 1 and 0.75 or 1
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.scale(IMP_SCALE)
  love.graphics.translate(-x, -y)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.ellipse("fill", x + 3, y + 3, 11 * emerge, 10 * emerge, 14)
  -- Arms, reaching forward, swinging.
  love.graphics.setColor(IMP.dark)
  love.graphics.setLineWidth(3.5)
  for _, side in ipairs({ -1, 1 }) do
    local sx, sy = x + px * side * 7, y + py * side * 7
    local reach = 9 + side * swing * 0.6
    local hx, hy = sx + fx * reach + px * side * 2, sy + fy * reach + py * side * 2
    love.graphics.line(sx, sy, hx, hy)
    love.graphics.setColor(IMP.spike)
    love.graphics.circle("fill", hx + fx * 2, hy + fy * 2, 1.4, 6) -- claws
    love.graphics.setColor(IMP.dark)
  end
  love.graphics.setLineWidth(1)
  -- The body, hunched.
  love.graphics.setColor(IMP.body)
  love.graphics.ellipse("fill", x - fx * 1, y - fy * 1, 9 * emerge, 10 * emerge, 16)
  love.graphics.setColor(IMP.dark)
  love.graphics.circle("fill", x + fx * 5, y + fy * 5, 5 * emerge, 12) -- the head, low
  -- Spikes along the shoulders and down the back.
  love.graphics.setColor(IMP.spike)
  for k = -2, 2 do
    local back, off = k * 2.5 + 1, k % 2 == 0 and 2 or -2
    local bx, by = x - fx * back + px * off, y - fy * back + py * off
    love.graphics.polygon("fill", bx - px * 1.2, by - py * 1.2, bx + px * 1.2, by + py * 1.2, bx - fx * 3.5,
      by - fy * 3.5)
  end
  for _, side in ipairs({ -1, 1 }) do -- the shoulder horns
    local bx, by = x + px * side * 6 + fx * 2, y + py * side * 6 + fy * 2
    local tx, ty = bx + px * side * 4 - fx * 2, by + py * side * 4 - fy * 2
    love.graphics.polygon("fill", bx, by, tx, ty, bx - fx * 2, by - fy * 2)
  end
  -- Eyes.
  love.graphics.setColor(ORANGE)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.circle("fill", x + fx * 8 + px * side * 2, y + fy * 8 + py * side * 2, 1.3, 6)
  end
  if s.state == 2 then -- the fireball, held up: the tell
    local pulse = 0.8 + 0.2 * math.sin(clock * 30)
    local hx, hy = x + fx * 12 + px * 6, y + fy * 12 + py * 6
    love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.5)
    love.graphics.circle("fill", hx, hy, 11 * pulse, 14)
    love.graphics.setColor(1, 0.85, 0.4)
    love.graphics.circle("fill", hx, hy, 5 * pulse, 12)
  end
  love.graphics.pop()
end

local function healthBar(s, max, r)
  if s.hp < max then
    local bw, f = 20, math.max(0, s.hp / max)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 4, bw * f, 2)
  end
end

local function bubble(s, text)
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local w = math.min(220, font:getWidth(text) + 14)
  local _, lines = font:getWrap(text, w - 10)
  local h = #lines * font:getHeight() + 8
  local x, y = s.dx - w / 2, s.dy - Body.SHOULDERS - 14 - h
  love.graphics.setColor(0.08, 0.02, 0.02, 0.8)
  love.graphics.rectangle("fill", x, y, w, h, 4)
  love.graphics.setColor(RED[1], RED[2], RED[3], 0.8)
  love.graphics.rectangle("line", x, y, w, h, 4)
  love.graphics.setColor(1, 0.85, 0.8)
  love.graphics.printf(text, x + 5, y + 4, w - 10, "center")
end

function Horde.drawAboveCars()
  for _, s in pairs(shown) do
    local rank = RANK[s.kind]
    if rank then
      local swing = s.state == 0 and 0 or math.sin(s.stride * 0.18) * 1.4 -- a shamble
      Body.person(s.dx, s.dy, s.facing, swing, LOOK[rank])
      drawEyes(s)
      if rank == "overtime" and s.spinT and clock - s.spinT < 1.2 then
        love.graphics.setColor(ORANGE[1], ORANGE[2], ORANGE[3], 0.7) -- the barrels, hot
        love.graphics.circle("fill", s.dx + math.cos(s.facing) * 22, s.dy + math.sin(s.facing) * 22, 3, 8)
      end
      healthBar(s, Possessed.RANKS[rank].health, Body.SHOULDERS)
    else
      drawImp(s)
      healthBar(s, Imps.HEALTH, Imps.RADIUS)
    end
    if s.hurt > 0 then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.6)
      love.graphics.circle("fill", s.dx, s.dy, Body.SHOULDERS + 1, 12)
    end
  end
  Fireballs.draw()
  for id, b in pairs(said) do
    local s = shown[id]
    if s then
      bubble(s, b.text)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Horde.drawNightLights(glow)
  for _, s in pairs(shown) do
    -- Lit from inside, as everything of Heck's is: you see them in the dark
    -- before they see you.
    if s.kind == "i" then
      glow(s.dx, s.dy, s.state == 2 and 110 or 60, ORANGE, s.state == 2 and 1 or 0.7)
    else
      glow(s.dx, s.dy, 52, RED, 0.75)
    end
  end
  Fireballs.drawNightLights(glow)
end

--- The open vents on `map`: a black hole where the grille was, the grille
--- bent back off it. Under everyone.
function Horde.drawVents(map)
  for i, v in ipairs(map and map.horde and map.horde.vents or {}) do
    if opened[i] then
      love.graphics.setColor(0.05, 0.02, 0.02)
      love.graphics.rectangle("fill", v.x - 22, v.y - 16, 44, 32, 4)
      love.graphics.setColor(0.35, 0.10, 0.06, 0.8)
      love.graphics.rectangle("line", v.x - 22, v.y - 16, 44, 32, 4)
      love.graphics.setColor(0.45, 0.32, 0.30)
      love.graphics.push()
      love.graphics.translate(v.x + math.cos(v.out) * 30, v.y + math.sin(v.out) * 30)
      love.graphics.rotate(v.out + 0.6)
      love.graphics.rectangle("fill", -20, -6, 40, 12)
      love.graphics.setColor(0.25, 0.16, 0.15)
      for k = -16, 16, 8 do
        love.graphics.rectangle("fill", k, -5, 3, 10)
      end
      love.graphics.pop()
    end
  end
end

function Horde.walkers()
  local list = {}
  for id, s in pairs(shown) do
    list[#list + 1] = { key = "hrd" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

Horde.clientMessages = {
  HRD_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 7, 8 do
      local id, kind, x, y = tonumber(args[i]), args[i + 1], tonumber(args[i + 2]), tonumber(args[i + 3])
      if id and x and y then
        local s = shown[id]
        if not s then
          local max = RANK[kind] and Possessed.RANKS[RANK[kind]].health or Imps.HEALTH
          s = { kind = kind, dx = x, dy = y, stride = 0, hurt = 0, hp = max }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 4]) or s.facing or 0
        local hp = tonumber(args[i + 5]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.state = tonumber(args[i + 6]) or 0
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
  HRD_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      local rank = RANK[args[5]]
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, rank and LOOK[rank] or IMP_CORPSE)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, rank and 0.9 or 1.2)
      end
    end
  end,
  HRD_SAY = function(_client, args)
    local id = tonumber(args[1])
    local s = id and shown[id]
    if not s then
      return
    end
    local side = s.kind == "i" and "imp" or "possessed"
    local lines = Story.horde[side][args[2]]
    local text = lines and lines[tonumber(args[3]) or 0]
    if text then
      said[id] = { text = text, t = 0 }
    end
    if args[2] == "alert" then
      Horde.play(side == "imp" and "screech" or "groan", s.dx, s.dy)
    end
  end,
  HRD_VENT = function(_client, args)
    local i = tonumber(args[1])
    if i then
      opened[i] = true
    end
  end,
  HRD_SPIN = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      s.spinT = clock
      Horde.play("spin", s.dx, s.dy)
    end
  end,
  HRD_CLAW = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      Horde.play("claw", s.dx, s.dy)
    end
  end,
}
for kind, handler in pairs(Fireballs.clientMessages) do
  Horde.clientMessages[kind] = handler
end

return Horde
