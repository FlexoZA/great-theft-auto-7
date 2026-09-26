-- Shotgun, on the host: the sniper on top of the bluff. Deadly with a
-- sniper rifle, which he hates; he would rather use his pistol, and he
-- does, on anyone who gets close while he can't slip away.
--
-- How he fights:
--   * He goes out of sight (the chicken, abilities/chicken.lua, on his own
--     numbers: STEALTH) the moment he can, and while hidden walks to a new
--     spot on the plateau (the map's `perches`): one on the lip over the
--     meadow while everyone is down there, and while somebody has come up,
--     one as far from them as he can find.
--   * When it wears off he picks the nearest player he can see and draws a
--     bead on them: for WARN seconds the target is marked on every screen
--     (init.lua says so: SG_AIM), his aim follows them, leading the way
--     they are moving, until LOCK before the shot, when it stops. Then the
--     round goes where the aim was. Stop, turn or dodge in that last moment,
--     or get behind something, and it misses.
--   * Somebody within EVADE of him: he vanishes if he can and goes
--     somewhere else; if he can't, he backs away from them firing his
--     pistol.
--   * FIVE rounds, then a long RELOAD.
--
-- The cliff (city-map's "cliff") is solid, rounds included: nobody below
-- can hit him. He fires down over the lip: a round aimed at somebody below
-- leaves from just past the rock, so the cliff stops their bullets and
-- never his. His eyes see over the lip the same way (`clear`).
--
-- Like every boss (bosses/stamina.lua) he has breath: running (hurrying
-- to a new spot, backing off) spends it, and a vanish costs STEALTH_BREATH;
-- winded, he walks, and stays where everyone can see him. This module only
-- thinks and hands back what happened; init.lua owns the wire.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local Stamina = require("src.features.bosses.stamina")
local Chicken = require("src.features.abilities.chicken")
local Guns = require("src.features.weapons.guns")

local Boss = {}
Boss.__index = Boss

-- Tuning --------------------------------------------------------------------

Boss.HEALTH = 1600 -- eight sniper rounds or eighty pistol rounds, for one player (more humans, more)
Boss.RADIUS = 12 -- px
Boss.SPEED = 105 -- px/s, hurrying to a new spot
Boss.WALK_SPEED = 42 -- px/s winded: a walk (45) leaves him behind
Boss.BREATH = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  drain = 11, -- per second hurrying (~9 s of it)
  regen = 14,
  recovered = 50,
  breath = 40, -- in him before he vanishes
}
Boss.STEALTH_BREATH = 20 -- what a vanish costs him
-- His chicken: out of sight long enough to get somewhere, back soon.
Boss.STEALTH = Chicken.variant({ seconds = 6, cooldown = 15 })
Boss.RANGE = 1800 -- px he picks targets at (the rifle carries a little further)
Boss.EVADE = 320 -- px: closer than this and he gets away, or out the pistol
Boss.WARN = 1.0 -- seconds the target is marked before the shot
Boss.LOCK = 0.25 -- seconds before the shot that his aim stops following
Boss.BOLT = 1.6 -- seconds from one shot to drawing the next bead
Boss.MAGAZINE = 5
Boss.RELOAD = 5 -- seconds
Boss.PISTOL_EVERY = 0.4 -- seconds between pistol rounds
Boss.PISTOL_SPREAD = 0.06
Boss.MUZZLE = 20
Boss.SAY_EVERY = { 5, 9 } -- seconds between speeches, at random in this range
Boss.DROPS = 35 -- koins he spills when he goes down

Boss.lines = {
  "No debating! Debating is how arguments START!",
  "You raised a point. That's a crime. I'm arresting the point.",
  "I'd rather use my pistol. This rifle has OPINIONS.",
  "Stop talking! Words are just debating in small pieces!",
  "There are two sides to every story and both of them are going to jail!",
  "Hold still! Moving is a form of rebuttal!",
  "Counter-argument? COUNTER-ARREST!",
  "I don't debate. I snipe. It's quieter.",
  "Moderators are accomplices!",
  "I'm not arguing with you! ARGUING IS ILLEGAL!",
  "One more word and it's a debate. One more debate and it's a SENTENCE.",
  "I hate this rifle. I hate debating MORE.",
  "You call it discourse. I call it a list of suspects.",
  "Agree with me or don't! Either way, no discussing it!",
}

local random = love.math.random

--- The map in play, if it is the bluff.
local function cliffMap()
  local city = Features.byName["city-map"]
  local map = city and city.map
  return map and map.kind == "cliff" and map or nil
end

--- Is (x, y) inside a solid of the map's, the cliff counted or not?
local function solidAt(map, x, y, withLedge)
  local col = map.cells[math.floor(x / Layout.CELL)]
  local list = col and col[math.floor(y / Layout.CELL)]
  if not list then
    return false
  end
  for _, b in ipairs(list) do
    if (withLedge or not b.ledge) and x >= b.x and x <= b.x + b.w and y >= b.y and y <= b.y + b.h then
      return true
    end
  end
  return false
end

--- Can he see from (x0, y0) to (x1, y1)? Walls, boulders and trees are in
--- the way; the cliff is not: he is on top of it, looking down.
function Boss.clear(map, x0, y0, x1, y1)
  local dx, dy = x1 - x0, y1 - y0
  local n = math.floor(math.sqrt(dx * dx + dy * dy) / 12)
  for i = 1, n do
    local k = i / (n + 1)
    if solidAt(map, x0 + dx * k, y0 + dy * k, false) then
      return false
    end
  end
  return true
end

--- Where a round from (x, y) along `aim` should leave from: past the
--- cliff's rock if the line crosses it within `reach`, just past his hands otherwise.
local function muzzle(map, x, y, aim, reach)
  local cx, cy = math.cos(aim), math.sin(aim)
  local inside = false
  for d = Boss.MUZZLE, reach, 6 do
    local px, py = x + cx * d, y + cy * d
    local rock = solidAt(map, px, py, true) and not solidAt(map, px, py, false)
    if inside and not rock then
      return px + cx * 4, py + cy * 4
    end
    inside = rock
  end
  return x + cx * Boss.MUZZLE, y + cy * Boss.MUZZLE
end

--- Him, at (x, y), with `hp` hit points (HEALTH when not given).
function Boss.new(x, y, hp)
  hp = hp or Boss.HEALTH
  return setmetatable({
    x = x,
    y = y,
    facing = math.pi / 2,
    hp = hp,
    max = hp,
    time = 0,
    hiddenUntil = 0, -- out of sight until then
    stealthReady = 0, -- his chicken is back then
    goal = nil, -- the perch he is making for
    aim = nil, -- { target, t, x, y, vx, vy, locked }: a bead drawn on somebody
    boltIn = 0,
    rounds = Boss.MAGAZINE,
    reloadIn = 0,
    pistolIn = 0,
    sayIn = 2,
    frozen = 0,
    panic = nil,
    stuck = 0,
    sidestep = 0,
    side = 1,
    breath = Stamina.new(Boss.BREATH),
    running = false,
  }, Boss)
end

function Boss:hidden()
  return self.time < self.hiddenUntil
end

local function blockedAt(x, y)
  local r = Boss.RADIUS
  for _, f in ipairs(Features.list) do
    if f.blocksPoint then
      if
        f:blocksPoint(x, y)
        or f:blocksPoint(x - r, y)
        or f:blocksPoint(x + r, y)
        or f:blocksPoint(x, y - r)
        or f:blocksPoint(x, y + r)
      then
        return true
      end
    end
  end
  return false
end

function Boss:walk(angle, speed, dt)
  if self.sidestep > 0 then
    self.sidestep = self.sidestep - dt
    angle = angle + self.side * math.pi / 2
  end
  local px, py = self.x, self.y
  local nx = self.x + math.cos(angle) * speed * dt
  if not blockedAt(nx, self.y) then
    self.x = nx
  end
  local ny = self.y + math.sin(angle) * speed * dt
  if not blockedAt(self.x, ny) then
    self.y = ny
  end
  if (self.x - px) ^ 2 + (self.y - py) ^ 2 < (speed * dt * 0.4) ^ 2 then
    self.stuck = self.stuck + dt
    if self.stuck > 0.4 then
      self.stuck, self.sidestep, self.side = 0, 0.8, -self.side
    end
  else
    self.stuck = 0
  end
end

--- His pace: a hurry with breath in him, a walk without.
function Boss:pace(scale)
  return self.breath:pace(Boss.SPEED * (scale or 1), Boss.WALK_SPEED)
end

--- Everyone he could go after: { p, x, y, d2 }, nearest first. `seeing`
--- keeps only those in range and in sight.
function Boss:players(server, map, seeing)
  local list = {}
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = (x - self.x) ^ 2 + (y - self.y) ^ 2
      if not seeing or (d2 <= Boss.RANGE ^ 2 and Boss.clear(map, self.x, self.y, x, y)) then
        list[#list + 1] = { p = p, x = x, y = y, d2 = d2 }
      end
    end
  end
  table.sort(list, function(a, b)
    return a.d2 < b.d2
  end)
  return list
end

--- A new spot to shoot from. With somebody up on the plateau, the one
--- furthest from whoever is nearest to it; otherwise one on the lip in
--- range of somebody below, at random, or the lip spot nearest them.
function Boss:pickPerch(server, map)
  local climbers, below = {}, {}
  for _, e in ipairs(self:players(server, map, false)) do
    if e.y < map.cliffY then
      climbers[#climbers + 1] = e
    else
      below[#below + 1] = e
    end
  end
  local best, bestScore
  for _, perch in ipairs(map.perches) do
    local here = (perch.x - self.x) ^ 2 + (perch.y - self.y) ^ 2 < 60 * 60
    if not here then
      local score
      if #climbers > 0 then
        local near = math.huge
        for _, e in ipairs(climbers) do
          near = math.min(near, (perch.x - e.x) ^ 2 + (perch.y - e.y) ^ 2)
        end
        score = math.sqrt(near) + random() * 250
      elseif perch.edge then
        local near = math.huge
        for _, e in ipairs(below) do
          near = math.min(near, math.sqrt((perch.x - e.x) ^ 2 + (perch.y - e.y) ^ 2))
        end
        -- In range of somebody is what matters; after that, anywhere will do.
        score = (near <= Boss.RANGE * 0.9 and 2000 or -near) + random() * 600
      end
      if score and (not bestScore or score > bestScore) then
        best, bestScore = perch, score
      end
    end
  end
  return best
end

--- Out of sight, off to a new spot. Returns the event for the wire.
function Boss:vanish(server, map)
  self.hiddenUntil = self.time + Boss.STEALTH.seconds
  self.stealthReady = self.time + Boss.STEALTH.cooldown
  self.breath:spend(Boss.STEALTH_BREATH)
  self.aim = nil
  self.goal = self:pickPerch(server, map)
  return { "hide", self.x, self.y }
end

--- May he vanish now: his chicken back and breath for it?
function Boss:canVanish()
  return self.time >= self.stealthReady and self.breath:has(Boss.STEALTH_BREATH)
end

--- One sniper round from where he stands at `aim`, over the lip if need be.
local function fireRifle(server, map, self, aim, reach)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    local mx, my = muzzle(map, self.x, self.y, aim, reach)
    weapons:serverFireFrom(server, 0, mx, my, aim, Guns.sniper)
  end
end

local function firePistol(server, self, aim)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    aim = aim + (random() * 2 - 1) * Boss.PISTOL_SPREAD
    weapons:serverFireFrom(server, 0, self.x + math.cos(aim) * Boss.MUZZLE, self.y + math.sin(aim) * Boss.MUZZLE,
      aim, Guns.pistol)
  end
end

--- His tick. Returns what the others should hear about: a list of events,
--- { "say", index }, { "hide", x, y }, { "show", x, y }, { "aim", targetId, seconds },
--- { "aimoff" }, { "reload" }.
function Boss:update(server, dt)
  self.running = false
  local events = self:think(server, dt)
  self.breath:step(self.running, dt)
  return events
end

--- The bead he has on somebody: follow them, leading their walk, until
--- the lock; then the shot. Returns true while it goes on.
function Boss:stepAim(server, map, dt, events)
  local a = self.aim
  local p = server.players[a.target]
  local x, y
  if p and Features.visible(server, p) then
    x, y = Features.bodyPose(server, p)
  end
  if not a.locked then
    if not x or not Boss.clear(map, self.x, self.y, x, y) then
      self.aim = nil -- lost them: behind something, out of sight or gone
      events[#events + 1] = { "aimoff" }
      return false
    end
    -- How they are moving, eased, so the lead doesn't jitter.
    if a.x then
      local k = math.min(1, dt * 6)
      a.vx = a.vx + ((x - a.x) / dt - a.vx) * k
      a.vy = a.vy + ((y - a.y) / dt - a.vy) * k
    end
    a.x, a.y = x, y
  end
  a.t = a.t - dt
  if not a.locked and a.t <= Boss.LOCK then
    -- Lead them to where they will be when the round arrives, if they
    -- keep going the way they are.
    local d = math.sqrt((a.x - self.x) ^ 2 + (a.y - self.y) ^ 2)
    local ahead = a.t + d / Guns.sniper.speed
    a.aimX, a.aimY = a.x + a.vx * ahead, a.y + a.vy * ahead
    a.locked = true
  end
  local ax, ay = a.aimX or a.x, a.aimY or a.y
  self.facing = math.atan2(ay - self.y, ax - self.x)
  if a.t <= 0 then
    local reach = math.sqrt((ax - self.x) ^ 2 + (ay - self.y) ^ 2)
    fireRifle(server, map, self, self.facing, reach)
    self.aim = nil
    self.rounds = self.rounds - 1
    self.boltIn = Boss.BOLT
    if self.rounds <= 0 then
      self.reloadIn = Boss.RELOAD
      events[#events + 1] = { "reload" }
    end
    return false
  end
  return true
end

--- What he does this tick (see `update`).
function Boss:think(server, dt)
  local events = {}
  local map = cliffMap()
  self.time = self.time + dt
  if not map then
    return events
  end
  if self.time - dt < self.hiddenUntil and not self:hidden() then
    events[#events + 1] = { "show", self.x, self.y }
  end
  if not self:hidden() then
    self.sayIn = self.sayIn - dt
    if self.sayIn <= 0 then
      self.sayIn = Boss.SAY_EVERY[1] + random() * (Boss.SAY_EVERY[2] - Boss.SAY_EVERY[1])
      events[#events + 1] = { "say", random(#Boss.lines) }
    end
  end
  self.boltIn = math.max(0, self.boltIn - dt)
  self.pistolIn = math.max(0, self.pistolIn - dt)
  if self.reloadIn > 0 then
    self.reloadIn = self.reloadIn - dt
    if self.reloadIn <= 0 then
      self.rounds = Boss.MAGAZINE
    end
  end
  if self.frozen > 0 then
    self.frozen = self.frozen - dt
    return events
  end
  if self.panic then
    self.panic.left = self.panic.left - dt
    self.facing = math.atan2(self.y - self.panic.y, self.x - self.panic.x)
    self:walk(self.facing, self:pace(1.3), dt)
    self.running = not self.breath:winded()
    if self.panic.left <= 0 then
      self.panic = nil
    end
    return events
  end

  -- Hidden: on his way to the new spot, and nothing else.
  if self:hidden() then
    local g = self.goal
    if g and (g.x - self.x) ^ 2 + (g.y - self.y) ^ 2 > 16 * 16 then
      self.facing = math.atan2(g.y - self.y, g.x - self.x)
      self:walk(self.facing, self:pace(), dt)
      self.running = not self.breath:winded()
    end
    return events
  end

  -- Too close for comfort: gone if he can be, the pistol if not.
  local all = self:players(server, map, false)
  local near = all[1]
  if near and near.d2 < Boss.EVADE ^ 2 then
    if self:canVanish() then
      if self.aim then
        events[#events + 1] = { "aimoff" }
      end
      events[#events + 1] = self:vanish(server, map)
      return events
    end
    local toward = math.atan2(near.y - self.y, near.x - self.x)
    self:walk(toward + math.pi, self:pace(0.8), dt)
    self.running = not self.breath:winded()
    if self.aim then
      self.aim = nil
      events[#events + 1] = { "aimoff" }
    end
    self.facing = toward
    if self.pistolIn <= 0 and Boss.clear(map, self.x, self.y, near.x, near.y) then
      self.pistolIn = Boss.PISTOL_EVERY
      firePistol(server, self, toward)
    end
    return events
  end

  -- Back where everyone can see him: gone again as soon as he can be,
  -- unless he is about to take a shot.
  if not self.aim and self:canVanish() then
    events[#events + 1] = self:vanish(server, map)
    return events
  end

  if self.aim then
    self:stepAim(server, map, dt, events)
    return events
  end
  if self.boltIn > 0 or self.reloadIn > 0 then
    return events
  end
  local seen = self:players(server, map, true)[1]
  if seen then
    self.aim = { target = seen.p.id, t = Boss.WARN, vx = 0, vy = 0 }
    self.facing = math.atan2(seen.y - self.y, seen.x - self.x)
    events[#events + 1] = { "aim", seen.p.id, Boss.WARN }
  elseif near then
    -- Nobody in sight: along the lip towards the nearest of them.
    local tx = math.max(map.ramp.x1 + 80, math.min(map.left + map.w - 80, near.x))
    local ty = near.y < map.cliffY and near.y or map.cliffY - 60
    if (tx - self.x) ^ 2 + (ty - self.y) ^ 2 > 40 * 40 then
      self.facing = math.atan2(ty - self.y, tx - self.x)
      self:walk(self.facing, self:pace(0.5), dt)
    end
  end
  return events
end

--- Is (x, y) within `radius` of him?
function Boss:hitBy(x, y, radius)
  return (self.x - x) ^ 2 + (self.y - y) ^ 2 < (radius + Boss.RADIUS) ^ 2
end

return Boss
