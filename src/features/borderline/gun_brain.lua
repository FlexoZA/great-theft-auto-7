-- How a gun hauler (GUN) thinks (docs/borderline.md, "The army"):
-- Hyperbole's standard model, a rifle on one arm and a grenade launcher on
-- the other, and drilled. Posted ones stand watch (their cone sweeping
-- across what they guard); squads walk a beat behind their leader. Seeing
-- somebody, one calls the rest near it (army.lua: `s.spotted`).
--
-- In a fight it keeps its distance: it closes in from past `far`, backs off
-- inside `near`, and between the two side-steps back and forth so it is
-- never standing still, firing in bursts. When two or more are after the
-- same player, the second and third swing out to the sides (`FLANK`) so
-- they come at you from more than one way. Every so often it lobs a grenade
-- at you (the grenades feature's), and at where it lost you. Hurt by
-- somebody it can't see, it turns and goes to look. It never goes further
-- than `leash` from its post or beat.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = true

Brain.CONF = {
  health = 70,
  speed = 80, -- px/s in a fight
  walk = 45, -- px/s on its beat
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
  leash = 900, -- px from its post (or wherever its beat is) it will go
}

Brain.SWEEP = math.rad(40) -- a posted one's cone swings this far either side of its watch
Brain.SWEEP_TIME = 5 -- ...there and back in this many seconds
Brain.FLANK = math.rad(70) -- how far round a player the second and third swing out
Brain.FORMATION = { { 0, 0 }, { -40, -32 }, { -40, 32 }, { -80, 0 } } -- slots behind the leader, his frame

function Brain.gun()
  return Chassis.gun("GUN", "ak47", { damage = 8, spread = 0.06 })
end

function Brain.init(s)
  s.side, s.strafeIn = (s.id % 2 == 0) and 1 or -1, 0
  s.lobIn = Chassis.between(Brain.CONF.grenadeEvery) * 0.5
  s.phase = love.math.random() * 2 * math.pi
end

--- A squad of these on `route` (a loop of { x, y }), leader first: each
--- member's `squad`, so they walk it together.
function Brain.formSquad(members, route, start)
  local squad = { route = route, leg = (start or 1) % #route + 1, members = members }
  for _, s in ipairs(members) do
    s.squad, s.state = squad, "beat"
  end
  return squad
end

Brain.wake = Chassis.wake

function Brain.hurt(_roster, s, angle)
  if s.target then
    s.side, s.strafeIn = -s.side, Chassis.between(Brain.CONF.strafe) -- hit: step the other way
  else
    Chassis.shotFromNowhere(s, angle, 300)
  end
end

--- Is `s` this far from home (its post, or its squad leader)?
local function leashed(s)
  local hx, hy = s.homeX, s.homeY
  if s.squad and s.squad.members[1] and s.squad.members[1] ~= s then
    hx, hy = s.squad.members[1].x, s.squad.members[1].y
  end
  return Chassis.dist2(s.x, s.y, hx, hy) > s.conf.leash * s.conf.leash
end

--- Which of those after the same player `s` is: 0 for the first, 1, 2...
local function rank(roster, s)
  local n = 0
  for _, o in ipairs(roster.list) do
    if o ~= s and o.code == s.code and o.target == s.target and o.id < s.id then
      n = n + 1
    end
  end
  return n
end

--- Where `s` wants to stand to fight somebody at (tx, ty): on a ring round
--- them between `near` and `far`, swung out to one side for the flankers.
local function spotToFight(roster, s, tx, ty)
  local conf = s.conf
  local a = math.atan2(s.y - ty, s.x - tx)
  local k = rank(roster, s)
  if k > 0 then
    a = a + Brain.FLANK * (k % 2 == 1 and 1 or -1) * math.ceil(k / 2) * 0.5
  end
  local d = (conf.near + conf.far) / 2
  return tx + math.cos(a) * d, ty + math.sin(a) * d
end

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

local function fight(roster, server, s, tx, ty, dt)
  local conf = s.conf
  local d = math.sqrt(Chassis.dist2(s.x, s.y, tx, ty))
  if leashed(s) then
    roster:goTo(s, s.homeX, s.homeY, conf.walk, dt, false)
  elseif d > conf.far or d < conf.near or rank(roster, s) > 0 then
    local gx, gy = spotToFight(roster, s, tx, ty)
    if Chassis.dist2(s.x, s.y, gx, gy) > 40 * 40 then
      roster:goTo(s, gx, gy, conf.speed, dt, false)
    end
  else
    -- In its band: side-step across the line to you.
    s.strafeIn = s.strafeIn - dt
    if s.strafeIn <= 0 then
      s.side, s.strafeIn = -s.side, Chassis.between(conf.strafe)
    end
    local a = math.atan2(ty - s.y, tx - s.x) + s.side * math.pi / 2
    if not Chassis.move(s, math.cos(a) * conf.speed * 0.6 * dt, math.sin(a) * conf.speed * 0.6 * dt) then
      s.side = -s.side
    end
  end
  roster:shoot(server, s, tx, ty, Brain.gun(), dt)
  maybeLob(server, s, tx, ty, dt)
end

--- A squad member with nobody of its own: after a mate who has somebody,
--- else the leader walks the beat and the rest keep their slots.
local function patrol(roster, s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m ~= s and m.target and m.seenX then
      Brain.wake(s, m.seenX, m.seenY)
      return
    end
  end
  local leader = squad.members[1]
  if leader == s then
    local to = squad.route[squad.leg]
    if Chassis.dist2(s.x, s.y, to.x, to.y) < 24 * 24 then
      squad.leg = squad.leg % #squad.route + 1
      to = squad.route[squad.leg]
    end
    roster:goTo(s, to.x, to.y, s.conf.walk, dt)
    s.homeX, s.homeY = s.x, s.y
    return
  end
  local slot = Brain.FORMATION[1]
  for i, m in ipairs(squad.members) do
    if m == s then
      slot = Brain.FORMATION[(i - 1) % #Brain.FORMATION + 1]
    end
  end
  local c, sn = math.cos(leader.facing), math.sin(leader.facing)
  local gx, gy = leader.x + slot[1] * c - slot[2] * sn, leader.y + slot[1] * sn + slot[2] * c
  local d = math.sqrt(Chassis.dist2(s.x, s.y, gx, gy))
  if d < 6 then
    s.facing = Chassis.turn(s.facing, leader.facing, Chassis.TURN, dt)
  else
    roster:goTo(s, gx, gy, s.conf.walk * math.min(1.8, 0.6 + d / 60), dt) -- catches up when behind
  end
end

function Brain.think(roster, server, s, dt)
  local conf = s.conf
  local wary = s.target or s.state == "search"
  local tx, ty, fresh = roster:track(server, s, wary and conf.alertFov or conf.fov, dt)
  if fresh then
    s.spotted = true
  end
  if tx then
    s.state = "hunt"
    fight(roster, server, s, tx, ty, dt)
    return
  end
  s.aimFor = 0
  if s.state == "hunt" and not s.target then
    s.state, s.t = "search", 0
    if s.seenX then -- a parting gift where it lost you
      s.lobIn = math.min(s.lobIn, 0.8)
    end
  end
  if s.state == "search" and s.seenX then
    if s.t < 1.5 and Chassis.dist2(s.x, s.y, s.seenX, s.seenY) > 200 * 200 then
      maybeLob(server, s, s.seenX, s.seenY, dt)
    end
    local left = roster:goTo(s, s.seenX, s.seenY, conf.speed * 0.8, dt)
    if left < 40 then
      s.facing = s.facing + dt * 1.2
    end
    if s.t > conf.search + (left < 40 and 0 or 6) then
      s.state = s.squad and "beat" or "back"
    end
  elseif s.state == "back" then
    if roster:goTo(s, s.homeX, s.homeY, conf.walk, dt) < 14 then
      s.state = "calm"
    end
  elseif s.squad and s.state == "beat" then
    patrol(roster, s, dt)
  else -- at its post, its cone sweeping across what it watches
    local want = s.watch + Brain.SWEEP * math.sin(2 * math.pi * roster.time / Brain.SWEEP_TIME + s.phase)
    s.facing = Chassis.turn(s.facing, want, Chassis.TURN, dt)
  end
end

--- Off its squad when it goes down: the next one leads.
function Brain.gone(s)
  local squad = s.squad
  for k, m in ipairs(squad and squad.members or {}) do
    if m == s then
      table.remove(squad.members, k)
      return
    end
  end
end

return Brain
