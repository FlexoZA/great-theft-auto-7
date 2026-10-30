-- How a kamikaze hauler (EXP) thinks (docs/borderline.md, "The army"):
-- stripped to the frame, no arms, a red core in its chest. It stands about
-- with its pack until somebody comes into sight, then sprints straight at
-- the nearest one, its core blinking faster the closer it gets
-- (`charging` from `WARN` px: everyone sees it), and goes off when it
-- reaches them. Killed on the way, it goes off all the same where it fell,
-- and that blast hurts its own side too (army.lua asks `Brain.burst`): so
-- shoot it while it is still among its friends.
--
-- The body (walking, sight) is chassis.lua's. It has no legs to lose: no
-- torso crawl, it just blows.

local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = false

Brain.CONF = {
  health = 40,
  speed = 150, -- px/s at you: a sprint is 170, so you can only just keep ahead
  mill = 20,
  range = 520,
  aware = 160,
  fov = math.rad(110),
  aim = 0, -- (no gun)
  search = 4,
  lostAfter = 2,
}

Brain.REACH = 60 -- px from you it goes off
Brain.WARN = 220 -- px from you its core starts racing
Brain.BLAST = { radius = 120, damage = 45, type = "explosive" }

function Brain.init(s)
  s.millX, s.millY = s.x, s.y
end

Brain.wake = Chassis.wake

function Brain.hurt(_roster, s, angle)
  Chassis.shotFromNowhere(s, angle, 260)
end

--- It always goes off, however it went down.
function Brain.burst()
  return Brain.BLAST
end

function Brain.think(roster, server, s, dt)
  local conf = s.conf
  local tx, ty, fresh = roster:track(server, s, conf.fov, dt)
  if fresh then
    s.spotted = true
  end
  s.charging = nil
  if tx then
    s.state = "hunt"
    local d = roster:goTo(s, tx, ty, conf.speed, dt)
    if d <= Brain.WARN then
      s.charging = 1 - d / Brain.WARN
    end
    if d <= Brain.REACH then
      s.detonate = true -- army.lua sets it off
    end
    return
  end
  if s.state ~= "calm" and s.seenX then
    if roster:goTo(s, s.seenX, s.seenY, conf.speed * 0.6, dt) < 30 or s.t > conf.search + 6 then
      s.state, s.homeX, s.homeY = "calm", s.x, s.y
    end
    return
  end
  roster:goTo(s, s.homeX, s.homeY, conf.mill, dt)
end

return Brain
