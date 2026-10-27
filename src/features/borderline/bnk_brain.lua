-- BNK-9's brain (BNK), on the host: the Bunker's boss and the line's last
-- (docs/borderline.md, "The bosses"), the bunker's flying core: a slab of
-- armour on four engines with a huge red eye at its front. It is one of the
-- army's (army.lua runs it with the rest, so rounds reach it the same way),
-- a boss with the boss bar; a machine in the air, so no breath (the
-- Hunter-Chopper's rule), no medkits and nothing to walk out from under.
-- How it rises out of the eye's hatch, the laser's beam on every screen and
-- its crash are bnk9.lua's; how it looks bnk_look.lua's.
--
-- It hovers over everything on the roof (`hover`: drawn up there, its
-- shadow on the deck, but in reach of every round), by turns:
--
--   fly    off to somewhere new over the roof (FLY.speed), not too near
--          where it was, nearer whoever it is after
--   park   it holds there (PARK.time), turning its eye on the nearest
--          player, and fires: a spread of mines (mines.lua) round them,
--          then the eye laser
--
-- Its moves, each with a tell:
--
--   mines  its launchers thunk and MINES.count mines come down round you
--          (they arm on landing; step near one and it beeps, then blows)
--   laser  its eye charges (LASER.aim: a red line from it to you, which
--          follows you for the first part and then sets), then the beam
--          (LASER.beam seconds): whoever is in it burns (`fire`), up to
--          the first thing solid
--
-- And all the while its four corner turrets (bnt_brain.lua, army models of
-- their own it carries) shoot at whoever they can see. One shot off grows
-- back TURRETS.back seconds later. Its eye is the weak spot: a hit on it
-- does EYE.taken times the damage (`taken`). Below half its health
-- (FURY) it flies faster, parks shorter and grows its turrets back sooner.
-- What the others should see it puts on `s.events` for bnk9.lua to send.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Kit = require("src.features.borderline.boss_kit")
local Mines = require("src.features.borderline.mines")
local Bosses = require("src.features.bosses")
local Turret = require("src.features.borderline.bnt_brain")

local Brain = {}

Brain.LEGS = false -- no torso crawl: it comes down whole
Brain.BOSS = true -- army.lua: its kill is a boss's
Brain.RADIUS = 64 -- (its look is drawn to match: bnk_look.lua)

Brain.HEALTH = 6000 -- for one player (more humans, more: bosses/init.lua)
Brain.CONF = {
  health = Brain.HEALTH, -- (bnk9.lua sets its real health as it rises)
  range = 1400, -- px it sees, from up there
}

-- px/s (`fury` below half); it goes `min` px or more from where it was, ending up about `off` px from them.
Brain.FLY = { speed = 150, fury = 215, min = 260, off = 380 }
Brain.PARK = { time = 7, fury = 4.5 }
Brain.MINES = { count = 3, spread = 140, windUp = 0.5, at = 1.0 } -- `at` seconds into a park
-- The laser: `aim` seconds lining up (following for `follow` of them), then
-- `beam` seconds at `dps` (`fire`) along a beam `width` across, at most
-- `length` long; `at` seconds into a park.
Brain.LASER = { aim = 1.0, follow = 0.6, beam = 1.2, dps = 70, width = 26, length = 1400, at = 2.6 }
Brain.EYE = { ahead = 46, r = 22, taken = 2 } -- px ahead of its middle; how big; what a hit on it is worth
-- Where its turrets ride: (x, y) in its own frame, its front +x.
Brain.CORNERS = { { 40, -44 }, { 40, 44 }, { -44, -44 }, { -44, 44 } }
Brain.TURRETS = { back = 16, fury = 10 }
Brain.FURY = 0.5 -- of its health, where it gets faster

local random = love.math.random

function Brain.init(s)
  s.events, s.turrets, s.turretBack = {}, {}, {}
  s.hover = true
  s.power = Bosses.power()
  s.mode, s.modeT = "park", 0 -- it rises out of the hatch to park over it
end

--- Gone (army.lua's `down`): bnk9.lua reads it.
function Brain.gone(s)
  s.dead = true
end

--- Where its eye is now.
function Brain.eye(s)
  return s.x + math.cos(s.facing) * Brain.EYE.ahead, s.y + math.sin(s.facing) * Brain.EYE.ahead
end

--- What a hit at (x, y) on it is worth: double on its eye (chassis.lua's hurt).
function Brain.taken(s, x, y)
  if not x then
    return 1
  end
  local ex, ey = Brain.eye(s)
  return Chassis.dist2(x, y, ex, ey) <= (Brain.EYE.r + 8) ^ 2 and Brain.EYE.taken or 1
end

--- Its turrets where its corners are now; one shot off comes back after a while.
local function turrets(roster, s, dt)
  local ca, sa = math.cos(s.facing), math.sin(s.facing)
  local back = s.fury and Brain.TURRETS.fury or Brain.TURRETS.back
  for i, c in ipairs(Brain.CORNERS) do
    local x, y = s.x + ca * c[1] - sa * c[2], s.y + sa * c[1] + ca * c[2]
    local t = s.turrets[i]
    if t and not roster:indexOf(t) then -- shot off
      s.turrets[i], s.turretBack[i] = nil, back
      t = nil
    end
    if t then
      t.x, t.y = x, y
    else
      s.turretBack[i] = (s.turretBack[i] or 0) - dt
      if s.turretBack[i] <= 0 then
        t = roster:add(Turret, "BNT", x, y, s.facing)
        t.x, t.y = x, y -- (where it is bolted on, not a clear spot on the deck)
        t.mount, t.corner = s, i
        s.turrets[i] = t
        if s.modeT > 0 then -- (the first four come with it)
          s.events[#s.events + 1] = { "turret", x, y }
        end
      end
    end
  end
end

--- Where to fly to next: over the roof, `FLY.min` or more from here, and
--- of the spots it tries the one nearest FLY.off from (tx, ty).
local function nextSpot(s, b, tx, ty)
  local best, bx, by
  for _ = 1, 10 do
    local x, y = b.x0 + random() * (b.x1 - b.x0), b.y0 + random() * (b.y1 - b.y0)
    if Chassis.dist2(x, y, s.x, s.y) >= Brain.FLY.min ^ 2 then
      local score = tx and math.abs(math.sqrt(Chassis.dist2(x, y, tx, ty)) - Brain.FLY.off) or 0
      if not best or score < best then
        best, bx, by = score, x, y
      end
    end
  end
  return bx or (b.x0 + b.x1) / 2, by or (b.y0 + b.y1) / 2
end

--- Where its laser's beam ends: along `angle` from (x, y), at the first
--- thing solid or LASER.length.
local function beamEnd(x, y, angle)
  local ux, uy = math.cos(angle), math.sin(angle)
  local d = 0
  while d < Brain.LASER.length do
    d = d + 16
    if Features.any("blocksShot", x + ux * d, y + uy * d) then
      break
    end
  end
  return x + ux * d, y + uy * d, d
end

--- Is (px, py) in the beam from (x, y) along `angle`, `length` long?
local function inBeam(px, py, x, y, angle, length)
  local ux, uy = math.cos(angle), math.sin(angle)
  local along = (px - x) * ux + (py - y) * uy
  local across = math.abs(-(px - x) * uy + (py - y) * ux)
  return along >= 0 and along <= length and across <= Brain.LASER.width / 2 + 10
end

--- The laser, a tick of it: lining up, then the beam.
local function laser(server, s, who, tx, ty, dt)
  local L = s.laser
  L.t = L.t + dt
  local ex, ey = Brain.eye(s)
  if L.t < Brain.LASER.follow and who then
    L.angle = math.atan2(ty - ey, tx - ex)
  end
  s.facing = Chassis.turn(s.facing, L.angle, Chassis.TURN * 1.5, dt) -- its eye on the line: the red line is it
  if L.t < Brain.LASER.aim then
    return
  end
  if not L.firing then
    L.firing = true
    local _, _, len = beamEnd(ex, ey, L.angle)
    L.length = len
    s.events[#s.events + 1] = { "beam", ex, ey, L.angle, len, Brain.LASER.beam }
  end
  L.burnIn = (L.burnIn or 0) - dt
  if L.burnIn <= 0 then
    L.burnIn = 0.2
    local weapons = Features.byName.weapons
    for _, p in pairs(server.players) do
      if weapons and weapons.serverDamage and Features.visible(server, p) then
        local px, py = Features.bodyPose(server, p)
        if inBeam(px, py, ex, ey, L.angle, L.length) then
          weapons:serverDamage(server, p, nil, math.floor(Brain.LASER.dps * 0.2 * s.power + 0.5), L.angle, "fire")
        end
      end
    end
  end
  if L.t >= Brain.LASER.aim + Brain.LASER.beam then
    s.laser, s.charging = nil, nil
  end
end

--- Its mines, round (tx, ty).
local function mines(server, s, tx, ty)
  local M = Brain.MINES
  for k = 1, M.count do
    local a, d = random() * 2 * math.pi, k == 1 and 30 or M.spread * (0.5 + 0.5 * random())
    local x, y = tx + math.cos(a) * d, ty + math.sin(a) * d
    if not Chassis.blocked(x, y) then
      Mines.serverLay(server, s.x, s.y, x, y)
    end
  end
end

function Brain.think(roster, server, s, dt)
  if not s.fury and s.hp <= s.max * Brain.FURY then
    s.fury = true
    s.events[#s.events + 1] = { "fury" }
  end
  turrets(roster, s, dt)
  s.modeT = s.modeT + dt
  local who, tx, ty = Kit.target(server, s)
  local b = s.bounds
  if s.laser then
    laser(server, s, who, tx, ty, dt)
    return
  end
  if s.mode == "fly" then
    local dx, dy = s.toX - s.x, s.toY - s.y
    local d = math.sqrt(dx * dx + dy * dy)
    local speed = s.fury and Brain.FLY.fury or Brain.FLY.speed
    if d <= speed * dt then
      s.x, s.y = s.toX, s.toY
      s.mode, s.modeT, s.minesDone, s.laserDone = "park", 0, nil, nil
    else
      s.x, s.y = s.x + dx / d * speed * dt, s.y + dy / d * speed * dt
      s.facing = Chassis.turn(s.facing, math.atan2(dy, dx), Chassis.TURN * 0.4, dt)
    end
    return
  end
  -- Parked: its eye on them, the mines, then the laser, then off again.
  if who then
    s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Chassis.TURN * 0.4, dt)
  end
  if who and not s.minesDone and s.modeT >= Brain.MINES.at then
    s.minesDone = true
    mines(server, s, tx, ty)
  end
  if who and not s.laserDone and s.modeT >= Brain.LASER.at then
    s.laserDone, s.charging = true, true
    s.laser = { t = 0, angle = s.facing }
    local ex, ey = Brain.eye(s)
    s.laser.angle = math.atan2(ty - ey, tx - ex)
    s.events[#s.events + 1] = { "aim", Brain.LASER.aim, Brain.LASER.follow }
    return
  end
  if s.modeT >= (s.fury and Brain.PARK.fury or Brain.PARK.time) and b then
    s.toX, s.toY = nextSpot(s, b, tx, ty)
    s.mode, s.modeT = "fly", 0
  end
end

return Brain
