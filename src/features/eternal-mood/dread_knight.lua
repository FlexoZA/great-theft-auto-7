-- The Dread Knights (docs/eternal-mood.md, "The demons"): Heck's elite, a
-- head over a person in black plate cracked through with Heck's red, a
-- horned helm, braces on his legs and a long blade grown out of each
-- forearm. Not a boss, but the strongest and the smartest thing in the
-- horde: one to a spot (the map's `horde.knights`), on Earth, in the Foundry
-- and in Heck.
--
-- He stands at his spot until a player comes within its `wake` px, into his
-- sight (SEES, no wall in between) or shoots him; then he comes after you,
-- weaving, and cuts you down up close: a slash, or a lunge from a few steps
-- off. Whatever he lands knocks you back and stuns you, you bleed, and most
-- of the time it's a deep wound. He dodges your rounds and abilities on his
-- breath, backs off when he's winded, and goes for medkits when he's badly
-- hurt. What he does is his brain's (dread_knight_brain.lua), how he looks
-- dread_knight_look.lua's; this module is the knight, the wire and the
-- screens.
--
-- He is Heck's: only players' rounds reach him. His health scales with the
-- humans (bosses/init.lua). Down, he drops koins and a pickup, and raises
-- `serverKill` "demon".
--
-- Messages
--   server -> all  DK_STATE <tick> [<id> <x> <y> <facing> <hp> <max> <move> <aim> <awake> <stamina> <winded>]...
--                  (unreliable, 15 Hz; move 0 none, 1 blade back for a slash, 2 slashing (the follow-through
--                  and the moment after), 3 crouched for a lunge (along `aim`), 4 lunging, 5 dodging (along `aim`))
--   server -> all  DK_SAY  <id> <category> <index>  knight <id> says DreadKnight.lines[category][index]
--   server -> all  DK_HIT  <name> <x> <y>           slash (it landed), miss
--   server -> all  DK_DOWN <id> <x> <y> <angle>     one went down (to a joiner too, for the bodies)

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Ground = require("src.features.eternal-mood.ground")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Onscreen = require("src.features.eternal-mood.onscreen")
local Look = require("src.features.eternal-mood.dread_knight_look")

local DreadKnight = {}
DreadKnight.__index = DreadKnight

local Brain

-- Tuning --------------------------------------------------------------------

DreadKnight.HEALTH = 600 -- for one player (more humans, more: bosses/init.lua); a Cacodaemon has 220
DreadKnight.RADIUS = 13 -- px: his shoulders (dread_knight_look.lua draws him); a person is 9
DreadKnight.WALK = 85 -- px/s
DreadKnight.RUN = 150 -- px/s, from well off; a player's sprint is 170
DreadKnight.STROLL = 50 -- px/s winded
DreadKnight.TURN = 6 -- rad/s
DreadKnight.BREATH = { drain = 12, regen = 16, recovered = 45, breath = 30 }
DreadKnight.SEES = 600 -- px he sees, no wall in between
DreadKnight.HUNTS = 1400 -- px: once awake he goes after the nearest player this near
DreadKnight.WAKE = 480 -- px: a spot's `wake` when it doesn't say
DreadKnight.WEAVE = 3.2 -- rad/s his weave swings at, closing in...
DreadKnight.WEAVE_ARC = 0.6 -- ...this far either side of straight at you
DreadKnight.REGROUP = 220 -- px he backs off to when winded
DreadKnight.SLASH_REACH = 46 -- px: this near he slashes...
DreadKnight.ARC = 1.0 -- ...everyone within this many radians of his front
DreadKnight.SLASH_WINDUP = 0.35 -- seconds his blade is back first (the tell)
DreadKnight.SLASH_EVERY = 1.0 -- seconds at least between slashes
DreadKnight.SLASH_DAMAGE = 26 -- melee: every hit bleeds (damage's 4 s at 3)...
DreadKnight.DEEP_CHANCE = 0.7 -- ...and this often it's a deep wound...
DreadKnight.DEEP_TIME = 6 -- ...this many seconds...
DreadKnight.DEEP_DPS = 6 -- ...at this much a second
DreadKnight.KNOCK = 150 -- px a hit throws you back...
DreadKnight.KNOCK_TIME = 0.3 -- ...over this long
DreadKnight.STUN = 1.2 -- seconds a hit holds you (less what you wear against melee)
DreadKnight.RECOVER = 0.45 -- seconds he stands after a slash, open
DreadKnight.LUNGE_MIN = 90 -- px: he lunges at whoever is this far...
DreadKnight.LUNGE_MAX = 230 -- ...to this far
DreadKnight.LUNGE_WINDUP = 0.4 -- seconds crouched first (the tell, a lane on the floor)
DreadKnight.LUNGE_SPEED = 560 -- px/s...
DreadKnight.LUNGE_TIME = 0.4 -- ...for up to this long
DreadKnight.LUNGE_EVERY = { 2.5, 3.5 } -- seconds between lunges...
DreadKnight.UP_WINDOW = 0.6 -- ...but within this long of whoever he stunned getting up, straight away
DreadKnight.LUNGE_COST = 22 -- breath
DreadKnight.LEAD = 0.35 -- seconds ahead of you a lunge is aimed
DreadKnight.DODGE_WARN = 0.3 -- seconds' warning he needs of a round to get off its line...
DreadKnight.DODGE_SPEED = 460 -- ...throwing himself aside this fast...
DreadKnight.DODGE_TIME = 0.22 -- ...for this long (about 100 px; further from under an ability)
DreadKnight.DODGE_COOL = 1.2 -- seconds at least between dodges
DreadKnight.DODGE_COST = 18 -- breath; winded, he can't...
DreadKnight.DODGE_FLOOR = 30 -- ...nor with less than this in him: what's under it is for his lunges
DreadKnight.SAY_EVERY = { 8, 13 }
DreadKnight.DROPS = 8 -- koins
DreadKnight.SPACE = 60 -- px apart when a spot has more than one

DreadKnight.lines = {
  wake = { "YOU ARE BEHIND SCHEDULE.", "ANOTHER ONE FOR THE CHOPPING BLOCK.", "KNEEL, AND IT IS QUICK." },
  taunt = { "STAND STILL.", "RUN. IT HELPS ME.", "YOUR FORM IS POOR.", "I HAVE TWO OF THESE." },
  gloat = { "BLEED FOR ME.", "STAY DOWN.", "THAT ONE WILL SCAR.", "AGAIN?" },
  down = { "...DREADFUL.", "TELL HECK... I TRIED.", "NOT... THE KNEES..." },
}

local random = love.math.random

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- The knight -----------------------------------------------------------------

function DreadKnight.new(id, x, y, facing, hp, nav, wake)
  return setmetatable({
    id = id, x = x, y = y, facing = facing, aim = facing, hp = hp, max = hp, nav = nav, wake = wake,
    home = { x = x, y = y, facing = facing }, time = 0, move = nil, moveT = 0, slashIn = 0,
    lungeIn = 1 + random(), sayIn = 3, frozen = 0, stuck = 0, side = random() < 0.5 and 1 or -1,
    breath = Stamina.new(DreadKnight.BREATH), running = false, mode = "home", awake = false,
  }, DreadKnight)
end

--- Does he fit at (x, y): no wall, no lava?
function DreadKnight.fits(x, y)
  return Ground.fits(x, y, DreadKnight.RADIUS)
end
local fits = DreadKnight.fits

function DreadKnight:turn(angle, dt, rate)
  local d = Sight.angleDiff(angle, self.facing)
  local step = (rate or DreadKnight.TURN) * dt
  if math.abs(d) <= step then
    self.facing = angle
  else
    self.facing = self.facing + (d > 0 and step or -step)
  end
end

--- Walk along `angle` at `speed`, sliding along walls. Returns false when
--- he got nowhere.
function DreadKnight:walk(angle, speed, dt)
  return Ground.walk(self, angle, speed, dt, DreadKnight.RADIUS)
end

function DreadKnight:pace()
  return self.breath:pace(DreadKnight.RUN, DreadKnight.STROLL)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { list, fallen = { { id, x, y, angle } }, syncIn }

--- The knights at `map`'s spots (its `horde.knights`: { x, y, facing, count,
--- wake }), finding their way on `nav`. Nothing on a map without any.
function DreadKnight.serverStart(server, map, nav)
  DreadKnight.serverStop(server)
  local spots = map.horde and map.horde.knights
  if not (spots and #spots > 0) then
    return
  end
  sv = { list = {}, fallen = {}, syncIn = 0 }
  local id = 0
  for _, spot in ipairs(spots) do
    local n = spot.count or 1
    for i = 1, n do
      local a = i / n * 2 * math.pi
      local d = n > 1 and DreadKnight.SPACE or 0
      local x, y = spot.x + math.cos(a) * d, spot.y + math.sin(a) * d
      if not fits(x, y) then
        x, y = spot.x, spot.y
      end
      id = id + 1
      sv.list[#sv.list + 1] = DreadKnight.new(id, x, y, spot.facing or math.pi / 2,
        Bosses.health(DreadKnight.HEALTH, server), nav, spot.wake or DreadKnight.WAKE)
    end
  end
end

function DreadKnight.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("DK_STATE", server.tick))
  end
end

local function fmt(n)
  return ("%.0f"):format(n)
end

local function say(server, k, category)
  local list = DreadKnight.lines[category]
  if list then
    server:broadcast(Protocol.encode("DK_SAY", k.id, category, random(#list)))
  end
end

local function wake(server, k)
  if not k.awake then
    k.awake = true
    say(server, k, "wake")
  end
end

local MOVE = { windup = 1, slash = 2, crouch = 3, lunge = 4, dodge = 5 }

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = 2
  local parts = { server.tick }
  for _, k in ipairs(sv.list) do
    local stamina, winded = k.breath:wire()
    local aim = k.move == "dodge" and k.dodgeA or k.aim
    for _, v in ipairs({ k.id, fmt(k.x), fmt(k.y), ("%.2f"):format(k.facing), fmt(math.max(0, k.hp)), fmt(k.max),
      MOVE[k.move] or 0, ("%.3f"):format(aim), k.awake and 1 or 0, stamina, winded }) do
      parts[#parts + 1] = v
    end
  end
  local msg = Protocol.encode("DK_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- Is a player near enough (or in plain sight) to wake `k`?
local function stirred(server, k)
  for _, p in pairs(server.players) do
    if not p.bot and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = dist2(x, y, k.x, k.y)
      if d2 <= k.wake * k.wake or (d2 <= DreadKnight.SEES ^ 2 and Sight.clear(k.x, k.y, x, y)) then
        return true
      end
    end
  end
  return false
end

function DreadKnight.serverStep(server, dt)
  if not sv then
    return
  end
  for _, k in ipairs(sv.list) do
    if not k.awake and stirred(server, k) then
      wake(server, k)
    end
    if k.awake then
      for _, e in ipairs(Brain.think(k, server, dt)) do
        if e[1] == "say" then
          say(server, k, e[2])
        elseif e[1] == "hit" then
          server:broadcast(Protocol.encode("DK_HIT", e[2], fmt(e[3]), fmt(e[4])))
        end
      end
    end
  end
  sync(server)
end

--- Down: his last word, his body, koins, a pickup, the kill.
local function down(server, k, i, by, angle)
  table.remove(sv.list, i)
  if random() < 0.6 then
    say(server, k, "down")
  end
  local fell = { k.id, fmt(k.x), fmt(k.y), ("%.3f"):format(angle or k.facing) }
  sv.fallen[#sv.fallen + 1] = fell
  server:broadcast(Protocol.encode("DK_DOWN", unpack(fell)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, k.x, k.y, DreadKnight.DROPS)
  end
  local pickups = Features.byName.pickups
  if pickups and pickups.serverDropEnemy then
    pickups:serverDropEnemy(server, k.x, k.y)
  end
  Features.call("serverKill", server, { kind = "demon", x = k.x, y = k.y, by = by, angle = angle })
end

--- A round through (x, y): the `serverShotAt` convention. Only a player's
--- reaches him (and wakes him). Returns true when it hit.
function DreadKnight.serverShotAt(server, x, y, radius, by, angle, damage)
  if not sv or by == 0 then
    return false
  end
  for i, k in ipairs(sv.list) do
    if dist2(x, y, k.x, k.y) <= (DreadKnight.RADIUS + (radius or 0)) ^ 2 then
      wake(server, k)
      k.hp = k.hp - (damage or 20)
      if k.hp <= 0 then
        down(server, k, i, by, angle)
      end
      return true
    end
  end
  return false
end

--- Every knight still up, for the audit (tools/audit).
function DreadKnight.serverEnemies(_server, add)
  for _, k in ipairs(sv and sv.list or {}) do
    add({ id = k, kind = "eternal-mood/dread-knight", x = k.x, y = k.y, hp = k.hp, radius = DreadKnight.RADIUS })
  end
end

function DreadKnight.serverFreezeArea(x, y, radius, seconds)
  for _, k in ipairs(sv and sv.list or {}) do
    if dist2(x, y, k.x, k.y) <= radius * radius then
      k.frozen = math.max(k.frozen, seconds)
    end
  end
end

function DreadKnight.serverPlayerJoined(server, player)
  if sv and not player.bot then
    for _, fell in ipairs(sv.fallen) do
      server:send(player, Protocol.encode("DK_DOWN", unpack(fell)), true)
    end
  end
end

--- For tests.
function DreadKnight.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, max, move, moveAt, aim, awake, stamina, winded, stride }
local said = {} -- id -> { text, t }
local bodies = {} -- { x, y, angle }
local flashes = {} -- { x, y, t } a blade landing
local lastTick, heardAt, clock = 0, 0, 0
local bank = {}

local FLASH_FOR = 0.25
local RED = { 0.95, 0.15, 0.12 }

function DreadKnight.load()
  local function make(seconds, volume, build)
    return Onscreen.sound(seconds, volume, build, 250, 2200)
  end
  bank.growl = make(0.9, 0.8, function(buf) -- waking: a low growl through a helm
    buf:sweep(0, 0.85, 80, 55, { wave = "saw", amp = 0.5, attack = 0.05, decay = 0.7, vibRate = 11, vibDepth = 6 })
    buf:noiseBurst(0, 0.8, { amp = 0.2, decay = 0.5 })
    buf:drive(2.5)
    buf:lowpass(700)
  end)
  bank.draw = make(0.35, 0.5, function(buf) -- a blade drawn back: a rising scrape
    buf:noiseBurst(0, 0.3, { amp = 0.4, decay = 0.25 })
    buf:sweep(0, 0.3, 900, 2400, { wave = "sine", amp = 0.12, decay = 0.25 })
    buf:highpass(1200)
  end)
  bank.swish = make(0.3, 0.7, function(buf) -- the swing
    buf:noiseBurst(0, 0.22, { amp = 0.7, decay = 0.12 })
    buf:sweep(0, 0.2, 1400, 300, { wave = "sine", amp = 0.15, decay = 0.15 })
    buf:highpass(700)
    buf:lowpass(3200)
  end)
  bank.hit = make(0.45, 0.9, function(buf) -- it landed: a chop and a thud
    buf:kick(0, 0.9)
    buf:noiseBurst(0, 0.18, { amp = 0.9, decay = 0.06 })
    buf:tone(0, 0.3, 2900, { wave = "square", amp = 0.06, decay = 0.2, sustain = 0 })
    buf:lowpass(3500)
  end)
  bank.stomp = make(0.4, 0.7, function(buf) -- off on a lunge: braces firing
    buf:kick(0, 0.8)
    buf:noiseBurst(0, 0.12, { amp = 0.5, decay = 0.05 })
    buf:sweep(0.02, 0.2, 260, 90, { wave = "square", amp = 0.15, decay = 0.15 })
    buf:lowpass(1800)
  end)
  bank.dash = make(0.3, 0.6, function(buf) -- throwing himself aside
    buf:kick(0, 0.5)
    buf:noiseBurst(0, 0.25, { amp = 0.5, decay = 0.12 })
    buf:sweep(0, 0.22, 300, 120, { wave = "sine", amp = 0.25, decay = 0.15 })
    buf:lowpass(1800)
  end)
  bank.fall = make(0.8, 0.9, function(buf) -- down, in his plate
    buf:kick(0, 1)
    buf:noiseBurst(0, 0.5, { amp = 0.6, decay = 0.2 })
    for k = 0, 2 do
      buf:tone(0.05 + k * 0.09, 0.3, 1800 - k * 300, { wave = "square", amp = 0.05, decay = 0.2, sustain = 0 })
    end
    buf:lowpass(3000)
  end)
end

local function play(name, x, y)
  Onscreen.play(bank, name, x, y)
end

function DreadKnight.clear()
  shown, said, bodies, flashes, lastTick = {}, {}, {}, {}, 0
end

function DreadKnight.update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > 1.5 then
    shown = {}
  end
  Onscreen.ease(shown, dt)
  for id, s in pairs(said) do
    s.t = s.t - dt
    if s.t <= 0 then
      said[id] = nil
    end
  end
  for i = #flashes, 1, -1 do
    flashes[i].t = flashes[i].t + dt
    if flashes[i].t > FLASH_FOR then
      table.remove(flashes, i)
    end
  end
end

--- The bodies; and under each knight his tells: his reach while a blade is
--- back, the lane he'll go down while he's crouched.
function DreadKnight.drawBelowCars()
  for _, b in ipairs(bodies) do
    Look.drawBody(b, clock)
  end
  for _, m in pairs(shown) do
    if m.move == 1 then
      local t = math.min(1, (clock - (m.moveAt or clock)) / DreadKnight.SLASH_WINDUP)
      love.graphics.setColor(RED[1], RED[2], RED[3], 0.1 + 0.2 * t)
      love.graphics.arc("fill", m.dx, m.dy, DreadKnight.SLASH_REACH, m.facing - DreadKnight.ARC,
        m.facing + DreadKnight.ARC, 16)
    elseif m.move == 3 then
      local t = math.min(1, (clock - (m.moveAt or clock)) / DreadKnight.LUNGE_WINDUP)
      local ex, ey = Sight.reach(m.dx, m.dy, m.aim, DreadKnight.LUNGE_SPEED * DreadKnight.LUNGE_TIME)
      love.graphics.setColor(RED[1], RED[2], RED[3], 0.12 + 0.28 * t)
      love.graphics.setLineWidth(DreadKnight.RADIUS * 2)
      love.graphics.line(m.dx, m.dy, ex, ey)
      love.graphics.setLineWidth(1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- A thin bar: `f` of it filled in `color`, centred on x at y.
local function bar(x, y, w, f, r, g, b, a)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - w / 2 - 1, y, w + 2, 5)
  love.graphics.setColor(r, g, b, a or 1)
  love.graphics.rectangle("fill", x - w / 2, y + 1, w * math.max(0, math.min(1, f)), 3)
end

local BREATH_MAX = Stamina.defaults.max

function DreadKnight.drawAboveCars()
  for id, m in pairs(shown) do
    Look.draw(m, clock)
    if m.awake then -- health over him; breath under it once he's spent some
      local y = m.dy - DreadKnight.RADIUS - 16
      bar(m.dx, y, 36, m.hp / math.max(1, m.max), RED[1], RED[2], RED[3])
      if m.winded or (m.stamina or BREATH_MAX) < BREATH_MAX then
        if m.winded then
          bar(m.dx, y + 5, 36, (m.stamina or 0) / BREATH_MAX, 1, 0.5, 0.45, 0.6 + 0.4 * math.sin(clock * 8))
        else
          bar(m.dx, y + 5, 36, (m.stamina or 0) / BREATH_MAX, 0.45, 0.75, 1)
        end
      end
    end
    local s = said[id]
    if s then
      require("src.features.eternal-mood.horde").drawBubble(m.dx, m.dy - DreadKnight.RADIUS - 22, s.text)
    end
  end
  for _, f in ipairs(flashes) do -- the blade landing
    local t = f.t / FLASH_FOR
    love.graphics.setColor(1, 0.9, 0.8, 0.8 * (1 - t))
    love.graphics.setLineWidth(3)
    love.graphics.line(f.x - 14 + t * 6, f.y - 10, f.x + 14 - t * 6, f.y + 10)
    love.graphics.setLineWidth(1)
  end
  love.graphics.setColor(1, 1, 1)
end

--- His eyes and the cracks in his plate, in the dark.
function DreadKnight.drawNightLights(glow)
  for _, m in pairs(shown) do
    local hx, hy = m.dx + math.cos(m.facing) * 6, m.dy + math.sin(m.facing) * 6
    glow(hx, hy, 34, RED, m.awake and 0.7 or 0.35)
    glow(m.dx, m.dy, 60, RED, 0.25)
  end
end

DreadKnight.clientMessages = {
  DK_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 10, 11 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        seen[id] = true
        local m = shown[id]
        if not m then
          m = { dx = x, dy = y, stride = 0 }
          shown[id] = m
        end
        m.x, m.y = x, y
        m.facing = tonumber(args[i + 3]) or m.facing or 0
        m.hp, m.max = tonumber(args[i + 4]) or m.hp, tonumber(args[i + 5]) or m.max
        local move = tonumber(args[i + 6]) or 0
        if move ~= m.move then
          m.moveAt = clock
          if move == 1 or move == 3 then
            play("draw", m.dx, m.dy)
          elseif move == 4 then
            play("stomp", m.dx, m.dy)
          elseif move == 5 then
            play("dash", m.dx, m.dy)
          end
        end
        m.move = move
        m.aim = tonumber(args[i + 7]) or m.facing
        local awake = args[i + 8] == "1"
        if awake and m.awake == false then
          play("growl", m.dx, m.dy)
        end
        m.awake = awake
        m.stamina, m.winded = Stamina.read(args, i + 9)
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  DK_SAY = function(_client, args)
    local id, list = tonumber(args[1]), DreadKnight.lines[args[2]]
    local text = list and list[tonumber(args[3]) or 0]
    if id and text then
      said[id] = { text = text, t = 1.5 + #text * 0.05 }
    end
  end,
  DK_HIT = function(_client, args)
    local x, y = tonumber(args[2]), tonumber(args[3])
    if not (x and y) then
      return
    end
    if args[1] == "slash" then
      play("hit", x, y)
      flashes[#flashes + 1] = { x = x, y = y, t = 0 }
    else
      play("swish", x, y)
    end
  end,
  DK_DOWN = function(_client, args)
    local id, x, y, angle = tonumber(args[1]), tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    if x and y then
      bodies[#bodies + 1] = { x = x, y = y, angle = angle }
      play("fall", x, y)
    end
    if id then
      shown[id] = nil
    end
  end,
}

Brain = require("src.features.eternal-mood.dread_knight_brain")

return DreadKnight
