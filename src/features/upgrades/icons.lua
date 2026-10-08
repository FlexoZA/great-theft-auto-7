-- Upgrade icons: one small drawing per kind of upgrade, for the gym's
-- panel. Drawn on a 32 x 32 grid centred on (0, 0) and scaled to fit a
-- circle of radius `r`, in the kind's own colour (`Icons.colors`) with white
-- for highlights, the way the ability icons are. Unknown keys get a dot.

local Icons = {}

-- Each kind's colour: health and stamina match their bars in the HUD, the
-- dodge its bar's violet, reach the koins it pulls in.
Icons.colors = {
  health = { 0.92, 0.3, 0.3 },
  stamina = { 0.4, 0.85, 0.45 },
  reach = { 1, 0.8, 0.3 },
  regen = { 0.35, 0.85, 0.75 },
  slots = { 0.85, 0.62, 0.38 },
  dodge = { 0.78, 0.65, 1 },
  walk = { 0.45, 0.7, 1 },
}
local GREY = { 0.8, 0.8, 0.85 }
local WHITE = { 1, 1, 1 }

local function color(c, alpha, k)
  k = k or 1
  love.graphics.setColor(c[1] * k, c[2] * k, c[3] * k, (c[4] or 1) * alpha)
end

-- A heart with a plus on it: more of it.
local function health(c, a)
  color(c, a)
  love.graphics.circle("fill", -6, -4, 7.5, 20)
  love.graphics.circle("fill", 6, -4, 7.5, 20)
  love.graphics.polygon("fill", -13.2, -1, 13.2, -1, 0, 14)
  color(WHITE, a * 0.35)
  love.graphics.circle("fill", -8, -6, 2.5, 10) -- shine
  color(WHITE, a)
  love.graphics.rectangle("fill", -1.5, -7, 3, 11, 1)
  love.graphics.rectangle("fill", -5.5, -3, 11, 3, 1)
end

-- A lightning bolt: go for longer.
local function stamina(c, a)
  color(c, a)
  love.graphics.polygon("fill", 3, -15, -9, 2, 2, 2) -- two blades overlapping in the middle (fill is convex only)
  love.graphics.polygon("fill", -3, 15, 9, -3, -2, -3)
  color(WHITE, a * 0.4)
  love.graphics.polygon("fill", 2, -12, -5, 0, -2, 0) -- shine
end

-- A horseshoe magnet pulling a koin in, the koin level with the gap
-- between its poles (the lower right is left for the key badge).
local function reach(c, a)
  color(c, a)
  love.graphics.circle("fill", 11, -2, 5.5, 18)
  color(WHITE, a * 0.6)
  love.graphics.circle("line", 11, -2, 3, 14)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(4, -2, 6, -2)
  love.graphics.setLineWidth(6)
  color({ 0.9, 0.25, 0.25 }, a)
  love.graphics.arc("line", "open", -5, -2, 8, math.pi * 0.5, math.pi * 1.5)
  love.graphics.line(-5, -10, 1, -10)
  love.graphics.line(-5, 6, 1, 6)
  color(WHITE, a)
  love.graphics.setLineWidth(1)
  love.graphics.rectangle("fill", 1, -13, 4, 6)
  love.graphics.rectangle("fill", 1, 3, 4, 6)
end

-- A circular arrow round a small bolt: it comes back faster.
local function regen(c, a)
  color(c, a)
  love.graphics.setLineWidth(3)
  love.graphics.arc("line", "open", 0, 0, 12, -math.pi * 0.35, math.pi * 1.35)
  love.graphics.polygon("fill", 6.5, -15, 14, -9.5, 5, -6)
  love.graphics.setLineWidth(1)
  color(WHITE, a)
  love.graphics.polygon("fill", 1.5, -8, -4.5, 1, 0.5, 1)
  love.graphics.polygon("fill", -1.5, 8, 4.5, -1, -0.5, -1)
end

-- A backpack with a flap and a pocket: room for more.
local function slots(c, a)
  color(c, a, 0.7)
  love.graphics.setLineWidth(3)
  love.graphics.arc("line", "open", 0, -9, 5, math.pi, 2 * math.pi)
  love.graphics.setLineWidth(1)
  color(c, a)
  love.graphics.rectangle("fill", -11, -9, 22, 24, 5)
  color(c, a, 0.75)
  love.graphics.rectangle("fill", -11, -9, 22, 9, 5)
  love.graphics.rectangle("fill", -7, 4, 14, 8, 2)
  color(WHITE, a)
  love.graphics.rectangle("fill", -1.5, -2, 3, 4, 1)
end

-- A figure leaning into a dash, with speed lines behind it.
local function dodge(c, a)
  color(WHITE, a * 0.7)
  love.graphics.setLineWidth(2)
  love.graphics.line(-15, -4, -8, -4)
  love.graphics.line(-15, 2, -6, 2)
  love.graphics.line(-13, 8, -7, 8)
  color(c, a)
  love.graphics.circle("fill", 6, -11, 3.5, 14)
  love.graphics.setLineWidth(3.5)
  love.graphics.line(4, -6, -1, 4) -- body
  love.graphics.line(-1, 4, 5, 8, 3, 14) -- front leg
  love.graphics.line(-1, 4, -6, 9, -11, 9) -- back leg
  love.graphics.line(3, -4, 10, -1) -- front arm
  love.graphics.line(3, -4, -4, -3) -- back arm
  love.graphics.setLineWidth(1)
end

-- A pair of footprints striding up: further with each step.
local function walk(c, a)
  color(WHITE, a * 0.5)
  love.graphics.setLineWidth(2)
  love.graphics.line(-14, 12, -14, 4)
  love.graphics.line(14, 0, 14, -8)
  love.graphics.setLineWidth(1)
  color(c, a)
  love.graphics.ellipse("fill", -5, 4, 4.5, 7, 16) -- left sole
  love.graphics.circle("fill", -5, 13.5, 3.5, 12) -- left heel
  love.graphics.ellipse("fill", 5, -9, 4.5, 7, 16) -- right sole, a stride ahead
  love.graphics.circle("fill", 5, 0.5, 3.5, 12) -- right heel
  color(WHITE, a * 0.4)
  love.graphics.circle("fill", -6.5, 1, 1.5, 8) -- shine
  love.graphics.circle("fill", 3.5, -12, 1.5, 8)
end

local DRAW = {
  health = health,
  stamina = stamina,
  reach = reach,
  regen = regen,
  slots = slots,
  dodge = dodge,
  walk = walk,
}

--- The colour of kind `key`, grey for one without its own.
function Icons.color(key)
  return Icons.colors[key] or GREY
end

--- Draw the icon for upgrade `key` centred on (cx, cy) inside a circle of
--- radius `r`, `alpha` (1) opaque.
function Icons.draw(key, cx, cy, r, alpha)
  alpha = alpha or 1
  local c = Icons.color(key)
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

return Icons
