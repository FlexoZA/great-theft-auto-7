-- How a jet hauler (JET) thinks (docs/borderline.md, "The army"): wings
-- folded on its back and thrusters under them. On the ground it fights
-- like any drilled model (drill.lua) with its rifle. Every so often, with
-- somebody in sight, it crouches as its thrusters light (`charging`), takes
-- off and makes a run straight over you and on past, faster than anyone
-- runs and over walls. Along the line of its run it drops rockets, each on
-- a red ring first (barrage.lua), and at the end it comes down wherever
-- there is room and fights on. In the air (`flying`) nothing reaches it:
-- shoot it on the ground or as it lands.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's;
-- the map's edges keep its runs in (the roster's `bounds`, from army.lua).

local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")
local Barrage = require("src.features.borderline.barrage")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 70,
  speed = 130,
  walk = 70,
  range = 640,
  aware = 170,
  fov = math.rad(80),
  alertFov = math.rad(120),
  far = 450,
  near = 250,
  strafe = { 1.2, 2.6 },
  aim = 0.5,
  burst = 3,
  every = 0.12,
  pause = { 1.0, 1.8 },
  search = 6,
  lostAfter = 3,
  leash = 1400, -- its runs carry it about
  runEvery = { 7, 11 }, -- seconds on the ground between runs
  takeOff = 0.7, -- seconds its thrusters light before it goes
  flySpeed = 320, -- px/s in the air
  runPast = 360, -- px past you it flies on
  marks = 5, -- rockets along the run
  markGap = 90, -- px between them
  markRadius = 70,
  markDamage = 20,
  markDelay = 0.8, -- seconds from the ring to the rocket, for the first...
  markStagger = 0.12, -- ...and this much more for each after
  landFor = 0.5, -- seconds it stands, shootable, coming down
}

function Brain.gun()
  return Chassis.gun("JET", "ak47", { damage = 7, spread = 0.07 })
end

function Brain.init(s)
  Drill.init(s)
  s.runIn = Chassis.between(Brain.CONF.runEvery) * 0.5
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone
Brain.hurt = Drill.hurt

--- (x, y) kept `margin` px inside the roster's bounds.
local function inside(roster, x, y, margin)
  local b = roster.bounds
  if not b then
    return x, y
  end
  return math.max(b.x0 + margin, math.min(b.x1 - margin, x)), math.max(b.y0 + margin, math.min(b.y1 - margin, y))
end

--- Off it goes: a run over (tx, ty) and on past, rockets marked along it.
local function takeOff(roster, server, s, tx, ty)
  local conf = s.conf
  local a = math.atan2(ty - s.y, tx - s.x)
  local ux, uy = math.cos(a), math.sin(a)
  s.runX, s.runY = inside(roster, tx + ux * conf.runPast, ty + uy * conf.runPast, 96)
  s.flying, s.facing, s.target = true, a, nil
  local half = (conf.marks - 1) / 2
  for k = 0, conf.marks - 1 do
    local along = (k - half) * conf.markGap
    Barrage.serverFire(server, s.x, s.y, tx + ux * along, ty + uy * along, conf.markRadius, conf.markDamage,
      conf.markDelay + k * conf.markStagger)
  end
end

--- In the air: straight at the end of its run, over everything; there, it
--- comes down where there is room.
local function fly(s, dt)
  local dx, dy = s.runX - s.x, s.runY - s.y
  local d = math.sqrt(dx * dx + dy * dy)
  local step = s.conf.flySpeed * dt
  if d > step then
    s.x, s.y = s.x + dx / d * step, s.y + dy / d * step
    return
  end
  s.x, s.y = Chassis.clearSpot(s.runX, s.runY, s.radius)
  s.flying, s.landing = nil, s.conf.landFor
  s.runIn = Chassis.between(s.conf.runEvery)
end

function Brain.think(roster, server, s, dt)
  if s.flying then
    fly(s, dt)
    return
  end
  if s.landing then -- touching down: it stands there a moment
    s.landing = s.landing > dt and s.landing - dt or nil
    return
  end
  local tx, ty = Drill.look(roster, server, s, dt)
  if s.charging then
    s.charging = s.charging - dt
    if tx then
      s.lastX, s.lastY = tx, ty
    end
    if s.charging <= 0 then
      s.charging = nil
      takeOff(roster, server, s, s.lastX, s.lastY)
    end
    return
  end
  if tx then
    s.runIn = s.runIn - dt
    if s.runIn <= 0 then
      s.charging, s.lastX, s.lastY = s.conf.takeOff, tx, ty
      return
    end
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
