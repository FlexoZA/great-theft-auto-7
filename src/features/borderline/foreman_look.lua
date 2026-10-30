-- How Foreman BIG-B055 looks (docs/borderline.md, "The bosses"): the
-- haulers' body in its own kit (hauler_look.lua's FMN: the badass that runs
-- the line, 2.2x, black and gold, a hard hat welded on, twin war cannons),
-- one cannon gone once it has torn it off (`Look.ripped`, kept by
-- foreman.lua), and the cannon it threw aside, lying where it fell.
--
--   Look.draw(h, clock)          h: { dx, dy, facing, stride, charge, flash }
--   Look.drawWreck(w, clock)     where it went down: w { x, y, angle }
--   Look.drawCannon(x, y, angle) the torn-off cannon on the floor

local Hauler = require("src.features.borderline.hauler_look")
local Paint = require("src.features.borderline.boss_paint")

local Look = {}

Look.ripped = false -- on this screen (foreman.lua)

local C = Hauler.C

function Look.draw(h, clock)
  Hauler.draw({ dx = h.dx, dy = h.dy, facing = h.facing, code = "FMN", stride = h.stride, charge = h.charge,
    flash = h.flash, ripped = Look.ripped }, clock)
end

function Look.drawWreck(w, clock)
  Hauler.drawWreck({ x = w.x, y = w.y, angle = w.angle, code = "FMN", ripped = true }, clock)
end

--- Its cannon, torn off: the barrel, the gold muzzle, the shoulder's
--- wiring hanging out of the end.
function Look.drawCannon(x, y, angle)
  love.graphics.push()
  love.graphics.translate(x, y)
  love.graphics.rotate(angle)
  Paint.plate(-18, -7, 36, 14, C.gunmetal, 3)
  Paint.plate(14, -8.5, 8, 17, C.gold, 2)
  Paint.color(C.ink)
  love.graphics.rectangle("fill", 18, -2.5, 6, 5)
  Paint.color(C.eye, 0.8)
  love.graphics.setLineWidth(1.5)
  love.graphics.line(-18, -3, -25, -6)
  love.graphics.line(-18, 3, -24, 7)
  love.graphics.setLineWidth(1)
  love.graphics.pop()
  love.graphics.setColor(1, 1, 1)
end

return Look
