-- The boss bar every boss shares on the HUD: its name over a health bar
-- above the ability circles, and its breath as a thin bar under that,
-- throbbing red with "winded" beside it while the boss is blown.
--
--   Bar.draw({
--     title = "CRAZY KAREN", titleColor = { 1, 0.55, 0.75 }, fill = { 0.9, 0.2, 0.45 },
--     hp = b.hp, max = b.max, stamina = b.stamina, staminaMax = 100, winded = b.winded,
--   })

local UI = require("src.ui")

local Bar = {}

Bar.width = 380
Bar.height = 14
Bar.bottom = 150 -- px up from the bottom edge: above the magazine line and the ability circles
Bar.breathHeight = 5

function Bar.draw(spec)
  local w, h = love.graphics.getDimensions()
  local bw, bh = Bar.width, Bar.height
  local bx, by = math.floor((w - bw) / 2), h - Bar.bottom
  love.graphics.setFont(UI.fonts.small)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.printf(spec.title, 1, by - 19, w, "center")
  love.graphics.setColor(spec.titleColor)
  love.graphics.printf(spec.title, 0, by - 20, w, "center")
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 2, by - 2, bw + 4, bh + 4, 3)
  local f = math.max(0, math.min(1, (spec.hp or 0) / math.max(1, spec.max or 1)))
  love.graphics.setColor(spec.fill)
  love.graphics.rectangle("fill", bx, by, bw * f, bh, 2)
  love.graphics.setColor(1, 1, 1, 0.5)
  love.graphics.rectangle("line", bx, by, bw, bh, 2)

  -- Its breath: so you can see when to run, and when it is about to.
  local sh, sy = Bar.breathHeight, by + bh + 4
  local sf = math.max(0, math.min(1, (spec.stamina or 0) / math.max(1, spec.staminaMax or 100)))
  love.graphics.setColor(0, 0, 0, 0.65)
  love.graphics.rectangle("fill", bx - 2, sy - 2, bw + 4, sh + 4, 2)
  if spec.winded then
    love.graphics.setColor(0.9, 0.3, 0.3, 0.45 + 0.25 * math.sin(love.timer.getTime() * 8))
  else
    love.graphics.setColor(0.45, 0.75, 1)
  end
  love.graphics.rectangle("fill", bx, sy, bw * sf, sh, 1)
  if spec.winded then
    love.graphics.setColor(1, 0.5, 0.45)
    love.graphics.printf("winded", bx + bw + 8, sy - 5, 80, "left")
  end
  love.graphics.setColor(1, 1, 1)
end

return Bar
