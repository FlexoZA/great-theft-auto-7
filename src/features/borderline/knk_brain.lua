-- The Knuckle Scrapper's brain (KNK), on the host: the Frozen Wreck's boss
-- (docs/borderline.md, "The bosses"), a junk hauler that built itself huge
-- out of Max's wrecked train, a scrap pile with arms. The tutorial boss:
-- slow, every move it makes told well ahead. It is one of the army's
-- (army.lua runs it with the rest, so rounds reach it the same way), but a
-- boss by the standard (bosses/init.lua): breath, the boss bar, medkits,
-- dodging abilities, walking without getting stuck (boss_kit.lua). How it builds itself
-- out of the engine, and the junk haulers that climb out of the wreck to
-- feed it, are scrapper.lua's; how it looks scrapper_look.lua's.
--
-- It is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   somebody it can't see: after them on the walking grid
--          (bosses/walk.lua), wherever they are
--   fight  somebody it can see: it lumbers straight at them
--   heal   badly hurt (bosses/heal.lua): off for the nearest medkit
--
-- Its moves, each with a tell:
--
--   swing  whoever is close: it draws a fist back (SWING.windUp), then
--          sweeps it round in front of it: whoever is in the arc takes it
--          (`impact`) and is thrown. It takes a moment to come round again
--   throw  whoever is further off: it tears a lump of scrap off itself
--          and lifts it (THROW.windUp), then lobs it at where they stand,
--          a red ring marking where it comes down (`impact`, thrown)
--
-- An ability about to land on it and it walks out from under it
-- (bosses/dodge.lua). A freeze holds it (chassis.lua). Its breath
-- (bosses/stamina.lua): walking after you spends it, a throw needs some
-- and costs it; winded it shuffles and can't throw. A swing is free (melee,
-- the standard). What the others should see (a fist drawn back, a lump
-- lifted, the swing, the lump let go) it puts on `s.events` for
-- scrapper.lua to send.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Kit = require("src.features.borderline.boss_kit")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")

local Brain = {}

Brain.LEGS = false -- no torso crawl: it falls apart whole
Brain.BOSS = true -- army.lua: its kill is a boss's
Brain.RADIUS = 56 -- (its look is drawn to match: scrapper_look.lua's SCALE)

Brain.HEALTH = 1500 -- for one player (more humans, more: bosses/init.lua); the junk it eats heals it on top
Brain.CONF = {
  health = Brain.HEALTH, -- (scrapper.lua sets its real health as it stands up)
  speed = 60, -- px/s lumbering after you
  walk = 35, -- px/s winded
  range = 800, -- px it sees
}
Brain.WINDED = setmetatable({ speed = Brain.CONF.walk }, { __index = Brain.CONF })

Brain.BREATH = { drain = 7, regen = 12, recovered = 50, breath = 40 }
-- `reach` px in front it swings at (from its middle), `half` radians either
-- side of where it faces.
Brain.SWING = { reach = 150, half = 1.1, windUp = 0.75, damage = 25, shove = 260, recover = 0.7 }
-- At whoever is `min` px or more off, every `every` seconds: a lump `radius`
-- px across where it lands, `flight` seconds after it lets go.
Brain.THROW = { min = 220, max = 700, every = { 4, 6 }, windUp = 0.9, flight = 1.1, radius = 75, damage = 30,
  shove = 160, recover = 0.5, cost = 18 }

local random = love.math.random

function Brain.init(s)
  s.breath, s.events = Stamina.new(Brain.BREATH), {}
  s.throwIn = Chassis.between(Brain.THROW.every) * 0.5
  s.power = Bosses.power()
end

Brain.wake = Chassis.wake

--- Gone (army.lua's `down`): scrapper.lua reads it.
function Brain.gone(s)
  s.dead = true
end

local step, walkTo = Kit.step, Kit.walkTo

--- A move under way (its tell, then what it does). Returns true while one is.
local function moving(server, s, dt)
  if not s.move then
    return false
  end
  s.moveT = s.moveT + dt
  local W, T = Brain.SWING, Brain.THROW
  if s.move == "swing" then
    if s.moveT >= W.windUp then
      Chassis.slam(server, s.x, s.y, W.reach, W.damage * s.power, W.shove, s.facing, W.half)
      s.events[#s.events + 1] = { "swing", s.x, s.y, s.facing, W.reach }
      s.move, s.moveT, s.charging = "recover", 0, nil
      s.recoverFor = W.recover
    end
  elseif s.move == "throw" then
    local p = s.aimAt and server.players[s.aimAt]
    if p and Features.visible(server, p) then -- it follows them with the lump up
      s.lastX, s.lastY = Features.bodyPose(server, p)
      s.facing = Chassis.turn(s.facing, math.atan2(s.lastY - s.y, s.lastX - s.x), Chassis.TURN, dt)
    end
    if s.moveT >= T.windUp then
      s.events[#s.events + 1] = { "throw", s.x, s.y, s.lastX, s.lastY, T.radius, T.flight, T.damage * s.power,
        T.shove }
      s.move, s.moveT, s.charging = "recover", 0, nil
      s.recoverFor = T.recover
      s.throwIn = Chassis.between(T.every)
    end
  elseif s.move == "recover" then
    if s.moveT >= s.recoverFor then
      s.move = nil
    end
  end
  return true
end

--- A swing or a throw at somebody it can see `d` px off, if one is due.
--- Returns true when one starts.
local function attack(s, who, tx, ty, d)
  local W, T = Brain.SWING, Brain.THROW
  local toward = math.atan2(ty - s.y, tx - s.x)
  if d <= W.reach and math.abs(Chassis.turnBetween(s.facing, toward)) < W.half then
    s.move, s.moveT, s.charging = "swing", 0, true
    s.events[#s.events + 1] = { "draw", W.windUp } -- its fist going back: every screen shows the tell
    return true
  end
  if s.throwIn <= 0 and d >= T.min and d <= T.max and s.breath:has(T.cost) then
    s.breath:spend(T.cost)
    s.move, s.moveT, s.charging = "throw", 0, true
    s.aimAt, s.lastX, s.lastY = who, tx, ty
    s.events[#s.events + 1] = { "lift", T.windUp } -- the lump coming up over its head
    return true
  end
  return false
end

function Brain.think(roster, server, s, dt)
  s.running = false
  s.conf = s.breath:winded() and Brain.WINDED or Brain.CONF
  s.throwIn = s.throwIn - dt
  if moving(server, s, dt) then
    s.breath:step(false, dt)
    return
  end
  local who, tx, ty = Kit.before(roster, server, s, dt)
  if not who then
    return
  end
  local d = math.sqrt(Chassis.dist2(s.x, s.y, tx, ty))
  local toward = math.atan2(ty - s.y, tx - s.x)
  s.facing = Chassis.turn(s.facing, toward, Chassis.TURN * 0.6, dt) -- heavy: it comes round slowly
  if attack(s, who, tx, ty, d) then
    s.breath:step(false, dt)
    return
  end
  if d > Brain.SWING.reach * 0.7 then -- straight at them, round whatever's in the way
    if Kit.straight(s, tx, ty) then
      step(s, toward, s.conf.speed, dt)
    else
      walkTo(roster, s, tx, ty, s.conf.speed, dt)
    end
    s.running = true
  elseif random() < dt then -- close, waiting to come round: a shuffle
    step(s, toward + (random() - 0.5) * 2, Brain.CONF.walk, dt)
  end
  s.breath:step(s.running and not s.breath:winded(), dt)
end

return Brain
