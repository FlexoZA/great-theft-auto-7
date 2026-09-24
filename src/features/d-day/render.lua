-- Drawing the beach's inhabitants, client side: the defenders and their
-- sight cones, the mortar rings, the Major and his nests, the flag, and
-- the HUD (objective line, boss bar, portrait). init.lua keeps the state
-- (what the host last said) and calls in here.

local Features = require("src.features")
local UI = require("src.ui")
local Sight = require("src.features.d-day.sight")
local Troops = require("src.features.d-day.troops")
local Major = require("src.features.d-day.major")
local Screen = require("src.features.d-day.screen")

local Render = {}

local UNIFORM = { 0.42, 0.45, 0.38 } -- field grey
local UNIFORM_DARK = { 0.30, 0.33, 0.27 }
local HELMET = { 0.26, 0.29, 0.24 }
local SKIN = { 0.90, 0.74, 0.60 }
local RIFLE = { 0.18, 0.14, 0.10 }
local PACK = { 0.40, 0.34, 0.24 }
local MAJOR_TUNIC = { 0.36, 0.40, 0.28 }
local GOLD = { 0.95, 0.78, 0.25 }
local TACHE = { 0.60, 0.58, 0.55 }
local CRATER = { 0.30, 0.25, 0.18 }
local BLOOD = { 0.55, 0.08, 0.10 }

local PORTRAIT_LOOK = {
  bg = { 0.10, 0.10, 0.06 },
  ray = { 0.26, 0.28, 0.14 },
  titleColor = { 0.95, 0.78, 0.25 },
  speechColor = { 0.25, 0.20, 0.05 },
  kicker = "BOSS",
  title = "MAJOR LOOZ'ER",
  subtitle = "has a few words about the flag.",
  hint = "ATTENTION!",
}

--- The MG nest ability, if the abilities feature is there to draw it.
local function nestKind()
  return Features.byName.abilities and require("src.features.abilities.mgnest") or nil
end

-- World: under everyone ------------------------------------------------------

--- A mortar on its way: a ring on the sand filling as it falls.
local function drawAim(a, time)
  local k = 1 - math.max(0, a.t) / a.total
  local pulse = 0.5 + 0.5 * math.sin(time * 16)
  love.graphics.setColor(1, 0.35, 0.15, 0.10 + 0.08 * pulse)
  love.graphics.circle("fill", a.x, a.y, a.r, 40)
  love.graphics.setColor(1, 0.35, 0.15, 0.30)
  love.graphics.circle("fill", a.x, a.y, a.r * k, 40)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(1, 0.55, 0.2, 0.6 + 0.4 * pulse)
  love.graphics.circle("line", a.x, a.y, a.r, 40)
  love.graphics.setLineWidth(1)
end

local function drawStain(s)
  if s.crater then
    love.graphics.setColor(CRATER[1], CRATER[2], CRATER[3], 0.55)
    love.graphics.circle("fill", s.x, s.y, s.r, 20)
    love.graphics.setColor(CRATER[1] * 0.7, CRATER[2] * 0.7, CRATER[3] * 0.7, 0.6)
    love.graphics.circle("fill", s.x, s.y, s.r * 0.55, 16)
    return
  end
  local size = s.big and 1.8 or 1
  love.graphics.setColor(BLOOD[1], BLOOD[2], BLOOD[3], 0.8)
  love.graphics.ellipse("fill", s.x, s.y, 12 * size, 9 * size)
  for k = 0, 4 do
    local a = s.angle + (k - 2) * 0.5
    love.graphics.circle("fill", s.x + math.cos(a) * 14 * size, s.y + math.sin(a) * 14 * size, 2 + k % 2)
  end
  love.graphics.setColor(s.big and MAJOR_TUNIC or UNIFORM)
  love.graphics.ellipse("fill", s.x + 3, s.y - 2, 6 * size, 4 * size)
  love.graphics.setColor(HELMET)
  love.graphics.circle("fill", s.x - 6 * size, s.y + 2, 4 * size)
end

--- Is (x, y) within `pad` px of the visible part of the world?
local function onScreen(camera, x, y, pad)
  local w, h = love.graphics.getDimensions()
  local s = camera and camera.scale or 1
  local hw, hh = w / (2 * s) + pad, h / (2 * s) + pad
  return not camera or (math.abs(x - camera.x) < hw and math.abs(y - camera.y) < hh)
end

function Render.below(D, camera, time)
  for _, s in ipairs(D.stains) do
    drawStain(s)
  end
  for _, a in ipairs(D.aims) do
    drawAim(a, time)
  end
  local Nest = nestKind()
  if Nest then
    for _, n in ipairs(D.nests) do
      Nest.drawEffect(n)
    end
  end
  for _, s in pairs(D.troops) do
    if onScreen(camera, s.dx, s.dy, Troops.RANGE) then
      Sight.draw(s.dx, s.dy, s.angle, Troops.RANGE, s.alert, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- World: over everyone -------------------------------------------------------

--- A defender from above: helmet, shoulders, rifle out front; a pack on a
--- rifleman's back; a red "!" over anyone who has you in his sights.
local function drawSoldier(s, time)
  local x, y, r = s.dx, s.dy, Troops.RADIUS
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(RIFLE)
  love.graphics.setLineWidth(3)
  love.graphics.line(x + fx * 2 - fy * 3, y + fy * 2 + fx * 3, x + fx * (r + 11) - fy * 3, y + fy * (r + 11) + fx * 3)
  love.graphics.setLineWidth(1)
  if s.kind == "rifleman" then
    love.graphics.setColor(PACK)
    love.graphics.rectangle("fill", x - fx * 7 - 4, y - fy * 7 - 4, 8, 8, 2)
  end
  love.graphics.setColor(UNIFORM_DARK)
  love.graphics.ellipse("fill", x, y, r + 1, r + 1)
  love.graphics.setColor(UNIFORM)
  love.graphics.circle("fill", x - fy * (r - 1), y + fx * (r - 1), 3, 8)
  love.graphics.circle("fill", x + fy * (r - 1), y - fx * (r - 1), 3, 8)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 5 - fy * 3, y + fy * 5 + fx * 3, 2, 6) -- the hand on the rifle
  love.graphics.setColor(HELMET)
  love.graphics.circle("fill", x, y, r - 1.5, 12)
  love.graphics.setColor(HELMET[1] * 1.3, HELMET[2] * 1.3, HELMET[3] * 1.3)
  love.graphics.circle("fill", x - fx - fy, y - fy + fx, r - 4, 10)
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(1, 0.25, 0.2)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < Troops.HEALTH then
    local bw, f = 20, math.max(0, s.hp / Troops.HEALTH)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

--- The flag on its pole, waving: the Major's until his fight is over, then
--- yours.
local function drawFlag(map, captured, time)
  local px, py = map.flagX, map.flagY
  local top = py - 70
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.setLineWidth(4)
  love.graphics.line(px + 4, py + 2, px + 34, py - 8) -- the shadow of the pole
  love.graphics.setColor(0.35, 0.33, 0.30)
  love.graphics.circle("fill", px, py, 7, 12)
  love.graphics.setColor(0.75, 0.75, 0.72)
  love.graphics.setLineWidth(3)
  love.graphics.line(px, py, px, top)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(GOLD)
  love.graphics.circle("fill", px, top, 3.5, 8)
  -- The cloth, in strips, each a little further along the wave.
  local w, h, strips = 64, 40, 8
  local cloth = captured and { 0.20, 0.35, 0.80 } or { 0.28, 0.30, 0.24 }
  for i = 0, strips - 1 do
    local x0, x1 = px + i * w / strips, px + (i + 1) * w / strips
    local k0, k1 = i / strips, (i + 1) / strips
    local y0 = top + 4 + math.sin(time * 5 - i * 0.7) * 5 * k0
    local y1 = top + 4 + math.sin(time * 5 - (i + 1) * 0.7) * 5 * k1
    local shadeK = 0.85 + 0.15 * math.sin(time * 5 - i * 0.7 + 1)
    love.graphics.setColor(cloth[1] * shadeK, cloth[2] * shadeK, cloth[3] * shadeK)
    love.graphics.polygon("fill", x0, y0, x1, y1, x1, y1 + h, x0, y0 + h)
  end
  local mid = top + 4 + h / 2 + math.sin(time * 5 - strips * 0.35) * 2.5
  if captured then
    love.graphics.setColor(1, 1, 1)
    local cx, cy, R = px + w / 2, mid, 10
    for k = 0, 4 do
      local a = -math.pi / 2 + k * 2 * math.pi / 5
      local b1, b2 = a + math.pi / 5, a - math.pi / 5
      love.graphics.polygon("fill", cx + math.cos(a) * R, cy + math.sin(a) * R, cx + math.cos(b1) * R * 0.4,
        cy + math.sin(b1) * R * 0.4, cx + math.cos(b2) * R * 0.4, cy + math.sin(b2) * R * 0.4)
    end
    love.graphics.circle("fill", cx, cy, R * 0.4, 10)
  else
    love.graphics.setColor(GOLD)
    love.graphics.circle("line", px + w / 2, mid, 11, 16)
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.printf("L", px + w / 2 - 20, mid - UI.fonts.heading:getHeight() / 2, 40, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

--- A speech bubble over his head, the tail pointing down at him.
local function drawBubble(x, y, text, alpha)
  local font = UI.fonts.small
  local maxW = 240
  local w, lines = font:getWrap(text, maxW)
  w = math.min(maxW, w) + 16
  local h = #lines * font:getHeight() + 12
  local bx, by = x - w / 2, y - h - 14
  love.graphics.setColor(0, 0, 0, 0.5 * alpha)
  love.graphics.rectangle("fill", bx + 2, by + 3, w, h, 6)
  love.graphics.setColor(1, 1, 1, 0.95 * alpha)
  love.graphics.rectangle("fill", bx, by, w, h, 6)
  love.graphics.polygon("fill", x - 6, by + h - 1, x + 6, by + h - 1, x, by + h + 8)
  love.graphics.setFont(font)
  love.graphics.setColor(0.2, 0.15, 0.02, alpha)
  love.graphics.printf(text, bx + 8, by + 6, w - 16, "center")
end

--- The Major from above: a big olive tunic, gold epaulettes, a peaked cap
--- and a moustache you can see from the air.
local function drawMajor(m, time)
  local x, y, r = m.dx, m.dy, Major.RADIUS
  local fx, fy = math.cos(m.angle), math.sin(m.angle)
  local swing = math.sin(time * 6 + m.bob) * 1.2
  local sx, sy = -fy * swing, fx * swing
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + 4, y + 4, r + 1, 16)
  love.graphics.setColor(RIFLE)
  love.graphics.setLineWidth(4)
  love.graphics.line(x + fx * 4 - fy * 5, y + fy * 4 + fx * 5, x + fx * (r + 14) - fy * 5, y + fy * (r + 14) + fx * 5)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x - fy * (r + 2) - sx, y + fx * (r + 2) - sy, 4, 8)
  love.graphics.circle("fill", x + fy * (r + 2) + sx, y - fx * (r + 2) + sy, 4, 8)
  love.graphics.setColor(MAJOR_TUNIC)
  love.graphics.circle("fill", x, y, r, 16)
  love.graphics.setColor(GOLD)
  love.graphics.rectangle("fill", x - fy * (r - 3) - 3, y + fx * (r - 3) - 3, 6, 6)
  love.graphics.rectangle("fill", x + fy * (r - 3) - 3, y - fx * (r - 3) - 3, 6, 6)
  -- Cap: the crown, a black peak out front, a gold badge.
  love.graphics.setColor(0.28, 0.32, 0.22)
  love.graphics.circle("fill", x, y, 8.5, 14)
  love.graphics.setColor(0.08, 0.08, 0.08)
  love.graphics.arc("fill", "pie", x + fx * 3, y + fy * 3, 8, m.angle - 1.1, m.angle + 1.1, 10)
  love.graphics.setColor(GOLD)
  love.graphics.circle("fill", x + fx * 2, y + fy * 2, 2, 6)
  -- The moustache, sticking out past the peak on both sides.
  love.graphics.setColor(TACHE)
  love.graphics.setLineWidth(3)
  love.graphics.line(x + fx * 9 - fy * 8, y + fy * 9 + fx * 8, x + fx * 11, y + fy * 11, x + fx * 9 + fy * 8,
    y + fy * 9 - fx * 8)
  love.graphics.setLineWidth(1)

  local bw = 60
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y - r - 16, bw + 2, 6)
  local f = math.max(0, m.hp / m.max)
  love.graphics.setColor(1 - f, f, 0.2)
  love.graphics.rectangle("fill", x - bw / 2, y - r - 15, bw * f, 4)
  if m.say and m.sayTimer > 0 then
    drawBubble(x, y - r - 18, m.say, math.min(1, m.sayTimer * 2))
  end
end

function Render.above(D, map, camera, time)
  if map and map.flagX then
    drawFlag(map, D.stage == "done", time)
  end
  for _, s in pairs(D.troops) do
    if onScreen(camera, s.dx, s.dy, 60) then
      drawSoldier(s, time)
    end
  end
  if D.major then
    drawMajor(D.major, time)
  end
  love.graphics.setColor(1, 1, 1)
end

-- HUD -----------------------------------------------------------------------

local OBJECTIVES = {
  assault = "Objective: get up the beach and take the flag on the hilltop",
  reveal = "Objective: take the flag on the hilltop",
  boss = "Objective: defeat Major Looz'er",
  done = "Objective: the flag is yours. Take the EXIT star home",
}

local function drawObjective(stage, distance)
  local text = OBJECTIVES[stage]
  if not text then
    return
  end
  if stage == "assault" and distance then
    text = text .. ("  (%d m)"):format(math.floor(distance / 10))
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.print(text, 11, 211)
  love.graphics.setColor(0.85, 0.9, 0.55)
  love.graphics.print(text, 10, 210)
end

local function drawBossBar(m)
  local w, h = love.graphics.getDimensions()
  local bw, bh = 380, 14
  local bx, by = math.floor((w - bw) / 2), h - 150 -- above the magazine line and the ability circles
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("MAJOR LOOZ'ER", 1, by - 19, w, "center")
  love.graphics.setColor(GOLD)
  love.graphics.printf("MAJOR LOOZ'ER", 0, by - 20, w, "center")
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4, 3)
  love.graphics.setColor(0.55, 0.62, 0.30)
  love.graphics.rectangle("fill", bx, by, bw * math.max(0, m.hp / m.max), bh, 2)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.rectangle("line", bx, by, bw, bh, 2)
end

--- `distance` is how far I am from the flag, if I am anywhere.
function Render.hud(D, face, distance, time)
  if D.stage then
    drawObjective(D.stage, distance)
  end
  if D.major and D.stage == "boss" then
    drawBossBar(D.major)
  end
  if D.page then
    PORTRAIT_LOOK.speech = D.page.line
    Screen.draw(face, PORTRAIT_LOOK, time)
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
