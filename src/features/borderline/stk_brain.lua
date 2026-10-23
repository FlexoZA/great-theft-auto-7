-- How a stalker hauler (STK) thinks (docs/borderline.md, "The army"):
-- Hyperbole's hunter, tall and quick on three long legs, two flechette
-- pods on its shoulders. It stands watch and walks its beat like the
-- drilled models (drill.lua: posted, or hunting the stacks in a pair) and
-- keeps its distance the same way, quicker about it. Its modes, the first
-- that applies each tick:
--
--   dodge   once it knows somebody is about (hunting, or searching where
--           it lost them), a player's round about to hit it or an ability
--           about to land on it (bosses/dodge.lua): it throws itself
--           aside. Not before: a shot from hiding lands, and only then
--           does it turn round. A dodge spends breath as it goes
--           (bosses/stamina.lua), and it can't again straight away; a few
--           in a row and it is winded, walking, with no dodge or charge
--           in it until it has its breath back (every screen sees its
--           breath under it, red while it is winded).
--   charge  now and then, somebody at the right distance: it crouches
--           (`charging`, its pods and eye glow), then runs straight at
--           where they stood and can't turn; whoever it runs into is
--           knocked flying (`impact`). Then it backs off to its distance.
--   heal    badly hurt, it goes for a medkit lying near (bosses/heal.lua),
--           backing towards it at a walk and still shooting while it can
--           see somebody, running for it while it can't.
--   fight   bursts of flechettes (darts.lua) that stick and blow.
--   watch   nobody in sight: drill's watch, beat and search.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")
local Darts = require("src.features.borderline.darts")
local Stamina = require("src.features.bosses.stamina")
local Heal = require("src.features.bosses.heal")
local Dodge = require("src.features.bosses.dodge")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 140,
  speed = 190, -- px/s in a fight: a sprint's worth
  walk = 90, -- px/s on its beat
  range = 640,
  aware = 200,
  fov = math.rad(100),
  alertFov = math.rad(150),
  far = 480, -- px: further than this it closes in
  near = 260, -- px: nearer than this it backs off
  strafe = { 0.8, 1.6 }, -- seconds each way it side-steps
  aim = 0.6, -- its pods spinning up
  burst = 6,
  every = 0.07,
  pause = { 1.8, 2.6 },
  search = 6,
  lostAfter = 3,
  leash = 1200, -- px from its post (or its pair's leader) it will go
}

-- Its darts (darts.lua): `sting` as one sticks in you, a blast `radius` px wide of `damage` a second later.
Brain.DART = { speed = 650, ttl = 1.0, sting = 3, radius = 40, damage = 10 }
Brain.SPREAD = 0.09 -- radians either side a dart may stray
Brain.PODS = 9 -- px either side of its middle the pods fire from, by turns
Brain.DODGE = { warn = 0.4, speed = 480, time = 0.22, cool = 1.2 } -- (its breath goes while it dodges)
Brain.CHARGE = { every = { 6, 9 }, range = { 110, 380 }, windUp = 0.5, speed = 430, time = 0.6, reach = 30,
  damage = 20, cost = 30, backOff = 1.2 }
-- Its breath: `drain` a second while it dodges (about a quarter of it a dodge), the charge's `cost` at once.
Brain.BREATH = { drain = 110, regen = 14, recovered = 50, breath = 20 }
-- Winded it only walks: its numbers then.
Brain.WINDED = setmetatable({ speed = Brain.CONF.walk }, { __index = Brain.CONF })

local random = love.math.random

--- A dart out of one pod or the other along `aim`, give or take its spread.
local function fireDart(server, s, aim)
  s.pod = -(s.pod or 1)
  local px, py = -math.sin(s.facing) * Brain.PODS * s.pod, math.cos(s.facing) * Brain.PODS * s.pod
  local a = aim + (random() * 2 - 1) * Brain.SPREAD
  Darts.serverFire(server, s.x + px + math.cos(a) * s.radius, s.y + py + math.sin(a) * s.radius, a, Brain.DART)
end

function Brain.gun()
  return fireDart
end

function Brain.init(s)
  Drill.init(s)
  s.breath = Stamina.new(Brain.BREATH)
  s.chargeIn, s.dodgeAt, s.backFor = Chassis.between(Brain.CHARGE.every) * 0.5, 0, 0
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone
Brain.hurt = Drill.hurt

--- Which way (a unit vector onto ground it fits) gets `s` off the line of
--- a player's round about to hit it, or out from under an ability; nil
--- when nothing is coming. Then who fired the round, if it was one.
local function threat(server, s)
  local weapons = Features.byName.weapons
  local reach = Brain.DODGE.speed * Brain.DODGE.time
  for _, r in ipairs(weapons and weapons.sv and weapons.sv.projectiles or {}) do
    local speed = math.sqrt(r.vx * r.vx + r.vy * r.vy)
    if r.owner ~= 0 and server.players[r.owner] and speed > 0 then
      local ux, uy = r.vx / speed, r.vy / speed
      local ahead = (s.x - r.x) * ux + (s.y - r.y) * uy
      local off = (s.y - r.y) * ux - (s.x - r.x) * uy
      local wide = s.radius + 10 + (r.blast and r.blast.radius * 0.6 or 0)
      if ahead > 0 and ahead < speed * Brain.DODGE.warn and math.abs(off) < wide then
        local side = off >= 0 and 1 or -1 -- away from the line, if there's room that way
        for _, k in ipairs({ side, -side }) do
          if Chassis.fits(s.x - uy * k * reach, s.y + ux * k * reach, s.radius) then
            return -uy * k, ux * k, r.owner
          end
        end
        return nil
      end
    end
  end
  local a = Dodge.threat(s.x, s.y, s.radius)
  if a then
    return Dodge.away(a, s.x, s.y)
  end
  return nil
end

--- The player in front of a charging `s`, within its reach, if any.
local function runInto(server, s)
  local hx, hy = s.x + math.cos(s.facing) * s.radius, s.y + math.sin(s.facing) * s.radius
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if Chassis.dist2(px, py, hx, hy) <= Brain.CHARGE.reach * Brain.CHARGE.reach then
        return p
      end
    end
  end
  return nil
end

--- Charging: straight on until its time is up, a wall stops it, or it hits somebody.
local function rush(server, s, dt)
  local c = Brain.CHARGE
  s.rushFor = s.rushFor - dt
  local step = c.speed * dt
  local moved = Chassis.move(s, math.cos(s.facing) * step, math.sin(s.facing) * step)
  local p = runInto(server, s)
  if p then
    local weapons = Features.byName.weapons
    if weapons and weapons.serverDamage then
      weapons:serverDamage(server, p, nil, c.damage, s.facing, "impact")
    end
  end
  if p or not moved or s.rushFor <= 0 then
    s.rushFor, s.backFor = nil, c.backOff
    s.chargeIn = Chassis.between(c.every)
  end
end

--- Badly hurt and a medkit in reach: go and get it (see the top). Returns
--- true while that is what it is doing.
local function heal(roster, server, s, tx, ty, dt)
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
  if not s.medkit or Heal.pickUp(server, s, s.radius) then
    return false
  end
  roster:goTo(s, s.medkit.x, s.medkit.y, tx and s.conf.walk or s.conf.speed, dt, not tx)
  if tx then
    roster:shoot(server, s, tx, ty, fireDart, dt)
  end
  return true
end

--- Does `s` know somebody is about: hunting them, or looking where it lost them?
local function alert(s)
  return s.target ~= nil or s.state == "hunt" or s.state == "search"
end

function Brain.think(roster, server, s, dt)
  s.breath:step(s.dodgeFor ~= nil, dt)
  s.conf = s.breath:winded() and Brain.WINDED or Brain.CONF
  if s.dodgeFor then
    s.dodgeFor = s.dodgeFor - dt
    Chassis.move(s, s.dodgeX * Brain.DODGE.speed * dt, s.dodgeY * Brain.DODGE.speed * dt)
    if s.dodgeFor <= 0 then
      s.dodgeFor = nil
    end
    return
  end
  if s.rushFor then
    rush(server, s, dt)
    return
  end
  local tx, ty = Drill.look(roster, server, s, dt)
  if s.charging then -- crouched, aiming at where they stand
    s.charging = s.charging - dt
    if tx then
      s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Chassis.TURN, dt)
    end
    if s.charging <= 0 then
      s.charging, s.rushFor = nil, Brain.CHARGE.time
    end
    return
  end
  if alert(s) and roster.time >= s.dodgeAt and s.breath:has() then
    local ux, uy, shooter = threat(server, s)
    if ux then
      local sx, sy = nil, nil
      if shooter then
        sx, sy = Chassis.poseOf(server, shooter)
      end
      if sx and not s.target then -- whoever fired it: it calls the rest and goes after them
        Chassis.wake(s, sx, sy)
        s.spotted = true
      end
      s.dodgeFor, s.dodgeX, s.dodgeY = Brain.DODGE.time, ux, uy
      s.dodgeAt, s.aimFor = roster.time + Brain.DODGE.cool, 0
      return
    end
  end
  if heal(roster, server, s, tx, ty, dt) then
    return
  end
  if not tx then
    Drill.idle(roster, s, dt)
    return
  end
  local c = Brain.CHARGE
  s.chargeIn = s.chargeIn - dt
  if s.backFor > 0 then -- just charged: back off, facing them
    s.backFor = s.backFor - dt
    local away = math.atan2(s.y - ty, s.x - tx)
    Chassis.move(s, math.cos(away) * s.conf.speed * dt, math.sin(away) * s.conf.speed * dt)
    s.facing = Chassis.turn(s.facing, away + math.pi, Chassis.TURN, dt)
    return
  end
  local d2 = Chassis.dist2(s.x, s.y, tx, ty)
  if s.chargeIn <= 0 and d2 > c.range[1] * c.range[1] and d2 < c.range[2] * c.range[2]
    and s.breath:has(c.cost) then
    s.breath:spend(c.cost)
    s.charging, s.aimFor = c.windUp, 0
    return
  end
  Drill.band(roster, s, tx, ty, dt)
  roster:shoot(server, s, tx, ty, fireDart, dt)
end

return Brain
