-- How a junk hauler (JNK) thinks (docs/borderline.md, "The army"): the
-- cheapest thing Hyperbole ever built, and it knows it. They come in packs,
-- standing about a spot picking over whatever is there (the train wreck),
-- and the first one to see somebody wakes the lot (army.lua: `s.spotted`).
-- Then they walk straight at you, plinking with their pistols, no cover and
-- no plan, until they are close; lose you and they wander over to where you
-- were, mill about, and settle there. Hurt by somebody they can't see, they
-- turn and go that way.
--
-- One climbing out of the wreck to feed the Knuckle Scrapper (`feed`, set
-- by scrapper.lua) does nothing else: it carries its scrap straight to it,
-- whoever shoots at it, until it is pulled in or the Scrapper is gone.
--
-- The body (walking, sight, the trigger, the torso crawl) is chassis.lua's.

local Chassis = require("src.features.borderline.chassis")

local Brain = {}

Brain.LEGS = true -- it can lose them (the torso crawl)

Brain.CONF = {
  health = 30,
  speed = 105, -- px/s after somebody
  mill = 22, -- px/s picking about its spot
  millRange = 70, -- px round its spot it picks about in
  range = 480, -- px it sees and shoots
  aware = 150, -- px all round it hears you
  fov = math.rad(100),
  close = 170, -- px it walks in to
  aim = 0.6,
  burst = 2,
  every = 0.35,
  pause = { 0.8, 1.6 },
  search = 6, -- seconds it looks about where it lost you
  lostAfter = 2.5,
}

function Brain.gun()
  return Chassis.gun("JNK", "pistol", { damage = 6, spread = 0.14 })
end

function Brain.init(s)
  s.millX, s.millY, s.millIn = s.x, s.y, 0
end

Brain.wake = Chassis.wake

function Brain.hurt(_roster, s, angle)
  Chassis.shotFromNowhere(s, angle, 220)
end

function Brain.think(roster, server, s, dt)
  local conf = s.conf
  if s.feed and s.feed.dead then
    s.feed = nil
  end
  if s.feed then
    roster:goTo(s, s.feed.x, s.feed.y, conf.speed, dt)
    return
  end
  local tx, ty, fresh = roster:track(server, s, conf.fov, dt)
  if fresh then
    s.spotted = true
  end
  if tx then
    s.state = "hunt"
    if Chassis.dist2(s.x, s.y, tx, ty) > conf.close * conf.close then
      roster:goTo(s, tx, ty, conf.speed, dt, false)
    end
    roster:shoot(server, s, tx, ty, Brain.gun(), dt)
    return
  end
  s.aimFor = 0
  if s.state == "hunt" and not s.target then
    s.state, s.t = "search", 0
  end
  if s.state == "search" and s.seenX then
    local left = roster:goTo(s, s.seenX, s.seenY, conf.speed * 0.8, dt)
    if left < 40 then
      s.facing = s.facing + dt * 1.5 -- looking about
    end
    if s.t > conf.search + (left < 40 and 0 or 6) then
      s.state, s.homeX, s.homeY = "calm", s.x, s.y -- it settles where it gave up
      Brain.init(s)
    end
    return
  end
  -- Calm: shuffling about its spot, picking at things.
  s.millIn = s.millIn - dt
  if s.millIn <= 0 then
    local a, d = love.math.random() * 2 * math.pi, love.math.random() * conf.millRange
    s.millX, s.millY = s.homeX + math.cos(a) * d, s.homeY + math.sin(a) * d
    s.millIn = 2 + love.math.random() * 3
  end
  roster:goTo(s, s.millX, s.millY, conf.mill, dt)
end

return Brain
