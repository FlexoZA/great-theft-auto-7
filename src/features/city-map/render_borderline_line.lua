-- The Assembly Line's factory floor (borderline.lua's `assembly`,
-- borderline_assembly.lua), drawn into the map's canvas by
-- render_borderline.lua: the belts (their parts ride them live: the
-- borderline feature's works.lua), the welding arms' bases (the arms swing
-- live too), the presses, the paint booths, the stairs up to the Foreman's
-- floor and the step along its edge, racks of hauler parts, parts carts,
-- the Fabricators' pads (the machines are live: fabricators.lua). Each is a
-- `DRAW[kind](s)` for a thing of `map.cover`, the same as the rest.

local Kit = require("src.features.city-map.render_borderline_kit")

local Line = {}

local INK, C = Kit.INK, Kit.C
local color, hash, lengthwise = Kit.color, Kit.hash, Kit.lengthwise
local box, blob, hazard = Kit.box, Kit.blob, Kit.hazard

local DRAW = {}
Line.DRAW = DRAW

local RUBBER = { 0.14, 0.14, 0.16 }

--- A belt: its steel frame either side, hazard paint along the frame's
--- top, the rubber between with cleats across it pointing the way it runs
--- (`dir`), the rollers showing at its ends, a drive motor at the end it
--- runs to.
function DRAW.belt(s)
  local east = s.dir ~= "w"
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  color(RUBBER)
  love.graphics.rectangle("fill", s.x, s.y + 14, s.w, s.h - 28)
  color(C.gunmetal) -- the cleats, chevrons pointing the way it goes
  local sign = east and 1 or -1
  for a = 24, s.w - 24, 48 do
    local x = s.x + a
    love.graphics.polygon("fill", x - sign * 8, s.y + 20, x + sign * 8, s.y + s.h / 2, x - sign * 8, s.y + s.h - 20,
      x - sign * 2, s.y + s.h / 2)
  end
  color(C.white, 0.08) -- the sheen down the middle
  love.graphics.rectangle("fill", s.x, s.y + s.h / 2 - 3, s.w, 6)
  hazard(s.x, s.y, s.w, 8)
  hazard(s.x, s.y + s.h - 8, s.w, 8)
  color(INK, 0.5) -- the frame's bolts
  for a = s.x + 16, s.x + s.w - 8, 64 do
    love.graphics.circle("fill", a, s.y + 11, 2.5, 6)
    love.graphics.circle("fill", a, s.y + s.h - 11, 2.5, 6)
  end
  for _, ex in ipairs({ s.x - 12, s.x + s.w }) do -- the end rollers
    box(ex, s.y + 10, 12, s.h - 20, C.steel)
  end
  local mx = east and s.x + s.w + 14 or s.x - 54 -- the drive motor
  box(mx, s.y + s.h / 2 - 22, 40, 44, C.yellow)
  color(C.gunmetal)
  for k = 0, 3 do
    love.graphics.rectangle("fill", mx + 6 + k * 8, s.y + s.h / 2 - 16, 4, 32)
  end
end

--- A welding arm's base, bolted to the floor: a yellow pedestal, its
--- bolts round it, the turntable, cables running off to the side (the arm
--- itself swings and welds: borderline/works.lua).
function DRAW.arm(s)
  local cx, cy = s.x + s.w / 2, s.y + s.h / 2
  color(INK, 0.7) -- the cables
  love.graphics.setLineWidth(4)
  love.graphics.line(cx, cy, cx + s.w * 0.9, cy + s.h * 0.3)
  love.graphics.setLineWidth(1)
  blob(s.x, s.y, s.w, s.h, C.yellow)
  color(C.yellowDark)
  love.graphics.circle("line", cx, cy, s.w * 0.4, 16)
  color(INK)
  for k = 0, 5 do
    local a = k / 6 * math.pi * 2
    love.graphics.circle("fill", cx + math.cos(a) * s.w * 0.4, cy + math.sin(a) * s.h * 0.4, 2, 6)
  end
  blob(cx - s.w * 0.22, cy - s.h * 0.22, s.w * 0.44, s.h * 0.44, C.gunmetal)
end

--- A stamping press: four columns at its corners, the crown over them
--- across the top, the bed with its die between, hazard paint round the
--- bed, light curtains (red posts) at the front.
function DRAW.press(s)
  box(s.x, s.y, s.w, s.h, C.steel)
  color(C.gunmetal) -- the bed and the die
  love.graphics.rectangle("fill", s.x + 26, s.y + 22, s.w - 52, s.h - 44)
  color(C.gunmetalLight)
  love.graphics.rectangle("fill", s.x + 36, s.y + 32, s.w - 72, s.h - 64)
  hazard(s.x, s.y, s.w, 10)
  hazard(s.x, s.y + s.h - 10, s.w, 10)
  for _, cx in ipairs({ s.x + 4, s.x + s.w - 22 }) do -- the columns
    for _, cy in ipairs({ s.y + 4, s.y + s.h - 22 }) do
      box(cx, cy, 18, 18, C.gunmetal)
    end
  end
  color({ 0.85, 0.15, 0.12 }) -- the light curtain's posts
  love.graphics.rectangle("fill", s.x + 26, s.y + s.h - 6, 6, 10)
  love.graphics.rectangle("fill", s.x + s.w - 32, s.y + s.h - 6, 6, 10)
end

--- A paint booth: white panel walls, the open end facing the line, a
--- hauler shell inside half painted yellow, overspray round it, the
--- extractor fan on its roof.
function DRAW.booth(s)
  local h = hash(s.seed or 1)
  box(s.x, s.y, s.w, s.h, C.white)
  color(INK, 0.15) -- the panels
  for a = s.x + 32, s.x + s.w - 8, 32 do
    love.graphics.rectangle("fill", a, s.y, 2, s.h)
  end
  color(C.gunmetal) -- the open end
  love.graphics.rectangle("fill", s.x + 10, s.y + s.h - 20, s.w - 20, 20)
  color(C.yellow, 0.35) -- overspray
  love.graphics.ellipse("fill", s.x + s.w / 2, s.y + s.h * 0.55, s.w * 0.36, s.h * 0.3, 18)
  local sx, sy = s.x + s.w / 2 - 22, s.y + s.h * 0.35 -- the shell, half done
  box(sx, sy, 44, 34, C.gunmetalLight)
  color(C.yellow)
  love.graphics.rectangle("fill", sx, sy, 44 * (0.3 + 0.6 * h), 34)
  blob(s.x + s.w - 44, s.y + 10, 30, 30, C.steel) -- the fan
  color(INK)
  love.graphics.line(s.x + s.w - 29, s.y + 14, s.x + s.w - 29, s.y + 36)
  love.graphics.line(s.x + s.w - 40, s.y + 25, s.x + s.w - 18, s.y + 25)
end

--- Steel stairs up to the Foreman's floor: treads, each lit along its
--- nose, handrails either side.
function DRAW.stairs(s)
  color(C.gunmetal)
  love.graphics.rectangle("fill", s.x, s.y, s.w, s.h)
  for y = s.y + 4, s.y + s.h - 10, 14 do
    color(C.steel)
    love.graphics.rectangle("fill", s.x + 8, y, s.w - 16, 10)
    color(C.yellow) -- the nose of each tread
    love.graphics.rectangle("fill", s.x + 8, y + 8, s.w - 16, 2)
  end
  for _, rx in ipairs({ s.x, s.x + s.w - 6 }) do
    color(INK)
    love.graphics.rectangle("fill", rx, s.y, 6, s.h)
  end
end

--- The step along the Foreman's floor: a steel edge up a step from the
--- line, hazard paint along its lip, the handrail's posts.
function DRAW.step(s)
  box(s.x, s.y, s.w, s.h, C.gunmetalLight)
  hazard(s.x, s.y + s.h - 8, s.w, 8)
  color(INK)
  for a = s.x + 20, s.x + s.w - 10, 64 do
    love.graphics.rectangle("fill", a, s.y + 2, 6, 6)
  end
end

--- A rack of hauler parts along a wall: steel shelves, on each a torso
--- (its eye not lit yet), a pair of legs or an arm.
function DRAW.rack(s)
  local h = hash(s.seed or 1)
  lengthwise(s, function(L, W)
    box(-L / 2, -W / 2, L, W, C.gunmetal)
    color(C.gunmetalLight) -- the uprights
    for a = -L / 2, L / 2 - 4, 64 do
      love.graphics.rectangle("fill", a, -W / 2, 4, W)
    end
    for k = 0, math.floor(L / 64) - 1 do
      local x = -L / 2 + 10 + k * 64
      local kind = math.floor((h * 10 + k) % 3)
      if kind == 0 then -- a torso
        box(x, -W / 2 + 10, 40, W - 20, C.yellow)
        color(C.gunmetal)
        love.graphics.circle("fill", x + 30, 0, 5, 8)
      elseif kind == 1 then -- legs
        box(x + 4, -W / 2 + 12, 12, W - 24, C.gunmetalLight)
        box(x + 24, -W / 2 + 12, 12, W - 24, C.gunmetalLight)
      else -- an arm
        box(x, -6, 40, 12, C.yellowDark)
      end
    end
  end)
end

--- A parts cart: a steel tray on castors, a torso and some plates in it,
--- its handle.
function DRAW.cart(s)
  local h = hash(s.seed or 1)
  box(s.x, s.y, s.w, s.h, C.steel)
  color(C.gunmetal)
  love.graphics.rectangle("fill", s.x + 5, s.y + 5, s.w - 10, s.h - 10)
  box(s.x + 8, s.y + 8, s.w * 0.45, s.h - 16, h < 0.5 and C.yellow or C.gunmetalLight)
  color(INK) -- the handle
  love.graphics.rectangle("fill", s.x + s.w, s.y + 6, 6, s.h - 12)
end

--- A Fabricator's pad: concrete inset in the floor, a hazard border, its
--- number painted at the foot (the machine on it is live: fabricators.lua).
function DRAW.fabpad(s)
  box(s.x, s.y, s.w, s.h, C.concreteDark)
  hazard(s.x, s.y, s.w, 14)
  hazard(s.x, s.y + s.h - 14, s.w, 14)
  hazard(s.x, s.y, 14, s.h)
  hazard(s.x + s.w - 14, s.y, 14, s.h)
  color(INK, 0.2) -- oil soaked into it
  love.graphics.ellipse("fill", s.x + s.w * 0.6, s.y + s.h * 0.55, s.w * 0.25, s.h * 0.18, 16)
  color(C.yellow)
  love.graphics.setFont(Kit.signFont())
  love.graphics.printf("FAB " .. (s.n or 1), s.x, s.y + s.h - 34, s.w, "center")
end

return Line
