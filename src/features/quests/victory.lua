-- The victory screen: the job is done and this is how you did. Laid out like
-- the bosses' intro screens (a column on the left with a small heading, a
-- big title and a line under it; the picture big on the right): a star in
-- the job's colour over slow turning rays, and the numbers in a box where
-- the boss's words would be. It is what the star home offers once the job
-- is done (Enter goes home, Backspace stays to pick things up), and what
-- everyone else sees on getting home when somebody else took them (any
-- key puts it away).
--
--   Victory.draw(spec, t, time, fillStar)
--
-- `spec` is { title, color, stats, hint, level }: `stats` as QST_STATS left
-- them (nil before any arrived), `hint` the line at the bottom, `level` the
-- level the job was done at (named by Jobs.levelName; nil: no line). `t` is how long
-- the screen has been up, `time` the clock for the rays; `fillStar(cx, cy, R)`
-- is the quests feature's star.

local UI = require("src.ui")
local Video = require("src.video")
local Jobs = require("src.features.quests.jobs")

local Victory = {}

Victory.minTime = 0.6 -- seconds before a key does anything (no going home by accident)

--- "4:07", or "1:02:09" past the hour.
function Victory.clock(seconds)
  seconds = math.max(0, math.floor(seconds or 0))
  local h, m, s = math.floor(seconds / 3600), math.floor(seconds / 60) % 60, seconds % 60
  if h > 0 then
    return ("%d:%02d:%02d"):format(h, m, s)
  end
  return ("%d:%02d"):format(m, s)
end

--- The rows of the box: { label, value }.
function Victory.rows(stats)
  stats = stats or {}
  local rows = {
    { "Time", Victory.clock(stats.time) },
    { "Enemies killed", tostring(stats.kills or 0) },
    { "Bosses beaten", tostring(stats.bosses or 0) },
    { "Deaths", tostring(stats.deaths or 0) },
    { "Fcks picked up", tostring(stats.koins or 0) },
  }
  local unlocks = stats.unlocks or {}
  rows[#rows + 1] = { "Unlocked", #unlocks > 0 and table.concat(unlocks, ", ") or "nothing new" }
  return rows
end

function Victory.draw(spec, t, time, fillStar)
  local w, h = love.graphics.getDimensions()
  local c = spec.color or { 1, 0.85, 0.3 }
  local appear = math.min(1, t / 0.3)
  local homeX, homeY = math.floor(w * 0.72), math.floor(h * 0.5)
  local radius = math.sqrt(w * w + h * h)

  love.graphics.setColor(c[1] * 0.08, c[2] * 0.08, c[3] * 0.08)
  love.graphics.rectangle("fill", 0, 0, w, h)
  local a0 = time * 0.1
  love.graphics.setColor(c[1] * 0.2, c[2] * 0.2, c[3] * 0.2)
  for i = 0, 17, 2 do
    local a1 = a0 + i / 18 * 2 * math.pi
    local a2 = a0 + (i + 1) / 18 * 2 * math.pi
    love.graphics.polygon("fill", homeX, homeY, homeX + math.cos(a1) * radius, homeY + math.sin(a1) * radius,
      homeX + math.cos(a2) * radius, homeY + math.sin(a2) * radius)
  end
  -- The star lands with a little bounce and breathes.
  local size = math.min(h * 0.26, w * 0.18)
  local pop = 1 + 0.3 * math.max(0, 1 - t / 0.45)
  local R = size * pop * (0.96 + 0.04 * math.sin(time * 2.5))
  love.graphics.setColor(c[1], c[2], c[3], 0.15)
  love.graphics.circle("fill", homeX, homeY, R * 1.25, 64)
  love.graphics.setColor(0, 0, 0, 0.4)
  fillStar(homeX + 8, homeY + 8, R)
  love.graphics.setColor(c)
  local outline = fillStar(homeX, homeY, R)
  love.graphics.setColor(c[1] * 0.45, c[2] * 0.45, c[3] * 0.45)
  love.graphics.setLineWidth(5)
  love.graphics.polygon("line", outline)
  love.graphics.setLineWidth(1)

  local colX, colW = math.floor(math.max(40, w * 0.07)), math.floor(w * 0.42)
  love.graphics.setColor(0, 0, 0, 0.5)
  love.graphics.rectangle("fill", 0, 0, colX + colW + 30, h)
  local y = math.floor(h * 0.1)
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(c)
  love.graphics.print("JOB DONE", colX, y)
  y = y + 26
  love.graphics.setFont(UI.fonts.title)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.print("VICTORY", colX + 3, y + 3)
  love.graphics.setColor(c[1], c[2], c[3], appear)
  love.graphics.print("VICTORY", colX, y)
  y = y + UI.fonts.title:getHeight() + 6
  love.graphics.setFont(UI.fonts.heading)
  love.graphics.setColor(1, 1, 1)
  love.graphics.printf(spec.title or "", colX, y, colW, "left")
  local _, tl = UI.fonts.heading:getWrap(spec.title or "", colW)
  y = y + #tl * UI.fonts.heading:getHeight() + 4
  if spec.level then -- the level it was done at, and what that level is called
    love.graphics.setFont(UI.fonts.body)
    love.graphics.setColor(c)
    love.graphics.print("LEVEL " .. spec.level .. "  -  " .. Jobs.levelName(spec.level), colX, y)
    y = y + UI.fonts.body:getHeight()
  end
  y = y + 26

  -- The numbers, one row each; what was unlocked wraps under its label.
  local font = UI.fonts.body
  local rows = Victory.rows(spec.stats)
  local inner = colW - 32
  local heights = {}
  local bh = 28
  for i, row in ipairs(rows) do
    local _, wl = font:getWrap(row[2], inner * 0.55)
    heights[i] = math.max(1, #wl) * font:getHeight() + 6
    bh = bh + heights[i]
  end
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.rectangle("fill", colX, y, colW, bh, 8)
  love.graphics.setColor(c[1], c[2], c[3], 0.7)
  love.graphics.setLineWidth(2)
  love.graphics.rectangle("line", colX, y, colW, bh, 8)
  love.graphics.setLineWidth(1)
  love.graphics.setFont(font)
  local ry = y + 14
  for i, row in ipairs(rows) do
    -- Rows count up into place one after another.
    local a = math.max(0, math.min(1, (t - 0.25 - i * 0.12) / 0.25))
    love.graphics.setColor(0.7, 0.72, 0.78, a)
    love.graphics.print(row[1], colX + 16, ry)
    love.graphics.setColor(1, 1, 1, a)
    love.graphics.printf(row[2], colX + 16 + inner * 0.45, ry, inner * 0.55, "right")
    ry = ry + heights[i]
  end
  if not spec.stats then
    love.graphics.setColor(0.7, 0.72, 0.78)
    love.graphics.printf("(counting...)", colX, y + bh + 8, colW, "center")
  end

  if t >= Victory.minTime then
    local pulse = 0.5 + 0.5 * math.sin(time * 3)
    love.graphics.setFont(UI.fonts.small)
    love.graphics.setColor(1, 1, 1, 0.5 + 0.35 * pulse)
    love.graphics.printf(spec.hint or "press any key", 0, h - 40, w, "center")
  end

  if Video.get("scanlines") then
    love.graphics.setColor(0, 0, 0, 0.18)
    for sy = 0, h, 4 do
      love.graphics.rectangle("fill", 0, sy, w, 1)
    end
  end
  love.graphics.setColor(1, 1, 1)
end

return Victory
