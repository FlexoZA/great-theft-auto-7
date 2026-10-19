-- How Hyperbole's drilled models behave (docs/borderline.md, "The army"):
-- the gun, rocket, plasma and jet haulers all stand watch and walk beats
-- the same way, and keep their distance in a fight the same way; what they
-- shoot is each one's own brain (gun_brain.lua, rpg_brain.lua, ...).
--
-- Out of a fight (`Drill.idle`): posted ones stand watch, their cone
-- sweeping across what they guard; squads walk a beat behind their leader,
-- and go with any of them who has somebody; one that lost somebody walks
-- to where it saw them, looks about, and goes back to its post or squad.
--
-- In one (`Drill.band`): it closes in from past its `far`, backs off inside
-- its `near`, and between the two side-steps back and forth so it is never
-- standing still. When two or more of a model are after the same player,
-- the second and third swing out to the sides (`FLANK`) so they come at
-- you from more than one way. It never goes further than `leash` from its
-- post or its squad.
--
-- Their numbers (in each brain's CONF): walk, speed, far, near, strafe,
-- leash, search.

local Chassis = require("src.features.borderline.chassis")

local Drill = {}

Drill.SWEEP = math.rad(40) -- a posted one's cone swings this far either side of its watch
Drill.SWEEP_TIME = 5 -- ...there and back in this many seconds
Drill.FLANK = math.rad(70) -- how far round a player the second and third swing out
Drill.FORMATION = { { 0, 0 }, { -40, -32 }, { -40, 32 }, { -80, 0 } } -- slots behind the leader, his frame

--- Set up a drilled one (its brain's `init` calls this).
function Drill.init(s)
  s.side, s.strafeIn = (s.id % 2 == 0) and 1 or -1, 0
  s.phase = love.math.random() * 2 * math.pi
end

--- A squad of these on `route` (a loop of { x, y }), leader first: each
--- member's `squad`, so they walk it together.
function Drill.formSquad(members, route, start)
  local squad = { route = route, leg = (start or 1) % #route + 1, members = members }
  for _, s in ipairs(members) do
    s.squad, s.state = squad, "beat"
  end
  return squad
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
    a = a + Drill.FLANK * (k % 2 == 1 and 1 or -1) * math.ceil(k / 2) * 0.5
  end
  local d = (conf.near + conf.far) / 2
  return tx + math.cos(a) * d, ty + math.sin(a) * d
end

--- Keep `s` at its distance from somebody at (tx, ty): see the top.
function Drill.band(roster, s, tx, ty, dt)
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
end

--- Look about, a few times a second (chassis' `track`), with a wider
--- cone once on edge; seeing somebody new, it calls the rest (army.lua
--- reads `spotted`). Returns where its target is while it can see them.
function Drill.look(roster, server, s, dt)
  local conf = s.conf
  local wary = s.target or s.state == "search"
  local tx, ty, fresh = roster:track(server, s, wary and conf.alertFov or conf.fov, dt)
  if fresh then
    s.spotted = true
  end
  if tx then
    s.state = "hunt"
  end
  return tx, ty
end

--- Hit: in a fight it steps the other way; caught unawares it turns round
--- and goes to look where the round came from.
function Drill.hurt(_roster, s, angle)
  if s.target then
    s.side, s.strafeIn = -s.side, Chassis.between(s.conf.strafe)
  else
    Chassis.shotFromNowhere(s, angle, 300)
  end
end

--- A squad member with nobody of its own: after a mate who has somebody,
--- else the leader walks the beat and the rest keep their slots.
local function patrol(roster, s, dt)
  local squad = s.squad
  for _, m in ipairs(squad.members) do
    if m ~= s and m.target and m.seenX then
      Chassis.wake(s, m.seenX, m.seenY)
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
  local slot = Drill.FORMATION[1]
  for i, m in ipairs(squad.members) do
    if m == s then
      slot = Drill.FORMATION[(i - 1) % #Drill.FORMATION + 1]
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

--- `s` with nobody in sight: after whoever it just lost, back to its post,
--- on its beat, or standing watch (see the top). Returns true for the
--- first tick after it lost somebody.
function Drill.idle(roster, s, dt)
  local conf = s.conf
  s.aimFor = 0
  local lost = false
  if s.state == "hunt" and not s.target then
    s.state, s.t, lost = "search", 0, true
  end
  if s.state == "search" and s.seenX then
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
    local want = s.watch + Drill.SWEEP * math.sin(2 * math.pi * roster.time / Drill.SWEEP_TIME + s.phase)
    s.facing = Chassis.turn(s.facing, want, Chassis.TURN, dt)
  end
  return lost
end

--- Off its squad when it goes down: the next one leads.
function Drill.gone(s)
  local squad = s.squad
  for k, m in ipairs(squad and squad.members or {}) do
    if m == s then
      table.remove(squad.members, k)
      return
    end
  end
end

return Drill
