-- Major Looz'er, on the host: the boss on the hilltop. He is big, slow and
-- takes a great many rounds. He sees all round him (he is a major), walks
-- to within rifle range of the nearest player he can see, and fires
-- three-round bursts at them. His special is the MG nest, the same one a
-- player can buy (abilities/mgnest.lua): every so often he throws one down
-- in front of him, facing whoever he is after, and for five seconds it
-- sweeps its forty-five-degree arc with rifle fire, hurting anyone in it.
--
-- In between he never stops talking about his country. This module is the
-- man: his numbers, his lines, his body and his nests. What he does is his
-- brain's (major_brain.lua): fight, hunt, and when badly hurt break off for
-- a medkit (the bosses' standard, bosses/heal.lua). Neither owns the wire;
-- init.lua does.
--
-- Like every boss (bosses/stamina.lua) he has breath: marching after you
-- (or away from a stink) spends it, and empty he is winded, down to a
-- stroll a walking player can leave behind, with no MG nest in him until a
-- good part of it is back. His rifle costs him nothing.

local Features = require("src.features")
local Stamina = require("src.features.bosses.stamina")

local Major = {}
Major.__index = Major

local Brain -- his brain, required at the bottom: it needs Major's numbers

-- Tuning --------------------------------------------------------------------

Major.HEALTH = 2200 -- a hundred and ten pistol rounds, for one player (more humans, more: bosses/init.lua)
Major.RADIUS = 17 -- px; two soldiers across (a soldier is 8.5 each side)
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
Major.MUZZLE = 44 -- px from his middle a round leaves: the tip of the rifle he holds out
Major.NEST_EVERY = 11 -- seconds between MG nests
Major.NEST_FIRST = 4 -- seconds into the fight before the first
Major.NEST_OUT = 46 -- px in front of him it goes down
Major.SAY_EVERY = { 4, 7 } -- seconds between speeches, at random in this range
Major.DROPS = 40 -- koins he spills when he goes down

--- What he says: `Major.TALK` lines of his country, then the ones for a
--- medkit (said as he takes one).
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
Major.TALK = #Major.lines
for _, line in ipairs({
  "This isn't a medkit! It's a PATRIOT KIT!",
  "A field dressing! Like my grandfather's! He also wasn't hurt!",
  "Merely a flesh wound! On loan to the nation!",
  "Bandages are just flags for your arm!",
}) do
  Major.lines[#Major.lines + 1] = line
end

--- The MG nest ability, if the abilities feature is there to lend it.
function Major.nestKind()
  return Features.byName.abilities and require("src.features.abilities.mgnest") or nil
end

--- Him, at (x, y), with `hp` hit points (HEALTH when not given), finding
--- his way round walls on `nav` (d-day/nav.lua's walking grid) if given.
function Major.new(x, y, hp, nav)
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
    nav = nav,
    mode = "hunt", -- what his brain is doing: "fight", "hunt" or "heal"
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

--- His tick (his brain, major_brain.lua, decides). Returns what the others
--- should hear about: a list of events, { "say", index } or
--- { "nest", x, y, angle }.
function Major:update(server, dt)
  self.running = false
  local events = Brain.think(self, server, dt)
  self.breath:step(self.running, dt)
  return events
end

--- His pace: a march with breath in him, a stroll without. `scale` is on
--- the march only.
function Major:pace(scale)
  return self.breath:pace(Major.SPEED * (scale or 1), Major.WALK_SPEED)
end

--- Every nest he put down sprays its arc a round at a time, sweeping from
--- side to side the way a player's does, until it is spent.
function Major:stepNests(server)
  local Nest = Major.nestKind()
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

Brain = require("src.features.d-day.major_brain")

return Major
