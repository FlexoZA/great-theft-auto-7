-- Client-side crowd: holds the last snapshot from the server, eases every
-- pedestrian towards it and draws them (the core's person, src/body.lua, in
-- a look of their own picked by id). Nothing here changes the world.

local Body = require("src.body")

local Render = {
  peds = {}, -- id -> { x, y, dx, dy, angle, flee, frozen, bob }
  time = 0,
  panicked = {}, -- pedestrians that started running in the last sync()...
  panickedN = 0, -- ...and how many of them, so the table can be reused
}

local SMOOTHING = 10 -- per second, matching the feel of the car smoothing
local SNAP = 150 -- px; a jump this big is a fresh pedestrian, not a walk
-- What a pedestrian wears, each list picked from by id (at a different
-- stride, so the combinations vary) so a pedestrian keeps their look.
local SHIRTS = {
  { 0.92, 0.42, 0.40 },
  { 0.40, 0.65, 0.95 },
  { 0.95, 0.90, 0.50 },
  { 0.50, 0.85, 0.55 },
  { 0.88, 0.88, 0.92 },
  { 0.75, 0.50, 0.90 },
}
local PANTS = {
  { 0.22, 0.26, 0.42 }, -- jeans
  { 0.18, 0.18, 0.2 },
  { 0.45, 0.4, 0.3 },
  { 0.35, 0.3, 0.38 },
}
local SKINS = {
  { 0.92, 0.78, 0.63 },
  { 0.78, 0.6, 0.45 },
  { 0.55, 0.38, 0.26 },
  { 0.35, 0.23, 0.15 },
}
local HAIRS = {
  { 0.18, 0.12, 0.08 },
  { 0.08, 0.07, 0.07 },
  { 0.55, 0.38, 0.18 },
  { 0.85, 0.72, 0.4 },
  { 0.55, 0.55, 0.58 },
}
local ICE = { 0.55, 0.85, 1.0 } -- the glaze over a frozen one
local looks = {} -- id -> the look table handed to Body.person, reused

--- A colour part way from `c` to ice.
local function frosted(c, k)
  return { c[1] + (ICE[1] - c[1]) * k, c[2] + (ICE[2] - c[2]) * k, c[3] + (ICE[3] - c[3]) * k }
end

--- Pedestrian `id`'s look: the same every time, frosted over while frozen.
local function lookOf(id, p)
  local look = looks[id]
  if not look then
    look = {
      base = {
        shirt = SHIRTS[id % #SHIRTS + 1], pants = PANTS[(id * 7) % #PANTS + 1],
        skin = SKINS[(id * 3) % #SKINS + 1], hair = HAIRS[(id * 5) % #HAIRS + 1],
      },
    }
    looks[id] = look
  end
  for _, k in ipairs({ "shirt", "pants", "skin", "hair" }) do
    look[k] = p.frozen and frosted(look.base[k], 0.6) or look.base[k]
  end
  look.panic = p.flee
  return look
end

function Render.clear()
  Render.peds = {}
  looks = {}
  Render.time = 0
  Render.panickedN = 0
end

--- Apply a PED_SYNC payload: args[1] is the tick, then groups of four.
function Render.sync(args)
  local peds = Render.peds
  local seen = {}
  Render.panickedN = 0
  for i = 2, #args - 3, 4 do
    local id = tonumber(args[i])
    local x, y = tonumber(args[i + 1]), tonumber(args[i + 2])
    if id and x and y then
      local p = peds[id]
      if not p then
        p = { dx = x, dy = y, angle = 0, bob = love.math.random() * 6 }
        peds[id] = p
      end
      local flee = args[i + 3] == "1"
      if flee and not p.flee then
        -- Just spotted a car: worth a yelp (init.lua decides).
        local n = Render.panickedN + 1
        local slot = Render.panicked[n]
        if not slot then
          slot = {}
          Render.panicked[n] = slot
        end
        slot.id, slot.x, slot.y = id, x, y
        Render.panickedN = n
      end
      p.x, p.y, p.flee, p.frozen = x, y, flee, args[i + 3] == "2"
      seen[id] = true
    end
  end
  for id in pairs(peds) do
    if not seen[id] then
      peds[id] = nil
      looks[id] = nil
    end
  end
end

function Render.remove(id)
  Render.peds[id] = nil
  looks[id] = nil
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

--- Draws every pedestrian inside the view, each the core's person in their look.
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
      -- The stride: a walk, or a run when fleeing; still when frozen.
      local swing = p.frozen and 0 or math.sin(t * (p.flee and 16 or 7) + p.bob) * (p.flee and 1.4 or 0.9)
      Body.person(x, y, p.angle, swing, lookOf(id, p))
      if p.frozen then
        love.graphics.setColor(ICE[1], ICE[2], ICE[3], 0.35)
        love.graphics.circle("fill", x, y, Body.SHOULDERS + 3, 12)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
