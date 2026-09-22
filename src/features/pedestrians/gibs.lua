-- The messy part, all client side: chunks that fly off a bumper and the stain
-- they leave behind. Both lists are capped, so a car ploughing through a
-- crowd costs a fixed amount of work. The noise lives in sounds.lua.

local Gibs = {
  chunks = {}, -- flying pieces, oldest first
  stains = {}, -- ground decals, FIFO
}

local MAX_CHUNKS = 260
local MAX_STAINS = 70
local CHUNKS_PER_SPLAT = 11
local DRAG = 2.6 -- per second; chunks skid to a stop
local LIFE = { 0.5, 1.1 } -- seconds

local RED = { 0.55, 0.05, 0.07 }
local random = love.math.random

function Gibs.clear()
  Gibs.chunks = {}
  Gibs.stains = {}
end

--- A pedestrian met a bumper at (x, y); `angle` is the car's direction.
function Gibs.splat(x, y, angle)
  local chunks, stains = Gibs.chunks, Gibs.stains

  for _ = 1, CHUNKS_PER_SPLAT do
    -- Mostly forward along the car, with a wide fan either side.
    local a = angle + (random() - 0.5) * 2.2
    local speed = 90 + random() * 260
    chunks[#chunks + 1] = {
      x = x,
      y = y,
      vx = math.cos(a) * speed,
      vy = math.sin(a) * speed,
      r = 1.2 + random() * 2.4,
      life = LIFE[1] + random() * (LIFE[2] - LIFE[1]),
      age = 0,
    }
  end
  while #chunks > MAX_CHUNKS do
    table.remove(chunks, 1)
  end

  -- The stain is fixed at birth: four blobs smeared along the car's path.
  local blobs = {}
  for i = 1, 4 do
    local d = (i - 1) * (6 + random() * 10)
    blobs[i] = {
      ox = math.cos(angle) * d + (random() - 0.5) * 8,
      oy = math.sin(angle) * d + (random() - 0.5) * 8,
      r = 7 - i * 1.1 + random() * 2,
    }
  end
  stains[#stains + 1] = { x = x, y = y, blobs = blobs }
  while #stains > MAX_STAINS do
    table.remove(stains, 1)
  end
end

function Gibs.update(dt)
  local chunks = Gibs.chunks
  local i, n = 1, #chunks
  while i <= n do
    local c = chunks[i]
    c.age = c.age + dt
    if c.age >= c.life then
      chunks[i] = chunks[n]
      chunks[n] = nil
      n = n - 1
    else
      local drag = math.max(0, 1 - DRAG * dt)
      c.vx, c.vy = c.vx * drag, c.vy * drag
      c.x = c.x + c.vx * dt
      c.y = c.y + c.vy * dt
      i = i + 1
    end
  end
end

--- Ground stains, under everything else.
function Gibs.drawStains()
  love.graphics.setColor(RED[1], RED[2], RED[3], 0.75)
  for _, s in ipairs(Gibs.stains) do
    for _, b in ipairs(s.blobs) do
      love.graphics.circle("fill", s.x + b.ox, s.y + b.oy, b.r, 8)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

--- Flying chunks, over the cars.
function Gibs.drawChunks()
  for _, c in ipairs(Gibs.chunks) do
    local fade = 1 - c.age / c.life
    love.graphics.setColor(RED[1] + 0.15 * fade, RED[2], RED[3], 0.45 + 0.55 * fade)
    love.graphics.circle("fill", c.x, c.y, c.r, 6)
  end
  love.graphics.setColor(1, 1, 1)
end

return Gibs
