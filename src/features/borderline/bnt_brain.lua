-- How one of BNK-9's corner turrets (BNT) thinks (docs/borderline.md, "8.
-- The Bunker"): a twin gun on a ring bolted to a corner of the flying core.
-- It goes where BNK-9 carries it (bnk_brain.lua moves it with itself: its
-- `mount`, its `corner`), turns to the nearest player it can see and fires
-- bursts. Shot off, it falls to the roof; BNK-9 grows another in its place
-- after a while.
--
-- The trigger is chassis.lua's (`shoot`), the gun a hauler's.

local Features = require("src.features")
local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = false
Brain.RADIUS = 16

Brain.CONF = {
  health = 300,
  range = 750, -- px it sees
  aim = 0.45,
  burst = 5,
  every = 0.12,
  pause = { 1.3, 2.0 },
}

function Brain.gun()
  return Chassis.gun("BNT", "uzi", { damage = 8, spread = 0.06, speed = 900 })
end

function Brain.init(s)
  s.hover = true -- carried in the air over the roof, but in reach of every round (not `flying`)
end

--- The nearest player it can see from up there, and where.
local function nearest(server, s)
  local best, bx, by, bd2
  for _, p in pairs(server.players) do
    if Features.visible(server, p) then
      local x, y = Features.bodyPose(server, p)
      local d2 = Chassis.dist2(x, y, s.x, s.y)
      if d2 <= s.conf.range ^ 2 and (not bd2 or d2 < bd2) and Chassis.lineClear(s.x, s.y, x, y) then
        best, bx, by, bd2 = p, x, y, d2
      end
    end
  end
  return best, bx, by
end

function Brain.think(roster, server, s, dt)
  local who, tx, ty = nearest(server, s)
  if who then
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
  else
    s.aimFor = 0
    s.facing = Chassis.turn(s.facing, s.mount and s.mount.facing or s.facing, Chassis.TURN * 0.5, dt)
  end
end

return Brain
