-- Ability icons: one small drawing per ability key, for the HUD's ring
-- row, the inventory's ability slots and an ability carried in a bag
-- ("ability-<key>"). Drawn on a 32 x 32 grid centred on (0, 0) and scaled
-- to fit a circle of radius `r`, mostly in the ability's own colour with
-- white for highlights. Unknown keys get a plain dot.

local Kinds = require("src.features.abilities.kinds")

local Icons = {}

local WHITE = { 1, 1, 1 }

local function color(c, alpha, k)
  k = k or 1
  love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, (c[4] or 1) * alpha)
end

-- A snowflake: six arms, each with a pair of twigs.
local function freeze(c, a)
  color(c, a)
  love.graphics.setLineWidth(2.4)
  for i = 0, 5 do
    local t = i * math.pi / 3 - math.pi / 2
    local dx, dy = math.cos(t), math.sin(t)
    love.graphics.line(0, 0, dx * 14, dy * 14)
    for _, s in ipairs({ -1, 1 }) do
      local tw = t + s * 0.75
      local bx, by = dx * 8, dy * 8
      love.graphics.line(bx, by, bx + math.cos(tw) * 5, by + math.sin(tw) * 5)
    end
  end
  color(WHITE, a)
  love.graphics.circle("fill", 0, 0, 3, 12)
end

local function heart(x, y, s)
  love.graphics.circle("fill", x - 5 * s, y - 3 * s, 6 * s, 20)
  love.graphics.circle("fill", x + 5 * s, y - 3 * s, 6 * s, 20)
  love.graphics.polygon("fill", x - 10.6 * s, y - 0.5 * s, x + 10.6 * s, y - 0.5 * s, x, y + 11 * s)
end

-- A heart that keeps topping itself up: little pluses rising off it.
local function regen(c, a)
  color(c, a)
  heart(-2, 2, 0.95)
  color(WHITE, a * 0.35)
  love.graphics.circle("fill", -7, -3, 2.5, 10) -- shine
  color(WHITE, a)
  love.graphics.setLineWidth(2)
  love.graphics.line(11, -13, 11, -5)
  love.graphics.line(7, -9, 15, -9)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(13, 0, 13, 5)
  love.graphics.line(10.5, 2.5, 15.5, 2.5)
end

-- A medic's cross, in one go.
local function heal(c, a)
  color(WHITE, a)
  love.graphics.rectangle("fill", -6.5, -14.5, 13, 29, 3)
  love.graphics.rectangle("fill", -14.5, -6.5, 29, 13, 3)
  color(c, a)
  love.graphics.rectangle("fill", -4.5, -12.5, 9, 25, 2)
  love.graphics.rectangle("fill", -12.5, -4.5, 25, 9, 2)
end

-- A machine gun on a wall of sandbags, the muzzle lit.
local function mgnest(c, a)
  love.graphics.setLineWidth(1)
  for _, b in ipairs({ { -9, 5 }, { 3, 5 }, { -15, 11 }, { -3, 11 }, { 9, 11 }, { 14, 5 } }) do
    love.graphics.setColor(0.72, 0.62, 0.42, a)
    love.graphics.rectangle("fill", b[1] - 5.5, b[2] - 3, 11, 6, 3)
    love.graphics.setColor(0.42, 0.35, 0.22, a)
    love.graphics.rectangle("line", b[1] - 5.5, b[2] - 3, 11, 6, 3)
  end
  love.graphics.setColor(0.62, 0.65, 0.72, a)
  love.graphics.rectangle("fill", -15, -7, 7, 5, 1) -- stock
  love.graphics.rectangle("fill", -9, -9, 12, 8, 1) -- receiver
  love.graphics.rectangle("fill", 3, -7, 8, 4) -- barrel jacket
  love.graphics.rectangle("fill", 11, -6, 4, 2) -- muzzle
  love.graphics.setColor(0.35, 0.37, 0.43, a)
  love.graphics.rectangle("fill", -6, -12, 6, 3) -- feed cover
  love.graphics.setLineWidth(2)
  love.graphics.line(-3, -1, -3, 2) -- mount, on the bags
  color(c, a)
  love.graphics.polygon("fill", 15, -8, 20, -5, 15, -2) -- muzzle flash
  love.graphics.setLineWidth(1)
end

-- A green cloud with stink lines coming off it.
local function fart(c, a)
  color(c, a, 0.75)
  love.graphics.circle("fill", -7, 7, 7, 20)
  love.graphics.circle("fill", 7, 7, 7, 20)
  color(c, a)
  love.graphics.circle("fill", 0, 3, 9, 24)
  love.graphics.circle("fill", -9, 9, 5, 16)
  love.graphics.circle("fill", 9, 9, 5, 16)
  color(WHITE, a * 0.3)
  love.graphics.circle("fill", -3, 0, 3, 12)
  color(c, a)
  love.graphics.setLineWidth(2)
  for i = -1, 1 do
    -- A wavy line rising off the cloud.
    local pts = {}
    for k = 0, 8 do
      local y = -8 - k * 1.1
      pts[#pts + 1] = i * 7 + math.sin(k * 0.9 + i) * 2.2
      pts[#pts + 1] = y
    end
    love.graphics.line(pts)
  end
end

-- A border fence with a gap torn in it and an arrow coming through.
local function openborders(c, a)
  love.graphics.setColor(0.72, 0.74, 0.8, a)
  love.graphics.setLineWidth(2)
  for _, side in ipairs({ -1, 1 }) do
    local x0, x1 = side * 5, side * 16
    love.graphics.line(x0, -2, x1, -2) -- rails
    love.graphics.line(x0, 4, x1, 4)
    for _, x in ipairs({ side * 6, side * 11, side * 16 }) do
      love.graphics.line(x, -6, x, 8) -- posts
    end
  end
  -- Barbed wire curling off the torn ends.
  love.graphics.setLineWidth(1.2)
  love.graphics.line(-6, -6, -4, -9, -2, -7)
  love.graphics.line(6, -6, 4, -9, 2, -7)
  color(c, a)
  love.graphics.setLineWidth(3.4)
  love.graphics.line(0, 15, 0, -7)
  love.graphics.polygon("fill", -6.5, -6, 6.5, -6, 0, -16)
end

-- A jump: an arc up and over from a puff of dust, landing on an arrowhead.
local function leap(c, a)
  color(WHITE, a * 0.6)
  love.graphics.circle("fill", -15, 10, 3, 10)
  love.graphics.circle("fill", -11, 12, 2.2, 10)
  color(c, a)
  love.graphics.setLineWidth(3.5)
  love.graphics.arc("line", "open", 0, 10, 12, math.pi, 2 * math.pi - 0.35, 24)
  love.graphics.polygon("fill", 7, 4, 17, 3, 13.5, 13)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(-16, 15, 16, 15) -- the ground
  -- Speed lines behind the top of the jump.
  love.graphics.line(-12, -6, -7, -6)
  love.graphics.line(-14, -1, -10, -1)
end

local DRAW = {
  freeze = freeze,
  regen = regen,
  heal = heal,
  mgnest = mgnest,
  fart = fart,
  openborders = openborders,
  leap = leap,
}

--- Draw the icon for ability `key` centred on (cx, cy) inside a circle of
--- radius `r`, `alpha` (1) opaque.
function Icons.draw(key, cx, cy, r, alpha)
  alpha = alpha or 1
  local ability = Kinds.byKey[key]
  local c = ability and ability.color or { 0.8, 0.8, 0.85 }
  love.graphics.push()
  love.graphics.translate(cx, cy)
  love.graphics.scale(r / 16)
  local draw = DRAW[key]
  if draw then
    draw(c, alpha)
  else
    color(c, alpha)
    love.graphics.circle("fill", 0, 0, 6, 16)
  end
  love.graphics.pop()
  love.graphics.setLineWidth(1)
end

--- The key an ability goes off on, in a little dark badge low on the right
--- of its ring (radius `r` at (cx, cy)), so the icon can have the middle.
function Icons.keyBadge(text, cx, cy, r, alpha, font)
  alpha = alpha or 1
  font = font or love.graphics.getFont()
  local bw = math.max(16, font:getWidth(text) + 8)
  local bh = font:getHeight() + 2
  local bx = math.floor(cx + r * 0.72 - bw / 2)
  local by = math.floor(cy + r * 0.72 - bh / 2)
  love.graphics.setColor(0.05, 0.05, 0.07, 0.9 * alpha)
  love.graphics.rectangle("fill", bx, by, bw, bh, 4)
  love.graphics.setColor(1, 1, 1, 0.35 * alpha)
  love.graphics.rectangle("line", bx, by, bw, bh, 4)
  love.graphics.setFont(font)
  love.graphics.setColor(1, 1, 1, alpha)
  love.graphics.print(text, bx + math.floor((bw - font:getWidth(text)) / 2), by + 1)
end

return Icons
