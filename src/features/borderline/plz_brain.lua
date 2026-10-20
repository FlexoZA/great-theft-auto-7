-- How a plasma hauler (PLZ) thinks (docs/borderline.md, "The army" and
-- "Plasma"): a cannon on its arm with purple coils down it, and a tank of
-- Bragium on its back to feed it. It stands watch and keeps its distance
-- the way every drilled model does (drill.lua), at middling range. Its
-- coils glow while it lines up (its trigger's `aim`, which everyone sees),
-- then one slow bolt (bolts.lua) that splashes and melts armor: sidestep
-- it.
--
-- Its weak spot is the tank: a killing hit from behind (a round travelling
-- the way it faces) bursts it, a splash of plasma that hurts whoever is
-- near, its own side included (army.lua asks `Brain.burst`).
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")
local Bolts = require("src.features.borderline.bolts")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 90,
  speed = 105,
  walk = 60,
  range = 600,
  aware = 160,
  fov = math.rad(80),
  alertFov = math.rad(120),
  far = 500,
  near = 280,
  strafe = { 1.2, 2.4 },
  aim = 0.6, -- the coils charging
  burst = 1,
  every = 0.2,
  pause = { 1.4, 2.2 },
  search = 6,
  lostAfter = 3,
  leash = 900,
}

Brain.BOLT = { speed = 260, ttl = 2.6, damage = 22, splash = 40 } -- 260 px/s: a sprint (170) sidesteps it
Brain.BACK = math.rad(60) -- a killing round within this of its facing came from behind
Brain.BURST = { radius = 95, damage = 40 } -- the tank going up

local MUZZLE = 20 -- px out front the bolt leaves from

local function fireBolt(server, s, aim)
  Bolts.serverFire(server, s.x + math.cos(aim) * MUZZLE, s.y + math.sin(aim) * MUZZLE, aim, Brain.BOLT)
end

function Brain.gun()
  return fireBolt
end

Brain.init = Drill.init
Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone

Brain.hurt = Drill.hurt

--- Did the round that killed `s`, travelling along `angle`, burst its
--- tank? Returns the splash ({ radius, damage }) if so.
function Brain.burst(s, angle)
  if angle and math.abs(Chassis.turnBetween(s.facing, angle)) <= Brain.BACK then
    return Brain.BURST
  end
  return nil
end

function Brain.think(roster, server, s, dt)
  local tx, ty = Drill.look(roster, server, s, dt)
  if tx then
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, fireBolt, dt)
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
