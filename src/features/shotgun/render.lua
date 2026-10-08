-- Drawing the bluff's business, client side: Shotgun himself (unless he
-- is out of sight), the feathers where he vanishes and comes back, the
-- bead he draws on somebody (a laser from his rifle and a closing ring on
-- them), and the HUD: the objective, his boss bar, a warning for whoever
-- he has in his sights, and his portrait. init.lua keeps the state (what
-- the host last said) and calls in here.

local UI = require("src.ui")
local Boss = require("src.features.shotgun.boss")
local Chicken = require("src.features.abilities.chicken")
local Stamina = require("src.features.bosses.stamina")
local BossBar = require("src.features.bosses.bar")
local Screen = require("src.features.shotgun.screen")

local Render = {}

local CAMO = { 0.38, 0.42, 0.26 }
local CAMO_DARK = { 0.26, 0.29, 0.17 }
local SKIN = { 0.93, 0.80, 0.68 }
local HAIR = { 0.35, 0.28, 0.20 }
local RIFLE = { 0.16, 0.15, 0.14 }
local SCOPE = { 0.10, 0.10, 0.10 }
local BLOOD = { 0.55, 0.08, 0.10 }
local LASER = { 1, 0.15, 0.1 }
local TITLE = { 0.95, 0.55, 0.35 }

local PORTRAIT_LOOK = {
  bg = { 0.12, 0.09, 0.06 },
  ray = { 0.30, 0.20, 0.12 },
  titleColor = TITLE,
  speechColor = { 0.25, 0.08, 0.05 },
  kicker = "BOSS",
  title = "SHOTGUN",
  subtitle = "does not want to discuss it.",
  hint = "NO DEBATING",
}

-- World ----------------------------------------------------------------------

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
  love.graphics.setColor(0.3, 0.08, 0.04, alpha)
  love.graphics.printf(text, bx + 8, by + 6, w - 16, "center")
end

--- Shotgun from above: hunched camo shoulders, a bald head with a few
--- hairs across it, glasses glinting out front, the long rifle with its
--- scope, and the pistol he would rather use on his hip.
local function drawBoss(b, time)
  local x, y, r = b.dx, b.dy, Boss.RADIUS
  local fx, fy = math.cos(b.angle), math.sin(b.angle)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + 4, y + 4, r + 1, 16)
  -- The rifle, out along his aim, the scope on top.
  love.graphics.setColor(RIFLE)
  love.graphics.setLineWidth(3)
  love.graphics.line(x - fx * 6 + fy * 4, y - fy * 6 - fx * 4, x + fx * (r + 26) + fy * 4, y + fy * (r + 26) - fx * 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(SCOPE)
  love.graphics.setLineWidth(5)
  love.graphics.line(x + fx * 4 + fy * 4, y + fy * 4 - fx * 4, x + fx * 14 + fy * 4, y + fy * 14 - fx * 4)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 8 + fy * 5, y + fy * 8 - fx * 5, 3, 8)
  love.graphics.circle("fill", x + fx * 16 + fy * 3, y + fy * 16 - fx * 3, 3, 8)
  -- Body, and the holster on the other side.
  love.graphics.setColor(CAMO_DARK)
  love.graphics.circle("fill", x, y, r + 1, 16)
  love.graphics.setColor(CAMO)
  love.graphics.circle("fill", x - fx, y - fy, r - 1, 16)
  love.graphics.setColor(CAMO_DARK)
  love.graphics.circle("fill", x - fx * 5 - fy * 4, y - fy * 5 + fx * 4, 3, 6)
  love.graphics.circle("fill", x + fx * 2 + fy * 6, y + fy * 2 - fx * 6, 2.5, 6)
  love.graphics.setColor(RIFLE)
  love.graphics.rectangle("fill", x - fy * (r - 2) - 3, y + fx * (r - 2) - 3, 6, 6)
  -- Head: bald on top, a few hairs, the glasses out front.
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x, y, 7.5, 14)
  love.graphics.setColor(HAIR)
  love.graphics.line(x - fx * 5 - fy * 5, y - fy * 5 + fx * 5, x + fy * 5, y - fx * 5)
  love.graphics.line(x - fx * 5 - fy * 3, y - fy * 5 + fx * 3, x + fx * 2 + fy * 5, y + fy * 2 - fx * 5)
  love.graphics.setColor(0.08, 0.08, 0.08)
  love.graphics.setLineWidth(3)
  love.graphics.line(x + fx * 6 - fy * 5, y + fy * 6 + fx * 5, x + fx * 6 + fy * 5, y + fy * 6 - fx * 5)
  love.graphics.setLineWidth(1)
  local glint = 0.5 + 0.5 * math.sin(time * 3 + b.bob)
  love.graphics.setColor(0.8, 0.95, 1, 0.4 + 0.5 * glint)
  love.graphics.circle("fill", x + fx * 7 - fy * 3, y + fy * 7 + fx * 3, 1.5, 6)
  love.graphics.circle("fill", x + fx * 7 + fy * 3, y + fy * 7 - fx * 3, 1.5, 6)

  local bw = 60
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", x - bw / 2 - 1, y - r - 16, bw + 2, 6)
  local f = math.max(0, b.hp / b.max)
  love.graphics.setColor(1 - f, f, 0.2)
  love.graphics.rectangle("fill", x - bw / 2, y - r - 15, bw * f, 4)
  if b.say and b.sayTimer > 0 then
    drawBubble(x, y - r - 18, b.say, math.min(1, b.sayTimer * 2))
  end
end

--- The bead he has on somebody at (tx, ty): a laser from his rifle, faint
--- and flickering at first, solid once the aim has locked; and on them a
--- ring closing in, with crosshair ticks, over a red "!" .
local function drawAim(b, a, tx, ty, time)
  local k = 1 - math.max(0, a.t) / a.total -- 0 at the start, 1 at the shot
  local locked = a.t <= Boss.LOCK
  local fx, fy = math.cos(b.angle), math.sin(b.angle)
  local mx, my = b.dx + fx * (Boss.RADIUS + 26), b.dy + fy * (Boss.RADIUS + 26)
  if b.shown then
    local flicker = locked and 1 or (0.35 + 0.35 * math.abs(math.sin(time * 30)))
    love.graphics.setLineWidth(locked and 2 or 1)
    love.graphics.setColor(LASER[1], LASER[2], LASER[3], 0.25 + 0.5 * k * flicker)
    love.graphics.line(mx, my, tx, ty)
    love.graphics.setLineWidth(1)
  end
  local ring = 44 - 30 * k
  local pulse = 0.5 + 0.5 * math.sin(time * (10 + 20 * k))
  love.graphics.setColor(LASER[1], LASER[2], LASER[3], 0.12 + 0.12 * pulse)
  love.graphics.circle("fill", tx, ty, ring, 32)
  love.graphics.setLineWidth(locked and 3 or 2)
  love.graphics.setColor(LASER[1], LASER[2], LASER[3], 0.6 + 0.4 * pulse)
  love.graphics.circle("line", tx, ty, ring, 32)
  for i = 0, 3 do
    local ang = i * math.pi / 2 + (locked and 0 or time * 2)
    local c, s = math.cos(ang), math.sin(ang)
    love.graphics.line(tx + c * (ring - 6), ty + s * (ring - 6), tx + c * (ring + 6), ty + s * (ring + 6))
  end
  love.graphics.setLineWidth(1)
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf("!", tx - 19, ty - ring - 34, 40, "center")
  love.graphics.setColor(1, 0.25, 0.2)
  love.graphics.printf("!", tx - 20, ty - ring - 35, 40, "center")
end

local function drawStain(s)
  love.graphics.setColor(BLOOD[1], BLOOD[2], BLOOD[3], 0.8)
  love.graphics.ellipse("fill", s.x, s.y, 20, 15)
  for k = 0, 4 do
    local a = s.angle + (k - 2) * 0.5
    love.graphics.circle("fill", s.x + math.cos(a) * 24, s.y + math.sin(a) * 24, 3 + k % 2)
  end
  love.graphics.setColor(CAMO)
  love.graphics.ellipse("fill", s.x + 3, s.y - 2, 10, 7)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", s.x - 10, s.y + 2, 6)
end

function Render.below(S)
  for _, s in ipairs(S.stains) do
    drawStain(s)
  end
  love.graphics.setColor(1, 1, 1)
end

--- `pose(id)` is where player `id` is drawn, or nil.
function Render.above(S, pose, time)
  for _, p in ipairs(S.puffs) do
    Chicken.drawPuff(p.x, p.y, p.t, p.seed)
  end
  local b = S.boss
  if b and b.shown then
    drawBoss(b, time)
  end
  if b and S.aim then
    local tx, ty = pose(S.aim.target)
    if tx then
      drawAim(b, S.aim, tx, ty, time)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- HUD -----------------------------------------------------------------------

local OBJECTIVES = {
  reveal = "Objective: get up the cliff (the ramp is at the far left)",
  hunt = "Objective: get up the cliff (the ramp is at the far left) and stop Shotgun",
  top = "Objective: stop Shotgun",
  done = "Objective: debate over. Take the EXIT star home",
}

local function drawObjective(stage, up)
  local text = OBJECTIVES[(stage == "hunt" and up) and "top" or stage]
  if not text then
    return
  end
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.print(text, 11, 211)
  love.graphics.setColor(1, 0.75, 0.55)
  love.graphics.print(text, 10, 210)
end

--- Shotgun has a bead on me: the screen's edge throbs red and it says so.
local function drawWarning(a, time)
  local w, h = love.graphics.getDimensions()
  local k = 1 - math.max(0, a.t) / a.total
  local pulse = 0.5 + 0.5 * math.sin(time * (12 + 24 * k))
  love.graphics.setLineWidth(18)
  love.graphics.setColor(1, 0.1, 0.05, (0.15 + 0.35 * k) * (0.6 + 0.4 * pulse))
  love.graphics.rectangle("line", 9, 9, w - 18, h - 18)
  love.graphics.setLineWidth(1)
  local text = a.t <= Boss.LOCK and "DODGE!" or "SHOTGUN HAS YOU IN HIS SIGHTS"
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(0, 0, 0, 0.7)
  love.graphics.printf(text, 2, h * 0.22 + 2, w, "center")
  love.graphics.setColor(1, 0.3 + 0.3 * pulse, 0.2)
  love.graphics.printf(text, 0, h * 0.22, w, "center")
end

--- `up`: am I on top of the cliff?
function Render.hud(S, face, myId, up, time)
  drawObjective(S.stage, up)
  local b = S.boss
  if b and S.stage == "hunt" then
    BossBar.draw({
      title = b.shown and "SHOTGUN" or "SHOTGUN (out of sight)", titleColor = TITLE, fill = { 0.85, 0.45, 0.25 },
      hp = b.hp, max = b.max, stamina = b.stamina, staminaMax = Stamina.defaults.max, winded = b.winded,
    })
  end
  if S.aim and S.aim.target == myId then
    drawWarning(S.aim, time)
  end
  if S.page then
    PORTRAIT_LOOK.speech = S.page.line
    Screen.draw(face, PORTRAIT_LOOK, time)
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
