-- How a dozer hauler (DZR) thinks (docs/borderline.md, "The army"): wide,
-- slow and tough, a bulldozer blade across its front. The blade stops every
-- round that comes at it from the front (`Brain.blocks`, army.lua asks):
-- flank it, or blow it up (blasts and fire go round a blade).
--
-- It stands watch like any drilled model (drill.lua). With somebody in
-- sight it shoves its way at them, blade first, and up close it shoves
-- them (`impact`, knocked down). Every so often it folds into a dozer
-- (`charging`, a moment everyone sees), then charges in a straight line
-- where you stood, fast, and can't turn once it has started: step aside.
-- Whoever it runs into is flattened (`impact`, harder).
--
-- The body (walking, sight, the torso crawl) is chassis.lua's.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 160,
  speed = 85,
  walk = 60,
  range = 560,
  aware = 170,
  fov = math.rad(90),
  alertFov = math.rad(120),
  aim = 0,
  search = 6,
  lostAfter = 3,
  leash = 900,
  strafe = { 2, 3 }, -- (drill's dodge reads it)
}

Brain.SHIELD = math.rad(35) -- either side of straight ahead the blade covers (70 in all)
Brain.SHOVE = { reach = 44, damage = 18, every = 1.2 }
Brain.CHARGE = { every = { 6, 8 }, windUp = 0.6, speed = 240, time = 1.3, hit = 30, damage = 30 }

function Brain.init(s)
  Drill.init(s)
  s.chargeIn, s.shoveIn = Chassis.between(Brain.CHARGE.every) * 0.6, 0
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone
Brain.hurt = Drill.hurt

--- Does the blade stop a `dtype` round travelling along `angle` into `s`?
--- From the front, and not a blast or fire (they go round it).
function Brain.blocks(s, angle, dtype)
  if dtype == "explosive" or dtype == "fire" or not angle or s.crawl then
    return false
  end
  return math.abs(Chassis.turnBetween(s.facing, angle + math.pi)) <= Brain.SHIELD
end

--- Hurt whoever is within `reach` of `s`'s front by `damage`, knocked along its facing.
local function ram(server, s, reach, damage)
  local weapons = Features.byName.weapons
  if not (weapons and weapons.serverDamage) then
    return false
  end
  local hit = false
  local fx, fy = s.x + math.cos(s.facing) * s.radius, s.y + math.sin(s.facing) * s.radius
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      if Chassis.dist2(px, py, fx, fy) <= reach * reach then
        weapons:serverDamage(server, p, nil, damage, s.facing, "impact")
        hit = true
      end
    end
  end
  return hit
end

--- Charging: straight on until its time is up, a wall stops it, or it hits somebody.
local function charge(server, s, dt)
  local c = Brain.CHARGE
  s.rushFor = s.rushFor - dt
  local moved = Chassis.move(s, math.cos(s.facing) * c.speed * dt, math.sin(s.facing) * c.speed * dt)
  if not moved or s.rushFor <= 0 or ram(server, s, c.hit, c.damage) then
    s.rushFor = nil
    s.chargeIn = Chassis.between(c.every)
  end
end

function Brain.think(roster, server, s, dt)
  if s.rushFor then
    charge(server, s, dt)
    return
  end
  local tx, ty = Drill.look(roster, server, s, dt)
  if s.charging then -- folding down, aiming at where you stand
    s.charging = s.charging - dt
    if tx then
      s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Chassis.TURN * 0.6, dt)
    end
    if s.charging <= 0 then
      s.charging, s.rushFor = nil, Brain.CHARGE.time
    end
    return
  end
  if tx then
    s.chargeIn = s.chargeIn - dt
    s.shoveIn = s.shoveIn - dt
    local d2 = Chassis.dist2(s.x, s.y, tx, ty)
    if s.chargeIn <= 0 and d2 > 120 * 120 then
      s.charging = Brain.CHARGE.windUp
      return
    end
    s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Chassis.TURN * 0.5, dt) -- the blade at you
    if d2 > (Brain.SHOVE.reach + s.radius) ^ 2 then
      roster:goTo(s, tx, ty, s.conf.speed, dt, false)
    elseif s.shoveIn <= 0 then
      ram(server, s, Brain.SHOVE.reach, Brain.SHOVE.damage)
      s.shoveIn = Brain.SHOVE.every
    end
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
