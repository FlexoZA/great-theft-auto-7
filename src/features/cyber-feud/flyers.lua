-- What flies over Grey City (the Drop): every now and then one of three
-- machines crosses the sky high over everyone, its shadow sliding over the
-- streets far below it:
--
--   aerodyne  Halcyon's executive VTOL: a sleek white wedge on four ducted
--             fans, magenta trim, nav lights blinking, a searchlight
--             sweeping the streets under it
--   hauler    a heavy lifter: a long grey hull between two big ducted
--             rotors, a shipping container slung under it, amber beacons
--   adrone    an ad drone: a quadcopter towing a holo billboard, the ad
--             scrolling across it, flickering
--
-- They take turns (each of the three before any comes again), and each
-- crosses on a straight line passing near whoever is watching, from well
-- off one side of the screen to well off the other. At night (the night
-- feature) their lights glow and the aerodyne's searchlight lights the
-- ground. Each one's engine (flyer_sounds.lua) is heard from wherever it
-- is, panning and fading with distance, a little higher in pitch coming
-- than going. Scenery only, on each screen by itself: nothing is sent,
-- nothing can be hit.

local UI = require("src.ui")
local Sounds = require("src.features.cyber-feud.flyer_sounds")

local Flyers = {}

-- Tuning ------------------------------------------------------------------
Flyers.firstIn = { 6, 12 } -- seconds on the map before the first one
Flyers.every = { 18, 40 } -- seconds between one and the next
Flyers.reach = 1700 -- px either side of the watcher a crossing starts and ends
Flyers.miss = 500 -- px at most its line passes the watcher by
Flyers.SHADOW = 90 -- px its shadow falls away, down and right: it is high up
Flyers.SCALE = 1.7 -- how much bigger than life it is drawn: high up, it is near the camera
Flyers.doppler = 1800 -- px/s; its speed towards or away from you over this is how far its pitch shifts

local KINDS = { "aerodyne", "hauler", "adrone" }
local SPEED = { aerodyne = 430, hauler = 230, adrone = 300 } -- px/s
local ADS = { "KARMA KREDIT  0% APR*", "CHROME 4 LESS", "HALCYON: TOMORROW, SCHEDULED", "NOODLZ  OPEN 25/7",
  "CLONE CARE  BACK BETTER", "SOYLENT FRIED" }

local MAGENTA = { 1.00, 0.24, 0.78 }
local CYAN = { 0.18, 0.90, 1.00 }
local AMBER = { 1.00, 0.62, 0.15 }
local RED = { 1.00, 0.15, 0.12 }
local GREEN = { 0.30, 1.00, 0.45 }
local WHITE = { 1.00, 1.00, 1.00 }
local BEAM = { 0.85, 0.92, 1.00 }

local random = love.math.random
local clock = 0
local flying = nil -- { kind, x, y, dx, dy, angle, left, seed, ad }
local nextIn = nil
local order, turn = {}, 0

local function between(r)
  return r[1] + random() * (r[2] - r[1])
end

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

--- Synthesise the engines, once.
function Flyers.load()
  Sounds.load()
end

--- No more of it: its engine stops.
local function land()
  if flying and flying.sound then
    flying.sound:stop()
  end
  flying = nil
end

function Flyers.clear()
  land()
  nextIn = nil
end

--- Its engine with it, higher coming towards the listener, lower going away.
local function hear(f)
  if not f.sound then
    return
  end
  local lx, _, ly = love.audio.getPosition()
  local rx, ry = f.x - lx, f.y - ly
  local d = math.max(1, math.sqrt(rx * rx + ry * ry))
  local closing = -(rx * f.dx + ry * f.dy) / d -- px/s towards the listener
  Sounds.place(f.sound, f.x, f.y, math.max(0.5, 1 + closing / Flyers.doppler))
end

--- The next kind up: each of the three in a shuffled order, then again.
local function nextKind()
  turn = turn + 1
  if turn > #order then
    order, turn = { unpack(KINDS) }, 1
    for i = #order, 2, -1 do
      local j = random(i)
      order[i], order[j] = order[j], order[i]
    end
  end
  return order[turn]
end

--- One crosses over (wx, wy), the one watching.
local function launch(wx, wy)
  local kind = nextKind()
  local a = random() * 2 * math.pi
  local ux, uy = math.cos(a), math.sin(a)
  local off = (random() * 2 - 1) * Flyers.miss
  local speed = SPEED[kind]
  flying = {
    kind = kind, angle = a, dx = ux * speed, dy = uy * speed,
    x = wx - ux * Flyers.reach - uy * off, y = wy - uy * Flyers.reach + ux * off,
    left = 2 * Flyers.reach / speed, seed = random() * 100, ad = ADS[random(#ADS)],
  }
  flying.sound = Sounds.loop(kind)
  hear(flying)
end

--- Every frame while the map is on screen; (wx, wy) where I am, if anywhere.
function Flyers.update(dt, wx, wy)
  clock = clock + dt
  if flying then
    flying.x, flying.y = flying.x + flying.dx * dt, flying.y + flying.dy * dt
    flying.left = flying.left - dt
    if flying.left <= 0 then
      land()
    else
      hear(flying)
    end
    return
  end
  nextIn = (nextIn or between(Flyers.firstIn)) - dt
  if nextIn <= 0 and wx then
    nextIn = between(Flyers.every)
    launch(wx, wy)
  end
end

-- The machines (in their own frame: x forward, y to the right) -----------------

--- A ducted fan: its ring, and the blur of blades turning inside it, the
--- ground showing through.
local function fan(x, y, r, spin)
  love.graphics.setColor(0.08, 0.09, 0.11, 0.45)
  love.graphics.circle("fill", x, y, r, 24)
  love.graphics.setColor(0.75, 0.78, 0.84, 0.16)
  love.graphics.circle("fill", x, y, r * 0.88, 20) -- the blur of them going round
  love.graphics.setLineWidth(math.max(1, r * 0.1))
  for k = 0, 3 do -- four blades, smeared
    local a = spin + k * math.pi / 2
    love.graphics.setColor(0.80, 0.83, 0.88, 0.35)
    love.graphics.line(x, y, x + math.cos(a) * r * 0.86, y + math.sin(a) * r * 0.86)
    love.graphics.setColor(0.80, 0.83, 0.88, 0.12)
    love.graphics.line(x, y, x + math.cos(a - 0.25) * r * 0.86, y + math.sin(a - 0.25) * r * 0.86)
  end
  color({ 0.25, 0.27, 0.30 })
  love.graphics.circle("fill", x, y, r * 0.18, 10) -- the hub
  color({ 0.62, 0.64, 0.69 })
  love.graphics.setLineWidth(r * 0.2)
  love.graphics.circle("line", x, y, r, 24)
  love.graphics.setLineWidth(1)
end

local function blink(period, on, phase)
  return ((clock + (phase or 0)) % period) < on
end

local function aerodyne()
  local spin = clock * 40
  for _, p in ipairs({ { 30, -34 }, { 30, 34 }, { -34, -38 }, { -34, 38 } }) do
    color({ 0.70, 0.72, 0.76 })
    love.graphics.setLineWidth(5)
    love.graphics.line(p[1] * 0.4, p[2] * 0.3, p[1], p[2]) -- its strut
    fan(p[1], p[2], 17, spin + p[1])
  end
  -- The hull: a white wedge, its nose ahead, lit along its top.
  color({ 0.80, 0.82, 0.86 })
  love.graphics.polygon("fill", 58, 0, 20, -18, -48, -20, -56, 0, -48, 20, 20, 18)
  color({ 0.93, 0.94, 0.96 })
  love.graphics.polygon("fill", 58, 0, 20, -10, -44, -10, -44, 10, 20, 10)
  color({ 0.06, 0.08, 0.11 })
  love.graphics.polygon("fill", 46, 0, 22, -9, 8, -8, 8, 8, 22, 9) -- the canopy
  color(MAGENTA)
  love.graphics.setLineWidth(2)
  love.graphics.line(18, -18, -48, -20)
  love.graphics.line(18, 18, -48, 20)
  love.graphics.setLineWidth(1)
  color(MAGENTA, 0.9)
  love.graphics.rectangle("fill", -40, -3, 30, 6) -- Halcyon's mark along its spine
  -- Nav lights: red on the left, green on the right, a white strobe behind.
  color(RED)
  love.graphics.circle("fill", -48, -21, 2.5)
  color(GREEN)
  love.graphics.circle("fill", -48, 21, 2.5)
  if blink(1.2, 0.08) then
    color(WHITE)
    love.graphics.circle("fill", -56, 0, 3.5)
  end
end

local function hauler(f)
  -- The container under it, swinging a little on its cables.
  local sway = math.sin(clock * 1.3 + f.seed) * 3
  color({ 0.10, 0.10, 0.12 })
  love.graphics.setLineWidth(1)
  for _, p in ipairs({ { 24, -14 }, { 24, 14 }, { -24, -14 }, { -24, 14 } }) do
    love.graphics.line(p[1] * 0.6, p[2] * 0.4, p[1] + sway, p[2])
  end
  color({ 0.62, 0.30, 0.14 })
  love.graphics.rectangle("fill", -42 + sway, -20, 84, 40)
  color({ 0.50, 0.24, 0.11 })
  for x = -38, 38, 8 do
    love.graphics.rectangle("fill", x + sway, -19, 3, 38) -- its ribs
  end
  color({ 0.92, 0.92, 0.90 })
  love.graphics.rectangle("fill", -30 + sway, 10, 22, 6) -- a stencil on its roof
  -- The spine between its rotors, the cab at the front.
  color({ 0.36, 0.38, 0.42 })
  love.graphics.rectangle("fill", -62, -6, 124, 12, 4)
  color({ 0.46, 0.48, 0.53 })
  love.graphics.rectangle("fill", -58, -3, 116, 3)
  color({ 0.40, 0.42, 0.46 })
  love.graphics.rectangle("fill", 34, -12, 22, 24, 6)
  color({ 0.08, 0.09, 0.11 })
  love.graphics.rectangle("fill", 46, -9, 9, 18, 3) -- the cab's glass
  local spin = clock * 26
  fan(66, 0, 34, spin)
  fan(-66, 0, 34, -spin)
  color({ 0.95, 0.75, 0.10 })
  love.graphics.rectangle("fill", -40, -15, 6, 2) -- hazard stripes
  love.graphics.rectangle("fill", -28, -15, 6, 2)
  love.graphics.rectangle("fill", 28, 13, 6, 2)
  -- Amber beacons, one at each end, turning.
  for _, x in ipairs({ -50, 50 }) do
    local a = clock * 6 + x
    color(AMBER, 0.6 + 0.4 * math.abs(math.cos(a)))
    love.graphics.circle("fill", x, 0, 3.5)
  end
end

local adFont = nil

local function adrone(f)
  -- The billboard it tows, behind it: a holo panel, the ad scrolling across.
  local bw, bh, bx = 190, 44, -40 - 190
  local flick = (math.floor(clock * 20 + f.seed) % 23 == 0) and 0.35 or 1
  color({ 0.10, 0.10, 0.12 })
  love.graphics.setLineWidth(1)
  love.graphics.line(-10, 0, bx + bw, -bh / 2)
  love.graphics.line(-10, 0, bx + bw, bh / 2)
  local tint = f.seed % 2 < 1 and MAGENTA or CYAN
  color(tint, 0.22 * flick)
  love.graphics.rectangle("fill", bx, -bh / 2, bw, bh)
  color(tint, 0.85 * flick)
  love.graphics.rectangle("line", bx, -bh / 2, bw, bh)
  for y = -bh / 2 + 3, bh / 2 - 3, 4 do -- scanlines
    color(tint, 0.08 * flick)
    love.graphics.line(bx, y, bx + bw, y)
  end
  adFont = adFont or UI.fonts.heading
  local text = f.ad .. "     "
  local tw = adFont:getWidth(text)
  local scroll = (clock * 60) % tw
  love.graphics.push()
  -- Read left to right whichever way it flies.
  local flip = math.cos(f.angle) < 0
  love.graphics.translate(bx + bw / 2, 0)
  if flip then
    love.graphics.rotate(math.pi)
  end
  love.graphics.setFont(adFont)
  color(WHITE, 0.9 * flick)
  local th = adFont:getHeight()
  -- Two copies of the text end to end, scrolling; each letter only while it
  -- is inside the panel (no scissor: this is drawn in the world, rotated).
  for k = 0, 1 do
    local x = -bw / 2 + 6 - scroll + k * tw
    for i = 1, #text do
      local ch = text:sub(i, i)
      local w = adFont:getWidth(ch)
      if x >= -bw / 2 + 4 and x + w <= bw / 2 - 4 then
        love.graphics.print(ch, x, -th / 2)
      end
      x = x + w
    end
  end
  love.graphics.pop()
  -- The quadcopter.
  color({ 0.18, 0.19, 0.22 })
  love.graphics.setLineWidth(4)
  love.graphics.line(-14, -14, 14, 14)
  love.graphics.line(-14, 14, 14, -14)
  love.graphics.setLineWidth(1)
  local spin = clock * 50
  for _, p in ipairs({ { 14, -14 }, { 14, 14 }, { -14, -14 }, { -14, 14 } }) do
    fan(p[1], p[2], 9, spin + p[2])
  end
  color({ 0.30, 0.32, 0.36 })
  love.graphics.rectangle("fill", -8, -7, 16, 14, 3)
  color(tint)
  love.graphics.circle("fill", 6, 0, 2.5)
end

local DRAW = { aerodyne = aerodyne, hauler = hauler, adrone = adrone }

--- Its silhouette, for the shadow: a rough outline of each.
local function silhouette(f)
  if f.kind == "aerodyne" then
    love.graphics.polygon("fill", 58, 0, 20, -18, -48, -20, -56, 0, -48, 20, 20, 18)
    for _, p in ipairs({ { 30, -34 }, { 30, 34 }, { -34, -38 }, { -34, 38 } }) do
      love.graphics.circle("fill", p[1], p[2], 17, 16)
    end
  elseif f.kind == "hauler" then
    love.graphics.rectangle("fill", -62, -20, 124, 40, 8)
    love.graphics.circle("fill", 66, 0, 34, 20)
    love.graphics.circle("fill", -66, 0, 34, 20)
  else
    love.graphics.circle("fill", 0, 0, 22, 16)
    love.graphics.rectangle("fill", -230, -22, 190, 44)
  end
end

--- In the world, over everything: its shadow far below, then the machine.
function Flyers.draw()
  local f = flying
  if not f then
    return
  end
  love.graphics.push()
  love.graphics.translate(f.x + Flyers.SHADOW, f.y + Flyers.SHADOW)
  love.graphics.rotate(f.angle)
  love.graphics.setColor(0, 0, 0, 0.22)
  silhouette(f) -- its shadow on the ground, life size
  love.graphics.pop()
  love.graphics.push()
  love.graphics.translate(f.x, f.y)
  love.graphics.rotate(f.angle)
  love.graphics.scale(Flyers.SCALE)
  DRAW[f.kind](f)
  love.graphics.pop()
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 1, 1)
end

--- At night (the night feature): its lights, and the aerodyne's searchlight
--- on the ground, sweeping.
function Flyers.lights(glow)
  local f = flying
  if not f then
    return
  end
  local c, s = math.cos(f.angle) * Flyers.SCALE, math.sin(f.angle) * Flyers.SCALE
  local function at(x, y) -- its frame to the world
    return f.x + x * c - y * s, f.y + x * s + y * c
  end
  if f.kind == "aerodyne" then
    local x, y = at(-48, -21)
    glow(x, y, 26, RED, 0.9)
    x, y = at(-48, 21)
    glow(x, y, 26, GREEN, 0.9)
    if blink(1.2, 0.08) then
      x, y = at(-56, 0)
      glow(x, y, 60, WHITE, 1)
    end
    x, y = at(0, 0)
    glow(x, y, 90, MAGENTA, 0.35)
    -- The searchlight: a pool on the ground below and ahead, sweeping side to side.
    local sweep = math.sin(clock * 0.9 + f.seed) * 160
    local gx, gy = at(120, sweep)
    glow(gx + Flyers.SHADOW, gy + Flyers.SHADOW, 150, BEAM, 0.75)
    glow(gx + Flyers.SHADOW, gy + Flyers.SHADOW, 60, BEAM, 0.6)
  elseif f.kind == "hauler" then
    for _, bx in ipairs({ -50, 50 }) do
      local x, y = at(bx, 0)
      glow(x, y, 70, AMBER, 0.4 + 0.5 * math.abs(math.cos(clock * 6 + bx)))
    end
  else
    local tint = f.seed % 2 < 1 and MAGENTA or CYAN
    local x, y = at(-135, 0)
    glow(x, y, 170, tint, 0.55)
    x, y = at(6, 0)
    glow(x, y, 24, tint, 0.9)
  end
end

return Flyers
