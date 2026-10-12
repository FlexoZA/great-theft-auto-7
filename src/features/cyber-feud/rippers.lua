-- The Static's rippers (docs/cyber-feud.md, "The Static"): blades out of
-- chrome forearms, on the Market's west lanes (the map's `rippers`).
-- troops.lua starts, steps and stops them with the rest of the Static, and
-- passes rounds on to them; their heads are ripper_brain.lua.
--
-- A ripper goes for whoever is most alone, runs in, crouches for half a
-- second with a cyan line on the ground showing where it is going, and
-- lunges a long way down it: step off the line. Up close it slashes. In
-- the feud it is the Static's: Halcyon (officers and enforcers) are its
-- `rivals` and it is theirs, and the Static's own rounds pass it by. Its
-- cuts are `melee`, so an enforcer's shield stops one from in front.
--
-- Messages
--   server -> all  RIP_STATE <tick> (<id> <x> <y> <facing> <hp> <state> <lunge> <alert>)...
--                  (unreliable, 15 Hz; state 0 beat, 1 run, 2 crouch, 3 lunge, 4 recover;
--                  lunge the angle it crouched on; alert 1 has somebody)
--   server -> all  RIP_CUT   <id>                one lunged or slashed (the sound)
--   server -> all  RIP_DOWN  <id> <x> <y> <angle>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Brain = require("src.features.cyber-feud.ripper_brain")

local Rippers = {}

-- Tuning ------------------------------------------------------------------
Rippers.health = 40 -- a ganger has 50
Rippers.fov = math.rad(110)
Rippers.aware = 260 -- px all round it hears somebody in: they are keen
Rippers.drops = 4 -- koins one spills (a ganger 3)
Rippers.firstId = 12001

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 16
local SNAP = 260 -- px; a lunge covers a lot in one sync, so a little more than the others
local STALE = 1
local HURT = 0.18
local TRAIL = 0.25 -- seconds a lunge's afterimages show
local LINE = Brain.LUNGE_SPEED * Brain.LUNGE_TIME -- px the crouch's line shows, as far as the lunge goes

local CYAN = { 0.18, 0.90, 1.00 }
local CHROME = { 0.78, 0.82, 0.86 }
local STATE_CODE = { beat = 0, run = 1, crouch = 2, lunge = 3, recover = 4 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

--- `s` cuts `who`: a player takes it as melee damage; a rival soldier as a
--- round of the Static's through where he stands (troops.lua decides,
--- an enforcer's shield included).
local function hit(server, _s, who, damage, angle)
  if type(who) == "table" then
    require("src.features.cyber-feud.troops").serverShotAt(server, who.x, who.y, 2, 0, angle, damage, "melee",
      "static")
    return
  end
  local weapons = Features.byName.weapons
  local p = server.players[who]
  if p and weapons and weapons.serverDamage then
    weapons:serverDamage(server, p, nil, damage, angle, "melee")
  end
end

--- Put a ripper on each of `map`'s `rippers` beats, finding their way on
--- `nav`, calm while `calm`. Returns the brain (for Halcyon's `rivals`), or
--- nil on a map without them.
function Rippers.serverStart(server, map, nav, calm)
  Rippers.serverStop(server)
  if not (map.rippers and nav) then
    return nil
  end
  local brain = Brain.new({
    fov = Rippers.fov, aware = Rippers.aware, health = Rippers.health, nav = nav, hit = hit,
    firstId = Rippers.firstId, calm = calm,
  })
  for _, r in ipairs(map.rippers) do
    brain:add(r.route, r.start or 1)
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0 }
  return brain
end

function Rippers.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Rippers.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("RIP_STATE", server.tick))
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
    parts[#parts + 1] = ("%.2f"):format(s.lungeAngle or s.facing)
    parts[#parts + 1] = s.target and 1 or 0
  end
  local msg = Protocol.encode("RIP_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Rippers.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for _, s in ipairs(sv.brain.list) do
    if s.lunged or s.cut then
      server:broadcast(Protocol.encode("RIP_CUT", s.id, s.lunged and "l" or "s"))
      s.lunged = nil
    end
  end
  sync(server)
end

local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("RIP_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Rippers.drops)
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
function Rippers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
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

function Rippers.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Rippers.serverPanicArea(x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius)
  end
end

--- For tests.
function Rippers.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, state, lunge, alert, stride, hurt, trail }
local lastTick, heardAt, clock = 0, 0, 0
local bank = {} -- lunge, slash: base Sources

-- Lean, dark, a cyan-tipped crest of cable hair; the blades are drawn over him.
local LOOK = {
  shirt = { 0.12, 0.13, 0.15 }, pants = { 0.09, 0.09, 0.11 }, shoes = { 0.04, 0.04, 0.05 },
  skin = { 0.66, 0.50, 0.40 }, hair = { 0.06, 0.06, 0.08 }, gun = true, gunLength = 0,
}

--- The blades' sounds, synthesised once: a ringing "shing" for a lunge, a swish for a slash.
function Rippers.load()
  local function make(seconds, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(0.8), "static")
    src:setAttenuationDistances(260, 2000)
    return src
  end
  bank.lunge = make(0.4, function(buf)
    buf:noiseBurst(0, 0.12, { amp = 0.5, decay = 0.05 })
    buf:sweep(0, 0.35, 3800, 5200, { wave = "sine", amp = 0.35, decay = 0.12 })
    buf:tone(0.02, 0.3, 6100, { wave = "sine", amp = 0.15, decay = 0.08, sustain = 0 })
    buf:highpass(1400)
  end)
  bank.slash = make(0.18, function(buf)
    buf:noiseBurst(0, 0.15, { amp = 0.7, decay = 0.04 })
    buf:highpass(2200)
    buf:lowpass(7000)
  end)
end

local function play(name, x, y)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.92 + random() * 0.18)
    s:setVolume(0.55 * Audio.volume("weapons"))
    s:play()
  end
end

function Rippers.clear()
  shown, lastTick = {}, 0
end

function Rippers.update(dt)
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
    for i = #s.trail, 1, -1 do
      s.trail[i].t = s.trail[i].t + dt
      if s.trail[i].t > TRAIL then
        table.remove(s.trail, i)
      end
    end
    if s.state == 3 then
      s.trail[#s.trail + 1] = { x = s.dx, y = s.dy, t = 0 }
    end
  end
end

--- Their cones, and a crouching one's line: where its lunge will go.
function Rippers.drawBelowCars()
  local cones = not Features.any("hideSightCones")
  for id, s in pairs(shown) do
    if cones then
      Sight.draw(s.dx, s.dy, s.facing, Brain.RANGE, s.alert, clock, Rippers.fov, { seed = id, color = CYAN })
    end
    if s.state == 2 then
      local ex, ey = Sight.reach(s.dx, s.dy, s.lunge, LINE + 20)
      local pulse = 0.5 + 0.5 * math.abs(math.sin(clock * 18))
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.18 + 0.2 * pulse)
      love.graphics.setLineWidth(Brain.HIT_REACH * 2)
      love.graphics.line(s.dx, s.dy, ex, ey)
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * pulse)
      love.graphics.setLineWidth(1.5)
      love.graphics.line(s.dx, s.dy, ex, ey)
      love.graphics.setLineWidth(1)
    end
  end
end

--- Its two blades, out past the hands; flat back along the arms on its beat.
local function drawBlades(s)
  love.graphics.push()
  love.graphics.translate(s.dx, s.dy)
  love.graphics.rotate(s.state == 2 and s.lunge or s.facing)
  local out = s.state ~= 0 and 1 or 0.35
  love.graphics.setLineWidth(1.6)
  for _, side in ipairs({ -1, 1 }) do
    local hx, hy = 7, side * 2.6
    love.graphics.setColor(CHROME)
    love.graphics.line(hx - 4, hy, hx + 13 * out, hy + side * 2.5 * out)
    if s.state == 2 or s.state == 3 then -- the edge catching the light
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.9)
      love.graphics.circle("fill", hx + 13 * out, hy + side * 2.5 * out, 1.3, 6)
    end
  end
  love.graphics.setColor(CYAN)
  for _, c in ipairs({ { -3.4, -1.6 }, { -4.4, 0 }, { -3.4, 1.6 } }) do -- the crest's tips
    love.graphics.circle("fill", c[1], c[2], 0.8, 6)
  end
  love.graphics.setLineWidth(1)
  love.graphics.pop()
end

function Rippers.drawAboveCars()
  for _, s in pairs(shown) do
    for _, p in ipairs(s.trail) do -- a lunge's afterimages
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.35 * (1 - p.t / TRAIL))
      love.graphics.circle("fill", p.x, p.y, Body.SHOULDERS * 0.9, 12)
    end
    local crouch = s.state == 2 and 0.82 or 1
    love.graphics.push()
    love.graphics.translate(s.dx, s.dy)
    love.graphics.scale(crouch)
    local angle = s.state == 2 and s.lunge or s.facing
    Body.person(0, 0, angle, s.state == 0 and math.sin(s.stride * 0.2) * 1.2 or math.sin(s.stride * 0.3) * 1.6, LOOK)
    love.graphics.pop()
    drawBlades(s)
    if s.hurt > 0 then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.6)
      love.graphics.circle("fill", s.dx, s.dy, Body.SHOULDERS, 12)
    end
    local r = Body.SHOULDERS
    if s.alert then
      love.graphics.setFont(require("src.ui").fonts.heading)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.printf("!", s.dx - 19, s.dy - r - 30, 40, "center")
      love.graphics.setColor(CYAN)
      love.graphics.printf("!", s.dx - 20, s.dy - r - 31, 40, "center")
    end
    if s.hp < Rippers.health then
      local bw, f = 20, math.max(0, s.hp / Rippers.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 3, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 4, bw * f, 2)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

function Rippers.drawNightLights(glow)
  for _, s in pairs(shown) do
    local hot = s.state == 2 or s.state == 3
    glow(s.dx, s.dy, hot and 60 or 36, CYAN, hot and 0.8 or 0.35)
  end
end

function Rippers.walkers()
  local list = {}
  for id, s in pairs(shown) do
    list[#list + 1] = { key = "rip" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

Rippers.clientMessages = {
  RIP_STATE = function(_client, args)
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
          s = { dx = x, dy = y, stride = 0, hurt = 0, hp = Rippers.health, trail = {} }
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
        s.lunge = tonumber(args[i + 6]) or s.facing
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
  RIP_CUT = function(_client, args)
    local s = shown[tonumber(args[1]) or -1]
    if s then
      play(args[2] == "l" and "lunge" or "slash", s.dx, s.dy)
    end
  end,
  RIP_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, LOOK)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 1.05)
      end
    end
  end,
}

return Rippers
