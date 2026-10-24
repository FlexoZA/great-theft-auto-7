-- How a hauler dock (DCK) behaves (docs/borderline.md, "The army"): the
-- charging bay Hyperbole parks its haulers in, a plasma gun on a turret
-- over it guarding the terminal beside it. It turns all the way round and
-- fires plasma in bursts of three (bolts.lua), slow enough to sidestep.
--
-- While anyone is within `WAKE` px (or it has somebody), every `BUILD_EVERY`
-- seconds it builds a fresh junk hauler and sends it out of the bay, up to
-- `CAP` of its own out at once. Shoot it down, or hack the terminal it
-- runs (the map's terminal with the same `dock`; army.lua's
-- `serverShutDock`), and it stops. It never moves. A turret, so hardly a
-- brain: no posts, no squads; it beeps for the rest (`spotted`) when it
-- first sees somebody.

local Chassis = require("src.features.borderline.chassis")
local Bolts = require("src.features.borderline.bolts")
local Junk = require("src.features.borderline.junk_brain")

local Brain = {}

Brain.LEGS = false
Brain.RADIUS = 26

Brain.CONF = {
  health = 300,
  range = 620,
  aware = 620,
  fov = 2 * math.pi + 1, -- it turns all the way round
  aim = 0.7, -- the gun's coils charging
  burst = 3,
  every = 0.22,
  pause = { 1.8, 2.6 },
  lostAfter = 2,
}

Brain.BOLT = { speed = 300, ttl = 2.2, damage = 14, splash = 32 } -- lighter than a plasma hauler's, three at a time
Brain.WAKE = 900 -- px a player comes within to start it building
Brain.BUILD_EVERY = 20 -- seconds between new junk haulers
Brain.CAP = 3 -- of its own out at once
Brain.BAY = 40 -- px out of the bay (south of it) a new hauler steps

local MUZZLE = 30 -- px out front a bolt leaves from

local function fireBolt(server, s, aim)
  Bolts.serverFire(server, s.x + math.cos(aim) * MUZZLE, s.y + math.sin(aim) * MUZZLE, aim, Brain.BOLT)
end

function Brain.gun()
  return fireBolt
end

function Brain.init(s)
  s.buildIn, s.built, s.awake = Brain.BUILD_EVERY / 2, {}, false
end

function Brain.wake(s)
  s.awake = true
end

--- Shot by somebody it hadn't seen: it beeps for the rest.
function Brain.hurt(_roster, s)
  if not s.target then
    s.awake, s.spotted = true, true
  end
end

--- Is any player within `WAKE` of it?
local function near(server, s)
  for _, p in pairs(server.players) do
    if Chassis.visible(server, p) then
      local px, py = Chassis.pose(server, p)
      if Chassis.dist2(px, py, s.x, s.y) <= Brain.WAKE * Brain.WAKE then
        return true
      end
    end
  end
  return false
end

--- How many it built are still out.
local function out(roster, s)
  local alive = {}
  for _, h in ipairs(s.built) do
    if roster:indexOf(h) then
      alive[#alive + 1] = h
    end
  end
  s.built = alive
  return #alive
end

--- A junk hauler out of the bay, sent after whoever the dock is shooting at.
local function build(roster, s)
  local h = roster:add(Junk, "JNK", s.x, s.y + Brain.BAY, math.pi / 2)
  s.built[#s.built + 1] = h
  if s.seenX then
    Junk.wake(h, s.seenX, s.seenY)
  end
end

function Brain.think(roster, server, s, dt)
  local tx, ty, fresh = roster:track(server, s, s.conf.fov, dt)
  if fresh then
    s.spotted = true
  end
  if tx then
    roster:shoot(server, s, tx, ty, fireBolt, dt)
  else
    s.aimFor = 0
  end
  if s.target or near(server, s) then
    s.awake = true
  end
  if not s.awake then
    return
  end
  s.buildIn = s.buildIn - dt
  if s.buildIn <= 0 then
    s.buildIn = Brain.BUILD_EVERY
    if out(roster, s) < Brain.CAP then
      build(roster, s)
    end
  end
end

return Brain
