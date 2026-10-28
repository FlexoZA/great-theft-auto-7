-- The Citadel at work (city-map's `citadel`): its computers ticking over and
-- the Combine's repair drones flying round fixing things. All of it is
-- scenery, on every machine on its own: nothing here is sent, solid or hit.
--
--   the computers  the terminals' and the computer banks' screens and lights
--                  (city-map's citadel.lua places them, render_citadel.lua
--                  draws them still), drawn under everyone: lights blinking
--                  along each bank's front, a line scrolling down each
--                  terminal's screen and a cursor blinking on it.
--   the drones     small round drones flying from one job to the next near
--                  it: a computer, a pillar down in the drop, the struts
--                  under a catwalk. At each they hover a few seconds,
--                  welding, a beam from the lens and sparks off the job.
--                  Drawn over everyone, their shadows on the floor under them.
--
-- citadel.lua passes its hooks on to this module.

local Features = require("src.features")

local Upkeep = {}

-- Tuning ------------------------------------------------------------------
Upkeep.perDrone = 2 -- one drone for every this many jobs...
Upkeep.maxDrones = 30 -- ...and no more than this
Upkeep.speed = { 110, 170 } -- px/s a drone flies at, slowest to fastest
Upkeep.work = { 2.5, 6 } -- seconds spent at a job
Upkeep.reach = 1400 -- px: the next job is one this close, when there is one
Upkeep.sparkRate = 30 -- sparks a second off a job being welded
Upkeep.maxSparks = 500
Upkeep.size = 1.3 -- how big a drone is drawn

local GLOW = { 0.40, 0.80, 1.00 }
local WARM = { 1.00, 0.55, 0.20 }

local state = nil -- { map, jobs, drones, sparks, time } for the map it was built for

local function hash(n)
  local v = math.sin(n) * 43758.5453
  return v - math.floor(v)
end

local function rand(lo, hi)
  return lo + love.math.random() * (hi - lo)
end

--- Every job a drone could fly to on `map`: { x, y }.
local function jobs(map)
  local list = {}
  for _, s in ipairs(map.cover or {}) do
    if s.kind == "bank" then
      for k = 0.25, 0.8, 0.5 do -- a job at either end of a long row
        list[#list + 1] = { x = s.x + s.w * (s.w > s.h and k or 0.5), y = s.y + s.h * (s.w > s.h and 0.5 or k) }
      end
    elseif s.kind == "console" then
      list[#list + 1] = { x = s.x + s.w / 2, y = s.y + s.h / 2 }
    end
  end
  for _, b in ipairs(map.backdrop or {}) do
    if b.kind == "pillar" then
      list[#list + 1] = { x = b.x + b.w / 2, y = b.y + b.h / 2 }
    end
  end
  for _, w in ipairs(map.catwalks or {}) do -- the struts under each edge
    if w.w > w.h then
      for x = w.x + 120, w.x + w.w - 120, 440 do
        list[#list + 1] = { x = x + 30, y = w.y + w.h + 30 }
      end
    else
      for y = w.y + 120, w.y + w.h - 120, 440 do
        list[#list + 1] = { x = w.x + w.w + 30, y = y + 40 }
      end
    end
  end
  return list
end

--- A job near (x, y) for a drone to go on to, not the one it is at.
local function nextJob(s, x, y, at)
  local near = {}
  for _, j in ipairs(s.jobs) do
    if j ~= at and (j.x - x) ^ 2 + (j.y - y) ^ 2 < Upkeep.reach ^ 2 then
      near[#near + 1] = j
    end
  end
  if #near == 0 then
    near = s.jobs
  end
  return near[love.math.random(1, #near)]
end

local function build(map)
  local s = { map = map, jobs = jobs(map), drones = {}, sparks = {}, time = 0 }
  if #s.jobs == 0 then
    return s
  end
  local n = math.min(Upkeep.maxDrones, math.ceil(#s.jobs / Upkeep.perDrone))
  for i = 1, n do
    local at = s.jobs[love.math.random(1, #s.jobs)]
    s.drones[i] = {
      x = at.x, y = at.y, angle = rand(0, 2 * math.pi), job = at,
      working = rand(0, Upkeep.work[2]), -- not all of them setting off at once
      speed = rand(Upkeep.speed[1], Upkeep.speed[2]), seed = i * 7.31,
    }
  end
  return s
end

local function cityMap()
  local city = Features.byName["city-map"]
  return city and city.current == "citadel" and city.map or nil
end

-- Where a drone hangs over its job while it works: just off it, so the
-- beam shows.
local HOVER_X, HOVER_Y = -14, -26

local function turnTo(a, target, rate)
  local d = (target - a + math.pi) % (2 * math.pi) - math.pi
  return a + math.max(-rate, math.min(rate, d))
end

function Upkeep.update(dt)
  local map = cityMap()
  if not map then
    state = nil
    return
  end
  if not state or state.map ~= map then
    state = build(map)
  end
  local s = state
  s.time = s.time + dt
  for _, d in ipairs(s.drones) do
    local tx, ty = d.job.x + HOVER_X, d.job.y + HOVER_Y
    if d.working then
      d.working = d.working - dt
      d.angle = turnTo(d.angle, math.atan2(d.job.y - d.y, d.job.x - d.x), 4 * dt)
      -- Sparks off the job, flying every way and fading.
      if love.math.random() < Upkeep.sparkRate * dt and #s.sparks < Upkeep.maxSparks then
        for _ = 1, love.math.random(1, 3) do
          local a, v = rand(0, 2 * math.pi), rand(40, 140)
          s.sparks[#s.sparks + 1] = { x = d.job.x, y = d.job.y, vx = math.cos(a) * v, vy = math.sin(a) * v,
            t = 0, life = rand(0.2, 0.55) }
        end
      end
      if d.working <= 0 then
        d.working, d.job = nil, nextJob(s, d.x, d.y, d.job)
      end
    else
      local dx, dy = tx - d.x, ty - d.y
      local dist = math.sqrt(dx * dx + dy * dy)
      if dist < 4 then
        d.working = rand(Upkeep.work[1], Upkeep.work[2])
      else
        -- Ease in to the job; drift a little side to side on the way.
        local v = math.min(d.speed, dist * 1.5 + 20) * dt
        local wob = math.sin(s.time * 1.7 + d.seed) * 0.25
        local ux, uy = dx / dist, dy / dist
        d.x = d.x + (ux - uy * wob) * math.min(v, dist)
        d.y = d.y + (uy + ux * wob) * math.min(v, dist)
        d.angle = turnTo(d.angle, math.atan2(dy, dx), 3 * dt)
      end
    end
  end
  for i = #s.sparks, 1, -1 do
    local p = s.sparks[i]
    p.t = p.t + dt
    if p.t >= p.life then
      table.remove(s.sparks, i)
    else
      p.x, p.y = p.x + p.vx * dt, p.y + p.vy * dt
      p.vx, p.vy = p.vx * (1 - 3 * dt), p.vy * (1 - 3 * dt)
    end
  end
end

--- The computers' lights and screens, under everyone.
function Upkeep.drawBelowCars()
  local s = state
  if not s then
    return
  end
  local t = s.time
  for _, c in ipairs(s.map.cover) do
    if c.kind == "bank" then
      -- A light every 9 px along the front, each blinking at its own rate:
      -- mostly the Combine's blue, some amber, the odd one red.
      local across = c.w > c.h
      local len = across and c.w or c.h
      local fx, fy -- the middle of the front strip
      if c.side == "top" then
        fx, fy = c.x, c.y + c.h - 5.5
      elseif c.side == "bottom" then
        fx, fy = c.x, c.y + 5.5
      elseif c.side == "left" then
        fx, fy = c.x + c.w - 5.5, c.y
      else
        fx, fy = c.x + 5.5, c.y
      end
      for k = 6, len - 6, 9 do
        local h = hash(c.seed + k * 0.37)
        local on = math.sin(t * (1 + h * 6) + h * 40) > -0.2 + h * 0.6
        if on then
          if h < 0.06 then
            love.graphics.setColor(1, 0.25, 0.2, 0.95)
          elseif h < 0.3 then
            love.graphics.setColor(WARM[1], WARM[2], WARM[3], 0.9)
          else
            love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.95)
          end
          local x, y = across and fx + k or fx, across and fy or fy + k
          love.graphics.rectangle("fill", x - 2, y - 2, 4, 4)
        end
      end
    elseif c.kind == "console" then
      -- A line of light scrolling down the screen, a cursor blinking after the last line.
      local sh = c.h * 0.55
      local k = (t * (0.3 + hash(c.seed) * 0.4) + hash(c.seed * 3)) % 1
      love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.25)
      love.graphics.rectangle("fill", c.x + 6, c.y + 5 + k * (sh - 4), c.w - 12, 4)
      if (t * 2 + c.seed) % 1 < 0.5 then
        love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.9)
        love.graphics.rectangle("fill", c.x + c.w - 18, c.y + sh - 4, 6, 3)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

local function drawDrone(d, t)
  local bob = math.sin(t * 3 + d.seed) * 2
  -- Its shadow on the floor (or far down in the drop), well off under it.
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", d.x + 16, d.y + 24, 11 * Upkeep.size, 8 * Upkeep.size)
  local x, y = d.x, d.y + bob
  if d.working then
    -- The welding beam, flickering, from the lens to the job.
    local flick = 0.5 + 0.5 * hash(t * 37 + d.seed)
    local lx, ly = x + math.cos(d.angle) * 9 * Upkeep.size, y + math.sin(d.angle) * 9 * Upkeep.size
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.25 * flick)
    love.graphics.setLineWidth(5)
    love.graphics.line(lx, ly, d.job.x, d.job.y)
    love.graphics.setColor(0.85, 0.97, 1, 0.8 * flick)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(lx, ly, d.job.x, d.job.y)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(1, 0.9, 0.6, 0.35 + 0.4 * flick)
    love.graphics.circle("fill", d.job.x, d.job.y, 5 + 4 * flick, 12)
    love.graphics.setColor(1, 1, 1, 0.9)
    love.graphics.circle("fill", d.job.x, d.job.y, 2.5, 8)
  end
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(d.angle)
  love.graphics.scale(Upkeep.size)
  -- Two little thruster pods either side, glowing faintly underneath.
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.setColor(GLOW[1], GLOW[2], GLOW[3], 0.25 + 0.15 * math.sin(t * 20 + d.seed + side))
    love.graphics.circle("fill", -2, side * 11, 5, 10)
    love.graphics.setColor(0.20, 0.23, 0.27)
    love.graphics.rectangle("fill", -6, side * 11 - 3, 9, 6, 2)
  end
  -- The body: a steel ball, a dark band round it, the lens at the front.
  love.graphics.setColor(0.30, 0.34, 0.39)
  love.graphics.circle("fill", 0, 0, 9, 16)
  love.graphics.setColor(0.12, 0.13, 0.15)
  love.graphics.setLineWidth(2)
  love.graphics.circle("line", 0, 0, 9, 16)
  love.graphics.line(-7, 0, 4, 0)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(0.48, 0.53, 0.58)
  love.graphics.circle("fill", -2, -3, 3, 8) -- the light catching its top
  local lens = d.working and WARM or GLOW
  love.graphics.setColor(lens[1], lens[2], lens[3], 0.35)
  love.graphics.circle("fill", 8, 0, 6, 12)
  love.graphics.setColor(lens[1], lens[2], lens[3])
  love.graphics.circle("fill", 7, 0, 3, 10)
  -- A red light blinking on the back.
  if (t * 1.5 + d.seed) % 1 < 0.15 then
    love.graphics.setColor(1, 0.2, 0.15)
    love.graphics.circle("fill", -9, 0, 2, 8)
  end
  love.graphics.pop()
end

--- The drones and their sparks, over everyone.
function Upkeep.drawAboveCars()
  local s = state
  if not s then
    return
  end
  for _, p in ipairs(s.sparks) do
    local k = 1 - p.t / p.life
    love.graphics.setColor(1, 0.6 + 0.4 * k, 0.25 + 0.6 * k, k)
    love.graphics.line(p.x, p.y, p.x - p.vx * 0.04, p.y - p.vy * 0.04)
  end
  for _, d in ipairs(s.drones) do
    drawDrone(d, s.time)
  end
  love.graphics.setColor(1, 1, 1)
end

return Upkeep
