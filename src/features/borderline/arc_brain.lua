-- How an arc hauler (ARC) thinks (docs/borderline.md, "The army"): blue
-- coils on both arms and a dish on its back. It stands watch and keeps
-- its distance like any drilled model (drill.lua), closer in than most,
-- and throws shock bolts from both arms that zap you on after the hit.
--
-- Its trick is the dome. In a fight, every so often its dish throws a dome
-- up round it (`DOME`): rounds from outside stop at it, so nothing out
-- there can hurt any of the army under it, but whoever walks inside is
-- zapped every second, and from inside your rounds hit. army.lua keeps the
-- domes (`s.dome`, its seconds left) and does both.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 80,
  speed = 70,
  walk = 40,
  range = 520,
  aware = 170,
  fov = math.rad(80),
  alertFov = math.rad(120),
  far = 380,
  near = 200,
  strafe = { 1.2, 2.4 },
  aim = 0.5,
  burst = 2, -- one from each arm
  every = 0.25,
  pause = { 1.2, 2.0 },
  search = 6,
  lostAfter = 3,
  leash = 700,
}

Brain.DOME = { radius = 180, time = 5, every = { 11, 14 }, zap = 8 } -- zap: shock a second inside

function Brain.gun()
  return Chassis.gun("ARC", "pistol", {
    damage = 10, spread = 0.05, speed = 700, damageType = "shock", electrify = { seconds = 1.5, dps = 6 },
  })
end

function Brain.init(s)
  Drill.init(s)
  s.domeIn = 4
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone
Brain.hurt = Drill.hurt

function Brain.think(roster, server, s, dt)
  if s.dome then
    s.dome = s.dome > dt and s.dome - dt or nil
  end
  local tx, ty = Drill.look(roster, server, s, dt)
  if tx then
    s.domeIn = s.domeIn - dt
    if s.domeIn <= 0 then
      s.dome, s.domeIn = Brain.DOME.time, Chassis.between(Brain.DOME.every)
      s.domed = true -- army.lua tells everyone
    end
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
