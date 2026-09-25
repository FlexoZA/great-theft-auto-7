-- Drawing the turf war, client side: each tower's detection zone on the
-- ground, the gun on its top swinging after whoever it watches, its health
-- when hurt, the rubble once it is down; the creeps (simps in the side's
-- hoodie, soldiers in its uniform) and the stains where they fell; the HUD
-- line and the minimap marks. init.lua keeps the state (what the host last
-- said) and calls in.

local UI = require("src.ui")
local Towers = require("src.features.turf-war.towers")

local Render = {}

local BRASS = { 1, 0.62, 0.25 }
local ALERT = { 1, 0.25, 0.2 }
local RUBBLE = { 0.34, 0.32, 0.30 }
local RUBBLE_DARK = { 0.22, 0.21, 0.20 }
local SMOKE = { 0.5, 0.5, 0.5 }
local COVER = { 0.75, 0.75, 0.78 }
local SKIN = { 0.90, 0.74, 0.60 }
local RIFLE = { 0.18, 0.14, 0.10 }
local BLOOD = { 0.55, 0.08, 0.10 }
local SOLDIER_RADIUS = 7
local SIMP_RADIUS = 6

local function shade(c, k)
  return { c[1] * k, c[2] * k, c[3] * k }
end

--- Is (x, y) within `pad` px of the visible part of the world?
local function onScreen(camera, x, y, pad)
  local w, h = love.graphics.getDimensions()
  local s = camera and camera.scale or 1
  local hw, hh = w / (2 * s) + pad, h / (2 * s) + pad
  return not camera or (math.abs(x - camera.x) < hw and math.abs(y - camera.y) < hh)
end

local function teamColor(map, team)
  return map.teams[team].color
end

-- World: under everyone ------------------------------------------------------

--- The zone: a faint disc in the team's colour while the tower scans, hot
--- red and pulsing while it has someone.
local function drawZone(t, c, time)
  local r = Towers.RANGE
  if t.alert then
    local pulse = 0.5 + 0.5 * math.sin(time * 10)
    love.graphics.setColor(ALERT[1], ALERT[2], ALERT[3], 0.08 + 0.05 * pulse)
    love.graphics.circle("fill", t.x, t.y, r, 64)
    love.graphics.setLineWidth(2)
    love.graphics.setColor(ALERT[1], ALERT[2], ALERT[3], 0.45 + 0.3 * pulse)
    love.graphics.circle("line", t.x, t.y, r, 64)
  else
    love.graphics.setColor(c[1], c[2], c[3], 0.05)
    love.graphics.circle("fill", t.x, t.y, r, 64)
    love.graphics.setLineWidth(1)
    love.graphics.setColor(c[1], c[2], c[3], 0.28)
    love.graphics.circle("line", t.x, t.y, r, 64)
  end
  love.graphics.setLineWidth(1)
end

--- What is left of a tower: broken stone over its square, smoke drifting
--- off it.
local function drawRubble(t, time)
  local h = Towers.SIZE / 2
  love.graphics.setColor(RUBBLE_DARK)
  love.graphics.rectangle("fill", t.x - h, t.y - h, Towers.SIZE, Towers.SIZE, 4)
  love.graphics.setColor(RUBBLE)
  for k = 0, 6 do
    local ox = ((t.id * 37 + k * 53) % 40) - 20
    local oy = ((t.id * 91 + k * 29) % 40) - 20
    love.graphics.rectangle("fill", t.x + ox - 6, t.y + oy - 5, 12 + k % 3 * 3, 10, 2)
  end
  for k = 0, 2 do
    local rise = (time * 14 + k * 24) % 70
    local a = 0.35 * (1 - rise / 70)
    love.graphics.setColor(SMOKE[1], SMOKE[2], SMOKE[3], a)
    love.graphics.circle("fill", t.x + math.sin(time * 1.3 + k) * 8, t.y - 6 - rise, 8 + rise * 0.18, 12)
  end
end

--- Where a soldier fell: a splash and what he wore.
local function drawStain(s, c)
  love.graphics.setColor(BLOOD[1], BLOOD[2], BLOOD[3], 0.8)
  love.graphics.ellipse("fill", s.x, s.y, 12, 9)
  for k = 0, 4 do
    local a = s.angle + (k - 2) * 0.5
    love.graphics.circle("fill", s.x + math.cos(a) * 14, s.y + math.sin(a) * 14, 2 + k % 2)
  end
  love.graphics.setColor(shade(c, 0.7))
  love.graphics.ellipse("fill", s.x + 3, s.y - 2, 6, 4)
  if s.kind == "soldier" then
    love.graphics.setColor(shade(c, 0.45))
    love.graphics.circle("fill", s.x - 6, s.y + 2, 4) -- the helmet
  else
    love.graphics.setColor(SKIN)
    love.graphics.circle("fill", s.x - 6, s.y + 2, 3)
  end
end

function Render.below(TW, map, camera, time)
  for _, s in ipairs(TW.stains) do
    if onScreen(camera, s.x, s.y, 30) then
      drawStain(s, teamColor(map, s.team))
    end
  end
  for _, t in ipairs(TW.list) do
    if onScreen(camera, t.x, t.y, Towers.RANGE) then
      if t.down then
        drawRubble(t, time)
      else
        drawZone(t, teamColor(map, t.team), time)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- World: over everyone -------------------------------------------------------

--- The gun on top: a mount, the barrel pointing where it aims, the team's
--- light; a bar when it is hurt, a white flash when it is hit, a shield
--- while another tower covers it, and a red "!" while it has someone.
local function drawGun(t, c, covered, time)
  local x, y, h = t.x, t.y, Towers.SIZE / 2
  local fx, fy = math.cos(t.daim), math.sin(t.daim)
  love.graphics.setColor(0, 0, 0, 0.35)
  love.graphics.circle("fill", x + 2, y + 2, 11, 16)
  love.graphics.setColor(0.2, 0.2, 0.22)
  love.graphics.circle("fill", x, y, 10, 16)
  love.graphics.setLineWidth(5)
  love.graphics.line(x, y, x + fx * 27, y + fy * 27)
  love.graphics.setLineWidth(2)
  love.graphics.setColor(BRASS)
  love.graphics.line(x + fx * 6, y + fy * 6, x + fx * 22, y + fy * 22)
  love.graphics.setColor(c)
  love.graphics.circle("fill", x, y, 4, 10)
  love.graphics.setLineWidth(1)
  if t.flash > 0 then
    love.graphics.setColor(1, 1, 1, math.min(1, t.flash * 3))
    love.graphics.rectangle("fill", x - h, y - h, Towers.SIZE, Towers.SIZE, 4)
  end
  if t.hp < t.max then
    local bw, f = 44, math.max(0, t.hp / t.max)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + h + 3, bw + 2, 6)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + h + 4, bw * f, 4)
  end
  if covered then
    local sx, sy = x + h - 4, y - h - 4
    love.graphics.setColor(0, 0, 0, 0.5)
    love.graphics.rectangle("fill", sx - 5, sy - 6, 12, 14, 3)
    love.graphics.setColor(COVER)
    love.graphics.rectangle("line", sx - 5, sy - 6, 12, 14, 3)
    love.graphics.rectangle("fill", sx - 2, sy - 1, 6, 5)
  end
  if t.alert then
    local bob = math.sin(time * 10 + t.id) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - h - 32 + bob, 40, "center")
    love.graphics.setColor(ALERT)
    love.graphics.printf("!", x - 20, y - h - 33 + bob, 40, "center")
  end
end

--- A soldier from above in his side's colours: helmet, shoulders, rifle
--- out front; a bar when hurt, a red "!" over anyone who has you in his
--- sights.
local function drawSoldier(s, c, time)
  local x, y, r = s.dx, s.dy, SOLDIER_RADIUS
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local uniform, dark, helmet = shade(c, 0.75), shade(c, 0.5), shade(c, 0.35)
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(RIFLE)
  love.graphics.setLineWidth(3)
  love.graphics.line(x + fx * 2 - fy * 3, y + fy * 2 + fx * 3, x + fx * (r + 11) - fy * 3, y + fy * (r + 11) + fx * 3)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(dark)
  love.graphics.ellipse("fill", x, y, r + 1, r + 1)
  love.graphics.setColor(uniform)
  love.graphics.circle("fill", x - fy * (r - 1), y + fx * (r - 1), 3, 8)
  love.graphics.circle("fill", x + fy * (r - 1), y - fx * (r - 1), 3, 8)
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 5 - fy * 3, y + fy * 5 + fx * 3, 2, 6) -- the hand on the rifle
  love.graphics.setColor(helmet)
  love.graphics.circle("fill", x, y, r - 1.5, 12)
  love.graphics.setColor(shade(c, 0.5))
  love.graphics.circle("fill", x - fx - fy, y - fy + fx, r - 4, 10)
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(ALERT)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < 40 then
    local bw, f = 20, math.max(0, s.hp / 40)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

--- A simp from above in his side's hoodie: a head, arms swinging as he
--- runs, a fist out front while a punch lands; a bar once hurt, a red "!"
--- while he has someone.
local function drawSimp(s, c, time)
  local x, y, r = s.dx, s.dy, SIMP_RADIUS
  local fx, fy = math.cos(s.angle), math.sin(s.angle)
  local swing = math.sin(time * 12 + s.bob) * (s.alert and 1.6 or 0.8)
  local sx, sy = -fy * swing, fx * swing
  love.graphics.setColor(0, 0, 0, 0.3)
  love.graphics.circle("fill", x + 2, y + 2, r, 10)
  love.graphics.setColor(SKIN)
  if s.swing then
    love.graphics.circle("fill", x + fx * (r + 6), y + fy * (r + 6), 2.4, 6) -- the fist
  end
  love.graphics.circle("fill", x - fy * (r + 1) - sx, y + fx * (r + 1) - sy, 2, 6)
  love.graphics.circle("fill", x + fy * (r + 1) + sx, y - fx * (r + 1) + sy, 2, 6)
  love.graphics.setColor(shade(c, 0.8))
  love.graphics.circle("fill", x + sx * 0.5, y + sy * 0.5, r, 10)
  love.graphics.setColor(shade(c, 0.55))
  love.graphics.circle("fill", x - fx * 2, y - fy * 2, r - 2, 8) -- the hood
  love.graphics.setColor(SKIN)
  love.graphics.circle("fill", x + fx * 2, y + fy * 2, 3.2, 8)
  if s.alert then
    local bob = math.sin(time * 10 + s.bob) * 1.5
    love.graphics.setFont(UI.fonts.heading)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.printf("!", x - 19, y - r - 30 + bob, 40, "center")
    love.graphics.setColor(ALERT)
    love.graphics.printf("!", x - 20, y - r - 31 + bob, 40, "center")
  end
  if s.hp < 40 then
    local bw, f = 20, math.max(0, s.hp / 40)
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", x - bw / 2 - 1, y + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", x - bw / 2, y + r + 4, bw * f, 2)
  end
end

function Render.above(TW, map, camera, time)
  for _, t in ipairs(TW.list) do
    if not t.down and onScreen(camera, t.x, t.y, 60) then
      drawGun(t, teamColor(map, t.team), Towers.coveredIn(TW.list, t) ~= nil, time)
    end
  end
  for _, s in pairs(TW.troops) do
    if onScreen(camera, s.dx, s.dy, 60) then
      if s.kind == "soldier" then
        drawSoldier(s, teamColor(map, s.team), time)
      else
        drawSimp(s, teamColor(map, s.team), time)
      end
    end
  end
  love.graphics.setColor(1, 1, 1)
end

-- HUD -----------------------------------------------------------------------

--- The line under the quest's: towers standing a side, which side I am
--- on and the shop key; a notice (a covered tower, a tower down) centred
--- low.
function Render.hud(TW, map, myTeam, notice, noticeTimer, shopKey)
  local w, h = love.graphics.getDimensions()
  local font = UI.fonts.small
  love.graphics.setFont(font)
  local x, y = 10, 210
  local function word(text, color)
    UI.label(text, x, y, color)
    x = x + font:getWidth(text)
  end
  word("Turf war:  ", { 0.85, 0.85, 0.9 })
  for team = 1, 2 do
    local standing, total = 0, 0
    for _, t in ipairs(TW.list) do
      if t.team == team then
        total = total + 1
        standing = standing + (t.down and 0 or 1)
      end
    end
    word(("%s %d/%d towers   "):format(map.teams[team].name, standing, total), teamColor(map, team))
  end
  if myTeam then
    word("You: " .. map.teams[myTeam].name .. "   ", teamColor(map, myTeam))
  end
  if shopKey then
    word(shopKey .. ": shop", { 0.6, 0.6, 0.65 })
  end
  if notice and noticeTimer > 0 then
    local a = math.min(1, noticeTimer * 2)
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(0, 0, 0, 0.6 * a)
    love.graphics.printf(notice, 1, h - 129, w, "center")
    love.graphics.setColor(1, 0.85, 0.3, a)
    love.graphics.printf(notice, 0, h - 130, w, "center")
  end
  love.graphics.setColor(1, 1, 1)
end

--- Towers and vaults on the minimap, in their side's colour; a tower that
--- is down goes dark.
function Render.minimap(TW, map, toMap)
  for _, s in pairs(TW.troops) do
    local px, py = toMap(s.dx, s.dy)
    love.graphics.setColor(teamColor(map, s.team))
    love.graphics.circle("fill", px, py, 1.5, 6)
  end
  for _, t in ipairs(TW.list) do
    local px, py = toMap(t.x, t.y)
    if t.down then
      love.graphics.setColor(RUBBLE_DARK)
    else
      love.graphics.setColor(teamColor(map, t.team))
    end
    love.graphics.rectangle("fill", px - 2, py - 2, 4, 4)
  end
  for _, b in ipairs(map.bases) do
    local px, py = toMap(b.vault.x, b.vault.y)
    love.graphics.setColor(0, 0, 0, 0.8)
    love.graphics.rectangle("fill", px - 4, py - 4, 8, 8)
    love.graphics.setColor(teamColor(map, b.team))
    love.graphics.rectangle("fill", px - 3, py - 3, 6, 6)
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
