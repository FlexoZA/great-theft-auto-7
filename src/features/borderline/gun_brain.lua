-- How a gun hauler (GUN) thinks (docs/borderline.md, "The army"):
-- Hyperbole's standard model, a rifle on one arm and a grenade launcher on
-- the other. It stands watch, walks its beat and keeps its distance the
-- way every drilled model does (drill.lua): posted or in squads, side-
-- stepping in its band, flanking in pairs. Seeing somebody, it calls the
-- rest near it (army.lua: `s.spotted`). It fires its rifle in bursts, and
-- every so often lobs a grenade (the grenades feature's) at you, and one
-- at where it lost you as it goes to look. Hurt by somebody it can't see,
-- it turns and goes to look.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 70,
  speed = 120, -- px/s in a fight
  walk = 70, -- px/s on its beat
  range = 620,
  aware = 170,
  fov = math.rad(80),
  alertFov = math.rad(120),
  far = 450, -- px: further than this it closes in
  near = 250, -- px: nearer than this it backs off
  strafe = { 1.2, 2.6 }, -- seconds each way it side-steps
  aim = 0.5,
  burst = 3,
  every = 0.12,
  pause = { 1.0, 1.8 },
  grenadeEvery = { 9, 14 }, -- seconds between lobs
  grenadeRange = { 200, 520 }, -- px it lobs at
  search = 6,
  lostAfter = 3,
  leash = 900, -- px from its post (or its squad's leader) it will go
}

function Brain.gun()
  return Chassis.gun("GUN", "ak47", { damage = 8, spread = 0.06 })
end

function Brain.init(s)
  Drill.init(s)
  s.lobIn = Chassis.between(Brain.CONF.grenadeEvery) * 0.5
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone

Brain.hurt = Drill.hurt

local function maybeLob(server, s, tx, ty, dt)
  s.lobIn = s.lobIn - dt
  if s.lobIn > 0 then
    return
  end
  local r = s.conf.grenadeRange
  local d2 = Chassis.dist2(s.x, s.y, tx, ty)
  if d2 < r[1] * r[1] or d2 > r[2] * r[2] then
    return
  end
  local grenades = Features.byName.grenades
  if grenades and grenades.serverLob then
    grenades:serverLob(server, s.x, s.y, tx, ty, 0)
  end
  s.lobIn = Chassis.between(s.conf.grenadeEvery)
end

function Brain.think(roster, server, s, dt)
  local tx, ty = Drill.look(roster, server, s, dt)
  if tx then
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    maybeLob(server, s, tx, ty, dt)
    return
  end
  if Drill.idle(roster, s, dt) and s.seenX then
    s.lobIn = math.min(s.lobIn, 0.8) -- a parting gift where it lost you
  end
  if s.state == "search" and s.seenX and s.t < 1.5 and Chassis.dist2(s.x, s.y, s.seenX, s.seenY) > 200 * 200 then
    maybeLob(server, s, s.seenX, s.seenY, dt)
  end
end

return Brain
