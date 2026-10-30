-- How a rocket hauler (RPG) thinks (docs/borderline.md, "The army"): a
-- heavier hauler with a launcher on one arm and two pods of rockets on its
-- back. It stands watch and keeps its distance the way every drilled model
-- does (drill.lua), only further back. From its arm it fires one rocket at
-- a time (the weapons feature's rocket launcher, slower and lighter); every
-- so often it stops, its pods open and glow (`charging`: everyone sees it
-- wind up), and it sends a volley up out of them that comes down round
-- where you stand, each one on a red ring first (barrage.lua). Kill it
-- first, or keep moving.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")
local Barrage = require("src.features.borderline.barrage")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 120,
  speed = 90,
  walk = 60,
  range = 760,
  aware = 170,
  fov = math.rad(80),
  alertFov = math.rad(120),
  far = 650, -- it hangs back
  near = 400,
  strafe = { 1.5, 3 },
  aim = 0.8,
  burst = 1,
  every = 0.2,
  pause = { 2.4, 3.4 }, -- between rockets from its arm
  search = 6,
  lostAfter = 3,
  leash = 900,
  volleyEvery = { 7, 10 }, -- seconds between pod volleys
  windUp = 1.0, -- seconds its pods glow before they fire
  volley = 4, -- rockets a volley
  volleySpread = 90, -- px round you they come down
  volleyRadius = 80, -- px each blast reaches
  volleyDamage = 28, -- at the middle of each
  volleyDelay = 1.1, -- seconds from leaving the pods to the ground (the first)
  volleyStagger = 0.15, -- seconds between one landing and the next
}

function Brain.gun()
  return Chassis.gun("RPG", "rocket", {
    speed = 420, -- slower than a player's: you see it coming
    ttl = 1.9,
    blast = { radius = 90, damage = 30, soft = 0 },
  })
end

function Brain.init(s)
  Drill.init(s)
  s.volleyIn = Chassis.between(Brain.CONF.volleyEvery) * 0.6
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone

Brain.hurt = Drill.hurt

--- The pods: rockets up and over, coming down round (tx, ty). `conf`
--- has the volley's numbers (the badass hauler's pods use it with its own).
function Brain.volley(server, s, tx, ty, conf)
  for k = 0, conf.volley - 1 do
    local a = love.math.random() * 2 * math.pi
    local d = k == 0 and 0 or conf.volleySpread * (0.5 + 0.5 * love.math.random()) -- one right on you
    Barrage.serverFire(server, s.x, s.y, tx + math.cos(a) * d, ty + math.sin(a) * d, conf.volleyRadius,
      conf.volleyDamage, conf.volleyDelay + k * conf.volleyStagger)
  end
end

function Brain.think(roster, server, s, dt)
  local conf = s.conf
  local tx, ty = Drill.look(roster, server, s, dt)
  if s.charging then -- winding up: it stands, turning to you, and lets go
    s.charging = s.charging - dt
    if tx then
      s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Chassis.TURN, dt)
      s.lastX, s.lastY = tx, ty
    end
    if s.charging <= 0 then
      s.charging = nil
      if s.lastX then
        Brain.volley(server, s, s.lastX, s.lastY, conf)
      end
      s.volleyIn = Chassis.between(conf.volleyEvery)
    end
    return
  end
  if tx then
    s.volleyIn = s.volleyIn - dt
    if s.volleyIn <= 0 then
      s.charging, s.lastX, s.lastY = conf.windUp, tx, ty
      return
    end
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
