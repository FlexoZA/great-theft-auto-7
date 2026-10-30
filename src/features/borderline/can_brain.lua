-- How a rim cannon (CAN) behaves (docs/borderline.md, "8. The Bunker"): a
-- heavy gun on a turret round the Bunker's rim. It doesn't need to see
-- you: it lobs its shells over everything. It turns slowly to the nearest
-- player within `range`, charges for `aim` seconds (its muzzle glowing),
-- and lobs a shell at where they stand, which comes down a moment later
-- on a red ring (barrage.lua; owned by nobody, so it never hurts the army).
-- Each fires every few seconds, the first shots staggered, so a few at a
-- time are in the air and the roof is a dance between the rings. It never
-- moves. A turret, so hardly a brain: no posts, no squads, no calls.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")
local Barrage = require("src.features.borderline.barrage")

local Brain = {}

Brain.LEGS = false
Brain.RADIUS = 30

Brain.CONF = {
  health = 120,
  range = 1600, -- across the whole roof
  aware = 1600,
  fov = 2 * math.pi + 1, -- it turns all the way round
  aim = 0.9, -- seconds its muzzle glows before a shell goes
  burst = 1,
  every = 0.2,
  pause = { 4.5, 7.5 }, -- seconds between its shells
  lostAfter = 3,
}

Brain.SHELL = { radius = 75, damage = 26, delay = 1.5, scatter = 45 } -- where it lands: within `scatter` of you
Brain.FIRST = { 1, 6 } -- seconds before its first shell: they don't all go at once
Brain.TURN = 1.6 -- radians a second the turret turns

local MUZZLE = 34 -- px out along the barrel a shell leaves from

function Brain.init(s)
  s.reload = Chassis.between(Brain.FIRST)
end

function Brain.wake() end

function Brain.hurt() end

--- The nearest player it can lob at, and where they are.
local function nearest(server, s)
  local best, bx, by, bd = nil, nil, nil, s.conf.range * s.conf.range
  for id, p in pairs(server.players) do
    if Features.visible(server, p) then
      local px, py = Features.bodyPose(server, p)
      local d = Chassis.dist2(px, py, s.x, s.y)
      if d <= bd then
        best, bx, by, bd = id, px, py, d
      end
    end
  end
  return best, bx, by
end

function Brain.think(_roster, server, s, dt)
  local who, tx, ty = nearest(server, s)
  s.target = who
  if not who then
    s.charging = nil
    return
  end
  s.facing = Chassis.turn(s.facing, math.atan2(ty - s.y, tx - s.x), Brain.TURN, dt)
  s.reload = s.reload - dt
  s.charging = s.reload <= s.conf.aim or nil
  if s.reload > 0 then
    return
  end
  s.reload = Chassis.between(s.conf.pause)
  s.charging = nil
  local sh = Brain.SHELL
  local a, d = love.math.random() * 2 * math.pi, love.math.random() * sh.scatter
  Barrage.serverFire(server, s.x + math.cos(s.facing) * MUZZLE, s.y + math.sin(s.facing) * MUZZLE,
    tx + math.cos(a) * d, ty + math.sin(a) * d, sh.radius, sh.damage, sh.delay)
end

return Brain
