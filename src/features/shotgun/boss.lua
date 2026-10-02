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
-- winded, he walks, and stays where everyone can see him.
--
-- This module is the man: his numbers, his lines, his eyes and his legs.
-- What he does is his brain's (brain.lua), which also sends him, badly
-- hurt, after a medkit, out of sight if he can manage it (the bosses'
-- standard, bosses/heal.lua). init.lua owns the wire.

local Features = require("src.features")
local Layout = require("src.features.city-map.layout")
local Stamina = require("src.features.bosses.stamina")
local Chicken = require("src.features.abilities.chicken")

local Boss = {}
Boss.__index = Boss

local Brain -- his brain, required at the bottom: it reads his numbers off him

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

--- What he says: `Boss.TALK` lines about debating, then the ones for a
--- medkit.
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
Boss.TALK = #Boss.lines
for _, line in ipairs({
  "A medkit. No, I will NOT be discussing my injuries.",
  "Patched up. That's not a concession, that's maintenance!",
  "You shot me? That's a debate tactic! Disqualified!",
}) do
  Boss.lines[#Boss.lines + 1] = line
end

--- The map in play, if it is the bluff.
function Boss.cliffMap()
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
function Boss.muzzle(map, x, y, aim, reach)
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

--- Him, at (x, y), with `hp` hit points (HEALTH when not given), finding
--- his way round the bluff on `nav` (d-day/nav.lua's walking grid) if given.
function Boss.new(x, y, hp, nav)
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
    nav = nav,
    mode = "hide", -- what his brain is doing (brain.lua)
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

--- His tick (his brain, brain.lua, decides). Returns what the others should
--- hear about: a list of events, { "say", index }, { "hide", x, y },
--- { "show", x, y }, { "aim", targetId, seconds }, { "aimoff" }, { "reload" }.
function Boss:update(server, dt)
  self.running = false
  local events = Brain.think(self, server, dt)
  self.breath:step(self.running, dt)
  return events
end

--- May he vanish now: his chicken back and breath for it?
function Boss:canVanish()
  return self.time >= self.stealthReady and self.breath:has(Boss.STEALTH_BREATH)
end

--- Is (x, y) within `radius` of him?
function Boss:hitBy(x, y, radius)
  return (self.x - x) ^ 2 + (self.y - y) ^ 2 < (radius + Boss.RADIUS) ^ 2
end

Brain = require("src.features.shotgun.brain")

return Boss
