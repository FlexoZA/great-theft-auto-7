-- Foreman BIG-B055's brain (FMN), on the host: the Assembly Line's boss
-- (docs/borderline.md, "The bosses"), the badass hauler that runs the
-- line, bigger still, gold trim, a hard hat welded on. It is one of the
-- army's (army.lua runs it with the rest, so the drones on its floor tend
-- it and rounds reach it the same way), but a boss by the standard
-- (bosses/init.lua): breath, the boss bar, medkits, dodging abilities,
-- walking without getting stuck (boss_kit.lua). Waking it, the haulers the
-- crane drops for it and the shipping bay it holds shut are foreman.lua's;
-- how it looks foreman_look.lua's (the haulers' body, hauler_look.lua's FMN).
--
-- Until somebody comes up onto its floor it stands over the line, looking
-- down at it (`dormant`): a hit wakes it too.
--
-- Awake, every badass move, each with a tell:
--
--   cannons  bursts of shells from its arms, each a small blast
--   pods     a rocket hauler's volley (rpg_brain.lua's) onto red rings
--   stomp    whoever is close: it rears up (STOMP.windUp) and stamps,
--            knocking everyone round it flat (`impact`)
--   call     every CALL.every it blows its whistle and the line's crane
--            brings it another hauler (foreman.lua drops it)
--
-- At half its health (RIP) it tears one cannon off and throws it aside,
-- and from then on it charges too:
--
--   charge   at whoever is a fair way off: a lane lights up from it to
--            them (CHARGE.windUp), then it runs straight down it, flattening
--            whoever is in the way (`impact`, thrown). Run into a wall
--            and it is stunned a moment (CHARGE.stun): shoot it then
--
-- A freeze holds it (chassis.lua). Its breath (bosses/stamina.lua): walking
-- after you spends it, a volley or a charge needs some and costs it; winded
-- it walks, no volleys, no charges. The cannons, the stomp and the whistle
-- are free. What the others should see it puts on `s.events` for
-- foreman.lua to send.

local Chassis = require("src.features.borderline.chassis")
local Kit = require("src.features.borderline.boss_kit")
local Rpg = require("src.features.borderline.rpg_brain")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Walk = require("src.features.bosses.walk")

local Brain = {}

Brain.LEGS = false -- no torso crawl: it goes down whole
Brain.BOSS = true -- army.lua: its kill is a boss's
Brain.RADIUS = 30

Brain.HEALTH = 4000 -- for one player (more humans, more: bosses/init.lua); its floor's medic drone heals it on top
Brain.CONF = {
  health = Brain.HEALTH, -- (foreman.lua sets its real health as it stands its post)
  speed = 80, -- px/s
  walk = 45, -- px/s winded
  range = 800, -- px it sees
  aim = 0.5, -- its cannons lining up
  burst = 4,
  every = 0.18,
  pause = { 1.2, 1.8 },
  -- Its pods (rpg_brain.lua's volley).
  volleyEvery = { 9, 12 },
  windUp = 0.9,
  volley = 7,
  volleySpread = 130,
  volleyRadius = 80,
  volleyDamage = 28,
  volleyDelay = 1.1,
  volleyStagger = 0.12,
  volleyCost = 16,
}
-- One cannon left (RIP): half the burst.
Brain.RIPPED = setmetatable({ burst = 2 }, { __index = Brain.CONF })
Brain.WINDED = setmetatable({ speed = Brain.CONF.walk }, { __index = Brain.CONF })

Brain.KEEP = 260 -- px it likes to be from whoever it fights
Brain.BREATH = { drain = 8, regen = 13, recovered = 50, breath = 40 }
Brain.STOMP = { reach = 140, damage = 30, shove = 220, windUp = 0.55, every = 4 }
Brain.CALL = { every = 14, everyRipped = 10 } -- seconds between whistles
Brain.RIP = 0.5 -- of its health, where it tears a cannon off
-- At whoever is `min` px off or more, every `every` seconds: a lane `width`
-- across up to `max` long, lit `windUp` seconds, run at `speed`.
Brain.CHARGE = { min = 220, max = 650, every = { 6, 8 }, windUp = 0.8, speed = 520, width = 70, damage = 35,
  shove = 300, stun = 1.6, recover = 0.6, cost = 25 }

local random = love.math.random
local step, walkTo = Kit.step, Kit.walkTo

function Brain.gun()
  return Chassis.gun("FMN", "rocket", {
    speed = 640, ttl = 1.1, blast = { radius = 50, damage = 16, soft = 0 },
  })
end

function Brain.init(s)
  s.breath, s.events = Stamina.new(Brain.BREATH), {}
  s.volleyIn = Chassis.between(Brain.CONF.volleyEvery) * 0.6
  s.stompIn, s.callIn, s.chargeIn = 0, Brain.CALL.every * 0.4, Chassis.between(Brain.CHARGE.every) * 0.5
  s.power = Bosses.power()
  s.dormant = true
end

--- Woken: by somebody on its floor (foreman.lua), a hit, or the army's call.
function Brain.wake(s, x, y)
  s.dormant = nil
  Chassis.wake(s, x, y)
end

function Brain.hurt(_roster, s)
  s.dormant = nil
end

--- Gone (army.lua's `down`): foreman.lua reads it.
function Brain.gone(s)
  s.dead = true
end

--- A move under way (its tell, then what it does). Returns true while one is.
local function moving(server, s, dt)
  if not s.move then
    return false
  end
  s.moveT = s.moveT + dt
  local S, C = Brain.STOMP, Brain.CHARGE
  if s.move == "stomp" then
    if s.moveT >= S.windUp then
      Chassis.slam(server, s.x, s.y, S.reach, S.damage * s.power, S.shove)
      s.events[#s.events + 1] = { "stomp", s.x, s.y, S.reach }
      s.move, s.charging, s.stompIn = nil, nil, S.every
    end
  elseif s.move == "volley" then
    if s.moveT >= s.conf.windUp then
      Rpg.volley(server, s, s.lastX, s.lastY, s.conf)
      s.move, s.charging = nil, nil
      s.volleyIn = Chassis.between(s.conf.volleyEvery)
    end
  elseif s.move == "lane" then
    if s.moveT >= C.windUp then
      s.move, s.moveT, s.hit = "dash", 0, {}
      s.dashFrom = { x = s.x, y = s.y }
    end
  elseif s.move == "dash" then -- straight down the lane, through whoever is in it
    local ux, uy = math.cos(s.laneA), math.sin(s.laneA)
    local nx, ny = s.x + ux * C.speed * dt, s.y + uy * C.speed * dt
    if not Walk.fits(Kit.blocked, nx, ny, s.radius) then -- into a wall: it reels
      s.move, s.moveT, s.charging = "stunned", 0, nil
      s.events[#s.events + 1] = { "crash", s.x + ux * s.radius, s.y + uy * s.radius }
      return true
    end
    s.x, s.y = nx, ny
    s.stride = s.stride + C.speed * dt
    for id, p in pairs(server.players) do
      if not s.hit[id] and Chassis.visible(server, p) then
        local px, py = Chassis.pose(server, p)
        if Chassis.dist2(px, py, s.x, s.y) <= (s.radius + 24) ^ 2 then
          s.hit[id] = true
          local side = (px - s.x) * -uy + (py - s.y) * ux >= 0 and 1 or -1 -- thrown out of its way
          Chassis.knock(server, p, s.laneA + side * 0.9, C.damage * s.power, C.shove)
        end
      end
    end
    if Chassis.dist2(s.x, s.y, s.dashFrom.x, s.dashFrom.y) >= s.laneLen ^ 2 then
      s.move, s.moveT, s.charging = "recover", 0, nil
    end
  elseif s.move == "stunned" then
    if s.moveT >= C.stun then
      s.move = nil
    end
  elseif s.move == "recover" then
    if s.moveT >= C.recover then
      s.move = nil
    end
  end
  return true
end

--- The lane a charge at (tx, ty) runs: straight at them, out past them a
--- little, as far as CHARGE.max.
local function lane(s, tx, ty)
  local d = math.min(Brain.CHARGE.max, math.sqrt(Chassis.dist2(s.x, s.y, tx, ty)) + 80)
  return math.atan2(ty - s.y, tx - s.x), d
end

--- A stomp, a charge or a volley at somebody it can see `d` px off, if one
--- is due. Returns true when one starts.
local function attack(s, tx, ty, d)
  local S, C = Brain.STOMP, Brain.CHARGE
  if s.stompIn <= 0 and d <= S.reach * 0.8 then
    s.move, s.moveT, s.charging = "stomp", 0, true
    return true
  end
  if s.ripped and s.chargeIn <= 0 and d >= C.min and s.breath:has(C.cost) then
    s.breath:spend(C.cost)
    s.laneA, s.laneLen = lane(s, tx, ty)
    s.facing = s.laneA
    s.move, s.moveT, s.charging = "lane", 0, true
    s.chargeIn = Chassis.between(C.every)
    s.events[#s.events + 1] = { "lane", s.x, s.y, s.laneA, s.laneLen, C.width, C.windUp }
    return true
  end
  if s.volleyIn <= 0 and s.breath:has(s.conf.volleyCost) then
    s.breath:spend(s.conf.volleyCost)
    s.move, s.moveT, s.charging, s.lastX, s.lastY = "volley", 0, true, tx, ty
    return true
  end
  return false
end

function Brain.think(roster, server, s, dt)
  s.running = false
  if s.dormant then -- overseeing the line from its floor
    s.facing = Chassis.turn(s.facing, s.watch, Chassis.TURN * 0.3, dt)
    s.breath:step(false, dt)
    return
  end
  if not s.ripped and s.hp <= s.max * Brain.RIP then
    s.ripped = true
    s.chargeIn = math.min(s.chargeIn, 2)
    s.events[#s.events + 1] = { "rip", s.x, s.y, s.facing }
  end
  s.conf = s.breath:winded() and Brain.WINDED or s.ripped and Brain.RIPPED or Brain.CONF
  s.volleyIn, s.stompIn, s.chargeIn = s.volleyIn - dt, s.stompIn - dt, s.chargeIn - dt
  s.callIn = s.callIn - dt
  if s.callIn <= 0 then -- the whistle, whatever else it is doing
    s.callIn = s.ripped and Brain.CALL.everyRipped or Brain.CALL.every
    s.events[#s.events + 1] = { "call" }
  end
  if moving(server, s, dt) then
    s.breath:step(s.move == "dash", dt)
    return
  end
  local who, tx, ty = Kit.before(roster, server, s, dt)
  if not who then
    return
  end
  local d = math.sqrt(Chassis.dist2(s.x, s.y, tx, ty))
  local toward = math.atan2(ty - s.y, tx - s.x)
  if attack(s, tx, ty, d) then
    s.breath:step(false, dt)
    return
  end
  roster:shoot(server, s, tx, ty, Brain.gun(), dt)
  if d > Brain.KEEP + 100 then
    if Kit.straight(s, tx, ty) then
      step(s, toward, s.conf.speed, dt)
    else
      walkTo(roster, s, tx, ty, s.conf.speed, dt)
    end
    s.running = true
  elseif d < Brain.KEEP - 120 then
    step(s, toward + math.pi, s.conf.speed * 0.6, dt)
  else -- strafing, now this way, now that
    s.side = s.side or 1
    if not step(s, toward + s.side * math.pi / 2, Brain.CONF.walk, dt) or random() < dt * 0.3 then
      s.side = -s.side
    end
  end
  s.breath:step(s.running and not s.breath:winded(), dt)
end

return Brain
