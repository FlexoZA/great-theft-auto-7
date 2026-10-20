-- How Kilowatt looks (kilowatt.lua on the Roof, war_rigs.lua riding past on
-- the Overpass), seen from above: more machine than man. Gunmetal plating
-- where a ganger has clothes, steel arms and a steel skull, chrome
-- pauldrons and jaw, a reactor in his chest pulsing cyan through its cage,
-- a mohawk of cables with glowing tips. Bolted to an armoured back plate,
-- two insulator spikes stand up off his shoulder blades, leaning back, a
-- blue arc crackling between their tips the whole time. Venting, the cage
-- swings open and the arc runs white and fat; in phase 2 it forks and
-- arcs jump off his shoulders.
--
--   Look.draw(angle, walk, state)   in his own space, already moved to where he is and scaled
--     state { pulse = 0..1 (the reactor), venting, phase2, whip (the whip crackling in his fist) }
--   Look.BODY                       his Body.person look, for his corpse
--   Look.arcAt(x, y, angle, scale)  where the arc between his spikes is in the world (for the night's glow)

local Body = require("src.body")

local Look = {}

local CYAN = { 0.18, 0.90, 1.00 }
local HOT = { 0.78, 0.98, 1.00 }
local CHROME = { 0.78, 0.82, 0.86 }
local GUNMETAL = { 0.27, 0.30, 0.34 }
local PLATE = { 0.34, 0.37, 0.42 }
local SEAM = { 0.12, 0.13, 0.15 }
local STEEL_LIT = { 0.80, 0.84, 0.90 }
local STEEL_DARK = { 0.22, 0.24, 0.28 }

-- Body.person's look: plating for clothes, steel for skin.
local BODY = {
  shirt = GUNMETAL, pants = { 0.16, 0.17, 0.19 }, skin = { 0.50, 0.54, 0.59 },
  hair = { 0.13, 0.15, 0.17 }, shoes = { 0.06, 0.06, 0.07 },
}
Look.BODY = BODY -- (his corpse lies in it)

-- The spikes: where each stands on his back, and where its tip leans out to
-- (his own space: +x ahead of him, y to his side). Seen from above, a spike
-- standing up and leaning back shows as a long point running back off him.
local BASE_X, BASE_Y, BASE_W = -3.4, 3.6, 2.4
local TIP_X, TIP_Y = -12.5, 7.4

local random = love.math.random

local function setColor(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or 1)
end

--- One spike, `side` -1 or 1: a ridge up the middle of it, a lit face and
--- a dark one either side, so it stands up; two insulator rings, and a cap
--- glowing at the tip.
local function spike(side, glow)
  local bx, by = BASE_X, BASE_Y * side
  local tx, ty = TIP_X, TIP_Y * side
  local inner, outer = by - BASE_W * side, by + BASE_W * side
  local rx = bx + 1 -- the ridge's foot, toward his front
  setColor(STEEL_LIT)
  love.graphics.polygon("fill", bx, inner, rx, by, tx, ty)
  setColor(STEEL_DARK)
  love.graphics.polygon("fill", rx, by, bx, outer, tx, ty)
  setColor(SEAM)
  love.graphics.setLineWidth(0.35)
  love.graphics.polygon("line", bx, inner, rx, by, bx, outer, tx, ty)
  love.graphics.setLineWidth(0.5)
  setColor(CHROME)
  for _, f in ipairs({ 0.35, 0.6 }) do -- the insulators, narrowing up the spike
    local cx, cy = bx + (tx - bx) * f, by + (ty - by) * f
    local w = BASE_W * (1.1 - f)
    love.graphics.line(cx + 0.4, cy - w, cx - 0.4, cy + w)
  end
  love.graphics.setLineWidth(1)
  setColor(CYAN, glow)
  love.graphics.circle("fill", tx, ty, 1.1, 8)
  setColor(HOT, glow)
  love.graphics.circle("fill", tx, ty, 0.5, 6)
end

--- A jagged path from (x0, y0) to (x1, y1) in `steps`.
local function jagged(x0, y0, x1, y1, steps, jitter)
  local pts = { x0, y0 }
  for i = 1, steps - 1 do
    local f = i / steps
    pts[#pts + 1] = x0 + (x1 - x0) * f + (random() - 0.5) * jitter
    pts[#pts + 1] = y0 + (y1 - y0) * f + (random() - 0.5) * jitter * 0.4
  end
  pts[#pts + 1], pts[#pts + 2] = x1, y1
  return pts
end

--- `pts` drawn `width` wide, its corners cut so a faint wide line doesn't
--- stack up on itself.
local function stroke(pts, width, color, alpha)
  setColor(color, alpha)
  love.graphics.setLineWidth(width)
  love.graphics.setLineJoin("bevel")
  love.graphics.line(pts)
  love.graphics.setLineJoin("miter")
  love.graphics.setLineWidth(1)
end

--- The arc between the spikes' tips, new every frame: a wide blue glow and a
--- thin white core; fat and white while he vents, forking in phase 2.
local function arc(state)
  local hot = state.venting
  local pts = jagged(TIP_X, -TIP_Y, TIP_X, TIP_Y, 7, 3.6)
  stroke(pts, hot and 3.2 or 2.2, hot and HOT or CYAN, hot and 0.45 or 0.3)
  stroke(pts, hot and 1.2 or 0.8, HOT, hot and 1 or 0.7 + 0.3 * random())
  if state.phase2 and random() < 0.6 then -- a fork reaching off the arc
    local i = 2 * love.math.random(2, 6) - 1
    local fx, fy = pts[i], pts[i + 1]
    stroke(jagged(fx, fy, fx - 3 - random() * 3, fy + (random() - 0.5) * 5, 3, 1.6), 0.6, HOT, 0.8)
  end
end

--- The plate bolted over his back: the spikes stand on it.
local function backPlate()
  setColor(PLATE)
  love.graphics.ellipse("fill", -2.6, 0, 3.4, 6.4, 14)
  setColor(SEAM)
  love.graphics.setLineWidth(0.5)
  love.graphics.ellipse("line", -2.6, 0, 3.4, 6.4, 14)
  love.graphics.line(-2.6, -6.2, -2.6, 6.2) -- the spine's seam
  love.graphics.setLineWidth(1)
  setColor(CHROME)
  for _, y in ipairs({ -4.6, -1.5, 1.5, 4.6 }) do -- rivets down each side of it
    love.graphics.circle("fill", -0.9, y * 0.85, 0.35, 5)
    love.graphics.circle("fill", -4.3, y * 0.85, 0.35, 5)
  end
end

function Look.arcAt(x, y, angle, scale)
  return x + math.cos(angle) * TIP_X * scale, y + math.sin(angle) * TIP_X * scale
end

function Look.draw(angle, walk, state)
  -- The spikes' shadows fall off his back, down and right like everyone's.
  love.graphics.push()
  love.graphics.translate(2.5, 2.5)
  love.graphics.rotate(angle)
  love.graphics.setColor(0, 0, 0, 0.25)
  for _, side in ipairs({ -1, 1 }) do
    love.graphics.polygon("fill", BASE_X + 1, (BASE_Y - BASE_W) * side, BASE_X + 1, (BASE_Y + BASE_W) * side, TIP_X,
      TIP_Y * side)
  end
  love.graphics.pop()

  Body.person(0, 0, angle, walk, BODY)
  love.graphics.rotate(angle)
  backPlate()
  setColor(CHROME)
  love.graphics.ellipse("fill", 0, -7.5, 3.4, 2.6, 10) -- the pauldrons
  love.graphics.ellipse("fill", 0, 7.5, 3.4, 2.6, 10)
  setColor(SEAM)
  love.graphics.setLineWidth(0.4)
  love.graphics.line(-1.8, -7.5, 1.8, -7.5)
  love.graphics.line(-1.8, 7.5, 1.8, 7.5)
  love.graphics.setLineWidth(1)
  setColor(CHROME)
  love.graphics.rectangle("fill", 3, -2, 2, 4, 0.6) -- the jaw
  local core = state.venting and HOT or CYAN
  setColor(core, state.pulse or 1)
  love.graphics.circle("fill", 2, 0, state.venting and 3.4 or 2.6, 10) -- the reactor
  if state.venting then -- the cage swung open
    setColor(CHROME)
    love.graphics.setLineWidth(0.8)
    love.graphics.line(4.5, -3, 6.5, -5)
    love.graphics.line(4.5, 3, 6.5, 5)
    love.graphics.setLineWidth(1)
  end
  setColor(SEAM)
  love.graphics.setLineWidth(1.2)
  for i = -2, 2 do -- the mohawk's cables
    love.graphics.line(-1, i * 1.1, -4.6 + math.abs(i) * 0.5, i * 1.6)
  end
  love.graphics.setLineWidth(1)
  setColor(CYAN)
  for i = -2, 2 do
    love.graphics.circle("fill", -4.6 + math.abs(i) * 0.5, i * 1.6, 0.8, 6)
  end
  local glow = state.venting and 1 or 0.6 + 0.4 * (state.pulse or 1)
  spike(-1, glow)
  spike(1, glow)
  arc(state)
  if state.whip then -- the whip crackling in his fist
    setColor(HOT)
    love.graphics.circle("fill", 7, 6, 1.6 + random() * 1.2, 8)
  end
  if state.phase2 and random() < 0.4 then -- arcs off his shoulders
    setColor(HOT)
    local s = random() < 0.5 and -1 or 1
    love.graphics.line(0, s * 7.5, -2 + random() * 4, s * (10 + random() * 3), random() * 3, s * 12)
  end
  love.graphics.setColor(1, 1, 1)
end

return Look
