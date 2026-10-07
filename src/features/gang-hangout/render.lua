-- Drawing the Gang Hangout and its guards. The building is in the look of
-- the others (buildings/render.lua's parts): a tarred roof behind its
-- parapet, the name on a plate, a tag sprayed across the roof in the
-- boss's colour, and out front a yard with a burning barrel and a beaten
-- sofa. The guards are the core's person (src/body.lua) in their crew's
-- look (crews.lua), thugs wearing their boss's colour.

local UI = require("src.ui")
local Body = require("src.body")
local Car = require("src.car")
local Crews = require("src.features.gang-hangout.crews")
local Parts = require("src.features.buildings.render").parts

local Render = {}

local ROOF = { 0.24, 0.22, 0.23 }
local YARD = { 0.38, 0.36, 0.33 }
local LENS = { 0.45, 0.85, 1.00 }
local LENS_ALERT = { 1.00, 0.45, 0.20 }
local GREY = { 0.75, 0.75, 0.75 }

--- The hangout filling `r` ({ x, y, w, h }), `owner` the boss's id (nil on
--- the build screen's card), `t` the time for the fire.
function Render.building(r, owner, t)
  local P = Parts
  local color = owner and Car.colorFor(owner) or GREY
  local yard = math.min(46, r.h * 0.3)
  P.slabs(r.x, r.y, r.w, r.h, YARD, 28)
  local hx, hy, hw, hh = r.x + 6, r.y + 6, r.w - 12, r.h - yard - 6
  P.roof(hx, hy, hw, hh, ROOF)
  P.aircon(hx + 24, hy + 24, t)

  -- The tag: a few fat strokes in the boss's colour, sprayed over the tar.
  love.graphics.setColor(color[1], color[2], color[3], 0.85)
  love.graphics.setLineWidth(6)
  local cx, cy, s = hx + hw * 0.62, hy + hh * 0.42, math.min(hw, hh) * 0.22
  love.graphics.line(cx - s * 1.6, cy + s * 0.4, cx - s * 0.8, cy - s * 0.6, cx - s * 0.2, cy + s * 0.5,
    cx + s * 0.6, cy - s * 0.7, cx + s * 1.5, cy + s * 0.2)
  love.graphics.circle("fill", cx + s * 1.7, cy + s * 0.6, 4)
  love.graphics.setLineWidth(1)
  P.namePlate(hx + hw / 2, hy + hh * 0.78, "HANGOUT", color, UI.fonts.body)

  -- The yard out front: the door, a sofa and a barrel with a fire in it.
  local front = hy + hh
  love.graphics.setColor(0.1, 0.08, 0.07)
  love.graphics.rectangle("fill", hx + hw / 2 - 12, front - 4, 24, 6)
  local sx, sy = hx + 30, front + yard * 0.45
  love.graphics.setColor(0.45, 0.2, 0.18)
  love.graphics.rectangle("fill", sx, sy - 6, 44, 14, 3)
  love.graphics.setColor(0.36, 0.15, 0.13)
  love.graphics.rectangle("fill", sx, sy - 10, 44, 6, 2)
  local bx, by = hx + hw - 34, front + yard * 0.5
  love.graphics.setColor(0.3, 0.3, 0.32)
  love.graphics.circle("fill", bx, by, 9)
  local flicker = 0.75 + 0.25 * math.sin(t * 13) * math.sin(t * 7.3)
  love.graphics.setColor(1, 0.55, 0.12, 0.9)
  love.graphics.circle("fill", bx, by, 6 * flicker)
  love.graphics.setColor(1, 0.9, 0.4, 0.9)
  love.graphics.circle("fill", bx, by, 3 * flicker)
  love.graphics.setColor(1, 1, 1)
end

--- The hangout's mark on the big map, at (0, 0), drawn about 50 px across:
--- a spray can.
function Render.mark()
  love.graphics.setColor(0.85, 0.2, 0.25)
  love.graphics.rectangle("fill", -9, -12, 18, 28, 3)
  love.graphics.setColor(0.95, 0.95, 0.95)
  love.graphics.rectangle("fill", -5, -19, 10, 7, 2)
  love.graphics.setColor(0.15, 0.15, 0.15)
  love.graphics.rectangle("fill", -9, -2, 18, 6)
end

local looks = {} -- crew level .. ":" .. owner -> the crew's look in that boss's colour

local function lookFor(crew, owner)
  if not crew.look.colors then
    return crew.look
  end
  local key = crew.level .. ":" .. tostring(owner)
  local look = looks[key]
  if not look then
    look = {}
    for k, v in pairs(crew.look) do
      look[k] = v
    end
    look.hat = Car.colorFor(owner or 0) -- a bandana in the boss's colour
    looks[key] = look
  end
  return look
end

--- One guard, `g` as the client keeps it: { dx, dy, angle, level, hp, mode, owner, bob }.
function Render.guard(g, t)
  local crew = Crews.at(g.level)
  local look = lookFor(crew, g.owner)
  local moving = g.mode ~= "post"
  local swing = moving and math.sin(t * 12 + g.bob) * 1.2 or 0
  Body.person(g.dx, g.dy, g.angle, swing, look)
  if crew.look.lenses then
    love.graphics.push()
    love.graphics.translate(g.dx, g.dy)
    love.graphics.rotate(g.angle)
    love.graphics.setColor(g.mode == "fight" and LENS_ALERT or LENS)
    love.graphics.circle("fill", 3.4, -1.5, 1.1, 6)
    love.graphics.circle("fill", 3.4, 1.5, 1.1, 6)
    love.graphics.pop()
  end
  -- A dot in the boss's colour at his shoulder, so you can tell whose he is.
  local c = Car.colorFor(g.owner or 0)
  local fx, fy = math.cos(g.angle), math.sin(g.angle)
  love.graphics.setColor(0, 0, 0, 0.6)
  love.graphics.circle("fill", g.dx + fy * 6 - fx * 2, g.dy - fx * 6 - fy * 2, 2.6, 8)
  love.graphics.setColor(c[1], c[2], c[3])
  love.graphics.circle("fill", g.dx + fy * 6 - fx * 2, g.dy - fx * 6 - fy * 2, 2, 8)
  if g.hp < crew.health then
    local bw, f, r = 20, math.max(0, g.hp / crew.health), Body.SHOULDERS
    love.graphics.setColor(0, 0, 0, 0.6)
    love.graphics.rectangle("fill", g.dx - bw / 2 - 1, g.dy + r + 3, bw + 2, 4)
    love.graphics.setColor(1 - f, f, 0.2)
    love.graphics.rectangle("fill", g.dx - bw / 2, g.dy + r + 4, bw * f, 2)
  end
  love.graphics.setColor(1, 1, 1)
end

return Render
