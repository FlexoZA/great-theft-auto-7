-- The Static's sparkers (docs/cyber-feud.md, "The Static"): hooded, a belt
-- of cyan EMP grenades, hanging back on the Market's west lanes (the map's
-- `sparkers`). troops.lua starts, steps and stops them with the rest of the
-- Static, and passes rounds on to them; their heads are sparker_brain.lua.
--
-- A sparker keeps its distance and lobs EMPs: one raised for a moment,
-- then thrown in an arc, a cyan ring on the ground where it will come down
-- for as long as it is in the air, and a burst there (`shock`): EMP.damage
-- at the middle, a third of it at the edge, so a player caught near the
-- middle is stunned too (damage's `stunMin`). It is a jolt for machines,
-- not people: Halcyon's officers and enforcers shrug it off, and so does
-- the Static. Halcyon's watcher drones are its `rivals`: one caught in the
-- burst is knocked out (watchers.lua's serverEmp). (Turrets will be too,
-- once they are on the street; a car stalled by one waits for cars to
-- need it.) In
-- the feud Halcyon shoots at sparkers as at the rest of the Static.
--
-- Messages
--   server -> all  SPK_STATE <tick> (<id> <x> <y> <facing> <hp> <alert> <windUp>)...
--                  (unreliable, 15 Hz; alert 1 has somebody; windUp 1 has a grenade raised)
--   server -> all  SPK_LOB   <id> <ox> <oy> <x> <y> <flight>   an EMP in the air from o to (x, y)
--   server -> all  SPK_EMP   <x> <y>                           one went off
--   server -> all  SPK_DOWN  <id> <x> <y> <angle>

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Body = require("src.body")
local Sight = require("src.features.d-day.sight")
local Corpses = require("src.features.corpses")
local Synth = require("src.audio.synth")
local Audio = require("src.audio")
local Brain = require("src.features.cyber-feud.sparker_brain")

local Sparkers = {}

-- Tuning ------------------------------------------------------------------
Sparkers.health = 40
Sparkers.fov = math.rad(100)
Sparkers.aware = 200
Sparkers.drops = 4 -- koins one spills (a ganger 3)
Sparkers.firstId = 13001
Sparkers.EMP = { radius = 110, damage = 26, speed = 480, minFlight = 0.35, arc = 0.3 }

local SYNC_EVERY = 2
local EMPTY_AFTER = 1
local SMOOTHING = 14
local SNAP = 200
local STALE = 1
local HURT = 0.18
local BURST = 0.55 -- seconds a burst shows

local CYAN = { 0.18, 0.90, 1.00 }
local WHITE = { 0.85, 1.00, 1.00 }

local random = love.math.random

local function fmt(v)
  return ("%.1f"):format(v)
end

local function dist2(ax, ay, bx, by)
  return (ax - bx) ^ 2 + (ay - by) ^ 2
end

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends, flying = { { ox, oy, x, y, t, flight } } }

--- `s` throws an EMP from where it stands at (x, y), landing short of the first wall.
local function lob(server, s, x, y)
  local angle = math.atan2(y - s.y, x - s.x)
  local d = math.sqrt(dist2(s.x, s.y, x, y))
  local ex, ey = Sight.reach(s.x, s.y, angle, d)
  local back = math.min(12, math.sqrt(dist2(s.x, s.y, ex, ey))) -- off the wall, not in it
  if ex ~= x or ey ~= y then
    ex, ey = ex - math.cos(angle) * back, ey - math.sin(angle) * back
  end
  local E = Sparkers.EMP
  local flight = math.max(E.minFlight, math.sqrt(dist2(s.x, s.y, ex, ey)) / E.speed)
  sv.flying[#sv.flying + 1] = { ox = s.x, oy = s.y, x = ex, y = ey, t = 0, flight = flight }
  server:broadcast(Protocol.encode("SPK_LOB", s.id, fmt(s.x), fmt(s.y), fmt(ex), fmt(ey), ("%.3f"):format(flight)))
end

--- An EMP going off at (x, y): a jolt to every player on foot within its
--- radius, harder nearer the middle, and any watcher drone caught knocked out.
local function burst(server, x, y)
  server:broadcast(Protocol.encode("SPK_EMP", fmt(x), fmt(y)))
  require("src.features.cyber-feud.watchers").serverEmp(x, y, Sparkers.EMP.radius) -- the machines it is for
  require("src.features.cyber-feud.stings").serverEmp(x, y, Sparkers.EMP.radius)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverDamage) then
    return
  end
  local E = Sparkers.EMP
  for _, p in pairs(server.players) do
    if Features.visible(server, p) and not p.vehicle then
      local px, py = Features.bodyPose(server, p)
      local d = math.sqrt(dist2(px, py, x, y))
      if d <= E.radius then
        local amount = math.floor(E.damage * (1 - (2 / 3) * d / E.radius) + 0.5)
        weapons:serverDamage(server, p, nil, amount, math.atan2(py - y, px - x), "shock")
      end
    end
  end
end

function Sparkers.serverStart(server, map, nav, calm)
  Sparkers.serverStop(server)
  if not (map.sparkers and nav) then
    return nil
  end
  local brain = Brain.new({
    fov = Sparkers.fov, aware = Sparkers.aware, health = Sparkers.health, nav = nav, lob = lob,
    firstId = Sparkers.firstId, calm = calm,
  })
  for _, r in ipairs(map.sparkers) do
    brain:add(r.route, r.start or 1)
  end
  sv = { brain = brain, syncIn = 0, emptySends = 0, flying = {} }
  return brain
end

function Sparkers.serverWake()
  if sv then
    sv.brain.calm = false
  end
end

function Sparkers.serverStop(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("SPK_STATE", server.tick))
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
    parts[#parts + 1] = s.target and 1 or 0
    parts[#parts + 1] = s.windUp and 1 or 0
  end
  local msg = Protocol.encode("SPK_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

function Sparkers.serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  for i = #sv.flying, 1, -1 do -- the EMPs in the air keep going whatever happens to who threw them
    local g = sv.flying[i]
    g.t = g.t + dt
    if g.t >= g.flight then
      table.remove(sv.flying, i)
      burst(server, g.x, g.y)
    end
  end
  sync(server)
end

--- Where EMPs are coming down, for enemies that get out of the way (the
--- assassin droids' brain asks grenades and abilities the same).
function Sparkers.serverIncoming()
  local out = {}
  for _, g in ipairs(sv and sv.flying or {}) do
    out[#out + 1] = { x = g.x, y = g.y, radius = Sparkers.EMP.radius }
  end
  return out
end

local function down(server, s, by, angle, cause)
  server:broadcast(Protocol.encode("SPK_DOWN", s.id, fmt(s.x), fmt(s.y), ("%.3f"):format(angle or 0)))
  local money = Features.byName.money
  if money and money.drop then
    money:drop(server, s.x, s.y, Sparkers.drops)
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
function Sparkers.serverShotAt(server, x, y, radius, by, angle, damage, dtype, from)
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

function Sparkers.serverFreezeArea(x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Sparkers.serverPanicArea(x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius)
  end
end

--- For tests.
function Sparkers.server()
  return sv
end

-- Client --------------------------------------------------------------------

local shown = {} -- id -> { x, y, dx, dy, facing, hp, alert, windUp, stride, hurt }
local flying = {} -- { ox, oy, x, y, t, flight }
local bursts = {} -- { x, y, t, bolts }
local lastTick, heardAt, clock = 0, 0, 0
local bank = {} -- toss, zap: base Sources

-- A dark hood over everything, a cyan-glowing belt drawn over him.
local LOOK = {
  shirt = { 0.15, 0.17, 0.20 }, pants = { 0.10, 0.10, 0.12 }, shoes = { 0.05, 0.05, 0.06 },
  skin = { 0.58, 0.44, 0.34 }, hat = { 0.20, 0.22, 0.26 },
}

function Sparkers.load()
  local function make(seconds, build)
    local buf = Synth.newBuffer(seconds)
    build(buf)
    local src = love.audio.newSource(buf:toSoundData(0.85), "static")
    src:setAttenuationDistances(260, 2200)
    return src
  end
  bank.toss = make(0.25, function(buf) -- a rising whine as it arms
    buf:sweep(0, 0.22, 900, 2600, { wave = "square", amp = 0.25, decay = 0.15 })
    buf:lowpass(3500)
  end)
  bank.zap = make(0.6, function(buf) -- the burst: a crack, a buzz falling away
    buf:noiseBurst(0, 0.08, { amp = 1.0, decay = 0.02 })
    buf:sweep(0, 0.5, 220, 60, { wave = "saw", amp = 0.6, decay = 0.18 })
    for k = 0, 5 do
      buf:noiseBurst(0.05 + k * 0.07, 0.03, { amp = 0.5 - k * 0.07, decay = 0.01 })
    end
    buf:highpass(120)
    buf:drive(1.8)
  end)
end

local function play(name, x, y, volume)
  local base = bank[name]
  if base then
    local s = base:clone()
    s:setPosition(x, 0, y)
    s:setPitch(0.94 + random() * 0.12)
    s:setVolume(volume * Audio.volume("weapons"))
    s:play()
  end
end

function Sparkers.clear()
  shown, flying, bursts, lastTick = {}, {}, {}, 0
end

--- A jagged bolt out from the middle of a burst, as a list of points.
local function bolt(angle, length)
  local pts, n = { 0, 0 }, 5
  for k = 1, n do
    local d = length * k / n
    local a = angle + (random() - 0.5) * 0.7
    pts[#pts + 1] = math.cos(a) * d
    pts[#pts + 1] = math.sin(a) * d
  end
  return pts
end

function Sparkers.update(dt)
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
  for i = #flying, 1, -1 do
    flying[i].t = flying[i].t + dt
    if flying[i].t > flying[i].flight + 0.2 then -- the burst takes over (or never came)
      table.remove(flying, i)
    end
  end
  for i = #bursts, 1, -1 do
    local b = bursts[i]
    b.t = b.t + dt
    if b.t > BURST then
      table.remove(bursts, i)
    elseif b.t - b.drawn > 0.07 then -- the bolts flicker
      b.drawn, b.bolts = b.t, {}
      for n = 1, 7 do
        b.bolts[n] = bolt(n / 7 * 2 * math.pi + random() * 0.6, Sparkers.EMP.radius * (0.5 + random() * 0.5))
      end
    end
  end
end

--- Their cones, the rings where EMPs in the air will come down, and the bursts.
function Sparkers.drawBelowCars()
  local R = Sparkers.EMP.radius
  if not Features.any("hideSightCones") then
    for id, s in pairs(shown) do
      Sight.draw(s.dx, s.dy, s.facing, Brain.RANGE, s.alert, clock, Sparkers.fov, { seed = id, color = CYAN })
    end
  end
  for _, g in ipairs(flying) do
    local k = math.min(1, g.t / g.flight)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.08 + 0.12 * k)
    love.graphics.circle("fill", g.x, g.y, R, 40)
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.45 + 0.45 * k)
    love.graphics.setLineWidth(2)
    for n = 0, 11 do -- a dashed ring, turning
      local a0 = n / 12 * 2 * math.pi + clock * 1.5
      love.graphics.arc("line", "open", g.x, g.y, R, a0, a0 + 0.3, 6)
    end
    love.graphics.setLineWidth(1)
  end
  for _, b in ipairs(bursts) do
    local k = b.t / BURST
    love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.35 * (1 - k))
    love.graphics.circle("fill", b.x, b.y, R * (0.6 + 0.4 * k), 40)
    love.graphics.setColor(WHITE[1], WHITE[2], WHITE[3], 0.9 * (1 - k))
    love.graphics.setLineWidth(3)
    love.graphics.circle("line", b.x, b.y, R * (0.3 + 0.75 * k), 40)
    love.graphics.setLineWidth(1)
  end
end

function Sparkers.drawAboveCars()
  for _, s in pairs(shown) do
    Body.person(s.dx, s.dy, s.facing, math.sin(s.stride * 0.18) * 1.2, LOOK)
    love.graphics.push()
    love.graphics.translate(s.dx, s.dy)
    love.graphics.rotate(s.facing)
    for n = -2, 2 do -- the belt of grenades round his middle
      love.graphics.setColor(CYAN[1], CYAN[2], CYAN[3], 0.6 + 0.4 * math.abs(math.sin(clock * 3 + n)))
      love.graphics.circle("fill", -1, n * 2.2, 1.1, 6)
    end
    if s.windUp then -- one raised behind him, glowing hot
      love.graphics.setColor(WHITE)
      love.graphics.circle("fill", -2, 9, 2.6, 8)
      love.graphics.setColor(CYAN)
      love.graphics.circle("line", -2, 9, 3.6 + math.sin(clock * 30), 8)
    end
    love.graphics.pop()
    local r = Body.SHOULDERS
    if s.hurt > 0 then
      love.graphics.setColor(1, 1, 1, s.hurt / HURT * 0.6)
      love.graphics.circle("fill", s.dx, s.dy, r, 12)
    end
    if s.alert then
      love.graphics.setFont(require("src.ui").fonts.heading)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.printf("!", s.dx - 19, s.dy - r - 30, 40, "center")
      love.graphics.setColor(CYAN)
      love.graphics.printf("!", s.dx - 20, s.dy - r - 31, 40, "center")
    end
    if s.hp < Sparkers.health then
      local bw, f = 20, math.max(0, s.hp / Sparkers.health)
      love.graphics.setColor(0, 0, 0, 0.6)
      love.graphics.rectangle("fill", s.dx - bw / 2 - 1, s.dy + r + 3, bw + 2, 4)
      love.graphics.setColor(1 - f, f, 0.2)
      love.graphics.rectangle("fill", s.dx - bw / 2, s.dy + r + 4, bw * f, 2)
    end
  end
  local E = Sparkers.EMP
  for _, g in ipairs(flying) do -- the grenade in the air, its shadow on the ground under it
    local k = math.min(1, g.t / g.flight)
    local x, y = g.ox + (g.x - g.ox) * k, g.oy + (g.y - g.oy) * k
    local h = E.arc * math.sqrt(dist2(g.ox, g.oy, g.x, g.y)) * math.sin(math.pi * k)
    love.graphics.setColor(0, 0, 0, 0.35)
    love.graphics.circle("fill", x, y, 3, 8)
    love.graphics.setColor(CYAN)
    love.graphics.circle("fill", x, y - h, 3.5, 8)
    love.graphics.setColor(WHITE)
    love.graphics.circle("fill", x, y - h, 1.6, 6)
  end
  for _, b in ipairs(bursts) do -- the bolts
    love.graphics.push()
    love.graphics.translate(b.x, b.y)
    love.graphics.setColor(WHITE[1], WHITE[2], WHITE[3], 1 - b.t / BURST)
    love.graphics.setLineWidth(1.5)
    for _, pts in ipairs(b.bolts) do
      love.graphics.line(pts)
    end
    love.graphics.setLineWidth(1)
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1)
end

function Sparkers.drawNightLights(glow)
  for _, s in pairs(shown) do
    glow(s.dx, s.dy, s.windUp and 60 or 34, CYAN, s.windUp and 0.8 or 0.35)
  end
  for _, g in ipairs(flying) do
    local k = math.min(1, g.t / g.flight)
    glow(g.ox + (g.x - g.ox) * k, g.oy + (g.y - g.oy) * k, 50, CYAN, 0.7)
  end
  for _, b in ipairs(bursts) do
    glow(b.x, b.y, Sparkers.EMP.radius * 2, CYAN, 1 - b.t / BURST)
  end
end

function Sparkers.walkers()
  local list = {}
  for id, s in pairs(shown) do
    list[#list + 1] = { key = "spk" .. id, x = s.dx, y = s.dy, size = "person" }
  end
  return list
end

Sparkers.clientMessages = {
  SPK_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 6, 7 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      if id and x and y then
        local s = shown[id]
        if not s then
          s = { dx = x, dy = y, stride = 0, hurt = 0, hp = Sparkers.health }
          shown[id] = s
        end
        s.x, s.y = x, y
        s.facing = tonumber(args[i + 3]) or s.facing or 0
        local hp = tonumber(args[i + 4]) or s.hp
        if hp < s.hp then
          s.hurt = HURT
        end
        s.hp = hp
        s.alert = args[i + 5] == "1"
        s.windUp = args[i + 6] == "1"
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  SPK_LOB = function(_client, args)
    local ox, oy, x, y = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]), tonumber(args[5])
    local flight = tonumber(args[6])
    if ox and oy and x and y and flight then
      flying[#flying + 1] = { ox = ox, oy = oy, x = x, y = y, t = 0, flight = flight }
      play("toss", ox, oy, 0.4)
    end
  end,
  SPK_EMP = function(_client, args)
    local x, y = tonumber(args[1]), tonumber(args[2])
    if not (x and y) then
      return
    end
    local nearest, best = nil, math.huge
    for i, g in ipairs(flying) do
      local d2 = dist2(g.x, g.y, x, y)
      if d2 < best then
        nearest, best = i, d2
      end
    end
    if nearest then
      table.remove(flying, nearest)
    end
    bursts[#bursts + 1] = { x = x, y = y, t = 0, drawn = -1, bolts = {} }
    play("zap", x, y, 0.7)
  end,
  SPK_DOWN = function(_client, args)
    local id = tonumber(args[1])
    local x, y, angle = tonumber(args[2]), tonumber(args[3]), tonumber(args[4]) or 0
    local s = id and shown[id]
    if id then
      shown[id] = nil
    end
    if x and y then
      Corpses.add(s and s.dx or x, s and s.dy or y, angle, LOOK)
      if Features.byName.pedestrians then
        require("src.features.pedestrians.sounds").play("splat", x, y, 0.95)
      end
    end
  end,
}

return Sparkers
