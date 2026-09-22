-- Client-side crowd: holds the last snapshot from the server, eases every
-- pedestrian towards it and draws them. Nothing here changes the world.

local Render = {
  peds = {}, -- id -> { x, y, dx, dy, angle, flee, bob }
  time = 0,
}

local SMOOTHING = 10 -- per second, matching the feel of the car smoothing
local SNAP = 150 -- px; a jump this big is a fresh pedestrian, not a walk
local BODY = 5
local HEAD = 3

-- A few flat shirt colours, picked by id so a pedestrian keeps theirs.
local SHIRTS = {
  { 0.92, 0.42, 0.40 },
  { 0.40, 0.65, 0.95 },
  { 0.95, 0.90, 0.50 },
  { 0.50, 0.85, 0.55 },
  { 0.88, 0.88, 0.92 },
  { 0.75, 0.50, 0.90 },
}
local SKIN = { 0.92, 0.78, 0.63 }

function Render.clear()
  Render.peds = {}
  Render.time = 0
end

--- Apply a PED_SYNC payload: args[1] is the tick, then groups of four.
function Render.sync(args)
  local peds = Render.peds
  local seen = {}
  for i = 2, #args - 3, 4 do
    local id = tonumber(args[i])
    local x, y = tonumber(args[i + 1]), tonumber(args[i + 2])
    if id and x and y then
      local p = peds[id]
      if not p then
        p = { dx = x, dy = y, angle = 0, bob = love.math.random() * 6 }
        peds[id] = p
      end
      p.x, p.y, p.flee = x, y, args[i + 3] == "1"
      seen[id] = true
    end
  end
  for id in pairs(peds) do
    if not seen[id] then
      peds[id] = nil
    end
  end
end

function Render.remove(id)
  Render.peds[id] = nil
end

function Render.update(dt)
  Render.time = Render.time + dt
  local k = math.min(1, dt * SMOOTHING)
  for _, p in pairs(Render.peds) do
    local ex, ey = p.x - p.dx, p.y - p.dy
    if ex * ex + ey * ey > SNAP * SNAP then
      p.dx, p.dy = p.x, p.y
    else
      local mx, my = ex * k, ey * k
      p.dx, p.dy = p.dx + mx, p.dy + my
      if mx * mx + my * my > 0.01 then
        p.angle = math.atan2(my, mx) -- face where you are walking
      end
    end
  end
end

--- Draws every pedestrian inside the view. Two circles each, no transforms.
function Render.draw(camera)
  local w, h = love.graphics.getDimensions()
  local scale = camera.scale or 1
  local halfW, halfH = w / (2 * scale) + 20, h / (2 * scale) + 20
  local left, right = camera.x - halfW, camera.x + halfW
  local top, bottom = camera.y - halfH, camera.y + halfH
  local t = Render.time

  for id, p in pairs(Render.peds) do
    local x, y = p.dx, p.dy
    if x > left and x < right and y > top and y < bottom then
      local fx, fy = math.cos(p.angle), math.sin(p.angle)
      -- Sway across the direction of travel: a cheap two-legged waddle.
      local swing = math.sin(t * (p.flee and 16 or 7) + p.bob) * (p.flee and 1.4 or 0.9)
      local sx, sy = -fy * swing, fx * swing

      love.graphics.setColor(0, 0, 0, 0.25)
      love.graphics.circle("fill", x + 1.5, y + 1.5, BODY, 8)
      love.graphics.setColor(SHIRTS[id % #SHIRTS + 1])
      love.graphics.circle("fill", x + sx, y + sy, BODY, 8)
      if p.flee then -- arms flung out in panic
        love.graphics.circle("fill", x - fy * 4.5 - sx, y + fx * 4.5 - sy, 1.8, 6)
        love.graphics.circle("fill", x + fy * 4.5 - sx, y - fx * 4.5 - sy, 1.8, 6)
      end
      love.graphics.setColor(SKIN)
      love.graphics.circle("fill", x + fx * 1.8 + sx * 0.5, y + fy * 1.8 + sy * 0.5, HEAD, 7)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
