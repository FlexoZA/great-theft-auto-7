-- Major Looz'er, on the host: the boss on the hilltop. He is big, slow and
-- takes a great many rounds. He sees all round him (he is a major), walks
-- to within rifle range of the nearest player he can see, and fires
-- three-round bursts at them. His special is the MG nest, the same one a
-- player can buy (abilities/mgnest.lua): every so often he throws one down
-- in front of him, facing whoever he is after, and for five seconds it
-- sweeps its forty-five-degree arc with rifle fire, hurting anyone in it.
--
-- In between he never stops talking about his country. This module only
-- thinks and hands back what happened; init.lua owns the wire.
--
-- Like every boss (bosses/stamina.lua) he has breath: marching after you
-- (or away from a stink) spends it, and empty he is winded, down to a
-- stroll a walking player can leave behind, with no MG nest in him until a
-- good part of it is back. His rifle costs him nothing.

local Features = require("src.features")
local Sight = require("src.features.d-day.sight")
local Stamina = require("src.features.bosses.stamina")

local Major = {}
Major.__index = Major

-- Tuning --------------------------------------------------------------------

Major.HEALTH = 2200 -- a hundred and ten pistol rounds, for one player (more humans, more: bosses/init.lua)
Major.RADIUS = 13 -- px
Major.SPEED = 72 -- px/s; a march, not a run
Major.WALK_SPEED = 40 -- px/s winded: a stroll, and a walk (45) leaves him behind
Major.BREATH = { -- his stamina (bosses/stamina.lua has the rule and the defaults)
  drain = 12, -- per second marching (~8 s of it)
  regen = 14,
  recovered = 50, -- back before a winded Major marches again
  breath = 50, -- in him before he throws a nest down
}
Major.NEST_STAMINA = 25 -- what an MG nest costs him
Major.RANGE = 760 -- px he sees (all the way round)
Major.KEEP = 260 -- px he likes to keep between himself and his target
Major.BURST = 3 -- rounds in a burst
Major.BURST_GAP = 0.12 -- seconds between rounds in a burst
Major.BURST_EVERY = 2.0 -- seconds from one burst to the next
Major.SPREAD = 0.08
Major.MUZZLE = 18
Major.NEST_EVERY = 11 -- seconds between MG nests
Major.NEST_FIRST = 4 -- seconds into the fight before the first
Major.NEST_OUT = 46 -- px in front of him it goes down
Major.SAY_EVERY = { 4, 7 } -- seconds between speeches, at random in this range
Major.DROPS = 40 -- koins he spills when he goes down

Major.lines = {
  "Freedom isn't free! It's nineteen ninety-nine a month and you WILL subscribe!",
  "I love this country so much I married a map of it!",
  "Every grain of sand on that beach is a patriot! Except that one. I'm watching it.",
  "Salute the flag! Salute it HARDER! With your FEELINGS!",
  "My grandfather defended this hill! From what? Doesn't matter! PATRIOTISM!",
  "I pledge allegiance to the hill, and to the flag on the hill, and to me, on the hill!",
  "In my day we didn't have enemies! We had to shout at the sea!",
  "This moustache has been saluted by four admirals and a very confused goose!",
  "Stand up straight! The anthem can SEE you!",
  "Look at my medals! LOOK AT THEM! Three of them are for looking at medals!",
  "Retreat is just advancing in a direction I haven't approved yet!",
  "I don't sleep. I stand to attention with my eyes closed!",
  "This flag was hand-stitched by eagles! Bald ones! They were very embarrassed about it!",
  "The only thing we have to fear is not saluting enough!",
}

local random = love.math.random

--- The MG nest ability, if the abilities feature is there to lend it.
local function nestKind()
  return Features.byName.abilities and require("src.features.abilities.mgnest") or nil
end

--- Him, at (x, y), with `hp` hit points (HEALTH when not given).
function Major.new(x, y, hp)
  hp = hp or Major.HEALTH
  return setmetatable({
    x = x,
    y = y,
    facing = math.pi / 2,
    hp = hp,
    max = hp,
    burstLeft = 0,
    burstIn = 1,
    nestIn = Major.NEST_FIRST,
    sayIn = 1,
    frozen = 0,
    panic = nil,
    stuck = 0,
    sidestep = 0,
    side = 1,
    nests = {}, -- { x, y, angle, placedAt, untilT, nextShot }
    time = 0,
    breath = Stamina.new(Major.BREATH), -- winded, he strolls and throws no nest
    running = false, -- at full tilt this tick, for his breath
  }, Major)
end

local function blockedAt(x, y)
  local r = Major.RADIUS
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

function Major:walk(angle, speed, dt)
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
      self.stuck, self.sidestep, self.side = 0, 0.7, -self.side
    end
  else
    self.stuck = 0
  end
end

--- The nearest player he can see, and where they are; failing that, the
--- nearest player anywhere (he goes looking).
function Major:target(server)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for _, p in pairs(server.players) do
    if Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = (x - self.x) ^ 2 + (y - self.y) ^ 2
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = p, x, y, d2
      end
      if d2 <= Major.RANGE ^ 2 and (not seenD2 or d2 < seenD2) and Sight.clear(self.x, self.y, x, y) then
        seen, sx, sy, seenD2 = p, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

--- One round at `aim`, out of his rifle.
local function fire(server, x, y, aim)
  local weapons = Features.byName.weapons
  if weapons and weapons.serverFireFrom then
    aim = aim + (random() * 2 - 1) * Major.SPREAD
    weapons:serverFireFrom(server, 0, x + math.cos(aim) * Major.MUZZLE, y + math.sin(aim) * Major.MUZZLE, aim,
      require("src.features.weapons.guns").ak47)
  end
end

--- His tick. Returns what the others should hear about: a list of events,
--- { "say", index } or { "nest", x, y, angle }.
function Major:update(server, dt)
  self.running = false
  local events = self:think(server, dt)
  self.breath:step(self.running, dt)
  return events
end

--- His pace: a march with breath in him, a stroll without. `scale` is on
--- the march only.
function Major:pace(scale)
  return self.breath:pace(Major.SPEED * (scale or 1), Major.WALK_SPEED)
end

--- What he does this tick (see `update`).
function Major:think(server, dt)
  local events = {}
  self.time = self.time + dt
  self:stepNests(server)
  self.sayIn = self.sayIn - dt
  if self.sayIn <= 0 then
    self.sayIn = Major.SAY_EVERY[1] + random() * (Major.SAY_EVERY[2] - Major.SAY_EVERY[1])
    events[#events + 1] = { "say", random(#Major.lines) }
  end
  if self.frozen > 0 then
    self.frozen = self.frozen - dt
    return events
  end
  if self.panic then
    self.panic.left = self.panic.left - dt
    self.facing = math.atan2(self.y - self.panic.y, self.x - self.panic.x)
    self:walk(self.facing, self:pace(1.8), dt)
    self.running = not self.breath:winded()
    if self.panic.left <= 0 then
      self.panic = nil
    end
    return events
  end

  local target, tx, ty, visible = self:target(server)
  if not target then
    return events
  end
  local toward = math.atan2(ty - self.y, tx - self.x)
  local d = math.sqrt((tx - self.x) ^ 2 + (ty - self.y) ^ 2)
  self.facing = toward
  if not visible or d > Major.KEEP + 40 then
    self:walk(toward, self:pace(), dt)
    self.running = not self.breath:winded()
  elseif d < Major.KEEP - 80 then
    self:walk(toward + math.pi, self:pace(0.7), dt) -- backs off, still facing them
    self.running = not self.breath:winded()
  end
  if not visible then
    self.burstLeft = 0
    return events
  end

  self.burstIn = self.burstIn - dt
  if self.burstIn <= 0 then
    if self.burstLeft <= 0 then
      self.burstLeft = Major.BURST
    end
    fire(server, self.x, self.y, toward)
    self.burstLeft = self.burstLeft - 1
    self.burstIn = self.burstLeft > 0 and Major.BURST_GAP or Major.BURST_EVERY
  end

  self.nestIn = self.nestIn - dt
  local Nest = nestKind()
  -- A nest takes breath: none while he is winded or nearly so (the timer
  -- stays run down, so it comes as soon as he has it back).
  if Nest and self.nestIn <= 0 and self.breath:has(Major.NEST_STAMINA) then
    self.nestIn = Major.NEST_EVERY
    self.breath:spend(Major.NEST_STAMINA)
    local nx, ny = self.x + math.cos(toward) * Major.NEST_OUT, self.y + math.sin(toward) * Major.NEST_OUT
    local out = Major.NEST_OUT
    while out > 0 and Features.any("blocksPoint", nx, ny) do
      out = math.max(0, out - 8) -- not inside a wall: pulled back towards him
      nx, ny = self.x + math.cos(toward) * out, self.y + math.sin(toward) * out
    end
    self.nests[#self.nests + 1] = {
      x = nx, y = ny, angle = toward, placedAt = self.time, untilT = self.time + Nest.seconds, nextShot = self.time,
    }
    events[#events + 1] = { "nest", nx, ny, toward }
  end
  return events
end

--- Every nest he put down sprays its arc a round at a time, sweeping from
--- side to side the way a player's does, until it is spent.
function Major:stepNests(server)
  local Nest = nestKind()
  local weapons = Features.byName.weapons
  local now = self.time
  for i = #self.nests, 1, -1 do
    local nest = self.nests[i]
    if not (Nest and weapons) or now >= nest.untilT then
      table.remove(self.nests, i)
    else
      while now >= nest.nextShot do
        local t = nest.nextShot - nest.placedAt
        local aim = nest.angle + (Nest.arc / 2) * 0.9 * math.sin(2 * math.pi * t / Nest.sweep)
        local mx, my = nest.x + math.cos(aim) * Nest.barrel, nest.y + math.sin(aim) * Nest.barrel
        weapons:serverFireFrom(server, 0, mx, my, aim, Nest.gun)
        nest.nextShot = nest.nextShot + Nest.fireEvery
      end
    end
  end
end

--- Is (x, y) within `radius` of him?
function Major:hitBy(x, y, radius)
  return (self.x - x) ^ 2 + (self.y - y) ^ 2 < (radius + Major.RADIUS) ^ 2
end

return Major
