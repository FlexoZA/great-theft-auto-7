-- How Hyperbole's haulers look (docs/borderline.md, "The army"), seen from
-- above at world size, facing +x in their own frame: a loader robot on two
-- thin legs, a squat hull in Hyperbole yellow over gunmetal, a hazard stripe
-- across its back, and up front the round head that is nearly all red eye. Every model is that one body with
-- its own kit on it (`Look.KITS`, by code): what its arms carry, what is on
-- its back, its colours and its size.
--
--   JNK  junk: patched, a panel missing, a rust-red arm with a pistol
--   GUN  a rifle arm and a grenade launcher
--   RPG  a launcher arm and two rocket pods on its back
--   PLZ  a plasma cannon, purple coils down it, a Bragium tank on its back
--   EXP  stripped to the frame, a red core blinking in its chest, no arms
--   DZR  wide, a bulldozer blade across its front
--   ARC  blue coils on both arms, a dish on its back
--   JET  wings folded on its back and thrusters; spread when it flies
--   BAD  the badass: bigger, black and yellow, horns, twin war cannons, pods
--   STK  the stalker: tall on three long legs, one red eye slit, a flechette
--        pod on each shoulder
--
--   Look.draw(h, clock)
--       h: { dx, dy, facing, code, stride, charge, flash, crawl, flying }
--       `stride` the distance walked (the legs step with it), `charge` 0..1
--       a weapon winding up (coils glow, pods open, the core blinks
--       faster), `flash` 0..1 just hit, `crawl` true for the torso crawl
--       (legs gone, sparking, dragging itself), `flying` for a jet hauler
--       in the air (drawn higher: a shadow below, wings out)
--   Look.drawWreck(w, clock)   where one fell: w { x, y, angle, code }
--   Look.radius(code)          its size, px (for hit boxes and the HUD)

local Look = {}

Look.C = {
  yellow = { 0.95, 0.76, 0.19 },
  yellowDark = { 0.74, 0.55, 0.10 },
  gunmetal = { 0.23, 0.25, 0.28 },
  gunmetalLight = { 0.38, 0.41, 0.46 },
  steel = { 0.62, 0.65, 0.70 },
  ink = { 0.06, 0.06, 0.07 },
  eye = { 1.00, 0.19, 0.19 },
  eyeHot = { 1.00, 0.75, 0.70 },
  rust = { 0.58, 0.26, 0.14 },
  rustDark = { 0.40, 0.18, 0.10 },
  plasma = { 0.71, 0.30, 1.00 },
  plasmaHot = { 0.92, 0.75, 1.00 },
  arc = { 0.35, 0.75, 1.00 },
  arcHot = { 0.80, 0.95, 1.00 },
  black = { 0.12, 0.12, 0.13 },
  rocket = { 0.85, 0.18, 0.12 },
  flame = { 1.00, 0.60, 0.15 },
  white = { 1, 1, 1 },
}
local C = Look.C

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A filled rounded box with the black outline round it.
local function plate(x, y, w, h, fill, r)
  color(C.ink)
  love.graphics.rectangle("fill", x - 1.2, y - 1.2, w + 2.4, h + 2.4, (r or 1) + 1)
  color(fill)
  love.graphics.rectangle("fill", x, y, w, h, r or 1)
end

local function disc(x, y, r, fill)
  color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.2, 16)
  color(fill)
  love.graphics.circle("fill", x, y, r, 16)
end

local function glow(c, a, x, y, r)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", x, y, r, 14)
  love.graphics.setBlendMode("alpha")
end

-- Parts -------------------------------------------------------------------------

--- Two thin legs stepping by `stride`: out from the hips, back to the
--- knee (they bend backwards, like a bird's) and down to a pad of a foot,
--- wide of the hull so it reads as standing tall.
local function legs(k, stride)
  if k.tripod then
    -- Three long legs, two forward and one back, each kinked out at the
    -- knee; they step by turns.
    for i, leg in ipairs({ { 8, -1 }, { 8, 1 }, { -12, 0 } }) do
      local step = math.sin(stride * 0.16 + i * 2.1) * 5
      local hx, hy = leg[1] * 0.4, leg[2] * 5
      local fx, fy = leg[1] + step + (leg[2] == 0 and -14 or 7), leg[2] * 23
      local kx, ky = (hx + fx) / 2 + (leg[2] == 0 and 0 or -4), (hy + fy) / 2 + (leg[2] == 0 and 9 or leg[2] * 6)
      for pass = 1, 2 do
        color(pass == 1 and C.ink or C.gunmetalLight)
        love.graphics.setLineWidth(pass == 1 and 4.2 or 2.4)
        love.graphics.line(hx, hy, kx, ky, fx, fy)
      end
      love.graphics.setLineWidth(1)
      disc(kx, ky, 1.9, C.yellowDark)
      disc(fx, fy, 1.7, C.gunmetal) -- a spike of a foot
    end
    return
  end
  local spread = k.wide and 15 or 13
  for _, side in ipairs({ -1, 1 }) do
    local step = math.sin(stride * 0.18) * 6 * side
    local kx, ky = -8 - step * 0.3, side * (spread - 2)
    local fx, fy = 1 + step, side * spread
    for pass = 1, 2 do
      color(pass == 1 and C.ink or C.gunmetalLight)
      love.graphics.setLineWidth(pass == 1 and 4 or 2.2)
      love.graphics.line(-3, side * 5, kx, ky, fx, fy)
    end
    love.graphics.setLineWidth(1)
    disc(kx, ky, 1.8, C.yellowDark) -- the knee joint
    plate(fx - 1, fy - 2.5, 7, 5, C.gunmetal, 2) -- the foot
  end
end

--- An arm out of the hull's side (`side` -1 left, 1 right) holding a gun
--- whose barrel is `len` long and `thick` across, in `fill`.
local function gunArm(side, len, thick, fill, muzzle)
  local y = side * 8
  plate(-3, y - 2, 7, 4, C.gunmetal) -- the shoulder
  plate(2, y - thick / 2, len, thick, fill, 1)
  if muzzle then
    plate(2 + len - 3, y - thick / 2 - 0.8, 4, thick + 1.6, muzzle, 1)
  end
end

--- The hull: yellow plates over gunmetal, a hazard stripe across the back,
--- a strip of the model's trim colour up front. `stripped` leaves only the
--- frame.
local function hull(k)
  local w, h = 16, k.wide and 20 or 16
  if k.stripped then
    plate(-9, -h / 2, w, h, C.gunmetal, 3)
    color(C.gunmetalLight) -- the frame's struts
    love.graphics.rectangle("fill", -9, -1, w, 2)
    love.graphics.rectangle("fill", -2, -h / 2, 2, h)
    return
  end
  plate(-9, -h / 2, w, h, k.body or C.yellow, 3)
  -- The hazard stripe across the back.
  for i = 0, math.floor(h / 3) - 1 do
    color(i % 2 == 0 and C.ink or (k.body or C.yellow))
    love.graphics.rectangle("fill", -9, -h / 2 + i * 3 + 0.5, 3, 3)
  end
  if k.patched then -- junk: a rust patch and a panel off
    color(C.rust)
    love.graphics.rectangle("fill", -2, -h / 2 + 1, 6, 5)
    color(C.ink)
    love.graphics.rectangle("fill", 0, h / 2 - 6, 5, 4)
    color(C.eye, 0.8) -- wires showing
    love.graphics.line(1, h / 2 - 5, 4, h / 2 - 3)
  end
  color(k.trim or C.gunmetal) -- the model's trim along the hull's front edge
  love.graphics.rectangle("fill", 3, -h / 2 + 2, 2, h - 4)
end

--- The head up front: a gunmetal ring round the big red eye, lit brighter
--- when hit or winding up.
local function head(k, heat, clock)
  local hx = k.wide and 9 or 8
  disc(hx, 0, 6, C.gunmetal)
  if k.horns then
    color(C.ink)
    love.graphics.polygon("fill", hx - 3, -5, hx + 4, -11, hx + 1, -4)
    love.graphics.polygon("fill", hx - 3, 5, hx + 4, 11, hx + 1, 4)
  end
  local pulse = 0.75 + 0.25 * math.sin(clock * 4)
  if k.slit then -- one narrow slit across a dark visor
    disc(hx, 0, 6, C.black)
    color(C.eye, pulse)
    love.graphics.rectangle("fill", hx + 1.5, -4.6, 2.4, 9.2, 1)
    color(C.eyeHot, 0.4 + 0.6 * heat)
    love.graphics.rectangle("fill", hx + 2.1, -2 - heat, 1.2, 4 + 2 * heat)
    if heat > 0 then
      glow(C.eye, 0.4 * heat, hx + 2.5, 0, 9)
    end
    return
  end
  color(C.eye, pulse)
  love.graphics.circle("fill", hx + 0.8, 0, 4.2, 16)
  color(C.eyeHot, 0.5 + 0.5 * heat)
  love.graphics.circle("fill", hx + 1.8, -0.6, 1.6 + heat, 10)
  if heat > 0 then
    glow(C.eye, 0.4 * heat, hx + 1, 0, 8)
  end
end

-- The kits ------------------------------------------------------------------------

Look.KITS = {}

Look.KITS.JNK = {
  trim = C.rust,
  scale = 1,
  patched = true,
  arms = function()
    gunArm(-1, 4, 3, C.gunmetalLight) -- a stub where the other arm was
    gunArm(1, 9, 3, C.rust, C.gunmetal) -- a pistol on the rust-red arm
  end,
}

Look.KITS.GUN = {
  scale = 1,
  arms = function()
    gunArm(-1, 9, 5, C.gunmetal, C.yellowDark) -- the grenade launcher: short and fat
    gunArm(1, 17, 3, C.gunmetal, C.ink) -- the rifle
  end,
}

local function pods(charge, x)
  for _, side in ipairs({ -1, 1 }) do
    local y = side * 6
    plate(x, y - 4, 7, 8, C.gunmetal, 1)
    for i = 0, 3 do
      local rx, ry = x + 1.7 + (i % 2) * 3.6, y - 2 + math.floor(i / 2) * 4
      color(charge > 0 and C.flame or C.rocket)
      love.graphics.circle("fill", rx, ry, 1.3, 8)
    end
    if charge > 0 then
      glow(C.flame, 0.35 * charge, x + 3.5, y, 6)
    end
  end
end

Look.KITS.RPG = {
  trim = C.rocket,
  scale = 1.1,
  arms = function()
    gunArm(-1, 6, 3, C.gunmetalLight)
    gunArm(1, 14, 6, C.gunmetal, C.rocket) -- the launcher: a wide tube, a warhead in its mouth
  end,
  back = function(charge)
    pods(charge, -16)
  end,
}

local function coils(y, x0, n, c, hot, charge, clock)
  for i = 0, n - 1 do
    local g = charge > 0 and (0.5 + 0.5 * math.sin(clock * 30 + i)) * charge or 0.15
    love.graphics.setColor(c[1] + (hot[1] - c[1]) * g, c[2] + (hot[2] - c[2]) * g, c[3] + (hot[3] - c[3]) * g)
    love.graphics.rectangle("fill", x0 + i * 4, y - 3, 2.2, 6)
  end
end

Look.KITS.PLZ = {
  trim = C.plasma,
  scale = 1.05,
  arms = function(charge, clock)
    gunArm(-1, 6, 3, C.gunmetalLight)
    gunArm(1, 16, 6, C.gunmetal, C.gunmetalLight)
    coils(8, 5, 3, C.plasma, C.plasmaHot, charge, clock)
    if charge > 0 then
      glow(C.plasma, 0.6 * charge, 19, 8, 4 + 5 * charge)
    end
  end,
  back = function(_, clock)
    -- The Bragium tank: a glass cylinder of purple, sloshing.
    plate(-17, -5, 8, 10, C.gunmetal, 3)
    color(C.plasma, 0.85 + 0.15 * math.sin(clock * 2))
    love.graphics.rectangle("fill", -16, -4, 6, 8, 2)
    color(C.plasmaHot, 0.6)
    love.graphics.rectangle("fill", -15, -3, 1.5, 6)
  end,
}

Look.KITS.EXP = {
  scale = 0.95,
  stripped = true,
  arms = function(charge, clock)
    -- No arms: the core, blinking faster the closer it gets to going off.
    local rate = 3 + 20 * charge
    local on = math.sin(clock * rate) > 0
    disc(-2, 0, 4, on and C.eye or C.rustDark)
    if on then
      glow(C.eye, 0.5 + 0.4 * charge, -2, 0, 8 + 6 * charge)
    end
  end,
}

Look.KITS.DZR = {
  trim = C.yellowDark,
  scale = 1.15,
  wide = true,
  arms = function()
    gunArm(1, 6, 4, C.gunmetal)
    gunArm(-1, 6, 4, C.gunmetal)
    -- The blade across the front, curved, hazard striped along its edge.
    color(C.ink)
    love.graphics.setLineWidth(6)
    love.graphics.arc("line", "open", -2, 0, 20, -0.95, 0.95, 12)
    color(C.yellowDark)
    love.graphics.setLineWidth(3.6)
    love.graphics.arc("line", "open", -2, 0, 20, -0.95, 0.95, 12)
    love.graphics.setLineWidth(1)
    color(C.ink)
    for i = -3, 3 do
      local a = i * 0.27
      love.graphics.circle("fill", -2 + math.cos(a) * 21.5, math.sin(a) * 21.5, 0.9, 6)
    end
  end,
}

Look.KITS.ARC = {
  trim = C.arc,
  scale = 1,
  arms = function(charge, clock)
    for _, side in ipairs({ -1, 1 }) do
      gunArm(side, 12, 5, C.gunmetal, C.arc)
      coils(side * 8, 4, 2, C.arc, C.arcHot, charge, clock)
    end
    if charge > 0 then
      glow(C.arc, 0.5 * charge, 14, 0, 10 + 6 * charge)
    end
  end,
  back = function(_, clock)
    -- The dish that throws the dome up.
    disc(-14, 0, 6, C.gunmetalLight)
    disc(-14, 0, 3.5, C.gunmetal)
    color(C.arc, 0.6 + 0.4 * math.sin(clock * 5))
    love.graphics.circle("fill", -14, 0, 1.6, 8)
  end,
}

Look.KITS.JET = {
  trim = C.white,
  scale = 1,
  arms = function()
    gunArm(-1, 8, 3, C.gunmetal, C.ink)
    gunArm(1, 14, 3, C.gunmetal, C.ink)
  end,
  back = function(_, clock, flying)
    local spread = flying and 1 or 0
    for _, side in ipairs({ -1, 1 }) do
      -- A wing: folded back along the hull, or swept out.
      local tipX, tipY = -16 + 8 * spread, side * (7 + 15 * spread)
      color(C.ink)
      love.graphics.polygon("fill", -6, side * 3, tipX - 1, tipY + side, -14, side * 3)
      color(C.yellow)
      love.graphics.polygon("fill", -7, side * 3.5, tipX, tipY, -13, side * 3.5)
    end
    plate(-15, -4, 4, 8, C.gunmetal) -- the thrusters
    if flying then
      local f = 0.7 + 0.3 * math.sin(clock * 40)
      glow(C.flame, 0.7 * f, -17, 0, 6)
      color(C.flame, f)
      love.graphics.polygon("fill", -15, -2.5, -23 - 4 * f, 0, -15, 2.5)
    end
  end,
}

Look.KITS.BAD = {
  scale = 1.6,
  body = { 0.20, 0.20, 0.22 },
  trim = C.yellow,
  horns = true,
  arms = function(charge)
    for _, side in ipairs({ -1, 1 }) do
      gunArm(side, 15, 7, C.gunmetal, C.yellow) -- the war cannons
      color(C.ink)
      love.graphics.rectangle("fill", 13, side * 8 - 1, 5, 2)
    end
    if charge > 0 then
      glow(C.flame, 0.4 * charge, 18, 0, 10)
    end
  end,
  back = function(charge)
    pods(charge, -17)
  end,
}

Look.KITS.STK = {
  trim = C.eye,
  scale = 1.25,
  tripod = true,
  slit = true,
  arms = function(charge)
    -- A flechette pod on each shoulder, the darts' tips showing in its mouth.
    for _, side in ipairs({ -1, 1 }) do
      local y = side * 9
      plate(-3, y - 3.5, 13, 7, C.gunmetal, 2)
      color(C.ink)
      love.graphics.rectangle("fill", 8, y - 2.8, 2.4, 5.6)
      color(charge > 0 and C.yellow or C.steel)
      for i = 0, 2 do
        love.graphics.rectangle("fill", 8.6, y - 2.2 + i * 1.8, 1.8, 0.9)
      end
      if charge > 0 then
        glow(C.yellow, 0.45 * charge, 10, y, 4 + 4 * charge)
      end
    end
  end,
}

-- Drawing -----------------------------------------------------------------------

local function kitOf(code)
  return Look.KITS[code] or Look.KITS.GUN
end

function Look.radius(code)
  return 13 * kitOf(code).scale
end

--- Sparks off torn wiring at (x, y), now and then.
local function sparks(x, y, clock, seed)
  local t = (clock * 3 + seed) % 1
  if t < 0.35 then
    color(C.flame)
    for i = 0, 2 do
      local a = seed + i * 2.1 + clock * 7
      love.graphics.circle("fill", x + math.cos(a) * 5 * t * 3, y + math.sin(a) * 5 * t * 3, 0.9, 5)
    end
  end
end

function Look.draw(h, clock)
  local k = kitOf(h.code)
  local charge, flash = h.charge or 0, h.flash or 0
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  local lift = h.flying and 18 or 0
  love.graphics.setColor(0, 0, 0, h.flying and 0.22 or 0.35) -- the shadow, further off when it flies
  love.graphics.ellipse("fill", 3 + lift * 0.4, 4 + lift, 14 * k.scale, 12 * k.scale, 18)
  love.graphics.rotate(h.facing or 0)
  love.graphics.scale(k.scale * (h.flying and 1.12 or 1))
  if h.crawl then
    -- Legs gone: the hull drags itself along on its arms, scrape marks
    -- behind it, sparks off the torn hips.
    color(C.ink, 0.35)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(-10, -4, -24, -5)
    love.graphics.line(-10, 4, -22, 6)
    love.graphics.setLineWidth(1)
    color(C.gunmetalLight)
    love.graphics.rectangle("fill", -12, -5, 3, 2)
    love.graphics.rectangle("fill", -12, 3, 3, 2)
    sparks(-11, 4, clock, 1.3)
    sparks(-11, -4, clock, 2.9)
  elseif not h.flying then
    legs(k, h.stride or 0)
  end
  if k.back then
    k.back(charge, clock, h.flying)
  end
  hull(k)
  k.arms(charge, clock)
  head(k, math.max(charge, flash), clock)
  if flash > 0 then -- the hit: everything goes white for a moment
    love.graphics.setColor(1, 1, 1, 0.55 * flash)
    love.graphics.rectangle("fill", -10, -9, 22, 18, 4)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where one fell: in pieces, its eye dark, oil under it, sparking.
function Look.drawWreck(w, clock)
  local k = kitOf(w.code)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle + 0.5)
  love.graphics.scale(k.scale)
  color(C.ink, 0.55) -- oil
  love.graphics.ellipse("fill", 1, 2, 18, 13, 18)
  legs(k, 0)
  hull(k)
  k.arms(0, 0)
  disc(8, 0, 6, C.gunmetal)
  color(C.rustDark) -- the eye, out
  love.graphics.circle("fill", 8.8, 0, 4.2, 16)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", 0, 0, 12, 11, 16)
  sparks(4, 3, clock, w.x % 7)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
