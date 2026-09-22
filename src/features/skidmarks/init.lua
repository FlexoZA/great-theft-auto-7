-- Skid marks: when a car slides sideways (handbrake turns, hard cornering)
-- its rear wheels leave dark rubber on the road that fades over time.
--
-- Purely local. Works from the snapshots every client already has: the
-- sideways speed is the car's movement between snapshots projected across
-- its heading, so nothing extra is sent.


local Skidmarks = {
  name = "skidmarks",
  priority = 30, -- on the road (map 20), under pedestrians (60) and cars
}

Skidmarks.threshold = 110 -- px/s sideways before rubber is laid
Skidmarks.life = 14 -- seconds a mark takes to fade
Skidmarks.maxMarks = 800
Skidmarks.width = 4

local marks = {} -- { x1, y1, x2, y2, t }
local last = {} -- car id -> { x, y, angle, time, lx, ly, rx, ry (rear wheels), skidding }

local function rearWheels(x, y, angle)
  local ca, sa = math.cos(angle), math.sin(angle)
  local ax, ay = x - ca * 12, y - sa * 12 -- rear axle
  local ox, oy = -sa * 8, ca * 8 -- half track
  return ax - ox, ay - oy, ax + ox, ay + oy
end

local function addMark(x1, y1, x2, y2)
  if #marks >= Skidmarks.maxMarks then
    table.remove(marks, 1)
  end
  marks[#marks + 1] = { x1, y1, x2, y2, Skidmarks.life }
end

function Skidmarks:enterGame()
  marks = {}
  last = {}
end

function Skidmarks:exitGame()
  self:enterGame()
end

function Skidmarks:update(dt, client)
  local now = love.timer.getTime()
  for id, c in pairs(client.cars) do
    local prev = last[id]
    if not prev then
      local lx, ly, rx, ry = rearWheels(c.x, c.y, c.angle)
      last[id] = { x = c.x, y = c.y, time = now, lx = lx, ly = ly, rx = rx, ry = ry }
    elseif c.x ~= prev.x or c.y ~= prev.y then
      -- A new snapshot arrived: how fast did it move across its heading?
      local sdt = math.max(now - prev.time, 1 / 60)
      local vx, vy = (c.x - prev.x) / sdt, (c.y - prev.y) / sdt
      local lateral = math.abs(-vx * math.sin(c.angle) + vy * math.cos(c.angle))
      local lx, ly, rx, ry = rearWheels(c.x, c.y, c.angle)
      if lateral > self.threshold and prev.skidding then
        addMark(prev.lx, prev.ly, lx, ly)
        addMark(prev.rx, prev.ry, rx, ry)
      end
      prev.skidding = lateral > self.threshold
      prev.x, prev.y, prev.time = c.x, c.y, now
      prev.lx, prev.ly, prev.rx, prev.ry = lx, ly, rx, ry
    end
  end
  for id in pairs(last) do
    if not client.cars[id] then
      last[id] = nil
    end
  end

  local i = 1
  while i <= #marks do
    local m = marks[i]
    m[5] = m[5] - dt
    if m[5] <= 0 then
      table.remove(marks, i)
    else
      i = i + 1
    end
  end
end

function Skidmarks:drawBelowCars()
  love.graphics.setLineWidth(self.width)
  for _, m in ipairs(marks) do
    love.graphics.setColor(0.05, 0.05, 0.05, 0.55 * math.min(1, m[5] / 4))
    love.graphics.line(m[1], m[2], m[3], m[4])
  end
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- For tests.
function Skidmarks.marks()
  return marks
end



return Skidmarks
