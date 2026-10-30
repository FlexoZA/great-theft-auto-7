-- The Colosseum: the endgame, going up on a whole block in the middle of
-- the city (city-map's `map.colosseum`, the block north of the spawn road;
-- layout.lua clears it and fences it off solid). Until every job on the
-- board is finished it is a building site, and nobody gets in.
--
-- How far it has got is how many board jobs are finished in this world:
-- the quests feature's `finished`, which the host decides, sends everyone
-- (QST_FINISHED) and keeps with the saved world, so every screen shows the
-- same stage and it is still there next time. Each job puts up more of the
-- ring (look.lua): the three tiers of arches over the first six jobs, the
-- attic on the seventh while the scaffolding starts coming down, and the
-- last finishes it: the scaffolding and cranes gone, the yard paved, flags
-- at the corners and the gate standing open. The arena inside comes later.
--
-- The cranes are borderline's tower cranes (works.lua, the Bragium Pit's),
-- drawn through `Borderline:drawSiteCranes`: two while the tiers go up,
-- one for the attic, none once it is done.
--
-- Walk or drive up to the gate (the sidewalk in the middle of the block's
-- south side) and it says what is going on: under construction, and how
-- many jobs are done of how many, or once it is finished that the games
-- begin soon. It is on the minimap and the big map as an oval, the built
-- part of the ring lit up.
--
-- Nothing here is on the host: the world is the quests feature's and the
-- block's walls are city-map's.

local Features = require("src.features")
local UI = require("src.ui")
local Look = require("src.features.colosseum.look")

local Colosseum = {
  name = "colosseum",
  priority = 27, -- over the map canvas (20), under skidmarks (30), pedestrians and cars
}

-- Tuning ------------------------------------------------------------------
Colosseum.gateReach = 110 -- px from the gate that shows what is going on

local canvas = nil -- the stage drawn once (look.lua), redrawn when it changes
local baked = nil -- { site, done, total } the canvas shows
local plan = nil -- look.lua's plan for the stage shown
local cranes = {} -- borderline-style tower cranes for the stage shown
local time = 0
local atGate = false

--- The building site on the map in play, or nil (off the city).
local function site()
  local city = Features.byName["city-map"]
  return city and city.map and city.map.colosseum or nil
end

--- How many board jobs are finished in this world, and how many there are.
local function progress()
  local quests = Features.byName.quests
  if not (quests and quests.board) then
    return 0, 1
  end
  local done = 0
  for _, job in ipairs(quests.board) do
    if quests.finished and quests.finished[job.id] then
      done = done + 1
    end
  end
  return done, math.max(1, #quests.board)
end

--- Where the gate is, world px: on the sidewalk outside it.
local function gate(s)
  return s.x + s.w / 2, s.y + s.h + 30
end

function Colosseum:exitGame()
  baked, plan, cranes, atGate = nil, nil, {}, false
end

--- The stage the site is at now; the canvas and the cranes follow it.
local function refresh(s)
  local done, total = progress()
  if baked and baked.site == s and baked.done == done and baked.total == total then
    return
  end
  plan = Look.plan(done, total)
  cranes = Look.cranes(s, plan.cranes)
  if not canvas and love.graphics and love.graphics.newCanvas then -- once: the site, and room for shadows round it
    canvas = love.graphics.newCanvas(s.w + 2 * Look.MARGIN, s.h + 2 * Look.MARGIN)
  end
  if canvas then
    Look.bake(canvas, s, plan)
  end
  baked = { site = s, done = done, total = total }
end

function Colosseum:update(dt, client)
  time = time + dt
  local s = site()
  atGate = false
  if not s then
    return
  end
  refresh(s)
  local x, y = client:myPose()
  if x then
    local gx, gy = gate(s)
    atGate = (x - gx) ^ 2 + (y - gy) ^ 2 < self.gateReach ^ 2
  end
end

--- Is the site within `camera`'s view (true without one)?
local function inView(s, camera)
  if not camera then
    return true
  end
  local k = camera.scale or 1
  local vw, vh = love.graphics.getWidth() / 2 / k + 400, love.graphics.getHeight() / 2 / k + 400
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  return math.abs(cx - camera.x) < vw + s.w / 2 and math.abs(cy - camera.y) < vh + s.h / 2
end

local function borderline()
  local b = Features.byName.borderline
  return b and b.drawSiteCranes and b or nil
end

function Colosseum:drawBelowCars(_client, camera)
  local s = site()
  if not (s and plan and inView(s, camera)) then
    return
  end
  if canvas then
    love.graphics.setColor(1, 1, 1)
    love.graphics.draw(canvas, Look.origin(s))
  end
  local b = borderline()
  if b and #cranes > 0 then
    b:drawSiteCranes(cranes, true)
  end
  love.graphics.setColor(1, 1, 1)
end

function Colosseum:drawAboveCars(_client, camera)
  local s = site()
  if not (s and plan and inView(s, camera)) then
    return
  end
  local b = borderline()
  if b and #cranes > 0 then
    b:drawSiteCranes(cranes, false)
  end
  if plan.finished then
    Look.drawFlags(s, time)
  end
  love.graphics.setColor(1, 1, 1)
end

function Colosseum:drawHUD()
  if not (atGate and plan) then
    return
  end
  local w, h = love.graphics.getDimensions()
  local title, line, color
  if plan.finished then
    title, line, color = "THE COLOSSEUM", "Finished. The games begin soon.", { 1, 0.85, 0.3 }
  else
    title = "THE COLOSSEUM - UNDER CONSTRUCTION"
    line = ("Locked. It opens when every job is done (%d/%d)."):format(plan.done, plan.total)
    color = { 1, 0.6, 0.35 }
  end
  love.graphics.setFont(UI.fonts.body)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(title, 1, h - 151, w, "center")
  love.graphics.printf(line, 1, h - 129, w, "center")
  love.graphics.setColor(color)
  love.graphics.printf(title, 0, h - 152, w, "center")
  love.graphics.setColor(0.9, 0.9, 0.9)
  love.graphics.printf(line, 0, h - 130, w, "center")
  love.graphics.setColor(1, 1, 1)
end

--- An oval where it stands, the built part of the ring lit up (all of it
--- once finished), so it can be found on both maps.
function Colosseum:drawOnMinimap(_client, toMap)
  local s = site()
  if not (s and plan) then
    return
  end
  local cx, cy = toMap(s.x + s.w / 2, s.y + s.h / 2)
  local ex = toMap(s.x + s.w / 2 + Look.OUTER[1], s.y + s.h / 2)
  local k = (ex - cx) / Look.OUTER[1] -- map px per world px
  local rx, ry = Look.OUTER[1] * k, Look.OUTER[2] * k
  local width = math.max(2, (Look.OUTER[2] - Look.INNER[2]) * k * 0.7)
  love.graphics.setColor(0, 0, 0, 0.8)
  love.graphics.setLineWidth(width + 2)
  love.graphics.ellipse("line", cx, cy, rx - width / 2, ry - width / 2, 32)
  love.graphics.setLineWidth(width)
  love.graphics.setColor(0.45, 0.42, 0.38)
  love.graphics.ellipse("line", cx, cy, rx - width / 2, ry - width / 2, 32)
  local f = plan.finished and 1 or plan.levels / Look.LEVELS
  if f > 0 then
    love.graphics.setColor(0.92, 0.80, 0.55)
    local points = {}
    local n = math.max(2, math.floor(32 * f))
    for i = 0, n do
      local a = -math.pi / 2 + 2 * math.pi * f * i / n
      points[#points + 1] = cx + math.cos(a) * (rx - width / 2)
      points[#points + 1] = cy + math.sin(a) * (ry - width / 2)
    end
    love.graphics.line(points)
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

return Colosseum
