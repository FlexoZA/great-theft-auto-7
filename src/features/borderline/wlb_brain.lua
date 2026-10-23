-- Wilbur's brain (WLB), on the host: the Bragium Pit's boss (docs/
-- borderline.md, "The bosses"), Handsome Jerry's cyborg enforcer, more
-- machine than man. He is one of the army's (army.lua runs him with the
-- rest, so the drones tend him and rounds reach him the same way), but a
-- boss by the standard (bosses/init.lua): breath, the boss bar, medkits,
-- dodging abilities, walking without getting stuck. How he gets onto the
-- pad, the lock and the bar are wilbur.lua's; how he looks wilbur_look.lua's.
--
-- He is always in one of these, the later ones cutting in on the earlier:
--
--   hunt   somebody he can't see: after them on the walking grid
--          (bosses/walk.lua), wherever they are
--   fight  somebody he can see: he keeps about KEEP off, circling, and
--          fires his arm gun in long bursts
--   heal   badly hurt (bosses/heal.lua): off for the nearest medkit,
--          backing there at a walk and still shooting while he can see you
--
-- His moves, each with a tell:
--
--   rockets  his shoulder pod opens and glows (VOLLEY.windUp), then a
--            volley comes down on red rings round you (barrage.lua)
--   leap     at whoever is a fair way off: he crouches (LEAP.windUp, a red
--            ring where he'll land), goes up (out of reach of any round),
--            and slams down: whoever is in the ring takes it (`impact`)
--            and is thrown flat. He comes up slow (LEAP.recover)
--   drones   every DRONES.every he sends one out of his back, a shield
--            drone and a medic drone by turns (drone_brain.lua): they
--            tend him, so shoot them first. No more than DRONES.cap of his
--            own out at once
--
-- At half his health Jerry pushes an upgrade (UPGRADE): his plates glow,
-- he moves quicker, fires sooner and sends drones twice as often.
--
-- An ability about to land on him and he walks out from under it
-- (bosses/dodge.lua). A freeze holds him (chassis.lua). His breath
-- (bosses/stamina.lua): running spends it, a volley or a leap needs some
-- and costs it; winded he walks, and can't leap or fire the pod. What the
-- others should hear about (a leap's ring, the slam, the upgrade) he puts
-- on `s.events` for wilbur.lua to send.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Drone = require("src.features.borderline.drone_brain")
local Barrage = require("src.features.borderline.barrage")
local Bosses = require("src.features.bosses")
local Stamina = require("src.features.bosses.stamina")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")
local Walk = require("src.features.bosses.walk")

local Brain = {}

Brain.LEGS = false -- no torso crawl: he goes down whole
Brain.BOSS = true -- army.lua: his kill is a boss's
Brain.RADIUS = 30

Brain.HEALTH = 3000 -- for one player (more humans, more: bosses/init.lua); the drones heal him on top
Brain.CONF = {
  health = Brain.HEALTH, -- (wilbur.lua sets his real health as he lands)
  speed = 95, -- px/s at a run
  walk = 45, -- px/s winded
  range = 900, -- px he sees
  aware = 900,
  fov = 2 * math.pi + 1,
  aim = 0.5, -- his gun spinning up
  burst = 10,
  every = 0.07,
  pause = { 1.2, 1.8 },
}
-- Upgraded (UPGRADE): quicker on his feet and on the trigger.
Brain.UPGRADED = setmetatable({ speed = 125, pause = { 0.7, 1.1 } }, { __index = Brain.CONF })
Brain.WINDED = setmetatable({ speed = Brain.CONF.walk }, { __index = Brain.CONF })

Brain.KEEP = 300 -- px he likes to be from whoever he fights
Brain.BREATH = { drain = 9, regen = 13, recovered = 50, breath = 40 }
Brain.VOLLEY = { every = { 8, 11 }, everyUp = { 5, 7 }, windUp = 0.8, count = 5, spread = 110, radius = 80,
  damage = 30, delay = 1.1, stagger = 0.15, cost = 16 }
Brain.LEAP = { min = 260, max = 560, every = 7, windUp = 0.7, air = 0.8, hit = 110, damage = 40, shove = 220,
  recover = 0.8, cost = 28 }
Brain.DRONES = { every = 15, everyUp = 7.5, cap = 2, capUp = 3, out = 40 } -- `out`: px behind him one comes out
Brain.UPGRADE = 0.5 -- of his health, where Jerry pushes it

local random = love.math.random

function Brain.gun()
  return Chassis.gun("WLB", "minigun", { damage = 9, spread = 0.08 })
end

function Brain.init(s)
  s.breath, s.events, s.mine = Stamina.new(Brain.BREATH), {}, {}
  s.volleyIn, s.leapAt, s.droneIn = Chassis.between(Brain.VOLLEY.every) * 0.5, 0, 1.5
  s.nextDrone = "SHD"
  s.power = Bosses.power()
end

Brain.wake = Chassis.wake

--- Gone (army.lua's `down`): wilbur.lua reads it.
function Brain.gone(s)
  s.dead = true
end

local function blocked(x, y)
  return Chassis.blocked(x, y)
end

--- The nearest player he can see, and where; failing that, the nearest
--- anywhere, and whether he sees them.
local function target(server, s)
  local seen, sx, sy, seenD2
  local any, ax, ay, anyD2
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Chassis.dist2(x, y, s.x, s.y)
      if not anyD2 or d2 < anyD2 then
        any, ax, ay, anyD2 = id, x, y, d2
      end
      if d2 <= s.conf.range ^ 2 and (not seenD2 or d2 < seenD2) and Chassis.lineClear(s.x, s.y, x, y) then
        seen, sx, sy, seenD2 = id, x, y, d2
      end
    end
  end
  if seen then
    return seen, sx, sy, true
  end
  return any, ax, ay, false
end

--- One step along `angle`, by the boss walking rule.
local function step(s, angle, speed, dt)
  return Walk.step(s, blocked, angle, speed, dt, s.radius)
end

--- One step on the walking grid towards (x, y).
local function walkTo(roster, s, x, y, speed, dt)
  s.walkNav = s.walkNav or Walk.nav(roster.nav, blocked, s.radius)
  local way = Walk.route(s, s.walkNav, x, y, roster.time)
  if way then
    s.facing = Chassis.turn(s.facing, way, Chassis.TURN, dt)
    step(s, way, speed, dt)
  end
end

--- Everyone within `radius` of (x, y) takes `damage` (`impact`) and is
--- thrown `shove` px out from it. Returns how many it caught.
function Brain.slam(server, x, y, radius, damage, shove)
  local weapons, onFoot = Features.byName.weapons, Features.byName["on-foot"]
  local caught = 0
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if Chassis.dist2(px, py, x, y) <= radius * radius then
        local a = math.atan2(py - y, px - x)
        caught = caught + 1
        if weapons and weapons.serverDamage then
          weapons:serverDamage(server, p, nil, math.floor(damage + 0.5), a, "impact")
        end
        if onFoot and onFoot.serverShove then
          onFoot:serverShove(server, p, math.cos(a), math.sin(a), shove, 0.35)
        end
      end
    end
  end
  return caught
end

--- Where a leap at (tx, ty) comes down: as near them as LEAP.max allows,
--- back towards him until he fits there; nil when that's hardly worth it.
local function landing(s, tx, ty)
  local a = math.atan2(ty - s.y, tx - s.x)
  local d = math.min(Brain.LEAP.max, math.sqrt(Chassis.dist2(tx, ty, s.x, s.y)))
  while d >= Brain.LEAP.min * 0.6 do
    local x, y = s.x + math.cos(a) * d, s.y + math.sin(a) * d
    if Walk.fits(blocked, x, y, s.radius) then
      return x, y
    end
    d = d - 16
  end
  return nil
end

--- How many of the drones he sent out are still up.
local function droneCount(roster, s)
  local alive = {}
  for _, d in ipairs(s.mine) do
    if roster:indexOf(d) then
      alive[#alive + 1] = d
    end
  end
  s.mine = alive
  return #alive
end

--- A drone out of his back, if it's time and there's room for one.
local function sendDrone(roster, server, s, dt)
  s.droneIn = s.droneIn - dt
  if s.droneIn > 0 then
    return
  end
  s.droneIn = s.upgraded and Brain.DRONES.everyUp or Brain.DRONES.every
  if droneCount(roster, s) >= Bosses.plus(s.upgraded and Brain.DRONES.capUp or Brain.DRONES.cap, server) then
    return
  end
  local back = s.facing + math.pi
  local d = roster:add(Drone, s.nextDrone, s.x + math.cos(back) * Brain.DRONES.out,
    s.y + math.sin(back) * Brain.DRONES.out, s.facing)
  s.mine[#s.mine + 1] = d
  s.nextDrone = s.nextDrone == "SHD" and "FIX" or "SHD"
end

--- The volley out of his shoulder pod, coming down round (tx, ty).
local function volley(server, s, tx, ty)
  local v = Brain.VOLLEY
  for k = 0, v.count - 1 do
    local a = random() * 2 * math.pi
    local d = k == 0 and 0 or v.spread * (0.5 + 0.5 * random()) -- one right on you
    Barrage.serverFire(server, s.x, s.y, tx + math.cos(a) * d, ty + math.sin(a) * d, v.radius, v.damage * s.power,
      v.delay + k * v.stagger)
  end
end

--- A move under way (its tell, then what it does). Returns true while one is.
local function moving(server, s, dt)
  if not s.move then
    return false
  end
  s.moveT = s.moveT + dt
  if s.move == "volley" then
    local p = s.aimAt and server.players[s.aimAt]
    if p and Features.visible(server, p) then
      s.lastX, s.lastY = Features.bodyPose(server, p)
      s.facing = Chassis.turn(s.facing, math.atan2(s.lastY - s.y, s.lastX - s.x), Chassis.TURN, dt)
    end
    if s.moveT >= Brain.VOLLEY.windUp then
      volley(server, s, s.lastX, s.lastY)
      s.move, s.charging = nil, nil
      s.volleyIn = Chassis.between(s.upgraded and Brain.VOLLEY.everyUp or Brain.VOLLEY.every)
    end
  elseif s.move == "crouch" then
    if s.moveT >= Brain.LEAP.windUp then
      s.move, s.moveT, s.flying, s.charging = "leap", 0, true, nil
      s.leapFrom = { x = s.x, y = s.y }
    end
  elseif s.move == "leap" then -- up over whatever's low; nothing reaches him up there
    local k = math.min(1, s.moveT / Brain.LEAP.air)
    local f, t = s.leapFrom, s.leapTo
    s.x, s.y = f.x + (t.x - f.x) * k, f.y + (t.y - f.y) * k
    if k >= 1 then
      local L = Brain.LEAP
      Brain.slam(server, s.x, s.y, L.hit, L.damage * s.power, L.shove)
      s.events[#s.events + 1] = { "slam", s.x, s.y, L.hit }
      s.move, s.moveT, s.flying, s.leapFrom, s.leapTo = "land", 0, nil, nil, nil
      s.route = nil
    end
  elseif s.move == "land" then
    if s.moveT >= Brain.LEAP.recover then
      s.move = nil
    end
  end
  return true
end

--- A leap or a volley at somebody he can see `d` px off, if one is due.
--- Kiting to a medkit along `way`, a leap only that way. Returns true when one starts.
local function attack(roster, s, who, tx, ty, d, way)
  local toward = math.atan2(ty - s.y, tx - s.x)
  local L, V = Brain.LEAP, Brain.VOLLEY
  local thatWay = not way or math.abs(Chassis.turnBetween(toward, way)) < 0.6
  if thatWay and roster.time >= s.leapAt and d >= L.min and s.breath:has(L.cost) then
    local lx, ly = landing(s, tx, ty)
    if lx then
      s.breath:spend(L.cost)
      s.move, s.moveT, s.charging = "crouch", 0, true
      s.leapTo, s.leapAt = { x = lx, y = ly }, roster.time + L.every
      s.events[#s.events + 1] = { "leap", lx, ly, L.hit, L.windUp + L.air }
      return true
    end
  end
  if s.volleyIn <= 0 and s.breath:has(V.cost) then
    s.breath:spend(V.cost)
    s.move, s.moveT, s.charging = "volley", 0, true
    s.aimAt, s.lastX, s.lastY = who, tx, ty
    return true
  end
  return false
end

--- Badly hurt and a medkit in reach: off for it (see the top). Returns
--- true while that is what he is doing.
local function heal(roster, server, s, who, tx, ty, visible, dt)
  if not Heal.wants(s.hp, s.max) then
    s.medkit = nil
    return false
  end
  if s.medkit and not Heal.there(s.medkit) then
    s.medkit = nil
  end
  if not s.medkit and roster.time >= (s.healLook or 0) then
    s.medkit, s.healLook = Heal.find(s.x, s.y), roster.time + Heal.checkEvery
  end
  if not s.medkit then
    return false
  end
  s.walkNav = s.walkNav or Walk.nav(roster.nav, blocked, s.radius)
  local way = Heal.way(s, s.walkNav, s.medkit, roster.time)
  if not way then
    Heal.giveUp(s, roster.time)
    s.medkit = nil
    return false
  end
  if visible then -- kiting: facing them, shooting, at a walk
    if not attack(roster, s, who, tx, ty, math.sqrt(Chassis.dist2(s.x, s.y, tx, ty)), way) then
      roster:shoot(server, s, tx, ty, Brain.gun(), dt)
      step(s, way, Brain.CONF.walk, dt)
    end
  else
    s.facing = Chassis.turn(s.facing, way, Chassis.TURN, dt)
    step(s, way, s.conf.speed, dt)
    s.running = true
  end
  Heal.pickUp(server, s, s.radius)
  return true
end

function Brain.think(roster, server, s, dt)
  s.running = false
  if not s.upgraded and s.hp <= s.max * Brain.UPGRADE then
    s.upgraded = true
    s.droneIn = math.min(s.droneIn, 1)
    s.events[#s.events + 1] = { "upgrade" }
  end
  s.conf = s.breath:winded() and Brain.WINDED or s.upgraded and Brain.UPGRADED or Brain.CONF
  s.volleyIn = s.volleyIn - dt
  if moving(server, s, dt) then
    s.breath:step(false, dt)
    return
  end
  sendDrone(roster, server, s, dt)
  local threat = Dodge.threat(s.x, s.y, s.radius)
  if threat then -- out from under it, at a run
    local ux, uy = Dodge.away(threat, s.x, s.y)
    step(s, math.atan2(uy, ux), s.conf.speed, dt)
    s.breath:step(not s.breath:winded(), dt)
    return
  end
  local who, tx, ty, visible = target(server, s)
  if not who then
    s.breath:step(false, dt)
    return
  end
  if heal(roster, server, s, who, tx, ty, visible, dt) then
    s.breath:step(s.running, dt)
    return
  end
  if not visible then
    walkTo(roster, s, tx, ty, s.conf.speed, dt)
    s.breath:step(not s.breath:winded(), dt)
    return
  end
  local d = math.sqrt(Chassis.dist2(s.x, s.y, tx, ty))
  if attack(roster, s, who, tx, ty, d) then
    s.breath:step(false, dt)
    return
  end
  roster:shoot(server, s, tx, ty, Brain.gun(), dt)
  local toward = math.atan2(ty - s.y, tx - s.x)
  if d > Brain.KEEP + 120 and not Walk.wideClear(blocked, s.x, s.y, tx, ty, s.radius) then
    walkTo(roster, s, tx, ty, s.conf.speed, dt) -- round whatever's in the way
    s.running = true
  elseif d > Brain.KEEP + 80 then
    step(s, toward, d > Brain.KEEP + 200 and s.conf.speed or Brain.CONF.walk, dt)
    s.running = d > Brain.KEEP + 200
  elseif d < Brain.KEEP - 80 then
    step(s, toward + math.pi, s.conf.speed * 0.7, dt)
  else -- circling, now this way, now that
    s.side = s.side or 1
    if not step(s, toward + s.side * math.pi / 2, Brain.CONF.walk, dt) or random() < dt * 0.3 then
      s.side = -s.side
    end
  end
  s.breath:step(s.running and not s.breath:winded(), dt)
end

return Brain
