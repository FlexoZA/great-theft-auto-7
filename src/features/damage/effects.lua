-- What damage looks like, all client side: the statuses on a body (flames,
-- blood, sparks, stars), the numbers that float up off a hit, and what a
-- body leaves behind by the type that killed it (ash, a scorch mark, the
-- gibs). The damage feature (init.lua) feeds it and draws it.

local UI = require("src.ui")

local Effects = {
  numbers = {}, -- { key, x, y, amount, dtype, t }: floating damage numbers, newest last
  remains = {}, -- { kind = "ash" | "scorch", x, y, angle, t }: left on the ground
  drips = {}, -- { x, y, r, t }: blood a bleeding body left on the ground
}

-- Tuning ------------------------------------------------------------------
Effects.numberTime = 0.9 -- seconds a number floats
Effects.numberRise = 34 -- px it floats up over that time
Effects.numberMerge = 0.35 -- seconds within which hits on the same target add up into one number
Effects.remainsTime = 90 -- seconds ash or a scorch mark stays
Effects.dripTime = 3 -- seconds a drip stays on the ground

local MAX_NUMBERS = 60
local MAX_REMAINS = 60
local MAX_DRIPS = 300

function Effects.clear()
  Effects.numbers, Effects.remains, Effects.drips = {}, {}, {}
end

--- A hit of `amount` (`dtype`) on target `key` (a player or a car) at (x, y):
--- a number floats up there, or a fresh one on the same target grows by it.
function Effects.number(key, x, y, amount, dtype)
  if not (amount and amount > 0) then
    return
  end
  local list = Effects.numbers
  for i = #list, 1, -1 do
    local n = list[i]
    if n.key == key and Effects.numberTime - n.t < Effects.numberMerge then
      n.amount, n.x, n.y, n.t = n.amount + amount, x, y, Effects.numberTime
      if amount > n.biggest then
        n.dtype, n.biggest = dtype, amount -- coloured by what did most of it
      end
      return
    end
  end
  if #list >= MAX_NUMBERS then
    table.remove(list, 1)
  end
  list[#list + 1] = {
    key = key, x = x, y = y, amount = amount, biggest = amount, dtype = dtype, t = Effects.numberTime,
  }
end

--- Something left at (x, y) for a while: "ash" or "scorch".
function Effects.leave(kind, x, y, angle)
  if #Effects.remains >= MAX_REMAINS then
    table.remove(Effects.remains, 1)
  end
  Effects.remains[#Effects.remains + 1] = { kind = kind, x = x, y = y, angle = angle or 0, t = Effects.remainsTime }
end

--- A drop of blood on the ground at (x, y), a little way off.
function Effects.drip(x, y)
  if #Effects.drips >= MAX_DRIPS then
    return
  end
  local a = love.math.random() * 2 * math.pi
  local d = love.math.random() * 7
  Effects.drips[#Effects.drips + 1] = {
    x = x + math.cos(a) * d, y = y + math.sin(a) * d, r = 1.8 + love.math.random() * 2, t = Effects.dripTime,
  }
end

local function age(list, dt)
  for i = #list, 1, -1 do
    local e = list[i]
    e.t = e.t - dt
    if e.t <= 0 then
      table.remove(list, i)
    end
  end
end

function Effects.update(dt)
  age(Effects.numbers, dt)
  age(Effects.remains, dt)
  age(Effects.drips, dt)
end

-- The ground ------------------------------------------------------------------

--- Ash where somebody was burned or fried: a grey heap and scattered flakes,
--- and their clothes left lying there.
local function drawAsh(s)
  love.graphics.setColor(0.08, 0.07, 0.07, 0.6)
  love.graphics.ellipse("fill", s.x, s.y, 16, 12)
  love.graphics.setColor(0.55, 0.54, 0.52, 0.9)
  love.graphics.ellipse("fill", s.x, s.y, 9, 7)
  for k = 0, 6 do
    local a = s.angle + k * 0.9
    love.graphics.circle("fill", s.x + math.cos(a) * (10 + k), s.y + math.sin(a) * (8 + k), 1.5 + k % 2, 5)
  end
  love.graphics.setColor(0.25, 0.35, 0.60, 0.9)
  love.graphics.ellipse("fill", s.x + 6, s.y + 4, 6, 3)
end

--- A scorch mark where a blast took somebody: a black star burned into the road.
local function drawScorch(s)
  local fade = math.min(1, s.t / 10)
  love.graphics.setColor(0.05, 0.04, 0.04, 0.55 * fade)
  love.graphics.circle("fill", s.x, s.y, 20)
  for k = 0, 7 do
    local a = s.angle + k * math.pi / 4 + (k % 2) * 0.2
    local len = 24 + (k % 3) * 6
    love.graphics.polygon("fill", s.x + math.cos(a - 0.18) * 14, s.y + math.sin(a - 0.18) * 14,
      s.x + math.cos(a) * len, s.y + math.sin(a) * len, s.x + math.cos(a + 0.18) * 14, s.y + math.sin(a + 0.18) * 14)
  end
end

--- Everything on the ground: remains, then drips, fading as they dry.
function Effects.drawGround()
  for _, r in ipairs(Effects.remains) do
    if r.kind == "ash" then
      drawAsh(r)
    else
      drawScorch(r)
    end
  end
  for _, drip in ipairs(Effects.drips) do
    love.graphics.setColor(0.7, 0.02, 0.02, 0.85 * math.min(1, drip.t / Effects.dripTime * 2))
    love.graphics.circle("fill", drip.x, drip.y, drip.r)
  end
  love.graphics.setColor(1, 1, 1)
end

-- Statuses on a body ----------------------------------------------------------

--- Flames licking up off a body: a glow on the ground, then a few tongues
--- flickering at their own pace, hot at the heart.
function Effects.flames(x, y, seed, clock)
  love.graphics.setColor(1, 0.45, 0.1, 0.22 + 0.08 * math.sin(clock * 11 + seed))
  love.graphics.circle("fill", x, y, 22)
  for i = 1, 6 do
    local phase = clock * (1.6 + i * 0.25) + seed * 1.7 + i * 0.37
    local rise = (phase % 1) -- each tongue climbs and fades, then starts again
    local ox = math.sin(phase * 6.3 + i) * 4 + (i - 3.5) * 3.5
    local oy = 4 - rise * 26
    local r = 8 * (1 - rise * 0.6)
    love.graphics.setColor(1, 0.35 + 0.3 * (1 - rise), 0.05, 0.75 * (1 - rise))
    love.graphics.circle("fill", x + ox, y + oy, r)
    love.graphics.setColor(1, 0.9, 0.4, 0.8 * (1 - rise))
    love.graphics.circle("fill", x + ox, y + oy + 1, r * 0.45)
  end
end

--- Blood: drops falling off a body, each its own way (the drips it leaves
--- on the ground are drawn with the ground).
function Effects.blood(x, y, seed, clock)
  for i = 1, 6 do
    local phase = clock * 1.8 + seed * 0.9 + i * 0.29
    local fall = phase % 1
    local a = seed * 2.3 + i * 1.7
    local ox, oy = math.cos(a) * 9, math.sin(a) * 5
    love.graphics.setColor(0.85, 0.05, 0.05, 0.95 * (1 - fall * 0.7))
    love.graphics.circle("fill", x + ox, y + oy + fall * 16, 3.2 - fall)
  end
end

--- Sparks crackling round a body: a few jagged blue arcs, a new shape
--- every flicker, over a pale glow.
function Effects.sparks(x, y, seed, clock)
  love.graphics.setColor(0.6, 0.85, 1, 0.25)
  love.graphics.circle("fill", x, y, 16)
  local flicker = math.floor(clock * 18)
  love.graphics.setLineWidth(1.5)
  love.graphics.setColor(0.55, 0.85, 1, 0.95)
  for i = 1, 3 do
    local a = (flicker * 2.39 + i * 2.1 + seed) % (2 * math.pi)
    local px, py = x + math.cos(a) * 6, y + math.sin(a) * 6
    local pts = { px, py }
    for k = 1, 3 do
      local j = ((flicker * 7 + i * 13 + k * 5) % 11) / 11 - 0.5
      px = px + math.cos(a + j) * 5
      py = py + math.sin(a + j) * 5
      pts[#pts + 1], pts[#pts + 2] = px, py
    end
    love.graphics.line(pts)
  end
  love.graphics.setLineWidth(1)
end

--- Knocked down: stars going round over the head.
function Effects.stars(x, y, seed, clock)
  for i = 1, 3 do
    local a = clock * 5 + seed + i * (2 * math.pi / 3)
    local sx, sy = x + math.cos(a) * 13, y - 16 + math.sin(a) * 5
    love.graphics.setColor(1, 0.9, 0.3, 0.95)
    love.graphics.circle("fill", sx, sy, 3.5)
    love.graphics.setColor(1, 1, 0.85, 0.95)
    love.graphics.circle("fill", sx, sy, 1.5)
  end
end

-- Numbers ---------------------------------------------------------------------

--- The floating numbers, in world space, each in its type's colour with a
--- dark edge so it reads on any ground. `colorOf(dtype)` gives the colour.
function Effects.drawNumbers(colorOf, scale)
  local font = UI.fonts.body
  love.graphics.setFont(font)
  local s = 1 / (scale or 1) -- the same size on screen whatever the zoom
  for _, n in ipairs(Effects.numbers) do
    local k = 1 - n.t / Effects.numberTime -- 0 when it appears, 1 as it goes
    local text = ("%d"):format(math.max(1, math.floor(n.amount + 0.5)))
    local w = font:getWidth(text)
    local x, y = n.x, n.y - 42 - k * Effects.numberRise -- over the name, not on it
    local alpha = math.min(1, n.t / (Effects.numberTime * 0.4))
    local pop = 1 + 0.35 * math.max(0, 1 - k * 5) -- a little bigger the moment it lands
    love.graphics.push()
    love.graphics.translate(x, y)
    love.graphics.scale(s * pop)
    love.graphics.setColor(0, 0, 0, 0.7 * alpha)
    for _, o in ipairs({ { -1, 0 }, { 1, 0 }, { 0, -1 }, { 0, 1 } }) do
      love.graphics.print(text, -w / 2 + o[1], o[2])
    end
    local c = colorOf(n.dtype)
    love.graphics.setColor(c[1], c[2], c[3], alpha)
    love.graphics.print(text, -w / 2, 0)
    love.graphics.pop()
  end
  love.graphics.setColor(1, 1, 1)
end

return Effects
