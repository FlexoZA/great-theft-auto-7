-- Gun icons: one small side-on drawing per gun key, facing right, for the
-- inventory screen's weapon slots and for a gun lying in an item box
-- ("gun-<key>"). Unknown keys get a plain pistol-shaped stand-in. Drawn
-- about 60 x 30 px at scale 1, centred on (cx, cy).

local Icons = {}

local STEEL = { 0.80, 0.82, 0.88 }
local DARK = { 0.42, 0.44, 0.52 } -- gunmetal, light enough to read on a dark panel
local OLIVE = { 0.38, 0.45, 0.32 }
local RED = { 0.85, 0.2, 0.15 }

local function color(c, alpha)
  love.graphics.setColor(c[1], c[2], c[3], alpha)
end

local function pistol(a)
  color(STEEL, a)
  love.graphics.rectangle("fill", -18, -10, 32, 8, 2) -- slide
  love.graphics.rectangle("fill", 12, -8, 8, 4) -- muzzle
  color(DARK, a)
  love.graphics.rectangle("fill", -18, -2, 28, 4) -- frame
  love.graphics.polygon("fill", -14, 2, -4, 2, -8, 15, -18, 15) -- grip
  love.graphics.rectangle("fill", -16, -13, 3, 3) -- rear sight
  love.graphics.rectangle("fill", 8, -13, 2, 3) -- front sight
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", 2, 2, 6, 0.2, math.pi - 0.2) -- trigger guard
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("fill", 0, 2, 2, 5) -- trigger
end

local function uzi(a)
  love.graphics.translate(0, -4) -- the magazine hangs low: keep the whole gun centred
  color(DARK, a)
  love.graphics.rectangle("fill", -22, -8, 36, 13, 2) -- receiver
  love.graphics.rectangle("fill", -8, 5, 9, 14, 1) -- grip
  love.graphics.rectangle("fill", -18, -12, 3, 4) -- rear sight
  love.graphics.rectangle("fill", 8, -12, 3, 4) -- front sight
  color(STEEL, a)
  love.graphics.rectangle("fill", -6, 5, 5, 18) -- magazine, out of the grip
  love.graphics.rectangle("fill", 14, -5, 10, 5) -- barrel
  love.graphics.rectangle("fill", -32, -6, 11, 3) -- folded stock
  love.graphics.rectangle("fill", -32, -6, 3, 8)
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", 2, 5, 5, 0.2, math.pi - 0.2) -- trigger guard
  love.graphics.setLineWidth(1)
end

local function rocket(a)
  color(OLIVE, a)
  love.graphics.rectangle("fill", -24, -6, 44, 12, 3) -- tube
  love.graphics.polygon("fill", -24, -6, -31, -10, -31, 10, -24, 6) -- back bell
  love.graphics.polygon("fill", 20, -6, 27, -9, 27, 9, 20, 6) -- front bell
  color(DARK, a)
  love.graphics.rectangle("fill", -8, 6, 6, 11, 1) -- pistol grip
  love.graphics.rectangle("fill", 8, 6, 5, 8, 1) -- fore grip
  love.graphics.rectangle("fill", -4, -12, 4, 6) -- sight
  love.graphics.rectangle("fill", -22, 6, 20, 2) -- shoulder rest
  color(RED, a)
  love.graphics.polygon("fill", 27, -5, 35, 0, 27, 5) -- the rocket's nose
end

local WOOD = { 0.55, 0.36, 0.2 }

local function ak47(a)
  color(WOOD, a)
  love.graphics.polygon("fill", -34, -5, -22, -5, -22, 6, -36, 7) -- stock
  love.graphics.rectangle("fill", 4, -3, 12, 6) -- hand guard
  love.graphics.polygon("fill", -8, 3, -2, 3, -4, 13, -10, 13) -- grip
  color(DARK, a)
  love.graphics.rectangle("fill", -22, -7, 28, 10, 1) -- receiver
  love.graphics.polygon("fill", -6, 3, 4, 3, 8, 15, -1, 15) -- curved magazine
  love.graphics.rectangle("fill", -10, -11, 3, 4) -- rear sight
  love.graphics.rectangle("fill", 20, -12, 2, 5) -- front sight
  love.graphics.rectangle("fill", -22, -9, 8, 2) -- dust cover rib
  color(STEEL, a)
  love.graphics.rectangle("fill", 16, -4, 12, 3) -- gas tube
  love.graphics.rectangle("fill", 16, -1, 18, 3) -- barrel
  love.graphics.rectangle("fill", 32, -2, 4, 5) -- muzzle brake
end

local function shotgun(a)
  color(WOOD, a)
  love.graphics.polygon("fill", -36, -4, -22, -6, -22, 5, -38, 8) -- stock
  love.graphics.rectangle("fill", 4, -1, 14, 6, 2) -- pump
  color(DARK, a)
  love.graphics.rectangle("fill", -22, -6, 22, 9, 1) -- receiver
  love.graphics.rectangle("fill", -2, 1, 30, 4) -- magazine tube
  love.graphics.setLineWidth(2)
  love.graphics.arc("line", "open", -12, 3, 5, 0.2, math.pi - 0.2) -- trigger guard
  love.graphics.setLineWidth(1)
  color(STEEL, a)
  love.graphics.rectangle("fill", -2, -5, 38, 4) -- barrel
  love.graphics.rectangle("fill", 34, -6, 2, 3) -- bead
end

local DRAW = { pistol = pistol, uzi = uzi, rocket = rocket, ak47 = ak47, shotgun = shotgun }

--- Draw the icon for gun `key` centred on (cx, cy), `scale` times its
--- natural size, `alpha` (1) opaque.
function Icons.draw(key, cx, cy, scale, alpha)
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(scale or 1)
  local draw = DRAW[key] or pistol
  draw(alpha or 1)
  love.graphics.pop()
end

return Icons
