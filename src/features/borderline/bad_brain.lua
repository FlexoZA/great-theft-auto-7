-- How a badass hauler (BAD) thinks (docs/borderline.md, "The army"): the
-- elite. Big, black and yellow, horns either side of its eye, a war cannon
-- on each arm and rocket pods on its back. It stands watch and keeps its
-- distance like any drilled model (drill.lua), but it doesn't mind you
-- close: its band is short.
--
--   cannons  bursts of shells, one arm then the other, each a small blast
--   pods     a rocket hauler's volley (rpg_brain.lua's), more of them
--   stomp    come too close and it rears up (`charging`) and stamps: the
--            ground round it knocks everyone down (`impact`)
--
-- One or two a map from Prosperity on. The body (walking, sight, the
-- trigger, the torso crawl) is chassis.lua's.

local Protocol = require("src.net.protocol")
local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Drill = require("src.features.borderline.drill")
local Rpg = require("src.features.borderline.rpg_brain")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 450,
  speed = 85,
  walk = 55,
  range = 700,
  aware = 200,
  fov = math.rad(90),
  alertFov = math.rad(130),
  far = 380,
  near = 160,
  strafe = { 1.6, 3 },
  aim = 0.6,
  burst = 3,
  every = 0.18,
  pause = { 1.4, 2.2 },
  search = 6,
  lostAfter = 3,
  leash = 700,
  -- Its pods (rpg_brain.lua's volley).
  volleyEvery = { 9, 12 },
  windUp = 0.9,
  volley = 6,
  volleySpread = 120,
  volleyRadius = 80,
  volleyDamage = 26,
  volleyDelay = 1.1,
  volleyStagger = 0.12,
}

Brain.STOMP = { reach = 110, damage = 25, windUp = 0.5, every = 4 } -- reach: px round it

function Brain.gun()
  return Chassis.gun("BAD", "rocket", {
    speed = 640, ttl = 1.1, blast = { radius = 45, damage = 14, soft = 0 },
  })
end

function Brain.init(s)
  Drill.init(s)
  s.volleyIn = Chassis.between(Brain.CONF.volleyEvery) * 0.6
  s.stompIn = 0
end

Brain.formSquad = Drill.formSquad
Brain.wake = Chassis.wake
Brain.gone = Drill.gone
Brain.hurt = Drill.hurt

--- The stamp: everyone round it knocked flat (HYP_STOMP: army.lua's sound).
local function stomp(server, s)
  local weapons = Features.byName.weapons
  server:broadcast(Protocol.encode("HYP_STOMP", s.id))
  if not (weapons and weapons.serverDamage) then
    return
  end
  for _, p in pairs(server.players) do
    if Chassis.visible(server, p) then
      local px, py = Chassis.pose(server, p)
      if Chassis.dist2(px, py, s.x, s.y) <= Brain.STOMP.reach * Brain.STOMP.reach then
        weapons:serverDamage(server, p, nil, Brain.STOMP.damage, math.atan2(py - s.y, px - s.x), "impact")
      end
    end
  end
end

--- Done winding up: the move it was winding up for.
local function release(server, s)
  if s.move == "stomp" then
    stomp(server, s)
    s.stompIn = Brain.STOMP.every
  elseif s.lastX then
    Rpg.volley(server, s, s.lastX, s.lastY, s.conf)
    s.volleyIn = Chassis.between(s.conf.volleyEvery)
  end
  s.charging, s.move = nil, nil
end

function Brain.think(roster, server, s, dt)
  local tx, ty = Drill.look(roster, server, s, dt)
  if s.charging then
    s.charging = s.charging - dt
    if tx then
      s.lastX, s.lastY = tx, ty
    end
    if s.charging <= 0 then
      release(server, s)
    end
    return
  end
  if tx then
    s.volleyIn, s.stompIn = s.volleyIn - dt, s.stompIn - dt
    local reach = Brain.STOMP.reach * 0.8
    if s.stompIn <= 0 and Chassis.dist2(s.x, s.y, tx, ty) <= reach * reach then
      s.charging, s.move = Brain.STOMP.windUp, "stomp"
      return
    elseif s.volleyIn <= 0 then
      s.charging, s.move, s.lastX, s.lastY = s.conf.windUp, "volley", tx, ty
      return
    end
    Drill.band(roster, s, tx, ty, dt)
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    return
  end
  Drill.idle(roster, s, dt)
end

return Brain
