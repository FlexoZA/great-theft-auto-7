-- How Wilbur looks (docs/borderline.md, "The bosses"), seen from above at
-- world size, facing +x in his own frame, in the haulers' outlined style
-- (hauler_look.lua's colours): Max's cyborg enforcer, a broad slab of a
-- man in Hyperbole plate. His right arm is a rotary gun, his left a steel
-- fist; a rocket pod sits on his left shoulder; his head is half a man's
-- (a buzz cut, a scowl) and half steel, with a red eye. Upgraded, the
-- seams of his plates glow.
--
--   Look.draw(h, clock)
--       h: { dx, dy, facing, stride, charge, flash, flying }
--       `charge` 0..1 the pod opening or a leap crouched for, `flash` 0..1
--       just hit, `flying` up in a leap (drawn higher, a shadow below)
--   Look.drawWreck(w, clock)    where he fell: w { x, y, angle }
--   Look.upgraded               set by wilbur.lua once Max's upgrade is in

local Hauler = require("src.features.borderline.hauler_look")

local Look = {}

Look.upgraded = false

local C = Hauler.C
local SKIN = { 0.86, 0.66, 0.54 }
local SKIN_DARK = { 0.62, 0.44, 0.36 }
local HAIR = { 0.28, 0.24, 0.22 }
local GLOW = { 1.00, 0.55, 0.15 }

local function color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A filled rounded box with the black outline round it.
local function plate(x, y, w, h, fill, r)
  color(C.ink)
  love.graphics.rectangle("fill", x - 1.5, y - 1.5, w + 3, h + 3, (r or 2) + 1.5)
  color(fill)
  love.graphics.rectangle("fill", x, y, w, h, r or 2)
end

local function disc(x, y, r, fill)
  color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.5, 20)
  color(fill)
  love.graphics.circle("fill", x, y, r, 20)
end

local function glow(c, a, x, y, r)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", x, y, r, 18)
  love.graphics.setBlendMode("alpha")
end

--- His feet, stepping by `stride`: one ahead as the other goes back.
local function feet(stride)
  local step = math.sin(stride * 0.09) * 7
  plate(-6 + step, -17, 16, 9, C.gunmetal, 3)
  plate(-6 - step, 8, 16, 9, C.gunmetal, 3)
end

--- The gun arm (right, +y): a shoulder plate, the arm, the rotary barrels.
local function gunArm(charge, clock)
  plate(-8, 15, 14, 12, C.yellow, 3)
  plate(2, 18, 16, 8, C.gunmetal, 2)
  plate(16, 17, 20, 10, C.gunmetalLight, 2)
  color(C.ink)
  local spin = (clock * (charge > 0 and 30 or 4)) % 3
  for i = 0, 2 do
    love.graphics.rectangle("fill", 18, 18.5 + ((i + spin) % 3) * 2.6, 18, 1.2)
  end
end

--- The fist arm (left, -y): a shoulder plate, the arm, a big steel fist.
local function fistArm()
  plate(-8, -27, 14, 12, C.yellow, 3)
  plate(2, -25, 12, 8, C.gunmetal, 2)
  disc(18, -21, 7, C.steel)
  color(C.gunmetal)
  for i = -1, 1 do -- knuckles
    love.graphics.rectangle("fill", 22, -22.5 + i * 3.4, 3, 2)
  end
end

--- The rocket pod on his left shoulder, its four tubes glowing as it opens.
local function pod(charge)
  plate(-20, -28, 13, 12, C.gunmetal, 2)
  for i = 0, 3 do
    local rx, ry = -16.5 + (i % 2) * 6, -24.5 + math.floor(i / 2) * 5
    color(charge > 0 and C.flame or C.rocket)
    love.graphics.circle("fill", rx, ry, 1.8, 8)
  end
  if charge > 0 then
    glow(C.flame, 0.45 * charge, -14, -22, 9)
  end
end

--- The torso: Hyperbole plate over his back, a hazard stripe across it, the
--- seams lit when he is upgraded.
local function torso(clock)
  plate(-18, -16, 30, 32, C.yellow, 6)
  color(C.yellowDark)
  love.graphics.rectangle("fill", -10, -14, 14, 28, 3)
  for i = 0, 6 do -- the hazard stripe down his back
    color(i % 2 == 0 and C.ink or C.yellow)
    love.graphics.rectangle("fill", -17, -14 + i * 4, 4, 4)
  end
  color(C.gunmetal) -- a cable from his back to his head
  love.graphics.setLineWidth(2)
  love.graphics.line(-8, -6, 0, -4, 6, -7)
  love.graphics.setLineWidth(1)
  if Look.upgraded then
    local k = 0.6 + 0.4 * math.sin(clock * 6)
    color(GLOW, k)
    love.graphics.setLineWidth(1.5)
    love.graphics.line(-10, -14, -10, 14)
    love.graphics.line(4, -14, 4, 14)
    love.graphics.line(-10, 0, 4, 0)
    love.graphics.setLineWidth(1)
    glow(GLOW, 0.2 * k, -3, 0, 22)
  end
end

--- His head: the man's half (left, -y) and the steel half with its eye.
local function head(heat, clock)
  local hx = 6
  disc(hx, 0, 9, SKIN)
  color(HAIR) -- a buzz cut over the man's half
  love.graphics.arc("fill", hx - 1, 0, 8.5, math.pi * 0.55, math.pi * 1.5, 12)
  color(SKIN_DARK) -- a scowl's brow
  love.graphics.rectangle("fill", hx + 4, -6, 3, 4)
  color(C.ink)
  love.graphics.arc("fill", hx, 0, 9.5, -0.05, math.pi * 0.5 + 0.05, 12)
  color(C.gunmetalLight) -- the steel half
  love.graphics.arc("fill", hx, 0, 8.5, 0, math.pi * 0.5, 12)
  local pulse = 0.8 + 0.2 * math.sin(clock * 4)
  color(C.eye, pulse)
  love.graphics.circle("fill", hx + 5, 3.5, 2.6, 12)
  color(C.eyeHot, 0.5 + 0.5 * heat)
  love.graphics.circle("fill", hx + 5.6, 3, 1.1 + heat, 8)
  if heat > 0 then
    glow(C.eye, 0.4 * heat, hx + 5, 3.5, 10)
  end
end

function Look.draw(h, clock)
  local charge, flash = h.charge or 0, h.flash or 0
  love.graphics.push()
  love.graphics.translate(h.dx, h.dy)
  local lift = h.flying and 34 or 0
  love.graphics.setColor(0, 0, 0, h.flying and 0.2 or 0.35) -- the shadow, smaller and further off up a leap
  love.graphics.ellipse("fill", 4 + lift * 0.3, 6 + lift, 34 - lift * 0.3, 30 - lift * 0.3, 24)
  love.graphics.rotate(h.facing or 0)
  love.graphics.scale(h.flying and 1.15 or 1)
  if not h.flying then
    feet(h.stride or 0)
  end
  gunArm(charge, clock)
  fistArm()
  torso(clock)
  pod(charge)
  head(math.max(charge, flash), clock)
  if flash > 0 then -- the hit: everything goes white for a moment
    love.graphics.setColor(1, 1, 1, 0.5 * flash)
    love.graphics.rectangle("fill", -18, -26, 40, 52, 8)
  end
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

--- Where he fell: face down, his eye out, oil under him, smoking.
function Look.drawWreck(w, clock)
  love.graphics.push()
  love.graphics.translate(w.x, w.y)
  love.graphics.rotate(w.angle + 0.4)
  color(C.ink, 0.55) -- oil
  love.graphics.ellipse("fill", 2, 3, 40, 32, 24)
  gunArm(0, 0)
  fistArm()
  torso(0)
  pod(0)
  disc(6, 0, 9, SKIN_DARK)
  color(C.rustDark) -- the eye, out
  love.graphics.circle("fill", 11, 3.5, 2.6, 12)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.ellipse("fill", 0, 0, 22, 26, 18)
  local t = (clock * 0.7) % 1 -- smoke off his back
  love.graphics.setColor(0.3, 0.3, 0.32, 0.4 * (1 - t))
  love.graphics.circle("fill", -6 - t * 10, -t * 18, 6 + t * 10, 14)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
