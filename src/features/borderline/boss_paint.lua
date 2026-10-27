-- How the line's bosses are painted (wilbur_look.lua, scrapper_look.lua):
-- the haulers' flat colours (hauler_look.lua's), with the heavier black
-- outline a boss gets so it stands out from the army round it.

local Hauler = require("src.features.borderline.hauler_look")

local Paint = {}

local C = Hauler.C

function Paint.color(c, a)
  love.graphics.setColor(c[1], c[2], c[3], a or c[4] or 1)
end

--- A filled rounded box with the black outline round it.
function Paint.plate(x, y, w, h, fill, r)
  Paint.color(C.ink)
  love.graphics.rectangle("fill", x - 1.5, y - 1.5, w + 3, h + 3, (r or 2) + 1.5)
  Paint.color(fill)
  love.graphics.rectangle("fill", x, y, w, h, r or 2)
end

function Paint.disc(x, y, r, fill)
  Paint.color(C.ink)
  love.graphics.circle("fill", x, y, r + 1.5, 20)
  Paint.color(fill)
  love.graphics.circle("fill", x, y, r, 20)
end

--- A soft light added over what's under it.
function Paint.glow(c, a, x, y, r)
  love.graphics.setBlendMode("add")
  love.graphics.setColor(c[1], c[2], c[3], a)
  love.graphics.circle("fill", x, y, r, 18)
  love.graphics.setBlendMode("alpha")
end

--- A lane lit on the floor ahead of a boss's move (the Smelter's gush, the
--- Foreman's charge): from (x, y) along `angle`, `length` long and `width`
--- across, red, its edges throbbing faster as `k` (0..1) runs out, arrows
--- down it.
function Paint.lane(x, y, angle, length, width, k, clock)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  local hw = width / 2
  love.graphics.setColor(1, 0.25, 0.15, 0.1 + 0.15 * k)
  love.graphics.rectangle("fill", 0, -hw, length, width)
  love.graphics.setColor(1, 0.25, 0.15, 0.5 + 0.4 * math.sin(clock * (8 + 20 * k)))
  love.graphics.setLineWidth(3)
  love.graphics.rectangle("line", 0, -hw, length, width)
  love.graphics.setLineWidth(1)
  love.graphics.setColor(1, 0.25, 0.15, 0.4)
  for a = 40, length - 20, 60 do
    love.graphics.polygon("fill", a, -hw * 0.4, a + 22, 0, a, hw * 0.4)
  end
  love.graphics.pop()
end

return Paint
