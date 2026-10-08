-- The fires that never go out (a map's `fires`: City 17's and the Outer City's): flames and
-- smoke drawn every frame over the canvas, and on the host, anyone on foot
-- who walks into a fire on the ground catches alight. Everything moves by
-- the clock and each fire's seed, so it needs no state and no messages.

local Features = require("src.features")

local Fires = {
  burnTime = 2, -- seconds you burn on after walking into one
  burnDps = 6, -- fire damage a second while you do
  checkEvery = 0.25, -- seconds between checks for anyone standing in one
  wind = -0.5, -- radians; the way the smoke drifts (up and to the right)
}

-- How big each kind burns: flames, how far the smoke climbs, how many puffs.
local SIZE = {
  barrel = { flame = 0.8, smoke = 90, puffs = 4 },
  heap = { flame = 1.2, smoke = 130, puffs = 5 },
  roof = { flame = 1.8, smoke = 240, puffs = 8 },
}

local function inView(f, camera, margin)
  if not camera then
    return true
  end
  local w, h = love.graphics.getDimensions()
  local s = camera.scale or 1
  return math.abs(f.x - camera.x) < w / 2 / s + margin and math.abs(f.y - camera.y) < h / 2 / s + margin
end

--- The light it throws on the ground, breathing.
local function glow(f, k, clock)
  local flicker = 0.75 + 0.15 * math.sin(clock * 9 + f.seed) + 0.1 * math.sin(clock * 23 + f.seed * 2)
  love.graphics.setColor(1, 0.45, 0.12, 0.10 * flicker)
  love.graphics.circle("fill", f.x, f.y, 70 * k, 24)
  love.graphics.setColor(1, 0.55, 0.15, 0.14 * flicker)
  love.graphics.circle("fill", f.x, f.y, 38 * k, 20)
end

--- Tongues of flame, each climbing and fading at its own pace, hot at the
--- heart, and a spark or two thrown up.
local function flames(f, k, clock)
  local n = math.floor(5 + 4 * k)
  for i = 1, n do
    local phase = clock * (1.3 + (i % 4) * 0.22) + f.seed * 0.37 + i * 0.41
    local rise = phase % 1
    local ox = (math.sin(phase * 5.1 + i) * 5 + (i - n / 2) * 3.2) * k
    local oy = (6 - rise * 34) * k
    local r = 10 * k * (1 - rise * 0.65)
    love.graphics.setColor(0.95, 0.30 + 0.30 * (1 - rise), 0.05, 0.8 * (1 - rise))
    love.graphics.circle("fill", f.x + ox, f.y + oy, r, 10)
    love.graphics.setColor(1, 0.88, 0.45, 0.85 * (1 - rise))
    love.graphics.circle("fill", f.x + ox, f.y + oy + 2 * k, r * 0.45, 8)
  end
  for i = 1, 3 do
    local rise = (clock * 0.7 + f.seed * 0.11 + i / 3) % 1
    local x = f.x + math.sin(rise * 9 + i * 2 + f.seed) * 14 * k
    local y = f.y - rise * 70 * k
    love.graphics.setColor(1, 0.7, 0.25, 1 - rise)
    love.graphics.rectangle("fill", x, y, 2, 2)
  end
end

--- Smoke climbing off it and drifting with the wind, spreading as it goes.
local function smoke(f, size, clock)
  local dx, dy = math.sin(Fires.wind), -math.cos(Fires.wind)
  for i = 1, size.puffs do
    local t = (clock * 0.12 + f.seed * 0.013 + i / size.puffs) % 1
    local d = t * size.smoke
    local wob = math.sin(t * 7 + i + f.seed) * 8
    local x, y = f.x + dx * d + wob, f.y - 20 * size.flame + dy * d
    local g = 0.12 + 0.1 * (i % 2)
    love.graphics.setColor(g, g, g * 1.05, 0.45 * (1 - t) * math.min(1, t * 6))
    love.graphics.circle("fill", x, y, (8 + t * 26) * size.flame, 14)
  end
end

--- Every fire in view, over the cars and people: the city's fires burn
--- above what walks past them.
function Fires.draw(map, camera, clock)
  local list = map.fires
  if not list then
    return
  end
  for _, f in ipairs(list) do
    if inView(f, camera, 260) then
      local size = SIZE[f.kind] or SIZE.heap
      glow(f, size.flame, clock)
      flames(f, size.flame, clock)
    end
  end
  for _, f in ipairs(list) do
    if inView(f, camera, 320) then
      smoke(f, SIZE[f.kind] or SIZE.heap, clock)
    end
  end
end

--- On the host: anyone on foot standing in a fire on the ground catches
--- alight. `state` keeps the time to the next check.
function Fires.step(map, server, dt, state)
  state.checkIn = (state.checkIn or 0) - dt
  if state.checkIn > 0 or not map.fires then
    return
  end
  state.checkIn = Fires.checkEvery
  local damage = Features.byName.damage
  if not damage then
    return
  end
  for _, p in pairs(server.players) do
    if not p.bot and not p.vehicle and Features.present(p) then
      local x, y = Features.bodyPose(server, p)
      for _, f in ipairs(map.fires) do
        if f.kind == "heap" and (x - f.x) ^ 2 + (y - f.y) ^ 2 <= (f.r + 6) ^ 2 then
          damage:ignite(server, p, Fires.burnTime, Fires.burnDps)
          break
        end
      end
    end
  end
end

return Fires
