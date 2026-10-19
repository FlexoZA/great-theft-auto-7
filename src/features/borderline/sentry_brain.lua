-- How a sentry (SEN) behaves (docs/borderline.md, "The army"): a yellow
-- turret in a hatch, flush with the floor, and out of reach there (`sunk`).
-- When a player comes within `WAKE` px it rises (`rise` 0..1, half a
-- second), turns to whoever it sees and fires in bursts; with nobody in
-- sight for `SINK_AFTER` seconds it sinks back. It never moves. A turret,
-- so hardly a brain: no posts, no squads, no calls.

local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = false
Brain.RADIUS = 14

Brain.CONF = {
  health = 90,
  range = 560,
  aware = 560,
  fov = 2 * math.pi + 1, -- it turns all the way round
  aim = 0.4,
  burst = 4,
  every = 0.1,
  pause = { 1.2, 1.8 },
  lostAfter = 2,
}

Brain.WAKE = 450 -- px a player comes within to bring it up
Brain.RISE = 0.5 -- seconds to come up (or go down)
Brain.SINK_AFTER = 6

function Brain.gun()
  return Chassis.gun("SEN", "ak47", { damage = 7, spread = 0.07 })
end

function Brain.init(s)
  s.rise, s.sunk, s.quiet = 0, true, 0
end

function Brain.wake() end

function Brain.hurt() end

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

function Brain.think(roster, server, s, dt)
  local up = s.rise >= 1
  local tx, ty = nil, nil
  if up then
    tx, ty = roster:track(server, s, s.conf.fov, dt)
  end
  if tx then
    s.quiet = 0
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
  else
    s.quiet = s.quiet + dt
    s.aimFor = 0
  end
  -- Up while somebody is near, or for a while after it last saw anyone.
  local want = near(server, s) or (s.rise > 0 and s.quiet < Brain.SINK_AFTER)
  s.rise = math.max(0, math.min(1, s.rise + (want and dt or -dt) / Brain.RISE))
  s.sunk = s.rise < 1
  if s.rise <= 0 then
    s.target, s.quiet = nil, Brain.SINK_AFTER
  end
end

return Brain
