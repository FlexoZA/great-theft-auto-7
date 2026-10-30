-- The Smelter's brain (SML), on the host: the Refinery's boss (docs/
-- borderline.md, "The bosses"), a squat plasma furnace on four legs with
-- molten Bragium in its belly. It is one of the army's (army.lua runs it
-- with the rest, so rounds reach it the same way), but a boss by the
-- standard (bosses/init.lua): breath, the boss bar, medkits, dodging
-- abilities, walking without getting stuck (boss_kit.lua). How it hauls
-- itself out of the casting pit, and the freight door it holds shut, are
-- smelter.lua's; how it looks smelter_look.lua's.
--
-- It is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   somebody it can't see: after them on the walking grid
--   fight  somebody it can see: it keeps about KEEP off, edging round them
--   heal   badly hurt (bosses/heal.lua): off for the nearest medkit
--
-- Its moves, each with a tell:
--
--   shot   its coils glow (SHOT.aim), then one plasma bolt at you
--          (bolts.lua: big and slow, splashing where it lands)
--   gush   its belly door opens and a lane lights up in front of it
--          (GUSH.windUp), then molten Bragium pours down that lane for
--          GUSH.pour seconds: whoever is in it burns (`plasma`), and it
--          leaves puddles burning all along it (puddles.lua)
--   vent   after every VENT.after moves it has to vent: it stands still,
--          its belly glowing open, for VENT.time seconds, and every hit
--          on it does VENT.taken times the damage (`taken`)
--
-- An ability about to land on it and it walks out from under it
-- (bosses/dodge.lua). A freeze holds it (chassis.lua). Its breath
-- (bosses/stamina.lua): walking after you spends it, a gush needs some and
-- costs it; winded it shuffles and can't gush. A shot is free. What the
-- others should see (the lane lit, the pour, the vent) it puts on
-- `s.events` for smelter.lua to send.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Kit = require("src.features.borderline.boss_kit")
local Bolts = require("src.features.borderline.bolts")
local Puddles = require("src.features.borderline.puddles")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")

local Brain = {}

Brain.LEGS = false -- no torso crawl: it goes out whole
Brain.BOSS = true -- army.lua: its kill is a boss's
Brain.RADIUS = 50 -- (its look is drawn to match: smelter_look.lua's SCALE)

Brain.HEALTH = 3500 -- for one player (more humans, more: bosses/init.lua)
Brain.CONF = {
  health = Brain.HEALTH, -- (smelter.lua sets its real health as it climbs out)
  speed = 50, -- px/s, a furnace on legs
  walk = 30, -- px/s winded
  range = 850, -- px it sees
}
Brain.WINDED = setmetatable({ speed = Brain.CONF.walk }, { __index = Brain.CONF })

Brain.KEEP = 280 -- px it likes to be from whoever it fights
Brain.BREATH = { drain = 6, regen = 12, recovered = 50, breath = 40 }
Brain.SHOT = { every = { 1.6, 2.3 }, aim = 0.6 }
Brain.BOLT = { speed = 320, ttl = 2.4, damage = 18, splash = 40 } -- (bolts.lua's kind)
-- A lane `length` px long and `width` px across in front of it, lit for
-- `windUp` seconds, then poured into for `pour` seconds at `dps` plasma a
-- second, its puddles `puddle` px round burning `burn` seconds.
Brain.GUSH = { every = { 7, 9 }, windUp = 1.0, pour = 2.2, length = 520, width = 80, dps = 40, puddle = 44,
  burn = 5, puddleEvery = 0.22, cost = 20 }
Brain.VENT = { after = 3, time = 3, taken = 2 }

local random = love.math.random
local step, walkTo = Kit.step, Kit.walkTo

function Brain.init(s)
  s.breath, s.events = Stamina.new(Brain.BREATH), {}
  s.shotIn, s.gushIn = Chassis.between(Brain.SHOT.every), Chassis.between(Brain.GUSH.every) * 0.6
  s.moves = 0
  s.power = Bosses.power()
end

Brain.wake = Chassis.wake

--- Gone (army.lua's `down`): smelter.lua reads it.
function Brain.gone(s)
  s.dead = true
end

--- What a hit on it is worth: double while it vents (chassis.lua's hurt).
function Brain.taken(s)
  return s.venting and Brain.VENT.taken or 1
end

--- Where its spout is: at its front, out along `angle`.
local function spout(s, angle)
  return s.x + math.cos(angle) * s.radius * 0.9, s.y + math.sin(angle) * s.radius * 0.9
end

--- Is (px, py) in the lane from (x, y) along `angle`, `length` long and
--- `width` across (`reach` of it poured so far)?
local function inLane(px, py, x, y, angle, reach, width)
  local ux, uy = math.cos(angle), math.sin(angle)
  local along = (px - x) * ux + (py - y) * uy
  local across = math.abs(-(px - x) * uy + (py - y) * ux)
  return along >= -10 and along <= reach and across <= width / 2 + 8
end

--- The pour, a tick of it: whoever is in the lane burns, and the puddles
--- spread down it as the front gets further.
local function pour(server, s, dt)
  local G = Brain.GUSH
  local reach = G.length * math.min(1, s.moveT / 0.5) -- it takes half a second to run the lane's length
  s.burnIn = (s.burnIn or 0) - dt
  if s.burnIn <= 0 then
    s.burnIn = 0.25
    local weapons = Features.byName.weapons
    for _, p in pairs(server.players) do
      if weapons and weapons.serverDamage and Features.visible(server, p) and not p.vehicle then
        local px, py = Features.bodyPose(server, p)
        if inLane(px, py, s.laneX, s.laneY, s.laneA, reach, G.width) then
          weapons:serverDamage(server, p, nil, math.floor(G.dps * 0.25 * s.power + 0.5), s.laneA, "plasma")
        end
      end
    end
  end
  s.puddleIn = (s.puddleIn or 0) - dt
  if s.puddleIn <= 0 then
    s.puddleIn = G.puddleEvery
    local d = reach * (0.15 + 0.85 * random())
    local off = (random() - 0.5) * G.width * 0.5
    local ux, uy = math.cos(s.laneA), math.sin(s.laneA)
    local x, y = s.laneX + ux * d - uy * off, s.laneY + uy * d + ux * off
    if not Chassis.blocked(x, y) then
      Puddles.serverPour(server, x, y, G.puddle * (0.8 + 0.4 * random()), G.burn, G.dps * 0.5 * s.power)
    end
  end
end

--- One move done: after every VENT.after of them, it vents.
local function moved(s)
  s.moves = s.moves + 1
  if s.moves >= Brain.VENT.after then
    s.moves = 0
    s.move, s.moveT, s.venting = "vent", 0, true
    s.events[#s.events + 1] = { "vent", Brain.VENT.time }
  else
    s.move = nil
  end
end

--- A move under way (its tell, then what it does). Returns true while one is.
local function moving(server, s, dt)
  if not s.move then
    return false
  end
  s.moveT = s.moveT + dt
  local S, G = Brain.SHOT, Brain.GUSH
  if s.move == "shot" then
    local p = s.aimAt and server.players[s.aimAt]
    if p and Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      s.facing = Chassis.turn(s.facing, math.atan2(y - s.y, x - s.x), Chassis.TURN, dt)
    end
    if s.moveT >= S.aim then
      local x, y = spout(s, s.facing)
      Bolts.serverFire(server, x, y, s.facing, Brain.BOLT)
      s.charging = nil
      s.shotIn = Chassis.between(S.every)
      moved(s)
    end
  elseif s.move == "aim" then -- the lane lit, it lines up on them, then sets
    local p = s.aimAt and server.players[s.aimAt]
    if p and Features.visible(server, p) and s.moveT < G.windUp * 0.6 then
      local x, y = Features.bodyPose(server, p)
      s.facing = Chassis.turn(s.facing, math.atan2(y - s.y, x - s.x), Chassis.TURN * 0.5, dt)
    end
    if s.moveT >= G.windUp then
      s.laneA = s.facing
      s.laneX, s.laneY = spout(s, s.laneA)
      s.move, s.moveT = "pour", 0
      s.events[#s.events + 1] = { "gush", s.laneX, s.laneY, s.laneA, G.length, G.width, G.pour }
    end
  elseif s.move == "pour" then
    pour(server, s, dt)
    if s.moveT >= G.pour then
      s.charging = nil
      s.gushIn = Chassis.between(G.every)
      moved(s)
    end
  elseif s.move == "vent" then
    if s.moveT >= Brain.VENT.time then
      s.move, s.venting = nil, nil
    end
  end
  return true
end

--- A gush or a shot at somebody it can see `d` px off, if one is due.
--- Returns true when one starts.
local function attack(s, who, d)
  local G = Brain.GUSH
  if s.gushIn <= 0 and d <= G.length * 0.9 and s.breath:has(G.cost) then
    s.breath:spend(G.cost)
    s.move, s.moveT, s.charging, s.aimAt = "aim", 0, true, who
    local x, y = spout(s, s.facing)
    s.events[#s.events + 1] = { "aim", x, y, s.facing, G.length, G.width, G.windUp }
    return true
  end
  if s.shotIn <= 0 then
    s.move, s.moveT, s.charging, s.aimAt = "shot", 0, true, who
    return true
  end
  return false
end

function Brain.think(roster, server, s, dt)
  s.running = false
  s.conf = s.breath:winded() and Brain.WINDED or Brain.CONF
  s.shotIn, s.gushIn = s.shotIn - dt, s.gushIn - dt
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
  s.facing = Chassis.turn(s.facing, toward, Chassis.TURN * 0.6, dt)
  if attack(s, who, d) then
    s.breath:step(false, dt)
    return
  end
  if d > Brain.KEEP + 100 then
    if Kit.straight(s, tx, ty) then
      step(s, toward, s.conf.speed, dt)
    else
      walkTo(roster, s, tx, ty, s.conf.speed, dt)
    end
    s.running = true
  elseif d < Brain.KEEP - 100 then
    step(s, toward + math.pi, s.conf.speed * 0.6, dt)
  else -- edging round them, now this way, now that
    s.side = s.side or 1
    if not step(s, toward + s.side * math.pi / 2, Brain.CONF.walk, dt) or random() < dt * 0.25 then
      s.side = -s.side
    end
  end
  s.breath:step(s.running and not s.breath:winded(), dt)
end

return Brain
