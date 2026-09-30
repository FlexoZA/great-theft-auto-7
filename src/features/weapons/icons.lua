-- Gun icons: one small side-on drawing per gun key, facing right, for the
-- inventory screen's weapon slots and for a gun lying in an item box
-- ("gun-<key>"). Unknown keys get a plain pistol-shaped stand-in. Drawn
-- about 60 x 30 px at scale 1, centred on (cx, cy).
--
-- Every part is shaded the same way (shade.lua, shared with the clothes
-- and armor): its colour, a lighter band along its top where the light
-- catches it, a darker one along its bottom, and a thin dark outline that
-- stays one pixel wide at any scale, so the drawings read as solid things
-- from the HUD down to a bag box.

local Shade = require("src.features.weapons.shade")

local Icons = {}

local STEEL = { 0.80, 0.82, 0.88 }
local DARK = { 0.42, 0.44, 0.52 } -- gunmetal, light enough to read on a dark panel
local BLACK = { 0.26, 0.27, 0.32 } -- grips, magazines, rubber
local OLIVE = { 0.38, 0.45, 0.32 }
local RED = { 0.85, 0.2, 0.15 }
local WOOD = { 0.55, 0.36, 0.2 }
local BRASS = { 0.85, 0.66, 0.25 }

local set, box, poly, line, strokes = Shade.set, Shade.box, Shade.poly, Shade.line, Shade.strokes

--- Wood grain: a couple of long faint lines along a stock or a fore end.
local function grain(x1, y1, x2, y2)
  line(WOOD, 0.75, 1, x1, y1, x2, y2)
  line(WOOD, 0.75, 1, x1 + 2, y1 + 3, x2 - 1, y2 + 3)
end

local function triggerGuard(x, y, r)
  line(DARK, 1, 2, x - r, y, x - r, y + r * 0.8, x - r * 0.4, y + r * 1.4, x + r, y + r * 1.4, x + r, y)
end

local function pistol()
  poly(BLACK, -14, 2, -3, 2, -7, 16, -18, 16) -- grip
  for i = 0, 2 do -- checkering on the grip panel
    for j = 0, 1 do
      set(BLACK, 1.5)
      love.graphics.circle("fill", -12 + j * 3 - i * 0.8, 6 + i * 3, 0.6)
    end
  end
  box(-18.5, 15, 11, 2.5, DARK, 0.5) -- magazine base plate
  box(-17, -3, 29, 5.5, DARK, 1) -- frame
  triggerGuard(1, 2.5, 5)
  line(STEEL, 0.8, 1.5, 1, 2.5, 0.5, 7) -- trigger
  box(-20.5, -10, 3, 4, DARK, 0.5) -- hammer
  box(13, -9, 6, 4.5, DARK, 0.5) -- barrel, out of the slide
  box(-18, -11.5, 32, 8.5, STEEL, 1.5) -- slide
  strokes(STEEL, 0.55, 4, -16, -10, 1.6, 5.5, true) -- serrations at the back of it
  box(0, -10.5, 6, 3.2, BLACK, 0.4) -- ejection port
  box(-16, -14, 4, 2.5, DARK, 0.3) -- rear sight
  box(10, -14, 2, 2.5, DARK, 0.3) -- front sight
end

local function uzi()
  love.graphics.translate(0, -4) -- the magazine hangs low: keep the whole gun centred
  box(-27, -8, 3.5, 11, DARK, 0.5) -- the folded stock's butt plate
  line(STEEL, 0.9, 1.5, -24, -6, -10, -6) -- its arms along the side
  line(STEEL, 0.9, 1.5, -24, 1, -10, 1)
  box(-6.5, 4, 5.5, 19, STEEL, 0.8) -- magazine, out of the grip
  strokes(STEEL, 0.7, 4, -6, 8, 3.5, 4.5) -- its ribs
  box(-7.5, 22, 7.5, 2.5, DARK, 0.5) -- its base
  box(-9, 4, 10, 14, BLACK, 1.5) -- grip, round the magazine
  box(-3, 5, 3, 12, BLACK, 1) -- the magazine seen through it
  box(-10.5, 6, 2, 8, DARK, 0.5) -- grip safety
  triggerGuard(5, 4.5, 4)
  line(STEEL, 0.8, 1.5, 4.5, 4.5, 4, 8.5) -- trigger
  box(-22, -9, 36, 13.5, DARK, 2) -- receiver
  line(DARK, 0.65, 1, -20, -4, 12, -4) -- the top cover's seam
  set(STEEL)
  love.graphics.circle("fill", -4, -11, 1.8) -- cocking knob
  set(DARK, 0.45)
  love.graphics.setLineWidth(Shade.pixel())
  love.graphics.circle("line", -4, -11, 1.8)
  set(STEEL, 1.1)
  love.graphics.circle("fill", -15, 0, 1) -- selector
  box(14, -6, 6, 6, STEEL, 1) -- barrel nut
  box(19.5, -4.5, 4.5, 3, STEEL, 0.5) -- barrel
  box(-19, -12.5, 3, 3.5, DARK, 0.3) -- rear sight
  box(9, -12.5, 3, 3.5, DARK, 0.3) -- front sight
end

local function ak47()
  poly(WOOD, -35, -5, -22, -5, -22, 6, -37, 8) -- stock
  grain(-34, -2, -23, -2)
  poly(BLACK, -37.5, -5.5, -34.5, -5.5, -34.5, 7.8, -37.5, 8.2) -- butt plate
  poly(WOOD, -8, 3, -2, 3, -4, 13, -10, 13) -- grip
  line(WOOD, 0.75, 1, -6.5, 5, -8, 11)
  -- The curved magazine, ribbed across.
  poly(DARK, -6, 3, 4, 3, 5.5, 8, -3.5, 8)
  poly(DARK, -3.5, 8, 5.5, 8, 8.5, 15, 0, 15)
  line(DARK, 0.6, 1, -4, 6, 4.5, 6)
  line(DARK, 0.6, 1, -2, 10, 6.5, 10)
  line(DARK, 0.6, 1, -0.5, 13, 7.5, 13)
  box(-22, -7, 28, 10.5, DARK, 1) -- receiver
  box(-22, -9, 20, 2.5, DARK, 0.5) -- dust cover, ribbed at the back
  strokes(DARK, 0.6, 3, -20, -8.5, 1.5, 1.8, true)
  line(STEEL, 0.9, 1.5, -14, -1, -8, -1) -- selector lever
  for _, rx in ipairs({ -18, -12, 1 }) do -- rivets
    set(DARK, 1.35)
    love.graphics.circle("fill", rx, 1.5, 0.7)
  end
  box(-10.5, -11.5, 3.5, 4.5, DARK, 0.4) -- rear sight block
  box(6, -4.5, 12, 7, WOOD, 1.5) -- lower hand guard
  grain(7, -2, 16, -2)
  box(16, -5, 12, 3, STEEL, 0.5) -- gas tube
  box(16, -1.5, 18, 3, STEEL, 0.5) -- barrel
  box(18, -8, 4, 3.5, DARK, 0.4) -- gas block
  box(20, -12.5, 1.8, 5, DARK, 0.3) -- front sight post
  box(32, -2.5, 5, 5, DARK, 0.8) -- muzzle brake
  line(DARK, 0.5, 1, 34.5, -2, 34.5, 2)
end

local function shotgun()
  poly(WOOD, -36, -4, -22, -6, -22, 5, -38, 8) -- stock
  grain(-35, -1, -23, -2.5)
  poly(BLACK, -38.5, -4.5, -35.5, -4.5, -35.5, 7.7, -38.5, 8.3) -- recoil pad
  triggerGuard(-12, 3, 4.5)
  line(STEEL, 0.8, 1.5, -12.5, 3, -13, 7) -- trigger
  box(-2, 1, 30, 4.5, DARK, 1) -- magazine tube
  box(26, 0.5, 3, 5.5, DARK, 0.5) -- its cap
  box(-22, -6.5, 22, 10, DARK, 1) -- receiver
  box(-14, -4.5, 7, 3, BLACK, 0.4) -- ejection port
  box(-12, 1.5, 6, 1.5, BLACK, 0.3) -- loading port
  box(-2, -5.5, 38, 4.5, STEEL, 0.8) -- barrel
  for i = 0, 8 do -- vent rib along the top
    box(1 + i * 3.8, -7, 1.6, 1.6, STEEL, 0)
  end
  set(BRASS)
  love.graphics.circle("fill", 35, -7, 1) -- front bead
  box(4, -1.5, 14, 7.5, WOOD, 2) -- pump
  strokes(WOOD, 0.6, 5, 6, -0.5, 2.3, 5.5, true) -- its grooves
end

local function rocket()
  box(-8, 5, 6, 12, BLACK, 1) -- pistol grip
  box(8, 5, 5, 9, BLACK, 1) -- fore grip
  triggerGuard(-1, 5.5, 3)
  box(-22, 5.5, 20, 2.5, DARK, 0.5) -- shoulder rest
  poly(OLIVE, -24, -6, -31, -10, -31, 10, -24, 6) -- back bell
  set(OLIVE, 0.35)
  love.graphics.ellipse("fill", -30.5, 0, 1.2, 8) -- looking into it
  poly(OLIVE, 20, -6, 27, -9, 27, 9, 20, 6) -- front bell
  box(-24, -6.5, 44, 13, OLIVE, 4) -- tube
  box(-17, -6.5, 3, 13, OLIVE, 0) -- bands round it
  box(12, -6.5, 3, 13, OLIVE, 0)
  box(4, -6.5, 5, 13, { 0.9, 0.75, 0.2 }, 0) -- the warning stripe
  box(-5, -13, 7, 6.5, DARK, 1) -- sight
  set({ 0.55, 0.8, 1 })
  love.graphics.rectangle("fill", 0.5, -11.5, 1, 3) -- its lens
  -- The rocket's nose, sticking out of the front.
  poly(RED, 27, -5, 34, -2, 34, 2, 27, 5)
  poly(RED, 34, -2, 37, 0, 34, 2)
  set(RED, 0.55)
  love.graphics.rectangle("fill", 27, -5, 1.5, 10)
end

local function sniper()
  poly(WOOD, -38, -3, -20, -5, -20, 5, -38, 9) -- stock
  grain(-37, 1, -21, -1)
  box(-36, -7, 11, 3.5, WOOD, 1) -- cheek rest
  poly(BLACK, -39.5, -3.3, -36.5, -3.3, -36.5, 8.6, -39.5, 9.4) -- butt pad
  poly(BLACK, -14, 4, -8, 4, -10, 12, -16, 12) -- grip
  box(-6, 4, 6, 5.5, BLACK, 0.5) -- box magazine
  line(DARK, 1, 1.5, 0, 11, 10, 11) -- the bipod, folded under the fore end
  line(DARK, 1, 1.5, 2, 12.5, 12, 12.5)
  box(-20, -4, 20, 8.5, DARK, 1) -- receiver
  box(-2, -2, 16, 6, WOOD, 2) -- fore end
  grain(0, 0, 12, 0)
  line(STEEL, 1, 1.5, -3, -3, -1, 1) -- bolt handle
  set(STEEL)
  love.graphics.circle("fill", -1, 1.5, 1.6) -- and its knob
  box(-10, -8, 2, 4.5, DARK, 0.3) -- scope mounts
  box(-2, -8, 2, 4.5, DARK, 0.3)
  box(-18, -13.5, 22, 6, BLACK, 3) -- the scope's tube
  box(-22, -14.5, 5, 8, BLACK, 1) -- eyepiece
  box(3, -15.5, 6, 10, BLACK, 1.5) -- objective bell
  box(-9, -16, 3, 3, DARK, 0.4) -- turrets
  box(-8.5, -9, 3, 2, DARK, 0.4)
  set({ 0.55, 0.8, 1 }, 1)
  love.graphics.rectangle("fill", 8, -14, 1.2, 7) -- the lens
  set({ 0.9, 0.97, 1 })
  love.graphics.rectangle("fill", 8, -13.5, 1.2, 2) -- and a glint on it
  box(14, -1.2, 22, 3, STEEL, 0.5) -- long barrel
  box(34, -2.5, 5, 5.5, DARK, 0.8) -- muzzle brake
  strokes(DARK, 0.5, 2, 35.5, -1.5, 2, 3.5, true)
end

--- The flamethrower: a red fuel tank under a long nozzle, a hose from the
--- tank to the gun, and a pilot flame at the tip.
local function flamethrower()
  box(0, 1, 6, 12, BLACK, 1) -- the grip
  box(12, 1, 4, 8, BLACK, 1) -- the fore grip
  triggerGuard(-4, 1.5, 3)
  -- The hose, looping from the tank's valve up into the back of the gun.
  line(BLACK, 1, 2.5, -9, 0, -12, -3, -16, -2, -18, 0)
  box(-27, 1, 22, 11.5, RED, 5.5) -- the tank
  box(-22, 1, 2.2, 11.5, STEEL, 0.3) -- straps round it
  box(-12, 1, 2.2, 11.5, STEEL, 0.3)
  box(-8, -1.5, 3.5, 3, BRASS, 0.5) -- its valve
  box(-20, -6.5, 42, 7.5, DARK, 2) -- the body and barrel
  strokes(DARK, 0.55, 5, 4, -5.5, 3, 5.5, true) -- vents in the heat shield
  box(21, -8.5, 7, 11.5, DARK, 1) -- the nozzle
  box(27, -7, 2, 8.5, STEEL, 0.5) -- its ring
  box(22, 3, 5, 2.5, BRASS, 0.5) -- the igniter under it
  set({ 1, 0.5, 0.1 })
  love.graphics.circle("fill", 32, -3, 3.2) -- the pilot flame
  set({ 1, 0.85, 0.35 })
  love.graphics.circle("fill", 31.5, -3, 1.8)
  set({ 1, 1, 0.8 })
  love.graphics.circle("fill", 31, -3, 0.8)
end

local DRAW = {
  pistol = pistol, uzi = uzi, rocket = rocket, ak47 = ak47, shotgun = shotgun, sniper = sniper,
  flamethrower = flamethrower,
}

--- Draw the icon for gun `key` centred on (cx, cy), `scale` times its
--- natural size, `a` (1) opaque.
function Icons.draw(key, cx, cy, scale, a)
  scale = scale or 1
  Shade.begin(scale, a)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale)
  local draw = DRAW[key] or pistol
  draw()
  love.graphics.pop()
  Shade.finish()
end

return Icons
