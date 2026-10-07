-- Rollermines: the Combine's mines that hunt, after Half-Life 2's. A steel
-- ball sunk in the ground until somebody comes near; then it hops out,
-- blades snapping open, rolls after them, faster than anyone can run and
-- nearly as fast as a car, and goes off when it touches them, or their car.
--
-- Any map that marks `map.rollermines` ({ x, y, r, count }: the Winding
-- Road does) gets them set there when everyone arrives on a quest: `count`
-- to a spot for one human, more with more (Bosses.count), scattered within
-- `r`. A map may also ask for some scattered at random over all of its
-- open ground (`map.rollermineScatter` = { count, clear = { { x, y, r }... } }:
-- `count` for one human, more with more, none within `r` of any `clear`
-- spot), different every time. What each does is its brain's (brain.lua).
-- A quest's end or a map change takes them all away. Another feature can
-- set some down anywhere, already awake (`serverSummon`: A-Man's briefcase).
--
-- One goes off on contact (its blade tips: 28 px from a person's middle;
-- somebody on foot it touches takes a shock first, `Brain.SHOCK`, 35, which
-- stuns them), when it is shot to pieces (`Brain.HEALTH`, 40)
-- or when a blast catches it (another mine's too: they set each other off
-- in a chain). Its blast is the weapons feature's (`Brain.BLAST`: 45 at the
-- middle, 95 px across), so it hurts everyone and every car near it, the
-- Combine's rounds (owned by nobody) pass by it, and one a player shot
-- is their kill and spills a koin.
--
-- The host owns them; clients hear about every one at 15 Hz.
--
-- Messages
--   server -> all  RLM_STATE <tick> (<id> <x> <y> <hp> <mode> <armed>)...  (unreliable, 15 Hz;
--                  mode 1 dormant, 2 popping out, 3 rolling, 4 stopped; armed 1 while it beeps)
--   server -> all  RLM_DOWN  <id>     it went off (the blast itself is weapons' WPN_BOOM)
--
-- Modules
--   brain.lua    what each one does, on the host
--   render.lua   one drawn from above: sunk, hopping out, rolling, about to go
--   sounds.lua   their noises: popping out, the whirr of it rolling, the beep

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Bosses = require("src.features.bosses")
local Brain = require("src.features.rollermines.brain")
local Render = require("src.features.rollermines.render")
local Sounds = require("src.features.rollermines.sounds")

local Rollermines = {
  name = "rollermines",
}

-- Tuning ------------------------------------------------------------------
Rollermines.drops = 1 -- koins one a player shot spills

local SYNC_EVERY = 2 -- server ticks between RLM_STATE
local EMPTY_AFTER = 1 -- sends of an empty list after the last one goes, so every screen clears
local SMOOTHING = 14 -- per second, the easing of what is drawn
local SNAP = 200 -- px; a jump this big is a placement, not a roll
local HURT = 0.15 -- seconds one flashes white after a hit
local WHIRR_EVERY = 0.36 -- seconds between a rolling one's whirrs
local BEEP_EVERY = 0.3 -- seconds between an armed one's beeps
local MODES = { dormant = 1, popping = 2, roll = 3, idle = 4 }
local STALE = 1 -- seconds without word from the host before what it last sent is dropped: a
-- late state from a map just left can't leave a ghost behind for longer

-- Server --------------------------------------------------------------------

local sv = nil -- { brain, syncIn, emptySends }

local shown = {} -- id -> { x, y, dx, dy, vx, vy, heading, spin, hp, mode, armed, t, hurt, whirrIn, beepIn }

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.map
end

--- Everyone arrived on a quest: the map's mines set at each of its spots.
function Rollermines:serverQuestStarted(server)
  local map = cityMap()
  sv = nil
  if not (map and map.rollermines) then
    return
  end
  sv = { brain = Brain.new(), syncIn = 0, emptySends = 0 }
  for _, s in ipairs(map.rollermines) do
    for _ = 1, Bosses.count(s.count, server) do
      local a, d = love.math.random() * 2 * math.pi, math.sqrt(love.math.random()) * s.r
      sv.brain:place(s.x + math.cos(a) * d, s.y + math.sin(a) * d)
    end
  end
  local scatter, city = map.rollermineScatter, Features.byName["city-map"]
  if scatter and city then
    local function clear(x, y)
      for _, c in ipairs(scatter.clear or {}) do
        if (x - c.x) ^ 2 + (y - c.y) ^ 2 < c.r * c.r then
          return false
        end
      end
      return true
    end
    for _ = 1, Bosses.count(scatter.count, server) do
      for _ = 1, 20 do -- a random open spot, away from the ones kept clear
        local x, y = city:randomRoadPoint()
        if x and clear(x, y) then
          sv.brain:place(x + (love.math.random() - 0.5) * 40, y + (love.math.random() - 0.5) * 40)
          break
        end
      end
    end
  end
end

local function clear(server)
  if sv then
    sv = nil
    server:broadcast(Protocol.encode("RLM_STATE", server.tick)) -- an empty list clears every screen
  end
end

function Rollermines:serverQuestEnded(server)
  clear(server)
end

function Rollermines:mapChanged(_map, server)
  if server then
    clear(server)
  end
  shown = {} -- off every screen at once: the clearing RLM_STATE may carry a tick already seen
end

function Rollermines:serverStart()
  sv = nil
end

local function sync(server)
  sv.syncIn = sv.syncIn - 1
  if sv.syncIn > 0 then
    return
  end
  sv.syncIn = SYNC_EVERY
  local parts = { server.tick }
  for _, m in ipairs(sv.brain.list) do
    parts[#parts + 1] = m.id
    parts[#parts + 1] = ("%.0f"):format(m.x)
    parts[#parts + 1] = ("%.0f"):format(m.y)
    parts[#parts + 1] = ("%.0f"):format(math.max(0, m.hp))
    parts[#parts + 1] = MODES[m.mode]
    parts[#parts + 1] = m.armed and 1 or 0
  end
  if #parts == 1 then
    if sv.emptySends >= EMPTY_AFTER then
      return
    end
    sv.emptySends = sv.emptySends + 1
  else
    sv.emptySends = 0
  end
  local msg = Protocol.encode("RLM_STATE", unpack(parts))
  for _, player in pairs(server.players) do
    if not player.bot then
      server:send(player, msg, true)
    end
  end
end

--- One goes off: the blast (and first a shock for whoever on foot it
--- touched), and if a player shot it, their kill and a koin.
local function blow(server, m)
  server:broadcast(Protocol.encode("RLM_DOWN", m.id))
  local weapons = Features.byName.weapons
  local zapped = m.zap
  if zapped and weapons and weapons.serverDamage and Features.present(zapped) then
    local px, py = Features.bodyPose(server, zapped)
    weapons:serverDamage(server, zapped, nil, Brain.SHOCK, math.atan2(py - m.y, px - m.x), "shock")
  end
  if weapons and weapons.explode then
    weapons:explode(server, { id = 0, owner = m.by or 0, vx = m.vx, vy = m.vy + 0.01, blast = Brain.BLAST }, m.x, m.y)
  end
  if m.by and m.by ~= 0 then
    local money = Features.byName.money
    if money and money.drop then
      money:drop(server, m.x, m.y, Rollermines.drops)
    end
    Features.call("serverKill", server, { kind = "rollermine", x = m.x, y = m.y, by = m.by })
  end
end

function Rollermines:serverStep(server, dt)
  if not sv then
    return
  end
  sv.brain:update(server, dt)
  local due = sv.brain:due()
  if due then
    for _, m in ipairs(due) do
      blow(server, m)
      if not sv then
        return -- the blast ended the quest (it killed the last of them...) and took the rest away
      end
    end
  end
  sync(server)
end

--- A round or a blast through (x, y): the `serverShotAt` convention. Rounds
--- owned by nobody (the Combine's) pass by; a blast (no `damage`) sets it off.
function Rollermines:serverShotAt(_server, x, y, radius, by, _angle, damage)
  if not sv or (by == 0 and damage) then
    return false
  end
  local m = sv.brain:at(x, y, radius)
  if not m then
    return false
  end
  if by and by ~= 0 then
    m.by = by
  end
  sv.brain:hurt(m, damage or Brain.HEALTH, damage == nil)
  return true
end

function Rollermines:serverFreezeArea(_server, x, y, radius, seconds)
  if sv then
    sv.brain:freeze(x, y, radius, seconds)
  end
end

function Rollermines:serverPanicArea(_server, x, y, radius)
  if sv then
    sv.brain:scare(x, y, radius)
  end
end

--- Another feature sets `count` down at (x, y) on any map, whether it has
--- mines of its own or not (A-Man's briefcase in the Citadel): they land
--- within `r` px already hopping out, and roll after whoever is nearest.
--- Returns how many.
function Rollermines:serverSummon(_server, x, y, count, r)
  if not sv then
    sv = { brain = Brain.new(), syncIn = 0, emptySends = 0 }
  end
  for _ = 1, count do
    local a, d = love.math.random() * 2 * math.pi, math.sqrt(love.math.random()) * (r or 60)
    local m = sv.brain:place(x + math.cos(a) * d, y + math.sin(a) * d)
    m.mode, m.t = "popping", 0
  end
  return count
end

--- The host's rollermines, for tests.
function Rollermines.state()
  return sv
end

-- Client --------------------------------------------------------------------

local lastTick = 0
local clock = 0
local heardAt = 0 -- when the last RLM_STATE came

function Rollermines:load()
  Sounds.load()
end

function Rollermines:exitGame()
  shown, lastTick = {}, 0
end

function Rollermines:update(dt)
  clock = clock + dt
  if next(shown) and love.timer.getTime() - heardAt > STALE then
    shown = {}
  end
  local k = math.min(1, dt * SMOOTHING)
  for _, m in pairs(shown) do
    m.t = m.t + dt
    local ex, ey = m.x - m.dx, m.y - m.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      m.dx, m.dy = m.x, m.y
    else
      local px, py = m.dx, m.dy
      m.dx, m.dy = m.dx + ex * k, m.dy + ey * k
      local mx, my = m.dx - px, m.dy - py
      local moved = math.sqrt(mx * mx + my * my)
      if moved > 0.05 then
        m.heading = math.atan2(my, mx)
      end
      m.spin = m.spin + moved / Render.RADIUS
      m.speed = m.speed + (moved / math.max(dt, 1e-6) - m.speed) * math.min(1, dt * 6)
    end
    m.hurt = math.max(0, m.hurt - dt)
    if m.mode == MODES.roll and m.speed > 60 then
      m.whirrIn = m.whirrIn - dt
      if m.whirrIn <= 0 then
        m.whirrIn = WHIRR_EVERY
        Sounds.play("whirr", m.dx, m.dy, 0.8 + math.min(0.6, m.speed / 700))
      end
    end
    if m.armed then
      m.beepIn = m.beepIn - dt
      if m.beepIn <= 0 then
        m.beepIn = BEEP_EVERY
        Sounds.play("beep", m.dx, m.dy)
      end
    end
  end
end

--- How far through what it is doing one is, as the model wants it.
local function pose(m)
  local p = { spin = m.spin, heading = m.heading, armed = m.armed, hurt = m.hurt / HURT * 0.7 }
  if m.mode == MODES.dormant then
    p.sink, p.blades = 1, 0
  elseif m.mode == MODES.popping then
    local k = math.min(1, m.t / Brain.POP)
    p.sink = math.max(0, 1 - k * 2)
    p.lift = math.sin(k * math.pi)
    p.blades = math.max(0, k * 1.6 - 0.6)
  else
    p.blades = 1
  end
  return p
end

--- The dormant ones in the ground, under the cars.
function Rollermines:drawBelowCars()
  for _, m in pairs(shown) do
    if m.mode == MODES.dormant then
      Render.draw(m.dx, m.dy, pose(m), clock)
    end
  end
end

function Rollermines:drawAboveCars()
  for _, m in pairs(shown) do
    if m.mode ~= MODES.dormant then
      Render.draw(m.dx, m.dy, pose(m), clock)
      if m.hp < Brain.HEALTH then -- a bar under it once it is hurt
        local bw, f = 22, math.max(0, m.hp / Brain.HEALTH)
        love.graphics.setColor(0, 0, 0, 0.6)
        love.graphics.rectangle("fill", m.dx - bw / 2 - 1, m.dy + Render.RADIUS + 9, bw + 2, 4)
        love.graphics.setColor(1 - f, f, 0.2)
        love.graphics.rectangle("fill", m.dx - bw / 2, m.dy + Render.RADIUS + 10, bw * f, 2)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

Rollermines.clientMessages = {
  RLM_STATE = function(_client, args)
    local tick = tonumber(args[1])
    if not tick or tick <= lastTick then
      return
    end
    lastTick, heardAt = tick, love.timer.getTime()
    local seen = {}
    for i = 2, #args - 5, 6 do
      local id, x, y = tonumber(args[i]), tonumber(args[i + 1]), tonumber(args[i + 2])
      local hp, mode = tonumber(args[i + 3]), tonumber(args[i + 4])
      if id and x and y and mode then
        local m = shown[id]
        if not m then
          m = { dx = x, dy = y, heading = love.math.random() * 2 * math.pi, spin = love.math.random() * 6,
            speed = 0, hp = hp or Brain.HEALTH, mode = mode, t = 0, hurt = 0, whirrIn = 0, beepIn = 0 }
          shown[id] = m
        elseif m.mode ~= mode then
          m.mode, m.t = mode, 0
          if mode == MODES.popping then
            Sounds.play("pop", x, y, 0.9 + love.math.random() * 0.2)
          end
        end
        m.x, m.y = x, y
        if hp and hp < m.hp then
          m.hurt = HURT
        end
        m.hp = hp or m.hp
        local armed = args[i + 5] == "1"
        if armed and not m.armed then
          m.beepIn = 0
        end
        m.armed = armed
        seen[id] = true
      end
    end
    for id in pairs(shown) do
      if not seen[id] then
        shown[id] = nil
      end
    end
  end,
  RLM_DOWN = function(_client, args)
    local id = tonumber(args[1])
    if id then
      shown[id] = nil
    end
  end,
}

return Rollermines
